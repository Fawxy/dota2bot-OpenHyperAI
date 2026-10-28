import { get } from "./adapter";
import { abort, must } from "./abort";
import { Reason, Result, TaskBody, TaskUnit, Vec } from "./types";
import * as Skill from "./skill";
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
    /** Job verbs: phases are reported through this task's `label`/`urgent`. */
    stack(this: void, plan: Verbs.StackPlan): TaskBody;
    pull(this: void, plan: Verbs.PullPlan): TaskBody;
    runeRun(this: void, plan: Verbs.RunePlan): TaskBody;
    clearCamp(this: void, plan: Verbs.ClearPlan): TaskBody;
    gank(this: void, plan: Verbs.GankPlan): TaskBody;
}

export interface CtxControls {
    startedAt: number;
    label(this: void, label: string): void;
    urgent(this: void, on: boolean): void;
}

export function makeCtx(bot: TaskUnit, c: CtxControls): Ctx {
    const now = (): number => get()!.now();
    const hooks: Verbs.JobHooks = { label: c.label, urgent: c.urgent };
    return {
        bot,
        now,
        elapsed: () => now() - c.startedAt,
        label: c.label,
        urgent: c.urgent,
        ok: () => ({ success: true, reason: "ok" }),
        fail: (reason, message) => ({ success: false, reason, message }),
        abort,
        must,
        skill: () => Skill.of(bot),
        react: () => Skill.react(bot),
        jitter: (secs) => Skill.jitter(bot, secs),

        walkTo: (loc: Vec, opts?: Verbs.WalkOpts) => Verbs.walkTo(bot, loc, opts),
        walkPath: (points: Vec[], opts?: Verbs.WalkOpts) => Verbs.walkPath(bot, points, opts),
        holdAt: (point, opts) => Verbs.holdAt(bot, point, opts),
        wait: (secs, opts) => Verbs.wait(bot, secs, opts),
        waitUntil: (t, opts) => Verbs.waitUntil(bot, t, opts),
        retreatTo: (opts) => Verbs.retreatTo(bot, opts),
        lastHit: (opts) => Verbs.lastHit(bot, opts),
        laneFarm: (spot, opts) => Verbs.laneFarm(bot, spot, { label: c.label, ...opts }),
        deny: (opts) => Verbs.deny(bot, opts),
        attackAndConfirm: (pick, opts) => Verbs.attackAndConfirm(bot, pick, opts),
        cast: (ability, opts) => Verbs.cast(bot, ability, opts),
        useItem: (name, opts) => Verbs.useItem(bot, name, opts),
        pickUpRune: (rune, opts) => Verbs.pickUpRune(bot, rune, opts),
        stack: (plan) => Verbs.stack(bot, plan, hooks),
        pull: (plan) => Verbs.pull(bot, plan, hooks),
        runeRun: (plan) => Verbs.runeRun(bot, plan, hooks),
        clearCamp: (plan) => Verbs.clearCamp(bot, plan, hooks),
        gank: (plan) => Verbs.gank(bot, plan, hooks),
    };
}
