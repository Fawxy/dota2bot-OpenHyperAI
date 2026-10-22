/**
 * Lane safety and laning-phase transitions facade (task 12).
 * Imports every transitions module so their load-time registrations run; later tasks add their Tick calls and hooks.
 * J.* helpers cannot be required from humaniser modules, so they arrive through SetHelpers.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";
import * as LaneState from "bots/FunLib/humaniser/lane_state";
import * as Busy from "bots/FunLib/humaniser/transitions/busy";
import * as MidRunes from "bots/FunLib/humaniser/transitions/mid_runes";
import * as Rotation from "bots/FunLib/humaniser/transitions/rotation";

export { Settings, Runes, Busy, MidRunes, Rotation };

export interface TransitionHelpers {
    IsInLaningPhase?: (this: void) => boolean;
    WeAreStronger?: (this: void, bot: Unit, radius: number) => boolean;
    IsAllyOfHuman?: (this: void, bot: Unit) => boolean;
}

/** What the overlay prints (the defaults only evaluate where the lane system has a snapshot for the bot); later tasks replace the placeholders with their real state. */
export interface OverlayProviders {
    Busy: (this: void, bot: Unit) => boolean;
    Spare: (this: void, bot: Unit) => boolean;
    Alone: (this: void, bot: Unit) => boolean;
    Rotation: (this: void, bot: Unit) => "top" | "bot" | undefined;
}

const NEVER = (): boolean => false;
let helpers: TransitionHelpers = {};
let providers: OverlayProviders = {
    Busy: (bot) => LaneState.ForBot(bot) !== undefined && Busy.IsBusy(bot, DotaTime())[0],
    Spare: (bot) => LaneState.ForBot(bot) !== undefined && Busy.LaneCanSpare(bot, false)[0],
    Alone: NEVER,
    Rotation: (bot) => Rotation.Target(bot),
};

export function SetHelpers(h: TransitionHelpers): void {
    helpers = h;
}

export function Helpers(): TransitionHelpers {
    return helpers;
}

export function SetOverlayProviders(p: Partial<OverlayProviders>): void {
    providers = { ...providers, ...p };
}

export function IsActive(): boolean {
    return Settings.IsActive();
}

export function InLaningPhase(): boolean {
    return helpers.IsInLaningPhase !== undefined ? helpers.IsInLaningPhase() : DotaTime() < 600;
}

export function Tick(bot: Unit): void {
    if (!Settings.IsActive()) return;
    MidRunes.Tick(bot);
    Rotation.Tick(bot);
}

/** Rune-mode hooks (3b). True for our pos 2 while the MidRunes sub-feature is on. */
export function MidRunesOn(bot: Unit): boolean {
    return MidRunes.IsOn(bot);
}

export function MidRuneFocus(bot: Unit): LuaMultiReturn<[boolean, boolean, number | undefined]> {
    return MidRunes.Focus(bot);
}

export function MidRuneYield(bot: Unit): void {
    MidRunes.Yield(bot);
}

export function MidRuneSkip(bot: Unit, raw: number, desire: number, target?: number, status?: number, gate?: string): void {
    MidRunes.NoteSkip(bot, raw, desire, target, status, gate);
}

/** Rune-mode hooks (Task 4): the power rune a rotating support heads for, or undefined. */
export function RuneTarget(bot: Unit): number | undefined {
    return Rotation.RuneTarget(bot);
}

/** Our mid's power-rune desire while a rotating support is with it or at the spot; 0 otherwise. */
export function MidRuneDesire(bot: Unit): number {
    return Rotation.MidRuneDesire(bot);
}

/** The rune mode refused this frame: the rotation floor must not apply. */
export function RotationYield(bot: Unit): void {
    Rotation.Yield(bot);
}

export function Overlay(bot: Unit): string {
    return `phase: ${InLaningPhase() ? "laning" : "post"} busy=${tostring(providers.Busy(bot))} spare=${tostring(providers.Spare(bot))} alone=${tostring(
        providers.Alone(bot)
    )} rot=${providers.Rotation(bot) ?? "-"}`;
}
