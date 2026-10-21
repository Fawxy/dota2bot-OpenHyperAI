/**
 * The camp stack job as a lua-tasks task (spike, Customize.Humaniser.Tasks.Stack): camp_jobs' stack plan, checks,
 * log lines and telemetry, with travel, wait, aggro and the walk-off written as one body. Phases are task labels,
 * so an abort reports the same phase names as the legacy job.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as Tasks from "bots/FunLib/humaniser/tasks";

type Plan = CampJobs.StackPlan;

interface Run {
    plan: Plan;
    ended?: "done" | "aborted";
}

let runs: Record<number, Run> = {};

function T(): LaneConfig.LaneSettings["Timing"] {
    return LaneConfig.Settings().Timing;
}

function there(bot: Unit, loc: Vector): boolean {
    return GetUnitToLocationDistance(bot, loc) <= LaneConfig.Settings().Radii.JobArrive;
}

function fail(reason: Lib.Reason, message: string): Lib.Result {
    return { success: false, reason, message };
}

/** False when the flag is off or the runner refused; camp_jobs then runs the legacy job on the same plan. */
export function Start(bot: Unit, p: Plan): boolean {
    if (Config.Get().Tasks.Stack !== true) return false;
    const started = Tasks.Start(
        bot,
        {
            name: "stack",
            host: BotMode.Farm,
            tier: "CAMP_JOB",
            floor: CampJobs.DesireOf("stack"),
            preemptAfter: T().JobPreemptAfter,
            // The legacy job has no stall rule while farm stays active; the guard's timeout bounds it.
            stallAfter: math.huge,
            guard: () => guard(bot, p),
            onEnd: (r, info) => ended(bot, p, r, info),
        },
        () => body(bot, p)
    );
    if (!started) return false;
    runs[bot.GetPlayerID()] = { plan: p };
    Stacking.Reserve(p.campIdx, bot.GetPlayerID(), p.exitUntil);
    CampJobs.NoteJobStart(bot, { kind: "stack", campIdx: p.campIdx, aggroAt: p.aggroAt, forced: p.forced }, p.data);
    return true;
}

/** The legacy job's checks in its order; the runner's Tick checks death first, but Step resumes without it. */
function guard(bot: Unit, p: Plan): string | undefined {
    if (!LaneConfig.IsOn("Stack")) return "flag-off";
    if (!bot.IsAlive()) return "dead";
    if (DotaTime() > p.aggroAt + T().JobMaxAfterAggro) return "timeout";
    const [ok, why] = CampJobs.StackAllowed(bot, p.forced);
    return ok ? undefined : why;
}

function* body(bot: Unit, p: Plan): Lib.TaskBody {
    const V = Tasks.Verbs()!;
    const u = bot as unknown as Lib.TaskUnit;
    const walk = (points: Vector[], until: number) =>
        V.walkPath(u, points, { tolerance: LaneConfig.Settings().Radii.JobArrive, timeout: math.huge, stuckSecs: math.huge, interruptIf: () => DotaTime() >= until });

    Tasks.Urgent(bot, true);
    Tasks.Label(bot, "travel");
    // Pushed off the stand point while waiting, the bot walks back for as long as the aggro can still be made.
    do {
        if (!(yield* walk([p.stand], p.aggroAt + T().JobStartLate)).success) return fail("timeout", "late");
        Tasks.Label(bot, "wait");
        yield* V.waitUntil(u, p.aggroAt, { hold: "lane:job_wait", interruptIf: () => !there(bot, p.stand) });
    } while (!there(bot, p.stand));

    Tasks.Label(bot, "aggro");
    let before = 0;
    const pick = () => {
        const n = CampJobs.CampNeutral(bot, p.campIdx);
        if (n !== undefined) before = CampJobs.NeutralsInBox(bot, p.campIdx);
        return n as unknown as Lib.TaskTarget | undefined;
    };
    const hit = yield* V.attackAndConfirm(u, pick, {
        findFor: math.max(0, p.aggroAt + T().NoCampAfter - DotaTime()),
        confirmFor: T().AggroConfirm,
        searchAt: p.stand,
        hold: "lane:job_aggro",
        confirmed: () => CampJobs.NeutralTargets(bot),
    });
    if (hit.reason === "no_target") {
        if (!there(bot, p.stand)) return fail("timeout", "late");
        // Standing at the box and seeing no neutral: whatever was stacked there has been farmed.
        Stacking.ClearStack(p.campIdx);
        return fail("no_target", "mistake:no-camp");
    }
    if (!hit.success) return fail(hit.reason, "mistake:no-aggro");
    CampJobs.NoteStackAggro(bot, p, before, DotaTime());

    Tasks.Urgent(bot, false);
    Tasks.Label(bot, "exit");
    yield* walk(p.path, p.exitUntil);
    yield* V.waitUntil(u, p.exitUntil, { hold: "lane:stack_exit" });
    return { success: true, reason: "ok" };
}

function ended(bot: Unit, p: Plan, r: Lib.Result, info: { label?: string; steps: number }): void {
    runs[bot.GetPlayerID()].ended = r.success ? "done" : "aborted";
    if (r.success) return;
    // The runner's own endings carry its details as the message (never_started, stalled, mode=<m>); legacy has one word each.
    const reason = r.reason === "preempted" || r.reason === "dead" || r.reason === "error" ? r.reason : (r.message ?? r.reason);
    const phase = info.label ?? "travel";
    CampJobs.NoteJobAbort(bot, { kind: "stack", campIdx: p.campIdx, baseAggro: p.baseAggro, phase, acted: info.steps > 0, divert: 0, aggroLanded: false }, reason);
}

/** The bot's latest stack task: its plan, its label while it runs, and how it ended. */
export function Job(bot: Unit): { plan: Plan; label?: string; ended?: string } | undefined {
    const run = runs[bot.GetPlayerID()];
    if (run === undefined) return undefined;
    const current = Tasks.Current(bot);
    return { plan: run.plan, label: current?.name === "stack" ? current.label : undefined, ended: run.ended };
}

/** The rotation probe: the aggro is within `seconds` while the bot travels to the camp or waits there. */
export function UpcomingWithin(bot: Unit, seconds: number): boolean {
    const job = Job(bot);
    if (job === undefined || job.ended !== undefined || job.label === "aggro" || job.label === "exit") return false;
    return job.plan.aggroAt - DotaTime() <= seconds;
}

CampJobs.SetStackTask({ Start, UpcomingWithin });
