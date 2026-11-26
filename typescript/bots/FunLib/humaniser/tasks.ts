/**
 * OHA integration for the engine's task runner (bundle bots/FunLib/engine/tasks.lua, built from engine/).
 *
 * The bundle is required lazily under pcall, only once the humaniser and Tasks.Enable are on: a static require
 * would let a bundle that fails to load in Dota's VM break the whole humaniser module, even with Enable = false.
 * No task of ours posts a claim: the jobs hold their host mode through the chooser.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneOffers from "bots/FunLib/humaniser/lane_offers";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Utils from "bots/FunLib/utils";

type Bundle = typeof Lib;

let attempted = false;
let lib: Bundle | undefined;

export function Enabled(): boolean {
    return Config.IsEnabled() && Config.Get().Tasks.Enable !== false;
}

/** A switch whose job runs on the bundle (StackJob, slice 4): it loads the bundle through `ForOurs` with the humaniser off. */
function oursOn(): boolean {
    return Ours.On("StackExecute") || Ours.On("RuneRotation") || Ours.On("SupportPull");
}

/** A core counts as able to take a creep this far past its attack range (`judgement`). */
const CORE_REACH_BUFFER = 150;
/** ... or when its position this far ahead (s) is nearer the creep by more than the epsilon (it is walking to it). */
const APPROACH_LOOKAHEAD = 0.5;
const APPROACH_EPSILON = 25;

function coreCanReach(core: Unit, creep: Unit): boolean {
    const dist = GetUnitToUnitDistance(core, creep);
    if (dist <= core.GetAttackRange() + CORE_REACH_BUFFER) return true;
    const ahead = GetUnitToLocationDistance(creep, (core as Unit & { GetExtrapolatedLocation(seconds: number): Vector }).GetExtrapolatedLocation(APPROACH_LOOKAHEAD));
    return ahead < dist - APPROACH_EPSILON;
}

/** An allied core (position 1-3, not the bot) within 1600 that can take the creep itself. */
function CoreCanTake(bot: Unit, creep: Unit, allies: Unit[]): boolean {
    for (const ally of allies) {
        if (ally !== bot && ally.IsAlive()) {
            const pos = LaneConfig.PositionOf(ally);
            if (pos !== undefined && pos <= 3 && coreCanReach(ally, creep)) return true;
        }
    }
    return false;
}

interface FilterFrame {
    t: number;
    by: LuaTable<object, boolean>;
    allies?: Unit[];
}
/** One table per bot, cleared on a new frame (no allocation per frame). */
const filterCache: Record<number, FilterFrame | undefined> = {};

function mayTake(bot: Unit, creep: Unit, f: FilterFrame): boolean {
    if (creep === undefined || creep === null || creep.IsNull()) return false;
    // A bot outside positions 1 and 2 leaves the creep to a core that can take it.
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined || pos <= 2) return true;
    if (f.allies === undefined) f.allies = bot.GetNearbyHeroes(1600, false, BotMode.None);
    return !CoreCanTake(bot, creep, f.allies);
}

/** Skill 1 (the adapter gives no `skill`, which the engine reads as 1): no reaction delay, jitter, aim error or lapse. */
const SKILL_ONE = { react: 0, jitter: 0, aimError: 0, lapse: 0 };

const adapter: Lib.Adapter = {
    claim: () => undefined,
    release: () => undefined,
    lastHitFilter: (bot, creep) => {
        // laneTargets asks for every creep every frame; one answer per bot, creep and frame.
        const pid = bot.GetPlayerID();
        const now = DotaTime();
        let f = filterCache[pid];
        if (f === undefined) {
            f = { t: now, by: new LuaTable<object, boolean>() };
            filterCache[pid] = f;
        } else if (f.t !== now) {
            f.t = now;
            f.allies = undefined;
            for (const [k] of f.by) f.by.delete(k);
        }
        const by = f.by;
        const hit = by.get(creep);
        if (hit !== undefined) return hit;
        const allowed = mayTake(bot as unknown as Unit, creep as unknown as Unit, f);
        by.set(creep, allowed);
        return allowed;
    },
    profile: () => SKILL_ONE,
    lastHitError: () => 0,
    random: () => RandomFloat(0, 1),
    // GetLastAttackTime is on the GameTime clock.
    attackClock: () => GameTime(),
    // DotaTime, the clock camp-job plans are timed in; the runner and verbs only ever use differences of it.
    now: () => DotaTime(),
    log: (tag, msg) => HDebug.Log(tag, msg),
    event: (name, fields) => Telemetry.EventUntyped(name, fields as [string, any][]),
    vector: (x, y, z) => Vector(x, y, z),
    enabled: () => Enabled() || oursOn(),
};

function loadBundle(ours = false): Bundle | undefined {
    if (!Enabled() && !(ours && oursOn())) return undefined;
    if (attempted) return lib;
    attempted = true;
    const [ok, res] = pcall(require, GetScriptDirectory() + "/FunLib/engine/tasks");
    const support = `[H:tasks] support coroutine=${type(coroutine)} bundle=`;
    // Always printed (not gated on Debug): the first in-game check is whether the bundle loads at all.
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    if (ok && type(res) === "table") {
        lib = res as Bundle;
        lib.init(adapter);
        JobVerbs.Bind(lib, adapter);
        const verbs = lib.Verbs;
        LaneOffers.SetOffers(bot => verbs.laneTargets(bot, { within: 1 }));
        (rawPrint ?? print)(support + "ok");
    } else {
        (rawPrint ?? print)(`${support}fail ${tostring(res)}`);
    }
    return lib;
}

/** The loaded bundle (loading it on first use), or undefined when tasks are off or it failed to load. */
export function Loaded(): Bundle | undefined {
    return loadBundle();
}

// LaneConfig.Roll / Gauss draw from the SDK Skill model (loading the bundle if needed); RandomFloat while tasks are off.
LaneConfig.SetRng(() => loadBundle()?.Skill);

/** True once the bundle has loaded and tasks are enabled. */
export function IsActive(): boolean {
    return lib !== undefined && Enabled();
}

/**
 * The decider's rows' task names: only the decider starts one (`Begin`), since a start replaces whatever task the hero has
 * (the runner's `replaced`) and the order among rows is the decider's. A row's name is its task's name.
 */
const ROW_TASKS: Record<string, boolean> = { pull: true, stack: true, rune_detour: true, creep: true };

/**
 * The older chooser path, as built, starts a `stack` task of its own and names itself in `via`. RuneJob.Wants and
 * RuneJob.MidWants start `rune`, which is no row's task, so they need no entry.
 */
const EXEMPT: Record<string, boolean> = { "StackJob.Wants": true };

/** The row whose begin the decider is running, if any. */
let beginning: string | undefined;

/** The decider's begin: `begin` runs with `row`'s task start allowed. An error in it is raised again after the allowance ends. */
export function Begin(row: string, begin: (this: void) => boolean): boolean {
    const prev = beginning;
    beginning = row;
    const [ok, res] = pcall(begin);
    beginning = prev;
    if (!ok) error(res, 0);
    return res === true;
}

/** A row's task started anywhere but the decider's begin: refused and logged (ev=lua_error where=Tasks.Start). */
function refusedRowStart(name: string, via: string | undefined): boolean {
    if (ROW_TASKS[name] !== true || beginning === name || (via !== undefined && EXEMPT[via] === true)) return false;
    Telemetry.Failed("Tasks.Start", `row task ${name} started outside the decider's begin`);
    return true;
}

export function Start(bot: Unit, opts: Lib.TaskOptions, body: Lib.TaskFactory, via?: string): boolean {
    if (refusedRowStart(opts.name, via)) return false;
    const l = loadBundle();
    return l !== undefined && l.Tasks.task(bot as unknown as Lib.TaskUnit, opts, body);
}

/** Call from the host mode's Think(); returns false when no task of this bot runs under `mode`. */
export function Step(bot: Unit, mode: number): boolean {
    const l = loadBundle();
    return l !== undefined && l.Tasks.Step(bot as unknown as Lib.TaskUnit, mode);
}

export function Tick(bot: Unit): void {
    loadBundle()?.Tasks.Tick(bot as unknown as Lib.TaskUnit);
}

/** Never loads the bundle: no task can be running before one was started. */
export function Current(bot: Unit): ReturnType<Bundle["Tasks"]["Current"]> {
    return IsActive() ? lib!.Tasks.Current(bot as unknown as Lib.TaskUnit) : undefined;
}

/** The running task however the bundle was loaded (ForOurs too); never loads it (the overlay). */
export function Running(bot: Unit): ReturnType<Bundle["Tasks"]["Current"]> {
    return lib?.Tasks.Current(bot as unknown as Lib.TaskUnit);
}

export function Cancel(bot: Unit, reason: Lib.Reason, message?: string): void {
    if (IsActive()) lib!.Tasks.Cancel(bot as unknown as Lib.TaskUnit, reason, message);
}

export function Urgent(bot: Unit, on: boolean): void {
    lib?.Tasks.Urgent(bot as unknown as Lib.TaskUnit, on);
}

export function Label(bot: Unit, label: string): void {
    lib?.Tasks.Label(bot as unknown as Lib.TaskUnit, label);
}

export function Describe(bot: Unit): string | undefined {
    return loadBundle()?.Tasks.Describe(bot as unknown as Lib.TaskUnit);
}

export function Verbs(): Bundle["Verbs"] | undefined {
    return loadBundle()?.Verbs;
}

/** The job verbs (bot code on the engine's verbs), or undefined when tasks are off or the bundle failed to load. */
export function Jobs(): typeof JobVerbs | undefined {
    return loadBundle() !== undefined ? JobVerbs : undefined;
}

/**
 * The task calls for a job behind an Ours switch (StackJob): the same runner, loaded for the switch alone, so the job runs
 * with the humaniser or its tasks off. The humaniser's own calls above stay gated on Enabled().
 */
export const ForOurs = {
    Start: (bot: Unit, opts: Lib.TaskOptions, body: Lib.TaskFactory, via?: string): boolean => {
        if (refusedRowStart(opts.name, via)) return false;
        const l = loadBundle(true);
        return l !== undefined && l.Tasks.task(bot as unknown as Lib.TaskUnit, opts, body);
    },
    Step: (bot: Unit, mode: number): boolean => {
        const l = loadBundle(true);
        return l !== undefined && l.Tasks.Step(bot as unknown as Lib.TaskUnit, mode);
    },
    Tick: (bot: Unit): void => {
        loadBundle(true)?.Tasks.Tick(bot as unknown as Lib.TaskUnit);
    },
    Cancel: (bot: Unit, reason: Lib.Reason, message?: string): void => {
        lib?.Tasks.Cancel(bot as unknown as Lib.TaskUnit, reason, message);
    },
    Running: (bot: Unit): ReturnType<Bundle["Tasks"]["Current"]> => lib?.Tasks.Current(bot as unknown as Lib.TaskUnit),
    Jobs: (): typeof JobVerbs | undefined => (loadBundle(true) !== undefined ? JobVerbs : undefined),
    Verbs: (): Bundle["Verbs"] | undefined => loadBundle(true)?.Verbs,
};
