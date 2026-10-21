/**
 * Glue for the vendored dota-bot-sdk lua-bridge (bots/FunLib/sdk/bridge.lua), a probe of whether
 * the bot VM can POST to a localhost sidecar. Run sheet: dota-bot-sdk/docs/BRIDGE_SPIKE.md.
 */
import { Unit } from "bots/ts_libs/dota";
import * as Config from "bots/FunLib/humaniser/config";
import * as Utils from "bots/FunLib/utils";
import * as Bridge from "bots/FunLib/sdk/bridge";

// OHA's dkjson; its functions take no self.
const Json: { encode(this: void, v: any): string; decode(this: void, s: string): any } = require("bots/ts_libs/utils/json");

let initialised = false;

function log(this: void, line: string): void {
    // Not gated on Debug: the probe's whole output is these lines.
    const rawPrint: ((s: string) => void) | undefined = (Utils as any).RawPrint;
    (rawPrint ?? print)(`[H:bridge] ${line}`);
}

function ensureInit(): void {
    if (initialised) return;
    initialised = true;
    Bridge.Init(
        {
            log,
            realTime: () => RealTime(),
            gameTime: () => GameTime(),
            encode: Json.encode,
            decode: Json.decode,
        },
        Config.Get().Bridge
    );
}

export function IsEnabled(): boolean {
    return Config.IsEnabled() && Config.Get().Bridge.Enable === true;
}

export function Tick(bot: Unit): void {
    if (!IsEnabled()) return;
    if (!bot.IsHero() || bot.IsIllusion()) return;
    ensureInit();
    Bridge.Tick(bot.GetTeam(), bot.GetPlayerID());
}
