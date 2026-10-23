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
    ValveWeight: 0.5,
    FretWeight: 0.5,
    SkillOverride: undefined as number | undefined,
    /**
     * FretBots bridge. FretBots runs in a separate VScript context, so its difficulty must be inferred.
     * FretBotsLevelOverride: force the FretBots level the bots believe (0..10), for when the mirror is wrong.
     * BridgeModifier: if set, FretBots writes difficulty*10 and allyScale*100 as stack counts on this modifier
     * (applied by FretBots/Settings.lua). Off by default because changing stacks on a built-in modifier is untested.
     */
    FretBridge: {
        FretBotsLevelOverride: undefined as number | undefined,
        BridgeModifier: undefined as string | undefined,
    },
    Profile: {
        PersonalMin: 0.85,
        PersonalMax: 1.15,
        NoticeLow: 0.55,
        NoticeHigh: 0.18,
        ReactLow: 0.5,
        ReactHigh: 0.17,
        // Reading a ping or typed chat takes far longer than a visual reaction.
        PingLow: 2.0,
        PingHigh: 0.8,
        ChatLow: 2.0,
        ChatHigh: 1.0,
        JitterLow: 0.45,
        JitterHigh: 0.2,
        LapseLow: 0.15,
        LapseHigh: 0.02,
        LapseMinExtra: 0.3,
        LapseMaxExtra: 0.8,
        AimErrorLow: 250,
        AimErrorHigh: 40,
        // OpenAI Five at ~0.2s still felt inhuman; never go below this.
        MinReact: 0.17,
    },
    Orders: {
        DesireFloor: 0.85,
        AckCooldown: 20,
    },
    Perception: { Enable: true } as Record<string, any>,
    AllyLastHit: { Enable: true } as Record<string, any>,
    Pings: { Enable: true } as Record<string, any>,
    Commands: { Enable: true } as Record<string, any>,
    Lane: { Enable: true } as Record<string, any>,
    LaneFight: { Enable: true } as Record<string, any>,
    Transitions: { Enable: true } as Record<string, any>,
    Intent: { Enable: true } as Record<string, any>,
    LastHitSkill: { Enable: true } as Record<string, any>,
    FarmPattern: { Enable: true } as Record<string, any>,
    Trainer: { LastHit: { Enable: true } } as Record<string, any>,
    /**
     * [HEV] event lines for tools/hlog. Off unless Customize turns it on; never changes behaviour.
     * Runs even with Enable = false (A/B games); only Customize.Enable = false turns it off with the rest.
     */
    Telemetry: { Enable: false } as Record<string, any>,
    // tasks: coroutine task runner spike (see humaniser/tasks.ts). Stack: run camp stacks as a task (stack_task.ts).
    Tasks: { Enable: true, Demo: false, Stack: false } as Record<string, any>,
    // Behaviour-state layer on the SDK's States (humaniser/states). Off: no selection, telemetry or tasks.
    States: { Enable: false, Shadow: true, Own: { laning: [2] }, Teams: "allies", ShadowTeams: "allies", LanePosEvery: 2 } as Record<string, any>,
    // Team game phase on the SDK's Phase (humaniser/states/phase). Priors off: shadow, logs ev=phase only.
    Phase: { Enable: false, Priors: false, Interval: 0.5, SeenWindow: 3, ThreatRadius: 900 } as Record<string, any>,
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
        // A States.Own list replaces the default one, so removing a position in Customize really removes it.
        const own = (Customize.Humaniser as any)?.States?.Own;
        if (own !== undefined) merged.States = { ...merged.States, Own: own };
        // Customize.Enable = false turns off every custom setting, humaniser and telemetry included.
        if (Customize.Enable === false) {
            merged.Enable = false;
            merged.Telemetry = DEFAULTS.Telemetry;
        }
        cached = merged;
    }
    return cached;
}

export function IsEnabled(): boolean {
    return Get().Enable === true;
}

/** True when the humaniser and the named sub-feature are both enabled. */
export function IsFeatureEnabled(feature: "Perception" | "AllyLastHit" | "Pings" | "Commands" | "Lane" | "LaneFight" | "Transitions" | "Intent" | "LastHitSkill" | "FarmPattern"): boolean {
    const cfg = Get();
    return cfg.Enable === true && cfg[feature] !== undefined && cfg[feature].Enable === true;
}
