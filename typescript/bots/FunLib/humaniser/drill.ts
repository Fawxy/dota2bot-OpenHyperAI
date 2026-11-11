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
import { BotMode, GameState, Item, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import Customize = require("bots/FunLib/custom_loader");
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";

/** What a hero does in a drill. `play`: everything, as in a normal game. */
/** `actor`: a hero a rig's setup scripts (it takes only those steps). */
export type Role = "cast" | "bench" | "statue" | "sentry" | "chaser" | "laneonly" | "actor" | "play";

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
     *  back past it; waiting behind their own T1 on control reps. Checked after `sentry`. */
    chaser?: Sides;
    /** Chasers hit only the cast, never a statue beside it (an ally statue in reach must not draw the chase). */
    chaseCast?: boolean;
    /** Chasers keep OHA's spell and item use during a chase rep (the fast drop into `lethal` in games is not auto-attacks). */
    chaserCasts?: boolean;
    /** Chasers of this entry stand off once per chase rep when the target's HP share is at or under LINGER_HP (see `lingerStep`). */
    linger?: boolean;
    /** In a chase rep, the chasers break off for the rest of the rep (waiting behind their T1) once the cast's HP share is at
     *  or under this, and the cast's retreat starts nothing until then (`RetreatHeld`): the low-HP walk is forced. */
    breakAt?: number;
    /** A lane-only cast keeps OHA's item use (not its spells): the heal walk's salve. */
    castItems?: boolean;
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
    /** A rig (drills from 11/11/2026): each rep is setup, ready, release (see `Rig`). */
    rig?: Rig;
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
    // it comes within CHASE_RANGE of the chaser's lane spot on odd reps, and waits behind its own T1 on even reps (the control).
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
    // Slice even-fight (D24, D1): the same two chasers on the Radiant pos1, its pos5 a sentry in lane on every rep (it hits
    // them back, so the fight costs them), every fourth rep the control (no chase). A partner benched on alternate reps did
    // not walk back in time (drill retreat-even 1-4: beside the cast on rep 1 only); the 1v2 is retreat-chase2's.
    "retreat-even": {
        note: "Radiant pos1 lane-only with our retreat live; Dire pos3 and pos4 chase only it, with their spells and items; Radiant pos5 a sentry beside it (2v2); every 4th rep no chase",
        cast: SAFE_CORE,
        sentry: { r: [5] },
        chaser: { d: [3, 4] },
        chaseCast: true,
        chaserCasts: true,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 60, from: 60, control: 4 },
    },
    // Slice heal-stop (D3): the low-HP walk. The Dire pos3 hits only the Radiant pos1, whose retreat is held until it is at
    // 25% HP; then the chaser breaks off and the cast's own retreat runs (a leave, then the heal floor). Every bot is handed a
    // salve each rep (recipe), which the cast uses through OHA's item code, so HP comes back on the walk. 90 s reps (the off
    // arm's walk home and back is about 80 s); every 4th rep no chase.
    "retreat-heal": {
        note: "Radiant pos1 lane-only with our retreat live but held in a chase rep until 25% HP, OHA's items on; Dire pos3 chases only it and breaks off at 25%; a salve each rep; every 4th rep no chase",
        cast: SAFE_CORE,
        chaser: { d: [3] },
        chaseCast: true,
        breakAt: 0.25,
        castItems: true,
        others: "bench",
        castLaneOnly: true,
        rep: { every: 90, from: 60, control: 4 },
    },
    // Slice hit-back (D24's hit-back half; D10's leave-together as a rep kind, user 12/11/2026). half: decision. Facts the
    // hit back reads: an enemy hero damaged the cast within 1 s (forced: the Dire actor attacks it), standing inside our
    // creeps' aggro (forced: the spots sit at our bot lane front, which `paid` checks at ready), the trade's remaining
    // respects clear (no tower: the front is off both towers early; numbers even; HP over half: the attack stops at 60%), the
    // laning stage (window 600) and the cast in its lane. `pair`: two hitters and the Radiant pos5 beside the cast (an even
    // 2v2 the hold keeps), the pos5 walking home 3 s after ready (leave-together: the cast leaves within 2 s of it passing
    // 1,200). `control`: the pos3 stands beside and never attacks. Release: laning (last hits compete), attack (the trade),
    // retreat, idle. `Ours.RetreatOdds` on in both arms (recipe), so a held cast is what the hit back answers.
    "retreat-hitback": {
        note: "rig: Radiant pos1 at our bot lane front, hit by the Dire pos3 from inside our creeps' aggro to 60% (hit), or by the Dire pos3 and pos4 with our pos5 beside it until the pos5 walks home 3 s after ready (pair), or the pos3 stands by (control); then laning, attack, retreat; four 135 s reps from 1:00",
        cast: SAFE_CORE,
        others: "bench",
        // 135 s (fix2: the cast's heal walk from the front and back is about 80 s, and the fight 20 s), so four reps by 10:00.
        rep: { every: 135, from: 60 },
        rig: {
            half: "decision",
            switch: "HitBack",
            window: 600,
            spots: {
                cast: ["r:frontbot", -200, 0],
                partner: ["r:frontbot", -450, 0],
                near: ["r:frontbot", 0, 0],
            },
            timeout: 95,
            keeps: ["levelup"],
            release: { modes: ["laning", "attack", "retreat", "idle"] },
            reps: [
                {
                    name: "hit",
                    setup: { r1: ["heal", "stand cast"], d3: ["heal", "walk near", "attack r1 until hp 0.6", "leave"] },
                    ready: { paid: 500 },
                },
                {
                    name: "pair",
                    setup: {
                        r1: ["heal", "stand cast"],
                        r5: ["heal", "stand partner"],
                        d3: ["heal", "walk near", "attack r1 until hp 0.55", "leave"],
                        d4: ["heal", "walk near", "attack r1 until hp 0.55", "leave"],
                    },
                    after: { r5: ["wait 3", "leave"] },
                    ready: { paid: 500 },
                },
                {
                    name: "hit",
                    setup: { r1: ["heal", "stand cast"], d3: ["heal", "walk near", "attack r1 until hp 0.6", "leave"] },
                    ready: { paid: 500 },
                },
                {
                    name: "control",
                    setup: { r1: ["heal", "stand cast"], d3: ["heal", "stand near"] },
                    ready: { near: 800 },
                },
            ],
        },
    },
    // Slice heal-items' drill as a rig (slice drill-rig's first consumer). half: decision. Facts the heal start reads: the
    // cast's HP share (25% or under; a control rep 60%), the regen it holds (a salve, or a tango and no salve), whether an
    // enemy hero is in reach (none within 1,600, or the attacker standing by within 1,200), our lane front nearer than our
    // fountain (the waves, untouched). Forced: HP by the Dire pos3 attacking the statue cast until its share; items bought by
    // the cast at its fountain during setup (gold from the recipe); reach by where the attacker stands after. Both heal in
    // their fountain first (no console control sets a bot's HP: probe 12/11/2026, SCENARIOS.md; fix3: the attacker lost HP
    // standing beside a camp and died). Spots: 2,850 west of our bot T1, 700 off the lane (our creeps would hit the attacker),
    // over 1,000 from every camp box (fix3: `near` 621 from the small camp by T1). The attack stops 5 points under the ready
    // bar (fix5: stopping at the bar, the cast regenerated over it while the attacker walked out of reach). Release: our
    // retreat, else it stands (`idle`; fix6: a Valve built-in mode took the control rep's cast).
    "retreat-heal-items": {
        note: "rig: Radiant pos5 healed and handed a salve or a tango at its fountain, stood west of our bot T1 off the lane and away from camps, hit by the healed Dire pos3 to 25% (60% control); the attacker leaves for its fountain (or stays near); then only our retreat runs for it",
        cast: { r: [5] },
        others: "bench",
        rep: { every: 150, from: 60 },
        rig: {
            half: "decision",
            switch: "HealItems",
            window: 600,
            spots: {
                cast: ["r:bot1", -2750, 700],
                near: ["r:bot1", -2250, 700],
            },
            timeout: 110,
            // The attacker's learned spells count in the retreat's threat read (GetEstimatedDamageToTarget), so both level as on the base branch.
            keeps: ["levelup"],
            release: { modes: ["retreat", "idle"] },
            reps: [
                {
                    name: "salve",
                    setup: { r5: ["heal", "buy item_flask", "stand cast"], d3: ["heal", "walk near", "attack r5 until hp 0.2", "leave"] },
                    ready: { hpAtMost: 0.25, holds: ["item_flask"], clear: 1600 },
                },
                {
                    name: "tango",
                    setup: { r5: ["heal", "sell item_flask", "buy item_tango", "stand cast"], d3: ["heal", "walk near", "attack r5 until hp 0.2", "leave"] },
                    ready: { hpAtMost: 0.25, holds: ["item_tango"], lacks: ["item_flask"], clear: 1600 },
                },
                {
                    name: "stays",
                    setup: { r5: ["heal", "buy item_flask", "stand cast"], d3: ["heal", "walk near", "attack r5 until hp 0.2", "stand near"] },
                    ready: { hpAtMost: 0.25, holds: ["item_flask"], near: 1200 },
                },
                {
                    name: "control",
                    setup: { r5: ["heal", "buy item_flask", "stand cast"], d3: ["heal", "walk near", "attack r5 until hp 0.55", "leave"] },
                    ready: { hpAtMost: 0.6, holds: ["item_flask"], clear: 1600 },
                },
            ],
        },
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
    if (rigActor(d, bot)) return "actor";
    if (listed(d.statue, bot.GetTeam(), pos)) return "statue";
    if (listed(d.sentry, bot.GetTeam(), pos)) return "sentry";
    if (listed(d.chaser, bot.GetTeam(), pos)) return "chaser";
    if (listed(d.laneOnly, bot.GetTeam(), pos)) return "laneonly";
    return d.others;
}

/** Benched, a statue, a sentry or a chaser: the hero holds farm mode above every other mode, takes the drill's step and never casts. */
export function Held(bot: Unit): boolean {
    const r = RoleOf(bot);
    return r === "bench" || r === "statue" || r === "sentry" || r === "chaser" || r === "actor" || (r === "cast" && rigCastHeld(bot));
}

/** A chaser of an entry with `chaserCasts`, in a chase rep: OHA's spells and items stay on for it although it is held. */
export function Casts(bot: Unit): boolean {
    const d = Active();
    const rep = RepAt(DotaTime());
    return d !== undefined && d.chaserCasts === true && RoleOf(bot) === "chaser" && rep > 0 && !controlRep(d, rep);
}

/** The cast of an entry with `castItems`: OHA's item use stays on for it although it is lane-only. */
export function CastItems(bot: Unit): boolean {
    return Active()?.castItems === true && RoleOf(bot) === "cast";
}

/** The rep in which each cast first stood at or under `breakAt` HP (once reached, its retreat is free for the rest of the rep). */
const reachedBreak: Record<number, number> = {};

/**
 * The cast of an entry with `breakAt`, in a chase rep, above that HP share and not yet under it this rep: its retreat starts
 * nothing. `hp` is the cast's HP share (the caller's read).
 */
export function RetreatHeld(bot: Unit, hp: number): boolean {
    const d = Active();
    if (d === undefined || d.breakAt === undefined || RoleOf(bot) !== "cast") return false;
    const rep = RepAt(DotaTime());
    if (rep === 0 || controlRep(d, rep)) return false;
    const pid = bot.GetPlayerID();
    if (reachedBreak[pid] === rep) return false;
    if (hp > d.breakAt) return true;
    reachedBreak[pid] = rep;
    Telemetry.Event("drill", [["ph", "break"], ["name", Name()], ["pid", pid], ["rep", rep], ["thp", math.floor(hp * 100 + 0.5) / 100]]);
    return false;
}

/** The rep in which each chaser broke off (`breakAt`). */
const brokeOff: Record<number, number> = {};

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
    if (d?.rig !== undefined && (r === "actor" || r === "cast")) return Held(bot) ? rigHold(bot) : rigIdle(bot);
    if (r === "chaser" && d !== undefined && !controlRep(d, RepAt(DotaTime())) && RepAt(DotaTime()) > 0 && brokeOff[bot.GetPlayerID()] !== RepAt(DotaTime())) {
        if (chase(bot)) return true;
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
    const breakAt = Active()?.breakAt;
    if (best !== undefined && breakAt !== undefined && best.GetHealth() / math.max(1, best.GetMaxHealth()) <= breakAt) {
        const rep = RepAt(DotaTime());
        brokeOff[bot.GetPlayerID()] = rep;
        Telemetry.Event("drill", [["ph", "break"], ["name", Name()], ["pid", bot.GetPlayerID()], ["tpid", best.GetPlayerID()], ["rep", rep], ["thp", math.floor((best.GetHealth() / math.max(1, best.GetMaxHealth())) * 100 + 0.5) / 100]]);
        return false;
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

// ---- Rigs (skill eval-run "Drill", SCENARIOS.md "A new drill's entry is a rig spec", slice drill-rig) ----

/** The rig's ready checks: all must hold at once, on each cast hero. */
export interface RigReady {
    /** The cast's HP share at or under this. */
    hpAtMost?: number;
    /** Items the cast holds (inventory, one of each name). */
    holds?: string[];
    /** Items the cast does not hold. */
    lacks?: string[];
    /** No enemy hero within this distance of the cast. */
    clear?: number;
    /** An enemy hero within this distance of the cast. */
    near?: number;
    /**
     * An enemy hero damaged the cast within the last second, and every such hero stands within this distance of one of the
     * cast team's lane creeps (inside our creeps' aggro: slice hit-back).
     */
    paid?: number;
}

/** One kind of rep; a rig's reps cycle through these (rep n takes entry (n - 1) mod length). */
export interface RigRep {
    /** Logged as `var=` on the rep's lines. */
    name: string;
    /**
     * Ordered steps per hero (`r5`, `d3`: team and position). The cast's heroes and every actor are listed; a listed hero
     * that is not cast is an actor (held, it only takes these steps). Steps:
     * - `stand <spot>`: walk there and stay, swaying so it never auto-attacks (a statue); never ends.
     * - `walk <spot>`: walk there; ends on arrival.
     * - `heal`: its fountain until full HP (95%); ends at once when already full.
     * - `buy <item>` / `sell <item>`: at its fountain (walks there first); ends when done.
     * - `attack <hero> until hp <share>`: once that hero stands on its last step, attack it until its HP share is at or
     *   under the share (or it dies); ends then.
     * - `leave [spot]`: walk to the spot (default its fountain) and stay; never ends.
     * Each list ends in `stand` or `leave`: a hero is placed once it stands at its last step's point, and ready needs every
     * listed hero of its own team placed (no state is shared across teams: the other team's part is read from the facts).
     */
    setup: Record<string, string[]>;
    /**
     * Steps an own-team actor takes once the cast is released, in place of its setup (slice hit-back: the partner walks off
     * mid-hold). Also `wait <s>`: stand at its last setup point until s seconds after the release; ends then.
     */
    after?: Record<string, string[]>;
    ready: RigReady;
}

export interface Rig {
    /** `decision`: inputs forced, the choice read; `execution`: the choice forced, the doing read. */
    half: "decision" | "execution";
    /**
     * Named points: an anchor (`r:fountain`, `d:fountain`, `<r|d>:<top|mid|bot><1|2|3>` a tower, `<r|d>:front<top|mid|bot>`
     * that team's lane front, `GetLaneFrontLocation`, whose dx is a distance along the lane, negative towards that team's base)
     * and an offset. A front spot is resolved again at each rep's first frame.
     */
    spots: Record<string, [string, number, number]>;
    reps: RigRep[];
    /** Seconds from the rep's start for the ready checks to hold; else the rep is invalid. */
    timeout: number;
    /**
     * What runs for the cast after ready: its modes (the Gate names in the mode files, and `idle`: stand still,
     * at RIG_IDLE_DESIRE, when no released mode wants it), OHA's item use, OHA's ability use. A Valve built-in mode with
     * no mode file is not gated; `idle` holds against those seen so far, and `@drill_roles` `rel_modes` shows any that win.
     * `also` lists any of OHA's purchases, courier, buyback and level-ups the cast may use. Everything else gets desire 0 or is held. `Overrides.DrillHost = true` releases the cast's modes, items and abilities (the host-on step); purchases, courier, buyback and level-ups still follow `also`.
     */
    /** Kinds OHA keeps for every hero of the rig, in every phase (the rig's situation depends on them). */
    keeps?: HeldKind[];
    release: { modes: string[]; items?: boolean; abilities?: boolean; also?: HeldKind[] };
    /** The switch the rig tests (`Ours.<Name>`), off for the rig check (dotactl recipe `rig.override`). */
    switch: string;
    /** DotaTime seconds the rule's stage ends (a laning rule: 600). A rep ending after it is logged `rend` past `win` and the
     *  rig check leaves it out of the count: the rule does not run there, so the off arm cannot fail it. */
    window: number;
}

type Phase = "setup" | "released" | "invalid";

interface RigState {
    rep: number;
    start: number;
    /** Per pid: the step index, whether it stands on its last step at its point. */
    step: Record<number, number>;
    placed: Record<number, boolean>;
    phase: Record<number, Phase>;
    /** Per pid and item: the first and the last purchase attempt this rep. */
    bought: Record<number, Record<string, [number, number]>>;
    /** Per cast pid: the ready check failing at the last frame, logged when it changes (`ph=wait`). */
    waiting: Record<number, string>;
    /** Per cast pid: where its current idle spell stands, and the spell's last frame. */
    idleAt: Record<number, [Vector, number]>;
    /** Per cast pid: its HP share has been at or under the ready bar this rep. */
    hpMet: Record<number, boolean>;
    /** When this VM's cast was released this rep (`after` steps and `wait` read it). */
    releasedAt?: number;
    /** Per actor pid: the index into its `after` steps. */
    afterStep: Record<number, number>;
    /** Per attacker pid: the hero its attack step found, kept for the rep (hit-back fix2: the cast walked off its spot to hit back). */
    atk: Record<number, Unit>;
}

let rig: RigState | undefined;

const FRONT_LANES: Record<string, Lane> = { fronttop: Lane.Top, frontmid: Lane.Mid, frontbot: Lane.Bot };

/** Resolved rig spots by name, for the game (logged once each, `ph=spot`; a front spot once a rep). */
const rigSpots: Record<string, Vector | false | undefined> = {};

/** The hero key `r5` / `d3` of a bot, or undefined before its position is known. */
function keyOf(bot: Unit): string | undefined {
    const pos = LaneConfig.PositionOf(bot);
    return pos === undefined ? undefined : `${bot.GetTeam() === Team.Radiant ? "r" : "d"}${pos}`;
}

function rigOf(d: Entry | undefined): Rig | undefined {
    return d?.rig;
}

/** The rep kind for rep `n` (1-based). */
export function RigRepOf(n: number): RigRep | undefined {
    const r = rigOf(Active());
    if (r === undefined || r.reps.length === 0 || n <= 0) return undefined;
    return r.reps[(n - 1) % r.reps.length];
}

function rigState(): RigState | undefined {
    const d = Active();
    if (rigOf(d) === undefined) return undefined;
    const n = RepAt(DotaTime());
    if (n === 0) return undefined;
    if (rig === undefined || rig.rep !== n) {
        rig = { rep: n, start: d!.rep.from + (n - 1) * d!.rep.every, step: {}, placed: {}, phase: {}, bought: {}, waiting: {}, idleAt: {}, hpMet: {}, afterStep: {}, atk: {} };
        // Front spots are re-read now, on the rep's first frame, so both teams' VMs take the front at about the same moment.
        for (const name of Object.keys(rigOf(d)!.spots)) {
            if (FRONT_LANES[frontOf(name) ?? ""] === undefined) continue;
            rigSpots[name] = undefined;
            rigPoint(GetBot(), name);
        }
    }
    return rig;
}

/** A hero listed in the rig's setup that is not cast: an actor. */
function rigActor(d: Entry, bot: Unit): boolean {
    const k = keyOf(bot);
    if (k === undefined || d.rig === undefined) return false;
    return d.rig.reps.some(r => r.setup[k] !== undefined);
}

/** A rig's cast hero, before release or on an invalid rep: held, taking its own setup steps. */
function rigCastHeld(bot: Unit): boolean {
    const st = rigState();
    if (st === undefined) return rigOf(Active()) !== undefined;
    return st.phase[bot.GetPlayerID()] !== "released";
}

/** For a rig's cast after release: the modes it may run (undefined: not a rig cast, not released, or host on). */
function releasedModes(bot: Unit): Record<string, true> | undefined {
    const d = Active();
    const r = rigOf(d);
    if (r === undefined || RoleOf(bot) !== "cast" || overrides()?.["DrillHost"] === true) return undefined;
    const st = rigState();
    if (st === undefined || st.phase[bot.GetPlayerID()] !== "released") return undefined;
    const out: Record<string, true> = {};
    for (const m of r.release.modes) out[m] = true;
    return out;
}

/** What OHA's per-hero entry points do for a hero; `Owns` is asked once at the top of each. */
/** The kinds a rig entry can free by name; items and abilities are held through `Chooser.HoldsCasts` and freed only by `release`. */
export type HeldKind = "purchase" | "courier" | "buyback" | "levelup";
export type OwnedKind = HeldKind | "items" | "abilities";

/**
 * A rig owns its heroes (user 12/11/2026, rigA2: OHA spent the cast's 600 gold before each rep, so the salve buy failed):
 * true when OHA's code for `what` must not run for this hero. A rig's actors always; its cast until ready, and after ready
 * for every kind its release does not list (host-on frees only items and abilities: OHA's purchases would spend the gold the
 * next rep's `buy` needs). A kind the rig `keeps` is never owned. False for every other hero, in every other drill, and with no drill. Modes are
 * held through `RigDesire` (Chooser.Decide) instead.
 */
export function Owns(bot: Unit, what: OwnedKind): boolean {
    const r = rigOf(Active());
    if (r === undefined) return false;
    if (r.keeps !== undefined && r.keeps.indexOf(what as HeldKind) >= 0) return false;
    const role = RoleOf(bot);
    if (role === "actor") return true;
    if (role !== "cast") return false;
    if (rigCastHeld(bot)) return true;
    const host = overrides()?.["DrillHost"] === true;
    if (what === "items") return !host && r.release.items !== true;
    if (what === "abilities") return !host && r.release.abilities !== true;
    return r.release.also === undefined || r.release.also.indexOf(what) < 0;
}

/** Chooser.Decide: a rig cast after release gets desire 0 for every mode its release does not list. */
export function RigDesire(bot: Unit, mode: string): number | undefined {
    const m = releasedModes(bot);
    if (m === undefined || m[mode] === true) return undefined;
    // `idle` listed: farm (the bench's host) holds the cast standing, under the released modes' holds.
    return mode === "farm" && m["idle"] === true ? RIG_IDLE_DESIRE : 0;
}

/**
 * A released cast's desire for `idle` (farm mode, standing where it was released). Over the Valve built-in mode that took a
 * released cast nothing else wanted (fix6, 12/11/2026: mode 28 at 0.475, which no mode file gates), under the 0.95 at which
 * our retreat and the arbiter's hosts hold. `judgement`.
 */
const RIG_IDLE_DESIRE = 0.5;

/**
 * Farm Think for a released rig cast: while farm is not itself released it stands still (`idle`; Valve also keeps an
 * active mode at desire 0 for a few seconds, and OHA's farm Think ran then: fix6). False for anyone else.
 */
function rigIdle(bot: Unit): boolean {
    const m = releasedModes(bot);
    if (RoleOf(bot) !== "cast" || m === undefined || m["farm"] === true) return false;
    const st = rigState();
    if (st === undefined) return false;
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    // A new idle spell (none in the last second) stands where the cast is now, not where it was released.
    const last = st.idleAt[pid];
    if (last === undefined || now - last[1] > 1) st.idleAt[pid] = [bot.GetLocation(), now];
    else last[1] = now;
    standAt(bot, st.idleAt[pid][0]);
    return true;
}

/**
 * Chooser.HoldsCasts: for a rig cast after release, whether OHA's item use (`items`) or ability use waits; undefined when
 * the rig does not decide (not a rig cast, not released, or host on).
 */
export function RigHoldsCasts(bot: Unit, items: boolean): boolean | undefined {
    const r = rigOf(Active());
    if (r === undefined || releasedModes(bot) === undefined) return undefined;
    return Owns(bot, items ? "items" : "abilities");
}

const TOWER_IDS: Record<string, Tower> = {
    top1: Tower.Top1, mid1: Tower.Mid1, bot1: Tower.Bot1,
    top2: Tower.Top2, mid2: Tower.Mid2, bot2: Tower.Bot2,
    top3: Tower.Top3, mid3: Tower.Mid3, bot3: Tower.Bot3,
};

/** The `front<lane>` part of a spot's anchor, if it names a lane front. */
function frontOf(name: string): string | undefined {
    const s = rigOf(Active())?.spots[name];
    if (s === undefined) return undefined;
    const [, what] = string.match(s[0], "^([rd]):(%w+)$");
    return what;
}

/** The anchor plus offset a spot names, before it is made passable. */
function rawSpot(name: string): Vector | undefined {
    const s = rigOf(Active())?.spots[name];
    if (s === undefined) return undefined;
    const [anchor, dx, dy] = s;
    const [side, what] = string.match(anchor, "^([rd]):(%w+)$");
    if (side === undefined) return undefined;
    const team = side === "r" ? Team.Radiant : Team.Dire;
    const lane = FRONT_LANES[what];
    if (lane !== undefined) {
        // dx is along the lane here (negative: back towards that team's base), so the spot follows the lane's bend.
        const f = GetLaneFrontLocation(team, lane, dx);
        return Vector(f.x, f.y + dy, f.z);
    }
    if (what === "fountain") {
        const [x, y, z] = FOUNTAIN[team];
        return Vector(x + dx, y + dy, z);
    }
    const id = TOWER_IDS[what];
    if (id === undefined) return undefined;
    const tw = GetTower(team, id);
    if (tw === null || tw === undefined) return undefined;
    const a = tw.GetLocation();
    return Vector(a.x + dx, a.y + dy, a.z);
}

/** A spot off the walkable map moves to the nearest passable point on rings this far apart, up to RIG_SNAP_RINGS. `judgement`. */
const RIG_SNAP_STEP = 50;
const RIG_SNAP_RINGS = 20;

function passableNear(p: Vector): Vector | undefined {
    if (IsLocationPassable(p)) return p;
    for (let ring = 1; ring <= RIG_SNAP_RINGS; ring++) {
        const r = ring * RIG_SNAP_STEP;
        for (let k = 0; k < 16; k++) {
            const a = (k / 16) * 2 * math.pi;
            const q = Vector(p.x + r * math.cos(a), p.y + r * math.sin(a), p.z);
            if (IsLocationPassable(q)) return q;
        }
    }
    return undefined;
}

/** The distance from `p` to the nearest live tower of `team`, for the spot line. */
function nearestTower(team: Team, p: Vector): number {
    let best = math.huge;
    for (const k of Object.keys(TOWER_IDS)) {
        const tw = GetTower(team, TOWER_IDS[k]);
        if (tw === null || tw === undefined || !tw.IsAlive()) continue;
        const a = tw.GetLocation();
        best = math.min(best, math.sqrt((a.x - p.x) ** 2 + (a.y - p.y) ** 2));
    }
    return best;
}


/** A rig spot's point; `fountain` is the bot's own. Undefined for an unknown name, a dead anchor tower or no passable point. */
function rigPoint(bot: Unit, name: string): Vector | undefined {
    if (name === "fountain") {
        const [x, y, z] = FOUNTAIN[bot.GetTeam()];
        return Vector(x, y, z);
    }
    const known = rigSpots[name];
    if (known !== undefined) return known === false ? undefined : known;
    const raw = rawSpot(name);
    const p = raw !== undefined ? passableNear(raw) : undefined;
    rigSpots[name] = p ?? false;
    Telemetry.Event("drill", [
        ["ph", "spot"],
        ["name", Name()],
        ["spot", name],
        ["x", p !== undefined ? math.floor(p.x) : undefined],
        ["y", p !== undefined ? math.floor(p.y) : undefined],
        ["d", raw !== undefined && p !== undefined ? math.floor(math.sqrt((raw.x - p.x) ** 2 + (raw.y - p.y) ** 2)) : undefined],
        ["rt", p !== undefined ? math.floor(nearestTower(Team.Radiant, p)) : undefined],
        ["dt", p !== undefined ? math.floor(nearestTower(Team.Dire, p)) : undefined],
    ]);
    return p;
}

/**
 * A rig shares no state across teams: each team's bots may run in their own Lua VM (not verified; rig1, 12/11/2026, the Dire
 * actor waited all game on the Radiant cast's flag), so the other team is read only through the API (`attackTarget`, the
 * ready facts). Own-team heroes register here from their Tick.
 */
const rigUnits: Record<string, Unit> = {};

/** The unit of own-team hero key `r5` / `d3`, or undefined (another team's hero, or one that has not ticked yet). */
function heroOf(bot: Unit, key: string): Unit | undefined {
    const [side] = string.match(key, "^([rd])%d$");
    if (side === undefined || (side === "r" ? Team.Radiant : Team.Dire) !== bot.GetTeam()) return undefined;
    return rigUnits[key];
}

/** A hero counts as standing at its last step's point within this (it sways about 20 either side). `judgement`. */
const RIG_PLACED = 200;
/** An attacker that does not see its target walks to within this of the target's spot. `judgement` (inside night vision, 800). */
const RIG_APPROACH = 400;

/**
 * An attacker finds an enemy hero standing at a lane-front spot within this of its own reading of the spot: the two teams' VMs
 * read our lane front 250-370 apart (hit-back fix1). `judgement`; the cast's partner stands 250 behind it, farther from the
 * attacker's reading, which lies ahead of ours.
 */
const RIG_FIND_FRONT = 500;

/** The spot name of hero `key`'s last setup step this rep. */
function lastSpotName(st: RigState, key: string): string | undefined {
    const steps = RigRepOf(st.rep)?.setup[key];
    if (steps === undefined || steps.length === 0) return undefined;
    return steps[steps.length - 1].split(" ")[1];
}

/** The point of hero `key`'s last setup step this rep. */
function lastPoint(st: RigState, key: string, bot: Unit): Vector | undefined {
    const steps = RigRepOf(st.rep)?.setup[key];
    if (steps === undefined || steps.length === 0) return undefined;
    return rigPoint(bot, steps[steps.length - 1].split(" ")[1] ?? "fountain");
}

/**
 * The target of an attack step: an own-team hero by key once it stands at its last step's point; an enemy hero is the visible
 * one nearest that point within RIG_PLACED (rig2, 12/11/2026: OHA's position of an enemy hero is its estimate, 3 by default,
 * so the Dire actor never found the Radiant pos5 by position). Only the cast stands there; everyone else is benched.
 */
function attackTarget(bot: Unit, st: RigState, key: string): Unit | undefined {
    const p = lastPoint(st, key, bot);
    if (p === undefined) return undefined;
    const own = heroOf(bot, key);
    if (own !== undefined) return GetUnitToLocationDistance(own, p) <= RIG_PLACED ? own : undefined;
    let best: Unit | undefined;
    const spot = lastSpotName(st, key);
    let bestD = spot !== undefined && FRONT_LANES[frontOf(spot) ?? ""] !== undefined ? RIG_FIND_FRONT : RIG_PLACED;
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!h.IsAlive() || h.GetLocation() === undefined) continue;
        const d = GetUnitToLocationDistance(h, p);
        if (d <= bestD) {
            best = h;
            bestD = d;
        }
    }
    return best;
}

interface ShopBot extends Unit {
    ActionImmediate_PurchaseItem(name: string): number;
    ActionImmediate_SellItem(item: Item): void;
    DistanceFromFountain(): number;
}

/** Within this of its fountain a hero can buy and heals. `judgement` (the shop's reach is wider). */
const RIG_SHOP_REACH = 400;
/** A `buy` step gives up after this many seconds of tries (no gold, or the shop refuses). `judgement`. */
const RIG_BUY_SECS = 10;
/** `heal` ends at this HP share. `judgement`. */
const RIG_FULL_HP = 0.95;
/** A hero stands at a point within this. */
const RIG_AT = 100;

function hpShare(u: Unit): number {
    return u.GetHealth() / math.max(1, u.GetMaxHealth());
}

function holdsItem(bot: Unit, name: string): boolean {
    const slot = bot.FindItemSlot(name);
    return slot >= 0 && slot <= 8;
}

/** Stands at `p` as a statue does: a move order always on, swaying, so it never acquires a target. */
function standAt(bot: Unit, p: Vector): boolean {
    if (GetUnitToLocationDistance(bot, p) > RIG_AT) {
        bot.Action_MoveToLocation(p);
        return false;
    }
    const pid = bot.GetPlayerID();
    let side = statueSide[pid] ?? 1;
    let target = Vector(p.x + side * STATUE_SWAY * 0.5, p.y, p.z);
    if (GetUnitToLocationDistance(bot, target) < 15) {
        side = -side;
        statueSide[pid] = side;
        target = Vector(p.x + side * STATUE_SWAY * 0.5, p.y, p.z);
    }
    bot.Action_MoveToLocation(target);
    return true;
}

function atFountain(bot: Unit): boolean {
    const [x, y, z] = FOUNTAIN[bot.GetTeam()];
    const f = Vector(x, y, z);
    if (GetUnitToLocationDistance(bot, f) <= RIG_SHOP_REACH) return true;
    bot.Action_MoveToLocation(f);
    return false;
}

/** One step's order this frame; true when the step has ended (the next one starts). */
function rigStep(bot: Unit, st: RigState, step: string, last: boolean): boolean {
    const pid = bot.GetPlayerID();
    const words = step.split(" ");
    const verb = words[0];
    if (verb === "stand" || verb === "leave") {
        const p = rigPoint(bot, words[1] ?? "fountain");
        if (p === undefined) return false;
        standAt(bot, p);
        // Within RIG_PLACED, not standAt's 100: at a lane front the creeps shove a statue past 100 (hit-back fix1).
        st.placed[pid] = last && GetUnitToLocationDistance(bot, p) <= RIG_PLACED;
        return false;
    }
    if (verb === "wait") {
        const secs = tonumber(words[1]) ?? 0;
        if (st.releasedAt !== undefined && DotaTime() - st.releasedAt >= secs) return true;
        const p = lastPoint(st, keyOf(bot)!, bot);
        if (p !== undefined) standAt(bot, p);
        return false;
    }
    if (verb === "walk") {
        const p = rigPoint(bot, words[1]);
        if (p === undefined) return false;
        if (GetUnitToLocationDistance(bot, p) <= RIG_AT) return true;
        bot.Action_MoveToLocation(p);
        return false;
    }
    if (verb === "heal") {
        if (hpShare(bot) >= RIG_FULL_HP) return true;
        atFountain(bot);
        return false;
    }
    if (verb === "buy" || verb === "sell") {
        if (!atFountain(bot)) return false;
        const b = bot as ShopBot;
        const item = words[1];
        if (verb === "buy") {
            // Retried each second until held (fix4, 12/11/2026: rep 1's salve was not held at ready), giving up after
            // RIG_BUY_SECS: ready then fails `holds`.
            if (holdsItem(bot, item)) return true;
            const now = DotaTime();
            st.bought[pid] = st.bought[pid] ?? {};
            const tried = st.bought[pid][item];
            if (tried !== undefined && now - tried[0] >= RIG_BUY_SECS) return true;
            if (tried === undefined || now - tried[1] >= 1) {
                st.bought[pid][item] = [tried !== undefined ? tried[0] : now, now];
                const res = b.ActionImmediate_PurchaseItem(item);
                Telemetry.Event("drill", [["ph", "buy"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["step", item], ["res", tostring(res)], ["gold", bot.GetGold()]]);
            }
            return false;
        }
        for (let slot = 0; slot <= 8; slot++) {
            const it = bot.GetItemInSlot(slot);
            if (it !== null && it !== undefined && it.GetName() === item) b.ActionImmediate_SellItem(it);
        }
        return true;
    }
    if (verb === "attack") {
        // attack <hero> until hp <share>
        const share = tonumber(words[4]);
        if (share === undefined) return false;
        const kept = st.atk[pid];
        const target = kept !== undefined && !kept.IsNull() && kept.IsAlive() && kept.CanBeSeen() ? kept : attackTarget(bot, st, words[1]);
        if (target !== undefined) st.atk[pid] = target;
        if (target !== undefined && hpShare(target) <= share) return true;
        if (target === undefined) {
            // Not seen at its spot yet (still walking there, or in fog): go to that spot (fix3, 12/11/2026: a respawned
            // attacker that stood waiting in its fountain never saw the cast again).
            const p = lastPoint(st, words[1], bot);
            if (p !== undefined && GetUnitToLocationDistance(bot, p) > RIG_APPROACH) bot.Action_MoveToLocation(p);
            else bot.Action_MoveToLocation(bot.GetLocation());
            return false;
        }
        bot.Action_AttackUnit(target, true);
        return false;
    }
    return false;
}

/** A rig hero's setup this frame (cast before release, or an actor): runs its current step, moving on as steps end. */
function rigHold(bot: Unit): boolean {
    const st = rigState();
    const k = keyOf(bot);
    if (st === undefined || k === undefined) {
        // Before the first rep everyone in a rig waits in its fountain.
        atFountain(bot);
        return true;
    }
    const rr = RigRepOf(st.rep);
    const pid = bot.GetPlayerID();
    const after = rr?.after?.[k];
    if (after !== undefined && after.length > 0 && st.releasedAt !== undefined && RoleOf(bot) !== "cast") {
        for (let guard = 0; guard < after.length; guard++) {
            const i = st.afterStep[pid] ?? 0;
            const last = i >= after.length - 1;
            if (!rigStep(bot, st, after[i], last) || last) return true;
            st.afterStep[pid] = i + 1;
            Telemetry.Event("drill", [["ph", "after"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["i", i + 1], ["step", after[i + 1]]]);
        }
        return true;
    }
    const steps = rr?.setup[k];
    if (steps === undefined || steps.length === 0) {
        st.placed[pid] = true;
        atFountain(bot);
        return true;
    }
    // Several steps may end in one frame (buy, sell); a step that keeps the frame stops the loop.
    for (let guard = 0; guard < steps.length; guard++) {
        const i = st.step[pid] ?? 0;
        const last = i >= steps.length - 1;
        if (!rigStep(bot, st, steps[i], last) || last) return true;
        st.step[pid] = i + 1;
        Telemetry.Event("drill", [["ph", "step"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["i", i + 1], ["step", steps[i + 1]]]);
    }
    return true;
}

/** The first ready check that fails for the cast, or undefined when all hold. `setup`: a rig hero not yet on its last step. */
function failingCheck(bot: Unit, st: RigState, rr: RigRep): string | undefined {
    // Only the cast's own team's setup is read here (no state is shared across teams); the facts below read the rest.
    for (const k of Object.keys(rr.setup)) {
        const u = heroOf(bot, k);
        if (u !== undefined && st.placed[u.GetPlayerID()] !== true) return "setup";
    }
    const r = rr.ready;
    // Latched: once at or under the bar this rep it stays met, so regen while the attacker walks off cannot race it (fix5).
    if (r.hpAtMost !== undefined) {
        if (hpShare(bot) <= r.hpAtMost) st.hpMet[bot.GetPlayerID()] = true;
        else if (st.hpMet[bot.GetPlayerID()] !== true) return "hp";
    }
    for (const it of r.holds ?? []) if (!holdsItem(bot, it)) return "holds";
    for (const it of r.lacks ?? []) if (holdsItem(bot, it)) return "lacks";
    if (r.clear !== undefined || r.near !== undefined) {
        let nearest = math.huge;
        for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
            if (!h.IsAlive() || h.GetLocation() === undefined) continue;
            nearest = math.min(nearest, GetUnitToUnitDistance(bot, h));
        }
        if (r.clear !== undefined && nearest <= r.clear) return "clear";
        if (r.near !== undefined && nearest > r.near) return "near";
    }
    if (r.paid !== undefined) {
        const ours = bot.GetNearbyLaneCreeps(1600, false) ?? [];
        let hitters = 0;
        for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
            if (!h.IsAlive() || h.GetLocation() === undefined || !bot.WasRecentlyDamagedByHero(h, 1)) continue;
            hitters++;
            const at = h.GetLocation();
            if (!ours.some((c) => c.IsAlive() && GetUnitToLocationDistance(c, at) <= r.paid!)) return "paid";
        }
        if (hitters === 0) return "hit";
    }
    return undefined;
}

/** Per frame, a rig's cast: in setup, checks ready; logs `ph=ready` once per rep (ok=1, or ok=0 with the failing check at timeout). */
function rigTick(bot: Unit): void {
    const st = rigState();
    if (st === undefined) return;
    const pid = bot.GetPlayerID();
    if (st.phase[pid] === undefined) st.phase[pid] = "setup";
    if (st.phase[pid] !== "setup") return;
    const rr = RigRepOf(st.rep);
    const r = rigOf(Active());
    if (rr === undefined || r === undefined) return;
    const fail = failingCheck(bot, st, rr);
    const secs = DotaTime() - st.start;
    // Each change of the first failing check is logged, so a rep that times out shows what held it and when.
    if (fail !== undefined && st.waiting[pid] !== fail) {
        st.waiting[pid] = fail;
        Telemetry.Event("drill", [["ph", "wait"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["fail", fail], ["secs", math.floor(secs * 10 + 0.5) / 10], ["hp", math.floor(hpShare(bot) * 100 + 0.5) / 100]]);
    }
    if (fail !== undefined && secs < r.timeout) return;
    st.phase[pid] = fail === undefined ? "released" : "invalid";
    if (fail === undefined) st.releasedAt = DotaTime();
    Telemetry.Event("drill", [
        ["ph", "ready"],
        ["name", Name()],
        ["pid", pid],
        ["rep", st.rep],
        ["var", rr.name],
        ["ok", fail === undefined ? 1 : 0],
        ["fail", fail],
        ["secs", math.floor(secs * 10 + 0.5) / 10],
        ["hp", math.floor(hpShare(bot) * 100 + 0.5) / 100],
        ["rend", st.start + Active()!.rep.every],
        ["win", r.window],
        ["rel", r.release.modes.filter((m) => m !== "idle").join(",")],
    ]);
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
    if (name !== undefined && TABLE[name].rig !== undefined) {
        const k = keyOf(bot);
        if (k !== undefined) rigUnits[k] = bot;
    }
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
    if (rep === 0 || lastRep[team] === rep) {
        rigTick(bot);
        return;
    }
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
        ["var", RigRepOf(rep)?.name],
    ]);
    rigTick(bot);
}

/** Tests: forget the role and rep lines already logged. */
export function ResetCache(): void {
    for (const k of Object.keys(lastRep)) delete lastRep[k as unknown as number];
    for (const k of Object.keys(lastRole)) delete lastRole[k as unknown as number];
    for (const k of Object.keys(statueSide)) delete statueSide[k as unknown as number];
    for (const k of Object.keys(lastSpot)) delete lastSpot[k as unknown as number];
    for (const k of Object.keys(lingering)) delete lingering[k as unknown as number];
    for (const k of Object.keys(lingered)) delete lingered[k as unknown as number];
    for (const k of Object.keys(reachedBreak)) delete reachedBreak[k as unknown as number];
    for (const k of Object.keys(brokeOff)) delete brokeOff[k as unknown as number];
    removedLogged = false;
    rig = undefined;
    for (const k of Object.keys(rigUnits)) delete rigUnits[k];
    for (const k of Object.keys(rigSpots)) delete rigSpots[k];
}
