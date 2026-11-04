/**
 * Core next gold (slice core-next-gold, switch Ours.CoreCampTrip; plan docs/proposals/2026-11-04-lane-stage-farm.md piece 2):
 * an in-lane pos1-3 core leaves for a camp of its own jungle when the lane forecast says the camp's gold beats the lane gold
 * that dies unattended while it is away, clears it (chaining another while the gap allows) and walks back to the lane front.
 * The job chooser hosts it; laning owns the choice through this job's trigger. Takes over FarmPattern's lane-stage trips for
 * the cores it owns, keeping its clear-time estimate and per-bot pace learning.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import type { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Ours from "bots/FunLib/humaniser/ours";
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
     *  per stack, times the bot's learned pace (Learn towards measured / estimate, within LearnClamp; LateGrowth on a late leave). */
    ClearSec: { small: 7, medium: 10, large: 13, ancient: 18 } as Record<string, number>,
    RefLevel: 8,
    LevelScale: [0.6, 1.6],
    StackedClearMul: 0.8,
    Learn: 0.3,
    LearnClamp: [0.4, 2.5],
    LateGrowth: 1.15,
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
    returning?: boolean;
    threatSince?: number;
    back?: number;
    hit?: boolean;
}

const running: Record<number, Trip | undefined> = {};
const nextPlanAt: Record<number, number> = {};
const pace: Record<number, number> = {};
/** Camps cleared or seen empty, by team then camp, as the minute (they respawn on the next). */
const cleared: Record<number, Record<number, number>> = {};
/** Skip lines written, by pid: one per wave window and reason. */
const skipped: Record<number, Record<string, boolean>> = {};
const gates: Record<number, { min: number; n: Record<string, number> }> = {};

export function ResetCache(): void {
    for (const t of [running, nextPlanAt, pace, cleared, skipped, gates] as Record<number, unknown>[]) for (const [k] of pairs(t)) delete t[k as number];
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

// ------------------------------------------------------------------------------------------------ the forecast

/** The first second of `samples` with the fronts within ClashGap, and the clash point there; undefined when none. */
export function ClashOf(samples: LanePush.Sample[], path: LanePath, team: number): Clash | undefined {
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    for (const smp of samples) {
        const r = smp.front[Team.Radiant];
        const d = smp.front[Team.Dire];
        if (r !== undefined && d !== undefined && d - r <= SETTINGS.ClashGap) {
            const [x, y] = LanePush.PointAt(path, (r + d) / 2);
            return { t: smp.t, at: Vector(x, y, 0), t0: samples[0].t, samples, enemy };
        }
    }
    return undefined;
}

/** Enemy lane creeps the run kills from its start to `t` (the last sample when `t` lies beyond it). */
export function DeadBy(c: Clash, t: number): number {
    let n = 0;
    for (const smp of c.samples) {
        if (smp.t > t) break;
        n = smp.dead[c.enemy] ?? 0;
    }
    return n;
}

/** The lane gold the core would have taken from the creeps the run kills between `from` and `to`. */
export function LossBetween(c: Clash, from: number, to: number): number {
    return math.max(0, DeadBy(c, to) - DeadBy(c, from)) * SETTINGS.CreepGold * SETTINGS.LaneShare;
}

// ------------------------------------------------------------------------------------------------ camps

function currentMinute(t: number): number {
    return math.floor(t / 60);
}

function campNeutralsSeen(center: Vector): boolean {
    for (const n of GetUnitList(UnitType.NeutralCreeps) ?? []) {
        if (n !== null && n !== undefined && n.IsAlive() && dist(n.GetLocation(), center) <= SETTINGS.CampRadius) return true;
    }
    return false;
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
    if (IsLocationVisible(center) && !campNeutralsSeen(center)) return false;
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
        const stacks = Stacking.StackCount(spawner.idx);
        const prior = PriorClearTime(spawner.type, level, stacks);
        const clr = prior * Pace(bot);
        const back = dist(center, c.at) / speed;
        const ret = now + dist(from, center) / speed + clr + back;
        if (ret > c.t + s.MaxLate) continue;
        const gold = (s.CampGold[spawner.type] ?? s.CampGold.medium) * (1 + stacks);
        const loss = LossBetween(c, now, ret);
        const net = gold - loss;
        if (net >= s.MinNet && (best === undefined || net > best.net))
            best = { camp: spawner.idx, type: spawner.type, ret, leaveBy: ret - back, clr, prior, gold, loss, net };
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
    if (enemyLaneCreepNear(bot.GetLocation(), s.WaveClearRadius) || enemyLaneCreepNear(front, s.WaveClearRadius)) return "wave";
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

function planFields(p: CampPlan): Telemetry.Fields<"core_camp"> {
    return [
        ["camp", p.camp],
        ["type", p.type],
        ["ret", r1(p.ret)],
        ["clr", r1(p.clr)],
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
        const r = yield* V.clearCamp(
            bot as unknown as Lib.TaskUnit,
            { at: Camps.BoxCenter(spawner), radius: SETTINGS.CampRadius, deadline: t.plan.leaveBy, onEngage: (at) => (t.engagedAt = at) },
            hooks
        );
        const now = DotaTime();
        // No `continue` in this loop: TSTL lowers it to a flag set after the final `break`, which Lua 5.1 rejects.
        if (!r.success) {
            if (r.reason !== "timeout") return r;
            if (t.engagedAt !== undefined) growLate(bot);
            break;
        }
        if (r.message === "cleared" && t.engagedAt !== undefined) learn(bot, now - t.engagedAt, t.plan.prior);
        markCleared(bot.GetTeam(), t.plan.camp, now);
        const next = Plan(bot, bot.GetLocation(), now, t.clash);
        if (next === undefined) break;
        t.plan = next;
        t.camps++;
        log(bot, "next", t.clash, [["after", r.message ?? "ok"], ...planFields(next)]);
    }
    return yield* walkBack(bot, t, ctx);
}

function finish(bot: Unit, t: Trip, r: Lib.Result, label: string | undefined): void {
    running[bot.GetPlayerID()] = undefined;
    const why = r.success ? (r.message ?? "ok") : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`;
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
        ["g1", bot.GetGold()],
        ["secs", r1(DotaTime() - t.left)],
        ["pace", r1(Pace(bot))],
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
    const clash = ClashOf(samples, path, bot.GetTeam());
    // No clash within the horizon: the run says nothing about the lane's loss, so no trip on it.
    if (clash === undefined) return held("no-clash");
    if (clash.t - now < SETTINGS.MinGap) return held("gap");
    const plan = Plan(bot, bot.GetLocation(), now, clash);
    if (plan === undefined) return held("no-plan");
    const why = blocked(bot) ?? startGate(bot, plan, now);
    if (why !== undefined) {
        noteSkip(bot, why, clash, plan);
        return held("skip");
    }
    tally(bot, now, "trip");
    const t: Trip = { lane, clash, plan, camps: 1, left: now, g0: bot.GetGold(), host };
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
