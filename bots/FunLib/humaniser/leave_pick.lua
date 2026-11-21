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
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Commit = require(GetScriptDirectory().."/FunLib/humaniser/commit")
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
    LogEvery = 2
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
--- Gold (unconverted) of the enemy lane creeps within our attack range + FarmPad that our units' attacks kill within the horizon.
local function farmGold(bot)
    local creeps = bot:GetNearbyLaneCreeps(
        math.min(
            1600,
            bot:GetAttackRange() + ____exports.SETTINGS.FarmPad
        ),
        true
    ) or ({})
    if #creeps == 0 then
        return 0
    end
    local ours = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1600, false) or ({})) do
        if seen(c) then
            ours[#ours + 1] = c
        end
    end
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        if seen(a) and not a:IsIllusion() and GetUnitToUnitDistance(bot, a) <= 1600 then
            ours[#ours + 1] = a
        end
    end
    local gold = 0
    for ____, c in ipairs(creeps) do
        do
            local __continue29
            repeat
                if not seen(c) then
                    __continue29 = true
                    break
                end
                local dps = 0
                for ____, u in ipairs(ours) do
                    if u:GetAttackTarget() == c then
                        dps = dps + u:GetAttackDamage() / spa(u)
                    end
                end
                if c:GetHealth() <= P.HORIZON * dps then
                    gold = gold + (P.LASTHIT_BY_KIND[creepKind(c:GetUnitName())] or P.LASTHIT)
                end
                __continue29 = true
            until true
            if not __continue29 then
                break
            end
        end
    end
    return gold
end
local function walk(bot)
    local best = math.huge
    for ____, id in ipairs(TOWER_IDS) do
        local tw = GetTower(
            bot:GetTeam(),
            id
        )
        if tw ~= nil and tw ~= nil and not tw:IsNull() and tw:IsAlive() then
            best = math.min(
                best,
                GetUnitToUnitDistance(bot, tw)
            )
        end
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
            local __continue42
            repeat
                if not seen(e) or e:IsIllusion() then
                    __continue42 = true
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
                __continue42 = true
            until true
            if not __continue42 then
                break
            end
        end
    end
    for ____, epid in ipairs(Commit.HitterIds(pid, ____exports.SETTINGS.HitWindow)) do
        do
            local __continue47
            repeat
                if by[epid] == true then
                    __continue47 = true
                    break
                end
                by[epid] = true
                hs = hs + 1
                __continue47 = true
            until true
            if not __continue47 then
                break
            end
        end
    end
    local n = 1
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue50
            repeat
                if not seen(a) or a == bot or a:IsIllusion() then
                    __continue50 = true
                    break
                end
                if GetUnitToUnitDistance(a, s.t) <= P.REACH then
                    n = n + 1
                end
                __continue50 = true
            until true
            if not __continue50 then
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
        local b = Commit.BurstNow(bot).by
        local sum = 0
        for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
            local x = seen(e) and not e:IsIllusion() and GetUnitToUnitDistance(bot, e) <= P.REACH and b[e:GetPlayerID()] or nil
            if x ~= nil then
                sum = sum + (x.spell + x.attack)
            end
        end
        g.burst = sum >= bot:GetHealth()
        if not g.burst then
            g.cg = farmGold(bot)
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
    local ____Telemetry_Event_15 = Telemetry.Event
    local ____array_14 = __TS__SparseArrayNew(
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
        ____array_14,
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
    ____Telemetry_Event_15(
        "choice",
        {__TS__SparseArraySpread(____array_14)}
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
    local ____inBand_result_16
    if inBand(lw) then
        ____inBand_result_16 = ____exports.Gather(bot, lw)
    else
        ____inBand_result_16 = nil
    end
    local g = ____inBand_result_16
    if g == nil then
        states[pid] = {lw = lw, res = nil}
        return nil
    end
    if st == nil or st.inc == nil then
        st = __TS__ObjectAssign({}, st or ({}), {inc = lw.why ~= nil and "leave" or "stay"})
    end
    st.lw = lw
    local key = (((((((g.sc .. "|") .. tostring(g.tpid)) .. "|") .. tostring(math.min(g.n, 2))) .. "|") .. tostring(g.ne)) .. "|") .. tostring(math.min(g.hs, 2))
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
