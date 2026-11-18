/**
 * Plan trade-from-the-stand step 3 probes (master docs/proposals/2026-11-18-trade-from-the-stand.md, "Revision after D and
 * D2"): the decisions only, so they are tested without a game. states/laning gathers the facts and acts.
 * - f, `Ours.LaneHit`: the laning body hits an enemy hero in its attack range when nothing of the lane is due before the hit's
 *   attack cycle ends: the lowest pick, after a last hit, a pre-hit, a deny and the idle swing. No episode: one attack, then the
 *   next scan chooses again.
 * - g, `Ours.LaneYield`: with nothing of the lane due, laning bids YIELD_DESIRE, under Valve's attack mode as OHA's laning sits
 *   when it loses to it, so that mode (where it runs for the hero: `Ours.CoreTrade` off) can take the hero.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";

/** The trade's creep-aggro answer for this frame (states/core_trade AggroPlan). */
export type Aggro = "attack" | "prime" | "step_out";

export interface HitFacts {
    /** A trade, kill, fight or join episode is open (core_trade Running): the trade's attack mode has the hero. */
    trade: boolean;
    /** Our retreat's episode runs. */
    leaving: boolean;
    /** The pick chose a pre-hit (it is due now). */
    pre: boolean;
    /** A melee walk-in to a last hit is running or was just chosen (states/contest). */
    walkIn: boolean;
    /** A last hit or deny this laner may take is due before the hit's attack cycle ends (Due). */
    due: boolean;
    /** The pick chose an idle swing (states/idle_swing): it outranks the hero hit. */
    idle: boolean;
    /** We stand inside an enemy tower's reach: a hit on a hero there draws the tower. */
    tower: boolean;
    aggro: Aggro;
    /** Ours.LaneHitAggro (plan step 3 f round 2): the aggro plan is not asked; only creeps actually hitting us hold the hit. */
    aggroFree: boolean;
    /** Enemy lane creeps attacking us now, and the trade's `creeps` bar (core_trade MAX_CREEPS_ON_ME). */
    creepsOnMe: number;
    creepBar: number;
}

export type HitWhy = "trade" | "retreat" | "pre" | "walk_in" | "due" | "idle" | "tower" | "aggro" | "creeps" | "hit";

/**
 * Whether to hit the hero, and if not the first reason, in the order the lane's own picks rank above it: the running episodes,
 * the creeps (pre-hit, walk-in, a due last hit or deny, the idle swing), then the costs of the hit itself (their tower, creep
 * aggro). `prime` and `attack` both draw no aggro (AggroPlan's own reading: a fresh order with no enemy creep within its clear
 * radius, or one inside the cooldown of an earlier order); `step_out` would, so the hero is not hit.
 */
export function Answer(this: void, f: HitFacts): HitWhy {
    if (f.trade) return "trade";
    if (f.leaving) return "retreat";
    if (f.pre) return "pre";
    if (f.walkIn) return "walk_in";
    if (f.due) return "due";
    if (f.idle) return "idle";
    if (f.tower) return "tower";
    if (f.aggroFree) return f.creepsOnMe >= f.creepBar ? "creeps" : "hit";
    if (f.aggro === "step_out") return "aggro";
    return "hit";
}

/**
 * Seconds from an attack order on the hero now until our next swing can start: the cooldown left and the turn to it (the
 * last-hit engine's own `cooldownLeft`, `turnTime`) and one full attack cycle, since the hit restarts the attack clock.
 */
export function Cycle(this: void, cooldownLeft: number, turn: number, secondsPerAttack: number): number {
    return cooldownLeft + turn + secondsPerAttack;
}

/**
 * Of laneTargets' facts (asked with `within` = the cycle), the earliest creep this laner may take (`mine`, the reach rule) whose
 * swing is due before the cycle ends and the walk to it is done: hitting the hero now would make that swing late. Undefined:
 * none, the hero hit costs no last hit or deny on offer.
 */
export function Due(
    this: void,
    targets: Lib.Verbs.LaneTarget[],
    mine: ((this: void, t: Lib.Verbs.LaneTarget) => boolean) | undefined,
    cycle: number,
): Lib.Verbs.LaneTarget | undefined {
    let first: Lib.Verbs.LaneTarget | undefined;
    for (const t of targets) {
        if (mine !== undefined && !mine(t)) continue;
        if (!LanePick.Reachable(t)) continue;
        if (t.due >= cycle + t.walk) continue;
        if (first === undefined || t.due < first.due) first = t;
    }
    return first;
}

/**
 * g's level. OHA's laning bid a mean 0.49 in the seconds Valve's attack mode won (step D2), and OHA's attack-mode entries came at
 * 0.54 or more in nine of ten (h2hohafight1, 1,213 entries to 10:00: 94% above 0.52, 86% above 0.55). 0.52 stays over the rig's
 * idle hold (drill RIG_IDLE_DESIRE 0.5) and the Valve built-in mode the arbiter's LaneDesire was set over (0.475), so a yield
 * leaves the hero to the attack mode and to nothing else. `judgement`.
 */
export const YIELD_DESIRE = 0.52;

/**
 * Laning's last-hit bid (mode_laning_generic's 0.9, OWNERSHIP H2). Under the yield it follows our own read both ways: a creep the
 * pick would take bids it, so the hero comes back from whatever mode took it (lhrig1_g_s30: on OHA's read alone, creeps within 800,
 * Sniper never left the rig's idle hold after a yield and took no last hit in 17 reps).
 */
export const LAST_HIT_DESIRE = 0.9;

export interface YieldFacts {
    /** Our wave hold runs (states/wave_hold's hold point is set). */
    hold: boolean;
    /** A melee walk-in to a last hit runs. */
    walkIn: boolean;
    /** The pick would take a creep now (lane_pick Choose on laneTargets' facts within the body's horizon), or a pre-hit. */
    offered: boolean;
}

export type YieldWhy = "hold" | "walk_in" | "offered" | "yield";

/** Whether laning yields (`yield`), or what the lane has due. */
export function YieldAnswer(this: void, f: YieldFacts): YieldWhy {
    if (f.hold) return "hold";
    if (f.walkIn) return "walk_in";
    if (f.offered) return "offered";
    return "yield";
}
