/**
 * Humaniser entry point, exposed as J.Humaniser.
 * Tick(bot) runs every frame per bot from ItemUsageThink, before that function's throttle.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as Chat from "bots/FunLib/humaniser/chat";
import * as DesireLog from "bots/FunLib/humaniser/desire_log";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as RegenObs from "bots/FunLib/humaniser/regen_obs";
import * as ApiProbe from "bots/FunLib/humaniser/api_probe";
import * as VisionMap from "bots/FunLib/humaniser/vision_map";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as StackJob from "bots/FunLib/humaniser/stack_job";
import * as RuneJob from "bots/FunLib/humaniser/rune_job";
import * as RunePickup from "bots/FunLib/humaniser/rune_pickup";
import * as RunePlan from "bots/FunLib/humaniser/rune_plan";
import * as Plays from "bots/FunLib/humaniser/plays/plays";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as Chooser from "bots/FunLib/humaniser/chooser";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as ChoiceShadow from "bots/FunLib/humaniser/choice_shadow";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Drill from "bots/FunLib/humaniser/drill";

export { Config, HDebug, Chat, LaneConfig, Telemetry, Ours, StackJob, RuneJob, RunePickup, RunePlan, Plays, PullJob, Chooser, Decider, Overrides, Drill, ChoiceShadow };
// tasks: task runner spike
import * as Tasks from "bots/FunLib/humaniser/tasks";
// tasks: task runner spike
export { Tasks };
import * as States from "bots/FunLib/humaniser/states/index";
export { States };
import * as Retreat from "bots/FunLib/humaniser/retreat";
export { Retreat };
import * as SustainGather from "bots/FunLib/humaniser/sustain_gather";
export { SustainGather };
import * as SustainAct from "bots/FunLib/humaniser/sustain_act";
export { SustainAct };
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
export { SafeGather };
import * as CastLog from "bots/FunLib/humaniser/cast_log";

const OVERLAY_REFRESH = 0.25;
const overlayAt: Record<number, number> = {};

export function IsEnabled(): boolean {
    return Config.IsEnabled();
}

function telemetryContext(this: void, bot: Unit): Telemetry.BotContext {
    return { by: DesireLog.Explain(bot, bot.GetActiveMode()), competing: DesireLog.Competing(bot) };
}

function drawOverlay(bot: Unit): void {
    if (!HDebug.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    const now = GameTime();
    if (now - (overlayAt[pid] ?? -1) >= OVERLAY_REFRESH) {
        overlayAt[pid] = now;
        HDebug.Text(bot, "desire", DesireLog.Explain(bot, bot.GetActiveMode()));
        if (Tasks.IsActive()) HDebug.Text(bot, "task", Tasks.Describe(bot) ?? "-");
    }
    HDebug.Draw(bot);
}

// The unguarded steps of tick, so the perf probe can time each (Telemetry.PerfStep; installed below, after the guards).
// Copied here at load, before GuardModule runs: a step that gets a guard later must leave this table and be called by name.
const steps = {
    feed: Camps.FeedNeutralSpeeds,
    telemetry: Telemetry.Tick,
    regen: RegenObs.Tick,
    // A hero sustain carries logs its own cut from ItemThink: the shadow skips it.
    sustain: (bot: Unit) => {
        if (!SustainAct.Holds(bot)) SustainGather.Tick(bot);
    },
    landing: SafeGather.Tick,
    pullShadow: PullJob.Shadow,
    stackShadow: StackJob.Shadow,
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
    Drill.Tick(bot);
    Retreat.Tick(bot);
    // The landing sampler (safe here's `landing`): once per hero per tick, with telemetry off too. See SafeGather.Tick.
    pcall(steps.landing, bot);
    steps.telemetry(bot, telemetryContext);
    // Slice chase-log: our casts (ev=cast), logged a tick after the callback queues them.
    pcall(CastLog.Tick, bot);
    // The observer only reads: an error in it must not skip the Tasks tick below.
    pcall(steps.regen, bot);
    // Sustain: the decision in shadow (ev=cut kind=sustain) for a hero sustain_act.ts does not carry; reads and logs, no order.
    pcall(steps.sustain, bot);
    // The pull's trigger where the pull is switched off (ev=choice kind=pull src=shadow): reads and logs, no order.
    pcall(steps.pullShadow, bot);
    pcall(steps.probe, bot);
    // Overrides.VisionMap only: the map dump for the sight model (reads and logs).
    pcall(VisionMap.Tick, bot);
    steps.tasks(bot);
    HDebug.SharedStateProbe(bot);
    steps.overlay(bot);
}

const none = (): undefined => undefined;
const no = (): boolean => false;
const zero = (): number => 0;

// Each fallback is what the hook returns with its feature off, so a humaniser error degrades to upstream behaviour.
if (Telemetry.GuardsEnabled()) {
    Telemetry.GuardModule("States", States, { MayOwn: no, WisdomOwned: no });
    // An error leaves the farm mode to OHA (no job desire, no owned Think).
    Telemetry.GuardModule("StackJob", StackJob, { Wants: no, Step: no, End: none, Running: no, NoteIdleHeld: none, NoteHit: none, Benched: no, Bench: no, Minutes: () => StackJob.SETTINGS.TriggerMinutes });
    // A drill error plays the hero as in a normal game (no bench, no statue, not lane-only).
    Telemetry.GuardModule("Drill", Drill, { Tick: none, Held: no, Casts: no, Hold: no, LaneOnly: no, InLane: no, InLaneDenies: no, ForbidsItem: no, ForbidsCast: no, IdleStatue: no, Owns: no, ForcedJob: none, ForcedAt: none, RoleOf: () => "play", Implied: none, RepTimes: none, RepAt: zero, Name: none, Active: none });
    Telemetry.GuardModule("Chooser", Chooser, { RunningJobName: none, Decide: none, FarmDesire: zero, FarmThink: no, Abort: none, HoldsRun: no, PullsNeutrals: no, HoldsIdle: no, HoldsCasts: no, Benched: no, Bench: no });
    // An error hands the hero to OHA's retreat desire for that call (undefined) and a Think that issues nothing.
    // Telemetry only: an error drops the purchase's ev=sustain_buy line.
    Telemetry.GuardModule("SustainGather", SustainGather, { Bought: none });
    // An error in sustain's executor gives no order that frame and lets OHA's item loop have the items (HoldsItem false);
    // the lane row and the supply step take no frame.
    Telemetry.GuardModule("SustainAct", SustainAct, { ItemThink: none, Holds: no, HoldsItem: no, HoldsBuy: no, OwnsCourier: no, Walking: no, Step: no, ResetCache: none });
    Telemetry.GuardModule("Retreat", Retreat, { Desire: none, Think: none, Tick: none, Running: no, Owns: no, On: no, Fountain: none, TowerOnUs: none, ResetCache: none });
}
if (Telemetry.GuardsEnabled()) {
    for (const [k, fn] of pairs(steps as Record<string, (this: void, ...args: any[]) => any>)) (steps as any)[k] = Telemetry.PerfStep(`Tick:${k}`, fn);
}
Telemetry.PerfDeepInstall();
// The decider's rows, in doctrine order. A row's error yields the hero to stock for that call (not applying; finished).
if (Decider.ROWS.indexOf(PullJob.ROW) < 0) {
    if (Telemetry.GuardsEnabled()) {
        PullJob.ROW.applies = Telemetry.Guard("PullRow.applies", PullJob.ROW.applies, no);
        PullJob.ROW.step = Telemetry.Guard("PullRow.step", PullJob.ROW.step, () => true);
    }
    Decider.ROWS.push(PullJob.ROW);
    if (Telemetry.GuardsEnabled()) {
        StackJob.ROW.applies = Telemetry.Guard("StackRow.applies", StackJob.ROW.applies, no);
        StackJob.ROW.step = Telemetry.Guard("StackRow.step", StackJob.ROW.step, () => true);
    }
    Decider.ROWS.push(StackJob.ROW);
}
const guardedTick = Telemetry.GuardsEnabled() ? Telemetry.Guard("Tick", tick) : tick;

export function Tick(bot: Unit): void {
    guardedTick(bot);
}
