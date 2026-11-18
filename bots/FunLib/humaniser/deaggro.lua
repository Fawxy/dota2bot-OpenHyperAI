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
local usable, close, open
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function usable(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive()
end
function close(bot, o, result, now, onUs)
    __TS__Delete(
        open,
        bot:GetPlayerID()
    )
    Telemetry.Event(
        "deaggro",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", o.kinds},
            {"result", result},
            {"n", #o.attackers},
            {"lk", o.locked},
            {"cov", o.covers},
            {"left", onUs},
            {
                "dt",
                math.floor((now - o.orderedAt) * 100) / 100
            },
            {
                "hp",
                math.floor(o.hp * 100) / 100
            },
            {
                "dhp",
                math.floor((o.hp - bot:GetHealth() / math.max(
                    1,
                    bot:GetMaxHealth()
                )) * 100) / 100
            }
        }
    )
    return result
end
--- The open attempt, read each frame by the caller (undefined: none open). `ok` once no unlocked attacker that was on us at the
-- order still targets us (dead or gone counts as off); `still_hit` if some still do after ConfirmFor; `gone` when the hero died;
-- `stale` when the caller has not watched for StaleAfter.
function ____exports.Watch(bot)
    local o = open[bot:GetPlayerID()]
    if o == nil then
        return nil
    end
    local now = DotaTime()
    if not bot:IsAlive() then
        return close(
            bot,
            o,
            "gone",
            now,
            0
        )
    end
    if now - o.watchedAt > ____exports.SETTINGS.StaleAfter then
        return close(
            bot,
            o,
            "stale",
            now,
            0
        )
    end
    o.watchedAt = now
    local onUs = 0
    for ____, a in ipairs(o.attackers) do
        if not a.fact.locked and usable(a.unit) and a.unit:GetAttackTarget() == bot then
            onUs = onUs + 1
        end
    end
    if onUs == 0 then
        return close(
            bot,
            o,
            "ok",
            now,
            0
        )
    end
    if now - o.orderedAt >= ____exports.SETTINGS.ConfirmFor then
        return close(
            bot,
            o,
            "still_hit",
            now,
            onUs
        )
    end
    return "pending"
end
____exports.SETTINGS = {ScanR = 1600, ConfirmFor = 1, StaleAfter = 0.5}
local function dist(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return math.sqrt(dx * dx + dy * dy)
end
--- Pure: our unit the most unlocked attackers would switch to, nearest the hero on a tie.
function ____exports.Plan(attackers, ours)
    local locked = 0
    for ____, a in ipairs(attackers) do
        if a.locked then
            locked = locked + 1
        end
    end
    if #attackers == 0 then
        return {covers = 0, locked = locked, why = "none"}
    end
    if locked == #attackers then
        return {covers = 0, locked = locked, why = "locked"}
    end
    local best
    local bestN = 0
    do
        local i = 0
        while i < #ours do
            local o = ours[i + 1]
            local n = 0
            for ____, a in ipairs(attackers) do
                if not a.locked and dist(a.x, a.y, o.x, o.y) <= a.reach then
                    n = n + 1
                end
            end
            if n > bestN or n == bestN and n > 0 and best ~= nil and o.d < ours[best + 1].d then
                best = i
                bestN = n
            end
            i = i + 1
        end
    end
    if best == nil then
        return {covers = 0, locked = locked, why = "no_unit"}
    end
    return {target = best, covers = bestN, locked = locked}
end
--- Who targets the hero now: enemy towers and enemy lane creeps whose attack target is it. Each unit is read once.
function ____exports.Read(bot)
    local out = {}
    local here = bot:GetLocation()
    local br = bot:GetBoundingRadius()
    for ____, t in ipairs(bot:GetNearbyTowers(____exports.SETTINGS.ScanR, true) or ({})) do
        do
            local __continue17
            repeat
                if not usable(t) or t:GetAttackTarget() ~= bot then
                    __continue17 = true
                    break
                end
                local at = t:GetLocation()
                out[#out + 1] = {
                    unit = t,
                    fact = {
                        kind = "tower",
                        x = at.x,
                        y = at.y,
                        reach = t:GetAttackRange() + t:GetBoundingRadius(),
                        locked = false
                    }
                }
                __continue17 = true
            until true
            if not __continue17 then
                break
            end
        end
    end
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(____exports.SETTINGS.ScanR, true) or ({})) do
        do
            local __continue20
            repeat
                if not usable(c) or c:GetAttackTarget() ~= bot then
                    __continue20 = true
                    break
                end
                local at = c:GetLocation()
                local cr = c:GetBoundingRadius()
                local locked = dist(at.x, at.y, here.x, here.y) <= c:GetAttackRange() + cr + br
                out[#out + 1] = {
                    unit = c,
                    fact = {
                        kind = "lane",
                        x = at.x,
                        y = at.y,
                        reach = c:GetAcquisitionRange() + cr,
                        locked = locked
                    }
                }
                __continue20 = true
            until true
            if not __continue20 then
                break
            end
        end
    end
    return out
end
local function ownCreeps(bot)
    local out = {}
    local team = bot:GetTeam()
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(____exports.SETTINGS.ScanR, false) or ({})) do
        if usable(c) and c:GetTeam() == team and LaneState.IsLaneCreepName(c:GetUnitName()) then
            out[#out + 1] = c
        end
    end
    return out
end
open = {}
function ____exports.Reset()
    for k in pairs(open) do
        __TS__Delete(open, k)
    end
end
local function kindsOf(attackers)
    local t = 0
    local l = 0
    for ____, a in ipairs(attackers) do
        if a.fact.kind == "tower" then
            t = t + 1
        else
            l = l + 1
        end
    end
    return t > 0 and l > 0 and "mixed" or (t > 0 and "tower" or "lane")
end
--- Read, plan and give the order (`Action_AttackUnit` with bOnce, as lane_tech's tower drop; it replaces the hero's current
-- order this frame). One attempt per hero at a
-- time: while one is open Shed refuses (`open`); Watch closes it. A `locked` or `no_unit` answer tells the caller an order
-- would do nothing now (a locked creep needs us out of its attack range first, which is the caller's move).
function ____exports.Shed(bot)
    local pid = bot:GetPlayerID()
    if open[pid] ~= nil and ____exports.Watch(bot) == "pending" then
        return {ordered = false, why = "open"}
    end
    local attackers = ____exports.Read(bot)
    local ours = ownCreeps(bot)
    local here = bot:GetLocation()
    local ownFacts = {}
    for ____, c in ipairs(ours) do
        local at = c:GetLocation()
        ownFacts[#ownFacts + 1] = {
            x = at.x,
            y = at.y,
            d = dist(at.x, at.y, here.x, here.y)
        }
    end
    local attackerFacts = {}
    for ____, a in ipairs(attackers) do
        attackerFacts[#attackerFacts + 1] = a.fact
    end
    local p = ____exports.Plan(attackerFacts, ownFacts)
    if p.target == nil then
        return {ordered = false, why = p.why or "none"}
    end
    local target = ours[p.target + 1]
    bot:Action_AttackUnit(target, true)
    local now = DotaTime()
    open[pid] = {
        orderedAt = now,
        watchedAt = now,
        target = target,
        attackers = attackers,
        kinds = kindsOf(attackers),
        covers = p.covers,
        locked = p.locked,
        hp = bot:GetHealth() / math.max(
            1,
            bot:GetMaxHealth()
        )
    }
    return {ordered = true, covers = p.covers, locked = p.locked}
end
return ____exports
