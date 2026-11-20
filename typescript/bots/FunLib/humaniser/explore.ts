/**
 * Explore roll (experiment, `Ours.ExploreRoll`): a hero our retreat owns draws a multiplier on its safe-read kill bar when it first
 * stands in a fight band, holds it until it has been out of the band for `Release` s or dies, and logs `ev=roll`, so the bar can be
 * fitted from the outcome that follows each roll instead of from batches of games. `SafeGather.FromRead` passes `Mult` to `Safe.Decide`,
 * so every consumer of the read sees the same scaled bar.
 */
import { BotMode, Unit } from "bots/ts_libs/dota";
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
    Telemetry.Event("roll", [["kind", "safe"], ["ph", "end"], ["pid", pid], ["mult", x.mult], ["secs", r2(now - x.start)], ["why", why]]);
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
        ["kind", "safe"], ["ph", "start"], ["pid", pid], ["mult", mult], ["ratio", r2(a.ratio)], ["kill", math.floor(a.kill + 0.5)],
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
    for (const k of Object.keys(blocks)) delete blocks[k as unknown as number];
}

export const TRADE = {
    /** The draw is uniform over these: a multiplier on the exchange's bars (`Trade.Decide`), higher is more willing to attack heroes. */
    Aggs: [0.5, 0.75, 1.0, 1.35, 1.75],
    /** Seconds a draw is held, counted from the hero's first laning frame. */
    Block: 45,
    /** The covariates' radii: heroes and a lane partner, and lane creeps. */
    NearHeroes: 1200,
    NearCreeps: 1000,
    SeeHeroes: 1600,
    /** A frame is worth at most this many seconds in the tally: a hero out of lane for a while adds nothing for the gap. */
    MaxDt: 1,
};

const LEVEL_FIELD: Record<string, string | undefined> = { none: "sn", hit: "sh", hitback: "sb", kill: "sk", join: "sj" };
/** `none`'s reason as the field its seconds go to: the first gate that failed, or the end that stopped the exchange. */
const NONE_FIELD: Record<string, string | undefined> = {
    unfavoured: "rnf",
    no_reach: "rnr",
    deny: "rdn",
    due: "rdu",
    creeps: "rcr",
    wave: "rwv",
    kill: "rus",
    unknown: "rus",
    tower: "rus",
    aggro: "rag",
    no_target: "rnt",
};
const FIELDS = ["sn", "sh", "sb", "sk", "sj", "rnf", "rnr", "rdn", "rdu", "rcr", "rwv", "rus", "rag", "rnt", "rot", "ord"];

/** Ends the held block: logs its tally. */
function endBlock(pid: number, b: Block): void {
    const f: [string, number | string][] = [["kind", "trade"], ["ph", "end"], ["pid", pid], ["agg", b.agg], ["blk", b.blk]];
    let secs = 0;
    for (const k of ["sn", "sh", "sb", "sk", "sj"]) secs += b.tally[k] ?? 0;
    f.push(["secs", r2(secs)]);
    for (const k of FIELDS) f.push([k, k === "ord" ? b.tally[k] ?? 0 : r2(b.tally[k] ?? 0)]);
    Telemetry.Event("roll", f as any);
}

/** One frame's answer in the hero's block (`Ours.ExploreTrade` on, a block held): its seconds go to the level and, for `none`, to the reason's field. */
export function Tally(bot: Unit, level: string, why: string, now: number): void {
    const b = blocks[bot.GetPlayerID()];
    if (b === undefined) return;
    const dt = b.last === undefined ? 0 : math.min(TRADE.MaxDt, math.max(0, now - b.last));
    b.last = now;
    const lf = LEVEL_FIELD[level] ?? "sn";
    b.tally[lf] = (b.tally[lf] ?? 0) + dt;
    if (level === "none") {
        const nf = NONE_FIELD[why] ?? "rot";
        b.tally[nf] = (b.tally[nf] ?? 0) + dt;
    }
}

/** The hero was ordered to attack an enemy hero by the exchange. */
export function Order(bot: Unit): void {
    const b = blocks[bot.GetPlayerID()];
    if (b !== undefined) b.tally.ord = (b.tally.ord ?? 0) + 1;
}

/** Seconds per level and, for `none`, per reason bucket, and the attack orders on heroes: summed over a block from the frames Desire answered in lane. */
type Tally = Record<string, number>;

interface Block {
    agg: number;
    blk: number;
    first: number;
    tally: Tally;
    /** Time of the last tallied frame (a gap over `TRADE.MaxDt` counts as `MaxDt`). */
    last?: number;
}

const blocks: Record<number, Block | undefined> = {};

/** The 45 s block index of `now` for a hero whose first laning frame was `first`. */
export function BlockOf(first: number, now: number): number {
    return math.max(0, math.floor((now - first) / TRADE.Block));
}

/** The draw for a uniform `u` in [0, 1). */
export function AggFor(u: number): number {
    const n = TRADE.Aggs.length;
    return TRADE.Aggs[math.min(n - 1, math.max(0, math.floor(u * n)))];
}

function logTrade(bot: Unit, b: Block): void {
    let ned = -1;
    let ne = 0;
    for (const h of bot.GetNearbyHeroes(TRADE.SeeHeroes, true, BotMode.None)) {
        if (h.IsNull() || !h.IsAlive()) continue;
        const d = GetUnitToUnitDistance(bot, h);
        if (ned < 0 || d < ned) ned = d;
        if (d <= TRADE.NearHeroes) ne++;
    }
    const mine = bot.GetNearbyHeroes(TRADE.NearHeroes, false, BotMode.None).length;
    Telemetry.Event("roll", [
        ["kind", "trade"], ["ph", "start"], ["pid", bot.GetPlayerID()], ["agg", b.agg], ["blk", b.blk],
        ["hp", r2(bot.GetHealth() / math.max(1, bot.GetMaxHealth()))], ["lvl", bot.GetLevel()], ["ned", math.floor(ned)], ["ne", ne],
        ["ocr", bot.GetNearbyLaneCreeps(TRADE.NearCreeps, false).length], ["ecr", bot.GetNearbyLaneCreeps(TRADE.NearCreeps, true).length], ["pn", mine > 0 ? 1 : 0],
    ]);
}

/**
 * The hero's aggression on the in-lane exchange (`Ours.ExploreTrade`): undefined with the switch off, else the draw held for the
 * current 45 s block, redrawn on the first call in the next one. Called from `Trade.Gather`, so only a hero in lane draws.
 */
export function Agg(bot: Unit): number | undefined {
    if (!Ours.On("ExploreTrade")) return undefined;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const held = blocks[pid];
    const first = held !== undefined ? held.first : now;
    const blk = BlockOf(first, now);
    if (held !== undefined && held.blk === blk) return held.agg;
    if (held !== undefined) endBlock(pid, held);
    const b: Block = { agg: AggFor(LaneConfig.Draw() ?? RandomFloat(0, 1)), blk, first, tally: {} };
    blocks[pid] = b;
    logTrade(bot, b);
    return b.agg;
}

export const _test = { rolls, blocks };
