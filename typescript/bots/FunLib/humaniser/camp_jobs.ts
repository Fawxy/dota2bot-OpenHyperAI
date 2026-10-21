/**
 * Camp-job executor (task 07): full, half and double pulls run from mode_farm_generic as timed jobs.
 * The job window only gates a job's start (PF2); once started the job keeps its desire until it is done or
 * aborted. Each pull's outcome is measured as the divert fraction and logged for tools/replay-mining.
 */
import { Team, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LanePlanner from "bots/FunLib/humaniser/lane_planner";
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
    watchFrom?: number;
    sampledAt?: number;
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

export function ResetCache(): void {
    jobs = {};
    doneCycle = {};
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

export function Start(bot: Unit, req: JobRequest): boolean {
    if (PULL_KINDS[req.kind] !== true) return false; // stack and contest executors arrive with their own tasks
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
    jobs[bot.GetPlayerID()] = job;
    LanePlanner.Commit(bot, commitTech(req.kind));
    HDebug.Log(
        "lane",
        string.format(
            "job-start pid=%d kind=%s camp=%d key=%s data=%s aggroAt=%.1f forced=%s",
            bot.GetPlayerID(),
            LOG_KIND[req.kind],
            req.campIdx,
            data.key ?? "-",
            dataLabel(data),
            job.aggroAt,
            tostring(req.forced === true)
        )
    );
    return true;
}

export function Current(bot: Unit): Job | undefined {
    return jobs[bot.GetPlayerID()];
}

function isLive(job: Job | undefined): job is Job {
    return job !== undefined && job.phase !== "done" && job.phase !== "return";
}

export function Active(bot: Unit): boolean {
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

function close(bot: Unit, job: Job, phase: "done" | "return", grade: string | undefined, reason: string): void {
    job.phase = phase;
    doneCycle[bot.GetPlayerID()] = cycleOf(DotaTime());
    if (grade !== undefined) logJob(bot, job, grade);
    else HDebug.Log("lane", `job-abort pid=${bot.GetPlayerID()} kind=${LOG_KIND[job.kind]} camp=${job.campIdx} reason=${reason}`);
}

/** Before the aggro nothing happened in the lane, so only a note is logged; after it the pull is graded. */
function abort(bot: Unit, job: Job, reason: string): void {
    const graded = job.actualAggro !== undefined;
    close(bot, job, "return", graded ? `aborted:${reason}` : undefined, reason);
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
    if (now > job.aggroAt + settings().Timing.JobMaxAfterAggro) {
        // A pull already in its watch has done its work: grade it rather than call it aborted.
        if (job.phase === "watch") close(bot, job, "return", Grade(job.kind, job.peakDivert), "timeout");
        else abort(bot, job, "timeout");
        return false;
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

export function Desire(bot: Unit): number {
    if (!LaneConfig.IsActive()) return 0;
    const job = jobs[bot.GetPlayerID()];
    if (isLive(job)) {
        if (!keepGoing(bot, job)) return 0;
        if (LanePlanner.Committed(bot) === undefined) LanePlanner.Commit(bot, commitTech(job.kind));
        return desireOf(job.kind);
    }
    if (!anyJobFlag() || !bot.IsAlive()) return 0;
    const started = schedule(bot);
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

function step(bot: Unit, job: Job): boolean {
    const now = DotaTime();
    const cfg = settings();
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
        const creep = campNeutral(bot, job);
        if (creep !== undefined) {
            bot.Action_AttackUnit(creep, true);
            if (job.stage === 1) job.actualAggro = now;
            job.phase = "lead";
            return true;
        }
        if (now >= job.aggroAt + cfg.Timing.NoCampAfter) {
            if (job.stage === 1) {
                job.actualAggro = job.aggroAt;
                close(bot, job, "return", "mistake:no-camp", "no-camp");
            } else {
                close(bot, job, "done", Grade(job.kind, job.peakDivert), "second camp empty");
            }
            return false;
        }
        return moveTo(bot, job.stand);
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
            close(bot, job, "done", Grade(job.kind, job.peakDivert), "done");
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
