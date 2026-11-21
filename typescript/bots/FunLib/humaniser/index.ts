/**
 * Humaniser entry point, exposed as J.Humaniser.
 * Tick(bot) runs every frame per bot from ItemUsageThink, before that function's throttle.
 */
import { GameState, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Camps from "bots/FunLib/humaniser/camps";
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
import * as FarmPattern from "bots/FunLib/humaniser/farm_pattern";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as RegenObs from "bots/FunLib/humaniser/regen_obs";
import * as ApiProbe from "bots/FunLib/humaniser/api_probe";
import * as Commit from "bots/FunLib/humaniser/commit";
import * as VisionMap from "bots/FunLib/humaniser/vision_map";
import * as Perception from "bots/FunLib/humaniser/perception";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Etiquette from "bots/FunLib/humaniser/etiquette";
import * as StackJob from "bots/FunLib/humaniser/stack_job";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";
import * as CoreCamp from "bots/FunLib/humaniser/core_camp";
import * as RunePickup from "bots/FunLib/humaniser/rune_pickup";
import * as RunePlan from "bots/FunLib/humaniser/rune_plan";
import * as Plays from "bots/FunLib/humaniser/plays/plays";
import * as PullFarm from "bots/FunLib/humaniser/pull_farm";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as CampClaims from "bots/FunLib/humaniser/camp_claims";
import * as Chooser from "bots/FunLib/humaniser/chooser";
import * as Arbiter from "bots/FunLib/humaniser/arbiter";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Utils from "bots/FunLib/utils";

export { Config, HDebug, Chat, Difficulty, Profile, Orders, AllyLastHit, Pings, Commands, Lane, Transitions, Intent, LastHitSkill, FarmPattern, Trainer, Telemetry, Ours, Etiquette, StackJob, RuneJob, RunePickup, RunePlan, Plays, PullJob, PullFarm, CampClaims, Chooser, Overrides, Drill, CoreCamp, Arbiter };
// tasks: task runner spike
import * as Tasks from "bots/FunLib/humaniser/tasks";
// tasks: task runner spike
export { Tasks };
import * as States from "bots/FunLib/humaniser/states/index";
export { States };
import * as Trade from "bots/FunLib/humaniser/states/trade";
export { Trade };
import * as LaneControl from "bots/FunLib/humaniser/lane_control";
export { LaneControl };
import * as Retreat from "bots/FunLib/humaniser/retreat";
export { Retreat };
import * as SustainGather from "bots/FunLib/humaniser/sustain_gather";
export { SustainGather };
import * as SustainAct from "bots/FunLib/humaniser/sustain_act";
export { SustainAct };
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
export { SafeGather };
import * as PairJoin from "bots/FunLib/humaniser/pair_join";
import * as CastLog from "bots/FunLib/humaniser/cast_log";

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
        // tasks: task runner spike
        if (Tasks.IsActive()) HDebug.Text(bot, "task", Tasks.Describe(bot) ?? "-");
        if (States.IsEnabled()) HDebug.Text(bot, "state", States.Describe(bot) ?? "-");
    }
    HDebug.Draw(bot);
}

// The pull supply step asks sustain for a hero it carries: registered here because sustain_act.ts imports camp_jobs.ts.
// Through the module table, so the guards installed below apply.
CampJobs.SetSustain(
    (bot: Unit) => SustainAct.Holds(bot),
    (bot: Unit) => SustainAct.Yield(bot),
);

// The unguarded steps of tick, so the perf probe can time each (Telemetry.PerfStep; installed below, after the guards).
// Copied here at load, before GuardModule runs: a step that gets a guard later must leave this table and be called by name.
const steps = {
    feed: Camps.FeedNeutralSpeeds,
    pings: Pings.Tick,
    commands: Commands.Tick,
    lane: Lane.Tick,
    trainer: Trainer.Tick,
    lastHit: LastHitSkill.Tick,
    orders: Orders.GetFor as (this: void, bot: Unit) => unknown,
    intent: Intent.Tick,
    telemetry: Telemetry.Tick,
    regen: RegenObs.Tick,
    // A hero sustain carries logs its own cut from ItemThink: the shadow skips it.
    sustain: (bot: Unit) => {
        if (!SustainAct.Holds(bot)) SustainGather.Tick(bot);
    },
    landing: SafeGather.Tick,
    commit: Commit.Tick,
    probe: ApiProbe.Tick,
    tasks: Tasks.Tick,
    overlay: drawOverlay,
};

// One Lua VM per team, so a team's bots share this clock and run their steps on the same frames: a "first caller this
// frame" step still runs once, and lane partners read each other's state from the same frame.
let frameAt: number | undefined;
let frameNo = 0;
let allSteps = true;

/** Whether this frame runs every step (each Config TickEvery-th frame) or only the frame steps. */
function stepsDue(): boolean {
    const now = GameTime();
    if (now !== frameAt) {
        frameAt = now;
        frameNo++;
        const every = Config.Get().TickEvery;
        allSteps = every <= 1 || frameNo % every === 0;
    }
    return allSteps;
}

/**
 * The steps that run on the frames between: each names what a lower rate would lose. Every other step reads the world
 * ten times a second: the modes that act on them run 3 to 6 times a second, and a step that counts time in tenths
 * (a teleport's settle) may be read a tick late.
 */
function frameSteps(this: void, bot: Unit): void {
    // A rig places and releases units to the frame; no drill, no step.
    if (Drill.Active() !== undefined) Drill.Tick(bot);
    // The trainer times a human's swings; off unless Trainer.Enable.
    if (Trainer.IsEnabled()) steps.trainer(bot);
    steps.telemetry(bot, telemetryContext, true);
    // Debug text lasts one frame.
    steps.overlay(bot);
}

function tick(this: void, bot: Unit): void {
    const all = stepsDue();
    if (!Config.IsEnabled()) {
        // Telemetry only: an A/B game with the humaniser off still logs snapshots and mode changes.
        if (Telemetry.IsEnabled() && bot.IsHero() && !bot.IsIllusion()) {
            Telemetry.Tick(bot, undefined, !all);
            if (all) pcall(RegenObs.Tick, bot);
        }
        return;
    }
    if (!bot.IsHero() || bot.IsIllusion()) return;
    if (!all) {
        frameSteps(bot);
        return;
    }
    steps.feed(bot);
    Chat.EnsureInstalled(bot);
    Chat.FlushDeferred((tag, line) => HDebug.Log(tag, line));
    Difficulty.Init();
    if (testHandlerTeams[bot.GetTeam()] !== true) {
        testHandlerTeams[bot.GetTeam()] = true;
        Chat.Subscribe(`htest:${bot.GetTeam()}`, makeTestCommandHandler(bot.GetTeam()));
    }
    logStart(bot);
    Drill.Tick(bot);
    Retreat.Tick(bot);
    PairJoin.Tick(bot);
    steps.pings(bot);
    steps.commands(bot);
    steps.lane(bot);
    Transitions.Tick(bot);
    steps.trainer(bot);
    steps.lastHit(bot);
    // Reading and accepting orders happens here every frame, not only when a mode happens to ask.
    steps.orders(bot);
    steps.intent(bot);
    // The landing sampler (safe here's `landing`): once per hero per tick, with telemetry off too. See SafeGather.Tick.
    pcall(steps.landing, bot);
    // The commitment tracker (Ours.PricedLeave step 1, logged only): its flag poll needs the 10 Hz tick. See Commit.Tick.
    const [commitOk, commitErr] = pcall(steps.commit, bot);
    if (!commitOk) Telemetry.Failed("Commit.Tick", commitErr);
    // Lane controller slice 2a: shadow decisions only (ev=lane_ctl); nothing reads them yet.
    LaneControl.Tick(bot);
    steps.telemetry(bot, telemetryContext);
    // Slice chase-log: our casts (ev=cast), logged a tick after the callback queues them.
    pcall(CastLog.Tick, bot);
    // The observer only reads: an error in it must not skip the States and Tasks ticks below.
    pcall(steps.regen, bot);
    // Sustain: the decision in shadow (ev=cut kind=sustain) for a hero sustain_act.ts does not carry; reads and logs, no order.
    pcall(steps.sustain, bot);
    pcall(steps.probe, bot);
    // Overrides.VisionMap only: the map dump for the sight model (reads and logs).
    pcall(VisionMap.Tick, bot);
    // States select and (re)start their tasks before the runner's Tick checks them.
    States.Tick(bot);
    // tasks: task runner spike
    steps.tasks(bot);
    HDebug.SharedStateProbe(bot);
    steps.overlay(bot);
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
        CampJobHoldsRetreat: no,
        CampJobHoldsCasts: no,
        RuneContestDesire: zero,
        PreferStackedCamp: none,
    });
    Telemetry.GuardModule("Transitions", Transitions, { Tick: none, MidRunesOn: no, MidRuneFocus: () => $multi(false, false, undefined), MidRuneYield: none, MidRuneSkip: none, RuneTarget: none, HoldsRune: no, MidRuneDesire: zero, RotationYield: none, PickLaneWard: none, ConfirmLaneWard: none });
    Telemetry.GuardModule("States", States, { Tick: none, Step: no, MayOwn: no, SetLaneSpot: none, Describe: none, IsEnabled: no, WisdomOwned: no, Owns: no, BodyLastHits: no, BodyBusy: no, BodySupportHits: no, BodySupportLastHits: no, SupportOwnsAttack: no });
    // An error hands the attack mode to OHA's port (undefined desire, port Think) and leaves laning's 0.9 as it was.
    Telemetry.GuardModule("Trade", Trade, { Owns: no, Desire: none, OwnsFrame: no, Think: none, OnEnd: none, LastHitYields: no, OwnsLaneRun: no, OwnsFights: no, Holds: none });
    Telemetry.GuardModule("FarmPattern", FarmPattern, { Desire: zero, Think: no, OnEnd: none, Abort: none });
    Telemetry.GuardModule("PairJoin", PairJoin, { Tick: none });
    // A predicate error leaves the creep to the core (the etiquette answer) rather than take it.
    Telemetry.GuardModule("Etiquette", Etiquette, { Applies: no, CoreCanTake: () => true, MayLastHit: no, LeavesTarget: no });
    // An error leaves the farm mode to OHA (no job desire, no owned Think).
    Telemetry.GuardModule("StackJob", StackJob, { Wants: no, Step: no, End: none, Running: no, NoteIdleHeld: none, NoteHit: none, Benched: no, Bench: no, Minutes: () => StackJob.SETTINGS.TriggerMinutes });
    // A drill error plays the hero as in a normal game (no bench, no statue, not lane-only).
    Telemetry.GuardModule("Drill", Drill, { Tick: none, Held: no, Casts: no, Hold: no, LaneOnly: no, InLane: no, InLaneDenies: no, ForbidsItem: no, ForbidsCast: no, LaneHold: no, LaneAggro: no, IdleStatue: no, Owns: no, ForcedJob: none, ForcedAt: none, RoleOf: () => "play", Implied: none, RepTimes: none, RepAt: zero, Name: none, Active: none });
    // An error leaves the complete-items TP and the rune mode to OHA.
    Telemetry.GuardModule("Arbiter", Arbiter, { DeniesItemsTp: no, DeniesOhaRune: no });
    Telemetry.GuardModule("Chooser", Chooser, { RunningJobName: none, Decide: none, After: (_b: unknown, _m: unknown, d: unknown) => d, FarmDesire: zero, FarmThink: no, Abort: none, HoldsRun: no, HoldsIdle: no, HoldsCasts: no, Benched: no, Bench: no });
    Telemetry.GuardModule("AllyLastHit", AllyLastHit, { FilterCreeps: arg2, MayLastHit: () => $multi(true, "free: error") });
    Telemetry.GuardModule("Orders", Orders, {
        FilterAvoided: arg2,
        AvoidsLocation: no,
        CapRetreatDesire: arg2,
        OrderFloor: zero,
        DesireFloor: zero,
    });
    Telemetry.GuardModule("Commands", Commands, { ShouldUseOrderedSmoke: no });
    // A controller error drops that wave's ev=lane_ctl line; no bot action reads it.
    Telemetry.GuardModule("LaneControl", LaneControl, { Tick: none });
    // An error hands the hero to OHA's retreat desire for that call (undefined) and a Think that issues nothing.
    // Telemetry only: an error drops the purchase's ev=sustain_buy line.
    Telemetry.GuardModule("SustainGather", SustainGather, { Bought: none });
    // An error in sustain's executor gives no order that frame and lets OHA's item loop have the items (HoldsItem false);
    // the lane row and the supply step take no frame.
    Telemetry.GuardModule("SustainAct", SustainAct, { ItemThink: none, Holds: no, HoldsItem: no, HoldsBuy: no, OwnsCourier: no, Walking: no, Step: no, Yield: no, ResetCache: none });
    Telemetry.GuardModule("Retreat", Retreat, { Desire: none, Think: none, Tick: none, Running: no, Owns: no, On: no, Fountain: none, TowerOnUs: none, ResetCache: none });
    Telemetry.GuardModule("Perception", Perception, {
        FilterNearbyEnemies: arg2,
        FilterUnitList: arg1,
        FilterChanneling: arg2,
        IsCastKnown: () => true,
        GetIncomingTrackingProjectiles: (target: { GetIncomingTrackingProjectiles(this: unknown): unknown }) => target.GetIncomingTrackingProjectiles(),
    });
}
if (Telemetry.GuardsEnabled()) {
    for (const [k, fn] of pairs(steps as Record<string, (this: void, ...args: any[]) => any>)) (steps as any)[k] = Telemetry.PerfStep(`Tick:${k}`, fn);
}
Telemetry.PerfDeepInstall();
const guardedTick = Telemetry.GuardsEnabled() ? Telemetry.Guard("Tick", tick) : tick;

export function Tick(bot: Unit): void {
    guardedTick(bot);
}
