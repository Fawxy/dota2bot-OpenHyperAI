/**
 * Trade: one decision for the hero-on-hero exchange in lane (design docs/proposals/2026-11-19-trade-decision-design.md in the
 * master repo, D18, D19, D24, D10). `Decide` is pure over `Inputs`: no unit handles, no game calls, so a logged cut replays
 * offline. One function for all five positions: the role is logged, never read.
 *
 * Per candidate (an enemy hero within 1,600) the levels are tried in the order join (a play's target), join (the pair's
 * target; a kill on it comes first), kill, hit back, hit; a gate that fails at one level drops to the next, and a candidate
 * that gets no level reports the first gate that failed. Across candidates the higher level wins (section 3 of the design).
 * A running exchange (`Inputs.run`) is the same decision with slack on its own bars, plus the ends of section 2.
 */
import { BotMode, DamageType, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import * as CoreLastHit from "bots/FunLib/humaniser/states/core_last_hit";
import * as SupportDeny from "bots/FunLib/humaniser/states/support_deny";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as CreepAggro from "bots/FunLib/humaniser/creep_aggro";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Laning from "bots/FunLib/humaniser/states/laning";
import * as PairJoin from "bots/FunLib/humaniser/pair_join";
import * as Plays from "bots/FunLib/humaniser/plays/plays";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";

export type Level = "none" | "hit" | "hitback" | "kill" | "join";
export type Source = "pair" | "play";

/**
 * Every number the decision owns, with its source. The burst and HP bars live in `Threat.SETTINGS` (StandBurst 1 / PackBurst
 * 0.5 and StandHp 0.5 / PackHp 0.7, banked h2hstand1) and the unseen bar is its `MissingRefuse` (0.5, the 425 graded rows):
 * read at call time, not copied.
 */
const BARS = {
    /** A target at this HP share or less is a kill candidate. Banked `@lane_encounters` on cil5, lposchk3, sspotchk1: 11 kills and no deaths per 100 encounters with the lowest enemy at 40% or less, 1.8 and 1.8 at 41-70%. */
    commitHp: 0.4,
    /** Enemy lane creeps within 500 above which a hit or hit back is vetoed (EC-045, `judgement`), and for a kill the more than one full wave of D19's "a big enemy wave" (`judgement`). */
    waveHit: 3,
    waveKill: 5,
    /** Enemy creeps attacking us (a tower counts 2) at which a hit or hit back is vetoed: already tanking (`judgement`). */
    creeps: 2,
    /** A running exchange's slack on its own bars: HP share, burst, and one more creep in the wave (`judgement`). */
    slackHp: 0.05,
    slackBurst: 0.05,
    slackWave: 1,
    /** `losing`: HP share lost beyond the target's since our first landed hit (LOSING_BY, user 03/11/2026), and before it (UNLANDED_CAP, banked h2hhighhit2: 42 of 50 no-damage `losing` ends had lost under 120 HP). */
    losing: 0.05,
    unlandedCap: 0.15,
    /** A running kill ends on this many failed catch reads at least `catchGap` s apart (design section 2, `judgement`). */
    catchFails: 2,
    catchGap: 0.5,
    /** The window the catch read sums our damage over when the target is not heading for its tower (CATCH_WINDOW, `judgement`: a fitted 5.7 s window ended 94 of 124 kills in the smoke game within 0.3 s). */
    catchWindow: 30,
    /** The default horizon of `Arrives` (s): 1 s of walking plus an attack point (WALK_IN, `judgement`). A kill and a join do not ask it: the catch read and the pair or play reach decide their walk. */
    walkIn: 1.5,
    /**
     * The walk a hit or hit back pays for follows its value (coordinator, 19/11/2026; the step-4 smoke game: 267 of 579 hits ended
     * `no_reach`, 195 of them after 0.1 s, opened at a gap of 474 on a target walking towards us that then turned): a hit opens only
     * if we reach attack range within `walkHit` s with the target's approach not credited (only its retreat counts against us), and
     * a running one is judged on `walkHit + slackWalk` so it does not end on the frame the target takes a step. While it steps out
     * of the creeps, `no_clear` bounds it.
     */
    walkHit: 0.5,
    slackWalk: 0.5,
    /** The pair join acts on a target within this of us (D10: about 4 s of walking), and a play's target within our reach plus this (JOIN_WALK: about 2 s, `judgement`). */
    pairReach: 1200,
    playWalk: 600,
    /** Our range this far over the target's makes a hit free (OUTRANGE; necrolyte on dragon knight 400 and sniper on zeus 170 are free, oracle on lion 20 and dazzle on necrolyte 75 are not; `judgement`). */
    outrange: 100,
    /** Logged backstops, never the rule: an offer attack mode did not take (LOST_AFTER), a step out that has not cleared the creeps (STEP_OUT_LIMIT), a chase (CHASE_BACKSTOP; T1: a time limit is a backstop only). */
    notTaken: 1,
    noClear: 2,
    chase: 30,
};

export interface Read3 {
    burst: number;
    n: number;
    missing: number;
}

/** One hero of ours on the target, as the catch read sees it. */
export interface Hunter {
    /** Distance to the target's place (seen, or the predicted place while unseen). */
    d: number;
    /** Attack range plus both hulls. */
    reach: number;
    /** How fast the distance shrinks: our speed less the target's speed away from us (units/s). */
    close: number;
    /** Attack damage per second on the target, after its armour. */
    dps: number;
    /** Ready damage spells: reach, cast point (s) and damage on the target after its resistances. */
    spells: { range: number; cp: number; dmg: number }[];
}

interface Catch {
    ok: boolean;
    /** Damage the hunters land within the window. */
    dmg: number;
    /** Seconds until the first of it (math.huge: none). */
    first: number;
    /** The window used: seconds until the target reaches its own tower's reach (the catch window when not heading there). */
    safe: number;
}

function arrive(d: number, r: number, close: number): number {
    if (d <= r) return 0;
    return close > 0 ? (d - r) / close : math.huge;
}

/** Each hunter's attacks from the moment it is in attack range to the end of `w`, and each ready spell it reaches in time, against the target's HP. */
export function CatchRead(hunters: Hunter[], thpAbs: number, w: number = BARS.catchWindow): Catch {
    let dmg = 0;
    let first = math.huge;
    for (const h of hunters) {
        const ta = arrive(h.d, h.reach, h.close);
        if (ta < w) {
            dmg += h.dps * (w - ta);
            first = math.min(first, ta);
        }
        for (const s of h.spells) {
            const ts = arrive(h.d, s.range, h.close) + s.cp;
            if (ts > w) continue;
            dmg += s.dmg;
            first = math.min(first, ts);
        }
    }
    return { ok: dmg >= thpAbs, dmg, first, safe: w };
}

/** Whether a hero at `gap` (distance past attack range plus both hulls, 0 or less in range) is in range within `horizon` s when the target moves `away` (signed; towards us is negative) and we run at `ms`. */
export function Arrives(gap: number, ms: number, away: number, horizon: number = BARS.walkIn): boolean {
    if (gap <= 0) return true;
    const closing = ms - away;
    return closing > 0 && gap <= closing * horizon;
}

/** A hit with no answer coming back: the target swings at a lane creep, or our range is `outrange` or more over its. */
export function Free(targetLastHitting: boolean, range: number, targetRange: number): boolean {
    return targetLastHitting || range >= targetRange + BARS.outrange;
}

/** HP lost beyond what the target lost since the baseline, over our max HP (positive: losing). Absolute HP, so a big hero is not judged against a small one's fractions. */
export function Deficit(hp0: number, hp: number, thp0: number, thp: number, maxHp: number): number {
    return (hp0 - hp - (thp0 - thp)) / math.max(1, maxHp);
}

interface Cand {
    pid: number;
    /** Its HP share and HP. */
    thp: number;
    thpAbs: number;
    /** Distance to us, and past our attack range plus both hulls (0 or less in range). */
    d: number;
    gap: number;
    /** Its speed away from us along the line between us (negative: towards). */
    away: number;
    /** It damaged us in the last second. */
    hitting: boolean;
    /** It swings at a lane creep, or our range is `outrange` over its. */
    free: boolean;
    /** Our 3 s damage on it over its HP, and its on us over ours. */
    ko: number;
    kt: number;
    /** It stands in our creeps' aggro. */
    paid: boolean;
    /** Our attack point on it is inside an enemy tower's reach. */
    tw: boolean;
    /** The threat read along the walk to it over `Threat.SETTINGS.GateHorizon`, asked for a kill or join; absent: the read here stands in. */
    walk?: Read3;
    /** The catch read on it, asked for a kill candidate; absent: no kill. */
    catch?: Catch;
    /** The hunters behind `catch`, kept for the cut line only. */
    hunters?: Hunter[];
    /** An exchange with it ended `losing` and neither has damaged the other since for `StayEngaged` (the executor's memory; a read, not a timer): no hit and no hit back on it. */
    lost?: boolean;
}

export interface Run {
    level: Exclude<Level, "none">;
    target: number;
    source?: Source;
    /** The target is alive (IsHeroAlive); a seen one is among `cands`. */
    alive: boolean;
    /** Seconds since the offer, and since attack mode took it (absent: not taken yet). */
    offered: number;
    started?: number;
    /** Our first hit has landed, and `Deficit` from its baseline (before it, from the start). */
    landed: boolean;
    soFar: number;
    /** Failed catch reads so far, and the time of the last (a kill). */
    catchFails: number;
    catchFailAt?: number;
    /** Seconds the current step out of the creeps has run (absent: not stepping out). */
    stepFor?: number;
    /** A kill whose target is unseen: where the chase walks, the reads of the walk there, and the catch read on its last HP. */
    chaseAt?: { x: number; y: number };
    unseen?: { at: boolean; tower: boolean; threat: boolean };
    catch?: Catch;
}

export interface Inputs {
    now: number;
    /** Our HP share. */
    hp: number;
    /** Our movement speed. */
    ms: number;
    /** The threat read here over `StayHorizon` (a hitter over `StayEngaged`): their damage on us over our HP, the enemy heroes that reach us, the unseen weight. */
    burst: number;
    n: number;
    missing: number;
    /** A tower is attacking us. */
    towerOnMe: boolean;
    /** Enemy lane creeps attacking us (a tower counts 2), and enemy lane creeps within 500. */
    creepsOnMe: number;
    wave: number;
    /** The laning body is offered a deny now. */
    denyDue: boolean;
    /** The pair answer (PairJoin.For): its target and both kill shares; `dec` is logged only. */
    pair?: { tgt: number; ko: number; kt: number; dec: string };
    /** A running play near us we may join: its target and its hard zero for us. */
    play?: { id: number; kind: string; tgt: number; zero?: string };
    cands: Cand[];
    run?: Run;
}

export interface How {
    verb: "attack" | "move";
    aggro: "free" | "commit";
    at?: { x: number; y: number };
}

export interface Answer {
    level: Level;
    target?: number;
    source?: Source;
    how?: How;
    /** The rule that decided; for `none`, the first gate that failed (or the end that stopped a running exchange). */
    reason: string;
    /** Why the running exchange ended this frame, if it did (`higher`: another candidate won the order). */
    ended?: string;
    /** A running kill's failed catch reads after this frame, and when the last was. */
    catchFails?: number;
    catchFailAt?: number;
}

const RANK: Record<Level, number> = { none: 0, hit: 1, hitback: 2, kill: 3, join: 4 };

interface Pick {
    level: Level;
    source?: Source;
    reason: string;
    /** Orders a kill on the pair's target level with the pair join. */
    rank: number;
}

const burstBar = (n: number): number => (n >= 2 ? Threat.SETTINGS.PackBurst : Threat.SETTINGS.StandBurst);
const hpBar = (n: number): number => (n >= 2 ? Threat.SETTINGS.PackHp : Threat.SETTINGS.StandHp);

function pairOn(i: Inputs, c: Cand): boolean {
    return i.pair !== undefined && i.pair.tgt === c.pid && i.pair.ko > i.pair.kt;
}

function playOn(i: Inputs, c: Cand): boolean {
    return i.play !== undefined && i.play.tgt === c.pid && i.play.zero === undefined;
}

/** A running kill's catch state this frame: failures so far, when the last was, and whether it has ended on them. */
function catchState(i: Inputs, run: Run, ok: boolean): { fails: number; at?: number; ended: boolean } {
    if (ok) return { fails: 0, ended: false };
    if (run.catchFails === 0 || run.catchFailAt === undefined) return { fails: 1, at: i.now, ended: BARS.catchFails <= 1 };
    if (i.now - run.catchFailAt >= BARS.catchGap) return { fails: run.catchFails + 1, at: i.now, ended: run.catchFails + 1 >= BARS.catchFails };
    return { fails: run.catchFails, at: run.catchFailAt, ended: false };
}

/** The gates of one level on one candidate in the bars table's order: the first that fails, or undefined. `run` is set for the running exchange's own target (the slack). */
function gate(i: Inputs, c: Cand, level: Exclude<Level, "none">, src: Source | undefined, run: Run | undefined): string | undefined {
    if (i.towerOnMe || c.tw) return "tower";
    const walks = level === "kill" || level === "join";
    const r: Read3 = walks && c.walk !== undefined ? c.walk : { burst: i.burst, n: i.n, missing: i.missing };
    const slack = run !== undefined;
    if (r.burst >= burstBar(r.n) + (slack ? BARS.slackBurst : 0)) return "burst";
    if (!walks && i.hp < hpBar(i.n) - (slack ? BARS.slackHp : 0)) return "hp";
    if (!walks && c.lost === true) return "lost";
    if (walks && r.missing >= Threat.SETTINGS.MissingRefuse) return "missing";
    const wave = slack ? BARS.slackWave : 0;
    if (level === "kill") {
        const cs = c.catch;
        if (cs === undefined) return "catch";
        if (!cs.ok && !(run !== undefined && run.level === "kill" && !catchState(i, run, false).ended)) return "catch";
        if (i.wave > BARS.waveKill + wave) return "wave";
        return undefined;
    }
    if (level === "join") {
        if (src === "pair" ? c.d > BARS.pairReach : c.gap > BARS.playWalk) return "no_reach";
        return undefined;
    }
    if (!(c.free || c.ko > c.kt || (level === "hitback" && c.paid))) return "unfavoured";
    if (run?.stepFor === undefined && !Arrives(c.gap, i.ms, math.max(0, c.away), BARS.walkHit + (slack ? BARS.slackWalk : 0))) return "no_reach";
    if (i.denyDue) return "deny";
    if (i.creepsOnMe >= BARS.creeps) return "creeps";
    if (i.wave > BARS.waveHit + wave) return "wave";
    return undefined;
}

/** The level one candidate gets, trying the rules in order; or `none` with the first gate that failed. */
function pickFor(i: Inputs, c: Cand, run: Run | undefined): Pick {
    let first: string | undefined;
    const fail = (why: string | undefined): boolean => {
        if (why === undefined) return false;
        first = first ?? why;
        return true;
    };
    const killable = c.thp <= BARS.commitHp || (run !== undefined && run.level === "kill");
    if (playOn(i, c) && !fail(gate(i, c, "join", "play", run))) return { level: "join", source: "play", reason: "play", rank: 5 };
    const pair = pairOn(i, c);
    if (pair) {
        if (killable && !fail(gate(i, c, "kill", "pair", run))) return { level: "kill", source: "pair", reason: "pair", rank: 4 };
        if (!fail(gate(i, c, "join", "pair", run))) return { level: "join", source: "pair", reason: "pair", rank: 4 };
    } else if (killable && !fail(gate(i, c, "kill", undefined, run))) return { level: "kill", reason: "kill", rank: 3 };
    if (c.hitting && !fail(gate(i, c, "hitback", undefined, run))) return { level: "hitback", reason: "hitback", rank: 2 };
    if (!fail(gate(i, c, "hit", undefined, run))) return { level: "hit", reason: "hit", rank: 1 };
    return { level: "none", reason: first ?? "none", rank: 0 };
}

/** `a` is the better target of two candidates at the same rank: kill on the lowest HP, hit back on the nearest, hit on a free one then the smallest gap, a join on the nearest. */
function before(a: { c: Cand; p: Pick }, b: { c: Cand; p: Pick }): boolean {
    if (a.p.rank !== b.p.rank) return a.p.rank > b.p.rank;
    if (a.p.level === "kill") return a.c.thp < b.c.thp;
    if (a.p.level === "hit") {
        if (a.c.free !== b.c.free) return a.c.free;
        return a.c.gap < b.c.gap;
    }
    return a.c.d < b.c.d;
}

function howOf(level: Level, run: Run | undefined, seen: boolean): How | undefined {
    if (level === "none") return undefined;
    if (level === "hit" || level === "hitback") return { verb: "attack", aggro: "free" };
    if (!seen && run !== undefined && run.chaseAt !== undefined) return { verb: "move", aggro: "commit", at: run.chaseAt };
    return { verb: "attack", aggro: "commit" };
}

/** Ends that exclude the target from this frame's fresh choice: the exchange did not fail a gate, it stopped. */
const STOPS: Record<string, boolean | undefined> = {
    target_dead: true,
    target_lost: true,
    not_taken: true,
    no_clear: true,
    backstop: true,
    losing: true,
    cannot_catch: true,
    spot_clear: true,
    utower: true,
    threat: true,
};

/** What ends the running exchange besides a gate of its own level, or undefined. */
function endOf(i: Inputs, run: Run, t: Cand | undefined): string | undefined {
    if (!run.alive) return "target_dead";
    if (run.started === undefined && run.offered > BARS.notTaken) return "not_taken";
    if (run.stepFor !== undefined && run.stepFor > BARS.noClear) return "no_clear";
    if (run.level === "kill" && run.started !== undefined && run.started > BARS.chase) return "backstop";
    if (t === undefined) {
        if (run.level !== "kill") return "target_lost";
        const u = run.unseen;
        if (u !== undefined) {
            if (u.at) return "spot_clear";
            if (u.tower) return "utower";
            if (u.threat) return "threat";
        }
        if (run.catch !== undefined && catchState(i, run, run.catch.ok).ended) return "cannot_catch";
        return undefined;
    }
    if (run.level === "hit" || run.level === "hitback") {
        if (run.soFar > (run.landed ? BARS.losing : BARS.unlandedCap)) return "losing";
    }
    if (run.level === "join") {
        if (run.source === "pair" && !pairOn(i, t)) return "pair_end";
        if (run.source === "play" && !playOn(i, t)) return "play_end";
    }
    if (run.level === "kill" && t.catch !== undefined && catchState(i, run, t.catch.ok).ended) return "cannot_catch";
    return undefined;
}

function answerOf(i: Inputs, pid: number, c: Cand | undefined, p: Pick, run: Run | undefined, ended: string | undefined, reason?: string): Answer {
    const a: Answer = { level: p.level, target: pid, source: p.source, how: howOf(p.level, run, c !== undefined), reason: reason ?? p.reason, ended };
    if (p.level === "kill" && run !== undefined && run.level === "kill" && run.target === pid) {
        const cs = catchState(i, run, c?.catch?.ok ?? true);
        a.catchFails = cs.fails;
        a.catchFailAt = cs.at;
    }
    return a;
}

/** The frame's answer: the level and target, how, and why, over `i`. */
export function Decide(i: Inputs): Answer {
    const run = i.run;
    let ended: string | undefined;
    let exclude: number | undefined;
    let kept: { c: Cand | undefined; p: Pick } | undefined;
    if (run !== undefined) {
        const t = i.cands.find((c) => c.pid === run.target);
        ended = endOf(i, run, t);
        if (ended === undefined && t === undefined) {
            const p: Pick = { level: "kill", reason: "chase", rank: 3 };
            kept = { c: undefined, p };
        } else if (ended === undefined) {
            const own = gate(i, t!, run.level, run.source, run);
            const p = pickFor(i, t!, run);
            if (own !== undefined) ended = own;
            else if (p.level === "none") ended = p.reason;
            else kept = { c: t, p };
        }
        if (ended !== undefined && STOPS[ended] === true) exclude = run.target;
    }
    const rest: { c: Cand; p: Pick }[] = [];
    for (const c of i.cands) {
        if (kept !== undefined && kept.c === c) continue;
        if (c.pid === exclude) continue;
        rest.push({ c, p: pickFor(i, c, undefined) });
    }
    let best: { c: Cand; p: Pick } | undefined;
    for (const r of rest) if (r.p.level !== "none" && (best === undefined || before(r, best))) best = r;
    if (kept !== undefined) {
        if (best === undefined || best.p.rank <= kept.p.rank) {
            const upReason = kept.c !== undefined && RANK[kept.p.level] > RANK[run!.level] ? (kept.p.level === "kill" ? "kill_up" : "level_up") : undefined;
            return answerOf(i, run!.target, kept.c, kept.p, run, undefined, upReason);
        }
        return answerOf(i, best.c.pid, best.c, best.p, undefined, "higher");
    }
    if (best !== undefined) return answerOf(i, best.c.pid, best.c, best.p, undefined, ended);
    return { level: "none", reason: noneReason(rest, ended), ended };
}

/** The reason of a frame with no answer: the end that stopped a running exchange, else the nearest candidate's first failed gate. */
function noneReason(rest: { c: Cand; p: Pick }[], ended: string | undefined): string {
    if (ended !== undefined) return ended;
    let near: { c: Cand; p: Pick } | undefined;
    for (const r of rest) if (near === undefined || r.c.d < near.c.d) near = r;
    return near === undefined ? "no_target" : near.p.reason;
}

/**
 * What holds retreat (design section 1, "Hold"), over the inputs (`Holds` reads them for a hero): `hitback` while some hitter passes tower, burst and HP and is either paid or
 * free or favoured, whatever the swing is doing (a due deny, creeps and the wave change the swing, not the hold); `join`
 * while some candidate is a pair join. Undefined: retreat decides alone.
 */
export function HoldsOf(i: Inputs): "hitback" | "join" | undefined {
    const run = i.run;
    for (const c of i.cands) {
        const slack = run !== undefined && run.target === c.pid ? run : undefined;
        if (!c.hitting || i.towerOnMe || c.tw) continue;
        if (i.burst >= burstBar(i.n) + (slack !== undefined ? BARS.slackBurst : 0)) continue;
        if (i.hp < hpBar(i.n) - (slack !== undefined ? BARS.slackHp : 0)) continue;
        if (c.paid || c.free || c.ko > c.kt) return "hitback";
    }
    for (const c of i.cands) {
        const slack = run !== undefined && run.target === c.pid ? run : undefined;
        if (pairOn(i, c) && gate(i, c, "join", "pair", slack) === undefined) return "join";
    }
    return undefined;
}

/** Enemy heroes within this of us are candidates: past any laning hero's attack range and its walk-in. */
const CAND_RADIUS = 1600;
/** Enemy lane creeps within this of us count as the wave and turn on a hero attacker (EC-053: lane creeps acquire a hero attacker within about 500). */
const CREEP_RADIUS = 500;
/** A hero hit us "recently" within this (s): Threat.SETTINGS.EngagedRecent's value. */
const HIT_RECENT = 1;
/** Seconds between the two places a target's velocity is read from, and the age past which a sample is no velocity (a target seen again after a gap). `judgement`. */
const HEADING_SPAN = 0.5;
const HEADING_STALE = 1.5;
/** Within this of the predicted place (past both hulls) the chaser stands on it and the trail is cold (`judgement`: a step). */
const AT_PLACE = 100;

interface Sample {
    x: number;
    y: number;
    at: number;
}

/** Per enemy hero: samples of its place a HEADING_SPAN or more apart, newest `s1` and the one before it. */
const heads: Record<number, { s0?: Sample; s1?: Sample } | undefined> = {};

function noteSeen(pid: number, l: Vector, now: number): void {
    const h = (heads[pid] = heads[pid] ?? {});
    if (h.s1 !== undefined && now - h.s1.at < HEADING_SPAN) return;
    h.s0 = h.s1;
    h.s1 = { x: l.x, y: l.y, at: now };
}

/** The hero's velocity (units/s) from its movement since the sample before last; 0 when unknown. */
function velocityOf(pid: number, l: Vector, now: number): LuaMultiReturn<[number, number]> {
    const s0 = heads[pid]?.s0;
    if (s0 === undefined || now - s0.at > HEADING_STALE) return $multi(0, 0);
    const dt = math.max(0.01, now - s0.at);
    return $multi((l.x - s0.x) / dt, (l.y - s0.y) / dt);
}

/** What the unseen chase needs of a target when it last was seen. */
interface LastSeen {
    vx: number;
    vy: number;
    physF: number;
    magF: number;
    hull: number;
    thpAbs: number;
}
const lastSeen: Record<number, LastSeen | undefined> = {};

/** The enemy hero handles Gather saw on its last call, by pid: the executor reads them straight after it. */
const lastHandles: Record<number, Unit | undefined> = {};

/** The last pair answer that was a join (per bot) and when, for the Keep window. */
const lastPair: Record<number, { p: NonNullable<Inputs["pair"]>; at: number } | undefined> = {};

/** Heroes we lost an exchange with, per bot: set when one ends `losing`, cleared once neither has damaged the other for StayEngaged. */
const lostWith: Record<number, Record<number, boolean> | undefined> = {};

/** Whether `h` is one we lost an exchange with and not yet quiet (clears the memory when it is). */
function lostFor(bot: Unit, h: Unit): boolean {
    const mine = lostWith[bot.GetPlayerID()];
    const pid = h.GetPlayerID();
    if (mine === undefined || mine[pid] !== true) return false;
    const quiet = Threat.SETTINGS.StayEngaged;
    if (!bot.WasRecentlyDamagedByHero(h, quiet) && !h.WasRecentlyDamagedByHero(bot, quiet)) {
        mine[pid] = undefined as unknown as boolean;
        return false;
    }
    return true;
}

/** The hero's running exchange as the catch read counts its hunters: only the executor writes it (`NoteRun`). */
const runs: Record<number, { level: Level; target: number } | undefined> = {};

function NoteRun(pid: number, level: Level, target: number | undefined): void {
    runs[pid] = target !== undefined && (level === "kill" || level === "join") ? { level, target } : undefined;
}

function distXY(a: Vector, b: Vector): number {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return math.sqrt(dx * dx + dy * dy);
}

function frac(u: Unit): number {
    return u.GetHealth() / math.max(1, u.GetMaxHealth());
}

function valid(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.CanBeSeen() && !u.IsIllusion();
}

/** The enemy hero is swinging at a lane creep: a last-hit or deny attempt. */
function lastHitting(h: Unit): boolean {
    const t = h.GetAttackTarget();
    return t !== undefined && t !== null && !t.IsNull() && t.IsCreep() && !t.IsHero();
}

/** Where the bot attacks `target` from: here inside attack range plus both hulls, else the point on the line to it at that distance (where an attack order stops walking). */
function attackPoint(bot: Unit, target: Unit): Vector {
    const me = bot.GetLocation();
    const at = target.GetLocation();
    const range = bot.GetAttackRange() + bot.GetBoundingRadius() + target.GetBoundingRadius();
    const d = distXY(me, at);
    if (d <= range) return me;
    const f = range / d;
    return Vector(at.x + (me.x - at.x) * f, at.y + (me.y - at.y) * f, me.z);
}

/** The target's speed away from `u` along the line from `u` to `place`; unseen, the speed Threat last read for it. */
function awaySpeed(u: Unit, place: Vector, vx: number, vy: number, pid: number, seen: boolean, unseenKnown: boolean): number {
    const me = u.GetLocation();
    const dx = place.x - me.x;
    const dy = place.y - me.y;
    const n = math.sqrt(dx * dx + dy * dy);
    if (n < 1) return 0;
    if (!seen && !unseenKnown) return Threat.SeenSpeed(pid) ?? Threat.SETTINGS.MissingSpeed;
    return (vx * dx + vy * dy) / n;
}

/** A unit's attack damage per second before armour (GetSecondsPerAttack is on every hero handle). */
function rawDps(u: Unit): number {
    const spa = (u as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.();
    return spa !== undefined && spa > 0 ? u.GetAttackDamage() / spa : 0;
}

/** One hero of ours as a hunter on a target at `place`, from the target's velocity and damage factors. */
function hunterOf(u: Unit, place: Vector, ls: LastSeen, pid: number, seen: boolean, known: boolean): Hunter {
    const spells: { range: number; cp: number; dmg: number }[] = [];
    for (const sp of SpellReady.ReadySpells(u)) {
        const f = sp.dtype === DamageType.Pure ? 1 : sp.dtype === DamageType.Physical ? ls.physF : ls.magF;
        spells.push({ range: sp.range, cp: sp.cp, dmg: sp.dmg * f });
    }
    return {
        d: distXY(u.GetLocation(), place),
        reach: u.GetAttackRange() + u.GetBoundingRadius() + ls.hull,
        close: u.GetCurrentMovementSpeed() - awaySpeed(u, place, ls.vx, ls.vy, pid, seen, known),
        dps: rawDps(u) * ls.physF,
        spells,
    };
}

/** The bot and every ally of ours alive with a kill or join running on the same target: the catch read's hunters. */
function huntersOf(bot: Unit, place: Vector, ls: LastSeen, pid: number, seen: boolean, known: boolean): Hunter[] {
    const out = [hunterOf(bot, place, ls, pid, seen, known)];
    const me = bot.GetPlayerID();
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (a === undefined || a === null || a.IsNull() || !a.IsAlive() || a.IsIllusion() || a.GetPlayerID() === me) continue;
        if (runs[a.GetPlayerID()]?.target !== pid) continue;
        out.push(hunterOf(a, place, ls, pid, seen, known));
    }
    return out;
}

const TOWER_IDS = [Tower.Top1, Tower.Top2, Tower.Top3, Tower.Mid1, Tower.Mid2, Tower.Mid3, Tower.Bot1, Tower.Bot2, Tower.Bot3, Tower.Base1, Tower.Base2];

/**
 * Seconds until the target at `place` is inside its own nearest standing tower's reach, at its speed towards that tower; the
 * catch window when it is not heading there (no safety in sight).
 */
function safeTime(bot: Unit, place: Vector, ls: LastSeen, pid: number, seen: boolean, known: boolean): number {
    const theirs = bot.GetTeam() === Team.Radiant ? Team.Dire : Team.Radiant;
    let best: Vector | undefined;
    let bestD = math.huge;
    for (const id of TOWER_IDS) {
        const t = GetTower(theirs, id);
        if (t === undefined || t === null || !t.IsAlive()) continue;
        const d = distXY(t.GetLocation(), place);
        if (d < bestD) {
            bestD = d;
            best = t.GetLocation();
        }
    }
    if (best === undefined) return BARS.catchWindow;
    const left = bestD - LaneConfig.TowerReach();
    if (left <= 0) return 0;
    let v: number;
    if (!seen && !known) v = Threat.SeenSpeed(pid) ?? Threat.SETTINGS.MissingSpeed;
    else v = (ls.vx * (best.x - place.x) + ls.vy * (best.y - place.y)) / math.max(1, bestD);
    return v > 0 ? math.min(BARS.catchWindow, left / v) : BARS.catchWindow;
}

/** An unseen target's predicted place: our team's last sighting moved on by its last seen velocity times the time unseen, capped at its last read speed. Undefined without a sighting. */
function predictedPlace(pid: number, ls: LastSeen | undefined): Vector | undefined {
    const info = GetHeroLastSeenInfo(pid)[0];
    if (info === undefined) return undefined;
    const l = info.location;
    const vx = ls?.vx ?? 0;
    const vy = ls?.vy ?? 0;
    const v = math.sqrt(vx * vx + vy * vy);
    const cap = Threat.SeenSpeed(pid) ?? Threat.SETTINGS.MissingSpeed;
    const f = v > cap && v > 0 ? cap / v : 1;
    return Vector(l.x + vx * f * info.time_since_seen, l.y + vy * f * info.time_since_seen, l.z);
}

/** An enemy tower whose reach covers `a` or `b`. */
function towerCovers(bot: Unit, a: Vector, b: Vector): boolean {
    const reach = LaneConfig.TowerReach();
    for (const t of bot.GetNearbyTowers(1600, true)) {
        if (!t.IsAlive()) continue;
        const tl = t.GetLocation();
        if (distXY(tl, a) <= reach || distXY(tl, b) <= reach) return true;
    }
    return false;
}

/**
 * What the executor knows of the running exchange (`Run` less what Gather reads): the ages and the exchange's own numbers.
 * `offered`, `started` are seconds since the offer and the start; `soFar` is `Deficit` from the landing baseline (from the start
 * before it); `stepFor` the seconds of the current step out of the creeps.
 */
type RunState = Omit<Run, "alive" | "chaseAt" | "unseen" | "catch">;

/** The inputs of one frame, read from the game once. `rs` is the executor's running exchange, if any. Reads only (it writes the heading samples and the last-seen record). */
export function Gather(bot: Unit, rs?: RunState): Inputs {
    const now = DotaTime();
    const here = bot.GetLocation();
    const stay = Threat.Read(bot, here, here, Threat.SETTINGS.StayHorizon, { engagedWindow: Threat.SETTINGS.StayEngaged });
    let wave = 0;
    let creepsOnMe = 0;
    for (const c of bot.GetNearbyLaneCreeps(CREEP_RADIUS, true)) {
        if (!c.IsAlive()) continue;
        wave++;
        if (c.GetAttackTarget() === bot) creepsOnMe++;
    }
    let towerOnMe = false;
    const reach = LaneConfig.TowerReach();
    const towers: Vector[] = [];
    for (const t of bot.GetNearbyTowers(reach + 1000, true)) {
        if (!t.IsAlive()) continue;
        towers.push(t.GetLocation());
        if (t.GetAttackTarget() === bot) {
            creepsOnMe += 2;
            towerOnMe = true;
        }
    }
    const walkOf = Threat.Reader(bot, Threat.SETTINGS.GateHorizon);
    const bpid = bot.GetPlayerID();
    const pairRead = PairJoin.For(bot);
    let pair: Inputs["pair"] = pairRead.ans !== undefined && pairRead.rec !== undefined && pairRead.ans.tgt !== -1
        ? { tgt: pairRead.ans.tgt, ko: pairRead.ans.ko, kt: pairRead.ans.kt, dec: pairRead.ans.dec }
        : undefined;
    // The ally's last hit leaves a gap between two swings (PairJoin HitRecent is 1 s): a join answer stands for Keep s after the situation lapses.
    const kept = lastPair[bpid];
    if (pair !== undefined && pair.ko > pair.kt) lastPair[bpid] = { p: pair, at: now };
    else if (pair === undefined && kept !== undefined && now - kept.at <= PairJoin.SETTINGS.Keep) pair = kept.p;
    for (const k in lastHandles) lastHandles[k as unknown as number] = undefined;
    const play = playFor(bot, here);
    const myRange = bot.GetAttackRange();
    const myHull = bot.GetBoundingRadius();
    const ms = bot.GetCurrentMovementSpeed();
    const cands: Cand[] = [];
    let runSeen = false;
    for (const h of bot.GetNearbyHeroes(CAND_RADIUS, true, BotMode.None)) {
        if (!valid(h)) continue;
        const pid = h.GetPlayerID();
        const at = h.GetLocation();
        const d = GetUnitToUnitDistance(bot, h);
        const gap = d - (myRange + myHull + h.GetBoundingRadius());
        noteSeen(pid, at, now);
        const [vx, vy] = velocityOf(pid, at, now);
        let away = 0;
        if (gap > 0 && d > 1) away = (vx * (at.x - here.x) + vy * (at.y - here.y)) / d;
        const free = Free(lastHitting(h), myRange, h.GetAttackRange());
        const hitting = bot.WasRecentlyDamagedByHero(h, HIT_RECENT);
        const stand = attackPoint(bot, h);
        let tw = false;
        for (const tl of towers) if (distXY(stand, tl) <= reach) tw = true;
        const thp = frac(h);
        const isRun = rs !== undefined && rs.target === pid;
        if (isRun) runSeen = true;
        const c: Cand = {
            pid,
            thp,
            thpAbs: h.GetHealth(),
            d,
            gap,
            away,
            hitting,
            free,
            ko: free ? 0 : shareOn(bot, h),
            kt: free ? 0 : shareOn(h, bot),
            paid: hitting && CreepAggro.Paid(bot, h),
            tw,
            lost: lostFor(bot, h),
        };
        lastHandles[pid] = h;
        const asked = thp <= BARS.commitHp || (pair !== undefined && pair.tgt === pid) || (play !== undefined && play.tgt === pid) || isRun;
        if (asked) {
            const r = walkOf(here, at);
            c.walk = { burst: r.burst, n: r.reach.length, missing: r.missing };
        }
        if (thp <= BARS.commitHp || (isRun && rs!.level === "kill")) {
            const ls: LastSeen = {
                vx,
                vy,
                physF: h.GetActualIncomingDamage(100, DamageType.Physical) / 100,
                magF: h.GetActualIncomingDamage(100, DamageType.Magical) / 100,
                hull: h.GetBoundingRadius(),
                thpAbs: c.thpAbs,
            };
            lastSeen[pid] = ls;
            const hunters = huntersOf(bot, at, ls, pid, true, true);
            c.hunters = hunters;
            c.catch = CatchRead(hunters, c.thpAbs, safeTime(bot, at, ls, pid, true, true));
        }
        cands.push(c);
    }
    const i: Inputs = {
        now,
        hp: frac(bot),
        burst: stay.burst,
        n: stay.reach.length,
        missing: stay.missing,
        ms,
        towerOnMe,
        creepsOnMe,
        wave,
        denyDue: Laning.DenyDue(bot),
        pair,
        play,
        cands,
    };
    if (i.play !== undefined && i.play.zero === undefined) {
        const pc = cands.find((c) => c.pid === i.play!.tgt);
        if (pc !== undefined) i.play.zero = FightZero(i, pc);
    }
    if (rs !== undefined) i.run = runOf(bot, rs, runSeen, here);
    return i;
}

/** The running exchange with what only the game can say: the target's life, and for an unseen kill its chase. */
function runOf(bot: Unit, rs: RunState, seen: boolean, here: Vector): Run {
    const run: Run = { ...rs, alive: IsHeroAlive(rs.target) };
    if (seen || !run.alive || rs.level !== "kill") return run;
    const ls = lastSeen[rs.target];
    const place = predictedPlace(rs.target, ls);
    if (place === undefined) {
        run.unseen = { at: true, tower: false, threat: false };
        return run;
    }
    run.chaseAt = { x: place.x, y: place.y };
    const hull = ls?.hull ?? 0;
    const known = ls !== undefined;
    const lsr: LastSeen = ls ?? { vx: 0, vy: 0, physF: 1, magF: 1, hull: 0, thpAbs: 0 };
    const r = Threat.Read(bot, here, place, Threat.SETTINGS.GateHorizon, { exclude: rs.target });
    run.unseen = {
        at: distXY(here, place) <= bot.GetBoundingRadius() + hull + AT_PLACE,
        tower: towerCovers(bot, here, place),
        threat: r.mpids.length > 0 && r.missing >= Threat.SETTINGS.MissingRefuse,
    };
    run.catch = CatchRead(huntersOf(bot, place, lsr, rs.target, false, known), lsr.thpAbs, safeTime(bot, place, lsr, rs.target, false, known));
    return run;
}

/** `from`'s estimated damage on `on` over PairJoin's window over `on`'s HP: one side's kill share in a 1v1 exchange. */
function shareOn(from: Unit, on: Unit): number {
    return SpellReady.DamageOn(from, on, PairJoin.SETTINGS.Window) / math.max(1, on.GetHealth());
}

/**
 * The running play whose target we fight: one we are in already (we rolled it, or joined it), else the first running play
 * near us that someone else started, with its target seen and its hard zero for us (Plays.Weigh). A hero that started a play
 * of another kind is that play's (the executor leaves it alone).
 */
function playFor(bot: Unit, here: Vector): Inputs["play"] {
    const mine = Plays.Of(bot);
    const pick = (p: Plays.Play): Inputs["play"] => {
        const t = p.target;
        if (!valid(t)) return undefined;
        return { id: p.id, kind: p.kind, tgt: p.tgt, zero: Plays.Weigh(Plays.InputsOf({ kind: p.kind, by: bot, target: t, at: t.GetLocation() })).zero };
    };
    if (mine !== undefined) return mine.by === bot && mine.kind !== LANE_FIGHT ? undefined : pick(mine);
    for (const p of Plays.Near(here, CAND_RADIUS)) {
        if (p.by === bot) continue;
        const r = pick(p);
        if (r !== undefined) return r;
    }
    return undefined;
}

/** Why a lane fight on this candidate is off the table, whoever starts it: their tower, their burst along the walk, a big wave. */
export function FightZero(i: Inputs, c: Cand): string | undefined {
    if (i.towerOnMe || c.tw) return "tower";
    const r: Read3 = c.walk ?? { burst: i.burst, n: i.n, missing: i.missing };
    if (r.burst >= burstBar(r.n)) return "burst";
    if (i.wave > BARS.waveKill) return "wave";
    return undefined;
}

/** The cut's cadence: an answer change at once, a running exchange every 0.5 s, else every 2 s, to the laning stage's end (PairJoin's 12:00). */
const CUT_RUNNING = 0.5;
const CUT_IDLE = 2;
const CUT_UNTIL = 720;
const cutState: Record<number, { key?: string; at?: number } | undefined> = {};

/** Six places: a replay on a border decides as the game did. */
const round6 = (v: number): number => math.floor(v * 1000000 + 0.5) / 1000000;
const r1 = (v: number): number => math.floor(v * 10 + 0.5) / 10;
const bit = (b: boolean | undefined): number | undefined => (b === undefined ? undefined : b ? 1 : 0);
const or = (v: number | string | undefined): string | number => (v === undefined ? "-" : v);

/** `arr` (the seventh field) is the opening read for a reader of the line: we reach attack range within `walkHit`. Decide recomputes it from gap, away and `ms`. */
function candText(c: Cand, ms: number): string {
    const w = c.walk;
    const k = c.catch;
    return [
        c.pid,
        round6(c.thp),
        math.floor(c.thpAbs + 0.5),
        math.floor(c.d),
        math.floor(c.gap),
        math.floor(c.away),
        Arrives(c.gap, ms, math.max(0, c.away), BARS.walkHit) ? 1 : 0,
        c.hitting ? 1 : 0,
        c.free ? 1 : 0,
        round6(c.ko),
        round6(c.kt),
        c.paid ? 1 : 0,
        c.tw ? 1 : 0,
        or(w !== undefined ? round6(w.burst) : undefined),
        or(w?.n),
        or(w !== undefined ? round6(w.missing) : undefined),
        or(bit(k?.ok)),
        or(k !== undefined ? math.floor(k.dmg + 0.5) : undefined),
        or(k !== undefined ? round6(k.safe) : undefined),
        c.lost === true ? 1 : 0,
    ].join(",");
}

function huntersText(hs: Hunter[]): string {
    const out: string[] = [];
    for (const h of hs) {
        const sp: string[] = [];
        for (const s of h.spells) sp.push(`${r1(s.range)}:${math.floor(s.cp * 100 + 0.5) / 100}:${r1(s.dmg)}`);
        out.push([r1(h.d), r1(h.reach), r1(h.close), r1(h.dps), sp.join("/")].join(","));
    }
    return out.join(";");
}

function runText(r: Run, now: number): string {
    return [
        r.level,
        r.target,
        or(r.source),
        r.alive ? 1 : 0,
        round6(r.offered),
        or(r.started !== undefined ? round6(r.started) : undefined),
        r.landed ? 1 : 0,
        round6(r.soFar),
        r.catchFails,
        or(r.catchFailAt !== undefined ? round6(now - r.catchFailAt) : undefined),
        or(r.stepFor !== undefined ? round6(r.stepFor) : undefined),
        or(r.chaseAt !== undefined ? math.floor(r.chaseAt.x) : undefined),
        or(r.chaseAt !== undefined ? math.floor(r.chaseAt.y) : undefined),
        or(bit(r.catch?.ok)),
    ].join(":");
}

function howText(h: How | undefined): string | undefined {
    if (h === undefined) return undefined;
    return h.at !== undefined ? `${h.verb}:${h.aggro}@${math.floor(h.at.x)},${math.floor(h.at.y)}` : `${h.verb}:${h.aggro}`;
}

/**
 * The `ev=cut kind=trade` line for this frame's inputs and answer, when one is due (see the cut's cadence). Reads only.
 */
export function Cut(bot: Unit, i: Inputs, a: Answer): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || i.now > CUT_UNTIL) return;
    if (i.cands.length === 0 && i.run === undefined) return;
    const pid = bot.GetPlayerID();
    const st = (cutState[pid] = cutState[pid] ?? {});
    const key = `${a.level}:${a.target}:${a.reason}:${a.ended}`;
    const every = i.run !== undefined ? CUT_RUNNING : CUT_IDLE;
    if (key === st.key && st.at !== undefined && i.now >= st.at && i.now - st.at < every) return;
    st.key = key;
    st.at = i.now;
    let lowest: Cand | undefined;
    for (const c of i.cands) if (c.hunters !== undefined && (lowest === undefined || c.thp < lowest.thp)) lowest = c;
    const pos = LaneConfig.PositionOf(bot);
    const cds: string[] = [];
    for (const c of i.cands) cds.push(candText(c, i.ms));
    const u = i.run?.unseen;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "trade"],
        ["role", pos !== undefined && pos >= 4 ? "support" : "core"],
        ["hp", round6(i.hp)],
        ["bu", round6(i.burst)],
        ["n", i.n],
        ["mi", round6(i.missing)],
        ["ms", math.floor(i.ms)],
        ["tm", i.towerOnMe ? 1 : 0],
        ["hc", i.creepsOnMe],
        ["cr", i.wave],
        ["dn", i.denyDue ? 1 : 0],
        ["pjr", i.pair !== undefined ? `${i.pair.dec}:${i.pair.tgt}:${round6(i.pair.ko)}:${round6(i.pair.kt)}` : undefined],
        ["pl", i.play !== undefined ? `${i.play.id}:${i.play.kind}:${i.play.tgt}:${i.play.zero ?? "-"}` : undefined],
        ["cd", cds.join(";")],
        ["chu", lowest !== undefined ? huntersText(lowest.hunters!) : undefined],
        ["run", i.run !== undefined ? runText(i.run, i.now) : undefined],
        ["uat", bit(u?.at)],
        ["utw", bit(u?.tower)],
        ["uth", bit(u?.threat)],
        ["lv", a.level],
        ["tgt", a.target],
        ["src", a.source],
        ["how", howText(a.how)],
        ["why", a.reason],
        ["ed", a.ended],
    ]);
}

// ---------------------------------------------------------------------------------------------------------------------
// The executor: the episode of one exchange per hero, Desire and Think for the attack mode, and the seam of design section 5.
// Decide says what to do (`Answer.how`); this part carries it out and keeps the bookkeeping Decide reads back (`RunState`).
// ---------------------------------------------------------------------------------------------------------------------

/** Desire of a hit or hit back, and of a kill or join: under laning's 0.9 last-hit desire and any retreat (design section 9). */
export const DESIRE_HIT = 0.6;
export const DESIRE_COMMIT = 0.75;

/**
 * The speculative lane fight (slice lane-fight, user 04/11/2026: the fights no clear window decides come from the play roll):
 * the base weight is the older core trade's (before value on cil5, lposchk3, sspotchk1: cores 0.4 kills and 0.5 deaths per 100 encounters at
 * even numbers with the enemy over 40%, about 110 such encounters a game; lfpchk1 at 0.05 fired 1.6 a game, so 0.1 for about 4;
 * `judgement`), a chance per target at most every FIGHT_ROLL_EVERY s so standing beside a hero is not a roll a frame. A fired play
 * is fought as a join by its roller and by whoever joins it; the play ends with the roller's exchange or at its timeout.
 */
export const LANE_FIGHT = "lane_fight";
const FIGHT_BASE = 0.1;
const FIGHT_ROLL_EVERY = 15;
const FIGHT_TIMEOUT = 10;
Plays.Define(LANE_FIGHT, { base: FIGHT_BASE, timeout: FIGHT_TIMEOUT, chases: true });

/** Within this of its assigned lane's path the hero is in lane. */
const LANE_WIDTH = 1200;
/**
 * Creep aggro (EC-053, Liquipedia Lane_Creeps 7.41f): an attack order on an enemy hero draws enemy lane creeps within 500 of the
 * ordering hero and starts a 3 s cooldown even when none are near; attack animations within 500 draw them too, except while that
 * cooldown runs. So an order given clear of creeps buys up to 3 s of hits near them with no aggro. CLEAR adds 50 for creeps
 * moving during the order's latency; COOLDOWN_LEFT stops relying on the cooldown 0.3 s before it ends.
 */
const AGGRO_CLEAR = 550;
const AGGRO_COOLDOWN = 3;
const COOLDOWN_LEFT = 0.3;
/** One `ev=trade_no` per run of unanswered hits: none for the same hero within this (s), as the D24h view's onset. */
const NO_EVERY = 5;
/** After a loss of sight (`target_lost`), what follows within this many seconds is logged on `ev=chase`. */
const CHASE_WATCH = 12;

type Open = Exclude<Level, "none">;

interface Episode {
    level: Open;
    source?: Source;
    tpid: number;
    target: Unit;
    how?: How;
    offeredAt: number;
    startedAt?: number;
    hp0: number;
    thp0: number;
    /** Our first landed hit and the baselines `soFar` is read from: the frame before it landed (`hpPrev`, `thpPrev` track that frame until it does). */
    landedAt?: number;
    hpPrev?: number;
    thpPrev?: number;
    hpL?: number;
    thpL?: number;
    /** The bot's GetLastAttackTime at the start (GameTime): an attack fired since raises it. */
    atkSeen?: number;
    catchFails: number;
    catchFailAt?: number;
    stepSince?: number;
    primes: number;
    stepOuts: number;
    /** Most enemy lane creeps attacking us at once during the exchange. */
    aggro: number;
    first?: "step" | "order";
    /** Attack mode's OnEnd ran: the next Desire closes it naming the mode that took the bot. */
    ended?: boolean;
    tmax: number;
    thull: number;
    thpSeen: number;
    unseenSince?: number;
    play?: Plays.Play;
    joined?: boolean;
    /** What it was opened on, for the end line. */
    hp: number;
    thp: number;
    n: number;
    wave: number;
}

const episodes: Record<number, Episode | undefined> = {};
/** Which arm this frame's GetDesire took: Think follows it. */
const ownsFrame: Record<number, boolean | undefined> = {};
/** When this bot last gave an attack order on an enemy hero (its aggro cooldown runs from there). */
const primedAt: Record<number, number | undefined> = {};
/** When this bot last had a lane-fight chance, per target pid. */
const rolledAt: Record<number, Record<number, number> | undefined> = {};
const lastNo: Record<number, number | undefined> = {};

/** Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it): the laning body holds the hero. */
export function Owns(bot: Unit): boolean {
    return Ours.On("Trade") && (CoreLastHit.Applies(bot) || SupportDeny.Applies(bot));
}

/** The hero lanes: held by its laning body (transitions/phase) and standing by its own lane; elsewhere OHA's port fights. */
function inLane(bot: Unit): boolean {
    return Phase.LaningHeld(bot) && GetAmountAlongLane(bot.GetAssignedLane(), bot.GetLocation()).distance <= LANE_WIDTH;
}

/** Every fight of this in-lane hero beyond a hit is this module's: team roam keeps only its non-fight branches for it. */
export function OwnsFights(bot: Unit): boolean {
    return Owns(bot) && bot.IsAlive() && inLane(bot);
}

/** OHA's farm mode runs a laning hero off on its own triggers (`X.ShouldRun`); in lane this context decides when its hero backs off, so farm skips them. */
export function OwnsLaneRun(bot: Unit): boolean {
    return Owns(bot) && inLane(bot);
}

function roleOf(bot: Unit): string {
    const pos = LaneConfig.PositionOf(bot);
    return pos !== undefined && pos >= 4 ? "support" : "core";
}

/** The name PairJoin and the old views know the level by. */
const kindOf = (level: Open): string => (level === "hit" || level === "hitback" ? "trade" : level);

const desireOf = (level: Open): number => (level === "hit" || level === "hitback" ? DESIRE_HIT : DESIRE_COMMIT);

/** Where the running exchange stands: `Deficit` from the landing baseline once our first hit has landed, before it from the start (a ranged hit counts from its firing). */
function soFarOf(bot: Unit, ep: Episode, now: number): { landed: boolean; soFar: number } {
    const hp = bot.GetHealth();
    const thp = valid(ep.target) ? ep.target.GetHealth() : ep.thpSeen;
    const max = bot.GetMaxHealth();
    // GetLastAttackTime rises when an attack fires, on GameTime's clock, so it is compared with its own value at the start.
    const fired = bot.GetLastAttackTime();
    const rose = ep.atkSeen !== undefined && fired > ep.atkSeen;
    if (rose) ep.atkSeen = fired;
    const at = bot.GetAttackTarget();
    if (ep.landedAt === undefined && rose && at !== undefined && at !== null && at.IsHero() && at.GetPlayerID() === ep.tpid) {
        ep.landedAt = now;
        ep.hpL = ep.hpPrev ?? ep.hp0;
        ep.thpL = ep.thpPrev ?? ep.thp0;
    }
    if (ep.landedAt === undefined) {
        ep.hpPrev = hp;
        ep.thpPrev = thp;
        return { landed: false, soFar: Deficit(ep.hp0, hp, ep.thp0, thp, max) };
    }
    return { landed: true, soFar: Deficit(ep.hpL!, hp, ep.thpL!, thp, max) };
}

/** The executor's numbers for Decide: what `Gather` takes as the running exchange. */
function RunStateOf(bot: Unit, ep: Episode, now: number): RunState {
    const sf = soFarOf(bot, ep, now);
    return {
        level: ep.level,
        target: ep.tpid,
        source: ep.source,
        offered: now - ep.offeredAt,
        started: ep.startedAt !== undefined ? now - ep.startedAt : undefined,
        landed: sf.landed,
        soFar: sf.soFar,
        catchFails: ep.catchFails,
        catchFailAt: ep.catchFailAt,
        stepFor: ep.stepSince !== undefined ? now - ep.stepSince : undefined,
    };
}

/** What holds retreat for this hero now (`HoldsOf` on this frame's inputs): `hitback`, `join` or nothing. */
export function Holds(bot: Unit): "hitback" | "join" | undefined {
    if (!Owns(bot) || !bot.IsAlive() || !inLane(bot)) return undefined;
    const ep = episodes[bot.GetPlayerID()];
    const i = Gather(bot, ep !== undefined && ep.ended !== true ? RunStateOf(bot, ep, DotaTime()) : undefined);
    return HoldsOf(i);
}

/** The enemy hero `pid` if our team sees it now: a hero's handle reads null once it leaves sight and a new one comes back with it. */
function seenHero(pid: number): Unit | undefined {
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (h !== undefined && h !== null && !h.IsNull() && !h.IsIllusion() && h.GetPlayerID() === pid && h.IsAlive() && h.CanBeSeen()) return h;
    }
    return undefined;
}

// --- chase telemetry (ev=chase): what follows a loss of sight -----------------------------------------------------------

interface Chase {
    level: Open;
    tpid: number;
    at: number;
}
const chases: Record<number, Chase | undefined> = {};

function chaseLost(bot: Unit, ep: Episode, now: number): void {
    const pid = bot.GetPlayerID();
    if (chases[pid] !== undefined) chaseEnd(bot, chases[pid]!, now, "next", undefined);
    chases[pid] = { level: ep.level, tpid: ep.tpid, at: now };
    const info = GetHeroLastSeenInfo(ep.tpid)[0];
    const me = bot.GetLocation();
    const d = info !== undefined ? distXY(me, info.location) : undefined;
    const reach = bot.GetAttackRange() + bot.GetBoundingRadius() + ep.thull;
    const a = heads[ep.tpid]?.s0;
    const b = heads[ep.tpid]?.s1;
    const span = a !== undefined && b !== undefined ? b.at - a.at : 0;
    const hv = span > 0 ? distXY(Vector(a!.x, a!.y, 0), Vector(b!.x, b!.y, 0)) / span : undefined;
    const hd = span > 0 ? math.floor(math.deg(math.atan2(b!.y - a!.y, b!.x - a!.x)) + 0.5) : undefined;
    Telemetry.Event("chase", [
        ["pid", pid],
        ["ph", "lost"],
        ["role", roleOf(bot)],
        ["ek", kindOf(ep.level)],
        ["tgt", ep.tpid],
        ["dur", ep.startedAt !== undefined ? math.floor((now - ep.startedAt) * 10) / 10 : undefined],
        ["hp", math.floor(frac(bot) * 100) / 100],
        ["thp", math.floor((ep.thpSeen / math.max(1, ep.tmax)) * 100) / 100],
        ["kh", BARS.commitHp],
        ["x", math.floor(me.x)],
        ["y", math.floor(me.y)],
        ["lx", info !== undefined ? math.floor(info.location.x) : undefined],
        ["ly", info !== undefined ? math.floor(info.location.y) : undefined],
        ["tss", info !== undefined ? math.floor(info.time_since_seen * 10 + 0.5) / 10 : undefined],
        ["d", d !== undefined ? math.floor(d) : undefined],
        ["gap", d !== undefined ? math.floor(d - reach) : undefined],
        ["ms", math.floor(bot.GetCurrentMovementSpeed())],
        ["tms", math.floor(Threat.SeenSpeed(ep.tpid) ?? -1)],
        ["hv", hv !== undefined ? math.floor(hv) : undefined],
        ["hd", hd],
        ["sp", SpellReady.ReadyDamage(bot)],
    ]);
}

function chaseTick(bot: Unit, now: number): void {
    const c = chases[bot.GetPlayerID()];
    if (c === undefined) return;
    const dead = !IsHeroAlive(c.tpid);
    const seen = dead ? undefined : seenHero(c.tpid);
    const out = now - c.at > CHASE_WATCH;
    if (!dead && seen === undefined && !out) return;
    chaseEnd(bot, c, now, dead ? "dead" : seen !== undefined ? "seen" : "gone", seen);
}

function chaseEnd(bot: Unit, c: Chase, now: number, ph: string, seen: Unit | undefined): void {
    const pid = bot.GetPlayerID();
    chases[pid] = undefined;
    const ep = episodes[pid];
    Telemetry.Event("chase", [
        ["pid", pid],
        ["ph", ph],
        ["ek", kindOf(c.level)],
        ["tgt", c.tpid],
        ["dt", math.floor((now - c.at) * 10) / 10],
        ["alive", bot.IsAlive() ? 1 : 0],
        ["d", seen !== undefined && bot.IsAlive() ? math.floor(GetUnitToUnitDistance(bot, seen)) : undefined],
        ["thp", seen !== undefined ? math.floor(frac(seen) * 100) / 100 : undefined],
        ["hp", bot.IsAlive() ? math.floor(frac(bot) * 100) / 100 : undefined],
        ["mode", bot.GetActiveMode()],
        ["onk", ep !== undefined && ep.tpid === c.tpid ? kindOf(ep.level) : undefined],
    ]);
}

// --- the episode ------------------------------------------------------------------------------------------------------

/** The target Think named with SetTarget is cleared, if it is still the one set (another module's stays). */
function clearTarget(bot: Unit, ep: Episode): void {
    const t = bot.GetTarget();
    if (t === undefined || t === null) return;
    if (t === ep.target || (valid(t) && t.IsHero() && t.GetPlayerID() === ep.tpid) || !valid(t)) bot.SetTarget(undefined as any);
}

function close(bot: Unit, ep: Episode, why: string, now: number): void {
    const pid = bot.GetPlayerID();
    episodes[pid] = undefined;
    NoteRun(pid, "none", undefined);
    if (ep.level !== "hit" && ep.level !== "hitback") clearTarget(bot, ep);
    if (why === "losing") {
        const mine = (lostWith[pid] = lostWith[pid] ?? {});
        mine[ep.tpid] = true;
    }
    const started = ep.startedAt !== undefined;
    if (ep.play !== undefined && ep.play.by === bot) Plays.End(ep.play, why);
    const killed = started && !IsHeroAlive(ep.tpid);
    const thp = killed ? 0 : valid(ep.target) ? ep.target.GetHealth() : ep.thpSeen;
    if (why === "target_lost" && Telemetry.IsEnabled()) chaseLost(bot, ep, now);
    Telemetry.Event("trade", [
        ["pid", pid],
        ["role", roleOf(bot)],
        ["kind", ep.level],
        ["tgt", ep.tpid],
        ["play", ep.play?.id],
        ["join", ep.play !== undefined ? (ep.joined === true ? 1 : 0) : undefined],
        ["hb", ep.level === "hitback" ? 1 : undefined],
        ["result", started ? (killed ? "kill" : "done") : "lost"],
        ["why", why],
        ["dur", started ? math.floor((now - ep.startedAt!) * 10) / 10 : 0],
        ["hpd", started ? ep.hp0 - bot.GetHealth() : 0],
        ["thpd", started ? ep.thp0 - thp : 0],
        ["ld", started && ep.landedAt !== undefined ? math.floor((ep.landedAt - ep.startedAt!) * 10) / 10 : undefined],
        ["hp", math.floor(ep.hp * 100) / 100],
        ["thp", math.floor(ep.thp * 100) / 100],
        ["en", ep.n],
        ["cr", ep.wave],
        ["pr", ep.primes],
        ["so", ep.stepOuts],
        ["fa", ep.first],
        ["ag", ep.aggro],
        ["mode", bot.GetActiveMode()],
        ["md", math.floor(bot.GetActiveModeDesire() * 100) / 100],
    ]);
    if (started) PairJoin.After(bot, kindOf(ep.level), why, ep.tpid);
}

function open(bot: Unit, i: Inputs, a: Answer, now: number): number {
    const level = a.level as Open;
    const tpid = a.target!;
    const t = lastHandles[tpid];
    if (t === undefined) return 0;
    const c = i.cands.find((x) => x.pid === tpid)!;
    let play: Plays.Play | undefined;
    let joined: boolean | undefined;
    if (a.source === "play" && i.play !== undefined) {
        play = Plays.Active().find((p) => p.id === i.play!.id);
        if (play !== undefined) {
            if (Plays.Of(bot) === undefined) Plays.Join(play, bot);
            joined = play.by !== bot;
        }
    }
    const pid = bot.GetPlayerID();
    episodes[pid] = {
        level,
        source: a.source,
        tpid,
        target: t,
        how: a.how,
        offeredAt: now,
        hp0: bot.GetHealth(),
        thp0: t.GetHealth(),
        catchFails: 0,
        primes: 0,
        stepOuts: 0,
        aggro: 0,
        tmax: t.GetMaxHealth(),
        thull: t.GetBoundingRadius(),
        thpSeen: t.GetHealth(),
        play,
        joined,
        hp: i.hp,
        thp: c.thp,
        n: i.n,
        wave: i.wave,
    };
    NoteRun(pid, level, tpid);
    return desireOf(level);
}

/** What this frame's answer does to the episode: keep it (a level change on the same target is made in place), end it, open one. Returns the desire. */
function apply(bot: Unit, ep: Episode | undefined, i: Inputs, a: Answer, now: number): number {
    const pid = bot.GetPlayerID();
    if (ep !== undefined) {
        if (a.level !== "none" && a.target === ep.tpid && a.ended === undefined) {
            if (a.level !== ep.level) {
                ep.level = a.level as Open;
                NoteRun(pid, ep.level, ep.tpid);
            }
            ep.source = a.source;
            ep.how = a.how;
            if (a.catchFails !== undefined) {
                ep.catchFails = a.catchFails;
                ep.catchFailAt = a.catchFailAt;
            }
            return desireOf(ep.level);
        }
        close(bot, ep, a.ended ?? (a.level !== "none" && a.target !== ep.tpid ? "switch" : a.reason), now);
    }
    if (a.level === "none") {
        unanswered(bot, now, a.reason, i);
        return 0;
    }
    return open(bot, i, a, now);
}

/** Logs why no exchange opened this frame while an enemy hero is hitting us (`ev=trade_no`), so the D24h view's unanswered cases have a cause. */
function unanswered(bot: Unit, now: number, why: string, i: Inputs): void {
    const pid = bot.GetPlayerID();
    const last = lastNo[pid];
    if (!Telemetry.IsEnabled() || (last !== undefined && now - last < NO_EVERY)) return;
    let hitter: Cand | undefined;
    for (const c of i.cands) if (c.hitting && (hitter === undefined || c.d < hitter.d)) hitter = c;
    if (hitter === undefined) return;
    lastNo[pid] = now;
    const h = lastHandles[hitter.pid];
    Telemetry.Event("trade_no", [
        ["pid", pid],
        ["role", roleOf(bot)],
        ["why", why],
        ["tgt", hitter.pid],
        ["d", math.floor(hitter.d)],
        ["reach", math.floor(hitter.d - hitter.gap)],
        ["har", h !== undefined ? math.floor(h.GetAttackRange()) : undefined],
        ["agg", hitter.paid ? 1 : 0],
        ["hp", math.floor(i.hp * 100) / 100],
        ["thp", math.floor(hitter.thp * 100) / 100],
        ["en", i.n],
        ["cr", i.wave],
        ["hc", i.creepsOnMe],
        ["mode", bot.GetActiveMode()],
        ["md", math.floor(bot.GetActiveModeDesire() * 100) / 100],
    ]);
}

/** Whether a lane-fight chance on `tpid` is due (at most every FIGHT_ROLL_EVERY seconds); asking claims it. */
function rollDue(bot: Unit, tpid: number, now: number): boolean {
    const pid = bot.GetPlayerID();
    const seen = (rolledAt[pid] = rolledAt[pid] ?? {});
    const last = seen[tpid];
    if (last !== undefined && now - last < FIGHT_ROLL_EVERY) return false;
    seen[tpid] = now;
    return true;
}

/**
 * The lane-fight chance (design section 4): offered once per target per FIGHT_ROLL_EVERY s when the frame's answer is a hit or
 * nothing and tower, burst (the walk read) and wave pass. The target is the hit's, else the nearest hero.
 */
function chanceTarget(bot: Unit, i: Inputs, a: Answer, now: number): Unit | undefined {
    if (a.level !== "hit" && a.level !== "none") return undefined;
    let c: Cand | undefined;
    if (a.level === "hit") c = i.cands.find((x) => x.pid === a.target);
    else for (const x of i.cands) if (c === undefined || x.d < c.d) c = x;
    const t = c !== undefined ? lastHandles[c.pid] : undefined;
    if (c === undefined || t === undefined || !rollDue(bot, c.pid, now)) return undefined;
    if (c.walk === undefined) {
        const r = Threat.Read(bot, bot.GetLocation(), t.GetLocation(), Threat.SETTINGS.GateHorizon);
        c.walk = { burst: r.burst, n: r.reach.length, missing: r.missing };
    }
    return FightZero(i, c) === undefined ? t : undefined;
}

/**
 * The in-lane attack desire, or undefined outside lane (the caller then asks OHA's port). One Gather and one Decide a frame; the
 * answer opens, keeps (a level change on the same target in place), ends or replaces the hero's exchange. An exchange attack mode
 * never took is ended `not_taken` by Decide itself.
 */
export function Desire(bot: Unit): number | undefined {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    let ep = episodes[pid];
    if (Telemetry.IsEnabled()) chaseTick(bot, now);
    if (!bot.IsAlive() || !inLane(bot)) {
        if (ep !== undefined) close(bot, ep, bot.IsAlive() ? "lane_end" : "dead", now);
        ownsFrame[pid] = false;
        return bot.IsAlive() ? undefined : 0;
    }
    ownsFrame[pid] = true;
    Plays.Tick(now);
    if (ep !== undefined && ep.ended === true) {
        close(bot, ep, `mode_${bot.GetActiveMode()}`, now);
        ep = undefined;
    }
    // A hero that started a play of another kind (the rune spawn's) is driven by that play until it ends (OWNERSHIP H24).
    const mine = Plays.Of(bot);
    if (mine !== undefined && mine.by === bot && mine.kind !== LANE_FIGHT) {
        if (ep !== undefined) close(bot, ep, "play", now);
        return 0;
    }
    let i = Gather(bot, ep !== undefined ? RunStateOf(bot, ep, now) : undefined);
    if (ep !== undefined) noteSight(bot, ep, now);
    let a = Decide(i);
    if (ep === undefined && OwnsFights(bot)) {
        const t = chanceTarget(bot, i, a, now);
        const play = t !== undefined ? Plays.Roll({ kind: LANE_FIGHT, by: bot, target: t, at: t.GetLocation() }, now) : undefined;
        if (play !== undefined) {
            i = Gather(bot);
            a = Decide(i);
            if (a.level !== "join" || a.source !== "play" || a.target !== play.tgt) Plays.End(play, "refused");
        }
    }
    Cut(bot, i, a);
    return apply(bot, ep, i, a, now);
}

/** After Gather: the target's current handle and HP when it is seen, and the loss of sight of a running kill where the chase goes on past it. */
function noteSight(bot: Unit, ep: Episode, now: number): void {
    const t = lastHandles[ep.tpid];
    if (t !== undefined) {
        ep.target = t;
        ep.thpSeen = t.GetHealth();
        ep.unseenSince = undefined;
    } else if (ep.level === "kill" && ep.startedAt !== undefined && ep.unseenSince === undefined && IsHeroAlive(ep.tpid)) {
        ep.unseenSince = now;
        if (Telemetry.IsEnabled()) chaseLost(bot, ep, now);
    }
}

type AggroAction = "attack" | "prime" | "step_out";

/**
 * The aggro-free attack: what a trading hero does this frame so its hits draw no creep aggro: `attack` while its own attack
 * order's cooldown covers it; `prime` (a fresh attack order) when no enemy lane creep is within AGGRO_CLEAR; otherwise `step_out`
 * of the creeps first.
 */
export function AggroPlan(now: number, primed: number | undefined, creepsWithinClear: number): AggroAction {
    if (primed !== undefined && now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT) return "attack";
    return creepsWithinClear === 0 ? "prime" : "step_out";
}

/** Whether this frame's GetDesire took our arm; mode_attack_generic's Think runs ours when true, OHA's port otherwise. */
export function OwnsFrame(bot: Unit): boolean {
    return ownsFrame[bot.GetPlayerID()] === true;
}

/** Carries out `Answer.how` on the episode: a move to the predicted place for an unseen chase, a committed attack order, or the aggro-free plan (the step out of the creeps is the only mechanics decided here). */
export function Think(bot: Unit): void {
    const pid = bot.GetPlayerID();
    const ep = episodes[pid];
    if (ep === undefined || ep.how === undefined) return;
    const how = ep.how;
    const commits = how.aggro === "commit";
    if (!valid(ep.target)) {
        // OHA's casts read GetTarget, so the stale handle is cleared; sight back sets it again.
        if (commits) clearTarget(bot, ep);
        if (how.verb === "move" && how.at !== undefined) bot.Action_MoveToLocation(Vector(how.at.x, how.at.y, bot.GetLocation().z));
        return;
    }
    const now = DotaTime();
    // OHA's hero files cast at GetTarget under J.IsGoingOnSomeone, so a committed exchange names its target there.
    if (commits) bot.SetTarget(ep.target);
    if (ep.startedAt === undefined) {
        ep.startedAt = now;
        ep.atkSeen = bot.GetLastAttackTime();
        PairJoin.Reopened(bot);
    }
    const creeps: Unit[] = [];
    let onMe = 0;
    for (const c of bot.GetNearbyLaneCreeps(AGGRO_CLEAR, true)) {
        if (c.IsNull() || !c.IsAlive()) continue;
        creeps.push(c);
        if (c.GetAttackTarget() === bot) onMe++;
    }
    ep.aggro = math.max(ep.aggro, onMe);
    const plan = commits ? "attack" : AggroPlan(now, primedAt[pid], creeps.length);
    if (plan === "step_out") {
        if (ep.stepSince === undefined) {
            ep.stepSince = now;
            ep.stepOuts++;
        }
        ep.first = ep.first ?? "step";
        bot.Action_MoveToLocation(stepOutPoint(bot, creeps));
        return;
    }
    ep.stepSince = undefined;
    ep.first = ep.first ?? "order";
    if (plan === "prime") {
        primedAt[pid] = now;
        ep.primes++;
        bot.Action_AttackUnit(ep.target, false);
        return;
    }
    if (bot.GetAttackTarget() !== ep.target) {
        // An order inside the cooldown draws nothing and does not restart it.
        if (commits) primedAt[pid] = now;
        bot.Action_AttackUnit(ep.target, false);
    }
}

/** AGGRO_CLEAR + 100 from the creeps' centre, on the far side from them. */
function stepOutPoint(bot: Unit, creeps: Unit[]): Vector {
    const me = bot.GetLocation();
    let x = 0;
    let y = 0;
    let seen = 0;
    for (const c of creeps) {
        // cil2 (A_on_1 t=776.3, B_on_2 t=377.1): a creep the query listed as alive returned no location; cause not known.
        const l = c.GetLocation() as Vector | undefined;
        if (l === undefined) continue;
        x += l.x;
        y += l.y;
        seen++;
    }
    // No located creep: treat the hero as on the centre, which steps back along the lane.
    x = seen > 0 ? x / seen : me.x;
    y = seen > 0 ? y / seen : me.y;
    let dx = me.x - x;
    let dy = me.y - y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len < 1) {
        // Standing on the centre: step back along the lane towards our own side.
        const back = GetLocationAlongLane(bot.GetAssignedLane(), math.max(0, GetAmountAlongLane(bot.GetAssignedLane(), me).amount - 0.05));
        dx = back.x - me.x;
        dy = back.y - me.y;
    }
    const n = math.max(1, math.sqrt(dx * dx + dy * dy));
    return Vector(x + (dx / n) * (AGGRO_CLEAR + 100), y + (dy / n) * (AGGRO_CLEAR + 100), me.z);
}

/** Attack mode lost the hero to another mode: a started exchange ends there (closed by the next Desire, which can name that mode). */
export function OnEnd(bot: Unit): void {
    const ep = episodes[bot.GetPlayerID()];
    if (ep !== undefined && ep.startedAt !== undefined) ep.ended = true;
}

/**
 * Laning's 0.9 last-hit desire must not cut a retreat this hero is already in (core-time-diagnosis s2: a death within 15 s of
 * such a cut was 4 times as likely), nor a kill or join (lfpchk1: 2 of 8 fights ended in a last hit at 4.9 s; a pair join, D10
 * group 2, is above the last hit, D11 group 3, by the doctrine). A hit or hit back still gives way to it. A predicate on the
 * laning GetDesire (OWNERSHIP H2), for every hero this context owns.
 */
export function LastHitYields(bot: Unit): boolean {
    if (!Owns(bot)) return false;
    if (bot.GetActiveMode() === BotMode.Retreat) return true;
    const ep = episodes[bot.GetPlayerID()];
    return ep !== undefined && (ep.level === "kill" || ep.level === "join") && ep.startedAt !== undefined && ep.ended !== true;
}

/** An exchange is open for this hero (Desire returns its desire in attack mode); reads only. */
export function Running(bot: Unit): boolean {
    const ep = episodes[bot.GetPlayerID()];
    return ep !== undefined && ep.ended !== true;
}

/** A pair join (D10, group 2) is open for this hero, or a kill carrying one: the arbiter's pair group. Reads only. */
export function Joining(bot: Unit): boolean {
    const ep = episodes[bot.GetPlayerID()];
    return ep !== undefined && ep.ended !== true && ep.source === "pair";
}

/** The hero's running exchange, its level and target (ev=cast, and PairJoin's partner read). Reads only. */
export function EpisodeOf(pid: number): { kind: Level; tpid: number; target: Unit; at: number } | undefined {
    const ep = episodes[pid];
    return ep === undefined || ep.ended === true ? undefined : { kind: ep.level, tpid: ep.tpid, target: ep.target, at: ep.offeredAt };
}

/** When this bot last gave an attack order on an enemy hero from an exchange (lane_aggro shares the 3 s draw clock). */
export function PrimedAt(pid: number): number | undefined {
    return primedAt[pid];
}

/** Another lane module gave an attack order on an enemy hero: the aggro-free plan counts it as its prime. */
export function NotePrimed(pid: number, t: number): void {
    primedAt[pid] = t;
}

export function Reset(): void {
    for (const k in heads) heads[k as unknown as number] = undefined;
    for (const k in lastSeen) lastSeen[k as unknown as number] = undefined;
    for (const k in runs) runs[k as unknown as number] = undefined;
    for (const k in cutState) cutState[k as unknown as number] = undefined;
    for (const k in episodes) episodes[k as unknown as number] = undefined;
    for (const k in ownsFrame) ownsFrame[k as unknown as number] = undefined;
    for (const k in primedAt) primedAt[k as unknown as number] = undefined;
    for (const k in rolledAt) rolledAt[k as unknown as number] = undefined;
    for (const k in lastNo) lastNo[k as unknown as number] = undefined;
    for (const k in chases) chases[k as unknown as number] = undefined;
    for (const k in lostWith) lostWith[k as unknown as number] = undefined;
    for (const k in lastPair) lastPair[k as unknown as number] = undefined;
    for (const k in lastHandles) lastHandles[k as unknown as number] = undefined;
}
