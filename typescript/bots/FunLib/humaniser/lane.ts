/**
 * Lane management facade (task 07). Imports every lane module so their load-time registrations run;
 * later tasks add behaviour to Tick.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as LanePlanner from "bots/FunLib/humaniser/lane_planner";
import * as LaneMid from "bots/FunLib/humaniser/lane_mid";
import * as LaneTech from "bots/FunLib/humaniser/lane_tech";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import * as Harass from "bots/FunLib/humaniser/harass";
import * as Counter from "bots/FunLib/humaniser/counterplay";
import * as LaneDebug from "bots/FunLib/humaniser/lane_debug";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Intent from "bots/FunLib/humaniser/intent";
import { teamMembers } from "bots/FunLib/humaniser/commands";

export { LaneConfig as Config, LaneHooks as Hooks, Camps, LaneState, LaneRoles, LanePlan, LanePlanner, LaneMid, LaneTech, CampJobs, PullTiming, Stacking, Harass, Counter };

export function IsEnabled(): boolean {
    return LaneConfig.IsEnabled();
}

export function SetHelpers(h: LaneConfig.LaneHelpers): void {
    LaneConfig.SetHelpers(h);
}

export function Tick(bot: Unit): void {
    LaneDebug.Tick(bot);
    CampJobs.FlushModeEnd(bot);
    const snapshot = LaneState.ForBot(bot);
    if (snapshot === undefined) return;
    Counter.Tick(bot);
    CampJobs.CoverTick(bot);
    if (HDebug.IsEnabled()) {
        const state = LaneState.Describe(snapshot, LaneState.ScoreFor(bot, snapshot));
        HDebug.Text(bot, "lane", `${state} ${LanePlan.Describe(LanePlan.View(bot, snapshot))}`);
    }
}

/** Whether this bot's laning Think() is OHA's (decided once at mode-file load, like AllyLastHit.OwnsLaning). */
export function OwnsLaning(bot: Unit): boolean {
    return LaneTech.OwnsLaning(bot);
}

function mayTouchAny(bot: Unit, creeps: Unit[]): boolean {
    for (const creep of creeps) if (!LaneMid.MayTouchWave(bot, creep)) return false;
    return true;
}

/** False when any of these creeps is a human mid's wave this bot must leave alone (deny included). */
export function MayDeny(bot: Unit, allyCreeps: Unit[]): boolean {
    return mayTouchAny(bot, allyCreeps);
}

/** Runs before last hits; true means this frame's action is issued. */
export function PreThink(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], lastHit?: LaneTech.LastHit): boolean {
    if (!mayTouchAny(bot, enemyCreeps)) {
        // Shedding tower aggro is safety, not a touch of the human's wave, but it may only hit creeps the bot may touch.
        const touchable: Unit[] = [];
        for (const c of allyCreeps) if (LaneMid.MayTouchWave(bot, c)) touchable.push(c);
        return LaneTech.TowerDropThink(bot, touchable);
    }
    return LaneTech.PreThink(bot, allyCreeps, enemyCreeps, enemies, lastHit);
}

/** Runs after last hit and deny; true means this frame's action is issued. */
export function Think(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[]): boolean {
    if (!mayTouchAny(bot, enemyCreeps)) return false;
    if (LaneTech.Think(bot, allyCreeps, enemyCreeps, enemies)) return true;
    return Counter.Think(bot, enemies);
}

/** Lane position override for the final move; returns `loc` itself when nothing applies. */
export function AdjustPosition(bot: Unit, loc: Vector): Vector {
    const override = LaneHooks.PositionOverride(bot, loc);
    if (override !== loc) return override;
    let adjusted = LaneTech.AdjustPosition(bot, loc);
    if (adjusted === loc) adjusted = Counter.AdjustPosition(bot, loc);
    if (adjusted !== loc || !LaneConfig.IsOn("Harass") || CampJobs.Covering(bot)) return adjusted;
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

export function PickDeny(bot: Unit, allyCreeps: Unit[]): Unit | undefined {
    return LaneMid.PickDeny(bot, allyCreeps);
}

/** With Lane.Harass on, every bot whose laning Think() 04 or 07 owns uses the shared harass tool instead of 04's. */
export function SupersedesHarass(_bot: Unit): boolean {
    return LaneConfig.IsActive() && LaneConfig.IsOn("Harass");
}

/** 04's Harass step for a superseded bot; `etiquette` is true when 04 owns the bot (an ally of a human). */
export function HarassThink(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], etiquette: boolean): boolean {
    // No trades while the support is away on a camp (CampJobs.CoverTick) or while caution suppresses them (task 12).
    if (CampJobs.Covering(bot) || LaneHooks.TradesSuppressed(bot)) return false;
    return Harass.Think(bot, allyCreeps, enemyCreeps, enemies, etiquette);
}

/** mode_farm_generic GetDesire: a camp job's desire, 0 when no job runs (and before any engine call when off). */
export function CampJobDesire(bot: Unit): number {
    return CampJobs.Desire(bot);
}

const JOB_FOCUS_MODES: BotMode[] = [BotMode.Ward, BotMode.TeamRoam, BotMode.Roam, BotMode.Rune, BotMode.SideShop, BotMode.SecretShop];

/**
 * mode_farm_generic GetDesire's return for a running job (`desire` from CampJobDesire). With intent arbitration
 * the job's desire is a same-frame CAMP_JOB floor over a raw 0, so survival and order claims outrank it and the
 * survival cap treats it as lifted; a second claim keeps the active mode's stickiness from making the pull late.
 * Without intent, or for a unit intent leaves out, it is the desire itself.
 */
export function CampJobRawDesire(bot: Unit, desire: number): number {
    const job = CampJobs.Current(bot);
    const kind = job?.kind ?? "job";
    const floor = CampJobs.Commits(bot) ? LaneConfig.Settings().Timing.JobCommitDesire : desire;
    if (!Intent.Claim(bot, { source: `lane:${kind}`, tier: "CAMP_JOB", mode: BotMode.Farm, floor, until: GameTime() })) return desire;
    // Travel, wait and the wait for the hit to be confirmed are timed against the pull; after that other modes' stickiness is no concern.
    if (job !== undefined && (job.phase === "travel" || job.phase === "wait" || job.phase === "aggro")) {
        Intent.Claim(bot, { source: "lane:camp_job", tier: "CAMP_JOB", mode: BotMode.Farm, unsticks: true });
    } else {
        Intent.Release(bot, "lane:camp_job", BotMode.Farm);
    }
    // Claims only order within one mode, so the floor on farm alone lost to ward, team_roam or a shop walk. Those
    // errands wait until the job is done; attack, retreat, defend and orders are left alone.
    const cap = desire - LaneConfig.Settings().Thresholds.JobFocusMargin;
    for (const mode of JOB_FOCUS_MODES) Intent.Claim(bot, { source: "lane:job_focus", tier: "CAMP_JOB", mode, cap });
    // Retreat's laning-phase creep-damage branch counts the chasing neutrals, so it beat the job at healthy HP once
    // the camp was hit. Held while only neutrals threaten; survival and order claims sit on higher tiers.
    if (CampJobs.HoldsRetreat(bot)) Intent.Claim(bot, { source: "lane:job_hold", tier: "CAMP_JOB", mode: BotMode.Retreat, cap });
    else Intent.Release(bot, "lane:job_hold", BotMode.Retreat);
    return 0;
}

/** mode_farm_generic's ShouldRun: neutrals hitting a bot leading a pull are not a reason to run. */
export function CampJobHoldsRetreat(bot: Unit): boolean {
    return CampJobs.HoldsRetreat(bot);
}

/** ability_item_usage_generic: no spells or items on the camp a job is working. */
export function CampJobHoldsCasts(bot: Unit): boolean {
    return CampJobs.HoldsCasts(bot);
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

/** mode_farm_generic: a run started, so the camp job it would no longer execute ends now. */
export function CampJobAbort(bot: Unit, reason: string): void {
    CampJobs.Abort(bot, reason);
}

/** mode_rune_generic GetDesire floor: a mid bot contesting the rune after spotting the enemy mid's pre-rune shove. */
export function RuneContestDesire(bot: Unit): number {
    return Counter.RuneContestDesire(bot);
}

/** mode_farm_generic: a camp an enemy was seen stacking, or undefined to keep the farm pick. */
export function PreferStackedCamp(bot: Unit, camps: any[]): any | undefined {
    return Counter.PreferStackedCamp(bot, camps);
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
