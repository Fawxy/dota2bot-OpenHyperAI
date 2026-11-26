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
-- End of Lua Library inline imports
local ____exports = {}
local claims, held
--- The hero lets go of whatever it holds; true when it held a claim.
function ____exports.Release(pid)
    local cid = held[pid]
    if cid == nil then
        return false
    end
    held[pid] = nil
    local m = claims[cid]
    if m ~= nil then
        __TS__Delete(m, pid)
        if (next(m)) == nil then
            claims[cid] = nil
        end
    end
    return true
end
--- pid -> creep id -> the hero's answer.
local answers = {}
claims = {}
held = {}
function ____exports.ResetCache()
    for ____, t in ipairs({answers, claims, held}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
--- The hero's answers on each listed creep, new ones made now; answers on creeps this read does not list are dropped.
function ____exports.Touch(pid, cids, now)
    local m = answers[pid]
    if m == nil then
        m = {}
        answers[pid] = m
    end
    for ____, cid in ipairs(cids) do
        local r = m[cid]
        if r == nil then
            m[cid] = {at = now, first = now}
        else
            r.at = now
        end
    end
    for cid, r in pairs(m) do
        if r.at ~= now then
            __TS__Delete(m, cid)
        end
    end
    return m
end
--- The hero's latest answer on the creep, if the read still lists it.
function ____exports.AnswerOf(pid, cid)
    local ____opt_0 = answers[pid]
    return ____opt_0 and ____opt_0[cid]
end
--- The hero takes the creep (a hero holds one claim: an earlier one is released first). Returns the heroes already holding a claim on the
-- same creep, which the caller logs; the claim is taken either way.
function ____exports.Take(cid, c)
    ____exports.Release(c.pid)
    local m = claims[cid]
    local others = {}
    if m == nil then
        m = {}
        claims[cid] = m
    end
    for pid in pairs(m) do
        others[#others + 1] = pid
    end
    m[c.pid] = c
    held[c.pid] = cid
    return others
end
function ____exports.Phase(pid, p)
    local cid = held[pid]
    local ____temp_4
    if cid == nil then
        ____temp_4 = nil
    else
        local ____opt_2 = claims[cid]
        ____temp_4 = ____opt_2 and ____opt_2[pid]
    end
    local c = ____temp_4
    if c ~= nil then
        c.phase = p
    end
end
--- The heroes holding a claim on the creep, none when it is free.
function ____exports.ClaimsOn(cid)
    local out = {}
    local m = claims[cid]
    if m ~= nil then
        for ____, c in pairs(m) do
            out[#out + 1] = c
        end
    end
    return out
end
--- The creep the hero holds, if any.
function ____exports.HeldBy(pid)
    return held[pid]
end
return ____exports
