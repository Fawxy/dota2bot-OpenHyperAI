/**
 * Lane management facade (task 07). Imports every lane module so their load-time registrations run;
 * later tasks add behaviour to Tick.
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LaneDebug from "bots/FunLib/humaniser/lane_debug";
import * as HDebug from "bots/FunLib/humaniser/debug";

export { LaneConfig as Config, LaneHooks as Hooks, Camps, LaneState, LaneRoles, LanePlan };

export function IsEnabled(): boolean {
    return LaneConfig.IsEnabled();
}

export function SetHelpers(h: LaneConfig.LaneHelpers): void {
    LaneConfig.SetHelpers(h);
}

export function Tick(bot: Unit): void {
    LaneDebug.Tick(bot);
    const snapshot = LaneState.ForBot(bot);
    if (snapshot === undefined) return;
    if (HDebug.IsEnabled()) {
        const state = LaneState.Describe(snapshot, LaneState.ScoreFor(bot, snapshot));
        HDebug.Text(bot, "lane", `${state} ${LanePlan.Describe(LanePlan.View(bot, snapshot))}`);
    }
}
