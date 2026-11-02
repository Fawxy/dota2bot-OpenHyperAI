/**
 * Ours.SupportDeny (slice l1-support-deny): for pos4-5 (both teams unless Ours.SupportDenyDire is false), the laning state's
 * body takes the support's denies (the reachable own creep with the earliest eta, lane_pick ChooseDeny, the swing timed by
 * the engine's deny verb), whatever the core is doing, replacing OHA's DenyThink. The support's last hits stay OHA's
 * (with Ours.LeaveCoreCreep). The step runs first in the support's lane steps (states/support_lane).
 * Off: OHA's own path, exactly as before.
 */
import { Team, Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";

export function Applies(bot: Unit): boolean {
    if (!Ours.On("SupportDeny")) return false;
    if (bot.GetTeam() === Team.Dire && !Ours.On("SupportDenyDire")) return false;
    const pos = LaneConfig.PositionOf(bot);
    return pos === 4 || pos === 5;
}
