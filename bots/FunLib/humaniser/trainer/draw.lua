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
local CreepKind = ____api.CreepKind
local DrawLine = ____api.DrawLine
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
local BAR_WIDTH = 200
local TICK_HEIGHT = 16
local MARKER_HEIGHT = 32
local BAR_MAX_DISTANCE = 1200
--- Units per second. The swing line sits LINE_OFFSET from the left, so the bar shows 0.75 s of window behind it and 1.75 s of countdown ahead.
local SCALE = 80
local LINE_OFFSET = 60
local GREY = {128, 128, 128}
local WHITE = {255, 255, 255}
local BLUE = {80, 160, 255}
local YELLOW = {255, 255, 0}
local RED = {255, 60, 60}
local STATE_OFFSET = 150
--- Inside this many seconds before the window opens, the word switches from WAIT to READY.
local READY_LEAD = 0.3
--- One word for what the bar is showing now, so the bar can be checked against plain text.
function ____exports.BarState(p, now)
    if now < p.startOpen - READY_LEAD then
        return "WAIT"
    end
    if now < p.startOpen then
        return "READY"
    end
    if now <= p.startClose then
        return p.isDeny and "DENY" or "ATTACK"
    end
    return "LATE"
end
local function windowColour(p)
    if p.isDeny then
        return {0, 255, 255}
    end
    if p.uncertain then
        return {255, 191, 0}
    end
    return {0, 255, 0}
end
--- Countdown bar over each predicted creep. The white swing line never moves; the window is drawn
-- from that line leftwards, its length the window's duration. The tall marker is now, sliding left
-- at real-time speed: it crosses the line as the window opens and leaves the zone as it closes.
function ____exports.Bars(subject, preds, now, swingStart)
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
    local cfg = Settings.Get()
    local row = 0
    for ____, p in ipairs(preds) do
        do
            local __continue21
            repeat
                local creep = p.creep
                if not creep:IsAlive() or GetUnitToUnitDistance(subject, creep) > BAR_MAX_DISTANCE then
                    __continue21 = true
                    break
                end
                local loc = creep:GetLocation()
                local left = loc.x - BAR_WIDTH / 2
                local right = left + BAR_WIDTH
                local line = left + LINE_OFFSET
                local z = loc.z + BAR_Z
                local y = loc.y
                local function clamp(x)
                    return math.max(
                        left,
                        math.min(right, x)
                    )
                end
                local function xAt(t)
                    return clamp(line + (p.startOpen - t) * SCALE)
                end
                local function hline(from, to, c, dz)
                    return DrawLine(
                        Vector(from, y, z + dz),
                        Vector(to, y, z + dz),
                        c[1],
                        c[2],
                        c[3]
                    )
                end
                local function tick(x, c, height)
                    if height == nil then
                        height = TICK_HEIGHT
                    end
                    return DrawLine(
                        Vector(x, y, z),
                        Vector(x, y, z + height),
                        c[1],
                        c[2],
                        c[3]
                    )
                end
                local colour = windowColour(p)
                hline(left, right, GREY, TICK_HEIGHT / 2)
                local windowEnd = clamp(line - (p.startClose - p.startOpen) * SCALE)
                if windowEnd < line then
                    hline(windowEnd, line, colour, TICK_HEIGHT / 2 + 2)
                    tick(windowEnd, colour)
                end
                tick(line, WHITE)
                local marker = now < p.startOpen and YELLOW or (now <= p.startClose and colour or RED)
                tick(
                    xAt(now),
                    marker,
                    MARKER_HEIGHT
                )
                local state = ____exports.BarState(p, now)
                local r, g, b = unpack(state == "READY" and WHITE or marker)
                DebugDrawText(
                    cfg.TextX,
                    cfg.TextY + STATE_OFFSET + LINE_HEIGHT * row,
                    (CreepKind(creep) .. ": ") .. state,
                    r,
                    g,
                    b
                )
                row = row + 1
                if swingStart ~= nil and targetId == tostring(creep) then
                    tick(
                        xAt(swingStart),
                        BLUE
                    )
                end
                __continue21 = true
            until true
            if not __continue21 then
                break
            end
        end
    end
end
return ____exports
