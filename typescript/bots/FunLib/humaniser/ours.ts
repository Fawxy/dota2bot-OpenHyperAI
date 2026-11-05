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
     * Slice core-in-lane: with CoreLastHit on, the core's attack mode is ours in lane (trades, states/core_trade) and OHA's Lua
     * port outside it; false leaves Valve's attack mode (sub-switch for debugging).
     */
    CoreTrade: true,
    /** Slice 5 re-run: with CoreLastHit on, false keeps the Dire cores on Valve's laning (Radiant only), so one side stays identical in both arms. */
    CoreLastHitDire: true,
    /** Slice l1-support-deny: pos4-5 go for every own creep they can deny, before anything else in lane (states/support_deny). */
    SupportDeny: true,
    /** With SupportDeny on, false keeps the Dire supports on OHA's deny (Radiant only), as CoreLastHitDire. */
    SupportDenyDire: true,
    /** Slice support-lane-hits: with SupportDeny on, the support's body also takes the last hits no allied core will take
     *  (states/lane_claims), in place of OHA's last hits; false keeps those OHA's (denies only, sub-switch for debugging). */
    SupportLastHit: true,
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
    /** Slice pull-half: with SupportPull on, the safe-lane pos5 half-pulls (the neutrals reach the meet point after the wave's
     *  body, so only its back creeps turn) when the lane holds on their half, and full-pulls when it pushes out; false: full
     *  pulls only. */
    SupportHalfPull: true,
    /**
     * Slice lane-positioning: with CoreLastHit on, a pos1-3 stands on our lane spot (states/lane_spot: creep rings widened
     * below half HP, tower ring at every level, XP limit) instead of OHA's PositionTarget; since slice support-spot, with
     * SupportDeny and SupportHarass on, a pos4-5 too, instead of OHA's PositionThink.
     */
    LaneSpot: true,
    /**
     * Slice support-spot: with SupportDeny on, a pos4-5's attack mode is ours in lane (harass through states/core_trade, the
     * aggro-free plan) and OHA's Lua port outside it, and with LaneSpot on the support stands on our lane spot (a support_lane
     * step) instead of OHA's PositionThink; false leaves both OHA's and Valve's.
     */
    SupportHarass: true,
    /** With LaneSpot on, our own towers relax a core's spot limits in their range above 25% HP (states/lane_spot Cover): enemy
     *  creeps attacking something else there keep a small ring, enemy heroes our tower would punish a short reach. Supports,
     *  and off: the open-lane limits. */
    LaneSpotTower: true,
    /**
     * Slice lane-fight: with CoreLastHit and CoreTrade on, an in-lane pos1-3's fights are ours (states/core_trade): it commits on
     * a target at 40% HP or less with even numbers or more, OHA's team roam keeps only its non-fight branches for it and
     * LaneFight makes no claim. Off: team roam's fight branches and LaneFight's claims, and the trade's 25% kill cut.
     */
    CoreLaneFight: true,
    /**
     * Slice lane-aggro: an in-lane core (and a support whose lane core is away) draws enemy lane creeps on purpose
     * (lane_aggro): `feed` walks the enemy wave onto our ranged creep for our deny, `drag` walks a creep about to die away
     * from an enemy hero for a safe last hit. Off: no draws, and OHA-era lane_tech keeps its aggro pull.
     */
    LaneAggro: true,
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
};

export type Feature = keyof typeof DEFAULTS;

/** Every switch's value as `Name:1|0` in name order (telemetry: which arm a game ran when no --set shows it). */
export function Describe(): string {
    const names: string[] = [];
    for (const name in DEFAULTS) names.push(name);
    names.sort();
    return names.map((n) => `${n}:${On(n as Feature) ? 1 : 0}`).join(",");
}

export function On(feature: Feature): boolean {
    if (Customize.Enable === false) return false;
    const value = Customize.Ours?.[feature];
    if (value === undefined || value === null) return DEFAULTS[feature];
    return value === true;
}
