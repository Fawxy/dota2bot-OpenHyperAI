/** @noSelfInFile */
import { Result, TaskBody, TaskOptions, TaskUnit } from "./types";
/** Seconds a task may wait for its first `Step` while its host mode is not active. */
export declare const START_GRACE = 1;
interface LastRun {
    name: string;
    result: Result;
}
export declare function task(bot: TaskUnit, opts: TaskOptions, body: (this: void) => TaskBody): boolean;
export declare function Step(bot: TaskUnit, host: number): boolean;
export declare function Tick(bot: TaskUnit): void;
export declare function Cancel(bot: TaskUnit, reason: Result["reason"], message?: string): void;
export declare function Current(bot: TaskUnit): {
    name: string;
    host: number;
    startedAt: number;
    steps: number;
} | undefined;
export declare function Last(bot: TaskUnit): LastRun | undefined;
export declare function Describe(bot: TaskUnit): string;
export {};
