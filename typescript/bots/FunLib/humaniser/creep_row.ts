/**
 * The lane's creeps (no-creep-unpaid proposal s5; doctrine D11), a hard row of the decider with two kinds and one hold, both merged on.
 * `lh` (switch Ours.LaneCreeps): a core takes their ranged creep by a right-click, in range with a swing to spare; trip table row `creep`
 * (pos 1 to 3). `dn` (switch Ours.CreepDeny, slice oha-creep-deny): a support denies our own lane creep of any kind; trip table row
 * `deny` (pos 4 and 5). `KindOf` is the one predicate per kind; the cells, the go and the hold are shared, a deny skipping the `tower`
 * and `given` cells.
 *
 * The cells were named with the user from step 2's table (25/11/2026): near (in range or a walk up to NearWalk, not
 * out-damaged) and far and free (a longer walk with no enemy hero's range on the stand spot). The decision is taken at the
 * creep offer read (`creep_offer.ts`, every 0.2 s a hero), on that read's facts: the read hands its candidates in through
 * SetRow, so a creep's handle is only called on a read that lists it. `Claim` is the cell rule on the facts; the row goes on
 * the claimed creep closest to due once it is about to come due (`Due`), whether or not stock is attacking it: the row's swing
 * landed as often as stock's (53 of 69 with a swing on, oha-creep-ranged), so taking stock's swing costs nothing. It never starts
 * while another task runs for the hero (a pull or stack: the runner would replace it), reason `row`.
 *
 * On time: it goes only while the creep comes due no sooner than the hero can be in the verb's range (`OnTime`, `Need`); else it
 * refuses and the hero stays stock's, and a later read may still go. Of 152 attempts on cearly1 the 62 that began with under 0.25 s
 * to spare landed 12 times, the 90 with more 46.
 *
 * The verb is the engine's `lastHit` (`lh`) or `deny` (`dn`) on that creep (it walks into range, waits and swings when its hit kills);
 * the attempt latches the hold until the task ends (the creep dies, the hit lands, the wait runs out), then the hero is stock's again.
 * Hard from the go: the hold is the decider's HARD, so Valve's attack, item, evasive and defend-ally do
 * not take the hero; stock's retreat lets go first (the decider's `retreatLeads`, which a hard hold is under too).
 *
 * The claim (`creep_claim.ts`, `Reads.creep`): the attempt takes it in `begin` and the task's end releases it (`finish`), whatever the end;
 * the row's per-creep answers (`Seen`) live in that read. Nothing reads the claim to decide yet.
 *
 * Lines: the read's `ev=choice kind=creep`, `src=own` with this row's `go` and latest `why`; `ev=job job=creep` start and end
 * per attempt, with `k`.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Unit } from "bots/ts_libs/dota";
import * as CreepClaim from "bots/FunLib/humaniser/creep_claim";
import * as CreepOffer from "bots/FunLib/humaniser/creep_offer";
import * as Decider from "bots/FunLib/humaniser/decider";
import type { Reads } from "bots/FunLib/humaniser/reads";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as LaneHits from "bots/FunLib/humaniser/lane_hits";
import * as Ours from "bots/FunLib/humaniser/ours";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";

export const SETTINGS = {
    /** The longest walk (s) in the near cell; past it a covered stand spot is refused (step 2's table split, proposal s5). */
    NearWalk: 1.0,
    /** The wait for the creep to come due, after its eta: laneFarm's own (`maxWait` eta + 1.5 s, engine/docs/API.md). `judgement`. */
    WaitSlack: 1.5,
    /**
     * judgement: the row may go once the creep comes due within the walk plus this (s), or one attack cycle when that is longer.
     * Earlier means more creeps seen in time (43 refusals in six games were creeps not yet offered, due in about 1.6 s with 2.5 s of walk), but
     * a longer hold on a creep that may die to another hit or be taken by a mate before the hero is in reach.
     */
    EarlyLead: 3,
    /** The decider's round (s) as the row meets it: a gap between the row's steps longer than it means another mode had the hero (`tk`). */
    Round: 0.4,
};

/** The mode the decider hosts its rows in: the engine steps the attempt's task under it. */
const HOST = BotMode.Farm;

/** The offer's facts the cell rule reads (the read's snapshot, or a fixture's). */
export interface Facts {
    /** The creep's kind for this hero: `lh` a last hit, `dn` a deny, undefined neither (`KindOf`). */
    k: "lh" | "dn" | undefined;
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
 * The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (neither kind this hero acts on: `KindOf`),
 * `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `race` (a walk-in: an enemy hero
 * with a hit at least ours can be in range of the creep before it comes due), `covered` (a walk past NearWalk to a spot
 * an enemy hero's range covers), `tower` (inside our tower's range: the under-tower hit is a later widening, s6), `etower`
 * (the stand spot is inside their tower's), `given` (a walk-in: another target comes due where the hero stands before it is back),
 * `mate` (a teammate's hit kills it first). A deny skips `tower` (our tower is no hazard to our own creep) and `given` (a support's
 * other targets are the ranking, a later slice's).
 */
export function Claim(this: void, f: Facts): string | undefined {
    if (f.k === undefined) return "kind";
    if (f.slk <= 0) return "late";
    if (f.ein > 0 && f.ed > f.md) return "outdmg";
    // Round 1 (rig cr1: walk-ins landed 17 of 51, 23 denied by a lane opponent not yet in range when the row went). In range
    // the hero is there first: 8 of 11 landed, none denied.
    if (f.walk > 0 && f.erc > 0) return "race";
    if (f.walk > SETTINGS.NearWalk && f.eh > 0) return "covered";
    if (f.otw && f.k === "lh") return "tower";
    if (f.ptw) return "etower";
    // In range there is no walk, so nothing is given up: which creep to swing at is the row's pick (Consider).
    if (f.walk > 0 && f.g2 > 0 && f.k === "lh") return "given";
    if (f.kb === "mate") return "mate";
    return undefined;
}

/**
 * About to come due: due within the walk plus `lead` (`Lead`: the longer of one own attack cycle, `GetSecondsPerAttack`, and `EarlyLead`), so the hero is in range and
 * facing with a full cycle to spare whatever its cooldown. Round 0 of oha-creep-ranged went at walk + 0.4 s and lost 48 of
 * 122 uncut attempts with no swing on the creep (re-read 25/11/2026). The creep offer asks laneTargets for creeps due within
 * at least one cycle (`CreepOffer.Within`), so such a creep is offered by then.
 */
export function Due(this: void, walk: number, due: number, lead: number): boolean {
    return due <= walk + lead;
}

/**
 * Seconds until the hero can order its swing from inside the verb's own range: the walk to the engine's `attackReach` of the creep
 * (lastHit's `why=range` test, which the offer's `walk` also reads) at the hero's current move speed. No wind-up, flight or turn: `due`
 * already counts them between the order and the hit (the engine's `ownHit`), so it is the time to the order.
 */
export function Need(this: void, bot: Unit, creep: Unit): number {
    const at = creep.GetLocation();
    const me = bot.GetLocation();
    const dx = at.x - me.x;
    const dy = at.y - me.y;
    return math.max(0, math.sqrt(dx * dx + dy * dy) - CreepOffer.Reach(bot, creep)) / math.max(100, bot.GetCurrentMovementSpeed());
}

/** The creep comes due no sooner than the hero can be in the verb's range (`need`, `Need`). */
export function OnTime(this: void, need: number, due: number): boolean {
    return due >= need;
}

type Seen = CreepClaim.Answer;

/** The record of each listed creep, new ones made now; records of creeps this read does not list are dropped (the claim read's). */
function touch(pid: number, cands: CreepOffer.Candidate[], now: number): Record<number, Seen> {
    const cids: number[] = [];
    for (const c of cands) cids.push(c.cid);
    return CreepClaim.Touch(pid, cids, now);
}

/** Why the on-time check refused: at the creep's first read about to come due, after a refusal on time for `held` or `acting`, or neither. */
function noTime(r: Seen, first: boolean): string {
    if (first) return "notime_new";
    return r.ok === "held" || r.ok === "acting" || r.ok === "row" ? "notime_" + r.ok : "notime";
}

/**
 * The one predicate per kind, asked by Consider, Claim (through the facts) and dueNow alike. A last hit: their ranged creep, for a hero whose
 * position does `creep` with Ours.LaneCreeps on. A deny: any of our creeps, for a hero whose position does `deny` with Ours.CreepDeny on.
 */
export function KindOf(this: void, bot: Unit, kind: string, ck: string): "lh" | "dn" | undefined {
    const pos = LaneConfig.PositionOf(bot);
    if (kind === "lasthit" && ck === "r" && TripTable.Does("creep", pos) && Ours.On("LaneCreeps")) return "lh";
    if (kind === "deny" && TripTable.Does("deny", pos) && Ours.On("CreepDeny")) return "dn";
    return undefined;
}

/** The creep is of a kind this hero acts on and about to come due at this read (the first such read is kept). */
function dueNow(bot: Unit, c: CreepOffer.Candidate, r: Seen, lead: number, now: number): boolean {
    if (KindOf(bot, c.t.kind, c.ck) === undefined || !Due(c.t.walk, c.t.due, lead)) return false;
    if (r.due0 === undefined) r.due0 = now;
    return true;
}

interface Attempt {
    cid: number;
    creep: Unit;
    t0: number;
    hp0: number;
    /** Seconds from the start to the first step that ended inside the verb's range (lastHit's own test: centre distance against the engine's attackReach). */
    tin?: number;
    /** Attempt id (Telemetry.NextAid), on the go choice line and the job lines. */
    aid: number;
    /** Seconds from the start to the row's first step (the wait for the host mode's next call); undefined until it steps. */
    wt?: number;
    /** The verb's phase now and when it began (the engine's onPhase); undefined before it reports one. */
    phase?: Lib.Verbs.LastHitPhase;
    phaseAt: number;
    /** Seconds spent in each phase so far (the open phase is added at the end). */
    spent: Record<string, number>;
    /** Seconds from the go to the verb's swing order (the `swing` phase); undefined until then. */
    so?: number;
    /** The time of the last step; a gap over `Round` is another mode having the hero. `tk` times and `tks` seconds so far. */
    lastStep?: number;
    tk: number;
    tks: number;
    /** `lh` a last hit, `dn` a deny: the job lines' `k`. */
    k: "lh" | "dn";
}

const running: Record<number, Attempt | undefined> = {};
/** pid -> the creep of the hero's last attempt: one attempt a creep. */
const lastCid: Record<number, number | undefined> = {};

/** The candidate Consider chose, while it asks the decider to begin the row (`Decider.Offer`): what `begin` starts. */
interface Pending {
    best: CreepOffer.Candidate;
    k: "lh" | "dn";
    need: number;
    lead: number;
    now: number;
    seen: Seen;
}

const pending: Record<number, Pending | undefined> = {};

export function ResetCache(): void {
    for (const t of [running, lastCid, pending] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
    CreepClaim.ResetCache();
}

export function On(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    const lh = TripTable.Does("creep", pos) && Ours.On("LaneCreeps");
    const dn = TripTable.Does("deny", pos) && Ours.On("CreepDeny");
    return (lh || dn) && bot.IsBot() && !Drill.Held(bot);
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

function enterPhase(a: Attempt, p: Lib.Verbs.LastHitPhase, t: number): void {
    if (a.phase !== undefined) a.spent[a.phase] += t - a.phaseAt;
    a.phase = p;
    a.phaseAt = t;
    if (p === "swing" && a.so === undefined) a.so = t - a.t0;
}

/**
 * The start line: the creep (`cid`, as on the read's line and `creep_death`), the walk and due at go, the hero's attack range (`rng`)
 * and the engine's reach on the creep (`rch`), and
 * what the reads saw: `gn` the need at go and `sp` the spare (due less need), `hw` and `hm` the last refusal while about to come
 * due and the hero's mode then (absent when it went at the first such read), `hs` seconds from that first read to the go, `sa` 1
 * when the hero's attack target was the creep, `nw` 1 when this read was the first to list the creep, `k` `lh` or `dn`, `ld` the lead in force (s: one attack
 * cycle, or `EarlyLead`), `oc` the other heroes already holding a claim on the creep (CreepClaim.Take).
 */
function startLine(bot: Unit, cid: number, aid: number, t: { walk: number; due: number }, g: { need: number; reach: number; seen: Seen; now: number; sa: boolean; lead: number; k: "lh" | "dn"; oc: number }): void {
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["aid", aid],
        ["job", "creep"],
        ["k", g.k],
        ["phase", "start"],
        ["why", "trigger"],
        ["host", HOST],
        ["cid", cid],
        ["gw", r2(t.walk)],
        ["gd", r2(t.due)],
        ["rng", math.floor(bot.GetAttackRange())],
        ["rch", math.floor(g.reach)],
        ["gn", r2(g.need)],
        ["sp", r2(t.due - g.need)],
        ["hw", g.seen.why],
        ["hm", g.seen.mode],
        ["hs", r2(g.now - (g.seen.due0 ?? g.now))],
        ["sa", g.sa ? 1 : 0],
        ["nw", g.seen.first === g.now ? 1 : 0],
        ["ld", r2(g.lead)],
        ["oc", g.oc],
    ]);
}

/**
 * The end line: `pw`, `pq`, `ps` the seconds in each phase of the verb (walk, wait, swing), `so` the seconds from the go to the swing order (-1 none), `tk` how many times another
 * mode had the hero (a gap between steps over `Round`) and `tks` the seconds it did, `wt` the seconds from the go to the row's first step (-1 never), `tin` the seconds to first in the verb's range (-1 never), `sw` 1 when the verb ordered its swing (its message
 * is the post-swing one, which carries `end=`; absent on a cut, whose message is the runner's; 0 with `why=ok` when the hero's count
 * rose from a swing ordered before the verb's, message `hit=other`), `cl` 1 when the hero's claim on the creep was held and is released, `hp0`/`hp1` the hero's HP at the
 * start and end, `msg` the verb's message (what the swing was based on, or what held it).
 */
function endLine(bot: Unit, a: Attempt | undefined, r: Lib.Result, cut: string | undefined, claimed: boolean): void {
    const msg = r.message;
    let sw: number | undefined;
    if (r.success) sw = msg !== undefined && string.find(msg, "hit=other", 1, true)[0] === 1 ? 0 : 1;
    else if (r.reason !== "preempted" && msg !== undefined) sw = string.find(msg, " end=", 1, true)[0] !== undefined ? 1 : 0;
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["aid", a?.aid],
        ["job", "creep"],
        ["k", a?.k],
        ["phase", "end"],
        ["why", r.success ? "ok" : r.reason],
        ["host", HOST],
        ["cut", cut],
        ["cl", claimed ? 1 : 0],
        ["cid", a?.cid],
        ["so", a === undefined ? undefined : a.so !== undefined ? r2(a.so) : -1],
        ["tk", a?.tk],
        ["tks", a === undefined ? undefined : r2(a.tks)],
        ["pw", a === undefined ? undefined : r2(a.spent.walk)],
        ["pq", a === undefined ? undefined : r2(a.spent.wait)],
        ["ps", a === undefined ? undefined : r2(a.spent.swing)],
        ["wt", a === undefined ? undefined : a.wt !== undefined ? r2(a.wt) : -1],
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
    const claimed = CreepClaim.Release(pid);
    const now = DotaTime();
    if (a !== undefined) {
        if (a.phase !== undefined) a.spent[a.phase] += now - a.phaseAt;
        // Ended while another mode still had the hero (the runner's preempt): that absence counts too.
        if (a.lastStep !== undefined && now - a.lastStep > SETTINGS.Round) {
            a.tk++;
            a.tks += now - a.lastStep;
        }
    }
    endLine(bot, a, r, cutBy(bot, r), claimed);
}

function factsOf(bot: Unit, c: CreepOffer.Candidate): Facts {
    const s = c.facts();
    return { k: KindOf(bot, c.t.kind, c.ck), walk: c.t.walk, slk: c.arrive.slack, eh: s.path.covering, md: s.md, ed: s.ed, ein: s.ein, erc: s.erc, ptw: s.path.tower, otw: s.otw, g2: s.given.due, kb: s.kb };
}

/**
 * The lead (s) the row goes on: a creep due within the walk plus this is about to come due (`Due`). One own attack cycle, or `EarlyLead` when
 * that is longer.
 */
export function Lead(this: void, bot: Unit): number {
    return math.max(CreepOffer.AttackCycle(bot), SETTINGS.EarlyLead);
}

/** What the read asks laneTargets to offer (`within`) for a hero the row acts on: the lead, so a creep is listed by the time the row may go. 0: the read's own. */
export function OfferLead(this: void, bot: Unit): number {
    return On(bot) ? SETTINGS.EarlyLead : 0;
}

/**
 * The read's hook (CreepOffer.SetRow), at each read of a hero: notes why each candidate is not taken and starts an attempt on
 * the claimed creep closest to due. Reasons asked before the facts are read: `busy` (an attempt runs), `kind`, `early` (not
 * yet about to come due), `acting`, `row` (another task runs for the hero: a pull or stack), `held` (stock's retreat holds the hero: a later read may still go),
 * `tried` (this creep's attempt has ended); then Claim's;
 * `notime_new`, `notime_held`, `notime_acting`, `notime` (the hero cannot be in the verb's range before the creep comes due: at the
 * creep's first read about to come due, after a refusal on time for `held` or `acting`, or neither; asked after `early`).
 * The chosen creep is then offered to the decider (`Decider.Offer`), which begins the row at once unless a row above holds the
 * hero; `refused` when the task runner said no or the decider did not begin it. The last of these reasons given while the creep was about to come due is kept per hero
 * and creep (`Seen`), with the hero's mode when it was `held`, and goes out on the start line (`hw`, `hm`).
 */
export function Consider(this: void, bot: Unit, cands: CreepOffer.Candidate[]): void {
    if (!On(bot)) return;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const lead = Lead(bot);
    const recs = touch(pid, cands, now);
    if (cands.length === 0) return;
    if (running[pid] !== undefined) {
        for (const c of cands) {
            const r = recs[c.cid];
            if (dueNow(bot, c, r, lead, now)) {
                r.why = "busy";
                r.mode = undefined;
            }
            c.note(false, "busy");
        }
        return;
    }
    if (Tasks.Jobs() === undefined) return;
    const busy = acting(bot);
    // Starting a task replaces the hero's running one (the engine's `replaced`): a pull or stack in progress is not ours to take. The
    // runner's current task is asked, not the decider's Held: Held names the row that held the hero at its last round, while the runner's
    // task is what Start would replace, whichever row or job started it.
    const other = Tasks.Running(bot) !== undefined;
    // An attempt started while stock's retreat holds the hero is cut before its first step and spends the creep's one try (rig ce1:
    // 9 of 56 never started). Valve's attack no longer does: the hold is hard.
    const mode = bot.GetActiveMode();
    const held = Decider.LetGo(bot) || mode === BotMode.Retreat;
    let best: CreepOffer.Candidate | undefined;
    for (const c of cands) {
        let why: string | undefined;
        const r = recs[c.cid];
        const first = r.due0 === undefined;
        if (KindOf(bot, c.t.kind, c.ck) === undefined) why = "kind";
        else if (!dueNow(bot, c, r, lead, now)) why = "early";
        else if (!OnTime(Need(bot, c.creep), c.t.due)) why = noTime(r, first);
        else if (busy) why = "acting";
        else if (other) why = "row";
        else if (held) why = "held";
        else if (lastCid[pid] === c.cid) why = "tried";
        else why = Claim(factsOf(bot, c));
        if (why !== undefined && why !== "kind" && why !== "early") {
            r.why = why;
            if (string.sub(why, 1, 6) !== "notime") r.ok = why;
            r.mode = why === "held" ? HDebug.ModeName(mode) : undefined;
        }
        if (why !== undefined) c.note(false, why);
        else if (best === undefined || c.t.eta < best.t.eta) best = c;
    }
    if (best === undefined) return;
    for (const c of cands) {
        if (c === best || KindOf(bot, c.t.kind, c.ck) === undefined) continue;
        c.note(false, "other");
        recs[c.cid].why = "other";
        recs[c.cid].ok = "other";
    }
    pending[pid] = { best, k: KindOf(bot, best.t.kind, best.ck)!, need: Need(bot, best.creep), lead, now, seen: recs[best.cid] };
    Decider.Offer(bot, ROW);
    if (pending[pid] === undefined) return;
    // Not begun and not refused by the runner: Consider's own `other` check already turned away a row above holding the hero,
    // so what is left is an error in the row's guarded `wants`. It reads as the runner's refusal, not as another row.
    pending[pid] = undefined;
    best.note(false, "refused");
    recs[best.cid].why = "refused";
}

/** The row's `begin`: starts the attempt on the creep Consider chose, at the read's moment. */
function rowBegin(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const pd = pending[pid];
    pending[pid] = undefined;
    if (pd === undefined) return false;
    const { best, k, need, lead, now } = pd;
    const t = best.t;
    const creep = t.creep;
    const ok = Tasks.Start(bot, { name: "creep", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r) => finish(bot, r) }, (ctx: Lib.Ctx) => {
        const opts = { target: creep, maxWait: t.eta + SETTINGS.WaitSlack, interruptIf: () => mateTakes(bot, creep), onPhase: (p: Lib.Verbs.LastHitPhase, at: number) => onPhase(pid, p, at) };
        if (k === "dn") return ctx.deny(opts);
        return ctx.lastHit(opts);
    });
    if (!ok) {
        best.note(false, "refused");
        pd.seen.why = "refused";
        return false;
    }
    const aid = Telemetry.NextAid(pid);
    best.note(true, undefined, aid);
    const t0 = DotaTime();
    const a: Attempt = {
        cid: best.cid,
        creep: best.creep,
        t0,
        hp0: math.floor(bot.GetHealth()),
        aid,
        phaseAt: t0,
        spent: { walk: 0, wait: 0, swing: 0 },
        tk: 0,
        tks: 0,
        k,
    };
    running[pid] = a;
    lastCid[pid] = best.cid;
    const rank = TripTable.RankOf(k === "dn" ? "deny" : "creep", LaneConfig.PositionOf(bot));
    const others = CreepClaim.Take(best.cid, { pid, rank: rank!, k, due: pd.now + t.due });
    const sa = bot.GetAttackTarget();
    startLine(bot, best.cid, aid, t, { need, reach: CreepOffer.Reach(bot, best.creep), seen: pd.seen, now, sa: sa !== null && sa !== undefined && sa === creep, lead, k, oc: others.length });
    return true;
}

/** The verb's phase change, from the engine's onPhase (the phase times of the end line). */
function onPhase(pid: number, p: Lib.Verbs.LastHitPhase, t: number): void {
    const a = running[pid];
    if (a !== undefined) enterPhase(a, p, t);
    CreepClaim.Phase(pid, p);
}

/**
 * The row's `wants`: an offer while an attempt runs (the latch), and while Consider offers its chosen creep to the decider. The
 * row decides at the read (Consider), never at the decider's round.
 */
function rowWants(bot: Unit, _reads: Reads): Decider.Offer | undefined {
    if (!On(bot)) return undefined;
    Tasks.Tick(bot);
    const pid = bot.GetPlayerID();
    const a = running[pid];
    if (a !== undefined) return { tgt: `creep:${a.cid}` };
    const pd = pending[pid];
    if (pd === undefined) return undefined;
    return { tgt: `creep:${pd.best.cid}`, by: pd.now + pd.best.t.due - pd.need };
}

/** The row's verb: one frame of the attempt; true once it has ended. */
function rowStep(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const first = running[pid];
    if (first === undefined) return true;
    const now = DotaTime();
    if (first.wt === undefined) first.wt = now - first.t0;
    // The host mode steps the verb every frame it has the hero: a longer gap is another mode having it.
    if (first.lastStep !== undefined && now - first.lastStep > SETTINGS.Round) {
        first.tk++;
        first.tks += now - first.lastStep;
    }
    first.lastStep = now;
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
            if (math.sqrt(dx * dx + dy * dy) <= CreepOffer.Reach(bot, a.creep)) a.tin = DotaTime() - a.t0;
        }
    }
    return false;
}

/** The decider's row (registered in index.ts, so the decider imports no row). Hard (plan s3). */
export const ROW: Decider.Row = { name: "creep", wants: rowWants, begin: rowBegin, step: rowStep };
