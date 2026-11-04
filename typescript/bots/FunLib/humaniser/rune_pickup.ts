/**
 * Rune pickup give-up (slice rune-spawn, switch Ours.RuneSpawn). The 0:00 river bounty at a power spot is sometimes never
 * taken by `Action_PickUpRune` (cause unknown; on some client sessions no pickup of rune id 0 works at all) and OHA's rune
 * mode then held the hero at the spot until the 2:00 spawn. OHA's own guard waits for the pickup action to end, which an
 * order on an untakeable rune may never do; this one times from the first order instead. One `ev=rune_try` line when a
 * try starts and one when it ends (`gone`: the rune went; `left`: the hero walked off; `gave_up`).
 */
import { Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare function GetRuneStatus(this: void, rune: number): number;
declare function GetRuneSpawnLocation(this: void, rune: number): { x: number; y: number; z: number };
declare const RUNE_STATUS_AVAILABLE: number;

export const SETTINGS = {
    /** Seconds of pickup orders within Near of an available rune before it is given up (judgement). */
    GiveUpAfter: 3,
    Near: 150,
    /** A try ends `left` once the hero is this far from the spot. */
    LeftAt: 400,
    /** River runes respawn every 2 minutes: a given-up rune stays given up until the next spawn. */
    SpawnEvery: 120,
};

interface Try {
    rune: number;
    from: number;
    act0: number;
}

const tries: Record<number, Try | undefined> = {};
const unpickableUntil: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(tries)) tries[k as number] = undefined;
    for (const [k] of pairs(unpickableUntil)) unpickableUntil[k as number] = undefined;
}

export function On(): boolean {
    return Ours.On("RuneSpawn");
}

function actionType(bot: Unit): number {
    return (bot as unknown as { GetCurrentActionType(): number }).GetCurrentActionType();
}

/** The next river spawn after `now` (2:00, 4:00, ...). */
export function NextSpawn(now: number): number {
    return (math.floor(math.max(now, 0) / SETTINGS.SpawnEvery) + 1) * SETTINGS.SpawnEvery;
}

/** Given up by any hero of this team until the rune's next spawn. */
export function Unpickable(rune: number, now: number = DotaTime()): boolean {
    const until = unpickableUntil[rune];
    return until !== undefined && now < until;
}

function line(bot: Unit, t: Try, res: string, now: number): void {
    Telemetry.Event("rune_try", [
        ["pid", bot.GetPlayerID()],
        ["rune", t.rune],
        ["res", res],
        ["d", math.floor(GetUnitToLocationDistance(bot, GetRuneSpawnLocation(t.rune) as never))],
        ["act0", t.act0],
        ["act", actionType(bot)],
        ["st", GetRuneStatus(t.rune)],
        ["dt", math.floor((now - t.from) * 10) / 10],
    ]);
}

/** Every frame from the rune mode: closes this hero's open try once the rune went or the hero walked off. */
export function Tick(bot: Unit, now: number = DotaTime()): void {
    const pid = bot.GetPlayerID();
    const t = tries[pid];
    if (t === undefined) return;
    if (GetRuneStatus(t.rune) !== RUNE_STATUS_AVAILABLE) {
        line(bot, t, "gone", now);
        tries[pid] = undefined;
    } else if (GetUnitToLocationDistance(bot, GetRuneSpawnLocation(t.rune) as never) > SETTINGS.LeftAt) {
        line(bot, t, "left", now);
        tries[pid] = undefined;
    }
}

/**
 * Before each pickup order: false when the rune is given up (the caller does not order it). Gives the rune up once this
 * hero has been ordering it within Near for GiveUpAfter seconds while it stays available.
 */
export function Try(bot: Unit, rune: number, now: number = DotaTime()): boolean {
    if (Unpickable(rune, now)) return false;
    const pid = bot.GetPlayerID();
    let t = tries[pid];
    if (t !== undefined && t.rune !== rune) {
        line(bot, t, "left", now);
        t = undefined;
    }
    if (t === undefined) {
        t = { rune, from: now, act0: actionType(bot) };
        tries[pid] = t;
        line(bot, t, "try", now);
        return true;
    }
    const near = GetUnitToLocationDistance(bot, GetRuneSpawnLocation(rune) as never) <= SETTINGS.Near;
    if (near && now - t.from >= SETTINGS.GiveUpAfter && GetRuneStatus(rune) === RUNE_STATUS_AVAILABLE) {
        unpickableUntil[rune] = NextSpawn(now);
        line(bot, t, "gave_up", now);
        tries[pid] = undefined;
        return false;
    }
    if (!near) t.from = now;
    return true;
}
