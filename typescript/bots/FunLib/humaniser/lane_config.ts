/**
 * Lane management configuration and shared helpers (task 07).
 * Every tunable lives in DEFAULTS; Settings() deep-merges Customize.Humaniser.Lane over it.
 * jmz_func cannot be required from humaniser modules, so J.* helpers arrive through SetHelpers.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Profile from "bots/FunLib/humaniser/profile";

export type LaneFlag =
    | "Plan"
    | "Block"
    | "FullPull"
    | "HalfPull"
    | "StackPull"
    | "AggroPull"
    | "Freeze"
    | "Shove"
    | "Stack"
    | "Harass"
    | "Mid"
    | "CounterPlay"
    | "Telegraph"
    | "CampBlock";
export type Technique = "block" | "full_pull" | "half_pull" | "stack_pull" | "aggro_pull" | "freeze" | "shove" | "stack";
export type CurveName =
    | "JitterSigma"
    | "AttemptRate"
    | "PathNoise"
    | "StackAttempt"
    | "HarassCapitalise"
    | "CounterNotice"
    | "PlanMisread"
    | "CoverAbsentCore"
    | "DoubleDraw";

export const DEFAULTS = {
    Enable: true,
    OwnLaningThink: "allies" as string,
    Plan: true,
    Block: true,
    FullPull: true,
    HalfPull: true,
    StackPull: true,
    AggroPull: true,
    Freeze: true,
    Shove: true,
    Stack: true,
    Harass: true,
    Mid: true,
    CounterPlay: true,
    Telegraph: true,
    CampBlock: false,
    Gates: {
        Block: 0.3,
        FullPull: 0.3,
        HalfPull: 0.6,
        StackPull: 0.75,
        AggroPull: 0.5,
        Freeze: 0.7,
        Shove: 0.4,
        SoloCampJob: 0.6,
        MultiStackAncients: 0.7,
        CampBlock: 0.6,
        HarassPosition: 0.6,
        RandomHarass: 0.5,
    },
    Curves: {
        JitterSigma: [1.5, 0.2],
        AttemptRate: [0.15, 0.85],
        PathNoise: [150, 20],
        StackAttempt: [0.2, 0.9],
        HarassCapitalise: [0.25, 0.85],
        CounterNotice: [0.2, 0.8],
        PlanMisread: [0.3, 0.05],
        CoverAbsentCore: [0.3, 0.9],
        DoubleDraw: [0.2, 0.0],
    } as Record<string, number[]>,
    Eq: { Safe: -0.7, Off: -0.7, Mid: -0.1, MidPreRune: 0.15, XpDenyWeight: 0.2 },
    Planner: { FullPullBelow: -0.5, SmallDriftBelow: -0.2, AggroCorrectBelow: -0.15, LargeWaveMargin: 2, AggroStepEq: 0.15 },
    Timing: {
        SnapshotRefresh: 0.5,
        WaveCycle: 30,
        AggroWindow: 3.0,
        AggroCooldown: 2.3,
        WalkBack: 1.5,
        BlockEnd: 30,
        BlockLostSec: 2,
        StackMoveFrom: 45,
        StackExitUntil: 1.0,
        StackOutcomeAt: 2,
        StackOutcomeUntil: 5,
        StackEarlyBefore: 52,
        StackLateAfter: 57,
        StackAssumedFrom: 53,
        StackAssumedTo: 56,
        JobDesire: 0.7,
        ContestDesire: 0.65,
        ContestMax: 10,
        ContestAttackGap: 2.5,
        JobStartSlack: 3,
        JobStartLate: 2,
        JobMaxAfterAggro: 15,
        JobUpcoming: 10,
        MaxTravel: 12,
        WatchSec: 8,
        WatchEvery: 0.25,
        PullPeriod: 60,
        HalfPullLater: 2,
        NoCampAfter: 1,
        AggroConfirm: 2,
        DoublePullReach: 8,
        ShoveMaxSec: 8,
        PingHandsOff: 30,
        PlanSustain: 5,
        PlanMinDwell: 15,
        CoreYieldStagger: 1.5,
        HumanPullWindow: 6,
        CounterUnseen: 4,
        CounterPullWindow: 6,
        CounterWaveLate: 5,
        CounterSignalTTL: 20,
        PunishGap: 2,
        PunishFor: 6,
        PathSafeSeen: 5,
        MidRuneShoveLookahead: 25,
        RuneContestAfter: 10,
        DropRangedDenyFor: 20,
        RuneContestDesire: 0.6,
        MarkedStackFor: 120,
        StackWatchFrom: 50,
        StackWatchTo: 58,
        StackOutsideUntil: 3,
        CampBlockFrom: 50,
        CampBlockTo: 58,
        StackedCampSeen: 5,
        CounterForgetAfter: 120,
        PreRuneMin: 15,
        PreRuneMax: 20,
        RandomHarassMin: 4,
        RandomHarassMax: 8,
        LowSkillHarassExtra: 1.5,
        AggroDanceBack: 1,
        BlockNoiseEvery: 1,
        CampBlockCooldown: 180,
        PullTelegraphLead: 5,
        PullTelegraphCooldown: 60,
        StackTelegraphCooldown: 120,
        CounterTelegraphCooldown: 60,
        ShoveTelegraphCooldown: 60,
        ExposureSeen: 3,
    },
    Thresholds: {
        CoreAbsentDist: 1200,
        CoreBusyHP: 0.6,
        CoreBusyDamageMult: 1.3,
        PartnerMinHP: 0.4,
        PartnerDangerEnemies: 2,
        PartnerDangerRadius: 1200,
        SupportNearFront: 800,
        StableEnemyRadius: 1200,
        StableSeenWithin: 3,
        StableMinHP: 0.5,
        FullPullMin: 0.8,
        HalfPullMin: 0.3,
        HalfPullMax: 0.6,
        HarassExtraRange: 100,
        AggroDanceCreeps: 3,
        AggroDanceRadius: 500,
        HarassTowerLevel: 6,
        HarassTowerTargetHP: 0.3,
        EnemyTowerRange: 850,
        ShoveMinHP: 0.5,
        ShoveDoneCreeps: 1,
        TowerSwapAllyHP: 0.6,
        TowerSwapBotHP: 0.6,
        FreezeDriftMargin: 0.2,
        MidTowerEq: 0.8,
        FreezeCoreEqMax: -0.3,
        MidMissingEq: -0.6,
        FreezeSuspectEq: 0.6,
        ThinWaveMargin: 2,
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
        AggroDrawExtra: 200,
        AggroWalkBack: 300,
        AggroWalkMax: 400,
        BlockAhead: 120,
        BlockSide: 50,
        BlockStart: 1500,
        BlockLost: 400,
        BlockContact: 700,
        TowerAggro: 900,
        TowerExitMargin: 100,
        Zone: 900,
        ZoneOffset: 150,
        HoldMinBack: 250,
        HarassStandBack: 50,
        LowHpCreep: 700,
        StepBackCreeps: 700,
        StepBackEps: 50,
        NeutralSearch: 700,
        StandOffset: 150,
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
        PullCampLastSeen: 1500,
        PathSafe: 1500,
        StackedCampSafe: 1500,
        ContestReach: 1200,
        CounterNeutralScan: 1600,
        MidFront: 1200,
        MidHuman: 1500,
        LaneActive: 2500,
        PullPathEdge: 150,
        BoxMargin: 300,
        AggroDanceStep: 250,
        Stronger: 1200,
        ApproachExtrapolate: 0.5,
    },
    Infer: { ShoveHits: 4, FreezeDenies: 2, FreezeEqMax: -0.5, HoldSignals: 2, ShoveHitDamageMult: 1.3 },
    Camps: { HalfMeetOffset: 500, PullCampMaxTowerDist: 2500, ReplayMatchRadius: 600, LaneSampleStep: 0.005 },
    Orders: { FreezeShove: 90, PullNoPull: 120, Stack: 60 },
    // Idle-poke gates for bots 04 does not own; 04-owned bots read AllyLastHit.Settings() instead.
    HarassIdle: { IdleWindow: 1.2, IdleExtraRange: 300, IdleMinHP: 0.5, TowerAvoidRange: 850 },
};

export type LaneSettings = typeof DEFAULTS;

const FLAG_OF: Record<Technique, LaneFlag> = {
    block: "Block",
    full_pull: "FullPull",
    half_pull: "HalfPull",
    stack_pull: "StackPull",
    aggro_pull: "AggroPull",
    freeze: "Freeze",
    shove: "Shove",
    stack: "Stack",
};

const GATE_OF: Record<Technique, string | undefined> = {
    block: "Block",
    full_pull: "FullPull",
    half_pull: "HalfPull",
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
    "HalfPull",
    "StackPull",
    "AggroPull",
    "Freeze",
    "Shove",
    "Stack",
    "Harass",
    "Mid",
    "CounterPlay",
    "CampBlock",
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

export function Gauss(): number {
    const u1 = RandomFloat(1e-6, 1);
    const u2 = RandomFloat(1e-6, 1);
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
}

export function Jitter(skill: number): number {
    return Gauss() * Curve("JitterSigma", skill);
}

export function Roll(chance: number): boolean {
    return RandomFloat(0, 1) < chance;
}

export function SkillOf(bot: Unit): number {
    return Profile.Get(bot).skill;
}

export function OwnLaningMode(): "allies" | "all" | "off" {
    const mode = Settings().OwnLaningThink;
    return mode === "allies" || mode === "all" ? mode : "off";
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
    IsValidBuilding?: (this: void, u: Unit) => boolean;
    GetHP?: (this: void, u: Unit) => number;
}

let helpers: LaneHelpers = {};

export function SetHelpers(h: LaneHelpers): void {
    helpers = h;
}

export function Helpers(): LaneHelpers {
    return helpers;
}

export function PositionOf(unit: Unit): number | undefined {
    return helpers.GetPosition !== undefined ? helpers.GetPosition(unit) : undefined;
}

export function InLaningPhase(): boolean {
    return helpers.IsInLaningPhase !== undefined ? helpers.IsInLaningPhase() : DotaTime() < 600;
}
