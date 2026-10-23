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
    // A MISSING read this soon after a power spawn is not taken as "spawned elsewhere".
    MidRuneSpawnGrace: 1,
    // rune_skip telemetry: a mid's rune desire below this within this many seconds of a power spawn.
    MidRuneSkipDesire: 0.3,
    MidRuneSkipWindow: 10,
    BusyHP: 0.5,
    BusyMana: 0.3,
    HumanPingWindow: 30,
    // Pings this close to the lane front count as being on the lane.
    LanePingRadius: 2000,
    // A camp job due within this many seconds makes the bot busy.
    BusyJobLead: 30,
    SpareEq: -0.2,
    SparePartnerHP: 0.6,
    SpareCreepAggro: 3,
    SpareSeenWithin: 5,
    Pos5PartnerHP: 0.75,
    Pos5EnemyRadius: 1200,
    // A partner under this HP fraction with a visible enemy within attack range plus SpareKillMargin is in kill position.
    SpareKillHP: 0.5,
    SpareKillMargin: 300,
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
    // Straight-line distance to the spot times this is the travel estimate.
    PathFactor: 1.2,
    // A support whose leave time is further in the past than this can no longer make the spawn.
    LateSlack: 2,
    // A decided rotation re-checks LaneCanSpare until this long after its leave time (the first part of the walk).
    RecheckUntilWalk: 4,
    // A rotation stays active this long after the spawn.
    RotateLinger: 5,
    RotateFloor: 0.7,
    // Standing this close to the spot before the spawn is a deliberate wait (Intent.Hold).
    RotateHoldRadius: 300,
    // A rotating support at its spawned rune leaves it for our mid (within ContestMidRadius of the spot). It takes it
    // with an enemy hero within RuneHoldEnemyRadius, with our mid not coming RuneHoldGrace s after the spawn, or at
    // RuneHoldMax; the rotation stays active up to RuneHoldMax while the rune lies there.
    RuneHoldEnemyRadius: 1200,
    RuneHoldGrace: 3,
    RuneHoldMax: 15,
    // The contest check starts this many seconds before the planned arrival.
    ContestFrom: 6,
    // Our mid counts towards a contest within this distance of the spot.
    ContestMidRadius: 2500,
    // The mid's contest desire applies from this many seconds before the spawn.
    MidContestFrom: 10,
    AloneMissing: 4,
    LaneMissing: 6,
    OffsetMin: 150,
    OffsetMax: 300,
    RetreatScaleMax: 1.3,
    // Caution scales retreat only while the bot is threatened: hit by a hero within ThreatHitWindow s, under ThreatHP,
    // or targeted by an enemy tower. Otherwise it only steps the lane position back and suppresses trades.
    ThreatHitWindow: 2,
    ThreatHP: 0.5,
    SkillAmount: { Low: 0.5, High: 1.0 } as LerpPair,
    MissingCooldown: 30,
    // An alone laner's caution: AloneLevel against one enemy laner, plus AloneLevelPerEnemy per extra one (capped at 1).
    AloneLevel: 0.5,
    AloneLevelPerEnemy: 0.25,
    // Trades are suppressed from this caution level up.
    SuppressLevel: 0.5,
    // An enemy unseen longer than this is no longer counted as missing (it has left the lane, not hidden near it).
    MissingMaxAge: 60,
    // SuppressTrades lets trades through when WeAreStronger within this radius.
    CautionStrongerRadius: 1200,
    // A mid callout is skipped when the counterplay already noticed mid_missing this recently.
    MidMissingSignalWindow: 30,
    TpRadius: 1600,
    TpLinger: 2,
    TpSetupSkill: 0.7,
    TpSetupDistance: 600,
    // A setup point is pushed back toward our tower until it is this far from a live enemy T1 (tower range plus margin).
    TpTowerClear: 850,
    // Radius for the WeAreStronger check that picks setup over backing off.
    TpStrongerRadius: 1600,
    // Enemy TPs are read once per team per this many seconds.
    TpRefresh: 0.25,
    WardFrom: 150,
    WardTo: 270,
    WardChance: { Low: 0.4, High: 0.95 } as LerpPair,
    // An allied observer this close to the gank anchor already covers the lane.
    WardCoverRadius: 1600,
    // Only a spot this close to the gank anchor is worth the early ward; otherwise the ward mode chooses.
    WardAnchorRadius: 1500,
    // The allied-ward list is read once per team per this many seconds.
    WardScanPeriod: 5,
    WardFloor: 0.6,
    // A lane-ward pick counts as live (the claim keeps posting) this long after the ward mode last asked.
    WardLive: 1,
    // A planted lane ward covers the lane this long (the observer ward's lifetime).
    WardLifetime: 360,
    SupportLevel: 6,
    SupportFrom: 360,
    SupportTo: 480,
    LostWindow: 240,
    LostDeaths: 2,
    LostLevelGap: 2,
    SuggestCooldown: 60,
    // Enemy hero seen within this long counts as present near our jungle camp.
    JungleSeenWindow: 3,
    JungleCampRadius: 2500,
    // A human ping this close to the bot after a lost-lane suggestion is taken as an answer.
    LostPingRadius: 1500,
    // The human partner must be away from the lane this long after a suggestion before the bot leaves.
    AbsentHold: 10,
    // Laning mode cap once a bot's laning has ended.
    LaningCap: 0.3,
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
