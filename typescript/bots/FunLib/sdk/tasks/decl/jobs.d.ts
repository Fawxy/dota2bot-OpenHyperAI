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
/** One neutral camp as the host knows it (e.g. a `GetNeutralSpawners()` box plus the host's camp data). */
export interface Camp {
    /** Where the bot waits to hit the camp. */
    stand: Vec;
    /** Spawn box; neutrals within it (plus `margin`) are the camp. */
    box?: Box;
    /** Spawner origin, walked towards when nothing is seen from the stand point. */
    origin?: Vec;
    /**
     * A closer stand point, taken `approachLead` s before the aggro when nothing
     * is in sight from `stand` (trees, night vision), so the camp is seen in time to hit it on its second.
     */
    approach?: Vec;
    /** Box margin: idle neutrals stand just outside the box. Default 300. */
    margin?: number;
    /** `GetNearbyNeutralCreeps` radius. Default 700. */
    search?: number;
    /** Host override of the neutral to hit. */
    pick?: (this: void) => TaskAttacker | undefined;
    /** Extra proof the aggro landed (e.g. a neutral targets the bot), passed to `attackAndConfirm`. */
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
    /** The neutral the order went to (hosts time a ranged hit's flight from it). */
    target?: TaskAttacker;
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
    /** Seconds before the aggro the bot moves to `camp.approach` when it sees nothing. Default 3. */
    approachLead?: number;
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
    /** When the hit should land (the camp's stack second, without jitter: the verb adds the skill error). */
    aggroAt: number;
    /** Walked after the hit, out of the box. */
    exitPath: Vec[];
    /** Absolute time the walk-off ends (just after the next :00 spawn check). */
    exitUntil: number;
}
/**
 * Camp stack (the SDK's original stack example as a verb): travel, wait at the stand point, a confirmed hit landing on
 * the aggro second (+ skill error), walk off along `exitPath`, stay out until `exitUntil`. Labels `travel`, `wait`,
 * `aggro`, `exit`; urgent until the hit lands.
 */
export declare function stack(bot: TaskUnit, p: StackPlan, h?: JobHooks): TaskBody;
export interface PullPlan extends AggroOpts {
    /** The camp whose hit is graded (a double's small camp). */
    camp: Camp;
    /** When its hit should land (the camp's full or half pull second, e.g. :15/:45 or :17/:47). */
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
    /** And until this time (e.g. a little after the wave arrives). */
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
export interface ClearPlan {
    /** The camp's centre (its box centre); neutrals within `radius` of it are the camp. */
    at: Vec;
    /** Neutrals chase out of the box: this far from `at` they still count. Default 700. */
    radius?: number;
    /** Within this of `at` the bot is at the camp. Default 300. */
    arrive?: number;
    /** `GetNearbyNeutralCreeps` radius. Default 1600. */
    search?: number;
    /** Absolute time the camp must be left by: past it the verb fails `timeout` "late". */
    deadline?: number;
    /** Seconds at the camp seeing nothing before it counts as empty. Default 0.5. */
    emptyAfter?: number;
    /** Seconds between repeated attack orders on the same target (a dropped order is re-given). Default 1. */
    reorder?: number;
    /** Host override of the next target among the camp's neutrals (default: keep the current one, else lowest HP). */
    pick?: (this: void, neutrals: TaskAttacker[]) => TaskAttacker | undefined;
    /** Called once, the first frame a neutral is within attack range + 100 (hosts time the clear from here). */
    onEngage?: (this: void, t: number) => void;
}
/**
 * Clears a neutral camp: walks to `at`, attacks its neutrals (the current target is kept while it lives, else the
 * lowest HP one), one order per target (re-given every `reorder` s), and after each kill waits one reaction delay
 * (`Skill.react`, skill-scaled) before the next order. Ends ok with message "cleared" once a camp it fought is
 * empty, or "empty" when nothing was there; `timeout` "late" past `deadline`. Labels `go`, then `farm` from the first frame a neutral is in attack range (+100).
 */
export declare function clearCamp(bot: TaskUnit, p: ClearPlan, h?: JobHooks): TaskBody;
export interface GankPlan {
    /** The hero to kill, re-read every frame (the host's perception decides what the bot knows). */
    target: (this: void) => TaskAttacker | undefined;
    /** Approach waypoints chosen by the host (through fog and trees, not down the lane); then the chase starts. */
    path: Vec[];
    /** Within this of the target the bot engages (attacks). Default 700. */
    engageRange?: number;
    /** Called once when the ETA to the target falls to `lead` s (humans ping "coming" ~3-5 s before arriving). */
    telegraph?: {
        lead: number;
        fn: (this: void, eta: number) => void;
    };
    /** Host check every frame; a returned string ends the gank `interrupted` with it (target under its tower, ...). */
    commit?: (this: void) => string | undefined;
    /** Seconds the target may be out of sight before it counts as escaped. Default 2. */
    lostGrace?: number;
    /** Seconds of fighting after engaging before giving up. Default 8. */
    engageFor?: number;
    /** Absolute time to have engaged by; fails `timeout` "late". */
    deadline?: number;
    /** Seconds between repeated attack orders. Default 1. */
    reorder?: number;
    onEngage?: (this: void, t: number) => void;
}
/**
 * A gank: walk the host's approach path, then chase the target into `engageRange` and attack it (one reaction delay
 * after reaching range, `Skill.react`), re-ordering every `reorder` s. Ends ok "kill" when the target dies; fails
 * `interrupted` "escaped" when it stays out of sight `lostGrace` s, `timeout` "no-kill" after `engageFor` s of
 * fighting, `timeout` "late" if not engaged by `deadline`, or with the host's `commit` message. Labels `travel`,
 * `engage`; urgent while engaged.
 */
export declare function gank(bot: TaskUnit, p: GankPlan, h?: JobHooks): TaskBody;
