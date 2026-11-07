/**
 * The pull (slice support-lane, switch Ours.SupportPull, KR S.3): a pos4/pos5 takes our wave into its lane's first pull camp
 * when the lane push reading wants it, then comes back to lane. The job chooser hosts it and decides when it may start; this
 * module reads the lane once per pull slot (`ev=choice kind=pull`), plans the pull from the camp data (`camps`,
 * `pull_timing`), walks it with the job verb `pull` and logs one `ev=pull_job` line per started pull.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Calendar from "bots/FunLib/humaniser/calendar";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LanePush from "bots/FunLib/humaniser/lane_push";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as PullTiming from "bots/FunLib/humaniser/pull_timing";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

// All `judgement` (slice file, Decisions), except where a source is named.
export const SETTINGS = {
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
    /** A lane creep has left the lane (pull_creep lt) once it is this far off the lane path above its own least. */
    Leave: 100,
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
    /** The neutrals returned, for the damage estimate. */
    units: Unit[];
    /** At a decision: the camp's expected damage on the puller (CampDamage) and the puller's HP. */
    dmg?: number;
    php?: number;
    /** At a decision: the nearest enemy hero to the stand point or the meet point (siteThreat). */
    se?: number;
}

export type Kind = "full" | "half";

interface Plan {
    kind: Kind;
    /** The full pull's hit second for this wave: the slot the lane is read and decided for, whatever the kind. */
    key: number;
    camp: Camps.CampJobData;
    spawner: Camps.Spawner;
    stand: Vector;
    lead: Vector[];
    meet: Vector;
    timing: PullTiming.PullTiming;
    /** The planned hit second (no skill error). */
    slot: number;
}

interface Pull {
    plan: Plan;
    left: number;
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
    /** A half pull's step-in: the puller's offset from the stand point towards the meet point when the wave engaged (hi). */
    stepIn?: number;
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
    /** The half-pull harness's per-creep record (ev=pull_creep), and the puller's last place and time for its speed. */
    creeps?: Map<Unit, CreepTrack>;
    creepN?: number;
    pAt?: Vector;
    pT?: number;
    /** The shed (SETTINGS ShedMargin): when it began, the puller's HP share then, and the point it last walked to. */
    shs?: number;
    shh?: number;
    shedTo?: Vector;
    /** Slice pull-aggro: the neutrals' landings on the puller (pull_job fl lc la nar), from its HP each frame. */
    lastHp?: number;
    fl?: number;
    lc?: number;
    la?: number;
    nar?: number;
    /** Slice pull-aggro (Ours.PullOnHero, full pulls): the leave time read at the hit and when the lead began (lvp, lva);
     *  arrival at the stand (the watch) and the first tagged neutral within its attack reach of the puller after it (laga);
     *  seconds with a tagged neutral on the puller at the camp and from the lead on (tkc, tks), from the last sample's time;
     *  the first frame our wave fought theirs (cla); the deadline's cause and time (dl); per tagged neutral when it was first
     *  the first tagged neutral was GiveUpFrom out of the camp (firstOut); fb 1 when the plan's first landing was the unseen-camp fallback. */
    lvp?: number;
    lva?: number;
    arrAt?: number;
    laga?: number;
    tkc?: number;
    tks?: number;
    tkT?: number;
    cla?: number;
    dl?: string;
    dlAt?: number;
    firstOut?: number;
    fb?: number;
}

/** One lane creep of ours near the watch after the hit (ev=pull_creep): read at its turn onto a neutral, else at its
 *  nearest approach to the puller so far. */
interface CreepTrack {
    ci: number;
    rg: number;
    tr: number;
    tt?: number;
    dp?: number;
    dn?: number;
    ph?: number;
    pv?: number;
    po?: number;
    ca?: number;
    /** Least distance off the lane path so far, and the frame it rose Leave above it (the creep left the lane). */
    off0?: number;
    lt?: number;
    ld?: number;
    ln?: number;
    /** Slice pull-aggro: its acquisition range, landings on the puller within it, and the landing kept (pull_creep ar..hn). */
    ar?: number;
    hk?: number;
    hAt?: number;
    lastD?: number;
    lastN?: number;
    bestD?: number;
    bestN?: number;
    hl?: number;
}

interface Decision {
    slot: number;
    want: boolean;
    kind: Kind;
    reading?: LanePush.Reading;
    /** The lane with the pulled wave gone (Wanted's input). */
    gone?: LanePush.WaveGone;
    /** A core could hold their wave (CoreToHold), and which rule wanted the pull: new, old or both. */
    hold?: boolean;
    rule?: string;
    /** The lane controller decided this wave (slice lane-control 2b): a refusal is `ctl`, not `lane`. */
    ctl?: boolean;
    /** A half pull's clearance margin when it stayed for want of one (choice why=half-geo). */
    hm?: number;
    /** Slice pull-aggro: 1 when a wanted half pull was refused for a melee spawn (choice pm); the timer's no-window cause
     *  at the last frame read (choice nw). */
    pm?: number;
    nw?: string;
    nws?: number;
    ent?: number;
    clp?: number;
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
/** Slice pull-aggro: per camp, whether its last seen spawn held a ranged unit (CampRanged). */
const campKinds: Record<number, { spawn: number; ranged: boolean } | undefined> = {};

/** A pull that ended ok: its camp, when, and the wave's diverted share so far (PullFarm's trigger reads it). */
interface Ended {
    camp: number;
    at: number;
    pull: Pull;
}

export function ResetCache(): void {
    for (const t of [running, trailing, handled, decided, gateWhy, timers, ended, priorities, campKinds] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
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

function campFor(bot: Unit): Camps.CampJobData | undefined {
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Bot) return undefined;
    return Camps.PullCampsFor(bot.GetTeam(), lane)[0];
}

export function Applies(bot: Unit): boolean {
    return Ours.On("SupportPull") && Ours.On("JobChooser") && bot.IsBot() && isSupport(bot) && pullerOfLane(bot) && campFor(bot) !== undefined;
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

/** The next full pull's walk start, end (the hit second plus Take) and hit second (`key`), or undefined with no plan. */
export function Window(bot: Unit, now: number): { start: number; end: number; key: number } | undefined {
    const p = planFor(bot, now, "full");
    if (p === undefined) return undefined;
    return { start: p.key - travel(bot, p) - SETTINGS.Early, end: p.key + SETTINGS.Take, key: p.key };
}

function fitsAhead(bot: Unit, now: number): boolean {
    const LaneControl = require("bots/FunLib/humaniser/lane_control") as typeof import("bots/FunLib/humaniser/lane_control");
    const pid = bot.GetPlayerID();
    if (!LaneControl.Drives() || running[pid] !== undefined) return false;
    const w = Window(bot, now);
    if (w === undefined || handled[pid] === w.key) return false;
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

/**
 * The next wave's pull of `kind`. A half pull is the same wave and the same meet point hit HalfPullLater after the full
 * pull's second (pull_timing's half timing), so its slot is the first half second at or after the full one; `key` stays
 * the full slot, so one wave is read and decided once whatever the kind.
 */
function planFor(bot: Unit, now: number, kind: Kind): Plan | undefined {
    const camp = campFor(bot);
    const spawner = camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
    if (camp === undefined || camp.pull === undefined || spawner === undefined) return undefined;
    const t = LaneConfig.Settings().Timing;
    const full = PullTiming.ForCamp(camp, false);
    if (full.seconds.length === 0) return undefined;
    const key = NextSlot(now - t.JobStartLate, full.seconds, t.PullPeriod);
    // Camps hold neutrals for a whole minute only from their first spawn on (camp_jobs' CampsUp).
    if (math.floor(key / t.PullPeriod) * t.PullPeriod < t.NeutralFirstSpawn) return undefined;
    const meet = camp.pull.meetPoint;
    const timing = kind === "half" ? PullTiming.ForCamp(camp, true, meet) : full;
    if (timing.seconds.length === 0) return undefined;
    const slot = kind === "half" ? NextSlot(key, timing.seconds, t.PullPeriod) : key;
    const lead = PullTiming.LeadPath(camp.pull, meet);
    const stand = Camps.StandPoint(spawner, lead[0], LaneConfig.Settings().Radii.StandOffset);
    return { kind, key, camp, spawner, stand, lead, meet, timing, slot };
}

/** The safe lane of `bot`'s team (pull_timing's LaneAhead rule). */
function safeLane(bot: Unit): boolean {
    const lane = bot.GetAssignedLane();
    return lane !== Lane.Mid && (bot.GetTeam() === Team.Radiant) === (lane === Lane.Bot);
}

/**
 * Which pull a wanted slot gets: the safe-lane pos5 half-pulls when a wanted lane holds (it is out a little: slow
 * and thin the wave rather than reset it; banked full pulls from there took the clash to -0.66 in 30 s and back to +0.07
 * in 60, partial ones to -0.13 and -0.15, slice file Decisions), and full-pulls when it pushes out. Everyone else full.
 */
export function KindFor(bot: Unit, r: LanePush.Reading | undefined): Kind {
    return halfWanted(bot, r) && !MeleeSpawn(bot) ? "half" : "full";
}

function halfWanted(bot: Unit, r: LanePush.Reading | undefined): boolean {
    if (!Ours.On("SupportHalfPull") || LaneConfig.PositionOf(bot) !== 5 || !safeLane(bot)) return false;
    if (LaneConfig.Settings().PullTiming.HalfAll === true) return true;
    return r !== undefined && r.state === "HOLD";
}

/**
 * Slice pull-aggro (user 07/11/2026: no half pulls from melee-only camps): whether `camp`'s spawn holds a ranged unit
 * (GetAttackRange >= HalfRangedFrom), read per spawn from the units seen in its box (camp 1 spawned melee and ranged sets,
 * phagg1); unseen, the last seen spawn's; undefined never seen.
 */
export function CampRanged(camp: Camps.CampJobData, spawner: Camps.Spawner, now: number): boolean | undefined {
    const s = CampStateOf(spawner);
    if (s.units.length > 0) {
        const from = LaneConfig.Settings().PullTiming.HalfRangedFrom;
        let ranged = false;
        for (const u of s.units) if (u.GetAttackRange() >= from) ranged = true;
        campKinds[camp.campIdx] = { spawn: math.floor(now / LaneConfig.Settings().Timing.PullPeriod), ranged };
    }
    return campKinds[camp.campIdx]?.ranged;
}

/** With Ours.PullOnHero: `bot`'s pull camp's spawn is known melee only. */
function MeleeSpawn(bot: Unit): boolean {
    if (!Ours.On("PullOnHero")) return false;
    const camp = campFor(bot);
    const spawner = camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
    return camp !== undefined && spawner !== undefined && CampRanged(camp, spawner, DotaTime()) === false;
}

type Attacker = Unit & { GetAttackPoint(): number; GetAttackProjectileSpeed(): number };

/** An attack's wind-up in seconds: GetAttackPoint over the unit's attack speed, as the old lock-on read it. */
function windup(u: Unit): number {
    return (u as Attacker).GetAttackPoint() / math.max(0.1, u.GetAttackSpeed());
}

/** A ranged attack's flight over `d` (GetAttackProjectileSpeed; 0 for a unit with none, a melee one). */
function flight(u: Unit, d: number): number {
    const v = (u as Attacker).GetAttackProjectileSpeed();
    return v > 0 ? d / v : 0;
}

/**
 * Slice pull-aggro (design 08/11/2026): with Ours.PullOnHero, a full pull's puller side (PullTiming.OnHero). `first`: the
 * puller's wind-up and projectile flight to its attack range, then the soonest neutral landing: a melee one walks the
 * puller's attack range less its own reach and winds up, a ranged one winds up and its projectile flies the puller's range
 * (HeroFirst while the camp is unseen, fb 1). `lagExtra`: the slowest melee neutral's wind-up (0 for an all-ranged camp).
 * `pass`: the neutrals' walk from the camp stand to GiveUpFrom from the camp. Half pulls keep the existing timing.
 */
function heroFor(bot: Unit, p: Plan, timer: PullTiming.CreepTimer, pull?: Pull): void {
    if (!Ours.On("PullOnHero") || timer.keep > 0) {
        timer.hero = undefined;
        return;
    }
    const cfg = LaneConfig.Settings().PullTiming;
    const range = bot.GetAttackRange();
    const own = windup(bot) + (range >= cfg.HalfRangedFrom ? flight(bot, range) : 0);
    let soonest: number | undefined;
    let extra = 0;
    for (const u of CampStateOf(p.spawner).units) {
        const r = u.GetAttackRange();
        let l: number;
        if (r >= cfg.HalfRangedFrom) l = windup(u) + flight(u, range);
        else {
            l = math.max(0, range - r) / math.max(1, u.GetCurrentMovementSpeed()) + windup(u);
            extra = math.max(extra, windup(u));
        }
        soonest = math.min(soonest ?? math.huge, l);
    }
    if (pull !== undefined) pull.fb = soonest === undefined ? 1 : undefined;
    // The camp's speed comes with every wave timing; with none the read gives no hit, so the puller's own (no lag) only fills the slot.
    const nsp = p.timing.neutralSpeed ?? bot.GetCurrentMovementSpeed();
    const o = p.spawner.location;
    const d0 = math.sqrt((p.stand.x - o.x) ** 2 + (p.stand.y - o.y) ** 2);
    timer.hero = {
        from: p.stand,
        route: p.lead,
        speed: bot.GetCurrentMovementSpeed(),
        first: soonest !== undefined ? own + soonest : cfg.HeroFirst,
        lagExtra: extra,
        neutralSpeed: nsp,
        pass: math.max(0, cfg.GiveUpFrom - d0) / math.max(1, nsp),
        giveUp: cfg.GiveUpAfterCamp[p.camp.campIdx] ?? cfg.GiveUpAfter,
    };
}

/** Our lane creep `c` attacking the other team's lane creep. */
function onLaneCreep(c: Unit): boolean {
    const t = c.GetAttackTarget();
    return t !== undefined && t !== null && t.GetTeam() !== c.GetTeam() && t.GetTeam() !== Team.Neutral && LanePush.IsLaneCreep(t.GetUnitName());
}

/**
 * Slice pull-aggro's deadline (design step 5), read every frame from the confirmed hit and latched: `give-up` the camp's
 * GiveUpAfterCamp s after the first tagged neutral passed GiveUpFrom, `dead` every tagged neutral died, `clash` a creep of
 * the timed wave fights theirs, `back` the wave's back creep on the lane is past the stand and out of its range, `cap`
 * JobMaxAfterAggro after the hit.
 */
function deadlineCause(pull: Pull): string | undefined {
    if (pull.dl !== undefined) return pull.dl;
    const now = DotaTime();
    const s = LaneConfig.Settings();
    const p = pull.plan;
    const hat = pull.hat ?? now;
    let cause: string | undefined;
    if (now >= hat + s.Timing.JobMaxAfterAggro) cause = "cap";
    if (cause === undefined && pull.tagged !== undefined && pull.tagged.length > 0) {
        // Timed from the first neutral past GiveUpFrom, as GiveUpAfterCamp was fitted (gu - g4; review L2); a camp whose
        // tagged neutrals all died ends `dead` (an empty tag list ends nothing: review L3).
        let alive = 0;
        for (const u of pull.tagged) {
            if (stale(u)) continue;
            alive++;
            if (pull.firstOut === undefined && GetUnitToLocationDistance(u, p.spawner.location) > s.PullTiming.GiveUpFrom) pull.firstOut = now;
        }
        if (alive === 0) cause = "dead";
        else if (pull.firstOut !== undefined && now - pull.firstOut >= (pull.timer.hero?.giveUp ?? s.PullTiming.GiveUpAfter)) cause = "give-up";
    }
    if (cause === undefined && waveFights(pull)) cause = "clash";
    if (cause === undefined && PullTiming.BackPast(pull.timer, p.meet, now)) cause = "back";
    if (cause !== undefined) {
        pull.dl = cause;
        pull.dlAt = now;
    }
    return cause;
}

/** Slice pull-aggro: one of our lane creeps of the timed wave (near the pull, not already at the meet point at the hit:
 *  `early`, review L1) fights the other team's lane creeps. */
function waveFights(pull: Pull): boolean {
    const early = pull.early ?? [];
    return laneCreepsNear(pull.plan, LaneConfig.Settings().Radii.MeetWatch).some((c) => early.indexOf(c) < 0 && onLaneCreep(c));
}

/** Slice pull-aggro: a tagged neutral is attacking the puller. */
function onPuller(bot: Unit, pull: Pull): boolean {
    for (const u of pull.tagged ?? []) if (!stale(u) && u.GetAttackTarget() === bot) return true;
    return false;
}

/** Slice pull-aggro: per frame from the hit, the tank seconds (tkc at the camp, tks from the lead on), the neutrals' lag at
 *  the stand (laga) and the first frame our wave fought theirs (cla). */
function trackHero(bot: Unit, pull: Pull): void {
    if (pull.timer.hero === undefined || pull.hat === undefined) return;
    const now = DotaTime();
    const on = onPuller(bot, pull);
    if (pull.tkT !== undefined && on) {
        const dt = now - pull.tkT;
        if (pull.label === "hold") pull.tkc = (pull.tkc ?? 0) + dt;
        else pull.tks = (pull.tks ?? 0) + dt;
    }
    pull.tkT = now;
    if (pull.arrAt !== undefined && pull.laga === undefined) {
        for (const u of pull.tagged ?? []) {
            if (stale(u)) continue;
            if (GetUnitToUnitDistance(u, bot) <= u.GetAttackRange() + u.GetBoundingRadius() + bot.GetBoundingRadius()) pull.laga = now - pull.arrAt;
        }
    }
    if (pull.cla === undefined && waveFights(pull)) pull.cla = now;
}

function travel(bot: Unit, p: Plan): number {
    return (GetUnitToLocationDistance(bot, p.stand) * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed());
}

export function CampStateOf(spawner: Camps.Spawner): CampState {
    const m = LaneConfig.Settings().Radii.BoxMargin;
    const lo = spawner.min;
    const hi = spawner.max;
    const s: CampState = { n: 0, seen: 0, hp: 0, vis: IsLocationVisible(spawner.location), units: [] };
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

/** The wave a slot pulls: ours spawned on the last 30 s at or before the slot (aggro comes after the spawn). */
export function PulledSpawn(slot: number): number {
    return math.floor((slot - 1) / 30) * 30;
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
        ["cdmg", r0(s.dmg)],
        ["php", r0(s.php)],
        ["se", r0(s.se)],
    ];
}

/** `slot` the plan's hit second (a half pull's, not the wave's `key`), so the line joins its `pull_job` line. */
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
        ["pk", d.want ? d.kind : undefined],
        ["hm", d.hm],
        ["pm", d.pm],
        ["nw", d.nw],
        ["nws", d.nws],
        ["ent", d.ent],
        ["clp", d.clp],
        ...campFields(camp),
    ]);
}

/** Slice pull-aggro's pull_job fields (LOGGING "Pulls"); none without Ours.PullOnHero on a full pull. */
function heroFields(p: Pull): Telemetry.Fields<"pull_job"> {
    const t = p.timer;
    const h = t.hero;
    if (h === undefined) return [];
    const r2 = (x: number | undefined) => (x !== undefined ? math.floor(x * 100 + 0.5) / 100 : undefined);
    const since = (x: number | undefined) => (x !== undefined && p.hat !== undefined ? r2(x - p.hat) : undefined);
    return [
        ["ent", r2(t.ent)],
        ["lvp", r2(p.lvp)],
        ["lva", r2(p.lva)],
        ["fst", r2(h.first)],
        ["fl1", since(p.fl)],
        ["lag", r2(t.lag)],
        ["laga", r2(p.laga)],
        ["gup", r2(t.gup)],
        ["clp", r2(t.clp)],
        ["cla", r2(p.cla)],
        ["tkc", r2(p.tkc)],
        ["tks", r2(p.tks)],
        ["dl", p.dl],
        ["fb", p.fb],
    ];
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
        ["pk", p.plan.kind],
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
        ["nsp", p.plan.timing.neutralSpeed !== undefined ? math.floor(p.plan.timing.neutralSpeed + 0.5) : undefined],
        ["hr", p.timer.hit !== undefined ? "geo" : "plan"],
        ["hc", p.timer.n],
        ["hn", p.timer.next],
        ["hb", p.timer.back],
        ["hf", p.timer.clear],
        ["hu", p.timer.turn],
        ["hm", p.timer.margin],
        ["hs", p.timer.standBack],
        ["hi", p.stepIn],
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
        ["fl", p.fl !== undefined ? math.floor(p.fl * 100 + 0.5) / 100 : undefined],
        ["lc", p.lc],
        ["la", p.la !== undefined ? math.floor(p.la * 100 + 0.5) / 100 : undefined],
        ["nar", p.nar],
        ...heroFields(p),
    ];
    if (!r.success) {
        creepLines(bot, p);
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
    creepLines(bot, tr.pull);
    Telemetry.Event("pull_job", [...tr.fields, ["dt", share(tr.pull)]]);
}

/** The harness's per-creep lines (ev=pull_creep), written once with the pull's own line. */
function creepLines(bot: Unit, p: Pull): void {
    if (p.creeps === undefined) return;
    const r1 = (x: number | undefined) => (x !== undefined ? math.floor(x * 10 + 0.5) / 10 : undefined);
    const r0 = (x: number | undefined) => (x !== undefined ? math.floor(x + 0.5) : undefined);
    for (const [, c] of p.creeps) {
        Telemetry.Event("pull_creep", [
            ["pid", bot.GetPlayerID()],
            ["slot", p.plan.slot],
            ["camp", p.plan.camp.campIdx],
            ["ci", c.ci],
            ["rg", c.rg],
            ["tr", c.tr],
            ["tt", r1(c.tt)],
            ["dp", r0(c.dp)],
            ["dn", r0(c.dn)],
            ["ph", c.ph],
            ["pv", r0(c.pv)],
            ["po", r0(c.po)],
            ["ca", r0(c.ca)],
            ["lt", r1(c.lt)],
            ["ld", r0(c.ld)],
            ["ln", r0(c.ln)],
            ["ar", r0(c.ar)],
            ["hk", c.hk],
            ["hl", c.hl !== undefined ? math.floor(c.hl * 100 + 0.5) / 100 : undefined],
            ["hd", r0(c.tr === 1 ? c.lastD : c.bestD)],
            ["hn", r0(c.tr === 1 ? c.lastN : c.bestN)],
        ]);
    }
    p.creeps = undefined;
}

/**
 * Every frame after the hit: each lane creep of ours near the watch is read at the frame its attack target becomes a
 * neutral, else at its nearest approach to the puller so far (CreepTrack). What the puller was doing is read in the same
 * frame: hit by a tagged neutral or not, moving or standing, how far off the lane.
 */
function trackCreeps(bot: Unit, p: Pull): void {
    if (p.hat === undefined) return;
    const now = DotaTime();
    const at = bot.GetLocation();
    let pv = 0;
    if (p.pAt !== undefined && p.pT !== undefined && now > p.pT) pv = GetUnitToLocationDistance(bot, p.pAt) / (now - p.pT);
    p.pAt = at;
    p.pT = now;
    if (p.creeps === undefined) p.creeps = new Map();
    const path = p.plan.timing.lanePath;
    const meetAlong = p.plan.timing.meetAlong;
    let ph = 0;
    const alive: Unit[] = [];
    for (const u of p.tagged ?? []) {
        if (stale(u)) continue;
        alive.push(u);
        if (u.GetAttackTarget() === bot) ph = 1;
    }
    const po = path !== undefined ? PullTiming.Along(path, at)[1] : undefined;
    const landed = landing(bot, p, ph === 1);
    for (const c of laneCreepsNear(p.plan, LaneConfig.Settings().Radii.MeetWatch)) {
        let t = p.creeps.get(c);
        if (t === undefined) {
            t = { ci: p.creepN ?? 0, rg: string.find(c.GetUnitName(), "ranged")[0] !== undefined ? 1 : 0, tr: 0 };
            p.creepN = (p.creepN ?? 0) + 1;
            p.creeps.set(c, t);
        }
        if (t.tr === 1) continue;
        const dp = GetUnitToUnitDistance(c, bot);
        const nearest = () => {
            let dn: number | undefined;
            for (const u of alive) {
                const d = GetUnitToUnitDistance(c, u);
                if (dn === undefined || d < dn) dn = d;
            }
            return dn;
        };
        if (landed) {
            if (t.ar === undefined) t.ar = c.GetAcquisitionRange();
            const ar = t.ar ?? 0;
            if (dp <= ar) {
                t.hk = (t.hk ?? 0) + 1;
                if (p.la === undefined) p.la = now;
            }
            // The latest landing (written for a turn) and the one nearest the puller (written for a creep that never turns).
            const dn = nearest();
            t.hAt = now;
            t.lastD = dp;
            t.lastN = dn;
            if (t.bestD === undefined || dp < t.bestD) {
                t.bestD = dp;
                t.bestN = dn;
            }
        }
        if (path !== undefined && t.lt === undefined) {
            const off = PullTiming.Along(path, c.GetLocation())[1];
            if (t.off0 === undefined || off < t.off0) t.off0 = off;
            else if (off > t.off0 + SETTINGS.Leave) {
                t.lt = now - p.hat;
                t.ld = dp;
                t.ln = nearest();
            }
        }
        const turned = onNeutral(c);
        if (!turned && t.dp !== undefined && dp >= t.dp) continue;
        const dn = nearest();
        t.tr = turned ? 1 : 0;
        if (turned && t.hAt !== undefined) t.hl = now - t.hAt;
        t.tt = now - p.hat;
        t.dp = dp;
        t.dn = dn;
        t.ph = ph;
        t.pv = pv;
        t.po = po;
        if (path !== undefined && meetAlong !== undefined) t.ca = PullTiming.Along(path, c.GetLocation())[0] - meetAlong;
    }
}

/**
 * Slice pull-aggro: true on a frame where a tagged neutral's attack landed on the puller: its HP fell since the last frame
 * while a tagged neutral had it as its attack target (`onPuller`) and no enemy hero or lane creep within 1,600 did (their
 * damage would look the same). Counts fl, lc for the pull line.
 */
function landing(bot: Unit, p: Pull, onPuller: boolean): boolean {
    const hp = bot.GetHealth();
    const prev = p.lastHp;
    p.lastHp = hp;
    if (prev === undefined || hp >= prev || !onPuller) return false;
    for (const kind of [UnitType.EnemyHeroes, UnitType.EnemyCreeps]) {
        for (const e of GetUnitList(kind)) {
            if (e.IsAlive() && GetUnitToUnitDistance(e, bot) <= 1600 && e.GetAttackTarget() === bot) return false;
        }
    }
    const now = DotaTime();
    if (p.fl === undefined) p.fl = now;
    p.lc = (p.lc ?? 0) + 1;
    return true;
}

/** Our lane creeps within `radius` of the meet point or of the camp origin: a wave the neutrals walk back from follows them
 *  into the camp and fights there (pw1: the Radiant safe small camp sits about 1100 from its meet point, so a watch of the
 *  meet point alone logged those waves as never diverted). */
/** How far `at` is from `stand` towards the meet point (negative: back towards the camp). */
function stepped(p: Plan, stand: Vector, at: Vector): number {
    const dx = p.meet.x - stand.x;
    const dy = p.meet.y - stand.y;
    const l = math.max(1, math.sqrt(dx * dx + dy * dy));
    return math.floor(((at.x - stand.x) * dx + (at.y - stand.y) * dy) / l + 0.5);
}

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
    if (p.label !== "hold" && p.label !== "lead" && p.label !== "watch") return;
    watchLine(bot, p, p.label);
    diag(bot, p, trackCreeps);
    diag(bot, p, trackHero);
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
    diag(bot, p, trackCreeps);
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
        const r = u.GetAttackRange();
        if (p.nar === undefined || r > p.nar) p.nar = r;
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
    // A half pull's search also picks where the puller stands: the lead's end, which the verb walks after the hit (with the
    // step-in, HalfStepBack behind it, stepping in during the watch).
    const lead = [...p.lead];
    // Slice pull-aggro: a full pull timed on the puller (PullTiming.OnHero) holds at the camp until its leave time.
    const onHero = pull.timer.hero !== undefined;
    const stepIn = pull.timer.keep > 0 && s.PullTiming.HalfStepIn === true;
    if (stepIn && lead.length > 0) lead[lead.length - 1] = PullTiming.StepBackPoint(p.spawner.location, pull.timer.stand ?? p.meet, p.timing.lanePath);
    // The hit follows the wave until the order goes out (the verb reads `earlier` every frame of the wait).
    camp.earlier = () => {
        if (onHero) heroFor(bot, p, pull.timer, pull);
        pull.hitAt = PullTiming.Read(pull.timer, DotaTime());
        if (pull.timer.stand !== undefined && lead.length > 0)
            lead[lead.length - 1] = stepIn ? PullTiming.StepBackPoint(p.spawner.location, pull.timer.stand, p.timing.lanePath) : pull.timer.stand;
        return aggroAt - pull.hitAt;
    };
    const stepAt = stepIn
        ? () => {
              const end = pull.timer.stand ?? p.meet;
              const engaged = laneCreepsNear(p, s.Radii.MeetWatch).some((c) => onNeutral(c));
              const here = bot.GetLocation();
              // The camp's neutrals as offsets from the puller: they follow it, so a step moves them too.
              const offs: Vector[] = [];
              let ranged = false;
              for (const u of pull.tagged ?? []) {
                  if (stale(u)) continue;
                  // A tagged neutral out of vision is alive with no location (phhar8: every watch errored on it).
                  const l = u.GetLocation();
                  if (l === undefined || l === null) continue;
                  offs.push(Vector(l.x - here.x, l.y - here.y, 0));
                  if (u.GetAttackRange() >= s.PullTiming.HalfRangedFrom) ranged = true;
              }
              const byNeutrals = s.PullTiming.HalfStepNeutrals === true;
              const at = PullTiming.StepIn(pull.timer, p.spawner.location, end, p.meet, DotaTime(), engaged, here, byNeutrals ? offs : undefined, byNeutrals && ranged);
              // hi: the puller's offset off the lane path when the creeps engage (with the step-in `end` is the meet point,
              // so a measure along end-to-meet would be 0: review 2026-11-05-pull-half M1).
              if (engaged && pull.stepIn === undefined) {
                  const path = p.timing.lanePath;
                  pull.stepIn = path !== undefined ? math.floor(PullTiming.Along(path, here)[1] + 0.5) : stepped(p, end, here);
              }
              return at as unknown as Lib.Vec;
              }
        : undefined;
    // Slice pull-aggro: the leave time follows the wave through the hold (the hit's read goes on); the deadline is read
    // through the hold, the lead and the watch, which ends WatchAfterWave after it.
    const holdUntil = onHero
        ? () => {
              PullTiming.Read(pull.timer, DotaTime());
              const leave = PullTiming.Leave(pull.timer) ?? DotaTime();
              if (pull.lvp === undefined) pull.lvp = leave;
              return leave;
          }
        : undefined;
    return {
        holdUntil,
        aggroed: onHero ? () => onPuller(bot, pull) : undefined,
        aggroFor: s.PullTiming.LockFor,
        deadline: onHero ? () => deadlineCause(pull) : undefined,
        bail: () => bailPoint(bot) as unknown as Lib.Vec | undefined,
        bailFor: SETTINGS.BailFor,
        camp,
        aggroAt,
        lead: lead as unknown as Lib.Vec[],
        watchAt: () => {
            const step = stepAt?.();
            const shed = shedPoint(bot, pull);
            return (shed ?? step) as unknown as Lib.Vec | undefined;
        },
        watchSec: s.Timing.WatchSec,
        watchUntil: () => {
            if (onHero) return deadlineCause(pull) !== undefined ? pull.dlAt! + s.PullTiming.WatchAfterWave : math.huge;
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
            if ((l === "hold" || l === "lead") && p.hat === undefined) diag(bot, p, tagCamp);
            if (l === "lead" && p.lva === undefined && p.hat !== undefined) p.lva = DotaTime();
            if (l === "watch" && p.arrAt === undefined) p.arrAt = DotaTime();
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
    const full = planFor(bot, now, "full");
    if (full === undefined || handled[pid] === full.key) return false;
    // A wave decided a half pull waits for the half's own (later) leave time.
    const kind = decided[pid]?.slot === full.key ? decided[pid]!.kind : "full";
    const half = kind === "half" ? planFor(bot, now, "half") : undefined;
    // No half plan for this camp: the full plan runs and the decision says so, so choice and pull_job agree on pk.
    if (kind === "half" && half === undefined && decided[pid] !== undefined) decided[pid]!.kind = "full";
    const p = half ?? full;
    const walk = travel(bot, p);
    // Once our wave is out its creeps time the hit (pull_timing's CreepTimer); the leave time, the late check and the hit all
    // use that second (pw2: 12 starts planned against the slot failed `late` while still walking, the wave being early).
    let timer = timers[pid];
    if (timer === undefined || timer.slot !== p.slot) {
        const cfg = LaneConfig.Settings().PullTiming;
        timer =
            p.kind === "half"
                ? PullTiming.Timer(p.timing, p.slot, 1, cfg.HalfClear, 2, bot.GetCurrentMovementSpeed())
                : PullTiming.Timer(p.timing, p.slot, 0, cfg.FullPast);
        timers[pid] = timer;
    }
    heroFor(bot, p, timer);
    const hitAt = PullTiming.Read(timer, now);
    if (now < hitAt - walk - SETTINGS.Early) return false;
    let d = decided[pid];
    if (d === undefined || d.slot !== p.key) {
        const reading = LanePush.Read(bot.GetTeam(), bot.GetAssignedLane());
        // The half-pull harness (HalfAll) wants every slot of the half-pulling support, so the hit and step-in get read
        // many times a game; the lane reading's trigger is checked in normal games.
        const harness = LaneConfig.Settings().PullTiming.HalfAll === true && KindFor(bot, reading) === "half";
        const gone = LanePush.WaveGoneNow(bot.GetTeam(), bot.GetAssignedLane(), PulledSpawn(p.key), p.key + SETTINGS.ArriveAfter);
        const tgt = LanePush.TargetOf(bot.GetAssignedLane());
        const hold = CoreToHold(bot) !== undefined;
        // Slice lane-control 2b: the lane controller's decision for the pulled wave says whether to pull (rule `ctl`); the
        // pull keeps its own gates below. With no decision for that wave, the pull's own triggers decide.
        const LaneControl = require("bots/FunLib/humaniser/lane_control") as typeof import("bots/FunLib/humaniser/lane_control");
        const ctl = LaneControl.DecisionFor(bot.GetTeam(), bot.GetAssignedLane(), PulledSpawn(p.key));
        const byCtl = ctl !== undefined && CtlWants(ctl, pid);
        const byNew = ctl === undefined && Wanted(gone, tgt);
        const byOld = ctl === undefined && hold && OldWanted(reading, tgt);
        const rule = byCtl ? "ctl" : byNew && byOld ? "both" : byNew ? "new" : byOld ? "old" : undefined;
        const want = rule !== undefined || harness;
        d = { slot: p.key, want, kind: want ? KindFor(bot, reading) : "full", reading, gone, hold, rule, ctl: ctl !== undefined };
        if (want && d.kind === "full" && halfWanted(bot, reading) && MeleeSpawn(bot)) d.pm = 1;
        decided[pid] = d;
        gateWhy[pid] = undefined;
        if (d.kind === "half") return false;
    }
    const camp = CampStateOf(p.spawner);
    const done = (go: boolean, why: string | undefined) => {
        handled[pid] = p.key;
        gateWhy[pid] = undefined;
        choiceLine(bot, d!, p.slot, go, why, camp);
    };
    // Slice pull-aggro: a half whose spawn is seen melee before the hit becomes the full pull while its second is still
    // ahead, else stays (half-melee: a coverage count, not a miss).
    if (d.want && d.kind === "half" && MeleeSpawn(bot)) {
        d.pm = 1;
        if (now < full.slot - travel(bot, full)) {
            d.kind = "full";
            return false;
        }
        done(false, "half-melee");
        return false;
    }
    if (!d.want) {
        done(false, d.ctl === true ? "ctl" : d.reading === undefined ? "no-read" : "lane");
        return false;
    }
    // No hit splits the wave: a half that takes all four is the full pull the lane reading turned down.
    if (d.kind === "half" && timer.margin !== undefined && timer.margin <= 0) {
        d.hm = timer.margin;
        done(false, "half-geo");
        return false;
    }
    camp.dmg = CampDamage(bot, camp, p.spawner.type);
    camp.php = bot.GetHealth();
    const site = siteThreat(p, camp);
    // Slice pull-aggro: no window (the wave enters after the predicted give-up or clash) holds the start like a gate.
    const noWin = timer.hero !== undefined && timer.nowin !== undefined ? "no-window" : undefined;
    d.nw = timer.nowin;
    d.nws = timer.hero !== undefined && timer.slack !== undefined ? math.floor(timer.slack * 100 + 0.5) / 100 : undefined;
    // Review M2: the entry and the predicted clash the window was judged on.
    d.ent = timer.hero !== undefined && timer.ent !== undefined ? math.floor(timer.ent * 100 + 0.5) / 100 : undefined;
    d.clp = timer.hero !== undefined && timer.clp !== undefined ? math.floor(timer.clp * 100 + 0.5) / 100 : undefined;
    const why = CampGate(camp, now, hitAt) ?? noWin ?? blocked(bot) ?? campDmgGate(bot, camp.dmg) ?? site ?? PartnerThreat(bot) ?? (acting(bot) ? "acting" : undefined);
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
        // Slice pull-aggro: the wave read on the walk may close the window (the entry after the predicted give-up or clash).
        const why = CampGate(s, DotaTime(), p.hitAt) ?? campDmgGate(bot, s.dmg) ?? (p.timer.hero !== undefined && p.timer.nowin !== undefined ? "no-window" : undefined);
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
