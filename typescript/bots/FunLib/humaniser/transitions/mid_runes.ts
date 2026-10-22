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
    // The spawn this bot has seen taken or empty at its spot; that spawn no longer pulls it.
    doneSpawn: number;
    skipSpawn: number;
}

const states: Record<number, MidState> = {};

function stateFor(bot: Unit): MidState {
    const pid = bot.GetPlayerID();
    let s = states[pid];
    if (s === undefined) {
        s = { checkAt: -math.huge, claim: false, focus: false, preSpawn: false, doneSpawn: -1, skipSpawn: -1 };
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

function nearestPower(loc: Vector): LuaMultiReturn<[number, number]> {
    let best = Rune.Power1 as number;
    let bestD = math.huge;
    for (const rune of [Rune.Power1, Rune.Power2]) {
        const spot = GetRuneSpawnLocation(rune);
        const d = math.sqrt((spot.x - loc.x) ** 2 + (spot.y - loc.y) ** 2);
        if (d < bestD) {
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
    const due = Runes.NextSpawn("power", now) - now;
    const [rune, dist] = nearestPower(bot.GetLocation());
    const status = GetRuneStatus(rune);
    const last = lastSpawn(now);
    if (last !== undefined && status === RUNE_STATUS_MISSING) s.doneSpawn = last;
    // Spawned and not yet seen taken; an unseen (UNKNOWN) spot only counts within reach.
    const pending = last !== undefined && s.doneSpawn !== last && status !== RUNE_STATUS_MISSING;
    const inReach = dist <= cfg.MidRuneRadius;
    s.preSpawn = due <= cfg.MidRuneFocus;
    s.focus = s.preSpawn || (pending && (status === RUNE_STATUS_AVAILABLE || inReach));
    s.claim = inReach && (due <= cfg.MidRuneLead || pending);
}

function current(bot: Unit): MidState {
    const s = stateFor(bot);
    const now = DotaTime();
    if (now >= s.checkAt) refresh(bot, s, now);
    return s;
}

/**
 * For the rune mode: whether only power spots count (a power rune is due within MidRuneFocus or is up),
 * and whether it is due rather than up, so a MISSING (not yet spawned) power spot still counts.
 */
export function Focus(bot: Unit): LuaMultiReturn<[boolean, boolean]> {
    if (!IsOn(bot)) return $multi(false, false);
    const s = current(bot);
    return $multi(s.focus, s.focus && s.preSpawn);
}

export function Tick(bot: Unit): void {
    if (!IsOn(bot)) return;
    const s = current(bot);
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
