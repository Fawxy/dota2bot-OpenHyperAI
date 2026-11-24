/**
 * The whole-wave pull (doctrine D17, switch Ours.SupportPull), a row of the decider (plan s3): a pos4/pos5 takes our wave
 * into its lane's first pull camp when the pull's own forecast of the lane wants it, then the decider yields it back to
 * stock. This module reads the lane once per pull slot (`ev=choice kind=pull`), plans the pull from the camp data (`camps`,
 * `pull_timing`), walks it with the job verb `pull` and logs one `ev=pull_job` line per started pull. With the switch off
 * the same read is logged as a shadow and nothing else runs.
 */
import * as GameRules from "bots/FunLib/humaniser/game_rules";
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, DamageType, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";

/** Telemetry only (`hit` on the pull's lines): a hero damaged the puller within this many seconds. */
const HERO_HIT_WITHIN = 3;

// All `judgement` (slice file, Decisions), except where a source is named.
export const SETTINGS = {
    /** A camp read `one` or `empty` on the walk ends the pull only once it has held this long (`judgement`): a camp coming into
     *  sight shows its neutrals over a few frames, since the API returns no fogged ones (drill pull ldr6: 5 of 9 pulls
     *  cancelled `one` on the first sight of a freshly spawned full camp). A four-corner visibility rule was tried first
     *  and never read true (ldr11, ldr12: every pull walked into an empty camp). */
    CampLowHold: 1.5,
    /** ... and only once the puller is within this of its stand point, so its own vision covers the camp (`judgement`; ldr14:
     *  3 of 9 pulls on a fresh camp still cancelled `one` after the hold, 3-6 s into the walk). Both values leave about 2 s
     *  before the slot (ldr17: the empty-camp cancels fell 2.0 s before to 0.8 s after it); the hold never runs past the hit. */
    CampReadNear: 500,
    /** Leave this long before the walk alone would arrive, so the bot stands at the camp before the hit. */
    Early: 2,
    /** Walking paths run longer than the straight line (rune_job's PathFactor). */
    PathFactor: 1.2,
    /** A pull is wanted when, with the pulled wave gone, the clash ArriveAfter s after the slot (the current wave's fight
     *  resolved) is forecast more than WantPast beyond the lane's target point (LanePush TargetOf), and their creeps in lane
     *  have at most PowerRatio times our HP (slice support-lane, Decision 06/11/2026; ArriveAfter and PowerRatio
     *  `judgement`, scored offline on the banked slots before the change: the slice file). A lane coming in (IN) is no
     *  refusal: the pull keeps our next wave from dying under their tower. */
    WantPast: 150,
    ArriveAfter: 12,
    PowerRatio: 1.2,
    /** Our creeps within MeetWatch of the meet point or of the camp origin are watched; a creep attacking a neutral is
     *  diverted. Wave size: our creeps within WaveSize of either when the first one is seen diverted (camp_jobs' sample,
     *  LaneConfig Radii). */
    WatchEvery: 0.25,
    /** After a job that ended ok, keep sampling the wave this long past the later of the job end and the wave's due time:
     *  the job ends 3 s after the wave is due, while its later creeps are still reaching the neutrals (sp2: pulls logged at
     *  div 0.25 moved the lane back the most, `eq` -1.65 in 30 s, about 0.8 of the T1-T1 stretch). */
    TrailSec: 10,
    /** The stay's backstop: it ends `timeout:late` this long after it began (the old pull farm's MaxFarm; a clear is 7-26 s). */
    StayMax: 35,
    /** The stay clears the neutrals left once none of our creeps is at the camp only if the camp's damage over
     *  StayClearSeconds leaves StayClearReserve of max HP (the old pull farm's ClearSeconds and ClearReserve). */
    StayClearSeconds: 4,
    StayClearReserve: 0.3,
    /** `ev=pull_watch` cadence: one line per pull per this many seconds from the lead to the end of the trail. */
    WatchLogEvery: 1,
    /** The neutral `nd`/`nh`/`nt` describe is the nearest within this of the meet point, so a camp that never followed still shows. */
    WatchNeutralSearch: 3000,
    /** Diagnosis (slice pull-diag): at the hit the camp's own neutrals are tagged, those in its box or attacking the puller
     *  within TagRadius; Acquire is the creep acquisition range (EC-053) for `na`; ArriveR the wave's arrival for `wa`. */
    TagRadius: 1200,
    Acquire: 500,
    ArriveR: 300,
    /** A tagged neutral counts once it is Left from its camp origin (EC-084: the 5 s give-up timer starts past 400); it is
     *  walking home once it is HomeMargin back from its own farthest point. A chasing neutral out of attack range reports
     *  no attack target (review 2026-11-04-pull-diag H1), so giving up is read from movement. */
    Left: 400,
    HomeMargin: 150,
    /** A tagged neutral has started (`nm`) once it is this far from where it stood at the hit. */
    Moved: 50,
    /** The start check (`why=camp-dmg`, also run on the walk): the camp's damage on the puller for HitSeconds must leave it
     *  StartReserve of its max HP. The window is a constant, not a share of the lead (user 06/11/2026: "when we're pulling
     *  the damage checks need to loosen. it's our creeps tanking that damage, not us, and we don't take much damage
     *  pulling"): on the banked `ok` pulls with no hero hit the puller lost 12% of its max HP on average whatever the camp
     *  (518 off-lane pulls of the hard camp with no hero hit, 2,142 safe-lane pulls of the small camp; p90 30%, 0 died; the
     *  numbers and query are in the slice file), about
     *  1.1 s of the hard camp's damage and 2.4 s of the small camp's; the old share of the lead (0.5 of 6.9 s) priced the
     *  hard camp at 38% of max HP and held 227 wanted off-lane slots at 63% HP. The camp's damage is what the API estimates
     *  for the neutrals it returns in the box, so a stacked camp still counts its stack (pw3_C_on_3 t=262.5: 8 neutrals,
     *  the one death; the off-lane walk met the hard camp stacked 5-12 deep on 250 of its 312 `cancelled:camp-dmg`); with
     *  none returned, one spawn at DefaultDps (`large` 80 is the API's own 53-89 for the seen hard camp). StartReserve is
     *  the bail reserve: a start that would leave less plans to bail. All `judgement`. */
    HitSeconds: 1.5,
    StartReserve: 0.25,
    DefaultDps: { small: 40, medium: 60, large: 80, ancient: 150 } as Record<Camps.CampType, number>,
    /** After the hit (lead and watch), the puller steps back towards our tower when neutrals hit it and its HP after
     *  BailGrace seconds of their damage is under BailReserve of its max; it keeps stepping back while they still hit it, at
     *  most BailFor seconds, then the job ends `interrupted:bail`. The horizon is short on purpose: a puller walking the lead
     *  takes a small part of the camp's damage, so projecting it to the wave's arrival bailed at full HP (pc1: 12 bails,
     *  all about 1 s after the hit, at 58-100% HP). `judgement`. */
    BailReserve: 0.25,
    BailGrace: 2,
    BailFor: 6,
    /** Neutrals within this of the puller are the ones that can be hitting it. */
    BailScan: 1200,
    /** With no tower of ours on the lane, step this far straight away from the neutrals. */
    BailStep: 700,
    /** The shed (user 06/11/2026: "get the neutrals onto your allied creeps and not tank asap after pull succeeds"): in the
     *  watch, once a lane creep of ours near the watch attacks a neutral while a neutral still attacks the puller, the
     *  puller walks to ShedMargin past the attacking neutrals' longest attack range from their centre, away from them and
     *  towards our tower's side, so their aggro passes to the creeps. It walks at most ShedFor seconds and then stays where
     *  the shed left it for the rest of the watch (no walk back into the neutrals). Not a bail: the job still ends `ok`.
     *  Bug-hunt 05/11/2026 mark 13 (WD pid 7, camp 26): held the watch point 322-330 s at 67% -> 44% HP while 1-4 creeps
     *  were on the neutrals from 324 and the neutrals stayed on it until 327. `judgement`. */
    ShedMargin: 300,
    ShedFor: 5,
    /** The bar (families proposal s5, named 24/11/2026): a pull is started only into a camp of at least this many neutrals on
     *  the hero's record. From the banked pull rigs' diverted pulls, creeps dead within 1,000 of the camp by neutrals met:
     *  3 met 13 of 61, 4 met 4 of 36, 5 met 7 of 8, 6 or more 137 of 140. */
    StrongAt: 6,
    /** Neutrals the spawn rule adds to an empty camp while it is out of sight (`judgement`: a camp's set varies by kind,
     *  2 to 4; the next sighting corrects it). */
    SetSize: { small: 3, medium: 3, large: 3, ancient: 3 } as Record<Camps.CampType, number>,
    /** The record's look at the lane's camp while no pull runs, at most this often (`judgement`). */
    RecordEvery: 0.5,
};

/** What the API returns in the camp's box: `n` neutrals, `seen` of them `CanBeSeen`, `hp` their health, `vis` the camp's
 *  origin visible to our team (its neutrals stand there; the box corners plus margin were never all visible in pc1). */
interface CampState {
    n: number;
    seen: number;
    hp: number;
    vis: boolean;
    /** The counted box's four corners are in sight (telemetry `cfv` only: in drills they never all read visible, ldr11). */
    full?: boolean;
    /** The neutrals returned, for the damage estimate. */
    units: Unit[];
    /** At a decision: the camp's expected damage on the puller (CampDamage) and the puller's HP. */
    dmg?: number;
    php?: number;
    /** At a decision: the nearest enemy hero to the stand point or the meet point (siteThreat). */
    se?: number;
    /** At a decision: the camp as the hero's record knows it (Known). */
    known?: CampKnown;
}

interface Plan {
    camp: Camps.CampJobData;
    spawner: Camps.Spawner;
    stand: Vector;
    lead: Vector[];
    meet: Vector;
    timing: PullTiming.PullTiming;
    /** The planned hit second (no skill error): the slot the lane is read and decided for. */
    slot: number;
}

interface Pull {
    plan: Plan;
    left: number;
    /** The walk's camp read went `one` or `empty` (why, since when); cleared when it reads full again. */
    low?: { why: string; at: number };
    host: number;
    label?: string;
    hit?: boolean;
    idle?: number;
    sampledAt?: number;
    watchedAt?: number;
    wave: number;
    peak: number;
    near?: number;
    neutrals: number;
    /** The hit second as last read (the live wave up to the order), and the shift it had at the start. */
    hitAt: number;
    timer: PullTiming.CreepTimer;
    start: CampState;
    /** Slice pull-diag: hit confirmed at, the camp's neutrals tagged then, and what they did (pull_job sh..wa). */
    hat?: number;
    tagged?: Unit[];
    /** Per tagged neutral: its farthest distance from the camp origin so far. */
    peaks?: Map<Unit, number>;
    /** Lane creeps already within ArriveR of the meet point at the hit (they do not set `wa`). */
    early?: Unit[];
    g4?: number;
    diagErr?: boolean;
    gh?: number;
    na?: number;
    gu?: number;
    gd?: number;
    wa?: number;
    /** Where each tagged neutral stood at the hit, and when the first was 50 from it (nm). */
    starts?: Map<Unit, Vector>;
    nm?: number;
    /** The shed (SETTINGS ShedMargin): when it began, the puller's HP share then, and the point it last walked to. */
    shs?: number;
    shh?: number;
    shedTo?: Vector;
    /** The stay (Ours.SupportPullStay): when it began, its deny and neutral last-hit tries and successes. */
    stayAt?: number;
    sdt?: number;
    sdk?: number;
    slt?: number;
    slk?: number;
}

interface Decision {
    slot: number;
    want: boolean;
    reading?: LanePush.Reading;
    /** The lane with the pulled wave gone (Wanted's input). */
    gone?: LanePush.WaveGone;
    /** Which rule wanted the pull: `new` (Wanted) or `drill`. */
    rule?: string;
    /** A drill decided this wave (Drill.ForcedAt): a refusal is `drill`. */
    drill?: boolean;
}

interface Trail {
    pull: Pull;
    fields: Telemetry.Fields<"pull_job">;
    until: number;
}

const running: Record<number, Pull | undefined> = {};
const trailing: Record<number, Trail | undefined> = {};
const handled: Record<number, number | undefined> = {};
const decided: Record<number, Decision | undefined> = {};
const timers: Record<number, PullTiming.CreepTimer | undefined> = {};
const gateWhy: Record<number, string | undefined> = {};
/** By camp idx: this hero's record of each camp (CampRecord). */
const records: Record<number, CampRecord | undefined> = {};
const watchedAt: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, trailing, handled, decided, gateWhy, timers, records, watchedAt] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

function isSupport(u: Unit): boolean {
    const pos = LaneConfig.PositionOf(u);
    return pos === 4 || pos === 5;
}

/** The support that pulls for `bot`'s lane: pos5 when both supports share it. */
function pullerOfLane(bot: Unit): boolean {
    if (LaneConfig.PositionOf(bot) === 5) return true;
    const lane = bot.GetAssignedLane();
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m === bot) continue;
        if (LaneConfig.PositionOf(m) === 5 && m.GetAssignedLane() === lane) return false;
    }
    return true;
}

/** The lane's first pull camp; with `Overrides.PullCamp` (a rig's camp type, e.g. `large` for the hard camp) the first of that type. */
function campFor(bot: Unit): Camps.CampJobData | undefined {
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Bot) return undefined;
    const camps = Camps.PullCampsFor(bot.GetTeam(), lane);
    const kind = Overrides.Get("PullCamp");
    if (typeof kind === "string" && kind !== "") return camps.find((c) => c.type === kind);
    return camps[0];
}

/** The hero that would pull for its lane, whatever the switches say. */
export function IsPuller(bot: Unit): boolean {
    return bot.IsBot() && TripTable.Does("pull", LaneConfig.PositionOf(bot)) && isSupport(bot) && pullerOfLane(bot) && campFor(bot) !== undefined;
}

/** The row is switched on for this lane's puller (Ours.Team scopes it, so the other team's puller is shadowed). A hero a drill
 *  benches or stands as a statue is the drill's: the chooser never asked its jobs, and the row is not asked either. */
function rowOn(bot: Unit): boolean {
    return Ours.On("SupportPull") && IsPuller(bot) && !Drill.Held(bot);
}

/** The next hit second at or after `from` among `seconds` of each minute (camp_jobs' NextAggroTime). */
export function NextSlot(from: number, seconds: number[], period: number): number {
    const base = math.floor(from / period) * period;
    let best = math.huge;
    for (const s of seconds) for (const t of [base + s, base + period + s]) if (t >= from && t < best) best = t;
    return best;
}

/** The next wave's pull: its hit second from the wave plan (pull_timing), stand, lead and meet point. */
function planFor(bot: Unit, now: number): Plan | undefined {
    const camp = campFor(bot);
    const spawner = camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
    if (camp === undefined || camp.pull === undefined || spawner === undefined) return undefined;
    const t = LaneConfig.Settings().Timing;
    const timing = PullTiming.ForCamp(camp);
    if (timing.seconds.length === 0) return undefined;
    const slot = NextSlot(now - t.JobStartLate, timing.seconds, t.PullPeriod);
    // Camps hold neutrals for a whole minute only from their first spawn on (camp_jobs' CampsUp).
    if (math.floor(slot / t.PullPeriod) * t.PullPeriod < t.NeutralFirstSpawn) return undefined;
    const meet = camp.pull.meetPoint;
    const lead = PullTiming.LeadPath(camp.pull, meet);
    const stand = Camps.StandPoint(spawner, lead[0], LaneConfig.Settings().Radii.StandOffset);
    return { camp, spawner, stand, lead, meet, timing, slot };
}

function travel(bot: Unit, p: Plan): number {
    return (GetUnitToLocationDistance(bot, p.stand) * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed());
}

export function CampStateOf(spawner: Camps.Spawner): CampState {
    const m = LaneConfig.Settings().Radii.BoxMargin;
    const lo = spawner.min;
    const hi = spawner.max;
    const z = spawner.location.z;
    // The corners of the box as counted (BoxMargin beyond it, review 2026-11-08-lane-drills L5).
    const [x0, y0, x1, y1] = [lo.x - m, lo.y - m, hi.x + m, hi.y + m];
    const full = IsLocationVisible(Vector(x0, y0, z)) && IsLocationVisible(Vector(x1, y0, z)) && IsLocationVisible(Vector(x0, y1, z)) && IsLocationVisible(Vector(x1, y1, z));
    const s: CampState = { n: 0, seen: 0, hp: 0, vis: IsLocationVisible(spawner.location), full, units: [] };
    for (const u of GetUnitList(UnitType.NeutralCreeps)) {
        if (!u.IsAlive()) continue;
        const p = u.GetLocation();
        if (p === undefined || p === null) continue;
        if (p.x < lo.x - m || p.x > hi.x + m || p.y < lo.y - m || p.y > hi.y + m) continue;
        s.n++;
        if (u.CanBeSeen()) s.seen++;
        s.hp += u.GetHealth();
        s.units.push(u);
    }
    return s;
}

/**
 * What this hero knows of a camp's strength while it is out of sight (families proposal s5: the trigger reads about 10 s
 * before the slot with the camp fogged, `cn` 0 in every pullchain1 slot). A sighting is a fact and replaces the record; in
 * between it moves only by the game's rules. The count is the neutrals last seen whose handles still read alive (one that
 * dies in fog drops out if the API reports it; if not, the record stays high until the next sighting) plus the neutrals the
 * spawn rules added since.
 */
interface CampRecord {
    units: Unit[];
    added: number;
    /** The last sighting that set the record, and whether the rules have added since (`src` on the lines). */
    seenAt: number;
    src: "seen" | "rules";
    /** The last minute mark the spawn rule was applied to. */
    minute: number;
    /** A stack holds the record (Hold): no look counts the camp until then. */
    heldUntil?: number;
}


/** A camp's neutrals within this of its origin, seen alive, stay on the record through a sighting of the box: a stack's
 *  pulled set walks back over :00 and stands outside the counted box (`judgement`, the pull's TagRadius). */
const RECORD_LEASH = 1200;

function alive(u: Unit): boolean {
    return !u.IsNull() && u.IsAlive();
}

function recordCount(r: CampRecord): number {
    let n = r.added;
    for (const u of r.units) if (alive(u)) n++;
    return n;
}

/**
 * The spawn rule since the record's last minute: at each mark an empty camp gets a set, a camp holding neutrals gets nothing
 * (leftovers block the spawn: pullchain1, Dire 7:00). A stack's set is the stack row's to add (NoteSet), since the record
 * cannot tell a pulled-out camp from one in its box.
 */
function advance(r: CampRecord, type: Camps.CampType, now: number): void {
    const m = math.floor(now / GameRules.NEUTRAL_EVERY);
    while (r.minute < m) {
        r.minute++;
        if (r.minute * GameRules.NEUTRAL_EVERY >= GameRules.NEUTRAL_FIRST && recordCount(r) === 0) {
            r.added += SETTINGS.SetSize[type];
            r.src = "rules";
        }
    }
}

function recordOf(spawner: Camps.Spawner, now: number): CampRecord {
    let r = records[spawner.idx];
    if (r === undefined) {
        // Before the first spawn the camp is empty, and the rule fills it at the first mark.
        r = { units: [], added: 0, seenAt: now, src: "rules", minute: math.floor(now / GameRules.NEUTRAL_EVERY) };
        if (now >= GameRules.NEUTRAL_FIRST) r.added = SETTINGS.SetSize[spawner.type];
        records[spawner.idx] = r;
    }
    advance(r, spawner.type, now);
    return r;
}

/**
 * A look at the camp (`s`, CampStateOf now). A full view (the box's corners in sight, or `close`: one of ours stands at the
 * camp, since the corners never all read visible in the drills, ldr11) replaces the record; a partial one only raises it,
 * since a neutral out of view would drop a strong camp under the bar. An unseen origin says nothing (the API returns no
 * fogged neutrals).
 */
export function NoteSighting(spawner: Camps.Spawner, s: CampState, close: boolean): void {
    if (!s.vis) return;
    const now = DotaTime();
    const r = recordOf(spawner, now);
    if (r.heldUntil !== undefined && now < r.heldUntil) return;
    if (!(s.full === true || close) && s.n <= recordCount(r)) return;
    const units = [...s.units];
    for (const u of r.units) {
        if (!alive(u) || !u.CanBeSeen() || units.includes(u) || GetUnitToLocationDistance(u, spawner.location) > RECORD_LEASH) continue;
        units.push(u);
    }
    r.units = units;
    r.added = 0;
    r.seenAt = now;
    r.src = "seen";
}

/**
 * The stack row's read of its camp after the mark: the set it pulled out (`pulled`, the handles at its hit) and the spawn it
 * saw come in (`fresh`), or a set by the rules when the box was out of sight (`fresh` undefined). It replaces the record:
 * the row held it through the stack (Hold), since no look at the box counts a pulled-out set.
 */
export function NoteStack(spawner: Camps.Spawner, pulled: Unit[], fresh: number | undefined): void {
    const now = DotaTime();
    const r = recordOf(spawner, now);
    r.units = pulled.filter((u) => alive(u));
    r.added = fresh ?? SETTINGS.SetSize[spawner.type];
    r.src = fresh !== undefined ? "seen" : "rules";
    if (fresh !== undefined) r.seenAt = now;
    r.heldUntil = undefined;
}

/** No look updates the record until `until` (or NoteStack): a stack is pulling the camp out of its box. */
export function Hold(spawner: Camps.Spawner, until: number): void {
    recordOf(spawner, DotaTime()).heldUntil = until;
}

export interface CampKnown {
    n: number;
    src: "seen" | "rules";
    /** Seconds since the last sighting that set the record. */
    age: number;
    /** Of `n`, the neutrals last seen whose handles still read alive; the rest the rules added. */
    held: number;
}

/** The camp's strength as this hero knows it now (CampRecord). */
export function Known(spawner: Camps.Spawner): CampKnown {
    const now = DotaTime();
    const r = recordOf(spawner, now);
    const n = recordCount(r);
    return { n, src: r.src, age: math.floor((now - r.seenAt) * 10) / 10, held: n - r.added };
}

/** The camp holds at least the bar's neutrals (SETTINGS.StrongAt) on this hero's record. */
export function Strong(spawner: Camps.Spawner): boolean {
    return Known(spawner).n >= SETTINGS.StrongAt;
}

/**
 * `empty` when the camp holds nothing to pull at `hitAt`: nothing returned while the team sees the camp's origin, and no
 * spawn minute before the hit (a camp respawns only on the minute, so it stays empty). An empty box out of sight says
 * nothing: the API returns no fogged neutrals (pc1: every one returned was `CanBeSeen`). `one` the same with a single
 * neutral left: too little to hold a wave (banked `ok` pulls with one neutral seen at the start diverted 26 of 56, two or
 * more 243 of 385; user 04/11/2026: skip it). Stacking it instead is the stack job's call, not this one's.
 */
export function CampGate(s: CampState, now: number, hitAt: number): string | undefined {
    if (!readsHit(s, now, hitAt)) return undefined;
    if (s.n === 0) return "empty";
    if (s.n === 1) return "one";
    return undefined;
}

/** What the team sees of the camp now holds at the hit: the origin is in sight and no spawn mark comes before the hit. */
function readsHit(s: CampState, now: number, hitAt: number): boolean {
    const period = LaneConfig.Settings().Timing.PullPeriod;
    return s.vis && math.floor(hitAt / period) <= math.floor(now / period);
}

/** The camp's expected damage on `bot` over `seconds` of its hits (the pull's HitSeconds by default; DefaultDps unseen). */
export function CampDamage(bot: Unit, s: CampState, type: Camps.CampType, seconds?: number): number {
    const exposure = seconds ?? SETTINGS.HitSeconds;
    if (s.units.length === 0) return SETTINGS.DefaultDps[type] * exposure;
    let dmg = 0;
    for (const u of s.units) dmg += u.GetEstimatedDamageToTarget(true, bot, exposure, DamageType.All);
    return dmg;
}

/** The puller cannot take the camp: its expected damage would leave less than StartReserve of max HP. */
function campDmgGate(bot: Unit, dmg: number): string | undefined {
    return bot.GetHealth() - dmg < bot.GetMaxHealth() * SETTINGS.StartReserve ? "camp-dmg" : undefined;
}

/** Where the puller steps back to while neutrals are about to kill it (SETTINGS BailReserve), else undefined. */
function bailPoint(bot: Unit): Vector | undefined {
    if (!bot.IsAlive()) return undefined;
    const at = bot.GetLocation();
    let dps = 0;
    let cx = 0;
    let cy = 0;
    let k = 0;
    for (const u of GetUnitList(UnitType.NeutralCreeps)) {
        if (!u.IsAlive() || u.GetAttackTarget() !== bot || GetUnitToUnitDistance(u, bot) > SETTINGS.BailScan) continue;
        const l = u.GetLocation();
        if (l === undefined || l === null) continue;
        dps += u.GetEstimatedDamageToTarget(true, bot, 1, DamageType.All);
        cx += l.x;
        cy += l.y;
        k++;
    }
    if (k === 0) return undefined;
    if (bot.GetHealth() - dps * SETTINGS.BailGrace >=bot.GetMaxHealth() * SETTINGS.BailReserve) return undefined;
    const tower = ourTower(bot);
    if (tower !== undefined) return tower;
    const dx = at.x - cx / k;
    const dy = at.y - cy / k;
    const d = math.max(1, math.sqrt(dx * dx + dy * dy));
    return Vector(at.x + (dx * SETTINGS.BailStep) / d, at.y + (dy * SETTINGS.BailStep) / d, at.z);
}

/**
 * In the watch: where the puller walks to hand the neutrals to our creeps (SETTINGS ShedMargin), else undefined. Starts once
 * a lane creep of ours near the watch attacks a neutral while a neutral attacks the puller; once started it follows the
 * neutrals that still attack the puller for ShedFor seconds, and otherwise returns where it last walked to, so the watch
 * stays out of the fight.
 */
function shedPoint(bot: Unit, pull: Pull): Vector | undefined {
    if (!bot.IsAlive()) return undefined;
    const now = DotaTime();
    if (pull.shs !== undefined && now - pull.shs > SETTINGS.ShedFor) return pull.shedTo;
    const at = bot.GetLocation();
    let cx = 0;
    let cy = 0;
    let k = 0;
    let range = 0;
    for (const u of GetUnitList(UnitType.NeutralCreeps)) {
        if (!u.IsAlive() || u.GetAttackTarget() !== bot || GetUnitToUnitDistance(u, bot) > SETTINGS.BailScan) continue;
        const l = u.GetLocation();
        if (l === undefined || l === null) continue;
        cx += l.x;
        cy += l.y;
        k++;
        range = math.max(range, u.GetAttackRange());
    }
    if (k === 0) return pull.shedTo;
    if (pull.shs === undefined && !laneCreepsNear(pull.plan, LaneConfig.Settings().Radii.MeetWatch).some((c) => onNeutral(c))) return undefined;
    cx /= k;
    cy /= k;
    const unit = (x: number, y: number): [number, number, number] => {
        const l = math.sqrt(x * x + y * y);
        return l < 1 ? [0, 0, 0] : [x / l, y / l, l];
    };
    const [ax, ay, al] = unit(at.x - cx, at.y - cy);
    const tower = ourTower(bot);
    const [tx, ty, tl] = tower !== undefined ? unit(tower.x - at.x, tower.y - at.y) : [0, 0, 0];
    // Away from the neutrals, bent towards our tower; straight away when the tower lies behind them.
    let [dx, dy, dl] = unit(ax + tx, ay + ty);
    if (dl < 0.5) [dx, dy, dl] = al > 0 ? [ax, ay, 1] : [tx, ty, tl];
    if (dl === 0) return pull.shedTo;
    if (pull.shs === undefined) {
        pull.shs = now;
        pull.shh = bot.GetHealth() / math.max(1, bot.GetMaxHealth());
    }
    const r = range + SETTINGS.ShedMargin;
    pull.shedTo = Vector(cx + dx * r, cy + dy * r, at.z);
    return pull.shedTo;
}

/** Our first standing tower on the bot's lane, outermost first. */
function ourTower(bot: Unit): Vector | undefined {
    const ids = bot.GetAssignedLane() === Lane.Top ? [Tower.Top1, Tower.Top2, Tower.Top3] : [Tower.Bot1, Tower.Bot2, Tower.Bot3];
    for (const id of ids) {
        const t = GetTower(bot.GetTeam(), id);
        if (t !== null && t !== undefined && t.IsAlive()) return t.GetLocation();
    }
    return undefined;
}

/**
 * The reading wants a pull: the clash is forecast beyond the lane's target point (`target`, from our T1) and is not coming
 * in. Lane aggro feeds on the same target and the wave hold meets their wave at it, so all three aim at one meeting point.
 */
export function Wanted(g: LanePush.WaveGone | undefined, target: number): boolean {
    if (g === undefined || g.own === undefined) return false;
    return g.own > target + SETTINGS.WantPast && g.ep <= SETTINGS.PowerRatio * g.ap;
}

/**
 * Two slots pull the same wave. A slot is a float from the camp's timing, which is re-read at every timing read since the
 * neutral speed is (neutral-speed-at-order), so the same slot drifts by a fraction of a second between frames; comparing the
 * floats restarted a cancelled pull on its own slot (lctl9: 11 duplicate pull_job lines in 5 games, none in lctl4). Keyed by
 * the pulled wave instead.
 */
export function SameWave(a: number | undefined, b: number): boolean {
    return a !== undefined && PulledSpawn(a) === PulledSpawn(b);
}

/** The wave a slot pulls: ours spawned on the last 30 s at or before the slot (aggro comes after the spawn). */
export function PulledSpawn(slot: number): number {
    return math.floor((slot - 1) / GameRules.WAVE_EVERY) * GameRules.WAVE_EVERY;
}

/** The nearest enemy hero to the pull site (stand or meet point), logged as `se`: no gate reads it. */
function siteEnemy(p: Plan): number | undefined {
    let near: number | undefined;
    for (const e of GetUnitList(UnitType.EnemyHeroes)) {
        if (!e.IsAlive() || e.IsIllusion()) continue;
        const d = math.min(GetUnitToLocationDistance(e, p.stand), GetUnitToLocationDistance(e, p.meet));
        if (near === undefined || d < near) near = d;
    }
    return near;
}

/** OHA's own action holds the hero (rune_job's check: a queued TP, a cast or channel). */
function acting(bot: Unit): boolean {
    return bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility();
}

function campFields(s: CampState): Telemetry.Fields<"choice" | "pull_job"> {
    const r0 = (x: number | undefined) => (x !== undefined ? math.floor(x + 0.5) : undefined);
    return [
        ["cn", s.n],
        ["cs", s.seen],
        ["chp", r0(s.hp)],
        ["cv", s.vis ? 1 : 0],
        ["cfv", s.full === undefined ? undefined : s.full ? 1 : 0],
        ["cdmg", r0(s.dmg)],
        ["php", r0(s.php)],
        ["se", r0(s.se)],
        ["rn", s.known?.n],
        ["rsrc", s.known?.src],
        ["rage", s.known?.age],
        ["rh", s.known?.held],
    ];
}

/** `slot` the plan's hit second, so the line joins its `pull_job` line. */
function choiceLine(bot: Unit, d: Decision, slot: number, go: boolean, why: string | undefined, camp: CampState, src = "own"): void {
    const r = d.reading;
    const r1 = (x: number | undefined) => (x !== undefined ? math.floor(x + 0.5) : undefined);
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "pull"],
        ["go", go ? 1 : 0],
        ["want", d.want ? 1 : 0],
        ["why", why],
        ["src", src],
        ["lane", bot.GetAssignedLane()],
        ["slot", slot],
        ["st", r?.state],
        ["q", r !== undefined ? math.floor(r.q * 100 + 0.5) / 100 : undefined],
        ["mv", r1(r?.move)],
        ["own", r1(r?.own)],
        ["tgt", LanePush.TargetOf(bot.GetAssignedLane())],
        ["tw", r !== undefined ? (r.tower ? 1 : 0) : undefined],
        ["pa", r1(d.gone?.own)],
        ["ap", r1(d.gone?.ap)],
        ["ep", r1(d.gone?.ep)],
        ["pw", d.gone?.pw],
        ["rule", d.rule],
        ["ms", r?.ms],
        ...campFields(camp),
    ]);
}

function jobLine(bot: Unit, p: Pull, phase: string, why: string, cut?: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "pull"],
        ["phase", phase],
        ["why", why],
        ["host", p.host],
        ...(phase === "end" ? ([["hit", p.hit === true ? 1 : 0]] as Telemetry.Fields<"job">) : []),
        ["cut", cut],
        ["hp", cut === "retreat" ? math.floor((bot.GetHealth() / math.max(1, bot.GetMaxHealth())) * 100 + 0.5) / 100 : undefined],
    ]);
}

/**
 * Plan s4 step 8: the decider does not tell a row it was cut off, so a pull the engine ends because the host mode lost the
 * hero names what took it: `retreat` when the decider let go for stock's retreat or the retreat mode holds the hero (OHA's
 * latch outbids the hold), else the mode that does.
 */
function cutBy(bot: Unit, r: Lib.Result): string | undefined {
    if (r.success || r.reason !== "preempted") return undefined;
    if (Decider.LetGo(bot) || bot.GetActiveMode() === BotMode.Retreat) return "retreat";
    return HDebug.ModeName(bot.GetActiveMode());
}

function finish(bot: Unit, p: Pull, end: Lib.Result, label: string | undefined): void {
    running[bot.GetPlayerID()] = undefined;
    const endWhy = end.success ? end.message ?? "ok" : `${end.reason}${end.message !== undefined ? ":" + end.message : ""}`;
    // Once the stay began the pull itself ended ok: the line's res and why are the pull's, the stay's end is `st`.
    const r: Lib.Result = p.stayAt !== undefined ? { success: true, reason: "ok" } : end;
    const why = r.success ? "ok" : endWhy;
    const cut = cutBy(bot, end);
    jobLine(bot, p, "end", why, p.stayAt !== undefined ? undefined : cut);
    const r1 = (x: number) => math.floor(x * 10) / 10;
    const fields: Telemetry.Fields<"pull_job"> = [
        ["pid", bot.GetPlayerID()],
        ["pos", LaneConfig.PositionOf(bot)],
        ["lane", bot.GetAssignedLane()],
        ["camp", p.plan.camp.campIdx],
        ["slot", p.plan.slot],
        ["res", r.success ? "ok" : "fail"],
        ["why", why],
        ["label", label ?? p.label],
        ["div", share(p)],
        ["n", p.wave],
        ["left", r1(p.left)],
        ["away", r1(DotaTime() - p.left)],
        ["died", bot.IsAlive() ? 0 : 1],
        ["hit", p.hit === true ? 1 : 0],
        ["idle", p.idle],
        ["wd", p.near !== undefined ? math.floor(p.near + 0.5) : undefined],
        ["nn", p.neutrals],
        ...campFields(p.start),
        ["sh", math.floor((p.hitAt - p.plan.slot) * 10 + 0.5) / 10],
        ["s0", p.timer.first !== undefined ? math.floor(p.timer.first * 10 + 0.5) / 10 : undefined],
        ["lv", p.timer.reads],
        ["nsp", p.timer.timing.neutralSpeed !== undefined ? math.floor(p.timer.timing.neutralSpeed + 0.5) : undefined],
        ["hr", p.timer.hit !== undefined ? "geo" : "plan"],
        ["hc", p.timer.n],
        ["hn", p.timer.next],
        ["hb", p.timer.back],
        ["ht", p.hat],
        ["g4", p.g4],
        ["gh", p.gh !== undefined ? math.floor(p.gh + 0.5) : undefined],
        ["na", p.na],
        ["gu", p.gu],
        ["gd", p.gd !== undefined ? math.floor(p.gd + 0.5) : undefined],
        ["wa", p.wa],
        ["nm", p.nm],
        ["shs", p.shs !== undefined ? math.floor(p.shs * 10 + 0.5) / 10 : undefined],
        ["shh", p.shh !== undefined ? math.floor(p.shh * 100 + 0.5) / 100 : undefined],
        ["st", p.stayAt !== undefined ? (cut !== undefined ? `${endWhy}:${cut}` : endWhy) : undefined],
        ["ss", p.stayAt !== undefined ? r1(DotaTime() - p.stayAt) : undefined],
        ["sdt", p.sdt],
        ["sdk", p.sdk],
        ["slt", p.slt],
        ["slk", p.slk],
    ];
    if (!r.success) {
        Telemetry.Event("pull_job", fields);
        return;
    }
    const now = DotaTime();
    trailing[bot.GetPlayerID()] = { pull: p, fields, until: math.max(now, PullTiming.WaveAt(p.timer) ?? now) + SETTINGS.TrailSec };
}

function share(p: Pull): number {
    return p.wave > 0 ? math.floor((p.peak / p.wave) * 100 + 0.5) / 100 : 0;
}

/** Samples a finished pull's wave until its trail ends, then writes its line with `dt`. A new pull's start writes it first. */
function trail(bot: Unit, flush: boolean): void {
    const pid = bot.GetPlayerID();
    const tr = trailing[pid];
    if (tr === undefined) return;
    if (!flush && DotaTime() < tr.until) {
        sampleWave(bot, tr.pull);
        watchLine(bot, tr.pull, "trail");
        return;
    }
    trailing[pid] = undefined;
    Telemetry.Event("pull_job", [...tr.fields, ["dt", share(tr.pull)]]);
}

/** Our lane creeps within `radius` of the meet point or of the camp origin: a wave the neutrals walk back from follows them
 *  into the camp and fights there (pw1: the Radiant safe small camp sits about 1100 from its meet point, so a watch of the
 *  meet point alone logged those waves as never diverted). */
function laneCreepsNear(p: Plan, radius: number): Unit[] {
    const out: Unit[] = [];
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (!c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        if (GetUnitToLocationDistance(c, p.meet) <= radius || GetUnitToLocationDistance(c, p.spawner.location) <= radius) out.push(c);
    }
    return out;
}

function onNeutral(c: Unit): boolean {
    const t = c.GetAttackTarget();
    return t !== undefined && t !== null && t.GetTeam() === Team.Neutral;
}

/** During lead and watch: our wave's largest diverted share (camp_jobs' sample: the wave is counted once the first of it
 *  is seen on a neutral). */
function sample(bot: Unit, p: Pull): void {
    if (p.label !== "lead" && p.label !== "watch") return;
    watchLine(bot, p, p.label);
    const now = DotaTime();
    if (p.sampledAt !== undefined && now - p.sampledAt < SETTINGS.WatchEvery) return;
    p.sampledAt = now;
    const radii = LaneConfig.Settings().Radii;
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (!c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        const d = GetUnitToLocationDistance(c, p.plan.meet);
        if (p.near === undefined || d < p.near) p.near = d;
    }
    let nn = 0;
    for (const u of GetUnitList(UnitType.NeutralCreeps)) if (u.IsAlive() && GetUnitToLocationDistance(u, p.plan.meet) <= radii.MeetWatch) nn++;
    p.neutrals = math.max(p.neutrals, nn);
    countDiverted(p);
    diag(bot, p, trackTagged);
}

function sampleWave(bot: Unit, p: Pull): void {
    const now = DotaTime();
    if (p.sampledAt !== undefined && now - p.sampledAt < SETTINGS.WatchEvery) return;
    p.sampledAt = now;
    countDiverted(p);
    diag(bot, p, trackTagged);
}

/** A diagnostics error is printed once per pull, so a missing field is not read as "never happened" (review L5). */
function diag(bot: Unit, p: Pull, fn: (this: void, bot: Unit, p: Pull) => void): void {
    const [ok, err] = pcall(fn, bot, p);
    if (ok || p.diagErr === true) return;
    p.diagErr = true;
    print(`[Humaniser] pull diag error slot=${p.plan.slot}: ${tostring(err)}`);
}

/** At the hit: the camp's neutrals (in its box, or on the puller within TagRadius), so the watch follows that camp only. */
function tagCamp(bot: Unit, p: Pull): void {
    p.hat = DotaTime();
    const tagged = CampStateOf(p.plan.spawner).units;
    for (const u of GetUnitList(UnitType.NeutralCreeps)) {
        if (!u.IsAlive() || tagged.indexOf(u) >= 0 || GetUnitToUnitDistance(u, bot) > SETTINGS.TagRadius) continue;
        if (u.GetAttackTarget() === bot) tagged.push(u);
    }
    p.tagged = tagged;
    p.peaks = new Map();
    p.starts = new Map();
    for (const u of tagged) {
        const l = u.GetLocation();
        if (l !== undefined && l !== null) p.starts.set(u, l);
    }
    p.early = [];
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (c.IsAlive() && LanePush.IsLaneCreep(c.GetUnitName()) && GetUnitToLocationDistance(c, p.plan.meet) <= SETTINGS.ArriveR) p.early.push(c);
    }
}

interface TaggedState {
    alive: number;
    onPuller: number;
    onCreep: number;
    nearest?: number;
    farthest?: number;
}

/** CANDIDATE(stale): same as ally_last_hit's. A tagged neutral that died is freed, and IsAlive on its handle throws. */
function stale(u: Unit): boolean {
    return ((u as any).IsNull !== undefined && u.IsNull()) || !u.IsAlive();
}

function taggedState(bot: Unit, p: Pull, ours: Unit[]): TaggedState {
    const s: TaggedState = { alive: 0, onPuller: 0, onCreep: 0 };
    for (const u of p.tagged ?? []) {
        if (stale(u)) continue;
        s.alive++;
        const k = targetKind(bot, u.GetAttackTarget());
        if (k === "p") s.onPuller++;
        else if (k === "c") s.onCreep++;
        let d = ours.length > 0 ? math.huge : GetUnitToLocationDistance(u, p.plan.meet);
        for (const c of ours) d = math.min(d, GetUnitToUnitDistance(u, c));
        if (s.nearest === undefined || d < s.nearest) s.nearest = d;
        const h = GetUnitToLocationDistance(u, p.plan.spawner.location);
        if (s.farthest === undefined || h > s.farthest) s.farthest = h;
    }
    return s;
}

function trackTagged(bot: Unit, p: Pull): void {
    const now = DotaTime();
    if (p.wa === undefined && p.early !== undefined) {
        for (const c of GetUnitList(UnitType.AlliedCreeps)) {
            if (!c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName()) || p.early.indexOf(c) >= 0) continue;
            if (GetUnitToLocationDistance(c, p.plan.meet) <= SETTINGS.ArriveR) {
                p.wa = now;
                break;
            }
        }
    }
    if (p.tagged === undefined || p.peaks === undefined) return;
    const s = taggedState(bot, p, laneCreepsNear(p.plan, LaneConfig.Settings().Radii.MeetWatch));
    if (s.farthest !== undefined && (p.gh === undefined || s.farthest > p.gh)) p.gh = s.farthest;
    if (p.na === undefined && s.nearest !== undefined && s.nearest <= SETTINGS.Acquire && s.alive > 0) p.na = now;
    // Only neutrals that left their camp count (box members that never followed stay out); give-up is every one of them
    // back HomeMargin from its own peak with no attack target at all.
    let left = 0;
    let home = 0;
    for (const u of p.tagged) {
        if (stale(u)) continue;
        const s0 = p.starts?.get(u);
        if (p.nm === undefined && s0 !== undefined && GetUnitToLocationDistance(u, s0) >= SETTINGS.Moved) p.nm = now;
        const h = GetUnitToLocationDistance(u, p.plan.spawner.location);
        const peak = math.max(p.peaks.get(u) ?? 0, h);
        p.peaks.set(u, peak);
        if (peak <= SETTINGS.Left) continue;
        if (p.g4 === undefined) p.g4 = now;
        left++;
        const t = u.GetAttackTarget();
        if (h < peak - SETTINGS.HomeMargin && (t === undefined || t === null)) home++;
    }
    if (p.gu === undefined && left > 0 && home === left) {
        p.gu = now;
        p.gd = s.nearest;
    }
}

function countDiverted(p: Pull): void {
    const radii = LaneConfig.Settings().Radii;
    let n = 0;
    for (const c of laneCreepsNear(p.plan, radii.MeetWatch)) if (onNeutral(c)) n++;
    if (n === 0) return;
    if (p.wave === 0) p.wave = math.max(1, laneCreepsNear(p.plan, radii.WaveSize).length);
    p.peak = math.max(p.peak, math.min(n, p.wave));
}

function targetKind(bot: Unit, t: Unit | null | undefined): string {
    if (t === undefined || t === null) return "x";
    if (t === bot) return "p";
    if (t.IsHero()) return "h";
    if (t.IsCreep()) return "c";
    return "o";
}

/**
 * One `ev=pull_watch` sample: what our creeps near the meet point or the camp origin attack, and where the neutrals are and what they attack
 * (slice support-lane open item: waves at the meet point with neutrals near that never hit one). `nd`, `nh`, `nt` describe
 * the neutral closest to any of our creeps near the meet point (or to the meet point when none is), counted or not in `nn`.
 */
function watchLine(bot: Unit, p: Pull, ph: string): void {
    const now = DotaTime();
    if (p.watchedAt !== undefined && now - p.watchedAt < SETTINGS.WatchLogEvery) return;
    p.watchedAt = now;
    const radii = LaneConfig.Settings().Radii;
    const meet = p.plan.meet;
    const ours = laneCreepsNear(p.plan, radii.MeetWatch);
    let won = 0;
    let whe = 0;
    let wcr = 0;
    let wid = 0;
    let wd: number | undefined;
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (!c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        const d = GetUnitToLocationDistance(c, meet);
        if (wd === undefined || d < wd) wd = d;
    }
    for (const c of ours) {
        const t = c.GetAttackTarget();
        if (t === undefined || t === null) wid++;
        else if (t.GetTeam() === Team.Neutral) won++;
        else if (t.IsHero()) whe++;
        else wcr++;
    }
    let nn = 0;
    let ntp = 0;
    let ntc = 0;
    let ntx = 0;
    let best: Unit | undefined;
    let nd = math.huge;
    for (const u of GetUnitList(UnitType.NeutralCreeps)) {
        if (!u.IsAlive()) continue;
        let d = GetUnitToLocationDistance(u, meet);
        if (d > SETTINGS.WatchNeutralSearch) continue;
        if (d <= radii.WaveSize) {
            nn++;
            const k = targetKind(bot, u.GetAttackTarget());
            if (k === "p") ntp++;
            else if (k === "c") ntc++;
            else if (k === "x") ntx++;
        }
        for (const c of ours) d = math.min(d, GetUnitToUnitDistance(u, c));
        if (d < nd) {
            nd = d;
            best = u;
        }
    }
    const r0 = (x: number | undefined) => (x !== undefined ? math.floor(x + 0.5) : undefined);
    Telemetry.Event("pull_watch", [
        ["pid", bot.GetPlayerID()],
        ["slot", p.plan.slot],
        ["ph", ph],
        ["wc", ours.length],
        ["won", won],
        ["whe", whe],
        ["wcr", wcr],
        ["wid", wid],
        ["wd", r0(wd)],
        ["nn", nn],
        ["ntp", ntp],
        ["ntc", ntc],
        ["ntx", ntx],
        ["nd", best !== undefined ? r0(nd) : undefined],
        ["nh", best !== undefined ? r0(GetUnitToLocationDistance(best, p.plan.spawner.location)) : undefined],
        ["nt", best !== undefined ? targetKind(bot, best.GetAttackTarget()) : undefined],
        ["pd", bot.IsAlive() ? r0(GetUnitToLocationDistance(bot, meet)) : undefined],
        ["shd", p.shs !== undefined ? 1 : undefined],
        ...taggedFields(bot, p, ours),
    ]);
}

function taggedFields(bot: Unit, p: Pull, ours: Unit[]): Telemetry.Fields<"pull_watch"> {
    if (p.tagged === undefined) return [];
    const s = taggedState(bot, p, ours);
    const r0 = (x: number | undefined) => (x !== undefined ? math.floor(x + 0.5) : undefined);
    return [
        ["tn", s.alive],
        ["tp", s.onPuller],
        ["tc", s.onCreep],
        ["td", r0(s.nearest)],
        ["th", r0(s.farthest)],
    ];
}

function verbCamp(p: Plan): JobVerbs.Camp {
    const radii = LaneConfig.Settings().Radii;
    const o = p.spawner.location;
    const d = math.sqrt((p.stand.x - o.x) ** 2 + (p.stand.y - o.y) ** 2);
    // states/camp_job's campOf: blind at the stand point, step in to StandApproach from the origin before the hit.
    const approach =
        d > radii.StandApproach + radii.JobArrive ? Vector(o.x + ((p.stand.x - o.x) * radii.StandApproach) / d, o.y + ((p.stand.y - o.y) * radii.StandApproach) / d, o.z) : undefined;
    return {
        stand: p.stand as unknown as Lib.Vec,
        approach: approach as unknown as Lib.Vec | undefined,
        box: { min: p.spawner.min as unknown as Lib.Vec, max: p.spawner.max as unknown as Lib.Vec },
        origin: o as unknown as Lib.Vec,
        margin: radii.BoxMargin,
        search: radii.NeutralSearch,
    };
}

function verbPlan(bot: Unit, pull: Pull, aggroAt: number): JobVerbs.PullPlan {
    const p = pull.plan;
    const s = LaneConfig.Settings();
    const camp = verbCamp(p);
    // The hit follows the wave until the order goes out (the verb reads `earlier` every frame of the wait).
    camp.earlier = () => {
        pull.hitAt = PullTiming.Read(pull.timer, DotaTime());
        return aggroAt - pull.hitAt;
    };
    return {
        bail: () => bailPoint(bot) as unknown as Lib.Vec | undefined,
        bailFor: SETTINGS.BailFor,
        camp,
        aggroAt,
        lead: p.lead as unknown as Lib.Vec[],
        watchAt: () => shedPoint(bot, pull) as unknown as Lib.Vec | undefined,
        watchSec: s.Timing.WatchSec,
        watchUntil: () => {
            const w = PullTiming.WaveAt(pull.timer);
            return w !== undefined ? w + s.PullTiming.WatchAfterWave : undefined;
        },
        leadDeadline: aggroAt + s.Timing.JobMaxAfterAggro,
        arrive: s.Radii.JobArrive,
        startLate: s.Timing.JobStartLate,
        approachLead: s.Timing.StandApproachLead,
        noCampAfter: s.Timing.NoCampAfter,
        confirmFor: s.Timing.AggroConfirm,
    };
}

/** The stay's camp clear: the camp's damage on the puller over StayClearSeconds must leave it StayClearReserve of max HP. */
function stayClears(bot: Unit, p: Pull): boolean {
    const s = CampStateOf(p.plan.spawner);
    if (s.n === 0) return false;
    return bot.GetHealth() - CampDamage(bot, s, p.plan.spawner.type, SETTINGS.StayClearSeconds) >= bot.GetMaxHealth() * SETTINGS.StayClearReserve;
}

function* stay(bot: Unit, p: Pull, hooks: JobVerbs.JobHooks): Lib.TaskBody {
    p.stayAt = DotaTime();
    return yield* Tasks.Jobs()!.stayCamp(
        bot as unknown as Lib.TaskUnit,
        {
            at: p.plan.spawner.location as unknown as Lib.Vec,
            deadline: p.stayAt + SETTINGS.StayMax,
            clearLeft: () => stayClears(bot, p),
            onAttempt: (kind, r) => {
                if (kind === "deny") {
                    p.sdt = (p.sdt ?? 0) + 1;
                    if (r.success) p.sdk = (p.sdk ?? 0) + 1;
                } else {
                    p.slt = (p.slt ?? 0) + 1;
                    if (r.success) p.slk = (p.slk ?? 0) + 1;
                }
            },
        },
        hooks
    );
}

function* body(bot: Unit, p: Pull, aggroAt: number, ctx: Lib.Ctx): Lib.TaskBody {
    const hooks: JobVerbs.JobHooks = {
        label: (l) => {
            ctx.label(l);
            p.label = l;
            // Diagnostics only: an error here must not end the pull (review 2026-11-04-pull-diag L3).
            if (l === "lead" && p.hat === undefined) diag(bot, p, tagCamp);
        },
        urgent: ctx.urgent,
    };
    const r = yield* Tasks.Jobs()!.pull(bot as unknown as Lib.TaskUnit, verbPlan(bot, p, aggroAt), hooks);
    if (!r.success || !Ours.On("SupportPullStay")) return r;
    return yield* stay(bot, p, hooks);
}

interface Due {
    p: Plan;
    timer: PullTiming.CreepTimer;
    hitAt: number;
    walk: number;
    d: Decision;
}

/**
 * The slot this puller would have to leave for now, with the lane's read of it: undefined before the leave time and once
 * the slot's wave is handled. The lane is read once per wave, on the first frame at or after the leave time.
 */
function dueSlot(bot: Unit, now: number): Due | undefined {
    const pid = bot.GetPlayerID();
    const p = planFor(bot, now);
    if (p === undefined || SameWave(handled[pid], p.slot)) return undefined;
    const walk = travel(bot, p);
    // Once our wave is out its creeps time the hit (pull_timing's CreepTimer); the leave time, the late check and the hit all
    // use that second (pw2: 12 starts planned against the slot failed `late` while still walking, the wave being early).
    let timer = timers[pid];
    if (timer === undefined || !SameWave(timer.slot, p.slot)) {
        timer = PullTiming.Timer(p.timing, p.slot, LaneConfig.Settings().PullTiming.FullPast);
        timers[pid] = timer;
    }
    const hitAt = PullTiming.Read(timer, now);
    if (now < hitAt - walk - SETTINGS.Early) return undefined;
    let d = decided[pid];
    if (d === undefined || !SameWave(d.slot, p.slot)) {
        const reading = LanePush.Read(bot.GetTeam(), bot.GetAssignedLane());
        const gone = LanePush.WaveGoneNow(bot.GetTeam(), bot.GetAssignedLane(), PulledSpawn(p.slot), p.slot + SETTINGS.ArriveAfter);
        const tgt = LanePush.TargetOf(bot.GetAssignedLane());
        // A drill that forces the pull (humaniser/drill.ts `pull`): the rep of the pulled wave decides, input on pulls (rule
        // `drill`), a control rep or a wave before the first rep does not (`why=drill`). The pull's own gates below still apply.
        const forced = Drill.ForcedAt("pull", PulledSpawn(p.slot));
        if (forced !== undefined) d = { slot: p.slot, want: forced === "on", reading, gone, rule: forced === "on" ? "drill" : undefined, drill: true };
        else {
            const byNew = Wanted(gone, tgt);
            d = { slot: p.slot, want: byNew, reading, gone, rule: byNew ? "new" : undefined };
        }
        decided[pid] = d;
        gateWhy[pid] = undefined;
    }
    return { p, timer, hitAt, walk, d };
}

/**
 * Plan s5's denominator in the arm that does not pull: for a lane's puller whose pull is switched off, the same read of each
 * slot at the same leave time, written as the line the row writes (`go=0 why=off src=shadow`). It reads and logs; nothing is
 * ordered or started. A shadowed slot is where a puller standing where stock left it would have had to leave; the on arm's
 * puller may stand elsewhere, so the two arms' slots match by wave, not by second.
 */
export function Shadow(bot: Unit): void {
    logSeeds();
    if (!Telemetry.IsEnabled() || !IsPuller(bot) || rowOn(bot) || Drill.Held(bot)) return;
    if (!LaneConfig.InLaningPhase() || !bot.IsAlive()) return;
    watch(bot);
    const due = dueSlot(bot, DotaTime());
    if (due === undefined) return;
    handled[bot.GetPlayerID()] = due.p.slot;
    const camp = CampStateOf(due.p.spawner);
    camp.known = Known(due.p.spawner);
    choiceLine(bot, due.d, due.p.slot, false, "off", camp, "shadow");
}

/** The mode the decider hosts its rows in: the engine steps the pull's task under it. */
const HOST = BotMode.Farm;


/**
 * The record's look at the lane's camp while no pull of this hero runs (a running pull's walk looks in Step; after its hit
 * the neutrals are out of the box). Full when the hero stands within CampReadNear of the camp's origin. Both arms, so the
 * shadow line carries the same record.
 */
function watch(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    if (running[pid] !== undefined || now - (watchedAt[pid] ?? -math.huge) < SETTINGS.RecordEvery) return;
    watchedAt[pid] = now;
    const sp = SpawnerFor(bot);
    if (sp === undefined) return;
    NoteSighting(sp, CampStateOf(sp), bot.IsAlive() && GetUnitToLocationDistance(bot, sp.location) <= SETTINGS.CampReadNear);
}

/** The spawner of the lane's pull camp (the pull's and the stack row's camp). */
export function SpawnerFor(bot: Unit): Camps.Spawner | undefined {
    const camp = campFor(bot);
    return camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
}

/**
 * Why a wanted pull may not start now. Danger is the shared read's answer where the hero stands; a hero Valve's attack or a
 * retreat holds is left to it. The camp's damage is the pull's own check, since the shared read prices no neutral damage.
 * The old job's HP floor, hero-hit check, enemy-site rule and partner check are gone: once started, stopping is the
 * decider's (it lets go when stock would retreat) and the verb's bail.
 */
function startBlock(bot: Unit, camp: CampState, now: number, hitAt: number): string | undefined {
    const gate = CampGate(camp, now, hitAt);
    if (gate !== undefined) return gate;
    if (SafeGather.At(bot, bot.GetLocation(), { who: "pull_start" }).level === "deadly") return "enemy-near";
    const mode = bot.GetActiveMode();
    if (mode === BotMode.Attack || mode === BotMode.Retreat) return "busy";
    return campDmgGate(bot, camp.dmg!) ?? (acting(bot) ? "acting" : undefined);
}

/**
 * The row's `applies`, asked every scoring round: true while a pull runs or as one starts. The lane is read once per slot at
 * the leave time; a wanted pull then waits on `startBlock` until it could no longer reach the camp by the hit's late limit.
 * A pull the decider let go of (stock's retreat) or another mode took is ended by the engine once the host has been without
 * the hero for `preemptAfter`; its wave is handled, so it does not start again.
 */
let seedsLogged = false;

/** Once a game, the seeded pull camps' resolution (`ev=pull_camp_seed`), once the spawner list is in. */
function logSeeds(): void {
    if (seedsLogged || !Telemetry.IsEnabled()) return;
    const reads = Camps.SeedReads();
    if (reads.length === 0) return;
    seedsLogged = true;
    for (const r of reads) Telemetry.Event("pull_camp_seed", [["key", r.key], ["idx", r.idx], ["td", r.td], ["ld", r.ld], ["ok", r.ok ? 1 : 0]]);
}

function rowApplies(bot: Unit): boolean {
    logSeeds();
    if (!rowOn(bot)) return false;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    const cur = running[pid];
    if (cur !== undefined) {
        if (bot.WasRecentlyDamagedByAnyHero(HERO_HIT_WITHIN)) cur.hit = true;
        return true;
    }
    trail(bot, false);
    if (Tasks.Jobs() === undefined || !LaneConfig.InLaningPhase() || !bot.IsAlive()) return false;
    watch(bot);
    const now = DotaTime();
    const due = dueSlot(bot, now);
    if (due === undefined) return false;
    const { p, timer, hitAt, walk, d } = due;
    const camp = CampStateOf(p.spawner);
    camp.known = Known(p.spawner);
    const done = (go: boolean, why: string | undefined) => {
        handled[pid] = p.slot;
        gateWhy[pid] = undefined;
        choiceLine(bot, d, p.slot, go, why, camp);
    };
    if (!d.want) {
        done(false, d.drill === true ? "drill" : d.reading === undefined ? "no-read" : "lane");
        return false;
    }
    // Only a strong camp takes the wave (families proposal s5); under the bar the stack row builds it. A camp seen empty or
    // with one neutral says so (CampGate, in the start check).
    if (camp.known.n < SETTINGS.StrongAt && CampGate(camp, now, hitAt) === undefined) {
        done(false, "weak");
        return false;
    }
    camp.dmg = CampDamage(bot, camp, p.spawner.type);
    camp.php = bot.GetHealth();
    camp.se = siteEnemy(p);
    const why = startBlock(bot, camp, now, hitAt);
    if (now + walk > hitAt + LaneConfig.Settings().Timing.JobStartLate) {
        done(false, gateWhy[pid] ?? why ?? "late");
        return false;
    }
    if (why !== undefined) {
        gateWhy[pid] = why;
        return false;
    }
    const aggroAt = hitAt;
    trail(bot, true);
    const pull: Pull = { plan: p, left: now, host: HOST, wave: 0, peak: 0, neutrals: 0, hitAt, timer, start: camp };
    const ok = Tasks.Start(bot, { name: "pull", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r, info) => finish(bot, pull, r, info.label) }, (ctx: Lib.Ctx) =>
        body(bot, pull, aggroAt, ctx)
    );
    if (!ok) {
        done(false, "refused");
        return false;
    }
    done(true, undefined);
    running[pid] = pull;
    jobLine(bot, pull, "start", "trigger");
    return true;
}

/** The row's verb: one frame of the pull; true once it has ended. */
function rowStep(bot: Unit): boolean {
    Step(bot);
    return running[bot.GetPlayerID()] === undefined;
}

/** The decider's row (registered in index.ts, so the decider imports no row). */
export const ROW: Decider.Row = { name: "pull", applies: rowApplies, step: rowStep };

function Step(bot: Unit): boolean {
    const p = running[bot.GetPlayerID()];
    if (p === undefined) return false;
    // Before the hit the walk may bring the camp into sight: stop there rather than hit an empty camp or one it cannot take.
    if (p.label === undefined || p.label === "travel" || p.label === "wait") {
        const s = CampStateOf(p.plan.spawner);
        s.dmg = CampDamage(bot, s, p.plan.spawner.type);
        s.php = bot.GetHealth();
        const now = DotaTime();
        const close = GetUnitToLocationDistance(bot, p.plan.stand) <= SETTINGS.CampReadNear;
        NoteSighting(p.plan.spawner, s, close);
        // On arrival the puller's own look is the record (a full view): a camp under the bar is not pulled.
        const gate = CampGate(s, now, p.hitAt) ?? (readsHit(s, now, p.hitAt) && Known(p.plan.spawner).n < SETTINGS.StrongAt ? "weak" : undefined);
        // `one`/`empty`/`weak` count only near the stand (CampReadNear) and must hold CampLowHold s (the camp fills in as it
        // comes into sight); camp damage ends it at once.
        if (gate === undefined || !close) p.low = undefined;
        else if (p.low === undefined || p.low.why !== gate) p.low = { why: gate, at: now };
        // The hold shrinks to the time left before the hit: a puller reaching the ring late still reads the camp before it
        // hits (review 2026-11-08-lane-drills M3: ldr17's cancels fell 2 s before to 0.8 s after the slot).
        const hold = math.min(SETTINGS.CampLowHold, p.hitAt - now);
        const why = (p.low !== undefined && now - p.low.at >= hold ? p.low.why : undefined) ?? campDmgGate(bot, s.dmg);
        if (why !== undefined) {
            // The pull_job line then carries the camp that cancelled it, not the one at the start.
            p.start = s;
            End(bot, why);
            return false;
        }
    }
    sample(bot, p);
    return Tasks.Step(bot, HOST);
}

export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

function End(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}

export function NoteIdleHeld(bot: Unit): void {
    const p = running[bot.GetPlayerID()];
    if (p !== undefined) p.idle = (p.idle ?? 0) + 1;
}
