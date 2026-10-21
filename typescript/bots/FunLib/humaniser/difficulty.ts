/**
 * Difficulty resolver: combines Valve lobby difficulty and FretBots difficulty into skill in [0,1].
 *
 * FretBots runs in a separate game-mode VScript context, so the bot side cannot read its settings directly.
 * Sources, best first:
 *   1. Config override (FretBridge.FretBotsLevelOverride).
 *   2. Bridge modifier stack counts, only if FretBridge.BridgeModifier is configured (see FretBots/Settings.lua).
 *   3. Chat mirror: repeats FretBots' vote parsing (plain numbers typed during the vote windows).
 *   4. Customize.Fretbots.Default_Difficulty / Default_Ally_Scale.
 * FretBots is considered active when it has applied its marker modifier to this bot (see IsFretBotsMarked).
 */
import { GameState, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Chat from "bots/FunLib/humaniser/chat";
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");

export interface FretInfo {
    active: boolean;
    level: number; // 0..10
    allyScale: number; // 0..1, applies to the team with humans
    source: "override" | "modifier" | "chat" | "default" | "inactive";
}

const SKILL_CACHE_SECONDS = 5;
// FretBots gives every bot this at game start (FretBots/modifiers/Modifier.lua, ApplySpecialModifiers).
// The same modifier can come from a level 10+ talent, so the check is only trusted early and at low level.
const FRET_MARKER_MODIFIER = "modifier_special_bonus_cooldown_reduction";
const FRET_MARKER_MAX_LEVEL = 9;
const FRET_MARKER_MAX_TIME = 300;
// FretBots' ally-scale vote runs for ~30 s after the horn (Settings.voteEndTime).
const ALLY_VOTE_WINDOW = 40;
const FRET_MAX_LEVEL = 10;

const valveDifficultyToSkill = (): Record<number, number> => ({
    [DIFFICULTY_PASSIVE]: 0,
    [DIFFICULTY_EASY]: 0.25,
    [DIFFICULTY_MEDIUM]: 0.5,
    [DIFFICULTY_HARD]: 0.75,
    [DIFFICULTY_UNFAIR]: 1,
});

let fretMarkerSeen = false;
const difficultyVotes: Record<number, number> = {};
const allyScaleVotes: Record<number, number> = {};

interface SkillCacheEntry {
    skill: number;
    time: number;
}
const skillCache: Record<number, SkillCacheEntry> = {};

function clamp(x: number, lo: number, hi: number): number {
    return x < lo ? lo : x > hi ? hi : x;
}

function average(votes: Record<number, number>): number | undefined {
    let total = 0;
    let count = 0;
    for (const [, v] of pairs(votes)) {
        total += v;
        count++;
    }
    return count > 0 ? total / count : undefined;
}

function onChatForVotes(this: void, msg: Chat.ChatMessage): void {
    const value = tonumber(msg.text);
    if (value === undefined) return;
    const state = GetGameState();
    if (state < GameState.GameInProgress) {
        if (difficultyVotes[msg.pid] === undefined) difficultyVotes[msg.pid] = clamp(value, 0, FRET_MAX_LEVEL);
    } else if (DotaTime() < ALLY_VOTE_WINDOW) {
        if (allyScaleVotes[msg.pid] === undefined) allyScaleVotes[msg.pid] = clamp(value, 0, 1);
    }
}

let subscribed = false;
/** Must run before voting so the mirror sees the votes; called from the humaniser tick. */
export function Init(): void {
    if (subscribed) return;
    subscribed = true;
    Chat.Subscribe("difficulty-vote-mirror", onChatForVotes);
}

function readBridgeModifier(bot: Unit, name: string): [number, number] | undefined {
    const index = bot.GetModifierByName(name);
    if (index === undefined || index < 0) return undefined;
    const stacks = bot.GetModifierStackCount(index);
    // Encoding written by FretBots/Settings.lua: difficulty*10 + allyScale*100*1000 (both rounded).
    const level = (stacks % 1000) / 10;
    const allyScale = math.floor(stacks / 1000) / 100;
    return [level, allyScale];
}

function IsFretBotsMarked(bot: Unit): boolean {
    if (fretMarkerSeen) return true;
    if (DotaTime() > FRET_MARKER_MAX_TIME || bot.GetLevel() > FRET_MARKER_MAX_LEVEL) return false;
    if (bot.HasModifier(FRET_MARKER_MODIFIER)) fretMarkerSeen = true;
    return fretMarkerSeen;
}

export function GetFret(bot: Unit): FretInfo {
    const cfg = Config.Get();
    const override = cfg.FretBridge.FretBotsLevelOverride;
    const defaults = Customize.Fretbots ?? {};
    const defaultLevel: number = defaults.Default_Difficulty ?? 2;
    const defaultAllyScale: number = defaults.Default_Ally_Scale ?? 0.5;

    if (override !== undefined) {
        return { active: true, level: clamp(override, 0, FRET_MAX_LEVEL), allyScale: defaultAllyScale, source: "override" };
    }
    if (cfg.FretBridge.BridgeModifier !== undefined) {
        const bridged = readBridgeModifier(bot, cfg.FretBridge.BridgeModifier);
        if (bridged !== undefined) return { active: true, level: bridged[0], allyScale: bridged[1], source: "modifier" };
    }
    if (!IsFretBotsMarked(bot)) return { active: false, level: 0, allyScale: 1, source: "inactive" };

    const votedLevel = average(difficultyVotes);
    const votedScale = average(allyScaleVotes);
    if (votedLevel !== undefined) {
        return { active: true, level: votedLevel, allyScale: votedScale ?? defaultAllyScale, source: "chat" };
    }
    return { active: true, level: defaultLevel, allyScale: votedScale ?? defaultAllyScale, source: "default" };
}

export function GetValveSkill(bot: Unit): number {
    return valveDifficultyToSkill()[bot.GetDifficulty()] ?? 0.5;
}

/** True when the bot's team has at least one human player. */
export function IsAllyOfHuman(bot: Unit): boolean {
    for (const pid of GetTeamPlayers(bot.GetTeam())) {
        if (!IsPlayerBot(pid)) return true;
    }
    return false;
}

function computeSkill(bot: Unit): number {
    const cfg = Config.Get();
    if (cfg.SkillOverride !== undefined) return clamp(cfg.SkillOverride, 0, 1);
    const valve = GetValveSkill(bot);
    const fret = GetFret(bot);
    if (!fret.active) return valve;
    let fretSkill = fret.level / FRET_MAX_LEVEL;
    // FretBots scales ally bots' bonuses by allyScale; their effective strength follows suit.
    if (IsAllyOfHuman(bot)) fretSkill = fretSkill * fret.allyScale;
    const weightTotal = cfg.ValveWeight + cfg.FretWeight;
    if (weightTotal <= 0) return valve;
    return clamp((cfg.ValveWeight * valve + cfg.FretWeight * fretSkill) / weightTotal, 0, 1);
}

/** Skill in [0,1], cached per bot for 5 s. */
export function GetSkill(bot: Unit): number {
    const pid = bot.GetPlayerID();
    const now = GameTime();
    const entry = skillCache[pid];
    if (entry !== undefined && now - entry.time < SKILL_CACHE_SECONDS) return entry.skill;
    const skill = computeSkill(bot);
    skillCache[pid] = { skill, time: now };
    return skill;
}
