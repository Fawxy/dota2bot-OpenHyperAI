--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local ____spell_damage_data = require(GetScriptDirectory().."/FunLib/humaniser/spell_damage_data")
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
local function attackPart(e, target, window)
    local ____this_1
    ____this_1 = e
    local ____opt_0 = ____this_1.GetSecondsPerAttack
    local spa = ____opt_0 and ____opt_0(____this_1)
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
--- `e`'s GetEstimatedDamageToTarget on `target` over `window` (all damage types, spells it can cast now); with BurstReady off, Valve's figure.
function ____exports.DamageOn(e, target, window)
    local est = e:GetEstimatedDamageToTarget(true, target, window, DamageType.All)
    if est <= 0 or not Ours.On("BurstReady") then
        return est
    end
    local spent = ____exports.SpentOn(e, target, window)
    if spent <= 0 then
        return est
    end
    return math.max(
        math.min(
            est,
            attackPart(e, target, window)
        ),
        est - spent
    )
end
return ____exports
