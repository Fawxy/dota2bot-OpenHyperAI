/**
 * Lane management facade (task 07). Imports every lane module so their load-time registrations run;
 * later tasks add behaviour to Tick.
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneDebug from "bots/FunLib/humaniser/lane_debug";

export { LaneConfig as Config, LaneHooks as Hooks, Camps };

export function IsEnabled(): boolean {
    return LaneConfig.IsEnabled();
}

export function SetHelpers(h: LaneConfig.LaneHelpers): void {
    LaneConfig.SetHelpers(h);
}

export function Tick(bot: Unit): void {
    LaneDebug.Tick(bot);
    if (!LaneConfig.IsActive()) return;
}
