/**
 * De-aggro (slice deaggro, DOCTRINE D5's "a skill to be built"): shed the aggro of an enemy tower or enemy lane creeps that
 * target this hero, by one attack order on a lane creep of ours they would switch to. The order alone sheds it; the attack
 * need not land (user 18/11/2026), so a full-HP creep we cannot hit is a valid target. A lane technique with no caller yet:
 * it decides how, never when (the caller owns that, its doctrine rule and its switch), and never walks (stepping out of a
 * reach is positioning or retreat): only our creeps inside the hero's own attack range are order targets, so the order
 * never moves the hero (as lane_tech's tower drop). Hands the hero back the frame after the order.
 *
 * What it knows (ref `theory/creep-aggro`): a creep keeps a target inside its attack range, so a creep with us inside its
 * reach is `locked` and no order moves it; a creep chasing us switches to a unit of ours within its acquisition range. A tower
 * switches to a unit of ours within its attack range. Only our lane creeps are order targets: whether an order on an allied
 * hero sheds anything is unread.
 *
 *   Read(bot)            who targets the hero now
 *   Plan(attackers, ours) pure: the order target the most attackers would switch to, or why there is none
 *   Shed(bot)            Read + Plan + the order; opens an attempt that Watch closes
 *   Watch(bot)           the open attempt: `pending`, then `ok` / `still_hit` / `stale` / `gone`, logged once as ev=deaggro
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export type Kind = "tower" | "lane";

// Mechanics are the reference's; every number here is `judgement` until a rig reads it.
export const SETTINGS = {
    /** Attackers are looked for this far from the hero (tower reach and a chasing creep's acquisition fit inside). */
    ScanR: 1600,
    /** After the order, the attackers' targets are read for this long; still on us after it: `still_hit`. */
    ConfirmFor: 1.0,
    /** An attempt not watched for this long closes `stale` on the next call (its caller lost the frame). */
    StaleAfter: 0.5,
};

/** One attacker, as plain numbers (Plan is pure). */
export interface AttackerFact {
    kind: Kind;
    x: number;
    y: number;
    /** Tower: its attack range plus its radius. Lane creep: its acquisition range plus its radius (where it looks for a new
     *  target). Plan adds our creep's radius. */
    reach: number;
    /** A creep with us inside its attack range: it will not switch. Never true for a tower. */
    locked: boolean;
}

export interface OwnFact {
    x: number;
    y: number;
    /** Distance from the hero, for the tie-break. */
    d: number;
    /** Its bounding radius (an attacker's reach is to its edge). */
    r: number;
}

export interface PlanResult {
    /** Index into `ours` of the order target, or undefined with `why`. */
    target?: number;
    /** Attackers the target would take (unlocked ones within their reach of it). */
    covers: number;
    locked: number;
    why?: "none" | "locked" | "no_unit";
}

export interface Attacker {
    unit: Unit;
    fact: AttackerFact;
}

function dist(ax: number, ay: number, bx: number, by: number): number {
    const dx = ax - bx;
    const dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
}

function usable(u: Unit | null | undefined): u is Unit {
    return u !== null && u !== undefined && !u.IsNull() && u.IsAlive();
}

/** Pure: our unit the most unlocked attackers would switch to, nearest the hero on a tie. */
export function Plan(attackers: AttackerFact[], ours: OwnFact[]): PlanResult {
    let locked = 0;
    for (const a of attackers) if (a.locked) locked++;
    if (attackers.length === 0) return { covers: 0, locked, why: "none" };
    if (locked === attackers.length) return { covers: 0, locked, why: "locked" };
    let best: number | undefined;
    let bestN = 0;
    for (let i = 0; i < ours.length; i++) {
        const o = ours[i];
        let n = 0;
        for (const a of attackers) if (!a.locked && dist(a.x, a.y, o.x, o.y) <= a.reach + o.r) n++;
        if (n > bestN || (n === bestN && n > 0 && best !== undefined && o.d < ours[best].d)) {
            best = i;
            bestN = n;
        }
    }
    if (best === undefined) return { covers: 0, locked, why: "no_unit" };
    return { target: best, covers: bestN, locked };
}

/** Who targets the hero now: enemy towers and enemy lane creeps whose attack target is it. Each unit is read once. */
export function Read(bot: Unit): Attacker[] {
    const out: Attacker[] = [];
    const here = bot.GetLocation();
    const br = bot.GetBoundingRadius();
    for (const t of bot.GetNearbyTowers(SETTINGS.ScanR, true) ?? []) {
        if (!usable(t) || t.GetAttackTarget() !== bot) continue;
        const at = t.GetLocation();
        out.push({ unit: t, fact: { kind: "tower", x: at.x, y: at.y, reach: t.GetAttackRange() + t.GetBoundingRadius(), locked: false } });
    }
    for (const c of bot.GetNearbyLaneCreeps(SETTINGS.ScanR, true) ?? []) {
        if (!usable(c) || c.GetAttackTarget() !== bot) continue;
        const at = c.GetLocation();
        const cr = c.GetBoundingRadius();
        const locked = dist(at.x, at.y, here.x, here.y) <= c.GetAttackRange() + cr + br;
        out.push({ unit: c, fact: { kind: "lane", x: at.x, y: at.y, reach: c.GetAcquisitionRange() + cr, locked } });
    }
    return out;
}

/** Our lane creeps inside the hero's attack range (to their edge): an order on one never walks the hero. */
function ownCreeps(bot: Unit): Unit[] {
    const out: Unit[] = [];
    const team = bot.GetTeam();
    const reach = bot.GetAttackRange() + bot.GetBoundingRadius();
    for (const c of bot.GetNearbyLaneCreeps(reach + 100, false) ?? []) {
        if (!usable(c) || c.GetTeam() !== team || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        if (GetUnitToUnitDistance(bot, c) <= reach + c.GetBoundingRadius()) out.push(c);
    }
    return out;
}

interface Open {
    orderedAt: number;
    watchedAt: number;
    target: Unit;
    attackers: Attacker[];
    kinds: string;
    covers: number;
    locked: number;
    hp: number;
}

const open: Record<number, Open | undefined> = {};

export function Reset(): void {
    for (const k in open) delete open[k as unknown as number];
}

export type ShedResult = { ordered: true; covers: number; locked: number } | { ordered: false; why: "open" | "none" | "locked" | "no_unit" };

function kindsOf(attackers: Attacker[]): string {
    let t = 0;
    let l = 0;
    for (const a of attackers) if (a.fact.kind === "tower") t++;
    else l++;
    return t > 0 && l > 0 ? "mixed" : t > 0 ? "tower" : "lane";
}

/**
 * Read, plan and give the order (`Action_AttackUnit` with bOnce, as lane_tech's tower drop; it replaces the hero's current
 * order this frame). One attempt per hero at a time: while one is open Shed refuses (`open`); Watch closes it. A `locked` or
 * `no_unit` answer tells the caller an order would do nothing now (a locked creep needs us out of its attack range first;
 * `no_unit` may mean our creep is out of our attack range: both are the caller's move).
 */
export function Shed(bot: Unit): ShedResult {
    const pid = bot.GetPlayerID();
    if (open[pid] !== undefined && Watch(bot) === "pending") return { ordered: false, why: "open" };
    const attackers = Read(bot);
    const ours = ownCreeps(bot);
    const here = bot.GetLocation();
    const ownFacts: OwnFact[] = [];
    for (const c of ours) {
        const at = c.GetLocation();
        ownFacts.push({ x: at.x, y: at.y, d: dist(at.x, at.y, here.x, here.y), r: c.GetBoundingRadius() });
    }
    const attackerFacts: AttackerFact[] = [];
    for (const a of attackers) attackerFacts.push(a.fact);
    const p = Plan(attackerFacts, ownFacts);
    if (p.target === undefined) return { ordered: false, why: p.why ?? "none" };
    const target = ours[p.target];
    bot.Action_AttackUnit(target, true);
    const now = DotaTime();
    open[pid] = {
        orderedAt: now,
        watchedAt: now,
        target,
        attackers,
        kinds: kindsOf(attackers),
        covers: p.covers,
        locked: p.locked,
        hp: bot.GetHealth() / math.max(1, bot.GetMaxHealth()),
    };
    return { ordered: true, covers: p.covers, locked: p.locked };
}

export type WatchResult = "pending" | "ok" | "still_hit" | "gone" | "stale" | undefined;

function close(bot: Unit, o: Open, result: Exclude<WatchResult, "pending" | undefined>, now: number, onUs: number): WatchResult {
    delete open[bot.GetPlayerID()];
    // Unlocked attackers that died or left our sight: off us, but not by a switch.
    let dead = 0;
    for (const a of o.attackers) if (!a.fact.locked && !usable(a.unit)) dead++;
    Telemetry.Event("deaggro", [
        ["pid", bot.GetPlayerID()],
        ["kind", o.kinds],
        ["result", result],
        ["n", o.attackers.length],
        ["lk", o.locked],
        ["cov", o.covers],
        ["left", onUs],
        ["dead", dead],
        ["dt", math.floor((now - o.orderedAt) * 100) / 100],
        ["hp", math.floor(o.hp * 100) / 100],
        ["dhp", math.floor((o.hp - bot.GetHealth() / math.max(1, bot.GetMaxHealth())) * 100) / 100],
    ]);
    return result;
}

/**
 * The open attempt, read each frame by the caller (undefined: none open). `ok` once no unlocked attacker that was on us at the
 * order still targets us (dead or gone counts as off, logged apart as `dead`); `still_hit` if some still do after ConfirmFor; `gone` when the hero died;
 * `stale` when the caller has not watched for StaleAfter.
 */
export function Watch(bot: Unit): WatchResult {
    const o = open[bot.GetPlayerID()];
    if (o === undefined) return undefined;
    const now = DotaTime();
    if (!bot.IsAlive()) return close(bot, o, "gone", now, 0);
    if (now - o.watchedAt > SETTINGS.StaleAfter) return close(bot, o, "stale", now, 0);
    o.watchedAt = now;
    // Locked creeps were never going to switch (Plan did not count them), so they do not hold the attempt open.
    let onUs = 0;
    for (const a of o.attackers) if (!a.fact.locked && usable(a.unit) && a.unit.GetAttackTarget() === bot) onUs++;
    if (onUs === 0) return close(bot, o, "ok", now, 0);
    if (now - o.orderedAt >= SETTINGS.ConfirmFor) return close(bot, o, "still_hit", now, onUs);
    return "pending";
}
