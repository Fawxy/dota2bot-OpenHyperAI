/**
 * Support last-hit etiquette (slice 3, switch Ours.LeaveCoreCreep): a pos4/pos5 bot leaves an enemy lane creep that an
 * allied core (OHA position 1-3, bot or human) can take, and takes one no core can (EC-050, EC-055). It replaces
 * OHA's choice for these bots in mode_laning_generic (Valve's C++ laning there) and in mode_team_roam_generic's
 * X.GetLastHitCreep.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";

// All judgement (slice 3 work order). ReachBuffer is wider than the hlog audit's 150 so a core that walks into range
// during the support's swing still counts; Approach* as AllyLastHit.CoreCanReach, within ApproachRange of the creep.
export const SETTINGS = {
    ReachBuffer: 300,
    ApproachRange: 1000,
    ApproachLookahead: 0.5,
    ApproachEpsilon: 25,
};

type MovingUnit = Unit & { GetExtrapolatedLocation(seconds: number): Vector };

function isCore(unit: Unit): boolean {
    const pos = LaneConfig.PositionOf(unit);
    return pos !== undefined && pos <= 3;
}

/** The switch is on and `bot` is a support (position 4 or 5). */
export function Applies(bot: Unit): boolean {
    if (!Ours.On("LeaveCoreCreep")) return false;
    const pos = LaneConfig.PositionOf(bot);
    return pos === 4 || pos === 5;
}

/** Whether `core` can take `creep` itself: attacking it, in attack range + ReachBuffer, or walking to it. */
export function CanTake(core: Unit, creep: Unit): boolean {
    if (core.GetAttackTarget() === creep) return true;
    const dist = GetUnitToUnitDistance(core, creep);
    if (dist <= core.GetAttackRange() + SETTINGS.ReachBuffer) return true;
    if (dist > SETTINGS.ApproachRange) return false;
    const ahead = GetUnitToLocationDistance(creep, (core as MovingUnit).GetExtrapolatedLocation(SETTINGS.ApproachLookahead));
    return ahead < dist - SETTINGS.ApproachEpsilon;
}

/** Some living allied core other than `bot` can take `creep`. Walks GetTeamMember (GetTeamPlayers is empty for a bot-only team). */
export function CoreCanTake(bot: Unit, creep: Unit): boolean {
    for (let i = 1; i <= 5; i++) {
        const member = GetTeamMember(i);
        if (member === null || member === undefined || member === bot) continue;
        if (!member.IsAlive() || member.IsIllusion() || !isCore(member)) continue;
        if (CanTake(member, creep)) return true;
    }
    return false;
}

/** May `bot` last-hit `creep`? Only meaningful where Applies(bot). */
export function MayLastHit(bot: Unit, creep: Unit): boolean {
    return !CoreCanTake(bot, creep);
}
