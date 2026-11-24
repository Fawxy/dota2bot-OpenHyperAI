/**
 * The deny (doctrine D12, switch Ours.Deny), a row of the decider (plan s3; families proposal s6, case 1): a hero denies any of
 * our lane creeps the reach rule (`lane_offers.Reachable`) puts in its reach. Which positions may is `states/trip_table`'s
 * row `deny` (pos 4 and 5 for now; cores are held back until the row's worth and the claim exist). No pre-positioning: the
 * offers are the engine's `laneTargets` as they stand.
 *
 * The row latches its attempt (user 24/11/2026): `applies` is true while a started deny's task runs, whatever the offer now
 * says, so a damage estimate that changes mid-wind-up does not drop the hold and let stock cancel the swing. The task is
 * the engine `deny` verb on that creep; it ends when the creep dies, the deny lands or its wait runs out (`maxWait`, as
 * laneFarm's), and then the decider yields the hero to stock. Stock's retreat lets go first (the decider's).
 *
 * One `ev=choice kind=deny` line per creep offered (its `slot` the second it was first offered), a shadow where the switch is
 * off, and an `ev=job job=deny` start and end per attempt: the timeline's `decision` rows, so `q @decisions --p what=deny`
 * gives the land rate (`done` per started) with no hlog change.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneOffers from "bots/FunLib/humaniser/lane_offers";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** The mode the decider hosts its rows in: the engine steps the deny's task under it. */
const HOST = BotMode.Farm;

/** The wait for the creep to come due, after its eta: laneFarm's own (`maxWait` eta + 1.5 s, engine/docs/API.md). `judgement`. */
export const WAIT_SLACK = 1.5;

interface Attempt {
    cid: number;
    slot: number;
}

const running: Record<number, Attempt | undefined> = {};
/** Per hero: the creeps already given their choice line, by CreepId, with the line's `go`. */
const logged: Record<number, Record<number, number> | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, logged] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

/** A bot whose position the trip table lets deny, whatever the switches say: the hero the line's reader names. */
export function MayDeny(bot: Unit): boolean {
    return bot.IsBot() && TripTable.Does("deny", LaneConfig.PositionOf(bot));
}

/** OHA's own action holds the hero (pull_job's and rune_job's check: a queued TP, a cast or channel). */
function acting(bot: Unit): boolean {
    return bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility();
}

/** The reachable deny closest to coming due, else undefined. Undefined too while the engine bundle is not loaded. */
export function Offer(bot: Unit): Lib.Verbs.LaneTarget | undefined {
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return undefined;
    let best: Lib.Verbs.LaneTarget | undefined;
    for (const t of verbs.laneTargets(bot as unknown as Lib.TaskUnit, { within: 1, lastHit: false })) {
        if (t.kind !== "deny" || !LaneOffers.Reachable(t)) continue;
        if (best === undefined || t.eta < best.eta) best = t;
    }
    return best;
}

function choiceLine(bot: Unit, slot: number, go: boolean, why: string | undefined, t: Lib.Verbs.LaneTarget, src?: string): void {
    const r2 = (x: number) => math.floor(x * 100 + 0.5) / 100;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "deny"],
        ["want", 1],
        ["go", go ? 1 : 0],
        ["why", why],
        ["src", src ?? "own"],
        ["lane", bot.GetAssignedLane()],
        ["slot", slot],
        ["walk", r2(t.walk)],
        ["due", r2(t.due)],
        ["dies", t.dies === math.huge ? -1 : r2(t.dies)],
    ]);
}

/** Once per creep and hero: true the first time (and the first time it goes), so a line goes out only then. */
function firstLine(bot: Unit, cid: number, go: boolean): boolean {
    const pid = bot.GetPlayerID();
    let seen = logged[pid];
    if (seen === undefined) {
        seen = {};
        logged[pid] = seen;
    }
    const was = seen[cid];
    if (was === 1 || (was === 0 && !go)) return false;
    seen[cid] = go ? 1 : 0;
    return true;
}

/** Slot of a creep's line: the second it was first offered, to 0.1 s. */
const slots: Record<number, number> = {};
function slotOf(cid: number): number {
    let s = slots[cid];
    if (s === undefined) {
        s = math.floor(DotaTime() * 10) / 10;
        slots[cid] = s;
    }
    return s;
}

function jobLine(bot: Unit, phase: string, why: string, cut?: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "deny"],
        ["phase", phase],
        ["why", why],
        ["host", HOST],
        ["cut", cut],
    ]);
}

/** As the pull's: a deny the engine ends because the host lost the hero names what took it. */
function cutBy(bot: Unit, r: Lib.Result): string | undefined {
    if (r.success || r.reason !== "preempted") return undefined;
    if (Decider.LetGo(bot) || bot.GetActiveMode() === BotMode.Retreat) return "retreat";
    return HDebug.ModeName(bot.GetActiveMode());
}

function finish(bot: Unit, r: Lib.Result): void {
    running[bot.GetPlayerID()] = undefined;
    jobLine(bot, "end", r.success ? "ok" : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`, cutBy(bot, r));
}

function rowOn(bot: Unit): boolean {
    return Ours.On("Deny") && MayDeny(bot) && !Drill.Held(bot);
}

/** The shadow (switch off, or the other team under Ours.Team): the same offer, logged once per creep, nothing ordered. */
function shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled() || !MayDeny(bot) || Drill.Held(bot)) return;
    if (!LaneConfig.InLaningPhase() || !bot.IsAlive()) return;
    const t = Offer(bot);
    if (t === undefined) return;
    const cid = Telemetry.CreepId(t.creep as unknown as Unit);
    if (firstLine(bot, cid, false)) choiceLine(bot, slotOf(cid), false, "off", t, "shadow");
}

/** The row's `applies`, asked every scoring round: true while an attempt runs (the latch) or as one starts. */
function rowApplies(bot: Unit): boolean {
    if (!rowOn(bot)) {
        shadow(bot);
        return false;
    }
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return true;
    if (!LaneConfig.InLaningPhase() || !bot.IsAlive()) return false;
    const t = Offer(bot);
    if (t === undefined) return false;
    const cid = Telemetry.CreepId(t.creep as unknown as Unit);
    const slot = slotOf(cid);
    if (acting(bot)) {
        if (firstLine(bot, cid, false)) choiceLine(bot, slot, false, "acting", t);
        return false;
    }
    const creep = t.creep;
    const ok = Tasks.Start(bot, { name: "deny", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: r => finish(bot, r) }, (ctx: Lib.Ctx) =>
        ctx.deny({ target: creep, maxWait: t.eta + WAIT_SLACK })
    );
    if (!ok) {
        if (firstLine(bot, cid, false)) choiceLine(bot, slot, false, "refused", t);
        return false;
    }
    if (firstLine(bot, cid, true)) choiceLine(bot, slot, true, undefined, t);
    running[pid] = { cid, slot };
    jobLine(bot, "start", "trigger");
    return true;
}

/** The row's verb: one frame of the deny; true once it has ended. */
function rowStep(bot: Unit): boolean {
    if (running[bot.GetPlayerID()] === undefined) return true;
    Tasks.Step(bot, HOST);
    return running[bot.GetPlayerID()] === undefined;
}

/**
 * The decider's row (registered in index.ts, so the decider imports no row). Soft (plan s3): Valve's attack, item, evasive
 * and defend-ally outbid it when they want the hero; on the hard hold the supports lost about a quarter of their seconds in
 * attack mode (batch sdeny1).
 */
export const ROW: Decider.Row = { name: "deny", applies: rowApplies, step: rowStep, soft: true };
