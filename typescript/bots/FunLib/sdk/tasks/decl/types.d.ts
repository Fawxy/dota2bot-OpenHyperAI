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
    GetTeam?(): number;
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
    GetNearbyTowers?(radius: number, enemies: boolean): TaskAttacker[];
    GetNearbyNeutralCreeps?(radius: number): TaskAttacker[];
    /** Attack speed multiplier (1 = base); divides the attack point. */
    GetAttackSpeed?(): number;
    GetSecondsPerAttack?(): number;
    GetAttackProjectileSpeed?(): number;
    GetCurrentMovementSpeed?(): number;
    GetDenies?(): number;
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
/** A unit whose attacks on a creep the last-hit prediction counts (creeps, heroes, towers). */
export interface TaskAttacker {
    GetLocation(): Vec;
    IsAlive(): boolean;
    GetTeam?(): number;
    IsNull?(): boolean;
    CanBeSeen?(): boolean;
    GetAttackTarget?(): unknown;
    /** 1503 (ACTIVITY_ATTACK) during an attack animation. */
    GetAnimActivity?(): number;
    /** Progress through the current animation, 0..1. */
    GetAnimCycle?(): number;
    GetAttackPoint?(): number;
    GetSecondsPerAttack?(): number;
    GetAttackDamage?(): number;
    GetAttackRange?(): number;
    GetAttackProjectileSpeed?(): number;
}
/** An entry of `GetIncomingTrackingProjectiles()`: plain fields, as Dota returns them. */
export interface TaskProjectile {
    location: Vec;
    caster?: TaskAttacker;
    is_attack?: boolean;
}
/** Minimal structural lane creep handle. Optional members feed the last-hit prediction. */
export interface TaskCreep extends TaskAttacker {
    GetHealth(): number;
    IsAlive(): boolean;
    GetLocation(): Vec;
    IsNull?(): boolean;
    GetMaxHealth?(): number;
    /** HP per second; negative while losing HP over time. */
    GetHealthRegen?(): number;
    /** Damage after armour/resistance (Dota: `DAMAGE_TYPE_PHYSICAL` = 1). */
    GetActualIncomingDamage?(damage: number, damageType: number): number;
    GetIncomingTrackingProjectiles?(): TaskProjectile[];
    GetUnitName?(): string;
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
    GetLocation?(): Vec;
    IsAlive?(): boolean;
    IsNull?(): boolean;
    CanBeSeen?(): boolean;
    GetAnimActivity?(): number;
    GetAnimCycle?(): number;
    GetAttackPoint?(): number;
    GetSecondsPerAttack?(): number;
    GetAttackDamage?(): number;
    GetAttackRange?(): number;
    GetAttackProjectileSpeed?(): number;
}
/** Human timing profile (OHA `Profile.Get`): `react` s base reaction, `jitter` fraction, `lapse` chance. */
export interface SkillProfile {
    react: number;
    jitter: number;
    aimError?: number;
    lapse?: number;
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
    /** Structured telemetry: `fields` are ordered key/value pairs. Without it, events go to `log` as `ev=name k=v`. */
    event?(this: void, name: string, fields: [string, unknown][]): void;
    enabled(this: void): boolean;
    /** Builds a point verbs create themselves (e.g. holdAt's scattered spot); hosts whose move order needs a native vector supply it. */
    vector?(this: void, x: number, y: number, z: number): Vec;
    /** Execution skill in [0, 1] (OHA `Difficulty.GetSkill`). Absent: 1. Read every time a verb needs it. */
    skill?(this: void, bot: TaskUnit): number;
    profile?(this: void, bot: TaskUnit): SkillProfile;
    /** Last-hit error half-width (OHA `LastHitSkill.ErrorWidth`, pressure included); overrides the skill lerp. */
    lastHitError?(this: void, bot: TaskUnit): number;
    /** Uniform [0, 1); defaults to `math.random`. */
    random?(this: void): number;
    /**
     * The clock `GetLastAttackTime()` runs on (Dota: `GameTime()`, not `DotaTime()`). With it, `lastHit`/`deny`
     * add the bot's remaining attack cooldown to its own hit time.
     */
    attackClock?(this: void): number;
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
