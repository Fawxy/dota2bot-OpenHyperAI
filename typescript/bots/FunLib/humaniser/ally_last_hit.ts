/**
 * Allied last-hit etiquette: near a protected human core, allied bots deny rather than last-hit, and only take
 * an enemy creep the human is going to miss. Every tier follows that rule; Profile.deference picks the tier
 * (Polite on easy, Teammate on hard), which sets how quickly and how many kinds of miss the bot notices.
 *
 * MayLastHit returns (allowed, reason). Reasons are prefixed so callers can tell who decided:
 *   "skip: ..."  held back for a protected human
 *   "take: ..."  a protected human is near, but etiquette allows this creep
 *   "free: ..."  etiquette does not apply (callers keep their own rules)
 *
 * jmz_func cannot be required from here (it requires the humaniser), so J.GetPosition and
 * J.IsInLaningPhase are injected with SetHelpers.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Difficulty from "bots/FunLib/humaniser/difficulty";
import * as Profile from "bots/FunLib/humaniser/profile";
import * as HDebug from "bots/FunLib/humaniser/debug";

export const DEFAULTS = {
    ProtectPositions: [1, 2, 3],
    // Bots in these positions keep their own farm unless they share the human's lane.
    OwnFarmPositions: [1, 2],
    ProtectRange: 1000,
    PoliteMin: 0.75,
    HelpfulMin: 0.4,
    // Per tier, what counts as the human missing a creep:
    //   AwayBuffer  creep is beyond the human's attack range plus this, and the human is not walking to it
    //   IdleSeconds human has not attacked for this long
    //   DenyRace    an enemy hero is attacking the deniable creep
    //   Busy        human is attacking an enemy hero
    MissRules: {
        polite: { AwayBuffer: 400, IdleSeconds: 6, DenyRace: false, Busy: false },
        helpful: { AwayBuffer: 150, IdleSeconds: 3, DenyRace: true, Busy: false },
        teammate: { AwayBuffer: 75, IdleSeconds: 1.5, DenyRace: true, Busy: true },
    },
    ApproachLookahead: 0.5,
    ApproachEpsilon: 25,
    // Lane creeps can only be denied below half health.
    DeniableHealth: 0.5,
    HarassInterval: 2.5,
    HarassWindow: 1.2,
    HarassExtraRange: 300,
    HarassMinHP: 0.5,
    TowerAvoidRange: 850,
};

export type AllyLastHitSettings = typeof DEFAULTS;
export type Tier = "polite" | "helpful" | "teammate";
export type MissRule = AllyLastHitSettings["MissRules"]["polite"];

export interface Helpers {
    GetPosition?: (this: void, unit: Unit) => number;
    IsInLaningPhase?: (this: void) => boolean;
}

type LaneUnit = Unit & { GetExtrapolatedLocation(seconds: number): Vector };

let helpers: Helpers = {};
let settings: AllyLastHitSettings | undefined;

interface FrameCache<T> {
    time: number;
    value: T;
}
const humansByTeam: Record<number, FrameCache<Unit[]>> = {};
const enemyHeroesByPlayer: Record<number, FrameCache<Unit[]>> = {};
const lastSkipByPlayer: Record<number, string> = {};

export function SetHelpers(h: Helpers): void {
    helpers = h;
}

export function Settings(): AllyLastHitSettings {
    if (settings === undefined) {
        const result: any = {};
        for (const [k, v] of pairs(DEFAULTS)) result[k] = v;
        const overrides: any = Config.Get().AllyLastHit ?? {};
        // Shallow on purpose: list values such as ProtectPositions replace the default list.
        for (const [k, v] of pairs(overrides)) result[k] = v;
        // MissRules merges per tier and per field, so one value can be tuned without restating the rest.
        const rules: any = {};
        for (const [tier, rule] of pairs(DEFAULTS.MissRules)) {
            const merged: any = {};
            for (const [k, v] of pairs(rule)) merged[k] = v;
            const o = overrides.MissRules?.[tier];
            if (o !== undefined && type(o) === "table") for (const [k, v] of pairs(o)) merged[k] = v;
            rules[tier] = merged;
        }
        result.MissRules = rules;
        settings = result as AllyLastHitSettings;
    }
    return settings;
}

function contains(list: number[], value: number | undefined): boolean {
    if (value === undefined) return false;
    for (const v of list) if (v === value) return true;
    return false;
}

function positionOf(unit: Unit): number | undefined {
    return helpers.GetPosition !== undefined ? helpers.GetPosition(unit) : undefined;
}

function inLaningPhase(): boolean {
    return helpers.IsInLaningPhase !== undefined ? helpers.IsInLaningPhase() : DotaTime() < 600;
}

function cached<T>(store: Record<number, FrameCache<T>>, key: number, compute: () => T): T {
    const now = DotaTime();
    const entry = store[key];
    if (entry !== undefined && entry.time === now) return entry.value;
    const value = compute();
    store[key] = { time: now, value };
    return value;
}

/** True when this bot's laning Think() should be owned by OHA so etiquette can apply. Evaluated at file load. */
export function OwnsLaning(bot: Unit): boolean {
    return Config.IsFeatureEnabled("AllyLastHit") && Difficulty.IsAllyOfHuman(bot);
}

export function GetTier(bot: Unit): Tier {
    const s = Settings();
    const d = Profile.Get(bot).deference;
    if (d >= s.PoliteMin) return "polite";
    if (d >= s.HelpfulMin) return "helpful";
    return "teammate";
}

function protectedHumans(bot: Unit): Unit[] {
    const team = bot.GetTeam();
    return cached(humansByTeam, team, () => {
        const result: Unit[] = [];
        const positions = Settings().ProtectPositions;
        const players = GetTeamPlayers(team);
        for (let i = 1; i <= players.length; i++) {
            const member = GetTeamMember(i);
            if (member === null || member === undefined || !member.IsAlive() || member.IsIllusion()) continue;
            if (IsPlayerBot(member.GetPlayerID())) continue;
            if (contains(positions, positionOf(member))) result.push(member);
        }
        return result;
    });
}

/**
 * The protected human nearest to `location` within ProtectRange, or undefined with the "free:" reason
 * explaining why etiquette does not apply.
 */
export function GetProtectedHuman(bot: Unit, location: Vector): LuaMultiReturn<[Unit | undefined, string]> {
    if (!Config.IsFeatureEnabled("AllyLastHit")) return $multi(undefined, "free: disabled");
    if (!inLaningPhase()) return $multi(undefined, "free: not-laning");
    const s = Settings();
    let nearest: Unit | undefined;
    let nearestDist = s.ProtectRange;
    for (const human of protectedHumans(bot)) {
        const dist = GetUnitToLocationDistance(human, location);
        if (dist <= nearestDist) {
            nearest = human;
            nearestDist = dist;
        }
    }
    if (nearest === undefined) return $multi(undefined, "free: no-human");
    if (contains(s.OwnFarmPositions, positionOf(bot)) && nearest.GetAssignedLane() !== bot.GetAssignedLane()) {
        return $multi(undefined, "free: own-lane");
    }
    return $multi(nearest, "");
}

function canHumanReach(human: Unit, creep: Unit, rule: MissRule): boolean {
    const s = Settings();
    const dist = GetUnitToUnitDistance(human, creep);
    if (dist <= human.GetAttackRange() + rule.AwayBuffer) return true;
    const ahead = GetUnitToLocationDistance(creep, (human as LaneUnit).GetExtrapolatedLocation(s.ApproachLookahead));
    return ahead < dist - s.ApproachEpsilon;
}

function isAboutToBeDenied(bot: Unit, creep: Unit): boolean {
    if (creep.GetHealth() >= creep.GetMaxHealth() * Settings().DeniableHealth) return false;
    for (const enemy of nearbyEnemyHeroes(bot)) {
        if (enemy.GetAttackTarget() === creep) return true;
    }
    return false;
}

function isAttackingHero(bot: Unit, human: Unit): boolean {
    const target = human.GetAttackTarget();
    if (target === null || target === undefined) return false;
    for (const enemy of nearbyEnemyHeroes(bot)) {
        if (enemy === target) return true;
    }
    return false;
}

function nearbyEnemyHeroes(bot: Unit): Unit[] {
    return cached(enemyHeroesByPlayer, bot.GetPlayerID(), () => bot.GetNearbyHeroes(1600, true, BotMode.None));
}

/** Why the human is going to miss `creep` under this tier's rules, or undefined if they should get it. */
function missReason(bot: Unit, human: Unit, creep: Unit, tier: Tier): string | undefined {
    const rule = Settings().MissRules[tier];
    if (!canHumanReach(human, creep, rule)) return "human-away";
    if (GameTime() - human.GetLastAttackTime() > rule.IdleSeconds) return "human-idle";
    if (rule.DenyRace && isAboutToBeDenied(bot, creep)) return "deny-race";
    if (rule.Busy && isAttackingHero(bot, human)) return "human-busy";
    return undefined;
}

function decide(bot: Unit, human: Unit, creep: Unit, tier: Tier): LuaMultiReturn<[boolean, string]> {
    if (human.GetAttackTarget() === creep) return $multi(false, "skip: human-target");
    const miss = missReason(bot, human, creep, tier);
    if (miss === undefined) return $multi(false, `skip: ${tier}`);
    return $multi(true, `take: ${miss}`);
}

function showOverlay(bot: Unit, tier: Tier, allowed: boolean, reason: string): void {
    if (!HDebug.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    if (!allowed) lastSkipByPlayer[pid] = `${reason} @${string.format("%.0f", DotaTime())}`;
    HDebug.Text(bot, "lasthit", `${tier} d=${string.format("%.2f", Profile.Get(bot).deference)} ${lastSkipByPlayer[pid] ?? "-"}`);
}

/** May `bot` take the last hit on `creep`? Allied creeps (denies) are always allowed. */
export function MayLastHit(bot: Unit, creep: Unit): LuaMultiReturn<[boolean, string]> {
    if (!Config.IsFeatureEnabled("AllyLastHit")) return $multi(true, "free: disabled");
    if (creep.GetTeam() === bot.GetTeam()) return $multi(true, "free: deny");
    const [human, freeReason] = GetProtectedHuman(bot, creep.GetLocation());
    if (human === undefined) return $multi(true, freeReason);
    const tier = GetTier(bot);
    const [allowed, reason] = decide(bot, human, creep, tier);
    showOverlay(bot, tier, allowed, reason);
    return $multi(allowed, reason);
}

/** Returns `creeps` unchanged when etiquette is off for this bot, otherwise only the creeps it may hit. */
export function FilterCreeps(bot: Unit, creeps: Unit[]): Unit[] {
    if (!Config.IsFeatureEnabled("AllyLastHit") || !Difficulty.IsAllyOfHuman(bot)) return creeps;
    const result: Unit[] = [];
    for (const creep of creeps) {
        const [allowed] = MayLastHit(bot, creep);
        if (allowed) result.push(creep);
    }
    return result;
}
