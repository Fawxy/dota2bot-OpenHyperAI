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
    /** Slice rune-rotation: pos4 to the 6:00 power rune and its 7:00 shrine, pos5 to the 6:00 rune when it has no stack (RuneJob). */
    RuneRotation: true,
    /** Slice support-lane: pos4/5 pull our wave into the lane's first pull camp when the lane push reading wants it (PullJob);
     *  the old camp-job pulls stop for those bots. Needs JobChooser. */
    SupportPull: true,
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
