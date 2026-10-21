/**
 * Camp-job executor (task 07): full, half and double pulls, stacks and counter-play camp contests run from
 * mode_farm_generic as timed jobs.
 * The job window only gates a job's start (PF2); once started the job keeps its desire until it is done or
 * aborted. Each pull's outcome is measured as the divert fraction, each stack's as the box's neutral count after
 * the minute, and both are logged for tools/replay-mining.
 */
import { Team, Unit, Vector } from "bots/ts_libs/dota";
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

export type JobKind = "full_pull" | "half_pull" | "stack_pull" | "double_pull" | "stack" | "contest";

export interface JobRequest {
    kind: JobKind;
    campIdx: number;
    secondCampIdx?: number;
    forced?: boolean;
    minute?: number;
    /** Contest: the enemy seen pulling, attacked while visible. */
    targetPid?: number;
}

export interface Job extends JobRequest {
    phase: "travel" | "wait" | "aggro" | "lead" | "watch" | "exit" | "return" | "done";
    aggroAt: number;
    plannedSec: number;
    path: Vector[];
    meet?: Vector;
    startedAt: number;
    peakDivert: number;
    waveSize: number;
    /** Camp being worked now: campIdx, then secondCampIdx in a double pull's second stage. */
    activeCamp: number;
    stand: Vector;
    waypoint: number;
    stage: number;
    secondTried: boolean;
    telegraphed: boolean;
    baseAggro: number;
    actualAggro?: number;
    aggroTarget?: Unit;
    /** GameTime() of the attack order, the clock GetLastAttackTime() uses. */
    aggroOrderedAt?: number;
    watchFrom?: number;
    sampledAt?: number;
    /** Stack: the next :00 + StackExitUntil, when the walk-off ends. */
    exitUntil?: number;
    stackBefore?: number;
    lastAttackAt?: number;
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

let jobs: Record<number, Job> = {};
let doneCycle: Record<number, number> = {};
let pendingStacks: Record<number, PendingStack> = {};

export function ResetCache(): void {
    jobs = {};
    doneCycle = {};
    pendingStacks = {};
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
    if (kind === "stack" || kind === "contest") return data.stack !== undefined ? [data.stack.aggroSec] : [];
    const pull = data.pull;
    if (pull === undefined) return [];
    if (kind !== "half_pull") return pull.aggroSec;
    if (pull.halfAggroSec !== undefined) return pull.halfAggroSec;
    const later = settings().Timing.HalfPullLater;
    return pull.aggroSec.map((s) => s + later);
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

export function WindowOpen(now: number, aggroAt: number, travel: number): boolean {
    const t = settings().Timing;
    return now >= aggroAt - travel - t.JobStartSlack && now <= aggroAt + t.JobStartLate;
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
    return Camps.BoxEdgePoint(spawner, firstWaypoint, settings().Radii.StandOffset) ?? Camps.BoxCenter(spawner);
}

/** The camp's lead waypoints with its own meet point replaced by `meet`. */
function leadPath(pull: Camps.PullData, meet: Vector): Vector[] {
    const result: Vector[] = [];
    const n = pull.path.length;
    for (let i = 0; i < n; i++) {
        const p = pull.path[i];
        if (i === n - 1 && dist2D(p, pull.meetPoint) < 1) continue;
        result.push(p);
    }
    result.push(meet);
    return result;
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
    HDebug.Log(
        "lane",
        string.format(
            "job-start pid=%d kind=%s camp=%d key=%s data=%s aggroAt=%.1f forced=%s",
            bot.GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            data.key ?? "-",
            dataLabel(data),
            job.aggroAt,
            tostring(job.forced === true)
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
    const aggroSec = data.stack.aggroSec;

    // Draw order (PF10): Gauss (2) for the jitter, then one RandomVector for the stand and each exit waypoint.
    const jitter = LaneConfig.Jitter(skill);
    const noise = LaneConfig.Curve("PathNoise", skill);
    const stand = noisy(Stacking.StandPoint(spawner, data), noise);
    const path = data.stack.exitPath.map((p) => noisy(p, noise));

    let base = NextAggroTime(now, [aggroSec], period);
    if (req.forced === true && base < now + travelTo(bot, stand)) base = NextAggroTime(now + travelTo(bot, stand), [aggroSec], period);
    const minuteStart = base - aggroSec;

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
            secondTried: false,
            telegraphed: false,
            baseAggro: base,
            exitUntil: minuteStart + period + cfg.Timing.StackExitUntil,
        },
        data
    );
    return true;
}

/** Started only by counterplay: walk to the enemy pull camp and hit the puller while it stays visible. */
function startContest(bot: Unit, req: JobRequest): boolean {
    const data = Camps.ByIdx(req.campIdx);
    const spawner = Camps.SpawnerByIdx(req.campIdx);
    if (data === undefined || spawner === undefined) return false;
    const now = DotaTime();
    const center = Camps.BoxCenter(spawner);
    register(
        bot,
        {
            ...req,
            phase: "travel",
            aggroAt: now,
            plannedSec: 0,
            path: [center],
            startedAt: now,
            peakDivert: 0,
            waveSize: 0,
            activeCamp: req.campIdx,
            stand: center,
            waypoint: 0,
            stage: 1,
            secondTried: false,
            telegraphed: true,
            baseAggro: now,
        },
        data
    );
    return true;
}

export function Start(bot: Unit, req: JobRequest): boolean {
    if (req.kind === "stack") return startStack(bot, req);
    if (req.kind === "contest") return startContest(bot, req);
    if (PULL_KINDS[req.kind] !== true) return false;
    const data = Camps.ByIdx(req.campIdx);
    const spawner = Camps.SpawnerByIdx(req.campIdx);
    if (data === undefined || data.pull === undefined || spawner === undefined) return false;
    const seconds = AggroSecondsFor(req.kind, data);
    if (seconds.length === 0) return false;
    const cfg = settings();
    const skill = LaneConfig.SkillOf(bot);
    const now = DotaTime();
    const period = cfg.Timing.PullPeriod;

    // Draw order (PF10): Gauss (2) for the jitter, then one RandomVector per stand and lead waypoint.
    const jitter = LaneConfig.Jitter(skill);
    const meet = req.kind === "half_pull" ? data.pull.halfMeetPoint ?? data.pull.meetPoint : data.pull.meetPoint;
    const noise = LaneConfig.Curve("PathNoise", skill);
    const exact = leadPath(data.pull, meet);
    const stand = noisy(standFor(spawner, exact[0]), noise);
    const path = exact.map((p) => noisy(p, noise));

    let base = NextAggroTime(now - cfg.Timing.JobStartLate, seconds, period);
    if (req.forced === true && base < now + travelTo(bot, stand)) base = NextAggroTime(now + travelTo(bot, stand), seconds, period);

    const job: Job = {
        ...req,
        phase: "travel",
        aggroAt: base + jitter,
        plannedSec: base % period,
        path,
        meet,
        startedAt: now,
        peakDivert: 0,
        waveSize: 0,
        activeCamp: req.campIdx,
        stand,
        waypoint: 0,
        stage: 1,
        secondTried: false,
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
export function Active(bot: Unit): boolean {
    if (!LaneConfig.IsActive()) return false;
    return isLive(jobs[bot.GetPlayerID()]);
}

export function UpcomingWithin(bot: Unit, seconds: number): boolean {
    const job = jobs[bot.GetPlayerID()];
    if (job === undefined || (job.phase !== "travel" && job.phase !== "wait")) return false;
    return job.aggroAt - DotaTime() <= seconds;
}

// ---------------------------------------------------------------------------------------------- ending

function logJob(bot: Unit, job: Job, grade: string): void {
    const data = Camps.ByIdx(job.campIdx);
    // Relative to the planned second, so a jittered pull past the minute does not wrap to 0.
    const aggro = job.plannedSec + ((job.actualAggro ?? job.aggroAt) - job.baseAggro);
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

/** Completed pull: the graded `job` line that parse_condebug.js counts as an attempt. */
function close(bot: Unit, job: Job, phase: "done" | "return", grade: string): void {
    job.phase = phase;
    doneCycle[bot.GetPlayerID()] = cycleOf(DotaTime());
    if (job.kind === "stack_pull") Stacking.ClearStack(job.campIdx);
    logJob(bot, job, grade);
}

/**
 * Aborts go on the `job-abort` line, which the console parser does not read, so safety aborts never count
 * against a camp's timing. A double pull aborted in its second stage still grades the first pull.
 */
function abort(bot: Unit, job: Job, reason: string): void {
    if (job.stage === 2) {
        close(bot, job, "return", Grade(job.kind, job.peakDivert));
        return;
    }
    job.phase = "return";
    // A stack's walk-off reaches past :00; the stack's own cycle is already held by its commit.
    if (job.kind !== "stack") doneCycle[bot.GetPlayerID()] = cycleOf(DotaTime());
    if (job.kind === "stack_pull" && job.actualAggro !== undefined) Stacking.ClearStack(job.campIdx);
    const [token] = string.gsub(reason, "%s+", "-");
    HDebug.Log(
        "lane",
        string.format(
            "job-abort pid=%d kind=%s camp=%d key=%s reason=%s divert=%.2f",
            bot.GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            Camps.ByIdx(job.campIdx)?.key ?? "-",
            token,
            job.peakDivert
        )
    );
}

/** A contest is no pull attempt, so it ends on its own line, which the console parser does not read. */
function endContest(bot: Unit, job: Job, reason: string): void {
    job.phase = "return";
    doneCycle[bot.GetPlayerID()] = cycleOf(DotaTime());
    HDebug.Log("lane", string.format("contest-end pid=%d camp=%d reason=%s", bot.GetPlayerID(), job.campIdx, reason));
}

// ---------------------------------------------------------------------------------------------- desire

function jobAllowed(bot: Unit, s: LaneState.LaneSnapshot, forced: boolean): LuaMultiReturn<[boolean, string]> {
    const enemies = LaneState.Enemies(bot, s.lane);
    const [ok, why] = LaneRoles.MayRunCampJob(bot, s, enemies);
    if (ok || !forced || why !== "not-owner") return $multi(ok, why);
    if (!LaneConfig.InLaningPhase()) return $multi(false, "not-laning");
    if (LaneRoles.RoleIn(bot, s) === "solo") {
        if (!LaneRoles.LaneStable(bot, enemies)) return $multi(false, "solo: unstable");
    } else if (!LaneRoles.PartnerSafe(bot, s, enemies)) {
        return $multi(false, "partner unsafe");
    }
    return $multi(true, "ok");
}

/** Stacks need no camp-job ownership (any eligible support may stack, after laning too); forced ones only safety. */
function stackAllowed(bot: Unit, job: Job): LuaMultiReturn<[boolean, string]> {
    const s = LaneState.ForBot(bot);
    const laning = LaneConfig.InLaningPhase();
    if (laning && s === undefined) return $multi(false, "no-lane");
    const enemies = LaneState.Enemies(bot, s?.lane ?? bot.GetAssignedLane());
    const [ok, why] = job.forced === true ? Stacking.Safe(bot, s, enemies) : Stacking.Eligible(bot, s, enemies);
    if (!ok) return $multi(false, why);
    if (laning && s !== undefined && LanePlan.View(bot, s).handsOff) return $multi(false, "handsoff");
    return $multi(true, "ok");
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
    if (job.kind === "contest" && now - job.startedAt >= settings().Timing.ContestMax) {
        endContest(bot, job, "timeout");
        return false;
    }
    if (now > job.aggroAt + settings().Timing.JobMaxAfterAggro) {
        // A pull already in its watch has done its work: grade it rather than call it aborted.
        if (job.phase === "watch") close(bot, job, "return", Grade(job.kind, job.peakDivert));
        else abort(bot, job, "timeout");
        return false;
    }
    if (job.kind === "stack") {
        const [ok, why] = stackAllowed(bot, job);
        if (!ok) abort(bot, job, why);
        return ok;
    }
    const s = LaneState.ForBot(bot);
    if (s === undefined) {
        abort(bot, job, "no-lane");
        return false;
    }
    const [ok, why] = jobAllowed(bot, s, job.forced === true);
    if (!ok) {
        abort(bot, job, why);
        return false;
    }
    if (LanePlan.View(bot, s).handsOff) {
        abort(bot, job, "handsoff");
        return false;
    }
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

/** Earliest pull aggro in the start window for the camp's full or half seconds, before asking the planner. */
function windowFor(bot: Unit, data: Camps.CampJobData, kind: JobKind, now: number): boolean {
    const spawner = Camps.SpawnerByIdx(data.campIdx);
    if (spawner === undefined || data.pull === undefined) return false;
    const travel = travelTo(bot, standFor(spawner, leadPath(data.pull, data.pull.meetPoint)[0]));
    if (travel > settings().Timing.MaxTravel) return false;
    const base = NextAggroTime(now - settings().Timing.JobStartLate, AggroSecondsFor(kind, data), settings().Timing.PullPeriod);
    return WindowOpen(now, base, travel);
}

function schedule(bot: Unit): boolean {
    const now = DotaTime();
    const pid = bot.GetPlayerID();
    if (doneCycle[pid] === cycleOf(now) || !LaneConfig.InLaningPhase()) return false;
    const s = LaneState.ForBot(bot);
    if (s === undefined) return false;
    const camps = Camps.PullCampsFor(s.team, s.lane);
    if (camps.length === 0) return false;
    if (!windowFor(bot, camps[0], "full_pull", now) && !windowFor(bot, camps[0], "half_pull", now)) {
        // A stack pull may use a later camp than the first one.
        let any = false;
        for (const c of camps) if (LaneHooks.IsStacked(c.campIdx) && windowFor(bot, c, "stack_pull", now)) any = true;
        if (!any) return false;
    }
    const kind = PULL_TECHS[LanePlanner.Plan(bot, s).tech];
    if (kind === undefined) return false;
    const camp = pullCampFor(kind, camps);
    if (!windowFor(bot, camp, kind, now)) return false;
    const req: JobRequest = { kind, campIdx: camp.campIdx };
    if (kind === "full_pull" && camps.length > 1 && LaneConfig.Knows("stack_pull", LaneConfig.SkillOf(bot))) {
        req.kind = "double_pull";
        req.secondCampIdx = camps[1].campIdx;
    }
    return Start(bot, req);
}

/** Earliest second of the minute at which any camp's stack window can open, so most frames skip the stack roll. */
function earliestStackStart(): number {
    const t = settings().Timing;
    let earliest = t.StackMoveFrom;
    for (const data of Camps.Resolve()) {
        if (data.stack !== undefined) earliest = math.min(earliest, data.stack.aggroSec - t.MaxTravel - t.JobStartLate);
    }
    return earliest;
}

function scheduleStack(bot: Unit, now: number): boolean {
    const t = settings().Timing;
    const minute = math.floor(now / t.PullPeriod);
    const sec = now - minute * t.PullPeriod;
    if (sec < earliestStackStart()) return false;
    // A stack is the cycle's technique (PF14): nothing else may have started in it.
    if (LanePlanner.Committed(bot) !== undefined) return false;
    const data = Stacking.WantsStack(bot, minute);
    const spawner = data !== undefined ? Camps.SpawnerByIdx(data.campIdx) : undefined;
    if (data === undefined || data.stack === undefined || spawner === undefined) return false;
    const travel = travelTo(bot, Stacking.StandPoint(spawner, data));
    const from = math.min(t.StackMoveFrom, data.stack.aggroSec - travel - t.JobStartLate);
    if (sec < from || sec > data.stack.aggroSec) return false;
    return Start(bot, { kind: "stack", campIdx: data.campIdx, minute });
}

export function Desire(bot: Unit): number {
    if (!LaneConfig.IsActive()) return 0;
    const now = DotaTime();
    settleStack(bot, now);
    const job = jobs[bot.GetPlayerID()];
    if (isLive(job)) {
        if (job.kind === "stack" && job.phase === "exit" && now >= (job.exitUntil ?? now)) {
            job.phase = "done";
            return 0;
        }
        if (!keepGoing(bot, job)) return 0;
        // A stack's walk-off past :00 does not claim the new cycle: the stack was the previous cycle's technique.
        if (job.kind !== "stack" && LanePlanner.Committed(bot) === undefined) LanePlanner.Commit(bot, commitTech(job.kind));
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

function telegraph(bot: Unit, job: Job, now: number): void {
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

function boxInSight(bot: Unit, campIdx: number): boolean {
    const spawner = Camps.SpawnerByIdx(campIdx);
    return spawner !== undefined && bot.IsAlive() && GetUnitToLocationDistance(bot, Camps.BoxCenter(spawner)) <= settings().Radii.StackSight;
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
        aggro: job.plannedSec + (now - job.baseAggro),
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
    const assumed = after === undefined && p.aggro >= t.StackAssumedFrom && p.aggro <= t.StackAssumedTo;
    Stacking.NoteStackOutcome(p.campIdx, p.minute, after, assumed);
    const grade = after === undefined ? "unknown" : StackGrade(p.aggro);
    HDebug.Log(
        "lane",
        string.format(
            "stack pid=%d camp=%d type=%s aggro=%.1f planned=%.1f before=%d after=%s grade=%s",
            bot.GetPlayerID(),
            p.campIdx,
            p.type,
            p.aggro,
            p.planned,
            p.before,
            after === undefined ? "?" : tostring(after),
            grade
        )
    );
    if (assumed) HDebug.Log("lane", string.format("stack-assumed pid=%d camp=%d aggro=%.1f", bot.GetPlayerID(), p.campIdx, p.aggro));
    if (grade === "ok" && after !== undefined && after > p.before) Stacking.Telegraph(bot, p.type);
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

/** Double pull: once the first camp has engaged, lead the second camp into the same wave if it pulls soon enough. */
function trySecondCamp(bot: Unit, job: Job, now: number): boolean {
    if (job.kind !== "double_pull" || job.stage !== 1 || job.secondTried || job.peakDivert <= 0 || job.secondCampIdx === undefined) return false;
    job.secondTried = true;
    const data = Camps.ByIdx(job.secondCampIdx);
    const spawner = Camps.SpawnerByIdx(job.secondCampIdx);
    if (data === undefined || data.pull === undefined || spawner === undefined || job.meet === undefined) return false;
    const cfg = settings();
    const base = NextAggroTime(now, AggroSecondsFor("full_pull", data), cfg.Timing.PullPeriod);
    if (base - now > cfg.Timing.DoublePullReach) return false;
    const skill = LaneConfig.SkillOf(bot);
    const jitter = LaneConfig.Jitter(skill);
    const noise = LaneConfig.Curve("PathNoise", skill);
    const exact = leadPath(data.pull, job.meet);
    job.stand = noisy(standFor(spawner, exact[0]), noise);
    job.path = exact.map((p) => noisy(p, noise));
    job.aggroAt = base + jitter;
    job.activeCamp = job.secondCampIdx;
    job.stage = 2;
    job.waypoint = 0;
    job.watchFrom = undefined;
    job.phase = "travel";
    HDebug.Log("lane", `job-second pid=${bot.GetPlayerID()} camp=${job.secondCampIdx} aggroAt=${string.format("%.1f", job.aggroAt)}`);
    return true;
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

function stepContest(bot: Unit, job: Job, now: number): boolean {
    const target = contestTarget(bot, job);
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

function step(bot: Unit, job: Job): boolean {
    const now = DotaTime();
    const cfg = settings();
    if (job.kind === "contest") return stepContest(bot, job, now);
    if (job.phase === "travel" || job.phase === "wait") {
        telegraph(bot, job, now);
        if (now < job.aggroAt) {
            if (!arrived(bot, job.stand)) return moveTo(bot, job.stand);
            // Holding still at the stand point: the job owns the frame without a new order.
            job.phase = "wait";
            return true;
        }
        job.phase = "aggro";
    }
    if (job.phase === "aggro") {
        if (job.aggroTarget === undefined) {
            const creep = campNeutral(bot, job);
            if (creep !== undefined) {
                if (job.kind === "stack") job.stackBefore = neutralsInBox(bot, job.activeCamp);
                bot.Action_AttackUnit(creep, true);
                job.aggroTarget = creep;
                job.aggroOrderedAt = GameTime();
                return true;
            }
            if (now >= job.aggroAt + cfg.Timing.NoCampAfter) {
                // Standing at the box and seeing no neutral: whatever was stacked there has been farmed.
                Stacking.ClearStack(job.activeCamp);
                abort(bot, job, "mistake:no-camp");
                return false;
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
            return true;
        }
        if (job.stage === 1) job.actualAggro = now;
        job.aggroTarget = undefined;
        if (job.kind === "stack") {
            noteStackAggro(bot, job, now);
            job.phase = "exit";
        } else {
            job.phase = "lead";
        }
    }
    if (job.phase === "exit") {
        if (now >= (job.exitUntil ?? now)) {
            job.phase = "done";
            return false;
        }
        while (job.waypoint < job.path.length && arrived(bot, job.path[job.waypoint])) job.waypoint++;
        if (job.waypoint < job.path.length) return moveTo(bot, job.path[job.waypoint]);
        // At the end of the exit path: stay out of the box until :00 + StackExitUntil.
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
        if (trySecondCamp(bot, job, now)) return step(bot, job);
        if (now - (job.watchFrom ?? now) >= cfg.Timing.WatchSec) {
            close(bot, job, "done", Grade(job.kind, job.peakDivert));
            return false;
        }
        const last = job.path[job.path.length - 1];
        if (last !== undefined && !arrived(bot, last)) return moveTo(bot, last);
        return true;
    }
    return false;
}

export function Think(bot: Unit): boolean {
    if (!LaneConfig.IsActive()) return false;
    const job = jobs[bot.GetPlayerID()];
    if (!isLive(job)) return false;
    const acted = step(bot, job);
    overlay(bot, job);
    return acted;
}

export function OnEnd(bot: Unit): void {
    if (!LaneConfig.IsActive()) return;
    const job = jobs[bot.GetPlayerID()];
    if (isLive(job)) abort(bot, job, "mode-end");
}

export function RegisterProbes(): void {
    LaneHooks.SetRotationProbe((bot) => UpcomingWithin(bot, settings().Timing.JobUpcoming));
}

RegisterProbes();
