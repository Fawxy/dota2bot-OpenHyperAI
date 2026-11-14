/**
 * Pair join (D10, slice pair-join): a laner whose ally in reach is being hit by an enemy hero joins the fight when what our
 * heroes there can do to theirs outweighs what theirs can do to ours. In shadow: `Tick` decides and logs `ev=cut kind=join`
 * (the inputs, the answer); nothing acts on it yet. `Decide` is pure, so a cut replays offline (driver pair_join).
 *
 * The weighing: over `Window` s, each side's best kill share, GetEstimatedDamageToTarget summed over its heroes on one target
 * over that target's HP, the target the side does best on. We join on theirs (`tgt`) when our share is the larger; numbers
 * against us leave it out at once (D1 is retreat's).
 */
import { DamageType, Unit, UnitType } from "bots/ts_libs/dota";
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

/** The rule: outnumbered stays out; else join when our best kill share beats theirs. */
export function Decide(rec: Rec): Answer {
    const [tgt, ko] = best(rec.ours, rec.theirs, rec.dmg);
    const [, kt] = best(rec.theirs, rec.ours, rec.dmg);
    if (rec.theirs.length > rec.ours.length) return { dec: "outnumbered", tgt, ko, kt };
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

/** The situation's record, or undefined when no ally within AllyRange was hit by a hero within HitRecent. The hit ally is the one at the lowest HP share. */
export function Gather(bot: Unit): Rec | undefined {
    let ally: Unit | undefined;
    const allies: Unit[] = [];
    for (const a of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (!live(a)) continue;
        allies.push(a);
        if (a === bot || dist(a, bot) > SETTINGS.AllyRange || !a.WasRecentlyDamagedByAnyHero(SETTINGS.HitRecent)) continue;
        if (ally === undefined || a.GetHealth() / a.GetMaxHealth() < ally.GetHealth() / ally.GetMaxHealth()) ally = a;
    }
    if (ally === undefined) return undefined;
    const ours: Unit[] = allies.filter((a) => dist(a, ally!) <= SETTINGS.OursRange);
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

const states: Record<number, { at?: number; dec?: Dec; cutAt?: number }> = {};

function members(ms: Member[]): string {
    return ms.map((m) => [m.pid, m.x, m.y, m.hp, m.mhp, ...(m.ret !== undefined ? [m.ret] : [])].join(",")).join(";");
}

function dmgOf(rec: Rec): string {
    const out: string[] = [];
    for (const side of [rec.ours, rec.theirs]) for (const f of side) for (const [to, d] of Object.entries(rec.dmg[f.pid] ?? {})) out.push(`${f.pid},${to},${d}`);
    return out.join(";");
}

/** Per frame (index Tick): every Every s in the laning stage, the decision and its cut. Reads only. */
export function Tick(bot: Unit): void {
    if (!Telemetry.IsEnabled() || Telemetry.Get().Cut !== true || !bot.IsAlive()) return;
    const now = DotaTime();
    if (now > SETTINGS.Until) return;
    const pid = bot.GetPlayerID();
    const st = (states[pid] = states[pid] ?? {});
    if (st.at !== undefined && now - st.at < SETTINGS.Every) return;
    st.at = now;
    const rec = Gather(bot);
    if (rec === undefined) {
        st.dec = undefined;
        return;
    }
    const a = Decide(rec);
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

