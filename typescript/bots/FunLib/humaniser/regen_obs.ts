/**
 * Regen observer (Regen slice, step 0). Logs when a timed regen buff starts, is refreshed and ends on a hero, and why it ended,
 * whoever caused it, so OHA's uses (the OFF arm) and ours are read on one truth. Reads and logs only; it changes no order.
 * Runs every frame per hero beside Telemetry.Tick, in both arms.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

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
