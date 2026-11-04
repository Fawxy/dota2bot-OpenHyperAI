--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
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
function ____exports.Run(bot)
    local team = bot:GetTeam()
    if done[team] == true or DotaTime() < 30 then
        return
    end
    done[team] = true
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    local to = Rotate.ShrineFor(enemy)
    local towers = FR.TowerSpots(enemy)
    local lane = team == Team.Dire and Vector(-5800, 5000, 0) or Vector(5800, -5000, 0)
    local starts = {
        {"lane", lane},
        {
            "rune0",
            GetRuneSpawnLocation(Rune.Power1)
        },
        {
            "rune1",
            GetRuneSpawnLocation(Rune.Power2)
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
    local handles = __TS__ArrayMap(
        towers,
        function(____, t) return AddAvoidanceZone(
            Vector(t.x, t.y, 1000),
            30
        ) end
    )
    print((((((((((("[HEV] t=" .. string.format(
        "%.3f",
        DotaTime()
    )) .. " ev=pathprobe team=") .. tostring(team)) .. " towers=") .. table.concat(
        __TS__ArrayMap(
            towers,
            function(____, t) return (tostring(math.floor(t.x)) .. ",") .. tostring(math.floor(t.y)) end
        ),
        ";"
    )) .. " to=") .. tostring(math.floor(to.x))) .. ",") .. tostring(math.floor(to.y))) .. " pass=") .. tostring(IsLocationPassable(to) and 1 or 0))
    for ____, ____value in ipairs(starts) do
        local name = ____value[1]
        local start = ____value[2]
        for ____, ____value in ipairs({{"none", {}}, {"vec", vecs}, {"handle", handles}}) do
            local v = ____value[1]
            local avoid = ____value[2]
            local ok, err = pcall(function() return GeneratePath(
                start,
                to,
                avoid,
                function(d, wp) return report(
                    team,
                    name,
                    v,
                    start,
                    towers,
                    d,
                    wp or ({})
                ) end
            ) end)
            if not ok then
                print((((((((("[HEV] t=" .. string.format(
                    "%.3f",
                    DotaTime()
                )) .. " ev=pathprobe team=") .. tostring(team)) .. " from=") .. name) .. " v=") .. v) .. " err=") .. (string.gsub(
                    tostring(err),
                    " ",
                    "_"
                )))
            end
        end
    end
end
return ____exports
