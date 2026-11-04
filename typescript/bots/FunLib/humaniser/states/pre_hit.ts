/**
 * Ours.PreHit (slice pre-hit, `docs/team/slices/pre-hit.md` in the master repo): a core hits an enemy lane creep our tower is
 * attacking so that the tower then leaves it in the core's kill range. Under a tower the one-swing `lastHit` verb cannot win a
 * creep whose HP steps from above our hit to below zero in one tower hit. Two questions on the engine's `hpForecast`: will the
 * creep's HP ever sit in our kill range long enough for a swing to land there? If not, would one hit of ours now (low and
 * high damage roll alike) make such a window by the time our next swing can land? Pre-hit only on "no", then "yes". The
 * swing is laneFarm's `prehit` (one `attackAndConfirm`); the normal last-hit pick then takes the creep. A pre-hit never spends
 * the swing a last hit on another creep needs: none may come due before our attack is ready again (user 04/11/2026).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** Seconds of forecast: a pre-hit's landing plus one attack cycle (about 1.4-1.7 s early) plus the window after it. `judgement`. */
export const HORIZON = 3.5;
/** Forecast sampling step in seconds (under a frame at 30 fps is not needed: windows are judged against WINDOW_MIN). */
export const STEP = 0.05;
/**
 * The shortest kill window a swing is trusted to land in: about one body step (0.167 s in game) plus a little for the timing
 * the verb still gets wrong. `judgement`.
 */
export const WINDOW_MIN = 0.2;
/** Own towers within this of the bot are read for their attack target (tower range 700 plus the reach of a short walk). */
const TOWER_RADIUS = 1200;

/**
 * From `from` on (seconds from now), the forecast HP with an optional extra hit: `window` when it stays in (0, mine] for at
 * least WINDOW_MIN before it dies, `dead` when it reaches 0 with no such run, `open` when it is still above 0 at the horizon
 * with none (the forecast cannot say).
 */
export type Window = "window" | "dead" | "open";

export interface Extra {
    t: number;
    d: number;
}

export function WindowFrom(
    this: void,
    hpAt: (this: void, t: number) => number,
    horizon: number,
    mine: number,
    from: number,
    extra?: Extra,
): Window {
    let runStart: number | undefined;
    for (let t = from; t <= horizon + 1e-9; t += STEP) {
        const hp = hpAt(t) - (extra !== undefined && t >= extra.t ? extra.d : 0);
        if (hp <= 0) return runStart !== undefined && t - runStart >= WINDOW_MIN ? "window" : "dead";
        if (hp <= mine) {
            if (runStart === undefined) runStart = t;
            if (t - runStart >= WINDOW_MIN) return "window";
        } else runStart = undefined;
    }
    return "open";
}

/** Why a pre-hit was or was not chosen, for the snapshot's `lf` (`pr=`) and ev=prehit (`why`). */
export type Verdict = "go" | "window" | "open" | "kills" | "no-after" | "lh" | "phase" | "far";

/**
 * The two questions, on the forecast under each schedule in `hpAts` (the engine's `spread`, `early`, `late` placements of the
 * hits whose time is unknown; prhchk2: with `spread` alone, 10 of 32 pre-hit creeps died before our next swing, 5 of them while
 * we were still on cooldown): no schedule may show a window already, and every schedule, at both rolls, must show one after our
 * hit. `t0` our earliest landing (walk plus own hit time), `period` our attack cycle, `lo`/`hi` our damage after armour at the
 * low and high roll. The kill range is the low roll's (as the last-hit verb's `mine`).
 */
export function Decide(
    this: void,
    hpAts: ((this: void, t: number) => number)[],
    horizon: number,
    t0: number,
    period: number,
    lo: number,
    hi: number,
): Verdict {
    let open = false;
    for (const hpAt of hpAts) {
        const now = WindowFrom(hpAt, horizon, lo, t0);
        if (now === "window") return "window";
        if (now === "open") open = true;
    }
    if (open) return "open";
    for (const hpAt of hpAts) {
        // A hit that may kill at t0 is a last hit, the last-hit verb's to take (it is also inside the window above at the low roll).
        if (hpAt(t0) <= hi) return "kills";
    }
    for (const hpAt of hpAts) {
        for (const d of [lo, hi]) {
            if (WindowFrom(hpAt, horizon, lo, t0 + period, { t: t0, d }) !== "window") return "no-after";
        }
    }
    return "go";
}

/** An own lane creep in reach of the creep that is not attacking it yet: its hit `damage` (after armour) every `period` from `first`. */
export interface Joiner {
    damage: number;
    first: number;
    period: number;
}

/**
 * `hpAt` with the hits of creeps that may join the attack, each at its earliest (prhfc3 04/11/2026: own lane creeps that turned
 * onto the creep after the decision fired 55 times in 27 pre-hits against 26 creep hits forecast, the largest part of the 30-130
 * HP the forecast missed).
 */
export function WithJoiners(this: void, hpAt: (this: void, t: number) => number, joiners: Joiner[]): (this: void, t: number) => number {
    return (t: number): number => {
        let hp = hpAt(t);
        for (const j of joiners) if (t >= j.first) hp -= j.damage * (math.floor((t - j.first) / j.period) + 1);
        return hp;
    };
}

/** Own creeps this far past their attack range from the creep count as joiners (about one body step of walking). `judgement`. */
const JOIN_SLACK = 100;

function joinersOf(bot: Unit, target: Unit): Joiner[] {
    const out: Joiner[] = [];
    for (const c of bot.GetNearbyLaneCreeps(1600, false) ?? []) {
        if (c.GetAttackTarget() === target || !c.IsAlive()) continue;
        const d = GetUnitToUnitDistance(c, target);
        if (d > c.GetAttackRange() + JOIN_SLACK) continue;
        const a = c as unknown as Lib.TaskUnit;
        const period = a.GetSecondsPerAttack?.() ?? 1;
        const speed = a.GetAttackProjectileSpeed?.() ?? 0;
        const flight = c.GetAttackRange() > 300 && speed > 0 ? d / speed : 0;
        out.push({
            damage: target.GetActualIncomingDamage(c.GetAttackDamage(), DamageType.Physical),
            first: (a.GetAttackPoint?.() ?? 0.5) * period + flight,
            period: math.max(0.1, period),
        });
    }
    return out;
}

export function Applies(bot: Unit): boolean {
    return Ours.On("PreHit") && CoreLastHit.Applies(bot);
}

interface Note {
    verdict: Verdict;
    creep?: Lib.TaskCreep;
    hp?: number;
    t0?: number;
    lo?: number;
}
const notes: Record<number, Note | undefined> = {};

/** The decision's numbers for the ev=prehit of the pre-hit on `creep`, if it was this bot's last one. */
export function NoteOf(pid: number, creep: Lib.TaskCreep): Note | undefined {
    const n = notes[pid];
    return n !== undefined && n.creep === creep ? n : undefined;
}

/**
 * The pre-hit this core would make now, as a `prehit` LaneTarget, or undefined. Candidates: enemy lane creeps an own tower is
 * attacking, within a MAX_WALK walk. `verbs` is the engine bundle's Verbs (hpForecast, ownHitTime, laneTargets).
 */
/**
 * The verdict on one tower's target and, on `go`, the pre-hit. A function with early returns rather than a loop body with
 * `continue`: TSTL's Lua 5.1 `continue` (a `repeat ... until true` block) put a statement after the loop's `break`, which LuaJIT
 * (Dota) refuses to compile, so the module and everything requiring it failed to load in game (prhchk1, 04/11/2026).
 */
function consider(bot: Unit, me: Lib.TaskUnit, verbs: typeof Lib.Verbs, tower: Unit, target: Unit): [Note | undefined, Lib.Verbs.LaneTarget | undefined] {
    if (!target.IsAlive() || target.GetTeam() === bot.GetTeam() || !target.IsCreep() || target.IsHero()) return [undefined, undefined];
    const creep = target as unknown as Lib.TaskCreep;
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const walk = math.max(0, GetUnitToUnitDistance(bot, target) - bot.GetAttackRange()) / speed;
    if (walk > LanePick.MAX_WALK) return [{ verdict: "far" }, undefined];
    const f = verbs.hpForecast(me, creep, HORIZON);
    if (f.unphasedTower) return [{ verdict: "phase", creep }, undefined];
    const t0 = walk + verbs.ownHitTime(me, creep);
    const period = me.GetSecondsPerAttack?.() ?? 1.7;
    const variance = me.GetBaseDamageVariance?.() ?? 0;
    const lo = target.GetActualIncomingDamage(bot.GetAttackDamage() - variance, DamageType.Physical);
    const hi = target.GetActualIncomingDamage(bot.GetAttackDamage() + variance, DamageType.Physical);
    const hpAt = (t: number): number => verbs.forecastHp(f, t);
    const early = (t: number): number => verbs.forecastHp(f, t, "early");
    const hpAts = [hpAt, early, (t: number): number => verbs.forecastHp(f, t, "late")];
    const joiners = joinersOf(bot, target);
    if (joiners.length > 0) hpAts.push(WithJoiners(early, joiners));
    let verdict = Decide(hpAts, HORIZON, t0, period, lo, hi);
    if (verdict === "go") {
        // Our attack is busy until t0 + period: a last hit on another creep due before then would be lost to it.
        for (const o of verbs.laneTargets(me, { within: t0 + period, deny: false })) {
            if (o.creep !== creep && LanePick.Reachable(o) && o.eta <= t0 + period) verdict = "lh";
        }
    }
    const note: Note = { verdict, creep, hp: f.hp, t0, lo };
    if (verdict !== "go") return [note, undefined];
    startWatch(bot, verbs, tower, target, f, lo);
    let dies = math.huge;
    for (let t = 0; t <= HORIZON && dies === math.huge; t += STEP) if (hpAt(t) <= 0) dies = t;
    return [note, { creep, kind: "prehit", eta: walk, due: 0, walk, dies, ranged: LanePick.IsRanged(creep) }];
}

export function Find(bot: Unit, verbs: typeof Lib.Verbs): Lib.Verbs.LaneTarget | undefined {
    if (!Applies(bot)) return undefined;
    const pid = bot.GetPlayerID();
    const me = bot as unknown as Lib.TaskUnit;
    let best: Lib.Verbs.LaneTarget | undefined;
    let note: Note | undefined;
    for (const tower of bot.GetNearbyTowers(TOWER_RADIUS, false) ?? []) {
        const target = tower.GetAttackTarget();
        if (best === undefined && target !== undefined && target !== null) {
            const [n, pre] = consider(bot, me, verbs, tower, target);
            // A far creep's verdict never hides a nearer one's.
            if (n !== undefined && (note === undefined || n.verdict !== "far")) note = n;
            best = pre;
        }
    }
    sampleWatch(bot, verbs);
    if (note !== undefined) {
        notes[pid] = note;
        LanePick.NoteVerdict(pid, DotaTime(), note.verdict);
    }
    return best;
}

/**
 * Forecast probe (prhchk3 04/11/2026: creeps the forecast had alive 2.4-3.5 s died 0.7-2.3 s after the pre-hit fired, the
 * damage rate about twice the forecast's, source unread). From each `go` decision, the creep's real HP is sampled on later
 * scans beside the forecast HP at the same time (spread, without our hit), until it dies or WATCH_FOR passes; one
 * ev=prehit_fc then carries both series and what the forecast counted against what was attacking the creep at the decision.
 */
const WATCH_FOR = 2.5;
const WATCH_EVERY = 0.1;
const WATCH_SAMPLES = 20;
interface Watch {
    creep: Unit;
    f: Lib.Verbs.HpForecast;
    t: number;
    last: number;
    hs: string[];
    fs: string[];
    fields: [string, any][];
    /** GameTime at the decision, and each attacker's last attack time seen, for `fire`. */
    g0: number;
    lat: LuaTable<Unit, number>;
    fire: string[];
}
const WATCH_FIRES = 30;
const watches: Record<number, Watch | undefined> = {};

function startWatch(bot: Unit, verbs: typeof Lib.Verbs, tower: Unit, creep: Unit, f: Lib.Verbs.HpForecast, lo: number): void {
    const pid = bot.GetPlayerID();
    if (watches[pid] !== undefined) return;
    let kt = 0, kc = 0, kh = 0, ks = 0, td = -1;
    for (const h of f.hits) {
        if (h.t > 1) continue;
        if (h.by === "tower") { kt++; td = h.damage; } else if (h.by === "creep") kc++; else if (h.by === "hero") kh++; else ks++;
    }
    let ac = 0, ah = 0;
    for (const c of bot.GetNearbyLaneCreeps(1600, false) ?? []) if (c.GetAttackTarget() === creep) ac++;
    for (const h of bot.GetNearbyHeroes(1600, false, 0) ?? []) if (h !== bot && h.GetAttackTarget() === creep) ah++;
    const tw = creep.GetActualIncomingDamage(tower.GetAttackDamage(), DamageType.Physical);
    watches[pid] = {
        creep, f, t: DotaTime(), last: -1, hs: [], fs: [], g0: GameTime(), lat: new LuaTable(), fire: [],
        fields: [
            ["pid", pid],
            ["hp", math.floor(f.hp)],
            ["lo", math.floor(lo)],
            ["tw", math.floor(tw)],
            ["td", math.floor(td)],
            ["twp", math.floor(((tower as unknown as Lib.TaskUnit).GetSecondsPerAttack?.() ?? -1) * 100) / 100],
            ["kt", kt], ["kc", kc], ["kh", kh], ["ks", ks],
            ["nu", f.unphasedHits.length],
            ["ud", math.floor(f.unphased)],
            ["ac", ac],
            ["ah", ah],
        ],
    };
    sampleWatch(bot, verbs);
}

function sampleWatch(bot: Unit, verbs: typeof Lib.Verbs): void {
    const pid = bot.GetPlayerID();
    const w = watches[pid];
    if (w === undefined) return;
    const dt = DotaTime() - w.t;
    // A removed creep's handle is invalid; IsAlive on it raises (prhfc3 game B t=117.967, the laning task failed every scan after).
    const alive = !w.creep.IsNull() && w.creep.IsAlive();
    if (alive && dt < WATCH_FOR && w.hs.length < WATCH_SAMPLES) {
        noteFires(bot, w);
        if (dt - w.last < WATCH_EVERY) return;
        w.last = dt;
        const r = math.floor(dt * 100) / 100;
        w.hs.push(`${r}:${math.floor(w.creep.GetHealth())}`);
        w.fs.push(`${math.floor(verbs.forecastHp(w.f, dt))}`);
        return;
    }
    watches[pid] = undefined;
    Telemetry.Event("prehit_fc", [
        ...(w.fields as any),
        ["end", math.floor(dt * 100) / 100],
        ["dead", !alive],
        ["fdies", forecastDeath(verbs, w.f)],
        ["hs", w.hs.join(",")],
        ["fs", w.fs.join(",")],
        ["fire", w.fire.join(",")],
    ]);
}

/**
 * Each attack fired at the watched creep since the decision, as `<kind>:<seconds>` (attack time, not landing): T own tower,
 * C own lane creep, S this bot, H another own hero, D enemy hero, E enemy creep, X enemy tower. Read from each attacker's
 * GetLastAttackTime while its attack target is the creep, so one aimed elsewhere when it fired is missed.
 */
function noteFires(bot: Unit, w: Watch): void {
    const note = (u: Unit, kind: string): void => {
        if (u.GetAttackTarget() !== w.creep) return;
        const at = u.GetLastAttackTime();
        const before = w.lat.get(u);
        w.lat.set(u, at);
        if (at > w.g0 && (before === undefined || at > before) && w.fire.length < WATCH_FIRES) {
            w.fire.push(`${kind}:${math.floor((at - w.g0) * 100) / 100}`);
        }
    };
    note(bot, "S");
    for (const u of bot.GetNearbyTowers(1600, false) ?? []) note(u, "T");
    for (const u of bot.GetNearbyTowers(1600, true) ?? []) note(u, "X");
    for (const u of bot.GetNearbyLaneCreeps(1600, false) ?? []) note(u, "C");
    for (const u of bot.GetNearbyLaneCreeps(1600, true) ?? []) note(u, "E");
    for (const u of bot.GetNearbyHeroes(1600, false, 0) ?? []) if (u !== bot) note(u, "H");
    for (const u of bot.GetNearbyHeroes(1600, true, 0) ?? []) note(u, "D");
}

function forecastDeath(verbs: typeof Lib.Verbs, f: Lib.Verbs.HpForecast): number {
    for (let t = 0; t <= HORIZON; t += STEP) if (verbs.forecastHp(f, t) <= 0) return math.floor(t * 100) / 100;
    return -1;
}
