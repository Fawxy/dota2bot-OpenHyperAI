/**
 * Single chat callback per script context that fans messages out to subscribers.
 *
 * Valve's behaviour with several InstallChatCallback calls in one context is unverified,
 * so humaniser features never install their own callback; they Subscribe here instead.
 * If modules turn out to be shared per team, several bots may each deliver the same message,
 * so messages are de-duplicated before dispatch.
 */
import { Unit } from "bots/ts_libs/dota";

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

// Injected by index.ts (this module has no deps). OHA's print override hides plain print().
let logger: ((this: void, line: string) => void) | undefined;
export function SetLogger(fn: (this: void, line: string) => void): void {
    logger = fn;
}

function describeEvent(event: any): string {
    const keys: string[] = [];
    for (const [k, v] of pairs(event)) keys.push(`${tostring(k)}=${tostring(v)}`);
    return keys.join(" ");
}
const recent: ChatMessage[] = [];
let installed = false;

function isDuplicate(msg: ChatMessage): boolean {
    for (const prev of recent) {
        if (prev.pid === msg.pid && prev.text === msg.text && msg.time - prev.time < DEDUPE_WINDOW) return true;
    }
    return false;
}

function onChat(this: void, event: ChatEvent): void {
    if (logger !== undefined) logger(`recv ${event === undefined ? "nil" : describeEvent(event)}`);
    if (event === undefined || event.string === undefined) return;
    const msg: ChatMessage = { pid: event.player_id, text: event.string, teamOnly: event.team_only === true, time: GameTime() };
    if (isDuplicate(msg)) {
        if (logger !== undefined) logger(`dup pid=${msg.pid} text=${msg.text}`);
        return;
    }
    recent.push(msg);
    if (recent.length > LOG_LIMIT) recent.shift();
    for (const name of subscriberOrder) {
        const handler = subscribers[name];
        const [ok, err] = pcall(handler, msg);
        if (!ok) {
            print(`[Humaniser] chat subscriber '${name}' failed: ${tostring(err)}`);
            if (logger !== undefined) logger(`subscriber_failed name=${name} err=${tostring(err)}`);
        }
    }
}

/** Installs the shared callback once for this script context. Safe to call every frame. */
export function EnsureInstalled(_bot: Unit): void {
    if (installed) return;
    installed = true;
    InstallChatCallback(onChat);
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
