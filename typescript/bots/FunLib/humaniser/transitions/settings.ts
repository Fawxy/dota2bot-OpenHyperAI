/**
 * Lane safety and laning-phase transitions (task 12): configuration.
 * Every tunable lives in DEFAULTS; Get() deep-merges Customize.Humaniser.Transitions over it.
 * Lerp pairs are { Low, High } and interpolate on the bot's skill (Low at skill 0, High at skill 1).
 */
import * as Config from "bots/FunLib/humaniser/config";

export type TransitionFlag = "MidRunes" | "Rotation" | "Caution" | "Teleports" | "LaneWard" | "Phase" | "LostLane";
export interface LerpPair {
    Low: number;
    High: number;
}

export const DEFAULTS = {
    Enable: true,
    MidRunes: true,
    Rotation: true,
    Caution: true,
    Teleports: true,
    LaneWard: true,
    Phase: true,
    LostLane: true,
    Refresh: 0.5,
    MidRuneFloor: 0.6,
    // Seconds before a power spawn: only power spots count for the mid / the floor claim starts.
    MidRuneFocus: 20,
    MidRuneLead: 15,
    MidRuneRadius: 3500,
    // After a power spawn, an unseen spot is still worth checking for this long.
    MidRuneCheckWindow: 15,
    // rune_skip telemetry: a mid's rune desire below this within this many seconds of a power spawn.
    MidRuneSkipDesire: 0.3,
    MidRuneSkipWindow: 10,
    BusyHP: 0.5,
    BusyMana: 0.3,
    HumanPingWindow: 30,
    SpareEq: -0.2,
    SparePartnerHP: 0.6,
    SpareCreepAggro: 3,
    SpareSeenWithin: 5,
    Pos5PartnerHP: 0.75,
    Pos5EnemyRadius: 1200,
    // Enemies last seen farther than this from the lane front are not counted as missing laners.
    SpareLaneRadius: 3500,
    DecideFrom: 25,
    DecideTo: 20,
    ArriveLead: 4,
    RotateChance: { Low: 0.3, High: 0.9 } as LerpPair,
    ArriveSigma: { Low: 6, High: 1 } as LerpPair,
    // Skips LaneCanSpare, never IsBusy.
    MistakeChance: { Low: 0.15, High: 0 } as LerpPair,
    MidSupportRadius: 1500,
    MidContestDesire: 0.55,
    ContestRadius: 1800,
    ContestSeenWithin: 5,
    Pos5ContestEnemies: 2,
    ChatCooldown: 60,
    AloneMissing: 4,
    LaneMissing: 6,
    OffsetMin: 150,
    OffsetMax: 300,
    RetreatScaleMax: 1.3,
    AttackScaleMin: 0.7,
    SkillAmount: { Low: 0.5, High: 1.0 } as LerpPair,
    MissingCooldown: 30,
    TpRadius: 1600,
    TpLinger: 2,
    TpSetupSkill: 0.7,
    TpSetupDistance: 600,
    WardFrom: 150,
    WardTo: 270,
    WardChance: { Low: 0.4, High: 0.95 } as LerpPair,
    SupportLevel: 6,
    SupportFrom: 360,
    SupportTo: 480,
    LostWindow: 240,
    LostDeaths: 2,
    LostLHRatio: 0.4,
    LostLevelGap: 2,
    // Placeholder until minute 10.
    ExpectedLHPerMin: { Low: 3, High: 7 } as LerpPair,
    SuggestCooldown: 60,
};

export type TransitionSettings = typeof DEFAULTS;

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" ? merge(d, v) : v;
    }
    return result;
}

let cached: TransitionSettings | undefined;

export function Get(): TransitionSettings {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().Transitions) as TransitionSettings;
    return cached;
}

export function ResetSettings(): void {
    cached = undefined;
}

export function IsActive(): boolean {
    return Config.IsFeatureEnabled("Transitions");
}

export function IsOn(flag: TransitionFlag): boolean {
    return IsActive() && Get()[flag] === true;
}

export function Lerp(pair: LerpPair, skill: number): number {
    const s = skill < 0 ? 0 : skill > 1 ? 1 : skill;
    return pair.Low + (pair.High - pair.Low) * s;
}
