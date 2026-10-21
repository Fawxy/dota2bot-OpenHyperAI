/**
 * Technique planner (task 07, Phase C decision only): which technique, if any, a bot runs this wave cycle.
 * Choose is pure and re-run on every Plan call (PF3), so orders, pings and rotations act mid-cycle; only the
 * per-cycle attempt roll and the committed technique are remembered (PF14). No unit actions here.
 */
import { Lane, Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as LaneRoles from "bots/FunLib/humaniser/lane_roles";
import * as LanePlan from "bots/FunLib/humaniser/lane_plan";
import * as HDebug from "bots/FunLib/humaniser/debug";

export interface PlannerInput {
    skill: number;
    role: LaneRoles.LaneRole;
    isMid: boolean;
    now: number;
    dotaTime: number;
    plan: LanePlan.PlanView;
    laneScore: number;
    eqPos: number;
    allyCreeps: number;
    enemyCreeps: number;
    enemyLaners: number;
    pullCamp: boolean;
    stackedPullCamp: boolean;
    mayRunCampJob: boolean;
    partnerSafe: boolean;
    coverAbsentCore: boolean;
    rotationPlanned: boolean;
    humanCoreInLane: boolean;
    desiredEq: number;
    override?: LaneConfig.Technique;
}

export type Choice = { tech: LaneConfig.Technique | "hold" | "none"; reason: string };
type Committable = LaneConfig.Technique | "contest";

interface CycleState {
    cycle: number;
    rolls: Record<string, boolean>;
    committed?: Committable;
}

let cycles: Record<number, CycleState> = {};
let current: Record<number, Choice> = {};

export function ResetCache(): void {
    cycles = {};
    current = {};
}

function pick(tech: Choice["tech"], reason: string): Choice {
    return { tech, reason };
}

export function Choose(i: PlannerInput): Choice {
    const cfg = LaneConfig.Settings();
    const bands = cfg.Planner;
    const knows = (tech: LaneConfig.Technique) => LaneConfig.Knows(tech, i.skill);
    const plan = i.plan;
    const supportish = i.role === "support";

    if (plan.handsOff) return pick("none", "handsoff");

    if (i.dotaTime >= 0 && i.dotaTime < cfg.Timing.BlockEnd && knows("block")) {
        // A bot core leaves the block to a human core in its lane; supports block alongside one (C/B2 ruling).
        if (i.role !== "core" || !i.humanCoreInLane) return pick("block", "0:00 block");
    }

    if (i.override !== undefined && knows(i.override)) return pick(i.override, `counter: ${i.override}`);
    if (i.rotationPlanned && plan.plan !== "FREEZE" && knows("shove")) return pick("shove", "shove before rotating");

    if (plan.plan === "SHOVE") return knows("shove") ? pick("shove", "plan shove") : pick("none", "plan shove: unknown");

    if (i.coverAbsentCore && supportish) {
        if (knows("freeze")) return pick("freeze", "cover core: freeze");
        if (knows("aggro_pull") && i.laneScore <= bands.AggroCorrectBelow) return pick("aggro_pull", "cover core: aggro");
        return pick("hold", "cover core: hold");
    }

    const campOk = i.pullCamp && plan.pullAllowed && i.mayRunCampJob && i.partnerSafe;

    if (plan.plan === "FREEZE") {
        if (i.laneScore <= bands.SmallDriftBelow && i.allyCreeps >= i.enemyCreeps + bands.LargeWaveMargin && campOk && knows("half_pull")) {
            return pick("half_pull", "freeze: thin large wave");
        }
        if (!supportish && i.eqPos > i.desiredEq + cfg.Thresholds.FreezeDriftMargin && knows("aggro_pull")) {
            return pick("aggro_pull", "freeze: drag back");
        }
        return knows("freeze") ? pick("freeze", "plan freeze") : pick("hold", "plan freeze: hold");
    }

    if (i.isMid && i.eqPos >= cfg.Thresholds.MidTowerEq && knows("aggro_pull")) return pick("aggro_pull", "mid: out of tower range");

    if (!i.isMid || i.pullCamp) {
        if ((i.laneScore <= bands.FullPullBelow || plan.pullForced) && campOk) {
            if (i.stackedPullCamp && knows("stack_pull") && i.enemyLaners > 0) return pick("stack_pull", "deny: stacked camp");
            if (knows("full_pull")) return pick("full_pull", plan.pullForced ? "pull ordered" : "wave pushed out");
        }
        if (i.laneScore <= bands.SmallDriftBelow && campOk && knows("half_pull")) return pick("half_pull", "small drift");
    }

    if (i.laneScore <= bands.AggroCorrectBelow && knows("aggro_pull")) return pick("aggro_pull", "small correction");
    return pick("none", "lane fine");
}

function cycleIndex(time: number): number {
    return math.floor(time / LaneConfig.Settings().Timing.WaveCycle);
}

function stateFor(pid: number, now: number): CycleState {
    const idx = cycleIndex(now);
    let c = cycles[pid];
    if (c === undefined || c.cycle !== idx) {
        c = { cycle: idx, rolls: {} };
        cycles[pid] = c;
    }
    return c;
}

/** A dead core makes RoleIn report the support as solo; the support keeps its role while covering. */
function roleOf(bot: Unit, s: LaneState.LaneSnapshot): LaneRoles.LaneRole {
    const role = LaneRoles.RoleIn(bot, s);
    if (role !== "solo" || !LaneRoles.CoreAbsent(s)) return role;
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 4 ? "support" : role;
}

function humanCoreIn(bot: Unit, s: LaneState.LaneSnapshot): boolean {
    const pid = bot.GetPlayerID();
    for (const h of s.allies) {
        if (h.pid === pid || h.isBot || !h.alive || !h.assigned) continue;
        if (h.position !== undefined && h.position >= 1 && h.position <= 3) return true;
    }
    return false;
}

function buildInput(bot: Unit, s: LaneState.LaneSnapshot, now: number): PlannerInput {
    const role = roleOf(bot, s);
    const enemies = LaneState.Enemies(bot, s.lane);
    const camps = Camps.PullCampsFor(s.team, s.lane);
    let stacked = false;
    for (const job of camps) if (LaneHooks.IsStacked(job.campIdx)) stacked = true;
    const plan = role === "support" ? LanePlan.ForSupport(bot, s) : LanePlan.View(bot, s);
    return {
        skill: LaneConfig.SkillOf(bot),
        role,
        isMid: s.lane === Lane.Mid,
        now,
        dotaTime: now,
        plan,
        laneScore: LaneState.ScoreFor(bot, s).laneScore,
        eqPos: s.eqPos,
        allyCreeps: s.ally.count,
        enemyCreeps: s.enemy.count,
        enemyLaners: LanePlan.EnemyLaners(bot, s),
        pullCamp: camps.length > 0,
        stackedPullCamp: stacked,
        mayRunCampJob: LaneRoles.MayRunCampJob(bot, s, enemies)[0],
        partnerSafe: LaneRoles.PartnerSafe(bot, s, enemies),
        coverAbsentCore: role === "support" && LaneRoles.CoverAbsentCore(bot, s, now),
        rotationPlanned: LaneHooks.IsRotationPlanned(bot),
        humanCoreInLane: humanCoreIn(bot, s),
        desiredEq: s.desiredEq,
        override: LaneHooks.TechniqueOverride(bot),
    };
}

// Only the technique a human ordered skips the attempt roll; anything else chosen meanwhile still rolls.
const ORDERED_BY_PULL: Record<string, boolean> = { full_pull: true, stack_pull: true, half_pull: true };

function gate(bot: Unit, i: PlannerInput, choice: Choice): Choice {
    const tech = choice.tech;
    if (tech === "none" || tech === "hold") return choice;
    const c = stateFor(bot.GetPlayerID(), i.now);
    if (c.committed !== undefined) return c.committed === tech ? choice : pick("none", `one per cycle (${c.committed})`);
    if (ORDERED_BY_PULL[tech] === true && i.plan.pullForced) return choice;
    if (tech === "stack_pull" && i.plan.stackRequested) return choice;
    let ok = c.rolls[tech];
    if (ok === undefined) {
        ok = LaneConfig.Roll(LaneConfig.Curve("AttemptRate", i.skill));
        c.rolls[tech] = ok;
    }
    return ok ? choice : pick("none", `skip: attempt-roll ${tech}`);
}

export function Plan(bot: Unit, s: LaneState.LaneSnapshot): Choice {
    if (!LaneConfig.IsActive()) return pick("none", "lane off");
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const input = buildInput(bot, s, now);
    const result = gate(bot, input, Choose(input));
    const prev = current[pid];
    if (prev === undefined || prev.tech !== result.tech) {
        LaneRoles.ClearNeed(bot);
        if (result.tech === "aggro_pull") LaneRoles.NoteNeed(bot, now);
    }
    current[pid] = result;
    HDebug.Text(bot, "lane_tech", Describe(result));
    return result;
}

export function Current(bot: Unit): Choice | undefined {
    return current[bot.GetPlayerID()];
}

export function Commit(bot: Unit, tech: Committable): void {
    stateFor(bot.GetPlayerID(), DotaTime()).committed = tech;
}

/** Frees the cycle's technique when the job that committed it ended without acting. */
export function Release(bot: Unit, tech: Committable): void {
    const c = stateFor(bot.GetPlayerID(), DotaTime());
    if (c.committed === tech) c.committed = undefined;
}

export function Committed(bot: Unit): Committable | undefined {
    return stateFor(bot.GetPlayerID(), DotaTime()).committed;
}

export function Describe(c: Choice): string {
    return `tech=${c.tech} (${c.reason})`;
}
