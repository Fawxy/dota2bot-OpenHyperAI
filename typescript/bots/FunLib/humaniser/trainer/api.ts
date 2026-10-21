/**
 * Dota API calls the trainer needs that bots/ts_libs/dota does not type yet.
 * Kept here, not in ts_libs, so this module stays independent of other humaniser work.
 */
import { Unit, Vector } from "bots/ts_libs/dota";

export interface TUnit extends Unit {
    GetLastHits(): number;
    GetDenies(): number;
    GetAnimCycle(): number;
    GetAttackPoint(): number;
    GetSecondsPerAttack(): number;
    GetAttackSpeed(): number;
    GetAttackProjectileSpeed(): number;
    GetIncomingTrackingProjectiles(): { location: Vector; caster?: Unit; is_attack: boolean }[];
    IsStunned(): boolean;
    IsHexed(): boolean;
    IsTower(): boolean;
}

export function T(u: Unit): TUnit {
    return u as TUnit;
}

declare function DebugDrawLine(a: Vector, b: Vector, r: number, g: number, b2: number): void;

export function DrawLine(a: Vector, b: Vector, r: number, g: number, b2: number): void {
    DebugDrawLine(a, b, r, g, b2);
}

export type CreepKind = "melee" | "ranged" | "siege";

export function CreepKind(u: Unit): CreepKind {
    const name = u.GetUnitName();
    if (string.find(name, "siege", 1, true)[0] !== undefined) return "siege";
    if (string.find(name, "ranged", 1, true)[0] !== undefined) return "ranged";
    return "melee";
}

/** "npc_dota_hero_crystal_maiden" -> "Crystal maiden". */
export function HeroLabel(u: Unit): string {
    const name = string.gsub(string.gsub(u.GetUnitName(), "npc_dota_hero_", "")[0], "_", " ")[0];
    return string.upper(string.sub(name, 1, 1)) + string.sub(name, 2);
}

/** World helpers injected from jmz_func, which this module cannot require (it requires the humaniser). */
export interface TrainerHelpers {
    GetAttackProDelayTime(this: void, subject: Unit, creep: Unit): number;
    IsInLaningPhase(this: void): boolean;
}

let helpers: TrainerHelpers | undefined;

export function SetTrainerHelpers(h: TrainerHelpers): void {
    helpers = h;
}

export function GetTrainerHelpers(): TrainerHelpers | undefined {
    return helpers;
}
