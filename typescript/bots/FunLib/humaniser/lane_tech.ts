/**
 * In-lane techniques (task 07): creep block, aggro pull and drop, tower-aggro drop, freeze/hold positioning
 * and shove, executed inside the owned laning Think(). A technique only starts when the planner names it
 * (PF14); the tower-aggro drop is a safety reaction and ignores the planner.
 */
import { Lane, Team, Tower, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LanePlanner from "bots/FunLib/humaniser/lane_planner";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Intent from "bots/FunLib/humaniser/intent";

type Phase = "approach" | "block" | "walk" | "swap";

interface Sequence {
    tech: LaneConfig.Technique;
    phase: Phase;
    startedAt: number;
    noiseAt?: number;
    noise?: number;
    side?: number;
    engaged?: boolean;
    lostSince?: number;
    walkTo?: Vector;
}

interface TowerDrop {
    tower: Unit;
    dropped: boolean;
}

interface Shove {
    startedAt: number;
}

const IN_LANE_FLAGS: LaneConfig.LaneFlag[] = ["Block", "AggroPull", "Freeze", "Shove", "Harass", "Mid"];
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

let sequences: Record<number, Sequence> = {};
let drops: Record<number, TowerDrop> = {};
let shoves: Record<number, Shove> = {};
let finished: Record<number, number> = {};
let started: Record<number, string> = {};
let drawAt: Record<number, number> = {};
let plans: Record<number, { time: number; choice: LanePlanner.Choice }> = {};
let towerCache: Record<number, { time: number; list: Unit[] }> = {};

export function ResetCache(): void {
    sequences = {};
    drops = {};
    shoves = {};
    finished = {};
    started = {};
    drawAt = {};
    plans = {};
    towerCache = {};
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

/** Point `len` from `from` toward `to`; `from` itself when the two coincide. */
function toward(from: Vector, to: Vector, len: number): Vector {
    const d = dist2D(from, to);
    if (d < 1e-6) return from;
    return Vector(from.x + ((to.x - from.x) / d) * len, from.y + ((to.y - from.y) / d) * len, from.z);
}

function cycleOf(time: number): number {
    return math.floor(time / settings().Timing.WaveCycle);
}

function hpOf(unit: Unit): number {
    const max = unit.GetMaxHealth();
    return max > 0 ? unit.GetHealth() / max : 0;
}

function enemyTeamOf(team: number): number {
    return team === Team.Radiant ? Team.Dire : Team.Radiant;
}

function forwardSign(team: number): number {
    return Camps.ToAbsAmount(team, 1) > Camps.ToAbsAmount(team, 0) ? 1 : -1;
}

function inLaneFlagsOn(): boolean {
    if (!LaneConfig.IsActive()) return false;
    for (const flag of IN_LANE_FLAGS) if (LaneConfig.IsOn(flag)) return true;
    return false;
}

export function OwnsLaning(bot: Unit): boolean {
    if (!inLaneFlagsOn()) return false;
    const mode = LaneConfig.OwnLaningMode();
    if (mode === "all") return true;
    if (mode === "allies") return Difficulty.IsAllyOfHuman(bot);
    return false;
}

/** The bot's lane snapshot when the in-lane techniques may act this frame; undefined before any engine call otherwise. */
function activeSnapshot(bot: Unit): LaneState.LaneSnapshot | undefined {
    if (!inLaneFlagsOn()) return undefined;
    const s = LaneState.ForBot(bot);
    if (s === undefined) return undefined;
    if (GetUnitToLocationDistance(bot, s.frontLoc) > settings().Radii.LaneActive) return undefined;
    return s;
}

function planFor(bot: Unit, s: LaneState.LaneSnapshot): LanePlanner.Choice {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const cached = plans[pid];
    if (cached !== undefined && cached.time === now) return cached.choice;
    const choice = LanePlanner.Plan(bot, s);
    plans[pid] = { time: now, choice };
    return choice;
}

function enemyTowers(team: number): Unit[] {
    const now = DotaTime();
    const cached = towerCache[team];
    if (cached !== undefined && cached.time === now) return cached.list;
    const list: Unit[] = [];
    const enemy = enemyTeamOf(team);
    for (const id of TOWER_IDS) {
        const tower = GetTower(enemy, id);
        if (tower !== null && tower !== undefined && tower.IsAlive()) list.push(tower);
    }
    towerCache[team] = { time: now, list };
    return list;
}

function underEnemyTower(team: number, loc: Vector): boolean {
    const range = settings().Thresholds.EnemyTowerRange;
    for (const tower of enemyTowers(team)) if (dist2D(tower.GetLocation(), loc) <= range) return true;
    return false;
}

function isUsable(unit: Unit | null | undefined): unit is Unit {
    return unit !== null && unit !== undefined && !unit.IsNull() && unit.IsAlive() && unit.CanBeSeen();
}

function isLaneCreep(unit: Unit | null | undefined): unit is Unit {
    return isUsable(unit) && LaneState.IsLaneCreepName(unit.GetUnitName());
}

function cycleSecText(time: number): string {
    return string.format("%.1f", time % settings().Timing.WaveCycle);
}

/** Laning's last-hit state this frame: a creep killable now, one about to be, or none. */
export type LastHit = "kill" | "soon" | undefined;

function noteStart(bot: Unit, tech: string, reason: string, lastHit?: LastHit): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const key = `${cycleOf(now)}:${tech}`;
    if (started[pid] === key) return;
    started[pid] = key;
    HDebug.Log("lane", `pid=${pid} tech=${tech} @${cycleSecText(now)} reason=${reason}`);
    Telemetry.Event("lane_tech", [
        ["pid", pid],
        ["tech", tech],
        ["reason", reason],
        ["lh", lastHit !== undefined],
    ]);
}

export function Mistake(bot: Unit, kind: string): void {
    HDebug.Log("lane", `mistake pid=${bot.GetPlayerID()} ${kind}`);
}

function overlay(bot: Unit, text: string): void {
    HDebug.Text(bot, "lane_exec", text);
}

function finish(bot: Unit): void {
    const pid = bot.GetPlayerID();
    delete sequences[pid];
    finished[pid] = cycleOf(DotaTime());
}

function finishedThisCycle(pid: number): boolean {
    return finished[pid] === cycleOf(DotaTime());
}

// ---------------------------------------------------------------------------------------------- geometry

export function BlockPoint(lead: Vector, dirAmountSign: number, lane: Lane, ahead: number, side: number): Vector {
    const step = settings().Camps.LaneSampleStep;
    const a = GetAmountAlongLane(lane, lead).amount;
    const p0 = GetLocationAlongLane(lane, a);
    const p1 = GetLocationAlongLane(lane, clamp01(a + dirAmountSign * step));
    const d = dist2D(p0, p1);
    if (d < 1e-6) return lead;
    const dx = (p1.x - p0.x) / d;
    const dy = (p1.y - p0.y) / d;
    return Vector(lead.x + dx * ahead - dy * side, lead.y + dy * ahead + dx * side, lead.z);
}

export function HoldPoint(team: number, lane: Lane, eq: number, ourTower: number, theirTower: number, back: number): Vector {
    const step = settings().Camps.LaneSampleStep;
    const teamAmount = ourTower + ((eq + 1) / 2) * (theirTower - ourTower);
    const loc = GetLocationAlongLane(lane, clamp01(Camps.ToAbsAmount(team, teamAmount)));
    const behind = GetLocationAlongLane(lane, clamp01(Camps.ToAbsAmount(team, teamAmount - step)));
    return toward(loc, behind, back);
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

function nearest(from: Vector, units: Unit[], maxDist: number): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = maxDist;
    for (const u of units) {
        const d = dist2D(u.GetLocation(), from);
        if (d <= bestDist) {
            best = u;
            bestDist = d;
        }
    }
    return best;
}

function alliedLaneCreeps(bot: Unit, allyCreeps: Unit[]): Unit[] {
    const result: Unit[] = [];
    const team = bot.GetTeam();
    for (const c of allyCreeps ?? []) if (isLaneCreep(c) && c.GetTeam() === team) result.push(c);
    return result;
}

// ---------------------------------------------------------------------------------------------- tower aggro

function towerTargeting(bot: Unit, target: Unit, radius: number): Unit | undefined {
    const loc = target.GetLocation();
    for (const tower of enemyTowers(bot.GetTeam())) {
        if (dist2D(tower.GetLocation(), loc) > radius) continue;
        if (tower.GetAttackTarget() === target) return tower;
    }
    return undefined;
}

/** Safety reaction (exempt from the planner, attempt roll and commit lock): shed tower aggro, then leave its range. */
function towerDrop(bot: Unit, s: LaneState.LaneSnapshot, allyCreeps: Unit[]): boolean {
    const pid = bot.GetPlayerID();
    const radii = settings().Radii;
    let drop = drops[pid];
    if (drop === undefined) {
        if (!LaneConfig.Knows("aggro_pull", LaneConfig.SkillOf(bot))) return false;
        const tower = towerTargeting(bot, bot, radii.TowerAggro);
        if (tower === undefined) return false;
        drop = { tower, dropped: false };
        drops[pid] = drop;
        noteStart(bot, "tower_drop", "tower aggro");
    }
    const exit = radii.TowerAggro + radii.TowerExitMargin;
    const towerLoc = drop.tower.GetLocation();
    const here = bot.GetLocation();
    if (!drop.dropped) {
        drop.dropped = true;
        const range = bot.GetAttackRange();
        const heroes: Unit[] = [];
        for (const h of s.allies) if (h.alive && h.pid !== pid) heroes.push(h.unit);
        const target = nearest(here, alliedLaneCreeps(bot, allyCreeps), range) ?? nearest(here, heroes, range);
        if (target !== undefined) {
            overlay(bot, `tech=tower_drop@${cycleSecText(DotaTime())} drop`);
            bot.Action_AttackUnit(target, true);
            return true;
        }
    }
    if (!drop.tower.IsAlive() || dist2D(here, towerLoc) >= exit - settings().Thresholds.ApproachEpsilon) {
        delete drops[pid];
        return false;
    }
    overlay(bot, `tech=tower_drop@${cycleSecText(DotaTime())} exit`);
    bot.Action_MoveToLocation(toward(towerLoc, here, exit));
    return true;
}

// ---------------------------------------------------------------------------------------------- block

function blockContact(lead: Unit, s: LaneState.LaneSnapshot, enemyCreeps: Unit[]): boolean {
    const contact = settings().Radii.BlockContact;
    const loc = lead.GetLocation();
    for (const list of [s.enemy.units, enemyCreeps ?? []]) {
        for (const c of list) if (isLaneCreep(c) && c.GetTeam() !== s.team && dist2D(c.GetLocation(), loc) <= contact) return true;
    }
    return false;
}

function runBlock(bot: Unit, s: LaneState.LaneSnapshot, seq: Sequence, enemyCreeps: Unit[], choice: LanePlanner.Choice): boolean {
    const cfg = settings();
    const now = DotaTime();
    const lead = s.ally.lead;
    if (choice.tech !== "block" || now >= cfg.Timing.BlockEnd || lead === undefined || !lead.IsAlive() || blockContact(lead, s, enemyCreeps)) {
        finish(bot);
        return false;
    }
    const leadLoc = lead.GetLocation();
    const dist = GetUnitToLocationDistance(bot, leadLoc);
    if (dist <= cfg.Radii.BlockLost) seq.engaged = true;
    if (seq.engaged === true && dist > cfg.Radii.BlockLost) {
        if (seq.lostSince === undefined) seq.lostSince = now;
        if (now - seq.lostSince >= cfg.Timing.BlockLostSec) {
            Mistake(bot, "block-lost");
            finish(bot);
            return false;
        }
    } else {
        seq.lostSince = undefined;
    }

    if (seq.engaged !== true && dist > cfg.Radii.BlockStart) {
        seq.phase = "approach";
        overlay(bot, `tech=block@${cycleSecText(seq.startedAt)} approach`);
        bot.Action_MoveToLocation(leadLoc);
        return true;
    }
    seq.phase = "block";
    if (seq.noiseAt === undefined || now - seq.noiseAt >= cfg.Timing.BlockNoiseEvery) {
        seq.noiseAt = now;
        seq.noise = RandomFloat(-1, 1) * LaneConfig.Curve("PathNoise", LaneConfig.SkillOf(bot));
        seq.side = seq.side === undefined || seq.side < 0 ? 1 : -1;
    }
    const point = BlockPoint(leadLoc, forwardSign(s.team), s.lane, cfg.Radii.BlockAhead + (seq.noise ?? 0), (seq.side ?? 1) * cfg.Radii.BlockSide);
    overlay(bot, `tech=block@${cycleSecText(seq.startedAt)} block`);
    bot.Action_MoveToLocation(point);
    return true;
}

function startBlock(bot: Unit, s: LaneState.LaneSnapshot, enemyCreeps: Unit[], choice: LanePlanner.Choice): boolean {
    const lead = s.ally.lead;
    if (DotaTime() >= settings().Timing.BlockEnd || lead === undefined || blockContact(lead, s, enemyCreeps)) return false;
    const seq: Sequence = { tech: "block", phase: "approach", startedAt: DotaTime() };
    sequences[bot.GetPlayerID()] = seq;
    const acted = runBlock(bot, s, seq, enemyCreeps, choice);
    if (acted) {
        LanePlanner.Commit(bot, "block");
        noteStart(bot, "block", choice.reason);
    }
    return acted;
}

// ---------------------------------------------------------------------------------------------- aggro pull

function drawTarget(bot: Unit, enemies: Unit[]): Unit | undefined {
    const reach = bot.GetAttackRange() + settings().Radii.AggroDrawExtra;
    const team = bot.GetTeam();
    const candidates: Unit[] = [];
    for (const e of enemies ?? []) {
        if (!isUsable(e) || e.GetTeam() === team || underEnemyTower(team, e.GetLocation())) continue;
        candidates.push(e);
    }
    return nearest(bot.GetLocation(), candidates, reach);
}

/** Lane point to walk the drawn creeps back to: one aggro step behind the wave, never ahead of the bot. */
function walkBackPoint(bot: Unit, s: LaneState.LaneSnapshot): Vector {
    const cfg = settings();
    const here = bot.GetLocation();
    const own = LaneState.EqPos(Camps.ToTeamAmount(s.team, GetAmountAlongLane(s.lane, here).amount), s.ourTowerAmount, s.theirTowerAmount);
    const eq = math.min(s.eqPos - cfg.Planner.AggroStepEq, own);
    const lanePoint = HoldPoint(s.team, s.lane, eq, s.ourTowerAmount, s.theirTowerAmount, cfg.Radii.AggroWalkBack);
    const noise = LaneConfig.Curve("PathNoise", LaneConfig.SkillOf(bot));
    const point = Vector(lanePoint.x + RandomFloat(-1, 1) * noise, lanePoint.y + RandomFloat(-1, 1) * noise, lanePoint.z);
    return dist2D(here, point) > cfg.Radii.AggroWalkMax ? toward(here, point, cfg.Radii.AggroWalkMax) : point;
}

function beginDrop(bot: Unit, s: LaneState.LaneSnapshot, phase: Phase, reason: string, lastHit: LastHit): void {
    const now = DotaTime();
    LanePlanner.Commit(bot, "aggro_pull");
    LaneRoles.NoteAggroDraw(bot, s);
    sequences[bot.GetPlayerID()] = { tech: "aggro_pull", phase, startedAt: now, walkTo: phase === "walk" ? walkBackPoint(bot, s) : undefined };
    noteStart(bot, "aggro_pull", reason, lastHit);
}

/** Planned swap: an allied core is losing HP to an enemy tower, so the bot takes the tower's aggro instead. */
function trySwap(bot: Unit, s: LaneState.LaneSnapshot, enemies: Unit[], reason: string, lastHit: LastHit): boolean {
    const t = settings().Thresholds;
    if (hpOf(bot) <= t.TowerSwapBotHP) return false;
    const pid = bot.GetPlayerID();
    for (const h of s.allies) {
        if (!h.alive || h.pid === pid || h.position === undefined || h.position < 1 || h.position > 3 || h.hp >= t.TowerSwapAllyHP) continue;
        const tower = towerTargeting(bot, h.unit, settings().Radii.TowerAggro);
        if (tower === undefined) continue;
        const candidates: Unit[] = [];
        for (const e of enemies ?? []) if (isUsable(e) && e.GetTeam() !== s.team) candidates.push(e);
        const hero = nearest(tower.GetLocation(), candidates, t.EnemyTowerRange);
        if (hero === undefined) continue;
        bot.Action_AttackUnit(hero, true);
        beginDrop(bot, s, "swap", `${reason}: tower swap`, lastHit);
        overlay(bot, `tech=aggro_pull@${cycleSecText(DotaTime())} swap`);
        return true;
    }
    return false;
}

function startAggro(bot: Unit, s: LaneState.LaneSnapshot, enemies: Unit[], choice: LanePlanner.Choice, lastHit: LastHit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let at = drawAt[pid];
    if (at === undefined) {
        at = now + math.max(0, LaneConfig.Jitter(LaneConfig.SkillOf(bot)));
        drawAt[pid] = at;
    }
    if (now < at) {
        overlay(bot, string.format("tech=aggro_pull wait: jitter %.1fs", at - now));
        return false;
    }
    const [may, why] = LaneRoles.MayDrawAggro(bot, s);
    if (!may) {
        overlay(bot, `tech=aggro_pull ${why}`);
        return false;
    }
    // A tower swap saves a core's life, so it goes ahead; a plain draw waits until no creep is dying.
    if (trySwap(bot, s, enemies, choice.reason, lastHit)) {
        delete drawAt[pid];
        return true;
    }
    if (lastHit !== undefined) {
        overlay(bot, "tech=aggro_pull wait: last hit");
        return false;
    }
    const hero = drawTarget(bot, enemies);
    if (hero === undefined) {
        overlay(bot, "tech=aggro_pull wait: no target");
        return false;
    }
    delete drawAt[pid];
    bot.Action_AttackUnit(hero, true);
    beginDrop(bot, s, "walk", choice.reason, lastHit);
    overlay(bot, `tech=aggro_pull@${cycleSecText(DotaTime())} draw`);
    return true;
}

function runAggro(bot: Unit, seq: Sequence, allyCreeps: Unit[], lastHit: LastHit): boolean {
    const now = DotaTime();
    const walkBack = settings().Timing.WalkBack;
    // A creep dying in range is taken now: the drawn creeps lose interest in a few seconds anyway.
    if (lastHit === "kill" && (seq.phase === "swap" || seq.phase === "walk")) {
        finish(bot);
        return false;
    }
    if (seq.phase === "swap") {
        // The tower drop above takes over once the tower switches to the bot.
        if (now - seq.startedAt < walkBack) {
            Intent.Hold(bot, "lane:swap");
            return true;
        }
        finish(bot);
        return false;
    }
    if (seq.phase === "walk" && now - seq.startedAt < walkBack) {
        overlay(bot, `tech=aggro_pull@${cycleSecText(seq.startedAt)} walk`);
        bot.Action_MoveToLocation(seq.walkTo ?? bot.GetLocation());
        return true;
    }
    finish(bot);
    const creeps = alliedLaneCreeps(bot, allyCreeps);
    const here = bot.GetLocation();
    // TODO (in-game): the deny order may be refused on an allied creep above 50% HP; check the drop still happens.
    const target = nearest(here, creeps, bot.GetAttackRange()) ?? nearest(here, creeps, math.huge);
    if (target === undefined) return false;
    overlay(bot, `tech=aggro_pull@${cycleSecText(seq.startedAt)} drop`);
    bot.Action_AttackUnit(target, true);
    return true;
}

// ---------------------------------------------------------------------------------------------- entry points

/** Only the tower-aggro drop: for a bot that must otherwise leave this wave alone. */
export function TowerDropThink(bot: Unit, allyCreeps: Unit[]): boolean {
    const s = activeSnapshot(bot);
    return s !== undefined && towerDrop(bot, s, allyCreeps);
}

export function PreThink(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], lastHit?: LastHit): boolean {
    const s = activeSnapshot(bot);
    if (s === undefined) return false;
    if (towerDrop(bot, s, allyCreeps)) return true;
    const pid = bot.GetPlayerID();
    const choice = planFor(bot, s);
    const seq = sequences[pid];
    if (seq !== undefined) {
        if (seq.tech === "block") return runBlock(bot, s, seq, enemyCreeps, choice);
        return runAggro(bot, seq, allyCreeps, lastHit);
    }
    // The draw delay is sampled once per need: a choice change ends the need.
    if (choice.tech !== "aggro_pull") delete drawAt[pid];
    if (finishedThisCycle(pid)) return false;
    if (choice.tech === "block") return startBlock(bot, s, enemyCreeps, choice);
    if (choice.tech === "aggro_pull") return startAggro(bot, s, enemies, choice, lastHit);
    return false;
}

function enemyCreepsNearFront(s: LaneState.LaneSnapshot): number {
    let n = 0;
    for (const c of s.enemy.units) if (isLaneCreep(c)) n++;
    return n;
}

export function Think(bot: Unit, _allyCreeps: Unit[], enemyCreeps: Unit[], _enemies: Unit[]): boolean {
    const s = activeSnapshot(bot);
    if (s === undefined) return false;
    const pid = bot.GetPlayerID();
    const cfg = settings();
    const now = DotaTime();
    const choice = planFor(bot, s);
    let shove = shoves[pid];
    if (shove !== undefined) {
        if (choice.tech !== "shove" || now - shove.startedAt >= cfg.Timing.ShoveMaxSec || enemyCreepsNearFront(s) <= cfg.Thresholds.ShoveDoneCreeps) {
            delete shoves[pid];
            finished[pid] = cycleOf(now);
            return false;
        }
    } else if (choice.tech !== "shove" || finishedThisCycle(pid) || enemyCreepsNearFront(s) <= cfg.Thresholds.ShoveDoneCreeps) {
        return false;
    }
    const stronger = LaneConfig.Helpers().WeAreStronger;
    if (stronger === undefined || !stronger(bot, cfg.Radii.Stronger) || hpOf(bot) < cfg.Thresholds.ShoveMinHP) return false;
    const target = ShoveTarget(bot, enemyCreeps);
    if (target === undefined) return false;
    if (shove === undefined) {
        shove = { startedAt: now };
        shoves[pid] = shove;
        LanePlanner.Commit(bot, "shove");
        noteStart(bot, "shove", choice.reason);
        if (choice.reason === "shove before rotating" && LaneConfig.IsOn("Telegraph") && Difficulty.IsAllyOfHuman(bot)) {
            Orders.Say(bot, "say_lane_shove_rotate", cfg.Timing.ShoveTelegraphCooldown);
        }
    }
    overlay(bot, `tech=shove@${cycleSecText(shove.startedAt)} hit`);
    bot.Action_AttackUnit(target, true);
    return true;
}

/** Visible enemy laner nearest our lead creep, within Zone of the front. */
function zoneTarget(bot: Unit, s: LaneState.LaneSnapshot): Vector | undefined {
    const zone = settings().Radii.Zone;
    let best: Vector | undefined;
    let bestDist = math.huge;
    for (const e of LaneState.Enemies(bot, s.lane)) {
        if (!e.visible || dist2D(e.location, s.frontLoc) > zone) continue;
        const d = dist2D(e.location, s.frontLoc);
        if (d < bestDist) {
            best = e.location;
            bestDist = d;
        }
    }
    return best;
}

/** Between our lead creep and the nearest visible enemy laner: where a support zones from. */
export function ZonePoint(bot: Unit, s: LaneState.LaneSnapshot): Vector | undefined {
    const lead = s.ally.lead;
    if (lead === undefined) return undefined;
    const enemy = zoneTarget(bot, s);
    return enemy !== undefined ? toward(lead.GetLocation(), enemy, settings().Radii.ZoneOffset) : undefined;
}

/** freeze/hold, or the plan's posture when the one-per-cycle lock (after e.g. a drag-back) hides it from the choice. */
function postureOf(bot: Unit, s: LaneState.LaneSnapshot, choice: LanePlanner.Choice): "freeze" | "hold" | undefined {
    if (choice.tech === "freeze" || choice.tech === "hold") return choice.tech;
    if (choice.tech !== "none" || string.sub(choice.reason, 1, 13) !== "one per cycle") return undefined;
    const pos = LaneConfig.PositionOf(bot);
    const plan = (pos !== undefined && pos >= 4 ? LanePlan.ForSupport(bot, s) : LanePlan.View(bot, s)).plan;
    return plan === "FREEZE" ? "freeze" : plan === "HOLD" ? "hold" : undefined;
}

export function AdjustPosition(bot: Unit, loc: Vector): Vector {
    const s = activeSnapshot(bot);
    if (s === undefined) return loc;
    const choice = planFor(bot, s);
    const posture = postureOf(bot, s, choice);
    if (posture === undefined) return loc;
    noteStart(bot, posture, choice.reason);
    Intent.Hold(bot, `lane:${posture}`);
    const cfg = settings();
    const pos = LaneConfig.PositionOf(bot);
    if (pos !== undefined && pos >= 4) {
        const zone = ZonePoint(bot, s);
        if (zone !== undefined) {
            overlay(bot, `tech=${posture}@${cycleSecText(DotaTime())} zone`);
            return zone;
        }
    }
    overlay(bot, `tech=${posture}@${cycleSecText(DotaTime())} hold`);
    const back = math.max(bot.GetAttackRange(), cfg.Radii.HoldMinBack);
    return HoldPoint(s.team, s.lane, s.desiredEq, s.ourTowerAmount, s.theirTowerAmount, back);
}
