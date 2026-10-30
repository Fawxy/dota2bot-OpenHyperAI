/**
 * Stack execution (slice 4, switch Ours.StackExecute, KR S.2a): on a placeholder trigger (minutes 3, 5 and 7) the
 * pos5 stacks its nearest own-side camp with the `stack` job verb, then watches the box for the outcome. OHA has no
 * stacking code; with the switch off the pos5 never stacks. Hosted by mode_farm_generic (Desire, Think, Abort).
 * One `ev=stack` line per trigger minute: the attempt's result, or `res=skip` with the reason no job started.
 * When to stack, and who, is S.2b: it replaces TRIGGER_MINUTES and keeps the job and its result line.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Team, Unit, Vector } from "bots/ts_libs/dota";
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");
import * as Camps from "bots/FunLib/humaniser/camps";
import * as CampJobs from "bots/FunLib/humaniser/camp_jobs";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Stacking from "bots/FunLib/humaniser/stacking";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

// All judgement (slice 4 work order); the trigger is a placeholder for S.2b.
export const SETTINGS = {
    /** Game-clock minutes whose stack second (x:52-x:57) gets an attempt: 3:5x, 5:5x, 7:5x. */
    TriggerMinutes: [3, 5, 7],
    /** Second of the trigger minute from which the trigger looks (a far camp starts early). */
    LookFrom: 15,
    /** Seconds of slack on the straight-line walk to the stand point. 5 (probe 4: the path ran ~6 s over) was not enough for
     *  omniknight from the Dire safe lane to evil_1: started at x:40-x:46, it never reached the stand (no `arr` in 9 of 10
     *  attempts), swung on the way in from 70-180 inside the camp and stacked 0 of 10 (s4solo3). Witch doctor on good_2
     *  reached its stand ~4 s early. 9 gives the long walks time to arrive and wait. */
    Lead: 9,
    /** A start held back by the gate goes ahead only with this much slack left: starts at 0 s slack reached the stand point at
     *  :54 and missed the window (probe s4p5, 5:5x on good_1 and evil_1). */
    MinSlack: 3,
    /** Seconds before the hit the job steps in towards an unseen camp. */
    ApproachLead: 6,
    /** Distance from the camp origin the job steps in to when it sees nothing from the stand point. */
    ApproachDist: 250,
    MinHpFraction: 0.5,
    /** Lane opponents stand 450-1,200 from a laning pos5 (s4 validation game): only one in reach blocks the start. */
    EnemyRadius: 600,
    HitWithin: 3,
    /** Above OHA's ward (0.83) and laning, below a serious retreat (0.94-1.1); s4 validation game. */
    Desire: 0.92,
    /** Seconds without a step before the job counts as stalled. Farm's Think skips the step while the bot cannot act; the
     *  engine's default 2 ended 3 good_2 attempts after the hit (`preempted:stalled`, s4solo5; the camp's centaur khan
     *  stuns). */
    StallAfter: 4,
    /** Seconds in another mode before the job counts as preempted. */
    PreemptAfter: 1,
    /** Stand and walk off on the camp's lane side, not away from the lane (user replay review, 30/10/2026: these camps pull
     *  more easily towards the lane). Away from the lane, every evil_1 hit by lich and omniknight came from 80-185 inside the
     *  camp, unseen from the stand point (s4solo4, s4solo4a: 0 of 15). */
    ExitTowardLane: true,
    /** The watch for the outcome ends this long after the next minute's :00 spawn check. */
    WatchUntil: 5,
    /** A job may not start more than this many seconds before its latest end (:00 + WatchUntil): KR S.2's 25 s away. The
     *  walk and Lead come before the hit and the watch after it is fixed, so a far camp cannot fit: s4 A_on_4 3:31, lich
     *  from out of lane to camp 23 (a 14.6 s walk), away 30.7. Such a minute is skipped as `far`. */
    AwayMax: 25,
    /** Seconds after :00 a stacked camp is usually seen and the watch ends (s4: :02-:04). The far rule plans with it, not
     *  the worst case (:00 + WatchUntil, which skipped a 23 s job at 3:39 in s4r2); the watch is cut at AwayMax instead. */
    FarEnd: 3,
    /** Seconds kept spare on the walk from A to B's hit (the order goes out the hit's lead early); judgement. */
    DoubleSlack: 0.5,
    /** A double's start slack instead of Lead (9): the walk to camp A from the safe-lane T1 is ~8 s for good_2, and with
     *  Lead the job would run ~27.5 s, over AwayMax (E1, 31/10/2026). A double that still cannot fit runs single. */
    DoubleLead: 5,
    /** A double's watch end after :00: camp A's origin is ~1,100-1,600 from B's stand, so A was read in time only after
     *  a quick B stack, and was unread in most of dsolo4b-5c (31/10/2026). AwayMax still cuts it. */
    DoubleWatchUntil: 8,
    /** Seconds B's box is read without a fresh neutral before the watch walks to A (a stacked B is usually seen by :02-:04). */
    BReadFor: 2,
    /** A double's waits keep this far from the camp's nearest visible neutral (the verb's `waitClear`): Dota's hero
     *  acquisition range is about 800 (judgement, to be confirmed by `fauto`); warlock and lich lost 25-40% HP at the
     *  shrine pair's camp A from their arrival at :48-:49, 3 s before the hit (dsolo4b, dsolo4c; user replay review). */
    WaitClear: 850,
};

// Test harness for the slice 4 diagnosis (user 30/10/2026), off by default: Customize.Overrides.Solo = <pid> benches the
// other nine heroes in their fountain, so one pos5 stacks with no lane opponents or fights around it, and
// Overrides.StackEvery = true tries every minute from 2:00 instead of TriggerMinutes. Overrides.StackFar = true lifts the
// AwayMax skip and watch cut (slice double-stack, user 31/10/2026: test execution apart from getting there; the pos4 lanes
// 12-17 s from its pairs). Scenario games only, never a verdict.
const FOUNTAIN: Record<number, [number, number, number]> = { [Team.Radiant]: [-6619, -6336, 384], [Team.Dire]: [6928, 6372, 392] };

function override(key: string): unknown {
    return (Customize as any).Overrides?.[key];
}

/** Overrides.Solo names another hero: this one sits out the game in its fountain. */
export function Benched(bot: Unit): boolean {
    const solo = override("Solo");
    return typeof solo === "number" && solo >= 0 && bot.GetPlayerID() !== solo;
}

/** mode_farm_generic Think for a benched hero: walk to the fountain and stay. False when the hero is not benched. */
export function Bench(bot: Unit): boolean {
    if (!Benched(bot)) return false;
    const [x, y, z] = FOUNTAIN[bot.GetTeam()];
    const f = Vector(x, y, z);
    if (GetUnitToLocationDistance(bot, f) > 300) bot.Action_MoveToLocation(f);
    return true;
}

/** AwayMax, or no limit with Overrides.StackFar (scenario games only). */
function awayMax(): number {
    return override("StackFar") === true ? math.huge : SETTINGS.AwayMax;
}

/** The minutes with an attempt: TriggerMinutes, or every minute from 2 with Overrides.StackEvery. */
export function Minutes(): number[] {
    if (override("StackEvery") !== true) return SETTINGS.TriggerMinutes;
    const out: number[] = [];
    for (let m = 2; m <= 60; m++) out.push(m);
    return out;
}

export interface Attempt {
    minute: number;
    campIdx: number;
    type: string;
    startedAt: number;
    before?: number;
    aggro?: number;
    after?: number;
    /** At the end: visible neutrals within `NeutralSearch` of the bot, those inside the box, and the bot's distance to the origin. */
    near?: number;
    inbox?: number;
    dist?: number;
    vis?: number;
    /** Sampled once at the spawn check (:59.5): visible neutrals still in the box, neutrals near the bot outside it
     *  (the pulled camp), the bot inside the box (1/0), the origin visible (1/0), the bot's distance to the exit point. */
    box59?: number;
    pulled59?: number;
    bot59?: number;
    vis59?: number;
    exit59?: number;
    /** The neutral the hit landed on (not logged), the bot's distance to the origin at the hit, the neutral's distance to
     *  the origin 2 s after the hit and at :59.5 ("?" when unseen or dead), and visible neutrals in the bare box at :59.5
     *  (Valve's spawn check has no margin). */
    target?: Unit;
    hitd?: number;
    tgt2?: number;
    tgt59?: number;
    strict59?: number;
    /** Seconds of the minute the verb reached the stand point (`wait`), gave the hit order (`aggro`) and walked off
     *  (`exit`); the bot's HP % at the hit order, the walk-off and :59.5 (user replay, s4solo1: the bots stood and tanked
     *  before walking off). */
    arr?: number;
    hit0?: number;
    /** The neutral the hit order went to and its HP then; the second it first lost HP (the hit landed) and the second a camp
     *  neutral first targeted the bot (the camp turned): s4 A_on_1's two `no-aggro` misses could not tell a hit that never
     *  landed from a camp slow to react. */
    aim?: Unit;
    aimHp?: number;
    dmg?: number;
    react?: number;
    exitAt?: number;
    hpa?: number;
    hpe?: number;
    hp59?: number;
    /** Spells the bot cast while the job ran, "name@second" (user replay, s4solo1: witch doctor's cask stunned the camp at
     *  3:5x and 4:5x and the large neutral walked back into the box; nothing in the log showed it). */
    casts?: string[];
    lastCast?: string;
    /** The camp's neutrals at the hit, and each one 2 s after the hit and at :59.5 as name:dist:in|out:a|- (distance to
     *  the origin, inside the bare box, attacking the bot); "name:?" unseen, "name:dead". */
    campUnits?: Unit[];
    /** Every neutral the bot saw from the start of the job until the :00 spawn check, and the most neutrals in the box after
     *  it that are not among them: the spawn. Counting the box alone graded returning neutrals as a stack (s4solo3 11:0x and
     *  12:0x: `after` rose by one with four neutrals inside the bare box at :59.5). */
    seen?: Set<Unit>;
    fresh?: number;
    n2?: string;
    n59?: string;
    /** The most lane creeps (either team) within LANE_NEAR of the camp's origin from the hit to the end of the watch: the
     *  walk-off dragged a wave into the camp, a partial pull (user watching s4solo7ab: evil_1's north-west route pulled the
     *  top lane twice; nothing in the log showed it). */
    lane?: number;
    /** OHA idle relocations the job held while it ran (`HoldsIdle`). */
    idle?: number;
    /** Double stack: 1 when the attempt hits `first` before this camp; 0 when the camp has a partner but the walk between
     *  them does not fit (`Fits`); undefined when it has none or the switch is off. */
    double?: number;
    /** Why a camp with a partner ran single: `walk` (A to B does not fit the gap), `far` (over AwayMax), `late`. */
    dwhy?: string;
    first?: FirstCamp;
}

/** Camp A of a double stack, hit before the attempt's own camp (B). */
export interface FirstCamp {
    campIdx: number;
    type: string;
    /** Its stand point and hit second, and camp B's hit second (the pair's). */
    stand: Vector;
    fsec: number;
    sec: number;
    aggro?: number;
    before?: number;
    hitd?: number;
    arr?: number;
    box59?: number;
    fresh?: number;
    /** A's neutrals at its hit: B's hit is picked and confirmed on other neutrals only. */
    units?: Unit[];
    /** A's neutrals 2 s after its hit and at :59.5 (as `n2`/`n59`), and 1 when A's box was in sight during the watch: in
     *  ds2, 3 doubles stacked B but read A's spawn as 0 and the log could not say where A's neutrals were. */
    n2?: string;
    n59?: string;
    seen?: number;
    /** The second of the minute A's box was first in sight at or after :00 + StackOutcomeAt; undefined: A was never read. */
    chk?: number;
    /** A's hit order second and HP % then, and the first second before it the bot's attack target was a neutral in A's
     *  box (an auto-attack while it waited). */
    hit0?: number;
    hpa?: number;
    auto?: number;
}

const handled: Record<number, Record<number, boolean>> = {};
const exits: Record<number, Vector[]> = {};

/**
 * Walk-off directions set by hand for camps the user described (30/10/2026, watching s4solo5): the safe-lane easy camps run
 * along the lane towards the corner where it turns, not into it. good_1 (Radiant, origin 3978,-5027): east; evil_2 (Dire,
 * -3911,4829): west, the mirror. evil_1 (Dire hard, -4824,3915): north; its derived lane-side stand lay south-west
 * behind trees, ~350 from the origin with the camp never seen (s4solo6a/6c, 13 of 13 `mistake:no-camp`; user 30/10/2026:
 * stand north or north-west). North-west sees the camp (15 of 22 stacked, s4solo7) but drags the top lane's wave into it,
 * a partial pull (user watching s4solo7ab); that route waits for the stack route choice row. evil_13 (Dire shrine pair's
 * camp B, 8430,1263): south, back towards the offlane and the secret shop; the derived lane-side walk-off ran north-west
 * towards mid, the harder of its two routes (user replay review of dsolo4b, 31/10/2026; both go to the route choice row).
 * Matched by spawner origin (7.41 map); other camps derive their walk-off.
 */
const EXIT_DIRS: { x: number; y: number; dx: number; dy: number }[] = [
    { x: 3978, y: -5027, dx: 1, dy: 0 },
    { x: -3911, y: 4829, dx: -1, dy: 0 },
    { x: -4824, y: 3915, dx: 0, dy: 1 },
    { x: 8430, y: 1263, dx: 0, dy: -1 },
];

function setExit(sp: Camps.Spawner): Vector[] | undefined {
    for (const e of EXIT_DIRS) {
        if (math.abs(sp.location.x - e.x) > 200 || math.abs(sp.location.y - e.y) > 200) continue;
        const away = LaneConfig.Settings().Radii.StackExit;
        const c = Camps.BoxCenter(sp);
        const target = Vector(c.x + e.dx * away, c.y + e.dy * away, c.z);
        return [Camps.BoxEdgePoint(sp, target, away) ?? target];
    }
    return undefined;
}

/** The walk-off after the hit: a hand-set direction (EXIT_DIRS), else the camp data's path, or one derived towards the
 *  lane (ExitTowardLane). */
export function ExitPath(sp: Camps.Spawner, data: Camps.CampJobData): Vector[] {
    if (exits[sp.idx] !== undefined) return exits[sp.idx];
    const set = setExit(sp);
    if (set !== undefined) exits[sp.idx] = set;
    else if (SETTINGS.ExitTowardLane) exits[sp.idx] = Camps.DeriveStackExit(sp, sp.team, true);
    else return data.stack!.exitPath;
    return exits[sp.idx];
}

/**
 * Double-stack pairs (EC-063, user lead 31/10/2026), matched by spawner origin as EXIT_DIRS: camp B (graded, the line's
 * own camp), camp A (hit first), the two hit seconds, the position that stacks it, and whether A's stand faces B.
 * The pos5's are its safe-lane camps (145 of 168 started slice 4 5v5 attempts); the pos4's lie on the offlane side: each
 * ancient camp and its neighbour, and the two camps by each wisdom shrine (the nearer of each pair to the offlane T1
 * first). Seconds (judgement): camp A early in its Valve window, at :53 at the latest (EC-063's guides: ":53, then
 * :55-:56"; A's neutrals chase the bot through B's hit, so A's own window may not bind), camp B late in its window.
 * The pos4's pairs fit only with A's stand facing B (E1, 31/10/2026); evil_8 then evil_9 still does not for a 550-range
 * hero (EC-063 rates it the weakest) and runs single with `dwhy=walk`.
 * Solo runs on f215060 (31/10/2026) moved them: the pos5's B was hit about 1 s after its planned second (the walk from A
 * after A's confirmed hit), and `good_1` stacked 0 of 8 hit after :56.4, so both pos5 pairs hit earlier; the shrine pairs'
 * A neutrals were back in A's box at :59 after a :52-:54 hit against A's own 55-56 window (0 of 22 stacked), and A's
 * stand facing B leaves a short walk, so A is hit as late as the walk to B allows there (54 and 53.5).
 */
interface Pair {
    x: number;
    y: number;
    fx: number;
    fy: number;
    fsec: number;
    sec: number;
    pos: number;
    face: boolean;
}
const PAIRS: Pair[] = [
    { x: 3978, y: -5027, fx: 4649, fy: -3699, fsec: 51.5, sec: 55.5, pos: 5, face: false }, // good_1 (55-57) after good_2 (52-54)
    { x: -3911, y: 4829, fx: -4824, fy: 3915, fsec: 54, sec: 56, pos: 5, face: false }, // evil_2 (55-57) after evil_1 (54-56)
    { x: -4013, y: 992, fx: -5015, fy: -96, fsec: 52.5, sec: 55, pos: 4, face: true }, // good_7 (53-55) after ancient good_8 (52-54)
    { x: -8023, y: -1838, fx: -8313, fy: -553, fsec: 54, sec: 55.75, pos: 4, face: true }, // good_16 after good_13 (both 55-56)
    { x: 3392, y: -1408, fx: 4352, fy: 48, fsec: 53, sec: 55, pos: 4, face: true }, // evil_9 after ancient evil_8 (both 53-55)
    { x: 8430, y: 1263, fx: 7928, fy: -120, fsec: 53.5, sec: 55.75, pos: 4, face: true }, // evil_13 after evil_7 (both 55-56)
];

/** A resolved pair: camps B and A, the hit seconds, and A's stand point. */
export interface Double {
    b: Camps.CampJobData;
    a: Camps.CampJobData;
    fsec: number;
    sec: number;
    stand: Vector;
}

function near(v: Vector, x: number, y: number): boolean {
    return math.abs(v.x - x) <= 200 && math.abs(v.y - y) <= 200;
}

function campAt(team: number, x: number, y: number): Camps.CampJobData | undefined {
    for (const s of Camps.Spawners()) {
        if (s.team !== team || !near(s.location, x, y) || Stacking.Window(s.idx)[0] === undefined) continue;
        const d = Camps.ByIdx(s.idx, s.team);
        if (d !== undefined && d.stack !== undefined) return d;
    }
    return undefined;
}

function resolvePair(p: Pair, team: number): Double | undefined {
    const b = campAt(team, p.x, p.y);
    const a = campAt(team, p.fx, p.fy);
    if (a === undefined || b === undefined) return undefined;
    const spa = Camps.SpawnerByIdx(a.campIdx)!;
    const stand = p.face ? Camps.StandPoint(spa, Camps.SpawnerByIdx(b.campIdx)!.location, LaneConfig.Settings().Radii.StandOffset) : Stand(spa, a);
    return { b, a, fsec: p.fsec, sec: p.sec, stand };
}

/** The pos5's pair for its nearest camp, which may be either camp of it: the pos5 stood nearer camp A (the large one) in
 *  14 of 20 started attempts (probe ds1), and the pair then never ran. */
export function Partner(data: Camps.CampJobData): Double | undefined {
    const sp = Camps.SpawnerByIdx(data.campIdx);
    if (sp === undefined) return undefined;
    for (const p of PAIRS) {
        if (p.pos === 5 && (near(sp.location, p.x, p.y) || near(sp.location, p.fx, p.fy))) return resolvePair(p, sp.team);
    }
    return undefined;
}

/** The pos4's pair in `minute`: its team's pairs in turn, so each gets tried (a placeholder like the trigger: S.2b). */
export function PairFor(team: number, minute: number): Double | undefined {
    const list: Double[] = [];
    for (const p of PAIRS) {
        const d = p.pos === 4 ? resolvePair(p, team) : undefined;
        if (d !== undefined) list.push(d);
    }
    return list.length > 0 ? list[math.floor(minute / 2) % list.length] : undefined;
}

/**
 * The walk from A's stand point to hitting B fits between the two hits: B's neutral is hit from attack range of its box,
 * so a ranged hero walks less than a melee one (EC-063's table: most pairs fit a ranged hero only).
 */
export function Fits(bot: Unit, d: Double): boolean {
    const spb = Camps.SpawnerByIdx(d.b.campIdx)!;
    const reach = bot.GetAttackRange() + (spb.max.x - spb.min.x) / 2;
    const walk = math.max(0, dist(d.stand, spb.location) - reach) / math.max(1, bot.GetCurrentMovementSpeed());
    return walk + SETTINGS.DoubleSlack <= d.sec - d.fsec;
}

/** Where the bot waits for the hit: StandOffset past the box edge, on the walk-off side. */
export function Stand(sp: Camps.Spawner, data: Camps.CampJobData): Vector {
    return Camps.StandPoint(sp, ExitPath(sp, data)[0], LaneConfig.Settings().Radii.StandOffset);
}
const gateWhy: Record<number, string | undefined> = {};
const running: Record<number, Attempt | undefined> = {};

export function ResetCache(): void {
    for (const k in handled) delete handled[k];
    for (const k in gateWhy) delete gateWhy[k];
    for (const k in running) delete running[k];
    for (const k in exits) delete exits[k];
}

/** The switch is on and `bot` is OHA position 5, or position 4 with Ours.DoubleStack (it stacks its pairs only). */
export function Applies(bot: Unit): boolean {
    if (!Ours.On("StackExecute")) return false;
    const pos = LaneConfig.PositionOf(bot);
    return pos === 5 || (pos === 4 && Ours.On("DoubleStack"));
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

/** Own-side, not ancient, with a Valve stack window: the camps this job may stack. */
export function Candidates(team: number): Camps.CampJobData[] {
    const out: Camps.CampJobData[] = [];
    for (const s of Camps.Spawners()) {
        if (s.team !== team || s.type === "ancient" || Stacking.Window(s.idx)[0] === undefined) continue;
        const data = Camps.ByIdx(s.idx, team);
        if (data !== undefined && data.stack !== undefined) out.push(data);
    }
    return out;
}

/** The candidate whose stand point is nearest `loc`, with that stand point. */
export function Nearest(team: number, loc: Vector): LuaMultiReturn<[Camps.CampJobData | undefined, Vector | undefined]> {
    let best: Camps.CampJobData | undefined;
    let stand: Vector | undefined;
    for (const data of Candidates(team)) {
        const sp = Camps.SpawnerByIdx(data.campIdx)!;
        const p = Stand(sp, data);
        if (stand === undefined || dist(loc, p) < dist(loc, stand)) {
            best = data;
            stand = p;
        }
    }
    return $multi(best, stand);
}

/** Hero damage just now, checked every frame of a running job (1x probe s4p7: the pos5 was hit at 61% on the walk, kept
 *  going and died at the camp to two heroes). Not an enemy hero in reach: lane opponents walk within 600 of a laning pos5,
 *  and that check ended 4 jobs 1-6 s after their start (probe s4p8). Not HP or mode: the camp's neutrals hit the bot by
 *  design, and the mode is ours. */
function Threat(bot: Unit): string | undefined {
    return bot.WasRecentlyDamagedByAnyHero(SETTINGS.HitWithin) ? "hit" : undefined;
}

/** Why the pos5 may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
 *  hero just now, or fighting or retreating. */
export function Gate(bot: Unit): string | undefined {
    if (bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MinHpFraction) return "low-hp";
    if ((bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length > 0) return "enemy-near";
    if (Threat(bot) !== undefined) return "hit";
    const mode = bot.GetActiveMode();
    if (mode === BotMode.Attack || mode === BotMode.Retreat) return "busy";
    return undefined;
}

/** The stack verb's plan for `data` in `minute`: the hit lands on the camp's stack second of that minute. */
/** The verb's camp for `sp`, waiting at `stand`; `others` are neutrals that are not this camp (a double's camp A). */
function campFor(bot: Unit, sp: Camps.Spawner, stand: Vector, others?: () => Unit[] | undefined): JobVerbs.Camp {
    const r = LaneConfig.Settings().Radii;
    // Seen nothing from the stand point (trees, high ground, night): step in to ApproachDist from the origin. Not camp_jobs'
    // StandApproach (150): hit from 84-124 the neutral had moved 57-72 two seconds later and stayed in the box; hits from
    // 389-450 drew it 300-600 out (probe s4p4). Lich saw evil_1 from 274 (probe 4). 250, not 300: witch doctor's evil_2
    // stand point is 383 from the origin, so 300 lay inside the arrive radius and the bot never stepped in (probe s4p5).
    const o = sp.location;
    const d = math.max(1, ((stand.x - o.x) ** 2 + (stand.y - o.y) ** 2) ** 0.5);
    const close = math.min(d, SETTINGS.ApproachDist);
    const approach = Vector(o.x + ((stand.x - o.x) * close) / d, o.y + ((stand.y - o.y) * close) / d, o.z);
    const camp: JobVerbs.Camp = {
        stand: stand as unknown as Lib.Vec,
        box: { min: sp.min as unknown as Lib.Vec, max: sp.max as unknown as Lib.Vec },
        origin: sp.location as unknown as Lib.Vec,
        margin: r.BoxMargin,
        search: r.NeutralSearch,
        confirmed: () => CampJobs.Exec.NeutralTargets(bot),
        approach: approach as unknown as Lib.Vec,
    };
    if (others === undefined) return camp;
    // Camp A's neutrals chase the bot to B: they target it and may stand in B's box margin, so B's hit and its proof skip them.
    const other = (n: Unit) => (others() ?? []).includes(n);
    camp.pick = () => {
        let best: Unit | undefined;
        for (const n of bot.GetNearbyNeutralCreeps(r.NeutralSearch, false) ?? []) {
            if (n === null || n === undefined || !n.IsAlive() || !n.CanBeSeen() || other(n) || !Camps.InBox(sp.idx, n.GetLocation(), r.BoxMargin)) continue;
            if (best === undefined || GetUnitToUnitDistance(bot, n) < GetUnitToUnitDistance(bot, best)) best = n;
        }
        return best as unknown as Lib.TaskAttacker | undefined;
    };
    camp.confirmed = () => {
        for (const n of bot.GetNearbyNeutralCreeps(r.NeutralSearch, false) ?? []) {
            if (n !== null && n !== undefined && n.IsAlive() && n.CanBeSeen() && !other(n) && n.GetAttackTarget() === bot) return true;
        }
        return false;
    };
    return camp;
}

export function Plan(bot: Unit, data: Camps.CampJobData, stand: Vector, minute: number, a: Attempt): JobVerbs.StackPlan {
    const sp = Camps.SpawnerByIdx(data.campIdx)!;
    const r = LaneConfig.Settings().Radii;
    const t = LaneConfig.Settings().Timing;
    const start = minute * 60;
    const f = a.first;
    const fd = f !== undefined ? Camps.ByIdx(f.campIdx) : undefined;
    const fsp = f !== undefined ? Camps.SpawnerByIdx(f.campIdx) : undefined;
    const first =
        f !== undefined && fd !== undefined && fsp !== undefined
            ? { camp: campFor(bot, fsp, f.stand), aggroAt: start + f.fsec }
            : undefined;
    const firstDone = () => f === undefined || f.aggro !== undefined;
    return {
        camp: campFor(bot, sp, stand, f !== undefined ? () => f.units : undefined),
        first,
        // 6 s, not camp_jobs' StandApproachLead (3): from the stand the camp was first seen at :55, so the hit landed at
        // :55.8-57.7 with the camp back in its box at :59.5 (probe s4p2, lich on evil_1 and evil_2).
        approachLead: SETTINGS.ApproachLead,
        waitClear: f !== undefined ? SETTINGS.WaitClear : undefined,
        aggroAt: start + (first !== undefined ? f!.sec : Stacking.AggroSec(data)),
        exitPath: ExitPath(sp, data) as unknown as Lib.Vec[],
        exitUntil: start + 60 + t.StackExitUntil,
        arrive: r.JobArrive,
        onTarget: n => {
            const u = n as unknown as Unit;
            if (!firstDone() || a.aim === u) return;
            a.aim = u;
            a.aimHp = u.GetHealth();
        },
        onAggro: info => {
            if (f !== undefined && f.aggro === undefined) {
                f.before = CampJobs.Exec.NeutralsInBox(bot, f.campIdx);
                f.aggro = info.confirmedAt - start;
                f.hitd = math.floor(GetUnitToLocationDistance(bot, fsp!.location));
                f.units = campNeutrals(bot, f.campIdx, info.target as unknown as Unit | undefined);
                return;
            }
            a.target = info.target as unknown as Unit | undefined;
            a.campUnits = campNeutrals(bot, data.campIdx, a.target, a);
            a.before = f === undefined ? CampJobs.Exec.NeutralsInBox(bot, data.campIdx) : a.campUnits.length;
            a.aggro = info.confirmedAt - start;
            a.hitd = math.floor(GetUnitToLocationDistance(bot, sp.location));
        },
    };
}

/** Seconds to walk from the bot to `p`. */
function travel(bot: Unit, p: Vector): number {
    return GetUnitToLocationDistance(bot, p) / math.max(1, bot.GetCurrentMovementSpeed());
}

function* body(bot: Unit, plan: JobVerbs.StackPlan, a: Attempt, ctx: Lib.Ctx): Lib.TaskBody {
    const label = (l: string) => {
        ctx.label(l);
        phase(bot, a, l);
    };
    const r = yield* Tasks.Jobs()!.stack(bot as unknown as Lib.TaskUnit, plan, { label, urgent: ctx.urgent });
    if (!r.success) return r;
    // Watch: walk towards the camp until its origin is in sight (night vision is 800, the exit point ~900 past the box),
    // count the box, and end once it holds more than at the hit or at :00 + WatchUntil. A double reads B, then walks to A
    // once B stacked or was read for BReadFor, and reads each box whenever it is in sight; A is `unseen` when it never was.
    ctx.label("watch");
    const spawnCheck = a.minute * 60 + 60;
    const outcomeAt = spawnCheck + LaneConfig.Settings().Timing.StackOutcomeAt;
    const f = a.first !== undefined && a.first.aggro !== undefined ? a.first : undefined;
    const until = f !== undefined ? SETTINGS.DoubleWatchUntil : SETTINGS.WatchUntil;
    let stopped = false;
    let campIdx = a.campIdx;
    let bReadAt: number | undefined;
    while (DotaTime() < math.min(spawnCheck + until, a.startedAt + awayMax() - 0.5)) {
        if (!bot.IsAlive()) return { success: false, reason: "dead" };
        if (f !== undefined && f.seen === undefined && CampJobs.Exec.BoxInSight(bot, f.campIdx)) f.seen = 1;
        if (DotaTime() >= outcomeAt) {
            if (CampJobs.Exec.BoxInSight(bot, a.campIdx)) {
                bReadAt = bReadAt ?? DotaTime();
                a.after = math.max(a.after ?? 0, CampJobs.Exec.NeutralsInBox(bot, a.campIdx));
                a.fresh = math.max(a.fresh ?? 0, freshInBox(bot, a, a.campIdx));
            }
            if (f !== undefined && CampJobs.Exec.BoxInSight(bot, f.campIdx)) {
                f.chk = f.chk ?? sec(a);
                f.fresh = math.max(f.fresh ?? 0, freshInBox(bot, a, f.campIdx));
            }
            if (f === undefined ? (a.fresh ?? 0) > 0 : (a.fresh ?? 0) > 0 && (f.fresh ?? 0) > 0) break;
            if (f !== undefined && campIdx === a.campIdx && bReadAt !== undefined
                && ((a.fresh ?? 0) > 0 || DotaTime() >= bReadAt + SETTINGS.BReadFor)) {
                campIdx = f.campIdx;
                stopped = false;
            }
        }
        if (CampJobs.Exec.BoxInSight(bot, campIdx)) {
            if (!stopped) bot.Action_MoveToLocation(bot.GetLocation());
            stopped = true;
        } else {
            bot.Action_MoveToLocation(Camps.SpawnerByIdx(campIdx)!.location);
        }
        yield;
    }
    return { success: true, reason: "ok" };
}

function sec(a: Attempt): number {
    return math.floor((DotaTime() - a.minute * 60) * 10) / 10;
}

function hpPct(bot: Unit): number {
    return math.floor((100 * bot.GetHealth()) / math.max(1, bot.GetMaxHealth()));
}

/** The verb's phase labels as seconds of the minute, with the HP at the hit order and at the walk-off. */
function phase(bot: Unit, a: Attempt, l: string): void {
    // A double's phases before camp A's hit are A's: arrival as farr, and no hit fields (they are B's).
    if (a.first !== undefined && a.first.aggro === undefined) {
        if (l === "wait") a.first.arr = a.first.arr ?? sec(a);
        if (l === "aggro" && a.first.hit0 === undefined) {
            a.first.hit0 = sec(a);
            a.first.hpa = hpPct(bot);
        }
        return;
    }
    if (l === "wait" && a.arr === undefined) a.arr = sec(a);
    if (l === "aggro") {
        a.hit0 = sec(a);
        a.hpa = hpPct(bot);
    }
    if (l === "exit") {
        a.exitAt = sec(a);
        a.hpe = hpPct(bot);
    }
}

/** Every frame of a running job, from Desire: farm's Think does not run while the bot casts (J.CanNotUseAction). */
function track(bot: Unit, a: Attempt): void {
    const ab = bot.GetCurrentActiveAbility();
    const name = ab !== null && ab !== undefined ? ab.GetName() : undefined;
    if (name !== undefined && name !== a.lastCast) {
        a.casts = a.casts ?? [];
        a.casts.push(`${name}@${sec(a)}`);
    }
    a.lastCast = name;
    if (DotaTime() < a.minute * 60 + 60) {
        a.seen = a.seen ?? new Set<Unit>();
        for (const c of bot.GetNearbyNeutralCreeps(SEEN_SCAN, false) ?? []) {
            if (c !== null && c !== undefined && c.IsAlive()) a.seen.add(c);
        }
    }
    sample59(bot, a);
    const f = a.first;
    if (f !== undefined && f.hit0 === undefined && f.auto === undefined) {
        const tgt = bot.GetAttackTarget();
        if (tgt !== null && tgt !== undefined && tgt.GetTeam() === Team.Neutral && Camps.InBox(f.campIdx, tgt.GetLocation(), LaneConfig.Settings().Radii.BoxMargin)) f.auto = sec(a);
    }
    if (a.hit0 !== undefined) {
        const n = a.aim;
        if (a.dmg === undefined && n !== undefined && !n.IsNull() && (!n.IsAlive() || n.GetHealth() < (a.aimHp ?? 0))) a.dmg = sec(a);
        if (a.react === undefined && campTargets(bot, a)) a.react = sec(a);
    }
    if (a.aggro !== undefined) a.lane = math.max(a.lane ?? 0, laneNear(bot, a));
}

/** Lane creeps this close to a camp's origin are in it: the 7.41 lane-side camps are ~1500+ from their lane. */
const LANE_NEAR = 900;

function laneNear(bot: Unit, a: Attempt): number {
    const sp = Camps.SpawnerByIdx(a.campIdx);
    if (sp === undefined) return 0;
    let n = 0;
    for (const enemy of [false, true]) {
        for (const c of bot.GetNearbyLaneCreeps(SEEN_SCAN, enemy) ?? []) {
            if (c !== null && c !== undefined && c.IsAlive() && GetUnitToLocationDistance(c, sp.location) <= LANE_NEAR) n++;
        }
    }
    return n;
}

/** Neutral scan radius for the seen set (the API's maximum). */
const SEEN_SCAN = 1600;

/** Visible neutrals in camp `campIdx`'s box (with margin) the bot had not seen before the :00 spawn check. */
function freshInBox(bot: Unit, a: Attempt, campIdx: number): number {
    const margin = LaneConfig.Settings().Radii.BoxMargin;
    let n = 0;
    for (const c of bot.GetNearbyNeutralCreeps(LaneConfig.Settings().Radii.StackCountScan, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen() && Camps.InBox(campIdx, c.GetLocation(), margin) && !(a.seen?.has(c) ?? false)) n++;
    }
    return n;
}

/** A double's camp A neutrals, which B's counts skip (they chase the bot into B's box margin). */
function isFirst(a: Attempt | undefined, n: Unit): boolean {
    return a?.first?.units?.includes(n) ?? false;
}

/** A visible neutral of the attempt's camp (not a double's camp A) is attacking the bot. */
function campTargets(bot: Unit, a: Attempt): boolean {
    for (const n of bot.GetNearbyNeutralCreeps(LaneConfig.Settings().Radii.NeutralSearch, false) ?? []) {
        if (n !== null && n !== undefined && n.IsAlive() && n.CanBeSeen() && !isFirst(a, n) && n.GetAttackTarget() === bot) return true;
    }
    return false;
}

/** Visible neutrals in camp `campIdx`'s box (with margin) and the hit one, without a double's camp A: the units to pull. */
function campNeutrals(bot: Unit, campIdx: number, target: Unit | undefined, a?: Attempt): Unit[] {
    const out: Unit[] = [];
    const margin = LaneConfig.Settings().Radii.BoxMargin;
    for (const c of bot.GetNearbyNeutralCreeps(LaneConfig.Settings().Radii.StackCountScan, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen() && !isFirst(a, c) && (c === target || Camps.InBox(campIdx, c.GetLocation(), margin))) out.push(c);
    }
    if (target !== undefined && !out.includes(target)) out.push(target);
    return out;
}

/** Each camp neutral now: name:dist:in|out:a|-. */
function describe(bot: Unit, units: Unit[] | undefined, campIdx: number): string {
    const sp = Camps.SpawnerByIdx(campIdx);
    const parts: string[] = [];
    for (const n of units ?? []) {
        if (n.IsNull() || !n.IsAlive()) {
            parts.push("dead");
            continue;
        }
        const name = string.gsub(n.GetUnitName(), "npc_dota_neutral_", "")[0];
        if (sp === undefined || !n.CanBeSeen()) {
            parts.push(`${name}:?`);
            continue;
        }
        const d = math.floor(GetUnitToLocationDistance(n, sp.location));
        const inBox = Camps.InBox(campIdx, n.GetLocation(), 0) ? "in" : "out";
        parts.push(`${name}:${d}:${inBox}:${n.GetAttackTarget() === bot ? "a" : "-"}`);
    }
    return parts.join(",");
}

function log(bot: Unit, minute: number, fields: Telemetry.Fields<"stack">): void {
    Telemetry.Event("stack", [["pid", bot.GetPlayerID()], ["min", minute], ...fields]);
}

/** What the bot sees of the camp as the attempt ends, so a `no_target` reads as an empty camp or a wrong box from the log. */
function look(bot: Unit, a: Attempt): void {
    const sp = Camps.SpawnerByIdx(a.campIdx);
    if (sp === undefined || !bot.IsAlive()) return;
    let near = 0;
    for (const c of bot.GetNearbyNeutralCreeps(LaneConfig.Settings().Radii.NeutralSearch, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen()) near++;
    }
    a.near = near;
    a.inbox = CampJobs.Exec.NeutralsInBox(bot, a.campIdx);
    a.dist = math.floor(GetUnitToLocationDistance(bot, sp.location));
    a.vis = IsLocationVisible(sp.location) ? 1 : 0;
}

function finish(bot: Unit, a: Attempt, result: Lib.Result): void {
    running[bot.GetPlayerID()] = undefined;
    look(bot, a);
    const sp = Camps.SpawnerByIdx(a.campIdx);
    // After a landed hit the box decides the result; before it, the attempt failed.
    const landed = a.aggro !== undefined;
    const res = !landed ? "failed" : (a.fresh ?? 0) > 0 ? "stacked" : "not_stacked";
    log(bot, a.minute, [
        ["res", res],
        ["why", result.success ? "ok" : `${result.reason}${result.message !== undefined ? ":" + result.message : ""}`],
        ["camp", a.campIdx],
        ["type", a.type],
        ["start", math.floor(a.startedAt * 10) / 10],
        ["aggro", a.aggro !== undefined ? math.floor(a.aggro * 10) / 10 : "?"],
        ["before", a.before ?? "?"],
        ["after", a.after ?? "?"],
        ["fresh", a.fresh ?? "?"],
        ["away", math.floor((DotaTime() - a.startedAt) * 10) / 10],
        ["death", result.reason === "dead" || !bot.IsAlive() ? 1 : 0],
        ["cx", sp !== undefined ? math.floor(sp.location.x) : "?"],
        ["cy", sp !== undefined ? math.floor(sp.location.y) : "?"],
        ["dist", a.dist ?? "?"],
        ["near", a.near ?? "?"],
        ["inbox", a.inbox ?? "?"],
        ["vis", a.vis ?? "?"],
        ["box59", a.box59 ?? "?"],
        ["pulled59", a.pulled59 ?? "?"],
        ["bot59", a.bot59 ?? "?"],
        ["vis59", a.vis59 ?? "?"],
        ["exit59", a.exit59 ?? "?"],
        ["hitd", a.hitd ?? "?"],
        ["tgt2", a.tgt2 === undefined || a.tgt2 < 0 ? "?" : a.tgt2],
        ["tgt59", a.tgt59 === undefined || a.tgt59 < 0 ? "?" : a.tgt59],
        ["strict59", a.strict59 ?? "?"],
        ["arr", a.arr ?? "?"],
        ["hit0", a.hit0 ?? "?"],
        ["dmg", a.dmg ?? "?"],
        ["react", a.react ?? "?"],
        ["exit", a.exitAt ?? "?"],
        ["hpa", a.hpa ?? "?"],
        ["hpe", a.hpe ?? "?"],
        ["hp59", a.hp59 ?? "?"],
        ["casts", a.casts !== undefined ? a.casts.join(",") : "-"],
        ["n2", a.n2 ?? "?"],
        ["n59", a.n59 ?? "?"],
        ["lane", a.aggro !== undefined ? a.lane ?? 0 : "?"],
        ["idle", a.idle ?? 0],
        ...doubleFields(a),
    ]);
}

/** A double's camp A on the attempt's line (`f` prefix); `double` alone when the camp's partner did not fit. */
function doubleFields(a: Attempt): Telemetry.Fields<"stack"> {
    if (a.double === undefined) return [];
    const f = a.first;
    if (f === undefined) return [["double", a.double], ["dwhy", a.dwhy ?? "?"]];
    const landed = f.aggro !== undefined;
    return [
        ["double", a.double],
        ["fres", !landed ? "failed" : (f.fresh ?? 0) > 0 ? "stacked" : f.chk === undefined ? "unseen" : "not_stacked"],
        ["fcamp", f.campIdx],
        ["ftype", f.type],
        ["faggro", landed ? math.floor(f.aggro! * 10) / 10 : "?"],
        ["fbefore", f.before ?? "?"],
        ["ffresh", f.fresh ?? "?"],
        ["fbox59", f.box59 ?? "?"],
        ["fhitd", f.hitd ?? "?"],
        ["farr", f.arr ?? "?"],
        ["fseen", f.seen ?? 0],
        ["fchk", f.chk ?? "?"],
        ["fhit0", f.hit0 ?? "?"],
        ["fhpa", f.hpa ?? "?"],
        ["fauto", f.auto ?? "?"],
        ["fn2", f.n2 ?? "?"],
        ["fn59", f.n59 ?? "?"],
    ];
}

/** mode_farm_generic GetDesire: the job's desire while it runs or as it starts, else 0 (OHA decides). */
export function Desire(bot: Unit): number {
    if (!Applies(bot)) return 0;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) {
        track(bot, running[pid]!);
        const threat = Threat(bot);
        if (threat === undefined) return SETTINGS.Desire;
        Tasks.Cancel(bot, "cancelled", threat);
        return 0;
    }
    const now = DotaTime();
    handled[pid] = handled[pid] ?? {};
    for (const minute of Minutes()) {
        if (handled[pid][minute] || now < minute * 60 + SETTINGS.LookFrom || now >= minute * 60 + 60) continue;
        // The pos4 stacks only its pairs (camp B of the minute's pair); the pos5 its nearest camp, with its partner if any.
        const pos4 = LaneConfig.PositionOf(bot) === 4;
        const pair = pos4 ? PairFor(bot.GetTeam(), minute) : undefined;
        let [data, stand] = Nearest(bot.GetTeam(), bot.GetLocation());
        if (pos4) [data, stand] = pair !== undefined ? [pair.b, Stand(Camps.SpawnerByIdx(pair.b.campIdx)!, pair.b)] : [undefined, undefined];
        const skip = (why: string) => {
            handled[pid][minute] = true;
            gateWhy[pid] = undefined;
            log(bot, minute, [
                ["res", "skip"],
                ["why", why],
            ]);
            return 0;
        };
        if (data === undefined || stand === undefined || Tasks.Jobs() === undefined) return skip("no-camp");
        // A double starts from camp A: its stand point and hit second set the start.
        const fd = pos4 ? pair : Ours.On("DoubleStack") ? Partner(data) : undefined;
        let double = fd !== undefined && Fits(bot, fd);
        let dwhy = fd !== undefined && !double ? "walk" : undefined;
        let aggroAt = minute * 60 + Stacking.AggroSec(data);
        let walk = travel(bot, stand);
        let lead = SETTINGS.Lead;
        if (double) {
            const fAt = minute * 60 + fd!.fsec;
            const fWalk = travel(bot, fd!.stand);
            // Started at its latest slack (MinSlack) the double must still end within AwayMax, else this minute runs single.
            // Held by the gate past its own latest start, it runs single while the single can still start.
            dwhy = minute * 60 + 60 + SETTINGS.FarEnd - (fAt - fWalk - SETTINGS.MinSlack) > awayMax() ? "far" : now > fAt - fWalk - SETTINGS.MinSlack ? "late" : undefined;
            double = dwhy === undefined;
            // The line's camp is B; a minute that runs single keeps the nearest camp (slice 4's stack).
            if (double) [aggroAt, walk, lead, data, stand] = [fAt, fWalk, SETTINGS.DoubleLead, fd!.b, Stand(Camps.SpawnerByIdx(fd!.b.campIdx)!, fd!.b)];
        }
        if (now < aggroAt - walk - lead) return 0;
        if (now > aggroAt - walk - SETTINGS.MinSlack) return skip(gateWhy[pid] ?? "late");
        if (minute * 60 + 60 + SETTINGS.FarEnd - now > awayMax()) return skip("far");
        const why = Gate(bot);
        if (why !== undefined) {
            gateWhy[pid] = why;
            return 0;
        }
        const a: Attempt = { minute, campIdx: data.campIdx, type: data.type, startedAt: now };
        if (fd !== undefined) a.double = double ? 1 : 0;
        a.dwhy = dwhy;
        if (double) a.first = { campIdx: fd!.a.campIdx, type: fd!.a.type, stand: fd!.stand, fsec: fd!.fsec, sec: fd!.sec };
        const plan = Plan(bot, data, stand, minute, a);
        const ok = Tasks.Start(bot, { name: "stack", host: BotMode.Farm, preemptAfter: SETTINGS.PreemptAfter, stallAfter: SETTINGS.StallAfter, onEnd: result => finish(bot, a, result) }, (ctx: Lib.Ctx) =>
            body(bot, plan, a, ctx)
        );
        if (!ok) return skip("refused");
        handled[pid][minute] = true;
        gateWhy[pid] = undefined;
        running[pid] = a;
        return SETTINGS.Desire;
    }
    return 0;
}

/** mode_farm_generic Think: steps the job; false when none runs. */
/** At :59.5 of the attempt's minute: the state Valve's spawn check sees, so a `not_stacked` names its cause in the log. */
/** The hit neutral's distance to the camp origin, or undefined when it is gone or unseen. */
function targetDist(a: Attempt): number | undefined {
    const t = a.target;
    const sp = Camps.SpawnerByIdx(a.campIdx);
    if (t === undefined || sp === undefined || t.IsNull() || !t.IsAlive() || !t.CanBeSeen()) return undefined;
    return math.floor(GetUnitToLocationDistance(t, sp.location));
}

function sample59(bot: Unit, a: Attempt): void {
    // A double's camp A, on its own clock: B's hit may never come (preempted after A's, ds2).
    const f = a.first;
    if (f !== undefined && f.aggro !== undefined) {
        if (f.n2 === undefined && DotaTime() >= a.minute * 60 + f.aggro + 2) f.n2 = describe(bot, f.units, f.campIdx);
        if (f.n59 === undefined && DotaTime() >= a.minute * 60 + 59.5) {
            f.n59 = describe(bot, f.units, f.campIdx);
            f.box59 = CampJobs.Exec.NeutralsInBox(bot, f.campIdx);
        }
    }
    if (a.tgt2 === undefined && a.aggro !== undefined && DotaTime() >= a.minute * 60 + a.aggro + 2) {
        a.tgt2 = targetDist(a) ?? -1;
        a.n2 = describe(bot, a.campUnits, a.campIdx);
    }
    if (a.box59 !== undefined || a.aggro === undefined || DotaTime() < a.minute * 60 + 59.5) return;
    const sp = Camps.SpawnerByIdx(a.campIdx);
    const data = Camps.ByIdx(a.campIdx);
    if (sp === undefined) return;
    const margin = LaneConfig.Settings().Radii.BoxMargin;
    let pulled = 0;
    for (const c of bot.GetNearbyNeutralCreeps(LaneConfig.Settings().Radii.NeutralSearch, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen() && !Camps.InBox(a.campIdx, c.GetLocation(), margin)) pulled++;
    }
    a.box59 = CampJobs.Exec.NeutralsInBox(bot, a.campIdx);
    a.tgt59 = targetDist(a) ?? -1;
    let strict = 0;
    for (const c of bot.GetNearbyNeutralCreeps(LaneConfig.Settings().Radii.StackCountScan, false) ?? []) {
        if (c !== null && c !== undefined && c.IsAlive() && c.CanBeSeen() && Camps.InBox(a.campIdx, c.GetLocation(), 0)) strict++;
    }
    a.strict59 = strict;
    a.n59 = describe(bot, a.campUnits, a.campIdx);
    a.hp59 = hpPct(bot);
    a.pulled59 = pulled;
    a.bot59 = Camps.InBox(a.campIdx, bot.GetLocation(), 0) ? 1 : 0;
    a.vis59 = IsLocationVisible(sp.location) ? 1 : 0;
    const path = data !== undefined && data.stack !== undefined ? ExitPath(sp, data) : undefined;
    a.exit59 = path !== undefined && path.length > 0 ? math.floor(GetUnitToLocationDistance(bot, path[path.length - 1])) : undefined;
}

export function Think(bot: Unit): boolean {
    const a = running[bot.GetPlayerID()];
    if (a === undefined) return false;
    return Tasks.Step(bot, BotMode.Farm);
}

/**
 * mode_farm_generic's ShouldRun: neutrals hitting the pos5 during its stack are not a reason to run; the job's exit is its
 * retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
 */
export function HoldsRun(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

/**
 * ability_item_usage: spells and items wait while the job runs, as camp_jobs' HoldsCasts does for camp jobs. OHA's farm
 * branches cast on the camp: witch doctor's cask landed at :42-:47, before the hit, and once after it, and the stunned
 * neutrals walked back into the box (user replay and s4solo2); a TP scroll on the walk stalled the job (s4solo2 5:4x).
 * An enemy hero in reach lifts it so the bot can fight or save itself. Benched heroes (Overrides.Solo) never cast.
 */
export function HoldsCasts(bot: Unit): boolean {
    if (Benched(bot)) return true;
    if (running[bot.GetPlayerID()] === undefined) return false;
    return (bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length === 0;
}

/**
 * jmz_func CheckBotIdleState (called from team_roam's GetDesire whatever mode is active): a bot in farm mode that moved
 * under 100 in 3 s gets ClearActions and an attack-move to its lane front. A stack job stands still at its stand point by
 * design, and when the check fell inside the 2 s after the hit order it replaced the attack: all 4 slice 4 `no-aggro` misses
 * (attack-move from the order to the miss, s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55). True while the job
 * runs, counted on the attempt.
 */
export function HoldsIdle(bot: Unit): boolean {
    const a = running[bot.GetPlayerID()];
    if (a === undefined) return false;
    a.idle = (a.idle ?? 0) + 1;
    return true;
}

/** OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`. */
export function Abort(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}
