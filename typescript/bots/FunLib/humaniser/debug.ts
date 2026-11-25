/**
 * Humaniser debug logging (HDebug.Log, gated on Customize.Humaniser.Debug) and mode names. The on-screen overlay is
 * overlay.ts; Debug adds each hero's competing desires to its line there.
 */
import { BotMode, Team, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Utils from "bots/FunLib/utils";

const PROBE_LOG_INTERVAL = 5;

const modeNames: Record<number, string> = {
    [BotMode.None]: "none",
    [BotMode.Laning]: "laning",
    [BotMode.Attack]: "attack",
    [BotMode.Roam]: "roam",
    [BotMode.Retreat]: "retreat",
    [BotMode.SecretShop]: "secret_shop",
    [BotMode.SideShop]: "side_shop",
    [BotMode.Rune]: "rune",
    [BotMode.PushTowerTop]: "push_top",
    [BotMode.PushTowerMid]: "push_mid",
    [BotMode.PushTowerBot]: "push_bot",
    [BotMode.DefendTowerTop]: "defend_top",
    [BotMode.DefendTowerMid]: "defend_mid",
    [BotMode.DefendTowerBot]: "defend_bot",
    [BotMode.Assemble]: "assemble",
    [BotMode.TeamRoam]: "team_roam",
    [BotMode.Farm]: "farm",
    [BotMode.DefendAlly]: "defend_ally",
    [BotMode.EvasiveManeuvers]: "evasive",
    [BotMode.Roshan]: "roshan",
    [BotMode.Item]: "item",
    [BotMode.Ward]: "ward",
};

export function IsEnabled(): boolean {
    const cfg = Config.Get();
    return cfg.Enable === true && cfg.Debug === true;
}

export function ModeName(mode: number): string {
    return modeNames[mode] ?? `mode_${mode}`;
}

export function Log(tag: string, ...args: any[]): void {
    if (!IsEnabled()) return;
    const parts: string[] = [`[H:${tag}]`];
    for (const arg of args) parts.push(tostring(arg));
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    (rawPrint ?? print)(parts.join(" "));
}

// TEMPORARY (task 01, step 5): determines whether required modules are shared between a team's bots,
// and whether Radiant and Dire share a Lua VM. Remove once docs/HUMANISER_DEV.md records the result.
let probeTotal = 0;
const probeByPlayer: Record<number, number> = {};
const probeTeamsSeen: Record<number, boolean> = {};
const probeLastLog: Record<number, number> = {};

export function SharedStateProbe(bot: Unit): void {
    if (!IsEnabled()) return;
    const pid = bot.GetPlayerID();
    probeTotal++;
    probeByPlayer[pid] = (probeByPlayer[pid] ?? 0) + 1;
    probeTeamsSeen[bot.GetTeam()] = true;

    const now = DotaTime();
    if (now - (probeLastLog[pid] ?? -PROBE_LOG_INTERVAL) < PROBE_LOG_INTERVAL) return;
    probeLastLog[pid] = now;

    let playersSeen = 0;
    for (const _ of Object.keys(probeByPlayer)) playersSeen++;
    const bothTeams = probeTeamsSeen[Team.Radiant] === true && probeTeamsSeen[Team.Dire] === true;
    Log("probe", `pid=${pid} team=${bot.GetTeam()} total=${probeTotal} mine=${probeByPlayer[pid]} playersInThisModule=${playersSeen} bothTeamsInThisModule=${bothTeams}`);
}
