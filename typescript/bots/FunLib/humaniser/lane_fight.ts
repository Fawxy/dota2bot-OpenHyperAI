/**
 * Lane fight facade (task 11): trades and kill setups with imperfect cooldown memory. Tick runs per bot per frame
 * from Humaniser.Tick; ReadFor is the fight read (trade and respect windows); CheckKill is the kill check; later tasks
 * add the executor.
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneFightConfig from "bots/FunLib/humaniser/lane_fight_config";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as AbilityClasses from "bots/FunLib/humaniser/ability_classes";
import * as CooldownMemory from "bots/FunLib/humaniser/cooldown_memory";
import * as CastWatch from "bots/FunLib/humaniser/cast_watch";
import * as FightRead from "bots/FunLib/humaniser/fight_read";
import * as KillCheck from "bots/FunLib/humaniser/kill_check";

export { LaneFightConfig as Config, AbilityClasses, CooldownMemory, CastWatch, FightRead, KillCheck };

export function IsActive(): boolean {
    return LaneFightConfig.IsActive();
}

export function Tick(bot: Unit): void {
    if (!LaneFightConfig.IsActive() || !LaneFightConfig.AppliesTo(bot) || !LaneConfig.InLaningPhase()) return;
    // A bot with no assigned lane (no lane snapshot) has no lane enemies to watch.
    if (LaneFightConfig.IsOn("Memory") && LaneState.ForBot(bot) !== undefined) CastWatch.Tick(bot);
}

/** The fight read for `bot`; callers act on it. Guarded in index.ts: an error reads as no window. */
export function ReadFor(bot: Unit, now: number): FightRead.Read {
    return FightRead.ReadFor(bot, now);
}

/** The kill check on `target` with `partners`; guarded in index.ts: an error reads as no check. */
export function CheckKill(bot: Unit, partners: (Unit | undefined)[], target: Unit, now: number): KillCheck.KillResult | undefined {
    return KillCheck.Check(bot, partners, target, now);
}
