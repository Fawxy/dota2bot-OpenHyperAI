/**
 * Single chat callback per script context that fans messages out to subscribers.
 *
 * Valve's behaviour with several InstallChatCallback calls in one context is unverified,
 * so humaniser features never install their own callback; they Subscribe here instead.
 * If modules turn out to be shared per team, several bots may each deliver the same message,
 * so messages are de-duplicated before dispatch.
 */
import { GameState, Unit } from "bots/ts_libs/dota";

export interface ChatMessage {
    pid: number;
    text: string;
    teamOnly: boolean;
    time: number;
}

type Handler = (this: void, msg: ChatMessage) => void;

const DEDUPE_WINDOW = 0.25;
const LOG_LIMIT = 50;

const subscribers: Record<string, Handler> = {};
const subscriberOrder: string[] = [];

// Diagnostics raised inside the chat callback are queued and printed from Tick via FlushDeferred.
// In-game, printing (and iterating the raw event) inside the engine's callback coincided with game crashes.
const DEFERRED_LIMIT = 100;
const deferred: string[][] = [];
export function Defer(tag: string, line: string): void {
    if (deferred.length < DEFERRED_LIMIT) deferred.push([tag, line]);
}
export function FlushDeferred(log: (this: void, tag: string, line: string) => void): void {
    while (deferred.length > 0) {
        const entry = deferred.shift()!;
        log(entry[0], entry[1]);
    }
}

const recent: ChatMessage[] = [];
let installed = false;
let installedInProgress = false;

function isDuplicate(msg: ChatMessage): boolean {
    for (const prev of recent) {
        if (prev.pid === msg.pid && prev.text === msg.text && msg.time - prev.time < DEDUPE_WINDOW) return true;
    }
    return false;
}

function onChat(this: void, event: ChatEvent): void {
    if (event === undefined || event.string === undefined) {
        Defer("chat", "recv nil_or_no_string");
        return;
    }
    Defer("chat", `recv pid=${tostring(event.player_id)} team_only=${tostring(event.team_only)} text=${tostring(event.string)}`);
    const msg: ChatMessage = { pid: event.player_id, text: event.string, teamOnly: event.team_only === true, time: GameTime() };
    if (isDuplicate(msg)) {
        Defer("chat", `dup pid=${msg.pid} text=${msg.text}`);
        return;
    }
    recent.push(msg);
    if (recent.length > LOG_LIMIT) recent.shift();
    for (const name of subscriberOrder) {
        const handler = subscribers[name];
        const [ok, err] = pcall(handler, msg);
        if (!ok) {
            print(`[Humaniser] chat subscriber '${name}' failed: ${tostring(err)}`);
            Defer("chat", `subscriber_failed name=${name} err=${tostring(err)}`);
        }
    }
}

/**
 * Installs the shared callback for this script context: on first call, and once more when the game reaches in-progress.
 * Safe to call every frame. hero_selection.lua's UpdateLaneAssignments re-installs its own chat callback every frame
 * until the horn; in-game, a hub installed only during pre-game never received a message, consistent with only the
 * latest install being kept. If the engine instead keeps every callback, the duplicate delivery is dropped by isDuplicate.
 */
export function EnsureInstalled(_bot: Unit): void {
    if (!installed) {
        installed = true;
        installedInProgress = GetGameState() === GameState.GameInProgress;
        InstallChatCallback(onChat);
        Defer("chat", `installed gt=${GameTime()} state=${GetGameState()}`);
    }
    if (!installedInProgress && GetGameState() === GameState.GameInProgress) {
        installedInProgress = true;
        InstallChatCallback(onChat);
        Defer("chat", `reinstalled gt=${GameTime()} state=${GetGameState()}`);
    }
}

/** Registers (or replaces) a named handler. Names keep re-subscription idempotent. */
export function Subscribe(name: string, handler: Handler): void {
    if (subscribers[name] === undefined) subscriberOrder.push(name);
    subscribers[name] = handler;
}

export function Unsubscribe(name: string): void {
    if (subscribers[name] === undefined) return;
    delete subscribers[name];
    const index = subscriberOrder.indexOf(name);
    if (index >= 0) subscriberOrder.splice(index, 1);
}

export function IsCommand(text: string): boolean {
    return string.sub(text, 1, 1) === "!";
}
