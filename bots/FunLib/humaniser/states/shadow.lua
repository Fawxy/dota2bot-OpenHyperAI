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

local __TS__Symbol, Symbol
do
    local symbolMetatable = {__tostring = function(self)
        return ("Symbol(" .. (self.description or "")) .. ")"
    end}
    function __TS__Symbol(description)
        return setmetatable({description = description}, symbolMetatable)
    end
    Symbol = {
        asyncDispose = __TS__Symbol("Symbol.asyncDispose"),
        dispose = __TS__Symbol("Symbol.dispose"),
        iterator = __TS__Symbol("Symbol.iterator"),
        hasInstance = __TS__Symbol("Symbol.hasInstance"),
        species = __TS__Symbol("Symbol.species"),
        toStringTag = __TS__Symbol("Symbol.toStringTag")
    }
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local __TS__Unpack = table.unpack or unpack

local __TS__Generator
do
    local function generatorIterator(self)
        return self
    end
    local function generatorNext(self, ...)
        local co = self.____coroutine
        if coroutine.status(co) == "dead" then
            return {done = true}
        end
        local status, value = coroutine.resume(co, ...)
        if not status then
            error(value, 0)
        end
        return {
            value = value,
            done = coroutine.status(co) == "dead"
        }
    end
    function __TS__Generator(fn)
        return function(...)
            local args = {...}
            local argsLength = __TS__CountVarargs(...)
            return {
                ____coroutine = coroutine.create(function() return fn(__TS__Unpack(args, 1, argsLength)) end),
                [Symbol.iterator] = generatorIterator,
                next = generatorNext
            }
        end
    end
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local FarmPattern = require(GetScriptDirectory().."/FunLib/humaniser/farm_pattern")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Rotation = require(GetScriptDirectory().."/FunLib/humaniser/transitions/rotation")
local MidRunes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/mid_runes")
____exports.JOB = 0.8
____exports.ROTATE = 0.75
--- A farm trip beats laning (0.5 plus stickiness), as OHA's trip desire (0.62) beats laning's 0.446.
____exports.TRIP = 0.7
____exports.FARM = 0.4
--- Seconds a job scorer keeps its score after its source went false. The layer leaves an unowned job the moment
-- its scorer stops (no dwell for jobs), so one-frame gaps in a source would otherwise count as two switches.
____exports.LINGER = 1
local PULL_KINDS = {
    full_pull = true,
    half_pull = true,
    stack_pull = true,
    double_pull = true,
    contest = true
}
local seen = {}
function ____exports.ResetCache()
    for k in pairs(seen) do
        __TS__Delete(seen, k)
    end
end
local function lingering(bot, state, on, score)
    local key = (tostring(bot:GetPlayerID()) .. ":") .. state
    local now = DotaTime()
    if on then
        seen[key] = now
        return score
    end
    local at = seen[key]
    return at ~= nil and now - at <= ____exports.LINGER and score or nil
end
local function liveJob(bot)
    local ____CampJobs_Active_result_0
    if CampJobs.Active(bot) then
        ____CampJobs_Active_result_0 = CampJobs.Current(bot)
    else
        ____CampJobs_Active_result_0 = nil
    end
    return ____CampJobs_Active_result_0
end
--- Pulls (full, half, stack, double) and pull contests: a camp job OHA's scheduler started this cycle.
function ____exports.PullScore(bot)
    local job = liveJob(bot)
    return lingering(bot, "pull", job ~= nil and PULL_KINDS[job.kind] == true, ____exports.JOB)
end
function ____exports.StackScore(bot)
    local ____lingering_4 = lingering
    local ____bot_3 = bot
    local ____opt_1 = liveJob(bot)
    return ____lingering_4(____bot_3, "stack", (____opt_1 and ____opt_1.kind) == "stack", ____exports.JOB)
end
--- A support's power-rune rotation once it leaves (Rotation.Active), or the mid's rune claim.
function ____exports.RotateScore(bot)
    return lingering(
        bot,
        "rotate",
        Rotation.Active(bot) ~= nil or MidRunes.Claiming(bot),
        ____exports.ROTATE
    )
end
--- A farm trip in progress (also inside the laning phase), else after laning any bot FarmPattern would farm with.
-- Only StartGate's lasting checks count: its transient ones (mode, HP, orders, retreat, runes, enemies) flip
-- many times a minute, and the interrupts they reflect are left out of the agreement measure anyway.
function ____exports.FarmScore(bot)
    if not FarmPattern.IsActive() then
        return nil
    end
    if FarmPattern.Current(bot) ~= nil then
        return ____exports.TRIP
    end
    if Phase.IsLaningFor(bot) then
        return nil
    end
    return FarmPattern.Eligible(bot) == nil and ____exports.FARM or nil
end
local idle = __TS__Generator(function(ctx)
    return ctx.fail("unsupported", "shadow")
end)
local function spec(name, kind, host, score)
    return function(bot) return {
        name = name,
        kind = kind,
        host = host,
        score = function() return score(bot) end,
        body = idle
    } end
end
--- (name, spec factory) in registration order; `rotate` hosts on rune mode, its ganks (roam) come later.
____exports.SPECS = {
    {
        "pull",
        spec("pull", "job", BotMode.Farm, ____exports.PullScore)
    },
    {
        "stack",
        spec("stack", "job", BotMode.Farm, ____exports.StackScore)
    },
    {
        "rotate",
        spec("rotate", "job", BotMode.Rune, ____exports.RotateScore)
    },
    {
        "farm",
        spec("farm", "posture", BotMode.Farm, ____exports.FarmScore)
    }
}
return ____exports
