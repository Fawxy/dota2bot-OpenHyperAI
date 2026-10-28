import { aborted } from "./abort";
import { get as getAdapter } from "./adapter";
import { Ctx, makeCtx } from "./ctx";
import { Supported } from "./support";
import { Adapter, Result, TaskBody, TaskOptions, TaskUnit } from "./types";

/** Seconds a task may wait for its first `Step`, whatever the active mode, before it is cancelled. */
export const START_GRACE = 1.0;

const DEFAULT_TIER = "LANE_PLAN";
const DEFAULT_FLOOR = 0.6;
const DEFAULT_STALL_AFTER = 2.0;
const MAX_REPLACE = 8;

interface Running {
    name: string;
    host: number;
    tier: string;
    floor: number;
    source: string;
    startedAt: number;
    steps: number;
    body: TaskFactory;
    ctx?: Ctx;
    gen?: TaskBody;
    onEnd?: TaskOptions["onEnd"];
    guard?: TaskOptions["guard"];
    stallAfter: number;
    preemptAfter: number;
    lastStepAt: number;
    awaySince?: number;
    urgent: boolean;
    label?: string;
    claimedAt?: number;
    claimedUrgent?: boolean;
    ended: boolean;
}

interface LastRun {
    name: string;
    result: Result;
}

/** A task body factory. It receives the task's `Ctx`; factories that take no argument work unchanged. */
export type TaskFactory = (this: void, ctx: Ctx) => TaskBody;

const running: Record<number, Running | undefined> = {};
const last: Record<number, LastRun | undefined> = {};
const loggedRefusals: Record<string, boolean | undefined> = {};

function refuse(why: string): false {
    const a = getAdapter();
    if (a !== undefined && loggedRefusals[why] === undefined) {
        loggedRefusals[why] = true;
        a.log("tasks", "task refused: " + why);
    }
    return false;
}

// A task can be ended from inside its own resume or onEnd (Cancel, or a replacing `task`); only the first end
// counts, and a successor started meanwhile keeps its slot.
function finish(bot: TaskUnit, t: Running, result: Result): void {
    if (t.ended) return;
    t.ended = true;
    const id = bot.GetPlayerID();
    if (running[id] === t) running[id] = undefined;
    last[id] = { name: t.name, result };
    const a = getAdapter();
    if (a !== undefined) a.release(bot, t.source, t.host);
    const onEnd = t.onEnd;
    if (onEnd === undefined) return;
    const [ok, err] = pcall(() => onEnd(result, { label: t.label, steps: t.steps }));
    if (!ok && a !== undefined) a.log("tasks", "task " + t.name + " onEnd error: " + tostring(err));
}

// At most one claim per frame (a frame is one `now()` value), unless urgency changed since the last one.
function claim(a: Adapter, bot: TaskUnit, t: Running): void {
    const now = a.now();
    if (t.claimedAt === now && t.claimedUrgent === t.urgent) return;
    t.claimedAt = now;
    t.claimedUrgent = t.urgent;
    a.claim(bot, { source: t.source, mode: t.host, tier: t.tier, floor: t.floor, urgent: t.urgent });
}

function guarded(bot: TaskUnit, t: Running): boolean {
    if (t.guard === undefined) return false;
    const message = t.guard();
    if (message === undefined) return false;
    finish(bot, t, { success: false, reason: "interrupted", message });
    return true;
}

export function task(bot: TaskUnit, opts: TaskOptions, body: TaskFactory): boolean {
    const a = getAdapter();
    if (a === undefined) return refuse("no_adapter");
    if (!a.enabled()) return refuse("disabled");
    if (!Supported()) return refuse("unsupported");

    // Tasks started by a replaced task's onEnd are replaced too; an onEnd that always restarts is refused.
    for (let i = 0; i < MAX_REPLACE && running[bot.GetPlayerID()] !== undefined; i++) Cancel(bot, "cancelled", "replaced");
    if (running[bot.GetPlayerID()] !== undefined) return refuse("onEnd restarts endlessly");

    const now = a.now();
    const t: Running = {
        name: opts.name,
        host: opts.host,
        tier: opts.tier ?? DEFAULT_TIER,
        floor: opts.floor ?? DEFAULT_FLOOR,
        source: "task:" + opts.name,
        startedAt: now,
        steps: 0,
        body,
        onEnd: opts.onEnd,
        guard: opts.guard,
        stallAfter: opts.stallAfter ?? DEFAULT_STALL_AFTER,
        preemptAfter: opts.preemptAfter ?? 0,
        lastStepAt: now,
        urgent: false,
        ended: false,
    };
    t.ctx = makeCtx(bot, {
        startedAt: now,
        label: (label) => {
            t.label = label;
        },
        urgent: (on) => {
            t.urgent = on;
        },
    });
    running[bot.GetPlayerID()] = t;
    return true;
}

export function Step(bot: TaskUnit, host: number): boolean {
    const a = getAdapter();
    const t = running[bot.GetPlayerID()];
    if (a === undefined || t === undefined || t.host !== host || !a.enabled()) return false;
    if (guarded(bot, t)) return false;

    claim(a, bot, t);

    // The body factory is called lazily so its errors are caught by the same pcall as the resume.
    const [ok, res] = pcall(() => {
        if (t.gen === undefined) t.gen = t.body(t.ctx!);
        return t.gen.next();
    });
    t.steps += 1;
    t.lastStepAt = a.now();

    if (!ok) {
        const thrown = aborted(res);
        if (thrown !== undefined) {
            finish(bot, t, thrown);
            return true;
        }
        const message = tostring(res);
        a.log("tasks", "task " + t.name + " error: " + message);
        finish(bot, t, { success: false, reason: "error", message });
    } else if (res.done) {
        finish(bot, t, (res.value as Result | undefined) ?? { success: true, reason: "ok" });
    }
    return true;
}

/**
 * Every frame from the host's global tick. Re-posts the claim while the task is live, so the host can win
 * the mode before the first `Step`; the grace and stall limits keep an unstepped task from pinning it.
 */
export function Tick(bot: TaskUnit): void {
    const a = getAdapter();
    const t = running[bot.GetPlayerID()];
    if (t === undefined) return;
    if (a === undefined || !a.enabled()) {
        Cancel(bot, "cancelled", "disabled");
        return;
    }
    if (!bot.IsAlive()) {
        Cancel(bot, "dead");
        return;
    }
    if (guarded(bot, t)) return;

    const now = a.now();
    if (t.steps === 0) {
        if (now - t.startedAt > START_GRACE) {
            Cancel(bot, "preempted", "never_started");
            return;
        }
    } else {
        const mode = bot.GetActiveMode();
        if (mode === t.host) {
            t.awaySince = undefined;
        } else {
            if (t.awaySince === undefined) t.awaySince = now;
            if (now - t.awaySince >= t.preemptAfter) {
                Cancel(bot, "preempted", "mode=" + mode);
                return;
            }
        }
        if (now - t.lastStepAt > t.stallAfter) {
            Cancel(bot, "preempted", "stalled");
            return;
        }
    }
    claim(a, bot, t);
}

export function Cancel(bot: TaskUnit, reason: Result["reason"], message?: string): void {
    const t = running[bot.GetPlayerID()];
    if (t === undefined) return;
    finish(bot, t, { success: false, reason, message });
}

/** Sets or clears urgency on the current task's claims from the next one posted; callable from a body. */
export function Urgent(bot: TaskUnit, on: boolean): void {
    const t = running[bot.GetPlayerID()];
    if (t !== undefined) t.urgent = on;
}

/** Sets a free-form label on the current task, shown by `Current`/`Describe` and passed to `onEnd`. */
export function Label(bot: TaskUnit, label: string): void {
    const t = running[bot.GetPlayerID()];
    if (t !== undefined) t.label = label;
}

export function Current(
    bot: TaskUnit,
):
    | { name: string; host: number; startedAt: number; steps: number; label?: string; preemptAfter: number }
    | undefined {
    const t = running[bot.GetPlayerID()];
    if (t === undefined) return undefined;
    const { name, host, startedAt, steps, label, preemptAfter } = t;
    return { name, host, startedAt, steps, label, preemptAfter };
}

export function Last(bot: TaskUnit): LastRun | undefined {
    return last[bot.GetPlayerID()];
}

export function Describe(bot: TaskUnit): string {
    const t = running[bot.GetPlayerID()];
    if (t !== undefined) return t.name + (t.label !== undefined ? ":" + t.label : "") + " step=" + t.steps;
    const l = last[bot.GetPlayerID()];
    if (l !== undefined) return "- last=" + l.name + " " + (l.result.success ? "ok" : l.result.reason);
    return "-";
}
