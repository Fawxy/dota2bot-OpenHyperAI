/**
 * Sustain, carried out (design docs/proposals/2026-11-19-sustain-design.md in the master repo, step 3; switch `Ours.Sustain`).
 * For a held laner (Phase.LaningHeld, no drill hold), `ItemThink` runs the pure Decide on sustain_gather.ts's inputs and gives
 * the order for `use`, `step_out_use` and `give`; `home` and `buy` are logged only (retreat's heal and OHA's purchases still
 * act: steps 4 and 5). OHA's item loop leaves every heal and mana item on such a hero alone (`HoldsItem`).
 *
 * Where the orders run: an order with no walk (a self cast, a tango with the tree in range) from ItemUsageThink, in any mode,
 * as OHA's own item use does. A walk (a tango's tree, a step out to the safe spot, an ally out of cast range) starts only
 * while the laning mode or a camp job's supply step will yield the frame, and is carried on by the lane table's `sustain`
 * row (`Walking`/`Step`) or the supply step (`Yield`), so the body's own move does not undo it. One attempt runs at a time;
 * rule 1 (an instant heal under hits) may replace a running one. Each attempt logs `ev=sustain` at its end.
 */
import { BotMode, Item, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Sustain from "bots/FunLib/humaniser/sustain";
import * as SustainGather from "bots/FunLib/humaniser/sustain_gather";
import * as ItemUse from "bots/FunLib/humaniser/item_use";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare const BOT_ACTION_TYPE_USE_ABILITY: number;

/** API methods ts_libs does not declare yet. */
interface ActBot {
    GetCurrentActionType(): number;
}
interface RangeItem {
    GetCastRange(): number;
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
    /** The supply step yielded within this (s): a walk started from a camp job is still being carried. */
    YieldFresh: 0.3,
};

/** Cast on our own hero (OHA's cast type `unit` for these); a tree item on its tree; any other item has no target. */
const SELF: Record<string, true> = { item_flask: true, item_clarity: true };

interface Act {
    kind: "use" | "step_out_use" | "give";
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
const decidedAt: Record<number, number | undefined> = {};
const yieldedAt: Record<number, number | undefined> = {};

/** A hero sustain carries: the switch, a laner we hold, and no drill hold on its items (a lane-only cast without `castItems`, a rig's hold). */
export function Holds(bot: Unit): boolean {
    if (!Ours.On("Sustain") || bot.IsIllusion() || !Phase.LaningHeld(bot) || Drill.Held(bot)) return false;
    if (Drill.RigHoldsCasts(bot, true) === true) return false;
    return !(Overrides.LaneOnly(bot) && !Drill.CastItems(bot));
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

/** A walk can be carried now: the laning mode holds the hero (its `sustain` row steps it), or a camp job's supply step yields. */
function carried(bot: Unit, now: number): boolean {
    if (bot.GetActiveMode() === BotMode.Laning) return true;
    const y = yieldedAt[bot.GetPlayerID()];
    return y !== undefined && now - y <= SETTINGS.YieldFresh;
}

/** A walk may start: as `carried`, or a camp job runs whose supply step will yield to it. */
function canWalk(bot: Unit, now: number): boolean {
    return carried(bot, now) || CampJobs.Active(bot);
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

/** Gives the attempt's order for this frame (a walk's order again while it runs). */
function order(bot: Unit, a: Act): void {
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

/** Starts the answer's attempt, if it is one this step carries out and its order can be given now. */
function start(bot: Unit, i: Sustain.Inputs, ans: Sustain.Answer, now: number): void {
    if ((ans.kind !== "use" && ans.kind !== "step_out_use" && ans.kind !== "give") || ans.slot === undefined || ans.name === undefined) return;
    const name = `item_${ans.name}`;
    const item = itemIn(bot, ans.slot, name);
    if (item === undefined) return;
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
        if (t === undefined || i.tree === undefined) return;
        a.tree = t.id;
        a.walk = i.tree.walk;
    } else if (ans.kind === "step_out_use") {
        if (ans.at === undefined || i.safeSpot === undefined) return;
        a.spot = Vector(ans.at.x, ans.at.y, bot.GetLocation().z);
        a.walk = i.safeSpot.walk;
        const it = i.items.find((x) => x.slot === ans.slot);
        a.run = { kind: "step_out_use", slot: ans.slot, name: ans.name, started: now, hp0: i.hp, dur: a.walk + (it?.dur ?? 0), at: ans.at };
    } else if (ans.kind === "give") {
        const ally = ans.to !== undefined ? allyOf(ans.to) : undefined;
        if (ally === undefined) return;
        a.to = ans.to;
        a.walk = math.max(0, GetUnitToUnitDistance(bot, ally) - (item as unknown as RangeItem).GetCastRange()) / math.max(100, bot.GetCurrentMovementSpeed());
    }
    if (a.walk > 0 && !canWalk(bot, now)) return;
    a.deadline = now + a.walk + SETTINGS.StartWait;
    acts[bot.GetPlayerID()] = a;
    order(bot, a);
}

/** One frame of a running attempt: true once it has ended. */
function progress(bot: Unit, a: Act, now: number): boolean {
    if (a.kind === "step_out_use") {
        if (a.drunk !== true && !carried(bot, now) && now > a.at) {
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
    if (a.walk > 0 && !carried(bot, now) && now > a.at) {
        end(bot, "cut");
        return true;
    }
    if (now > a.deadline) {
        end(bot, "missed");
        return true;
    }
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
        return;
    }
    if (!Holds(bot)) {
        end(bot, "released");
        return;
    }
    const now = DotaTime();
    const hit = bot.WasRecentlyDamagedByAnyHero(1);
    const a = acts[pid];
    if (a !== undefined && !progress(bot, a, now) && !hit) return;
    const last = decidedAt[pid];
    if (last !== undefined && now - last < (hit ? SETTINGS.DecideHit : SETTINGS.DecideEvery)) return;
    decidedAt[pid] = now;
    SustainGather.NoteCourier(bot);
    const i = SustainGather.Gather(bot);
    const ans = Sustain.Decide(i);
    // Under hits a running attempt is asked again only for rule 1: an instant heal replaces it.
    if (acts[pid] !== undefined) {
        if (ans.reason !== "survive") return;
        end(bot, "cut");
    }
    SustainGather.Cut(bot, i, ans, true);
    start(bot, i, ans, now);
}

/** The lane table's `sustain` row: an attempt with a walk still to make wants the frame. */
export function Walking(bot: Unit): boolean {
    const a = acts[bot.GetPlayerID()];
    if (a === undefined || a.walk <= 0) return false;
    return a.kind !== "step_out_use" || a.drunk !== true;
}

/** The row's run: the walk's order again. True: the frame is taken. */
export function Step(bot: Unit): boolean {
    const a = acts[bot.GetPlayerID()];
    if (a === undefined) return false;
    order(bot, a);
    return true;
}

/** camp_jobs' supply step under `Ours.Sustain`: true while an attempt walks, its order given, so the job leaves the frame to it. */
export function Yield(bot: Unit): boolean {
    if (!Walking(bot)) return false;
    yieldedAt[bot.GetPlayerID()] = DotaTime();
    return Step(bot);
}

/** Per game: the attempts and the cadence. */
export function ResetCache(): void {
    for (const k of Object.keys(acts)) delete acts[k as unknown as number];
    for (const k of Object.keys(decidedAt)) delete decidedAt[k as unknown as number];
    for (const k of Object.keys(yieldedAt)) delete yieldedAt[k as unknown as number];
}

export const _test = { acts };
