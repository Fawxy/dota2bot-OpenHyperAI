/**
 * Humaniser configuration: defaults merged with Customize.Humaniser.
 * Every tunable number lives here so playtests can adjust curves in one place.
 * User Customize files may predate a key, so all reads go through Get() which falls back to DEFAULTS.
 */
// custom_loader prefers a user copy in game/Customize over the bundled defaults; it is hand-written Lua.
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/FunLib/custom_loader");

export const DEFAULTS = {
    Enable: true,
    Debug: false,
    /**
     * Humaniser.Tick runs its steps on every TickEvery-th frame (3 = ten times a game second); only the steps index.ts
     * names as frame steps run on the others. 1 runs every step every frame.
     */
    TickEvery: 3,
    /**
     * [HEV] event lines for tools/hlog. Off unless Customize turns it on; never changes behaviour.
     * Runs even with Enable = false (A/B games); only Customize.Enable = false turns it off with the rest.
     */
    Telemetry: { Enable: false } as Record<string, any>,
    /** The engine's task runner (humaniser/tasks.ts), which the jobs run on. */
    Tasks: { Enable: true } as Record<string, any>,
};

export type HumaniserConfig = typeof DEFAULTS;

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" ? merge(d, v) : v;
    }
    return result;
}

let cached: HumaniserConfig | undefined;

export function Get(): HumaniserConfig {
    if (cached === undefined) {
        const merged = merge(DEFAULTS, Customize.Humaniser) as HumaniserConfig;
        // Customize.Enable = false turns off every custom setting, humaniser and telemetry included.
        if (Customize.Enable === false) {
            merged.Enable = false;
            merged.Telemetry = DEFAULTS.Telemetry;
        }
        cached = merged;
    }
    return cached;
}

/**
 * Game time as the humaniser's game-phase logic sees it: DotaTime() plus Customize.Overrides.ClockOffset (scenario
 * games fake "10:00 in" this way, since the real clock can't be set). Only for "which part of the game is it" reads;
 * anything synced to world timers (camp spawns, runes, waves) and relative timers must keep raw DotaTime().
 */
export function Now(): number {
    const offset = (Customize as any).Overrides?.ClockOffset;
    return DotaTime() + (typeof offset === "number" ? offset : 0);
}

export function IsEnabled(): boolean {
    return Get().Enable === true;
}
