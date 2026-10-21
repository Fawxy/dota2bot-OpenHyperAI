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
    team: number;
    lane?: Lane;
    stack?: { aggroSec: number; exitPath: Vector[] };
    pull?: PullData;
    source: "seed" | "replay" | "measured";
    type: CampType;
    key?: string;
    derived: boolean;
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
 * **TODO (in-game):** GetAmountAlongLane/GetLocationAlongLane are assumed absolute (0 = Radiant ancient) while
 * GetLaneFrontAmount is team-relative. OHA's J.GetClosestTeamLane feeds a team-relative amount straight into
 * GetLocationAlongLane, so one assumption may be wrong for Dire. Flip this if so.
 */
const LANE_AMOUNT_TEAM_RELATIVE = false;

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
let byIdx: Record<number, CampJobData> = {};

export function ResetCache(): void {
    spawnerCache = undefined;
    resolveCache = undefined;
    byIdx = {};
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
    spawnerCache = list;
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
    if (LANE_AMOUNT_TEAM_RELATIVE || team === Team.Radiant) return absAmount;
    return 1 - absAmount;
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
    // Our wave walks toward the enemy base: up the absolute amount for Radiant, down for Dire.
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

export function DerivePullPath(s: Spawner, meet: Vector): Vector[] {
    const c = BoxCenter(s);
    const dx = meet.x - c.x;
    const dy = meet.y - c.y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) return [meet];
    const ux = dx / len;
    const uy = dy / len;
    const halfW = (s.max.x - s.min.x) / 2;
    const halfH = (s.max.y - s.min.y) / 2;
    const tx = math.abs(ux) > 1e-6 ? halfW / math.abs(ux) : math.huge;
    const ty = math.abs(uy) > 1e-6 ? halfH / math.abs(uy) : math.huge;
    const t = math.min(tx, ty) + LaneConfig.Settings().Radii.PullPathEdge;
    return [Vector(c.x + ux * t, c.y + uy * t, c.z), meet];
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
    if (nearest === undefined || nearestDist < 1) return [Vector(c.x, c.y - away, c.z)];
    const ux = (c.x - nearest.x) / nearestDist;
    const uy = (c.y - nearest.y) / nearestDist;
    return [Vector(c.x + ux * away, c.y + uy * away, c.z)];
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

function matchReplay(s: Spawner): CampDataEntry | undefined {
    const radius = camps().ReplayMatchRadius;
    for (const entry of CAMP_DATA) {
        if (entry.near === undefined || entry.team !== s.team || entry.type !== s.type) continue;
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
    const jobs: Record<number, CampJobData> = {};
    const claimed: Record<number, boolean> = {};

    for (const s of spawners) {
        const entry = matchReplay(s);
        if (entry === undefined) continue;
        claimed[s.idx] = true;
        const lane = entry.laneKind !== undefined ? LaneOfKind(entry.team, entry.laneKind) : undefined;
        const job: CampJobData = {
            campIdx: s.idx,
            team: s.team,
            lane,
            stack: stackFor(s, entry),
            source: entry.source,
            type: s.type,
            key: entry.key,
            derived: false,
        };
        if (lane !== undefined && entry.pullAggroSec !== undefined && entry.pullPath !== undefined && entry.meetPoint !== undefined) {
            job.pull = { aggroSec: entry.pullAggroSec, halfAggroSec: entry.halfAggroSec, path: entry.pullPath, meetPoint: entry.meetPoint, halfMeetPoint: entry.halfMeetPoint };
        }
        jobs[s.idx] = job;
    }

    for (const entry of CAMP_DATA) {
        if (entry.near !== undefined || entry.laneKind === undefined || entry.pullAggroSec === undefined) continue;
        const lane = LaneOfKind(entry.team, entry.laneKind);
        const tower = laneTower(entry.team, lane);
        if (tower === undefined) continue;
        let best: Spawner | undefined;
        let bestDist = math.huge;
        for (const s of spawners) {
            if (claimed[s.idx] === true || s.team !== entry.team || s.type !== entry.type) continue;
            const d = dist2D(s.location, tower);
            if (d < bestDist) {
                bestDist = d;
                best = s;
            }
        }
        if (best === undefined || bestDist > camps().PullCampMaxTowerDist) continue;
        claimed[best.idx] = true;
        const meet = DeriveMeetPoint(entry.team, lane, best.location);
        jobs[best.idx] = {
            campIdx: best.idx,
            team: best.team,
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
        };
    }

    const result: CampJobData[] = [];
    for (const s of spawners) {
        const job = jobs[s.idx] ?? {
            campIdx: s.idx,
            team: s.team,
            stack: stackFor(s, undefined),
            source: "seed",
            type: s.type,
            derived: true,
        };
        result.push(job);
        byIdx[s.idx] = job;
    }
    resolveCache = result;
    return result;
}

export function ByIdx(idx: number): CampJobData | undefined {
    Resolve();
    return byIdx[idx];
}

export function PullCampsFor(team: number, lane: Lane): CampJobData[] {
    const found: CampJobData[] = [];
    for (const job of Resolve()) {
        if (job.team === team && job.lane === lane && job.pull !== undefined) found.push(job);
    }
    found.sort((a, b) => (TYPE_RANK[a.type] !== TYPE_RANK[b.type] ? TYPE_RANK[a.type] - TYPE_RANK[b.type] : a.campIdx - b.campIdx));
    return found;
}
