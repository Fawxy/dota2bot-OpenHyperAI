/**
 * Lane fight facade (task 11): trades and kill setups with imperfect cooldown memory. Tick runs per bot per frame
 * from Humaniser.Tick; later tasks add the fight read and the executor.
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import * as CooldownMemory from "bots/FunLib/humaniser/cooldown_memory";
import * as CastWatch from "bots/FunLib/humaniser/cast_watch";

export { LaneFightConfig as Config, AbilityClasses, CooldownMemory, CastWatch };

export function IsActive(): boolean {
    return LaneFightConfig.IsActive();
}

export function Tick(bot: Unit): void {
    if (!LaneFightConfig.IsActive() || !LaneFightConfig.AppliesTo(bot) || !LaneConfig.InLaningPhase()) return;
    // A bot with no assigned lane (no lane snapshot) has no lane enemies to watch.
    if (LaneFightConfig.IsOn("Memory") && LaneState.ForBot(bot) !== undefined) CastWatch.Tick(bot);
}
