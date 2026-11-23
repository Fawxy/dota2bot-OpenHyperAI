/**
 * Sustain, carried out (design docs/proposals/2026-11-19-sustain-design.md in the master repo, steps 3-5; switch `Ours.Sustain`).
 * For a held laner (Phase.LaningHeld, no drill hold), `ItemThink` runs the pure Decide on sustain_gather.ts's inputs and gives
 * the order for `use`, `step_out_use`, `give` and `wait`, makes a `buy`'s purchase and has the hero's courier deliver it, and
 * tells retreat whether rule 2 sends the hero home (`RetreatState.SetHome`: retreat's heal leave walks it; while that walk runs,
 * Decide is asked with a running `home`, so nothing is spent on the way). OHA's item loop leaves every heal and mana item on
 * such a hero alone (`HoldsItem`); its lane-regen purchases (`HoldsBuy`), teleport home (`HoldsTeleport`; not its escape) and, while a delivery of ours
 * is on its way, its courier code (`OwnsCourier`) stand aside.
 *
 * Where the orders run: an order with no walk (a self cast, a tango with the tree in range) from ItemUsageThink, in any mode,
 * as OHA's own item use does. A walk (a tango's tree, a step out to the safe spot, an ally out of cast range) starts only
 * while the laning mode holds the hero, and is carried on by the lane table's `sustain` row (`Walking`/`Step`), so the
 * body's own move does not undo it. One attempt runs at a time;
 * rule 1 (an instant heal under hits) may replace a running one. Each attempt logs `ev=sustain` at its end.
 */
import { BotMode, Item, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Sustain from "bots/FunLib/humaniser/sustain";
import * as SustainGather from "bots/FunLib/humaniser/sustain_gather";
import * as ItemUse from "bots/FunLib/humaniser/item_use";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Phase from "bots/FunLib/humaniser/laning_held";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";

declare const BOT_ACTION_TYPE_USE_ABILITY: number;
declare const PURCHASE_ITEM_SUCCESS: number;
declare const COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS: number;
declare const COURIER_ACTION_BURST: number;
declare const COURIER_STATE_DELIVERING_ITEMS: number;
declare const COURIER_STATE_DEAD: number;
declare function GetCourierState(c: Unit): number;

/** API methods ts_libs does not declare yet. */
interface ActBot {
    GetCurrentActionType(): number;
}
interface RangeItem {
    GetCastRange(): number;
}
interface ShopBot {
    ActionImmediate_PurchaseItem(name: string): number;
    ActionImmediate_Courier(courier: Unit, action: number): boolean;
}

export const SETTINGS = {
    /** The decision runs at most this often per hero (s), as the shadow's. */
    DecideEvery: 0.5,
    /** While a hero hit us in the last second: rule 1's instant heal must land before the next hits (s). judgement. */
    DecideHit: 0.1,
    /** A use whose charge has not gone this long after the order, plus its walk, ends `missed` (s). judgement. */
    StartWait: 1.5,
    /** A step out drinks within this of the safe spot. judgement: a move order's own arrival tolerance. */
    Arrive: 100,
    /** A delivery not in slots 0-8 by its eta plus this ends `late` (s): the courier's walk is estimated on a straight line. judgement. */
    LateSlack: 20,
    /** The courier's delivery order is given again at most this often while it is not delivering (s). judgement. */
    CourierEvery: 2,
    /** A teleport refusal this long after the last one starts a new run and logs again (s). OHA asks every frame. judgement. */
    RefuseGap: 2,
};

/** Cast on our own hero (OHA's cast type `unit` for these); a tree item on its tree; any other item has no target. */
const SELF: Record<string, true> = { item_flask: true, item_clarity: true };

interface Act {
    kind: "use" | "step_out_use" | "give" | "wait";
    item: string;
    slot: number;
    why: string;
    at: number;
    hp0: number;
    mp0: number;
    /** Charges of the item held over slots 0-8 at the order: a fall means the use started. */
    charges0: number;
    /** Walk seconds at the order (0: none). */
    walk: number;
    deadline: number;
    tree?: number;
    to?: number;
    spot?: Vector;
    /** step_out_use: the item was used at the spot. */
    drunk?: boolean;
    run?: Sustain.Run;
}

const acts: Record<number, Act | undefined> = {};

/**
 * A delivery our courier carries out: a purchase of ours, or regen already on the way that a wait adopted (`item` "stash").
 * What is on the way is the game's read (SustainGather.OnTheWay), not this record: it lands when nothing is left in the stash
 * or on the courier.
 */
interface Delivery {
    item: string;
    why: string;
    at: number;
    /** The eta read at the start (s): `late` after it plus LateSlack. */
    eta: number;
    hp0: number;
    mp0: number;
    res?: number;
    orderAt: number;
    orders: number;
}
const deliveries: Record<number, Delivery | undefined> = {};
const decidedAt: Record<number, number | undefined> = {};
const refusedAt: Record<number, number | undefined> = {};

/** A hero sustain carries: the switch, a laner we hold, and no drill hold on its items (a lane-only cast without `castItems`, a rig's hold). */
export function Holds(bot: Unit): boolean {
    if (!Ours.On("Sustain") || bot.IsIllusion() || !Phase.LaningHeld(bot) || Drill.Held(bot)) return false;
    if (Drill.RigHoldsCasts(bot, true) === true && !Drill.RigFreesSustain(bot)) return false;
    return !(Overrides.LaneOnly(bot) && !Drill.CastItems(bot));
}

/**
 * OHA's retreat teleport home (item_tpscroll, ability_item_usage_generic.lua, cases 1 and 3: `why`) stands aside for a hero
 * sustain carries, whose trip home is rule 2's walk. Asked last in the case's condition, so a refusal is one OHA would have cast;
 * logged once per run of refusals. OHA's escape teleport (case 2) does not ask: it is a way out of a fight, not a trip home.
 */
export function HoldsTeleport(bot: Unit, why: string): boolean {
    if (!Holds(bot)) return false;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const last = refusedAt[pid];
    refusedAt[pid] = now;
    if (last === undefined || now - last > SETTINGS.RefuseGap) {
        Telemetry.Event("sustain_tp", [
            ["pid", pid],
            ["why", why],
            ["hp", math.floor((100 * bot.GetHealth()) / bot.GetMaxHealth())],
        ]);
    }
    return true;
}

/** A rig owns this kind for the hero (drill.ts Owns) and its release does not free our sustain (the sustain rig's does). */
function rigOwns(bot: Unit, what: "purchase" | "courier"): boolean {
    return Drill.Owns(bot, what) && !Drill.RigFreesSustain(bot);
}

/** OHA's lane-regen purchase rules (item_purchase_generic.lua BuyRegen) skip a hero sustain carries: rules 2 and 5 buy. */
export function HoldsBuy(bot: Unit): boolean {
    return Holds(bot);
}

/** OHA's courier code (CourierUsageThink) stands aside while a delivery of ours is on its way to this hero. */
export function OwnsCourier(bot: Unit): boolean {
    return deliveries[bot.GetPlayerID()] !== undefined;
}

/** OHA's item loop and roam's tango skip this item on this hero: every heal and mana item sustain reads, on a hero it carries. */
export function HoldsItem(bot: Unit, name: string): boolean {
    return SustainGather.ITEMS[name] !== undefined && Holds(bot);
}

/** The item's charges over slots 0-8; one held with no charge count (a shared tango, an empty wand) counts a half, so its use or a last charge's still shows as a fall. */
function chargesOf(bot: Unit, name: string): number {
    let n = 0;
    for (let s = 0; s <= 8; s++) {
        const it = bot.GetItemInSlot(s);
        if (it === undefined || it === null || it.GetName() !== name) continue;
        const c = it.GetCurrentCharges() ?? 0;
        n += c > 0 ? c : 0.5;
    }
    return n;
}

function itemIn(bot: Unit, slot: number, name: string): Item | undefined {
    const it = bot.GetItemInSlot(slot);
    return it !== undefined && it !== null && it.GetName() === name && it.IsFullyCastable() ? it : undefined;
}

function allyOf(pid: number): Unit | undefined {
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) if (a !== undefined && a !== null && !a.IsNull() && a.IsAlive() && !a.IsIllusion() && a.GetPlayerID() === pid) return a;
    return undefined;
}

/** A walk can be carried now: the laning mode holds the hero (its `sustain` row steps it). */
function carried(bot: Unit): boolean {
    return bot.GetActiveMode() === BotMode.Laning;
}

const r1 = (v: number): number => math.floor(v * 10 + 0.5) / 10;
const n0 = (v: number): number => math.floor(v + 0.5);

function end(bot: Unit, why: string): void {
    const pid = bot.GetPlayerID();
    const a = acts[pid];
    if (a === undefined) return;
    acts[pid] = undefined;
    if (!Telemetry.IsEnabled()) return;
    Telemetry.Event("sustain", [
        ["pid", pid],
        ["k", a.kind],
        ["it", a.item],
        ["to", a.to],
        ["why", a.why],
        ["hp0", n0(a.hp0)],
        ["hp1", n0(bot.GetHealth())],
        ["mp0", n0(a.mp0)],
        ["mp1", n0(bot.GetMana())],
        ["sec", r1(DotaTime() - a.at)],
        ["ed", why],
        ["wk", a.walk > 0 ? r1(a.walk) : undefined],
    ]);
}

function endBuy(bot: Unit, why: string): void {
    const pid = bot.GetPlayerID();
    const d = deliveries[pid];
    if (d === undefined) return;
    deliveries[pid] = undefined;
    if (!Telemetry.IsEnabled()) return;
    Telemetry.Event("sustain", [
        ["pid", pid],
        ["k", "buy"],
        ["it", d.item],
        ["why", d.why],
        ["hp0", n0(d.hp0)],
        ["hp1", n0(bot.GetHealth())],
        ["mp0", n0(d.mp0)],
        ["mp1", n0(bot.GetMana())],
        ["sec", r1(DotaTime() - d.at)],
        ["ed", why],
        ["res", d.res],
        ["cor", d.orders],
        ["eta", r1(d.eta)],
    ]);
}

/**
 * One frame of a delivery: nothing left on the way (stash and courier read) ends it `delivered`; late or the courier dead end it
 * too (what is still on the way stays in Decide's read, so no second purchase follows); else the courier is ordered to take the
 * stash to us (and burst).
 */
function deliver(bot: Unit, d: Delivery, now: number): void {
    const c = SustainGather.CourierOf(bot);
    // Not in the purchase's own frame: the item may reach the stash only once the order is processed.
    if (now > d.at && SustainGather.OnTheWay(bot, c) === undefined) return endBuy(bot, "delivered");
    const st = c !== undefined ? GetCourierState(c) : COURIER_STATE_DEAD;
    if (c === undefined || st === COURIER_STATE_DEAD) return endBuy(bot, "courier_dead");
    if (now > d.at + d.eta + SETTINGS.LateSlack) return endBuy(bot, "late");
    if (st === COURIER_STATE_DELIVERING_ITEMS || now - d.orderAt < SETTINGS.CourierEvery) return;
    d.orderAt = now;
    d.orders += 1;
    const b = bot as unknown as ShopBot;
    b.ActionImmediate_Courier(c, COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS);
    const burst = c.GetAbilityByName("courier_burst");
    if (burst !== undefined && burst !== null && burst.IsFullyCastable()) b.ActionImmediate_Courier(c, COURIER_ACTION_BURST);
}

/**
 * A purchase for Decide's `buy` (or a use's `also`): bought and its delivery started. False when regen is already on the way (the
 * game's read, whoever bought it), a rig owns the hero's purchases, or the game refused it.
 */
function purchase(bot: Unit, i: Sustain.Inputs, name: string, why: string, now: number): boolean {
    const pid = bot.GetPlayerID();
    // A rig hands its heroes their items and holds their couriers (drill.ts Owns): no purchase of ours there, unless its release frees sustain.
    if (deliveries[pid] !== undefined || SustainGather.OnTheWay(bot) !== undefined || rigOwns(bot, "purchase") || rigOwns(bot, "courier")) return false;
    const full = `item_${name}`;
    const res = (bot as unknown as ShopBot).ActionImmediate_PurchaseItem(full);
    if (res !== PURCHASE_ITEM_SUCCESS) {
        if (Telemetry.IsEnabled())
            Telemetry.Event("sustain", [["pid", pid], ["k", "buy"], ["it", full], ["why", why], ["hp0", n0(i.hp)], ["mp0", n0(i.mp)], ["sec", 0], ["ed", "failed"], ["res", res]]);
        return false;
    }
    SustainGather.Bought(bot, full, `ours_${why}`);
    const d: Delivery = { item: full, why, at: now, eta: i.courier?.eta ?? 0, hp0: i.hp, mp0: i.mp, res, orderAt: -math.huge, orders: 0 };
    deliveries[pid] = d;
    // Bought in the shop's range it is in the inventory at once; else the stash, and the courier goes now.
    deliver(bot, d, now);
    return true;
}

/** Gives the attempt's order for this frame (a walk's order again while it runs). */
function order(bot: Unit, a: Act): void {
    if (a.kind === "wait") {
        if (a.spot !== undefined && GetUnitToLocationDistance(bot, a.spot) > SETTINGS.Arrive) bot.Action_MoveToLocation(a.spot);
        return;
    }
    const item = itemIn(bot, a.slot, a.item);
    if (item === undefined) return;
    if (a.kind === "step_out_use") {
        if (a.spot === undefined || a.drunk === true) return;
        if (GetUnitToLocationDistance(bot, a.spot) > SETTINGS.Arrive) {
            bot.Action_MoveToLocation(a.spot);
            return;
        }
        a.drunk = true;
        if (a.run !== undefined) a.run.started = DotaTime();
        if (SELF[a.item] === true) ItemUse.UseOnSelf(bot, item);
        else ItemUse.UseNoTarget(bot, item);
        return;
    }
    // A repeated order while the cast is under way would restart it.
    if ((bot as unknown as ActBot).GetCurrentActionType() === BOT_ACTION_TYPE_USE_ABILITY && a.at < DotaTime()) return;
    if (a.kind === "give") {
        const ally = a.to !== undefined ? allyOf(a.to) : undefined;
        if (ally !== undefined) ItemUse.UseOnAlly(bot, item, ally);
    } else if (a.tree !== undefined) ItemUse.UseOnTree(bot, item, a.tree);
    else if (SELF[a.item] === true) ItemUse.UseOnSelf(bot, item);
    else ItemUse.UseNoTarget(bot, item);
}

/** A wait at the safe spot for a delivery on its way: true when it started (its walk carried). */
function startWait(bot: Unit, i: Sustain.Inputs, ans: Sustain.Answer, now: number): boolean {
    if (ans.at === undefined) return false;
    const spot = Vector(ans.at.x, ans.at.y, bot.GetLocation().z);
    const walk = GetUnitToLocationDistance(bot, spot) / math.max(100, bot.GetCurrentMovementSpeed());
    if (GetUnitToLocationDistance(bot, spot) > SETTINGS.Arrive && !carried(bot)) return false;
    const a: Act = { kind: "wait", item: "", slot: -1, why: ans.reason, at: now, hp0: i.hp, mp0: i.mp, charges0: 0, walk, deadline: math.huge, spot };
    acts[bot.GetPlayerID()] = a;
    order(bot, a);
    adopt(bot, i, ans.reason, now);
    return true;
}

/**
 * Regen on the way that no delivery of ours carries (OHA's purchase, or one of ours that ran late): our courier brings it, or a
 * wait would last as long as it sat in the stash. Asked at a wait's start and at each of its decisions (review: a delivery
 * ended `late` left the wait standing with the courier idle).
 */
function adopt(bot: Unit, i: Sustain.Inputs, why: string, now: number): void {
    const pid = bot.GetPlayerID();
    if (deliveries[pid] !== undefined || i.delivery === undefined || rigOwns(bot, "courier")) return;
    const d: Delivery = { item: "stash", why, at: now, eta: i.delivery.eta, hp0: i.hp, mp0: i.mp, orderAt: -math.huge, orders: 0 };
    deliveries[pid] = d;
    deliver(bot, d, now);
}

/**
 * Starts the answer's attempt, if it is one this module carries out and its order can be given now. True when it did (or the
 * answer needs nothing done: none, home); false when an answer was not carried (a refused purchase, a walk nobody carries).
 */
function start(bot: Unit, i: Sustain.Inputs, ans: Sustain.Answer, now: number): boolean {
    if (ans.kind === "none" || ans.kind === "home") return true;
    if (ans.kind === "wait") return startWait(bot, i, ans, now);
    if (ans.kind === "buy") return ans.name !== undefined && purchase(bot, i, ans.name, ans.reason, now);
    if (ans.slot === undefined || ans.name === undefined) return false;
    const name = `item_${ans.name}`;
    const item = itemIn(bot, ans.slot, name);
    if (item === undefined) return false;
    const a: Act = {
        kind: ans.kind,
        item: name,
        slot: ans.slot,
        why: ans.reason,
        at: now,
        hp0: i.hp,
        mp0: i.mp,
        charges0: chargesOf(bot, name),
        walk: 0,
        deadline: now + SETTINGS.StartWait,
    };
    if (ans.kind === "use" && SustainGather.ITEMS[name]?.tree === true) {
        const t = SustainGather.TreeOf(bot);
        if (t === undefined || i.tree === undefined) return false;
        a.tree = t.id;
        a.walk = i.tree.walk;
    } else if (ans.kind === "step_out_use") {
        if (ans.at === undefined || i.safeSpot === undefined) return false;
        a.spot = Vector(ans.at.x, ans.at.y, bot.GetLocation().z);
        a.walk = i.safeSpot.walk;
        const it = i.items.find((x) => x.slot === ans.slot);
        a.run = { kind: "step_out_use", slot: ans.slot, name: ans.name, started: now, hp0: i.hp, dur: a.walk + (it?.dur ?? 0), at: ans.at };
    } else if (ans.kind === "give") {
        const ally = ans.to !== undefined ? allyOf(ans.to) : undefined;
        if (ally === undefined) return false;
        a.to = ans.to;
        a.walk = math.max(0, GetUnitToUnitDistance(bot, ally) - (item as unknown as RangeItem).GetCastRange()) / math.max(100, bot.GetCurrentMovementSpeed());
    }
    if (a.walk > 0 && !carried(bot)) return false;
    a.deadline = now + a.walk + SETTINGS.StartWait;
    acts[bot.GetPlayerID()] = a;
    order(bot, a);
    // Rule 2's tango and ship: the purchase goes with the tango (the use started; a refused purchase leaves the tango eaten and the next decision goes home).
    if (ans.also !== undefined) purchase(bot, i, ans.also, ans.reason, now);
    return true;
}

/** Rule 2's answers: the hero cannot stay as it is. One not carried (a refused purchase, a wait or tango walk nobody carries) sends it home. */
const RULE2: Record<string, true> = { cannot_stay: true, low_both: true, delivery: true, wait_tango: true, tango_ship: true };

/** Starts the answer and tells retreat whether the hero goes home: rule 2's `home`, or a rule 2 answer that could not be carried (a wait first for a tango that could not start). */
function carry(bot: Unit, i: Sustain.Inputs, ans: Sustain.Answer, now: number): void {
    let ok = start(bot, i, ans, now);
    // A rule 2 tango that could not start: the hero waits at the spot instead, and only once the wait has started is the purchase
    // sent with it made (review: bought first, a wait that could not start then sent the hero home with the salve bought).
    if (!ok && (ans.reason === "wait_tango" || ans.reason === "tango_ship") && startWait(bot, i, ans, now)) {
        ok = ans.also === undefined || purchase(bot, i, ans.also, ans.reason, now);
        if (!ok) end(bot, "cut");
    }
    RetreatState.SetHome(bot, ans.kind === "home" || (!ok && RULE2[ans.reason] === true));
}

/** One frame of a running attempt: true once it has ended. */
function progress(bot: Unit, a: Act, now: number): boolean {
    if (a.kind === "wait") {
        if (!carried(bot) && now > a.at) {
            end(bot, "cut");
            return true;
        }
        const pid = bot.GetPlayerID();
        const last = decidedAt[pid];
        if (last !== undefined && now - last < SETTINGS.DecideEvery) return false;
        decidedAt[pid] = now;
        const i = SustainGather.Gather(bot);
        const ans = Sustain.Decide(i);
        if (ans.kind === "wait" && ans.at !== undefined) {
            a.spot = Vector(ans.at.x, ans.at.y, bot.GetLocation().z);
            RetreatState.SetHome(bot, false);
            adopt(bot, i, ans.reason, now);
            return false;
        }
        end(bot, "done");
        SustainGather.Cut(bot, i, ans, true);
        carry(bot, i, ans, now);
        return true;
    }
    if (a.kind === "step_out_use") {
        if (a.drunk !== true && !carried(bot) && now > a.at) {
            end(bot, "cut");
            return true;
        }
        // The running answer is asked at the decision's own cadence (a read per ask); the walk's order is the row's, every frame.
        const pid = bot.GetPlayerID();
        const last = decidedAt[pid];
        if (last !== undefined && now - last < SETTINGS.DecideEvery) return false;
        decidedAt[pid] = now;
        const i = SustainGather.Gather(bot, a.run);
        const ans = Sustain.Decide(i);
        SustainGather.Cut(bot, i, ans, true);
        RetreatState.SetHome(bot, ans.kind === "home");
        if (ans.reason !== "running") {
            end(bot, ans.ended ?? "done");
            return true;
        }
        if (a.drunk !== true && now > a.deadline + (a.run?.dur ?? 0)) {
            end(bot, "missed");
            return true;
        }
        return false;
    }
    if (chargesOf(bot, a.item) < a.charges0) {
        end(bot, "started");
        return true;
    }
    if (a.walk > 0 && !carried(bot) && now > a.at) {
        end(bot, "cut");
        return true;
    }
    if (now > a.deadline) {
        end(bot, "missed");
        return true;
    }
    // An order with no walk is given again each frame until its charge goes: a stun or a mode's move in between swallows it
    // (smoke 2: 5 of 11 wand uses under hits missed, the next one landed). A walk's order is the lane row's.
    if (a.walk <= 0) order(bot, a);
    return false;
}

/**
 * ItemUsageThink's call (ability_item_usage_generic.lua), every hero every frame: nothing unless sustain carries the hero.
 * A running attempt is stepped; else, at DecideEvery (DecideHit under hits), Decide's answer is started and logged.
 */
export function ItemThink(bot: Unit): void {
    const pid = bot.GetPlayerID();
    if (!bot.IsAlive()) {
        end(bot, "dead");
        endBuy(bot, "dead");
        RetreatState.SetHome(bot, undefined);
        return;
    }
    if (!Holds(bot)) {
        end(bot, "released");
        endBuy(bot, "released");
        RetreatState.SetHome(bot, undefined);
        return;
    }
    const now = DotaTime();
    const d = deliveries[pid];
    if (d !== undefined) deliver(bot, d, now);
    const hit = bot.WasRecentlyDamagedByAnyHero(1);
    const a = acts[pid];
    if (a !== undefined && !progress(bot, a, now) && !hit) return;
    const last = decidedAt[pid];
    if (last !== undefined && now - last < (hit ? SETTINGS.DecideHit : SETTINGS.DecideEvery)) return;
    decidedAt[pid] = now;
    SustainGather.NoteCourier(bot);
    // Retreat's walk home runs: Decide is asked with a running `home` (rule 1 still fires; nothing else is spent on the way).
    const run: Sustain.Run | undefined = RetreatState.Healing(bot) ? { kind: "home", started: now, hp0: bot.GetHealth() } : undefined;
    const i = SustainGather.Gather(bot, run);
    const ans = Sustain.Decide(i);
    // Under hits a running attempt is asked again only for rule 1: an instant heal replaces it, unless it is rule 1's own
    // (its charge goes a frame or two after the order: smoke 1 cut 16 of 23 wand uses that way and ordered them again).
    const running = acts[pid];
    if (running !== undefined) {
        if (ans.reason !== "survive" || running.why === "survive") return;
        end(bot, "cut");
    }
    SustainGather.Cut(bot, i, ans, true);
    carry(bot, i, ans, now);
}

/**
 * The lane table's `sustain` row: an attempt not yet under way wants the frame, a walk or not (smoke 1: 6 of 49 tangos with
 * the tree in range were never eaten, the body's move given after the cast); a step out once it has drunk does not.
 */
export function Walking(bot: Unit): boolean {
    const a = acts[bot.GetPlayerID()];
    if (a === undefined) return false;
    // A wait holds the frame at the spot too: the body's own move would walk it back into the lane.
    return a.kind !== "step_out_use" || a.drunk !== true;
}

/** The row's run: the walk's order again. True: the frame is taken. */
export function Step(bot: Unit): boolean {
    const a = acts[bot.GetPlayerID()];
    if (a === undefined) return false;
    order(bot, a);
    return true;
}

/** Per game: the attempts and the cadence. */
export function ResetCache(): void {
    for (const k of Object.keys(acts)) delete acts[k as unknown as number];
    for (const k of Object.keys(decidedAt)) delete decidedAt[k as unknown as number];
    for (const k of Object.keys(deliveries)) delete deliveries[k as unknown as number];
    for (const k of Object.keys(refusedAt)) delete refusedAt[k as unknown as number];
}

export const _test = { acts, deliveries };
