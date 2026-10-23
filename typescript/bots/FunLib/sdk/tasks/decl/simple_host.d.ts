/** @noSelfInFile */
import { Ctx } from "./ctx";
import { TaskFactory } from "./runner";
import { Adapter, Result, TaskBody, TaskUnit } from "./types";
export interface InstallOptions {
    /** Game clock in seconds. Default `DotaTime`. */
    now?: (this: void) => number;
    /** Print runner/host log lines. Default false. */
    debug?: boolean;
    /** Checked every frame alongside `SetEnabled`; false cancels the running task and refuses new ones. */
    enabled?: (this: void) => boolean;
    /** Seconds a claim stays live without being re-posted. Default 1. */
    claimTTL?: number;
}
export declare const adapter: Adapter;
/** Installs the host as the runner's adapter. Returns false (and installs nothing) without a clock. */
export declare function install(o?: InstallOptions): boolean;
/** Kill switch. Off: the next `desire` call cancels the running task (`cancelled`/`disabled`). */
export declare function SetEnabled(on: boolean): void;
/** The strongest live claim on `mode` for this bot: highest floor, urgent if any live claim is. */
export declare function ClaimOf(bot: TaskUnit, mode: number): {
    floor: number;
    urgent: boolean;
} | undefined;
/**
 * Call from mode `mode`'s `GetDesire` with the desire it would return without tasks (nil falls through to
 * Valve's). Ticks the runner once per bot per frame, then returns `max(base, floor)` while a task holds a
 * live claim on `mode`, else `base`. Urgency is not used: this host has no hysteresis to suppress.
 */
export declare function desire(bot: TaskUnit, mode: number, base?: number): number | undefined;
/** Call from mode `mode`'s `Think`; steps this bot's task if it is hosted on `mode`. True if one ran. */
export declare function think(bot: TaskUnit, mode: number): boolean;
/**
 * Call from mode `mode`'s `OnEnd`. A started task hosted on `mode` ends `preempted`, as the runner's `Tick`
 * would on the next frame; one with `preemptAfter` set is left to `Tick`, and an unstarted one to the grace.
 */
export declare function onEnd(bot: TaskUnit, mode: number): void;
export interface ModeFns {
    GetDesire?: (this: void) => number | undefined;
    Think?: (this: void) => void;
    OnStart?: (this: void) => void;
    OnEnd?: (this: void) => void;
}
/**
 * Layers task hosting on a mode file's functions:
 *   local M = tasks.SimpleHost.wrapMode(BOT_MODE_FARM, { GetDesire = GetDesire, Think = Think, OnEnd = OnEnd })
 *   GetDesire, Think, OnStart, OnEnd = M.GetDesire, M.Think, M.OnStart, M.OnEnd
 * `Think` runs the task, else the original. Defining `Think` replaces Valve's built-in one for the mode, so a
 * file with no `Think` of its own should not let `GetDesire` fall through (nil) to Valve's desire.
 */
export declare function wrapMode(mode: number, original?: ModeFns, getBot?: (this: void) => TaskUnit): Required<ModeFns>;
/**
 * A task body written as a plain function, for Lua callers (who cannot write generators). Inside `fn`,
 * `coroutine.yield()` ends this frame's slice and `run(verb)` runs a verb to completion, one slice per frame,
 * returning its `Result`; `run(ctx.must(verb))` ends the task on failure. Returning nothing counts as ok.
 */
export declare function body(fn: (this: void, run: (this: void, gen: TaskBody) => Result, ctx: Ctx) => Result | undefined): TaskFactory;
