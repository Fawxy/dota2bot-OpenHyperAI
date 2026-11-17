/**
 * Slice chase-log (kill-chances step 3a): one `ev=cast` line per cast of a hero on this script's team, from
 * InstallCastCallback on the hero's own player. A callback runs outside any bot's think (cast_watch.ts: host helpers that
 * read GetBot fail there), so casts are queued and logged on the hero's next tick, beside the CoreTrade episode it runs.
 * The callback's table is logged as found: its key names once per hero (`ks`), the ability's name, the location and a hero
 * target where it holds them. Reads only.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as CoreTrade from "bots/FunLib/humaniser/states/core_trade";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";

/** A dead hero has no tick to drain its queue; casts past this many are dropped. */
const PENDING_MAX = 16;

interface Pending {
    event: any;
    at: number;
}
const installed: Record<number, boolean> = {};
const keysLogged: Record<number, boolean> = {};
const pending: Record<number, Pending[]> = {};

interface Handle {
    IsNull(): boolean;
    GetName?(): string;
}

/** The ability's name: a string, or a handle's GetName (smoke chase-log: 48 of 457 handles gave none through an IsNull test). */
function nameOf(a: any): string | undefined {
    if (type(a) === "string") return a as string;
    if (type(a) !== "table") return undefined;
    const h = a as Handle;
    if (type(h.IsNull) === "function" && h.IsNull()) return undefined;
    if (type(h.GetName) !== "function") return undefined;
    const n = h.GetName!();
    return type(n) === "string" && n !== "" ? n : undefined;
}

function keysOf(event: any): string {
    const ks: string[] = [];
    for (const [k, v] of pairs(event as Record<string, any>)) ks.push(`${tostring(k)}:${type(v)}`);
    table.sort(ks);
    return ks.join("|");
}

function log(bot: Unit, p: Pending): void {
    const e = p.event;
    if (type(e) !== "table") return;
    const pid = bot.GetPlayerID();
    const loc = e.location;
    const hasLoc = loc !== undefined && loc !== null && type(loc.x) === "number" && type(loc.y) === "number" && (loc.x !== 0 || loc.y !== 0);
    const ep = CoreTrade.EpisodeOf(pid);
    const t = ep?.target;
    const seen = t !== undefined && !t.IsNull() && t.CanBeSeen();
    const name = nameOf(e.ability);
    const first = keysLogged[pid] !== true;
    keysLogged[pid] = true;
    let el: number | undefined;
    if (hasLoc && seen) {
        const tl = t!.GetLocation();
        el = math.floor(math.sqrt((tl.x - loc.x) * (tl.x - loc.x) + (tl.y - loc.y) * (tl.y - loc.y)));
    }
    Telemetry.Event("cast", [
        ["pid", pid],
        ["ab", name],
        ["cl", SpellReady.ClassByName(bot, name)],
        ["x", hasLoc ? math.floor(loc.x) : undefined],
        ["y", hasLoc ? math.floor(loc.y) : undefined],
        ["el", el],
        ["ek", ep?.kind],
        ["etg", ep?.tpid],
        ["es", ep !== undefined ? (seen ? 1 : 0) : undefined],
        ["ed", seen && bot.IsAlive() ? math.floor(GetUnitToUnitDistance(bot, t!)) : undefined],
        ["lag", math.floor((DotaTime() - p.at) * 10) / 10],
        ["ks", first ? keysOf(e) : undefined],
    ]);
}

/** Installs the hero's callback once, then logs the casts queued since its last tick. */
export function Tick(bot: Unit): void {
    if (!Telemetry.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    if (installed[pid] !== true) {
        installed[pid] = true;
        pending[pid] = [];
        const q = pending[pid];
        const handler = (event: any): void => {
            if (q.length < PENDING_MAX) q.push({ event, at: DotaTime() });
        };
        InstallCastCallback(pid, Telemetry.GuardsEnabled() ? Telemetry.Guard("CastLog.OnCast", handler) : handler);
    }
    const q = pending[pid];
    if (q.length === 0) return;
    const items = q.splice(0, q.length);
    for (const p of items) log(bot, p);
}
