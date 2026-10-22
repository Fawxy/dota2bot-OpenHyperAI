/**
 * Camp-job executor (task 07): full, half and double pulls, stacks and counter-play camp contests run from
 * mode_farm_generic as timed jobs.
 * The job window only gates a job's start (PF2); once started the job keeps its desire until it is done or
 * aborted. Each pull's outcome is measured as the divert fraction, each stack's as the box's neutral count after
 * the minute, and both are logged for tools/replay-mining.
 */
import { BotMode, Item, Team, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LanePlanner from "bots/FunLib/humaniser/lane_planner";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";
import * as LastHitSkill from "bots/FunLib/humaniser/last_hit_skill";

export type JobKind = "full_pull" | "half_pull" | "stack_pull" | "double_pull" | "stack" | "contest";

export interface JobRequest {
    kind: JobKind;
    campIdx: number;
    secondCampIdx?: number;
    forced?: boolean;
    minute?: number;
    /** Contest: the enemy seen pulling, attacked while visible. */
    targetPid?: number;
    /** Pre-contest: the expected enemy aggro, awaited at a lookout on their pull path. */
    preAggroAt?: number;
    /** Take: a non-owner laner last-hits their pulled wave at the camp instead of hitting the puller. */
    take?: boolean;
}

export interface Job extends JobRequest {
    phase: "travel" | "wait" | "aggro" | "lead" | "watch" | "exit" | "lookout" | "return" | "done";
    aggroAt: number;
    plannedSec: number;
    path: Vector[];
    meet?: Vector;
    startedAt: number;
    peakDivert: number;
    waveSize: number;
    /** Camp being worked now: campIdx, or a double pull's hard camp (secondCampIdx) until it is hit. */
    activeCamp: number;
    stand: Vector;
    waypoint: number;
    stage: number;
    /** Double pull: the small camp's stand and hit, taken up once the hard camp has been hit. */
    chain?: { stand: Vector; aggroAt: number };
    telegraphed: boolean;
    baseAggro: number;
    actualAggro?: number;
    aggroTarget?: Unit;
    /** Pre-contest: when the puller was first seen from the lookout; ContestMax counts from here. */
    attackFrom?: number;
    /** Take: the last-hit swing in flight, the swings made, and when pulled creeps were last seen or the stand reached. */
    swing?: { target: Unit; at: number };
    swings?: number;
    creepSeenAt?: number;
    arrivedAt?: number;
    /** GameTime() of the attack order, the clock GetLastAttackTime() uses. */
    aggroOrderedAt?: number;
    /** The camp whose stand point was moved in toward its spawner origin because no neutral was seen from it. */
    approachedCamp?: number;
    watchFrom?: number;
    /** When the pulled wave should reach the meet point (wave-timed pulls); the watch waits for it. */
    waveAt?: number;
    /** Pull: the aggro slot before any live shift, which `skipped` and the scheduler compare against. */
    slot?: number;
    timing?: PullTiming.TimingSource;
    sampledAt?: number;
    /** Stack: the next :00 + StackExitUntil, when the walk-off ends. */
    exitUntil?: number;
    stackBefore?: number;
    lastAttackAt?: number;
    /** Farm's Think has run this job at least once; until then an abort leaves the cycle free. */
    acted?: boolean;
    lastThinkAt?: number;
    /** A desire query has come since the last Think: the start of a possible pre-emption. */
    unthought?: boolean;
    /** The camp ping for a human partner was considered (once per job). */
    pinged?: boolean;
    /** lane_job_hold was logged: the start gate failed while the commitment kept the job going. */
    heldNoted?: boolean;
    /** Retreat held below the job while the camp chases the bot ("on"); "off" once a real threat released it for good. */
    retreatHold?: "on" | "off";
    /** Tango and clarity each used at most once per pull; until supplyUntil, or the item's modifier shows, the job gives no order. */
    tangoUsed?: boolean;
    clarityUsed?: boolean;
    supplyUntil?: number;
    supplyModifier?: string;
}

/**
 * A stack whose aggro landed; its outcome is read from the next :00 + StackOutcomeAt to :00 + StackOutcomeUntil,
 * after the job itself ended. The stacked neutrals walk back into the box over those seconds, so the peak count is kept.
 */
interface PendingStack {
    campIdx: number;
    minute: number;
    at: number;
    until: number;
    peak?: number;
    before: number;
    aggro: number;
    planned: number;
    type: Camps.CampType;
}

const PULL_KINDS: Record<string, boolean> = { full_pull: true, half_pull: true, stack_pull: true, double_pull: true };
const PULL_TECHS: Record<string, JobKind> = { full_pull: "full_pull", half_pull: "half_pull", stack_pull: "stack_pull" };
// The console parser reads `kind=%w+` and treats `half` as the half-pull timing.
const LOG_KIND: Record<JobKind, string> = {
    full_pull: "full",
    half_pull: "half",
    stack_pull: "stackpull",
    double_pull: "double",
    stack: "stack",
    contest: "contest",
};
const FLAG_OF: Record<JobKind, LaneConfig.LaneFlag> = {
    full_pull: "FullPull",
    half_pull: "HalfPull",
    stack_pull: "StackPull",
    double_pull: "FullPull",
    stack: "Stack",
    contest: "CounterPlay",
};
const JOB_FLAGS: LaneConfig.LaneFlag[] = ["FullPull", "HalfPull", "StackPull"];
// jmz_func's melee/ranged split for attack timing.
const RANGED_ATTACK_RANGE = 326;

let jobs: Record<number, Job> = {};
let doneCycle: Record<number, number> = {};
let pendingStacks: Record<number, PendingStack> = {};
/** The aggro time of a job aborted before it acted, so the same attempt is not registered again. */
let skipped: Record<number, number> = {};
/** Gates of the bot's lane_plan events in its latest wave cycle. */
let planNoted: Record<number, { cycle: number; gates: Record<string, boolean> }> = {};
/** The core's view of its support leaving for a camp: when it started, and how it was known. */
let covering: Record<number, { since: number; via: string; partner: number; kind: string }> = {};
/** Until when a bot starts no pre-contest in that lane: the last one found the enemy not pulling. */
let preContestRest: Record<number, { lane: number; until: number }> = {};

export function ResetCache(): void {
    jobs = {};
    doneCycle = {};
    pendingStacks = {};
    skipped = {};
    planNoted = {};
    covering = {};
    preContestRest = {};
}

function settings(): LaneConfig.LaneSettings {
    return LaneConfig.Settings();
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function cycleOf(time: number): number {
    return math.floor(time / settings().Timing.WaveCycle);
}

function commitTech(kind: JobKind): LaneConfig.Technique | "contest" {
    if (kind === "double_pull") return "full_pull";
    if (kind === "contest") return "contest";
    return kind as LaneConfig.Technique;
}

// ---------------------------------------------------------------------------------------------- pure helpers

export function AggroSecondsFor(kind: JobKind, data: Camps.CampJobData): number[] {
    if (kind === "stack" || kind === "contest") return data.stack !== undefined ? [Stacking.AggroSec(data)] : [];
    return data.pull !== undefined ? PullTiming.SeedSeconds(data.pull, kind === "half_pull") : [];
}

export function NextAggroTime(dotaTime: number, seconds: number[], period: number): number {
    const base = math.floor(dotaTime / period) * period;
    let best = math.huge;
    for (const s of seconds) {
        for (const t of [base + s, base + period + s]) if (t >= dotaTime && t < best) best = t;
    }
    return best;
}

export function TravelTime(dist: number, speed: number): number {
    return dist / math.max(speed, 1);
}

/** The point `dist` along the polyline from `origin` through `path`; the last point when the polyline is shorter. */
export function LookoutPoint(origin: Vector, path: Vector[], dist: number): Vector {
    let from = origin;
    let left = dist;
    for (const to of path) {
        const seg = dist2D(from, to);
        if (seg >= left && seg > 0) {
            const f = left / seg;
            return Vector(from.x + (to.x - from.x) * f, from.y + (to.y - from.y) * f, from.z);
        }
        left -= seg;
        from = to;
    }
    return from;
}

export function WindowOpen(now: number, aggroAt: number, travel: number): boolean {
    const t = settings().Timing;
    return now >= aggroAt - travel - t.JobStartSlack && now <= aggroAt + t.JobStartLate;
}

/** Camps hold neutrals for the whole minute containing `time` only from their first spawn on. */
export function CampsUp(time: number): boolean {
    const t = settings().Timing;
    return math.floor(time / t.PullPeriod) * t.PullPeriod >= t.NeutralFirstSpawn;
}

function isNeutral(unit: Unit | null | undefined): boolean {
    return unit !== null && unit !== undefined && unit.GetTeam() === Team.Neutral;
}

export function MeasureDivert(allyCreeps: Unit[], waveSize: number): number {
    let n = 0;
    for (const c of allyCreeps) if (isNeutral(c.GetAttackTarget())) n++;
    return math.min(1, n / math.max(waveSize, 1));
}

export function Grade(kind: JobKind, divert: number): string {
    const t = settings().Thresholds;
    if (kind === "half_pull") {
        if (divert > t.HalfPullMax) return "mistake:half->full";
        if (divert < t.HalfPullMin) return "mistake:weak-pull";
        return "ok";
    }
    if (divert > t.FullPullMin) return "ok";
    return divert > 0 ? "mistake:weak-pull" : "mistake:no-divert";
}

// ---------------------------------------------------------------------------------------------- job setup

function noisy(v: Vector, noise: number): Vector {
    const r = RandomVector(noise);
    return Vector(v.x + r.x, v.y + r.y, v.z);
}

function standFor(spawner: Camps.Spawner, firstWaypoint: Vector): Vector {
    return Camps.StandPoint(spawner, firstWaypoint, settings().Radii.StandOffset);
}

const leadPath = PullTiming.LeadPath;

function timingFor(kind: JobKind, data: Camps.CampJobData, meet?: Vector): PullTiming.PullTiming {
    return PullTiming.ForCamp(data, kind === "half_pull", meet);
}

interface DoubleGeometry {
    why?: string;
    /** The hard camp's hit lands this long before the small camp's. */
    before: number;
    /** The hard camp reaches the meet point this long after the wave (negative: before it). */
    late: number;
    /** The bot's walk between the two stands. */
    gap: number;
    hardStand?: Vector;
}

/**
 * The classic double pull: hit the hard camp from its side facing the small camp, walk to the small camp's stand, hit
 * it on its own second and lead both; the hard camp follows and must reach the meet point by DoublePullJoin after the
 * wave. The reverse (the hard camp led in once the small one engaged) cannot fit on 7.41: evil_1 / good_2 are 6-9 s of
 * neutral walk from the small camp's meet plus the bot's walk there, so they would arrive 10-16 s after the wave.
 * `why`: no-camp, no-wave (the small camp is not wave-timed, so the hard camp cannot be placed), far, join.
 */
export function DoubleGeometry(small: Camps.CampJobData, hard: Camps.CampJobData, speed: number): DoubleGeometry {
    const smallSp = Camps.SpawnerByIdx(small.campIdx);
    const hardSp = Camps.SpawnerByIdx(hard.campIdx);
    if (small.pull === undefined || smallSp === undefined || hardSp === undefined) return { why: "no-camp", before: 0, late: 0, gap: 0 };
    const timing = timingFor("full_pull", small);
    if (timing.waveAfter === undefined) return { why: "no-wave", before: 0, late: 0, gap: 0 };
    const cfg = settings();
    const exact = leadPath(small.pull, small.pull.meetPoint);
    const smallStand = standFor(smallSp, exact[0]);
    const hardStand = Camps.StandPoint(hardSp, smallStand, cfg.Radii.StandOffset);
    const gap = TravelTime(dist2D(hardStand, smallStand), speed);
    const before = gap + cfg.Timing.DoublePullHitGap;
    const hardSpeed = (cfg.PullTiming.NeutralSpeed as Record<string, number>)[hard.type] ?? 300;
    const late = PullTiming.WalkLength(hardSp.location, [smallStand, ...exact]) / hardSpeed - before - timing.waveAfter;
    let why: string | undefined;
    if (gap > cfg.Timing.DoublePullMaxGap) why = "far";
    else if (late > cfg.Timing.DoublePullJoin) why = "join";
    return { why, before, late, gap, hardStand };
}

function hpOk(bot: Unit): boolean {
    const maxHP = bot.GetMaxHealth();
    return maxHP > 0 && bot.GetHealth() / maxHP >= settings().Thresholds.JobMinHP;
}

/** Why a pull or stack should not start now, else undefined. Forced (debug) jobs skip it. */
function startBlocked(bot: Unit): string | undefined {
    const maxHP = bot.GetMaxHealth();
    if (maxHP <= 0 || bot.GetHealth() / maxHP < settings().Thresholds.JobStartHP) return "low-hp";
    // A job farm could only win in retreat's dip ends as mode-end the next round (console.9055994510, mirana 4:49).
    const retreat = Intent.Resolved(bot, BotMode.Retreat);
    if (retreat !== undefined && retreat >= settings().Timing.JobDesire) return "retreat";
    return undefined;
}

function travelTo(bot: Unit, loc: Vector): number {
    return TravelTime(GetUnitToLocationDistance(bot, loc), bot.GetCurrentMovementSpeed());
}

function dataLabel(data: Camps.CampJobData): string {
    return data.unverified === true ? "unverified" : data.source;
}

function register(bot: Unit, job: Job, data: Camps.CampJobData): void {
    jobs[bot.GetPlayerID()] = job;
    LanePlanner.Commit(bot, commitTech(job.kind));
    const fields: [string, any][] = [
        ["pid", bot.GetPlayerID()],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
        ["key", data.key],
        ["data", dataLabel(data)],
        ["aggroAt", job.aggroAt],
        ["forced", job.forced === true],
        ["timing", job.timing ?? "seed"],
    ];
    if (job.preAggroAt !== undefined) fields.push(["pre", 1]);
    if (job.take === true) fields.push(["take", 1]);
    Telemetry.Event("lane_job_start", fields);
    HDebug.Log(
        "lane",
        string.format(
            "job-start pid=%d kind=%s camp=%d key=%s data=%s aggroAt=%.1f forced=%s timing=%s",
            bot.GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            data.key ?? "-",
            dataLabel(data),
            job.aggroAt,
            tostring(job.forced === true),
            job.timing ?? "seed"
        )
    );
}

function startStack(bot: Unit, req: JobRequest): boolean {
    const data = Camps.ByIdx(req.campIdx);
    const spawner = Camps.SpawnerByIdx(req.campIdx);
    if (data === undefined || data.stack === undefined || spawner === undefined) return false;
    const cfg = settings();
    const skill = LaneConfig.SkillOf(bot);
    const now = DotaTime();
    const period = cfg.Timing.PullPeriod;
    const aggroSec = Stacking.AggroSec(data);

    // Draw order (PF10): Gauss (2) for the jitter, then one RandomVector for the stand and each exit waypoint.
    const jitter = LaneConfig.Jitter(skill);
    const noise = LaneConfig.Curve("PathNoise", skill);
    const stand = noisy(Stacking.StandPoint(spawner, data), noise);
    const path = data.stack.exitPath.map((p) => noisy(p, noise));

    let base = NextAggroTime(now, [aggroSec], period);
    if (req.forced === true && base < now + travelTo(bot, stand)) base = NextAggroTime(now + travelTo(bot, stand), [aggroSec], period);
    const minuteStart = base - aggroSec;
    const exitUntil = minuteStart + period + cfg.Timing.StackExitUntil;
    Stacking.Reserve(req.campIdx, bot.GetPlayerID(), exitUntil);

    register(
        bot,
        {
            ...req,
            minute: math.floor(base / period),
            phase: "travel",
            aggroAt: base + jitter,
            plannedSec: aggroSec,
            path,
            startedAt: now,
            peakDivert: 0,
            waveSize: 0,
            activeCamp: req.campIdx,
            stand,
            waypoint: 0,
            stage: 1,
            telegraphed: false,
            baseAggro: base,
            exitUntil,
        },
        data
    );
    return true;
}

/**
 * Started only by counterplay: walk to the enemy pull camp and hit the puller while it stays visible. A pre-contest
 * (preAggroAt) first waits at a lookout on their pull path for the expected puller.
 */
function startContest(bot: Unit, req: JobRequest): boolean {
    const data = Camps.ByIdx(req.campIdx);
    const spawner = Camps.SpawnerByIdx(req.campIdx);
    if (data === undefined || spawner === undefined) return false;
    const now = DotaTime();
    let stand = Camps.BoxCenter(spawner);
    if (req.preAggroAt !== undefined) {
        if (data.pull === undefined) return false;
        stand = LookoutPoint(spawner.location, PullTiming.LeadPath(data.pull, data.pull.meetPoint), settings().Radii.PreContestStand);
    }
    register(
        bot,
        {
            ...req,
            phase: req.preAggroAt !== undefined ? "lookout" : "travel",
            aggroAt: req.preAggroAt ?? now,
            plannedSec: 0,
            path: [stand],
            startedAt: now,
            peakDivert: 0,
            waveSize: 0,
            activeCamp: req.campIdx,
            stand,
            waypoint: 0,
            stage: 1,
            telegraphed: true,
            baseAggro: now,
        },
        data
    );
    return true;
}

export function Start(bot: Unit, req: JobRequest): boolean {
    if (req.kind === "stack") return startStack(bot, req);
    if (!hpOk(bot)) return false;
    if (req.kind === "contest") return startContest(bot, req);
    if (PULL_KINDS[req.kind] !== true) return false;
    const data = Camps.ByIdx(req.campIdx, bot.GetTeam());
    const spawner = Camps.SpawnerByIdx(req.campIdx);
    if (data === undefined || data.pull === undefined || spawner === undefined) return false;
    const timing = timingFor(req.kind, data);
    const seconds = timing.seconds;
    if (seconds.length === 0) return false;
    const cfg = settings();
    const skill = LaneConfig.SkillOf(bot);
    const now = DotaTime();
    const period = cfg.Timing.PullPeriod;

    // Draw order (PF10): Gauss (2) for the jitter, then one RandomVector per stand and lead waypoint (a double's hard stand last).
    const jitter = LaneConfig.Jitter(skill);
    const meet = req.kind === "half_pull" ? data.pull.halfMeetPoint ?? data.pull.meetPoint : data.pull.meetPoint;
    const noise = LaneConfig.Curve("PathNoise", skill);
    const exact = leadPath(data.pull, meet);
    const stand = noisy(standFor(spawner, exact[0]), noise);
    const path = exact.map((p) => noisy(p, noise));
    let first: { camp: number; stand: Vector; before: number } | undefined;
    if (req.kind === "double_pull") {
        const hard = req.secondCampIdx !== undefined ? Camps.ByIdx(req.secondCampIdx, bot.GetTeam()) : undefined;
        const g = hard !== undefined ? DoubleGeometry(data, hard, bot.GetCurrentMovementSpeed()) : undefined;
        if (hard === undefined || g === undefined || g.why !== undefined || g.hardStand === undefined) return false;
        first = { camp: hard.campIdx, stand: noisy(g.hardStand, noise), before: g.before };
    }

    let base = NextAggroTime(now - cfg.Timing.JobStartLate, seconds, period);
    if (req.forced === true && base < now + travelTo(bot, stand)) base = NextAggroTime(now + travelTo(bot, stand), seconds, period);
    const slot = base;
    const shift = PullTiming.LiveShift(timing, base, now);
    if (shift !== undefined) base += shift;

    const job: Job = {
        ...req,
        phase: "travel",
        aggroAt: base + jitter - (first?.before ?? 0),
        chain: first !== undefined ? { stand, aggroAt: base + jitter } : undefined,
        plannedSec: base % period,
        path,
        meet,
        slot,
        waveAt: timing.waveAfter !== undefined ? base + timing.waveAfter : undefined,
        timing: shift !== undefined ? "live" : timing.source,
        startedAt: now,
        peakDivert: 0,
        waveSize: 0,
        activeCamp: first?.camp ?? req.campIdx,
        stand: first?.stand ?? stand,
        waypoint: 0,
        stage: 1,
        telegraphed: false,
        baseAggro: base,
    };
    register(bot, job, data);
    return true;
}

export function Current(bot: Unit): Job | undefined {
    return jobs[bot.GetPlayerID()];
}

function isLive(job: Job | undefined): job is Job {
    return job !== undefined && job.phase !== "done" && job.phase !== "return";
}

/** Cheap: a config read, then a table lookup; false before any engine call when the lane system is off. */
export function PreContestResting(bot: Unit, lane: number): boolean {
    const r = preContestRest[bot.GetPlayerID()];
    return r !== undefined && r.lane === lane && DotaTime() < r.until;
}

export function Active(bot: Unit): boolean {
    if (!LaneConfig.IsActive()) return false;
    return isLive(jobs[bot.GetPlayerID()]);
}

export function UpcomingWithin(bot: Unit, seconds: number): boolean {
    const job = jobs[bot.GetPlayerID()];
    if (job === undefined || (job.phase !== "travel" && job.phase !== "wait")) return false;
    return job.aggroAt - DotaTime() <= seconds;
}

// ---------------------------------------------------------------------------------------------- partner cover

/**
 * How a core knows its lane support is away on a camp job, or undefined: `job` when this module instance holds the
 * support's job (modules shared between bots), else `camp` when the support is seen away from the front within
 * Radii.CoverCamp of one of the lane's pull camps (also a human support's pull). Laning phase only.
 */
export function CoverFor(bot: Unit): LuaMultiReturn<[string | undefined, number | undefined, string | undefined]> {
    if (!LaneConfig.IsActive() || !LaneConfig.InLaningPhase()) return $multi(undefined, undefined, undefined);
    const s = LaneState.ForBot(bot);
    if (s === undefined || LaneRoles.RoleIn(bot, s) !== "core") return $multi(undefined, undefined, undefined);
    const partner = LaneRoles.Partner(bot, s);
    if (partner === undefined || !partner.alive) return $multi(undefined, undefined, undefined);
    const job = jobs[partner.pid];
    if (isLive(job) && job.kind !== "contest") return $multi("job", partner.pid, LOG_KIND[job.kind]);
    if (partner.distToFront <= settings().Thresholds.SupportNearFront) return $multi(undefined, undefined, undefined);
    const loc = partner.unit.GetLocation();
    for (const c of Camps.PullCampsFor(s.team, s.lane)) {
        const spawner = Camps.SpawnerByIdx(c.campIdx);
        if (spawner !== undefined && dist2D(loc, Camps.BoxCenter(spawner)) <= settings().Radii.CoverCamp) {
            return $multi("camp", partner.pid, "camp");
        }
    }
    return $multi(undefined, undefined, undefined);
}

/**
 * Lane.Tick: while its support is on a camp, the core plays safer: retreat is scaled up by Thresholds.CoverRetreatScale
 * (it backs off sooner from a threat it would have stood against with the support beside it) and 07's harass and
 * forward stand point are off (Covering). `lane_cover` marks when that starts and ends.
 */
export function CoverTick(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const [via, partner, kind] = CoverFor(bot);
    const now = DotaTime();
    const cur = covering[pid];
    if (via === undefined) {
        if (cur !== undefined) {
            delete covering[pid];
            Intent.Release(bot, "lane:cover", BotMode.Retreat);
            Telemetry.Event("lane_cover", [
                ["pid", pid],
                ["state", "end"],
                ["partner", cur.partner],
                ["via", cur.via],
                ["dur", now - cur.since],
            ]);
        }
        return;
    }
    if (cur === undefined) {
        covering[pid] = { since: now, via, partner: partner!, kind: kind! };
        Telemetry.Event("lane_cover", [
            ["pid", pid],
            ["state", "start"],
            ["partner", partner],
            ["via", via],
            ["kind", kind],
        ]);
    }
    Intent.Claim(bot, { source: "lane:cover", tier: "LANE_PLAN", mode: BotMode.Retreat, scale: settings().Thresholds.CoverRetreatScale });
}

export function Covering(bot: Unit): boolean {
    return covering[bot.GetPlayerID()] !== undefined;
}

// ---------------------------------------------------------------------------------------------- ending

function logJob(bot: Unit, job: Job, grade: string): void {
    const data = Camps.ByIdx(job.campIdx, bot.GetTeam());
    // Relative to the planned second, so a jittered pull past the minute does not wrap to 0.
    const aggro = job.plannedSec + ((job.actualAggro ?? job.aggroAt) - job.baseAggro);
    Telemetry.Event("lane_job", [
        ["pid", bot.GetPlayerID()],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
        ["key", data?.key],
        ["aggro", aggro],
        ["planned", job.plannedSec],
        ["divert", job.peakDivert],
        ["grade", grade],
    ]);
    HDebug.Log(
        "lane",
        string.format(
            "job pid=%d kind=%s camp=%d key=%s aggro=%.1f planned=%.1f divert=%.2f grade=%s",
            bot.GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            data?.key ?? "-",
            aggro,
            job.plannedSec,
            job.peakDivert,
            grade
        )
    );
}

// Posted by Lane.CampJobRawDesire while a job runs. They outlive a scoring round, so they go when the job does.
const JOB_CLAIM_SOURCES = ["lane:camp_job", "lane:job_focus", "lane:job_hold"];

function releaseClaims(bot: Unit): void {
    for (const source of JOB_CLAIM_SOURCES) Intent.ReleaseSource(bot, source);
}

/** Completed pull: the graded `job` line that parse_condebug.js counts as an attempt. */
function close(bot: Unit, job: Job, phase: "done" | "return", grade: string): void {
    job.phase = phase;
    releaseClaims(bot);
    doneCycle[bot.GetPlayerID()] = cycleOf(DotaTime());
    if (job.kind === "stack_pull") Stacking.ClearStack(job.campIdx);
    logJob(bot, job, grade);
}

/**
 * Aborts go on the `job-abort` line, which the console parser does not read, so safety aborts never count
 * against a camp's timing.
 */
function abort(bot: Unit, job: Job, reason: string, keepStack = false, extra: [string, any][] = []): void {
    const phase = job.phase;
    job.phase = "return";
    releaseClaims(bot);
    const pid = bot.GetPlayerID();
    if (job.acted !== true) {
        // Registered from a desire query that farm never acted on: the cycle stays free for another technique.
        LanePlanner.Release(bot, commitTech(job.kind));
        skipped[pid] = job.slot ?? job.baseAggro;
    } else if (job.kind !== "stack") {
        // A stack's walk-off reaches past :00; the stack's own cycle is already held by its commit.
        doneCycle[pid] = cycleOf(DotaTime());
    }
    if (job.take === true) LanePlanner.Release(bot, "contest");
    if (!keepStack && job.kind === "stack_pull" && job.actualAggro !== undefined) Stacking.ClearStack(job.campIdx);
    if (job.kind === "stack") Stacking.Release(job.campIdx, pid);
    const [token] = string.gsub(reason, "%s+", "-");
    Telemetry.Event("lane_job_abort", [
        ["pid", pid],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
        ["key", Camps.ByIdx(job.campIdx, bot.GetTeam())?.key],
        ["reason", token],
        ["phase", phase],
        ["acted", job.acted === true],
        ["divert", job.peakDivert],
        ...(job.preAggroAt !== undefined ? ([["pre", 1]] as [string, any][]) : []),
        ...(job.take === true ? ([["take", 1]] as [string, any][]) : []),
        ...extra,
    ]);
    HDebug.Log(
        "lane",
        string.format(
            "job-abort pid=%d kind=%s camp=%d key=%s reason=%s divert=%.2f",
            bot.GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            Camps.ByIdx(job.campIdx, bot.GetTeam())?.key ?? "-",
            token,
            job.peakDivert
        )
    );
}

/**
 * A stack's walk-off ended (its outcome follows on `lane_stack`). Logged so the end is never only implied: without it a
 * stack ending at :01 and a pull starting 10 s later read as two jobs at once (ogre, console.9055921786, 8:01 / 8:11).
 */
function endStack(bot: Unit, job: Job): void {
    job.phase = "done";
    releaseClaims(bot);
    Telemetry.Event("lane_job_end", [
        ["pid", bot.GetPlayerID()],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
    ]);
}

/** A contest is no pull attempt, so it ends on its own line, which the console parser does not read. */
function endContest(bot: Unit, job: Job, reason: string): void {
    job.phase = "return";
    releaseClaims(bot);
    // The core's own lane techniques are free again once the take is over.
    if (job.take === true) LanePlanner.Release(bot, "contest");
    doneCycle[bot.GetPlayerID()] = cycleOf(DotaTime());
    const pre = job.preAggroAt !== undefined ? 1 : 0;
    if (pre === 1 && (reason === "enemy-in-lane" || reason === "no-pull")) {
        preContestRest[bot.GetPlayerID()] = { lane: bot.GetAssignedLane(), until: DotaTime() + settings().Timing.PreContestCooldown };
    }
    const fields: [string, any][] = [
        ["pid", bot.GetPlayerID()],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
        ["reason", reason],
        ["pre", pre],
    ];
    if (job.take === true) fields.push(["take", 1], ["swings", job.swings ?? 0]);
    Telemetry.Event("lane_job_end", fields);
    HDebug.Log("lane", string.format("contest-end pid=%d camp=%d reason=%s pre=%d", bot.GetPlayerID(), job.campIdx, reason, pre));
}

// ---------------------------------------------------------------------------------------------- desire

/** Continue checks for a running pull: the partner check is the committed one (LaneRoles.PartnerHolding). */
function jobAllowed(bot: Unit, s: LaneState.LaneSnapshot, forced: boolean): LuaMultiReturn<[boolean, string]> {
    if (!hpOk(bot)) return $multi(false, "low-hp");
    const enemies = LaneState.Enemies(bot, s.lane);
    const [ok, why] = LaneRoles.MayRunCampJob(bot, s, enemies, true);
    if (ok || !forced || why !== "not-owner") return $multi(ok, why);
    if (!LaneConfig.InLaningPhase()) return $multi(false, "not-laning");
    if (LaneRoles.RoleIn(bot, s) === "solo") {
        if (!LaneRoles.LaneStable(bot, enemies)) return $multi(false, "solo: unstable");
        return $multi(true, "ok");
    }
    return LaneRoles.PartnerHolding(bot, s, enemies);
}

/** Stacks need no camp-job ownership (any eligible support may stack, after laning too); forced ones only safety. */
function stackAllowed(bot: Unit, job: Job): LuaMultiReturn<[boolean, string]> {
    const s = LaneState.ForBot(bot);
    const laning = LaneConfig.InLaningPhase();
    if (laning && s === undefined) return $multi(false, "no-lane");
    const enemies = LaneState.Enemies(bot, s?.lane ?? bot.GetAssignedLane());
    const [ok, why] = job.forced === true ? Stacking.Safe(bot, s, enemies, true) : Stacking.Eligible(bot, s, enemies, true);
    if (!ok) return $multi(false, why);
    if (laning && s !== undefined && LanePlan.View(bot, s).handsOff) return $multi(false, "handsoff");
    return $multi(true, "ok");
}

function partnerFields(bot: Unit, s: LaneState.LaneSnapshot | undefined): [string, any][] {
    const r = s !== undefined ? LaneRoles.ReadPartner(bot, s, LaneState.Enemies(bot, s.lane)) : undefined;
    if (r === undefined) return [];
    return [
        ["partner", r.pid],
        ["php", r.hp],
        ["pnear", r.near],
        ["pclose", r.close],
        ["ploss", r.loss],
    ];
}

/** Safety aborts carry the partner reading, so the log shows what the support reacted to. */
function abortUnsafe(bot: Unit, job: Job, why: string, s: LaneState.LaneSnapshot | undefined): void {
    const [partnerAbort] = string.find(why, "^partner");
    abort(bot, job, why, false, partnerAbort !== undefined ? partnerFields(bot, s) : []);
}

/** Once per job: the start gate would have stopped it here, and only the commitment keeps it going. */
function noteHeld(bot: Unit, job: Job, s: LaneState.LaneSnapshot | undefined): void {
    if (job.heldNoted === true || s === undefined || !Telemetry.IsEnabled()) return;
    if (LaneRoles.PartnerSafe(bot, s, LaneState.Enemies(bot, s.lane))) return;
    job.heldNoted = true;
    Telemetry.Event("lane_job_hold", [["pid", bot.GetPlayerID()], ["hold", "partner"], ["kind", LOG_KIND[job.kind]], ["camp", job.campIdx], ["phase", job.phase], ...partnerFields(bot, s)]);
}

/**
 * The camp has been hit and is chasing the bot: from the hit in the aggro phase through lead and watch, and for a
 * double pull also the walk to the small camp and its hit once the hard camp is on the bot (its chain is taken up).
 */
function drawingCamp(job: Job): boolean {
    if (job.kind === "stack" || job.kind === "contest") return false;
    if (job.kind === "double_pull" && job.chain === undefined) return true;
    return job.phase === "lead" || job.phase === "watch" || (job.phase === "aggro" && job.aggroOrderedAt !== undefined);
}

/** What should still send a pulling bot home; the neutrals' own hits (the point of a pull) are not on the list. */
function retreatThreat(bot: Unit): string | undefined {
    const cfg = settings();
    const maxHP = bot.GetMaxHealth();
    if (maxHP <= 0 || bot.GetHealth() / maxHP < cfg.Thresholds.JobHoldMinHP) return "hp";
    const hit = cfg.Timing.JobHoldHeroHit;
    if (bot.WasRecentlyDamagedByAnyHero(hit)) return "hero-hit";
    if (bot.WasRecentlyDamagedByTower(hit)) return "tower";
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (e.visible && e.unit !== undefined && e.unit.GetAttackTarget() === bot) return "hero-attack";
    }
    // Tower range (700) plus a margin; only a tower already shooting us counts.
    for (const tower of bot.GetNearbyTowers(1000, true)) if (tower.GetAttackTarget() === bot) return "tower";
    return undefined;
}

function logRetreatHold(bot: Unit, job: Job, state: "on" | "off", reason?: string): void {
    if (!Telemetry.IsEnabled()) return;
    const maxHP = bot.GetMaxHealth();
    Telemetry.Event("lane_job_hold", [
        ["pid", bot.GetPlayerID()],
        ["hold", "retreat"],
        ["state", state],
        ["reason", reason ?? "neutrals"],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
        ["phase", job.phase],
        ["hp", maxHP > 0 ? bot.GetHealth() / maxHP : 0],
    ]);
}

/**
 * True while a pull's retreat may be held below the job: the camp is drawn and nothing but neutrals threatens.
 * The first real threat releases the hold for the rest of the job. lane_job_hold logs the hold and its release once each.
 */
export function HoldsRetreat(bot: Unit): boolean {
    const job = jobs[bot.GetPlayerID()];
    if (!isLive(job) || job.retreatHold === "off" || !drawingCamp(job)) return false;
    const why = retreatThreat(bot);
    if (why === undefined) {
        if (job.retreatHold !== "on") {
            job.retreatHold = "on";
            logRetreatHold(bot, job, "on");
        }
        return true;
    }
    job.retreatHold = "off";
    Intent.ReleaseSource(bot, "lane:job_hold");
    logRetreatHold(bot, job, "off", why);
    return false;
}

/**
 * Spells and items wait while a job works a camp: upstream's farm branches (J.IsFarming is true in farm mode or on a
 * neutral target) cast stuns and nukes on the camp it is drawing. From the camp coming into sight, or being drawn,
 * until the job ends; an enemy hero in range lifts it so the bot can still fight or save itself.
 */
export function HoldsCasts(bot: Unit): boolean {
    const job = jobs[bot.GetPlayerID()];
    if (!isLive(job) || job.kind === "contest") return false;
    if (job.phase === "travel" && !drawingCamp(job) && campNeutral(bot, job) === undefined) return false;
    return !enemyHeroNear(bot);
}

function enemyHeroNear(bot: Unit): boolean {
    return (bot.GetNearbyHeroes(settings().Radii.JobEnemyHero, true, BotMode.None) ?? []).length > 0;
}

/**
 * The job's farm desire goes above Valve's attack mode (JobCommitDesire) unless the bot has a reason to leave: an
 * enemy hero near, a human's order or survival claim, or retreat already scoring at the job's own desire. Retreat is
 * scored before farm in each round, so its sample is this round's; with no fresh sample (intent off) nothing commits.
 */
export function Commits(bot: Unit): boolean {
    const job = jobs[bot.GetPlayerID()];
    if (!isLive(job) || job.kind === "contest" || Orders.GetFor(bot) !== undefined || Intent.PriorityLive(bot) || enemyHeroNear(bot)) return false;
    const retreat = Intent.Resolved(bot, BotMode.Retreat);
    return retreat !== undefined && retreat < desireOf(job.kind);
}

/**
 * A take's continue check. Its bot is not the lane's camp-job owner, so MayRunCampJob does not apply: it leaves on
 * low HP, on TakePullMax, or once outnumbered by visible enemy heroes at the camp.
 */
function keepTaking(bot: Unit, job: Job, now: number): boolean {
    const cfg = settings();
    if (!LaneConfig.IsOn("TakePull")) {
        abort(bot, job, "flag-off");
        return false;
    }
    const s = LaneState.ForBot(bot);
    if (s !== undefined && LanePlan.View(bot, s).handsOff) {
        abort(bot, job, "handsoff");
        return false;
    }
    let reason: string | undefined;
    if (!hpOk(bot)) reason = "low-hp";
    else if (now - job.startedAt >= cfg.Timing.TakePullMax) reason = "timeout";
    // A late wave reads as a pull: back to the lane once it arrives, unless the pulled wave has been found.
    else if (job.creepSeenAt === undefined && s !== undefined && s.enemy.count > cfg.Thresholds.TakePullLaneCreeps) reason = "lane-wave";
    else {
        let near = 0;
        const here = bot.GetLocation();
        for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
            if (e.visible && dist2D(e.location, here) <= cfg.Radii.TakePullDanger) near++;
        }
        if (near >= cfg.Thresholds.TakePullDangerEnemies) reason = "outnumbered";
    }
    if (reason === undefined) return true;
    endContest(bot, job, reason);
    return false;
}

/** Abort checks for a running job; true when it may continue. */
function keepGoing(bot: Unit, job: Job): boolean {
    if (!LaneConfig.IsOn(FLAG_OF[job.kind])) {
        abort(bot, job, "flag-off");
        return false;
    }
    if (!bot.IsAlive()) {
        abort(bot, job, "dead");
        return false;
    }
    const now = DotaTime();
    if (job.take === true) return keepTaking(bot, job, now);
    if (job.kind === "contest") {
        // The lookout waits out the aggro, so a pre-contest's ContestMax counts from the first sight of the puller.
        const from = job.preAggroAt !== undefined ? job.attackFrom : job.startedAt;
        if (from !== undefined && now - from >= settings().Timing.ContestMax) {
            endContest(bot, job, "timeout");
            return false;
        }
    }
    if (now > job.aggroAt + settings().Timing.JobMaxAfterAggro) {
        // A pull already in its watch has done its work: grade it rather than call it aborted.
        if (job.phase === "watch") close(bot, job, "return", Grade(job.kind, job.peakDivert));
        else abort(bot, job, "timeout");
        return false;
    }
    if (job.kind === "stack") {
        const [ok, why] = stackAllowed(bot, job);
        const ls = LaneConfig.InLaningPhase() ? LaneState.ForBot(bot) : undefined;
        if (!ok) abortUnsafe(bot, job, why, ls);
        else noteHeld(bot, job, ls);
        return ok;
    }
    const s = LaneState.ForBot(bot);
    if (s === undefined) {
        abort(bot, job, "no-lane");
        return false;
    }
    const [ok, why] = jobAllowed(bot, s, job.forced === true);
    if (!ok) {
        abortUnsafe(bot, job, why, s);
        return false;
    }
    if (LanePlan.View(bot, s).handsOff) {
        abort(bot, job, "handsoff");
        return false;
    }
    noteHeld(bot, job, s);
    return true;
}

function desireOf(kind: JobKind): number {
    const t = settings().Timing;
    return kind === "contest" ? t.ContestDesire : t.JobDesire;
}

function anyJobFlag(): boolean {
    for (const flag of JOB_FLAGS) if (LaneConfig.IsOn(flag)) return true;
    return false;
}

function pullCampFor(tech: JobKind, camps: Camps.CampJobData[]): Camps.CampJobData {
    if (tech === "stack_pull") for (const c of camps) if (LaneHooks.IsStacked(c.campIdx)) return c;
    return camps[0];
}

/**
 * Travel to the camp's stand point when the start window of its next full or half pull would be open now for a bot
 * within MaxTravel, else undefined. A result above MaxTravel means only the distance keeps the window shut.
 */
function windowTravel(bot: Unit, data: Camps.CampJobData, kind: JobKind, now: number): number | undefined {
    const spawner = Camps.SpawnerByIdx(data.campIdx);
    if (spawner === undefined || data.pull === undefined) return undefined;
    const t = settings().Timing;
    const base = NextAggroTime(now - t.JobStartLate, timingFor(kind, data).seconds, t.PullPeriod);
    if (!CampsUp(base)) return undefined;
    const travel = travelTo(bot, standFor(spawner, leadPath(data.pull, data.pull.meetPoint)[0]));
    return WindowOpen(now, base, math.min(travel, t.MaxTravel)) ? travel : undefined;
}

/** In reach, and still able to stand at the camp by the late tolerance: a later start would only end as `late`. */
function windowFor(bot: Unit, data: Camps.CampJobData, kind: JobKind, now: number): boolean {
    const t = settings().Timing;
    const travel = windowTravel(bot, data, kind, now);
    if (travel === undefined || travel > t.MaxTravel) return false;
    return now + travel <= NextAggroTime(now - t.JobStartLate, timingFor(kind, data).seconds, t.PullPeriod) + t.JobStartLate;
}

/**
 * One lane_plan event per wave cycle and gate: why this bot did or did not start a pull in it. The gates are
 * re-checked every frame, so a bot that reads `far` early in the cycle may still reach the planner later in it.
 */
function notePlan(bot: Unit, s: LaneState.LaneSnapshot, now: number, fields: [string, any][]): void {
    if (!Telemetry.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    const cycle = cycleOf(now);
    const gate = fields[0][1] as string;
    let noted = planNoted[pid];
    if (noted === undefined || noted.cycle !== cycle) {
        noted = { cycle, gates: {} };
        planNoted[pid] = noted;
    }
    if (noted.gates[gate] === true) return;
    noted.gates[gate] = true;
    const [mayRun, why] = LaneRoles.MayRunCampJob(bot, s, LaneState.Enemies(bot, s.lane));
    Telemetry.Event("lane_plan", [
        ["pid", pid],
        ...fields,
        ["owner", mayRun ? "ok" : why],
        ["eq", s.eqPos],
        ["meet", s.meetAmount],
        ["want", s.desiredEq],
        ["front", s.ourFront],
        ["efront", s.enemyFront],
        ["tower", s.ourTowerAmount],
        ["etower", s.theirTowerAmount],
    ]);
}

/**
 * Whether this bot may double pull its lane's first two camps (skill, a second camp), and if so whether its start
 * window, the hard camp's hit `before` ahead of the small camp's second, is open now; `why` says what rules it out.
 */
function doubleFor(bot: Unit, camps: Camps.CampJobData[], now: number): { open: boolean; why?: string; g: DoubleGeometry } | undefined {
    if (camps.length < 2 || !LaneConfig.Knows("stack_pull", LaneConfig.SkillOf(bot))) return undefined;
    const g = DoubleGeometry(camps[0], camps[1], bot.GetCurrentMovementSpeed());
    if (g.why !== undefined || g.hardStand === undefined) return { open: false, why: g.why, g };
    const t = settings().Timing;
    const base = NextAggroTime(now - t.JobStartLate, timingFor("full_pull", camps[0]).seconds, t.PullPeriod);
    const hardAt = base - g.before;
    const travel = travelTo(bot, g.hardStand);
    if (!CampsUp(base) || travel > t.MaxTravel || now + travel > hardAt) return { open: false, why: "reach", g };
    return { open: WindowOpen(now, hardAt, travel), g };
}

function schedule(bot: Unit): boolean {
    const now = DotaTime();
    const pid = bot.GetPlayerID();
    if (doneCycle[pid] === cycleOf(now) || !LaneConfig.InLaningPhase()) return false;
    const s = LaneState.ForBot(bot);
    if (s === undefined) return false;
    const camps = Camps.PullCampsFor(s.team, s.lane);
    if (camps.length === 0) {
        notePlan(bot, s, now, [["gate", "no-camp"]]);
        return false;
    }
    const double = doubleFor(bot, camps, now);
    const doubleOpen = double !== undefined && double.open;
    if (!doubleOpen && !windowFor(bot, camps[0], "full_pull", now) && !windowFor(bot, camps[0], "half_pull", now)) {
        // A stack pull may use a later camp than the first one.
        let any = false;
        for (const c of camps) if (LaneHooks.IsStacked(c.campIdx) && windowFor(bot, c, "stack_pull", now)) any = true;
        if (!any) {
            const travel = windowTravel(bot, camps[0], "full_pull", now);
            if (travel !== undefined)
                notePlan(bot, s, now, [
                    ["gate", travel > settings().Timing.MaxTravel ? "far" : "late"],
                    ["camp", camps[0].campIdx],
                    ["travel", travel],
                    ["timing", timingFor("full_pull", camps[0]).source],
                ]);
            return false;
        }
    }
    const choice = LanePlanner.Plan(bot, s);
    const input = LanePlanner.LastInput(bot);
    const view = LaneState.ScoreFor(bot, s);
    notePlan(bot, s, now, [
        ["gate", "planner"],
        ["camp", camps[0].campIdx],
        ["timing", timingFor("full_pull", camps[0]).source],
        ["tech", choice.tech],
        ["reason", choice.reason],
        ["score", input?.laneScore],
        ["fscore", input?.forecastScore],
        ["w", view.foresight],
        ["imb", s.imbalance],
        ["feq", s.forecastEq],
        ["apow", s.allyPower],
        ["epow", s.enemyPower],
        ["plan", input?.plan.plan],
        ["pullOk", input?.plan.pullAllowed],
        ["partner", input?.partnerSafe],
        ["laners", input?.enemyLaners],
    ]);
    const kind = PULL_TECHS[choice.tech];
    if (kind === undefined) return false;
    const blocked = startBlocked(bot);
    if (blocked !== undefined) {
        notePlan(bot, s, now, [["gate", blocked], ["camp", camps[0].campIdx]]);
        return false;
    }
    const camp = pullCampFor(kind, camps);
    const asDouble = kind === "full_pull" && doubleOpen;
    // A double that fits but whose (hard camp) window opens later than the full pull's: wait for it.
    if (kind === "full_pull" && double !== undefined && !double.open && double.why === undefined) return false;
    if (!asDouble && !windowFor(bot, camp, kind, now)) return false;
    const base = NextAggroTime(now - settings().Timing.JobStartLate, timingFor(kind, camp).seconds, settings().Timing.PullPeriod);
    if (skipped[pid] === base) return false;
    const req: JobRequest = { kind, campIdx: camp.campIdx };
    if (asDouble) {
        req.kind = "double_pull";
        req.secondCampIdx = camps[1].campIdx;
    } else if (kind === "full_pull" && double !== undefined) {
        notePlan(bot, s, now, [
            ["gate", "double-unfit"],
            ["camp", camp.campIdx],
            ["second", camps[1].campIdx],
            ["why", double.why],
            ["late", double.g.late],
            ["gap", double.g.gap],
        ]);
    }
    return Start(bot, req);
}

/** Earliest second of the minute at which any camp's stack window can open, so most frames skip the stack roll. */
function earliestStackStart(): number {
    const t = settings().Timing;
    let earliest = t.StackMoveFrom;
    for (const data of Camps.Resolve()) {
        if (data.stack !== undefined) earliest = math.min(earliest, Stacking.AggroSec(data) - t.MaxTravel - t.JobStartLate);
    }
    return earliest;
}

function scheduleStack(bot: Unit, now: number): boolean {
    const t = settings().Timing;
    const minute = math.floor(now / t.PullPeriod);
    const sec = now - minute * t.PullPeriod;
    if (sec < earliestStackStart() || !CampsUp(now)) return false;
    // A stack is the cycle's technique (PF14): nothing else may have started in it.
    if (LanePlanner.Committed(bot) !== undefined) return false;
    const data = Stacking.WantsStack(bot, minute);
    const spawner = data !== undefined ? Camps.SpawnerByIdx(data.campIdx) : undefined;
    if (data === undefined || data.stack === undefined || spawner === undefined) return false;
    const travel = travelTo(bot, Stacking.StandPoint(spawner, data));
    const aggroSec = Stacking.AggroSec(data);
    const from = math.min(t.StackMoveFrom, aggroSec - travel - t.JobStartLate);
    if (sec < from || sec > aggroSec) return false;
    if (skipped[bot.GetPlayerID()] === NextAggroTime(now, [aggroSec], t.PullPeriod)) return false;
    if (startBlocked(bot) !== undefined) return false;
    return Start(bot, { kind: "stack", campIdx: data.campIdx, minute });
}

/**
 * Farm's GetDesire registers a job whether or not farm wins the frame. A job farm's Think has not run for
 * JobPreemptAfter while another mode is active was out-bid; a stun inside farm mode is not a pre-emption.
 */
function preempted(bot: Unit, job: Job, now: number): boolean {
    if (job.unthought !== true) return false;
    if (now - (job.lastThinkAt ?? job.startedAt) <= settings().Timing.JobPreemptAfter) return false;
    return bot.GetActiveMode() !== BotMode.Farm;
}

/** Ends a live job from outside the executor (farm mode starting a run). */
export function Abort(bot: Unit, reason: string): void {
    if (!LaneConfig.IsActive()) return;
    const job = jobs[bot.GetPlayerID()];
    if (isLive(job)) abort(bot, job, reason);
}

export function Desire(bot: Unit): number {
    if (!LaneConfig.IsActive()) return 0;
    const now = DotaTime();
    settleStack(bot, now);
    const job = jobs[bot.GetPlayerID()];
    if (isLive(job)) {
        if (job.kind === "stack" && job.phase === "exit" && now >= (job.exitUntil ?? now)) {
            endStack(bot, job);
            return 0;
        }
        if (preempted(bot, job, now)) {
            // The camp was never reached on time, so its stack state says nothing about the box.
            if (job.phase === "watch") close(bot, job, "return", Grade(job.kind, job.peakDivert));
            else abort(bot, job, "preempted", true);
            return 0;
        }
        job.unthought = true;
        if (!keepGoing(bot, job)) return 0;
        // A stack's walk-off past :00 does not claim the new cycle: the stack was the previous cycle's technique.
        if (job.kind !== "stack" && job.take !== true && LanePlanner.Committed(bot) === undefined) LanePlanner.Commit(bot, commitTech(job.kind));
        return desireOf(job.kind);
    }
    if (!bot.IsAlive()) return 0;
    let started = anyJobFlag() && schedule(bot);
    if (!started && LaneConfig.IsOn("Stack")) started = scheduleStack(bot, now);
    return started ? desireOf(jobs[bot.GetPlayerID()].kind) : 0;
}

// ---------------------------------------------------------------------------------------------- think

function overlay(bot: Unit, job: Job): void {
    HDebug.Text(bot, "lane_job", string.format("job=%s@%.1f %s out=%.2f", job.kind, job.plannedSec, job.phase, job.peakDivert));
}

function moveTo(bot: Unit, loc: Vector): boolean {
    bot.Action_MoveToLocation(loc);
    return true;
}

function arrived(bot: Unit, loc: Vector): boolean {
    return GetUnitToLocationDistance(bot, loc) <= settings().Radii.JobArrive;
}

/**
 * A human core cannot read this module, so the support pings the camp it leaves for, the usual "pulling, play safe"
 * heads-up. A bot core reads the same thing from CoverFor.
 */
function pingPartner(bot: Unit, job: Job): void {
    if (job.pinged === true || job.kind === "contest") return;
    job.pinged = true;
    if (!LaneConfig.IsOn("Telegraph") || !LaneConfig.InLaningPhase()) return;
    const s = LaneState.ForBot(bot);
    const partner = s !== undefined ? LaneRoles.Partner(bot, s) : undefined;
    if (partner === undefined || partner.isBot || !Orders.Ping(bot, job.stand)) return;
    Telemetry.Event("lane_job_ping", [
        ["pid", bot.GetPlayerID()],
        ["kind", LOG_KIND[job.kind]],
        ["camp", job.campIdx],
        ["partner", partner.pid],
    ]);
}

function telegraph(bot: Unit, job: Job, now: number): void {
    pingPartner(bot, job);
    if (job.kind === "stack") return;
    if (job.telegraphed || job.stage !== 1 || now < job.aggroAt - settings().Timing.PullTelegraphLead) return;
    job.telegraphed = true;
    if (!LaneConfig.IsOn("Telegraph") || !Difficulty.IsAllyOfHuman(bot)) return;
    Orders.Say(bot, job.kind === "half_pull" ? "say_lane_half_pull" : "say_lane_pulling_in_5", settings().Timing.PullTelegraphCooldown);
}

function campNeutral(bot: Unit, job: Job): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = math.huge;
    for (const n of bot.GetNearbyNeutralCreeps(settings().Radii.NeutralSearch, false) ?? []) {
        if (n === null || n === undefined || !n.IsAlive() || !n.CanBeSeen()) continue;
        if (!Camps.InBox(job.activeCamp, n.GetLocation())) continue;
        const d = GetUnitToLocationDistance(bot, n.GetLocation());
        if (d < bestDist) {
            best = n;
            bestDist = d;
        }
    }
    return best;
}

function aggroConfirmed(bot: Unit, job: Job): boolean {
    if (job.aggroOrderedAt !== undefined && bot.GetLastAttackTime() >= job.aggroOrderedAt) return true;
    // A double's hard camp is already on the bot, so only the small camp's hit confirms its own aggro.
    if (job.kind === "double_pull" && job.activeCamp === job.campIdx) return false;
    for (const n of bot.GetNearbyNeutralCreeps(settings().Radii.NeutralSearch, false) ?? []) {
        if (n !== null && n !== undefined && n.IsAlive() && n.CanBeSeen() && n.GetAttackTarget() === bot) return true;
    }
    return false;
}

function neutralsInBox(bot: Unit, campIdx: number): number {
    const margin = settings().Radii.BoxMargin;
    let n = 0;
    for (const c of bot.GetNearbyNeutralCreeps(settings().Radii.StackCountScan, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen() && Camps.InBox(campIdx, c.GetLocation(), margin)) n++;
    }
    return n;
}

/**
 * The camp idles at its spawner origin, so that is what must be in sight. Distance alone counted fogged boxes: ogre on
 * good_2 at 8:02, night (hero vision 800) and ~1,100 from the origin, read 2 of 3 neutrals and graded the stack failed.
 */
function boxInSight(bot: Unit, campIdx: number): boolean {
    const spawner = Camps.SpawnerByIdx(campIdx);
    if (spawner === undefined || !bot.IsAlive()) return false;
    return GetUnitToLocationDistance(bot, spawner.location) <= settings().Radii.StackSight && IsLocationVisible(spawner.location);
}

export function StackGrade(aggroSec: number): string {
    const t = settings().Timing;
    if (aggroSec < t.StackEarlyBefore) return "mistake:early";
    if (aggroSec > t.StackLateAfter) return "mistake:late";
    return "ok";
}

/** The aggro landed: the attempt counts from here, whether or not the walk-off completes. */
function noteStackAggro(bot: Unit, job: Job, now: number): void {
    const data = Camps.ByIdx(job.campIdx);
    const before = job.stackBefore ?? 0;
    const minute = job.minute ?? math.floor(job.baseAggro / settings().Timing.PullPeriod);
    Stacking.NoteStackAttempt(job.campIdx, minute, before);
    const minuteEnd = (job.exitUntil ?? now) - settings().Timing.StackExitUntil;
    pendingStacks[bot.GetPlayerID()] = {
        campIdx: job.campIdx,
        minute,
        at: minuteEnd + settings().Timing.StackOutcomeAt,
        until: minuteEnd + settings().Timing.StackOutcomeUntil,
        before,
        aggro: job.plannedSec + ((job.actualAggro ?? now) - job.baseAggro),
        planned: job.plannedSec,
        type: data?.type ?? "medium",
    };
}

function settleStack(bot: Unit, now: number): void {
    const p = pendingStacks[bot.GetPlayerID()];
    if (p === undefined || now < p.at) return;
    if (boxInSight(bot, p.campIdx)) p.peak = math.max(p.peak ?? 0, neutralsInBox(bot, p.campIdx));
    if (now < p.until && (p.peak === undefined || p.peak <= p.before)) return;
    delete pendingStacks[bot.GetPlayerID()];
    const t = settings().Timing;
    const after = p.peak;
    const [from, to] = Stacking.Window(p.campIdx);
    const assumed = after === undefined && p.aggro >= (from ?? t.StackAssumedFrom) && p.aggro <= (to ?? t.StackAssumedTo);
    const stacked = Stacking.NoteStackOutcome(p.campIdx, p.minute, after, assumed);
    // Timing only, as parse_condebug.js calibrates the stack second from it; `stacked` carries the outcome.
    const grade = after === undefined ? "unknown" : StackGrade(p.aggro);
    Telemetry.Event("lane_stack", [
        ["pid", bot.GetPlayerID()],
        ["camp", p.campIdx],
        ["type", p.type],
        ["aggro", p.aggro],
        ["planned", p.planned],
        ["before", p.before],
        ["after", after ?? "?"],
        ["grade", grade],
        ["stacked", stacked],
        ["assumed", assumed],
    ]);
    HDebug.Log(
        "lane",
        string.format(
            "stack pid=%d camp=%d type=%s aggro=%.1f planned=%.1f before=%d after=%s grade=%s stacked=%d",
            bot.GetPlayerID(),
            p.campIdx,
            p.type,
            p.aggro,
            p.planned,
            p.before,
            after === undefined ? "?" : tostring(after),
            grade,
            stacked ? 1 : 0
        )
    );
    if (assumed) HDebug.Log("lane", string.format("stack-assumed pid=%d camp=%d aggro=%.1f", bot.GetPlayerID(), p.campIdx, p.aggro));
    if (grade === "ok" && stacked && after !== undefined) Stacking.Telegraph(bot, p.type);
}

function laneCreepsNear(bot: Unit, center: Vector, radius: number): Unit[] {
    const result: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(settings().Radii.LaneCreepScan, false) ?? []) {
        if (c === null || c === undefined || !c.IsAlive() || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        if (dist2D(c.GetLocation(), center) <= radius) result.push(c);
    }
    return result;
}

function sample(bot: Unit, job: Job, now: number): void {
    const cfg = settings();
    if (job.sampledAt !== undefined && now - job.sampledAt < cfg.Timing.WatchEvery) return;
    job.sampledAt = now;
    const meet = job.meet ?? bot.GetLocation();
    const watched = laneCreepsNear(bot, meet, cfg.Radii.MeetWatch);
    if (job.waveSize === 0) {
        if (MeasureDivert(watched, 1) === 0) return;
        job.waveSize = math.max(1, laneCreepsNear(bot, meet, cfg.Radii.WaveSize).length);
    }
    job.peakDivert = math.max(job.peakDivert, MeasureDivert(watched, job.waveSize));
}

/** The puller while it stays near the camp, else any visible enemy at the camp; never a chase across the map. */
function contestTarget(bot: Unit, job: Job): Unit | undefined {
    const center = job.stand;
    const radii = settings().Radii;
    let best: Unit | undefined;
    for (const e of LaneState.Enemies(bot, bot.GetAssignedLane())) {
        if (!e.visible || e.unit === undefined) continue;
        const d = dist2D(e.location, center);
        if (e.pid === job.targetPid && d <= radii.ContestReach) return e.unit;
        if (best === undefined && d <= radii.EnemyNearCamp) best = e.unit;
    }
    return best;
}

function enemyInLane(bot: Unit, job: Job): boolean {
    const s = LaneState.ForBot(bot);
    if (s === undefined) return false;
    for (const e of LaneState.Enemies(bot, s.lane)) {
        if (e.pid === job.targetPid && e.visible && dist2D(e.location, s.frontLoc) <= settings().Radii.Exposure) return true;
    }
    return false;
}

/** Waiting at the lookout for the expected puller; true while the job keeps the frame. */
function stepLookout(bot: Unit, job: Job, now: number): boolean {
    const t = settings().Timing;
    if (now >= job.aggroAt - t.PreContestLead && enemyInLane(bot, job)) {
        endContest(bot, job, "enemy-in-lane");
        return false;
    }
    if (now > job.aggroAt + t.PreContestWait) {
        endContest(bot, job, "no-pull");
        return false;
    }
    if (!arrived(bot, job.stand)) return moveTo(bot, job.stand);
    Intent.Hold(bot, "lane:precontest");
    return true;
}

function pulledCreeps(bot: Unit, job: Job): Unit[] {
    const radii = settings().Radii;
    const out: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(radii.LaneCreepScan, true) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && dist2D(c.GetLocation(), job.stand) <= radii.TakePullCreeps) out.push(c);
    }
    return out;
}

/** Last hits on their pulled wave; true while the job keeps the frame. */
function stepTake(bot: Unit, job: Job, now: number): boolean {
    const t = settings().Timing;
    if (job.swing !== undefined) {
        if (job.swing.target.IsAlive() && now - job.swing.at < t.TakePullSwing) return true;
        job.swing = undefined;
    }
    if (job.arrivedAt === undefined && arrived(bot, job.stand)) job.arrivedAt = now;
    const creeps = pulledCreeps(bot, job);
    if (creeps.length > 0) {
        job.creepSeenAt = now;
        const damage = bot.GetAttackDamage();
        const killable = creeps.filter((c) => LastHitSkill.WillKill(bot, c, damage, aggroLead(bot, c), false));
        const pick = killable.length > 0 ? LastHitSkill.Choose(bot, killable) : undefined;
        if (pick !== undefined) {
            bot.Action_AttackUnit(pick, true);
            LastHitSkill.NoteAttempt(bot, pick);
            job.swing = { target: pick, at: now };
            job.swings = (job.swings ?? 0) + 1;
            return true;
        }
        let low = creeps[0];
        for (const c of creeps) if (c.GetHealth() < low.GetHealth()) low = c;
        if (GetUnitToUnitDistance(bot, low) > bot.GetAttackRange()) return moveTo(bot, low.GetLocation());
        Intent.Hold(bot, "lane:take_pull");
        return true;
    }
    const since = job.creepSeenAt ?? job.arrivedAt;
    if (since === undefined) return moveTo(bot, job.stand);
    if (now - since >= t.TakePullWait) {
        endContest(bot, job, "no-creeps");
        return false;
    }
    Intent.Hold(bot, "lane:take_pull");
    return true;
}

function stepContest(bot: Unit, job: Job, now: number): boolean {
    if (job.take === true) return stepTake(bot, job, now);
    const target = contestTarget(bot, job);
    if (job.phase === "lookout") {
        if (target === undefined) return stepLookout(bot, job, now);
        job.attackFrom = now;
        job.phase = "travel";
    }
    if (target !== undefined) {
        if (job.lastAttackAt === undefined || now - job.lastAttackAt >= settings().Timing.ContestAttackGap) {
            bot.Action_AttackUnit(target, true);
            job.lastAttackAt = now;
        }
        return true;
    }
    if (!arrived(bot, job.stand)) return moveTo(bot, job.stand);
    endContest(bot, job, "no-target");
    return false;
}

/** Seconds from an attack order on `creep` to its hit landing (walk into range, wind-up, projectile flight). */
function aggroLead(bot: Unit, creep: Unit): number {
    const t = settings().Timing;
    const estimate = LaneConfig.Helpers().GetAttackProDelayTime;
    const lead = estimate !== undefined ? estimate(bot, creep) : t.AggroLeadDefault;
    return math.max(0, math.min(t.AggroLeadMax, lead));
}

function orderAggro(bot: Unit, job: Job, creep: Unit): boolean {
    if (job.kind === "stack") job.stackBefore = neutralsInBox(bot, job.activeCamp);
    bot.Action_AttackUnit(creep, true);
    job.aggroTarget = creep;
    job.aggroOrderedAt = GameTime();
    job.phase = "aggro";
    return true;
}

/**
 * Seen nothing from the stand point (trees, night vision): move the stand in to StandApproach from the spawner origin,
 * once per camp. False when already done or the stand is that close anyway.
 */
function approachCamp(job: Job): boolean {
    const spawner = Camps.SpawnerByIdx(job.activeCamp);
    if (spawner === undefined || job.approachedCamp === job.activeCamp) return false;
    job.approachedCamp = job.activeCamp;
    const o = spawner.location;
    const d = dist2D(job.stand, o);
    const near = settings().Radii.StandApproach;
    if (d <= near + settings().Radii.JobArrive) return false;
    job.stand = Vector(o.x + ((job.stand.x - o.x) * near) / d, o.y + ((job.stand.y - o.y) * near) / d, o.z);
    return true;
}

/**
 * When the aggro hit landed, in DotaTime. GetLastAttackTime() (GameTime clock) is taken as the projectile's release,
 * so a ranged hit adds its flight; a confirmation from a neutral targeting the bot comes after the hit, so `now`.
 * **TODO (in-game):** if GetLastAttackTime() is the swing start, this reads early by the wind-up.
 */
function aggroLanded(bot: Unit, job: Job, now: number): number {
    const last = bot.GetLastAttackTime();
    if (job.aggroOrderedAt === undefined || last < job.aggroOrderedAt) return now;
    let flight = 0;
    const speed = (bot as Unit & { GetAttackProjectileSpeed(): number }).GetAttackProjectileSpeed();
    if (job.aggroTarget !== undefined && bot.GetAttackRange() > RANGED_ATTACK_RANGE && speed > 0) {
        flight = math.min(GetUnitToUnitDistance(bot, job.aggroTarget), bot.GetAttackRange()) / speed;
    }
    return math.min(now, now - (GameTime() - last)) + flight;
}

/** Bot API methods for item use that ts_libs does not declare yet (its Action_UseAbilityOnEntity takes abilities only). */
interface SupplyBot {
    GetNearbyTrees(radius: number): number[];
    Action_UseAbilityOnTree(item: Item, tree: number): void;
    Action_UseAbilityOnEntity(item: Item, target: Unit): void;
}
declare function GetTreeLocation(tree: number): Vector;

function usableItem(bot: Unit, name: string): Item | undefined {
    const slot = bot.FindItemSlot(name);
    if (slot === undefined || slot < 0 || slot > 5) return undefined;
    const item = bot.GetItemInSlot(slot);
    return item !== null && item !== undefined && item.IsFullyCastable() ? item : undefined;
}

function tangoTree(bot: Unit): number | undefined {
    for (const tree of (bot as unknown as SupplyBot).GetNearbyTrees(settings().Radii.TangoTree) ?? []) {
        const loc = GetTreeLocation(tree);
        if (IsLocationVisible(loc) && IsLocationPassable(loc)) return tree;
    }
    return undefined;
}

/**
 * A support about to take a camp's hits eats a tango and drinks a clarity on the way, with time to spare: upstream
 * waits for 200 HP or 60% mana lost, and from the camp coming into sight the cast hold keeps its item code off.
 * True while the job leaves the frame to the use.
 */
function supply(bot: Unit, job: Job, now: number): boolean {
    const slack = job.aggroAt - now - travelTo(bot, job.stand);
    if (job.supplyUntil !== undefined) {
        if (now < job.supplyUntil && slack > 0 && !bot.HasModifier(job.supplyModifier ?? "")) return true;
        job.supplyUntil = undefined;
    }
    const cfg = settings();
    if ((job.tangoUsed === true && job.clarityUsed === true) || slack < cfg.Timing.SupplySlack || enemyHeroNear(bot)) return false;
    if (job.clarityUsed !== true && bot.GetMaxMana() - bot.GetMana() >= cfg.Thresholds.ClarityMinLost && !bot.HasModifier("modifier_clarity_potion")) {
        const clarity = usableItem(bot, "item_clarity");
        if (clarity !== undefined) {
            job.clarityUsed = true;
            awaitSupply(job, now, "modifier_clarity_potion");
            (bot as unknown as SupplyBot).Action_UseAbilityOnEntity(clarity, bot);
            return true;
        }
    }
    if (job.tangoUsed !== true && bot.GetMaxHealth() - bot.GetHealth() >= cfg.Thresholds.TangoMinLost
        && !bot.HasModifier("modifier_tango_heal") && !bot.HasModifier("modifier_flask_healing")) {
        const tango = usableItem(bot, "item_tango_single") ?? usableItem(bot, "item_tango");
        const tree = tango !== undefined ? tangoTree(bot) : undefined;
        if (tango !== undefined && tree !== undefined) {
            job.tangoUsed = true;
            awaitSupply(job, now, "modifier_tango_heal");
            (bot as unknown as SupplyBot).Action_UseAbilityOnTree(tango, tree);
            return true;
        }
    }
    return false;
}

function awaitSupply(job: Job, now: number, modifier: string): void {
    job.supplyUntil = now + settings().Timing.SupplyWait;
    job.supplyModifier = modifier;
}

function step(bot: Unit, job: Job): boolean {
    const now = DotaTime();
    const cfg = settings();
    if (job.kind === "contest") return stepContest(bot, job, now);
    if (job.phase === "travel" || job.phase === "wait") {
        telegraph(bot, job, now);
        if (job.kind !== "stack" && supply(bot, job, now)) return true;
        // aggroAt is when the hit should land, so the order goes out its walk, wind-up and flight early; a camp
        // already in sight on the way is attacked from there rather than after reaching the stand point.
        const creep = campNeutral(bot, job);
        if (creep !== undefined && now >= job.aggroAt - aggroLead(bot, creep)) return orderAggro(bot, job, creep);
        if (creep === undefined && now >= job.aggroAt - cfg.Timing.StandApproachLead && arrived(bot, job.stand) && approachCamp(job))
            return moveTo(bot, job.stand);
        const there = arrived(bot, job.stand);
        if (now < job.aggroAt) {
            if (!there) return moveTo(bot, job.stand);
            // Holding still at the stand point: the job owns the frame without a new order.
            job.phase = "wait";
            Intent.Hold(bot, "lane:job_wait");
            return true;
        }
        if (!there) {
            // Same tolerance as a late start; past it the aggro second is lost.
            if (now >= job.aggroAt + cfg.Timing.JobStartLate) {
                abort(bot, job, "late", true);
                return false;
            }
            return moveTo(bot, job.stand);
        }
        job.phase = "aggro";
    }
    if (job.phase === "aggro") {
        if (job.aggroTarget === undefined) {
            const creep = campNeutral(bot, job);
            if (creep !== undefined) return orderAggro(bot, job, creep);
            if (arrived(bot, job.stand) && approachCamp(job)) return moveTo(bot, job.stand);
            if (now >= job.aggroAt + cfg.Timing.NoCampAfter) {
                if (arrived(bot, job.stand)) {
                    // Standing at the box and seeing no neutral: whatever was stacked there has been farmed.
                    Stacking.ClearStack(job.activeCamp);
                    abort(bot, job, "mistake:no-camp");
                    return false;
                }
                // Still walking in (an approach): the travel phase's late tolerance.
                if (now >= job.aggroAt + cfg.Timing.JobStartLate) {
                    abort(bot, job, "late", true);
                    return false;
                }
            }
            return moveTo(bot, job.stand);
        }
        // Leading off before the hit lands would cancel the attack order, so wait for the world to confirm it.
        if (!aggroConfirmed(bot, job)) {
            if (GameTime() - (job.aggroOrderedAt ?? GameTime()) >= cfg.Timing.AggroConfirm) {
                abort(bot, job, "mistake:no-aggro");
                return false;
            }
            if (!job.aggroTarget.IsAlive() || !job.aggroTarget.CanBeSeen()) job.aggroTarget = undefined;
            Intent.Hold(bot, "lane:job_aggro");
            return true;
        }
        if (job.stage === 1 && job.chain === undefined) job.actualAggro = aggroLanded(bot, job, now);
        job.aggroTarget = undefined;
        if (job.chain !== undefined) {
            // A double's hard camp is on the bot: on to the small camp, whose hit is the graded pull's.
            job.activeCamp = job.campIdx;
            job.stand = job.chain.stand;
            job.aggroAt = job.chain.aggroAt;
            job.chain = undefined;
            job.aggroOrderedAt = undefined;
            job.phase = "travel";
            HDebug.Log("lane", `job-second pid=${bot.GetPlayerID()} camp=${job.campIdx} aggroAt=${string.format("%.1f", job.aggroAt)}`);
            return step(bot, job);
        }
        if (job.kind === "stack") {
            noteStackAggro(bot, job, now);
            job.phase = "exit";
        } else {
            job.phase = "lead";
        }
    }
    if (job.phase === "exit") {
        if (now >= (job.exitUntil ?? now)) {
            endStack(bot, job);
            return false;
        }
        while (job.waypoint < job.path.length && arrived(bot, job.path[job.waypoint])) job.waypoint++;
        if (job.waypoint < job.path.length) return moveTo(bot, job.path[job.waypoint]);
        // At the end of the exit path: stay out of the box until :00 + StackExitUntil.
        Intent.Hold(bot, "lane:stack_exit");
        return true;
    }
    if (job.phase === "lead") {
        while (job.waypoint < job.path.length && arrived(bot, job.path[job.waypoint])) job.waypoint++;
        if (job.waypoint < job.path.length) return moveTo(bot, job.path[job.waypoint]);
        job.phase = "watch";
        job.watchFrom = now;
    }
    if (job.phase === "watch") {
        sample(bot, job, now);
        if (now - (job.watchFrom ?? now) >= cfg.Timing.WatchSec && (job.waveAt === undefined || now >= job.waveAt + cfg.PullTiming.WatchAfterWave)) {
            close(bot, job, "done", Grade(job.kind, job.peakDivert));
            return false;
        }
        const last = job.path[job.path.length - 1];
        if (last !== undefined && !arrived(bot, last)) return moveTo(bot, last);
        Intent.Hold(bot, "lane:job_watch");
        return true;
    }
    return false;
}

export function Think(bot: Unit): boolean {
    if (!LaneConfig.IsActive()) return false;
    const job = jobs[bot.GetPlayerID()];
    if (!isLive(job)) return false;
    job.acted = true;
    job.lastThinkAt = DotaTime();
    job.unthought = false;
    const acted = step(bot, job);
    overlay(bot, job);
    return acted;
}

export function OnEnd(bot: Unit): void {
    if (!LaneConfig.IsActive()) return;
    const job = jobs[bot.GetPlayerID()];
    if (isLive(job)) abort(bot, job, "mode-end", false, modeEndFields(bot, job));
}

function round3(v: number | undefined): number {
    return v === undefined ? -1 : math.floor(v * 1000 + 0.5) / 1000;
}

/** Which mode took farm's place and whether the job's claims on other modes were still live when it did. */
function modeEndFields(bot: Unit, job: Job): [string, any][] {
    if (!Telemetry.IsEnabled()) return [];
    const to = bot.GetActiveMode();
    return [
        ["to", HDebug.ModeName(to)],
        ["toBy", Intent.Explain(bot, to)],
        ["competing", Intent.Competing(bot)],
        ["hold", job.retreatHold ?? "-"],
        ["holdAge", round3(Intent.ClaimAge(bot, "lane:job_hold", BotMode.Retreat))],
        ["focusAge", round3(Intent.ClaimAge(bot, "lane:job_focus", BotMode.Ward))],
        ["farmAge", round3(Intent.SampleAge(bot, BotMode.Farm))],
        ["toAge", round3(Intent.SampleAge(bot, to))],
    ];
}

export function RegisterProbes(): void {
    LaneHooks.SetRotationProbe((bot) => UpcomingWithin(bot, settings().Timing.JobUpcoming));
}

RegisterProbes();
