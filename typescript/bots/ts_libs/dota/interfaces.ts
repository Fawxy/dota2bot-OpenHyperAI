/**
 * The Dota2 bot scriping interfaces from Valve. https://developer.valvesoftware.com/wiki/Dota_Bot_Scripting
 */

import { BotActionType, BotMode, DamageType, Lane, Team } from "./enums";

export interface Location {}

// https://developer.valvesoftware.com/wiki/Category:Vector
// update for add/sub/div later.
export interface Vector {
    x: number;
    y: number;
    z: number;
    Normalized(): Vector;
}

export interface Ping {
    time: number;
    location: Vector;
    normal_ping: boolean;
    player_id: number;
}

export interface Item {
    GetName(): string;
    GetCooldownTimeRemaining(): number;
    IsFullyCastable(): boolean;
}

export interface AvoidanceZone {
    location: Vector;
    ability: Ability;
    caster: Unit;
    radius: number;
    playerid: number;
}

export interface Unit {
    // Seems to be internal to bot script?
    frameProcessTime: number | null;
    assignedRole: number | null;
    DefendLaneDesire: number[] | null;
    laneToDefend: Lane;
    stateTetheredHero: Unit | null;

    IsNull(): boolean;

    CanBeSeen(): boolean;

    GetPrimaryAttribute(): number;

    GetAttributeValue(nAttr: number): number;

    GetPlayerID(): number;

    GetLocation(): Vector;

    /** World angle in degrees, 0 along +x. */
    GetFacing(): number;

    GetUnitName(): string;

    GetAbilityCount(): number;

    GetAbilityByIndex(index: number): Ability | null;
    GetAbilityInSlot(index: number): Ability | null;

    IsUsingAbility(): boolean;
    IsCastingAbility(): boolean;
    GetCurrentActiveAbility(): Ability | null;

    IsInvisible(): boolean;

    IsAlive(): boolean;

    IsBuilding(): boolean;

    IsHero(): boolean;

    IsInvulnerable(): boolean;

    IsBot(): boolean;

    GetAttackSpeed(): number;

    GetActualIncomingDamage(damage: number, damageType: DamageType): number;

    Action_AttackMove(location: Vector): void;

    IsCreep(): boolean;

    IsDominated(): boolean;

    IsIllusion(): boolean;

    IsMagicImmune(): boolean;

    NumModifiers(): number;

    GetModifierName(nModifier: number): string;

    GetModifierStackCount(nModifier: number): number;

    /** Returns a modifier index usable with GetModifierStackCount, or -1 when absent. */
    GetModifierByName(sName: string): number;

    GetDifficulty(): number;

    IsChanneling(): boolean;

    GetRespawnTime(): number;

    GetNearbyCreeps(range: number, enemy: boolean): Unit[];

    GetMostRecentPing(): Ping;

    GetLocation(): Vector;

    GetNearbyHeroes(range: number, includeEnemies: boolean, mode: BotMode): Unit[];
    GetNearbyNeutralCreeps(range: number, includeEnemies: boolean): Unit[];

    GetItemInSlot(slot: number): Item | null;
    NumQueuedActions(): number;

    GetQueuedActionType(index: number): BotActionType;

    GetAnimActivity(): number;

    Action_UseAbilityOnEntity(ability: Ability, target: Unit): void;

    Action_UseAbilityOnLocation(ability: Ability | Item, location: Location): void;

    Action_UseAbility(ability: Ability): void;
    Action_MoveToLocation(location: Vector): void;
    Action_AttackUnit(unit: Unit, once: boolean): void;

    GetAttackTarget(): Unit | null;
    GetTarget(): Unit | null;
    SetTarget(unit: Unit): void;

    GetTeam(): Team;

    GetLastAttackTime(): number;
    WasRecentlyDamagedByAnyHero(delta: number): boolean;
    WasRecentlyDamagedByTower(delta: number): boolean;
    WasRecentlyDamagedByCreep(delta: number): boolean;
    GetMaxHealth(): number;
    GetHealth(): number;
    GetHealthRegen(): number;
    GetMaxMana(): number;
    GetMana(): number;
    GetManaRegen(): number;

    GetLevel(): number;
    GetEstimatedDamageToTarget(bCurrentlyAvailable: boolean, hTarget: Unit, fDuration: number, nDamageTypes: number): number;
    IsAncientCreep(): boolean;
    HasModifier(modifierName: string): boolean;
    GetActiveMode(): number;
    GetAbilityByName(abilityName: string): Ability;
    GetAttackRange(): number;
    GetBoundingRadius(): number;
    GetCurrentVisionRange(): number;
    GetNetWorth(): number;
    FindItemSlot(itemName: string): number;
    GetNearbyLaneCreeps(radius: number, enemyTeam: boolean): Unit[];
    GetNearbyTowers(radius: number, enemyTeam: boolean): Unit[];
    GetAttackDamage(): number;
    GetActiveModeDesire(): number;
    GetGold(): number;
    GetCurrentMovementSpeed(): number;
    GetExtrapolatedLocation(seconds: number): Vector;
    Action_MovePath(path: Vector[]): void;
    GetAssignedLane(): Lane;
    ActionImmediate_Chat(message: string, globalChat: boolean): void;

    /** @param pingType Ping type, "!" if false, "X" otherwise, essentially works as ALT key */
    ActionImmediate_Ping(xCoord: number, yCoord: number, pingType: boolean): void;
}

export interface Ability {
    IsFullyCastable(): boolean;
    IsHidden(): boolean;

    GetCastRange(): number;

    IsNull(): boolean;

    GetName(): string;

    IsTrained(): boolean;

    IsActivated(): boolean;

    GetManaCost(): number;

    GetCooldownTimeRemaining(): number;
    GetLevel(): number;
    GetCooldown(): number;
    IsUltimate(): boolean;
    GetBehavior(): number;
}

export interface Talent {}
