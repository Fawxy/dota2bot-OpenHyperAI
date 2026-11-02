/**
 * Lane read (slice lane-read): one reading per (team, lane) of what the lane holds now, for later lane decisions to read.
 * Facts only, no scores and no decisions. Amounts are in Radiant's direction (0 at Radiant's ancient) but each team's script
 * measures along its own lane path, so the two teams' amounts for one place differ (mid by about 0.16 in game lr1): compare
 * amounts only within one team's reading, and across teams by map position. It reads the calling script's team:
 * GetUnitList and GetTeamMember answer for that team only, so Read(team) must run from a script of that team.
 * Not gated by LaneConfig.IsActive (the old claims-based plan flags), so it outlives them; it imports nothing that logs.
 */
import { Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneGeom from "bots/FunLib/humaniser/lane_geom";

export const WAVE_CYCLE = 30;
const TEAM_SLOTS = 5;

export interface Creeps {
    count: number;
    hp: number;
    power: number;
    /** Amount of the creep furthest towards the enemy base, and its map position; undefined with no creep. */
    lead?: number;
    leadLoc?: Vector;
}

export interface EnemyRead {
    pid: number;
    visible: boolean;
    /** Seconds since seen (0 when visible). */
    seen: number;
    /** Distance to our wave front, from the last seen location when not visible. */
    dist: number;
    /** HP share and level, only when visible. */
    hp?: number;
    lvl?: number;
}

export interface AggroRead {
    pid: number;
    /** Visible enemy lane creeps attacking this hero now. */
    now: number;
    /** Seconds since an enemy lane creep last attacked it; undefined if never this game. */
    since?: number;
}

/** One of our own lane creeps: kind m(elee), r(anged), s(iege) or f(lagbearer), absolute amount and HP. */
export interface CensusCreep {
    kind: string;
    amount: number;
    hp: number;
}

export interface LaneRead {
    team: number;
    lane: Lane;
    /** Creep advantage 0..2 over the creeps near our front (visible ones only): Imbalance + 1, HP-weighted. */
    adv: number;
    eq: number;
    near: Creeps;
    enemyNear: Creeps;
    ourFront: number;
    enemyFront: number;
    ourTower: number;
    theirTower: number;
    cycleSec: number;
    nextWaveIn: number;
    enemies: EnemyRead[];
    dead: number;
    aggro: AggroRead[];
    /** Our own creeps in the whole lane, from the full list (a team always sees its own): the other team's ground truth. */
    census: Creeps;
    /** Our own creeps near the enemy's front: the enemy reading's `enemyNear` without fog, for its self-check. */
    censusAtEnemy: Creeps;
    /** Every own creep in the lane, by amount: the start state a lane forecast restarts from. */
    creeps: CensusCreep[];
    /** Our nearest alive tower on the lane: tier 1-3 and HP, tier 0 and no HP when all three are down. */
    towerTier: number;
    towerHp?: number;
    frontLoc: Vector;
}

interface TeamMemory {
    enemyPids: Record<number, boolean>;
    aggroAt: Record<number, number>;
}

const LANES: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];
const TOWER_IDS: Record<number, number[]> = {
    [Lane.Top]: [Tower.Top1, Tower.Top2, Tower.Top3],
    [Lane.Mid]: [Tower.Mid1, Tower.Mid2, Tower.Mid3],
    [Lane.Bot]: [Tower.Bot1, Tower.Bot2, Tower.Bot3],
};

let memory: Record<number, TeamMemory> = {};
let towerAmounts: Record<string, number> = {};

export function Reset(): void {
    memory = {};
    towerAmounts = {};
}

function memoryFor(team: number): TeamMemory {
    let m = memory[team];
    if (m === undefined) {
        m = { enemyPids: {}, aggroAt: {} };
        memory[team] = m;
    }
    return m;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function absAmount(lane: Lane, loc: Vector): { amount: number; distance: number } {
    const r = GetAmountAlongLane(lane, loc);
    return { amount: Camps.ToTeamAmount(Team.Radiant, r.amount), distance: r.distance };
}

export function CreepWeight(name: string): number {
    const w = LaneConfig.Settings().ForecastModel.TypeWeight;
    if (string.find(name, "ranged", 1, true)[0] !== undefined) return w.ranged;
    if (string.find(name, "siege", 1, true)[0] !== undefined) return w.siege;
    return w.melee;
}

/** Imbalance + 1: 0 when the enemy has every creep, 1 even, 2 when we have every creep; PowerFloor damps small totals. */
export function Advantage(allyPower: number, enemyPower: number): number {
    return 1 + (allyPower - enemyPower) / (allyPower + enemyPower + LaneConfig.Settings().ForecastModel.PowerFloor);
}

/** The most-advanced amount of `team`'s creeps: Radiant pushes towards 1, Dire towards 0. */
export function Leads(team: number, a: number | undefined, b: number): number {
    if (a === undefined) return b;
    return team === Team.Radiant ? math.max(a, b) : math.min(a, b);
}

function emptyCreeps(): Creeps {
    return { count: 0, hp: 0, power: 0 };
}

function addCreep(c: Creeps, team: number, unit: Unit, amount: number, loc: Vector): void {
    const hp = unit.GetHealth();
    c.count++;
    c.hp += hp;
    c.power += hp * CreepWeight(unit.GetUnitName());
    const lead = Leads(team, c.lead, amount);
    if (lead !== c.lead) {
        c.lead = lead;
        c.leadLoc = loc;
    }
}

export function IsLaneCreepName(name: string): boolean {
    for (const part of ["creep_goodguys", "creep_badguys", "goodguys_siege", "badguys_siege"])
        if (string.find(name, part, 1, true)[0] !== undefined) return true;
    return false;
}

interface Placed {
    unit: Unit;
    loc: Vector;
    amount: number;
}

function byLane(units: Unit[], visibleOnly: boolean): Record<number, Placed[]> {
    const out: Record<number, Placed[]> = { [Lane.Top]: [], [Lane.Mid]: [], [Lane.Bot]: [] };
    const assign = LaneConfig.Settings().Radii.LaneAssign;
    for (const unit of units) {
        if (visibleOnly && !unit.CanBeSeen()) continue;
        if (!unit.IsAlive() || !IsLaneCreepName(unit.GetUnitName())) continue;
        const loc = unit.GetLocation();
        let best: Lane | undefined;
        let bestDist = math.huge;
        let bestAmount = 0;
        for (const lane of LANES) {
            const r = absAmount(lane, loc);
            if (r.distance < bestDist) {
                bestDist = r.distance;
                best = lane;
                bestAmount = r.amount;
            }
        }
        if (best !== undefined && bestDist <= assign) out[best].push({ unit, loc, amount: bestAmount });
    }
    return out;
}

/** Absolute amount of `owner`'s nearest alive tower on `lane`; its base end (0 or 1) when all three are down. */
function towerAmount(team: number, owner: number, lane: Lane): number {
    for (const id of TOWER_IDS[lane]) {
        const tower = GetTower(owner, id);
        if (tower === null || tower === undefined || !tower.IsAlive()) continue;
        const key = `${team}:${owner}:${id}`;
        let amount = towerAmounts[key];
        if (amount === undefined) {
            amount = absAmount(lane, tower.GetLocation()).amount;
            towerAmounts[key] = amount;
        }
        return amount;
    }
    return owner === Team.Radiant ? 0 : 1;
}

function ownTower(team: number, lane: Lane): { tier: number; hp?: number } {
    const ids = TOWER_IDS[lane];
    for (let i = 0; i < ids.length; i++) {
        const tower = GetTower(team, ids[i]);
        if (tower !== null && tower !== undefined && tower.IsAlive()) return { tier: i + 1, hp: tower.GetHealth() };
    }
    return { tier: 0 };
}

export function CreepKind(name: string): string {
    if (string.find(name, "siege", 1, true)[0] !== undefined) return "s";
    if (string.find(name, "ranged", 1, true)[0] !== undefined) return "r";
    if (string.find(name, "flag", 1, true)[0] !== undefined) return "f";
    return "m";
}

function readEnemies(team: number, m: TeamMemory, front: Vector): { enemies: EnemyRead[]; dead: number } {
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    // GetTeamPlayers is empty for a bot-only team in practice mode, so ids seen in the unit list are remembered too.
    for (const pid of GetTeamPlayers(enemyTeam)) m.enemyPids[pid] = true;
    const enemies: EnemyRead[] = [];
    const seen: Record<number, boolean> = {};
    for (const u of GetUnitList(UnitType.EnemyHeroes)) {
        if (!u.CanBeSeen() || !u.IsAlive() || u.IsIllusion()) continue;
        const pid = u.GetPlayerID();
        m.enemyPids[pid] = true;
        seen[pid] = true;
        const maxHP = u.GetMaxHealth();
        enemies.push({ pid, visible: true, seen: 0, dist: dist2D(u.GetLocation(), front), hp: maxHP > 0 ? u.GetHealth() / maxHP : 0, lvl: u.GetLevel() });
    }
    let dead = 0;
    for (const [pid] of pairs(m.enemyPids)) {
        const id = pid as number;
        if (seen[id] === true) continue;
        if (!IsHeroAlive(id)) {
            dead++;
            continue;
        }
        const info = GetHeroLastSeenInfo(id)[0];
        if (info === undefined) continue;
        enemies.push({ pid: id, visible: false, seen: info.time_since_seen, dist: dist2D(info.location, front) });
    }
    return { enemies, dead };
}

function readAggro(lane: Lane, m: TeamMemory, enemyCreeps: Placed[], front: Vector, now: number): AggroRead[] {
    const near = LaneConfig.Settings().Radii.AllyNearFront;
    const result: AggroRead[] = [];
    for (let i = 1; i <= TEAM_SLOTS; i++) {
        const hero = GetTeamMember(i);
        if (hero === null || hero === undefined || hero.IsIllusion() || !hero.IsAlive()) continue;
        if (hero.GetAssignedLane() !== lane && GetUnitToLocationDistance(hero, front) > near) continue;
        let n = 0;
        for (const c of enemyCreeps) if (c.unit.GetAttackTarget() === hero) n++;
        const pid = hero.GetPlayerID();
        if (n > 0) m.aggroAt[pid] = now;
        const at = m.aggroAt[pid];
        result.push({ pid, now: n, since: at !== undefined ? now - at : undefined });
    }
    return result;
}

/** One reading per lane for `team`, which must be the calling script's team. */
export function Read(team: number, now: number): LaneRead[] {
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const m = memoryFor(team);
    const own = byLane(GetUnitList(UnitType.AlliedCreeps), false);
    const foes = byLane(GetUnitList(UnitType.EnemyCreeps), true);
    const radius = LaneConfig.Settings().Radii.LaneCreep;
    const reads: LaneRead[] = [];
    for (const lane of LANES) {
        const frontLoc = GetLaneFrontLocation(team, lane, 0);
        const enemyFrontLoc = GetLaneFrontLocation(enemyTeam, lane, 0);
        const ourFront = absAmount(lane, frontLoc).amount;
        const enemyFront = absAmount(lane, enemyFrontLoc).amount;
        const ourTower = towerAmount(team, team, lane);
        const theirTower = towerAmount(team, enemyTeam, lane);
        const meet = LaneGeom.MeetAmount(ourFront, enemyFront, ourTower, theirTower);
        const census = emptyCreeps();
        const near = emptyCreeps();
        const enemyNear = emptyCreeps();
        const censusAtEnemy = emptyCreeps();
        const creeps: CensusCreep[] = [];
        for (const c of own[lane]) {
            creeps.push({ kind: CreepKind(c.unit.GetUnitName()), amount: c.amount, hp: c.unit.GetHealth() });
            addCreep(census, team, c.unit, c.amount, c.loc);
            if (dist2D(c.loc, frontLoc) <= radius) addCreep(near, team, c.unit, c.amount, c.loc);
            if (dist2D(c.loc, enemyFrontLoc) <= radius) addCreep(censusAtEnemy, team, c.unit, c.amount, c.loc);
        }
        for (const c of foes[lane]) if (dist2D(c.loc, frontLoc) <= radius) addCreep(enemyNear, enemyTeam, c.unit, c.amount, c.loc);
        const { enemies, dead } = readEnemies(team, m, frontLoc);
        creeps.sort((a, b) => a.amount - b.amount);
        const tower = ownTower(team, lane);
        const cycleSec = now % WAVE_CYCLE;
        reads.push({
            team,
            lane,
            adv: Advantage(near.power, enemyNear.power),
            eq: LaneGeom.EqPos(meet, ourTower, theirTower),
            near,
            enemyNear,
            ourFront,
            enemyFront,
            ourTower,
            theirTower,
            cycleSec,
            nextWaveIn: WAVE_CYCLE - cycleSec,
            enemies,
            dead,
            aggro: readAggro(lane, m, foes[lane], frontLoc, now),
            census,
            censusAtEnemy,
            creeps,
            towerTier: tower.tier,
            towerHp: tower.hp,
            frontLoc,
        });
    }
    return reads;
}

/**
 * The `ee` field of ev=lane_read, parsed by hlog query `@lane_read_check`: per enemy `pid:v:dist:hp%:lvl` when visible,
 * `pid:secs_since_seen:dist` when not, joined by `;`.
 */
export function FormatEnemies(enemies: EnemyRead[]): string {
    const out: string[] = [];
    for (const e of enemies) {
        const head = `${e.pid}:${e.visible ? "v" : math.floor(e.seen)}:${math.floor(e.dist)}`;
        out.push(e.visible ? `${head}:${math.floor((e.hp ?? 0) * 100 + 0.5)}:${e.lvl}` : head);
    }
    return out.join(";");
}

/** The `ag` field of ev=lane_read: per allied hero `pid:creeps_on_it_now:secs_since_last` (-1 never), joined by `;`. */
export function FormatAggro(aggro: AggroRead[]): string {
    const out: string[] = [];
    for (const a of aggro) out.push(`${a.pid}:${a.now}:${a.since === undefined ? "-1" : string.format("%.1f", math.floor(a.since * 10) / 10)}`);
    return out.join(";");
}

/** The `cc` field of ev=lane_read: per own creep `kind:amount_in_thousandths:hp`, by amount, joined by `;`. */
export function FormatCreeps(creeps: CensusCreep[]): string {
    const out: string[] = [];
    for (const c of creeps) out.push(`${c.kind}:${math.floor(c.amount * 1000 + 0.5)}:${math.floor(c.hp + 0.5)}`);
    return out.join(";");
}
