/**
 * Which lane creep a laner goes for next, from the engine's `laneTargets` facts. Moved from the engine's old
 * `nextLastHit` (slice 5a) unchanged: priority ranged last hit > ranged deny > melee last hit > melee deny, as eta
 * biases, so a melee creep due now still beats a ranged one due much later. Biases are `judgement`. A creep that will
 * be dead before the bot can walk into range and swing is skipped (slice 5).
 */
import type * as Lib from "bots/FunLib/engine/tasks";

/** Seconds of eta a ranged or siege creep is preferred by (more gold and XP). */
export const RANGED_BIAS = 0.4;
/** Seconds of eta a last hit is preferred over a deny by (a core never gives up its last hit to deny). */
export const LAST_HIT_BIAS = 0.3;
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
        const key = t.eta - (t.ranged ? RANGED_BIAS : 0) - (t.kind === "lasthit" ? LAST_HIT_BIAS : 0);
        if (key < bestKey) {
            bestKey = key;
            best = t;
        }
    }
    return best;
}

/**
 * What the laning body last did about last hits, per player, for the snapshot's `lf` field (slice 5, missed-bar step 1:
 * creeps dying in the core's range with no attempt near them had no cause in the log). Telemetry only.
 */
interface Scan {
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
