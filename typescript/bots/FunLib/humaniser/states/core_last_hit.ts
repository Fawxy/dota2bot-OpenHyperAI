/**
 * Ours.CoreLastHit (slice 5): for pos1-3 (both teams unless Ours.CoreLastHitDire is false), the laning state's body takes the core's lane last hits and
 * denies (the creep from laneTargets with states/lane_pick, the swing timed by the engine's lastHit/deny facts),
 * replacing OHA's LastHitThink/DenyThink and, on the team without a human, Valve's C++ laning. The body stands on
 * OHA's own lane spot (States.Laning.Spot 'oha'); the state's floor is 0, so OHA's mode arbitration is unchanged.
 * Off: OHA's own path, exactly as before.
 */
import { Team, Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";

export function Applies(bot: Unit): boolean {
    if (!Ours.On("CoreLastHit")) return false;
    if (bot.GetTeam() === Team.Dire && !Ours.On("CoreLastHitDire")) return false;
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 1 && pos <= 3;
}
