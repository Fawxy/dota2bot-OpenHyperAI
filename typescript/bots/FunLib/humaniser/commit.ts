/**
 * The commitment tracker (decision centre pilot step 1, `Ours.PricedLeave`; master docs/proposals/2026-11-21-decision-centre.md s11 and
 * 2026-11-20-leave-on-commitment.md s2): each enemy hero's state towards each of our heroes, `near`, `poked` or `committed`, from the
 * times it damaged us, and what it could land on us before we react (ready spells apart from one attack). LOGGED ONLY: nothing reads it
 * to change behaviour (`ev=commit`, `ev=dmgcb`, the `rcs` column of `ev=cut kind=safe`).
 *
 * Hit times come from InstallDamageCallback, installed on each of our heroes' player ids: smoke dc-step1 (22/11/2026) showed a player's
 * callback fires for damage that player's hero takes, with one table `{unit, player_id, attacking_unit, attacking_player_id, damage,
 * ability}` (player_id the victim's). An event counts only when it resolves to an enemy hero damaging one of our heroes. Until the first
 * such event, and as a cross-check after it, `WasRecentlyDamagedByHero` is polled each tick; the state follows the callback once it has
 * delivered one hit this game (`src`).
 */
import { DamageType, Team, Unit, UnitType } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as SpellReady from "bots/FunLib/humaniser/spell_ready";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export const SETTINGS = {
    /** `poked`: damaged us within this many seconds (`SafeGather.SETTINGS.PressWindow`). */
    PokeWindow: 3,
    /** `committed`: two hits at least `SecondGap` apart within this many seconds. */
    CommitWindow: 4,
    /**
     * Two hits this far apart (s) are "separate seconds": a spell and the attack that follows it land together, a laner's next attack
     * lands 1.2 to 1.7 s later. judgement. A damage-over-time spell ticking each second reads as committed (open in the design).
     */
    SecondGap: 1,
    /** The burst-now window (s): ready spells and one attack that land before we can react (`SafeGather.SETTINGS.ExitTurn`). judgement. */
    ReactWindow: 1,
    /** `near`: an enemy hero within its attack range plus its move speed over this many seconds plus both hulls (the held read's horizon). */
    NearHorizon: 2,
    /**
     * `near` is held this many seconds after the enemy was last seen in reach (hysteresis: a laner stepping in and out of the reach
     * edge, or into fog, keeps one near spell instead of a near/gone pair each step). judgement.
     */
    NearHold: 1,
    /** Hit times older than this are dropped. */
    Keep: 6,
    /** `ev=dmgcb kind=sum` every this many seconds. */
    SumEvery: 60,
    /** The first this many callback calls each log their argument shape (`ev=dmgcb kind=shape`). */
    ShapeLines: 3,
};

export type State = "gone" | "near" | "poked" | "committed";

const MAX_PLAYER_ID = 23;

// ------------------------------------------------------------------------------------------------------------------- pure

/** The hit evidence's state of one enemy: `committed`, `poked`, or undefined (no damage within `PokeWindow`). `pokers`: how many enemy heroes damaged us within `PokeWindow`, this one included. */
export function HitState(hits: number[], now: number, pokers: number): { st: "poked" | "committed" | undefined; why?: string } {
    let last = -math.huge;
    let first = math.huge;
    for (const t of hits) {
        if (t > now || now - t > SETTINGS.CommitWindow) continue;
        if (t > last) last = t;
        if (t < first) first = t;
    }
    if (now - last > SETTINGS.PokeWindow) return { st: undefined };
    if (last - first >= SETTINGS.SecondGap) return { st: "committed", why: "second" };
    if (pokers >= 2) return { st: "committed", why: "pair" };
    return { st: "poked", why: "hit" };
}

/**
 * How many distinct enemy heroes in `hitsBy` have at least one hit time in [now - `window`, now]. With `window` `PokeWindow` (3 s) it is
 * `nh`, the `pokers` of HitState; step 2's chance tables index by it (0, 1, 2+).
 */
export function CountHitters(hitsBy: Record<number, number[] | undefined>, now: number, window: number = SETTINGS.PokeWindow): number {
    let n = 0;
    for (const [, hits] of pairs(hitsBy)) {
        for (const t of hits) {
            if (t <= now && now - t <= window) {
                n++;
                break;
            }
        }
    }
    return n;
}

/** Every enemy's state towards one hero from its hit times (`hitsBy` by enemy pid) and which enemies are near: hit evidence first, then `near`, else `gone`. */
export function States(hitsBy: Record<number, number[] | undefined>, near: Record<number, boolean | undefined>, now: number): Record<number, { st: State; why: string }> {
    const pokers = CountHitters(hitsBy, now);
    const out: Record<number, { st: State; why: string }> = {};
    for (const [epid, hits] of pairs(hitsBy)) {
        const h = HitState(hits, now, pokers);
        if (h.st !== undefined) out[epid] = { st: h.st, why: h.why! };
    }
    for (const [epid, on] of pairs(near)) {
        if (on && out[epid] === undefined) out[epid] = { st: "near", why: "reach" };
    }
    return out;
}

/** Ready spells' part of an enemy's damage on us over the reaction window, and one attack: `DamageOn` less its attack part, floored at 0. */
export function SplitBurst(total: number, attackOverWindow: number, oneAttack: number): { spell: number; attack: number } {
    return { spell: math.max(0, total - attackOverWindow), attack: math.max(0, oneAttack) };
}

/** A callback's arguments resolved to who damaged whom, or undefined. Handles are tables with methods; a plain table is read by its keys. */
export interface Parsed {
    victim?: Unit;
    attacker?: Unit;
    attackerPid?: number;
    dmg?: number;
}

function isHandle(a: unknown): boolean {
    return type(a) === "table" && (a as { GetUnitName?: unknown }).GetUnitName !== undefined;
}

export function ParseArgs(args: unknown[]): Parsed {
    const out: Parsed = {};
    const units: Unit[] = [];
    for (let i = 0; i < 4; i++) {
        const a = args[i];
        if (isHandle(a)) units.push(a as Unit);
        else if (type(a) === "number" && out.dmg === undefined) out.dmg = a as number;
        else if (type(a) === "table") {
            const t = a as Record<string, unknown>;
            for (const k of ["damage", "nDamage", "amount"]) if (type(t[k]) === "number" && out.dmg === undefined) out.dmg = t[k] as number;
            // `player_id` is the victim's (smoke dc-step1), so it is never read as the attacker.
            for (const k of ["attacking_player_id", "attacker_player_id"]) if (type(t[k]) === "number" && out.attackerPid === undefined) out.attackerPid = t[k] as number;
            for (const k of ["unit", "victim", "target"]) if (isHandle(t[k]) && out.victim === undefined) out.victim = t[k] as Unit;
            for (const k of ["attacking_unit", "attacker", "source"]) if (isHandle(t[k]) && out.attacker === undefined) out.attacker = t[k] as Unit;
        }
    }
    if (units.length >= 2) {
        out.victim = out.victim ?? units[0];
        out.attacker = out.attacker ?? units[1];
    } else if (units.length === 1) {
        if (out.victim === undefined) out.victim = units[0];
        else if (out.attacker === undefined) out.attacker = units[0];
    }
    return out;
}

/**
 * The (our hero's pid, enemy hero's pid) a parsed event is, or undefined (an attacker that is not an enemy hero, or none named).
 */
export function Resolve(p: Parsed, ours: number, teamOf: (this: void, pid: number) => number): { victim: number; attacker: number } | undefined {
    const v = p.victim;
    if (v === undefined || !v.IsHero() || v.IsIllusion() || v.GetTeam() !== ours) return undefined;
    let apid = p.attackerPid;
    if (p.attacker !== undefined) {
        if (!p.attacker.IsHero() || p.attacker.IsIllusion()) return undefined;
        apid = p.attacker.GetPlayerID();
    }
    if (apid === undefined || apid < 0) return undefined;
    const at = teamOf(apid);
    if (at === ours || (at !== Team.Radiant && at !== Team.Dire)) return undefined;
    return { victim: v.GetPlayerID(), attacker: apid };
}

// --------------------------------------------------------------------------------------------------------------- the game

type Hits = Record<number, Record<number, number[] | undefined> | undefined>;
const cbHits: Hits = {};
const pollHits: Hits = {};
let cbLive = false;
let installedAll = false;
let shapes = 0;
const counts = { n: 0, ok: 0, cb: 0, poll: 0 };
let sumAt: number | undefined;
const lastPoll: Record<number, number | undefined> = {};
const current: Record<number, Record<number, State> | undefined> = {};
/** Per our pid: the hitter count `nh` as last ticked (`rcs`). */
const currentNh: Record<number, number | undefined> = {};
/** Per our pid, per enemy pid: until when `near` holds (`NearHold` past the last tick it was seen in reach). */
const nearUntil: Record<number, Record<number, number | undefined> | undefined> = {};
/** Per our pid: the hit source its last tick used, so the poll-to-callback switch is not logged as a game event. */
const lastSrc: Record<number, string | undefined> = {};

function push(store: Hits, victim: number, attacker: number, t: number): void {
    const by = store[victim] ?? {};
    store[victim] = by;
    const list = by[attacker] ?? [];
    const keep: number[] = [];
    for (const x of list) if (t - x <= SETTINGS.Keep) keep.push(x);
    keep.push(t);
    by[attacker] = keep;
}

function describe(args: unknown[]): string {
    const parts: string[] = [];
    for (let i = 0; i < 4; i++) {
        const a = args[i];
        if (isHandle(a)) {
            const u = a as Unit;
            parts.push(`h:${u.GetUnitName()}:${u.GetPlayerID()}`);
        } else if (type(a) === "table") {
            const keys: string[] = [];
            for (const [k, v] of pairs(a as Record<string, unknown>)) keys.push(`${tostring(k)}=${isHandle(v) ? "h" : type(v) === "number" || type(v) === "string" ? tostring(v) : type(v)}`);
            parts.push(`{${keys.join(",")}}`);
        } else parts.push(type(a) === "number" ? `n:${tostring(a)}` : type(a));
    }
    return parts.join("|");
}

function onDamage(this: void, installed: number, args: unknown[]): void {
    counts.n++;
    const r = Resolve(ParseArgs(args), GetTeam(), GetTeamForPlayer);
    if (shapes < SETTINGS.ShapeLines) {
        shapes++;
        Telemetry.Event("dmgcb", [["kind", "shape"], ["ipid", installed], ["ok", r !== undefined ? 1 : 0], ["args", describe(args)]]);
    }
    if (r === undefined) return;
    counts.ok++;
    counts.cb++;
    cbLive = true;
    push(cbHits, r.victim, r.attacker, DotaTime());
}

/**
 * InstallDamageCallback on each of our heroes' player ids (it reports the damage that hero takes), once per team VM.
 * Clash: `Overrides.ApiProbe` (api_probe.ts, a probe run, off in normal games) installs its own callback on every hero id. Whether the
 * API keeps one callback per id (the later install wins and the other goes silent) is not known, so a game with the probe on may
 * leave this tracker on the poll or the probe blind; `ev=dmgcb kind=sum` (`n` 0, `live` 0) shows the first. Run them apart.
 */
function install(): void {
    if (installedAll) return;
    installedAll = true;
    const g = _G as unknown as { InstallDamageCallback?: unknown };
    if (type(g.InstallDamageCallback) !== "function") {
        Telemetry.Event("dmgcb", [["kind", "missing"]]);
        return;
    }
    const installDamage = g.InstallDamageCallback as (this: void, pid: number, fn: (this: void, ...args: unknown[]) => void) => void;
    let n = 0;
    for (let pid = 0; pid <= MAX_PLAYER_ID; pid++) {
        const t = GetTeamForPlayer(pid);
        if (t !== GetTeam()) continue;
        const ipid = pid;
        installDamage(ipid, (...args: unknown[]) => {
            const [ok, err] = pcall(onDamage, ipid, args);
            if (!ok) Telemetry.Failed("Commit.onDamage", err);
        });
        n++;
    }
    Telemetry.Event("dmgcb", [["kind", "installed"], ["n", n]]);
}

const r0 = (v: number): number => math.floor(v + 0.5);

function burstOn(e: Unit, bot: Unit): { spell: number; attack: number } {
    const w = SETTINGS.ReactWindow;
    const total = SpellReady.DamageOn(e, bot, w);
    const spa = (e as Unit & { GetSecondsPerAttack?(): number }).GetSecondsPerAttack?.() ?? 0;
    const one = bot.GetActualIncomingDamage(e.GetAttackDamage(), DamageType.Physical);
    return SplitBurst(total, spa > 0 ? (one * w) / spa : 0, one);
}

/** Our hero's view of one enemy as last ticked (`rcs` on the safe cut): `n` near, `p` poked, `c` committed, `-` gone or never seen. */
export function Code(ourPid: number, epid: number): string {
    const st = current[ourPid]?.[epid];
    return st === "near" ? "n" : st === "poked" ? "p" : st === "committed" ? "c" : "-";
}

/** The hitter count `nh` towards our hero as last ticked (`rcs`), or undefined before its first tick. */
export function Nh(ourPid: number): number | undefined {
    return currentNh[ourPid];
}

/**
 * How many distinct living enemy heroes hit our hero `pid` within the last `windowSec` seconds, fogged ones included (hit times are kept
 * by player id from the source the tracker uses now: the callback once live, else the flag poll, which records visible enemies only).
 * Hit times are kept `Keep` (6 s), so a longer window reads as 6 s. Reads the store directly: current between ticks too.
 */
export function Hitters(pid: number, windowSec: number): number {
    const by = (cbLive ? cbHits : pollHits)[pid];
    if (by === undefined) return 0;
    const live: Record<number, number[] | undefined> = {};
    for (const [epid, hits] of pairs(by)) if (IsHeroAlive(epid)) live[epid] = hits;
    return CountHitters(live, DotaTime(), windowSec);
}

/**
 * The burst now on `bot` (`ReactWindow`, 1 s): per visible living enemy hero, its ready-spell part and one attack (the `bs`/`ba` split),
 * and their sum. Takes the handle, not a pid: the reads need our hero's resistances. A fogged enemy has no handle and is left out.
 */
export function BurstNow(bot: Unit): { by: Record<number, { spell: number; attack: number }>; sum: number } {
    const by: Record<number, { spell: number; attack: number }> = {};
    let sum = 0;
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e.IsIllusion() || !e.IsAlive()) continue;
        const b = burstOn(e, bot);
        by[e.GetPlayerID()] = b;
        sum += b.spell + b.attack;
    }
    return { by, sum };
}

/** The living enemy heroes' player ids, visible or not (GetTeamForPlayer and IsHeroAlive read through fog). */
function livingEnemies(ours: number): number[] {
    const out: number[] = [];
    for (let p = 0; p <= MAX_PLAYER_ID; p++) {
        const t = GetTeamForPlayer(p);
        if (t === ours || (t !== Team.Radiant && t !== Team.Dire) || !IsHeroAlive(p)) continue;
        out.push(p);
    }
    return out;
}

/**
 * The tracker's step, once per hero per Humaniser tick (10 Hz): installs the callback, polls the damage flags, and logs each enemy's
 * state change towards `bot` as `ev=commit`. A lower rate loses the poll's hit times (a 1 s gap between two hits needs a few samples a
 * second) and delays a transition's line. Nothing reads the state but `Code` and `Nh` (log columns).
 *
 * The state is keyed on every living enemy hero's player id, seen or not: an enemy hitting us from fog keeps its hit-based state (the
 * callback names it). Only the reads that need a visible handle are skipped for a fogged enemy: the flag poll, the reach test (its
 * `near` holds `NearHold` past the last tick it was seen in reach) and the burst read (`bs`/`ba` empty, left out of `bsum`). No API gives
 * a fogged enemy's current position (GetHeroLastSeenInfo is the last seen one, which the hold already covers).
 */
export function Tick(bot: Unit): void {
    if (!Ours.On("PricedLeave")) return;
    install();
    const now = DotaTime();
    if (sumAt === undefined) sumAt = now + SETTINGS.SumEvery;
    else if (now >= sumAt) {
        sumAt = now + SETTINGS.SumEvery;
        Telemetry.Event("dmgcb", [["kind", "sum"], ["n", counts.n], ["ok", counts.ok], ["cb", counts.cb], ["poll", counts.poll], ["live", cbLive ? 1 : 0]]);
        counts.n = 0;
        counts.ok = 0;
        counts.cb = 0;
        counts.poll = 0;
    }
    const pid = bot.GetPlayerID();
    const prev = current[pid] ?? {};
    const hp = bot.GetHealth();
    if (!bot.IsAlive()) {
        // Our hero died: each enemy still tracked goes `gone` (why dead), once.
        if (Telemetry.IsEnabled()) {
            for (const [epid, was] of pairs(prev)) {
                Telemetry.Event("commit", [["pid", pid], ["epid", epid], ["st", "gone"], ["was", was], ["why", "dead"], ["nh", currentNh[pid]], ["src", lastSrc[pid]], ["hp", hp]]);
            }
        }
        current[pid] = {};
        currentNh[pid] = undefined;
        nearUntil[pid] = {};
        lastPoll[pid] = undefined;
        return;
    }
    const since = lastPoll[pid];
    const w = since === undefined ? 0.1 : math.max(0.1, math.min(0.5, now - since));
    lastPoll[pid] = now;
    const at = bot.GetLocation();
    const ourHull = bot.GetBoundingRadius();
    const handles: Record<number, Unit> = {};
    for (const e of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (e.IsIllusion() || !e.IsAlive()) continue;
        handles[e.GetPlayerID()] = e;
    }
    const until = nearUntil[pid] ?? {};
    nearUntil[pid] = until;
    const src = cbLive ? "cb" : "poll";
    const near: Record<number, boolean> = {};
    const alive: Record<number, boolean> = {};
    const hitsBy: Record<number, number[] | undefined> = {};
    for (const epid of livingEnemies(bot.GetTeam())) {
        alive[epid] = true;
        const e = handles[epid];
        if (e !== undefined) {
            if (bot.WasRecentlyDamagedByHero(e, w)) {
                counts.poll++;
                push(pollHits, pid, epid, now);
            }
            const l = e.GetLocation();
            const d = math.sqrt((l.x - at.x) ** 2 + (l.y - at.y) ** 2);
            const reach = e.GetAttackRange() + e.GetCurrentMovementSpeed() * SETTINGS.NearHorizon + e.GetBoundingRadius() + ourHull;
            if (d <= reach) until[epid] = now + SETTINGS.NearHold;
        }
        near[epid] = (until[epid] ?? -math.huge) >= now;
        hitsBy[epid] = (cbLive ? cbHits : pollHits)[pid]?.[epid];
    }
    for (const [epid] of pairs(until)) if (alive[epid] !== true) until[epid] = undefined;
    // Only living enemies' hits are counted: `nh` and `pair` count living hitters.
    const nh = CountHitters(hitsBy, now);
    const states = States(hitsBy, near, now);
    const next: Record<number, State> = {};
    let changed = false;
    for (const [epid, s] of pairs(states)) {
        next[epid] = s.st;
        if (prev[epid] !== s.st) changed = true;
    }
    for (const [epid] of pairs(prev)) if (next[epid] === undefined) changed = true;
    current[pid] = next;
    currentNh[pid] = nh;
    const switched = lastSrc[pid] === "poll" && src === "cb";
    lastSrc[pid] = src;
    if (switched) {
        // The poll-to-callback switch replaces the hit list: the state jump it makes is not a game event, so this tick logs only the switch.
        Telemetry.Event("dmgcb", [["kind", "switch"], ["ipid", pid]]);
        return;
    }
    if (!changed || !Telemetry.IsEnabled()) return;
    // The burst read is made only on a change: one estimate per visible enemy in play.
    const burst: Record<number, { spell: number; attack: number }> = {};
    let sum = 0;
    for (const [epid] of pairs(next)) {
        const e = handles[epid];
        if (e === undefined) continue;
        const b = burstOn(e, bot);
        burst[epid] = b;
        sum += b.spell + b.attack;
    }
    const emit = (epid: number, st: State, was: State, why: string): void => {
        let hits = 0;
        for (const t of hitsBy[epid] ?? []) if (now - t <= SETTINGS.CommitWindow) hits++;
        const b = burst[epid];
        Telemetry.Event("commit", [
            ["pid", pid],
            ["epid", epid],
            ["st", st],
            ["was", was],
            ["why", why],
            ["hits", hits],
            ["nh", nh],
            ["src", src],
            ["hp", hp],
            ["bs", b !== undefined ? r0(b.spell) : undefined],
            ["ba", b !== undefined ? r0(b.attack) : undefined],
            ["bsum", r0(sum)],
            ["bra", sum > 0 ? math.floor((hp / sum) * 100 + 0.5) / 100 : undefined],
        ]);
    };
    for (const [epid, st] of pairs(next)) {
        const was = prev[epid] ?? "gone";
        if (was !== st) emit(epid, st, was, states[epid].why);
    }
    for (const [epid, was] of pairs(prev)) {
        if (next[epid] === undefined) emit(epid, "gone", was, alive[epid] !== true ? "edead" : handles[epid] === undefined ? "fog" : "left");
    }
}

/** Tests: forget every hit, state and the install. */
export function Reset(): void {
    for (const k in cbHits) delete cbHits[k as unknown as number];
    for (const k in pollHits) delete pollHits[k as unknown as number];
    for (const k in current) delete current[k as unknown as number];
    for (const k in currentNh) delete currentNh[k as unknown as number];
    for (const k in nearUntil) delete nearUntil[k as unknown as number];
    for (const k in lastSrc) delete lastSrc[k as unknown as number];
    for (const k in lastPoll) delete lastPoll[k as unknown as number];
    cbLive = false;
    installedAll = false;
    shapes = 0;
    sumAt = undefined;
    counts.n = 0;
    counts.ok = 0;
    counts.cb = 0;
    counts.poll = 0;
}
