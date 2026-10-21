/**
 * Humaniser debug overlay and logging.
 *
 * DebugDrawText is screen-space only, so each bot gets its own text block on screen
 * (Radiant on the left, Dire on the right) rather than text above the hero.
 * Draws last a single frame, so Draw() must be called every frame.
 */
import { BotMode, Team, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Utils from "bots/FunLib/utils";

const LINE_HEIGHT = 14;
const BLOCK_HEIGHT = 100;
const TOP_OFFSET = 120;
const RADIANT_X = 10;
const DIRE_X = 1100;
// Desires reported less recently than this are stale (that mode stopped returning a value).
const DESIRE_STALE_SECONDS = 0.5;
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

interface KeyedLines {
    order: string[];
    text: Record<string, string>;
}

interface DesireSample {
    value: number;
    time: number;
}

const linesByPlayer: Record<number, KeyedLines> = {};
const desiresByPlayer: Record<number, Record<number, DesireSample>> = {};

export function IsEnabled(): boolean {
    const cfg = Config.Get();
    return cfg.Enable === true && cfg.Debug === true;
}

export function ModeName(mode: number): string {
    return modeNames[mode] ?? `mode_${mode}`;
}

/** Sets a persistent line for this bot, replaced on the next call with the same key. */
export function Text(bot: Unit, key: string, text: string): void {
    if (!IsEnabled()) return;
    const pid = bot.GetPlayerID();
    let lines = linesByPlayer[pid];
    if (lines === undefined) {
        lines = { order: [], text: {} };
        linesByPlayer[pid] = lines;
    }
    if (lines.text[key] === undefined) lines.order.push(key);
    lines.text[key] = text;
}

export function Circle(loc: Vector, radius: number, r: number, g: number, b: number): void {
    if (!IsEnabled()) return;
    DebugDrawCircle(loc, radius, r, g, b);
}

export function Log(tag: string, ...args: any[]): void {
    if (!IsEnabled()) return;
    const parts: string[] = [`[H:${tag}]`];
    for (const arg of args) parts.push(tostring(arg));
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    (rawPrint ?? print)(parts.join(" "));
}

/**
 * Mode files can report their own GetDesire() results here so the overlay can rank them.
 * Modes that return nil fall through to Valve's C++ desire, which cannot be read.
 */
export function RecordDesire(bot: Unit, mode: number, desire: number | undefined): void {
    if (!IsEnabled() || desire === undefined) return;
    const pid = bot.GetPlayerID();
    let desires = desiresByPlayer[pid];
    if (desires === undefined) {
        desires = {};
        desiresByPlayer[pid] = desires;
    }
    desires[mode] = { value: desire, time: DotaTime() };
}

function topDesires(pid: number, count: number): string {
    const desires = desiresByPlayer[pid];
    if (desires === undefined) return "";
    const now = DotaTime();
    const fresh: [number, number][] = [];
    for (const [mode, sample] of Object.entries(desires)) {
        if (now - sample.time <= DESIRE_STALE_SECONDS) fresh.push([tonumber(mode)!, sample.value]);
    }
    fresh.sort((a, b) => b[1] - a[1]);
    const parts: string[] = [];
    for (let i = 0; i < fresh.length && i < count; i++) {
        parts.push(`${ModeName(fresh[i][0])}=${string.format("%.2f", fresh[i][1])}`);
    }
    return parts.join(" ");
}

function slotOf(bot: Unit): number {
    const players = GetTeamPlayers(bot.GetTeam());
    const pid = bot.GetPlayerID();
    for (let i = 0; i < players.length; i++) {
        if (players[i] === pid) return i;
    }
    return 0;
}

/** Draws this bot's overlay block. Call once per frame per bot. */
export function Draw(bot: Unit): void {
    if (!IsEnabled()) return;
    const pid = bot.GetPlayerID();
    const x = bot.GetTeam() === Team.Radiant ? RADIANT_X : DIRE_X;
    let y = TOP_OFFSET + slotOf(bot) * BLOCK_HEIGHT;

    const header = `${string.gsub(bot.GetUnitName(), "npc_dota_hero_", "")[0]} [${pid}] ${ModeName(bot.GetActiveMode())} ${string.format(
        "%.2f",
        bot.GetActiveModeDesire()
    )}`;
    DebugDrawText(x, y, header, 255, 255, 0);
    y += LINE_HEIGHT;

    const top = topDesires(pid, 3);
    if (top !== "") {
        DebugDrawText(x, y, top, 200, 200, 200);
        y += LINE_HEIGHT;
    }

    const lines = linesByPlayer[pid];
    if (lines === undefined) return;
    for (const key of lines.order) {
        DebugDrawText(x, y, `${key}: ${lines.text[key]}`, 255, 255, 255);
        y += LINE_HEIGHT;
    }
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
