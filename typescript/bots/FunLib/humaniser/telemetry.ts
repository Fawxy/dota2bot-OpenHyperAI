/**
 * Machine-readable telemetry: one "[HEV] t=<DotaTime> ev=<name> k=v ..." line per event, for tools/hlog.
 *
 * Independent of Debug (no overlay needed) and never changes behaviour. Values without spaces are bare,
 * anything else is double-quoted with inner quotes turned into single quotes.
 * State is keyed by player ID so this works whether or not modules are shared between a team's bots.
 * Events emitted from a team-wide context (order posts, pings, commands) repeat once per module instance;
 * tools/hlog de-duplicates them.
 */
import { GameState, Team, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Chat from "bots/FunLib/humaniser/chat";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Utils from "bots/FunLib/utils";

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
    profileKey?: string;
    // Etiquette decisions by creep handle; weak so dead creeps are collected.
    decisions: LuaTable<Unit, Decision>;
    markCursor: Record<number, number>;
    ended: boolean;
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

export function Event(ev: string, fields: [string, any][]): void {
    if (!IsEnabled()) return;
    const line = FormatLine(ev, fields);
    if (sink !== undefined) {
        sink(line);
        return;
    }
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    (rawPrint ?? print)(line);
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
        s = { modeSince: 0, snapAt: -math.huge, lastHits: -1, denies: -1, decisions: weakKeys(), markCursor: {}, ended: false };
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

function unitFields(unit: Unit): [string, any][] {
    const loc = unit.GetLocation();
    const stats = unit as unknown as StatsUnit;
    const target = unit.GetAttackTarget();
    return [
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
}

function botFields(bot: Unit, ctx: BotContext | undefined): [string, any][] {
    const fields = unitFields(bot);
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
        const creep = s.prevTarget ?? unit.GetAttackTarget() ?? undefined;
        const d = creep !== undefined ? s.decisions.get(creep) : undefined;
        const fresh = d !== undefined && now - d.at <= Get().DecisionMaxAge;
        Event("lasthit", [
            ["pid", unit.GetPlayerID()],
            ["human", human],
            ["n", lh - s.lastHits],
            ["creep", creep !== undefined ? creep.GetUnitName() : undefined],
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
        const fields: [string, any][] = [
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

function snapHumans(bot: Unit, now: number): void {
    const team = bot.GetTeam();
    if (bot.GetPlayerID() !== lowestBotPID(team)) return;
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
        if (now - hs.snapAt >= Get().SnapshotInterval) {
            hs.snapAt = now;
            const fields: [string, any][] = [
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
    if (now - s.snapAt >= Get().SnapshotInterval) {
        s.snapAt = now;
        const fields: [string, any][] = [["pid", bot.GetPlayerID()]];
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
