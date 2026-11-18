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
