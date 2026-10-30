import { get } from "./adapter";
import { HoldOpts, holdAt } from "./verbs";
import { deny, lastHit, LaneTarget, laneTargets, LastHitOpts } from "./lasthit";
import { Result, TaskBody, TaskUnit, Vec } from "./types";

export interface LaneFarmOpts {
    /** holdAt options for standing at the spot (its interruptIf is the verb's own). */
    hold?: HoldOpts;
    /** Whether to go for last hits and denies now; read every frame. Default: always. */
    lastHits?: (this: void) => boolean;
    /** laneTargets' `within`. Default 1. */
    within?: number;
    /**
     * Which of the creeps laneTargets offers to go for (or none). The engine makes no choice of its own: without
     * `pick` the verb only holds the spot.
     */
    pick?: (this: void, targets: LaneTarget[]) => LaneTarget | undefined;
    /** An attempt is dropped once the bot is this far from the spot. Default 900. */
    leash?: number;
    /** Within this of the spot the label is `hold`, beyond `far` it is `walk` again. Defaults 600 / 1200. */
    near?: number;
    far?: number;
    /** Seconds between looks for the next creep while holding (a scan of every creep nearby). Default 0.1. */
    scanEvery?: number;
    /** Enemy heroes within this of the bot at an attempt's start make it `contested`. Default 1000. */
    contestRadius?: number;
    label?: (this: void, label: string) => void;
    /** Called after every last-hit or deny attempt. */
    onAttempt?: (this: void, target: LaneTarget, result: Result, contested: boolean) => void;
    deadline?: number;
    interruptIf?: (this: void) => boolean;
}

function dist(a: Vec, b: Vec): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
}

function enemyHeroNear(bot: TaskUnit, r: number): boolean {
    for (const h of bot.GetNearbyHeroes?.(r, true, 0) ?? []) if (h.IsAlive?.() ?? true) return true;
    return false;
}

/**
 * Posture verb for a laner: holds `spot()` (re-read every frame) and, while `lastHits()` allows, breaks off for
 * the creep `pick` chooses from laneTargets (walking in so it arrives as the creep becomes killable), swings with the
 * skill-scaled lastHit/deny verbs, then walks back. Never ends ok by itself; ends on death, `deadline`,
 * `interruptIf`. Labels phases `walk` / `hold` / `lasthit` / `deny`.
 */
export function* laneFarm(bot: TaskUnit, spot: (this: void) => Vec | undefined, opts: LaneFarmOpts = {}): TaskBody {
    const near = opts.near ?? 600;
    const far = opts.far ?? 1200;
    const leash = opts.leash ?? 900;
    const label = opts.label ?? (() => undefined);
    const away = (): number => {
        const p = spot();
        return p !== undefined ? dist(bot.GetLocation(), p) : 0;
    };
    let target: LaneTarget | undefined;
    const scanEvery = opts.scanEvery ?? 0.1;
    let scannedAt = -math.huge;
    const pick = (): boolean => {
        const t = get()!.now();
        if (t - scannedAt < scanEvery) return false;
        scannedAt = t;
        if (opts.pick === undefined || (opts.lastHits !== undefined && !opts.lastHits())) return false;
        // Not beyond the leash: an attempt there is dropped at once, and picking it again would spin.
        if (away() > leash) return false;
        const offered = laneTargets(bot, { within: opts.within });
        target = offered.length > 0 ? opts.pick(offered) : undefined;
        return target !== undefined;
    };
    const stop = (): boolean => (opts.interruptIf !== undefined && opts.interruptIf()) || (opts.deadline !== undefined && get()!.now() >= opts.deadline);
    let atSpot = false;
    let passAt: number | undefined;
    while (true) {
        // Backstop: a pass of this loop that took no frame (an exit fired before any yield) yields once, so no
        // condition flip can spin the coroutine inside one resume.
        const t0 = get()!.now();
        if (passAt === t0) yield;
        passAt = get()!.now();
        label(atSpot ? "hold" : "walk");
        const r = yield* holdAt(bot, spot, {
            ...(opts.hold ?? {}),
            deadline: opts.deadline,
            interruptIf: () => {
                if (stop()) return true;
                const d = spot() !== undefined ? away() : undefined;
                if (atSpot ? (d ?? 0) > far : (d ?? math.huge) <= near) return true;
                return pick();
            },
        });
        if (r.reason !== "interrupted") return r;
        if (stop()) return { success: false, reason: "interrupted" };
        if (target === undefined) {
            const d = spot() !== undefined ? away() : undefined;
            atSpot = d !== undefined && d <= (atSpot ? far : near);
            continue;
        }
        const t = target;
        target = undefined;
        const contested = enemyHeroNear(bot, opts.contestRadius ?? 1000);
        label(t.kind);
        const o: LastHitOpts = {
            target: t.creep,
            maxWait: t.eta + 1.5,
            deadline: opts.deadline,
            hold: opts.hold?.hold,
            interruptIf: () => stop() || away() > leash,
        };
        const res = t.kind === "lasthit" ? yield* lastHit(bot, o) : yield* deny(bot, o);
        if (opts.onAttempt !== undefined) opts.onAttempt(t, res, contested);
        if (res.reason === "dead") return res;
    }
}
