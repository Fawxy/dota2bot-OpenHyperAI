/**
 * World facts: game numbers (tower reach, unit speeds, acquisition range) read from the Valve API once and shared by every
 * bot, instead of written as constants in each context (slice world-facts; ROADMAP debt, cause api-first-constants).
 *
 * A reader takes the caller's old constant as `fallback` and returns the live value, or the fallback when the API gives
 * nothing usable. The fallback is counted in Fallbacks() and read by telemetry (ev=world_fact), so it is never silent.
 * Lifetimes: a tower's reach is read once per tower handle (per game); a speed or acquisition range once per type and
 * per second (the first bot to ask in that second reads the API, the others get the stored value).
 * No imports from telemetry or any context: telemetry reads Probe() and Fallbacks(), contexts call the readers.
 */
import { Unit } from "bots/ts_libs/dota";

/** Seconds a per-moment value is reused for. */
const MomentSec = 1;

/** Test hook: API reads made, by fact. */
export const ReadCount: Record<string, number> = {};

const newTowers = () => setmetatable(new LuaTable<Unit, number>(), { __mode: "k" });
let towers = newTowers();
const moment: Record<string, { at: number; v: number | undefined }> = {};
const fell: Record<string, number> = {};
const live: Record<string, number> = {};

function counted(fact: string): void {
    ReadCount[fact] = (ReadCount[fact] ?? 0) + 1;
}

function fallback(fact: string, value: number): number {
    fell[fact] = (fell[fact] ?? 0) + 1;
    return value;
}

function valid(u: Unit | undefined): u is Unit {
    return u !== undefined && u !== null && u.IsNull() !== true;
}

/** One API read per key per second: `read` runs for the first asker, the stored result serves the rest (also a miss). */
function perMoment(fact: string, key: string, read: () => number | undefined): number | undefined {
    const now = math.floor(DotaTime() / MomentSec);
    const k = fact + ":" + key;
    const m = moment[k];
    if (m !== undefined && m.at === now) return m.v;
    counted(fact);
    const v = read();
    moment[k] = { at: now, v };
    if (v !== undefined) live[fact] = v;
    return v;
}

/** Reach of a tower's attack to a target's centre: its attack range plus its own bounding radius. Per game, per tower. */
export function TowerReach(tower: Unit, fb: number): number {
    const known = towers.get(tower);
    if (known !== undefined) return known;
    if (!valid(tower)) return fallback("tower_reach", fb);
    counted("tower_reach");
    const range = tower.GetAttackRange();
    if (range === undefined || range <= 0) return fallback("tower_reach", fb);
    const reach = range + (tower.GetBoundingRadius() ?? 0);
    towers.set(tower, reach);
    live.tower_reach = reach;
    return reach;
}

function speedOf(units: Unit[] | undefined): number | undefined {
    for (const u of units ?? []) {
        if (!valid(u)) continue;
        const s = u.GetCurrentMovementSpeed();
        if (s !== undefined && s > 0) return s;
    }
    return undefined;
}

/** Speed of a lane creep of `team` as seen from `bot` (own team's creeps via the allied scan, the other team's via the enemy scan). */
export function LaneCreepSpeed(bot: Unit, team: number, fb: number): number {
    const v = perMoment("lane_creep_speed", tostring(team), () =>
        speedOf(bot.GetNearbyLaneCreeps(1600, team !== bot.GetTeam())),
    );
    return v ?? live.lane_creep_speed ?? fallback("lane_creep_speed", fb);
}

/** Speed of a neutral creep near `bot`. */
export function NeutralSpeed(bot: Unit, fb: number): number {
    const v = perMoment("neutral_speed", "n", () => speedOf(bot.GetNearbyNeutralCreeps(1600, true)));
    return v ?? live.neutral_speed ?? fallback("neutral_speed", fb);
}

/** Acquisition range of `unit`, keyed by its name (one read per unit type per second). */
export function AcquisitionRange(unit: Unit, fb: number): number {
    const v = perMoment("acquisition", unit.GetUnitName(), () => {
        const r = unit.GetAcquisitionRange();
        return r !== undefined && r > 0 ? r : undefined;
    });
    return v ?? fallback("acquisition", fb);
}

/** Latest live value per fact, for the probe's ev=world_fact line. */
export function Live(): Record<string, number> {
    return live;
}

/** Times a reader returned its fallback, per fact (read by telemetry). */
export function Fallbacks(): Record<string, number> {
    return fell;
}

/** Test hook: forget everything. */
export function Reset(): void {
    for (const k of Object.keys(moment)) delete moment[k];
    for (const k of Object.keys(fell)) delete fell[k];
    for (const k of Object.keys(live)) delete live[k];
    for (const k of Object.keys(ReadCount)) delete ReadCount[k];
    towers = newTowers();
}

export interface ProbeRow {
    fact: string;
    live: number | undefined;
    constant: number;
}

/** What `bot` can read this moment beside the constants the contexts hold (slice world-facts probe; telemetry logs each once per game). */
export function Probe(bot: Unit, constants: { tower: number; laneCreep: number; neutral: number; acquisition: number }): ProbeRow[] {
    const rows: ProbeRow[] = [];
    const tower = bot.GetNearbyTowers(1600, true)[0] ?? bot.GetNearbyTowers(1600, false)[0];
    if (tower !== undefined) rows.push({ fact: "tower_reach", live: TowerReach(tower, constants.tower), constant: constants.tower });
    const creeps = bot.GetNearbyLaneCreeps(1600, true);
    const mine = bot.GetNearbyLaneCreeps(1600, false);
    const creep = creeps[0] ?? mine[0];
    if (creep !== undefined) {
        rows.push({ fact: "lane_creep_speed", live: LaneCreepSpeed(bot, creep.GetTeam(), constants.laneCreep), constant: constants.laneCreep });
        rows.push({ fact: "acquisition_lane_creep", live: AcquisitionRange(creep, constants.acquisition), constant: constants.acquisition });
    }
    const n = bot.GetNearbyNeutralCreeps(1600, true)[0];
    if (n !== undefined) {
        rows.push({ fact: "neutral_speed", live: NeutralSpeed(bot, constants.neutral), constant: constants.neutral });
        rows.push({ fact: "acquisition_neutral", live: AcquisitionRange(n, constants.acquisition), constant: constants.acquisition });
    }
    return rows;
}
