/**
 * Kill check (task 11): whether our laners' combined burst can kill a lane enemy. Evaluate() holds the rules over
 * plain inputs; Check gathers them from the units, the cooldown memory and the lane counts, cached per
 * (bot, target) for KillCheckEvery with one burst-error roll per fresh check.
 */
import { DamageType, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as CooldownMemory from "bots/FunLib/humaniser/cooldown_memory";
import * as CastWatch from "bots/FunLib/humaniser/cast_watch";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import * as FightRead from "bots/FunLib/humaniser/fight_read";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";

export interface KillInputs {
    burst: number;
    hp: number;
    regen: number;
    escapeReady: boolean;
    towerInRange: boolean;
    enemiesNear: number;
    alliesNear: number;
    skill: number;
    errRoll: number;
    // The bot's HP fraction and the enemies counted within COUNTER_RANGE of it: with two or more of them and the bot
    // under COUNTER_HP the enemy side could kill it first.
    botHP?: number;
    enemiesNearBot?: number;
    // Damage the bot takes over SurviveWindow (creeps it aggroes, a covering tower, enemy heroes) against its HP.
    incoming?: number;
    botHealth?: number;
    botMaxHealth?: number;
    // The margin the burst must reach (1 unless a solo core or a missing enemy asks for more).
    minMargin?: number;
}

export type FailReason = "illusion" | "unkillable" | "magic_immune" | "escape" | "tower" | "outnumbered" | "counter" | "burst" | "survive";

export interface KillResult {
    pass: boolean;
    margin: number;
    overwhelming: boolean;
    reason?: FailReason;
}

const BURST_RANGE = 1200;
const BURST_SECONDS = 5;
const TOWER_RANGE = 900;
const COUNTER_ENEMIES = 2;
const COUNTER_HP = 0.5;
const COUNTER_RANGE = 1200;
const TOWER_IDS = [
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
];

let cache: Record<number, Record<string, { at: number; result: KillResult }>> = {};

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function marginOf(i: KillInputs): number {
    const err = LaneFightConfig.Curve("BurstError", i.skill) * (2 * i.errRoll - 1);
    return (i.burst * (1 + err)) / math.max(1, i.hp + i.regen * BURST_SECONDS);
}

export function Evaluate(i: KillInputs): KillResult {
    const s = LaneFightConfig.Settings();
    const margin = marginOf(i);
    const overwhelming = margin >= s.Overwhelming;
    let reason: FailReason | undefined;
    if (margin < (i.minMargin ?? 1)) reason = "burst";
    else if (i.escapeReady) reason = "escape";
    else if (i.towerInRange && margin < s.TowerOverride) reason = "tower";
    else if (i.enemiesNear > i.alliesNear) reason = "outnumbered";
    else if (i.botHP !== undefined && (i.enemiesNearBot ?? 0) >= COUNTER_ENEMIES && i.botHP < COUNTER_HP) reason = "counter";
    else if (i.incoming !== undefined && i.botHealth !== undefined && i.botMaxHealth !== undefined && i.botHealth - i.incoming < s.SurviveHP * i.botMaxHealth)
        reason = "survive";
    return { pass: reason === undefined, margin, overwhelming, reason };
}

export function Passes(i: KillInputs): LuaMultiReturn<[boolean, number]> {
    const r = Evaluate(i);
    return $multi(r.pass, r.margin);
}

function located(u: Unit | undefined): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.CanBeSeen() && u.GetLocation() !== undefined;
}

function contributes(u: Unit | undefined, targetLoc: Vector): u is Unit {
    return located(u) && !u.IsIllusion() && dist2D(u.GetLocation(), targetLoc) <= BURST_RANGE;
}

/** Each unit's burst over the window, less the part of it spent walking into attack range. */
function burstOn(units: Unit[], target: Unit): number {
    let total = 0;
    const loc = target.GetLocation();
    for (const u of units) {
        const walk = math.max(0, dist2D(u.GetLocation(), loc) - u.GetAttackRange()) / math.max(1, u.GetCurrentMovementSpeed());
        total += (u.GetEstimatedDamageToTarget(true, target, BURST_SECONDS, DamageType.All) * math.max(0, BURST_SECONDS - walk)) / BURST_SECONDS;
    }
    return total;
}

/** Damage the bot takes over SurviveWindow for attacking `target`: the enemy creeps by it, a covering tower, enemy heroes near the bot. */
function incomingOn(bot: Unit, target: Unit, snap: LaneState.LaneSnapshot): number {
    const s = LaneFightConfig.Settings();
    const window = s.SurviveWindow;
    const loc = target.GetLocation();
    let total = 0;
    for (const c of snap.enemy.units) {
        if (!located(c) || dist2D(c.GetLocation(), loc) > s.CreepAggroRadius) continue;
        total += bot.GetActualIncomingDamage(c.GetAttackDamage() * c.GetAttackSpeed() * window, DamageType.Physical);
    }
    const tower = towerCovering(target.GetTeam(), loc);
    if (tower !== undefined) total += bot.GetActualIncomingDamage(tower.GetAttackDamage() * tower.GetAttackSpeed() * window, DamageType.Physical);
    const botLoc = bot.GetLocation();
    for (const e of LaneState.Enemies(bot, snap.lane)) {
        if (!e.visible || !located(e.unit) || dist2D(e.unit.GetLocation(), botLoc) > COUNTER_RANGE) continue;
        total += e.unit.GetEstimatedDamageToTarget(true, bot, window, DamageType.All);
    }
    return total;
}

function minMarginFor(bot: Unit, contributors: Unit[]): number {
    const s = LaneFightConfig.Settings();
    const pos = LaneConfig.PositionOf(bot);
    let min = contributors.length === 1 && contributors[0] === bot && (pos === 1 || pos === 2) ? s.CoreSoloMargin : 1;
    if (LaneHooks.EnemiesMissing(bot) > 0) min = math.max(min, s.MissingMargin);
    return min;
}

function escapeReady(botPid: number, target: Unit, now: number, skill: number): boolean {
    const targetPid = target.GetPlayerID();
    for (const a of CastWatch.AbilitiesOf(target)) {
        if (!a.learned || !AbilityClasses.IsEscape(a.name)) continue;
        const [ready] = CooldownMemory.ProbablyReady(botPid, targetPid, a.name, true, now, skill);
        if (ready) return true;
    }
    return false;
}

/** An alive tower of `enemyTeam` covers `loc` (the kill check's tower rule). */
export function TowerCovers(enemyTeam: number, loc: Vector): boolean {
    return towerInRange(enemyTeam, loc);
}

function towerCovering(enemyTeam: number, loc: Vector): Unit | undefined {
    for (const id of TOWER_IDS) {
        const tower = GetTower(enemyTeam, id);
        if (tower === null || tower === undefined || !tower.IsAlive()) continue;
        if (dist2D(loc, tower.GetLocation()) <= TOWER_RANGE) return tower;
    }
    return undefined;
}

function towerInRange(enemyTeam: number, loc: Vector): boolean {
    return towerCovering(enemyTeam, loc) !== undefined;
}

function hpFraction(u: Unit): number {
    const max = u.GetMaxHealth();
    return max > 0 ? u.GetHealth() / max : 0;
}

function skipReason(bot: Unit, target: Unit): FailReason | undefined {
    const h = LaneConfig.Helpers();
    if (target.IsIllusion() || (h.IsSuspiciousIllusion !== undefined && h.IsSuspiciousIllusion(target))) return "illusion";
    if (h.CannotBeKilled !== undefined && h.CannotBeKilled(bot, target)) return "unkillable";
    if (target.IsMagicImmune !== undefined && target.IsMagicImmune()) return "magic_immune";
    return undefined;
}

function compute(bot: Unit, contributors: Unit[], target: Unit, snap: LaneState.LaneSnapshot, now: number): KillResult {
    const skip = skipReason(bot, target);
    if (skip !== undefined) return { pass: false, margin: 0, overwhelming: false, reason: skip };
    const pid = bot.GetPlayerID();
    const skill = Profile.Get(bot).skill;
    const loc = target.GetLocation();
    const counts = FightRead.LaneCounts(bot, snap, COUNTER_RANGE, loc);
    return Evaluate({
        burst: burstOn(contributors, target),
        hp: target.GetHealth(),
        regen: target.GetHealthRegen !== undefined ? target.GetHealthRegen() : 0,
        escapeReady: escapeReady(pid, target, now, skill),
        towerInRange: towerInRange(target.GetTeam(), loc),
        enemiesNear: counts.enemies,
        alliesNear: counts.allies,
        skill,
        errRoll: RandomFloat(0, 1),
        botHP: hpFraction(bot),
        enemiesNearBot: counts.enemiesNearBot,
        incoming: incomingOn(bot, target, snap),
        botHealth: bot.GetHealth(),
        botMaxHealth: bot.GetMaxHealth(),
        minMargin: minMarginFor(bot, contributors),
    });
}

/**
 * Undefined when there is nothing to check: Kill off, no lane snapshot, or a target that is removed, dead, unseen or
 * has no location. Cached for KillCheckEvery per (bot, target, partners that contribute burst); `fresh` recomputes (an
 * abort re-check must not reuse a result from before the signal).
 */
export function Check(bot: Unit, partners: (Unit | undefined)[], target: Unit, now: number, fresh?: boolean): KillResult | undefined {
    if (!LaneFightConfig.IsOn("Kill") || !located(bot) || !located(target)) return undefined;
    const snap = LaneState.ForBot(bot);
    if (snap === undefined) return undefined;
    const pid = bot.GetPlayerID();
    const loc = target.GetLocation();
    const contributors: Unit[] = [];
    const partnerPids: number[] = [];
    if (contributes(bot, loc)) contributors.push(bot);
    for (const p of partners) {
        if (p === bot || !contributes(p, loc)) continue;
        contributors.push(p);
        partnerPids.push(p.GetPlayerID());
    }
    table.sort(partnerPids);
    const key = `${target.GetPlayerID()}:${partnerPids.length > 0 ? table.concat(partnerPids, ",") : "solo"}`;
    let byTarget = cache[pid];
    if (byTarget === undefined) {
        byTarget = {};
        cache[pid] = byTarget;
    }
    const cached = byTarget[key];
    if (fresh !== true && cached !== undefined && now >= cached.at && now - cached.at < LaneFightConfig.Settings().KillCheckEvery) return cached.result;
    const result = compute(bot, contributors, target, snap, now);
    byTarget[key] = { at: now, result };
    return result;
}


export function ResetCache(): void {
    cache = {};
}
