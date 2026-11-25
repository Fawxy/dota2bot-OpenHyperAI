/**
 * The lane creep offer as a shadow (no-creep-unpaid proposal s4a; slice oha-creep-offer). No row, no switch, no order: for
 * each hero `states/trip_table` lets act on a `creep` row it keeps one opportunity per lane creep the engine's `laneTargets`
 * offers (last hits and denies, every kind), answers the offer's three questions on it (`offer.ts`) and writes one
 * `ev=choice kind=creep src=shadow go=0 why=off` line when the creep leaves the hero's nearby lane creep lists.
 *
 * The answers are kept as they stood when `Arrive` first said ok, else at the largest slack seen (`want` says which).
 * Everything the line needs is stored while the creep is listed: a handle that is not in this tick's lists is only a table
 * key here, never called (BACKLOG 0.14).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { Lane, Unit, UnitType } from "bots/ts_libs/dota";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHits from "bots/FunLib/humaniser/lane_hits";
import * as LaneOffers from "bots/FunLib/humaniser/lane_offers";
import * as LaneRead from "bots/FunLib/humaniser/lane_read";
import * as Offer from "bots/FunLib/humaniser/offer";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /** A later read replaces the best-slack snapshot only by this much (s): the snapshot's reads cost more than a tick's (judgement). */
    SlackStep: 0.1,
    /** A slack above this reads as this in the line (the engine's `dies` is infinite for a creep nothing is hitting; judgement). */
    SlackCap: 99,
    /** Towers are read this far from the hero: the reader radius plus a tower's reach, rounded up (judgement). */
    TowerRadius: 2500,
};

type Timed = Unit & { GetSecondsPerAttack?(): number };

/** The answers and facts as they stood at one read of the creep. */
interface Snap {
    walk: number;
    due: number;
    dies: number;
    slk: number;
    hpp: number;
    mode: string;
    crhp: number;
    given: Offer.Given;
    path: Offer.PathCostAnswer;
    /** Whose hit the forecast says kills the creep: me, mate, foe, creep, tower, none; and when. */
    kb: string;
    kt?: number;
    md: number;
    /** The highest hit among visible enemy heroes within their own range of the creep, and how many are. */
    ed: number;
    ein: number;
}

interface Opp {
    creep: Unit;
    lane: number;
    first: number;
    ck: string;
    who: string;
    okFrom?: number;
    okTo?: number;
    snap: Snap;
    atk: boolean;
}

/** pid -> creep id -> its opportunity. */
const opps: Record<number, Record<number, Opp | undefined> | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(opps)) opps[k as number] = undefined;
}

function r1(x: number): number {
    return math.floor(x * 10 + 0.5) / 10;
}

function r2(x: number): number {
    return math.floor(x * 100 + 0.5) / 100;
}

function dist(a: { x: number; y: number }, b: { x: number; y: number }): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/** A bot whose position the trip table lets act on a creep offer. */
export function MayOffer(bot: Unit): boolean {
    return bot.IsBot() && TripTable.Does("creep", LaneConfig.PositionOf(bot));
}

function enemyFormat(es: Offer.EnemyCost[]): string {
    const out: string[] = [];
    for (const e of es) out.push(`${e.pid}:${math.floor(e.dist)}:${math.floor(e.range)}:${math.floor(e.dmg)}:${r2(e.spa)}:${r2(e.exp)}`);
    return out.join(";");
}

function line(bot: Unit, o: Opp): void {
    const s = o.snap;
    const want = o.okFrom !== undefined;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "creep"],
        ["go", 0],
        ["want", want ? 1 : 0],
        ["why", "off"],
        ["src", "shadow"],
        ["lane", o.lane],
        ["slot", o.first],
        ["cid", Telemetry.CreepId(o.creep)],
        ["ck", o.ck],
        ["who", o.who],
        ["wo", o.okFrom !== undefined ? r1(o.okFrom - o.first) : undefined],
        ["wl", o.okFrom !== undefined && o.okTo !== undefined ? r1(o.okTo - o.okFrom) : undefined],
        ["walk", r2(s.walk)],
        ["due", r2(s.due)],
        ["dies", s.dies === math.huge ? -1 : r2(s.dies)],
        ["slk", r2(math.min(s.slk, SETTINGS.SlackCap))],
        ["hpp", r2(s.hpp)],
        ["mode", s.mode],
        ["crhp", math.floor(s.crhp)],
        ["g2", s.given.due],
        ["g2r", s.given.ranged],
        ["pc", s.path.creeps],
        ["pd", math.floor(s.path.cdps + 0.5)],
        ["ptw", s.path.tower ? 1 : 0],
        ["eh", s.path.covering],
        ["exs", r2(s.path.exposure)],
        ["en", enemyFormat(s.path.enemies)],
        ["kb", s.kb],
        ["kt", s.kt !== undefined ? r2(s.kt) : undefined],
        ["md", math.floor(s.md)],
        ["ed", math.floor(s.ed)],
        ["ein", s.ein],
        ["atk", o.atk ? 1 : 0],
    ]);
}

function closeAll(bot: Unit, pid: number): void {
    const m = opps[pid];
    if (m === undefined) return;
    for (const [cid, o] of pairs(m)) {
        line(bot, o);
        m[cid] = undefined;
    }
}

const LANES: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];

/** The creep's lane row in the lane read, the hero's own lane tried first. */
function rowOf(bot: Unit, creep: Unit): LaneHits.CreepHits | undefined {
    const team = bot.GetTeam();
    const own = bot.GetAssignedLane();
    const first = LaneHits.Of(team, own, creep);
    if (first !== undefined) return first;
    for (const lane of LANES) {
        if (lane === own) continue;
        const r = LaneHits.Of(team, lane, creep);
        if (r !== undefined) return r;
    }
    return undefined;
}

/** What one call reads about the world, once, when a snapshot first needs it. */
interface Frame {
    hero: { x: number; y: number };
    speed: number;
    hull: number;
    reach: number;
    enemyCreeps: Unit[];
    towers?: Offer.PathTower[];
    creeps?: Offer.PathCreep[];
    enemies?: Offer.PathEnemy[];
}

function towersOf(bot: Unit, f: Frame): Offer.PathTower[] {
    if (f.towers !== undefined) return f.towers;
    const out: Offer.PathTower[] = [];
    for (const t of bot.GetNearbyTowers(SETTINGS.TowerRadius, true)) {
        const at = t.GetLocation();
        out.push({ x: at.x, y: at.y, reach: t.GetAttackRange() + t.GetBoundingRadius() + f.hull });
    }
    f.towers = out;
    return out;
}

function creepsOf(f: Frame): Offer.PathCreep[] {
    if (f.creeps !== undefined) return f.creeps;
    const out: Offer.PathCreep[] = [];
    for (const c of f.enemyCreeps) {
        const at = c.GetLocation();
        const spa = (c as Timed).GetSecondsPerAttack?.() ?? 1;
        out.push({ x: at.x, y: at.y, reach: c.GetAcquisitionRange() + c.GetBoundingRadius() + f.hull, dps: c.GetAttackDamage() / math.max(spa, 0.1) });
    }
    f.creeps = out;
    return out;
}

function enemiesOf(f: Frame): Offer.PathEnemy[] {
    if (f.enemies !== undefined) return f.enemies;
    const out: Offer.PathEnemy[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!e.IsAlive() || !e.CanBeSeen()) continue;
        const at = e.GetLocation();
        if (at === null || at === undefined) continue;
        out.push({ x: at.x, y: at.y, pid: e.GetPlayerID(), range: e.GetAttackRange(), hull: e.GetBoundingRadius(), dmg: e.GetAttackDamage(), spa: (e as Timed).GetSecondsPerAttack?.() ?? 1 });
    }
    f.enemies = out;
    return out;
}

/** Whose hit the forecast says kills the creep, and when. */
function race(bot: Unit, creep: Unit): [string, number | undefined] {
    const row = rowOf(bot, creep);
    if (row === undefined) return ["none", undefined];
    const k = LaneHits.KillingHit(row);
    if (k === undefined) return ["none", undefined];
    if (k.by === "tower") return ["tower", k.t];
    if (k.by === "creep") return ["creep", k.t];
    const a = k.attacker as unknown as Unit;
    if (a === bot) return ["me", k.t];
    return [a.GetTeam() === bot.GetTeam() ? "mate" : "foe", k.t];
}

function snapshot(bot: Unit, f: Frame, t: Lib.Verbs.LaneTarget, slack: number, others: Offer.Other[]): Snap {
    const creep = t.creep as unknown as Unit;
    const at = creep.GetLocation();
    const spot = Offer.StandSpot(f.hero, at, f.reach + creep.GetBoundingRadius());
    const path = Offer.PathCost({ from: f.hero, spot, speed: f.speed, hull: f.hull, creeps: creepsOf(f), towers: towersOf(bot, f), enemies: enemiesOf(f) });
    let ed = 0;
    let ein = 0;
    const hull = creep.GetBoundingRadius();
    for (const e of enemiesOf(f)) {
        if (dist(e, at) > e.range + e.hull + hull) continue;
        ein++;
        if (e.dmg > ed) ed = e.dmg;
    }
    const [kb, kt] = race(bot, creep);
    return {
        walk: t.walk,
        due: t.due,
        dies: t.dies,
        slk: slack,
        hpp: bot.GetHealth() / math.max(bot.GetMaxHealth(), 1),
        mode: HDebug.ModeName(bot.GetActiveMode()),
        crhp: creep.GetHealth(),
        given: Offer.GivenUp(others, 2 * t.walk + LaneOffers.ARRIVE_SLACK),
        path,
        kb,
        kt,
        md: bot.GetAttackDamage(),
        ed,
        ein,
    };
}

/**
 * One call per hero (the tick's ten a second): opens, updates and closes the hero's opportunities. Reads and logs; nothing is
 * ordered.
 */
export function Shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled() || !MayOffer(bot)) return;
    const pid = bot.GetPlayerID();
    if (!bot.IsAlive() || Drill.Held(bot) || !LaneConfig.InLaningPhase()) {
        closeAll(bot, pid);
        return;
    }
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return;
    const now = DotaTime();
    const taskBot = bot as unknown as Lib.TaskUnit;
    const targets = verbs.laneTargets(taskBot, { radius: LaneHits.READER_RADIUS, within: 1 });

    const listed = new LuaTable<Unit, boolean>();
    const mine = bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false);
    const theirs = bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, true);
    for (const c of mine) listed.set(c, true);
    for (const c of theirs) listed.set(c, true);

    let m = opps[pid];
    if (m !== undefined) {
        for (const [cid, o] of pairs(m)) {
            if (listed.get(o.creep) === true) continue;
            line(bot, o);
            m[cid] = undefined;
        }
    }
    if (targets.length === 0) return;
    if (m === undefined) {
        m = {};
        opps[pid] = m;
    }

    const loc = bot.GetLocation();
    const f: Frame = { hero: { x: loc.x, y: loc.y }, speed: math.max(100, bot.GetCurrentMovementSpeed()), hull: bot.GetBoundingRadius(), reach: bot.GetAttackRange() + bot.GetBoundingRadius(), enemyCreeps: theirs };
    const atkTarget = bot.GetAttackTarget();
    const slot = math.floor(now * 10) / 10;

    for (const t of targets) {
        const creep = t.creep as unknown as Unit;
        const cid = Telemetry.CreepId(creep);
        const a = Offer.Arrive(t.walk, LaneOffers.ARRIVE_SLACK, t.dies);
        let o = m[cid];
        const others: Offer.Other[] = [];
        if (o === undefined || (o.okFrom === undefined && (a.ok || a.slack > o.snap.slk + SETTINGS.SlackStep))) {
            for (const x of targets) if (x !== t && x.walk <= 0) others.push({ due: x.due, ranged: x.ranged });
        }
        if (o === undefined) {
            o = {
                creep,
                lane: bot.GetAssignedLane(),
                first: slot,
                ck: LaneRead.CreepKind(creep.GetUnitName()),
                who: t.kind === "deny" ? "o" : "t",
                snap: snapshot(bot, f, t, a.slack, others),
                atk: false,
            };
            m[cid] = o;
        } else if (o.okFrom === undefined && (a.ok || a.slack > o.snap.slk + SETTINGS.SlackStep)) {
            o.snap = snapshot(bot, f, t, a.slack, others);
        }
        if (a.ok) {
            if (o.okFrom === undefined) o.okFrom = now;
            o.okTo = now;
        }
        if (atkTarget !== null && atkTarget !== undefined && atkTarget === creep) o.atk = true;
    }
}
