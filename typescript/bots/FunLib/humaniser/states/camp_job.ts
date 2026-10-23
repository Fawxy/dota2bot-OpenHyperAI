/**
 * `stack` and `pull` states (team slices 7-8): camp jobs executed by the SDK job verbs (`Verbs.stack`, `Verbs.pull`)
 * instead of camp_jobs' step(). OHA still decides and plans every job (LanePlanner, Stacking, CampJobs.Start) and keeps
 * its bookkeeping: continue checks, preempt and mode-end aborts in Desire/OnEnd, grading, stack outcomes and telemetry.
 * The body only executes the plan: travel, wait, aggro on the second, lead or walk off, watch. Jobs not owned (or
 * contests and takes) run on step() as before.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const STACK = "stack";
export const PULL = "pull";

type Job = CampJobs.Job;
const Exec = CampJobs.Exec;

const STATE_OF: Partial<Record<CampJobs.JobKind, string>> = {
    stack: STACK,
    full_pull: PULL,
    half_pull: PULL,
    stack_pull: PULL,
    double_pull: PULL,
};

/** Above laning's 0.5 + stickiness; below the job break (0.9), so a running job is never switched for another. */
const SCORE = 0.8;

/** The state a job runs as, or undefined for jobs that stay on step() (contests, takes). */
export function StateOf(job: Pick<Job, "kind" | "take">): string | undefined {
    if (job.take === true) return undefined;
    return STATE_OF[job.kind];
}

function liveJob(bot: Unit, state: string): Job | undefined {
    const job = CampJobs.Current(bot);
    return job !== undefined && Exec.IsLive(job) && StateOf(job) === state ? job : undefined;
}

function T(): LaneConfig.LaneSettings["Timing"] {
    return LaneConfig.Settings().Timing;
}

function R(): LaneConfig.LaneSettings["Radii"] {
    return LaneConfig.Settings().Radii;
}

function campOf(bot: Unit, idx: number, stand: Vector, opts: { confirmAny: boolean }): Lib.Verbs.Camp {
    const sp = Camps.SpawnerByIdx(idx);
    return {
        stand: stand as unknown as Lib.Vec,
        box: sp !== undefined ? { min: sp.min as unknown as Lib.Vec, max: sp.max as unknown as Lib.Vec } : undefined,
        origin: sp !== undefined ? (sp.location as unknown as Lib.Vec) : undefined,
        margin: R().BoxMargin,
        search: R().NeutralSearch,
        // A double's hard camp is already on the bot, so any neutral targeting it says nothing about the small camp.
        confirmed: opts.confirmAny ? () => Exec.NeutralTargets(bot) : undefined,
    };
}

/** GameTime of the aggro order (the clock GetLastAttackTime uses) from its DotaTime. */
function gameTimeOf(dotaTime: number): number {
    return GameTime() - (DotaTime() - dotaTime);
}

function onLabel(bot: Unit, job: Job, label: string): void {
    job.phase = label as Job["phase"];
    if (label === "aggro" && job.kind === "stack") job.stackBefore = Exec.NeutralsInBox(bot, job.activeCamp);
}

function landed(bot: Unit, job: Job, info: Lib.Verbs.AggroInfo): void {
    job.aggroOrderedAt = gameTimeOf(info.orderedAt);
    job.aggroTarget = info.target as unknown as Unit | undefined;
    const now = DotaTime();
    if (job.chain !== undefined) {
        // The double's hard camp is on the bot: the small camp's hit is the graded one (step()'s stage change).
        job.activeCamp = job.campIdx;
        job.stand = job.chain.stand;
        job.aggroAt = job.chain.aggroAt;
        job.chain = undefined;
        job.aggroOrderedAt = undefined;
        job.aggroTarget = undefined;
        return;
    }
    if (job.stage === 1) job.actualAggro = Exec.AggroLanded(bot, job, now);
    job.aggroTarget = undefined;
    if (job.kind === "stack") Exec.NoteStackAggro(bot, job, now);
}

function stackPlan(bot: Unit, job: Job): Lib.Verbs.StackPlan {
    return {
        camp: campOf(bot, job.campIdx, job.stand, { confirmAny: true }),
        // OHA's aggroAt already holds its skill jitter (LaneConfig.Jitter, the same curve as the SDK's timingError).
        aggroAt: job.aggroAt,
        timingError: 0,
        exitPath: job.path as unknown as Lib.Vec[],
        exitUntil: job.exitUntil ?? job.aggroAt + T().JobMaxAfterAggro,
        arrive: R().JobArrive,
        startLate: T().JobStartLate,
        noCampAfter: T().NoCampAfter,
        confirmFor: T().AggroConfirm,
        onAggro: (info) => landed(bot, job, info),
    };
}

function pullPlan(bot: Unit, job: Job): Lib.Verbs.PullPlan {
    const chain = job.chain;
    const small = chain !== undefined ? chain.stand : job.stand;
    return {
        camp: campOf(bot, job.campIdx, small, { confirmAny: chain === undefined }),
        aggroAt: chain !== undefined ? chain.aggroAt : job.aggroAt,
        first: chain !== undefined ? { camp: campOf(bot, job.activeCamp, job.stand, { confirmAny: true }), aggroAt: job.aggroAt } : undefined,
        timingError: 0,
        lead: job.path as unknown as Lib.Vec[],
        watchSec: T().WatchSec,
        watchUntil: job.waveAt !== undefined ? job.waveAt + LaneConfig.Settings().PullTiming.WatchAfterWave : undefined,
        leadDeadline: (chain !== undefined ? chain.aggroAt : job.aggroAt) + T().JobMaxAfterAggro,
        arrive: R().JobArrive,
        startLate: T().JobStartLate,
        noCampAfter: T().NoCampAfter,
        confirmFor: T().AggroConfirm,
        onAggro: (info) => landed(bot, job, info),
    };
}

/** Steps `g` once per frame, except on frames where `host()` acted for the job (a tango or clarity). */
function* withHost(g: Lib.TaskBody, host: () => boolean): Lib.TaskBody {
    while (true) {
        if (!host()) {
            const s = g.next();
            if (s.done) return (s.value as Lib.Result | undefined) ?? { success: true, reason: "ok" };
        }
        yield;
    }
}

function perFrame(bot: Unit, job: Job): boolean {
    const now = DotaTime();
    if (job.phase === "travel" || job.phase === "wait") {
        Exec.Telegraph(bot, job, now);
        if (job.kind !== "stack" && Exec.Supply(bot, job, now)) return true;
    }
    if (job.phase === "watch") Exec.Sample(bot, job, now);
    return false;
}

const started: Record<number, Job | undefined> = {};

function* body(bot: Unit, state: string, ctx: Lib.Ctx): Lib.TaskBody {
    const job = liveJob(bot, state);
    if (job === undefined) return ctx.fail("no_target", "no-job");
    const pid = bot.GetPlayerID();
    // A restart after a preempt would replay travel and aggro over a half-done job: step() resumes it from its phase.
    if (started[pid] === job) {
        job.sdk = false;
        return ctx.fail("interrupted", "legacy-resume");
    }
    started[pid] = job;
    const V = Tasks.Verbs()!;
    const u = bot as unknown as Lib.TaskUnit;
    const hooks: Lib.Verbs.JobHooks = {
        label: (l) => {
            ctx.label(l);
            onLabel(bot, job, l);
        },
        urgent: ctx.urgent,
    };
    const run = job.kind === "stack" ? V.stack(u, stackPlan(bot, job), hooks) : V.pull(u, pullPlan(bot, job), hooks);
    return yield* withHost(run, () => perFrame(bot, job));
}

/** The legacy abort reason (and keepStack) for a failed body, as step() would have aborted. */
function abortOf(r: Lib.Result): LuaMultiReturn<[string, boolean]> {
    if (r.message === "late") return $multi("late", true);
    if (r.message === "mistake:no-camp" || r.message === "mistake:no-aggro") return $multi(r.message, false);
    if (r.message === "lead") return $multi(`lead-${r.reason}`, false);
    return $multi(r.reason, false);
}

function ended(bot: Unit, state: string, r: Lib.Result, info: { label?: string; steps: number }): void {
    const job = CampJobs.Current(bot);
    if (job === undefined || StateOf(job) !== state) return;
    Telemetry.Event("job_exec", [
        ["pid", bot.GetPlayerID()],
        ["kind", Exec.LogKind(job.kind)],
        ["camp", job.campIdx],
        ["result", r.success ? "ok" : "fail"],
        ["reason", r.reason],
        ["msg", r.message],
        ["label", info.label],
        ["sdk", job.sdkFrames ?? 0],
        ["legacy", job.legacyFrames ?? 0],
    ]);
    if (!Exec.IsLive(job)) return;
    if (r.success) {
        if (job.kind === "stack") Exec.EndStack(bot, job);
        else Exec.Close(bot, job);
        return;
    }
    // Interrupts and the runner's own endings: step() carries on from the job's phase, or OHA's checks end the job.
    if (r.reason === "preempted" || r.reason === "cancelled" || r.reason === "error" || r.reason === "interrupted") {
        job.sdk = false;
        return;
    }
    const [reason, keepStack] = abortOf(r);
    if (reason === "mistake:no-camp" && job.kind === "stack") Stacking.ClearStack(job.activeCamp);
    Exec.Abort(bot, job, reason, keepStack);
}

/**
 * `shadow` scores bots whose position is not owned (states/shadow.ts, slice 2: any live camp job of the kind,
 * contests included, with its linger), so shadow agreement stays measured the same way.
 */
export function Spec(
    bot: Unit,
    state: string,
    owned: (this: void, bot: Unit, state: string) => boolean,
    shadow?: (this: void, bot: Unit) => number | undefined
): Lib.StateSpec {
    return {
        name: state,
        kind: "job",
        host: BotMode.Farm,
        tier: "CAMP_JOB",
        floor: T().JobDesire,
        preemptAfter: T().JobPreemptAfter,
        // A job step() runs (planned before the position was owned) is shadowed, never started over it.
        score: () => {
            const job = liveJob(bot, state);
            if (job !== undefined && job.sdk === true) return SCORE;
            if (owned(bot, state)) return undefined;
            if (shadow !== undefined) return shadow(bot);
            return job !== undefined ? SCORE : undefined;
        },
        guard: () => {
            const job = liveJob(bot, state);
            if (job === undefined) return "job-ended";
            return job.sdk === true ? undefined : "legacy";
        },
        onEnd: (r, info) => ended(bot, state, r, info),
        body: (ctx) => body(bot, state, ctx),
    };
}

export function ResetCache(): void {
    for (const [k] of pairs(started)) started[k as number] = undefined;
}
