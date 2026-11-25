/**
 * The lane's creeps, first group (no-creep-unpaid proposal s5; doctrine D11; switch Ours.LaneCreeps), a soft row of the
 * decider: a core takes their ranged creep by a right-click, in range with a swing to spare. Which positions act is
 * `states/trip_table`'s `creep` row (pos 1 to 3; supports wait for the core-first margin, proposal s3).
 *
 * The cells were named with the user from step 2's table (25/11/2026): near (in range or a walk up to NearWalk, not
 * out-damaged) and far and free (a longer walk with no enemy hero's range on the stand spot). The decision is taken at the
 * creep offer read (`creep_offer.ts`, every 0.2 s a hero), on that read's facts: the read hands its candidates in through
 * SetRow, so a creep's handle is only called on a read that lists it. `Claim` is the cell rule on the facts; the row goes on
 * the claimed creep closest to due once it is about to come due (`Due`), whether or not stock is attacking it: the row's swing
 * landed as often as stock's (53 of 69 with a swing on, oha-creep-ranged), so taking stock's swing costs nothing.
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
    /** Enemy heroes with a hit at least ours that can be in range of the creep before it comes due (the race). */
    erc: number;
    ptw: boolean;
    otw: boolean;
    g2: number;
    kb: string;
}

/**
 * The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (not their ranged creep),
 * `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `race` (a walk-in: an enemy hero
 * with a hit at least ours can be in range of the creep before it comes due), `covered` (a walk past NearWalk to a spot
 * an enemy hero's range covers), `tower` (inside our tower's range: the under-tower hit is a later widening, s6), `etower`
 * (the stand spot is inside their tower's), `given` (a walk-in: another target comes due where the hero stands before it is back),
 * `mate` (a teammate's hit kills it first).
 */
export function Claim(this: void, f: Facts): string | undefined {
    if (f.kind !== "lasthit" || f.ck !== "r") return "kind";
    if (f.slk <= 0) return "late";
    if (f.ein > 0 && f.ed > f.md) return "outdmg";
    // Round 1 (rig cr1: walk-ins landed 17 of 51, 23 denied by a lane opponent not yet in range when the row went). In range
    // the hero is there first: 8 of 11 landed, none denied.
    if (f.walk > 0 && f.erc > 0) return "race";
    if (f.walk > SETTINGS.NearWalk && f.eh > 0) return "covered";
    if (f.otw) return "tower";
    if (f.ptw) return "etower";
    // In range there is no walk, so nothing is given up: which creep to swing at is the row's pick (Consider).
    if (f.walk > 0 && f.g2 > 0) return "given";
    if (f.kb === "mate") return "mate";
    return undefined;
}

/**
 * About to come due: due within the walk plus `lead`, one own attack cycle (`GetSecondsPerAttack`), so the hero is in range and
 * facing with a full cycle to spare whatever its cooldown. Round 0 of oha-creep-ranged went at walk + 0.4 s and lost 48 of
 * 122 uncut attempts with no swing on the creep (re-read 25/11/2026). The creep offer asks laneTargets for creeps due within
 * at least one cycle (`CreepOffer.Within`), so such a creep is offered by then.
 */
export function Due(this: void, walk: number, due: number, lead: number): boolean {
    return due <= walk + lead;
}

/**
 * Seconds until the hero can order its swing from inside the verb's own range: the walk to `bot.GetAttackRange()` of the creep's
 * centre (lastHit's `why=range` test; the offer's `walk` uses a wider range, which cost a median 0.3 s on cearly1) at the hero's
 * current move speed. No wind-up, flight or turn: `due` already counts them between the order and the hit (the engine's
 * `ownHit`), so it is the time to the order.
 */
export function Need(this: void, bot: Unit, creep: Unit): number {
    const at = creep.GetLocation();
    const me = bot.GetLocation();
    const dx = at.x - me.x;
    const dy = at.y - me.y;
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    return math.max(0, math.sqrt(dx * dx + dy * dy) - bot.GetAttackRange()) / speed;
}

/** The creep comes due no sooner than the hero can be in the verb's range (`need`, `Need`). */
export function OnTime(this: void, need: number, due: number): boolean {
    return due >= need;
}

/** What the reads saw of one creep for one hero; dropped once a read no longer lists the creep. */
interface Seen {
    /** The read's time when it was last listed (the prune's mark). */
    at: number;
    first: number;
    /** The first read where the creep was about to come due (`Due`). */
    due0?: number;
    /** The last reason the row refused it at a read where it was about to come due, and the hero's mode name then when that was `held`. */
    why?: string;
    mode?: string;
}

const seen: Record<number, Record<number, Seen> | undefined> = {};

/** The record of each listed creep, new ones made now; records of creeps this read does not list are dropped. */
function touch(pid: number, cands: CreepOffer.Candidate[], now: number): Record<number, Seen> {
    let m = seen[pid];
    if (m === undefined) {
        m = {};
        seen[pid] = m;
    }
    for (const c of cands) {
        const r = m[c.cid];
        if (r === undefined) m[c.cid] = { at: now, first: now };
        else r.at = now;
    }
    for (const [cid, r] of pairs(m)) if (r.at !== now) delete m[cid as number];
    return m;
}

/** The creep is a ranged one of theirs to last-hit and about to come due at this read (the first such read is kept). */
function dueNow(c: CreepOffer.Candidate, r: Seen, lead: number, now: number): boolean {
    if (c.t.kind !== "lasthit" || c.ck !== "r" || !Due(c.t.walk, c.t.due, lead)) return false;
    if (r.due0 === undefined) r.due0 = now;
    return true;
}

interface Attempt {
    cid: number;
    creep: Unit;
    t0: number;
    hp0: number;
    /** Seconds from the start to the first step that ended inside the verb's range (lastHit's own test: centre distance against attack range). */
    tin?: number;
}

const running: Record<number, Attempt | undefined> = {};
/** pid -> the creep of the hero's last attempt: one attempt a creep. */
const lastCid: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, lastCid, seen] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
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

function r2(x: number): number {
    return math.floor(x * 100 + 0.5) / 100;
}

/**
 * The start line: the creep (`cid`, as on the read's line and `creep_death`), the walk and due at go, the hero's attack range, and
 * what the reads saw: `gn` the need at go and `sp` the spare (due less need), `hw` and `hm` the last refusal while about to come
 * due and the hero's mode then (absent when it went at the first such read), `hs` seconds from that first read to the go, `sa` 1
 * when the hero's attack target was the creep, `nw` 1 when this read was the first to list the creep.
 */
function startLine(bot: Unit, cid: number, t: { walk: number; due: number }, g: { need: number; seen: Seen; now: number; sa: boolean }): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "creep"],
        ["phase", "start"],
        ["why", "trigger"],
        ["host", HOST],
        ["cid", cid],
        ["gw", r2(t.walk)],
        ["gd", r2(t.due)],
        ["rng", math.floor(bot.GetAttackRange())],
        ["gn", r2(g.need)],
        ["sp", r2(t.due - g.need)],
        ["hw", g.seen.why],
        ["hm", g.seen.mode],
        ["hs", r2(g.now - (g.seen.due0 ?? g.now))],
        ["sa", g.sa ? 1 : 0],
        ["nw", g.seen.first === g.now ? 1 : 0],
    ]);
}

/**
 * The end line: `tin` the seconds to first in the verb's range (-1 never), `sw` 1 when the verb ordered its swing (its message
 * is the post-swing one, which carries `end=`; absent on a cut, whose message is the runner's), `hp0`/`hp1` the hero's HP at the
 * start and end, `msg` the verb's message (what the swing was based on, or what held it).
 */
function endLine(bot: Unit, a: Attempt | undefined, r: Lib.Result, cut: string | undefined): void {
    const msg = r.message;
    let sw: number | undefined;
    if (r.success) sw = 1;
    else if (r.reason !== "preempted" && msg !== undefined) sw = string.find(msg, " end=", 1, true)[0] !== undefined ? 1 : 0;
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "creep"],
        ["phase", "end"],
        ["why", r.success ? "ok" : r.reason],
        ["host", HOST],
        ["cut", cut],
        ["cid", a?.cid],
        ["tin", a === undefined ? undefined : a.tin !== undefined ? r2(a.tin) : -1],
        ["sw", sw],
        ["hp0", a?.hp0],
        ["hp1", math.floor(bot.GetHealth())],
        ["msg", msg],
    ]);
}

/** As the pull's: an attempt the engine ends because the host lost the hero names what took it. */
function cutBy(bot: Unit, r: Lib.Result): string | undefined {
    if (r.success || r.reason !== "preempted") return undefined;
    if (Decider.LetGo(bot) || bot.GetActiveMode() === BotMode.Retreat) return "retreat";
    return HDebug.ModeName(bot.GetActiveMode());
}

function finish(bot: Unit, r: Lib.Result): void {
    const pid = bot.GetPlayerID();
    const a = running[pid];
    running[pid] = undefined;
    endLine(bot, a, r, cutBy(bot, r));
}

function factsOf(c: CreepOffer.Candidate): Facts {
    const s = c.facts();
    return { kind: c.t.kind, ck: c.ck, walk: c.t.walk, slk: c.arrive.slack, eh: s.path.covering, md: s.md, ed: s.ed, ein: s.ein, erc: s.erc, ptw: s.path.tower, otw: s.otw, g2: s.given.due, kb: s.kb };
}

/**
 * The read's hook (CreepOffer.SetRow), at each read of a hero: notes why each candidate is not taken and starts an attempt on
 * the claimed creep closest to due. Reasons asked before the facts are read: `busy` (an attempt runs), `kind`, `early` (not
 * yet about to come due), `acting`, `held` (Valve's attack or stock's retreat holds the hero: a later read may still go),
 * `tried` (this creep's attempt has ended); then Claim's;
 * `refused` (the task runner said no). The last of these reasons given while the creep was about to come due is kept per hero
 * and creep (`Seen`), with the hero's mode when it was `held`, and goes out on the start line (`hw`, `hm`).
 */
export function Consider(this: void, bot: Unit, cands: CreepOffer.Candidate[]): void {
    if (!On(bot)) return;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const lead = CreepOffer.AttackCycle(bot);
    const recs = touch(pid, cands, now);
    if (running[pid] !== undefined) {
        for (const c of cands) {
            const r = recs[c.cid];
            if (dueNow(c, r, lead, now)) {
                r.why = "busy";
                r.mode = undefined;
            }
            c.note(false, "busy");
        }
        return;
    }
    if (Tasks.Jobs() === undefined) return;
    const busy = acting(bot);
    // Round 2 (rig ce1: 9 of 56 attempts never started): the soft hold cannot take the hero from Valve's attack or stock's
    // retreat, so an attempt started then is cut before its first step and spends the creep's one try.
    const mode = bot.GetActiveMode();
    const held = Decider.LetGo(bot) || mode === BotMode.Attack || mode === BotMode.Retreat;
    let best: CreepOffer.Candidate | undefined;
    for (const c of cands) {
        let why: string | undefined;
        const r = recs[c.cid];
        if (c.t.kind !== "lasthit" || c.ck !== "r") why = "kind";
        else if (!dueNow(c, r, lead, now)) why = "early";
        else if (busy) why = "acting";
        else if (held) why = "held";
        else if (lastCid[pid] === c.cid) why = "tried";
        else why = Claim(factsOf(c));
        if (why !== undefined && why !== "kind" && why !== "early") {
            r.why = why;
            r.mode = why === "held" ? HDebug.ModeName(mode) : undefined;
        }
        if (why !== undefined) c.note(false, why);
        else if (best === undefined || c.t.eta < best.t.eta) best = c;
    }
    if (best === undefined) return;
    for (const c of cands) {
        if (c === best || c.t.kind !== "lasthit" || c.ck !== "r") continue;
        c.note(false, "other");
        if (recs[c.cid].due0 !== undefined) recs[c.cid].why = "other";
    }
    const t = best.t;
    const creep = t.creep;
    const need = Need(bot, best.creep);
    const ok = Tasks.Start(bot, { name: "creep", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r) => finish(bot, r) }, (ctx: Lib.Ctx) =>
        ctx.lastHit({ target: creep, maxWait: t.eta + SETTINGS.WaitSlack, interruptIf: () => mateTakes(bot, creep) })
    );
    if (!ok) {
        best.note(false, "refused");
        recs[best.cid].why = "refused";
        return;
    }
    best.note(true);
    running[pid] = { cid: best.cid, creep: best.creep, t0: DotaTime(), hp0: math.floor(bot.GetHealth()) };
    lastCid[pid] = best.cid;
    const sa = bot.GetAttackTarget();
    startLine(bot, best.cid, t, { need, seen: recs[best.cid], now, sa: sa !== null && sa !== undefined && sa === creep });
}

/** The row's `applies`: true while an attempt runs (the latch). The attempt starts at the read (Consider), never here. */
function rowApplies(bot: Unit): boolean {
    if (!On(bot)) return false;
    Tasks.Tick(bot);
    return running[bot.GetPlayerID()] !== undefined;
}

/** The row's verb: one frame of the attempt; true once it has ended. */
function rowStep(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    if (running[pid] === undefined) return true;
    Tasks.Step(bot, HOST);
    const a = running[pid];
    if (a === undefined) return true;
    // Still running after the step: the verb read the creep this frame and found it alive, so its handle may be called.
    if (a.tin === undefined) {
        const at = a.creep.GetLocation();
        const me = bot.GetLocation();
        if (at !== undefined && at !== null) {
            const dx = at.x - me.x;
            const dy = at.y - me.y;
            if (math.sqrt(dx * dx + dy * dy) <= bot.GetAttackRange()) a.tin = DotaTime() - a.t0;
        }
    }
    return false;
}

/** The decider's row (registered in index.ts, so the decider imports no row). Soft (plan s3). */
export const ROW: Decider.Row = { name: "creep", applies: rowApplies, step: rowStep, soft: true };
