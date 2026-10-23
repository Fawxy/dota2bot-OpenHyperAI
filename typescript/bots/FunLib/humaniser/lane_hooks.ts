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
type FightProbe = (this: void, bot: Unit) => boolean;
type CautionProbe = (this: void, bot: Unit) => boolean;
type PositionProbe = (this: void, bot: Unit, loc: Vector) => Vector;
type TradeProbe = (this: void, bot: Unit) => boolean;
type MissingProbe = (this: void, bot: Unit, maxAge?: number) => number;
type RotationDecidedProbe = (this: void, bot: Unit) => boolean;

let rotationProbes: RotationProbe[] = [];
let stackedProbes: StackedProbe[] = [];
let busyProbes: BusyProbe[] = [];
let override: OverrideProbe | undefined;
let fightProbes: FightProbe[] = [];
let cautionProbe: CautionProbe | undefined;
let positionProbe: PositionProbe | undefined;
let tradeProbe: TradeProbe | undefined;
let missingProbe: MissingProbe | undefined;
let rotationDecidedProbe: RotationDecidedProbe | undefined;

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

/** lane_fight registers this: camp jobs must not start while the bot is committed to a lane kill. */
export function SetFightProbe(fn: FightProbe): void {
    fightProbes.push(fn);
}

export function IsFightCommitting(bot: Unit): boolean {
    for (const probe of fightProbes) if (probe(bot)) return true;
    return false;
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

export function SetMissingProbe(fn: MissingProbe): void {
    missingProbe = fn;
}

/** Task 12's count of lane enemies gone missing from the bot's lane; `maxAge` keeps only those unseen at most that long. */
export function EnemiesMissing(bot: Unit, maxAge?: number): number {
    return missingProbe !== undefined ? missingProbe(bot, maxAge) : 0;
}

/** Task 12 registers this: the bot has decided to rotate for the next power rune (from the decision, not the leave time). */
export function SetRotationDecidedProbe(fn: RotationDecidedProbe): void {
    rotationDecidedProbe = fn;
}

export function RotationDecided(bot: Unit): boolean {
    return rotationDecidedProbe !== undefined && rotationDecidedProbe(bot);
}

export function ResetHooks(): void {
    rotationProbes = [];
    stackedProbes = [];
    busyProbes = [];
    override = undefined;
    fightProbes = [];
    cautionProbe = undefined;
    positionProbe = undefined;
    tradeProbe = undefined;
    missingProbe = undefined;
    rotationDecidedProbe = undefined;
}
