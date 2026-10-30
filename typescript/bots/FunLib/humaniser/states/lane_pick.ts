/**
 * Which lane creep a laner goes for next, from the engine's `laneTargets` facts. Moved from the engine's old
 * `nextLastHit` (slice 5a) unchanged: priority ranged last hit > ranged deny > melee last hit > melee deny, as eta
 * biases, so a melee creep due now still beats a ranged one due much later. Biases are `judgement`. A creep that will
 * be dead before the bot can walk into range and swing is skipped (slice 5).
 */
import type * as Lib from "bots/FunLib/engine/tasks";

/** Seconds of eta a ranged or siege creep is preferred by (more gold and XP). */
export const RANGED_BIAS = 0.4;
/** Seconds of eta a last hit is preferred over a deny by (a core never gives up its last hit to deny). */
export const LAST_HIT_BIAS = 0.3;
/**
 * Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
 * A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
 * were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
 */
export const ARRIVE_SLACK = 0.45;

export function Choose(this: void, targets: Lib.Verbs.LaneTarget[]): Lib.Verbs.LaneTarget | undefined {
    let best: Lib.Verbs.LaneTarget | undefined;
    let bestKey = Infinity;
    for (const t of targets) {
        if (t.walk > 0 && t.walk + ARRIVE_SLACK >= t.dies) continue;
        const key = t.eta - (t.ranged ? RANGED_BIAS : 0) - (t.kind === "lasthit" ? LAST_HIT_BIAS : 0);
        if (key < bestKey) {
            bestKey = key;
            best = t;
        }
    }
    return best;
}
