/**
 * Customize.Overrides: test-harness knobs written per turn by dotactl (`--set Overrides.<Key>=<value>`), read where a
 * scenario changes what a bot does. Readers: stack_job (Solo, StackEvery, StackFar), chooser and mode_laning_generic
 * (LaneOnly).
 */
import Customize = require("bots/FunLib/custom_loader");

export function Get(key: string): unknown {
    return (Customize as any).Overrides?.[key];
}

/**
 * Overrides.LaneOnly (slice lane-last-hits, scenario games only): every bot stays in laning mode through the laning phase
 * and does nothing in it but hold its spot, last-hit and deny: no techniques, harass, trades, spells or items. A check
 * harness for the last-hit model (many attempts per game, no trade or retreat deaths), not a behaviour.
 */
export function LaneOnly(): boolean {
    return Get("LaneOnly") === true;
}
