/**
 * The lane's creeps, first group (no-creep-unpaid proposal s5; doctrine D11; switch Ours.LaneCreeps), a soft row of the
 * decider: a core takes their ranged creep by a right-click where stock does not swing. Which positions act is
 * `states/trip_table`'s `creep` row (pos 1 to 3; supports wait for the core-first margin, proposal s3).
 *
 * The cells were named with the user from step 2's table (25/11/2026): near (in range or a walk up to NearWalk, not
 * out-damaged) and far and free (a longer walk with no enemy hero's range on the stand spot). The decision is taken at the
 * creep offer read (`creep_offer.ts`, every 0.2 s a hero), on that read's facts: the read hands its candidates in through
 * SetRow, so a creep's handle is only called on a read that lists it. `Claim` is the cell rule on the facts; the row goes on
 * the claimed creep closest to due once it is about to come due (`Due`) and stock is not attacking it, since stock takes three
 * in four of the claimed creeps it swings at (cofshadow2) and the row is for the ones it leaves.
 *
 * The verb is the engine's `lastHit` on that creep (it walks into range, waits and swings when its hit kills); the attempt
 * latches the hold until the task ends (the creep dies, the hit lands, the wait runs out), then the hero is stock's again.
 * Soft: Valve's attack, item, evasive and defend-ally outbid it; stock's retreat lets go first (the decider's).
 *
 * Lines: the read's `ev=choice kind=creep`, `src=own` with this row's `go` and latest `why`; `ev=job job=creep` start and end
 * per attempt.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as CreepOffer from "bots/FunLib/humaniser/creep_offer";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneHits from "bots/FunLib/humaniser/lane_hits";
import * as Ours from "bots/FunLib/humaniser/ours";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /** The longest walk (s) in the near cell; past it a covered stand spot is refused (step 2's table split, proposal s5). */
    NearWalk: 1.0,
    /**
     * The row goes once `due` is within the walk plus this (s): two of the read's intervals, so the next read is not too late
     * (judgement). Earlier, stock may still swing at the creep itself.
     */
    Lead: 0.4,
    /** The wait for the creep to come due, after its eta: laneFarm's own (`maxWait` eta + 1.5 s, engine/docs/API.md). `judgement`. */
    WaitSlack: 1.5,
};

/** The mode the decider hosts its rows in: the engine steps the attempt's task under it. */
const HOST = BotMode.Farm;

/** The offer's facts the cell rule reads (the read's snapshot, or a fixture's). */
export interface Facts {
    kind: string;
    ck: string;
    walk: number;
    slk: number;
    /** Enemy heroes whose range covers the stand spot. */
    eh: number;
    md: number;
    ed: number;
    ein: number;
    ptw: boolean;
    otw: boolean;
    g2: number;
    kb: string;
}

/**
 * The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (not their ranged creep),
 * `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `covered` (a walk past NearWalk to a spot
 * an enemy hero's range covers), `tower` (inside our tower's range: the under-tower hit is a later widening, s6), `etower`
 * (the stand spot is inside their tower's), `given` (a walk-in: another target comes due where the hero stands before it is back),
 * `mate` (a teammate's hit kills it first).
 */
export function Claim(this: void, f: Facts): string | undefined {
    if (f.kind !== "lasthit" || f.ck !== "r") return "kind";
    if (f.slk <= 0) return "late";
    if (f.ein > 0 && f.ed > f.md) return "outdmg";
    if (f.walk > SETTINGS.NearWalk && f.eh > 0) return "covered";
    if (f.otw) return "tower";
    if (f.ptw) return "etower";
    // In range there is no walk, so nothing is given up: which creep to swing at is the row's pick (Consider).
    if (f.walk > 0 && f.g2 > 0) return "given";
    if (f.kb === "mate") return "mate";
    return undefined;
}

/** About to come due: a swing ordered on arrival is due within Lead of it. */
export function Due(this: void, walk: number, due: number): boolean {
    return due <= walk + SETTINGS.Lead;
}

interface Attempt {
    cid: number;
}

const running: Record<number, Attempt | undefined> = {};
/** pid -> the creep of the hero's last attempt: one attempt a creep. */
const lastCid: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, lastCid] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

export function On(bot: Unit): boolean {
    return Ours.On("LaneCreeps") && CreepOffer.MayOffer(bot) && !Drill.Held(bot);
}

/** OHA's own action holds the hero (the deny and pull rows' check: a queued order, a cast or channel). */
function acting(bot: Unit): boolean {
    return bot.NumQueuedActions() > 0 || bot.IsChanneling() || bot.IsUsingAbility() || bot.IsCastingAbility();
}

/** A teammate's hit kills the creep first in the lane read (the attempt drops before its swing then). */
function mateTakes(bot: Unit, creep: unknown): boolean {
    const row = LaneHits.Of(bot.GetTeam(), bot.GetAssignedLane(), creep as Unit);
    if (row === undefined) return false;
    const k = LaneHits.KillingHit(row);
    if (k === undefined || (k.by !== "hero" && k.by !== "self")) return false;
    const a = k.attacker as unknown as Unit;
    return a !== bot && a.GetTeam() === bot.GetTeam();
}

function jobLine(bot: Unit, phase: string, why: string, cut?: string): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "creep"],
        ["phase", phase],
        ["why", why],
        ["host", HOST],
        ["cut", cut],
    ]);
}

/** As the pull's: an attempt the engine ends because the host lost the hero names what took it. */
function cutBy(bot: Unit, r: Lib.Result): string | undefined {
    if (r.success || r.reason !== "preempted") return undefined;
    if (Decider.LetGo(bot) || bot.GetActiveMode() === BotMode.Retreat) return "retreat";
    return HDebug.ModeName(bot.GetActiveMode());
}

function finish(bot: Unit, r: Lib.Result): void {
    running[bot.GetPlayerID()] = undefined;
    jobLine(bot, "end", r.success ? "ok" : r.reason, cutBy(bot, r));
}

function factsOf(c: CreepOffer.Candidate): Facts {
    const s = c.facts();
    return { kind: c.t.kind, ck: c.ck, walk: c.t.walk, slk: c.arrive.slack, eh: s.path.covering, md: s.md, ed: s.ed, ein: s.ein, ptw: s.path.tower, otw: s.otw, g2: s.given.due, kb: s.kb };
}

/**
 * The read's hook (CreepOffer.SetRow), at each read of a hero: notes why each candidate is not taken and starts an attempt on
 * the claimed creep closest to due. Reasons asked before the facts are read: `busy` (an attempt runs), `kind`, `early` (not
 * yet about to come due), `acting`, `stock` (stock is attacking it), `tried` (this creep's attempt has ended); then Claim's;
 * `refused` (the task runner said no).
 */
export function Consider(this: void, bot: Unit, cands: CreepOffer.Candidate[]): void {
    if (!On(bot)) return;
    const pid = bot.GetPlayerID();
    if (running[pid] !== undefined) {
        for (const c of cands) c.note(false, "busy");
        return;
    }
    if (Tasks.Jobs() === undefined) return;
    const target = bot.GetAttackTarget();
    const busy = acting(bot);
    let best: CreepOffer.Candidate | undefined;
    for (const c of cands) {
        let why: string | undefined;
        if (c.t.kind !== "lasthit" || c.ck !== "r") why = "kind";
        else if (!Due(c.t.walk, c.t.due)) why = "early";
        else if (busy) why = "acting";
        else if (target === c.creep) why = "stock";
        else if (lastCid[pid] === c.cid) why = "tried";
        else why = Claim(factsOf(c));
        if (why !== undefined) c.note(false, why);
        else if (best === undefined || c.t.eta < best.t.eta) best = c;
    }
    if (best === undefined) return;
    for (const c of cands) if (c !== best && c.t.kind === "lasthit" && c.ck === "r") c.note(false, "other");
    const t = best.t;
    const creep = t.creep;
    const ok = Tasks.Start(bot, { name: "creep", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r) => finish(bot, r) }, (ctx: Lib.Ctx) =>
        ctx.lastHit({ target: creep, maxWait: t.eta + SETTINGS.WaitSlack, interruptIf: () => mateTakes(bot, creep) })
    );
    if (!ok) {
        best.note(false, "refused");
        return;
    }
    best.note(true);
    running[pid] = { cid: best.cid };
    lastCid[pid] = best.cid;
    jobLine(bot, "start", "trigger");
}

/** The row's `applies`: true while an attempt runs (the latch). The attempt starts at the read (Consider), never here. */
function rowApplies(bot: Unit): boolean {
    if (!On(bot)) return false;
    Tasks.Tick(bot);
    return running[bot.GetPlayerID()] !== undefined;
}

/** The row's verb: one frame of the attempt; true once it has ended. */
function rowStep(bot: Unit): boolean {
    if (running[bot.GetPlayerID()] === undefined) return true;
    Tasks.Step(bot, HOST);
    return running[bot.GetPlayerID()] === undefined;
}

/** The decider's row (registered in index.ts, so the decider imports no row). Soft (plan s3). */
export const ROW: Decider.Row = { name: "creep", applies: rowApplies, step: rowStep, soft: true };
