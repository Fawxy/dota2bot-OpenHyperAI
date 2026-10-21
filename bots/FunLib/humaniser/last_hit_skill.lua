--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
____exports.DEFAULTS = {
    RequireOwnedLaning = true,
    ErrorLow = 0.15,
    ErrorHigh = 0.02,
    AttemptLow = 0.75,
    AttemptHigh = 0.98,
    DenyAttemptLow = 0.35,
    DenyAttemptHigh = 0.9,
    PressureMult = 1.5,
    PressureSeconds = 2,
    RangedPrioritySkill = 0.6
}
local helpers = {}
local settings
local entriesByPlayer = {}
local ownedLaning = {}
local warned = {}
local widthCache = {}
local countsByPlayer = {}
local tickedAt = {}
local TICK_SECONDS = 0.25
function ____exports.SetHelpers(h)
    helpers = h
end
function ____exports.Settings()
    if settings == nil then
        local result = {}
        for k, v in pairs(____exports.DEFAULTS) do
            result[k] = v
        end
        local overrides = Config.Get().LastHitSkill or ({})
        for k, v in pairs(overrides) do
            result[k] = v
        end
        settings = result
    end
    return settings
end
local function lerp(low, high, skill)
    return low + (high - low) * skill
end
--- Records whether OHA owns this bot's laning Think(); warns once when the feature can do nothing for it.
function ____exports.NoteLaningOwner(bot, owned)
    local pid = bot:GetPlayerID()
    ownedLaning[pid] = owned
    if owned or warned[pid] == true then
        return
    end
    if not Config.IsFeatureEnabled("LastHitSkill") or not ____exports.Settings().RequireOwnedLaning then
        return
    end
    warned[pid] = true
    print(((("[Humaniser] LastHitSkill: pid=" .. tostring(pid)) .. " ") .. bot:GetUnitName()) .. " is on Valve laning; no effect (set Lane.OwnLaningThink='all')")
end
function ____exports.IsActiveFor(bot)
    if not Config.IsFeatureEnabled("LastHitSkill") then
        return false
    end
    if Profile.Get(bot).skill >= 1 then
        return false
    end
    if Trainer.IsSelfTestBot(bot) then
        return false
    end
    return not ____exports.Settings().RequireOwnedLaning or ownedLaning[bot:GetPlayerID()] == true
end
local function isUnderPressure(bot)
    if bot:WasRecentlyDamagedByAnyHero(____exports.Settings().PressureSeconds) then
        return true
    end
    local target = bot:GetAttackTarget()
    return target ~= nil and target ~= nil and target:IsHero() and target:GetTeam() ~= bot:GetTeam()
end
--- The current error half-width e, pressure included.
function ____exports.ErrorWidth(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local hit = widthCache[pid]
    if hit ~= nil and hit.time == now then
        return hit.value
    end
    local s = ____exports.Settings()
    local e = lerp(
        s.ErrorLow,
        s.ErrorHigh,
        Profile.Get(bot).skill
    )
    if isUnderPressure(bot) then
        e = e * s.PressureMult
    end
    widthCache[pid] = {time = now, value = e}
    return e
end
function ____exports.Upstream(creep, attackDamage, delay, isDeny)
    if isDeny then
        return creep:GetHealth() <= attackDamage
    end
    return helpers.WillKillTarget ~= nil and helpers.WillKillTarget(creep, attackDamage, DamageType.Physical, delay)
end
local function entriesFor(bot)
    local pid = bot:GetPlayerID()
    local entries = entriesByPlayer[pid]
    if entries == nil then
        entries = setmetatable({}, {__mode = "k"})
        entriesByPlayer[pid] = entries
    end
    return entries
end
local function counterOf(bot, isDeny)
    return isDeny and bot:GetDenies() or bot:GetLastHits()
end
function ____exports.WillKill(bot, creep, attackDamage, delay, isDeny)
    if not ____exports.IsActiveFor(bot) then
        return ____exports.Upstream(creep, attackDamage, delay, isDeny)
    end
    local entries = entriesFor(bot)
    local entry = entries[creep]
    if entry == nil then
        local s = ____exports.Settings()
        local skill = Profile.Get(bot).skill
        local rate = isDeny and lerp(s.DenyAttemptLow, s.DenyAttemptHigh, skill) or lerp(s.AttemptLow, s.AttemptHigh, skill)
        local eps = RandomFloat(-1, 1)
        entry = {
            eps = eps,
            attempt = RandomFloat(0, 1) < rate,
            attempted = false,
            isDeny = isDeny,
            countAtAttempt = 0
        }
        entries[creep] = entry
    end
    if not entry.attempt then
        return false
    end
    local kills = ____exports.Upstream(
        creep,
        attackDamage * (1 + entry.eps * ____exports.ErrorWidth(bot)),
        delay,
        isDeny
    )
    if kills and not entry.attempted then
        entry.attempted = true
        entry.countAtAttempt = counterOf(bot, isDeny)
    end
    return kills
end
local function isRangedOrSiege(creep)
    local name = creep:GetUnitName()
    return (string.find(name, "ranged", 1, true)) ~= nil or (string.find(name, "siege", 1, true)) ~= nil
end
--- Which of several creeps killable together to take: the first, unless skill is high enough to prefer ranged.
function ____exports.Choose(bot, killable)
    local skill = Profile.Get(bot).skill
    if ____exports.IsActiveFor(bot) and skill > ____exports.Settings().RangedPrioritySkill then
        for ____, creep in ipairs(killable) do
            if isRangedOrSiege(creep) then
                return creep
            end
        end
    end
    return killable[1]
end
function ____exports.Counts(bot)
    local pid = bot:GetPlayerID()
    local counts = countsByPlayer[pid]
    if counts == nil then
        counts = {attempts = 0, misses = 0}
        countsByPlayer[pid] = counts
    end
    return counts
end
--- Resolves creeps that are gone: an attempt the bot's own last-hit (or deny) count did not move for is a miss.
-- Dead creeps the bot never went for are dropped uncounted.
function ____exports.Tick(bot)
    if not ____exports.IsActiveFor(bot) then
        return
    end
    local pid = bot:GetPlayerID()
    local now = GameTime()
    if now - (tickedAt[pid] or -1) < TICK_SECONDS then
        return
    end
    tickedAt[pid] = now
    local entries = entriesFor(bot)
    local counts = ____exports.Counts(bot)
    for creep, entry in pairs(entries) do
        do
            local __continue41
            repeat
                if not creep:IsNull() and creep:IsAlive() then
                    __continue41 = true
                    break
                end
                if entry.attempted then
                    counts.attempts = counts.attempts + 1
                    if counterOf(bot, entry.isDeny) == entry.countAtAttempt then
                        counts.misses = counts.misses + 1
                    end
                end
                entries[creep] = nil
                __continue41 = true
            until true
            if not __continue41 then
                break
            end
        end
    end
end
return ____exports
