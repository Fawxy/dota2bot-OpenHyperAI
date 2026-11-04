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
    /** Claim a spawner of the other team (the off-lane hard camp beside the enemy safe-lane T1); maxTowerDist stays measured from our tower. */
    enemySide?: boolean;
    pullAggroSec?: number[];
    halfAggroSec?: number[];
    pullPath?: Vector[];
    meetPoint?: Vector;
    halfMeetPoint?: Vector;
    /** Derived meet point: this far back along our wave's path from the lane point nearest the camp. */
    meetBack?: number;
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
    // 7.41 map: the off lane pulls the enemy's hard camp beside their safe-lane T1 (evil_1 / good_2, ~2550 / ~2200 from our
    // off-lane T1). Our own hard camp behind the off-lane T2 (good_13 / evil_7) is 12-20 s away (console.9055874680
    // gate=far) and stays a stack camp only. meetBack 600: the nearest lane point is due west (east for Dire) of the camp on
    // the lane's long stretch, where our wave walks towards the clash; 600 back adds about 120 to the neutrals' walk and
    // brings our wave there about 1.8 s sooner (user 04/11/2026, replay ptm1_A 4:21). Banked camp 18 pulls diverted 2 of 10
    // with the enemy wave's front already south of the camp, 7 of 20 north of it. `judgement`.
    { key: "radiant_off_large", team: 2, type: "large", laneKind: "off", enemySide: true, maxTowerDist: 2800, meetBack: 600, pullAggroSec: [18, 48], halfAggroSec: [20, 50], source: "seed", unverified: true },
    { key: "dire_off_large", team: 3, type: "large", laneKind: "off", enemySide: true, maxTowerDist: 2800, meetBack: 600, pullAggroSec: [18, 48], halfAggroSec: [20, 50], source: "seed", unverified: true },
    // BEGIN GENERATED REPLAY ENTRIES
    // END GENERATED REPLAY ENTRIES
];
