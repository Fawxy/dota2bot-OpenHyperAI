/**
 * Stack execution (slice 4, switch Ours.StackExecute, KR S.2a): on a placeholder trigger (minutes 3, 5 and 7) the
 * pos5 stacks its nearest own-side camp with the `stack` job verb, then watches the box for the outcome. OHA has no
 * stacking code; with the switch off the pos5 never stacks. Hosted by mode_farm_generic (Desire, Think, Abort).
 * One `ev=stack` line per trigger minute: the attempt's result, or `res=skip` with the reason no job started.
 * When to stack, and who, is S.2b: it replaces TRIGGER_MINUTES and keeps the job and its result line.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
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
    /** Seconds of slack on the straight-line walk to the stand point: the path around trees and the camp ran ~6 s over (probe 4). */
    Lead: 5,
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
    /** Seconds in another mode before the job counts as preempted. */
    PreemptAfter: 1,
    /** The watch for the outcome ends this long after the next minute's :00 spawn check. */
    WatchUntil: 5,
};

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
}

const handled: Record<number, Record<number, boolean>> = {};
const gateWhy: Record<number, string | undefined> = {};
const running: Record<number, Attempt | undefined> = {};

export function ResetCache(): void {
    for (const k in handled) delete handled[k];
    for (const k in gateWhy) delete gateWhy[k];
    for (const k in running) delete running[k];
}

/** The switch is on and `bot` is OHA position 5. */
export function Applies(bot: Unit): boolean {
    return Ours.On("StackExecute") && LaneConfig.PositionOf(bot) === 5;
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
        const p = Stacking.StandPoint(sp, data);
        if (stand === undefined || dist(loc, p) < dist(loc, stand)) {
            best = data;
            stand = p;
        }
    }
    return $multi(best, stand);
}

/** An enemy hero in reach or hero damage just now: the gate's hero checks, also run every frame of a running job (the
 *  1x probe s4p7: the pos5 was hit at 61% on the walk, kept going and died at the camp to two heroes). HP and mode are not
 *  checked mid-job: the camp's neutrals hit the bot by design, and the mode is ours. */
function Threat(bot: Unit): string | undefined {
    if ((bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length > 0) return "enemy-near";
    if (bot.WasRecentlyDamagedByAnyHero(SETTINGS.HitWithin)) return "hit";
    return undefined;
}

/** Why the pos5 may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
 *  hero just now, or fighting or retreating. */
export function Gate(bot: Unit): string | undefined {
    if (bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MinHpFraction) return "low-hp";
    const threat = Threat(bot);
    if (threat !== undefined) return threat;
    const mode = bot.GetActiveMode();
    if (mode === BotMode.Attack || mode === BotMode.Retreat) return "busy";
    return undefined;
}

/** The stack verb's plan for `data` in `minute`: the hit lands on the camp's stack second of that minute. */
export function Plan(bot: Unit, data: Camps.CampJobData, stand: Vector, minute: number, a: Attempt): JobVerbs.StackPlan {
    const sp = Camps.SpawnerByIdx(data.campIdx)!;
    const r = LaneConfig.Settings().Radii;
    const t = LaneConfig.Settings().Timing;
    const start = minute * 60;
    // Seen nothing from the stand point (trees, high ground, night): step in to ApproachDist from the origin. Not camp_jobs'
    // StandApproach (150): hit from 84-124 the neutral had moved 57-72 two seconds later and stayed in the box; hits from
    // 389-450 drew it 300-600 out (probe s4p4). Lich saw evil_1 from 274 (probe 4). 250, not 300: witch doctor's evil_2
    // stand point is 383 from the origin, so 300 lay inside the arrive radius and the bot never stepped in (probe s4p5).
    const o = sp.location;
    const d = math.max(1, ((stand.x - o.x) ** 2 + (stand.y - o.y) ** 2) ** 0.5);
    const near = math.min(d, SETTINGS.ApproachDist);
    const approach = Vector(o.x + ((stand.x - o.x) * near) / d, o.y + ((stand.y - o.y) * near) / d, o.z);
    return {
        camp: {
            stand: stand as unknown as Lib.Vec,
            box: { min: sp.min as unknown as Lib.Vec, max: sp.max as unknown as Lib.Vec },
            origin: sp.location as unknown as Lib.Vec,
            margin: r.BoxMargin,
            search: r.NeutralSearch,
            confirmed: () => CampJobs.Exec.NeutralTargets(bot),
            approach: approach as unknown as Lib.Vec,
        },
        // 6 s, not camp_jobs' StandApproachLead (3): from the stand the camp was first seen at :55, so the hit landed at
        // :55.8-57.7 with the camp back in its box at :59.5 (probe s4p2, lich on evil_1 and evil_2).
        approachLead: SETTINGS.ApproachLead,
        aggroAt: start + Stacking.AggroSec(data),
        exitPath: data.stack!.exitPath as unknown as Lib.Vec[],
        exitUntil: start + 60 + t.StackExitUntil,
        arrive: r.JobArrive,
        onAggro: info => {
            a.before = CampJobs.Exec.NeutralsInBox(bot, data.campIdx);
            a.aggro = info.confirmedAt - start;
            a.target = info.target as unknown as Unit | undefined;
            a.hitd = math.floor(GetUnitToLocationDistance(bot, sp.location));
        },
    };
}

/** Seconds to walk from the bot to `p`. */
function travel(bot: Unit, p: Vector): number {
    return GetUnitToLocationDistance(bot, p) / math.max(1, bot.GetCurrentMovementSpeed());
}

function* body(bot: Unit, plan: JobVerbs.StackPlan, a: Attempt, ctx: Lib.Ctx): Lib.TaskBody {
    const r = yield* Tasks.Jobs()!.stack(bot as unknown as Lib.TaskUnit, plan, { label: ctx.label, urgent: ctx.urgent });
    if (!r.success) return r;
    // Watch: walk towards the camp until its origin is in sight (night vision is 800, the exit point ~900 past the box),
    // count the box, and end once it holds more than at the hit or at :00 + WatchUntil.
    ctx.label("watch");
    const sp = Camps.SpawnerByIdx(a.campIdx)!;
    const spawnCheck = a.minute * 60 + 60;
    const outcomeAt = spawnCheck + LaneConfig.Settings().Timing.StackOutcomeAt;
    let stopped = false;
    while (DotaTime() < spawnCheck + SETTINGS.WatchUntil) {
        if (!bot.IsAlive()) return { success: false, reason: "dead" };
        if (CampJobs.Exec.BoxInSight(bot, a.campIdx)) {
            if (!stopped) bot.Action_MoveToLocation(bot.GetLocation());
            stopped = true;
            if (DotaTime() >= outcomeAt) {
                a.after = math.max(a.after ?? 0, CampJobs.Exec.NeutralsInBox(bot, a.campIdx));
                if (a.after > (a.before ?? 0)) break;
            }
        } else {
            bot.Action_MoveToLocation(sp.location);
        }
        yield;
    }
    return { success: true, reason: "ok" };
}

function log(bot: Unit, minute: number, fields: [string, any][]): void {
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
    const res = !landed ? "failed" : a.after !== undefined && a.after > (a.before ?? 0) ? "stacked" : "not_stacked";
    log(bot, a.minute, [
        ["res", res],
        ["why", result.success ? "ok" : `${result.reason}${result.message !== undefined ? ":" + result.message : ""}`],
        ["camp", a.campIdx],
        ["type", a.type],
        ["start", math.floor(a.startedAt * 10) / 10],
        ["aggro", a.aggro !== undefined ? math.floor(a.aggro * 10) / 10 : "?"],
        ["before", a.before ?? "?"],
        ["after", a.after ?? "?"],
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
    ]);
}

/** mode_farm_generic GetDesire: the job's desire while it runs or as it starts, else 0 (OHA decides). */
export function Desire(bot: Unit): number {
    if (!Applies(bot)) return 0;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) {
        const threat = Threat(bot);
        if (threat === undefined) return SETTINGS.Desire;
        Tasks.Cancel(bot, "cancelled", threat);
        return 0;
    }
    const now = DotaTime();
    handled[pid] = handled[pid] ?? {};
    for (const minute of SETTINGS.TriggerMinutes) {
        if (handled[pid][minute] || now < minute * 60 + SETTINGS.LookFrom || now >= minute * 60 + 60) continue;
        const [data, stand] = Nearest(bot.GetTeam(), bot.GetLocation());
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
        const aggroAt = minute * 60 + Stacking.AggroSec(data);
        const walk = travel(bot, stand);
        if (now < aggroAt - walk - SETTINGS.Lead) return 0;
        if (now > aggroAt - walk - SETTINGS.MinSlack) return skip(gateWhy[pid] ?? "late");
        const why = Gate(bot);
        if (why !== undefined) {
            gateWhy[pid] = why;
            return 0;
        }
        const a: Attempt = { minute, campIdx: data.campIdx, type: data.type, startedAt: now };
        const plan = Plan(bot, data, stand, minute, a);
        const ok = Tasks.Start(bot, { name: "stack", host: BotMode.Farm, preemptAfter: SETTINGS.PreemptAfter, onEnd: result => finish(bot, a, result) }, (ctx: Lib.Ctx) =>
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
    if (a.tgt2 === undefined && a.aggro !== undefined && DotaTime() >= a.minute * 60 + a.aggro + 2) a.tgt2 = targetDist(a) ?? -1;
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
    a.pulled59 = pulled;
    a.bot59 = Camps.InBox(a.campIdx, bot.GetLocation(), 0) ? 1 : 0;
    a.vis59 = IsLocationVisible(sp.location) ? 1 : 0;
    const path = data?.stack?.exitPath;
    a.exit59 = path !== undefined && path.length > 0 ? math.floor(GetUnitToLocationDistance(bot, path[path.length - 1])) : undefined;
}

export function Think(bot: Unit): boolean {
    const a = running[bot.GetPlayerID()];
    if (a === undefined) return false;
    sample59(bot, a);
    return Tasks.Step(bot, BotMode.Farm);
}

/**
 * mode_farm_generic's ShouldRun: neutrals hitting the pos5 during its stack are not a reason to run; the job's exit is its
 * retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
 */
export function HoldsRun(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

/** OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`. */
export function Abort(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}
