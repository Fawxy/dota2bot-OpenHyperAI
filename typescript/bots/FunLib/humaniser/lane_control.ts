/**
 * Lane controller, slices 2a and 2b (design `docs/proposals/2026-11-06-lane-controller.md` s5.1-s5.3, s5.1b, s5.1c; slice
 * file `docs/team/slices/lane-controller.md`): once per wave per team and lane, one reading of where the clash will sit against
 * the lane's target point, the mode from the ruleset R1-R6, the wave intent, the levers that could close the gap with each
 * one's predicted effect, and the set it chooses. One `ev=lane_ctl kind=wave` line per decision and one `kind=chk` line
 * Horizon s later with the clash then, which scores the prediction (hlog view `lane_ctl`).
 *
 * Slice 2b (`Ours.LaneControlDrive`, under `Ours.LaneControl`): the decision drives the levers. Each lever's owner reads it
 * as a named input and keeps its own gates (rule 6: nobody scales another's output): the idle swing reads the mode and intent
 * (`ModeFor`) and its `setup` lever (`Chosen`), lane aggro's feed whether the feed is in this wave's set (`Chosen`), the pull trigger whether the
 * pull of the pulled wave is (`DecisionFor`). Commitment (s5.1b): a decision holds for its wave; a `shove` mode breaks early
 * (`kind=break`) when an enemy laner shows up near the clash or the core drops low. With no decision for the moment (before
 * From, after Until, or no reading) each owner falls back to its own trigger. Aggro's other draws (drag, tower, the hold's
 * back) keep their own triggers: the controller is one input to lane aggro, not its owner.
 *
 * The pull's effect is the fight model's (lane_push WaveGoneFrom: this wave gone) against the plain forecast, scaled by
 * PullScale: on 17 banked games (138 diverted pulls) the unscaled model overshoots the move by about 1.6x at 30-45 s after
 * the slot; scaled by 0.61 it had the lowest error of every arm at +30 and +45 s (median 788 and 684, read 8 s before the
 * slot; design s5.1c has the table; `docs/proposals/lane-forecast/pulleffect.js`). The check falls about 31 s after a pull
 * slot (read at wave + 2, slots near wave + 16), so the +30 s row is its offline before value.
 *
 * Slice 2c (user 09/11/2026): the read records whether their last due wave arrived (`ew`: present, absent, unknown; the
 * enemy wave tracker `enemy_wave.ts` follows one wave at a time and the read takes its resolution). Absent is a fact the
 * lane keeps (`Suspect`) for a later investigate-lane or contest-pull job; the one response now is `MissingWave`: no pull
 * of ours this cycle (`pull:ew`), the other levers as the ruleset gives them; resolved between reads, a chosen pull that has
 * not left is broken (`PullBreak`, `kind=break why=ew`).
 */
import { Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Calendar from "bots/FunLib/humaniser/calendar";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as EnemyWave from "bots/FunLib/humaniser/enemy_wave";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

declare function RealTime(this: void): number;

export type Mode = "safe" | "shove";
export type Intent = "back" | "hold" | "forward" | "reset";

/** All `judgement` unless marked. */
export const SETTINGS = {
    /** Second of the 30 s wave cycle the decision is read at (our wave has just spawned, before any pull slot). */
    ReadAt: 2,
    From: 60,
    Until: 720,
    /** The prediction's horizon: the next meeting after this wave's pull (scored offline at slot + 30..45 s). */
    Horizon: 45,
    /** `need` within Band of the target is `hold` (PullJob WantPast, so the shadow intent asks for a pull where today's
     *  trigger does). */
    Band: 150,
    /** pulleffect.js least-squares k for diverted pulls at slot + 30 and + 45 s (0.61, 0.64; 17 games). */
    PullScale: 0.6,
    /** Slice 2b: a pull's expected effect is the diverted one times the chance a start diverts the wave (measured 0.33-0.50
     *  per start on the banked pulls, design s5.1c; `judgement` inside that range, retuned from the check run). */
    DivertShare: 0.4,
    /** A decision serves the idle swing and the feed until the next wave's read (30 s) plus a second's slack. */
    Live: 31,
    /** A `shove` decision's break conditions are re-read this often (s). */
    BreakEvery: 1,
    /** Fixed lever sizes, along the lane towards our T1 (EC-078 gives the direction only; slice 2b measures them). */
    PreDenySize: 300,
    FeedSize: 300,
    /** Slice 2b: the idle swing's `setup` (an enemy creep hit into our last-hit range), towards their T1. */
    SetupSize: 300,
    /** A hero within this of the clash point counts in lane. */
    InLane: 2000,
    /** R2: a support departure (a rune trip or a stack on its calendar, slice 3) leaving within this many seconds makes this
     *  wave the reset wave. */
    DepartWithin: 60,
    /** Slice 3 (design s5.4, s5.5 rule 2): a support's pull that does not fit before a stack on its calendar takes the
     *  stack's minute when the lane's predicted need (n45) is past YieldBase + YieldPerMin a minute after 3:00 (the stack
     *  weighted up as the game goes on, user 06/11/2026); else the stack keeps it. `judgement`: on the banked :30 waves of
     *  stack minutes (lctl2, lctl3) 800 read as two in three at 3:30, but the check run lctl4 (07/11/2026) yielded 16 of 17
     *  clash:stack minutes at 3:30 (review M3: 4 of 20 supports never stacked); on lctl4 n45, 1,600 yields 0.65 at 3:30,
     *  0.32 at 5:30, 0.29 at 7:30. */
    YieldBase: 1600,
    YieldPerMin: 200,
    /** The minute YieldPerMin counts from (the first stack minute). */
    YieldFrom: 3,
    /** ...and not sooner than this: a support leaving before this wave's pull slot (about 16 s after the spawn, 14 after
     *  the read) has no time to reset it (review 2026-11-06-lane-control-3115b32 M2: lctl1 read at 5:32, departure 5:35). */
    DepartAfter: 15,
    /** R6: the core below this HP share, or this many enemy heroes within CoreThreatR of it with no support in lane. */
    CoreLowHp: 0.4,
    CoreThreat: 2,
    CoreThreatR: 1200,
    /** R5: their laners are the enemy heroes seen within EnemyLaneR of the clash in the last EnemyMemory s; all of them dead
     *  or seen farther than EnemyAway from it. */
    EnemyLaneR: 2500,
    EnemyMemory: 90,
    EnemyAway: 3000,
    /** Fallback only: a tower's reach from its centre along the lane, read live by WorldFacts.Reach (7.41: attack range 700 +
     *  bounding radius 144). `shove` targets their T1's range edge this far short of it; a pull's hold floor is our T1's. */
    TowerRange: 844,
    /** Slice 4a (design s5.7; user 06/11/2026: the pos3 may pull the hard camp and no other): before this game second the
     *  offlane's pos4, in lane and able, pulls; from it (the pos4 roams from about 6:00) the pos3 is the first puller. */
    CorePullFrom: 360,
    /** The pos3 pulls only when the lane gold it would lose while away (CoreCamp LossBetween on the plain forecast, from the
     *  walk's start to its walk back) is at most this: two lane creeps at the core's full share. The pull's own worth is the
     *  reset lane, which the lane advantage layer (s5.8) will price; `judgement` until then, read from `closs`. User 07/11/2026:
     *  keep the rule order, but the lane's need lifts the limit: plus CorePullPerNeed gold a unit of n45 past the band (a
     *  clash 2,000 past the target allows about 170). */
    CorePullWorth: 80,
    CorePullPerNeed: 0.05,
    /** Walking paths run longer than the straight line (CoreCamp's and rune_job's PathFactor). */
    PathFactor: 1.2,
    /** Slice 2c (user 09/11/2026): a read that sees their due wave absent (pulled, blocked or cut) refuses our own pull for
     *  this cycle (`pull:ew`); the other levers stay. The drill reads `ewp` to tell whether Choose refused it anyway. */
    SkipPullOnMissingWave: true,
    /** How long an absent read stays the lane's suspect fact (`Suspect`), for a later investigate-lane or contest-pull job. */
    SuspectFor: 60,
};

/** One candidate puller: the support (with the calendar's refusal) or the offlane pos3 (with its site and gold reads). */
export interface PullerInputs {
    now: number;
    /** The need the levers are chosen on (the clash 45 s on past the target). */
    n45?: number;
    sup?: { pid: number; why?: string };
    core?: { pid: number; missing: number; loss?: number };
}

/**
 * Slice 4a (design s5.7, its rule list `judgement`): who takes the pull lever. Before CorePullFrom an able support pulls. Else
 * the offlane pos3 pulls when no enemy hero is missing near its walk to the camp (CoreCamp MissingOf) and the lane gold it
 * loses while away is at most CorePullLimit (the lane's need lifts it); failing that an able support still pulls. `why` the support's refusal (or
 * `no_sup`) when neither goes; `cwhy` why the core did not.
 */
/** The lane gold the pos3 may lose to pull: CorePullWorth, plus CorePullPerNeed a unit of need past the band. */
export function CorePullLimit(n45: number | undefined): number {
    return SETTINGS.CorePullWorth + SETTINGS.CorePullPerNeed * math.max(0, (n45 ?? 0) - SETTINGS.Band);
}

export function PullerOf(i: PullerInputs): { who: string; by?: string; why?: string; cwhy?: string } {
    const supOk = i.sup !== undefined && i.sup.why === undefined;
    if (supOk && i.now < SETTINGS.CorePullFrom) return { who: `${i.sup!.pid}`, by: "sup" };
    let cwhy: string | undefined;
    if (i.core !== undefined) {
        cwhy = i.core.missing > 0 ? "missing" : i.core.loss === undefined ? "no_plan" : i.core.loss > CorePullLimit(i.n45) ? "loss" : undefined;
        if (cwhy === undefined) return { who: `${i.core.pid}`, by: "core" };
    }
    if (supOk) return { who: `${i.sup!.pid}`, by: "sup", cwhy };
    return { who: "", why: i.sup?.why ?? "no_sup", cwhy };
}

export interface Lever {
    name: string;
    /** Predicted change of the clash at the horizon, along the lane from our side (negative: towards our T1). */
    effect: number;
    /** Order of danger, least first. */
    danger: number;
    who: string;
    /** Why it cannot be used, undefined when it can. */
    why?: string;
}

export interface Choice {
    levers: Lever[];
    /** The chosen set leaves the clash this far past the target (positive: towards their T1). */
    left: number;
    /** No set reached the band without overshooting it. */
    short: boolean;
}

/** Levers that cannot be taken together (a pull resets our wave, a shove spends it). */
function clash(a: Lever, b: Lever): boolean {
    return (a.name === "pull" && b.name === "shove") || (a.name === "shove" && b.name === "pull");
}

/**
 * The fewest, then least dangerous, usable levers whose summed effect takes `need` (the clash past the target) into
 * [-band, band]; when none does, the set that comes nearest without passing -band (design s5.3, user 06/11/2026). Up to
 * three levers; an empty set when `need` is already inside the band.
 */
export function Choose(need: number, band: number, levers: Lever[]): Choice {
    if (math.abs(need) <= band) return { levers: [], left: need, short: false };
    const ok = levers.filter((l) => l.why === undefined && (need > 0 ? l.effect < 0 : l.effect > 0));
    let best: Choice | undefined;
    let bestKey: [number, number, number] | undefined;
    const sets: Lever[][] = [];
    const grow = (from: number, set: Lever[]) => {
        for (let i = from; i < ok.length; i++) {
            const next = [...set, ok[i]];
            sets.push(next);
            if (next.length < 3) grow(i + 1, next);
        }
    };
    grow(0, []);
    for (const set of sets) {
        let bad = false;
        for (let i = 0; i < set.length && !bad; i++) for (let j = i + 1; j < set.length; j++) if (clash(set[i], set[j])) bad = true;
        if (bad) continue;
        let left = need;
        let danger = 0;
        for (const l of set) {
            left += l.effect;
            danger += l.danger;
        }
        const over = need > 0 ? left < -band : left > band;
        if (over) continue;
        const inside = math.abs(left) <= band;
        // inside first, then fewer levers, then less danger; outside, nearer the band first
        const key: [number, number, number] = inside ? [0, set.length, danger] : [1, math.abs(left), danger];
        if (bestKey === undefined || key[0] < bestKey[0] || (key[0] === bestKey[0] && (key[1] < bestKey[1] || (key[1] === bestKey[1] && key[2] < bestKey[2])))) {
            bestKey = key;
            best = { levers: set, left, short: !inside };
        }
    }
    return best ?? { levers: [], left: need, short: true };
}

export function IntentOf(need: number, band: number, reset: boolean): Intent {
    if (reset && need > -band) return "reset";
    return need > band ? "back" : need < -band ? "forward" : "hold";
}

/**
 * The set for this wave's intent: a `reset` lane already inside the band takes the pre-deny alone (design s5.5 rule 1), a
 * change-wanting intent runs Choose, `hold` takes nothing. `levers[0]` is the pre-deny.
 */
export function ChoiceFor(intent: Intent, n45: number, band: number, levers: Lever[]): Choice {
    if (intent === "reset" && math.abs(n45) <= band) {
        const pd = levers[0];
        return pd.why === undefined ? { levers: [pd], left: n45 + pd.effect, short: false } : { levers: [], left: n45, short: true };
    }
    if (intent === "back" || intent === "reset" || intent === "forward") return Choose(n45, band, levers);
    return { levers: [], left: n45, short: false };
}

/**
 * Slice 2c: the choice with the tracker's resolution `ew` applied. On an `a` read with SkipPullOnMissingWave a pull lever on
 * offer is refused `ew` (a pull refused already keeps its own reason: `no_sup`, `away`, `stack`, ... stay readable) and `ewp`
 * says whether ChoiceFor with the pull on offer would have taken it: 1 the skip changed the set, 0 the model refused it anyway
 * (the drill's redundancy read); unset when the pull was not on offer. Any other read leaves the levers alone, `ewp` unset.
 */
export function MissingWave(ew: EnemyWave.Sight | undefined, intent: Intent, n45: number, band: number, levers: Lever[]): { levers: Lever[]; choice: Choice; ewp?: number } {
    if (ew !== "a" || !SETTINGS.SkipPullOnMissingWave) return { levers, choice: ChoiceFor(intent, n45, band, levers) };
    const pull = levers.find((l) => l.name === "pull");
    if (pull === undefined || pull.why !== undefined) return { levers, choice: ChoiceFor(intent, n45, band, levers) };
    const used = levers.map((l) => (l === pull ? { ...l, why: "ew" } : l));
    const would = ChoiceFor(intent, n45, band, levers);
    return { levers: used, choice: ChoiceFor(intent, n45, band, used), ewp: would.levers.some((l) => l.name === "pull") ? 1 : 0 };
}

// ------------------------------------------------------------------------------------------------- the game's view

interface Laner {
    unit: Unit;
    pid: number;
    pos: number;
    bot: boolean;
    present: boolean;
}

/** What the levers' owners read (slice 2b). */
export interface Decision {
    wave: number;
    /** Game second the decision was made. */
    at: number;
    rule: string;
    mode: Mode;
    intent: Intent;
    /** Chosen lever names (`predeny`, `feed`, `pull`, `shove`, and `hold` beside a pull). */
    levers: string[];
    /** Who takes each lever, by index: `both`, `core`, `sup` or a pid. */
    who: string[];
    /** The clash point at the read, for the break checks. */
    cx: number;
    cy: number;
    core?: Unit;
    /** Why a `shove` mode broke before its wave ended (`enemy`, `core_low`), or `ew` when their wave absent took its pull. */
    broke?: string;
    /** Slice 3: the stack minute this decision's pull takes from its support (`YieldsStack`). */
    yields?: number;
    /** Slice 2c: the enemy wave tracker's resolution read at this decision (`u` with none resolved since the last read). */
    ew?: EnemyWave.Sight;
}

/**
 * Slice 2c: what the lane knows is up (user 09/11/2026). `their_wave_missing`: at second `t` our creeps saw the spot of
 * their due wave empty (pulled, blocked or cut). Nothing reads it yet: it is the named input of a later investigate-lane or
 * contest-pull job. CANDIDATE(lane_suspect).
 */
export interface Suspicion {
    kind: "their_wave_missing";
    t: number;
}

interface LaneMemory {
    /** Enemy pid -> last second it was seen near the clash. */
    enemies: Record<number, number>;
    wave?: number;
    /** Decided waves whose check is still to log, oldest first. */
    chks: number[];
    /** Decisions by wave second, the last few kept. */
    decisions: Record<number, Decision>;
    last?: Decision;
    breakAt?: number;
    suspect?: Suspicion;
}

const memory: Record<string, LaneMemory> = {};

export function ResetCache(): void {
    for (const k in memory) delete memory[k];
    EnemyWave.ResetCache();
}

function memoryOf(team: number, lane: Lane): LaneMemory {
    const key = `${team}:${lane}`;
    let m = memory[key];
    if (m === undefined) {
        m = { enemies: {}, chks: [], decisions: {} };
        memory[key] = m;
    }
    return m;
}

function dist(a: Vector, x: number, y: number): number {
    return math.sqrt((a.x - x) ** 2 + (a.y - y) ** 2);
}

/** The calling script's team's heroes assigned to `lane` (GetTeamMember, not GetTeamPlayers: practice mode). */
function lanersOf(lane: Lane, cx: number, cy: number): Laner[] {
    const out: Laner[] = [];
    for (let i = 1; i <= 5; i++) {
        const u = GetTeamMember(i);
        if (u === undefined || u === null || u.IsNull() || u.GetAssignedLane() !== lane) continue;
        const pos = LaneConfig.PositionOf(u) ?? 0;
        out.push({ unit: u, pid: u.GetPlayerID(), pos, bot: u.IsBot(), present: u.IsAlive() && dist(u.GetLocation(), cx, cy) <= SETTINGS.InLane });
    }
    return out;
}

/** The need past which a support's pull takes a stack's minute (slice 3). */
export function YieldPast(now: number): number {
    return SETTINGS.YieldBase + SETTINGS.YieldPerMin * math.max(0, now / 60 - SETTINGS.YieldFrom);
}

/**
 * The pull lever's calendar check (slice 3): `fit` the calendar's answer for the support's next pull window; `why` the
 * refusal (`away`: it does not fit before a rune trip; `stack`: nor before a stack the lane does not need more); `yld` the
 * stack minute the pull may take.
 */
export function PullCalendar(fit: Calendar.Fit, e: Calendar.Entry | undefined, n45: number, now: number): { fit: string; why?: string; yld?: number } {
    if (fit !== "clash" || e === undefined) return { fit };
    const tag = `clash:${e.kind}`;
    if (e.fixed || e.running) return { fit: tag, why: "away" };
    return n45 > YieldPast(now) ? { fit: tag, yld: e.key } : { fit: tag, why: "stack" };
}

/** R5: their laners are known: every enemy hero seen near the lane lately is dead or seen far from the clash. */
function enemiesAway(m: LaneMemory, now: number, cx: number, cy: number): boolean {
    const visible: Record<number, Unit> = {};
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e === null || e === undefined || e.IsIllusion() || !e.CanBeSeen()) continue;
        visible[e.GetPlayerID()] = e;
        if (dist(e.GetLocation(), cx, cy) <= SETTINGS.EnemyLaneR) m.enemies[e.GetPlayerID()] = now;
    }
    let any = false;
    for (const k in m.enemies) {
        const pid = tonumber(k)!;
        if (now - m.enemies[pid] > SETTINGS.EnemyMemory) {
            delete m.enemies[pid];
            continue;
        }
        any = true;
        if (!IsHeroAlive(pid)) continue;
        const e = visible[pid];
        if (e === undefined || dist(e.GetLocation(), cx, cy) <= SETTINGS.EnemyAway) return false;
    }
    return any;
}

function coreThreat(core: Laner, supportIn: boolean): boolean {
    const u = core.unit;
    if (u.GetHealth() / math.max(1, u.GetMaxHealth()) < SETTINGS.CoreLowHp) return true;
    if (supportIn) return false;
    const near = u.GetNearbyHeroes(SETTINGS.CoreThreatR, true, 0) ?? [];
    return near.length >= SETTINGS.CoreThreat;
}

function ownAt(samples: LanePush.Sample[] | undefined, path: LanePath | undefined, team: number, t: number): number | undefined {
    if (samples === undefined || path === undefined) return undefined;
    const c = LanePush.ClashAt(samples, t);
    if (c === undefined) return undefined;
    const [t1, dir] = LanePush.OwnT1(path, team);
    return dir * (c - t1);
}

function round(x: number | undefined): number | undefined {
    return x === undefined ? undefined : math.floor(x + 0.5);
}

function decide(team: number, lane: Lane, now: number, m: LaneMemory): void {
    const clock = (RealTime as unknown) !== undefined ? RealTime : undefined;
    const started = clock?.();
    const s = SETTINGS;
    const path = LanePush.PathOf(lane);
    const r = LanePush.Read(team, lane);
    if (path === undefined || r === undefined) {
        Telemetry.Event("lane_ctl", [["team", team], ["lane", lane], ["kind", "wave"], ["why", r === undefined ? "no_read" : "no_path"]]);
        return;
    }
    const [cx, cy] = LanePush.PointAt(path, r.clash);
    const laners = lanersOf(lane, cx, cy);
    const cores = laners.filter((l) => l.pos >= 1 && l.pos <= 3);
    const sups = laners.filter((l) => l.pos >= 4);
    const coreIn = cores.find((l) => l.present);
    const supIn = sups.find((l) => l.present);
    const supBot = sups.find((l) => l.present && l.bot);
    // Each hero's own calendar (user 07/11/2026); a human support has none.
    const cal = supIn !== undefined && supIn.bot ? Calendar.Of(supIn.unit, now) : undefined;
    const dep = cal !== undefined ? Calendar.NextLeave(cal, now) : undefined;
    // The ruleset (design s5.1), most binding first.
    let rule = "R1";
    let mode: Mode = "safe";
    const away = enemiesAway(m, now, cx, cy);
    if (coreIn !== undefined && coreThreat(coreIn, supIn !== undefined)) rule = "R6";
    else if (away && (coreIn !== undefined || supIn !== undefined)) {
        rule = "R5";
        mode = "shove";
    } else if (supIn !== undefined && dep !== undefined && dep >= s.DepartAfter && dep <= s.DepartWithin) rule = "R2";
    else if (coreIn !== undefined && supIn === undefined) rule = "R3";
    // R4 (a core alone with a use for the time) needs the camp trip's shove-then-camp price, not built yet (ROADMAP Core next
    // gold): never chosen in slice 2a.
    const [ourT1, dir] = LanePush.OwnT1(path, team);
    const theirT1 = path.towers.find((tw) => tw.team !== team)!.s;
    const span = dir * (theirT1 - ourT1);
    const reach = WorldFacts.Reach(s.TowerRange);
    const tgt = mode === "shove" ? span - reach : LanePush.TargetOf(lane);
    // The plain forecast and the lane with this wave pulled, both to the horizon.
    const at = math.floor(now) + s.Horizon;
    const [samples] = LanePush.Forecast(team, lane, s.Horizon + 3);
    const plain = ownAt(samples, path, team, at);
    const cycle = LaneConfig.Settings().Timing.WaveCycle;
    const ts = math.floor(now / cycle) * cycle;
    const gone = LanePush.WaveGoneNow(team, lane, ts, at);
    const need = r.own + r.move - tgt;
    const base = plain ?? r.own + r.move;
    const n45 = base - tgt;
    const intent = IntentOf(n45, s.Band, rule === "R2");
    const pe = gone?.own !== undefined && plain !== undefined ? s.PullScale * s.DivertShare * (gone.own - plain) : undefined;
    // The pull's window against the puller's calendar (slice 3).
    let pc: { fit: string; why?: string; yld?: number } | undefined;
    if (supBot !== undefined) {
        // Lazy: pull_job's imports reach this module (its own require of lane_control is lazy for the same reason).
        const PullJob = require("bots/FunLib/humaniser/pull_job") as typeof import("bots/FunLib/humaniser/pull_job");
        const w = PullJob.Window(supBot.unit, now);
        if (w !== undefined) {
            const [fit, e] = Calendar.FitOf(Calendar.Of(supBot.unit, now), w.start, w.end);
            pc = PullCalendar(fit, e, n45, now);
        }
    }
    // Slice 4a: the offlane pos3 as a puller of its hard camp (the offlane's only pull camp), under Ours.CorePull.
    let coreCand: { pid: number; missing: number; loss?: number } | undefined;
    if (coreIn !== undefined && coreIn.bot && coreIn.pos === 3 && rule !== "R6" && lane === Camps.LaneOfKind(team, "off") && Ours.On("CorePull") && samples !== undefined) {
        const PullJob = require("bots/FunLib/humaniser/pull_job") as typeof import("bots/FunLib/humaniser/pull_job");
        const CoreCamp = require("bots/FunLib/humaniser/core_camp") as typeof import("bots/FunLib/humaniser/core_camp");
        const w = PullJob.Window(coreIn.unit, now);
        if (w === undefined) coreCand = { pid: coreIn.pid, missing: 0 };
        else {
            const u = coreIn.unit;
            const back = (math.sqrt((w.stand.x - cx) ** 2 + (w.stand.y - cy) ** 2) * s.PathFactor) / math.max(1, u.GetCurrentMovementSpeed());
            const clash: import("bots/FunLib/humaniser/core_camp").Clash = { t: now, at: Vector(cx, cy, 0), t0: samples[0]?.t ?? now, samples, enemy: team === Team.Radiant ? Team.Dire : Team.Radiant, path, team };
            coreCand = { pid: coreIn.pid, missing: CoreCamp.MissingOf(u, w.stand).n, loss: CoreCamp.LossBetween(clash, w.start, w.end + back) };
        }
    }
    const puller = PullerOf({ now, n45, sup: supBot !== undefined ? { pid: supBot.pid, why: pc?.why } : undefined, core: coreCand });
    // Slice 2c: the enemy wave the tracker resolved since the last read (`u` with none: nothing resolved yet, or no reading).
    const fact = EnemyWave.Take(EnemyWave.StateOf(team, lane));
    const ew: EnemyWave.Sight = fact?.ew ?? "u";
    const offered: Lever[] = [];
    const levers: Lever[] = [];
    const anyIn = coreIn !== undefined || supIn !== undefined;
    offered.push({ name: "predeny", effect: -s.PreDenySize, danger: 1, who: coreIn !== undefined && supIn !== undefined ? "both" : coreIn !== undefined ? "core" : "sup", why: !anyIn ? "nobody" : !Ours.On("PreDeny") ? "off" : undefined });
    offered.push({ name: "feed", effect: -s.FeedSize, danger: 2, who: coreIn !== undefined ? "core" : "sup", why: !anyIn ? "nobody" : undefined });
    offered.push({
        name: "pull",
        effect: pe ?? 0,
        danger: 3,
        who: puller.who,
        why: puller.by === undefined && puller.why === "no_sup" ? "no_sup" : rule === "R6" ? "r6" : pe === undefined ? "no_clash" : gone !== undefined && gone.pw === 0 ? "no_wave" : puller.by === undefined ? puller.why : undefined,
    });
    offered.push({ name: "setup", effect: s.SetupSize, danger: 1, who: coreIn !== undefined && supIn !== undefined ? "both" : coreIn !== undefined ? "core" : "sup", why: mode === "shove" ? "mode" : !anyIn ? "nobody" : !Ours.On("PreDeny") ? "off" : undefined });
    offered.push({ name: "shove", effect: s.PreDenySize, danger: 2, who: coreIn !== undefined ? "core" : "sup", why: mode !== "shove" ? "mode" : !anyIn ? "nobody" : undefined });
    // The reset wave (R2) brings the clash back to the target before the support leaves; already inside the band, a
    // pre-deny alone (design s5.5 rule 1). `forward` takes the shove under `shove`, the idle swing's setup otherwise (slice 2b,
    // user 06/11/2026: hit an enemy creep into our last-hit range while no enemy hero can deny it). Slice 2c: their wave
    // absent refuses our pull first.
    const mw = MissingWave(ew, intent, n45, s.Band, offered);
    for (const l of mw.levers) levers.push(l);
    const c = mw.choice;
    const left = c.left;
    // The core's hold catches a pull that would leave the next clash under our tower (design s5.3: a pull and the hold go
    // together).
    const chosen = c.levers.map((l) => l.name);
    const who = c.levers.map((l) => l.who);
    let after = tgt + left;
    // Not when the core is the puller: it cannot hold their wave from the camp.
    if (chosen.includes("pull") && after < reach && coreIn !== undefined && puller.by !== "core") {
        chosen.push("hold");
        who.push(`${coreIn.pid}`);
        after = math.max(after, reach);
    }
    const rej: string[] = [];
    for (const l of levers) if (l.why !== undefined) rej.push(`${l.name}:${l.why}`);
    const ms = started !== undefined ? math.floor((clock!() - started) * 10000 + 0.5) / 10 : undefined;
    m.chks.push(ts);
    const yields = chosen.includes("pull") ? pc?.yld : undefined;
    const d: Decision = { wave: ts, at: now, rule, mode, intent, levers: chosen, who, cx, cy, core: coreIn?.unit, yields, ew };
    Remember(team, lane, d);
    Telemetry.Event("lane_ctl", [
        ["team", team],
        ["lane", lane],
        ["kind", "wave"],
        ["wave", ts],
        ["mode", mode],
        ["rule", rule],
        ["tgt", round(tgt)],
        ["own", round(r.own)],
        ["mv", round(r.move)],
        ["st", r.state],
        ["need", round(need)],
        ["m45", round(plain)],
        ["p45", round(gone?.own)],
        ["pe", round(pe)],
        ["n45", round(n45)],
        ["intent", intent],
        ["lever", chosen.length > 0 ? chosen.join("+") : "none"],
        ["who", who.join("+")],
        ["left", round(after - tgt)],
        ["short", c.short ? true : undefined],
        ["rej", rej.join(";")],
        ["core", coreIn !== undefined ? coreIn.pid : undefined],
        ["sup", supIn !== undefined ? supIn.pid : undefined],
        ["dep", round(dep)],
        ["fit", pc?.fit],
        ["yld", yields],
        ["pby", puller.by],
        ["cwhy", puller.cwhy],
        ["cmiss", coreCand?.missing],
        ["closs", round(coreCand?.loss)],
        ["away", away ? true : undefined],
        ["ms", ms],
        ["ew", ew],
        ["ewp", mw.ewp],
        ["ewd", fact !== undefined && fact.due !== undefined ? fact.due - fact.ts : undefined],
    ]);
}

function check(team: number, lane: Lane, wave: number): void {
    const r = LanePush.Read(team, lane);
    Telemetry.Event("lane_ctl", [
        ["team", team],
        ["lane", lane],
        ["kind", "chk"],
        ["wave", wave],
        ["own", round(r?.own)],
        ["mv", round(r?.move)],
        ["st", r?.state],
    ]);
}

/** Stores a wave's decision for the levers' owners (decide's, and the tests'); the last few waves are kept. */
export function Remember(team: number, lane: Lane, d: Decision): void {
    const m = memoryOf(team, lane);
    m.decisions[d.wave] = d;
    m.last = d;
    for (const k in m.decisions) if (tonumber(k)! < d.wave - 120) delete m.decisions[tonumber(k)!];
}

/** Slice 2c: records what the lane's tracker found up (Tick's, and the tests'). */
export function NoteSuspect(team: number, lane: Lane, s: Suspicion): void {
    memoryOf(team, lane).suspect = s;
}

/**
 * Slice 2c: their wave resolved absent between reads. The live decision for `wave` (this cycle's; an older one's pull is past
 * its slot) loses its pull when the puller's slot is not settled (`PullJob.Settled`: not handled, not running; a pull
 * decided but waiting at a gate re-reads the decision and refuses `ew`), with the core's `hold` that only a pull adds; the
 * mode, the intent and the ruleset's other levers stay. Logged `kind=break why=ew` as the R5 shove break is. A settled pull
 * is left alone and nothing is logged. Returns whether the pull was removed.
 */
export function PullBreak(team: number, lane: Lane, now: number, wave: number, settled: (pid: number, wave: number) => boolean): boolean {
    const d = Current(team, lane, now);
    if (d === undefined || d.wave !== wave) return false;
    const i = d.levers.indexOf("pull");
    if (i < 0) return false;
    const pid = tonumber(d.who[i]);
    if (pid !== undefined && settled(pid, d.wave)) return false;
    for (const name of ["pull", "hold"]) {
        const k = d.levers.indexOf(name);
        if (k >= 0) {
            d.levers.splice(k, 1);
            d.who.splice(k, 1);
        }
    }
    d.yields = undefined;
    breakLog(team, lane, d, "ew");
    return true;
}

function pullSettled(pid: number, wave: number): boolean {
    const PullJob = require("bots/FunLib/humaniser/pull_job") as typeof import("bots/FunLib/humaniser/pull_job");
    return PullJob.Settled(pid, wave);
}

function breakLog(team: number, lane: Lane, d: Decision, why: string): void {
    d.broke = why;
    Telemetry.Event("lane_ctl", [
        ["team", team],
        ["lane", lane],
        ["kind", "break"],
        ["wave", d.wave],
        ["why", why],
    ]);
}


/** Slice 2c: the lane's most recent suspicion within SuspectFor s of `now`, undefined when none or aged out. */
export function Suspect(team: number, lane: Lane, now: number = DotaTime()): Suspicion | undefined {
    const s = memory[`${team}:${lane}`]?.suspect;
    return s !== undefined && now - s.t <= SETTINGS.SuspectFor ? s : undefined;
}

/** Slice 3: the live decision's pull takes this support's stack minute `minute`. */
export function YieldsStack(team: number, lane: Lane, pid: number, minute: number): boolean {
    const d = Current(team, lane);
    if (d === undefined || d.yields !== minute) return false;
    for (let i = 0; i < d.levers.length; i++) if (d.levers[i] === "pull" && d.who[i] === `${pid}`) return true;
    return false;
}

/** Slice 2b's sub-switch: the decision drives the levers (off: shadow, 2a's behaviour). */
export function Drives(): boolean {
    return Ours.On("LaneControl") && Ours.On("LaneControlDrive");
}

/** The decision made for the wave that spawned at `wave` (a pull's pulled wave), while the controller drives. */
export function DecisionFor(team: number, lane: Lane, wave: number): Decision | undefined {
    if (!Drives()) return undefined;
    return memory[`${team}:${lane}`]?.decisions[wave];
}

/** The lane's live decision (this wave's, until the next read), while the controller drives. */
export function Current(team: number, lane: Lane, now: number = DotaTime()): Decision | undefined {
    if (!Drives()) return undefined;
    const d = memory[`${team}:${lane}`]?.last;
    return d !== undefined && now - d.at <= SETTINGS.Live ? d : undefined;
}

/** The lane's mode for the idle swing: the live decision's, `safe` with none. */
export function ModeFor(team: number, lane: Lane): Mode {
    return Current(team, lane)?.mode ?? "safe";
}

/** Whether `lever` is in the lane's live decision; undefined with none (the owner's own trigger then decides). */
export function Chosen(team: number, lane: Lane, lever: string): boolean | undefined {
    const d = Current(team, lane);
    return d === undefined ? undefined : d.levers.includes(lever);
}

/** An enemy hero seen (visible, alive, not an illusion) within EnemyAway of the clash: the shove's break. Vision loss is no
 *  break (review 2026-11-06-lane-control-2b H1: every R5 shove in lctl2 broke 0-13 s in when `enemiesAway` read a hero out of
 *  vision as near). */
export function EnemySeenNear(heroes: { x: number; y: number }[], cx: number, cy: number, r: number): boolean {
    for (const h of heroes) if ((h.x - cx) ** 2 + (h.y - cy) ** 2 <= r * r) return true;
    return false;
}

function seenEnemies(): { x: number; y: number }[] {
    const out: { x: number; y: number }[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e === null || e === undefined || e.IsNull() || !e.IsAlive() || e.IsIllusion() || !e.CanBeSeen()) continue;
        const at = e.GetLocation();
        out.push({ x: at.x, y: at.y });
    }
    return out;
}

/** Commitment's breaking events for a `shove` mode (s5.1b): an enemy hero seen near the clash, or the core low or dead. */
function breakCheck(team: number, lane: Lane, m: LaneMemory, now: number): void {
    const d = m.last;
    if (d === undefined || d.mode !== "shove" || now - d.at > SETTINGS.Live) return;
    if (m.breakAt !== undefined && now - m.breakAt < SETTINGS.BreakEvery) return;
    m.breakAt = now;
    let why: string | undefined;
    if (EnemySeenNear(seenEnemies(), d.cx, d.cy, SETTINGS.EnemyAway)) why = "enemy";
    else if (d.core !== undefined && !d.core.IsNull() && (!d.core.IsAlive() || d.core.GetHealth() / math.max(1, d.core.GetMaxHealth()) < SETTINGS.CoreLowHp))
        why = "core_low";
    if (why === undefined) return;
    d.mode = "safe";
    d.levers = d.levers.filter((l) => l !== "shove");
    breakLog(team, lane, d, why);
}

/**
 * Called every frame by every hero of the team: the first call in a lane's read second decides that lane's wave (each lane the
 * team has a hero assigned to), and the first call Horizon s after a decision logs its check.
 */
export function Tick(bot: Unit): void {
    if (!Ours.On("LaneControl")) return;
    const now = DotaTime();
    const s = SETTINGS;
    if (now < 0 || now > s.Until + s.Horizon) return;
    const team = bot.GetTeam();
    if (team !== Team.Radiant && team !== Team.Dire) return;
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Mid && lane !== Lane.Bot) return;
    const m = memoryOf(team, lane);
    const cycle = LaneConfig.Settings().Timing.WaveCycle;
    const wave = math.floor(now / cycle) * cycle;
    // Slice 2c: the enemy wave tracker steps once a second from the first spawn, so the first read at From has a resolution.
    // Absent between reads: the lane's suspect fact, and this wave's chosen pull is broken if it has not left. In a read
    // second (this wave's decision not made yet) the resolution is left for the read below, which takes it as `ew`.
    if (now <= s.Until) {
        const res = EnemyWave.Tick(team, lane, now);
        if (res !== undefined && res.ew === "a") {
            NoteSuspect(team, lane, { kind: "their_wave_missing", t: now });
            if (Drives() && m.wave === wave) PullBreak(team, lane, now, wave, pullSettled);
        }
    }
    if (now < s.From) return;
    while (m.chks.length > 0 && now >= m.chks[0] + s.ReadAt + s.Horizon) check(team, lane, m.chks.shift()!);
    if (Drives()) breakCheck(team, lane, m, now);
    if (now > s.Until || now - wave < s.ReadAt || m.wave === wave) return;
    m.wave = wave;
    decide(team, lane, now, m);
}
