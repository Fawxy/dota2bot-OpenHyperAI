/**
 * Safe here, the game side (design docs/proposals/2026-11-19-safe-here-design.md in the master repo, sections 2, 3, 5 and 7 step 3).
 * `FromRead` builds `Safe.Inputs` from a `Threat.Read` the consumer already made this frame; `Shadow` runs `Safe.Decide` on them
 * and logs `ev=cut kind=safe` beside the consumer's own decision. Nothing reads the answer: a fault in Shadow is reported and
 * swallowed, and no consumer's behaviour depends on this module.
 *
 * The landing sampler has no Tick step of its own: it takes a sample when a shadow call site runs for that hero, so a hero no
 * site asks about costs nothing.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as Safe from "bots/FunLib/humaniser/safe";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

export const SETTINGS = {
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
};

export interface Opts {
    away: boolean;
    held: boolean;
    /** The caller has a hold (a hit back or a join). A function is asked only when the shadow runs, for a hold that costs a read. */
    hold: boolean | ((this: void) => boolean);
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
 * creep, a tower). A drop with no flag is not counted (burn, fall damage, an unflagged source); a rise is ignored. Called by
 * `Shadow` before it reads the landing; a second call in the same frame does nothing.
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

const towerSeen: Record<number, { t: number; on: boolean } | undefined> = {};

/**
 * A live enemy tower whose reach holds `bot` is attacking it or hit it in the last half second: retreat's `TowerOnUs` test
 * written again here, since retreat imports this module (a require cycle). Read once a frame per hero.
 */
function towerOnMe(bot: Unit, now: number): boolean {
    const pid = bot.GetPlayerID();
    const seen = towerSeen[pid];
    if (seen !== undefined && seen.t === now) return seen.on;
    let on = false;
    const br = bot.GetBoundingRadius();
    for (const tw of bot.GetNearbyTowers(1200, true) ?? []) {
        if (!tw.IsAlive()) continue;
        if (GetUnitToUnitDistance(bot, tw) > WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + br) continue;
        if (tw.GetAttackTarget() === bot || bot.WasRecentlyDamagedByTower(0.5)) {
            on = true;
            break;
        }
    }
    towerSeen[pid] = { t: now, on };
    return on;
}

// ------------------------------------------------------------------------------------------------------------ the inputs

/**
 * `Safe.Inputs` from a read the consumer made this frame (no second read; a consumer that caches its read for a fraction of a second
 * passes the cached one, and the clock here is the game's now, not the read's `t`). `hitting` is the read's `eng`, so it is only set when
 * the read was made with `engagedWindow`; a gate's read (no window) has none hitting and every row at the short window.
 * `exit`: the longest, over the reachers, of the seconds for the hero to walk straight away from where it stands to the edge of
 * that hero's reach (its `run`: speed x the read's horizon + attack range + both hulls), at our current speed. A hero already
 * outside a row's reach adds 0, and an unseen lane row has no place to measure from. Logged only.
 */
export function FromRead(bot: Unit, r: Threat.Read, opts: Opts): Safe.Inputs {
    const reach: Safe.Reacher[] = [];
    for (const row of r.rows) reach.push({ pid: row.pid, hitting: row.eng, dmg: row.dmg });
    let exit = 0;
    if (r.rows.length > 0) {
        const here = bot.GetLocation();
        const speed = math.max(1, bot.GetCurrentMovementSpeed());
        for (const row of r.rows) exit = math.max(exit, math.max(0, row.run - dist(here, row.at)) / speed);
    }
    for (const l of lanerRows(bot, r)) reach.push(l);
    return {
        hp: bot.GetHealth(),
        hpMax: bot.GetMaxHealth(),
        reach,
        missing: r.missing,
        tower: r.tower,
        towerOnMe: towerOnMe(bot, DotaTime()),
        landing: Landing(bot, DotaTime()),
        exit: r.rows.length > 0 ? exit : undefined,
        away: opts.away,
        held: opts.held,
        hold: typeof opts.hold === "function" ? opts.hold() : opts.hold,
    };
}

// -------------------------------------------------------------------------------------------------------------- the cut

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
        ["lv", a.level],
        ["kill", n0(a.kill)],
        ["ra", a.kill > 0 ? r2(a.ratio) : undefined],
        ["pr", r2(a.price)],
        ["why", a.reason],
    ];
}

const cutState: Record<string, { key: string; at: number } | undefined> = {};

function shadow(bot: Unit, who: string, r: Threat.Read, opts: Opts): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || !bot.IsAlive()) return;
    Sample(bot, DotaTime());
    const i = FromRead(bot, r, opts);
    const a = Safe.Decide(i);
    const key = `${a.level}:${a.reason}`;
    const id = `${bot.GetPlayerID()}:${who}`;
    const now = DotaTime();
    const last = cutState[id];
    if (last !== undefined && last.key === key && (now - last.at < SETTINGS.CutEvery || (i.reach.length === 0 && a.price <= 0))) return;
    cutState[id] = { key, at: now };
    Telemetry.Event("cut", CutFields(bot.GetPlayerID(), who, r.place, i, a));
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

/** Per game (the other caches' reset): the sampler, the lane memory and the shadow's cadence. */
export function ResetCache(): void {
    for (const k of Object.keys(samplers)) delete samplers[k as unknown as number];
    for (const k of Object.keys(laners)) delete laners[k as unknown as number];
    for (const k of Object.keys(towerSeen)) delete towerSeen[k as unknown as number];
    for (const k of Object.keys(cutState)) delete cutState[k];
}

/** Threat.Gate's call (a trip: the walk leaves our creeps and tower; the gate holds nothing). index.ts registers it with `Threat.SetGateShadow`. */
export function GateShadow(this: void, bot: Unit, consumer: string, r: Threat.Read): void {
    Shadow(bot, consumer, r, { away: true, held: false, hold: false });
}

export const _test = { samplers, laners, cutState };
