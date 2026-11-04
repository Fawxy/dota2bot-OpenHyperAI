/**
 * Ours.PreHit (slice pre-hit, `docs/team/slices/pre-hit.md` in the master repo): a core hits an enemy lane creep our tower is
 * attacking so that the tower then leaves it in the core's kill range. Under a tower the one-swing `lastHit` verb cannot win a
 * creep whose HP steps from above our hit to below zero in one tower hit. On each scan the core plans its next few swings
 * against the tower's known landing times (`Plan`): which of them to spend as pre-hits so that one lands on the creep inside
 * the kill range (0, low roll], choosing the plan whose kill HP sits furthest from both edges of that range (prhchk2-5, 04/11/2026:
 * one hit aimed at any window at all landed the kill on 2-15 HP, which one high roll or one creep hit undid; two hits aimed at
 * the middle of the range leave about 25). The plan is remade every scan from the creep's real HP, so a hit the forecast missed
 * changes the next decision rather than the result. The swing is laneFarm's `prehit` (one `attackAndConfirm`); the kill is the
 * normal last-hit pick's and verb's. A pre-hit never spends the swing a last hit on another creep needs: none may come due
 * before our attack is ready again (user 04/11/2026).
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** Seconds of forecast: two pre-hits and the kill (about 0.7 s to the first landing, then two attack cycles of 1.4-1.7 s). `judgement`. */
export const HORIZON = 4.5;
/** Forecast sampling step in seconds, for the forecast's own death time. */
export const STEP = 0.05;
/**
 * Seconds after a tower's hit lands that our own may land and count as after it: the verb relies on a hit one server tick
 * before its own, plus a frame of slack for the timing it still gets wrong. `judgement`.
 */
export const AFTER = 0.1;
/** The most pre-hits one plan spends before its kill: a third would reach past the horizon at early attack speeds. `judgement`. */
export const MAX_PREHITS = 2;
/** Own towers within this of the bot are read for their attack target (tower range 700 plus the reach of a short walk). */
const TOWER_RADIUS = 1200;

/** A plan of our swings on one creep: when each lands (seconds from now), the last one the kill. */
export interface Plan {
    swings: number[];
    /** The creep's HP as the kill lands, before our hit. */
    hpKill: number;
    /** How far `hpKill` sits from the kill range's edges: min(hpKill, lo - hpKill). Higher survives more forecast error. */
    margin: number;
}

function better(a: Plan, b: Plan | undefined): boolean {
    if (b === undefined) return true;
    if (a.margin !== b.margin) return a.margin > b.margin;
    if (a.swings.length !== b.swings.length) return a.swings.length < b.swings.length;
    return a.swings[a.swings.length - 1] < b.swings[b.swings.length - 1];
}

/**
 * The best plan from a swing that can land at `earliest` with `dealt` HP of ours already in the forecast and `pre` pre-hits
 * spent. A swing lands at `earliest` or just after a later tower hit (`AFTER`); landing where a tower hit falls inside the last
 * AFTER before it is not relied on. On the creep's HP there (`hpAt` is the forecast without our hits) it is the kill when inside
 * (0, lo], else a pre-hit of `mean` damage followed by the best plan from one attack cycle later.
 */
function search(
    hpAt: (this: void, t: number) => number,
    horizon: number,
    towers: number[],
    earliest: number,
    dealt: number,
    pre: number,
    period: number,
    lo: number,
    mean: number,
): Plan | undefined {
    const candidates: number[] = [];
    let clear = true;
    for (const t of towers) if (t > earliest - AFTER && t <= earliest) clear = false;
    if (clear) candidates.push(earliest);
    for (const t of towers) if (t + AFTER > earliest) candidates.push(t + AFTER);
    let best: Plan | undefined;
    for (const at of candidates) {
        if (at > horizon) break;
        const hp = hpAt(at) - dealt;
        if (hp <= 0) continue;
        let plan: Plan | undefined;
        if (hp <= lo) plan = { swings: [at], hpKill: hp, margin: math.min(hp, lo - hp) };
        else if (pre < MAX_PREHITS) {
            const rest = search(hpAt, horizon, towers, at + period, dealt + mean, pre + 1, period, lo, mean);
            if (rest !== undefined) plan = { swings: [at, ...rest.swings], hpKill: rest.hpKill, margin: rest.margin };
        }
        if (plan !== undefined && better(plan, best)) best = plan;
    }
    return best;
}

/**
 * The plan for a creep whose forecast HP without our hits is `hpAt` and whose tower hits land at `towers` (seconds from now,
 * sorted): our first swing can land at `first` (the walk plus our hit time) and every `period` after one, our low-roll damage
 * after armour is `lo` (the kill range's top, as the last-hit verb's `mine`) and our mean damage `mean` (what a pre-hit takes).
 * Undefined when no plan within the horizon ends in a kill.
 */
export function Plan(
    this: void,
    hpAt: (this: void, t: number) => number,
    horizon: number,
    towers: number[],
    first: number,
    period: number,
    lo: number,
    mean: number,
): Plan | undefined {
    return search(hpAt, horizon, towers, first, 0, 0, period, lo, mean);
}

/**
 * Why a pre-hit was or was not chosen, for the snapshot's `lf` (`pr=`): `go` a pre-hit now; `kills` the
 * plan's first swing is the kill now (the last-hit verb's); `wait` the plan's first swing comes after a later tower hit (remade
 * then); `none` no plan ends in a kill; `lh` a last hit on another creep comes due before our attack is ready again; `phase` the
 * tower's hit times unknown; `far` beyond the pick's walk.
 */
export type Verdict = "go" | "kills" | "wait" | "none" | "lh" | "phase" | "far";

export function Applies(bot: Unit): boolean {
    return Ours.On("PreHit") && CoreLastHit.Applies(bot);
}

interface Note {
    verdict: Verdict;
    creep?: Lib.TaskCreep;
    hp?: number;
    t0?: number;
    lo?: number;
    plan?: Plan;
}
const notes: Record<number, Note | undefined> = {};

/** The decision's numbers for the ev=prehit of the pre-hit on `creep`, if it was this bot's last one. */
export function NoteOf(pid: number, creep: Lib.TaskCreep): Note | undefined {
    const n = notes[pid];
    return n !== undefined && n.creep === creep ? n : undefined;
}

/**
 * The verdict on one tower's target and, on `go`, the pre-hit. A function with early returns rather than a loop body with
 * `continue`: TSTL's Lua 5.1 `continue` (a `repeat ... until true` block) put a statement after the loop's `break`, which LuaJIT
 * (Dota) refuses to compile, so the module and everything requiring it failed to load in game (prhchk1, 04/11/2026).
 */
function consider(bot: Unit, me: Lib.TaskUnit, verbs: typeof Lib.Verbs, tower: Unit, target: Unit): [Note | undefined, Lib.Verbs.LaneTarget | undefined] {
    // A removed unit's handle raises on IsAlive (prhfc3 game B); the tower's target is read fresh each look but guarded the same.
    if (target.IsNull() || !target.IsAlive() || target.GetTeam() === bot.GetTeam() || !target.IsCreep() || target.IsHero()) return [undefined, undefined];
    const creep = target as unknown as Lib.TaskCreep;
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const walk = math.max(0, GetUnitToUnitDistance(bot, target) - bot.GetAttackRange()) / speed;
    if (walk > LanePick.MAX_WALK) return [{ verdict: "far" }, undefined];
    const f = verbs.hpForecast(me, creep, HORIZON);
    if (f.unphasedTower) return [{ verdict: "phase", creep }, undefined];
    const towers: number[] = [];
    for (const h of f.hits) if (h.by === "tower") towers.push(h.t);
    const first = walk + verbs.ownHitTime(me, creep);
    const period = me.GetSecondsPerAttack?.() ?? 1.7;
    const variance = me.GetBaseDamageVariance?.() ?? 0;
    const lo = target.GetActualIncomingDamage(bot.GetAttackDamage() - variance, DamageType.Physical);
    const mean = target.GetActualIncomingDamage(bot.GetAttackDamage(), DamageType.Physical);
    const hpAt = (t: number): number => verbs.forecastHp(f, t);
    const plan = Plan(hpAt, HORIZON, towers, first, period, lo, mean);
    let verdict: Verdict;
    if (plan === undefined) verdict = "none";
    else if (plan.swings[0] > first + 1e-6) verdict = "wait";
    else if (plan.swings.length === 1) verdict = "kills";
    else verdict = "go";
    if (verdict === "go") {
        // Our attack is busy until first + period: a last hit on another creep due before then would be lost to it.
        for (const o of verbs.laneTargets(me, { within: first + period, deny: false })) {
            if (o.creep !== creep && LanePick.Reachable(o) && o.eta <= first + period) verdict = "lh";
        }
    }
    const note: Note = { verdict, creep, hp: f.hp, t0: first, lo, plan };
    if (verdict !== "go") return [note, undefined];
    startWatch(bot, verbs, tower, target, f, lo);
    let dies = math.huge;
    for (let t = 0; t <= HORIZON && dies === math.huge; t += STEP) if (hpAt(t) <= 0) dies = t;
    return [note, { creep, kind: "prehit", eta: walk, due: 0, walk, dies, ranged: LanePick.IsRanged(creep) }];
}

/**
 * The pre-hit this core would make now, as a `prehit` LaneTarget, or undefined. Candidates: enemy lane creeps an own tower is
 * attacking, within a MAX_WALK walk. `verbs` is the engine bundle's Verbs (hpForecast, ownHitTime, laneTargets).
 */
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
