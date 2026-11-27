/**
 * The draw's offer (no-creep-unpaid proposal s6b; slice oha-aggro-shadow), logged as a shadow: no row acts on it yet. For each
 * core `states/trip_table` lets act on an `aggro` row, while their lane creeps fight ours near our ranged creep, it reads where the
 * hero would stand to draw them (within `Reach` of the nearest), where it would hand them to our ranged creep, and the go rule's
 * checks, and writes one `ev=choice kind=aggro src=shadow go=0 why=off` line per hero and our ranged creep when that creep leaves
 * the hero's lists (dies or goes out of reach) or the laning phase ends. Orders nothing.
 *
 * The line keeps the read with the fewest failed checks (the first of a tie) and its list, so the funnel is countable check by
 * check, and `want` 1 when some read failed none. Facts measured in `docs/reference/specifics/engine-physics.md`, "The draw".
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { Unit, UnitType } from "bots/ts_libs/dota";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHits from "bots/FunLib/humaniser/lane_hits";
import * as LaneOffers from "bots/FunLib/humaniser/lane_offers";
import * as LaneRead from "bots/FunLib/humaniser/lane_read";
import * as Offer from "bots/FunLib/humaniser/offer";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /** Seconds between a hero's reads, offset by player id as the creep offer's (judgement: a draw's chance lasts seconds). */
    Every: 0.2,
    /** The draw spot is this far (centre) from their nearest fighting creep: the measured 500 reach less a margin (judgement). */
    Reach: 450,
    /** Creeps within this of the draw spot (centre) are drawn (measured: 490 melee 4 of 4, 500 ranged 1 of 1, none at 510). */
    Drawn: 500,
    /** The hand-over spot is this far behind our ranged creep, away from the clash (measured: 2 of 2 handed over at 250). */
    Back: 250,
    /** Their creeps fighting within this of our ranged creep make the clash (judgement: about a wave's length). */
    Clash: 1200,
    /** Seconds from the order to the draw's end: melee let go at about 2.3 s, ranged 2.85 (measured); the window is twice the walk plus this. */
    Draw: 2.5,
    /** The longest walk to the draw spot (s), as the creep offer's `MAX_WALK` (judgement). */
    MaxWalk: 1.0,
    /** The draw spot must be this far outside an enemy tower's reach (attack range and both hulls; judgement). */
    TowerMargin: 100,
    /** The per-hero cooldown of the draw after an attack on a hero (s; Lane_Creeps, Type 1). */
    Cooldown: 3,
    /** A height difference (location z) under this is level ground: half the 128 step (judgement). */
    Step: 64,
    /** Towers are read this far from the hero (as the creep offer's `TowerRadius`). */
    TowerRadius: 2500,
};

export interface Vec {
    x: number;
    y: number;
}

function dist(a: Vec, b: Vec): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/** The draw spot: the hero's place when within `reach` of the creep, else the point at `reach` from it on the line to the hero. */
export function DrawSpot(this: void, hero: Vec, creep: Vec, reach: number): Vec {
    return Offer.StandSpot(hero, creep, reach);
}

/** The hand-over spot: `back` behind our ranged creep on the line from the clash's centre through it. */
export function HandSpot(this: void, ranged: Vec, clash: Vec, back: number): Vec {
    const d = dist(ranged, clash);
    if (d === 0) return { x: ranged.x, y: ranged.y };
    return { x: ranged.x + ((ranged.x - clash.x) / d) * back, y: ranged.y + ((ranged.y - clash.y) / d) * back };
}

/** A last hit or deny on offer, with what the draw does to it. */
export interface Target {
    kind: "lasthit" | "deny";
    /** Seconds until a swing ordered now would be due (the engine's `due`). */
    due: number;
    ranged: boolean;
    /** Their creep: it is among the drawn. */
    drawn: boolean;
    /** Our creep: something that would not be drawn is hitting it (their creep beyond the draw, an enemy hero or tower). */
    undrawn: boolean;
    /** Our ranged creep the draw would feed. */
    feed: boolean;
}

export interface Given {
    /** Every target but the feed due inside the window (the rule as first written). */
    all: number;
    /** Those the draw would cost (s6b): their creeps not drawn, and drawn melee (no row above takes a core's melee yet); our creeps an undrawn attacker keeps on time. */
    miss: number;
    /** Their drawn creeps due inside the window, ranged and melee (the creep row's hand-over takes the ranged). */
    dr: number;
    dm: number;
}

/** What the draw gives up over `window` seconds. */
export function GivenUp(this: void, ts: Target[], window: number): Given {
    const g: Given = { all: 0, miss: 0, dr: 0, dm: 0 };
    for (const t of ts) {
        if (t.feed || t.due >= window) continue;
        g.all++;
        if (t.kind === "lasthit") {
            if (t.drawn) {
                if (t.ranged) g.dr++;
                else {
                    g.dm++;
                    g.miss++;
                }
            } else g.miss++;
        } else if (t.undrawn) g.miss++;
    }
    return g;
}

/** One read's facts, as the checks read them. */
export interface Facts {
    /** `hg` (their fighting creeps on average higher than our ranged creep by more than Step) or `dn`. */
    k: string;
    walk: number;
    /** Their creeps already attacking our ranged creep. */
    onR: number;
    /** Ground heights (location z) of their fighting creeps on average and of our ranged creep. */
    fh: number;
    rh: number;
    seen: number;
    /** The draw spot's gap to the nearest enemy tower's reach (negative inside); undefined with none near. */
    tw?: number;
    covering: number;
    deadly: boolean;
    miss: number;
    /** Seconds since the hero last attacked a hero; undefined when not seen. */
    sinceHero?: number;
}

/** The go rule's failed checks, in the order s6b gives them. */
export function Checks(this: void, f: Facts): string[] {
    const out: string[] = [];
    if (f.k === "dn" && f.onR > 0) out.push("onr");
    if (f.miss > 0) out.push("due");
    if (f.walk > SETTINGS.MaxWalk) out.push("far");
    if (f.seen === 0) out.push("unseen");
    if (f.tw !== undefined && f.tw < SETTINGS.TowerMargin) out.push("etower");
    if (f.covering > 0) out.push("covered");
    if (f.deadly) out.push("danger");
    if (f.rh > f.fh + SETTINGS.Step) out.push("up");
    if (f.sinceHero !== undefined && f.sinceHero < SETTINGS.Cooldown) out.push("cd");
    return out;
}

/** One read as the line writes it. */
interface Snap {
    f: Facts;
    fails: string[];
    drawn: number;
    melee: number;
    rhp: number;
    /** Our lane creeps' HP within Clash of our ranged creep over their fighting creeps'. */
    pw: number;
    g: Given;
    danger: string;
}

interface Opp {
    ranged: Unit;
    cid: number;
    lane: number;
    first: number;
    snap: Snap;
    reads: number;
    wanted: number;
    okFrom?: number;
}

const opps: Record<number, Opp | undefined> = {};
const readAt: Record<number, number | undefined> = {};
const heroHitAt: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(opps)) opps[k as number] = undefined;
    for (const [k] of pairs(readAt)) readAt[k as number] = undefined;
    for (const [k] of pairs(heroHitAt)) heroHitAt[k as number] = undefined;
}

function due(pid: number, now: number): boolean {
    const n = math.floor((now + (pid % 2) * (SETTINGS.Every / 2)) / SETTINGS.Every + 1e-6);
    if (readAt[pid] === n) return false;
    readAt[pid] = n;
    return true;
}

function r2(x: number): number {
    return math.floor(x * 100 + 0.5) / 100;
}

function r1(x: number): number {
    return math.floor(x * 10 + 0.5) / 10;
}

/** A hero the read covers: a bot whose position the trip table lets act on an `aggro` row. */
export function MayOffer(bot: Unit): boolean {
    return bot.IsBot() && TripTable.Does("aggro", LaneConfig.PositionOf(bot));
}

function line(bot: Unit, o: Opp): void {
    const s = o.snap;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "aggro"],
        ["go", 0],
        ["want", o.okFrom !== undefined ? 1 : 0],
        ["why", "off"],
        ["src", "shadow"],
        ["lane", o.lane],
        ["slot", o.first],
        ["cid", o.cid],
        ["wo", o.okFrom !== undefined ? r1(o.okFrom - o.first) : undefined],
        ["ak", s.f.k],
        ["arf", s.fails.length > 0 ? s.fails.join(",") : "-"],
        ["ard", o.reads],
        ["awr", o.wanted],
        ["walk", r2(s.f.walk)],
        ["an", s.drawn],
        ["am", s.melee],
        ["ao", s.f.onR],
        ["af", math.floor(s.f.fh + 0.5)],
        ["ar", math.floor(s.f.rh + 0.5)],
        ["arp", r2(s.rhp)],
        ["apw", r2(s.pw)],
        ["aes", s.f.seen],
        ["atw", s.f.tw !== undefined ? math.floor(s.f.tw) : undefined],
        ["eh", s.f.covering],
        ["adl", s.danger],
        ["ag0", s.g.all],
        ["ag1", s.g.miss],
        ["agr", s.g.dr],
        ["agm", s.g.dm],
    ]);
}

function close(bot: Unit, pid: number): void {
    const o = opps[pid];
    if (o === undefined) return;
    line(bot, o);
    opps[pid] = undefined;
}

function sameTeam(u: Unit | null | undefined, team: number): boolean {
    return u !== null && u !== undefined && u.GetTeam() === team;
}

/** One read of the hero's chance: undefined when there is no clash near our ranged creep. */
function read(bot: Unit, ranged: Unit, theirs: Unit[], mine: Unit[], now: number): Snap | undefined {
    const team = bot.GetTeam();
    const rAt = ranged.GetLocation();
    const fight: Unit[] = [];
    let onR = 0;
    let cz = 0;
    for (const c of theirs) {
        const at = c.GetLocation();
        if (at === null || at === undefined || !c.IsAlive()) continue;
        const tg = c.GetAttackTarget();
        if (!sameTeam(tg, team)) continue;
        if (tg === ranged) onR++;
        if (LaneRead.CreepKind(c.GetUnitName()) === "f" || dist(at, rAt) > SETTINGS.Clash) continue;
        fight.push(c);
        cz += at.z;
    }
    if (fight.length === 0) return undefined;
    const loc = bot.GetLocation();
    const hero = { x: loc.x, y: loc.y };
    let near: Vec | undefined;
    let nd = math.huge;
    for (const c of fight) {
        const d = dist(hero, c.GetLocation());
        if (d < nd) {
            nd = d;
            near = c.GetLocation();
        }
    }
    const spot = DrawSpot(hero, near!, SETTINGS.Reach);
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const walk = math.max(0, nd - SETTINGS.Reach) / speed;
    const drawnSet = new LuaTable<Unit, boolean>();
    let drawn = 0;
    let melee = 0;
    for (const c of fight) {
        if (dist(spot, c.GetLocation()) > SETTINGS.Drawn) continue;
        drawnSet.set(c, true);
        drawn++;
        if (LaneRead.CreepKind(c.GetUnitName()) === "m") melee++;
    }
    const fh = cz / fight.length;
    const rh = rAt.z;
    const k = fh > rh + SETTINGS.Step ? "hg" : "dn";
    let ours = 0;
    let theirsHp = 0;
    for (const c of fight) theirsHp += c.GetHealth();
    for (const c of mine) {
        const at = c.GetLocation();
        if (at !== null && at !== undefined && c.IsAlive() && dist(at, rAt) <= SETTINGS.Clash) ours += c.GetHealth();
    }

    // Visible enemy heroes: the order's target, the cover on the draw spot, and who else is hitting our creeps.
    const enemies: Offer.PathEnemy[] = [];
    const hitters: Unit[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!e.IsAlive() || e.IsIllusion() || !e.CanBeSeen()) continue;
        const at = e.GetLocation();
        if (at === null || at === undefined) continue;
        enemies.push({ x: at.x, y: at.y, pid: e.GetPlayerID(), range: e.GetAttackRange(), hull: e.GetBoundingRadius(), dmg: e.GetAttackDamage(), spa: 1 });
        hitters.push(e);
    }
    let tw: number | undefined;
    const hull = bot.GetBoundingRadius();
    for (const t of bot.GetNearbyTowers(SETTINGS.TowerRadius, true)) {
        const at = t.GetLocation();
        if (at === null || at === undefined) continue;
        const gap = dist(spot, at) - (t.GetAttackRange() + t.GetBoundingRadius() + hull);
        if (tw === undefined || gap < tw) tw = gap;
        hitters.push(t);
    }
    const path = Offer.PathCost({ from: hero, spot, speed, hull, creeps: [], towers: [], enemies });

    // What comes due in the window, and what the draw does to each.
    const window = 2 * walk + SETTINGS.Draw;
    const ts: Target[] = [];
    const offers = Tasks.Verbs()!.laneTargets(bot as unknown as Lib.TaskUnit, { radius: LaneHits.READER_RADIUS, within: window });
    for (const t of offers) {
        if (t.kind === "prehit" || !LaneOffers.Reachable(t)) continue;
        const c = t.creep as unknown as Unit;
        let undrawn = false;
        if (t.kind === "deny") {
            for (const x of theirs) if (x.GetAttackTarget() === c && drawnSet.get(x) !== true) undrawn = true;
            for (const x of hitters) if (x.GetAttackTarget() === c) undrawn = true;
        }
        ts.push({ kind: t.kind, due: t.due, ranged: t.ranged, drawn: drawnSet.get(c) === true, undrawn, feed: c === ranged });
    }
    const g = GivenUp(ts, window);
    const danger = SafeGather.At(bot, Vector(spot.x, spot.y, 0)).level;
    const pid = bot.GetPlayerID();
    const hit = heroHitAt[pid];
    const f: Facts = { k, walk, onR, fh, rh, seen: enemies.length, tw, covering: path.covering, deadly: danger === "deadly", miss: g.miss, sinceHero: hit !== undefined ? now - hit : undefined };
    return { f, fails: Checks(f), drawn, melee, rhp: ranged.GetHealth() / math.max(ranged.GetMaxHealth(), 1), pw: ours / math.max(theirsHp, 1), g, danger };
}

function readFn(this: void, bot: Unit, ranged: Unit, theirs: Unit[], mine: Unit[], now: number): Snap | undefined {
    return read(bot, ranged, theirs, mine, now);
}
let timedRead: typeof readFn | undefined;

/**
 * The reference arm's denominator: the draw's chance read and logged (`src=shadow go=0 why=off`) for every core the trip table
 * covers. Reads and logs; nothing is ordered.
 */
export function Shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    if (!due(pid, now) || !MayOffer(bot)) return;
    if (!bot.IsAlive() || Drill.Held(bot) || !LaneConfig.InLaningPhase() || Tasks.Verbs() === undefined) {
        close(bot, pid);
        return;
    }
    const tg = bot.GetAttackTarget();
    if (tg !== null && tg !== undefined && tg.IsHero() && tg.GetTeam() !== bot.GetTeam()) heroHitAt[pid] = now;

    // Our ranged creep nearest the hero within the reader's radius.
    let ranged: Unit | undefined;
    let rd = math.huge;
    const loc = bot.GetLocation();
    const mine = bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false);
    for (const c of mine) {
        if (!c.IsAlive() || LaneRead.CreepKind(c.GetUnitName()) !== "r") continue;
        const at = c.GetLocation();
        if (at === null || at === undefined) continue;
        const d = dist(loc, at);
        if (d < rd) {
            rd = d;
            ranged = c;
        }
    }
    let o = opps[pid];
    if (o !== undefined && o.ranged !== ranged) {
        close(bot, pid);
        o = undefined;
    }
    if (ranged === undefined) return;
    if (timedRead === undefined) timedRead = Telemetry.PerfStep("AO:read", readFn);
    const s = timedRead(bot, ranged, bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, true), mine, now);
    if (s === undefined) return;
    if (o === undefined) {
        o = { ranged, cid: Telemetry.CreepId(ranged), lane: bot.GetAssignedLane(), first: math.floor(now * 10) / 10, snap: s, reads: 0, wanted: 0 };
        opps[pid] = o;
    } else if (s.fails.length < o.snap.fails.length) o.snap = s;
    o.reads++;
    if (s.fails.length === 0) {
        o.wanted++;
        if (o.okFrom === undefined) o.okFrom = now;
    }
}
