/**
 * Whether an enemy hero stands inside our lane creeps' aggro (EC-053: our creeps turn on an enemy hero that attacks one of us
 * within that radius, so its hits on us are paid for). Read by the hit back (states/core_trade) and the hold (retreat's
 * `unpaid`): one answer for both, so a drill rig that supplies the fact (`Drill.RigCreepAggro`) gives it to both.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";

export function Paid(bot: Unit, h: Unit): boolean {
    const forced = Drill.RigCreepAggro();
    if (forced !== undefined) return forced;
    const radius = LaneFightConfig.Settings().CreepAggroRadius;
    const at = h.GetLocation();
    return (bot.GetNearbyLaneCreeps(1600, false) ?? []).some((c) => c.IsAlive() && GetUnitToLocationDistance(c, at) <= radius);
}
