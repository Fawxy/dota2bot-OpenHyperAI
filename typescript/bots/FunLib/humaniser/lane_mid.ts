/** Mid lane playbook: the pre-rune shove window. */
import { Lane } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as LaneState from "bots/FunLib/humaniser/lane_state";

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

export function MidPullAllowed(team: number): boolean {
    return Camps.PullCampsFor(team, Lane.Mid).length > 0;
}

export function RegisterProbes(): void {
    LaneHooks.SetRotationProbe((bot) => bot.GetAssignedLane() === Lane.Mid && IsPreRune(bot.GetTeam(), Lane.Mid));
}

LaneState.SetPreRune(IsPreRune);
RegisterProbes();
