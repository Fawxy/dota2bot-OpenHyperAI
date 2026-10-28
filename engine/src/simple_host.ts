/**
 * Standalone host for plain Valve bot scripts: an `Adapter` that keeps claims itself, plus mode-file glue.
 *
 * A task hosted on mode M raises M's `GetDesire` to its claim floor while it is live, is stepped from M's
 * `Think`, and is preempted from M's `OnEnd`. The runner's `Tick` (grace, stall, preempt, death, kill switch)
 * runs from `desire`, once per bot per frame: Dota calls every mode's `GetDesire` every frame, so the host
 * mode's file is guaranteed to tick even while another mode is active. Every mode a task can be hosted on
 * must therefore call `desire` (or be wrapped with `wrapMode`) in its `GetDesire`.
 *
 * All state is keyed by player ID, so it works whether `require`d modules are shared between bots or not, as
 * long as a bot's task is started, ticked and stepped through one module instance (simplest: one mode file).
 */
import { init } from "./adapter";
import { Ctx } from "./ctx";
import * as Runner from "./runner";
import { TaskFactory } from "./runner";
import { Adapter, Result, TaskBody, TaskUnit, Vec } from "./types";

export interface InstallOptions {
    /** Game clock in seconds. Default `DotaTime`. */
    now?: (this: void) => number;
    /** Print runner/host log lines. Default false. */
    debug?: boolean;
    /** Checked every frame alongside `SetEnabled`; false cancels the running task and refuses new ones. */
    enabled?: (this: void) => boolean;
    /** Seconds a claim stays live without being re-posted. Default 1. */
    claimTTL?: number;
    /** Builds the points verbs make themselves. Default: the script's global `Vector`, when it has one. */
    vector?: (this: void, x: number, y: number, z: number) => Vec;
}

interface Claim {
    floor: number;
    urgent: boolean;
    at: number;
}

// claims[playerID][mode][source]
const claims: Record<number, Record<number, Record<string, Claim | undefined> | undefined> | undefined> = {};
const tickedAt: Record<number, number | undefined> = {};
let opts: InstallOptions = {};
let switchedOn = true;

// Feature-detected Dota globals; rawget so a missing one is nil rather than an undefined-global error.
function global(name: string): unknown {
    return rawget(_G as unknown as Record<string, unknown>, name);
}

function now(): number {
    return opts.now !== undefined ? opts.now() : (global("DotaTime") as (this: void) => number)();
}

function enabled(): boolean {
    return switchedOn && (opts.enabled === undefined || opts.enabled());
}

export const adapter: Adapter = {
    claim: (bot, c) => {
        const id = bot.GetPlayerID();
        const byMode = claims[id] ?? (claims[id] = {});
        const bySource = byMode[c.mode] ?? (byMode[c.mode] = {});
        bySource[c.source] = { floor: c.floor, urgent: c.urgent === true, at: now() };
    },
    release: (bot, source, mode) => {
        const bySource = claims[bot.GetPlayerID()]?.[mode];
        if (bySource !== undefined) bySource[source] = undefined;
    },
    now: () => now(),
    log: (tag, msg) => {
        if (opts.debug === true) print("[" + tag + "] " + msg);
    },
    enabled: () => enabled(),
};

/**
 * Installs the host as the runner's adapter. Returns false (and installs nothing) without a clock. Points verbs
 * build themselves are made with `opts.vector`, else the script's `Vector`, as Dota's move orders require.
 */
export function install(o: InstallOptions = {}): boolean {
    if (o.now === undefined && type(global("DotaTime")) !== "function") {
        print("[tasks] SimpleHost.install: no DotaTime; pass opts.now");
        return false;
    }
    opts = o;
    const V = global("Vector");
    // Dota's Vector may be a callable table rather than a function, so presence is the test.
    adapter.vector = o.vector ?? (V !== undefined ? (x, y, z) => (V as (this: void, x: number, y: number, z: number) => Vec)(x, y, z) : undefined);
    init(adapter);
    return true;
}

/** Kill switch. Off: the next `desire` call cancels the running task (`cancelled`/`disabled`). */
export function SetEnabled(on: boolean): void {
    switchedOn = on;
}

/** The strongest live claim on `mode` for this bot: highest floor, urgent if any live claim is. */
export function ClaimOf(bot: TaskUnit, mode: number): { floor: number; urgent: boolean } | undefined {
    const bySource = claims[bot.GetPlayerID()]?.[mode];
    if (bySource === undefined || !enabled()) return undefined;
    const t = now();
    const ttl = opts.claimTTL ?? 1.0;
    let best: { floor: number; urgent: boolean } | undefined;
    for (const [, c] of pairs(bySource)) {
        if (c === undefined || t - c.at > ttl) continue;
        if (best === undefined) best = { floor: c.floor, urgent: c.urgent };
        else {
            best.floor = math.max(best.floor, c.floor);
            best.urgent = best.urgent || c.urgent;
        }
    }
    return best;
}

/**
 * Call from mode `mode`'s `GetDesire` with the desire it would return without tasks (nil falls through to
 * Valve's). Ticks the runner once per bot per frame, then returns `max(base, floor)` while a task holds a
 * live claim on `mode`, else `base`. Urgency is not used: this host has no hysteresis to suppress.
 */
export function desire(bot: TaskUnit, mode: number, base?: number): number | undefined {
    const id = bot.GetPlayerID();
    const t = now();
    if (tickedAt[id] !== t) {
        tickedAt[id] = t;
        Runner.Tick(bot);
    }
    const c = ClaimOf(bot, mode);
    if (c === undefined) return base;
    return base === undefined ? c.floor : math.max(base, c.floor);
}

/** Call from mode `mode`'s `Think`; steps this bot's task if it is hosted on `mode`. True if one ran. */
export function think(bot: TaskUnit, mode: number): boolean {
    return Runner.Step(bot, mode);
}

/**
 * Call from mode `mode`'s `OnEnd`. A started task hosted on `mode` ends `preempted`, as the runner's `Tick`
 * would on the next frame; one with `preemptAfter` set is left to `Tick`, and an unstarted one to the grace.
 */
export function onEnd(bot: TaskUnit, mode: number): void {
    const t = Runner.Current(bot);
    if (t === undefined || t.host !== mode || t.steps === 0 || t.preemptAfter > 0) return;
    Runner.Cancel(bot, "preempted", "mode_end");
}

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
export function wrapMode(mode: number, original: ModeFns = {}, getBot?: (this: void) => TaskUnit): Required<ModeFns> {
    const bot = (): TaskUnit => (getBot ?? (global("GetBot") as (this: void) => TaskUnit))();
    return {
        GetDesire: () => desire(bot(), mode, original.GetDesire !== undefined ? original.GetDesire() : undefined),
        Think: () => {
            if (!think(bot(), mode) && original.Think !== undefined) original.Think();
        },
        OnStart: () => {
            if (original.OnStart !== undefined) original.OnStart();
        },
        OnEnd: () => {
            onEnd(bot(), mode);
            if (original.OnEnd !== undefined) original.OnEnd();
        },
    };
}

/**
 * A task body written as a plain function, for Lua callers (who cannot write generators). Inside `fn`,
 * `coroutine.yield()` ends this frame's slice and `run(verb)` runs a verb to completion, one slice per frame,
 * returning its `Result`; `run(ctx.must(verb))` ends the task on failure. Returning nothing counts as ok.
 */
export function body(
    fn: (this: void, run: (this: void, gen: TaskBody) => Result, ctx: Ctx) => Result | undefined,
): TaskFactory {
    return function* (ctx) {
        return fn(run, ctx) as Result;
    };
}

// Called from inside the generator's coroutine, so `coroutine.yield` suspends the task, not this function.
function run(this: void, gen: TaskBody): Result {
    while (true) {
        const r = gen.next();
        if (r.done === true) return r.value;
        coroutine.yield();
    }
}
