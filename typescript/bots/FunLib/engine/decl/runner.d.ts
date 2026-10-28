/** @noSelfInFile */
import { Ctx } from "./ctx";
import { Result, TaskBody, TaskOptions, TaskUnit } from "./types";
/** Seconds a task may wait for its first `Step`, whatever the active mode, before it is cancelled. */
export declare const START_GRACE = 1;
interface LastRun {
    name: string;
    result: Result;
}
/** A task body factory. It receives the task's `Ctx`; factories that take no argument work unchanged. */
export type TaskFactory = (this: void, ctx: Ctx) => TaskBody;
export declare function task(bot: TaskUnit, opts: TaskOptions, body: TaskFactory): boolean;
export declare function Step(bot: TaskUnit, host: number): boolean;
/**
 * Every frame from the host's global tick. Re-posts the claim while the task is live, so the host can win
 * the mode before the first `Step`; the grace and stall limits keep an unstepped task from pinning it.
 */
export declare function Tick(bot: TaskUnit): void;
export declare function Cancel(bot: TaskUnit, reason: Result["reason"], message?: string): void;
/** Sets or clears urgency on the current task's claims from the next one posted; callable from a body. */
export declare function Urgent(bot: TaskUnit, on: boolean): void;
/** Sets a free-form label on the current task, shown by `Current`/`Describe` and passed to `onEnd`. */
export declare function Label(bot: TaskUnit, label: string): void;
export declare function Current(bot: TaskUnit): {
    name: string;
    host: number;
    startedAt: number;
    steps: number;
    label?: string;
    preemptAfter: number;
} | undefined;
export declare function Last(bot: TaskUnit): LastRun | undefined;
export declare function Describe(bot: TaskUnit): string;
export {};
