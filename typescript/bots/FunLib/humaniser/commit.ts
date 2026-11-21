/**
 * The commitment tracker (decision centre pilot step 1, `Ours.PricedLeave`; master docs/proposals/2026-11-21-decision-centre.md s11 and
 * 2026-11-20-leave-on-commitment.md s2): each enemy hero's state towards each of our heroes, `near`, `poked` or `committed`, from the
 * times it damaged us, and what it could land on us before we react (ready spells apart from one attack). LOGGED ONLY: nothing reads it
 * to change behaviour (`ev=commit`, `ev=dmgcb`, the `rcs` column of `ev=cut kind=safe`).
 *
 * Hit times come from InstallDamageCallback (installed on every hero's player id, since whether a player's callback reports the damage
 * it deals or takes is not verified: an event counts only when it resolves to an enemy hero damaging one of our heroes). Until the first
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

/** Every enemy's state towards one hero from its hit times (`hitsBy` by enemy pid) and which enemies are near: hit evidence first, then `near`, else `gone`. */
export function States(hitsBy: Record<number, number[] | undefined>, near: Record<number, boolean | undefined>, now: number): Record<number, { st: State; why: string }> {
    let pokers = 0;
    for (const [, hits] of pairs(hitsBy)) {
        for (const t of hits) {
            if (t <= now && now - t <= SETTINGS.PokeWindow) {
                pokers++;
                break;
            }
        }
    }
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
            for (const k of ["player_id", "attacker_player_id", "attacker_pid", "playerid"]) if (type(t[k]) === "number" && out.attackerPid === undefined) out.attackerPid = t[k] as number;
            for (const k of ["unit", "victim", "target"]) if (isHandle(t[k]) && out.victim === undefined) out.victim = t[k] as Unit;
            for (const k of ["attacker", "source"]) if (isHandle(t[k]) && out.attacker === undefined) out.attacker = t[k] as Unit;
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
 * The (our hero's pid, enemy hero's pid) a parsed event is, or undefined. `installed` is the player id the callback was installed for:
 * with a victim and no attacker it is the attacker when it is an enemy's (a callback for the damage a player deals).
 */
export function Resolve(p: Parsed, installed: number, ours: number, teamOf: (this: void, pid: number) => number): { victim: number; attacker: number } | undefined {
    const v = p.victim;
    if (v === undefined || !v.IsHero() || v.IsIllusion() || v.GetTeam() !== ours) return undefined;
    let apid = p.attackerPid;
    if (p.attacker !== undefined) {
        if (!p.attacker.IsHero() || p.attacker.IsIllusion()) return undefined;
        apid = p.attacker.GetPlayerID();
    }
    if (apid === undefined && teamOf(installed) !== ours) apid = installed;
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
    const r = Resolve(ParseArgs(args), installed, GetTeam(), GetTeamForPlayer);
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

/** InstallDamageCallback on every hero's player id, once per team VM. */
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
        if (t !== Team.Radiant && t !== Team.Dire) continue;
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

/** Our hero's view of one enemy as last ticked (`rc` on the safe cut): `n` near, `p` poked, `c` committed, `-` gone or never seen. */
export function Code(ourPid: number, epid: number): string {
    const st = current[ourPid]?.[epid];
    return st === "near" ? "n" : st === "poked" ? "p" : st === "committed" ? "c" : "-";
}

/**
 * The tracker's step, once per hero per Humaniser tick (10 Hz): installs the callback, polls the damage flags, and logs each enemy's
 * state change towards `bot` as `ev=commit`. A lower rate loses the poll's hit times (a 1 s gap between two hits needs a few samples a
 * second) and delays a transition's line. Nothing reads the state but `Code` (a log column).
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
    if (!bot.IsAlive()) {
        current[pid] = {};
        lastPoll[pid] = undefined;
        return;
    }
    const since = lastPoll[pid];
    const w = since === undefined ? 0.1 : math.max(0.1, math.min(0.5, now - since));
    lastPoll[pid] = now;
    const at = bot.GetLocation();
    const near: Record<number, boolean> = {};
    const handles: Record<number, Unit> = {};
    for (const e of GetUnitList(UnitType.EnemyHeroes)) {
        if (e.IsIllusion() || !e.IsAlive()) continue;
        const epid = e.GetPlayerID();
        handles[epid] = e;
        if (bot.WasRecentlyDamagedByHero(e, w)) {
            counts.poll++;
            push(pollHits, pid, epid, now);
        }
        const l = e.GetLocation();
        const d = math.sqrt((l.x - at.x) ** 2 + (l.y - at.y) ** 2);
        const reach = e.GetAttackRange() + e.GetCurrentMovementSpeed() * SETTINGS.NearHorizon + e.GetBoundingRadius() + bot.GetBoundingRadius();
        near[epid] = d <= reach;
    }
    const src = cbLive ? "cb" : "poll";
    const states = States((cbLive ? cbHits : pollHits)[pid] ?? {}, near, now);
    const next: Record<number, State> = {};
    let changed = false;
    for (const [epid, s] of pairs(states)) {
        // A hero that died or left our list keeps no state, whatever its hit times say.
        if (handles[epid] === undefined) continue;
        next[epid] = s.st;
        if (prev[epid] !== s.st) changed = true;
    }
    for (const [epid] of pairs(prev)) if (next[epid] === undefined) changed = true;
    current[pid] = next;
    if (!changed || !Telemetry.IsEnabled()) return;
    // The burst read is made only on a change: one estimate per enemy in play.
    const burst: Record<number, { spell: number; attack: number }> = {};
    let sum = 0;
    for (const [epid, st] of pairs(next)) {
        if (st === "gone") continue;
        const b = burstOn(handles[epid], bot);
        burst[epid] = b;
        sum += b.spell + b.attack;
    }
    const hp = bot.GetHealth();
    const byPid = (cbLive ? cbHits : pollHits)[pid] ?? {};
    const emit = (epid: number, st: State, was: State, why: string): void => {
        let hits = 0;
        for (const t of byPid[epid] ?? []) if (now - t <= SETTINGS.CommitWindow) hits++;
        const b = burst[epid];
        Telemetry.Event("commit", [
            ["pid", pid],
            ["epid", epid],
            ["st", st],
            ["was", was],
            ["why", why],
            ["hits", hits],
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
        if (next[epid] === undefined) emit(epid, "gone", was, handles[epid] === undefined ? "lost" : "left");
    }
}

/** Tests: forget every hit, state and the install. */
export function Reset(): void {
    for (const k in cbHits) delete cbHits[k as unknown as number];
    for (const k in pollHits) delete pollHits[k as unknown as number];
    for (const k in current) delete current[k as unknown as number];
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
