/**
 * Lane creep aggro (slice lane-aggro, `Ours.LaneAggro`): a laner draws enemy lane creeps on purpose with an attack order on an
 * enemy hero (EC-053: creeps within 500 of the ordering hero chase it for up to 2.3 s; one draw per 3 s per hero), then walks
 * them where it wants them. Two moves, one module for both roles (a lane technique, so bot code, not an engine verb):
 * - `feed`: the enemy wave is walked back onto our ranged creep (any HP, user 05/11/2026). Their melee creeps kill it quickly,
 *   we deny it (the deny itself is the laning body's), and losing our wave's biggest hitter early tilts the clash toward our
 *   tower. Read on the lane push: not when the clash already sits near our tower or is coming in.
 * - `drag`: one or two enemy creeps about to die beside an enemy hero are walked away from that hero, so the last hit is ours
 *   and a deny means the enemy walks up.
 * Cores do both. A support inherits them only while its lane's core is away (user 05/11/2026). One draw per lane at a time,
 * and none while our pull is out on that lane (the pull drags our wave away; feeding it then gives the wave away twice).
 * Stepped from mode_laning_generic's Think (cores, after the body's running swing) and from support_lane's step list.
 */
import { BotMode, Lane, Team, Tower, Unit, Vector } from "bots/ts_libs/dota";
import type * as Lib from "bots/FunLib/engine/tasks";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as PullJob from "bots/FunLib/humaniser/pull_job";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as CoreTrade from "bots/FunLib/humaniser/states/core_trade";
import * as Laning from "bots/FunLib/humaniser/states/laning";

export type Kind = "feed" | "drag";
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
    /** No draw this close to an enemy tower (an attack order near it can turn the tower). */
    TowerR: 1000,
    /** Feed: our ranged creep at this HP fraction or more (below it the body's deny already wants it). */
    FeedCreepHp: 0.5,
    /** Feed: enemy melee creeps on our wave within this of our ranged creep, and at least FeedMinCreeps of them. */
    FightR: 700,
    FeedMinCreeps: 2,
    /** Feed: the approach point stands this far back (toward our tower) from the enemy creeps' centre, at most ApproachMax walk away. */
    ApproachBack: 380,
    ApproachMax: 350,
    ApproachTime: 1.2,
    /** Feed: walk back to this far behind our ranged creep, so it is the nearest of ours when the creeps re-pick. */
    FeedBack: 250,
    /** Feed: the drop (attack order on our ranged creep) once a drawn creep is this close to it, after DropAfter, or at DropBy. */
    DropNear: 220,
    DropAfter: 0.8,
    DropBy: 1.8,
    /** No creep drawn this long after the order: `no_draw`. */
    DrawCheck: 0.6,
    /** Feed: the clash where it sits between the T1s (0 ours, 1 theirs) at least this far out. */
    FeedMinQ: 0.3,
    /** Drag: a last hit due in this window (s): sooner the body just takes it, later it is not worth a draw yet. */
    DragDueMin: 0.8,
    DragDueMax: 3,
    /** Drag: the enemy hero contests within its attack range plus this of the creep. */
    DragContest: 150,
    DragBack: 300,
    DragWalk: 1.2,
    /** A lane hit due this soon (any kind) keeps the body's frame: no feed. */
    BusyWithin: 1.5,
    /** The move stops when the bot has lost this share of its max HP since the order. */
    HurtShare: 0.12,
    /** Results are read until then: the fed creep's death, the dragged creep's death. */
    FeedWatch: 9,
    DragWatch: 3.5,
    /** A support's lane core is away when no allied core of that lane is alive within this. */
    CoreNear: 1600,
};

interface Attempt {
    kind: Kind;
    phase: PhaseName;
    startedAt: number;
    orderedAt?: number;
    walkedAt?: number;
    droppedAt?: number;
    hero: Unit;
    creep: Unit;
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
}

const attempts: Record<number, Attempt | undefined> = {};
const orderedAt: Record<number, number | undefined> = {};
const decidedAt: Record<number, number | undefined> = {};
/** Our ranged creeps already fed (one feed per creep). */
const fed: LuaTable<Unit, boolean> = new LuaTable();
/** Last draw per team and lane: one draw per lane at a time. */
const laneDraw: Record<string, { pid: number; at: number } | undefined> = {};
const pushCache: Record<string, { t: number; r: LanePush.Reading | undefined } | undefined> = {};

function laneKey(team: number, lane: Lane): string {
    return `${team}:${lane}`;
}

function valid(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.CanBeSeen();
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

/** Pure: whether the lane push reading wants the wave tilted toward us (the clash not near our tower, not coming in). */
export function FeedWanted(r: { state: string; q: number } | undefined): boolean {
    if (r === undefined) return false;
    return r.state !== "IN" && r.q >= SETTINGS.FeedMinQ;
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
function heroSafe(at: Vector, heroes: Unit[]): boolean {
    for (const h of heroes) {
        if (GetUnitToLocationDistance(h, at) <= h.GetAttackRange() + h.GetBoundingRadius() * 2 + SETTINGS.HeroMargin) return false;
    }
    return true;
}

function nearTower(at: Vector, team: number): boolean {
    const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
    for (const id of [Tower.Top1, Tower.Mid1, Tower.Bot1, Tower.Top2, Tower.Mid2, Tower.Bot2]) {
        const t = GetTower(enemy, id);
        if (t !== undefined && t !== null && t.IsAlive() && d2(t.GetLocation(), at) <= SETTINGS.TowerR) return true;
    }
    return false;
}

/** The enemy hero the order names: the nearest visible one, not by its own tower. */
function orderTarget(bot: Unit, heroes: Unit[]): Unit | undefined {
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const h of heroes) {
        if (nearTower(h.GetLocation(), bot.GetTeam())) continue;
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
    if (nearTower(bot.GetLocation(), bot.GetTeam())) return "tower";
    if (allyPullOut(bot)) return "pull";
    return undefined;
}

function start(bot: Unit, a: Attempt): void {
    attempts[bot.GetPlayerID()] = a;
}

function tryDrag(bot: Unit, heroes: Unit[], now: number): Attempt | undefined {
    const here = bot.GetLocation();
    for (const t of laneTargets(bot, SETTINGS.DragDueMax, false)) {
        if (t.kind !== "lasthit" || t.due < SETTINGS.DragDueMin || t.due > SETTINGS.DragDueMax) continue;
        const creep = t.creep as unknown as Unit;
        if (!valid(creep) || GetUnitToUnitDistance(bot, creep) > SETTINGS.DrawR) continue;
        let contester: Unit | undefined;
        for (const h of heroes) {
            if (GetUnitToUnitDistance(h, creep) <= h.GetAttackRange() + h.GetBoundingRadius() + SETTINGS.DragContest) contester = h;
        }
        if (contester === undefined) continue;
        const hero = orderTarget(bot, heroes);
        if (hero === undefined) return undefined;
        const back = along(here, backDir(bot.GetTeam(), bot.GetAssignedLane(), here), SETTINGS.DragBack);
        if (!heroSafe(back, heroes)) return undefined;
        return newAttempt(bot, "drag", "walk", hero, creep, back, undefined, now);
    }
    return undefined;
}

function tryFeed(bot: Unit, heroes: Unit[], now: number): Attempt | undefined {
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    let ranged: Unit | undefined;
    for (const c of bot.GetNearbyLaneCreeps(1200, false)) {
        if (valid(c) && isLaneCreep(c) && isRanged(c) && fed.get(c) !== true && frac(c) >= SETTINGS.FeedCreepHp) ranged = c;
    }
    if (ranged === undefined) return undefined;
    const fighting = enemyCreepsNear(bot, ranged.GetLocation(), SETTINGS.FightR);
    if (fighting.length < SETTINGS.FeedMinCreeps) return undefined;
    let cx = 0;
    let cy = 0;
    for (const c of fighting) {
        cx += c.GetLocation().x;
        cy += c.GetLocation().y;
    }
    const centre = Vector(cx / fighting.length, cy / fighting.length, ranged.GetLocation().z);
    const dir = backDir(team, lane, centre);
    const approach = along(centre, dir, SETTINGS.ApproachBack);
    if (GetUnitToLocationDistance(bot, approach) > SETTINGS.ApproachMax) return undefined;
    if (enemyCreepsNear(bot, approach, SETTINGS.DrawR).length < SETTINGS.FeedMinCreeps) return undefined;
    const back = along(ranged.GetLocation(), dir, SETTINGS.FeedBack);
    if (!heroSafe(approach, heroes) || !heroSafe(back, heroes) || nearTower(approach, team)) return undefined;
    if (laneTargets(bot, SETTINGS.BusyWithin, true).length > 0) return undefined;
    const r = pushRead(team, lane);
    if (!FeedWanted(r)) return undefined;
    const hero = orderTarget(bot, heroes);
    if (hero === undefined) return undefined;
    const a = newAttempt(bot, "feed", "approach", hero, ranged, back, approach, now);
    a.q = r !== undefined ? math.floor(r.q * 100) / 100 : undefined;
    a.st = r?.state;
    return a;
}

function newAttempt(bot: Unit, kind: Kind, phase: PhaseName, hero: Unit, creep: Unit, back: Vector, approach: Vector | undefined, now: number): Attempt {
    return {
        kind,
        phase,
        startedAt: now,
        hero,
        creep,
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

function finish(bot: Unit, a: Attempt, result: string, now: number): void {
    attempts[bot.GetPlayerID()] = undefined;
    Telemetry.Event("aggro", [
        ["pid", bot.GetPlayerID()],
        ["role", a.role],
        ["kind", a.kind],
        ["result", result],
        ["tgt", a.hero.IsNull() ? undefined : a.hero.GetPlayerID()],
        ["near", a.near],
        ["drawn", a.drawn],
        ["onr", a.onr],
        ["dhp", a.hp0 - a.hpMin],
        ["hp", math.floor((a.hp0 / math.max(1, bot.GetMaxHealth())) * 100) / 100],
        ["q", a.q],
        ["st", a.st],
        ["hd", a.hd],
        ["drop", a.droppedAt !== undefined ? math.floor((a.droppedAt - (a.orderedAt ?? a.startedAt)) * 100) / 100 : undefined],
        ["dur", math.floor((now - a.startedAt) * 100) / 100],
    ]);
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

/** The result once the move has handed the frame back: the creep's fate, read from our last-hit and deny counters. */
function watch(bot: Unit, a: Attempt, now: number): void {
    if (!bot.IsAlive()) return finish(bot, a, "died", now);
    const dead = a.creep.IsNull() || !a.creep.IsAlive();
    if (a.kind === "feed") {
        if (!dead) a.onr = math.max(a.onr, drawnOn(bot, a.creep).length);
        if (dead) return finish(bot, a, counter(bot, "GetDenies") > a.dn0 ? "denied" : "lost", now);
        if (now - (a.droppedAt ?? a.startedAt) > SETTINGS.FeedWatch) return finish(bot, a, "alive", now);
    } else {
        if (dead) return finish(bot, a, counter(bot, "GetLastHits") > a.lh0 ? "ok" : "lost", now);
        if (now - (a.walkedAt ?? a.startedAt) > SETTINGS.DragWatch) return finish(bot, a, "alive", now);
    }
}

/** The move's frame: true while it gives the bot's orders (approach, the draw, the walk back). */
function act(bot: Unit, a: Attempt, now: number): boolean {
    const pid = bot.GetPlayerID();
    a.hpMin = math.min(a.hpMin, bot.GetHealth());
    if (!bot.IsAlive()) {
        finish(bot, a, "died", now);
        return false;
    }
    if (!valid(a.hero) || (a.kind === "drag" && (a.creep.IsNull() || !a.creep.IsAlive()))) {
        if (a.orderedAt === undefined) {
            finish(bot, a, "cancelled", now);
            return false;
        }
    }
    if ((a.hp0 - bot.GetHealth()) / math.max(1, bot.GetMaxHealth()) > SETTINGS.HurtShare) {
        finish(bot, a, "hurt", now);
        return false;
    }
    if (a.phase === "approach") {
        const at = a.approach!;
        if (GetUnitToLocationDistance(bot, at) > 60 && now - a.startedAt < SETTINGS.ApproachTime) {
            bot.Action_MoveToLocation(at);
            return true;
        }
        if (!a.creep.IsAlive() || !valid(a.hero)) {
            finish(bot, a, "cancelled", now);
            return false;
        }
        a.phase = "walk";
    }
    if (a.orderedAt === undefined) {
        a.near = enemyCreepsNear(bot, bot.GetLocation(), 500).length;
        bot.Action_AttackUnit(a.hero, true);
        a.orderedAt = now;
        orderedAt[pid] = now;
        CoreTrade.NotePrimed(pid, now);
        laneDraw[laneKey(bot.GetTeam(), bot.GetAssignedLane())] = { pid, at: now };
        if (a.kind === "feed") fed.set(a.creep, true);
        return true;
    }
    const t = now - a.orderedAt;
    a.drawn = math.max(a.drawn, drawnOn(bot, bot).length);
    if (t >= SETTINGS.DrawCheck && a.drawn === 0) {
        finish(bot, a, "no_draw", now);
        return false;
    }
    if (a.kind === "feed") {
        let nearest: number | undefined;
        if (a.creep.IsAlive()) {
            for (const c of drawnOn(bot, bot)) {
                const d = GetUnitToUnitDistance(c, a.creep);
                if (nearest === undefined || d < nearest) nearest = d;
            }
        }
        if (!a.creep.IsAlive()) {
            a.phase = "watch";
            a.droppedAt = now;
            return false;
        }
        if (DropNow(t, a.drawn, nearest)) {
            bot.Action_AttackUnit(a.creep, true);
            a.droppedAt = now;
            a.phase = "watch";
            return true;
        }
        bot.Action_MoveToLocation(a.back);
        return true;
    }
    // drag: walk the drawn creeps back, then the body takes the last hit as it comes due.
    if (t < SETTINGS.DragWalk && a.creep.IsAlive()) {
        bot.Action_MoveToLocation(a.back);
        return true;
    }
    a.walkedAt = now;
    if (a.creep.IsAlive() && valid(a.hero)) a.hd = math.floor(GetUnitToUnitDistance(a.hero, a.creep));
    a.phase = "watch";
    return false;
}

/**
 * One frame of the module for this bot: reads a running move's result, steps a running move, or decides whether to start one.
 * True when it gave the bot's order this frame (the caller's other steps then stay off).
 */
export function Step(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const a = attempts[pid];
    if (a !== undefined) {
        if (a.phase === "watch") {
            watch(bot, a, now);
        } else {
            return act(bot, a, now);
        }
    }
    if (attempts[pid] !== undefined || !Owns(bot)) return false;
    const last = decidedAt[pid];
    if (last !== undefined && now - last < SETTINGS.Every) return false;
    decidedAt[pid] = now;
    if (gate(bot, now) !== undefined) return false;
    const heroes = enemyHeroes(bot, 1600);
    if (heroes.length === 0 || !heroSafe(bot.GetLocation(), heroes)) return false;
    const next = tryDrag(bot, heroes, now) ?? tryFeed(bot, heroes, now);
    if (next === undefined) return false;
    start(bot, next);
    return act(bot, next, now);
}

/** A move is giving this bot's orders (not only watching its result). */
export function Acting(bot: Unit): boolean {
    const a = attempts[bot.GetPlayerID()];
    return a !== undefined && a.phase !== "watch";
}

export function Reset(): void {
    for (const k in attempts) attempts[k as unknown as number] = undefined;
    for (const k in orderedAt) orderedAt[k as unknown as number] = undefined;
    for (const k in decidedAt) decidedAt[k as unknown as number] = undefined;
    for (const k in laneDraw) laneDraw[k] = undefined;
    for (const k in pushCache) pushCache[k] = undefined;
}
