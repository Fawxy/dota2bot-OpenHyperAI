/**
 * Last-hit and deny accuracy that scales with skill (task 10).
 *
 * WillKill wraps the "will this attack kill it" check. Each bot rolls, once per creep, a damage-estimate error
 * eps in [-1, 1] and whether it even tries for that creep. Both are kept until the creep is gone, so GetDesire,
 * Think and the move-to lookahead all agree and a mode desire built on the answer does not flicker under
 * intent arbitration (task 09). eps is scaled by ErrorWidth at use, so pressure widens the error on creeps
 * rolled before it began. Positive eps overestimates damage (an early swing, the creep survives); negative
 * eps underestimates it (a late swing, someone else takes the creep).
 *
 * Skill 1.0, a disabled feature, and (with RequireOwnedLaning) a bot on Valve's laning all get the upstream
 * predicate untouched.
 *
 * jmz_func cannot be required from here (it requires the humaniser), so WillKillTarget is injected.
 */
import { DamageType, GameState, Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as Trainer from "bots/FunLib/humaniser/trainer/trainer";

export const DEFAULTS = {
    RequireOwnedLaning: true,
    ErrorLow: 0.15,
    ErrorHigh: 0.02,
    AttemptLow: 0.75,
    AttemptHigh: 0.98,
    // Denies take more attention, so low skill denies much less.
    DenyAttemptLow: 0.35,
    DenyAttemptHigh: 0.9,
    PressureMult: 1.5,
    PressureSeconds: 2,
    RangedPrioritySkill: 0.6,
};

export type LastHitSkillSettings = typeof DEFAULTS;

export interface Helpers {
    WillKillTarget?: (this: void, target: Unit, dmg: number, dmgType: number, delay: number) => boolean;
}

type CsUnit = Unit & { GetLastHits(): number; GetDenies(): number };

interface CreepEntry {
    eps: number;
    attempt: boolean;
    /** Set by NoteAttempt once the bot issues a swing; a kill check alone (desire, lookahead) is not an attempt. */
    attempted: boolean;
    isDeny: boolean;
}

let helpers: Helpers = {};
let settings: LastHitSkillSettings | undefined;
const entriesByPlayer: Record<number, LuaTable<Unit, CreepEntry>> = {};
const ownedLaning: Record<number, boolean> = {};
const warned: Record<number, boolean> = {};
const widthCache: Record<number, { time: number; value: number }> = {};
const countsByPlayer: Record<number, { attempts: number; misses: number }> = {};
const tickedAt: Record<number, number> = {};
const countersAt: Record<number, { lastHits: number; denies: number }> = {};
const heroTargetAt: Record<number, number> = {};

const TICK_SECONDS = 0.25;

export function SetHelpers(h: Helpers): void {
    helpers = h;
}

export function Settings(): LastHitSkillSettings {
    if (settings === undefined) {
        const result: any = {};
        for (const [k, v] of pairs(DEFAULTS)) result[k] = v;
        const overrides: any = Config.Get().LastHitSkill ?? {};
        for (const [k, v] of pairs(overrides)) result[k] = v;
        settings = result as LastHitSkillSettings;
    }
    return settings;
}

function lerp(low: number, high: number, skill: number): number {
    return low + (high - low) * skill;
}

/** Records whether OHA owns this bot's laning Think(); warns once when the feature can do nothing for it. */
export function NoteLaningOwner(bot: Unit, owned: boolean): void {
    const pid = bot.GetPlayerID();
    ownedLaning[pid] = owned;
    if (owned || warned[pid] === true) return;
    if (!Config.IsFeatureEnabled("LastHitSkill") || !Settings().RequireOwnedLaning) return;
    warned[pid] = true;
    print(`[Humaniser] LastHitSkill: pid=${pid} ${bot.GetUnitName()} is on Valve laning; no effect (set Lane.OwnLaningThink='all')`);
}

export function IsActiveFor(bot: Unit): boolean {
    if (!Config.IsFeatureEnabled("LastHitSkill")) return false;
    if (Profile.Get(bot).skill >= 1) return false;
    // The trainer's self-test bot is its timing reference, so it must stay exact.
    if (Trainer.IsSelfTestBot(bot)) return false;
    return !Settings().RequireOwnedLaning || ownedLaning[bot.GetPlayerID()] === true;
}

/**
 * Hit by a hero, or attacked one, in the last PressureSeconds. Harassing is latched on time like the damage
 * window: turning to a creep must not end the pressure at once, or the last-hit answer would flip its own input.
 */
function isUnderPressure(bot: Unit): boolean {
    const seconds = Settings().PressureSeconds;
    const target = bot.GetAttackTarget();
    if (target !== null && target !== undefined && target.IsHero() && target.GetTeam() !== bot.GetTeam()) {
        heroTargetAt[bot.GetPlayerID()] = GameTime();
    }
    if (GameTime() - (heroTargetAt[bot.GetPlayerID()] ?? -math.huge) < seconds) return true;
    return bot.WasRecentlyDamagedByAnyHero(seconds);
}

/** The current error half-width e, pressure included. */
export function ErrorWidth(bot: Unit): number {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const hit = widthCache[pid];
    if (hit !== undefined && hit.time === now) return hit.value;
    const s = Settings();
    let e = lerp(s.ErrorLow, s.ErrorHigh, Profile.Get(bot).skill);
    if (isUnderPressure(bot)) e *= s.PressureMult;
    widthCache[pid] = { time: now, value: e };
    return e;
}

export function Upstream(creep: Unit, attackDamage: number, delay: number, isDeny: boolean): boolean {
    if (isDeny) return creep.GetHealth() <= attackDamage;
    return helpers.WillKillTarget !== undefined && helpers.WillKillTarget(creep, attackDamage, DamageType.Physical, delay);
}

function entriesFor(bot: Unit): LuaTable<Unit, CreepEntry> {
    const pid = bot.GetPlayerID();
    let entries = entriesByPlayer[pid];
    if (entries === undefined) {
        entries = setmetatable(new LuaTable<Unit, CreepEntry>(), { __mode: "k" });
        entriesByPlayer[pid] = entries;
    }
    return entries;
}

function counterOf(bot: Unit, isDeny: boolean): number {
    return isDeny ? (bot as CsUnit).GetDenies() : (bot as CsUnit).GetLastHits();
}

export function WillKill(bot: Unit, creep: Unit, attackDamage: number, delay: number, isDeny: boolean): boolean {
    if (!IsActiveFor(bot)) return Upstream(creep, attackDamage, delay, isDeny);
    const entries = entriesFor(bot);
    let entry = entries.get(creep);
    if (entry === undefined) {
        const s = Settings();
        const skill = Profile.Get(bot).skill;
        const rate = isDeny ? lerp(s.DenyAttemptLow, s.DenyAttemptHigh, skill) : lerp(s.AttemptLow, s.AttemptHigh, skill);
        const eps = RandomFloat(-1, 1);
        entry = { eps, attempt: RandomFloat(0, 1) < rate, attempted: false, isDeny };
        entries.set(creep, entry);
    }
    if (!entry.attempt) return false;
    return Upstream(creep, attackDamage * (1 + entry.eps * ErrorWidth(bot)), delay, isDeny);
}

/** Call where the bot issues its last-hit or deny swing on a creep WillKill judged killable. */
export function NoteAttempt(bot: Unit, creep: Unit): void {
    if (!IsActiveFor(bot)) return;
    const entry = entriesFor(bot).get(creep);
    if (entry !== undefined && entry.attempt) entry.attempted = true;
}

function isRangedOrSiege(creep: Unit): boolean {
    const name = creep.GetUnitName();
    return string.find(name, "ranged", 1, true)[0] !== undefined || string.find(name, "siege", 1, true)[0] !== undefined;
}

/** Which of several creeps killable together to take: the first, unless skill is high enough to prefer ranged. */
export function Choose(bot: Unit, killable: Unit[]): Unit | undefined {
    const skill = Profile.Get(bot).skill;
    if (IsActiveFor(bot) && skill > Settings().RangedPrioritySkill) {
        for (const creep of killable) if (isRangedOrSiege(creep)) return creep;
    }
    return killable[0];
}

export function Counts(bot: Unit): { attempts: number; misses: number } {
    const pid = bot.GetPlayerID();
    let counts = countsByPlayer[pid];
    if (counts === undefined) {
        counts = { attempts: 0, misses: 0 };
        countsByPlayer[pid] = counts;
    }
    return counts;
}

/**
 * Resolves creeps that are gone. Kills are credited per tick: attempts of a kind that resolve in this tick count
 * as hits up to how far the bot's last-hit (or deny) counter moved since the last tick, and the rest as misses.
 * A kill the bot made by other means (a spell) can hide one miss; dead creeps it never swung at are dropped.
 */
export function Tick(bot: Unit): void {
    // Before the horn there are no creeps, and reading skill then would cache it ahead of the FretBots vote.
    if (GetGameState() !== GameState.GameInProgress || !IsActiveFor(bot)) return;
    const pid = bot.GetPlayerID();
    const now = GameTime();
    if (now - (tickedAt[pid] ?? -1) < TICK_SECONDS) return;
    tickedAt[pid] = now;
    const current = { lastHits: counterOf(bot, false), denies: counterOf(bot, true) };
    const previous = countersAt[pid] ?? current;
    countersAt[pid] = current;
    const entries = entriesFor(bot);
    let lastHitAttempts = 0;
    let denyAttempts = 0;
    for (const [creep, entry] of entries) {
        if (!creep.IsNull() && creep.IsAlive()) continue;
        if (entry.attempted) {
            if (entry.isDeny) denyAttempts += 1;
            else lastHitAttempts += 1;
        }
        entries.delete(creep);
    }
    const counts = Counts(bot);
    counts.attempts += lastHitAttempts + denyAttempts;
    counts.misses += math.max(0, lastHitAttempts - (current.lastHits - previous.lastHits));
    counts.misses += math.max(0, denyAttempts - (current.denies - previous.denies));
}
