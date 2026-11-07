/**
 * Pull aggro timing from wave arrival (task 07). Our wave spawns at :00/:30 at its lane's melee spawner and walks
 * the lane's path_corner chain at lane-creep speed; the aggro second is its arrival at the camp's meet point minus
 * the neutrals' walk from the spawner origin along the lead path, minus a lead so the neutrals are there first.
 * Camps whose meet point is not on our lane's chain (another map, a moved camp) keep their data-table seconds.
 */
import { Lane, Team, UnitType, Vector } from "bots/ts_libs/dota";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneState from "bots/FunLib/humaniser/lane_state";

export type TimingSource = "wave" | "live" | "seed";

/**
 * 7.41 lane creep paths from maps/dota.vpk (entity lump, 22/10/2026): each team's npc_dota_spawner_<team>_<lane>
 * origin (the melee spawner), then the path_corner chain from its NPCFirstWaypoint. The first corner lies ~150-540
 * behind the spawner on every lane; creeps walk it, so it is kept.
 */
const LANE_PATHS: Record<string, number[][]> = {
    radiant_top: [[-6608, -4064], [-6584, -4224], [-6080, 384], [-6656, 1600], [-6208, 4224], [-6200, 5312], [-5792, 5464], [-5160, 5712], [-4488, 5824], [-3784, 5928], [-2792, 6048], [-1856, 6104], [3856, 5784], [5323, 4852]],
    radiant_mid: [[-5008, -4488], [-4856, -4376], [-3148, -2694], [-976, -824], [-360, -256], [176, 120], [912, 624], [2584, 1704], [4472, 3944], [5323, 4788]],
    radiant_bot: [[-3648, -6112], [-4024, -6112], [480, -6457], [2048, -6336], [3320, -6184], [4028, -6140], [4672, -6098], [5743, -5781], [6028, -5484], [6133, -4708], [6256, -3252], [6336, 3328], [5387, 4788]],
    dire_top: [[3168, 5792], [3704, 5768], [-1872, 6144], [-5248, 5696], [-6139, 5476], [-6236, 4872], [-6336, 3896], [-6576, -3720], [-5591, -5024]],
    dire_mid: [[4096, 3584], [4456, 3960], [2520, 1728], [864, 672], [144, 152], [-392, -224], [-1008, -760], [-4872, -4360], [-5527, -5024]],
    dire_bot: [[6272, 3648], [6320, 3840], [6080, 352], [6720, -2112], [6298, -3319], [6315, -4054], [6087, -5290], [5711, -5784], [5312, -6140], [1036, -6428], [-4224, -6096], [-5527, -5088]],
};

const LANE_NAME: Record<number, string> = { [Lane.Top]: "top", [Lane.Mid]: "mid", [Lane.Bot]: "bot" };

export interface PullTiming {
    /** Aggro seconds within the minute, one per wave slot, ascending. */
    seconds: number[];
    source: TimingSource;
    /** Seconds from the aggro second to the wave reaching the meet point (watch window). */
    waveAfter?: number;
    /** Wave travel from spawn to the meet point. */
    waveTravel?: number;
    /** Path distance from the spawner to the meet point (live wave reading). */
    meetAlong?: number;
    lanePath?: number[][];
    /** Seconds the wave runs ahead of the constant-speed model on this lane (WaveAhead). */
    ahead?: number;
    /** The team whose wave is pulled (ours or the other team's); LiveRead reads that team's creeps. */
    team?: number;
    /** Seconds the neutrals take from the hit to the meet point (the lead path at NeutralSpeed), and that speed. */
    walk?: number;
    neutralSpeed?: number;
    /** What `Read` needs to read the speed again at the order: the lead path's length, the camp's type, seed speed and index. */
    walkLen?: number;
    type?: string;
    seedSpeed?: number;
    campIdx?: number;
}

/** A live reading of our wave against the plan: the shift from its body (applied) and from its front creep (logged). */
export interface LiveReading {
    shift: number;
    front: number;
}

function settings(): LaneConfig.LaneSettings["PullTiming"] {
    return LaneConfig.Settings().PullTiming;
}

function hypot(ax: number, ay: number, bx: number, by: number): number {
    const dx = ax - bx;
    const dy = ay - by;
    return math.sqrt(dx * dx + dy * dy);
}

export function LanePath(team: number, lane: Lane): number[][] | undefined {
    const name = LANE_NAME[lane];
    if (name === undefined || (team !== Team.Radiant && team !== Team.Dire)) return undefined;
    const key = `${team === Team.Radiant ? "radiant" : "dire"}_${name}`;
    return (settings().LanePaths as Record<string, number[][]>)[key] ?? LANE_PATHS[key];
}

/** Distance along `path` (from its first point) to the nearest point on it, and how far `p` is from that point. */
export function Along(path: number[][], p: Vector): LuaMultiReturn<[number, number]> {
    let acc = 0;
    let bestAlong = 0;
    let bestOff = math.huge;
    for (let i = 0; i + 1 < path.length; i++) {
        const [ax, ay] = path[i];
        const [bx, by] = path[i + 1];
        const len = hypot(ax, ay, bx, by);
        let t = len > 0 ? ((p.x - ax) * (bx - ax) + (p.y - ay) * (by - ay)) / (len * len) : 0;
        t = math.max(0, math.min(1, t));
        const off = hypot(p.x, p.y, ax + (bx - ax) * t, ay + (by - ay) * t);
        if (off < bestOff) {
            bestOff = off;
            bestAlong = acc + t * len;
        }
        acc += len;
    }
    return $multi(bestAlong, bestOff);
}

export function WalkLength(from: Vector, path: Vector[]): number {
    let d = 0;
    let prev = from;
    for (const p of path) {
        d += hypot(prev.x, prev.y, p.x, p.y);
        prev = p;
    }
    return d;
}

function normalise(s: number, period: number): number {
    return s - math.floor(s / period) * period;
}

/**
 * Wave-derived aggro seconds for `team`'s wave on `lane` and a camp whose neutrals walk `leadPath` (ending at the
 * meet point) from `origin`; `seed` when an input is missing or the meet point is off the lane path.
 */
export function For(team: number, lane: Lane | undefined, origin: Vector | undefined, type: Camps.CampType, leadPath: Vector[], seed: number[], campIdx?: number): PullTiming {
    const cfg = settings();
    const fallback: PullTiming = { seconds: seed, source: "seed" };
    const meet = leadPath[leadPath.length - 1];
    const seedSpeed = (cfg.NeutralSpeed as Record<string, number>)[type];
    const neutralSpeed = seedSpeed === undefined ? undefined : WorldFacts.NeutralSpeedFor(type, seedSpeed, campIdx);
    if (cfg.FromWave !== true || lane === undefined || origin === undefined || meet === undefined || neutralSpeed === undefined) return fallback;
    const path = LanePath(team, lane);
    if (path === undefined || path.length < 2) return fallback;
    const [meetAlong, off] = Along(path, meet);
    if (off > cfg.PathMaxOffset) return fallback;
    const t = LaneConfig.Settings().Timing;
    const ahead = LaneAhead(team, lane);
    const waveTravel = meetAlong / WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed) - ahead;
    const walkLen = WalkLength(origin, leadPath);
    const walk = walkLen / neutralSpeed;
    const waveAfter = walk + cfg.Lead;
    const seconds = (cfg.WaveSlots as number[]).map((slot) => normalise(slot + waveTravel - waveAfter, t.PullPeriod));
    seconds.sort((a, b) => a - b);
    return { seconds, source: "wave", waveAfter, waveTravel, meetAlong, lanePath: path, ahead, team, walk, neutralSpeed, walkLen, type, seedSpeed, campIdx };
}

/** WaveAhead for `team`'s `lane`: the safe lane's or the off lane's, 0 for mid. */
function LaneAhead(team: number, lane: Lane): number {
    const ahead = settings().WaveAhead;
    if (lane === Lane.Mid) return 0;
    const safe = (team === Team.Radiant) === (lane === Lane.Bot);
    return safe ? ahead.safe : ahead.off;
}

/** The camp's lead waypoints with its own meet point replaced by `meet`. */
export function LeadPath(pull: Camps.PullData, meet: Vector): Vector[] {
    const result: Vector[] = [];
    const n = pull.path.length;
    for (let i = 0; i < n; i++) {
        const p = pull.path[i];
        if (i === n - 1 && hypot(p.x, p.y, pull.meetPoint.x, pull.meetPoint.y) < 1) continue;
        result.push(p);
    }
    result.push(meet);
    return result;
}

/**
 * `data`'s pull seconds: from its team's wave reaching the pull's meet point for seed camps, else the data table's, since
 * replay and measured seconds are measurements.
 */
export function ForCamp(data: Camps.CampJobData): PullTiming {
    if (data.pull === undefined) return { seconds: [], source: "seed" };
    const seed = data.pull.aggroSec;
    const spawner = Camps.SpawnerByIdx(data.campIdx);
    if (data.source !== "seed" || spawner === undefined) return { seconds: seed, source: "seed" };
    return For(data.team, data.lane, spawner.location, data.type, LeadPath(data.pull, data.pull.meetPoint), seed, data.campIdx);
}

/**
 * The old camp-job pulls' live correction (camp_jobs; the pull job times its hit on the creeps, CreepTimer).
 * Live correction for a wave-timed pull at `aggroAt` (no jitter): once its wave has left the barracks, its lane creeps
 * within LiveWindow of where the wave should be say how early or late it really is. The plan already carries the lane's
 * WaveAhead; this is what is left. The shift applied is the wave's body (the mean of those creeps): the front creep runs
 * ahead of the creeps that take the neutrals (camp 1 hit 0.5-1 s early on the front creep, replay pdg3_C), so it is only
 * logged. A wave can also be blocked or held up on the way. Undefined when nothing reliable is seen.
 */
export function LiveRead(timing: PullTiming, aggroAt: number, now: number): LiveReading | undefined {
    if (timing.source !== "wave" || timing.waveAfter === undefined || timing.waveTravel === undefined || timing.meetAlong === undefined || timing.lanePath === undefined)
        return undefined;
    const cfg = settings();
    const spawnAt = aggroAt + timing.waveAfter - timing.waveTravel;
    if (now < spawnAt + cfg.LiveFrom) return undefined;
    const expected = (now - spawnAt + (timing.ahead ?? 0)) * WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed);
    if (expected >= timing.meetAlong) return undefined;
    const window = cfg.LiveWindow * WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed);
    let front: number | undefined;
    let sum = 0;
    let n = 0;
    const kind = timing.team === undefined || timing.team === GetTeam() ? UnitType.AlliedCreeps : UnitType.EnemyCreeps;
    for (const c of GetUnitList(kind) ?? []) {
        if (c === null || c === undefined || !c.IsAlive() || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        const [along, off] = Along(timing.lanePath, c.GetLocation());
        if (off > cfg.LiveMaxOffset || math.abs(along - expected) > window) continue;
        if (front === undefined || along > front) front = along;
        sum += along;
        n += 1;
    }
    if (front === undefined) return undefined;
    const clamp = (d: number) => math.max(-cfg.LiveMaxShift, math.min(cfg.LiveMaxShift, (expected - d) / WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed)));
    return { shift: clamp(sum / n), front: clamp(front) };
}

/**
 * Each creep of the timed wave by its distance along the lane path, front first: the timing team's lane creeps within
 * LiveWindow of where the wave should be at `now` for a hit at `aggroAt`, as LiveRead reads them, without its stop at the
 * meet point. Empty without a wave model.
 */
export function WaveAlongs(timing: PullTiming, aggroAt: number, now: number): number[] {
    const out: number[] = [];
    if (timing.source !== "wave" || timing.waveAfter === undefined || timing.waveTravel === undefined || timing.lanePath === undefined) return out;
    const cfg = settings();
    const v = WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed);
    const spawnAt = aggroAt + timing.waveAfter - timing.waveTravel;
    const expected = (now - spawnAt + (timing.ahead ?? 0)) * v;
    const window = cfg.LiveWindow * v;
    const kind = timing.team === undefined || timing.team === GetTeam() ? UnitType.AlliedCreeps : UnitType.EnemyCreeps;
    for (const c of GetUnitList(kind) ?? []) {
        if (c === null || c === undefined || !c.IsAlive() || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        const [along, off] = Along(timing.lanePath, c.GetLocation());
        if (off <= cfg.LiveMaxOffset && math.abs(along - expected) <= window) out.push(along);
    }
    out.sort((a, b) => b - a);
    return out;
}

export function LiveShift(timing: PullTiming, aggroAt: number, now: number): number | undefined {
    return LiveRead(timing, aggroAt, now)?.shift;
}

/**
 * A full pull's hit second timed on its wave's creeps (user 07/11/2026: one simple timing): the hit goes out so the
 * neutrals, walking `timing.walk` from the hit, reach the meet point just as the wave's front creep is `past` beyond it
 * along the lane, from every creep's position at lane creep speed. The puller leads as soon as its hit is confirmed (a
 * ranged hero once its attack goes out, a melee one as it lands), so only the neutrals' walk needs timing. Read every
 * LiveEvery s up to the order; the plan's slot stands until the front creep and one behind it are read. Any puller and
 * either team's wave: it reads only the timing it is given.
 */
export interface CreepTimer {
    timing: PullTiming;
    slot: number;
    past: number;
    /** At the last read: the hit second, when the back creep reaches the meet point, the creeps read, and on that hit the
     *  predicted distance past the meet point at the neutrals' arrival of the second creep (`next`) and of the back one
     *  (`back`; negative: short of it). */
    hit?: number;
    waveAt?: number;
    n: number;
    next?: number;
    back?: number;
    /** The first creep-timed hit's shift from the slot. */
    first?: number;
    readAt?: number;
    reads: number;
}

export function Timer(timing: PullTiming, slot: number, past: number): CreepTimer {
    return { timing, slot, past, n: 0, reads: 0 };
}

/** Reads the wave if LiveEvery has passed since the last read; returns the hit second (the slot until one is timed). */
export function Read(c: CreepTimer, now: number): number {
    const t = c.timing;
    const meet = t.meetAlong;
    if ((c.readAt === undefined || now - c.readAt >= settings().LiveEvery) && meet !== undefined && t.walk !== undefined) {
        c.readAt = now;
        // The neutrals' speed is read again at every read up to the order (user 08/11/2026): a camp in view is re-fed each
        // second, so the walk uses the pack standing there now, not the previous respawn's mix the plan was made on.
        if (t.walkLen !== undefined && t.type !== undefined && t.seedSpeed !== undefined) {
            const sp = WorldFacts.NeutralSpeedFor(t.type, t.seedSpeed, t.campIdx);
            t.neutralSpeed = sp;
            t.walk = t.walkLen / sp;
        }
        const walk = t.walk as number;
        const alongs = WaveAlongs(t, c.slot, now);
        c.n = alongs.length;
        if (alongs.length >= 2) {
            const v = WorldFacts.Latest("lane_creep_speed", settings().CreepSpeed);
            const hit = now + (meet + c.past - alongs[0]) / v - walk;
            const pastAt = (along: number) => math.floor(along + v * (hit + walk - now) - meet + 0.5);
            c.hit = hit;
            c.waveAt = now + (meet - alongs[alongs.length - 1]) / v;
            c.next = pastAt(alongs[1]);
            c.back = pastAt(alongs[alongs.length - 1]);
            c.reads += 1;
            if (c.first === undefined) c.first = hit - c.slot;
        }
    }
    return c.hit ?? c.slot;
}

/** When the wave's back creep reaches the meet point: from the last read (none after the order goes out, so the logged
 *  read is the one the hit went on), else the plan's. */
export function WaveAt(c: CreepTimer): number | undefined {
    if (c.waveAt !== undefined) return c.waveAt;
    return c.timing.waveAfter !== undefined ? c.slot + c.timing.waveAfter : undefined;
}
