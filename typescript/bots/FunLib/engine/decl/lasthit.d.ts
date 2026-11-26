/** @noSelfInFile */
import { TaskAttacker, TaskBody, TaskCreep, TaskUnit } from "./types";
/**
 * Damage (after armour) the creep takes from others within `horizon` seconds (cut to FORECAST_MAX): attack projectiles in
 * flight, every attacker of either team winding up an attack on it, and (since slice pre-hit, 05/11/2026) the repeats of a
 * tower's or lane creep's such hit one attack cycle apart within the horizon, its phase being known. Attacks of an attacker
 * whose phase is unknown are not counted; the prediction runs every frame, so they enter it once their wind-up begins or
 * their projectile flies.
 */
export declare function incomingDamage(bot: TaskUnit, creep: TaskCreep, horizon: number): number;
/**
 * Damage per second (after armour) of the attackers targeting the creep: `dps` all of them, `between` only those whose
 * phase is unknown (no wind-up now and no attack projectile in flight: their next hit lands at an unknown time within one
 * attack cycle, so it is extrapolated; one winding up or with a projectile in flight is credited with that hit and its
 * repeats by `incomingDamage`; since slice pre-hit, 05/11/2026, before which only a wind-up counted as known).
 */
export declare function incomingDps(bot: TaskUnit, creep: TaskCreep): {
    dps: number;
    between: number;
};
/**
 * One hit the forecast expects: seconds from now until it lands, damage after armour, the attacker's kind and the attacker,
 * and `commit`, seconds until the attack is committed (its attack point, after which it can no longer be cancelled): 0 for
 * a projectile in flight, the wind-up left for one winding up, and for a tower's or lane creep's repeat its landing less
 * its flight.
 */
export interface ForecastHit {
    t: number;
    damage: number;
    by: "tower" | "creep" | "hero" | "self";
    attacker: TaskAttacker;
    commit: number;
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
    /**
     * The same attackers one by one: damage after armour, attack cycle, `first` the earliest their next hit can land (a wind-up
     * from now, plus flight for a ranged one) and `last` the latest (one cycle from now, plus flight: no wind-up is seen, so the
     * attacker is in its backswing or cooldown and its last hit landed by now). The bracket assumes the attacker is in range and
     * its wind-up readable; one still walking to the creep can land later.
     */
    unphasedHits: {
        damage: number;
        period: number;
        first: number;
        last: number;
    }[];
}
/**
 * How `forecastHp` places the hits of the attackers whose phase is unknown: `spread` evenly from SEEN_AHEAD on (as the last-hit
 * belief), `early` each one's next hit at its `first` and every cycle after, `late` at its `last` and every cycle after.
 */
export type ForecastSchedule = "spread" | "early" | "late";
/**
 * The creep's HP over the next `horizon` seconds from the hits the attacker index already sees: projectiles in flight
 * (arrival = distance / projectile speed), wind-ups (`windupLanding`), and for a tower or lane creep, its latest known hit
 * repeated every `GetSecondsPerAttack` while it attacks the creep now (UNVERIFIED in-game that it stays on it: a tower re-targets
 * on hero aggro or when the creep leaves its range, and a lane creep on aggro, which the repeats do not foresee). Heroes are not repeated: their next attacks are choices, not a cycle. Repeats assume the distance, and so the
 * flight time, stays as now. A fact for a caller that plans more than the one swing `lastHit` makes (the pre-hit under a
 * tower); `forecastHp` reads it.
 */
export declare function hpForecast(bot: TaskUnit, creep: TaskCreep, horizon: number): HpForecast;
/** The forecast's HP `t` seconds from now (may go below 0: the creep is dead by then), the unknown-phase hits placed by `schedule`. */
export declare function forecastHp(f: HpForecast, t: number, schedule?: ForecastSchedule): number;
/**
 * The centre-to-centre distance within which `attacker` begins an attack on `target` without moving: its attack range plus
 * both hull radii (`GetBoundingRadius`, 0 for a handle without one). `range` is the attacker's attack range when the caller
 * has already read it. Source: banked games (commit 628bfdd0, docs/contracts/attackReach.md), 21,212 hero attacks on lane creeps begun
 * within 0.12 s of the creep's death in 1,394 games: they began up to range + 40 from a melee creep (hull 16) and range + 32
 * from a ranged creep (hull 8) for heroes of hull 24, and 28 of 21,212 began farther.
 */
export declare function attackReach(attacker: TaskUnit, target: TaskCreep, range?: number): number;
/** Seconds until the bot can start its next swing (0 without the adapter's `attackClock`). */
export declare function cooldownLeft(bot: TaskUnit): number;
/** Seconds to turn to face the creep (0 without GetFacing). */
export declare function turnTime(bot: TaskUnit, creep: TaskCreep): number;
/**
 * Seconds from an attack order now until the bot's hit lands: wind-up (attack point / attack speed), the
 * cooldown left from its last attack (only with the adapter's `attackClock`), and projectile travel for a
 * ranged bot, and the turn to face the creep (`turnTime`).
 */
export declare function ownHitTime(bot: TaskUnit, creep: TaskCreep): number;
/**
 * Clears this module's state that outlives a frame: the wind-up records, the per-bot skill rolls and the nearby index. For a
 * test's setup, or a host starting a new game; play needs no call (the wind-up record restarts on its own guards, the
 * index on a new frame).
 */
export declare function resetLastHitState(): void;
export interface LaneTarget {
    creep: TaskCreep;
    /** `prehit`: never offered by laneTargets; a caller's pick that `laneFarm` carries out as one attack (see LaneFarmOpts.pick). */
    kind: "lasthit" | "deny" | "prehit";
    /** Seconds until a swing ordered then would be due (0: due now), or the walk into attack reach (`attackReach`) if longer. */
    eta: number;
    /** Seconds until a swing ordered then would be due (0: due now). */
    due: number;
    /** Seconds to walk into attack reach (`attackReach`) at the current speed (0: in reach). */
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
 * The lane creeps that become killable within `within` seconds of the bot reaching attack reach (`attackReach`), enemy creeps
 * first, then allied ones (a caller's tie-break may rely on that order; within each side, the host's creep order): enemy creeps to last-hit (the adapter's `lastHitFilter` applies) and allied creeps to deny. Facts only, with
 * exact prediction and no skill error (the verbs apply that when they swing): eta is when the creep becomes
 * killable by a swing ordered then (from incoming DPS), or the walk into attack reach if longer. Which one to go for is
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
    /** Hold tag passed to the adapter's `hold` while standing in attack reach (`attackReach`) waiting. */
    hold?: string;
    interruptIf?: (this: void) => boolean;
    /**
     * Called once on each change of the verb's phase, with the time it was entered: `walk` (outside attack reach, moving in),
     * `wait` (in reach, no swing ordered yet), `swing` (the attack is ordered, not yet confirmed). Called on the frame of the change,
     * after the order of a `swing`. A verb that never reaches a phase never reports it.
     */
    onPhase?: (this: void, phase: LastHitPhase, t: number) => void;
}
export type LastHitPhase = "walk" | "wait" | "swing";
/**
 * Last-hits an enemy lane creep (`opts.target`, or the best one within `searchRadius` that the adapter's
 * `lastHitFilter` allows). Waits in attack reach (`attackReach`) until the bot believes its hit, ordered now, lands after
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
