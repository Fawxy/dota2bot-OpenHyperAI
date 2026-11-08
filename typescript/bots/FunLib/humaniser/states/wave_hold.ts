/**
 * The wave hold (slice core-in-lane, `Ours.CoreHold`; docs/proposals/2026-11-05-pull-effect.md s4 step 2, design by the user
 * 05/11/2026): when our wave on an in-lane core's lane is gone (pulled, drawn away by lane aggro's tower move, or anything
 * else) and theirs walks in, the core meets it at the lane's target point (lane_push TargetOf) instead of letting it die to
 * our T1. The trigger is the event, never the reason (logged as `why`).
 * The branch (user 08/11/2026, from drill `hold`: a lone core in front of their whole wave lost 40-90% HP in 20 s):
 * - `hold`: the wave's expected damage on the core until our creeps reach the hold point is within TankShare of its max HP
 *   (our creeps arrive soon, or the core can soak it); the target point is lane_spot's named input `hold`; the body keeps
 *   last hitting from that spot.
 * - `drag`: otherwise, when our next wave is far enough that their creeps can be taken behind our T1 first: lane_aggro's
 *   draw `back` walks them there to meet it.
 * - otherwise the attempt ends `concede`: their wave reaches our T1 and the core last hits under it.
 * - `retreat`: OHA's retreat took the core.
 * Two starts (logged as `trig`, decided 06/11/2026 from obs0611 marks 4 and 5): `gone`, our wave is gone from the lane outside
 * our T1's range; `forecast`, our wave is still fighting theirs at or inside the hold point and lane_push's run has their front
 * inside our T1's fire within ForecastSecs, so the core is in front before our wave dies.
 * One ev=wave_hold line per attempt, at its end. Stepped from the core draw step (States.CoreAggroStep, H1), before lane
 * aggro's own step; States.Tick ends an attempt whose caller lost the frame.
 */
import { BotMode, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import type { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as LaneAggro from "bots/FunLib/humaniser/lane_aggro";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";

// Every number is `judgement` (slice core-in-lane, Decisions 05/11/2026).
function creepSpeed(): number {
    return WorldFacts.Latest("lane_creep_speed", SETTINGS.CreepSpeed);
}

export const SETTINGS = {
    Every: 0.25,
    /** Lane creeps within this of the lane path count as on the lane. */
    PathR: 600,
    /** Their wave: at least MinCreeps creeps from our T1 to StartAhead past the target point. */
    MinCreeps: 2,
    StartAhead: 1600,
    /** Our T1's listed attack range (game files), for the reads that count creeps "under our T1" (Read's busy rule, the
     *  forecast, `tw`, the `tower` end). */
    TowerR: 700,
    /**
     * The user's rule (06/11/2026): the hold keeps their creeps just outside tower fire. The tower hits a creep whose centre
     * is within its attack range plus both hull radii (hschk2 8:25 top: their creep at 792-795 from our T1's centre was shot
     * dead). The reach comes from the API (our T1's GetAttackRange and GetBoundingRadius, a creep's GetBoundingRadius), these
     * fallbacks when it gives nothing: range 700 (npc_units.txt), hulls DOTA_HULL_SIZE_TOWER 144 and DOTA_HULL_SIZE_REGULAR
     * 16. Their front within LateMargin past that reach is too late to start; the hold point is never nearer our T1 than it.
     * LateMargin is `judgement`.
     */
    TowerHull: 144,
    CreepHull: 16,
    LateMargin: 50,
    /**
     * Our wave is gone when none of our lane creeps stands from OursBehind behind our T1 to OursAhead past their rearmost creep
     * in the stretch, not counting one inside TowerR that is already fighting. chold1 0:31 mid: their front creeps chased past
     * a clash still running 1,000 further out; a window on their front alone read that as our wave gone. obs0611 marks 4 and
     * 5: a lone creep of ours fighting inside our T1's range (a pull returnee at 666, a ranged creep at 512) kept the hold off
     * until their front was late. A fresh wave walking out under our T1 still counts (63 banked replays: ignoring it too
     * started 154 holds 10 s or more before their creeps reached our T1, 24 when it counts).
     */
    OursBehind: 400,
    OursAhead: 600,
    /** The waves met: one of ours this close to their nearest creep. */
    MeetR: 700,
    /** The core is near enough to hold (from the hold point) and healthy enough to start. */
    Reach: 2000,
    StartHp: 0.5,
    /** A hero within lane_spot HeroReach plus this of the core or the hold point threatens it. */
    ThreatMargin: 200,
    /**
     * Our next wave is near when it reaches the hold point within NearSecs: no drag, the waves meet at the hold. It counts the
     * spawn schedule and our lane creeps already on the map with no attack target at creep speed in a straight line (creeps
     * back from a pull camp, a wave late off the schedule). ptchk1 A 7:00 top: the pulled creeps walked back from the camp
     * while the schedule said 24 s; the drag took their wave from 1,195 to 790 from our T1 just as ours met it.
     */
    NearSecs: 10,
    /**
     * The drag's point: at least this far behind our T1 along the lane, and out of its fire (the reach plus LateMargin); its
     * time: their front's walk there at creep speed plus DrawSecs, done DragMargin before our creeps reach that point. The
     * user's rule (06/11/2026, hschk3 1:45, Luna dragged their wave under our T1 onto our creeps back from a pull): the drag
     * walks them through tower fire only when they meet our creeps behind the T1 out of its reach; a creep of ours already
     * between the drag point and their front would meet them in its fire, so the core holds at the hold point instead. No
     * route around the T1: its lane is walled by trees and cliffs, and the hold point is the simpler fallback.
     */
    Behind: 500,
    /** Fallback only: the lane creeps' speed is read live (WorldFacts.Latest). */
    CreepSpeed: 325,
    DrawSecs: 1,
    DragMargin: 2,
    /** Ends: HurtShare of max HP lost since the start, or under HurtFloor; not stepped for LeftAfter; MaxSecs. */
    HurtShare: 0.25,
    HurtFloor: 0.35,
    LeftAfter: 3,
    /** No new attempt this long after one ended other than `left` (a hurt or lost hold does not restart on the same wave). */
    RestAfter: 15,
    MaxSecs: 45,
    /** A drag that reached its point behind our T1 waits there. */
    Arrived: 300,
    /** A lane-aggro tower move that ended this recently is why our wave is gone. */
    AggroRecent: 20,
    /** The forecast start: read at most every ForecastEvery while our wave is there and their front within ForecastAhead past
     *  the hold point's ceiling (the lane target or the floor, whichever is further; `judgement`, since the side target 900
     *  lies inside the floor); it starts when lane_push's run puts their front inside tower fire (the reach) within ForecastSecs. */
    ForecastAhead: 200,
    ForecastEvery: 1,
    ForecastSecs: 8,
    /** One ev=wave_hold_skip per bot and reason at most this often. */
    SkipEvery: 5,
    /**
     * The hold takes their wave's aggro (hschk3: 16 of 37 holds ended `tower`; standing at the point, the core let their creeps
     * walk past it, decided 06/11/2026): once their front is within HoldDrawLead seconds' walk of the hold point and the core
     * stands within HoldNear of it with no creep of theirs on it, lane_aggro's draw (StartBack) walks it HoldDrawOut further out,
     * so they fight it at the hold point, out of our T1's fire. `judgement`.
     */
    HoldDrawLead: 1,
    HoldNear: 300,
    HoldDrawOut: 150,
    /** The hold's budget: the wave's expected damage on the core until our creeps reach the hold point, as a share of its max
     *  HP (`judgement`, under HurtShare so a hold that goes as expected does not end `hurt`). */
    TankShare: 0.15,
    /** Fallback only: a lane creep's seconds per attack (base attack time 1.0, npc_units.txt), read live by GetSecondsPerAttack. */
    CreepSpa: 1,
};

/** API reads not in the typings (the Valve bot API has them). */
type Attacker = Unit & { GetSecondsPerAttack?(): number; GetArmor?(): number; IsTower?(): boolean };

export type Branch = "hold" | "drag" | "retreat";

/** Their wave in the stretch (our T1 distances, positive towards theirs): its count, front and rear. */
export function Stretch(theirs: number[], target: number): { n: number; front: number; rear: number } {
    let n = 0;
    let front = math.huge;
    let rear = -math.huge;
    for (const o of theirs) {
        if (o < -SETTINGS.OursBehind || o > target + SETTINGS.StartAhead) continue;
        n++;
        front = math.min(front, o);
        rear = math.max(rear, o);
    }
    return { n, front, rear };
}

/**
 * Pure: the trigger's reading of a lane, from our T1 distances (positive towards theirs) of the lane creeps on it; `busy[i]`
 * when ours[i] has an attack target.
 */
export function Read(theirs: number[], ours: number[], target: number, busy: boolean[] = [], reach = EffReach()): { front: number; n: number } | string {
    const w = Stretch(theirs, target);
    if (w.n < SETTINGS.MinCreeps) return "none";
    for (let i = 0; i < ours.length; i++) {
        const o = ours[i];
        if (o < SETTINGS.TowerR && busy[i] === true) continue;
        if (o >= -SETTINGS.OursBehind && o <= w.rear + SETTINGS.OursAhead) return "ours";
    }
    if (w.front < reach + SETTINGS.LateMargin) return "late";
    return { front: w.front, n: w.n };
}

/** Pure: our T1's fire reach to a creep's centre (`reach` in the docs), from the API's values or the fallbacks. */
export function EffReach(range?: number, towerHull?: number, creepHull?: number): number {
    const ok = (x: number | undefined, d: number) => (x !== undefined && x > 0 ? x : d);
    return ok(range, SETTINGS.TowerR) + ok(towerHull, SETTINGS.TowerHull) + ok(creepHull, SETTINGS.CreepHull);
}

/** Pure: the hold point's distance from our T1 for the lane target and their front at the start: never past their front, never
 *  inside LateMargin past the tower's reach. */
export function HoldAt(target: number, front: number, reach = EffReach()): number {
    return math.max(reach + SETTINGS.LateMargin, math.min(target, front));
}

/** Pure: whether a creep of ours at `own` is in the clash at the start (fighting, within our-wave reach of their rear), so
 *  its fight does not end the attempt as `met`. Our next wave walking up is not. */
export function InClash(own: number, busy: boolean, rear: number): boolean {
    return busy && own >= -SETTINGS.OursBehind && own <= rear + SETTINGS.OursAhead;
}

/**
 * Pure: seconds from `t0` until lane_push's run (`samples`) has `enemy`'s front inside our T1's range, within ForecastSecs;
 * undefined when it stays out. `t1` and `dir` are our T1 on the path and the sign towards theirs.
 */
export function TowerIn(samples: LanePush.Sample[], t1: number, dir: number, enemy: number, t0: number, reach = EffReach()): number | undefined {
    for (const smp of samples) {
        if (smp.t - t0 > SETTINGS.ForecastSecs) break;
        const f = smp.front[enemy];
        if (f !== undefined && dir * (f - t1) < reach) return smp.t - t0;
    }
    return undefined;
}

/**
 * Pure: the branch (user 05/11/2026). `threat` an enemy hero's move on the core; `near` seconds until our next wave reaches the
 * hold point; `need` seconds the drag needs; `behind` seconds until our next wave reaches the drag's point.
 */
export function Choose(cost: number, budget: number, need: number, behind: number): Branch | "concede" {
    if (cost <= budget) return "hold";
    return need + SETTINGS.DragMargin <= behind ? "drag" : "concede";
}

/** Pure: seconds the core stands as their wave's target at the hold point `hd` before our creeps get there: our creeps' time
 *  to the hold point `near` less their front's walk to it. */
export function TankSecs(near: number, front: number, hd: number): number {
    return math.max(0, near - math.max(0, front - hd) / creepSpeed());
}

/** Pure: the physical damage a unit with armor `a` takes per point dealt (Dota's armor formula, 1 - 0.06a / (1 + 0.06|a|)). */
export function ArmorMult(a: number): number {
    return 1 - (0.06 * a) / (1 + 0.06 * math.abs(a));
}

/** Pure: the wave's damage per second on one target, from each creep's attack damage and seconds per attack. */
export function WaveDps(creeps: { dmg: number; spa: number }[], armorMult: number): number {
    let s = 0;
    for (const c of creeps) if (c.spa > 0) s += c.dmg / c.spa;
    return s * armorMult;
}

/** Pure: seconds until our next wave reaches the hold point, from the spawn schedule's `schedule` and the straight-line
 *  distances to it of our lane creeps already on the map and walking. */
export function Near(schedule: number, live: number[]): number {
    let d = math.huge;
    for (const x of live) d = math.min(d, x);
    return math.min(schedule, d / creepSpeed());
}

/** Pure: whether the hold draws their wave now: their front (from our T1) within the lead of the hold point `hd`, the core
 *  `at` from it, `on` their creeps already on the core. */
export function DrawNow(front: number, hd: number, at: number, on: number): boolean {
    return on === 0 && at <= SETTINGS.HoldNear && front <= hd + SETTINGS.HoldDrawLead * creepSpeed();
}

/**
 * Pure: lane_spot pushed the held spot back inside the hold point's floor for an enemy hero (`why` hero, spot `own` from our
 * T1) while their front is within HoldDrawLead seconds' walk of the floor: the hold cannot stand where it keeps their wave out
 * of our T1's fire, so it ends `unsafe`. Further out the hold runs on from the pushed spot (hschk4: 7 of 13 unsafe ends were
 * Zeus mid stepping out of Sniper's reach with their front 1,100-1,440 out; user 06/11/2026: stepping back from a hero's reach
 * is right, the hold point would give Sniper free harass).
 */
export function Unsafe(anchor: string | undefined, why: string | undefined, own: number, reach: number, front: number): boolean {
    const floor = reach + SETTINGS.LateMargin;
    return anchor === "hold" && why === "hero" && own < floor && front <= floor + SETTINGS.HoldDrawLead * creepSpeed();
}

/** Pure: the drag point's distance behind our T1: out of its fire for every creep (`reach` plus LateMargin). */
export function BehindAt(reach = EffReach()): number {
    return math.max(SETTINGS.Behind, reach + SETTINGS.LateMargin);
}

/** Pure: the seconds the drag needs from their front's distance from our T1, to the drag point `bd` behind it. */
export function DragSecs(front: number, bd = SETTINGS.Behind): number {
    return (front + bd) / creepSpeed() + SETTINGS.DrawSecs;
}

/**
 * Pure: seconds until a creep of ours on the lane (our T1 distances) reaches the drag point `bd` behind our T1; 0 when one
 * already stands between it and their front, where it would meet their dragged wave inside our T1's fire.
 */
export function OursAtBehind(ours: number[], bd: number, front: number): number {
    let s = math.huge;
    for (const o of ours) {
        if (o > front) continue;
        s = math.min(s, o >= -bd ? 0 : (-bd - o) / creepSpeed());
    }
    return s;
}

interface Attempt {
    lane: Lane;
    br: Branch;
    sw: number;
    startedAt: number;
    steppedAt: number;
    hold: Vector;
    behind: Vector;
    why: string;
    trig: string;
    fc?: number;
    hd: number;
    rch: number;
    /** The drag point's distance behind our T1. */
    bd: number;
    /** Hold draws given (lane_aggro StartBack on the hold branch). */
    hdr: number;
    /** Our creeps already fighting at the start that do not end it as `met` (the losing wave, a lone creep under the T1). */
    old: Unit[];
    n: number;
    lh0: number;
    dn0: number;
    own0: number;
    omin: number;
    mo?: number;
    tw: number;
    tgt: number;
    nw: number;
    ds?: number;
    nb?: number;
    nl?: number;
    lv?: number;
    /** At the last branch read: tank seconds, expected damage, budget. */
    tk?: number;
    cost?: number;
    bud?: number;
    thr?: number;
    hp0: number;
    hpMin: number;
    readAt: number;
}

const attempts: Record<number, Attempt | undefined> = {};
const decidedAt: Record<number, number | undefined> = {};
const endedAt: Record<number, number | undefined> = {};
const skippedAt: Record<string, number | undefined> = {};
const forecastAt: Record<number, number | undefined> = {};

function counter(bot: Unit, name: "GetLastHits" | "GetDenies"): number {
    const f = (bot as any)[name];
    return f !== undefined ? (f(bot) as number) : 0;
}

function frac(u: Unit): number {
    return u.GetHealth() / math.max(1, u.GetMaxHealth());
}

/** Whether the hold may act for this bot: the switches, an in-lane core under CoreLastHit with our spot. */
export function Owns(bot: Unit): boolean {
    return Ours.On("CoreHold") && Ours.On("LaneSpot") && CoreLastHit.Applies(bot) && bot.IsAlive() && Phase.IsLaningFor(bot);
}

const T1_OF: Record<number, Tower> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

/** Our T1's reach on this lane from the API, with a creep of theirs (when one is in view) for the creep hull. */
function towerReach(team: number, lane: Lane, v: LaneView): number {
    const t = GetTower(team, T1_OF[lane]);
    const alive = t !== undefined && t !== null && !t.IsNull() && t.IsAlive();
    const c = v.units.length > 0 ? v.units[0].u : undefined;
    return EffReach(alive ? t.GetAttackRange() : undefined, alive ? t.GetBoundingRadius() : undefined, c !== undefined ? c.GetBoundingRadius() : undefined);
}

function fighting(c: Unit): boolean {
    const t = c.GetAttackTarget();
    return t !== undefined && t !== null && !t.IsNull();
}

interface LaneView {
    path: LanePath;
    t1: number;
    dir: number;
    theirs: number[];
    ours: number[];
    busy: boolean[];
    /** Their creeps on the lane with their distance from our T1. */
    units: { u: Unit; own: number }[];
    /** Ours likewise. */
    mine: { u: Unit; own: number }[];
}

function viewOf(team: number, lane: Lane): LaneView | undefined {
    const path = LanePush.PathOf(lane);
    if (path === undefined) return undefined;
    const [t1, dir] = LanePush.OwnT1(path, team);
    const project = (list: Unit[], keep?: { u: Unit; own: number }[]): number[] => {
        const out: number[] = [];
        for (const c of list) {
            if (c === undefined || c === null || c.IsNull() || !c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
            const l = c.GetLocation();
            if (l === undefined) continue;
            const [s, d] = LanePush.Project(path, l.x, l.y);
            if (d > SETTINGS.PathR) continue;
            const own = dir * (s - t1);
            out.push(own);
            keep?.push({ u: c, own });
        }
        return out;
    };
    const units: { u: Unit; own: number }[] = [];
    const theirs = project(GetUnitList(UnitType.EnemyCreeps), units);
    const mine: { u: Unit; own: number }[] = [];
    const ours = project(GetUnitList(UnitType.AlliedCreeps), mine);
    const busy = mine.map((m) => fighting(m.u));
    return { path, t1, dir, theirs, ours, busy, units, mine };
}

function pointAt(v: LaneView, own: number, z: number): Vector {
    const [x, y] = LanePush.PointAt(v.path, v.t1 + v.dir * own);
    return Vector(x, y, z);
}

/** Distances to the hold point of our lane creeps within NearSecs' walk of it that have no attack target. */
function walkingTo(hold: Vector): number[] {
    const out: number[] = [];
    const r = SETTINGS.NearSecs * creepSpeed();
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (c === undefined || c === null || c.IsNull() || !c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        const t = c.GetAttackTarget();
        if (t !== undefined && t !== null && !t.IsNull()) continue;
        const d = GetUnitToLocationDistance(c, hold);
        if (d <= r) out.push(d);
    }
    return out;
}

function whyGone(bot: Unit, now: number): string {
    const lane = bot.GetAssignedLane();
    for (let i = 1; i <= 5; i++) {
        const h = GetTeamMember(i);
        if (h === undefined || h === null || h.IsNull()) continue;
        if (h.GetAssignedLane() === lane && PullJob.Running(h)) return "pull";
    }
    const at = LaneAggro.TowerMovedAt(bot.GetPlayerID());
    if (at !== undefined && now - at <= SETTINGS.AggroRecent) return "aggro";
    return "other";
}

/** The visible enemy hero whose reach covers the core or the hold point, if any. */
function threatOf(bot: Unit, hold: Vector): Unit | undefined {
    for (const h of bot.GetNearbyHeroes(1600, true, BotMode.None)) {
        if (h === undefined || h === null || h.IsNull() || !h.IsAlive() || h.IsIllusion()) continue;
        const r = LaneSpot.HeroReach(bot, h) + SETTINGS.ThreatMargin;
        if (GetUnitToUnitDistance(bot, h) <= r || GetUnitToLocationDistance(h, hold) <= r) return h;
    }
    return undefined;
}

function finish(bot: Unit, a: Attempt, res: string, now: number): void {
    const pid = bot.GetPlayerID();
    attempts[pid] = undefined;
    if (res !== "left") endedAt[pid] = now;
    Laning.SetHold(bot, undefined);
    Telemetry.Event("wave_hold", [
        ["pid", pid],
        ["lane", a.lane],
        ["br", a.br],
        ["res", res],
        ["why", a.why],
        ["trig", a.trig],
        ["fc", a.fc !== undefined ? math.floor(a.fc * 10) / 10 : undefined],
        ["hd", math.floor(a.hd)],
        ["rch", math.floor(a.rch)],
        ["hdr", a.hdr],
        ["n", a.n],
        ["lh", counter(bot, "GetLastHits") - a.lh0],
        ["dn", counter(bot, "GetDenies") - a.dn0],
        ["own0", math.floor(a.own0)],
        ["omin", math.floor(a.omin)],
        ["mo", a.mo !== undefined ? math.floor(a.mo) : undefined],
        ["tw", a.tw],
        ["tgt", a.tgt],
        ["nw", math.floor(a.nw * 10) / 10],
        ["ds", a.ds !== undefined ? math.floor(a.ds * 10) / 10 : undefined],
        ["nb", a.nb !== undefined ? math.floor(a.nb * 10) / 10 : undefined],
        ["nl", a.nl !== undefined ? math.floor(a.nl * 10) / 10 : undefined],
        ["lv", a.lv],
        ["tk", a.tk !== undefined ? math.floor(a.tk * 10) / 10 : undefined],
        ["cost", a.cost !== undefined ? math.floor(a.cost) : undefined],
        ["bud", a.bud !== undefined ? math.floor(a.bud) : undefined],
        ["thr", a.thr],
        ["sw", a.sw],
        ["hp", math.floor((a.hp0 / math.max(1, bot.GetMaxHealth())) * 100) / 100],
        ["dhp", a.hp0 - a.hpMin],
        ["dur", math.floor((now - a.startedAt) * 100) / 100],
        ["md", res === "left" || res === "died" ? bot.GetActiveMode() : undefined],
    ]);
}

/** Every frame (States.Tick): an attempt whose caller lost the frame ends, `retreat` when OHA's retreat holds the core. */
export function Tick(bot: Unit): void {
    const a = attempts[bot.GetPlayerID()];
    if (a === undefined) return;
    const now = DotaTime();
    if (!bot.IsAlive()) return finish(bot, a, "died", now);
    if (now - a.steppedAt <= SETTINGS.LeftAfter) return;
    if (bot.GetActiveMode() === BotMode.Retreat) a.br = "retreat";
    finish(bot, a, "left", now);
}

/** Why a start was refused (`reach`, `hp`), or the attempt. */
function begin(bot: Unit, v: LaneView, front: number, n: number, rear: number, reach: number, now: number, trig: string, fc: number | undefined): Attempt | string {
    const lane = bot.GetAssignedLane();
    const tgt = LanePush.TargetOf(lane);
    const z = bot.GetLocation().z;
    const hd = HoldAt(tgt, front, reach);
    const hold = pointAt(v, hd, z);
    if (GetUnitToLocationDistance(bot, hold) > SETTINGS.Reach) return "reach";
    if (frac(bot) < SETTINGS.StartHp) return "hp";
    const nw = LanePush.NextArrival(v.path, bot.GetTeam(), v.t1 + v.dir * hd, now) - now;
    const old: Unit[] = [];
    for (let i = 0; i < v.mine.length; i++) if (InClash(v.mine[i].own, v.busy[i], rear)) old.push(v.mine[i].u);
    return {
        lane,
        br: "hold",
        sw: 0,
        startedAt: now,
        steppedAt: now,
        hold,
        behind: pointAt(v, -BehindAt(reach), z),
        bd: BehindAt(reach),
        hdr: 0,
        why: trig === "forecast" ? "losing" : whyGone(bot, now),
        trig,
        fc,
        hd,
        rch: reach,
        old,
        n,
        lh0: counter(bot, "GetLastHits"),
        dn0: counter(bot, "GetDenies"),
        own0: front,
        omin: front,
        tw: 0,
        tgt,
        nw,
        hp0: bot.GetHealth(),
        hpMin: bot.GetHealth(),
        readAt: -math.huge,
    };
}

/** One ev=wave_hold_skip per bot and reason per SkipEvery. */
function skip(bot: Unit, v: LaneView, why: string, front: number, n: number, reach: number, now: number, fc?: number): void {
    const key = `${bot.GetPlayerID()}:${why}`;
    const at = skippedAt[key];
    if (at !== undefined && now - at < SETTINGS.SkipEvery) return;
    skippedAt[key] = now;
    let on = 0;
    let oin = 0;
    for (const o of v.ours) {
        if (o < -SETTINGS.OursBehind) continue;
        if (o < SETTINGS.TowerR) oin++;
        else on++;
    }
    // ours: the first creep of ours that keeps the start off (Read's rule), its distance and what it attacks
    let ob: number | undefined;
    let obt: string | undefined;
    if (why === "ours" || why === "ours_far") {
        const w = Stretch(v.theirs, LanePush.TargetOf(bot.GetAssignedLane()));
        for (let i = 0; i < v.mine.length; i++) {
            const o = v.mine[i].own;
            if (o < SETTINGS.TowerR && v.busy[i]) continue;
            if (o >= -SETTINGS.OursBehind && o <= w.rear + SETTINGS.OursAhead) {
                ob = o;
                const t = v.mine[i].u.GetAttackTarget();
                obt = t === undefined || t === null || t.IsNull() ? "none" : t.IsHero() ? "hero" : (t as Attacker).IsTower?.() === true ? "tower" : LanePush.IsLaneCreep(t.GetUnitName()) ? "lane" : "other";
                break;
            }
        }
    }
    Telemetry.Event("wave_hold_skip", [
        ["pid", bot.GetPlayerID()],
        ["lane", bot.GetAssignedLane()],
        ["why", why],
        ["front", math.floor(front)],
        ["n", n],
        ["on", on],
        ["oin", oin],
        ["rch", math.floor(reach)],
        ["fc", fc !== undefined ? math.floor(fc * 10) / 10 : undefined],
        ["ob", ob !== undefined ? math.floor(ob) : undefined],
        ["obt", obt],
    ]);
}

/** Whether no creep of ours on the lane is fighting a lane creep or a hero (their wave is walking in unopposed). */
function notOnWave(v: LaneView): boolean {
    for (const m of v.mine) {
        const t = m.u.GetAttackTarget();
        if (t !== undefined && t !== null && !t.IsNull() && (t.IsHero() || LanePush.IsLaneCreep(t.GetUnitName()))) return false;
    }
    return true;
}

/** lane_push's run for the forecast start, at most every ForecastEvery per bot: seconds until their front is inside our T1's
 *  range, or undefined (also when the run fails or was read too recently: `false`). */
function forecastIn(bot: Unit, v: LaneView, reach: number, now: number): number | undefined | false {
    const pid = bot.GetPlayerID();
    const at = forecastAt[pid];
    if (at !== undefined && now - at < SETTINGS.ForecastEvery) return false;
    forecastAt[pid] = now;
    const [ok, r] = pcall(() => {
        const [smp] = LanePush.Forecast(bot.GetTeam(), bot.GetAssignedLane(), SETTINGS.ForecastSecs + 1);
        return smp;
    });
    // Typed again: pcall's result is untyped, and TSTL shifts array indices only on array types.
    const samples = (ok ? r : undefined) as LanePush.Sample[] | undefined;
    if (samples === undefined || samples.length === 0) return undefined;
    const enemy = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    return TowerIn(samples, v.t1, v.dir, enemy, samples[0].t, reach);
}

/** The start read: an attempt, or undefined (a skip worth reading is logged). */
function tryStart(bot: Unit, now: number): Attempt | undefined {
    const pid = bot.GetPlayerID();
    const lane = bot.GetAssignedLane();
    const v = viewOf(bot.GetTeam(), lane);
    if (v === undefined) return undefined;
    const tgt = LanePush.TargetOf(lane);
    const reach = towerReach(bot.GetTeam(), lane, v);
    const r = Read(v.theirs, v.ours, tgt, v.busy, reach);
    const w = Stretch(v.theirs, tgt);
    let front: number;
    let n: number;
    let trig = "gone";
    let fc: number | undefined;
    if (typeof r === "string") {
        if (r !== "ours" && r !== "late") return undefined;
        // Only a wave near the hold point is worth a line or a forecast: further out the lanes are just fighting. A creep of
        // ours that keeps the start off while no creep of ours is on their wave is logged (`ours_far`; drill hold: holds
        // first read their front already late).
        if (w.front > math.max(tgt, reach + SETTINGS.LateMargin) + SETTINGS.ForecastAhead) {
            if (r === "ours" && notOnWave(v)) skip(bot, v, "ours_far", w.front, w.n, reach, now);
            return undefined;
        }
        if (r === "late") {
            skip(bot, v, "late", w.front, w.n, reach, now);
            return undefined;
        }
        if (w.front < reach + SETTINGS.LateMargin) {
            skip(bot, v, "ours", w.front, w.n, reach, now);
            return undefined;
        }
        const f = forecastIn(bot, v, reach, now);
        if (f === false) return undefined;
        if (f === undefined) {
            skip(bot, v, "ours", w.front, w.n, reach, now);
            return undefined;
        }
        front = w.front;
        n = w.n;
        trig = "forecast";
        fc = f;
    } else {
        front = r.front;
        n = r.n;
    }
    const ended = endedAt[pid];
    if (ended !== undefined && now - ended < SETTINGS.RestAfter) {
        skip(bot, v, "rest", front, n, reach, now, fc);
        return undefined;
    }
    const a = begin(bot, v, front, n, w.rear, reach, now, trig, fc);
    if (typeof a === "string") {
        skip(bot, v, a, front, n, reach, now, fc);
        return undefined;
    }
    return a;
}

/**
 * One frame for this core: starts, steps or ends the hold. It gives no order itself: the hold is the spot's input, the drag
 * lane_aggro's draw (stepped right after by the caller).
 */
export function Step(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let a = attempts[pid];
    if (a === undefined) {
        if (!Owns(bot)) return;
        const last = decidedAt[pid];
        if (last !== undefined && now - last < SETTINGS.Every) return;
        decidedAt[pid] = now;
        const started = tryStart(bot, now);
        if (started === undefined) return;
        a = started;
        attempts[pid] = a;
    }
    a.steppedAt = now;
    a.hpMin = math.min(a.hpMin, bot.GetHealth());
    if (!Owns(bot)) return finish(bot, a, "left", now);
    if ((a.hp0 - bot.GetHealth()) / math.max(1, bot.GetMaxHealth()) >= SETTINGS.HurtShare || frac(bot) < SETTINGS.HurtFloor) {
        return finish(bot, a, "hurt", now);
    }
    if (now - a.startedAt > SETTINGS.MaxSecs) return finish(bot, a, "timeout", now);
    if (now - a.readAt < SETTINGS.Every) return;
    a.readAt = now;
    const v = viewOf(bot.GetTeam(), a.lane);
    if (v === undefined) return finish(bot, a, "left", now);
    let front = math.huge;
    let nearest: Unit | undefined;
    for (const x of v.units) {
        if (x.own < -SETTINGS.OursBehind - a.bd || x.own > a.tgt + SETTINGS.StartAhead) continue;
        if (x.own < front) {
            front = x.own;
            nearest = x.u;
        }
    }
    if (nearest === undefined) return finish(bot, a, "cleared", now);
    a.omin = math.min(a.omin, front);
    if (front < SETTINGS.TowerR) a.tw = 1;
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (c === undefined || c === null || c.IsNull() || !c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        if (a.old.includes(c)) continue;
        if (GetUnitToUnitDistance(c, nearest) <= SETTINGS.MeetR) {
            a.mo = front;
            return finish(bot, a, "met", now);
        }
    }
    if (a.br === "hold" && front < SETTINGS.TowerR) return finish(bot, a, "tower", now);
    if (a.br === "hold") {
        const info = Laning.SpotInfo(bot);
        if (info !== undefined) {
            const [s] = LanePush.Project(v.path, info.spot.x, info.spot.y);
            if (Unsafe(info.anchor, info.why, v.dir * (s - v.t1), a.rch, front)) return finish(bot, a, "unsafe", now);
        }
    }

    const threat = threatOf(bot, a.hold);
    if (threat !== undefined) a.thr = threat.GetPlayerID();
    const wave: { dmg: number; spa: number }[] = [];
    for (const x of v.units) if (x.own >= -SETTINGS.OursBehind - a.bd && x.own <= a.tgt + SETTINGS.StartAhead) wave.push({ dmg: x.u.GetAttackDamage(), spa: (x.u as Attacker).GetSecondsPerAttack?.() ?? SETTINGS.CreepSpa });
    const dps = WaveDps(wave, ArmorMult((bot as Attacker).GetArmor?.() ?? 0));
    a.bud = SETTINGS.TankShare * bot.GetMaxHealth();
    const live = walkingTo(a.hold);
    a.nl = live.length > 0 ? Near(math.huge, live) : undefined;
    const sched = LanePush.NextArrival(v.path, bot.GetTeam(), v.t1 + v.dir * a.tgt, now) - now;
    const near = Near(sched, live);
    a.tk = TankSecs(near, front, a.hd);
    a.cost = dps * a.tk;
    a.ds = DragSecs(math.max(0, front), a.bd);
    a.nb = math.min(LanePush.NextArrival(v.path, bot.GetTeam(), v.t1 - v.dir * a.bd, now) - now, OursAtBehind(v.ours, a.bd, front));
    // A drag under way is lane_aggro's until its walk ends, and once behind our T1 the core waits there for our wave: the
    // branch is not read again meanwhile.
    const dragging = a.br === "drag" && (LaneAggro.Acting(bot) || GetUnitToLocationDistance(bot, a.behind) <= SETTINGS.Arrived);
    const br = dragging ? "drag" : Choose(a.cost, a.bud, a.ds, a.nb);
    if (br === "hold" && !dragging && Choose(dps * TankSecs(sched, front, a.hd), a.bud, a.ds, a.nb) !== "hold") a.lv = 1;
    if (br === "concede" || (br === "drag" && !dragging && !LaneAggro.StartBack(bot, a.behind))) return finish(bot, a, "concede", now);
    if (br !== a.br) {
        a.sw++;
        a.br = br;
    }
    // The hold point (the drag's point on the drag and retreat branches; OHA's retreat holds the frame on the latter) anchors
    // the spot for the whole attempt, over lane_spot's other anchors.
    Laning.SetHold(bot, a.br === "hold" ? a.hold : a.behind);
    if (a.br === "hold" && !LaneAggro.Acting(bot)) {
        let on = 0;
        for (const x of v.units) {
            const t = x.u.GetAttackTarget();
            if (t !== undefined && t !== null && t === bot) on++;
        }
        if (DrawNow(front, a.hd, GetUnitToLocationDistance(bot, a.hold), on) && LaneAggro.StartBack(bot, pointAt(v, a.hd + SETTINGS.HoldDrawOut, a.hold.z), "hold")) a.hdr++;
    }
}

export function Reset(): void {
    for (const k in attempts) attempts[k as unknown as number] = undefined;
    for (const k in decidedAt) decidedAt[k as unknown as number] = undefined;
    for (const k in endedAt) endedAt[k as unknown as number] = undefined;
    for (const k in skippedAt) skippedAt[k] = undefined;
    for (const k in forecastAt) forecastAt[k as unknown as number] = undefined;
}
