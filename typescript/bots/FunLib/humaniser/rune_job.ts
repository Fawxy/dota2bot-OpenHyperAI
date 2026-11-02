/**
 * Rune rotation (slice rune-rotation, switch Ours.RuneRotation, KR M.1): on a plain trigger a support leaves lane to be at
 * a rune spawn by its time. Pos4: the 6:00 power rune and its own 7:00 wisdom shrine; pos5: the 6:00 power rune, ranked
 * below its stack. The job chooser hosts it and decides when it may start; this module says when it wants to run, walks
 * the trip (the job verb `runeRun`) and logs one `ev=rune_job` line per trip or skip.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { Rune, Unit, Vector } from "bots/ts_libs/dota";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;

type Kind = "power" | "wisdom";

// All judgement (slice file, Decisions).
export const SETTINGS = {
    /** Spawns each position goes for. Power at 6:00, the shrine at 7:00 (transitions/runes RUNE_RULES). */
    Trips: { [4]: [["power", 360], ["wisdom", 420]], [5]: [["power", 360]] } as Record<number, [Kind, number][]>,
    /** Rank against the hero's other jobs (the stack job is 0.92): pos4's trip holds its 5:5x stack back, pos5's yields. */
    Priority: { [4]: 0.95, [5]: 0.85 } as Record<number, number>,
    /** The trip claims the hero this long before the spawn, so a lower job does not start in its way. */
    ClaimFrom: 60,
    /** A start held back (gate or another job) past its leave time by this much is skipped: it would arrive late. */
    StartSlack: 3,
    /** Walking paths run longer than the straight line (states/rotate's PATH_FACTOR). */
    PathFactor: 1.2,
    /** Not at the spot this long after the spawn: the verb ends `timeout:late`. Power: the verb's default. */
    LateBy: { power: 5, wisdom: 15 } as Record<Kind, number>,
    /** Liquipedia/7.41: stand within 300 of the shrine for 3 s. */
    ShrineChannel: 3,
    ShrineRadius: 300,
};

interface Trip {
    kind: Kind;
    spawn: number;
    side?: string;
    at: Vector;
    rune?: number;
    left: number;
    arr?: number;
    host: number;
    hit?: boolean;
    idle?: number;
}

const running: Record<number, Trip | undefined> = {};
const handled: Record<number, Record<string, boolean>> = {};
const gateWhy: Record<number, string | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(running)) running[k as number] = undefined;
    for (const [k] of pairs(handled)) handled[k as number] = {};
    for (const [k] of pairs(gateWhy)) gateWhy[k as number] = undefined;
}

export function Applies(bot: Unit): boolean {
    return Ours.On("RuneRotation") && Ours.On("JobChooser") && bot.IsBot() && SETTINGS.Trips[LaneConfig.PositionOf(bot) ?? 0] !== undefined;
}

/** This hero's rank for the chooser, or undefined when the job never applies to it. */
export function Priority(bot: Unit): number | undefined {
    return Applies(bot) ? SETTINGS.Priority[LaneConfig.PositionOf(bot) ?? 0] : undefined;
}

function key(kind: Kind, spawn: number): string {
    return `${kind}:${spawn}`;
}

/** The trips still open for this bot now: from ClaimFrom before the spawn until its late limit, not yet handled. */
function open(bot: Unit): [Kind, number][] {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const out: [Kind, number][] = [];
    for (const [kind, spawn] of SETTINGS.Trips[LaneConfig.PositionOf(bot) ?? 0] ?? []) {
        if (handled[pid]?.[key(kind, spawn)] !== true && now >= spawn - SETTINGS.ClaimFrom && now < spawn + SETTINGS.LateBy[kind]) out.push([kind, spawn]);
    }
    return out;
}

/** True while a trip runs or is pending for this bot: lower-ranked jobs wait. */
export function Claims(bot: Unit): boolean {
    return Applies(bot) && (Running(bot) || open(bot).length > 0);
}

function powerRunes(): [number, Vector][] {
    return [Rune.Power1, Rune.Power2].map((r) => [r, GetRuneSpawnLocation(r)] as [number, Vector]);
}

/** The power spot a teammate's trip already has, by rune id. */
function takenSpots(bot: Unit): Record<number, boolean> {
    const out: Record<number, boolean> = {};
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m === bot) continue;
        const t = running[m.GetPlayerID()];
        if (t !== undefined && t.rune !== undefined) out[t.rune] = true;
    }
    return out;
}

/** Pos4: the power spot nearest it. Others: the nearest spot no teammate's trip has, else the nearest. */
function powerSpot(bot: Unit): [number, Vector] {
    const taken: Record<number, boolean> = LaneConfig.PositionOf(bot) === 4 ? {} : takenSpots(bot);
    let best: [number, Vector] | undefined;
    let bestCost = math.huge;
    for (const spot of powerRunes()) {
        const cost = GetUnitToLocationDistance(bot, spot[1]) + (taken[spot[0]] ? 1e6 : 0);
        if (cost < bestCost) [best, bestCost] = [spot, cost];
    }
    return best!;
}

function planFor(t: Trip): JobVerbs.RunePlan {
    if (t.kind === "wisdom") {
        return {
            at: t.at as unknown as Lib.Vec,
            spawnAt: t.spawn,
            channel: SETTINGS.ShrineChannel,
            radius: SETTINGS.ShrineRadius,
            tolerance: SETTINGS.ShrineRadius - 100,
            lateBy: SETTINGS.LateBy.wisdom,
            pickupFor: 20,
        };
    }
    return { at: t.at as unknown as Lib.Vec, spawnAt: t.spawn, rune: t.rune, lateBy: SETTINGS.LateBy.power };
}

/** When to leave for the trip: the verb's skill-scaled arrival less the walk (path factor on the straight line). */
function leaveAt(bot: Unit, t: Trip): number {
    const u = bot as unknown as Lib.TaskUnit;
    const arrive = Tasks.Jobs()!.runeArriveBy(u, planFor(t));
    return arrive - (GetUnitToLocationDistance(bot, t.at) * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed());
}

function tripFor(bot: Unit, kind: Kind, spawn: number, host: number): Trip {
    if (kind === "wisdom") return { kind, spawn, at: Rotate.ShrineFor(bot.GetTeam()), left: DotaTime(), host };
    const [rune, at] = powerSpot(bot);
    return { kind, spawn, at, rune, side: at.y > 0 ? "top" : "bot", left: DotaTime(), host };
}

function log(bot: Unit, kind: Kind, spawn: number, fields: Telemetry.Fields<"rune_job">): void {
    Telemetry.Event("rune_job", [["pid", bot.GetPlayerID()], ["pos", LaneConfig.PositionOf(bot)], ["kind", kind], ["spawn", spawn], ...fields]);
}

function jobLine(bot: Unit, t: Trip, phase: string, why: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "rune"],
        ["phase", phase],
        ["why", why],
        ["host", t.host],
        ...(phase === "end" ? ([["hit", t.hit === true ? 1 : 0]] as Telemetry.Fields<"job">) : []),
    ]);
}

function finish(bot: Unit, t: Trip, r: Lib.Result, label: string | undefined): void {
    running[bot.GetPlayerID()] = undefined;
    const why = r.success ? "ok" : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`;
    jobLine(bot, t, "end", why);
    const r1 = (x: number | undefined) => (x !== undefined ? math.floor(x * 10) / 10 : undefined);
    log(bot, t.kind, t.spawn, [
        ["res", r.success ? "ok" : "fail"],
        ["why", why],
        ["label", label],
        ["side", t.side],
        ["left", r1(t.left)],
        ["arr", r1(t.arr)],
        ["away", r1(DotaTime() - t.left)],
        ["died", bot.IsAlive() ? 0 : 1],
        ["hit", t.hit === true ? 1 : 0],
        ["idle", t.idle],
    ]);
}

/** OHA's own action holds the hero (a queued TP, a cast or channel): the host's Think does not step a job then
 *  (J.CanNotUseAction), so a trip started now ends `never_started` (probe rr2: a pos4 in its fountain with a queued TP). */
function acting(bot: Unit): boolean {
    return bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility();
}

/**
 * Every frame while the chooser asks: true while a trip runs or as one starts. `blocked` says why a start must wait (the
 * chooser's checks, or a higher job's claim); `host` is the mode that will step the trip.
 */
export function Wants(bot: Unit, blocked: (bot: Unit) => string | undefined, host: number): boolean {
    if (!Applies(bot)) return false;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return true;
    if (Tasks.Jobs() === undefined) return false;
    handled[pid] = handled[pid] ?? {};
    for (const [kind, spawn] of open(bot)) {
        const skip = (why: string) => {
            handled[pid][key(kind, spawn)] = true;
            gateWhy[pid] = undefined;
            log(bot, kind, spawn, [["res", "skip"], ["why", why]]);
            return false;
        };
        if (!bot.IsAlive()) {
            gateWhy[pid] = "dead";
            continue;
        }
        const t = tripFor(bot, kind, spawn, host);
        const leave = leaveAt(bot, t);
        if (DotaTime() < leave) return false;
        const why = blocked(bot) ?? (acting(bot) ? "acting" : undefined);
        // The leave time moves with the bot, so it can pass the slack in one frame: name what holds it now, if anything.
        if (DotaTime() > leave + SETTINGS.StartSlack) return skip(gateWhy[pid] ?? why ?? "late");
        if (why !== undefined) {
            gateWhy[pid] = why;
            return false;
        }
        const ok = Tasks.Start(bot, { name: "rune", host, preemptAfter: 1, stallAfter: 4, onEnd: (r, info) => finish(bot, t, r, info.label) }, (ctx: Lib.Ctx) =>
            body(bot, t, ctx)
        );
        if (!ok) return skip("refused");
        handled[pid][key(kind, spawn)] = true;
        gateWhy[pid] = undefined;
        running[pid] = t;
        jobLine(bot, t, "start", "trigger");
        return true;
    }
    return false;
}

function* body(bot: Unit, t: Trip, ctx: Lib.Ctx): Lib.TaskBody {
    const hooks: JobVerbs.JobHooks = {
        label: (l) => {
            ctx.label(l);
            if ((l === "wait" || l === "channel") && t.arr === undefined) t.arr = DotaTime();
        },
        urgent: ctx.urgent,
    };
    return yield* Tasks.Jobs()!.runeRun(bot as unknown as Lib.TaskUnit, planFor(t), hooks);
}

export function Step(bot: Unit, host: number): boolean {
    return running[bot.GetPlayerID()] !== undefined && Tasks.Step(bot, host);
}

export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

export function End(bot: Unit, why: string): void {
    if (running[bot.GetPlayerID()] !== undefined) Tasks.Cancel(bot, "cancelled", why);
}

export function NoteHit(bot: Unit): void {
    const t = running[bot.GetPlayerID()];
    if (t !== undefined) t.hit = true;
}

export function NoteIdleHeld(bot: Unit): void {
    const t = running[bot.GetPlayerID()];
    if (t !== undefined) t.idle = (t.idle ?? 0) + 1;
}

/** A teammate of `team` is on a shrine trip: OHA's own wisdom logic leaves the shrine to it. */
export function ShrineTaken(team: number): boolean {
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m.GetTeam() !== team) continue;
        if (running[m.GetPlayerID()]?.kind === "wisdom") return true;
    }
    return false;
}
