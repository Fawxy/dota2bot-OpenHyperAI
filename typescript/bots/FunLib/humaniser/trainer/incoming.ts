/**
 * Port of OHA's incoming-damage estimate (jmz_func GetCreepAttackProjectileWillRealDamage and
 * GetCreepAttackActivityWillRealDamage), returning timed hits instead of a total so the predictor can build an HP curve.
 */
import { DamageType, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import { CreepKind, T, TUnit } from "bots/FunLib/humaniser/trainer/api";

export interface Hit {
    at: number;
    damage: number;
}

const CACHE_SECONDS = 0.25;
const ATTACK_ACTIVITY = 1503;
const SIEGE_POINT = 0.292;
const SIEGE_SWING = 0.699;
const TOWER_PROJECTILE_FACTOR = 0.93;
const NEARBY_RADIUS = 1600;

const LIST_TYPES = [
    UnitType.AlliedCreeps,
    UnitType.EnemyCreeps,
    UnitType.AlliedHeroes,
    UnitType.EnemyHeroes,
    UnitType.AlliedBuildings,
    UnitType.EnemyBuildings,
];

const cache: { [team: number]: { at: number; units: Unit[] } } = {};

function unitsForTeam(): Unit[] {
    const team = GetTeam();
    const now = GameTime();
    const entry = cache[team];
    if (entry !== undefined && now - entry.at < CACHE_SECONDS && now >= entry.at) return entry.units;
    const units: Unit[] = [];
    for (const listType of LIST_TYPES) {
        for (const u of GetUnitList(listType)) {
            if (u !== null && u !== undefined) units.push(u);
        }
    }
    cache[team] = { at: now, units };
    return units;
}

/** Allied and enemy creeps, heroes and towers within radius of loc. Lists are cached for 0.25 s per team. */
export function NearbyUnits(loc: Vector, radius: number): Unit[] {
    const result: Unit[] = [];
    for (const u of unitsForTeam()) {
        if (u.IsAlive() && GetUnitToLocationDistance(u, loc) <= radius) result.push(u);
    }
    return result;
}

/** Visible heroes of both teams, from the same cached lists. */
export function Heroes(): Unit[] {
    const result: Unit[] = [];
    for (const u of unitsForTeam()) {
        if (u.IsHero() && !u.IsIllusion()) result.push(u);
    }
    return result;
}

function kindOf(u: TUnit): CreepKind {
    if (u.IsTower()) return "ranged";
    if (u.IsHero()) {
        return u.GetAttackRange() > 320 || u.GetUnitName() === "npc_dota_hero_templar_assassin" ? "ranged" : "melee";
    }
    return CreepKind(u);
}

function projectileSpeed(u: TUnit): number {
    const speed = u.GetAttackProjectileSpeed();
    return u.IsTower() ? speed * TOWER_PROJECTILE_FACTOR : speed;
}

function pushRepeating(hits: Hit[], first: number, period: number, damage: number, repeat: boolean, horizon: number) {
    let at = first;
    while (at <= horizon) {
        hits.push({ at: math.max(at, 0), damage });
        if (!repeat || period <= 0) break;
        at += period;
    }
}

function attackerHit(hits: Hit[], attacker: TUnit, creep: TUnit, horizon: number) {
    const kind = kindOf(attacker);
    const point = attacker.GetAttackPoint();
    const period = attacker.GetSecondsPerAttack();
    const cycle = attacker.GetAnimCycle();
    const dist = GetUnitToUnitDistance(attacker, creep);
    const damage = creep.GetActualIncomingDamage(attacker.GetAttackDamage(), DamageType.Physical);
    const travel = kind === "ranged" || kind === "siege" ? math.max(dist - 22, 0) / attacker.GetAttackProjectileSpeed() : 0;
    const repeat = !attacker.IsHero();

    let first: number;
    if (kind === "siege" && attacker.GetAnimActivity() === ATTACK_ACTIVITY && cycle < SIEGE_POINT) {
        first = ((SIEGE_POINT - cycle) * SIEGE_SWING) / SIEGE_POINT + travel;
    } else if (attacker.GetAnimActivity() === ATTACK_ACTIVITY && cycle < point) {
        first = (point - cycle) * period + travel;
    } else {
        const swingStart = math.max(attacker.GetLastAttackTime() + period - GameTime(), 0);
        first = swingStart + point * period + travel;
    }
    pushRepeating(hits, first, period, damage, repeat, horizon);
}

/** Damage other units will deal to creep within horizon seconds, excluding the subject's own attacks. */
export function Hits(creep: Unit, subject: Unit, horizon: number): Hit[] {
    const hits: Hit[] = [];
    const target = T(creep);
    const loc = creep.GetLocation();

    for (const p of target.GetIncomingTrackingProjectiles()) {
        if (!p.is_attack || p.caster === undefined || p.caster === null || p.caster === subject) continue;
        const caster = T(p.caster);
        const travelTime = GetUnitToLocationDistance(creep, p.location) / projectileSpeed(caster);
        if (travelTime > horizon) continue;
        hits.push({
            at: travelTime,
            damage: creep.GetActualIncomingDamage(caster.GetAttackDamage(), DamageType.Physical),
        });
    }

    for (const u of NearbyUnits(loc, NEARBY_RADIUS)) {
        if (u === subject || u === creep || u.GetAttackTarget() !== creep) continue;
        attackerHit(hits, T(u), target, horizon);
    }

    table.sort(hits, (a, b) => a.at < b.at);
    return hits;
}
