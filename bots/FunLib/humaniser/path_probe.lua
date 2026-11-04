--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ArraySlice(self, first, last)
    local len = #self
    first = first or 0
    if first < 0 then
        first = len + first
        if first < 0 then
            first = 0
        end
    else
        if first > len then
            first = len
        end
    end
    last = last or len
    if last < 0 then
        last = len + last
        if last < 0 then
            last = 0
        end
    else
        if last > len then
            last = len
        end
    end
    local out = {}
    first = first + 1
    last = last + 1
    local n = 1
    while first < last do
        out[n] = self[first]
        first = first + 1
        n = n + 1
    end
    return out
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
local Rune = ____dota.Rune
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local Rotate = require(GetScriptDirectory().."/FunLib/humaniser/states/rotate")
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
    print((((((((((((((((("[HEV] t=" .. string.format(
        "%.3f",
        DotaTime()
    )) .. " ev=pathprobe team=") .. tostring(team)) .. " from=") .. from) .. " v=") .. variant) .. " d=") .. tostring(math.floor(d))) .. " n=") .. tostring(#wp)) .. " min=") .. tostring(math.floor(min))) .. " tw=") .. tw) .. " wp=") .. pts)
end
local function hev(rest)
    print((("[HEV] t=" .. string.format(
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
function ____exports.Run(bot)
    local team = bot:GetTeam()
    if done[team] == true or DotaTime() < 30 then
        return
    end
    done[team] = true
    hev(("team=" .. tostring(team)) .. " step=begin")
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    local to = guard(
        "shrine",
        function() return Rotate.ShrineFor(enemy) end
    )
    local towers = guard(
        "towers",
        function() return FR.TowerSpots(enemy) end
    ) or ({})
    if to == nil then
        return
    end
    hev((((((("team=" .. tostring(team)) .. " step=inputs towers=") .. table.concat(
        __TS__ArrayMap(
            towers,
            function(____, t) return (tostring(math.floor(t.x)) .. ",") .. tostring(math.floor(t.y)) end
        ),
        ";"
    )) .. " to=") .. tostring(math.floor(to.x))) .. ",") .. tostring(math.floor(to.y)))
    hev((("team=" .. tostring(team)) .. " step=pass pass=") .. tostring(guard(
        "passable",
        function() return IsLocationPassable(to) end
    )))
    local lane = team == Team.Dire and Vector(-5800, 5000, 0) or Vector(5800, -5000, 0)
    local starts = {
        {"lane", lane},
        {
            "rune0",
            guard(
                "rune0",
                function() return GetRuneSpawnLocation(Rune.Power1) end
            )
        },
        {
            "rune1",
            guard(
                "rune1",
                function() return GetRuneSpawnLocation(Rune.Power2) end
            )
        },
        {
            "bot",
            bot:GetLocation()
        }
    }
    local vecs = __TS__ArrayMap(
        towers,
        function(____, t) return Vector(t.x, t.y, 1000) end
    )
    local variants = {{"none", {}}, {"vec", vecs}}
    local handle = guard(
        "zone",
        function()
            local ____AddAvoidanceZone_6 = AddAvoidanceZone
            local ____Vector_5 = Vector
            local ____opt_0 = towers[1]
            local ____temp_4 = ____opt_0 and ____opt_0.x or 0
            local ____opt_2 = towers[1]
            return ____AddAvoidanceZone_6(
                ____Vector_5(____temp_4, ____opt_2 and ____opt_2.y or 0, 1000),
                30
            )
        end
    )
    hev((((("team=" .. tostring(team)) .. " step=zone h=") .. tostring(handle)) .. " type=") .. type(handle))
    if handle ~= nil then
        local handles = {
            handle,
            unpack(__TS__ArrayMap(
                __TS__ArraySlice(towers, 1),
                function(____, t) return guard(
                    "zone",
                    function() return AddAvoidanceZone(
                        Vector(t.x, t.y, 1000),
                        30
                    ) end
                ) end
            ))
        }
        variants[#variants + 1] = {
            "handle",
            __TS__ArrayFilter(
                handles,
                function(____, h) return h ~= nil end
            )
        }
    end
    for ____, ____value in ipairs(starts) do
        local name = ____value[1]
        local start = ____value[2]
        do
            local __continue27
            repeat
                if start == nil then
                    __continue27 = true
                    break
                end
                for ____, ____value in ipairs(variants) do
                    local v = ____value[1]
                    local avoid = ____value[2]
                    guard(
                        (("gen:" .. name) .. ":") .. v,
                        function() return GeneratePath(
                            start,
                            to,
                            avoid,
                            function(d, wp)
                                guard(
                                    (("cb:" .. name) .. ":") .. v,
                                    function() return report(
                                        team,
                                        name,
                                        v,
                                        start,
                                        towers,
                                        d,
                                        wp or ({})
                                    ) end
                                )
                            end
                        ) end
                    )
                    hev((((("team=" .. tostring(team)) .. " step=called from=") .. name) .. " v=") .. v)
                end
                __continue27 = true
            until true
            if not __continue27 then
                break
            end
        end
    end
end
return ____exports
