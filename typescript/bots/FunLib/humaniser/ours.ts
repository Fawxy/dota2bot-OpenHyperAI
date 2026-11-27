/**
 * Kill switches for the decisions we have taken over from OHA (Customize.Ours). Each switch's OFF arm is OHA's own
 * decision. A Customize file without the block or the key gets DEFAULTS; Customize.Enable = false turns all of them off.
 * Every default is off (plan s7, agreed 23/11/2026): none of these has beaten the reference arm, so the default build is
 * the reference arm and a batch arm, drill or test that wants one names it. The exception is a small row (plan s5) merged on
 * as provisional after its audit; its own line is read at the next checkpoint batch and it is deleted there if not above zero:
 * RuneDetour, TowerStay, CreepSpells, FightFirst. A widening (plan s5: more heroes run a behaviour merged on) is merged on the same way after its firing audit, and is
 * deleted at that checkpoint if the behaviour's line or guards fall: SupportCreeps, AimedCasts.
 */
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");

export const DEFAULTS = {
    /** Slice 4: the pos5 stacks its nearest camp on a placeholder trigger (StackJob). */
    StackExecute: false,
    /** Slice double-stack: the stack job hits a listed partner camp first, so one minute stacks two camps (StackJob). */
    DoubleStack: false,
    /** Slice job-chooser: while our job runs, OHA's modes outside the exceptions list cannot take the hero (Chooser). */
    JobChooser: false,
    /** Slice rune-rotation: pos4 to the 6:00 power rune and its 7:00 shrine, pos5 to the 6:00 rune when it has no stack (RuneJob). */
    RuneRotation: false,
    /** Slice rune-spawn: the team's 6:00 power rune (spot plan, hidden wait, timed walk, plays) and the 0:00 river bounty's
     *  pickup give-up (rune_pickup). Needs JobChooser and RuneRotation for the supports' side. */
    RuneSpawn: false,
    /** The own bounty on a cheap detour, a row of the decider (rune_detour.ts, doctrine D26): a hero of ours out of its lane takes its
     *  own jungle's live bounty when the path by it adds about 12 s or less. Off: the pass is logged as a shadow and stock plays.
     *  On: provisional (plan s5's small row, merged after its audit; read at the next checkpoint batch). */
    RuneDetour: true,
    /** The whole-wave pull, a row of the decider (pull_job.ts, doctrine D17): the lane's pos5 (else pos4) pulls our wave into the
     *  lane's first pull camp when the pull's forecast wants it and the puller's record of the camp holds the bar (6
     *  neutrals), and stacks that camp in a minute the record is under it (stack_job.ts ROW; families proposal s5, lanecamp's
     *  stack-then-pull group). Off: both are logged as shadows and stock plays. On: it beat the reference arm on its line
     *  (oha-pull-row's batch pullstack1). */
    SupportPull: true,
    /** The lane's creeps, first group, a hard row of the decider (creep_row.ts, doctrine D11; no-creep-unpaid proposal s5): a core
     *  (pos 1 to 3) last-hits their ranged creep in the claimed cells (near, or a longer walk no enemy hero covers) once it is
     *  about to come due, whether or not stock is attacking it. Off: the read logs every offer as a shadow and stock plays.
     *  On: it beat the reference arm on its line (oha-creep-earlyhard's batches ceh1 and ceh2). */
    LaneCreeps: true,
    /** The lane's creeps, second kind, the deny, on the creep row (creep_row.ts, slice oha-creep-deny): a support (pos 4 and 5) denies
     *  our own lane creeps of every kind on the row's early go and hard hold, in the claimed cells bar `tower` and `given`. A core's
     *  denies stay Valve's. Off: the read logs the offers as shadows and stock plays. On: it beat the reference arm on its line (oha-creep-deny's batch cden1, cden1r). */
    CreepDeny: true,
    /** The lane's creeps, the under-tower hit, on the creep row (creep_row.ts, slice oha-tower-creeps; no-creep-unpaid proposal s6): a core
     *  last-hits their lane creep of any kind whose creep is inside our tower's attack range, as well as their ranged creep anywhere, and the
     *  `tower` refusal is lifted. Needs LaneCreeps. Off: the row takes their ranged creep outside our tower's range only. On: it beat the reference arm on its line (oha-tower-creeps' batch twc1). */
    TowerCreeps: true,
    /** The lane's creeps, a support's last hit, on the creep row (creep_row.ts, slice oha-support-creeps; no-creep-unpaid proposal s6a): a
     *  support (pos 4 and 5) last-hits their ranged creep when no hero with a lower `creep` cell has it (creep_row `FreeFor`), and yields
     *  it to one that starts on it before its swing; their ranged creep only, outside our tower's range (the under-tower hit is a core's).
     *  Needs LaneCreeps. Off: a support takes no last hit and stock plays. On: provisional (plan s5's widening, merged after its firing
     *  audit scraudit1; deleted at the next checkpoint batch if the line or guards fall). */
    SupportCreeps: true,
    /** The lane's creeps, the cast, on the creep row (creep_row.ts, slice oha-creep-spells; no-creep-unpaid proposal s6): a hero of ours at any
     *  position casts a unit-target spell on their lane creep of any kind that the attack cannot take, when the cast kills it now with no walk,
     *  the mana of the hero's dearest other key spell is kept, and a key spell also hits an enemy hero (SpellSecure.CastPick); the creep free of
     *  our claims and of a teammate's hit. Off: the cast pass runs as a shadow (`cw=off`) and stock plays. On: provisional (plan s5's small
     *  row, merged after its audit creep-spells_audit_A to _C); read at the next checkpoint batch and deleted there if not above zero. */
    CreepSpells: true,
    /** The cast's widening to aimed spells (creep_row.ts, slice oha-aimed-cast): with CreepSpells, a point spell is cast at its aim's point,
     *  a no-target spell around the hero as it stands, and one that lands in front of the hero (a raze) after the hero turns to the aim's
     *  facing; the same gates as the unit-target cast. Off: such a cast that passes them is logged `cw=aimoff` and unit-target casts only.
     *  On: provisional (plan s5's widening, merged after its firing audit aimaudit1); deleted at the next checkpoint batch if the line or
     *  guards fall. */
    AimedCasts: true,
    /** Slice oha-tower-fallthrough, a flag between two versions of our code: on, the leftover rule decides only whether to pre-hit, and
     *  a `none` verdict, a refused pre-hit or the tower leaving the creep falls through to the plain last hit. Off: the rule ends the
     *  attempt there. Both log the rule's first refusal mid-attempt (`tl`, `tlt`, `tlc`). On: provisional (plan s5's small row); read at
     *  the next checkpoint batch against an arm with it off and every other switch on, and the flag deleted there either way. */
    TowerStay: true,
    /** The draw (protective aggro), a decider row (aggro_row.ts, slice oha-lane-aggro; no-creep-unpaid proposal s6b): a core (pos 1 to 3)
     *  beside our ranged creep while their lane creeps fight ours gives one attack order on the nearest enemy hero our team sees and walks
     *  back past our ranged creep, so the drawn creeps take it when the draw lets go. Off: the read logs every chance as a shadow and
     *  stock plays. Off until its batch: the on arm sets it; deleted if it does not beat the reference arm. */
    LaneAggro: false,
    /** Slice oha-no-start-over-fight (offers-and-the-decider s10, slice A), a flag between two versions of our code: on, the decider
     *  refuses to begin any row while Valve has the hero in attack, roam or team roam (fights stay Valve's; a row already holding is not
     *  cut), and the row reads the refusal (`Decider.Refusal`: the creep row notes `fight`, the pull and stack take it as the slot's
     *  reason). Off: a row begins from any mode. On: provisional (user 27/11/2026: the check before the batch could not read its
     *  line at 6 pairs); read at the next checkpoint batch against ckpt3, and the flag deleted there either way. */
    FightFirst: true,
    /** Slice threat (design docs/proposals/2026-11-09-fights-and-retreat.md s5.1-5.2): the missing-hero and visible-threat
     *  gates of the jobs' trip read (SafeGather.TripGate) read Threat.Read (the missing belief, a
     *  weight per unseen hero by game minute, in place of a count) and log ev=threat. */
    Threat: false,
    /** Slice retreat (design s5.4, master slices/retreat.md): a laning bot hero's retreat is ours (retreat.ts: leave when
     *  Safe.At calls the place deadly, the anchor by route cost, the stop on a place Safe.At does not call deadly); OHA's retreat desire, farm's ShouldRun and the
     *  areas' retreat nudges are off for it, and every other hero in retreat mode takes the plain walk. Off: OHA's retreat
     *  and Valve's walk. */
    Retreat: false,
    /** Slice rune-verb (rework s7): under the 6:00 plan's switches, the mid's water spawns (2:00, 4:00) are its own trips, one
     *  per spawn (rune_job MidWants), and OHA's power and water branch stands aside for it until the plan takes over. Off: OHA's. */
    MidWater: false,
    /** Slice burst-cooldowns (D1, D2, D18): an enemy hero's estimated damage (the threat read's burst, the kill check's incoming
     *  damage, the pair join's and trade-free's kill shares) counts only the spells it can cast now (SpellReady.DamageOn).
     *  Off: Valve's estimate, which counts every learned enemy spell ready. */
    BurstReady: false,
    /** Sustain steps 3-5 (D6; design docs/proposals/2026-11-19-sustain-design.md): a held laner's heal and mana item use, its
     *  walk home (retreat's heal leave reads rule 2), its regen purchases and their courier delivery are sustain.ts Decide's,
     *  carried out by sustain_act.ts (use, step_out_use, give, home, buy, wait); OHA's item loop, roam's tango, lane-regen
     *  purchases, teleport home and courier skip that hero, and the support's pull supply asks it. Off: OHA's, the supply step's
     *  own rule, and retreat's heal floor sends the hero home. */
    Sustain: false,
    /** Plan after the collapse, variant D (an experiment): the safe read counts an enemy hero that is not hitting us over the
     *  walk out of every reacher's range plus `SafeGather.SETTINGS.ExitTurn`, not the full `KillWindow`. Off: `KillWindow`. */
    ExitWindow: false,
    /** Plan after the collapse step 1: while no enemy hero damaged us in `SafeGather.SETTINGS.PressWindow`, a held place is
     *  deadly under `Safe.BARS.idle` (1.0) of the kill line, not `stay` (1.25). Off: `stay` always (the safe read's and
     *  sustain's kill line both read `Inputs.pressed`). A switch for the checkpoint's deaths test (20/11/2026). */
    IdleBar: false,
    /** Step 4.2a (docs/proposals/2026-11-20-step4-exchanges.md), the read half: an enemy tower is a row in the safe read's kill line (its damage
     *  on us from when it would be on us to the end of the kill window), not a flat `deadly tower`. Off: the flat rule. */
    TowerRead: false,
    /** Plan after the collapse step 5, group 1 (docs/proposals/2026-11-20-after-the-collapse.md): a chooser job's start asks the safe read here
     *  (and a rune trip's walk) with no HP floor or hit timer of its own, except a job with no price for a camp's neutrals (the stack); a running
     *  job ends on a deadly answer here; the core camp's start has no HP floor. Off: the floors (0.5, 0.65) and the 3 s hit timer. */
    TripRead: false,
    /** Shadow choice line (choice_shadow.ts, 22/11/2026): per hero of ours, ev=choice kind=shadow ~1 Hz and on each change of
     *  active mode: each OHA mode's own desire as the one real call returned it, OHA's argmax, the mode Valve picked and the module of
     *  ours that made the difference. Logging only: the gate's return values and OHA's calls are unchanged. Off: no line. */
    ChoiceShadow: false,
};

export type Feature = keyof typeof DEFAULTS;

/** Every switch's value as `Name:1|0` in name order (telemetry: which arm a game ran when no --set shows it). */
export function Describe(): string {
    const names: string[] = [];
    for (const name in DEFAULTS) names.push(name);
    names.sort();
    return names.map((n) => `${n}:${On(n as Feature) ? 1 : 0}`).join(",");
}

/**
 * Customize.Ours.Team (head-to-head scope): "radiant" or "dire" (any case) or 2 or 3 turns every Ours switch off on the other
 * team, whose contexts then run OHA's path. It scopes the Ours switches only: the older humaniser features under
 * Customize.Humaniser still run on both teams, so the other side is OHA as hosted with those on (eval-run, "Stage-close
 * head-to-head"). Unset or any other value: both teams. The two teams run in separate VMs, each knowing its own GetTeam().
 */
export function ScopedTeam(): number | undefined {
    const scope = (Customize.Ours as unknown as { Team?: unknown } | undefined)?.Team;
    if (scope === 2 || scope === 3) return scope;
    if (typeof scope !== "string") return undefined;
    const name = scope.toLowerCase();
    return name === "radiant" ? 2 : name === "dire" ? 3 : undefined;
}

function OtherTeamScoped(): boolean {
    const team = ScopedTeam();
    return team !== undefined && GetTeam() !== team;
}

export function On(feature: Feature): boolean {
    if (Customize.Enable === false) return false;
    if (OtherTeamScoped()) return false;
    const value = Customize.Ours?.[feature];
    if (value === undefined || value === null) return DEFAULTS[feature];
    return value === true;
}
