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
import { BotMode, DamageType, GameState, Item, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import Customize = require("bots/FunLib/custom_loader");
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as WorldFacts from "bots/FunLib/humaniser/world_facts";
import * as Sight from "bots/FunLib/humaniser/sight";
import * as Ours from "bots/FunLib/humaniser/ours";

/** What a hero does in a drill. `play`: everything, as in a normal game. */
/** `actor`: a hero a rig's setup scripts (it takes only those steps). */
/** `inlane`: plays everything, ours or OHA's, but nothing that leaves its lane (`InLaneDenies`, `ForbidsItem`, `forbidCast`). */
export type Role = "cast" | "bench" | "statue" | "sentry" | "chaser" | "laneonly" | "inlane" | "actor" | "play";

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
    /** Heroes that play in-lane: everything as in a game, ours or OHA's, but no mode, item or spell that leaves the lane (the
     *  lane ladder, master `docs/proposals/2026-11-19-lane-ladder.md`). A cast with `castInLane` is held the same way. */
    inLane?: Sides;
    /** The cast plays in-lane (as `inLane`). */
    castInLane?: boolean;
    /** The entry's `r` lists name our side and `d` theirs: swapped when `Ours.Team` scopes Dire, so one entry is played from
     *  both sides of the map (the ladder's rule: a rung is two games, sides swapped). Unscoped: as written. Only the role
     *  lists swap (cast, statue, sentry, chaser, laneOnly, inLane): `spots`, `castSpots` and rig sides stay as written. */
    sided?: boolean;
    /** Everyone not in `cast` or `statue`. */
    others: "bench" | "statue" | "laneonly" | "inlane" | "play";
    /** The cast plays lane-only (hold its spot, last-hit, deny; no techniques, harass, trades, spells or items). */
    castLaneOnly?: boolean;
    /** `statue`: the cast stands as a statue whenever its forced job (`forces`) does not run, so nothing but that job touches
     *  the lane (a pull drill's puller between pulls). Only the forced job is asked (`ForcedJob`). */
    castIdle?: "statue";
    /** The rep clock (DotaTime seconds): a rep every `every` from `from`; with `control` n, every nth rep withholds the
     *  input (`input=off`, the control in the same game); with `on` n, only reps 1, n + 1, 2n + 1 ... carry it and the
     *  rest withhold it (room for a forced action's effect to play out before the next). */
    rep: { every: number; from: number; control?: number; on?: number };
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
 * The sustain rig's tasks (D6, `Ours.Sustain`; master docs/proposals/2026-11-19-sustain-design.md, check 3): each forces one
 * answer's facts on one hero. The recipe sets every hero's HP to 20% at +63 s of each rep (`rig_hp_all`), a hero holding a
 * circlet to 5% (`rig_hp_holding`), one holding branches to 10% mana (`rig_mp_holding`), and every tango to one charge
 * (`rig_charges`), the last three for Radiant heroes only (team 2: the bench buys too): the marker items name the task to the server setters, which cannot read the bot's state. At 25% with no
 * enemy the kill line is the 30% floor (20% leaves a margin for the regen before release: fix1, a home hero at 25% stood at 30% when
 * released and bought instead of going home), so:
 * - `tango` / `salve` / `bottle`: what is in hand clears the line; rule 3 tops up (a tango at a tree, a salve stepped out
 *   or used where it stands, the bottle).
 * - `home`: nothing in hand, mana low: rule 2 sends it home at once (`low_both`), retreat walks it, it heals to 80%.
 * - `ship`: nothing in hand, mana full, gold and a free courier: rule 2 buys the cover and waits at the safe spot; our
 *   courier delivers it (design step 5, the call games had not proven before the smokes).
 * - `tango_ship`: one tango at 5%: the tango alone falls short, so it is eaten now and a salve shipped with it (`also`).
 * - `bottle_dry` (design step 6, not in the rotation yet): a bottle with no charges (`rig_charges item_bottle 0`); its
 *   answer (home for a refill, or hold for a rune) is step 6's to design; add it to SUSTAIN_ROTATION then.
 */
const SUSTAIN_HEALS = ["item_tango", "item_flask", "item_bottle", "item_clarity", "item_faerie_fire", "item_enchanted_mango"];
const SUSTAIN_MARKS = ["item_branches", "item_circlet"];
const SUSTAIN_ITEMS = [...SUSTAIN_HEALS, ...SUSTAIN_MARKS];
/** No enemy hero this near (none acts: every Dire hero is benched), so the safe-here read's kill is 0. */
const SUSTAIN_CLEAR = 1600;
/** The tree a tango walks to: within rule 3's idle walk (8 s there and back) with margin. `judgement`. */
const SUSTAIN_TREE = 600;
const SUSTAIN_TASKS: Record<string, { buy: string[]; ready: RigReady }> = {
    tango: {
        buy: ["item_tango"],
        ready: { hpAtMost: 0.25, holds: ["item_tango"], charges: { item_tango: [1, 1] }, clear: SUSTAIN_CLEAR, tree: SUSTAIN_TREE },
    },
    salve: { buy: ["item_flask"], ready: { hpAtMost: 0.25, holds: ["item_flask"], clear: SUSTAIN_CLEAR } },
    bottle: { buy: ["item_bottle"], ready: { hpAtMost: 0.25, holds: ["item_bottle"], charges: { item_bottle: [1, 3] }, clear: SUSTAIN_CLEAR } },
    home: { buy: ["item_branches"], ready: { hpAtMost: 0.25, mpAtMost: 0.2, holds: ["item_branches"], clear: SUSTAIN_CLEAR } },
    ship: { buy: [], ready: { hpAtMost: 0.25, mpAtLeast: 0.5, goldAtLeast: 200, courier: true, clear: SUSTAIN_CLEAR } },
    tango_ship: {
        buy: ["item_tango", "item_circlet"],
        ready: {
            hpAtMost: 0.1,
            mpAtLeast: 0.5,
            holds: ["item_tango", "item_circlet"],
            charges: { item_tango: [1, 1] },
            goldAtLeast: 200,
            courier: true,
            clear: SUSTAIN_CLEAR,
            tree: SUSTAIN_TREE,
        },
    },
    bottle_dry: { buy: ["item_bottle"], ready: { hpAtMost: 0.25, holds: ["item_bottle"], charges: { item_bottle: [0, 0] }, clear: SUSTAIN_CLEAR } },
};
/** The tasks the rig rotates through: rep k gives hero r(i+1) task (i + k) mod length (six kinds; a game's five reps meet five of them per hero). */
const SUSTAIN_ROTATION = ["tango", "salve", "bottle", "home", "ship", "tango_ship"];

/** One rep kind per rotation step: each hero sells what the last task left, heals, buys its task's items and stands at its own spot. */
function sustainReps(): RigRep[] {
    const reps: RigRep[] = [];
    for (let k = 0; k < SUSTAIN_ROTATION.length; k++) {
        const setup: Record<string, string[]> = {};
        const readyBy: Record<string, RigReady> = {};
        const tasks: Record<string, string> = {};
        for (let i = 0; i < 5; i++) {
            const key = `r${i + 1}`;
            const task = SUSTAIN_ROTATION[(i + k) % SUSTAIN_ROTATION.length];
            const t = SUSTAIN_TASKS[task];
            const own = t.ready.holds ?? [];
            setup[key] = ["heal", ...SUSTAIN_ITEMS.map((it) => `sell ${it}`), ...t.buy.map((it) => `buy ${it}`), `stand s${i + 1}`];
            readyBy[key] = { ...t.ready, lacks: SUSTAIN_ITEMS.filter((it) => own.indexOf(it) < 0) };
            tasks[key] = task;
        }
        reps.push({ name: `rot${k + 1}`, setup, ready: {}, readyBy, tasks });
    }
    return reps;
}

/**
 * The drill table. Names match dotactl's recipes.json `drills`. A slice whose drill has no entry adds it here (and a
 * recipe when it needs reset steps or a later `--until`).
 */
export const TABLE: Record<string, Entry> = {
    // The lone-hero stand (slice mid-stand, D11 against D1; the stand rule is `Safe.At` since oha-safe-behave; switch `Ours.Retreat`). half: execution. Facts the stand reads:
    // exactly one enemy hero in reach (forced: the Dire mid stands at a fixed point on its side of the mid river, everyone
    // else benched); it is not hitting the cast (a rig statue never attacks or casts); its estimated damage over 3 s is
    // between the old refusal bar and the cast's HP (forced: both mids at level 6 by the recipe with level-ups kept, so its
    // learned spells count in GetEstimatedDamageToTarget as in games; a statue at level 1 read 0.13 to 0.18; and the cast's HP
    // set to 70% about 3 s before each rep by the recipe, since at full HP the burst read 0.31 to 0.39, on the bar); the
    // cast at half HP or more. Seed 30 (lineup A): the cast Sniper (ranged, low HP), the statue Zeus (two nukes). The cast waits
    // behind the river on its side each rep, then lanes against natural waves with our retreat live. Read after release:
    // no `threat` retreat and the spot not refused on `burst` or `threat` (scratch readout until a view exists).
    "lane-stand": {
        note: "rig: Radiant pos2 behind the mid river, the Dire pos2 a statue across it (one hero in reach, not hitting, burst between 0.35 and 1 of the cast's HP at level 6, HP at half or more); then laning, retreat; HP set to 70% before each rep; 30 s reps from 1:00; seed 30",
        cast: { r: [2] },
        others: "bench",
        rep: { every: 30, from: 60 },
        rig: {
            half: "execution",
            switch: "Retreat",
            window: 600,
            spots: {
                home: ["r:mid1", 450, 450],
                foe: ["d:mid1", -550, -550],
            },
            timeout: 15,
            keeps: ["levelup"],
            release: { modes: ["laning", "retreat", "idle"] },
            reps: [{ name: "lone", setup: { r2: ["stand home"], d2: ["stand foe"] }, ready: { lone: [1700, 0.35, 1], hpAtLeast: 0.5 } }],
        },
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
    // Slice burst-truth (D1, D2: the burst read's truth). half: decision, a model graded on facts: what a lone enemy hero with
    // its spells ready deals in 3 s against the read (GetEstimatedDamageToTarget, `Threat.Read`'s burst; with every spell
    // castable the read's own figure; for an enemy the raw figure ignores cooldown and mana, so only the ready case is
    // checked). Our pos2 stands at hit-back's side spot off the bot lane at full HP (the burst is not cut short by its death)
    // and is released to `idle` only, so it neither leaves nor trades; the Dire pos2 heals (HP and mana), walks to its spot
    // (about 430 from the cast) and casts its listed unit-target spells and attacks for 6 s (`burst`). Our pos2 logs the read
    // and its HP every 0.25 s from ready (`trace`). Truth: the most HP lost in any 3 s. Seed 8 (lion against oracle); a seed
    // 30 control (sniper against zuus) is possible but was not run. Both mids level 4 (`--at "-1:00 dota_bot_give_level 3"`).
    // 120 s reps: one oracle cycle (walk in, burst, walk home, refill) took about 102 s, so 90 s reps (oracle2) drifted and
    // timed out reps 4 and 5.
    "burst-read": {
        note: "rig: Radiant pos2 at a side spot off our bot lane at full HP, the Dire pos2 bursts it from about 430 north for 6 s with its unit-target spells and attacks; the read and HP traced; 120 s reps from 0:30; seed 8",
        cast: { r: [2] },
        others: "bench",
        rep: { every: 120, from: 30 },
        rig: {
            half: "decision",
            switch: "BurstReady",
            window: 600,
            spots: {
                side: ["r:bot1", -2750, 700],
                foe: ["r:bot1", -2750, 1200],
            },
            timeout: 100,
            keeps: ["levelup"],
            release: { modes: ["idle"] },
            trace: 12,
            reps: [
                {
                    name: "burst",
                    setup: {
                        r2: ["heal", "stand side"],
                        d2: ["heal", "walk foe", "burst r2 for 6 using oracle_purifying_flames oracle_fortunes_end zuus_arc_lightning zuus_lightning_bolt", "leave"],
                    },
                    ready: { near: 1000, hpAtLeast: 0.9 },
                },
            ],
        },
    },
    // Slice rig-sight (proposal 2026-11-18-vision-tool step R): the harness's sight checks against the game, and calibration
    // data for a sight model (step M). No rule and no switch: the cast stands, released to `idle` only. The Dire pos4 stands
    // at one spot a rep, chosen from rig1's grids (18/11/2026): `open` in the lane corridor the cast sees, 500 north; `trees` a
    // walked point 800 north-west, in fog by day and night; `high` up one height step (level 4 to the cast's 2), fogged 700
    // west although open ground (rig1's first `open`); `far` 2,200 north, past the grid and also at level 4, so it mixes
    // distance with a height step. Rep 1 stays a `sees` rep: the actor walks from its fountain (seen at 47 s in rig2), past
    // `after`, which an `unseen` rep would pass with the actor still crossing the map. Read: each rep's ph=ready (ok, fail,
    // `sight`) against the actor's `ev=snap` position, and ph=grid (the team's sight around the cast, 100 apart). 60 s reps
    // from 0:00 to 10:00 hold day (to 5:00) and night; seed 8.
    "sight-probe": {
        note: "rig: Radiant pos1 standing off our bot lane; the Dire pos4 stands 500 north in the lane corridor (open, seen), 800 north-west behind trees (unseen), 700 west up a height step (high, unseen) or 2,200 north, also up a step (far, unseen); the team's sight grid logged at ready; 60 s reps from 0:00; seed 8",
        cast: SAFE_CORE,
        others: "bench",
        rep: { every: 60, from: 0 },
        rig: {
            half: "execution",
            switch: "none",
            window: 600,
            spots: {
                side: ["r:bot1", -2750, 700],
                open: ["r:bot1", -2730, 1200],
                trees: ["r:bot1", -3150, 1400],
                high: ["r:bot1", -3350, 700],
                far: ["r:bot1", -2750, 2900],
            },
            timeout: 50,
            release: { modes: ["idle"] },
            grid: [1600, 100],
            reps: [
                { name: "open", setup: { r1: ["stand side"], d4: ["stand open"] }, ready: { sees: ["d4"], after: 20 } },
                { name: "trees", setup: { r1: ["stand side"], d4: ["stand trees"] }, ready: { unseen: ["d4"], after: 20 } },
                { name: "far", setup: { r1: ["stand side"], d4: ["stand far"] }, ready: { unseen: ["d4"], after: 20 } },
                { name: "high", setup: { r1: ["stand side"], d4: ["stand high"] }, ready: { unseen: ["d4"], after: 20 } },
            ],
        },
    },
    "retreat-heal-items": {
        note: "rig: Radiant pos5 healed and handed a salve or a tango at its fountain, stood west of our bot T1 off the lane and away from camps, hit by the healed Dire pos3 to 25% (60% control); the attacker leaves for its fountain (or stays near); then only our retreat runs for it; four 135 s reps from 1:00, all inside the laning stage",
        cast: { r: [5] },
        others: "bench",
        rep: { every: 135, from: 60 },
        rig: {
            half: "decision",
            switch: "Sustain",
            window: 600,
            spots: {
                cast: ["r:bot1", -2750, 700],
                near: ["r:bot1", -2250, 700],
            },
            timeout: 95,
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
    // Sustain's execution rig (D6, design check 3; SUSTAIN_TASKS above): the five Radiant heroes, each at its own spot in our
    // jungle and base 4,000 to 6,000 from the fountain, off the lanes and 1,200 or more apart (rule 6 gives within 800); every
    // Dire hero benched. Each 108 s rep rotates the six tasks across the five heroes (six rep kinds), so one game has five
    // reps from 1:00 inside the laning stage and about four of each task. Released to laning (sustain's walks run in its
    // `sustain` row), retreat (the walk home) and idle; `release.sustain` frees our sustain's items, purchases and courier
    // (switch off: OHA's item use), every other kind stays the rig's. Read with tools/hlog/sustain_rig.js.
    sustain: {
        note: "rig: the five Radiant heroes, each at its own spot off the lanes, every Dire hero benched; each rep a rotation of six sustain tasks (tango, salve, bottle, home, ship, tango and ship) forced by items bought at the fountain and the recipe's HP, mana and charge setters; then laning, retreat and idle with our sustain's items, purchases and courier; 108 s reps from 1:00",
        cast: { r: [1, 2, 3, 4, 5] },
        others: "bench",
        rep: { every: 108, from: 60 },
        rig: {
            half: "execution",
            switch: "Sustain",
            window: 600,
            spots: {
                s1: ["r:bot3", 1350, 1300],
                s2: ["r:bot3", 2950, 1100],
                s3: ["r:top3", 1300, 1050],
                s4: ["r:top3", 2300, 1850],
                s5: ["r:mid3", 2850, 650],
            },
            timeout: 80,
            release: { modes: ["laning", "retreat", "idle"], sustain: true },
            // Sustain's walks (a tree, a step out, the wait for a delivery) and its item orders run only in the laning mode's `sustain`
            // row; the idle hold's standing order cancels them (fix1: every use answer held, none carried; the released heroes in
            // farm at 0.55 all rep). Under any laning bid, so the idle hold stands a hero only when laning does not want it. `judgement`.
            idle: 0.05,
            reps: sustainReps(),
        },
    },
    // The lane ladder (master docs/proposals/2026-11-19-lane-ladder.md, step C): one hero per lane, per side, playing its
    // full decision (ours or OHA's) in-lane: no mode, teleport or global spell that leaves the lane. `sided`: `r` is our
    // side (Ours.Team), so each rung is one entry played from both sides. Natural reps (each wave); 10:00 recipes.
    // Rungs 1 to 3 (last hits, denies, the wave and the camps): our pos 1-3, enemy creeps only.
    "ladder-solo": { note: "lane ladder rungs 1-3: our pos 1-3 in-lane, one per lane, everyone else benched", cast: { r: [1, 2, 3] }, others: "bench", castInLane: true, sided: true, rep: { every: 30, from: 0 } },
    // Rung 4: our side-lane supports alone (pos 5 safe, pos 4 off).
    "ladder-support": { note: "lane ladder rung 4: our pos 4 and 5 in-lane, alone in their side lanes, everyone else benched", cast: { r: [4, 5] }, others: "bench", castInLane: true, sided: true, rep: { every: 30, from: 0 } },
    // Rung 5: one against one per lane (our safe pos1 against their pos3, mid against mid, our pos3 against their pos1).
    // Symmetric, so `sided` does nothing; Ours.Team says which side is ours. The isolation check is this drill with every
    // Ours switch off on both sides.
    "ladder-duel": { note: "lane ladder rung 5: pos 1-3 of both sides in-lane, one against one per lane, everyone else benched", cast: { r: [1, 2, 3], d: [1, 2, 3] }, others: "bench", castInLane: true, rep: { every: 30, from: 0 } },
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
    // The pull rig with time for the pulled wave's fight to end (families proposal s5 step 2): only every other minute's wave is
    // pulled (1:00, 3:00 ...), so the camp is reset in the minute between (`--every "2:00@2:45 ent_fire npc_dota_creep_neutral
    // Kill" --every "2:00@2:52 dota_spawn_neutrals"`, set with `--set Overrides.Drill=pull-long`): in `pull` the :45 kill cut
    // the fight in 7 of 8 pulls with 3 to 5 of our creeps still at the camp (pullrig2, 23/11/2026). The :30 waves are the
    // control as in `pull`; the unpulled minute wave between walks past a camp still fighting.
    "pull-long": {
        note: "Radiant pos5 pulls every other minute's wave (1:00, 3:00 ...), a statue otherwise; the other waves unpulled; everyone else benched",
        cast: { r: [5] },
        others: "bench",
        castIdle: "statue",
        rep: { every: 30, from: 60, on: 4 },
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

/** For a `sided` entry under `Ours.Team` = Dire, the `r` lists are Dire's and the `d` lists Radiant's. */
function swapped(): boolean {
    return Active()?.sided === true && Ours.ScopedTeam() === Team.Dire;
}

function listed(s: Sides | undefined, team: Team, pos: number | undefined): boolean {
    if (s === undefined || pos === undefined) return false;
    const radiant = (team === Team.Radiant) !== swapped();
    const list = radiant ? s.r : s.d;
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
    if (listed(d.inLane, bot.GetTeam(), pos)) return "inlane";
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

/** In-lane: the cast of an entry with `castInLane`, or a hero listed in `inLane` or under `others: "inlane"`. */
export function InLane(bot: Unit): boolean {
    const r = RoleOf(bot);
    return r === "inlane" || (r === "cast" && Active()?.castInLane === true);
}

/**
 * Modes an in-lane hero may not take (Chooser.Gate's name): each takes a laner out of its lane or across the map (a rune
 * walk, a shop trip, a ward walk, Roshan, the team's gather). Push and defend of another lane are held too; of its own
 * lane they run (the wave is the hero's job). `roam` and `team_roam` run: in this fork they carry in-lane play (team
 * roam's last hits, lane fights and help within 2,200; roam's salve guard, tango and hero specials); roam's gank of
 * another lane is held at its choice (mode_roam_generic CheckLaneToGank asks `InLane`). `judgement`: the ladder's list
 * (proposal section 3, "Blocked across lanes"); the isolation view reads what still leaves.
 */
const OUT_OF_LANE: Record<string, true> = {
    rune: true,
    assemble: true,
    assemble_with_humans: true,
    roshan: true,
    outpost: true,
    secret_shop: true,
    side_shop: true,
    ward: true,
};
const LANE_SUFFIX: Record<string, Lane> = { top: Lane.Top, mid: Lane.Mid, bot: Lane.Bot };

/** Whether an in-lane hero's desire for `mode` (Chooser.Gate's name) is held at 0. */
export function InLaneDenies(bot: Unit, mode: string): boolean {
    if (Active() === undefined || !InLane(bot)) return false;
    if (OUT_OF_LANE[mode] === true) return true;
    const [kind, suffix] = string.match(mode, "^(%a+)_tower_(%a+)$");
    if (kind !== "push" && kind !== "defend") return false;
    const lane = LANE_SUFFIX[suffix as string];
    return lane !== undefined && lane !== (bot.GetAssignedLane() as Lane);
}

/** Items an in-lane hero never uses: a teleport leaves the lane. API item names. */
const TELEPORTS: Record<string, true> = { item_tpscroll: true, item_travel_boots: true, item_travel_boots_2: true };

/** Whether an in-lane hero's item use (OHA's ConsiderItemDesire loop) skips `item`. */
export function ForbidsItem(bot: Unit, item: string): boolean {
    return TELEPORTS[item] === true && Active() !== undefined && InLane(bot);
}

/**
 * Spells that reach other lanes, which no placement isolates; the drill forbids the cast and keeps the hero (user,
 * 19/11/2026). Ability names (API); the lineups' only global is Zeus's (lineup A). A hero with another global adds it here.
 */
const GLOBAL_SPELLS: Record<string, true> = { zuus_thundergods_wrath: true };

/** Whether an in-lane hero's cast of `ability` is refused at its desire (a hero file's hook: hero_zuus ConsiderR). */
export function ForbidsCast(bot: Unit, ability: string): boolean {
    return GLOBAL_SPELLS[ability] === true && Active() !== undefined && InLane(bot);
}

/** The backstop for a global spell no hero file's hook refuses: an in-lane hero in its cast point has its order cleared
 *  (each frame, from Tick) and logs `ph=forbid` at most once per 5 s (an episode, not a cast). A hero file that re-queues
 *  the spell every frame would loop here: a `forbid` line means that hero needs its own `ForbidsCast` hook. */
const forbidLogged: Record<number, number> = {};
function forbidCast(bot: Unit): void {
    if (!InLane(bot)) return;
    const a = bot.GetCurrentActiveAbility();
    if (a === null || GLOBAL_SPELLS[a.GetName()] !== true) return;
    bot.Action_ClearActions(true);
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    if (forbidLogged[pid] !== undefined && now - forbidLogged[pid] < 5) return;
    forbidLogged[pid] = now;
    Telemetry.Event("drill", [["ph", "forbid"], ["name", Name()], ["pid", pid], ["ability", a.GetName()]]);
}


/** An Overrides key the active drill implies, or undefined. */
export function Implied(key: string): unknown {
    return Active()?.overrides?.[key];
}

const FOUNTAIN: Record<number, [number, number, number]> = { [Team.Radiant]: [-6619, -6336, 384], [Team.Dire]: [6624, 6368, 392] };
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
        waitInFountain(bot);
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
    /** The cast's HP share at or over this (slice hit-back: the hold and D24 need half HP and more). */
    hpAtLeast?: number;
    /** Items the cast holds (inventory, one of each name). */
    holds?: string[];
    /** Items the cast does not hold. */
    lacks?: string[];
    /** No enemy hero within this distance of the cast. */
    clear?: number;
    /** An enemy hero within this distance of the cast. */
    near?: number;
    /** An enemy hero damaged the cast within the last second. */
    hit?: boolean;
    /**
     * Every enemy hero that damaged the cast within the last second stands this far past the cast's trade reach, [min, max]
     * (slice hit-back `far`: out of reach, inside the walk-in).
     */
    past?: [number, number];
    /** The cast's HP share at least this under that of an enemy hero that damaged it within the last second. */
    behind?: number;
    /**
     * The lone-hero stand's facts, [distance, low, high]: exactly one live enemy hero in sight within the distance (a
     * straight line, not the rule's walk; fogged heroes are not counted), nobody hit the cast in the last second, and that hero's estimated
     * damage over 3 s (GetEstimatedDamageToTarget, the call the threat read makes) is at least `low` and under `high` of
     * the cast's HP. Fails `lone`, `lonehit` or `burst`. The rule's tower and
     * `missing` conditions are neither forced nor checked.
     */
    lone?: [number, number, number];
    /**
     * The pair join's situation (D10), [ally, foe]: a hero of the cast's team within `ally` of the cast (the cast included)
     * damaged by an enemy hero within the last second, with another live one of ours within `ally` of it, and the enemy heroes
     * in sight within `foe` of it. Fails `pairhit` or `pairnone`.
     */
    pair?: [number, number];
    /**
     * With `pair`: our side's best kill share over 3 s (GetEstimatedDamageToTarget summed on one enemy hero, over its HP) beats
     * theirs on ours: the rule's weighing, kept in step with PairJoin.Decide by hand. Fails `ahead`.
     */
    ahead?: boolean;
    /**
     * The tower pre-hit's situation (K1, `Ours.PreHit`): an own tower within 1,200 of the cast attacking an enemy lane creep
     * within this distance of the cast (the pre-hit's TOWER_RADIUS and its walk). Fails `towercreep`.
     */
    towerCreep?: number;
    /**
     * The commit's reach (slice trade-reach, D19), [hp, min, max]: a live enemy hero in sight at this HP share or under stands
     * min to max past the cast's trade reach (`pastReach`). Fails `low`.
     */
    low?: [number, number, number];
    /** At least this many live enemy heroes in sight within 1,200 of the cast (the old trade's NEAR). Fails `foes`. */
    foes?: number;
    /** At most this many live enemy heroes in sight within 1,200 of the cast. Fails `foesmax`. */
    foesAtMost?: number;
    /** At most this many other live heroes of the cast's team within 1,200 of it. Fails `allies`. */
    alliesAtMost?: number;
    /**
     * Enemy hero keys (`d4`) the cast's team sees at their stand point: an enemy hero in sight within RIG_PLACED of it
     * (`rigSight` 1). Fails `sees`. A key of the cast's own team, or with no `stand` step, fails `sightkey`.
     */
    sees?: string[];
    /**
     * Enemy hero keys whose stand point is out of the cast's team's sight with no enemy hero seen within RIG_PLACED of it
     * (`rigSight` 0). The other team's placement is not read (no state crosses teams): the actor's `ev=snap` positions say
     * whether it stood there (`after` gives it time to walk). Fails `unseen`, or `sightkey` as `sees`.
     */
    unseen?: string[];
    /**
     * At least this many seconds from the rep's start: the time the other team's actors take to reach their spots, which the
     * cast cannot read when they are meant to be out of sight (`unseen`). Fails `early`.
     */
    after?: number;
    /** The cast's mana share at or under this, latched as `hpAtMost` (slice sustain-rig). Fails `mp`. */
    mpAtMost?: number;
    /** The cast's mana share at or over this. Fails `mplow`. */
    mpAtLeast?: number;
    /** The cast's gold at or over this. Fails `gold`. */
    goldAtLeast?: number;
    /** The cast's own courier alive and free (idle or at base, the state sustain's courier read takes). Fails `courier`. */
    courier?: boolean;
    /** A tree within this of the cast (GetNearbyTrees). Fails `tree`. */
    tree?: number;
    /** Per item: the charges of the cast's first one in slots 0-8, [min, max] (a bottle's, a tango's). Fails `charges`. */
    charges?: Record<string, [number, number]>;
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
     * - `wait <hero>`: hold until that hero of ours is placed, or an enemy hero is seen at that hero's stand; ends then.
     * - `heal`: its fountain until full HP and mana (95%); ends at once when already full.
     * - `burst <hero> for <secs> using <spell>...`: cast the listed unit-target spells on the hero as they come up, else
     *   attack it, for `secs` from the first order (`burstStep`); ends then.
     * - `buy <item>` / `sell <item>`: at its fountain (walks there first); ends when done.
     * - `attack <hero> until hp <share>`: once that hero stands on its last step, attack it until its HP share is at or
     *   under the share (or it dies); ends then. `attack <hero> from <d> until hp <share>`: first walk to `d` from it on
     *   the line it came in on, then attack from there (inside the attacker's range it does not step in).
     * - `leave [spot]`: walk to the spot (default its fountain) and stay; never ends.
     * - `stand <spot> until hp <share>`: a statue there until its own HP share is at or under the share; ends then.
     * - `front`: a statue at its last-hit place, behind its own lane front by its attack range (`lastHitPlace`), following
     *   the front; never ends. `lasthit`: as front, and it walks up to each enemy lane creep near the place that its next two
     *   hits kill, attacks it and walks back (`swingStep`). `hitback`: as lasthit, and it attacks an enemy hero that hits it
     *   (`answerStep`).
     * Each list ends in `stand`, `leave` or one of the three above: a hero is placed once it stands at its last step's point, and ready needs every
     * listed hero of its own team placed (no state is shared across teams: the other team's part is read from the facts).
     */
    setup: Record<string, string[]>;
    ready: RigReady;
    /** Per cast hero (`r1`): its own ready checks in place of `ready` (several casts, each on its own task: the sustain rig). */
    readyBy?: Record<string, RigReady>;
    /** Per cast hero: the task its setup forces, logged as `task=` on its ready line. */
    tasks?: Record<string, string>;
}

export interface Rig {
    /** `decision`: inputs forced, the choice read; `execution`: the choice forced, the doing read. */
    half: "decision" | "execution";
    /**
     * Named points: an anchor (`r:fountain`, `d:fountain`, `<r|d>:<top|mid|bot><1|2|3>` a tower) and an offset.
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
    /**
     * `sustain`: the regen owner runs for the released cast: with `Ours.Sustain` on, our sustain's heal and mana items, its
     * purchases and its courier deliveries (`RigFreesSustain`; OHA's item use, purchases and courier stay held); off, OHA's item
     * use (the before line: its rules on the same facts).
     */
    release: { modes: string[]; items?: boolean; abilities?: boolean; also?: HeldKind[]; sustain?: boolean };
    /**
     * The `idle` hold's desire for this rig (default RIG_IDLE_DESIRE). tower-prehit 0.3: laning bids 0.446 between due last
     * hits at level 7 or under before 9:00 and 0.369 at level 8 to 11 before 12:00, so the default 0.5 stood the cast still
     * beside creeps it could take (off3: the mid's 54 lost tower creeps in reach with no attempt), and 0.44 did from level 8
     * (off4: Sniper from 5:45, Luna from 8:18).
     */
    idle?: number;
    /** Seconds from ready the cast logs `ph=trace` (its HP and the read of the enemy heroes in sight) every RIG_TRACE_EVERY. */
    trace?: number;
    /**
     * [half-width, step]: at ready (ok or not) the cast logs `ph=grid`, IsLocationVisible over the square of that half-width
     * around it at that step (`Sight.VisionGridBox`'s `x0,y0,nx,ny,step,hex`): its team's sight, for fitting a sight model.
     */
    grid?: [number, number];
    /**
     * From release to the rep's end the cast logs `ph=atk` for each of its attacks fired at an enemy hero (`tpid`), and `ph=chit`
     * and `ph=hhit` for each attack an enemy lane creep or hero fires at it, with its damage (lane-trade: the view's truth of
     * what a trade did, read apart from the trade's own fields).
     */
    watch?: boolean;
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
    /** Per cast pid: its mana share has been at or under the ready bar this rep (`mpAtMost`). */
    mpMet: Record<number, boolean>;
    /** Per attacker pid: the hero its attack step found, kept for the rep (hit-back fix2: the cast walked off its spot to hit back). */
    atk: Record<number, Unit>;
    /** Per attacker pid: an `attack ... from <d>` step reached its distance this rep. */
    inPlace: Record<number, boolean>;
    /** Per burst actor pid: its first order this rep, the start of its current channel, each spell's last order. */
    burst: Record<number, { start: number; chan?: number; ordered: Record<string, number> }>;
    /** Per cast pid: when it was released, and its last trace line. */
    readyAt: Record<number, number>;
    tracedAt: Record<number, number>;
    /** Per `lasthit` actor pid: the creep it walks up to and the DotaTime it started. */
    swing: Record<number, { c: Unit; at: number }>;
    /** Per `hitback` actor pid: the hero it answers and the DotaTime that hero last hit it. */
    answer: Record<number, { h: Unit; at: number }>;
    /** Per watched cast pid: GameTime at its last watch frame, and its GetLastAttackTime then. */
    watchAt: Record<number, [number, number]>;
}

let rig: RigState | undefined;

/** Resolved rig spots by name, for the game (logged once each, `ph=spot`). */
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
        rig = { rep: n, start: d!.rep.from + (n - 1) * d!.rep.every, step: {}, placed: {}, phase: {}, bought: {}, waiting: {}, idleAt: {}, hpMet: {}, mpMet: {}, atk: {}, inPlace: {}, burst: {}, readyAt: {}, tracedAt: {}, swing: {}, answer: {}, watchAt: {} };
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
    // The sustain release's off arm: OHA's item use is the regen owner (the before line on the same facts).
    if (what === "items" && r.release.sustain === true && !Ours.On("Sustain")) return false;
    if (what === "items") return !host && r.release.items !== true;
    if (what === "abilities") return !host && r.release.abilities !== true;
    return r.release.also === undefined || r.release.also.indexOf(what) < 0;
}

/**
 * A released rig cast whose release names `sustain`, with the switch on: our sustain may use its heal and mana items, buy and
 * send its courier, which the rig otherwise owns (`Owns`). False for anyone else, in setup, and with the switch off.
 */
export function RigFreesSustain(bot: Unit): boolean {
    const r = rigOf(Active());
    if (r === undefined || r.release.sustain !== true || !Ours.On("Sustain") || RoleOf(bot) !== "cast") return false;
    return !rigCastHeld(bot);
}

/** Chooser.Decide: a rig cast after release gets desire 0 for every mode its release does not list. */
export function RigDesire(bot: Unit, mode: string): number | undefined {
    const m = releasedModes(bot);
    if (m === undefined || m[mode] === true) return undefined;
    // `idle` listed: farm (the bench's host) holds the cast standing, under the released modes' holds.
    return mode === "farm" && m["idle"] === true ? rigOf(Active())?.idle ?? RIG_IDLE_DESIRE : 0;
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

/** The anchor plus offset a spot names, before it is made passable. */
function rawSpot(name: string): Vector | undefined {
    const s = rigOf(Active())?.spots[name];
    if (s === undefined) return undefined;
    const [anchor, dx, dy] = s;
    const [side, what] = string.match(anchor, "^([rd]):(%w+)$");
    if (side === undefined) return undefined;
    const team = side === "r" ? Team.Radiant : Team.Dire;
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
    logSpot(name, p, raw !== undefined && p !== undefined ? math.floor(math.sqrt((raw.x - p.x) ** 2 + (raw.y - p.y) ** 2)) : undefined);
    return p;
}

/** The `ph=spot` line: where a spot resolved, how far it moved to be passable, and its nearest tower of each team. */
function logSpot(name: string, p: Vector | undefined, moved: number | undefined): void {
    Telemetry.Event("drill", [
        ["ph", "spot"],
        ["name", Name()],
        ["spot", name],
        ["x", p !== undefined ? math.floor(p.x) : undefined],
        ["y", p !== undefined ? math.floor(p.y) : undefined],
        ["d", moved],
        ["rt", p !== undefined ? math.floor(nearestTower(Team.Radiant, p)) : undefined],
        ["dt", p !== undefined ? math.floor(nearestTower(Team.Dire, p)) : undefined],
        ["hl", p !== undefined ? GetHeightLevel(p) : undefined],
    ]);
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

/** The point of hero `key`'s last setup step this rep. */
function lastPoint(st: RigState, key: string, bot: Unit): Vector | undefined {
    const steps = RigRepOf(st.rep)?.setup[key];
    if (steps === undefined || steps.length === 0) return undefined;
    // Where an attacker finds the hero: its last `stand` step's spot, else its last step's (pair-kill fix1: the flee Lich's
    // `stand low until hp 0.2, leave` sent the Warlock to its own fountain looking for it).
    for (let i = steps.length - 1; i >= 0; i--) {
        const w = steps[i].split(" ");
        if (w[0] === "stand" && w[1] !== undefined) return rigPoint(bot, w[1]);
    }
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
    let bestD = RIG_PLACED;
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
/** An `attack ... from <d>` step is in place within this past `d`. `judgement`. */
const RIG_FROM_SLACK = 50;

function hpShare(u: Unit): number {
    return u.GetHealth() / math.max(1, u.GetMaxHealth());
}

function holdsItem(bot: Unit, name: string): boolean {
    const slot = bot.FindItemSlot(name);
    return slot >= 0 && slot <= 8;
}

declare function GetCourier(n: number): Unit | undefined;
declare function GetCourierState(c: Unit): number;
declare const COURIER_STATE_IDLE: number;
declare const COURIER_STATE_AT_BASE: number;
interface TreeBot {
    GetNearbyTrees(radius: number): number[];
}

function mpShare(u: Unit): number {
    return u.GetMana() / math.max(1, u.GetMaxMana());
}

/** The charges of the hero's first `name` in slots 0-8; undefined when it holds none. */
function chargesOf(bot: Unit, name: string): number | undefined {
    for (let slot = 0; slot <= 8; slot++) {
        const it = bot.GetItemInSlot(slot);
        if (it !== null && it !== undefined && it.GetName() === name) return it.GetCurrentCharges() ?? 0;
    }
    return undefined;
}

/** The hero's own courier alive and free: idle or at base (sustain_gather's courier read). */
function courierFree(bot: Unit): boolean {
    for (let n = 0; n <= 4; n++) {
        const c = GetCourier(n);
        if (c === undefined || c === null || c.GetPlayerID() !== bot.GetPlayerID()) continue;
        const s = GetCourierState(c);
        return s === COURIER_STATE_IDLE || s === COURIER_STATE_AT_BASE;
    }
    return false;
}

/** The ready checks for this cast hero: its own (`readyBy`), else the rep's. */
function readyOf(bot: Unit, rr: RigRep): RigReady {
    const k = keyOf(bot);
    return (k !== undefined ? rr.readyBy?.[k] : undefined) ?? rr.ready;
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

/**
 * Where a held hero waits in its fountain: one slot per position, on an arc WAIT_RADIUS out from the fountain point toward
 * the map centre, WAIT_STEP radians apart (about 200 units; a slot snapped to passable ground may sit nearer its neighbour: Dire pos 1 is
 * about 95 from pos 3). lane-trade swingon/swingon2 (20/11/2026): since patch 7.42 the
 * Dire heroes spawn 400-700 out of the fountain, and every held one walked to the one fountain point; packed about 56 apart
 * against the fountain, the actors in the middle could not get out for the whole game. `judgement`.
 */
const WAIT_RADIUS = 350;
const WAIT_STEP = 0.6;
/** A waiting hero within this of its slot gets no new order. */
const WAIT_AT = 50;
const waitSlots: Record<string, Vector> = {};

/** The hero's waiting slot (by position; by player id before its position is known), snapped to passable ground. */
export function WaitSlot(bot: Unit): Vector {
    const team = bot.GetTeam();
    const n = LaneConfig.PositionOf(bot) ?? (bot.GetPlayerID() % 5) + 1;
    const key = `${team}:${n}`;
    const known = waitSlots[key];
    if (known !== undefined) return known;
    const [x, y, z] = FOUNTAIN[team];
    const len = math.sqrt(x * x + y * y);
    const ux = -x / len;
    const uy = -y / len;
    const a = (n - 3) * WAIT_STEP;
    const dx = math.cos(a) * ux - math.sin(a) * uy;
    const dy = math.cos(a) * uy + math.sin(a) * ux;
    const p = passableNear(Vector(x + WAIT_RADIUS * dx, y + WAIT_RADIUS * dy, z)) ?? Vector(x, y, z);
    waitSlots[key] = p;
    return p;
}

function waitInFountain(bot: Unit): void {
    const p = WaitSlot(bot);
    if (GetUnitToLocationDistance(bot, p) > WAIT_AT) bot.Action_MoveToLocation(p);
}

function atFountain(bot: Unit): boolean {
    const [x, y, z] = FOUNTAIN[bot.GetTeam()];
    const f = Vector(x, y, z);
    if (GetUnitToLocationDistance(bot, f) <= RIG_SHOP_REACH) return true;
    bot.Action_MoveToLocation(f);
    return false;
}

/**
 * A channelled spell is meant to be let go after this long, so the next order lands inside the 3 s. `judgement`. It did not
 * work in burst-read oracle2: Fortune's End's root landed 2.9 to 3.5 s after its order in every rep and no attack landed
 * during the channel, so the burst measured is a lower bound of what the hero can deal.
 */
const RIG_CHANNEL_SECS = 0.3;
/** A spell order is not repeated (nor logged) within this while its cast point runs. */
const RIG_REORDER_SECS = 0.5;

/**
 * `burst <hero> for <secs> using <spell>...`: from its first order, for `secs`, cast the first listed spell it holds that is
 * castable now on the hero (each a unit-target spell), else attack it; a channel runs RIG_CHANNEL_SECS before the next order.
 * Each spell order logs `ph=cast`. Ends after `secs`; before the hero is seen at its spot it walks there.
 */
function burstStep(bot: Unit, st: RigState, words: string[]): boolean {
    const pid = bot.GetPlayerID();
    const secs = tonumber(words[3]) ?? 0;
    const spells = words.slice(5);
    const now = DotaTime();
    const b = st.burst[pid];
    if (b !== undefined && now - b.start >= secs) return true;
    const kept = st.atk[pid];
    const target = kept !== undefined && !kept.IsNull() && kept.IsAlive() && kept.CanBeSeen() ? kept : attackTarget(bot, st, words[1]);
    if (target === undefined) {
        const p = lastPoint(st, words[1], bot);
        if (p !== undefined && GetUnitToLocationDistance(bot, p) > RIG_APPROACH) bot.Action_MoveToLocation(p);
        return false;
    }
    st.atk[pid] = target;
    const cur = b ?? { start: now, ordered: {} };
    st.burst[pid] = cur;
    if (bot.IsChanneling()) {
        cur.chan = cur.chan ?? now;
        if (now - cur.chan < RIG_CHANNEL_SECS) return false;
    } else {
        cur.chan = undefined;
        if (bot.IsCastingAbility()) return false;
    }
    for (const name of spells) {
        const a = bot.GetAbilityByName(name);
        if (a === undefined || a === null || a.IsNull() || a.GetLevel() <= 0 || !a.IsFullyCastable()) continue;
        const last = cur.ordered[name];
        if (last !== undefined && now - last < RIG_REORDER_SECS) return false;
        cur.ordered[name] = now;
        bot.Action_UseAbilityOnEntity(a, target);
        Telemetry.Event("drill", [["ph", "cast"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["spell", name], ["lvl", a.GetLevel()], ["s", math.floor((now - cur.start) * 100 + 0.5) / 100], ["mana", math.floor(bot.GetMana())], ["tgt", target.GetPlayerID()]]);
        return false;
    }
    bot.Action_AttackUnit(target, true);
    return false;
}

/**
 * lane-trade's last-hit place: this far behind its own lane front, less than its attack range, so a creep at the clash is in
 * reach. `judgement`.
 */
const LH_INSIDE = 50;
const LH_BACK_MIN = 100;
/** A `lasthit` actor walks up to one of the enemy's lane creeps within this of its place. `judgement`. */
const SWING_REACH = 800;
/** ... once its HP is at or under this many of the actor's hits on it (the walk takes about one). `judgement`. */
const SWING_HITS = 2;
/** A walk-up gives up after this long (the creep lives on, another hero took it). `judgement`. */
const SWING_SECS = 3;
/** A `hitback` actor answers a hero that damaged it within this, for ANSWER_KEEP after its last hit. `judgement`. */
const ANSWER_HIT = 0.5;
const ANSWER_KEEP = 2;
/** It does not chase past its attack range plus this from its place. `judgement`. */
const ANSWER_LEASH = 400;

/** Behind its own team's lane front of its lane by its attack range less LH_INSIDE (at least LH_BACK_MIN). */
function lastHitPlace(bot: Unit): Vector {
    const back = math.max(LH_BACK_MIN, bot.GetAttackRange() - LH_INSIDE);
    return GetLaneFrontLocation(bot.GetTeam(), bot.GetAssignedLane() as Lane, -back);
}

/**
 * `lasthit`: walk up to the lowest of the enemy's lane creeps within SWING_REACH of the place that SWING_HITS of its hits
 * kill and attack it until it dies (or SWING_SECS); true while it does. Each walk-up logs `ph=swing`.
 */
function swingStep(bot: Unit, st: RigState, place: Vector): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const cur = st.swing[pid];
    if (cur !== undefined) {
        if (!cur.c.IsNull() && cur.c.IsAlive() && now - cur.at < SWING_SECS) {
            if (bot.GetAttackTarget() !== cur.c) bot.Action_AttackUnit(cur.c, true);
            return true;
        }
        delete st.swing[pid];
        return false;
    }
    const dmg = bot.GetAttackDamage();
    let best: Unit | undefined;
    for (const c of bot.GetNearbyLaneCreeps(1600, true) ?? []) {
        if (c.IsNull() || !c.IsAlive() || c.GetLocation() === undefined || GetUnitToLocationDistance(c, place) > SWING_REACH) continue;
        if (c.GetHealth() > SWING_HITS * c.GetActualIncomingDamage(dmg, DamageType.Physical)) continue;
        if (best === undefined || c.GetHealth() < best.GetHealth()) best = c;
    }
    if (best === undefined) return false;
    st.swing[pid] = { c: best, at: now };
    Telemetry.Event("drill", [["ph", "swing"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["d", math.floor(GetUnitToUnitDistance(bot, best))]]);
    bot.Action_AttackUnit(best, true);
    return true;
}

/**
 * `hitback`: attack the enemy hero that damaged it within ANSWER_HIT, until ANSWER_KEEP after its last hit, while that hero
 * stays within its attack range + ANSWER_LEASH of the place; true while it does. Each answer logs `ph=answer`.
 */
function answerStep(bot: Unit, st: RigState, place: Vector): boolean {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const leash = bot.GetAttackRange() + ANSWER_LEASH;
    // A hitter past the leash is never answered, so its line is not logged frame after frame while its hit is recent.
    const hitter = (bot.GetNearbyHeroes(1600, true, BotMode.None) ?? []).find(
        (h) => h.IsAlive() && !h.IsIllusion() && bot.WasRecentlyDamagedByHero(h, ANSWER_HIT) && GetUnitToLocationDistance(h, place) <= leash,
    );
    if (hitter !== undefined) {
        if (st.answer[pid] === undefined) Telemetry.Event("drill", [["ph", "answer"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["tpid", hitter.GetPlayerID()], ["d", math.floor(GetUnitToUnitDistance(bot, hitter))]]);
        st.answer[pid] = { h: hitter, at: now };
    }
    const a = st.answer[pid];
    if (a === undefined) return false;
    const h = a.h;
    if (now - a.at > ANSWER_KEEP || h.IsNull() || !h.IsAlive() || !h.CanBeSeen() || GetUnitToLocationDistance(h, place) > leash) {
        delete st.answer[pid];
        return false;
    }
    // A walk-up to a creep gives way to the answer.
    delete st.swing[pid];
    if (bot.GetAttackTarget() !== h) bot.Action_AttackUnit(h, true);
    return true;
}

/** One step's order this frame; true when the step has ended (the next one starts). */
function rigStep(bot: Unit, st: RigState, step: string, last: boolean): boolean {
    const pid = bot.GetPlayerID();
    const words = step.split(" ");
    const verb = words[0];
    if (verb === "stand" || verb === "leave") {
        const p = rigPoint(bot, words[1] ?? "fountain");
        if (p === undefined) return false;
        // `stand <spot> until hp <share>`: a statue there until its own HP share is at or under the share; ends then.
        const until = verb === "stand" && words[2] === "until" ? tonumber(words[4]) : undefined;
        if (until !== undefined) {
            standAt(bot, p);
            return hpShare(bot) <= until;
        }
        standAt(bot, p);
        // Within RIG_PLACED, not standAt's 100: lane creeps can shove a statue past 100 (hit-back fix1).
        st.placed[pid] = last && GetUnitToLocationDistance(bot, p) <= RIG_PLACED;
        return false;
    }
    if (verb === "wait") {
        // pair-kill fix3: the Warlock hit the Lich low before Witch Doctor was back from healing or Omniknight had walked
        // in, and the Lich regenerated past the ready bar while they came.
        const own = heroOf(bot, words[1]);
        const done = own !== undefined ? st.placed[own.GetPlayerID()] === true : attackTarget(bot, st, words[1]) !== undefined;
        if (!done) bot.Action_MoveToLocation(bot.GetLocation());
        return done;
    }
    if (verb === "walk") {
        const p = rigPoint(bot, words[1]);
        if (p === undefined) return false;
        if (GetUnitToLocationDistance(bot, p) <= RIG_AT) return true;
        bot.Action_MoveToLocation(p);
        return false;
    }
    if (verb === "heal") {
        // Mana too (burst-truth: a burst actor's spells cost the rep before's mana, and an unhurt actor ended `heal` at once).
        if (hpShare(bot) >= RIG_FULL_HP && bot.GetMana() >= RIG_FULL_HP * bot.GetMaxMana()) return true;
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
    if (verb === "front" || verb === "lasthit" || verb === "hitback") {
        const p = lastHitPlace(bot);
        if (verb === "hitback" && answerStep(bot, st, p)) return false;
        if (verb !== "front" && swingStep(bot, st, p)) return false;
        standAt(bot, p);
        st.placed[pid] = last && GetUnitToLocationDistance(bot, p) <= RIG_PLACED;
        return false;
    }
    if (verb === "burst") return burstStep(bot, st, words);
    if (verb === "attack") {
        // attack <hero> [from <d>] until hp <share>
        const share = tonumber(words[words.length - 1]);
        if (share === undefined) return false;
        const from = words[2] === "from" ? tonumber(words[3]) : undefined;
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
        // Once at `from` it attacks from there for the rest of the step, even if the target walks in. Before that it also backs
        // off to `from` (on2: an attacker that arrived first, or stood beside the cast the rep before, hit from in reach).
        if (from !== undefined && st.inPlace[pid] !== true) {
            const t = target.GetLocation();
            const me = bot.GetLocation();
            const dd = math.max(1, math.sqrt((me.x - t.x) ** 2 + (me.y - t.y) ** 2));
            if (math.abs(dd - from) > RIG_FROM_SLACK) {
                const goal = passableNear(Vector(t.x + ((me.x - t.x) * from) / dd, t.y + ((me.y - t.y) * from) / dd, me.z));
                bot.Action_MoveToLocation(goal ?? t);
                return false;
            }
            st.inPlace[pid] = true;
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
        waitInFountain(bot);
        return true;
    }
    const rr = RigRepOf(st.rep);
    const pid = bot.GetPlayerID();
    const steps = rr?.setup[k];
    if (steps === undefined || steps.length === 0) {
        st.placed[pid] = true;
        waitInFountain(bot);
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

/** Enemy heroes that damaged the cast within the last second. */
function hitters(bot: Unit): Unit[] {
    return (GetUnitList(UnitType.EnemyHeroes) ?? []).filter((h) => h.IsAlive() && h.GetLocation() !== undefined && bot.WasRecentlyDamagedByHero(h, 1));
}

/**
 * How far `h` stands past the cast's trade reach: the old trade's reachOf for a core (attack range, both bounding radii, its
 * REACH of 100). Kept in step with it by hand: the drill does not import the behaviour it tests.
 */
function pastReach(bot: Unit, h: Unit): number {
    return GetUnitToUnitDistance(bot, h) - (bot.GetAttackRange() + bot.GetBoundingRadius() * 2 + 100);
}

/** The nearest hitter's distance past the cast's reach, for the wait and ready lines (undefined when nobody hit it). */
function nearestPast(bot: Unit): number | undefined {
    let best: number | undefined;
    for (const h of hitters(bot)) {
        const p = math.floor(pastReach(bot, h));
        if (best === undefined || p < best) best = p;
    }
    return best;
}

/**
 * `clear`: an enemy hero out of sight counts as gone only once its last sighting is farther than `clear`, or RIG_FOG_CLEAR s
 * old (on1 to on3 and r1: the attacker leaving stepped into fog 490 off, `clear` held at once and the cast's heal start read a
 * hero seen 0.3 s before). `judgement`: a 300-speed hero walks 1,600 in about 5.3 s.
 */
const RIG_FOG_CLEAR = 6;

/** An enemy hero not in sight whose last sighting is within `r` of `bot` and under RIG_FOG_CLEAR s old. */
function foggedWithin(bot: Unit, r: number): boolean {
    for (let pid = 0; pid <= 23; pid++) {
        const t = GetTeamForPlayer(pid);
        if (t === bot.GetTeam() || (t !== Team.Radiant && t !== Team.Dire) || !IsHeroAlive(pid)) continue;
        const info = GetHeroLastSeenInfo(pid)[0];
        if (info === undefined || info.time_since_seen >= RIG_FOG_CLEAR) continue;
        if (GetUnitToLocationDistance(bot, info.location) <= r) return true;
    }
    return false;
}

/** The spot of hero `key`'s last `stand` step this rep, or undefined when it has none (a `leave` names no point we can read). */
function standPoint(st: RigState, key: string, bot: Unit): Vector | undefined {
    const steps = RigRepOf(st.rep)?.setup[key] ?? [];
    for (let i = steps.length - 1; i >= 0; i--) {
        const w = steps[i].split(" ");
        if (w[0] === "stand" && w[1] !== undefined) return rigPoint(bot, w[1]);
    }
    return undefined;
}

/**
 * What the cast's team sees of enemy hero `key` at its stand point: 1 an enemy hero in sight within RIG_PLACED of it, 0 the
 * point out of sight (IsLocationVisible) and no enemy hero seen there, 2 the point in sight and nobody there (not placed yet,
 * or gone); undefined for a key of the cast's own team or one with no `stand` step.
 */
function rigSight(bot: Unit, st: RigState, key: string): number | undefined {
    const [side] = string.match(key, "^([rd])%d$");
    if (side === undefined || (side === "r" ? Team.Radiant : Team.Dire) === bot.GetTeam()) return undefined;
    const p = standPoint(st, key, bot);
    if (p === undefined) return undefined;
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (h.IsAlive() && h.GetLocation() !== undefined && h.CanBeSeen() && !h.IsIllusion() && GetUnitToLocationDistance(h, p) <= RIG_PLACED) return 1;
    }
    return IsLocationVisible(p) ? 2 : 0;
}

/** The ph=wait and ph=ready `sight` field: `key:rigSight` for each enemy key of the rep with a stand point, comma-separated. */
function sightField(bot: Unit, st: RigState, rr: RigRep): string | undefined {
    const out: string[] = [];
    for (const k of Object.keys(rr.setup).sort()) {
        const s = rigSight(bot, st, k);
        if (s !== undefined) out.push(`${k}:${s}`);
    }
    return out.length > 0 ? out.join(",") : undefined;
}

/** With exactly one live enemy hero in sight within `r` of the cast: its estimated damage over 3 s as a share of the cast's HP. */
function loneBurst(bot: Unit, r: number): number | undefined {
    let n = 0;
    let dmg = 0;
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!h.IsAlive() || h.GetLocation() === undefined || !h.CanBeSeen() || GetUnitToUnitDistance(bot, h) > r) continue;
        n += 1;
        dmg += h.GetEstimatedDamageToTarget(true, bot, 3, DamageType.All);
    }
    return n === 1 ? dmg / math.max(1, bot.GetHealth()) : undefined;
}

/** The first ready check that fails for the cast, or undefined when all hold. `setup`: a rig hero not yet on its last step. */
function failingCheck(bot: Unit, st: RigState, rr: RigRep): string | undefined {
    // Only the cast's own team's setup is read here (no state is shared across teams); the facts below read the rest.
    for (const k of Object.keys(rr.setup)) {
        const u = heroOf(bot, k);
        // Each cast waits for itself and the rig's actors, never for another cast (tower-prehit: one cast per lane).
        if (u !== undefined && st.placed[u.GetPlayerID()] !== true && (u.GetPlayerID() === bot.GetPlayerID() || RoleOf(u) !== "cast")) return "setup";
    }
    const r = readyOf(bot, rr);
    if (r.after !== undefined && DotaTime() - st.start < r.after) return "early";
    for (const k of r.sees ?? []) {
        const s = rigSight(bot, st, k);
        if (s === undefined) return "sightkey";
        if (s !== 1) return "sees";
    }
    for (const k of r.unseen ?? []) {
        const s = rigSight(bot, st, k);
        if (s === undefined) return "sightkey";
        if (s !== 0) return "unseen";
    }
    // Latched: once at or under the bar this rep it stays met, so regen while the attacker walks off cannot race it (fix5).
    if (r.hpAtMost !== undefined) {
        if (hpShare(bot) <= r.hpAtMost) st.hpMet[bot.GetPlayerID()] = true;
        else if (st.hpMet[bot.GetPlayerID()] !== true) return "hp";
    }
    if (r.hpAtLeast !== undefined && hpShare(bot) < r.hpAtLeast) return "hplow";
    if (r.mpAtMost !== undefined) {
        if (mpShare(bot) <= r.mpAtMost) st.mpMet[bot.GetPlayerID()] = true;
        else if (st.mpMet[bot.GetPlayerID()] !== true) return "mp";
    }
    if (r.mpAtLeast !== undefined && mpShare(bot) < r.mpAtLeast) return "mplow";
    for (const it of r.holds ?? []) if (!holdsItem(bot, it)) return "holds";
    for (const it of r.lacks ?? []) if (holdsItem(bot, it)) return "lacks";
    for (const [it, [lo, hi]] of Object.entries(r.charges ?? {})) {
        const c = chargesOf(bot, it);
        if (c === undefined || c < lo || c > hi) return "charges";
    }
    if (r.goldAtLeast !== undefined && bot.GetGold() < r.goldAtLeast) return "gold";
    if (r.courier === true && !courierFree(bot)) return "courier";
    if (r.tree !== undefined && ((bot as unknown as TreeBot).GetNearbyTrees(r.tree) ?? []).length === 0) return "tree";
    if (r.clear !== undefined || r.near !== undefined) {
        let nearest = math.huge;
        for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
            if (!h.IsAlive() || h.GetLocation() === undefined) continue;
            nearest = math.min(nearest, GetUnitToUnitDistance(bot, h));
        }
        if (r.clear !== undefined && (nearest <= r.clear || foggedWithin(bot, r.clear))) return "clear";
        if (r.near !== undefined && nearest > r.near) return "near";
    }
    if (r.hit === true || r.past !== undefined || r.behind !== undefined) {
        const hs = hitters(bot);
        if (hs.length === 0) return "hit";
        if (r.past !== undefined) {
            for (const h of hs) {
                const p = pastReach(bot, h);
                if (p < r.past[0] || p > r.past[1]) return "past";
            }
        }
        if (r.behind !== undefined && !hs.some((h) => hpShare(h) - hpShare(bot) >= r.behind!)) return "behind";
    }
    if (r.lone !== undefined) {
        const b = loneBurst(bot, r.lone[0]);
        if (b === undefined) return "lone";
        if (hitters(bot).length > 0) return "lonehit";
        if (b < r.lone[1] || b >= r.lone[2]) return "burst";
    }
    if (r.pair !== undefined) {
        const f = pairFacts(bot, r.pair[0], r.pair[1]);
        if (typeof f === "string") return f;
        if (r.ahead === true && !(f.ko > f.kt)) return "ahead";
    }
    if (r.towerCreep !== undefined) {
        // off4: the top T1 fell at 5:21 and every later rep failed `towercreep`; a dead tower is its own fault.
        if ((bot.GetNearbyTowers(1200, false) ?? []).length === 0) return "notower";
        if (!TowerOnCreep(bot, r.towerCreep)) return "towercreep";
    }
    if (r.low !== undefined || r.foes !== undefined || r.foesAtMost !== undefined || r.alliesAtMost !== undefined) {
        const [low, foes, allies] = LowFacts(bot, r.low);
        if (r.low !== undefined && !low) return "low";
        if (r.foes !== undefined && foes < r.foes) return "foes";
        if (r.foesAtMost !== undefined && foes > r.foesAtMost) return "foesmax";
        if (r.alliesAtMost !== undefined && allies > r.alliesAtMost) return "allies";
    }
    return undefined;
}

/**
 * RigReady `low` and `foes` (slice trade-reach): whether a live enemy hero in sight at `low[0]` HP share or under stands
 * `low[1]` to `low[2]` past the cast's trade reach, how many live enemy heroes in sight stand within 1,200 of it, and how many
 * other live heroes of its own team do.
 */
export function LowFacts(bot: Unit, low: [number, number, number] | undefined): LuaMultiReturn<[boolean, number, number]> {
    let found = false;
    let foes = 0;
    let allies = 0;
    for (const h of GetUnitList(UnitType.AlliedHeroes) ?? []) {
        if (h.GetPlayerID() === bot.GetPlayerID() || !h.IsAlive() || h.GetLocation() === undefined || h.IsIllusion()) continue;
        if (GetUnitToUnitDistance(bot, h) <= 1200) allies += 1;
    }
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!h.IsAlive() || h.GetLocation() === undefined || !h.CanBeSeen() || h.IsIllusion()) continue;
        if (GetUnitToUnitDistance(bot, h) <= 1200) foes += 1;
        if (low === undefined || hpShare(h) > low[0]) continue;
        const p = pastReach(bot, h);
        if (p >= low[1] && p <= low[2]) found = true;
    }
    return $multi(found, foes, allies);
}

/** An own tower within 1,200 of the bot is attacking an enemy lane creep within `d` of it (RigReady `towerCreep`). */
export function TowerOnCreep(bot: Unit, d: number): boolean {
    for (const tower of bot.GetNearbyTowers(1200, false) ?? []) {
        const t = tower.GetAttackTarget();
        if (t === undefined || t === null || t.IsNull() || !t.IsAlive()) continue;
        if (t.GetTeam() === bot.GetTeam() || !t.IsCreep() || t.IsHero()) continue;
        if (GetUnitToUnitDistance(bot, t) <= d) return true;
    }
    return false;
}

/**
 * The pair join's facts around the cast (RigReady `pair`): the hit hero of ours (the lowest HP share), ours within `ally` of
 * it and the enemy heroes in sight within `foe` of it, and both sides' best kill share over 3 s; or the failing check.
 */
function pairFacts(bot: Unit, ally: number, foe: number): { ko: number; kt: number; ours: number; theirs: number } | string {
    const live = (u: Unit) => !u.IsNull() && u.IsAlive() && u.GetLocation() !== undefined && !u.IsIllusion();
    const allies = (GetUnitList(UnitType.AlliedHeroes) ?? []).filter((u) => live(u));
    let hit: Unit | undefined;
    for (const a of allies) {
        if (GetUnitToUnitDistance(a, bot) > ally || !a.WasRecentlyDamagedByAnyHero(1)) continue;
        if (hit === undefined || hpShare(a) < hpShare(hit)) hit = a;
    }
    if (hit === undefined) return "pairhit";
    const ours = allies.filter((a) => GetUnitToUnitDistance(a, hit!) <= ally);
    if (ours.length < 2) return "pairnone";
    const theirs = (GetUnitList(UnitType.EnemyHeroes) ?? []).filter((e) => live(e) && e.CanBeSeen() && GetUnitToUnitDistance(e, hit!) <= foe);
    if (theirs.length === 0) return "pairhit";
    const share = (from: Unit[], on: Unit[]) => {
        let best = 0;
        for (const o of on) {
            let d = 0;
            for (const f of from) d += f.GetEstimatedDamageToTarget(true, o, 3, DamageType.All);
            best = math.max(best, d / math.max(1, o.GetHealth()));
        }
        return best;
    };
    return { ko: share(ours, theirs), kt: share(theirs, ours), ours: ours.length, theirs: theirs.length };
}

/** A `lone` rep's burst share for the wait and ready lines, two decimals (undefined otherwise, or with no lone hero). */
function burstField(bot: Unit, rr: RigRep): number | undefined {
    if (rr.ready.lone === undefined) return undefined;
    const b = loneBurst(bot, rr.ready.lone[0]);
    return b === undefined ? undefined : math.floor(b * 100 + 0.5) / 100;
}

const RIG_TRACE_EVERY = 0.25;
/** The trace's enemy heroes: in sight within this of the cast (the lone stand's reach). */
const RIG_TRACE_REACH = 1700;

type TracedUnit = Unit & { IsRooted?(): boolean };

/**
 * After ready, for `secs`, every RIG_TRACE_EVERY: the cast's HP and the read of the enemy heroes in sight within
 * RIG_TRACE_REACH, each one's GetEstimatedDamageToTarget(true, cast, 3, all) summed (`est`, HP), as the threat read calls
 * it; the nearest one's mana share; whether the cast is rooted (a bolt landed).
 */
function rigTrace(bot: Unit, st: RigState, secs: number): void {
    const pid = bot.GetPlayerID();
    const now = DotaTime();
    const from = st.readyAt[pid];
    if (from === undefined || now - from > secs) return;
    const last = st.tracedAt[pid];
    if (last !== undefined && now - last < RIG_TRACE_EVERY) return;
    st.tracedAt[pid] = now;
    let est = 0;
    let n = 0;
    let near: Unit | undefined;
    for (const h of GetUnitList(UnitType.EnemyHeroes) ?? []) {
        if (!h.IsAlive() || h.GetLocation() === undefined || !h.CanBeSeen() || GetUnitToUnitDistance(bot, h) > RIG_TRACE_REACH) continue;
        n += 1;
        est += h.GetEstimatedDamageToTarget(true, bot, 3, DamageType.All);
        if (near === undefined || GetUnitToUnitDistance(bot, h) < GetUnitToUnitDistance(bot, near)) near = h;
    }
    Telemetry.Event("drill", [
        ["ph", "trace"],
        ["name", Name()],
        ["pid", pid],
        ["rep", st.rep],
        ["s", math.floor((now - from) * 100 + 0.5) / 100],
        ["hp", bot.GetHealth()],
        ["mhp", bot.GetMaxHealth()],
        ["est", math.floor(est + 0.5)],
        ["n", n],
        ["foe", near?.GetUnitName()],
        ["fmana", near === undefined ? undefined : math.floor((near.GetMana() / math.max(1, near.GetMaxMana())) * 100 + 0.5) / 100],
        ["flvl", near?.GetLevel()],
        ["d", near === undefined ? undefined : math.floor(GetUnitToUnitDistance(bot, near))],
        ["root", (bot as TracedUnit).IsRooted?.() === true ? 1 : 0],
        ["alive", bot.IsAlive() ? 1 : 0],
    ]);
}

/** Enemy lane creeps within this of a watched cast are read for attacks on it (a ranged creep's reach and its walk). */
const WATCH_CREEPS = 900;

/**
 * Rig `watch`, per frame of a released cast: `ph=atk` when its GetLastAttackTime rose with an enemy hero its attack target;
 * `ph=chit` for each enemy lane creep attacking it whose GetLastAttackTime falls since the last frame, `ph=hhit` the same for an
 * enemy hero (all on GameTime's clock, so no creep handle need be kept between frames).
 */
function rigWatch(bot: Unit, st: RigState): void {
    const pid = bot.GetPlayerID();
    const now = GameTime();
    const mine = bot.GetLastAttackTime();
    const prev = st.watchAt[pid];
    st.watchAt[pid] = [now, mine];
    if (prev === undefined) return;
    if (mine > prev[1]) {
        const t = bot.GetAttackTarget();
        if (t !== undefined && t !== null && !t.IsNull() && t.IsHero() && t.GetTeam() !== bot.GetTeam()) {
            Telemetry.Event("drill", [["ph", "atk"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["tpid", t.GetPlayerID()], ["d", math.floor(GetUnitToUnitDistance(bot, t))]]);
        }
    }
    // `dmg`: the attack's damage after the cast's armour (GetAttackDamage is the attacker's mean), so the view can split the HP a
    // trade cost between creeps and the hero; an enemy hero's spells are not attacks and stay in the remainder.
    const hitOn = (u: Unit, ph: string, tpid?: number) => {
        if (u.IsNull() || !u.IsAlive() || u.GetAttackTarget() !== bot) return;
        const at = u.GetLastAttackTime();
        if (at <= prev[0] || at > now) return;
        Telemetry.Event("drill", [["ph", ph], ["name", Name()], ["pid", pid], ["rep", st.rep], ["tpid", tpid], ["dmg", math.floor(bot.GetActualIncomingDamage(u.GetAttackDamage(), DamageType.Physical) + 0.5)]]);
    };
    for (const c of bot.GetNearbyLaneCreeps(WATCH_CREEPS, true) ?? []) hitOn(c, "chit");
    for (const h of bot.GetNearbyHeroes(1600, true, BotMode.None) ?? []) if (!h.IsIllusion()) hitOn(h, "hhit", h.GetPlayerID());
}

/** Per frame, a rig's cast: in setup, checks ready; logs `ph=ready` once per rep (ok=1, or ok=0 with the failing check at timeout). */
function rigTick(bot: Unit): void {
    const st = rigState();
    if (st === undefined) return;
    const pid = bot.GetPlayerID();
    if (st.phase[pid] === undefined) st.phase[pid] = "setup";
    const r = rigOf(Active());
    if (st.phase[pid] === "released" && r?.trace !== undefined) rigTrace(bot, st, r.trace);
    if (st.phase[pid] === "released" && r?.watch === true) rigWatch(bot, st);
    if (st.phase[pid] !== "setup") return;
    const rr = RigRepOf(st.rep);
    if (rr === undefined || r === undefined) return;
    const fail = failingCheck(bot, st, rr);
    const secs = DotaTime() - st.start;
    // Each change of the first failing check is logged, so a rep that times out shows what held it and when.
    if (fail !== undefined && st.waiting[pid] !== fail) {
        st.waiting[pid] = fail;
        Telemetry.Event("drill", [["ph", "wait"], ["name", Name()], ["pid", pid], ["rep", st.rep], ["fail", fail], ["secs", math.floor(secs * 10 + 0.5) / 10], ["hp", math.floor(hpShare(bot) * 100 + 0.5) / 100], ["d", nearestPast(bot)], ["bu", burstField(bot, rr)], ["sight", sightField(bot, st, rr)]]);
    }
    if (fail !== undefined && secs < r.timeout) return;
    st.phase[pid] = fail === undefined ? "released" : "invalid";
    st.readyAt[pid] = DotaTime();
    Telemetry.Event("drill", [
        ["ph", "ready"],
        ["name", Name()],
        ["pid", pid],
        ["rep", st.rep],
        ["var", rr.name],
        ["task", rr.tasks?.[keyOf(bot) ?? ""]],
        ["ok", fail === undefined ? 1 : 0],
        ["fail", fail],
        ["secs", math.floor(secs * 10 + 0.5) / 10],
        ["hp", math.floor(hpShare(bot) * 100 + 0.5) / 100],
        ["mp", math.floor(mpShare(bot) * 100 + 0.5) / 100],
        ["d", nearestPast(bot)],
        ["bu", burstField(bot, rr)],
        ["rend", st.start + Active()!.rep.every],
        ["win", r.window],
        ["rel", r.release.modes.filter((m) => m !== "idle").join(",")],
        ["sight", sightField(bot, st, rr)],
        ["hl", GetHeightLevel(bot.GetLocation())],
    ]);
    if (r.grid !== undefined) {
        const at = bot.GetLocation();
        const [half, step] = r.grid;
        Telemetry.Event("drill", [
            ["ph", "grid"],
            ["name", Name()],
            ["pid", pid],
            ["rep", st.rep],
            ["var", rr.name],
            ["x", math.floor(at.x)],
            ["y", math.floor(at.y)],
            ["vg", Sight.VisionGridBox(at.x - half, at.y - half, at.x + half, at.y + half, step, at.z)],
            // The grid is the team's sight: the other sources a model of the cast's own must add (2,000 covers a tower's).
            ["vu", Sight.Viewers(at.x, at.y, half + 2000, bot)],
            ["vr", math.floor(bot.GetCurrentVisionRange())],
        ]);
    }
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
    if (d.rep.on !== undefined && d.rep.on > 0) return (n - 1) % d.rep.on !== 0;
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
    forbidCast(bot);
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
    for (const k of Object.keys(waitSlots)) delete waitSlots[k];
    for (const k of Object.keys(rigUnits)) delete rigUnits[k];
    for (const k of Object.keys(rigSpots)) delete rigSpots[k];
}
