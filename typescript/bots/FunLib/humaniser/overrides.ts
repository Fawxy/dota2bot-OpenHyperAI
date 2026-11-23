/**
 * Customize.Overrides: test-harness knobs written per turn by dotactl (`--set Overrides.<Key>=<value>`, or `--drill <name>`,
 * which sets `Overrides.Drill`), read where a drill or scenario changes what a bot does. Readers: drill (Drill: who plays,
 * benches, stands as a statue or plays lane-only, and the reps), stack_job (StackFar, ShrineLane, Sweep and the other
 * stack diagnostics).
 */
import { Unit } from "bots/ts_libs/dota";
import Customize = require("bots/FunLib/custom_loader");
import * as Drill from "bots/FunLib/humaniser/drill";

/** An explicit override, else the value the active drill implies (`Drill.TABLE` entry `overrides`), else the default. An
 *  empty string is general.lua's unset default for a string knob, so it never shadows a drill's value. */
export function Get(key: string): unknown {
    const v = (Customize as any).Overrides?.[key];
    if (v !== undefined && v !== "") return v;
    const implied = Drill.Implied(key);
    return implied !== undefined ? implied : v;
}

/**
 * Lane-only (a drill's `castLaneOnly` or `others: "laneonly"`; the old Overrides.LaneOnly is drill `lane-only`): the bot
 * stays in laning mode through the laning phase and does nothing in it but hold its spot, last-hit and deny: no
 * techniques, harass, trades, spells or items. A harness, not a behaviour. Per hero: a drill's bench and statues are not.
 */
export function LaneOnly(bot: Unit): boolean {
    return Drill.LaneOnly(bot);
}

