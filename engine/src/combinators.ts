import { get } from "./adapter";
import { Result, TaskBody } from "./types";

// A generator that returned without a value is treated as ok, as the runner does for a task body.
function settle(value: Result | undefined): Result {
    return value ?? { success: true, reason: "ok" };
}

/**
 * Steps `g` once per frame. Before each step `check()` may return a message, which ends the combinator with
 * `interrupted` carrying it; `g` is then abandoned (its `finally` blocks do not run).
 */
export function* watch(this: void, g: TaskBody, check: (this: void) => string | undefined): TaskBody {
    while (true) {
        const message = check();
        if (message !== undefined) return { success: false, reason: "interrupted", message };
        const s = g.next();
        if (s.done) return settle(s.value as Result | undefined);
        yield;
    }
}

/** Ends with `timeout` once `secs` have passed since its first step, unless `g` finished first. */
export function* withTimeout(this: void, g: TaskBody, secs: number): TaskBody {
    const now = get()!.now;
    const start = now();
    while (true) {
        if (now() - start >= secs) return { success: false, reason: "timeout" };
        const s = g.next();
        if (s.done) return settle(s.value as Result | undefined);
        yield;
    }
}

/**
 * Runs `factory()` up to `times` times, starting a fresh attempt the frame after a failed one, while
 * `shouldRetry(result)` allows (default: any failure). Returns the last attempt's result.
 */
export function* retry(
    this: void,
    times: number,
    factory: (this: void, attempt: number) => TaskBody,
    shouldRetry?: (this: void, r: Result) => boolean,
): TaskBody {
    let r: Result = { success: false, reason: "error", message: "retry: times < 1" };
    for (let attempt = 1; attempt <= times; attempt++) {
        r = settle(yield* factory(attempt));
        if (r.success) return r;
        if (shouldRetry !== undefined && !shouldRetry(r)) return r;
        if (attempt < times) yield;
    }
    return r;
}

export interface RaceResult extends Result {
    /** 1-based index of the branch that finished. */
    winner: number;
}

/**
 * Steps every branch once per frame, in order, and returns the first to finish; the rest are abandoned.
 * Branches stepped after an acting one in the same frame override its orders, so let one branch act and make
 * the others watchers (`waitUntil`, conditions).
 */
export function* race(this: void, ...branches: TaskBody[]): Generator<void, RaceResult, unknown> {
    if (branches.length === 0) return { success: false, reason: "error", message: "race: no branches", winner: 0 };
    while (true) {
        for (let i = 0; i < branches.length; i++) {
            const s = branches[i].next();
            if (s.done) {
                const r = settle(s.value as Result | undefined);
                return { success: r.success, reason: r.reason, message: r.message, winner: i + 1 };
            }
        }
        yield;
    }
}

/** Never acts; finishes `ok` on the first frame `cond()` holds (without yielding if it already does). */
export function* until(this: void, cond: (this: void) => boolean): TaskBody {
    while (!cond()) yield;
    return { success: true, reason: "ok" };
}
