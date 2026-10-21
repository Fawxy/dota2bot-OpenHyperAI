--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local GameState = ____dota.GameState
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
local countersAt = {}
local heroTargetAt = {}
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
--- Hit by a hero, or attacked one, in the last PressureSeconds. Harassing is latched on time like the damage
-- window: turning to a creep must not end the pressure at once, or the last-hit answer would flip its own input.
local function isUnderPressure(bot)
    local seconds = ____exports.Settings().PressureSeconds
    local target = bot:GetAttackTarget()
    if target ~= nil and target ~= nil and target:IsHero() and target:GetTeam() ~= bot:GetTeam() then
        heroTargetAt[bot:GetPlayerID()] = GameTime()
    end
    if GameTime() - (heroTargetAt[bot:GetPlayerID()] or -math.huge) < seconds then
        return true
    end
    return bot:WasRecentlyDamagedByAnyHero(seconds)
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
            isDeny = isDeny
        }
        entries[creep] = entry
    end
    if not entry.attempt then
        return false
    end
    return ____exports.Upstream(
        creep,
        attackDamage * (1 + entry.eps * ____exports.ErrorWidth(bot)),
        delay,
        isDeny
    )
end
--- Call where the bot issues its last-hit or deny swing on a creep WillKill judged killable.
function ____exports.NoteAttempt(bot, creep)
    if not ____exports.IsActiveFor(bot) then
        return
    end
    local entry = entriesFor(bot)[creep]
    if entry ~= nil and entry.attempt then
        entry.attempted = true
    end
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
--- Resolves creeps that are gone. Kills are credited per tick: attempts of a kind that resolve in this tick count
-- as hits up to how far the bot's last-hit (or deny) counter moved since the last tick, and the rest as misses.
-- A kill the bot made by other means (a spell) can hide one miss; dead creeps it never swung at are dropped.
function ____exports.Tick(bot)
    if GetGameState() ~= GameState.GameInProgress or not ____exports.IsActiveFor(bot) then
        return
    end
    local pid = bot:GetPlayerID()
    local now = GameTime()
    if now - (tickedAt[pid] or -1) < TICK_SECONDS then
        return
    end
    tickedAt[pid] = now
    local current = {
        lastHits = counterOf(bot, false),
        denies = counterOf(bot, true)
    }
    local previous = countersAt[pid] or current
    countersAt[pid] = current
    local entries = entriesFor(bot)
    local lastHitAttempts = 0
    local denyAttempts = 0
    for creep, entry in pairs(entries) do
        do
            local __continue44
            repeat
                if not creep:IsNull() and creep:IsAlive() then
                    __continue44 = true
                    break
                end
                if entry.attempted then
                    if entry.isDeny then
                        denyAttempts = denyAttempts + 1
                    else
                        lastHitAttempts = lastHitAttempts + 1
                    end
                end
                entries[creep] = nil
                __continue44 = true
            until true
            if not __continue44 then
                break
            end
        end
    end
    local counts = ____exports.Counts(bot)
    counts.attempts = counts.attempts + (lastHitAttempts + denyAttempts)
    counts.misses = counts.misses + math.max(0, lastHitAttempts - (current.lastHits - previous.lastHits))
    counts.misses = counts.misses + math.max(0, denyAttempts - (current.denies - previous.denies))
end
return ____exports
