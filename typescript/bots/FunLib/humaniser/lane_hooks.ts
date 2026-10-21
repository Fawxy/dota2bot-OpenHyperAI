/**
 * Leaf probe registry (PF11). Lower lane modules read answers owned by higher modules through these
 * probes, which the higher module registers at load, so no require cycle is created.
 */
import { Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";

type RotationProbe = (this: void, bot: Unit) => boolean;
type StackedProbe = (this: void, campIdx: number) => boolean;
type OverrideProbe = (this: void, bot: Unit) => LaneConfig.Technique | undefined;

let rotationProbes: RotationProbe[] = [];
let stackedProbes: StackedProbe[] = [];
let override: OverrideProbe | undefined;

export function SetRotationProbe(fn: RotationProbe): void {
    rotationProbes.push(fn);
}

export function IsRotationPlanned(bot: Unit): boolean {
    for (const probe of rotationProbes) if (probe(bot)) return true;
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

export function ResetHooks(): void {
    rotationProbes = [];
    stackedProbes = [];
    override = undefined;
}
