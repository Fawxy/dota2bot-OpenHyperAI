/**
 * Behaviour-state layer (Customize.Humaniser.States, team slice 1) on the SDK's `States` module. OHA supplies
 * the states (scorers read OHA's own decisions; bodies replace one OHA step each), ownership by position, the
 * host Think() hook and telemetry. Off (Enable = false) means no selection, no telemetry and no tasks.
 */
import type * as Lib from "bots/FunLib/sdk/tasks/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as LaneMetrics from "bots/FunLib/humaniser/states/lane_metrics";
import * as Shadow from "bots/FunLib/humaniser/states/shadow";
import * as CampJob from "bots/FunLib/humaniser/states/camp_job";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Farm from "bots/FunLib/humaniser/states/farm";
import * as Gank from "bots/FunLib/humaniser/states/gank";
import * as FarmPattern from "bots/FunLib/humaniser/farm_pattern";

export interface StatesSettings {
    Enable: boolean;
    /** Choose and log states for every bot in ShadowTeams (and Teams); own only what Own lists. */
    Shadow: boolean;
    /** State name -> positions (J.GetPosition) whose body the SDK runs. */
    Own: Record<string, number[]>;
    /** Who may own: "allies" = allies of a human only (where OHA's Lua laning Think runs); "all": every bot. */
    Teams: "allies" | "all";
    /** Who is shadowed (states chosen and logged, nothing owned beyond Teams): "allies" or "all". */
    ShadowTeams: "allies" | "all";
    /** Seconds between `lane_pos` telemetry lines per bot in the laning state. */
    LanePosEvery: number;
}

const LANE_POS_EVERY = 2;

/** `States.Modes` (team slice 14): the layer as the authority over mode desires (SDK `Modes`). */
export interface ModesSettings {
    Enable: boolean;
    /** Mode names the layer decides outright (suppressed unless they host the current state). */
    Own: string[];
    /** Positions (J.GetPosition) of the allowed team whose modes the layer decides. */
    Positions: number[];
    Hold: number;
    InterruptDwell: number;
    Commit: number;
    IdleAfter: number;
    IdleBackoff: number;
    /** Also decide for a current state that is only shadowed (OHA runs its behaviour). */
    Shadow: boolean;
    /** Reason tags an owned mode's score always passes with (mode files' escapes from danger). */
    Pass: string[];
}

const MODES_DEFAULTS: ModesSettings = {
    Enable: false,
    Own: ["laning", "farm"],
    Positions: [1, 2, 3, 4, 5],
    Hold: 0.08,
    InterruptDwell: 2.5,
    Commit: 0.75,
    IdleAfter: 3,
    IdleBackoff: 5,
    Shadow: false,
    // mode_farm_generic's run (Medusa's gaze, danger near the enemy fountain): 1.1 from farm, owned.
    Pass: ["run"],
};

/** Names accepted in Modes.Own: the modes that host a state of this layer. */
const MODE_IDS: Record<string, BotMode> = { laning: BotMode.Laning, farm: BotMode.Farm, rune: BotMode.Rune, roam: BotMode.Roam };

let modesSettings: ModesSettings | undefined;

// Read from Customize directly: Config's deep merge would mix a shorter Own/Positions list with the default one.
export function Modes(): ModesSettings {
    if (modesSettings !== undefined) return modesSettings;
    const c = (Config.Raw()?.States?.Modes ?? {}) as Partial<ModesSettings>;
    const out: any = {};
    for (const [k, v] of pairs(MODES_DEFAULTS)) out[k] = (c as any)[k] ?? v;
    modesSettings = out as ModesSettings;
    return modesSettings;
}

/** Tests reload Customize between cases. */
export function ResetModes(): void {
    modesSettings = undefined;
}

function modesOn(bot: Unit): boolean {
    const m = Modes();
    if (m.Enable !== true || !IsEnabled() || !ownTeam(bot)) return false;
    const pos = LaneConfig.PositionOf(bot);
    for (const p of m.Positions) if (p === pos) return true;
    return false;
}

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

function ownTeam(bot: Unit): boolean {
    return Settings().Teams === "all" || Difficulty.IsAllyOfHuman(bot);
}

function shadowTeam(bot: Unit): boolean {
    return Settings().Shadow === true && (Settings().ShadowTeams === "all" || ownTeam(bot));
}

function ownsAny(): boolean {
    const own = Settings().Own;
    if (own === undefined) return false;
    for (const [, list] of pairs(own)) if ((list as number[]).length > 0) return true;
    return false;
}

/** Whether the layer may ever own a state for this bot; for load-time decisions (mode_laning_generic's Think). */
export function MayOwn(bot: Unit): boolean {
    return IsEnabled() && ownTeam(bot) && ownsAny();
}

// Ownership is also gated by team here, not only at Tick: shadowed bots outside Teams are ticked too, and a
// Dire bot whose laning Think is Valve's C++ one must never get a task.
function owns(bot: Unit, state: string): boolean {
    if (!ownTeam(bot)) return false;
    const list = ownList(state);
    if (list === undefined) return false;
    const pos = LaneConfig.PositionOf(bot);
    for (const p of list) if (p === pos) return true;
    return false;
}

type SpecFactory = (this: void, bot: Unit) => Lib.StateSpec;

/** States by name in registration order; registering an existing name replaces it in place. */
const registry: { name: string; make: SpecFactory }[] = [];
let registryVersion = 0;

export function Register(name: string, make: SpecFactory): void {
    registryVersion += 1;
    for (const r of registry) {
        if (r.name === name) {
            r.make = make;
            return;
        }
    }
    registry.push({ name, make });
}

export function Registered(): string[] {
    return registry.map((r) => r.name);
}

Register(Laning.NAME, (bot) => Laning.Spec(bot, owns));
for (const [name, make] of Shadow.SPECS) Register(name, make);
// Owned job states (team slices 7-9) replace the shadow specs of the same name; unowned bots keep the shadow scores.
Register(CampJob.PULL, (bot) => CampJob.Spec(bot, CampJob.PULL, owns, Shadow.PullScore));
Register(CampJob.STACK, (bot) => CampJob.Spec(bot, CampJob.STACK, owns, Shadow.StackScore));
Register(Rotate.NAME, (bot) => Rotate.Spec(bot, owns, Shadow.RotateScore));
Register(Farm.NAME, (bot) => Farm.Spec(bot, Shadow.FarmScore));
Register(Gank.NAME, (bot) => Gank.Spec(bot, owns));

// The SDK treats a scorer error as "not applicable" and only logs it under Debug; with guards on it becomes an
// ev=lua_error like any other hook's, so a scorer failing on some bot (e.g. a Dire one) shows in the error count.
function guarded(spec: Lib.StateSpec): Lib.StateSpec {
    if (Telemetry.GuardsEnabled()) spec.score = Telemetry.Guard(`States.score.${spec.name}`, spec.score, () => undefined);
    return spec;
}

let installed = false;
const defined: Record<number, number | undefined> = {};
const lanePosAt: Record<number, number | undefined> = {};

function lib(): ReturnType<typeof Tasks.Loaded> {
    const l = Tasks.Loaded();
    if (l === undefined || l.States === undefined) return undefined;
    if (!installed) {
        installed = true;
        // `farm` is owned only while an SDK trip runs: a posture owned all game would start a task the farm mode
        // never steps outside trips, and the runner would cancel and restart it every second (pre-flight H1).
        l.States.SetOwned((b, state) => {
            const u = b as unknown as Unit;
            if (!owns(u, state)) return false;
            return state !== Farm.NAME || FarmPattern.Live(u)?.sdk === true;
        });
        installModes(l);
    }
    return l;
}

function installModes(l: NonNullable<ReturnType<typeof Tasks.Loaded>>): void {
    const m = Modes();
    const ids: number[] = [];
    for (const name of m.Own) {
        const id = MODE_IDS[name];
        if (id !== undefined) ids.push(id);
    }
    l.Modes.SetOwned(ids, { pass: m.Pass });
    l.Modes.SetEnabled((b) => modesOn(b as unknown as Unit));
    l.Modes.configure({ hold: m.Hold, interruptDwell: m.InterruptDwell, commit: m.Commit, idleAfter: m.IdleAfter, idleBackoff: m.IdleBackoff, shadow: m.Shadow });
    // Off: no authority at all, so Intent resolves exactly as before; the switch and idle counters still run.
    if (m.Enable === true) Intent.SetAuthority((bot, mode, raw, reason) => l.Modes.Decide(bot as unknown as Lib.TaskUnit, mode, raw, reason));
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
    const info = Laning.SpotInfo(bot);
    Telemetry.Event("lane_pos", [
        ["pid", pid],
        ["d", spot !== undefined ? math.floor(GetUnitToLocationDistance(bot, spot)) : undefined],
        ["owned", cur.owned],
        ["running", cur.running],
        ["label", cur.running ? task?.label : undefined],
        ["mode", bot.GetActiveMode()],
        ["spot", info !== undefined ? info.anchor : "oha"],
        ["pushed", info?.pushed],
        ["hph", LaneMetrics.HeroLost(bot)],
    ]);
}

/** Every frame from Humaniser.Tick, before Tasks.Tick. */
export function Tick(bot: Unit): void {
    if (!IsEnabled()) return;
    if (!shadowTeam(bot) && !(ownTeam(bot) && ownsAny())) return;
    const l = lib();
    if (l === undefined) return;
    const pid = bot.GetPlayerID();
    if (defined[pid] !== registryVersion) {
        defined[pid] = registryVersion;
        l.States.define(
            bot as unknown as Lib.TaskUnit,
            registry.map((r) => guarded(r.make(bot))),
        );
    }
    l.States.Tick(bot as unknown as Lib.TaskUnit);
    l.Modes.Tick(bot as unknown as Lib.TaskUnit);
    LaneMetrics.Tick(bot);
    lanePos(bot, l);
}

/** Whether the layer runs `state`'s body for this bot now (enabled, team rule, position listed in Own). */
export function Owns(bot: Unit, state: string): boolean {
    return IsEnabled() && owns(bot, state);
}

/** Steps the bot's farm-hosted state only when it is one of `names`, so one executor never runs another's body. */
function stepFarm(bot: Unit, names: Record<string, boolean>): boolean {
    const cur = lib()?.States.Current(bot as unknown as Lib.TaskUnit);
    return cur !== undefined && names[cur.name] === true && Step(bot, BotMode.Farm);
}

const FARM_STATES: Record<string, boolean> = { [Farm.NAME]: true };
const CAMP_STATES: Record<string, boolean> = { [CampJob.STACK]: true, [CampJob.PULL]: true };

FarmPattern.SetExecutor({
    Owns: (bot) => Owns(bot, Farm.NAME) && lib() !== undefined,
    Step: (bot) => stepFarm(bot, FARM_STATES),
});

CampJobs.SetExecutor({
    Owns: (bot, job) => {
        const state = CampJob.StateOf(job);
        return state !== undefined && Owns(bot, state) && lib() !== undefined;
    },
    Step: (bot) => stepFarm(bot, CAMP_STATES),
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

/** True while the laning body runs for this bot and owns its last hits: the Lua Think skips its own. */
export function BodyLastHits(bot: Unit): boolean {
    if (!IsEnabled() || !Laning.OwnsLastHit(bot)) return false;
    const cur = Tasks.Loaded()?.States.Current(bot as unknown as Lib.TaskUnit);
    return cur !== undefined && cur.name === Laning.NAME && cur.owned && cur.running;
}

/**
 * mode_laning_generic.lua hands over its own laning steps (everything its Think does but PositionThink); the
 * laning body runs them on its hold and walk frames, so none can re-order a last-hit swing (team slice 14).
 */
export function SetLaneAssist(bot: Unit, fn: (this: void) => boolean): void {
    Laning.SetAssist(bot, fn);
}

/** Whether the layer decides this bot's mode desires now (overlay, tests). */
export function ModesAsserting(bot: Unit): boolean {
    if (!IsEnabled()) return false;
    const l = Tasks.Loaded();
    return l !== undefined && l.Modes !== undefined && l.Modes.Asserting(bot as unknown as Lib.TaskUnit);
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
