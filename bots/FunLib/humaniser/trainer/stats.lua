--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
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
local ____format = require(GetScriptDirectory().."/FunLib/humaniser/trainer/format")
local Sec = ____format.Sec
local Signed = ____format.Signed
local MIN_TAKEABLE = 10
local ON_TIME = 0.03
local SPLIT_MIN_OFFSETS = 3
local SPLIT_MIN_DIFF = 0.05
local HARASS_MIN_GROUP = 5
local HARASS_LINE_GAP = 15
local HARASS_LEAK_GAP = 20
local BIAS_MIN_MEAN = 0.06
local BIAS_MIN_SHARE = 0.2
local NO_SWING_MIN = 3
local KIND_SHARE = 0.6
local DENY_MIN = 5
local DENY_MAX_RATE = 0.3
local ADJ_STEP = 0.05
local function Pct(s, t)
    return t == 0 and 0 or math.floor(100 * s / t + 0.5)
end
local function IsSuccess(v)
    return v.kind == "PERFECT" or v.kind == "OK"
end
local function Mean(xs)
    local sum = 0
    for ____, x in ipairs(xs) do
        sum = sum + x
    end
    return sum / #xs
end
local function Median(xs)
    local sorted = {unpack(xs)}
    __TS__ArraySort(
        sorted,
        function(____, a, b) return a - b end
    )
    local n = #sorted
    local mid = math.floor(n / 2)
    return n % 2 == 1 and sorted[mid + 1] or (sorted[mid] + sorted[mid + 1]) / 2
end
local function Direction(avg)
    if math.abs(avg) < ON_TIME then
        return "fine"
    end
    return avg < 0 and "early" or "late"
end
____exports.Stats = __TS__Class()
local Stats = ____exports.Stats
Stats.name = "Stats"
function Stats.prototype.____constructor(self)
    self.takeable = {}
    self.awaiting = {}
    self.earlyLost = 0
end
function Stats.prototype.Add(self, e)
    if e.type == "outcome" then
        if not e.subjectGotIt then
            self.earlyLost = self.earlyLost + #(self.awaiting[e.creepId] or ({}))
        end
        __TS__Delete(self.awaiting, e.creepId)
    elseif e.v.kind ~= "CANCELLED" then
        local ____self_takeable_0 = self.takeable
        ____self_takeable_0[#____self_takeable_0 + 1] = e.v
        if e.v.kind == "EARLY" then
            if self.awaiting[e.v.creepId] == nil then
                self.awaiting[e.v.creepId] = {}
            end
            local ____self_awaiting_e_v_creepId_1 = self.awaiting[e.v.creepId]
            ____self_awaiting_e_v_creepId_1[#____self_awaiting_e_v_creepId_1 + 1] = e.v
        end
    end
end
function Stats.prototype.Reset(self)
    self.takeable = {}
    self.awaiting = {}
    self.earlyLost = 0
end
function Stats.prototype.Lines(self, o)
    local lines = {
        self:scoreLine(o.denies),
        self:timingLine(o.outcomeOnly),
        self:Leak(o.denies)
    }
    local harass = self:harassLine()
    if harass ~= nil then
        lines[#lines + 1] = harass
    end
    return lines
end
function Stats.prototype.SelfTestLine(self)
    local t = #self.takeable
    local s = #__TS__ArrayFilter(
        self.takeable,
        function(____, v) return IsSuccess(v) end
    )
    return ((((((((("selftest: " .. tostring(s)) .. "/") .. tostring(t)) .. " PERFECT+OK (") .. tostring(Pct(s, t))) .. "%) - easy misses ") .. tostring(self:count(function(v) return v.kind == "MISSED_EASY" end))) .. " of ") .. tostring(t)) .. " reachable"
end
function Stats.prototype.Leak(self, denies)
    if #self.takeable < MIN_TAKEABLE then
        return "not enough data yet"
    end
    local rules = {}
    local function add(r)
        if r ~= nil then
            rules[#rules + 1] = r
        end
    end
    add(self:noSwingRule())
    add(self:lateRule())
    add(self:earlyRule())
    add(self:harassRule())
    if denies then
        add(self:denyRule())
    end
    local best = nil
    for ____, r in ipairs(rules) do
        if best == nil or r.cost > best.cost then
            best = r
        end
    end
    return best == nil and "no clear leak - keep going" or best.line
end
function Stats.prototype.count(self, pred)
    return #__TS__ArrayFilter(
        self.takeable,
        function(____, v) return pred(v) end
    )
end
function Stats.prototype.scoreLine(self, denies)
    local lh = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return not v.isDeny end
    )
    local dn = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.isDeny end
    )
    local lhOk = #__TS__ArrayFilter(
        lh,
        function(____, v) return IsSuccess(v) end
    )
    local line = ((((("LH " .. tostring(lhOk)) .. "/") .. tostring(#lh)) .. " (") .. tostring(Pct(lhOk, #lh))) .. "%)"
    if denies then
        line = line .. ((" - denies " .. tostring(#__TS__ArrayFilter(
            dn,
            function(____, v) return IsSuccess(v) end
        ))) .. "/") .. tostring(#dn)
    end
    return (line .. " - easy misses ") .. tostring(self:count(function(v) return v.kind == "MISSED_EASY" end))
end
function Stats.prototype.offsets(self, filter)
    local out = {}
    for ____, v in ipairs(self.takeable) do
        do
            local __continue42
            repeat
                if v.offset == nil or not v.swung then
                    __continue42 = true
                    break
                end
                if filter ~= nil and not filter(v) then
                    __continue42 = true
                    break
                end
                out[#out + 1] = v.offset
                __continue42 = true
            until true
            if not __continue42 then
                break
            end
        end
    end
    return out
end
function Stats.prototype.isLate(self, v)
    return v.kind == "LATE" or v.kind == "MISSED_EASY" and v.swung
end
function Stats.prototype.timingLine(self, outcomeOnly)
    if outcomeOnly then
        local early = self:count(function(v) return v.kind == "EARLY" end)
        return ((("early " .. tostring(early)) .. " - late ") .. tostring(self:count(function(v) return self:isLate(v) end))) .. " (no timing detail)"
    end
    local offsets = self:offsets()
    if #offsets == 0 then
        return "no timing data yet"
    end
    local mean = Mean(offsets)
    local median = ("(median " .. Signed(Median(offsets))) .. "s)"
    local line = math.abs(mean) < ON_TIME and "you start on time on average " .. median or (((("you start " .. Sec(mean)) .. "s ") .. (mean < 0 and "early" or "late")) .. " on average ") .. median
    local ranged = self:offsets(function(v) return v.creepKind == "ranged" end)
    local melee = self:offsets(function(v) return v.creepKind == "melee" end)
    if #ranged >= SPLIT_MIN_OFFSETS and #melee >= SPLIT_MIN_OFFSETS then
        local r = Mean(ranged)
        local m = Mean(melee)
        if math.abs(r - m) > SPLIT_MIN_DIFF then
            line = line .. ((((((("; " .. Direction(r)) .. " on ranged (") .. Signed(r)) .. "s), ") .. Direction(m)) .. " on melee (") .. Signed(m)) .. "s)"
        end
    end
    return line
end
function Stats.prototype.group(self, harassed)
    local g = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.harassed == harassed end
    )
    return {
        t = #g,
        s = #__TS__ArrayFilter(
            g,
            function(____, v) return IsSuccess(v) end
        )
    }
end
function Stats.prototype.harassGap(self)
    local harassed = self:group(true)
    local free = self:group(false)
    if harassed.t < HARASS_MIN_GROUP or free.t < HARASS_MIN_GROUP then
        return nil
    end
    return {harassed = harassed, free = free, gap = 100 * free.s / free.t - 100 * harassed.s / harassed.t}
end
function Stats.prototype.harassLine(self)
    local g = self:harassGap()
    if g == nil or math.abs(g.gap) < HARASS_LINE_GAP then
        return nil
    end
    return ((("under harass " .. tostring(Pct(g.harassed.s, g.harassed.t))) .. "% vs ") .. tostring(Pct(g.free.s, g.free.t))) .. "% free"
end
function Stats.prototype.noSwingRule(self)
    local misses = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.kind == "MISSED_EASY" and not v.swung end
    )
    if #misses < NO_SWING_MIN then
        return nil
    end
    local suffix = ". Watch every creep near you, not just your target."
    local kinds = {{"ranged", ", mostly ranged. Watch the backline."}, {"melee", ", mostly melee. Watch the front line."}, {"siege", ", mostly siege. Watch the catapult."}}
    for ____, ____value in ipairs(kinds) do
        local kind = ____value[1]
        local text = ____value[2]
        if #__TS__ArrayFilter(
            misses,
            function(____, v) return v.creepKind == kind end
        ) >= KIND_SHARE * #misses then
            suffix = text
            break
        end
    end
    return {
        cost = #misses,
        line = (tostring(#misses) .. " easy creeps lost with no swing") .. suffix
    }
end
function Stats.prototype.attempts(self)
    return self:count(function(v) return v.swung end)
end
function Stats.prototype.adjustment(self, mean)
    return Sec(math.max(
        ADJ_STEP,
        math.floor(math.abs(mean) / ADJ_STEP + 0.5) * ADJ_STEP
    ))
end
function Stats.prototype.lateRule(self)
    local offsets = self:offsets()
    if #offsets == 0 then
        return nil
    end
    local mean = Mean(offsets)
    local late = self:count(function(v) return self:isLate(v) end)
    if mean < BIAS_MIN_MEAN or late < BIAS_MIN_SHARE * self:attempts() then
        return nil
    end
    return {
        cost = late,
        line = ("you're late: start your swing about " .. self:adjustment(mean)) .. "s sooner"
    }
end
function Stats.prototype.earlyRule(self)
    local offsets = self:offsets()
    if #offsets == 0 then
        return nil
    end
    local mean = Mean(offsets)
    local early = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.kind == "EARLY" end
    )
    if mean > -BIAS_MIN_MEAN or #early < BIAS_MIN_SHARE * self:attempts() then
        return nil
    end
    return {
        cost = self.earlyLost,
        line = ("you're early: wait about " .. self:adjustment(mean)) .. "s longer before swinging"
    }
end
function Stats.prototype.harassRule(self)
    local g = self:harassGap()
    if g == nil or g.gap < HARASS_LEAK_GAP then
        return nil
    end
    return {
        cost = math.floor(g.gap / 100 * g.harassed.t + 0.5),
        line = "you lose timing when hit: back off or swing earlier under pressure"
    }
end
function Stats.prototype.denyRule(self)
    local dn = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.isDeny end
    )
    local ok = #__TS__ArrayFilter(
        dn,
        function(____, v) return IsSuccess(v) end
    )
    if #dn < DENY_MIN or ok >= DENY_MAX_RATE * #dn then
        return nil
    end
    return {
        cost = #dn - ok,
        line = ((("denies " .. tostring(ok)) .. "/") .. tostring(#dn)) .. ": check allied creeps under half HP"
    }
end
return ____exports
