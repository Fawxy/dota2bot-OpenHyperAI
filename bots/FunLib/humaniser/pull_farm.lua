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

local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
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

local Map
do
    Map = __TS__Class()
    Map.name = "Map"
    function Map.prototype.____constructor(self, entries)
        self[Symbol.toStringTag] = "Map"
        self.items = {}
        self.size = 0
        self.nextKey = {}
        self.previousKey = {}
        if entries == nil then
            return
        end
        local iterable = entries
        if iterable[Symbol.iterator] then
            local iterator = iterable[Symbol.iterator](iterable)
            while true do
                local result = iterator:next()
                if result.done then
                    break
                end
                local value = result.value
                self:set(value[1], value[2])
            end
        else
            local array = entries
            for ____, kvp in ipairs(array) do
                self:set(kvp[1], kvp[2])
            end
        end
    end
    function Map.prototype.clear(self)
        self.items = {}
        self.nextKey = {}
        self.previousKey = {}
        self.firstKey = nil
        self.lastKey = nil
        self.size = 0
    end
    function Map.prototype.delete(self, key)
        local contains = self:has(key)
        if contains then
            self.size = self.size - 1
            local next = self.nextKey[key]
            local previous = self.previousKey[key]
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
            self.nextKey[key] = nil
            self.previousKey[key] = nil
        end
        self.items[key] = nil
        return contains
    end
    function Map.prototype.forEach(self, callback)
        for ____, key in __TS__Iterator(self:keys()) do
            callback(nil, self.items[key], key, self)
        end
    end
    function Map.prototype.get(self, key)
        return self.items[key]
    end
    function Map.prototype.has(self, key)
        return self.nextKey[key] ~= nil or self.lastKey == key
    end
    function Map.prototype.set(self, key, value)
        local isNewValue = not self:has(key)
        if isNewValue then
            self.size = self.size + 1
        end
        self.items[key] = value
        if self.firstKey == nil then
            self.firstKey = key
            self.lastKey = key
        elseif isNewValue then
            self.nextKey[self.lastKey] = key
            self.previousKey[key] = self.lastKey
            self.lastKey = key
        end
        return self
    end
    Map.prototype[Symbol.iterator] = function(self)
        return self:entries()
    end
    function Map.prototype.entries(self)
        local items = self.items
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = {key, items[key]}}
                key = nextKey[key]
                return result
            end
        }
    end
    function Map.prototype.keys(self)
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
    function Map.prototype.values(self)
        local items = self.items
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = items[key]}
                key = nextKey[key]
                return result
            end
        }
    end
    Map[Symbol.species] = Map
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

local function __TS__SparseArrayNew(...)
    local sparseArray = {...}
    sparseArray.sparseLength = __TS__CountVarargs(...)
    return sparseArray
end

local function __TS__SparseArrayPush(sparseArray, ...)
    local args = {...}
    local argsLen = __TS__CountVarargs(...)
    local listLen = sparseArray.sparseLength
    for i = 1, argsLen do
        sparseArray[listLen + i] = args[i]
    end
    sparseArray.sparseLength = listLen + argsLen
end

local function __TS__SparseArraySpread(sparseArray)
    local _unpack = unpack or table.unpack
    return _unpack(sparseArray, 1, sparseArray.sparseLength)
end
-- End of Lua Library inline imports
local ____exports = {}
local locOf, dist, madstones, campLeft, running, pickUp
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local UnitType = ____dota.UnitType
local CampClaims = require(GetScriptDirectory().."/FunLib/humaniser/camp_claims")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CoreCamp = require(GetScriptDirectory().."/FunLib/humaniser/core_camp")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local LaneSpot = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_spot")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function locOf(u)
    local at = u:GetLocation()
    local ____temp_0
    if at == nil then
        ____temp_0 = nil
    else
        ____temp_0 = at
    end
    return ____temp_0
end
function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function madstones(center)
    local out = __TS__New(Map)
    for ____, d in ipairs(GetDroppedItemList() or ({})) do
        do
            local __continue61
            repeat
                if d == nil or d == nil or d.item == nil or d.item == nil or d.location == nil then
                    __continue61 = true
                    break
                end
                if (string.find(
                    d.item:GetName(),
                    ____exports.SETTINGS.PickName,
                    1,
                    true
                )) == nil or dist(d.location, center) > ____exports.SETTINGS.PickRadius then
                    __continue61 = true
                    break
                end
                out:set(
                    (tostring(math.floor(d.location.x)) .. ",") .. tostring(math.floor(d.location.y)),
                    d
                )
                __continue61 = true
            until true
            if not __continue61 then
                break
            end
        end
    end
    return out
end
--- Picks up the madstone drops by the cleared camp (SETTINGS PickName), nearest first, for at most PickMax seconds.
pickUp = __TS__Generator(function(bot, f, ctx)
    local left = madstones(f.center)
    f.ms = left.size
    f.mp = 0
    local done = {success = true, reason = "ok"}
    if f.ms == 0 then
        return done
    end
    ctx.label("pickup")
    local from = DotaTime()
    local ordered = {}
    local orderedAt = -math.huge
    while bot:IsAlive() and DotaTime() - from <= ____exports.SETTINGS.PickMax do
        local best
        local bestKey
        for ____, ____value in __TS__Iterator(left) do
            local k = ____value[1]
            local d = ____value[2]
            if best == nil or dist(
                bot:GetLocation(),
                d.location
            ) < dist(
                bot:GetLocation(),
                best.location
            ) then
                best = d
                bestKey = k
            end
        end
        if best == nil or bestKey == nil then
            break
        end
        if DotaTime() - orderedAt >= ____exports.SETTINGS.ReturnReorder then
            bot:Action_PickUpItem(best.item)
            if __TS__ArrayIndexOf(ordered, bestKey) < 0 then
                ordered[#ordered + 1] = bestKey
            end
            orderedAt = DotaTime()
        end
        coroutine.yield()
        local now = madstones(f.center)
        f.mp = f.mp + #__TS__ArrayFilter(
            ordered,
            function(____, k) return not now:has(k) end
        )
        ordered = __TS__ArrayFilter(
            ordered,
            function(____, k) return now:has(k) end
        )
        left = now
    end
    return done
end)
function campLeft(center)
    local n = 0
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps) or ({})) do
        do
            local __continue77
            repeat
                if u == nil or u == nil or not u:IsAlive() then
                    __continue77 = true
                    break
                end
                local at = locOf(u)
                if at ~= nil and dist(at, center) <= ____exports.SETTINGS.CampRadius then
                    n = n + 1
                end
                __continue77 = true
            until true
            if not __continue77 then
                break
            end
        end
    end
    return n
end
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
____exports.SETTINGS = {
    Priority = 0.88,
    StartWithin = 12,
    MaxFarm = 35,
    AbortHP = 0.35,
    CampRadius = 700,
    CoreThere = 600,
    ReturnArrive = 900,
    ReturnMax = 25,
    ReturnReorder = 0.5,
    PickName = "madstone",
    PickRadius = 900,
    PickMax = 6,
    LastHit = true,
    LastHitAll = true,
    LastHitHits = 2
}
running = {}
--- The pull end (`at`) each hero's window was last settled for: one start or one skip line per pull.
local handled = {}
local lastWhy = {}
function ____exports.ResetCache()
    for ____, t in ipairs({running, handled, lastWhy}) do
        for k in pairs(t) do
            __TS__Delete(t, k)
        end
    end
end
function ____exports.Applies(bot)
    return Ours.On("SupportPullFarm") and PullJob.Applies(bot)
end
function ____exports.Priority(bot)
    return ____exports.Applies(bot) and ____exports.SETTINGS.Priority or nil
end
function ____exports.Claims(bot)
    return ____exports.Running(bot)
end
local function hpShare(bot)
    return bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    )
end
--- An ally core (pos1-3) already at the camp.
local function coreThere(bot, center)
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue13
            repeat
                if a == nil or a == nil or not a:IsAlive() or a == bot or (LaneConfig.PositionOf(a) or 9) > 3 then
                    __continue13 = true
                    break
                end
                local at = locOf(a)
                if at ~= nil and dist(at, center) <= ____exports.SETTINGS.CoreThere then
                    return true
                end
                __continue13 = true
            until true
            if not __continue13 then
                break
            end
        end
    end
    return false
end
--- Why the support may not start on the camp now, or undefined.
local function startGate(bot, camp, center, blocked)
    local state = PullJob.CampStateOf(camp)
    if state.n == 0 then
        return "no-neutrals"
    end
    if CampClaims.On("core", camp.idx) ~= nil then
        return "core-coming"
    end
    if coreThere(bot, center) then
        return "core-there"
    end
    local dmg = PullJob.CampDamage(bot, state, camp.type, nil)
    if bot:GetHealth() - dmg < bot:GetMaxHealth() * PullJob.SETTINGS.StartReserve then
        return "camp-dmg"
    end
    if CoreCamp.ThreatOnWay(bot, center) then
        return "threat"
    end
    return blocked(bot) or PullJob.PartnerThreat(bot)
end
local function fields(bot, f, camp)
    return {
        {
            "pid",
            bot:GetPlayerID()
        },
        {
            "pos",
            LaneConfig.PositionOf(bot)
        },
        {
            "lane",
            bot:GetAssignedLane()
        },
        {"camp", camp},
        {"ago", f and f.ago},
        {"div", f and f.div},
        {"n0", f and f.n0}
    }
end
local function jobLine(bot, f, phase, why)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "pullfarm"},
            {"phase", phase},
            {"why", why},
            {"host", f.host},
            unpack(phase == "end" and ({{"hit", f.hit == true and 1 or 0}}) or ({}))
        }
    )
end
--- Why the farm must stop now (the task's guard, every frame), or undefined. The walk back ignores heroes: laning decides.
local function guard(bot, f)
    if f.returning == true then
        return nil
    end
    if CampClaims.On("core", f.camp) ~= nil then
        return "yield"
    end
    if hpShare(bot) < ____exports.SETTINGS.AbortHP then
        return "hp"
    end
    local near = false
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue29
            repeat
                if e == nil or e == nil or not e:IsAlive() or e:IsIllusion() then
                    __continue29 = true
                    break
                end
                local at = locOf(e)
                if at ~= nil and dist(
                    at,
                    bot:GetLocation()
                ) <= LaneSpot.HeroReach(bot, e) then
                    near = true
                end
                __continue29 = true
            until true
            if not __continue29 then
                break
            end
        end
    end
    if not near then
        f.threatSince = nil
        return nil
    end
    local now = DotaTime()
    f.threatSince = f.threatSince or now
    return now - f.threatSince >= Profile.Get(bot).reactBase and "threat" or nil
end
local walkBack = __TS__Generator(function(bot, f, ctx)
    ctx.label("return")
    f.returning = true
    local from = DotaTime()
    local orderedAt = -math.huge
    while true do
        if not bot:IsAlive() then
            return {success = false, reason = "dead"}
        end
        local now = DotaTime()
        local front = GetLaneFrontLocation(
            bot:GetTeam(),
            f.lane,
            0
        )
        if dist(
            bot:GetLocation(),
            front
        ) <= ____exports.SETTINGS.ReturnArrive then
            f.back = now
            return {success = true, reason = "ok", message = "back"}
        end
        if now - from > ____exports.SETTINGS.ReturnMax then
            return {success = false, reason = "timeout", message = "late"}
        end
        if now - orderedAt >= ____exports.SETTINGS.ReturnReorder then
            bot:Action_MoveToLocation(front)
            orderedAt = now
        end
        coroutine.yield()
    end
end)
--- Madstone charges in `bot`'s item slots (inventory, backpack, stash and neutral slot).
local function madstoneCharges(bot)
    local n = 0
    do
        local slot = 0
        while slot <= 16 do
            do
                local __continue41
                repeat
                    local it = bot:GetItemInSlot(slot)
                    if it == nil or it == nil or (string.find(
                        it:GetName(),
                        ____exports.SETTINGS.PickName,
                        1,
                        true
                    )) == nil then
                        __continue41 = true
                        break
                    end
                    local ____math_max_9 = math.max
                    local ____opt_7 = it.GetCurrentCharges
                    n = n + ____math_max_9(
                        1,
                        ____opt_7 and ____opt_7(it) or 1
                    )
                    __continue41 = true
                until true
                if not __continue41 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return n
end
--- A unit of ours other than `bot` (the pulled wave's creeps, an ally hero) attacking `n`.
local function othersOn(bot, n)
    for ____, kind in ipairs({UnitType.AlliedCreeps, UnitType.AlliedHeroes}) do
        for ____, u in ipairs(GetUnitList(kind) or ({})) do
            if u ~= nil and u ~= nil and u ~= bot and u:IsAlive() and u:GetAttackTarget() == n then
                return true
            end
        end
    end
    return false
end
--- The clear waits for the killing hit on `n` (SETTINGS LastHit).
local function takeLastHit(bot, n, camp)
    if not ____exports.SETTINGS.LastHit or not ____exports.SETTINGS.LastHitAll and #camp > 1 or not othersOn(bot, n) then
        return false
    end
    local hit = n:GetActualIncomingDamage(
        bot:GetAttackDamage(),
        DamageType.Physical
    )
    return n:GetHealth() <= ____exports.SETTINGS.LastHitHits * math.max(1, hit)
end
local body = __TS__Generator(function(bot, f, ctx)
    local hooks = {
        label = function(l) return ctx.label(l) end,
        urgent = ctx.urgent
    }
    local lh = bot:GetLastHits()
    local r = __TS__DelegatedYield(Tasks.Jobs().clearCamp(
        bot,
        {
            at = f.center,
            radius = ____exports.SETTINGS.CampRadius,
            deadline = f.left + ____exports.SETTINGS.MaxFarm,
            lastHit = function(n, camp) return takeLastHit(bot, n, camp) end,
            onLastHit = function(_n, res)
                f.lt = (f.lt or 0) + 1
                if res.success then
                    f.lk = (f.lk or 0) + 1
                end
            end,
            onGone = function(_n, at, left)
                local now = bot:GetLastHits()
                local mine = now > lh
                lh = now
                if left > 0 then
                    return
                end
                f.fl = mine and 1 or 0
                f.fd = math.floor(dist(
                    bot:GetLocation(),
                    at
                ) + 0.5)
            end
        },
        hooks
    ))
    if r.success and r.message == "cleared" and f.fl == nil then
        f.fl = 0
    end
    f.nl = campLeft(f.center)
    if not r.success then
        return r
    end
    __TS__DelegatedYield(pickUp(bot, f, ctx))
    return __TS__DelegatedYield(walkBack(bot, f, ctx))
end)
local function finish(bot, f, r, label)
    running[bot:GetPlayerID()] = nil
    CampClaims.Set(
        "pullfarm",
        bot:GetPlayerID(),
        nil
    )
    local why = r.success and (r.message or "ok") or r.reason .. (r.message ~= nil and ":" .. r.message or "")
    jobLine(bot, f, "end", why)
    local function r1(x)
        return x ~= nil and math.floor(x * 10 + 0.5) / 10 or nil
    end
    local ____Telemetry_Event_11 = Telemetry.Event
    local ____array_10 = __TS__SparseArrayNew(
        {"phase", "end"},
        unpack(fields(bot, f, f.camp))
    )
    __TS__SparseArrayPush(
        ____array_10,
        {"res", r.success and "ok" or "fail"},
        {"why", why},
        {"label", label},
        {
            "nl",
            f.nl or (label == "return" and 0 or campLeft(f.center))
        },
        {
            "back",
            r1(f.back)
        },
        {"g0", f.g0},
        {
            "g1",
            bot:GetNetWorth()
        },
        {
            "secs",
            r1(DotaTime() - f.left)
        },
        {
            "hp0",
            math.floor(f.hp0 * 100 + 0.5) / 100
        },
        {
            "hp",
            math.floor(hpShare(bot) * 100 + 0.5) / 100
        },
        {
            "died",
            bot:IsAlive() and 0 or 1
        },
        {"ms", f.ms},
        {"mp", f.mp},
        {
            "lh",
            bot:GetLastHits() - f.lh0
        },
        {"lt", f.lt},
        {"lk", f.lk},
        {"fl", f.fl},
        {"fd", f.fd},
        {
            "mi",
            madstoneCharges(bot) - f.mi0
        }
    )
    ____Telemetry_Event_11(
        "pull_clear",
        {__TS__SparseArraySpread(____array_10)}
    )
end
--- Every frame while the chooser asks: true while a farm runs or as one starts. A farm may start only in the StartWithin
-- seconds after this hero's ok pull, on the pull's own camp; the window closes with one skip line naming the gate that held it.
function ____exports.Wants(bot, blocked, host)
    if not ____exports.Applies(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    if Tasks.Jobs() == nil or not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return false
    end
    local pull = PullJob.Finished(bot)
    if pull == nil or handled[pid] == pull.at then
        return false
    end
    local now = DotaTime()
    local camp = Camps.SpawnerByIdx(pull.camp)
    local ago = now - pull.at
    if camp == nil then
        return false
    end
    local center = Camps.BoxCenter(camp)
    local f = {
        camp = pull.camp,
        center = center,
        lane = bot:GetAssignedLane(),
        left = now,
        host = host,
        ago = math.floor(ago * 10 + 0.5) / 10,
        div = pull.div,
        n0 = PullJob.CampStateOf(camp).n,
        g0 = bot:GetNetWorth(),
        hp0 = hpShare(bot),
        lh0 = bot:GetLastHits(),
        mi0 = madstoneCharges(bot)
    }
    local why = ago > ____exports.SETTINGS.StartWithin and (lastWhy[pid] or "late") or startGate(bot, camp, center, blocked)
    if why ~= nil then
        lastWhy[pid] = why
        if ago > ____exports.SETTINGS.StartWithin or why == "no-neutrals" or why == "core-coming" or why == "core-there" then
            handled[pid] = pull.at
            lastWhy[pid] = nil
            local ____Telemetry_Event_13 = Telemetry.Event
            local ____array_12 = __TS__SparseArrayNew(
                {"phase", "skip"},
                unpack(fields(bot, f, pull.camp))
            )
            __TS__SparseArrayPush(____array_12, {"why", why})
            ____Telemetry_Event_13(
                "pull_clear",
                {__TS__SparseArraySpread(____array_12)}
            )
        end
        return false
    end
    handled[pid] = pull.at
    lastWhy[pid] = nil
    local ok = Tasks.Start(
        bot,
        {
            name = "pullfarm",
            host = host,
            preemptAfter = 1,
            stallAfter = 4,
            guard = function() return guard(bot, f) end,
            onEnd = function(r, info) return finish(bot, f, r, info.label) end
        },
        function(ctx) return body(bot, f, ctx) end
    )
    if not ok then
        local ____Telemetry_Event_15 = Telemetry.Event
        local ____array_14 = __TS__SparseArrayNew(
            {"phase", "skip"},
            unpack(fields(bot, f, pull.camp))
        )
        __TS__SparseArrayPush(____array_14, {"why", "refused"})
        ____Telemetry_Event_15(
            "pull_clear",
            {__TS__SparseArraySpread(____array_14)}
        )
        return false
    end
    running[pid] = f
    CampClaims.Set("pullfarm", pid, f.camp)
    jobLine(bot, f, "start", "trigger")
    local ____Telemetry_Event_17 = Telemetry.Event
    local ____array_16 = __TS__SparseArrayNew(
        {"phase", "start"},
        unpack(fields(bot, f, f.camp))
    )
    __TS__SparseArrayPush(
        ____array_16,
        {
            "hp0",
            math.floor(f.hp0 * 100 + 0.5) / 100
        }
    )
    ____Telemetry_Event_17(
        "pull_clear",
        {__TS__SparseArraySpread(____array_16)}
    )
    return true
end
function ____exports.Step(bot, host)
    return running[bot:GetPlayerID()] ~= nil and Tasks.Step(bot, host)
end
function ____exports.End(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
function ____exports.NoteHit(bot)
    local f = running[bot:GetPlayerID()]
    if f ~= nil then
        f.hit = true
    end
end
function ____exports.NoteIdleHeld(_bot)
end
return ____exports
