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

local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
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

local function __TS__CountVarargs(...)
    return select("#", ...)
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

local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Commit = require(GetScriptDirectory().."/FunLib/humaniser/commit")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local LeavePrice = require(GetScriptDirectory().."/FunLib/humaniser/leave_price")
local P = require(GetScriptDirectory().."/FunLib/humaniser/dc_prices")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Trade = require(GetScriptDirectory().."/FunLib/humaniser/states/trade")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
____exports.SETTINGS = {
    JoinReach = 1200,
    HitReach = 1600,
    HitWindow = 1,
    FarmPad = 300,
    LogEvery = 2,
    WaveReach = 1200,
    EngagePad = 150,
    BurstScan = 1600,
    LostGrace = 1
}
local TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
    Tower.Base1,
    Tower.Base2
}
local states = {}
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(states)) do
        __TS__Delete(states, k)
    end
end
--- The incumbent is forgotten (an episode started or ended outside the decider's sight, in shadow).
function ____exports.Forget(bot)
    states[bot:GetPlayerID()] = nil
end
--- The pick acts (`Ours.PricedLeaveAct`, which needs `Ours.PricedLeave`).
function ____exports.Acts()
    return Ours.On("PricedLeave") and Ours.On("PricedLeaveAct")
end
local function seen(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen() and u:GetLocation() ~= nil
end
--- The scope (s2), in order: our own exchange's target, our play's target, an ally's exchange target within JoinReach of us.
function ____exports.ScopeOf(bot)
    if Trade.Running(bot) then
        local ____opt_0 = Trade.EpisodeOf(bot:GetPlayerID())
        local t = ____opt_0 and ____opt_0.target
        if seen(t) then
            return {sc = "trade", t = t}
        end
    end
    local play = Plays.Of(bot)
    if play ~= nil and seen(play.target) then
        return {sc = "play", t = play.target}
    end
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue12
            repeat
                if not seen(a) or a == bot or a:IsIllusion() or GetUnitToUnitDistance(bot, a) > ____exports.SETTINGS.JoinReach or not Trade.Running(a) then
                    __continue12 = true
                    break
                end
                local ____opt_2 = Trade.EpisodeOf(a:GetPlayerID())
                local t = ____opt_2 and ____opt_2.target
                if seen(t) and GetUnitToUnitDistance(bot, t) <= ____exports.SETTINGS.JoinReach then
                    return {sc = "ally", t = t}
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    return nil
end
local function creepKind(name)
    if (string.find(name, "siege", 1, true)) ~= nil then
        return "siege"
    end
    if (string.find(name, "ranged", 1, true)) ~= nil then
        return "ranged"
    end
    if (string.find(name, "flag", 1, true)) ~= nil then
        return "flag"
    end
    return "melee"
end
local function spa(u)
    local ____math_max_6 = math.max
    local ____this_5
    ____this_5 = u
    local ____opt_4 = ____this_5.GetSecondsPerAttack
    return ____math_max_6(
        0.2,
        ____opt_4 and ____opt_4(____this_5) or 1.7
    )
end
--- Pure: which of a wave's creeps die within `h` seconds under `dps` (their effective HP, after armour), lowest first: the k lowest
-- whose summed HP the wave's damage over the horizon covers. A per-creep "its current attackers kill it" read missed nearly every
-- death (smoke dc-step2: cg 0 on 18 of 19 lines), as lane creeps switch targets and focus the low ones.
function ____exports.Due(ehp, dps, h)
    local order = {}
    do
        local i = 0
        while i < #ehp do
            order[#order + 1] = i
            i = i + 1
        end
    end
    __TS__ArraySort(
        order,
        function(____, a, b) return ehp[a + 1] - ehp[b + 1] end
    )
    local out = {}
    do
        local i = 0
        while i < #ehp do
            out[#out + 1] = false
            i = i + 1
        end
    end
    local left = dps * h
    for ____, i in ipairs(order) do
        if ehp[i + 1] > left then
            break
        end
        left = left - ehp[i + 1]
        out[i + 1] = true
    end
    return out
end
local function towersOf(team)
    local out = {}
    for ____, id in ipairs(TOWER_IDS) do
        local tw = GetTower(team, id)
        if tw ~= nil and tw ~= nil and not tw:IsNull() and tw:IsAlive() then
            out[#out + 1] = tw
        end
    end
    return out
end
--- The farm read the fit and the replay priced (step0-price-fit.md "Farm in reach"; replay.js): enemy lane creeps within our attack
-- range + FarmPad that die within the horizon, by anyone, at the last-hit price by kind; `Farm` takes the conversion. Due: the
-- enemy wave within WaveReach of us, under the damage of our lane creeps and towers engaging it (within their range + hulls +
-- EngagePad of one of its creeps) and our heroes attacking a creep, lowest HP first (`Due`).
function ____exports.FarmRead(bot)
    local reach = bot:GetAttackRange() + ____exports.SETTINGS.FarmPad
    local wave = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(____exports.SETTINGS.WaveReach, true) or ({})) do
        if seen(c) then
            wave[#wave + 1] = c
        end
    end
    local out = {gold = 0, cn = 0, cd = 0}
    if #wave == 0 then
        return out
    end
    local inReach = {}
    for ____, c in ipairs(wave) do
        local r = GetUnitToUnitDistance(bot, c) <= reach
        inReach[#inReach + 1] = r
        if r then
            out.cn = out.cn + 1
        end
    end
    if out.cn == 0 then
        return out
    end
    local dps = 0
    local function engages(u)
        local r = u:GetAttackRange() + u:GetBoundingRadius() + ____exports.SETTINGS.EngagePad
        for ____, c in ipairs(wave) do
            if GetUnitToUnitDistance(u, c) <= r + c:GetBoundingRadius() then
                return true
            end
        end
        return false
    end
    local attackers = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(____exports.SETTINGS.WaveReach, false) or ({})) do
        if seen(c) then
            attackers[#attackers + 1] = c
        end
    end
    for ____, tw in ipairs(towersOf(bot:GetTeam())) do
        if GetUnitToUnitDistance(bot, tw) <= ____exports.SETTINGS.WaveReach + 700 then
            attackers[#attackers + 1] = tw
        end
    end
    for ____, u in ipairs(attackers) do
        if engages(u) then
            dps = dps + u:GetAttackDamage() / spa(u)
        end
    end
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue54
            repeat
                if not seen(a) or a:IsIllusion() or GetUnitToUnitDistance(bot, a) > ____exports.SETTINGS.WaveReach then
                    __continue54 = true
                    break
                end
                local t = a:GetAttackTarget()
                if t ~= nil and t ~= nil and not t:IsNull() and not t:IsHero() and engages(a) then
                    dps = dps + a:GetAttackDamage() / spa(a)
                end
                __continue54 = true
            until true
            if not __continue54 then
                break
            end
        end
    end
    local ehp = {}
    for ____, c in ipairs(wave) do
        ehp[#ehp + 1] = c:GetHealth() / math.max(
            0.05,
            c:GetActualIncomingDamage(100, DamageType.Physical) / 100
        )
    end
    local due = ____exports.Due(ehp, dps, P.HORIZON)
    do
        local i = 0
        while i < #wave do
            do
                local __continue60
                repeat
                    if not inReach[i + 1] or not due[i + 1] then
                        __continue60 = true
                        break
                    end
                    out.cd = out.cd + 1
                    out.gold = out.gold + (P.LASTHIT_BY_KIND[creepKind(wave[i + 1]:GetUnitName())] or P.LASTHIT)
                    __continue60 = true
                until true
                if not __continue60 then
                    break
                end
            end
            i = i + 1
        end
    end
    return out
end
--- Burst now (a hard leave): the ready spells and one attack of the enemies in reach land on us before we react, and their sum
-- reaches our HP. A spell counts only when castable (learned, shown, off cooldown: IsFullyCastable, which follows an enemy's own
-- cooldown and mana; its mana cost read too) and we are within its cast range (or radius) plus both hulls plus what the enemy closes
-- in `Commit.SETTINGS.ReactWindow`; the attack likewise within its attack range. Enemies beyond BurstScan are not read. Smoke
-- dc-step2: every `why=priced` start was a burst leave over a hit back (Valve's estimate counts every spell at any distance).
function ____exports.BurstNow(bot)
    local win = Commit.SETTINGS.ReactWindow
    local sum = 0
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue63
            repeat
                if not seen(e) or e:IsIllusion() then
                    __continue63 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, e)
                if d > ____exports.SETTINGS.BurstScan then
                    __continue63 = true
                    break
                end
                local pad = bot:GetBoundingRadius() + e:GetBoundingRadius() + e:GetCurrentMovementSpeed() * win
                local mana = e:GetMana()
                for ____, s in ipairs(SpellReady.ReadySpells(e)) do
                    do
                        local __continue66
                        repeat
                            if s.mana ~= nil and s.mana > mana then
                                __continue66 = true
                                break
                            end
                            if s.cd ~= nil and s.cd > 0 then
                                __continue66 = true
                                break
                            end
                            if d > s.range + pad then
                                __continue66 = true
                                break
                            end
                            sum = sum + bot:GetActualIncomingDamage(s.dmg, s.dtype)
                            __continue66 = true
                        until true
                        if not __continue66 then
                            break
                        end
                    end
                end
                if d <= e:GetAttackRange() + pad then
                    sum = sum + bot:GetActualIncomingDamage(
                        e:GetAttackDamage(),
                        DamageType.Physical
                    )
                end
                __continue63 = true
            until true
            if not __continue63 then
                break
            end
        end
    end
    return {
        burst = sum >= bot:GetHealth(),
        sum = sum
    }
end
local function walk(bot)
    local best = math.huge
    for ____, tw in ipairs(towersOf(bot:GetTeam())) do
        best = math.min(
            best,
            GetUnitToUnitDistance(bot, tw)
        )
    end
    return best == math.huge and 10000 or best
end
--- The decider's inputs at the fit's reach (s3); undefined outside the scope.
function ____exports.Gather(bot, lw)
    local s = ____exports.ScopeOf(bot)
    if s == nil then
        return nil
    end
    local pid = bot:GetPlayerID()
    local by = {}
    local hs = 0
    local ne = 0
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue78
            repeat
                if not seen(e) or e:IsIllusion() then
                    __continue78 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, e)
                if d <= P.REACH then
                    ne = ne + 1
                end
                if d <= ____exports.SETTINGS.HitReach and e:GetAttackTarget() == bot and by[e:GetPlayerID()] ~= true then
                    by[e:GetPlayerID()] = true
                    hs = hs + 1
                end
                __continue78 = true
            until true
            if not __continue78 then
                break
            end
        end
    end
    for ____, epid in ipairs(Commit.HitterIds(pid, ____exports.SETTINGS.HitWindow)) do
        do
            local __continue83
            repeat
                if by[epid] == true then
                    __continue83 = true
                    break
                end
                by[epid] = true
                hs = hs + 1
                __continue83 = true
            until true
            if not __continue83 then
                break
            end
        end
    end
    local n = 1
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue86
            repeat
                if not seen(a) or a == bot or a:IsIllusion() then
                    __continue86 = true
                    break
                end
                if GetUnitToUnitDistance(a, s.t) <= P.REACH then
                    n = n + 1
                end
                __continue86 = true
            until true
            if not __continue86 then
                break
            end
        end
    end
    local hp = 100 * bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    )
    local g = {
        sc = s.sc,
        tpid = s.t:GetPlayerID(),
        nh = Commit.Nh(pid),
        ne = ne,
        hp = hp,
        hs = hs,
        thp = 100 * s.t:GetHealth() / math.max(
            1,
            s.t:GetMaxHealth()
        ),
        n = n,
        w = walk(bot),
        ms = bot:GetCurrentMovementSpeed(),
        pos = LaneConfig.PositionOf(bot) or 3,
        cg = 0,
        tower = lw.why == "tower",
        heal = lw.why == "heal",
        lethal = lw.why == "lethal"
    }
    if not g.tower and not g.heal and not g.lethal then
        local b = ____exports.BurstNow(bot)
        g.burst = b.burst
        g.bsum = b.sum
        if not g.burst then
            local f = ____exports.FarmRead(bot)
            g.cg = f.gold
            g.cn = f.cn
            g.cd = f.cd
        end
    end
    return g
end
local function r1(x)
    local ____temp_7
    if x == nil then
        ____temp_7 = nil
    else
        ____temp_7 = math.floor(x * 10 + 0.5) / 10
    end
    return ____temp_7
end
local function r3(x)
    local ____temp_8
    if x == nil then
        ____temp_8 = nil
    else
        ____temp_8 = math.floor(x * 1000 + 0.5) / 1000
    end
    return ____temp_8
end
--- The leave rule's answer in the priced band (a threat leave or its holds), or a hard leave.
local function inBand(lw)
    return lw.why == "threat" or lw.why == "tower" or lw.why == "heal" or lw.why == "lethal" or lw.stay == "join" or lw.stay == "hitback"
end
local function log(bot, st, r, act, now)
    local tag = r.hard or r.pick
    if st.loggedPick == tag and r.rel == 0 and st.loggedAt ~= nil and now - st.loggedAt < ____exports.SETTINGS.LogEvery then
        return
    end
    st.loggedPick = tag
    st.loggedAt = now
    local g = r.g
    local ____Telemetry_Event_16 = Telemetry.Event
    local ____array_15 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "leave"},
        {"pick", r.pick},
        {"act", act and 1 or 0},
        {"hard", r.hard},
        {"inc", r.inc},
        {"rel", r.rel},
        {"mg", r.M},
        {"sc", g.sc},
        {"tpid", g.tpid}
    )
    local ____opt_9 = st.lw
    local ____temp_13 = ____opt_9 and ____opt_9.why
    if ____temp_13 == nil then
        local ____opt_11 = st.lw
        ____temp_13 = ____opt_11 and ____opt_11.stay
    end
    __TS__SparseArrayPush(
        ____array_15,
        {"lw", ____temp_13},
        {
            "hp",
            r1(g.hp)
        },
        {"hs", g.hs},
        {"nh", g.nh},
        {"ne", g.ne},
        {
            "thp",
            r1(g.thp)
        },
        {"n", g.n},
        {
            "w",
            math.floor(g.w)
        },
        {
            "spd",
            math.floor(g.ms)
        },
        {"pos", g.pos},
        {
            "cg",
            r1(g.cg)
        },
        {"cin", g.cn},
        {"cdue", g.cd}
    )
    local ____temp_14
    if g.bsum == nil then
        ____temp_14 = nil
    else
        ____temp_14 = math.floor(g.bsum)
    end
    __TS__SparseArrayPush(
        ____array_15,
        {"bsum", ____temp_14},
        {
            "sv",
            r1(r.stay)
        },
        {
            "lv",
            r1(r.leave)
        },
        {
            "d",
            r1(r.d)
        },
        {
            "pks",
            r3(r.pks)
        },
        {
            "pkl",
            r3(r.pkl)
        },
        {
            "pds",
            r3(r.pds)
        },
        {
            "pdl",
            r3(r.pdl)
        },
        {
            "fm",
            r1(r.F)
        },
        {
            "wk",
            r1(r.W)
        }
    )
    ____Telemetry_Event_16(
        "choice",
        {__TS__SparseArraySpread(____array_15)}
    )
end
--- The priced pick for this hero given the leave rule's answer `lw`, decided once per answer (the retreat refreshes it with its read,
-- at most every `Retreat.SETTINGS.ReadEvery`): whichever caller asks first in the frame decides and the other reads it. Undefined
-- outside the scope or the band, which forgets the incumbent. The first incumbent is the leave rule's answer. Logs the line.
function ____exports.For(bot, lw)
    local pid = bot:GetPlayerID()
    local st = states[pid]
    if st ~= nil and st.lw == lw then
        return st.res
    end
    local now = DotaTime()
    local band = inBand(lw)
    local ____band_17
    if band then
        ____band_17 = ____exports.Gather(bot, lw)
    else
        ____band_17 = nil
    end
    local g = ____band_17
    if g == nil then
        if st ~= nil and st.inc ~= nil and st.tpid ~= nil and IsHeroAlive(st.tpid) then
            st.lostAt = st.lostAt or now
            if now - st.lostAt <= ____exports.SETTINGS.LostGrace then
                st.lw = lw
                local ____band_18
                if band then
                    ____band_18 = st.res
                else
                    ____band_18 = nil
                end
                return ____band_18
            end
        end
        states[pid] = {lw = lw, res = nil}
        return nil
    end
    if st == nil or st.inc == nil then
        st = {inc = lw.why ~= nil and "leave" or "stay"}
    end
    st.lw = lw
    st.lostAt = nil
    st.tpid = g.tpid
    local key = (((g.sc .. "|") .. tostring(g.tpid)) .. "|") .. tostring(math.min(g.n, 2))
    g.rel = st.key ~= nil and st.key ~= key
    st.key = key
    local r = __TS__ObjectAssign(
        {},
        LeavePrice.Decide(g, st.inc),
        {g = g}
    )
    st.inc = r.pick
    st.res = r
    states[pid] = st
    log(
        bot,
        st,
        r,
        ____exports.Acts(),
        DotaTime()
    )
    return r
end
return ____exports
