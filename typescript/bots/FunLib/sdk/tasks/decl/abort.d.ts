/** @noSelfInFile */
import { Reason, Result, TaskBody } from "./types";
/** Ends the running task with `result` from any generator depth; the runner finishes it as if returned. */
export declare function abortWith(this: void, result: Result): never;
export declare function abort(this: void, reason: Reason, message?: string): never;
/** The carried result if `err` was raised by `abort`/`must`, else undefined. */
export declare function aborted(this: void, err: unknown): Result | undefined;
/**
 * Runs `g` and returns its result if it succeeded; a failure ends the whole task with that result, its message
 * replaced by `message` when given.
 */
export declare function must(this: void, g: TaskBody, message?: string): TaskBody;
