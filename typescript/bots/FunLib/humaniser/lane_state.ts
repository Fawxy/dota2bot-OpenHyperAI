/**
 * Per-lane state snapshot (task 07): equilibrium position, creep summaries, wave timing and nearby
 * heroes. Cached per (team, lane); nothing here touches the engine unless the lane system is active.
 * Observer-dependent values (exposure, laneScore) are computed per bot in ScoreFor, not stored in the
 * shared snapshot.
 */
import { Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export interface CreepSummary {
    count: number;
    totalHP: number;
    rangedAlive: boolean;
    siegeAlive: boolean;
    units: Unit[];
    lead?: Unit;
}

export interface LaneHero {
    unit: Unit;
    pid: number;
    isBot: boolean;
    alive: boolean;
    assigned: boolean;
    position: number | undefined;
    hp: number;
    distToFront: number;
}

export interface LaneSnapshot {
    team: number;
    lane: Lane;
    kind: Camps.LaneKind;
    time: number;
    ourFront: number;
    enemyFront: number;
    meetAmount: number;
    ourTowerAmount: number;
    theirTowerAmount: number;
    eqPos: number;
    frontLoc: Vector;
    ally: CreepSummary;
    enemy: CreepSummary;
    cycleSec: number;
    nextWaveIn: number;
    enemyArrivalSec?: number;
    enemyWaveSizes: number[];
    allies: LaneHero[];
    desiredEq: number;
    enemyDeniesPerCycle: number[];
    lastAllyAggroAt: Record<number, number>;
    eqHistory: number[];
    allyPower: number;
    enemyPower: number;
    imbalance: number;
    forecastEq: number;
}

export interface LaneEnemy {
    unit?: Unit;
    pid: number;
    visible: boolean;
    location: Vector;
    timeSinceSeen: number;
    position?: number;
}

export interface ObserverView {
    exposure: number;
    laneScore: number;
    foresight: number;
    forecastScore: number;
}

interface ScannedCreep {
    unit: Unit;
    loc: Vector;
    absAmount: number;
}

interface Scan {
    time: number;
    ally: Record<number, ScannedCreep[]>;
    enemy: Record<number, ScannedCreep[]>;
}

interface Track {
    cycle: number;
    arrivalSec?: number;
    maxEnemy: number;
    denies: number;
    deniedCreeps: LuaTable<Unit, boolean>;
    lastEq: number;
    arrivals: number[];
    waveSizes: number[];
    deniesPerCycle: number[];
    eqHistory: number[];
    aggro: Record<number, number>;
    eqSampledCycle?: number;
}

const LANES: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];
const TOWER_IDS: Record<number, number[]> = {
    [Lane.Top]: [Tower.Top1, Tower.Top2, Tower.Top3],
    [Lane.Mid]: [Tower.Mid1, Tower.Mid2, Tower.Mid3],
    [Lane.Bot]: [Tower.Bot1, Tower.Bot2, Tower.Bot3],
};
const WAVE_HISTORY = 3;
const EQ_HISTORY = 4;
const ARRIVAL_CREEPS = 3;

let scans: Record<number, Scan> = {};
let snapshots: Record<string, LaneSnapshot> = {};
let tracks: Record<string, Track> = {};
let towerAmounts: Record<string, number> = {};
let enemyCache: Record<number, { time: number; list: LaneEnemy[] }> = {};
let viewCache: Record<string, { time: number; view: ObserverView }> = {};
let preRuneFn: (this: void, team: number, lane: Lane) => boolean = () => false;
let refreshCallbacks: ((this: void, s: LaneSnapshot) => void)[] = [];

function weakKeys(): LuaTable<Unit, boolean> {
    return setmetatable(new LuaTable<Unit, boolean>(), { __mode: "k" });
}

function timing(): LaneConfig.LaneSettings["Timing"] {
    return LaneConfig.Settings().Timing;
}

function radii(): LaneConfig.LaneSettings["Radii"] {
    return LaneConfig.Settings().Radii;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function clamp(v: number, lo: number, hi: number): number {
    return v < lo ? lo : v > hi ? hi : v;
}

function contains(name: string, part: string): boolean {
    return string.find(name, part, 1, true)[0] !== undefined;
}

function enemyTeamOf(team: number): number {
    return team === Team.Radiant ? Team.Dire : Team.Radiant;
}

function copyRecord(r: Record<number, number>): Record<number, number> {
    const copy: Record<number, number> = {};
    for (const [k, v] of pairs(r)) copy[k as number] = v as number;
    return copy;
}

function push(list: number[], v: number, max: number): void {
    list.push(v);
    if (list.length > max) table.remove(list, 1);
}

function median(list: number[]): number | undefined {
    if (list.length === 0) return undefined;
    const sorted = [...list];
    sorted.sort((a, b) => a - b);
    const n = sorted.length;
    return n % 2 === 1 ? sorted[(n - 1) / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
}

export function EqPos(meetAmount: number, ourTower: number, theirTower: number): number {
    const span = theirTower - ourTower;
    if (span === 0) return 0;
    return clamp((2 * (meetAmount - ourTower)) / span - 1, -1, 1);
}

/** A front behind its own side's tower has no wave in lane (it reads that side's base), so the other front is the meet. */
export function MeetAmount(ourFront: number, enemyFront: number, ourTower: number, theirTower: number): number {
    const span = theirTower - ourTower;
    const oursOut = (ourFront - ourTower) * span < 0;
    const theirsOut = (enemyFront - theirTower) * span > 0;
    if (oursOut && !theirsOut) return enemyFront;
    if (theirsOut && !oursOut) return ourFront;
    return (ourFront + enemyFront) / 2;
}

export function CreepWeight(name: string): number {
    const w = LaneConfig.Settings().ForecastModel.TypeWeight;
    if (contains(name, "ranged")) return w.ranged;
    if (contains(name, "siege")) return w.siege;
    return w.melee;
}

export function LanePower(units: Unit[]): number {
    let power = 0;
    for (const u of units) if (u.IsAlive()) power += u.GetHealth() * CreepWeight(u.GetUnitName());
    return power;
}

export function Imbalance(allyPower: number, enemyPower: number): number {
    return (allyPower - enemyPower) / (allyPower + enemyPower + LaneConfig.Settings().ForecastModel.PowerFloor);
}

export function ForecastEq(eqPos: number, imbalance: number): number {
    return clamp(eqPos + LaneConfig.Settings().ForecastModel.K * imbalance, -1, 1);
}

export function LaneKindOf(team: number, lane: Lane): Camps.LaneKind {
    if (lane === Lane.Mid) return "mid";
    return lane === Camps.LaneOfKind(team, "safe") ? "safe" : "off";
}

export function DesiredEq(kind: Camps.LaneKind, preRune: boolean): number {
    const eq = LaneConfig.Settings().Eq;
    if (kind === "mid") return preRune ? eq.MidPreRune : eq.Mid;
    return kind === "safe" ? eq.Safe : eq.Off;
}

export function LaneScore(desired: number, eqPos: number, enemyXpExposure: number): number {
    return desired - eqPos - LaneConfig.Settings().Eq.XpDenyWeight * enemyXpExposure;
}

export function ForesightOf(skill: number): number {
    return LaneConfig.IsOn("Forecast") ? LaneConfig.Curve("Foresight", skill) : 0;
}

export function ForecastScore(desired: number, eqPos: number, forecastEq: number, foresight: number, exposure: number): number {
    return LaneScore(desired, eqPos + foresight * (forecastEq - eqPos), exposure);
}

export function SetPreRune(fn: (this: void, team: number, lane: Lane) => boolean): void {
    preRuneFn = fn;
}

export function OnRefresh(fn: (this: void, s: LaneSnapshot) => void): void {
    refreshCallbacks.push(fn);
}

export function ResetCache(): void {
    scans = {};
    snapshots = {};
    tracks = {};
    towerAmounts = {};
    enemyCache = {};
    viewCache = {};
}

export function IsLaneCreepName(name: string): boolean {
    return contains(name, "creep_goodguys") || contains(name, "creep_badguys") || contains(name, "goodguys_siege") || contains(name, "badguys_siege");
}

function partition(units: Unit[], enemy: boolean): Record<number, ScannedCreep[]> {
    const byLane: Record<number, ScannedCreep[]> = { [Lane.Top]: [], [Lane.Mid]: [], [Lane.Bot]: [] };
    const assign = radii().LaneAssign;
    for (const unit of units) {
        if (enemy && !unit.CanBeSeen()) continue;
        if (!unit.IsAlive() || !IsLaneCreepName(unit.GetUnitName())) continue;
        const loc = unit.GetLocation();
        let bestLane: Lane | undefined;
        let bestDist = math.huge;
        let bestAmount = 0;
        for (const lane of LANES) {
            const r = GetAmountAlongLane(lane, loc);
            if (r.distance < bestDist) {
                bestDist = r.distance;
                bestLane = lane;
                bestAmount = r.amount;
            }
        }
        if (bestLane === undefined || bestDist > assign) continue;
        byLane[bestLane].push({ unit, loc, absAmount: bestAmount });
    }
    return byLane;
}

function scanFor(team: number): Scan {
    const now = DotaTime();
    const cached = scans[team];
    if (cached !== undefined && cached.time === now) return cached;
    const scan: Scan = {
        time: now,
        ally: partition(GetUnitList(UnitType.AlliedCreeps), false),
        enemy: partition(GetUnitList(UnitType.EnemyCreeps), true),
    };
    scans[team] = scan;
    return scan;
}

function summarise(team: number, list: ScannedCreep[], front: Vector, withLead: boolean): CreepSummary {
    const summary: CreepSummary = { count: 0, totalHP: 0, rangedAlive: false, siegeAlive: false, units: [] };
    const radius = radii().LaneCreep;
    let leadAmount = -math.huge;
    for (const c of list) {
        if (dist2D(c.loc, front) > radius) continue;
        summary.count++;
        summary.totalHP += c.unit.GetHealth();
        const name = c.unit.GetUnitName();
        if (contains(name, "ranged")) summary.rangedAlive = true;
        if (contains(name, "siege")) summary.siegeAlive = true;
        summary.units.push(c.unit);
        if (withLead) {
            const amount = Camps.ToTeamAmount(team, c.absAmount);
            if (amount > leadAmount) {
                leadAmount = amount;
                summary.lead = c.unit;
            }
        }
    }
    return summary;
}

/** Absolute amount of the nearest alive tower of `owner` on `lane`; undefined when all three are down. */
function nearestTowerAbs(owner: number, lane: Lane): number | undefined {
    for (const id of TOWER_IDS[lane]) {
        const tower = GetTower(owner, id);
        if (tower === null || tower === undefined || !tower.IsAlive()) continue;
        // The amount is in the reading script's frame, and this module may be shared by both teams.
        const key = `${GetTeam()}:${owner}:${id}`;
        let amount = towerAmounts[key];
        if (amount === undefined) {
            amount = GetAmountAlongLane(lane, tower.GetLocation()).amount;
            towerAmounts[key] = amount;
        }
        return amount;
    }
    return undefined;
}

function teamAmountAt(team: number, lane: Lane, loc: Vector): number {
    return Camps.ToTeamAmount(team, GetAmountAlongLane(lane, loc).amount);
}

/** `loc`'s amount along `lane` in `team`'s frame (0 = team's base), the frame of the snapshot's fronts and towers. */
export function TeamAmountAt(team: number, lane: Lane, loc: Vector): number {
    return teamAmountAt(team, lane, loc);
}

function heroesFor(team: number, lane: Lane, front: Vector): LaneHero[] {
    const result: LaneHero[] = [];
    const near = radii().AllyNearFront;
    const count = GetTeamPlayers(team).length;
    for (let i = 1; i <= count; i++) {
        const unit = GetTeamMember(i);
        if (unit === null || unit === undefined || unit.IsIllusion()) continue;
        const alive = unit.IsAlive();
        const assigned = unit.GetAssignedLane() === lane;
        const dist = alive ? GetUnitToLocationDistance(unit, front) : math.huge;
        if (!assigned && !(alive && dist <= near)) continue;
        const maxHP = unit.GetMaxHealth();
        result.push({
            unit,
            pid: unit.GetPlayerID(),
            isBot: unit.IsBot(),
            alive,
            assigned,
            position: LaneConfig.PositionOf(unit),
            hp: alive && maxHP > 0 ? unit.GetHealth() / maxHP : 0,
            distToFront: dist,
        });
    }
    return result;
}

function trackFor(key: string, now: number): Track {
    let t = tracks[key];
    if (t === undefined) {
        t = {
            cycle: math.floor(now / timing().WaveCycle),
            maxEnemy: 0,
            denies: 0,
            deniedCreeps: weakKeys(),
            lastEq: 0,
            arrivals: [],
            waveSizes: [],
            deniesPerCycle: [],
            eqHistory: [],
            aggro: {},
        };
        tracks[key] = t;
    }
    return t;
}

function rollCycle(t: Track, now: number): void {
    const cycle = math.floor(now / timing().WaveCycle);
    if (cycle === t.cycle) return;
    if (t.arrivalSec !== undefined) push(t.arrivals, t.arrivalSec, WAVE_HISTORY);
    push(t.waveSizes, t.maxEnemy, WAVE_HISTORY);
    push(t.deniesPerCycle, t.denies, WAVE_HISTORY);
    push(t.eqHistory, t.lastEq, EQ_HISTORY);
    t.cycle = cycle;
    t.arrivalSec = undefined;
    t.maxEnemy = 0;
    t.denies = 0;
    t.deniedCreeps = weakKeys();
}

function countDenies(t: Track, observer: Unit, lane: Lane, enemyLane: ScannedCreep[]): void {
    for (const e of Enemies(observer, lane)) {
        if (!e.visible || e.unit === undefined) continue;
        const target = e.unit.GetAttackTarget();
        if (target === null || target === undefined || t.deniedCreeps.get(target) === true) continue;
        for (const c of enemyLane) {
            if (c.unit === target) {
                t.deniedCreeps.set(target, true);
                t.denies++;
                break;
            }
        }
    }
}

function refresh(team: number, lane: Lane, key: string, observer: Unit | undefined): LaneSnapshot {
    const now = DotaTime();
    const enemyTeam = enemyTeamOf(team);
    const scan = scanFor(team);
    const t = trackFor(key, now);
    rollCycle(t, now);

    const frontLoc = GetLaneFrontLocation(team, lane, 0);
    // In game GetLaneFrontAmount answers in the calling script's frame whatever team is asked (console.9055745679:
    // both fronts equal at the meet, enemy front 1 before the horn, for both teams), so both fronts come from their
    // locations in the same frame as the tower amounts. EqPos does not depend on which way that frame runs.
    const ourFront = teamAmountAt(team, lane, frontLoc);
    const enemyFront = teamAmountAt(team, lane, GetLaneFrontLocation(enemyTeam, lane, 0));
    const ourAbs = nearestTowerAbs(team, lane);
    const theirAbs = nearestTowerAbs(enemyTeam, lane);
    const ourTowerAmount = ourAbs !== undefined ? Camps.ToTeamAmount(team, ourAbs) : 0;
    const theirTowerAmount = theirAbs !== undefined ? Camps.ToTeamAmount(team, theirAbs) : 1;
    const meetAmount = MeetAmount(ourFront, enemyFront, ourTowerAmount, theirTowerAmount);
    const eqPos = EqPos(meetAmount, ourTowerAmount, theirTowerAmount);
    const kind = LaneKindOf(team, lane);

    const ally = summarise(team, scan.ally[lane], frontLoc, true);
    const enemy = summarise(team, scan.enemy[lane], frontLoc, false);

    const allyPower = LanePower(ally.units);
    const enemyPower = LanePower(enemy.units);
    const imbalance = Imbalance(allyPower, enemyPower);

    const cycleSec = now % timing().WaveCycle;
    if (enemy.count > t.maxEnemy) t.maxEnemy = enemy.count;
    if (t.arrivalSec === undefined && enemy.count >= ARRIVAL_CREEPS) t.arrivalSec = cycleSec;
    t.lastEq = eqPos;
    const forecastEq = ForecastEq(eqPos, imbalance);
    if (cycleSec >= timing().EqSampleAt && t.eqSampledCycle !== t.cycle) {
        t.eqSampledCycle = t.cycle;
        Telemetry.Event("lane_eq", [
            ["team", team],
            ["lane", lane],
            ["kind", kind],
            ["eq", eqPos],
            ["imb", imbalance],
            ["feq", forecastEq],
            ["a", ally.count],
            ["e", enemy.count],
        ]);
    }

    for (const c of enemy.units) {
        const target = c.GetAttackTarget();
        if (target !== null && target !== undefined && target.GetTeam() === team && target.IsHero()) t.aggro[target.GetPlayerID()] = now;
    }
    if (observer !== undefined) countDenies(t, observer, lane, scan.enemy[lane]);

    const snapshot: LaneSnapshot = {
        team,
        lane,
        kind,
        time: now,
        ourFront,
        enemyFront,
        meetAmount,
        ourTowerAmount,
        theirTowerAmount,
        eqPos,
        frontLoc,
        ally,
        enemy,
        cycleSec,
        nextWaveIn: timing().WaveCycle - cycleSec,
        enemyArrivalSec: median(t.arrivals),
        enemyWaveSizes: [...t.waveSizes],
        allies: heroesFor(team, lane, frontLoc),
        desiredEq: DesiredEq(kind, preRuneFn(team, lane)),
        enemyDeniesPerCycle: [...t.deniesPerCycle],
        lastAllyAggroAt: copyRecord(t.aggro),
        eqHistory: [...t.eqHistory],
        allyPower,
        enemyPower,
        imbalance,
        forecastEq,
    };
    snapshots[key] = snapshot;
    for (const fn of refreshCallbacks) fn(snapshot);
    return snapshot;
}

/** `observer` is the bot driving this refresh; it supplies the visible enemy heroes for deny counting. */
export function Get(team: number, lane: Lane, observer?: Unit): LaneSnapshot | undefined {
    if (!LaneConfig.IsActive()) return undefined;
    const key = `${team}:${lane}`;
    const cached = snapshots[key];
    if (cached !== undefined && DotaTime() - cached.time < timing().SnapshotRefresh) return cached;
    return refresh(team, lane, key, observer);
}

export function ForBot(bot: Unit): LaneSnapshot | undefined {
    if (!LaneConfig.IsActive()) return undefined;
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Mid && lane !== Lane.Bot) return undefined;
    return Get(bot.GetTeam(), lane, bot);
}

// A handle cached up to SnapshotRefresh ago can be a removed entity by now (a killed or expired illusion), and any
// method call on it raises "Invalid object" (console.9055828679: GetAttackTarget in countDenies at 10:44).
function holdsRemovedUnit(list: LaneEnemy[]): boolean {
    for (const e of list) if (e.unit !== undefined && e.unit.IsNull()) return true;
    return false;
}

export function Enemies(bot: Unit, _lane: Lane): LaneEnemy[] {
    if (!LaneConfig.IsActive()) return [];
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const cached = enemyCache[pid];
    if (cached !== undefined && now - cached.time < timing().SnapshotRefresh && !holdsRemovedUnit(cached.list)) return cached.list;

    const list: LaneEnemy[] = [];
    const seen: Record<number, boolean> = {};
    for (const u of GetUnitList(UnitType.EnemyHeroes)) {
        if (!u.CanBeSeen() || !u.IsAlive() || u.IsIllusion()) continue;
        const epid = u.GetPlayerID();
        seen[epid] = true;
        list.push({ unit: u, pid: epid, visible: true, location: u.GetLocation(), timeSinceSeen: 0, position: LaneConfig.PositionOf(u) });
    }
    for (const epid of GetTeamPlayers(enemyTeamOf(bot.GetTeam()))) {
        if (seen[epid] === true || !IsHeroAlive(epid)) continue;
        const info = GetHeroLastSeenInfo(epid)[0];
        if (info === undefined) continue;
        list.push({ pid: epid, visible: false, location: info.location, timeSinceSeen: info.time_since_seen });
    }
    enemyCache[pid] = { time: now, list };
    return list;
}

export function ScoreFor(bot: Unit, s: LaneSnapshot): ObserverView {
    const pid = bot.GetPlayerID();
    const key = `${pid}:${s.lane}`;
    const cached = viewCache[key];
    if (cached !== undefined && cached.time === s.time) return cached.view;

    let near = 0;
    const radius = radii().Exposure;
    const seenWithin = timing().ExposureSeen;
    for (const e of Enemies(bot, s.lane)) {
        if (!e.visible && e.timeSinceSeen > seenWithin) continue;
        if (dist2D(e.location, s.frontLoc) <= radius) near++;
    }
    const exposure = math.min(1, near / LaneConfig.Settings().Thresholds.ExposureEnemies);
    const foresight = ForesightOf(LaneConfig.SkillOf(bot));
    const view: ObserverView = {
        exposure,
        laneScore: LaneScore(s.desiredEq, s.eqPos, exposure),
        foresight,
        forecastScore: ForecastScore(s.desiredEq, s.eqPos, s.forecastEq, foresight, exposure),
    };
    viewCache[key] = { time: s.time, view };
    return view;
}

export function Describe(s: LaneSnapshot, v: ObserverView): string {
    return string.format("eq=%.2f want=%.2f score=%.2f a%d/e%d next=%.0fs", s.eqPos, s.desiredEq, v.laneScore, s.ally.count, s.enemy.count, s.nextWaveIn);
}
