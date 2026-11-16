/**
 * Ours.PreHit (slice pre-hit, `docs/team/slices/pre-hit.md` in the master repo): a core hits an enemy lane creep our tower is
 * attacking so that the tower then leaves it in the core's kill range. Under a tower the one-swing `lastHit` verb cannot win a
 * creep whose HP steps from above our hit to below zero in one tower hit. On each scan the core plans its next few swings
 * against the tower's known landing times (`Plan`): which of them to spend as pre-hits so that one lands on the creep inside
 * the kill range (0, low roll], choosing the plan most likely to land its kill in range under the forecast's fitted error
 * (`ERROR`; slice prehit-odds, 17/11/2026: the forecast misses creeps joining, so the real HP runs a median 23 below it at 1-2 s
 * ahead and passes through the range before our next attack is ready), counting every landing from when our attack is ready
 * (`killFrom`), then the one whose kill HP sits furthest from both edges (prhchk2-5, 04/11/2026). The plan is remade every scan from the creep's real HP, so a hit the forecast missed
 * changes the next decision rather than the result. The swing is laneFarm's `prehit` (one `attackAndConfirm`); the kill is the
 * normal last-hit pick's and verb's. A pre-hit never spends the swing a last hit on another creep needs: none may come due
 * before our attack is ready again (user 04/11/2026). While the tower's current target leaves our swing free, the same plan
 * runs on the creep the tower will take next (`NextTarget`, `NextTowerHits`; slice prehit-next, 17/11/2026), so the pre-hit
 * can land before the tower's first hit on it.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

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
/**
 * Forecast for the tower's predicted next target (slice prehit-next): its tower hits start only once the current target
 * dies, about 1-2 s out, and a creep takes four or more tower hits, so the plan needs longer than HORIZON. `judgement`.
 */
export const NEXT_HORIZON = 6;
/** Seconds from the current target's death to the tower's attack on the next leaving (acquiring and its wind-up). `judgement`. */
export const NEXT_TURN = 0.1;
/** Tower attack projectile speed when the read fails (Dota towers: 750). */
const TOWER_PROJECTILE = 750;

/** A plan of our swings on one creep: when each lands (seconds from now), the last one the kill. */
export interface Plan {
    swings: number[];
    /** The creep's forecast HP as the kill lands, before our hit. */
    hpKill: number;
    /** How far `hpKill` sits from the kill range's edges: min(hpKill, lo - hpKill), negative above the range. */
    margin: number;
    /** The chance the creep's real HP is in range at a landing once our kill swing is ready (`killFrom`, `ERROR`). */
    odds: number;
}

/**
 * The forecast's error on a creep our tower is hitting: real HP below the forecast's, our own hits removed, at a time ahead
 * (`ev=prehit_fc`, 353 probes from h2hhighstand1 and rig tower-prehit on1, 17/11/2026; `fitted`). It is 0 in about 40% of
 * samples and 20-120 HP in most of the rest: our creeps join that the forecast, which counts current attackers, cannot see;
 * the negative tail is a forecast tower hit landing late. One row per half second ahead (the last for 2 s and beyond): the
 * error at the probabilities `ERROR_P`.
 */
export const ERROR_P = [0.02, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.98];
export const ERROR: number[][] = [
    [-80, -12, -1, 0, 0, 0, 2, 7, 17, 64, 107],
    [-75, -41, -1, 1, 4, 9, 25, 49, 72, 90, 133],
    [-78, -3, 1, 4, 7, 18, 28, 41, 65, 87, 133],
    [-72, -3, 2, 5, 10, 21, 34, 50, 64, 92, 173],
    [-72, -1, 3, 6, 11, 26, 40, 61, 84, 110, 176],
];
/** HP beyond the table's end points over which the chance runs out to 0 and to 1. `judgement`. */
const ERROR_TAIL = 20;

/** The chance the forecast's error at `t` seconds ahead is at most `x` HP: P(real HP >= forecast - x). */
export type ErrorCdf = (this: void, t: number, x: number) => number;

export const FittedError: ErrorCdf = (t: number, x: number): number => {
    const row = ERROR[math.min(ERROR.length - 1, math.max(0, math.floor(t / 0.5)))];
    const n = row.length;
    if (x < row[0] - ERROR_TAIL) return 0;
    if (x < row[0]) return (ERROR_P[0] * (x - (row[0] - ERROR_TAIL))) / ERROR_TAIL;
    if (x >= row[n - 1] + ERROR_TAIL) return 1;
    if (x >= row[n - 1]) return ERROR_P[n - 1] + ((1 - ERROR_P[n - 1]) * (x - row[n - 1])) / ERROR_TAIL;
    let i = 0;
    while (i + 1 < n && row[i + 1] <= x) i++;
    const span = row[i + 1] - row[i];
    return ERROR_P[i] + ((ERROR_P[i + 1] - ERROR_P[i]) * (x - row[i])) / span;
};

/** No error: the forecast is the creep's HP (the planner before odds). A kill on exactly lo counts, on exactly 0 does not. */
export const NoError: ErrorCdf = (_t: number, x: number): number => (x > 0 ? 1 : 0);

function better(a: Plan, b: Plan | undefined): boolean {
    if (b === undefined) return true;
    if (math.abs(a.odds - b.odds) > 1e-9) return a.odds > b.odds;
    if (a.margin !== b.margin) return a.margin > b.margin;
    if (a.swings.length !== b.swings.length) return a.swings.length < b.swings.length;
    return a.swings[a.swings.length - 1] < b.swings[b.swings.length - 1];
}

/** Where a swing may land from `earliest`: then, unless a tower hit falls in the AFTER before it, and just after each later tower hit. */
function landings(towers: number[], earliest: number): number[] {
    const out: number[] = [];
    let clear = true;
    for (const t of towers) if (t > earliest - AFTER && t <= earliest) clear = false;
    if (clear) out.push(earliest);
    for (const t of towers) if (t + AFTER > earliest) out.push(t + AFTER);
    return out;
}

/**
 * The kill from an attack ready at `earliest`, with `dealt` HP of ours in the forecast. The last-hit verb swings on the creep's
 * real HP whenever a hit kills, so the kill is won if the real HP is in (0, lo] at any landing from `earliest` on, and lost to
 * the tower if it passes through the range before then: the chance sums, over those landings, the chance the forecast's error
 * puts the HP there in range (the ranges a tower hit apart do not overlap: its hit is over lo). The plan's kill swing is the
 * likeliest landing.
 */
function killFrom(
    hpAt: (this: void, t: number) => number,
    horizon: number,
    towers: number[],
    earliest: number,
    dealt: number,
    lo: number,
    err: ErrorCdf,
): Plan | undefined {
    let odds = 0;
    let best: Plan | undefined;
    for (const at of landings(towers, earliest)) {
        if (at > horizon) break;
        const hp = hpAt(at) - dealt;
        const p = err(at, hp) - err(at, hp - lo);
        if (p <= 0) continue;
        odds += p;
        const here: Plan = { swings: [at], hpKill: hp, margin: math.min(hp, lo - hp), odds: p };
        if (better(here, best)) best = here;
    }
    if (best === undefined) return undefined;
    best.odds = math.min(1, odds);
    return best;
}

/**
 * The best plan from a swing that can land at `earliest` with `dealt` HP of ours already in the forecast and `pre` pre-hits
 * spent: the kill from there (`killFrom`), or, where the forecast HP is above lo, a pre-hit of `mean` damage at one of the
 * landings followed by the best plan from one attack cycle later.
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
    err: ErrorCdf,
): Plan | undefined {
    let best = killFrom(hpAt, horizon, towers, earliest, dealt, lo, err);
    if (pre >= MAX_PREHITS) return best;
    for (const at of landings(towers, earliest)) {
        if (at > horizon) break;
        const hp = hpAt(at) - dealt;
        if (hp > lo) {
            const rest = search(hpAt, horizon, towers, at + period, dealt + mean, pre + 1, period, lo, mean, err);
            if (rest !== undefined) {
                const plan: Plan = { swings: [at, ...rest.swings], hpKill: rest.hpKill, margin: rest.margin, odds: rest.odds };
                if (better(plan, best)) best = plan;
            }
        }
    }
    return best;
}

/**
 * The plan for a creep whose forecast HP without our hits is `hpAt` and whose tower hits land at `towers` (seconds from now,
 * sorted): our first swing can land at `first` (the walk plus our hit time) and every `period` after one, our low-roll damage
 * after armour is `lo` (the kill range's top, as the last-hit verb's `mine`) and our mean damage `mean` (what a pre-hit takes);
 * `err` the forecast's error (default the fitted one). Undefined when no plan within the horizon has a chance of a kill.
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
    err: ErrorCdf = FittedError,
): Plan | undefined {
    return search(hpAt, horizon, towers, first, 0, 0, period, lo, mean, err);
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
    /** The creep is the tower's predicted next target, not its current one. */
    next?: boolean;
}

/**
 * The tower's next target once `current` dies, as read now: the enemy lane creep in its reach nearest the tower, other than
 * `current` (the hypothesis ev=tower_pick grades; the published rule could not be read, 17/11/2026). `creeps` the enemy lane
 * creeps near; `reach` the tower's attack range plus its radius.
 */
export function NextTarget(this: void, tower: Unit, current: Unit | undefined, creeps: Unit[], reach: number): Unit | undefined {
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const c of creeps) {
        if (c === current || c.IsNull() || !c.IsAlive()) continue;
        const d = GetUnitToUnitDistance(tower, c);
        if (d <= reach + (c.GetBoundingRadius() ?? 0) && d < bestD) {
            best = c;
            bestD = d;
        }
    }
    return best;
}

/**
 * When the tower's hits land on its next target (seconds from now, up to `horizon`): its current target dies at `dies`; its
 * last hit on it landed at `last` (undefined if none before the death) after `travelCur` s of flight; the next is `travelNext`
 * away in flight. The tower fires on the next once its attack is ready (`period` after the last fired) and not before the
 * death plus NEXT_TURN, then every `period`.
 */
export function NextTowerHits(
    this: void,
    dies: number,
    last: number | undefined,
    travelCur: number,
    travelNext: number,
    period: number,
    horizon: number,
): number[] {
    let fire = dies + NEXT_TURN;
    if (last !== undefined) fire = math.max(fire, last - travelCur + period);
    const out: number[] = [];
    for (let t = fire + travelNext; t <= horizon; t += period) out.push(t);
    return out;
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
    const hpAt = (t: number): number => verbs.forecastHp(f, t);
    return decide(bot, me, verbs, tower, target, walk, f, hpAt, towers, HORIZON, false);
}

/**
 * The verdict on the tower's predicted next target (`NextTarget`) while it is still on `current`: the current one's forecast
 * gives its death and the tower's last hit on it, `NextTowerHits` the tower's hits on the next from then, added to the next
 * creep's own forecast (its current attackers, no tower).
 */
function considerNext(bot: Unit, me: Lib.TaskUnit, verbs: typeof Lib.Verbs, tower: Unit, current: Unit, next: Unit): [Note | undefined, Lib.Verbs.LaneTarget | undefined] {
    if (current.IsNull() || !current.IsAlive() || next.IsNull() || !next.IsAlive()) return [undefined, undefined];
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const walk = math.max(0, GetUnitToUnitDistance(bot, next) - bot.GetAttackRange()) / speed;
    if (walk > LanePick.MAX_WALK) return [{ verdict: "far", next: true }, undefined];
    const cur = current as unknown as Lib.TaskCreep;
    const fc = verbs.hpForecast(me, cur, NEXT_HORIZON);
    if (fc.unphasedTower) return [{ verdict: "phase", next: true }, undefined];
    let dies: number | undefined;
    for (let t = 0; t <= NEXT_HORIZON && dies === undefined; t += STEP) if (verbs.forecastHp(fc, t) <= 0) dies = t;
    if (dies === undefined) return [{ verdict: "none", next: true }, undefined];
    let last: number | undefined;
    for (const h of fc.hits) if (h.by === "tower" && h.t <= dies + STEP) last = last === undefined ? h.t : math.max(last, h.t);
    const tu = tower as unknown as Lib.TaskUnit;
    const read = tu.GetSecondsPerAttack?.();
    const tperiod = read !== undefined && read > 0 ? read : 1;
    const ps = tu.GetAttackProjectileSpeed?.();
    const pspeed = ps !== undefined && ps > 0 ? ps : TOWER_PROJECTILE;
    const towers = NextTowerHits(dies, last, GetUnitToUnitDistance(tower, current) / pspeed, GetUnitToUnitDistance(tower, next) / pspeed, tperiod, NEXT_HORIZON);
    const creep = next as unknown as Lib.TaskCreep;
    const f = verbs.hpForecast(me, creep, NEXT_HORIZON);
    // Another of our towers on it already: the current-target path reads it.
    for (const h of f.hits) if (h.by === "tower") return [undefined, undefined];
    const tw = next.GetActualIncomingDamage(tower.GetAttackDamage(), DamageType.Physical);
    const hpAt = (t: number): number => {
        let n = 0;
        for (const h of towers) if (h <= t) n++;
        return verbs.forecastHp(f, t) - tw * n;
    };
    return decide(bot, me, verbs, tower, next, walk, f, hpAt, towers, NEXT_HORIZON, true);
}

/** The plan on `target` and its verdict; on `go` the pre-hit and the probe's watch. */
function decide(
    bot: Unit,
    me: Lib.TaskUnit,
    verbs: typeof Lib.Verbs,
    tower: Unit,
    target: Unit,
    walk: number,
    f: Lib.Verbs.HpForecast,
    hpAt: (this: void, t: number) => number,
    towers: number[],
    horizon: number,
    next: boolean,
): [Note | undefined, Lib.Verbs.LaneTarget | undefined] {
    const creep = target as unknown as Lib.TaskCreep;
    const first = walk + verbs.ownHitTime(me, creep);
    const read = me.GetSecondsPerAttack?.();
    const period = read !== undefined && read > 0 ? read : WorldFacts.Fallback("attack_period", 1.7);
    const variance = me.GetBaseDamageVariance?.() ?? 0;
    const lo = target.GetActualIncomingDamage(bot.GetAttackDamage() - variance, DamageType.Physical);
    const mean = target.GetActualIncomingDamage(bot.GetAttackDamage(), DamageType.Physical);
    const plan = Plan(hpAt, horizon, towers, first, period, lo, mean);
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
    const note: Note = { verdict, creep, hp: f.hp, t0: first, lo, plan, next: next ? true : undefined };
    if (verdict !== "go") return [note, undefined];
    startWatch(bot, verbs, tower, target, f, lo, next);
    let dies = math.huge;
    for (let t = 0; t <= horizon && dies === math.huge; t += STEP) if (hpAt(t) <= 0) dies = t;
    return [note, { creep, kind: "prehit", eta: walk, due: 0, walk, dies, ranged: LanePick.IsRanged(creep) }];
}

/**
 * The pre-hit this core would make now, as a `prehit` LaneTarget, or undefined. Candidates: enemy lane creeps an own tower is
 * attacking, within a MAX_WALK walk, then each tower's predicted next target. `verbs` is the engine bundle's Verbs
 * (hpForecast, forecastHp, ownHitTime, laneTargets).
 */
export function Find(bot: Unit, verbs: typeof Lib.Verbs): Lib.Verbs.LaneTarget | undefined {
    if (!Applies(bot)) return undefined;
    const pid = bot.GetPlayerID();
    const me = bot as unknown as Lib.TaskUnit;
    let best: Lib.Verbs.LaneTarget | undefined;
    let note: Note | undefined;
    const towersNear = bot.GetNearbyTowers(TOWER_RADIUS, false) ?? [];
    for (const tower of towersNear) {
        const target = tower.GetAttackTarget();
        if (best === undefined && target !== undefined && target !== null) {
            const [n, pre] = consider(bot, me, verbs, tower, target);
            // A far creep's verdict never hides a nearer one's.
            if (n !== undefined && (note === undefined || n.verdict !== "far")) note = n;
            best = pre;
        }
    }
    // The tower's next target, while its current one leaves our swing free: no pre-hit, kill or planned kill on it.
    const creeps = bot.GetNearbyLaneCreeps(1600, true) ?? [];
    const free = best === undefined && (note === undefined || (note.verdict !== "go" && note.verdict !== "kills" && note.verdict !== "wait" && note.verdict !== "lh"));
    for (const tower of towersNear) {
        const target = tower.GetAttackTarget();
        const current = target !== undefined && target !== null && !target.IsNull() && target.IsAlive() && target.IsCreep() && target.GetTeam() !== bot.GetTeam() ? target : undefined;
        const next = current !== undefined ? NextTarget(tower, current, creeps, WorldFacts.TowerReach(tower, 788)) : undefined;
        notePick(tower, current, next, creeps);
        if (free && best === undefined && current !== undefined && next !== undefined) {
            const [n, pre] = considerNext(bot, me, verbs, tower, current, next);
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
 * The next-target read's probe (ev=tower_pick): per own tower, its creep target and the creep `NextTarget` predicted on the
 * last scan; when the tower's target moves from one enemy creep to another, one line grades the prediction and says where
 * the taken creep stood. Shared by every core scanning the tower (one module table per team), so one line per switch.
 */
interface PickState {
    target: Unit;
    predicted?: Unit;
    /** DotaTime the tower was last seen on `target`. */
    at: number;
}
const picks = new LuaTable<Unit, PickState>();
/** A switch counts when the old target was seen this recently (scans skipped, a frame on no target). `judgement`. */
const PICK_GAP = 1;

function notePick(tower: Unit, current: Unit | undefined, next: Unit | undefined, creeps: Unit[]): void {
    const prev = picks.get(tower);
    // An idle tower, or one on a hero: kept; a creep taken more than PICK_GAP later was not chosen after one.
    if (current === undefined) return;
    if (prev !== undefined && prev.target !== current && DotaTime() - prev.at <= PICK_GAP) {
        const reach = WorldFacts.TowerReach(tower, 788);
        const d = GetUnitToUnitDistance(tower, current);
        let rank = 1, n = 0, dn = math.huge, natk = 0;
        for (const c of creeps) {
            if (c.IsNull() || !c.IsAlive()) continue;
            const dc = GetUnitToUnitDistance(tower, c);
            if (dc > reach + (c.GetBoundingRadius() ?? 0)) continue;
            n++;
            if (c !== current && dc < d) rank++;
            if (dc < dn) dn = dc;
            if (c.GetAttackTarget() === tower) natk++;
        }
        const ct = current.GetAttackTarget();
        Telemetry.Event("tower_pick", [
            ["ok", prev.predicted === current],
            ["rank", rank],
            ["n", n],
            ["d", math.floor(d)],
            ["dn", dn === math.huge ? -1 : math.floor(dn)],
            ["atk", ct === tower],
            ["atkh", ct !== undefined && ct !== null && !ct.IsNull() && ct.IsHero()],
            ["natk", natk],
            ["rg", LanePick.IsRanged(current as unknown as Lib.TaskCreep)],
            ["prev", !prev.target.IsNull() && prev.target.IsAlive()],
        ]);
    }
    picks.set(tower, { target: current, predicted: next, at: DotaTime() });
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

function startWatch(bot: Unit, verbs: typeof Lib.Verbs, tower: Unit, creep: Unit, f: Lib.Verbs.HpForecast, lo: number, next: boolean): void {
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
            ["nx", next ? true : undefined],
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
