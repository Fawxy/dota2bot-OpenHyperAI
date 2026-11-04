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
local rounds = {}
local asked = {}
local function hev(rest)
    out((("[HEV] t=" .. string.format(
        "%.3f",
        DotaTime()
    )) .. " ev=pathprobe ") .. rest)
end
local function nearest(reqs, p, pick)
    local best = -1
    local bestD = math.huge
    for ____, r in ipairs(reqs) do
        local d = FR.Dist(
            pick(r),
            p
        )
        if d < bestD then
            best, bestD = r.pid, d
        end
    end
    return {
        best,
        math.floor(bestD)
    }
end
function ____exports.Run(bot)
    local now = DotaTime()
    if now < 30 or now > 90 then
        return
    end
    local round = math.floor((now - 30) / 10)
    local pid = bot:GetPlayerID()
    local k = (tostring(round) .. ":") .. tostring(pid)
    if asked[k] == true then
        return
    end
    asked[k] = true
    local enemy = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
    local ____temp_1 = rounds[round] or ({})
    rounds[round] = ____temp_1
    local reqs = ____temp_1
    local req = {
        pid = pid,
        from = bot:GetLocation(),
        to = Rotate.ShrineFor(enemy),
        ret = "?"
    }
    reqs[#reqs + 1] = req
    local frame = now
    local ok, ret = pcall(function() return GeneratePath(
        req.from,
        req.to,
        {},
        function(...)
            local args = {...}
            local nums = table.concat(
                __TS__ArrayMap(
                    __TS__ArrayFilter(
                        args,
                        function(____, a) return type(a) == "number" end
                    ),
                    function(____, a) return string.format("%.0f", a) end
                ),
                ","
            )
            local wp = __TS__ArrayFind(
                args,
                function(____, a) return type(a) == "table" end
            )
            if wp == nil or #wp == 0 then
                hev((((((("r=" .. tostring(round)) .. " pid=") .. tostring(pid)) .. " nowp n=") .. tostring(#args)) .. " nums=") .. nums)
                return
            end
            local sp, sd = unpack(nearest(
                reqs,
                wp[1],
                function(r) return r.from end
            ))
            local gp, gd = unpack(nearest(
                reqs,
                wp[#wp],
                function(r) return r.to end
            ))
            local own0 = math.floor(FR.Dist(wp[1], req.from))
            local ownN = math.floor(FR.Dist(wp[#wp], req.to))
            hev((((((((((((((((((((((((("r=" .. tostring(round)) .. " pid=") .. tostring(pid)) .. " n=") .. tostring(#wp)) .. " nums=") .. nums) .. " ret=") .. req.ret) .. " lag=") .. string.format(
                "%.2f",
                DotaTime() - frame
            )) .. " own0=") .. tostring(own0)) .. " ownN=") .. tostring(ownN)) .. " start_pid=") .. tostring(sp)) .. " start_d=") .. tostring(sd)) .. " goal_pid=") .. tostring(gp)) .. " goal_d=") .. tostring(gd)) .. " reqs=") .. tostring(#reqs))
        end
    ) end)
    req.ret = ok and tostring(ret) or "err:" .. (string.gsub(
        tostring(ret),
        " ",
        "_"
    ))
    hev((((((((((("r=" .. tostring(round)) .. " pid=") .. tostring(pid)) .. " ask from=") .. tostring(math.floor(req.from.x))) .. ",") .. tostring(math.floor(req.from.y))) .. " ret=") .. req.ret) .. " frame=") .. string.format("%.3f", frame))
end
return ____exports
