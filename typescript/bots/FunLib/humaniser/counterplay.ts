/**
 * Counter-play (task 07, Phase F): spotting enemy pulls, freezes, stacks and a missing or shoving enemy mid,
 * and the lane's answer to each. Fair by construction: the only inputs are LaneState.Enemies (perception-filtered
 * visible heroes plus GetHeroLastSeenInfo), visible creeps and neutrals, and public map data. Each bot notices a
 * signal instance at most once, with a skill-scaled chance; an unnoticed instance is remembered so it is not re-rolled.
 */
import { Lane, Team, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LanePlanner from "bots/FunLib/humaniser/lane_planner";
import * as LaneTech from "bots/FunLib/humaniser/lane_tech";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";
import * as Harass from "bots/FunLib/humaniser/harass";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as HDebug from "bots/FunLib/humaniser/debug";

export interface PullSignalInput {
    now: number;
    enemySupport: LaneState.LaneEnemy;
    campLoc: Vector;
    campPullSec: number[];
    campHalfSec?: number[];
}

export interface PullExpectedInput {
    now: number;
    /** Our lane's forecast eq mirrored to the enemy: the caller passes ours, this negates it. */
    forecastEq: number;
    enemyDesiredEq: number;
    pullSec: number[];
    supportInLane: boolean;
}

export type SignalKind = "pull" | "half_pull" | "freeze" | "stack" | "mid_missing" | "rune_shove" | "pull_expected";

export interface Signal {
    kind: SignalKind;
    lane: Lane;
    at: number;
    campIdx?: number;
    enemyPid?: number;
    /** pull_expected: when the predicted pull aggros the camp. */
    aggroAt?: number;
    noticed: boolean;
}

interface Punish {
    pid: number;
    startAt: number;
    lastAt?: number;
}

interface ObserverState {
    lastEval?: number;
    instances: Record<string, Signal>;
    responded: Record<string, boolean>;
    freezeKey?: string;
    waveCycle?: number;
    waveMax: number;
    punish?: Punish;
    stackAttack?: { pid: number; until: number; orderedAt?: number };
    /** Break-freeze / rune-shove answer: shove while that is safe, otherwise zone. */
    counterUntil?: number;
    runeContestUntil?: number;
    campBlockAt?: number;
    said: Record<string, number>;
}

const LANE_NAME: Record<number, string> = { [Lane.Top]: "top", [Lane.Mid]: "mid", [Lane.Bot]: "bot" };
const WARDS: Record<string, boolean> = { item_ward_sentry: true, item_ward_observer: true, item_ward_dispenser: true };
const INVENTORY_SLOTS = 6;

let observers: Record<number, ObserverState> = {};
// Hero positions are fixed for the game; read while visible, since PositionOf needs a unit handle.
let positions: Record<number, number> = {};
let marked: Record<number, Record<number, number>> = {};
let dropDenyUntil: Record<number, number> = {};
// "<team>:<lane>:<instance key>" of instances already telegraphed: two laners noticing one instance say it once.
let teamSaid: Record<string, boolean> = {};

export function ResetCache(): void {
    observers = {};
    positions = {};
    marked = {};
    dropDenyUntil = {};
    teamSaid = {};
}

function settings(): LaneConfig.LaneSettings {
    return LaneConfig.Settings();
}

function on(): boolean {
    return LaneConfig.IsOn("CounterPlay");
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function distToSegment(p: Vector, a: Vector, b: Vector): number {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len2 = dx * dx + dy * dy;
    if (len2 === 0) return dist2D(p, a);
    const t = math.max(0, math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
    return dist2D(p, Vector(a.x + t * dx, a.y + t * dy, 0));
}

function circularGap(a: number, b: number, period: number): number {
    const d = math.abs(a - b) % period;
    return math.min(d, period - d);
}

function enemyTeamOf(team: number): number {
    return team === Team.Radiant ? Team.Dire : Team.Radiant;
}

function cycleOf(time: number): number {
    return math.floor(time / settings().Timing.WaveCycle);
}

function isSupport(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 4;
}

function stronger(bot: Unit): boolean {
    const fn = LaneConfig.Helpers().WeAreStronger;
    return fn !== undefined && fn(bot, settings().Radii.Stronger);
}

function stateOf(pid: number): ObserverState {
    let st = observers[pid];
    if (st === undefined) {
        st = { instances: {}, responded: {}, waveMax: 0, said: {} };
        observers[pid] = st;
    }
    return st;
}

// ---------------------------------------------------------------------------------------------- pure signals

export function EnemyPullSuspected(i: PullSignalInput): boolean {
    const cfg = settings();
    const e = i.enemySupport;
    if (e.visible) return dist2D(e.location, i.campLoc) <= cfg.Radii.EnemyNearCamp;
    if (e.timeSinceSeen <= cfg.Timing.CounterUnseen || dist2D(e.location, i.campLoc) > cfg.Radii.PullCampLastSeen) return false;
    const period = cfg.Timing.WaveCycle;
    const sec = i.now % period;
    for (const s of [...i.campPullSec, ...(i.campHalfSec ?? [])]) {
        if (circularGap(sec, s % period, period) <= cfg.Timing.CounterPullWindow) return true;
    }
    return false;
}

/**
 * `visibleEnemyCreeps` is the most enemy creeps seen at the front so far this cycle: a wave already fighting
 * loses creeps, so the current count would read a normal wave as thin. Thin is judged once the wave has had
 * CounterWaveLate seconds to arrive in full.
 */
export function WaveAnomaly(cycleSec: number, expectedArrival: number | undefined, visibleEnemyCreeps: number, typicalSize: number): "late" | "thin" | undefined {
    if (expectedArrival === undefined) return undefined;
    const cfg = settings();
    const settled = expectedArrival + cfg.Timing.CounterWaveLate;
    if (visibleEnemyCreeps === 0) return cycleSec > settled ? "late" : undefined;
    if (cycleSec >= settled && visibleEnemyCreeps <= typicalSize - cfg.Thresholds.ThinWaveMargin) return "thin";
    return undefined;
}

export function FreezeSuspected(eqHistory: number[], enemyDeniesPerCycle: number[]): boolean {
    const cfg = settings();
    const n = eqHistory.length;
    const m = enemyDeniesPerCycle.length;
    if (n < 2 || m < 2) return false;
    for (let k = 1; k <= 2; k++) {
        if (eqHistory[n - k] < cfg.Thresholds.FreezeSuspectEq || enemyDeniesPerCycle[m - k] < cfg.Infer.FreezeDenies) return false;
    }
    return true;
}

/** The next aggro time at which the enemy support will want to pull, or undefined when it will not. */
export function EnemyPullExpected(i: PullExpectedInput): number | undefined {
    if (!i.supportInLane || i.pullSec.length === 0) return undefined;
    const cfg = settings();
    if (LaneState.LaneScore(i.enemyDesiredEq, -i.forecastEq, 0) > cfg.Planner.SmallDriftBelow) return undefined;
    const aggroAt = CampJobs.NextAggroTime(i.now, i.pullSec, cfg.Timing.PullPeriod);
    return CampJobs.CampsUp(aggroAt) ? aggroAt : undefined;
}

export function StackSuspected(secOfMinute: number, enemyNearCampVisible: boolean, neutralOutsideBoxVisible: boolean): boolean {
    const t = settings().Timing;
    if (enemyNearCampVisible && secOfMinute >= t.StackWatchFrom && secOfMinute <= t.StackWatchTo) return true;
    return neutralOutsideBoxVisible && secOfMinute >= 0 && secOfMinute <= t.StackOutsideUntil;
}

// ---------------------------------------------------------------------------------------------- noticing

function say(bot: Unit, st: ObserverState, key: string, instance: string): void {
    if (!LaneConfig.IsOn("Telegraph") || !Difficulty.IsAllyOfHuman(bot)) return;
    if (teamSaid[instance] === true) return;
    const cooldown = settings().Timing.CounterTelegraphCooldown;
    const last = st.said[key];
    if (last !== undefined && GameTime() - last < cooldown) return;
    if (Orders.Say(bot, key, cooldown)) {
        st.said[key] = GameTime();
        teamSaid[instance] = true;
    }
}

function visibleEnemy(enemies: LaneState.LaneEnemy[], pid: number | undefined): LaneState.LaneEnemy | undefined {
    if (pid === undefined) return undefined;
    for (const e of enemies) if (e.pid === pid && e.visible && e.unit !== undefined) return e;
    return undefined;
}

function mark(team: number, campIdx: number, now: number): void {
    let m = marked[team];
    if (m === undefined) {
        m = {};
        marked[team] = m;
    }
    m[campIdx] = now + settings().Timing.MarkedStackFor;
}

/** Answers that need no unit action happen at notice time, so they also work for bots outside laning Think. */
function onNotice(bot: Unit, st: ObserverState, key: string, sig: Signal, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], inferred: boolean): void {
    const cfg = settings();
    const now = DotaTime();
    const instance = `${s.team}:${s.lane}:${key}`;
    HDebug.Log("lane", `counter pid=${bot.GetPlayerID()} noticed=${sig.kind} lane=${sig.lane} camp=${sig.campIdx ?? "-"} enemy=${sig.enemyPid ?? "-"}`);
    if (sig.kind === "pull_expected") return;
    if (sig.kind === "pull" || sig.kind === "half_pull") {
        say(bot, st, inferred ? "say_lane_their_sup_missing" : `say_lane_they_pull_${LANE_NAME[sig.lane]}`, instance);
    } else if (sig.kind === "freeze") {
        say(bot, st, "say_lane_they_freeze", instance);
        if (!isSupport(bot)) return;
        st.counterUntil = (cycleOf(now) + 2) * cfg.Timing.WaveCycle;
    } else if (sig.kind === "stack") {
        const stacker = visibleEnemy(enemies, sig.enemyPid);
        // The attack is issued from laning Think; after laning the camp is marked instead.
        const canHit = LaneConfig.InLaningPhase() && stacker !== undefined && GetUnitToLocationDistance(bot, stacker.location) <= cfg.Radii.Stronger;
        if (canHit && stacker !== undefined && stronger(bot)) {
            st.stackAttack = { pid: stacker.pid, until: now + cfg.Timing.PunishFor };
        } else if (sig.campIdx !== undefined) {
            mark(s.team, sig.campIdx, now);
        }
    } else if (sig.kind === "mid_missing") {
        say(bot, st, "say_lane_ss_mid", instance);
        dropDenyUntil[s.team] = now + cfg.Timing.DropRangedDenyFor;
    } else if (sig.kind === "rune_shove") {
        const next = LaneConfig.Helpers().NextPowerRuneTime;
        const rune = next !== undefined ? next() : now;
        if (stronger(bot)) st.runeContestUntil = rune + cfg.Timing.RuneContestAfter;
        else st.counterUntil = rune;
    }
}

/** The notice roll is the only draw for a new instance (PF10 draw order). */
function observe(bot: Unit, st: ObserverState, key: string, sig: Omit<Signal, "noticed">, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], inferred = false): void {
    if (st.instances[key] !== undefined) return;
    const signal: Signal = { ...sig, noticed: LaneConfig.Roll(LaneConfig.Curve("CounterNotice", LaneConfig.SkillOf(bot))) };
    st.instances[key] = signal;
    if (signal.noticed) onNotice(bot, st, key, signal, s, enemies, inferred);
}

function prune(st: ObserverState, now: number): void {
    const forget = settings().Timing.CounterForgetAfter;
    for (const [key, sig] of pairs(st.instances)) {
        if (now - sig.at > forget && key !== st.freezeKey) {
            delete st.instances[key];
            delete st.responded[key];
        }
    }
}

function notePositions(enemies: LaneState.LaneEnemy[]): void {
    for (const e of enemies) {
        if (!e.visible || e.unit === undefined || positions[e.pid] !== undefined) continue;
        const pos = e.position ?? LaneConfig.PositionOf(e.unit);
        if (pos !== undefined) positions[e.pid] = pos;
    }
}

/** Known enemy of that position whose (last-seen) location is nearest the lane; never-seen enemies are unknown. */
function enemyAt(enemies: LaneState.LaneEnemy[], lane: Lane, wanted: (pos: number) => boolean): LaneState.LaneEnemy | undefined {
    let best: LaneState.LaneEnemy | undefined;
    let bestDist = math.huge;
    for (const e of enemies) {
        const pos = positions[e.pid];
        if (pos === undefined || !wanted(pos)) continue;
        const d = GetAmountAlongLane(lane, e.location).distance;
        if (d < bestDist) {
            best = e;
            bestDist = d;
        }
    }
    return best;
}

function suspectedCamp(camps: Camps.CampJobData[], support: LaneState.LaneEnemy, now: number): number | undefined {
    for (const camp of camps) {
        const spawner = Camps.SpawnerByIdx(camp.campIdx);
        if (spawner === undefined || camp.pull === undefined) continue;
        // The enemy's own wave-timed seconds (pull_timing), as our jobs use, else the seeds.
        const input = {
            now,
            enemySupport: support,
            campLoc: Camps.BoxCenter(spawner),
            campPullSec: PullTiming.ForCamp(camp, false).seconds,
            campHalfSec: PullTiming.ForCamp(camp, true).seconds,
        };
        if (EnemyPullSuspected(input)) return camp.campIdx;
    }
    return undefined;
}

/** Gate and skill are checked before observe so no notice roll is spent below the gate. */
function pullExpectedSignal(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], camp: Camps.CampJobData, support: LaneState.LaneEnemy | undefined, now: number): void {
    if (!LaneConfig.IsOn("PreContest") || LaneConfig.SkillOf(bot) < settings().Gates.PreContest || camp.pull === undefined) return;
    const aggroAt = EnemyPullExpected({
        now,
        forecastEq: s.forecastEq,
        enemyDesiredEq: LaneState.DesiredEq(LaneState.LaneKindOf(enemyTeamOf(s.team), s.lane), false),
        pullSec: PullTiming.ForCamp(camp, false).seconds,
        supportInLane: support !== undefined && isLaner(support, s),
    });
    if (aggroAt === undefined) return;
    const key = `pexp:${camp.campIdx}:${math.floor(aggroAt / settings().Timing.WaveCycle)}`;
    observe(bot, st, key, { kind: "pull_expected", lane: s.lane, at: now, campIdx: camp.campIdx, enemyPid: support?.pid, aggroAt }, s, enemies);
}

function pullSignals(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], now: number): void {
    const camps = Camps.PullCampsFor(enemyTeamOf(s.team), s.lane);
    if (camps.length === 0) return;
    const cycle = cycleOf(now);
    const support = enemyAt(enemies, s.lane, (pos) => pos >= 4);
    const suspected = support !== undefined ? suspectedCamp(camps, support, now) : undefined;
    if (support !== undefined && suspected !== undefined) {
        const sig = { kind: "pull" as const, lane: s.lane, at: now, campIdx: suspected, enemyPid: support.pid };
        observe(bot, st, `pull:${suspected}:${cycle}`, sig, s, enemies, !support.visible);
    }
    pullExpectedSignal(bot, st, s, enemies, camps[0], support, now);

    if (st.waveCycle !== cycle) {
        st.waveCycle = cycle;
        st.waveMax = 0;
    }
    st.waveMax = math.max(st.waveMax, s.enemy.count);
    if (s.enemyWaveSizes.length === 0) return;
    let typical = 0;
    for (const n of s.enemyWaveSizes) typical = math.max(typical, n);
    const anomaly = WaveAnomaly(s.cycleSec, s.enemyArrivalSec, st.waveMax, typical);
    if (anomaly === undefined) return;
    const kind = anomaly === "late" ? "pull" : "half_pull";
    const sig = { kind, lane: s.lane, at: now, campIdx: camps[0].campIdx, enemyPid: support?.pid } as Omit<Signal, "noticed">;
    observe(bot, st, `${kind}:${camps[0].campIdx}:${cycle}`, sig, s, enemies);
}

function freezeSignal(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], now: number): void {
    if (!FreezeSuspected(s.eqHistory, s.enemyDeniesPerCycle)) {
        st.freezeKey = undefined;
        return;
    }
    // One instance per freeze episode: a freeze that holds for several cycles is noticed (or missed) once.
    if (st.freezeKey === undefined) st.freezeKey = `freeze:${cycleOf(now)}`;
    observe(bot, st, st.freezeKey, { kind: "freeze", lane: s.lane, at: now }, s, enemies);
}

function midSignals(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], now: number): void {
    if (s.lane !== Lane.Mid) return;
    const cfg = settings();
    const shoveEq = cfg.Thresholds.MidMissingEq;
    const enemyMid = enemyAt(enemies, s.lane, (pos) => pos === 2);
    const last = s.eqHistory[s.eqHistory.length - 1];
    if (enemyMid !== undefined && !enemyMid.visible && enemyMid.timeSinceSeen > cfg.Timing.CounterUnseen && last !== undefined && last <= shoveEq) {
        observe(bot, st, `mid_missing:${cycleOf(now)}`, { kind: "mid_missing", lane: s.lane, at: now, enemyPid: enemyMid.pid }, s, enemies);
    }
    const next = LaneConfig.Helpers().NextPowerRuneTime;
    if (next === undefined || s.eqPos > shoveEq) return;
    const rune = next();
    const left = rune - now;
    if (left <= 0 || left > cfg.Timing.MidRuneShoveLookahead) return;
    observe(bot, st, `rune_shove:${math.floor(rune)}`, { kind: "rune_shove", lane: s.lane, at: now, enemyPid: enemyMid?.pid }, s, enemies);
}

function stackSignals(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], now: number): void {
    const cfg = settings();
    const minute = math.floor(now / 60);
    const sec = now - minute * 60;
    const watching = sec >= cfg.Timing.StackWatchFrom && sec <= cfg.Timing.StackWatchTo;
    const after = sec <= cfg.Timing.StackOutsideUntil;
    if (!watching && !after) return;
    // A stack seen at :50-:58 and its neutrals walking back at :00-:03 are the same instance.
    const stackMinute = watching ? minute : minute - 1;

    const outside: Record<number, boolean> = {};
    if (after) {
        for (const n of bot.GetNearbyNeutralCreeps(cfg.Radii.CounterNeutralScan, false) ?? []) {
            if (n === null || n === undefined || !n.IsAlive() || !n.CanBeSeen()) continue;
            const [spawner] = Camps.NearestSpawner(n.GetLocation());
            // Our own camps are left out: neutrals outside them at :00 are usually our own stack or pull.
            if (spawner === undefined || spawner.team === s.team) continue;
            if (!Camps.InBox(spawner.idx, n.GetLocation(), cfg.Radii.NeutralOutsideMargin)) outside[spawner.idx] = true;
        }
    }
    for (const spawner of Camps.Spawners()) {
        const center = Camps.BoxCenter(spawner);
        let near: LaneState.LaneEnemy | undefined;
        if (watching) {
            for (const e of enemies) {
                if (e.visible && dist2D(e.location, center) <= cfg.Radii.EnemyNearCamp) {
                    near = e;
                    break;
                }
            }
        }
        if (!StackSuspected(sec, near !== undefined, outside[spawner.idx] === true)) continue;
        const sig = { kind: "stack" as const, lane: s.lane, at: now, campIdx: spawner.idx, enemyPid: near?.pid };
        observe(bot, st, `stack:${spawner.idx}:${stackMinute}`, sig, s, enemies);
    }
}

/** Evaluates once per lane snapshot refresh; off, it returns before any engine call. */
export function Tick(bot: Unit): void {
    if (!on()) return;
    const s = LaneState.ForBot(bot);
    if (s === undefined) return;
    const st = stateOf(bot.GetPlayerID());
    if (st.lastEval === s.time) return;
    st.lastEval = s.time;
    const now = DotaTime();
    prune(st, now);
    const enemies = LaneState.Enemies(bot, s.lane);
    notePositions(enemies);
    if (LaneConfig.InLaningPhase()) {
        pullSignals(bot, st, s, enemies, now);
        freezeSignal(bot, st, s, enemies, now);
        midSignals(bot, st, s, enemies, now);
    }
    stackSignals(bot, st, s, enemies, now);
}

function live(st: ObserverState, now: number): [string, Signal][] {
    const ttl = settings().Timing.CounterSignalTTL;
    const result: [string, Signal][] = [];
    for (const [key, sig] of pairs(st.instances)) if (sig.noticed && now - sig.at <= ttl) result.push([key, sig]);
    return result;
}

export function Signals(bot: Unit): Signal[] {
    if (!on()) return [];
    const st = observers[bot.GetPlayerID()];
    if (st === undefined) return [];
    return live(st, DotaTime()).map(([, sig]) => sig);
}

// ---------------------------------------------------------------------------------------------- responses

function towerProtects(bot: Unit, target: LaneState.LaneEnemy): boolean {
    const range = settings().Thresholds.EnemyTowerRange;
    for (const t of bot.GetNearbyTowers(1600, true) ?? []) {
        if (t !== null && t !== undefined && dist2D(t.GetLocation(), target.location) <= range) return true;
    }
    return false;
}

function hpOf(u: Unit): number {
    const max = u.GetMaxHealth();
    return max > 0 ? u.GetHealth() / max : 0;
}

/** The remaining visible enemy laner (not the puller) nearest our front. */
function remainingLaner(s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], pullerPid: number | undefined): LaneState.LaneEnemy | undefined {
    let best: LaneState.LaneEnemy | undefined;
    let bestDist = settings().Radii.LaneCreep;
    for (const e of enemies) {
        if (!e.visible || e.unit === undefined || e.pid === pullerPid) continue;
        const d = dist2D(e.location, s.frontLoc);
        if (d <= bestDist) {
            best = e;
            bestDist = d;
        }
    }
    return best;
}

/** This lane's enemy laners: seen near our front, the same test LanePlan.EnemyLaners uses. */
function isLaner(e: LaneState.LaneEnemy, s: LaneState.LaneSnapshot): boolean {
    const cfg = settings();
    if (!e.visible && e.timeSinceSeen > cfg.Timing.ExposureSeen) return false;
    return dist2D(e.location, s.frontLoc) <= cfg.Radii.Exposure;
}

/**
 * No enemy other than this lane's laners (the puller included) seen near the route recently. The laners are
 * already weighed by the partner-safety check the camp-job executor repeats every frame.
 */
function pathSafe(bot: Unit, s: LaneState.LaneSnapshot, to: Vector, enemies: LaneState.LaneEnemy[], pullerPid: number | undefined): boolean {
    const cfg = settings();
    const from = bot.GetLocation();
    for (const e of enemies) {
        if (e.pid === pullerPid || isLaner(e, s) || (!e.visible && e.timeSinceSeen > cfg.Timing.PathSafeSeen)) continue;
        if (distToSegment(e.location, from, to) <= cfg.Radii.PathSafe) return false;
    }
    return true;
}

/** Punish the 2v1 while the enemy support is away; a reaction, so exempt from the one-technique lock. */
function runPunish(bot: Unit, st: ObserverState, enemies: LaneState.LaneEnemy[], now: number): boolean {
    const p = st.punish;
    if (p === undefined) return false;
    const t = settings().Timing;
    const target = visibleEnemy(enemies, p.pid);
    if (now - p.startAt > t.PunishFor || target === undefined || target.unit === undefined) {
        st.punish = undefined;
        return false;
    }
    if (Harass.TowerForbids(bot.GetLevel(), towerProtects(bot, target), hpOf(target.unit))) return false;
    if (p.lastAt === undefined || now - p.lastAt >= t.PunishGap) {
        bot.Action_AttackUnit(target.unit, true);
        p.lastAt = now;
    }
    return true;
}

function respondToPull(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], now: number): void {
    for (const [key, sig] of live(st, now)) {
        if ((sig.kind !== "pull" && sig.kind !== "half_pull") || st.responded[key] === true) continue;
        if (stronger(bot)) {
            const laner = remainingLaner(s, enemies, sig.enemyPid);
            if (laner === undefined) continue;
            st.responded[key] = true;
            st.punish = { pid: laner.pid, startAt: now };
            return;
        }
        if (sig.campIdx === undefined || LaneRoles.CampJobOwner(s) !== bot.GetPlayerID() || LanePlanner.Committed(bot) !== undefined) continue;
        if (CampJobs.Active(bot)) continue;
        const spawner = Camps.SpawnerByIdx(sig.campIdx);
        if (spawner === undefined || !pathSafe(bot, s, Camps.BoxCenter(spawner), enemies, sig.enemyPid)) continue;
        if (CampJobs.Start(bot, { kind: "contest", campIdx: sig.campIdx, targetPid: sig.enemyPid })) st.responded[key] = true;
        return;
    }
}

function findWard(bot: Unit): any | undefined {
    for (let slot = 0; slot < INVENTORY_SLOTS; slot++) {
        const item = bot.GetItemInSlot(slot);
        if (item !== null && item !== undefined && WARDS[item.GetName()] === true) return item;
    }
    return undefined;
}

/**
 * Blocks the enemy pull camp's next spawn with a ward in its box at :50-:58.
 * TODO (in-game): confirm a sentry/observer ward in the box still blocks the neutral spawn on the current patch.
 */
function campBlock(bot: Unit, st: ObserverState, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[], now: number): boolean {
    const cfg = settings();
    if (!LaneConfig.IsOn("CampBlock") || !LaneConfig.InLaningPhase() || !isSupport(bot)) return false;
    if (LaneConfig.SkillOf(bot) <= cfg.Gates.CampBlock) return false;
    const sec = now % 60;
    if (sec < cfg.Timing.CampBlockFrom || sec > cfg.Timing.CampBlockTo) return false;
    const ward = findWard(bot);
    if (st.campBlockAt !== undefined && now - st.campBlockAt < cfg.Timing.CampBlockCooldown) {
        // Walking to the box to plant: keep the frame until the ward is used or the window closes.
        return ward !== undefined && math.floor(st.campBlockAt / 60) === math.floor(now / 60);
    }
    if (ward === undefined) return false;
    let spawner: Camps.Spawner | undefined;
    for (const camp of Camps.PullCampsFor(enemyTeamOf(s.team), s.lane)) {
        const sp = Camps.SpawnerByIdx(camp.campIdx);
        // The enemy off lane pulls our own hard camp: a ward there would block our pulls too.
        if (sp !== undefined && sp.team !== s.team) {
            spawner = sp;
            break;
        }
    }
    if (spawner === undefined) return false;
    const center = Camps.BoxCenter(spawner);
    const eta = GetUnitToLocationDistance(bot, center) / math.max(bot.GetCurrentMovementSpeed(), 1);
    if (eta > cfg.Timing.CampBlockTo - sec || !pathSafe(bot, s, center, enemies, undefined)) return false;
    bot.Action_UseAbilityOnLocation(ward, center);
    st.campBlockAt = now;
    HDebug.Log("lane", `counter pid=${bot.GetPlayerID()} camp-block camp=${spawner.idx}`);
    return true;
}

/** Laning Think, after the techniques; true when this frame's action is issued. */
export function Think(bot: Unit, _enemies: Unit[]): boolean {
    const counter = on();
    if (!counter && !LaneConfig.IsOn("CampBlock")) return false;
    const s = LaneState.ForBot(bot);
    if (s === undefined) return false;
    const st = stateOf(bot.GetPlayerID());
    const now = DotaTime();
    const enemies = LaneState.Enemies(bot, s.lane);
    if (counter) {
        if (runStackAttack(bot, st, enemies, now)) return true;
        if (runPunish(bot, st, enemies, now)) return true;
        respondToPull(bot, st, s, enemies, now);
        if (runPunish(bot, st, enemies, now)) return true;
    }
    return campBlock(bot, st, s, enemies, now);
}

/** One hit on a stacker; the frame is held until the hit lands (GetLastAttackTime is on the GameTime clock). */
function runStackAttack(bot: Unit, st: ObserverState, enemies: LaneState.LaneEnemy[], now: number): boolean {
    const sa = st.stackAttack;
    if (sa === undefined) return false;
    const stacker = visibleEnemy(enemies, sa.pid);
    if (now > sa.until || stacker === undefined || stacker.unit === undefined) {
        st.stackAttack = undefined;
        return false;
    }
    if (sa.orderedAt === undefined) {
        bot.Action_AttackUnit(stacker.unit, true);
        sa.orderedAt = GameTime();
        return true;
    }
    if (bot.GetLastAttackTime() >= sa.orderedAt) {
        st.stackAttack = undefined;
        return false;
    }
    return true;
}

/** The live break-freeze / rune-shove answer: "shove", "zone", or undefined when none applies. */
function counterAnswer(bot: Unit): { answer: "shove" | "zone"; s: LaneState.LaneSnapshot } | undefined {
    if (!on()) return undefined;
    const st = observers[bot.GetPlayerID()];
    if (st === undefined || st.counterUntil === undefined) return undefined;
    if (DotaTime() >= st.counterUntil) {
        st.counterUntil = undefined;
        return undefined;
    }
    // Never push out a wave our own lane plan is freezing.
    const s = LaneState.ForBot(bot);
    if (s === undefined || LanePlan.View(bot, s).plan === "FREEZE") return undefined;
    // The same gates LaneTech's shove executor applies, so the planner never commits to a shove that cannot run.
    const canShove = LaneConfig.Knows("shove", LaneConfig.SkillOf(bot)) && stronger(bot) && hpOf(bot) >= settings().Thresholds.ShoveMinHP;
    return { answer: canShove ? "shove" : "zone", s };
}

/** Zoning point while the counter answer is to zone; `loc` itself otherwise. */
export function AdjustPosition(bot: Unit, loc: Vector): Vector {
    const c = counterAnswer(bot);
    if (c === undefined || c.answer !== "zone") return loc;
    return LaneTech.ZonePoint(bot, c.s) ?? loc;
}

function techniqueOverride(bot: Unit): LaneConfig.Technique | undefined {
    const c = counterAnswer(bot);
    return c !== undefined && c.answer === "shove" ? "shove" : undefined;
}

export function RuneContestDesire(bot: Unit): number {
    if (!on()) return 0;
    const st = observers[bot.GetPlayerID()];
    if (st === undefined || st.runeContestUntil === undefined) return 0;
    if (DotaTime() >= st.runeContestUntil) {
        st.runeContestUntil = undefined;
        return 0;
    }
    return settings().Timing.RuneContestDesire;
}

export function MarkedStacked(team: number): number[] {
    const result: number[] = [];
    if (!on()) return result;
    const now = DotaTime();
    for (const [idx, until] of pairs(marked[team] ?? {})) if (until > now) result.push(idx as number);
    result.sort((a, b) => a - b);
    return result;
}

function campSafe(center: Vector, enemies: LaneState.LaneEnemy[]): boolean {
    const cfg = settings();
    for (const e of enemies) {
        if (!e.visible && e.timeSinceSeen > cfg.Timing.StackedCampSeen) continue;
        if (dist2D(e.location, center) <= cfg.Radii.StackedCampSafe) return false;
    }
    return true;
}

/** mode_farm_generic: a core after laning heads for a camp an enemy was seen stacking; undefined keeps its own pick. */
export function PreferStackedCamp(bot: Unit, camps: any[]): any | undefined {
    if (!on() || LaneConfig.InLaningPhase()) return undefined;
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos < 1 || pos > 3) return undefined;
    const team = bot.GetTeam();
    const marks = marked[team];
    if (marks === undefined) return undefined;
    const now = DotaTime();
    const enemies = LaneState.Enemies(bot, bot.GetAssignedLane());
    const matchRadius = settings().Camps.ReplayMatchRadius;
    let best: any | undefined;
    let bestDist = math.huge;
    for (const camp of camps ?? []) {
        const loc = camp?.cattr?.location as Vector | undefined;
        if (loc === undefined) continue;
        const [spawner, d] = Camps.NearestSpawner(loc);
        if (spawner === undefined || d > matchRadius || (marks[spawner.idx] ?? 0) <= now) continue;
        if (spawner.team !== team && !campSafe(Camps.BoxCenter(spawner), enemies)) continue;
        const dist = GetUnitToLocationDistance(bot, loc);
        if (dist < bestDist) {
            best = camp;
            bestDist = dist;
        }
    }
    return best;
}

export function DropRangedDeny(team: number): boolean {
    return on() && (dropDenyUntil[team] ?? 0) > DotaTime();
}

export function RegisterProbes(): void {
    LaneHooks.SetTechniqueOverride(techniqueOverride);
}

RegisterProbes();
