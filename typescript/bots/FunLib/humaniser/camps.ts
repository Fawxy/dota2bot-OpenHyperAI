/**
 * Camp resolution (task 07): matches the live neutral spawners to camps_data and derives lane geometry
 * (meet points, pull paths, stack exits) for seeds that carry no explicit vectors.
 * Spawn boxes always come from GetNeutralSpawners(), never from data.
 */
import { Lane, Team, Tower, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import { CAMP_DATA, CampDataEntry, DEFAULT_STACK_SEC } from "bots/FunLib/humaniser/camps_data";

export type CampType = "small" | "medium" | "large" | "ancient";
export type LaneKind = "safe" | "off" | "mid";

export interface PullData {
    aggroSec: number[];
    halfAggroSec?: number[];
    path: Vector[];
    meetPoint: Vector;
    halfMeetPoint?: Vector;
}

export interface CampJobData {
    campIdx: number;
    /** The team whose job this is; differs from the spawner's team for an enemy-side (off-lane) camp. */
    team: number;
    lane?: Lane;
    stack?: { aggroSec: number; exitPath: Vector[] };
    pull?: PullData;
    source: "seed" | "replay" | "measured";
    type: CampType;
    key?: string;
    derived: boolean;
    unverified?: boolean;
}

export interface Spawner {
    idx: number;
    team: number;
    type: CampType;
    location: Vector;
    min: Vector;
    max: Vector;
    speed: any;
}

/**
 * Engine lane amounts run from the calling script's own base (0) to the enemy's (1): in console.9055745679 Dire's
 * GetAmountAlongLane tower amounts mirror Radiant's for the mirror lanes. "Abs" amounts below are that engine frame;
 * ToTeamAmount/ToAbsAmount convert to and from `team`'s frame, which differs from it when a script reasons about the
 * other team (enemy camps, enemy lane state).
 * **TODO (in-game):** GetLocationAlongLane is assumed to share GetAmountAlongLane's frame (only the latter was measured).
 * Set false to go back to treating engine amounts as absolute (0 = Radiant ancient) for both teams.
 */
const LANE_AMOUNT_TEAM_RELATIVE = true;

const LANES: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];
const TYPE_RANK: Record<string, number> = { small: 0, medium: 1, large: 2, ancient: 3 };
// TODO (in-game): the API doc says an int, OHA treats it as a string; both are accepted.
const TYPE_BY_INT: CampType[] = ["small", "medium", "large", "ancient"];

function normaliseType(raw: any): CampType {
    if (type(raw) === "number") return TYPE_BY_INT[raw as number] ?? "medium";
    const s = string.lower(tostring(raw));
    if (s === "small" || s === "medium" || s === "large" || s === "ancient") return s;
    return "medium";
}

function camps(): LaneConfig.LaneSettings["Camps"] {
    return LaneConfig.Settings().Camps;
}

function dist2D(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

let spawnerCache: Spawner[] | undefined;
let resolveCache: CampJobData[] | undefined;
/** Job of the spawner's own team, per camp. */
let byIdx: Record<number, CampJobData> = {};
/** Seed and replay jobs per team, per camp: one camp can be one team's safe-lane camp and the other's off-lane camp. */
let byTeam: Record<number, Record<number, CampJobData>> = {};

export function ResetCache(): void {
    spawnerCache = undefined;
    resolveCache = undefined;
    byIdx = {};
    byTeam = {};
}

export function Spawners(): Spawner[] {
    if (spawnerCache !== undefined) return spawnerCache;
    const list: Spawner[] = [];
    const raw = GetNeutralSpawners();
    if (raw !== undefined && raw !== null) {
        for (const [key, entry] of pairs(raw as any)) {
            const e = entry as any;
            const idx = type(key) === "number" ? (key as number) : (e.idx as number);
            list.push({ idx, team: e.team, type: normaliseType(e.type), location: e.location, min: e.min, max: e.max, speed: e.speed });
        }
    }
    list.sort((a, b) => a.idx - b.idx);
    // Spawners may not exist yet early in the game; only a non-empty result is final.
    if (list.length > 0) spawnerCache = list;
    return list;
}

export function BoxCenter(s: Spawner): Vector {
    return Vector((s.min.x + s.max.x) / 2, (s.min.y + s.max.y) / 2, (s.min.z + s.max.z) / 2);
}

export function NearestSpawner(loc: Vector): LuaMultiReturn<[Spawner | undefined, number]> {
    let best: Spawner | undefined;
    let bestDist = math.huge;
    for (const s of Spawners()) {
        const d = dist2D(BoxCenter(s), loc);
        if (d < bestDist) {
            bestDist = d;
            best = s;
        }
    }
    return $multi(best, bestDist);
}

export function InBox(idx: number, loc: Vector, margin: number = 0): boolean {
    for (const s of Spawners()) {
        if (s.idx !== idx) continue;
        return loc.x >= s.min.x - margin && loc.x <= s.max.x + margin && loc.y >= s.min.y - margin && loc.y <= s.max.y + margin;
    }
    return false;
}

export function LaneOfKind(team: number, kind: LaneKind): Lane {
    if (kind === "mid") return Lane.Mid;
    const radiant = team === Team.Radiant;
    const safe = radiant ? Lane.Bot : Lane.Top;
    const off = radiant ? Lane.Top : Lane.Bot;
    return kind === "safe" ? safe : off;
}

export function ToTeamAmount(team: number, absAmount: number): number {
    const frameTeam = LANE_AMOUNT_TEAM_RELATIVE ? GetTeam() : Team.Radiant;
    return team === frameTeam ? absAmount : 1 - absAmount;
}

export function ToAbsAmount(team: number, teamAmount: number): number {
    return ToTeamAmount(team, teamAmount);
}

export function NearestLaneAmount(lane: Lane, loc: Vector): number {
    const step = camps().LaneSampleStep;
    const n = math.floor(1 / step + 0.5);
    let best = 0;
    let bestDist = math.huge;
    for (let i = 0; i <= n; i++) {
        const a = math.min(1, i * step);
        const d = dist2D(GetLocationAlongLane(lane, a), loc);
        if (d < bestDist) {
            bestDist = d;
            best = a;
        }
    }
    return best;
}

export function DeriveMeetPoint(_team: number, lane: Lane, campLoc: Vector): Vector {
    return GetLocationAlongLane(lane, NearestLaneAmount(lane, campLoc));
}

export function DeriveHalfMeetPoint(team: number, lane: Lane, meet: Vector): Vector {
    const step = camps().LaneSampleStep;
    const offset = camps().HalfMeetOffset;
    // Our wave walks toward the enemy base: up the engine amount in our own frame, down in the other team's.
    const dir = ToAbsAmount(team, 1) > ToAbsAmount(team, 0) ? 1 : -1;
    let a = NearestLaneAmount(lane, meet);
    let prev = GetLocationAlongLane(lane, a);
    let prevDist = dist2D(prev, meet);
    while (a > 0 && a < 1) {
        a = math.max(0, math.min(1, a + dir * step));
        const cur = GetLocationAlongLane(lane, a);
        const curDist = dist2D(cur, meet);
        if (curDist >= offset) {
            const span = curDist - prevDist;
            const t = span > 0 ? math.max(0, math.min(1, (offset - prevDist) / span)) : 1;
            return Vector(prev.x + (cur.x - prev.x) * t, prev.y + (cur.y - prev.y) * t, prev.z + (cur.z - prev.z) * t);
        }
        prev = cur;
        prevDist = curDist;
    }
    return prev;
}

/** Point `offset` outside the spawn box, on the ray from its centre toward `target`; undefined when they coincide. */
export function BoxEdgePoint(s: Spawner, target: Vector, offset: number): Vector | undefined {
    const c = BoxCenter(s);
    const dx = target.x - c.x;
    const dy = target.y - c.y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return undefined;
    const ux = dx / len;
    const uy = dy / len;
    const halfW = (s.max.x - s.min.x) / 2;
    const halfH = (s.max.y - s.min.y) / 2;
    const tx = math.abs(ux) > 1e-6 ? halfW / math.abs(ux) : math.huge;
    const ty = math.abs(uy) > 1e-6 ? halfH / math.abs(uy) : math.huge;
    const t = math.min(tx, ty) + offset;
    return Vector(c.x + ux * t, c.y + uy * t, c.z);
}

/**
 * Where a bot stands to aggro the camp: on the ray from the spawner origin (where the neutrals idle, not the box
 * centre) toward `toward`, `offset` past the box edge but at most Radii.StandReach from the origin. 7.41 boxes are
 * 600-1150 wide with the origin off-centre (good_8/evil_8: ~1000 from the west edge), so an edge stand could leave the
 * camp outside NeutralSearch or behind the trees along the box edge (console.9055828679 `mistake:no-camp`).
 */
export function StandPoint(s: Spawner, toward: Vector, offset: number): Vector {
    const o = s.location;
    const dx = toward.x - o.x;
    const dy = toward.y - o.y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return o;
    const ux = dx / len;
    const uy = dy / len;
    const tx = ux > 1e-6 ? (s.max.x - o.x) / ux : ux < -1e-6 ? (s.min.x - o.x) / ux : math.huge;
    const ty = uy > 1e-6 ? (s.max.y - o.y) / uy : uy < -1e-6 ? (s.min.y - o.y) / uy : math.huge;
    const d = math.min(math.max(0, math.min(tx, ty)) + offset, LaneConfig.Settings().Radii.StandReach);
    return Vector(o.x + ux * d, o.y + uy * d, o.z);
}

export function DerivePullPath(s: Spawner, meet: Vector): Vector[] {
    const edge = BoxEdgePoint(s, meet, LaneConfig.Settings().Radii.PullPathEdge);
    return edge === undefined ? [meet] : [edge, meet];
}

export function SpawnerByIdx(idx: number): Spawner | undefined {
    for (const s of Spawners()) if (s.idx === idx) return s;
    return undefined;
}

export function DeriveStackExit(s: Spawner, _team: number): Vector[] {
    const c = BoxCenter(s);
    let nearest: Vector | undefined;
    let nearestDist = math.huge;
    for (const lane of LANES) {
        const p = GetLocationAlongLane(lane, NearestLaneAmount(lane, c));
        const d = dist2D(p, c);
        if (d < nearestDist) {
            nearestDist = d;
            nearest = p;
        }
    }
    const away = LaneConfig.Settings().Radii.StackExit;
    let ux = 0;
    let uy = -1;
    if (nearest !== undefined && nearestDist >= 1) {
        ux = (c.x - nearest.x) / nearestDist;
        uy = (c.y - nearest.y) / nearestDist;
    }
    // Directly away from the lane can run into the map edge: evil_7 (Dire hard camp behind the bot T2) sits ~200 from it, so the
    // walk-off ended 350 past the box and its ranged trolls kept shooting from inside (console.9055828679, after=3).
    // Turn by 45 degree steps, at each step the side farther from the lane first, until the whole walk is passable.
    // StackExit is measured past the box edge, not from the centre: 7.41 boxes are 600-1100 wide, so from the
    // centre the walk-off from the stand point (edge + StandOffset) shrank to ~300-450 and the camp was not dragged clear.
    let fallback: Vector | undefined;
    for (const turn of [0, 45, 90, 135]) {
        const candidates: Vector[] = [];
        for (const sign of turn === 0 ? [1] : [1, -1]) {
            const a = (sign * turn * math.pi) / 180;
            const dx = ux * math.cos(a) - uy * math.sin(a);
            const dy = ux * math.sin(a) + uy * math.cos(a);
            const target = Vector(c.x + dx * away, c.y + dy * away, c.z);
            candidates.push(BoxEdgePoint(s, target, away) ?? target);
        }
        if (nearest !== undefined && candidates.length === 2 && dist2D(candidates[1], nearest) > dist2D(candidates[0], nearest)) candidates.reverse();
        fallback = fallback ?? candidates[0];
        for (const exit of candidates) if (walkable(BoxEdgePoint(s, exit, 0) ?? c, exit)) return [exit];
    }
    return [fallback ?? c];
}

function walkable(from: Vector, to: Vector): boolean {
    const step = LaneConfig.Settings().Radii.ExitCheckStep;
    const n = math.max(1, math.ceil(dist2D(from, to) / step));
    for (let i = 1; i <= n; i++) {
        const t = i / n;
        if (!IsLocationPassable(Vector(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t, from.z))) return false;
    }
    return true;
}

const T1: Record<number, number> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };
const T2: Record<number, number> = { [Lane.Top]: Tower.Top2, [Lane.Mid]: Tower.Mid2, [Lane.Bot]: Tower.Bot2 };

function laneTower(team: number, lane: Lane): Vector | undefined {
    for (const id of [T1[lane], T2[lane]]) {
        const tower = GetTower(team, id);
        if (tower !== null && tower !== undefined && tower.IsAlive()) return tower.GetLocation();
    }
    return undefined;
}

function campTeamOf(entry: CampDataEntry): number {
    if (entry.enemySide !== true) return entry.team;
    return entry.team === Team.Radiant ? Team.Dire : Team.Radiant;
}

function matchReplay(s: Spawner): CampDataEntry | undefined {
    const radius = camps().ReplayMatchRadius;
    for (const entry of CAMP_DATA) {
        if (entry.near === undefined || campTeamOf(entry) !== s.team || entry.type !== s.type) continue;
        if (dist2D(entry.near, s.location) <= radius) return entry;
    }
    return undefined;
}

function stackFor(s: Spawner, entry: CampDataEntry | undefined): { aggroSec: number; exitPath: Vector[] } {
    return {
        aggroSec: entry?.stackAggroSec ?? DEFAULT_STACK_SEC[s.type],
        exitPath: entry?.stackExitPath ?? DeriveStackExit(s, s.team),
    };
}

export function Resolve(): CampJobData[] {
    if (resolveCache !== undefined) return resolveCache;
    const spawners = Spawners();
    const jobs: Record<number, Record<number, CampJobData>> = { [Team.Radiant]: {}, [Team.Dire]: {} };

    for (const s of spawners) {
        const entry = matchReplay(s);
        if (entry === undefined) continue;
        const lane = entry.laneKind !== undefined ? LaneOfKind(entry.team, entry.laneKind) : undefined;
        const job: CampJobData = {
            campIdx: s.idx,
            team: entry.team,
            lane,
            stack: stackFor(s, entry),
            source: entry.source,
            type: s.type,
            key: entry.key,
            derived: false,
            unverified: entry.unverified,
        };
        if (lane !== undefined && entry.pullAggroSec !== undefined && entry.pullPath !== undefined && entry.meetPoint !== undefined) {
            job.pull = { aggroSec: entry.pullAggroSec, halfAggroSec: entry.halfAggroSec, path: entry.pullPath, meetPoint: entry.meetPoint, halfMeetPoint: entry.halfMeetPoint };
        }
        jobs[entry.team][s.idx] = job;
    }

    for (const entry of CAMP_DATA) {
        if (entry.near !== undefined || entry.laneKind === undefined || entry.pullAggroSec === undefined) continue;
        const lane = LaneOfKind(entry.team, entry.laneKind);
        const tower = laneTower(entry.team, lane);
        if (tower === undefined) continue;
        const maxTowerDist = entry.maxTowerDist ?? camps().PullCampMaxTowerDist;
        const own = jobs[entry.team];
        const campTeam = campTeamOf(entry);
        let best: Spawner | undefined;
        let bestDist = math.huge;
        for (const s of spawners) {
            if (own[s.idx] !== undefined || s.team !== campTeam || s.type !== entry.type) continue;
            const d = dist2D(s.location, tower);
            if (d >= bestDist || d > maxTowerDist) continue;
            // Near the tower is not enough: a jungle camp behind it cannot be led to the lane.
            if (dist2D(s.location, DeriveMeetPoint(entry.team, lane, s.location)) > camps().PullCampMaxLaneDist) continue;
            bestDist = d;
            best = s;
        }
        if (best === undefined) continue;
        const meet = DeriveMeetPoint(entry.team, lane, best.location);
        own[best.idx] = {
            campIdx: best.idx,
            team: entry.team,
            lane,
            stack: stackFor(best, entry),
            pull: {
                aggroSec: entry.pullAggroSec,
                halfAggroSec: entry.halfAggroSec,
                path: DerivePullPath(best, meet),
                meetPoint: meet,
                halfMeetPoint: DeriveHalfMeetPoint(entry.team, lane, meet),
            },
            source: entry.source,
            type: best.type,
            key: entry.key,
            derived: true,
            unverified: entry.unverified,
        };
    }

    const result: CampJobData[] = [];
    for (const s of spawners) {
        const job = jobs[s.team]?.[s.idx] ?? {
            campIdx: s.idx,
            team: s.team,
            stack: stackFor(s, undefined),
            source: "seed",
            type: s.type,
            derived: true,
        };
        result.push(job);
        byIdx[s.idx] = job;
        const enemyJob = jobs[s.team === Team.Radiant ? Team.Dire : Team.Radiant][s.idx];
        if (enemyJob !== undefined) result.push(enemyJob);
    }
    byTeam = jobs;
    if (spawners.length > 0) resolveCache = result;
    return result;
}

/** `team`'s job on the camp, else the job of the spawner's own team (every spawner has one). */
export function ByIdx(idx: number, team?: number): CampJobData | undefined {
    Resolve();
    return (team !== undefined ? byTeam[team]?.[idx] : undefined) ?? byIdx[idx];
}

export function PullCampsFor(team: number, lane: Lane): CampJobData[] {
    const found: CampJobData[] = [];
    for (const job of Resolve()) {
        if (job.team === team && job.lane === lane && job.pull !== undefined) found.push(job);
    }
    found.sort((a, b) => (TYPE_RANK[a.type] !== TYPE_RANK[b.type] ? TYPE_RANK[a.type] - TYPE_RANK[b.type] : a.campIdx - b.campIdx));
    return found;
}
