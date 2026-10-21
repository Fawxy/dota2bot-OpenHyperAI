/**
 * Mid lane playbook (task 07, Phase B3): the pre-rune shove window, deniable-ranged-creep priority and
 * keeping bots off a human mid's wave. The block, aggro pull and shove executors are shared with the other lanes.
 */
import { Lane, Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Counter from "bots/FunLib/humaniser/counterplay";

const DENY_HP = 0.49;

function dist2D(a: { x: number; y: number }, b: { x: number; y: number }): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

export function IsPreRuneWindow(now: number, nextRune: number): boolean {
    const timing = LaneConfig.Settings().Timing;
    const left = nextRune - now;
    return left >= timing.PreRuneMin && left <= timing.PreRuneMax;
}

export function IsPreRune(_team: number, lane: Lane): boolean {
    if (lane !== Lane.Mid || !LaneConfig.IsOn("Mid")) return false;
    const next = LaneConfig.Helpers().NextPowerRuneTime;
    return next !== undefined && IsPreRuneWindow(DotaTime(), next());
}

/**
 * Mid bot only: the first allied ranged lane creep it can deny right now; otherwise the Lua fallback decides.
 * The priority drops while counterplay has the enemy mid missing after a shove.
 */
export function PickDeny(bot: Unit, allyCreeps: Unit[]): Unit | undefined {
    if (!LaneConfig.IsOn("Mid") || bot.GetAssignedLane() !== Lane.Mid) return undefined;
    if (Counter.DropRangedDeny(bot.GetTeam())) return undefined;
    const damage = bot.GetAttackDamage();
    for (const creep of allyCreeps) {
        if (!creep.IsAlive() || !LaneState.IsLaneCreepName(creep.GetUnitName())) continue;
        if (string.find(creep.GetUnitName(), "ranged", 1, true)[0] === undefined) continue;
        const hp = creep.GetHealth();
        if (hp < DENY_HP * creep.GetMaxHealth() && hp <= damage) return creep;
    }
    return undefined;
}

/** False for a non-mid bot near the wave of a human mid, so it does not shove, pull or deny there. */
export function MayTouchWave(bot: Unit, creep: Unit): boolean {
    if (!LaneConfig.IsOn("Mid") || !LaneConfig.InLaningPhase() || bot.GetAssignedLane() === Lane.Mid) return true;
    const s = LaneState.Get(bot.GetTeam(), Lane.Mid, bot);
    if (s === undefined) return true;
    const radii = LaneConfig.Settings().Radii;
    if (dist2D(creep.GetLocation(), s.frontLoc) > radii.MidFront) return true;
    for (const h of s.allies) {
        if (!h.isBot && h.alive && h.assigned && h.position === 2 && h.distToFront <= radii.MidHuman) return false;
    }
    return true;
}

export function MidPullAllowed(team: number): boolean {
    return Camps.PullCampsFor(team, Lane.Mid).length > 0;
}

export function RegisterProbes(): void {
    LaneHooks.SetRotationProbe((bot) => bot.GetAssignedLane() === Lane.Mid && IsPreRune(bot.GetTeam(), Lane.Mid));
}

LaneState.SetPreRune(IsPreRune);
RegisterProbes();
