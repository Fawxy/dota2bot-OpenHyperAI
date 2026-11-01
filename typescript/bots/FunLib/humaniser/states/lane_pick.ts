/**
 * Which lane creep a laner goes for next, from the engine's `laneTargets` facts. Strict priority (slice l1-lane-priority, user
 * rule 01/11/2026): any reachable last hit beats every deny; denies are taken only when no last hit is offered. Within a kind
 * the earliest eta wins, a ranged or siege creep counting as RANGED_BIAS sooner, so a melee creep due now still beats a ranged
 * one due much later. Bias is `judgement`. A creep that will be dead before the bot can walk into range and swing is skipped
 * (slice 5).
 */
import type * as Lib from "bots/FunLib/engine/tasks";

/** Seconds of eta a ranged or siege creep is preferred by (more gold and XP). */
export const RANGED_BIAS = 0.4;
/** Added to a deny's key so any last hit sorts before it. */
const DENY_OFFSET = 1000;
/**
 * Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
 * A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
 * were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
 */
export const ARRIVE_SLACK = 0.45;

export function Choose(this: void, targets: Lib.Verbs.LaneTarget[]): Lib.Verbs.LaneTarget | undefined {
    let best: Lib.Verbs.LaneTarget | undefined;
    let bestKey = Infinity;
    for (const t of targets) {
        if (t.walk > 0 && t.walk + ARRIVE_SLACK >= t.dies) continue;
        // A deny's key is pushed past any last hit's (eta is seconds, never near DENY_OFFSET), so denies win only alone.
        const key = t.eta - (t.ranged ? RANGED_BIAS : 0) + (t.kind === "lasthit" ? 0 : DENY_OFFSET);
        if (key < bestKey) {
            bestKey = key;
            best = t;
        }
    }
    return best;
}

/** How many of `targets` are reachable last hits and reachable denies (the reach rule above), and how many last hits other than `except`. */
function countOffers(targets: Lib.Verbs.LaneTarget[], except?: Lib.Verbs.LaneTarget): LuaMultiReturn<[number, number, number]> {
    let lastHits = 0;
    let denies = 0;
    let otherLastHits = 0;
    for (const t of targets) {
        if (t.walk > 0 && t.walk + ARRIVE_SLACK >= t.dies) continue;
        if (t.kind === "lasthit") {
            lastHits++;
            if (except === undefined || t.creep !== except.creep) otherLastHits++;
        } else denies++;
    }
    return $multi(lastHits, denies, otherLastHits);
}

/** The engine's `laneTargets`, handed over by humaniser/tasks once the bundle is loaded; telemetry never loads the bundle itself. */
let offers: ((this: void, bot: Lib.TaskUnit) => Lib.Verbs.LaneTarget[]) | undefined;

export function SetOffers(fn: (this: void, bot: Lib.TaskUnit) => Lib.Verbs.LaneTarget[]): void {
    offers = fn;
}

/**
 * What the bot could take right now, whoever plays its laning (slice lane-activity, both arms): reachable last hits and denies,
 * as the laning body would be offered them. Reads facts only (no skill roll). Undefined while the bundle is not loaded.
 */
export function Options(bot: Lib.TaskUnit): LuaMultiReturn<[number | undefined, number | undefined]> {
    if (offers === undefined) return $multi(undefined, undefined);
    const [lastHits, denies] = countOffers(offers(bot));
    return $multi(lastHits, denies);
}

/**
 * What the laning body last did about last hits, per player, for the snapshot's `lf` field (slice 5, missed-bar step 1:
 * creeps dying in the core's range with no attempt near them had no cause in the log). Telemetry only.
 */
interface Scan {
    /** At the last pick: the creep chosen, reachable last hits and denies offered; `seen`, the most other last hits offered while the attempt waited. */
    chosen?: Lib.Verbs.LaneTarget;
    pickLastHits?: number;
    pickDenies?: number;
    seen?: number;
    /** A retarget's pick, held until the attempt it replaces has reported. */
    next?: { chosen: Lib.Verbs.LaneTarget; lastHits: number; denies: number };
    /** The body's phase label (walk, hold, lasthit, deny). */
    ph?: string;
    /** When the body last asked whether it may last-hit, and its distance to the spot then. */
    scanAt?: number;
    aw?: number;
    /** When it last chose among offered creeps: how many were offered, skipped as unreachable, and whether one was chosen. */
    pickAt?: number;
    n?: number;
    sk?: number;
    ch?: boolean;
}
const scans: Record<number, Scan> = {};

function scanOf(pid: number): Scan {
    let s = scans[pid];
    if (s === undefined) {
        s = {};
        scans[pid] = s;
    }
    return s;
}

export function NotePhase(pid: number, ph: string): void {
    scanOf(pid).ph = ph;
}

export function NoteScan(pid: number, now: number, aw: number | undefined): void {
    const s = scanOf(pid);
    s.scanAt = now;
    s.aw = aw;
}

export function NotePick(pid: number, now: number, targets: Lib.Verbs.LaneTarget[], chosen: Lib.Verbs.LaneTarget | undefined): void {
    const s = scanOf(pid);
    s.pickAt = now;
    s.n = targets.length;
    let sk = 0;
    for (const t of targets) if (t.walk > 0 && t.walk + ARRIVE_SLACK >= t.dies) sk++;
    s.sk = sk;
    s.ch = chosen !== undefined;
    if (chosen !== undefined) {
        const [lastHits, denies] = countOffers(targets);
        // A retarget picks while the old attempt has not reported yet: its offers must reach its own ev=lh, so the new ones wait.
        if (s.chosen !== undefined && (s.ph === "lasthit" || s.ph === "deny")) {
            s.next = { chosen, lastHits, denies };
        } else {
            s.next = undefined;
            s.chosen = chosen;
            s.pickLastHits = lastHits;
            s.pickDenies = denies;
            s.seen = 0;
        }
    }
}

/** While an attempt waits (the body's scan, every 0.1 s): the most last hits other than its creep on offer, so a deny's cost can be read. */
export function NoteWait(bot: Lib.TaskUnit): void {
    const s = scans[bot.GetPlayerID()];
    if (s === undefined || s.chosen === undefined || offers === undefined) return;
    if (s.ph !== "lasthit" && s.ph !== "deny") return;
    const [, , others] = countOffers(offers(bot), s.chosen);
    if (others > (s.seen ?? 0)) s.seen = others;
}

/**
 * ev=lh's offer fields for the attempt that just ended: last hits and denies offered at its pick, most other last hits seen during
 * it. Call once per attempt: it then moves on to the pick a retarget held back.
 */
export function AttemptOffers(pid: number): LuaMultiReturn<[number | undefined, number | undefined, number | undefined]> {
    const s = scans[pid];
    if (s === undefined) return $multi(undefined, undefined, undefined);
    const lastHits = s.pickLastHits;
    const denies = s.pickDenies;
    const seen = s.seen;
    if (s.next !== undefined) {
        s.chosen = s.next.chosen;
        s.pickLastHits = s.next.lastHits;
        s.pickDenies = s.next.denies;
        s.seen = 0;
        s.next = undefined;
    }
    return $multi(lastHits, denies, seen);
}

/** `ph=hold sc=0.1 aw=340 pk=2.3 n=2 sk=1 ch=0`: ages in s since the last scan and the last pick; undefined before any. */
export function Describe(pid: number, now: number): string | undefined {
    const s = scans[pid];
    if (s === undefined) return undefined;
    const age = (t: number | undefined): string => (t === undefined ? "-" : string.format("%.1f", now - t));
    return string.format(
        "ph=%s sc=%s aw=%s pk=%s n=%s sk=%s ch=%s",
        s.ph ?? "-",
        age(s.scanAt),
        s.aw === undefined ? "-" : tostring(math.floor(s.aw)),
        age(s.pickAt),
        tostring(s.n ?? "-"),
        tostring(s.sk ?? "-"),
        s.ch === undefined ? "-" : s.ch ? "1" : "0",
    );
}
