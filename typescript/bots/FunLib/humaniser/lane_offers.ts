/**
 * What a laner could take right now, whoever plays its laning: the snapshot's `ol`/`od` (slice lane-activity, both arms). Reads
 * the engine's `laneTargets` facts through the reach rule below. Reads facts only (no skill roll).
 */
import type * as Lib from "bots/FunLib/engine/tasks";

/**
 * Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
 * A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
 * were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
 */
export const ARRIVE_SLACK = 0.45;
/**
 * The longest walk into range counted as on offer. Check run llhchk2 (03/11/2026, 5 normal games, skill 1): attempts
 * picked in range landed 0.61 of the time, under a second's walk 0.53, one to two seconds 0.34, beyond 0.19. `judgement`.
 */
export const MAX_WALK = 1.0;

/** The reach rule: a creep in range always; one to walk to only when the walk is short and it outlives the walk and a swing. */
export function Reachable(this: void, t: Lib.Verbs.LaneTarget): boolean {
    if (t.walk <= 0) return true;
    if (t.walk + ARRIVE_SLACK >= t.dies) return false;
    return t.walk <= MAX_WALK;
}

/** The engine's `laneTargets`, handed over by humaniser/tasks once the bundle is loaded; telemetry never loads the bundle itself. */
let offers: ((this: void, bot: Lib.TaskUnit) => Lib.Verbs.LaneTarget[]) | undefined;

export function SetOffers(fn: (this: void, bot: Lib.TaskUnit) => Lib.Verbs.LaneTarget[]): void {
    offers = fn;
}

/** Reachable last hits and reachable denies on offer now. Undefined while the bundle is not loaded. */
export function Options(bot: Lib.TaskUnit): LuaMultiReturn<[number | undefined, number | undefined]> {
    if (offers === undefined) return $multi(undefined, undefined);
    let lastHits = 0;
    let denies = 0;
    for (const t of offers(bot)) {
        if (!Reachable(t)) continue;
        if (t.kind === "lasthit") lastHits++;
        else denies++;
    }
    return $multi(lastHits, denies);
}
