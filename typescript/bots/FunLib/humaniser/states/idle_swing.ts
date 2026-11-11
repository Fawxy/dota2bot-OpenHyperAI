/**
 * The idle swing (slice idle-swing, `docs/proposals/2026-11-06-lane-controller.md` s5.6 and s7 step 1; master slice files
 * core-in-lane and support-lane): what an owned laner hits when the shared picker (states/lane_pick `Choose`) has no last hit,
 * deny or pre-hit to offer. The picker's order stays strict: any last hit, then a deny, then a pre-hit's rank, then this. The
 * lane's mode sets its kind (user 06/11/2026: pre-deny and shove are the same question):
 * - `predeny` (mode `safe`, the default, `Ours.PreDeny`): our lane creep below half HP that no enemy hero can reach before our
 *   hits kill it, so the wave loses HP on our side and the deny comes sooner. No claim: both laners hit the same creep together
 *   (user 06/11/2026: "the two heroes in lane could work together to deny quickly"), so a creep an allied hero is already
 *   hitting comes first (the forecast counts that hero's hits in the kill time), then ranged creeps, then the lowest HP.
 * - `setup` (slice lane-control 2b, mode `safe` with the controller's `setup` lever, its intent `forward`; user 06/11/2026: the
 *   mirror of pre-deny): an enemy lane creep outside their tower that our next hit does not kill, whose kill by our hits
 *   (SetupHits at most, this swing included) comes before any enemy hero could walk into range and deny it, so the wave
 *   moves out and the last hit after it is ours. With no setup on offer, the pre-deny.
 * - `shove` (mode `shove`: the lane controller's R5, or `Overrides.ForceShove` for a harness run): an enemy lane creep
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
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

export type Kind = "predeny" | "setup" | "shove";
export type Mode = "safe" | "shove";

/** Dota lets a hero attack its own creep below half HP (the deny rule). */
export const DENY_FRACTION = 0.5;
/** Seconds of forecast for the pre-deny's kill time: four attack cycles at early attack speeds. `judgement`. */
export const HORIZON = 6;
/** Enemy heroes farther than this from the creep are not read (no threat within the horizon at lane speeds). */
const ENEMY_RADIUS = 1600;
/** Lane creeps the idle swing can reach: the bot's attack range plus the walk it allows (`LanePick.MAX_WALK` at its current speed),
 *  the same distance the per-creep `walk` test uses, capped at the old fixed 900 so the scan only ever shrinks. */
const CREEP_RADIUS_CAP = 900;
function creepRadius(bot: Unit): number {
    return math.min(CREEP_RADIUS_CAP, bot.GetAttackRange() + LanePick.MAX_WALK * math.max(100, bot.GetCurrentMovementSpeed()));
}
/** Setup: our hits to the kill, this swing and the last hit included (`judgement`: "hit a creep twice and get an easy last
 *  hit", user 06/11/2026). */
export const SETUP_HITS = 3;
/** Fallback only: a tower's reach to a target's centre (7.41: attack range 700 + bounding radius 144), read live by
 *  WorldFacts.TowerReach. The setup's clearance is that reach plus the creep's own radius (slice 4; was TOWER_CLEAR 800). */
const TOWER_REACH = 844;
/** Fallbacks only (logged once per game through WorldFacts.Fallback): attack period and an enemy's attack point. */
const PERIOD_FALLBACK = 1.7;
const ATTACK_POINT_FALLBACK = 0.4;

/** Our attack period from the API, the counted fallback when the read gives nothing. */
function periodOf(me: Lib.TaskUnit): number {
    const p = me.GetSecondsPerAttack?.();
    return p !== undefined && p > 0 ? p : WorldFacts.Fallback("attack_period", PERIOD_FALLBACK);
}

/**
 * Seconds until our hits kill a creep: our first landing at `first`, then one every `period`, each of `mean` damage, on the
 * creep's forecast HP without our hits (`hpAt`). The others' damage counts through `hpAt`. Math.huge when it outlives `horizon`;
 * RACE_LOST when the others kill it before one of our hits lands (the deny would come due while our attack is on cooldown).
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
        const left = hpAt(t) - k * mean;
        if (left <= 0) return RACE_LOST;
        k++;
        if (left - mean <= 0) return t;
    }
    return math.huge;
}

/** KillTime's value for a creep the others kill between our hits. */
export const RACE_LOST = -1;

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

type LaneControlModule = typeof import("bots/FunLib/humaniser/lane_control");
/** Required at the call: lane_control's imports (rune_job, stack_job) reach the chooser and the laning body. */
function laneControl(): LaneControlModule {
    return require("bots/FunLib/humaniser/lane_control") as LaneControlModule;
}

/** The lane's mode for this laner: `shove` where `Overrides.ForceShove` names its team and lane, else the lane controller's. */
export function ModeOf(bot: Unit): Mode {
    if (ForcedIn(Overrides.Get("ForceShove"), bot.GetTeam(), bot.GetAssignedLane())) return "shove";
    return laneControl().ModeFor(bot.GetTeam(), bot.GetAssignedLane());
}

/** Whether the lane controller asks this lane for the setup swing (its intent `forward` in mode `safe`). */
export function SetupWanted(bot: Unit): boolean {
    return laneControl().Chosen(bot.GetTeam(), bot.GetAssignedLane(), "setup") === true;
}

/** Our hits to a kill at `kill` from the first landing at `first`, one every `period` (this swing included). */
export function HitsTo(this: void, kill: number, first: number, period: number): number {
    return math.floor((kill - first) / math.max(0.01, period) + 0.5) + 1;
}

/** The decision's numbers for the swing's ev=idle_swing. */
export interface Note {
    kind: Kind;
    mode: Mode;
    creep: Lib.TaskCreep;
    hp: number;
    /** HP as a fraction of max. */
    hf: number;
    /** The creep's place at the pick. */
    x: number;
    y: number;
    /** predeny: our kill time and the nearest enemy hero's reach (math.huge: none near). */
    kill?: number;
    reach?: number;
    /** predeny: an allied hero was already hitting the creep. */
    focus?: boolean;
    /** setup: our hits to the kill, this swing included. */
    hits?: number;
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

/** Forgets the bot's note once its swing is logged. */
export function Clear(pid: number): void {
    notes[pid] = undefined;
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
        // Attack range counts from edge to edge: both bounding radii come off the centre distance (slice 4).
        const gap = GetUnitToUnitDistance(h, creep) - h.GetAttackRange() - (h.GetBoundingRadius() ?? 0) - (creep.GetBoundingRadius() ?? 0);
        const walk = math.max(0, gap) / speed;
        const point = (h as Unit & { GetAttackPoint?(): number }).GetAttackPoint?.();
        const t = walk + (point !== undefined && point >= 0 ? point : WorldFacts.Fallback("attack_point", ATTACK_POINT_FALLBACK));
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
    const period = periodOf(me);
    const partner = focused(bot);
    let best: Unit | undefined;
    let bestKey: { focus: boolean; ranged: boolean; hp: number } | undefined;
    let bestNote: Note | undefined;
    for (const c of bot.GetNearbyLaneCreeps(creepRadius(bot), false) ?? []) {
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
        // In one-hit range at our hit it is a deny, the deny pick's with its timing and claim (user 06/11/2026), not a pre-deny.
        if (verbs.forecastHp(f, first) <= mean) continue;
        const kill = KillTime((t) => verbs.forecastHp(f, t), first, period, mean, HORIZON);
        if (kill === RACE_LOST) continue;
        const reach = enemyReach(bot, c);
        if (!SafeFromEnemy(kill, reach)) continue;
        const key = { focus: partner.has(c), ranged: LanePick.IsRanged(tc), hp };
        if (Better(key, bestKey)) {
            best = c;
            bestKey = key;
            const at = c.GetLocation();
            bestNote = { kind: "predeny", mode: "safe", creep: tc, hp, hf: hp / max, x: at.x, y: at.y, kill, reach, focus: key.focus, denies: 0, lastHits: 0 };
        }
    }
    return [bestNote, best];
}

function nearEnemyTower(bot: Unit, c: Unit): boolean {
    for (const tw of bot.GetNearbyTowers(1600, true) ?? []) {
        if (usable(tw) && GetUnitToUnitDistance(tw, c) <= WorldFacts.TowerReach(tw, TOWER_REACH) + (c.GetBoundingRadius() ?? 0)) return true;
    }
    return false;
}

/** Order of setup candidates: fewer of our hits to the kill, then ranged (more gold), then lower HP. */
export function BetterSetup(
    this: void,
    a: { hits: number; ranged: boolean; hp: number },
    b: { hits: number; ranged: boolean; hp: number } | undefined,
): boolean {
    if (b === undefined) return true;
    if (a.hits !== b.hits) return a.hits < b.hits;
    if (a.ranged !== b.ranged) return a.ranged;
    return a.hp < b.hp;
}

function findSetup(bot: Unit, me: Lib.TaskUnit, verbs: typeof Lib.Verbs): [Note | undefined, Unit | undefined] {
    const period = periodOf(me);
    let best: Unit | undefined;
    let bestKey: { hits: number; ranged: boolean; hp: number } | undefined;
    let bestNote: Note | undefined;
    for (const c of bot.GetNearbyLaneCreeps(creepRadius(bot), true) ?? []) {
        if (!usable(c)) continue;
        const max = c.GetMaxHealth();
        const hp = c.GetHealth();
        if (max <= 0) continue;
        const walk = math.max(0, GetUnitToUnitDistance(bot, c) - bot.GetAttackRange()) / math.max(100, bot.GetCurrentMovementSpeed());
        if (walk > LanePick.MAX_WALK || nearEnemyTower(bot, c)) continue;
        const tc = c as unknown as Lib.TaskCreep;
        const f = verbs.hpForecast(me, tc, HORIZON);
        const first = walk + verbs.ownHitTime(me, tc);
        const mean = c.GetActualIncomingDamage(bot.GetAttackDamage(), DamageType.Physical);
        // In one-hit range at our hit it is a last hit, the last-hit pick's (as pre-deny leaves a deny to the deny pick).
        if (verbs.forecastHp(f, first) <= mean) continue;
        const kill = KillTime((t) => verbs.forecastHp(f, t), first, period, mean, HORIZON);
        if (kill === RACE_LOST || kill === math.huge) continue;
        const hits = HitsTo(kill, first, period);
        if (hits > SETUP_HITS) continue;
        const reach = enemyReach(bot, c);
        if (!SafeFromEnemy(kill, reach)) continue;
        const key = { hits, ranged: LanePick.IsRanged(tc), hp };
        if (BetterSetup(key, bestKey)) {
            best = c;
            bestKey = key;
            const at = c.GetLocation();
            bestNote = { kind: "setup", mode: "safe", creep: tc, hp, hf: hp / max, x: at.x, y: at.y, kill, reach, hits, denies: 0, lastHits: 0 };
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
    for (const c of bot.GetNearbyLaneCreeps(creepRadius(bot), true) ?? []) {
        if (!usable(c)) continue;
        if (math.max(0, GetUnitToUnitDistance(bot, c) - bot.GetAttackRange()) / speed <= LanePick.MAX_WALK) near.push(c);
    }
    const c = LaneTech.ShoveTarget(bot, near);
    if (c === undefined) return [undefined, undefined];
    const max = c.GetMaxHealth();
    const at = c.GetLocation();
    return [
        { kind: "shove", mode: "shove", creep: c as unknown as Lib.TaskCreep, hp: c.GetHealth(), hf: max > 0 ? c.GetHealth() / max : 1, x: at.x, y: at.y, denies: 0, lastHits: 0 },
        c,
    ];
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
    let [note, creep] = mode === "shove" ? findShove(bot) : SetupWanted(bot) ? findSetup(bot, me, verbs) : [undefined, undefined];
    if (note === undefined && mode !== "shove") [note, creep] = findPreDeny(bot, me, verbs);
    if (note === undefined || creep === undefined) return undefined;
    const t = target(bot, creep);
    const busy = t.walk + verbs.ownHitTime(me, t.creep) + periodOf(me);
    if (needed(me, verbs, busy, t.creep, mine)) return undefined;
    note.denies = Count(bot, "GetDenies");
    note.lastHits = Count(bot, "GetLastHits");
    notes[bot.GetPlayerID()] = note;
    return t;
}
