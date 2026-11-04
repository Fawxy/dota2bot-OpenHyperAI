/**
 * Rune rotation (slice rune-rotation, switch Ours.RuneRotation, KR M.1): on a plain trigger a support leaves lane to be at
 * a rune spawn by its time. Pos4: the 6:00 power rune and its own 7:00 wisdom shrine; pos5: the 6:00 power rune, ranked
 * below its stack. The job chooser hosts it and decides when it may start; this module says when it wants to run, walks
 * the trip (the job verb `runeRun`) and logs one `ev=rune_job` line per trip or skip.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Rune, Team, Unit, Vector } from "bots/ts_libs/dota";
import * as JobVerbs from "bots/FunLib/humaniser/job_verbs";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as Plays from "bots/FunLib/humaniser/plays/plays";
import * as RunePlan from "bots/FunLib/humaniser/rune_plan";
import * as StackJob from "bots/FunLib/humaniser/stack_job";
import * as Rotate from "bots/FunLib/humaniser/states/rotate";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare function IsLocationPassable(this: void, loc: Vector): boolean;

type Kind = "power" | "wisdom" | "contest";

// All judgement (slice file, Decisions).
export const SETTINGS = {
    /** Spawns each position goes for. Power at 6:00, the shrine at 7:00 (transitions/runes RUNE_RULES). */
    Trips: { [4]: [["power", 360], ["wisdom", 420]], [5]: [["power", 360], ["contest", 420]] } as Record<number, [Kind, number][]>,
    /** Rank against the hero's other jobs (the stack job is 0.92): pos4's trip holds its 5:5x stack back, pos5's yields. */
    Priority: { [4]: 0.95, [5]: 0.85 } as Record<number, number>,
    /** The trip claims the hero this long before the spawn, so a lower job does not start in its way. */
    ClaimFrom: 60,
    /** A start held back (gate or another job) past its leave time by this much is skipped: it would arrive late. */
    StartSlack: 3,
    /** Walking paths run longer than the straight line (states/rotate's PATH_FACTOR). */
    PathFactor: 1.2,
    /** Not at the spot this long after the spawn: the verb ends `timeout:late`. Power: the verb's default. */
    LateBy: { power: 5, wisdom: 15, contest: 15 } as Record<Kind, number>,
    /** After its spawn, the trip's decision stays ours until that rune's next spawn (power every 2 min, the next shrine at 14:00):
     *  OHA's rune mode does not send the hero there, whether the trip ran or was skipped. */
    OwnFor: { power: 120, wisdom: 420, contest: 0 } as Record<Kind, number>,
    /** Liquipedia/7.41: stand within 300 of the shrine for 3 s. */
    ShrineChannel: 3,
    ShrineRadius: 300,
    /** Ours.RuneSpawn plays (slice rune-spawn; all judgement). A gank chance after a support's 6:00 trip goes to the nearest
     *  visible enemy hero within GankReach; the gank must engage within GankEngageBy s and fights GankFightFor s. */
    GankReach: 4000,
    GankEngageBy: 20,
    GankFightFor: 8,
    /** The shrine contest's route keeps this far from enemy towers (attack range 700 plus OHA's retreat margin; judgement),
     *  with waypoints this much farther out, at most DetourMax of them. */
    TowerAvoid: 1000,
    DetourMargin: 200,
    DetourMax: 3,
    /** An enemy hero within FightNear of the spot at the spawn is a rune-fight chance. */
    FightNear: 700,
    /** The gank or fight stops with its target this near its own tower, or the support under this HP fraction. */
    StopTower: 700,
    StopHp: 0.3,
};

// The rune spawn's play kinds (slice rune-spawn, all judgement): the library holds no kind list (OWNERSHIP H24).
Plays.Define("gank", { base: 0.35, timeout: 30, chases: true });
// A low enemy within reach with numbers even is a sure fight (Plays.SureKill), not a roll.
Plays.Define("rune_fight", { base: 0.5, timeout: 15, chases: false, sure: Plays.SureKill(SETTINGS.FightNear) });
// The contest walks across the map and channels: its play lasts the trip.
Plays.Define("shrine", { base: 0.4, timeout: 60, chases: false });

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
    /** Ours.RuneSpawn's 6:00 trip: the planned spot's stand, and what the hero did at the spawn. */
    stand?: RunePlan.Stand;
    act?: string;
    race?: RunePlan.RaceInputs;
    hidden?: number;
    /** Waypoints before `at`: the contest's route around enemy towers. */
    via?: Vector[];
    /** Plays this trip started: the shrine contest's roll, the rune fight, the gank after the trip. */
    play?: Plays.Play;
    fight?: Plays.Play;
    gank?: Plays.Play;
}

/** A support with a stack open that minute is not free for the 6:00 plan (pos5's trip yields to its stack). */
export function Busy(this: void, u: Unit): boolean {
    return LaneConfig.PositionOf(u) === 5 && StackJob.Pending(u);
}

/** The 6:00 power trip runs as rune_spawn's plan (spot plan, stand, timed walk) rather than the plain trip. */
function planned(kind: Kind, spawn: number): boolean {
    return kind === "power" && spawn === RunePlan.SETTINGS.Spawn && RunePlan.On();
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
        if (kind === "contest" && !RunePlan.On()) continue;
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
    if (t.kind === "wisdom" || t.kind === "contest") {
        return {
            at: t.at as unknown as Lib.Vec,
            via: t.via as unknown as Lib.Vec[] | undefined,
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
    if (t.stand !== undefined) return RunePlan.LeaveAt(bot, t.stand.at, t.at);
    const u = bot as unknown as Lib.TaskUnit;
    const arrive = Tasks.Jobs()!.runeArriveBy(u, planFor(t));
    let walk = 0;
    let from = bot.GetLocation();
    for (const to of [...(t.via ?? []), t.at]) [walk, from] = [walk + FR.Dist(from, to), to];
    return arrive - (walk * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed());
}

/**
 * CANDIDATE(route): waypoints from `from` to `to` that keep each leg TowerAvoid from every tower in `towers`: a leg passing
 * closer gets a point beside the nearest such tower, on the side the leg passes (the other side when that is not
 * passable), at most DetourMax points. rspchk1: both fired shrine contests walked past the enemy's tower and OHA's retreat
 * took the hero (405 s, retreat 1.10 and 1.26). Exported for tests.
 */
export function Detour(from: Vector, to: Vector, towers: Vector[]): Vector[] {
    const s = SETTINGS;
    const via: Vector[] = [];
    let a = from;
    for (let n = 0; n < s.DetourMax; n++) {
        let worst: Vector | undefined;
        let worstD = s.TowerAvoid;
        let near = a;
        for (const tw of towers) {
            const c = closestOn(a, to, tw);
            const d = FR.Dist(c, tw);
            if (d < worstD) [worst, worstD, near] = [tw, d, c];
        }
        if (worst === undefined) break;
        let dx = near.x - worst.x;
        let dy = near.y - worst.y;
        let len = math.sqrt(dx * dx + dy * dy);
        if (len < 1) [dx, dy, len] = [-(to.y - a.y), to.x - a.x, math.max(1, FR.Dist(a, to))];
        const r = s.TowerAvoid + s.DetourMargin;
        let p = Vector(worst.x + (dx / len) * r, worst.y + (dy / len) * r, worst.z);
        if (!IsLocationPassable(p)) p = Vector(worst.x - (dx / len) * r, worst.y - (dy / len) * r, worst.z);
        via.push(p);
        a = p;
    }
    return via;
}

function closestOn(a: Vector, b: Vector, p: Vector): Vector {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const l2 = dx * dx + dy * dy;
    const k = l2 > 0 ? math.max(0, math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)) : 0;
    return Vector(a.x + k * dx, a.y + k * dy, a.z);
}

function tripFor(bot: Unit, kind: Kind, spawn: number, host: number, mine?: number): Trip {
    if (kind === "wisdom") return { kind, spawn, at: Rotate.ShrineFor(bot.GetTeam()), left: DotaTime(), host };
    if (kind === "contest") {
        const enemy = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
        const at = Rotate.ShrineFor(enemy);
        return { kind, spawn, at, via: Detour(bot.GetLocation(), at, FR.TowerSpots(enemy)), left: DotaTime(), host };
    }
    if (mine !== undefined) {
        const at = RunePlan.SpotAt(mine);
        return { kind, spawn, at, rune: mine, side: at.y > 0 ? "top" : "bot", left: DotaTime(), host, stand: RunePlan.StandFor(bot, at) };
    }
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
    // A play the trip started and its verb did not end (the task was preempted or cancelled) ends with the trip.
    for (const p of [t.play, t.fight, t.gank]) if (p !== undefined) Plays.End(p, `trip:${why}`, p === t.play && r.success ? "contested" : undefined);
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
        ["phase", t.act],
        ["ta", t.race !== undefined ? r1(t.race.ours) : undefined],
        ["te", t.race !== undefined && t.race.theirs < math.huge ? r1(t.race.theirs) : undefined],
        ["hid", t.hidden],
        ["sh", t.stand?.height],
        ["sph", t.stand?.spotHeight],
        ["play", (t.play ?? t.fight)?.id],
        ["gank", t.gank?.id],
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
    // Ends timed-out plays and writes settled play lines every frame, whether a trip runs or not.
    Plays.Tick();
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
            // Still dead at the spawn: the trip cannot arrive, so it ends here with its line, not silently at the window's end.
            if (DotaTime() >= spawn) return skip("dead");
            gateWhy[pid] = "dead";
            continue;
        }
        let mine: number | undefined;
        if (planned(kind, spawn)) {
            // Before the plan exists nobody starts; after it, only the planned support goes.
            if (DotaTime() < RunePlan.SETTINGS.PlanAt) continue;
            mine = RunePlan.SpotOf(bot, Busy);
            if (mine === undefined) return skip("plan-other");
        }
        const t = tripFor(bot, kind, spawn, host, mine);
        const leave = leaveAt(bot, t);
        if (DotaTime() < leave) return false;
        const why = blocked(bot) ?? (acting(bot) ? "acting" : undefined);
        // The leave time moves with the bot, so it can pass the slack in one frame: name what holds it now, if anything.
        if (DotaTime() > leave + SETTINGS.StartSlack) return skip(gateWhy[pid] ?? why ?? "late");
        if (why !== undefined) {
            gateWhy[pid] = why;
            return false;
        }
        if (kind === "contest") {
            // The contest is a play: a free pos5 rolls for it at its leave time; no fire, no trip.
            if (Busy(bot)) return skip("busy");
            const play = Plays.Roll({ kind: "shrine", by: bot, at: t.at });
            if (play === undefined) return skip("roll");
            t.play = play;
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
            if ((l === "wait" || l === "channel" || l === "decide") && t.arr === undefined) t.arr = DotaTime();
        },
        urgent: ctx.urgent,
    };
    if (t.stand !== undefined && t.rune !== undefined) {
        const r = yield* Tasks.Jobs()!.runeSpawnRun(bot as unknown as Lib.TaskUnit, spawnPlanFor(bot, t), hooks);
        if (t.fight !== undefined) yield* playFight(bot, t.fight, hooks);
        else if (LaneConfig.PositionOf(bot) !== 2 && bot.IsAlive()) {
            t.gank = offerGank(bot);
            if (t.gank !== undefined) yield* playFight(bot, t.gank, hooks);
        }
        return r;
    }
    return yield* Tasks.Jobs()!.runeRun(bot as unknown as Lib.TaskUnit, planFor(t), hooks);
}

function nearestEnemy(at: Vector, within: number): Unit | undefined {
    let best: Unit | undefined;
    let bestD = within;
    for (const e of FR.EnemiesNear(at, within)) {
        const d = FR.Dist(e.GetLocation(), at);
        if (d <= bestD) [best, bestD] = [e, d];
    }
    return best;
}

/** After a support's 6:00 trip: one gank chance on the nearest visible enemy hero within GankReach (none: no chance). */
function offerGank(bot: Unit): Plays.Play | undefined {
    const e = nearestEnemy(bot.GetLocation(), SETTINGS.GankReach);
    if (e === undefined) return undefined;
    return Plays.Roll({ kind: "gank", by: bot, target: e, at: e.GetLocation() });
}

/** A fired gank or rune fight: the gank verb on the play's target, straight in, ended by the verb or the play's stops. */
function* playFight(bot: Unit, play: Plays.Play, hooks: JobVerbs.JobHooks): Lib.TaskBody {
    const target = play.target!;
    const r = yield* Tasks.Jobs()!.gank(
        bot as unknown as Lib.TaskUnit,
        {
            target: () => (FR.Alive(target) ? (target as unknown as Lib.TaskAttacker) : undefined),
            path: [],
            deadline: DotaTime() + SETTINGS.GankEngageBy,
            engageFor: SETTINGS.GankFightFor,
            commit: () =>
                FR.HpFraction(bot) < SETTINGS.StopHp
                    ? "hp"
                    : FR.Alive(target) && FR.TowerDistance(target.GetTeam(), target.GetLocation()) < SETTINGS.StopTower
                      ? "tower"
                      : undefined,
        },
        hooks
    );
    Plays.End(play, r.success ? (r.message ?? "ok") : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`);
    return r;
}

/** The 6:00 spawn run's plan: the spot and stand from rune_plan, its race as the decision. */
export function spawnPlanFor(bot: Unit, t: Trip): JobVerbs.SpawnPlan {
    const other = RunePlan.Other(t.rune!);
    let hideFrom: number | undefined;
    return {
        rune: t.rune!,
        at: t.at as unknown as Lib.Vec,
        otherRune: other,
        otherAt: RunePlan.SpotAt(other) as unknown as Lib.Vec,
        stand: t.stand!.at as unknown as Lib.Vec,
        spawnAt: t.spawn,
        early: RunePlan.SETTINGS.Early,
        decide: () => {
            const [act, race] = RunePlan.Race(bot, t.rune!);
            t.race = race;
            // An enemy hero at the spot: one rune-fight roll (user 04/11/2026); a fired fight replaces the act.
            if (t.fight === undefined && act !== "none" && t.race !== undefined) {
                const e = nearestEnemy(t.at, SETTINGS.FightNear);
                if (e !== undefined) {
                    t.fight = Plays.Roll({ kind: "rune_fight", by: bot, target: e, at: t.at });
                    if (t.fight !== undefined) return "off";
                }
            }
            return act;
        },
        denyResult: () => RunePlan.DenyResult(t.rune!),
        phase: (name, act) => {
            if (name === "hide") hideFrom = DotaTime();
            if (name === "walk" && hideFrom !== undefined) t.hidden = math.floor((DotaTime() - hideFrom) * 10) / 10;
            if (name === "decide") t.act = act;
        },
    };
}

/** The rune mode's desire while the mid's trip runs: above laning's (up to about 0.95), below a retreat's. */
export const MID_DESIRE = 0.97;
const MID_HOST = BotMode.Rune;

/**
 * Ours.RuneSpawn, the mid's side of the 6:00 plan, every frame from the rune mode's GetDesire: true while its trip runs or
 * as it starts (the mode then returns MidDesire and steps it in Think). Not a chooser job: the mid has no other jobs, and
 * the rune mode is the mode Valve would give a rune walk.
 */
export function MidWants(bot: Unit): boolean {
    if (!RunePlan.On() || !bot.IsBot() || LaneConfig.PositionOf(bot) !== 2) return false;
    const pid = bot.GetPlayerID();
    Plays.Tick();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return true;
    if (Tasks.Jobs() === undefined) return false;
    const spawn = RunePlan.SETTINGS.Spawn;
    const now = DotaTime();
    handled[pid] = handled[pid] ?? {};
    const k = key("power", spawn);
    if (handled[pid][k] === true || now < RunePlan.SETTINGS.PlanAt || now >= spawn + SETTINGS.LateBy.power) return false;
    const mine = RunePlan.SpotOf(bot, Busy);
    if (mine === undefined) return false;
    const skip = (why: string) => {
        handled[pid][k] = true;
        log(bot, "power", spawn, [["res", "skip"], ["why", why]]);
        return false;
    };
    if (!bot.IsAlive()) return now >= spawn ? skip("dead") : false;
    const t = tripFor(bot, "power", spawn, MID_HOST, mine);
    const leave = leaveAt(bot, t);
    if (now < leave) return false;
    // A held start walks straight in when it goes (runeSpawnRun skips the stand once late); held past the slack it is skipped.
    if (acting(bot)) return now > leave + SETTINGS.StartSlack ? skip("acting") : false;
    const ok = Tasks.Start(bot, { name: "rune", host: MID_HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r, info) => finish(bot, t, r, info.label) }, (ctx: Lib.Ctx) =>
        body(bot, t, ctx)
    );
    if (!ok) return skip("refused");
    handled[pid][k] = true;
    running[pid] = t;
    jobLine(bot, t, "start", "plan");
    return true;
}

export function MidStep(bot: Unit): boolean {
    return LaneConfig.PositionOf(bot) === 2 && Step(bot, MID_HOST);
}

export function Step(bot: Unit, host: number): boolean {
    return running[bot.GetPlayerID()] !== undefined && Tasks.Step(bot, host);
}

export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] !== undefined;
}

/** The mode that steps this hero's running trip (the chooser's host, or the rune mode for the mid's 6:00 trip), if any. */
export function HostOf(bot: Unit): number | undefined {
    return running[bot.GetPlayerID()]?.host;
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

/** This hero's spawn of `kind` is the job's to decide now, taken or skipped: OHA's rune mode stands aside (review 03/11/2026:
 *  after a skip, OHA's wisdom branch walked the same pos4 to the shrine in 12 of 16 cases). */
export function Owns(bot: Unit, kind: Kind): boolean {
    if (!Applies(bot)) return false;
    const now = DotaTime();
    for (const [k, spawn] of SETTINGS.Trips[LaneConfig.PositionOf(bot) ?? 0] ?? []) {
        if (k === kind && now >= spawn - SETTINGS.ClaimFrom && now < spawn + SETTINGS.OwnFor[k]) return true;
    }
    return false;
}

/** OHA's own wisdom logic leaves the shrine to `bot`: its own spawn is the job's (taken or skipped), or a teammate's trip is on
 *  the shrine. Only the job's hero is held past a skip; the rest of the team stays OHA's (follow-up review 03/11/2026: a
 *  team-wide hold left the shrine untaken after a skip, 9 of 30 within 15 s against OFF's 14). */
export function ShrineHeld(bot: Unit): boolean {
    if (Owns(bot, "wisdom")) return true;
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m.GetTeam() !== bot.GetTeam()) continue;
        if (running[m.GetPlayerID()]?.kind === "wisdom") return true;
    }
    return false;
}
