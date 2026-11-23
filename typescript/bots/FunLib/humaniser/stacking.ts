/**
 * What the stack job reads of a camp: Valve's stack window, the second to land the hit, the neutrals in its box, and the
 * record of camps stacked (assumed from the hit's timing when the box was out of sight).
 */
import * as GameRules from "bots/FunLib/humaniser/game_rules";
import { Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Camps from "bots/FunLib/humaniser/camps";
import { DEFAULT_STACK_SEC } from "bots/FunLib/humaniser/camps_data";

interface StackRecord {
    minute: number;
    count: number;
}

let records: Record<number, StackRecord> = {};

export function ResetCache(): void {
    records = {};
}

function settings(): LaneConfig.LaneSettings {
    return LaneConfig.Settings();
}

function currentMinute(): number {
    return math.floor(DotaTime() / GameRules.NEUTRAL_EVERY);
}

/**
 * 7.41 stack windows (seconds to land the hit) from scripts/creep_pull_timings.txt in pak01_dir.vpk (read 22/10/2026,
 * what the `dota_hud_show_creep_spawn_camp_names` overlay shows), by the camp's spawner origin from maps/dota.vpk:
 * [x, y, stack_start, stack_end]. good_14, good_20, evil_11 and evil_20 are the 7.42 positions (19/11/2026, their windows unchanged). Camps 1,300+ apart, so WINDOW_MATCH cannot pick the wrong one.
 */
const WINDOWS: number[][] = [
    [-4824, 3915, 54, 56], // evil_1
    [-3911, 4829, 55, 57], // evil_2
    [1224, 4176, 55, 56], // evil_4
    [1064, 2580, 55, 56], // evil_5
    [-852, 4940, 54, 55], // evil_6
    [7928, -120, 55, 56], // evil_7
    [4352, 48, 53, 55], // evil_8
    [3392, -1408, 53, 55], // evil_9
    [-4229, 8140, 54, 56], // evil_11
    [2016, 7896, 55, 57], // evil_12
    [8430, 1263, 55, 56], // evil_13
    [336, 7696, 55, 56], // evil_14
    [-2596, 3850, 55, 56], // evil_15
    [-6408, 7816, 55, 56], // evil_20
    [3978, -5027, 55, 57], // good_1
    [4649, -3699, 52, 54], // good_2
    [186, -5197, 54, 55], // good_4
    [-1454, -3356, 55, 56], // good_5
    [-4013, 992, 53, 55], // good_7
    [-5015, -96, 52, 54], // good_8
    [-1983, -4815, 56, 57], // good_9
    [-720, -7696, 55, 57], // good_11
    [-2415, -8402, 53, 55], // good_12
    [-8313, -553, 55, 56], // good_13
    [4520, -8336, 55, 57], // good_14
    [1922, -3975, 56, 57], // good_15
    [-8023, -1838, 55, 56], // good_16
    [6712, -7632, 55, 56], // good_20
];
const WINDOW_MATCH = 300;

/** Valve's stack window for the camp, or undefined (another map, a moved camp, StackFromValve off). */
export function Window(campIdx: number): LuaMultiReturn<[number | undefined, number | undefined]> {
    const spawner = Camps.SpawnerByIdx(campIdx);
    if (spawner === undefined || settings().Timing.StackFromValve !== true) return $multi(undefined, undefined);
    for (const w of WINDOWS) {
        const dx = w[0] - spawner.location.x;
        const dy = w[1] - spawner.location.y;
        if (dx * dx + dy * dy <= WINDOW_MATCH * WINDOW_MATCH) return $multi(w[2], w[3]);
    }
    return $multi(undefined, undefined);
}

/**
 * The second the stack hit should land: StackWindowAt through Valve's window for a camp on the type's default second,
 * else the data's (a replay or measured stack second is kept). The seeds (small 54.5 to ancient 53.0) were 1-2.5 s
 * early for most 7.41 camps (evil_2/good_1 55-57, evil_1 54-56) and 1.5 s late for good_2/good_8 (52-54).
 */
export function AggroSec(data: Camps.CampJobData): number {
    const sec = data.stack?.aggroSec ?? DEFAULT_STACK_SEC[data.type];
    if (sec !== DEFAULT_STACK_SEC[data.type]) return sec;
    const [from, to] = Window(data.campIdx);
    if (from === undefined || to === undefined) return sec;
    return from + (to - from) * settings().Timing.StackWindowAt;
}

/** Records the attempt as stacked when `assumed` (the hit landed in the safe band; the box is not counted). */
export function NoteStackOutcome(campIdx: number, minute: number, assumed: boolean): boolean {
    if (!assumed) return false;
    const prev = records[campIdx];
    const count = prev !== undefined && prev.minute === minute - 1 ? prev.count + 1 : 1;
    records[campIdx] = { minute, count };
    return true;
}

export function IsStacked(campIdx: number): boolean {
    const rec = records[campIdx];
    return rec !== undefined && rec.minute >= currentMinute() - 1;
}

export function StackCount(campIdx: number): number {
    return IsStacked(campIdx) ? records[campIdx].count : 0;
}

export function NeutralsInBox(bot: Unit, campIdx: number): number {
    const margin = settings().Radii.BoxMargin;
    let n = 0;
    for (const c of bot.GetNearbyNeutralCreeps(settings().Radii.StackCountScan, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen() && Camps.InBox(campIdx, c.GetLocation(), margin)) n++;
    }
    return n;
}

/**
 * The camp idles at its spawner origin, so that is what must be in sight. Distance alone counted fogged boxes: ogre on
 * good_2 at 8:02, night (hero vision 800) and ~1,100 from the origin, read 2 of 3 neutrals and graded the stack failed.
 */
export function BoxInSight(bot: Unit, campIdx: number): boolean {
    const spawner = Camps.SpawnerByIdx(campIdx);
    if (spawner === undefined || !bot.IsAlive()) return false;
    return GetUnitToLocationDistance(bot, spawner.location) <= settings().Radii.StackSight && IsLocationVisible(spawner.location);
}

/** A visible neutral near the bot is attacking it. */
export function NeutralTargets(bot: Unit): boolean {
    for (const n of bot.GetNearbyNeutralCreeps(settings().Radii.NeutralSearch, false) ?? []) {
        if (n !== null && n !== undefined && n.IsAlive() && n.CanBeSeen() && n.GetAttackTarget() === bot) return true;
    }
    return false;
}
