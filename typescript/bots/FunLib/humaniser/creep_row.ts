/**
 * The lane's creeps (no-creep-unpaid proposal s5; doctrine D11), a hard row of the decider with two kinds and one hold, both merged on.
 * `lh` (switch Ours.LaneCreeps): a core takes their ranged creep by a right-click, in range with a swing to spare, and with Ours.TowerCreeps
 * (slice oha-tower-creeps) their creep of any kind inside our tower's range too; trip table row `creep`
 * (pos 1 to 3; a support too with Ours.SupportCreeps, slice oha-support-creeps, their ranged creep only: its cell is above the cores', so the
 * creep must be free for it, `FreeFor`, refusals `claimed`, `wait`, `human`, and its attempt yields, `yd=1` on the end line, to a
 * lower-cell hero that holds a claim on the creep before the support's swing is ordered). `dn` (switch Ours.CreepDeny, slice oha-creep-deny): a support denies our own lane creep of any kind; trip table row
 * `deny` (pos 4 and 5). `KindOf` is the one predicate per kind; the cells, the go and the hold are shared, a deny skipping the `tower`
 * and `given` cells, and a last hit skipping `tower` with Ours.TowerCreeps.
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
 * The claim (`claims.ts`, `Reads.claims`): the decider takes it from the offer once `begin` returns and releases it when the task ends, after `finish`, whatever the end;
 * the row's per-creep answers (`Seen`) live in that read. The free rule and the yield read it (a support's last hit only).
 *
 * The leftover rule (Ours.TowerCreeps; `Verdict`): a creep one of our towers is attacking dies to a tower shot, so the hero's hit counts only if the
 * creep has at most one hit of HP (the hero's lowest roll) just before the killing shot. When it has up to two (or three) hits, the row goes at once,
 * orders one or two plain attacks (`towerAttempt`, the engine's `attackAndConfirm`, the order cancelled after each so the hero does not swing again),
 * then goes on with `lastHit` under the same hold and claim. Verdict `none` refuses (`nowindow`, or `mates` when our own creeps are attacking it) and ends a
 * running attempt whose swing is not yet ordered. A melee creep in our tower's range that the tower is not attacking is refused `notarget`.
 *
 * The cast (switch Ours.CreepSpells, slice oha-creep-spells; no-creep-unpaid proposal s6): when a read starts no attack, the row casts on
 * their lane creep of any kind that the attack cannot take (`AttackCannot`), when a unit-target spell kills it now with no walk, the reserve
 * kept, and a key spell also hits an enemy hero (`SpellSecure.CastPick`, user 27/11/2026), the creep free of our claims (`FreeFor`, any claim
 * on it) and of a teammate's hit. Any position. The verb is the engine's `cast` on the creep, hard and claimed as committed (phase `swing`)
 * until the cast's effect is seen.
 *
 * Lines: the read's `ev=choice kind=creep`, `src=own` with this row's `go` and latest `why` (and the cast's `cg`, `cw`); `ev=job job=creep`
 * start and end per attempt, with `k`.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, DamageType, Unit } from "bots/ts_libs/dota";
import * as CreepClaim from "bots/FunLib/humaniser/creep_claim";
import * as Claims from "bots/FunLib/humaniser/claims";
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
import * as SpellSecure from "bots/FunLib/humaniser/spell_secure";

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
    /**
     * Ours.CreepReserve: a decider round's length, farm's `GetDesire` for one hero (offers-and-the-decider s4, measured 27/11/2026:
     * median 0.316 s). A reserved start is offered at the round after which one more would leave less than `Margin`.
     */
    DeciderRound: 0.32,
    /**
     * Ours.CreepReserve, judgement: the spare (s) a reserved start keeps past the walk. The walk's error once the wait between rounds is
     * taken out, 90th percentile 0.41 s (cores) and 0.51 s (supports), plus the start inside a round, about 0.1 s (`wt`'s 10th
     * percentile); read 27/11/2026 over the ckpt3 and ckpt3m on arms (2,157 attempts).
     */
    Margin: 0.6,
    /** The most plain attacks (pre-hits) an attempt orders before its last hit; `Verdict` asks for at most two. */
    MaxPreHits: 2,
    /** Seconds past the estimated landing of a pre-hit before the verdict is asked again on the creep's HP. `judgement`. */
    LandSlack: 0.1,
    /** Seconds past the walk and own hit time for a pre-hit's attack to fire. CANDIDATE(preHitSlack): copies `PREHIT_SLACK` (engine/src/lane.ts, laneFarm's). */
    PreHitSlack: 0.5,
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
    /** The hero's `creep` cell is above the lowest (a support): Ours.TowerCreeps does not lift its `tower` refusal. Absent reads as false. */
    out?: boolean;
}

/**
 * The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (neither kind this hero acts on: `KindOf`),
 * `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `race` (a walk-in: an enemy hero
 * with a hit at least ours can be in range of the creep before it comes due), `covered` (a walk past NearWalk to a spot
 * an enemy hero's range covers), `tower` (a last hit inside our tower's range, unless Ours.TowerCreeps is on and the hero is not `out`), `etower`
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
    if (f.otw && f.k === "lh" && (f.out === true || !Ours.On("TowerCreeps"))) return "tower";
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

/**
 * The hero's hit cannot land before the creep dies to the others' hits: its swing is ordered no sooner than the creep comes due, the
 * hero is in range (`need`) and its attack is ready (`cd`, the engine's `cooldownLeft`), and lands `hit - cd` after the order (`hit` the
 * engine's `ownHitTime`, which counts the cooldown left already).
 */
export function AttackLate(this: void, due: number, need: number, cd: number, hit: number, dies: number): boolean {
    return math.max(due, need, cd) + (hit - cd) > dies;
}

/**
 * A lower-cell hero's answer that says it is still going for the creep: it held back for its own cast, another task or the runner, not for
 * the creep. Not `held` (stock's retreat has it) or `busy` (its attempt on another creep runs): that hero cannot take this creep now.
 */
const STILL_GOING: Record<string, boolean> = { acting: true, row: true, refused: true };

/**
 * For the cast: a hero with a lower `creep` cell has the creep on offer and its latest fresh answer says it is still going for it
 * (`STILL_GOING`). `FreeFor` reads any fresh refusal as free, which fits the support's attack (its audit) but not a cast that spends mana.
 */
function mateGoing(bot: Unit, cid: number, now: number): boolean {
    const pid = bot.GetPlayerID();
    const mine = TripTable.RankOf("creep", LaneConfig.PositionOf(bot));
    if (mine === undefined) return false;
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === null || m === undefined || m.GetPlayerID() === pid || !m.IsBot()) continue;
        const cell = TripTable.RankOf("creep", LaneConfig.PositionOf(m));
        if (cell === undefined || cell >= mine) continue;
        const a = CreepClaim.AnswerOf(m.GetPlayerID(), cid);
        if (a !== undefined && a.why !== undefined && STILL_GOING[a.why] && now - a.at <= CreepClaim.ANSWER_FRESH) return true;
    }
    return false;
}

/** The row's refusals of an attack that leave the creep to the cast: the hero cannot take it in time, or not safely. */
const CAST_OVER: Record<string, boolean> = { late: true, outdmg: true, race: true, covered: true, etower: true, tower: true, notime: true, notime_new: true, notime_held: true, notime_acting: true };

/**
 * Why the attack cannot take the creep, for the cast; undefined when it can, or when the row held back for a reason the cast shares (the hero
 * acting, another task, retreat, a claim, a teammate's hit). `why` the row's refusal this read. For a creep the row does not attack (`kind`)
 * or not yet about to come due (`early`): the cell rule on it as a last hit (`claim`, Claim's answer), the on-time check, then `late`
 * (`AttackLate`), so the cast waits while the attack may still take it.
 */
export function AttackCannot(this: void, why: string, claim: string | undefined, onTime: boolean, late: boolean): string | undefined {
    if (CAST_OVER[why]) return why;
    if (why !== "kind" && why !== "early") return undefined;
    if (claim !== undefined) return CAST_OVER[claim] ? claim : undefined;
    if (!onTime) return "notime";
    return late ? "late" : undefined;
}

export type Vd = "wait" | "prehit" | "none";

export interface Verdicted {
    vd: Vd;
    /** Tower shots before the one that kills, and the HP the creep has just before that shot (in `(0, towerHit]`). */
    shots: number;
    leftover: number;
    /** Pre-hits still needed (0 for `wait` and `none`). */
    need: number;
}

/**
 * The leftover rule, pure. `hp` the creep's HP, `towerHit` the tower's damage on it after armour, `lo` and `hi` the hero's lowest and highest hit on it
 * after armour, `period` the tower's seconds per attack, `walk` the seconds before the hero's first attack can start, `cycle` the hero's attack cycle.
 * `wait`: the creep is killable by the hero's hit just before the killing shot (leftover within `hi`: from `lo` up the verb swings only on a high roll
 * and the row leaves that to it), so the row carries on as without the rule. `prehit`: one hit now (leftover over `hi`, within `2 * lo`) or two (over
 * `2 * hi`, within `3 * lo`) leave it within one lowest hit, and the hero's attack is ready again before the last hit is needed
 * (`shots >= 1`, `shots * period - walk >= cycle * hits`). `none` otherwise.
 */
export function Verdict(this: void, hp: number, towerHit: number, lo: number, hi: number, period: number, walk: number, cycle: number): Verdicted {
    if (towerHit <= 0 || lo <= 0) return { vd: "wait", shots: 0, leftover: hp, need: 0 };
    const shots = math.max(0, math.floor((hp - 1) / towerHit));
    const leftover = hp - towerHit * shots;
    if (leftover <= hi) return { vd: "wait", shots, leftover, need: 0 };
    const need = leftover <= 2 * lo ? 1 : leftover > 2 * hi && leftover <= 3 * lo ? 2 : 0;
    if (need === 0 || shots < 1 || shots * period - walk < cycle * need) return { vd: "none", shots, leftover, need: 0 };
    return { vd: "prehit", shots, leftover, need };
}

/** What the row knows of a creep one of our towers is attacking: the facts of the verdict, the verdict, and why it is refused (`nowindow`, `mates`). */
interface TowerRead {
    tower: Unit;
    hit: number;
    v: Verdicted;
    why?: "nowindow" | "mates";
}

type Timed = Unit & { GetSecondsPerAttack?(): number; GetBaseDamageVariance?(): number };

/** Our towers near the hero, read once a read (`Consider`); the tower's target is asked per candidate. */
function ownTowers(bot: Unit): Unit[] {
    return bot.GetNearbyTowers(CreepOffer.SETTINGS.TowerRadius, false) ?? [];
}

/** A tower of ours that is attacking the creep now. */
function attackerOf(towers: Unit[], creep: Unit): Unit | undefined {
    for (const t of towers) if (t.IsAlive() && t.GetAttackTarget() === creep) return t;
    return undefined;
}

/**
 * One of our lane creeps attacks the creep: a creep's hit in the lane read (its wind-up was seen), or its attack target. Asked for a creep
 * whose verdict is `prehit` (a pre-hit then would race our creeps for the leftover) and once at the rule's first refusal mid-attempt (`tlc`).
 */
function creepsAttack(bot: Unit, creep: Unit): boolean {
    const row = LaneHits.Of(bot.GetTeam(), bot.GetAssignedLane(), creep);
    if (row !== undefined) {
        for (const h of row.forecast.hits) if (h.by === "creep" && (h.attacker as unknown as Unit).GetTeam() === bot.GetTeam()) return true;
    }
    for (const c of bot.GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false) ?? []) if (c.GetAttackTarget() === creep) return true;
    return false;
}

/**
 * The verdict on the creep's HP now. `done` the pre-hits already ordered: past `MaxPreHits` the verdict is `none`. A `prehit` becomes `none` with
 * `why=mates` when our creeps attack the creep, else `nowindow` for any `none`.
 */
function towerRead(bot: Unit, creep: Unit, tower: Unit, done: number): TowerRead {
    const hit = creep.GetActualIncomingDamage(tower.GetAttackDamage(), DamageType.Physical);
    // CANDIDATE(heroHitBounds): the hero's low and high hit copy the engine's `lowestHit` (engine/src/lasthit.ts).
    const dmg = bot.GetAttackDamage();
    const spread = (bot as Timed).GetBaseDamageVariance?.() ?? 0;
    const lo = creep.GetActualIncomingDamage(dmg - spread, DamageType.Physical);
    const hi = creep.GetActualIncomingDamage(dmg + spread, DamageType.Physical);
    const v = Verdict(creep.GetHealth(), hit, lo, hi, (tower as Timed).GetSecondsPerAttack?.() ?? 1, Need(bot, creep), CreepOffer.AttackCycle(bot));
    const r: TowerRead = { tower, hit, v };
    if (v.vd === "prehit" && done >= SETTINGS.MaxPreHits) r.v = { ...v, vd: "none", need: 0 };
    if (r.v.vd === "prehit" && creepsAttack(bot, creep)) {
        r.v = { ...v, vd: "none", need: 0 };
        r.why = "mates";
    } else if (r.v.vd === "none") r.why = "nowindow";
    return r;
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
    return r.ok === "held" || r.ok === "acting" || r.ok === "row" || r.ok === "fight" ? "notime_" + r.ok : "notime";
}

/**
 * The one predicate per kind, asked by Consider, Claim (through the facts) and dueNow alike. A last hit: their ranged creep, or with
 * Ours.TowerCreeps one of any kind inside our tower's range (`otw`), for a hero whose position does `creep` with Ours.LaneCreeps on;
 * a hero whose cell is above the lowest (a support, with Ours.SupportCreeps) takes their ranged creep only, the case its widening was audited on.
 * A deny: any of our creeps, for a hero whose position does `deny` with Ours.CreepDeny on.
 */
export function KindOf(this: void, bot: Unit, kind: string, ck: string, otw: boolean): "lh" | "dn" | undefined {
    const pos = LaneConfig.PositionOf(bot);
    if (kind === "lasthit" && lastHits(pos) && (ck === "r" || (otw && underTower(pos)))) return "lh";
    if (kind === "deny" && TripTable.Does("deny", pos) && Ours.On("CreepDeny")) return "dn";
    return undefined;
}

/** The position's `creep` cell is one it acts on: with Ours.LaneCreeps, and a cell above the lowest also needs Ours.SupportCreeps. */
function lastHits(pos: number | undefined): boolean {
    return TripTable.Does("creep", pos) && Ours.On("LaneCreeps") && (!TripTable.Outranked("creep", pos) || Ours.On("SupportCreeps"));
}

/** The under-tower hit and its leftover rule (Ours.TowerCreeps) are a lowest-cell hero's (a core's): a support's widening was audited without them. */
function underTower(pos: number | undefined): boolean {
    return Ours.On("TowerCreeps") && !TripTable.Outranked("creep", pos);
}

/**
 * `KindOf` for a candidate. Its `otw` is read from the read's fresh facts (cached for the read), and only for a last hit of a non-ranged
 * creep by a hero the under-tower hit is for (`underTower`), the one case the answer depends on it: the facts' snapshot costs more than the rest of the check.
 */
function kindOf(bot: Unit, c: CreepOffer.Candidate): "lh" | "dn" | undefined {
    const needsOtw = c.t.kind === "lasthit" && c.ck !== "r" && underTower(LaneConfig.PositionOf(bot));
    return KindOf(bot, c.t.kind, c.ck, needsOtw && c.facts().otw);
}

/** The creep is of a kind this hero acts on and about to come due at this read (the first such read is kept). */
function dueNow(bot: Unit, c: CreepOffer.Candidate, r: Seen, lead: number, now: number): boolean {
    if (kindOf(bot, c) === undefined || !Due(c.t.walk, c.t.due, lead)) return false;
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
    /** `lh` a last hit, `dn` a deny, `sp` a cast: the job lines' `k`. */
    k: "lh" | "dn" | "sp";
    /** The attempt's interrupt was a yield to a lower-cell hero's claim (`yieldsTo`), not a mate's hit: the end line's `yd`. */
    yielded?: boolean;
    /** The tower that was attacking the creep at the go (the leftover rule applies to this attempt), and the pre-hits ordered so far (the end line's `ph`). */
    tower?: Unit;
    ph: number;
    /** The leftover rule's first refusal mid-attempt (the end line's `tl`): `tgt` the tower's target is no longer the creep (or the tower is gone), else the
     *  verdict's. It ends the attempt unless `Ours.TowerStay`, which falls through to the plain last hit. */
    tl?: string;
    /** Seconds from the go to that refusal (the end line's `tlt`), and whether our creeps were attacking the creep then (`tlc`). */
    tlt?: number;
    tlc?: boolean;
}

const running: Record<number, Attempt | undefined> = {};
/** pid -> the creep of the hero's last attempt: one attempt a creep. */
const lastCid: Record<number, number | undefined> = {};

/** The candidate Consider chose, while it asks the decider to begin the row (`Decider.Offer`): what `begin` starts. */
interface Pending {
    best: CreepOffer.Candidate;
    k: "lh" | "dn" | "sp";
    /** A cast (`k` `sp`): the answer the pick chose. */
    cast?: SpellSecure.Answer;
    need: number;
    lead: number;
    now: number;
    seen: Seen;
    tr?: TowerRead;
    /** A reserved attempt's start (Ours.CreepReserve): when the reservation was taken (the start line's `rv`). */
    rvAt?: number;
}

const pending: Record<number, Pending | undefined> = {};

/**
 * Ours.CreepReserve: an attempt reserved at its go. `pd` is the latest read's view of the creep (each read refreshes it), `at` when
 * it was reserved, `why` the latest read's refusal of the creep that waits for the start round (`acting`, `held`) or is asked again
 * there (a claim's refusal).
 */
interface Reservation {
    cid: number;
    pd: Pending;
    at: number;
    why?: string;
}

const reserved: Record<number, Reservation | undefined> = {};

/** A reservation's refusals that wait: the start is not offered while one stands, and it drops only once late. */
const WAITS: Record<string, boolean> = { acting: true, held: true, fight: true };

/** An attempt the row reserves rather than starts: a right-click with no tower read (the leftover rule's pre-hits start before due), the switch on. */
function reserves(k: Pending["k"], tr: TowerRead | undefined): boolean {
    return k !== "sp" && tr === undefined && Ours.On("CreepReserve");
}

/** The spare (s) left now past the hero's walk to the reserved creep, from the latest read's need and its due (or `at`, its death). */
function slackOf(pd: Pending, now: number, at: number = pd.best.t.due): number {
    return at - pd.need - (now - pd.now);
}

/** The reservation ends without a start: the claim goes, the creep's try is not spent, and the line says why. */
function drop(bot: Unit, pid: number, rv: Reservation, why: string): void {
    reserved[pid] = undefined;
    if (pending[pid]?.rvAt !== undefined) pending[pid] = undefined;
    Decider.Unreserve(bot, ROW);
    if (!Telemetry.IsEnabled()) return;
    Telemetry.Event("job", [
        ["pid", pid],
        ["job", "creep"],
        ["k", rv.pd.k],
        ["phase", "drop"],
        ["why", why],
        ["host", HOST],
        ["cid", rv.cid],
        ["rv", r2(DotaTime() - rv.at)],
    ]);
}

/**
 * A read with a reservation: the creep is read again as any candidate (`whys`), and the reservation drops when the creep is gone
 * from the read (`gone`), no longer about to come due (`early`), not reachable before it dies (`late`: Consider's on-time test reads
 * the reserved creep's death, not its due), another task runs for
 * the hero (`row`), or our tower now attacks it (`tower`: the leftover rule starts at once, so the next read offers it). Any other
 * refusal is kept for the start round. Else the read's view replaces the reservation's. True while it stands.
 */
function keep(bot: Unit, pid: number, rv: Reservation, cands: CreepOffer.Candidate[], whys: Record<number, string | undefined>, reads: Record<number, TowerRead | undefined>, recs: Record<number, Seen>, lead: number, now: number): boolean {
    const c = cands.find((x) => x.cid === rv.cid);
    const why = c === undefined ? "gone" : whys[c.cid];
    let out: string | undefined;
    if (c === undefined) out = "gone";
    else if (why === "early" || why === "kind") out = "early";
    else if (why !== undefined && string.sub(why, 1, 6) === "notime") out = "late";
    else if (why === "row") out = "row";
    else if (reads[c.cid] !== undefined) out = "tower";
    if (out !== undefined) {
        drop(bot, pid, rv, out);
        return false;
    }
    rv.why = why;
    rv.pd = { ...rv.pd, best: c!, need: Need(bot, c!.creep), lead, now, seen: recs[c!.cid] };
    if (why === undefined) c!.note(false, "reserved");
    return true;
}

/**
 * The decider's round with a reservation: the start is offered (as `pending`, which `rowBegin` takes) once one more round would
 * leave less than `Margin`, unless a waiting refusal stands; past its due it is still offered until the hero's walk would end after
 * the creep dies (rig ladder-support dire, 27/11/2026: 9 of 14 `late` drops with no other mode were started by the same hero within 2 s, most
 * already in range, a start refused at its round having let the due pass). Late, gone, or a claim's refusal kept from the last read: dropped.
 * The creep's handle is read only through `IsNull` and `IsAlive`: the read that listed it may be a round old.
 */
function startDue(bot: Unit, pid: number, rv: Reservation): Decider.Offer | undefined {
    // A begin refused at an earlier round left its reason with the decider; the reservation's own `why` carries what matters now.
    Decider.Refusal(bot, ROW.name);
    const now = DotaTime();
    const creep = rv.pd.best.creep as Unit & { IsNull?(this: Unit): boolean };
    if ((creep.IsNull?.() ?? false) || !creep.IsAlive()) {
        drop(bot, pid, rv, "gone");
        return undefined;
    }
    if (slackOf(rv.pd, now, rv.pd.best.t.dies) < 0) {
        drop(bot, pid, rv, "late");
        return undefined;
    }
    if (slackOf(rv.pd, now) > SETTINGS.DeciderRound + SETTINGS.Margin) return undefined;
    if (rv.why !== undefined) {
        if (WAITS[rv.why] !== true) drop(bot, pid, rv, rv.why);
        return undefined;
    }
    const pd: Pending = { ...rv.pd, rvAt: rv.at };
    pending[pid] = pd;
    return offerOf(bot, pd);
}

export function ResetCache(): void {
    for (const t of [running, lastCid, pending, reserved] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
    CreepClaim.ResetCache();
    Claims.ResetCache();
}

export function On(bot: Unit): boolean {
    const pos = LaneConfig.PositionOf(bot);
    const lh = lastHits(pos);
    const dn = TripTable.Does("deny", pos) && Ours.On("CreepDeny");
    return (lh || dn || casts()) && bot.IsBot() && !Drill.Held(bot);
}

/** The cast is every position's (Ours.CreepSpells). */
function casts(): boolean {
    return Ours.On("CreepSpells");
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

export type Free = "claimed" | "wait" | "human";

/**
 * Whether the creep is free for this hero, as far as the heroes with a lower `creep` cell go; undefined when it is, else why not. A hero
 * with the lowest cell is always free, with no scan. In order: `claimed` (a lower-cell hero holds a claim on it, `Claims.ClaimsOn`),
 * then over the teammates with a lower cell: `human` (not a bot, in this hero's assigned lane: a human publishes no answers, so its
 * creep is never free) and `wait` (it has the creep on offer and has not refused it yet: its answer, `CreepClaim.AnswerOf`, has no
 * `why`). A fresh answer with a `why` is a refusal (`Consider` sets `why` on every refusal, and the next read after an attempt's end
 * gives `tried`, so a stale `why` from before a go is overtaken by the claim, then by `tried`); no answer, or a stale one, is not on offer.
 */
export function FreeFor(this: void, bot: Unit, cid: number, now: number): Free | undefined {
    const pid = bot.GetPlayerID();
    const pos = LaneConfig.PositionOf(bot);
    const mine = TripTable.RankOf("creep", pos);
    if (mine === undefined || !TripTable.Outranked("creep", pos)) return undefined;
    for (const c of Claims.ClaimsOn(Claims.CreepTarget(cid))) if (c.pid !== pid && c.k === "lh" && c.rank !== undefined && c.rank < mine) return "claimed";
    const lane = bot.GetAssignedLane();
    let wait = false;
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === null || m === undefined || m.GetPlayerID() === pid) continue;
        const cell = TripTable.RankOf("creep", LaneConfig.PositionOf(m));
        if (cell === undefined || cell >= mine) continue;
        if (!m.IsBot()) {
            if (m.GetAssignedLane() === lane) return "human";
            continue;
        }
        const a = CreepClaim.AnswerOf(m.GetPlayerID(), cid);
        if (a !== undefined && a.why === undefined && now - a.at <= CreepClaim.ANSWER_FRESH) wait = true;
    }
    return wait ? "wait" : undefined;
}

/** A lower-cell hero holds a claim on the creep this hero holds and this hero's swing is not yet ordered (a core's cell is never above a support's). */
function yieldsTo(pid: number, cid: number): boolean {
    const on = Claims.ClaimsOn(Claims.CreepTarget(cid));
    const mine = on.find((c) => c.pid === pid);
    if (mine === undefined || mine.k !== "lh" || mine.phase === "swing" || mine.rank === undefined) return false;
    const r = mine.rank;
    return on.some((c) => c.pid !== pid && c.k === "lh" && c.rank !== undefined && c.rank < r);
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
 * cycle, or `EarlyLead`), `oc` the other heroes already holding a claim on the creep (Claims.ClaimsOn, before the decider takes this one); with Ours.TowerCreeps and a tower attacking the
 * creep `lf` the creep's HP just before the killing tower shot, `tT` the tower's damage on it, `ts` the shots before that one and `vd` the verdict (`Verdict`).
 * A reserved start (Ours.CreepReserve) carries `rv`, the seconds from the reservation to the start; its walk, need and `sa` are the latest
 * read's, its due that read's less the time since.
 */
function startLine(bot: Unit, cid: number, aid: number, t: { walk: number; due: number }, g: { rv?: number; need: number; reach: number; seen: Seen; now: number; sa: boolean; lead: number; k: "lh" | "dn" | "sp"; oc: number; tr?: TowerRead; cast?: SpellSecure.Answer }): void {
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
        ["lf", g.tr === undefined ? undefined : r2(g.tr.v.leftover)],
        ["tT", g.tr === undefined ? undefined : r2(g.tr.hit)],
        ["ts", g.tr?.v.shots],
        ["vd", g.tr?.v.vd],
        ["ab", g.cast?.spell.name],
        ["al", g.cast === undefined ? undefined : r2(g.cast.timing.land)],
        ["az", g.cast?.also],
        ["am", g.cast === undefined ? undefined : math.floor(g.cast.over + 0.5)],
        ["rv", g.rv === undefined ? undefined : r2(g.rv)],
    ]);
}

/**
 * The end line: `pw`, `pq`, `ps` the seconds in each phase of the verb (walk, wait, swing), `so` the seconds from the go to the swing order (-1 none), `tk` how many times another
 * mode had the hero (a gap between steps over `Round`) and `tks` the seconds it did, `wt` the seconds from the go to the row's first step (-1 never), `tin` the seconds to first in the verb's range (-1 never), `sw` 1 when the verb ordered its swing (its message
 * is the post-swing one, which carries `end=`; absent on a cut, whose message is the runner's; 0 with `why=ok` when the hero's count
 * rose from a swing ordered before the verb's, message `hit=other`), `cl` 1 when the hero's claim on the creep was held and is released, `yd` 1 when the end was a yield (`why=interrupted`), `ph` the pre-hits ordered (an attempt the leftover rule covers; absent otherwise), `hp0`/`hp1` the hero's HP at the
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
        ["yd", a?.yielded === true ? 1 : undefined],
        ["cid", a?.cid],
        ["ph", a?.tower === undefined ? undefined : a.ph],
        ["tl", a?.tl],
        ["tlt", a?.tlt === undefined ? undefined : r2(a.tlt)],
        ["tlc", a?.tlc === undefined ? undefined : a.tlc ? 1 : 0],
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
    // The decider releases the claim after this end (its task-end hook): whether the hero held one is read here.
    const claimed = Claims.HeldBy(pid) !== undefined;
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
    return { k: kindOf(bot, c), walk: c.t.walk, slk: c.arrive.slack, eh: s.path.covering, md: s.md, ed: s.ed, ein: s.ein, erc: s.erc, ptw: s.path.tower, otw: s.otw, g2: s.given.due, kb: s.kb, out: TripTable.Outranked("creep", LaneConfig.PositionOf(bot)) };
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
    if (cands.length === 0) {
        const rv = reserved[pid];
        if (rv !== undefined) drop(bot, pid, rv, "gone");
        return;
    }
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
    // 9 of 56 never started). A running attempt is not cut by Valve's attack: the hold is hard. A start out of a fight is the
    // decider's to refuse (`fight`, Ours.FightFirst, below).
    const mode = bot.GetActiveMode();
    const held = Decider.LetGo(bot) || mode === BotMode.Retreat;
    let best: CreepOffer.Candidate | undefined;
    const tower = underTower(LaneConfig.PositionOf(bot));
    let towers: Unit[] | undefined;
    const reads: Record<number, TowerRead | undefined> = {};
    const whys: Record<number, string | undefined> = {};
    for (const c of cands) {
        let why: string | undefined;
        const r = recs[c.cid];
        const first = r.due0 === undefined;
        const k = kindOf(bot, c);
        let tr: TowerRead | undefined;
        let notarget = false;
        if (k === "lh" && tower) {
            towers ??= ownTowers(bot);
            const tw = attackerOf(towers, c.creep);
            tr = tw === undefined ? undefined : towerRead(bot, c.creep, tw, 0);
            reads[c.cid] = tr;
            // A last hit that is not ranged is inside our tower's range (`KindOf`), and the tower is not attacking it.
            notarget = tr === undefined && c.ck !== "r";
        }
        // The verdict `prehit` goes before the creep comes due: the pre-hits are what make it killable then.
        const pre = tr?.v.vd === "prehit";
        if (pre && r.due0 === undefined) r.due0 = now;
        if (k === undefined) why = "kind";
        else if (notarget) why = "notarget";
        else if (tr?.why !== undefined) why = tr.why;
        else if (!pre && !dueNow(bot, c, r, lead, now)) why = "early";
        else if (!pre && !OnTime(Need(bot, c.creep), reserved[pid]?.cid === c.cid ? c.t.dies : c.t.due)) why = noTime(r, first);
        else if (busy) why = "acting";
        else if (other) why = "row";
        else if (held) why = "held";
        else if (lastCid[pid] === c.cid) why = "tried";
        else {
            why = k === "lh" ? FreeFor(bot, c.cid, now) : undefined;
            if (why === undefined) why = Claim(factsOf(bot, c));
        }
        if (why !== undefined && why !== "kind" && why !== "early") {
            r.why = why;
            if (string.sub(why, 1, 6) !== "notime") r.ok = why;
            r.mode = why === "held" ? HDebug.ModeName(mode) : undefined;
        }
        whys[c.cid] = why;
        if (why !== undefined) c.note(false, why);
        else if (best === undefined || c.t.eta < best.t.eta) best = c;
    }
    const rv = reserved[pid];
    if (rv !== undefined && keep(bot, pid, rv, cands, whys, reads, recs, lead, now)) {
        // The hero has its plan, as when an attempt runs: no other creep and no cast.
        for (const c of cands) {
            if (c.cid === rv.cid || whys[c.cid] !== undefined || kindOf(bot, c) === undefined) continue;
            c.note(false, "busy");
            recs[c.cid].why = "busy";
        }
        return;
    }
    if (best === undefined) {
        // A creep the row does not attack is refused `kind` before the hero's own gates are asked, so the cast asks them here. With the
        // switch off the pass runs as the cast's shadow: the reference arm logs where it would have cast.
        castPass(bot, cands, whys, recs, now, busy ? "acting" : other ? "row" : held ? "held" : undefined, !casts());
        return;
    }
    for (const c of cands) {
        if (c === best || kindOf(bot, c) === undefined) continue;
        c.note(false, "other");
        recs[c.cid].why = "other";
        recs[c.cid].ok = "other";
    }
    const pd: Pending = { best, k: kindOf(bot, best)!, need: Need(bot, best.creep), lead, now, seen: recs[best.cid], tr: reads[best.cid] };
    if (reserves(pd.k, pd.tr) && slackOf(pd, now) > SETTINGS.DeciderRound + SETTINGS.Margin) {
        if (Decider.Reserve(bot, ROW, offerOf(bot, pd))) {
            reserved[pid] = { cid: best.cid, pd, at: now };
            best.note(false, "reserved");
            return;
        }
    } else {
        pending[pid] = pd;
        Decider.Offer(bot, ROW);
        if (pending[pid] === undefined) return;
        pending[pid] = undefined;
    }
    // `fight`: the decider refused the start because the hero is in a fight (Ours.FightFirst). Like `held`, a later read may clear it:
    // no claim and no `tried` are set (rowBegin's), so the creep is offered again at the next read while it is still on time.
    if (Decider.Refusal(bot, ROW.name) === "fight") {
        best.note(false, "fight");
        const r = recs[best.cid];
        r.why = "fight";
        r.ok = "fight";
        r.mode = HDebug.ModeName(mode);
        return;
    }
    // Not begun and not refused by the runner: Consider's own `other` check already turned away a row above holding the hero,
    // so what is left is an error in the row's guarded `wants`. It reads as the runner's refusal, not as another row.
    best.note(false, "refused");
    recs[best.cid].why = "refused";
}

/**
 * The cast pass, when the read starts no attack: over their creeps the attack cannot take (`AttackCannot`), the hero's gates (`gate`: `acting`,
 * `row`, `held`, as the attack's) and `tried` (the hero's last attempt was on this creep), the creep's refusals (`claimed`: a lower-cell hero's
 * `FreeFor`, or any hero of ours holding a claim on it; `mate`), then the cast's (`SpellSecure.CastPick`); the creep that dies soonest of those
 * with a cast is offered to the decider. Each creep weighed gets the cast's line fields (`noteCast`). `shadow` (Ours.CreepSpells off): the
 * creep it would cast on reads `off` and nothing is offered.
 */
function castPass(bot: Unit, cands: CreepOffer.Candidate[], whys: Record<number, string | undefined>, recs: Record<number, Seen>, now: number, gate: string | undefined, shadow: boolean): void {
    const pid = bot.GetPlayerID();
    const verbs = Tasks.Verbs()!;
    let cd: number | undefined;
    let best: CreepOffer.Candidate | undefined;
    let pick: SpellSecure.Answer | undefined;
    for (const c of cands) {
        const why = whys[c.cid];
        if (c.t.kind !== "lasthit" || why === undefined) continue;
        // A hero with no creep spell has nothing to weigh: the attack's facts are not read for it (the default arm runs this pass too).
        const as = c.spells();
        if (as.length === 0) continue;
        let claim: string | undefined;
        let onTime = true;
        let late = false;
        if (why === "kind" || why === "early") {
            claim = Claim({ ...factsOf(bot, c), k: "lh" });
            if (claim === undefined) {
                const need = Need(bot, c.creep);
                onTime = OnTime(need, c.t.due);
                if (onTime) {
                    cd ??= verbs.cooldownLeft(bot as unknown as Lib.TaskUnit);
                    late = AttackLate(c.t.due, need, cd, verbs.ownHitTime(bot as unknown as Lib.TaskUnit, c.t.creep), c.t.dies);
                }
            }
        }
        if (AttackCannot(why, claim, onTime, late) === undefined) continue;
        let no: string | undefined = gate ?? (lastCid[pid] === c.cid ? "tried" : undefined);
        if (no !== undefined) {
            c.noteCast(false, no);
            continue;
        }
        if (FreeFor(bot, c.cid, now) !== undefined || mateGoing(bot, c.cid, now) || Claims.ClaimsOn(Claims.CreepTarget(c.cid)).length > 0) no = "claimed";
        else if (c.facts().kb === "mate") no = "mate";
        let p: SpellSecure.Answer | undefined;
        if (no === undefined) {
            const r = SpellSecure.CastPick(as);
            p = r.pick;
            if (p === undefined) no = r.why;
        }
        if (p === undefined) {
            c.noteCast(false, no);
            continue;
        }
        if (best === undefined || c.t.dies < best.t.dies) {
            if (best !== undefined) best.noteCast(false, "other");
            best = c;
            pick = p;
        } else c.noteCast(false, "other");
    }
    if (best === undefined) return;
    if (shadow) {
        best.noteCast(false, "off");
        return;
    }
    pending[pid] = { best, k: "sp", cast: pick, need: 0, lead: 0, now, seen: recs[best.cid] };
    Decider.Offer(bot, ROW);
    if (pending[pid] === undefined) return;
    pending[pid] = undefined;
    best.noteCast(false, Decider.Refusal(bot, ROW.name) === "fight" ? "fight" : "refused");
}

/**
 * The leftover rule's refusal of a running attempt before its swing is ordered: the verdict is `none` now, or the tower left the creep. Noted
 * once (`refuse`); it ends the attempt only with `Ours.TowerStay` off.
 */
function towerLost(bot: Unit, pid: number): boolean {
    const a = running[pid];
    if (a === undefined || a.tower === undefined || a.so !== undefined || a.tl !== undefined) return false;
    if (towerGone(a.tower) || a.tower.GetAttackTarget() !== a.creep) return refuse(bot, a, "tgt");
    const tr = towerRead(bot, a.creep, a.tower, a.ph);
    if (tr.v.vd !== "none") return false;
    return refuse(bot, a, tr.why ?? "none");
}

/**
 * Notes the leftover rule's first refusal on the attempt, and whether our creeps were attacking the creep then (`tlc`: with the tower alone the
 * leftover cannot change, so a flip without them is the tower's damage spread or another hero); true when it ends the attempt (`Ours.TowerStay` off).
 */
function refuse(bot: Unit, a: Attempt, why: string): boolean {
    if (a.tl === undefined) {
        a.tl = why;
        a.tlt = DotaTime() - a.t0;
        a.tlc = a.creep.IsAlive() && creepsAttack(bot, a.creep);
    }
    return !Ours.On("TowerStay");
}

function towerGone(tower: Unit): boolean {
    return tower.IsNull() || !tower.IsAlive();
}

/** The pre-hit's interrupt: the tower left the creep (or fell); notes the refusal and always cuts the pre-hit. */
function towerLeft(bot: Unit, a: Attempt, creep: Unit): boolean {
    if (a.tower === undefined || (!towerGone(a.tower) && a.tower.GetAttackTarget() === creep)) return false;
    refuse(bot, a, "tgt");
    return true;
}

/**
 * The attempt of a creep a tower is attacking: while the verdict is `prehit`, one plain attack (not a last hit: the engine's `attackAndConfirm`, which
 * walks in itself), its order cancelled once it has fired or failed (an attack order outlives its one attack: engine/src/lane.ts, the pre-hit), and a
 * wait until the hit has landed so the verdict is asked on the creep's HP; then `lastHit` on the same creep. The hold and the claim are the attempt's.
 */
function* towerAttempt(ctx: Lib.Ctx, bot: Unit, pid: number, creep: Unit, opts: Lib.Verbs.LastHitOpts): Lib.TaskBody {
    while (true) {
        const a = running[pid];
        if (a === undefined || a.tower === undefined || !creep.IsAlive()) break;
        if (towerGone(a.tower) || a.tower.GetAttackTarget() !== creep) {
            if (refuse(bot, a, "tgt")) return ctx.fail("interrupted", "nowindow");
            break;
        }
        const tr = towerRead(bot, creep, a.tower, a.ph);
        if (tr.v.vd === "none") {
            if (refuse(bot, a, tr.why ?? "none")) return ctx.fail("interrupted", tr.why);
            break;
        }
        if (tr.v.vd === "wait") break;
        const walk = Need(bot, creep);
        const hitIn = Tasks.Verbs()!.ownHitTime(bot as unknown as Lib.TaskUnit, creep as unknown as Lib.TaskCreep);
        const landAt = ctx.now() + walk + hitIn + SETTINGS.LandSlack;
        a.ph++;
        const r = yield* ctx.attackAndConfirm(() => (creep.IsAlive() ? (creep as unknown as Lib.TaskCreep) : undefined), {
            findFor: 0,
            confirmFor: walk + hitIn + SETTINGS.PreHitSlack,
            aggroConfirms: false,
            hold: "creep_prehit",
            interruptIf: () => mateTakes(bot, creep) || towerLeft(bot, a, creep),
        });
        bot.Action_MoveToLocation(bot.GetLocation());
        if (!r.success && !(a.tl === "tgt" && Ours.On("TowerStay"))) return r;
        if (!r.success) break;
        while (ctx.now() < landAt && creep.IsAlive()) yield;
    }
    return yield* ctx.lastHit(opts);
}

/** The row's `begin`: starts the attempt on the creep Consider chose, at the read's moment. */
function rowBegin(bot: Unit): boolean {
    const pid = bot.GetPlayerID();
    const pd = pending[pid];
    pending[pid] = undefined;
    if (pd === undefined) return false;
    const { best, k, need, lead, now, tr, cast } = pd;
    const rv = pd.rvAt !== undefined ? reserved[pid] : undefined;
    const t = best.t;
    const creep = t.creep;
    // A reserved start comes at a round after the read that last saw the creep: its due and eta are that much nearer.
    const age = DotaTime() - now;
    const ability = cast === undefined ? undefined : bot.GetAbilityByName(cast.spell.name);
    if (k === "sp" && (ability === undefined || ability === null)) {
        best.noteCast(false, "refused");
        return false;
    }
    const ok = Tasks.Start(bot, { name: "creep", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (r) => finish(bot, r) }, (ctx: Lib.Ctx) => {
        // The cast lands after its flight; the verb ends once its effect (cooldown or mana) is seen, and the creep's fate is the result.
        if (k === "sp") return ctx.cast(ability as unknown as Lib.TaskAbility, { target: creep, timeout: cast!.timing.land + 1 });
        const opts = { target: creep, maxWait: math.max(0, t.eta - age) + SETTINGS.WaitSlack, interruptIf: () => mateTakes(bot, creep) || yieldNow(pid, best.cid) || towerLost(bot, pid), onPhase: (p: Lib.Verbs.LastHitPhase, at: number) => onPhase(pid, p, at) };
        if (k === "dn") return ctx.deny(opts);
        if (tr === undefined) return ctx.lastHit(opts);
        return towerAttempt(ctx, bot, pid, creep as unknown as Unit, opts);
    });
    if (!ok) {
        if (k === "sp") best.noteCast(false, "refused");
        else {
            best.note(false, "refused");
            pd.seen.why = "refused";
        }
        if (rv !== undefined) drop(bot, pid, rv, "refused");
        return false;
    }
    if (rv !== undefined) reserved[pid] = undefined;
    const aid = Telemetry.NextAid(pid);
    if (k === "sp") best.noteCast(true, undefined, aid);
    else best.note(true, undefined, aid);
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
        tower: tr?.tower,
        ph: 0,
    };
    running[pid] = a;
    lastCid[pid] = best.cid;
    // The decider takes the claim (`offerOf`'s) once this begin returns; the heroes already holding it are counted now.
    let oc = 0;
    for (const c of Claims.ClaimsOn(Claims.CreepTarget(best.cid))) if (c.pid !== pid) oc++;
    const sa = bot.GetAttackTarget();
    startLine(bot, best.cid, aid, { walk: t.walk, due: t.due - age }, { rv: pd.rvAt === undefined ? undefined : t0 - pd.rvAt, need, reach: CreepOffer.Reach(bot, best.creep), seen: pd.seen, now, sa: sa !== null && sa !== undefined && sa === creep, lead, k, oc, tr, cast });
    return true;
}

/** The attempt's interrupt for a yield: flags the attempt so its end line says so. */
function yieldNow(pid: number, cid: number): boolean {
    if (!yieldsTo(pid, cid)) return false;
    const a = running[pid];
    if (a !== undefined) a.yielded = true;
    return true;
}

/** The verb's phase change, from the engine's onPhase (the phase times of the end line). */
function onPhase(pid: number, p: Lib.Verbs.LastHitPhase, t: number): void {
    const a = running[pid];
    if (a !== undefined) enterPhase(a, p, t);
    Claims.Phase(pid, p);
}

/**
 * The row's `wants`: an offer while an attempt runs (the latch), and while Consider offers its chosen creep to the decider. The
 * row decides at the read (Consider); with a reservation (Ours.CreepReserve) the decider's round offers its start (`startDue`).
 */
function rowWants(bot: Unit, _reads: Reads): Decider.Offer | undefined {
    if (!On(bot)) return undefined;
    Tasks.Tick(bot);
    const pid = bot.GetPlayerID();
    const a = running[pid];
    if (a !== undefined) return { tgt: `creep:${a.cid}` };
    const rv = reserved[pid];
    if (rv !== undefined) {
        // A start offered at an earlier round and refused there is asked afresh.
        pending[pid] = undefined;
        return startDue(bot, pid, rv);
    }
    const pd = pending[pid];
    if (pd === undefined) return undefined;
    return offerOf(bot, pd);
}

const WAY: Record<Pending["k"], string> = { lh: "attack", dn: "deny", sp: "spell" };

/**
 * The pending attempt's offer: its creep, the time to go by, the way, and the claim the decider takes at the begin (the hero's
 * cell, the kind, the time its swing or cast is due). A cast goes at the read that chose it (its window is now, not the attack's
 * due) and is committed from its order, so its claim starts in `swing` and no lower-cell hero's start makes it yield (`yieldsTo`).
 */
function offerOf(bot: Unit, pd: Pending): Decider.Offer {
    const { best, k } = pd;
    const rank = TripTable.RankOf(k === "dn" ? "deny" : "creep", LaneConfig.PositionOf(bot));
    const due = pd.now + (k === "sp" ? pd.cast!.timing.land : best.t.due);
    return {
        tgt: Claims.CreepTarget(best.cid),
        by: k === "sp" ? pd.now : pd.now + best.t.due - pd.need,
        way: WAY[k],
        claim: { rank, k: k === "dn" ? "dn" : "lh", due, phase: k === "sp" ? "swing" : undefined },
    };
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
