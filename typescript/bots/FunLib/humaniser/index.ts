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
import * as Lane from "bots/FunLib/humaniser/lane";
import * as Transitions from "bots/FunLib/humaniser/transitions/transitions";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as LastHitSkill from "bots/FunLib/humaniser/last_hit_skill";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Perception from "bots/FunLib/humaniser/perception";
import * as Utils from "bots/FunLib/utils";

export { Config, HDebug, Chat, Difficulty, Profile, Orders, AllyLastHit, Pings, Commands, Lane, Transitions, Intent, LastHitSkill, Trainer, Telemetry };

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

function telemetryContext(this: void, bot: Unit): Telemetry.BotContext {
    const order = Orders.GetFor(bot);
    return {
        by: Intent.IsActive() ? Intent.Explain(bot, bot.GetActiveMode()) : undefined,
        order: order !== undefined ? Orders.Describe(order) : undefined,
        competing: Intent.IsActive() ? Intent.Competing(bot) : undefined,
    };
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
        if (Transitions.IsActive()) HDebug.Text(bot, "phase", Transitions.Overlay(bot));
        if (Intent.IsActive()) HDebug.Text(bot, "intent", Intent.Explain(bot, bot.GetActiveMode()));
        if (LastHitSkill.IsActiveFor(bot)) {
            const cs = LastHitSkill.Counts(bot);
            HDebug.Text(bot, "cs", string.format("e=%.3f attempts=%d misses=%d", LastHitSkill.ErrorWidth(bot), cs.attempts, cs.misses));
        }
    }
    HDebug.Draw(bot);
}

function tick(this: void, bot: Unit): void {
    if (!Config.IsEnabled()) {
        // Telemetry only: an A/B game with the humaniser off still logs snapshots and mode changes.
        if (Telemetry.IsEnabled() && bot.IsHero() && !bot.IsIllusion()) Telemetry.Tick(bot);
        return;
    }
    if (!bot.IsHero() || bot.IsIllusion()) return;
    Chat.EnsureInstalled(bot);
    Chat.FlushDeferred((tag, line) => HDebug.Log(tag, line));
    Difficulty.Init();
    if (testHandlerTeams[bot.GetTeam()] !== true) {
        testHandlerTeams[bot.GetTeam()] = true;
        Chat.Subscribe(`htest:${bot.GetTeam()}`, makeTestCommandHandler(bot.GetTeam()));
    }
    logStart(bot);
    Pings.Tick(bot);
    Commands.Tick(bot);
    Lane.Tick(bot);
    Transitions.Tick(bot);
    Trainer.Tick(bot);
    LastHitSkill.Tick(bot);
    // Reading and accepting orders happens here every frame, not only when a mode happens to ask.
    Orders.GetFor(bot);
    Intent.Tick(bot);
    Telemetry.Tick(bot, telemetryContext);
    HDebug.SharedStateProbe(bot);
    drawOverlay(bot);
}

const none = (): undefined => undefined;
const no = (): boolean => false;
const zero = (): number => 0;
const arg1 = (a: any): any => a;
const arg2 = (_a: any, b: any): any => b;

// Each fallback is what the hook returns with its feature off, so a humaniser error degrades to upstream behaviour.
if (Telemetry.GuardsEnabled()) {
    Telemetry.GuardModule("Intent", Intent, { Resolve: (_bot: Unit, _mode: number, raw: any) => raw });
    Telemetry.GuardModule("Lane", Lane, {
        CampJobDesire: zero,
        CampJobRawDesire: arg2,
        CampJobThink: no,
        CampJobOnEnd: none,
        CampJobAbort: none,
        RuneContestDesire: zero,
        PreferStackedCamp: none,
        PreThink: no,
        Think: no,
        HarassThink: no,
        AdjustPosition: arg2,
    });
    Telemetry.GuardModule("Transitions", Transitions, { Tick: none, MidRunesOn: no, MidRuneFocus: no, MidRuneYield: none, MidRuneSkip: none });
    Telemetry.GuardModule("AllyLastHit", AllyLastHit, { FilterCreeps: arg2, MayLastHit: () => $multi(true, "free: error") });
    Telemetry.GuardModule("Orders", Orders, {
        FilterAvoided: arg2,
        AvoidsLocation: no,
        CapRetreatDesire: arg2,
        OrderFloor: zero,
        DesireFloor: zero,
    });
    Telemetry.GuardModule("Commands", Commands, { ShouldUseOrderedSmoke: no });
    Telemetry.GuardModule("Perception", Perception, {
        FilterNearbyEnemies: arg2,
        FilterUnitList: arg1,
        FilterChanneling: arg2,
        IsCastKnown: () => true,
        GetIncomingTrackingProjectiles: (target: { GetIncomingTrackingProjectiles(this: unknown): unknown }) => target.GetIncomingTrackingProjectiles(),
    });
}
const guardedTick = Telemetry.GuardsEnabled() ? Telemetry.Guard("Tick", tick) : tick;

export function Tick(bot: Unit): void {
    guardedTick(bot);
}
