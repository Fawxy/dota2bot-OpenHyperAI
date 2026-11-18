/**
 * Lane management configuration and shared helpers (task 07).
 * Every tunable lives in DEFAULTS; Settings() deep-merges Customize.Humaniser.Lane over it.
 * jmz_func cannot be required from humaniser modules, so J.* helpers arrive through SetHelpers.
 */
import { Unit } from "bots/ts_libs/dota";
import * as GameRules from "bots/FunLib/humaniser/game_rules";
import * as Config from "bots/FunLib/humaniser/config";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

export type LaneFlag =
    | "Plan"
    | "Block"
    | "FullPull"
    | "StackPull"
    | "AggroPull"
    | "Freeze"
    | "Shove"
    | "Stack"
    | "Mid"
    | "CounterPlay"
    | "Telegraph"
    | "Forecast";
export type Technique = "block" | "full_pull" | "stack_pull" | "aggro_pull" | "freeze" | "shove" | "stack";
export type CurveName =
    | "JitterSigma"
    | "AttemptRate"
    | "PathNoise"
    | "StackAttempt"
    | "CounterNotice"
    | "PlanMisread"
    | "CoverAbsentCore"
    | "Foresight"
    | "SureCommit";

export const DEFAULTS = {
    Enable: true,
    Plan: true,
    Block: true,
    FullPull: true,
    StackPull: true,
    AggroPull: true,
    Freeze: true,
    Shove: true,
    Stack: true,
    Mid: true,
    CounterPlay: true,
    Telegraph: true,
    Forecast: true,
    ForecastModel: { K: 0.4, TypeWeight: { melee: 1.0, ranged: 1.6, siege: 1.0 }, PowerFloor: 550 },
    Gates: {
        Block: 0.3,
        FullPull: 0.3,
        StackPull: 0.75,
        AggroPull: 0.5,
        Freeze: 0.7,
        Shove: 0.4,
        SoloCampJob: 0.6,
        MultiStackAncients: 0.7,
    },
    // Skill 1 is no handicap of ours (user 12/11/2026): chances end at 1, errors and noise at 0.
    Curves: {
        JitterSigma: [1.5, 0],
        AttemptRate: [0.15, 1],
        PathNoise: [150, 0],
        StackAttempt: [0.2, 1],
        CounterNotice: [0.2, 1],
        PlanMisread: [0.3, 0],
        CoverAbsentCore: [0.3, 1],
        Foresight: [0, 1],
        // Slice rune-spawn, Plays' sure tier: the chance a sure play commits (1 at skill 1: no draw). Judgement.
        SureCommit: [0.5, 1],
    } as Record<string, number[]>,
    Eq: { Safe: -0.7, Off: -0.7, Mid: -0.1, MidPreRune: 0.15, XpDenyWeight: 0.2 },
    Planner: { FullPullBelow: -0.5, AggroCorrectBelow: -0.15, AggroStepEq: 0.15 },
    Timing: {
        SnapshotRefresh: 0.5,
        WaveCycle: GameRules.WAVE_EVERY,
        BlockEnd: 30,
        StackMoveFrom: 45,
        StackExitUntil: 1.0,
        StackOutcomeAt: 2,
        StackOutcomeUntil: 5,
        StackEarlyBefore: 52,
        StackLateAfter: 57,
        StackAssumedFrom: 53,
        StackAssumedTo: 56,
        // Stack the camps creep_pull_timings.txt names at StackWindowAt through Valve's window (Stacking.WINDOWS).
        StackFromValve: true,
        StackWindowAt: 0.5,
        JobDesire: 0.7,
        // Valve's attack mode (0.95, C++ for most heroes, so no claim can lower it) cut 9 of 34 jobs in
        // console.9055994510, most in lane skirmishes the puller was not part of. The job's farm sits just above it.
        JobCommitDesire: 0.96,
        // Tango and clarity on the way to a pull only with this much time to spare before the walk to the stand.
        SupplySlack: 1.5,
        // Longest the job waits, giving no other order, for an ordered tango or clarity to take effect.
        SupplyWait: 1.5,
        PartnerHPWindow: 2,
        PartnerBailConfirm: 0.4,
        JobStartSlack: 3,
        JobStartLate: 2,
        JobMaxAfterAggro: 15,
        JobPreemptAfter: 1,
        JobHoldHeroHit: 1.5,
        JobStartHeroHit: 2,
        JobUpcoming: 10,
        MaxTravel: 12,
        // An enemy seen at our front this long is one of the lane's laners; sightings further apart than the gap add nothing.
        LanerSeenMin: 10,
        LanerSeenGap: 1,
        EqSampleAt: 10,
        WatchSec: 8,
        WatchEvery: 0.25,
        PullPeriod: GameRules.NEUTRAL_EVERY,
        NeutralFirstSpawn: GameRules.NEUTRAL_FIRST,
        NoCampAfter: 1,
        AggroConfirm: 2,
        // Order-to-hit estimate when J.GetAttackProDelayTime is not injected; the order goes this early.
        AggroLeadDefault: 0.4,
        AggroLeadMax: 1.5,
        // A stand point with no neutral in sight moves in toward the spawner origin from this long before the aggro.
        StandApproachLead: 3,
        // Double pull, hard camp first: its hit leaves DoublePullHitGap before the walk to the small camp's stand, that
        // walk is at most DoublePullMaxGap, and the hard camp must reach the meet by DoublePullJoin after the wave.
        DoublePullHitGap: 1,
        DoublePullMaxGap: 6,
        DoublePullJoin: 3,
        PingHandsOff: 30,
        PlanSustain: 5,
        PlanMinDwell: 15,
        HumanPullWindow: 6,
        CounterUnseen: 4,
        CounterPullWindow: 3,
        CounterWaveLate: 5,
        CounterSignalTTL: 20,
        MidRuneShoveLookahead: 25,
        RuneContestAfter: 10,
        RuneContestDesire: 0.6,
        MarkedStackFor: 120,
        StackWatchFrom: 50,
        StackWatchTo: 58,
        StackOutsideUntil: 3,
        StackedCampSeen: 5,
        CounterForgetAfter: 120,
        PreRuneMin: 15,
        PreRuneMax: 20,
        PullTelegraphLead: 5,
        PullTelegraphCooldown: 60,
        StackTelegraphCooldown: 120,
        CounterTelegraphCooldown: 60,
        ExposureSeen: 3,
    },
    Thresholds: {
        CoreAbsentDist: 1200,
        PartnerMinHP: 0.4,
        JobMinHP: 0.4,
        JobHoldMinHP: 0.5,
        // Starting needs room above JobHoldMinHP for the camp's hits (console.9055994510: 4 of 8 jobs that ended in
        // retreat started at 51-59%).
        JobStartHP: 0.65,
        // A pull, stack or take does not start while a lane enemy went missing at most this long ago: a fresh
        // disappearance is a gank threat to the core left behind; one gone longer is back in base or at its own camp.
        JobMissingFresh: 20,
        // Before a pull: a tango from this much lost HP and a clarity from this much lost mana, as the camp's hits and
        // the pull's casts will use the rest (upstream waits for 200 HP or 60% mana).
        TangoMinLost: 80,
        ClarityMinLost: 150,
        PartnerDangerEnemies: 2,
        PartnerDangerRadius: 1200,
        PartnerBailHP: 0.35,
        PartnerDiveLoss: 0.12,
        CoverRetreatScale: 1.25,
        JobFocusMargin: 0.02,
        SupportNearFront: 800,
        StableEnemyRadius: 1200,
        StableSeenWithin: 3,
        StableMinHP: 0.5,
        FullPullMin: 0.8,
        // Fallback only: the tower's reach to a point is read live (world_facts; 844 in 7.41 = attack range 700 + tower radius 144).
        EnemyTowerRange: 844,
        // Fallback only: a hero's bounding radius (24), added to the tower's reach for a hero's centre (edges meet, user 08/11/2026).
        HeroRadius: 24,
        ShoveMinHP: 0.5,
        FreezeDriftMargin: 0.2,
        MidTowerEq: 0.8,
        FreezeCoreEqMax: -0.3,
        MidMissingEq: -0.6,
        FreezeSuspectEq: 0.6,
        ThinWaveMargin: 2,
        WaveCreeps: 4,
        StackMaxCampCount: 1,
        ApproachEpsilon: 25,
        ExposureEnemies: 2,
    },
    Radii: {
        LaneCreep: 1200,
        LaneAssign: 1200,
        AllyNearFront: 1600,
        Exposure: 1500,
        LaneFrontPing: 600,
        HumanPullRadius: 800,
        StepBackCreeps: 700,
        StepBackEps: 50,
        NeutralSearch: 700,
        // An enemy hero this close lets a camp job's bot cast again and ends its commitment over Valve's attack mode.
        JobEnemyHero: 1200,
        // Tango's tree, near enough not to cost the pull its timing.
        TangoTree: 300,
        // A start is a fight's when an enemy hero this close is hitting the bot or being hit by it.
        JobStartEnemy: 800,
        StandOffset: 150,
        // Stand at most this far from the spawner origin: inside NeutralSearch with room for the camp's spread.
        StandReach: 450,
        // Approaching an unseen camp stops this far short of the spawner origin.
        StandApproach: 150,
        ExitCheckStep: 300,
        PartnerDive: 700,
        CoverCamp: 1200,
        JobArrive: 100,
        LaneCreepScan: 1600,
        MeetWatch: 800,
        WaveSize: 1200,
        StackExit: 900,
        StackCoreCamp: 3000,
        StackSight: 1200,
        StackCountScan: 1600,
        EnemyNearCamp: 800,
        NeutralOutsideMargin: 200,
        // A support last seen this near where a puller stands; a guess (vision is not logged), check inferred=1 signals.
        PullCampLastSeen: 800,
        PullerNear: 300,
        StackedCampSafe: 1500,
        CounterNeutralScan: 1600,
        PullPathEdge: 150,
        BoxMargin: 300,
        Stronger: 1200,
        ApproachExtrapolate: 0.5,
    },
    Infer: { ShoveHits: 4, FreezeDenies: 2, FreezeEqMax: -0.5, HoldSignals: 2, ShoveHitDamageMult: 1.3 },
    Camps: { PullCampMaxTowerDist: 2500, PullCampMaxLaneDist: 2400, ReplayMatchRadius: 600, LaneSampleStep: 0.005 },
    // Pull aggro from wave arrival (pull_timing.ts); FromWave false keeps the camp data seconds.
    PullTiming: {
        FromWave: true,
        // npc_units.txt (7.41): every lane creep MovementSpeed 325.
        CreepSpeed: 325,
        // Camp leaders' speeds from npc_units.txt (fastest common member per type), capped near a support's ~300,
        // since the camp chases the puller.
        NeutralSpeed: { small: 290, medium: 300, large: 300, ancient: 290 } as Record<string, number>,
        // Seconds the neutrals reach the meet point before the wave.
        Lead: 1.5,
        // Seconds our wave reaches a point ahead of CreepSpeed from spawn. 7.41 speeds the safe-lane wave up and slows the
        // off lane's after spawn (patch notes, no figure). From the wave's body (LiveRead's `sh` on top of the first values,
        // safe 3 / off 0.5, in ptm1): Radiant safe about 2.4, Dire safe about 3.7, off lane about -0.5 (camp 18) and -0.3
        // (camp 2). Safe is not split by side on 9-11 pulls each; LiveRead corrects the rest. `judgement`. Plans read with
        // no live reading (counterplay, lane_plan, camp jobs) take these as they are.
        WaveAhead: { safe: 3, off: -0.4 },
        WaveSlots: [0, 30],
        // evil_2's meet from GetLocationAlongLane stands ~340 off the Dire top creep path (watch positions, 9055874680).
        PathMaxOffset: 500,
        LiveFrom: 2,
        LiveWindow: 5,
        LiveMaxOffset: 600,
        LiveMaxShift: 4,
        // Live re-timing (slice pull-live): the wave is read again this often from the leave time to the meet point.
        LiveEvery: 0.25,
        WatchAfterWave: 3,
        // The hit is timed on the wave's creeps (pull_timing CreepTimer): the neutrals reach the meet point as the front creep
        // is FullPast beyond it (plv2's pace aimed them 0.5 s before the wave's body, the front creep running 0.5-1 s ahead
        // of the body: about 100 past). `judgement`.
        FullPast: 100,
        // Per `<radiant|dire>_<top|mid|bot>`, [x, y] points from the lane spawner; overrides pull_timing's 7.41 paths.
        LanePaths: {} as Record<string, number[][]>,
    },
    Orders: { FreezeShove: 90, PullNoPull: 120, Stack: 60 },
};

export type LaneSettings = typeof DEFAULTS;

const FLAG_OF: Record<Technique, LaneFlag> = {
    block: "Block",
    full_pull: "FullPull",
    stack_pull: "StackPull",
    aggro_pull: "AggroPull",
    freeze: "Freeze",
    shove: "Shove",
    stack: "Stack",
};

const GATE_OF: Record<Technique, string | undefined> = {
    block: "Block",
    full_pull: "FullPull",
    stack_pull: "StackPull",
    aggro_pull: "AggroPull",
    freeze: "Freeze",
    shove: "Shove",
    stack: undefined,
};

// Telegraph only produces chat lines, so it never keeps the lane system active on its own.
const CONSUMER_FLAGS: LaneFlag[] = [
    "Plan",
    "Block",
    "FullPull",
    "StackPull",
    "AggroPull",
    "Freeze",
    "Shove",
    "Stack",
    "Mid",
    "CounterPlay",
];

function isArray(t: any): boolean {
    return t[1] !== undefined;
}

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" && !isArray(d) ? merge(d, v) : v;
    }
    return result;
}

let cached: LaneSettings | undefined;

/**
 * How far from an enemy tower a hero's centre can be attacked: the tower's attack range and radius plus the hero's radius
 * (the edges meet; 868 in 7.41), read from the game (world_facts), the Thresholds constants when a read fails.
 */
export function TowerReach(): number {
    const t = Settings().Thresholds;
    return WorldFacts.Reach(t.EnemyTowerRange) + WorldFacts.HeroRadius(t.HeroRadius);
}

/** The enemy tower's attack range alone (read from the game; 700 when the read fails). */
export function TowerAttackRange(): number {
    return WorldFacts.TowerAttackRange(700);
}

export function Settings(): LaneSettings {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().Lane) as LaneSettings;
    return cached;
}

export function ResetSettings(): void {
    cached = undefined;
}

export function IsEnabled(): boolean {
    return Config.IsFeatureEnabled("Lane");
}

export function IsOn(flag: LaneFlag): boolean {
    return IsEnabled() && Settings()[flag] === true;
}

export function IsActive(): boolean {
    if (!IsEnabled()) return false;
    for (const flag of CONSUMER_FLAGS) if (Settings()[flag] === true) return true;
    return false;
}

export function GateFor(tech: Technique): number {
    const gate = GATE_OF[tech];
    return gate === undefined ? 0 : (Settings().Gates as Record<string, number>)[gate] ?? 0;
}

export function Knows(tech: Technique, skill: number): boolean {
    return IsOn(FLAG_OF[tech]) && skill >= GateFor(tech);
}

function clamp01(v: number): number {
    return v < 0 ? 0 : v > 1 ? 1 : v;
}

export function Curve(name: CurveName, skill: number): number {
    const c = Settings().Curves[name];
    return c[0] + (c[1] - c[0]) * clamp01(skill);
}

/** Uniform [0, 1) and standard-normal draws: the SDK Skill model. */
export interface Rng {
    random: (this: void) => number;
    gauss: (this: void) => number;
}

let rngSource: ((this: void) => Rng | undefined) | undefined;

/**
 * Set by tasks.ts (which imports this module, so the source is injected rather than required): returns the SDK Skill
 * once the tasks bundle is loaded, else undefined. Without one, draws fall back to RandomFloat (tasks off).
 */
export function SetRng(source: ((this: void) => Rng | undefined) | undefined): void {
    rngSource = source;
}

function rng(): Rng | undefined {
    return rngSource !== undefined ? rngSource() : undefined;
}

export function Gauss(): number {
    const r = rng();
    if (r !== undefined) return r.gauss();
    const u1 = RandomFloat(1e-6, 1);
    const u2 = RandomFloat(1e-6, 1);
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

export function Jitter(skill: number): number {
    return Gauss() * Curve("JitterSigma", skill);
}

/** One uniform [0, 1) draw from the engine's Skill rng, or undefined without the tasks bundle (no host fallback). */
export function Draw(): number | undefined {
    const r = rng();
    return r !== undefined ? r.random() : undefined;
}

export function Roll(chance: number): boolean {
    const r = rng();
    return (r !== undefined ? r.random() : RandomFloat(0, 1)) < chance;
}

export function SkillOf(bot: Unit): number {
    return Profile.Get(bot).skill;
}

export interface LaneHelpers {
    GetPosition?: (this: void, unit: Unit) => number;
    IsInLaningPhase?: (this: void) => boolean;
    WillKillTarget?: (this: void, target: Unit, dmg: number, dmgType: number, delay: number) => boolean;
    GetAttackProDelayTime?: (this: void, attacker: Unit, target: Unit) => number;
    WeAreStronger?: (this: void, bot: Unit, radius: number) => boolean;
    NextPowerRuneTime?: (this: void) => number;
    IsValidHero?: (this: void, u: Unit) => boolean;
    IsSuspiciousIllusion?: (this: void, u: Unit) => boolean;
    CannotBeKilled?: (this: void, bot: Unit, target: Unit) => boolean;
    IsValidBuilding?: (this: void, u: Unit) => boolean;
    GetHP?: (this: void, u: Unit) => number;
    /** The hero's localised display name, or undefined when unknown. */
    HeroDisplayName?: (this: void, u: Unit) => string | undefined;
}

let helpers: LaneHelpers = {};

export function SetHelpers(h: LaneHelpers): void {
    helpers = h;
    phaseAt = undefined;
}

export function Helpers(): LaneHelpers {
    return helpers;
}

export function PositionOf(unit: Unit): number | undefined {
    return helpers.GetPosition !== undefined ? helpers.GetPosition(unit) : undefined;
}

let phaseAt: number | undefined;
let phaseBot: Unit | undefined;
let phaseValue = false;

/**
 * OHA's answer, asked once per frame and bot: its helper scans every allied unit on each call (J.IsModeTurbo looks for the
 * courier) and reads the calling bot's net worth after the time floor, and our gates asked about a million times in ten
 * minutes (perf probe 16/11/2026: the largest single cost in our script).
 */
export function InLaningPhase(): boolean {
    const now = DotaTime();
    // OHA's own check reads raw DotaTime(); a scenario clock offset makes our phase reads use Config.Now() instead.
    const ours = Config.Now();
    if (ours !== now) return ours < 600;
    if (helpers.IsInLaningPhase === undefined) return now < 600;
    const bot = GetBot !== undefined ? GetBot() : undefined;
    if (now === phaseAt && bot === phaseBot) return phaseValue;
    phaseValue = helpers.IsInLaningPhase();
    phaseAt = now;
    phaseBot = bot;
    return phaseValue;
}
