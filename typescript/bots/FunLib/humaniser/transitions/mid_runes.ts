/**
 * Lane safety and laning-phase transitions (task 12, 3b): our mid takes power runes.
 *
 * mode_rune_generic left power runes alone for four reasons (task-3b-report.md): a nearer bounty
 * shadowed the power rune, a MISSING power rune is skipped until :52 of the minute, an idle bot (one
 * waiting at the spot) has no rune desire, and without a bottle the desire lost to laning.
 * Focus() fixes the first three inside the rune mode; Tick() posts a floor claim for the fourth.
 * The rune mode yields the claim on any frame its own gates refuse, so the floor never overrides them.
 */
import { BotMode, Rune, Unit, Vector } from "bots/ts_libs/dota";
import * as Intent from "bots/FunLib/humaniser/intent";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare function GetRuneStatus(this: void, rune: number): number;
declare const RUNE_STATUS_AVAILABLE: number;
declare const RUNE_STATUS_MISSING: number;

export const SOURCE = "transitions:mid_rune";

interface MidState {
    checkAt: number;
    claim: boolean;
    focus: boolean;
    preSpawn: boolean;
    // The power spot to head for after a spawn; undefined lets the rune mode pick the nearest.
    target?: number;
    // What this bot has seen of the latest spawn. A rune spawns at only one of the two spots.
    spawn: number;
    seenAvailable: Record<number, boolean>;
    seenEmpty: Record<number, boolean>;
    done: boolean;
    skipSpawn: number;
}

const states: Record<number, MidState> = {};

function stateFor(bot: Unit): MidState {
    const pid = bot.GetPlayerID();
    let s = states[pid];
    if (s === undefined) {
        s = { checkAt: -math.huge, claim: false, focus: false, preSpawn: false, spawn: -1, seenAvailable: {}, seenEmpty: {}, done: false, skipSpawn: -1 };
        states[pid] = s;
    }
    return s;
}

export function IsMid(bot: Unit): boolean {
    return LaneConfig.PositionOf(bot) === 2;
}

export function IsOn(bot: Unit): boolean {
    return Settings.IsOn("MidRunes") && IsMid(bot);
}

const POWER_SPOTS: number[] = [Rune.Power1, Rune.Power2];

function distanceTo(loc: Vector, rune: number): number {
    const spot = GetRuneSpawnLocation(rune);
    return math.sqrt((spot.x - loc.x) ** 2 + (spot.y - loc.y) ** 2);
}

/** The nearest power spot passing `ok`, or undefined. */
function nearestPower(loc: Vector, ok: (this: void, rune: number) => boolean): LuaMultiReturn<[number | undefined, number]> {
    let best: number | undefined;
    let bestD = math.huge;
    for (const rune of POWER_SPOTS) {
        const d = distanceTo(loc, rune);
        if (ok(rune) && d < bestD) {
            bestD = d;
            best = rune;
        }
    }
    return $multi(best, bestD);
}

/** The latest power spawn strictly before `now`, or undefined before the first. */
function lastSpawn(now: number): number | undefined {
    const last = Runes.NextSpawn("power", now) - Runes.RUNE_RULES.power.every;
    return last >= Runes.RUNE_RULES.power.first && last < now ? last : undefined;
}

function refresh(bot: Unit, s: MidState, now: number): void {
    const cfg = Settings.Get();
    s.checkAt = now + cfg.Refresh;
    const loc = bot.GetLocation();
    const due = Runes.NextSpawn("power", now) - now;
    s.preSpawn = due <= cfg.MidRuneFocus;
    s.target = undefined;

    let pending = false;
    const last = lastSpawn(now);
    if (last !== undefined) {
        if (s.spawn !== last) {
            s.spawn = last;
            s.seenAvailable = {};
            s.seenEmpty = {};
            s.done = false;
        }
        let available: number | undefined;
        for (const rune of POWER_SPOTS) {
            const status = GetRuneStatus(rune);
            if (status === RUNE_STATUS_AVAILABLE) {
                s.seenAvailable[rune] = true;
                available = rune;
            } else if (status === RUNE_STATUS_MISSING) {
                // Seen available here before: taken. Otherwise the rune did not spawn here.
                if (s.seenAvailable[rune] === true) s.done = true;
                s.seenEmpty[rune] = true;
            }
        }
        if (s.seenEmpty[Rune.Power1] === true && s.seenEmpty[Rune.Power2] === true) s.done = true;
        if (!s.done) {
            if (available !== undefined) s.target = available;
            // An unseen spot is only worth checking shortly after the spawn.
            else if (now - last <= cfg.MidRuneCheckWindow) s.target = nearestPower(loc, (r) => s.seenEmpty[r] !== true)[0];
            pending = s.target !== undefined;
        }
    }

    const inReach = (s.target !== undefined ? distanceTo(loc, s.target) : nearestPower(loc, () => true)[1]) <= cfg.MidRuneRadius;
    s.focus = s.preSpawn || (pending && inReach);
    s.claim = inReach && (due <= cfg.MidRuneLead || pending);
    if (!pending) s.target = undefined;
}

function current(bot: Unit): MidState {
    const s = stateFor(bot);
    const now = DotaTime();
    if (now >= s.checkAt) refresh(bot, s, now);
    return s;
}

/**
 * For the rune mode: whether only power spots count (a power rune is due within MidRuneFocus or is up),
 * whether it is due rather than up, so a MISSING (not yet spawned) power spot still counts, and after a
 * spawn the one spot to head for (where it was seen, else the nearer spot not yet seen empty).
 */
export function Focus(bot: Unit): LuaMultiReturn<[boolean, boolean, number | undefined]> {
    if (!IsOn(bot)) return $multi(false, false, undefined);
    const s = current(bot);
    return $multi(s.focus, s.focus && s.preSpawn, s.focus && !s.preSpawn ? s.target : undefined);
}

export function Tick(bot: Unit): void {
    if (!IsOn(bot)) return;
    const s = current(bot);
    // Unlike caution and rotations, the mid-rune floor applies all game, by decision: a mid contesting power runes is
    // normal play after laning too.
    if (s.claim) Intent.Claim(bot, { source: SOURCE, tier: "TRANSITION", mode: BotMode.Rune, floor: Settings.Get().MidRuneFloor });
}

/** The rune mode refused this frame (a safety gate, no power target): the floor must not apply. */
export function Yield(bot: Unit): void {
    Intent.Release(bot, SOURCE, BotMode.Rune);
}

/** rune_skip telemetry: a mid with little rune desire around a power spawn, at most once per spawn. */
export function NoteSkip(bot: Unit, raw: number, desire: number, target: number | undefined, status: number | undefined, gate: string | undefined): void {
    if (!Telemetry.IsEnabled() || !IsMid(bot)) return;
    const cfg = Settings.Get();
    if (type(desire) !== "number" || desire >= cfg.MidRuneSkipDesire) return;
    const now = DotaTime();
    const next = Runes.NextSpawn("power", now);
    const last = lastSpawn(now);
    let spawn: number | undefined;
    if (next - now <= cfg.MidRuneSkipWindow) spawn = next;
    else if (last !== undefined && now - last <= cfg.MidRuneSkipWindow) spawn = last;
    if (spawn === undefined) return;
    const s = stateFor(bot);
    if (s.skipSpawn === spawn) return;
    s.skipSpawn = spawn;
    Telemetry.Event("rune_skip", [
        ["pid", bot.GetPlayerID()],
        ["spawn", spawn],
        ["target", target],
        ["status", status],
        ["raw", raw],
        ["desire", desire],
        ["laning", Intent.Competing(bot)],
        ["gate", gate],
    ]);
}
