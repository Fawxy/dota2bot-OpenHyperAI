--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local Rotate = require(GetScriptDirectory().."/FunLib/humaniser/states/rotate")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local ____Utils_RawPrint_0 = Utils.RawPrint
if ____Utils_RawPrint_0 == nil then
    ____Utils_RawPrint_0 = print
end
local out = ____Utils_RawPrint_0
local done = {}
local function segDist(a, b, p)
    local dx = b.x - a.x
    local dy = b.y - a.y
    local l2 = dx * dx + dy * dy
    local k = l2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)
    ) or 0
    local cx = a.x + k * dx - p.x
    local cy = a.y + k * dy - p.y
    return math.sqrt(cx * cx + cy * cy)
end
local function report(team, from, variant, start, towers, d, wp)
    local min = math.huge
    local which = -1
    local a = start
    for ____, p in ipairs({unpack(wp)}) do
        do
            local i = 0
            while i < #towers do
                local s = segDist(a, p, towers[i + 1])
                if s < min then
                    min, which = s, i
                end
                i = i + 1
            end
        end
        a = p
    end
    local pts = table.concat(
        __TS__ArrayMap(
            wp,
            function(____, p) return (tostring(math.floor(p.x)) .. ",") .. tostring(math.floor(p.y)) end
        ),
        ";"
    )
    local tw = which >= 0 and (tostring(math.floor(towers[which + 1].x)) .. ",") .. tostring(math.floor(towers[which + 1].y)) or "-"
    out((((((((((((((((("[HEV] t=" .. string.format(
        "%.3f",
        DotaTime()
    )) .. " ev=pathprobe team=") .. tostring(team)) .. " from=") .. from) .. " v=") .. variant) .. " d=") .. tostring(math.floor(d))) .. " n=") .. tostring(#wp)) .. " min=") .. tostring(math.floor(min))) .. " tw=") .. tw) .. " wp=") .. pts)
end
local function hev(rest)
    out((("[HEV] t=" .. string.format(
        "%.3f",
        DotaTime()
    )) .. " ev=pathprobe ") .. rest)
end
local function guard(step, f)
    local ok, v = pcall(f)
    if not ok then
        hev((("step=" .. step) .. " err=") .. (string.gsub(
            tostring(v),
            " ",
            "_"
        )))
        return nil
    end
    return v
end
local queue = {}
function ____exports.Run(bot)
    local next = table.remove(queue, 1)
    if next ~= nil then
        next()
    end
    local team = bot:GetTeam()
    if done[team] == true or DotaTime() < 30 then
        return
    end
    done[team] = true
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    local to = Rotate.ShrineFor(enemy)
    local towers = FR.TowerSpots(enemy)
    local starts = team == Team.Radiant and ({
        {
            "safe",
            Vector(4025, -6225, 0)
        },
        {
            "lane",
            Vector(5004, -4874, 0)
        }
    }) or ({
        {
            "safe",
            Vector(-4002, 5473, 0)
        },
        {
            "lane",
            Vector(-4601, 4782, 0)
        }
    })
    local vecs = __TS__ArrayMap(
        towers,
        function(____, t) return Vector(t.x, t.y, 1100) end
    )
    local handles = __TS__ArrayMap(
        towers,
        function(____, t) return guard(
            "zone",
            function() return AddAvoidanceZone(
                Vector(t.x, t.y, 1100),
                120
            ) end
        ) end
    )
    hev((("team=" .. tostring(team)) .. " step=zones h=") .. table.concat(
        __TS__ArrayMap(
            handles,
            function(____, h) return tostring(h) end
        ),
        ","
    ))
    for ____, ____value in ipairs(starts) do
        local name = ____value[1]
        local start = ____value[2]
        for ____, ____value in ipairs({
            {"none", {}},
            {"vec", vecs},
            {
                "handle",
                __TS__ArrayFilter(
                    handles,
                    function(____, h) return h ~= nil end
                )
            }
        }) do
            local v = ____value[1]
            local avoid = ____value[2]
            queue[#queue + 1] = function() return guard(
                (("gen:" .. name) .. ":") .. v,
                function() return GeneratePath(
                    start,
                    to,
                    avoid,
                    function(...)
                        local args = {...}
                        local wp = __TS__ArrayFind(
                            args,
                            function(____, x) return type(x) == "table" end
                        )
                        local d = __TS__ArrayFind(
                            args,
                            function(____, x) return type(x) == "number" end
                        )
                        if wp ~= nil then
                            guard(
                                (("cb:" .. name) .. ":") .. v,
                                function() return report(
                                    team,
                                    name,
                                    v,
                                    start,
                                    towers,
                                    d or -1,
                                    wp
                                ) end
                            )
                        else
                            hev((((((("team=" .. tostring(team)) .. " from=") .. name) .. " v=") .. v) .. " nowp n=") .. tostring(#args))
                        end
                    end
                ) end
            ) end
        end
    end
end
return ____exports
