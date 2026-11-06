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

type Kind = "power" | "wisdom" | "contest";

// All judgement (slice file, Decisions).
export const SETTINGS = {
    /** Spawns each position goes for. Power at 6:00, the shrine at 7:00 (transitions/runes RUNE_RULES). */
    Trips: { [4]: [["power", 360], ["wisdom", 420]], [5]: [["power", 360], ["contest", 420]] } as Record<number, [Kind, number][]>,
    /** Rank against the hero's other jobs (the stack job is 0.92): pos4's trip holds its 5:5x stack back, pos5's yields. */
    Priority: { [4]: 0.95, [5]: 0.85 } as Record<number, number>,
    /** The trip claims the hero this long before the spawn, so a lower job does not start in its way. */
    ClaimFrom: 60,
    /** The calendar's estimate of a trip's end: this long after the spawn (banked trips are away about 14 s, `away`), then
     *  the walk back (slice lane-control 3; `judgement`). */
    CalendarBack: 10,
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
    /** The shrine contest takes Valve's path when it keeps this far from every enemy tower (attack range 700 plus OHA's
     *  retreat margin; judgement), or keeps farther than the edge route; otherwise the edge route. */
    TowerAvoid: 1000,
    /** The edge route to each team's shrine, before the shrine: points of Valve's own path along the map edge from the far
     *  safe lane (probe genpath7, 05/11/2026; walkable, 1,108-1,912 from the towers). */
    Edge: {
        [Team.Dire]: [[8281, -3787], [8538, -3017], [8538, -2632]],
        [Team.Radiant]: [[-7255, 2632], [-7897, 1990]],
    } as Record<number, [number, number][]>,
    /** Valve's GeneratePath waypoints come about 128 apart; legs are merged up to this length (judgement). */
    RouteStep: 600,
    /** A cached path is asked again once the hero has moved this far from where it was asked, or after RouteFresh s. */
    RouteMoved: 400,
    RouteFresh: 10,
    /** At its leave time a contest waits at most this long for Valve's path, then walks the edge route (answers took
     *  0.03-0.3 s in probe v8, but one can never come or always be dropped: review 2026-11-05 F1). */
    RouteWait: 1.5,
    /** An answer is the hero's own only when its first waypoint is this near where it was asked and its last this near the
     *  goal (judgement: Valve's waypoints are about 128 apart; the shrine itself is not walkable). */
    RouteEnds: 300,
    /** An enemy hero within FightNear of the spot at the spawn is a rune-fight chance. */
    FightNear: 700,
    /** The gank or fight stops with its target this near its own tower, or the support under this HP fraction. */
    /** Added to the tower's reach: the gank stops with its target this near its own tower. -144 is the tower's radius, so the distance is its attack range, 700 (judgement; was 700). */
    StopHp: 0.3,
    /** The mid's trip does not start under this HP fraction (the chooser's MinHpFraction for supports' jobs; rspchk2 game 1
     *  started one at 2% HP). */
    MidMinHp: 0.5,
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
    /** Where `via` came from: Valve's path, or the edge route when the path passes nearer a tower or has not answered. */
    route?: "path" | "edge";
    /** The route's least distance from an enemy tower. */
    clear?: number;
    /** Valve's answer behind a `path` route: seconds since it was asked, and its distance from the start. */
    pathAge?: [number, number];
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

/**
 * This bot's rune trips still ahead or running at `now`, for its calendar (slice lane-control 3): claimed from ClaimFrom
 * before the spawn, leaving at the spawn less the walk to the nearer power spot (PathFactor on the straight line; the shrine
 * trips are planned later and sit about as far, so the same estimate), back CalendarBack after the spawn plus the same walk.
 * Fixed: a rune trip is never traded for lane control (design s5.5 rule 1).
 */
export function CalendarEntries(bot: Unit, now: number): { kind: "rune"; key: number; claim: number; leave: number; back: number; fixed: boolean; running?: boolean }[] {
    if (!Applies(bot)) return [];
    const pid = bot.GetPlayerID();
    const out: { kind: "rune"; key: number; claim: number; leave: number; back: number; fixed: boolean; running?: boolean }[] = [];
    let walk = math.huge;
    for (const [, at] of powerRunes()) walk = math.min(walk, (GetUnitToLocationDistance(bot, at) * SETTINGS.PathFactor) / math.max(1, bot.GetCurrentMovementSpeed()));
    const r = running[pid];
    for (const [kind, spawn] of SETTINGS.Trips[LaneConfig.PositionOf(bot) ?? 0] ?? []) {
        if (kind === "contest" && !RunePlan.On()) continue;
        const back = spawn + SETTINGS.CalendarBack + walk;
        if (r !== undefined && r.kind === kind && r.spawn === spawn) {
            out.push({ kind: "rune", key: spawn, claim: spawn - SETTINGS.ClaimFrom, leave: r.left, back, fixed: true, running: true });
            continue;
        }
        if (handled[pid]?.[key(kind, spawn)] === true || now >= spawn + SETTINGS.LateBy[kind]) continue;
        const leave = Tasks.Jobs() !== undefined ? calendarLeave(bot, kind, spawn, now) : spawn - walk;
        if (leave === false) continue;
        out.push({ kind: "rune", key: spawn, claim: spawn - SETTINGS.ClaimFrom, leave: leave ?? spawn - walk, back, fixed: true });
    }
    return out;
}

/**
 * The trip's own leave time (`leaveAt`, as `Wants` reads it), for the calendar (review H1, lctl4_C_on_3 t=362 pid 0 and
 * lctl4_B_on_5 pid 2: the walk to a power spot put the 7:00 contest's leave 20 s late, so a pull fitted before it and the
 * contest was lost). The contest's route is the edge route (the longer one, so never a later leave; the trip asks Valve's
 * path only when it starts). A planned power rune: the plan's spot once the plan exists, `false` when the plan gave this
 * bot none; undefined before the plan (the caller's walk estimate).
 */
function calendarLeave(bot: Unit, kind: Kind, spawn: number, now: number): number | false | undefined {
    if (kind === "contest") {
        const enemy = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
        return leaveAt(bot, { kind, spawn, at: Rotate.ShrineFor(enemy), via: edgeVia(enemy), left: now, host: 0 });
    }
    if (planned(kind, spawn)) {
        if (now < RunePlan.SETTINGS.PlanAt) return undefined;
        const mine = RunePlan.SpotOf(bot, Busy, now);
        if (mine === undefined) return false;
        return leaveAt(bot, tripFor(bot, kind, spawn, 0, mine));
    }
    return leaveAt(bot, tripFor(bot, kind, spawn, 0));
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

/** The edge route's waypoints to `team`'s shrine. */
function edgeVia(team: number): Vector[] {
    return (SETTINGS.Edge[team] ?? []).map(([x, y]) => Vector(x, y, 256));
}

declare function GeneratePath(this: void, from: Vector, to: Vector, avoid: unknown[], done: (this: void, ...args: unknown[]) => void): void;

type Path = { from: Vector; asked: number; to: Vector; via?: Vector[] };
const paths: Record<number, Path> = {};
/** Answers PathVia threw away since the hero's last contest line, as `vbad`. */
const rejected: Record<number, number> = {};
/** When a contest started waiting for Valve's path at its leave time: [spawn, DotaTime]. */
const pathWait: Record<number, [number, number]> = {};

/**
 * CANDIDATE(route): Valve's walking path from the hero to `to`, as waypoints before `to`, legs merged up to RouteStep; undefined
 * until an answer asked within RouteMoved of where the hero is now and at most RouteFresh s ago arrives (an older answer
 * starts from somewhere else: its first leg is a straight line that can cross the lane by a tower). A request that has not
 * answered in a second is sent again. The callback's arguments are (distance, request id, waypoints), not the (distance,
 * waypoints) of Valve's docs, and it runs on a later frame (probe genpath5, 04/11/2026: 10 of 24 requests in one frame
 * called back). Avoidance zones changed no path (genpath5 to genpath7); from the contest's starts in rspchk4 at 6:30,
 * Valve's path is the shortest walk, which passes enemy towers: drill2 (05/11/2026) logged 10 contest paths from lane
 * starts keeping 519-596 from the safe-lane tier-1, inside OHA retreat's 898 (`X.ShouldRun`). An answer that does not run
 * from where it was asked to `to` is dropped (`vbad`; probe v8: 1 of 70 same-frame answers was another hero's).
 */
export function PathVia(bot: Unit, to: Vector): Vector[] | undefined {
    if (typeof GeneratePath === "undefined") return undefined;
    const pid = bot.GetPlayerID();
    const here = bot.GetLocation();
    const c = paths[pid];
    const fits = c !== undefined && FR.Dist(c.to, to) <= 1 && FR.Dist(c.from, here) <= SETTINGS.RouteMoved && DotaTime() - c.asked <= SETTINGS.RouteFresh;
    if (!fits || (c.via === undefined && DotaTime() - c.asked > 1)) {
        const entry: Path = { from: here, asked: DotaTime(), to };
        paths[pid] = entry;
        GeneratePath(here, to, [], (...args: unknown[]) => {
            for (const a of args) {
                if (type(a) !== "table") continue;
                const wp = a as Vector[];
                if (wp.length > 0 && FR.Dist(wp[0], entry.from) <= SETTINGS.RouteEnds && FR.Dist(wp[wp.length - 1], to) <= SETTINGS.RouteEnds) entry.via = Thin(wp, to);
                else rejected[pid] = (rejected[pid] ?? 0) + 1;
            }
        });
        return entry.via;
    }
    return c.via;
}

/** The hero's path request is out and has not answered yet, within a second of asking. */
export function PathPending(bot: Unit): boolean {
    const c = paths[bot.GetPlayerID()];
    return c !== undefined && c.via === undefined && DotaTime() - c.asked <= 1;
}

/** The answer behind PathVia's last route: its age and how far from the hero it was asked. */
function pathAge(bot: Unit): [number, number] | undefined {
    const c = paths[bot.GetPlayerID()];
    return c?.via !== undefined ? [DotaTime() - c.asked, FR.Dist(c.from, bot.GetLocation())] : undefined;
}

function takeRejected(bot: Unit): number {
    const n = rejected[bot.GetPlayerID()] ?? 0;
    rejected[bot.GetPlayerID()] = 0;
    return n;
}

/** Valve's waypoints (the first is the start) with a point kept only where skipping it would make a leg longer than RouteStep. */
export function Thin(wp: Vector[], to: Vector): Vector[] {
    const out: Vector[] = [];
    let last = wp[0];
    for (let i = 1; i < wp.length; i++) {
        if (FR.Dist(last, wp[i + 1] ?? to) > SETTINGS.RouteStep) {
            out.push(wp[i]);
            last = wp[i];
        }
    }
    return out;
}

/** The least distance from any tower to the walk from `from` through `legs`. */
export function Clearance(from: Vector, legs: Vector[], towers: Vector[]): number {
    let min = math.huge;
    let a = from;
    for (const b of legs) {
        for (const tw of towers) min = math.min(min, FR.Dist(closestOn(a, b, tw), tw));
        a = b;
    }
    return min;
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
        const towers = FR.TowerSpots(enemy);
        const here = bot.GetLocation();
        const path = PathVia(bot, at);
        const edge = edgeVia(enemy);
        const pathClear = path !== undefined ? Clearance(here, [...path, at], towers) : -1;
        const edgeClear = Clearance(here, [...edge, at], towers);
        const usePath = path !== undefined && (pathClear >= SETTINGS.TowerAvoid || pathClear >= edgeClear);
        return {
            kind,
            spawn,
            at,
            via: usePath ? path : edge,
            route: usePath ? "path" : "edge",
            clear: usePath ? pathClear : edgeClear,
            pathAge: path !== undefined ? pathAge(bot) : undefined,
            left: DotaTime(),
            host,
        };
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
        ["via", t.via !== undefined ? t.via.length : undefined],
        ["route", t.route],
        ["vclr", t.clear !== undefined ? math.floor(t.clear) : undefined],
        ["vage", t.pathAge !== undefined ? r1(t.pathAge[0]) : undefined],
        ["voff", t.pathAge !== undefined ? math.floor(t.pathAge[1]) : undefined],
        ["vbad", t.kind === "contest" ? takeRejected(bot) : undefined],
        ["vpts", t.via !== undefined && t.route !== undefined ? t.via.map((q) => `${math.floor(q.x)},${math.floor(q.y)}`).join(";") : undefined],
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
        let mine: number | undefined;
        const skip = (why: string) => {
            handled[pid][key(kind, spawn)] = true;
            gateWhy[pid] = undefined;
            log(bot, kind, spawn, [["res", "skip"], ["why", why]]);
            if (mine !== undefined && DotaTime() < spawn) dropFromPlan(bot, why);
            return false;
        };
        if (!bot.IsAlive()) {
            // Still dead at the spawn: the trip cannot arrive, so it ends here with its line, not silently at the window's end.
            if (DotaTime() >= spawn) return skip("dead");
            gateWhy[pid] = "dead";
            continue;
        }
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
        if (DotaTime() > leave + SETTINGS.StartSlack && !canStillArrive(bot, t)) return skip(gateWhy[pid] ?? why ?? "late");
        if (why !== undefined) {
            gateWhy[pid] = why;
            return false;
        }
        if (kind === "contest") {
            // The contest is a play: a free pos5 rolls for it at its leave time; no fire, no trip.
            if (Busy(bot)) return skip("busy");
            // The start waits a frame or so for Valve's path, which may be clear and shorter than the edge route.
            if (t.route === "edge" && PathPending(bot)) {
                if (pathWait[pid]?.[0] !== spawn) pathWait[pid] = [spawn, DotaTime()];
                if (DotaTime() - pathWait[pid][1] <= SETTINGS.RouteWait) return false;
            }
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

/** The plan's spot goes from a support that will not go to the other free one, whose own trip opens again. */
function dropFromPlan(bot: Unit, why: string): void {
    const next = RunePlan.Drop(bot, why, Busy);
    if (next === undefined) return;
    const pid = next.GetPlayerID();
    handled[pid] = handled[pid] ?? {};
    handled[pid][key("power", RunePlan.SETTINGS.Spawn)] = false;
}

/** A replacement support starts past its leave time while a straight walk still reaches the spot by the spawn (the verb
 *  skips the stand once late). */
function canStillArrive(bot: Unit, t: Trip): boolean {
    return t.stand !== undefined && RunePlan.Replaces(bot) && DotaTime() + RunePlan.WalkSecs(bot, t.at) * SETTINGS.PathFactor <= t.spawn;
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
                    : FR.Alive(target) && FR.TowerDistance(target.GetTeam(), target.GetLocation()) < LaneConfig.TowerAttackRange()
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

/**
 * The rune mode's desire while the mid's trip runs: above laning's (up to about 0.95). Only OHA retreat's 1.0 and 1.1 returns
 * beat it; its HIGH and VERYHIGH returns (0.8, 0.9) lose once the trip runs (it starts only at MidMinHp or more).
 */
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
    const why = bot.GetHealth() < bot.GetMaxHealth() * SETTINGS.MidMinHp ? "low-hp" : acting(bot) ? "acting" : undefined;
    if (why !== undefined) return now > leave + SETTINGS.StartSlack ? skip(why) : false;
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
