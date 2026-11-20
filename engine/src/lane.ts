import { get } from "./adapter";
import { attackAndConfirm, HoldOpts, holdAt } from "./verbs";
import { deny, lastHit, LaneTarget, laneTargets, LastHitOpts, ownHitTime } from "./lasthit";
import { Result, TaskBody, TaskUnit, Vec } from "./types";

export interface LaneFarmOpts {
    /** holdAt options for standing at the spot (its interruptIf is the verb's own). */
    hold?: HoldOpts;
    /** Whether to go for last hits and denies now; read every frame. Default: always. */
    lastHits?: (this: void) => boolean;
    /** laneTargets' `within`. Default 1. */
    within?: number;
    /** laneTargets' `radius` (how far from the bot creeps are offered). Default laneTargets' own: max(800, attack range + 400). */
    radius?: number;
    /**
     * Which of the creeps laneTargets offers to go for (or none). The engine makes no choice of its own: without
     * `pick` the verb only holds the spot. With `retarget`, `current` is the creep an attempt is waiting for when
     * the verb asks whether to stay on it (its fresh facts are among `targets`): returning another creep ends the
     * attempt for it; returning `current`'s creep keeps waiting, and undefined keeps waiting or, with `dropLost`, releases it. Whether a switch is worth the
     * attack cooldown is the caller's rule. `pick` is asked on every scan, also when laneTargets offers nothing (`targets`
     * empty), so it may answer a creep of its own: a target of kind `prehit` (built by the caller; laneTargets never offers
     * one) is carried out as one attack on the creep (`attackAndConfirm`, confirmed only by the bot's own attack firing),
     * after which the verb scans again. With `retarget`, a `prehit` on the creep an attempt waits for replaces that attempt.
     */
    pick?: (this: void, targets: LaneTarget[], current?: LaneTarget) => LaneTarget | undefined;
    /** An attempt is dropped once the bot is this far from the spot. Default 900. */
    leash?: number;
    /** Within this of the spot the label is `hold`, beyond `far` it is `walk` again. Defaults 600 / 1200. */
    near?: number;
    far?: number;
    /** Seconds between looks for the next creep while holding (a scan of every creep nearby). Default 0.1. */
    scanEvery?: number;
    /**
     * While an attempt waits for its creep (before the swing), keep scanning every `scanEvery`; once the creep is no
     * longer among laneTargets' offers and `pick` chooses another, drop the attempt (`interrupted`, message `sw=1`)
     * and go for that one. Default false: an attempt waits for its creep up to its eta + 1.5 s.
     */
    retarget?: boolean;
    /**
     * With `retarget`: also drop the attempt (`interrupted`, message `sw=0`) when its creep is no longer offered and `pick`
     * has nothing else, instead of waiting out its eta + 1.5 s, and when its creep is still offered but `pick(offers,
     * current)` answers undefined (the caller releases it). A creep drops out of the offers when the others' damage will kill
     * it before a swing ordered now lands. Default false. A function is asked with the waited-on creep's target each time
     * the rule would apply, so a caller can release some attempts and keep waiting on others.
     */
    dropLost?: boolean | ((this: void, current: LaneTarget) => boolean);
    /** Enemy heroes within this of the bot at an attempt's start make it `contested`. Default 1000. */
    contestRadius?: number;
    label?: (this: void, label: string) => void;
    /** Called after every last-hit or deny attempt. */
    onAttempt?: (this: void, target: LaneTarget, result: Result, contested: boolean) => void;
    deadline?: number;
    interruptIf?: (this: void) => boolean;
}

/** Seconds past the expected attack before a pre-hit that has not fired counts as `missed`. */
const PREHIT_SLACK = 0.5;

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
 * skill-scaled lastHit/deny verbs (a `prehit` pick with one plain attack), then walks back. Never ends ok by itself; ends on death, `deadline`,
 * `interruptIf`. Labels phases `walk` / `hold` / `lasthit` / `deny` / `prehit`.
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
        target = opts.pick(laneTargets(bot, { within: opts.within, radius: opts.radius }));
        return target !== undefined;
    };
    const stop = (): boolean => (opts.interruptIf !== undefined && opts.interruptIf()) || (opts.deadline !== undefined && get()!.now() >= opts.deadline);
    // While an attempt waits, `pick` is asked every scan whether to stay on its creep (passed as `current` while
    // laneTargets still offers it) or go for another; a creep no longer offered is left as before. In the lane-only
    // calibration games (llhscn1, 03/11/2026) 71% of the creeps that died in a core's range with no attempt died
    // while the body waited on another creep that was still offered.
    const retarget = (current: LaneTarget): boolean => {
        if (!opts.retarget) return false;
        const t = get()!.now();
        if (t - scannedAt < scanEvery) return false;
        scannedAt = t;
        if (opts.pick === undefined || (opts.lastHits !== undefined && !opts.lastHits())) return false;
        const offered = laneTargets(bot, { within: opts.within, radius: opts.radius });
        const drops = (): boolean => (typeof opts.dropLost === "function" ? opts.dropLost(current) : opts.dropLost === true);
        // Handle identity holds across scans in game (contract laneFarm, evidence: ER-008 re-run s5c).
        let still: LaneTarget | undefined;
        for (const o of offered) if (o.creep === current.creep) still = o;
        if (still !== undefined) {
            const next = opts.pick(offered, still);
            // With dropLost, a pick that no longer answers the creep it waits on releases it (the caller's claim on it ended,
            // or it can no longer be reached): the attempt ends sw=0 before its swing.
            if (next === undefined && drops()) {
                dropped = true;
                return true;
            }
            if (next === undefined || (next.creep === current.creep && next.kind === current.kind)) return false;
            target = next;
            return true;
        }
        target = opts.pick(offered);
        if (target === undefined && drops()) dropped = true;
        return target !== undefined || dropped;
    };
    let dropped = false;
    let atSpot = false;
    let passAt: number | undefined;
    while (true) {
        // Backstop: a pass of this loop that took no frame (an exit fired before any yield) yields once, so no
        // condition flip can spin the coroutine inside one resume.
        const t0 = get()!.now();
        if (passAt === t0) yield;
        passAt = get()!.now();
        if (target === undefined) {
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
        }
        const t = target;
        target = undefined;
        dropped = false;
        const contested = enemyHeroNear(bot, opts.contestRadius ?? 1000);
        label(t.kind);
        const o: LastHitOpts = {
            target: t.creep,
            maxWait: t.eta + 1.5,
            deadline: opts.deadline,
            hold: opts.hold?.hold,
            interruptIf: () => stop() || away() > leash || retarget(t),
        };
        const res =
            t.kind === "prehit"
                ? yield* attackAndConfirm(bot, () => (t.creep.IsAlive() ? t.creep : undefined), {
                      findFor: 0,
                      // The walk into range, the swing, and the attack cooldown left: past that the attack did not fire.
                      confirmFor: t.walk + ownHitTime(bot, t.creep) + PREHIT_SLACK,
                      aggroConfirms: false,
                      hold: opts.hold?.hold,
                      deadline: opts.deadline,
                      interruptIf: () => stop() || away() > leash,
                  })
                : t.kind === "lasthit"
                  ? yield* lastHit(bot, o)
                  : yield* deny(bot, o);
        // An attack order outlives the one attack it was given for: the bot keeps swinging at the creep until it dies or
        // another order comes, and a last-hit wait in range gives none (prhchk5: a second, unplanned hit about one attack
        // cycle after every pre-hit). A pre-hit is one attack, so its order is cancelled once it has fired or failed.
        if (t.kind === "prehit") bot.Action_MoveToLocation(bot.GetLocation());
        if (res.reason === "interrupted" && (target !== undefined || dropped)) res.message = `${res.message ?? ""} sw=${target !== undefined ? 1 : 0}`;
        if (opts.onAttempt !== undefined) opts.onAttempt(t, res, contested);
        if (res.reason === "dead") return res;
    }
}
