/**
 * A support's lane steps under our switches (slice l1-support-deny), as one ordered list: the first step that wants the frame
 * acts, and mode_laning_generic's own steps (OHA's last hit, the techniques, harass) run only when none does. The combiner for
 * the support's lane steps (OWNERSHIP.md): a later behaviour (harass, zoning, pulls on wave state) adds its own step here, or
 * moves one, with a fixture for the new order, instead of a special case in the Lua Think.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Laning from "bots/FunLib/humaniser/states/laning";

export interface StepCtx {
    /** Whether the laning body runs for this bot now (state current, owned, running). */
    bodyRunning: (this: void) => boolean;
    /** The body's phase label (walk, hold, lasthit, deny), when it runs. */
    bodyLabel: (this: void) => string | undefined;
    /** Steps the laning body this frame; true when it acted. */
    stepBody: (this: void) => boolean;
}

interface LaneStep {
    name: string;
    wants: (this: void, bot: Unit, ctx: StepCtx) => boolean;
    run: (this: void, bot: Unit, ctx: StepCtx) => boolean;
}

/**
 * User rule 02/11/2026: deny before anything else while denies are tuned. Wants the frame while the body is in a deny
 * attempt or would start one now; its scan picks the creep when stepped.
 */
const deny: LaneStep = {
    name: "deny",
    wants: (bot, ctx) => Laning.OwnsDenyOnly(bot) && ctx.bodyRunning() && (ctx.bodyLabel() === "deny" || Laning.DenyOffered(bot)),
    run: (_bot, ctx) => ctx.stepBody(),
};

export const STEPS: LaneStep[] = [deny];

/** The name of the step that acted, or undefined when none wanted the frame (or the one that did issued nothing). */
export function Step(bot: Unit, ctx: StepCtx): string | undefined {
    for (const s of STEPS) {
        if (s.wants(bot, ctx) && s.run(bot, ctx)) return s.name;
    }
    return undefined;
}

/** Whether any step may act for this bot: decided per frame by mode_laning_generic before its own steps. */
export function Applies(bot: Unit): boolean {
    return Laning.OwnsDenyOnly(bot);
}
