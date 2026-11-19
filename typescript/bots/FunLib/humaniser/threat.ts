/**
 * The threat read (design docs/proposals/2026-11-09-fights-and-retreat.md s5.1-5.2, slice threat): what could hurt `bot` on
 * the walk from `from` to `place` within `horizon` seconds, as named inputs and one number. The read never decides: each
 * consumer applies its own rule to the inputs (the gates share one, `Gate`: a visible hero in reach, else the belief's weight
 * sum); `threat` and `band` are logged for the budget slices to come. One table of weights, all `judgement` unless a row in
 * docs/team/slices/threat.md says otherwise.
 */
import { Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";

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
    /**
     * `escape` (slice retreat): items that count as a leave when ready (blink, force staff, a TP scroll), and the margin (units)
     * beyond a chaser's attack range plus both hulls that a faster bot needs to step out of reach first. judgement.
     */
    EscapeItems: ["item_blink", "item_force_staff", "item_tpscroll"],
    EscapeMargin: 100,
    /**
     * An enemy hero is engaged when it damaged us within this many seconds (`WasRecentlyDamagedByHero`): a read that passes
     * `opts.engagedWindow` counts its damage over that window instead of BurstWindow, since a hero hitting us now keeps hitting
     * for as long as we stand there. judgement.
     */
    EngagedRecent: 1,
    /**
     * The burst bar of one hero (D1's "their burst can kill me"; retreat's EvenBurst). Sustain's heal budget reads it. judgement.
     */
    StandBurst: 1,
    /**
     * The stay read (retreat's LeaveWhy, and the trade decision's "is it safe here?"): the horizon (s) of the read at our own place
     * and the window a hero already hitting us is counted over. The same two numbers for both so a trade never opens on a read
     * retreat would leave on. judgement; they were retreat's Horizon and EngagedWindow (reasons there).
     */
    StayHorizon: 2,
    StayEngaged: 6,
    /** One ev=threat line per hero and consumer at most this often (s), unless the consumer's decision changes. */
    LogEvery: 5,
};

export type Band = "none" | "watch" | "pressured" | "lethal";

/** One reaching hero as the read counted it: the damage it was given (over the engaged window when `eng`, else the burst window), where it stood and how far it reaches within the horizon (its run plus attack range and both hulls). */
export interface ReachRow {
    pid: number;
    dmg: number;
    eng: boolean;
    at: Vector;
    run: number;
}

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
    /** Our other heroes who can reach `place` within `horizon`; an ally in our retreat counts no help (slice retreat). */
    allies: number;
    /** `bot` can leave the reach of every hero in `reach` first: an escape item ready, or faster than each of them and
     *  outside each one's attack range (slice retreat; `lethal` needs it). */
    escape: boolean;
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
    /** With `opts.engagedWindow`: the reaching heroes that damaged us within EngagedRecent (`eng`) and whose attack target is us
     *  (`att`, logged to see whether the API answers for an enemy hero); both empty without the option. */
    eng: number[];
    att: number[];
    /** The reaching heroes in `reach` order, with the damage the read counted for each (safe_gather.ts reads these instead of asking SpellReady again). */
    rows: ReachRow[];
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

const T1_IDS = [Tower.Top1, Tower.Mid1, Tower.Bot1];

/** A team's standing towers among `ids`, in `ids` order. */
function standing(team: number, ids: Tower[]): Unit[] {
    const out: Unit[] = [];
    for (const id of ids) {
        const tw = GetTower(team, id);
        if (valid(tw)) out.push(tw);
    }
    return out;
}

function nearestOf(at: Vector[], place: Vector): number | undefined {
    let best: number | undefined;
    for (const a of at) {
        const d = dist(a, place);
        if (best === undefined || d < best) best = d;
    }
    return best;
}

function stepFactor(steps: [number, number][], v: number): number {
    for (const [edge, f] of steps) if (v < edge) return f;
    return steps[steps.length - 1][1];
}

/** The walk's points every WalkStep, and the place (the vision cut looks at each). */
export function WalkPoints(from: Vector, place: Vector): Vector[] {
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

function itemReady(bot: Unit, name: string): boolean {
    const slot = bot.FindItemSlot(name);
    // Slots 0-5 are the inventory; the backpack's items cannot be cast.
    if (slot < 0 || slot > 5) return false;
    const item = bot.GetItemInSlot(slot);
    return item !== null && item !== undefined && item.IsFullyCastable();
}

/** The last movement speed Read saw for an enemy hero (the missing belief's run uses it), or undefined. */
export function SeenSpeed(pid: number): number | undefined {
    return speeds[pid];
}

export function BandOf(threat: number, lethal: boolean): Band {
    if (lethal) return "lethal";
    return threat >= SETTINGS.Pressured ? "pressured" : threat >= SETTINGS.Watch ? "watch" : "none";
}

/** `engagedWindow`: seconds a reaching hero that is hitting us now is counted over (instead of the burst window). */
export interface ReadOpts {
    engagedWindow?: number;
    /** Seconds a reaching hero's damage is counted over; default min(horizon, BurstWindow). */
    window?: number;
    /** An unseen hero left out of `missing` (slice kill-chase: the chased target, whose place is the walk's end). */
    exclude?: number;
}

/** A hero as one set of reads sees it: where it is and how far it gets within the horizon (its run plus its attack range and both hulls). */
interface Seen {
    u: Unit;
    pid: number;
    at: Vector;
    run: number;
    /** Filled the first time the hero reaches a walk: whether it aims at us or hit us just now, and its damage over its window. */
    dmg?: number;
    att?: boolean;
    eng?: boolean;
}

/**
 * The reads for `bot` with `horizon` seconds ahead, as a function of the walk (`from` to `place`). What does not depend on the
 * walk (who is seen and where, the standing towers, the unseen heroes' sightings, an escape item) is read from the game once,
 * here, so a caller weighing several places in one frame (the lane spot) pays for the heroes and towers once. Use it within
 * the frame it was made in. `lethal` fires when the heroes in reach can deal the bot's HP within the burst window, they
 * outnumber our heroes in reach and the bot has no `escape`.
 *
 * The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
 * read speed, capped) plus MissingMargin; one whose run touches the walk, with some of that reach out of our sight
 * (VisionCut), adds EarlyWeight or LateWeight by game minute, scaled by the place prior (DepthFactor for the place's depth,
 * DistFactor for its last-seen distance to the place). Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for
 * a bot-only team). A hero the API has no sighting of is not placed and not counted.
 */
export function Reader(bot: Unit, horizon: number, opts?: ReadOpts): (this: void, from: Vector, place: Vector) => Read {
    const s = SETTINGS;
    const now = DotaTime();
    const team = bot.GetTeam();
    const enemyTeam = team === Team.Radiant ? Team.Dire : Team.Radiant;
    const hull = bot.GetBoundingRadius();
    const window = opts?.window ?? math.min(horizon, s.BurstWindow);
    const visible: Record<number, boolean> = {};
    const enemies: Seen[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!valid(e) || !e.CanBeSeen()) continue;
        const pid = e.GetPlayerID();
        visible[pid] = true;
        const sp = e.GetCurrentMovementSpeed();
        if (sp !== undefined && sp > 0) speeds[pid] = sp;
        const at = e.GetLocation();
        if (at === null || at === undefined) continue;
        enemies.push({ u: e, pid, at, run: sp * horizon + e.GetAttackRange() + e.GetBoundingRadius() + hull });
    }
    const allies: Seen[] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!valid(a) || a === bot || RetreatState.Running(a)) continue;
        const at = a.GetLocation();
        if (at === null || at === undefined) continue;
        allies.push({ u: a, pid: a.GetPlayerID(), at, run: a.GetCurrentMovementSpeed() * horizon + a.GetAttackRange() + a.GetBoundingRadius() + hull });
    }
    const enemyTowers = standing(enemyTeam, TOWER_IDS);
    const enemyTowerAt = enemyTowers.map((tw) => tw.GetLocation());
    const enemyTowerReach: (number | undefined)[] = [];
    // The depth reads a team's standing T1s (the tower set the depth factors were fitted on), else its standing towers.
    const depthAt = (t: number, all: Vector[] | undefined): Vector[] => {
        const t1 = standing(t, T1_IDS).map((tw) => tw.GetLocation());
        return t1.length > 0 ? t1 : (all ?? standing(t, TOWER_IDS).map((tw) => tw.GetLocation()));
    };
    const ownDepthAt = depthAt(team, undefined);
    const enemyDepthAt = depthAt(enemyTeam, enemyTowerAt);
    const unseen: { pid: number; at: Vector; tss: number; r: number }[] = [];
    for (let pid = 0; pid <= MAX_PLAYER_ID; pid++) {
        const t = GetTeamForPlayer(pid);
        if (t === team || (t !== Team.Radiant && t !== Team.Dire) || visible[pid] === true || !IsHeroAlive(pid)) continue;
        if (pid === opts?.exclude) continue;
        const info = GetHeroLastSeenInfo(pid)[0];
        if (info === undefined || info.time_since_seen <= s.MissingAfter) continue;
        unseen.push({ pid, at: info.location, tss: info.time_since_seen, r: math.min((speeds[pid] ?? s.MissingSpeed) * info.time_since_seen, s.MissingReachMax) + s.MissingMargin });
    }
    const early = now < s.EarlyUntil ? s.EarlyWeight : s.LateWeight;
    const hp = math.max(1, bot.GetHealth());
    let escapeItem: boolean | undefined;

    return (from, place) => {
        const reach: number[] = [];
        const chasers: Unit[] = [];
        const eng: number[] = [];
        const att: number[] = [];
        const rows: ReachRow[] = [];
        let dmg = 0;
        for (const e of enemies) {
            if (distToSegment(e.at, from, place) > e.run) continue;
            reach.push(e.pid);
            chasers.push(e.u);
            if (e.dmg === undefined) {
                let w = window;
                if (opts?.engagedWindow !== undefined) {
                    e.att = e.u.GetAttackTarget() === bot;
                    e.eng = bot.WasRecentlyDamagedByHero(e.u, s.EngagedRecent);
                    if (e.eng) w = opts.engagedWindow;
                }
                e.dmg = SpellReady.DamageOn(e.u, bot, w);
            }
            if (e.att === true) att.push(e.pid);
            if (e.eng === true) eng.push(e.pid);
            rows.push({ pid: e.pid, dmg: e.dmg, eng: e.eng === true, at: e.at, run: e.run });
            dmg += e.dmg;
        }
        let near = 0;
        for (const a of allies) if (distToSegment(a.at, place, place) <= a.run) near++;

        const own = nearestOf(ownDepthAt, place);
        const en = nearestOf(enemyDepthAt, place);
        const depth = own === undefined || en === undefined || own + en <= 0 ? s.DepthDefault : en / (own + en);

        const base = early * stepFactor(s.DepthFactor, depth);
        let missing = 0;
        let mcut = 0;
        let mtss: number | undefined;
        const mpids: number[] = [];
        let points: Vector[] | undefined;
        for (const m of unseen) {
            if (distToSegment(m.at, from, place) > m.r) continue;
            if (s.VisionCut) {
                points = points ?? WalkPoints(from, place);
                if (!unseenWithin(points, m.at, m.r)) {
                    mcut++;
                    continue;
                }
            }
            missing += base * stepFactor(s.DistFactor, dist(m.at, place));
            mpids.push(m.pid);
            mtss = math.max(mtss ?? 0, m.tss);
        }

        let tower = false;
        for (let i = 0; i < enemyTowers.length && !tower; i++) {
            let r = enemyTowerReach[i];
            if (r === undefined) {
                r = WorldFacts.TowerReach(enemyTowers[i], s.TowerReach);
                enemyTowerReach[i] = r;
            }
            tower = dist(enemyTowerAt[i], place) <= r;
        }

        // Can `bot` leave the chasers' reach first (design 5.1): an escape item ready, or faster than each and out of its attack range.
        let escape = true;
        if (chasers.length > 0) {
            if (escapeItem === undefined) {
                escapeItem = false;
                for (const name of s.EscapeItems) if (itemReady(bot, name)) escapeItem = true;
            }
            if (!escapeItem) {
                const ours = bot.GetCurrentMovementSpeed();
                for (const e of chasers) {
                    if (e.GetCurrentMovementSpeed() >= ours || GetUnitToUnitDistance(bot, e) - e.GetAttackRange() - e.GetBoundingRadius() - hull < s.EscapeMargin) {
                        escape = false;
                        break;
                    }
                }
            }
        }

        const burst = dmg / hp;
        const raw = s.WReach * reach.length + s.WMissing * missing + (tower ? s.WTower : 0) + s.WBurst * math.min(1, burst) - s.WAlly * near;
        const threat = math.max(0, math.min(1, raw));
        const lethal = burst >= 1 && reach.length > near && !escape;
        return { t: now, from, place, horizon, depth, reach, burst, allies: near, escape, tower, missing, mpids, mtss, mcut, threat, band: BandOf(threat, lethal), eng, att, rows };
    };
}

/** One read: `bot` walking from `from` to `place` with `horizon` seconds ahead (see Reader). */
export function Read(bot: Unit, from: Vector, place: Vector, horizon: number, opts?: ReadOpts): Read {
    return Reader(bot, horizon, opts)(from, place);
}

let gateCut: ((this: void, bot: Unit, from: Vector, place: Vector, consumer: string) => void) | undefined;

/** The gate's fixture cut for one logged gate decision (safe_gather.ts `TripGate` calls it after `Log`). A fault in the cut is swallowed. */
export function NoteGateCut(bot: Unit, from: Vector, place: Vector, consumer: string): void {
    if (gateCut !== undefined) pcall(gateCut, bot, from, place, consumer);
}

/** cut.ts registers the gate's fixture cut here (it imports this module, so the module cannot import it); called after each logged gate decision. */
export function SetGateCut(fn: (this: void, bot: Unit, from: Vector, place: Vector, consumer: string) => void): void {
    gateCut = fn;
}

const r2 = (x: number): number => math.floor(x * 100 + 0.5) / 100;

/**
 * ev=threat for one consumer's decision on a read: on a changed decision, else at most once per LogEvery per hero and
 * consumer (gates run every think; the design's "once per decision" would flood). Returns whether it logged.
 */
export function Log(bot: Unit, consumer: string, r: Read, decision: string): boolean {
    const pid = bot.GetPlayerID();
    const key = `${pid}:${consumer}`;
    const last = logged[key];
    if (last !== undefined && last.decision === decision && r.t - last.t < SETTINGS.LogEvery) return false;
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
        ["esc", r.reach.length > 0 ? r.escape : undefined],
        ["tower", r.tower],
        ["miss", r2(r.missing)],
        ["mpid", r.mpids.length > 0 ? r.mpids.join(",") : undefined],
        ["mtss", r.mtss !== undefined ? math.floor(r.mtss + 0.5) : undefined],
        ["mcut", r.mcut > 0 ? r.mcut : undefined],
        ["hp", r2(bot.GetHealth() / math.max(1, bot.GetMaxHealth()))],
    ]);
    return true;
}
