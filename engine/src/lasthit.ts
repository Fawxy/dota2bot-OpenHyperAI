import { get } from "./adapter";
import * as Skill from "./skill";
import { Reason, Result, TaskAttacker, TaskBody, TaskCreep, TaskHero, TaskUnit, Vec } from "./types";

declare const DAMAGE_TYPE_PHYSICAL: number | undefined;

const ACTIVITY_ATTACK = 1503;
/** Heroes (and some units) alternate their attack animation with ATTACK2. */
const ACTIVITY_ATTACK2 = 1504;
/** Above this attack range a unit attacks with a projectile. */
const RANGED_ABOVE = 320;
/** Projectiles start this far in front of a ranged hero / creep. */
const HERO_LAUNCH_OFFSET = 39;
const CREEP_LAUNCH_OFFSET = 22;
/** Larger than any search radius we use; callers filter by distance so one query serves them all. */
const QUERY_RADIUS = 1600;
/** Skill above which, of several creeps killable now, the ranged/siege one is taken. */
const RANGED_PRIORITY_SKILL = 0.6;
/** Extra seconds a lapse delays the swing, on top of the normal timing error. */
const LAPSE_MIN = 0.15;
const LAPSE_MAX = 0.4;
/**
 * Seconds a hit must land before ours to be relied on (one frame at 30 fps); grows with the observed frame
 * time, since bots think less often per game second at high timescales.
 */
const MIN_MARGIN = 0.034;
const MAX_MARGIN = 0.3;
/** Seconds ahead over which attacks are visible as wind-ups (a creep's attack point is 0.467 s). */
const SEEN_AHEAD = 0.45;
/** An attack order may be given this long before the cooldown ends: Dota queues it and the swing starts on time. */
const COOLDOWN_QUEUE = 0.25;
/** Seconds after the predicted hit time before an unresolved swing counts as `missed`. */
const CONFIRM_SLACK = 0.5;

function ok(): Result {
    return { success: true, reason: "ok" };
}

function fail(reason: Reason): Result {
    return { success: false, reason };
}

function now(): number {
    return get()!.now();
}

function expired(deadline: number | undefined): boolean {
    return deadline !== undefined && now() >= deadline;
}

function dist(a: Vec, b: Vec): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
}

/**
 * Dead, released, or out of our sight: a handle of a unit in the fog stays valid and alive but reads no location,
 * so `dist` on it would error.
 */
function gone(u: TaskAttacker): boolean {
    return (u.IsNull?.() ?? false) || !u.IsAlive() || u.GetLocation() === undefined;
}

// Per-frame query cache, per bot: every lastHit/deny of a bot in one frame shares one set of queries.
interface Nearby {
    t: number;
    enemyCreeps: TaskCreep[];
    allyCreeps: TaskCreep[];
    others?: TaskAttacker[];
    /** Attackers by their current target, built once per frame (one GetAttackTarget per unit). */
    byTarget?: LuaTable<TaskAttacker, TaskAttacker[]>;
}
const nearbyCache: { [playerID: number]: Nearby } = {};

function nearby(bot: TaskUnit): Nearby {
    const id = bot.GetPlayerID();
    const t = now();
    const hit = nearbyCache[id];
    if (hit !== undefined && hit.t === t) return hit;
    const n: Nearby = {
        t,
        enemyCreeps: bot.GetNearbyLaneCreeps?.(QUERY_RADIUS, true) ?? [],
        allyCreeps: bot.GetNearbyLaneCreeps?.(QUERY_RADIUS, false) ?? [],
    };
    nearbyCache[id] = n;
    return n;
}

/** Heroes and towers of both teams; only queried once a swing decision is due. */
function others(bot: TaskUnit, n: Nearby): TaskAttacker[] {
    if (n.others !== undefined) return n.others;
    const out: TaskAttacker[] = [];
    for (const enemies of [true, false]) {
        for (const h of bot.GetNearbyHeroes?.(QUERY_RADIUS, enemies, 0) ?? []) {
            if (h.GetLocation !== undefined && h.IsAlive !== undefined) out.push(h as TaskHero as TaskAttacker);
        }
        for (const t of bot.GetNearbyTowers?.(QUERY_RADIUS, enemies) ?? []) out.push(t);
    }
    n.others = out;
    return out;
}

function physical(creep: TaskCreep, raw: number): number {
    if (creep.GetActualIncomingDamage === undefined) return raw;
    return creep.GetActualIncomingDamage(raw, DAMAGE_TYPE_PHYSICAL ?? 1);
}

function isRanged(u: TaskAttacker): boolean {
    return (u.GetAttackRange?.() ?? 0) > RANGED_ABOVE && (u.GetAttackProjectileSpeed?.() ?? 0) > 0;
}

/**
 * Raw damage of `a`'s current attack on `creep` if it lands within `horizon` seconds, else 0. UNVERIFIED
 * in-game: reads the wind-up left as (attackPoint - animCycle) * secondsPerAttack, which treats
 * the attack point as a fraction of the attack cycle.
 */
function windupDamage(a: TaskAttacker, creep: TaskCreep, horizon: number): number {
    if (a.GetAnimActivity === undefined) return 0;
    const act = a.GetAnimActivity();
    if (act !== ACTIVITY_ATTACK && act !== ACTIVITY_ATTACK2) return 0;
    if (a.GetAnimCycle === undefined || a.GetAttackPoint === undefined) return 0;
    const cycle = a.GetAnimCycle();
    const point = a.GetAttackPoint();
    if (cycle >= point) return 0;
    let t = (point - cycle) * (a.GetSecondsPerAttack?.() ?? 1);
    if (isRanged(a)) {
        t += math.max(0, dist(a.GetLocation(), creep.GetLocation()) - CREEP_LAUNCH_OFFSET) / a.GetAttackProjectileSpeed!();
    }
    return t <= horizon ? (a.GetAttackDamage?.() ?? 0) : 0;
}

/**
 * Damage (after armour) the creep takes from others within `horizon` seconds: attack projectiles in flight
 * plus every attacker of either team winding up an attack on it. Attacks not yet started are not counted;
 * the prediction runs every frame, so they enter it once their wind-up begins.
 */
export function incomingDamage(bot: TaskUnit, creep: TaskCreep, horizon: number): number {
    return physical(creep, scanAttackers(bot, creep, horizon).raw);
}

/** Damage per second (after armour) of every visible attacker of either team currently targeting the creep. */
export function incomingDps(bot: TaskUnit, creep: TaskCreep): number {
    return physical(creep, scanAttackers(bot, creep, 0).dps);
}

function attackersByTarget(bot: TaskUnit, n: Nearby): LuaTable<TaskAttacker, TaskAttacker[]> {
    if (n.byTarget !== undefined) return n.byTarget;
    const by = new LuaTable<TaskAttacker, TaskAttacker[]>();
    const myTeam = bot.GetTeam?.();
    const add = (a: TaskAttacker): void => {
        if (a === (bot as unknown) || gone(a)) return;
        // CanBeSeen is "visible to the enemy team": it says nothing about our own units, so only enemies are
        // dropped by it (a fogged enemy's attack target cannot be read).
        if (myTeam !== undefined && a.GetTeam?.() !== myTeam && !(a.CanBeSeen?.() ?? true)) return;
        if (myTeam === undefined && !(a.CanBeSeen?.() ?? true)) return;
        const target = a.GetAttackTarget?.();
        if (target === undefined || target === null) return;
        let list = by.get(target as TaskAttacker);
        if (list === undefined) {
            list = [];
            by.set(target as TaskAttacker, list);
        }
        list.push(a);
    };
    for (const c of n.enemyCreeps) add(c);
    for (const c of n.allyCreeps) add(c);
    for (const o of others(bot, n)) add(o);
    n.byTarget = by;
    return by;
}

function scanAttackers(bot: TaskUnit, creep: TaskCreep, horizon: number): { raw: number; dps: number } {
    let raw = 0;
    let dps = 0;
    for (const p of creep.GetIncomingTrackingProjectiles?.() ?? []) {
        const c = p.caster;
        if (p.is_attack === true && c !== undefined && c !== null && c !== (bot as unknown) && !(c.IsNull?.() ?? false)) {
            const speed = c.GetAttackProjectileSpeed?.() ?? 0;
            if (speed > 0 && dist(p.location, creep.GetLocation()) / speed <= horizon) raw += c.GetAttackDamage?.() ?? 0;
        }
    }
    for (const a of attackersByTarget(bot, nearby(bot)).get(creep as TaskAttacker) ?? []) {
        if (a === (creep as TaskAttacker)) continue;
        raw += windupDamage(a, creep, horizon);
        dps += (a.GetAttackDamage?.() ?? 0) / (a.GetSecondsPerAttack?.() ?? 1);
    }
    return { raw, dps };
}

/**
 * Seconds from an attack order now until the bot's hit lands: wind-up (attack point / attack speed), the
 * cooldown left from its last attack (only with the adapter's `attackClock`), and projectile travel for a
 * ranged bot. The bot is assumed facing the creep: turn time is not modelled.
 */
/** Seconds until the bot can start its next swing (0 without the adapter's `attackClock`). */
export function cooldownLeft(bot: TaskUnit): number {
    const a = get()!;
    if (a.attackClock === undefined || bot.GetSecondsPerAttack === undefined || bot.GetLastAttackTime === undefined) return 0;
    const windup = bot.GetAttackPoint!() / (bot.GetAttackSpeed?.() ?? 1);
    const idle = bot.GetSecondsPerAttack() - windup;
    // A hit landing this frame can read a hair after the clock; one reading clearly ahead of it is ignored.
    const since = a.attackClock() - bot.GetLastAttackTime() + 0.01;
    if (since < -0.1) return 0;
    return math.max(0, since) < idle ? idle - math.max(0, since) : 0;
}

// LuaJIT (Dota) has math.atan2; Lua 5.3 (fengari, tests) folds it into math.atan.
const atan2: (this: void, y: number, x: number) => number = (math as any).atan2 ?? (math as any).atan;

/** Hero turn rate (radians per 0.03 s; heroes 0.5-0.9) and the angle an attack can start within. */
const TURN_RATE = 0.6;
const TURN_SLACK = 0.2;

/** Seconds to turn to face the creep (0 without GetFacing). */
export function turnTime(bot: TaskUnit, creep: TaskCreep): number {
    const facing = bot.GetFacing?.();
    if (facing === undefined || facing === null) return 0;
    const a = bot.GetLocation();
    const b = creep.GetLocation();
    const want = atan2(b.y - a.y, b.x - a.x);
    let d = math.abs(want - (facing * Math.PI) / 180) % (2 * Math.PI);
    if (d > Math.PI) d = 2 * Math.PI - d;
    return (0.03 * math.max(0, d - TURN_SLACK)) / TURN_RATE;
}

export function ownHitTime(bot: TaskUnit, creep: TaskCreep): number {
    let t = bot.GetAttackPoint!() / (bot.GetAttackSpeed?.() ?? 1) + cooldownLeft(bot) + turnTime(bot, creep);
    const speed = bot.GetAttackProjectileSpeed?.() ?? 0;
    const range = bot.GetAttackRange();
    if (range > RANGED_ABOVE && speed > 0) {
        const d = dist(bot.GetLocation(), creep.GetLocation()) - HERO_LAUNCH_OFFSET;
        t += math.min(math.max(0, d), range) / speed;
    }
    return t;
}

/** Per bot and creep, the error rolled once and kept until the creep is gone, so retries do not re-roll it. */
interface Roll {
    /** In [-1, 1]; scales own damage by 1 + eps * width. Positive: swings early. */
    eps: number;
    /** Seconds added to the prediction horizon. Positive: swings early; negative (and lapses): late. */
    shift: number;
}
const rolls: { [playerID: number]: LuaTable<TaskCreep, Roll> } = {};

function rollFor(bot: TaskUnit, creep: TaskCreep): Roll {
    const id = bot.GetPlayerID();
    let byCreep = rolls[id];
    if (byCreep === undefined) {
        byCreep = setmetatable(new LuaTable<TaskCreep, Roll>(), { __mode: "k" });
        rolls[id] = byCreep;
    }
    let r = byCreep.get(creep);
    if (r === undefined) {
        const width = Skill.lastHitError(bot);
        let shift = (2 * Skill.random() - 1) * width * Skill.TIMING_PER_ERROR;
        if (Skill.random() < Skill.lapseChance(bot)) shift -= Skill.lerp(LAPSE_MIN, LAPSE_MAX, Skill.random());
        r = { eps: 2 * Skill.random() - 1, shift };
        byCreep.set(creep, r);
    }
    return r;
}

interface Belief {
    /** Seconds until our hit would land if ordered now. */
    tHit: number;
    /** True when nothing visible kills the creep before our hit lands (exact, no error). */
    survives: boolean;
    /** HP the bot believes the creep will have when its hit lands, before its own damage. */
    hpAtHit: number;
    /** Own damage as the bot believes it (error applied, after armour). */
    mine: number;
}

/**
 * What the bot believes about a swing ordered now. A negative timing shift shortens the horizon (late swing);
 * a positive one extends it with the attackers' DPS, i.e. counts hits that have not started yet (early swing):
 * the visible prediction alone cannot over-anticipate, so without that extrapolation early errors vanish.
 */
function believe(bot: TaskUnit, creep: TaskCreep, withError: boolean, margin: number = MIN_MARGIN): Belief {
    const tHit = ownHitTime(bot, creep);
    const regen = creep.GetHealthRegen?.() ?? 0;
    const hp = creep.GetHealth();
    // Only hits landing at least `margin` before ours are relied on: one landing in the same frame as ours may
    // be applied after it, and the creep survives our swing.
    // Beyond SEEN_AHEAD, hits that land before ours have not started their wind-up yet: extrapolate the current
    // attackers' DPS over that part of the horizon (without it, ranged swings with 0.6-1 s horizons come late).
    const relied = math.max(0, tHit - margin);
    const dps = incomingDps(bot, creep);
    const certain = hp + regen * tHit - incomingDamage(bot, creep, relied);
    const visible = certain - math.max(0, relied - SEEN_AHEAD) * dps;
    let believed = visible;
    let width = 0;
    let eps = 0;
    if (withError) {
        const r = rollFor(bot, creep);
        width = Skill.lastHitError(bot);
        eps = r.eps;
        if (r.shift < 0) {
            const h = math.max(0, tHit - margin + r.shift);
            believed = hp + regen * h - incomingDamage(bot, creep, h) - math.max(0, h - SEEN_AHEAD) * dps;
        } else if (r.shift > 0) {
            believed = visible + regen * r.shift - dps * r.shift;
        }
    }
    return {
        tHit,
        // Survival is judged on seen hits only; the extrapolated ones may never come.
        survives: certain > 0,
        hpAtHit: believed,
        // The lowest roll of the damage spread: a swing on the average roll fails about half the borderline creeps.
        mine: physical(creep, (bot.GetAttackDamage!() - (bot.GetBaseDamageVariance?.() ?? 0)) * (1 + eps * width)),
    };
}

/** Swing now: the creep survives everyone else until our hit lands, and (as believed) our hit then kills it. */
function due(b: Belief): boolean {
    return b.survives && b.hpAtHit <= b.mine;
}

function isRangedCreep(c: TaskCreep): boolean {
    const name = c.GetUnitName?.();
    if (name === undefined) return false;
    return string.find(name, "ranged", 1, true)[0] !== undefined || string.find(name, "siege", 1, true)[0] !== undefined;
}

function deniable(c: TaskCreep): boolean {
    const max = c.GetMaxHealth?.();
    return max === undefined || c.GetHealth() < max / 2;
}

/**
 * Of `creeps`, the one closest to dying to our hit (exact prediction, no error), preferring a ranged or siege
 * creep already killable when the bot's skill is above RANGED_PRIORITY_SKILL.
 */
function choose(bot: TaskUnit, creeps: TaskCreep[]): TaskCreep | undefined {
    let best: TaskCreep | undefined;
    let bestMargin = Infinity;
    let ranged: TaskCreep | undefined;
    const preferRanged = Skill.of(bot) > RANGED_PRIORITY_SKILL;
    for (const c of creeps) {
        const b = believe(bot, c, false);
        const margin = b.hpAtHit - b.mine;
        if (margin < bestMargin) {
            bestMargin = margin;
            best = c;
        }
        if (preferRanged && ranged === undefined && b.survives && margin <= 0 && isRangedCreep(c)) ranged = c;
    }
    return ranged ?? best;
}

/**
 * Deny heuristic, UNVERIFIED in-game: assumes an enemy hero attacking the creep on its last live frame
 * landed the killing blow, and that Dota hands back the same handle for the same unit so `==` matches.
 */
function enemyTargeting(bot: TaskUnit, creep: TaskCreep): boolean {
    const heroes = bot.GetNearbyHeroes?.(1200, true, 0);
    if (heroes === undefined) return false;
    for (const h of heroes) {
        if (h.GetAttackTarget?.() === creep) return true;
    }
    return false;
}

export interface LaneTarget {
    creep: TaskCreep;
    kind: "lasthit" | "deny";
    /** Seconds until a swing ordered then would be due (0: due now), or the walk into attack range if longer. */
    eta: number;
    /** Seconds of walking into attack range at the bot's current speed (0: already in range). */
    walk: number;
    /** A ranged or siege creep (more gold and XP than a melee one). */
    ranged: boolean;
}

export interface LaneTargetsOpts {
    /** Creeps farther than this are ignored. Default max(800, attack range + 400). */
    radius?: number;
    /**
     * Only creeps that become killable at most this many seconds after the bot could be in range are returned,
     * so a melee hero standing outside the creep rings sets off in time. Default 1.
     */
    within?: number;
    /** Consider allied creeps to deny. Default true. */
    deny?: boolean;
    /** Consider enemy creeps to last-hit. Default true. */
    lastHit?: boolean;
}

/** Seconds until the creep is killable by a swing ordered then, and the walk into attack range. */
function etaOf(bot: TaskUnit, c: TaskCreep, walkSpeed: number): [number, number] | undefined {
    const b = believe(bot, c, false);
    if (!b.survives) return undefined;
    const walk = math.max(0, dist(bot.GetLocation(), c.GetLocation()) - bot.GetAttackRange()) / walkSpeed;
    const margin = b.hpAtHit - b.mine;
    if (margin <= 0) return [0, walk];
    const dps = incomingDps(bot, c) + math.max(0, -(c.GetHealthRegen?.() ?? 0));
    if (dps <= 0) return undefined;
    return [margin / dps, walk];
}

/**
 * The lane creeps that become killable within `within` seconds of the bot reaching attack range, in no order:
 * enemy creeps to last-hit (the adapter's `lastHitFilter` applies) and allied creeps to deny. Facts only, with
 * exact prediction and no skill error (the verbs apply that when they swing): eta is when the creep becomes
 * killable by a swing ordered then (from incoming DPS), or the walk into range if longer. Which one to go for is
 * the caller's choice.
 */
export function laneTargets(bot: TaskUnit, opts: LaneTargetsOpts = {}): LaneTarget[] {
    const out: LaneTarget[] = [];
    if (bot.GetAttackDamage === undefined || bot.GetAttackPoint === undefined || bot.GetNearbyLaneCreeps === undefined) {
        return out;
    }
    const adapter = get()!;
    const radius = opts.radius ?? math.max(800, bot.GetAttackRange() + 400);
    const within = opts.within ?? 1;
    const speed = math.max(100, bot.GetCurrentMovementSpeed?.() ?? 300);
    const here = bot.GetLocation();
    const n = nearby(bot);
    const consider = (c: TaskCreep, kind: "lasthit" | "deny"): void => {
        if (gone(c) || dist(here, c.GetLocation()) > radius) return;
        if (kind === "lasthit" && adapter.lastHitFilter !== undefined && !adapter.lastHitFilter(bot, c)) return;
        const e = etaOf(bot, c, speed);
        if (e === undefined || e[0] - e[1] > within) return;
        out.push({ creep: c, kind, eta: math.max(e[0], e[1]), walk: e[1], ranged: isRangedCreep(c) });
    };
    if (opts.lastHit !== false) for (const c of n.enemyCreeps) consider(c, "lasthit");
    if (opts.deny !== false && bot.GetDenies !== undefined) for (const c of n.allyCreeps) consider(c, "deny");
    return out;
}

export interface LastHitOpts {
    /** Seconds to wait for the creep to become due before failing `timeout`. Default 1.5. */
    maxWait?: number;
    deadline?: number;
    target?: TaskCreep;
    /** Default attack range + 300. */
    searchRadius?: number;
    /** Hold tag passed to the adapter's `hold` while standing in range waiting. */
    hold?: string;
    interruptIf?: (this: void) => boolean;
}

type Mode = "lasthit" | "deny";

function* strike(bot: TaskUnit, mode: Mode, opts: LastHitOpts): TaskBody {
    const adapter = get()!;
    if (bot.GetAttackDamage === undefined || bot.GetAttackPoint === undefined) return fail("unsupported");
    if (mode === "deny" && bot.GetDenies === undefined) return fail("unsupported");
    const start = now();
    const maxWait = opts.maxWait ?? 1.5;

    let creep = opts.target;
    if (creep === undefined) {
        if (bot.GetNearbyLaneCreeps === undefined) return fail("unsupported");
        const radius = opts.searchRadius ?? bot.GetAttackRange() + 300;
        const here = bot.GetLocation();
        const n = nearby(bot);
        let candidates = 0;
        const allowed: TaskCreep[] = [];
        for (const c of mode === "deny" ? n.allyCreeps : n.enemyCreeps) {
            if (!gone(c) && dist(here, c.GetLocation()) <= radius) {
                candidates++;
                if (mode === "deny" || adapter.lastHitFilter === undefined || adapter.lastHitFilter(bot, c)) {
                    allowed.push(c);
                }
            }
        }
        creep = choose(bot, allowed);
        if (creep === undefined) return fail(candidates > 0 ? "etiquette" : "no_target");
    } else if (mode === "lasthit" && adapter.lastHitFilter !== undefined && !adapter.lastHitFilter(bot, creep)) {
        return fail("etiquette");
    }

    const counter = (): number => (mode === "deny" ? bot.GetDenies!() : bot.GetLastHits());
    const lostReason = (enemyOnIt: boolean): Reason => (mode === "lasthit" && enemyOnIt ? "denied" : "taken_by_other");
    const baseline = counter();
    let enemyOnIt = false;
    let tHit = 0;
    let diag = "";
    let lastFrame: number | undefined;
    let margin = MIN_MARGIN;
    while (true) {
        const t = now();
        if (lastFrame !== undefined && t > lastFrame) margin = math.min(MAX_MARGIN, math.max(MIN_MARGIN, 1.2 * (t - lastFrame)));
        lastFrame = t;
        if (!bot.IsAlive()) return fail("dead");
        if (gone(creep)) return fail(lostReason(enemyOnIt));
        if (opts.interruptIf !== undefined && opts.interruptIf()) return fail("interrupted");
        if (now() - start > maxWait || expired(opts.deadline)) return fail("timeout");
        if (mode === "lasthit") enemyOnIt = enemyTargeting(bot, creep);
        if (dist(bot.GetLocation(), creep.GetLocation()) > bot.GetAttackRange()) {
            bot.Action_MoveToLocation(creep.GetLocation());
        } else {
            // An order given during the attack cooldown starts the swing later than the prediction's horizon
            // covers (hits not yet wound up are unseen), so the decision waits until the swing can start.
            if ((mode === "lasthit" || deniable(creep)) && cooldownLeft(bot) <= math.max(margin, COOLDOWN_QUEUE)) {
                const b = believe(bot, creep, true, margin);
                if (due(b)) {
                    tHit = b.tHit;
                    // In-game calibration (docs/API.md "UNVERIFIED"): what the swing was based on.
                    diag = string.format("hp=%d pred=%d mine=%d t=%.2f m=%.2f", math.floor(creep.GetHealth()), math.floor(b.hpAtHit), math.floor(b.mine), b.tHit, margin);
                    bot.Action_AttackUnit(creep, true);
                    break;
                }
            }
            if (opts.hold !== undefined && adapter.hold !== undefined) adapter.hold(bot, opts.hold);
        }
        yield;
    }

    const swingAt = now();
    // GetLastAttackTime rises when the attack fires (a ranged hero's projectile leaves), not when it lands, so the
    // outcome is judged against the predicted landing time instead: a creep lost before it was taken by someone
    // else; one alive (or killed by someone else) after it was missed.
    const landBy = (): boolean => now() - swingAt >= tHit;
    const out = (r: Result): Result => {
        const hp = gone(creep) ? 0 : math.floor(creep.GetHealth());
        r.message = string.format("%s end=%d dt=%.2f", diag, hp, now() - swingAt);
        return r;
    };
    while (true) {
        yield;
        if (counter() > baseline) return out(ok());
        if (gone(creep)) return out(fail(landBy() ? "missed" : lostReason(enemyOnIt)));
        if (!bot.IsAlive()) return fail("dead");
        if (now() - swingAt > tHit + CONFIRM_SLACK) return out(fail("missed"));
        if (mode === "lasthit") enemyOnIt = enemyTargeting(bot, creep);
    }
}

/**
 * Last-hits an enemy lane creep (`opts.target`, or the best one within `searchRadius` that the adapter's
 * `lastHitFilter` allows). Waits in attack range until the bot believes its hit, ordered now, lands after
 * everyone else's incoming damage and kills: `creepHP + regen * t - incoming(t) <= ownDamage`, where t is the
 * own hit time (wind-up, cooldown, projectile travel) and incoming counts attack projectiles in flight and
 * wind-ups of creeps, heroes and towers targeting the creep. The belief carries a per-creep error from the
 * bot's skill (see docs/API.md): misses are early swings (`missed`) or late ones (`taken_by_other`/`denied`).
 * Ok once the bot's last-hit count rises.
 */
export function* lastHit(bot: TaskUnit, opts: LastHitOpts = {}): TaskBody {
    return yield* strike(bot, "lasthit", opts);
}

/**
 * Denies an allied lane creep: as `lastHit`, but only swings while the creep is below 50% HP (Dota refuses
 * the order above it), and confirms on the bot's deny count. `lastHitFilter` does not apply; whether a core
 * should deny rather than last-hit is the body's decision. Lost to an enemy last hit: `taken_by_other`.
 */
export function* deny(bot: TaskUnit, opts: LastHitOpts = {}): TaskBody {
    return yield* strike(bot, "deny", opts);
}
