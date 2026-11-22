/**
 * Spike oha-yield-spike (plan step 5), throwaway: can our code hand a hero to Valve's attack and take it back?
 * Variant by player slot, fixed at load: slots 0-1 `own` (the attack file's Lua GetDesire returns 0.95 in a window, nil
 * outside it, Think left to Valve), slots 2-3 `zero` (attack left to Valve; every gated Lua mode returns 0 in a window),
 * slot 4 `nil` (the attack file's GetDesire always returns nil, Think left to Valve).
 * A window opens where Valve's own attack takes the hero about half the time (VALVE-MODES: an enemy hero within attack
 * range + 300, own HP 70%+), lasts HOLD seconds, then at least GAP seconds pass before the next.
 */
import { BotMode, Unit, UnitType } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Ours from "bots/FunLib/humaniser/ours";

export type Kind = "own" | "zero" | "nil";

const HOLD = 4;
const GAP = 6;
const REACH_EXTRA = 300;
const MIN_HP = 0.7;
/** Valve's attack desire for `own` in a window: above OHA's laning (0.45) and team roam (0.72), level with its retreat. */
export const OWN_DESIRE = 0.95;

interface Win {
    until: number;
    next: number;
    at: number;
    tick: number;
    n: number;
    atk: number;
    hero: number;
    mode0: string;
}
const wins: Record<number, Win> = {};
const kindLogged: Record<number, boolean> = {};

export function KindOf(bot: Unit): Kind | undefined {
    if (!Ours.On("YieldProbe")) return undefined;
    const slot = bot.GetPlayerID() % 5;
    const k: Kind = slot <= 1 ? "own" : slot <= 3 ? "zero" : "nil";
    if (kindLogged[bot.GetPlayerID()] !== true) {
        kindLogged[bot.GetPlayerID()] = true;
        Telemetry.Event("yield", [
            ["pid", bot.GetPlayerID()],
            ["ph", "kind"],
            ["kind", k],
        ]);
    }
    return k;
}

function nearestEnemy(bot: Unit): [Unit | undefined, number] {
    let best: Unit | undefined;
    let bd = math.huge;
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (h.IsNull() || !h.IsAlive() || h.IsIllusion()) continue;
        const d = GetUnitToUnitDistance(bot, h);
        if (d < bd) {
            bd = d;
            best = h;
        }
    }
    return [best, bd];
}

function modeName(bot: Unit): string {
    return HDebug.ModeName(bot.GetActiveMode());
}

/** Advances the hero's window once per game time; true while a window holds. */
export function InWindow(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let w = wins[pid];
    if (w === undefined) {
        w = { until: -1, next: 30, at: 0, tick: -1, n: 0, atk: 0, hero: 0, mode0: "" };
        wins[pid] = w;
    }
    if (w.tick === now) return now < w.until;
    w.tick = now;
    if (!bot.IsAlive()) {
        if (now < w.until) close(bot, w, now, "dead");
        return false;
    }
    if (now < w.until) {
        w.n++;
        if (bot.GetActiveMode() === BotMode.Attack) w.atk++;
        const t = bot.GetAttackTarget();
        if (t !== null && t !== undefined && !t.IsNull() && t.IsHero()) w.hero++;
        return true;
    }
    if (w.until > 0) close(bot, w, now, "time");
    if (now < w.next || now > 600) return false;
    if (bot.GetHealth() < bot.GetMaxHealth() * MIN_HP) return false;
    const [e, d] = nearestEnemy(bot);
    if (e === undefined || d > bot.GetAttackRange() + REACH_EXTRA) return false;
    w.until = now + HOLD;
    w.at = now;
    w.n = 0;
    w.atk = 0;
    w.hero = 0;
    w.mode0 = modeName(bot);
    Telemetry.Event("yield", [
        ["pid", pid],
        ["ph", "start"],
        ["kind", KindOf(bot)],
        ["mode", w.mode0],
        ["ed", math.floor(d)],
        ["tpid", e.GetPlayerID()],
        ["hp", math.floor((100 * bot.GetHealth()) / bot.GetMaxHealth())],
    ]);
    return true;
}

function close(bot: Unit, w: Win, now: number, why: string): void {
    Telemetry.Event("yield", [
        ["pid", bot.GetPlayerID()],
        ["ph", "end"],
        ["kind", KindOf(bot)],
        ["why", why],
        ["mode", modeName(bot)],
        ["secs", math.floor((now - w.at) * 10) / 10],
        ["n", w.n],
        ["atk", w.atk],
        ["hero", w.hero],
        ["hp", math.floor((100 * bot.GetHealth()) / bot.GetMaxHealth())],
    ]);
    w.until = -1;
    w.next = now + GAP;
}

/** `zero`: every gated mode returns 0 while the window holds. */
export function Zeroes(bot: Unit): boolean {
    return KindOf(bot) === "zero" && InWindow(bot);
}

/** The attack file's GetDesire for `own` and `nil`; undefined is returned to the engine as nil. */
export function AttackDesire(bot: Unit, k: Kind): number | undefined {
    if (k === "own" && InWindow(bot)) return OWN_DESIRE;
    if (k === "nil") InWindow(bot);
    return undefined;
}
