/**
 * Machine-readable telemetry: one "[HEV] t=<DotaTime> ev=<name> k=v ..." line per event, for tools/hlog.
 *
 * Independent of Debug (no overlay needed) and never changes behaviour. Values without spaces are bare,
 * anything else is double-quoted with inner quotes turned into single quotes.
 * State is keyed by player ID so this works whether or not modules are shared between a team's bots.
 * Events emitted from a team-wide context (order posts, pings, commands) repeat once per module instance;
 * tools/hlog de-duplicates them.
 */
import { Barracks, GameState, Lane, Rune, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as Config from "bots/FunLib/humaniser/config";
import * as Chat from "bots/FunLib/humaniser/chat";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Utils from "bots/FunLib/utils";
import type { BOT, EVENTS, EventName, UNIT } from "bots/FunLib/humaniser/events";

export const SCHEMA = 2;

// Written by typescript/post-process/build-info.js at build time (git sha, "+dirty" for local changes); a log names the
// build it ran, since the Dota bots symlink can point at any worktree.
const BUILD: string = (() => {
    const [ok, info] = pcall(require, GetScriptDirectory() + "/FunLib/humaniser/build_info");
    return ok && type(info) === "table" && type((info as any).build) === "string" ? (info as any).build : "unknown";
})();

export const DEFAULTS = {
    Enable: false,
    SnapshotInterval: 1.0,
    // Etiquette decisions older than this are not attributed to a last hit.
    DecisionMaxAge: 1.0,
    MarkAck: true,
    // Runs the humaniser entry points under xpcall and reports errors as ev=lua_error (read once, at load).
    LuaErrors: true,
    // A repeating (where, msg) error is reported again at most this often, with its running count.
    LuaErrorRepeat: 10,
    // ev=creep_death (BACKLOG 1.12, WO-025): enemy lane creep deaths near own heroes are logged until this game time.
    CreepDeathUntil: 720,
};

export type TelemetryConfig = typeof DEFAULTS;

/** What index.ts knows about a bot that this module cannot import without a require cycle. */
export interface BotContext {
    by?: string;
    order?: string;
    competing?: string;
}
export type ContextProvider = (this: void, bot: Unit) => BotContext;

interface StatsUnit {
    GetLastHits(): number;
    GetDenies(): number;
    GetCurrentActionType(): number;
}

interface Decision {
    allowed: boolean;
    reason: string;
    at: number;
}

interface BotState {
    mode?: number;
    modeSince: number;
    snapAt: number;
    lastHits: number;
    denies: number;
    prevTarget?: Unit;
    // Read while the target was live (BACKLOG 0.14): by the frame that sees the last hit it may be a removed entity.
    prevTargetName?: string;
    profileKey?: string;
    // Etiquette decisions by creep handle; weak so dead creeps are collected.
    decisions: LuaTable<Unit, Decision>;
    markCursor: Record<number, number>;
    ended: boolean;
    // Hero events (BACKLOG 0.6): last frame's modifier and item edges.
    smoked: boolean;
    aegis: boolean;
    tpFrom?: [number, number, number];
    tpEndAt?: number;
}

interface MarkRecord {
    by: number;
    text: string;
    t: number;
    n: number;
}

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) result[k] = v;
    return result;
}

let cached: TelemetryConfig | undefined;
export function Get(): TelemetryConfig {
    if (cached === undefined) cached = merge(DEFAULTS, (Config.Get() as any).Telemetry) as TelemetryConfig;
    return cached;
}

/** Independent of the humaniser master switch, so an A/B game with the humaniser off still reports. */
export function IsEnabled(): boolean {
    return Get().Enable === true;
}

function formatValue(v: any): string {
    if (type(v) === "number") {
        if (v === math.floor(v) && math.abs(v) < 1e9) return string.format("%d", v);
        return string.format("%.3f", v);
    }
    if (type(v) === "boolean") return v ? "1" : "0";
    const s = tostring(v);
    if (string.find(s, '[%s="]')[0] === undefined && s !== "") return s;
    return `"${string.gsub(string.gsub(s, '"', "'")[0], "[\r\n]", " ")[0]}"`;
}

/** The exact line Event() prints, without printing it. Field order is the caller's. */
export function FormatLine(ev: string, fields: [string, any][]): string {
    const parts: string[] = ["[HEV]", `t=${formatValue(DotaTime())}`, `ev=${ev}`];
    for (const [k, v] of fields) {
        if (v !== undefined && v !== null) parts.push(`${k}=${formatValue(v)}`);
    }
    return parts.join(" ");
}

let sink: ((this: void, line: string) => void) | undefined;
/** Tests capture lines here instead of printing them. */
export function SetSink(fn: ((this: void, line: string) => void) | undefined): void {
    sink = fn;
}

type Kinds = { num: number; str: string; numstr: string; bool: boolean; mixed: number | string };
type Events = typeof EVENTS;
/** One [key, value] pair of event K: only declared keys, each with its declared value type (undefined and null are skipped on print). */
type PairOf<G> = { [F in keyof G]: [F, Kinds[G[F] & keyof Kinds] | undefined | null] }[keyof G];
export type Pair<K extends EventName> = PairOf<Events[K]>;
type UnitPair = PairOf<typeof UNIT>;
type BotPair = PairOf<typeof BOT>;
type LanePair = Extract<UnitPair, ["ln" | "s" | "ld", any]>;
export type Fields<K extends EventName> = Pair<K>[];

/** For names built at run time (farm_pattern trips, the engine adapter); listed as untyped in tools/hlog/EVENTS.md. */
export function EventUntyped(ev: string, fields: [string, any][]): void {
    if (!IsEnabled()) return;
    const line = FormatLine(ev, fields);
    if (sink !== undefined) {
        sink(line);
        return;
    }
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    (rawPrint ?? print)(line);
}

/** Typed event: the name and every key must be declared in events.ts. The printed line is exactly what EventUntyped prints. */
export function Event<K extends EventName>(ev: K, fields: Fields<K>): void {
    EventUntyped(ev, fields as [string, any][]);
}

type AnyFn = (this: void, ...args: any[]) => any;

/** Whether index.ts should install Guard() around the humaniser entry points. */
export function GuardsEnabled(): boolean {
    return IsEnabled() && Get().LuaErrors === true;
}

interface ErrorStat {
    n: number;
    at: number;
}
const MAX_ERROR_KEYS = 64;
const errorStats: Record<string, ErrorStat> = {};
let errorKeys = 0;

function shortTrace(this: void): string | undefined {
    if (type(debug) !== "table" || type(debug.traceback) !== "function") return undefined;
    const frames: string[] = [];
    for (const [line] of string.gmatch(debug.traceback("", 1), "[^\n]+")) {
        const [loc] = string.match(line, "([%w_]+%.lua:%d+)");
        if (loc !== undefined && string.find(loc, "^telemetry%.lua")[0] === undefined) {
            const [fname] = string.match(line, "function '([^']+)'");
            frames.push(fname !== undefined ? `${loc}(${fname})` : loc);
            if (frames.length >= 6) break;
        }
    }
    return frames.length > 0 ? frames.join(" < ") : undefined;
}

function describeError(this: void, err: any): string {
    if (type(err) === "string") return err;
    const [ok, s] = pcall(tostring, err);
    return ok && type(s) === "string" ? (s as string) : `<${type(err)}>`;
}

function currentPID(this: void): number {
    return GetBot().GetPlayerID();
}

function reportError(this: void, where: string, err: any, tb: string | undefined): void {
    let msg = describeError(err);
    if (msg.length > 200) msg = string.sub(msg, 1, 200);
    let key = `${where}|${msg}`;
    if (errorStats[key] === undefined && errorKeys >= MAX_ERROR_KEYS) key = `${where}|*`;
    const now = GameTime();
    let stat = errorStats[key];
    if (stat === undefined) {
        errorKeys++;
        stat = { n: 0, at: -math.huge };
        errorStats[key] = stat;
    }
    stat.n++;
    if (now - stat.at < Get().LuaErrorRepeat) return;
    stat.at = now;
    const [okPid, pid] = pcall(currentPID);
    Event("lua_error", [
        ["pid", okPid ? pid : undefined],
        ["where", where],
        ["n", stat.n],
        ["msg", msg],
        ["tb", tb],
    ]);
}

/**
 * fn under xpcall. An error is reported (rate-limited per where+msg) and swallowed: the caller gets
 * fallback(...args), which should be what the hook returns with its feature off. Reporting happens after
 * xpcall returns, so a stack overflow (handler cannot run: "error in error handling") is still reported.
 * Up to six arguments, no allocation per call; multiple return values pass through.
 */
export function Guard<F extends AnyFn>(where: string, fn: F, fallback?: AnyFn): F {
    let a1: any, a2: any, a3: any, a4: any, a5: any, a6: any;
    let tb: string | undefined;
    const thunk = (): any => fn(a1, a2, a3, a4, a5, a6);
    const handler = (err: any): any => {
        const [ok, t] = pcall(shortTrace);
        tb = ok ? t : undefined;
        return err;
    };
    const fail = (b1: any, b2: any, b3: any, b4: any, b5: any, b6: any, err: any): any => {
        const trace = tb;
        tb = undefined;
        pcall(reportError, where, err, trace);
        if (fallback !== undefined) return fallback(b1, b2, b3, b4, b5, b6);
        return undefined;
    };
    // res is only spread, so TSTL passes it as Lua varargs without building a table.
    const finish = (b1: any, b2: any, b3: any, b4: any, b5: any, b6: any, ok: boolean, ...res: any[]): any => {
        if (ok) return $multi(...res);
        return fail(b1, b2, b3, b4, b5, b6, ...(res as [any]));
    };
    return ((b1: any, b2: any, b3: any, b4: any, b5: any, b6: any) => {
        a1 = b1;
        a2 = b2;
        a3 = b3;
        a4 = b4;
        a5 = b5;
        a6 = b6;
        tb = undefined;
        return finish(b1, b2, b3, b4, b5, b6, ...(xpcall(thunk, handler) as unknown as [boolean, any]));
    }) as unknown as F;
}

/**
 * An OHA entry point (mode GetDesire/Think/OnStart/OnEnd, item and ability thinks) under pcall, for H.1. An error is
 * reported as ev=lua_error where=oha.<where> (rate-limited like Guard) and raised again unchanged, so OHA behaves as
 * before. pcall, not xpcall: with no handler a stack overflow keeps its own message ("<file>:<line>: stack overflow")
 * instead of Dota's "error in error handling". Returns fn unchanged when it is nil or guards are off.
 */
export function Entry<F extends AnyFn>(where: string, fn: F | undefined): F | undefined {
    if (fn === undefined || !GuardsEnabled()) return fn;
    const name = `oha.${where}`;
    const fail = (err: any): never => {
        pcall(reportError, name, err, undefined);
        return error(err, 0);
    };
    const finish = (ok: boolean, ...res: any[]): any => {
        if (ok) return $multi(...res);
        return fail(...(res as [any]));
    };
    return ((...args: any[]) => finish(...(pcall(fn, ...args) as unknown as [boolean, any]))) as unknown as F;
}

/** Replaces each named export of a module table with a Guard()ed one. Lua callers resolve exports at call time. */
export function GuardModule(name: string, mod: any, fallbacks: Record<string, AnyFn>): void {
    for (const [k, fallback] of pairs(fallbacks)) {
        if (type(mod[k]) === "function") mod[k] = Guard(`${name}.${k}`, mod[k], fallback);
    }
}

function weakKeys<K extends AnyNotNil, V>(): LuaTable<K, V> {
    return setmetatable(new LuaTable<K, V>(), { __mode: "k" });
}

const states: Record<number, BotState> = {};
function stateFor(pid: number): BotState {
    let s = states[pid];
    if (s === undefined) {
        s = { modeSince: 0, snapAt: -math.huge, lastHits: -1, denies: -1, decisions: weakKeys(), markCursor: {}, ended: false, smoked: false, aegis: false };
        states[pid] = s;
    }
    return s;
}

function heroName(unit: Unit): string {
    return string.gsub(unit.GetUnitName(), "npc_dota_hero_", "")[0];
}

/** Called from AllyLastHit.MayLastHit for every enemy creep it judges. */
export function NoteLastHitDecision(bot: Unit, creep: Unit, allowed: boolean, reason: string): void {
    if (!IsEnabled()) return;
    const decisions = stateFor(bot.GetPlayerID()).decisions;
    const d = decisions.get(creep);
    if (d === undefined) decisions.set(creep, { allowed, reason, at: DotaTime() });
    else {
        d.allowed = allowed;
        d.reason = reason;
        d.at = DotaTime();
    }
}

// Marks queued by the chat handler per team; each bot reports its own state for every mark it has not seen.
const marksByTeam: Record<number, MarkRecord[]> = {};
const markCount: Record<number, number> = {};
const subscribedTeams: Record<number, boolean> = {};

/** Chat hub subscriber for one team. Exported for tests. */
export function HandleChat(team: number, msg: Chat.ChatMessage): void {
    if (!IsEnabled() || IsPlayerBot(msg.pid)) return;
    const [, , rest] = string.find(string.lower(msg.text), "^%s*!mark(.*)$");
    if (rest === undefined || (rest !== "" && string.find(rest as string, "^%s")[0] === undefined)) return;
    const [, , note] = string.find(msg.text, "^%s*!%a+%s*(.-)%s*$");
    const n = (markCount[team] ?? 0) + 1;
    markCount[team] = n;
    if (marksByTeam[team] === undefined) marksByTeam[team] = [];
    marksByTeam[team].push({ by: msg.pid, text: note as string, t: DotaTime(), n });
}

function lowestBotPID(team: number): number | undefined {
    let best: number | undefined;
    for (const pid of GetTeamPlayers(team)) {
        if (IsPlayerBot(pid) && (best === undefined || pid < best)) best = pid;
    }
    return best;
}

function pct(v: number, max: number): number {
    return max > 0 ? math.floor((100 * v) / max + 0.5) : 0;
}

// Lane-front fields (slice 2b, old request H4). Engine lane amounts are in the calling script's team frame (console.9055745679,
// LaneState refresh), so the log carries absolute amounts, 0 at Radiant's ancient, whichever team's script wrote the line.
const LANES: [Lane, "top" | "mid" | "bot"][] = [[Lane.Top, "top"], [Lane.Mid, "mid"], [Lane.Bot, "bot"]];

function absAlong(lane: Lane, loc: Vector): { amount: number; distance: number } {
    const r = GetAmountAlongLane(lane, loc);
    return { amount: Camps.ToTeamAmount(Team.Radiant, r.amount), distance: r.distance };
}

/** ln (nearest lane), s (absolute amount along it) and ld (distance from it) for one hero. */
function laneFields(loc: Vector): LanePair[] {
    let best: { amount: number; distance: number } | undefined;
    let name = "";
    for (const [lane, n] of LANES) {
        const r = absAlong(lane, loc);
        if (best === undefined || r.distance < best.distance) {
            best = r;
            name = n;
        }
    }
    return [
        ["ln", name],
        ["s", best!.amount],
        ["ld", math.floor(best!.distance)],
    ];
}

/** One ev=front per team: the team's wave front per lane, absolute amount and map position. */
function trackFront(team: number): void {
    const fields: Fields<"front"> = [["team", team]];
    for (const [lane, n] of LANES) {
        const loc = GetLaneFrontLocation(team, lane, 0);
        fields.push([n, absAlong(lane, loc).amount]);
        fields.push([`${n}x` as const, math.floor(loc.x)]);
        fields.push([`${n}y` as const, math.floor(loc.y)]);
    }
    Event("front", fields);
}

// Own guards, so a failure reads as where=Telemetry.Lane|Telemetry.Front and drops only these fields or this event.
const guardedLaneFields = Guard("Telemetry.Lane", laneFields, () => []);
const guardedFront = Guard("Telemetry.Front", trackFront);

function unitFields(unit: Unit): UnitPair[] {
    const loc = unit.GetLocation();
    const stats = unit as unknown as StatsUnit;
    const target = unit.GetAttackTarget();
    const fields: UnitPair[] = [
        ["x", math.floor(loc.x)],
        ["y", math.floor(loc.y)],
        ["alive", unit.IsAlive()],
        ["hp", pct(unit.GetHealth(), unit.GetMaxHealth())],
        ["mp", pct(unit.GetMana(), unit.GetMaxMana())],
        ["lvl", unit.GetLevel()],
        ["lh", stats.GetLastHits()],
        ["dn", stats.GetDenies()],
        // Snapshots stop while a bot is dead, so deaths come from the scoreboard, not from alive=0.
        ["kills", GetHeroKills !== undefined ? GetHeroKills(unit.GetPlayerID()) : undefined],
        ["deaths", GetHeroDeaths !== undefined ? GetHeroDeaths(unit.GetPlayerID()) : undefined],
        ["tgt", target !== null && target !== undefined ? target.GetUnitName() : undefined],
    ];
    for (const f of guardedLaneFields(loc)) fields.push(f);
    return fields;
}

function botFields(bot: Unit, ctx: BotContext | undefined): BotPair[] {
    const fields: BotPair[] = unitFields(bot);
    fields.push(["mode", HDebug.ModeName(bot.GetActiveMode())]);
    fields.push(["d", bot.GetActiveModeDesire()]);
    fields.push(["act", (bot as unknown as StatsUnit).GetCurrentActionType()]);
    fields.push(["gold", bot.GetGold()]);
    if (ctx !== undefined) {
        fields.push(["by", ctx.by]);
        fields.push(["order", ctx.order]);
    }
    return fields;
}

function maybeProfile(bot: Unit, s: BotState): void {
    // Profile.Get draws RandomFloat, which a humaniser-off game must not do; skill is read-only.
    if (!Config.IsEnabled()) {
        const offKey = "off|" + tostring(LaneConfig.PositionOf(bot));
        if (s.profileKey === offKey) return;
        s.profileKey = offKey;
        Event("bot", [
            ["pid", bot.GetPlayerID()],
            ["hero", heroName(bot)],
            ["team", bot.GetTeam()],
            ["schema", SCHEMA],
            ["humaniser", false],
            ["skill", Difficulty.GetSkill(bot)],
            ["ally", Difficulty.IsAllyOfHuman(bot)],
            ["build", BUILD],
            ["pos", LaneConfig.PositionOf(bot)],
        ]);
        return;
    }
    const p = Profile.Get(bot);
    const cfg = Config.Get().Profile;
    // pos is part of the key: positions settle after the first tick (role assignment, a human's !pos swap).
    const key = string.format("%.3f|%.3f|%.3f|%s", p.skill, p.noticeBase, p.reactBase, tostring(LaneConfig.PositionOf(bot)));
    if (key === s.profileKey) return;
    s.profileKey = key;
    Event("bot", [
        ["pid", bot.GetPlayerID()],
        ["hero", heroName(bot)],
        ["team", bot.GetTeam()],
        ["schema", SCHEMA],
        ["skill", p.skill],
        ["ally", Difficulty.IsAllyOfHuman(bot)],
        ["notice", p.noticeBase],
        ["react", p.reactBase],
        ["ping", p.pingBase],
        ["chat", p.chatBase],
        ["jitter", p.jitter],
        ["lapse", p.lapseChance],
        ["lapseMax", cfg.LapseMaxExtra],
        ["minReact", cfg.MinReact],
        ["deference", p.deference],
        ["build", BUILD],
        ["pos", LaneConfig.PositionOf(bot)],
    ]);
}

function trackCounters(unit: Unit, s: BotState, human: boolean, now: number): void {
    const stats = unit as unknown as StatsUnit;
    const lh = stats.GetLastHits();
    const dn = stats.GetDenies();
    if (s.lastHits >= 0 && lh > s.lastHits) {
        const current = unit.GetAttackTarget() ?? undefined;
        const creep = s.prevTarget ?? current;
        // Never call into prevTarget here: the engine may have removed the killed creep already.
        const creepName = s.prevTarget !== undefined ? s.prevTargetName : current?.GetUnitName();
        const d = creep !== undefined ? s.decisions.get(creep) : undefined;
        const fresh = d !== undefined && now - d.at <= Get().DecisionMaxAge;
        Event("lasthit", [
            ["pid", unit.GetPlayerID()],
            ["human", human],
            ["n", lh - s.lastHits],
            ["creep", creepName],
            ["dec", fresh ? d!.reason : undefined],
            ["decAge", fresh ? now - d!.at : undefined],
        ]);
    }
    if (s.denies >= 0 && dn > s.denies)
        Event("deny", [
            ["pid", unit.GetPlayerID()],
            ["human", human],
            ["n", dn - s.denies],
        ]);
    s.lastHits = lh;
    s.denies = dn;
    const target = unit.GetAttackTarget();
    s.prevTarget = target !== null && target !== undefined ? target : undefined;
    s.prevTargetName = s.prevTarget?.GetUnitName();
}

function trackMode(bot: Unit, s: BotState, now: number, provider: ContextProvider | undefined): void {
    const mode = bot.GetActiveMode();
    if (mode === s.mode) return;
    const from = s.mode;
    s.mode = mode;
    const dwell = now - s.modeSince;
    s.modeSince = now;
    if (from === undefined) return;
    const ctx = provider !== undefined ? provider(bot) : undefined;
    Event("mode", [
        ["pid", bot.GetPlayerID()],
        ["from", HDebug.ModeName(from)],
        ["to", HDebug.ModeName(mode)],
        ["d", bot.GetActiveModeDesire()],
        ["dwell", dwell],
        ["by", ctx?.by],
    ]);
}

function reportMarks(bot: Unit, s: BotState, provider: ContextProvider | undefined): void {
    const team = bot.GetTeam();
    const marks = marksByTeam[team];
    if (marks === undefined) return;
    const pid = bot.GetPlayerID();
    const seen = s.markCursor[team] ?? 0;
    for (let i = seen; i < marks.length; i++) {
        const m = marks[i];
        if (pid === lowestBotPID(team)) {
            Event("mark", [
                ["n", m.n],
                ["by", m.by],
                ["team", team],
                ["text", m.text],
                ["at", m.t],
            ]);
            if (Get().MarkAck) bot.ActionImmediate_Chat(`mark ${m.n} saved`, false);
        }
        const ctx = provider !== undefined ? provider(bot) : undefined;
        const fields: Fields<"mark_state"> = [
            ["n", m.n],
            ["pid", pid],
            ["hero", heroName(bot)],
        ];
        for (const f of botFields(bot, ctx)) fields.push(f);
        fields.push(["competing", ctx?.competing]);
        Event("mark_state", fields);
    }
    s.markCursor[team] = marks.length;
}

function ancientDown(team: Team): boolean {
    const ancient = GetAncient(team);
    return ancient === undefined || ancient === null || !ancient.IsAlive() || ancient.GetHealth() <= 0;
}

// World and hero events (BACKLOG 0.6, slice 23). The first bot of a team to tick in a frame reports its own team's rune
// pickups, wards and building losses, so a ten-bot game logs each event once per team. Reads only, never an action.
declare function GetRuneStatus(this: void, rune: number): number;
declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare function GetRoshanKillTime(this: void): number;
declare const RUNE_STATUS_AVAILABLE: number;

const RUNES = [Rune.Power1, Rune.Power2, Rune.Bounty1, Rune.Bounty2, Rune.Bounty3, Rune.Bounty4];
const TOWER_TIERS: [number, number][] = [
    [Tower.Top1, 1], [Tower.Mid1, 1], [Tower.Bot1, 1],
    [Tower.Top2, 2], [Tower.Mid2, 2], [Tower.Bot2, 2],
    [Tower.Top3, 3], [Tower.Mid3, 3], [Tower.Bot3, 3],
    [Tower.Base1, 4], [Tower.Base2, 4],
];
const BARRACKS = [Barracks.TopMelee, Barracks.TopRanged, Barracks.MidMelee, Barracks.MidRanged, Barracks.BotMelee, Barracks.BotRanged];
/** RUNE_RULES power.first (transitions/runes): power spots hold water runes before it. */
const POWER_FROM = 360;
/** judgement: the own hero nearest a rune when it vanishes took it if within pickup range plus a frame of movement. */
const RUNE_TAKER_R = 400;
/** judgement: ward cast range 500 plus movement since the cast. */
const WARD_OWNER_R = 800;
/** Rune status is stale across 0:00 (b23 gate logs: every spot "taken" at t = 0.2), so tracking starts after this. */
const RUNES_FROM = 1;
/** A teleport's landing spot is read this long after its modifier ends. */
const TP_SETTLE = 0.1;

interface RuneSeen {
    up: boolean;
    loc: Vector;
}

interface WorldState {
    runes: Record<number, RuneSeen>;
    wards: LuaTable<Unit, boolean>;
    buildings: Record<string, boolean>;
    roshanAt?: number;
    slowAt: number;
}
const worlds: Record<number, WorldState> = {};

// Last frame each per-team job ran. Dota runs no script for a dead bot, so a fixed logger (lowest PID) would hold the team's
// events until it respawns (review 2026-10-28 finding 1); a team's bots share this module (lane_eq: once per team and cycle).
const teamJobAt: Record<string, number> = {};
function firstThisFrame(job: string, team: number, now: number): boolean {
    const key = `${job}${team}`;
    if (teamJobAt[key] === now) return false;
    teamJobAt[key] = now;
    return true;
}

// The calling bot's team (GetTeamMember is per script team), members 1..5: GetTeamPlayers is empty for a bot-only team
// in practice mode, and bounding the loop by it logged no ev=creep_death or rune pickup there (debt getteamplayers-bound).
function teamHeroes(): Unit[] {
    const heroes: Unit[] = [];
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m !== null && m !== undefined && m.IsAlive()) heroes.push(m);
    }
    return heroes;
}

function nearest(units: Unit[], loc: Vector): LuaMultiReturn<[Unit | undefined, number]> {
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const u of units) {
        const d = GetUnitToLocationDistance(u, loc);
        if (d < bestD) {
            best = u;
            bestD = d;
        }
    }
    return $multi(best, bestD);
}

function trackRunes(team: number, w: WorldState, now: number): void {
    if (now < RUNES_FROM) return;
    for (const r of RUNES) {
        const seen = w.runes[r];
        if (GetRuneStatus(r) === RUNE_STATUS_AVAILABLE) {
            if (seen === undefined || !seen.up) w.runes[r] = { up: true, loc: GetRuneSpawnLocation(r) };
            continue;
        }
        if (seen === undefined || !seen.up) continue;
        // Gone or out of sight. Without an own hero next to it, either the enemy took it (their logger reports it) or fog.
        seen.up = false;
        const [taker, d] = nearest(teamHeroes(), seen.loc);
        if (taker === undefined || d > RUNE_TAKER_R) continue;
        const [, enemyD] = nearest(GetUnitList(UnitType.EnemyHeroes), seen.loc);
        if (enemyD < d) continue;
        const power = r === Rune.Power1 || r === Rune.Power2;
        Event("rune_pickup", [
            ["pid", taker.GetPlayerID()],
            ["team", team],
            ["rune", r],
            ["kind", power ? (now < POWER_FROM ? "water" : "power") : "bounty"],
            ["x", math.floor(seen.loc.x)],
            ["y", math.floor(seen.loc.y)],
        ]);
    }
}

function trackWards(team: number, w: WorldState): void {
    for (const ward of GetUnitList(UnitType.AlliedWards)) {
        if (w.wards.get(ward) === true) continue;
        w.wards.set(ward, true);
        const name = ward.GetUnitName();
        const kind = string.find(name, "observer")[0] !== undefined ? "obs" : string.find(name, "sentry")[0] !== undefined ? "sentry" : undefined;
        // Hero summons in the ward list (serpent wards and the like) answer no KR.
        if (kind === undefined) continue;
        const loc = ward.GetLocation();
        const [owner, d] = nearest(teamHeroes(), loc);
        Event("ward_place", [
            ["pid", owner !== undefined && d <= WARD_OWNER_R ? owner.GetPlayerID() : undefined],
            ["team", team],
            ["kind", kind],
            ["x", math.floor(loc.x)],
            ["y", math.floor(loc.y)],
        ]);
    }
}

function trackBuilding(team: number, w: WorldState, kind: string, id: number, u: Unit | null, tier?: number): void {
    const key = `${kind}${id}`;
    const alive = u !== null && u !== undefined && u.IsAlive();
    const known = w.buildings[key];
    w.buildings[key] = alive;
    if (known === true && !alive)
        Event("building_fall", [
            ["team", team],
            ["kind", kind],
            ["id", id],
            ["tier", tier],
        ]);
}

function trackWorld(this: void, bot: Unit, now: number): void {
    const team = bot.GetTeam();
    if (!firstThisFrame("world", team, now)) return;
    let w = worlds[team];
    if (w === undefined) {
        w = { runes: {}, wards: weakKeys(), buildings: {}, slowAt: -math.huge };
        worlds[team] = w;
    }
    // Every frame: a rune's taker walks out of range within a second.
    trackRunes(team, w, now);
    if (now - w.slowAt < Get().SnapshotInterval) return;
    w.slowAt = now;
    trackWards(team, w);
    for (const [id, tier] of TOWER_TIERS) trackBuilding(team, w, "tower", id, GetTower(team, id), tier);
    for (const id of BARRACKS) trackBuilding(team, w, "rax", id, GetBarracks(team, id));
    const killedAt = GetRoshanKillTime();
    if (w.roshanAt !== undefined && killedAt > w.roshanAt)
        Event("roshan_kill", [
            ["team", team],
            ["at", killedAt],
        ]);
    w.roshanAt = killedAt;
    guardedFront(team);
}

/** Smoke, teleport and aegis edges for one hero (bot or human). */
function trackHero(this: void, unit: Unit, s: BotState, now: number, slow: boolean): void {
    const smoked = unit.HasModifier("modifier_smoke_of_deceit");
    if (smoked && !s.smoked) {
        const loc = unit.GetLocation();
        Event("smoke_use", [
            ["pid", unit.GetPlayerID()],
            ["team", unit.GetTeam()],
            ["x", math.floor(loc.x)],
            ["y", math.floor(loc.y)],
        ]);
    }
    s.smoked = smoked;
    const teleporting = unit.HasModifier("modifier_teleporting");
    if (teleporting) {
        if (s.tpFrom === undefined) {
            const loc = unit.GetLocation();
            s.tpFrom = [loc.x, loc.y, now];
        }
        s.tpEndAt = undefined;
    } else if (s.tpFrom !== undefined) {
        if (s.tpEndAt === undefined) s.tpEndAt = now;
        else if (now - s.tpEndAt >= TP_SETTLE) {
            const [fx, fy, at] = s.tpFrom;
            const loc = unit.GetLocation();
            Event("tp", [
                ["pid", unit.GetPlayerID()],
                ["team", unit.GetTeam()],
                ["fx", math.floor(fx)],
                ["fy", math.floor(fy)],
                ["x", math.floor(loc.x)],
                ["y", math.floor(loc.y)],
                ["dur", s.tpEndAt - at],
                ["dist", math.floor(math.sqrt((loc.x - fx) ** 2 + (loc.y - fy) ** 2))],
            ]);
            s.tpFrom = undefined;
            s.tpEndAt = undefined;
        }
    }
    if (!slow) return;
    const aegis = unit.FindItemSlot("item_aegis") >= 0;
    if (aegis && !s.aegis)
        Event("aegis", [
            ["pid", unit.GetPlayerID()],
            ["team", unit.GetTeam()],
        ]);
    s.aegis = aegis;
}

// Lane creep deaths (BACKLOG 1.12, WO-025): who got each enemy lane creep that died near the team, and what each own core
// was doing. Read from what was seen last frame, never through a dead creep's handle (BACKLOG 0.14).
interface CreepSeen {
    kind: string;
    x: number;
    y: number;
    hp: number;
}
interface CreepDeath {
    creep: Unit;
    seen: CreepSeen;
    by?: string;
}
interface CreepTrack {
    creeps: LuaTable<Unit, CreepSeen>;
    // Handles logged as deaths: one seen alive again was a creep that left vision (ev=creep_revive, the WO-025 G2 gate).
    dead: LuaTable<Unit, CreepSeen>;
    lastHits: Record<number, number>;
    denies: Record<number, number>;
    // Per core pid: last frame's attack target. Per hero pid: the target when its last attack started (attackAt on the
    // GameTime clock, as GetLastAttackTime is) and the bot's mode then (none for a human).
    target: Record<number, Unit | undefined>;
    attackAt: Record<number, number>;
    attackOn: Record<number, Unit | undefined>;
    attackMode: Record<number, number | undefined>;
}
const creepTracks: Record<number, CreepTrack> = {};
/** A creep that vanishes above this health share left vision; it did not die. */
const DEATH_MAX_HP = 0.5;
/** Deaths are logged only this close to an own hero (vision), and cores are described only this close to the death. */
const DEATH_NEAR = 1500;
/** A hero whose last hits (or an enemy whose denies) rose takes the nearest death within this distance. */
const KILLER_NEAR = 1200;

function creepKind(name: string): string | undefined {
    const lane = string.find(name, "creep_goodguys", 1, true)[0] !== undefined || string.find(name, "creep_badguys", 1, true)[0] !== undefined;
    if (string.find(name, "siege", 1, true)[0] !== undefined) return "siege";
    if (!lane) return undefined;
    return string.find(name, "ranged", 1, true)[0] !== undefined ? "ranged" : "melee";
}

function deathDistance(u: Unit, d: CreepDeath): number {
    const loc = u.GetLocation();
    return math.sqrt((loc.x - d.seen.x) ** 2 + (loc.y - d.seen.y) ** 2);
}

/** Gives each counter rise the nearest unclaimed death. */
function claimDeaths(deaths: CreepDeath[], unit: Unit, n: number, by: string): void {
    for (let k = 0; k < n; k++) {
        let best: CreepDeath | undefined;
        let bestD = KILLER_NEAR;
        for (const d of deaths) {
            const dist = deathDistance(unit, d);
            if (d.by === undefined && dist <= bestD) {
                best = d;
                bestD = dist;
            }
        }
        if (best === undefined) return;
        best.by = by;
    }
}

function rise(counts: Record<number, number>, pid: number, value: number): number {
    const prev = counts[pid];
    counts[pid] = value;
    return prev !== undefined && value > prev ? value - prev : 0;
}

function trackCreepDeaths(this: void, bot: Unit, now: number): void {
    if (now < 0 || now > Get().CreepDeathUntil) return;
    const team = bot.GetTeam();
    if (!firstThisFrame("creeps", team, now)) return;
    let c = creepTracks[team];
    if (c === undefined) {
        c = { creeps: new LuaTable(), dead: new LuaTable(), lastHits: {}, denies: {}, target: {}, attackAt: {}, attackOn: {}, attackMode: {} };
        creepTracks[team] = c;
    }
    const heroes = teamHeroes();
    const gameNow = GameTime();
    const alive: Unit[] = [];
    const live = new LuaTable<Unit, boolean>();
    for (const u of GetUnitList(UnitType.EnemyCreeps) ?? []) {
        if (u === null || u === undefined || !u.IsAlive()) continue;
        alive.push(u);
        live.set(u, true);
        const back = c.dead.get(u);
        if (back !== undefined) {
            c.dead.delete(u);
            Event("creep_revive", [
                ["team", team],
                ["kind", back.kind],
                ["hp", back.hp],
            ]);
        }
    }
    const deaths: CreepDeath[] = [];
    for (const [creep, seen] of c.creeps) {
        if (live.get(creep) === true) continue;
        c.creeps.delete(creep);
        if (seen.hp > DEATH_MAX_HP) continue;
        const d: CreepDeath = { creep, seen };
        for (const h of heroes) {
            if (deathDistance(h, d) <= DEATH_NEAR) {
                deaths.push(d);
                break;
            }
        }
    }
    for (const h of heroes) {
        const n = rise(c.lastHits, h.GetPlayerID(), (h as unknown as StatsUnit).GetLastHits());
        if (n > 0) claimDeaths(deaths, h, n, tostring(h.GetPlayerID()));
    }
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e === null || e === undefined || !e.IsAlive() || e.IsIllusion()) continue;
        const [ok, dn] = pcall(() => (e as unknown as StatsUnit).GetDenies());
        const n = ok && type(dn) === "number" ? rise(c.denies, e.GetPlayerID(), dn as number) : 0;
        if (n > 0) claimDeaths(deaths, e, n, "deny");
    }
    const cores: [Unit, 1 | 2 | 3][] = [];
    for (const h of heroes) {
        const pos = LaneConfig.PositionOf(h);
        if (pos !== undefined && pos >= 1 && pos <= 3) cores.push([h, pos as 1 | 2 | 3]);
    }
    for (const d of deaths) {
        const fields: Fields<"creep_death"> = [
            ["team", team],
            ["kind", d.seen.kind],
            ["x", math.floor(d.seen.x)],
            ["y", math.floor(d.seen.y)],
            ["hp", d.seen.hp],
            ["by", d.by ?? "none"],
        ];
        // The killer's mode when it started the swing that killed (slice 3: a mode switch between swing and death
        // otherwise leaves the snapshot mode wrong).
        const killer = d.by !== undefined ? tonumber(d.by) : undefined;
        if (killer !== undefined && c.attackOn[killer] === d.creep) {
            const mode = c.attackMode[killer];
            if (mode !== undefined) fields.push(["bm", HDebug.ModeName(mode)]);
            fields.push(["bs", gameNow - c.attackAt[killer]]);
        }
        for (const [core, pos] of cores) {
            const dist = deathDistance(core, d);
            if (dist > DEATH_NEAR) continue;
            const pid = core.GetPlayerID();
            fields.push([`p${pos}d` as const, math.floor(dist)]);
            fields.push([`p${pos}r` as const, core.GetAttackRange()]);
            fields.push([`p${pos}t` as const, c.target[pid] === d.creep]);
            if (c.attackOn[pid] === d.creep) fields.push([`p${pos}a` as const, gameNow - c.attackAt[pid]]);
        }
        Event("creep_death", fields);
        c.dead.set(d.creep, d.seen);
    }
    // This frame's state, read for next frame's deaths.
    for (const [core] of cores) c.target[core.GetPlayerID()] = core.GetAttackTarget() ?? undefined;
    for (const h of heroes) {
        const pid = h.GetPlayerID();
        const at = h.GetLastAttackTime();
        if (c.attackAt[pid] === undefined || at > c.attackAt[pid]) {
            c.attackAt[pid] = at;
            c.attackOn[pid] = h.GetAttackTarget() ?? undefined;
            c.attackMode[pid] = stateFor(pid).mode;
        }
    }
    for (const u of alive) {
        const kind = creepKind(u.GetUnitName());
        if (kind === undefined) continue;
        const loc = u.GetLocation();
        c.creeps.set(u, { kind, x: loc.x, y: loc.y, hp: u.GetHealth() / math.max(1, u.GetMaxHealth()) });
    }
}

const guardedWorld = Guard("Telemetry.World", trackWorld);
const guardedCreeps = Guard("Telemetry.Creeps", trackCreepDeaths);
const guardedHero = Guard("Telemetry.Hero", trackHero);

function snapHumans(bot: Unit, now: number): void {
    const team = bot.GetTeam();
    if (!firstThisFrame("humans", team, now)) return;
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        if (IsPlayerBot(players[i - 1])) continue;
        const member = GetTeamMember(i);
        if (member === null || member === undefined) continue;
        const hs = stateFor(member.GetPlayerID());
        if (hs.snapAt < 0) {
            hs.snapAt = now;
            Event("player", [
                ["pid", member.GetPlayerID()],
                ["hero", heroName(member)],
                ["team", team],
                ["human", true],
            ]);
        }
        trackCounters(member, hs, true, now);
        const slow = now - hs.snapAt >= Get().SnapshotInterval;
        guardedHero(member, hs, now, slow);
        if (slow) {
            hs.snapAt = now;
            const fields: Fields<"snap"> = [
                ["pid", member.GetPlayerID()],
                ["human", true],
            ];
            for (const f of unitFields(member)) fields.push(f);
            Event("snap", fields);
        }
    }
}

/** Runs every frame per bot from Humaniser.Tick, whether or not the humaniser is enabled. */
export function Tick(bot: Unit, provider?: ContextProvider): void {
    if (!IsEnabled()) return;
    const state = GetGameState();
    if (state !== GameState.GameInProgress && state !== GameState.PreGame && state !== GameState.PostGame) return;
    const team = bot.GetTeam();
    if (subscribedTeams[team] !== true) {
        subscribedTeams[team] = true;
        Chat.Subscribe(`telemetry:${team}`, (msg: Chat.ChatMessage) => HandleChat(team, msg));
    }
    const s = stateFor(bot.GetPlayerID());
    const now = DotaTime();
    if (s.ended) return;
    maybeProfile(bot, s);
    trackMode(bot, s, now, provider);
    trackCounters(bot, s, false, now);
    reportMarks(bot, s, provider);
    const slow = now - s.snapAt >= Get().SnapshotInterval;
    guardedHero(bot, s, now, slow);
    guardedWorld(bot, now);
    guardedCreeps(bot, now);
    if (slow) {
        s.snapAt = now;
        const fields: Fields<"snap"> = [["pid", bot.GetPlayerID()]];
        for (const f of botFields(bot, provider !== undefined ? provider(bot) : undefined)) fields.push(f);
        Event("snap", fields);
    }
    snapHumans(bot, now);
    if (state === GameState.PostGame || ancientDown(Team.Radiant) || ancientDown(Team.Dire)) {
        s.ended = true;
        Event("game_end", [
            ["pid", bot.GetPlayerID()],
            ["radiantAncient", !ancientDown(Team.Radiant)],
            ["direAncient", !ancientDown(Team.Dire)],
        ]);
    }
}
