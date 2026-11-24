/**
 * Lane-hits check (`Overrides.LaneReadProbe`, probe games only; slice oha-lane-swings): is LaneHits right about who kills a
 * creep? Each frame, once per team VM, every lane's LaneHits rows are read and each creep's latest prediction kept: the hit
 * the forecast says kills it (`KillingHit`: its kind, the hero's player id, seconds to it, its commit). When a creep leaves
 * the read, one `ev=lane_hits_check` line: the last prediction beside who took it, read from the game: the heroes of the team
 * whose last hits (an enemy creep) or denies (an own creep) rose that frame (`rose`), and the visible enemy heroes' the same
 * way (`erose`; for an own creep their last hits, for an enemy creep their denies). Several creeps can die in one frame, so a
 * rise is the frame's, not the creep's: the reader pairs them. Reads and logs only. Runs under pcall.
 */
import { Lane, Unit, UnitType } from "bots/ts_libs/dota";
import * as LaneHits from "bots/FunLib/humaniser/lane_hits";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

const LANES: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];

/** The hero counters the probe reads (GetDenies is not declared on Unit). */
interface Counted {
    GetLastHits(): number;
    GetDenies(): number;
}
interface Tally {
    lh: number;
    dn: number;
}

/** A hero's counters, or undefined when the reads fail (an enemy handle may not answer). */
function tally(h: Unit): Tally | undefined {
    const [ok, v] = pcall((): Tally => ({ lh: (h as unknown as Counted).GetLastHits(), dn: (h as unknown as Counted).GetDenies() }));
    return ok ? (v as Tally) : undefined;
}

interface Pred {
    creep: Unit;
    lane: Lane;
    own: boolean;
    cid: number;
    hp: number;
    by: string;
    pid: number;
    t: number;
    commit: number;
    at: number;
}

let frameAt: number | undefined;
let known = new LuaTable<Unit, Pred>();
/** Per hero handle: last hits and denies at the last frame. */
let counts = new LuaTable<Unit, Tally>();

export function ResetCache(): void {
    frameAt = undefined;
    known = new LuaTable<Unit, Pred>();
    counts = new LuaTable<Unit, Tally>();
}

function round(x: number): number {
    return math.floor(x * 1000 + 0.5) / 1000;
}

/** The heroes whose last hits (`lh`) or denies (`dn`) rose since the last frame: player ids joined by `;`. */
function risen(heroes: Unit[]): { lh: string; dn: string } {
    const lh: number[] = [];
    const dn: number[] = [];
    for (const h of heroes) {
        const now = tally(h);
        const was = counts.get(h);
        if (now === undefined || was === undefined) continue;
        if (now.lh > was.lh) lh.push(h.GetPlayerID());
        if (now.dn > was.dn) dn.push(h.GetPlayerID());
    }
    return { lh: lh.join(";"), dn: dn.join(";") };
}

function remember(heroes: Unit[]): void {
    for (const h of heroes) {
        const now = tally(h);
        if (now !== undefined) counts.set(h, now);
    }
}

function teamHeroes(): Unit[] {
    const out: Unit[] = [];
    for (let i = 1; i <= 5; i++) {
        const h = GetTeamMember(i);
        if (h !== undefined && h !== null && !h.IsNull() && !h.IsIllusion()) out.push(h);
    }
    return out;
}

function enemyHeroes(): Unit[] {
    const out: Unit[] = [];
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) if (!h.IsNull() && !h.IsIllusion() && h.CanBeSeen()) out.push(h);
    return out;
}

function frame(bot: Unit): void {
    const now = DotaTime();
    if (frameAt === now) return;
    frameAt = now;
    const team = bot.GetTeam();
    const ours = teamHeroes();
    const theirs = enemyHeroes();
    const seen = new LuaTable<Unit, boolean>();
    for (const lane of LANES) {
        for (const r of LaneHits.Read(team, lane)) {
            seen.set(r.creep, true);
            const k = LaneHits.KillingHit(r);
            const a = k !== undefined && (k.by === "hero" || k.by === "self") ? (k.attacker as unknown as Unit) : undefined;
            known.set(r.creep, {
                creep: r.creep, lane, own: r.own, cid: Telemetry.CreepId(r.creep), hp: r.hp,
                by: k === undefined ? "none" : k.by, pid: a !== undefined ? a.GetPlayerID() : -1,
                t: k === undefined ? -1 : k.t, commit: k === undefined ? -1 : k.commit, at: now,
            });
        }
    }
    const left: Pred[] = [];
    for (const [c, p] of known) if (seen.get(c) !== true) left.push(p);
    if (left.length > 0) {
        const o = risen(ours);
        const e = risen(theirs);
        for (const p of left) {
            known.delete(p.creep);
            const dead = p.creep.IsNull() || !p.creep.IsAlive();
            Telemetry.Event("lane_hits_check", [
                ["lane", p.lane],
                ["own", p.own ? 1 : 0],
                ["cid", p.cid],
                ["hp", math.floor(p.hp)],
                ["pby", p.by],
                ["ppid", p.pid],
                ["pt", p.t < 0 ? -1 : round(p.t)],
                ["pc", p.commit < 0 ? -1 : round(p.commit)],
                ["age", round(now - p.at)],
                ["rose", (p.own ? o.dn : o.lh) === "" ? undefined : p.own ? o.dn : o.lh],
                ["erose", (p.own ? e.lh : e.dn) === "" ? undefined : p.own ? e.lh : e.dn],
                ["end", dead ? "dead" : "left"],
            ]);
        }
    }
    remember(ours);
    remember(theirs);
}

export function Tick(bot: Unit): void {
    if (Overrides.Get("LaneReadProbe") !== true) return;
    pcall(frame, bot);
}
