/**
 * Lane hits (slice oha-lane-swings; master families proposal s6, user 24/11/2026): per lane and team, each own lane creep and
 * each visible enemy lane creep with its HP forecast and every hit coming at it, heroes' named by player id: when it lands,
 * when it commits (its attack point; 0 in flight), its damage. One team-owned table keyed by lane, so a team level can sit on
 * it later; absolute facts (lane, creep, player id), never "my core". Facts only: no choice is made here.
 *
 * Read from the engine's `hpForecast` (attacker index, wind-up timing verified in game by swingwc1-2: within one frame of the
 * fire on about 98% of our heroes' wind-ups; enemy heroes not measured). A wind-up is not a commitment: a seen wind-up of a
 * melee core fired 55% of the time, 87% once past half of it (swingprobe2-4); the consumer weighs that, from `commit`.
 *
 * Each creep's forecast is read from the nearest alive hero of the team within READER_RADIUS (the engine's attacker index
 * is that hero's surroundings); a creep with none is left out (no hero of ours can act on it). Built on demand, once per
 * team, lane and frame. Not wired into any decision here: its consumer is the support's deny (slice oha-deny-free).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { Lane, Unit, UnitType } from "bots/ts_libs/dota";
import * as LaneRead from "bots/FunLib/humaniser/lane_read";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";

/** The engine's attacker-index radius (engine lasthit QUERY_RADIUS): a reader farther from the creep misses its attackers. */
export const READER_RADIUS = 1600;
/** Seconds of forecast: past the longest wind-up plus flight (about 1.2 s) with room for a creep's repeats. `judgement`. */
export const HORIZON = 3;

/** One hero's hit at a creep. */
export interface HeroHit {
    pid: number;
    /** 1 a hero of the reading team, 0 the other team's. */
    ours: boolean;
    /** Seconds from now until it lands, and until it commits (0: already fired, in flight or landing). */
    t: number;
    commit: number;
    /** After the creep's armour. */
    damage: number;
}

export interface CreepHits {
    creep: Unit;
    /** The reading team's own creep (a deny target), else an enemy creep (a last-hit target). */
    own: boolean;
    hp: number;
    /** The player id of the hero the forecast was read from. */
    reader: number;
    forecast: Lib.Verbs.HpForecast;
    /** Every hero's hit at the creep within HORIZON, both teams, sorted by `t`. */
    heroes: HeroHit[];
}

interface Cached {
    at: number;
    rows: CreepHits[];
}
const cache: Record<string, Cached | undefined> = {};

export function Reset(): void {
    for (const [k] of pairs(cache)) cache[k as string] = undefined;
}

function dist(a: Unit, b: Unit): number {
    const p = a.GetLocation();
    const q = b.GetLocation();
    const dx = p.x - q.x;
    const dy = p.y - q.y;
    return math.sqrt(dx * dx + dy * dy);
}

/** The team's alive heroes (GetTeamMember answers for the calling script's team). */
function ownHeroes(): Unit[] {
    const out: Unit[] = [];
    for (let i = 1; i <= 5; i++) {
        const h = GetTeamMember(i);
        if (h !== undefined && h !== null && !h.IsNull() && h.IsAlive() && !h.IsIllusion()) out.push(h);
    }
    return out;
}

function nearestReader(heroes: Unit[], creep: Unit): Unit | undefined {
    let best: Unit | undefined;
    let bestD = READER_RADIUS;
    for (const h of heroes) {
        const d = dist(h, creep);
        if (d <= bestD) {
            bestD = d;
            best = h;
        }
    }
    return best;
}

function heroHits(f: Lib.Verbs.HpForecast, team: number): HeroHit[] {
    const out: HeroHit[] = [];
    for (const h of f.hits) {
        if (h.by !== "hero" && h.by !== "self") continue;
        const a = h.attacker as unknown as Unit;
        out.push({ pid: a.GetPlayerID(), ours: a.GetTeam() === team, t: h.t, commit: h.commit, damage: h.damage });
    }
    return out;
}

function build(team: number, lane: Lane, verbs: NonNullable<ReturnType<typeof Tasks.Verbs>>): CreepHits[] {
    const heroes = ownHeroes();
    const rows: CreepHits[] = [];
    if (heroes.length === 0) return rows;
    const sides: [boolean, LaneRead.Placed[]][] = [
        [true, LaneRead.ByLane(GetUnitList(UnitType.AlliedCreeps), false)[lane]],
        [false, LaneRead.ByLane(GetUnitList(UnitType.EnemyCreeps), true)[lane]],
    ];
    for (const [own, placed] of sides) {
        for (const p of placed) {
            const reader = nearestReader(heroes, p.unit);
            if (reader === undefined) continue;
            const f = verbs.hpForecast(reader as unknown as Lib.TaskUnit, p.unit as unknown as Lib.TaskCreep, HORIZON);
            rows.push({ creep: p.unit, own, hp: f.hp, reader: reader.GetPlayerID(), forecast: f, heroes: heroHits(f, team) });
        }
    }
    return rows;
}

/**
 * The lane's creeps with the hits coming at them, for `team` (the calling script's team), read once a frame; empty while
 * the engine bundle is not loaded.
 */
export function Read(team: number, lane: Lane): CreepHits[] {
    const key = `${team}:${lane}`;
    const now = DotaTime();
    const c = cache[key];
    if (c !== undefined && c.at === now) return c.rows;
    const verbs = Tasks.Verbs();
    const rows = verbs === undefined ? [] : build(team, lane, verbs);
    cache[key] = { at: now, rows };
    return rows;
}

/** The read's row for one creep, if the lane lists it this frame. */
export function Of(team: number, lane: Lane, creep: Unit): CreepHits | undefined {
    for (const r of Read(team, lane)) if (r.creep === creep) return r;
    return undefined;
}

/**
 * The hit the forecast says kills the creep (the first at which its HP, every hit to then counted and the unknown-phase hits
 * spread as lastHit's belief does, is 0 or less), else undefined.
 */
export function KillingHit(r: CreepHits): Lib.Verbs.ForecastHit | undefined {
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return undefined;
    for (const h of r.forecast.hits) if (verbs.forecastHp(r.forecast, h.t) <= 0) return h;
    return undefined;
}
