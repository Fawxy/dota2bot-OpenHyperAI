/**
 * Pair join (D10, slices pair-join, pair-join-on): a laner whose ally in reach (or who itself) is being hit by an enemy hero
 * joins the fight when what our heroes there can do to theirs outweighs what theirs can do to ours. `For` decides at most
 * every `Every` s; `Tick` logs `ev=cut kind=join` (the inputs, the answer). With `Ours.PairJoin`, `Joins` is acted on:
 * CoreTrade opens a committed attack (kind `join`) on `tgt` and retreat's LeaveWhy stays (`join`). `Decide` is pure, so a
 * cut replays offline (driver pair_join).
 *
 * The weighing: over `Window` s, each side's best kill share, GetEstimatedDamageToTarget summed over its heroes on one target
 * over that target's HP, the target the side does best on. We join on theirs (`tgt`) when our share is the larger; numbers
 * against us leave it out at once (D1 is retreat's).
 */
import { DamageType, Unit, UnitType } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as RetreatState from "bots/FunLib/humaniser/retreat_state";

export const SETTINGS = {
    /** The ally's distance from the bot for the rule to apply (D10's 1,200; the funnel's). */
    AllyRange: 1200,
    /** Enemy heroes within this of the hit ally are in the fight (the ledger's `pr` radius). */
    FoeRange: 1000,
    /** Our heroes within this of the hit ally are in the fight (the ledger's allies radius). */
    OursRange: 1200,
    /** An ally counts as hit when a hero damaged it within this many seconds. judgement. */
    HitRecent: 1,
    /** The damage window both sides are weighed over (s): Threat's burst window. judgement. */
    Window: 3,
    /** Seconds between decisions while the situation holds. judgement. */
    Every: 0.5,
    /** The laning stage the rule covers (s): the ledger's 12:00. */
    Until: 720,
    /** An unchanged answer is logged again after this many seconds (Retreat CutEvery). */
    CutEvery: 2,
    /**
     * A join holds this long after the last `join` answer while no other answer replaces it (the ally's last hit leaves the
     * 1 s HitRecent between two swings): about one and a half lane attack intervals. judgement.
     */
    Keep: 1.5,
    /** The joiner acts only on a target within this of it: D10's 1,200, about 4 s of walking. judgement. */
    TargetRange: 1200,
    /**
     * Slice join-after (shadow): after a taken join or trade of ours ends, the weighing is read with no hit needed for this
     * long (s): the longest mirror fight bucket the funnel graded (6-10 s) plus a little. judgement.
     */
    AfterWindow: 8,
    /** ... once every this many seconds (the snapshot's cadence, so a sample joins `ev=snap` by second). judgement. */
    AfterEvery: 1,
};

/** One hero in the fight: pid, place, HP, in our retreat (ours only). */
export interface Member {
    pid: number;
    x: number;
    y: number;
    hp: number;
    mhp: number;
    ret?: number;
}

/** What one decision reads: the hit ally, both sides, and `dmg[a][b]`, hero a's estimated damage to hero b over Window. */
export interface Rec {
    ally: number;
    ours: Member[];
    theirs: Member[];
    dmg: Record<number, Record<number, number>>;
}

export type Dec = "join" | "outnumbered" | "losing";

export interface Answer {
    dec: Dec;
    /** Our best target (the enemy we do best on), or -1. */
    tgt: number;
    /** Our best kill share and theirs. */
    ko: number;
    kt: number;
}

/** The side `from`'s best kill share on `on` over the window: the target and the share. */
function best(from: Member[], on: Member[], dmg: Record<number, Record<number, number>>): LuaMultiReturn<[number, number]> {
    let tgt = -1;
    let share = 0;
    for (const o of on) {
        let d = 0;
        for (const f of from) d += dmg[f.pid]?.[o.pid] ?? 0;
        const s = d / math.max(o.hp, 1);
        if (tgt === -1 || s > share) {
            tgt = o.pid;
            share = s;
        }
    }
    return $multi(tgt, share);
}

/** The rule: outnumbered stays out; else join when our best kill share beats theirs. Ours in retreat (`ret` 1) are leaving: they count on neither side. */
export function Decide(rec: Rec): Answer {
    const ours = rec.ours.filter((m) => m.ret !== 1);
    const [tgt, ko] = best(ours, rec.theirs, rec.dmg);
    const [, kt] = best(rec.theirs, ours, rec.dmg);
    if (rec.theirs.length > ours.length) return { dec: "outnumbered", tgt, ko, kt };
    return { dec: ko > kt ? "join" : "losing", tgt, ko, kt };
}

function live(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.GetLocation() !== undefined && !u.IsIllusion();
}

function dist(a: Unit, b: Unit): number {
    const p = a.GetLocation();
    const q = b.GetLocation();
    return math.sqrt((p.x - q.x) ** 2 + (p.y - q.y) ** 2);
}

function member(u: Unit, ours: boolean): Member {
    const l = u.GetLocation();
    const m: Member = { pid: u.GetPlayerID(), x: math.floor(l.x + 0.5), y: math.floor(l.y + 0.5), hp: math.floor(u.GetHealth() + 0.5), mhp: math.floor(u.GetMaxHealth() + 0.5) };
    if (ours) m.ret = RetreatState.Running(u) ? 1 : 0;
    return m;
}

/**
 * The situation's record, or undefined when no ally within AllyRange (the bot included) was hit by a hero within HitRecent,
 * or fewer than two of ours not retreating stand within OursRange of the hit ally (a hero alone is D1's and D24's, not a
 * pair's; review of pair-join-on: a partner in retreat left a lone hero weighed 1v1, which could join). The hit ally is
 * the one at the lowest HP share.
 */
export function Gather(bot: Unit): Rec | undefined {
    let ally: Unit | undefined;
    const allies: Unit[] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!live(a)) continue;
        allies.push(a);
        if (dist(a, bot) > SETTINGS.AllyRange || !a.WasRecentlyDamagedByAnyHero(SETTINGS.HitRecent)) continue;
        if (ally === undefined || a.GetHealth() / a.GetMaxHealth() < ally.GetHealth() / ally.GetMaxHealth()) ally = a;
    }
    if (ally === undefined) return undefined;
    const ours: Unit[] = allies.filter((a) => dist(a, ally!) <= SETTINGS.OursRange);
    if (ours.filter((a) => !RetreatState.Running(a)).length < 2) return undefined;
    return weigh(ally, ours);
}

/** The weighing around `ally` with our heroes `ours`: their seen heroes within FoeRange of it, or undefined with none. */
function weigh(ally: Unit, ours: Unit[]): Rec | undefined {
    const theirs: Unit[] = [];
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (live(e) && e.CanBeSeen() && dist(e, ally) <= SETTINGS.FoeRange) theirs.push(e);
    }
    if (theirs.length === 0) return undefined;
    const dmg: Record<number, Record<number, number>> = {};
    const fill = (from: Unit[], on: Unit[]) => {
        for (const f of from) {
            const row: Record<number, number> = {};
            for (const o of on) row[o.GetPlayerID()] = math.floor(f.GetEstimatedDamageToTarget(true, o, SETTINGS.Window, DamageType.All) + 0.5);
            dmg[f.GetPlayerID()] = row;
        }
    };
    fill(ours, theirs);
    fill(theirs, ours);
    return { ally: ally.GetPlayerID(), ours: ours.map((u) => member(u, true)), theirs: theirs.map((u) => member(u, false)), dmg };
}

interface State {
    /** When For last decided, and what: the record and answer, or none (no situation). */
    at?: number;
    rec?: Rec;
    ans?: Answer;
    /** The last `join` answer: when, and its target. */
    joinAt?: number;
    joinTgt?: number;
    /** The cut's last logged answer and when. */
    dec?: Dec;
    cutAt?: number;
}

const states: Record<number, State> = {};

/** The bot's decision, made afresh at most every Every s (the matrix is 2 x n x m estimates); reads only. */
export function For(bot: Unit): { rec?: Rec; ans?: Answer; fresh: boolean } {
    const now = DotaTime();
    const pid = bot.GetPlayerID();
    const st = (states[pid] = states[pid] ?? {});
    if (st.at !== undefined && now >= st.at && now - st.at < SETTINGS.Every) return { rec: st.rec, ans: st.ans, fresh: false };
    st.at = now;
    st.rec = bot.IsAlive() && now <= SETTINGS.Until ? Gather(bot) : undefined;
    st.ans = st.rec !== undefined ? Decide(st.rec) : undefined;
    if (st.ans?.dec === "join") {
        st.joinAt = now;
        st.joinTgt = st.ans.tgt;
    } else if (st.ans !== undefined) st.joinAt = undefined;
    return { rec: st.rec, ans: st.ans, fresh: true };
}

/**
 * With `Ours.PairJoin`: the enemy hero this bot joins the fight on (D10), or undefined. The last answer was `join` within
 * Keep s with no other answer since, the bot is not retreating, and the target is alive, seen and within TargetRange of it.
 */
export function Joins(bot: Unit): Unit | undefined {
    if (!Ours.On("PairJoin") || !bot.IsAlive() || RetreatState.Running(bot)) return undefined;
    For(bot);
    const st = states[bot.GetPlayerID()];
    if (st?.joinAt === undefined || DotaTime() - st.joinAt > SETTINGS.Keep) return undefined;
    const t = st.joinTgt !== undefined ? heroOf(st.joinTgt) : undefined;
    if (t === undefined || !t.CanBeSeen() || dist(t, bot) > SETTINGS.TargetRange) return undefined;
    return t;
}

function heroOf(pid: number): Unit | undefined {
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) if (live(e) && e.GetPlayerID() === pid) return e;
    return undefined;
}

function members(ms: Member[]): string {
    return ms.map((m) => [m.pid, m.x, m.y, m.hp, m.mhp, ...(m.ret !== undefined ? [m.ret] : [])].join(",")).join(";");
}

function dmgOf(rec: Rec): string {
    const out: string[] = [];
    for (const side of [rec.ours, rec.theirs]) for (const f of side) for (const [to, d] of Object.entries(rec.dmg[f.pid] ?? {})) out.push(`${f.pid},${to},${d}`);
    return out.join(";");
}

// --- Slice join-after (shadow): the weighing after a fight of ours ends, read without the hit (ev=join_after). ---

interface Watch {
    kind: string;
    why: string;
    tgt: number;
    start: number;
    next: number;
    samples: string[];
}

const watches: Record<number, Watch | undefined> = {};

const r3 = (v: number): number => math.floor(v * 1000 + 0.5) / 1000;
const r2 = (v: number): number => math.floor(v * 100 + 0.5) / 100;
/** A sample's field: whole numbers without a decimal point (Lua prints 1.0), others as rounded. */
const f = (v: number | string): string => (type(v) !== "number" ? (v as string) : v === math.floor(v as number) ? string.format("%d", v) : string.format("%g", v));

function flush(pid: number, res: string): void {
    const w = watches[pid];
    if (w === undefined) return;
    watches[pid] = undefined;
    Telemetry.Event("join_after", [
        ["pid", pid],
        ["kind", w.kind],
        ["why", w.why],
        ["tgt", w.tgt],
        ["res", res],
        ["s", w.samples.join(";")],
    ]);
}

/**
 * A taken `join` or `trade` window of `bot` on `tpid` has ended with `why` (states/core_trade close): watch the weighing for
 * AfterWindow s, while telemetry is on and in the laning stage. A watch still open ends `reopen`. Reads only.
 */
export function After(bot: Unit, kind: string, why: string, tpid: number): void {
    if (!Telemetry.IsEnabled()) return;
    const pid = bot.GetPlayerID();
    flush(pid, "reopen");
    const now = DotaTime();
    if ((kind !== "join" && kind !== "trade") || now > SETTINGS.Until || !bot.IsAlive()) return;
    watches[pid] = { kind, why, tgt: tpid, start: now, next: now, samples: [] };
}

/** Any CoreTrade window of `bot` (trade, join, kill, fight) has started: an open watch ends `reopen` (the fight went on). Reads only. */
export function Reopened(bot: Unit): void {
    flush(bot.GetPlayerID(), "reopen");
}

/** One sample of the watch: the weighing around the bot itself (no hit and no pair needed). */
function sample(bot: Unit, w: Watch, now: number): string {
    const allies: Unit[] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) if (live(a) && dist(a, bot) <= SETTINGS.OursRange) allies.push(a);
    const t = heroOf(w.tgt);
    const seen = t !== undefined && t.CanBeSeen();
    const thp = seen ? r2(t!.GetHealth() / math.max(1, t!.GetMaxHealth())) : -1;
    const d = seen ? math.floor(dist(t!, bot) + 0.5) : -1;
    const hp = r2(bot.GetHealth() / math.max(1, bot.GetMaxHealth()));
    const dt = math.floor((now - w.start) * 10 + 0.5) / 10;
    const rec = weigh(bot, allies);
    if (rec === undefined) return [dt, "n", 0, 0, thp, d, hp, allies.filter((a) => !RetreatState.Running(a)).length, 0].map((v) => f(v)).join(":");
    const a = Decide(rec);
    const no = rec.ours.filter((m) => m.ret !== 1).length;
    return [dt, a.dec.substring(0, 1), r3(a.ko), r3(a.kt), thp, d, hp, no, rec.theirs.length].map((v) => f(v)).join(":");
}

/** Per frame: the open watch's sample when due, and its line at the end. Reads only. */
function tickAfter(bot: Unit, now: number): void {
    const pid = bot.GetPlayerID();
    const w = watches[pid];
    if (w === undefined) return;
    // A bot that died is not ticked until it respawns (early respawns fit inside the window): a missed sample died with it.
    if (!bot.IsAlive() || now > w.next + SETTINGS.AfterEvery) return flush(pid, "dead");
    if (now > SETTINGS.Until) return flush(pid, "stage");
    if (now >= w.next) {
        w.samples.push(sample(bot, w, now));
        w.next = now + SETTINGS.AfterEvery;
    }
    if (now - w.start >= SETTINGS.AfterWindow) flush(pid, "full");
}

/** Per frame (index Tick): on each fresh decision in the laning stage, its cut; the join-after watch. Reads only. */
export function Tick(bot: Unit): void {
    if (Telemetry.IsEnabled()) tickAfter(bot, DotaTime());
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || !bot.IsAlive()) return;
    const now = DotaTime();
    if (now > SETTINGS.Until) return;
    const pid = bot.GetPlayerID();
    const { rec, ans: a, fresh } = For(bot);
    if (!fresh) return;
    const st = states[pid];
    if (rec === undefined || a === undefined) {
        st.dec = undefined;
        return;
    }
    if (a.dec === st.dec && now - (st.cutAt ?? -math.huge) < SETTINGS.CutEvery) return;
    st.dec = a.dec;
    st.cutAt = now;
    Telemetry.Event("cut", [
        ["pid", pid],
        ["kind", "join"],
        ["al", rec.ally],
        ["po", members(rec.ours)],
        ["pt", members(rec.theirs)],
        ["dm", dmgOf(rec)],
        ["dec", a.dec],
        ["tgt", a.tgt],
        ["ko", math.floor(a.ko * 1000 + 0.5) / 1000],
        ["kt", math.floor(a.kt * 1000 + 0.5) / 1000],
    ]);
}

