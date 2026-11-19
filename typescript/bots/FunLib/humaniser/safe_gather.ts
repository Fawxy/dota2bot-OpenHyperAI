/**
 * Safe here, the game side (design docs/proposals/2026-11-19-safe-here-design.md in the master repo, sections 2, 3, 5 and 7 step 3).
 * `FromRead` builds `Safe.Inputs` from a `Threat.Read` the consumer already made this frame; `Shadow` runs `Safe.Decide` on them
 * and logs `ev=cut kind=safe` beside the consumer's own decision. Nothing reads the answer: a fault in Shadow is reported and
 * swallowed, and no consumer's behaviour depends on this module.
 *
 * `At` is the one call a consumer makes: any place, the frame's shared reader, the answer returned. The landing sampler is a per-hero
 * Tick step (`Tick`), independent of telemetry; `FromRead` and `At` only read it.
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
    if (!cutOn() || !bot.IsAlive()) return;
    const i = FromRead(bot, r, opts);
    log(bot, who, r.place, i, Safe.Decide(i));
}

function cutOn(): boolean {
    return Telemetry.IsEnabled() && Telemetry.Get().Cut === true;
}

function log(bot: Unit, who: string, place: Vector, i: Safe.Inputs, a: Safe.Answer): void {
    const key = `${a.level}:${a.reason}`;
    const id = `${bot.GetPlayerID()}:${who}`;
    const now = DotaTime();
    const last = cutState[id];
    if (last !== undefined && last.key === key && (now - last.at < SETTINGS.CutEvery || (i.reach.length === 0 && a.price <= 0))) return;
    cutState[id] = { key, at: now };
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
function ask(bot: Unit, place: Vector, opts?: AtOpts): { a: Safe.Answer; r: Threat.Read } {
    const horizon = opts?.horizon ?? (opts?.held === true || opts?.hold === true ? Threat.SETTINGS.StayHorizon : SETTINGS.FreshHorizon);
    const from = opts?.from ?? bot.GetLocation();
    const r = frameReader(bot, horizon, opts?.engaged ?? true, opts?.exclude)(from, place);
    const i = FromRead(bot, r, { away: opts?.away ?? false, held: opts?.held ?? false, hold: opts?.hold ?? false });
    const a = Safe.Decide(i);
    const who = opts?.who;
    if (who !== undefined && cutOn() && bot.IsAlive()) {
        const [ok, err] = pcall(log, bot, who, place, i, a);
        if (!ok) Telemetry.Failed("SafeGather.At", err);
    }
    return { a, r };
}

/** Per game (the other caches' reset): the sampler, the lane memory, the shared readers and the shadow's cadence. */
export function ResetCache(): void {
    for (const k of Object.keys(frames)) delete frames[k as unknown as number];
    for (const k of Object.keys(samplers)) delete samplers[k as unknown as number];
    for (const k of Object.keys(laners)) delete laners[k as unknown as number];
    for (const k of Object.keys(towerSeen)) delete towerSeen[k as unknown as number];
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
