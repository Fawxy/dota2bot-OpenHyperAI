/** @noSelfInFile */
import { HoldOpts } from "./verbs";
import { LaneTarget } from "./lasthit";
import { Result, TaskBody, TaskUnit, Vec } from "./types";
export interface LaneFarmOpts {
    /** holdAt options for standing at the spot (its interruptIf is the verb's own). */
    hold?: HoldOpts;
    /** Whether to go for last hits and denies now; read every frame. Default: always. */
    lastHits?: (this: void) => boolean;
    /** nextLastHit's `within`. Default 1. */
    within?: number;
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
/**
 * Posture verb for a laner: holds `spot()` (re-read every frame) and, while `lastHits()` allows, breaks off for
 * the creep nextLastHit offers (walking in so it arrives as the creep becomes killable), swings with the
 * skill-scaled lastHit/deny verbs, then walks back. Never ends ok by itself; ends on death, `deadline`,
 * `interruptIf`. Labels phases `walk` / `hold` / `lasthit` / `deny`.
 */
export declare function laneFarm(bot: TaskUnit, spot: (this: void) => Vec | undefined, opts?: LaneFarmOpts): TaskBody;
