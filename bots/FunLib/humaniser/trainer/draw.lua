--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/trainer/settings")
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local DrawLine = ____api.DrawLine
local ____predict = require(GetScriptDirectory().."/FunLib/humaniser/trainer/predict")
local HORIZON = ____predict.HORIZON
local STEP = ____predict.STEP
local LINE_HEIGHT = 14
local MAX_LINES = 3
local LINE_SECONDS = 6
local SUMMARY_OFFSET = 50
local SUMMARY_SECONDS = 15
local function colour(kind)
    if kind == "PERFECT" then
        return {0, 255, 0}
    end
    if kind == "OK" then
        return {255, 255, 255}
    end
    if kind == "CANCELLED" then
        return {160, 160, 160}
    end
    return {255, 140, 0}
end
function ____exports.VerdictLines(lines, now)
    local cfg = Settings.Get()
    local fresh = __TS__ArrayFilter(
        lines,
        function(____, l) return now - l.at < LINE_SECONDS end
    )
    local first = math.max(#fresh - MAX_LINES, 0)
    do
        local i = first
        while i < #fresh do
            local r, g, b = unpack(colour(fresh[i + 1].kind))
            DebugDrawText(
                cfg.TextX,
                cfg.TextY + LINE_HEIGHT * (i - first),
                fresh[i + 1].text,
                r,
                g,
                b
            )
            i = i + 1
        end
    end
end
function ____exports.SummaryText(lines, shownAt, now)
    if now - shownAt >= SUMMARY_SECONDS then
        return
    end
    local cfg = Settings.Get()
    do
        local i = 0
        while i < #lines do
            DebugDrawText(
                cfg.TextX,
                cfg.TextY + SUMMARY_OFFSET + LINE_HEIGHT * i,
                lines[i + 1],
                255,
                255,
                255
            )
            i = i + 1
        end
    end
end
local BAR_Z = 180
local BAR_WIDTH = 160
local TICK_HEIGHT = 16
local BAR_MAX_DISTANCE = 1200
local GREY = {128, 128, 128}
local WHITE = {255, 255, 255}
local BLUE = {80, 160, 255}
local function windowColour(p)
    if p.isDeny then
        return {0, 255, 255}
    end
    if p.uncertain then
        return {255, 191, 0}
    end
    return {0, 255, 0}
end
--- Live timing bars over each predicted creep: the start window on a 2 s axis ("time"), or the creep's HP axis with the landing marker ("hp").
function ____exports.Bars(subject, preds, style, now, swingStart)
    if not subject:IsAlive() then
        return
    end
    local target = subject:GetAttackTarget()
    local ____temp_0
    if target == nil or target == nil then
        ____temp_0 = nil
    else
        ____temp_0 = tostring(target)
    end
    local targetId = ____temp_0
    for ____, p in ipairs(preds) do
        do
            local __continue17
            repeat
                local creep = p.creep
                if not creep:IsAlive() or GetUnitToUnitDistance(subject, creep) > BAR_MAX_DISTANCE then
                    __continue17 = true
                    break
                end
                local loc = creep:GetLocation()
                local left = loc.x - BAR_WIDTH / 2
                local z = loc.z + BAR_Z
                local y = loc.y
                local function hline(from, to, c, dz)
                    return DrawLine(
                        Vector(from, y, z + dz),
                        Vector(to, y, z + dz),
                        c[1],
                        c[2],
                        c[3]
                    )
                end
                local function tick(x, c)
                    return DrawLine(
                        Vector(x, y, z),
                        Vector(x, y, z + TICK_HEIGHT),
                        c[1],
                        c[2],
                        c[3]
                    )
                end
                local colour = windowColour(p)
                if style == "time" then
                    local function xAt(t)
                        return left + BAR_WIDTH * math.max(
                            0,
                            math.min(1, (t - now) / HORIZON)
                        )
                    end
                    hline(left, left + BAR_WIDTH, GREY, TICK_HEIGHT / 2)
                    local open = xAt(p.startOpen)
                    local close = xAt(p.startClose)
                    if close > open then
                        hline(open, close, colour, TICK_HEIGHT / 2 + 2)
                        tick(open, colour)
                        tick(close, colour)
                    end
                    tick(left, WHITE)
                    if swingStart ~= nil and targetId == tostring(creep) then
                        tick(
                            xAt(swingStart),
                            BLUE
                        )
                    end
                else
                    local maxHp = creep:GetMaxHealth()
                    local function xHp(hp)
                        return left + BAR_WIDTH * math.max(
                            0,
                            math.min(1, hp / maxHp)
                        )
                    end
                    hline(
                        left,
                        xHp(p.hp),
                        GREY,
                        TICK_HEIGHT / 2
                    )
                    tick(
                        xHp(p.effDmg),
                        WHITE
                    )
                    local index = math.min(
                        math.floor(p.delay / STEP + 0.5),
                        #p.curve - 1
                    )
                    tick(
                        xHp(p.curve[index + 1]),
                        colour
                    )
                end
                __continue17 = true
            until true
            if not __continue17 then
                break
            end
        end
    end
end
return ____exports
