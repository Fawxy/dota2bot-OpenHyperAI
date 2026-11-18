/**
 * Sustain, the game side (design docs/proposals/2026-11-19-sustain-design.md in the master repo, step 2): `Gather` reads
 * `Sustain.Inputs` from the game once, and `Tick` runs the pure `Decide` on them in shadow and logs `ev=cut kind=sustain`.
 * Nothing acts on the answer: no order, no gate. Step 3 gives it an executor under `Ours.Sustain`.
 *
 * Items are data: ITEMS names the special values one use is read from (the item's own values at run time, as `ev=regen_win`
 * reads them) and what the modifier does (hero damage ends it; read from the item's description, not the API).
 * `ev=sustain_item` logs each item's read values once a game, so a wrong key shows as a 0.
 * What a purchase restores comes from the same reads (an item no hero of ours has held yet is not offered); its price from
 * GetItemCost.
 *
 * Also the step's other telemetry: `ev=sustain_buy` (OHA's lane regen purchases with their rule, `Bought`), `ev=courier` (a
 * courier state change). Who started a regen buff is item_use.ts's `Used` (regen_obs `by`).
 */
import { Item, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Sustain from "bots/FunLib/humaniser/sustain";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as Retreat from "bots/FunLib/humaniser/retreat";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";

declare function GetTreeLocation(tree: number): Vector;
declare function GetCourier(n: number): Unit | undefined;
declare function GetCourierState(c: Unit): number;
declare function GetItemStockCount(name: string): number;
declare const COURIER_STATE_IDLE: number;
declare const COURIER_STATE_AT_BASE: number;
declare const COURIER_STATE_DEAD: number;

interface SpecItem {
    GetSpecialValueFloat(name: string): number;
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
    /** laneBurst counts an enemy hero seen this recently (design section 2). */
    LaneSeen: 10,
    /** An enemy hero this near is one of the lane's (judgement: a lane's width plus a hero's walk to it). */
    LaneRadius: 2000,
    /** A tree within this is the nearest tree read (regen_obs's scan). */
    TreeScan: 1200,
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
const learned: Record<string, { maxCharges: number; hp: number; mp: number; hpRate: number; mpRate: number } | undefined> = {};
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
    const l = (learned[name] ??= { maxCharges: 0, hp: 0, mp: 0, hpRate: 0, mpRate: 0 });
    if (!spec.perCharge) {
        if (charges > l.maxCharges) l.maxCharges = charges;
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
            ["hp", r1(hp)],
            ["mp", r1(mp)],
            ["dur", r1(dur)],
            ["ch", charges],
        ]);
    }
    return { slot, name: string.gsub(name, "^item_", "")[0], charges: uses, hp, mp, dur, breaks: spec.breaks, tree: spec.tree, refill: spec.refill, share: spec.share };
}

/** The heal and mana items in slots 0-8 (the backpack counts: a swap brings one out). */
export function Items(bot: Unit): Sustain.Item[] {
    const out: Sustain.Item[] = [];
    for (let s = 0; s <= 8; s++) {
        const item = bot.GetItemInSlot(s);
        if (item === undefined || item === null) continue;
        const it = readItem(s, item);
        if (it !== undefined) out.push(it);
    }
    return out;
}

/** HP and mana the regen buffs on the bot still restore: the buff's time left times the rate read from the item. */
function regenLeft(bot: Unit): [number, number] {
    let hp = 0;
    let mp = 0;
    const done: Record<string, boolean> = {};
    for (const [name, spec] of pairs(ITEMS)) {
        if (spec.mod === undefined || done[spec.mod] || !bot.HasModifier(spec.mod)) continue;
        done[spec.mod] = true;
        const l = learned[name];
        if (l === undefined) continue;
        const left = bot.GetModifierRemainingDuration(bot.GetModifierByName(spec.mod));
        hp += left * l.hpRate;
        mp += left * l.mpRate;
    }
    return [hp, mp];
}

const valid = (u: Unit | undefined | null): u is Unit => u !== undefined && u !== null && !u.IsNull() && u.IsAlive();
const dist = (a: Vector, b: Vector): number => math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);

/** The nearest visible, passable tree, and the nearest visible enemy hero's distance to it. */
function treeOf(bot: Unit, enemies: Unit[]): Sustain.Inputs["tree"] {
    let best: Vector | undefined;
    let bestD = math.huge;
    for (const tree of (bot as unknown as TreeBot).GetNearbyTrees(SETTINGS.TreeScan) ?? []) {
        const loc = GetTreeLocation(tree);
        if (!IsLocationVisible(loc) || !IsLocationPassable(loc)) continue;
        const d = GetUnitToLocationDistance(bot, loc);
        if (d < bestD) {
            bestD = d;
            best = loc;
        }
    }
    if (best === undefined) return undefined;
    let enemyD = math.huge;
    for (const e of enemies) enemyD = math.min(enemyD, dist(e.GetLocation(), best));
    return { d: bestD, enemyD };
}

/** Per bot, per enemy pid: the damage it could deal us over the burst window when last seen in our lane, and when. */
const laneSeen: Record<number, Record<number, { dmg: number; at: number } | undefined>> = {};

function laneBurst(bot: Unit, enemies: Unit[], now: number): number {
    const mine = (laneSeen[bot.GetPlayerID()] ??= {});
    for (const e of enemies) {
        if (GetUnitToUnitDistance(bot, e) > SETTINGS.LaneRadius) continue;
        mine[e.GetPlayerID()] = { dmg: SpellReady.DamageOn(e, bot, Threat.SETTINGS.BurstWindow), at: now };
    }
    let sum = 0;
    for (const [, s] of pairs(mine)) if (s !== undefined && now - s.at <= SETTINGS.LaneSeen) sum += s.dmg;
    return sum;
}

const safeCache: Record<number, { at: number; spot?: Sustain.Inputs["safeSpot"] } | undefined> = {};

function safeSpot(bot: Unit, now: number): Sustain.Inputs["safeSpot"] {
    const c = safeCache[bot.GetPlayerID()];
    if (c !== undefined && now - c.at < SETTINGS.SafeEvery) return c.spot;
    const a = Retreat.SafeSpot(bot);
    const spot = a !== undefined ? { x: a.at.x, y: a.at.y, walk: a.secs } : undefined;
    safeCache[bot.GetPlayerID()] = { at: now, spot };
    return spot;
}

function courierOf(bot: Unit): Unit | undefined {
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

/** The lane regen the fountain sells now: price from GetItemCost, what one purchase restores from an item of ours read before. */
function shopOf(): Sustain.Offer[] {
    const out: Sustain.Offer[] = [];
    for (const [name, spec] of pairs(ITEMS)) {
        const l = learned[name];
        if (!spec.shop || l === undefined || GetItemStockCount(name) <= 0) continue;
        const n = math.max(1, l.maxCharges);
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
    const enemies: Unit[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) if (valid(e) && e.CanBeSeen() && !e.IsIllusion()) enemies.push(e);
    const stay = Threat.Read(bot, here, here, Threat.SETTINGS.StayHorizon, { engagedWindow: Threat.SETTINGS.StayEngaged });
    const [rl, ml] = regenLeft(bot);
    const fountain = Retreat.Fountain(bot.GetTeam());
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const allies: Sustain.Inputs["allies"] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!valid(a) || a === bot || a.IsIllusion() || GetUnitToUnitDistance(bot, a) > SETTINGS.AllyRadius) continue;
        allies.push({ pid: a.GetPlayerID(), missing: a.GetMaxHealth() - a.GetHealth(), heals: healsOf(a) });
    }
    return {
        now,
        hp,
        hpMax: bot.GetMaxHealth(),
        mp: bot.GetMana(),
        mpMax: bot.GetMaxMana(),
        items: Items(bot),
        tree: treeOf(bot, enemies),
        hitRecently: bot.WasRecentlyDamagedByAnyHero(2),
        burst: stay.burst * hp,
        reach: stay.reach.length,
        laneBurst: laneBurst(bot, enemies, now),
        regenLeft: rl,
        manaLeft: ml,
        safeSpot: safeSpot(bot, now),
        gold: bot.GetGold(),
        courier: courierEta(bot, courierOf(bot), fountain),
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

/** Items as `slot,name,uses,hp,mp,dur,breaks,tree,refill,share` joined by `;`. */
export function ItemsText(items: Sustain.Item[]): string {
    const out: string[] = [];
    for (const it of items) out.push([it.slot, it.name, it.charges, t1(it.hp), t1(it.mp), t1(it.dur), b01(it.breaks), b01(it.tree), b01(it.refill), b01(it.share)].join(","));
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
        ["tr", i.tree !== undefined ? `${n0(i.tree.d)},${i.tree.enemyD === math.huge ? -1 : n0(i.tree.enemyD)}` : undefined],
        ["hr", b01(i.hitRecently)],
        ["bua", n0(i.burst)],
        ["rc", i.reach],
        ["lb", n0(i.laneBurst)],
        ["rl", n0(i.regenLeft)],
        ["ml", n0(i.manaLeft)],
        ["ss", i.safeSpot !== undefined ? `${n0(i.safeSpot.x)},${n0(i.safeSpot.y)},${t1(i.safeSpot.walk)}` : undefined],
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
        ["why", a.reason],
        ["ed", a.ended],
    ];
}

const cutState: Record<number, { key?: string; at: number; decidedAt: number } | undefined> = {};

/** Shadow (step 2): every hero in the laning stage, both teams; the answer is logged, never carried out. */
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
    const a = Sustain.Decide(i);
    const key = `${a.kind}:${a.name}:${a.reason}`;
    if (key === st.key && now - st.at < SETTINGS.CutEvery) return;
    st.key = key;
    st.at = now;
    Telemetry.Event("cut", CutFields(pid, i, a));
}

// ------------------------------------------------------------------------------------------------------ other telemetry

const courierSeen: Record<number, number | undefined> = {};

/** `ev=courier` when the hero's courier changes state (an order shows as its effect: moving, delivering, back at base). */
function noteCourier(bot: Unit): void {
    const c = courierOf(bot);
    if (c === undefined) return;
    const st = GetCourierState(c);
    const pid = bot.GetPlayerID();
    if (courierSeen[pid] === st) return;
    courierSeen[pid] = st;
    Telemetry.Event("courier", [
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

export const _test = { learned, laneSeen, cutState };
