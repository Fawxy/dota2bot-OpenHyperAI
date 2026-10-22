/**
 * Core farm pattern: between waves a core (pos 1-3) leaves its lane for a camp of its own jungle near the lane front,
 * clears it (chaining another while the next wave allows) or stacks it when it would get there just before the camp's
 * stack second, then walks back to be at the front when the next enemy wave arrives.
 *
 * Runs from mode_farm_generic: Desire after the camp-job hook and before farm's laning-phase early exit, Think after
 * the camp-job Think and before the ThinkLess throttle. A stack is camp_jobs' stack job (hit timing, walk-off, stacked
 * record), started for the core; the trip waits in its "stack" phase while that job runs.
 *
 * Lessons carried over from camp jobs: claims posted from farm's GetDesire reach retreat and the errands only in the
 * next scoring round, so the retreat hold starts on the walk in; a trip never starts while retreat already bids its
 * desire (it would only win in retreat's dip and end at once); enemy sightings end a trip after a reaction delay, not
 * on the first frame; mode-end and pre-emption logs name the mode that won.
 */
import { BotMode, Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";

export const DEFAULTS = {
    Enable: true,
    // First trip by position: not before StartTime (DotaTime) nor below MinLevel. From EndTime upstream farm runs alone.
    StartTime: { [1]: 300, [2]: 360, [3]: 330 } as Record<number, number>,
    MinLevel: { [1]: 5, [2]: 6, [3]: 6 } as Record<number, number>,
    EndTime: 1200,
    // Above laning's 0.446 (+ the 0.06 stickiness) and farm's own lane-front desires; below last hits (0.9) and camp jobs (0.7).
    Desire: 0.62,
    // Camp jobs' start gate (JobStartHP): lower starts ran into retreat's creep-damage branch on the first hits.
    StartHP: 0.65,
    AbortHP: 0.3,
    // Retreat is held below the trip from the walk in down to this HP, while no hero or tower threatens the bot.
    HoldRetreatHP: 0.4,
    HoldHeroHit: 2,
    // A trip starts within this of the lane front, with no enemy lane creep within WaveClearRadius (the wave is dead).
    FrontRadius: 1800,
    WaveClearRadius: 1000,
    // Visible enemy heroes this close to the bot (or to a camp) end a trip after the bot's reaction time (or rule the
    // camp out). The walk back ignores them: laning and retreat decide there.
    EnemyRadius: 1400,
    MaxCampDist: 2800,
    // How late after the next enemy wave reaches the front the bot may get back; it fights our creeps that long.
    LateTolerance: 5,
    // A stack may leave the front this much longer, since its gold arrives on a later trip.
    StackLateExtra: 8,
    WavePeriod: 30,
    // Prior seconds to clear a camp at RefLevel, scaled by RefLevel / level within LevelScale, plus StackedClearMul per
    // stack. Each bot then learns how much faster or slower it really is (Learn), within LearnClamp.
    ClearSec: { small: 7, medium: 10, large: 13, ancient: 18 } as Record<string, number>,
    RefLevel: 8,
    LevelScale: [0.6, 1.6],
    StackedClearMul: 0.8,
    Learn: 0.3,
    LearnClamp: [0.4, 2.5],
    // A camp left unfinished at leaveBy says the estimate was short: the bot's factor grows by this.
    LateGrowth: 1.15,
    AncientMinLevel: 12,
    // Relative gold of a camp; a stack counts StackValue of its camp's value, since it pays out later.
    Value: { small: 1, medium: 1.4, large: 1.9, ancient: 2.6 } as Record<string, number>,
    StackValue: 0.8,
    // A stack is planned when the bot reaches the stand point between StackMinWait and StackWaitMax before the hit.
    StackMinWait: 0.5,
    StackWaitMax: 10,
    Arrive: 300,
    ReturnArrive: 900,
    // Neutrals this far from the box centre still count as the camp's (they chase out of the box).
    CampRadius: 700,
    // A camp is seen empty when the bot is this close, the spot is visible and no neutral is there.
    EmptySight: 1200,
    NeutralScan: 1600,
    PlanEvery: 0.5,
    PreemptAfter: 1.0,
    ReturnMax: 25,
    // Errands that wait for the trip (camp jobs' JOB_FOCUS_MODES less rune, roam and team roam, which a core should still take).
    FocusMargin: 0.05,
};

export type FarmSettings = typeof DEFAULTS;

type Phase = "go" | "farm" | "stack" | "return";

interface Trip {
    team: number;
    lane: Lane;
    campIdx: number;
    type: Camps.CampType;
    phase: Phase;
    /** Next enemy wave at the lane front, and the latest time to be back there. */
    waveAt: number;
    deadline: number;
    /** Latest time to leave the current camp. */
    leaveBy: number;
    startedAt: number;
    camps: number;
    lastThinkAt?: number;
    returnFrom?: number;
    target?: Unit;
    /** When the bot first fought the current camp, and the clear estimate it was planned with (for Learn). */
    farmFrom?: number;
    estimate?: number;
    /** When a visible enemy hero first came within EnemyRadius; cleared once none is. */
    enemySince?: number;
}

export interface CampPlan {
    campIdx: number;
    type: Camps.CampType;
    stack: boolean;
    score: number;
    leaveBy: number;
    estimate: number;
    /** Stack: the minute whose stack second the hit lands on. */
    minute?: number;
}

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" ? merge(d, v) : v;
    }
    return result;
}

let cached: FarmSettings | undefined;
let trips: Record<number, Trip> = {};
let nextPlanAt: Record<number, number> = {};
/** Camps a trip found empty or cleared, by team then camp, as the minute it happened (they respawn on the next). */
let cleared: Record<number, Record<number, number>> = {};
let stackRolls: Record<number, { minute: number; ok: boolean }> = {};
/** Per bot: measured clear time over the prior estimate. */
let paceFactor: Record<number, number> = {};

export function Settings(): FarmSettings {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().FarmPattern) as FarmSettings;
    return cached;
}

export function ResetCache(): void {
    cached = undefined;
    trips = {};
    nextPlanAt = {};
    cleared = {};
    stackRolls = {};
    paceFactor = {};
}

export function IsActive(): boolean {
    return Config.IsFeatureEnabled("FarmPattern");
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function speedOf(bot: Unit): number {
    return math.max(bot.GetCurrentMovementSpeed(), 100);
}

function hpOf(bot: Unit): number {
    const max = bot.GetMaxHealth();
    return max > 0 ? bot.GetHealth() / max : 0;
}

function currentMinute(now: number): number {
    return math.floor(now / 60);
}

function clamp(v: number, range: number[]): number {
    return math.max(range[0], math.min(range[1], v));
}

/** When the next enemy wave reaches `front` on `lane`: waves leave the enemy spawner every WavePeriod from 0:00. */
export function NextWaveAt(team: number, lane: Lane, front: Vector, now: number): number | undefined {
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const path = PullTiming.LanePath(enemy, lane);
    if (path === undefined || path.length < 2) return undefined;
    const [along] = PullTiming.Along(path, front);
    const travel = along / LaneConfig.Settings().PullTiming.CreepSpeed;
    const period = Settings().WavePeriod;
    const k = math.max(0, math.ceil((now - travel) / period));
    return k * period + travel;
}

/** The prior clear time for a camp type at `level` with `stacks` extra sets of neutrals. */
export function PriorClearTime(type: Camps.CampType, level: number, stacks: number): number {
    const s = Settings();
    const scale = clamp(s.RefLevel / math.max(level, 1), s.LevelScale);
    return (s.ClearSec[type] ?? s.ClearSec.medium) * scale * (1 + s.StackedClearMul * stacks);
}

export function ClearTime(bot: Unit, type: Camps.CampType, stacks: number): number {
    return PriorClearTime(type, bot.GetLevel(), stacks) * (paceFactor[bot.GetPlayerID()] ?? 1);
}

export function PaceFactor(bot: Unit): number {
    return paceFactor[bot.GetPlayerID()] ?? 1;
}

function learnPace(bot: Unit, measured: number, prior: number): void {
    if (prior <= 0) return;
    const s = Settings();
    const pid = bot.GetPlayerID();
    const old = paceFactor[pid] ?? 1;
    paceFactor[pid] = clamp(old + s.Learn * (measured / prior - old), s.LearnClamp);
}

function eligiblePosition(bot: Unit): number | undefined {
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 1 && pos <= 3 ? pos : undefined;
}

/** Meepo's clones and Arc's tempest double share the hero's player ID, and intent leaves them out: so do trips. */
function sharesPlayerID(bot: Unit): boolean {
    return bot.GetUnitName() === "npc_dota_hero_meepo" || bot.HasModifier("modifier_arc_warden_tempest_double");
}

const IDLE_MODES: Record<number, boolean> = { [BotMode.Laning]: true, [BotMode.Farm]: true, [BotMode.None]: true };
const FOCUS_MODES: BotMode[] = [BotMode.Ward, BotMode.SideShop, BotMode.SecretShop];

/** Why the bot may not start a trip now, or undefined. */
export function StartGate(bot: Unit, now: number): string | undefined {
    const s = Settings();
    if (!bot.IsHero() || bot.IsIllusion() || sharesPlayerID(bot) || string.sub(bot.GetUnitName(), 1, 14) !== "npc_dota_hero_") return "unit";
    const pos = eligiblePosition(bot);
    if (pos === undefined) return "not-core";
    if (now < (s.StartTime[pos] ?? s.StartTime[1]) || now >= s.EndTime) return "time";
    if (bot.GetLevel() < (s.MinLevel[pos] ?? s.MinLevel[1])) return "level";
    if (hpOf(bot) < s.StartHP) return "low-hp";
    if (IDLE_MODES[bot.GetActiveMode()] !== true) return "busy-mode";
    if (Orders.GetFor(bot) !== undefined) return "has-order";
    if (LaneConfig.IsActive() && CampJobs.Active(bot)) return "camp-job";
    const retreat = Intent.Resolved(bot, BotMode.Retreat);
    if (retreat !== undefined && retreat >= s.Desire) return "retreat";
    return undefined;
}

function aliveUnits(list: UnitType): Unit[] {
    const out: Unit[] = [];
    for (const u of GetUnitList(list) ?? []) if (u !== null && u !== undefined && u.IsAlive()) out.push(u);
    return out;
}

function anyNear(units: Unit[], loc: Vector, radius: number): boolean {
    for (const u of units) if (dist2D(u.GetLocation(), loc) <= radius) return true;
    return false;
}

/** Heroes read once per plan rather than once per camp. */
interface Sight {
    enemies: Unit[];
    allies: Unit[];
}

function enemyCreepsNear(bot: Unit, radius: number): boolean {
    for (const c of bot.GetNearbyLaneCreeps(radius, true) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive()) return true;
    }
    return false;
}

/** The wave at the front is still alive: a bot standing back from it (ranged, zoned) must not count it as dead. */
function waveAlive(front: Vector, radius: number): boolean {
    for (const c of GetUnitList(UnitType.EnemyCreeps) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && LaneState.IsLaneCreepName(c.GetUnitName()) && dist2D(c.GetLocation(), front) <= radius) return true;
    }
    return false;
}

function campNeutrals(bot: Unit, center: Vector): Unit[] {
    const s = Settings();
    const out: Unit[] = [];
    for (const n of bot.GetNearbyNeutralCreeps(s.NeutralScan, false) ?? []) {
        if (n !== null && n !== undefined && n.IsAlive() && n.CanBeSeen() && dist2D(n.GetLocation(), center) <= s.CampRadius) out.push(n);
    }
    return out;
}

function allyInBox(bot: Unit, idx: number, allies: Unit[]): boolean {
    const pid = bot.GetPlayerID();
    for (const a of allies) if (a.GetPlayerID() !== pid && Camps.InBox(idx, a.GetLocation(), 300)) return true;
    return false;
}

/** Another core's trip is headed for or farming the camp (only seen when modules are shared per team). */
function claimedByAlly(bot: Unit, idx: number): boolean {
    const pid = bot.GetPlayerID();
    const team = bot.GetTeam();
    for (const [other, trip] of pairs(trips)) {
        if (other !== pid && trip.team === team && trip.campIdx === idx && trip.phase !== "return") return true;
    }
    return false;
}

function markCleared(team: number, idx: number, now: number): void {
    cleared[team] = cleared[team] ?? {};
    cleared[team][idx] = currentMinute(now);
}

function knownEmpty(bot: Unit, team: number, idx: number, center: Vector, now: number): boolean {
    if (cleared[team]?.[idx] === currentMinute(now)) return true;
    return dist2D(bot.GetLocation(), center) <= Settings().EmptySight && IsLocationVisible(center) && campNeutrals(bot, center).length === 0;
}

function campOpen(bot: Unit, team: number, idx: number, center: Vector, now: number, sight: Sight): boolean {
    if (knownEmpty(bot, team, idx, center, now)) return false;
    if (allyInBox(bot, idx, sight.allies) || claimedByAlly(bot, idx) || Stacking.ReservedByAlly(idx, bot.GetPlayerID())) return false;
    if (Orders.AvoidsLocation(bot, center)) return false;
    return !anyNear(sight.enemies, center, Settings().EnemyRadius);
}

function stackRoll(bot: Unit, minute: number): boolean {
    const pid = bot.GetPlayerID();
    const r = stackRolls[pid];
    if (r !== undefined && r.minute === minute) return r.ok;
    const ok = LaneConfig.Roll(LaneConfig.Curve("StackAttempt", LaneConfig.SkillOf(bot)));
    stackRolls[pid] = { minute, ok };
    return ok;
}

function stackPlan(bot: Unit, spawner: Camps.Spawner, from: Vector, front: Vector, now: number, deadline: number, value: number): CampPlan | undefined {
    if (!LaneConfig.IsActive() || !LaneConfig.IsOn("Stack")) return undefined;
    const s = Settings();
    const lane = LaneConfig.Settings();
    if (Stacking.StackCount(spawner.idx) >= lane.Thresholds.StackMaxCampCount) return undefined;
    const data = Camps.ByIdx(spawner.idx, spawner.team);
    if (data === undefined || data.stack === undefined) return undefined;
    const speed = speedOf(bot);
    const period = lane.Timing.PullPeriod;
    const aggroAt = CampJobs.NextAggroTime(now, [Stacking.AggroSec(data)], period);
    const wait = aggroAt - (now + dist2D(from, Stacking.StandPoint(spawner, data)) / speed);
    if (wait < s.StackMinWait || wait > s.StackWaitMax) return undefined;
    const minute = math.floor(aggroAt / period);
    const done = (minute + 1) * period + lane.Timing.StackExitUntil + dist2D(Camps.BoxCenter(spawner), front) / speed;
    if (done > deadline + s.StackLateExtra) return undefined;
    // The roll comes last so a minute's roll is only spent on a stack that could run.
    if (!stackRoll(bot, minute)) return undefined;
    return { campIdx: spawner.idx, type: spawner.type, stack: true, score: (value * s.StackValue) / (done - now), leaveBy: done, estimate: 0, minute };
}

/**
 * The best camp of the bot's own jungle within MaxCampDist of `front` that it can clear from `from` and still be back
 * at `front` by `deadline`, or stack on the way; by value per second of trip.
 */
export function PlanCamp(bot: Unit, from: Vector, front: Vector, now: number, deadline: number): CampPlan | undefined {
    const s = Settings();
    const team = bot.GetTeam();
    const speed = speedOf(bot);
    const level = bot.GetLevel();
    const sight: Sight = { enemies: aliveUnits(UnitType.EnemyHeroes), allies: aliveUnits(UnitType.AlliedHeroes) };
    let best: CampPlan | undefined;
    for (const spawner of Camps.Spawners()) {
        if (spawner.team !== team) continue;
        if (spawner.type === "ancient" && level < s.AncientMinLevel) continue;
        const center = Camps.BoxCenter(spawner);
        if (dist2D(center, front) > s.MaxCampDist || !campOpen(bot, team, spawner.idx, center, now, sight)) continue;
        const stacks = Stacking.StackCount(spawner.idx);
        const value = (s.Value[spawner.type] ?? 1) * (1 + stacks);
        const back = dist2D(center, front) / speed;
        const clearTime = ClearTime(bot, spawner.type, stacks);
        const total = dist2D(from, center) / speed + clearTime + back;
        if (now + total <= deadline) {
            const score = value / total;
            if (best === undefined || score > best.score)
                best = { campIdx: spawner.idx, type: spawner.type, stack: false, score, leaveBy: deadline - back, estimate: clearTime };
        }
        const stack = stackPlan(bot, spawner, from, front, now, deadline, value);
        if (stack !== undefined && (best === undefined || stack.score > best.score)) best = stack;
    }
    return best;
}

/** The lane whose wave the trip is timed against: the assigned lane while laning, then the nearest lane front. */
function homeLane(bot: Unit): Lane {
    if (LaneConfig.InLaningPhase()) return bot.GetAssignedLane();
    let best = Lane.Mid;
    let bestDist = math.huge;
    for (const lane of [Lane.Top, Lane.Mid, Lane.Bot]) {
        const d = GetUnitToLocationDistance(bot, GetLaneFrontLocation(bot.GetTeam(), lane, 0));
        if (d < bestDist) {
            best = lane;
            bestDist = d;
        }
    }
    return best;
}

function fmt(v: number | undefined): string {
    return v === undefined ? "-" : string.format("%.1f", v);
}

function log(bot: Unit, event: string, trip: Trip, extra: [string, any][] = []): void {
    if (!Telemetry.IsEnabled() && !HDebug.IsEnabled()) return;
    const fields: [string, any][] = [
        ["pid", bot.GetPlayerID()],
        ["camp", trip.campIdx],
        ["type", trip.type],
        ["phase", trip.phase],
        ["waveAt", fmt(trip.waveAt)],
        ["leaveBy", fmt(trip.leaveBy)],
        ...extra,
    ];
    Telemetry.Event(event, fields);
    const parts: string[] = [];
    for (const [k, v] of fields) parts.push(`${k}=${tostring(v)}`);
    HDebug.Log("farm", `${event} ${parts.join(" ")}`);
}

/** Points the trip at `plan`; a stack starts camp_jobs' stack job for the core. False when that job would not start. */
function adopt(bot: Unit, trip: Trip, plan: CampPlan): boolean {
    if (plan.stack && !CampJobs.Start(bot, { kind: "stack", campIdx: plan.campIdx, minute: plan.minute, core: true })) return false;
    trip.campIdx = plan.campIdx;
    trip.type = plan.type;
    trip.leaveBy = plan.leaveBy;
    trip.phase = plan.stack ? "stack" : "go";
    trip.estimate = plan.stack ? undefined : PriorClearTime(plan.type, bot.GetLevel(), Stacking.StackCount(plan.campIdx));
    trip.farmFrom = undefined;
    trip.target = undefined;
    trip.camps++;
    return true;
}

function schedule(bot: Unit, now: number): boolean {
    const s = Settings();
    if (StartGate(bot, now) !== undefined) return false;
    const team = bot.GetTeam();
    const lane = homeLane(bot);
    const front = GetLaneFrontLocation(team, lane, 0);
    if (GetUnitToLocationDistance(bot, front) > s.FrontRadius) return false;
    if (enemyCreepsNear(bot, s.WaveClearRadius) || waveAlive(front, s.WaveClearRadius) || anyNear(aliveUnits(UnitType.EnemyHeroes), bot.GetLocation(), s.EnemyRadius)) return false;
    const waveAt = NextWaveAt(team, lane, front, now);
    if (waveAt === undefined) return false;
    const deadline = waveAt + s.LateTolerance;
    const plan = PlanCamp(bot, bot.GetLocation(), front, now, deadline);
    if (plan === undefined) return false;
    const trip: Trip = { team, lane, campIdx: plan.campIdx, type: plan.type, phase: "go", waveAt, deadline, leaveBy: plan.leaveBy, startedAt: now, camps: 0 };
    if (!adopt(bot, trip, plan)) return false;
    trips[bot.GetPlayerID()] = trip;
    log(bot, "farm_trip_start", trip, [["lane", lane], ["pace", fmt(PaceFactor(bot))]]);
    return true;
}

function releaseClaims(bot: Unit): void {
    Intent.ReleaseSource(bot, "farm:hold");
    Intent.ReleaseSource(bot, "farm:focus");
}

function end(bot: Unit, trip: Trip, why: string): void {
    delete trips[bot.GetPlayerID()];
    releaseClaims(bot);
    const extra: [string, any][] = [["why", why], ["camps", trip.camps], ["secs", fmt(DotaTime() - trip.startedAt)]];
    if (why === "preempted" || why === "mode-end") {
        const to = bot.GetActiveMode();
        extra.push(["to", HDebug.ModeName(to)]);
        if (Intent.IsActive()) extra.push(["toBy", Intent.Explain(bot, to)]);
    }
    log(bot, "farm_trip_end", trip, extra);
}

function toReturn(bot: Unit, trip: Trip, now: number, why: string): void {
    if (why === "late" && trip.phase === "farm" && trip.farmFrom !== undefined) {
        const s = Settings();
        const pid = bot.GetPlayerID();
        paceFactor[pid] = clamp((paceFactor[pid] ?? 1) * s.LateGrowth, s.LearnClamp);
    }
    trip.phase = "return";
    trip.returnFrom = now;
    trip.target = undefined;
    releaseClaims(bot);
    log(bot, "farm_trip_return", trip, [["why", why]]);
}

/** Enemy heroes near the bot for longer than its reaction time (perception has already delayed when they show up). */
function threatened(bot: Unit, trip: Trip, now: number): boolean {
    if (trip.phase === "return" || !anyNear(aliveUnits(UnitType.EnemyHeroes), bot.GetLocation(), Settings().EnemyRadius)) {
        trip.enemySince = undefined;
        return false;
    }
    trip.enemySince = trip.enemySince ?? now;
    return now - trip.enemySince >= Profile.Get(bot).reactBase;
}

/** Why a live trip must end now, or undefined. */
function stopReason(bot: Unit, trip: Trip, now: number): string | undefined {
    const s = Settings();
    if (!bot.IsAlive()) return "dead";
    if (hpOf(bot) < s.AbortHP) return "low-hp";
    if (Orders.GetFor(bot) !== undefined) return "order";
    if (threatened(bot, trip, now)) return "enemy";
    // A stack job owns farm's Think while it runs, so a stale Think only means pre-emption under another mode.
    if (now - (trip.lastThinkAt ?? trip.startedAt) > s.PreemptAfter && bot.GetActiveMode() !== BotMode.Farm) return "preempted";
    if (trip.phase === "return") {
        if (GetUnitToLocationDistance(bot, GetLaneFrontLocation(trip.team, trip.lane, 0)) <= s.ReturnArrive) return "back";
        if (enemyCreepsNear(bot, s.WaveClearRadius)) return "wave";
        if (now - (trip.returnFrom ?? now) > s.ReturnMax) return "return-timeout";
    }
    return undefined;
}

/** Camp jobs' retreatThreat: a hero hitting or targeting the bot, or a tower, lifts the hold; neutrals do not. */
function retreatThreat(bot: Unit): boolean {
    const s = Settings();
    if (hpOf(bot) < s.HoldRetreatHP || bot.WasRecentlyDamagedByAnyHero(s.HoldHeroHit) || bot.WasRecentlyDamagedByTower(s.HoldHeroHit)) return true;
    for (const e of aliveUnits(UnitType.EnemyHeroes)) if (e.GetAttackTarget() === bot) return true;
    return false;
}

/**
 * Claims for a trip on its way to or in a camp: retreat held below it (so chasing neutrals do not send the core home)
 * and the errands capped below it. Posted every round from farm's GetDesire; both drop on the walk back.
 */
function postClaims(bot: Unit, trip: Trip): void {
    if (trip.phase === "return") return;
    const s = Settings();
    const cap = s.Desire - s.FocusMargin;
    if (!retreatThreat(bot)) Intent.Claim(bot, { source: "farm:hold", tier: "CAMP_JOB", mode: BotMode.Retreat, cap });
    else Intent.Release(bot, "farm:hold", BotMode.Retreat);
    for (const mode of FOCUS_MODES) Intent.Claim(bot, { source: "farm:focus", tier: "CAMP_JOB", mode, cap });
}

/** mode_farm_generic GetDesire: the trip's desire, 0 when the bot is not on (and does not start) a trip. */
export function Desire(bot: Unit): number {
    if (!IsActive()) return 0;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const trip = trips[pid];
    if (trip !== undefined) {
        const why = stopReason(bot, trip, now);
        if (why !== undefined) {
            end(bot, trip, why);
            return 0;
        }
        postClaims(bot, trip);
        return Settings().Desire;
    }
    if (!bot.IsAlive() || now < (nextPlanAt[pid] ?? -math.huge)) return 0;
    nextPlanAt[pid] = now + Settings().PlanEvery;
    if (!schedule(bot, now)) return 0;
    postClaims(bot, trips[pid]);
    return Settings().Desire;
}

function nextOrReturn(bot: Unit, trip: Trip, now: number, why: string, depth: number): boolean {
    const front = GetLaneFrontLocation(trip.team, trip.lane, 0);
    const plan = PlanCamp(bot, bot.GetLocation(), front, now, trip.deadline);
    if (plan !== undefined && adopt(bot, trip, plan)) {
        log(bot, "farm_trip_next", trip, [["after", why]]);
        return step(bot, trip, now, depth + 1);
    }
    toReturn(bot, trip, now, why);
    return step(bot, trip, now, depth + 1);
}

/** Keeps the current target while it lives and stays with the camp, so re-targeting does not cancel attacks. */
function pickTarget(trip: Trip, neutrals: Unit[]): Unit {
    const current = trip.target;
    if (current !== undefined && !current.IsNull()) {
        for (const n of neutrals) if (n === current) return current;
    }
    let best = neutrals[0];
    for (const u of neutrals) if (u.GetHealth() < best.GetHealth()) best = u;
    trip.target = best;
    return best;
}

const MAX_STEPS = 4;

function step(bot: Unit, trip: Trip, now: number, depth: number = 0): boolean {
    if (depth > MAX_STEPS) return false;
    if (trip.phase === "stack") {
        // Farm's Think ran CampJobThink before this hook, so a job adopted this frame (a chained stack) is run here,
        // and the frame is never left to upstream farm.
        if (CampJobs.Active(bot)) {
            CampJobs.Think(bot);
            return true;
        }
        return nextOrReturn(bot, trip, now, "stacked", depth);
    }
    if (trip.phase === "return") {
        bot.Action_MoveToLocation(GetLaneFrontLocation(trip.team, trip.lane, 0));
        return true;
    }
    const spawner = Camps.SpawnerByIdx(trip.campIdx);
    if (spawner === undefined) {
        toReturn(bot, trip, now, "no-camp");
        return step(bot, trip, now, depth + 1);
    }
    if (now >= trip.leaveBy) {
        toReturn(bot, trip, now, "late");
        return step(bot, trip, now, depth + 1);
    }
    const center = Camps.BoxCenter(spawner);
    const neutrals = campNeutrals(bot, center);
    const there = GetUnitToLocationDistance(bot, center) <= Settings().Arrive;
    if (trip.phase === "go") {
        if (!there && neutrals.length === 0) {
            bot.Action_MoveToLocation(center);
            return true;
        }
        trip.phase = "farm";
    }
    if (neutrals.length === 0) {
        if (!there) {
            bot.Action_MoveToLocation(center);
            return true;
        }
        if (trip.farmFrom !== undefined && trip.estimate !== undefined) learnPace(bot, now - trip.farmFrom, trip.estimate);
        markCleared(trip.team, trip.campIdx, now);
        Stacking.ClearStack(trip.campIdx);
        return nextOrReturn(bot, trip, now, trip.farmFrom !== undefined ? "cleared" : "empty", depth);
    }
    const target = pickTarget(trip, neutrals);
    // Timed from the first frame in attack range, so the walk in (camps are seen from up to ~2,000) is not clear time.
    if (trip.farmFrom === undefined && GetUnitToUnitDistance(bot, target) <= bot.GetAttackRange() + 100) trip.farmFrom = now;
    bot.Action_AttackUnit(target, true);
    return true;
}

function overlay(bot: Unit, trip: Trip, now: number): void {
    HDebug.Text(
        bot,
        "farm",
        string.format("trip %s camp=%d %s wave=%+.1f leave=%+.1f pace=%.2f", trip.phase, trip.campIdx, trip.type, trip.waveAt - now, trip.leaveBy - now, PaceFactor(bot))
    );
}

/** mode_farm_generic Think: true when the trip owns this frame. */
export function Think(bot: Unit): boolean {
    if (!IsActive()) return false;
    const trip = trips[bot.GetPlayerID()];
    if (trip === undefined) return false;
    const now = DotaTime();
    trip.lastThinkAt = now;
    overlay(bot, trip, now);
    return step(bot, trip, now);
}

export function OnEnd(bot: Unit): void {
    if (!IsActive()) return;
    const trip = trips[bot.GetPlayerID()];
    if (trip !== undefined) end(bot, trip, "mode-end");
}

/** mode_farm_generic: a run started, so the trip ends now. */
export function Abort(bot: Unit, why: string): void {
    if (!IsActive()) return;
    const trip = trips[bot.GetPlayerID()];
    if (trip !== undefined) end(bot, trip, why);
}

export function Current(bot: Unit): Readonly<Trip> | undefined {
    return trips[bot.GetPlayerID()];
}
