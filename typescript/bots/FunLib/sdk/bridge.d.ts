// Vendored from dota-bot-sdk packages/lua-bridge @ 9043ff1. Do not edit; rebuild and re-vendor.
/** @noSelfInFile */
export interface BridgeDeps {
    log: (this: void, line: string) => void;
    realTime: (this: void) => number;
    gameTime: (this: void) => number;
    encode: (this: void, v: any) => string;
    decode: (this: void, s: string) => any;
    lookup?: (this: void, name: string) => any;
    random?: (this: void) => number;
}
export interface BridgeConfig {
    Enable: boolean;
    Url: string;
    Hz: number;
    TimeoutSec: number;
    FailuresBeforeBackoff: number;
    MaxBackoffSec: number;
    PayloadBytes: number;
    SummaryEverySec: number;
}
export declare const DEFAULTS: BridgeConfig;
export declare function Init(deps: BridgeDeps, config?: Partial<BridgeConfig>): void;
export declare function Tick(team: number, pid: number): void;
export declare function GetStats(): {
    inst: string;
    sent: number;
    received: number;
    lost: number;
    errors: number;
    inFlight: boolean;
    backoffUntil: number;
    ctor: string;
    disabled?: string;
};
