/** @noSelfInFile */
import { TaskBody, TaskTarget, TaskUnit, Vec } from "./types";
import { StopOpts } from "./verbs_util";
export type { StopOpts } from "./verbs_util";
export interface WalkOpts extends StopOpts {
    /** Distance from a waypoint that counts as reached. Default 150. */
    tolerance?: number;
    /** Seconds for the whole walk. Default 10. */
    timeout?: number;
    /** Seconds without progress (stuns excluded) before failing `stuck`. Default 1.5. */
    stuckSecs?: number;
}
export declare function walkTo(bot: TaskUnit, loc: Vec, opts?: WalkOpts): TaskBody;
/**
 * Walks through `points` in order. Each frame, every leading waypoint already within tolerance is skipped,
 * so a bot that starts at (or overshoots onto) later waypoints never walks back. `timeout` runs from the
 * start of the walk; stuck detection restarts at each new waypoint and is disabled by `stuckSecs = math.huge`.
 */
export declare function walkPath(bot: TaskUnit, points: Vec[], opts?: WalkOpts): TaskBody;
export declare function wait(bot: TaskUnit, secs: number, opts?: StopOpts): TaskBody;
export interface WaitUntilOpts extends StopOpts {
    /** Adapter hold tag reported every frame while waiting. */
    hold?: string;
}
/** Finishes as soon as game time reaches `t`, on the first resume without yielding if it already has. */
export declare function waitUntil(bot: TaskUnit, t: number, opts?: WaitUntilOpts): TaskBody;
export interface RetreatOpts extends WalkOpts {
    safe: Vec;
}
/** `walkTo(opts.safe)` with retreat defaults: tolerance 300, timeout 20, stuckSecs 3. */
export declare function retreatTo(bot: TaskUnit, opts: RetreatOpts): TaskBody;
export interface AttackConfirmOpts extends StopOpts {
    /** Seconds from the verb's start to keep calling `pick` before giving up with `no_target`. */
    findFor: number;
    /** Seconds from the latest attack order to see it land before giving up with `missed`. */
    confirmFor: number;
    /** Walked towards while `pick` finds nothing. */
    searchAt?: Vec;
    hold?: string;
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
export interface HoldOpts extends StopOpts {
    /** Distance from the target spot that counts as there. Default 100. */
    tolerance?: number;
    /** Seconds between picks of a new spot while the point stays put. Default 1. */
    repath?: number;
    /** Fraction of `repath` the interval varies by, uniformly (0.3 = +-15%). Default 0.3. */
    jitter?: number;
    /** Each spot is the point plus a random offset of up to this many units. Default 50. */
    scatter?: number;
    /** Adapter hold tag reported every frame the bot stands still. */
    hold?: string;
    /**
     * Idle steps: each new spot is a step of [min, max] units from where the bot stands (kept within `scatter`
     * of the point), instead of a random offset from the point, so a waiting laner shuffles rather than freezes.
     */
    step?: [number, number];
    /** How far the point must move to force a new spot before `repath`. Default tolerance / 2. */
    follow?: number;
}
/**
 * Posture verb: keeps the bot within `tolerance` of `point()` (re-read every frame) and never ends `ok` by itself.
 * A new spot is picked when the point moves more than half the tolerance or every `repath` s (+jitter). An order
 * is issued on every resume (walk to the spot, or stand on the bot's own location), so an order the host gave
 * between resumes never sticks. `point()` returning undefined stands the bot still.
 */
export declare function holdAt(bot: TaskUnit, point: (this: void) => Vec | undefined, opts?: HoldOpts): TaskBody;
