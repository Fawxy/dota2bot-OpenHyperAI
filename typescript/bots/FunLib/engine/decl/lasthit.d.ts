/** @noSelfInFile */
import { TaskBody, TaskCreep, TaskUnit } from "./types";
/**
 * Damage (after armour) the creep takes from others within `horizon` seconds: attack projectiles in flight
 * plus every attacker of either team winding up an attack on it. Attacks not yet started are not counted;
 * the prediction runs every frame, so they enter it once their wind-up begins.
 */
export declare function incomingDamage(bot: TaskUnit, creep: TaskCreep, horizon: number): number;
/** Damage per second (after armour) of every visible attacker of either team currently targeting the creep. */
export declare function incomingDps(bot: TaskUnit, creep: TaskCreep): number;
/**
 * Seconds from an attack order now until the bot's hit lands: wind-up (attack point / attack speed), the
 * cooldown left from its last attack (only with the adapter's `attackClock`), and projectile travel for a
 * ranged bot. The bot is assumed facing the creep: turn time is not modelled.
 */
/** Seconds until the bot can start its next swing (0 without the adapter's `attackClock`). */
export declare function cooldownLeft(bot: TaskUnit): number;
/** Seconds to turn to face the creep (0 without GetFacing). */
export declare function turnTime(bot: TaskUnit, creep: TaskCreep): number;
export declare function ownHitTime(bot: TaskUnit, creep: TaskCreep): number;
export interface LaneTarget {
    creep: TaskCreep;
    kind: "lasthit" | "deny";
    /** Seconds until a swing ordered then would be due (0: due now), or the walk into attack range if longer. */
    eta: number;
    /** Seconds until a swing ordered then would be due (0: due now). */
    due: number;
    /** Seconds to walk into attack range at the current speed (0: in range). */
    walk: number;
    /** Seconds until the creep dies to the others' damage at their current DPS (exact, as `due`). */
    dies: number;
    /** A ranged or siege creep (more gold and XP than a melee one). */
    ranged: boolean;
}
export interface LaneTargetsOpts {
    /** Creeps farther than this are ignored. Default max(800, attack range + 400). */
    radius?: number;
    /**
     * Only creeps that become killable at most this many seconds after the bot could be in range are returned,
     * so a melee hero standing outside the creep rings sets off in time. Default 1.
     */
    within?: number;
    /** Consider allied creeps to deny. Default true. */
    deny?: boolean;
    /** Consider enemy creeps to last-hit. Default true. */
    lastHit?: boolean;
}
/**
 * The lane creeps that become killable within `within` seconds of the bot reaching attack range, enemy creeps
 * first, then allied ones (a caller's tie-break may rely on that order; within each side, the host's creep order): enemy creeps to last-hit (the adapter's `lastHitFilter` applies) and allied creeps to deny. Facts only, with
 * exact prediction and no skill error (the verbs apply that when they swing): eta is when the creep becomes
 * killable by a swing ordered then (from incoming DPS), or the walk into range if longer. Which one to go for is
 * the caller's choice.
 */
export declare function laneTargets(bot: TaskUnit, opts?: LaneTargetsOpts): LaneTarget[];
export interface LastHitOpts {
    /** Seconds to wait for the creep to become due before failing `timeout`. Default 1.5. */
    maxWait?: number;
    deadline?: number;
    target?: TaskCreep;
    /** Default attack range + 300. */
    searchRadius?: number;
    /** Hold tag passed to the adapter's `hold` while standing in range waiting. */
    hold?: string;
    interruptIf?: (this: void) => boolean;
}
/**
 * Last-hits an enemy lane creep (`opts.target`, or the best one within `searchRadius` that the adapter's
 * `lastHitFilter` allows). Waits in attack range until the bot believes its hit, ordered now, lands after
 * everyone else's incoming damage and kills: `creepHP + regen * t - incoming(t) <= ownDamage`, where t is the
 * own hit time (wind-up, cooldown, projectile travel) and incoming counts attack projectiles in flight and
 * wind-ups of creeps, heroes and towers targeting the creep. The belief carries a per-creep error from the
 * bot's skill (see docs/API.md): misses are early swings (`missed`) or late ones (`taken_by_other`/`denied`).
 * Ok once the bot's last-hit count rises.
 */
export declare function lastHit(bot: TaskUnit, opts?: LastHitOpts): TaskBody;
/**
 * Denies an allied lane creep: as `lastHit`, but only swings while the creep is below 50% HP (Dota refuses
 * the order above it), and confirms on the bot's deny count. `lastHitFilter` does not apply; whether a core
 * should deny rather than last-hit is the body's decision. Lost to an enemy last hit: `taken_by_other`.
 */
export declare function deny(bot: TaskUnit, opts?: LastHitOpts): TaskBody;
