import { abort } from "./abort";
import * as Flow from "./combinators";
import { TaskFactory } from "./runner";
import { Reason, Result, TaskBody, TaskTarget, TaskUnit, Vec } from "./types";
import * as Verbs from "./verbs";

/**
 * Test-only body factories (task bodies must be generators, which Lua test code cannot author).
 * `counting(n, log, result)`: n yields; pushes the 1-based slice number into `log` at the start of every
 * resume (n + 1 entries once finished), then returns `result` (nil means the runner's default ok).
 */
export function counting(n: number, log: number[], result?: Result): (this: void) => TaskBody {
    return function* () {
        for (let i = 1; i <= n; i++) {
            log.push(i);
            yield;
        }
        log.push(n + 1);
        return result as Result;
    };
}

/** Calls `fns[i]` at the start of the i-th resume, yielding after each; then returns `result`. */
export function calling(fns: ((this: void) => void)[], result?: Result): (this: void) => TaskBody {
    return function* () {
        for (const fn of fns) {
            fn();
            yield;
        }
        return result as Result;
    };
}

/** Throws `message` on the k-th resume (k - 1 clean yields first). */
export function throwing(k: number, message: string): (this: void) => TaskBody {
    return function* () {
        for (let i = 1; i < k; i++) yield;
        error(message, 0);
    };
}

/** Composes verbs with `yield*`: walk to `loc`, then wait `secs`; stops at the first failed verb. */
export function walkThenWait(bot: TaskUnit, loc: Vec, secs: number): (this: void) => TaskBody {
    return function* () {
        const r = yield* Verbs.walkTo(bot, loc);
        if (!r.success) return r;
        return yield* Verbs.wait(bot, secs);
    };
}

/** walkTo `loc`, waitUntil game time `t`, then attackAndConfirm `pick()`; stops at the first failed verb. */
export function walkWaitAttack(
    bot: TaskUnit,
    loc: Vec,
    t: number,
    pick: (this: void) => TaskTarget | undefined,
    confirmFor: number,
): (this: void) => TaskBody {
    return function* () {
        const walked = yield* Verbs.walkTo(bot, loc);
        if (!walked.success) return walked;
        const waited = yield* Verbs.waitUntil(bot, t);
        if (!waited.success) return waited;
        return yield* Verbs.attackAndConfirm(bot, pick, { findFor: 0, confirmFor });
    };
}

// ---- Bodies written against `ctx`, `must`/`abort` and `Flow` ----

/** Labels `walk`, must-walks to `loc` (optional deadline), labels `wait`, waits `secs`. */
export function ctxWalkWait(loc: Vec, secs: number, deadline?: number): TaskFactory {
    return function* (ctx) {
        ctx.label("walk");
        yield* ctx.must(ctx.walkTo(loc, { deadline }));
        ctx.label("wait");
        yield* ctx.must(ctx.wait(secs));
        return ctx.ok();
    };
}

function* abortsAtDepth(depth: number, reason: Reason, message: string): TaskBody {
    yield;
    if (depth <= 1) abort(reason, message);
    return yield* abortsAtDepth(depth - 1, reason, message);
}

/** Yields once per level, then aborts from `depth` generators down; `after` counts resumes past the abort. */
export function nestedAbort(depth: number, reason: Reason, message: string, after: number[]): TaskFactory {
    return function* () {
        yield* abortsAtDepth(depth, reason, message);
        after.push(1);
        return { success: true, reason: "ok" };
    };
}

/** Records elapsed() and now() on its first resume into `seen`, then finishes. */
export function ctxClock(seen: { elapsed?: number; now?: number }): TaskFactory {
    return function* (ctx) {
        yield;
        seen.elapsed = ctx.elapsed();
        seen.now = ctx.now();
        return ctx.ok();
    };
}

/** Walks to `loc` under `Flow.watch`; `check` may interrupt. */
export function watchedWalk(loc: Vec, check: (this: void) => string | undefined): TaskFactory {
    return (ctx) => Flow.watch(ctx.walkTo(loc, { timeout: 60 }), check);
}

/** Walks to `loc` under `Flow.withTimeout(secs)`. */
export function timedWalk(loc: Vec, secs: number): TaskFactory {
    return (ctx) => Flow.withTimeout(ctx.walkTo(loc, { timeout: 60 }), secs);
}

/** Up to `times` walks to `locs[attempt]` (each `timeout` s); `attempts` records each attempt number. */
export function retryWalks(
    times: number,
    locs: Vec[],
    timeout: number,
    attempts: number[],
    shouldRetry?: (this: void, r: Result) => boolean,
): TaskFactory {
    return (ctx) =>
        Flow.retry(
            times,
            (attempt) => {
                attempts.push(attempt);
                return ctx.walkTo(locs[attempt - 1], { timeout, stuckSecs: math.huge });
            },
            shouldRetry,
        );
}

/** Races a walk to `loc` against `until(cond)`; records the winner in `out`. */
export function raceWalkUntil(loc: Vec, cond: (this: void) => boolean, out: { winner?: number }): TaskFactory {
    return function* (ctx) {
        const r = yield* Flow.race(ctx.walkTo(loc, { timeout: 60 }), Flow.until(cond));
        out.winner = r.winner;
        return r;
    };
}

/** Up to `times` walks that fail at once (deadline already passed); `at` records ctx.now() per attempt. */
export function retryInstantFail(times: number, at: number[]): TaskFactory {
    return (ctx) =>
        Flow.retry(times, () => {
            at.push(ctx.now());
            return ctx.walkTo({ x: 5000, y: 0 }, { deadline: -1 });
        });
}

/** Labels `hold` and holds at `loc` through `ctx.holdAt` (no scatter). */
export function ctxHold(loc: Vec): TaskFactory {
    return function* (ctx) {
        ctx.label("hold");
        return yield* ctx.holdAt(() => loc, { scatter: 0 });
    };
}
