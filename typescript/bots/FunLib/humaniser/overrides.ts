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

/** An explicit override, else the value the active drill implies (`Drill.TABLE` entry `overrides`). */
export function Get(key: string): unknown {
    const v = (Customize as any).Overrides?.[key];
    return v !== undefined ? v : Drill.Implied(key);
}

/**
 * Lane-only (a drill's `castLaneOnly` or `others: "laneonly"`; the old Overrides.LaneOnly is drill `lane-only`): the bot
 * stays in laning mode through the laning phase and does nothing in it but hold its spot, last-hit and deny: no
 * techniques, harass, trades, spells or items. A harness, not a behaviour. With no bot: whether any hero is lane-only.
 */
export function LaneOnly(bot?: Unit): boolean {
    return bot === undefined ? Drill.AnyLaneOnly() : Drill.LaneOnly(bot);
}

/**
 * Overrides.CampForce (slice core-next-gold, harness games only): an owned core's camp trip starts whenever an open camp is
 * in reach, without the decision's gates (creeps at the core, the gap to the clash, the return deadline, the least net). The
 * safety gates stay. A harness for the trip's execution (walk, clear, chain, walk back, its ends and deaths), not a behaviour.
 */
export function CampForce(): boolean {
    return Get("CampForce") === true;
}
