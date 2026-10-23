/** @noSelfInFile */
import { TaskAttacker, TaskBody, TaskUnit, Vec } from "./types";
/** Task controls a job reports its phases through; `ctx` binds its own. */
export interface JobHooks {
    label?: (this: void, label: string) => void;
    urgent?: (this: void, on: boolean) => void;
}
export interface Box {
    min: Vec;
    max: Vec;
}
/** One neutral camp as the host knows it (OHA: `GetNeutralSpawners()` box plus camp data). */
export interface Camp {
    /** Where the bot waits to hit the camp. */
    stand: Vec;
    /** Spawn box; neutrals within it (plus `margin`) are the camp. */
    box?: Box;
    /** Spawner origin, walked towards when nothing is seen from the stand point. */
    origin?: Vec;
    /** Box margin: idle neutrals stand just outside the box. Default 300 (OHA `Radii.BoxMargin`). */
    margin?: number;
    /** `GetNearbyNeutralCreeps` radius. Default 700. */
    search?: number;
    /** Host override of the neutral to hit. */
    pick?: (this: void) => TaskAttacker | undefined;
    /** Extra proof the aggro landed (OHA: a neutral targets the bot), passed to `attackAndConfirm`. */
    confirmed?: (this: void) => boolean;
}
export interface AggroInfo {
    camp: Camp;
    /** The plan's aggro second (when the hit should land). */
    planned: number;
    /** Skill error applied to it (s, positive late). */
    error: number;
    orderedAt: number;
    confirmedAt: number;
}
export interface AggroOpts {
    /** Stand-point tolerance. Default 100. */
    arrive?: number;
    /** Seconds after the (erred) aggro second the bot may still reach the stand point. Default 2. */
    startLate?: number;
    /** Seconds after it to keep looking for a neutral. Default 1. */
    noCampAfter?: number;
    /** Seconds from the order to see the hit land. Default 2. */
    confirmFor?: number;
    /** Seconds added to every aggro second of the job; default one `Skill.timingError(bot)` draw per job. */
    timingError?: number;
    /** Seconds before the hit the order goes out; default estimated per target (`aggroLead`). */
    aggroLead?: number;
    onAggro?: (this: void, info: AggroInfo) => void;
}
/**
 * The camp's neutral nearest the bot: alive, visible, inside the box grown by `margin` (or, without a box,
 * within `margin` of the origin, else anything in `search`).
 */
export declare function campNeutral(bot: TaskUnit, camp: Camp): TaskAttacker | undefined;
/** Seconds from an attack order on `target` to the hit landing: walk into range, wind-up, projectile flight. */
export declare function aggroLead(bot: TaskUnit, target: TaskAttacker): number;
export interface StackPlan extends AggroOpts {
    camp: Camp;
    /** When the hit should land (OHA: `baseAggro`, the camp's stack second; no host jitter, the SDK adds it). */
    aggroAt: number;
    /** Walked after the hit, out of the box. */
    exitPath: Vec[];
    /** Absolute time the walk-off ends (OHA: next :00 + `StackExitUntil`). */
    exitUntil: number;
}
/**
 * Camp stack (v0.2 port of OHA's O2 `stack_task.ts`): travel, wait at the stand point, a confirmed hit landing on
 * the aggro second (+ skill error), walk off along `exitPath`, stay out until `exitUntil`. Labels `travel`, `wait`,
 * `aggro`, `exit`; urgent until the hit lands.
 */
export declare function stack(bot: TaskUnit, p: StackPlan, h?: JobHooks): TaskBody;
export interface PullPlan extends AggroOpts {
    /** The camp whose hit is graded (a double's small camp). */
    camp: Camp;
    /** When its hit should land (OHA: the camp's full or half pull second, e.g. :15/:45 or :17/:47). */
    aggroAt: number;
    /** Walked after the hit, to the meet point with the wave (last point). */
    lead: Vec[];
    /** Double pull: this camp is hit first at its own second, then `camp`. */
    first?: {
        camp: Camp;
        aggroAt: number;
    };
    /** Watch at the meet point at least this long. Default 8. */
    watchSec?: number;
    /** And until this time (OHA: wave arrival + `WatchAfterWave`). */
    watchUntil?: number;
    /** Absolute time the lead must be done by. Default aggroAt + 15. */
    leadDeadline?: number;
}
/**
 * Pull (full, half, double: the kind is in the data). Aggro the camp so the hit lands on its second (+ one skill
 * error for the whole job), lead it along `lead` to the meet point, then watch there. Labels `travel`, `wait`,
 * `aggro` (twice for a double), `lead`, `watch`; urgent until the lead is done. Grading the divert is the host's.
 */
export declare function pull(bot: TaskUnit, p: PullPlan, h?: JobHooks): TaskBody;
export interface RunePlan {
    /** Where to wait for the spawn (the rune spot, or beside it). */
    at: Vec;
    /** Game time the rune spawns or the shrine activates. */
    spawnAt: number;
    /** Rune location constant; picked up with `pickUpRune`. Omit for a shrine (`channel`). */
    rune?: number;
    /** Rune position override for `pickUpRune`. */
    runeAt?: Vec;
    /** Seconds early to arrive at skill 1. Default 4. */
    early?: number;
    /** Arrival tolerance at `at`. Default 150. */
    tolerance?: number;
    /** Not at `at` by spawnAt + lateBy: fails `timeout` "late". Default 5. */
    lateBy?: number;
    /** Seconds after the spawn to get the rune or finish the channel. Default 10. */
    pickupFor?: number;
    /** Shrine: stand within `radius` of `at` this many seconds after it activates (wisdom shrine: 3). */
    channel?: number;
    /** Shrine radius. Default 300. */
    radius?: number;
    /** Host proof of the gain (gold, modifier, XP). Rune: decides ok vs taken_by_other; shrine: ok vs missed. */
    confirmed?: (this: void) => boolean;
    /** Seconds added to the arrival; default one `Skill.timingError(bot)` draw per bot and spawn. */
    timingError?: number;
}
/** When the bot means to be at `at`: `early * lerp(0.25, 1, skill)` s before the spawn, plus its timing error. */
export declare function runeArriveBy(bot: TaskUnit, p: RunePlan): number;
/** When to start `runeRun` to arrive by `runeArriveBy`, from the straight-line walk at the current speed. */
export declare function runeLeaveAt(bot: TaskUnit, p: RunePlan): number;
/**
 * Rune or shrine run: walk to `at`, wait for the spawn, then one reaction delay later pick the rune up (retrying
 * while it is not yet reported, for 2 s) or, for a shrine, stand within `radius` for `channel` s (pushed out, the
 * count restarts). Start it at `runeLeaveAt` to arrive skill-scaled early. Labels `travel`, `wait`, then `pickup`
 * or `channel`.
 */
export declare function runeRun(bot: TaskUnit, p: RunePlan, h?: JobHooks): TaskBody;
