--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local BotScriptEnums = ____dota.BotScriptEnums
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
____exports.DEFAULTS = {
    ProtectPositions = {1, 2, 3},
    OwnFarmPositions = {1, 2},
    ProtectRange = 1000,
    PoliteMin = 0.75,
    HelpfulMin = 0.4,
    OutOfRangeBuffer = 150,
    IdleSeconds = 3,
    ApproachLookahead = 0.5,
    ApproachEpsilon = 25,
    DeniableHealth = 0.5,
    SwingRangeBuffer = 50,
    HarassInterval = 2.5,
    HarassWindow = 1.2,
    HarassExtraRange = 300,
    HarassMinHP = 0.5,
    TowerAvoidRange = 850
}
local helpers = {}
local settings
local humansByTeam = {}
local enemyHeroesByPlayer = {}
local enemyCreepsByPlayer = {}
local lastSkipByPlayer = {}
function ____exports.SetHelpers(h)
    helpers = h
end
function ____exports.Settings()
    if settings == nil then
        local result = {}
        for k, v in pairs(____exports.DEFAULTS) do
            result[k] = v
        end
        for k, v in pairs(Config.Get().AllyLastHit or ({})) do
            result[k] = v
        end
        settings = result
    end
    return settings
end
local function contains(list, value)
    if value == nil then
        return false
    end
    for ____, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end
local function positionOf(unit)
    return helpers.GetPosition ~= nil and helpers.GetPosition(unit) or nil
end
local function inLaningPhase()
    local ____temp_0
    if helpers.IsInLaningPhase ~= nil then
        ____temp_0 = helpers.IsInLaningPhase()
    else
        ____temp_0 = DotaTime() < 600
    end
    return ____temp_0
end
local function cached(store, key, compute)
    local now = DotaTime()
    local entry = store[key]
    if entry ~= nil and entry.time == now then
        return entry.value
    end
    local value = compute()
    store[key] = {time = now, value = value}
    return value
end
--- True when this bot's laning Think() should be owned by OHA so etiquette can apply. Evaluated at file load.
function ____exports.OwnsLaning(bot)
    return Config.IsFeatureEnabled("AllyLastHit") and Difficulty.IsAllyOfHuman(bot)
end
function ____exports.GetTier(bot)
    local s = ____exports.Settings()
    local d = Profile.Get(bot).deference
    if d >= s.PoliteMin then
        return "polite"
    end
    if d >= s.HelpfulMin then
        return "helpful"
    end
    return "teammate"
end
local function protectedHumans(bot)
    local team = bot:GetTeam()
    return cached(
        humansByTeam,
        team,
        function()
            local result = {}
            local positions = ____exports.Settings().ProtectPositions
            local players = GetTeamPlayers(team)
            do
                local i = 1
                while i <= #players do
                    do
                        local __continue22
                        repeat
                            local member = GetTeamMember(i)
                            if member == nil or member == nil or not member:IsAlive() or member:IsIllusion() then
                                __continue22 = true
                                break
                            end
                            if IsPlayerBot(member:GetPlayerID()) then
                                __continue22 = true
                                break
                            end
                            if contains(
                                positions,
                                positionOf(member)
                            ) then
                                result[#result + 1] = member
                            end
                            __continue22 = true
                        until true
                        if not __continue22 then
                            break
                        end
                    end
                    i = i + 1
                end
            end
            return result
        end
    )
end
--- The protected human nearest to `location` within ProtectRange, or undefined with the "free:" reason
-- explaining why etiquette does not apply.
function ____exports.GetProtectedHuman(bot, location)
    if not Config.IsFeatureEnabled("AllyLastHit") then
        return nil, "free: disabled"
    end
    if not inLaningPhase() then
        return nil, "free: not-laning"
    end
    local s = ____exports.Settings()
    local nearest
    local nearestDist = s.ProtectRange
    for ____, human in ipairs(protectedHumans(bot)) do
        local dist = GetUnitToLocationDistance(human, location)
        if dist <= nearestDist then
            nearest = human
            nearestDist = dist
        end
    end
    if nearest == nil then
        return nil, "free: no-human"
    end
    if contains(
        s.OwnFarmPositions,
        positionOf(bot)
    ) and nearest:GetAssignedLane() ~= bot:GetAssignedLane() then
        return nil, "free: own-lane"
    end
    return nearest, ""
end
local function isAttackAnimation(unit)
    local activity = unit:GetAnimActivity()
    return activity == ACTIVITY_ATTACK or activity == ACTIVITY_ATTACK2
end
local function canHumanReach(human, creep)
    local s = ____exports.Settings()
    local dist = GetUnitToUnitDistance(human, creep)
    if dist <= human:GetAttackRange() + s.OutOfRangeBuffer then
        return true
    end
    local ahead = GetUnitToLocationDistance(
        creep,
        human:GetExtrapolatedLocation(s.ApproachLookahead)
    )
    return ahead < dist - s.ApproachEpsilon
end
local function isAboutToBeDenied(bot, creep)
    if creep:GetHealth() >= creep:GetMaxHealth() * ____exports.Settings().DeniableHealth then
        return false
    end
    local enemies = cached(
        enemyHeroesByPlayer,
        bot:GetPlayerID(),
        function() return bot:GetNearbyHeroes(1600, true, BotMode.None) end
    )
    for ____, enemy in ipairs(enemies) do
        if enemy:GetAttackTarget() == creep then
            return true
        end
    end
    return false
end
local function isLowestInHumanRange(bot, human, creep)
    local range = human:GetAttackRange() + ____exports.Settings().SwingRangeBuffer
    local creeps = cached(
        enemyCreepsByPlayer,
        bot:GetPlayerID(),
        function() return bot:GetNearbyLaneCreeps(1600, true) end
    )
    local lowest
    for ____, c in ipairs(creeps) do
        do
            local __continue45
            repeat
                if not c:IsAlive() or GetUnitToUnitDistance(human, c) > range then
                    __continue45 = true
                    break
                end
                if lowest == nil or c:GetHealth() < lowest:GetHealth() then
                    lowest = c
                end
                __continue45 = true
            until true
            if not __continue45 then
                break
            end
        end
    end
    return lowest == creep
end
local function decide(bot, human, creep, tier)
    if tier == "polite" then
        return false, "skip: polite"
    end
    if human:GetAttackTarget() == creep then
        return false, "skip: human-target"
    end
    if tier == "helpful" then
        if not canHumanReach(human, creep) then
            return true, "take: human-away"
        end
        if GameTime() - human:GetLastAttackTime() > ____exports.Settings().IdleSeconds then
            return true, "take: human-idle"
        end
        if isAboutToBeDenied(bot, creep) then
            return true, "take: deny-race"
        end
        return false, "skip: helpful"
    end
    if isAttackAnimation(human) and isLowestInHumanRange(bot, human, creep) then
        return false, "skip: human-swing"
    end
    return true, "take: teammate"
end
local function showOverlay(bot, tier, allowed, reason)
    if not HDebug.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    if not allowed then
        lastSkipByPlayer[pid] = (reason .. " @") .. string.format(
            "%.0f",
            DotaTime()
        )
    end
    HDebug.Text(
        bot,
        "lasthit",
        (((tier .. " d=") .. string.format(
            "%.2f",
            Profile.Get(bot).deference
        )) .. " ") .. (lastSkipByPlayer[pid] or "-")
    )
end
--- May `bot` take the last hit on `creep`? Allied creeps (denies) are always allowed.
function ____exports.MayLastHit(bot, creep)
    if not Config.IsFeatureEnabled("AllyLastHit") then
        return true, "free: disabled"
    end
    if creep:GetTeam() == bot:GetTeam() then
        return true, "free: deny"
    end
    local human, freeReason = ____exports.GetProtectedHuman(
        bot,
        creep:GetLocation()
    )
    if human == nil then
        return true, freeReason
    end
    local tier = ____exports.GetTier(bot)
    local allowed, reason = decide(bot, human, creep, tier)
    showOverlay(bot, tier, allowed, reason)
    return allowed, reason
end
--- Returns `creeps` unchanged when etiquette is off for this bot, otherwise only the creeps it may hit.
function ____exports.FilterCreeps(bot, creeps)
    if not Config.IsFeatureEnabled("AllyLastHit") or not Difficulty.IsAllyOfHuman(bot) then
        return creeps
    end
    local result = {}
    for ____, creep in ipairs(creeps) do
        local allowed = ____exports.MayLastHit(bot, creep)
        if allowed then
            result[#result + 1] = creep
        end
    end
    return result
end
return ____exports
