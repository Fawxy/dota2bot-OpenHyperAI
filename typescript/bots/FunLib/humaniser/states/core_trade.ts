/**
 * Core in lane, trading (L.2c): a pos1-3 core's attacks on enemy heroes while it lanes. mode_attack_generic defines its
 * GetDesire/Think for the bots this owns (decided at load, OWNERSHIP H13): in lane, this module's desire and Think; out of
 * lane, OHA's Lua port override_generic/mode_attack_generic, since defining GetDesire removes Valve's attack desire for the
 * whole game. The desire sits under the laning 0.9 last-hit desire and under any retreat, so a due last hit or a retreat
 * always wins the frame. Inputs follow EC-045 (creeps in the area, no fighting in a big enemy wave or under their tower)
 * and EC-053 (lane creeps acquire a hero attacker within about 500); every threshold is `judgement`.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export type Kind = "trade" | "kill";
export type Respect = "low_hp" | "behind" | "outnumbered" | "tower" | "creeps" | "wave";

export interface Inputs {
    hp: number;
    targetHp: number;
    enemiesNear: number;
    alliesNear: number;
    /** Enemy lane creeps within CREEP_AGGRO of the bot: each turns on it once it hits a hero. */
    enemyCreepsNear: number;
    /** Enemy units already attacking the bot (creeps and tower). */
    hitByCreeps: number;
    /** The bot or the target within reach of an enemy tower. */
    tower: boolean;
}

export const DESIRE_TRADE = 0.6;
export const DESIRE_KILL = 0.75;
const MIN_HP = 0.5;
const BEHIND_BY = 0.15;
const KILL_HP = 0.25;
const MAX_WAVE = 3;
const MAX_CREEPS_ON_ME = 2;
/**
 * Hysteresis for a running trade: the HP floor, the HP gap and the wave size each get this much slack (the wave one creep), so
 * a trade on a border does not stop and start every frame.
 */
const KEEP_HP_SLACK = 0.05;
const KEEP_WAVE_SLACK = 1;
/**
 * A trade has no time limit (user 03/11/2026): it ends when the exchange turns against the core, i.e. it has lost this share of
 * its max HP more than the target lost since the trade began, or on any other end below.
 */
const LOSING_BY = 0.05;
/** A kill window commits and ignores the exchange, so it keeps a time limit. */
const KILL_TIME = 6;
/** Reach beyond the bot's attack range (plus both bounding radii) within which a hero is a target. */
const REACH = 100;
const NEAR = 1200;
const CREEP_AGGRO = 500;
const TOWER_REACH = 850;
/** Within this of its assigned lane's path the core is in lane (fight_read's LANE_WIDTH). */
const LANE_WIDTH = 1200;
/**
 * Creep aggro (EC-053, Liquipedia Lane_Creeps 7.41f): an attack order on an enemy hero draws enemy lane creeps within 500 of the
 * ordering hero and starts a 3 s cooldown even when none are near; attack animations within 500 draw them too, except while that
 * cooldown runs. So an order given clear of creeps buys up to 3 s of hits near them with no aggro. CLEAR adds 50 for creeps
 * moving during the order's latency; COOLDOWN_LEFT stops relying on the cooldown 0.3 s before it ends.
 */
const AGGRO_CLEAR = 550;
const AGGRO_COOLDOWN = 3;
const COOLDOWN_LEFT = 0.3;
/** A step out of the creeps that has not cleared them in this long ends the trade (`no_clear`). */
const STEP_OUT_LIMIT = 2;
/** A window Desire offered that attack mode did not take within this is logged as lost. */
const LOST_AFTER = 1;

/**
 * Whether a trade (or kill) is on against a target with these inputs, or why not. `running`: the trade is already under way, so
 * the borders get their slack.
 */
export function Decide(i: Inputs, running = false): { kind?: Kind; respect?: Respect } {
    const slack = running ? KEEP_HP_SLACK : 0;
    if (i.tower) return { respect: "tower" };
    if (i.enemiesNear > i.alliesNear) return { respect: "outnumbered" };
    if (i.targetHp <= KILL_HP && i.hp >= i.targetHp) return { kind: "kill" };
    if (i.hp < MIN_HP - slack) return { respect: "low_hp" };
    if (i.hp < i.targetHp - BEHIND_BY - slack) return { respect: "behind" };
    if (i.hitByCreeps >= MAX_CREEPS_ON_ME) return { respect: "creeps" };
    if (i.enemyCreepsNear > MAX_WAVE + (running ? KEEP_WAVE_SLACK : 0)) return { respect: "wave" };
    return { kind: "trade" };
}

/**
 * HP the core lost beyond what the target lost since `hp0`/`thp0`, as a share of the core's max HP (positive: losing).
 * Absolute HP on both sides, so a big hero is not judged against a small one's fractions.
 */
export function Deficit(hp0: number, hp: number, thp0: number, thp: number, maxHp: number): number {
    return (hp0 - hp - (thp0 - thp)) / math.max(1, maxHp);
}

interface Episode {
    kind: Kind;
    target: Unit;
    tpid: number;
    offeredAt: number;
    startedAt?: number;
    hp0: number;
    thp0: number;
    inputs: Inputs;
    /** When the current step out of the creeps began, while one runs. */
    stepSince?: number;
    primes: number;
    stepOuts: number;
    /** Most enemy lane creeps attacking the core at once during the trade. */
    aggro: number;
    /** Attack mode's OnEnd ran: the next Desire closes the trade naming the mode that took the bot (OnEnd still reads attack). */
    ended?: boolean;
}

export type AggroAction = "attack" | "prime" | "step_out";

/**
 * CANDIDATE(aggroFreeAttack): Support in lane's harass is the second consumer, then the engine's. What a trading hero does this
 * frame so its hits draw no creep aggro: `attack` while its own attack order's cooldown covers it; `prime` (a fresh attack
 * order) when no enemy lane creep is within AGGRO_CLEAR; otherwise `step_out` of the creeps first.
 */
export function AggroPlan(now: number, primedAt: number | undefined, creepsWithinClear: number): AggroAction {
    if (primedAt !== undefined && now - primedAt < AGGRO_COOLDOWN - COOLDOWN_LEFT) return "attack";
    return creepsWithinClear === 0 ? "prime" : "step_out";
}

const episodes: Record<number, Episode | undefined> = {};
/**
 * After a trade lost on the exchange: the core's HP fraction minus the target's when that trade began. No new trade until the
 * gap is back there (the core regained what it lost relative to the enemy), instead of a fixed wait.
 */
const recoverTo: Record<number, number | undefined> = {};
/** Which arm this frame's GetDesire took: Think follows it. */
const ownsFrame: Record<number, boolean | undefined> = {};
/** When this bot last gave an attack order on an enemy hero (its aggro cooldown runs from there). */
const primedAt: Record<number, number | undefined> = {};

/** Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it). */
export function Owns(bot: Unit): boolean {
    return Ours.On("CoreTrade") && CoreLastHit.Applies(bot);
}

/** The core lanes: laning phase for it (transitions/phase) and standing by its own lane; elsewhere OHA's port fights. */
function inLane(bot: Unit): boolean {
    return Phase.IsLaningFor(bot) && GetAmountAlongLane(bot.GetAssignedLane(), bot.GetLocation()).distance <= LANE_WIDTH;
}

function frac(u: Unit): number {
    return u.GetHealth() / math.max(1, u.GetMaxHealth());
}

function valid(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.CanBeSeen() && !u.IsIllusion();
}

function nearestTarget(bot: Unit): Unit | undefined {
    const reach = bot.GetAttackRange() + bot.GetBoundingRadius() * 2 + REACH;
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const h of bot.GetNearbyHeroes(reach, true, BotMode.None)) {
        if (!valid(h)) continue;
        const d = GetUnitToUnitDistance(bot, h);
        if (d < bestD) {
            best = h;
            bestD = d;
        }
    }
    return best;
}

export function Gather(bot: Unit, target: Unit): Inputs {
    let enemiesNear = 0;
    for (const h of bot.GetNearbyHeroes(NEAR, true, BotMode.None)) if (valid(h)) enemiesNear++;
    let alliesNear = 0;
    for (const h of bot.GetNearbyHeroes(NEAR, false, BotMode.None)) if (h.IsAlive() && !h.IsIllusion()) alliesNear++;
    let enemyCreepsNear = 0;
    let hitByCreeps = 0;
    for (const c of bot.GetNearbyLaneCreeps(CREEP_AGGRO, true)) {
        if (!c.IsAlive()) continue;
        enemyCreepsNear++;
        if (c.GetAttackTarget() === bot) hitByCreeps++;
    }
    let tower = false;
    for (const t of bot.GetNearbyTowers(TOWER_REACH + 1000, true)) {
        if (!t.IsAlive()) continue;
        if (GetUnitToUnitDistance(bot, t) <= TOWER_REACH || GetUnitToUnitDistance(target, t) <= TOWER_REACH) tower = true;
        if (t.GetAttackTarget() === bot) hitByCreeps += MAX_CREEPS_ON_ME;
    }
    return {
        hp: frac(bot),
        targetHp: frac(target),
        enemiesNear,
        // GetNearbyHeroes on our own team includes the bot.
        alliesNear: math.max(1, alliesNear),
        enemyCreepsNear,
        hitByCreeps,
        tower,
    };
}

function close(bot: Unit, ep: Episode, why: string, now: number): void {
    const pid = bot.GetPlayerID();
    episodes[pid] = undefined;
    const started = ep.startedAt !== undefined;
    if (started && why === "losing") recoverTo[pid] = ep.inputs.hp - ep.inputs.targetHp;
    const killed = started && (ep.target.IsNull() || !ep.target.IsAlive());
    const thp = !ep.target.IsNull() && ep.target.IsAlive() ? ep.target.GetHealth() : 0;
    const i = ep.inputs;
    Telemetry.Event("trade", [
        ["pid", pid],
        ["kind", ep.kind],
        ["tgt", ep.tpid],
        ["result", started ? (killed ? "kill" : "done") : "lost"],
        ["why", why],
        ["dur", started ? math.floor((now - ep.startedAt!) * 10) / 10 : 0],
        ["hpd", started ? ep.hp0 - bot.GetHealth() : 0],
        ["thpd", started ? ep.thp0 - thp : 0],
        ["hp", math.floor(i.hp * 100) / 100],
        ["thp", math.floor(i.targetHp * 100) / 100],
        ["en", i.enemiesNear],
        ["al", i.alliesNear],
        ["cr", i.enemyCreepsNear],
        ["pr", ep.primes],
        ["so", ep.stepOuts],
        ["ag", ep.aggro],
        ["mode", bot.GetActiveMode()],
        ["md", math.floor(bot.GetActiveModeDesire() * 100) / 100],
    ]);
}

/**
 * The in-lane attack desire, or undefined outside lane (the caller then asks OHA's port). Opens, keeps and ends the
 * bot's trade episode; a window attack mode never took is logged as `lost` with the mode that held the bot.
 */
export function Desire(bot: Unit): number | undefined {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let ep = episodes[pid];
    if (!bot.IsAlive() || !inLane(bot)) {
        if (ep !== undefined) close(bot, ep, bot.IsAlive() ? "lane_end" : "dead", now);
        ownsFrame[pid] = false;
        return bot.IsAlive() ? undefined : 0;
    }
    ownsFrame[pid] = true;
    if (ep !== undefined && ep.ended) {
        close(bot, ep, `mode_${bot.GetActiveMode()}`, now);
        ep = undefined;
    }
    if (ep !== undefined) {
        const why = keepWhy(bot, ep, now);
        if (why === undefined) return ep.kind === "kill" ? DESIRE_KILL : DESIRE_TRADE;
        close(bot, ep, why, now);
        ep = undefined;
    }
    const target = nearestTarget(bot);
    if (target === undefined) return 0;
    const inputs = Gather(bot, target);
    const d = Decide(inputs);
    if (d.kind === undefined) return 0;
    const gap = recoverTo[pid];
    if (d.kind === "trade" && gap !== undefined) {
        if (inputs.hp - inputs.targetHp < gap - 1e-6) return 0;
        recoverTo[pid] = undefined;
    }
    episodes[pid] = { kind: d.kind, target, tpid: target.GetPlayerID(), offeredAt: now, hp0: bot.GetHealth(), thp0: target.GetHealth(), inputs, primes: 0, stepOuts: 0, aggro: 0 };
    return d.kind === "kill" ? DESIRE_KILL : DESIRE_TRADE;
}

/** Why a running episode ends now, or undefined to keep it. */
function keepWhy(bot: Unit, ep: Episode, now: number): string | undefined {
    const t: Unit = ep.target;
    if (!valid(t)) return ep.target.IsNull() || !ep.target.IsAlive() ? "target_dead" : "target_lost";
    if (ep.startedAt === undefined) return now - ep.offeredAt > LOST_AFTER ? "not_taken" : undefined;
    if (ep.kind === "kill") {
        if (now - ep.startedAt > KILL_TIME) return "time";
    } else {
        if (ep.stepSince !== undefined && now - ep.stepSince > STEP_OUT_LIMIT) return "no_clear";
        const reach = bot.GetAttackRange() + bot.GetBoundingRadius() * 2 + REACH;
        // A step out moves away from the target on purpose, and the order primed from clear ground walks back in while its
        // cooldown covers the hits.
        const primed = primedAt[bot.GetPlayerID()];
        const walkingIn = primed !== undefined && now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT;
        if (ep.stepSince === undefined && !walkingIn && GetUnitToUnitDistance(bot, ep.target) > reach) return "out_of_reach";
        if (Deficit(ep.hp0, bot.GetHealth(), ep.thp0, ep.target.GetHealth(), bot.GetMaxHealth()) > LOSING_BY) return "losing";
    }
    const d = Decide(Gather(bot, ep.target), true);
    if (d.kind === undefined) return d.respect;
    return undefined;
}

/** Whether this frame's GetDesire took our arm; mode_attack_generic's Think runs ours when true, OHA's port otherwise. */
export function OwnsFrame(bot: Unit): boolean {
    return ownsFrame[bot.GetPlayerID()] === true;
}

export function Think(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const ep = episodes[pid];
    if (ep === undefined || !valid(ep.target)) return;
    const now = DotaTime();
    if (ep.startedAt === undefined) ep.startedAt = now;
    const creeps: Unit[] = [];
    let onMe = 0;
    for (const c of bot.GetNearbyLaneCreeps(AGGRO_CLEAR, true)) {
        // cil2 (A_on_1 t=776.3, B_on_2 t=377.1): a listed creep that had dropped from sight returned no location.
        if (c.IsNull() || !c.IsAlive() || !c.CanBeSeen()) continue;
        creeps.push(c);
        if (c.GetAttackTarget() === bot) onMe++;
    }
    ep.aggro = math.max(ep.aggro, onMe);
    // A kill window commits: it attacks whatever the creeps do.
    const plan = ep.kind === "kill" ? "attack" : AggroPlan(now, primedAt[pid], creeps.length);
    if (plan === "step_out") {
        if (ep.stepSince === undefined) {
            ep.stepSince = now;
            ep.stepOuts++;
        }
        bot.Action_MoveToLocation(stepOutPoint(bot, creeps));
        return;
    }
    ep.stepSince = undefined;
    if (plan === "prime") {
        primedAt[pid] = now;
        ep.primes++;
        bot.Action_AttackUnit(ep.target, false);
        return;
    }
    if (bot.GetAttackTarget() !== ep.target) {
        // An order inside the cooldown draws nothing and does not restart it.
        if (ep.kind === "kill") primedAt[pid] = now;
        bot.Action_AttackUnit(ep.target, false);
    }
}

/** AGGRO_CLEAR + 100 from the creeps' centre, on the far side from them. */
function stepOutPoint(bot: Unit, creeps: Unit[]): Vector {
    const me = bot.GetLocation();
    let x = 0;
    let y = 0;
    let seen = 0;
    for (const c of creeps) {
        const l = c.GetLocation() as Vector | undefined;
        if (l === undefined) continue;
        x += l.x;
        y += l.y;
        seen++;
    }
    // No located creep: treat the core as on the centre, which steps back along the lane.
    x = seen > 0 ? x / seen : me.x;
    y = seen > 0 ? y / seen : me.y;
    let dx = me.x - x;
    let dy = me.y - y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) {
        // Standing on the centre: step back along the lane towards our own side.
        const back = GetLocationAlongLane(bot.GetAssignedLane(), math.max(0, GetAmountAlongLane(bot.GetAssignedLane(), me).amount - 0.05));
        dx = back.x - me.x;
        dy = back.y - me.y;
    }
    const n = math.max(1, math.sqrt(dx * dx + dy * dy));
    return Vector(x + (dx / n) * (AGGRO_CLEAR + 100), y + (dy / n) * (AGGRO_CLEAR + 100), me.z);
}

/** Attack mode lost the bot to another mode: a running trade ends there (closed by the next Desire, which can name that mode). */
export function OnEnd(bot: Unit): void {
    const ep = episodes[bot.GetPlayerID()];
    if (ep !== undefined && ep.startedAt !== undefined) ep.ended = true;
}

/**
 * Laning's 0.9 last-hit desire must not cut a retreat this context's core is already in (core-time-diagnosis s2: a death
 * within 15 s of such a cut was 4 times as likely). A predicate on the laning GetDesire (OWNERSHIP H2).
 */
export function LastHitYieldsToRetreat(bot: Unit): boolean {
    return CoreLastHit.Applies(bot) && bot.GetActiveMode() === BotMode.Retreat;
}

export function Reset(): void {
    for (const k in episodes) episodes[k as unknown as number] = undefined;
    for (const k in recoverTo) recoverTo[k as unknown as number] = undefined;
    for (const k in primedAt) primedAt[k as unknown as number] = undefined;
    for (const k in ownsFrame) ownsFrame[k as unknown as number] = undefined;
}
