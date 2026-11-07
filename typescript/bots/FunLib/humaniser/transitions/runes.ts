/**
 * Lane safety and laning-phase transitions (task 12): rune rules.
 * The single source of rune spawn times for rotations and mid rune logic.
 */
import { Rune, Vector } from "bots/ts_libs/dota";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;

import { RUNE_RULES, RuneKind } from "bots/FunLib/humaniser/game_rules";

export { RUNE_RULES, RuneKind };

/** The first spawn time at or after `now`, or math.huge once the rune has stopped spawning. */
export function NextSpawn(kind: RuneKind, now: number): number {
    const rule = RUNE_RULES[kind];
    let t = rule.first;
    if (now > t) t += Math.ceil((now - t) / rule.every) * rule.every;
    if (rule.last !== undefined && t > rule.last) return math.huge;
    return t;
}

export function PowerSpots(): Vector[] {
    return [GetRuneSpawnLocation(Rune.Power1), GetRuneSpawnLocation(Rune.Power2)];
}

/** The side is named by the spot's world position (y > 0 is top), not by the RUNE_POWERUP index. */
export function NearestPowerSpot(loc: Vector): LuaMultiReturn<[Vector, "top" | "bot"]> {
    const spots = PowerSpots();
    let best = spots[0];
    let bestD = math.huge;
    for (const spot of spots) {
        const d = (spot.x - loc.x) ** 2 + (spot.y - loc.y) ** 2;
        if (d < bestD) {
            bestD = d;
            best = spot;
        }
    }
    return $multi(best, best.y > 0 ? "top" : "bot");
}
