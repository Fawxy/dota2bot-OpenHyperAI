// Internal helpers shared by the verb modules; not part of the public `Verbs` namespace.
import { get } from "./adapter";
import { Reason, Result, TaskTarget, TaskUnit, Vec } from "./types";

export function ok(): Result {
    return { success: true, reason: "ok" };
}

export function fail(reason: Reason, message?: string): Result {
    return { success: false, reason, message };
}

export function now(): number {
    return get()!.now();
}

/** True once game time has reached `deadline`; verbs then fail `timeout`. */
export function expired(deadline: number | undefined): boolean {
    return deadline !== undefined && now() >= deadline;
}

export function dist(a: Vec, b: Vec): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
}

/** Reports a deliberate stand-still to the adapter's `hold`; no tag, no report. */
export function hold(bot: TaskUnit, tag: string | undefined): void {
    if (tag === undefined) return;
    const a = get()!;
    if (a.hold !== undefined) a.hold(bot, tag);
}

/** Released, dead or out of sight. */
export function targetLost(t: TaskTarget): boolean {
    return (t.IsNull?.() ?? false) || !t.IsAlive() || !(t.CanBeSeen?.() ?? true);
}

/** The stop options every verb takes. */
export interface StopOpts {
    /** Absolute game time (`now()` clock); the verb fails `timeout` once it is reached. */
    deadline?: number;
    /** Checked every frame; true fails the verb `interrupted`. */
    interruptIf?: (this: void) => boolean;
}

/** `interrupted` or `timeout` when `opts` says to stop now, else undefined. */
export function stopped(opts: StopOpts): Result | undefined {
    if (opts.interruptIf !== undefined && opts.interruptIf()) return fail("interrupted");
    if (expired(opts.deadline)) return fail("timeout");
    return undefined;
}
