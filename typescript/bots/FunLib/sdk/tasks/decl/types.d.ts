/** @noSelfInFile */
export type Reason = "ok" | "timeout" | "stuck" | "preempted" | "dead" | "cancelled" | "error" | "no_target" | "missed" | "denied" | "taken_by_other" | "etiquette" | "interrupted" | "unsupported" | "not_castable" | "no_item";
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
    /** Game time of this unit's most recent attack; only ever compared with an earlier reading of itself. */
    GetLastAttackTime?(): number;
    GetNearbyLaneCreeps?(radius: number, enemies: boolean): TaskCreep[];
    GetNearbyHeroes?(radius: number, enemies: boolean, mode: number): TaskHero[];
    GetMana?(): number;
    IsChanneling?(): boolean;
    /** True during any ability's cast point. */
    IsCastingAbility?(): boolean;
    Action_UseAbility?(ability: TaskAbility): void;
    Action_UseAbilityOnEntity?(ability: TaskAbility, target: any): void;
    Action_UseAbilityOnLocation?(ability: TaskAbility, loc: Vec): void;
    /** `rune` is a rune location constant (`RUNE_POWERUP_1`, `RUNE_BOUNTY_1`, ...), not a position. */
    Action_PickUpRune?(rune: number): void;
    /** Slot index of the named item anywhere in the inventory, or -1. */
    FindItemSlot?(name: string): number;
    GetItemInSlot?(slot: number): TaskAbility | undefined;
}
/** Minimal structural ability handle. Items are abilities in Dota's API, so item handles fit too. */
export interface TaskAbility {
    /** Off cooldown and enough mana. */
    IsFullyCastable(): boolean;
    IsNull?(): boolean;
    GetName?(): string;
    GetCooldownTimeRemaining?(): number;
    GetCastPoint?(): number;
    GetChannelTime?(): number;
    GetManaCost?(): number;
    IsInAbilityPhase?(): boolean;
    IsChanneling?(): boolean;
}
/** Minimal structural lane creep handle. */
export interface TaskCreep {
    GetHealth(): number;
    IsAlive(): boolean;
    GetLocation(): Vec;
    IsNull?(): boolean;
}
/** Minimal structural attack target handle. */
export interface TaskTarget {
    IsAlive(): boolean;
    IsNull?(): boolean;
    CanBeSeen?(): boolean;
    GetAttackTarget?(): unknown;
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
    /** While set, the host should suppress other modes' hysteresis/stickiness so this claim wins at once. */
    urgent?: boolean;
}
/** Host integration hooks. Plain function fields (`this: void`) so they compile to `adapter.fn(...)`. */
export interface Adapter {
    claim(this: void, bot: TaskUnit, c: ClaimSpec): void;
    release(this: void, bot: TaskUnit, source: string, mode: number): void;
    lastHitFilter?(this: void, bot: TaskUnit, creep: any): boolean;
    /** Called each frame a verb deliberately keeps the bot standing still; hosts with a stuck detector use it. */
    hold?(this: void, bot: TaskUnit, tag: string): void;
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
    /**
     * Called exactly once when the task ends, for any reason, after its claim is released. Bodies must do
     * their cleanup here: a generator's `finally` does not run on cancel. Errors are logged, not raised.
     */
    onEnd?: (this: void, result: Result, info: {
        label?: string;
        steps: number;
    }) => void;
    /**
     * Evaluated every frame (in `Tick` and before each resume). A returned string ends the task with
     * `interrupted`, carrying the string verbatim as the message; the body is not resumed that frame.
     */
    guard?: (this: void) => string | undefined;
    /** Seconds without a `Step` after which a started task is cancelled (`preempted`/`stalled`). Default 2. */
    stallAfter?: number;
    /**
     * Seconds the active mode must differ from the host, continuously, before a started task is preempted.
     * Default 0: preempted on the first `Tick` in another mode.
     */
    preemptAfter?: number;
}
