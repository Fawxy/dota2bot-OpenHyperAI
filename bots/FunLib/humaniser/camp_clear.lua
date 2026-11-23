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

local function __TS__ArrayEvery(self, callbackfn, thisArg)
    for i = 1, #self do
        if not callbackfn(thisArg, self[i], i - 1, self) then
            return false
        end
    end
    return true
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
____exports.SETTINGS = {
    CampRadius = 700,
    ClearHP = {small = 0.12, medium = 0.2, large = 0.35, ancient = 0.6},
    HPRefLevel = 6,
    HPLevelStep = 0.8,
    HPLevelScale = {0.6, 3.2},
    StackedClearMul = 0.8,
    ArriveHP = 0.4,
    SwitchSec = 0.6,
    DefaultSPA = 1.7
}
--- Each camp's neutrals as last seen untouched, by team then camp.
local lastSeen = {}
function ____exports.ResetCache()
    for k in pairs(lastSeen) do
        __TS__Delete(lastSeen, k)
    end
end
local function clamp(v, r)
    return math.max(
        r[1],
        math.min(r[2], v)
    )
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
local function spaOf(u)
    local ____this_1
    ____this_1 = u
    local ____opt_0 = ____this_1.GetSecondsPerAttack
    local spa = ____opt_0 and ____opt_0(____this_1)
    return spa ~= nil and spa > 0 and spa or ____exports.SETTINGS.DefaultSPA
end
local function priorClearHP(____type, level, stacks)
    local s = ____exports.SETTINGS
    local scale = clamp(s.HPLevelStep ^ (level - s.HPRefLevel), s.HPLevelScale)
    return (s.ClearHP[____type] or s.ClearHP.medium) * scale * (1 + s.StackedClearMul * stacks)
end
--- The fraction of its max HP `bot` loses clearing `camp`. The neutrals die one at a time in the order that loses the least HP
-- (most damage a second per second of kill time first); each hits until it dies; SwitchSec between kills; the core's regen
-- offsets the loss. Spells and cleave are not in it.
local function clearHP(bot, camp)
    local hit = bot:GetAttackDamage() / spaOf(bot)
    local foes = {}
    for ____, n in ipairs(camp) do
        foes[#foes + 1] = {
            kill = n.hp / math.max(hit * n.take, 1) + ____exports.SETTINGS.SwitchSec,
            dps = bot:GetActualIncomingDamage(n.dmg, DamageType.Physical) / math.max(n.spa, 0.1)
        }
    end
    __TS__ArraySort(
        foes,
        function(____, a, b) return b.dps / b.kill - a.dps / a.kill end
    )
    local t = 0
    local taken = 0
    for ____, f in ipairs(foes) do
        t = t + f.kill
        taken = taken + f.dps * t
    end
    return math.max(
        0,
        taken - bot:GetHealthRegen() * t
    ) / math.max(
        bot:GetMaxHealth(),
        1
    )
end
--- The camp's live neutrals (the API returns none in fog). Kept as its make-up only when untouched (every one at full HP),
-- and never replaced by fewer: a read of a half-cleared or half-seen camp would price it at what is left.
local function liveNeutrals(team, idx, center)
    local live = {}
    local untouched = true
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps) or ({})) do
        do
            local __continue15
            repeat
                if u == nil or u == nil or not u:IsAlive() then
                    __continue15 = true
                    break
                end
                local at = u:GetLocation()
                if at == nil or at == nil or dist(at, center) > ____exports.SETTINGS.CampRadius then
                    __continue15 = true
                    break
                end
                local full = u:GetHealth() >= u:GetMaxHealth()
                live[#live + 1] = {
                    hp = u:GetHealth(),
                    take = u:GetActualIncomingDamage(100, DamageType.Physical) / 100,
                    dmg = u:GetAttackDamage(),
                    spa = spaOf(u),
                    full = full
                }
                if not full then
                    untouched = false
                end
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
    local ____opt_2 = lastSeen[team]
    local old = ____opt_2 and ____opt_2[idx]
    if #live > 0 and untouched and (old == nil or #live >= #old) then
        lastSeen[team] = lastSeen[team] or ({})
        lastSeen[team][idx] = live
    end
    return live
end
--- The clear's HP fraction: from the live neutrals, else the last untouched sighting scaled by `stacks`, else the type's table.
local function clearPrice(bot, spawner, stacks)
    local live = liveNeutrals(
        bot:GetTeam(),
        spawner.idx,
        Camps.BoxCenter(spawner)
    )
    local ____opt_4 = lastSeen[bot:GetTeam()]
    local seen = ____opt_4 and ____opt_4[spawner.idx]
    local partial = seen ~= nil and #live < #seen and __TS__ArrayEvery(
        live,
        function(____, n) return n.full end
    )
    if #live > 0 and not partial then
        return clearHP(bot, live)
    end
    if seen ~= nil then
        return clearHP(bot, seen) * (1 + ____exports.SETTINGS.StackedClearMul * stacks)
    end
    return priorClearHP(
        spawner.type,
        bot:GetLevel(),
        stacks
    )
end
--- Whether `core` could clear camp `idx` holding `stacks` stacks and keep ArriveHP of its max HP from full.
function ____exports.CanClear(core, idx, stacks)
    local spawner = Camps.SpawnerByIdx(idx)
    if spawner == nil then
        return false
    end
    return 1 - clearPrice(core, spawner, stacks) >= ____exports.SETTINGS.ArriveHP
end
return ____exports
