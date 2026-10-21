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
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as Harass from "bots/FunLib/humaniser/harass";
import * as LaneDebug from "bots/FunLib/humaniser/lane_debug";
import * as HDebug from "bots/FunLib/humaniser/debug";
import { teamMembers } from "bots/FunLib/humaniser/commands";

export { LaneConfig as Config, LaneHooks as Hooks, Camps, LaneState, LaneRoles, LanePlan, LanePlanner, LaneTech, CampJobs, Stacking, Harass };

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
    const adjusted = LaneTech.AdjustPosition(bot, loc);
    if (adjusted !== loc || !LaneConfig.IsOn("Harass")) return adjusted;
    const s = LaneState.ForBot(bot);
    if (s === undefined || LanePlan.View(bot, s).handsOff) return loc;
    const enemy = nearestVisibleEnemy(bot, s);
    if (enemy === undefined) return loc;
    return Harass.StandPoint(bot, enemy, s.ally.units) ?? loc;
}

function nearestVisibleEnemy(bot: Unit, s: LaneState.LaneSnapshot): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = LaneConfig.Settings().Radii.LaneCreep;
    for (const e of LaneState.Enemies(bot, s.lane)) {
        if (!e.visible || e.unit === undefined) continue;
        const d = GetUnitToLocationDistance(bot, e.location);
        if (d < bestDist) {
            best = e.unit;
            bestDist = d;
        }
    }
    return best;
}

export function PickDeny(_bot: Unit, _allyCreeps: Unit[]): Unit | undefined {
    return undefined;
}

/** With Lane.Harass on, every bot whose laning Think() 04 or 07 owns uses the shared harass tool instead of 04's. */
export function SupersedesHarass(_bot: Unit): boolean {
    return LaneConfig.IsActive() && LaneConfig.IsOn("Harass");
}

/** 04's Harass step for a superseded bot; `etiquette` is true when 04 owns the bot (an ally of a human). */
export function HarassThink(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], etiquette: boolean): boolean {
    return Harass.Think(bot, allyCreeps, enemyCreeps, enemies, etiquette);
}

/** mode_farm_generic GetDesire: a camp job's desire, 0 when no job runs (and before any engine call when off). */
export function CampJobDesire(bot: Unit): number {
    return CampJobs.Desire(bot);
}

/** mode_farm_generic Think: true when the camp job owns this frame. */
export function CampJobThink(bot: Unit): boolean {
    return CampJobs.Think(bot);
}

/** mode_laning_generic's last-hit desire yields to a running camp job. */
export function CampJobActive(bot: Unit): boolean {
    return CampJobs.Active(bot);
}

export function CampJobOnEnd(bot: Unit): void {
    CampJobs.OnEnd(bot);
}

function nearestBot(team: number, issuer: Unit): Unit | undefined {
    let best: Unit | undefined;
    let bestDist = math.huge;
    for (const member of teamMembers(team)) {
        if (!member.IsBot() || !member.IsAlive()) continue;
        const d = GetUnitToLocationDistance(member, issuer.GetLocation());
        if (d < bestDist) {
            best = member;
            bestDist = d;
        }
    }
    return best;
}

// !hpulltest <idx> [half]: the issuer's nearest bot runs that pull, bypassing the planner and the owner check.
LaneDebug.Register("hpulltest", (team, issuer, args) => {
    const campIdx = tonumber(args[0]);
    if (campIdx === undefined) {
        HDebug.Log("lane", "hpulltest usage: !hpulltest <idx> [half]");
        return;
    }
    const best = nearestBot(team, issuer);
    if (best === undefined) {
        HDebug.Log("lane", "hpulltest no bot");
        return;
    }
    const kind: CampJobs.JobKind = args[1] === "half" ? "half_pull" : "full_pull";
    const ok = CampJobs.Start(best, { kind, campIdx, forced: true });
    HDebug.Log("lane", `hpulltest pid=${best.GetPlayerID()} camp=${campIdx} kind=${kind} started=${tostring(ok)}`);
});

// !hstacktest <idx>: the issuer's nearest bot stacks that camp at its next reachable stack second, skipping eligibility.
LaneDebug.Register("hstacktest", (team, issuer, args) => {
    const campIdx = tonumber(args[0]);
    if (campIdx === undefined) {
        HDebug.Log("lane", "hstacktest usage: !hstacktest <idx>");
        return;
    }
    const best = nearestBot(team, issuer);
    if (best === undefined) {
        HDebug.Log("lane", "hstacktest no bot");
        return;
    }
    const ok = CampJobs.Start(best, { kind: "stack", campIdx, forced: true });
    HDebug.Log("lane", `hstacktest pid=${best.GetPlayerID()} camp=${campIdx} started=${tostring(ok)}`);
});
