/**
 * Camp data (task 07). Seed data from public guides (Liquipedia Pulling, Dotafire, bo3.gg); regenerate replay entries with tools/replay-mining (task 3). Spawn boxes are never stored here.
 */
import { Vector } from "bots/ts_libs/dota";
import { CampType, LaneKind } from "bots/FunLib/humaniser/camps";

export interface CampDataEntry {
    key: string;
    team: number;
    type: CampType;
    laneKind?: LaneKind;
    near?: Vector;
    stackAggroSec?: number;
    stackExitPath?: Vector[];
    /** Overrides Camps.PullCampMaxTowerDist (distance from the lane's T1, or T2 when T1 is dead) for this seed. */
    maxTowerDist?: number;
    pullAggroSec?: number[];
    halfAggroSec?: number[];
    pullPath?: Vector[];
    meetPoint?: Vector;
    halfMeetPoint?: Vector;
    source: "seed" | "replay" | "measured";
    unverified?: boolean;
    verifiedAt?: string;
}

export const DEFAULT_STACK_SEC: Record<CampType, number> = { small: 54.5, medium: 54.0, large: 53.5, ancient: 53.0 };

export const CAMP_DATA: CampDataEntry[] = [
    { key: "radiant_safe_small", team: 2, type: "small", laneKind: "safe", pullAggroSec: [15, 45], halfAggroSec: [17, 47], source: "seed" },
    { key: "dire_safe_small", team: 3, type: "small", laneKind: "safe", pullAggroSec: [15, 45], halfAggroSec: [17, 47], source: "seed" },
    { key: "radiant_safe_large", team: 2, type: "large", laneKind: "safe", pullAggroSec: [18, 48], halfAggroSec: [20, 50], source: "seed" },
    { key: "dire_safe_large", team: 3, type: "large", laneKind: "safe", pullAggroSec: [18, 48], halfAggroSec: [20, 50], source: "seed" },
    // 7.41 map: the off-lane hard camp sits outside the lane beside the off-lane T2, ~3100 (Radiant) / ~2700 (Dire) from T1.
    { key: "radiant_off_large", team: 2, type: "large", laneKind: "off", maxTowerDist: 3300, pullAggroSec: [18, 48], halfAggroSec: [20, 50], source: "seed", unverified: true },
    { key: "dire_off_large", team: 3, type: "large", laneKind: "off", maxTowerDist: 3300, pullAggroSec: [18, 48], halfAggroSec: [20, 50], source: "seed", unverified: true },
    // BEGIN GENERATED REPLAY ENTRIES
    // END GENERATED REPLAY ENTRIES
];
