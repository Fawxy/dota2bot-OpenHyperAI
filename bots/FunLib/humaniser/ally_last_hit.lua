--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local cached, nearbyEnemyHeroes, enemyHeroesByPlayer
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function cached(store, key, compute)
    local now = DotaTime()
    local entry = store[key]
    if entry ~= nil and entry.time == now then
        return entry.value
    end
    local value = compute()
    store[key] = {time = now, value = value}
    return value
end
function nearbyEnemyHeroes(bot)
    return cached(
        enemyHeroesByPlayer,
        bot:GetPlayerID(),
        function() return bot:GetNearbyHeroes(1600, true, BotMode.None) end
    )
end
____exports.DEFAULTS = {
    ProtectPositions = {1, 2, 3},
    OwnFarmPositions = {1, 2},
    ProtectRange = 1000,
    PoliteMin = 0.75,
    HelpfulMin = 0.4,
    MissRules = {polite = {AwayBuffer = 400, IdleSeconds = 6, DenyRace = false, Busy = false}, helpful = {AwayBuffer = 150, IdleSeconds = 3, DenyRace = true, Busy = false}, teammate = {AwayBuffer = 75, IdleSeconds = 1.5, DenyRace = true, Busy = true}},
    ApproachLookahead = 0.5,
    ApproachEpsilon = 25,
    DeniableHealth = 0.5,
    HarassInterval = 2.5,
    HarassWindow = 1.2,
    HarassExtraRange = 300,
    HarassMinHP = 0.5,
    TowerAvoidRange = 850
}
local helpers = {}
local settings
local humansByTeam = {}
enemyHeroesByPlayer = {}
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
        local overrides = Config.Get().AllyLastHit or ({})
        for k, v in pairs(overrides) do
            result[k] = v
        end
        local rules = {}
        for tier, rule in pairs(____exports.DEFAULTS.MissRules) do
            local merged = {}
            for k, v in pairs(rule) do
                merged[k] = v
            end
            local ____opt_0 = overrides.MissRules
            if ____opt_0 ~= nil then
                ____opt_0 = ____opt_0[tier]
            end
            local o = ____opt_0
            if o ~= nil and type(o) == "table" then
                for k, v in pairs(o) do
                    merged[k] = v
                end
            end
            rules[tier] = merged
        end
        result.MissRules = rules
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
    local ____temp_2
    if helpers.IsInLaningPhase ~= nil then
        ____temp_2 = helpers.IsInLaningPhase()
    else
        ____temp_2 = DotaTime() < 600
    end
    return ____temp_2
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
                        local __continue26
                        repeat
                            local member = GetTeamMember(i)
                            if member == nil or member == nil or not member:IsAlive() or member:IsIllusion() then
                                __continue26 = true
                                break
                            end
                            if IsPlayerBot(member:GetPlayerID()) then
                                __continue26 = true
                                break
                            end
                            if contains(
                                positions,
                                positionOf(member)
                            ) then
                                result[#result + 1] = member
                            end
                            __continue26 = true
                        until true
                        if not __continue26 then
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
--- A handle Dota no longer backs (IsNull), or a dead unit. Fakes without IsNull count as live.
local function stale(u)
    return u.IsNull ~= nil and u:IsNull() or not u:IsAlive()
end
function ____exports.GetProtectedHuman(bot, location)
    if not Config.IsFeatureEnabled("AllyLastHit") then
        return nil, "free: disabled"
    end
    if not inLaningPhase() then
        return nil, "free: not-laning"
    end
    if location == nil or location == nil then
        return nil, "free: no-location"
    end
    local s = ____exports.Settings()
    local nearest
    local nearestDist = s.ProtectRange
    for ____, human in ipairs(protectedHumans(bot)) do
        do
            local __continue35
            repeat
                if stale(human) then
                    __continue35 = true
                    break
                end
                local dist = GetUnitToLocationDistance(human, location)
                if dist <= nearestDist then
                    nearest = human
                    nearestDist = dist
                end
                __continue35 = true
            until true
            if not __continue35 then
                break
            end
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
local function canHumanReach(human, creep, rule)
    local s = ____exports.Settings()
    local dist = GetUnitToUnitDistance(human, creep)
    if dist <= human:GetAttackRange() + rule.AwayBuffer then
        return true
    end
    local ahead = GetUnitToLocationDistance(
        creep,
        human:GetExtrapolatedLocation(s.ApproachLookahead)
    )
    return ahead < dist - s.ApproachEpsilon
end
--- Whether an allied core can take `creep` itself: within its attack range plus the helpful tier's buffer, or walking
-- towards it. Bot supports judge their bot cores from the creep, not from their own position (laning mode).
function ____exports.CoreCanReach(core, creep)
    return canHumanReach(
        core,
        creep,
        ____exports.Settings().MissRules.helpful
    )
end
local function isAboutToBeDenied(bot, creep)
    if creep:GetHealth() >= creep:GetMaxHealth() * ____exports.Settings().DeniableHealth then
        return false
    end
    for ____, enemy in ipairs(nearbyEnemyHeroes(bot)) do
        if enemy:GetAttackTarget() == creep then
            return true
        end
    end
    return false
end
local function isAttackingHero(bot, human)
    local target = human:GetAttackTarget()
    if target == nil or target == nil then
        return false
    end
    for ____, enemy in ipairs(nearbyEnemyHeroes(bot)) do
        if enemy == target then
            return true
        end
    end
    return false
end
--- Why the human is going to miss `creep` under this tier's rules, or undefined if they should get it.
local function missReason(bot, human, creep, tier)
    local rule = ____exports.Settings().MissRules[tier]
    if not canHumanReach(human, creep, rule) then
        return "human-away"
    end
    if GameTime() - human:GetLastAttackTime() > rule.IdleSeconds then
        return "human-idle"
    end
    if rule.DenyRace and isAboutToBeDenied(bot, creep) then
        return "deny-race"
    end
    if rule.Busy and isAttackingHero(bot, human) then
        return "human-busy"
    end
    return nil
end
local function decide(bot, human, creep, tier)
    if human:GetAttackTarget() == creep then
        return false, "skip: human-target"
    end
    local miss = missReason(bot, human, creep, tier)
    if miss == nil then
        return false, "skip: " .. tier
    end
    return true, "take: " .. miss
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
    if creep == nil or creep == nil or stale(creep) then
        return false, "skip: invalid"
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
    Telemetry.NoteLastHitDecision(bot, creep, allowed, reason)
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
