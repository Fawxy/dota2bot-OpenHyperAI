/**
 * Who our retreat owns and whose episode runs (slice retreat, master docs/team/slices/retreat.md). Kept apart from retreat.ts
 * so the threat read and the areas whose retreat nudges the slice turns off can ask without importing the retreat itself.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

const running: Record<number, boolean> = {};

/** With `Ours.Retreat` on, a bot hero in its laning phase: our retreat decides when it leaves, where to and when it stops. */
export function Owns(bot: Unit): boolean {
    return Ours.On("Retreat") && Phase.LaningTransitions(bot);
}

/** An episode of our retreat runs for this hero (an ally counts no help to the threat read while it does). */
export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] === true;
}

export function SetRunning(bot: Unit, on: boolean): void {
    running[bot.GetPlayerID()] = on ? true : (undefined as any);
}

export function ResetCache(): void {
    for (const k of Object.keys(running)) delete running[k as unknown as number];
}
