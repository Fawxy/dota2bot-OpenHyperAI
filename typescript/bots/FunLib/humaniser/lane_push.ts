/**
 * Lane push reading (slice support-lane, `docs/proposals/2026-11-03-lane-state-decisions.md` s6), CANDIDATE(lane_push): which
 * way the clash point of one lane moves over the next 30 s from one team's side, OUT (towards their tower), IN (towards ours)
 * or HOLD. Within `Near` of a T1 the tower rule decides (EC-079: a wave at a tower bounces off it); elsewhere one mean-damage
 * run of the creep-and-tower fight model, a port of `docs/proposals/lane-forecast/lane_sim.js` (kept equal to it by
 * test_lane_push.lua), started from the team's view: its own creeps, visible enemy creeps and enemy waves placed by the
 * spawn schedule where none is seen (push.js `initView`). Offline at 30 s: right 65% of the time, the best simple rule 43%.
 */
import { Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
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
};

const R = Team.Radiant;
const D = Team.Dire;
const SPEED = 325;
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
    return { ...k, team, kind, s, maxhp: k.hp, readyAt: t, alive: true };
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
 * Returns a sample of both leads every second from `from`.
 */
export function Run(lane: LanePath, from: number, until: number, init: StartCreep[] | undefined, towerHp: Record<number, number | false | undefined>): Sample[] {
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
    let live: SimUnit[] = [];
    const best = (u: SimUnit, r: number): SimUnit | undefined => {
        let pick: SimUnit | undefined;
        let key = math.huge;
        for (const v of live) {
            if (v.team === u.team || !v.alive || !inReach(u, v, r)) continue;
            const k = rank(u, v) * 1e6 + math.abs(v.s - u.s);
            if (k < key) {
                key = k;
                pick = v;
            }
        }
        return pick;
    };
    let nextSample = from;
    for (let t = from; t <= until + 1e-9; t = round3(t + dt)) {
        if (math.abs(t % 30) < dt / 2 && !(init !== undefined && t < from + dt / 2)) {
            const ts = math.floor(t + 0.5);
            for (const u of WaveAt(R, ts, lane.spawnR)) units.push(u);
            for (const u of WaveAt(D, ts, lane.spawnD)) units.push(u);
        }
        live = [];
        for (const u of units) if (u.alive) live.push(u);
        for (const u of live) {
            let r = u.regen;
            if (u.building !== true) {
                for (const f of live) {
                    if (f.aura === true && f.team === u.team && math.abs(f.s - u.s) <= FLAG_RADIUS) {
                        r += FLAG_REGEN;
                        break;
                    }
                }
            }
            u.hp = math.min(u.maxhp, u.hp + r * dt);
        }
        for (const u of live) {
            if (u.target !== undefined && !u.target.alive) {
                u.target = undefined;
                u.swingAt = undefined;
            }
            if (u.swingAt !== undefined) continue;
            if (u.target !== undefined) {
                const b = best(u, u.range);
                if (b !== undefined && (rank(u, b) < rank(u, u.target) || !inReach(u, u.target, u.range))) u.target = b;
                else if (!inReach(u, u.target, u.acq) && b === undefined) u.target = undefined;
            }
            if (u.target === undefined) u.target = best(u, u.acq);
        }
        for (const u of live) {
            const v = u.target;
            if (v !== undefined && math.abs(v.s - u.s) <= u.range + REACH) {
                if (u.swingAt === undefined && t >= u.readyAt) {
                    u.swingAt = t + u.point;
                    u.readyAt = t + u.bat;
                }
                if (u.swingAt !== undefined && t >= u.swingAt) {
                    u.swingAt = undefined;
                    const dmg = damage(u, v);
                    if (u.proj > 0) projectiles.push({ at: t + math.abs(v.s - u.s) / u.proj, dst: v, dmg });
                    else hit(v, dmg);
                }
            } else if (u.building !== true) {
                u.swingAt = undefined;
                const goal = v !== undefined ? (v.s > u.s ? 1 : v.s < u.s ? -1 : 0) : dirOf(u.team);
                u.s += goal * SPEED * dt;
            }
        }
        for (let i = projectiles.length - 1; i >= 0; i--) {
            const p = projectiles[i];
            if (t >= p.at) {
                if (p.dst.alive) hit(p.dst, p.dmg);
                projectiles.splice(i, 1);
            }
        }
        if (t >= nextSample) {
            const front: Record<number, number | undefined> = {};
            for (const u of units) {
                if (!u.alive || u.building === true) continue;
                const f = front[u.team];
                front[u.team] = f === undefined ? u.s : u.team === R ? math.max(f, u.s) : math.min(f, u.s);
            }
            samples.push({ t: nextSample, front, dead: { [R]: dead[R], [D]: dead[D] } });
            nextSample++;
        }
    }
    return samples;
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

/**
 * The start state from team `v`'s view at second `t0`: own and visible enemy creeps (HP clipped to the kind's maximum), plus
 * each enemy wave spawned in the last 90 s that nothing would see, placed by the schedule at full HP (push.js `initView`).
 */
export function ViewStart(lane: LanePath, v: number, t0: number, own: StartCreep[], enemy: StartCreep[]): StartCreep[] {
    const e = v === R ? D : R;
    const de = dirOf(e);
    const init: StartCreep[] = [];
    let lead: number | undefined;
    for (const c of own) {
        init.push({ team: v, kind: c.kind, s: c.s, hp: math.min(c.hp, maxHp(c.kind, t0)), maxhp: maxHp(c.kind, t0) });
        if (lead === undefined || dirOf(v) * (c.s - lead) > 0) lead = c.s;
    }
    for (const c of enemy) init.push({ team: e, kind: c.kind, s: c.s, hp: math.min(c.hp, maxHp(c.kind, t0)), maxhp: maxHp(c.kind, t0) });
    const spawnE = e === R ? lane.spawnR : lane.spawnD;
    for (let ts = math.floor(t0 / 30) * 30; ts >= t0 - 90 && ts >= 0; ts -= 30) {
        const pos = spawnE + de * SPEED * (t0 - ts);
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
    /** Counterfactual move with `team`'s creeps short of `dropBefore` removed (the wave a pull takes), when asked. */
    cf?: number;
    /** Real milliseconds the runs took, when RealTime exists. */
    ms?: number;
}

/**
 * The reading for a start state. `dropBefore`: also run the counterfactual without our creeps short of that point along
 * the path (behind it from our side). Undefined when the run leaves no clash (a lane with no creeps of one team).
 */
export function ReadFrom(lane: LanePath, team: number, t0: number, init: StartCreep[], towerHp: Record<number, number | false | undefined>, dropBefore?: number): Reading | undefined {
    const clock = (RealTime as unknown) !== undefined ? RealTime : undefined;
    const started = clock?.();
    const h = SETTINGS.Horizon;
    const dir = dirOf(team);
    const moveOf = (list: StartCreep[]): [number | undefined, number | undefined] => {
        const smp = Run(lane, t0, t0 + h + 2, list, towerHp);
        const c0 = ClashAt(smp, t0);
        const cH = ClashAt(smp, t0 + h);
        return [c0, c0 !== undefined && cH !== undefined ? dir * (cH - c0) : undefined];
    };
    const [c0, move] = moveOf(init);
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
    if (dropBefore !== undefined) {
        const kept = init.filter((c) => c.team !== team || dir * (c.s - dropBefore) >= 0);
        reading.cf = moveOf(kept)[1];
    }
    if (started !== undefined) reading.ms = math.floor((clock!() - started) * 10000 + 0.5) / 10;
    return reading;
}

// ------------------------------------------------------------------------------------------------- the game's view

/** Distance along the lane path of the point nearest `(x, y)`, and how far the point is from the path. */
export function Project(lane: LanePath, x: number, y: number): LuaMultiReturn<[number, number]> {
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

/** `team`'s view of `lane` at the whole second now: the start creeps and T1 HP a run begins from. */
function viewNow(team: number, lane: Lane): LuaMultiReturn<[LanePath | undefined, number, StartCreep[], Record<number, number | false | undefined>]> {
    const path = LANE_PATHS[lane];
    const t0 = math.floor(DotaTime());
    if (path === undefined) return $multi(undefined, t0, [], {});
    const enemy = team === R ? D : R;
    const init = ViewStart(path, team, t0, creepsOn(path, GetUnitList(UnitType.AlliedCreeps), team, false), creepsOn(path, GetUnitList(UnitType.EnemyCreeps), enemy, true));
    return $multi(path, t0, init, { [team]: t1Hp(team, lane), [enemy]: t1Hp(enemy, lane) });
}

/** The reading for `team`'s side of `lane` now (the calling script must be `team`'s). `dropBefore`: a point along the path,
 *  see ReadFrom. */
export function Read(team: number, lane: Lane, dropBefore?: number): Reading | undefined {
    const [path, t0, init, towerHp] = viewNow(team, lane);
    if (path === undefined) return undefined;
    return ReadFrom(path, team, t0, init, towerHp, dropBefore);
}

/** One run of `lane` from `team`'s view now, `horizon` seconds ahead: its samples and the path, or undefined. */
export function Forecast(team: number, lane: Lane, horizon: number): LuaMultiReturn<[Sample[] | undefined, LanePath | undefined]> {
    const [path, t0, init, towerHp] = viewNow(team, lane);
    if (path === undefined) return $multi(undefined, undefined);
    return $multi(Run(path, t0, t0 + horizon, init, towerHp), path);
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
