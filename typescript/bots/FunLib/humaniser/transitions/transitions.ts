/**
 * Lane safety and laning-phase transitions facade (task 12).
 * Imports every transitions module so their load-time registrations run; later tasks add their Tick calls and hooks.
 * J.* helpers cannot be required from humaniser modules, so they arrive through SetHelpers.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Settings from "bots/FunLib/humaniser/transitions/settings";
import * as Runes from "bots/FunLib/humaniser/transitions/runes";

export { Settings, Runes };

export interface TransitionHelpers {
    IsInLaningPhase?: (this: void) => boolean;
    WeAreStronger?: (this: void, bot: Unit, radius: number) => boolean;
    IsAllyOfHuman?: (this: void, bot: Unit) => boolean;
}

/** What the overlay prints; later tasks replace the placeholders with their real state. */
export interface OverlayProviders {
    Busy: (this: void, bot: Unit) => boolean;
    Spare: (this: void, bot: Unit) => boolean;
    Alone: (this: void, bot: Unit) => boolean;
    Rotation: (this: void, bot: Unit) => "top" | "bot" | undefined;
}

const NEVER = (): boolean => false;
let helpers: TransitionHelpers = {};
let providers: OverlayProviders = { Busy: NEVER, Spare: NEVER, Alone: NEVER, Rotation: () => undefined };

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

export function Tick(_bot: Unit): void {
    if (!Settings.IsActive()) return;
}

export function Overlay(bot: Unit): string {
    return `phase: ${InLaningPhase() ? "laning" : "post"} busy=${tostring(providers.Busy(bot))} spare=${tostring(providers.Spare(bot))} alone=${tostring(
        providers.Alone(bot)
    )} rot=${providers.Rotation(bot) ?? "-"}`;
}
