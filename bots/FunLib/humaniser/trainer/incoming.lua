--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local UnitType = ____dota.UnitType
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local CreepKind = ____api.CreepKind
local T = ____api.T
local CACHE_SECONDS = 0.25
local ATTACK_ACTIVITY = 1503
local SIEGE_POINT = 0.292
local SIEGE_SWING = 0.699
local TOWER_PROJECTILE_FACTOR = 0.93
local NEARBY_RADIUS = 1600
local LIST_TYPES = {
    UnitType.AlliedCreeps,
    UnitType.EnemyCreeps,
    UnitType.AlliedHeroes,
    UnitType.EnemyHeroes,
    UnitType.AlliedBuildings,
    UnitType.EnemyBuildings
}
local cache = {}
local function unitsForTeam()
    local team = GetTeam()
    local now = GameTime()
    local entry = cache[team]
    if entry ~= nil and now - entry.at < CACHE_SECONDS and now >= entry.at then
        return entry.units
    end
    local units = {}
    for ____, listType in ipairs(LIST_TYPES) do
        for ____, u in ipairs(GetUnitList(listType)) do
            if u ~= nil and u ~= nil then
                units[#units + 1] = u
            end
        end
    end
    cache[team] = {at = now, units = units}
    return units
end
--- Allied and enemy creeps, heroes and towers within radius of loc. Lists are cached for 0.25 s per team.
function ____exports.NearbyUnits(loc, radius)
    local result = {}
    for ____, u in ipairs(unitsForTeam()) do
        if u:IsAlive() and GetUnitToLocationDistance(u, loc) <= radius then
            result[#result + 1] = u
        end
    end
    return result
end
--- Visible heroes of both teams, from the same cached lists.
function ____exports.Heroes()
    local result = {}
    for ____, u in ipairs(unitsForTeam()) do
        if u:IsHero() and not u:IsIllusion() then
            result[#result + 1] = u
        end
    end
    return result
end
function ____exports.Towers()
    local result = {}
    for ____, u in ipairs(unitsForTeam()) do
        if T(u):IsTower() and u:IsAlive() then
            result[#result + 1] = u
        end
    end
    return result
end
local function kindOf(u)
    if u:IsTower() then
        return "ranged"
    end
    if u:IsHero() then
        return (u:GetAttackRange() > 320 or u:GetUnitName() == "npc_dota_hero_templar_assassin") and "ranged" or "melee"
    end
    return CreepKind(u)
end
local function projectileSpeed(u)
    local speed = u:GetAttackProjectileSpeed()
    return u:IsTower() and speed * TOWER_PROJECTILE_FACTOR or speed
end
local function pushRepeating(hits, first, period, damage, ____repeat, horizon)
    local at = first
    while at <= horizon do
        hits[#hits + 1] = {
            at = math.max(at, 0),
            damage = damage
        }
        if not ____repeat or period <= 0 then
            break
        end
        at = at + period
    end
end
local function attackerHit(hits, attacker, creep, horizon)
    local kind = kindOf(attacker)
    local point = attacker:GetAttackPoint()
    local period = attacker:GetSecondsPerAttack()
    local cycle = attacker:GetAnimCycle()
    local dist = GetUnitToUnitDistance(attacker, creep)
    local damage = creep:GetActualIncomingDamage(
        attacker:GetAttackDamage(),
        DamageType.Physical
    )
    local travel = (kind == "ranged" or kind == "siege") and math.max(dist - 22, 0) / attacker:GetAttackProjectileSpeed() or 0
    local ____repeat = not attacker:IsHero()
    local first
    if kind == "siege" and attacker:GetAnimActivity() == ATTACK_ACTIVITY and cycle < SIEGE_POINT then
        first = (SIEGE_POINT - cycle) * SIEGE_SWING / SIEGE_POINT + travel
    elseif attacker:GetAnimActivity() == ATTACK_ACTIVITY and cycle < point then
        first = (point - cycle) * period + travel
    else
        local swingStart = math.max(
            attacker:GetLastAttackTime() + period - GameTime(),
            0
        )
        first = swingStart + point * period + travel
    end
    pushRepeating(
        hits,
        first,
        period,
        damage,
        ____repeat,
        horizon
    )
end
--- Damage other units will deal to creep within horizon seconds, excluding the subject's own attacks.
function ____exports.Hits(creep, subject, horizon)
    local hits = {}
    local target = T(creep)
    local loc = creep:GetLocation()
    for ____, p in ipairs(target:GetIncomingTrackingProjectiles()) do
        do
            local __continue33
            repeat
                if not p.is_attack or p.caster == nil or p.caster == nil or p.caster == subject then
                    __continue33 = true
                    break
                end
                local caster = T(p.caster)
                local travelTime = GetUnitToLocationDistance(creep, p.location) / projectileSpeed(caster)
                if travelTime > horizon then
                    __continue33 = true
                    break
                end
                hits[#hits + 1] = {
                    at = travelTime,
                    damage = creep:GetActualIncomingDamage(
                        caster:GetAttackDamage(),
                        DamageType.Physical
                    )
                }
                __continue33 = true
            until true
            if not __continue33 then
                break
            end
        end
    end
    for ____, u in ipairs(____exports.NearbyUnits(loc, NEARBY_RADIUS)) do
        do
            local __continue37
            repeat
                if u == subject or u == creep or u:GetAttackTarget() ~= creep then
                    __continue37 = true
                    break
                end
                attackerHit(
                    hits,
                    T(u),
                    target,
                    horizon
                )
                __continue37 = true
            until true
            if not __continue37 then
                break
            end
        end
    end
    table.sort(
        hits,
        function(a, b) return a.at < b.at end
    )
    return hits
end
return ____exports
