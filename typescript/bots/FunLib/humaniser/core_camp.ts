/**
 * Core next gold (slice core-next-gold, switch Ours.CoreCampTrip; plan docs/proposals/2026-11-04-lane-stage-farm.md piece 2):
 * an in-lane pos1-3 core leaves for a camp of its own jungle when the lane forecast says the camp's gold beats the lane gold
 * that dies unattended while it is away, clears it (chaining another while the gap allows) and walks back to the lane front.
 * The job chooser hosts it; laning owns the choice through this job's trigger. Takes over FarmPattern's lane-stage trips for
 * the cores it owns, keeping its clear-time estimate and per-bot pace learning.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, DamageType, Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import type { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as StackJob from "bots/FunLib/humaniser/stack_job";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";

// All judgement (slice file "The decision"); the clear-time model and its learning are FarmPattern's values.
export const SETTINGS = {
    /** Rank against the hero's other jobs (cores have none today). */
    Priority: 0.8,
    PlanEvery: 1,
    /** Neutrals spawn at 1:00; no trip before this. */
    From: 120,
    StartHP: 0.65,
    AbortHP: 0.3,
    FrontRadius: 1800,
    WaveClearRadius: 1000,
    /** A creep meeting within this of the enemy T1 (attack range 700 plus a margin) is mostly the tower's: the core's share
     *  of those deaths is TowerShare (it can take some last hits there, at a risk), not LaneShare. */
    TowerReach: 900,
    TowerShare: 0.2,
    /** The forecast run's length, the fronts' gap that counts as a clash, the least gap worth a trip, and how far into the
     *  clash a return may fall when the camp pays for the creeps lost. */
    Horizon: 60,
    ClashGap: 300,
    MinGap: 12,
    MaxLate: 15,
    /** Gold of an enemy lane creep (melee 37, ranged 48, siege 70 weighted by a wave) and the core's share of them in lane. */
    CreepGold: 40,
    LaneShare: 0.5,
    CampGold: { small: 80, medium: 120, large: 160, ancient: 250 } as Record<string, number>,
    MinNet: 30,
    CampMinLevel: { small: 3, medium: 4, large: 6, ancient: 12 } as Record<string, number>,
    MaxCampDist: 3800,
    /** Walking paths run longer than the straight line (rune_job's PathFactor). */
    PathFactor: 1.2,
    /** An enemy hero's reach (lane_spot HeroReach) plus this, touching the walk or the camp, holds the start. */
    ThreatMargin: 600,
    MidRuneGuard: 40,
    /** Neutrals this far from the box centre are the camp's. */
    CampRadius: 700,
    ReturnArrive: 900,
    ReturnMax: 25,
    ReturnReorder: 0.5,
    /** FarmPattern's clear-time model: seconds at RefLevel, scaled by RefLevel / level within LevelScale, plus StackedClearMul
     *  per stack, times the bot's learned pace (Learn towards measured / estimate, within LearnClamp; LateGrowth on a late leave).
     *  Medium and large are above FarmPattern's 10 and 13: over 164 trips (cnghar2, cngchk5, cngchk6) the third neutral
     *  died about 1.4-1.5 times later than those allowed, and a large camp averaged 1.25 kills a trip; ancient scaled with them (not measured). */
    ClearSec: { small: 7, medium: 14, large: 19, ancient: 26 } as Record<string, number>,
    RefLevel: 8,
    LevelScale: [0.6, 1.6],
    StackedClearMul: 0.8,
    Learn: 0.3,
    LearnClamp: [0.4, 2.5],
    LateGrowth: 1.15,
    /** The clear's HP cost as a fraction of max HP at HPRefLevel, times HPLevelStep per level above it (within LevelScale),
     *  plus StackedClearMul per stack, times the bot's learned HP rate (Learn, LearnClamp; LateGrowth on an HP abort). A camp
     *  is taken only when the core keeps ArriveHP after it. cnghar2/cngchk5 (05/11/2026): HP lost from start to end of a trip,
     *  median (80th percentile), small 0.08 (0.17) at levels 3-5, medium 0.16 (0.35) at 3-5, large 0.42 (0.64) at 6-7, the
     *  large ones mostly on camps OHA had stacked (11 neutral deaths in a minute); `judgement` puts an unstacked large lower. */
    ClearHP: { small: 0.12, medium: 0.2, large: 0.35, ancient: 0.6 } as Record<string, number>,
    /** Live neutrals in the box that read as one more stack: a camp spawns 2-4. */
    NeutralsPerStack: 3,
    HPRefLevel: 6,
    HPLevelStep: 0.88,
    ArriveHP: 0.4,
    /** The clear model (live or last-seen neutrals; the tables above only for a camp never seen): seconds between kills
     *  (retarget and walk), and the seconds per attack assumed when the API gives none (`judgement`). */
    SwitchSec: 0.6,
    DefaultSPA: 1.7,
};

/** One priced camp. */
export interface CampPlan {
    camp: number;
    type: Camps.CampType;
    /** Planned return to the clash point, latest leave from the camp, clear estimate, gold, the lane loss at the return, net. */
    ret: number;
    leaveBy: number;
    clr: number;
    /** The clear estimate before the pace factor, which the measured clear is learned against. */
    prior: number;
    /** Where the estimate came from: the camp's neutrals now (`live`), as last seen (`seen`), or the type tables (`table`). */
    src: string;
    /** The type tables' clear seconds and HP fraction for the same camp (logged beside the model's, to compare). */
    clrt: number;
    hpt: number;
    /** The priced neutrals (check telemetry) and their count. */
    nu?: string;
    n0?: number;
    /** The clear's HP cost (fraction of max HP) and its estimate before the learned rate. */
    hpc: number;
    hpPrior: number;
    gold: number;
    loss: number;
    net: number;
}

/** The forecast's next clash: when the fronts meet and where, and the enemy creep deaths per second of the run. */
export interface Clash {
    t: number;
    at: Vector;
    t0: number;
    samples: LanePush.Sample[];
    enemy: number;
    path: LanePath;
    team: number;
}

interface Trip {
    lane: Lane;
    clash: Clash;
    plan: CampPlan;
    camps: number;
    left: number;
    g0: number;
    host: number;
    engagedAt?: number;
    hpAtEngage?: number;
    /** The last clear's measured seconds from engage and HP lost (to the camp's end: cleared or left). */
    clrm?: number;
    hpm?: number;
    /** Neutrals the team still sees alive at the camp when the core leaves it. */
    nl?: number;
    returning?: boolean;
    threatSince?: number;
    back?: number;
    hit?: boolean;
}

const running: Record<number, Trip | undefined> = {};
const nextPlanAt: Record<number, number> = {};
const pace: Record<number, number> = {};
const hpRate: Record<number, number> = {};
/** Each camp's neutrals as last seen, by team then camp (a respawn is assumed the same until seen again). */
const lastSeen: Record<number, Record<number, Neutral[]>> = {};
/** Camps cleared or seen empty, by team then camp, as the minute (they respawn on the next). */
const cleared: Record<number, Record<number, number>> = {};
/** Skip lines written, by pid: one per wave window and reason. */
const skipped: Record<number, Record<string, boolean>> = {};
const gates: Record<number, { min: number; n: Record<string, number> }> = {};

export function ResetCache(): void {
    for (const t of [running, nextPlanAt, pace, hpRate, cleared, lastSeen, skipped, gates] as Record<number, unknown>[]) for (const [k] of pairs(t)) delete t[k as number];
}

function clamp(v: number, r: number[]): number {
    return math.max(r[0], math.min(r[1], v));
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

function distToSegment(p: Vector, a: Vector, b: Vector): number {
    const vx = b.x - a.x;
    const vy = b.y - a.y;
    const len2 = vx * vx + vy * vy;
    const u = len2 > 0 ? math.max(0, math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)) : 0;
    return math.sqrt((p.x - (a.x + u * vx)) ** 2 + (p.y - (a.y + u * vy)) ** 2);
}

function hpOf(bot: Unit): number {
    const m = bot.GetMaxHealth();
    return m > 0 ? bot.GetHealth() / m : 0;
}

function speedOf(bot: Unit): number {
    return math.max(bot.GetCurrentMovementSpeed(), 100);
}

/** Meepo's clones and Arc's tempest double share the hero's player ID. */
function sharesPlayerID(bot: Unit): boolean {
    return bot.GetUnitName() === "npc_dota_hero_meepo" || bot.HasModifier("modifier_arc_warden_tempest_double");
}

export function Applies(bot: Unit): boolean {
    if (!Ours.On("CoreCampTrip") || !Ours.On("CoreLastHit") || !Ours.On("JobChooser") || !bot.IsBot() || sharesPlayerID(bot)) return false;
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 1 && pos <= 3;
}

/** The core's lane-stage camp trips are this job's: FarmPattern starts none for it. */
export function Owns(bot: Unit): boolean {
    return Applies(bot) && LaneConfig.InLaningPhase();
}

export function Priority(bot: Unit): number | undefined {
    return Owns(bot) ? SETTINGS.Priority : undefined;
}

export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

export function Claims(bot: Unit): boolean {
    return Running(bot);
}

// ------------------------------------------------------------------------------------------------ clear time and pace

export function PriorClearTime(type: Camps.CampType, level: number, stacks: number): number {
    const s = SETTINGS;
    return (s.ClearSec[type] ?? s.ClearSec.medium) * clamp(s.RefLevel / math.max(level, 1), s.LevelScale) * (1 + s.StackedClearMul * stacks);
}

export function Pace(bot: Unit): number {
    return pace[bot.GetPlayerID()] ?? 1;
}

function learn(bot: Unit, measured: number, prior: number): void {
    if (prior <= 0) return;
    const pid = bot.GetPlayerID();
    const old = pace[pid] ?? 1;
    pace[pid] = clamp(old + SETTINGS.Learn * (measured / prior - old), SETTINGS.LearnClamp);
}

function growLate(bot: Unit): void {
    const pid = bot.GetPlayerID();
    pace[pid] = clamp((pace[pid] ?? 1) * SETTINGS.LateGrowth, SETTINGS.LearnClamp);
}

export function PriorClearHP(type: Camps.CampType, level: number, stacks: number): number {
    const s = SETTINGS;
    const scale = clamp(s.HPLevelStep ** (level - s.HPRefLevel), s.LevelScale);
    return (s.ClearHP[type] ?? s.ClearHP.medium) * scale * (1 + s.StackedClearMul * stacks);
}

export function HPRate(bot: Unit): number {
    return hpRate[bot.GetPlayerID()] ?? 1;
}

function learnHP(bot: Unit, measured: number, prior: number): void {
    if (prior <= 0) return;
    const pid = bot.GetPlayerID();
    const old = hpRate[pid] ?? 1;
    hpRate[pid] = clamp(old + SETTINGS.Learn * (math.max(measured, 0) / prior - old), SETTINGS.LearnClamp);
}

function growHP(bot: Unit): void {
    const pid = bot.GetPlayerID();
    hpRate[pid] = clamp((hpRate[pid] ?? 1) * SETTINGS.LateGrowth, SETTINGS.LearnClamp);
}

// ------------------------------------------------------------------------------------------------ the clear model

type Attacker = Unit & { GetSecondsPerAttack?(): number };

/** One neutral: HP, the share of a physical hit it takes after armour, its attack damage and seconds per attack. */
export interface Neutral {
    hp: number;
    take: number;
    dmg: number;
    spa: number;
    name?: string;
}

function spaOf(u: Unit): number {
    const spa = (u as Attacker).GetSecondsPerAttack?.();
    return spa !== undefined && spa > 0 ? spa : SETTINGS.DefaultSPA;
}

function readNeutral(u: Unit, hp: number): Neutral {
    return { hp, take: u.GetActualIncomingDamage(100, DamageType.Physical) / 100, dmg: u.GetAttackDamage(), spa: spaOf(u), name: u.GetUnitName() };
}

/**
 * Seconds for `bot` to clear `camp` by right-clicks and the fraction of its max HP lost doing it. The neutrals die one at a
 * time in the order that loses the least HP (most damage a second per second of kill time first); each hits until it dies;
 * SwitchSec between kills; the core's regen offsets the loss. Spells and cleave are not in it: the learned pace and HP rate
 * carry them.
 */
export function ClearOf(bot: Unit, camp: Neutral[]): LuaMultiReturn<[number, number]> {
    const hit = bot.GetAttackDamage() / spaOf(bot);
    const foes: { kill: number; dps: number }[] = [];
    for (const n of camp) {
        foes.push({
            kill: n.hp / math.max(hit * n.take, 1) + SETTINGS.SwitchSec,
            dps: bot.GetActualIncomingDamage(n.dmg, DamageType.Physical) / math.max(n.spa, 0.1),
        });
    }
    foes.sort((a, b) => b.dps / b.kill - a.dps / a.kill);
    let t = 0;
    let taken = 0;
    for (const f of foes) {
        t += f.kill;
        taken += f.dps * t;
    }
    const hp = math.max(0, taken - bot.GetHealthRegen() * t) / math.max(bot.GetMaxHealth(), 1);
    return $multi(t, hp);
}

/** The camp's live neutrals (the API returns none in fog), kept as its last-seen make-up at full HP. */
function liveNeutrals(team: number, idx: number, center: Vector): Neutral[] {
    const live: Neutral[] = [];
    const full: Neutral[] = [];
    for (const u of GetUnitList(UnitType.NeutralCreeps) ?? []) {
        if (u === null || u === undefined || !u.IsAlive()) continue;
        const at = u.GetLocation();
        if (at === null || at === undefined || dist(at, center) > SETTINGS.CampRadius) continue;
        live.push(readNeutral(u, u.GetHealth()));
        full.push(readNeutral(u, u.GetMaxHealth()));
    }
    if (full.length > 0) {
        lastSeen[team] = lastSeen[team] ?? {};
        lastSeen[team][idx] = full;
    }
    return live;
}

/** Clear seconds and HP fraction before the learned factors, and their source; `stacks` scales only the unseen ones. */
function estimate(bot: Unit, spawner: Camps.Spawner, center: Vector, stacks: number): LuaMultiReturn<[number, number, string, Neutral[] | undefined]> {
    const live = liveNeutrals(bot.GetTeam(), spawner.idx, center);
    if (live.length > 0) {
        const [secs, hp] = ClearOf(bot, live);
        return $multi(secs, hp, "live", live);
    }
    const seen = lastSeen[bot.GetTeam()]?.[spawner.idx];
    if (seen !== undefined) {
        const [secs, hp] = ClearOf(bot, seen);
        const k = 1 + SETTINGS.StackedClearMul * stacks;
        return $multi(secs * k, hp * k, "seen", seen);
    }
    const level = bot.GetLevel();
    return $multi(PriorClearTime(spawner.type, level, stacks), PriorClearHP(spawner.type, level, stacks), "table", undefined);
}

/** The neutrals the model priced, for the check: short name, HP, damage, seconds per attack, share taken. */
function neutralsField(ns: Neutral[] | undefined): string | undefined {
    if (ns === undefined) return undefined;
    const parts: string[] = [];
    for (const n of ns) {
        const [short] = string.gsub(n.name ?? "?", "npc_dota_neutral_", "");
        parts.push(`${short}/${math.floor(n.hp)}/${math.floor(n.dmg)}/${r2(n.spa)}/${r2(n.take)}`);
    }
    return parts.join(",");
}

// ------------------------------------------------------------------------------------------------ the forecast

/** The first second of `samples` with the fronts within ClashGap, and the clash point there; undefined when none. */
/** Whether lane position `s` lies within the enemy T1's reach (Radiant runs along increasing `s`). */
export function UnderEnemyTower(path: LanePath, team: number, s: number): boolean {
    for (const tw of path.towers) {
        if (tw.team === team) continue;
        return team === Team.Radiant ? s >= tw.s - SETTINGS.TowerReach : s <= tw.s + SETTINGS.TowerReach;
    }
    return false;
}

/** Where the fronts meet in a sample (their midpoint on the lane), or undefined when they are not within ClashGap. */
function meetingAt(smp: LanePush.Sample): number | undefined {
    const r = smp.front[Team.Radiant];
    const d = smp.front[Team.Dire];
    return r !== undefined && d !== undefined && d - r <= SETTINGS.ClashGap ? (r + d) / 2 : undefined;
}

/**
 * The next lane gold: the first second the fronts meet outside the enemy T1's reach. A wave crashing into their tower is
 * not it, so a pushed lane's gap runs to the next wave's meeting.
 */
export function ClashOf(samples: LanePush.Sample[], path: LanePath, team: number): Clash | undefined {
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    for (const smp of samples) {
        const m = meetingAt(smp);
        if (m !== undefined && !UnderEnemyTower(path, team, m)) {
            const [x, y] = LanePush.PointAt(path, m);
            return { t: smp.t, at: Vector(x, y, 0), t0: samples[0].t, samples, enemy, path, team };
        }
    }
    return undefined;
}

/**
 * The lane gold the core would have taken from the enemy creeps the run kills between `from` and `to` (to the last sample
 * when `to` lies beyond it): LaneShare of each, TowerShare of those killed while the fronts meet in the enemy T1's reach.
 */
export function LossBetween(c: Clash, from: number, to: number): number {
    let gold = 0;
    let prev: number | undefined;
    for (const smp of c.samples) {
        if (smp.t > to) break;
        const dead = smp.dead[c.enemy] ?? 0;
        if (prev !== undefined && smp.t > from && dead > prev) {
            const m = meetingAt(smp);
            const share = m !== undefined && UnderEnemyTower(c.path, c.team, m) ? SETTINGS.TowerShare : SETTINGS.LaneShare;
            gold += (dead - prev) * SETTINGS.CreepGold * share;
        }
        prev = dead;
    }
    return gold;
}

// ------------------------------------------------------------------------------------------------ camps

function currentMinute(t: number): number {
    return math.floor(t / 60);
}

/** Stacks read from the camp itself (any stacker's, not only our stack job's): floor(live neutrals / NeutralsPerStack) - 1. */
/** Live neutrals the team sees within CampRadius of `center` (the API returns none in fog; a fogged one has no location). */
function campNeutralCount(center: Vector): number {
    let n = 0;
    for (const u of GetUnitList(UnitType.NeutralCreeps) ?? []) {
        if (u === null || u === undefined || !u.IsAlive()) continue;
        const at = u.GetLocation();
        if (at !== null && at !== undefined && dist(at, center) <= SETTINGS.CampRadius) n++;
    }
    return n;
}

function seenStacks(center: Vector): number {
    return math.max(0, math.floor(campNeutralCount(center) / SETTINGS.NeutralsPerStack) - 1);
}

function markCleared(team: number, idx: number, now: number): void {
    cleared[team] = cleared[team] ?? {};
    cleared[team][idx] = currentMinute(now);
}

/** Lane mates whose pull is planned: our lane's pull camps are theirs. */
function matePulling(bot: Unit): boolean {
    const s = LaneState.ForBot(bot);
    if (s === undefined) return false;
    const pid = bot.GetPlayerID();
    for (const h of s.allies) if (h.assigned && h.pid !== pid && h.alive && PullJob.Claims(h.unit)) return true;
    return false;
}

function otherTripOn(bot: Unit, idx: number): boolean {
    const pid = bot.GetPlayerID();
    for (const [other, t] of pairs(running)) if (other !== pid && t !== undefined && t.plan.camp === idx) return true;
    return false;
}

function allyInBox(bot: Unit, idx: number): boolean {
    const pid = bot.GetPlayerID();
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (a !== null && a !== undefined && a.IsAlive() && a.GetPlayerID() !== pid && Camps.InBox(idx, a.GetLocation(), 300)) return true;
    }
    return false;
}

function campOpen(bot: Unit, spawner: Camps.Spawner, center: Vector, now: number, pullCamps: Record<number, boolean>): boolean {
    const team = bot.GetTeam();
    if (cleared[team]?.[spawner.idx] === currentMinute(now)) return false;
    // The API returns no neutrals in fog: a camp is known empty only where we see.
    if (IsLocationVisible(center) && campNeutralCount(center) === 0) return false;
    if (pullCamps[spawner.idx] === true) return false;
    return !allyInBox(bot, spawner.idx) && !otherTripOn(bot, spawner.idx) && !Stacking.ReservedByAlly(spawner.idx, bot.GetPlayerID());
}

/**
 * The best camp of the core's own jungle from `from` against the forecast `c`, or undefined: open, of a type its level
 * allows, within MaxCampDist of the clash point, back by the clash + MaxLate, with the highest net of at least MinNet.
 */
export function Plan(bot: Unit, from: Vector, now: number, c: Clash): CampPlan | undefined {
    const s = SETTINGS;
    const speed = speedOf(bot) / s.PathFactor;
    const level = bot.GetLevel();
    const pullCamps: Record<number, boolean> = {};
    if (matePulling(bot)) for (const p of Camps.PullCampsFor(bot.GetTeam(), bot.GetAssignedLane())) pullCamps[p.campIdx] = true;
    let best: CampPlan | undefined;
    for (const spawner of Camps.Spawners()) {
        if (spawner.team !== bot.GetTeam() || level < (s.CampMinLevel[spawner.type] ?? 1)) continue;
        const center = Camps.BoxCenter(spawner);
        if (dist(center, c.at) > s.MaxCampDist || !campOpen(bot, spawner, center, now, pullCamps)) continue;
        const stacks = math.max(Stacking.StackCount(spawner.idx), seenStacks(center));
        const [prior, hpPrior, src, priced] = estimate(bot, spawner, center, stacks);
        const clrt = PriorClearTime(spawner.type, level, stacks);
        const hpt = PriorClearHP(spawner.type, level, stacks);
        const clr = prior * Pace(bot);
        const hpc = hpPrior * HPRate(bot);
        if (hpOf(bot) - hpc < s.ArriveHP) continue;
        const back = dist(center, c.at) / speed;
        const ret = now + dist(from, center) / speed + clr + back;
        const force = Overrides.CampForce();
        if (ret > (force ? now + s.Horizon : c.t + s.MaxLate)) continue;
        const gold = (s.CampGold[spawner.type] ?? s.CampGold.medium) * (1 + stacks);
        const loss = LossBetween(c, now, ret);
        const net = gold - loss;
        if ((force || net >= s.MinNet) && (best === undefined || net > best.net))
            best = { camp: spawner.idx, type: spawner.type, ret, leaveBy: ret - back, clr, prior, src, nu: neutralsField(priced), n0: priced?.length, clrt, hpt, hpc, hpPrior, gold, loss, net };
    }
    return best;
}

/** Any open camp of a type the core's level allows within MaxCampDist of `front`: the forecast (about 11 ms for 60 s) runs only then. */
function anyCamp(bot: Unit, front: Vector, now: number): boolean {
    const level = bot.GetLevel();
    for (const spawner of Camps.Spawners()) {
        if (spawner.team !== bot.GetTeam() || level < (SETTINGS.CampMinLevel[spawner.type] ?? 1)) continue;
        const center = Camps.BoxCenter(spawner);
        if (dist(center, front) <= SETTINGS.MaxCampDist && campOpen(bot, spawner, center, now, {})) return true;
    }
    return false;
}

// ------------------------------------------------------------------------------------------------ gates

/** A visible enemy hero whose reach (plus ThreatMargin) touches the walk from the core to `at` or the camp itself. */
function threatOnWay(bot: Unit, at: Vector): boolean {
    const here = bot.GetLocation();
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e === null || e === undefined || !e.IsAlive() || e.IsIllusion()) continue;
        if (distToSegment(e.GetLocation(), here, at) <= LaneSpot.HeroReach(bot, e) + SETTINGS.ThreatMargin) return true;
    }
    return false;
}

function mateOnJob(bot: Unit): boolean {
    const s = LaneState.ForBot(bot);
    if (s === undefined) return false;
    const pid = bot.GetPlayerID();
    for (const h of s.allies) {
        if (!h.assigned || h.pid === pid || !h.alive) continue;
        if (StackJob.Running(h.unit) || PullJob.Running(h.unit) || RuneJob.Running(h.unit) || CampJobs.Active(h.unit)) return true;
    }
    return false;
}

function enemyLaneCreepNear(at: Vector, radius: number): boolean {
    for (const c of GetUnitList(UnitType.EnemyCreeps) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && LanePush.IsLaneCreep(c.GetUnitName()) && dist(c.GetLocation(), at) <= radius) return true;
    }
    return false;
}

/** Why the core is not looking for a camp now (cheap reads, before the forecast), or undefined. */
function inLaneGate(bot: Unit, now: number): string | undefined {
    const s = SETTINGS;
    if (!bot.IsAlive()) return "dead";
    if (now < s.From) return "time";
    const mode = bot.GetActiveMode();
    if (mode !== BotMode.Laning && mode !== BotMode.None) return "mode";
    if (hpOf(bot) < s.StartHP) return "low-hp";
    const front = GetLaneFrontLocation(bot.GetTeam(), bot.GetAssignedLane(), 0);
    if (dist(bot.GetLocation(), front) > s.FrontRadius) return "far";
    // Only creeps at the core hold it: a wave fighting at the front is priced by the forecast (cngchk3: the front clause held
    // 58-72% of laning seconds, a pushed lane never clears).
    if (!Overrides.CampForce() && enemyLaneCreepNear(bot.GetLocation(), s.WaveClearRadius)) return "wave";
    return undefined;
}

/** Why a fitting trip may not start now, or undefined. */
function startGate(bot: Unit, plan: CampPlan, now: number): string | undefined {
    if (mateOnJob(bot)) return "mate-job";
    if (LaneHooks.EnemiesMissing(bot, LaneConfig.Settings().Thresholds.JobMissingFresh) > 0) return "enemy-missing";
    if (LaneConfig.PositionOf(bot) === 2 && Runes.NextSpawn("power", now) - now < SETTINGS.MidRuneGuard) return "rune";
    const spawner = Camps.SpawnerByIdx(plan.camp);
    if (spawner !== undefined && threatOnWay(bot, Camps.BoxCenter(spawner))) return "threat";
    return undefined;
}

// ------------------------------------------------------------------------------------------------ telemetry

const r1 = (x: number | undefined): number | undefined => (x !== undefined ? math.floor(x * 10 + 0.5) / 10 : undefined);
const r2 = (x: number): number => math.floor(x * 100 + 0.5) / 100;

function planFields(p: CampPlan): Telemetry.Fields<"core_camp"> {
    return [
        ["camp", p.camp],
        ["type", p.type],
        ["ret", r1(p.ret)],
        ["clr", r1(p.clr)],
        ["src", p.src],
        ["clrt", r1(p.clrt)],
        ["hpt", r2(p.hpt)],
        ["n0", p.n0],
        ["nu", p.nu],
        ["hpc", r2(p.hpc)],
        ["gold", math.floor(p.gold)],
        ["loss", math.floor(p.loss)],
        ["net", math.floor(p.net)],
    ];
}

function log(bot: Unit, phase: string, c: Clash, fields: Telemetry.Fields<"core_camp">): void {
    Telemetry.Event("core_camp", [
        ["pid", bot.GetPlayerID()],
        ["pos", LaneConfig.PositionOf(bot)],
        ["lane", bot.GetAssignedLane()],
        ["phase", phase],
        ["clash", c.t],
        ["win", math.floor(c.t / 30)],
        ...fields,
    ]);
}

/** One skip line per wave window and reason: the coverage count's windows where a camp fitted and no trip started. */
function noteSkip(bot: Unit, why: string, c: Clash, plan: CampPlan): void {
    const pid = bot.GetPlayerID();
    const key = `${math.floor(c.t / 30)}:${why}`;
    skipped[pid] = skipped[pid] ?? {};
    if (skipped[pid][key] === true) return;
    skipped[pid][key] = true;
    log(bot, "skip", c, [["why", why], ...planFields(plan)]);
}

type GateField = "h_dead" | "h_mode" | "h_hp" | "h_far" | "h_wave" | "h_camp" | "h_fc" | "h_clash" | "h_gap" | "h_plan" | "h_skip" | "h_trip";
const GATE_FIELD: Record<string, GateField> = {
    dead: "h_dead",
    mode: "h_mode",
    "low-hp": "h_hp",
    far: "h_far",
    wave: "h_wave",
    "no-camp": "h_camp",
    "no-forecast": "h_fc",
    "no-clash": "h_clash",
    gap: "h_gap",
    "no-plan": "h_plan",
    skip: "h_skip",
    trip: "h_trip",
};

/**
 * The coverage's denominator: each planning second of the laning phase counted by what held it, one `phase=gates` line per
 * core per game minute. The skip lines only see seconds where a camp already fitted.
 */
function tally(bot: Unit, now: number, why: string): void {
    const pid = bot.GetPlayerID();
    const min = math.floor(now / 60);
    let g: { min: number; n: Record<string, number> } | undefined = gates[pid];
    if (g !== undefined && g.min !== min) {
        const fields: Telemetry.Fields<"core_camp"> = [["min", g.min]];
        for (const [k, n] of pairs(g.n)) fields.push([GATE_FIELD[k as string], n as number]);
        Telemetry.Event("core_camp", [["pid", pid], ["pos", LaneConfig.PositionOf(bot)], ["lane", bot.GetAssignedLane()], ["phase", "gates"], ...fields]);
        g = undefined;
    }
    if (g === undefined) {
        g = { min, n: {} };
        gates[pid] = g;
    }
    g.n[why] = (g.n[why] ?? 0) + 1;
}

function jobLine(bot: Unit, t: Trip, phase: string, why: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "camp"],
        ["phase", phase],
        ["why", why],
        ["host", t.host],
        ...(phase === "end" ? ([["hit", t.hit === true ? 1 : 0]] as Telemetry.Fields<"job">) : []),
    ]);
}

// ------------------------------------------------------------------------------------------------ the trip

/** Why the trip must stop now (the task's guard, every frame), or undefined. The walk back ignores heroes: laning decides. */
function guard(bot: Unit, t: Trip): string | undefined {
    if (hpOf(bot) < SETTINGS.AbortHP) return "hp";
    if (t.returning === true) return undefined;
    let near = false;
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e !== null && e !== undefined && e.IsAlive() && !e.IsIllusion() && dist(e.GetLocation(), bot.GetLocation()) <= LaneSpot.HeroReach(bot, e)) near = true;
    }
    if (!near) {
        t.threatSince = undefined;
        return undefined;
    }
    const now = DotaTime();
    t.threatSince = t.threatSince ?? now;
    return now - t.threatSince >= Profile.Get(bot).reactBase ? "threat" : undefined;
}

function* walkBack(bot: Unit, t: Trip, ctx: Lib.Ctx): Lib.TaskBody {
    ctx.label("return");
    t.returning = true;
    const from = DotaTime();
    let orderedAt = -math.huge;
    while (true) {
        if (!bot.IsAlive()) return { success: false, reason: "dead" };
        const now = DotaTime();
        const front = GetLaneFrontLocation(bot.GetTeam(), t.lane, 0);
        if (dist(bot.GetLocation(), front) <= SETTINGS.ReturnArrive || enemyLaneCreepNear(bot.GetLocation(), SETTINGS.WaveClearRadius)) {
            t.back = now;
            return { success: true, reason: "ok", message: dist(bot.GetLocation(), front) <= SETTINGS.ReturnArrive ? "back" : "wave" };
        }
        if (now - from > SETTINGS.ReturnMax) return { success: false, reason: "timeout", message: "late" };
        if (now - orderedAt >= SETTINGS.ReturnReorder) {
            bot.Action_MoveToLocation(front);
            orderedAt = now;
        }
        yield;
    }
}

function* body(bot: Unit, t: Trip, ctx: Lib.Ctx): Lib.TaskBody {
    const V = Tasks.Jobs()!;
    const hooks = { label: (l: string) => ctx.label(l), urgent: ctx.urgent };
    while (true) {
        const spawner = Camps.SpawnerByIdx(t.plan.camp);
        if (spawner === undefined) break;
        t.engagedAt = undefined;
        t.hpAtEngage = undefined;
        const r = yield* V.clearCamp(
            bot as unknown as Lib.TaskUnit,
            { at: Camps.BoxCenter(spawner), radius: SETTINGS.CampRadius, deadline: t.plan.leaveBy, onEngage: (at) => {
                t.engagedAt = at;
                t.hpAtEngage = hpOf(bot);
            } },
            hooks
        );
        const now = DotaTime();
        // No `continue` in this loop: TSTL lowers it to a flag set after the final `break`, which Lua 5.1 rejects.
        if (!r.success) {
            if (r.reason !== "timeout") return r;
            if (t.engagedAt !== undefined) {
                measured(bot, t, now, Camps.BoxCenter(spawner));
                growLate(bot);
            }
            break;
        }
        if (t.engagedAt !== undefined) measured(bot, t, now, Camps.BoxCenter(spawner));
        if (r.message === "cleared" && t.engagedAt !== undefined) {
            learn(bot, now - t.engagedAt, t.plan.prior);
            if (t.hpAtEngage !== undefined) learnHP(bot, t.hpAtEngage - hpOf(bot), t.plan.hpPrior);
        }
        markCleared(bot.GetTeam(), t.plan.camp, now);
        const next = Plan(bot, bot.GetLocation(), now, t.clash);
        if (next === undefined) break;
        t.plan = next;
        t.camps++;
        log(bot, "next", t.clash, [["after", r.message ?? "ok"], ["clrm", t.clrm], ["hpm", t.hpm], ["nl", t.nl], ...planFields(next)]);
    }
    return yield* walkBack(bot, t, ctx);
}

function measured(bot: Unit, t: Trip, now: number, center: Vector): void {
    t.nl = campNeutralCount(center);
    t.clrm = t.engagedAt !== undefined ? r1(now - t.engagedAt) : undefined;
    t.hpm = t.hpAtEngage !== undefined ? r2(t.hpAtEngage - hpOf(bot)) : undefined;
}

function finish(bot: Unit, t: Trip, r: Lib.Result, label: string | undefined): void {
    running[bot.GetPlayerID()] = undefined;
    const why = r.success ? (r.message ?? "ok") : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`;
    if (why === "interrupted:hp" && t.returning !== true) growHP(bot);
    jobLine(bot, t, "end", why);
    log(bot, "end", t.clash, [
        ["res", r.success ? "ok" : "fail"],
        ["why", why],
        ["label", label],
        ["camp", t.plan.camp],
        ["camps", t.camps],
        ["ret", r1(t.plan.ret)],
        ["back", r1(t.back)],
        ["g0", t.g0],
        ["g1", bot.GetNetWorth()],
        ["secs", r1(DotaTime() - t.left)],
        ["pace", r1(Pace(bot))],
        ["hp", r2(hpOf(bot))],
        ["hpr", r2(HPRate(bot))],
        ["clrm", t.clrm],
        ["hpm", t.hpm],
        ["nl", t.nl],
    ]);
}

/**
 * Every frame while the chooser asks: true while a trip runs or as one starts. Planned at most every PlanEvery: the cheap
 * in-lane reads, then the forecast and the camps, then the start gates (`blocked`: the chooser's own and higher jobs').
 */
export function Wants(bot: Unit, blocked: (bot: Unit) => string | undefined, host: number): boolean {
    if (!Owns(bot)) return false;
    Tasks.Tick(bot);
    const pid = bot.GetPlayerID();
    if (running[pid] !== undefined) return true;
    if (Tasks.Jobs() === undefined) return false;
    const now = DotaTime();
    if (now < (nextPlanAt[pid] ?? -math.huge)) return false;
    nextPlanAt[pid] = now + SETTINGS.PlanEvery;
    const held = (why: string): false => {
        tally(bot, now, why);
        return false;
    };
    const gate = inLaneGate(bot, now);
    if (gate === "time") return false;
    if (gate !== undefined) return held(gate);
    const lane = bot.GetAssignedLane();
    if (!anyCamp(bot, GetLaneFrontLocation(bot.GetTeam(), lane, 0), now)) return held("no-camp");
    const [samples, path] = LanePush.Forecast(bot.GetTeam(), lane, SETTINGS.Horizon);
    if (samples === undefined || path === undefined || samples.length === 0) return held("no-forecast");
    const force = Overrides.CampForce();
    let clash = ClashOf(samples, path, bot.GetTeam());
    // The harness: a lane with no clash in the run returns to its front at the horizon.
    if (clash === undefined && force) {
        const at = GetLaneFrontLocation(bot.GetTeam(), lane, 0);
        clash = { t: now + SETTINGS.Horizon, at, t0: samples[0].t, samples, enemy: bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant, path, team: bot.GetTeam() };
    }
    // No clash within the horizon: the run says nothing about the lane's loss, so no trip on it.
    if (clash === undefined) return held("no-clash");
    if (!force && clash.t - now < SETTINGS.MinGap) return held("gap");
    const plan = Plan(bot, bot.GetLocation(), now, clash);
    if (plan === undefined) return held("no-plan");
    const why = blocked(bot) ?? startGate(bot, plan, now);
    if (why !== undefined) {
        noteSkip(bot, why, clash, plan);
        return held("skip");
    }
    tally(bot, now, "trip");
    const t: Trip = { lane, clash, plan, camps: 1, left: now, g0: bot.GetNetWorth(), host };
    const ok = Tasks.Start(bot, { name: "camp", host, preemptAfter: 1, stallAfter: 4, guard: () => guard(bot, t), onEnd: (r, info) => finish(bot, t, r, info.label) }, (ctx: Lib.Ctx) =>
        body(bot, t, ctx)
    );
    if (!ok) return false;
    running[pid] = t;
    jobLine(bot, t, "start", "trigger");
    log(bot, "start", clash, planFields(plan));
    return true;
}

export function Step(bot: Unit, host: number): boolean {
    return running[bot.GetPlayerID()] !== undefined && Tasks.Step(bot, host);
}

export function End(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}

export function NoteHit(bot: Unit): void {
    const t = running[bot.GetPlayerID()];
    if (t !== undefined) t.hit = true;
}

export function NoteIdleHeld(_bot: Unit): void {}
