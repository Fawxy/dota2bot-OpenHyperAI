--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

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
local Round, Taker
local ____format = require(GetScriptDirectory().."/FunLib/humaniser/trainer/format")
local Sec = ____format.Sec
local Signed = ____format.Signed
function Round(x)
    return math.floor(x + 0.5)
end
function Taker(killer)
    if killer.kind == "tower" then
        return "tower took it"
    end
    if killer.kind == "enemyHero" then
        return "denied by " .. (killer.name or "an enemy hero")
    end
    if killer.kind == "ally" then
        return (killer.name or "an ally") .. " took it"
    end
    return "lane creep took it"
end
local RESOLVE_AFTER = 2.5
local MISS_GRACE = 0.3
local EARLY_WINDOW = 0.2
local EARLY_DROP_FRACTION = 0.6
local MIN_EARLY = 0.01
local EASY_RADIUS = 800
local WIDEST_MEMORY = 2
local WIDEST_LOOKAHEAD = 2
local SAME_SWING_SLACK = 0.1
____exports.Judge = __TS__Class()
local Judge = ____exports.Judge
Judge.name = "Judge"
function Judge.prototype.____constructor(self, easyWindow)
    self.easyWindow = easyWindow
    self.attempts = {}
    self.attempted = {}
    self.reported = {}
    self.prevAnim = "none"
    self.prevTarget = nil
    self.widest = {}
    self.handled = {}
    self.engaged = {}
end
function Judge.prototype.Step(self, s, creeps)
    local events = {}
    local byId = {}
    for ____, c in ipairs(creeps) do
        byId[c.id] = c
    end
    self:recordWindows(s.now, creeps)
    self:resolveOpen(s, byId, events)
    self:detectEasyMisses(s, creeps, events)
    self:trackSwing(s, byId, events)
    self:emitOutcomes(creeps, events)
    self.prevAnim = s.anim
    self.prevTarget = s.target
    return events
end
function Judge.prototype.resolveOpen(self, s, byId, events)
    local open = {}
    local group = {}
    for ____, a in ipairs(self.attempts) do
        if group[a.creepId] == nil then
            group[a.creepId] = {}
        end
        local ____group_a_creepId_0 = group[a.creepId]
        ____group_a_creepId_0[#____group_a_creepId_0 + 1] = a
    end
    for ____, a in ipairs(self.attempts) do
        local c = byId[a.creepId]
        local ____temp_1
        if c == nil then
            ____temp_1 = self:forced(s, a)
        else
            ____temp_1 = self:resolve(s, a, c, group[a.creepId])
        end
        local closed = ____temp_1
        if closed ~= nil then
            self.engaged[a.creepId] = true
        end
        if closed == nil then
            open[#open + 1] = a
        elseif closed ~= "silent" then
            events[#events + 1] = {type = "verdict", v = closed}
        end
    end
    self.attempts = open
end
function Judge.prototype.resolve(self, s, a, c, onCreep)
    if not c.alive then
        local ____temp_2
        if c.killer == nil then
            ____temp_2 = self:forced(s, a)
        else
            ____temp_2 = self:resolveDeath(
                s,
                a,
                c,
                c.killer,
                onCreep
            )
        end
        return ____temp_2
    end
    local dropWindowStart = a.predictedLand - EARLY_WINDOW
    if s.now < dropWindowStart then
        a.baselineHp = c.hp
    elseif s.now <= a.predictedLand + EARLY_WINDOW and a.baselineHp - c.hp >= EARLY_DROP_FRACTION * a.prediction.effDmg then
        return self:early(s, a)
    end
    if s.now > a.predictedLand + MISS_GRACE then
        return self:verdict("MISS", s, a, "missed - evasion/uphill?")
    end
    return self:forced(s, a)
end
function Judge.prototype.forced(self, s, a)
    if s.now - a.startedAt < RESOLVE_AFTER then
        return nil
    end
    return self:verdict("MISS", s, a, "missed - no result after 2.5s")
end
function Judge.prototype.early(self, s, a)
    local by = math.max(a.prediction.startOpen - a.swingStart, MIN_EARLY)
    local reason = (((("early by " .. Sec(by)) .. "s - creep had ") .. tostring(Round(a.hp))) .. " HP, you deal ") .. tostring(Round(a.prediction.effDmg))
    return self:verdict(
        "EARLY",
        s,
        a,
        reason,
        a.swingStart - a.prediction.ideal,
        s.now
    )
end
function Judge.prototype.resolveDeath(self, s, a, c, killer, onCreep)
    if killer.kind == "subject" then
        local credited = self:creditedAttempt(s, onCreep)
        if a == credited then
            return self:credit(s, a)
        end
        return __TS__ArrayIndexOf(onCreep, a) < __TS__ArrayIndexOf(onCreep, credited) and self:early(s, a) or "silent"
    end
    if a ~= onCreep[#onCreep] then
        return "silent"
    end
    local offset = a.swingStart - a.prediction.ideal
    if s.now < a.predictedLand then
        local easy = self:easyMiss(s, c, killer, a)
        if easy ~= nil then
            return easy
        end
        return self:verdict(
            "LATE",
            s,
            a,
            (("late by " .. Sec(a.predictedLand - s.now)) .. "s - ") .. Taker(killer),
            offset,
            s.now
        )
    end
    return self:verdict(
        "MISS",
        s,
        a,
        "missed - " .. Taker(killer)
    )
end
function Judge.prototype.creditedAttempt(self, s, onCreep)
    local latest = onCreep[#onCreep]
    if #onCreep < 2 then
        return latest
    end
    local older = onCreep[#onCreep - 2 + 1]
    return s.now - older.predictedLand <= SAME_SWING_SLACK and older or latest
end
function Judge.prototype.credit(self, s, a)
    local offset = a.swingStart - a.prediction.ideal
    local p = a.prediction
    if a.swingStart >= p.startOpen and a.swingStart < p.startClose then
        return self:verdict(
            "PERFECT",
            s,
            a,
            ("perfect (" .. Signed(offset)) .. "s)",
            offset,
            s.now
        )
    end
    local early = a.swingStart < p.startOpen
    local distance = early and p.startOpen - a.swingStart or a.swingStart - p.startClose
    return self:verdict(
        "OK",
        s,
        a,
        ((("got it (window said " .. Sec(distance)) .. "s ") .. (early and "early" or "late")) .. ")",
        offset,
        s.now
    )
end
function Judge.prototype.recordWindows(self, now, creeps)
    for ____, c in ipairs(creeps) do
        do
            local __continue34
            repeat
                local p = c.prediction
                if not c.alive or p == nil or p.startClose <= now then
                    __continue34 = true
                    break
                end
                local w = math.min(p.startClose, now + WIDEST_LOOKAHEAD) - math.max(p.startOpen, now)
                if self.widest[c.id] == nil then
                    self.widest[c.id] = {}
                end
                local ____self_widest_c_id_3 = self.widest[c.id]
                ____self_widest_c_id_3[#____self_widest_c_id_3 + 1] = {t = now, w = w}
                __continue34 = true
            until true
            if not __continue34 then
                break
            end
        end
    end
    for ____, id in ipairs(__TS__ObjectKeys(self.widest)) do
        local samples = self.widest[id]
        while #samples > 0 and now - samples[1].t > WIDEST_MEMORY do
            table.remove(samples, 1)
        end
        if #samples == 0 then
            __TS__Delete(self.widest, id)
        end
    end
end
function Judge.prototype.widestFor(self, id)
    local best = 0
    for ____, sample in ipairs(self.widest[id] or ({})) do
        best = math.max(best, sample.w)
    end
    return best
end
function Judge.prototype.detectEasyMisses(self, s, creeps, events)
    for ____, c in ipairs(creeps) do
        do
            local __continue46
            repeat
                if c.alive or c.killer == nil or self.handled[c.id] then
                    __continue46 = true
                    break
                end
                self.handled[c.id] = true
                if c.killer.kind ~= "subject" and not self.engaged[c.id] then
                    local v = self:easyMiss(s, c, c.killer, nil)
                    if v ~= nil then
                        events[#events + 1] = {type = "verdict", v = v}
                    end
                end
                __TS__Delete(self.widest, c.id)
                __continue46 = true
            until true
            if not __continue46 then
                break
            end
        end
    end
end
function Judge.prototype.easyMiss(self, s, c, killer, a)
    local window = self:widestFor(c.id)
    if not s.alive or not s.eligible or c.dist > EASY_RADIUS or window < self.easyWindow then
        return nil
    end
    local what = c.isDeny and "easy deny" or "easy one"
    local reason = ((("missed " .. what) .. " - ") .. Sec(window)) .. "s window, "
    reason = reason .. (a == nil and c.kind .. " creep, no swing" or ("you were " .. Sec(a.predictedLand - s.now)) .. "s late")
    if killer.kind == "ally" then
        reason = reason .. (" - " .. (killer.name or "an ally")) .. " took it after you passed"
    end
    local v = {
        kind = "MISSED_EASY",
        at = s.now,
        creepId = c.id,
        creepKind = c.kind,
        isDeny = c.isDeny,
        harassed = s.harassed,
        swung = a ~= nil,
        window = window,
        reason = reason
    }
    if a ~= nil then
        v.offset = a.swingStart - a.prediction.ideal
        v.predictedLand = a.predictedLand
        v.landedAt = s.now
    end
    return v
end
function Judge.prototype.verdict(self, kind, s, a, reason, offset, landedAt)
    return {
        kind = kind,
        at = s.now,
        creepId = a.creepId,
        creepKind = a.creepKind,
        isDeny = a.isDeny,
        harassed = a.harassed,
        swung = true,
        offset = offset,
        predictedLand = a.predictedLand,
        landedAt = landedAt,
        reason = reason
    }
end
function Judge.prototype.trackSwing(self, s, byId, events)
    local current = self:swingingAttempt()
    local retargeted = s.anim == "swing" and current ~= nil and current.creepId ~= s.target
    if current ~= nil then
        if s.anim == "followthrough" then
            current.swinging = false
        elseif s.anim == "none" or retargeted then
            self.attempts = __TS__ArrayFilter(
                self.attempts,
                function(____, a) return a ~= current end
            )
            events[#events + 1] = {
                type = "verdict",
                v = self:verdict("CANCELLED", s, current, "cancelled swing")
            }
        end
    end
    local started = s.anim == "swing" and (self.prevAnim ~= "swing" or s.target ~= self.prevTarget)
    if not started or s.target == nil then
        return
    end
    local c = byId[s.target]
    if c == nil or not c.alive or c.prediction == nil then
        return
    end
    local swingStart = s.swingStart or s.now
    self.attempted[c.id] = true
    local ____self_attempts_4 = self.attempts
    ____self_attempts_4[#____self_attempts_4 + 1] = {
        creepId = c.id,
        creepKind = c.kind,
        isDeny = c.isDeny,
        harassed = s.harassed,
        prediction = c.prediction,
        swingStart = swingStart,
        startedAt = s.now,
        predictedLand = swingStart + c.prediction.delay,
        hp = c.hp,
        baselineHp = c.hp,
        swinging = true
    }
end
function Judge.prototype.swingingAttempt(self)
    do
        local i = #self.attempts - 1
        while i >= 0 do
            if self.attempts[i + 1].swinging then
                return self.attempts[i + 1]
            end
            i = i - 1
        end
    end
    return nil
end
function Judge.prototype.emitOutcomes(self, creeps, events)
    for ____, c in ipairs(creeps) do
        do
            local __continue67
            repeat
                if c.alive or c.killer == nil or not self.attempted[c.id] or self.reported[c.id] then
                    __continue67 = true
                    break
                end
                self.reported[c.id] = true
                events[#events + 1] = {type = "outcome", creepId = c.id, subjectGotIt = c.killer.kind == "subject"}
                __continue67 = true
            until true
            if not __continue67 then
                break
            end
        end
    end
end
return ____exports
