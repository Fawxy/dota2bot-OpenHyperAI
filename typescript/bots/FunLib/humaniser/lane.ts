/**
 * Lane management facade (task 07). Imports every lane module so their load-time registrations run;
 * later tasks add behaviour to Tick.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LanePlanner from "bots/FunLib/humaniser/lane_planner";
import * as LaneTech from "bots/FunLib/humaniser/lane_tech";
import * as LaneDebug from "bots/FunLib/humaniser/lane_debug";
import * as HDebug from "bots/FunLib/humaniser/debug";

export { LaneConfig as Config, LaneHooks as Hooks, Camps, LaneState, LaneRoles, LanePlan, LanePlanner, LaneTech };

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

/** Whether this bot's laning Think() is OHA's (decided once at mode-file load, like AllyLastHit.OwnsLaning). */
export function OwnsLaning(bot: Unit): boolean {
    return LaneTech.OwnsLaning(bot);
}

/** Runs before last hits; true means this frame's action is issued. */
export function PreThink(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[]): boolean {
    return LaneTech.PreThink(bot, allyCreeps, enemyCreeps, enemies);
}

/** Runs after last hit and deny; true means this frame's action is issued. */
export function Think(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[]): boolean {
    return LaneTech.Think(bot, allyCreeps, enemyCreeps, enemies);
}

/** Lane position override for the final move; returns `loc` itself when nothing applies. */
export function AdjustPosition(bot: Unit, loc: Vector): Vector {
    return LaneTech.AdjustPosition(bot, loc);
}

export function PickDeny(_bot: Unit, _allyCreeps: Unit[]): Unit | undefined {
    return undefined;
}

export function SupersedesHarass(_bot: Unit): boolean {
    return false;
}
