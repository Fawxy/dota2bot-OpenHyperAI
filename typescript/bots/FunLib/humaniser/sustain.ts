/**
 * Sustain: one decision for HP and mana in lane (design docs/proposals/2026-11-19-sustain-design.md in the master repo, D6,
 * D1's kill line). `Decide` is pure over `Inputs`: no unit handles, no game calls, so a logged cut replays offline. One
 * function for all five positions.
 *
 * An item is data, never a rule: `Gather` (a later step) reads what one use restores, over how long, whether hero damage
 * ends it, whether it needs a tree, refills or can be given, from the item and its modifier at run time. The rules read
 * only those properties. An instant HP item (wand, stick, faerie fire) is kept for rule 1 and counts in `reachable`.
 *
 * Rules, first match (design section 2): 1 survive, 2 cannot stay, 3 top up, 4 mana, 5 buy ahead, 6 give.
 */
import { SETTINGS as RetreatSettings } from "bots/FunLib/humaniser/retreat";
import { SETTINGS as ThreatSettings } from "bots/FunLib/humaniser/threat";

export type Kind = "none" | "use" | "step_out_use" | "give" | "buy" | "home";

/** Every number the decision owns, with its source. The kill line's floor (`HealFloor`) and `HealUntil` are retreat's, the burst bar (`StandBurst`) the threat read's: read at call time, not copied. */
export const BARS = {
    /** Rule 3's top-up line, HP share (user 19/11/2026): OHA's median tango use is 64%; the reference keeps a mid above 60% (`theory/mid-trading-loop.md`). */
    topUp: 0.65,
    /** Rules 2 and 4: mana under this share is low (OHA's clarity bar of 40%, kept: `judgement`). */
    mana: 0.4,
    /** A tree this near is in reach for a tango (the observer's `regen_cover` window, 600). */
    treeReach: 600,
};

/** One heal or mana item in slots 0-8. */
export interface Item {
    slot: number;
    name: string;
    /** Uses left (a bottle's charges, a tango's charges; 1 for a single use). */
    charges: number;
    /** What one use restores, absolute. */
    hp: number;
    mp: number;
    /** Seconds the restore takes (0: instant). */
    dur: number;
    /** Damage from a hero ends the restore (its modifier). */
    breaks: boolean;
    /** The use targets a tree. */
    tree: boolean;
    /** Refills at the fountain or from a rune: a use costs no gold. */
    refill: boolean;
    /** One use can be given to an ally. */
    share: boolean;
}

/** A regen item the side shop or fountain sells, as one purchase. */
export interface Offer {
    name: string;
    cost: number;
    /** What the whole purchase restores, absolute. */
    hp: number;
    mp: number;
}

export interface Run {
    kind: Kind;
    slot?: number;
    name?: string;
    started: number;
    /** HP at the start, absolute. */
    hp0: number;
    /** The item's time and where, for a step-out use. */
    dur?: number;
    at?: { x: number; y: number };
}

export interface Inputs {
    now: number;
    /** Absolute. */
    hp: number;
    hpMax: number;
    mp: number;
    mpMax: number;
    items: Item[];
    /** The nearest passable tree: its distance, and the nearest enemy hero's distance to it. */
    tree?: { d: number; enemyD: number };
    /** A hero damaged us in the last 2 s. */
    hitRecently: boolean;
    /** The threat read here: the damage the enemy heroes in reach deal us in the engaged window (absolute), and how many reach us. */
    burst: number;
    reach: number;
    /** The most the lane's enemy heroes seen in the last 10 s deal us in the stay window (absolute): the kill line's stand-in until the shared "is it safe here?" read. */
    laneBurst: number;
    /** HP and mana the regen buffs on us still restore. */
    regenLeft: number;
    manaLeft: number;
    /** A point out of every seen enemy's reach, and the seconds to walk there. */
    safeSpot?: { x: number; y: number; walk: number };
    gold: number;
    /** Set when the courier is free and alive: seconds to deliver a purchase. */
    courier?: { eta: number };
    shop: Offer[];
    /** Seconds to walk to the fountain and back. */
    home: number;
    /** Between jobs: walking to a pull or a stack, or about to open a trade. */
    idle: boolean;
    atFountain: boolean;
    /** Lane allies within 800: HP missing (absolute) and heal items held. */
    allies: { pid: number; missing: number; heals: number }[];
    run?: Run;
}

export interface Answer {
    kind: Kind;
    slot?: number;
    name?: string;
    /** `give`: the ally. */
    to?: number;
    /** `step_out_use` and a `buy` that waits: where. */
    at?: { x: number; y: number };
    /** The rule that decided (for `none`: why nothing). */
    reason: string;
    /** Why a running answer ended this frame, if it did. */
    ended?: string;
}

/** An instant HP item: kept for rule 1, never spent topping up. */
function reserved(it: Item): boolean {
    return it.dur === 0 && it.hp > 0;
}

function treeOk(i: Inputs): boolean {
    return i.tree !== undefined && i.tree.d <= BARS.treeReach && i.tree.d < i.tree.enemyD;
}

/** Whether one use can start now: a tree item with a tree in reach, an item hero damage ends with a safe spot to use it at. */
function usable(i: Inputs, it: Item): boolean {
    if (it.charges <= 0) return false;
    if (it.tree) return treeOk(i);
    if (it.breaks && it.dur > 0) return i.safeSpot !== undefined;
    return true;
}

/** HP under which the lane's enemies can kill us by the stay bar, never under the heal floor. */
export function KillLine(i: Inputs): number {
    return math.max(RetreatSettings.HealFloor * i.hpMax, i.laneBurst / ThreatSettings.StandBurst);
}

/** HP plus what the regen running and the items in hand can restore, capped at max HP. */
export function Reachable(i: Inputs): number {
    let r = i.hp + i.regenLeft;
    for (const it of i.items) if (it.hp > 0 && usable(i, it)) r += it.hp * it.charges;
    return math.min(r, i.hpMax);
}

function topLine(i: Inputs, kill: number): number {
    return math.max(BARS.topUp * i.hpMax, kill);
}

function manaLow(i: Inputs): boolean {
    return i.mpMax > 0 && i.mp < BARS.mana * i.mpMax;
}

/** The purchase for `need` HP the gold covers: the largest that does not overshoot, else the smallest that covers it. */
function pickHp(i: Inputs, need: number): Offer | undefined {
    let under: Offer | undefined;
    let over: Offer | undefined;
    for (const o of i.shop) {
        if (o.hp <= 0 || o.cost > i.gold) continue;
        if (o.hp <= need) {
            if (under === undefined || o.hp > under.hp) under = o;
        } else if (over === undefined || o.hp < over.hp) over = o;
    }
    return under ?? over;
}

function pickMp(i: Inputs): Offer | undefined {
    let best: Offer | undefined;
    for (const o of i.shop) if (o.mp > 0 && o.cost <= i.gold && (best === undefined || o.cost < best.cost)) best = o;
    return best;
}

function use(it: Item, reason: string): Answer {
    return { kind: "use", slot: it.slot, name: it.name, reason };
}

/** Rule 1: a hero is hitting us, its burst kills us, and an instant item (the most restored first) lifts us over it. */
function survive(i: Inputs): Answer | undefined {
    if (!i.hitRecently || i.reach === 0 || i.hp >= i.burst) return undefined;
    let best: Item | undefined;
    for (const it of i.items) if (reserved(it) && it.charges > 0 && (best === undefined || it.hp > best.hp)) best = it;
    if (best !== undefined && i.hp + best.hp >= i.burst) return use(best, "survive");
    return undefined;
}

/** Rule 2: what the items reach is under the kill line. Low on HP and mana goes home at once; else a delivery that lifts us over it, waited for at a safe spot, if it comes sooner than the trip; else home. Nothing is spent. */
function cannotStay(i: Inputs, kill: number): Answer | undefined {
    const reach = Reachable(i);
    if (reach >= kill) return undefined;
    if (manaLow(i)) return { kind: "home", reason: "low_both" };
    const o = pickHp(i, kill - reach);
    if (o !== undefined && reach + o.hp >= kill && i.courier !== undefined && i.courier.eta < i.home && i.safeSpot !== undefined)
        return { kind: "buy", name: o.name, at: { x: i.safeSpot.x, y: i.safeSpot.y }, reason: "cannot_stay" };
    return { kind: "home", reason: "cannot_stay" };
}

/**
 * Rule 3: under the top-up line, or in an idle window, with no regen running and the missing HP covering one use. A
 * refilling item first, then a tree item, then one hero damage ends, used at a safe spot. Only an item hero damage ends
 * waits out a recent hit (D6: a tango ticks through damage).
 */
function topUp(i: Inputs, kill: number): Answer | undefined {
    if (i.regenLeft > 0) return undefined;
    if (i.hp >= topLine(i, kill) && !i.idle) return undefined;
    const missing = i.hpMax - i.hp;
    const order = (it: Item) => (it.refill ? 0 : it.tree ? 1 : 2);
    let best: Item | undefined;
    for (const it of i.items) {
        if (reserved(it) || it.hp <= 0 || it.charges <= 0 || missing < it.hp || !usable(i, it)) continue;
        if (it.breaks && i.hitRecently) continue;
        if (best === undefined || order(it) < order(best)) best = it;
    }
    if (best === undefined) return undefined;
    if (best.breaks && best.dur > 0 && i.safeSpot !== undefined && i.safeSpot.walk > 0)
        return { kind: "step_out_use", slot: best.slot, name: best.name, at: { x: i.safeSpot.x, y: i.safeSpot.y }, reason: "top_up" };
    return use(best, "top_up");
}

/** Rule 4: mana low, no mana regen running, the missing mana covering one use; a refilling item first. */
function mana(i: Inputs): Answer | undefined {
    if (!manaLow(i) || i.manaLeft > 0) return undefined;
    const missing = i.mpMax - i.mp;
    let best: Item | undefined;
    for (const it of i.items) {
        if (reserved(it) || it.mp <= 0 || it.charges <= 0 || missing < it.mp) continue;
        if (it.breaks && i.hitRecently) continue;
        if (best === undefined || (it.refill && !best.refill)) best = it;
    }
    return best !== undefined ? use(best, "mana") : undefined;
}

/** Rule 5: no heal item in hand under the top-up line (or no mana item with mana low), and the courier free: buy. */
function buyAhead(i: Inputs, kill: number): Answer | undefined {
    if (i.courier === undefined) return undefined;
    let heals = false;
    let manas = false;
    for (const it of i.items) {
        if (it.charges <= 0 || reserved(it)) continue;
        if (it.hp > 0) heals = true;
        if (it.mp > 0) manas = true;
    }
    if (!heals && i.hp < topLine(i, kill)) {
        const o = pickHp(i, i.hpMax - i.hp);
        if (o !== undefined) return { kind: "buy", name: o.name, reason: "buy_hp" };
    }
    if (!manas && manaLow(i)) {
        const o = pickMp(i);
        if (o !== undefined) return { kind: "buy", name: o.name, reason: "buy_mana" };
    }
    return undefined;
}

/** Rule 6: an ally with no heal item misses one use's worth, and we hold two uses or more of an item we can give. */
function give(i: Inputs): Answer | undefined {
    for (const it of i.items) {
        if (!it.share || it.charges < 2) continue;
        for (const a of i.allies) if (a.heals === 0 && a.missing >= it.hp) return { kind: "give", slot: it.slot, name: it.name, to: a.pid, reason: "give" };
    }
    return undefined;
}

/** Why a running answer ends this frame, if it does. */
function ends(i: Inputs, r: Run, kill: number): string | undefined {
    if (r.kind === "step_out_use") {
        if (i.reach > 0) return "interrupted";
        if (i.hp >= topLine(i, kill)) return "topped";
        if (i.now - r.started >= (r.dur ?? 0)) return "done";
        return undefined;
    }
    if (r.kind === "home") return i.atFountain && i.hp >= RetreatSettings.HealUntil * i.hpMax ? "healed" : undefined;
    return "done";
}

function fresh(i: Inputs, kill: number): Answer {
    return cannotStay(i, kill) ?? topUp(i, kill) ?? mana(i) ?? buyAhead(i, kill) ?? give(i) ?? { kind: "none", reason: "fine" };
}

export function Decide(i: Inputs): Answer {
    const s = survive(i);
    if (s !== undefined) return s;
    const kill = KillLine(i);
    const r = i.run;
    if (r === undefined) return fresh(i, kill);
    const why = ends(i, r, kill);
    if (why === undefined) return { kind: r.kind, slot: r.slot, name: r.name, at: r.at, reason: "running" };
    const a = fresh(i, kill);
    a.ended = why;
    return a;
}
