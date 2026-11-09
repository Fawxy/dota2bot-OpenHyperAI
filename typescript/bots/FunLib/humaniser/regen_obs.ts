/**
 * Regen observer (Regen slice, step 0). Logs when a timed regen buff starts, is refreshed and ends on a hero, and why it ended,
 * whoever caused it, so OHA's uses (the OFF arm) and ours are read on one truth. It also logs the windows a regen item could have
 * been used in (`ev=regen_win`: the hero idle, with HP missing and an item in hand), the denominator of the slice's coverage. Reads and
 * logs only; it changes no order.
 * Runs every frame per hero beside Telemetry.Tick, in both arms.
 */
import { Item, Unit, Vector } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare function GetTreeLocation(tree: number): Vector;

interface Tracked {
    item: string;
    modifier: string;
    /** The resource the item restores: its missing amount is logged at the start. */
    mana: boolean;
}

const TRACKED: Tracked[] = [
    { item: "tango", modifier: "modifier_tango_heal", mana: false },
    { item: "salve", modifier: "modifier_flask_healing", mana: false },
    { item: "clarity", modifier: "modifier_clarity_potion", mana: true },
];

// An end this close to the full duration counts as running out (a frame is 0.03-0.1 s); judgement, a tuning knob.
const EARLY_TOLERANCE = 0.5;
// A remaining duration that rose by more than this since the last frame is a refresh; judgement.
const REFRESH_RISE = 0.5;
// The window before an end in which a damage source is recorded; judgement, slice Facts table.
const SOURCE_WINDOW = 2;

interface Active {
    startAt: number;
    dur: number;
    left: number;
}

const active: Record<number, Record<string, Active | undefined>> = {};

// A window is a run of frames with the hero alive, not attacking and not hit by a hero in the 2 s before (slice Facts and Behaviours:
// the one truth for OHA's uses and ours). One shorter than this is not logged; judgement, a tuning knob.
const MIN_WINDOW = 1;
// How far to look for a tree at a window's start; judgement, a tuning knob (a tango's cast range is 165, the walk is the caller's budget).
const TREE_SCAN = 1200;

interface Win {
    t0: number;
    snapped: boolean;
    mode: number;
    miss0: number;
    missMax: number;
    tg: number;
    sv: number;
    tge: number;
    sve: number;
    tree: number;
    under: boolean;
    used: string[];
}
const wins: Record<number, Win | undefined> = {};

interface Spec {
    GetSpecialValueFloat(name: string): number;
}
interface TreeBot {
    GetNearbyTrees(radius: number): number[];
}

function inHand(bot: Unit, name: string): Item | undefined {
    const slot = bot.FindItemSlot(name);
    if (slot === undefined || slot < 0 || slot > 5) return undefined;
    return bot.GetItemInSlot(slot) ?? undefined;
}

/** The HP an item gives in full, read from the item (regen per second x duration), 0 when it is not in hand. */
function effectOf(item: Item | undefined): number {
    if (item === undefined) return 0;
    const spec = item as unknown as Spec;
    return spec.GetSpecialValueFloat("health_regen") * spec.GetSpecialValueFloat("buff_duration");
}

function nearestTree(bot: Unit): number {
    let best = -1;
    for (const tree of (bot as unknown as TreeBot).GetNearbyTrees(TREE_SCAN) ?? []) {
        const loc = GetTreeLocation(tree);
        if (!IsLocationVisible(loc) || !IsLocationPassable(loc)) continue;
        const d = GetUnitToLocationDistance(bot, loc);
        if (best < 0 || d < best) best = d;
    }
    return best;
}

function snapWindow(bot: Unit, w: Win): void {
    w.snapped = true;
    const tango = inHand(bot, "item_tango");
    const single = inHand(bot, "item_tango_single");
    const salve = inHand(bot, "item_flask");
    w.tg = (tango?.GetCurrentCharges() ?? 0) + (single !== undefined ? 1 : 0);
    w.tge = effectOf(tango ?? single);
    w.sv = salve?.GetCurrentCharges() ?? 0;
    w.sve = effectOf(salve);
    w.tree = w.tg > 0 ? nearestTree(bot) : -1;
}

function closeWindow(bot: Unit, w: Win, now: number): void {
    const len = now - w.t0;
    if (!w.snapped || len < MIN_WINDOW) return;
    const efforts = [w.tg > 0 ? w.tge : 0, w.sv > 0 ? w.sve : 0].filter(e => e > 0);
    if (efforts.length === 0 || w.missMax < Math.min(...efforts)) return;
    Telemetry.Event("regen_win", [
        ["pid", bot.GetPlayerID()],
        ["mode", w.mode],
        ["len", len],
        ["miss0", w.miss0],
        ["missmax", w.missMax],
        ["tg", w.tg],
        ["sv", w.sv],
        ["tge", w.tge],
        ["sve", w.sve],
        ["tree", w.tree],
        ["under", w.under],
        ["used", w.used.length > 0 ? w.used.join(",") : "-"],
    ]);
}

function trackWindow(bot: Unit, pid: number, now: number): void {
    const idle = bot.IsAlive() && bot.GetAttackTarget() === null && !bot.WasRecentlyDamagedByAnyHero(SOURCE_WINDOW);
    let w = wins[pid];
    if (!idle) {
        if (w !== undefined) closeWindow(bot, w, now);
        wins[pid] = undefined;
        return;
    }
    const miss = bot.GetMaxHealth() - bot.GetHealth();
    if (w === undefined) {
        w = { t0: now, snapped: false, mode: bot.GetActiveMode(), miss0: miss, missMax: miss, tg: 0, sv: 0, tge: 0, sve: 0, tree: -1, under: bot.HasModifier("modifier_tango_heal") || bot.HasModifier("modifier_flask_healing"), used: [] };
        wins[pid] = w;
    }
    if (miss > w.missMax) w.missMax = miss;
    if (!w.snapped && now - w.t0 >= MIN_WINDOW) snapWindow(bot, w);
}
// Recent (time, HP) per hero for the HP lost just before an end: the damage-source flags miss some damage (clarity ended early with
// no flagged source in the smoke game), the HP drop does not.
const recent: Record<number, { t: number; hp: number }[]> = {};

function sources(bot: Unit): string {
    const parts: string[] = [];
    if (bot.WasRecentlyDamagedByAnyHero(SOURCE_WINDOW)) parts.push("hero");
    if (bot.WasRecentlyDamagedByCreep(SOURCE_WINDOW)) parts.push("creep");
    if (bot.WasRecentlyDamagedByTower(SOURCE_WINDOW)) parts.push("tower");
    return parts.length > 0 ? parts.join(",") : "-";
}

function dropInWindow(pid: number, now: number, hp: number): number {
    let top = hp;
    for (const r of recent[pid] ?? []) if (now - r.t <= SOURCE_WINDOW && r.hp > top) top = r.hp;
    return top - hp;
}

function emit(bot: Unit, t: Tracked, state: string, why: string, dur: number, left: number, miss: number, src: string, drop: number): void {
    const maxHP = bot.GetMaxHealth(), maxMP = bot.GetMaxMana();
    Telemetry.Event("regen_obs", [
        ["pid", bot.GetPlayerID()],
        ["item", t.item],
        ["state", state],
        ["why", why],
        ["hp", maxHP > 0 ? bot.GetHealth() / maxHP : -1],
        ["mp", maxMP > 0 ? bot.GetMana() / maxMP : -1],
        ["miss", miss],
        ["dur", dur],
        ["left", left],
        ["src", src],
        ["drop", drop],
    ]);
}

export function Tick(bot: Unit): void {
    if (!Telemetry.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    const mine = (active[pid] ??= {});
    const now = DotaTime();
    trackWindow(bot, pid, now);
    const hist = (recent[pid] ??= []);
    const drop = dropInWindow(pid, now, bot.GetHealth());
    hist.push({ t: now, hp: bot.GetHealth() });
    while (hist.length > 0 && now - hist[0].t > SOURCE_WINDOW) hist.shift();
    for (const t of TRACKED) {
        const idx = bot.HasModifier(t.modifier) ? bot.GetModifierByName(t.modifier) : -1;
        const was = mine[t.modifier];
        if (idx >= 0) {
            const left = bot.GetModifierRemainingDuration(idx);
            if (was === undefined) {
                const miss = t.mana ? bot.GetMaxMana() - bot.GetMana() : bot.GetMaxHealth() - bot.GetHealth();
                mine[t.modifier] = { startAt: now, dur: left, left };
                emit(bot, t, "start", "-", left, left, miss, "-", 0);
                wins[pid]?.used.push(t.item);
            } else {
                if (left > was.left + REFRESH_RISE) {
                    emit(bot, t, "refresh", "-", was.dur, left, 0, "-", 0);
                    was.startAt = now;
                    was.dur = left;
                }
                was.left = left;
            }
        } else if (was !== undefined) {
            mine[t.modifier] = undefined;
            const elapsed = now - was.startAt;
            const why = !bot.IsAlive() ? "dead" : elapsed < was.dur - EARLY_TOLERANCE ? "early" : "full";
            emit(bot, t, "end", why, was.dur, Math.max(0, was.dur - elapsed), 0, why === "early" ? sources(bot) : "-", drop);
        }
    }
}
