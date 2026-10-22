/**
 * Leaf probe registry (PF11). Lower lane modules read answers owned by higher modules through these
 * probes, which the higher module registers at load, so no require cycle is created.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";

type RotationProbe = (this: void, bot: Unit) => boolean;
type StackedProbe = (this: void, campIdx: number) => boolean;
type BusyProbe = (this: void, bot: Unit) => boolean;
type OverrideProbe = (this: void, bot: Unit) => LaneConfig.Technique | undefined;
type CautionProbe = (this: void, bot: Unit) => boolean;
type PositionProbe = (this: void, bot: Unit, loc: Vector) => Vector;
type TradeProbe = (this: void, bot: Unit) => boolean;

let rotationProbes: RotationProbe[] = [];
let stackedProbes: StackedProbe[] = [];
let busyProbes: BusyProbe[] = [];
let override: OverrideProbe | undefined;
let cautionProbe: CautionProbe | undefined;
let positionProbe: PositionProbe | undefined;
let tradeProbe: TradeProbe | undefined;

export function SetRotationProbe(fn: RotationProbe): void {
    rotationProbes.push(fn);
}

export function IsRotationPlanned(bot: Unit): boolean {
    for (const probe of rotationProbes) if (probe(bot)) return true;
    return false;
}

/** Registered by modules that commit the bot to a kill setup or similar (task 11); read by the transitions IsBusy. */
export function SetBusyProbe(fn: BusyProbe): void {
    busyProbes.push(fn);
}

export function IsBusyByProbe(bot: Unit): boolean {
    for (const probe of busyProbes) if (probe(bot)) return true;
    return false;
}

export function SetStackedProbe(fn: StackedProbe): void {
    stackedProbes.push(fn);
}

export function IsStacked(campIdx: number): boolean {
    for (const probe of stackedProbes) if (probe(campIdx)) return true;
    return false;
}

export function SetTechniqueOverride(fn: OverrideProbe): void {
    override = fn;
}

export function TechniqueOverride(bot: Unit): LaneConfig.Technique | undefined {
    return override !== undefined ? override(bot) : undefined;
}

/** Registered by the transitions caution (task 12): a cautious core never picks SHOVE. */
export function SetCautionProbe(fn: CautionProbe): void {
    cautionProbe = fn;
}

export function IsCautious(bot: Unit): boolean {
    return cautionProbe !== undefined && cautionProbe(bot);
}

export function SetPositionProbe(fn: PositionProbe): void {
    positionProbe = fn;
}

/** The final lane move point; `loc` itself when no probe applies. */
export function PositionOverride(bot: Unit, loc: Vector): Vector {
    return positionProbe !== undefined ? positionProbe(bot, loc) : loc;
}

export function SetTradeProbe(fn: TradeProbe): void {
    tradeProbe = fn;
}

export function TradesSuppressed(bot: Unit): boolean {
    return tradeProbe !== undefined && tradeProbe(bot);
}

export function ResetHooks(): void {
    rotationProbes = [];
    stackedProbes = [];
    busyProbes = [];
    override = undefined;
    cautionProbe = undefined;
    positionProbe = undefined;
    tradeProbe = undefined;
}
