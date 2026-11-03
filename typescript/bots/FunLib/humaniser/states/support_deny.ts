/**
 * Ours.SupportDeny (slice l1-support-deny): for pos4-5 (both teams unless Ours.SupportDenyDire is false), the laning state's
 * body takes the support's denies, whatever the core is doing, replacing OHA's DenyThink; with Ours.SupportLastHit (slice
 * support-lane-hits) also the last hits no allied core will take (states/lane_claims), replacing OHA's LastHitThink for the
 * bot. One picker for every laner (lane_pick Choose, the claims as its role input), swings timed by the engine's verbs. The
 * step runs first in the support's lane steps (states/support_lane). Off: OHA's own path, exactly as before.
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

/** With Applies: the body also takes the support's claimed last hits (Ours.SupportLastHit); false leaves them to OHA. */
export function LastHits(_bot: Unit): boolean {
    return Ours.On("SupportLastHit");
}
