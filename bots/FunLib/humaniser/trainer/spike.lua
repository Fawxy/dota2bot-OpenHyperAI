--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/trainer/settings")
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local GetTrainerHelpers = ____api.GetTrainerHelpers
local T = ____api.T
local ____draw = require(GetScriptDirectory().."/FunLib/humaniser/trainer/draw")
local Bars = ____draw.Bars
local LOG_INTERVAL = 0.5
local LOOP_SECONDS = 2.5
local MOCK_LEAD = 1.5
local MOCK_WINDOW = 0.4
local NEAR_CREEP = 900
local lastLogAt = -math.huge
local lastCallAt
local function read(fn)
    local ok, value = pcall(fn)
    return ok and tostring(value) or ("ERR(" .. tostring(value)) .. ")"
end
local function nearestCreep(subject)
    local best
    local bestDist = NEAR_CREEP
    for ____, creep in ipairs(GetUnitList(UnitType.EnemyCreeps)) do
        do
            local __continue4
            repeat
                if creep == nil or creep == nil or not creep:IsAlive() then
                    __continue4 = true
                    break
                end
                local d = GetUnitToUnitDistance(subject, creep)
                if d <= bestDist then
                    best = creep
                    bestDist = d
                end
                __continue4 = true
            until true
            if not __continue4 then
                break
            end
        end
    end
    return best
end
--- A mock countdown on a loop: 1.5 s of lead, then a 0.4 s window, then 0.6 s after it closes.
local function drawBars(subject, creep, now)
    local loopStart = now - now % LOOP_SECONDS
    local open = loopStart + MOCK_LEAD
    local mock = {
        creep = creep,
        isDeny = false,
        uncertain = false,
        startOpen = open,
        startClose = open + MOCK_WINDOW
    }
    Bars(subject, {mock}, now)
end
local function logReadings(subject, target, gap)
    local s = T(subject)
    local parts = {
        "target=" .. (target ~= nil and target ~= nil and target:GetUnitName() or "-"),
        "lastAttack=" .. read(function() return s:GetLastAttackTime() end),
        "anim=" .. read(function() return s:GetAnimActivity() end),
        "cycle=" .. read(function() return s:GetAnimCycle() end),
        "point=" .. read(function() return s:GetAttackPoint() end),
        "as=" .. read(function() return s:GetAttackSpeed() end),
        "spa=" .. read(function() return s:GetSecondsPerAttack() end),
        "dmg=" .. read(function() return s:GetAttackDamage() end),
        "lh=" .. read(function() return s:GetLastHits() end),
        "dn=" .. read(function() return s:GetDenies() end)
    }
    local helpers = GetTrainerHelpers()
    if target ~= nil and target ~= nil and helpers ~= nil then
        parts[#parts + 1] = "proDelay=" .. read(function() return helpers.GetAttackProDelayTime(subject, target) end)
    end
    parts[#parts + 1] = "frameGap=" .. string.format("%.3f", gap)
    HDebug.Log(
        "trainer",
        "spike",
        unpack(parts)
    )
end
function ____exports.SpikeTick(_bot, subject)
    local now = GameTime()
    local gap = lastCallAt == nil and 0 or now - lastCallAt
    lastCallAt = now
    if now - lastLogAt >= LOG_INTERVAL then
        lastLogAt = now
        logReadings(
            subject,
            subject:GetAttackTarget(),
            gap
        )
    end
    local creep = nearestCreep(subject)
    if creep ~= nil then
        drawBars(subject, creep, now)
    end
    local cfg = Settings.Get()
    DebugDrawText(
        cfg.TextX,
        cfg.TextY,
        "ASCII - test",
        255,
        255,
        255
    )
    DebugDrawText(
        cfg.TextX,
        cfg.TextY + 14,
        "unicode – − test",
        255,
        255,
        255
    )
end
return ____exports
