import { get } from "./adapter";
import { TaskBody, TaskTarget, TaskUnit, Vec } from "./types";
import { random } from "./skill";
import { dist, expired, fail, hold, now, ok, StopOpts, stopped, targetLost } from "./verbs_util";

export type { StopOpts } from "./verbs_util";

export interface WalkOpts extends StopOpts {
    /** Distance from a waypoint that counts as reached. Default 150. */
    tolerance?: number;
    /** Seconds for the whole walk. Default 10. */
    timeout?: number;
    /** Seconds without progress (stuns excluded) before failing `stuck`. Default 1.5. */
    stuckSecs?: number;
}

export function* walkTo(bot: TaskUnit, loc: Vec, opts: WalkOpts = {}): TaskBody {
    return yield* walkPath(bot, [loc], opts);
}

/**
 * Walks through `points` in order. Each frame, every leading waypoint already within tolerance is skipped,
 * so a bot that starts at (or overshoots onto) later waypoints never walks back. `timeout` runs from the
 * start of the walk; stuck detection restarts at each new waypoint and is disabled by `stuckSecs = math.huge`.
 */
export function* walkPath(bot: TaskUnit, points: Vec[], opts: WalkOpts = {}): TaskBody {
    const tolerance = opts.tolerance ?? 150;
    const timeout = opts.timeout ?? 10;
    const stuckSecs = opts.stuckSecs ?? 1.5;
    const start = now();
    let i = 0;
    let tracking = -1;
    let prev = start;
    let best = 0;
    // Seconds without a 25-unit improvement towards points[i], excluding time spent stunned.
    let stuckClock = 0;
    while (true) {
        const t = now();
        if (!bot.IsAlive()) return fail("dead");
        while (i < points.length && dist(bot.GetLocation(), points[i]) <= tolerance) i++;
        if (i >= points.length) return ok();
        if (opts.interruptIf !== undefined && opts.interruptIf()) return fail("interrupted");
        if (t - start > timeout || expired(opts.deadline)) return fail("timeout");
        const d = dist(bot.GetLocation(), points[i]);
        if (tracking !== i) {
            tracking = i;
            best = d;
            stuckClock = 0;
        } else if (d <= best - 25) {
            best = d;
            stuckClock = 0;
        } else if (!(bot.IsStunned?.() ?? false)) {
            stuckClock += t - prev;
        }
        prev = t;
        if (stuckClock >= stuckSecs) return fail("stuck");
        bot.Action_MoveToLocation(points[i]);
        yield;
    }
}

export function* wait(bot: TaskUnit, secs: number, opts: StopOpts = {}): TaskBody {
    const start = now();
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        if (opts.interruptIf !== undefined && opts.interruptIf()) return fail("interrupted");
        if (now() - start >= secs) return ok();
        if (expired(opts.deadline)) return fail("timeout");
        yield;
    }
}

export interface WaitUntilOpts extends StopOpts {
    /** Adapter hold tag reported every frame while waiting. */
    hold?: string;
}

/** Finishes as soon as game time reaches `t`, on the first resume without yielding if it already has. */
export function* waitUntil(bot: TaskUnit, t: number, opts: WaitUntilOpts = {}): TaskBody {
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        if (now() >= t) return ok();
        if (opts.interruptIf !== undefined && opts.interruptIf()) return fail("interrupted");
        if (expired(opts.deadline)) return fail("timeout");
        hold(bot, opts.hold);
        yield;
    }
}

export interface RetreatOpts extends WalkOpts {
    safe: Vec;
}

/** `walkTo(opts.safe)` with retreat defaults: tolerance 300, timeout 20, stuckSecs 3. */
export function* retreatTo(bot: TaskUnit, opts: RetreatOpts): TaskBody {
    return yield* walkTo(bot, opts.safe, {
        ...opts,
        tolerance: opts.tolerance ?? 300,
        timeout: opts.timeout ?? 20,
        stuckSecs: opts.stuckSecs ?? 3,
    });
}

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
export function* attackAndConfirm(
    bot: TaskUnit,
    pick: (this: void) => TaskTarget | undefined,
    opts: AttackConfirmOpts,
): TaskBody {
    if (bot.GetLastAttackTime === undefined) return fail("unsupported");
    const start = now();
    let target: TaskTarget | undefined;
    let baseline = 0;
    let orderedAt = 0;
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        const stop = stopped(opts);
        if (stop !== undefined) return stop;
        if (target === undefined) {
            target = pick();
            if (target !== undefined) {
                bot.Action_AttackUnit(target, true);
                baseline = bot.GetLastAttackTime();
                orderedAt = now();
            } else if (now() - start >= opts.findFor) {
                return fail("no_target");
            } else if (opts.searchAt !== undefined) {
                bot.Action_MoveToLocation(opts.searchAt);
            }
        } else if (
            bot.GetLastAttackTime() > baseline ||
            target.GetAttackTarget?.() === bot ||
            (opts.confirmed?.() ?? false)
        ) {
            return ok();
        } else if (now() - orderedAt >= opts.confirmFor) {
            return fail("missed");
        } else if (targetLost(target)) {
            target = undefined;
        } else {
            hold(bot, opts.hold);
        }
        yield;
    }
}

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

function vec(x: number, y: number, z: number | undefined): Vec {
    const make = get()!.vector;
    return make !== undefined ? make(x, y, z ?? 0) : { x, y, z };
}

function scattered(p: Vec, r: number): Vec {
    if (r <= 0) return p;
    const a = random() * 2 * Math.PI;
    const d = random() * r;
    return vec(p.x + Math.cos(a) * d, p.y + Math.sin(a) * d, p.z);
}

// A step of [min, max] from `from` in a random direction; when that leaves the disc of radius r around p, the
// step is taken towards p instead, and clamped to the disc.
function stepped(from: Vec, p: Vec, r: number, min: number, max: number): Vec {
    const len = min + random() * (max - min);
    const a = random() * 2 * Math.PI;
    let x = from.x + Math.cos(a) * len;
    let y = from.y + Math.sin(a) * len;
    if (dist({ x, y }, p) > r) {
        const d = dist(from, p);
        if (d > 1e-6) {
            x = from.x + ((p.x - from.x) / d) * len;
            y = from.y + ((p.y - from.y) / d) * len;
        }
        const e = dist({ x, y }, p);
        if (e > r) {
            x = p.x + ((x - p.x) / e) * r;
            y = p.y + ((y - p.y) / e) * r;
        }
    }
    return vec(x, y, p.z);
}

/**
 * Posture verb: keeps the bot within `tolerance` of `point()` (re-read every frame) and never ends `ok` by itself.
 * A new spot is picked when the point moves more than half the tolerance or every `repath` s (+jitter). An order
 * is issued on every resume (walk to the spot, or stand on the bot's own location), so an order the host gave
 * between resumes never sticks. `point()` returning undefined stands the bot still.
 */
export function* holdAt(bot: TaskUnit, point: (this: void) => Vec | undefined, opts: HoldOpts = {}): TaskBody {
    const tolerance = opts.tolerance ?? 100;
    const repath = opts.repath ?? 1;
    const jitter = opts.jitter ?? 0.3;
    const scatter = opts.scatter ?? 50;
    const follow = opts.follow ?? tolerance / 2;
    let anchor: Vec | undefined;
    let spot: Vec | undefined;
    let nextPick = 0;
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        if (opts.interruptIf !== undefined && opts.interruptIf()) return fail("interrupted");
        if (expired(opts.deadline)) return fail("timeout");
        const t = now();
        const p = point();
        if (p === undefined) {
            anchor = undefined;
            bot.Action_MoveToLocation(bot.GetLocation());
            hold(bot, opts.hold);
        } else {
            if (anchor === undefined || t >= nextPick || dist(p, anchor) > follow) {
                const step = opts.step;
                const here = bot.GetLocation();
                spot =
                    step !== undefined && dist(here, p) <= scatter + tolerance
                        ? stepped(here, p, scatter, step[0], step[1])
                        : scattered(p, scatter);
                anchor = p;
                nextPick = t + repath * (1 + jitter * (random() - 0.5));
            }
            if (dist(bot.GetLocation(), spot!) > tolerance) {
                bot.Action_MoveToLocation(spot!);
            } else {
                bot.Action_MoveToLocation(bot.GetLocation());
                hold(bot, opts.hold);
            }
        }
        yield;
    }
}
