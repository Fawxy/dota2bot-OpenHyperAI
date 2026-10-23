/**
 * Shadow states (team slice 2): `pull`, `stack`, `rotate` and `farm`, scored from decisions OHA has already
 * made, so every bot reports the state it is in while OHA keeps doing all of it. Nothing here is owned; the
 * bodies exist only because a spec needs one. A later slice replaces a spec by registering an owned one of
 * the same name (States.Register).
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as FarmPattern from "bots/FunLib/humaniser/farm_pattern";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as Rotation from "bots/FunLib/humaniser/transitions/rotation";
import * as MidRunes from "bots/FunLib/humaniser/transitions/mid_runes";

export const JOB = 0.8;
export const ROTATE = 0.75;
/** A farm trip beats laning (0.5 plus stickiness), as OHA's trip desire (0.62) beats laning's 0.446. */
export const TRIP = 0.7;
export const FARM = 0.4;
/**
 * Seconds a job scorer keeps its score after its source went false. The layer leaves an unowned job the moment
 * its scorer stops (no dwell for jobs), so one-frame gaps in a source would otherwise count as two switches.
 */
export const LINGER = 1;

const PULL_KINDS: Record<string, boolean> = { full_pull: true, half_pull: true, stack_pull: true, double_pull: true, contest: true };

const seen: Record<string, number | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(seen)) delete seen[k as string];
}

function lingering(bot: Unit, state: string, on: boolean, score: number): number | undefined {
    const key = `${bot.GetPlayerID()}:${state}`;
    const now = DotaTime();
    if (on) {
        seen[key] = now;
        return score;
    }
    const at = seen[key];
    return at !== undefined && now - at <= LINGER ? score : undefined;
}

function liveJob(bot: Unit): CampJobs.Job | undefined {
    return CampJobs.Active(bot) ? CampJobs.Current(bot) : undefined;
}

/** Pulls (full, half, stack, double) and pull contests: a camp job OHA's scheduler started this cycle. */
export function PullScore(bot: Unit): number | undefined {
    const job = liveJob(bot);
    return lingering(bot, "pull", job !== undefined && PULL_KINDS[job.kind] === true, JOB);
}

export function StackScore(bot: Unit): number | undefined {
    return lingering(bot, "stack", liveJob(bot)?.kind === "stack", JOB);
}

/** A support's power-rune rotation once it leaves (Rotation.Active), or the mid's rune claim. */
export function RotateScore(bot: Unit): number | undefined {
    return lingering(bot, "rotate", Rotation.Active(bot) !== undefined || MidRunes.Claiming(bot), ROTATE);
}

/**
 * A farm trip in progress (also inside the laning phase), else after laning any bot FarmPattern would farm with.
 * Only StartGate's lasting checks count: its transient ones (mode, HP, orders, retreat, runes, enemies) flip
 * many times a minute, and the interrupts they reflect are left out of the agreement measure anyway.
 */
export function FarmScore(bot: Unit): number | undefined {
    if (!FarmPattern.IsActive()) return undefined;
    if (FarmPattern.Current(bot) !== undefined) return TRIP;
    if (Phase.IsLaningFor(bot)) return undefined;
    return FarmPattern.Eligible(bot) === undefined ? FARM : undefined;
}

function* idle(ctx: Lib.Ctx): Lib.TaskBody {
    return ctx.fail("unsupported", "shadow");
}

function spec(name: string, kind: Lib.StateSpec["kind"], host: number, score: (this: void, bot: Unit) => number | undefined): (bot: Unit) => Lib.StateSpec {
    return (bot: Unit) => ({ name, kind, host, score: () => score(bot), body: idle });
}

/** (name, spec factory) in registration order; `rotate` hosts on rune mode, its ganks (roam) come later. */
export const SPECS: [string, (bot: Unit) => Lib.StateSpec][] = [
    ["pull", spec("pull", "job", BotMode.Farm, PullScore)],
    ["stack", spec("stack", "job", BotMode.Farm, StackScore)],
    ["rotate", spec("rotate", "job", BotMode.Rune, RotateScore)],
    ["farm", spec("farm", "posture", BotMode.Farm, FarmScore)],
];
