/**
 * Lane fight configuration (task 11): trading and kill setups with imperfect cooldown memory.
 * Every tunable lives in DEFAULTS; Settings() deep-merges Customize.Humaniser.LaneFight over it.
 * Curves are [low, high] pairs read as low + (high - low) * skill.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";

export type LaneFightFlag = "Memory" | "Trade" | "Kill" | "CallKills";
export type CurveName =
    | "RememberUlt"
    | "RememberKey"
    | "RememberOther"
    | "TimingError"
    | "ForgetWindow"
    | "ShareLoss"
    | "Notice"
    | "BurstError"
    | "AbortNotice"
    | "SyncDelay";

export const DEFAULTS = {
    Enable: true,
    Memory: true,
    Trade: true,
    Kill: true,
    CallKills: true,
    // 'all' | 'allies' (bots whose team has a human) | 'enemies' (bots whose team has none)
    Teams: "all" as string,
    ShareMemory: false,
    // Install cast callbacks for exact cast events; false reads cooldowns and levels instead (Task 1 probe pending).
    UseCastCallback: false,
    PollInterval: 0.1,
    KillCheckEvery: 0.5,
    WindowReadEvery: 0.25,
    KeyThreatsWindow: 0.5,
    BlinkJump: 600,
    LevelSpikeMin: 10,
    LevelSpikeMax: 15,
    OutOfPosition: 400,
    TradeDuration: 2.5,
    TradeHits: 3,
    CommitMax: 8,
    StartHP: 0.5,
    StartMaxRetreat: 0.7,
    StopHP: 0.3,
    FogGrace: 1.0,
    TradeFloor: 0.75,
    CommitFloor: 0.82,
    TowerOverride: 1.3,
    FollowMargin: 0.8,
    Overwhelming: 1.5,
    SoloSkill: 0.7,
    CallCooldown: 30,
    Curves: {
        RememberUlt: [0.6, 0.98],
        RememberKey: [0.35, 0.9],
        RememberOther: [0.1, 0.6],
        TimingError: [0.35, 0.05],
        ForgetWindow: [20, 90],
        ShareLoss: [0.3, 0.05],
        Notice: [0.3, 0.9],
        BurstError: [0.3, 0.05],
        AbortNotice: [0.8, 0.15],
        SyncDelay: [0.6, 0.1],
    } as Record<string, number[]>,
};

export type LaneFightSettings = typeof DEFAULTS;

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

let cached: LaneFightSettings | undefined;

export function Settings(): LaneFightSettings {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().LaneFight) as LaneFightSettings;
    return cached;
}

export function ResetSettings(): void {
    cached = undefined;
}

function isEnabled(): boolean {
    return Config.IsFeatureEnabled("LaneFight");
}

export function IsOn(flag: LaneFightFlag): boolean {
    return isEnabled() && Settings()[flag] === true;
}

export function IsActive(): boolean {
    if (!isEnabled()) return false;
    const s = Settings();
    return s.Memory === true || s.Trade === true || s.Kill === true;
}

function clamp01(v: number): number {
    return v < 0 ? 0 : v > 1 ? 1 : v;
}

export function Curve(name: CurveName, skill: number): number {
    const c = Settings().Curves[name];
    return c[0] + (c[1] - c[0]) * clamp01(skill);
}

export function AppliesTo(bot: Unit): boolean {
    const teams = Settings().Teams;
    if (teams === "allies") return Difficulty.IsAllyOfHuman(bot);
    if (teams === "enemies") return !Difficulty.IsAllyOfHuman(bot);
    return true;
}
