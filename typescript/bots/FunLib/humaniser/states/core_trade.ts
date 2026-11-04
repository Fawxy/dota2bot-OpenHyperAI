/**
 * A laner's attacks on enemy heroes while it lanes: Core in lane's trades (L.2c, pos1-3) and, since slice support-spot, Support
 * in lane's harass (pos4-5, `Ours.SupportHarass`): one rule for both, the role an input (a support's reach is longer, and it
 * prefers a target busy last-hitting). mode_attack_generic defines its
 * GetDesire/Think for the bots this owns (decided at load, OWNERSHIP H13): in lane, this module's desire and Think; out of
 * lane, OHA's Lua port override_generic/mode_attack_generic, since defining GetDesire removes Valve's attack desire for the
 * whole game. The desire sits under the laning 0.9 last-hit desire and under any retreat, so a due last hit or a retreat
 * always wins the frame. Inputs follow EC-045 (creeps in the area, no fighting in a big enemy wave or under their tower)
 * and EC-053 (lane creeps acquire a hero attacker within about 500); every threshold is `judgement`.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as SupportDeny from "bots/FunLib/humaniser/states/support_deny";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Plays from "bots/FunLib/humaniser/plays/plays";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** `fight`: a lane fight from the play roll, rolled here or joined from an ally's play (slice lane-fight). */
export type Kind = "trade" | "kill" | "fight";
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
/**
 * Slice lane-fight: a core whose lane fights are ours (`OwnsLaneFights`) commits on a target at this HP or less. Banked read on
 * cil5, lposchk3, sspotchk1 (`@lane_encounters`): with the lowest enemy at 40% or less at an encounter's start cores saw 11 kills
 * and no deaths per 100 encounters, 26 and 0 when we were more; 41-70% gave 1.8 and 1.8. The cut is `judgement` from that.
 */
const COMMIT_HP = 0.4;
/**
 * The speculative lane fight (slice lane-fight, user 04/11/2026: the fights no clear window decides come from the play roll).
 * Before value on cil5, lposchk3, sspotchk1: cores 0.4 kills and 0.5 deaths per 100 encounters at even numbers with the enemy
 * over 40%, about 110 such core encounters a game, so the base is low (`judgement`). lfpchk1 at 0.05: 68 chances and 1.6
 * fired a game at a mean weight of 0.03, so 0.1 for about 4. A chance per target at most every FIGHT_ROLL_EVERY seconds, so standing beside a hero is not a roll a frame.
 */
export const LANE_FIGHT = "lane_fight";
const FIGHT_BASE = 0.1;
const FIGHT_ROLL_EVERY = 15;
/** A fight commits like a kill and keeps a limit; it also stops when the hero falls under the play roll's HP floor. */
const FIGHT_TIME = 8;
/**
 * Joining a running play (any kind with a target: a rune gank or rune fight, another hero's lane fight): its place within
 * JOIN_NEAR of the hero and its target within the hero's reach plus JOIN_WALK, about 2 s of walking (`judgement`).
 */
const JOIN_NEAR = 1600;
const JOIN_WALK = 600;
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
/**
 * A support's reach instead (judgement): its spot holds it outside the enemy heroes' reach (states/lane_spot, at least 800), so
 * a harass starts with a walk in. 300 is about 1 s of walking, inside the 3 s aggro cooldown the order primes.
 */
const HARASS_REACH = 300;
/**
 * A support prefers an enemy hero whose attack target is a lane creep (a last-hit attempt: its swing goes to the creep, not back
 * at us) by counting it this much nearer (judgement).
 */
const PUNISH_BONUS = 300;
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
export function Decide(i: Inputs, running = false, killHp = KILL_HP): { kind?: Kind; respect?: Respect } {
    const slack = running ? KEEP_HP_SLACK : 0;
    if (i.tower) return { respect: "tower" };
    if (i.enemiesNear > i.alliesNear) return { respect: "outnumbered" };
    if (i.targetHp <= killHp && i.hp >= i.targetHp) return { kind: "kill" };
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
    /** Whether the core's lane fights were ours at the offer: at the close a dead or out-of-lane core no longer reads as owned. */
    lf: boolean;
    startedAt?: number;
    hp0: number;
    thp0: number;
    /** The target's HP when last seen: an unseen target's handle reads as dead (cil3: 61 of 69 `kill` lines had no death). */
    thpSeen: number;
    inputs: Inputs;
    /** When the current step out of the creeps began, while one runs. */
    stepSince?: number;
    primes: number;
    stepOuts: number;
    /** Most enemy lane creeps attacking the core at once during the trade. */
    aggro: number;
    /** The play a `fight` runs in, and whether the hero joined it (another hero's play) rather than rolled it. */
    play?: Plays.Play;
    joined?: boolean;
    /** Attack mode's OnEnd ran: the next Desire closes the trade naming the mode that took the bot (OnEnd still reads attack). */
    ended?: boolean;
}

export type AggroAction = "attack" | "prime" | "step_out";

/**
 * The aggro-free attack, for core trades and support harass alike (one plan, so not an engine verb: a lane technique is bot code,
 * CLAUDE.md rule 3; slice support-spot). What a trading hero does this frame so its hits draw no creep aggro: `attack` while its own attack order's cooldown covers it; `prime` (a fresh attack
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
/** When this bot last had a lane-fight chance, per target pid. */
const rolledAt: Record<number, Record<number, number> | undefined> = {};

/**
 * The lane fight's own hard zeros on top of the library's (HP floor, two down, a target by its tower): the decline rule (the
 * other side more near the place) and the trade's `behind` (the hero well under the target's HP).
 */
export function FightZero(i: Plays.Inputs): string | undefined {
    if (i.theirs > i.ours) return "outnumbered";
    if (i.targetHp !== undefined && i.hp < i.targetHp - BEHIND_BY) return "behind";
    return undefined;
}

Plays.Define(LANE_FIGHT, { base: FIGHT_BASE, timeout: FIGHT_TIME + 2, chases: true, zero: FightZero });

/** Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it). */
export function Owns(bot: Unit): boolean {
    return (Ours.On("CoreTrade") && CoreLastHit.Applies(bot)) || isSupport(bot);
}

/**
 * Slice lane-fight (`Ours.CoreLaneFight`, OWNERSHIP H9): every fight of this in-lane core beyond a trade is this module's. Team
 * roam keeps only its non-fight branches for it and LaneFight makes no claim (its gates close), so a commit is `kill` here.
 * Beyond the commit, in Desire's order: join a running play near it (`fight`, joined), else roll a `lane_fight` play when no
 * clear window decides (`fight`, rolled), else the trade rule. Supports keep OHA's team roam until `Ours.SupportLaneFight` is built.
 */
export function OwnsLaneFights(bot: Unit): boolean {
    return Ours.On("CoreLaneFight") && Ours.On("CoreTrade") && CoreLastHit.Applies(bot) && bot.IsAlive() && inLane(bot);
}

function killHpFor(bot: Unit): number {
    return OwnsLaneFights(bot) ? COMMIT_HP : KILL_HP;
}

/** A support whose harass is ours (a bot under CoreLastHit is a core whatever its position). */
function isSupport(bot: Unit): boolean {
    return !CoreLastHit.Applies(bot) && SupportDeny.Harass(bot);
}

/** How far from the bot an enemy hero is a target: attack range, both bounding radii and the role's walk-in. */
function reachOf(bot: Unit): number {
    return bot.GetAttackRange() + bot.GetBoundingRadius() * 2 + (isSupport(bot) ? HARASS_REACH : REACH);
}

/** The enemy hero is swinging at a lane creep: a last-hit or deny attempt. */
function lastHitting(h: Unit): boolean {
    const t = h.GetAttackTarget();
    return t !== undefined && t !== null && !t.IsNull() && t.IsCreep() && !t.IsHero();
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
    const reach = reachOf(bot);
    const support = isSupport(bot);
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const h of bot.GetNearbyHeroes(reach, true, BotMode.None)) {
        if (!valid(h)) continue;
        const d = GetUnitToUnitDistance(bot, h) - (support && lastHitting(h) ? PUNISH_BONUS : 0);
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
    if (ep.play !== undefined && !ep.joined) Plays.End(ep.play, why);
    if (started && why === "losing") recoverTo[pid] = ep.inputs.hp - ep.inputs.targetHp;
    const killed = started && !IsHeroAlive(ep.tpid);
    const thp = killed ? 0 : valid(ep.target) ? ep.target.GetHealth() : ep.thpSeen;
    const i = ep.inputs;
    Telemetry.Event("trade", [
        ["pid", pid],
        ["role", isSupport(bot) ? "support" : "core"],
        ["lf", ep.lf ? 1 : 0],
        ["kind", ep.kind],
        ["tgt", ep.tpid],
        ["play", ep.play?.id],
        ["join", ep.play !== undefined ? (ep.joined ? 1 : 0) : undefined],
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
    Plays.Tick(now);
    if (ep !== undefined && ep.ended) {
        close(bot, ep, `mode_${bot.GetActiveMode()}`, now);
        ep = undefined;
    }
    if (ep !== undefined) {
        const why = keepWhy(bot, ep, now);
        if (why === undefined) return ep.kind === "trade" ? DESIRE_TRADE : DESIRE_KILL;
        close(bot, ep, why, now);
        ep = undefined;
    }
    // A hero that started a play of another context (the rune spawn's) is driven by it (OWNERSHIP H24).
    const mine = Plays.Of(bot);
    if (mine !== undefined && mine.by === bot) return 0;
    const owns = OwnsLaneFights(bot);
    const target = nearestTarget(bot);
    const inputs = target !== undefined ? Gather(bot, target) : undefined;
    const d = inputs !== undefined ? Decide(inputs, false, killHpFor(bot)) : {};
    if (d.kind !== "kill" && owns) {
        const join = joinable(bot);
        if (join !== undefined) return open(bot, "fight", join.target!, now, join, true);
    }
    if (target === undefined || inputs === undefined) return 0;
    if (owns && d.kind !== "kill" && d.respect !== "tower" && d.respect !== "outnumbered") {
        const play = rollFight(bot, target, now);
        if (play !== undefined) return open(bot, "fight", target, now, play, false);
    }
    if (d.kind === undefined) return 0;
    const gap = recoverTo[pid];
    if (d.kind === "trade" && gap !== undefined) {
        if (inputs.hp - inputs.targetHp < gap - 1e-6) return 0;
        recoverTo[pid] = undefined;
    }
    return open(bot, d.kind, target, now);
}

function open(bot: Unit, kind: Kind, target: Unit, now: number, play?: Plays.Play, joined?: boolean): number {
    if (joined) Plays.Join(play!, bot);
    episodes[bot.GetPlayerID()] = {
        kind,
        target,
        tpid: target.GetPlayerID(),
        offeredAt: now,
        lf: OwnsLaneFights(bot),
        hp0: bot.GetHealth(),
        thp0: target.GetHealth(),
        thpSeen: target.GetHealth(),
        inputs: Gather(bot, target),
        primes: 0,
        stepOuts: 0,
        aggro: 0,
        play,
        joined,
    };
    return kind === "trade" ? DESIRE_TRADE : DESIRE_KILL;
}

/**
 * A running play this hero may join: its place near, its target visible and within reach + JOIN_WALK, and the library's hard
 * zeros clear for this hero against that target (HP floor, two down, the target by its tower for a chasing kind) as well as
 * the trade's tower and decline respects. Deterministic: joining is the hero's judgement, the roll was the initiator's.
 */
function joinable(bot: Unit): Plays.Play | undefined {
    if (Plays.Of(bot) !== undefined) return undefined;
    const reach = reachOf(bot) + JOIN_WALK;
    for (const p of Plays.Near(bot.GetLocation(), JOIN_NEAR)) {
        const t = p.target;
        if (p.by === bot || !valid(t) || GetUnitToUnitDistance(bot, t) > reach) continue;
        const r = Decide(Gather(bot, t), false, killHpFor(bot)).respect;
        if (r === "tower" || r === "outnumbered") continue;
        if (Plays.Weigh(Plays.InputsOf({ kind: p.kind, by: bot, target: t, at: t.GetLocation() })).zero !== undefined) continue;
        return p;
    }
    return undefined;
}

/** One lane-fight chance on this target, at most every FIGHT_ROLL_EVERY seconds; the fired play, if any. */
function rollFight(bot: Unit, target: Unit, now: number): Plays.Play | undefined {
    const pid = bot.GetPlayerID();
    const seen = (rolledAt[pid] = rolledAt[pid] ?? {});
    const tpid = target.GetPlayerID();
    const last = seen[tpid];
    if (last !== undefined && now - last < FIGHT_ROLL_EVERY) return undefined;
    seen[tpid] = now;
    return Plays.Roll({ kind: LANE_FIGHT, by: bot, target, at: target.GetLocation() }, now);
}

/** Why a running episode ends now, or undefined to keep it. */
function keepWhy(bot: Unit, ep: Episode, now: number): string | undefined {
    const t: Unit = ep.target;
    if (!IsHeroAlive(ep.tpid)) return "target_dead";
    if (!valid(t)) return "target_lost";
    ep.thpSeen = t.GetHealth();
    if (ep.startedAt === undefined) return now - ep.offeredAt > LOST_AFTER ? "not_taken" : undefined;
    if (ep.kind === "kill") {
        if (now - ep.startedAt > KILL_TIME) return "time";
    } else if (ep.kind === "fight") {
        if (now - ep.startedAt > FIGHT_TIME) return "time";
        if (ep.play !== undefined && !Plays.Active().includes(ep.play)) return "play_end";
        if (FR.HpFraction(bot) < Plays.SETTINGS.HpFloor) return "hp";
        const r = Decide(Gather(bot, ep.target), true, killHpFor(bot)).respect;
        return r === "tower" || r === "outnumbered" ? r : undefined;
    } else {
        if (ep.stepSince !== undefined && now - ep.stepSince > STEP_OUT_LIMIT) return "no_clear";
        const reach = reachOf(bot);
        // A step out moves away from the target on purpose, and the order primed from clear ground walks back in while its
        // cooldown covers the hits.
        const primed = primedAt[bot.GetPlayerID()];
        const walkingIn = primed !== undefined && now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT;
        if (ep.stepSince === undefined && !walkingIn && GetUnitToUnitDistance(bot, ep.target) > reach) return "out_of_reach";
        if (Deficit(ep.hp0, bot.GetHealth(), ep.thp0, ep.target.GetHealth(), bot.GetMaxHealth()) > LOSING_BY) return "losing";
    }
    const d = Decide(Gather(bot, ep.target), true, killHpFor(bot));
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
        if (c.IsNull() || !c.IsAlive()) continue;
        creeps.push(c);
        if (c.GetAttackTarget() === bot) onMe++;
    }
    ep.aggro = math.max(ep.aggro, onMe);
    // A kill window or a fight commits: it attacks whatever the creeps do.
    const commits = ep.kind !== "trade";
    const plan = commits ? "attack" : AggroPlan(now, primedAt[pid], creeps.length);
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
        if (commits) primedAt[pid] = now;
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
        // cil2 (A_on_1 t=776.3, B_on_2 t=377.1): a creep the query listed as alive returned no location; cause not known.
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
 * OHA's farm mode runs a laning core (or, since slice support-spot, a harassing support) off for 1-4 s on its own triggers (`X.ShouldRun`: a trade it judges lost, creep hits,
 * enemy tower proximity at low level, ...). In lane this context decides when its core backs off, so farm GetDesire skips
 * ShouldRun for it (user 03/11/2026; cil4: with only the trade triggers skipped, the tower branches still held cores 330 s).
 */
export function TradeOwnsLaneRun(bot: Unit): boolean {
    return Owns(bot) && inLane(bot);
}

/**
 * Laning's 0.9 last-hit desire must not cut a retreat this context's core is already in (core-time-diagnosis s2: a death
 * within 15 s of such a cut was 4 times as likely), nor a kill or fight it has committed to (lfpchk1: 2 of 8 fights and 1
 * of 6 kills ended in a last hit, t=236 and t=154 at 4.9 s). Trades still give way to it. A predicate on the laning
 * GetDesire (OWNERSHIP H2).
 */
export function LastHitYields(bot: Unit): boolean {
    if (!CoreLastHit.Applies(bot)) return false;
    if (bot.GetActiveMode() === BotMode.Retreat) return true;
    const ep = episodes[bot.GetPlayerID()];
    return ep !== undefined && ep.kind !== "trade" && ep.startedAt !== undefined && !ep.ended;
}

export function Reset(): void {
    for (const k in episodes) episodes[k as unknown as number] = undefined;
    for (const k in recoverTo) recoverTo[k as unknown as number] = undefined;
    for (const k in primedAt) primedAt[k as unknown as number] = undefined;
    for (const k in ownsFrame) ownsFrame[k as unknown as number] = undefined;
    for (const k in rolledAt) rolledAt[k as unknown as number] = undefined;
}
