/**
 * Team Orders bus, shared by ping response (05) and chat commands (06).
 *
 * Whether required modules are shared between a team's bots is unverified, so the bus must give the same
 * result either way:
 *   - Orders are keyed by a deterministic sourceKey (e.g. "ping:<pid>:<time>"). Every bot that sees the same
 *     ping or chat line posts the same order; duplicates are ignored. Only Post with inputs every bot can see.
 *   - Responders are ranked once, at creation, from positions every bot can read. Each bot then decides on its
 *     own whether it is among the first maxResponders candidates. No cross-bot writes are required.
 *   - Declines are per bot and do not promote the next candidate (that would need shared state).
 */
import { BotMode, Lane, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Profile from "bots/FunLib/humaniser/profile";

export type OrderType = "GATHER" | "ATTACK" | "DEFEND" | "PUSH" | "ROSHAN" | "AVOID" | "SMOKE" | "RELEASE";

export interface OrderSpec {
    type: OrderType;
    sourceKey: string;
    issuerPID: number;
    location?: Vector;
    lane?: Lane;
    target?: Unit;
    /** Radius for AVOID. */
    radius?: number;
    duration: number;
    maxResponders: number;
    /** Bots within this distance also respond, beyond maxResponders. */
    alsoWithin?: number;
    /** Only consider bots within this distance (0 or undefined = any distance). */
    maxDistance?: number;
    /** Restrict responders to these player IDs (targeted chat commands). */
    onlyPIDs?: number[];
    /** How long a bot takes to read the order; defaults to the 'ping' delay. */
    delayKind?: Profile.DelayKind;
}

export interface TeamOrder extends OrderSpec {
    id: number;
    team: number;
    createdAt: number;
    expiresAt: number;
    /** Bot player IDs ranked nearest-first at creation, already cut to the responder set. */
    responders: number[];
}

// Higher wins when a bot has accepted several orders.
const PRIORITY: Record<OrderType, number> = {
    AVOID: 7,
    DEFEND: 6,
    ROSHAN: 5,
    ATTACK: 4,
    SMOKE: 3,
    GATHER: 2,
    PUSH: 1,
    RELEASE: 0,
};

const ordersByTeam: Record<number, TeamOrder[]> = {};
const seenSourceKeys: Record<string, boolean> = {};
let nextId = 1;

interface BotOrderState {
    readAt: number;
    declined?: string;
    announced?: boolean;
}
// Per observer, per order id. Keyed by player ID so it is correct whether or not modules are shared.
const botState: Record<number, Record<number, BotOrderState>> = {};

function teamOrders(team: number): TeamOrder[] {
    let list = ordersByTeam[team];
    if (list === undefined) {
        list = [];
        ordersByTeam[team] = list;
    }
    return list;
}

function prune(team: number): void {
    const list = teamOrders(team);
    const now = GameTime();
    for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].expiresAt <= now) list.splice(i, 1);
    }
}

function teamBots(team: number): Unit[] {
    const result: Unit[] = [];
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const member = GetTeamMember(i);
        if (member !== null && member !== undefined && member.IsBot() && !member.IsIllusion()) result.push(member);
    }
    return result;
}

export function OrderLocation(order: TeamOrder): Vector | undefined {
    if (order.target !== undefined && order.target.CanBeSeen() && order.target.IsAlive()) return order.target.GetLocation();
    return order.location;
}

function rankResponders(spec: OrderSpec, team: number): number[] {
    const loc = spec.location ?? (spec.target !== undefined ? spec.target.GetLocation() : undefined);
    const candidates: [number, number][] = [];
    for (const member of teamBots(team)) {
        const pid = member.GetPlayerID();
        if (spec.onlyPIDs !== undefined && spec.onlyPIDs.indexOf(pid) < 0) continue;
        const dist = loc !== undefined ? GetUnitToLocationDistance(member, loc) : 0;
        if (spec.maxDistance !== undefined && spec.maxDistance > 0 && dist > spec.maxDistance) continue;
        candidates.push([pid, dist]);
    }
    // Ties broken by player ID so every bot computes the same ranking.
    candidates.sort((a, b) => (a[1] !== b[1] ? a[1] - b[1] : a[0] - b[0]));
    const responders: number[] = [];
    for (let i = 0; i < candidates.length; i++) {
        const [pid, dist] = candidates[i];
        if (i < spec.maxResponders || (spec.alsoWithin !== undefined && dist <= spec.alsoWithin)) responders.push(pid);
    }
    return responders;
}

/**
 * Posts an order for the team and returns it. Re-posting the same sourceKey returns undefined.
 * An active order of the same type and lane is replaced. RELEASE cancels everything and is not stored.
 */
export function Post(team: number, spec: OrderSpec): TeamOrder | undefined {
    if (seenSourceKeys[spec.sourceKey] === true) return undefined;
    seenSourceKeys[spec.sourceKey] = true;
    if (spec.type === "RELEASE") {
        CancelAll(team);
        return undefined;
    }
    prune(team);
    const list = teamOrders(team);
    for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].type === spec.type && list[i].lane === spec.lane) list.splice(i, 1);
    }
    const now = GameTime();
    const order: TeamOrder = {
        ...spec,
        id: nextId++,
        team,
        createdAt: now,
        expiresAt: now + spec.duration,
        responders: rankResponders(spec, team),
    };
    list.push(order);
    return order;
}

export function Cancel(team: number, id: number): void {
    const list = teamOrders(team);
    for (let i = list.length - 1; i >= 0; i--) {
        if (list[i].id === id) list.splice(i, 1);
    }
}

export function CancelAll(team: number): void {
    const list = teamOrders(team);
    list.splice(0, list.length);
}

export function GetActive(team: number): TeamOrder[] {
    prune(team);
    return teamOrders(team);
}

function stateFor(bot: Unit, order: TeamOrder): BotOrderState {
    const pid = bot.GetPlayerID();
    let perBot = botState[pid];
    if (perBot === undefined) {
        perBot = {};
        botState[pid] = perBot;
    }
    let state = perBot[order.id];
    if (state === undefined) {
        state = { readAt: order.createdAt + Profile.SampleDelay(bot, order.delayKind ?? "ping") };
        perBot[order.id] = state;
    }
    return state;
}

export function IsResponder(bot: Unit, order: TeamOrder): boolean {
    return order.responders.indexOf(bot.GetPlayerID()) >= 0;
}

/** The first non-declined responder speaks for the team so only one bot acknowledges. */
export function IsSpokesperson(bot: Unit, order: TeamOrder): boolean {
    for (const pid of order.responders) {
        const state = botState[pid]?.[order.id];
        if (state === undefined || state.declined === undefined) return pid === bot.GetPlayerID();
    }
    return false;
}

/** Why this bot cannot respond right now, or undefined if it can. */
export function DeclineReason(bot: Unit, order: TeamOrder): string | undefined {
    if (!bot.IsAlive()) return "dead";
    if (bot.IsChanneling()) return "channeling";
    if (bot.GetActiveMode() === BotMode.Retreat && bot.GetHealth() / bot.GetMaxHealth() < 0.35) return "low_hp";
    if (order.type === "DEFEND" || order.type === "ROSHAN") {
        const loc = OrderLocation(order);
        if (loc !== undefined && GetUnitToLocationDistance(bot, loc) > 5000 && !HasTeleportReady(bot)) return "far";
    }
    return undefined;
}

export function HasTeleportReady(bot: Unit): boolean {
    const tp = bot.GetItemInSlot(15);
    return tp !== null && tp !== undefined && tp.IsFullyCastable();
}

/**
 * Marks this bot as accepting the order if it is a responder, has had time to read it, and can respond.
 * Returns false while the bot is still "reading", or if it declined.
 */
export function TryAccept(bot: Unit, order: TeamOrder): boolean {
    if (!IsResponder(bot, order)) return false;
    const state = stateFor(bot, order);
    if (GameTime() < state.readAt) return false;
    if (state.declined !== undefined) return false;
    const reason = DeclineReason(bot, order);
    if (reason !== undefined) {
        state.declined = reason;
        announce(bot, `say_order_decline_${reason}`);
        return false;
    }
    if (state.announced !== true) {
        state.announced = true;
        if (IsSpokesperson(bot, order)) announce(bot, `say_order_ack_${string.lower(order.type)}`);
    }
    return true;
}

type Announcer = (bot: Unit, key: string, cooldown: number) => void;
let announcer: Announcer | undefined;

/** jmz_func injects J.ModeAnnounce here; requiring jmz_func from this module would be circular. */
export function SetAnnouncer(fn: Announcer): void {
    announcer = fn;
}

function announce(bot: Unit, key: string): void {
    if (announcer !== undefined) announcer(bot, key, Config.Get().Orders.AckCooldown);
}

/** Highest-priority order this bot has accepted, or undefined. */
export function GetFor(bot: Unit): TeamOrder | undefined {
    let best: TeamOrder | undefined;
    for (const order of GetActive(bot.GetTeam())) {
        if (!TryAccept(bot, order)) continue;
        if (best === undefined || PRIORITY[order.type] > PRIORITY[best.type]) best = order;
    }
    return best;
}

function modeMatches(order: TeamOrder, botMode: BotMode, lane: Lane | undefined): boolean {
    switch (order.type) {
        case "GATHER":
        case "ATTACK":
        case "SMOKE":
            return botMode === BotMode.Assemble;
        case "ROSHAN":
            return botMode === BotMode.Roshan;
        case "DEFEND":
            return (
                (botMode === BotMode.DefendTowerTop || botMode === BotMode.DefendTowerMid || botMode === BotMode.DefendTowerBot) &&
                (order.lane === undefined || order.lane === lane)
            );
        case "PUSH":
            return (
                (botMode === BotMode.PushTowerTop || botMode === BotMode.PushTowerMid || botMode === BotMode.PushTowerBot) &&
                (order.lane === undefined || order.lane === lane)
            );
        default:
            return false;
    }
}

/** A desire floor for this mode if an accepted order maps to it, else 0. Combine with math.max. */
export function DesireFloor(bot: Unit, botMode: BotMode, lane?: Lane): number {
    if (!Config.IsEnabled()) return 0;
    const order = GetFor(bot);
    if (order === undefined || !modeMatches(order, botMode, lane)) return 0;
    return Config.Get().Orders.DesireFloor;
}

export function Describe(order: TeamOrder): string {
    const left = math.max(0, order.expiresAt - GameTime());
    const lane = order.lane !== undefined ? ` lane=${order.lane}` : "";
    return `${order.type}#${order.id}${lane} ${string.format("%.0f", left)}s`;
}
