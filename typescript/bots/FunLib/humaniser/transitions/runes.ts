/**
 * Lane safety and laning-phase transitions (task 12): rune rules.
 * The single source of rune spawn times for rotations and mid rune logic.
 */
import { Rune, Vector } from "bots/ts_libs/dota";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;

export type RuneKind = "power" | "water" | "bounty" | "wisdom";

// Checked against the Valve datafeed (patchnoteslist and patchnotes for 7.41 through 7.41f, latest 7.41f, 15/09/2026):
// no spawn-timing changes since 7.41, so these are the 7.41f rules.
export const RUNE_RULES: Record<RuneKind, { first: number; every: number; last?: number }> = {
    power: { first: 360, every: 120 },
    water: { first: 120, every: 120, last: 240 },
    bounty: { first: 0, every: 180 },
    wisdom: { first: 420, every: 420 },
};

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
