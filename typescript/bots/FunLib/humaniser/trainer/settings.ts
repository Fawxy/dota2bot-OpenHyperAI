import * as Config from "bots/FunLib/humaniser/config";

export const DEFAULTS = {
    Enable: true,
    Bar: true,
    BarStyle: "time" as "time" | "hp",
    OutcomeOnly: false,
    ScreenText: true,
    Denies: true,
    Chat: "off" as "off" | "misses" | "all",
    EasyWindow: 0.3,
    Checkpoints: [300, 600] as number[],
    SelfTest: false,
    TextX: 560,
    TextY: 40,
    WatchInterval: 0.1,
    MaxWatched: 2,
};

export type TrainerSettings = typeof DEFAULTS;

function merge(defaults: any, overrides: any): any {
    if (overrides === undefined || overrides === null || type(overrides) !== "table") return defaults;
    const result: any = {};
    for (const [k, v] of pairs(defaults)) result[k] = v;
    for (const [k, v] of pairs(overrides)) {
        const d = defaults[k];
        // A list replaces the default; merging by index would keep stale tail entries.
        const isList = d !== undefined && type(d) === "table" && d[1] !== undefined;
        result[k] = d !== undefined && type(d) === "table" && type(v) === "table" && !isList ? merge(d, v) : v;
    }
    return result;
}

let cached: TrainerSettings | undefined;

export function Get(): TrainerSettings {
    if (cached === undefined) cached = merge(DEFAULTS, Config.Get().Trainer?.LastHit) as TrainerSettings;
    return cached;
}

export function IsEnabled(): boolean {
    return Config.IsEnabled() && Get().Enable === true;
}
