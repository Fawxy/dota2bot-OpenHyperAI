/**
 * Rune spawn plan (slice rune-spawn, switch Ours.RuneSpawn): the team's one decision for the 6:00 power rune. At PlanAt
 * the mid gets the power spot cheaper for it and one free support the other, so whichever spot spawns has a hero of ours
 * on it and nobody infers another hero's intent. Each hero waits at a stand point out of its spot's sight (higher ground
 * where the map has it, EC-089: the API gives height levels but no line of sight and trees only around the bot itself)
 * and walks in to arrive at the spawn. At the spawn `Race` says what the hero does: take (it gets there first), deny (it
 * can attack the spot before an enemy reaches it; EC-085: the API has no rune handle, so the deny is an attack-move onto
 * the spot), off, or cross to the other spot. Plain readings; the task body is rune_spawn's.
 */
import { Rune, Unit, Vector } from "bots/ts_libs/dota";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";

declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare function GetRuneStatus(this: void, rune: number): number;
declare function GetHeightLevel(this: void, loc: Vector): number;
declare function IsLocationPassable(this: void, loc: Vector): boolean;
declare function GetAncient(this: void, team: number): Unit;
declare const RUNE_STATUS_AVAILABLE: number;

// All judgement (slice rune-spawn, Decisions).
export const SETTINGS = {
    /** RUNE_RULES power.first: the one source of rune spawn times (slice timer-facts). */
    Spawn: Runes.RUNE_RULES.power.first,
    /** The plan is made this long before the spawn. */
    PlanAt: Runes.RUNE_RULES.power.first - 40,
    /** Stand-point rings around the spot and the angles sampled on each. */
    StandRadii: [550, 750, 950],
    StandAngles: 16,
    /** A stand no higher than the spot, or farther from our ancient than the spot, costs this much walk. */
    LowPenalty: 1500,
    FarSidePenalty: 1000,
    /** Seconds a hero means to stand hidden before it walks in (it leaves lane for the stand this much earlier). */
    Hide: 5,
    /** Seconds early it means to reach the spot. */
    Early: 0.3,
    /** Take when our arrival beats every enemy hero's by this many seconds. */
    TakeMargin: 0.3,
    /** Seconds from reaching attack range to the hit landing (an attack point and a reaction). */
    DenySwing: 0.5,
    /** Enemy heroes this far from a spot count in its race. */
    RaceRadius: 3000,
    /** The mid's side of the plan holds it from its leave until this long after the spawn. */
    OwnAfter: 15,
};

export type Act = "take" | "deny" | "off" | "cross" | "none";

export interface Plan {
    at: number;
    midSpot?: number;
    mid?: Unit;
    supSpot?: number;
    sup?: Unit;
    why?: string;
    /** Supports whose start gate dropped them from the plan; `sup` is a replacement when it is set after a drop. */
    dropped?: Unit[];
}

const plans: Record<number, Plan | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(plans)) plans[k as number] = undefined;
}

export function On(): boolean {
    return Ours.On("RuneSpawn") && Ours.On("JobChooser") && Ours.On("RuneRotation");
}

export function Spots(): number[] {
    return [Rune.Power1, Rune.Power2];
}

export function SpotAt(rune: number): Vector {
    return GetRuneSpawnLocation(rune);
}

export function Other(rune: number): number {
    return rune === Rune.Power1 ? Rune.Power2 : Rune.Power1;
}

function teamHero(pos: number): Unit | undefined {
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m !== undefined && m !== null && m.IsBot() && LaneConfig.PositionOf(m) === pos) return m;
    }
    return undefined;
}

function nearer(u: Unit, a: number, b: number): number {
    return GetUnitToLocationDistance(u, SpotAt(a)) <= GetUnitToLocationDistance(u, SpotAt(b)) ? a : b;
}

/**
 * The free support (alive, not `busy`, not in `skip`) with the shorter walk to `spot` (to its nearer spot with none).
 * A support whose nearest spot is not `spot` never qualifies: it would cross a lane to the far rune (user 06/11/2026).
 */
function freeSupport(spot: number | undefined, busy: (this: void, u: Unit) => boolean, skip: Unit[]): Unit | undefined {
    const [a, b] = Spots();
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const pos of [4, 5]) {
        const s = teamHero(pos);
        if (!FR.Alive(s) || busy(s) || skip.includes(s!)) continue;
        if (spot !== undefined && nearer(s, a, b) !== spot) continue;
        const d = GetUnitToLocationDistance(s, SpotAt(spot ?? nearer(s, a, b)));
        if (d < bestD) [best, bestD] = [s, d];
    }
    return best;
}

/**
 * The spot plan from plain choices: `mid` takes the spot nearer it; the other spot goes to the free support with the
 * shorter walk to it among those it is nearest to (pos4 on a tie; a support nearer the mid's spot stays home rather than cross).
 * `busy(u)` says a support is not free (a stack that minute). Exported for tests.
 */
export function Make(now: number, busy: (this: void, u: Unit) => boolean): Plan {
    const [a, b] = Spots();
    const mid = teamHero(2);
    const plan: Plan = { at: now };
    if (FR.Alive(mid)) {
        plan.mid = mid;
        plan.midSpot = nearer(mid, a, b);
    }
    const supSpot = plan.midSpot !== undefined ? Other(plan.midSpot) : undefined;
    const best = freeSupport(supSpot, busy, []);
    if (best !== undefined) {
        plan.sup = best;
        plan.supSpot = supSpot ?? nearer(best, a, b);
    } else plan.why = freeSupport(undefined, busy, []) !== undefined ? "no-near-support" : "no-free-support";
    if (plan.mid === undefined) plan.why = plan.why ?? "no-mid";
    return plan;
}

/** This team's plan for the 6:00 spawn, made once at PlanAt (undefined before, or with the switch off). */
export function For(team: number, busy: (this: void, u: Unit) => boolean, now: number = DotaTime()): Plan | undefined {
    if (!On() || now < SETTINGS.PlanAt || now > SETTINGS.Spawn + 60) return undefined;
    let p = plans[team];
    if (p === undefined) {
        p = Make(now, busy);
        plans[team] = p;
        logPlan(team, p);
    }
    return p;
}

function logPlan(team: number, p: Plan): void {
    Telemetry.Event("rune_plan", [
        ["team", team],
        ["mid", p.mid?.GetPlayerID()],
        ["ms", p.midSpot],
        ["sup", p.sup?.GetPlayerID()],
        ["ss", p.supSpot],
        ["why", p.why],
    ]);
}

/**
 * The planned support `bot` will not go (its start gate skipped it, `why`): its spot goes to another free support, once per
 * support, and the plan logs again (rspchk2: 3 of 10 plans uncovered with the other support free). Returns the replacement.
 */
export function Drop(bot: Unit, why: string, busy: (this: void, u: Unit) => boolean): Unit | undefined {
    const p = plans[bot.GetTeam()];
    if (p === undefined || p.sup !== bot) return undefined;
    p.dropped = [...(p.dropped ?? []), bot];
    p.sup = freeSupport(p.supSpot, busy, p.dropped);
    p.why = `${p.sup !== undefined ? "swap" : "drop"}:${why}`;
    logPlan(bot.GetTeam(), p);
    return p.sup;
}

/** True when `bot` holds its spot as a replacement for a dropped support. */
export function Replaces(bot: Unit): boolean {
    const p = plans[bot.GetTeam()];
    return p !== undefined && p.sup === bot && p.dropped !== undefined;
}

/** The spot this hero holds in its team's plan, if any. */
export function SpotOf(bot: Unit, busy: (this: void, u: Unit) => boolean, now: number = DotaTime()): number | undefined {
    const p = For(bot.GetTeam(), busy, now);
    if (p === undefined) return undefined;
    if (p.mid === bot) return p.midSpot;
    if (p.sup === bot) return p.supSpot;
    return undefined;
}

/** The planned hero at `spot` other than `bot`, if any. */
export function HolderOf(team: number, spot: number): Unit | undefined {
    const p = plans[team];
    if (p === undefined) return undefined;
    return p.midSpot === spot ? p.mid : p.supSpot === spot ? p.sup : undefined;
}

export interface Stand {
    at: Vector;
    height: number;
    spotHeight: number;
}

/**
 * A stand point near `spot` for `bot`: passable points on rings around it, cheapest by the walk there and on to the spot,
 * with a penalty for one no higher than the spot or on the far side of the river. Falls back to the spot itself.
 */
export function StandFor(bot: Unit, spot: Vector): Stand {
    const s = SETTINGS;
    const spotHeight = GetHeightLevel(spot);
    const home = GetAncient(bot.GetTeam()).GetLocation();
    const spotHome = FR.Dist(spot, home);
    let best: Stand = { at: spot, height: spotHeight, spotHeight };
    let bestCost = math.huge;
    for (const r of s.StandRadii) {
        for (let k = 0; k < s.StandAngles; k++) {
            const a = (2 * math.pi * k) / s.StandAngles;
            const c = Vector(spot.x + r * math.cos(a), spot.y + r * math.sin(a), spot.z);
            if (!IsLocationPassable(c)) continue;
            const h = GetHeightLevel(c);
            const cost =
                GetUnitToLocationDistance(bot, c) +
                FR.Dist(c, spot) +
                (h > spotHeight ? 0 : s.LowPenalty) +
                (FR.Dist(c, home) > spotHome ? s.FarSidePenalty : 0);
            if (cost < bestCost) [best, bestCost] = [{ at: c, height: h, spotHeight }, cost];
        }
    }
    return best;
}

function speedOf(u: Unit): number {
    return math.max(1, u.GetCurrentMovementSpeed());
}

/** Seconds for `u` to walk to `at` in a straight line at its current speed. */
export function WalkSecs(u: Unit, at: Vector): number {
    return GetUnitToLocationDistance(u, at) / speedOf(u);
}

/** The soonest any living enemy hero within RaceRadius could reach `at`, in seconds (math.huge with none). */
export function EnemyArrival(at: Vector): number {
    let best = math.huge;
    for (const e of FR.EnemiesNear(at, SETTINGS.RaceRadius)) best = math.min(best, FR.Dist(e.GetLocation(), at) / speedOf(e));
    return best;
}

export interface RaceInputs {
    /** Our seconds to reach the spot, and to reach attack range of it plus the swing. */
    ours: number;
    oursDeny: number;
    theirs: number;
}

/** At a spot holding the rune: take if we get there first by TakeMargin, deny if our hit lands before they arrive, else off. */
export function RaceAt(i: RaceInputs): Act {
    if (i.ours + SETTINGS.TakeMargin <= i.theirs) return "take";
    if (i.oursDeny < i.theirs) return "deny";
    return "off";
}

export function RaceInputsOf(bot: Unit, spot: Vector): RaceInputs {
    const d = GetUnitToLocationDistance(bot, spot);
    return {
        ours: d / speedOf(bot),
        oursDeny: math.max(0, d - bot.GetAttackRange()) / speedOf(bot) + SETTINGS.DenySwing,
        theirs: EnemyArrival(spot),
    };
}

/**
 * What `bot`, planned at `mine`, does at the spawn. The rune at its spot: the race. The rune at the other spot: cross when
 * it would get there before every enemy hero and the other spot's planned hero would not (dead, or slower); else none.
 * Neither spot shows the rune yet: none (the caller waits a moment and asks again).
 */
export function Race(bot: Unit, mine: number): [Act, RaceInputs | undefined] {
    if (GetRuneStatus(mine) === RUNE_STATUS_AVAILABLE) {
        const i = RaceInputsOf(bot, SpotAt(mine));
        return [RaceAt(i), i];
    }
    const other = Other(mine);
    if (GetRuneStatus(other) !== RUNE_STATUS_AVAILABLE) return ["none", undefined];
    const at = SpotAt(other);
    const i = RaceInputsOf(bot, at);
    const holder = HolderOf(bot.GetTeam(), other);
    const holderSecs = FR.Alive(holder) && holder !== bot ? WalkSecs(holder, at) : math.huge;
    return [i.ours + SETTINGS.TakeMargin <= i.theirs && i.ours < holderSecs ? "cross" : "none", i];
}

/** After a deny try: the rune left `rune`'s spot with an enemy hero within 200 of it (taken) or not (gone); undefined while it is there. */
export function DenyResult(rune: number): "gone" | "taken" | undefined {
    if (GetRuneStatus(rune) === RUNE_STATUS_AVAILABLE) return undefined;
    return FR.EnemiesNear(SpotAt(rune), 200).length > 0 ? "taken" : "gone";
}

/** When `bot` should leave for its stand: so it stands Hide seconds before walking in to arrive Early before the spawn. */
export function LeaveAt(bot: Unit, stand: Vector, spot: Vector): number {
    const walkIn = FR.Dist(stand, spot) / speedOf(bot);
    return SETTINGS.Spawn - SETTINGS.Early - walkIn - SETTINGS.Hide - WalkSecs(bot, stand) * 1.2;
}

/** The mid's side of the plan holds it now: from its leave time until OwnAfter after the spawn. */
export function OwnsMid(bot: Unit, now: number = DotaTime()): boolean {
    if (!On() || now < SETTINGS.PlanAt || now > SETTINGS.Spawn + SETTINGS.OwnAfter) return false;
    const p = plans[bot.GetTeam()];
    return p !== undefined && p.mid === bot;
}
