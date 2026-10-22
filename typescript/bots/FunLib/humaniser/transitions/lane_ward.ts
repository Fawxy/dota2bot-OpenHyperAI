/**
 * Lane safety and laning-phase transitions (task 12, Task 7): an early observer on the gank path.
 * Each lane's support (offlane pos 4, safelane pos 5) wards the spot nearest the river or jungle entrance an enemy
 * walks through to gank that lane, unless an allied observer already covers it. The ward mode asks via Pick.
 */
import { BotMode, Lane, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";

export const SOURCE = "transitions:ward";

// First-pass coordinates: each team's own RADIANT_/DIRE_LANE_PHASE river spots in aba_ward_utility (the map is not
// exactly point-symmetric, so Dire's are not mirrored). They need calibrating in game.
export const GANK_ANCHORS: Record<number, Record<Lane, Vector>> = {
    2: {
        [Lane.Top]: Vector(-4014, 2569, 0),
        [Lane.Mid]: Vector(-1615, -122, 0),
        [Lane.Bot]: Vector(3097, -4069, 0),
    },
    3: {
        [Lane.Top]: Vector(-4310, 3639, 0),
        [Lane.Mid]: Vector(1141, -458, 0),
        [Lane.Bot]: Vector(3810, -4562, 0),
    },
};

interface PendingPick {
    spot: { location: Vector };
    key: string;
}

interface WardRead {
    at: number;
    locations: Vector[];
}

let rolls: Record<string, boolean> = {};
let reads: Record<number, WardRead> = {};
let liveAt: Record<number, number> = {};
let pending: Record<number, PendingPick | undefined> = {};
let planted: Record<string, { location: Vector; spot: { plant_time_obs?: number } }> = {};

export function ResetCache(): void {
    rolls = {};
    reads = {};
    liveAt = {};
    pending = {};
    planted = {};
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

/** Our observer wards' positions, read from the game at most once per WardScanPeriod per team. */
function observers(team: number): Vector[] {
    const now = DotaTime();
    const cached = reads[team];
    if (cached !== undefined && now - cached.at < Settings.Get().WardScanPeriod) return cached.locations;
    const locations: Vector[] = [];
    for (const w of GetUnitList(UnitType.AlliedWards)) {
        if (w.GetUnitName() === "npc_dota_observer_wards") locations.push(w.GetLocation());
    }
    reads[team] = { at: now, locations };
    return locations;
}

/** The support of the snapshot's lane: pos 4 off, pos 5 safe, else the lowest support position present. Needs a core in the lane. */
function laneSupport(s: LaneState.LaneSnapshot): number | undefined {
    const kind = LaneState.LaneKindOf(s.team, s.lane);
    if (kind === "mid") return undefined;
    let core = false;
    let lowest: number | undefined;
    let expectedPresent = false;
    const expected = kind === "off" ? 4 : 5;
    for (const h of s.allies) {
        if (!h.assigned || h.position === undefined) continue;
        if (h.position <= 3) core = true;
        else if (h.position === 4 || h.position === 5) {
            if (h.position === expected) expectedPresent = true;
            if (lowest === undefined || h.position < lowest) lowest = h.position;
        }
    }
    if (!core) return undefined;
    return expectedPresent ? expected : lowest;
}

export function Pick(bot: Unit, spots: { location: Vector }[]): { location: Vector } | undefined {
    pending[bot.GetPlayerID()] = undefined;
    if (!Settings.IsOn("LaneWard") || spots.length === 0) return undefined;
    const cfg = Settings.Get();
    const now = DotaTime();
    if (now < cfg.WardFrom || now > cfg.WardTo) return undefined;
    const s = LaneState.ForBot(bot);
    if (s === undefined) return undefined;
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos !== laneSupport(s)) return undefined;

    const key = `${s.team}:${s.lane}`;
    let passed = rolls[key];
    if (passed === undefined) {
        passed = LaneConfig.Roll(Settings.Lerp(cfg.WardChance, LaneConfig.SkillOf(bot)));
        rolls[key] = passed;
    }
    if (!passed) return undefined;

    const anchor = GANK_ANCHORS[s.team]?.[s.lane];
    if (anchor === undefined) return undefined;
    // The ward mode stamps plant_time_obs on the spot it plants, which covers the lane before the scan cache catches up.
    const done = planted[key];
    if (done !== undefined && done.spot.plant_time_obs !== undefined && done.spot.plant_time_obs > 0 && now - done.spot.plant_time_obs < cfg.WardLifetime) return undefined;
    for (const loc of observers(s.team)) if (dist2D(loc, anchor) <= cfg.WardCoverRadius) return undefined;

    let best: { location: Vector } | undefined;
    let bestD = math.huge;
    for (const spot of spots) {
        const d = dist2D(spot.location, anchor);
        if (d < bestD) {
            bestD = d;
            best = spot;
        }
    }
    if (best === undefined || bestD > cfg.WardAnchorRadius) return undefined;
    pending[bot.GetPlayerID()] = { spot: best, key };
    return best;
}

/** The ward mode took `spot` as its target after its own safety checks: only now does the pick count as live. */
export function Confirm(bot: Unit, spot: { location: Vector }): void {
    const p = pending[bot.GetPlayerID()];
    if (!Settings.IsOn("LaneWard") || p === undefined || p.spot !== spot) return;
    liveAt[bot.GetPlayerID()] = DotaTime();
    planted[p.key] = { location: spot.location, spot: spot as any };
}

export function Tick(bot: Unit): void {
    const at = liveAt[bot.GetPlayerID()];
    if (Settings.IsOn("LaneWard") && at !== undefined && DotaTime() - at <= Settings.Get().WardLive) {
        Intent.Claim(bot, { source: SOURCE, tier: "TRANSITION", mode: BotMode.Ward, floor: Settings.Get().WardFloor });
    } else {
        Intent.Release(bot, SOURCE, BotMode.Ward);
    }
}
