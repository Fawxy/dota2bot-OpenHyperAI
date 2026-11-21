/**
 * Safe here, the game side (design docs/proposals/2026-11-19-safe-here-design.md in the master repo, sections 2, 3, 5 and 7 step 3).
 * `FromRead` builds `Safe.Inputs` from a `Threat.Read` the consumer already made this frame; `Shadow` runs `Safe.Decide` on them
 * and logs `ev=cut kind=safe` beside the consumer's own decision. Nothing reads the answer: a fault in Shadow is reported and
 * swallowed, and no consumer's behaviour depends on this module.
 *
 * `At` is the one call a consumer makes: any place, the frame's shared reader, the answer returned. The landing sampler is a per-hero
 * Tick step (`Tick`), independent of telemetry; `FromRead` and `At` only read it.
 */
import { DamageType, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Deaggro from "bots/FunLib/humaniser/deaggro";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Safe from "bots/FunLib/humaniser/safe";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

export const SETTINGS = {
    /**
     * `Safe.Inputs.pressed`: an enemy hero damaged us within this many seconds. The 1 s `hitting` flag lapses between a laner's swings, so a bar
     * switched on it left on a hit, read safe a second later and walked back in (smoke 20/11: restarts within 3 s of a safe end 16 a team against 14.9).
     * 3 is about two swings and the walk out of reach. Replay of h2h742: 2 to 6 s all keep the 160 deaths called; 3 drops 50 kill leaves a game. judgement.
     */
    PressWindow: 3,
    /** A lane opponent that reached us this recently still counts when unseen (design section 2). */
    LanerSeen: 10,
    /** A read is "of the hero's own position" when its `from` and `place` are both within this of the hero; only such reads feed the lane memory. */
    OwnPlace: 50,
    /** A hero whose last sighting is older than this is not visible now (a visible hero reads about 0). */
    UnseenAfter: 0.5,
    /** The landing is HP lost per second over this window (s). */
    Window: 2,
    /** Two samples further apart than this give no drop: the flags (a short window) cannot say who did it. */
    MaxGap: 1,
    /** The shadow logs an unchanged answer at most this often (s), and only while a hero is in reach or the price is over 0. */
    CutEvery: 2,
    /**
     * A fresh place is read this far ahead (s) unless the caller gives a horizon; a held one over `Threat.SETTINGS.StayHorizon` (2).
     * Who is in reach is a hard edge: one step out of a second hero's 2 s reach read safe and the lane sent the hero back in
     * (smoke 19/11: 240 episodes a game against 119). 3 was the lane spot's own horizon. judgement.
     */
    FreshHorizon: 3,
    /**
     * A reaching hero that is not hitting us yet is counted over this many seconds, whatever the reach horizon (one hitting us: `StayEngaged`, 6).
     * At 2 s the line trebled the frame a hero began to hit: h2h pair safe-tune0 (19/11), 15 deaths against 8 on the old rules, the
     * read safe at ratio 2 to 5 one line before `lethal`. 4 is about the walk out (logged exit 1 to 3.5 s) plus a turn. judgement.
     */
    KillWindow: 4,
    /**
     * `Ours.CreepRead`: enemy lane creeps within this of the place or of the hero turn on a hero that attacks a hero (EC-053: 500, plus 50 for
     * creeps moving during the order's latency; the trade's AGGRO_CLEAR).
     */
    AggroRadius: 550,
    /**
     * The shed order goes out this long after the ask: the swing has to fire first. A drawn creep that reaches us sooner is locked by then (no order
     * moves a creep with us inside its attack range) and counts over the whole window; a later one with a shed target is taken off before it hits.
     * judgement: smoke creepread_B_dire_smoke2, 13 of 15 sheds after a swing found every creep on us locked, the other 2 came off in 0.19 s.
     */
    ShedIn: 1,
    /**
     * `Ours.ExitWindow`: a reaching hero that is not hitting us is counted over the walk out of every reacher's range from the place
     * read (`exit`) plus this many seconds to turn and react, when that is under `KillWindow`. A hero that damaged us within `PressWindow` is not
     * capped (hitting us it keeps `StayEngaged`, between swings `KillWindow`):
     * it chases, and capping it called 17 more of h2h742's deaths under 3 s before (16 had a hitter). judgement.
     */
    ExitTurn: 1,
};

export interface Opts {
    away: boolean;
    held: boolean;
    /** The caller has a hold (a hit back or a join). A function is asked only when the shadow runs, for a hold that costs a read. */
    hold: boolean | ((this: void) => boolean);
    /** `AtOpts.draws`, `AtOpts.commits`. */
    draws?: boolean;
    commits?: boolean;
}

const r1 = (v: number): number => math.floor(v * 10 + 0.5) / 10;
const r2 = (v: number): number => math.floor(v * 100 + 0.5) / 100;
const n0 = (v: number): number => math.floor(v + 0.5);
const b01 = (b: boolean): number => (b ? 1 : 0);
const dist = (a: Vector, b: Vector): number => math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);

function distToSegment(p: Vector, a: Vector, b: Vector): number {
    const vx = b.x - a.x;
    const vy = b.y - a.y;
    const len2 = vx * vx + vy * vy;
    const u = len2 > 0 ? math.max(0, math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)) : 0;
    return math.sqrt((p.x - (a.x + u * vx)) ** 2 + (p.y - (a.y + u * vy)) ** 2);
}

// ------------------------------------------------------------------------------------------------------------- landing

interface Sample {
    t: number;
    hero: number;
    creeps: number;
    tower: number;
}
interface Sampler {
    hp: number;
    t: number;
    ring: Sample[];
}
const samplers: Record<number, Sampler | undefined> = {};

/**
 * One frame's HP drop against the last sample, split equally between the sources whose damage flag covers the gap (a hero, a
 * creep, a tower). A drop with no flag is not counted (burn, fall damage, an unflagged source); a rise is ignored. A second
 * call with the same `now` does nothing.
 */
export function Sample(bot: Unit, now: number): void {
    const pid = bot.GetPlayerID();
    const hp = bot.GetHealth();
    const s = samplers[pid];
    if (s === undefined || now < s.t) {
        samplers[pid] = { hp, t: now, ring: [] };
        return;
    }
    if (now === s.t) return;
    const dt = now - s.t;
    const drop = s.hp - hp;
    s.hp = hp;
    s.t = now;
    const keep: Sample[] = [];
    for (const x of s.ring) if (now - x.t <= SETTINGS.Window) keep.push(x);
    s.ring = keep;
    if (dt > SETTINGS.MaxGap || drop <= 0) return;
    const w = math.max(dt, 0.1);
    const hero = bot.WasRecentlyDamagedByAnyHero(w);
    const creeps = bot.WasRecentlyDamagedByCreep(w);
    const tower = bot.WasRecentlyDamagedByTower(w);
    const n = b01(hero) + b01(creeps) + b01(tower);
    if (n === 0) return;
    const share = drop / n;
    keep.push({ t: now, hero: hero ? share : 0, creeps: creeps ? share : 0, tower: tower ? share : 0 });
}

/**
 * The sampler's step, run once per hero per Humaniser tick (index.ts `steps.landing`, every `TickEvery`-th frame, 10 Hz), whether
 * or not telemetry is on. A lower rate loses the attribution: the damage flags cover only a short window (`MaxGap` = 1 s), so
 * samples further apart than that give no drop and the `landing` price reads 0 under real damage. A dead hero is not sampled
 * (its respawn would read as a rise and a death as a drop with a flag).
 */
export function Tick(bot: Unit): void {
    if (!bot.IsAlive()) return;
    Sample(bot, DotaTime());
}

/** HP a second lost to each source over the last `Window` seconds, from the samples taken so far. */
export function Landing(bot: Unit, now: number): Safe.Inputs["landing"] {
    const out = { hero: 0, creeps: 0, tower: 0 };
    const s = samplers[bot.GetPlayerID()];
    if (s === undefined) return out;
    for (const x of s.ring) {
        if (now - x.t > SETTINGS.Window) continue;
        out.hero += x.hero;
        out.creeps += x.creeps;
        out.tower += x.tower;
    }
    out.hero /= SETTINGS.Window;
    out.creeps /= SETTINGS.Window;
    out.tower /= SETTINGS.Window;
    return out;
}

// -------------------------------------------------------------------------------------------------------------- laners

/** Per bot, per enemy pid: the damage it could deal us when it last reached us, and when. */
const laners: Record<number, Record<number, { dmg: number; at: number } | undefined> | undefined> = {};

/**
 * Records the reachers of a read of our own position (see `OwnPlace`) and returns the lane opponents that reached us within `LanerSeen`, are not visible now and could
 * have run to the walk since their last sighting (the missing belief's run: the speed the read last saw, capped, plus its margin).
 */
function lanerRows(bot: Unit, r: Threat.Read): Safe.Reacher[] {
    const pid = bot.GetPlayerID();
    const mine = laners[pid] ?? {};
    laners[pid] = mine;
    const now = DotaTime();
    const visible: Record<number, boolean> = {};
    // Only a read of the hero's own position writes the memory: a hero that reaches a far camp or a kill walk has not reached us.
    const here = bot.GetLocation();
    const own = dist(r.from, here) <= SETTINGS.OwnPlace && dist(r.place, here) <= SETTINGS.OwnPlace;
    for (const row of r.rows) {
        visible[row.pid] = true;
        if (own) mine[row.pid] = { dmg: row.dmg, at: now };
    }
    const out: Safe.Reacher[] = [];
    for (const [k, c] of pairs(mine)) {
        if (c === undefined || visible[k] === true) continue;
        if (now - c.at > SETTINGS.LanerSeen) {
            mine[k] = undefined;
            continue;
        }
        if (!IsHeroAlive(k)) continue;
        const info = GetHeroLastSeenInfo(k)[0];
        if (info === undefined || info.time_since_seen <= SETTINGS.UnseenAfter) continue;
        const run = math.min((Threat.SeenSpeed(k) ?? Threat.SETTINGS.MissingSpeed) * info.time_since_seen, Threat.SETTINGS.MissingReachMax) + Threat.SETTINGS.MissingMargin;
        if (distToSegment(info.location, r.from, r.place) > run) continue;
        out.push({ pid: k, hitting: false, dmg: c.dmg, unseen: true });
    }
    return out;
}

// ----------------------------------------------------------------------------------------------------------------- tower

/** The towers on a hero this frame: where each stands and how far it reaches this hero (its reach plus the hero's hull). */
const towerSeen: Record<number, { t: number; on: { at: Vector; reach: number }[] } | undefined> = {};

/**
 * A live enemy tower whose reach holds `bot` is attacking it or hit it in the last half second (retreat's `TowerOnUs` test
 * written again here, since retreat imports this module: a require cycle), and that tower can reach `place`. The hero's own
 * place is always inside. A place the tower cannot reach is not deadly for it: h2h742 had 13.6 such refusals a game, the lane
 * spot's and its preference's, while a tower hit the hero where it stood. The recent-damage flag does not name its tower, so
 * every tower holding the hero counts then. Read once a frame per hero.
 */
function towerOnMe(bot: Unit, now: number, place: Vector): boolean {
    const pid = bot.GetPlayerID();
    let seen = towerSeen[pid];
    if (seen === undefined || seen.t !== now) {
        seen = { t: now, on: [] };
        const br = bot.GetBoundingRadius();
        const here = bot.GetLocation();
        for (const tw of bot.GetNearbyTowers(1200, true) ?? []) {
            if (!tw.IsAlive()) continue;
            const at = tw.GetLocation();
            const reach = WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + br;
            if (dist(at, here) > reach) continue;
            if (tw.GetAttackTarget() === bot || bot.WasRecentlyDamagedByTower(0.5)) seen.on.push({ at, reach });
        }
        towerSeen[pid] = seen;
    }
    for (const tw of seen.on) if (dist(tw.at, place) <= tw.reach) return true;
    return false;
}

/**
 * Pure: a tower's damage on us over `window` s from the moment it would be on us. `hit` is one attack's damage on us, `spa` its seconds per attack;
 * `onUs`: it targets us now. Else it turns to us when our lane creeps in its reach are dead: `creepHits`, the attacks it needs to kill them
 * (0: none there). Other damage on those creeps is not counted, so the turn can come sooner than read.
 */
export function TowerDrawn(hit: number, spa: number, onUs: boolean, creepHits: number, window: number): number {
    const from = onUs ? 0 : creepHits * spa;
    return (hit / math.max(spa, 0.1)) * math.max(0, window - from);
}

interface TowerFact {
    unit: Unit;
    at: Vector;
    reach: number;
    dmg: number;
    spa: number;
    target: Unit | undefined;
    /** Attacks to kill our lane creeps in its reach; filled on first use. */
    creepHits?: number;
}
const towerFacts: Record<number, { t: number; towers: TowerFact[] } | undefined> = {};
const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

/** The live enemy towers of `bot`'s team, read once a frame per team. */
function enemyTowers(bot: Unit, now: number): TowerFact[] {
    const team = bot.GetTeam();
    let seen = towerFacts[team];
    if (seen === undefined || seen.t !== now) {
        seen = { t: now, towers: [] };
        const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
        for (const id of TOWER_IDS) {
            const tw = GetTower(enemy, id);
            if (tw === undefined || tw === null || tw.IsNull() || !tw.IsAlive()) continue;
            const spa = (tw as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.();
            seen.towers.push({ unit: tw, at: tw.GetLocation(), reach: WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach), dmg: tw.GetAttackDamage(), spa: spa !== undefined && spa > 0 ? spa : 1, target: tw.GetAttackTarget() ?? undefined });
        }
        towerFacts[team] = seen;
    }
    return seen.towers;
}

function creepHitsOf(tw: TowerFact): number {
    if (tw.creepHits !== undefined) return tw.creepHits;
    let hits = 0;
    for (const c of GetUnitList(UnitType.AlliedCreeps) ?? []) {
        if (c === null || c.IsNull() || !c.IsAlive() || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        if (dist(c.GetLocation(), tw.at) > tw.reach + c.GetBoundingRadius()) continue;
        hits += math.ceil(c.GetHealth() / math.max(1, c.GetActualIncomingDamage(tw.dmg, DamageType.Physical)));
    }
    tw.creepHits = hits;
    return hits;
}

const physSeen: Record<number, { t: number; f: number } | undefined> = {};

/** The share of physical damage `bot` takes, read once a frame per hero (the lane spot asks about 50 places a frame). */
function physFactor(bot: Unit, now: number): number {
    const pid = bot.GetPlayerID();
    const seen = physSeen[pid];
    if (seen !== undefined && seen.t === now) return seen.f;
    const f = bot.GetActualIncomingDamage(1000, DamageType.Physical) / 1000;
    physSeen[pid] = { t: now, f };
    return f;
}

/** `Safe.Inputs.drawn` for `place` (`Ours.TowerRead`): one row per live enemy tower whose reach holds it and that would be on us inside the kill window. `attacks`: the act asked for is an attack on a hero (`AtOpts.draws`). */
function drawnAt(bot: Unit, now: number, place: Vector, attacks: boolean): Safe.Drawn[] {
    const out: Safe.Drawn[] = [];
    const br = bot.GetBoundingRadius();
    let physF: number | undefined;
    for (const tw of enemyTowers(bot, now)) {
        if (dist(tw.at, place) > tw.reach + br) continue;
        physF = physF ?? physFactor(bot, now);
        // A tower turns at once on a hero that attacks a hero of its side inside its reach, whatever creeps stand there.
        const onUs = attacks || tw.target === bot;
        const dmg = TowerDrawn(tw.dmg * physF, tw.spa, onUs, onUs ? 0 : creepHitsOf(tw), SETTINGS.KillWindow);
        if (dmg > 0) out.push({ src: "tower", dmg });
    }
    return out;
}

/** One enemy lane creep an attack at a place would draw: its distance from the place, its attack reach to our edge, its speed, its damage a second on us. */
export interface DrawnCreep {
    d: number;
    reach: number;
    ms: number;
    dps: number;
    /** A shed order would take it: it is not in attack range of the place and a creep of ours we could order on stands inside its acquisition range. */
    shed: boolean;
}

/** Pure: the creeps' damage on us at the place, each from its arrival to the end of `window`; one a shed order would take that arrives after `shedIn` counts nothing. */
export function CreepsDrawn(creeps: DrawnCreep[], window: number, shedIn: number): number {
    let dmg = 0;
    for (const c of creeps) {
        const ta = c.d <= c.reach ? 0 : c.ms > 0 ? (c.d - c.reach) / c.ms : math.huge;
        if (c.shed && ta > shedIn) continue;
        if (ta < window) dmg += c.dps * (window - ta);
    }
    return dmg;
}

interface CreepFact {
    at: Vector;
    reach: number;
    acq: number;
    ms: number;
    dps: number;
}
interface OwnCreep {
    at: Vector;
    r: number;
}
const creepSeen: Record<number, { t: number; enemy: CreepFact[]; own: OwnCreep[] } | undefined> = {};

/** The lane creeps round `bot`, read once a frame per hero: the enemy's as they would hit us, ours as shed targets. */
function laneCreeps(bot: Unit, now: number): { enemy: CreepFact[]; own: OwnCreep[] } {
    const pid = bot.GetPlayerID();
    let seen = creepSeen[pid];
    if (seen !== undefined && seen.t === now) return seen;
    seen = { t: now, enemy: [], own: [] };
    const physF = physFactor(bot, now);
    const hull = bot.GetBoundingRadius();
    for (const c of bot.GetNearbyLaneCreeps(1600, true) ?? []) {
        if (c.IsNull() || !c.IsAlive()) continue;
        const at = c.GetLocation() as Vector | undefined;
        if (at === undefined) continue;
        const spa = (c as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.();
        const r = c.GetBoundingRadius();
        seen.enemy.push({
            at,
            reach: c.GetAttackRange() + r + hull,
            acq: c.GetAcquisitionRange() + r,
            ms: c.GetCurrentMovementSpeed(),
            dps: (c.GetAttackDamage() / (spa !== undefined && spa > 0 ? spa : 1)) * physF,
        });
    }
    for (const c of bot.GetNearbyLaneCreeps(1600, false) ?? []) {
        if (c.IsNull() || !c.IsAlive() || !LaneState.IsLaneCreepName(c.GetUnitName())) continue;
        const at = c.GetLocation() as Vector | undefined;
        if (at !== undefined) seen.own.push({ at, r: c.GetBoundingRadius() });
    }
    creepSeen[pid] = seen;
    return seen;
}

/**
 * `Ours.CreepRead`: what an attack on a hero from `place` draws. `near`: the enemy lane creeps within `AggroRadius` of the place or of the hero;
 * `dmg`: their damage on us over `window` (`CreepsDrawn`), priced to the shed: `Deaggro.Plan` over the creeps of ours inside our attack range of the place.
 * `sheds` false: the act will not stop to shed (a kill or join), so every creep counts from its arrival.
 */
export function CreepsAt(bot: Unit, place: Vector, window: number = SETTINGS.KillWindow, sheds: boolean = true): { near: number; dmg: number } {
    const now = DotaTime();
    const lc = laneCreeps(bot, now);
    const here = bot.GetLocation();
    const drawn: DrawnCreep[] = [];
    const attackers: Deaggro.AttackerFact[] = [];
    for (const c of lc.enemy) {
        const d = dist(c.at, place);
        if (d > SETTINGS.AggroRadius && dist(c.at, here) > SETTINGS.AggroRadius) continue;
        drawn.push({ d, reach: c.reach, ms: c.ms, dps: c.dps, shed: false });
        attackers.push({ kind: "lane", x: c.at.x, y: c.at.y, reach: c.acq, locked: d <= c.reach });
    }
    if (drawn.length === 0) return { near: 0, dmg: 0 };
    const mine = bot.GetAttackRange() + bot.GetBoundingRadius();
    const own: Deaggro.OwnFact[] = [];
    for (const o of lc.own) {
        const d = dist(o.at, place);
        if (d <= mine + o.r) own.push({ x: o.at.x, y: o.at.y, d, r: o.r });
    }
    const plan = sheds ? Deaggro.Plan(attackers, own) : undefined;
    if (plan !== undefined && plan.target !== undefined) {
        const t = own[plan.target];
        for (let k = 0; k < drawn.length; k++) {
            const a = attackers[k];
            drawn[k].shed = !a.locked && math.sqrt((a.x - t.x) ** 2 + (a.y - t.y) ** 2) <= a.reach + t.r;
        }
    }
    return { near: drawn.length, dmg: CreepsDrawn(drawn, window, SETTINGS.ShedIn) };
}

const pressSeen: Record<number, { t: number; on: boolean } | undefined> = {};

/** An enemy hero damaged `bot` within `PressWindow`. Read once a frame per hero: the lane spot asks about 50 places a frame. */
function pressed(bot: Unit, now: number): boolean {
    const pid = bot.GetPlayerID();
    const seen = pressSeen[pid];
    if (seen !== undefined && seen.t === now) return seen.on;
    const on = bot.WasRecentlyDamagedByAnyHero(SETTINGS.PressWindow);
    pressSeen[pid] = { t: now, on };
    return on;
}

const exitSeen: Record<number, { t: number; dmg: Record<string, number>; by: Record<number, boolean> } | undefined> = {};

function exitFrame(bot: Unit, now: number): { t: number; dmg: Record<string, number>; by: Record<number, boolean> } {
    const pid = bot.GetPlayerID();
    let seen = exitSeen[pid];
    if (seen === undefined || seen.t !== now) {
        seen = { t: now, dmg: {}, by: {} };
        exitSeen[pid] = seen;
    }
    return seen;
}

/** `e` damaged `bot` within `PressWindow`, read once a frame per hero and enemy. */
function pressedBy(bot: Unit, e: Unit, now: number): boolean {
    const seen = exitFrame(bot, now);
    const pid = e.GetPlayerID();
    let on = seen.by[pid];
    if (on === undefined) {
        on = bot.WasRecentlyDamagedByHero(e, SETTINGS.PressWindow);
        seen.by[pid] = on;
    }
    return on;
}

/** `e`'s damage on `bot` over the exit window `w`, estimated once a frame per hero, enemy and window. */
function exitDamage(bot: Unit, e: Unit, w: number, now: number): number {
    const seen = exitFrame(bot, now);
    const key = `${e.GetPlayerID()}:${w}`;
    let dmg = seen.dmg[key];
    if (dmg === undefined) {
        dmg = SpellReady.DamageOn(e, bot, w);
        seen.dmg[key] = dmg;
    }
    return dmg;
}

// ------------------------------------------------------------------------------------------------------------ the inputs

/**
 * `Safe.Inputs` from a read the consumer made this frame (no second read; a consumer that caches its read for a fraction of a second
 * passes the cached one, and the clock here is the game's now, not the read's `t`). `hitting` is the read's `eng`, so it is only set when
 * the read was made with `engagedWindow`; a gate's read (no window) has none hitting and every row at the short window.
 * `exit`: the longest, over the reachers, of the seconds for the hero to walk straight away from the walk's nearest point to that hero (the place itself for an own-place read) to the edge of
 * that hero's reach (its `run`: speed x the read's horizon + attack range + both hulls), at our current speed. A place already
 * outside a row's reach adds 0, and an unseen lane row has no place to measure from. With `Ours.ExitWindow` a visible hero that
 * is not hitting us that did not damage us within `PressWindow`
 * is counted over `exit` + `ExitTurn` when that is under `KillWindow` (never more than the read gave it; not on an `away` walk).
 */
export function FromRead(bot: Unit, r: Threat.Read, opts: Opts): Safe.Inputs {
    const reach: Safe.Reacher[] = [];
    let exit = 0;
    if (r.rows.length > 0) {
        const speed = math.max(1, bot.GetCurrentMovementSpeed());
        for (const row of r.rows) exit = math.max(exit, math.max(0, row.run - distToSegment(row.at, r.from, r.place)) / speed);
    }
    const now = DotaTime();
    const draws = opts.draws === true && Ours.On("CreepRead");
    const drawn = Ours.On("TowerRead") ? drawnAt(bot, now, r.place, draws) : undefined;
    // The creeps' row needs the tower's: without `drawn` the flat tower rule stands and no row is read.
    if (drawn !== undefined && draws) {
        const dmg = CreepsAt(bot, r.place, SETTINGS.KillWindow, opts.commits !== true).dmg;
        if (dmg > 0) drawn.push({ src: "creeps", dmg });
    }
    // Half-second steps up: about 50 places a frame share at most six estimates per enemy. Not for a walk away (a trip's gate):
    // the hero means to stay at its end, and only own-place reads were replayed.
    const w = Ours.On("ExitWindow") && !opts.away ? math.ceil((exit + SETTINGS.ExitTurn) * 2) / 2 : SETTINGS.KillWindow;
    for (const row of r.rows) {
        // The read's `eng` covers 1 s and is absent on a read without an engaged window: a hero between swings is not idle.
        const capped = !row.eng && row.u !== undefined && w < SETTINGS.KillWindow && !pressedBy(bot, row.u, now);
        reach.push({ pid: row.pid, hitting: row.eng, dmg: capped ? math.min(row.dmg, exitDamage(bot, row.u!, w, now)) : row.dmg });
    }
    for (const l of lanerRows(bot, r)) reach.push(l);
    return {
        hp: bot.GetHealth(),
        hpMax: bot.GetMaxHealth(),
        reach,
        missing: r.missing,
        tower: r.tower,
        towerOnMe: towerOnMe(bot, DotaTime(), r.place),
        landing: Landing(bot, DotaTime()),
        exit: r.rows.length > 0 ? exit : undefined,
        away: opts.away,
        held: opts.held,
        hold: typeof opts.hold === "function" ? opts.hold() : opts.hold,
        // Ours.IdleBar off: every read is judged at the pressed bar (`Safe.BARS.stay`), as before the idle bar.
        pressed: !Ours.On("IdleBar") || pressed(bot, DotaTime()),
        drawn,
    };
}

// -------------------------------------------------------------------------------------------------------------- the cut

function drawnField(drawn: Safe.Drawn[]): string {
    const rows: string[] = [];
    for (const d of drawn) rows.push(`${d.src},${n0(d.dmg)}`);
    return rows.join(";");
}

/** The `ev=cut kind=safe` fields (tools/hlog/cut.js reads them back into Inputs; the place is `pl`). */
export function CutFields(pid: number, who: string, place: Vector, i: Safe.Inputs, a: Safe.Answer): Telemetry.Fields<"cut"> {
    const rows: string[] = [];
    for (const x of i.reach) rows.push([x.pid, b01(x.hitting), n0(x.dmg), b01(x.unseen === true)].join(","));
    return [
        ["pid", pid],
        ["kind", "safe"],
        ["who", who],
        ["pl", `${n0(place.x)},${n0(place.y)}`],
        ["hpa", n0(i.hp)],
        ["hpm", n0(i.hpMax)],
        ["rr", rows.length > 0 ? rows.join(";") : undefined],
        ["mi", r2(i.missing)],
        ["stw", `${b01(i.tower)},${b01(i.towerOnMe)}`],
        ["ld", `${r2(i.landing.hero)},${r2(i.landing.creeps)},${r2(i.landing.tower)}`],
        ["ex", i.exit !== undefined ? r1(i.exit) : undefined],
        ["awy", b01(i.away)],
        ["hld", b01(i.held)],
        ["hd", b01(i.hold)],
        ["prs", b01(i.pressed === true)],
        ["dr", i.drawn === undefined ? undefined : i.drawn.length === 0 ? "-" : drawnField(i.drawn)],
        ["lv", a.level],
        ["kill", n0(a.kill)],
        ["ra", a.kill > 0 ? r2(a.ratio) : undefined],
        ["pr", r2(a.price)],
        ["why", a.reason],
    ];
}

/** `skip`, `frame`, `n` (a sampled asker only): how many asks of this level to pass over before the next line, and the count in the frame being read. */
const cutState: Record<string, { key: string; at: number; skip?: number; frame?: number; n?: number } | undefined> = {};

function shadow(bot: Unit, who: string, r: Threat.Read, opts: Opts): void {
    if (!cutOn() || !bot.IsAlive()) return;
    const i = FromRead(bot, r, opts);
    log(bot, who, r.place, i, Safe.Decide(i));
}

function cutOn(): boolean {
    return Telemetry.IsEnabled() && Telemetry.Get().Cut === true;
}

/**
 * `sampled`: the asker's place differs from ask to ask (`AtOpts.sampled`), so the cadence is kept per level: a line per level each
 * `CutEvery`, whatever the place. The asks come in a fixed order each frame (the lane spot's rows nearest first), so the line taken moves
 * one ask further down that order each time, and starts again from the first when a frame has fewer asks of the level than that.
 */
function log(bot: Unit, who: string, place: Vector, i: Safe.Inputs, a: Safe.Answer, sampled?: boolean): void {
    const key = `${a.level}:${a.reason}`;
    const id = sampled === true ? `${bot.GetPlayerID()}:${who}:${a.level}` : `${bot.GetPlayerID()}:${who}`;
    const now = DotaTime();
    const last = cutState[id];
    let skip = 0;
    if (last !== undefined) {
        if (now - last.at < SETTINGS.CutEvery && (sampled === true || last.key === key)) return;
        if (last.key === key && i.reach.length === 0 && a.price <= 0) return;
        if (sampled === true) {
            if (last.frame !== now) {
                // The frame before had too few asks of this level to reach the one wanted: back to the first.
                if (last.frame !== undefined && (last.n ?? 0) <= (last.skip ?? 0)) last.skip = 0;
                last.frame = now;
                last.n = 0;
            }
            last.n = (last.n ?? 0) + 1;
            skip = last.skip ?? 0;
            if (last.n <= skip) return;
        }
    }
    cutState[id] = sampled === true ? { key, at: now, skip: skip + 1 } : { key, at: now };
    Telemetry.Event("cut", CutFields(bot.GetPlayerID(), who, place, i, a));
}

/**
 * The shadow of one consumer's question: the safe-here answer for the read it made, logged as `ev=cut kind=safe who=<who>` when the
 * level or reason changes, else every `CutEvery` s while a hero is in reach or the landing price is over 0. The answer is not
 * returned: nothing can act on it, and a fault inside is reported as ev=lua_error and dropped.
 */
export function Shadow(bot: Unit, who: string, r: Threat.Read, opts: Opts): void {
    const [ok, err] = pcall(shadow, bot, who, r, opts);
    if (!ok) Telemetry.Failed("SafeGather.Shadow", err);
}

// ----------------------------------------------------------------------------------------------------------------------- At

export interface AtOpts {
    /** The walk starts here; default the hero's location. */
    from?: Vector;
    /** Seconds ahead; default `Threat.SETTINGS.StayHorizon` for a held place or a hold, `SETTINGS.FreshHorizon` for a fresh one. */
    horizon?: number;
    /** Count a hero hitting us over `StayEngaged` (default true); a walk away from a fight that is not ours may turn it off. */
    engaged?: boolean;
    away?: boolean;
    held?: boolean;
    hold?: boolean;
    /** An unseen hero left out of the unknown weight (`Threat.ReadOpts.exclude`): a chase's target, whose place is the walk's end. */
    exclude?: number;
    /** When given and cut logging is on, the answer is logged as `ev=cut kind=safe who=<who>` like a shadow, so the call replays offline. */
    who?: string;
    /** With `who`: this asker asks many places a frame (a creep pick's walk-ins, the lane spot's candidates), so its lines are a sample, one per level each `CutEvery`, not one per place. */
    sampled?: boolean;
    /** `Ours.CreepRead`: the act asked for is an attack on a hero from the place, which draws the enemy lane creeps near it: their row joins `drawn`. */
    draws?: boolean;
    /** With `draws`: the act does not stop to shed the creeps it draws (a kill or join), so none is priced as shed. */
    commits?: boolean;
}

interface Frame {
    t: number;
    readers: Record<string, ((this: void, from: Vector, place: Vector) => Threat.Read) | undefined>;
}
const frames: Record<number, Frame | undefined> = {};

/** The reader for this hero, horizon and engaged option, made once per game-time value: `Threat.Reader` is valid only within the frame it was made in. */
function frameReader(bot: Unit, horizon: number, engaged: boolean, exclude?: number): (this: void, from: Vector, place: Vector) => Threat.Read {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let f = frames[pid];
    if (f === undefined || f.t !== now) {
        f = { t: now, readers: {} };
        frames[pid] = f;
    }
    const key = `${horizon}:${engaged ? 1 : 0}:${exclude ?? "-"}`;
    let rd = f.readers[key];
    if (rd === undefined) {
        rd = Threat.Reader(bot, horizon, { engagedWindow: engaged ? Threat.SETTINGS.StayEngaged : undefined, exclude, window: SETTINGS.KillWindow });
        f.readers[key] = rd;
    }
    return rd;
}

/**
 * Can `bot` be killed walking to `place` (design section 3, "one way to ask"): the only call a consumer makes. Reads the walk on the frame's
 * shared reader (several places in one frame cost one unit scan), builds the inputs, returns `Safe.Decide`'s answer, and logs it as
 * `who` when asked. It works with telemetry off. An error in the read or the decision is not caught here: it reaches the caller's
 * own error path (the consumers run under the Humaniser's guards), since a made-up answer would be a decision nobody can see. A fault
 * in the logging alone is reported and dropped.
 */
export function At(bot: Unit, place: Vector, opts?: AtOpts): Safe.Answer {
    return ask(bot, place, opts).a;
}

/** `At`'s answer with the read it was made from (a gate logs the read's reaching and unseen heroes). */
function ask(bot: Unit, place: Vector, opts?: AtOpts): { a: Safe.Answer; r: Threat.Read; i: Safe.Inputs } {
    const horizon = opts?.horizon ?? (opts?.held === true || opts?.hold === true ? Threat.SETTINGS.StayHorizon : SETTINGS.FreshHorizon);
    const from = opts?.from ?? bot.GetLocation();
    const r = frameReader(bot, horizon, opts?.engaged ?? true, opts?.exclude)(from, place);
    const i = FromRead(bot, r, { away: opts?.away ?? false, held: opts?.held ?? false, hold: opts?.hold ?? false, draws: opts?.draws, commits: opts?.commits });
    const a = Safe.Decide(i);
    const who = opts?.who;
    if (who !== undefined && cutOn() && bot.IsAlive()) {
        const [ok, err] = pcall(log, bot, who, place, i, a, opts?.sampled);
        if (!ok) Telemetry.Failed("SafeGather.At", err);
    }
    return { a, r, i };
}

/** The cut line for an answer a consumer decided from its own read (`FromRead` then `Safe.Decide`), so it replays like an `At` call. */
export function Note(bot: Unit, who: string, place: Vector, i: Safe.Inputs, a: Safe.Answer): void {
    if (!cutOn() || !bot.IsAlive()) return;
    const [ok, err] = pcall(log, bot, who, place, i, a);
    if (!ok) Telemetry.Failed("SafeGather.Note", err);
}

/** `At` asked once for both bars of one place: without a hold (`who` logs this one) and with one, from one read. */
export function AtBoth(bot: Unit, place: Vector, opts?: AtOpts): { plain: Safe.Answer; hold: Safe.Answer } {
    const { a, i } = ask(bot, place, { ...opts, hold: false });
    return { plain: a, hold: Safe.Decide({ ...i, hold: true }) };
}

/** Per game (the other caches' reset): the sampler, the lane memory, the shared readers and the shadow's cadence. */
export function ResetCache(): void {
    for (const k of Object.keys(frames)) delete frames[k as unknown as number];
    for (const k of Object.keys(samplers)) delete samplers[k as unknown as number];
    for (const k of Object.keys(laners)) delete laners[k as unknown as number];
    for (const k of Object.keys(towerSeen)) delete towerSeen[k as unknown as number];
    for (const k of Object.keys(towerFacts)) delete towerFacts[k as unknown as number];
    for (const k of Object.keys(physSeen)) delete physSeen[k as unknown as number];
    for (const k of Object.keys(creepSeen)) delete creepSeen[k as unknown as number];
    for (const k of Object.keys(pressSeen)) delete pressSeen[k as unknown as number];
    for (const k of Object.keys(exitSeen)) delete exitSeen[k as unknown as number];
    for (const k of Object.keys(cutState)) delete cutState[k];
}

/**
 * The start gate every trip shares (a camp, a pull, a stack, a farm trip, a core's pull): `At` for the walk from `from` (default the hero's place) to
 * `place`, 4 s, `away`, not held, and no hold. Held on `deadly`, with the answer's reason (`kill`, `tower`, `unknown`). The read and its
 * decision are logged as ev=threat for `consumer` (with the gate's cut for the fixtures), and as ev=cut kind=safe under the same name.
 */
export function TripGate(bot: Unit, place: Vector, consumer: string, from?: Vector): { why?: string; r: Threat.Read; a: Safe.Answer } {
    const { a, r } = ask(bot, place, { from, horizon: WalkHorizon, away: true, held: false, hold: false, who: consumer });
    const why = a.level === "deadly" ? a.reason : undefined;
    if (Threat.Log(bot, consumer, r, why ?? "go")) Threat.NoteGateCut(bot, r.from, r.place, consumer);
    return { why, r, a };
}

/** The horizon (s) of a walk to a place away from here (a trip, a kill or join target, a joiner's walk): design section 3. Here is `Threat.SETTINGS.StayHorizon`, 2 s. */
export const WalkHorizon = 4;

export const _test = { samplers, laners, cutState, frames };
