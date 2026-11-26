/**
 * The lane creep offer (no-creep-unpaid proposal s4a; slice oha-creep-offer), the read behind the creep row. Orders nothing:
 * for each hero `states/trip_table` lets act on a `creep` row it keeps one opportunity per lane creep the engine's `laneTargets`
 * offers (last hits and denies, every kind), answers the offer's three questions on it (`offer.ts`) and writes one
 * `ev=choice kind=creep` line when the creep leaves the hero's nearby lane creep lists: `src=shadow go=0 why=off` unless the
 * row (`creep_row.ts`, handed in by index.ts through SetRow so this read imports no row) noted a decision on it, then
 * `src=own` with the row's `go` and `why`.
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
    /**
     * Seconds between a hero's reads, the six cores offset by player id so they do not read on one frame (judgement: the step
     * cost 8.6 to 10.2% of script time at ten reads a second). What the lower rate loses: the window's edges and the close are
     * read to this interval, `atk` is sampled once an interval, and a creep offered and gone inside one interval is missed.
     * The offset is `pid % 2` (the tick gives an interval two slots), so two of a team's three cores read on the same frame.
     */
    Every: 0.2,
    /** A later read replaces the best-slack snapshot only by this much (s): the snapshot's reads cost more than a tick's (judgement). */
    SlackStep: 0.1,
    /** A slack above this reads as this in the line (the engine's `dies` is infinite for a creep nothing is hitting; judgement). */
    SlackCap: 99,
    /** Towers are read this far from the hero: the reader radius plus a tower's reach, rounded up (judgement). */
    TowerRadius: 2500,
};

type Timed = Unit & { GetSecondsPerAttack?(): number };

/**
 * Where the hero's attack on the creep starts without a move: the engine's `attackReach` (attack range and both hulls), the one
 * fact the engine's walk and last-hit verb, this read and the row all use (ARCHITECTURE.md rule 1).
 */
export function Reach(bot: Unit, creep: Unit): number {
    return Tasks.Verbs()!.attackReach(bot as unknown as Lib.TaskUnit, creep as unknown as Lib.TaskCreep);
}

/** The unit's attack cycle (s, `GetSecondsPerAttack`); 1 where the handle has none. */
export function AttackCycle(u: Unit): number {
    return (u as Timed).GetSecondsPerAttack?.() ?? 1;
}

/**
 * laneTargets' `within` for the hero: the engine's default 1 s, or one own attack cycle when longer, so a creep is offered by
 * the time the creep row may go on it (it goes once due within the walk plus one cycle, creep_row.ts `Due`). For a hero the row acts
 * on, also the row's own lead when that is longer (`SetRow`'s `lead`, creep_row.ts `EarlyLead`); a hero it is off for asks as before.
 */
export function Within(bot: Unit): number {
    return math.max(1, AttackCycle(bot), rowLead === undefined ? 0 : rowLead(bot));
}

/**
 * The read's parts, timed as `CO:<part>` rows when the perf probe is on (kind `step`; PerfStep returns the function itself with the
 * probe off). Made on first use: the probe's clock is chosen at the first PerfStep.
 */
interface Parts {
    targets: (this: void, bot: Lib.TaskUnit) => Lib.Verbs.LaneTarget[];
    lists: (this: void, bot: Unit) => { listed: LuaTable<Unit, boolean>; theirs: Unit[] };
    snapshot: (this: void, bot: Unit, f: Frame, t: Lib.Verbs.LaneTarget, slack: number, others: Offer.Other[]) => Snap;
    race: (this: void, bot: Unit, creep: Unit) => [string, number | undefined];
}
let parts: Parts | undefined;

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
    /** Enemy heroes whose hit is at least ours that can be in their own range of the creep before it comes due, and the soonest (s). */
    erc: number;
    ert?: number;
    /** The creep is inside one of our towers' attack range. */
    otw: boolean;
    /** `GetHeightLevel` of the hero, the stand spot and the creep (undefined when the API gives none), the hero's attack range, and each listed enemy's `pid:level` in `en`'s order. */
    hh?: number;
    sh?: number;
    ch?: number;
    ra: number;
    enh?: string;
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
    /** Set by the row (Candidate.note): it started an attempt on this creep, the seconds from `first` to that start, and the walk then. */
    go?: boolean;
    gat?: number;
    gw?: number;
    /** The attempt id the row allocated at the go (Telemetry.NextAid), on the go line. */
    aid?: number;
    /**
     * The row's reason for not going: the first it gave once the creep was about to come due (`early` is replaced by the next
     * reason; any other stays, so a creep refused for the race and later unreachable reads `race`, not `late`). Undefined
     * while the row has said nothing (the line then reads `off`).
     */
    why?: string;
    /** The row's latest reason for not going, as given at its last read of the creep (`early` and `kind` included); the line's `lw`. */
    last?: string;
}

/**
 * One creep offered to the hero at this read, handed to the row. `creep` is listed this read, so its handle may be called
 * now. `facts` reads the offer's answers afresh (once a read); `note` records the row's decision for the line.
 */
export interface Candidate {
    t: Lib.Verbs.LaneTarget;
    creep: Unit;
    cid: number;
    ck: string;
    arrive: Offer.Arrival;
    facts(this: void): Snap;
    note(this: void, go: boolean, why?: string, aid?: number): void;
}

export type RowHook = (this: void, bot: Unit, cands: Candidate[]) => void;
let rowHook: RowHook | undefined;
/** Whether the row wants the read for this hero with telemetry off (the read itself writes lines only with telemetry on). */
let rowWants: ((this: void, bot: Unit) => boolean) | undefined;

/** The seconds the row wants a creep offered ahead of (0: none), asked of a hero whose row is on; heroes it is off for keep `Within`'s own. */
let rowLead: ((this: void, bot: Unit) => number) | undefined;

/** index.ts: the row's decision, asked at every read with the hero's candidates, and how far ahead it wants creeps offered. */
export function SetRow(hook: RowHook | undefined, wants?: (this: void, bot: Unit) => boolean, lead?: (this: void, bot: Unit) => number): void {
    rowHook = hook;
    rowWants = wants;
    rowLead = lead;
}

/** pid -> the read interval the hero last read in. */
const readAt: Record<number, number | undefined> = {};

/** pid -> creep id -> its opportunity. */
const opps: Record<number, Record<number, Opp | undefined> | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(opps)) opps[k as number] = undefined;
    for (const [k] of pairs(readAt)) readAt[k as number] = undefined;
    parts = undefined;
}

/** Whether this hero's read is due: once per interval, the heroes' intervals offset by player id. */
function due(pid: number, now: number): boolean {
    // The epsilon keeps a clock a hair under a boundary (100.2 / 0.2) in the interval it belongs to.
    const n = math.floor((now + (pid % 2) * (SETTINGS.Every / 2)) / SETTINGS.Every + 1e-6);
    if (readAt[pid] === n) return false;
    readAt[pid] = n;
    return true;
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
        ["aid", o.go === true ? o.aid : undefined],
        ["go", o.go === true ? 1 : 0],
        ["want", want ? 1 : 0],
        ["why", o.go === true ? undefined : o.why ?? "off"],
        ["lw", o.go === true ? undefined : o.last],
        ["src", o.go === true || o.why !== undefined ? "own" : "shadow"],
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
        ["erc", s.erc],
        ["ert", s.ert !== undefined ? r2(s.ert) : undefined],
        ["otw", s.otw ? 1 : 0],
        ["gat", o.gat !== undefined ? r1(o.gat) : undefined],
        ["gw", o.gw !== undefined ? r2(o.gw) : undefined],
        ["hh", s.hh],
        ["sh", s.sh],
        ["ch", s.ch],
        ["ra", math.floor(s.ra)],
        ["enh", s.enh],
    ]);
}

function hasOpen(pid: number): boolean {
    const m = opps[pid];
    if (m === undefined) return false;
    for (const [] of pairs(m)) return true;
    return false;
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
    enemyCreeps: Unit[];
    towers?: Offer.PathTower[];
    /** Our towers, `reach` their attack range plus the tower's hull (the creep's hull is added per creep). */
    ownTowers?: Offer.PathTower[];
    creeps?: Offer.PathCreep[];
    enemies?: Offer.PathEnemy[];
    /** `pid:level` of each entry of `enemies`, in its order. */
    enemyHeights?: string[];
}

/** The terrain height level at a place; undefined when the API is absent or gives no number. */
function heightAt(x: number, y: number): number | undefined {
    const [ok, h] = pcall(GetHeightLevel, Vector(x, y, 0));
    return ok && type(h) === "number" ? (h as number) : undefined;
}

function towersOf(bot: Unit, f: Frame): Offer.PathTower[] {
    if (f.towers !== undefined) return f.towers;
    const out: Offer.PathTower[] = [];
    for (const t of bot.GetNearbyTowers(SETTINGS.TowerRadius, true)) {
        const at = t.GetLocation();
        if (at === null || at === undefined) continue;
        out.push({ x: at.x, y: at.y, reach: t.GetAttackRange() + t.GetBoundingRadius() + f.hull });
    }
    f.towers = out;
    return out;
}

function ownTowersOf(bot: Unit, f: Frame): Offer.PathTower[] {
    if (f.ownTowers !== undefined) return f.ownTowers;
    const out: Offer.PathTower[] = [];
    for (const t of bot.GetNearbyTowers(SETTINGS.TowerRadius, false)) {
        const at = t.GetLocation();
        if (at === null || at === undefined) continue;
        out.push({ x: at.x, y: at.y, reach: t.GetAttackRange() + t.GetBoundingRadius() });
    }
    f.ownTowers = out;
    return out;
}

function creepsOf(f: Frame): Offer.PathCreep[] {
    if (f.creeps !== undefined) return f.creeps;
    const out: Offer.PathCreep[] = [];
    for (const c of f.enemyCreeps) {
        // The API has returned nil here in games; likely a fogged creep, still listed and alive but with no location (see `gone` in the engine's lasthit.ts).
        const at = c.GetLocation();
        if (at === null || at === undefined) continue;
        const spa = (c as Timed).GetSecondsPerAttack?.() ?? 1;
        out.push({ x: at.x, y: at.y, reach: c.GetAcquisitionRange() + c.GetBoundingRadius() + f.hull, dps: c.GetAttackDamage() / math.max(spa, 0.1) });
    }
    f.creeps = out;
    return out;
}

function enemiesOf(f: Frame): Offer.PathEnemy[] {
    if (f.enemies !== undefined) return f.enemies;
    const out: Offer.PathEnemy[] = [];
    const hs: string[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!e.IsAlive() || e.IsIllusion() || !e.CanBeSeen()) continue;
        const at = e.GetLocation();
        if (at === null || at === undefined) continue;
        out.push({ x: at.x, y: at.y, pid: e.GetPlayerID(), range: e.GetAttackRange(), hull: e.GetBoundingRadius(), dmg: e.GetAttackDamage(), spa: (e as Timed).GetSecondsPerAttack?.() ?? 1, speed: e.GetCurrentMovementSpeed() });
        hs.push(`${e.GetPlayerID()}:${heightAt(at.x, at.y) ?? "-"}`);
    }
    f.enemies = out;
    f.enemyHeights = hs;
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
    const spot = Offer.StandSpot(f.hero, at, Reach(bot, creep));
    const path = Offer.PathCost({ from: f.hero, spot, speed: f.speed, hull: f.hull, creeps: creepsOf(f), towers: towersOf(bot, f), enemies: enemiesOf(f) });
    let ed = 0;
    let ein = 0;
    let erc = 0;
    let ert: number | undefined;
    const md = bot.GetAttackDamage();
    const hull = creep.GetBoundingRadius();
    for (const e of enemiesOf(f)) {
        const gap = dist(e, at) - (e.range + e.hull + hull);
        // The race: an enemy hero whose hit is at least ours and who can stand in its own range of the creep before it comes
        // due for us (the enemy walking straight at its speed).
        const reach = math.max(0, gap) / math.max(100, e.speed ?? 300);
        if (e.dmg >= md && reach <= t.due) {
            erc++;
            if (ert === undefined || reach < ert) ert = reach;
        }
        if (gap > 0) continue;
        ein++;
        if (e.dmg > ed) ed = e.dmg;
    }
    const [kb, kt] = parts!.race(bot, creep);
    let otw = false;
    for (const tw of ownTowersOf(bot, f)) {
        if (dist(tw, at) <= tw.reach + hull) {
            otw = true;
            break;
        }
    }
    const hs = f.enemyHeights ?? [];
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
        md,
        ed,
        ein,
        erc,
        ert,
        otw,
        hh: heightAt(f.hero.x, f.hero.y),
        sh: heightAt(spot.x, spot.y),
        ch: heightAt(at.x, at.y),
        ra: bot.GetAttackRange(),
        enh: hs.length > 0 ? hs.join(";") : undefined,
    };
}

function partsOf(): Parts {
    if (parts !== undefined) return parts;
    parts = {
        targets: Telemetry.PerfStep("CO:targets", (bot: Lib.TaskUnit) => Tasks.Verbs()!.laneTargets(bot, { radius: LaneHits.READER_RADIUS, within: Within(bot as unknown as Unit) })),
        lists: Telemetry.PerfStep("CO:lists", (bot: Unit) => {
            const listed = new LuaTable<Unit, boolean>();
            const mine = bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false);
            const theirs = bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, true);
            for (const c of mine) listed.set(c, true);
            for (const c of theirs) listed.set(c, true);
            return { listed, theirs };
        }),
        snapshot: Telemetry.PerfStep("CO:snapshot", snapshot),
        race: Telemetry.PerfStep("CO:race", race),
    };
    return parts;
}

/**
 * One call per hero (the tick's ten a second): opens, updates and closes the hero's opportunities. Reads and logs; nothing is
 * ordered.
 */
export function Shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled() && (rowWants === undefined || !rowWants(bot))) return;
    const pid = bot.GetPlayerID();
    if (!due(pid, DotaTime()) || !MayOffer(bot)) return;
    if (!bot.IsAlive() || Drill.Held(bot) || !LaneConfig.InLaningPhase()) {
        closeAll(bot, pid);
        if (rowHook !== undefined) rowHook(bot, []);
        return;
    }
    if (Tasks.Verbs() === undefined) return;
    const P = partsOf();
    const now = DotaTime();
    const targets = P.targets(bot as unknown as Lib.TaskUnit);
    // Nothing offered and nothing open: no creep to list or close.
    if (targets.length === 0 && !hasOpen(pid)) return;
    const { listed, theirs } = P.lists(bot);

    let m = opps[pid];
    if (m !== undefined) {
        for (const [cid, o] of pairs(m)) {
            if (listed.get(o.creep) === true) continue;
            line(bot, o);
            m[cid] = undefined;
        }
    }
    if (targets.length === 0) {
        if (rowHook !== undefined) rowHook(bot, []);
        return;
    }
    if (m === undefined) {
        m = {};
        opps[pid] = m;
    }

    const loc = bot.GetLocation();
    const f: Frame = { hero: { x: loc.x, y: loc.y }, speed: math.max(100, bot.GetCurrentMovementSpeed()), hull: bot.GetBoundingRadius(), enemyCreeps: theirs };
    const atkTarget = bot.GetAttackTarget();
    const slot = math.floor(now * 10) / 10;
    const cands: Candidate[] = [];

    for (const t of targets) {
        const creep = t.creep as unknown as Unit;
        // Defence only: the engine's laneTargets already leaves out a creep with no location.
        const here = creep.GetLocation();
        if (here === null || here === undefined) continue;
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
                snap: P.snapshot(bot, f, t, a.slack, others),
                atk: false,
            };
            m[cid] = o;
        } else if (o.okFrom === undefined && (a.ok || a.slack > o.snap.slk + SETTINGS.SlackStep)) {
            o.snap = P.snapshot(bot, f, t, a.slack, others);
        }
        if (a.ok) {
            if (o.okFrom === undefined) o.okFrom = now;
            o.okTo = now;
        }
        if (atkTarget !== null && atkTarget !== undefined && atkTarget === creep) o.atk = true;
        if (rowHook !== undefined) cands.push(candidate(bot, f, targets, t, creep, cid, o, a, now));
    }
    if (rowHook !== undefined) rowHook(bot, cands);
}

function candidate(bot: Unit, f: Frame, targets: Lib.Verbs.LaneTarget[], t: Lib.Verbs.LaneTarget, creep: Unit, cid: number, o: Opp, a: Offer.Arrival, now: number): Candidate {
    let fresh: Snap | undefined;
    return {
        t,
        creep,
        cid,
        ck: o.ck,
        arrive: a,
        facts: () => {
            if (fresh === undefined) {
                const others: Offer.Other[] = [];
                for (const x of targets) if (x !== t && x.walk <= 0) others.push({ due: x.due, ranged: x.ranged });
                fresh = partsOf().snapshot(bot, f, t, a.slack, others);
            }
            return fresh;
        },
        note: (go: boolean, why?: string, aid?: number) => {
            if (o.go === true) return;
            if (go) {
                o.go = true;
                o.aid = aid;
                o.gat = now - o.first;
                o.gw = t.walk;
                o.why = undefined;
            } else {
                if (o.why === undefined || o.why === "early") o.why = why;
                o.last = why;
            }
        },
    };
}
