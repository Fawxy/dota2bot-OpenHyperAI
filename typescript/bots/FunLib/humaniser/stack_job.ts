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
    /** Seconds the bot arrives at the stand point before the hit. */
    Lead: 2,
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

/** Why the pos5 may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
 *  hero just now, or fighting or retreating. */
export function Gate(bot: Unit): string | undefined {
    if (bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MinHpFraction) return "low-hp";
    if ((bot.GetNearbyHeroes(SETTINGS.EnemyRadius, true, BotMode.None) ?? []).length > 0) return "enemy-near";
    if (bot.WasRecentlyDamagedByAnyHero(SETTINGS.HitWithin)) return "hit";
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
    return {
        camp: {
            stand: stand as unknown as Lib.Vec,
            box: { min: sp.min as unknown as Lib.Vec, max: sp.max as unknown as Lib.Vec },
            origin: sp.location as unknown as Lib.Vec,
            margin: r.BoxMargin,
            search: r.NeutralSearch,
            confirmed: () => CampJobs.Exec.NeutralTargets(bot),
        },
        aggroAt: start + Stacking.AggroSec(data),
        exitPath: data.stack!.exitPath as unknown as Lib.Vec[],
        exitUntil: start + 60 + t.StackExitUntil,
        arrive: r.JobArrive,
        onAggro: info => {
            a.before = CampJobs.Exec.NeutralsInBox(bot, data.campIdx);
            a.aggro = info.confirmedAt - start;
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

function finish(bot: Unit, a: Attempt, result: Lib.Result): void {
    running[bot.GetPlayerID()] = undefined;
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
    ]);
}

/** mode_farm_generic GetDesire: the job's desire while it runs or as it starts, else 0 (OHA decides). */
export function Desire(bot: Unit): number {
    if (!Applies(bot)) return 0;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return SETTINGS.Desire;
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
        if (now > aggroAt - walk) return skip(gateWhy[pid] ?? "late");
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
export function Think(bot: Unit): boolean {
    if (running[bot.GetPlayerID()] === undefined) return false;
    return Tasks.Step(bot, BotMode.Farm);
}

/** OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`. */
export function Abort(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}
