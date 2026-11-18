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
import { BotMode, DamageType, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as CreepAggro from "bots/FunLib/humaniser/creep_aggro";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as SupportDeny from "bots/FunLib/humaniser/states/support_deny";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as PairJoin from "bots/FunLib/humaniser/pair_join";
import * as Plays from "bots/FunLib/humaniser/plays/plays";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";

/**
 * `fight`: a lane fight from the play roll, rolled here or joined from an ally's play (slice lane-fight). `join`: D10's pair
 * join (`Ours.PairJoin`, PairJoin.Joins), a committed attack on the target the pair does best on.
 */
export type Kind = "trade" | "kill" | "fight" | "join";
export type Respect = "low_hp" | "behind" | "outnumbered" | "tower" | "creeps" | "wave" | "burst";

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
    /**
     * Slice trade-safe (`Ours.TradeSafe`, D18's "the threat to me is low"): the threat read's burst on the bot as retreat's stay
     * read counts it (enemy heroes in a SAFE_HORIZON reach, an engaged one over SAFE_ENGAGED), over the bot's current HP.
     * Present only with the switch on; Decide then asks "is it safe?" of it in place of `behind` and the target's tower.
     */
    burst?: number;
    /** With `burst`: the bot's attack point on the target (here, or where it stops at attack range) inside an enemy tower's reach, or a tower attacking the bot. */
    towerOnMe?: boolean;
    /**
     * Slice trade-free (`Ours.TradeFree`, D18's second question): the hit is free (`Free`: the target swings at a lane creep or
     * we outrange it), and each side's kill share over PairJoin's Window (`ko` ours on it, `kt` its on us; read only when not
     * free). Present only with the switch on; Answer then asks "free or favoured?" in place of `gap`.
     */
    free?: boolean;
    ko?: number;
    kt?: number;
    /**
     * Slice trade-free round 2 (D18's third question): a deny the laning body is offered now (Laning.DenyDue). With the switch
     * on, it outbids a free or favoured trade as a due last hit does (user 16/11/2026: deny wins over harass; an enemy caught
     * low is the kill's and the lane fight's, which it does not touch).
     */
    denyDue?: boolean;
    /**
     * Slice hitback-fold (D24): the target damaged this core within HIT_RECENT (unset for a support). Decide does not read it;
     * Exchange does: with it, the hit back's caution bars decide whether the exchange is taken so that retreat waits for it.
     */
    hitting?: boolean;
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
/**
 * Slice trade-landed (`Ours.TradeLanded`): an exchange starts at our first landed hit, so `losing` is judged from just before it
 * (the HP both heroes had on the last frame before it landed, so that hit counts). Until it lands, hits taken while stepping out
 * or walking in end the trade only past this share of max HP (BEHIND_BY's share; h2hhighhit2: 42 of the 50 no-damage `losing`
 * ends had lost under 120 HP). `judgement`.
 */
const UNLANDED_CAP = 0.15;
/**
 * Slice kill-chase (kill-chances step 3b, D19): a running kill is kept while CatchRead says the damage we and the allies on
 * the target can deal before it reaches safety, after closing to attack or cast range, reaches its HP. Safety is its own
 * tower's reach at its speed towards that tower (safeTime); a target not heading there has none in sight, and the horizon
 * is this cap. A fitted fixed window (5.7 s, h2hoha3 kills from 40% HP to death, 80th percentile) ended 94 of 124 kills in
 * the smoke game within 0.3 s while seen: one hero's attacks (30 to 40 a second) do not take a laner's 40% (240 to 290 HP)
 * in it, and the kills it was fitted on had several heroes hitting.
 */
export const CATCH_WINDOW = 30;
/**
 * A kill has no time limit; this logged backstop (`backstop`) only stops a read that never ends (T1's rule, user
 * 18/11/2026: a time limit is a logged backstop only). `judgement`: about five landed kills' length.
 */
const CHASE_BACKSTOP = 30;
/** Within this of the predicted place (past both hulls) the chaser stands on it (`spot_clear` if the hero is not seen). `judgement`: a step. */
const AT_PLACE = 100;
/** Seconds of the target's motion the seen velocity is read over (GetExtrapolatedLocation). */
const VELOCITY_SPAN = 0.5;

/** One hero of ours on the target, as the catch read sees it. */
export interface Hunter {
    /** Distance to the target's place (seen, or the predicted place while unseen). */
    d: number;
    /** Attack range plus both hulls. */
    reach: number;
    /** How fast the distance shrinks: our speed less the target's speed away from us (units/s). */
    close: number;
    /** Attack damage per second on the target, after its armour. */
    dps: number;
    /** Ready damage spells: reach, cast point (s) and damage on the target after its resistances. */
    spells: { range: number; cp: number; dmg: number }[];
}

export interface Catch {
    ok: boolean;
    /** Damage the hunters land within the window. */
    dmg: number;
    /** Seconds until the first of it (math.huge: none). */
    first: number;
}

/** Seconds until a hunter at `d` closing at `close` is within `r` (0 inside it; math.huge when it never closes). */
function arrive(d: number, r: number, close: number): number {
    if (d <= r) return 0;
    return close > 0 ? (d - r) / close : math.huge;
}

/**
 * The catch read (kill-chances step 3b): each hunter's attacks from the moment it is in attack range to the end of `w`,
 * and each ready spell whose cast range it reaches (plus the cast point) within `w`, summed against the target's HP.
 */
export function CatchRead(hunters: Hunter[], thp: number, w: number = CATCH_WINDOW): Catch {
    let dmg = 0;
    let first = math.huge;
    for (const h of hunters) {
        const ta = arrive(h.d, h.reach, h.close);
        if (ta < w) {
            dmg += h.dps * (w - ta);
            first = math.min(first, ta);
        }
        for (const s of h.spells) {
            const ts = arrive(h.d, s.range, h.close) + s.cp;
            if (ts > w) continue;
            dmg += s.dmg;
            first = math.min(first, ts);
        }
    }
    return { ok: dmg >= thp, dmg, first };
}
/**
 * Slice trade-reach (`Ours.KillReach`, D19): a core's commit looks this far past the trade's reach for a hero at the commit bar,
 * JOIN_WALK's "about 2 s of walking" (`judgement`). h2hcurrent1: 13 of 62 side-core hunter-chances never had the low hero in
 * reach and none attacked; 10 were within reach + 400, all within reach + 700.
 */
const KILL_WALK = JOIN_WALK;
/** A pair join commits like a fight and keeps its limit; it reopens at once while PairJoin still answers join. */
const JOIN_TIME = FIGHT_TIME;
/** Reach beyond the bot's attack range (plus both bounding radii) within which a hero is a target. */
const REACH = 100;
/**
 * Slice trade-safe: the threat read the "is it safe?" question asks, the same as retreat's stay read (Retreat SETTINGS Horizon
 * and EngagedWindow; not imported, since retreat's chooser imports a module that imports this one): enemy heroes able to reach
 * the bot within 2 s, a hero that hit us in the last second counted over 6 s. `judgement`, kept equal to retreat's so a trade
 * never opens on a read retreat would leave on.
 */
const SAFE_HORIZON = 2;
const SAFE_ENGAGED = 6;
/**
 * A support's reach instead (judgement): its spot holds it outside the enemy heroes' reach (states/lane_spot, at least 800), so
 * a harass starts with a walk in. 300 is about 1 s of walking, inside the 3 s aggro cooldown the order primes.
 */
const HARASS_REACH = 300;
/**
 * Slice trade-lands (`Ours.TradeLands`, D18; `judgement`): the horizon of "can the hero reach attack range", 1 s of walking as
 * HARASS_REACH assumes plus an attack point. A trade outside range opens only if it can; a taken trade waits for its first
 * attack while it still can.
 */
const WALK_IN = 1.5;
/** Backstop of the wait (a fault, logged as `hold_time`): seconds from the trade's start. */
const HOLD_MAX = 4;
/**
 * A support prefers an enemy hero whose attack target is a lane creep (a last-hit attempt: its swing goes to the creep, not back
 * at us) by counting it this much nearer (judgement).
 */
const PUNISH_BONUS = 300;
const NEAR = 1200;
const CREEP_AGGRO = 500;
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
/** A hit back answers a hero that damaged us within this (s): the threat read's `EngagedRecent`. `judgement`. */
const HIT_RECENT = 1;
/**
 * A hit back walks in this far past the hero's reach (user 12/11/2026: answer a hitter standing just out of reach, on the
 * aggro-free order, which also carries the hero towards its next last hit). Smoke game smoke-hit-back-refusals: 6 of the 7
 * unanswered hitters out of reach stood within 300 of it; the support's HARASS_REACH is the same walk. `judgement`.
 */
const HIT_BACK_WALK = 300;
/**
 * Slice high-hit-back (D24; slice hitback-fold dropped its switch): a hit back opens, and retreat's threat leave waits for it, only at this HP share or
 * more; a running one ends under it less KEEP_HP_SLACK. Threat PackHp's bar (h2hstand1: stands beside two heroes at 50-70% HP
 * cost lives; h2hhitback1's hit back from 50% HP had a hit back in the last 12 s of 14 deaths). `judgement`.
 */
const HIT_BACK_HP = 0.7;
/** A window Desire offered that attack mode did not take within this is logged as lost. */
const LOST_AFTER = 1;

/**
 * Whether a trade (or kill) is on against a target with these inputs, or why not. `running`: the trade is already under way, so
 * the borders get their slack.
 */
export function Decide(i: Inputs, running = false, killHp = KILL_HP): { kind?: Kind; respect?: Respect } {
    const slack = running ? KEEP_HP_SLACK : 0;
    if (i.burst !== undefined) return decideSafe(i, i.burst, running, killHp);
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
 * Slice trade-safe: "is it safe?" asked of the threat read (D18), the first of harass's three questions. Unsafe is a tower on
 * the bot itself, more of them near than us, HP under MIN_HP (the reference's one sourced HP rule) or their burst in reach at
 * Threat StandBurst of our HP or more (D1's "their burst can kill me", LoneStand's bar). Being behind the target on HP and the
 * target alone by its tower are no longer refusals: on the h2h trades HP gap did not predict a lost exchange. The kill keeps
 * the old tower test (a commit chases). Creeps and wave are unchanged.
 */
function decideSafe(i: Inputs, burst: number, running: boolean, killHp: number): { kind?: Kind; respect?: Respect } {
    const slack = running ? KEEP_HP_SLACK : 0;
    if (i.towerOnMe === true) return { respect: "tower" };
    if (i.enemiesNear > i.alliesNear) return { respect: "outnumbered" };
    if (!i.tower && i.targetHp <= killHp && i.hp >= i.targetHp) return { kind: "kill" };
    if (i.hp < MIN_HP - slack) return { respect: "low_hp" };
    if (burst >= Threat.SETTINGS.StandBurst + slack) return { respect: "burst" };
    if (i.hitByCreeps >= MAX_CREEPS_ON_ME) return { respect: "creeps" };
    if (i.enemyCreepsNear > MAX_WAVE + (running ? KEEP_WAVE_SLACK : 0)) return { respect: "wave" };
    return { kind: "trade" };
}

/**
 * Slice trade-free: a hit with no answer coming back. The target's attack target is a lane creep (a last-hit or deny swing), or
 * our attack range is OUTRANGE or more over its, so it must walk in to answer. OUTRANGE is about a third of a second of
 * walking at laning speeds (`judgement`): necrolyte on dragon knight (400) and sniper on zeus (170) are free, oracle on lion
 * (20) and dazzle on necrolyte (75) are not.
 */
const OUTRANGE = 100;
export function Free(targetLastHitting: boolean, range: number, targetRange: number): boolean {
    return targetLastHitting || range >= targetRange + OUTRANGE;
}

/**
 * Harass's second question (slice trade-free, D18): a trade the safe rule allows is taken when the hit is free or the exchange
 * favours us, our kill share over the window beating theirs (PairJoin's estimate). Undefined when the inputs carry no answer
 * (the switch off): the lost trade's `gap` then decides.
 */
function favoured(i: Inputs): boolean | undefined {
    if (i.free === undefined) return undefined;
    return i.free || (i.ko ?? 0) > (i.kt ?? 0);
}

/**
 * Whether questions 2 and 3, or with the switch off the gap a lost trade left, hold a trade Decide allows; its respect: `unfavoured`
 * (neither free nor favoured) or `deny` (a due deny is worth more).
 */
function heldBy(i: Inputs, gap: number | undefined): string | undefined {
    const f = favoured(i);
    if (f !== undefined) return !f ? "unfavoured" : i.denyDue === true ? "deny" : undefined;
    return heldByGap(i, gap) ? "gap" : undefined;
}

/** A trade the HP gap a lost trade left holds: the core has not regained, against the target, what it lost (`recoverTo`). */
function heldByGap(i: Inputs, gap: number | undefined): boolean {
    return gap !== undefined && i.hp - i.targetHp < gap - 1e-6;
}

/**
 * The fresh decision on a target in reach with no trade running, as one answer (the cut kind `trade`, driver core_trade):
 * Decide's kind or respect, or `gap` when a trade is held by the gap a lost trade left (with `Ours.TradeFree`, `unfavoured`
 * when the hit is neither free nor favoured, `deny` when a due deny outbids it).
 */
export function Answer(i: Inputs, killHp: number, gap: number | undefined): string {
    const d = Decide(i, false, killHp);
    const held = d.kind === "trade" ? heldBy(i, gap) : undefined;
    if (held !== undefined) return held;
    return d.kind ?? d.respect ?? "none";
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
    /** Slice chase-log: the target's max HP and hull at the offer (its handle reads null once unseen). */
    tmax: number;
    thull: number;
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
    /** A hit back (Exchange took it): opened on a hero hitting us inside our creeps' aggro, so `wave` and `behind` do not end it. */
    hb?: boolean;
    /** Slice kill-chase: a kill that carries a pair join (D10, group 2) further: opened by its `kill_up`, or the join's own
     *  target already under our kill. It keeps the join's group and its hold over the last hit (review of kill-chase). */
    pair?: boolean;
    /** Slice trade-landed: when our first hit on the target landed, and both heroes' HP on the last keep frame before it (the
     *  exchange's baseline from then); `hpPrev`/`thpPrev` track that frame until it lands. */
    landedAt?: number;
    hpPrev?: number;
    thpPrev?: number;
    hpL?: number;
    thpL?: number;
    /** The bot's GetLastAttackTime when the trade started (GameTime, not DotaTime): an attack fired since raises it. */
    atkSeen?: number;
    /** Slice trade-lands: an attack fired since the start (GetLastAttackTime rose); losing() moves `atkSeen` on, so it is kept here. */
    fired?: boolean;
    /** Telemetry only (`fa`): the episode's first act in Think, a step out of the creeps or an attack order. */
    first?: "step" | "order";
    /** Attack mode's OnEnd ran: the next Desire closes the trade naming the mode that took the bot (OnEnd still reads attack). */
    ended?: boolean;
    /** Slice chase-log: the target's place on its last seen frame, the place it was at about HEADING_SPAN before that
     *  (`seen0`), and the sample `seen` that moves on every HEADING_SPAN. */
    seenLast?: Place;
    seen?: Place;
    seen0?: Place;
    /** Slice kill-chase: the target's velocity on its last seen frame (units/s), and the share of physical and magical damage
     *  that reached it then (its armour and resistance), which the catch read uses while it is unseen. */
    tvx?: number;
    tvy?: number;
    physF?: number;
    magF?: number;
    /** The place the chase walks to while the target is unseen (keepKill's predicted place), and since when it is unseen. */
    chaseAt?: Vector;
    unseenSince?: number;
}

interface Place {
    x: number;
    y: number;
    at: number;
}

/**
 * Slice chase-log: after an episode loses sight of its target (`target_lost`), what follows within CHASE_WATCH s: the first
 * frame the target is seen again (`ph=seen`), its death (`dead`), or neither (`gone`). One `ev=chase ph=lost` line at the loss.
 */
const CHASE_WATCH = 12;
interface Chase {
    kind: Kind;
    tpid: number;
    at: number;
}
const chases: Record<number, Chase | undefined> = {};

/**
 * The enemy hero `pid` if our team sees it now. A hero's handle reads null once it leaves sight (smoke chase-log: every
 * `ph=lost` target's handle was null) and a new one comes back with it, so it is found again by pid.
 */
function seenHero(pid: number): Unit | undefined {
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (h !== undefined && h !== null && !h.IsNull() && !h.IsIllusion() && h.GetPlayerID() === pid && h.IsAlive() && h.CanBeSeen()) return h;
    }
    return undefined;
}

/** The `ev=chase ph=lost` line at a loss of sight, and the watch it opens. */
function chaseLost(bot: Unit, ep: Episode, now: number): void {
    const pid = bot.GetPlayerID();
    if (chases[pid] !== undefined) chaseEnd(bot, chases[pid]!, now, "next", undefined);
    chases[pid] = { kind: ep.kind, tpid: ep.tpid, at: now };
    const info = GetHeroLastSeenInfo(ep.tpid)[0];
    const me = bot.GetLocation();
    const d = info !== undefined ? distXY(me, info.location) : undefined;
    const reach = bot.GetAttackRange() + bot.GetBoundingRadius() + ep.thull;
    const a = ep.seen0;
    const b = ep.seenLast;
    const span = a !== undefined && b !== undefined ? b.at - a.at : 0;
    const hv = span > 0 ? distXY(Vector(a!.x, a!.y, 0), Vector(b!.x, b!.y, 0)) / span : undefined;
    const hd = span > 0 ? math.floor(math.deg(math.atan2(b!.y - a!.y, b!.x - a!.x)) + 0.5) : undefined;
    Telemetry.Event("chase", [
        ["pid", pid],
        ["ph", "lost"],
        ["role", isSupport(bot) ? "support" : "core"],
        ["ek", ep.kind],
        ["tgt", ep.tpid],
        ["dur", ep.startedAt !== undefined ? math.floor((now - ep.startedAt) * 10) / 10 : undefined],
        ["hp", math.floor(frac(bot) * 100) / 100],
        ["thp", math.floor((ep.thpSeen / math.max(1, ep.tmax)) * 100) / 100],
        ["kh", killHpFor(bot)],
        ["x", math.floor(me.x)],
        ["y", math.floor(me.y)],
        ["lx", info !== undefined ? math.floor(info.location.x) : undefined],
        ["ly", info !== undefined ? math.floor(info.location.y) : undefined],
        ["tss", info !== undefined ? math.floor(info.time_since_seen * 10 + 0.5) / 10 : undefined],
        ["d", d !== undefined ? math.floor(d) : undefined],
        ["gap", d !== undefined ? math.floor(d - reach) : undefined],
        ["ms", math.floor(bot.GetCurrentMovementSpeed())],
        ["tms", math.floor(Threat.SeenSpeed(ep.tpid) ?? -1)],
        ["hv", hv !== undefined ? math.floor(hv) : undefined],
        ["hd", hd],
        ["sp", SpellReady.ReadyDamage(bot)],
    ]);
}

/** A running watch's end, if this frame has one: the target seen again, dead, or the watch out of time. */
function chaseTick(bot: Unit, now: number): void {
    const pid = bot.GetPlayerID();
    const c = chases[pid];
    if (c === undefined) return;
    const dead = !IsHeroAlive(c.tpid);
    const seen = dead ? undefined : seenHero(c.tpid);
    const out = now - c.at > CHASE_WATCH;
    if (!dead && seen === undefined && !out) return;
    chaseEnd(bot, c, now, dead ? "dead" : seen !== undefined ? "seen" : "gone", seen);
}

/** The watch's end line: `seen` (with the hero's new handle), `dead`, `gone`, or `next` (a new loss of sight replaced it). */
function chaseEnd(bot: Unit, c: Chase, now: number, ph: string, seen: Unit | undefined): void {
    const pid = bot.GetPlayerID();
    chases[pid] = undefined;
    const ep = episodes[pid];
    Telemetry.Event("chase", [
        ["pid", pid],
        ["ph", ph],
        ["ek", c.kind],
        ["tgt", c.tpid],
        ["dt", math.floor((now - c.at) * 10) / 10],
        ["alive", bot.IsAlive() ? 1 : 0],
        ["d", seen !== undefined && bot.IsAlive() ? math.floor(GetUnitToUnitDistance(bot, seen)) : undefined],
        ["thp", seen !== undefined ? math.floor(frac(seen) * 100) / 100 : undefined],
        ["hp", bot.IsAlive() ? math.floor(frac(bot) * 100) / 100 : undefined],
        ["mode", bot.GetActiveMode()],
        ["onk", ep !== undefined && ep.tpid === c.tpid ? ep.kind : undefined],
    ]);
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
 * Slice fight-safe (D19): the lane fight asks trade-safe's "is it safe?" in place of `behind`. It needs that slice's burst read
 * (Gather fills `burst` only with TradeSafe on), so with TradeSafe off `behind` stays.
 */
function fightSafe(): boolean {
    return Ours.On("FightSafe") && Ours.On("TradeSafe");
}

/**
 * The lane fight's own hard zeros on top of the library's (HP floor, two down, a target by its tower): the decline rule (the
 * other side more near the place) and, without `fightSafe`, the trade's `behind` (the hero well under the target's HP).
 */
export function FightZero(i: Plays.Inputs): string | undefined {
    if (i.theirs > i.ours) return "outnumbered";
    if (!fightSafe() && i.targetHp !== undefined && i.hp < i.targetHp - BEHIND_BY) return "behind";
    return undefined;
}

/**
 * Why this core may not roll or join a lane fight on a target with these inputs, before the roll's own zeros: the target by
 * its tower (a fight chases, so the test harass dropped stays), more of them than us, and with `fightSafe` their burst in
 * reach at Threat StandBurst of our HP or more, PackBurst with two or more of them near (trade-safe's `burst` on the stand's
 * bars: a fight commits and chases, so it is never looser than a stand or a hit back; banked fights opened up to 15 points
 * behind on HP dealt about twice what they took, so the HP gap is not the danger, the burst is). Undefined: a chance may be
 * offered.
 */
export function FightRefusal(i: Inputs, killHp: number): Respect | undefined {
    const r = Decide(i, false, killHp).respect;
    if (i.tower || r === "tower") return "tower";
    if (r === "outnumbered") return r;
    if (!fightSafe() || i.burst === undefined) return undefined;
    const bar = i.enemiesNear >= 2 ? Threat.SETTINGS.PackBurst : Threat.SETTINGS.StandBurst;
    if (i.burst >= bar) return "burst";
    return undefined;
}

/**
 * The lane-fight gate as one answer (the cut's `fg`, the cut kind `trade`'s `fight` action): `kill` when the commit comes
 * first, the core's refusal, the roll's hard zero on `pi`, else `roll`. The roll's weighted draw is not part of it.
 */
export function FightAnswer(i: Inputs, killHp: number, pi: Plays.Inputs): string {
    if (Decide(i, false, killHp).kind === "kill") return "kill";
    return FightRefusal(i, killHp) ?? Plays.Weigh(pi).zero ?? "roll";
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
 * clear window decides (`fight`, rolled), else the trade rule. Slice support-lane-fight (`Ours.SupportLaneFight`, kill-chances
 * S1): a support whose harass is ours too, on the same bars, the role an input (reach, the last-hitting preference).
 */
export function OwnsLaneFights(bot: Unit): boolean {
    const role = CoreLastHit.Applies(bot) ? Ours.On("CoreLaneFight") && Ours.On("CoreTrade") : Ours.On("SupportLaneFight") && isSupport(bot);
    return role && bot.IsAlive() && inLane(bot);
}

/** Whose commit looks past reach (`KillReach`): a core's, and a support's whose lane fights are ours. */
function commitReaches(bot: Unit): boolean {
    return Ours.On("KillReach") && (CoreLastHit.Applies(bot) || OwnsLaneFights(bot));
}

function killHpFor(bot: Unit): number {
    return OwnsLaneFights(bot) ? COMMIT_HP : KILL_HP;
}

/** A support whose harass is ours (a bot under CoreLastHit is a core whatever its position). */
function isSupport(bot: Unit): boolean {
    return !CoreLastHit.Applies(bot) && SupportDeny.Harass(bot);
}

/**
 * Slice trade-lands: whether a hero at `gap` (distance past attack range plus both hulls, 0 or less when in range) gets into range
 * within `horizon` s when the target moves `away` (signed, along the line from us: towards us is negative) and we run at `ms`.
 */
export function Arrives(gap: number, ms: number, away: number, horizon: number): boolean {
    if (gap <= 0) return true;
    const closing = ms - away;
    return closing > 0 && gap <= closing * horizon;
}

/** Slice trade-lands: samples of an enemy hero's place (by pid) a HEADING_SPAN or more apart, newest `s1` and the one before it. */
const heads: Record<number, { s0?: Place; s1?: Place } | undefined> = {};

function noteHeading(target: Unit, now: number): void {
    const pid = target.GetPlayerID();
    const h = (heads[pid] = heads[pid] ?? {});
    if (h.s1 !== undefined && now - h.s1.at < HEADING_SPAN) return;
    const l = target.GetLocation();
    h.s0 = h.s1;
    h.s1 = { x: l.x, y: l.y, at: now };
}

/** The target's speed away from `bot` along the line between them (negative: towards), from its movement since the sample before last; 0 when unknown. */
function awayOf(bot: Unit, target: Unit, now: number): number {
    const s0 = heads[target.GetPlayerID()]?.s0;
    if (s0 === undefined || now - s0.at > HEADING_STALE) return 0;
    const l = target.GetLocation();
    const me = bot.GetLocation();
    const dx = l.x - me.x;
    const dy = l.y - me.y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return 0;
    const dt = now - s0.at;
    return (((l.x - s0.x) * dx + (l.y - s0.y) * dy) / len) / dt;
}

interface ReachRead {
    ok: boolean;
    gap: number;
    away: number;
}

/** Slice trade-lands' read: can `bot` get into attack range of `target` within WALK_IN, from the gap, its speed and the target's heading. */
function reachRead(bot: Unit, target: Unit, now: number): ReachRead {
    noteHeading(target, now);
    const gap = GetUnitToUnitDistance(bot, target) - (bot.GetAttackRange() + bot.GetBoundingRadius() + target.GetBoundingRadius());
    const away = gap > 0 ? awayOf(bot, target, now) : 0;
    return { ok: Arrives(gap, bot.GetCurrentMovementSpeed(), away, WALK_IN), gap, away };
}

/** A trade or hit back on `target` may open: always with the switch off, else when the read says its hit can land. */
function lands(bot: Unit, target: Unit, now: number): boolean {
    return !Ours.On("TradeLands") || reachRead(bot, target, now).ok;
}

/**
 * Slice trade-lands: how a running trade's first-attack wait stands this frame. `wait`: a due deny or a join on another hero
 * does not end it; `time`: the read still says it can reach but HOLD_MAX has run (the end is logged `hold_time`); undefined:
 * not waiting, today's rules apply (off, not started, an attack has fired, or the read says it cannot reach).
 */
function holdState(bot: Unit, ep: Episode, now: number): "wait" | "time" | undefined {
    if (!Ours.On("TradeLands") || ep.kind !== "trade" || ep.startedAt === undefined || ep.fired === true) return undefined;
    if (!reachRead(bot, ep.target, now).ok) return undefined;
    return now - ep.startedAt > HOLD_MAX ? "time" : "wait";
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

/**
 * The nearest enemy hero that hit us within HIT_RECENT: in reach, or up to HIT_BACK_WALK past it while it stands inside our
 * creeps' aggro (user 12/11/2026: answer a paying hitter just out of reach; D24: one hitting from outside it is stepped away from).
 */
function hitBackTarget(bot: Unit): Unit | undefined {
    const reach = reachOf(bot);
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const h of bot.GetNearbyHeroes(reach + HIT_BACK_WALK, true, BotMode.None)) {
        if (!valid(h) || !bot.WasRecentlyDamagedByHero(h, HIT_RECENT)) continue;
        const d = GetUnitToUnitDistance(bot, h);
        if (d >= bestD || (d > reach && !CreepAggro.Paid(bot, h))) continue;
        best = h;
        bestD = d;
    }
    return best;
}

/**
 * The one trade decision on a target (slice hitback-fold, D24 in D18; the cut kind `trade`'s driver): Answer (safe, free or
 * favoured, no due deny). When the target is hitting us (`hitting`), whether we take the exchange as a hit back, the one
 * retreat's threat leave waits for: two caution bars first, our HP at HIT_BACK_HP or more and, with two or more enemy heroes
 * near, their burst under Threat PackBurst of our HP (the two-hero stand's bar; D1's own bars there cost lives, h2hstand1).
 * `trade` or `kill` when taken, else the refusal (`hb_hp`, `hb_burst` or Answer's). A hitter in reach that only the bars
 * refuse still gets Answer's plain trade, which retreat does not wait for.
 */
export function Exchange(i: Inputs, killHp: number, gap: number | undefined): string {
    if (i.hitting === true) {
        if (i.hp < HIT_BACK_HP) return "hb_hp";
        if (i.enemiesNear >= 2 && (i.burst ?? 0) >= Threat.SETTINGS.PackBurst) return "hb_burst";
    }
    return Answer(i, killHp, gap);
}

/**
 * The hero hitting this core (hitBackTarget, up to HIT_BACK_WALK past reach) and Exchange on it. No hitter: undefined.
 */
function hitterExchange(bot: Unit): LuaMultiReturn<[Unit | undefined, string]> {
    const h = hitBackTarget(bot);
    if (h === undefined) return $multi(undefined, "no_hitter");
    // The HP bar before Gather, which reads the threat.
    if (frac(bot) < HIT_BACK_HP) return $multi(h, "hb_hp");
    return $multi(h, Exchange(Gather(bot, h), killHpFor(bot), recoverTo[bot.GetPlayerID()]));
}

/**
 * Whether this core is taking an exchange with a hero hitting it: retreat's threat leave waits while it holds (LeaveWhy's
 * `hitback` stay). A running hit back inside its bars, or a hitter Exchange takes now (retreat leaves 0.17 s after its read
 * goes over, before attack mode can open the episode). Lethal, a tower on us and the heal floor still leave first.
 */
export function Taking(bot: Unit): boolean {
    // Off, nothing opens the hit back, so nothing may hold retreat for one (review of hitback-fold: the rig's off arm).
    if (!Ours.On("CoreTrade") || !CoreLastHit.Applies(bot)) return false;
    const ep = episodes[bot.GetPlayerID()];
    // A running hit back holds only inside its own bars (keepWhy's slack): a hero arriving mid-trade lets D1 decide.
    if (ep !== undefined && ep.hb === true && ep.ended !== true) return valid(ep.target) && hbKeptWhy(Gather(bot, ep.target)) === undefined;
    const [h, a] = hitterExchange(bot);
    return h !== undefined && (a === "trade" || (a === "kill" && !heldUncatchable(bot, h)));
}

/** A running hit back's caution bars, kept with KEEP_HP_SLACK: the reason it ends, or undefined while it holds. */
function hbKeptWhy(g: Inputs): string | undefined {
    if (g.hp < HIT_BACK_HP - KEEP_HP_SLACK) return "hb_hp";
    if (g.enemiesNear >= 2 && (g.burst ?? 0) >= Threat.SETTINGS.PackBurst + KEEP_HP_SLACK) return "hb_burst";
    return undefined;
}

/** Hitters are looked for this far out: past any laning hero's attack range. */
const HITTER_RADIUS = 1600;
/** One `ev=trade_no` per run of unanswered hits: none for the same hero within this (s), as the D24h view's onset. */
const NO_EVERY = 5;
const lastNo: Record<number, number | undefined> = {};

/**
 * Logs why no trade opened this frame while an enemy hero is hitting us (`ev=trade_no`), so the D24h view's unanswered
 * cases have a cause. Always returns 0, the desire of a frame with no trade.
 */
function unanswered(bot: Unit, now: number, why: string, i?: Inputs): number {
    const pid = bot.GetPlayerID();
    const last = lastNo[pid];
    if (last !== undefined && now - last < NO_EVERY) return 0;
    let hitter: Unit | undefined;
    let hd = math.huge;
    for (const h of bot.GetNearbyHeroes(HITTER_RADIUS, true, BotMode.None)) {
        if (!valid(h) || !bot.WasRecentlyDamagedByHero(h, HIT_RECENT)) continue;
        const d = GetUnitToUnitDistance(bot, h);
        if (d < hd) {
            hitter = h;
            hd = d;
        }
    }
    if (hitter === undefined) return 0;
    lastNo[pid] = now;
    const agg = CreepAggro.Paid(bot, hitter);
    const g = i ?? Gather(bot, hitter);
    Telemetry.Event("trade_no", [
        ["pid", pid],
        ["role", isSupport(bot) ? "support" : "core"],
        ["why", why],
        ["tgt", hitter.GetPlayerID()],
        ["d", math.floor(hd)],
        ["reach", math.floor(reachOf(bot))],
        ["har", math.floor(hitter.GetAttackRange())],
        ["agg", agg ? 1 : 0],
        ["hp", math.floor(frac(bot) * 100) / 100],
        ["thp", math.floor(frac(hitter) * 100) / 100],
        ["en", g.enemiesNear],
        ["al", g.alliesNear],
        ["cr", g.enemyCreepsNear],
        ["hc", g.hitByCreeps],
        ["mode", bot.GetActiveMode()],
        ["md", math.floor(bot.GetActiveModeDesire() * 100) / 100],
    ]);
    return 0;
}

/** The core lanes: laning phase for it (transitions/phase) and standing by its own lane; elsewhere OHA's port fights. */
function inLane(bot: Unit): boolean {
    return Phase.LaningHeld(bot) && GetAmountAlongLane(bot.GetAssignedLane(), bot.GetLocation()).distance <= LANE_WIDTH;
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

/**
 * Slice trade-reach: the commit's target for a core, an enemy hero at `killHp` or less within reach + KILL_WALK that Decide
 * calls `kill` on (so not outnumbered, not by its tower, not over our HP), the lowest HP first. Undefined: the trade rule's
 * nearest hero in reach decides as before.
 */
function commitTarget(bot: Unit, killHp: number): LuaMultiReturn<[Unit | undefined, Inputs | undefined]> {
    if (!commitReaches(bot)) return $multi(undefined, undefined);
    let best: Unit | undefined;
    let bestI: Inputs | undefined;
    let bestHp = math.huge;
    for (const h of bot.GetNearbyHeroes(reachOf(bot) + KILL_WALK, true, BotMode.None)) {
        if (!valid(h)) continue;
        const f = frac(h);
        if (f > killHp || f >= bestHp) continue;
        const i = Gather(bot, h);
        if (Decide(i, false, killHp).kind !== "kill") continue;
        best = h;
        bestI = i;
        bestHp = f;
    }
    return $multi(best, bestI);
}

function distXY(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

/**
 * Where the bot attacks `target` from: here when the target is within attack range plus both hulls, else the point on the
 * line to it at that distance from the target (where an attack order stops walking). Slice trade-safe's tower test.
 */
function attackPoint(bot: Unit, target: Unit): Vector {
    const me = bot.GetLocation();
    const at = target.GetLocation();
    const range = bot.GetAttackRange() + bot.GetBoundingRadius() + target.GetBoundingRadius();
    const d = distXY(me, at);
    if (d <= range) return me;
    const f = range / d;
    return Vector(at.x + (me.x - at.x) * f, at.y + (me.y - at.y) * f, me.z);
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
    const safe = Ours.On("TradeSafe");
    let towerOnMe = false;
    const stand = safe ? attackPoint(bot, target) : undefined;
    const reach = LaneConfig.TowerReach();
    for (const t of bot.GetNearbyTowers(reach + 1000, true)) {
        if (!t.IsAlive()) continue;
        if (GetUnitToUnitDistance(bot, t) <= reach || GetUnitToUnitDistance(target, t) <= reach) tower = true;
        if (t.GetAttackTarget() === bot) {
            hitByCreeps += MAX_CREEPS_ON_ME;
            towerOnMe = true;
        }
        if (stand !== undefined && distXY(stand, t.GetLocation()) <= reach) towerOnMe = true;
    }
    const q2 = Ours.On("TradeFree") ? question2(bot, target) : {};
    const hitting = CoreLastHit.Applies(bot) && bot.WasRecentlyDamagedByHero(target, HIT_RECENT) ? true : undefined;
    if (safe) {
        const here = bot.GetLocation();
        const burst = Threat.Read(bot, here, here, SAFE_HORIZON, { engagedWindow: SAFE_ENGAGED }).burst;
        return {
            hp: frac(bot),
            targetHp: frac(target),
            enemiesNear,
            alliesNear: math.max(1, alliesNear),
            enemyCreepsNear,
            hitByCreeps,
            tower,
            burst,
            towerOnMe,
            ...q2,
            hitting,
        };
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
        ...q2,
        hitting,
    };
}

/**
 * Slice kill-chase: the target a kill of this bot last ended `cannot_catch` on. A kill on it reopens only once the catch
 * read says it lands again (smoke2: without this a kill reopened on the next frame, 76 ends at 0.5 s each).
 */
const uncatchable: Record<number, number | undefined> = {};

/** Whether a fresh kill on `target` is held: its last kill ended `cannot_catch` and the read still says so. */
function heldUncatchable(bot: Unit, target: Unit): boolean {
    const pid = bot.GetPlayerID();
    if (uncatchable[pid] !== target.GetPlayerID()) return false;
    const ep: Episode = {
        kind: "kill",
        target,
        tpid: target.GetPlayerID(),
        offeredAt: DotaTime(),
        lf: false,
        hp0: 0,
        thp0: 0,
        tmax: target.GetMaxHealth(),
        thull: target.GetBoundingRadius(),
        thpSeen: target.GetHealth(),
        inputs: undefined as unknown as Inputs,
        primes: 0,
        stepOuts: 0,
        aggro: 0,
    };
    noteChase(ep);
    const place = target.GetLocation();
    if (CatchRead(huntersOf(bot, ep, place, true), target.GetHealth(), safeTime(bot, ep, place)).ok) {
        uncatchable[pid] = undefined;
        return false;
    }
    return true;
}

/** Slice kill-chase: the target Think named with SetTarget is cleared, if it is still the one set (another module's stays). */
function clearTarget(bot: Unit, ep: Episode): void {
    const t = bot.GetTarget();
    if (t === undefined || t === null) return;
    if (t === ep.target || (valid(t) && t.IsHero() && t.GetPlayerID() === ep.tpid) || !valid(t)) bot.SetTarget(undefined as any);
}

function close(bot: Unit, ep: Episode, why: string, now: number): void {
    const pid = bot.GetPlayerID();
    episodes[pid] = undefined;
    if (ep.kind !== "trade") clearTarget(bot, ep);
    if (ep.kind === "kill") uncatchable[pid] = why === "cannot_catch" ? ep.tpid : undefined;
    const started = ep.startedAt !== undefined;
    if (ep.play !== undefined && !ep.joined) Plays.End(ep.play, why);
    if (started && why === "losing") recoverTo[pid] = ep.inputs.hp - ep.inputs.targetHp;
    const killed = started && !IsHeroAlive(ep.tpid);
    const thp = killed ? 0 : valid(ep.target) ? ep.target.GetHealth() : ep.thpSeen;
    const i = ep.inputs;
    // Slice chase-log: the loss of sight and its watch, before the episode's own end line.
    if (why === "target_lost" && Telemetry.IsEnabled()) chaseLost(bot, ep, now);
    Telemetry.Event("trade", [
        ["pid", pid],
        ["role", isSupport(bot) ? "support" : "core"],
        ["lf", ep.lf ? 1 : 0],
        ["kind", ep.kind],
        ["tgt", ep.tpid],
        ["play", ep.play?.id],
        ["join", ep.play !== undefined ? (ep.joined ? 1 : 0) : undefined],
        ["hb", ep.hb === true ? 1 : undefined],
        ["result", started ? (killed ? "kill" : "done") : "lost"],
        ["why", why],
        ["dur", started ? math.floor((now - ep.startedAt!) * 10) / 10 : 0],
        ["hpd", started ? ep.hp0 - bot.GetHealth() : 0],
        ["thpd", started ? ep.thp0 - thp : 0],
        ["ld", started && ep.landedAt !== undefined ? math.floor((ep.landedAt - ep.startedAt!) * 10) / 10 : undefined],
        ["hp", math.floor(i.hp * 100) / 100],
        ["thp", math.floor(i.targetHp * 100) / 100],
        ["en", i.enemiesNear],
        ["al", i.alliesNear],
        ["cr", i.enemyCreepsNear],
        ["pr", ep.primes],
        ["so", ep.stepOuts],
        ["fa", ep.first],
        ["ag", ep.aggro],
        ["mode", bot.GetActiveMode()],
        ["md", math.floor(bot.GetActiveModeDesire() * 100) / 100],
    ]);
    // Slice join-after (shadow): the weighing after a taken join or trade ends.
    if (started) PairJoin.After(bot, ep.kind, why, ep.tpid);
}

/** The cut's cadence (cut kind `trade`): a fresh decision at most every TRADE_CUT_EVERY s, an unchanged answer every TRADE_CUT_KEEP s, to TRADE_CUT_UNTIL (the laning stage; PairJoin's). */
const TRADE_CUT_EVERY = 0.5;
const TRADE_CUT_KEEP = 2;
const TRADE_CUT_UNTIL = 720;
const cutState: Record<number, { at?: number; dec?: string; cutAt?: number } | undefined> = {};

/** Six places: under heldByGap's 1e-6 margin's scale of concern, so a replay on a border decides as the game did (review). */
const round6 = (v: number): number => math.floor(v * 1000000 + 0.5) / 1000000;

/**
 * The `ev=cut kind=trade` fields of the fresh decision on `target` when a line is due (its inputs and answer, driver
 * core_trade), read before Desire acts on it; Desire adds `did` once it has. Undefined when no line is due. Writes only the heading samples `reachRead` keeps.
 */
function cutFields(bot: Unit, target: Unit, i: Inputs, killHp: number, lf: boolean, now: number): Telemetry.Fields<"cut"> | undefined {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || now > TRADE_CUT_UNTIL) return undefined;
    const pid = bot.GetPlayerID();
    const st = (cutState[pid] = cutState[pid] ?? {});
    if (st.at !== undefined && now >= st.at && now - st.at < TRADE_CUT_EVERY) return undefined;
    st.at = now;
    const gap = recoverTo[pid];
    // A line is kept when the trade rule's answer or, for a hitter, Exchange's changes.
    const xa = i.hitting === true ? Exchange(i, killHp, gap) : undefined;
    const dec = Answer(i, killHp, gap);
    const key = xa !== undefined ? `${dec}/${xa}` : dec;
    if (key === st.dec && now - (st.cutAt ?? -math.huge) < TRADE_CUT_KEEP) return undefined;
    st.dec = key;
    st.cutAt = now;
    const pi = lf ? Plays.InputsOf({ kind: LANE_FIGHT, by: bot, target, at: target.GetLocation() }) : undefined;
    const rr = reachRead(bot, target, now);
    return [
        ["pid", pid],
        ["kind", "trade"],
        ["role", isSupport(bot) ? "support" : "core"],
        ["tgt", target.GetPlayerID()],
        ["hp", round6(i.hp)],
        ["thp", round6(i.targetHp)],
        ["en", i.enemiesNear],
        ["ally", i.alliesNear],
        ["cr", i.enemyCreepsNear],
        ["hc", i.hitByCreeps],
        ["tw", i.tower ? 1 : 0],
        ["kh", killHp],
        ["lf", lf ? 1 : 0],
        ["gap", gap !== undefined ? round6(gap) : undefined],
        ["d", math.floor(GetUnitToUnitDistance(bot, target))],
        ["rch", math.floor(reachOf(bot))],
        ["hl", math.floor(bot.GetBoundingRadius() + target.GetBoundingRadius())],
        ["ms", math.floor(bot.GetCurrentMovementSpeed())],
        ["tms", math.floor(target.GetCurrentMovementSpeed())],
        ["aw", math.floor(rr.away)],
        ["lw", rr.ok ? 1 : 0],
        ["tlh", lastHitting(target) ? 1 : 0],
        ["bu", i.burst !== undefined ? round6(i.burst) : undefined],
        ["tm", i.burst !== undefined ? (i.towerOnMe === true ? 1 : 0) : undefined],
        ["ar", math.floor(bot.GetAttackRange())],
        ["tar", math.floor(target.GetAttackRange())],
        ["tme", target.GetAttackTarget() === bot ? 1 : 0],
        ["ko", round6(i.ko ?? shareOn(bot, target))],
        ["kt", round6(i.kt ?? shareOn(target, bot))],
        ["tf", i.free !== undefined ? 1 : undefined],
        ["dn", i.free !== undefined ? (i.denyDue === true ? 1 : 0) : undefined],
        ["dec", dec],
        ["hb", i.hitting === true ? 1 : undefined],
        ["xa", xa],
        ["fg", pi !== undefined ? FightAnswer(i, killHp, pi) : undefined],
        ["fpo", pi?.ours],
        ["fpt", pi?.theirs],
        ["ftd", pi !== undefined ? math.floor(math.min(pi.tower, 99999)) : undefined],
        ["fs", pi !== undefined ? (fightSafe() ? 1 : 0) : undefined],
    ];
}

/** Slice trade-free: question 2's inputs; the two estimates only when the hit is not free. */
function question2(bot: Unit, target: Unit): { free?: boolean; ko?: number; kt?: number; denyDue?: boolean } {
    const free = Free(lastHitting(target), bot.GetAttackRange(), target.GetAttackRange());
    const denyDue = Laning.DenyDue(bot);
    if (free) return { free, denyDue };
    return { free, ko: shareOn(bot, target), kt: shareOn(target, bot), denyDue };
}

/**
 * Slice trade-free-cut: `from`'s estimated damage on `on` over PairJoin's Window (GetEstimatedDamageToTarget, as the join cut's
 * `dm`) over `on`'s HP: one side's kill share in a 1v1 exchange. Logged on the trade cut only; Decide does not read it yet.
 */
function shareOn(from: Unit, on: Unit): number {
    return SpellReady.DamageOn(from, on, PairJoin.SETTINGS.Window) / math.max(1, on.GetHealth());
}

/** What the fresh decision opened (the cut's `did`): no episode, or its kind (`fight` joined from a play is `play`, a hit back `hitback`). */
function didOf(ep: Episode | undefined): string {
    if (ep === undefined) return "none";
    if (ep.kind === "fight") return ep.joined === true ? "play" : "fight";
    return ep.hb === true ? "hitback" : ep.kind;
}

/**
 * The in-lane attack desire, or undefined outside lane (the caller then asks OHA's port). Opens, keeps and ends the
 * bot's trade episode; a window attack mode never took is logged as `lost` with the mode that held the bot.
 */
export function Desire(bot: Unit): number | undefined {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let ep = episodes[pid];
    if (Telemetry.IsEnabled()) chaseTick(bot, now);
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
    // D10 (pair, group 2) comes before every other fight of the lane: a running trade, kill or fight gives way to it, on
    // its own target too (it reopens as the join, so the join's group, ends and last-hit yield hold; review of pair-join-on),
    // bar a kill on that target, which keeps the join's group and yield as `pair`.
    const join = PairJoin.Joins(bot);
    if (ep !== undefined && ep.kind === "trade" && ep.fired !== true && ep.atkSeen !== undefined && bot.GetLastAttackTime() > ep.atkSeen) ep.fired = true;
    // Slice kill-chase: a kill already on the join's own target is the join's answer carried further (it chases; the join
    // lapses Keep after the hit on us stops), so it stays, with the join's group and last-hit hold (`pair`).
    const sameKill = ep !== undefined && ep.kind === "kill" && join !== undefined && join.GetPlayerID() === ep.tpid;
    if (sameKill) ep!.pair = true;
    if (ep !== undefined && ep.kind !== "join" && join !== undefined && !sameKill) {
        // Slice trade-lands: a join on another hero waits for a trade's first attack (a join on its own target passes).
        const hold = join.GetPlayerID() !== ep.tpid ? holdState(bot, ep, now) : undefined;
        if (hold !== "wait") {
            close(bot, ep, hold === "time" ? "hold_time" : "pair_join", now);
            ep = undefined;
        }
    }
    if (ep !== undefined) {
        const why = keepWhy(bot, ep, now, join);
        if (why === undefined) return ep.kind === "trade" ? DESIRE_TRADE : DESIRE_KILL;
        close(bot, ep, why, now);
        // Slice kill-chase: a join whose target reached the kill bar reopens as the kill on it, ahead of the join.
        if (why === "kill_up" && ep.kind === "join" && valid(ep.target)) {
            const d = open(bot, "kill", ep.target, now);
            episodes[pid]!.pair = true;
            return d;
        }
        ep = undefined;
    }
    if (join !== undefined) return open(bot, "join", join, now);
    // A hero in a play with no fight of ours running (one it started in another context, the rune spawn's, or one it
    // joined whose fight already ended) is driven by that play until it ends (OWNERSHIP H24).
    const owns = OwnsLaneFights(bot);
    if (owns && Plays.Of(bot) !== undefined) return unanswered(bot, now, "play");
    const killHp = killHpFor(bot);
    // Slice trade-reach: a hero at the commit bar a short walk away is the target before the nearest one in reach.
    const [committed, ci] = commitTarget(bot, killHp);
    const target = committed ?? nearestTarget(bot);
    const inputs = ci ?? (target !== undefined ? Gather(bot, target) : undefined);
    if (target !== undefined && Ours.On("TradeLands")) noteHeading(target, now);
    const cut = target !== undefined && inputs !== undefined ? cutFields(bot, target, inputs, killHp, owns, now) : undefined;
    const desire = freshDecision(bot, pid, now, owns, target, inputs, killHp);
    if (cut !== undefined) {
        cut.push(["did", didOf(episodes[pid])]);
        Telemetry.Event("cut", cut);
    }
    return desire;
}

/** Desire with no episode open: the trade rule on the nearest hero in reach, a lane fight, a hit back, or nothing. */
function freshDecision(bot: Unit, pid: number, now: number, owns: boolean, target: Unit | undefined, inputs: Inputs | undefined, killHp: number): number {
    const d = inputs !== undefined ? Decide(inputs, false, killHp) : {};
    // Slice kill-chase: a kill the catch read just ended does not reopen on the same target until the read says it lands.
    if (d.kind === "kill" && target !== undefined && heldUncatchable(bot, target)) return hitBack(bot, now, "cannot_catch", inputs);
    if (d.kind !== "kill" && owns) {
        const join = joinable(bot);
        if (join !== undefined) return open(bot, "fight", join.target!, now, join, true);
    }
    if (target === undefined || inputs === undefined) return hitBack(bot, now, "no_target");
    if (owns && d.kind !== "kill" && FightRefusal(inputs, killHp) === undefined) {
        const play = rollFight(bot, target, now);
        if (play !== undefined) return open(bot, "fight", target, now, play, false);
    }
    if (d.kind === "trade" && !lands(bot, target, now)) return unanswered(bot, now, "no_reach", inputs);
    const gap = recoverTo[pid];
    const heldWhy = d.kind === "trade" ? heldBy(inputs, gap) : undefined;
    const held = heldWhy !== undefined;
    if (heldWhy === "deny") return unanswered(bot, now, "deny", inputs);
    if (d.kind === undefined || held) return hitBack(bot, now, d.respect ?? heldWhy ?? "gap", inputs);
    // A trade on a hero that is hitting us is a hit back only when Exchange (its HP and two-hero burst bars) takes it too:
    // retreat waits for it and it ends under those bars. Otherwise it opens as a plain trade.
    const ex = inputs.hitting === true ? Exchange(inputs, killHp, gap) : undefined;
    if (ex === "trade" || ex === "kill") {
        if (d.kind === "trade" && gap !== undefined) recoverTo[pid] = undefined;
        return open(bot, d.kind, target, now, undefined, undefined, true);
    }
    if (d.kind === "trade" && gap !== undefined) recoverTo[pid] = undefined;
    return open(bot, d.kind, target, now);
}

/** The trade rule opened nothing (`why`): a hit back if there is a hitter to answer, else the unanswered hit is logged. */
function hitBack(bot: Unit, now: number, why: string, inputs?: Inputs): number {
    if (!CoreLastHit.Applies(bot)) return unanswered(bot, now, why, inputs);
    const [hb, a] = hitterExchange(bot);
    if (hb === undefined) return unanswered(bot, now, why, inputs);
    if (a !== "trade" && a !== "kill") return unanswered(bot, now, a.startsWith("hb_") ? a : `hb_${a}`);
    if (a === "trade" && !lands(bot, hb, now)) return unanswered(bot, now, "hb_no_reach");
    // Slice kill-chase: the cannot_catch hold covers a hit back's kill too (review of kill-chase: a hitter backing away).
    if (a === "kill" && heldUncatchable(bot, hb)) return unanswered(bot, now, "cannot_catch", inputs);
    return open(bot, a, hb, now, undefined, undefined, true);
}

function open(bot: Unit, kind: Kind, target: Unit, now: number, play?: Plays.Play, joined?: boolean, hb?: boolean): number {
    if (joined) Plays.Join(play!, bot);
    episodes[bot.GetPlayerID()] = {
        kind,
        target,
        tpid: target.GetPlayerID(),
        offeredAt: now,
        lf: OwnsLaneFights(bot),
        hp0: bot.GetHealth(),
        thp0: target.GetHealth(),
        tmax: target.GetMaxHealth(),
        thull: target.GetBoundingRadius(),
        thpSeen: target.GetHealth(),
        inputs: Gather(bot, target),
        primes: 0,
        stepOuts: 0,
        aggro: 0,
        play,
        joined,
        hb,
    };
    return kind === "trade" ? DESIRE_TRADE : DESIRE_KILL;
}

/**
 * A running play this hero may join: its place near, its target visible and within reach + JOIN_WALK, and the library's hard
 * zeros clear for this hero against that target (HP floor, two down, the target by its tower for a chasing kind) as well as
 * its own FightRefusal. Deterministic: joining is the hero's judgement, the roll was the initiator's.
 */
function joinable(bot: Unit): Plays.Play | undefined {
    if (Plays.Of(bot) !== undefined) return undefined;
    const reach = reachOf(bot) + JOIN_WALK;
    for (const p of Plays.Near(bot.GetLocation(), JOIN_NEAR)) {
        const t = p.target;
        if (p.by === bot || !valid(t) || GetUnitToUnitDistance(bot, t) > reach) continue;
        if (FightRefusal(Gather(bot, t), killHpFor(bot)) !== undefined) continue;
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

/** Why a running episode ends now, or undefined to keep it. `join` is this frame's PairJoin.Joins. */
function keepWhy(bot: Unit, ep: Episode, now: number, join: Unit | undefined): string | undefined {
    if (ep.kind === "kill" || ep.kind === "join") return keepKill(bot, ep, now, join);
    const t: Unit = ep.target;
    if (!IsHeroAlive(ep.tpid)) return "target_dead";
    if (!valid(t)) return "target_lost";
    noteSeen(ep, now);
    // Harass's third question, asked every frame of a trade or hit back: a due deny ends it (slice trade-free round 2). A kill
    // or fight keeps going: an enemy caught low is worth more than the deny.
    if (ep.kind === "trade" && Ours.On("TradeFree") && Laning.DenyDue(bot)) {
        const hold = holdState(bot, ep, now);
        if (hold === undefined) return "deny";
        if (hold === "time") return "hold_time";
    }
    if (ep.startedAt === undefined) return now - ep.offeredAt > LOST_AFTER ? "not_taken" : undefined;
    if (ep.kind === "fight") {
        if (now - ep.startedAt > FIGHT_TIME) return "time";
        if (ep.play !== undefined && !Plays.Active().includes(ep.play)) return "play_end";
        if (FR.HpFraction(bot) < Plays.SETTINGS.HpFloor) return "hp";
        const g = Gather(bot, ep.target);
        if (g.tower) return "tower";
        const r = Decide(g, true, killHpFor(bot)).respect;
        return r === "tower" || r === "outnumbered" ? r : undefined;
    } else {
        // Slice trade-reach: a trade whose target has fallen to the commit bar gives way to the kill, which the same frame's
        // fresh decision opens (a trade does not chase; a kill does).
        const kh = killHpFor(bot);
        if (ep.kind === "trade" && frac(t) <= kh && commitReaches(bot) && Decide(Gather(bot, t), false, kh).kind === "kill" && !heldUncatchable(bot, t)) return "kill_up";
        if (ep.stepSince !== undefined && now - ep.stepSince > STEP_OUT_LIMIT) return "no_clear";
        const reach = reachOf(bot) + (ep.hb === true ? HIT_BACK_WALK : 0);
        // A step out moves away from the target on purpose, and the order primed from clear ground walks back in while its
        // cooldown covers the hits.
        const primed = primedAt[bot.GetPlayerID()];
        const walkingIn = primed !== undefined && now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT;
        if (ep.stepSince === undefined && !walkingIn && GetUnitToUnitDistance(bot, ep.target) > reach) return "out_of_reach";
        if (losing(bot, ep, now)) return "losing";
    }
    const g = Gather(bot, ep.target);
    const d = Decide(g, true, killHpFor(bot));
    if (d.kind === undefined) return d.respect;
    // The hit back's caution bars, kept with slack (slice high-hit-back): under them retreat's own rule decides again.
    if (ep.hb === true) return hbKeptWhy(g);
    return undefined;
}

/**
 * Slice chase-log: what the keep decision of a kill or join episode reads (cut kind `keep`). `offered` and `started` are
 * seconds since the offer and the start (absent: not started); `join` is this frame's PairJoin answer against the episode's
 * target; `g` is Gather's on the target, present only where the answer reads it (a seen kill, started, inside its time).
 */
export interface KeepInputs {
    kind: "kill" | "join";
    alive: boolean;
    seen: boolean;
    offered: number;
    started?: number;
    join?: "none" | "same" | "other";
    killHp: number;
    hb: boolean;
    g?: Inputs;
    /** Slice kill-chase, a started kill: the hunters on the target and its HP (seen, or as last seen), for CatchRead. */
    hunters?: Hunter[];
    thpAbs?: number;
    /** A started kill on an unseen target: we stand at its predicted place (`spot_clear`), that place or we inside an enemy
     *  tower's reach, more enemy heroes than ours near, unseen enemies other than the target weighing on the walk there. */
    at?: boolean;
    utower?: boolean;
    uout?: boolean;
    threat?: boolean;
    /** A join on a seen target at the kill bar that Decide calls `kill`: it becomes the kill. */
    killUp?: boolean;
    /** Seconds until the target reaches its own tower's reach at its speed towards it (CATCH_WINDOW when not heading there). */
    safe?: number;
}

/** Why a running kill or join ends now, or undefined to keep it: keepWhy's answer for those kinds, pure over its inputs. */
export function KeepAnswer(k: KeepInputs): string | undefined {
    if (!k.alive) return "target_dead";
    if (k.kind === "join") {
        if (!k.seen) return "target_lost";
        // Slice kill-chase: a join whose target is down to the kill bar hands it to the kill, which chases.
        if (k.killUp === true) return "kill_up";
        // The pair's answer, not the trade's inputs, holds a join: it ends when that answer does (losing, outnumbered, no
        // ally hit within Keep) or names another target, which the same frame opens.
        if (k.join === "none") return "pair_end";
        if (k.join === "other") return "retarget";
        if (k.started === undefined) return k.offered > LOST_AFTER ? "not_taken" : undefined;
        return k.started > JOIN_TIME ? "time" : undefined;
    }
    if (k.started === undefined) {
        if (!k.seen) return "target_lost";
        return k.offered > LOST_AFTER ? "not_taken" : undefined;
    }
    // Slice kill-chase: no time limit; the backstop is logged so a read that never ends shows.
    if (k.started > CHASE_BACKSTOP) return "backstop";
    if (k.seen) {
        const g = k.g!;
        // A running kill ends by the target's tower, as at its open (the safe rule's harass would keep it as a trade).
        if (g.tower) return "tower";
        const d = Decide(g, true, k.killHp);
        if (d.kind === undefined) return d.respect;
        // The hit back's caution bars, kept with slack (slice high-hit-back): under them retreat's own rule decides again.
        if (k.hb) {
            const hb = hbKeptWhy(g);
            if (hb !== undefined) return hb;
        }
    } else {
        // The creep's rule (ref theory/fight-chase "Fog"): at the place it should be and not there, the trail is cold.
        if (k.at === true) return "spot_clear";
        if (k.utower === true) return "tower";
        if (k.uout === true) return "outnumbered";
        if (k.threat === true) return "threat";
    }
    if (k.hunters !== undefined && k.thpAbs !== undefined && !CatchRead(k.hunters, k.thpAbs, k.safe).ok) return "cannot_catch";
    return undefined;
}

const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

/**
 * Seconds until the target at `place` is inside its own nearest standing tower's reach, at its speed towards that tower
 * (its seen velocity; unseen and never seen moving, its last read speed straight there). CATCH_WINDOW when it is not
 * heading there: no safety in sight.
 */
function safeTime(bot: Unit, ep: Episode, place: Vector): number {
    const theirs = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    let best: Vector | undefined;
    let bestD = math.huge;
    for (const id of TOWER_IDS) {
        const t = GetTower(theirs, id);
        if (t === undefined || t === null || !t.IsAlive()) continue;
        const d = distXY(t.GetLocation(), place);
        if (d < bestD) {
            bestD = d;
            best = t.GetLocation();
        }
    }
    if (best === undefined) return CATCH_WINDOW;
    const left = bestD - LaneConfig.TowerReach();
    if (left <= 0) return 0;
    let v: number;
    if (ep.tvx === undefined) v = Threat.SeenSpeed(ep.tpid) ?? Threat.SETTINGS.MissingSpeed;
    else v = (ep.tvx * (best.x - place.x) + (ep.tvy ?? 0) * (best.y - place.y)) / math.max(1, bestD);
    return v > 0 ? math.min(CATCH_WINDOW, left / v) : CATCH_WINDOW;
}

/** A unit's attack damage per second before armour (GetSecondsPerAttack is on every hero handle). */
function rawDps(u: Unit): number {
    const spa = (u as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.();
    return spa !== undefined && spa > 0 ? u.GetAttackDamage() / spa : 0;
}

/** The share of damage of type `dtype` that reaches the target, from its last seen frame's factors. */
function factorFor(ep: Episode, dtype: number): number {
    if (dtype === DamageType.Pure) return 1;
    return dtype === DamageType.Physical ? (ep.physF ?? 1) : (ep.magF ?? 1);
}

/** The target's speed away from `u` (its velocity along the line from `u` to `place`; unseen, its last read speed). */
function awaySpeed(ep: Episode, u: Unit, place: Vector, seen: boolean): number {
    const me = u.GetLocation();
    const dx = place.x - me.x;
    const dy = place.y - me.y;
    const n = math.sqrt(dx * dx + dy * dy);
    if (n < 1) return 0;
    if (!seen && ep.tvx === undefined) return Threat.SeenSpeed(ep.tpid) ?? Threat.SETTINGS.MissingSpeed;
    return ((ep.tvx ?? 0) * dx + (ep.tvy ?? 0) * dy) / n;
}

/** One hero of ours as a hunter on the episode's target at `place`. */
function hunterOf(ep: Episode, u: Unit, place: Vector, seen: boolean): Hunter {
    const spells: { range: number; cp: number; dmg: number }[] = [];
    for (const s of SpellReady.ReadySpells(u)) spells.push({ range: s.range, cp: s.cp, dmg: s.dmg * factorFor(ep, s.dtype) });
    return {
        d: distXY(u.GetLocation(), place),
        reach: u.GetAttackRange() + u.GetBoundingRadius() + ep.thull,
        close: u.GetCurrentMovementSpeed() - awaySpeed(ep, u, place, seen),
        dps: rawDps(u) * (ep.physF ?? 1),
        spells,
    };
}

/** The bot and every ally of ours alive with a kill or join on the same target: the catch read's hunters. */
function huntersOf(bot: Unit, ep: Episode, place: Vector, seen: boolean): Hunter[] {
    const out = [hunterOf(ep, bot, place, seen)];
    const me = bot.GetPlayerID();
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (a === undefined || a === null || a.IsNull() || !a.IsAlive() || a.IsIllusion() || a.GetPlayerID() === me) continue;
        const o = episodes[a.GetPlayerID()];
        if (o === undefined || o.ended === true || o.tpid !== ep.tpid || (o.kind !== "kill" && o.kind !== "join")) continue;
        out.push(hunterOf(ep, a, place, seen));
    }
    return out;
}

/** A seen frame of a kill's target: its velocity and the damage factors the unseen read reuses. */
function noteChase(ep: Episode): void {
    const t = ep.target;
    const l = t.GetLocation();
    const x = t.GetExtrapolatedLocation(VELOCITY_SPAN);
    ep.tvx = (x.x - l.x) / VELOCITY_SPAN;
    ep.tvy = (x.y - l.y) / VELOCITY_SPAN;
    ep.physF = t.GetActualIncomingDamage(100, DamageType.Physical) / 100;
    ep.magF = t.GetActualIncomingDamage(100, DamageType.Magical) / 100;
}

/**
 * An unseen target's predicted place: our team's last sighting moved on by its last seen velocity times the time unseen,
 * capped at its last read speed (the step 3 design, user 18/11/2026). Undefined without a sighting.
 */
function predictedPlace(ep: Episode): Vector | undefined {
    const info = GetHeroLastSeenInfo(ep.tpid)[0];
    if (info === undefined) return undefined;
    const l = info.location;
    const tss = info.time_since_seen;
    const vx = ep.tvx ?? 0;
    const vy = ep.tvy ?? 0;
    const v = math.sqrt(vx * vx + vy * vy);
    const cap = Threat.SeenSpeed(ep.tpid) ?? Threat.SETTINGS.MissingSpeed;
    const f = v > cap && v > 0 ? cap / v : 1;
    return Vector(l.x + vx * f * tss, l.y + vy * f * tss, l.z);
}

/** An enemy tower whose reach covers `a` or `b`. */
function towerCovers(bot: Unit, a: Vector, b: Vector): boolean {
    const reach = LaneConfig.TowerReach();
    for (const t of bot.GetNearbyTowers(1600, true)) {
        if (!t.IsAlive()) continue;
        const tl = t.GetLocation();
        if (distXY(tl, a) <= reach || distXY(tl, b) <= reach) return true;
    }
    return false;
}

/** The unseen-target half of a kill's keep reads: at the place, tower, numbers, and unseen enemies other than it on the walk. */
function unseenReads(bot: Unit, ep: Episode, place: Vector, k: KeepInputs): void {
    const here = bot.GetLocation();
    // Standing on the place, not in attack range of it: an unseen hero in our range is behind trees or up a ramp (32 of
    // 222 losses), which is what the chase walks past.
    k.at = distXY(here, place) <= bot.GetBoundingRadius() + ep.thull + AT_PLACE;
    k.utower = towerCovers(bot, here, place);
    let enemies = distXY(here, place) <= NEAR ? 1 : 0;
    for (const h of bot.GetNearbyHeroes(NEAR, true, BotMode.None)) if (valid(h)) enemies++;
    let allies = 0;
    for (const h of bot.GetNearbyHeroes(NEAR, false, BotMode.None)) if (h.IsAlive() && !h.IsIllusion()) allies++;
    k.uout = enemies > math.max(1, allies);
    // The target itself is left out: its own weight would count a known low hero as the danger (review of kill-chase).
    const r = Threat.Read(bot, here, place, Threat.SETTINGS.GateHorizon, { exclude: ep.tpid });
    k.threat = r.mpids.length > 0 && r.missing >= Threat.SETTINGS.MissingRefuse;
}

/** keepWhy for a kill or join: KeepAnswer on this frame's reads, the keep cut beside it. */
function keepKill(bot: Unit, ep: Episode, now: number, join: Unit | undefined): string | undefined {
    const alive = IsHeroAlive(ep.tpid);
    // Slice kill-chase: a fogged hero's handle reads null and a new one comes back with sight, so it is found again by pid.
    if (alive && !valid(ep.target)) {
        const h = seenHero(ep.tpid);
        if (h !== undefined) ep.target = h;
    }
    const seen = alive && valid(ep.target);
    if (seen) {
        noteSeen(ep, now);
        if (ep.kind === "kill") noteChase(ep);
        ep.unseenSince = undefined;
    } else if (alive && ep.kind === "kill" && ep.startedAt !== undefined && ep.unseenSince === undefined) {
        // The loss of sight is logged where the kill keeps going past it (slice chase-log's watch, now on a running chase).
        ep.unseenSince = now;
        if (Telemetry.IsEnabled()) chaseLost(bot, ep, now);
    }
    const k: KeepInputs = {
        kind: ep.kind as "kill" | "join",
        alive,
        seen,
        offered: now - ep.offeredAt,
        started: ep.startedAt !== undefined ? now - ep.startedAt : undefined,
        join: ep.kind === "join" ? (join === undefined ? "none" : join === ep.target ? "same" : "other") : undefined,
        killHp: killHpFor(bot),
        hb: ep.hb === true,
    };
    ep.chaseAt = undefined;
    if (ep.kind === "join" && seen) {
        const kh = k.killHp;
        k.killUp = frac(ep.target) <= kh && Decide(Gather(bot, ep.target), false, kh).kind === "kill" && !heldUncatchable(bot, ep.target);
    }
    if (ep.kind === "kill" && alive && k.started !== undefined && k.started <= CHASE_BACKSTOP) {
        const place = seen ? ep.target.GetLocation() : predictedPlace(ep);
        if (seen) k.g = Gather(bot, ep.target);
        if (place !== undefined) {
            if (!seen) {
                ep.chaseAt = place;
                unseenReads(bot, ep, place, k);
            }
            k.hunters = huntersOf(bot, ep, place, seen);
            k.thpAbs = seen ? ep.target.GetHealth() : ep.thpSeen;
            k.safe = safeTime(bot, ep, place);
        } else if (!seen) {
            // No sighting to chase towards.
            k.at = true;
        }
    }
    const why = KeepAnswer(k);
    keepCut(bot, ep, k, why, now);
    return why;
}

/** Seconds between the two places a seen target's heading is read from (`hv`, `hd` on ev=chase). */
const HEADING_SPAN = 0.5;
/** A heading sample older than this is not a heading (a target seen again after a gap). */
const HEADING_STALE = 1.5;

/** A seen frame of the episode's target: its HP, place and the place HEADING_SPAN or more before (its heading at a loss). */
function noteSeen(ep: Episode, now: number): void {
    const t = ep.target;
    ep.thpSeen = t.GetHealth();
    const l = t.GetLocation();
    if (ep.seen === undefined || now - ep.seen.at >= HEADING_SPAN) {
        ep.seen0 = ep.seen;
        ep.seen = { x: l.x, y: l.y, at: now };
    }
    ep.seenLast = { x: l.x, y: l.y, at: now };
}

/** The keep cut's cadence: a keep at most every KEEP_CUT_EVERY s per hero; every end. */
const KEEP_CUT_EVERY = 0.5;
const keepCutAt: Record<number, number | undefined> = {};

/** Our hero's distance to the target's place: seen, its place; unseen, our team's last sighting. Undefined when neither reads. */
function chaseDistance(bot: Unit, ep: Episode, seen: boolean): number | undefined {
    if (seen) return GetUnitToUnitDistance(bot, ep.target);
    const info = GetHeroLastSeenInfo(ep.tpid)[0];
    return info !== undefined ? distXY(bot.GetLocation(), info.location) : undefined;
}

/**
 * `ev=cut kind=keep`: KeepAnswer's inputs and answer (`dec`, `keep` for none) for a kill or join, driver core_keep; beside them
 * the chase's terms that nothing reads yet (kill-chances step 3b): distance, both speeds, our attack range and hulls, our
 * ready damage spells, and while unseen the last sighting. Reads only.
 */
function keepCut(bot: Unit, ep: Episode, k: KeepInputs, why: string | undefined, now: number): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || now > TRADE_CUT_UNTIL) return;
    const pid = bot.GetPlayerID();
    const last = keepCutAt[pid];
    if (why === undefined && last !== undefined && now >= last && now - last < KEEP_CUT_EVERY) return;
    keepCutAt[pid] = now;
    const g = k.g;
    const info = !k.seen && k.alive ? GetHeroLastSeenInfo(ep.tpid)[0] : undefined;
    const d = k.alive ? chaseDistance(bot, ep, k.seen) : undefined;
    const c = k.hunters !== undefined && k.thpAbs !== undefined ? CatchRead(k.hunters, k.thpAbs, k.safe) : undefined;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "keep"],
        ["role", isSupport(bot) ? "support" : "core"],
        ["tgt", ep.tpid],
        ["ek", k.kind],
        ["alv", k.alive ? 1 : 0],
        ["sn", k.seen ? 1 : 0],
        ["oa", round6(k.offered)],
        ["sa", k.started !== undefined ? round6(k.started) : undefined],
        ["jn", k.join],
        ["kh", k.killHp],
        ["hb", k.hb ? 1 : undefined],
        ["hp", g !== undefined ? round6(g.hp) : undefined],
        ["thp", g !== undefined ? round6(g.targetHp) : undefined],
        ["en", g?.enemiesNear],
        ["ally", g?.alliesNear],
        ["cr", g?.enemyCreepsNear],
        ["hc", g?.hitByCreeps],
        ["tw", g !== undefined ? (g.tower ? 1 : 0) : undefined],
        ["bu", g?.burst !== undefined ? round6(g.burst) : undefined],
        ["tm", g?.burst !== undefined ? (g.towerOnMe === true ? 1 : 0) : undefined],
        ["dec", why ?? "keep"],
        ["d", d !== undefined ? math.floor(d) : undefined],
        ["ar", math.floor(bot.GetAttackRange())],
        ["hl", math.floor(bot.GetBoundingRadius() + (k.seen ? ep.target.GetBoundingRadius() : 0))],
        ["ms", math.floor(bot.GetCurrentMovementSpeed())],
        ["tms", k.seen ? math.floor(ep.target.GetCurrentMovementSpeed()) : math.floor(Threat.SeenSpeed(ep.tpid) ?? -1)],
        ["sp", SpellReady.ReadyDamage(bot)],
        ["lx", info !== undefined ? math.floor(info.location.x) : undefined],
        ["ly", info !== undefined ? math.floor(info.location.y) : undefined],
        ["tss", info !== undefined ? math.floor(info.time_since_seen * 10 + 0.5) / 10 : undefined],
        ["chu", k.hunters !== undefined ? huntersText(k.hunters) : undefined],
        ["cth", k.thpAbs !== undefined ? math.floor(k.thpAbs + 0.5) : undefined],
        ["cdm", c !== undefined ? math.floor(c.dmg + 0.5) : undefined],
        ["cft", c !== undefined ? (c.first === math.huge ? -1 : round6(c.first)) : undefined],
        ["csf", k.safe !== undefined ? round6(k.safe) : undefined],
        ["uat", bit(k.at)],
        ["utw", bit(k.utower)],
        ["uou", bit(k.uout)],
        ["uth", bit(k.threat)],
        ["kup", bit(k.killUp)],
    ]);
}

const bit = (b: boolean | undefined): number | undefined => (b === undefined ? undefined : b ? 1 : 0);
const r1 = (v: number): number => math.floor(v * 10 + 0.5) / 10;

/** The hunters as the keep cut logs them (`chu`): enough to replay CatchRead. */
function huntersText(hs: Hunter[]): string {
    const out: string[] = [];
    for (const h of hs) {
        const sp: string[] = [];
        for (const s of h.spells) sp.push(`${r1(s.range)}:${math.floor(s.cp * 100 + 0.5) / 100}:${r1(s.dmg)}`);
        out.push([r1(h.d), r1(h.reach), r1(h.close), r1(h.dps), sp.join("/")].join(","));
    }
    return out.join(";");
}

/**
 * Whether a running trade or hit back has turned against the core. Off (`Ours.TradeLanded`): Deficit from the start over
 * LOSING_BY. On: before our first hit lands, Deficit from the start over UNLANDED_CAP; from the landing, Deficit from the frame
 * before it over LOSING_BY. A ranged hit counts from its firing, its projectile still in the air.
 */
function losing(bot: Unit, ep: Episode, now: number): boolean {
    const hp = bot.GetHealth();
    const thp = ep.target.GetHealth();
    const max = bot.GetMaxHealth();
    if (!Ours.On("TradeLanded")) return Deficit(ep.hp0, hp, ep.thp0, thp, max) > LOSING_BY;
    // Our first hit: an attack fired at the target since the start (GetLastAttackTime rises when it fires, on GameTime's
    // clock, so it is compared with its own value at the start). The enemy's WasRecentlyDamagedByHero(bot) read false on
    // every landed hit in the rig (drill retreat-hitback tl1).
    const fired = bot.GetLastAttackTime();
    const rose = ep.atkSeen !== undefined && fired > ep.atkSeen;
    if (rose) ep.atkSeen = fired;
    const at = bot.GetAttackTarget();
    if (ep.landedAt === undefined && rose && at !== null && at.IsHero() && at.GetPlayerID() === ep.tpid) {
        ep.landedAt = now;
        ep.hpL = ep.hpPrev ?? ep.hp0;
        ep.thpL = ep.thpPrev ?? ep.thp0;
    }
    if (ep.landedAt === undefined) {
        ep.hpPrev = hp;
        ep.thpPrev = thp;
        return Deficit(ep.hp0, hp, ep.thp0, thp, max) > UNLANDED_CAP;
    }
    return Deficit(ep.hpL!, hp, ep.thpL!, thp, max) > LOSING_BY;
}

/** Slice chase-log (ev=cast): the hero's running episode, its kind and target. Reads only. */
export function EpisodeOf(pid: number): { kind: Kind; tpid: number; target: Unit; at: number } | undefined {
    const ep = episodes[pid];
    return ep === undefined || ep.ended === true ? undefined : { kind: ep.kind, tpid: ep.tpid, target: ep.target, at: ep.offeredAt };
}

// Slice join-hits: PairJoin reads a partner's open episode and this module's refusal; it cannot import this module.
PairJoin.SetReaders({ episodeOf: EpisodeOf, refusal: (bot, target) => FightRefusal(Gather(bot, target), killHpFor(bot)) });

/** A pair join (D10) is open for this hero, or a kill carrying one (`pair`): the arbiter's pair group (2). Reads only. */
export function Joining(bot: Unit): boolean {
    const ep = episodes[bot.GetPlayerID()];
    return ep !== undefined && ep.ended !== true && (ep.kind === "join" || ep.pair === true);
}

/** A trade, kill, fight or join episode is open for this hero (Desire returns its desire in attack mode); reads only. */
export function Running(bot: Unit): boolean {
    const ep = episodes[bot.GetPlayerID()];
    return ep !== undefined && ep.ended !== true;
}

/** Whether this frame's GetDesire took our arm; mode_attack_generic's Think runs ours when true, OHA's port otherwise. */
export function OwnsFrame(bot: Unit): boolean {
    return ownsFrame[bot.GetPlayerID()] === true;
}

export function Think(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const ep = episodes[pid];
    if (ep === undefined) return;
    if (!valid(ep.target)) {
        // Slice kill-chase: an unseen kill's target is walked after to its predicted place (the creep's rule). OHA's casts
        // read GetTarget, so the stale handle is cleared (review of kill-chase); sight back sets it again.
        if (ep.kind !== "trade") clearTarget(bot, ep);
        if (ep.kind === "kill" && ep.chaseAt !== undefined) bot.Action_MoveToLocation(ep.chaseAt);
        return;
    }
    const now = DotaTime();
    // Slice kill-chase (step 3 design, user 18/11/2026): OHA's hero files cast at GetTarget under J.IsGoingOnSomeone, so a
    // committed episode names its target there.
    if (ep.kind !== "trade") bot.SetTarget(ep.target);
    if (ep.startedAt === undefined) {
        ep.startedAt = now;
        ep.atkSeen = bot.GetLastAttackTime();
        PairJoin.Reopened(bot);
    }
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
        ep.first = ep.first ?? "step";
        bot.Action_MoveToLocation(stepOutPoint(bot, creeps));
        return;
    }
    ep.stepSince = undefined;
    ep.first = ep.first ?? "order";
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
 * within 15 s of such a cut was 4 times as likely), nor a kill or fight this context's lane fights committed to (lfpchk1:
 * 2 of 8 fights ended in a last hit at 4.9 s, t=154 and t=236; kills by the same reasoning, `judgement`). Trades still
 * give way to it, as does a commit with Ours.CoreLaneFight off. A predicate on the laning GetDesire (OWNERSHIP H2). Slice
 * support-lane-fight: a support whose lane fights are ours is held by its kill, fight or join the same way (D18: a due last
 * hit or deny never outbids a kill); its retreat is left as it was.
 */
export function LastHitYields(bot: Unit): boolean {
    if (!CoreLastHit.Applies(bot)) return OwnsLaneFights(bot) && episodeHolds(episodes[bot.GetPlayerID()]);
    if (bot.GetActiveMode() === BotMode.Retreat) return true;
    return episodeHolds(episodes[bot.GetPlayerID()]);
}

/** A started kill, fight or join that is not ending: above the last hit. */
function episodeHolds(ep: Episode | undefined): boolean {
    // A pair join (D10, group 2) is above the last hit (D11, group 3) whoever owns the lane fights.
    return ep !== undefined && (ep.lf || ep.kind === "join" || ep.pair === true) && ep.kind !== "trade" && ep.startedAt !== undefined && !ep.ended;
}

/** When this bot last gave an attack order on an enemy hero from a trade (lane_aggro shares the 3 s draw clock). */
export function PrimedAt(pid: number): number | undefined {
    return primedAt[pid];
}

/** Another lane module gave an attack order on an enemy hero: the trade's aggro-free plan counts it as its prime. */
export function NotePrimed(pid: number, t: number): void {
    primedAt[pid] = t;
}

export function Reset(): void {
    for (const k in episodes) episodes[k as unknown as number] = undefined;
    for (const k in recoverTo) recoverTo[k as unknown as number] = undefined;
    for (const k in primedAt) primedAt[k as unknown as number] = undefined;
    for (const k in ownsFrame) ownsFrame[k as unknown as number] = undefined;
    for (const k in rolledAt) rolledAt[k as unknown as number] = undefined;
    for (const k in lastNo) lastNo[k as unknown as number] = undefined;
    for (const k in cutState) cutState[k as unknown as number] = undefined;
    for (const k in chases) chases[k as unknown as number] = undefined;
    for (const k in keepCutAt) keepCutAt[k as unknown as number] = undefined;
    for (const k in heads) heads[k as unknown as number] = undefined;
    for (const k in uncatchable) uncatchable[k as unknown as number] = undefined;
}
