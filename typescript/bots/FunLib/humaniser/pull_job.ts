/**
 * The pull (slice support-lane, switch Ours.SupportPull, KR S.3): a pos4/pos5 takes our wave into its lane's first pull camp
 * when the lane push reading wants it, then comes back to lane. The job chooser hosts it and decides when it may start; this
 * module reads the lane once per pull slot (`ev=choice kind=pull`), plans the pull from the camp data (`camps`,
 * `pull_timing`), walks it with the job verb `pull` and logs one `ev=pull_job` line per started pull.
 */
import * as GameRules from "bots/FunLib/humaniser/game_rules";
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Calendar from "bots/FunLib/humaniser/calendar";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";
import * as Drill from "bots/FunLib/humaniser/drill";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

// All `judgement` (slice file, Decisions), except where a source is named.
export const SETTINGS = {
    /** A camp read `one` or `empty` on the walk ends the pull only once it has held this long (`judgement`): a camp coming into
     *  sight shows its neutrals over a few frames, since the API returns no fogged ones (drill pull ldr6: 5 of 9 pulls
     *  cancelled `one` on the first sight of a freshly spawned full camp). A four-corner visibility rule was tried first
     *  and never read true (ldr11, ldr12: every pull walked into an empty camp). */
    CampLowHold: 1.5,
    /** ... and only once the puller is within this of its stand point, so its own vision covers the camp (`judgement`; ldr14:
     *  3 of 9 pulls on a fresh camp still cancelled `one` after the hold, 3-6 s into the walk). */
    CampReadNear: 500,
    /** Rank against the hero's other jobs: below the stack (0.92) and the rune trip (0.85 pos5 / 0.95 pos4 rank above at their
     *  times through their claims). */
    Priority: 0.9,
    /** Slice lane-control 3: the rank while the lane's decision wants this pull and it fits before the next departure (above
     *  the pos4 rune trip's 0.95 and the stack's 0.92). PriorityEvery: how often it is re-read. Take: a pull's end after its
     *  hit second for the calendar (the job ends 3 s after the wave is due at the camp, about 7 s after the hit). All
     *  `judgement`. */
    FitPriority: 0.96,
    PriorityEvery: 0.5,
    Take: 12,
    /** Leave this long before the walk alone would arrive, so the bot stands at the camp before the hit. */
    Early: 2,
    /** Walking paths run longer than the straight line (rune_job's PathFactor). */
    PathFactor: 1.2,
    /** A pull is wanted when, with the pulled wave gone, the clash ArriveAfter s after the slot (the current wave's fight
     *  resolved) is forecast more than WantPast beyond the lane's target point (LanePush TargetOf), and their creeps in lane
     *  have at most PowerRatio times our HP (slice support-lane, Decision 06/11/2026; ArriveAfter and PowerRatio
     *  `judgement`, scored offline on the banked slots before the change: the slice file). A lane coming in (IN) is no
     *  refusal: the pull keeps our next wave from dying under their tower. With our lane core there to hold their wave
     *  (CoreToHold) the earlier rule also wants it (OldWanted; user 06/11/2026: the pull and the hold work in tandem, the
     *  hold catching the overshoot the forecast shows with no hero in it). */
    WantPast: 150,
    ArriveAfter: 12,
    PowerRatio: 1.2,
    /** The lane partner is under threat: HP share below PartnerHp with an enemy hero within PartnerRadius, or PartnerGank
     *  enemy heroes within it. */
    PartnerHp: 0.5,
    PartnerRadius: 900,
    PartnerGank: 3,
    /** No start with an enemy hero within SiteEnemy of the stand point or the meet point (`why=enemy-site`). Banked `ok`
     *  off-lane pulls with one under 1,200 of the pull site at the start: 5 of 19 hit by a hero, 4 diverted; 1,200 or more:
     *  6 of 36 hit, 16 diverted (04/11/2026, the user's ptm1_A 4:21: a pull into an enemy offlaner). `judgement`. */
    SiteEnemy: 1200,
    /** Our creeps within MeetWatch of the meet point or of the camp origin are watched; a creep attacking a neutral is
     *  diverted. Wave size: our creeps within WaveSize of either when the first one is seen diverted (camp_jobs' sample,
     *  LaneConfig Radii). */
    WatchEvery: 0.25,
    /** After a job that ended ok, keep sampling the wave this long past the later of the job end and the wave's due time:
     *  the job ends 3 s after the wave is due, while its later creeps are still reaching the neutrals (sp2: pulls logged at
     *  div 0.25 moved the lane back the most, `eq` -1.65 in 30 s, about 0.8 of the T1-T1 stretch). */
    TrailSec: 10,
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
}

interface Decision {
    slot: number;
    want: boolean;
    reading?: LanePush.Reading;
    /** The lane with the pulled wave gone (Wanted's input). */
    gone?: LanePush.WaveGone;
    /** A core could hold their wave (CoreToHold), and which rule wanted the pull: new, old or both. */
    hold?: boolean;
    rule?: string;
    /** The lane controller decided this wave (slice lane-control 2b): a refusal is `ctl`, not `lane`. */
    ctl?: boolean;
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
const ended: Record<number, Ended | undefined> = {};
const priorities: Record<number, { at: number; p: number } | undefined> = {};

/** A pull that ended ok: its camp, when, and the wave's diverted share so far (PullFarm's trigger reads it). */
interface Ended {
    camp: number;
    at: number;
    pull: Pull;
}

export function ResetCache(): void {
    for (const t of [running, trailing, handled, decided, gateWhy, timers, ended, priorities] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
    Calendar.ResetCache();
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

/**
 * Slice lane-control 4a (design s5.7; user 06/11/2026: the pos3 may pull the hard camp and no other camp): the offlane pos3
 * under Ours.CorePull. The offlane's only pull camp is the hard camp (camps_data `off_large`). It pulls only when the lane
 * controller's decision names it (rule `ctl`), never on the support's own triggers.
 */
function corePuller(bot: Unit): boolean {
    return Ours.On("CorePull") && LaneConfig.PositionOf(bot) === 3 && bot.GetAssignedLane() === Camps.LaneOfKind(bot.GetTeam(), "off");
}

function campFor(bot: Unit): Camps.CampJobData | undefined {
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Bot) return undefined;
    return Camps.PullCampsFor(bot.GetTeam(), lane)[0];
}

export function Applies(bot: Unit): boolean {
    return Ours.On("SupportPull") && Ours.On("JobChooser") && bot.IsBot() && ((isSupport(bot) && pullerOfLane(bot)) || corePuller(bot)) && campFor(bot) !== undefined;
}

/**
 * Slice lane-control 3 (design s5.4, s5.5): above the hero's other jobs (FitPriority) while the lane controller's decision
 * for the next pulled wave has this support's pull and the pull fits before the next departure on its calendar (a claim has
 * begun, the walk has not: a rune trip claims from a minute before its spawn, a stack from :15); else Priority, so a
 * departure the pull does not fit before keeps its rank. Read at most every PriorityEvery s.
 */
export function Priority(bot: Unit): number | undefined {
    if (!Applies(bot)) return undefined;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const c = priorities[pid];
    if (c !== undefined && now >= c.at && now - c.at < SETTINGS.PriorityEvery) return c.p;
    const p = fitsAhead(bot, now) ? SETTINGS.FitPriority : SETTINGS.Priority;
    priorities[pid] = { at: now, p };
    return p;
}

/** The next pull's walk start, end (the hit second plus Take) and hit second (`key`), or undefined with no plan. */
export function Window(bot: Unit, now: number): { start: number; end: number; key: number; stand: Vector } | undefined {
    const p = planFor(bot, now);
    if (p === undefined) return undefined;
    return { start: p.slot - travel(bot, p) - SETTINGS.Early, end: p.slot + SETTINGS.Take, key: p.slot, stand: p.stand };
}

function fitsAhead(bot: Unit, now: number): boolean {
    const LaneControl = require("bots/FunLib/humaniser/lane_control") as typeof import("bots/FunLib/humaniser/lane_control");
    const pid = bot.GetPlayerID();
    if (!LaneControl.Drives() || running[pid] !== undefined) return false;
    const w = Window(bot, now);
    if (w === undefined || SameWave(handled[pid], w.key)) return false;
    const d = LaneControl.DecisionFor(bot.GetTeam(), bot.GetAssignedLane(), PulledSpawn(w.key));
    if (d === undefined || !CtlWants(d, pid)) return false;
    const [fit] = Calendar.FitOf(Calendar.Of(bot, now), w.start, w.end);
    return fit === "fits";
}

export function Claims(bot: Unit): boolean {
    return Running(bot);
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
 * `empty` when the camp holds nothing to pull at `hitAt`: nothing returned while the team sees the camp's origin, and no
 * spawn minute before the hit (a camp respawns only on the minute, so it stays empty). An empty box out of sight says
 * nothing: the API returns no fogged neutrals (pc1: every one returned was `CanBeSeen`). `one` the same with a single
 * neutral left: too little to hold a wave (banked `ok` pulls with one neutral seen at the start diverted 26 of 56, two or
 * more 243 of 385; user 04/11/2026: skip it). Stacking it instead is the stack job's call, not this one's.
 */
export function CampGate(s: CampState, now: number, hitAt: number): string | undefined {
    const period = LaneConfig.Settings().Timing.PullPeriod;
    if (!s.vis || math.floor(hitAt / period) > math.floor(now / period)) return undefined;
    if (s.n === 0) return "empty";
    if (s.n === 1) return "one";
    return undefined;
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

/** The lane controller's decision has this support's pull in its set (slice lane-control 2b). */
export function CtlWants(d: { levers: string[]; who: string[] }, pid: number): boolean {
    for (let i = 0; i < d.levers.length; i++) if (d.levers[i] === "pull" && d.who[i] === `${pid}`) return true;
    return false;
}

/** The earlier trigger: the 30 s forecast past the target and the lane not coming in. */
export function OldWanted(r: LanePush.Reading | undefined, target: number): boolean {
    return r !== undefined && r.state !== "IN" && r.own + r.move > target + SETTINGS.WantPast;
}

type WaveHoldModule = typeof import("bots/FunLib/humaniser/states/wave_hold");
type ChooserModule = typeof import("bots/FunLib/humaniser/chooser");

/**
 * Our lane core who could hold their wave at the lane's target point: the wave hold owns it (alive, laning, our spot), it is
 * on this lane, on none of our jobs and within the hold's Reach of the point. Required at the call, not imported: wave_hold
 * and the chooser import this module.
 */
export function CoreToHold(bot: Unit): Unit | undefined {
    const WaveHold = require("bots/FunLib/humaniser/states/wave_hold") as WaveHoldModule;
    const Chooser = require("bots/FunLib/humaniser/chooser") as ChooserModule;
    const lane = bot.GetAssignedLane();
    const path = LanePush.PathOf(lane);
    if (path === undefined) return undefined;
    const [t1, dir] = LanePush.OwnT1(path, bot.GetTeam());
    const [x, y] = LanePush.PointAt(path, t1 + dir * LanePush.TargetOf(lane));
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m === bot || m.GetAssignedLane() !== lane || !WaveHold.Owns(m) || Chooser.Running(m)) continue;
        if (GetUnitToLocationDistance(m, Vector(x, y, m.GetLocation().z)) <= WaveHold.SETTINGS.Reach) return m;
    }
    return undefined;
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

/** Why the lane partner (a teammate core assigned to the lane) should not be left now, else undefined. */
export function PartnerThreat(bot: Unit): string | undefined {
    const lane = bot.GetAssignedLane();
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m === bot || !m.IsAlive() || isSupport(m) || m.GetAssignedLane() !== lane) continue;
        // Distinct heroes only: an illusion is a unit, not a pid (lane-read-ec review L3 counted a pid twice).
        const pids: Record<number, boolean> = {};
        let n = 0;
        for (const e of GetUnitList(UnitType.EnemyHeroes)) {
            if (!e.IsAlive() || e.IsIllusion() || GetUnitToUnitDistance(e, m) > SETTINGS.PartnerRadius) continue;
            if (pids[e.GetPlayerID()] !== true) n++;
            pids[e.GetPlayerID()] = true;
        }
        if (n >= SETTINGS.PartnerGank) return "partner-gank";
        if (n > 0 && m.GetHealth() < m.GetMaxHealth() * SETTINGS.PartnerHp) return "partner-low";
    }
    return undefined;
}

/** The nearest enemy hero to the pull site (stand or meet point) into `camp.se`; `enemy-site` within SiteEnemy. */
function siteThreat(p: Plan, camp: CampState): string | undefined {
    let near: number | undefined;
    for (const e of GetUnitList(UnitType.EnemyHeroes)) {
        if (!e.IsAlive() || e.IsIllusion()) continue;
        const d = math.min(GetUnitToLocationDistance(e, p.stand), GetUnitToLocationDistance(e, p.meet));
        if (near === undefined || d < near) near = d;
    }
    camp.se = near;
    return near !== undefined && near <= SETTINGS.SiteEnemy ? "enemy-site" : undefined;
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
    ];
}

/** `slot` the plan's hit second, so the line joins its `pull_job` line. */
function choiceLine(bot: Unit, d: Decision, slot: number, go: boolean, why: string | undefined, camp: CampState): void {
    const r = d.reading;
    const r1 = (x: number | undefined) => (x !== undefined ? math.floor(x + 0.5) : undefined);
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "pull"],
        ["go", go ? 1 : 0],
        ["want", d.want ? 1 : 0],
        ["why", why],
        ["src", "own"],
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
        ["hold", d.hold === undefined ? undefined : d.hold ? 1 : 0],
        ["rule", d.rule],
        ["ms", r?.ms],
        ...campFields(camp),
    ]);
}

function jobLine(bot: Unit, p: Pull, phase: string, why: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "pull"],
        ["phase", phase],
        ["why", why],
        ["host", p.host],
        ...(phase === "end" ? ([["hit", p.hit === true ? 1 : 0]] as Telemetry.Fields<"job">) : []),
    ]);
}

function finish(bot: Unit, p: Pull, r: Lib.Result, label: string | undefined): void {
    running[bot.GetPlayerID()] = undefined;
    const why = r.success ? "ok" : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`;
    jobLine(bot, p, "end", why);
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
    ];
    if (!r.success) {
        Telemetry.Event("pull_job", fields);
        return;
    }
    const now = DotaTime();
    ended[bot.GetPlayerID()] = { camp: p.plan.camp.campIdx, at: now, pull: p };
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
    return yield* Tasks.Jobs()!.pull(bot as unknown as Lib.TaskUnit, verbPlan(bot, p, aggroAt), hooks);
}

/**
 * Every frame while the chooser asks: true while a pull runs or as one starts. The lane is read once per slot at the leave
 * time; a wanted pull then waits for `blocked` (the chooser's checks, a higher job's claim), the partner check and OHA's own
 * action until it could no longer reach the camp by the hit's late limit.
 */
export function Wants(bot: Unit, blocked: (bot: Unit) => string | undefined, host: number): boolean {
    if (!Applies(bot)) return false;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return true;
    trail(bot, false);
    if (Tasks.Jobs() === undefined || !LaneConfig.InLaningPhase() || !bot.IsAlive()) return false;
    const now = DotaTime();
    const p = planFor(bot, now);
    if (p === undefined || SameWave(handled[pid], p.slot)) return false;
    const walk = travel(bot, p);
    // Once our wave is out its creeps time the hit (pull_timing's CreepTimer); the leave time, the late check and the hit all
    // use that second (pw2: 12 starts planned against the slot failed `late` while still walking, the wave being early).
    let timer = timers[pid];
    if (timer === undefined || !SameWave(timer.slot, p.slot)) {
        timer = PullTiming.Timer(p.timing, p.slot, LaneConfig.Settings().PullTiming.FullPast);
        timers[pid] = timer;
    }
    const hitAt = PullTiming.Read(timer, now);
    if (now < hitAt - walk - SETTINGS.Early) return false;
    let d = decided[pid];
    if (d === undefined || !SameWave(d.slot, p.slot)) {
        const reading = LanePush.Read(bot.GetTeam(), bot.GetAssignedLane());
        const gone = LanePush.WaveGoneNow(bot.GetTeam(), bot.GetAssignedLane(), PulledSpawn(p.slot), p.slot + SETTINGS.ArriveAfter);
        const tgt = LanePush.TargetOf(bot.GetAssignedLane());
        const hold = CoreToHold(bot) !== undefined;
        // Slice lane-control 2b: the lane controller's decision for the pulled wave says whether to pull (rule `ctl`); the
        // pull keeps its own gates below. With no decision for that wave, the pull's own triggers decide.
        const LaneControl = require("bots/FunLib/humaniser/lane_control") as typeof import("bots/FunLib/humaniser/lane_control");
        const ctl = LaneControl.DecisionFor(bot.GetTeam(), bot.GetAssignedLane(), PulledSpawn(p.slot));
        // A drill that forces the pull (humaniser/drill.ts `pull`, `core-pull`): the rep of the pulled wave decides, input on
        // pulls (rule `drill`), a control rep or a wave before the first rep does not (`why=drill`); the controller is not
        // asked. The pull's own gates below still apply.
        const forced = Drill.ForcedAt("pull", PulledSpawn(p.slot));
        if (forced !== undefined) d = { slot: p.slot, want: forced === "on", reading, gone, hold, rule: forced === "on" ? "drill" : undefined, drill: true };
        else {
            // A core (slice 4a) whose walk to the far hard camp starts before the pulled wave's read waits for it rather than
            // settle the slot with no decision (lctl8: Dire's pos3 refused 11 slots `no_ctl` that way); too late by then is `late`.
            if (ctl === undefined && !isSupport(bot) && LaneControl.Drives() && now < PulledSpawn(p.slot) + LaneControl.SETTINGS.ReadAt + 1 && PulledSpawn(p.slot) <= LaneControl.SETTINGS.Until)
                return false;
            const byCtl = ctl !== undefined && CtlWants(ctl, pid);
            // A core (slice 4a) pulls only on the controller's word.
            const own = ctl === undefined && isSupport(bot);
            const byNew = own && Wanted(gone, tgt);
            const byOld = own && hold && OldWanted(reading, tgt);
            const rule = byCtl ? "ctl" : byNew && byOld ? "both" : byNew ? "new" : byOld ? "old" : undefined;
            d = { slot: p.slot, want: rule !== undefined, reading, gone, hold, rule, ctl: ctl !== undefined };
        }
        decided[pid] = d;
        gateWhy[pid] = undefined;
    }
    const camp = CampStateOf(p.spawner);
    const done = (go: boolean, why: string | undefined) => {
        handled[pid] = p.slot;
        gateWhy[pid] = undefined;
        choiceLine(bot, d!, p.slot, go, why, camp);
    };
    if (!d.want) {
        done(false, d.drill === true ? "drill" : d.ctl === true ? "ctl" : !isSupport(bot) ? "no_ctl" : d.reading === undefined ? "no-read" : "lane");
        return false;
    }
    camp.dmg = CampDamage(bot, camp, p.spawner.type);
    camp.php = bot.GetHealth();
    const site = siteThreat(p, camp);
    const why = CampGate(camp, now, hitAt) ?? blocked(bot) ?? campDmgGate(bot, camp.dmg) ?? site ?? PartnerThreat(bot) ?? (acting(bot) ? "acting" : undefined);
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
    const pull: Pull = { plan: p, left: now, host, wave: 0, peak: 0, neutrals: 0, hitAt, timer, start: camp };
    const ok = Tasks.Start(bot, { name: "pull", host, preemptAfter: 1, stallAfter: 4, onEnd: (r, info) => finish(bot, pull, r, info.label) }, (ctx: Lib.Ctx) =>
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

export function Step(bot: Unit, host: number): boolean {
    const p = running[bot.GetPlayerID()];
    if (p === undefined) return false;
    // Before the hit the walk may bring the camp into sight: stop there rather than hit an empty camp or one it cannot take.
    if (p.label === undefined || p.label === "travel" || p.label === "wait") {
        const s = CampStateOf(p.plan.spawner);
        s.dmg = CampDamage(bot, s, p.plan.spawner.type);
        s.php = bot.GetHealth();
        const now = DotaTime();
        const gate = CampGate(s, now, p.hitAt);
        // `one`/`empty` count only near the stand (CampReadNear) and must hold CampLowHold s (the camp fills in as it comes
        // into sight); camp damage ends it at once.
        if (gate === undefined || GetUnitToLocationDistance(bot, p.plan.stand) > SETTINGS.CampReadNear) p.low = undefined;
        else if (p.low === undefined || p.low.why !== gate) p.low = { why: gate, at: now };
        const why = (p.low !== undefined && now - p.low.at >= SETTINGS.CampLowHold ? p.low.why : undefined) ?? campDmgGate(bot, s.dmg);
        if (why !== undefined) {
            // The pull_job line then carries the camp that cancelled it, not the one at the start.
            p.start = s;
            End(bot, why);
            return false;
        }
    }
    sample(bot, p);
    return Tasks.Step(bot, host);
}

/** The bot's last ok pull: its camp index, end time and the wave's diverted share (still growing for TrailSec after the end). */
export function Finished(bot: Unit): { camp: number; at: number; div: number } | undefined {
    const e = ended[bot.GetPlayerID()];
    return e !== undefined ? { camp: e.camp, at: e.at, div: share(e.pull) } : undefined;
}

export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

export function End(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}

export function NoteHit(bot: Unit): void {
    const p = running[bot.GetPlayerID()];
    if (p !== undefined) p.hit = true;
}

export function NoteIdleHeld(bot: Unit): void {
    const p = running[bot.GetPlayerID()];
    if (p !== undefined) p.idle = (p.idle ?? 0) + 1;
}
