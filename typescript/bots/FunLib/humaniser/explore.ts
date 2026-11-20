/**
 * Explore roll (experiment, `Ours.ExploreRoll`): a hero our retreat owns draws a multiplier on its safe-read kill bar when it first
 * stands in a fight band, holds it until it has been out of the band for `Release` s or dies, and logs `ev=roll`, so the bar can be
 * fitted from the outcome that follows each roll instead of from batches of games. `SafeGather.FromRead` passes `Mult` to `Safe.Decide`,
 * so every consumer of the read sees the same scaled bar.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";
import * as Safe from "bots/FunLib/humaniser/safe";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /** The draw is uniform over these; the effective pressed bar (1.25) spans 0.6 to 2.2 of HP / kill. */
    Mults: [0.5, 0.75, 1.0, 1.35, 1.75],
    /** In band: an enemy hero reaches the hero's own place and HP / kill is under this. */
    BandHi: 2.0,
    /** A roll ends after this many seconds out of the band. */
    Release: 8,
};

interface Roll {
    mult: number;
    start: number;
    lastInBand: number;
}

const rolls: Record<number, Roll | undefined> = {};

const r2 = (v: number): number => math.floor(v * 100 + 0.5) / 100;

function end(pid: number, why: string, now: number): void {
    const x = rolls[pid];
    if (x === undefined) return;
    rolls[pid] = undefined;
    Telemetry.Event("roll", [["ph", "end"], ["pid", pid], ["mult", x.mult], ["secs", r2(now - x.start)], ["why", why]]);
}

/**
 * Whether a held roll has run out. A running retreat keeps it alive: the leave read (`Observe`) is not asked during an episode, so without
 * this a roll ended partway through the walk it caused and the hero drew again on its return (smoke: 13 of 45 ends, the high multipliers
 * re-rolling in 4 s against 24 to 39 s).
 */
function stale(bot: Unit, x: Roll, now: number): boolean {
    if (RetreatState.Running(bot)) {
        x.lastInBand = now;
        return false;
    }
    return now - x.lastInBand >= SETTINGS.Release;
}

/** A roll is held for `bot` (a drawn 1.0 included). */
export function Held(bot: Unit): boolean {
    return Ours.On("ExploreRoll") && rolls[bot.GetPlayerID()] !== undefined;
}

/** The multiplier on `bot`'s kill bar: its held roll, else 1 (switch off, no roll). A roll not refreshed for `Release` s ends here too, for a hero that stopped being read. */
export function Mult(bot: Unit): number {
    if (!Ours.On("ExploreRoll")) return 1;
    const pid = bot.GetPlayerID();
    const x = rolls[pid];
    if (x === undefined) return 1;
    const now = DotaTime();
    if (stale(bot, x, now)) {
        end(pid, "out", now);
        return 1;
    }
    return x.mult;
}

/** The hero's own-place read (`leave`) is in the band: someone reaches it and HP / kill is under `BandHi`. */
export function InBand(a: Safe.Answer): boolean {
    return a.reachers > 0 && a.kill > 0 && a.ratio < SETTINGS.BandHi;
}

/**
 * Watches the hero's own-place answer. Starts a roll on the first in-band read when none is held, refreshes a held one, ends it after
 * `Release` s out of band. Returns true when a roll started on this read: `a` was made unrolled, so the caller asks again.
 */
export function Observe(bot: Unit, a: Safe.Answer): boolean {
    if (!Ours.On("ExploreRoll") || !RetreatState.Owns(bot)) return false;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const x = rolls[pid];
    if (!InBand(a)) {
        if (x !== undefined && stale(bot, x, now)) end(pid, "out", now);
        return false;
    }
    if (x !== undefined) {
        x.lastInBand = now;
        return false;
    }
    const n = SETTINGS.Mults.length;
    const u = LaneConfig.Draw() ?? RandomFloat(0, 1);
    const mult = SETTINGS.Mults[math.min(n - 1, math.floor(u * n))];
    rolls[pid] = { mult, start: now, lastInBand: now };
    const hpa = bot.GetHealth();
    Telemetry.Event("roll", [
        ["ph", "start"], ["pid", pid], ["mult", mult], ["ratio", r2(a.ratio)], ["kill", math.floor(a.kill + 0.5)],
        ["hp", r2(hpa / math.max(1, bot.GetMaxHealth()))], ["hpa", math.floor(hpa + 0.5)], ["pressed", a.pressed],
        ["reach", a.reachers], ["bar", r2(a.bar)], ["base", a.ratio < a.bar],
    ]);
    return true;
}

/** The hero died: its roll ends. */
export function Died(bot: Unit): void {
    end(bot.GetPlayerID(), "died", DotaTime());
}

export function ResetCache(): void {
    for (const k of Object.keys(rolls)) delete rolls[k as unknown as number];
}

export const _test = { rolls };
