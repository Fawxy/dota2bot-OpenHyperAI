/**
 * Lane debug chat commands (task 07). Human issuers only, gated by Humaniser Debug and the Lane feature.
 * Output goes to the console via HDebug.Log (captured by -condebug). Later tasks Register their own commands.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as Chat from "bots/FunLib/humaniser/chat";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import { memberByPID } from "bots/FunLib/humaniser/commands";

export type DebugCommand = (this: void, team: number, issuer: Unit, args: string[]) => void;

const commands: Record<string, DebugCommand> = {};

export function Register(name: string, fn: DebugCommand): void {
    commands[string.lower(name)] = fn;
}

function fmt(v: Vector): string {
    return string.format("Vector(%.0f, %.0f, %.0f)", v.x, v.y, v.z);
}

Register("hpt", (_team, issuer) => {
    HDebug.Log("lane", "hpt", fmt(issuer.GetLocation()));
});

Register("hcamp", (_team, issuer) => {
    const [s] = Camps.NearestSpawner(issuer.GetLocation());
    if (s === undefined) {
        HDebug.Log("lane", "hcamp none");
        return;
    }
    const job = Camps.ByIdx(s.idx);
    HDebug.Log(
        "lane",
        "hcamp",
        `idx=${s.idx} team=${s.team} type=${s.type} min=${fmt(s.min)} max=${fmt(s.max)} job=${job?.key ?? "-"} source=${job?.source ?? "-"} derived=${tostring(job?.derived)}`
    );
});

export function HandleMessage(team: number, msg: Chat.ChatMessage): void {
    if (!HDebug.IsEnabled() || !LaneConfig.IsEnabled()) return;
    if (!Chat.IsCommand(msg.text) || IsPlayerBot(msg.pid)) return;
    const words: string[] = [];
    for (const [w] of string.gmatch(string.sub(msg.text, 2), "%S+")) words.push(string.lower(w as string));
    const name = words.shift();
    if (name === undefined) return;
    const fn = commands[name];
    if (fn === undefined) return;
    const issuer = memberByPID(team, msg.pid);
    if (issuer === undefined) return;
    fn(team, issuer, words);
}

const subscribed: Record<number, boolean> = {};

export function Tick(bot: Unit): void {
    if (!HDebug.IsEnabled() || !LaneConfig.IsEnabled()) return;
    const team = bot.GetTeam();
    if (subscribed[team] === true) return;
    subscribed[team] = true;
    Chat.Subscribe(`lanedebug:${team}`, (msg: Chat.ChatMessage) => HandleMessage(team, msg));
}
