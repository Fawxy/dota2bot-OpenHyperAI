/**
 * Customize.Overrides: test-harness knobs written per turn by dotactl (`--set Overrides.<Key>=<value>`, or `--drill <name>`,
 * which sets `Overrides.Drill`), read where a drill or scenario changes what a bot does. Readers: drill (Drill: who plays,
 * benches, stands as a statue or plays lane-only, and the reps), stack_job (StackFar, ShrineLane, Sweep and the other
 * stack diagnostics), core_camp (CampForce), states/idle_swing (ForceShove: the lanes whose laners shove, `bot`, `r:bot`,
 * `all`).
 */
import { Unit } from "bots/ts_libs/dota";
import Customize = require("bots/FunLib/custom_loader");
import * as Drill from "bots/FunLib/humaniser/drill";

/** An explicit override, else the value the active drill implies (`Drill.TABLE` entry `overrides`), else the default. An
 *  empty string is general.lua's unset default for a string knob (`ForceShove = ""`), so it never shadows a drill's value
 *  (drill shove ldr4: no shove swing ran under the implied `r:bot`). */
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

/**
 * Overrides.CampForce (slice core-next-gold, harness games only): an owned core's camp trip starts whenever an open camp is
 * in reach, without the decision's gates (creeps at the core, the gap to the clash, the return deadline, the least net). The
 * safety gates stay. A harness for the trip's execution (walk, clear, chain, walk back, its ends and deaths), not a behaviour.
 */
export function CampForce(): boolean {
    return Get("CampForce") === true;
}

/**
 * Overrides.AdmitLog (slice core-next-gold, drills only): the camp trip's price check at the camp (`admits`) judges both its
 * halves by the real rule, logs its verdict as `phase=admit` and refuses nobody, so what a refusal would have saved or cost
 * is observed (refusal precision). Baked into the arm's `Customize/general.lua` for a remote drill.
 */
export function AdmitLog(): boolean {
    return Get("AdmitLog") === true;
}
