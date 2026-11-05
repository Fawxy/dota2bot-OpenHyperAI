/**
 * The idle swing (slice idle-swing, `docs/proposals/2026-11-06-lane-controller.md` s5.6 and s7 step 1; master slice files
 * core-in-lane and support-lane): what an owned laner hits when the shared picker (states/lane_pick `Choose`) has no last hit,
 * deny or pre-hit to offer. The picker's order stays strict: any last hit, then a deny, then a pre-hit's rank, then this. The
 * lane's mode sets its kind (user 06/11/2026: pre-deny and shove are the same question):
 * - `predeny` (mode `safe`, the default, `Ours.PreDeny`): our lane creep below half HP that no enemy hero can reach before our
 *   hits kill it, so the wave loses HP on our side and the deny comes sooner. No claim: both laners hit the same creep together
 *   (user 06/11/2026: "the two heroes in lane could work together to deny quickly"), so a creep an allied hero is already
 *   hitting comes first (the forecast counts that hero's hits in the kill time), then ranged creeps, then the lowest HP.
 * - `shove` (mode `shove`; until the lane controller sets it, only `Overrides.ForceShove` for a harness run): an enemy lane creep
 *   outside their tower (`LaneTech.ShoveTarget`, the lowest HP), so their wave dies sooner and ours walks on.
 * A swing never spends the attack a last hit or deny needs: none may come due before our attack is ready again (the pre-hit's
 * rule, user 04/11/2026). The swing is laneFarm's caller-built `prehit` kind (one `attackAndConfirm`), told apart from a tower
 * pre-hit by `Of`. Telemetry: one `ev=idle_swing` per swing; a later deny of a pre-denied creep says `pre=<swings>` on its ev=lh.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { DamageType, Lane, Team, Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Overrides from "bots/FunLib/humaniser/overrides";
import * as LanePick from "bots/FunLib/humaniser/states/lane_pick";

export type Kind = "predeny" | "shove";
export type Mode = "safe" | "shove";

/** Dota lets a hero attack its own creep below half HP (the deny rule). */
export const DENY_FRACTION = 0.5;
/** Seconds of forecast for the pre-deny's kill time: four attack cycles at early attack speeds. `judgement`. */
export const HORIZON = 6;
/** Enemy heroes farther than this from the creep are not read (no threat within the horizon at lane speeds). */
const ENEMY_RADIUS = 1600;
/** Own lane creeps within this of the bot are pre-deny candidates (attack range plus a MAX_WALK walk is the real bound). */
const CREEP_RADIUS = 900;

/**
 * Seconds until our hits kill a creep: our first landing at `first`, then one every `period`, each of `mean` damage, on the
 * creep's forecast HP without our hits (`hpAt`). The others' damage counts through `hpAt`. Math.huge when it outlives `horizon`.
 */
export function KillTime(
    this: void,
    hpAt: (this: void, t: number) => number,
    first: number,
    period: number,
    mean: number,
    horizon: number,
): number {
    if (mean <= 0 || period <= 0) return math.huge;
    let k = 0;
    for (let t = first; t <= horizon; t += period) {
        k++;
        if (hpAt(t) - k * mean <= 0) return t;
    }
    return math.huge;
}

/**
 * Whether a pre-deny on our creep is safe from an enemy last hit: every enemy hero's time to reach attack range of it and swing
 * (`reach`, seconds) is longer than our kill time. No enemy hero near: always.
 */
export function SafeFromEnemy(this: void, kill: number, reach: number): boolean {
    return reach === math.huge || reach > kill;
}

/** `ForceShove` tokens: `bot`, `r:bot`, `d:top`, `all`, comma-separated (r Radiant, d Dire, no prefix both teams). */
export function ForcedIn(this: void, spec: unknown, team: number, lane: number): boolean {
    if (typeof spec !== "string" || spec === "") return false;
    const names: Record<string, number> = { top: Lane.Top, mid: Lane.Mid, bot: Lane.Bot };
    for (const [raw] of string.gmatch(spec, "[^,]+")) {
        const tok = string.lower(raw).trim();
        let side: number | undefined;
        let name = tok;
        const [p, rest] = string.match(tok, "^([rd]):(.+)$");
        if (p !== undefined) {
            side = p === "r" ? Team.Radiant : Team.Dire;
            name = rest!;
        }
        if (side !== undefined && side !== team) continue;
        if (name === "all" || names[name] === lane) return true;
    }
    return false;
}

/** The lane's mode for this laner: `shove` only where `Overrides.ForceShove` names its team and lane (slice 1 has no controller). */
export function ModeOf(bot: Unit): Mode {
    return ForcedIn(Overrides.Get("ForceShove"), bot.GetTeam(), bot.GetAssignedLane()) ? "shove" : "safe";
}

/** The decision's numbers for the swing's ev=idle_swing. */
export interface Note {
    kind: Kind;
    mode: Mode;
    creep: Lib.TaskCreep;
    hp: number;
    /** HP as a fraction of max. */
    hf: number;
    /** predeny: our kill time and the nearest enemy hero's reach (math.huge: none near). */
    kill?: number;
    reach?: number;
    /** predeny: an allied hero was already hitting the creep. */
    focus?: boolean;
    /** The bot's deny and last-hit counts at the pick, so the swing's ev says whether it took the creep itself. */
    denies: number;
    lastHits: number;
}
const notes: Record<number, Note | undefined> = {};

/** The note of this bot's last idle swing, if it was on `creep`: a `prehit` target with no note is a tower pre-hit. */
export function Of(pid: number, creep: Lib.TaskCreep): Note | undefined {
    const n = notes[pid];
    return n !== undefined && n.creep === creep ? n : undefined;
}

/** Pre-denied creeps per bot, newest last, with the swings spent on each, for the later deny's `pre`. */
const spent: Record<number, { creep: Lib.TaskCreep; n: number }[] | undefined> = {};
const SPENT_KEPT = 6;

export function NoteSwing(pid: number, creep: Lib.TaskCreep): void {
    let list = spent[pid];
    if (list === undefined) {
        list = [];
        spent[pid] = list;
    }
    for (const e of list) {
        if (e.creep === creep) {
            e.n++;
            return;
        }
    }
    list.push({ creep, n: 1 });
    if (list.length > SPENT_KEPT) list.shift();
}

/** Pre-deny swings this bot spent on `creep` (undefined: none). */
export function SpentOn(pid: number, creep: Lib.TaskCreep): number | undefined {
    for (const e of spent[pid] ?? []) if (e.creep === creep) return e.n;
    return undefined;
}

/** The bot's deny or last-hit count (GetDenies is missing from the API typings; 0 where a host lacks it). */
export function Count(bot: Unit, name: "GetLastHits" | "GetDenies"): number {
    const f = (bot as any)[name];
    return f !== undefined ? (f(bot) as number) : 0;
}

function usable(u: Unit | undefined | null): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive();
}

/** Seconds the nearest enemy hero needs to walk into attack range of `creep` and land a swing (math.huge: none near). */
function enemyReach(bot: Unit, creep: Unit): number {
    let best = math.huge;
    for (const h of bot.GetNearbyHeroes(ENEMY_RADIUS, true, 0) ?? []) {
        if (!usable(h)) continue;
        const speed = math.max(100, h.GetCurrentMovementSpeed());
        const walk = math.max(0, GetUnitToUnitDistance(h, creep) - h.GetAttackRange()) / speed;
        const t = walk + ((h as any).GetAttackPoint?.(h) ?? 0.4);
        if (t < best) best = t;
    }
    return best;
}

/** Our attack is busy until `busy`: a last hit or deny `mine` takes (other than on `creep`) due before then would be lost to it. */
function needed(
    me: Lib.TaskUnit,
    verbs: typeof Lib.Verbs,
    busy: number,
    creep: Lib.TaskCreep | undefined,
    mine: ((this: void, t: Lib.Verbs.LaneTarget) => boolean) | undefined,
): boolean {
    for (const o of verbs.laneTargets(me, { within: busy })) {
        if (o.creep === creep || (mine !== undefined && !mine(o))) continue;
        if (LanePick.Reachable(o) && o.eta <= busy) return true;
    }
    return false;
}

function target(bot: Unit, creep: Unit): Lib.Verbs.LaneTarget {
    const walk = math.max(0, GetUnitToUnitDistance(bot, creep) - bot.GetAttackRange()) / math.max(100, bot.GetCurrentMovementSpeed());
    const c = creep as unknown as Lib.TaskCreep;
    return { creep: c, kind: "prehit", eta: walk, due: 0, walk, dies: math.huge, ranged: LanePick.IsRanged(c) };
}

/** Allied heroes within this of the bot are read for the creep they are hitting (a partner's pre-deny or deny). */
const ALLY_RADIUS = 1200;

/** Creeps an allied hero other than `bot` is attacking now. */
function focused(bot: Unit): LuaSet<Unit> {
    const out = new LuaSet<Unit>();
    for (const h of bot.GetNearbyHeroes(ALLY_RADIUS, false, 0) ?? []) {
        if (!usable(h) || h === bot) continue;
        const t = h.GetAttackTarget();
        if (t !== undefined && t !== null) out.add(t);
    }
    return out;
}

/** Order of pre-deny candidates: a creep a partner hits, then ranged, then lower HP. */
export function Better(
    this: void,
    a: { focus: boolean; ranged: boolean; hp: number },
    b: { focus: boolean; ranged: boolean; hp: number } | undefined,
): boolean {
    if (b === undefined) return true;
    if (a.focus !== b.focus) return a.focus;
    if (a.ranged !== b.ranged) return a.ranged;
    return a.hp < b.hp;
}

function findPreDeny(bot: Unit, me: Lib.TaskUnit, verbs: typeof Lib.Verbs): [Note | undefined, Unit | undefined] {
    const period = me.GetSecondsPerAttack?.() ?? 1.7;
    const partner = focused(bot);
    let best: Unit | undefined;
    let bestKey: { focus: boolean; ranged: boolean; hp: number } | undefined;
    let bestNote: Note | undefined;
    for (const c of bot.GetNearbyLaneCreeps(CREEP_RADIUS, false) ?? []) {
        if (!usable(c) || c.GetTeam() !== bot.GetTeam()) continue;
        const max = c.GetMaxHealth();
        const hp = c.GetHealth();
        if (max <= 0 || hp >= max * DENY_FRACTION) continue;
        const walk = math.max(0, GetUnitToUnitDistance(bot, c) - bot.GetAttackRange()) / math.max(100, bot.GetCurrentMovementSpeed());
        if (walk > LanePick.MAX_WALK) continue;
        const tc = c as unknown as Lib.TaskCreep;
        const f = verbs.hpForecast(me, tc, HORIZON);
        const first = walk + verbs.ownHitTime(me, tc);
        const mean = c.GetActualIncomingDamage(bot.GetAttackDamage(), DamageType.Physical);
        const kill = KillTime((t) => verbs.forecastHp(f, t), first, period, mean, HORIZON);
        const reach = enemyReach(bot, c);
        if (!SafeFromEnemy(kill, reach)) continue;
        const key = { focus: partner.has(c), ranged: LanePick.IsRanged(tc), hp };
        if (Better(key, bestKey)) {
            best = c;
            bestKey = key;
            bestNote = { kind: "predeny", mode: "safe", creep: tc, hp, hf: hp / max, kill, reach, focus: key.focus, denies: 0, lastHits: 0 };
        }
    }
    return [bestNote, best];
}

type LaneTechModule = typeof import("bots/FunLib/humaniser/lane_tech");

function findShove(bot: Unit): [Note | undefined, Unit | undefined] {
    // Required at the call, not imported: lane_tech's imports reach states/laning, which imports this module.
    const LaneTech = require("bots/FunLib/humaniser/lane_tech") as LaneTechModule;
    const near: Unit[] = [];
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    for (const c of bot.GetNearbyLaneCreeps(CREEP_RADIUS, true) ?? []) {
        if (!usable(c)) continue;
        if (math.max(0, GetUnitToUnitDistance(bot, c) - bot.GetAttackRange()) / speed <= LanePick.MAX_WALK) near.push(c);
    }
    const c = LaneTech.ShoveTarget(bot, near);
    if (c === undefined) return [undefined, undefined];
    const max = c.GetMaxHealth();
    return [{ kind: "shove", mode: "shove", creep: c as unknown as Lib.TaskCreep, hp: c.GetHealth(), hf: max > 0 ? c.GetHealth() / max : 1, denies: 0, lastHits: 0 }, c];
}

/** The idle swing's switch: pre-deny under `Ours.PreDeny`; a forced shove needs no switch of its own (a harness knob). */
export function Applies(mode: Mode): boolean {
    return mode === "shove" || Ours.On("PreDeny");
}

/**
 * The idle swing this laner would make now, as a `prehit` LaneTarget, or undefined. `mine` is the picker's claims filter (a
 * support's last hits are only its claimed ones), so a core's last hit does not stop the support's swing.
 */
export function Find(
    bot: Unit,
    verbs: typeof Lib.Verbs,
    mine?: (this: void, t: Lib.Verbs.LaneTarget) => boolean,
): Lib.Verbs.LaneTarget | undefined {
    const mode = ModeOf(bot);
    if (!Applies(mode)) return undefined;
    const me = bot as unknown as Lib.TaskUnit;
    const [note, creep] = mode === "shove" ? findShove(bot) : findPreDeny(bot, me, verbs);
    if (note === undefined || creep === undefined) return undefined;
    const t = target(bot, creep);
    const busy = t.walk + verbs.ownHitTime(me, t.creep) + (me.GetSecondsPerAttack?.() ?? 1.7);
    if (needed(me, verbs, busy, t.creep, mine)) return undefined;
    note.denies = Count(bot, "GetDenies");
    note.lastHits = Count(bot, "GetLastHits");
    notes[bot.GetPlayerID()] = note;
    return t;
}
