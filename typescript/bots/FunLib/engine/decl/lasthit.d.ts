/** @noSelfInFile */
import { TaskBody, TaskCreep, TaskUnit } from "./types";
/**
 * Damage (after armour) the creep takes from others within `horizon` seconds: attack projectiles in flight
 * plus every attacker of either team winding up an attack on it. Attacks not yet started are not counted;
 * the prediction runs every frame, so they enter it once their wind-up begins.
 */
export declare function incomingDamage(bot: TaskUnit, creep: TaskCreep, horizon: number): number;
/**
 * Damage per second (after armour) of the attackers targeting the creep: `dps` all of them, `between` only those
 * not winding up an attack now (their next hit lands at an unknown time within one attack cycle, so it is
 * extrapolated; an attacker in its wind-up is credited with that hit by `incomingDamage` and its next one comes a
 * cycle later, beyond any horizon the verbs use).
 */
export declare function incomingDps(bot: TaskUnit, creep: TaskCreep): {
    dps: number;
    between: number;
};
/** One hit the forecast expects: seconds from now until it lands, damage after armour, and the attacker's kind. */
export interface ForecastHit {
    t: number;
    damage: number;
    by: "tower" | "creep" | "hero" | "self";
}
export interface HpForecast {
    /** HP and regen now. */
    hp: number;
    regen: number;
    horizon: number;
    /**
     * Hits at known times, sorted by `t`: attack projectiles in flight (the bot's own included), wind-ups seen, and for towers
     * and lane creeps the repeats of their latest known hit every attack cycle while they keep attacking it.
     */
    hits: ForecastHit[];
    /**
     * DPS after armour of the attackers on the creep with no hit in flight or wind-up (their next hit time is unknown),
     * spread evenly from SEEN_AHEAD on, as `believe` extrapolates them.
     */
    unphased: number;
    /** A tower among those: its hits are the forecast's largest, so with one unphased the hit times are not known. */
    unphasedTower: boolean;
}
/**
 * The creep's HP over the next `horizon` seconds from the hits the attacker index already sees: projectiles in flight
 * (arrival = distance / projectile speed), wind-ups (`windupLanding`), and for a tower or lane creep, its latest known hit
 * repeated every `GetSecondsPerAttack` while it attacks the creep now (UNVERIFIED in-game that it stays on it: a tower re-targets
 * on hero aggro or when the creep leaves its range, and a lane creep on aggro, which the repeats do not foresee). Heroes are not repeated: their next attacks are choices, not a cycle. Repeats assume the distance, and so the
 * flight time, stays as now. A fact for a caller that plans more than the one swing `lastHit` makes (the pre-hit under a
 * tower); `forecastHp` reads it.
 */
export declare function hpForecast(bot: TaskUnit, creep: TaskCreep, horizon: number): HpForecast;
/** The forecast's HP `t` seconds from now (may go below 0: the creep is dead by then). */
export declare function forecastHp(f: HpForecast, t: number): number;
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
    /** `prehit`: never offered by laneTargets; a caller's pick that `laneFarm` carries out as one attack (see LaneFarmOpts.pick). */
    kind: "lasthit" | "deny" | "prehit";
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
