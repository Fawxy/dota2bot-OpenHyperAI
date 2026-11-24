/**
 * The deny (doctrine D12, switch Ours.Deny), a row of the decider (plan s3; families proposal s6, case 1): a hero denies any of
 * our lane creeps the reach rule (`lane_offers.Reachable`) puts in its reach. Which positions may is `states/trip_table`'s
 * row `deny` (pos 4 and 5 for now; cores are held back until the row's worth and the claim exist). No pre-positioning: the
 * offers are the engine's `laneTargets` as they stand.
 *
 * The skip (slice oha-deny-skip): a creep whose killing hit in the lane read (`lane_hits`) is a teammate's is passed over
 * for the next reachable deny, and a live attempt drops before its swing once that becomes true. The killing hit is the
 * first at which the forecast reaches 0, so a teammate's that kills is never behind an enemy hero's that would. Asked
 * afresh each round: a teammate's wind-up that cancels gives the creep back.
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
import { BotMode, Lane, Unit } from "bots/ts_libs/dota";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as LaneHits from "bots/FunLib/humaniser/lane_hits";
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
    /** The teammate whose hit the attempt dropped for, once it has. */
    mate?: number;
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

const LANES: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];

/** A teammate's hit that kills the creep, as the lane read has it. */
export interface MateHit {
    pid: number;
    /** Seconds until that hit commits (0: fired). */
    commit: number;
}

/** The teammate (never the bot itself) whose hit kills the creep first, else undefined. */
export function MateOn(bot: Unit, creep: unknown): MateHit | undefined {
    const team = bot.GetTeam();
    let row: LaneHits.CreepHits | undefined;
    for (const lane of LANES) {
        row = LaneHits.Of(team, lane, creep as Unit);
        if (row !== undefined) break;
    }
    if (row === undefined) return undefined;
    const k = LaneHits.KillingHit(row);
    if (k === undefined || (k.by !== "hero" && k.by !== "self")) return undefined;
    const a = k.attacker as unknown as Unit;
    if (a === bot || a.GetTeam() !== team) return undefined;
    return { pid: a.GetPlayerID(), commit: k.commit };
}

export interface Offered {
    t: Lib.Verbs.LaneTarget;
    mate?: MateHit;
}

/**
 * The reachable deny closest to coming due that no teammate's hit takes. When a teammate's takes every reachable one, the
 * nearest-due of those comes back with its `mate` (the row logs it and holds nothing). Undefined when nothing is reachable,
 * or while the engine bundle is not loaded.
 */
export function Offer(bot: Unit): Offered | undefined {
    const verbs = Tasks.Verbs();
    if (verbs === undefined) return undefined;
    let free: Lib.Verbs.LaneTarget | undefined;
    let taken: Offered | undefined;
    for (const t of verbs.laneTargets(bot as unknown as Lib.TaskUnit, { within: 1, lastHit: false })) {
        if (t.kind !== "deny" || !LaneOffers.Reachable(t)) continue;
        if (free !== undefined && t.eta >= free.eta) continue;
        const mate = MateOn(bot, t.creep);
        if (mate === undefined) free = t;
        else if (taken === undefined || t.eta < taken.t.eta) taken = { t, mate };
    }
    return free !== undefined ? { t: free } : taken;
}

function choiceLine(bot: Unit, slot: number, go: boolean, why: string | undefined, o: Offered, src?: string): void {
    const t = o.t;
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
        ["mate", o.mate?.pid],
        ["mc", o.mate !== undefined ? r2(o.mate.commit) : undefined],
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
    const pid = bot.GetPlayerID();
    const mate = running[pid]?.mate;
    running[pid] = undefined;
    const why = r.success ? "ok" : r.reason === "interrupted" && mate !== undefined ? "mate" : `${r.reason}${r.message !== undefined ? ":" + r.message : ""}`;
    jobLine(bot, "end", why, cutBy(bot, r));
}

function rowOn(bot: Unit): boolean {
    return Ours.On("Deny") && MayDeny(bot) && !Drill.Held(bot);
}

/** The shadow (switch off, or the other team under Ours.Team): the same offer, logged once per creep, nothing ordered. */
function shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled() || !MayDeny(bot) || Drill.Held(bot)) return;
    if (!LaneConfig.InLaningPhase() || !bot.IsAlive()) return;
    const o = Offer(bot);
    if (o === undefined) return;
    const cid = Telemetry.CreepId(o.t.creep as unknown as Unit);
    if (firstLine(bot, cid, false)) choiceLine(bot, slotOf(cid), false, "off", o, "shadow");
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
    const o = Offer(bot);
    if (o === undefined) return false;
    const t = o.t;
    const cid = Telemetry.CreepId(t.creep as unknown as Unit);
    const slot = slotOf(cid);
    if (o.mate !== undefined) {
        if (firstLine(bot, cid, false)) choiceLine(bot, slot, false, "mate", o);
        return false;
    }
    if (acting(bot)) {
        if (firstLine(bot, cid, false)) choiceLine(bot, slot, false, "acting", o);
        return false;
    }
    const creep = t.creep;
    // Checked by the verb before its swing only: once swung, our hit lands whatever a teammate does.
    const mateTakes = (): boolean => {
        const m = MateOn(bot, creep);
        const a = running[pid];
        if (m !== undefined && a !== undefined) a.mate = m.pid;
        return m !== undefined;
    };
    const ok = Tasks.Start(bot, { name: "deny", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: r => finish(bot, r) }, (ctx: Lib.Ctx) =>
        ctx.deny({ target: creep, maxWait: t.eta + WAIT_SLACK, interruptIf: mateTakes })
    );
    if (!ok) {
        if (firstLine(bot, cid, false)) choiceLine(bot, slot, false, "refused", o);
        return false;
    }
    if (firstLine(bot, cid, true)) choiceLine(bot, slot, true, undefined, o);
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
