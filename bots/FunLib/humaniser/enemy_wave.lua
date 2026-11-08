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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
--- All `judgement` (user 09/11/2026), in path units and seconds.
____exports.SETTINGS = {
    DueNear = 300,
    RiseMin = 2,
    WindowBefore = 5,
    ArriveWindow = 10,
    GiveUp = 60,
    Speed = 325
}
local function fresh(ts)
    return {
        ts = ts,
        seen = false,
        wSecs = 0,
        ownNear = 0,
        recent = {}
    }
end
local function resolve(st, w, ew, cycle)
    st.resolved = {ts = w.ts, ew = ew, due = w.due}
    st.track = fresh(w.ts + cycle)
    return st.resolved
end
--- One second of the rule for the wave `st` follows (idempotent within a second); `cycle` the wave cycle (30 s). Returns the
-- resolution this second made, if any.
function ____exports.Step(st, i, cycle)
    local s = ____exports.SETTINGS
    local t = math.floor(i.now)
    if st.at == t then
        return nil
    end
    st.at = t
    if st.track == nil then
        st.track = fresh(math.floor(t / cycle) * cycle)
    end
    local w = st.track
    if t < w.ts then
        return nil
    end
    local raw = i.spawn + i.dir * i.speed * (t - w.ts)
    local passed = i.lead ~= nil and i.dir * (raw - i.lead) > 0
    local spot = passed and i.lead or raw
    local own = i.lead ~= nil and math.abs(i.lead - spot) <= s.DueNear
    if w.due == nil then
        if i.lead ~= nil and i.dir * (raw - i.lead) >= -s.DueNear then
            w.due = t
            local b = unpack(#w.recent > s.WindowBefore and table.remove(w.recent, 1) or ({i.count}))
            w.base = b
            for ____, ____value in ipairs(w.recent) do
                local c = ____value[1]
                local o = ____value[2]
                w.wSecs = w.wSecs + 1
                if c - b >= s.RiseMin then
                    w.seen = true
                end
                if o then
                    w.ownNear = w.ownNear + 1
                end
            end
            w.recent = {}
        else
            local ____w_recent_0 = w.recent
            ____w_recent_0[#____w_recent_0 + 1] = {i.count, own}
            if #w.recent > s.WindowBefore + 1 then
                table.remove(w.recent, 1)
            end
            return t >= w.ts + s.GiveUp and resolve(st, w, "u", cycle) or nil
        end
    end
    if t <= w.due + s.ArriveWindow then
        w.wSecs = w.wSecs + 1
        if i.count - w.base >= s.RiseMin then
            w.seen = true
        end
        if own then
            w.ownNear = w.ownNear + 1
        end
    end
    if t >= w.due + s.ArriveWindow then
        return resolve(st, w, w.seen and "p" or (w.ownNear * 2 >= w.wSecs and "a" or "u"), cycle)
    end
    return nil
end
--- The resolved fact not yet read, cleared by this call (one wave read takes it).
function ____exports.Take(st)
    local r = st.resolved
    st.resolved = nil
    return r
end
local states = {}
function ____exports.ResetCache()
    for k in pairs(states) do
        __TS__Delete(states, k)
    end
end
function ____exports.StateOf(team, lane)
    local key = (tostring(team) .. ":") .. tostring(lane)
    local st = states[key]
    if st == nil then
        st = {}
        states[key] = st
    end
    return st
end
--- The tracker's second for `team`'s side of `lane` (the calling script must be `team`'s); a frame within a stepped second
-- costs nothing. Returns the resolution this second made, if any.
function ____exports.Tick(team, lane, now)
    local st = ____exports.StateOf(team, lane)
    if st.at == math.floor(now) then
        return nil
    end
    local path, ____, own, enemy = LanePush.CreepsNow(team, lane)
    if path == nil then
        return nil
    end
    local e = team == Team.Radiant and Team.Dire or Team.Radiant
    local spawn, dir = LanePush.SpawnOf(path, e)
    return ____exports.Step(
        st,
        {
            now = now,
            spawn = spawn,
            dir = dir,
            speed = WorldFacts.Latest("lane_creep_speed", ____exports.SETTINGS.Speed),
            lead = LanePush.LeadOf(own, team),
            count = #enemy
        },
        LaneConfig.Settings().Timing.WaveCycle
    )
end
return ____exports
