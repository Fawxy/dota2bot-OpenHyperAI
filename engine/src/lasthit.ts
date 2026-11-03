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
/** Seconds a hit must land before ours to be relied on: one server tick at 30 fps. */
const MIN_MARGIN = 0.034;
/**
 * The frame margin: 1.2x the observed gap between the frames the verb is stepped at (MIN_MARGIN to MAX_MARGIN).
 * It only bounds how early in the attack cooldown an order may be given; the prediction horizon uses MIN_MARGIN.
 */
const MAX_MARGIN = 0.3;
/**
 * Seconds of the creep's HP history the observed damage rate is read over (at least one lane creep attack cycle, 1 s,
 * with room for the hits to be unevenly spaced), and the least history it needs (under one creep hit apart: shorter
 * and a single hit reads as a huge rate).
 */
const OBSERVE_WINDOW = 1.5;
const OBSERVE_MIN = 0.3;
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
    /** Enemy heroes within QUERY_RADIUS, queried once per frame on first use. */
    enemyHeroes?: TaskHero[];
    /** Attackers by their current target, built once per frame (one GetAttackTarget per unit). */
    byTarget?: LuaTable<TaskAttacker, TaskAttacker[]>;
    /** The towers and heroes among `others`, for the forecast's attacker kinds. */
    towers?: LuaTable<TaskAttacker, boolean>;
    heroes?: LuaTable<TaskAttacker, boolean>;
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

function enemyHeroes(bot: TaskUnit, n: Nearby): TaskHero[] {
    if (n.enemyHeroes === undefined) n.enemyHeroes = bot.GetNearbyHeroes?.(QUERY_RADIUS, true, 0) ?? [];
    return n.enemyHeroes;
}

/** Heroes and towers of both teams; only queried once a swing decision is due. */
function others(bot: TaskUnit, n: Nearby): TaskAttacker[] {
    if (n.others !== undefined) return n.others;
    const out: TaskAttacker[] = [];
    const towers = new LuaTable<TaskAttacker, boolean>();
    const heroes = new LuaTable<TaskAttacker, boolean>();
    for (const enemies of [true, false]) {
        for (const h of enemies ? enemyHeroes(bot, n) : bot.GetNearbyHeroes?.(QUERY_RADIUS, false, 0) ?? []) {
            if (h.GetLocation !== undefined && h.IsAlive !== undefined) {
                out.push(h as TaskHero as TaskAttacker);
                heroes.set(h as TaskHero as TaskAttacker, true);
            }
        }
        for (const t of bot.GetNearbyTowers?.(QUERY_RADIUS, enemies) ?? []) {
            out.push(t);
            towers.set(t, true);
        }
    }
    n.others = out;
    n.towers = towers;
    n.heroes = heroes;
    return out;
}

function physical(creep: TaskCreep, raw: number): number {
    if (creep.GetActualIncomingDamage === undefined) return raw;
    return creep.GetActualIncomingDamage(raw, DAMAGE_TYPE_PHYSICAL ?? 1);
}

function isRanged(u: TaskAttacker): boolean {
    return (u.GetAttackRange?.() ?? 0) > RANGED_ABOVE && (u.GetAttackProjectileSpeed?.() ?? 0) > 0;
}

/** Seconds until `a`'s attack point (after it, the attack can no longer be cancelled), or undefined when not winding up. */
function windupLeft(a: TaskAttacker): number | undefined {
    if (a.GetAnimActivity === undefined) return undefined;
    const act = a.GetAnimActivity();
    if (act !== ACTIVITY_ATTACK && act !== ACTIVITY_ATTACK2) return undefined;
    if (a.GetAnimCycle === undefined || a.GetAttackPoint === undefined) return undefined;
    const cycle = a.GetAnimCycle();
    const point = a.GetAttackPoint();
    if (cycle >= point) return undefined;
    return (point - cycle) * (a.GetSecondsPerAttack?.() ?? 1);
}

/**
 * Seconds until `a`'s current attack on `creep` lands, or undefined when it is not winding one up. UNVERIFIED
 * in-game: reads the wind-up left as (attackPoint - animCycle) * secondsPerAttack, which treats
 * the attack point as a fraction of the attack cycle.
 */
function windupLanding(a: TaskAttacker, creep: TaskCreep): number | undefined {
    let t = windupLeft(a);
    if (t === undefined) return undefined;
    if (isRanged(a)) {
        t += math.max(0, dist(a.GetLocation(), creep.GetLocation()) - CREEP_LAUNCH_OFFSET) / a.GetAttackProjectileSpeed!();
    }
    return t;
}

/**
 * Damage (after armour) the creep takes from others within `horizon` seconds: attack projectiles in flight
 * plus every attacker of either team winding up an attack on it. Attacks not yet started are not counted;
 * the prediction runs every frame, so they enter it once their wind-up begins.
 */
export function incomingDamage(bot: TaskUnit, creep: TaskCreep, horizon: number): number {
    return physical(creep, scanAttackers(bot, creep, horizon).raw);
}

/**
 * Damage per second (after armour) of the attackers targeting the creep: `dps` all of them, `between` only those
 * not winding up an attack now (their next hit lands at an unknown time within one attack cycle, so it is
 * extrapolated; an attacker in its wind-up is credited with that hit by `incomingDamage` and its next one comes a
 * cycle later, beyond any horizon the verbs use).
 */
export function incomingDps(bot: TaskUnit, creep: TaskCreep): { dps: number; between: number } {
    const s = scanAttackers(bot, creep, 0);
    return { dps: physical(creep, s.dps), between: physical(creep, s.between) };
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

function scanAttackers(bot: TaskUnit, creep: TaskCreep, horizon: number): { raw: number; dps: number; between: number } {
    let raw = 0;
    let dps = 0;
    let between = 0;
    for (const p of creep.GetIncomingTrackingProjectiles?.() ?? []) {
        const c = p.caster;
        if (p.is_attack === true && c !== undefined && c !== null && c !== (bot as unknown) && !(c.IsNull?.() ?? false)) {
            const speed = c.GetAttackProjectileSpeed?.() ?? 0;
            if (speed > 0 && dist(p.location, creep.GetLocation()) / speed <= horizon) raw += c.GetAttackDamage?.() ?? 0;
        }
    }
    for (const a of attackersByTarget(bot, nearby(bot)).get(creep as TaskAttacker) ?? []) {
        if (a === (creep as TaskAttacker)) continue;
        const land = windupLanding(a, creep);
        const damage = a.GetAttackDamage?.() ?? 0;
        if (land !== undefined && land <= horizon) raw += damage;
        const rate = damage / (a.GetSecondsPerAttack?.() ?? 1);
        dps += rate;
        if (land === undefined) between += rate;
    }
    return { raw, dps, between };
}

/** The longest forecast `hpForecast` makes, in seconds (a larger horizon is cut to it). */
const FORECAST_MAX = 10;

/** One hit the forecast expects: seconds from now until it lands, damage after armour, and the attacker's kind. */
export interface ForecastHit {
    t: number;
    damage: number;
    by: "tower" | "creep" | "hero" | "self";
}

export interface HpForecast {
    /** HP and regen now. */
    hp: number;
    regen: number;
    horizon: number;
    /**
     * Hits at known times, sorted by `t`: attack projectiles in flight (the bot's own included), wind-ups seen, and for towers
     * and lane creeps the repeats of their latest known hit every attack cycle while they keep attacking it.
     */
    hits: ForecastHit[];
    /**
     * DPS after armour of the attackers on the creep with no hit in flight or wind-up (their next hit time is unknown),
     * spread evenly from SEEN_AHEAD on, as `believe` extrapolates them.
     */
    unphased: number;
    /** A tower among those: its hits are the forecast's largest, so with one unphased the hit times are not known. */
    unphasedTower: boolean;
    /**
     * The same attackers one by one: damage after armour, attack cycle, and `first`, the earliest their next hit can land (a
     * wind-up from now, plus flight for a ranged one); the latest is `first` + `period` (a wind-up that starts one cycle from now).
     */
    unphasedHits: { damage: number; period: number; first: number }[];
}

/**
 * How `forecastHp` places the hits of the attackers whose phase is unknown: `spread` evenly from SEEN_AHEAD on (as the last-hit
 * belief), `early` each one's next hit at its `first` and every cycle after, `late` one cycle later than `early`.
 */
export type ForecastSchedule = "spread" | "early" | "late";

/**
 * The creep's HP over the next `horizon` seconds from the hits the attacker index already sees: projectiles in flight
 * (arrival = distance / projectile speed), wind-ups (`windupLanding`), and for a tower or lane creep, its latest known hit
 * repeated every `GetSecondsPerAttack` while it attacks the creep now (UNVERIFIED in-game that it stays on it: a tower re-targets
 * on hero aggro or when the creep leaves its range, and a lane creep on aggro, which the repeats do not foresee). Heroes are not repeated: their next attacks are choices, not a cycle. Repeats assume the distance, and so the
 * flight time, stays as now. A fact for a caller that plans more than the one swing `lastHit` makes (the pre-hit under a
 * tower); `forecastHp` reads it.
 */
export function hpForecast(bot: TaskUnit, creep: TaskCreep, horizon: number): HpForecast {
    // Repeats are listed up to the horizon, so an unbounded one would never end; a forecast past a few attack cycles says nothing.
    horizon = math.min(horizon, FORECAST_MAX);
    const n = nearby(bot);
    others(bot, n);
    const towers = n.towers!;
    const heroes = n.heroes!;
    const kindOf = (a: TaskAttacker): ForecastHit["by"] =>
        a === (bot as unknown) ? "self" : towers.get(a) === true ? "tower" : heroes.get(a) === true ? "hero" : "creep";
    const hits: ForecastHit[] = [];
    const latest = new LuaTable<TaskAttacker, number>();
    const here = creep.GetLocation();
    for (const p of creep.GetIncomingTrackingProjectiles?.() ?? []) {
        const c = p.caster;
        if (p.is_attack !== true || c === undefined || c === null || (c.IsNull?.() ?? false)) continue;
        const speed = c.GetAttackProjectileSpeed?.() ?? 0;
        if (speed <= 0) continue;
        const t = dist(p.location, here) / speed;
        if (t > horizon) continue;
        hits.push({ t, damage: physical(creep, c.GetAttackDamage?.() ?? 0), by: kindOf(c) });
        latest.set(c, math.max(latest.get(c) ?? -math.huge, t));
    }
    let unphased = 0;
    let unphasedTower = false;
    const unphasedHits: { damage: number; period: number; first: number }[] = [];
    for (const a of attackersByTarget(bot, n).get(creep as TaskAttacker) ?? []) {
        if (a === (creep as TaskAttacker)) continue;
        const kind = kindOf(a);
        const damage = physical(creep, a.GetAttackDamage?.() ?? 0);
        const period = a.GetSecondsPerAttack?.() ?? 1;
        const land = windupLanding(a, creep);
        if (land !== undefined && land <= horizon) {
            hits.push({ t: land, damage, by: kind });
            latest.set(a, math.max(latest.get(a) ?? -math.huge, land));
        }
        const last = land ?? latest.get(a);
        if (last === undefined) {
            unphased += damage / period;
            if (kind === "tower") unphasedTower = true;
            let first = (a.GetAttackPoint?.() ?? 0) * period;
            if (isRanged(a)) first += math.max(0, dist(a.GetLocation(), here) - CREEP_LAUNCH_OFFSET) / a.GetAttackProjectileSpeed!();
            unphasedHits.push({ damage, period, first });
            continue;
        }
        if (kind === "hero" || period <= 0) continue;
        for (let t = last + period; t <= horizon; t += period) hits.push({ t, damage, by: kind });
    }
    table.sort(hits, (x, y) => x.t < y.t);
    return { hp: creep.GetHealth(), regen: creep.GetHealthRegen?.() ?? 0, horizon, hits, unphased, unphasedTower, unphasedHits };
}

/** The forecast's HP `t` seconds from now (may go below 0: the creep is dead by then), the unknown-phase hits placed by `schedule`. */
export function forecastHp(f: HpForecast, t: number, schedule: ForecastSchedule = "spread"): number {
    let hp = f.hp + f.regen * t;
    if (schedule === "spread") hp -= f.unphased * math.max(0, t - SEEN_AHEAD);
    else {
        for (const u of f.unphasedHits) {
            const first = schedule === "early" ? u.first : u.first + u.period;
            if (t >= first && u.period > 0) hp -= u.damage * (math.floor((t - first) / u.period) + 1);
        }
    }
    for (const h of f.hits) {
        if (h.t > t) break;
        hp -= h.damage;
    }
    return hp;
}

/**
 * Enemy heroes in the attacker index on the creep whose wind-up lands within `horizon` (the hits `believe` credited
 * as certain): their count, raw damage, and the latest of their commit points (seconds until their attack point).
 * Swing-message attribution only.
 */
function enemyHeroWindups(bot: TaskUnit, creep: TaskCreep, horizon: number): { n: number; raw: number; commit: number } {
    const heroes = new LuaTable<TaskAttacker, boolean>();
    for (const h of enemyHeroes(bot, nearby(bot))) heroes.set(h as TaskHero as TaskAttacker, true);
    let n = 0;
    let raw = 0;
    let commit = 0;
    for (const a of attackersByTarget(bot, nearby(bot)).get(creep as TaskAttacker) ?? []) {
        if (heroes.get(a) !== true) continue;
        const land = windupLanding(a, creep);
        if (land === undefined || land > horizon) continue;
        n++;
        raw += a.GetAttackDamage?.() ?? 0;
        commit = math.max(commit, windupLeft(a) ?? 0);
    }
    return { n, raw, commit };
}

/**
 * In-game check of the wind-up reader on enemy heroes (UNVERIFIED `windupLeft`): over the frames a verb watched one
 * creep, how many had an enemy hero attacking it (`frames`), how many of those read that hero as winding up
 * (`windup`), and the raw animation reading of the last such hero (of the last wind-up frame once one was seen) (`act`, `cycle`, `point`; message fields hf hwf ha hc hpt). Message attribution only.
 */
interface HeroWatch {
    frames: number;
    windup: number;
    act: number;
    cycle: number;
    point: number;
}

function watchHeroes(bot: TaskUnit, creep: TaskCreep, w: HeroWatch): void {
    let seen = false;
    let winding = false;
    for (const h of enemyHeroes(bot, nearby(bot))) {
        const a = h as TaskHero as TaskAttacker;
        if (a.GetAttackTarget?.() !== creep) continue;
        seen = true;
        const up = windupLeft(a) !== undefined;
        if (up) winding = true;
        // After a wind-up frame, keep its reading: the animation that follows the hit says nothing about the reader.
        if (!up && (winding || w.windup > 0)) continue;
        w.act = a.GetAnimActivity?.() ?? -1;
        w.cycle = a.GetAnimCycle?.() ?? -1;
        w.point = a.GetAttackPoint?.() ?? -1;
    }
    if (seen) w.frames++;
    if (winding) w.windup++;
}

function heroWatchText(w: HeroWatch): string {
    if (w.frames === 0) return " hf=0 hwf=0";
    return string.format(" hf=%d hwf=%d ha=%d hc=%.2f hpt=%.2f", w.frames, w.windup, w.act, w.cycle, w.point);
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

/** Seconds from an attack order now until the bot's attack point: wind-up, cooldown left and turn. */
function ownCommitTime(bot: TaskUnit, creep: TaskCreep): number {
    return bot.GetAttackPoint!() / (bot.GetAttackSpeed?.() ?? 1) + cooldownLeft(bot) + turnTime(bot, creep);
}

export function ownHitTime(bot: TaskUnit, creep: TaskCreep): number {
    let t = ownCommitTime(bot, creep);
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
    /** Seconds of seen hits (wind-ups, projectiles) `hpAtHit` subtracted: shortened by a negative roll shift. */
    relied: number;
    /** Own damage as the bot believes it (error applied, after armour). */
    mine: number;
}

/**
 * What the bot believes about a swing ordered now. A negative timing shift shortens the horizon (late swing);
 * a positive one extends it with the attackers' DPS, i.e. counts hits that have not started yet (early swing):
 * the visible prediction alone cannot over-anticipate, so without that extrapolation early errors vanish.
 * `observedDps` is the creep's measured HP loss per second while the caller watched it (0 when unknown). The part
 * of it the attacker index does not account for (observed minus the indexed attackers' DPS) is damage from
 * attackers the index misses (fogged, untracked), extrapolated over the horizon; where the index sees every
 * attacker the belief is unchanged, so the seen wind-ups keep their phase information. In the lane-only
 * calibration games (llhscn1, 03/11/2026) the seen hits came to about half the damage that landed before our hit.
 */
function believe(bot: TaskUnit, creep: TaskCreep, withError: boolean, observedDps: number = 0): Belief {
    const tHit = ownHitTime(bot, creep);
    const regen = creep.GetHealthRegen?.() ?? 0;
    const hp = creep.GetHealth();
    // Only hits landing at least one server tick before ours are relied on: one landing in the same tick may be
    // applied after ours, and the creep survives our swing. (The margin is not the host's think gap: a hit landing
    // 0.1 s before ours is applied before it however rarely the body is stepped; tying the two together made the
    // verb ignore every hit in the last 0.2 s before its own and swing late, llhscn1.)
    // Beyond SEEN_AHEAD, hits that land before ours have not started their wind-up yet: extrapolate the DPS of
    // the attackers between swings over that part of the horizon (without it, ranged swings with 0.6-1 s horizons
    // come late). An attacker already winding up is credited with that hit above and not extrapolated too: counting
    // both read a 0.6-1 s horizon 12-30 HP too heavy and swung early (llhscn2, half the swings past 0.6 s missed).
    const relied = math.max(0, tHit - MIN_MARGIN);
    const { dps, between } = incomingDps(bot, creep);
    // The observed loss already includes regen (a negative regen is a drain the model counts below).
    const unseen = math.max(0, observedDps + regen - dps);
    const certain = hp + regen * tHit - incomingDamage(bot, creep, relied);
    const visible = certain - math.max(0, relied - SEEN_AHEAD) * between - unseen * relied;
    let believed = visible;
    let reliedUsed = relied;
    let width = 0;
    let eps = 0;
    if (withError) {
        const r = rollFor(bot, creep);
        width = Skill.lastHitError(bot);
        eps = r.eps;
        if (r.shift < 0) {
            const h = math.max(0, relied + r.shift);
            reliedUsed = h;
            believed = hp + regen * h - incomingDamage(bot, creep, h) - math.max(0, h - SEEN_AHEAD) * between - unseen * h;
        } else if (r.shift > 0) {
            believed = visible + regen * r.shift - dps * r.shift;
        }
    }
    return {
        tHit,
        // Survival is judged on seen hits only; the extrapolated ones may never come.
        survives: certain > 0,
        hpAtHit: believed,
        relied: reliedUsed,
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
    /** `prehit`: never offered by laneTargets; a caller's pick that `laneFarm` carries out as one attack (see LaneFarmOpts.pick). */
    kind: "lasthit" | "deny" | "prehit";
    /** Seconds until a swing ordered then would be due (0: due now), or the walk into attack range if longer. */
    eta: number;
    /** Seconds until a swing ordered then would be due (0: due now). */
    due: number;
    /** Seconds to walk into attack range at the current speed (0: in range). */
    walk: number;
    /** Seconds until the creep dies to the others' damage at their current DPS (exact, as `due`). */
    dies: number;
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

/**
 * Seconds until the creep is killable by a swing ordered then, the walk into attack range, and until it dies to the
 * others at their current DPS (hp at our hit over that DPS, plus our hit time; infinite with no one on it).
 */
function etaOf(bot: TaskUnit, c: TaskCreep, walkSpeed: number): [number, number, number] | undefined {
    const b = believe(bot, c, false);
    if (!b.survives) return undefined;
    const walk = math.max(0, dist(bot.GetLocation(), c.GetLocation()) - bot.GetAttackRange()) / walkSpeed;
    const margin = b.hpAtHit - b.mine;
    const dps = incomingDps(bot, c).dps + math.max(0, -(c.GetHealthRegen?.() ?? 0));
    const dies = dps > 0 ? b.tHit + b.hpAtHit / dps : math.huge;
    if (margin <= 0) return [0, walk, dies];
    if (dps <= 0) return undefined;
    return [margin / dps, walk, dies];
}

/**
 * The lane creeps that become killable within `within` seconds of the bot reaching attack range, enemy creeps
 * first, then allied ones (a caller's tie-break may rely on that order; within each side, the host's creep order): enemy creeps to last-hit (the adapter's `lastHitFilter` applies) and allied creeps to deny. Facts only, with
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
        out.push({ creep: c, kind, eta: math.max(e[0], e[1]), due: e[0], walk: e[1], dies: e[2], ranged: isRangedCreep(c) });
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
    const heroes: HeroWatch = { frames: 0, windup: 0, act: -1, cycle: -1, point: -1 };
    let diag = "";
    // Before a swing, what held it back on the last frame (in-game attribution of a lost creep that was never swung at):
    // `range` walking in, `cd` attack cooldown, `hp50` a deny above half HP, `wait` the kill belief not yet due.
    let held = "start";
    const early = (r: Result): Result => {
        r.message = string.format("w=%.2f why=%s", now() - start, held) + heroWatchText(heroes);
        return r;
    };
    let lastFrame: number | undefined;
    let margin = MIN_MARGIN;
    // In-game calibration: the mean gap between the frames this verb saw (how often the host steps the body).
    let gapSum = 0;
    let gapN = 0;
    // The damage actually landing on the creep, seen attackers or not: its HP as this verb saw it over the last
    // OBSERVE_WINDOW seconds, read as a lower bound on the rate (the loss over the window less one hit, the largest
    // single-frame drop seen). The window average over-reads by up to one hit whenever it does not divide the hit
    // period, and an over-read swings early while an under-read of the same size still lands (a swing's believed
    // HP at landing is at most one frame of damage under the kill, but the whole own damage above zero).
    const seen: { t: number; hp: number }[] = [];
    let observedDps = 0;
    while (true) {
        const t = now();
        if (lastFrame !== undefined && t > lastFrame) {
            margin = math.min(MAX_MARGIN, math.max(MIN_MARGIN, 1.2 * (t - lastFrame)));
            gapSum += t - lastFrame;
            gapN++;
        }
        lastFrame = t;
        if (!gone(creep)) {
            const hp = creep.GetHealth();
            seen.push({ t, hp });
            while (seen.length > 1 && t - seen[1].t >= OBSERVE_WINDOW) table.remove(seen, 1);
            const span = t - seen[0].t;
            let biggest = 0;
            for (let i = 1; i < seen.length; i++) biggest = math.max(biggest, seen[i - 1].hp - seen[i].hp);
            observedDps = span >= OBSERVE_MIN ? math.max(0, (seen[0].hp - hp - biggest) / span) : 0;
        }
        if (!bot.IsAlive()) return early(fail("dead"));
        if (gone(creep)) return early(fail(lostReason(enemyOnIt)));
        if (opts.interruptIf !== undefined && opts.interruptIf()) return early(fail("interrupted"));
        if (now() - start > maxWait || expired(opts.deadline)) return early(fail("timeout"));
        if (mode === "lasthit") enemyOnIt = enemyTargeting(bot, creep);
        watchHeroes(bot, creep, heroes);
        if (dist(bot.GetLocation(), creep.GetLocation()) > bot.GetAttackRange()) {
            held = string.format("range d=%d", math.floor(dist(bot.GetLocation(), creep.GetLocation()) - bot.GetAttackRange()));
            bot.Action_MoveToLocation(creep.GetLocation());
        } else {
            const cd = cooldownLeft(bot);
            held = mode === "deny" && !deniable(creep) ? "hp50" : string.format("cd c=%.2f", cd);
            // An order given during the attack cooldown starts the swing later than the prediction's horizon
            // covers (hits not yet wound up are unseen), so the decision waits until the swing can start.
            if ((mode === "lasthit" || deniable(creep)) && cooldownLeft(bot) <= math.max(margin, COOLDOWN_QUEUE)) {
                const b = believe(bot, creep, true, observedDps);
                held = string.format("wait hp=%d pred=%d mine=%d", math.floor(creep.GetHealth()), math.floor(b.hpAtHit), math.floor(b.mine));
                if (due(b)) {
                    tHit = b.tHit;
                    // In-game calibration (docs/API.md "UNVERIFIED"): what the swing was based on.
                    diag = string.format("w=%.2f hp=%d pred=%d mine=%d t=%.2f m=%.2f obs=%d idps=%d", now() - start, math.floor(creep.GetHealth()), math.floor(b.hpAtHit), math.floor(b.mine), b.tHit, margin, math.floor(observedDps), math.floor(incomingDps(bot, creep).dps));
                    // Enemy hero wind-ups this swing counted as certain (a feint would break them): `ew` how many, `er` 1
                    // when the swing is due only because of them, `ec` the latest of their commit points and `oc` ours
                    // (seconds from now).
                    const ew = enemyHeroWindups(bot, creep, b.relied);
                    if (ew.n > 0) {
                        diag = string.format("%s ew=%d er=%d ec=%.2f oc=%.2f", diag, ew.n, b.hpAtHit + physical(creep, ew.raw) > b.mine ? 1 : 0, ew.commit, ownCommitTime(bot, creep));
                    }
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
    // Calibration of the prediction against the game (docs/API.md "Message"): when the attack fired (`fa`, from
    // GetLastAttackTime rising; -1 never seen) and the creep's HP on the first frame at or past the predicted
    // landing (`lhp`; 0 gone, -1 never reached), beside the frame gap (`fg`).
    const atk0 = bot.GetLastAttackTime?.();
    let fireAt: number | undefined;
    let landHp: number | undefined;
    const out = (r: Result): Result => {
        const hp = gone(creep) ? 0 : math.floor(creep.GetHealth());
        r.message = string.format("%s end=%d dt=%.2f fa=%.2f lhp=%d fg=%.3f", diag, hp, now() - swingAt, fireAt ?? -1, landHp ?? -1, gapN > 0 ? gapSum / gapN : 0) + heroWatchText(heroes);
        return r;
    };
    while (true) {
        yield;
        if (fireAt === undefined && atk0 !== undefined && bot.GetLastAttackTime!() > atk0) fireAt = now() - swingAt;
        if (landHp === undefined && landBy()) landHp = gone(creep) ? 0 : math.floor(creep.GetHealth());
        if (counter() > baseline) return out(ok());
        // Gone with no credit: a late swing (someone else's hit took it) unless ours had fired by the predicted
        // landing. A creep that dies during our wind-up cancels the attack, so "gone past the landing time" alone
        // said `missed` for swings that were late by a fraction of a frame (half of llhscn1's `missed`).
        // Gone after our landing with the attack fired, or still alive at the landing: our hit did not kill it (missed).
        // Gone before, or at the landing with no attack fired (killed in our wind-up): someone else took it.
        if (gone(creep)) return out(fail(landBy() && (fireAt !== undefined || (landHp ?? 0) > 0) ? "missed" : lostReason(enemyOnIt)));
        if (!bot.IsAlive()) return fail("dead");
        if (now() - swingAt > tHit + CONFIRM_SLACK) return out(fail("missed"));
        if (mode === "lasthit") enemyOnIt = enemyTargeting(bot, creep);
        if (!gone(creep)) watchHeroes(bot, creep, heroes);
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
