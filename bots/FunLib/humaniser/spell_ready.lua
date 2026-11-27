--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local readyOf
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotScriptEnums = ____dota.BotScriptEnums
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local ____spell_damage_data = require(GetScriptDirectory().."/FunLib/humaniser/spell_damage_data")
local SPELL_ADDED = ____spell_damage_data.SPELL_ADDED
local SPELL_DAMAGE = ____spell_damage_data.SPELL_DAMAGE
local SPELL_SHAPE = ____spell_damage_data.SPELL_SHAPE
function readyOf(a, added)
    if a:GetLevel() <= 0 or a:IsHidden() or not a:IsFullyCastable() then
        return nil
    end
    local name = a:GetName()
    local row = SPELL_DAMAGE[name] or (added and SPELL_ADDED[name] or nil)
    local dmg = row ~= nil and a:GetSpecialValueFloat(row[1]) or a:GetAbilityDamage()
    if type(dmg) ~= "number" or not (dmg > 0) then
        return nil
    end
    local range = a:GetCastRange()
    if not (range > 0) then
        local r = a:GetSpecialValueFloat("radius")
        range = type(r) == "number" and r > 0 and r or 0
    end
    local dt = row ~= nil and row[3] or (a.GetDamageType ~= nil and a:GetDamageType() or DamageType.Magical)
    return {
        name = name,
        range = range,
        cp = a:GetCastPoint(),
        behavior = a:GetBehavior(),
        dmg = dmg,
        dtype = dt > 0 and dt or DamageType.Magical
    }
end
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
                    local r = readyOf(a, false)
                    if r ~= nil then
                        out[#out + 1] = r
                    end
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
--- Special-value keys an ability's numbers are found under, tried in order; GetSpecialValueFloat reads 0 for a key the ability lacks.
-- Key names, not heroes: the commonest in OHA's hero files (bots/BotLib) for a radius, a line's width and a projectile's speed.
-- `judgement`: a spell whose number sits under another key reads 0 (a radius of 0 hits only its target; a speed of 0 lands at once).
local RADIUS_KEYS = {
    "radius",
    "aoe",
    "area_of_effect",
    "impact_radius",
    "damage_radius",
    "bolt_aoe",
    "jump_radius"
}
local WIDTH_KEYS = {
    "width",
    "wave_width",
    "arrow_width",
    "burrow_width",
    "end_width"
}
local SPEED_KEYS = {
    "speed",
    "projectile_speed",
    "bolt_speed",
    "blast_speed",
    "arrow_speed",
    "burrow_speed",
    "travel_speed",
    "missile_speed"
}
--- Valve's ability behaviour and target-type flags; the numbers after `??` are their values, for a test run with no game globals.
local B_NO_TARGET = ABILITY_BEHAVIOR_NO_TARGET or 4
local B_UNIT = ABILITY_BEHAVIOR_UNIT_TARGET or 8
local B_POINT = ABILITY_BEHAVIOR_POINT or 16
local B_CHANNELLED = ABILITY_BEHAVIOR_CHANNELLED or 128
local B_TOGGLE = ABILITY_BEHAVIOR_TOGGLE or 512
local T_CREEP = ABILITY_TARGET_TYPE_CREEP or 2
local T_ENEMY = ABILITY_TARGET_TEAM_ENEMY or 2
--- Whether the power-of-two `flag` is set in `bits` (the build targets Lua 5.1, which has no bitwise operators).
local function has(bits, flag)
    return flag > 0 and math.floor(bits / flag) % 2 == 1
end
--- The special value at `key`, 0 when it reads as no positive number.
local function valueAt(a, key)
    local v = a:GetSpecialValueFloat(key)
    return type(v) == "number" and v > 0 and v or 0
end
local function firstKey(a, keys)
    for ____, k in ipairs(keys) do
        local v = a:GetSpecialValueFloat(k)
        if type(v) == "number" and v > 0 then
            return v
        end
    end
    return 0
end
local creepAt = -1
local creepBy = {}
--- The spells `bot` can cast now that could take a lane creep in one cast (slice oha-creep-spell-shadow): ReadySpells' list with
-- the SPELL_ADDED spells too, less ultimates, channelled, toggled and per-second spells, a unit-target spell that cannot target creeps, and a no-target one with no
-- radius; with each one's mana, cooldown, class, radius, line width and speed. Read once a frame per hero.
function ____exports.CreepSpellsOf(bot)
    local now = DotaTime()
    if now ~= creepAt then
        creepAt = now
        creepBy = {}
    end
    local pid = bot:GetPlayerID()
    local cached = creepBy[pid]
    if cached ~= nil then
        return cached
    end
    local keys = {}
    local learned = {}
    do
        local slot = 0
        while slot < SLOTS do
            do
                local __continue48
                repeat
                    local a = bot:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() or a:GetLevel() <= 0 or a:IsHidden() or a:IsPassive() or a:IsUltimate() then
                        __continue48 = true
                        break
                    end
                    if AbilityClasses.Classify(
                        a:GetName(),
                        false
                    ) == "key" then
                        keys[a:GetName()] = a:GetManaCost()
                    end
                    learned[#learned + 1] = a
                    __continue48 = true
                until true
                if not __continue48 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    local spells = {}
    for ____, a in ipairs(learned) do
        do
            local __continue51
            repeat
                local r = readyOf(a, true)
                if r == nil then
                    __continue51 = true
                    break
                end
                local row = SPELL_DAMAGE[r.name] or SPELL_ADDED[r.name]
                if row ~= nil and row[2] then
                    __continue51 = true
                    break
                end
                if has(r.behavior, B_CHANNELLED) or has(r.behavior, B_TOGGLE) then
                    __continue51 = true
                    break
                end
                local geo = SPELL_SHAPE[r.name]
                local geoRadius = (geo and geo.radius) ~= nil and valueAt(a, geo.radius) or 0
                local shape
                if has(r.behavior, B_UNIT) then
                    local ____opt_6 = a.GetTargetType
                    local tt = ____opt_6 and ____opt_6(a)
                    if tt ~= nil and tt > 0 and not has(tt, T_CREEP) then
                        __continue51 = true
                        break
                    end
                    local ____opt_8 = a.GetTargetTeam
                    local team = ____opt_8 and ____opt_8(a)
                    if team ~= nil and team > 0 and not has(team, T_ENEMY) then
                        __continue51 = true
                        break
                    end
                    shape = "u"
                elseif has(r.behavior, B_POINT) then
                    shape = "p"
                elseif has(r.behavior, B_NO_TARGET) and (r.range > 0 or geoRadius > 0) then
                    shape = "n"
                else
                    __continue51 = true
                    break
                end
                if shape ~= "u" and geo ~= nil then
                    local half = geo.width ~= nil and valueAt(a, geo.width) / 2 or (geo.half ~= nil and valueAt(a, geo.half) or 0)
                    local radius = geo.k == "l" and 0 or (geoRadius > 0 and geoRadius or (shape == "n" and r.range or 0))
                    spells[#spells + 1] = {
                        name = r.name,
                        shape = shape,
                        range = shape == "n" and geo.k == "s" and radius or r.range,
                        cp = r.cp,
                        dmg = r.dmg,
                        dtype = r.dtype,
                        mana = a:GetManaCost(),
                        cd = a:GetCooldown(),
                        key = keys[r.name] ~= nil,
                        radius = radius,
                        half = geo.k == "l" and half or 0,
                        speed = geo.speed ~= nil and valueAt(a, geo.speed) or 0,
                        geom = geo.k,
                        length = geo.k == "l" and math.max(
                            r.range,
                            geo.length ~= nil and valueAt(a, geo.length) or 0
                        ) or 0,
                        delay = geo.delay ~= nil and valueAt(a, geo.delay) or 0,
                        offset = geo.k == "r" and geo.offset ~= nil and valueAt(a, geo.offset) or 0
                    }
                    __continue51 = true
                    break
                end
                local width = firstKey(a, WIDTH_KEYS)
                local half = width > 0 and width / 2 or (firstKey(a, {"start_radius"}) > 0 and firstKey(a, {"end_radius"}) or 0)
                spells[#spells + 1] = {
                    name = r.name,
                    shape = shape,
                    range = r.range,
                    cp = r.cp,
                    dmg = r.dmg,
                    dtype = r.dtype,
                    mana = a:GetManaCost(),
                    cd = a:GetCooldown(),
                    key = keys[r.name] ~= nil,
                    radius = shape == "n" and r.range or firstKey(a, RADIUS_KEYS),
                    half = shape == "n" and 0 or half,
                    speed = shape == "n" and 0 or firstKey(a, SPEED_KEYS),
                    length = 0,
                    delay = 0,
                    offset = 0
                }
                __continue51 = true
            until true
            if not __continue51 then
                break
            end
        end
    end
    local out = {spells = spells, keys = keys}
    creepBy[pid] = out
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
                local __continue78
                repeat
                    local a = bot:GetAbilityInSlot(slot)
                    if a == nil or a == nil or a:IsNull() then
                        __continue78 = true
                        break
                    end
                    if a:GetLevel() <= 0 or a:IsHidden() or a:IsPassive() or not a:IsFullyCastable() then
                        __continue78 = true
                        break
                    end
                    out[#out + 1] = (a:GetName() .. ":") .. classOf(a)
                    __continue78 = true
                until true
                if not __continue78 then
                    break
                end
            end
            slot = slot + 1
        end
    end
    return #out > 0 and table.concat(out, ";") or nil
end
return ____exports
