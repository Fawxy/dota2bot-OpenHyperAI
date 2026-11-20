/**
 * Kill switches for the decisions we have taken over from OHA (Customize.Ours). Each switch's OFF arm is OHA's own
 * decision. A Customize file without the block or the key gets DEFAULTS; Customize.Enable = false turns all of them off.
 */
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");

export const DEFAULTS = {
    /** Slice 3: pos4/pos5 leave a lane creep an allied core can take (Etiquette). */
    LeaveCoreCreep: true,
    /** Slice 4: the pos5 stacks its nearest camp on a placeholder trigger (StackJob). */
    StackExecute: true,
    /** Slice double-stack: the stack job hits a listed partner camp first, so one minute stacks two camps (StackJob). */
    DoubleStack: true,
    /** Slice job-chooser: while our job runs, OHA's modes outside the exceptions list cannot take the hero (Chooser). */
    JobChooser: true,
    /**
     * Slice 5: pos1-3 take lane last hits and denies through the laning state's body (states/core_last_hit). On by user
     * decision 02/11/2026 although ER-008/009/010 FAILed against OHA (share flat, more deaths): our code ends up enabled.
     */
    CoreLastHit: true,
    /**
     * Slice oha-trade (design 2026-11-19-trade-decision-design.md): the hero-on-hero exchange in lane is one decision (states/trade):
     * hit, hit back, kill and join for every laner our laning body holds (CoreLastHit or SupportDeny), the attack mode's desire and
     * Think in lane, team roam's fight branches, farm's ShouldRun and retreat's hold. Off: OHA's attack port, team roam's own fights,
     * farm's ShouldRun and no retreat hold.
     */
    Trade: true,
    /** Slice 5 re-run: with CoreLastHit on, false keeps the Dire cores on Valve's laning (Radiant only), so one side stays identical in both arms. */
    CoreLastHitDire: true,
    /** Slice l1-support-deny: pos4-5 go for every own creep they can deny, before anything else in lane (states/support_deny). */
    SupportDeny: true,
    /** With SupportDeny on, false keeps the Dire supports on OHA's deny (Radiant only), as CoreLastHitDire. */
    SupportDenyDire: true,
    /** Slice support-lane-hits: with SupportDeny on, the support's body also takes the last hits no allied core will take
     *  (states/lane_claims), in place of OHA's last hits; false keeps those OHA's (denies only, sub-switch for debugging). */
    SupportLastHit: true,
    /** User 06/11/2026 (bug-hunt mark 11): a core leaves a deny an allied support's laning body is in an attempt on and goes for
     *  the next last hit or deny (states/lane_claims DenyYield); false: a core takes every creep (sub-switch for debugging). */
    CoreDenyYield: true,
    /**
     * Slice pre-hit: with CoreLastHit on, a core hits an enemy creep our tower is attacking when the tower would otherwise take
     * it from above the core's kill range and one hit makes a window (states/pre_hit); false: the core only last-hits.
     */
    PreHit: true,
    /** Slice rune-rotation: pos4 to the 6:00 power rune and its 7:00 shrine, pos5 to the 6:00 rune when it has no stack (RuneJob). */
    RuneRotation: true,
    /** Slice rune-spawn: the team's 6:00 power rune (spot plan, hidden wait, timed walk, plays) and the 0:00 river bounty's
     *  pickup give-up (rune_pickup). Needs JobChooser and RuneRotation for the supports' side. */
    RuneSpawn: true,
    /** Slice support-lane: pos4/5 pull our wave into the lane's first pull camp when the lane push reading wants it (PullJob);
     *  the old camp-job pulls stop for those bots. Needs JobChooser. */
    SupportPull: true,
    /**
     * Slice lane-positioning: with CoreLastHit on, a pos1-3 stands on our lane spot (states/lane_spot: creep rings widened
     * below half HP, tower ring at every level, XP limit) instead of OHA's PositionTarget; since slice support-spot, with
     * SupportDeny on, a pos4-5 too, instead of OHA's PositionThink.
     */
    LaneSpot: true,
    /** With LaneSpot on, our own towers relax a core's creep rings in their range above 25% HP (states/lane_spot Cover): enemy
     *  creeps attacking something else there keep a small ring. Heroes are Safe.At's alone. Supports, and off: the open-lane rings. */
    LaneSpotTower: true,
    /**
     * Slice lane-aggro: an in-lane core (and a support whose lane core is away) draws enemy lane creeps on purpose
     * (lane_aggro): `feed` walks the enemy wave onto our ranged creep for our deny, `drag` walks a creep about to die away
     * from an enemy hero for a safe last hit. Off: no draws, and OHA-era lane_tech keeps its aggro pull.
     */
    LaneAggro: true,
    /**
     * With CoreLastHit on, a melee pos1-3 walks in from its lane spot (up to 2.5 s) for a last hit on a
     * creep dying inside one enemy hero's reach when the walk-in's HP price passes (states/contest), and walks back. Off: the
     * reach rule's 1 s walk for every laner.
     */
    CoreContest: true,
    /**
     * Slice core-in-lane: with CoreLastHit and LaneSpot on, an in-lane core whose wave is gone holds their incoming wave at the
     * lane's target point (states/wave_hold, lane_spot input `hold`), or under an enemy hero's threat with time to spare drags
     * it behind our T1 to our next wave (lane_aggro `back`, needs LaneAggro). Off: the spot ignores their walking wave.
     */
    CoreHold: true,
    /** Slice core-next-gold: with CoreLastHit and JobChooser on, an in-lane pos1-3 leaves for a camp of its own jungle when the
     *  lane forecast prices the camp above the lane gold lost while away (CoreCamp, a chooser job); FarmPattern starts no trip
     *  for it in the laning phase. */
    CoreCampTrip: true,
    /** Slice support-pull-farm: with SupportPull and JobChooser on, the support that pulled stays on the camp and clears the
     *  neutrals the wave left (PullFarm, a chooser job) when the site is safe, and gives the camp up to a core whose camp trip
     *  comes; a core may then price the pulled camp. Off: the support walks back to lane after its pull, a core never takes a
     *  pulled camp. */
    SupportPullFarm: true,
    /** Slice idle-swing (lane controller design s5.6): an owned laner with no last hit, deny or pre-hit on offer hits our lane
     *  creep below half HP that no enemy hero reaches before our hits kill it (states/idle_swing), both laners on one creep.
     *  Off: the laner stands. A forced shove (Overrides.ForceShove) does not need it. */
    PreDeny: true,
    /** Slice pick-safe (safe-here design): the lane creep pick does not take a creep whose hit place the shared safe read
     *  (safe_gather At) calls deadly, as it does not take a creep that is not its claim; a running attempt on one is released.
     *  Off: the pick has no danger check. */
    PickSafe: true,
    /** Slice lane-control 2a (lane controller design s5.1-s5.3): once per wave per team and lane, the controller's reading,
     *  mode, intent and chosen levers as ev=lane_ctl (lane_control); LaneControlDrive decides whether bots act on it. Off: no reading,
     *  no line and no driving. */
    LaneControl: true,
    /** Slice lane-control 2b (design s7 step 2b): under LaneControl, the controller's decision drives the levers: the idle
     *  swing's mode and setup, lane aggro's feed and the support's pull read it, each keeping its own gates. Off: shadow
     *  (2a), each lever on its own trigger. */
    LaneControlDrive: true,
    /** Slice lane-control 4a (design s5.7): the offlane pos3 may pull its hard camp when the controller names it (from 6:00
     *  first, before it only with the pos4 away or unable), with no enemy hero missing near the walk and the lane gold lost
     *  while away at most LaneControl CorePullWorth. Needs SupportPull and LaneControlDrive. Off: only supports pull. */
    CorePull: true,
    /** Slice threat (design docs/proposals/2026-11-09-fights-and-retreat.md s5.1-5.2): the missing-hero and visible-threat
     *  gates of the core camp trip, the offlane pos3's pull and the support's pull farm read Threat.Read (the missing belief, a
     *  weight per unseen hero by game minute, in place of a count) and log ev=threat. Off: CoreCamp MissingOf and ThreatOnWay. */
    Threat: true,
    /** Slice retreat (design s5.4, master slices/retreat.md): a laning bot hero's retreat is ours (retreat.ts: leave when
     *  Safe.At calls the place deadly, the anchor by route cost, the stop on a place Safe.At does not call deadly); OHA's retreat desire, farm's ShouldRun and the
     *  areas' retreat nudges are off for it, and every other hero in retreat mode takes the plain walk. Off: OHA's retreat
     *  and Valve's walk. */
    Retreat: true,
    /** Slice arbiter-shadow (design docs/proposals/2026-11-11-arbiter.md): per owned hero, the arbiter's pick as ev=arb beside
     *  Valve's active mode (arbiter.ts). Logging only, no desire changes. Off: no line. */
    ArbiterShadow: true,
    /** Rework step 7 (docs/proposals/2026-11-13-rework.md s7): the arbiter's pick holds every owned laner, from its first
     *  laning read to an end event; OHA's modes are ours, borrowed, admitted or denied by the inventory (chooser.ts Decide).
     *  Off: only the retreat episode and the running job hold, as before. */
    ArbiterDrive: true,
    /** Slice rune-verb (rework s7): under the 6:00 plan's switches, the mid's water spawns (2:00, 4:00) are its own trips, one
     *  per spawn (rune_job MidWants), and OHA's power and water branch stands aside for it until the plan takes over. Off: OHA's. */
    MidWater: false,
    /** Slice burst-cooldowns (D1, D2, D18): an enemy hero's estimated damage (the threat read's burst, the kill check's incoming
     *  damage, the pair join's and trade-free's kill shares) counts only the spells it can cast now (SpellReady.DamageOn).
     *  Off: Valve's estimate, which counts every learned enemy spell ready. */
    BurstReady: true,
    /** Sustain steps 3-5 (D6; design docs/proposals/2026-11-19-sustain-design.md): a held laner's heal and mana item use, its
     *  walk home (retreat's heal leave reads rule 2), its regen purchases and their courier delivery are sustain.ts Decide's,
     *  carried out by sustain_act.ts (use, step_out_use, give, home, buy, wait); OHA's item loop, roam's tango, lane-regen
     *  purchases, teleport home and courier skip that hero, and the support's pull supply asks it. Off: OHA's, the supply step's
     *  own rule, and retreat's heal floor sends the hero home. */
    Sustain: true,
    /** Plan after the collapse, variant D (an experiment): the safe read counts an enemy hero that is not hitting us over the
     *  walk out of every reacher's range plus `SafeGather.SETTINGS.ExitTurn`, not the full `KillWindow`. Off: `KillWindow`. */
    ExitWindow: true,
    /** Plan after the collapse step 1: while no enemy hero damaged us in `SafeGather.SETTINGS.PressWindow`, a held place is
     *  deadly under `Safe.BARS.idle` (1.0) of the kill line, not `stay` (1.25). Off: `stay` always (the safe read's and
     *  sustain's kill line both read `Inputs.pressed`). A switch for the checkpoint's deaths test (20/11/2026). */
    IdleBar: true,
    /** Step 4.3 (docs/proposals/2026-11-20-step4-exchanges.md): with Trade on, a hit or hit back opens only when its swing place is clear of
     *  enemy lane creeps (or our own attack order's cooldown covers it) or it still pays with their damage counted, and a fresh one only when no
     *  last hit or deny comes due before the swing lands; the executor orders the attack as answered. Off: the wave gates alone, and the
     *  executor steps out of the creeps before it orders. */
    TradeSwing: true,
    /** Step 4.4, narrowed (same proposal): a hit or hit back that has opened is not asked the favoured test again until its first attack has
     *  fired. Off: asked every frame. */
    TradeHold: true,
    /** Experiment (explore.ts): a hero our retreat owns draws a multiplier on its safe-read kill bar per fight episode and logs it as ev=roll,
     *  so the bar is fitted from outcomes. Off: no draw, every bar as it was. */
    ExploreRoll: false,
    /** Experiment (explore.ts): a hero in lane draws an aggression multiplier per 45 s block on the in-lane exchange's bars (favoured margin, kill HP
     *  share, `losing` end) and logs it as ev=roll kind=trade. Off: no draw, every bar as it was. */
    ExploreTrade: false,
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
