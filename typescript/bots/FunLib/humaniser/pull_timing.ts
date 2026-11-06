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
    /** Seconds the neutrals take from the hit to the meet point (the lead path at NeutralSpeed). */
    walk?: number;
    /** The neutrals' walk: from the camp origin along the lead path at NeutralSpeed (a half pull's clearance search). */
    origin?: Vector;
    leadPath?: Vector[];
    neutralSpeed?: number;
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
export function For(team: number, lane: Lane | undefined, origin: Vector | undefined, type: Camps.CampType, leadPath: Vector[], half: boolean, seed: number[], campIdx?: number): PullTiming {
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
    // A half pull is timed as a full pull to its own (later) meet point, then HalfPullLater later, as the seeds were.
    const walk = WalkLength(origin, leadPath) / neutralSpeed;
    const waveAfter = walk + cfg.Lead - (half ? t.HalfPullLater : 0);
    const seconds = (cfg.WaveSlots as number[]).map((slot) => normalise(slot + waveTravel - waveAfter, t.PullPeriod));
    seconds.sort((a, b) => a - b);
    return { seconds, source: "wave", waveAfter, waveTravel, meetAlong, lanePath: path, ahead, team, walk, origin, leadPath, neutralSpeed };
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

/** The data table's pull seconds; a half pull without its own is HalfPullLater after the full pull. */
export function SeedSeconds(pull: Camps.PullData, half: boolean): number[] {
    if (!half) return pull.aggroSec;
    if (pull.halfAggroSec !== undefined) return pull.halfAggroSec;
    const later = LaneConfig.Settings().Timing.HalfPullLater;
    return pull.aggroSec.map((s) => s + later);
}

/**
 * `data`'s pull seconds: from its team's wave reaching `meet` (default the pull's own meet point, or the half one) for
 * seed camps, else the data table's, since replay and measured seconds are measurements.
 */
export function ForCamp(data: Camps.CampJobData, half: boolean, meet?: Vector): PullTiming {
    if (data.pull === undefined) return { seconds: [], source: "seed" };
    const seed = SeedSeconds(data.pull, half);
    const spawner = Camps.SpawnerByIdx(data.campIdx);
    if (data.source !== "seed" || spawner === undefined) return { seconds: seed, source: "seed" };
    const target = meet ?? (half ? data.pull.halfMeetPoint ?? data.pull.meetPoint : data.pull.meetPoint);
    return For(data.team, data.lane, spawner.location, data.type, LeadPath(data.pull, target), half, seed, data.campIdx);
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
    const spawnAt = aggroAt + timing.waveAfter - timing.waveTravel;
    const expected = (now - spawnAt + (timing.ahead ?? 0)) * WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed);
    const window = cfg.LiveWindow * WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed);
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
 * A pull's hit second timed on its wave's creeps (slice pull-half, user 05/11/2026): the hit goes out so the neutrals, walking
 * `timing.walk` from the hit, reach the meet point just as the wave's creep `index` from the front (0 the front one) is `past`
 * beyond it along the lane, from every creep's position at CreepSpeed. A full pull aims its front creep. A half pull
 * (`keep` 2) takes that as the centre of a search: each candidate hit walks the neutrals along the lead path against every
 * creep's path, and the hit kept is the one where the front `keep` creeps stay farthest outside HalfAcquire of them while
 * the next one still comes inside it (phchk1: the second creep aimed 500 past turned the whole wave on camp 1, whose
 * neutrals walk towards the front creeps). Read every LiveEvery s from the leave time to the order; the plan's slot stands
 * until the aimed creep and one behind it (a half pull: every creep up to the first meant to turn) are read. Any puller and
 * either team's wave: it reads only the timing it is given.
 */
export interface CreepTimer {
    timing: PullTiming;
    slot: number;
    index: number;
    past: number;
    /** Front creeps meant to walk on (0: a full pull). */
    keep: number;
    /** The puller's move speed: it walks the lead path ahead of the neutrals and stands at the meet point (half pulls). */
    heroSpeed?: number;
    /** At the last read: the hit second, when the back creep reaches the meet point, the creeps read, and on that hit the
     *  predicted distance past the meet point at the neutrals' arrival of the creep after the aimed one (`next`) and of the
     *  back one (`back`; negative: short of it). */
    hit?: number;
    waveAt?: number;
    n: number;
    next?: number;
    back?: number;
    /** A half pull's search on that hit: the nearest the kept creeps come to an aggro source, the neutrals or the hit
     *  puller (`clear`), the nearest the first creep meant to turn comes (`turn`), and `margin`, the smaller of clear -
     *  HalfAcquire and HalfAcquire - turn (negative: no hit in the search keeps the front creeps out and turns the next one). */
    clear?: number;
    turn?: number;
    margin?: number;
    /** The search's stand point for the puller (the lead's end), `standBack` short of the meet point. */
    standBack?: number;
    stand?: Vector;
    /** The first creep-timed hit's shift from the slot. */
    first?: number;
    readAt?: number;
    reads: number;
}

export function Timer(timing: PullTiming, slot: number, index: number, past: number, keep = 0, heroSpeed?: number): CreepTimer {
    return { timing, slot, index, past, keep, heroSpeed, n: 0, reads: 0 };
}

/** The point `along` down `path` (clamped to its ends). */
function PathPoint(path: number[][], along: number): [number, number] {
    let acc = 0;
    for (let i = 0; i + 1 < path.length; i++) {
        const [ax, ay] = path[i];
        const [bx, by] = path[i + 1];
        const len = hypot(ax, ay, bx, by);
        if (along <= acc + len || i + 2 === path.length) {
            const f = len > 0 ? math.max(0, math.min(1, (along - acc) / len)) : 0;
            return [ax + (bx - ax) * f, ay + (by - ay) * f];
        }
        acc += len;
    }
    return [path[0][0], path[0][1]];
}

/** Where a walker of the lead path is `s` seconds after the hit: down it from the origin, then at the meet point. */
function NeutralAt(origin: Vector, lead: Vector[], speed: number, s: number): [number, number] {
    let left = math.max(0, s) * speed;
    let px = origin.x;
    let py = origin.y;
    for (const p of lead) {
        const len = hypot(px, py, p.x, p.y);
        if (left <= len) {
            const f = len > 0 ? left / len : 0;
            return [px + (p.x - px) * f, py + (p.y - py) * f];
        }
        left -= len;
        px = p.x;
        py = p.y;
    }
    return [px, py];
}

/** `lead` with its last point moved `back` towards the point before it (the origin for a one-point lead). */
function Shorten(origin: Vector, lead: Vector[], back: number): Vector[] {
    if (back <= 0 || lead.length === 0) return lead;
    const end = lead[lead.length - 1];
    const prev = lead.length > 1 ? lead[lead.length - 2] : origin;
    const len = hypot(prev.x, prev.y, end.x, end.y);
    if (len <= 0) return lead;
    const f = math.max(0, len - back) / len;
    const out = lead.slice(0, lead.length - 1);
    out.push(Vector(prev.x + (end.x - prev.x) * f, prev.y + (end.y - prev.y) * f, end.z));
    return out;
}

export interface Clear {
    hit: number;
    clear: number;
    turn: number;
    margin: number;
    /** How far short of the meet point the puller stands (HalfStandBack), and that point. */
    back: number;
    stand: Vector;
}

/**
 * A half pull's hit and stand point from `centre`: candidate hits every HalfStep over HalfSearch around it (none before
 * `now`), each with the puller standing HalfStandBack short of the meet point on the lead's last leg. The puller starts
 * HalfHeroStart down the lead path at the hit (it hits from range) and walks it at `heroSpeed` to the stand point; the
 * neutrals leave the origin HalfNeutralDelay after the hit (the phchk2 replays: 0.4-2.3 s, camp 1 0.6-1.4) and follow it
 * there at NeutralSpeed, stopping where the first creep from `keep` back comes within HalfAcquire (the fight). A lane creep
 * turns within HalfAcquire of the neutrals or HalfHeroAggro of the puller they are hitting (EC-090: no written rule; in the
 * replays all four turned at 6:23 in A_on_4 with the neutrals 970-1025 off and the puller 280-390), the puller counted from
 * the hit on. Keeps the candidate with the largest margin (CreepTimer `margin`).
 */
function Clearance(t: PullTiming, alongs: number[], keep: number, now: number, centre: number, heroSpeed: number | undefined): Clear | undefined {
    const cfg = settings();
    const path = t.lanePath;
    const origin = t.origin;
    const lead = t.leadPath;
    const speed = t.neutralSpeed;
    const walk = t.walk;
    if (path === undefined || origin === undefined || lead === undefined || speed === undefined || walk === undefined) return undefined;
    const step = cfg.HalfStep;
    const r = WorldFacts.Latest("acquisition_lane_creep", cfg.HalfAcquire);
    const rh = cfg.HalfHeroAggro;
    const v = WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed);
    const [lo, hi] = cfg.HalfSearch;
    const first = math.max(0, math.ceil((centre + lo - now) / step));
    const last = math.floor((centre + hi - now) / step);
    if (last < first) return undefined;
    const delay = cfg.HalfNeutralDelay;
    const span = math.ceil((walk + delay + cfg.HalfHold) / step);
    // Creep positions on the shared grid now + i * step.
    const creeps: [number, number][][] = [];
    for (let k = 0; k < alongs.length; k++) {
        const row: [number, number][] = [];
        for (let i = 0; i <= last + span; i++) row.push(PathPoint(path, alongs[k] + v * i * step));
        creeps.push(row);
    }
    const hs = heroSpeed !== undefined && heroSpeed > 0 ? heroSpeed : undefined;
    let best: Clear | undefined;
    for (const back of cfg.HalfStandBack) {
        const route = Shorten(origin, lead, back);
        // Neutrals and puller at j steps after a hit.
        const walked: [number, number][] = [];
        const hero: [number, number][] = [];
        for (let j = 0; j <= span; j++) {
            walked.push(NeutralAt(origin, route, speed, j * step - delay));
            if (hs !== undefined) hero.push(NeutralAt(origin, route, hs, cfg.HalfHeroStart / hs + j * step));
        }
        for (let h = first; h <= last; h++) {
            let clear = math.huge;
            let turn = math.huge;
            let stop: [number, number] | undefined;
            for (let j = 0; j <= span; j++) {
                const [nx, ny] = stop ?? walked[j];
                const hit = hs !== undefined && hypot(nx, ny, hero[j][0], hero[j][1]) <= cfg.HalfHitReach;
                let fight = false;
                for (let k = 0; k < creeps.length; k++) {
                    const [cx, cy] = creeps[k][h + j];
                    const d = hypot(nx, ny, cx, cy);
                    // The nearer source in HalfAcquire's frame (a creep HalfHeroAggro from the puller counts as HalfAcquire). For
                    // the front creeps the puller counts throughout (it may be hit at any time); for the one meant to turn only
                    // while the neutrals are in HalfHitReach of it (phhar2: camp 26's hits had the third creep pass the unhit
                    // puller on the lane with the neutrals 600-700 behind it, and nothing turned).
                    const dh = hs !== undefined ? hypot(hero[j][0], hero[j][1], cx, cy) - rh + r : math.huge;
                    if (k < keep) clear = math.min(clear, math.min(d, dh));
                    else {
                        if (k === keep) turn = math.min(turn, hit ? math.min(d, dh) : d);
                        if (d <= r) fight = true;
                    }
                }
                if (fight && stop === undefined) stop = [nx, ny];
            }
            const margin = math.min(clear - r, r - turn);
            if (best === undefined || margin > best.margin)
                best = {
                    hit: now + h * step,
                    clear: math.floor(clear + 0.5),
                    turn: math.floor(turn + 0.5),
                    margin: math.floor(margin + 0.5),
                    back,
                    stand: route[route.length - 1],
                };
        }
    }
    return best;
}

/**
 * Where a stepping-in half pull's lead ends: back from `stand` towards `origin` (at least HalfStepBack) until HalfHoldOff
 * from the lane path, so the wave walks past out of reach of the puller and the neutrals hitting it (phhar4: 300 behind a
 * meet point on the lane, camp 1 took the whole wave 5 of 5 while the puller waited). At most the origin.
 */
export function StepBackPoint(origin: Vector, stand: Vector, path: number[][] | undefined): Vector {
    const cfg = settings();
    const ox = stand.x - origin.x;
    const oy = stand.y - origin.y;
    const ol = math.max(1, math.sqrt(ox * ox + oy * oy));
    let b = math.min(cfg.HalfStepBack, ol);
    const at = (d: number) => Vector(stand.x - (ox / ol) * d, stand.y - (oy / ol) * d, stand.z);
    if (path !== undefined) while (b < ol && Along(path, at(b))[1] < cfg.HalfHoldOff) b = math.min(ol, b + 50);
    return at(b);
}

/**
 * A half pull's live step-in (user 05/11/2026: walk-cancel towards the wave and time it): the lead ends HalfStepBack behind
 * `stand` (StepBackPoint), and during the watch the puller, its neutrals following, stands at the point on the line from
 * there through `stand` to the lane at the meet point that is nearest the lane while every front creep, now and
 * HalfStepAhead s on, stays more than HalfHeroAggro + HalfStepBuffer from it; none clear: the back end. Once `engaged` (a
 * creep of the wave on a neutral) it stays at `at`. The hit's timing error (the neutrals' start 0.4-2.1 s after the hit,
 * phchk3) is far above the search's margins (10-38); the lane end lets an off-lane meet point (camp 26: the puller 515-830
 * from the wave in phchk3, nothing taken) still reach the wave.
 */
export function StepIn(c: CreepTimer, origin: Vector, stand: Vector, meet: Vector, now: number, engaged: boolean, at: Vector, neutrals?: Vector[], ranged = false): Vector {
    if (engaged) return at;
    const cfg = settings();
    const t = c.timing;
    const path = t.lanePath;
    if (path === undefined) return stand;
    if (t.meetAlong !== undefined) {
        const [lx, ly] = PathPoint(path, t.meetAlong);
        meet = Vector(lx, ly, meet.z);
    }
    const alongs = WaveAlongs(t, c.slot, now);
    if (alongs.length < c.keep + 1) return stand;
    const fronts: [number, number][] = [];
    for (let k = 0; k < c.keep; k++) {
        fronts.push(PathPoint(path, alongs[k]));
        fronts.push(PathPoint(path, alongs[k] + WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed) * cfg.HalfStepAhead));
    }
    const back = StepBackPoint(origin, stand, path);
    const len = math.max(1, hypot(back.x, back.y, meet.x, meet.y));
    // What turns a creep is a neutral within HalfAcquire of it (the harness phhar5/phhar7: no creep turned on one farther
    // out, hit puller or not), so with the neutrals known their places, moved with the puller, are what must stay clear;
    // with none known the puller stands for them at HalfHeroAggro.
    const offs = neutrals !== undefined && neutrals.length > 0 ? neutrals : undefined;
    const reach = (offs !== undefined ? WorldFacts.Latest("acquisition_lane_creep", cfg.HalfAcquire) : cfg.HalfHeroAggro) + cfg.HalfStepBuffer;
    // With ranged neutrals known the line runs on HalfStepOver past the meet point, so neutrals that trail the puller can
    // still be brought to the lane; the far side is open only once the front creeps are clear of the crossing. Melee
    // neutrals close to 100-250 and need no crossing: with it they followed the puller on to the lane and took the
    // whole wave (phhar9 camp 1, 2 of 2).
    const ux = (meet.x - back.x) / len;
    const uy = (meet.y - back.y) / len;
    let crossClear = offs !== undefined && ranged;
    if (crossClear) for (const [fx, fy] of fronts) if (hypot(meet.x, meet.y, fx, fy) <= reach) crossClear = false;
    const full = len + (crossClear ? cfg.HalfStepOver : 0);
    const n = math.max(1, math.ceil(full / 50));
    const pins = cfg.HalfStand;
    const pin = pins.length > 0 ? pins[math.floor(c.slot / 30) % pins.length] : 0;
    for (let i = n; i >= 0; i--) {
        const x = back.x + ux * ((full * i) / n);
        const y = back.y + uy * ((full * i) / n);
        // The harness pin: the nearest point of the line to the lane that is still HalfStand off it, whatever the wave does.
        if (pin > 0) {
            if (Along(path, Vector(x, y, stand.z))[1] >= pin) return Vector(x, y, stand.z);
            continue;
        }
        let clear = true;
        if (offs !== undefined) {
            for (const o of offs) for (const [fx, fy] of fronts) if (hypot(x + o.x, y + o.y, fx, fy) <= reach) clear = false;
        } else {
            for (const [fx, fy] of fronts) if (hypot(x, y, fx, fy) <= reach) clear = false;
        }
        if (clear) return Vector(x, y, stand.z);
    }
    return back;
}

/** Reads the wave if LiveEvery has passed since the last read; returns the hit second (the slot until one is timed). */
export function Read(c: CreepTimer, now: number): number {
    const t = c.timing;
    const meet = t.meetAlong;
    const walk = t.walk;
    if ((c.readAt === undefined || now - c.readAt >= settings().LiveEvery) && meet !== undefined && walk !== undefined) {
        c.readAt = now;
        const alongs = WaveAlongs(t, c.slot, now);
        c.n = alongs.length;
        if (alongs.length >= math.max(c.index, c.keep) + 2) {
            const v = WorldFacts.Latest("lane_creep_speed", settings().CreepSpeed);
            let hit = now + (meet + c.past - alongs[c.index]) / v - walk;
            if (c.keep > 0 && settings().HalfStepIn === true) {
                // With the live step-in the hit only has to bring the neutrals to the back point in time: early costs a wait
                // off the lane, late loses the wave (phhar2 camp 26: the wave 450-730 past at their arrival, nothing taken).
                hit -= settings().HalfNeutralDelay + settings().HalfStepEarly;
            } else if (c.keep > 0) {
                const s = Clearance(t, alongs, c.keep, now, hit, c.heroSpeed);
                if (s !== undefined) {
                    hit = s.hit;
                    c.clear = s.clear;
                    c.turn = s.turn;
                    c.margin = s.margin;
                    c.standBack = s.back;
                    c.stand = s.stand;
                }
            }
            const pastAt = (along: number) => math.floor(along + v * (hit + walk - now) - meet + 0.5);
            c.hit = hit;
            c.waveAt = now + (meet - alongs[alongs.length - 1]) / v;
            c.next = pastAt(alongs[c.index + 1]);
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
