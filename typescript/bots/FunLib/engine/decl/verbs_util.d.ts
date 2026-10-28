/** @noSelfInFile */
import { Reason, Result, TaskTarget, TaskUnit, Vec } from "./types";
export declare function ok(): Result;
export declare function fail(reason: Reason, message?: string): Result;
export declare function now(): number;
/** True once game time has reached `deadline`; verbs then fail `timeout`. */
export declare function expired(deadline: number | undefined): boolean;
export declare function dist(a: Vec, b: Vec): number;
/** Reports a deliberate stand-still to the adapter's `hold`; no tag, no report. */
export declare function hold(bot: TaskUnit, tag: string | undefined): void;
/** Released, dead or out of sight. */
export declare function targetLost(t: TaskTarget): boolean;
/** The stop options every verb takes. */
export interface StopOpts {
    /** Absolute game time (`now()` clock); the verb fails `timeout` once it is reached. */
    deadline?: number;
    /** Checked every frame; true fails the verb `interrupted`. */
    interruptIf?: (this: void) => boolean;
}
/** `interrupted` or `timeout` when `opts` says to stop now, else undefined. */
export declare function stopped(opts: StopOpts): Result | undefined;
