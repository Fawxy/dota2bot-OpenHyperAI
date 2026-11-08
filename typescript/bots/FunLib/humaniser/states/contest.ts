/**
 * Ours.CoreContest (slice contest-walkin, user 09/11/2026): a melee core walks in from its lane spot for a last hit on a creep
 * dying inside an enemy hero's reach, then walks back. The spot keeps the core out of that reach between attempts (the risk
 * is paid every idle second there); the walk-in pays it only for the attempt, priced in HP before it starts and again on
 * every scan while it runs. Lane-positioning Decisions 04/11/2026: the contest is the last-hit pick's, not a limit of the spot.
 * The pick (states/lane_pick) asks `Far` for a creep beyond its usual MAX_WALK; the laning body releases a running walk-in
 * whose price stops passing (laneFarm `dropLost`) and does not pick that creep again.
 */
import { DamageType, Unit, Vector } from "bots/ts_libs/dota";
import type * as Lib from "bots/FunLib/engine/tasks";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";

/** Melee by attack range, as the lane-positioning reads (lposchk3 `away` misses: 437 melee against 47 ranged). */
export const MELEE_RANGE = 200;
/** The longest walk into range a walk-in commits to, s (`judgement`: about 750 at 300 movement, the depth of an enemy's reach past the spot). */
export const CONTEST_WALK = 2.5;
/** laneTargets' radius for a contesting core: CONTEST_WALK of walking plus melee range, with slack. */
export const RADIUS = 1000;
/** The priced HP may be at most this share of max HP per creep (`judgement`: about one enemy hit and a nuke at level 1-3). */
export const COST_CAP = 0.1;
/** HP share the core must keep after the priced cost (`judgement`; lane aggro's draws gate at 0.45). */
export const HP_FLOOR = 0.5;
/** Seconds of the enemy hero's movement added to its attack reach: it steps in on a walk-in (`judgement`; the spot's REACT_SECS is 1.5 for standing). */
export const STEP_IN = 0.5;
/** A ready nuke counts when the creep lies within its cast range plus this (`judgement`: a hero steps in to cast). */
export const NUKE_SLACK = 200;
/** Enemy heroes further than this from the creep are not priced. */
const QUERY = 1600;
/** Our swing's own time in the zone when the API gives no attack point, s. */
const SWING_DEFAULT = 0.5;

export type Why = "ok" | "cost" | "hp" | "two" | "tower";

/** One enemy hero as the price reads it. */
export interface Threat {
    /** Its distance to the creep. */
    d: number;
    /** Attack range plus both bounding radii plus STEP_IN of its movement: within this of the creep it hits us there. */
    zone: number;
    /** Its attack damage per second on us, after our armour. */
    dps: number;
    /** Its largest ready nuke's damage on us (0: none in range). */
    nuke: number;
}

export interface Price {
    ok: boolean;
    why: Why;
    /** Priced HP as a share of max HP. */
    cost: number;
    /** Enemy heroes whose zone covers the creep. */
    heroes: number;
    /** Seconds the walk-in spends inside the deepest zone. */
    exposure: number;
}

/**
 * The walk-in's price, pure: each enemy whose zone covers the creep hits us for the seconds we stand inside it (walking the
 * zone's depth in and out at `speed`, waiting in range for the creep to become due, and our swing) plus a ready nuke. Two or
 * more such heroes, or the creep inside an enemy tower's ring, refuse it outright.
 */
export function PriceOf(
    this: void,
    threats: Threat[],
    walk: number,
    wait: number,
    swing: number,
    speed: number,
    hp: number,
    maxHp: number,
    tower: boolean,
): Price {
    let damage = 0;
    let heroes = 0;
    let exposure = 0;
    const walkDist = walk * speed;
    for (const h of threats) {
        const depth = h.zone - h.d;
        if (depth <= 0) continue;
        heroes++;
        const inside = (2 * math.min(depth, walkDist)) / math.max(speed, 1) + wait + swing;
        exposure = math.max(exposure, inside);
        damage += h.dps * inside + h.nuke;
    }
    const cost = maxHp > 0 ? damage / maxHp : 1;
    let why: Why = "ok";
    if (tower) why = "tower";
    else if (heroes >= 2) why = "two";
    else if (cost > COST_CAP) why = "cost";
    else if (maxHp <= 0 || (hp - damage) / maxHp < HP_FLOOR) why = "hp";
    return { ok: why === "ok", why, cost, heroes, exposure };
}

/** A melee core under Ours.CoreLastHit with Ours.CoreContest on. */
export function Applies(bot: Unit): boolean {
    if (!Ours.On("CoreContest") || !CoreLastHit.Applies(bot)) return false;
    return bot.GetAttackRange() <= MELEE_RANGE;
}

function alive(u: Unit | undefined): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.GetLocation() !== undefined;
}

function dist(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

/** The largest ready damaging nuke of `enemy` whose cast range (plus NUKE_SLACK) reaches `d`, after our magic resistance. */
function nukeOn(bot: Unit, enemy: Unit, d: number): number {
    let best = 0;
    const mana = enemy.GetMana();
    for (let i = 0; i < 6; i++) {
        const a = enemy.GetAbilityInSlot(i);
        if (a === undefined || a === null || a.IsNull() || a.IsHidden() || a.IsPassive() || a.GetLevel() < 1) continue;
        const raw = a.GetAbilityDamage();
        if (raw <= 0 || a.GetCooldownTimeRemaining() > 0 || a.GetManaCost() > mana) continue;
        if (a.GetCastRange() + NUKE_SLACK < d) continue;
        const kind = (a as unknown as { GetDamageType?(): DamageType }).GetDamageType?.() ?? DamageType.Magical;
        best = math.max(best, bot.GetActualIncomingDamage(raw, kind));
    }
    return best;
}

/** The enemies near `at` as the price reads them. */
export function ThreatsAt(bot: Unit, at: Vector): Threat[] {
    const out: Threat[] = [];
    for (const h of bot.GetNearbyHeroes(QUERY, true, 0)) {
        if (!alive(h)) continue;
        const d = dist(h.GetLocation(), at);
        const zone = h.GetAttackRange() + h.GetBoundingRadius() + bot.GetBoundingRadius() + STEP_IN * h.GetCurrentMovementSpeed();
        const spa = (h as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.() ?? 1.7;
        const dps = bot.GetActualIncomingDamage(h.GetAttackDamage(), DamageType.Physical) / math.max(spa, 0.2);
        out.push({ d, zone, dps, nuke: nukeOn(bot, h, d) });
    }
    return out;
}

function towerAt(bot: Unit, at: Vector): boolean {
    for (const t of bot.GetNearbyTowers(QUERY, true)) {
        if (alive(t) && dist(t.GetLocation(), at) <= LaneSpot.TOWER_RING) return true;
    }
    return false;
}

/** The price of a walk-in for lane target `t` now. */
export function PriceFor(bot: Unit, t: Lib.Verbs.LaneTarget): Price {
    const at = (t.creep as unknown as Unit).GetLocation();
    if (at === undefined) return { ok: false, why: "cost", cost: 1, heroes: 0, exposure: 0 };
    const point = (bot as Unit & { GetAttackPoint?(): number }).GetAttackPoint?.();
    const swing = point !== undefined && point > 0 ? point : SWING_DEFAULT;
    return PriceOf(
        ThreatsAt(bot, at),
        t.walk,
        math.max(0, t.eta - t.walk),
        swing,
        bot.GetCurrentMovementSpeed(),
        bot.GetHealth(),
        bot.GetMaxHealth(),
        towerAt(bot, at),
    );
}

/** A running walk-in per bot: its creep, the price at its pick, and HP then; `refused` is a creep the price released. */
interface Walk {
    creep: Lib.TaskCreep;
    price: Price;
    hp: number;
    t: number;
}
const walks: Record<number, Walk | undefined> = {};
const refused: Record<number, Lib.TaskCreep | undefined> = {};
/** The last refusal logged per bot (creep and why), so ev=contest_skip is written once per creep and reason. */
const skipped: Record<number, { creep: Lib.TaskCreep; why: Why } | undefined> = {};

export function Start(pid: number, creep: Lib.TaskCreep, price: Price, hp: number, now: number): void {
    walks[pid] = { creep, price, hp, t: now };
}

/** The running walk-in on `creep`, if this bot is in one. */
export function Running(pid: number, creep: Lib.TaskCreep): Walk | undefined {
    const w = walks[pid];
    return w !== undefined && w.creep === creep ? w : undefined;
}

/** Ends the walk-in on `creep` (its attempt reported), returning it. */
export function Finish(pid: number, creep: Lib.TaskCreep): Walk | undefined {
    const w = Running(pid, creep);
    if (w !== undefined) walks[pid] = undefined;
    return w;
}

export function Refuse(pid: number, creep: Lib.TaskCreep): void {
    refused[pid] = creep;
}

export function Refused(pid: number, creep: Lib.TaskCreep): boolean {
    return refused[pid] === creep;
}

/** Whether a refusal of `creep` for `why` is new (not logged yet). */
export function NoteSkip(pid: number, creep: Lib.TaskCreep, why: Why): boolean {
    const s = skipped[pid];
    if (s !== undefined && s.creep === creep && s.why === why) return false;
    skipped[pid] = { creep, why };
    return true;
}
