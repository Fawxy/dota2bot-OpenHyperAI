/** @noSelfInFile */
import { Reason, Result, TaskAbility, TaskBody, TaskTarget, TaskUnit } from "./types";
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
    walkTo(this: void, ...a: Opt<typeof Verbs.walkTo>): TaskBody;
    walkPath(this: void, ...a: Opt<typeof Verbs.walkPath>): TaskBody;
    holdAt(this: void, ...a: Opt<typeof Verbs.holdAt>): TaskBody;
    wait(this: void, ...a: Opt<typeof Verbs.wait>): TaskBody;
    waitUntil(this: void, ...a: Opt<typeof Verbs.waitUntil>): TaskBody;
    retreatTo(this: void, ...a: Opt<typeof Verbs.retreatTo>): TaskBody;
    lastHit(this: void, ...a: Opt<typeof Verbs.lastHit>): TaskBody;
    attackAndConfirm(this: void, pick: (this: void) => TaskTarget | undefined, opts: Verbs.AttackConfirmOpts): TaskBody;
    cast(this: void, ability: TaskAbility | undefined, opts?: Verbs.CastOpts): TaskBody;
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
