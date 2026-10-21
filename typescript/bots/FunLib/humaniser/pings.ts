/**
 * Ping interpreter (task 05): turns human allies' map pings into Team Orders.
 *
 * Runs from every bot's Tick, at most once per team per frame per module instance. Pings are read from
 * GetMostRecentPing() of every human ally and classified from team-visible state only (unit lists,
 * building lists, map spots), so every bot derives the same order under the same sourceKey whether or
 * not modules are shared.
 */
import { GameState, Lane, Ping, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Orders from "bots/FunLib/humaniser/orders";

export const DEFAULTS = {
    Enable: true,
    // Pings older than this when first seen are ignored (e.g. placed before the scripts loaded).
    MaxPingAge: 3,
    RoshanRadius: 600,
    HeroRadius: 300,
    BuildingRadius: 700,
    SpotRadius: 800,
    Roshan: { Duration: 25, MaxResponders: 5 },
    Attack: { Duration: 8, MaxResponders: 2, MaxDistance: 4000, AlsoWithin: 1600 },
    Push: { Duration: 20, MaxResponders: 3 },
    Defend: { Duration: 20, MaxResponders: 2, AlsoTpBeyond: 5000 },
    // A danger ping lasts Duration at most. After MinSeconds it is forgotten early once the team can see the
    // pinged spot and no enemy hero has been seen within Radius of it for ClearSeconds.
    Avoid: { Duration: 10, Radius: 1200, MinSeconds: 4, ClearSeconds: 2 },
    Gather: { Duration: 8, MaxResponders: 2 },
};

export type PingConfig = typeof DEFAULTS;

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" ? merge(d, v) : v;
    }
    return result;
}

let cached: PingConfig | undefined;
export function Get(): PingConfig {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().Pings) as PingConfig;
    return cached;
}

/** True when the interpreter owns ping handling; legacy per-mode ping readers yield to it. */
export function IsActive(): boolean {
    return Config.IsFeatureEnabled("Pings");
}

/**
 * The single place that decides whether a ping means "danger". The bot API documents normal_ping = false
 * as the danger/X ping, but OHA's push/defend code treats "not normal_ping" as "attack here", so this is
 * unverified. Flip here after the step-0 in-game check (docs/HUMANISER_DEV.md).
 */
export function IsDangerPing(ping: Ping): boolean {
    return ping.normal_ping === false;
}

/** Map knowledge injected from jmz_func (this module cannot require it). */
export interface WorldHelpers {
    roshanLocation: (this: void) => Vector;
    /** Rune and Tormentor spots where pings keep their existing per-mode meaning. */
    reservedSpots: (this: void) => Vector[];
}
let helpers: WorldHelpers | undefined;

export function SetHelpers(h: WorldHelpers): void {
    helpers = h;
}

export function GetHelpers(): WorldHelpers | undefined {
    return helpers;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

/** Lane encoded in a building's unit name; the fort (and anything unnamed) counts as mid. */
export function LaneFromBuildingName(name: string): Lane {
    if (string.find(name, "_top")[0] !== undefined) return Lane.Top;
    if (string.find(name, "_bot")[0] !== undefined) return Lane.Bot;
    return Lane.Mid;
}

function isLaneBuilding(name: string): boolean {
    if (string.find(name, "watch_tower")[0] !== undefined || string.find(name, "fillers")[0] !== undefined) return false;
    return (
        string.find(name, "tower")[0] !== undefined || string.find(name, "rax")[0] !== undefined || string.find(name, "_fort")[0] !== undefined
    );
}

function nearestBuilding(list: UnitType, loc: Vector, radius: number): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = radius;
    for (const unit of GetUnitList(list)) {
        if (unit === null || unit === undefined || !unit.IsAlive() || !isLaneBuilding(unit.GetUnitName())) continue;
        const d = dist2D(unit.GetLocation(), loc);
        if (d <= bestDist) {
            best = unit;
            bestDist = d;
        }
    }
    return best;
}

export function NearestVisibleEnemyHero(loc: Vector, radius: number): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = radius;
    for (const unit of GetUnitList(UnitType.EnemyHeroes)) {
        if (unit === null || unit === undefined || !unit.IsAlive() || !unit.CanBeSeen()) continue;
        const d = dist2D(unit.GetLocation(), loc);
        if (d <= bestDist) {
            best = unit;
            bestDist = d;
        }
    }
    return best;
}

function nearReservedSpot(loc: Vector, radius: number): boolean {
    if (helpers === undefined) return false;
    for (const spot of helpers.reservedSpots()) {
        if (dist2D(spot, loc) <= radius) return true;
    }
    return false;
}

/**
 * The lane whose creep front the ping is on ("leave the wave alone") and the bots laning there; only during
 * laning with the lane plan on. Lanes nobody is assigned to are skipped, as nobody could respond there.
 */
function laneFrontPing(team: number, loc: Vector): { lane: Lane; pids: number[] } | undefined {
    if (!LaneConfig.IsOn("Plan") || !LaneConfig.InLaningPhase()) return undefined;
    let best: { lane: Lane; pids: number[] } | undefined;
    let bestDist = LaneConfig.Settings().Radii.LaneFrontPing;
    for (const lane of [Lane.Top, Lane.Mid, Lane.Bot]) {
        const pids = Orders.BotsAssignedTo(team, lane);
        if (pids.length === 0) continue;
        const d = dist2D(GetLaneFrontLocation(team, lane, 0), loc);
        if (d <= bestDist) {
            best = { lane, pids };
            bestDist = d;
        }
    }
    return best;
}

export interface Classification {
    context: string;
    spec?: Orders.OrderSpec;
}

/**
 * Classifies a ping by what is near it, in the spec's precedence order. Only reads state every bot on the
 * team sees identically. `issuerSmoked` widens GATHER/ATTACK to the whole team (moving out of a smoke).
 */
export function Classify(issuerPID: number, ping: Ping, issuerSmoked: boolean, team: number = GetTeam()): Classification {
    const cfg = Get();
    const loc = ping.location;
    const sourceKey = `ping:${issuerPID}:${string.format("%.2f", ping.time)}`;
    const base = { sourceKey, issuerPID, location: loc, delayKind: "ping" as const, ackPing: true };

    if (helpers !== undefined && dist2D(loc, helpers.roshanLocation()) <= cfg.RoshanRadius) {
        return {
            context: "roshan",
            spec: { ...base, type: "ROSHAN", location: helpers.roshanLocation(), duration: cfg.Roshan.Duration, maxResponders: cfg.Roshan.MaxResponders },
        };
    }

    const hero = NearestVisibleEnemyHero(loc, cfg.HeroRadius);
    if (hero !== undefined) {
        return {
            context: "enemy_hero",
            spec: {
                ...base,
                type: "ATTACK",
                target: hero,
                location: hero.GetLocation(),
                duration: cfg.Attack.Duration,
                maxResponders: issuerSmoked ? 5 : cfg.Attack.MaxResponders,
                maxDistance: cfg.Attack.MaxDistance,
                alsoWithin: cfg.Attack.AlsoWithin,
            },
        };
    }

    const enemyBuilding = nearestBuilding(UnitType.EnemyBuildings, loc, cfg.BuildingRadius);
    if (enemyBuilding !== undefined) {
        return {
            context: "enemy_building",
            spec: {
                ...base,
                type: "PUSH",
                lane: LaneFromBuildingName(enemyBuilding.GetUnitName()),
                location: enemyBuilding.GetLocation(),
                duration: cfg.Push.Duration,
                maxResponders: cfg.Push.MaxResponders,
            },
        };
    }

    const ownBuilding = nearestBuilding(UnitType.AlliedBuildings, loc, cfg.BuildingRadius);
    if (ownBuilding !== undefined) {
        return {
            context: "own_building",
            spec: {
                ...base,
                type: "DEFEND",
                lane: LaneFromBuildingName(ownBuilding.GetUnitName()),
                location: ownBuilding.GetLocation(),
                duration: cfg.Defend.Duration,
                maxResponders: cfg.Defend.MaxResponders,
                alsoTpBeyond: cfg.Defend.AlsoTpBeyond,
            },
        };
    }

    if (nearReservedSpot(loc, cfg.SpotRadius)) return { context: "reserved_spot" };

    if (IsDangerPing(ping)) {
        return {
            context: "danger",
            spec: { ...base, type: "AVOID", radius: cfg.Avoid.Radius, duration: cfg.Avoid.Duration, maxResponders: 5, ackPing: false },
        };
    }

    const front = laneFrontPing(team, loc);
    if (front !== undefined) {
        return {
            context: "lane_front",
            spec: {
                ...base,
                type: "LANE_HANDSOFF",
                lane: front.lane,
                duration: LaneConfig.Settings().Timing.PingHandsOff,
                maxResponders: front.pids.length,
                onlyPIDs: front.pids,
                ackPing: false,
            },
        };
    }

    return {
        context: "ground",
        spec: { ...base, type: "GATHER", duration: cfg.Gather.Duration, maxResponders: issuerSmoked ? 5 : cfg.Gather.MaxResponders },
    };
}

// Last ping time handled per human; GetMostRecentPing keeps returning the same ping until a new one.
const lastPingTime: Record<number, number> = {};
const scannedAt: Record<number, number> = {};
const clearSince: Record<number, number | undefined> = {};
let lastSummary = "-";

function cancelSmokeFrom(team: number, issuerPID: number): void {
    for (const order of Orders.GetActive(team)) {
        if (order.type === "SMOKE" && order.issuerPID === issuerPID) {
            Orders.Cancel(team, order.id);
            return;
        }
    }
}

/** Reads every human ally's latest ping and posts orders for new ones. Cheap when nothing changed. */
export function Scan(team: number): void {
    const cfg = Get();
    const now = GameTime();
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const pid = players[i - 1];
        if (IsPlayerBot(pid)) continue;
        const member = GetTeamMember(i);
        if (member === null || member === undefined) continue;
        const ping = member.GetMostRecentPing();
        if (ping === null || ping === undefined || ping.time === 0 || ping.location === undefined) continue;
        if (lastPingTime[pid] === ping.time) continue;
        lastPingTime[pid] = ping.time;
        if (now - ping.time > cfg.MaxPingAge) continue;

        const smoked = member.HasModifier("modifier_smoke_of_deceit");
        const result = Classify(pid, ping, smoked, team);
        lastSummary = `${result.context} by ${pid} @${string.format("%.1f", ping.time)}`;
        HDebug.Log("pings", lastSummary, `danger=${tostring(IsDangerPing(ping))}`);
        if (result.spec === undefined) continue;
        if (smoked && (result.spec.type === "GATHER" || result.spec.type === "ATTACK")) cancelSmokeFrom(team, pid);
        Orders.Post(team, result.spec);
    }
}

/** Cancels AVOID orders whose area the team can see is clear. Inputs are team-visible, so every bot agrees. */
export function ForgetClearedDangers(team: number): void {
    const cfg = Get().Avoid;
    const now = GameTime();
    for (const order of Orders.GetActive(team)) {
        if (order.type !== "AVOID" || order.location === undefined) continue;
        if (now - order.createdAt < cfg.MinSeconds) continue;
        const radius = order.radius ?? cfg.Radius;
        if (!IsLocationVisible(order.location) || NearestVisibleEnemyHero(order.location, radius) !== undefined) {
            clearSince[order.id] = undefined;
            continue;
        }
        const since = clearSince[order.id] ?? now;
        clearSince[order.id] = since;
        if (now - since >= cfg.ClearSeconds) {
            clearSince[order.id] = undefined;
            HDebug.Log("pings", `forgot danger ping ${order.id}: area clear`);
            Orders.Cancel(team, order.id);
        }
    }
}

export function Tick(bot: Unit): void {
    if (!IsActive() || GetGameState() !== GameState.GameInProgress) return;
    const team = bot.GetTeam();
    const now = GameTime();
    if (scannedAt[team] !== now) {
        scannedAt[team] = now;
        Scan(team);
        ForgetClearedDangers(team);
    }
    HDebug.Text(bot, "ping", lastSummary);
}
