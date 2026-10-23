/**
 * Behaviour-state layer (Customize.Humaniser.States, team slice 1) on the SDK's `States` module. OHA supplies
 * the states (scorers read OHA's own decisions; bodies replace one OHA step each), ownership by position, the
 * host Think() hook and telemetry. Off (Enable = false) means no selection, no telemetry and no tasks.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as CampJob from "bots/FunLib/humaniser/states/camp_job";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";

export interface StatesSettings {
    Enable: boolean;
    /** Choose and log states for every bot in Teams; own only what Own lists. */
    Shadow: boolean;
    /** State name -> positions (J.GetPosition) whose body the SDK runs. */
    Own: Record<string, number[]>;
    /** "allies": allies of a human only (where OHA's Lua laning Think runs); "all": every bot. */
    Teams: "allies" | "all";
    /** Seconds between `lane_pos` telemetry lines per bot in the laning state. */
    LanePosEvery: number;
}

const LANE_POS_EVERY = 2;

export function Settings(): StatesSettings {
    return Config.Get().States as StatesSettings;
}

function ownList(state: string): number[] | undefined {
    const own = Settings().Own;
    return own !== undefined ? own[state] : undefined;
}

export function IsEnabled(): boolean {
    return Config.IsEnabled() && Settings().Enable === true && Tasks.Enabled();
}

function teamApplies(bot: Unit): boolean {
    return Settings().Teams === "all" || Difficulty.IsAllyOfHuman(bot);
}

function ownsAny(): boolean {
    const own = Settings().Own;
    if (own === undefined) return false;
    for (const [, list] of pairs(own)) if ((list as number[]).length > 0) return true;
    return false;
}

/** Whether the layer may ever own a state for this bot; for load-time decisions (mode_laning_generic's Think). */
export function MayOwn(bot: Unit): boolean {
    return IsEnabled() && teamApplies(bot) && ownsAny();
}

function owns(bot: Unit, state: string): boolean {
    const list = ownList(state);
    if (list === undefined) return false;
    const pos = LaneConfig.PositionOf(bot);
    for (const p of list) if (p === pos) return true;
    return false;
}

let installed = false;
const defined: Record<number, boolean | undefined> = {};
const lanePosAt: Record<number, number | undefined> = {};

function lib(): ReturnType<typeof Tasks.Loaded> {
    const l = Tasks.Loaded();
    if (l === undefined || l.States === undefined) return undefined;
    if (!installed) {
        installed = true;
        l.States.SetOwned((b, state) => owns(b as unknown as Unit, state));
    }
    return l;
}

function lanePos(bot: Unit, l: NonNullable<ReturnType<typeof Tasks.Loaded>>): void {
    const cur = l.States.Current(bot as unknown as Lib.TaskUnit);
    if (cur === undefined || cur.name !== Laning.NAME) return;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    if (now - (lanePosAt[pid] ?? -math.huge) < (Settings().LanePosEvery ?? LANE_POS_EVERY)) return;
    lanePosAt[pid] = now;
    const spot = Laning.Spot(bot);
    const task = Tasks.Current(bot);
    Telemetry.Event("lane_pos", [
        ["pid", pid],
        ["d", spot !== undefined ? math.floor(GetUnitToLocationDistance(bot, spot)) : undefined],
        ["owned", cur.owned],
        ["running", cur.running],
        ["label", cur.running ? task?.label : undefined],
        ["mode", bot.GetActiveMode()],
    ]);
}

/** Every frame from Humaniser.Tick, before Tasks.Tick. */
export function Tick(bot: Unit): void {
    if (!IsEnabled() || !teamApplies(bot)) return;
    if (Settings().Shadow !== true && !ownsAny()) return;
    const l = lib();
    if (l === undefined) return;
    const pid = bot.GetPlayerID();
    if (defined[pid] !== true) {
        defined[pid] = true;
        l.States.define(bot as unknown as Lib.TaskUnit, [
            Laning.Spec(bot),
            CampJob.Spec(bot, CampJob.STACK, owns),
            CampJob.Spec(bot, CampJob.PULL, owns),
            Rotate.Spec(bot),
        ]);
    }
    l.States.Tick(bot as unknown as Lib.TaskUnit);
    lanePos(bot, l);
}

/** Whether the layer runs `state`'s body for this bot now (enabled, team rule, position listed in Own). */
export function Owns(bot: Unit, state: string): boolean {
    return IsEnabled() && teamApplies(bot) && owns(bot, state);
}

CampJobs.SetExecutor({
    Owns: (bot, job) => {
        const state = CampJob.StateOf(job);
        return state !== undefined && Owns(bot, state) && lib() !== undefined;
    },
    Step: (bot) => Step(bot, BotMode.Farm),
});

/**
 * mode_rune_generic: OHA's own wisdom logic stands aside for this bot (its shrine trip is the state's) or for the
 * team (an owned trip is on the shrine this fill).
 */
export function WisdomOwned(bot: Unit): boolean {
    if (!IsEnabled()) return false;
    return (Owns(bot, Rotate.NAME) && Rotate.OnTrip(bot)) || Rotate.ShrineTaken(bot.GetTeam());
}

/** First thing in a host mode's Think() step it replaces: true when the state's body acted this frame. */
export function Step(bot: Unit, mode: number): boolean {
    if (!IsEnabled()) return false;
    const l = lib();
    return l !== undefined && l.States.Step(bot as unknown as Lib.TaskUnit, mode);
}

/** mode_laning_generic.lua hands over its PositionThink target (nil until its GetDesire has run). */
export function SetLaneSpot(bot: Unit, fn: (this: void) => Vector | undefined): void {
    Laning.SetSpot(bot, fn);
}

export function Describe(bot: Unit): string | undefined {
    if (!IsEnabled()) return undefined;
    const cur = Tasks.Loaded()?.States.Current(bot as unknown as Lib.TaskUnit);
    return cur === undefined ? "-" : `${cur.name}${cur.owned ? "*" : ""}${cur.running ? " run" : ""} n=${cur.starts}`;
}
