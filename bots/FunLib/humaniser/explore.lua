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
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {Mults = {
    0.5,
    0.75,
    1,
    1.35,
    1.75
}, BandHi = 2, Release = 8}
local rolls = {}
local function r2(v)
    return math.floor(v * 100 + 0.5) / 100
end
local function ____end(pid, why, now)
    local x = rolls[pid]
    if x == nil then
        return
    end
    rolls[pid] = nil
    Telemetry.Event(
        "roll",
        {
            {"ph", "end"},
            {"pid", pid},
            {"mult", x.mult},
            {
                "secs",
                r2(now - x.start)
            },
            {"why", why}
        }
    )
end
--- The multiplier on `bot`'s kill bar: its held roll, else 1 (switch off, no roll). A roll not refreshed for `Release` s ends here too, for a hero that stopped being read.
function ____exports.Mult(bot)
    if not Ours.On("ExploreRoll") then
        return 1
    end
    local pid = bot:GetPlayerID()
    local x = rolls[pid]
    if x == nil then
        return 1
    end
    local now = DotaTime()
    if now - x.lastInBand >= ____exports.SETTINGS.Release then
        ____end(pid, "out", now)
        return 1
    end
    return x.mult
end
--- The hero's own-place read (`leave`) is in the band: someone reaches it and HP / kill is under `BandHi`.
function ____exports.InBand(a)
    return a.reachers > 0 and a.kill > 0 and a.ratio < ____exports.SETTINGS.BandHi
end
--- Watches the hero's own-place answer. Starts a roll on the first in-band read when none is held, refreshes a held one, ends it after
-- `Release` s out of band. Returns true when a roll started on this read: `a` was made unrolled, so the caller asks again.
function ____exports.Observe(bot, a)
    if not Ours.On("ExploreRoll") or not RetreatState.Owns(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local x = rolls[pid]
    if not ____exports.InBand(a) then
        if x ~= nil and now - x.lastInBand >= ____exports.SETTINGS.Release then
            ____end(pid, "out", now)
        end
        return false
    end
    if x ~= nil then
        x.lastInBand = now
        return false
    end
    local n = #____exports.SETTINGS.Mults
    local u = LaneConfig.Draw() or RandomFloat(0, 1)
    local mult = ____exports.SETTINGS.Mults[math.min(
        n - 1,
        math.floor(u * n)
    ) + 1]
    rolls[pid] = {mult = mult, start = now, lastInBand = now}
    local hpa = bot:GetHealth()
    Telemetry.Event(
        "roll",
        {
            {"ph", "start"},
            {"pid", pid},
            {"mult", mult},
            {
                "ratio",
                r2(a.ratio)
            },
            {
                "kill",
                math.floor(a.kill + 0.5)
            },
            {
                "hp",
                r2(hpa / math.max(
                    1,
                    bot:GetMaxHealth()
                ))
            },
            {
                "hpa",
                math.floor(hpa + 0.5)
            },
            {"pressed", a.pressed},
            {"reach", a.reachers},
            {
                "bar",
                r2(a.bar)
            },
            {"base", a.ratio < a.bar}
        }
    )
    return true
end
--- The hero died: its roll ends.
function ____exports.Died(bot)
    ____end(
        bot:GetPlayerID(),
        "died",
        DotaTime()
    )
end
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(rolls)) do
        __TS__Delete(rolls, k)
    end
end
____exports._test = {rolls = rolls}
return ____exports
