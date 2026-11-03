/**
 * The pull (slice support-lane, switch Ours.SupportPull, KR S.3): a pos4/pos5 takes our wave into its lane's first pull camp
 * when the lane push reading wants it, then comes back to lane. The job chooser hosts it and decides when it may start; this
 * module reads the lane once per pull slot (`ev=choice kind=pull`), plans the pull from the camp data (`camps`,
 * `pull_timing`), walks it with the job verb `pull` and logs one `ev=pull_job` line per started pull.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { Lane, Team, Unit, UnitType, Vector } from "bots/ts_libs/dota";
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
    /** Leave this long before the walk alone would arrive, so the bot stands at the camp before the hit. */
    Early: 2,
    /** Walking paths run longer than the straight line (rune_job's PathFactor). */
    PathFactor: 1.2,
    /** HOLD counts as wanting a pull once the clash point sits this far from our T1 towards theirs (0 ours, 1 theirs). */
    HoldPastQ: 0.5,
    /** The lane partner is under threat: HP share below PartnerHp with an enemy hero within PartnerRadius, or PartnerGank
     *  enemy heroes within it. */
    PartnerHp: 0.5,
    PartnerRadius: 900,
    PartnerGank: 3,
    /** Our creeps within MeetWatch of the meet point are watched; a creep attacking a neutral is diverted. Wave size: our
     *  creeps within WaveSize when the first one is seen diverted (camp_jobs' sample, LaneConfig Radii). */
    WatchEvery: 0.25,
    /** After a job that ended ok, keep sampling the wave this long past the later of the job end and the wave's due time:
     *  the job ends 3 s after the wave is due, while its later creeps are still reaching the neutrals (sp2: pulls logged at
     *  div 0.25 moved the lane back the most, `eq` -1.65 in 30 s, about 0.8 of the T1-T1 stretch). */
    TrailSec: 10,
    /** `ev=pull_watch` cadence: one line per pull per this many seconds from the lead to the end of the trail. */
    WatchLogEvery: 1,
    /** The neutral `nd`/`nh`/`nt` describe is the nearest within this of the meet point, so a camp that never followed still shows. */
    WatchNeutralSearch: 3000,
};

interface Plan {
    camp: Camps.CampJobData;
    spawner: Camps.Spawner;
    stand: Vector;
    lead: Vector[];
    meet: Vector;
    timing: PullTiming.PullTiming;
    /** The planned hit second (no skill error), and when our wave should reach the meet point. */
    slot: number;
    waveAt?: number;
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
}

interface Decision {
    slot: number;
    want: boolean;
    reading?: LanePush.Reading;
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
const gateWhy: Record<number, string | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, trailing, handled, decided, gateWhy] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
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

export function Priority(bot: Unit): number | undefined {
    return Applies(bot) ? SETTINGS.Priority : undefined;
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

function planFor(bot: Unit, now: number): Plan | undefined {
    const camp = campFor(bot);
    const spawner = camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
    if (camp === undefined || camp.pull === undefined || spawner === undefined) return undefined;
    const t = LaneConfig.Settings().Timing;
    const timing = PullTiming.ForCamp(camp, false);
    if (timing.seconds.length === 0) return undefined;
    const slot = NextSlot(now - t.JobStartLate, timing.seconds, t.PullPeriod);
    // Camps hold neutrals for a whole minute only from their first spawn on (camp_jobs' CampsUp).
    if (math.floor(slot / t.PullPeriod) * t.PullPeriod < t.NeutralFirstSpawn) return undefined;
    const meet = camp.pull.meetPoint;
    const lead = PullTiming.LeadPath(camp.pull, meet);
    const stand = Camps.StandPoint(spawner, lead[0], LaneConfig.Settings().Radii.StandOffset);
    return { camp, spawner, stand, lead, meet, timing, slot, waveAt: timing.waveAfter !== undefined ? slot + timing.waveAfter : undefined };
}

function travel(bot: Unit, p: Plan): number {
    return (GetUnitToLocationDistance(bot, p.stand) * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed());
}

/** The reading wants a pull: our clash point moves out (towards their tower), or holds past the middle on their side. */
export function Wanted(r: LanePush.Reading | undefined): boolean {
    if (r === undefined) return false;
    return r.state === "OUT" || (r.state === "HOLD" && r.q > SETTINGS.HoldPastQ);
}

/** Why the lane partner (a teammate core assigned to the lane) should not be left now, else undefined. */
function partnerThreat(bot: Unit): string | undefined {
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

/** OHA's own action holds the hero (rune_job's check: a queued TP, a cast or channel). */
function acting(bot: Unit): boolean {
    return bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility();
}

function choiceLine(bot: Unit, d: Decision, go: boolean, why: string | undefined): void {
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
        ["slot", d.slot],
        ["st", r?.state],
        ["q", r !== undefined ? math.floor(r.q * 100 + 0.5) / 100 : undefined],
        ["mv", r1(r?.move)],
        ["cf", r1(r?.cf)],
        ["tw", r !== undefined ? (r.tower ? 1 : 0) : undefined],
        ["ms", r?.ms],
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
    ];
    if (!r.success) {
        Telemetry.Event("pull_job", fields);
        return;
    }
    const now = DotaTime();
    trailing[bot.GetPlayerID()] = { pull: p, fields, until: math.max(now, p.plan.waveAt ?? now) + SETTINGS.TrailSec };
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
        sampleWave(tr.pull);
        watchLine(bot, tr.pull, "trail");
        return;
    }
    trailing[pid] = undefined;
    Telemetry.Event("pull_job", [...tr.fields, ["dt", share(tr.pull)]]);
}

function laneCreepsNear(center: Vector, radius: number): Unit[] {
    const out: Unit[] = [];
    for (const c of GetUnitList(UnitType.AlliedCreeps)) {
        if (!c.IsAlive() || !LanePush.IsLaneCreep(c.GetUnitName())) continue;
        if (GetUnitToLocationDistance(c, center) <= radius) out.push(c);
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
}

function sampleWave(p: Pull): void {
    const now = DotaTime();
    if (p.sampledAt !== undefined && now - p.sampledAt < SETTINGS.WatchEvery) return;
    p.sampledAt = now;
    countDiverted(p);
}

function countDiverted(p: Pull): void {
    const radii = LaneConfig.Settings().Radii;
    let n = 0;
    for (const c of laneCreepsNear(p.plan.meet, radii.MeetWatch)) if (onNeutral(c)) n++;
    if (n === 0) return;
    if (p.wave === 0) p.wave = math.max(1, laneCreepsNear(p.plan.meet, radii.WaveSize).length);
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
 * One `ev=pull_watch` sample: what our creeps near the meet point attack, and where the neutrals are and what they attack
 * (slice support-lane open item: waves at the meet point with neutrals near that never hit one). `nd`, `nh`, `nt` describe
 * the neutral closest to any of our creeps near the meet point (or to the meet point when none is), counted or not in `nn`.
 */
function watchLine(bot: Unit, p: Pull, ph: string): void {
    const now = DotaTime();
    if (p.watchedAt !== undefined && now - p.watchedAt < SETTINGS.WatchLogEvery) return;
    p.watchedAt = now;
    const radii = LaneConfig.Settings().Radii;
    const meet = p.plan.meet;
    const ours = laneCreepsNear(meet, radii.MeetWatch);
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
    ]);
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

function verbPlan(p: Plan, aggroAt: number): JobVerbs.PullPlan {
    const s = LaneConfig.Settings();
    return {
        camp: verbCamp(p),
        aggroAt,
        lead: p.lead as unknown as Lib.Vec[],
        watchSec: s.Timing.WatchSec,
        watchUntil: p.waveAt !== undefined ? p.waveAt + s.PullTiming.WatchAfterWave : undefined,
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
        },
        urgent: ctx.urgent,
    };
    return yield* Tasks.Jobs()!.pull(bot as unknown as Lib.TaskUnit, verbPlan(p.plan, aggroAt), hooks);
}

/** The pull side of the lane path: our walking wave is everything of ours short of the meet point (the counterfactual). */
function meetAlong(bot: Unit, p: Plan): number | undefined {
    const path = LanePush.PathOf(bot.GetAssignedLane());
    return path !== undefined ? LanePush.Project(path, p.meet.x, p.meet.y)[0] : undefined;
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
    if (p === undefined || handled[pid] === p.slot) return false;
    const walk = travel(bot, p);
    if (now < p.slot - walk - SETTINGS.Early) return false;
    let d = decided[pid];
    if (d === undefined || d.slot !== p.slot) {
        const reading = LanePush.Read(bot.GetTeam(), bot.GetAssignedLane(), meetAlong(bot, p));
        d = { slot: p.slot, want: Wanted(reading), reading };
        decided[pid] = d;
        gateWhy[pid] = undefined;
    }
    const done = (go: boolean, why: string | undefined) => {
        handled[pid] = p.slot;
        gateWhy[pid] = undefined;
        choiceLine(bot, d!, go, why);
    };
    if (!d.want) {
        done(false, d.reading === undefined ? "no-read" : "lane");
        return false;
    }
    const why = blocked(bot) ?? partnerThreat(bot) ?? (acting(bot) ? "acting" : undefined);
    if (now + walk > p.slot + LaneConfig.Settings().Timing.JobStartLate) {
        done(false, gateWhy[pid] ?? why ?? "late");
        return false;
    }
    if (why !== undefined) {
        gateWhy[pid] = why;
        return false;
    }
    // The wave left its barracks by now: its lead says how early or late it really is (pull_timing's LiveShift).
    const aggroAt = p.slot + (PullTiming.LiveShift(p.timing, p.slot, now) ?? 0);
    trail(bot, true);
    const pull: Pull = { plan: p, left: now, host, wave: 0, peak: 0, neutrals: 0 };
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
    sample(bot, p);
    return Tasks.Step(bot, host);
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
