/**
 * Per-bot human profile: reaction timing and error characteristics derived from skill.
 * Created lazily per player ID; the personal multiplier is rolled once so each bot feels consistent.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";

export type DelayKind = "notice" | "react" | "ping" | "chat";

export interface HumanProfile {
    skill: number;
    personal: number;
    noticeBase: number;
    reactBase: number;
    pingBase: number;
    chatBase: number;
    jitter: number;
    lapseChance: number;
    aimError: number;
    /** Allies only: 1 = never takes a human's farm, 0 = plays like a normal teammate. */
    deference: number;
    refreshedAt: number;
}

const REFRESH_SECONDS = 5;
const profiles: Record<number, HumanProfile> = {};

function lerp(low: number, high: number, skill: number): number {
    return low + (high - low) * skill;
}

function fill(profile: HumanProfile, skill: number): void {
    const p = Config.Get().Profile;
    profile.skill = skill;
    profile.noticeBase = lerp(p.NoticeLow, p.NoticeHigh, skill) * profile.personal;
    profile.reactBase = math.max(p.MinReact, lerp(p.ReactLow, p.ReactHigh, skill) * profile.personal);
    profile.pingBase = lerp(p.PingLow, p.PingHigh, skill) * profile.personal;
    profile.chatBase = lerp(p.ChatLow, p.ChatHigh, skill) * profile.personal;
    profile.jitter = lerp(p.JitterLow, p.JitterHigh, skill);
    profile.lapseChance = lerp(p.LapseLow, p.LapseHigh, skill);
    profile.aimError = lerp(p.AimErrorLow, p.AimErrorHigh, skill);
    profile.deference = lerp(1, 0, skill);
}

export function Get(bot: Unit): HumanProfile {
    const pid = bot.GetPlayerID();
    let profile = profiles[pid];
    const now = GameTime();
    if (profile === undefined) {
        const p = Config.Get().Profile;
        profile = {
            skill: 0,
            personal: RandomFloat(p.PersonalMin, p.PersonalMax),
            noticeBase: 0,
            reactBase: 0,
            pingBase: 0,
            chatBase: 0,
            jitter: 0,
            lapseChance: 0,
            aimError: 0,
            deference: 0,
            refreshedAt: now,
        };
        profiles[pid] = profile;
        fill(profile, Difficulty.GetSkill(bot));
    } else if (now - profile.refreshedAt >= REFRESH_SECONDS) {
        profile.refreshedAt = now;
        fill(profile, Difficulty.GetSkill(bot));
    }
    return profile;
}

function baseFor(profile: HumanProfile, kind: DelayKind): number {
    if (kind === "notice") return profile.noticeBase;
    if (kind === "react") return profile.reactBase;
    if (kind === "ping") return profile.pingBase;
    return profile.chatBase;
}

/** A human-like delay in seconds: base ± jitter, with an occasional "wasn't looking" lapse. */
export function SampleDelay(bot: Unit, kind: DelayKind): number {
    const profile = Get(bot);
    const p = Config.Get().Profile;
    let delay = baseFor(profile, kind) * (1 - profile.jitter / 2 + RandomFloat(0, profile.jitter));
    if (RandomFloat(0, 1) < profile.lapseChance) delay += RandomFloat(p.LapseMinExtra, p.LapseMaxExtra);
    if (kind === "react") delay = math.max(p.MinReact, delay);
    return delay;
}
