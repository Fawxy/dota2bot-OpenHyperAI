/**
 * Sustain: one decision for HP and mana in lane (design docs/proposals/2026-11-19-sustain-design.md in the master repo, D6,
 * D1's kill line). `Decide` is pure over `Inputs`: no unit handles, no game calls, so a logged cut replays offline. One
 * function for all five positions.
 *
 * An item is data, never a rule: `Gather` (a later step) reads what one use restores, over how long, whether hero damage
 * ends it, whether it needs a tree, refills or can be given, from the item and its modifier at run time. The rules read
 * only those properties. An instant HP item (wand, stick, faerie fire) is kept for rule 1 and counts in `reachable`.
 *
 * Rules, first match (design section 2): 1 survive, 2 cannot stay, 3 top up, 4 mana, 5 buy ahead, 6 give. Rule 2 waits at the
 * safe spot for a delivery on its way that lifts us over the kill line (eating a tango meanwhile), and ships one when the courier
 * comes sooner than the walk home (tango and ship: a tango eaten now with a purchase sent `also`).
 */
import { SETTINGS as RetreatSettings } from "bots/FunLib/humaniser/retreat";
import { Line as SafeLine } from "bots/FunLib/humaniser/safe";

export type Kind = "none" | "use" | "step_out_use" | "give" | "buy" | "home" | "wait";

/** Every number the decision owns, with its source. The kill line's floor (`HealFloor`) and `HealUntil` are retreat's, its bar (`stay`) the safe-here read's: read at call time, not copied. */
export const BARS = {
    /** Rule 3's top-up line, HP share (user 19/11/2026): OHA's median tango use is 64%; the reference keeps a mid above 60% (`theory/mid-trading-loop.md`). */
    topUp: 0.65,
    /** Rules 2 and 4: mana under this share is low (OHA's clarity bar of 40%, kept: `judgement`). */
    mana: 0.4,
    /** Rule 3: a tango walk there and back must end this long before the next last hit or deny is due (the turn and the cast). judgement. */
    castSlack: 0.5,
    /** Rule 3 with no hit due (no wave near) or in an idle window: the longest tango walk there and back (s). judgement: 4 s each way costs no lane time there. */
    idleWalk: 8,
    /**
     * Rule 2 sends a hero home only under this HP share, whatever the kill line: above it a hero plays back in lane, and a place
     * the lane can kill it in is retreat's to leave (smoke sustain-home 1: walks home at 65% and 74% HP when a lane's burst read
     * 536 of 840). judgement, before tonight's batch.
     */
    homeCap: 0.5,
    /** Rule 5 buys mana only under this share (OHA's clarity purchase bar, 30%; smoke 1: a core bought four clarities at 40%). judgement. */
    manaBuy: 0.3,
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
    /** Castable now: in slots 0-5 and off cooldown. One that is not still counts in what we reach (a swap, a cooldown) but is never picked. Missing: ready. */
    ready?: boolean;
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
    /** The nearest passable tree, read only with a tree item held: seconds to walk into cast range of it, and whether that walk is safe (the safe-here read over it is not `deadly`); `start` false when we stand `deadly` here, so a walk may count in rule 2 but not start now. */
    tree?: { walk: number; safe: boolean; start?: boolean };
    /** Seconds until the next last hit or deny comes due in our lane; none with no wave near. */
    nextDue?: number;
    /** A hero damaged us in the last 2 s. */
    hitRecently: boolean;
    /**
     * The safe-here read here, 2 s (design docs/proposals/2026-11-19-safe-here-design.md): what the heroes in reach can deal
     * (absolute; lane opponents seen in the last 10 s included), whether one of them is hitting us, and how many reach us.
     */
    safe: { kill: number; hitting: boolean; reach: number; /** `Safe.Pressed` of the same read; absent on an older cut, where `hitting` stands in. */ pressed?: boolean };
    /** HP and mana the regen buffs on us still restore. */
    regenLeft: number;
    manaLeft: number;
    /** A point out of every seen enemy's reach, and the seconds to walk there; `ok` false when the safe-here read there (held) is `deadly`, so no wait runs there (missing: not read, taken as safe). */
    safeSpot?: { x: number; y: number; walk: number; ok?: boolean };
    /** Regen on its way, whoever bought it (heal and mana items in the stash or on the courier, read from the game): what it restores and the seconds until it can land. */
    delivery?: { hp: number; mp: number; eta: number };
    /** A free slot in 0-8 for a purchase to land in (missing: room). */
    room?: boolean;
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
    /** `step_out_use`, `wait` and a `buy` or tango that waits: where. */
    at?: { x: number; y: number };
    /** A purchase sent with a use (rule 2's tango and ship). */
    also?: string;
    /** The rule that decided (for `none`: why nothing). */
    reason: string;
    /** Why a running answer ended this frame, if it did. */
    ended?: string;
}

/** An instant HP item: kept for rule 1, never spent topping up. */
function reserved(it: Item): boolean {
    return it.dur === 0 && it.hp > 0;
}

/** Rule 2's tree (user 19/11/2026): the walk is a cost against the trip, so a tango counts when its walk is safe and there and back is shorter than home. */
function treeReach(i: Inputs): boolean {
    return i.tree !== undefined && i.tree.safe && 2 * i.tree.walk < i.home;
}

/** Rule 3's tree: a safe walk there and back that ends before the next hit is due (no last hit or deny missed); with none due, or between jobs, a short walk. */
function treeNow(i: Inputs): boolean {
    // `start` false: we stand deadly here, so no walk starts now (it still counts in rule 2's reach: review of step 3).
    if (i.tree === undefined || !i.tree.safe || i.tree.start === false) return false;
    const trip = 2 * i.tree.walk;
    if (i.nextDue !== undefined && !i.idle) return trip + BARS.castSlack <= i.nextDue;
    return trip <= BARS.idleWalk;
}

/** Whether a use counts in what we reach: a tree item with a tree worth its walk, an item hero damage ends with a safe spot to use it at. */
function counts(i: Inputs, it: Item): boolean {
    if (it.charges <= 0) return false;
    if (it.tree) return treeReach(i);
    if (it.breaks && it.dur > 0) return i.safeSpot !== undefined;
    return true;
}

/** Whether one use can start now: castable, and a tree item's walk fits before the next hit. */
function usable(i: Inputs, it: Item): boolean {
    if (it.ready === false || !counts(i, it)) return false;
    return !it.tree || treeNow(i);
}

/**
 * HP under which this place is `deadly` by the safe-here read's own bar (Stay x kill), so sustain and retreat send a hero
 * home on one line; never under the heal floor (sustain's own going-home floor) and never over max HP (a lane that can kill
 * a full hero would otherwise send one home from the fountain; that place is retreat's answer).
 */
export function KillLine(i: Inputs): number {
    return math.min(i.hpMax, math.max(RetreatSettings.HealFloor * i.hpMax, SafeLine(i.safe.pressed ?? i.safe.hitting) * i.safe.kill));
}

/** HP plus what the regen running and the items in hand can restore, capped at max HP. */
export function Reachable(i: Inputs): number {
    let r = i.hp + i.regenLeft;
    for (const it of i.items) if (it.hp > 0 && counts(i, it)) r +=it.hp * it.charges;
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

/** The cheapest purchase the gold covers that restores at least `need` HP. */
function pickCover(i: Inputs, need: number): Offer | undefined {
    let best: Offer | undefined;
    for (const o of i.shop) if (o.hp >= need && o.cost <= i.gold && (best === undefined || o.cost < best.cost)) best = o;
    return best;
}

function pickMp(i: Inputs): Offer | undefined {
    let best: Offer | undefined;
    for (const o of i.shop) if (o.mp > 0 && o.cost <= i.gold && (best === undefined || o.cost < best.cost)) best = o;
    return best;
}

function use(it: Item, reason: string): Answer {
    return { kind: "use", slot: it.slot, name: it.name, reason };
}

/** Rule 1: a hero in reach is hitting us, what the reachers can deal kills us, and an instant item (the most restored first) lifts us over it. */
function survive(i: Inputs): Answer | undefined {
    if (!i.safe.hitting || i.hp >= i.safe.kill) return undefined;
    let best: Item | undefined;
    for (const it of i.items) if (reserved(it) && it.charges > 0 && it.ready !== false && (best === undefined || it.hp > best.hp)) best = it;
    if (best !== undefined && i.hp + best.hp >= i.safe.kill) return use(best, "survive");
    return undefined;
}

/** Rule 2's tango: a tree item castable now with no regen running (a recast refreshes the buff; it does not stack). */
function tangoNow(i: Inputs): Item | undefined {
    if (i.regenLeft > 0) return undefined;
    for (const it of i.items) if (it.tree && it.hp > 0 && usable(i, it)) return it;
    return undefined;
}

/**
 * Rule 2: what the items reach is under the kill line. Low on HP and mana goes home at once. A delivery on its way that lifts us
 * over the line is waited for at the safe spot (a tango eaten meanwhile); else, the courier sooner than the trip, the purchase that
 * lifts us over it is sent, with a tango eaten now when one is in hand (tango and ship); else home. Nothing else is spent: an item
 * used and then the walk home anyway is the waste the rule exists to stop (user 19/11/2026). The wait and the shipment need a safe
 * spot the safe-here read there does not call deadly.
 */
function cannotStay(i: Inputs, line: number): Answer | undefined {
    const kill = math.min(line, BARS.homeCap * i.hpMax);
    const reach = Reachable(i);
    if (reach >= kill) return undefined;
    if (manaLow(i)) return { kind: "home", reason: "low_both" };
    const spot = i.safeSpot !== undefined && i.safeSpot.ok !== false ? { x: i.safeSpot.x, y: i.safeSpot.y } : undefined;
    if (spot === undefined) return { kind: "home", reason: "cannot_stay" };
    const d = i.delivery;
    if (d !== undefined) {
        // No free slot: it cannot land, so it is not waited for.
        if (reach + d.hp < kill || d.eta >= i.home || i.room === false) return { kind: "home", reason: "cannot_stay" };
        const t = tangoNow(i);
        if (t !== undefined) return { kind: "use", slot: t.slot, name: t.name, at: spot, reason: "wait_tango" };
        return { kind: "wait", at: spot, reason: "delivery" };
    }
    if (i.courier === undefined || i.courier.eta >= i.home || i.room === false) return { kind: "home", reason: "cannot_stay" };
    const o = pickCover(i, kill - reach);
    if (o === undefined) return { kind: "home", reason: "cannot_stay" };
    const t = tangoNow(i);
    if (t !== undefined) return { kind: "use", slot: t.slot, name: t.name, at: spot, also: o.name, reason: "tango_ship" };
    return { kind: "buy", name: o.name, at: spot, reason: "cannot_stay" };
}

/**
 * Rule 3: under the top-up line, or in an idle window, with no regen running and the missing HP covering one use. A
 * refilling item first, then a tree item, then one hero damage ends, used at a safe spot. Only an item hero damage ends
 * waits out a recent hit or a hero in reach (D6: a tango ticks through damage; a step-out ends `interrupted` on reach).
 */
function topUp(i: Inputs, kill: number): Answer | undefined {
    if (i.regenLeft > 0) return undefined;
    if (i.hp >= topLine(i, kill) && !i.idle) return undefined;
    const missing = i.hpMax - i.hp;
    const order = (it: Item) => (it.refill ? 0 : it.tree ? 1 : 2);
    let best: Item | undefined;
    for (const it of i.items) {
        if (reserved(it) || it.hp <= 0 || it.charges <= 0 || missing < it.hp || !usable(i, it)) continue;
        if (it.breaks && (i.hitRecently || i.safe.reach > 0)) continue;
        if (best === undefined || order(it) < order(best)) best = it;
    }
    if (best === undefined) return undefined;
    if (best.breaks && best.dur > 0 && i.safeSpot !== undefined && i.safeSpot.walk > 0)
        return { kind: "step_out_use", slot: best.slot, name: best.name, at: { x: i.safeSpot.x, y: i.safeSpot.y }, reason: "top_up" };
    return use(best, "top_up");
}

/** Rule 4: mana low, no regen running (one at a time), the missing mana covering one use; a refilling item first. */
function mana(i: Inputs): Answer | undefined {
    if (!manaLow(i) || i.manaLeft > 0 || i.regenLeft > 0) return undefined;
    const missing = i.mpMax - i.mp;
    let best: Item | undefined;
    for (const it of i.items) {
        if (reserved(it) || it.mp <= 0 || it.charges <= 0 || it.ready === false || missing < it.mp) continue;
        if (it.breaks && (i.hitRecently || i.safe.reach > 0)) continue;
        if (best === undefined || (it.refill && !best.refill)) best = it;
    }
    return best !== undefined ? use(best, "mana") : undefined;
}

/** Rule 5: no heal item in hand under the top-up line (or no mana item with mana low), the courier free and nothing on its way: buy. */
function buyAhead(i: Inputs, kill: number): Answer | undefined {
    // One purchase on its way at a time; none at the fountain (it heals there) or with no slot for it to land in.
    if (i.courier === undefined || i.delivery !== undefined || i.atFountain || i.room === false) return undefined;
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
    if (!manas && i.mpMax > 0 && i.mp < BARS.manaBuy * i.mpMax) {
        const o = pickMp(i);
        if (o !== undefined) return { kind: "buy", name: o.name, reason: "buy_mana" };
    }
    return undefined;
}

/** Rule 6: an ally with no heal item misses one use's worth, and we hold two uses or more of an item we can give. */
function give(i: Inputs): Answer | undefined {
    for (const it of i.items) {
        if (!it.share || it.charges < 2 || it.ready === false) continue;
        for (const a of i.allies) if (a.heals === 0 && a.missing >= it.hp) return { kind: "give", slot: it.slot, name: it.name, to: a.pid, reason: "give" };
    }
    return undefined;
}

/** Why a running answer ends this frame, if it does. */
function ends(i: Inputs, r: Run, kill: number): string | undefined {
    if (r.kind === "step_out_use") {
        if (i.safe.reach > 0) return "interrupted";
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
