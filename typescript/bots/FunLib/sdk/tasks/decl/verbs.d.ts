/** @noSelfInFile */
import { TaskBody, TaskCreep, TaskUnit, Vec } from "./types";
export interface WalkOpts {
    tolerance?: number;
    timeout?: number;
    stuckSecs?: number;
    interruptIf?: (this: void) => boolean;
}
export declare function walkTo(bot: TaskUnit, loc: Vec, opts?: WalkOpts): TaskBody;
export declare function wait(bot: TaskUnit, secs: number, opts?: {
    interruptIf?: (this: void) => boolean;
}): TaskBody;
export declare function retreatTo(bot: TaskUnit, opts: {
    safe: Vec;
    tolerance?: number;
    timeout?: number;
}): TaskBody;
export interface LastHitOpts {
    maxWait?: number;
    target?: TaskCreep;
    searchRadius?: number;
}
export declare function lastHit(bot: TaskUnit, opts?: LastHitOpts): TaskBody;
