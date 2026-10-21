/**
 * The one harass tool (task 07, Phase E) for every bot whose laning Think() OHA owns, by task 04 (allies of
 * humans, `etiquette`) or task 07. A timed punish of enemy last-hit attempts runs first; when nothing fires, the
 * idle poke (a port of 04's HarassThink with its gates as parameters) runs. A low-skill bot's random-time
 * harass is that same idle poke on a random interval.
 */
import { DamageType, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as AllyLastHit from "bots/FunLib/humaniser/ally_last_hit";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as HDebug from "bots/FunLib/humaniser/debug";

export interface HarassGates {
    etiquette: boolean;
    interval: number;
    window: number;
    idleExtraRange: number;
    minHP: number;
    towerAvoidRange: number;
    needProtectedHuman: boolean;
    needStronger: boolean;
}

interface IdleState {
    target?: Unit;
    startAt: number;
    lastAt: number;
}

interface Attempt {
    creep: Unit;
    fireAt?: number;
}

interface Dance {
    until: number;
    to: Vector;
}

// 04 starts its harass clock this far in the past so the first poke can fire at once.
const IDLE_START = -90;
const TOWER_SCAN = 1600;

let idle: Record<number, IdleState> = {};
let randomInterval: Record<number, { interval: number; forLastAt: number }> = {};
let attempts: Record<number, LuaTable<Unit, Attempt>> = {};
let dances: Record<number, Dance> = {};
const spellHarass: Record<string, (this: void, bot: Unit, enemy: Unit) => boolean> = {};

export function ResetCache(): void {
    idle = {};
    randomInterval = {};
    attempts = {};
    dances = {};
}

function settings(): LaneConfig.LaneSettings {
    return LaneConfig.Settings();
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function clamp01(v: number): number {
    return v < 0 ? 0 : v > 1 ? 1 : v;
}

function toward(from: Vector, to: Vector, len: number): Vector {
    const d = dist2D(from, to);
    if (d < 1e-6) return from;
    return Vector(from.x + ((to.x - from.x) / d) * len, from.y + ((to.y - from.y) / d) * len, from.z);
}

function hpOf(unit: Unit): number {
    const h = LaneConfig.Helpers().GetHP;
    if (h !== undefined) return h(unit);
    const max = unit.GetMaxHealth();
    return max > 0 ? unit.GetHealth() / max : 0;
}

function isValidHero(unit: Unit | undefined): unit is Unit {
    if (unit === undefined) return false;
    const h = LaneConfig.Helpers().IsValidHero;
    return h !== undefined ? h(unit) : unit.IsAlive() && unit.CanBeSeen();
}

function isSuspiciousIllusion(unit: Unit): boolean {
    const h = LaneConfig.Helpers().IsSuspiciousIllusion;
    return h !== undefined && h(unit);
}

function isValidBuilding(unit: Unit): boolean {
    const h = LaneConfig.Helpers().IsValidBuilding;
    return h !== undefined ? h(unit) : unit.IsAlive();
}

function weAreStronger(bot: Unit): boolean {
    const h = LaneConfig.Helpers().WeAreStronger;
    return h !== undefined && h(bot, settings().Radii.Stronger);
}

function weakKeys<K extends AnyNotNil, V>(): LuaTable<K, V> {
    return setmetatable(new LuaTable<K, V>(), { __mode: "k" });
}

function attemptsOf(pid: number): LuaTable<Unit, Attempt> {
    let t = attempts[pid];
    if (t === undefined) {
        t = weakKeys<Unit, Attempt>();
        attempts[pid] = t;
    }
    return t;
}

function towerWithin(towers: Unit[], range: number, a: Unit, b: Unit): boolean {
    for (const tower of towers) {
        if (isValidBuilding(tower) && (GetUnitToUnitDistance(tower, a) < range || GetUnitToUnitDistance(tower, b) < range)) return true;
    }
    return false;
}

function log(bot: Unit, kind: "punish" | "poke", etiquette: boolean): void {
    HDebug.Log("lane", `harass pid=${bot.GetPlayerID()} kind=${kind} etiquette=${tostring(etiquette)}`);
}

export function GatesFor(bot: Unit, etiquette: boolean): HarassGates {
    if (etiquette) {
        const s = AllyLastHit.Settings();
        return {
            etiquette,
            interval: s.HarassInterval,
            window: s.HarassWindow,
            idleExtraRange: s.HarassExtraRange,
            minHP: s.HarassMinHP,
            towerAvoidRange: s.TowerAvoidRange,
            needProtectedHuman: true,
            needStronger: true,
        };
    }
    const h = settings().HarassIdle;
    const pid = bot.GetPlayerID();
    let interval = math.huge;
    if (LaneConfig.SkillOf(bot) < settings().Gates.RandomHarass) {
        let state = idle[pid];
        // The random poke waits one full interval before its first hit, unlike 04's immediate first poke.
        if (state === undefined) {
            state = { startAt: IDLE_START, lastAt: GameTime() };
            idle[pid] = state;
        }
        let r = randomInterval[pid];
        // PF10: this is the frame's last draw, after the punish draws (capitalise, react delay, low-skill extra).
        if (r === undefined || r.forLastAt !== state.lastAt) {
            const t = settings().Timing;
            r = { interval: RandomFloat(t.RandomHarassMin, t.RandomHarassMax), forLastAt: state.lastAt };
            randomInterval[pid] = r;
        }
        interval = r.interval;
    }
    return {
        etiquette,
        interval,
        window: h.IdleWindow,
        idleExtraRange: h.IdleExtraRange,
        minHP: h.IdleMinHP,
        towerAvoidRange: h.TowerAvoidRange,
        needProtectedHuman: false,
        needStronger: true,
    };
}

export function IsLastHitAttempt(enemy: Unit, ourCreeps: Unit[]): Unit | undefined {
    const h = LaneConfig.Helpers();
    const dmg = enemy.GetAttackDamage();
    const target = enemy.GetAttackTarget();
    if (target !== null && target !== undefined && h.WillKillTarget !== undefined && h.GetAttackProDelayTime !== undefined) {
        for (const creep of ourCreeps ?? []) {
            if (creep === target && creep.IsAlive() && h.WillKillTarget(creep, dmg, DamageType.Physical, h.GetAttackProDelayTime(enemy, creep))) return creep;
        }
    }
    const cfg = settings();
    const here = enemy.GetLocation();
    const ahead = enemy.GetExtrapolatedLocation(cfg.Radii.ApproachExtrapolate);
    let best: Unit | undefined;
    let bestDist = math.huge;
    for (const creep of ourCreeps ?? []) {
        if (!creep.IsAlive() || creep.GetHealth() > dmg) continue;
        const loc = creep.GetLocation();
        const d = dist2D(here, loc);
        if (dist2D(ahead, loc) <= d - cfg.Thresholds.ApproachEpsilon && d < bestDist) {
            best = creep;
            bestDist = d;
        }
    }
    return best;
}

export function TowerForbids(botLevel: number, nearEnemyTower: boolean, targetHP: number): boolean {
    const t = settings().Thresholds;
    return botLevel < t.HarassTowerLevel && nearEnemyTower && targetHP >= t.HarassTowerTargetHP;
}

export function AggroDance(enemyCreepsWithin500: number): boolean {
    return enemyCreepsWithin500 >= settings().Thresholds.AggroDanceCreeps;
}

export function Capitalises(skill: number): boolean {
    return LaneConfig.Roll(LaneConfig.Curve("HarassCapitalise", skill));
}

/** A step of AggroDanceStep back along the bot's lane toward its own base. */
function stepBack(bot: Unit): Vector {
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    const here = bot.GetLocation();
    const a = Camps.ToTeamAmount(team, GetAmountAlongLane(lane, here).amount);
    const behind = GetLocationAlongLane(lane, clamp01(Camps.ToAbsAmount(team, a - settings().Camps.LaneSampleStep)));
    return toward(here, behind, settings().Radii.AggroDanceStep);
}

export function StandPoint(bot: Unit, enemy: Unit, ourCreeps: Unit[]): Vector | undefined {
    const cfg = settings();
    if (LaneConfig.SkillOf(bot) < cfg.Gates.HarassPosition) return undefined;
    // Skill >= HarassPosition never takes GatesFor's random-interval draw.
    const g = GatesFor(bot, AllyLastHit.OwnsLaning(bot));
    if (hpOf(bot) < g.minHP || (g.needStronger && !weAreStronger(bot))) return undefined;
    const enemyLoc = enemy.GetLocation();
    let creep: Unit | undefined;
    for (const c of ourCreeps ?? []) {
        if (!c.IsAlive() || dist2D(c.GetLocation(), enemyLoc) > cfg.Radii.LowHpCreep) continue;
        if (creep === undefined || c.GetHealth() < creep.GetHealth()) creep = c;
    }
    if (creep === undefined) return undefined;
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    const loc = creep.GetLocation();
    const a = Camps.ToTeamAmount(team, GetAmountAlongLane(lane, loc).amount);
    const behind = GetLocationAlongLane(lane, clamp01(Camps.ToAbsAmount(team, a - cfg.Camps.LaneSampleStep)));
    const point = toward(loc, behind, math.max(0, bot.GetAttackRange() - cfg.Radii.HarassStandBack));
    for (const tower of bot.GetNearbyTowers(TOWER_SCAN, true)) {
        if (isValidBuilding(tower) && dist2D(tower.GetLocation(), point) <= cfg.Thresholds.EnemyTowerRange) return undefined;
    }
    return point;
}

/** 04's HarassThink with its gates as parameters; keeps 04's statement order and engine call order. */
export function IdlePoke(bot: Unit, enemies: Unit[], g: HarassGates, enemyCreeps?: Unit[]): boolean {
    const pid = bot.GetPlayerID();
    let st = idle[pid];
    if (st === undefined) {
        st = { startAt: IDLE_START, lastAt: IDLE_START };
        idle[pid] = st;
    }
    const now = GameTime();
    if (isValidHero(st.target) && now - st.startAt < g.window && bot.GetLastAttackTime() < st.startAt) {
        bot.Action_AttackUnit(st.target, true);
        return true;
    }
    st.target = undefined;
    if (now - st.lastAt < g.interval || hpOf(bot) < g.minHP) return false;
    if (g.needProtectedHuman) {
        const [human] = AllyLastHit.GetProtectedHuman(bot, bot.GetLocation());
        if (human === undefined) return false;
    }
    if (g.needStronger && !weAreStronger(bot)) return false;

    const towers = bot.GetNearbyTowers(TOWER_SCAN, true);
    let target: Unit | undefined;
    let targetDist = bot.GetAttackRange() + g.idleExtraRange;
    for (const enemy of enemies ?? []) {
        if (isValidHero(enemy) && !isSuspiciousIllusion(enemy) && GetUnitToUnitDistance(bot, enemy) <= targetDist) {
            if (!towerWithin(towers, g.towerAvoidRange, bot, enemy)) {
                target = enemy;
                targetDist = GetUnitToUnitDistance(bot, enemy);
            }
        }
    }
    if (target === undefined) return false;

    st.target = target;
    st.startAt = now;
    st.lastAt = now;
    bot.Action_AttackUnit(target, true);
    // 04's poke (etiquette) keeps 04's behaviour exactly; only 07-only bots step back after a poke into a wave.
    if (!g.etiquette) maybeDance(bot, enemyCreeps ?? [], now);
    log(bot, "poke", g.etiquette);
    return true;
}

function noteIdleHit(pid: number, now: number): void {
    const st = idle[pid];
    if (st === undefined) idle[pid] = { startAt: IDLE_START, lastAt: now };
    else st.lastAt = now;
}

/** Manners at fire time; true when the punish may go ahead. */
function mannersAllow(bot: Unit, enemy: Unit, towers: Unit[], etiquette: boolean): boolean {
    const t = settings().Thresholds;
    const near = towerWithin(towers, t.EnemyTowerRange, bot, enemy);
    if (TowerForbids(bot.GetLevel(), near, hpOf(enemy))) return false;
    if (etiquette) {
        const g = GatesFor(bot, true);
        if (hpOf(bot) < g.minHP || !weAreStronger(bot) || towerWithin(towers, g.towerAvoidRange, bot, enemy)) return false;
    }
    return true;
}

function enemyCreepsNear(bot: Unit, enemyCreeps: Unit[]): number {
    const r = settings().Thresholds.AggroDanceRadius;
    const team = bot.GetTeam();
    let n = 0;
    for (const c of enemyCreeps ?? []) {
        if (c.IsAlive() && c.GetTeam() !== team && GetUnitToUnitDistance(bot, c) <= r) n++;
    }
    return n;
}

function maybeDance(bot: Unit, enemyCreeps: Unit[], now: number): void {
    if (AggroDance(enemyCreepsNear(bot, enemyCreeps))) {
        dances[bot.GetPlayerID()] = { until: now + settings().Timing.AggroDanceBack, to: stepBack(bot) };
    }
}

function fire(bot: Unit, enemy: Unit, enemyCreeps: Unit[], etiquette: boolean): void {
    const fn = spellHarass[bot.GetUnitName()];
    if (fn === undefined || !fn(bot, enemy)) bot.Action_AttackUnit(enemy, true);
    const now = GameTime();
    noteIdleHit(bot.GetPlayerID(), now);
    maybeDance(bot, enemyCreeps, now);
    log(bot, "punish", etiquette);
}

function punish(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], etiquette: boolean): boolean {
    const pid = bot.GetPlayerID();
    const now = GameTime();
    const dance = dances[pid];
    if (dance !== undefined) {
        if (now < dance.until) {
            bot.Action_MoveToLocation(dance.to);
            return true;
        }
        delete dances[pid];
    }
    const cfg = settings();
    const team = bot.GetTeam();
    const reach = bot.GetAttackRange() + cfg.Thresholds.HarassExtraRange;
    const mine = attemptsOf(pid);
    let towers: Unit[] | undefined;
    for (const enemy of enemies ?? []) {
        if (!isValidHero(enemy) || enemy.GetTeam() === team) continue;
        let a = mine.get(enemy);
        if (GetUnitToUnitDistance(bot, enemy) > reach) {
            // A punish whose moment passed while the enemy was out of range is dropped, not fired late.
            if (a !== undefined && a.fireAt !== undefined && now >= a.fireAt) a.fireAt = undefined;
            continue;
        }
        const creep = IsLastHitAttempt(enemy, allyCreeps);
        if (creep !== undefined && (a === undefined || a.creep !== creep)) {
            const skill = LaneConfig.SkillOf(bot);
            a = { creep };
            mine.set(enemy, a);
            if (Capitalises(skill)) {
                let delay = Profile.SampleDelay(bot, "react");
                if (skill < cfg.Gates.RandomHarass) delay += RandomFloat(0, cfg.Timing.LowSkillHarassExtra);
                a.fireAt = now + delay;
            }
        }
        if (a === undefined || a.fireAt === undefined || now < a.fireAt) continue;
        a.fireAt = undefined;
        towers ??= bot.GetNearbyTowers(TOWER_SCAN, true);
        if (!mannersAllow(bot, enemy, towers, etiquette)) continue;
        fire(bot, enemy, enemyCreeps, etiquette);
        return true;
    }
    return false;
}

export function Think(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], etiquette: boolean): boolean {
    if (!LaneConfig.IsOn("Harass")) return false;
    const s = LaneState.ForBot(bot);
    if (s !== undefined && LanePlan.View(bot, s).handsOff) return false;
    if (punish(bot, allyCreeps, enemyCreeps, enemies, etiquette)) return true;
    return IdlePoke(bot, enemies, GatesFor(bot, etiquette), enemyCreeps);
}

export function RegisterSpellHarass(heroName: string, fn: (this: void, bot: Unit, enemy: Unit) => boolean): void {
    spellHarass[heroName] = fn;
}
