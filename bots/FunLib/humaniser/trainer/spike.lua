--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/trainer/settings")
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local DrawLine = ____api.DrawLine
local GetTrainerHelpers = ____api.GetTrainerHelpers
local T = ____api.T
local LOG_INTERVAL = 0.5
local BAR_WIDTH = 160
local BAR_HEIGHT_ABOVE = 180
local TICK_HEIGHT = 16
local HP_BAR_OFFSET = 40
local WINDOW_WIDTH = 40
local LOOP_SECONDS = 2
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
local function hLine(x0, x1, y, z, r, g, b)
    DrawLine(
        Vector(x0, y, z),
        Vector(x1, y, z),
        r,
        g,
        b
    )
end
local function vTick(x, y, z, height, r, g, b)
    DrawLine(
        Vector(x, y, z - height / 2),
        Vector(x, y, z + height / 2),
        r,
        g,
        b
    )
end
local function drawBars(creep, now)
    local loc = creep:GetLocation()
    local left = loc.x - BAR_WIDTH / 2
    local right = loc.x + BAR_WIDTH / 2
    local z = loc.z + BAR_HEIGHT_ABOVE
    local phase = now % LOOP_SECONDS / LOOP_SECONDS
    hLine(
        left,
        right,
        loc.y,
        z,
        128,
        128,
        128
    )
    vTick(
        left,
        loc.y,
        z,
        TICK_HEIGHT,
        255,
        255,
        255
    )
    vTick(
        right,
        loc.y,
        z,
        TICK_HEIGHT,
        128,
        128,
        128
    )
    local centre = right - phase * BAR_WIDTH
    local winLeft = math.max(left, centre - WINDOW_WIDTH / 2)
    local winRight = math.min(right, centre + WINDOW_WIDTH / 2)
    if winRight > winLeft then
        hLine(
            winLeft,
            winRight,
            loc.y,
            z,
            0,
            255,
            0
        )
        vTick(
            winLeft,
            loc.y,
            z,
            TICK_HEIGHT,
            0,
            255,
            0
        )
        vTick(
            winRight,
            loc.y,
            z,
            TICK_HEIGHT,
            0,
            255,
            0
        )
    end
    local hpZ = z + HP_BAR_OFFSET
    hLine(
        left,
        right,
        loc.y,
        hpZ,
        128,
        128,
        128
    )
    hLine(
        left,
        left + (1 - phase) * BAR_WIDTH,
        loc.y,
        hpZ,
        0,
        255,
        0
    )
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
        drawBars(creep, now)
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
