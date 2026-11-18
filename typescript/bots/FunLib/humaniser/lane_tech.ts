/** The creep an idle shove hits (states/idle_swing): the weakest enemy lane creep outside their tower's reach. */
import { Team, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";

export const TOWER_IDS: Tower[] = [
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
    Tower.Base1,
    Tower.Base2,
];

let towerCache: Record<number, { time: number; list: Unit[] }> = {};

export function ResetCache(): void {
    towerCache = {};
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function enemyTowers(team: number): Unit[] {
    const now = DotaTime();
    const cached = towerCache[team];
    if (cached !== undefined && cached.time === now) return cached.list;
    const list: Unit[] = [];
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    for (const id of TOWER_IDS) {
        const tower = GetTower(enemy, id);
        if (tower !== null && tower !== undefined && tower.IsAlive()) list.push(tower);
    }
    towerCache[team] = { time: now, list };
    return list;
}

function underEnemyTower(team: number, loc: Vector): boolean {
    const range = LaneConfig.TowerReach();
    for (const tower of enemyTowers(team)) if (dist2D(tower.GetLocation(), loc) <= range) return true;
    return false;
}

function isLaneCreep(unit: Unit | null | undefined): unit is Unit {
    return unit !== null && unit !== undefined && !unit.IsNull() && unit.IsAlive() && unit.CanBeSeen() && LaneState.IsLaneCreepName(unit.GetUnitName());
}

export function ShoveTarget(bot: Unit, enemyCreeps: Unit[]): Unit | undefined {
    const team = bot.GetTeam();
    let best: Unit | undefined;
    for (const c of enemyCreeps ?? []) {
        if (!isLaneCreep(c) || c.GetTeam() === team) continue;
        if (underEnemyTower(team, c.GetLocation())) continue;
        if (best === undefined || c.GetHealth() < best.GetHealth()) best = c;
    }
    return best;
}
