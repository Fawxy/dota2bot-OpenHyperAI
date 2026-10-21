/**
 * Humaniser entry point, exposed as J.Humaniser.
 * Tick(bot) runs every frame per bot from ItemUsageThink, before that function's throttle.
 */
import { GameState, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Chat from "bots/FunLib/humaniser/chat";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as AllyLastHit from "bots/FunLib/humaniser/ally_last_hit";
import * as Pings from "bots/FunLib/humaniser/pings";
import * as Commands from "bots/FunLib/humaniser/commands";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";
import * as Bridge from "bots/FunLib/humaniser/bridge";
// tasks: task runner spike
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as TasksDemo from "bots/FunLib/humaniser/tasks_demo_gather";
import * as Utils from "bots/FunLib/utils";

export { Config, HDebug, Chat, Difficulty, Profile, Orders, AllyLastHit, Pings, Commands, Intent, Trainer, Bridge };
// tasks: task runner spike
export { Tasks, TasksDemo };

const OVERLAY_REFRESH = 0.25;
const startLogged: Record<number, boolean> = {};
const overlayAt: Record<number, number> = {};
const testHandlerTeams: Record<number, boolean> = {};

export function IsEnabled(): boolean {
    return Config.IsEnabled();
}

function teamMemberByPID(team: number, pid: number): Unit | undefined {
    const players = GetTeamPlayers(team);
    for (let i = 1; i <= players.length; i++) {
        const member = GetTeamMember(i);
        if (member !== null && member !== undefined && member.GetPlayerID() === pid) return member;
    }
    return undefined;
}

/** Debug-only smoke test for the Orders bus: "!htest gather" posts a GATHER at the issuer. */
function makeTestCommandHandler(team: number): (this: void, msg: Chat.ChatMessage) => void {
    return (msg: Chat.ChatMessage) => {
        if (!Config.Get().Debug || IsPlayerBot(msg.pid)) return;
        if (string.lower(msg.text) !== "!htest gather") return;
        const issuer = teamMemberByPID(team, msg.pid);
        if (issuer === undefined) return;
        Orders.Post(team, {
            type: "GATHER",
            sourceKey: `htest:${msg.pid}:${string.format("%.2f", msg.time)}`,
            issuerPID: msg.pid,
            location: issuer.GetLocation(),
            duration: 8,
            maxResponders: 2,
        });
        HDebug.Log("orders", `htest gather posted by ${msg.pid}`);
    };
}

function logStart(bot: Unit): void {
    const pid = bot.GetPlayerID();
    if (startLogged[pid] === true || GetGameState() !== GameState.GameInProgress) return;
    startLogged[pid] = true;
    const fret = Difficulty.GetFret(bot);
    const profile = Profile.Get(bot);
    // Always printed (not gated on Debug) so skill resolution can be checked from any game's console.
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    const line = `[Humaniser] pid=${pid} ${bot.GetUnitName()} valve=${bot.GetDifficulty()} fret=${tostring(fret.active)}/${fret.level}/${
        fret.allyScale
    }(${fret.source}) allyOfHuman=${tostring(Difficulty.IsAllyOfHuman(bot))} skill=${string.format("%.2f", profile.skill)}`;
    (rawPrint ?? print)(line);
}

function drawOverlay(bot: Unit): void {
    if (!HDebug.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    const now = GameTime();
    if (now - (overlayAt[pid] ?? -1) >= OVERLAY_REFRESH) {
        overlayAt[pid] = now;
        const profile = Profile.Get(bot);
        const fret = Difficulty.GetFret(bot);
        HDebug.Text(bot, "skill", `${string.format("%.2f", profile.skill)} fret=${fret.active ? `${fret.level}x${fret.allyScale}(${fret.source})` : "off"}`);
        HDebug.Text(bot, "delay", `notice=${string.format("%.2f", profile.noticeBase)} react=${string.format("%.2f", profile.reactBase)}`);
        const order = Orders.GetFor(bot);
        HDebug.Text(bot, "order", order !== undefined ? Orders.Describe(order) : "-");
        const avoid = Orders.GetAccepted(bot, "AVOID");
        HDebug.Text(bot, "avoid", avoid !== undefined ? Orders.Describe(avoid) : "-");
        if (Intent.IsActive()) HDebug.Text(bot, "intent", Intent.Explain(bot, bot.GetActiveMode()));
        // tasks: task runner spike
        if (Tasks.IsActive()) HDebug.Text(bot, "task", Tasks.Describe(bot) ?? "-");
    }
    HDebug.Draw(bot);
}

export function Tick(bot: Unit): void {
    if (!Config.IsEnabled()) return;
    if (!bot.IsHero() || bot.IsIllusion()) return;
    Chat.EnsureInstalled(bot);
    Difficulty.Init();
    if (testHandlerTeams[bot.GetTeam()] !== true) {
        testHandlerTeams[bot.GetTeam()] = true;
        Chat.Subscribe(`htest:${bot.GetTeam()}`, makeTestCommandHandler(bot.GetTeam()));
    }
    logStart(bot);
    Pings.Tick(bot);
    Commands.Tick(bot);
    Trainer.Tick(bot);
    // Reading and accepting orders happens here every frame, not only when a mode happens to ask.
    Orders.GetFor(bot);
    Intent.Tick(bot);
    // tasks: task runner spike
    Tasks.Tick(bot);
    HDebug.SharedStateProbe(bot);
    Bridge.Tick(bot);
    drawOverlay(bot);
}
