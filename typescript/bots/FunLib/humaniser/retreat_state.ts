/**
 * Who our retreat owns and whose episode runs (slice retreat, master docs/team/slices/retreat.md). Kept apart from retreat.ts
 * so the threat read and the areas whose retreat nudges the slice turns off can ask without importing the retreat itself.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Phase from "bots/FunLib/humaniser/transitions/phase";

const running: Record<number, boolean> = {};

/**
 * With `Ours.Retreat` on, a bot hero in its laning phase: our retreat decides when it leaves, where to and when it stops. A
 * drill's held hero (bench, statue, sentry, chaser) is the drill's: our retreat outbid its hold (drills rtwalk2, rtchase2).
 * The laning phase is the hold's (Phase.LaningHeld).
 */
export function Owns(bot: Unit): boolean {
    if (!Ours.On("Retreat")) return false;
    // A drill's held hero is never read, so it logs no ownership line.
    return !Drill.Held(bot) && Phase.LaningHeld(bot);
}

/** An episode of our retreat runs for this hero (an ally counts no help to the threat read while it does). */
export function Running(bot: Unit): boolean {
    return running[bot.GetPlayerID()] === true;
}

export function SetRunning(bot: Unit, on: boolean): void {
    running[bot.GetPlayerID()] = on ? true : (undefined as any);
}

/** Sustain's answer for a hero it carries (sustain_act.ts writes it at each decision, so retreat reads it without importing sustain). */
const home: Record<number, { on: boolean; at: number } | undefined> = {};
const healing: Record<number, boolean> = {};

/** A sustain answer older than this (s) is not read: retreat's own heal floor decides. Sustain decides every 0.5 s, but a running use skips its decisions until it starts (a tango walk's deadline: walk plus 1.5 s). */
export const HOME_FRESH = 10;

/** sustain_act.ts, each decision for a hero it carries: whether rule 2 sends it home; undefined once it no longer carries it. */
export function SetHome(bot: Unit, on: boolean | undefined): void {
    home[bot.GetPlayerID()] = on === undefined ? undefined : { on, at: DotaTime() };
}

/** Sustain's going-home answer (design 2026-11-19-sustain-design.md rule 2), or undefined when sustain does not carry the hero or has not decided lately. */
export function Home(bot: Unit): boolean | undefined {
    const h = home[bot.GetPlayerID()];
    if (h === undefined || DotaTime() - h.at > HOME_FRESH) return undefined;
    return h.on;
}

/** A heal episode (the walk home) of our retreat runs for this hero: sustain spends nothing meanwhile (its `home` run). */
export function Healing(bot: Unit): boolean {
    return healing[bot.GetPlayerID()] === true;
}

export function SetHealing(bot: Unit, on: boolean): void {
    healing[bot.GetPlayerID()] = on ? true : (undefined as any);
}

/**
 * The priced leave's pick this frame (Ours.PricedLeaveAct): true when, with no episode running yet, it leaves now. retreat.ts fills the
 * slot at load (no import cycle); the arbiter reads it so the episode the retreat starts this frame is the pick this frame, not the next.
 */
let leaveNow: (this: void, bot: Unit) => boolean = () => false;

export function LeaveNow(bot: Unit): boolean {
    return leaveNow(bot);
}

export function SetLeaveNow(fn: (this: void, bot: Unit) => boolean): void {
    leaveNow = fn;
}

export function ResetCache(): void {
    for (const k of Object.keys(running)) delete running[k as unknown as number];
    for (const k of Object.keys(home)) delete home[k as unknown as number];
    for (const k of Object.keys(healing)) delete healing[k as unknown as number];
}
