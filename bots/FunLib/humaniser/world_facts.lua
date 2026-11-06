--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
--- Seconds a per-moment value is reused for.
local MomentSec = 1
--- Test hook: API reads made, by fact.
____exports.ReadCount = {}
local function newTowers()
    return setmetatable({}, {__mode = "k"})
end
local towers = newTowers()
local moment = {}
local fell = {}
local live = {}
local function counted(fact)
    ____exports.ReadCount[fact] = (____exports.ReadCount[fact] or 0) + 1
end
local function fallback(fact, value)
    fell[fact] = (fell[fact] or 0) + 1
    return value
end
local function valid(u)
    return u ~= nil and u ~= nil and u:IsNull() ~= true
end
--- One API read per key per second: `read` runs for the first asker, the stored result serves the rest (also a miss).
local function perMoment(fact, key, read)
    local now = math.floor(DotaTime() / MomentSec)
    local k = (fact .. ":") .. key
    local m = moment[k]
    if m ~= nil and m.at == now then
        return m.v
    end
    counted(fact)
    local v = read()
    moment[k] = {at = now, v = v}
    if v ~= nil then
        live[fact] = v
    end
    return v
end
--- Reach of a tower's attack to a target's centre: its attack range plus its own bounding radius. Per game, per tower.
function ____exports.TowerReach(tower, fb)
    local known = towers[tower]
    if known ~= nil then
        return known
    end
    if not valid(tower) then
        return fallback("tower_reach", fb)
    end
    counted("tower_reach")
    local range = tower:GetAttackRange()
    if range == nil or range <= 0 then
        return fallback("tower_reach", fb)
    end
    local reach = range + (tower:GetBoundingRadius() or 0)
    towers[tower] = reach
    live.tower_reach = reach
    return reach
end
local function speedOf(units)
    for ____, u in ipairs(units or ({})) do
        do
            local __continue14
            repeat
                if not valid(u) then
                    __continue14 = true
                    break
                end
                local s = u:GetCurrentMovementSpeed()
                if s ~= nil and s > 0 then
                    return s
                end
                __continue14 = true
            until true
            if not __continue14 then
                break
            end
        end
    end
    return nil
end
--- Speed of a lane creep of `team` as seen from `bot` (own team's creeps via the allied scan, the other team's via the enemy scan).
function ____exports.LaneCreepSpeed(bot, team, fb)
    local v = perMoment(
        "lane_creep_speed",
        tostring(team),
        function() return speedOf(bot:GetNearbyLaneCreeps(
            1600,
            team ~= bot:GetTeam()
        )) end
    )
    return v or live.lane_creep_speed or fallback("lane_creep_speed", fb)
end
--- Speed of a neutral creep near `bot`.
function ____exports.NeutralSpeed(bot, fb)
    local v = perMoment(
        "neutral_speed",
        "n",
        function() return speedOf(bot:GetNearbyNeutralCreeps(1600, true)) end
    )
    return v or live.neutral_speed or fallback("neutral_speed", fb)
end
--- Acquisition range of `unit`, keyed by its name (one read per unit type per second).
function ____exports.AcquisitionRange(unit, fb)
    local v = perMoment(
        "acquisition",
        unit:GetUnitName(),
        function()
            local r = unit:GetAcquisitionRange()
            return r ~= nil and r > 0 and r or nil
        end
    )
    return v or fallback("acquisition", fb)
end
--- Latest live value per fact, for the probe's ev=world_fact line.
function ____exports.Live()
    return live
end
--- Times a reader returned its fallback, per fact (read by telemetry).
function ____exports.Fallbacks()
    return fell
end
--- Test hook: forget everything.
function ____exports.Reset()
    for ____, k in ipairs(__TS__ObjectKeys(moment)) do
        __TS__Delete(moment, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(fell)) do
        __TS__Delete(fell, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(live)) do
        __TS__Delete(live, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(____exports.ReadCount)) do
        __TS__Delete(____exports.ReadCount, k)
    end
    towers = newTowers()
end
--- What `bot` can read this moment beside the constants the contexts hold (slice world-facts probe; telemetry logs each once per game).
function ____exports.Probe(bot, constants)
    local rows = {}
    local tower = bot:GetNearbyTowers(1600, true)[1] or bot:GetNearbyTowers(1600, false)[1]
    if tower ~= nil then
        rows[#rows + 1] = {
            fact = "tower_reach",
            live = ____exports.TowerReach(tower, constants.tower),
            constant = constants.tower
        }
    end
    local creeps = bot:GetNearbyLaneCreeps(1600, true)
    local mine = bot:GetNearbyLaneCreeps(1600, false)
    local creep = creeps[1] or mine[1]
    if creep ~= nil then
        rows[#rows + 1] = {
            fact = "lane_creep_speed",
            live = ____exports.LaneCreepSpeed(
                bot,
                creep:GetTeam(),
                constants.laneCreep
            ),
            constant = constants.laneCreep
        }
        rows[#rows + 1] = {
            fact = "acquisition_lane_creep",
            live = ____exports.AcquisitionRange(creep, constants.acquisition),
            constant = constants.acquisition
        }
    end
    local n = bot:GetNearbyNeutralCreeps(1600, true)[1]
    if n ~= nil then
        rows[#rows + 1] = {
            fact = "neutral_speed",
            live = ____exports.NeutralSpeed(bot, constants.neutral),
            constant = constants.neutral
        }
        rows[#rows + 1] = {
            fact = "acquisition_neutral",
            live = ____exports.AcquisitionRange(n, constants.acquisition),
            constant = constants.acquisition
        }
    end
    return rows
end
return ____exports
