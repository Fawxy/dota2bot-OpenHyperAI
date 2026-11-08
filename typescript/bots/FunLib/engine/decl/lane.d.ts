/** @noSelfInFile */
import { HoldOpts } from "./verbs";
import { LaneTarget } from "./lasthit";
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
/**
 * Posture verb for a laner: holds `spot()` (re-read every frame) and, while `lastHits()` allows, breaks off for
 * the creep `pick` chooses from laneTargets (walking in so it arrives as the creep becomes killable), swings with the
 * skill-scaled lastHit/deny verbs (a `prehit` pick with one plain attack), then walks back. Never ends ok by itself; ends on death, `deadline`,
 * `interruptIf`. Labels phases `walk` / `hold` / `lasthit` / `deny` / `prehit`.
 */
export declare function laneFarm(bot: TaskUnit, spot: (this: void) => Vec | undefined, opts?: LaneFarmOpts): TaskBody;
