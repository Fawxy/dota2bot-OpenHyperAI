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
import * as Utils from "bots/FunLib/utils";

export const SCHEMA = 1;

export const DEFAULTS = {
    Enable: false,
    SnapshotInterval: 1.0,
    // Etiquette decisions older than this are not attributed to a last hit.
    DecisionMaxAge: 1.0,
    MarkAck: true,
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

export function IsEnabled(): boolean {
    return Config.IsEnabled() && Get().Enable === true;
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
    const p = Profile.Get(bot);
    const cfg = Config.Get().Profile;
    const key = string.format("%.3f|%.3f|%.3f", p.skill, p.noticeBase, p.reactBase);
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

/** Runs every frame per bot from Humaniser.Tick. */
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
