/** @noSelfInFile */
import { Reason, Result, TaskBody, TaskUnit } from "./types";
import * as Verbs from "./verbs_all";
type Opt<F> = F extends (bot: TaskUnit, ...rest: infer R) => TaskBody ? R : never;
/** What a task body receives: the bot, task controls, and every verb bound to the bot. */
export interface Ctx {
    readonly bot: TaskUnit;
    now(this: void): number;
    /** Seconds since the task was started. */
    elapsed(this: void): number;
    label(this: void, label: string): void;
    urgent(this: void, on: boolean): void;
    ok(this: void): Result;
    fail(this: void, reason: Reason, message?: string): Result;
    /** Ends the task with a failure from any depth (throws; the runner catches it). */
    abort(this: void, reason: Reason, message?: string): never;
    must(this: void, g: TaskBody, message?: string): TaskBody;
    /** The bot's execution skill in [0, 1], read through the adapter on every call (default 1). */
    skill(this: void): number;
    /** One sampled reaction delay in seconds from the adapter's profile (0 without one). */
    react(this: void): number;
    /** `secs` scaled by the profile's jitter: secs * (1 +- jitter/2). */
    jitter(this: void, secs: number): number;
    walkTo(this: void, ...a: Opt<typeof Verbs.walkTo>): TaskBody;
    walkPath(this: void, ...a: Opt<typeof Verbs.walkPath>): TaskBody;
    holdAt(this: void, ...a: Opt<typeof Verbs.holdAt>): TaskBody;
    wait(this: void, ...a: Opt<typeof Verbs.wait>): TaskBody;
    waitUntil(this: void, ...a: Opt<typeof Verbs.waitUntil>): TaskBody;
    retreatTo(this: void, ...a: Opt<typeof Verbs.retreatTo>): TaskBody;
    lastHit(this: void, ...a: Opt<typeof Verbs.lastHit>): TaskBody;
    /** Laner posture: hold the spot, break off for last hits and denies; phases go to this task's label. */
    laneFarm(this: void, ...a: Opt<typeof Verbs.laneFarm>): TaskBody;
    deny(this: void, ...a: Opt<typeof Verbs.deny>): TaskBody;
    attackAndConfirm(this: void, ...a: Opt<typeof Verbs.attackAndConfirm>): TaskBody;
    cast(this: void, ...a: Opt<typeof Verbs.cast>): TaskBody;
    useItem(this: void, ...a: Opt<typeof Verbs.useItem>): TaskBody;
    pickUpRune(this: void, ...a: Opt<typeof Verbs.pickUpRune>): TaskBody;
}
export interface CtxControls {
    startedAt: number;
    label(this: void, label: string): void;
    urgent(this: void, on: boolean): void;
}
export declare function makeCtx(bot: TaskUnit, c: CtxControls): Ctx;
export {};
