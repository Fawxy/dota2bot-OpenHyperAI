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
import { Team, Tower, Unit } from "bots/ts_libs/dota";

/** Seconds a per-moment value is reused for. */
const MomentSec = 1;

/** Test hook: API reads made, by fact. */
export const ReadCount: Record<string, number> = {};

const newTowers = () => setmetatable(new LuaTable<Unit, number>(), { __mode: "k" });
let towers = newTowers();
const moment: Record<string, { at: number; v: number | undefined }> = {};
const fell: Record<string, number> = {};
const fellValue: Record<string, number> = {};
const live: Record<string, number> = {};

function counted(fact: string): void {
    ReadCount[fact] = (ReadCount[fact] ?? 0) + 1;
}

function fallback(fact: string, value: number): number {
    fell[fact] = (fell[fact] ?? 0) + 1;
    fellValue[fact] = value;
    return value;
}

/**
 * A caller's own API read gave nothing and it used the constant `fb` (a per-unit fact such as a hero's attack period, read
 * where the unit is in hand). Counted like the readers' fallbacks, so telemetry logs the first one of each fact.
 */
export function Fallback(fact: string, fb: number): number {
    return fallback(fact, fb);
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

/**
 * The script's own team first: each team's bots run in their own VM, and a fogged enemy tower answers with a wrong attack range
 * (lctl6 smoke, Dire reading Radiant's top T1 at the start: 200, not 700), so only a tower the team sees is read.
 */
function teamsOwnFirst(): number[] {
    return GetTeam() === Team.Dire ? [Team.Dire, Team.Radiant] : [Team.Radiant, Team.Dire];
}

let gameReach: number | undefined;
let gameRange: number | undefined;

/** The towers' attack range itself (700 in 7.41), the distance a hit reaches from the tower's edge. Per game, from the first tower that answers. */
export function TowerAttackRange(fb: number): number {
    if (gameRange !== undefined) return gameRange;
    for (const team of teamsOwnFirst()) {
        const t = GetTower(team, Tower.Top1);
        if (t !== null && t !== undefined && valid(t) && t.CanBeSeen()) {
            const r = t.GetAttackRange();
            if (r !== undefined && r > 0) {
                gameRange = r;
                return r;
            }
        }
    }
    return fallback("tower_range", fb);
}

/**
 * The towers' attack reach for the whole game (every tier has the same range and size in 7.41; read from the first tower that
 * answers, either team). Contexts add their own stated margin to it. `fb` is the constant it replaces.
 */
export function Reach(fb: number): number {
    if (gameReach !== undefined) return gameReach;
    for (const team of teamsOwnFirst()) {
        const t = GetTower(team, Tower.Top1);
        if (t !== null && t !== undefined && valid(t) && t.CanBeSeen()) {
            const r = TowerReach(t, -1);
            if (r > 0) {
                gameReach = r;
                return r;
            }
        }
    }
    return fallback("tower_reach", fb);
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
        // Base speed, not current: a camp creep standing still reads a current speed of 0 and a slowed one reads less, and the
        // pull's timing needs the speed it moves at once it starts (user 07/11/2026). A read of 0 or less is no read.
        const s = u.GetBaseMovementSpeed();
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
export function AcquisitionRange(unit: Unit, fb: number, kind: "lane_creep" | "neutral"): number {
    // Lane creeps differ by type (melee 500, ranged 600, siege 800 per lane_push KINDS): the remembered "lane_creep" value is the
    // melee creep's, the one the pull timing's clearance is written for (review H1). Other types read directly and are not stored.
    if (kind === "lane_creep" && !unit.GetUnitName().includes("melee")) {
        const r = unit.GetAcquisitionRange();
        return r !== undefined && r > 0 ? r : fb;
    }
    const v = perMoment("acquisition_" + kind, unit.GetUnitName(), () => {
        const r = unit.GetAcquisitionRange();
        return r !== undefined && r > 0 ? r : undefined;
    });
    return v ?? live["acquisition_" + kind] ?? fallback("acquisition_" + kind, fb);
}

const noReadYet: Record<string, boolean> = {};
/**
 * The latest live value of a fact, for code with no unit in hand (pure timing and simulation functions). Fed by the readers above
 * (telemetry's world-facts tick reads each moment); before the first read, or with telemetry off, it returns `fb`, counted once.
 */
export function Latest(fact: "lane_creep_speed" | "acquisition_lane_creep", fb: number): number {
    const v = live[fact];
    if (v !== undefined) return v;
    if (noReadYet[fact] !== true) {
        noReadYet[fact] = true;
        fallback(fact, fb);
    }
    return fb;
}

/** Latest live value per fact, for the probe's ev=world_fact line. */
export function Live(): Record<string, number> {
    return live;
}

/** Times a reader returned its fallback, per fact (read by telemetry). */
export function Fallbacks(): Record<string, number> {
    return fell;
}

/** Facts the probe has a row for: telemetry logs those from the probe, never from the fallback list (review M1). */
const PROBED: Record<string, boolean> = {
    tower_reach: true,
    tower_range: true,
    lane_creep_speed: true,
    acquisition_lane_creep: true,
    neutral_speed: true,
    acquisition_neutral: true,
};

/** Fallbacks taken for facts the probe has no row for (a caller's own read, `Fallback`): fact, count so far, value used. */
export function UnprobedFallbacks(): { fact: string; n: number; value: number }[] {
    const out: { fact: string; n: number; value: number }[] = [];
    for (const [fact, n] of Object.entries(fell)) {
        if (n > 0 && PROBED[fact] !== true) out.push({ fact, n, value: fellValue[fact] ?? -1 });
    }
    return out;
}

/** Test hook: forget everything. */
export function Reset(): void {
    for (const k of Object.keys(moment)) delete moment[k];
    for (const k of Object.keys(fell)) delete fell[k];
    for (const k of Object.keys(fellValue)) delete fellValue[k];
    for (const k of Object.keys(live)) delete live[k];
    for (const k of Object.keys(ReadCount)) delete ReadCount[k];
    for (const k of Object.keys(noReadYet)) delete noReadYet[k];
    towers = newTowers();
    gameReach = undefined;
    gameRange = undefined;
}

export interface ProbeRow {
    fact: string;
    live: number | undefined;
    constant: number;
}

/** What `bot` can read this moment beside the constants the contexts hold (slice world-facts probe; telemetry logs each once per game). */
export function Probe(
    bot: Unit,
    constants: { tower: number; towerRange: number; laneCreep: number; neutral: number; acquisition: number },
): ProbeRow[] {
    const rows: ProbeRow[] = [];
    const tower = bot.GetNearbyTowers(1600, true)[0] ?? bot.GetNearbyTowers(1600, false)[0];
    if (tower !== undefined) {
        rows.push({ fact: "tower_reach", live: TowerReach(tower, constants.tower), constant: constants.tower });
        rows.push({ fact: "tower_range", live: TowerAttackRange(constants.towerRange), constant: constants.towerRange });
    }
    const creeps = bot.GetNearbyLaneCreeps(1600, true);
    const mine = bot.GetNearbyLaneCreeps(1600, false);
    const creep = creeps[0] ?? mine[0];
    if (creep !== undefined) {
        rows.push({ fact: "lane_creep_speed", live: LaneCreepSpeed(bot, creep.GetTeam(), constants.laneCreep), constant: constants.laneCreep });
        // The remembered value is the melee creep's (review H1/L5): log the row from a melee creep only.
        const melee = [...creeps, ...mine].find((c) => c.GetUnitName().includes("melee"));
        if (melee !== undefined) rows.push({ fact: "acquisition_lane_creep", live: AcquisitionRange(melee, constants.acquisition, "lane_creep"), constant: constants.acquisition });
    }
    const n = bot.GetNearbyNeutralCreeps(1600, true)[0];
    if (n !== undefined) {
        rows.push({ fact: "neutral_speed", live: NeutralSpeed(bot, constants.neutral), constant: constants.neutral });
        rows.push({ fact: "acquisition_neutral", live: AcquisitionRange(n, constants.acquisition, "neutral"), constant: constants.acquisition });
    }
    return rows;
}
