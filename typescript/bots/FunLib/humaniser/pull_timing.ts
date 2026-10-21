/**
 * Pull aggro timing from wave arrival (task 07). Our wave spawns at :00/:30 at its lane's melee spawner and walks
 * the lane's path_corner chain at lane-creep speed; the aggro second is its arrival at the camp's meet point minus
 * the neutrals' walk from the spawner origin along the lead path, minus a lead so the neutrals are there first.
 * Camps whose meet point is not on our lane's chain (another map, a moved camp) keep their data-table seconds.
 */
import { Lane, Team, UnitType, Vector } from "bots/ts_libs/dota";
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

function walkLength(from: Vector, path: Vector[]): number {
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
export function For(team: number, lane: Lane | undefined, origin: Vector | undefined, type: Camps.CampType, leadPath: Vector[], half: boolean, seed: number[]): PullTiming {
    const cfg = settings();
    const fallback: PullTiming = { seconds: seed, source: "seed" };
    const meet = leadPath[leadPath.length - 1];
    const neutralSpeed = (cfg.NeutralSpeed as Record<string, number>)[type];
    if (cfg.FromWave !== true || lane === undefined || origin === undefined || meet === undefined || neutralSpeed === undefined) return fallback;
    const path = LanePath(team, lane);
    if (path === undefined || path.length < 2) return fallback;
    const [meetAlong, off] = Along(path, meet);
    if (off > cfg.PathMaxOffset) return fallback;
    const t = LaneConfig.Settings().Timing;
    const waveTravel = meetAlong / cfg.CreepSpeed;
    // A half pull is timed as a full pull to its own (later) meet point, then HalfPullLater later, as the seeds were.
    const waveAfter = walkLength(origin, leadPath) / neutralSpeed + cfg.Lead - (half ? t.HalfPullLater : 0);
    const seconds = (cfg.WaveSlots as number[]).map((slot) => normalise(slot + waveTravel - waveAfter, t.PullPeriod));
    seconds.sort((a, b) => a - b);
    return { seconds, source: "wave", waveAfter, waveTravel, meetAlong, lanePath: path };
}

/**
 * Live correction for a wave-timed pull at `aggroAt` (no jitter): once its wave has left the barracks, the lead creep
 * of our lane creeps within LiveWindow of where the wave should be says how early or late it really is. 7.41 speeds
 * safe-lane waves up and slows off-lane ones for a few seconds after spawn (patch notes, no figure given), and a wave
 * can be blocked or held up on the way. Returns the shift in seconds, or undefined when nothing reliable is seen.
 */
export function LiveShift(timing: PullTiming, aggroAt: number, now: number): number | undefined {
    if (timing.source !== "wave" || timing.waveAfter === undefined || timing.waveTravel === undefined || timing.meetAlong === undefined || timing.lanePath === undefined)
        return undefined;
    const cfg = settings();
    const spawnAt = aggroAt + timing.waveAfter - timing.waveTravel;
    if (now < spawnAt + cfg.LiveFrom) return undefined;
    const expected = (now - spawnAt) * cfg.CreepSpeed;
    if (expected >= timing.meetAlong) return undefined;
    const window = cfg.LiveWindow * cfg.CreepSpeed;
    let lead: number | undefined;
    for (const c of GetUnitList(UnitType.AlliedCreeps) ?? []) {
        if (c === null || c === undefined || !c.IsAlive() || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        const [along, off] = Along(timing.lanePath, c.GetLocation());
        if (off > cfg.LiveMaxOffset || math.abs(along - expected) > window) continue;
        if (lead === undefined || along > lead) lead = along;
    }
    if (lead === undefined) return undefined;
    const shift = (expected - lead) / cfg.CreepSpeed;
    return math.max(-cfg.LiveMaxShift, math.min(cfg.LiveMaxShift, shift));
}
