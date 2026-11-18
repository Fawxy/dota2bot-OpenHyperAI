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
export const BARS = {
    /** A target at this HP share or less is a kill candidate. Banked `@lane_encounters` on cil5, lposchk3, sspotchk1: 11 kills and no deaths per 100 encounters with the lowest enemy at 40% or less, 1.8 and 1.8 at 41-70%. */
    commitHp: 0.4,
    /** Enemy lane creeps within 500 above which a hit or hit back is vetoed (EC-045, `judgement`), and for a kill the more than one full wave of D19's "a big enemy wave" (`judgement`). */
    waveHit: 3,
    waveKill: 5,
    /** Enemy creeps attacking us (a tower counts 2) at which a hit or hit back is vetoed: already tanking (`judgement`). */
    creeps: 2,
    /** A running exchange's slack on its own bars: HP share, burst, and one more creep in the wave (KEEP_HP_SLACK and KEEP_WAVE_SLACK of core_trade, `judgement`). */
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
    /** A hit or hit back opens only if we reach attack range within this (s): 1 s of walking plus an attack point (WALK_IN, `judgement`). */
    walkIn: 1.5,
    /** The pair join acts on a target within this of us (PairJoin TargetRange, D10: about 4 s of walking), and a play's target within our reach plus this (JOIN_WALK: about 2 s, `judgement`). */
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

export interface Catch {
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

export interface Cand {
    pid: number;
    /** Its HP share and HP. */
    thp: number;
    thpAbs: number;
    /** Distance to us, and past our attack range plus both hulls (0 or less in range). */
    d: number;
    gap: number;
    /** Its speed away from us along the line between us (negative: towards), and whether we reach attack range within `walkIn`. */
    away: number;
    arrives: boolean;
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
    if (!c.arrives) return "no_reach";
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
 * What holds retreat (design section 1, "Hold"): `hitback` while some hitter passes tower, burst and HP and is either paid or
 * free or favoured, whatever the swing is doing (a due deny, creeps and the wave change the swing, not the hold); `join`
 * while some candidate is a pair join. Undefined: retreat decides alone.
 */
export function Holds(i: Inputs): "hitback" | "join" | undefined {
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

/** Enemy heroes within this of us are candidates: past any laning hero's attack range and its walk-in (core_trade's HITTER_RADIUS). */
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

/** The hero's running exchange as the catch read counts its hunters: only the executor writes it (`NoteRun`). */
const runs: Record<number, { level: Level; target: number } | undefined> = {};

export function NoteRun(pid: number, level: Level, target: number | undefined): void {
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
export type RunState = Omit<Run, "alive" | "chaseAt" | "unseen" | "catch">;

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
    const pairRead = PairJoin.For(bot);
    const pair = pairRead.ans !== undefined && pairRead.rec !== undefined && pairRead.rec.on !== "ours" && pairRead.ans.tgt !== -1
        ? { tgt: pairRead.ans.tgt, ko: pairRead.ans.ko, kt: pairRead.ans.kt, dec: pairRead.ans.dec }
        : undefined;
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
            arrives: Arrives(gap, ms, away, BARS.walkIn),
            hitting,
            free,
            ko: free ? 0 : shareOn(bot, h),
            kt: free ? 0 : shareOn(h, bot),
            paid: hitting && CreepAggro.Paid(bot, h),
            tw,
        };
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
        towerOnMe,
        creepsOnMe,
        wave,
        denyDue: Laning.DenyDue(bot),
        pair,
        play,
        cands,
    };
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

/** A running play near us whose target we may join: not ours, its target seen and the play's hard zero for us (Plays.Weigh), none while we are in a play ourselves. */
function playFor(bot: Unit, here: Vector): Inputs["play"] {
    if (Plays.Of(bot) !== undefined) return undefined;
    for (const p of Plays.Near(here, CAND_RADIUS)) {
        const t = p.target;
        if (p.by === bot || !valid(t)) continue;
        const zero = Plays.Weigh(Plays.InputsOf({ kind: p.kind, by: bot, target: t, at: t.GetLocation() })).zero;
        return { id: p.id, kind: p.kind, tgt: p.tgt, zero };
    }
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

function candText(c: Cand): string {
    const w = c.walk;
    const k = c.catch;
    return [
        c.pid,
        round6(c.thp),
        math.floor(c.thpAbs + 0.5),
        math.floor(c.d),
        math.floor(c.gap),
        math.floor(c.away),
        c.arrives ? 1 : 0,
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
 * The `ev=cut kind=trade2` line for this frame's inputs and answer, when one is due (see the cut's cadence). Not called from any
 * game path yet: the executor (step 4) calls it after Decide. Reads only.
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
    for (const c of i.cands) cds.push(candText(c));
    const u = i.run?.unseen;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "trade2"],
        ["role", pos !== undefined && pos >= 4 ? "support" : "core"],
        ["hp", round6(i.hp)],
        ["bu", round6(i.burst)],
        ["n", i.n],
        ["mi", round6(i.missing)],
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

export function Reset(): void {
    for (const k in heads) heads[k as unknown as number] = undefined;
    for (const k in lastSeen) lastSeen[k as unknown as number] = undefined;
    for (const k in runs) runs[k as unknown as number] = undefined;
    for (const k in cutState) cutState[k as unknown as number] = undefined;
}
