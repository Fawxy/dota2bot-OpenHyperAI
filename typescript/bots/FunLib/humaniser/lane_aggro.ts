/**
 * Lane creep aggro (slice lane-aggro, `Ours.LaneAggro`): a laner draws enemy lane creeps on purpose with an attack order on an
 * enemy hero (EC-053: creeps within 500 of the ordering hero chase it for up to 2.3 s; one draw per 3 s per hero; the target
 * may be any visible enemy hero, in any lane), then walks them where it wants them. Each lane has a target meeting point on
 * our side (user 05/11/2026: just outside our T1's range for the side lanes, the edge of our high ground in mid), and the lane
 * forecast (lane_push) says where the clash is heading. Three moves, one module for both roles (a lane technique, bot code):
 * - `feed`: the enemy wave is walked back onto our ranged creep (any HP) whenever the clash sits or is heading beyond the target
 *   point (the first wave, a bigger wave of ours, a clash in the middle). Their melee creeps kill it quickly, we deny it (the
 *   deny is the laning body's; lane_spot keeps the bot in reach of the fed creep while it goes down), and the clash tilts toward us.
 * - `tower`: our wave pushed into their tower: drawn from just outside the tower's range and walked back, so their creeps
 *   follow us out and can be farmed there (user 05/11/2026; also an initiation point, for the fight work later).
 * - `drag`: one or two enemy creeps about to die beside an enemy hero are walked away from that hero, so the last hit is ours
 *   and a deny means the enemy walks up.
 * - `back` (slice core-in-lane, started only by wave_hold's drag): their wave walking in with ours gone is drawn and walked
 *   behind our T1 to meet our next wave there, a new draw each cooldown while no creep follows. The pull gate does not apply.
 * Cores do both. A support inherits them only while its lane's core is away (user 05/11/2026). One draw per lane at a time,
 * and none while our pull is out on that lane (the pull drags our wave away; feeding it then gives the wave away twice).
 * Stepped from mode_laning_generic's Think (cores, after the body's running swing) and from support_lane's step list.
 */
import { BotMode, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import type * as Lib from "bots/FunLib/engine/tasks";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import type { LanePath } from "bots/FunLib/humaniser/lane_push_data";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as CoreTrade from "bots/FunLib/humaniser/states/core_trade";
import * as Laning from "bots/FunLib/humaniser/states/laning";

export type Kind = "feed" | "drag" | "tower" | "back";
type PhaseName = "approach" | "walk" | "watch";

// Mechanics are EC-053's; every other number is `judgement` until the probe (slice file) reads it.
export const SETTINGS = {
    /** EC-053's 3 s cooldown, with a margin for the order's latency. */
    Cooldown: 3.1,
    /** Enemy creeps this close to the ordering hero are drawn (EC-053's 500, less for creeps moving while the order lands). */
    DrawR: 450,
    /** A decision is read at most this often per bot (lane push and lane target scans are not free). */
    Every: 0.25,
    MinHp: 0.45,
    /** Enemy heroes' attack range plus this around the bot (and the approach point) closes the move: very little damage. */
    HeroMargin: 250,
    /** No feed or drag approach this close to an enemy tower (an attack order near it can turn the tower). */
    TowerR: 1000,
    /** The bot never orders within the tower's reach plus this margin of an enemy tower (judgement; was 900 = 844 + 56); the tower move orders from there out. */
    TowerOrderMargin: 56,
    /** Feed: our ranged creep at this HP fraction or more (below it the body's deny already wants it). */
    FeedCreepHp: 0.25,
    /** Feed when the clash sits, or is forecast, more than this beyond the target point. */
    FeedMargin: 150,
    /** No feed with our ranged creep this close to one of our towers (their wave would die to it). */
    OwnTowerR: 800,
    /** Tower: our wave within this of their tower, their creeps within TowerSeek of it; the order point sits TowerPast beyond
     *  their creeps (from the tower), at least TowerOrderR() out; walk TowerBack back for TowerWalk; read TowerWatch later. */
    TowerSeek: 1000,
    TowerPast: 250,
    TowerApproachMax: 900,
    TowerApproachTime: 2.5,
    TowerBack: 450,
    TowerWalk: 1.8,
    TowerWatch: 1.5,
    /** ev=aggro_skip: a bot's skip reason is logged when it changes, at most this often. */
    SkipEvery: 3,
    /** Feed: enemy melee creeps on our wave within this of our ranged creep, and at least FeedMinCreeps of them. */
    FightR: 700,
    FeedMinCreeps: 2,
    /**
     * Feed: the approach point stands this far back (toward our tower) from the enemy creeps' centre, at most ApproachMax walk
     * away (user 06/11/2026: lane_spot keeps an offlaner 560-940 from it, obs0611 mark 1). The walk gets its own time
     * (ApproachTime): distance / move speed + ApproachSlack, at most ApproachTimeMax.
     */
    ApproachBack: 380,
    ApproachMax: 900,
    ApproachSlack: 0.4,
    ApproachTimeMax: 3.5,
    /** Feed: walk back to this far behind our ranged creep, so it is the nearest of ours when the creeps re-pick. */
    FeedBack: 250,
    /** Feed: the drop (attack order on our ranged creep) once a drawn creep is this close to it, after DropAfter, or at DropBy. */
    DropNear: 220,
    DropAfter: 0.8,
    DropBy: 1.8,
    /**
     * No creep drawn this long after the order: `no_draw`. Drawn: an enemy creep within 500 at the order that targets the bot,
     * or that has moved MovedR since (melee creeps fighting stand still; a chasing creep may not report its target until it
     * swings: lagchk1 logged 22 of 33 tries as no_draw at 0.6 s on the target alone).
     */
    DrawCheck: 1.0,
    MovedR: 120,
    /** Drag: a last hit due in this window (s): sooner the body just takes it, later it is not worth a draw yet. */
    DragDueMin: 0.8,
    DragDueMax: 3,
    /** Drag: the enemy hero contests within its attack range plus this of the creep. */
    DragContest: 150,
    DragBack: 300,
    /** Drag: a contested last hit up to this far beyond DrawR is stepped toward (to DrawR less DragStepIn from the creep)
     *  when the step's spot is out of every enemy hero's reach (HeroMargin); farther, no drag (`judgement`). */
    DragStepMax: 300,
    DragStepIn: 50,
    /** Drag: no order once the creep stands farther than this (EC-053's 500 less a margin for the creep's move). */
    DragOrderR: 470,
    /** Drag: a step or walk-back spot inside an enemy hero's reach may be at most this much nearer to it than the bot is (`judgement`). */
    DragCloser: 50,
    DragWalk: 1.2,
    /** A lane hit due this soon (any kind) keeps the body's frame: no feed. */
    BusyWithin: 1.5,
    /**
     * An attempt not stepped for this long while another mode held the bot ends `stale` (its caller lost the frame, e.g. OHA's
     * retreat): acting phases (approach, walk) and the watch. Review 2026-11-05-lane-aggro-41120ba F1: a frozen move resumed
     * past its gates. A gap with the bot in laning mode throughout (a body swing, a Think that did not reach the step: awchk2
     * 5 of 26 stales) is resumed, up to StaleCap.
     */
    StaleActing: 0.5,
    StaleWatch: 3,
    StaleCap: 10,
    /** During the approach the move ends `unsafe` only once an enemy hero's attack reaches the approach point (or the feed's
     *  walk-back point) with this margin: less than HeroMargin at the start, so a walk started safe is not dropped by a few
     *  units (awchk2: 9 feed walks ended within about 0.5 s of their start, no HP lost). */
    UnsafeMargin: 0,
    /** The move stops when the bot has lost this share of its max HP since the order. */
    HurtShare: 0.12,
    /** Results are read until then: the fed creep's death, the dragged creep's death. */
    FeedWatch: 30,
    /**
     * Feed: no enemy hero within its attack range + radius + this of our ranged creep (lagchk2: 2 of 4 fed creeps that died
     * otherwise were the enemy hero's last hit, gold to them).
     */
    FeedHeroClear: 300,
    DragWatch: 3.5,
    /** Back: the walk ends within BackArrive of its point or after BackWalk; drawn creeps within BackOut of it are `ok`. */
    BackArrive: 150,
    BackWalk: 10,
    BackOut: 900,
    /** A support's lane core is away when no allied core of that lane is alive within this. */
    CoreNear: 1600,
};

interface Attempt {
    kind: Kind;
    phase: PhaseName;
    startedAt: number;
    steppedAt: number;
    orderedAt?: number;
    walkedAt?: number;
    droppedAt?: number;
    hero: Unit;
    tpid: number;
    /** Distance to the order's hero at the order. */
    td?: number;
    creep: Unit;
    tower?: Unit;
    out?: number;
    /** Feed watch: 1 once the laning spot anchored on the fed creep (lane_spot input `fed`), else 0. */
    sty: number;
    own?: number;
    fc?: number;
    approachTime: number;
    /** Distance from the bot to the approach point at the start. */
    ad?: number;
    /** Enemy lane creeps within 500 at the order and where they stood. */
    start?: { unit: Unit; x: number; y: number }[];
    mv: number;
    approach?: Vector;
    back: Vector;
    hp0: number;
    hpMin: number;
    near: number;
    drawn: number;
    onr: number;
    lh0: number;
    dn0: number;
    q?: number;
    st?: string;
    role: string;
    /** Enemy hero to dragged creep distance at the hand-back. */
    hd?: number;
    /** Back: the draws given. */
    nd?: number;
    /** Back: who asked (wave_hold `drag` or `hold`, slice core-in-lane). */
    src?: string;
    /** The first other mode seen holding the bot since the last step (Tick). */
    left?: number;
    /** Drag: the dragged creep's distance to the bot at the order, 1 once it targeted the bot or moved MovedR from where it
     *  stood at the order, and where it stood. */
    cd?: number;
    cf?: number;
    c0?: Vector;
    /** Drag: the contesting enemy hero and its last hits plus denies at the start (its own GetLastHits/GetDenies; GetHeroLastHits read nil in lhd4). */
    con?: Unit;
    clh0?: number;
    /** Drag: where the bot stood at the start (the step's safety is judged against it), the creep's HP fraction at the
     *  hand-back and its last seen distance to the bot. */
    from?: Vector;
    chp?: number;
    ld?: number;
    /** Drag: whether the bot is melee (attack range 200 or less) and whether a spot within its reach of the creep was out of
     *  every enemy hero's reach at the start (HitSpotSafe). */
    ml?: number;
    ss?: number;
    /** Drag, at the creep's death: `us` (our last hit), `hero` (the contester's last hits or denies rose), `none`. */
    by?: string;
}

const attempts: Record<number, Attempt | undefined> = {};
const orderedAt: Record<number, number | undefined> = {};
const decidedAt: Record<number, number | undefined> = {};
/** Creeps already logged as a drag candidate (`ev=drag_look`, once per creep), with when. */
const looked: LuaTable<Unit, number> = new LuaTable();
let lookedPruned = -math.huge;
/** Our ranged creeps already fed (one feed per creep). */
const fed: LuaTable<Unit, boolean> = new LuaTable();
/** Last draw per team and lane: one draw per lane at a time. */
const laneDraw: Record<string, { pid: number; at: number } | undefined> = {};
const pushCache: Record<string, { t: number; r: LanePush.Reading | undefined } | undefined> = {};
const lastSkip: Record<number, { why: string; at: number } | undefined> = {};
/** When each bot's last tower move ended (wave_hold logs it as why our wave is gone). */
const towerEnd: Record<number, number | undefined> = {};

export function TowerMovedAt(pid: number): number | undefined {
    return towerEnd[pid];
}

function laneKey(team: number, lane: Lane): string {
    return `${team}:${lane}`;
}

function valid(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.CanBeSeen();
}

/** A creep handle turns null once the unit is removed; IsAlive on it throws (lagchk5 t=484). */
function live(u: Unit): boolean {
    return !u.IsNull() && u.IsAlive();
}

function frac(u: Unit): number {
    return u.GetHealth() / math.max(1, u.GetMaxHealth());
}

function d2(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function along(from: Vector, dir: Vector, len: number): Vector {
    return Vector(from.x + dir.x * len, from.y + dir.y * len, from.z);
}

const T1: Record<number, Tower> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

/** Unit vector from `from` toward our side of the lane (our T1, else our ancient). */
function backDir(team: number, lane: Lane, from: Vector): Vector {
    const t = GetTower(team, T1[lane]);
    const home = t !== undefined && t !== null && t.IsAlive() ? t.GetLocation() : GetAncient(team).GetLocation();
    const len = math.max(1, d2(home, from));
    return Vector((home.x - from.x) / len, (home.y - from.y) / len, 0);
}

function isRanged(c: Unit): boolean {
    return c.GetUnitName().includes("ranged");
}

function isLaneCreep(c: Unit): boolean {
    return LanePush.IsLaneCreep(c.GetUnitName());
}

function counter(bot: Unit, name: "GetLastHits" | "GetDenies"): number {
    const f = (bot as any)[name];
    return f !== undefined ? (f(bot) as number) : 0;
}

/** Pure: whether the draw clock lets this bot order now (its own last draw and its trades' primes share the 3 s cooldown). */
export function CooldownClear(now: number, own: number | undefined, primed: number | undefined): boolean {
    const last = math.max(own ?? -math.huge, primed ?? -math.huge);
    return now - last >= SETTINGS.Cooldown;
}

/** Pure: whether another hero's draw holds this lane (one draw per lane at a time). */
export function LaneHeld(now: number, pid: number, held: { pid: number; at: number } | undefined): boolean {
    return held !== undefined && held.pid !== pid && now - held.at < SETTINGS.Cooldown;
}

/**
 * Whether an attempt last stepped `gap` seconds ago is stale: after another mode held the bot (`left`), the watch tolerates a
 * short loss of the frame and acting does not; with the bot in laning throughout, only a gap past StaleCap.
 */
export function Stale(phase: PhaseName, gap: number, left: boolean = true): boolean {
    if (!left) return gap > SETTINGS.StaleCap;
    return gap > (phase === "watch" ? SETTINGS.StaleWatch : SETTINGS.StaleActing);
}

/** Every frame (States.Tick, from ItemUsageThink, whichever mode runs): notes another mode holding the bot during an attempt. */
export function Tick(bot: Unit): void {
    const a = attempts[bot.GetPlayerID()];
    if (a === undefined || a.left !== undefined) return;
    const mode = bot.GetActiveMode();
    if (mode !== BotMode.Laning) a.left = mode;
}

/**
 * Pure: whether the clash sits, or is forecast to sit, beyond the target point (`own` the clash's distance from our T1 now,
 * `move` its forecast move toward their T1). A clash coming in from beyond it still wants the feed: it is not ours yet.
 */
export function FeedWanted(r: { own: number; move: number } | undefined, target: number): boolean {
    if (r === undefined) return false;
    return math.max(r.own, r.own + r.move) > target + SETTINGS.FeedMargin;
}

/**
 * Pure: the tower move's order point, on the line from their tower `(tx, ty)` through their creeps' centre `(cx, cy)`:
 * TowerPast beyond the creeps, never inside TowerOrderR() of the tower.
 */
export function TowerPoint(tx: number, ty: number, cx: number, cy: number): LuaMultiReturn<[number, number]> {
    const dx = cx - tx;
    const dy = cy - ty;
    const len = math.max(1, math.sqrt(dx * dx + dy * dy));
    const r = math.max(len + SETTINGS.TowerPast, TowerOrderR());
    return $multi(tx + (dx / len) * r, ty + (dy / len) * r);
}

/** Pure: seconds the bot gets to walk `dist` to the approach point at `speed` before it orders from where it stands. */
export function ApproachTime(dist: number, speed: number): number {
    return math.min(SETTINGS.ApproachTimeMax, dist / math.max(1, speed) + SETTINGS.ApproachSlack);
}

/**
 * Pure: whether the point `(x, y)` lies inside `team`'s wave hold point on `lane` (closer to our T1 along the path than lane_push
 * TargetOf). The feed walks their creeps to its back point, so a back point inside it draws them where wave_hold meets them.
 */
export function InsideHold(path: LanePath, team: number, lane: Lane, x: number, y: number): boolean {
    const [s] = LanePush.Project(path, x, y);
    const [t1, dir] = LanePush.OwnT1(path, team);
    return dir * (s - t1) < LanePush.TargetOf(lane);
}

/** Pure: the feed's drop now? `t` seconds since the order, `nearest` the closest drawn creep to our ranged creep. */
export function DropNow(t: number, drawn: number, nearest: number | undefined): boolean {
    if (t >= SETTINGS.DropBy) return true;
    return t >= SETTINGS.DropAfter && drawn > 0 && nearest !== undefined && nearest <= SETTINGS.DropNear;
}

function pushRead(team: number, lane: Lane): LanePush.Reading | undefined {
    const key = laneKey(team, lane);
    const now = DotaTime();
    const c = pushCache[key];
    if (c !== undefined && now - c.t < 1) return c.r;
    const [ok, r] = pcall(LanePush.Read, team, lane);
    const v = ok ? r : undefined;
    pushCache[key] = { t: now, r: v };
    return v;
}

function coreAway(bot: Unit): boolean {
    const lane = bot.GetAssignedLane();
    for (let i = 1; i <= 5; i++) {
        const h = GetTeamMember(i);
        if (h === undefined || h === null || h === bot || h.IsNull()) continue;
        const pos = LaneConfig.PositionOf(h);
        if (pos === undefined || pos > 3 || h.GetAssignedLane() !== lane) continue;
        if (h.IsAlive() && GetUnitToUnitDistance(h, bot) <= SETTINGS.CoreNear) return false;
    }
    return true;
}

function roleOf(bot: Unit): "core" | "support" | undefined {
    if (CoreLastHit.Applies(bot)) return "core";
    if (Laning.OwnsSupportHits(bot)) return "support";
    return undefined;
}

/** Whether this module may act for the bot now (the switch, laning phase, a core, or a support whose core is away). */
export function Owns(bot: Unit): boolean {
    if (!Ours.On("LaneAggro") || !bot.IsAlive() || !Phase.IsLaningFor(bot)) return false;
    const role = roleOf(bot);
    if (role === "core") return true;
    return role === "support" && coreAway(bot);
}

/** Whether the bot owns the move in principle (switch and role), so OHA's aggro pull stays off for it (lane_tech). */
export function OwnsTechnique(bot: Unit): boolean {
    return Ours.On("LaneAggro") && roleOf(bot) !== undefined;
}

function enemyHeroes(bot: Unit, r: number): Unit[] {
    const out: Unit[] = [];
    for (const h of bot.GetNearbyHeroes(r, true, BotMode.None)) if (valid(h) && !h.IsIllusion()) out.push(h);
    return out;
}

/** No enemy hero reaches `at` (attack range + radii + margin). */
function heroSafe(at: Vector, heroes: Unit[], margin: number = SETTINGS.HeroMargin): boolean {
    for (const h of heroes) {
        if (GetUnitToLocationDistance(h, at) <= h.GetAttackRange() + h.GetBoundingRadius() * 2 + margin) return false;
    }
    return true;
}

const TOWERS = [Tower.Top1, Tower.Mid1, Tower.Bot1, Tower.Top2, Tower.Mid2, Tower.Bot2];

function enemyOf(team: number): number {
    return team === Team.Radiant ? Team.Dire : Team.Radiant;
}

/** The nearest alive tier-1 or tier-2 tower of `team` within `r` of `at`. */
function towerNear(at: Vector, team: number, r: number): Unit | undefined {
    let best: Unit | undefined;
    let bestD = r;
    for (const id of TOWERS) {
        const t = GetTower(team, id);
        if (t === undefined || t === null || !t.IsAlive()) continue;
        const d = d2(t.GetLocation(), at);
        if (d <= bestD) {
            best = t;
            bestD = d;
        }
    }
    return best;
}

/** The radius inside which the bot never orders near an enemy tower: its live reach plus TowerOrderMargin. */
function TowerOrderR(): number {
    return LaneConfig.TowerReach() + SETTINGS.TowerOrderMargin;
}

function nearTower(at: Vector, team: number, r: number = SETTINGS.TowerR): boolean {
    return towerNear(at, enemyOf(team), r) !== undefined;
}

/** The enemy hero the order names: the nearest visible one anywhere (the draw comes from where the bot stands). */
function orderTarget(bot: Unit): Unit | undefined {
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const h of GetUnitList(UnitType.EnemyHeroes)) {
        if (!valid(h) || h.IsIllusion()) continue;
        const d = GetUnitToUnitDistance(bot, h);
        if (d < bestD) {
            best = h;
            bestD = d;
        }
    }
    return best;
}

function allyPullOut(bot: Unit): boolean {
    const lane = bot.GetAssignedLane();
    for (let i = 1; i <= 5; i++) {
        const h = GetTeamMember(i);
        if (h === undefined || h === null || h.IsNull()) continue;
        if (h.GetAssignedLane() === lane && PullJob.Running(h)) return true;
    }
    return false;
}

function enemyCreepsNear(bot: Unit, at: Vector, r: number): Unit[] {
    const out: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(1600, true)) {
        if (valid(c) && isLaneCreep(c) && d2(c.GetLocation(), at) <= r) out.push(c);
    }
    return out;
}

function laneTargets(bot: Unit, within: number, deny: boolean): Lib.Verbs.LaneTarget[] {
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return [];
    return verbs.laneTargets(bot as unknown as Lib.TaskUnit, { within, deny });
}

/** The shared gates of both moves, or why not. */
function gate(bot: Unit, now: number): string | undefined {
    const pid = bot.GetPlayerID();
    if (!CooldownClear(now, orderedAt[pid], CoreTrade.PrimedAt(pid))) return "cooldown";
    if (LaneHeld(now, pid, laneDraw[laneKey(bot.GetTeam(), bot.GetAssignedLane())])) return "lane";
    if (frac(bot) < SETTINGS.MinHp) return "hp";
    const t = bot.GetAttackTarget();
    if (t !== undefined && t !== null && !t.IsNull() && t.IsHero()) return "trading";
    if (nearTower(bot.GetLocation(), bot.GetTeam(), TowerOrderR())) return "tower";
    if (allyPullOut(bot)) return "pull";
    return undefined;
}

function start(bot: Unit, a: Attempt): void {
    attempts[bot.GetPlayerID()] = a;
}

/** The attempt, or why not and (feed `approach_far`) the approach distance. */
type Try = LuaMultiReturn<[Attempt | undefined, string, number?]>;

/** A last hit in the drag window that an enemy hero contests (within its attack range + DragContest of the creep). */
interface DragCand {
    creep: Unit;
    due: number;
    /** Bot to creep distance. */
    d: number;
    con: Unit;
    /** HitSpotSafe at the look. */
    ss: boolean;
    /** Why this one was not dragged (`go` when it was). */
    why?: string;
}

function contested(creep: Unit, heroes: Unit[]): Unit | undefined {
    let con: Unit | undefined;
    for (const h of heroes) {
        if (GetUnitToUnitDistance(h, creep) <= h.GetAttackRange() + h.GetBoundingRadius() + SETTINGS.DragContest) con = h;
    }
    return con;
}

/**
 * Pure: whether the bot can hit the creep from a spot out of every enemy hero's reach. The spot stands on the line from the
 * creep toward the bot at the bot's reach (attack range plus both radii, less a 25 margin), or where the bot is when nearer.
 */
export function HitSpot(cx: number, cy: number, bx: number, by: number, reach: number): [number, number] {
    const dx = bx - cx;
    const dy = by - cy;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return [bx, by];
    const r = math.min(len, math.max(0, reach - 25));
    return [cx + (dx / len) * r, cy + (dy / len) * r];
}

function hitSpotSafe(bot: Unit, creep: Unit, heroes: Unit[]): boolean {
    const c = creep.GetLocation();
    const b = bot.GetLocation();
    const [x, y] = HitSpot(c.x, c.y, b.x, b.y, bot.GetAttackRange() + bot.GetBoundingRadius() + creep.GetBoundingRadius());
    return heroSafe(Vector(x, y, b.z), heroes, SETTINGS.UnsafeMargin);
}

function dragCands(bot: Unit, heroes: Unit[]): DragCand[] {
    const out: DragCand[] = [];
    for (const t of laneTargets(bot, SETTINGS.DragDueMax, false)) {
        if (t.kind !== "lasthit" || t.due < SETTINGS.DragDueMin || t.due > SETTINGS.DragDueMax) continue;
        const creep = t.creep as unknown as Unit;
        if (!valid(creep)) continue;
        const con = contested(creep, heroes);
        if (con === undefined) continue;
        out.push({ creep, due: t.due, d: GetUnitToUnitDistance(bot, creep), con, ss: hitSpotSafe(bot, creep, heroes) });
    }
    return out;
}

/**
 * Pure: what a contested last hit gets (slice lh-draw 1b, user 09/11/2026: a hero that can hit the creep from a safe spot
 * just takes it). `safe`: a spot within our reach of the creep is out of every enemy hero's reach, no drag; `in`: within
 * draw range, draw now; `step`: a short step that is itself safe brings it into range; `step_unsafe`: that step is not safe;
 * `far`: beyond the step.
 */
export function DragPlan(d: number, ss: boolean, stepSafe: boolean): "safe" | "in" | "step" | "step_unsafe" | "far" {
    if (ss) return "safe";
    if (d <= SETTINGS.DrawR) return "in";
    if (d - SETTINGS.DrawR > SETTINGS.DragStepMax) return "far";
    return stepSafe ? "step" : "step_unsafe";
}

/**
 * The drag's safety (slice lh-draw 1b, lhd3: a melee hero against a ranged one stands in its reach all lane, so heroSafe
 * refused every drag): a spot is fine when it is out of each enemy hero's attack reach or no nearer to that hero than `here`
 * less DragCloser. The drag walks away from the enemy hero, so it lowers the exposure the hero already accepts.
 */
function noDeeper(here: Vector, to: Vector, heroes: Unit[]): boolean {
    for (const h of heroes) {
        const reach = h.GetAttackRange() + h.GetBoundingRadius() * 2;
        const dTo = GetUnitToLocationDistance(h, to);
        if (dTo <= reach && dTo < GetUnitToLocationDistance(h, here) - SETTINGS.DragCloser) return false;
    }
    return true;
}

/** Unit vector from `from` away from the enemy hero `con`, bent toward our side of the lane (the two directions' mean). */
function dragDir(team: number, lane: Lane, from: Vector, con: Unit): Vector {
    const b = backDir(team, lane, from);
    const c = con.GetLocation();
    const len = math.max(1, d2(from, c));
    const x = b.x + (from.x - c.x) / len;
    const y = b.y + (from.y - c.y) / len;
    const n = math.sqrt(x * x + y * y);
    return n < 0.01 ? b : Vector(x / n, y / n, 0);
}

/** The first candidate that can be dragged; each candidate looked at gets its `why`. */
function tryDrag(bot: Unit, heroes: Unit[], cands: DragCand[], now: number): Attempt | undefined {
    const here = bot.GetLocation();
    for (const c of cands) {
        let step: Vector | undefined;
        let stepSafe = false;
        if (!c.ss && c.d > SETTINGS.DrawR && c.d - SETTINGS.DrawR <= SETTINGS.DragStepMax) {
            const cl = c.creep.GetLocation();
            const [sx, sy] = HitSpot(cl.x, cl.y, here.x, here.y, SETTINGS.DrawR - SETTINGS.DragStepIn + 25);
            step = Vector(sx, sy, here.z);
            stepSafe = noDeeper(here, step, heroes);
        }
        const plan = DragPlan(c.d, c.ss, stepSafe);
        if (plan !== "in" && plan !== "step") {
            c.why = plan;
            continue;
        }
        const hero = orderTarget(bot);
        if (hero === undefined) {
            c.why = "no_target";
            return undefined;
        }
        const from = plan === "step" ? step! : here;
        const back = along(from, dragDir(bot.GetTeam(), bot.GetAssignedLane(), from, c.con), SETTINGS.DragBack);
        if (!noDeeper(here, back, heroes)) {
            c.why = "unsafe";
            return undefined;
        }
        c.why = plan === "step" ? "step" : "go";
        const a = newAttempt(bot, "drag", plan === "step" ? "approach" : "walk", hero, c.creep, back, plan === "step" ? step : undefined, now);
        if (plan === "step") {
            const ad = GetUnitToLocationDistance(bot, step!);
            a.ad = math.floor(ad);
            a.approachTime = ApproachTime(ad, bot.GetCurrentMovementSpeed());
        }
        a.con = c.con;
        a.clh0 = heroTally(c.con);
        a.from = here;
        a.ml = bot.GetAttackRange() <= 200 ? 1 : 0;
        a.ss = c.ss ? 1 : 0;
        return a;
    }
    return undefined;
}

/** An enemy hero's last hits plus denies (its denies of its own creeps take ours from us too); undefined out of sight. */
function heroTally(h: Unit): number | undefined {
    if (h.IsNull() || !h.CanBeSeen()) return undefined;
    return counter(h, "GetLastHits") + counter(h, "GetDenies");
}

/**
 * One `ev=drag_look` line per creep the first time it is a drag candidate, with why it was not dragged then (a shared gate,
 * `reach`, `far`, `no_target`, `unsafe`, `other`: an earlier candidate went or stopped the look) or `go`.
 */
function logLooks(bot: Unit, cands: DragCand[], pre: string | undefined, now: number): void {
    if (now - lookedPruned > 30) {
        lookedPruned = now;
        const gone: Unit[] = [];
        for (const [u, at] of looked) if (now - at > 30 || u.IsNull() || !u.IsAlive()) gone.push(u);
        for (const u of gone) looked.delete(u);
    }
    const ml = bot.GetAttackRange() <= 200 ? 1 : 0;
    for (const c of cands) {
        if (looked.has(c.creep)) continue;
        looked.set(c.creep, now);
        Telemetry.Event("drag_look", [
            ["pid", bot.GetPlayerID()],
            ["role", roleOf(bot) ?? "?"],
            ["why", pre ?? c.why ?? "other"],
            ["d", math.floor(c.d)],
            ["due", math.floor(c.due * 100) / 100],
            ["hd", math.floor(GetUnitToUnitDistance(c.con, c.creep))],
            ["ss", c.ss ? 1 : 0],
            ["ml", ml],
        ]);
    }
}

function tryTower(bot: Unit, heroes: Unit[], now: number): Try {
    const team = bot.GetTeam();
    const tw = towerNear(bot.GetLocation(), enemyOf(team), SETTINGS.TowerSeek + SETTINGS.TowerApproachMax);
    if (tw === undefined) return $multi(undefined, "none");
    const tl = tw.GetLocation();
    let ours = 0;
    for (const c of bot.GetNearbyLaneCreeps(1600, false)) if (valid(c) && isLaneCreep(c) && d2(c.GetLocation(), tl) <= LaneConfig.TowerReach()) ours++;
    const theirs = enemyCreepsNear(bot, tl, SETTINGS.TowerSeek);
    if (ours === 0 || theirs.length === 0) return $multi(undefined, "none");
    let cx = 0;
    let cy = 0;
    for (const c of theirs) {
        cx += c.GetLocation().x;
        cy += c.GetLocation().y;
    }
    const [px, py] = TowerPoint(tl.x, tl.y, cx / theirs.length, cy / theirs.length);
    const at = Vector(px, py, bot.GetLocation().z);
    const drawable = enemyCreepsNear(bot, at, SETTINGS.DrawR);
    if (drawable.length === 0) return $multi(undefined, "draw_far");
    if (GetUnitToLocationDistance(bot, at) > SETTINGS.TowerApproachMax) return $multi(undefined, "approach_far");
    if (!heroSafe(at, heroes)) return $multi(undefined, "unsafe");
    if (laneTargets(bot, SETTINGS.BusyWithin, true).length > 0) return $multi(undefined, "busy");
    const hero = orderTarget(bot);
    if (hero === undefined) return $multi(undefined, "no_target");
    const back = along(at, backDir(team, bot.GetAssignedLane(), at), SETTINGS.TowerBack);
    const a = newAttempt(bot, "tower", "approach", hero, drawable[0], back, at, now);
    a.tower = tw;
    a.ad = math.floor(GetUnitToLocationDistance(bot, at));
    a.approachTime = SETTINGS.TowerApproachTime;
    return $multi(a, "go");
}

function nearOwnTower(at: Vector, team: number): boolean {
    return towerNear(at, team, SETTINGS.OwnTowerR) !== undefined;
}

function tryFeed(bot: Unit, heroes: Unit[], now: number): Try {
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    let ranged: Unit | undefined;
    for (const c of bot.GetNearbyLaneCreeps(1200, false)) {
        if (valid(c) && isLaneCreep(c) && isRanged(c) && fed.get(c) !== true && frac(c) >= SETTINGS.FeedCreepHp) ranged = c;
    }
    if (ranged === undefined) return $multi(undefined, "no_ranged");
    // Slice lane-control 2b: the lane controller's wave decision says whether this wave wants the feed (a named input; the
    // feed keeps its own gates below); with no live decision, the feed's own reading decides.
    const LaneControl = require("bots/FunLib/humaniser/lane_control") as typeof import("bots/FunLib/humaniser/lane_control");
    const chosen = LaneControl.Chosen(team, lane, "feed");
    if (chosen === false) return $multi(undefined, "ctl");
    const r = pushRead(team, lane);
    if (chosen === undefined && !FeedWanted(r, LanePush.TargetOf(lane))) return $multi(undefined, r === undefined ? "no_read" : "at_target");
    if (nearOwnTower(ranged.GetLocation(), team)) return $multi(undefined, "own_tower");
    const fighting = enemyCreepsNear(bot, ranged.GetLocation(), SETTINGS.FightR);
    if (fighting.length < SETTINGS.FeedMinCreeps) return $multi(undefined, "few_creeps");
    for (const h of heroes) {
        if (GetUnitToUnitDistance(h, ranged) <= h.GetAttackRange() + h.GetBoundingRadius() + SETTINGS.FeedHeroClear) return $multi(undefined, "hero_on_ranged");
    }
    let cx = 0;
    let cy = 0;
    for (const c of fighting) {
        cx += c.GetLocation().x;
        cy += c.GetLocation().y;
    }
    const centre = Vector(cx / fighting.length, cy / fighting.length, ranged.GetLocation().z);
    const dir = backDir(team, lane, centre);
    const approach = along(centre, dir, SETTINGS.ApproachBack);
    const ad = GetUnitToLocationDistance(bot, approach);
    if (ad > SETTINGS.ApproachMax) return $multi(undefined, "approach_far", ad);
    if (enemyCreepsNear(bot, approach, SETTINGS.DrawR).length < SETTINGS.FeedMinCreeps) return $multi(undefined, "approach_creeps");
    const back = along(ranged.GetLocation(), dir, SETTINGS.FeedBack);
    const path = LanePush.PathOf(lane);
    if (path !== undefined && InsideHold(path, team, lane, back.x, back.y)) return $multi(undefined, "inside_hold");
    if (!heroSafe(approach, heroes) || !heroSafe(back, heroes)) return $multi(undefined, "unsafe");
    if (nearTower(approach, team)) return $multi(undefined, "tower");
    if (laneTargets(bot, SETTINGS.BusyWithin, true).length > 0) return $multi(undefined, "busy");
    const hero = orderTarget(bot);
    if (hero === undefined) return $multi(undefined, "no_target");
    const a = newAttempt(bot, "feed", "approach", hero, ranged, back, approach, now);
    a.ad = math.floor(ad);
    a.approachTime = ApproachTime(ad, bot.GetCurrentMovementSpeed());
    a.q = math.floor(r!.q * 100) / 100;
    a.st = r!.state;
    a.own = math.floor(r!.own);
    a.fc = math.floor(r!.own + r!.move);
    return $multi(a, "go");
}

function newAttempt(bot: Unit, kind: Kind, phase: PhaseName, hero: Unit, creep: Unit, back: Vector, approach: Vector | undefined, now: number): Attempt {
    return {
        kind,
        phase,
        startedAt: now,
        steppedAt: now,
        hero,
        tpid: hero.GetPlayerID(),
        creep,
        mv: 0,
        sty: 0,
        approachTime: SETTINGS.ApproachTimeMax,
        approach,
        back,
        hp0: bot.GetHealth(),
        hpMin: bot.GetHealth(),
        near: 0,
        drawn: 0,
        onr: 0,
        lh0: counter(bot, "GetLastHits"),
        dn0: counter(bot, "GetDenies"),
        role: roleOf(bot) ?? "?",
    };
}

function finish(bot: Unit, a: Attempt, result: string, now: number, gap?: number): void {
    attempts[bot.GetPlayerID()] = undefined;
    if (a.kind === "feed") Laning.SetFed(bot, undefined);
    if (a.kind === "tower") towerEnd[bot.GetPlayerID()] = now;
    Telemetry.Event("aggro", [
        ["pid", bot.GetPlayerID()],
        ["role", a.role],
        ["kind", a.kind],
        ["result", result],
        ["tgt", a.tpid],
        ["near", a.near],
        ["drawn", a.drawn],
        ["mv", a.mv],
        ["rhp", a.kind === "feed" && live(a.creep) ? math.floor(frac(a.creep) * 100) / 100 : undefined],
        ["onr", a.onr],
        ["dhp", a.hp0 - a.hpMin],
        ["hp", math.floor((a.hp0 / math.max(1, bot.GetMaxHealth())) * 100) / 100],
        ["q", a.q],
        ["st", a.st],
        ["hd", a.hd],
        ["own", a.own],
        ["fc", a.fc],
        ["td", a.td],
        ["out", a.out],
        ["sty", a.kind === "feed" ? a.sty : undefined],
        ["nd", a.nd],
        ["src", a.src],
        ["ad", a.ad],
        ["apt", a.ad !== undefined ? math.floor(a.approachTime * 100) / 100 : undefined],
        ["md", result === "stale" ? a.left ?? bot.GetActiveMode() : undefined],
        ["lbl", result === "stale" ? Tasks.Current(bot)?.label ?? "-" : undefined],
        ["gap", gap !== undefined ? math.floor(gap * 100) / 100 : undefined],
        ["drop", a.droppedAt !== undefined ? math.floor((a.droppedAt - (a.orderedAt ?? a.startedAt)) * 100) / 100 : undefined],
        ["dur", math.floor((now - a.startedAt) * 100) / 100],
        ["cd", a.cd],
        ["cf", a.cf],
        ["by", a.by],
        ["chp", a.chp],
        ["ld", a.ld],
        ["ml", a.ml],
        ["ss", a.ss],
    ]);
}

/**
 * Where a creep seen at the order stands now: undefined once removed, dead or with no location (it left our vision; the
 * handle stays valid but reads none: chold3_A_on_1 t=217.6, `lua_error` in States.SupportStep).
 */
function seenAt(u: Unit): Vector | undefined {
    if (u.IsNull() || !u.IsAlive()) return undefined;
    return u.GetLocation() ?? undefined;
}

/** Enemy creeps near at the order that have since moved MovedR or more (drawn off their fight). */
export function MovedOf(start: { unit: Unit; x: number; y: number }[] | undefined): number {
    let n = 0;
    for (const s0 of start ?? []) {
        const l = seenAt(s0.unit);
        if (l !== undefined && d2(l, Vector(s0.x, s0.y, l.z)) >= SETTINGS.MovedR) n++;
    }
    return n;
}

function drawnOn(bot: Unit, target: Unit): Unit[] {
    const out: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(1200, true)) {
        if (!valid(c)) continue;
        const t = c.GetAttackTarget();
        if (t !== undefined && t !== null && !t.IsNull() && t === target) out.push(c);
    }
    return out;
}

/**
 * wave_hold's drag: draw their creeps near the bot and walk them to `to` (behind our T1). False when a move already runs or a
 * shared gate (the draw clock, another hero's draw on the lane, HP, a trade) says no; the pull gate does not apply.
 */
export function StartBack(bot: Unit, to: Vector, src: "drag" | "hold" = "drag"): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    if (attempts[pid] !== undefined || !Ours.On("LaneAggro")) return false;
    if (!CooldownClear(now, orderedAt[pid], CoreTrade.PrimedAt(pid))) return false;
    if (LaneHeld(now, pid, laneDraw[laneKey(bot.GetTeam(), bot.GetAssignedLane())])) return false;
    if (frac(bot) < SETTINGS.MinHp) return false;
    const near = enemyCreepsNear(bot, bot.GetLocation(), SETTINGS.DrawR);
    if (near.length === 0) return false;
    const hero = orderTarget(bot);
    if (hero === undefined) return false;
    const a = newAttempt(bot, "back", "walk", hero, near[0], to, undefined, now);
    a.src = src;
    a.nd = 0;
    start(bot, a);
    return true;
}

/** The result once the move has handed the frame back: the creep's fate, read from our last-hit and deny counters. */
function watch(bot: Unit, a: Attempt, now: number): void {
    if (!bot.IsAlive()) return finish(bot, a, "died", now);
    const dead = !live(a.creep);
    if (a.kind === "feed") {
        if (!dead) a.onr = math.max(a.onr, drawnOn(bot, a.creep).length);
        if (dead) return finish(bot, a, counter(bot, "GetDenies") > a.dn0 ? "denied" : "lost", now);
        if (now - (a.droppedAt ?? a.startedAt) > SETTINGS.FeedWatch) return finish(bot, a, "alive", now);
    } else if (a.kind === "back") {
        let out = 0;
        for (const s0 of a.start ?? []) {
            const u = s0.unit;
            const l = seenAt(u);
            if (l !== undefined && d2(l, a.back) <= SETTINGS.BackOut) out++;
        }
        a.out = out;
        return finish(bot, a, out > 0 ? "ok" : "stayed", now);
    } else if (a.kind === "tower") {
        if (now - (a.walkedAt ?? a.startedAt) < SETTINGS.TowerWatch) return;
        let out = 0;
        const tl = a.tower!.GetLocation();
        for (const s0 of a.start ?? []) {
            const u = s0.unit;
            const l = seenAt(u);
            if (l !== undefined && d2(l, tl) >= TowerOrderR()) out++;
        }
        a.out = out;
        return finish(bot, a, out > 0 ? "ok" : "stayed", now);
    } else {
        if (!dead && seenAt(a.creep) !== undefined) a.ld = math.floor(GetUnitToUnitDistance(bot, a.creep));
        if (dead) {
            const ours = counter(bot, "GetLastHits") > a.lh0;
            const c1 = a.con !== undefined ? heroTally(a.con) : undefined;
            a.by = ours ? "us" : c1 !== undefined && a.clh0 !== undefined ? (c1 > a.clh0 ? "hero" : "none") : undefined;
            return finish(bot, a, ours ? "ok" : "lost", now);
        }
        if (now - (a.walkedAt ?? a.startedAt) > SETTINGS.DragWatch) return finish(bot, a, "alive", now);
    }
}

/**
 * Keeps the order's hero, or re-picks it (orderTarget's rule) once it has left vision: any visible enemy hero draws the creeps
 * (EC-053), so losing the first one need not end the move (obs0611: 11% of feeds ended `cancelled` that way). False when none is seen.
 */
function retarget(bot: Unit, a: Attempt): boolean {
    if (valid(a.hero)) return true;
    const h = orderTarget(bot);
    if (h === undefined) return false;
    a.hero = h;
    a.tpid = h.GetPlayerID();
    return true;
}

/** The move's frame: true while it gives the bot's orders (approach, the draw, the walk back). */
function act(bot: Unit, a: Attempt, now: number): boolean {
    const pid = bot.GetPlayerID();
    a.hpMin = math.min(a.hpMin, bot.GetHealth());
    if (!bot.IsAlive()) {
        finish(bot, a, "died", now);
        return false;
    }
    if (a.orderedAt === undefined && !retarget(bot, a)) {
        finish(bot, a, "cancelled", now);
        return false;
    }
    if (a.orderedAt === undefined && a.kind === "drag" && !live(a.creep)) {
        finish(bot, a, "cancelled", now);
        return false;
    }
    if ((a.hp0 - bot.GetHealth()) / math.max(1, bot.GetMaxHealth()) > SETTINGS.HurtShare) {
        finish(bot, a, "hurt", now);
        return false;
    }
    if (a.phase === "approach") {
        const at = a.approach!;
        // The walk may last ApproachTimeMax: an enemy hero that comes into reach of the approach point (or the feed's walk-back
        // point) during it ends the move before the bot walks into its attacks (review 2026-11-06-aggro-walkin M1).
        const heroes = enemyHeroes(bot, 1600);
        const unsafe = a.kind === "drag" ? !noDeeper(a.from!, at, heroes) : !heroSafe(at, heroes, SETTINGS.UnsafeMargin) || (a.kind === "feed" && !heroSafe(a.back, heroes, SETTINGS.UnsafeMargin));
        if (unsafe) {
            finish(bot, a, "unsafe", now);
            return false;
        }
        if (GetUnitToLocationDistance(bot, at) > 60 && now - a.startedAt < a.approachTime) {
            bot.Action_MoveToLocation(at);
            return true;
        }
        if (!live(a.creep) || !retarget(bot, a)) {
            finish(bot, a, "cancelled", now);
            return false;
        }
        a.phase = "walk";
    }
    if (a.orderedAt === undefined) {
        const near = enemyCreepsNear(bot, bot.GetLocation(), 500);
        a.near = near.length;
        a.start = near.map((c) => ({ unit: c, x: c.GetLocation().x, y: c.GetLocation().y }));
        a.td = math.floor(GetUnitToUnitDistance(bot, a.hero));
        if (a.kind === "drag" && live(a.creep)) {
            a.cd = math.floor(GetUnitToUnitDistance(bot, a.creep));
            // The draw takes creeps within 500 of us at the order only (EC-053): a creep out of it would not follow.
            if (a.cd > SETTINGS.DragOrderR) {
                finish(bot, a, "far", now);
                return false;
            }
            a.c0 = a.creep.GetLocation();
            a.cf = 0;
        }
        bot.Action_AttackUnit(a.hero, true);
        a.orderedAt = now;
        orderedAt[pid] = now;
        CoreTrade.NotePrimed(pid, now);
        laneDraw[laneKey(bot.GetTeam(), bot.GetAssignedLane())] = { pid, at: now };
        if (a.kind === "feed") fed.set(a.creep, true);
        if (a.nd !== undefined) a.nd++;
        return true;
    }
    const t = now - a.orderedAt;
    a.drawn = math.max(a.drawn, drawnOn(bot, bot).length);
    a.mv = math.max(a.mv, MovedOf(a.start));
    if (t >= SETTINGS.DrawCheck && a.drawn === 0 && a.mv === 0) {
        finish(bot, a, "no_draw", now);
        return false;
    }
    if (a.kind === "feed") {
        let nearest: number | undefined;
        if (live(a.creep)) {
            for (const c of drawnOn(bot, bot)) {
                const d = GetUnitToUnitDistance(c, a.creep);
                if (nearest === undefined || d < nearest) nearest = d;
            }
            for (const s0 of a.start ?? []) {
                const u = s0.unit;
                const l = seenAt(u);
                if (l === undefined || d2(l, Vector(s0.x, s0.y, 0)) < SETTINGS.MovedR) continue;
                const d = GetUnitToUnitDistance(u, a.creep);
                if (nearest === undefined || d < nearest) nearest = d;
            }
        }
        if (!live(a.creep)) {
            a.phase = "watch";
            a.droppedAt = now;
            return false;
        }
        if (DropNow(t, a.drawn + a.mv, nearest)) {
            bot.Action_AttackUnit(a.creep, true);
            a.droppedAt = now;
            a.phase = "watch";
            return true;
        }
        bot.Action_MoveToLocation(a.back);
        return true;
    }
    if (a.kind === "back") {
        if (GetUnitToLocationDistance(bot, a.back) > SETTINGS.BackArrive && now - a.startedAt < SETTINGS.BackWalk) {
            if (drawnOn(bot, bot).length === 0 && CooldownClear(now, orderedAt[pid], CoreTrade.PrimedAt(pid)) && retarget(bot, a)) {
                bot.Action_AttackUnit(a.hero, true);
                a.orderedAt = now;
                orderedAt[pid] = now;
                CoreTrade.NotePrimed(pid, now);
                laneDraw[laneKey(bot.GetTeam(), bot.GetAssignedLane())] = { pid, at: now };
                a.nd = (a.nd ?? 0) + 1;
                return true;
            }
            bot.Action_MoveToLocation(a.back);
            return true;
        }
        a.walkedAt = now;
        a.phase = "watch";
        return false;
    }
    if (a.kind === "tower") {
        if (t < SETTINGS.TowerWalk) {
            bot.Action_MoveToLocation(a.back);
            return true;
        }
        a.walkedAt = now;
        a.phase = "watch";
        return false;
    }
    // drag: walk the drawn creeps back, then the body takes the last hit as it comes due.
    if (live(a.creep) && a.cf === 0) {
        const at = a.creep.GetAttackTarget();
        const l = seenAt(a.creep);
        if ((at !== undefined && at !== null && !at.IsNull() && at === bot) || (l !== undefined && a.c0 !== undefined && d2(l, a.c0) >= SETTINGS.MovedR)) a.cf = 1;
    }
    if (t < SETTINGS.DragWalk && live(a.creep)) {
        bot.Action_MoveToLocation(a.back);
        return true;
    }
    a.walkedAt = now;
    if (live(a.creep) && valid(a.hero)) a.hd = math.floor(GetUnitToUnitDistance(a.hero, a.creep));
    if (live(a.creep)) a.chp = math.floor(frac(a.creep) * 100) / 100;
    a.phase = "watch";
    return false;
}

function skip(bot: Unit, why: string, now: number, ad?: number): void {
    const pid = bot.GetPlayerID();
    const last = lastSkip[pid];
    if (last !== undefined && (last.why === why || now - last.at < SETTINGS.SkipEvery)) return;
    lastSkip[pid] = { why, at: now };
    Telemetry.Event("aggro_skip", [
        ["pid", pid],
        ["role", roleOf(bot) ?? "?"],
        ["why", why],
        ["ad", ad !== undefined ? math.floor(ad) : undefined],
    ]);
}

/** Steps the bot's open attempt: the acting frame's result, or undefined when nothing acted (watching, ended or none). */
function stepOpen(bot: Unit, now: number): boolean | undefined {
    const pid = bot.GetPlayerID();
    const a = attempts[pid];
    if (a !== undefined && Stale(a.phase, now - a.steppedAt, a.left !== undefined)) finish(bot, a, "stale", now, now - a.steppedAt);
    else if (a !== undefined) {
        a.steppedAt = now;
        a.left = undefined;
    }
    if (a === undefined || attempts[pid] !== a) return undefined;
    if (a.phase !== "watch") return act(bot, a, now);
    if (a.kind === "feed") {
        // The deny reach is positioning's: lane_spot anchors on the fed creep once it is going down (H1 input `fed`).
        Laning.SetFed(bot, a.creep);
        if (Laning.SpotInfo(bot)?.anchor === "fed") a.sty = 1;
    }
    watch(bot, a, now);
    return undefined;
}

/** Steps only an open attempt, never deciding a new draw: a core's draw while its laning body is not running. */
export function StepOpen(bot: Unit): boolean {
    return stepOpen(bot, DotaTime()) ?? false;
}

/**
 * One frame of the module for this bot: reads a running move's result, steps a running move, or decides whether to start one.
 * True when it gave the bot's order this frame (the caller's other steps then stay off).
 */
export function Step(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const acted = stepOpen(bot, now);
    if (acted !== undefined) return acted;
    if (attempts[pid] !== undefined || !Owns(bot)) return false;
    const last = decidedAt[pid];
    if (last !== undefined && now - last < SETTINGS.Every) return false;
    decidedAt[pid] = now;
    const g = gate(bot, now);
    const heroes = enemyHeroes(bot, 1600);
    const cands = dragCands(bot, heroes);
    if (g !== undefined) {
        logLooks(bot, cands, g, now);
        skip(bot, g, now);
        return false;
    }
    // The drag has its own safety (noDeeper): a bot in an enemy hero's reach may still drag away from it.
    let next = tryDrag(bot, heroes, cands, now);
    logLooks(bot, cands, undefined, now);
    if (next === undefined && !heroSafe(bot.GetLocation(), heroes)) {
        skip(bot, "reach", now);
        return false;
    }
    let why = "drag";
    let ad: number | undefined;
    if (next === undefined) {
        const [tw, twWhy] = tryTower(bot, heroes, now);
        next = tw;
        why = "tower:" + twWhy;
        if (next === undefined && twWhy === "none") {
            const [fd, fdWhy, fdAd] = tryFeed(bot, heroes, now);
            next = fd;
            ad = fdAd;
            why = "feed:" + fdWhy;
        }
    }
    if (next === undefined) {
        skip(bot, why, now, ad);
        return false;
    }
    lastSkip[pid] = undefined;
    start(bot, next);
    return act(bot, next, now);
}

/** An attempt is open (acting or watching): its caller keeps stepping it so it ends cleanly. */
export function Pending(bot: Unit): boolean {
    return attempts[bot.GetPlayerID()] !== undefined;
}

/** A move is giving this bot's orders (not only watching its result). */
export function Acting(bot: Unit): boolean {
    const a = attempts[bot.GetPlayerID()];
    return a !== undefined && a.phase !== "watch";
}

export function Reset(): void {
    for (const k in attempts) attempts[k as unknown as number] = undefined;
    Laning.ClearFed();
    for (const k in orderedAt) orderedAt[k as unknown as number] = undefined;
    for (const k in decidedAt) decidedAt[k as unknown as number] = undefined;
    for (const k in laneDraw) laneDraw[k] = undefined;
    for (const k in pushCache) pushCache[k] = undefined;
    for (const k in lastSkip) lastSkip[k as unknown as number] = undefined;
    for (const k in towerEnd) towerEnd[k as unknown as number] = undefined;
}
