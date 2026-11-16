/**
 * Lane push reading (slice support-lane, `docs/proposals/2026-11-03-lane-state-decisions.md` s6), CANDIDATE(lane_push): which
 * way the clash point of one lane moves over the next 30 s from one team's side, OUT (towards their tower), IN (towards ours)
 * or HOLD. Within `Near` of a T1 the tower rule decides (EC-079: a wave at a tower bounces off it); elsewhere one mean-damage
 * run of the creep-and-tower fight model, a port of `docs/proposals/lane-forecast/lane_sim.js` (kept equal to it by
 * test_lane_push.lua), started from the team's view: its own creeps, visible enemy creeps and enemy waves placed by the
 * spawn schedule where none is seen (push.js `initView`). Offline at 30 s: right 65% of the time, the best simple rule 43%.
 */
import * as GameRules from "bots/FunLib/humaniser/game_rules";
import { Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";
import { LANE_PATHS, LanePath } from "bots/FunLib/humaniser/lane_push_data";

declare function RealTime(this: void): number;

export type State = "OUT" | "HOLD" | "IN";

// All `judgement` except Dt, SeenR and OurVision, which are the offline check's (push.js) so the scored numbers hold.
export const SETTINGS = {
    Horizon: 30,
    Band: 300,
    /** Tower rule radius along the lane path. */
    Near: 900,
    Dt: 0.05,
    /** A scheduled enemy wave counts as seen when a visible enemy creep is this close to where it should be. */
    SeenR: 500,
    /** ...or when it would be this close to (or behind) our lead creep, which would see it. */
    OurVision: 300,
    /** Lane creeps further than this from the lane path are not in the lane (lane_read's LaneAssign is the same idea). */
    Assign: 1100,
    /** The lane's target meeting point, this far along the lane from our T1 (side lanes: out of its range; mid: our
     *  high-ground edge; slice lane-aggro, `judgement`). Lane aggro's feed, the wave hold and the pull trigger read it. */
    TargetSide: 900,
    TargetMid: 1300,
    /** A wave's creeps are the lane creeps within this of where the schedule puts it (melee at the spot, ranged 150 behind;
     *  waves walk 9,750 apart; `judgement`). */
    WaveWindow: 500,
};

const R = Team.Radiant;
const D = Team.Dire;
/** Fallback only: the lane creeps' speed is read live (WorldFacts.Latest). */
const SPEED_FALLBACK = 325;
const speed = (): number => WorldFacts.Latest("lane_creep_speed", SPEED_FALLBACK);
const REACH = 50;
const FLAG_REGEN = 3;
const FLAG_RADIUS = 700;
const UPGRADE_EVERY = 450;

interface Kind {
    hp: number;
    regen: number;
    armor: number;
    dmg: number;
    bat: number;
    point: number;
    range: number;
    acq: number;
    proj: number;
    heavy: boolean;
    building?: boolean;
    aura?: boolean;
}

/** Game files (npc_units.txt, npc_abilities.txt), as lane_sim.js; its header has the sources. */
export const KINDS: Record<string, Kind> = {
    melee: { hp: 550, regen: 0.5, armor: 2, dmg: 21, bat: 1.0, point: 0.467, range: 100, acq: 500, proj: 0, heavy: false },
    flag: { hp: 550, regen: 0.5, armor: 2, dmg: 21, bat: 1.0, point: 0.467, range: 100, acq: 500, proj: 0, heavy: false, aura: true },
    ranged: { hp: 300, regen: 2, armor: 0, dmg: 23.5, bat: 1.0, point: 0.5, range: 500, acq: 600, proj: 900, heavy: false },
    siege: { hp: 935, regen: 0, armor: 0, dmg: 40.5, bat: 3.0, point: 0.7, range: 690, acq: 800, proj: 1100, heavy: true },
    tower1: { hp: 1800, regen: 0, armor: 12, dmg: 90, bat: 0.9, point: 0.6, range: 700, acq: 700, proj: 750, heavy: true, building: true },
};

interface SimUnit extends Kind {
    team: number;
    kind: string;
    s: number;
    maxhp: number;
    target?: SimUnit;
    swingAt?: number;
    readyAt: number;
    alive: boolean;
    /** Target type, fixed by the kind: building 0, unit 1, siege 2 (rank's). */
    ty: number;
}

/** One creep at the start of a run: kind (melee, flag, ranged, siege), position along the lane path, HP. */
export interface StartCreep {
    team: number;
    kind: string;
    s: number;
    hp: number;
    maxhp?: number;
}

/** Each team's lead creep position at one second; a team with no creep left has none. */
export interface Sample {
    t: number;
    front: Record<number, number | undefined>;
    /** Each team's lane creeps the run has killed so far (from its start, towers not counted). */
    dead: Record<number, number>;
}

function armorMult(a: number): number {
    return 1 - (0.06 * a) / (1 + 0.06 * math.abs(a));
}

function damage(a: SimUnit, b: SimUnit): number {
    let d = a.dmg;
    if (a.kind === "ranged") d *= b.heavy ? 0.35 : 1.5;
    else if (a.heavy && b.heavy) d *= 2.5;
    else if (!a.heavy && b.heavy) d *= 0.7;
    return d * armorMult(b.armor);
}

function rank(a: SimUnit, b: SimUnit): number {
    const type = b.building === true ? 0 : b.kind === "siege" ? 2 : 1;
    // siege: building 0, unit 1, siege 2; others: unit 0, siege 1, building 2
    if (a.kind === "siege") return type;
    return type === 1 ? 0 : type === 2 ? 1 : 2;
}

function makeUnit(team: number, kind: string, s: number, t: number): SimUnit {
    const k = KINDS[kind];
    return { ...k, team, kind, s, maxhp: k.hp, readyAt: t, alive: true, ty: k.building === true ? 0 : kind === "siege" ? 2 : 1 };
}

function dirOf(team: number): number {
    return team === R ? 1 : -1;
}

/** The wave `team` spawns at second `t` (a multiple of 30), at `spawnS`: 3 melee (one a flagbearer on the minute from
 *  2:00), 1 ranged 150 behind, a siege every 5:00; +12 HP and +1 (ranged +2) damage every 7:30. */
export function WaveAt(team: number, t: number, spawnS: number): SimUnit[] {
    const up = math.floor(t / UPGRADE_EVERY);
    const kinds = ["melee", "melee", "melee", "ranged"];
    if (t >= 120 && t % 60 === 0) kinds[2] = "flag";
    if (t >= 300 && t % 300 === 0) kinds.push("siege");
    return kinds.map((kind) => {
        const behind = kind === "ranged" ? -150 * dirOf(team) : 0;
        const u = makeUnit(team, kind, spawnS + behind, t);
        if (kind !== "siege") {
            u.hp += 12 * up;
            u.maxhp += 12 * up;
            u.dmg += (kind === "ranged" ? 2 : 1) * up;
        }
        return u;
    });
}

function round3(x: number): number {
    return math.floor(x * 1000 + 0.5) / 1000;
}

/**
 * One lane from `from` to `until` (s), mean damage. `init` creeps start at `from` (given, even empty, no wave spawns at
 * `from` itself);
 * `towerHp[team]` starts that team's T1 at a value, undefined leaves it at full, false leaves it out (down).
 * `skip` leaves out one team's wave spawning at second `skip.t` (a wave pulled before it reaches the lane).
 * Returns a sample of both leads every second from `from`. `steps`, when given, receives each sample's step time: a run to
 * an earlier `until` from the same start is exactly the samples whose step is at or before it (Upto).
 */
export function Run(
    lane: LanePath,
    from: number,
    until: number,
    init: StartCreep[] | undefined,
    towerHp: Record<number, number | false | undefined>,
    skip?: { team: number; t: number },
    steps?: number[],
): Sample[] {
    const dt = SETTINGS.Dt;
    const units: SimUnit[] = [];
    for (const tw of lane.towers) {
        const hp = towerHp[tw.team];
        if (hp === false) continue;
        const u = makeUnit(tw.team, "tower1", tw.s, from);
        if (hp !== undefined) u.hp = hp;
        units.push(u);
    }
    for (const c of init ?? []) {
        const u = makeUnit(c.team, c.kind, c.s, from);
        if (c.maxhp !== undefined) u.maxhp = c.maxhp;
        u.hp = c.hp;
        units.push(u);
    }
    const projectiles: { at: number; dst: SimUnit; dmg: number }[] = [];
    const samples: Sample[] = [];
    const dead: Record<number, number> = { [R]: 0, [D]: 0 };
    const hit = (v: SimUnit, dmg: number) => {
        v.hp -= dmg;
        if (v.hp <= 0 && v.alive) {
            v.alive = false;
            if (v.building !== true) dead[v.team] += 1;
        }
    };
    const inReach = (u: SimUnit, v: SimUnit, r: number) => math.abs(v.s - u.s) <= r + REACH;
    // The run's inner loop (every unit against every live enemy, 20 times a second of forecast) is written out with numeric
    // loops over arrays kept across steps; nothing dies between the step's live lists being built and its targets being
    // picked, so the pick reads no `alive`. Each team's list keeps the units' order, so ties pick the same unit as one scan
    // of every live unit. test_lane_push holds the results to the offline model and to the plain loop's samples.
    const live: SimUnit[] = [];
    let nLive = 0;
    /** Live units by team (index 0 Radiant, 1 Dire), each in `units` order. */
    const byTeam: SimUnit[][] = [[], []];
    const nBy = [0, 0];
    const flags: SimUnit[] = [];
    let nFlags = 0;
    const best = (u: SimUnit, r: number): SimUnit | undefined => {
        let pick: SimUnit | undefined;
        let key = math.huge;
        const us = u.s;
        const lim = r + REACH;
        const siege = u.kind === "siege";
        const e = u.team === R ? 1 : 0;
        const list = byTeam[e];
        const n = nBy[e];
        for (let i = 0; i < n; i++) {
            const v = list[i];
            let d = v.s - us;
            if (d < 0) d = -d;
            if (d <= lim) {
                const type = v.ty;
                const k = (siege ? type : type === 1 ? 0 : type === 2 ? 1 : 2) * 1e6 + d;
                if (k < key) {
                    key = k;
                    pick = v;
                }
            }
        }
        return pick;
    };
    let nextSample = from;
    // Read once, at the first creep that walks: a run is 600 steps of every creep, and the live speed does not change inside
    // one call. A run in which nothing walks still reads nothing (a read with no live value counts a fallback).
    let walk: number | undefined;
    for (let t = from; t <= until + 1e-9; t = round3(t + dt)) {
        if (math.abs(t % GameRules.WAVE_EVERY) < dt / 2 && !(init !== undefined && t < from + dt / 2)) {
            const ts = math.floor(t + 0.5);
            if (skip?.team !== R || skip.t !== ts) for (const u of WaveAt(R, ts, lane.spawnR)) units.push(u);
            if (skip?.team !== D || skip.t !== ts) for (const u of WaveAt(D, ts, lane.spawnD)) units.push(u);
        }
        nLive = 0;
        nFlags = 0;
        nBy[0] = 0;
        nBy[1] = 0;
        for (let i = 0; i < units.length; i++) {
            const u = units[i];
            if (u.alive) {
                live[nLive++] = u;
                const k = u.team === R ? 0 : 1;
                byTeam[k][nBy[k]++] = u;
                if (u.aura === true) flags[nFlags++] = u;
            }
        }
        for (let i = 0; i < nLive; i++) {
            const u = live[i];
            let r = u.regen;
            if (u.building !== true) {
                for (let j = 0; j < nFlags; j++) {
                    const f = flags[j];
                    if (f.team === u.team && math.abs(f.s - u.s) <= FLAG_RADIUS) {
                        r += FLAG_REGEN;
                        break;
                    }
                }
            }
            const hp = u.hp + r * dt;
            u.hp = hp < u.maxhp ? hp : u.maxhp;
        }
        for (let i = 0; i < nLive; i++) {
            const u = live[i];
            if (u.target !== undefined && !u.target.alive) {
                u.target = undefined;
                u.swingAt = undefined;
            }
            if (u.swingAt === undefined) {
                if (u.target !== undefined) {
                    const b = best(u, u.range);
                    if (b !== undefined && (rank(u, b) < rank(u, u.target) || !inReach(u, u.target, u.range))) u.target = b;
                    else if (!inReach(u, u.target, u.acq) && b === undefined) u.target = undefined;
                }
                if (u.target === undefined) u.target = best(u, u.acq);
            }
        }
        for (let i = 0; i < nLive; i++) {
            const u = live[i];
            const v = u.target;
            let gap = v !== undefined ? v.s - u.s : 0;
            if (gap < 0) gap = -gap;
            if (v !== undefined && gap <= u.range + REACH) {
                if (u.swingAt === undefined && t >= u.readyAt) {
                    u.swingAt = t + u.point;
                    u.readyAt = t + u.bat;
                }
                if (u.swingAt !== undefined && t >= u.swingAt) {
                    u.swingAt = undefined;
                    const dmg = damage(u, v);
                    if (u.proj > 0) projectiles.push({ at: t + gap / u.proj, dst: v, dmg });
                    else hit(v, dmg);
                }
            } else if (u.building !== true) {
                u.swingAt = undefined;
                const goal = v !== undefined ? (v.s > u.s ? 1 : v.s < u.s ? -1 : 0) : dirOf(u.team);
                if (walk === undefined) walk = speed();
                u.s += goal * walk * dt;
            }
        }
        // Landed projectiles hit last-fired first (the order HP is subtracted in); the rest keep their order.
        const np = projectiles.length;
        let landed = false;
        for (let i = np - 1; i >= 0; i--) {
            const p = projectiles[i];
            if (t >= p.at) {
                landed = true;
                if (p.dst.alive) hit(p.dst, p.dmg);
            }
        }
        if (landed) {
            let w = 0;
            for (let i = 0; i < np; i++) {
                const p = projectiles[i];
                if (!(t >= p.at)) projectiles[w++] = p;
            }
            for (let i = np - 1; i >= w; i--) projectiles.pop();
        }
        if (t >= nextSample) {
            const front: Record<number, number | undefined> = {};
            for (const u of units) {
                if (!u.alive || u.building === true) continue;
                const f = front[u.team];
                front[u.team] = f === undefined ? u.s : u.team === R ? math.max(f, u.s) : math.min(f, u.s);
            }
            samples.push({ t: nextSample, front, dead: { [R]: dead[R], [D]: dead[D] } });
            if (steps !== undefined) steps.push(t);
            nextSample++;
        }
    }
    return samples;
}

/** The samples a run from the same start to `until` returns, out of a longer run's samples and their `steps`. */
export function Upto(samples: Sample[], steps: number[], until: number): Sample[] {
    const out: Sample[] = [];
    for (let i = 0; i < samples.length; i++) {
        if (steps[i] > until + 1e-9) break;
        out.push(samples[i]);
    }
    return out;
}

/** Mean of the two leads' midpoint over t-2..t+2 (each second's first sample at or after it); undefined under 3 seconds. */
export function ClashAt(samples: Sample[], t: number): number | undefined {
    let sum = 0;
    let n = 0;
    for (let u = t - 2; u <= t + 2; u++) {
        let smp: Sample | undefined;
        for (const x of samples) {
            if (x.t >= u) {
                smp = x;
                break;
            }
        }
        const a = smp?.front[R];
        const b = smp?.front[D];
        if (a !== undefined && b !== undefined) {
            sum += (a + b) / 2;
            n++;
        }
    }
    return n >= 3 ? sum / n : undefined;
}

export function StateOf(move: number): State {
    return move > SETTINGS.Band ? "OUT" : move < -SETTINGS.Band ? "IN" : "HOLD";
}

/** EC-079: a clash within Near of a T1 bounces away from it; undefined elsewhere. */
export function TowerRule(lane: LanePath, clash: number, team: number): State | undefined {
    for (const tw of lane.towers) if (math.abs(clash - tw.s) <= SETTINGS.Near) return tw.team === team ? "OUT" : "IN";
    return undefined;
}

function maxHp(kind: string, t0: number): number {
    return KINDS[kind].hp + (kind === "siege" ? 0 : 12 * math.floor(t0 / UPGRADE_EVERY));
}

/** `team`'s lead lane creep: the path distance of its creep furthest towards the enemy; undefined with none. */
export function LeadOf(own: StartCreep[], team: number): number | undefined {
    let lead: number | undefined;
    for (const c of own) if (lead === undefined || dirOf(team) * (c.s - lead) > 0) lead = c.s;
    return lead;
}

/** Where `team`'s waves spawn on the path, and the sign of their travel along it. */
export function SpawnOf(lane: LanePath, team: number): LuaMultiReturn<[number, number]> {
    return $multi(team === R ? lane.spawnR : lane.spawnD, dirOf(team));
}

/**
 * The start state from team `v`'s view at second `t0`: own and visible enemy creeps (HP clipped to the kind's maximum), plus
 * each enemy wave spawned in the last 90 s that nothing would see, placed by the schedule at full HP (push.js `initView`).
 */
export function ViewStart(lane: LanePath, v: number, t0: number, own: StartCreep[], enemy: StartCreep[]): StartCreep[] {
    const e = v === R ? D : R;
    const de = dirOf(e);
    const init: StartCreep[] = [];
    const lead = LeadOf(own, v);
    for (const c of own) init.push({ team: v, kind: c.kind, s: c.s, hp: math.min(c.hp, maxHp(c.kind, t0)), maxhp: maxHp(c.kind, t0) });
    for (const c of enemy) init.push({ team: e, kind: c.kind, s: c.s, hp: math.min(c.hp, maxHp(c.kind, t0)), maxhp: maxHp(c.kind, t0) });
    const [spawnE] = SpawnOf(lane, e);
    for (let ts = math.floor(t0 / GameRules.WAVE_EVERY) * GameRules.WAVE_EVERY; ts >= t0 - 3 * GameRules.WAVE_EVERY && ts >= 0; ts -= GameRules.WAVE_EVERY) {
        const pos = spawnE + de * speed() * (t0 - ts);
        let seen = false;
        for (const c of enemy) if (math.abs(c.s - pos) <= SETTINGS.SeenR) seen = true;
        if (seen) continue;
        if (lead !== undefined && de * (pos - lead) >= -SETTINGS.OurVision) continue;
        for (const u of WaveAt(e, ts, spawnE)) init.push({ team: e, kind: u.kind, s: u.s - spawnE + pos, hp: u.hp, maxhp: u.maxhp });
    }
    return init;
}

export interface Reading {
    state: State;
    /** Clash point now (along the lane path) and its move from `team`'s side over the horizon (positive = towards their T1). */
    clash: number;
    move: number;
    /** Where the clash sits between the T1s, 0 at ours, 1 at theirs. */
    q: number;
    /** The clash's distance along the path from our T1 (positive towards theirs). */
    own: number;
    /** The tower rule decided. */
    tower: boolean;
    /** Real milliseconds the runs took, when RealTime exists. */
    ms?: number;
}

/** The reading for a start state. Undefined when the run leaves no clash (a lane with no creeps of one team). */
export function ReadFrom(lane: LanePath, team: number, t0: number, init: StartCreep[], towerHp: Record<number, number | false | undefined>): Reading | undefined {
    const clock = (RealTime as unknown) !== undefined ? RealTime : undefined;
    const started = clock?.();
    const reading = readingOf(lane, team, t0, Run(lane, t0, readUntil(t0), init, towerHp));
    if (reading !== undefined && started !== undefined) reading.ms = math.floor((clock!() - started) * 10000 + 0.5) / 10;
    return reading;
}

/** The second a reading's run goes to. */
function readUntil(t0: number): number {
    return t0 + SETTINGS.Horizon + 2;
}

/** The reading from a run to `readUntil(t0)` (or its exact prefix, Upto). */
function readingOf(lane: LanePath, team: number, t0: number, smp: Sample[]): Reading | undefined {
    const h = SETTINGS.Horizon;
    const dir = dirOf(team);
    const c0 = ClashAt(smp, t0);
    const cH = ClashAt(smp, t0 + h);
    const move = c0 !== undefined && cH !== undefined ? dir * (cH - c0) : undefined;
    if (c0 === undefined || move === undefined) return undefined;
    const ours = lane.towers.find((tw) => tw.team === team)!;
    const theirs = lane.towers.find((tw) => tw.team !== team)!;
    const tower = TowerRule(lane, c0, team);
    const reading: Reading = {
        state: tower ?? StateOf(move),
        clash: c0,
        move,
        q: (c0 - ours.s) / (theirs.s - ours.s),
        own: dir * (c0 - ours.s),
        tower: tower !== undefined,
    };
    return reading;
}

/** The lane as a pull leaves it: `team`'s wave spawned at `ts` gone to the neutrals. */
export interface WaveGone {
    /** The clash's distance from our T1 along the path (positive towards theirs) at second `at`; undefined with no clash. */
    own?: number;
    /** HP of the creeps in lane before that pair of waves: ours less the pulled wave, theirs less the wave spawned with it. */
    ap: number;
    ep: number;
    /** 1 when the pulled wave was found near the schedule's spot (or is still to spawn), 0 when the forecast runs with it in. */
    pw: number;
}

/** Where the schedule puts `team`'s wave spawned at `ts` at second `t0`. */
function waveSpot(lane: LanePath, team: number, ts: number, t0: number): number {
    return (team === R ? lane.spawnR : lane.spawnD) + dirOf(team) * speed() * (t0 - ts);
}

/**
 * `team`'s view `init` at `t0` with its wave spawned at `ts` removed (its creeps near the schedule's spot, or the spawn left
 * out when it is still to come), run to `at`. A wave off its schedule (a creep block, already fighting) is not found and
 * stays in the run (`pw` 0). CANDIDATE(wave_gone): the pull trigger is its one reader.
 */
export function WaveGoneFrom(
    lane: LanePath,
    team: number,
    t0: number,
    init: StartCreep[],
    towerHp: Record<number, number | false | undefined>,
    ts: number,
    at: number,
): WaveGone {
    const spawned = t0 >= ts;
    const inWave = (c: StartCreep) => spawned && math.abs(c.s - waveSpot(lane, c.team, ts, t0)) <= SETTINGS.WaveWindow;
    const left: StartCreep[] = [];
    let ap = 0;
    let ep = 0;
    let found = !spawned;
    for (const c of init) {
        if (c.team === team && inWave(c)) {
            found = true;
            continue;
        }
        left.push(c);
        if (c.team === team) ap += c.hp;
        else if (!inWave(c)) ep += c.hp;
    }
    const smp = Run(lane, t0, at + 2, left, towerHp, spawned ? undefined : { team, t: ts });
    const clash = ClashAt(smp, at);
    const ours = lane.towers.find((tw) => tw.team === team)!;
    return { own: clash !== undefined ? dirOf(team) * (clash - ours.s) : undefined, ap, ep, pw: found ? 1 : 0 };
}

// ------------------------------------------------------------------------------------------------- the game's view

/** A path's segments read once (`Project`'s arithmetic, unchanged), in chunks of CHUNK with each chunk's bounding box. */
interface Segs {
    ax: number[];
    ay: number[];
    vx: number[];
    vy: number[];
    len2: number[];
    len: number[];
    s0: number[];
    /** Per chunk: its first and last segment index, and its points' bounding box. */
    lo: number[];
    hi: number[];
    x0: number[];
    x1: number[];
    y0: number[];
    y1: number[];
}

const CHUNK = 8;
/** A chunk is skipped only when its box is this much further than a segment already measured (rounding slack). */
const SLACK = 1e-6;
const segsOf = new LuaMap<LanePath, Segs>();

function segs(lane: LanePath): Segs {
    let g = segsOf.get(lane);
    if (g !== undefined) return g;
    g = { ax: [], ay: [], vx: [], vy: [], len2: [], len: [], s0: [], lo: [], hi: [], x0: [], x1: [], y0: [], y1: [] };
    const n = lane.pts.length - 1;
    for (let i = 1; i <= n; i++) {
        const ax = lane.pts[i - 1][0];
        const ay = lane.pts[i - 1][1];
        const vx = lane.pts[i][0] - ax;
        const vy = lane.pts[i][1] - ay;
        const len2 = vx * vx + vy * vy;
        g.ax.push(ax);
        g.ay.push(ay);
        g.vx.push(vx);
        g.vy.push(vy);
        g.len2.push(len2);
        g.len.push(math.sqrt(len2));
        g.s0.push(lane.s[i - 1]);
    }
    for (let lo = 0; lo < n; lo += CHUNK) {
        const hi = math.min(n, lo + CHUNK) - 1;
        let x0 = math.huge;
        let x1 = -math.huge;
        let y0 = math.huge;
        let y1 = -math.huge;
        for (let p = lo; p <= hi + 1; p++) {
            x0 = math.min(x0, lane.pts[p][0]);
            x1 = math.max(x1, lane.pts[p][0]);
            y0 = math.min(y0, lane.pts[p][1]);
            y1 = math.max(y1, lane.pts[p][1]);
        }
        g.lo.push(lo);
        g.hi.push(hi);
        g.x0.push(x0);
        g.x1.push(x1);
        g.y0.push(y0);
        g.y1.push(y1);
    }
    segsOf.set(lane, g);
    return g;
}

/** Projections already made this whole second, per path, by x then y: a creep that stands still, or is read by several
 *  callers in one frame, is projected once. Pure in (path, x, y), so a hit is the same answer. */
let memoAt: number | undefined;
let memoS = new LuaMap<LanePath, LuaMap<number, LuaMap<number, number>>>();
let memoD = new LuaMap<LanePath, LuaMap<number, LuaMap<number, number>>>();

function projectAll(lane: LanePath, x: number, y: number): LuaMultiReturn<[number, number]> {
    const g = segs(lane);
    // Box distances; the nearest box's segments give a bound no skipped segment can beat.
    const box: number[] = [];
    let nearest = 0;
    for (let c = 0; c < g.lo.length; c++) {
        const ex = x < g.x0[c] ? g.x0[c] - x : x > g.x1[c] ? x - g.x1[c] : 0;
        const ey = y < g.y0[c] ? g.y0[c] - y : y > g.y1[c] ? y - g.y1[c] : 0;
        box.push(math.sqrt(ex * ex + ey * ey));
        if (box[c] < box[nearest]) nearest = c;
    }
    const at = (i: number): LuaMultiReturn<[number, number]> => {
        const ax = g.ax[i];
        const ay = g.ay[i];
        const vx = g.vx[i];
        const vy = g.vy[i];
        const len2 = g.len2[i];
        const u = math.max(0, math.min(1, len2 > 0 ? ((x - ax) * vx + (y - ay) * vy) / len2 : 0));
        return $multi(math.sqrt((x - (ax + u * vx)) ** 2 + (y - (ay + u * vy)) ** 2), u);
    };
    let bound = math.huge;
    for (let i = g.lo[nearest]; i <= g.hi[nearest]; i++) bound = math.min(bound, at(i)[0]);
    // In path order, as the full scan: the first segment at the least distance wins.
    let bestD = math.huge;
    let bestS = 0;
    for (let c = 0; c < g.lo.length; c++) {
        if (box[c] > bound + SLACK) continue;
        for (let i = g.lo[c]; i <= g.hi[c]; i++) {
            const [d, u] = at(i);
            if (d < bestD) {
                bestD = d;
                bestS = g.s0[i] + u * g.len[i];
            }
        }
    }
    return $multi(bestS, bestD);
}

/** Distance along the lane path of the point nearest `(x, y)`, and how far the point is from the path. */
export function Project(lane: LanePath, x: number, y: number): LuaMultiReturn<[number, number]> {
    // A NaN cannot be a table key.
    if (x !== x || y !== y) return projectAll(lane, x, y);
    const clock = (DotaTime as unknown) !== undefined ? math.floor(DotaTime()) : undefined;
    if (clock !== memoAt) {
        memoAt = clock;
        memoS = new LuaMap();
        memoD = new LuaMap();
    }
    let bx = memoS.get(lane);
    let dx = memoD.get(lane);
    if (bx === undefined || dx === undefined) {
        bx = new LuaMap();
        dx = new LuaMap();
        memoS.set(lane, bx);
        memoD.set(lane, dx);
    }
    let by = bx.get(x);
    let dy = dx.get(x);
    if (by === undefined || dy === undefined) {
        by = new LuaMap();
        dy = new LuaMap();
        bx.set(x, by);
        dx.set(x, dy);
    }
    const s = by.get(y);
    const d = dy.get(y);
    if (s !== undefined && d !== undefined) return $multi(s, d);
    const [ps, pd] = projectAll(lane, x, y);
    by.set(y, ps);
    dy.set(y, pd);
    return $multi(ps, pd);
}

/** The full scan `Project` replaced, kept for the test that holds the two equal. */
export function ProjectScan(lane: LanePath, x: number, y: number): LuaMultiReturn<[number, number]> {
    let bestD = math.huge;
    let bestS = 0;
    for (let i = 1; i < lane.pts.length; i++) {
        const [ax, ay] = [lane.pts[i - 1][0], lane.pts[i - 1][1]];
        const vx = lane.pts[i][0] - ax;
        const vy = lane.pts[i][1] - ay;
        const len2 = vx * vx + vy * vy;
        const u = math.max(0, math.min(1, len2 > 0 ? ((x - ax) * vx + (y - ay) * vy) / len2 : 0));
        const d = math.sqrt((x - (ax + u * vx)) ** 2 + (y - (ay + u * vy)) ** 2);
        if (d < bestD) {
            bestD = d;
            bestS = lane.s[i - 1] + u * math.sqrt(len2);
        }
    }
    return $multi(bestS, bestD);
}

export function PathOf(lane: Lane): LanePath | undefined {
    return LANE_PATHS[lane];
}

/** `team`'s T1 on the path, and the sign that turns a path distance into "towards their T1". */
export function OwnT1(lane: LanePath, team: number): LuaMultiReturn<[number, number]> {
    return $multi(lane.towers.find((tw) => tw.team === team)!.s, dirOf(team));
}

/**
 * When `team`'s next wave reaches path distance `s`, at or after `now`: waves spawn every 30 s from 0:00 (WaveAt) at the
 * team's spawn end and walk the path at the lane creeps' 325.
 */
export function NextArrival(lane: LanePath, team: number, s: number, now: number): number {
    const spawn = team === R ? lane.spawnR : lane.spawnD;
    const travel = math.abs(s - spawn) / speed();
    const k = math.max(0, math.ceil((now - travel) / GameRules.WAVE_EVERY));
    return k * 30 + travel;
}

function kindOf(name: string): string | undefined {
    if (string.find(name, "siege", 1, true)[0] !== undefined) return "siege";
    if (string.find(name, "creep_goodguys", 1, true)[0] === undefined && string.find(name, "creep_badguys", 1, true)[0] === undefined) return undefined;
    if (string.find(name, "ranged", 1, true)[0] !== undefined) return "ranged";
    if (string.find(name, "flag", 1, true)[0] !== undefined) return "flag";
    return "melee";
}

export function IsLaneCreep(name: string): boolean {
    return kindOf(name) !== undefined;
}

/** Lane creeps of a unit list on this lane's path (alive; visible only for `visibleOnly`), as start creeps of `team`. */
function creepsOn(lane: LanePath, units: Unit[], team: number, visibleOnly: boolean): StartCreep[] {
    const out: StartCreep[] = [];
    for (const u of units) {
        if (!u.IsAlive() || (visibleOnly && !u.CanBeSeen())) continue;
        const kind = kindOf(u.GetUnitName());
        if (kind === undefined) continue;
        const loc = u.GetLocation();
        const [s, d] = Project(lane, loc.x, loc.y);
        // A creep near two lanes' paths (the base, the river crossings) counts on its nearest one only.
        if (d > SETTINGS.Assign || nearerLane(lane, loc, d)) continue;
        out.push({ team, kind, s, hp: u.GetHealth() });
    }
    return out;
}

function nearerLane(lane: LanePath, loc: Vector, d: number): boolean {
    for (const k of [Lane.Top, Lane.Mid, Lane.Bot]) {
        const other = LANE_PATHS[k];
        if (other === lane) continue;
        if (Project(other, loc.x, loc.y)[1] < d) return true;
    }
    return false;
}

const T1: Record<number, Tower> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };

function t1Hp(team: number, lane: Lane): number | false {
    const t = GetTower(team, T1[lane]);
    return t === undefined || t === null || !t.IsAlive() ? false : t.GetHealth();
}

/** The lane creeps `team`'s view of `lane` starts from at the whole second now: the path, the second, its own creeps and
 *  the visible enemy creeps on the path (the enemy wave tracker reads the same). */
export function CreepsNow(team: number, lane: Lane): LuaMultiReturn<[LanePath | undefined, number, StartCreep[], StartCreep[]]> {
    const path = LANE_PATHS[lane];
    const t0 = math.floor(DotaTime());
    if (path === undefined) return $multi(undefined, t0, [], []);
    const enemy = team === R ? D : R;
    return $multi(path, t0, creepsOn(path, GetUnitList(UnitType.AlliedCreeps), team, false), creepsOn(path, GetUnitList(UnitType.EnemyCreeps), enemy, true));
}

/** One team's view of one lane on one frame, and the longest plain run made from it on that frame. */
interface FrameView {
    frame: number;
    path?: LanePath;
    t0: number;
    init: StartCreep[];
    towerHp: Record<number, number | false | undefined>;
    walk?: number;
    until?: number;
    smp?: Sample[];
    steps?: number[];
}
/** By team * 10 + lane. Callers on one frame (lane_control's decide reads, forecasts and pulls the same view) share it:
 *  nothing a view reads changes inside a frame, and a plain run is a function of the view and the creep speed. */
let frameViews = new LuaMap<number, FrameView>();

/** `team`'s view of `lane` at the whole second now: the start creeps and T1 HP a run begins from (once a frame). */
function viewNow(team: number, lane: Lane): FrameView {
    const frame = DotaTime();
    const key = team * 10 + lane;
    const had = frameViews.get(key);
    // The raw live creep speed, not speed(): reading it here must not count a fallback a run that never walks would not.
    // ViewStart places unseen waves by the speed, so a speed that turns live within the frame rebuilds the view and its run.
    const walk = WorldFacts.Live()["lane_creep_speed"];
    if (had !== undefined && had.frame === frame && had.walk === walk) return had;
    const [path, t0, own, enemyCreeps] = CreepsNow(team, lane);
    let v: FrameView;
    if (path === undefined) v = { frame, walk, t0, init: [], towerHp: {} };
    else {
        const enemy = team === R ? D : R;
        v = { frame, walk, path, t0, init: ViewStart(path, team, t0, own, enemyCreeps), towerHp: { [team]: t1Hp(team, lane), [enemy]: t1Hp(enemy, lane) } };
    }
    frameViews.set(key, v);
    return v;
}

/** Forgets the frame views (a new game or test world in the same VM, at a DotaTime already seen). */
export function ResetFrames(): void {
    frameViews = new LuaMap<number, FrameView>();
}

/** The plain run of a view to `until`: the frame's longest run cut at `until` when it reaches that far, else a new run
 *  that becomes the frame's (viewNow has already matched the creep speed). */
function runOf(v: FrameView, path: LanePath, until: number): Sample[] {
    if (v.smp === undefined || v.until! < until) {
        const steps: number[] = [];
        v.smp = Run(path, v.t0, until, v.init, v.towerHp, undefined, steps);
        v.steps = steps;
        v.until = until;
    }
    return Upto(v.smp, v.steps!, until);
}

/** The reading for `team`'s side of `lane` now (the calling script must be `team`'s). */
export function Read(team: number, lane: Lane): Reading | undefined {
    const v = viewNow(team, lane);
    if (v.path === undefined) return undefined;
    const clock = (RealTime as unknown) !== undefined ? RealTime : undefined;
    const started = clock?.();
    const reading = readingOf(v.path, team, v.t0, runOf(v, v.path, readUntil(v.t0)));
    if (reading !== undefined && started !== undefined) reading.ms = math.floor((clock!() - started) * 10000 + 0.5) / 10;
    return reading;
}

/** The lane's target meeting point, as a distance along the lane from our T1. */
export function TargetOf(lane: Lane): number {
    return lane === Lane.Mid ? SETTINGS.TargetMid : SETTINGS.TargetSide;
}

/** `team`'s view of `lane` now with its wave spawned at `ts` pulled away (WaveGoneFrom). */
export function WaveGoneNow(team: number, lane: Lane, ts: number, at: number): WaveGone | undefined {
    const v = viewNow(team, lane);
    if (v.path === undefined) return undefined;
    return WaveGoneFrom(v.path, team, v.t0, v.init, v.towerHp, ts, at);
}

/** One run of `lane` from `team`'s view now, `horizon` seconds ahead: its samples and the path, or undefined. */
export function Forecast(team: number, lane: Lane, horizon: number): LuaMultiReturn<[Sample[] | undefined, LanePath | undefined]> {
    const v = viewNow(team, lane);
    if (v.path === undefined) return $multi(undefined, undefined);
    return $multi(runOf(v, v.path, v.t0 + horizon), v.path);
}

/** The map point at distance `s` along the lane path. */
export function PointAt(lane: LanePath, s: number): [number, number] {
    const n = lane.pts.length;
    if (s <= lane.s[0]) return [lane.pts[0][0], lane.pts[0][1]];
    for (let i = 1; i < n; i++) {
        if (s <= lane.s[i]) {
            const u = (s - lane.s[i - 1]) / math.max(1e-9, lane.s[i] - lane.s[i - 1]);
            return [lane.pts[i - 1][0] + u * (lane.pts[i][0] - lane.pts[i - 1][0]), lane.pts[i - 1][1] + u * (lane.pts[i][1] - lane.pts[i - 1][1])];
        }
    }
    return [lane.pts[n - 1][0], lane.pts[n - 1][1]];
}
