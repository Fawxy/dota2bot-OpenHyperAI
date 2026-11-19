--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
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

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end
-- End of Lua Library inline imports
local ____exports = {}
local spentOf, addedOf, attackPart, damageOn, SLOTS, spentAt, spentBy, addedAt, addedBy, addedLogged, addedLogger
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local ____spell_damage_data = require(GetScriptDirectory().."/FunLib/humaniser/spell_damage_data")
local SPELL_ADDED = ____spell_damage_data.SPELL_ADDED
local SPELL_DAMAGE = ____spell_damage_data.SPELL_DAMAGE
function spentOf(e)
    local now = DotaTime()
    if now ~= spentAt then
        spentAt = now
        spentBy = {}
    end
    local pid = e:GetPlayerID()
    local cached = spentBy[pid]
    if cached ~= nil then
        return cached
    end
    local list = {}
    spentBy[pid] = list
    if e.GetAbilityInSlot == nil then
        return list
    end
    do
        local slot = 0
        while slot < SLOTS do
            do
                local __continue6
                repeat
                    local a = e:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() then
                        __continue6 = true
                        break
                    end
                    local row = SPELL_DAMAGE[a:GetName()]
                    if row == nil or a:GetLevel() <= 0 or a:IsHidden() or a:IsFullyCastable() then
                        __continue6 = true
                        break
                    end
                    local value = a:GetSpecialValueFloat(row[1])
                    if type(value) == "number" and value > 0 then
                        list[#list + 1] = {key = row[1], perSecond = row[2], type = row[3], value = value}
                    end
                    __continue6 = true
                until true
                if not __continue6 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return list
end
function addedOf(e)
    local now = DotaTime()
    if now ~= addedAt then
        addedAt = now
        addedBy = {}
    end
    local pid = e:GetPlayerID()
    local cached = addedBy[pid]
    if cached ~= nil then
        return cached
    end
    local list = {}
    addedBy[pid] = list
    if e.GetAbilityInSlot == nil then
        return list
    end
    do
        local slot = 0
        while slot < SLOTS do
            do
                local __continue15
                repeat
                    local a = e:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() then
                        __continue15 = true
                        break
                    end
                    local name = a:GetName()
                    local row = SPELL_ADDED[name]
                    if row == nil or a:GetLevel() <= 0 or a:IsHidden() or not a:IsFullyCastable() then
                        __continue15 = true
                        break
                    end
                    local value = a:GetSpecialValueFloat(row[1])
                    if type(value) ~= "number" or not (value > 0) then
                        __continue15 = true
                        break
                    end
                    list[#list + 1] = {perSecond = row[2], type = row[3], value = value}
                    local logKey = (((tostring(pid) .. ":") .. name) .. ":") .. tostring(a:GetLevel())
                    if addedLogged[logKey] ~= true then
                        addedLogged[logKey] = true
                        if addedLogger ~= nil then
                            addedLogger(
                                pid,
                                name,
                                row[4],
                                row[1],
                                value,
                                a:GetLevel(),
                                e:GetTeam() == GetTeam() and 1 or 0
                            )
                        end
                    end
                    __continue15 = true
                until true
                if not __continue15 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return list
end
--- The damage of `e`'s castable spells that Valve's estimate leaves out (SPELL_ADDED), on `target` over `window`; our own heroes included.
function ____exports.AddedOn(e, target, window)
    if e:IsIllusion() then
        return 0
    end
    local total = 0
    for ____, s in ipairs(addedOf(e)) do
        total = total + target:GetActualIncomingDamage(s.perSecond and s.value * window or s.value, s.type)
    end
    return total
end
function attackPart(e, target, window)
    local ____this_3
    ____this_3 = e
    local ____opt_2 = ____this_3.GetSecondsPerAttack
    local spa = ____opt_2 and ____opt_2(____this_3)
    if spa == nil or spa <= 0 then
        return 0
    end
    return target:GetActualIncomingDamage(
        e:GetAttackDamage() * window / spa,
        DamageType.Physical
    )
end
--- The damage of `e`'s learned spells it cannot cast now, on `target` over `window`: 0 for a hero of our team (its estimate already counts them).
function ____exports.SpentOn(e, target, window)
    if e:IsIllusion() then
        return 0
    end
    local spent = spentOf(e)
    if #spent == 0 or e:GetTeam() == GetTeam() then
        return 0
    end
    local total = 0
    for ____, s in ipairs(spent) do
        total = total + target:GetActualIncomingDamage(s.perSecond and s.value * window or s.value, s.type)
    end
    return total
end
function damageOn(e, target, window)
    local est = e:GetEstimatedDamageToTarget(true, target, window, DamageType.All)
    if not Ours.On("BurstReady") then
        return est
    end
    local added = ____exports.AddedOn(e, target, window)
    if est <= 0 then
        return added > 0 and added or est
    end
    local spent = ____exports.SpentOn(e, target, window)
    if spent <= 0 then
        return est + added
    end
    return math.max(
        math.min(
            est,
            attackPart(e, target, window)
        ),
        est - spent
    ) + added
end
SLOTS = 6
spentAt = -1
spentBy = {}
addedAt = -1
addedBy = {}
addedLogged = {}
--- Telemetry sets this at load: it imports this module, so this module cannot import it.
function ____exports.SetAddedLogger(fn)
    addedLogger = fn
end
--- The damage spells `bot` can cast now (learned, shown, IsFullyCastable) with what the chase's catch read needs (kill-chances
-- step 3b): cast range, cast point and damage. A spell with no damage over 0 is left out.
function ____exports.ReadySpells(bot)
    local out = {}
    do
        local slot = 0
        while slot < SLOTS do
            do
                local __continue32
                repeat
                    local a = bot:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() then
                        __continue32 = true
                        break
                    end
                    if a:GetLevel() <= 0 or a:IsHidden() or not a:IsFullyCastable() then
                        __continue32 = true
                        break
                    end
                    local name = a:GetName()
                    local row = SPELL_DAMAGE[name]
                    local dmg = row ~= nil and a:GetSpecialValueFloat(row[1]) or a:GetAbilityDamage()
                    if type(dmg) ~= "number" or not (dmg > 0) then
                        __continue32 = true
                        break
                    end
                    local range = a:GetCastRange()
                    if not (range > 0) then
                        local r = a:GetSpecialValueFloat("radius")
                        range = type(r) == "number" and r > 0 and r or 0
                    end
                    local dt = row ~= nil and row[3] or (a.GetDamageType ~= nil and a:GetDamageType() or DamageType.Magical)
                    out[#out + 1] = {
                        name = name,
                        range = range,
                        cp = a:GetCastPoint(),
                        behavior = a:GetBehavior(),
                        dmg = dmg,
                        dtype = dt > 0 and dt or DamageType.Magical
                    }
                    __continue32 = true
                until true
                if not __continue32 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return out
end
--- Slice chase-log: the damage spells `bot` can cast now (ReadySpells), as `;`-joined records of name,cast range,cast point
-- (s, two places),behaviour bits (GetBehavior),damage. Logged; the catch read reads the same list.
function ____exports.ReadyDamage(bot)
    local out = {}
    for ____, s in ipairs(____exports.ReadySpells(bot)) do
        local cp = math.floor(s.cp * 100 + 0.5) / 100
        out[#out + 1] = table.concat(
            {
                s.name,
                math.floor(s.range),
                cp,
                s.behavior,
                math.floor(s.dmg + 0.5)
            },
            ","
        )
    end
    return #out > 0 and table.concat(out, ";") or nil
end
local damageAt = -1
local damageBy = __TS__New(Map)
--- Per game (and per fixture: fixtures can share a DotaTime): the frame caches.
function ____exports.ResetCache()
    damageAt = -1
    damageBy = __TS__New(Map)
    spentAt = -1
    spentBy = {}
    addedAt = -1
    addedBy = {}
end
--- `e`'s GetEstimatedDamageToTarget on `target` over `window` (all damage types, spells it can cast now, plus the castable spells it leaves out: AddedOn); with BurstReady off, Valve's figure.
function ____exports.DamageOn(e, target, window)
    local now = DotaTime()
    if now ~= damageAt then
        damageAt = now
        damageBy = __TS__New(Map)
    end
    local byTarget = damageBy:get(e)
    if byTarget == nil then
        byTarget = __TS__New(Map)
        damageBy:set(e, byTarget)
    end
    local byWindow = byTarget:get(target)
    if byWindow == nil then
        byWindow = {}
        byTarget:set(target, byWindow)
    end
    local cached = byWindow[window]
    if cached ~= nil then
        return cached
    end
    local v = damageOn(e, target, window)
    byWindow[window] = v
    return v
end
--- Slice cast-read: an ability's class for the cast read: `u` ultimate, `k` key (a hard disable or spell immunity,
-- AbilityClasses), `d` damage (a SPELL_DAMAGE row or GetAbilityDamage over 0), else `o`. Logged only.
local function classOf(a)
    if a:IsUltimate() then
        return "u"
    end
    if AbilityClasses.Classify(
        a:GetName(),
        false
    ) == "key" then
        return "k"
    end
    if SPELL_DAMAGE[a:GetName()] ~= nil then
        return "d"
    end
    local dmg = a:GetAbilityDamage()
    return type(dmg) == "number" and dmg > 0 and "d" or "o"
end
--- Slice cast-read: the class (as `rdy`) of `bot`'s ability `name`; undefined for an item or a name the hero lacks.
function ____exports.ClassByName(bot, name)
    if name == nil or string.sub(name, 1, 5) == "item_" then
        return nil
    end
    local a = bot:GetAbilityByName(name)
    if a == nil or a == nil or a:IsNull() then
        return nil
    end
    return classOf(a)
end
--- Slice cast-read: the spells `bot` can cast now (learned, shown, not passive, IsFullyCastable) as `;`-joined
-- `name:class`. Abilities only: lane items are left out. Logged only (ev=snap `rdy`).
function ____exports.ReadyList(bot)
    local out = {}
    do
        local slot = 0
        while slot < SLOTS do
            do
                local __continue58
                repeat
                    local a = bot:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() then
                        __continue58 = true
                        break
                    end
                    if a:GetLevel() <= 0 or a:IsHidden() or a:IsPassive() or not a:IsFullyCastable() then
                        __continue58 = true
                        break
                    end
                    out[#out + 1] = (a:GetName() .. ":") .. classOf(a)
                    __continue58 = true
                until true
                if not __continue58 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return #out > 0 and table.concat(out, ";") or nil
end
return ____exports
