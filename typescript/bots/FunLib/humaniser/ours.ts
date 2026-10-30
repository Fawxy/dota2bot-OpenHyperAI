/**
 * Kill switches for the decisions we have taken over from OHA (Customize.Ours). Each switch's OFF arm is OHA's own
 * decision. A Customize file without the block or the key gets DEFAULTS; Customize.Enable = false turns all of them off.
 */
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");

export const DEFAULTS = {
    /** Slice 3: pos4/pos5 leave a lane creep an allied core can take (Etiquette). */
    LeaveCoreCreep: true,
    /** Slice 5: pos1-3 take lane last hits and denies through the laning state's body (states/core_last_hit). */
    CoreLastHit: true,
};

export type Feature = keyof typeof DEFAULTS;

export function On(feature: Feature): boolean {
    if (Customize.Enable === false) return false;
    const value = Customize.Ours?.[feature];
    if (value === undefined || value === null) return DEFAULTS[feature];
    return value === true;
}
