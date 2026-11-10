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
import { BotMode, GameState, Lane, Team, Tower, Unit, Vector } from "bots/ts_libs/dota";
import Customize = require("bots/FunLib/custom_loader");
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

/** What a hero does in a drill. `play`: everything, as in a normal game. */
export type Role = "cast" | "bench" | "statue" | "sentry" | "chaser" | "laneonly" | "play";

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
    /** Per statue (team, position): its spot per rep, cycling (rep n takes entry (n - 1) mod length; before rep 1 its lane):
     *  `lane` (behind its own creeps), `bench` (its fountain), `pull:<r|d>:<safe|off>` (beside the first pull camp of that
     *  team's lane, the side away from the camp's lane, so in fog from the lane; `:seen` appended: the lane side, in the
     *  lane's sight, for a gate that reads a visible hero). A statue with a spot walks there and stands. */
    spots?: { r?: Record<number, string[]>; d?: Record<number, string[]> };
    /** Heroes that stand as statues but attack an enemy hero inside their zone (Hold); checked after `statue`. */
    sentry?: Sides;
    /** Heroes that stand behind their own creeps and chase and hit an enemy hero within CHASE_RANGE of that spot, walking
     *  back past it; benched (in the fountain) on control reps. Checked after `sentry`. */
    chaser?: Sides;
    /** Chasers hit only the cast, never a statue beside it (an ally statue in reach must not draw the chase). */
    chaseCast?: boolean;
    /** Chasers of this entry stand off once per chase rep when the target's HP share is at or under LINGER_HP (see `lingerStep`). */
    linger?: boolean;
    /** The cast's start spot per rep, cycling as `spots` (rep n takes entry (n - 1) mod length): `tower` (inside the enemy
     *  T1's reach of the cast's lane), `front` (our lane front of the cast's lane), `pull:<r|d>:<safe|off>`. The forced
     *  context walks the cast there (`CastSpot`) before it acts. */
    castSpots?: string[];
    /** Heroes that play lane-only (as `castLaneOnly`); checked after `statue`. */
    laneOnly?: Sides;
    /** Lane-only heroes also run the wave hold (states/wave_hold, under its switches) and the hold's own draw; no other lane
     *  aggro draw starts. Its control arm is the same drill with `Ours.CoreHold` off. */
    laneHold?: boolean;
    /** Lane-only cores also run lane aggro's draws (the feed under the lane controller's word, tower), as a
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
    // Slice retreat (master slices/retreat.md "Drill"): the forced retreat from fixed points. Each rep the Radiant pos1 walks
    // to the rep's start spot and our retreat starts there (why=forced) and runs to its anchor; the Dire offlane pair stand in
    // their lane as statues, so the route's tower, wave and hero costs are all there but nothing acts. 60 s reps (rtwalk1: 45 s
    // cut the walk from the far spots before the anchor); the recipe runs to 8:00 for two reps per spot.
    "retreat-walk": {
        note: "Radiant pos1 walks to a start spot each 60 s rep (Dire bot T1 reach, our lane front, our safe pull camp) and our retreat is forced there; Dire pos3 and pos4 statues in lane; everyone else benched",
        cast: SAFE_CORE,
        statue: { d: [3, 4] },
        others: "bench",
        castSpots: ["tower", "front", "pull:r:safe"],
        rep: { every: 60, from: 30 },
        forces: "retreat",
    },
    // The chase drill (prediction): the Radiant pos1 lane-only with our retreat live; the Dire pos3 chases and hits it whenever
    // it comes within CHASE_RANGE of the chaser's lane spot on odd reps, and is benched on even reps (the control).
    "retreat-chase": {
        note: "Radiant pos1 lane-only with our retreat live; Dire pos3 chases it within 1,500 of its lane spot on odd reps, waits behind its own T1 on even reps (control); everyone else benched",
        cast: SAFE_CORE,
        chaser: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        rep: { every: 60, from: 60, control: 2 },
    },
    // The rtwatch1 shape (slice retreat, plan 2026-11-10-retreat-read-bars): the chase drill, but once per rep the chaser stands
    // off about 1,100 from the cast when she is low, so the lane spot's read bars are graded on a place the old limits pass.
    "retreat-linger": {
        note: "retreat-chase, and once per chase rep the Dire pos3 chaser stands 1,100 off the cast when she is at or under 45% HP, for up to 20 s or until she steps into its attack range; everyone else benched",
        cast: SAFE_CORE,
        chaser: { d: [3] },
        linger: true,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 60, from: 60, control: 2 },
    },
    // Two chasers (slice retreat step 3): the same drill with the Dire pos3 and pos4 both chasing, so the leave rule's `lethal`
    // (more heroes in reach than ours, no escape) and the lane spot's read of two heroes get forced reps.
    "retreat-chase2": {
        note: "Radiant pos1 lane-only with our retreat live; Dire pos3 and pos4 chase it within 1,500 of their lane spots on odd reps, waits behind its own T1 on even reps (control); everyone else benched",
        cast: SAFE_CORE,
        chaser: { d: [3, 4] },
        others: "bench",
        castLaneOnly: true,
        rep: { every: 60, from: 60, control: 2 },
    },
    // Slice even-fight (D24, D1): the same two chasers on the Radiant pos1, with its pos5 a statue at its lane spot on odd reps
    // (an even 2v2: stay unless lethal) and benched on even reps (a 1v2: leave); every fourth rep is the control (no chase).
    "retreat-even": {
        note: "Radiant pos1 lane-only with our retreat live; Dire pos3 and pos4 chase only it; Radiant pos5 a statue beside it on odd reps (2v2), benched on even reps (1v2); every 4th rep no chase",
        cast: SAFE_CORE,
        statue: { r: [5] },
        spots: { r: { 5: ["lane", "bench"] } },
        chaser: { d: [3, 4] },
        chaseCast: true,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 60, from: 60, control: 4 },
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
    // Slice lh-draw step 2: the deny feed on every wave the lane controller does not shove, against an enemy that hits back
    // (deaths or HP lost on feeds would bring the danger checks in). No forced lever: the controller decides live.
    "feed-every": {
        note: "Radiant pos1 lane-only with lane aggro, the lane controller live, Dire pos3 a sentry in the lane, everyone else benched",
        cast: SAFE_CORE,
        sentry: { d: [3] },
        others: "bench",
        castLaneOnly: true,
        laneAggro: true,
        rep: { every: 30, from: 0 },
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
    // Slice threat (design s7 slice 1): the missing belief's prediction drill. The Radiant offlane pos3 holds its lane (the
    // lane controller reads its hard-camp pull gate each wave); the Dire pos5 is a statue that stands each rep at one known
    // spot: beside the camp the pos3 pulls (on its walk), benched (the control), beside Dire's offlane pull camp across the
    // map, in its own lane in sight. Reps of 90 s give the walk across the map time before the next wave's read; to 10:00 so
    // reads fall both sides of the belief's 4:00 weight change.
    "threat-missing": {
        note: "Radiant pos3 lane-only in its lane; Dire pos5 a statue at a spot per rep (by the pos3's pull camp, bench, Dire offlane camp, its lane); everyone else benched",
        cast: { r: [3] },
        statue: { d: [5] },
        spots: { d: { 5: ["pull:r:off", "bench", "pull:d:off", "lane"] } },
        others: "bench",
        castLaneOnly: true,
        rep: { every: 90, from: 30 },
    },
    // Core next gold without the level gate: the Radiant pos1 and pos3 alone, a trip whenever an open camp's priced HP and
    // time fit (CampForce: the decision's wave, gap and net gates off, the HP, threat and missing gates on), so the clear's
    // HP price at levels 2-5 is graded on each trip (hpc against hpm, by lvl and src) before any game.
    "core-camp": {
        note: "Radiant pos1 and pos3 play, a camp trip whenever a camp's priced HP and time fit (CampForce), everyone else benched",
        cast: { r: [1, 3] },
        others: "bench",
        rep: { every: 30, from: 0 },
        overrides: { CampForce: true },
    },
    // Slice threat: the support's pull start on the read (PullJob.Wants). The pos5 plays its lane (pulls when the controller
    // says so); the Dire pos3 stands on the lane side of the pos5's pull camp on odd reps, in the lane's sight (the gate holds
    // on `reach`; the fog side, thrdr3c 09/11/2026, is unseen from the lane and a hero last seen 1,300 away in lane weighs
    // 0.02 at a camp this far on our side, so two pulls ran beside it) and is benched on even ones (control: the pull runs).
    // The pull is forced every wave (the controller's word is not asked: thrdr3 to thrdr3d, 09/11/2026, it wanted a pull on
    // 1 of 5 statue windows); 120 s reps because the statue walks about 40 s from its fountain to the camp.
    "threat-support": {
        note: "Radiant pos5 plays its lane and pulls every wave; Dire pos3 a statue on the lane side of the pos5's pull camp on odd reps, benched on even; everyone else benched",
        cast: { r: [5] },
        statue: { d: [3] },
        spots: { d: { 3: ["pull:r:safe:seen", "bench"] } },
        others: "bench",
        rep: { every: 120, from: 30 },
        forces: "pull",
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
    if (listed(d.chaser, bot.GetTeam(), pos)) return "chaser";
    if (listed(d.laneOnly, bot.GetTeam(), pos)) return "laneonly";
    return d.others;
}

/** Benched, a statue, a sentry or a chaser: the hero holds farm mode above every other mode, takes the drill's step and never casts. */
export function Held(bot: Unit): boolean {
    const r = RoleOf(bot);
    return r === "bench" || r === "statue" || r === "sentry" || r === "chaser";
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
const lastSpot: Record<number, string> = {};
/** How far beside a pull camp's box a spot statue stands (outside the box, so it blocks no spawn). judgement. */
const SPOT_OFFSET = 250;
/**
 * A sentry answers an enemy hero within its attack range + both bounding radii + this many seconds of its own movement, and
 * never leaves its spot by more than that movement: a laner stepping in to hit someone who walked into it. The same 0.5 s
 * as the contest price's STEP_IN on purpose: this step grades the price's damage and time terms on its own zone; a sentry
 * that chases further is a later step. `judgement`.
 */
export const SENTRY_STEP = 0.5;
/** A chaser follows an enemy hero up to this far from its lane spot (slice retreat's chase drill). `judgement`. */
export const CHASE_RANGE = 1500;
/** The `tower` cast spot stands this far from the enemy T1 toward our own T1 of the lane: inside its reach (868). `judgement`. */
const TOWER_SPOT = 500;

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
    const d = Active();
    if (r === "chaser" && d !== undefined && !controlRep(d, RepAt(DotaTime())) && RepAt(DotaTime()) > 0) {
        return chase(bot);
    }
    // A stand-off started late in a chase rep runs on into the control rep that follows (its wait starts after the window).
    if (r === "chaser" && lingering[bot.GetPlayerID()] !== undefined && lingerTick(bot, GetLaneFrontLocation(bot.GetTeam(), bot.GetAssignedLane() as Lane, STATUE_BEHIND))) return true;
    if (r === "chaser") {
        // Waiting between chase reps: behind its own T1 (user 10/11/2026), so the next rep starts without the fountain walk.
        const at = behindOwnT1(bot);
        if (at !== undefined) {
            if (GetUnitToLocationDistance(bot, at) > 100) bot.Action_MoveToLocation(at);
            return true;
        }
    }
    if (r === "bench" || r === "chaser") {
        const [x, y, z] = FOUNTAIN[bot.GetTeam()];
        const f = Vector(x, y, z);
        if (GetUnitToLocationDistance(bot, f) > 300) bot.Action_MoveToLocation(f);
        return true;
    }
    if (r !== "statue" && r !== "sentry" && !IdleStatue(bot)) return false;
    const named = r === "statue" ? SpotOf(bot) : "lane";
    if (named !== "lane") {
        const at = spotPoint(bot, named);
        noteSpot(bot, named, at);
        if (at !== undefined && GetUnitToLocationDistance(bot, at) > 50) bot.Action_MoveToLocation(at);
        return true;
    }
    if (r === "statue" && Active()?.spots !== undefined) noteSpot(bot, named, undefined);
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

/** A statue's spot for the current rep (`lane` before the first rep or without a spot list). */
export function SpotOf(bot: Unit): string {
    const d = Active();
    const pos = LaneConfig.PositionOf(bot);
    const list = pos !== undefined ? (bot.GetTeam() === Team.Radiant ? d?.spots?.r : d?.spots?.d)?.[pos] : undefined;
    const rep = RepAt(DotaTime());
    if (list === undefined || list.length === 0 || rep === 0) return "lane";
    return list[(rep - 1) % list.length];
}

/** The point a spot names; the fountain for `bench`, undefined for an unknown spot (the statue then stands where it is). */
function spotPoint(bot: Unit, spot: string): Vector | undefined {
    if (spot === "bench") {
        const [x, y, z] = FOUNTAIN[bot.GetTeam()];
        return Vector(x, y, z);
    }
    const [side, kind, seen] = string.match(spot, "^pull:([rd]):(%a+)(:?%a*)$");
    if (side === undefined || (kind !== "safe" && kind !== "off") || (seen !== "" && seen !== ":seen")) return undefined;
    // Lazy: camps reaches modules that read the drill.
    const Camps = require("bots/FunLib/humaniser/camps") as typeof import("bots/FunLib/humaniser/camps");
    const team = side === "r" ? Team.Radiant : Team.Dire;
    const camp = Camps.PullCampsFor(team, Camps.LaneOfKind(team, kind))[0];
    const s = camp !== undefined ? Camps.SpawnerByIdx(camp.campIdx) : undefined;
    if (s === undefined) return undefined;
    const c = Camps.BoxCenter(s);
    const lane = GetLaneFrontLocation(team, Camps.LaneOfKind(team, kind), 0);
    // SPOT_OFFSET past the box edge so the statue blocks no spawn (Camps.StandPoint caps at StandReach from the spawner
    // origin and landed inside the box, thrdr3d 09/11/2026: the 1:00 and 2:00 spawns blocked): the side away from the lane,
    // or the lane side for `:seen`.
    return Camps.BoxEdgePoint(s, seen === ":seen" ? lane : Vector(2 * c.x - lane.x, 2 * c.y - lane.y, c.z), SPOT_OFFSET);
}

function noteSpot(bot: Unit, spot: string, at: Vector | undefined): void {
    const pid = bot.GetPlayerID();
    const key = `${RepAt(DotaTime())}:${spot}`;
    if (lastSpot[pid] === key) return;
    lastSpot[pid] = key;
    Telemetry.Event("drill", [["ph", "spot"], ["name", Name()], ["pid", pid], ["team", bot.GetTeam()], ["rep", RepAt(DotaTime())], ["spot", spot], ["x", at !== undefined ? math.floor(at.x) : undefined], ["y", at !== undefined ? math.floor(at.y) : undefined]]);
}

/** How far behind its own T1, towards its fountain, a waiting chaser stands. `judgement`. */
const CHASER_WAIT_BEHIND = 350;

/** The point behind our own T1 of the hero's lane, towards our fountain; undefined without the tower. */
function behindOwnT1(bot: Unit): Vector | undefined {
    const ids: Record<number, Tower> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };
    const tw = GetTower(bot.GetTeam(), ids[bot.GetAssignedLane() as Lane]);
    if (tw === null || tw === undefined || !tw.IsAlive()) return undefined;
    const a = tw.GetLocation();
    const [fx, fy] = FOUNTAIN[bot.GetTeam()];
    const len = math.max(1, math.sqrt((fx - a.x) ** 2 + (fy - a.y) ** 2));
    return Vector(a.x + ((fx - a.x) * CHASER_WAIT_BEHIND) / len, a.y + ((fy - a.y) * CHASER_WAIT_BEHIND) / len, a.z);
}

/** retreat-linger: the target's HP share at or under which the chaser stands off (rtwatch1's episode ended at 37%, the walk back began at 38%). `judgement`. */
const LINGER_HP = 0.45;
/** retreat-linger: the longest stand-off (rtwatch1's contact came 15 s after the episode ended). `judgement`. */
const LINGER_SECS = 20;
/** retreat-linger: the distance held from the target (rtwatch1: Sand King about 1,100 away, just outside a 2 s reach). `judgement`. */
const LINGER_DIST = 1100;
/** The chaser counts as standing off at this much under LINGER_DIST (it stops within 50 of the point, which the tower pull-back may move). `judgement`. */
const LINGER_STANDOFF_SLACK = 100;
/** The tower's reach fallback and the margin kept outside it, as retreat.ts reads the reach. `judgement` for the margin. */
const TOWER_REACH_FALLBACK = 868;
const LINGER_TOWER_MARGIN = 100;

interface Linger {
    rep: number;
    /** When the back-off began (the HP trigger), and when the chaser first stood at the stand-off (the window's clock). */
    tgo: number;
    t0?: number;
    tpid: number;
    /** Closest distance since the stand-off (undefined before it), furthest since the trigger, the last seen distance. */
    dmin?: number;
    dmax: number;
    dlast?: number;
    clamp: number;
    /** Seconds the target was out of sight, the last tick's time, the last stand-off point. */
    uns: number;
    tlast: number;
    pt?: Vector;
}
const lingering: Record<number, Linger> = {};
/** The rep each chaser last lingered in (once per rep). */
const lingered: Record<number, number> = {};

function endLinger(bot: Unit, res: string, dnow?: number): void {
    const pid = bot.GetPlayerID();
    const st = lingering[pid];
    if (st === undefined) return;
    delete lingering[pid];
    Telemetry.Event("drill", [
        ["ph", "linger_end"],
        ["name", Name()],
        ["pid", pid],
        ["tpid", st.tpid],
        ["rep", st.rep],
        ["res", res],
        ["secs", math.floor((DotaTime() - (st.t0 ?? st.tgo)) * 10 + 0.5) / 10],
        ["dmin", st.dmin !== undefined ? math.floor(st.dmin) : undefined],
        ["dmax", math.floor(st.dmax)],
        ["dend", dnow !== undefined ? math.floor(dnow) : st.dlast !== undefined ? math.floor(st.dlast) : undefined],
        ["uns", math.floor(st.uns * 10 + 0.5) / 10],
        ["clamp", st.clamp],
    ]);
}

/** The point LINGER_DIST from `target` on the line towards `spot`, pulled out of our (Radiant's) T1 reach + a margin. */
function lingerPoint(bot: Unit, target: Unit, spot: Vector): [Vector, number] {
    const a = target.GetLocation();
    const len = math.max(1, math.sqrt((spot.x - a.x) ** 2 + (spot.y - a.y) ** 2));
    let p = Vector(a.x + ((spot.x - a.x) * LINGER_DIST) / len, a.y + ((spot.y - a.y) * LINGER_DIST) / len, spot.z);
    const ids: Record<number, Tower> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };
    const tw = GetTower(target.GetTeam(), ids[bot.GetAssignedLane() as Lane]);
    if (tw === null || tw === undefined || !tw.IsAlive()) return [p, 0];
    const tl = tw.GetLocation();
    const reach = WorldFacts.TowerReach(tw, TOWER_REACH_FALLBACK) + LINGER_TOWER_MARGIN;
    const td = math.max(1, math.sqrt((p.x - tl.x) ** 2 + (p.y - tl.y) ** 2));
    if (td >= reach) return [p, 0];
    p = Vector(tl.x + ((p.x - tl.x) * reach) / td, tl.y + ((p.y - tl.y) * reach) / td, p.z);
    return [p, 1];
}

/** The unit `pid` among the enemy heroes near `bot`, or undefined. */
function nearbyHero(bot: Unit, pid: number): Unit | undefined {
    for (const h of bot.GetNearbyHeroes(1600, true, BotMode.None) ?? []) if (h.IsAlive() && h.GetPlayerID() === pid) return h;
    return undefined;
}

/** retreat-linger: the HP trigger, once per rep. The chaser backs off; the window's clock starts when it stands at the stand-off. */
function startLinger(bot: Unit, target: Unit): boolean {
    const pid = bot.GetPlayerID();
    const rep = RepAt(DotaTime());
    // A cast out of sight reads wrong (thp 666 in rtlng1b): it starts nothing.
    if (target.GetLocation() === undefined) return false;
    const share = target.GetHealth() / math.max(1, target.GetMaxHealth());
    if (lingered[pid] === rep || share > LINGER_HP || share < 0) return false;
    const d = GetUnitToUnitDistance(bot, target);
    // The once-per-rep flag and the state are set before the line is logged.
    lingered[pid] = rep;
    lingering[pid] = { rep, tgo: DotaTime(), tpid: target.GetPlayerID(), dmax: d, dlast: d, clamp: 0, uns: 0, tlast: DotaTime() };
    const d0 = Active();
    Telemetry.Event("drill", [
        ["ph", "linger_go"],
        ["name", Name()],
        ["pid", pid],
        ["tpid", target.GetPlayerID()],
        ["rep", rep],
        ["thp", math.floor(share * 100 + 0.5) / 100],
        ["d", math.floor(d)],
        ["rend", d0 !== undefined ? d0.rep.from + rep * d0.rep.every : undefined],
    ]);
    return true;
}

/**
 * retreat-linger: one tick of a started stand-off; true when the chaser's order is given. It runs past the rep's end (the next
 * control rep's wait begins after it). Phases: backing off to the stand-off (ends `no_standoff` after LINGER_SECS), then the
 * window of LINGER_SECS from the first tick at LINGER_DIST - 100 or more from the target; it ends `contact` (the target within
 * the chaser's attack range + 100: the caller attacks in a chase rep), `timeout` or `died`; a target out of sight does not end it.
 */
function lingerTick(bot: Unit, spot: Vector): boolean {
    const pid = bot.GetPlayerID();
    const st = lingering[pid];
    if (st === undefined) return false;
    const now = DotaTime();
    const dt = now - st.tlast;
    st.tlast = now;
    const target = nearbyHero(bot, st.tpid);
    const seen = target !== undefined && target.GetLocation() !== undefined;
    if (!seen) {
        // Out of sight (night, fog) is part of the shape: hold the last stand-off point and keep the clock running.
        if (!IsHeroAlive(st.tpid)) {
            endLinger(bot, "died");
            return false;
        }
        st.uns += dt;
    } else {
        const dd = GetUnitToUnitDistance(bot, target);
        st.dlast = dd;
        st.dmax = math.max(st.dmax, dd);
        if (st.t0 === undefined && dd >= LINGER_DIST - LINGER_STANDOFF_SLACK) {
            st.t0 = now;
            const share = target.GetHealth() / math.max(1, target.GetMaxHealth());
            Telemetry.Event("drill", [["ph", "linger"], ["name", Name()], ["pid", pid], ["tpid", st.tpid], ["rep", st.rep], ["thp", share >= 0 && share <= 1 ? math.floor(share * 100 + 0.5) / 100 : undefined], ["d", math.floor(dd)]]);
        }
        if (st.t0 !== undefined) {
            st.dmin = st.dmin !== undefined ? math.min(st.dmin, dd) : dd;
            if (dd <= bot.GetAttackRange() + 100) {
                endLinger(bot, "contact", dd);
                return false;
            }
        }
    }
    if (st.t0 === undefined && now - st.tgo >= LINGER_SECS) {
        endLinger(bot, "no_standoff", st.dlast);
        return false;
    }
    if (st.t0 !== undefined && now - st.t0 >= LINGER_SECS) {
        endLinger(bot, "timeout", st.dlast);
        return false;
    }
    if (seen) {
        const [p, clamp] = lingerPoint(bot, target, spot);
        if (clamp === 1) st.clamp = 1;
        st.pt = p;
    }
    if (st.pt !== undefined && GetUnitToLocationDistance(bot, st.pt) > 50) bot.Action_MoveToLocation(st.pt);
    return true;
}

/** The chaser's step: attack the nearest enemy hero within CHASE_RANGE of its lane spot, else walk back to the spot. */
function chase(bot: Unit): boolean {
    const spot = GetLaneFrontLocation(bot.GetTeam(), bot.GetAssignedLane() as Lane, STATUE_BEHIND);
    let best: Unit | undefined;
    let bestD = math.huge;
    const castOnly = Active()?.chaseCast === true;
    for (const h of bot.GetNearbyHeroes(1600, true, BotMode.None) ?? []) {
        if (!h.IsAlive() || h.GetLocation() === undefined || GetUnitToLocationDistance(h, spot) > CHASE_RANGE) continue;
        if (castOnly && RoleOf(h) !== "cast") continue;
        const dd = GetUnitToUnitDistance(bot, h);
        if (dd < bestD) {
            best = h;
            bestD = dd;
        }
    }
    const st = lingering[bot.GetPlayerID()];
    if (st !== undefined && st.rep !== RepAt(DotaTime())) endLinger(bot, "rep_end");
    if (Active()?.linger === true) {
        if (best !== undefined && lingering[bot.GetPlayerID()] === undefined) startLinger(bot, best);
        if (lingerTick(bot, spot)) return true;
    }
    if (best !== undefined) bot.Action_AttackUnit(best, true);
    else if (GetUnitToLocationDistance(bot, spot) > 50) bot.Action_MoveToLocation(spot);
    return true;
}


/** The cast's start spot for rep `rep` (`castSpots`), or undefined when the entry has none. */
export function CastSpot(rep: number): string | undefined {
    const list = Active()?.castSpots;
    if (list === undefined || list.length === 0 || rep <= 0) return undefined;
    return list[(rep - 1) % list.length];
}

/** The point a cast spot names for `bot`, or undefined. */
export function CastSpotPoint(bot: Unit, spot: string): Vector | undefined {
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane() as Lane;
    if (spot === "front") return GetLaneFrontLocation(team, lane, 0);
    if (spot === "tower") {
        const ids: Record<number, Tower> = { [Lane.Top]: Tower.Top1, [Lane.Mid]: Tower.Mid1, [Lane.Bot]: Tower.Bot1 };
        const enemy = team === Team.Radiant ? Team.Dire : Team.Radiant;
        const theirs = GetTower(enemy, ids[lane]);
        const ours = GetTower(team, ids[lane]);
        if (theirs === null || theirs === undefined) return undefined;
        const a = theirs.GetLocation();
        const b = ours !== null && ours !== undefined ? ours.GetLocation() : GetLaneFrontLocation(team, lane, 0);
        const len = math.max(1, math.sqrt((b.x - a.x) ** 2 + (b.y - a.y) ** 2));
        return Vector(a.x + ((b.x - a.x) * TOWER_SPOT) / len, a.y + ((b.y - a.y) * TOWER_SPOT) / len, a.z);
    }
    return spotPoint(bot, spot);
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
    for (const k of Object.keys(lastSpot)) delete lastSpot[k as unknown as number];
    for (const k of Object.keys(lingering)) delete lingering[k as unknown as number];
    for (const k of Object.keys(lingered)) delete lingered[k as unknown as number];
    removedLogged = false;
}
