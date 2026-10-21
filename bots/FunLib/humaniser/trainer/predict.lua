--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local GetTrainerHelpers = ____api.GetTrainerHelpers
local MainSlotType = ____api.MainSlotType
local T = ____api.T
local ____incoming = require(GetScriptDirectory().."/FunLib/humaniser/trainer/incoming")
local Hits = ____incoming.Hits
____exports.STEP = 0.05
____exports.HORIZON = 2
local SAMPLES = math.floor(____exports.HORIZON / ____exports.STEP + 0.5) + 1
local EPSILON = 0.000001
local SMOOTH_FRAMES = 3
local HISTORY_SECONDS = 0.5
local JUMP_AGE = 0.3
local JUMP_SIZE = 0.15
local MIN_WINDOW = 0.1
local SHORT_WINDOW_LEAD = 0.05
--- curve[i] is the creep's HP at i * STEP seconds from now. Hits landing on the same sample merge into one drop.
function ____exports.BuildCurve(hp, regen, hits)
    local curve = {}
    local applied = 0
    local lost = 0
    do
        local i = 0
        while i < SAMPLES do
            local t = i * ____exports.STEP
            while applied < #hits and hits[applied + 1].at <= t + EPSILON do
                lost = lost + hits[applied + 1].damage
                applied = applied + 1
            end
            curve[#curve + 1] = hp + regen * t - lost
            i = i + 1
        end
    end
    return curve
end
--- Start times, relative to now, at which the subject's attack lands after the creep is low enough but before anyone else kills it.
function ____exports.KillWindow(curve, effDmg, delay, startFloor)
    local tOther = ____exports.HORIZON + ____exports.STEP
    local tLandMin
    do
        local i = 0
        while i < #curve do
            local t = i * ____exports.STEP
            if tLandMin == nil and curve[i + 1] <= effDmg then
                tLandMin = t
            end
            if curve[i + 1] <= 0 then
                tOther = t
                break
            end
            i = i + 1
        end
    end
    if tLandMin == nil or tLandMin >= tOther then
        return nil
    end
    local open = math.max(tLandMin - delay, startFloor or -math.huge)
    local close = tOther - delay
    if open >= close then
        return nil
    end
    return {open = open, close = close}
end
____exports.Smoother = __TS__Class()
local Smoother = ____exports.Smoother
Smoother.name = "Smoother"
function Smoother.prototype.____constructor(self)
    self.history = {}
end
function Smoother.prototype.Push(self, now, open, close)
    local ____self_history_0 = self.history
    ____self_history_0[#____self_history_0 + 1] = {t = now, open = open, close = close}
    while #self.history > 1 and now - self.history[1].t > HISTORY_SECONDS do
        table.remove(self.history, 1)
    end
    local count = math.min(SMOOTH_FRAMES, #self.history)
    local openSum = 0
    local closeSum = 0
    do
        local i = #self.history - count
        while i < #self.history do
            openSum = openSum + self.history[i + 1].open
            closeSum = closeSum + self.history[i + 1].close
            i = i + 1
        end
    end
    local uncertain = false
    for ____, s in ipairs(self.history) do
        do
            local __continue15
            repeat
                if now - s.t < JUMP_AGE then
                    __continue15 = true
                    break
                end
                local openMoved = open > now and s.open > s.t and math.abs(open - s.open) > JUMP_SIZE
                if openMoved or math.abs(close - s.close) > JUMP_SIZE then
                    uncertain = true
                end
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
    return {open = openSum / count, close = closeSum / count, uncertain = uncertain}
end
function ____exports.EffectiveDamage(subject, creep, isDeny)
    local unit = T(subject)
    local dmg = unit:GetAttackDamage()
    if not isDeny and unit:GetItemSlotType(unit:FindItemSlot("item_quelling_blade")) == MainSlotType() then
        local ranged = unit:GetAttackRange() > 310 or unit:GetUnitName() == "npc_dota_hero_templar_assassin"
        dmg = dmg + (ranged and 4 or 8)
    end
    return creep:GetActualIncomingDamage(dmg, DamageType.Physical)
end
local function denyFloor(curve, maxHp)
    do
        local i = 0
        while i < #curve do
            if curve[i + 1] < maxHp / 2 then
                return i * ____exports.STEP
            end
            i = i + 1
        end
    end
    return nil
end
function ____exports.Predict(subject, creep, isDeny, now, smoother)
    local helpers = GetTrainerHelpers()
    if helpers == nil then
        return nil
    end
    local hp = creep:GetHealth()
    local curve = ____exports.BuildCurve(
        hp,
        creep:GetHealthRegen(),
        Hits(creep, subject, ____exports.HORIZON)
    )
    local effDmg = ____exports.EffectiveDamage(subject, creep, isDeny)
    local delay = helpers.GetAttackProDelayTime(subject, creep)
    local floor
    if isDeny then
        floor = denyFloor(
            curve,
            creep:GetMaxHealth()
        )
        if floor == nil then
            return nil
        end
    end
    local window = ____exports.KillWindow(curve, effDmg, delay, floor)
    if window == nil then
        return nil
    end
    local smoothed = smoother:Push(now, now + window.open, now + window.close)
    local ideal = smoothed.close - smoothed.open < MIN_WINDOW and smoothed.open + SHORT_WINDOW_LEAD or (smoothed.open + smoothed.close) / 2
    return {
        creep = creep,
        isDeny = isDeny,
        startOpen = smoothed.open,
        startClose = smoothed.close,
        ideal = ideal,
        uncertain = smoothed.uncertain,
        delay = delay,
        effDmg = effDmg,
        hp = hp,
        curve = curve,
        at = now
    }
end
return ____exports
