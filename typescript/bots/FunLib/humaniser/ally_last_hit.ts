/**
 * Allied last-hit etiquette: allied bots leave a protected human core's lane creeps alone,
 * scaled by Profile.deference (Polite on easy, Teammate on hard).
 *
 * MayLastHit returns (allowed, reason). Reasons are prefixed so callers can tell who decided:
 *   "skip: ..."  held back for a protected human
 *   "take: ..."  a protected human is near, but etiquette allows this creep
 *   "free: ..."  etiquette does not apply (callers keep their own rules)
 *
 * jmz_func cannot be required from here (it requires the humaniser), so J.GetPosition and
 * J.IsInLaningPhase are injected with SetHelpers.
 */
import { BotMode, BotScriptEnums, Unit, Vector } from "bots/ts_libs/dota";
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
    OutOfRangeBuffer: 150,
    IdleSeconds: 3,
    ApproachLookahead: 0.5,
    ApproachEpsilon: 25,
    // Lane creeps can only be denied below half health.
    DeniableHealth: 0.5,
    // Attack range is measured edge to edge; unit distance is centre to centre.
    SwingRangeBuffer: 50,
    HarassInterval: 2.5,
    HarassWindow: 1.2,
    HarassExtraRange: 300,
    HarassMinHP: 0.5,
    TowerAvoidRange: 850,
};

export type AllyLastHitSettings = typeof DEFAULTS;
export type Tier = "polite" | "helpful" | "teammate";

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
const enemyCreepsByPlayer: Record<number, FrameCache<Unit[]>> = {};
const lastSkipByPlayer: Record<number, string> = {};

export function SetHelpers(h: Helpers): void {
    helpers = h;
}

export function Settings(): AllyLastHitSettings {
    if (settings === undefined) {
        const result: any = {};
        for (const [k, v] of pairs(DEFAULTS)) result[k] = v;
        // Shallow on purpose: list values such as ProtectPositions replace the default list.
        for (const [k, v] of pairs(Config.Get().AllyLastHit ?? {})) result[k] = v;
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

function isAttackAnimation(unit: Unit): boolean {
    const activity = unit.GetAnimActivity();
    return activity === BotScriptEnums.ACTIVITY_ATTACK || activity === BotScriptEnums.ACTIVITY_ATTACK2;
}

function canHumanReach(human: Unit, creep: Unit): boolean {
    const s = Settings();
    const dist = GetUnitToUnitDistance(human, creep);
    if (dist <= human.GetAttackRange() + s.OutOfRangeBuffer) return true;
    const ahead = GetUnitToLocationDistance(creep, (human as LaneUnit).GetExtrapolatedLocation(s.ApproachLookahead));
    return ahead < dist - s.ApproachEpsilon;
}

function isAboutToBeDenied(bot: Unit, creep: Unit): boolean {
    if (creep.GetHealth() >= creep.GetMaxHealth() * Settings().DeniableHealth) return false;
    const enemies = cached(enemyHeroesByPlayer, bot.GetPlayerID(), () => bot.GetNearbyHeroes(1600, true, BotMode.None));
    for (const enemy of enemies) {
        if (enemy.GetAttackTarget() === creep) return true;
    }
    return false;
}

function isLowestInHumanRange(bot: Unit, human: Unit, creep: Unit): boolean {
    const range = human.GetAttackRange() + Settings().SwingRangeBuffer;
    const creeps = cached(enemyCreepsByPlayer, bot.GetPlayerID(), () => bot.GetNearbyLaneCreeps(1600, true));
    let lowest: Unit | undefined;
    for (const c of creeps) {
        if (!c.IsAlive() || GetUnitToUnitDistance(human, c) > range) continue;
        if (lowest === undefined || c.GetHealth() < lowest.GetHealth()) lowest = c;
    }
    return lowest === creep;
}

function decide(bot: Unit, human: Unit, creep: Unit, tier: Tier): LuaMultiReturn<[boolean, string]> {
    if (tier === "polite") return $multi(false, "skip: polite");
    if (human.GetAttackTarget() === creep) return $multi(false, "skip: human-target");
    if (tier === "helpful") {
        if (!canHumanReach(human, creep)) return $multi(true, "take: human-away");
        if (GameTime() - human.GetLastAttackTime() > Settings().IdleSeconds) return $multi(true, "take: human-idle");
        if (isAboutToBeDenied(bot, creep)) return $multi(true, "take: deny-race");
        return $multi(false, "skip: helpful");
    }
    if (isAttackAnimation(human) && isLowestInHumanRange(bot, human, creep)) return $multi(false, "skip: human-swing");
    return $multi(true, "take: teammate");
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
