--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- The grid step: 64 is the gridnav cell.
local STEP = 64
--- The box when GetWorldBounds is missing: the 7.33+ map's playable area lies inside it. `judgement`.
local FALLBACK_HALF = 10240
local TREE_BATCH = 100
local TREE_GAP = 400
local phase = "start"
local frameAt
local box = {x0 = -FALLBACK_HALF, y0 = -FALLBACK_HALF, x1 = FALLBACK_HALF, y1 = FALLBACK_HALF}
local rowY = 0
local rows = 0
local treeAt = 0
local treeMiss = 0
local trees = 0
local function bounds()
    if GetWorldBounds == nil then
        return {box, "fallback"}
    end
    local ok, raw = pcall(GetWorldBounds)
    if not ok or type(raw) ~= "table" then
        return {box, "fallback"}
    end
    local b = raw
    if type(b[1]) ~= "number" or type(b[4]) ~= "number" then
        return {box, "fallback"}
    end
    return {{x0 = b[1], y0 = b[2], x1 = b[3], y1 = b[4]}, "api"}
end
local function cell(x, y)
    local v = Vector(x, y, 0)
    local okH, h = pcall(GetHeightLevel, v)
    local okP, p = pcall(IsLocationPassable, v)
    local level = okH and type(h) == "number" and math.max(
        0,
        math.min(
            7,
            math.floor(h)
        )
    ) or 0
    return level + (okP and p == true and 8 or 0)
end
local function row()
    local x0 = math.floor(box.x0 / STEP) * STEP
    local n = math.floor((box.x1 - x0) / STEP) + 1
    local hex = ""
    do
        local i = 0
        while i < n do
            hex = hex .. string.format(
                "%x",
                cell(x0 + i * STEP, rowY)
            )
            i = i + 1
        end
    end
    Telemetry.Event("vmap", {
        {"kind", "h"},
        {"y", rowY},
        {"x0", x0},
        {"n", n},
        {"hex", hex}
    })
    rows = rows + 1
    rowY = rowY + STEP
end
local function treeBatch()
    local parts = {}
    do
        local k = 0
        while k < TREE_BATCH and treeMiss < TREE_GAP do
            do
                local __continue10
                repeat
                    local ok, loc = pcall(GetTreeLocation, treeAt)
                    if not ok or loc == nil or loc == nil then
                        treeMiss = treeMiss + 1
                        __continue10 = true
                        break
                    end
                    treeMiss = 0
                    trees = trees + 1
                    parts[#parts + 1] = (((tostring(treeAt) .. ":") .. tostring(math.floor(loc.x))) .. ":") .. tostring(math.floor(loc.y))
                    __continue10 = true
                until true
                if not __continue10 then
                    break
                end
            end
            do
                k = k + 1
                treeAt = treeAt + 1
            end
        end
    end
    if #parts > 0 then
        Telemetry.Event(
            "vmap",
            {
                {"kind", "t"},
                {
                    "xy",
                    table.concat(parts, ";")
                }
            }
        )
    end
end
function ____exports.Tick(bot)
    if phase == "done" or bot:GetTeam() ~= Team.Radiant or Overrides.Get("VisionMap") ~= true then
        return
    end
    local now = GameTime()
    if now == frameAt then
        return
    end
    frameAt = now
    if phase == "start" then
        local b, src = unpack(bounds())
        box = b
        rowY = math.floor(box.y0 / STEP) * STEP
        Telemetry.Event("vmap", {
            {"kind", "start"},
            {"bx0", box.x0},
            {"by0", box.y0},
            {"bx1", box.x1},
            {"by1", box.y1},
            {"step", STEP},
            {"src", src}
        })
        phase = "h"
    elseif phase == "h" then
        row()
        if rowY > box.y1 then
            phase = "t"
        end
    elseif phase == "t" then
        treeBatch()
        if treeMiss >= TREE_GAP then
            phase = "end"
        end
    else
        Telemetry.Event("vmap", {{"kind", "end"}, {"rows", rows}, {"trees", trees}})
        phase = "done"
    end
end
return ____exports
