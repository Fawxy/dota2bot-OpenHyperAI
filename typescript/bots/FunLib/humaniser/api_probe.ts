/**
 * API probe (`Overrides.ApiProbe`, probe games only): what the Valve API returns about units we cannot see, so a read can
 * replace a guess where one exists. Both teams run it in one game and each team's own rows are the other's truth:
 *   `apiprobe_own`    each hero about itself, once a second (the truth; `seen` is its own CanBeSeen);
 *   `apiprobe_enemy`  the team's reporter about every enemy hero handle it has held, visible (`vis=1`, the control) or not;
 *   `apiprobe_cast`   every cast callback, own and enemy, with whether the caster was visible to us when it fired;
 *   `apiprobe_dmg`    damage callbacks per player and second: how many fired, and how many with the hero out of sight;
 *   `apiprobe_tp`     GetIncomingTeleports once a second, own and enemy.
 * A read that fails prints -2, one that returns nil -1. Reads and logs only; it changes no order.
 * Rows are sampled on the whole game second so the two VMs' rows pair up by `t`.
 */
import { Team, Unit, UnitType } from "bots/ts_libs/dota";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

const MAX_PLAYER_ID = 23;
const NIL = -1;
const ERR = -2;

/** Method declarations, so the calls compile with a self argument (a call on `any` compiles without one). */
interface Named {
    GetName(): string;
    GetCooldownTimeRemaining(): number;
}
interface Handle {
    IsNull(): boolean;
    CanBeSeen(): boolean;
    GetLocation(): { x: number; y: number } | undefined;
    IsAlive(): boolean;
    GetHealth(): number;
    GetMana(): number;
    GetLevel(): number;
    GetCurrentMovementSpeed(): number;
    GetNetWorth(): number;
    NumModifiers(): number;
    GetAbilityInSlot(slot: number): Named | null | undefined;
    GetItemInSlot(slot: number): Named | null | undefined;
    GetAttackTarget(): unknown;
    IsChanneling(): boolean;
    IsCastingAbility(): boolean;
}

type Reader = (this: void, u: Handle) => any;

function num(u: Handle, read: Reader): number {
    const [ok, v] = pcall(read, u);
    if (!ok) return ERR;
    if (v === undefined || v === null) return NIL;
    if (type(v) === "boolean") return v === true ? 1 : 0;
    return type(v) === "number" ? (v as number) : NIL;
}

function round(v: number): number {
    return v < 0 ? v : math.floor(v * 10 + 0.5) / 10;
}

function cooldownSum(this: void, u: Handle): number {
    let sum = 0;
    for (let slot = 0; slot <= 5; slot++) {
        const a = u.GetAbilityInSlot(slot);
        if (a !== undefined && a !== null) sum += a.GetCooldownTimeRemaining();
    }
    return sum;
}

function itemCount(this: void, u: Handle): number {
    let n = 0;
    for (let slot = 0; slot <= 5; slot++) {
        const item = u.GetItemInSlot(slot);
        if (item !== undefined && item !== null) n++;
    }
    return n;
}

function firstItem(u: Handle): string {
    const [ok, name] = pcall((): string | undefined => {
        for (let slot = 0; slot <= 5; slot++) {
            const item = u.GetItemInSlot(slot);
            if (item !== undefined && item !== null) return item.GetName();
        }
        return undefined;
    });
    if (!ok) return "err";
    return name ?? "none";
}

function unitFields(u: Handle): [string, any][] {
    const [okLoc, loc] = pcall((): any => u.GetLocation());
    const hasLoc = okLoc && loc !== undefined && loc !== null;
    return [
        ["loc", !okLoc ? ERR : hasLoc ? 1 : 0],
        ["x", hasLoc ? math.floor(loc.x) : undefined],
        ["y", hasLoc ? math.floor(loc.y) : undefined],
        ["alive", num(u, (h) => h.IsAlive())],
        ["hp", num(u, (h) => h.GetHealth())],
        ["mp", round(num(u, (h) => h.GetMana()))],
        ["lvl", num(u, (h) => h.GetLevel())],
        ["ms", num(u, (h) => h.GetCurrentMovementSpeed())],
        ["nw", num(u, (h) => h.GetNetWorth())],
        ["nmod", num(u, (h) => h.NumModifiers())],
        ["cds", round(num(u, cooldownSum))],
        ["nitem", num(u, itemCount)],
        ["it0", firstItem(u)],
        ["tgt", num(u, (h) => h.GetAttackTarget() !== undefined && h.GetAttackTarget() !== null)],
        ["chan", num(u, (h) => h.IsChanneling())],
        ["cast", num(u, (h) => h.IsCastingAbility())],
    ];
}

interface State {
    nextAt: number;
    handles: Record<number, Handle>;
}

const states: Record<number, State> = {};
const installed: Record<number, boolean> = {};
const damage: Record<number, { n: number; fog: number; sum: number }> = {};
let shapeLogged = false;

function heroPids(): number[] {
    const pids: number[] = [];
    for (let pid = 0; pid <= MAX_PLAYER_ID; pid++) {
        const t = GetTeamForPlayer(pid);
        if (t === Team.Radiant || t === Team.Dire) pids.push(pid);
    }
    return pids;
}

/** The team's lowest-pid living hero writes the team-wide rows, so they appear once whether or not modules are shared. */
function reporterPid(alive: boolean): number | undefined {
    let best: number | undefined;
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || (alive && !m.IsAlive())) continue;
        const pid = m.GetPlayerID();
        if (best === undefined || pid < best) best = pid;
    }
    return best;
}

/** 1 visible, 0 held but out of sight, -1 never held, -2 the read failed. */
function visibleNow(handles: Record<number, Handle>, pid: number): number {
    const h = handles[pid];
    if (h === undefined) return NIL;
    return num(h, (u) => u.CanBeSeen());
}

function describeArgs(args: any[]): string {
    const parts: string[] = [];
    for (let i = 0; i < 4; i++) {
        const a = args[i];
        if (type(a) === "table") {
            const keys: string[] = [];
            for (const [k, v] of pairs(a as Record<string, any>)) keys.push(`${tostring(k)}:${type(v)}`);
            parts.push(`{${keys.join(",")}}`);
        } else {
            parts.push(type(a));
        }
    }
    return parts.join("|");
}

function install(bot: Unit, st: State): void {
    const team = bot.GetTeam();
    const g = _G as any;
    for (const pid of heroPids()) {
        if (installed[pid] === true) continue;
        installed[pid] = true;
        const own = GetTeamForPlayer(pid) === team ? 1 : 0;
        InstallCastCallback(pid, (event: any) => {
            pcall(() => {
                const a = type(event) === "table" ? event.ability : undefined;
                let name = "?";
                if (type(a) === "string") name = a as string;
                else if (a !== undefined && a !== null) name = (a as Named).GetName();
                Telemetry.EventUntyped("apiprobe_cast", [
                    ["team", team],
                    ["pid", pid],
                    ["own", own],
                    ["vis", own === 1 ? 1 : visibleNow(st.handles, pid)],
                    ["ability", name],
                ]);
            });
        });
        if (type(g.InstallDamageCallback) !== "function") continue;
        g.InstallDamageCallback(pid, (...args: any[]) => {
            pcall(() => {
                if (!shapeLogged) {
                    shapeLogged = true;
                    Telemetry.EventUntyped("apiprobe_dmgshape", [["team", team], ["args", describeArgs(args)]]);
                }
                const d = damage[pid] ?? { n: 0, fog: 0, sum: 0 };
                damage[pid] = d;
                d.n++;
                if (own === 0 && visibleNow(st.handles, pid) !== 1) d.fog++;
                const first = args[0];
                const amount = type(first) === "table" ? first.damage : args[2];
                if (type(amount) === "number") d.sum += amount as number;
            });
        });
    }
}

function teamRows(bot: Unit, st: State): void {
    const team = bot.GetTeam();
    for (const [pid, h] of pairs(st.handles)) {
        const [okNull, isNull] = pcall((): boolean => h.IsNull());
        if (okNull && isNull) continue;
        Telemetry.EventUntyped("apiprobe_enemy", [["team", team], ["pid", pid], ["vis", num(h, (u) => u.CanBeSeen())], ...unitFields(h)]);
    }
    for (const [pid, d] of pairs(damage)) {
        if (d.n === 0) continue;
        Telemetry.EventUntyped("apiprobe_dmg", [
            ["team", team],
            ["pid", pid],
            ["own", GetTeamForPlayer(pid as number) === team ? 1 : 0],
            ["n", d.n],
            ["fog", d.fog],
            ["sum", math.floor(d.sum)],
        ]);
        d.n = 0;
        d.fog = 0;
        d.sum = 0;
    }
    const [ok, tps] = pcall(() => GetIncomingTeleports());
    if (!ok || tps === undefined || tps === null) return;
    for (const tp of tps as any[]) {
        Telemetry.EventUntyped("apiprobe_tp", [
            ["team", team],
            ["pid", tp.playerid],
            ["own", GetTeamForPlayer(tp.playerid) === team ? 1 : 0],
            ["x", math.floor(tp.location.x)],
            ["y", math.floor(tp.location.y)],
            ["rem", round(tp.time_remaining)],
        ]);
    }
}

export function Tick(bot: Unit): void {
    if (Overrides.Get("ApiProbe") !== true) return;
    const now = DotaTime();
    const pid = bot.GetPlayerID();
    const st = states[pid] ?? { nextAt: -math.huge, handles: {} };
    states[pid] = st;
    for (const u of GetUnitList(UnitType.EnemyHeroes)) {
        if (u.IsIllusion()) continue;
        st.handles[u.GetPlayerID()] = u as unknown as Handle;
    }
    if (reporterPid(false) === pid) install(bot, st);
    if (now < st.nextAt) return;
    st.nextAt = math.floor(now) + 1;
    Telemetry.EventUntyped("apiprobe_own", [["team", bot.GetTeam()], ["pid", pid], ["seen", num(bot as unknown as Handle, (u) => u.CanBeSeen())], ...unitFields(bot as unknown as Handle)]);
    if (reporterPid(true) === pid) teamRows(bot, st);
}
