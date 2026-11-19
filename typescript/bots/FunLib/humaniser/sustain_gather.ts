/**
 * Sustain, the game side (design docs/proposals/2026-11-19-sustain-design.md in the master repo, steps 2 and 3): `Gather`
 * reads `Sustain.Inputs` from the game once, and `Tick` runs the pure `Decide` on them in shadow and logs `ev=cut kind=sustain`
 * for every hero that sustain_act.ts does not carry out (with `Ours.Sustain`, a held hero's line is that module's).
 *
 * The danger inputs are the safe-here read's (safe_gather.ts `FromRead` on the one stay read made here): the kill line's
 * `kill`, who is hitting, and the read over the walk to a tree. Its lane-opponent rows replace step 2's own lane memory.
 *
 * Items are data: ITEMS names the special values one use is read from (the item's own values at run time, as `ev=regen_win`
 * reads them) and what the modifier does (hero damage ends it; read from the item's description, not the API).
 * `ev=sustain_item` logs each item's read values once a game, so a wrong key shows as a 0.
 * What a purchase restores comes from the same reads (an item no hero of ours has held yet is not offered); its price from
 * GetItemCost.
 *
 * Also the step's other telemetry: `ev=sustain_buy` (OHA's lane regen purchases with their rule, `Bought`), `ev=sustain_courier` (a
 * courier state change). Who started a regen buff is item_use.ts's `Used` (regen_obs `by`).
 */
import { Item, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Sustain from "bots/FunLib/humaniser/sustain";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as Safe from "bots/FunLib/humaniser/safe";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
import * as Retreat from "bots/FunLib/humaniser/retreat";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Laning from "bots/FunLib/humaniser/states/laning";

declare function GetTreeLocation(tree: number): Vector;
declare function GetCourier(n: number): Unit | undefined;
declare function GetCourierState(c: Unit): number;
declare function GetItemStockCount(name: string): number;
declare const COURIER_STATE_IDLE: number;
declare const COURIER_STATE_AT_BASE: number;
declare const COURIER_STATE_DEAD: number;
declare const COURIER_STATE_MOVING: number;
declare const COURIER_STATE_DELIVERING_ITEMS: number;

interface SpecItem {
    GetSpecialValueFloat(name: string): number;
    GetCastRange(): number;
}
interface TreeBot {
    GetNearbyTrees(radius: number): number[];
}

/**
 * How one use of an item is read. `hp`/`mp`: a total key, or `[per second, duration]`; `dur` the duration key (0 instant);
 * `perCharge`: the restore is per stored charge and one use spends them all (wand, stick).
 */
interface Spec {
    hp?: string | [string, string];
    mp?: string | [string, string];
    dur?: string;
    perCharge?: boolean;
    /** The buff it starts, for what a running one still restores. */
    mod?: string;
    breaks: boolean;
    tree: boolean;
    refill: boolean;
    share: boolean;
    /** Sold at the fountain shop as a lane regen purchase. */
    shop: boolean;
}

/**
 * `breaks`: salve and clarity end on damage from a hero (their descriptions; regen_obs `early` ends agree); a tango does not.
 * The bottle's is not confirmed: true is the cautious reading (a use only with no hero hitting or in reach) until a rig says.
 */
export const ITEMS: Record<string, Spec> = {
    item_tango: { hp: ["health_regen", "buff_duration"], dur: "buff_duration", mod: "modifier_tango_heal", breaks: false, tree: true, refill: false, share: true, shop: true },
    item_tango_single: { hp: ["health_regen", "buff_duration"], dur: "buff_duration", mod: "modifier_tango_heal", breaks: false, tree: true, refill: false, share: false, shop: false },
    item_flask: { hp: ["health_regen", "buff_duration"], dur: "buff_duration", mod: "modifier_flask_healing", breaks: true, tree: false, refill: false, share: false, shop: true },
    item_clarity: { mp: ["mana_regen", "buff_duration"], dur: "buff_duration", mod: "modifier_clarity_potion", breaks: true, tree: false, refill: false, share: false, shop: true },
    item_bottle: { hp: "health_restore", mp: "mana_restore", dur: "restore_time", mod: "modifier_bottle_regeneration", breaks: true, tree: false, refill: true, share: false, shop: false },
    item_faerie_fire: { hp: "hp_restore", breaks: false, tree: false, refill: false, share: false, shop: true },
    item_enchanted_mango: { mp: "replenish_amount", breaks: false, tree: false, refill: false, share: false, shop: true },
    item_magic_stick: { hp: "restore_per_charge", mp: "restore_per_charge", perCharge: true, breaks: false, tree: false, refill: false, share: false, shop: false },
    item_magic_wand: { hp: "restore_per_charge", mp: "restore_per_charge", perCharge: true, breaks: false, tree: false, refill: false, share: false, shop: false },
};

export const SETTINGS = {
    /** A tree within this is the nearest tree read (regen_obs's scan). */
    TreeScan: 1200,
    /** A tango's cast range when the item's own cannot be read (API: 165). */
    TangoRange: 165,
    /** Lane allies within this (design section 2). */
    AllyRadius: 800,
    /** The safe spot is re-read at most this often per hero (s): retreat's anchor choice walks routes. judgement. */
    SafeEvery: 1,
    /** Shadow: the decision runs at most this often per hero (s); the cut logs a change at once (to this) and else every CutEvery. */
    DecideEvery: 0.5,
    CutEvery: 2,
    /** The laning stage the shadow covers (s), as the trade cut's. */
    Until: 720,
};

// --------------------------------------------------------------------------------------------------------------- reads

/** Per item name: the most charges seen (what a purchase holds), and what one charge restores per second (a running buff). */
const learned: Record<string, { pack: number; hp: number; mp: number; hpRate: number; mpRate: number } | undefined> = {};
/** Per hero: the charges of each item held at the last read, for a purchase's size. */
const heldCharges: Record<number, Record<string, number> | undefined> = {};
const itemLogged: Record<string, boolean> = {};

function val(it: SpecItem, key: string | [string, string] | undefined): number {
    if (key === undefined) return 0;
    if (typeof key === "string") return it.GetSpecialValueFloat(key) ?? 0;
    return (it.GetSpecialValueFloat(key[0]) ?? 0) * (it.GetSpecialValueFloat(key[1]) ?? 0);
}

const r1 = (v: number): number => math.floor(v * 10 + 0.5) / 10;
/** One decimal as record text, with no trailing ".0" on whole numbers (the test runner's Lua 5.3 prints 112 as "112.0", the game's Lua as "112"). */
const t1 = (v: number): string => string.format("%.10g", r1(v));

/** One item in a slot as the decision's Item, or undefined when it is not a heal or mana item. */
function readItem(slot: number, item: Item): Sustain.Item | undefined {
    const name = item.GetName();
    const spec = ITEMS[name];
    if (spec === undefined) return undefined;
    const it = item as unknown as SpecItem;
    const charges = item.GetCurrentCharges() ?? 0;
    let hp = val(it, spec.hp);
    let mp = val(it, spec.mp);
    // Logged before a per-charge item's values are multiplied by its charges: an empty wand's key still shows.
    const hpRead = hp;
    const mpRead = mp;
    const dur = spec.dur !== undefined ? it.GetSpecialValueFloat(spec.dur) ?? 0 : 0;
    let uses = charges;
    if (spec.perCharge) {
        hp *= charges;
        mp *= charges;
        uses = charges > 0 ? 1 : 0;
    } else if (name === "item_tango_single" || (charges === 0 && !spec.refill)) {
        // A single-use item with no charge count (a shared tango) is one use.
        uses = 1;
    }
    const l = (learned[name] ??= { pack: 0, hp: 0, mp: 0, hpRate: 0, mpRate: 0 });
    if (!spec.perCharge) {
        l.hp = hp;
        l.mp = mp;
        if (dur > 0) {
            l.hpRate = hp / dur;
            l.mpRate = mp / dur;
        }
    }
    if (!itemLogged[name]) {
        itemLogged[name] = true;
        Telemetry.Event("sustain_item", [
            ["name", name],
            ["hp", r1(hpRead)],
            ["mp", r1(mpRead)],
            ["dur", r1(dur)],
            ["ch", charges],
        ]);
    }
    const ready = slot <= 5 && item.IsFullyCastable();
    return { slot, name: string.gsub(name, "^item_", "")[0], charges: uses, hp, mp, dur, breaks: spec.breaks, tree: spec.tree, refill: spec.refill, share: spec.share, ready };
}

/** The heal and mana items in slots 0-8 (the backpack counts: a swap brings one out). */
export function Items(bot: Unit): Sustain.Item[] {
    const out: Sustain.Item[] = [];
    const now: Record<string, number> = {};
    for (let s = 0; s <= 8; s++) {
        const item = bot.GetItemInSlot(s);
        if (item === undefined || item === null) continue;
        const it = readItem(s, item);
        if (it === undefined) continue;
        out.push(it);
        const name = item.GetName();
        now[name] = (now[name] ?? 0) + (item.GetCurrentCharges() ?? 0);
    }
    // What one purchase holds: the smallest rise in a hero's charges of an item (two stacked tango packs read 6 at once).
    const before = (heldCharges[bot.GetPlayerID()] ??= {});
    for (const [name, n] of pairs(now)) {
        const rise = n - (before[name] ?? 0);
        const l = learned[name];
        if (l !== undefined && rise > 0 && (l.pack === 0 || rise < l.pack)) l.pack = rise;
    }
    heldCharges[bot.GetPlayerID()] = now;
    return out;
}

/** HP and mana the regen buffs on the bot still restore: the buff's time left times the rate read from the item. */
function regenLeft(bot: Unit): [number, number] {
    let hp = 0;
    let mp = 0;
    const done: Record<string, boolean> = {};
    for (const [name, spec] of pairs(ITEMS)) {
        if (spec.mod === undefined || done[spec.mod] || !bot.HasModifier(spec.mod)) continue;
        // A buff two items start (tango, a shared tango) counts once, from whichever of them has been read.
        const l = learned[name];
        if (l === undefined || l.hpRate + l.mpRate === 0) continue;
        done[spec.mod] = true;
        const left = bot.GetModifierRemainingDuration(bot.GetModifierByName(spec.mod));
        hp += left * l.hpRate;
        mp += left * l.mpRate;
    }
    return [hp, mp];
}

const valid = (u: Unit | undefined | null): u is Unit => u !== undefined && u !== null && !u.IsNull() && u.IsAlive();
const dist = (a: Vector, b: Vector): number => math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);

/** Per hero: the tree the last read chose (its id, for the executor's order), with when it was read. */
const trees: Record<number, { at: number; id: number; loc: Vector; tree: NonNullable<Sustain.Inputs["tree"]> } | undefined> = {};

/** The tree the last Gather chose for this hero, if any: the executor's target. */
export function TreeOf(bot: Unit): { id: number; loc: Vector } | undefined {
    const t = trees[bot.GetPlayerID()];
    return t !== undefined ? { id: t.id, loc: t.loc } : undefined;
}

/**
 * The tree a tango walks to, read only with a tree item held. Two candidates among the visible, passable trees in the
 * scan: the nearest, and, with a safe spot, the one on the shortest detour from here to it (toward our side: a hero backs
 * off and eats on the way). Each walk is the seconds into the item's cast range of it, and safe when the safe-here read
 * over it (the trip gates' horizon) is not `deadly`; none needed for a tree already in range. The nearer safe one is
 * chosen, else the nearest (unsafe). Re-read at most every SafeEvery per hero (a read walks every enemy).
 */
function treeOf(bot: Unit, items: Sustain.Item[], now: number, spot: Sustain.Inputs["safeSpot"]): Sustain.Inputs["tree"] {
    const pid = bot.GetPlayerID();
    let slot: number | undefined;
    for (const it of items) if (it.tree && it.charges > 0 && (slot === undefined || it.ready === true)) slot = it.slot;
    if (slot === undefined) {
        trees[pid] = undefined;
        return undefined;
    }
    const c = trees[pid];
    if (c !== undefined && now - c.at < SETTINGS.SafeEvery) return c.tree;
    const here = bot.GetLocation();
    const goal = spot;
    let near: { id: number; loc: Vector; d: number } | undefined;
    let back: { id: number; loc: Vector; d: number; via: number } | undefined;
    for (const tree of (bot as unknown as TreeBot).GetNearbyTrees(SETTINGS.TreeScan) ?? []) {
        const loc = GetTreeLocation(tree);
        if (!IsLocationVisible(loc) || !IsLocationPassable(loc)) continue;
        const d = GetUnitToLocationDistance(bot, loc);
        if (near === undefined || d < near.d) near = { id: tree, loc, d };
        if (goal !== undefined) {
            const via = d + math.sqrt((loc.x - goal.x) ** 2 + (loc.y - goal.y) ** 2);
            if (back === undefined || via < back.via) back = { id: tree, loc, d, via };
        }
    }
    if (near === undefined) {
        trees[pid] = undefined;
        return undefined;
    }
    const item = bot.GetItemInSlot(slot);
    const range = item !== undefined && item !== null ? (item as unknown as SpecItem).GetCastRange() : 0;
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const judge = (t: { loc: Vector; d: number }): { walk: number; safe: boolean } => {
        const walk = math.max(0, t.d - (range > 0 ? range : SETTINGS.TangoRange)) / speed;
        if (walk <= 0) return { walk, safe: true };
        const r = Threat.Read(bot, here, t.loc, Threat.SETTINGS.GateHorizon);
        return { walk, safe: Safe.Decide(SafeGather.FromRead(bot, r, { away: false, held: false, hold: false })).level !== "deadly" };
    };
    let pick = near;
    let tree = judge(near);
    if (!tree.safe && back !== undefined && back.id !== near.id) {
        const t2 = judge(back);
        if (t2.safe) {
            pick = back;
            tree = t2;
        }
    }
    trees[pid] = { at: now, id: pick.id, loc: pick.loc, tree };
    return tree;
}

/** The safe-here read here, from the one stay read Gather makes: what the reachers can deal, whether one is hitting us, and the visible ones in reach. */
function safeHere(bot: Unit, r: Threat.Read): [Sustain.Inputs["safe"], boolean] {
    const i = SafeGather.FromRead(bot, r, { away: false, held: true, hold: false });
    const a = Safe.Decide(i);
    let hitting = false;
    let reach = 0;
    for (const x of i.reach) {
        if (x.hitting) hitting = true;
        if (x.unseen !== true) reach += 1;
    }
    return [{ kill: a.kill, hitting, reach, pressed: Safe.Pressed(i) }, a.level === "deadly"];
}

const safeCache: Record<number, { at: number; spot?: Sustain.Inputs["safeSpot"]; okAt?: number } | undefined> = {};

/**
 * The safe spot, re-read at most every SafeEvery. `deep`: we stand under the kill line, so rule 2 may wait there: the safe-here
 * read at the spot (held: the wait is a standing answer) says whether it is deadly. Read only then (a read walks every enemy).
 */
function safeSpot(bot: Unit, now: number, deep: boolean): Sustain.Inputs["safeSpot"] {
    const pid = bot.GetPlayerID();
    let c = safeCache[pid];
    if (c === undefined || now - c.at >= SETTINGS.SafeEvery) {
        const a = Retreat.SafeSpot(bot);
        c = { at: now, spot: a !== undefined ? { x: a.at.x, y: a.at.y, walk: a.secs } : undefined };
        safeCache[pid] = c;
    }
    const spot = c.spot;
    if (spot === undefined || !deep) return spot;
    if (c.okAt === undefined || now - c.okAt >= SETTINGS.SafeEvery) {
        c.okAt = now;
        spot.ok = SafeGather.At(bot, Vector(spot.x, spot.y, bot.GetLocation().z), { held: true }).level !== "deadly";
    }
    return spot;
}

/** A slot in 0-8 free for a purchase to land in. */
function roomOf(bot: Unit): boolean {
    for (let s = 0; s <= 8; s++) {
        const it = bot.GetItemInSlot(s);
        if (it === undefined || it === null) return true;
    }
    return false;
}

export function CourierOf(bot: Unit): Unit | undefined {
    for (let n = 0; n <= 4; n++) {
        const c = GetCourier(n);
        if (c !== undefined && c !== null && c.GetPlayerID() === bot.GetPlayerID()) return c;
    }
    return undefined;
}

/** The courier free and alive: seconds for it to fetch a purchase from the fountain and bring it to the bot. */
function courierEta(bot: Unit, c: Unit | undefined, fountain: Vector): Sustain.Inputs["courier"] {
    if (c === undefined) return undefined;
    const st = GetCourierState(c);
    if (st !== COURIER_STATE_IDLE && st !== COURIER_STATE_AT_BASE) return undefined;
    const v = math.max(100, c.GetCurrentMovementSpeed());
    return { eta: (dist(c.GetLocation(), fountain) + dist(fountain, bot.GetLocation())) / v };
}

/**
 * Regen on its way to the hero, read from the game (whoever bought it): heal and mana items in its stash (slots 9-14) or on its
 * courier, what they restore (their own values, as held items are read) and the seconds until they can land: the courier's
 * walk to us when it is out delivering or moving, else to the fountain and then to us. None on the way: undefined.
 */
export function OnTheWay(bot: Unit, c: Unit | undefined = CourierOf(bot), fountain: Vector = Retreat.Fountain(bot.GetTeam())): Sustain.Inputs["delivery"] {
    let hp = 0;
    let mp = 0;
    let found = false;
    const add = (slot: number, item: Item | undefined | null): void => {
        if (item === undefined || item === null) return;
        const it = readItem(slot, item);
        // An item that restores nothing now (an empty wand, stick or bottle from the item build) is not regen on the way (review).
        if (it === undefined || it.hp * it.charges + it.mp * it.charges <= 0) return;
        found = true;
        hp += it.hp * math.max(1, it.charges);
        mp += it.mp * math.max(1, it.charges);
    };
    for (let s = 9; s <= 14; s++) add(s, bot.GetItemInSlot(s));
    const st = c !== undefined ? GetCourierState(c) : COURIER_STATE_DEAD;
    if (c !== undefined && st !== COURIER_STATE_DEAD) for (let s = 0; s <= 8; s++) add(s, c.GetItemInSlot(s));
    if (!found) return undefined;
    let eta = math.huge;
    if (c !== undefined && st !== COURIER_STATE_DEAD) {
        const v = math.max(100, c.GetCurrentMovementSpeed());
        const out = st === COURIER_STATE_DELIVERING_ITEMS || st === COURIER_STATE_MOVING;
        eta = out ? dist(c.GetLocation(), bot.GetLocation()) / v : (dist(c.GetLocation(), fountain) + dist(fountain, bot.GetLocation())) / v;
    }
    return { hp, mp, eta };
}

/** The lane regen the fountain sells now: price from GetItemCost, what one purchase restores from an item of ours read before. */
function shopOf(): Sustain.Offer[] {
    const out: Sustain.Offer[] = [];
    for (const [name, spec] of pairs(ITEMS)) {
        const l = learned[name];
        if (!spec.shop || l === undefined || GetItemStockCount(name) <= 0) continue;
        const n = math.max(1, l.pack);
        out.push({ name: string.gsub(name, "^item_", "")[0], cost: GetItemCost(name), hp: l.hp * n, mp: l.mp * n });
    }
    return out;
}

/** Heal items an ally holds (uses of an item restoring HP over time). */
function healsOf(a: Unit): number {
    let n = 0;
    for (let s = 0; s <= 8; s++) {
        const item = a.GetItemInSlot(s);
        if (item === undefined || item === null) continue;
        const spec = ITEMS[item.GetName()];
        if (spec !== undefined && spec.hp !== undefined && spec.dur !== undefined) n += math.max(1, item.GetCurrentCharges() ?? 0);
    }
    return n;
}

/** The inputs of one frame, read from the game once. `run` is the executor's running answer (none in shadow). */
export function Gather(bot: Unit, run?: Sustain.Run): Sustain.Inputs {
    const now = DotaTime();
    const here = bot.GetLocation();
    const hp = bot.GetHealth();
    const stay = Threat.Read(bot, here, here, Threat.SETTINGS.StayHorizon, { engagedWindow: Threat.SETTINGS.StayEngaged });
    const items = Items(bot);
    const [safe, deadlyHere] = safeHere(bot, stay);
    // A walk does not start where we stand deadly, whatever the read over it says (that read has no engaged window: smoke 1,
    // a tango walk started under a lethal leave). It still counts in rule 2's reach (review: as one flag it sent harassed
    // heroes holding tangos `home`, which step 3 does not carry, so nothing was eaten).
    const hpMax = bot.GetMaxHealth();
    // Rule 2 fires only under the kill line (what we reach is at least our HP): the spot's own read is made only then.
    const spot = safeSpot(bot, now, hp < Sustain.KillLine({ hpMax, safe } as Sustain.Inputs));
    const t = treeOf(bot, items, now, spot);
    const tree = t !== undefined ? { walk: t.walk, safe: t.safe, start: !(t.walk > 0 && deadlyHere) } : undefined;
    const [rl, ml] = regenLeft(bot);
    const fountain = Retreat.Fountain(bot.GetTeam());
    const courier = CourierOf(bot);
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const allies: Sustain.Inputs["allies"] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!valid(a) || a === bot || a.IsIllusion() || GetUnitToUnitDistance(bot, a) > SETTINGS.AllyRadius) continue;
        allies.push({ pid: a.GetPlayerID(), missing: a.GetMaxHealth() - a.GetHealth(), heals: healsOf(a) });
    }
    return {
        now,
        hp,
        hpMax,
        mp: bot.GetMana(),
        mpMax: bot.GetMaxMana(),
        items,
        tree,
        // The next hit matters only to a tango walk: read with a tree in hand (laneTargets walks the wave).
        nextDue: tree !== undefined ? Laning.NextDue(bot) : undefined,
        hitRecently: bot.WasRecentlyDamagedByAnyHero(2),
        safe,
        regenLeft: rl,
        manaLeft: ml,
        safeSpot: spot,
        delivery: OnTheWay(bot, courier, fountain),
        room: roomOf(bot),
        gold: bot.GetGold(),
        courier: courierEta(bot, courier, fountain),
        shop: shopOf(),
        home: (2 * dist(here, fountain)) / speed,
        idle: CampJobs.Active(bot),
        atFountain: bot.HasModifier("modifier_fountain_aura_buff"),
        allies,
        run,
    };
}

// ----------------------------------------------------------------------------------------------------------- the cut line

const n0 = (v: number): number => math.floor(v + 0.5);
const b01 = (b: boolean): number => (b ? 1 : 0);

/** Items as `slot,name,uses,hp,mp,dur,breaks,tree,refill,share,ready` joined by `;`. */
export function ItemsText(items: Sustain.Item[]): string {
    const out: string[] = [];
    for (const it of items)
        out.push([it.slot, it.name, it.charges, t1(it.hp), t1(it.mp), t1(it.dur), b01(it.breaks), b01(it.tree), b01(it.refill), b01(it.share), b01(it.ready !== false)].join(","));
    return out.join(";");
}

/** The `ev=cut kind=sustain` fields for these inputs and answer (tools/hlog/sustain_diff.js reads them back into Inputs). */
export function CutFields(pid: number, i: Sustain.Inputs, a: Sustain.Answer): Telemetry.Fields<"cut"> {
    const shop: string[] = [];
    for (const o of i.shop) shop.push([o.name, o.cost, t1(o.hp), t1(o.mp)].join(","));
    const al: string[] = [];
    for (const x of i.allies) al.push([x.pid, n0(x.missing), x.heals].join(","));
    return [
        ["pid", pid],
        ["kind", "sustain"],
        ["hpa", n0(i.hp)],
        ["hpm", n0(i.hpMax)],
        ["mpa", n0(i.mp)],
        ["mpm", n0(i.mpMax)],
        ["it", i.items.length > 0 ? ItemsText(i.items) : undefined],
        ["tr", i.tree !== undefined ? `${t1(i.tree.walk)},${b01(i.tree.safe)},${b01(i.tree.start !== false)}` : undefined],
        ["nd", i.nextDue !== undefined ? r1(i.nextDue) : undefined],
        ["hr", b01(i.hitRecently)],
        ["kill", n0(i.safe.kill)],
        ["sh", b01(i.safe.hitting)],
        ["spr", b01(i.safe.pressed === true || i.safe.hitting)],
        ["rc", i.safe.reach],
        ["rl", n0(i.regenLeft)],
        ["ml", n0(i.manaLeft)],
        ["ss", i.safeSpot !== undefined ? `${n0(i.safeSpot.x)},${n0(i.safeSpot.y)},${t1(i.safeSpot.walk)},${b01(i.safeSpot.ok !== false)}` : undefined],
        ["dl", i.delivery !== undefined ? `${n0(i.delivery.hp)},${n0(i.delivery.mp)},${t1(i.delivery.eta)}` : undefined],
        ["rom", b01(i.room !== false)],
        ["gd", n0(i.gold)],
        ["co", i.courier !== undefined ? r1(i.courier.eta) : undefined],
        ["shp", shop.length > 0 ? shop.join(";") : undefined],
        ["ho", r1(i.home)],
        ["idl", b01(i.idle)],
        ["af", b01(i.atFountain)],
        ["als", al.length > 0 ? al.join(";") : undefined],
        ["ak", a.kind],
        ["anm", a.name],
        ["ato", a.to],
        ["alb", a.also],
        ["why", a.reason],
        ["ed", a.ended],
    ];
}

const cutState: Record<number, { key?: string; at: number; decidedAt: number } | undefined> = {};

/** The cut line for one decision: on a changed answer, else every CutEvery. `acted`: sustain_act.ts carries it out. */
export function Cut(bot: Unit, i: Sustain.Inputs, a: Sustain.Answer, acted: boolean): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true) return;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const st = (cutState[pid] ??= { at: -math.huge, decidedAt: -math.huge });
    const key = `${a.kind}:${a.name}:${a.reason}:${a.ended}`;
    if (key === st.key && now - st.at < SETTINGS.CutEvery) return;
    st.key = key;
    st.at = now;
    const f = CutFields(pid, i, a);
    if (acted) f.push(["act", 1]);
    Telemetry.Event("cut", f);
}

/** Shadow: every hero in the laning stage, both teams, that sustain_act.ts does not carry out (index.ts asks); the answer is logged, never carried out. */
export function Tick(bot: Unit): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || !bot.IsAlive()) return;
    const now = DotaTime();
    if (now < 0 || now > SETTINGS.Until) return;
    const pid = bot.GetPlayerID();
    const st = (cutState[pid] ??= { at: -math.huge, decidedAt: -math.huge });
    if (now - st.decidedAt < SETTINGS.DecideEvery) return;
    st.decidedAt = now;
    noteCourier(bot);
    const i = Gather(bot);
    Cut(bot, i, Sustain.Decide(i), false);
}

/** The courier telemetry for a hero sustain_act.ts carries (its Tick is not asked). */
export function NoteCourier(bot: Unit): void {
    noteCourier(bot);
}

// ------------------------------------------------------------------------------------------------------ other telemetry

const courierSeen: Record<number, number | undefined> = {};

/** `ev=sustain_courier` when the hero's courier changes state (an order shows as its effect: moving, delivering, back at base). */
function noteCourier(bot: Unit): void {
    const c = CourierOf(bot);
    if (c === undefined) return;
    const st = GetCourierState(c);
    const pid = bot.GetPlayerID();
    if (courierSeen[pid] === st) return;
    courierSeen[pid] = st;
    Telemetry.Event("sustain_courier", [
        ["pid", pid],
        ["st", st],
        ["dead", st === COURIER_STATE_DEAD ? 1 : 0],
        ["d", n0(GetUnitToUnitDistance(bot, c))],
    ]);
}

/** OHA's lane regen purchase rules call this beside each regen purchase (`item_purchase_generic.lua`). */
export function Bought(bot: Unit, name: string, why: string): void {
    if (!Telemetry.IsEnabled()) return;
    Telemetry.Event("sustain_buy", [
        ["pid", bot.GetPlayerID()],
        ["item", name],
        ["why", why],
        ["gold", bot.GetGold()],
        ["hp", bot.GetMaxHealth() > 0 ? r1((bot.GetHealth() / bot.GetMaxHealth()) * 100) : -1],
        ["mp", bot.GetMaxMana() > 0 ? r1((bot.GetMana() / bot.GetMaxMana()) * 100) : -1],
    ]);
}

export const _test = { learned, cutState, trees };
