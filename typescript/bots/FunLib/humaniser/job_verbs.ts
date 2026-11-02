/**
 * Job verbs: camp stack, pull (full, half, double), rune or shrine run, camp clear and gank, each one task body that
 * executes a plan the caller made. Bot code since slice 0b (moved out of the engine's `jobs`, unchanged): the engine
 * keeps the atomic verbs, `Skill` and the hit-timing facts these bodies are built from. The engine is reached through
 * the loaded bundle (`Bind`, from humaniser/tasks), never a static require, so a bundle that fails to load cannot
 * break the humaniser.
 */
import type * as Lib from "bots/FunLib/engine/tasks";

type Bundle = typeof Lib;
type Reason = Lib.Reason;
type Result = Lib.Result;
type TaskAttacker = Lib.TaskAttacker;
type TaskBody = Lib.TaskBody;
type TaskCreep = Lib.TaskCreep;
type TaskUnit = Lib.TaskUnit;
type Vec = Lib.Vec;

let engine: Bundle | undefined;
let host: Lib.Adapter | undefined;

/** The loaded bundle and the adapter it was initialised with: the clock and hold these bodies use. */
export function Bind(lib: Bundle, adapter: Lib.Adapter): void {
    engine = lib;
    host = adapter;
}

function E(): Bundle {
    return engine!;
}

// Default distances (units) and times (s) for camp jobs; every one can be overridden per plan.
const ARRIVE = 100;
const BOX_MARGIN = 300;
const NEUTRAL_SEARCH = 700;
const START_LATE = 2;
const NO_CAMP_AFTER = 1;
const AGGRO_CONFIRM = 2;
const APPROACH_LEAD = 3;
const AGGRO_LEAD_DEFAULT = 0.4;
const AGGRO_LEAD_MAX = 1.5;
/** A stand point the bot gets near but cannot reach (trees) counts as reached once it is this close and has not got
 *  STAND_STUCK_GAIN closer for STAND_STUCK_S: omniknight stopped ~300 short of evil_1's lane-side stand point and jiggled
 *  until `late` (s4solo5, 15 of 20 Dire attempts). */
const STAND_STUCK_R = 400;
const STAND_STUCK_S = 1.5;
const STAND_STUCK_GAIN = 25;
const LEAD_MAX_AFTER_AGGRO = 15;
const WATCH_SEC = 8;
/** Seconds early to arrive at a rune (players aim for 3-5 s). */
const RUNE_EARLY = 4;
/** Fraction of `early` kept at skill 0 (1 at skill 1): low-skill bots cut rune timings finer. */
const RUNE_EARLY_LOW = 0.25;
const RUNE_LATE_BY = 5;
/** After the spawn, seconds to keep retrying a rune not yet reported available. */
const RUNE_GRACE = 2;
const RUNE_PICKUP_FOR = 10;
const SHRINE_RADIUS = 300;

function ok(): Result {
    return { success: true, reason: "ok" };
}

function fail(reason: Reason, message?: string): Result {
    return { success: false, reason, message };
}

function now(): number {
    return host!.now();
}

function dist(a: Vec, b: Vec): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
}

function hold(bot: TaskUnit, tag: string): void {
    if (host!.hold !== undefined) host!.hold(bot, tag);
}

/** Task controls a job reports its phases through (pass the task's `ctx.label` and `ctx.urgent`). */
export interface JobHooks {
    label?: (this: void, label: string) => void;
    urgent?: (this: void, on: boolean) => void;
}

export interface Box {
    min: Vec;
    max: Vec;
}

/** One neutral camp as the host knows it (e.g. a `GetNeutralSpawners()` box plus the host's camp data). */
export interface Camp {
    /** Where the bot waits to hit the camp. */
    stand: Vec;
    /** Spawn box; neutrals within it (plus `margin`) are the camp. */
    box?: Box;
    /** Spawner origin, walked towards when nothing is seen from the stand point. */
    origin?: Vec;
    /**
     * A closer stand point, taken `approachLead` s before the aggro when nothing
     * is in sight from `stand` (trees, night vision), so the camp is seen in time to hit it on its second.
     */
    approach?: Vec;
    /** Box margin: idle neutrals stand just outside the box. Default 300. */
    margin?: number;
    /** `GetNearbyNeutralCreeps` radius. Default 700. */
    search?: number;
    /** Host override of the neutral to hit. */
    pick?: (this: void) => TaskAttacker | undefined;
    /** Extra proof the aggro landed (e.g. a neutral targets the bot), passed to `attackAndConfirm`. */
    confirmed?: (this: void) => boolean;
    /** Seconds to pull the hit forward, read every frame until the order (e.g. stacks already in the box block each other).
     *  CANDIDATE(earlier): one consumer, the double stack. */
    earlier?: (this: void) => number;
}

export interface AggroInfo {
    camp: Camp;
    /** The plan's aggro second (when the hit should land). */
    planned: number;
    /** Skill error applied to it (s, positive late). */
    error: number;
    orderedAt: number;
    confirmedAt: number;
    /** The neutral the order went to (hosts time a ranged hit's flight from it). */
    target?: TaskAttacker;
}

export interface AggroOpts {
    /** Stand-point tolerance. Default 100. */
    arrive?: number;
    /** Seconds after the (erred) aggro second the bot may still reach the stand point. Default 2. */
    startLate?: number;
    /** Seconds after it to keep looking for a neutral. Default 1. */
    noCampAfter?: number;
    /** Seconds from the order to see the hit land. Default 2. */
    confirmFor?: number;
    /** Each neutral the hit order goes to, as it is picked (hosts log whether the hit landed). */
    onTarget?: (this: void, n: TaskAttacker) => void;
    /** Seconds added to every aggro second of the job; default one `Skill.timingError(bot)` draw per job. */
    timingError?: number;
    /** Seconds before the hit the order goes out; default estimated per target (`aggroLead`). */
    aggroLead?: number;
    /** Seconds before the aggro the bot moves to `camp.approach` when it sees nothing. Default 3. */
    approachLead?: number;
    /** While it waits, the bot keeps this far from the camp's nearest visible neutral, stepping back along the line from
     *  it, then walks in on the hit's lead: an idle bot in auto-attack reach hits the camp seconds early and stands
     *  under fire (user replay review of dsolo4b, 31/10/2026). Default off. */
    waitClear?: number;
    onAggro?: (this: void, info: AggroInfo) => void;
}

function inBox(b: Box, p: Vec, m: number): boolean {
    return p.x >= b.min.x - m && p.x <= b.max.x + m && p.y >= b.min.y - m && p.y <= b.max.y + m;
}

/**
 * The camp's neutral nearest the bot: alive, visible, inside the box grown by `margin` (or, without a box,
 * within `margin` of the origin, else anything in `search`).
 */
/** The point `clear` from neutral `n` on the line from it through the bot, or undefined when the bot is already that far
 *  (within 25). CANDIDATE(waitClear): one consumer, the double stack. */
function clearPoint(bot: TaskUnit, n: TaskAttacker, clear: number): Vec | undefined {
    const p = n.GetLocation();
    const b = bot.GetLocation();
    const d = dist(p, b);
    if (d >= clear - 25) return undefined;
    const k = clear / math.max(1, d);
    return Vector(p.x + (b.x - p.x) * k, p.y + (b.y - p.y) * k, b.z ?? 0) as unknown as Vec;
}

export function campNeutral(bot: TaskUnit, camp: Camp): TaskAttacker | undefined {
    if (camp.pick !== undefined) return camp.pick();
    if (bot.GetNearbyNeutralCreeps === undefined) return undefined;
    const m = camp.margin ?? BOX_MARGIN;
    const here = bot.GetLocation();
    let best: TaskAttacker | undefined;
    let bestD = math.huge;
    for (const n of bot.GetNearbyNeutralCreeps(camp.search ?? NEUTRAL_SEARCH) ?? []) {
        if ((n.IsNull?.() ?? false) || !n.IsAlive() || !(n.CanBeSeen?.() ?? true)) continue;
        const p = n.GetLocation();
        if (camp.box !== undefined ? !inBox(camp.box, p, m) : camp.origin !== undefined && dist(p, camp.origin) > m) continue;
        const d = dist(here, p);
        if (d < bestD) {
            best = n;
            bestD = d;
        }
    }
    return best;
}

/** Seconds from an attack order on `target` to the hit landing: walk into range, wind-up, projectile flight. */
export function aggroLead(bot: TaskUnit, target: TaskAttacker): number {
    if (bot.GetAttackPoint === undefined) return AGGRO_LEAD_DEFAULT;
    const d = dist(bot.GetLocation(), target.GetLocation());
    const walk = math.max(0, d - bot.GetAttackRange()) / math.max(1, bot.GetCurrentMovementSpeed?.() ?? 300);
    const hit = E().Verbs.ownHitTime(bot, target as TaskCreep);
    return math.max(0, math.min(AGGRO_LEAD_MAX, walk + hit));
}

/**
 * Travels to the camp's stand point and hits the camp so the hit lands at `at` (already including the error):
 * the order goes `aggroLead` early, from wherever the bot is once a neutral is in sight. Ends `ok` when the hit is
 * confirmed. Failure messages: `late`, `mistake:no-camp`, `mistake:no-aggro`.
 */
function* aggroCamp(bot: TaskUnit, camp: Camp, planned: number, err: number, o: AggroOpts, h: JobHooks): TaskBody {
    let at = planned + err;
    const arrive = o.arrive ?? ARRIVE;
    const late = at + (o.startLate ?? START_LATE);
    let stand = camp.stand;
    let approached = camp.approach === undefined;
    let best = math.huge;
    let bestAt = now();
    // Only on the way in: a bot that stood on the point and was pushed off walks back (job verb test "stack pushed").
    let arrived = false;
    const there = () => {
        const d = dist(bot.GetLocation(), stand);
        if (d <= arrive) {
            arrived = true;
            return true;
        }
        if (arrived) return false;
        if (d < best - STAND_STUCK_GAIN) {
            best = d;
            bestAt = now();
        }
        return d <= STAND_STUCK_R && now() - bestAt >= STAND_STUCK_S;
    };
    let reached = false;
    let waiting = false;
    // Set once the wait stepped back from a neutral it could see: the lead the hit then needs from the new point.
    let clearLead: number | undefined;
    h.label?.("travel");
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        const t = now();
        const n = campNeutral(bot, camp);
        if (camp.earlier !== undefined) at = planned + err - camp.earlier();
        if (there()) reached = true;
        if (n !== undefined && t >= at - (o.aggroLead ?? aggroLead(bot, n))) break;
        if (n === undefined && clearLead !== undefined && there() && t >= at - clearLead) break;
        if (n === undefined && !approached && there() && t >= at - (o.approachLead ?? APPROACH_LEAD)) {
            approached = true;
            stand = camp.approach!;
            waiting = false;
            best = math.huge;
            bestAt = t;
            arrived = false;
        }
        if (t >= at && there()) break;
        if (!there()) {
            if (t >= late) return fail("timeout", "late");
            bot.Action_MoveToLocation(stand);
        } else {
            if (!waiting) h.label?.("wait");
            waiting = true;
            const back = o.waitClear !== undefined && n !== undefined ? clearPoint(bot, n, o.waitClear) : undefined;
            if (back !== undefined) {
                stand = back;
                approached = true;
                arrived = false;
                best = math.huge;
                bestAt = t;
                // aggroLead as if the neutral stood where it is now and the bot at the new point.
                const speed = math.max(1, bot.GetCurrentMovementSpeed?.() ?? 300);
                const hit = bot.GetAttackPoint === undefined ? AGGRO_LEAD_DEFAULT : E().Verbs.ownHitTime(bot, n as TaskCreep);
                clearLead = math.min(AGGRO_LEAD_MAX, math.max(0, o.waitClear! - bot.GetAttackRange()) / speed + hit);
                bot.Action_MoveToLocation(stand);
            } else {
                hold(bot, "job_wait");
            }
        }
        yield;
    }

    h.label?.("aggro");
    let orderedAt: number | undefined;
    let target: TaskAttacker | undefined;
    const pick = () => {
        const n = campNeutral(bot, camp);
        if (n !== undefined && orderedAt === undefined) orderedAt = now();
        if (n !== undefined) {
            target = n;
            o.onTarget?.(n);
        }
        return n;
    };
    const hit = yield* E().Verbs.attackAndConfirm(bot, pick, {
        findFor: math.max(0, at + (o.noCampAfter ?? NO_CAMP_AFTER) - now()),
        confirmFor: o.confirmFor ?? AGGRO_CONFIRM,
        searchAt: camp.origin ?? camp.stand,
        hold: "job_aggro",
        confirmed: camp.confirmed,
    });
    if (hit.reason === "no_target") return reached || there() ? fail("no_target", "mistake:no-camp") : fail("timeout", "late");
    if (!hit.success) return fail(hit.reason, "mistake:no-aggro");
    o.onAggro?.({ camp, planned, error: err, orderedAt: orderedAt ?? now(), confirmedAt: now(), target });
    return ok();
}

export interface StackPlan extends AggroOpts {
    camp: Camp;
    /** When the hit should land (the camp's stack second, without jitter: the verb adds the skill error). */
    aggroAt: number;
    /** Walked after the hit, out of the box. */
    exitPath: Vec[];
    /** Absolute time the walk-off ends (just after the next :00 spawn check). */
    exitUntil: number;
    /** Double stack: this camp is hit first at its own second, then `camp`, whose walk-off both camps follow. */
    first?: { camp: Camp; aggroAt: number };
}

/**
 * Camp stack: travel, wait at the stand point, a confirmed hit landing on
 * the aggro second (+ skill error), walk off along `exitPath`, stay out until `exitUntil`. Labels `travel`, `wait`,
 * `aggro` (twice for a double), `exit`; urgent until the last hit lands.
 */
export function* stack(bot: TaskUnit, p: StackPlan, h: JobHooks = {}): TaskBody {
    const err = p.timingError ?? E().Skill.timingError(bot);
    h.urgent?.(true);
    if (p.first !== undefined) {
        const f = yield* aggroCamp(bot, p.first.camp, p.first.aggroAt, err, p, h);
        if (!f.success) return f;
    }
    const r = yield* aggroCamp(bot, p.camp, p.aggroAt, err, p, h);
    if (!r.success) return r;
    h.urgent?.(false);
    h.label?.("exit");
    const arrive = p.arrive ?? ARRIVE;
    yield* E().Verbs.walkPath(bot, p.exitPath, { tolerance: arrive, timeout: math.huge, stuckSecs: math.huge, deadline: p.exitUntil });
    const held = yield* E().Verbs.waitUntil(bot, p.exitUntil, { hold: "stack_exit" });
    return held.success ? ok() : held;
}

export interface PullPlan extends AggroOpts {
    /** The camp whose hit is graded (a double's small camp). */
    camp: Camp;
    /** When its hit should land (the camp's full or half pull second, e.g. :15/:45 or :17/:47). */
    aggroAt: number;
    /** Walked after the hit, to the meet point with the wave (last point). */
    lead: Vec[];
    /** Double pull: this camp is hit first at its own second, then `camp`. */
    first?: { camp: Camp; aggroAt: number };
    /** Watch at the meet point at least this long. Default 8. */
    watchSec?: number;
    /** And until this time (e.g. a little after the wave arrives). */
    watchUntil?: number;
    /** Absolute time the lead must be done by. Default aggroAt + 15. */
    leadDeadline?: number;
}

/**
 * Pull (full, half, double: the kind is in the data). Aggro the camp so the hit lands on its second (+ one skill
 * error for the whole job), lead it along `lead` to the meet point, then watch there. Labels `travel`, `wait`,
 * `aggro` (twice for a double), `lead`, `watch`; urgent until the lead is done. Grading the divert is the host's.
 */
export function* pull(bot: TaskUnit, p: PullPlan, h: JobHooks = {}): TaskBody {
    const err = p.timingError ?? E().Skill.timingError(bot);
    h.urgent?.(true);
    if (p.first !== undefined) {
        const r = yield* aggroCamp(bot, p.first.camp, p.first.aggroAt, err, p, h);
        if (!r.success) return r;
    }
    const r = yield* aggroCamp(bot, p.camp, p.aggroAt, err, p, h);
    if (!r.success) return r;

    h.label?.("lead");
    const arrive = p.arrive ?? ARRIVE;
    if (p.lead.length > 0) {
        const led = yield* E().Verbs.walkPath(bot, p.lead, {
            tolerance: arrive,
            timeout: math.huge,
            stuckSecs: 3,
            deadline: p.leadDeadline ?? p.aggroAt + err + LEAD_MAX_AFTER_AGGRO,
        });
        if (!led.success) return fail(led.reason, "lead");
    }
    h.urgent?.(false);

    h.label?.("watch");
    const spot = p.lead.length > 0 ? p.lead[p.lead.length - 1] : bot.GetLocation();
    const until = math.max(now() + (p.watchSec ?? WATCH_SEC), p.watchUntil ?? 0);
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        if (now() >= until) return ok();
        if (dist(bot.GetLocation(), spot) > arrive) bot.Action_MoveToLocation(spot);
        else hold(bot, "job_watch");
        yield;
    }
}

export interface RunePlan {
    /** Where to wait for the spawn (the rune spot, or beside it). */
    at: Vec;
    /** Game time the rune spawns or the shrine activates. */
    spawnAt: number;
    /** Rune location constant; picked up with `pickUpRune`. Omit for a shrine (`channel`). */
    rune?: number;
    /** Rune position override for `pickUpRune`. */
    runeAt?: Vec;
    /** Seconds early to arrive at skill 1. Default 4. */
    early?: number;
    /** Arrival tolerance at `at`. Default 150. */
    tolerance?: number;
    /** Not at `at` by spawnAt + lateBy: fails `timeout` "late". Default 5. */
    lateBy?: number;
    /** Seconds after the spawn to get the rune or finish the channel. Default 10. */
    pickupFor?: number;
    /** Shrine: stand within `radius` of `at` this many seconds after it activates (wisdom shrine: 3). */
    channel?: number;
    /** Shrine radius. Default 300. */
    radius?: number;
    /** Host proof of the gain (gold, modifier, XP). Rune: decides ok vs taken_by_other; shrine: ok vs missed. */
    confirmed?: (this: void) => boolean;
    /** Seconds added to the arrival; default one `Skill.timingError(bot)` draw per bot and spawn. */
    timingError?: number;
}

const arrivalErrors: { [key: string]: number } = {};

/** When the bot means to be at `at`: `early * lerp(0.25, 1, skill)` s before the spawn, plus its timing error. */
export function runeArriveBy(bot: TaskUnit, p: RunePlan): number {
    let err = p.timingError;
    if (err === undefined) {
        const key = `${bot.GetPlayerID()}:${p.spawnAt}`;
        err = arrivalErrors[key] ?? E().Skill.timingError(bot);
        arrivalErrors[key] = err;
    }
    return p.spawnAt - (p.early ?? RUNE_EARLY) * E().Skill.lerp(RUNE_EARLY_LOW, 1, E().Skill.of(bot)) + err;
}

/** When to start `runeRun` to arrive by `runeArriveBy`, from the straight-line walk at the current speed. */
export function runeLeaveAt(bot: TaskUnit, p: RunePlan): number {
    const speed = math.max(1, bot.GetCurrentMovementSpeed?.() ?? 300);
    return runeArriveBy(bot, p) - dist(bot.GetLocation(), p.at) / speed;
}

/**
 * Rune or shrine run: walk to `at`, wait for the spawn, then one reaction delay later pick the rune up (retrying
 * while it is not yet reported, for 2 s) or, for a shrine, stand within `radius` for `channel` s (pushed out, the
 * count restarts). Start it at `runeLeaveAt` to arrive skill-scaled early. Labels `travel`, `wait`, then `pickup`
 * or `channel`.
 */
export function* runeRun(bot: TaskUnit, p: RunePlan, h: JobHooks = {}): TaskBody {
    const tolerance = p.tolerance ?? 150;
    h.label?.("travel");
    const walked = yield* E().Verbs.walkTo(bot, p.at, {
        tolerance,
        timeout: math.huge,
        stuckSecs: math.huge,
        deadline: p.spawnAt + (p.lateBy ?? RUNE_LATE_BY),
    });
    if (!walked.success) return walked.reason === "timeout" ? fail("timeout", "late") : walked;

    h.label?.("wait");
    const go = math.max(p.spawnAt, now()) + E().Skill.react(bot);
    while (now() < go) {
        if (!bot.IsAlive()) return fail("dead");
        if (dist(bot.GetLocation(), p.at) > tolerance) bot.Action_MoveToLocation(p.at);
        else hold(bot, "rune_wait");
        yield;
    }
    const giveUp = p.spawnAt + (p.pickupFor ?? RUNE_PICKUP_FOR);

    if (p.channel !== undefined) {
        h.label?.("channel");
        const radius = p.radius ?? SHRINE_RADIUS;
        let from: number | undefined;
        while (true) {
            if (!bot.IsAlive()) return fail("dead");
            const t = now();
            if (p.confirmed?.() === true) return ok();
            if (dist(bot.GetLocation(), p.at) <= radius) {
                from ??= t;
                if (t - from >= p.channel) return p.confirmed === undefined ? ok() : fail("missed");
                hold(bot, "rune_channel");
            } else {
                from = undefined;
                bot.Action_MoveToLocation(p.at);
            }
            if (t >= giveUp) return fail("timeout");
            yield;
        }
    }

    if (p.rune === undefined) return fail("no_target", "no rune");
    h.label?.("pickup");
    const graceUntil = go + RUNE_GRACE;
    while (true) {
        const r = yield* E().Verbs.pickUpRune(bot, p.rune, {
            at: p.runeAt,
            deadline: giveUp,
            timeout: math.max(0, giveUp - now()),
            confirmed: p.confirmed,
        });
        if (r.reason !== "no_target" || now() >= graceUntil) return r;
        yield;
    }
}

export interface ClearPlan {
    /** The camp's centre (its box centre); neutrals within `radius` of it are the camp. */
    at: Vec;
    /** Neutrals chase out of the box: this far from `at` they still count. Default 700. */
    radius?: number;
    /** Within this of `at` the bot is at the camp. Default 300. */
    arrive?: number;
    /** `GetNearbyNeutralCreeps` radius. Default 1600. */
    search?: number;
    /** Absolute time the camp must be left by: past it the verb fails `timeout` "late". */
    deadline?: number;
    /** Seconds at the camp seeing nothing before it counts as empty. Default 0.5. */
    emptyAfter?: number;
    /** Seconds between repeated attack orders on the same target (a dropped order is re-given). Default 1. */
    reorder?: number;
    /** Host override of the next target among the camp's neutrals (default: keep the current one, else lowest HP). */
    pick?: (this: void, neutrals: TaskAttacker[]) => TaskAttacker | undefined;
    /** Called once, the first frame a neutral is within attack range + 100 (hosts time the clear from here). */
    onEngage?: (this: void, t: number) => void;
}

const CLEAR_RADIUS = 700;
const CLEAR_ARRIVE = 300;
const CLEAR_SEARCH = 1600;
const CLEAR_EMPTY_AFTER = 0.5;
const CLEAR_REORDER = 1;
const ENGAGE_SLACK = 100;
/** Seconds a fought neutral may be out of sight before it no longer holds the camp open. */
const CLEAR_LOST = 2;

function campOf(bot: TaskUnit, p: ClearPlan): TaskAttacker[] {
    const out: TaskAttacker[] = [];
    if (bot.GetNearbyNeutralCreeps === undefined) return out;
    const r = p.radius ?? CLEAR_RADIUS;
    for (const n of bot.GetNearbyNeutralCreeps(p.search ?? CLEAR_SEARCH) ?? []) {
        if ((n.IsNull?.() ?? false) || !n.IsAlive() || !(n.CanBeSeen?.() ?? true)) continue;
        if (dist(n.GetLocation(), p.at) <= r) out.push(n);
    }
    return out;
}

function hpOf(n: TaskAttacker): number {
    const c = n as Partial<TaskCreep>;
    return c.GetHealth !== undefined ? c.GetHealth() : 0;
}

function lowestHp(list: TaskAttacker[]): TaskAttacker | undefined {
    let best: TaskAttacker | undefined;
    for (const n of list) if (best === undefined || hpOf(n) < hpOf(best)) best = n;
    return best;
}

/**
 * Clears a neutral camp: walks to `at`, attacks its neutrals (the current target is kept while it lives, else the
 * lowest HP one), one order per target (re-given every `reorder` s), and after each kill waits one reaction delay
 * (`Skill.react`, skill-scaled) before the next order. Ends ok with message "cleared" once a camp it fought is
 * empty, or "empty" when nothing was there; `timeout` "late" past `deadline`. Labels `go`, then `farm` from the first frame a neutral is in attack range (+100).
 */
export function* clearCamp(bot: TaskUnit, p: ClearPlan, h: JobHooks = {}): TaskBody {
    const arrive = p.arrive ?? CLEAR_ARRIVE;
    let fought = false;
    let engaged = false;
    let target: TaskAttacker | undefined;
    let orderedAt = -math.huge;
    let nextOrderAt = -math.huge;
    let emptySince: number | undefined;
    let seen: { n: TaskAttacker; at: number }[] = [];
    h.label?.("go");
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        const t = now();
        if (p.deadline !== undefined && t >= p.deadline) return fail("timeout", "late");
        const camp = campOf(bot, p);
        // Neutrals already fought stay the camp's while alive and seen recently, wherever they chase the bot: a camp
        // is not "cleared" while its neutrals stand 750 from the box.
        const kept: { n: TaskAttacker; at: number }[] = [];
        for (const e of seen) {
            const alive = !(e.n.IsNull?.() ?? false) && e.n.IsAlive();
            if (!alive) continue;
            const inCamp = camp.indexOf(e.n) >= 0;
            const visibleNow = inCamp || (e.n.CanBeSeen?.() ?? true);
            const at = visibleNow ? t : e.at;
            if (t - at > CLEAR_LOST) continue;
            if (!inCamp && visibleNow) camp.push(e.n);
            kept.push({ n: e.n, at });
        }
        for (const n of camp) if (!kept.some((e) => e.n === n)) kept.push({ n, at: t });
        seen = kept;
        if (target !== undefined && camp.indexOf(target) < 0) {
            // Killed (or lost): a human takes a moment to pick the next one.
            target = undefined;
            nextOrderAt = t + E().Skill.react(bot);
        }
        if (camp.length === 0) {
            if (dist(bot.GetLocation(), p.at) > arrive) {
                emptySince = undefined;
                bot.Action_MoveToLocation(p.at);
            } else {
                emptySince ??= t;
                if (fought || t - emptySince >= (p.emptyAfter ?? CLEAR_EMPTY_AFTER)) {
                    return { success: true, reason: "ok", message: fought ? "cleared" : "empty" };
                }
                hold(bot, "camp_look");
            }
            yield;
            continue;
        }
        emptySince = undefined;
        fought = true;
        if (t < nextOrderAt) {
            hold(bot, "camp_react");
            yield;
            continue;
        }
        const next = target ?? (p.pick !== undefined ? p.pick(camp) : undefined) ?? lowestHp(camp)!;
        if (next !== target || t - orderedAt >= (p.reorder ?? CLEAR_REORDER)) {
            bot.Action_AttackUnit(next, false);
            orderedAt = t;
        }
        target = next;
        if (!engaged && dist(bot.GetLocation(), next.GetLocation()) <= bot.GetAttackRange() + ENGAGE_SLACK) {
            engaged = true;
            h.label?.("farm");
            p.onEngage?.(t);
        }
        yield;
    }
}

export interface GankPlan {
    /** The hero to kill, re-read every frame (the host's perception decides what the bot knows). */
    target: (this: void) => TaskAttacker | undefined;
    /** Approach waypoints chosen by the host (through fog and trees, not down the lane); then the chase starts. */
    path: Vec[];
    /** Within this of the target the bot engages (attacks). Default 700. */
    engageRange?: number;
    /** Called once when the ETA to the target falls to `lead` s (humans ping "coming" ~3-5 s before arriving). */
    telegraph?: { lead: number; fn: (this: void, eta: number) => void };
    /** Host check every frame; a returned string ends the gank `interrupted` with it (target under its tower, ...). */
    commit?: (this: void) => string | undefined;
    /** Seconds the target may be out of sight before it counts as escaped. Default 2. */
    lostGrace?: number;
    /** Seconds of fighting after engaging before giving up. Default 8. */
    engageFor?: number;
    /** Absolute time to have engaged by; fails `timeout` "late". */
    deadline?: number;
    /** Seconds between repeated attack orders. Default 1. */
    reorder?: number;
    onEngage?: (this: void, t: number) => void;
}

const GANK_ENGAGE = 700;
const GANK_LOST_GRACE = 2;
const GANK_ENGAGE_FOR = 8;
const GANK_REORDER = 1;

function visible(t: TaskAttacker | undefined): t is TaskAttacker {
    return t !== undefined && !(t.IsNull?.() ?? false) && t.IsAlive() && (t.CanBeSeen?.() ?? true);
}

function pathLeft(from: Vec, path: Vec[], i: number, end: Vec): number {
    let d = 0;
    let at = from;
    for (let k = i; k < path.length; k++) {
        d += dist(at, path[k]);
        at = path[k];
    }
    return d + dist(at, end);
}

/**
 * A gank: walk the host's approach path, then chase the target into `engageRange` and attack it (one reaction delay
 * after reaching range, `Skill.react`), re-ordering every `reorder` s. Ends ok "kill" when the target dies; fails
 * `interrupted` "escaped" when it stays out of sight `lostGrace` s, `timeout` "no-kill" after `engageFor` s of
 * fighting, `timeout` "late" if not engaged by `deadline`, or with the host's `commit` message. Labels `travel`,
 * `engage`; urgent while engaged.
 */
export function* gank(bot: TaskUnit, p: GankPlan, h: JobHooks = {}): TaskBody {
    const range = p.engageRange ?? GANK_ENGAGE;
    const speed = () => math.max(1, bot.GetCurrentMovementSpeed?.() ?? 300);
    let wp = 0;
    let lastSeen: Vec | undefined;
    let lostAt: number | undefined;
    let telegraphed = p.telegraph === undefined;
    let engagedAt: number | undefined;
    let attackAt: number | undefined;
    let orderedAt = -math.huge;
    h.label?.("travel");
    while (true) {
        if (!bot.IsAlive()) return fail("dead");
        const t = now();
        const why = p.commit?.();
        if (why !== undefined) return fail("interrupted", why);
        const target = p.target();
        if (target !== undefined && !(target.IsNull?.() ?? false) && !target.IsAlive()) return { success: true, reason: "ok", message: "kill" };
        if (visible(target)) {
            lastSeen = target.GetLocation();
            lostAt = undefined;
        } else {
            lostAt ??= t;
            if (t - lostAt >= (p.lostGrace ?? GANK_LOST_GRACE)) return fail("interrupted", "escaped");
        }
        if (engagedAt === undefined && p.deadline !== undefined && t >= p.deadline) return fail("timeout", "late");
        if (engagedAt !== undefined && t - engagedAt >= (p.engageFor ?? GANK_ENGAGE_FOR)) return fail("timeout", "no-kill");
        const here = bot.GetLocation();
        while (wp < p.path.length && dist(here, p.path[wp]) <= ARRIVE) wp++;
        const goal = lastSeen ?? here;
        if (!telegraphed && lastSeen !== undefined) {
            const eta = pathLeft(here, p.path, wp, goal) / speed();
            if (eta <= p.telegraph!.lead) {
                telegraphed = true;
                p.telegraph!.fn(eta);
            }
        }
        if (wp < p.path.length) {
            bot.Action_MoveToLocation(p.path[wp]);
        } else if (engagedAt === undefined && (!visible(target) || dist(here, goal) > range)) {
            bot.Action_MoveToLocation(goal);
        } else if (visible(target)) {
            if (engagedAt === undefined) {
                engagedAt = t;
                attackAt = t + E().Skill.react(bot);
                h.label?.("engage");
                h.urgent?.(true);
                p.onEngage?.(t);
            }
            if (t >= attackAt! && t - orderedAt >= (p.reorder ?? GANK_REORDER)) {
                bot.Action_AttackUnit(target, false);
                orderedAt = t;
            }
        } else {
            bot.Action_MoveToLocation(goal);
        }
        yield;
    }
}
