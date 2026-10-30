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

local function __TS__ArrayIncludes(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    local k = fromIndex
    if fromIndex < 0 then
        k = len + fromIndex
    end
    if k < 0 then
        k = 0
    end
    for i = k + 1, len do
        if self[i] == searchElement then
            return true
        end
    end
    return false
end

local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
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

local function __TS__DelegatedYield(iterable)
    if type(iterable) == "string" then
        for index = 0, #iterable - 1 do
            coroutine.yield(__TS__StringAccess(iterable, index))
        end
    elseif iterable.____coroutine ~= nil then
        local co = iterable.____coroutine
        while true do
            local status, value = coroutine.resume(co)
            if not status then
                error(value, 0)
            end
            if coroutine.status(co) == "dead" then
                return value
            else
                coroutine.yield(value)
            end
        end
    elseif iterable[Symbol.iterator] then
        local iterator = iterable[Symbol.iterator](iterable)
        while true do
            local result = iterator:next()
            if result.done then
                return result.value
            else
                coroutine.yield(result.value)
            end
        end
    else
        for ____, value in ipairs(iterable) do
            coroutine.yield(value)
        end
    end
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

local __TS__Iterator
do
    local function iteratorGeneratorStep(self)
        local co = self.____coroutine
        local status, value = coroutine.resume(co)
        if not status then
            error(value, 0)
        end
        if coroutine.status(co) == "dead" then
            return
        end
        return true, value
    end
    local function iteratorIteratorStep(self)
        local result = self:next()
        if result.done then
            return
        end
        return true, result.value
    end
    local function iteratorStringStep(self, index)
        index = index + 1
        if index > #self then
            return
        end
        return index, string.sub(self, index, index)
    end
    function __TS__Iterator(iterable)
        if type(iterable) == "string" then
            return iteratorStringStep, iterable, 0
        elseif iterable.____coroutine ~= nil then
            return iteratorGeneratorStep, iterable
        elseif iterable[Symbol.iterator] then
            local iterator = iterable[Symbol.iterator](iterable)
            return iteratorIteratorStep, iterator
        else
            return ipairs(iterable)
        end
    end
end

local Set
do
    Set = __TS__Class()
    Set.name = "Set"
    function Set.prototype.____constructor(self, values)
        self[Symbol.toStringTag] = "Set"
        self.size = 0
        self.nextKey = {}
        self.previousKey = {}
        if values == nil then
            return
        end
        local iterable = values
        if iterable[Symbol.iterator] then
            local iterator = iterable[Symbol.iterator](iterable)
            while true do
                local result = iterator:next()
                if result.done then
                    break
                end
                self:add(result.value)
            end
        else
            local array = values
            for ____, value in ipairs(array) do
                self:add(value)
            end
        end
    end
    function Set.prototype.add(self, value)
        local isNewValue = not self:has(value)
        if isNewValue then
            self.size = self.size + 1
        end
        if self.firstKey == nil then
            self.firstKey = value
            self.lastKey = value
        elseif isNewValue then
            self.nextKey[self.lastKey] = value
            self.previousKey[value] = self.lastKey
            self.lastKey = value
        end
        return self
    end
    function Set.prototype.clear(self)
        self.nextKey = {}
        self.previousKey = {}
        self.firstKey = nil
        self.lastKey = nil
        self.size = 0
    end
    function Set.prototype.delete(self, value)
        local contains = self:has(value)
        if contains then
            self.size = self.size - 1
            local next = self.nextKey[value]
            local previous = self.previousKey[value]
            if next ~= nil and previous ~= nil then
                self.nextKey[previous] = next
                self.previousKey[next] = previous
            elseif next ~= nil then
                self.firstKey = next
                self.previousKey[next] = nil
            elseif previous ~= nil then
                self.lastKey = previous
                self.nextKey[previous] = nil
            else
                self.firstKey = nil
                self.lastKey = nil
            end
            self.nextKey[value] = nil
            self.previousKey[value] = nil
        end
        return contains
    end
    function Set.prototype.forEach(self, callback)
        for ____, key in __TS__Iterator(self:keys()) do
            callback(nil, key, key, self)
        end
    end
    function Set.prototype.has(self, value)
        return self.nextKey[value] ~= nil or self.lastKey == value
    end
    Set.prototype[Symbol.iterator] = function(self)
        return self:values()
    end
    function Set.prototype.entries(self)
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = {key, key}}
                key = nextKey[key]
                return result
            end
        }
    end
    function Set.prototype.keys(self)
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = key}
                key = nextKey[key]
                return result
            end
        }
    end
    function Set.prototype.values(self)
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = key}
                key = nextKey[key]
                return result
            end
        }
    end
    function Set.prototype.union(self, other)
        local result = __TS__New(Set, self)
        for ____, item in __TS__Iterator(other) do
            result:add(item)
        end
        return result
    end
    function Set.prototype.intersection(self, other)
        local result = __TS__New(Set)
        for ____, item in __TS__Iterator(self) do
            if other:has(item) then
                result:add(item)
            end
        end
        return result
    end
    function Set.prototype.difference(self, other)
        local result = __TS__New(Set, self)
        for ____, item in __TS__Iterator(other) do
            result:delete(item)
        end
        return result
    end
    function Set.prototype.symmetricDifference(self, other)
        local result = __TS__New(Set, self)
        for ____, item in __TS__Iterator(other) do
            if self:has(item) then
                result:delete(item)
            else
                result:add(item)
            end
        end
        return result
    end
    function Set.prototype.isSubsetOf(self, other)
        for ____, item in __TS__Iterator(self) do
            if not other:has(item) then
                return false
            end
        end
        return true
    end
    function Set.prototype.isSupersetOf(self, other)
        for ____, item in __TS__Iterator(other) do
            if not self:has(item) then
                return false
            end
        end
        return true
    end
    function Set.prototype.isDisjointFrom(self, other)
        for ____, item in __TS__Iterator(self) do
            if other:has(item) then
                return false
            end
        end
        return true
    end
    Set[Symbol.species] = Set
end
-- End of Lua Library inline imports
local ____exports = {}
local setExit, dist, sec, hpPct, phase, laneNear, freshInBox, isFirst, campTargets, campNeutrals, describe, doubleFields, targetDist, sample59, exits, EXIT_DIRS, LANE_NEAR, SEEN_SCAN
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Team = ____dota.Team
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function setExit(sp)
    for ____, e in ipairs(EXIT_DIRS) do
        do
            local __continue11
            repeat
                if math.abs(sp.location.x - e.x) > 200 or math.abs(sp.location.y - e.y) > 200 then
                    __continue11 = true
                    break
                end
                local away = LaneConfig.Settings().Radii.StackExit
                local c = Camps.BoxCenter(sp)
                local target = Vector(c.x + e.dx * away, c.y + e.dy * away, c.z)
                return {Camps.BoxEdgePoint(sp, target, away) or target}
            until true
            if not __continue11 then
                break
            end
        end
    end
    return nil
end
--- The walk-off after the hit: a hand-set direction (EXIT_DIRS), else the camp data's path, or one derived towards the
-- lane (ExitTowardLane).
function ____exports.ExitPath(sp, data)
    if exits[sp.idx] ~= nil then
        return exits[sp.idx]
    end
    local set = setExit(sp)
    if set ~= nil then
        exits[sp.idx] = set
    elseif ____exports.SETTINGS.ExitTowardLane then
        exits[sp.idx] = Camps.DeriveStackExit(sp, sp.team, true)
    else
        return data.stack.exitPath
    end
    return exits[sp.idx]
end
--- Where the bot waits for the hit: StandOffset past the box edge, on the walk-off side.
function ____exports.Stand(sp, data)
    return Camps.StandPoint(
        sp,
        ____exports.ExitPath(sp, data)[1],
        LaneConfig.Settings().Radii.StandOffset
    )
end
function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function sec(a)
    return math.floor((DotaTime() - a.minute * 60) * 10) / 10
end
function hpPct(bot)
    return math.floor(100 * bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ))
end
function phase(bot, a, l)
    if a.first ~= nil and a.first.aggro == nil then
        if l == "wait" then
            a.first.arr = a.first.arr or sec(a)
        end
        return
    end
    if l == "wait" and a.arr == nil then
        a.arr = sec(a)
    end
    if l == "aggro" then
        a.hit0 = sec(a)
        a.hpa = hpPct(bot)
    end
    if l == "exit" then
        a.exitAt = sec(a)
        a.hpe = hpPct(bot)
    end
end
function laneNear(bot, a)
    local sp = Camps.SpawnerByIdx(a.campIdx)
    if sp == nil then
        return 0
    end
    local n = 0
    for ____, enemy in ipairs({false, true}) do
        for ____, c in ipairs(bot:GetNearbyLaneCreeps(SEEN_SCAN, enemy) or ({})) do
            if c ~= nil and c ~= nil and c:IsAlive() and GetUnitToLocationDistance(c, sp.location) <= LANE_NEAR then
                n = n + 1
            end
        end
    end
    return n
end
function freshInBox(bot, a, campIdx)
    local margin = LaneConfig.Settings().Radii.BoxMargin
    local n = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.StackCountScan,
        false
    ) or ({})) do
        local ____temp_8 = c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() and Camps.InBox(
            campIdx,
            c:GetLocation(),
            margin
        )
        if ____temp_8 then
            local ____opt_5 = a.seen
            local ____temp_7 = ____opt_5 and ____opt_5:has(c)
            if ____temp_7 == nil then
                ____temp_7 = false
            end
            ____temp_8 = not ____temp_7
        end
        if ____temp_8 then
            n = n + 1
        end
    end
    return n
end
function isFirst(a, n)
    local ____opt_15 = a and a.first
    local ____opt_9 = ____opt_15 and ____opt_15.units
    if ____opt_9 ~= nil then
        local ____opt_10 = a and a.first
        ____opt_9 = __TS__ArrayIncludes(____opt_10 and ____opt_10.units, n)
    end
    local ____opt_9_19 = ____opt_9
    if ____opt_9_19 == nil then
        ____opt_9_19 = false
    end
    return ____opt_9_19
end
function campTargets(bot, a)
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        if n ~= nil and n ~= nil and n:IsAlive() and n:CanBeSeen() and not isFirst(a, n) and n:GetAttackTarget() == bot then
            return true
        end
    end
    return false
end
function campNeutrals(bot, campIdx, target, a)
    local out = {}
    local margin = LaneConfig.Settings().Radii.BoxMargin
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.StackCountScan,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() and not isFirst(a, c) and (c == target or Camps.InBox(
            campIdx,
            c:GetLocation(),
            margin
        )) then
            out[#out + 1] = c
        end
    end
    if target ~= nil and not __TS__ArrayIncludes(out, target) then
        out[#out + 1] = target
    end
    return out
end
function describe(bot, a)
    local sp = Camps.SpawnerByIdx(a.campIdx)
    local parts = {}
    for ____, n in ipairs(a.campUnits or ({})) do
        do
            local __continue133
            repeat
                if n:IsNull() or not n:IsAlive() then
                    parts[#parts + 1] = "dead"
                    __continue133 = true
                    break
                end
                local name = (string.gsub(
                    n:GetUnitName(),
                    "npc_dota_neutral_",
                    ""
                ))
                if sp == nil or not n:CanBeSeen() then
                    parts[#parts + 1] = name .. ":?"
                    __continue133 = true
                    break
                end
                local d = math.floor(GetUnitToLocationDistance(n, sp.location))
                local inBox = Camps.InBox(
                    a.campIdx,
                    n:GetLocation(),
                    0
                ) and "in" or "out"
                parts[#parts + 1] = (((((name .. ":") .. tostring(d)) .. ":") .. inBox) .. ":") .. (n:GetAttackTarget() == bot and "a" or "-")
                __continue133 = true
            until true
            if not __continue133 then
                break
            end
        end
    end
    return table.concat(parts, ",")
end
function doubleFields(a)
    if a.double == nil then
        return {}
    end
    local f = a.first
    if f == nil then
        return {{"double", a.double}, {"dwhy", a.dwhy or "?"}}
    end
    local landed = f.aggro ~= nil
    return {
        {"double", a.double},
        {"fres", not landed and "failed" or ((f.fresh or 0) > 0 and "stacked" or "not_stacked")},
        {"fcamp", f.campIdx},
        {"ftype", f.type},
        {
            "faggro",
            landed and math.floor(f.aggro * 10) / 10 or "?"
        },
        {"fbefore", f.before or "?"},
        {"ffresh", f.fresh or "?"},
        {"fbox59", f.box59 or "?"},
        {"fhitd", f.hitd or "?"},
        {"farr", f.arr or "?"}
    }
end
function targetDist(a)
    local t = a.target
    local sp = Camps.SpawnerByIdx(a.campIdx)
    if t == nil or sp == nil or t:IsNull() or not t:IsAlive() or not t:CanBeSeen() then
        return nil
    end
    return math.floor(GetUnitToLocationDistance(t, sp.location))
end
function sample59(bot, a)
    if a.tgt2 == nil and a.aggro ~= nil and DotaTime() >= a.minute * 60 + a.aggro + 2 then
        a.tgt2 = targetDist(a) or -1
        a.n2 = describe(bot, a)
    end
    if a.box59 ~= nil or a.aggro == nil or DotaTime() < a.minute * 60 + 59.5 then
        return
    end
    local sp = Camps.SpawnerByIdx(a.campIdx)
    local data = Camps.ByIdx(a.campIdx)
    if sp == nil then
        return
    end
    local margin = LaneConfig.Settings().Radii.BoxMargin
    local pulled = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() and not Camps.InBox(
            a.campIdx,
            c:GetLocation(),
            margin
        ) then
            pulled = pulled + 1
        end
    end
    a.box59 = CampJobs.Exec.NeutralsInBox(bot, a.campIdx)
    if a.first ~= nil and a.first.aggro ~= nil then
        a.first.box59 = CampJobs.Exec.NeutralsInBox(bot, a.first.campIdx)
    end
    a.tgt59 = targetDist(a) or -1
    local strict = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.StackCountScan,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() and Camps.InBox(
            a.campIdx,
            c:GetLocation(),
            0
        ) then
            strict = strict + 1
        end
    end
    a.strict59 = strict
    a.n59 = describe(bot, a)
    a.hp59 = hpPct(bot)
    a.pulled59 = pulled
    a.bot59 = Camps.InBox(
        a.campIdx,
        bot:GetLocation(),
        0
    ) and 1 or 0
    a.vis59 = IsLocationVisible(sp.location) and 1 or 0
    local path = data ~= nil and data.stack ~= nil and ____exports.ExitPath(sp, data) or nil
    a.exit59 = path ~= nil and #path > 0 and math.floor(GetUnitToLocationDistance(bot, path[#path])) or nil
end
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.SETTINGS = {
    TriggerMinutes = {3, 5, 7},
    LookFrom = 15,
    Lead = 9,
    MinSlack = 3,
    ApproachLead = 6,
    ApproachDist = 250,
    MinHpFraction = 0.5,
    EnemyRadius = 600,
    HitWithin = 3,
    Desire = 0.92,
    StallAfter = 4,
    PreemptAfter = 1,
    ExitTowardLane = true,
    WatchUntil = 5,
    AwayMax = 25,
    FarEnd = 3,
    FirstWindowAt = 0.25,
    SecondWindowAt = 0.75,
    DoubleSlack = 0.5,
    DoubleLead = 5
}
local FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6928, 6372, 392}}
local function override(key)
    local ____opt_0 = Customize.Overrides
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0[key]
    end
    return ____opt_0
end
--- Overrides.Solo names another hero: this one sits out the game in its fountain.
function ____exports.Benched(bot)
    local solo = override("Solo")
    return type(solo) == "number" and solo >= 0 and bot:GetPlayerID() ~= solo
end
--- mode_farm_generic Think for a benched hero: walk to the fountain and stay. False when the hero is not benched.
function ____exports.Bench(bot)
    if not ____exports.Benched(bot) then
        return false
    end
    local x, y, z = unpack(FOUNTAIN[bot:GetTeam()])
    local f = Vector(x, y, z)
    if GetUnitToLocationDistance(bot, f) > 300 then
        bot:Action_MoveToLocation(f)
    end
    return true
end
--- The minutes with an attempt: TriggerMinutes, or every minute from 2 with Overrides.StackEvery.
function ____exports.Minutes()
    if override("StackEvery") ~= true then
        return ____exports.SETTINGS.TriggerMinutes
    end
    local out = {}
    do
        local m = 2
        while m <= 60 do
            out[#out + 1] = m
            m = m + 1
        end
    end
    return out
end
local handled = {}
exits = {}
EXIT_DIRS = {{x = 3978, y = -5027, dx = 1, dy = 0}, {x = -3911, y = 4829, dx = -1, dy = 0}, {x = -4824, y = 3915, dx = 0, dy = 1}}
--- Double-stack partners (EC-063, user lead 31/10/2026), matched by spawner origin as EXIT_DIRS: camp B (the trigger's
-- nearest camp) to camp A, hit first. Only the safe-lane pairs: they are the pos5's own camps (145 of 168 started slice 4
-- 5v5 attempts), and the ancient and wisdom-shrine pairs lie on the offlane side, out of a safe-lane pos5's 25 s reach.
local PAIRS = {{x = 3978, y = -5027, fx = 4649, fy = -3699}, {x = -3911, y = 4829, fx = -4824, fy = 3915}}
local function near(v, x, y)
    return math.abs(v.x - x) <= 200 and math.abs(v.y - y) <= 200
end
--- Camp A for camp B, if B has a listed partner on the same team with a Valve window.
function ____exports.Partner(data)
    local sp = Camps.SpawnerByIdx(data.campIdx)
    if sp == nil then
        return nil
    end
    for ____, p in ipairs(PAIRS) do
        do
            local __continue22
            repeat
                if not near(sp.location, p.x, p.y) then
                    __continue22 = true
                    break
                end
                for ____, s in ipairs(Camps.Spawners()) do
                    do
                        local __continue24
                        repeat
                            if s.team ~= sp.team or not near(s.location, p.fx, p.fy) or (Stacking.Window(s.idx)) == nil then
                                __continue24 = true
                                break
                            end
                            local a = Camps.ByIdx(s.idx, s.team)
                            if a ~= nil and a.stack ~= nil then
                                return a
                            end
                            __continue24 = true
                        until true
                        if not __continue24 then
                            break
                        end
                    end
                end
                __continue22 = true
            until true
            if not __continue22 then
                break
            end
        end
    end
    return nil
end
--- The second of the minute `data`'s hit lands at `at` (0..1) through its Valve window.
function ____exports.WindowSec(data, at)
    local from, to = Stacking.Window(data.campIdx)
    if from == nil or to == nil then
        return Stacking.AggroSec(data)
    end
    return from + (to - from) * at
end
--- The walk from A's stand point to hitting B fits between the two hits: B's neutral is hit from attack range of its box,
-- so a ranged pos5 walks less than a melee one (EC-063's table: most pairs fit a ranged hero only).
function ____exports.Fits(bot, a, b)
    local spa = Camps.SpawnerByIdx(a.campIdx)
    local spb = Camps.SpawnerByIdx(b.campIdx)
    local reach = bot:GetAttackRange() + (spb.max.x - spb.min.x) / 2
    local walk = math.max(
        0,
        dist(
            ____exports.Stand(spa, a),
            spb.location
        ) - reach
    ) / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
    return walk + ____exports.SETTINGS.DoubleSlack <= ____exports.WindowSec(b, ____exports.SETTINGS.SecondWindowAt) - ____exports.WindowSec(a, ____exports.SETTINGS.FirstWindowAt)
end
local gateWhy = {}
local running = {}
function ____exports.ResetCache()
    for k in pairs(handled) do
        __TS__Delete(handled, k)
    end
    for k in pairs(gateWhy) do
        __TS__Delete(gateWhy, k)
    end
    for k in pairs(running) do
        __TS__Delete(running, k)
    end
    for k in pairs(exits) do
        __TS__Delete(exits, k)
    end
end
--- The switch is on and `bot` is OHA position 5.
function ____exports.Applies(bot)
    return Ours.On("StackExecute") and LaneConfig.PositionOf(bot) == 5
end
--- Own-side, not ancient, with a Valve stack window: the camps this job may stack.
function ____exports.Candidates(team)
    local out = {}
    for ____, s in ipairs(Camps.Spawners()) do
        do
            local __continue45
            repeat
                if s.team ~= team or s.type == "ancient" or (Stacking.Window(s.idx)) == nil then
                    __continue45 = true
                    break
                end
                local data = Camps.ByIdx(s.idx, team)
                if data ~= nil and data.stack ~= nil then
                    out[#out + 1] = data
                end
                __continue45 = true
            until true
            if not __continue45 then
                break
            end
        end
    end
    return out
end
--- The candidate whose stand point is nearest `loc`, with that stand point.
function ____exports.Nearest(team, loc)
    local best
    local stand
    for ____, data in ipairs(____exports.Candidates(team)) do
        local sp = Camps.SpawnerByIdx(data.campIdx)
        local p = ____exports.Stand(sp, data)
        if stand == nil or dist(loc, p) < dist(loc, stand) then
            best = data
            stand = p
        end
    end
    return best, stand
end
--- Hero damage just now, checked every frame of a running job (1x probe s4p7: the pos5 was hit at 61% on the walk, kept
-- going and died at the camp to two heroes). Not an enemy hero in reach: lane opponents walk within 600 of a laning pos5,
-- and that check ended 4 jobs 1-6 s after their start (probe s4p8). Not HP or mode: the camp's neutrals hit the bot by
-- design, and the mode is ours.
local function Threat(bot)
    return bot:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.HitWithin) and "hit" or nil
end
--- Why the pos5 may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
-- hero just now, or fighting or retreating.
function ____exports.Gate(bot)
    if bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MinHpFraction then
        return "low-hp"
    end
    if #(bot:GetNearbyHeroes(____exports.SETTINGS.EnemyRadius, true, BotMode.None) or ({})) > 0 then
        return "enemy-near"
    end
    if Threat(bot) ~= nil then
        return "hit"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    return nil
end
--- The verb's camp for `sp`, waiting at `stand`; `others` are neutrals that are not this camp (a double's camp A).
local function campFor(bot, sp, stand, others)
    local r = LaneConfig.Settings().Radii
    local o = sp.location
    local d = math.max(1, ((stand.x - o.x) ^ 2 + (stand.y - o.y) ^ 2) ^ 0.5)
    local close = math.min(d, ____exports.SETTINGS.ApproachDist)
    local approach = Vector(o.x + (stand.x - o.x) * close / d, o.y + (stand.y - o.y) * close / d, o.z)
    local camp = {
        stand = stand,
        box = {min = sp.min, max = sp.max},
        origin = sp.location,
        margin = r.BoxMargin,
        search = r.NeutralSearch,
        confirmed = function() return CampJobs.Exec.NeutralTargets(bot) end,
        approach = approach
    }
    if others == nil then
        return camp
    end
    local function other(n)
        return __TS__ArrayIncludes(
            others() or ({}),
            n
        )
    end
    camp.pick = function()
        local best
        for ____, n in ipairs(bot:GetNearbyNeutralCreeps(r.NeutralSearch, false) or ({})) do
            do
                local __continue64
                repeat
                    if n == nil or n == nil or not n:IsAlive() or not n:CanBeSeen() or other(n) or not Camps.InBox(
                        sp.idx,
                        n:GetLocation(),
                        r.BoxMargin
                    ) then
                        __continue64 = true
                        break
                    end
                    if best == nil or GetUnitToUnitDistance(bot, n) < GetUnitToUnitDistance(bot, best) then
                        best = n
                    end
                    __continue64 = true
                until true
                if not __continue64 then
                    break
                end
            end
        end
        return best
    end
    camp.confirmed = function()
        for ____, n in ipairs(bot:GetNearbyNeutralCreeps(r.NeutralSearch, false) or ({})) do
            if n ~= nil and n ~= nil and n:IsAlive() and n:CanBeSeen() and not other(n) and n:GetAttackTarget() == bot then
                return true
            end
        end
        return false
    end
    return camp
end
function ____exports.Plan(bot, data, stand, minute, a)
    local sp = Camps.SpawnerByIdx(data.campIdx)
    local r = LaneConfig.Settings().Radii
    local t = LaneConfig.Settings().Timing
    local start = minute * 60
    local f = a.first
    local ____temp_2
    if f ~= nil then
        ____temp_2 = Camps.ByIdx(f.campIdx)
    else
        ____temp_2 = nil
    end
    local fd = ____temp_2
    local ____temp_3
    if f ~= nil then
        ____temp_3 = Camps.SpawnerByIdx(f.campIdx)
    else
        ____temp_3 = nil
    end
    local fsp = ____temp_3
    local first = f ~= nil and fd ~= nil and fsp ~= nil and ({
        camp = campFor(
            bot,
            fsp,
            ____exports.Stand(fsp, fd)
        ),
        aggroAt = start + ____exports.WindowSec(fd, ____exports.SETTINGS.FirstWindowAt)
    }) or nil
    local function firstDone()
        return f == nil or f.aggro ~= nil
    end
    return {
        camp = campFor(
            bot,
            sp,
            stand,
            f ~= nil and (function() return f.units end) or nil
        ),
        first = first,
        approachLead = ____exports.SETTINGS.ApproachLead,
        aggroAt = start + (first ~= nil and ____exports.WindowSec(data, ____exports.SETTINGS.SecondWindowAt) or Stacking.AggroSec(data)),
        exitPath = ____exports.ExitPath(sp, data),
        exitUntil = start + 60 + t.StackExitUntil,
        arrive = r.JobArrive,
        onTarget = function(n)
            local u = n
            if not firstDone() or a.aim == u then
                return
            end
            a.aim = u
            a.aimHp = u:GetHealth()
        end,
        onAggro = function(info)
            if f ~= nil and f.aggro == nil then
                f.before = CampJobs.Exec.NeutralsInBox(bot, f.campIdx)
                f.aggro = info.confirmedAt - start
                f.hitd = math.floor(GetUnitToLocationDistance(bot, fsp.location))
                f.units = campNeutrals(bot, f.campIdx, info.target)
                return
            end
            a.target = info.target
            a.campUnits = campNeutrals(bot, data.campIdx, a.target, a)
            a.before = f == nil and CampJobs.Exec.NeutralsInBox(bot, data.campIdx) or #a.campUnits
            a.aggro = info.confirmedAt - start
            a.hitd = math.floor(GetUnitToLocationDistance(bot, sp.location))
        end
    }
end
--- Seconds to walk from the bot to `p`.
local function travel(bot, p)
    return GetUnitToLocationDistance(bot, p) / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
local body = __TS__Generator(function(bot, plan, a, ctx)
    local function label(l)
        ctx.label(l)
        phase(bot, a, l)
    end
    local r = __TS__DelegatedYield(Tasks.Jobs().stack(bot, plan, {label = label, urgent = ctx.urgent}))
    if not r.success then
        return r
    end
    ctx.label("watch")
    local spawnCheck = a.minute * 60 + 60
    local outcomeAt = spawnCheck + LaneConfig.Settings().Timing.StackOutcomeAt
    local f = a.first
    local stopped = false
    local campIdx = a.campIdx
    while DotaTime() < math.min(spawnCheck + ____exports.SETTINGS.WatchUntil, a.startedAt + ____exports.SETTINGS.AwayMax - 0.5) do
        if not bot:IsAlive() then
            return {success = false, reason = "dead"}
        end
        if CampJobs.Exec.BoxInSight(bot, campIdx) then
            if not stopped then
                bot:Action_MoveToLocation(bot:GetLocation())
            end
            stopped = true
            if DotaTime() >= outcomeAt then
                local fresh = freshInBox(bot, a, campIdx)
                if campIdx == a.campIdx then
                    a.after = math.max(
                        a.after or 0,
                        CampJobs.Exec.NeutralsInBox(bot, a.campIdx)
                    )
                    a.fresh = math.max(a.fresh or 0, fresh)
                else
                    f.fresh = math.max(f.fresh or 0, fresh)
                end
                if fresh > 0 then
                    if f == nil or campIdx ~= a.campIdx then
                        break
                    end
                    campIdx = f.campIdx
                    stopped = false
                end
            end
        else
            bot:Action_MoveToLocation(Camps.SpawnerByIdx(campIdx).location)
        end
        coroutine.yield()
    end
    return {success = true, reason = "ok"}
end)
--- Every frame of a running job, from Desire: farm's Think does not run while the bot casts (J.CanNotUseAction).
local function track(bot, a)
    local ab = bot:GetCurrentActiveAbility()
    local name = ab ~= nil and ab ~= nil and ab:GetName() or nil
    if name ~= nil and name ~= a.lastCast then
        a.casts = a.casts or ({})
        local ____a_casts_4 = a.casts
        ____a_casts_4[#____a_casts_4 + 1] = (name .. "@") .. tostring(sec(a))
    end
    a.lastCast = name
    if DotaTime() < a.minute * 60 + 60 then
        a.seen = a.seen or __TS__New(Set)
        for ____, c in ipairs(bot:GetNearbyNeutralCreeps(SEEN_SCAN, false) or ({})) do
            if c ~= nil and c ~= nil and c:IsAlive() then
                a.seen:add(c)
            end
        end
    end
    sample59(bot, a)
    if a.hit0 ~= nil then
        local n = a.aim
        if a.dmg == nil and n ~= nil and not n:IsNull() and (not n:IsAlive() or n:GetHealth() < (a.aimHp or 0)) then
            a.dmg = sec(a)
        end
        if a.react == nil and campTargets(bot, a) then
            a.react = sec(a)
        end
    end
    if a.aggro ~= nil then
        a.lane = math.max(
            a.lane or 0,
            laneNear(bot, a)
        )
    end
end
LANE_NEAR = 900
--- Neutral scan radius for the seen set (the API's maximum).
SEEN_SCAN = 1600
local function log(bot, minute, fields)
    Telemetry.Event(
        "stack",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"min", minute},
            unpack(fields)
        }
    )
end
--- What the bot sees of the camp as the attempt ends, so a `no_target` reads as an empty camp or a wrong box from the log.
local function look(bot, a)
    local sp = Camps.SpawnerByIdx(a.campIdx)
    if sp == nil or not bot:IsAlive() then
        return
    end
    local near = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() then
            near = near + 1
        end
    end
    a.near = near
    a.inbox = CampJobs.Exec.NeutralsInBox(bot, a.campIdx)
    a.dist = math.floor(GetUnitToLocationDistance(bot, sp.location))
    a.vis = IsLocationVisible(sp.location) and 1 or 0
end
local function finish(bot, a, result)
    running[bot:GetPlayerID()] = nil
    look(bot, a)
    local sp = Camps.SpawnerByIdx(a.campIdx)
    local landed = a.aggro ~= nil
    local res = not landed and "failed" or ((a.fresh or 0) > 0 and "stacked" or "not_stacked")
    log(
        bot,
        a.minute,
        {
            {"res", res},
            {"why", result.success and "ok" or result.reason .. (result.message ~= nil and ":" .. result.message or "")},
            {"camp", a.campIdx},
            {"type", a.type},
            {
                "start",
                math.floor(a.startedAt * 10) / 10
            },
            {
                "aggro",
                a.aggro ~= nil and math.floor(a.aggro * 10) / 10 or "?"
            },
            {"before", a.before or "?"},
            {"after", a.after or "?"},
            {"fresh", a.fresh or "?"},
            {
                "away",
                math.floor((DotaTime() - a.startedAt) * 10) / 10
            },
            {
                "death",
                (result.reason == "dead" or not bot:IsAlive()) and 1 or 0
            },
            {
                "cx",
                sp ~= nil and math.floor(sp.location.x) or "?"
            },
            {
                "cy",
                sp ~= nil and math.floor(sp.location.y) or "?"
            },
            {"dist", a.dist or "?"},
            {"near", a.near or "?"},
            {"inbox", a.inbox or "?"},
            {"vis", a.vis or "?"},
            {"box59", a.box59 or "?"},
            {"pulled59", a.pulled59 or "?"},
            {"bot59", a.bot59 or "?"},
            {"vis59", a.vis59 or "?"},
            {"exit59", a.exit59 or "?"},
            {"hitd", a.hitd or "?"},
            {"tgt2", (a.tgt2 == nil or a.tgt2 < 0) and "?" or a.tgt2},
            {"tgt59", (a.tgt59 == nil or a.tgt59 < 0) and "?" or a.tgt59},
            {"strict59", a.strict59 or "?"},
            {"arr", a.arr or "?"},
            {"hit0", a.hit0 or "?"},
            {"dmg", a.dmg or "?"},
            {"react", a.react or "?"},
            {"exit", a.exitAt or "?"},
            {"hpa", a.hpa or "?"},
            {"hpe", a.hpe or "?"},
            {"hp59", a.hp59 or "?"},
            {
                "casts",
                a.casts ~= nil and table.concat(a.casts, ",") or "-"
            },
            {"n2", a.n2 or "?"},
            {"n59", a.n59 or "?"},
            {"lane", a.aggro ~= nil and (a.lane or 0) or "?"},
            {"idle", a.idle or 0},
            unpack(doubleFields(a))
        }
    )
end
--- mode_farm_generic GetDesire: the job's desire while it runs or as it starts, else 0 (OHA decides).
function ____exports.Desire(bot)
    if not ____exports.Applies(bot) then
        return 0
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        track(bot, running[pid])
        local threat = Threat(bot)
        if threat == nil then
            return ____exports.SETTINGS.Desire
        end
        Tasks.Cancel(bot, "cancelled", threat)
        return 0
    end
    local now = DotaTime()
    handled[pid] = handled[pid] or ({})
    for ____, minute in ipairs(____exports.Minutes()) do
        do
            local __continue151
            repeat
                if handled[pid][minute] or now < minute * 60 + ____exports.SETTINGS.LookFrom or now >= minute * 60 + 60 then
                    __continue151 = true
                    break
                end
                local data, stand = ____exports.Nearest(
                    bot:GetTeam(),
                    bot:GetLocation()
                )
                local function skip(why)
                    handled[pid][minute] = true
                    gateWhy[pid] = nil
                    log(bot, minute, {{"res", "skip"}, {"why", why}})
                    return 0
                end
                if data == nil or stand == nil or Tasks.Jobs() == nil then
                    return skip("no-camp")
                end
                local ____Ours_On_result_20
                if Ours.On("DoubleStack") then
                    ____Ours_On_result_20 = ____exports.Partner(data)
                else
                    ____Ours_On_result_20 = nil
                end
                local fd = ____Ours_On_result_20
                local double = fd ~= nil and ____exports.Fits(bot, fd, data)
                local dwhy = fd ~= nil and not double and "walk" or nil
                local aggroAt = minute * 60 + Stacking.AggroSec(data)
                local walk = travel(bot, stand)
                local lead = ____exports.SETTINGS.Lead
                if double then
                    local fAt = minute * 60 + ____exports.WindowSec(fd, ____exports.SETTINGS.FirstWindowAt)
                    local fWalk = travel(
                        bot,
                        ____exports.Stand(
                            Camps.SpawnerByIdx(fd.campIdx),
                            fd
                        )
                    )
                    dwhy = minute * 60 + 60 + ____exports.SETTINGS.FarEnd - (fAt - fWalk - ____exports.SETTINGS.MinSlack) > ____exports.SETTINGS.AwayMax and "far" or (now > fAt - fWalk - ____exports.SETTINGS.MinSlack and "late" or nil)
                    double = dwhy == nil
                    if double then
                        aggroAt, walk, lead = fAt, fWalk, ____exports.SETTINGS.DoubleLead
                    end
                end
                if now < aggroAt - walk - lead then
                    return 0
                end
                if now > aggroAt - walk - ____exports.SETTINGS.MinSlack then
                    return skip(gateWhy[pid] or "late")
                end
                if minute * 60 + 60 + ____exports.SETTINGS.FarEnd - now > ____exports.SETTINGS.AwayMax then
                    return skip("far")
                end
                local why = ____exports.Gate(bot)
                if why ~= nil then
                    gateWhy[pid] = why
                    return 0
                end
                local a = {minute = minute, campIdx = data.campIdx, type = data.type, startedAt = now}
                if fd ~= nil then
                    a.double = double and 1 or 0
                end
                a.dwhy = dwhy
                if double then
                    a.first = {campIdx = fd.campIdx, type = fd.type}
                end
                local plan = ____exports.Plan(
                    bot,
                    data,
                    stand,
                    minute,
                    a
                )
                local ok = Tasks.Start(
                    bot,
                    {
                        name = "stack",
                        host = BotMode.Farm,
                        preemptAfter = ____exports.SETTINGS.PreemptAfter,
                        stallAfter = ____exports.SETTINGS.StallAfter,
                        onEnd = function(result) return finish(bot, a, result) end
                    },
                    function(ctx) return body(bot, plan, a, ctx) end
                )
                if not ok then
                    return skip("refused")
                end
                handled[pid][minute] = true
                gateWhy[pid] = nil
                running[pid] = a
                return ____exports.SETTINGS.Desire
            until true
            if not __continue151 then
                break
            end
        end
    end
    return 0
end
function ____exports.Think(bot)
    local a = running[bot:GetPlayerID()]
    if a == nil then
        return false
    end
    return Tasks.Step(bot, BotMode.Farm)
end
--- mode_farm_generic's ShouldRun: neutrals hitting the pos5 during its stack are not a reason to run; the job's exit is its
-- retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
function ____exports.HoldsRun(bot)
    return running[bot:GetPlayerID()] ~= nil
end
--- ability_item_usage: spells and items wait while the job runs, as camp_jobs' HoldsCasts does for camp jobs. OHA's farm
-- branches cast on the camp: witch doctor's cask landed at :42-:47, before the hit, and once after it, and the stunned
-- neutrals walked back into the box (user replay and s4solo2); a TP scroll on the walk stalled the job (s4solo2 5:4x).
-- An enemy hero in reach lifts it so the bot can fight or save itself. Benched heroes (Overrides.Solo) never cast.
function ____exports.HoldsCasts(bot)
    if ____exports.Benched(bot) then
        return true
    end
    if running[bot:GetPlayerID()] == nil then
        return false
    end
    return #(bot:GetNearbyHeroes(____exports.SETTINGS.EnemyRadius, true, BotMode.None) or ({})) == 0
end
--- jmz_func CheckBotIdleState (called from team_roam's GetDesire whatever mode is active): a bot in farm mode that moved
-- under 100 in 3 s gets ClearActions and an attack-move to its lane front. A stack job stands still at its stand point by
-- design, and when the check fell inside the 2 s after the hit order it replaced the attack: all 4 slice 4 `no-aggro` misses
-- (attack-move from the order to the miss, s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55). True while the job
-- runs, counted on the attempt.
function ____exports.HoldsIdle(bot)
    local a = running[bot:GetPlayerID()]
    if a == nil then
        return false
    end
    a.idle = (a.idle or 0) + 1
    return true
end
--- OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`.
function ____exports.Abort(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
return ____exports
