/**
 * Last-hit trainer (task 14): practice feedback for the human. Everything here runs only after "!trainer on"
 * and never issues orders. Chat replies are queued per team and spoken by the team's lowest-PID bot.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Settings from "bots/FunLib/humaniser/trainer/settings";
import { GetTrainerHelpers, SetTrainerHelpers, TrainerHelpers } from "bots/FunLib/humaniser/trainer/api";
import { SpikeTick } from "bots/FunLib/humaniser/trainer/spike";

const REPLY_INTERVAL = 0.5;
const USAGE = "usage: !trainer on|off|stats|reset|bar on|off|chat off|misses|all|denies on|off";

interface TeamState {
    on: boolean;
    bar: boolean;
    chat: "off" | "misses" | "all";
    denies: boolean;
    spike: boolean;
    replies: string[];
    lastReplyAt: number;
}

const teams: Record<number, TeamState> = {};

export function SetHelpers(h: TrainerHelpers): void {
    SetTrainerHelpers(h);
}

export function GetHelpers(): TrainerHelpers | undefined {
    return GetTrainerHelpers();
}

/** Same rule as commands.ts's lowestBotPID; not imported from there (commands.ts imports this module). */
export function TrainerBotPID(team: number): number | undefined {
    let best: number | undefined;
    for (const pid of GetTeamPlayers(team)) {
        if (IsPlayerBot(pid) && (best === undefined || pid < best)) best = pid;
    }
    return best;
}

function stateFor(team: number): TeamState {
    let s = teams[team];
    if (s === undefined) {
        const cfg = Settings.Get();
        s = { on: false, bar: cfg.Bar, chat: cfg.Chat, denies: cfg.Denies, spike: false, replies: [], lastReplyAt: -math.huge };
        teams[team] = s;
    }
    return s;
}

function onOff(s: TeamState): string {
    return s.on ? "on" : "off";
}

function status(s: TeamState): string {
    return `trainer ${onOff(s)} - bar ${s.bar ? "on" : "off"} - chat ${s.chat} - denies ${s.denies ? "on" : "off"}`;
}

function parseOnOff(word: string | undefined): boolean | undefined {
    if (word === "on") return true;
    if (word === "off") return false;
    return undefined;
}

export function OnCommand(team: number, _pid: number, args: string[]): void {
    if (!Settings.IsEnabled()) return;
    const s = stateFor(team);
    const sub = args[0];
    const reply = (line: string) => s.replies.push(line);
    if (sub === undefined) {
        reply(status(s));
    } else if (sub === "on" || sub === "off") {
        s.on = sub === "on";
        reply(status(s));
    } else if (sub === "bar" || sub === "denies") {
        const value = parseOnOff(args[1]);
        if (value === undefined) reply(USAGE);
        else {
            if (sub === "bar") s.bar = value;
            else s.denies = value;
            reply(status(s));
        }
    } else if (sub === "chat") {
        const mode = args[1];
        if (mode === "off" || mode === "misses" || mode === "all") {
            s.chat = mode;
            reply(status(s));
        } else reply(USAGE);
    } else if (sub === "stats" || sub === "reset") {
        HDebug.Log("trainer", sub, "not implemented yet");
    } else if (sub === "spike" && Config.Get().Debug === true) {
        s.spike = !s.spike;
        HDebug.Log("trainer", "spike", s.spike ? "on" : "off");
    } else {
        reply(USAGE);
    }
}

function humanOnTeam(team: number): Unit | undefined {
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const member = GetTeamMember(i);
        if (member !== null && member !== undefined && !IsPlayerBot(member.GetPlayerID())) return member;
    }
    return undefined;
}

export function Tick(bot: Unit): void {
    if (!Settings.IsEnabled()) return;
    const team = bot.GetTeam();
    const s = teams[team];
    if (s === undefined || bot.GetPlayerID() !== TrainerBotPID(team)) return;
    const now = GameTime();
    if (s.replies.length > 0 && now - s.lastReplyAt >= REPLY_INTERVAL) {
        s.lastReplyAt = now;
        bot.ActionImmediate_Chat(s.replies.shift()!, false);
    }
    if (s.spike) {
        const subject = humanOnTeam(team);
        if (subject !== undefined) SpikeTick(bot, subject);
    }
}
