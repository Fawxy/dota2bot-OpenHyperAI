/**
 * Team chat commands (task 06): "!def mid", "!rosh", "!2 push bot", ... posted to the Team Orders bus.
 *
 * Every module instance subscribes to the chat hub and parses every message, so each derives the same
 * orders. sourceKeys count repeats of the same text by the same player ("cmd:<pid>:<text>:<n>"), which
 * every instance that saw the whole chat agrees on without depending on frame timing.
 * The handler only posts orders or queues a line for a specific bot; bots act in their own Tick.
 * Names avoid FretBots' own "!" commands (FretBots/Settings.lua).
 */
import { GameState, Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Chat from "bots/FunLib/humaniser/chat";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as Pings from "bots/FunLib/humaniser/pings";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";

export const DEFAULTS = {
    Enable: true,
    Def: { Duration: 25, MaxResponders: 5 },
    Push: { Duration: 30, MaxResponders: 3 },
    Rosh: { Duration: 40, MaxResponders: 5 },
    Group: { Duration: 15, MaxResponders: 5 },
    Go: { Duration: 10, MaxResponders: 5, PingAge: 15, HeroRadius: 300 },
    Smoke: { Duration: 30, MaxResponders: 5, AlliesNeeded: 3, AlliesRadius: 600 },
    Back: { Duration: 8, Radius: 3000, EnemyRadius: 1500 },
};

export type CommandConfig = typeof DEFAULTS;

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" ? merge(d, v) : v;
    }
    return result;
}

let cached: CommandConfig | undefined;
export function Get(): CommandConfig {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().Commands) as CommandConfig;
    return cached;
}

export function IsActive(): boolean {
    return Config.IsFeatureEnabled("Commands");
}

/** The pre-humaniser "everyone defend" command; still handled by aba_role.ShouldTpToDefend too. */
export const LEGACY_DEFEND = "-都来守家";

export interface CommandContext {
    team: number;
    issuerPID: number;
    issuer: Unit;
    args: string[];
    /** Set when the command was prefixed with a slot or hero name. */
    onlyPIDs?: number[];
    sourceKey: string;
}

interface CommandDef {
    name: string;
    aliases: string[];
    handler: (this: void, ctx: CommandContext) => void;
}

const LANE_WORDS: Record<string, Lane> = {
    top: Lane.Top, t: Lane.Top, mid: Lane.Mid, m: Lane.Mid, middle: Lane.Mid, bot: Lane.Bot, b: Lane.Bot, bottom: Lane.Bot,
};

/**
 * top/mid/bot are map lanes, the same for both teams (Valve's LANE_* are absolute).
 * safe/off depend on the side: Radiant's safe lane is bot, Dire's is top.
 */
export function ParseLane(word: string | undefined, team: number): Lane | undefined {
    if (word === undefined) return undefined;
    const direct = LANE_WORDS[word];
    if (direct !== undefined) return direct;
    const radiant = team === Team.Radiant;
    if (word === "safe" || word === "s") return radiant ? Lane.Bot : Lane.Top;
    if (word === "off" || word === "o") return radiant ? Lane.Top : Lane.Bot;
    return undefined;
}

function teamMembers(team: number): Unit[] {
    const result: Unit[] = [];
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const member = GetTeamMember(i);
        if (member !== null && member !== undefined && !member.IsIllusion()) result.push(member);
    }
    return result;
}

function memberByPID(team: number, pid: number): Unit | undefined {
    for (const member of teamMembers(team)) {
        if (member.GetPlayerID() === pid) return member;
    }
    return undefined;
}

function lowestBotPID(team: number): number | undefined {
    let best: number | undefined;
    for (const pid of GetTeamPlayers(team)) {
        if (IsPlayerBot(pid) && (best === undefined || pid < best)) best = pid;
    }
    return best;
}

function heroKey(unit: Unit): string {
    return string.gsub(unit.GetUnitName(), "npc_dota_hero_", "")[0];
}

/** "2" -> the team's second slot; "lion" / "crystal" / "crystalmaiden" -> a unique bot by hero name. */
export function ResolveSelector(team: number, word: string): number[] | undefined {
    if (string.len(word) < 1) return undefined;
    const players = GetTeamPlayers(team);
    const slot = tonumber(word);
    if (slot !== undefined) {
        const pid = players[slot - 1];
        return pid !== undefined && IsPlayerBot(pid) ? [pid] : undefined;
    }
    // Short words would collide with FretBots' own commands (!me, !vo, !kb, !sp) and match too many heroes.
    if (string.len(word) < 3) return undefined;
    const exact: number[] = [];
    const partial: number[] = [];
    for (const member of teamMembers(team)) {
        if (!member.IsBot()) continue;
        const name = heroKey(member);
        const squashed = string.gsub(name, "_", "")[0];
        if (name === word || squashed === word) exact.push(member.GetPlayerID());
        else if (string.find(name, word, 1, true)[0] !== undefined || string.find(squashed, word, 1, true)[0] !== undefined)
            partial.push(member.GetPlayerID());
    }
    if (exact.length === 1) return exact;
    if (exact.length === 0 && partial.length === 1) return partial;
    return undefined;
}

function enemyHeroNear(loc: Vector, radius: number): Unit | undefined {
    return Pings.NearestVisibleEnemyHero(loc, radius);
}

/** Lane whose creep front is closest to our ancient, with visible enemy heroes there weighing heavily. */
export function MostThreatenedLane(team: number): Lane {
    const ancient = GetAncient(team);
    const enemies = GetUnitList(UnitType.EnemyHeroes);
    let best = Lane.Mid;
    let bestScore = -math.huge;
    for (const lane of [Lane.Top, Lane.Mid, Lane.Bot]) {
        const front = GetLaneFrontLocation(team, lane, 0);
        let score = ancient !== null && ancient !== undefined ? -GetUnitToLocationDistance(ancient, front) : 0;
        for (const enemy of enemies) {
            if (enemy !== null && enemy !== undefined && enemy.IsAlive() && enemy.CanBeSeen() && GetUnitToLocationDistance(enemy, front) <= 2500)
                score += 10000;
        }
        if (score > bestScore) {
            best = lane;
            bestScore = score;
        }
    }
    return best;
}

function laneNearest(team: number, loc: Vector): Lane {
    let best = Lane.Mid;
    let bestDist = math.huge;
    for (const lane of [Lane.Top, Lane.Mid, Lane.Bot]) {
        const front = GetLaneFrontLocation(team, lane, 0);
        const dx = front.x - loc.x;
        const dy = front.y - loc.y;
        const d = dx * dx + dy * dy;
        if (d < bestDist) {
            best = lane;
            bestDist = d;
        }
    }
    return best;
}

/** Nearest alive own tower to `loc` with no visible enemy hero close to it; falls back to our ancient. */
export function SafeTowerLocation(team: number, loc: Vector): Vector {
    const cfg = Get().Back;
    const enemies = GetUnitList(UnitType.EnemyHeroes);
    let best: Vector | undefined;
    let bestDist = math.huge;
    for (let id = 0; id <= 10; id++) {
        const tower = GetTower(team, id);
        if (tower === null || tower === undefined || !tower.IsAlive()) continue;
        let threatened = false;
        for (const enemy of enemies) {
            if (enemy !== null && enemy !== undefined && enemy.IsAlive() && enemy.CanBeSeen() && GetUnitToUnitDistance(enemy, tower) <= cfg.EnemyRadius) {
                threatened = true;
                break;
            }
        }
        if (threatened) continue;
        const tl = tower.GetLocation();
        const d = (tl.x - loc.x) * (tl.x - loc.x) + (tl.y - loc.y) * (tl.y - loc.y);
        if (d < bestDist) {
            best = tl;
            bestDist = d;
        }
    }
    return best ?? GetAncient(team).GetLocation();
}

export function HasSmoke(unit: Unit): boolean {
    const slot = unit.FindItemSlot("item_smoke_of_deceit");
    return slot !== undefined && slot >= 0 && slot <= 8;
}

// Lines queued from the chat handler for a specific bot; flushed in that bot's Tick.
const pendingSay: Record<number, string[]> = {};

function queueSay(team: number, key: string): void {
    const pid = lowestBotPID(team);
    if (pid === undefined) return;
    if (pendingSay[pid] === undefined) pendingSay[pid] = [];
    pendingSay[pid].push(key);
}

function responders(ctx: CommandContext, normal: number): number {
    return ctx.onlyPIDs !== undefined ? ctx.onlyPIDs.length : normal;
}

function post(ctx: CommandContext, spec: Omit<Orders.OrderSpec, "sourceKey" | "issuerPID">): Orders.TeamOrder | undefined {
    return Orders.Post(ctx.team, { ...spec, sourceKey: ctx.sourceKey, issuerPID: ctx.issuerPID, onlyPIDs: ctx.onlyPIDs, delayKind: "chat" });
}

function release(ctx: CommandContext): void {
    Orders.Post(ctx.team, { type: "RELEASE", sourceKey: `${ctx.sourceKey}:release`, issuerPID: ctx.issuerPID, duration: 0, maxResponders: 0 });
}

const COMMANDS: CommandDef[] = [
    {
        name: "def",
        aliases: ["defend"],
        handler: (ctx) => {
            const cfg = Get().Def;
            const lane = ParseLane(ctx.args[0], ctx.team) ?? MostThreatenedLane(ctx.team);
            post(ctx, { type: "DEFEND", lane, location: GetLaneFrontLocation(ctx.team, lane, 0), duration: cfg.Duration, maxResponders: responders(ctx, cfg.MaxResponders) });
        },
    },
    {
        name: "push",
        aliases: [],
        handler: (ctx) => {
            const cfg = Get().Push;
            const lane = ParseLane(ctx.args[0], ctx.team) ?? laneNearest(ctx.team, ctx.issuer.GetLocation());
            post(ctx, { type: "PUSH", lane, location: GetLaneFrontLocation(ctx.team, lane, 0), duration: cfg.Duration, maxResponders: responders(ctx, cfg.MaxResponders) });
        },
    },
    {
        name: "rosh",
        aliases: ["roshan"],
        handler: (ctx) => {
            const cfg = Get().Rosh;
            const h = Pings.GetHelpers();
            const location = h !== undefined ? h.roshanLocation() : undefined;
            post(ctx, { type: "ROSHAN", location, duration: cfg.Duration, maxResponders: responders(ctx, cfg.MaxResponders) });
        },
    },
    {
        name: "group",
        aliases: ["g"],
        handler: (ctx) => {
            const cfg = Get().Group;
            post(ctx, { type: "GATHER", location: ctx.issuer.GetLocation(), duration: cfg.Duration, maxResponders: responders(ctx, cfg.MaxResponders) });
        },
    },
    {
        name: "go",
        aliases: [],
        handler: (ctx) => {
            const cfg = Get().Go;
            let location: Vector | undefined;
            let target: Unit | undefined;
            const ping = ctx.issuer.GetMostRecentPing();
            if (ping !== null && ping !== undefined && ping.time !== 0 && GameTime() - ping.time <= cfg.PingAge) {
                location = ping.location;
                target = enemyHeroNear(location, cfg.HeroRadius);
            } else {
                const attackTarget = ctx.issuer.GetAttackTarget();
                if (attackTarget !== null && attackTarget !== undefined && attackTarget.IsHero() && attackTarget.GetTeam() !== ctx.team) {
                    target = attackTarget;
                    location = attackTarget.GetLocation();
                }
            }
            if (location === undefined) return;
            post(ctx, { type: "ATTACK", location, target, duration: cfg.Duration, maxResponders: responders(ctx, cfg.MaxResponders) });
        },
    },
    {
        name: "smoke",
        aliases: [],
        handler: (ctx) => {
            const cfg = Get().Smoke;
            let anySmoke = false;
            for (const member of teamMembers(ctx.team)) {
                if (HasSmoke(member)) anySmoke = true;
            }
            if (!anySmoke) {
                queueSay(ctx.team, "say_cmd_no_smoke");
                return;
            }
            post(ctx, { type: "SMOKE", target: ctx.issuer, location: ctx.issuer.GetLocation(), duration: cfg.Duration, maxResponders: responders(ctx, cfg.MaxResponders) });
        },
    },
    {
        name: "back",
        aliases: [],
        handler: (ctx) => {
            const cfg = Get().Back;
            release(ctx);
            // Bots near the issuer fall back (or just the named bot); ranking is by distance to the tower.
            let pids = ctx.onlyPIDs;
            if (pids === undefined) {
                pids = [];
                for (const member of teamMembers(ctx.team)) {
                    if (member.IsBot() && GetUnitToUnitDistance(member, ctx.issuer) <= cfg.Radius) pids.push(member.GetPlayerID());
                }
            }
            if (pids.length === 0) return;
            const location = SafeTowerLocation(ctx.team, ctx.issuer.GetLocation());
            Orders.Post(ctx.team, {
                type: "BACK",
                sourceKey: ctx.sourceKey,
                issuerPID: ctx.issuerPID,
                location,
                duration: cfg.Duration,
                maxResponders: pids.length,
                onlyPIDs: pids,
                delayKind: "chat",
            });
        },
    },
    {
        name: "farm",
        aliases: [],
        handler: (ctx) => {
            release(ctx);
            queueSay(ctx.team, "say_order_ack_release");
        },
    },
    {
        name: "trainer",
        aliases: [],
        handler: (ctx) => Trainer.OnCommand(ctx.team, ctx.issuerPID, ctx.args),
    },
    {
        name: "bhelp",
        aliases: [],
        handler: (ctx) => queueSay(ctx.team, "say_cmd_help"),
    },
];

function findCommand(word: string): CommandDef | undefined {
    for (const def of COMMANDS) {
        if (def.name === word || def.aliases.indexOf(word) >= 0) return def;
    }
    return undefined;
}

export interface ParsedCommand {
    name: string;
    args: string[];
    onlyPIDs?: number[];
}

/** Parses "!def mid", "!2 push bot", "!lion def top", "!lion !def top" and the legacy defend line. */
export function Parse(text: string, team: number): ParsedCommand | undefined {
    const trimmed = string.lower(string.gsub(text, "^%s*(.-)%s*$", "%1")[0]);
    if (trimmed === LEGACY_DEFEND) return { name: "def", args: [] };
    if (!Chat.IsCommand(trimmed)) return undefined;
    const words: string[] = [];
    for (const [w] of string.gmatch(string.sub(trimmed, 2), "%S+")) words.push(w);
    if (words.length === 0) return undefined;

    const direct = findCommand(words[0]);
    if (direct !== undefined) return { name: direct.name, args: words.slice(1) };

    if (words.length < 2) return undefined;
    const onlyPIDs = ResolveSelector(team, words[0]);
    if (onlyPIDs === undefined) return undefined;
    const second = string.sub(words[1], 1, 1) === "!" ? string.sub(words[1], 2) : words[1];
    const def = findCommand(second);
    // A named bot can't print help for the team or release everyone; those stay team-wide.
    if (def === undefined || def.name === "bhelp" || def.name === "farm" || def.name === "trainer") return undefined;
    return { name: def.name, args: words.slice(2), onlyPIDs };
}

const repeatCount: Record<string, number> = {};
let lastSummary = "-";

/** Chat hub subscriber for one team. Exported for tests. */
export function HandleMessage(team: number, msg: Chat.ChatMessage): void {
    if (!IsActive() || GetGameState() !== GameState.GameInProgress) return;
    if (IsPlayerBot(msg.pid)) return;
    const parsed = Parse(msg.text, team);
    if (parsed === undefined) return;
    if (GetTeamPlayers(team).indexOf(msg.pid) < 0) {
        HDebug.Log("commands", `[WARN] ignoring '${msg.text}' from player ${msg.pid}, not on team ${team}`);
        return;
    }
    if (!msg.teamOnly) return;
    const issuer = memberByPID(team, msg.pid);
    if (issuer === undefined) return;

    const countKey = `${msg.pid}:${string.lower(msg.text)}`;
    const n = (repeatCount[countKey] ?? 0) + 1;
    repeatCount[countKey] = n;
    const def = findCommand(parsed.name)!;
    def.handler({
        team,
        issuerPID: msg.pid,
        issuer,
        args: parsed.args,
        onlyPIDs: parsed.onlyPIDs,
        sourceKey: `cmd:${countKey}:${n}`,
    });
    lastSummary = `${parsed.name}${parsed.onlyPIDs !== undefined ? ` ->${parsed.onlyPIDs[0]}` : ""} by ${msg.pid}`;
    HDebug.Log("commands", lastSummary, msg.text);
}

/**
 * Order-driven smoke: true for the one responder chosen to pop smoke (first responder holding one in an
 * active slot) once enough allied heroes are close. Called from ConsiderItemDesire['item_smoke_of_deceit'].
 */
export function ShouldUseOrderedSmoke(bot: Unit): boolean {
    if (!IsActive()) return false;
    const order = Orders.GetAccepted(bot, "SMOKE");
    if (order === undefined || bot.HasModifier("modifier_smoke_of_deceit")) return false;
    let holder: number | undefined;
    for (const pid of order.responders) {
        const member = memberByPID(bot.GetTeam(), pid);
        if (member === undefined) continue;
        const slot = member.FindItemSlot("item_smoke_of_deceit");
        if (slot !== undefined && slot >= 0 && slot <= 5) {
            holder = pid;
            break;
        }
    }
    if (holder !== bot.GetPlayerID()) return false;
    const cfg = Get().Smoke;
    let near = 0;
    for (const ally of GetUnitList(UnitType.AlliedHeroes)) {
        if (ally !== null && ally !== undefined && ally.IsAlive() && !ally.IsIllusion() && GetUnitToUnitDistance(ally, bot) <= cfg.AlliesRadius) near++;
    }
    return near >= cfg.AlliesNeeded;
}

const subscribedTeams: Record<number, boolean> = {};

export function Tick(bot: Unit): void {
    if (!IsActive()) return;
    const team = bot.GetTeam();
    if (subscribedTeams[team] !== true) {
        subscribedTeams[team] = true;
        Chat.Subscribe(`commands:${team}`, (msg: Chat.ChatMessage) => HandleMessage(team, msg));
    }
    const queue = pendingSay[bot.GetPlayerID()];
    if (queue !== undefined && queue.length > 0 && Orders.CanSay(bot)) {
        Orders.Say(bot, queue.shift()!, 0);
    }
    HDebug.Text(bot, "cmd", lastSummary);
}
