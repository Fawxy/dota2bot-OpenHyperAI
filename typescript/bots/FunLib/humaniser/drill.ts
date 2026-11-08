/**
 * Drills (master `docs/proposals/2026-11-08-drills.md`, CLAUDE.md rule 8): `Customize.Overrides.Drill = "<name>"` picks an
 * entry of TABLE below. Only the entry's cast plays; every other hero is benched (walks to its fountain and waits), a statue
 * (stands behind its own creeps in its lane and never attacks, casts or uses items) or lane-only (holds its spot, last-hits
 * and denies), as the entry says. Reps run on a fixed clock; each rep logs `ev=drill ph=rep` once per team with a cast, and
 * a context forced by the drill reads its rep times from `RepTimes`. Each hero logs `ev=drill ph=role` when its role is
 * first known or changes. dotactl `--drill <name>` sets the override and the reset steps (its recipes.json `drills` block).
 *
 * Drills are behaviour knowledge (who acts, what is forced), so the table lives here, not in dotactl. A drill is a test
 * harness, never a behaviour: no drill is on unless the override names it. Absorbs the old `Overrides.Solo`
 * (bench), `LaneOnly` and `StackEvery` knobs.
 */
import { BotMode, GameState, Lane, Team, Unit } from "bots/ts_libs/dota";
import Customize = require("bots/FunLib/custom_loader");
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/** What a hero does in a drill. `play`: everything, as in a normal game. */
export type Role = "cast" | "bench" | "statue" | "sentry" | "laneonly" | "play";

/** Positions (1-5) per team: `r` Radiant, `d` Dire. */
export interface Sides {
    r?: number[];
    d?: number[];
}

export interface Entry {
    /** One line for the slice file and the role line. */
    note: string;
    /** The heroes under test. */
    cast: Sides;
    /** Heroes that stand as statues; checked after `cast`. */
    statue?: Sides;
    /** Heroes that stand as statues but attack an enemy hero inside their zone (Hold); checked after `statue`. */
    sentry?: Sides;
    /** Heroes that play lane-only (as `castLaneOnly`); checked after `statue`. */
    laneOnly?: Sides;
    /** Lane-only heroes also run the wave hold (states/wave_hold, under its switches) and the hold's own draw; no other lane
     *  aggro draw starts. Its control arm is the same drill with `Ours.CoreHold` off. */
    laneHold?: boolean;
    /** Lane-only cores also run lane aggro's draws (the feed under the lane controller's word, drag, tower), as a
     *  lane-only core otherwise does not. */
    laneAggro?: boolean;
    /** Everyone not in `cast` or `statue`. */
    others: "bench" | "statue" | "laneonly" | "play";
    /** The cast plays lane-only (hold its spot, last-hit, deny; no techniques, harass, trades, spells or items). */
    castLaneOnly?: boolean;
    /** `statue`: the cast stands as a statue whenever its forced job (`forces`) does not run, so nothing but that job touches
     *  the lane (a pull drill's puller between pulls). Only the forced job is asked (`ForcedJob`). */
    castIdle?: "statue";
    /** The rep clock (DotaTime seconds): a rep every `every` from `from`; with `control` n, every nth rep withholds the
     *  input (`input=off`, the control in the same game). */
    rep: { every: number; from: number; control?: number };
    /** The context the drill forces each rep (`RepTimes(context)`); absent when reps are natural (each lane wave). */
    forces?: string;
    /** Overrides keys the drill implies (`Overrides.Get` falls back to them; an explicit `--set` wins). */
    overrides?: Record<string, unknown>;
}

const SAFE_CORE: Sides = { r: [1] };
const ALL: Sides = { r: [1, 2, 3, 4, 5], d: [1, 2, 3, 4, 5] };

/**
 * The drill table. Names match dotactl's recipes.json `drills`. A slice whose drill has no entry adds it here (and a
 * recipe when it needs reset steps or a later `--until`).
 */
export const TABLE: Record<string, Entry> = {
    // Lane positioning's drill, step 1: the Radiant safe-lane core alone in its lane with natural waves (one rep each).
    "lane-spot": { note: "Radiant pos1 lane-only, everyone else benched", cast: SAFE_CORE, others: "bench", castLaneOnly: true, rep: { every: 30, from: 0 } },
    // Step 2: the Dire offlaner (the same lane) stands in range as a statue.
    "lane-spot-statue": {
        note: "Radiant pos1 lane-only, Dire pos3 a statue in its lane, everyone else benched",
        cast: SAFE_CORE,
        statue: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        rep: { every: 30, from: 0 },
    },
    // Step 3: the enemy laner active, both lane-only.
    "lane-spot-duel": { note: "Radiant pos1 and Dire pos3 lane-only, everyone else benched", cast: { r: [1], d: [3] }, others: "bench", castLaneOnly: true, rep: { every: 30, from: 0 } },
    // The contest walk-in's price: the Dire pos3 stands as a statue but hits back, so `cc` (the priced HP-%) is graded
    // against `dh` (the HP-% lost) on an opponent that acts.
    "lane-spot-sentry": {
        note: "Radiant pos1 lane-only, Dire pos3 a sentry in its lane (a statue that attacks an enemy hero inside its zone), everyone else benched",
        cast: SAFE_CORE,
        sentry: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        rep: { every: 30, from: 0 },
    },
    // The old Overrides.LaneOnly harness (slice lane-last-hits): every hero lane-only.
    "lane-only": { note: "every hero lane-only (the last-hit harness)", cast: ALL, others: "play", castLaneOnly: true, rep: { every: 30, from: 0 } },
    // The old Overrides.Solo + StackEvery = 3 harness (slice 4, double-stack): the Radiant pos5 alone stacks every third
    // minute from 2:00, with no 25 s away skip (StackFar). dotactl kills the neutrals at :05 of the two minutes between, so
    // each attempt meets a fresh camp: a kill in the attempt's own minute empties the camp it needs at :53 (drill2,
    // 08/11/2026: every-minute reps with a kill each :05 failed 7 of 7 `no-camp`).
    stack: { note: "Radiant pos5 alone, a stack attempt every third minute from 2:00", cast: { r: [5] }, others: "bench", rep: { every: 180, from: 120 }, forces: "stack", overrides: { StackFar: true } },
    // The sweep (KR S.2a tier 1, Overrides.Sweep; was Sweep + StackEvery): the Radiant pos5 alone takes each own-side camp
    // once, nearest untried first, an attempt every minute from 2:00; each attempt is on a fresh camp, so no reset.
    "stack-sweep": {
        note: "Radiant pos5 alone, an attempt every minute from 2:00 on the nearest own-side camp not tried yet",
        cast: { r: [5] },
        others: "bench",
        rep: { every: 60, from: 120 },
        forces: "stack",
        overrides: { StackFar: true, Sweep: true },
    },
    // Lane controller drills (slice file lane-controller.md "Drills"). Prediction step 0: nobody acts, every lane's waves meet
    // untouched; the controller still decides and checks each team-lane wave (rule R1, levers `nobody`), so `@lane_ctl` scores
    // its plain forecast against the untouched world. No cast, so no rep line: the waves are the reps.
    "lane-still": { note: "every hero benched; the controller's forecast against untouched waves", cast: {}, others: "bench", rep: { every: 30, from: 0 } },
    // Pull execution and effect: the Radiant pos5 pulls the wave of each input-on rep (the minute's wave) and is a statue
    // otherwise; the :30 waves are the control. Only the pull job runs for it; the controller's word is not asked.
    pull: {
        note: "Radiant pos5 pulls each minute's wave, a statue otherwise; the :30 wave unpulled (control); everyone else benched",
        cast: { r: [5] },
        others: "bench",
        castIdle: "statue",
        rep: { every: 30, from: 60, control: 2 },
        forces: "pull",
    },
    // Slice 4a's pull: the Radiant offlane pos3 pulls its hard camp on the same reps.
    "core-pull": {
        note: "Radiant pos3 pulls its hard camp each minute's wave, a statue otherwise; the :30 wave unpulled; everyone else benched",
        cast: { r: [3] },
        others: "bench",
        castIdle: "statue",
        rep: { every: 30, from: 60, control: 2 },
        forces: "pull",
    },
    // The statue steps (lane controller "Drills" steps): the same drills with the Dire laners that face the cast standing in
    // their lane as statues (never attack, cast or use items), so the lane has an enemy that is there but does not act.
    // Radiant pos5 pulls in the Radiant safe lane, which Dire's offlane pos3 and pos4 hold.
    "pull-statue": {
        note: "Radiant pos5 pulls each minute's wave, a statue otherwise; Dire pos3 and pos4 statues in the lane; the :30 wave unpulled",
        cast: { r: [5] },
        statue: { d: [3, 4] },
        others: "bench",
        castIdle: "statue",
        rep: { every: 30, from: 60, control: 2 },
        forces: "pull",
    },
    "shove-statue": {
        note: "Radiant pos1 lane-only in a forced shove (ForceShove r:bot), Dire pos3 a statue in the lane, everyone else benched",
        cast: SAFE_CORE,
        statue: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceShove: "r:bot" },
    },
    // The forced shove (slice 1's harness, slice 4b's crash target): the Radiant safe-lane core alone, lane-only, in mode
    // `shove`; each wave a rep.
    // The wave hold (slice core-in-lane), user 08/11/2026: does the core keep their wave out of our T1's fire once ours is gone?
    // The pull drill's pos5 takes each minute's wave away from the Radiant safe lane, so theirs walks in on the Radiant pos1,
    // lane-only with the hold; the :30 wave unpulled is the control in the game, and the same drill with Ours.CoreHold off
    // (`--set Ours.CoreHold=false`) is the arm where their creeps go under our tower.
    hold: {
        note: "Radiant pos5 pulls each minute's wave, a statue otherwise; Radiant pos1 lane-only with the wave hold; the :30 wave unpulled; everyone else benched",
        cast: { r: [5] },
        laneOnly: { r: [1] },
        laneHold: true,
        others: "bench",
        castIdle: "statue",
        rep: { every: 30, from: 60, control: 2 },
        forces: "pull",
    },
    shove: {
        note: "Radiant pos1 lane-only in a forced shove (ForceShove r:bot), everyone else benched",
        cast: SAFE_CORE,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceShove: "r:bot" },
    },
    // Lever-size drills: each input arm forces one lever on the Radiant safe lane every wave; its control arm is the same
    // game with no lever, read in pairs wave by wave (same seed, hlog @lever_pair).
    "lever-setup": {
        note: "Radiant pos1 lane-only, the setup forced every wave (ForceLever r:bot=setup), everyone else benched",
        cast: SAFE_CORE,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceLever: "r:bot=setup" },
    },
    "lever-none": {
        note: "Radiant pos1 lane-only, no lever every wave (ForceLever r:bot=none; lever-setup's control), everyone else benched",
        cast: SAFE_CORE,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceLever: "r:bot=none" },
    },
    // Slice lh-draw: the last-hit drag against a ranged enemy hero standing by its creeps (a melee statue leaves a safe spot to
    // hit from almost always: lhd2, 80 of 84 looks). Lineup A (seed 30): Pudge (melee) top against Lich, Sniper (ranged) mid
    // against Zeus. The feed refused (ForceLever none), so the drag is the draw under test.
    "drag-melee": {
        note: "Radiant pos3 lane-only with lane aggro, the feed refused (ForceLever r:top=none), Dire pos5 a statue in its lane (top), everyone else benched",
        cast: { r: [3] },
        statue: { d: [5] },
        others: "bench",
        castLaneOnly: true,
        laneAggro: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceLever: "r:top=none" },
    },
    "drag-ranged": {
        note: "Radiant pos2 lane-only with lane aggro, the feed refused (ForceLever r:mid=none), Dire pos2 a statue in mid, everyone else benched",
        cast: { r: [2] },
        statue: { d: [2] },
        others: "bench",
        castLaneOnly: true,
        laneAggro: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceLever: "r:mid=none" },
    },
    "lever-feed": {
        note: "Radiant pos1 lane-only with lane aggro, the feed forced every wave (ForceLever r:bot=feed), Dire pos3 a statue in the lane (the feed orders an attack on a visible enemy hero), everyone else benched",
        cast: SAFE_CORE,
        statue: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        laneAggro: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceLever: "r:bot=feed" },
    },
    "lever-feed-off": {
        note: "Radiant pos1 lane-only with lane aggro, no lever every wave (ForceLever r:bot=none; lever-feed's control), Dire pos3 a statue in the lane, everyone else benched",
        cast: SAFE_CORE,
        statue: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        laneAggro: true,
        rep: { every: 30, from: 0 },
        overrides: { ForceLever: "r:bot=none" },
    },
};

function overrides(): Record<string, unknown> | undefined {
    return (Customize as any).Overrides;
}

/** The active drill's name, or undefined (no drill, or a name the table does not hold). */
export function Name(): string | undefined {
    const n = overrides()?.["Drill"];
    return typeof n === "string" && TABLE[n] !== undefined ? n : undefined;
}

/** The active drill's entry, or undefined. */
export function Active(): Entry | undefined {
    const n = Name();
    return n === undefined ? undefined : TABLE[n];
}

function listed(s: Sides | undefined, team: Team, pos: number | undefined): boolean {
    if (s === undefined || pos === undefined) return false;
    const list = team === Team.Radiant ? s.r : s.d;
    return list !== undefined && list.indexOf(pos) >= 0;
}

/** The bot's role in the active drill: `play` when no drill is on. A hero whose position is not known yet plays. */
export function RoleOf(bot: Unit): Role {
    const d = Active();
    if (d === undefined) return "play";
    const pos = LaneConfig.PositionOf(bot);
    if (pos === undefined) return "play";
    if (listed(d.cast, bot.GetTeam(), pos)) return "cast";
    if (listed(d.statue, bot.GetTeam(), pos)) return "statue";
    if (listed(d.sentry, bot.GetTeam(), pos)) return "sentry";
    if (listed(d.laneOnly, bot.GetTeam(), pos)) return "laneonly";
    return d.others;
}

/** Benched, a statue or a sentry: the hero holds farm mode above every other mode, takes the drill's step and never casts. */
export function Held(bot: Unit): boolean {
    const r = RoleOf(bot);
    return r === "bench" || r === "statue" || r === "sentry";
}

/** Lane-only: the cast of an entry with `castLaneOnly`, or another hero under `others: "laneonly"`. */
export function LaneOnly(bot: Unit): boolean {
    const r = RoleOf(bot);
    const d = Active();
    return d !== undefined && ((r === "cast" && d.castLaneOnly === true) || r === "laneonly");
}

/** A lane-only hero of an entry with `laneHold`: the wave hold may act for it. */
export function LaneHold(bot: Unit): boolean {
    return Active()?.laneHold === true && LaneOnly(bot);
}

/** A lane-only hero of an entry with `laneAggro`: lane aggro's draws may act for it. */
export function LaneAggro(bot: Unit): boolean {
    return Active()?.laneAggro === true && LaneOnly(bot);
}

/** An Overrides key the active drill implies, or undefined. */
export function Implied(key: string): unknown {
    return Active()?.overrides?.[key];
}

const FOUNTAIN: Record<number, [number, number, number]> = { [Team.Radiant]: [-6619, -6336, 384], [Team.Dire]: [6928, 6372, 392] };
// A statue stands this far behind its own lane front (GetLaneFrontLocation's delta), out of the clash.
const STATUE_BEHIND = -300;
// It keeps a move order on at all times, swapping between two points this far apart: a hero with no order acquires
// enemies in range and auto-attacks, which a statue must never do.
const STATUE_SWAY = 40;
const statueSide: Record<number, number> = {};
/**
 * A sentry answers an enemy hero within its attack range + both bounding radii + this many seconds of its own movement, and
 * never leaves its spot by more than that movement: a laner stepping in to hit someone who walked into it. The same 0.5 s
 * as the contest price's STEP_IN on purpose: this step grades the price's damage and time terms on its own zone; a sentry
 * that chases further is a later step. `judgement`.
 */
export const SENTRY_STEP = 0.5;

/** A cast with `castIdle: "statue"`: it stands as a statue while its forced job does not run (the chooser asks the job
 *  first and gives this hero the statue's step only when the job neither runs nor starts). */
export function IdleStatue(bot: Unit): boolean {
    return Active()?.castIdle === "statue" && RoleOf(bot) === "cast";
}

/** The one chooser job a cast may run (the forced context, for an entry with `castIdle`), or undefined: every job. */
export function ForcedJob(bot: Unit): string | undefined {
    const d = Active();
    return d !== undefined && d.castIdle !== undefined && RoleOf(bot) === "cast" ? d.forces : undefined;
}

/** For a context the drill forces: whether the rep that `t` falls in carries the input (`on`), withholds it (`off`, a
 *  control rep) or is before the first rep (`none`); undefined when the drill does not force `context`. A pull reads it at
 *  its pulled wave's spawn second. */
export function ForcedAt(context: string, t: number): "on" | "off" | "none" | undefined {
    const d = Active();
    if (d === undefined || d.forces !== context) return undefined;
    const n = RepAt(t);
    if (n === 0) return "none";
    return controlRep(d, n) ? "off" : "on";
}

/**
 * The held hero's step: a benched hero walks to its fountain and waits; a statue (or an idle-statue cast) walks to its lane
 * spot behind its own creeps and sways there. False when the hero is not held.
 */
export function Hold(bot: Unit): boolean {
    const r = RoleOf(bot);
    if (r === "bench") {
        const [x, y, z] = FOUNTAIN[bot.GetTeam()];
        const f = Vector(x, y, z);
        if (GetUnitToLocationDistance(bot, f) > 300) bot.Action_MoveToLocation(f);
        return true;
    }
    if (r !== "statue" && r !== "sentry" && !IdleStatue(bot)) return false;
    const lane = bot.GetAssignedLane() as Lane;
    const spot = GetLaneFrontLocation(bot.GetTeam(), lane, STATUE_BEHIND);
    if (r === "sentry" && sentryAttack(bot, spot)) return true;
    const pid = bot.GetPlayerID();
    let side = statueSide[pid] ?? 1;
    let target = Vector(spot.x + side * STATUE_SWAY * 0.5, spot.y, spot.z);
    if (GetUnitToLocationDistance(bot, target) < 15) {
        side = -side;
        statueSide[pid] = side;
        target = Vector(spot.x + side * STATUE_SWAY * 0.5, spot.y, spot.z);
    }
    bot.Action_MoveToLocation(target);
    return true;
}

/** The sentry's answer: attack the nearest enemy hero inside its zone while it stands within its step of its spot. */
function sentryAttack(bot: Unit, spot: ReturnType<typeof GetLaneFrontLocation>): boolean {
    const step = SENTRY_STEP * bot.GetCurrentMovementSpeed();
    if (GetUnitToLocationDistance(bot, spot) > step) return false;
    const reach = bot.GetAttackRange() + bot.GetBoundingRadius() + step;
    let best: Unit | undefined;
    let bestD = math.huge;
    for (const h of bot.GetNearbyHeroes(1600, true, BotMode.None) ?? []) {
        if (!h.IsAlive()) continue;
        const d = GetUnitToUnitDistance(bot, h) - h.GetBoundingRadius();
        if (d <= reach && d < bestD) {
            best = h;
            bestD = d;
        }
    }
    if (best === undefined) return false;
    bot.Action_AttackUnit(best, true);
    return true;
}

/** The active drill's rep start times for a forced context (DotaTime seconds, up to 60:00), input-on reps only. */
export function RepTimes(context: string): number[] | undefined {
    const d = Active();
    if (d === undefined || d.forces !== context) return undefined;
    const out: number[] = [];
    let n = 0;
    for (let t = d.rep.from; t <= 3600; t += d.rep.every) {
        n += 1;
        if (!controlRep(d, n)) out.push(t);
    }
    return out;
}

function controlRep(d: Entry, n: number): boolean {
    return d.rep.control !== undefined && d.rep.control > 0 && n % d.rep.control === 0;
}

/** The rep (1-based) that `t` falls in, or 0 before the first. */
export function RepAt(t: number): number {
    const d = Active();
    if (d === undefined || t < d.rep.from) return 0;
    return math.floor((t - d.rep.from) / d.rep.every) + 1;
}

const lastRep: Record<number, number> = {};
const lastRole: Record<number, string> = {};
// Knobs drills replaced (08/11/2026): setting one now does nothing, so it is logged once instead of failing silently.
const REMOVED = ["Solo", "StackEvery", "LaneOnly"];
let removedLogged = false;

/**
 * Per hero per frame: the role line when it changes, and the team's rep line once per rep from its first cast hero. Only
 * from the pregame on: strategy time runs its own clock up to 0 before the pregame resets it to -90, so a line logged then
 * would fall in another game of the log store and fire rep 1 early (drill1, 08/11/2026).
 */
export function Tick(bot: Unit): void {
    const state = GetGameState();
    if (state !== GameState.PreGame && state !== GameState.GameInProgress) return;
    if (!removedLogged) {
        removedLogged = true;
        for (const k of REMOVED) {
            const v = overrides()?.[k];
            if (v !== undefined && v !== false && v !== -1) Telemetry.Event("drill", [["ph", "removed"], ["name", k]]);
        }
    }
    const name = Name();
    if (name === undefined) {
        const asked = overrides()?.["Drill"];
        if (typeof asked === "string" && asked !== "" && lastRole[-1] !== asked) {
            lastRole[-1] = asked;
            Telemetry.Event("drill", [["ph", "unknown"], ["name", asked]]);
        }
        return;
    }
    const d = TABLE[name];
    const pid = bot.GetPlayerID();
    const role = RoleOf(bot);
    const pos = LaneConfig.PositionOf(bot);
    if (lastRole[pid] !== role) {
        lastRole[pid] = role;
        Telemetry.Event("drill", [["ph", "role"], ["name", name], ["pid", pid], ["team", bot.GetTeam()], ["pos", pos], ["role", role]]);
    }
    if (role !== "cast") return;
    const now = DotaTime();
    const rep = RepAt(now);
    const team = bot.GetTeam();
    if (rep === 0 || lastRep[team] === rep) return;
    lastRep[team] = rep;
    const start = d.rep.from + (rep - 1) * d.rep.every;
    Telemetry.Event("drill", [
        ["ph", "rep"],
        ["name", name],
        ["team", team],
        ["rep", rep],
        ["input", controlRep(d, rep) ? "off" : "on"],
        ["start", start],
        ["forces", d.forces],
    ]);
}

/** Tests: forget the role and rep lines already logged. */
export function ResetCache(): void {
    for (const k of Object.keys(lastRep)) delete lastRep[k as unknown as number];
    for (const k of Object.keys(lastRole)) delete lastRole[k as unknown as number];
    for (const k of Object.keys(statueSide)) delete statueSide[k as unknown as number];
    removedLogged = false;
}
