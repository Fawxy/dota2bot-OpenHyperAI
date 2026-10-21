/** @noSelfInFile */
export type Reason = "ok" | "timeout" | "stuck" | "preempted" | "dead" | "cancelled" | "error" | "no_target" | "missed" | "denied" | "taken_by_other" | "etiquette" | "interrupted" | "unsupported";
export interface Result {
    success: boolean;
    reason: Reason;
    message?: string;
}
/** A task body: a generator resumed once per frame; each bare `yield` ends that frame's slice. */
export type TaskBody = Generator<void, Result, unknown>;
export interface Vec {
    x: number;
    y: number;
    z?: number;
}
/**
 * Minimal structural bot handle; no Dota/OHA imports. Members are methods (not `this: void`)
 * so they compile to `unit:Method(...)`, matching Dota's bot unit API.
 */
export interface TaskUnit {
    GetPlayerID(): number;
    GetLocation(): Vec;
    IsAlive(): boolean;
    GetActiveMode(): number;
    GetLastHits(): number;
    IsStunned?(): boolean;
    Action_MoveToLocation(loc: Vec): void;
    Action_AttackUnit(u: any, once: boolean): void;
    GetAttackRange(): number;
    GetAttackDamage?(): number;
    /** Seconds from swing start until the hit lands. */
    GetAttackPoint?(): number;
    GetNearbyLaneCreeps?(radius: number, enemies: boolean): TaskCreep[];
    GetNearbyHeroes?(radius: number, enemies: boolean, mode: number): TaskHero[];
}
/** Minimal structural lane creep handle. */
export interface TaskCreep {
    GetHealth(): number;
    IsAlive(): boolean;
    GetLocation(): Vec;
    IsNull?(): boolean;
}
/** Minimal structural hero handle, as returned by `GetNearbyHeroes`. */
export interface TaskHero {
    GetAttackTarget?(): unknown;
}
/** Mode claim forwarded to the host's mode arbiter. `floor` is the minimum desire the claim holds. */
export interface ClaimSpec {
    source: string;
    mode: number;
    tier: string;
    floor: number;
}
/** Host integration hooks. Plain function fields (`this: void`) so they compile to `adapter.fn(...)`. */
export interface Adapter {
    claim(this: void, bot: TaskUnit, c: ClaimSpec): void;
    release(this: void, bot: TaskUnit, source: string, mode: number): void;
    lastHitFilter?(this: void, bot: TaskUnit, creep: any): boolean;
    /** Game time in seconds. */
    now(this: void): number;
    log(this: void, tag: string, msg: string): void;
    enabled(this: void): boolean;
}
/** `host` is the mode id the task runs under. */
export interface TaskOptions {
    name: string;
    host: number;
    tier?: string;
    floor?: number;
}
