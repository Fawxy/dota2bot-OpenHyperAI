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
import { DamageType, Unit } from "bots/ts_libs/dota";
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
    attempted: boolean;
    isDeny: boolean;
    /** The bot's last-hit (or deny) count when it first went for this creep. */
    countAtAttempt: number;
}

let helpers: Helpers = {};
let settings: LastHitSkillSettings | undefined;
const entriesByPlayer: Record<number, LuaTable<Unit, CreepEntry>> = {};
const ownedLaning: Record<number, boolean> = {};
const warned: Record<number, boolean> = {};
const widthCache: Record<number, { time: number; value: number }> = {};

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

function isUnderPressure(bot: Unit): boolean {
    if (bot.WasRecentlyDamagedByAnyHero(Settings().PressureSeconds)) return true;
    const target = bot.GetAttackTarget();
    return target !== null && target !== undefined && target.IsHero() && target.GetTeam() !== bot.GetTeam();
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
        entry = { eps, attempt: RandomFloat(0, 1) < rate, attempted: false, isDeny, countAtAttempt: 0 };
        entries.set(creep, entry);
    }
    if (!entry.attempt) return false;
    const kills = Upstream(creep, attackDamage * (1 + entry.eps * ErrorWidth(bot)), delay, isDeny);
    if (kills && !entry.attempted) {
        entry.attempted = true;
        entry.countAtAttempt = counterOf(bot, isDeny);
    }
    return kills;
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
