/**
 * The threat read (design docs/proposals/2026-11-09-fights-and-retreat.md s5.1-5.2, slice threat): what could hurt `bot` on
 * the walk from `from` to `place` within `horizon` seconds, as named inputs and one number. The read never decides: each
 * consumer applies its own rule to the inputs (the gates share one, `Gate`: a visible hero in reach, else the belief's weight
 * sum); `threat` and `band` are logged for the budget slices to come. One table of weights, all `judgement` unless a row in
 * docs/team/slices/threat.md says otherwise.
 */
import { DamageType, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

export const SETTINGS = {
    /** An unseen enemy counts in the belief only after this many seconds unseen (the old MissingAfter, kept so the graded rows hold). */
    MissingAfter: 3,
    /** Fallback speed (units/s) for an unseen hero never seen moving; a seen hero's last read GetCurrentMovementSpeed is used. */
    MissingSpeed: 330,
    /** Cap on an unseen hero's run since its sighting, and the margin added to it (the old MissingReachMax and ThreatMargin). */
    MissingReachMax: 4000,
    MissingMargin: 600,
    /**
     * Belief weight of one unseen hero whose run touches the walk, before EarlyUntil and after (fitted, 20 games 1161-1243:
     * precision of a counted hero 0.22 before 4:00 and 0.55 after; no other prior separated, slice file "Priors graded").
     */
    EarlyWeight: 0.2,
    LateWeight: 0.5,
    EarlyUntil: 240,
    /**
     * Place prior (graded at the camp alone on the banked logs, slice file "Place prior"): a counted hero's weight is scaled by
     * the place's depth, its distance to the nearest live enemy tower over the sum of that and the distance to our nearest
     * (0 at our tower, 1 at theirs). A counted hero arrived at a deep place (the offlane hard camp, depth under 0.5) 0.21 of
     * the time, at a mid place (our stack camps, 0.5-0.65) 0.03 and on our side (the safe lane's pull camps, over 0.65)
     * 0.01. Steps as [upper depth edge, factor]; the sizes are fitted to those rates (three camp classes). The depth reads the
     * lanes' T1s while one of each team's stands (the offline fit's tower set), else every standing tower.
     */
    DepthFactor: [[0.5, 1], [0.65, 0.25], [1.01, 0.1]] as [number, number][],
    /** The depth with no standing tower on one side to read (judgement: the middle bucket's edge). */
    DepthDefault: 0.5,
    /** And by the hero's last-seen distance to the place (deep camp: arrived 0.32 within 1,200, 0.19 to 2,000, 0.10 to 3,000). */
    DistFactor: [[2000, 1], [3000, 0.5], [math.huge, 0.25]] as [number, number][],
    /** The horizon (s) the gates read with; 4 s puts a 300-speed melee's reach (run plus attack range and hulls) at about the
     *  old HeroReach plus ThreatMargin (1,400). judgement. */
    GateHorizon: 4,
    /** The weight sum that holds a gate: one hero after 4:00 at a deep place (0.5), three before; picked on the 425 graded rows
     *  (slice file threat.md): refusals 312 to 264, precision 0.53 to 0.58. */
    MissingRefuse: 0.5,
    /**
     * Vision cut (drill thrdr1: a hero last seen by the walk counts forever once it leaves unseen, 8 of 12 holds false): an
     * unseen hero counts only while some point of the walk within its run is out of our sight (IsLocationVisible), since
     * an empty visible stretch says it is not there. Points every WalkStep along the walk, and the place. judgement.
     */
    VisionCut: true,
    WalkStep: 300,
    /** The window `burst` sums the enemies' estimated damage over (s): the horizon, capped here. */
    BurstWindow: 3,
    /** Fallback tower reach (attack range plus radius) when the tower gives no read. */
    TowerReach: 868,
    /** threat = clamp01(sum of weight x input). */
    WReach: 0.25,
    WMissing: 0.3,
    WTower: 0.4,
    WBurst: 0.5,
    WAlly: 0.15,
    /** Band edges on `threat`; `lethal` is not a weight (see Read). */
    Watch: 0.25,
    Pressured: 0.5,
    /** One ev=threat line per hero and consumer at most this often (s), unless the consumer's decision changes. */
    LogEvery: 5,
};

export type Band = "none" | "watch" | "pressured" | "lethal";

export interface Read {
    t: number;
    from: Vector;
    place: Vector;
    horizon: number;
    /** The place's depth between the teams' live towers: 0 at ours, 1 at theirs (DepthFactor). */
    depth: number;
    /** Visible enemy heroes who can be in attack range of the walk within `horizon`. */
    reach: number[];
    /** Their estimated damage on `bot` over min(horizon, BurstWindow), as a share of its current HP. */
    burst: number;
    /** Our other heroes who can reach `place` within `horizon`. */
    allies: number;
    /** `place` inside a live enemy tower's reach. */
    tower: boolean;
    /** Sum of the belief weights of unseen enemies whose possible run touches the walk, their pids and the longest unseen (s). */
    missing: number;
    mpids: number[];
    mtss?: number;
    /** Unseen heroes whose run touches the walk but whose reachable part of it is all in our sight (VisionCut). */
    mcut: number;
    threat: number;
    band: Band;
}

const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];
const MAX_PLAYER_ID = 23;

let speeds: Record<number, number> = {};
let logged: Record<string, { t: number; decision: string }> = {};

export function ResetCache(): void {
    speeds = {};
    logged = {};
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) ** 2 + (a.y - b.y) ** 2);
}

function distToSegment(p: Vector, a: Vector, b: Vector): number {
    const vx = b.x - a.x;
    const vy = b.y - a.y;
    const len2 = vx * vx + vy * vy;
    const u = len2 > 0 ? math.max(0, math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)) : 0;
    return math.sqrt((p.x - (a.x + u * vx)) ** 2 + (p.y - (a.y + u * vy)) ** 2);
}

function valid(u: Unit | undefined | null): u is Unit {
    return u !== null && u !== undefined && u.IsAlive() && !u.IsIllusion();
}

/** Can `u` be in attack range of a point on the walk within `horizon`: its run plus its attack range and both hulls. */
function canReach(u: Unit, bot: Unit, from: Vector, place: Vector, horizon: number): boolean {
    const at = u.GetLocation();
    if (at === null || at === undefined) return false;
    const run = u.GetCurrentMovementSpeed() * horizon + u.GetAttackRange() + u.GetBoundingRadius() + bot.GetBoundingRadius();
    return distToSegment(at, from, place) <= run;
}

const T1_IDS = [Tower.Top1, Tower.Mid1, Tower.Bot1];

function nearestOf(team: number, ids: Tower[], place: Vector): number | undefined {
    let best: number | undefined;
    for (const id of ids) {
        const tw = GetTower(team, id);
        if (!valid(tw)) continue;
        const d = dist(tw.GetLocation(), place);
        if (best === undefined || d < best) best = d;
    }
    return best;
}

/** The team's nearest standing T1 (the tower set the depth factors were fitted on), else its nearest standing tower. */
function nearestTower(team: number, place: Vector): number | undefined {
    return nearestOf(team, T1_IDS, place) ?? nearestOf(team, TOWER_IDS, place);
}

/** The place's depth: its distance to the nearest enemy tower over the sum with the distance to our nearest; DepthDefault with no read. */
function placeDepth(team: number, enemyTeam: number, place: Vector): number {
    const own = nearestTower(team, place);
    const en = nearestTower(enemyTeam, place);
    if (own === undefined || en === undefined || own + en <= 0) return SETTINGS.DepthDefault;
    return en / (own + en);
}

function stepFactor(steps: [number, number][], v: number): number {
    for (const [edge, f] of steps) if (v < edge) return f;
    return steps[steps.length - 1][1];
}

function inTowerReach(enemyTeam: number, place: Vector): boolean {
    for (const id of TOWER_IDS) {
        const tw = GetTower(enemyTeam, id);
        if (!valid(tw)) continue;
        if (dist(tw.GetLocation(), place) <= WorldFacts.TowerReach(tw, SETTINGS.TowerReach)) return true;
    }
    return false;
}

/**
 * The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
 * read speed, capped) plus MissingMargin; one whose run touches the walk adds EarlyWeight or LateWeight by game minute.
 * Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for a bot-only team). A hero the API has no sighting of is
 * not placed and not counted.
 */
function walkPoints(from: Vector, place: Vector): Vector[] {
    const d = dist(from, place);
    const n = math.max(1, math.ceil(d / SETTINGS.WalkStep));
    const out: Vector[] = [];
    for (let i = 0; i <= n; i++) out.push(Vector(from.x + ((place.x - from.x) * i) / n, from.y + ((place.y - from.y) * i) / n, place.z));
    return out;
}

/** Some walk point within `r` of `at` is out of our sight. */
function unseenWithin(points: Vector[], at: Vector, r: number): boolean {
    for (const p of points) if (dist(p, at) <= r && !IsLocationVisible(p)) return true;
    return false;
}

/**
 * The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
 * read speed, capped) plus MissingMargin; one whose run touches the walk, with some of that reach out of our sight
 * (VisionCut), adds EarlyWeight or LateWeight by game minute, scaled by the place prior (DepthFactor for the place's depth,
 * DistFactor for its last-seen distance to the place). Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for
 * a bot-only team). A hero the API has no sighting of is not placed and not counted.
 */
function missingOf(
    bot: Unit,
    from: Vector,
    place: Vector,
    depth: number,
    now: number,
    visible: Record<number, boolean>,
): LuaMultiReturn<[number, number[], number | undefined, number]> {
    const s = SETTINGS;
    const team = bot.GetTeam();
    const base = (now < s.EarlyUntil ? s.EarlyWeight : s.LateWeight) * stepFactor(s.DepthFactor, depth);
    let sum = 0;
    let cut = 0;
    let mtss: number | undefined;
    const pids: number[] = [];
    let points: Vector[] | undefined;
    for (let pid = 0; pid <= MAX_PLAYER_ID; pid++) {
        const t = GetTeamForPlayer(pid);
        if (t === team || (t !== Team.Radiant && t !== Team.Dire) || visible[pid] === true || !IsHeroAlive(pid)) continue;
        const info = GetHeroLastSeenInfo(pid)[0];
        if (info === undefined || info.time_since_seen <= s.MissingAfter) continue;
        const r = math.min((speeds[pid] ?? s.MissingSpeed) * info.time_since_seen, s.MissingReachMax) + s.MissingMargin;
        if (distToSegment(info.location, from, place) > r) continue;
        if (s.VisionCut) {
            points = points ?? walkPoints(from, place);
            if (!unseenWithin(points, info.location, r)) {
                cut++;
                continue;
            }
        }
        sum += base * stepFactor(s.DistFactor, dist(info.location, place));
        pids.push(pid);
        mtss = math.max(mtss ?? 0, info.time_since_seen);
    }
    return $multi(sum, pids, mtss, cut);
}

export function BandOf(threat: number, lethal: boolean): Band {
    if (lethal) return "lethal";
    return threat >= SETTINGS.Pressured ? "pressured" : threat >= SETTINGS.Watch ? "watch" : "none";
}

/**
 * The read for `bot` walking from `from` to `place` with `horizon` seconds ahead. `lethal` fires when the heroes in reach
 * can deal the bot's HP within the burst window and they outnumber our heroes in reach (the `escape` input is not built yet:
 * slice file Open items).
 */
export function Read(bot: Unit, from: Vector, place: Vector, horizon: number): Read {
    const s = SETTINGS;
    const now = DotaTime();
    const visible: Record<number, boolean> = {};
    const reach: number[] = [];
    let dmg = 0;
    const window = math.min(horizon, s.BurstWindow);
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!valid(e) || !e.CanBeSeen()) continue;
        const pid = e.GetPlayerID();
        visible[pid] = true;
        const sp = e.GetCurrentMovementSpeed();
        if (sp !== undefined && sp > 0) speeds[pid] = sp;
        if (canReach(e, bot, from, place, horizon)) {
            reach.push(pid);
            dmg += e.GetEstimatedDamageToTarget(true, bot, window, DamageType.All);
        }
    }
    let allies = 0;
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!valid(a) || a === bot) continue;
        if (canReach(a, bot, place, place, horizon)) allies++;
    }
    const enemyTeam = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    const depth = placeDepth(bot.GetTeam(), enemyTeam, place);
    const [missing, mpids, mtss, mcut] = missingOf(bot, from, place, depth, now, visible);
    const tower = inTowerReach(enemyTeam, place);
    const hp = math.max(1, bot.GetHealth());
    const burst = dmg / hp;
    const raw = s.WReach * reach.length + s.WMissing * missing + (tower ? s.WTower : 0) + s.WBurst * math.min(1, burst) - s.WAlly * allies;
    const threat = math.max(0, math.min(1, raw));
    const lethal = burst >= 1 && reach.length > allies;
    return { t: now, from, place, horizon, depth, reach, burst, allies, tower, missing, mpids, mtss, mcut, threat, band: BandOf(threat, lethal) };
}

/**
 * The gate rule the starts share (the core camp trip, the pos3's pull, the support's pull and stack, the farm trip, the pull farm): held
 * by a visible hero who can reach the walk within GateHorizon ("threat"), else by the belief's weight sum at MissingRefuse
 * ("missing"); the read and its decision are logged as ev=threat for `consumer`.
 */
export function Gate(bot: Unit, from: Vector, place: Vector, consumer: string): { why?: "threat" | "missing"; r: Read } {
    const r = Read(bot, from, place, SETTINGS.GateHorizon);
    const why = r.reach.length > 0 ? "threat" : r.missing >= SETTINGS.MissingRefuse ? "missing" : undefined;
    Log(bot, consumer, r, why ?? "go");
    return { why, r };
}

const r2 = (x: number): number => math.floor(x * 100 + 0.5) / 100;

/**
 * ev=threat for one consumer's decision on a read: on a changed decision, else at most once per LogEvery per hero and
 * consumer (gates run every think; the design's "once per decision" would flood).
 */
export function Log(bot: Unit, consumer: string, r: Read, decision: string): void {
    const pid = bot.GetPlayerID();
    const key = `${pid}:${consumer}`;
    const last = logged[key];
    if (last !== undefined && last.decision === decision && r.t - last.t < SETTINGS.LogEvery) return;
    logged[key] = { t: r.t, decision };
    Telemetry.Event("threat", [
        ["pid", pid],
        ["who", consumer],
        ["dec", decision],
        ["x", math.floor(r.place.x)],
        ["y", math.floor(r.place.y)],
        ["hz", r2(r.horizon)],
        ["dep", r2(r.depth)],
        ["threat", r2(r.threat)],
        ["band", r.band],
        ["reach", r.reach.length],
        ["rpid", r.reach.length > 0 ? r.reach.join(",") : undefined],
        ["burst", r2(r.burst)],
        ["ally", r.allies],
        ["tower", r.tower],
        ["miss", r2(r.missing)],
        ["mpid", r.mpids.length > 0 ? r.mpids.join(",") : undefined],
        ["mtss", r.mtss !== undefined ? math.floor(r.mtss + 0.5) : undefined],
        ["mcut", r.mcut > 0 ? r.mcut : undefined],
        ["hp", r2(bot.GetHealth() / math.max(1, bot.GetMaxHealth()))],
    ]);
}
