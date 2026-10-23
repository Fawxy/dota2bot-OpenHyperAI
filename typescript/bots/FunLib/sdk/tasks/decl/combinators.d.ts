/** @noSelfInFile */
import { Result, TaskBody } from "./types";
/**
 * Steps `g` once per frame. Before each step `check()` may return a message, which ends the combinator with
 * `interrupted` carrying it; `g` is then abandoned (its `finally` blocks do not run).
 */
export declare function watch(this: void, g: TaskBody, check: (this: void) => string | undefined): TaskBody;
/** Ends with `timeout` once `secs` have passed since its first step, unless `g` finished first. */
export declare function withTimeout(this: void, g: TaskBody, secs: number): TaskBody;
/**
 * Runs `factory()` up to `times` times, starting a fresh attempt the frame after a failed one, while
 * `shouldRetry(result)` allows (default: any failure). Returns the last attempt's result.
 */
export declare function retry(this: void, times: number, factory: (this: void, attempt: number) => TaskBody, shouldRetry?: (this: void, r: Result) => boolean): TaskBody;
export interface RaceResult extends Result {
    /** 1-based index of the branch that finished. */
    winner: number;
}
/**
 * Steps every branch once per frame, in order, and returns the first to finish; the rest are abandoned.
 * Branches stepped after an acting one in the same frame override its orders, so let one branch act and make
 * the others watchers (`waitUntil`, conditions).
 */
export declare function race(this: void, ...branches: TaskBody[]): Generator<void, RaceResult, unknown>;
/** Never acts; finishes `ok` on the first frame `cond()` holds (without yielding if it already does). */
export declare function until(this: void, cond: (this: void) => boolean): TaskBody;
