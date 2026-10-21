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
return ____exports
