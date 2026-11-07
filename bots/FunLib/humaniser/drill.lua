--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end

local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ClassExtends(target, base)
    target.____super = base
    local staticMetatable = setmetatable({__index = base}, base)
    setmetatable(target, staticMetatable)
    local baseMetatable = getmetatable(base)
    if baseMetatable then
        if type(baseMetatable.__index) == "function" then
            staticMetatable.__index = baseMetatable.__index
        end
        if type(baseMetatable.__newindex) == "function" then
            staticMetatable.__newindex = baseMetatable.__newindex
        end
    end
    setmetatable(target.prototype, base.prototype)
    if type(base.prototype.__index) == "function" then
        target.prototype.__index = base.prototype.__index
    end
    if type(base.prototype.__newindex) == "function" then
        target.prototype.__newindex = base.prototype.__newindex
    end
    if type(base.prototype.__tostring) == "function" then
        target.prototype.__tostring = base.prototype.__tostring
    end
end

local Error, RangeError, ReferenceError, SyntaxError, TypeError, URIError
do
    local function getErrorStack(self, constructor)
        if debug == nil then
            return nil
        end
        local level = 1
        while true do
            local info = debug.getinfo(level, "f")
            level = level + 1
            if not info then
                level = 1
                break
            elseif info.func == constructor then
                break
            end
        end
        if __TS__StringIncludes(_VERSION, "Lua 5.0") then
            return debug.traceback(("[Level " .. tostring(level)) .. "]")
        else
            return debug.traceback(nil, level)
        end
    end
    local function wrapErrorToString(self, getDescription)
        return function(self)
            local description = getDescription(self)
            local caller = debug.getinfo(3, "f")
            local isClassicLua = __TS__StringIncludes(_VERSION, "Lua 5.0") or _VERSION == "Lua 5.1"
            if isClassicLua or caller and caller.func ~= error then
                return description
            else
                return (description .. "\n") .. tostring(self.stack)
            end
        end
    end
    local function initErrorClass(self, Type, name)
        Type.name = name
        return setmetatable(
            Type,
            {__call = function(____, _self, message) return __TS__New(Type, message) end}
        )
    end
    local ____initErrorClass_1 = initErrorClass
    local ____class_0 = __TS__Class()
    ____class_0.name = ""
    function ____class_0.prototype.____constructor(self, message)
        if message == nil then
            message = ""
        end
        self.message = message
        self.name = "Error"
        self.stack = getErrorStack(nil, self.constructor.new)
        local metatable = getmetatable(self)
        if metatable and not metatable.__errorToStringPatched then
            metatable.__errorToStringPatched = true
            metatable.__tostring = wrapErrorToString(nil, metatable.__tostring)
        end
    end
    function ____class_0.prototype.__tostring(self)
        return self.message ~= "" and (self.name .. ": ") .. self.message or self.name
    end
    Error = ____initErrorClass_1(nil, ____class_0, "Error")
    local function createErrorClass(self, name)
        local ____initErrorClass_3 = initErrorClass
        local ____class_2 = __TS__Class()
        ____class_2.name = ____class_2.name
        __TS__ClassExtends(____class_2, Error)
        function ____class_2.prototype.____constructor(self, ...)
            ____class_2.____super.prototype.____constructor(self, ...)
            self.name = name
        end
        return ____initErrorClass_3(nil, ____class_2, name)
    end
    RangeError = createErrorClass(nil, "RangeError")
    ReferenceError = createErrorClass(nil, "ReferenceError")
    SyntaxError = createErrorClass(nil, "SyntaxError")
    TypeError = createErrorClass(nil, "TypeError")
    URIError = createErrorClass(nil, "URIError")
end

local function __TS__ObjectGetOwnPropertyDescriptors(object)
    local metatable = getmetatable(object)
    if not metatable then
        return {}
    end
    return rawget(metatable, "_descriptors") or ({})
end

local function __TS__Delete(target, key)
    local descriptors = __TS__ObjectGetOwnPropertyDescriptors(target)
    local descriptor = descriptors[key]
    if descriptor then
        if not descriptor.configurable then
            error(
                __TS__New(
                    TypeError,
                    ((("Cannot delete property " .. tostring(key)) .. " of ") .. tostring(target)) .. "."
                ),
                0
            )
        end
        descriptors[key] = nil
        return true
    end
    target[key] = nil
    return true
end

local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local controlRep
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function controlRep(d, n)
    return d.rep.control ~= nil and d.rep.control > 0 and n % d.rep.control == 0
end
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
local SAFE_CORE = {r = {1}}
local ALL = {r = {
    1,
    2,
    3,
    4,
    5
}, d = {
    1,
    2,
    3,
    4,
    5
}}
--- The drill table. Names match dotactl's recipes.json `drills`. A slice whose drill has no entry adds it here (and a
-- recipe when it needs reset steps or a later `--until`).
____exports.TABLE = {
    ["lane-spot"] = {
        note = "Radiant pos1 lane-only, everyone else benched",
        cast = SAFE_CORE,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-statue"] = {
        note = "Radiant pos1 lane-only, Dire pos3 a statue in its lane, everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-duel"] = {
        note = "Radiant pos1 and Dire pos3 lane-only, everyone else benched",
        cast = {r = {1}, d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-only"] = {
        note = "every hero lane-only (the last-hit harness)",
        cast = ALL,
        others = "play",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    stack = {
        note = "Radiant pos5 alone, a stack attempt every minute from 2:00",
        cast = {r = {5}},
        others = "bench",
        rep = {every = 60, from = 120},
        forces = "stack",
        overrides = {StackFar = true}
    }
}
local function overrides()
    return Customize.Overrides
end
--- The active drill's name, or undefined (no drill, or a name the table does not hold).
function ____exports.Name()
    local ____opt_0 = overrides()
    local n = ____opt_0 and ____opt_0.Drill
    return type(n) == "string" and ____exports.TABLE[n] ~= nil and n or nil
end
--- The active drill's entry, or undefined.
function ____exports.Active()
    local n = ____exports.Name()
    local ____temp_2
    if n == nil then
        ____temp_2 = nil
    else
        ____temp_2 = ____exports.TABLE[n]
    end
    return ____temp_2
end
local function listed(s, team, pos)
    if s == nil or pos == nil then
        return false
    end
    local ____temp_3
    if team == Team.Radiant then
        ____temp_3 = s.r
    else
        ____temp_3 = s.d
    end
    local list = ____temp_3
    return list ~= nil and __TS__ArrayIndexOf(list, pos) >= 0
end
--- The bot's role in the active drill: `play` when no drill is on. A hero whose position is not known yet plays.
function ____exports.RoleOf(bot)
    local d = ____exports.Active()
    if d == nil then
        return "play"
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil then
        return "play"
    end
    if listed(
        d.cast,
        bot:GetTeam(),
        pos
    ) then
        return "cast"
    end
    if listed(
        d.statue,
        bot:GetTeam(),
        pos
    ) then
        return "statue"
    end
    return d.others
end
--- Benched or a statue: the hero holds farm mode above every other mode, takes the drill's step and never casts.
function ____exports.Held(bot)
    local r = ____exports.RoleOf(bot)
    return r == "bench" or r == "statue"
end
--- Lane-only: the cast of an entry with `castLaneOnly`, or another hero under `others: "laneonly"`.
function ____exports.LaneOnly(bot)
    local r = ____exports.RoleOf(bot)
    local d = ____exports.Active()
    return d ~= nil and (r == "cast" and d.castLaneOnly == true or r == "laneonly")
end
--- True while any hero of the active drill is lane-only (the old global LaneOnly, for callers with no bot).
function ____exports.AnyLaneOnly()
    local d = ____exports.Active()
    return d ~= nil and (d.castLaneOnly == true or d.others == "laneonly")
end
--- An Overrides key the active drill implies, or undefined.
function ____exports.Implied(key)
    local ____opt_6 = ____exports.Active()
    local ____opt_4 = ____opt_6 and ____opt_6.overrides
    return ____opt_4 and ____opt_4[key]
end
local FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6928, 6372, 392}}
local STATUE_BEHIND = -300
local STATUE_SWAY = 40
local statueSide = {}
--- The held hero's step: a benched hero walks to its fountain and waits; a statue walks to its lane spot behind its own
-- creeps and sways there. False when the hero is not held.
function ____exports.Hold(bot)
    local r = ____exports.RoleOf(bot)
    if r == "bench" then
        local x, y, z = unpack(FOUNTAIN[bot:GetTeam()])
        local f = Vector(x, y, z)
        if GetUnitToLocationDistance(bot, f) > 300 then
            bot:Action_MoveToLocation(f)
        end
        return true
    end
    if r ~= "statue" then
        return false
    end
    local lane = bot:GetAssignedLane()
    local spot = GetLaneFrontLocation(
        bot:GetTeam(),
        lane,
        STATUE_BEHIND
    )
    local pid = bot:GetPlayerID()
    local side = statueSide[pid] or 1
    local target = Vector(spot.x + side * STATUE_SWAY * 0.5, spot.y, spot.z)
    if GetUnitToLocationDistance(bot, target) < 15 then
        side = -side
        statueSide[pid] = side
        target = Vector(spot.x + side * STATUE_SWAY * 0.5, spot.y, spot.z)
    end
    bot:Action_MoveToLocation(target)
    return true
end
--- The active drill's rep start times for a forced context (DotaTime seconds, up to 60:00), input-on reps only.
function ____exports.RepTimes(context)
    local d = ____exports.Active()
    if d == nil or d.forces ~= context then
        return nil
    end
    local out = {}
    local n = 0
    do
        local t = d.rep.from
        while t <= 3600 do
            n = n + 1
            if not controlRep(d, n) then
                out[#out + 1] = t
            end
            t = t + d.rep.every
        end
    end
    return out
end
--- The rep (1-based) that `t` falls in, or 0 before the first.
function ____exports.RepAt(t)
    local d = ____exports.Active()
    if d == nil or t < d.rep.from then
        return 0
    end
    return math.floor((t - d.rep.from) / d.rep.every) + 1
end
local lastRep = {}
local lastRole = {}
--- Per hero per frame: the role line when it changes, and the team's rep line once per rep from its first cast hero. Only
-- from the pregame on: strategy time runs its own clock up to 0 before the pregame resets it to -90, so a line logged then
-- would fall in another game of the log store and fire rep 1 early (drill1, 08/11/2026).
function ____exports.Tick(bot)
    local state = GetGameState()
    if state ~= GameState.PreGame and state ~= GameState.GameInProgress then
        return
    end
    local name = ____exports.Name()
    if name == nil then
        local ____opt_8 = overrides()
        local asked = ____opt_8 and ____opt_8.Drill
        if type(asked) == "string" and asked ~= "" and lastRole[-1] ~= asked then
            lastRole[-1] = asked
            Telemetry.Event("drill", {{"ph", "unknown"}, {"name", asked}})
        end
        return
    end
    local d = ____exports.TABLE[name]
    local pid = bot:GetPlayerID()
    local role = ____exports.RoleOf(bot)
    local pos = LaneConfig.PositionOf(bot)
    if lastRole[pid] ~= role then
        lastRole[pid] = role
        Telemetry.Event(
            "drill",
            {
                {"ph", "role"},
                {"name", name},
                {"pid", pid},
                {
                    "team",
                    bot:GetTeam()
                },
                {"pos", pos},
                {"role", role}
            }
        )
    end
    if role ~= "cast" then
        return
    end
    local now = DotaTime()
    local rep = ____exports.RepAt(now)
    local team = bot:GetTeam()
    if rep == 0 or lastRep[team] == rep then
        return
    end
    lastRep[team] = rep
    local start = d.rep.from + (rep - 1) * d.rep.every
    Telemetry.Event(
        "drill",
        {
            {"ph", "rep"},
            {"name", name},
            {"team", team},
            {"rep", rep},
            {
                "input",
                controlRep(d, rep) and "off" or "on"
            },
            {"start", start},
            {"forces", d.forces}
        }
    )
end
--- Tests: forget the role and rep lines already logged.
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(lastRep)) do
        __TS__Delete(lastRep, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(lastRole)) do
        __TS__Delete(lastRole, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(statueSide)) do
        __TS__Delete(statueSide, k)
    end
end
return ____exports
