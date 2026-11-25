/**
 * The on-screen overlay of a dotactl game: drawn while `Overrides.Label` is set (dotactl passes the run's label; `--no-overlay`
 * leaves it unset). Draws only; nothing reads it to decide.
 *
 * DebugDrawText takes screen coordinates and has one large font (a hero line is a fifth of the screen wide on the Mac), so a hero's line sits in its team's block at the top left, not above the hero;
 * a ring on the map marks a hero while one of our jobs has it. Each team's VM draws its own block, and Radiant's draws the
 * label. A draw lasts one frame, so Draw runs every frame.
 */
import { BotMode, Team, Unit } from "bots/ts_libs/dota";
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");
import * as Decider from "bots/FunLib/humaniser/decider";
import * as DesireLog from "bots/FunLib/humaniser/desire_log";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

const X = 20;
const TOP = 90;
const LINE = 14;
/** A team's block: its own line and five heroes, then a gap. */
const BLOCK = 7 * LINE;
const RING = 140;

const OURS_COLOUR: [number, number, number] = [255, 220, 0];
const WAITING_COLOUR: [number, number, number] = [200, 180, 110];
const STOCK_COLOUR: [number, number, number] = [140, 140, 140];
const RING_COLOUR: Record<string, [number, number, number]> = {
    pull: [0, 200, 255],
    stack: [80, 230, 80],
    rune_detour: [230, 80, 230],
};

let headerAt = -1;
let switchesLine: string | undefined;

function label(): string | undefined {
    const v = (Customize as any).Overrides?.Label;
    return type(v) === "string" && v !== "" ? (v as string) : undefined;
}

/** The Ours switches on for this VM's team, read once: they are fixed for the game. */
function switches(): string {
    if (switchesLine === undefined) {
        const on: string[] = [];
        for (const name in Ours.DEFAULTS) if (Ours.On(name as Ours.Feature)) on.push(name);
        on.sort();
        switchesLine = on.length > 0 ? `ours: ${on.join(" ")}` : "stock";
    }
    return switchesLine;
}

function blockTop(team: number): number {
    return TOP + LINE + (team === Team.Radiant ? 0 : BLOCK);
}

interface Doing {
    text: string;
    colour: [number, number, number];
    ring?: string;
}

/** Ours while a task of ours runs under the active mode, or the decider holds the hero and farm (its host) is active. */
function doing(bot: Unit): Doing {
    const mode = bot.GetActiveMode();
    const task = Tasks.Running(bot);
    const held = Decider.Held(bot);
    const hold = held === undefined ? "" : held.soft === true ? " soft" : " hard";
    if (task !== undefined && task.host === mode) {
        const text = task.name + (task.label !== undefined ? `:${task.label}` : "") + hold;
        return { text, colour: OURS_COLOUR, ring: task.name };
    }
    if (held !== undefined && mode === BotMode.Farm) return { text: held.name + hold, colour: OURS_COLOUR, ring: held.name };
    if (held !== undefined) return { text: `${HDebug.ModeName(mode)} (${held.name} outbid)`, colour: WAITING_COLOUR };
    return { text: HDebug.ModeName(mode), colour: STOCK_COLOUR };
}

export function Draw(bot: Unit): void {
    const name = label();
    if (name === undefined) return;
    const team = bot.GetTeam();
    const top = blockTop(team);
    const now = GameTime();
    if (headerAt !== now) {
        headerAt = now;
        if (team === Team.Radiant) DebugDrawText(X, TOP, `${name}  build ${Telemetry.Build()}`, 255, 255, 255);
        const [r, g, b] = team === Team.Radiant ? [120, 220, 120] : [230, 110, 110];
        DebugDrawText(X, top, `${team === Team.Radiant ? "RADIANT" : "DIRE"}  ${switches()}`, r, g, b);
    }
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos < 1 || pos > 5) return;
    const d = doing(bot);
    const hero = string.gsub(bot.GetUnitName(), "npc_dota_hero_", "")[0];
    const extra = HDebug.IsEnabled() ? `  ${DesireLog.Competing(bot)}` : "";
    DebugDrawText(X, top + pos * LINE, `${pos} ${hero}  ${d.text}${extra}`, d.colour[0], d.colour[1], d.colour[2]);
    if (d.ring !== undefined && bot.IsAlive()) {
        const [r, g, b] = RING_COLOUR[d.ring] ?? OURS_COLOUR;
        DebugDrawCircle(bot.GetLocation(), RING, r, g, b);
    }
}
