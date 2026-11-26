/**
 * The lane camp's state, a read the pull and the stack rows are passed (`Reads.camp`, hum/reads.ts; ARCHITECTURE rule 3: a row
 * does not import another row). It holds what this side knows of the lane's pull camp: the look at its box (`CampStateOf`), the
 * record of its strength while it is out of sight (`NoteSighting`, `NoteStack`, `Hold`, `Known`), the gate on what a look shows
 * (`CampGate`), and who pulls it (`IsPuller`, `SpawnerFor`). It decides nothing. The record is stored knowledge and lasts; a
 * look at the game is kept for the frame it was asked in.
 */
import * as GameRules from "bots/FunLib/humaniser/game_rules";
import { Lane, Unit, UnitType } from "bots/ts_libs/dota";
import * as Camps from "bots/FunLib/humaniser/camps";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";

// All `judgement` (slice file, Decisions), except where a source is named.
export const SETTINGS = {
    /** The bar (families proposal s5, named 24/11/2026): a pull is started only into a camp of at least this many neutrals on
     *  the hero's record. From the banked pull rigs' diverted pulls, creeps dead within 1,000 of the camp by neutrals met:
     *  3 met 13 of 61, 4 met 4 of 36, 5 met 7 of 8, 6 or more 137 of 140. */
    StrongAt: 6,
    /** Neutrals the spawn rule adds to an empty camp while it is out of sight (`judgement`: a camp's set varies by kind,
     *  2 to 4; the next sighting corrects it). */
    SetSize: { small: 3, medium: 3, large: 3, ancient: 3 } as Record<Camps.CampType, number>,
};

/** What the API returns in the camp's box: `n` neutrals, `seen` of them `CanBeSeen`, `hp` their health, `vis` the camp's
 *  origin visible to our team (its neutrals stand there; the box corners plus margin were never all visible in pc1). */
export interface CampState {
    n: number;
    seen: number;
    hp: number;
    vis: boolean;
    /** The counted box's four corners are in sight (telemetry `cfv` only: in drills they never all read visible, ldr11). */
    full?: boolean;
    /** The neutrals returned, for the damage estimate. */
    units: Unit[];
    /** At a decision: the camp's expected damage on the puller (CampDamage) and the puller's HP. */
    dmg?: number;
    php?: number;
    /** At a decision: the nearest enemy hero to the stand point or the meet point (siteThreat). */
    se?: number;
    /** At a decision: the camp as the hero's record knows it (Known). */
    known?: CampKnown;
}

export interface CampKnown {
    n: number;
    src: "seen" | "rules";
    /** Seconds since the last sighting that set the record. */
    age: number;
    /** Of `n`, the neutrals last seen whose handles still read alive; the rest the rules added. */
    held: number;
}

/**
 * What this hero knows of a camp's strength while it is out of sight (families proposal s5: the trigger reads about 10 s
 * before the slot with the camp fogged, `cn` 0 in every pullchain1 slot). A sighting is a fact and replaces the record; in
 * between it moves only by the game's rules. The count is the neutrals last seen whose handles still read alive (one that
 * dies in fog drops out if the API reports it; if not, the record stays high until the next sighting) plus the neutrals the
 * spawn rules added since.
 */
interface CampRecord {
    units: Unit[];
    added: number;
    /** The last sighting that set the record, and whether the rules have added since (`src` on the lines). */
    seenAt: number;
    src: "seen" | "rules";
    /** The last minute mark the spawn rule was applied to. */
    minute: number;
    /** A stack holds the record (Hold): no look counts the camp until then. */
    heldUntil?: number;
}

/** By camp idx: this hero's record of each camp (CampRecord). */
const records: Record<number, CampRecord | undefined> = {};

/** By camp idx: the look `CampStateOf` took in the frame `t`. */
const looks: Record<number, { t: number; s: CampState } | undefined> = {};

export function ResetCache(): void {
    for (const t of [records, looks] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

function isSupport(u: Unit): boolean {
    const pos = LaneConfig.PositionOf(u);
    return pos === 4 || pos === 5;
}

/** The support that pulls for `bot`'s lane: pos5 when both supports share it. */
function pullerOfLane(bot: Unit): boolean {
    if (LaneConfig.PositionOf(bot) === 5) return true;
    const lane = bot.GetAssignedLane();
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === undefined || m === null || m === bot) continue;
        if (LaneConfig.PositionOf(m) === 5 && m.GetAssignedLane() === lane) return false;
    }
    return true;
}

/** The lane's first pull camp; with `Overrides.PullCamp` (a rig's camp type, e.g. `large` for the hard camp) the first of that type. */
export function CampFor(bot: Unit): Camps.CampJobData | undefined {
    const lane = bot.GetAssignedLane();
    if (lane !== Lane.Top && lane !== Lane.Bot) return undefined;
    const camps = Camps.PullCampsFor(bot.GetTeam(), lane);
    const kind = Overrides.Get("PullCamp");
    if (typeof kind === "string" && kind !== "") return camps.find((c) => c.type === kind);
    return camps[0];
}

/** The hero that would pull for its lane, whatever the switches say. */
export function IsPuller(bot: Unit): boolean {
    return bot.IsBot() && TripTable.Does("pull", LaneConfig.PositionOf(bot)) && isSupport(bot) && pullerOfLane(bot) && CampFor(bot) !== undefined;
}

/** The spawner of the lane's pull camp (the pull's and the stack row's camp). */
export function SpawnerFor(bot: Unit): Camps.Spawner | undefined {
    const camp = CampFor(bot);
    return camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
}

function scan(spawner: Camps.Spawner): CampState {
    const m = LaneConfig.Settings().Radii.BoxMargin;
    const lo = spawner.min;
    const hi = spawner.max;
    const z = spawner.location.z;
    // The corners of the box as counted (BoxMargin beyond it, review 2026-11-08-lane-drills L5).
    const [x0, y0, x1, y1] = [lo.x - m, lo.y - m, hi.x + m, hi.y + m];
    const full = IsLocationVisible(Vector(x0, y0, z)) && IsLocationVisible(Vector(x1, y0, z)) && IsLocationVisible(Vector(x0, y1, z)) && IsLocationVisible(Vector(x1, y1, z));
    const s: CampState = { n: 0, seen: 0, hp: 0, vis: IsLocationVisible(spawner.location), full, units: [] };
    for (const u of GetUnitList(UnitType.NeutralCreeps)) {
        if (!u.IsAlive()) continue;
        const p = u.GetLocation();
        if (p === undefined || p === null) continue;
        if (p.x < lo.x - m || p.x > hi.x + m || p.y < lo.y - m || p.y > hi.y + m) continue;
        s.n++;
        if (u.CanBeSeen()) s.seen++;
        s.hp += u.GetHealth();
        s.units.push(u);
    }
    return s;
}

/**
 * The look at the camp's box now. It scans the neutral list, and the pull asks it more than once in a frame (its `wants` for
 * the record and again for the decision, and its first step after the start), so the scan is kept for the frame. Callers write
 * the decision's fields onto what they get, so each gets its own copy.
 */
export function CampStateOf(spawner: Camps.Spawner): CampState {
    const now = DotaTime();
    let k = looks[spawner.idx];
    if (k === undefined || k.t !== now) {
        k = { t: now, s: scan(spawner) };
        looks[spawner.idx] = k;
    }
    return { ...k.s, units: [...k.s.units] };
}

/** A camp's neutrals within this of its origin, seen alive, stay on the record through a sighting of the box: a stack's
 *  pulled set walks back over :00 and stands outside the counted box (`judgement`, the pull's TagRadius). */
const RECORD_LEASH = 1200;

function alive(u: Unit): boolean {
    return !u.IsNull() && u.IsAlive();
}

function recordCount(r: CampRecord): number {
    let n = r.added;
    for (const u of r.units) if (alive(u)) n++;
    return n;
}

/**
 * The spawn rule since the record's last minute: at each mark an empty camp gets a set, a camp holding neutrals gets nothing
 * (leftovers block the spawn: pullchain1, Dire 7:00). A stack's set is the stack row's to add (NoteSet), since the record
 * cannot tell a pulled-out camp from one in its box.
 */
function advance(r: CampRecord, type: Camps.CampType, now: number): void {
    const m = math.floor(now / GameRules.NEUTRAL_EVERY);
    while (r.minute < m) {
        r.minute++;
        if (r.minute * GameRules.NEUTRAL_EVERY >= GameRules.NEUTRAL_FIRST && recordCount(r) === 0) {
            r.added += SETTINGS.SetSize[type];
            r.src = "rules";
        }
    }
}

function recordOf(spawner: Camps.Spawner, now: number): CampRecord {
    let r = records[spawner.idx];
    if (r === undefined) {
        // Before the first spawn the camp is empty, and the rule fills it at the first mark.
        r = { units: [], added: 0, seenAt: now, src: "rules", minute: math.floor(now / GameRules.NEUTRAL_EVERY) };
        if (now >= GameRules.NEUTRAL_FIRST) r.added = SETTINGS.SetSize[spawner.type];
        records[spawner.idx] = r;
    }
    advance(r, spawner.type, now);
    return r;
}

/**
 * A look at the camp (`s`, CampStateOf now). A full view (the box's corners in sight, or `close`: one of ours stands at the
 * camp, since the corners never all read visible in the drills, ldr11) replaces the record; a partial one only raises it,
 * since a neutral out of view would drop a strong camp under the bar. An unseen origin says nothing (the API returns no
 * fogged neutrals).
 */
export function NoteSighting(spawner: Camps.Spawner, s: CampState, close: boolean): void {
    if (!s.vis) return;
    const now = DotaTime();
    const r = recordOf(spawner, now);
    if (r.heldUntil !== undefined && now < r.heldUntil) return;
    if (!(s.full === true || close) && s.n <= recordCount(r)) return;
    const units = [...s.units];
    for (const u of r.units) {
        if (!alive(u) || !u.CanBeSeen() || units.includes(u) || GetUnitToLocationDistance(u, spawner.location) > RECORD_LEASH) continue;
        units.push(u);
    }
    r.units = units;
    r.added = 0;
    r.seenAt = now;
    r.src = "seen";
}

/**
 * The stack row's read of its camp after the mark: the set it pulled out (`pulled`, the handles at its hit) and the spawn it
 * saw come in (`fresh`), or a set by the rules when the box was out of sight (`fresh` undefined). It replaces the record:
 * the row held it through the stack (Hold), since no look at the box counts a pulled-out set.
 */
export function NoteStack(spawner: Camps.Spawner, pulled: Unit[], fresh: number | undefined): void {
    const now = DotaTime();
    const r = recordOf(spawner, now);
    r.units = pulled.filter((u) => alive(u));
    r.added = fresh ?? SETTINGS.SetSize[spawner.type];
    r.src = fresh !== undefined ? "seen" : "rules";
    if (fresh !== undefined) r.seenAt = now;
    r.heldUntil = undefined;
}

/** No look updates the record until `until` (or NoteStack): a stack is pulling the camp out of its box. */
export function Hold(spawner: Camps.Spawner, until: number): void {
    recordOf(spawner, DotaTime()).heldUntil = until;
}

/** The camp's strength as this hero knows it now (CampRecord). */
export function Known(spawner: Camps.Spawner): CampKnown {
    const now = DotaTime();
    const r = recordOf(spawner, now);
    const n = recordCount(r);
    return { n, src: r.src, age: math.floor((now - r.seenAt) * 10) / 10, held: n - r.added };
}

/** The camp holds at least the bar's neutrals (SETTINGS.StrongAt) on this hero's record. */
export function Strong(spawner: Camps.Spawner): boolean {
    return Known(spawner).n >= SETTINGS.StrongAt;
}

/**
 * `empty` when the camp holds nothing to pull at `hitAt`: nothing returned while the team sees the camp's origin, and no
 * spawn minute before the hit (a camp respawns only on the minute, so it stays empty). An empty box out of sight says
 * nothing: the API returns no fogged neutrals (pc1: every one returned was `CanBeSeen`). `one` the same with a single
 * neutral left: too little to hold a wave (banked `ok` pulls with one neutral seen at the start diverted 26 of 56, two or
 * more 243 of 385; user 04/11/2026: skip it). Stacking it instead is the stack job's call, not this one's.
 */
export function CampGate(s: CampState, now: number, hitAt: number): string | undefined {
    if (!ReadsHit(s, now, hitAt)) return undefined;
    if (s.n === 0) return "empty";
    if (s.n === 1) return "one";
    return undefined;
}

/** What the team sees of the camp now holds at the hit: the origin is in sight and no spawn mark comes before the hit. */
export function ReadsHit(s: CampState, now: number, hitAt: number): boolean {
    const period = LaneConfig.Settings().Timing.PullPeriod;
    return s.vis && math.floor(hitAt / period) <= math.floor(now / period);
}
