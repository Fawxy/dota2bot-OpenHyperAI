/**
 * API probe (`Overrides.ApiProbe`, probe games only): what the Valve API returns about units we cannot see, so a read can
 * replace a guess where one exists. Both teams run it in one game and each team's own rows are the other's truth:
 *   `apiprobe_own`    each hero about itself, once a second (the truth for the fields below; `seen`, its own CanBeSeen,
 *                     is always 1 and is no truth about what the enemy sees: that is whether the enemy wrote a row);
 *   `apiprobe_enemy`  the team's reporter about every enemy hero handle it holds; a hero out of sight has no row, since
 *                     its handle is null, so "unseen at t" is read as no enemy row within 1 s of t;
 *   `apiprobe_cast`   every cast callback, own and enemy, with whether the caster was visible to us when it fired;
 *   `apiprobe_dmg`    damage callbacks per player and second: how many fired, and how many with the hero out of sight;
 *   `apiprobe_tp`     GetIncomingTeleports once a second, own and enemy.
 * A read that fails prints -2, one that returns nil -1. Reads and logs only; it changes no order.
 * The tick runs under pcall: a probe error is silent, so a run is judged by its row counts, not by `lua_error`.
 * Run it with LaneFight.UseCastCallback off: whether two cast callbacks installed for one player stack is not known.
 * Rows are sampled on the whole game second so the two VMs' rows pair up by `t`.
 */
import { Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";

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
                Telemetry.Event("apiprobe_cast", [
                    ["team", team],
                    ["pid", pid],
                    ["own", own],
                    ["vis", own === 1 ? 1 : visibleNow(st.handles, pid)],
                    ["ability", name],
                ]);
            });
        });
        if (type(g.InstallDamageCallback) !== "function") continue;
        const installDamage = g.InstallDamageCallback as (this: void, pid: number, fn: (this: void, ...args: any[]) => void) => void;
        installDamage(pid, (...args: any[]) => {
            pcall(() => {
                if (!shapeLogged) {
                    shapeLogged = true;
                    Telemetry.Event("apiprobe_dmgshape", [["team", team], ["args", describeArgs(args)]]);
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
        Telemetry.Event("apiprobe_enemy", [["team", team], ["pid", pid], ["vis", num(h, (u) => u.CanBeSeen())], ...unitFields(h)] as Telemetry.Fields<"apiprobe_enemy">);
    }
    for (const [pid, d] of pairs(damage)) {
        if (d.n === 0) continue;
        Telemetry.Event("apiprobe_dmg", [
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
    for (const [epid, h] of pairs(st.handles)) {
        if (num(h, (u) => u.CanBeSeen()) !== 1 || num(h, (u) => u.IsAlive()) !== 1) continue;
        abilityRows(team, epid as number, 0, h);
        const target = nearestOwn(h);
        if (target !== undefined) estRow(team, epid as number, 0, h, target);
    }
    const [ok, tps] = pcall(() => GetIncomingTeleports());
    if (!ok || tps === undefined || tps === null) return;
    for (const tp of tps as any[]) {
        Telemetry.Event("apiprobe_tp", [
            ["team", team],
            ["pid", tp.playerid],
            ["own", GetTeamForPlayer(tp.playerid) === team ? 1 : 0],
            ["x", math.floor(tp.location.x)],
            ["y", math.floor(tp.location.y)],
            ["rem", round(tp.time_remaining)],
        ]);
    }
}

/** The enemy cooldown reads (slice burst-cooldowns): which of these an enemy ability handle answers, against the owner's own row. */
interface ProbeAbility {
    GetName(): string;
    IsHidden(): boolean;
    GetLevel(): number;
    IsCooldownReady(): boolean;
    IsFullyCastable(): boolean;
    IsOwnersManaEnough(): boolean;
    GetCooldownTimeRemaining(): number;
    GetCooldown(): number;
    GetSpecialValueFloat(key: string): number;
    GetAbilityDamage(): number;
    GetManaCost(): number;
    GetEstimatedDamageToTarget(target: unknown, duration: number, types: number): number;
}
interface EstUnit {
    GetAbilityInSlot(slot: number): ProbeAbility | null | undefined;
    GetEstimatedDamageToTarget(available: boolean, target: unknown, duration: number, types: number): number;
    GetLocation(): { x: number; y: number } | undefined;
}

const EST_WINDOW = 3;
const ALL_DAMAGE = 3;
// Ability rows repeat only on a change, else this often: per-second rows of static values would swamp the log.
const ABILITY_REPEAT = 10;
const lastAbility: Record<string, { sig: string; at: number }> = {};

function abilityRows(team: number, pid: number, own: number, h: Handle): void {
    const u = h as unknown as EstUnit;
    const target = own === 1 ? nearestEnemy(h) : nearestOwn(h);
    const now = DotaTime();
    for (let slot = 0; slot <= 5; slot++) {
        const [okA, a] = pcall(() => u.GetAbilityInSlot(slot));
        if (!okA || a === undefined || a === null) continue;
        const ab = a as ProbeAbility;
        const [okN, name] = pcall(() => ab.GetName());
        if (!okN || type(name) !== "string" || name === "generic_hidden") continue;
        if (num(h, () => ab.IsHidden()) === 1) continue;
        const fields: [string, any][] = [
            ["lvl", num(h, () => ab.GetLevel())],
            ["rdy", num(h, () => ab.IsCooldownReady())],
            ["fc", num(h, () => ab.IsFullyCastable())],
            ["mok", num(h, () => ab.IsOwnersManaEnough())],
            ["rem", round(num(h, () => ab.GetCooldownTimeRemaining()))],
            ["cd", round(num(h, () => ab.GetCooldown()))],
            ["scd", round(num(h, () => ab.GetSpecialValueFloat("AbilityCooldown")))],
            ["dmg", round(num(h, () => ab.GetAbilityDamage()))],
            ["mc", round(num(h, () => ab.GetManaCost()))],
            ["aest", target === undefined ? undefined : round(num(h, () => ab.GetEstimatedDamageToTarget(target, EST_WINDOW, ALL_DAMAGE)))],
        ];
        // rem moves every second while cooling; its sign is what a change means, its value rides along.
        const sig = fields.map(([k, v]) => (k === "rem" ? (v > 0 ? "+" : tostring(v)) : k === "aest" ? "" : tostring(v))).join(",");
        const key = `${team}:${pid}:${slot}`;
        const last = lastAbility[key];
        if (last !== undefined && last.sig === sig && now - last.at < ABILITY_REPEAT) continue;
        lastAbility[key] = { sig, at: now };
        Telemetry.Event("apiprobe_abil", [["team", team], ["pid", pid], ["own", own], ["slot", slot], ["name", name as string], ...fields] as Telemetry.Fields<"apiprobe_abil">);
    }
}

function estRow(team: number, src: number, own: number, h: Handle, target: Unit): void {
    const u = h as unknown as EstUnit;
    const [okL, at] = pcall(() => u.GetLocation());
    const d = okL && at !== undefined && at !== null ? GetUnitToLocationDistance(target, at as Vector) : -1;
    Telemetry.Event("apiprobe_est", [
        ["team", team],
        ["src", src],
        ["dst", target.GetPlayerID()],
        ["own", own],
        ["dist", math.floor(d)],
        ["et", round(num(h, () => u.GetEstimatedDamageToTarget(true, target, EST_WINDOW, ALL_DAMAGE)))],
        ["ef", round(num(h, () => u.GetEstimatedDamageToTarget(false, target, EST_WINDOW, ALL_DAMAGE)))],
        ["ec", own === 1 ? undefined : round(num(h, () => SpellReady.DamageOn(h as unknown as Unit, target, EST_WINDOW)))],
    ]);
}

function nearestOf(h: Handle, units: Unit[]): Unit | undefined {
    const [ok, at] = pcall(() => h.GetLocation());
    if (!ok || at === undefined || at === null) return undefined;
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const x of units) {
        if (x.IsNull() || !x.IsAlive() || x.IsIllusion()) continue;
        const d = GetUnitToLocationDistance(x, at as Vector);
        if (d < bestD) {
            bestD = d;
            best = x;
        }
    }
    return best;
}

function nearestOwn(h: Handle): Unit | undefined {
    const own: Unit[] = [];
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m !== undefined && m !== null) own.push(m);
    }
    return nearestOf(h, own);
}

function nearestEnemy(h: Handle): Unit | undefined {
    return nearestOf(h, GetUnitList(UnitType.EnemyHeroes));
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
    Telemetry.Event("apiprobe_own", [["team", bot.GetTeam()], ["pid", pid], ["seen", num(bot as unknown as Handle, (u) => u.CanBeSeen())], ...unitFields(bot as unknown as Handle)] as Telemetry.Fields<"apiprobe_own">);
    abilityRows(bot.GetTeam(), pid, 1, bot as unknown as Handle);
    const foe = nearestEnemy(bot as unknown as Handle);
    if (foe !== undefined && foe.CanBeSeen()) estRow(bot.GetTeam(), pid, 1, bot as unknown as Handle, foe);
    if (reporterPid(true) === pid) teamRows(bot, st);
}
