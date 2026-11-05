/**
 * The wave hold (slice core-in-lane, `Ours.CoreHold`; docs/proposals/2026-11-05-pull-effect.md s4 step 2, design by the user
 * 05/11/2026): when our wave on an in-lane core's lane is gone (pulled, drawn away by lane aggro's tower move, or anything
 * else) and theirs walks in, the core meets it at the lane's target point (lane_aggro TargetOf) instead of letting it die to
 * our T1. The trigger is the event, never the reason (logged as `why`).
 * - `hold`: the target point is lane_spot's named input `hold`; the body keeps last hitting from that spot.
 * - `drag`: an enemy hero threatens the core (lane_spot HeroReach) and our next wave is far enough that their creeps can be
 *   taken behind our T1 first: lane_aggro's draw `back` walks them there to meet it.
 * - `retreat`: OHA's retreat took the core.
 * One ev=wave_hold line per attempt, at its end. Stepped from the core draw step (States.CoreAggroStep, H1), before lane
 * aggro's own step; States.Tick ends an attempt whose caller lost the frame.
 */
import { BotMode, Lane, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import type { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as LaneAggro from "bots/FunLib/humaniser/lane_aggro";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as LaneSpot from "bots/FunLib/humaniser/states/lane_spot";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";

// Every number is `judgement` (slice core-in-lane, Decisions 05/11/2026).
export const SETTINGS = {
    Every: 0.25,
    /** Lane creeps within this of the lane path count as on the lane. */
    PathR: 600,
    /** Their wave: at least MinCreeps creeps from our T1 to StartAhead past the target point. */
    MinCreeps: 2,
    StartAhead: 1600,
    /** Our T1's range (700); their front inside it plus LateMargin is too late to hold. */
    TowerR: 700,
    LateMargin: 300,
    /**
     * Our wave is gone when none of our lane creeps stands from OursBehind behind our T1 to OursAhead past their rearmost creep
     * in the stretch. chold1 0:31 mid: their front creeps chased past a clash still running 1,000 further out; a window on
     * their front alone read that as our wave gone.
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
    /** Our next wave is near when it reaches the hold point within NearSecs: no drag, the waves meet at the hold. */
    NearSecs: 10,
    /** The drag's point: this far behind our T1 along the lane; its time: their front's walk there at creep speed plus
     *  DrawSecs, done DragMargin before our next wave reaches that point. */
    Behind: 500,
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
};

export type Branch = "hold" | "drag" | "retreat";

/** Pure: the trigger's reading of a lane, from our T1 distances (positive towards theirs) of the lane creeps on it. */
export function Read(theirs: number[], ours: number[], target: number): { front: number; n: number } | string {
    let n = 0;
    let front = math.huge;
    let rear = -math.huge;
    for (const o of theirs) {
        if (o < -SETTINGS.OursBehind || o > target + SETTINGS.StartAhead) continue;
        n++;
        front = math.min(front, o);
        rear = math.max(rear, o);
    }
    if (n < SETTINGS.MinCreeps) return "none";
    for (const o of ours) if (o >= -SETTINGS.OursBehind && o <= rear + SETTINGS.OursAhead) return "ours";
    if (front < SETTINGS.TowerR + SETTINGS.LateMargin) return "late";
    return { front, n };
}

/**
 * Pure: the branch (user 05/11/2026). `threat` an enemy hero's move on the core; `near` seconds until our next wave reaches the
 * hold point; `need` seconds the drag needs; `behind` seconds until our next wave reaches the drag's point.
 */
export function Choose(threat: boolean, near: number, need: number, behind: number): Branch {
    if (!threat || near <= SETTINGS.NearSecs) return "hold";
    return need + SETTINGS.DragMargin <= behind ? "drag" : "hold";
}

/** Pure: the seconds the drag needs from their front's distance from our T1. */
export function DragSecs(front: number): number {
    return (front + SETTINGS.Behind) / SETTINGS.CreepSpeed + SETTINGS.DrawSecs;
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
    thr?: number;
    hp0: number;
    hpMin: number;
    readAt: number;
}

const attempts: Record<number, Attempt | undefined> = {};
const decidedAt: Record<number, number | undefined> = {};
const endedAt: Record<number, number | undefined> = {};

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

interface LaneView {
    path: LanePath;
    t1: number;
    dir: number;
    theirs: number[];
    ours: number[];
    /** Their creeps on the lane with their distance from our T1. */
    units: { u: Unit; own: number }[];
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
    const ours = project(GetUnitList(UnitType.AlliedCreeps));
    return { path, t1, dir, theirs, ours, units };
}

function pointAt(v: LaneView, own: number, z: number): Vector {
    const [x, y] = LanePush.PointAt(v.path, v.t1 + v.dir * own);
    return Vector(x, y, z);
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

function begin(bot: Unit, v: LaneView, front: number, n: number, now: number): Attempt | undefined {
    const lane = bot.GetAssignedLane();
    const tgt = LaneAggro.TargetOf(lane);
    const z = bot.GetLocation().z;
    const hold = pointAt(v, tgt, z);
    if (GetUnitToLocationDistance(bot, hold) > SETTINGS.Reach || frac(bot) < SETTINGS.StartHp) return undefined;
    const nw = LanePush.NextArrival(v.path, bot.GetTeam(), v.t1 + v.dir * tgt, now) - now;
    return {
        lane,
        br: "hold",
        sw: 0,
        startedAt: now,
        steppedAt: now,
        hold,
        behind: pointAt(v, -SETTINGS.Behind, z),
        why: whyGone(bot, now),
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
        const ended = endedAt[pid];
        if (ended !== undefined && now - ended < SETTINGS.RestAfter) return;
        const v = viewOf(bot.GetTeam(), bot.GetAssignedLane());
        if (v === undefined) return;
        const r = Read(v.theirs, v.ours, LaneAggro.TargetOf(bot.GetAssignedLane()));
        if (typeof r === "string") return;
        a = begin(bot, v, r.front, r.n, now);
        if (a === undefined) return;
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
        if (x.own < -SETTINGS.OursBehind - SETTINGS.Behind || x.own > a.tgt + SETTINGS.StartAhead) continue;
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
        if (GetUnitToUnitDistance(c, nearest) <= SETTINGS.MeetR) {
            a.mo = front;
            return finish(bot, a, "met", now);
        }
    }
    if (a.br === "hold" && front < SETTINGS.TowerR) return finish(bot, a, "tower", now);

    const threat = threatOf(bot, a.hold);
    if (threat !== undefined) a.thr = threat.GetPlayerID();
    const near = LanePush.NextArrival(v.path, bot.GetTeam(), v.t1 + v.dir * a.tgt, now) - now;
    a.ds = DragSecs(math.max(0, front));
    a.nb = LanePush.NextArrival(v.path, bot.GetTeam(), v.t1 - v.dir * SETTINGS.Behind, now) - now;
    // A drag under way is lane_aggro's until its walk ends, and once behind our T1 the core waits there for our wave: the
    // branch is not read again meanwhile.
    const dragging = a.br === "drag" && (LaneAggro.Acting(bot) || GetUnitToLocationDistance(bot, a.behind) <= SETTINGS.Arrived);
    const br = dragging ? "drag" : Choose(threat !== undefined, near, a.ds, a.nb);
    if (br === "drag" && !dragging && !LaneAggro.StartBack(bot, a.behind)) {
        if (a.br !== "hold") a.sw++;
        a.br = "hold";
    } else if (br !== a.br) {
        a.sw++;
        a.br = br;
    }
    Laning.SetHold(bot, a.br === "hold" ? a.hold : undefined);
}

export function Reset(): void {
    for (const k in attempts) attempts[k as unknown as number] = undefined;
    for (const k in decidedAt) decidedAt[k as unknown as number] = undefined;
    for (const k in endedAt) endedAt[k as unknown as number] = undefined;
}
