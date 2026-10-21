/**
 * Shared lane plan (task 07): one plan per lane that both laners follow.
 * A bot core picks its plan from the lane state; a human core's plan is inferred from what the human
 * does each wave cycle, with hysteresis so the supports do not flip-flop. Accepted LANE_* orders override both.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHooks from "bots/FunLib/humaniser/lane_hooks";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Orders from "bots/FunLib/humaniser/orders";
import * as HDebug from "bots/FunLib/humaniser/debug";

export type LanePlan = "FREEZE" | "HOLD" | "SHOVE" | "NEUTRAL";

export interface CorePlanInput {
    skill: number;
    laneScore: number;
    eqPos: number;
    stronger: boolean;
    rotating: boolean;
    enemyLaners: number;
}

export interface CycleTally {
    shoveHits: number;
    lastHitTries: number;
    denies: number;
    aggroDraws: number;
    stepBacks: number;
    eqSum: number;
    samples: number;
}

export interface Inference {
    current: LanePlan;
    candidate: LanePlan;
    candidateSince: number;
    changedAt: number;
}

export interface PlanView {
    plan: LanePlan;
    source: "order" | "inferred" | "picked" | "default";
    handsOff: boolean;
    pullAllowed: boolean;
    pullForced: boolean;
    stackRequested: boolean;
    coreIsHuman: boolean;
    corePid?: number;
}

const PLAN_RANK: LanePlan[] = ["SHOVE", "FREEZE", "HOLD", "NEUTRAL"];
// With no stronger signal the neutral plan still outranks a single stray observation.
const NEUTRAL_SCORE = 0.25;

export function PickCorePlan(i: CorePlanInput): LanePlan {
    const cfg = LaneConfig.Settings();
    if (i.rotating) return "SHOVE";
    if (i.skill >= cfg.Gates.Freeze && i.stronger && i.enemyLaners > 0 && i.eqPos <= cfg.Thresholds.FreezeCoreEqMax) return "FREEZE";
    if (i.enemyLaners === 0 && i.laneScore < 0) return "SHOVE";
    return "HOLD";
}

export function NewTally(): CycleTally {
    return { shoveHits: 0, lastHitTries: 0, denies: 0, aggroDraws: 0, stepBacks: 0, eqSum: 0, samples: 0 };
}

function sumTally(a: CycleTally, b: CycleTally): CycleTally {
    return {
        shoveHits: a.shoveHits + b.shoveHits,
        lastHitTries: a.lastHitTries + b.lastHitTries,
        denies: a.denies + b.denies,
        aggroDraws: a.aggroDraws + b.aggroDraws,
        stepBacks: a.stepBacks + b.stepBacks,
        eqSum: a.eqSum + b.eqSum,
        samples: a.samples + b.samples,
    };
}

export function ClassifyTally(t: CycleTally): LanePlan {
    const infer = LaneConfig.Settings().Infer;
    if (t.shoveHits >= infer.ShoveHits) return "SHOVE";
    if (t.shoveHits === 0 && t.denies >= infer.FreezeDenies && t.samples > 0 && t.eqSum / t.samples <= infer.FreezeEqMax) return "FREEZE";
    if (t.aggroDraws + t.stepBacks >= infer.HoldSignals) return "HOLD";
    return "NEUTRAL";
}

function scoreTally(t: CycleTally): Record<LanePlan, number> {
    const infer = LaneConfig.Settings().Infer;
    const meanEq = t.samples > 0 ? t.eqSum / t.samples : 0;
    const freeze = t.shoveHits === 0 ? (t.denies / infer.FreezeDenies) * (meanEq <= infer.FreezeEqMax ? 1 : 0.5) : 0;
    return {
        SHOVE: t.shoveHits / infer.ShoveHits,
        FREEZE: freeze,
        HOLD: (t.aggroDraws + t.stepBacks) / infer.HoldSignals,
        NEUTRAL: NEUTRAL_SCORE,
    };
}

/** The best-scoring plan of the tally other than `exclude` (ties go to the order of PLAN_RANK). */
function alternativePlan(t: CycleTally, exclude: LanePlan): LanePlan {
    const scores = scoreTally(t);
    let best: LanePlan | undefined;
    for (const plan of PLAN_RANK) {
        if (plan === exclude) continue;
        if (best === undefined || scores[plan] > scores[best]) best = plan;
    }
    return best!;
}

export function NewInference(): Inference {
    return { current: "NEUTRAL", candidate: "NEUTRAL", candidateSince: 0, changedAt: -math.huge };
}

export function Step(inf: Inference, candidate: LanePlan, now: number): Inference {
    const timing = LaneConfig.Settings().Timing;
    const candidateSince = candidate !== inf.candidate ? now : inf.candidateSince;
    let current = inf.current;
    let changedAt = inf.changedAt;
    if (candidate !== current && now - candidateSince >= timing.PlanSustain && now - changedAt >= timing.PlanMinDwell) {
        current = candidate;
        changedAt = now;
    }
    return { current, candidate, candidateSince, changedAt };
}

interface LaneTrack {
    cycle: number;
    cur: CycleTally;
    prev: CycleTally;
    inf: Inference;
    pullBlockedCycle?: number;
}

interface PickInputs {
    time: number;
    skill: number;
    laneScore: number;
    eqPos: number;
    stronger: boolean;
    enemyLaners: number;
}

interface Misread {
    cycle: number;
    alt?: LanePlan;
}

let laneTracks: Record<string, LaneTrack> = {};
let pickCache: Record<string, PickInputs> = {};
let misreads: Record<number, Misread> = {};

export function ResetCache(): void {
    laneTracks = {};
    pickCache = {};
    misreads = {};
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function cycleIndex(time: number): number {
    return math.floor(time / LaneConfig.Settings().Timing.WaveCycle);
}

function trackFor(s: LaneState.LaneSnapshot): LaneTrack {
    const key = `${s.team}:${s.lane}`;
    let t = laneTracks[key];
    if (t === undefined) {
        t = { cycle: cycleIndex(s.time), cur: NewTally(), prev: NewTally(), inf: NewInference() };
        laneTracks[key] = t;
    }
    return t;
}

/** Ally hero assigned to the lane with the lowest core position (1-3), alive or not. */
function coreOf(s: LaneState.LaneSnapshot): LaneState.LaneHero | undefined {
    let best: LaneState.LaneHero | undefined;
    for (const h of s.allies) {
        if (!h.assigned || h.position === undefined || h.position < 1 || h.position > 3) continue;
        if (best === undefined || h.position < best.position! || (h.position === best.position && h.pid < best.pid)) best = h;
    }
    return best;
}

function isLaneCreep(unit: Unit | null | undefined): unit is Unit {
    return unit !== null && unit !== undefined && LaneState.IsLaneCreepName(unit.GetUnitName());
}

function sampleHuman(t: CycleTally, s: LaneState.LaneSnapshot, h: LaneState.LaneHero): void {
    const cfg = LaneConfig.Settings();
    const human = h.unit;
    const target = human.GetAttackTarget();
    const targetIsCreep = isLaneCreep(target);
    if (targetIsCreep) {
        if (target.GetTeam() !== s.team) {
            if (target.GetHealth() <= human.GetAttackDamage() * cfg.Infer.ShoveHitDamageMult) t.lastHitTries++;
            else t.shoveHits++;
        } else {
            t.denies++;
        }
    }
    if (s.lastAllyAggroAt[h.pid] === s.time && !targetIsCreep) t.aggroDraws++;

    const here = GetAmountAlongLane(s.lane, human.GetLocation()).amount;
    const ahead = GetAmountAlongLane(s.lane, human.GetExtrapolatedLocation(cfg.Radii.ApproachExtrapolate)).amount;
    if (Camps.ToTeamAmount(s.team, ahead) < Camps.ToTeamAmount(s.team, here)) {
        const moved = dist2D(GetLocationAlongLane(s.lane, here), GetLocationAlongLane(s.lane, ahead));
        if (moved > cfg.Radii.StepBackEps) {
            let near = 0;
            const loc = human.GetLocation();
            for (const c of s.enemy.units) if (dist2D(c.GetLocation(), loc) <= cfg.Radii.StepBackCreeps) near++;
            if (near >= 1) t.stepBacks++;
        }
    }
    t.eqSum += s.eqPos;
    t.samples++;
}

function inWindow(cycleSec: number, sec: number): boolean {
    const cycle = LaneConfig.Settings().Timing.WaveCycle;
    const d = math.abs(cycleSec - (sec % cycle));
    return math.min(d, cycle - d) <= LaneConfig.Settings().Timing.HumanPullWindow;
}

function humanPulling(s: LaneState.LaneSnapshot, human: Unit): boolean {
    const radius = LaneConfig.Settings().Radii.HumanPullRadius;
    const loc = human.GetLocation();
    for (const job of Camps.PullCampsFor(s.team, s.lane)) {
        if (job.pull === undefined) continue;
        let spawner: Camps.Spawner | undefined;
        for (const sp of Camps.Spawners()) {
            if (sp.idx === job.campIdx) spawner = sp;
        }
        if (spawner === undefined || dist2D(Camps.BoxCenter(spawner), loc) > radius) continue;
        const seconds = [...job.pull.aggroSec, ...(job.pull.halfAggroSec ?? [])];
        for (const sec of seconds) if (inWindow(s.cycleSec, sec)) return true;
    }
    return false;
}

export function ObserveSnapshot(s: LaneState.LaneSnapshot): void {
    if (!LaneConfig.IsOn("Plan")) return;
    const track = trackFor(s);
    const idx = cycleIndex(s.time);
    if (track.cycle !== idx) {
        track.prev = idx === track.cycle + 1 ? track.cur : NewTally();
        track.cur = NewTally();
        track.cycle = idx;
    }
    const core = coreOf(s);
    for (const h of s.allies) {
        if (h.isBot || !h.alive) continue;
        if (humanPulling(s, h.unit)) track.pullBlockedCycle = idx;
        if (core !== undefined && h.pid === core.pid) sampleHuman(track.cur, s, h);
    }
    if (core !== undefined && !core.isBot && core.alive) {
        track.inf = Step(track.inf, ClassifyTally(sumTally(track.cur, track.prev)), s.time);
    }
}

/** Enemy heroes seen near the lane front within the exposure window. */
export function EnemyLaners(bot: Unit, s: LaneState.LaneSnapshot): number {
    const cfg = LaneConfig.Settings();
    let n = 0;
    for (const e of LaneState.Enemies(bot, s.lane)) {
        if (!e.visible && e.timeSinceSeen > cfg.Timing.ExposureSeen) continue;
        if (dist2D(e.location, s.frontLoc) <= cfg.Radii.Exposure) n++;
    }
    return n;
}

function pickFor(picker: Unit, s: LaneState.LaneSnapshot): LanePlan {
    const key = `${picker.GetPlayerID()}:${s.lane}`;
    let inputs = pickCache[key];
    if (inputs === undefined || inputs.time !== s.time) {
        const stronger = LaneConfig.Helpers().WeAreStronger;
        inputs = {
            time: s.time,
            skill: LaneConfig.SkillOf(picker),
            laneScore: LaneState.ScoreFor(picker, s).laneScore,
            eqPos: s.eqPos,
            stronger: stronger !== undefined && stronger(picker, LaneConfig.Settings().Radii.Stronger),
            enemyLaners: EnemyLaners(picker, s),
        };
        pickCache[key] = inputs;
    }
    // Rotation probes are registered by higher modules and change within a snapshot window, so never cached.
    return PickCorePlan({ ...inputs, rotating: LaneHooks.IsRotationPlanned(picker) });
}

export function View(bot: Unit, s: LaneState.LaneSnapshot): PlanView {
    const core = coreOf(s);
    const coreIsHuman = core !== undefined && !core.isBot;
    if (!LaneConfig.IsOn("Plan")) {
        return { plan: "NEUTRAL", source: "default", handsOff: false, pullAllowed: true, pullForced: false, stackRequested: false, coreIsHuman, corePid: core?.pid };
    }
    const track = trackFor(s);
    let plan: LanePlan;
    let source: PlanView["source"];
    if (Orders.GetAcceptedForLane(bot, "LANE_FREEZE", s.lane) !== undefined) {
        plan = "FREEZE";
        source = "order";
    } else if (Orders.GetAcceptedForLane(bot, "LANE_SHOVE", s.lane) !== undefined) {
        plan = "SHOVE";
        source = "order";
    } else if (core !== undefined && coreIsHuman && core.alive) {
        plan = track.inf.current;
        source = "inferred";
    } else {
        // A bot core picks for itself; a dead or missing core leaves the pick to the observing bot.
        plan = pickFor(core !== undefined && core.alive ? core.unit : bot, s);
        source = "picked";
    }
    return {
        plan,
        source,
        handsOff: Orders.GetAcceptedForLane(bot, "LANE_HANDSOFF", s.lane) !== undefined,
        pullAllowed: Orders.GetAcceptedForLane(bot, "LANE_NOPULL", s.lane) === undefined && track.pullBlockedCycle !== cycleIndex(s.time),
        pullForced: Orders.GetAcceptedForLane(bot, "LANE_PULL", s.lane) !== undefined,
        stackRequested: Orders.GetAcceptedForLane(bot, "LANE_STACK", s.lane) !== undefined,
        coreIsHuman,
        corePid: core?.pid,
    };
}

/** View with the support's once-per-wave-cycle chance of reading the plan wrong. Orders are never misread. */
export function ForSupport(bot: Unit, s: LaneState.LaneSnapshot): PlanView {
    const view = View(bot, s);
    if (view.source === "order" || view.source === "default") return view;
    const pid = bot.GetPlayerID();
    const idx = cycleIndex(s.time);
    let m = misreads[pid];
    if (m === undefined || m.cycle !== idx) {
        m = { cycle: idx };
        misreads[pid] = m;
        if (LaneConfig.Roll(LaneConfig.Curve("PlanMisread", LaneConfig.SkillOf(bot)))) {
            const track = trackFor(s);
            m.alt = view.coreIsHuman ? alternativePlan(sumTally(track.cur, track.prev), view.plan) : "NEUTRAL";
            HDebug.Log("lane", `pid=${pid} misread plan ${view.plan} as ${m.alt}`);
        }
    }
    if (m.alt === undefined || m.alt === view.plan) return view;
    return { ...view, plan: m.alt };
}

export function Describe(v: PlanView): string {
    let text = `plan=${v.plan}(${v.source})`;
    if (v.handsOff) text += " handsoff";
    if (!v.pullAllowed) text += " nopull";
    if (v.pullForced) text += " pull!";
    if (v.stackRequested) text += " stack!";
    return text;
}

LaneState.OnRefresh(ObserveSnapshot);
