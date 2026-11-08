/**
 * The threat read (design docs/proposals/2026-11-09-fights-and-retreat.md s5.1-5.2, slice threat): what could hurt `bot` on
 * the walk from `from` to `place` within `horizon` seconds, as named inputs and one number. The read never decides: each
 * consumer applies its own rule to the inputs (slice 1's gates read `reach` and `missing`); `threat` and `band` are logged
 * for the budget slices to come. One table of weights, all `judgement` unless a row in docs/team/slices/threat.md says otherwise.
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
function missingOf(bot: Unit, from: Vector, place: Vector, now: number, visible: Record<number, boolean>): [number, number[], number | undefined] {
    const s = SETTINGS;
    const team = bot.GetTeam();
    const w = now < s.EarlyUntil ? s.EarlyWeight : s.LateWeight;
    let sum = 0;
    let mtss: number | undefined;
    const pids: number[] = [];
    for (let pid = 0; pid <= MAX_PLAYER_ID; pid++) {
        const t = GetTeamForPlayer(pid);
        if (t === team || (t !== Team.Radiant && t !== Team.Dire) || visible[pid] === true || !IsHeroAlive(pid)) continue;
        const info = GetHeroLastSeenInfo(pid)[0];
        if (info === undefined || info.time_since_seen <= s.MissingAfter) continue;
        const run = math.min((speeds[pid] ?? s.MissingSpeed) * info.time_since_seen, s.MissingReachMax);
        if (distToSegment(info.location, from, place) <= run + s.MissingMargin) {
            sum += w;
            pids.push(pid);
            mtss = math.max(mtss ?? 0, info.time_since_seen);
        }
    }
    return [sum, pids, mtss];
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
    const [missing, mpids, mtss] = missingOf(bot, from, place, now, visible);
    const enemyTeam = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    const tower = inTowerReach(enemyTeam, place);
    const hp = math.max(1, bot.GetHealth());
    const burst = dmg / hp;
    const raw = s.WReach * reach.length + s.WMissing * missing + (tower ? s.WTower : 0) + s.WBurst * math.min(1, burst) - s.WAlly * allies;
    const threat = math.max(0, math.min(1, raw));
    const lethal = burst >= 1 && reach.length > allies;
    return { t: now, from, place, horizon, reach, burst, allies, tower, missing, mpids, mtss, threat, band: BandOf(threat, lethal) };
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
        ["hp", r2(bot.GetHealth() / math.max(1, bot.GetMaxHealth()))],
    ]);
}
