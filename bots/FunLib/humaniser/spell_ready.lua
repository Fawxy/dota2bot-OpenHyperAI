--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local ____spell_damage_data = require(GetScriptDirectory().."/FunLib/humaniser/spell_damage_data")
local SPELL_ADDED = ____spell_damage_data.SPELL_ADDED
local SPELL_DAMAGE = ____spell_damage_data.SPELL_DAMAGE
local SLOTS = 6
local spentAt = -1
local spentBy = {}
local function spentOf(e)
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
local addedAt = -1
local addedBy = {}
local addedLogged = {}
local addedLogger
--- Telemetry sets this at load: it imports this module, so this module cannot import it.
function ____exports.SetAddedLogger(fn)
    addedLogger = fn
end
local function addedOf(e)
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
local function attackPart(e, target, window)
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
                    local mana = a.GetManaCost ~= nil and a:GetManaCost() or nil
                    local cd = a.GetCooldownTimeRemaining ~= nil and a:GetCooldownTimeRemaining() or nil
                    out[#out + 1] = {
                        name = name,
                        range = range,
                        cp = a:GetCastPoint(),
                        behavior = a:GetBehavior(),
                        dmg = dmg,
                        dtype = dt > 0 and dt or DamageType.Magical,
                        mana = mana,
                        cd = cd
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
--- `e`'s GetEstimatedDamageToTarget on `target` over `window` (all damage types, spells it can cast now, plus the castable spells it leaves out: AddedOn); with BurstReady off, Valve's figure.
function ____exports.DamageOn(e, target, window)
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
                local __continue52
                repeat
                    local a = bot:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() then
                        __continue52 = true
                        break
                    end
                    if a:GetLevel() <= 0 or a:IsHidden() or a:IsPassive() or not a:IsFullyCastable() then
                        __continue52 = true
                        break
                    end
                    out[#out + 1] = (a:GetName() .. ":") .. classOf(a)
                    __continue52 = true
                until true
                if not __continue52 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return #out > 0 and table.concat(out, ";") or nil
end
return ____exports
