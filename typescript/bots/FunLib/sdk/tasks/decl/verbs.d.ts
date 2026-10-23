/** @noSelfInFile */
import { TaskBody, TaskCreep, TaskTarget, TaskUnit, Vec } from "./types";
export interface WalkOpts {
    tolerance?: number;
    timeout?: number;
    deadline?: number;
    stuckSecs?: number;
    interruptIf?: (this: void) => boolean;
}
export declare function walkTo(bot: TaskUnit, loc: Vec, opts?: WalkOpts): TaskBody;
/**
 * Walks through `points` in order. Each frame, every leading waypoint already within tolerance is skipped,
 * so a bot that starts at (or overshoots onto) later waypoints never walks back. `timeout` runs from the
 * start of the walk; stuck detection restarts at each new waypoint and is disabled by `stuckSecs = math.huge`.
 */
export declare function walkPath(bot: TaskUnit, points: Vec[], opts?: WalkOpts): TaskBody;
export declare function wait(bot: TaskUnit, secs: number, opts?: {
    deadline?: number;
    interruptIf?: (this: void) => boolean;
}): TaskBody;
/** Finishes as soon as game time reaches `t`, on the first resume without yielding if it already has. */
export declare function waitUntil(bot: TaskUnit, t: number, opts?: {
    hold?: string;
    deadline?: number;
    interruptIf?: (this: void) => boolean;
}): TaskBody;
export declare function retreatTo(bot: TaskUnit, opts: {
    safe: Vec;
    tolerance?: number;
    timeout?: number;
}): TaskBody;
export interface LastHitOpts {
    maxWait?: number;
    deadline?: number;
    target?: TaskCreep;
    searchRadius?: number;
}
export declare function lastHit(bot: TaskUnit, opts?: LastHitOpts): TaskBody;
export interface AttackConfirmOpts {
    /** Seconds from the verb's start to keep calling `pick` before giving up with `no_target`. */
    findFor: number;
    /** Seconds from the latest attack order to see it land before giving up with `missed`. */
    confirmFor: number;
    /** Walked towards while `pick` finds nothing. */
    searchAt?: Vec;
    hold?: string;
    /** Absolute game time after which the verb fails `timeout` if not yet confirmed. */
    deadline?: number;
    /** Extra host-specific confirmation, checked alongside the bot's own signals. */
    confirmed?: (this: void) => boolean;
}
/**
 * Orders a queued attack on `pick()` and finishes `ok` once it is confirmed to have landed: the bot's last
 * attack time rose past its reading at the order (never compared with another clock), the target is
 * attacking the bot, or `opts.confirmed()`. A target that dies or vanishes before confirmation is dropped and
 * a new one picked and ordered the next frame, which restarts the `confirmFor` clock.
 */
export declare function attackAndConfirm(bot: TaskUnit, pick: (this: void) => TaskTarget | undefined, opts: AttackConfirmOpts): TaskBody;
