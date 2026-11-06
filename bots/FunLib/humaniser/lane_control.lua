--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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
-- End of Lua Library inline imports
local ____exports = {}
local memoryOf, memory
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Calendar = require(GetScriptDirectory().."/FunLib/humaniser/calendar")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
function memoryOf(team, lane)
    local key = (tostring(team) .. ":") .. tostring(lane)
    local m = memory[key]
    if m == nil then
        m = {enemies = {}, chks = {}, decisions = {}}
        memory[key] = m
    end
    return m
end
--- Stores a wave's decision for the levers' owners (decide's, and the tests'); the last few waves are kept.
function ____exports.Remember(team, lane, d)
    local m = memoryOf(team, lane)
    m.decisions[d.wave] = d
    m.last = d
    for k in pairs(m.decisions) do
        if tonumber(k) < d.wave - 120 then
            __TS__Delete(
                m.decisions,
                tonumber(k)
            )
        end
    end
end
--- Slice 2b's sub-switch: the decision drives the levers (off: shadow, 2a's behaviour).
function ____exports.Drives()
    return Ours.On("LaneControl") and Ours.On("LaneControlDrive")
end
--- The lane's live decision (this wave's, until the next read), while the controller drives.
function ____exports.Current(team, lane, now)
    if now == nil then
        now = DotaTime()
    end
    if not ____exports.Drives() then
        return nil
    end
    local ____opt_34 = memory[(tostring(team) .. ":") .. tostring(lane)]
    local d = ____opt_34 and ____opt_34.last
    return d ~= nil and now - d.at <= ____exports.SETTINGS.Live and d or nil
end
--- All `judgement` unless marked.
____exports.SETTINGS = {
    ReadAt = 2,
    From = 60,
    Until = 720,
    Horizon = 45,
    Band = 150,
    PullScale = 0.6,
    DivertShare = 0.4,
    Live = 31,
    BreakEvery = 1,
    PreDenySize = 300,
    FeedSize = 300,
    SetupSize = 300,
    InLane = 2000,
    DepartWithin = 60,
    YieldBase = 1600,
    YieldPerMin = 200,
    YieldFrom = 3,
    DepartAfter = 15,
    CoreLowHp = 0.4,
    CoreThreat = 2,
    CoreThreatR = 1200,
    EnemyLaneR = 2500,
    EnemyMemory = 90,
    EnemyAway = 3000,
    TowerRange = 844
}
--- Levers that cannot be taken together (a pull resets our wave, a shove spends it).
local function clash(a, b)
    return a.name == "pull" and b.name == "shove" or a.name == "shove" and b.name == "pull"
end
--- The fewest, then least dangerous, usable levers whose summed effect takes `need` (the clash past the target) into
-- [-band, band]; when none does, the set that comes nearest without passing -band (design s5.3, user 06/11/2026). Up to
-- three levers; an empty set when `need` is already inside the band.
function ____exports.Choose(need, band, levers)
    if math.abs(need) <= band then
        return {levers = {}, left = need, short = false}
    end
    local ok = __TS__ArrayFilter(
        levers,
        function(____, l)
            local ____temp_1 = l.why == nil
            if ____temp_1 then
                local ____temp_0
                if need > 0 then
                    ____temp_0 = l.effect < 0
                else
                    ____temp_0 = l.effect > 0
                end
                ____temp_1 = ____temp_0
            end
            return ____temp_1
        end
    )
    local best
    local bestKey
    local sets = {}
    local grow
    grow = function(from, set)
        do
            local i = from
            while i < #ok do
                local ____array_2 = __TS__SparseArrayNew(unpack(set))
                __TS__SparseArrayPush(____array_2, ok[i + 1])
                local next = {__TS__SparseArraySpread(____array_2)}
                sets[#sets + 1] = next
                if #next < 3 then
                    grow(i + 1, next)
                end
                i = i + 1
            end
        end
    end
    grow(0, {})
    for ____, set in ipairs(sets) do
        do
            local __continue9
            repeat
                local bad = false
                do
                    local i = 0
                    while i < #set and not bad do
                        do
                            local j = i + 1
                            while j < #set do
                                if clash(set[i + 1], set[j + 1]) then
                                    bad = true
                                end
                                j = j + 1
                            end
                        end
                        i = i + 1
                    end
                end
                if bad then
                    __continue9 = true
                    break
                end
                local left = need
                local danger = 0
                for ____, l in ipairs(set) do
                    left = left + l.effect
                    danger = danger + l.danger
                end
                local ____temp_3
                if need > 0 then
                    ____temp_3 = left < -band
                else
                    ____temp_3 = left > band
                end
                local over = ____temp_3
                if over then
                    __continue9 = true
                    break
                end
                local inside = math.abs(left) <= band
                local key = inside and ({0, #set, danger}) or ({
                    1,
                    math.abs(left),
                    danger
                })
                if bestKey == nil or key[1] < bestKey[1] or key[1] == bestKey[1] and (key[2] < bestKey[2] or key[2] == bestKey[2] and key[3] < bestKey[3]) then
                    bestKey = key
                    best = {levers = set, left = left, short = not inside}
                end
                __continue9 = true
            until true
            if not __continue9 then
                break
            end
        end
    end
    return best or ({levers = {}, left = need, short = true})
end
function ____exports.IntentOf(need, band, reset)
    if reset and need > -band then
        return "reset"
    end
    return need > band and "back" or (need < -band and "forward" or "hold")
end
memory = {}
function ____exports.ResetCache()
    for k in pairs(memory) do
        __TS__Delete(memory, k)
    end
end
local function dist(a, x, y)
    return math.sqrt((a.x - x) ^ 2 + (a.y - y) ^ 2)
end
--- The calling script's team's heroes assigned to `lane` (GetTeamMember, not GetTeamPlayers: practice mode).
local function lanersOf(lane, cx, cy)
    local out = {}
    do
        local i = 1
        while i <= 5 do
            do
                local __continue28
                repeat
                    local u = GetTeamMember(i)
                    if u == nil or u == nil or u:IsNull() or u:GetAssignedLane() ~= lane then
                        __continue28 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(u) or 0
                    out[#out + 1] = {
                        unit = u,
                        pid = u:GetPlayerID(),
                        pos = pos,
                        bot = u:IsBot(),
                        present = u:IsAlive() and dist(
                            u:GetLocation(),
                            cx,
                            cy
                        ) <= ____exports.SETTINGS.InLane
                    }
                    __continue28 = true
                until true
                if not __continue28 then
                    break
                end
            end
            i = i + 1
        end
    end
    return out
end
--- The need past which a support's pull takes a stack's minute (slice 3).
function ____exports.YieldPast(now)
    return ____exports.SETTINGS.YieldBase + ____exports.SETTINGS.YieldPerMin * math.max(0, now / 60 - ____exports.SETTINGS.YieldFrom)
end
--- The pull lever's calendar check (slice 3): `fit` the calendar's answer for the support's next pull window; `why` the
-- refusal (`away`: it does not fit before a rune trip; `stack`: nor before a stack the lane does not need more); `yld` the
-- stack minute the pull may take.
function ____exports.PullCalendar(fit, e, n45, now)
    if fit ~= "clash" or e == nil then
        return {fit = fit}
    end
    local tag = "clash:" .. e.kind
    if e.fixed or e.running then
        return {fit = tag, why = "away"}
    end
    return n45 > ____exports.YieldPast(now) and ({fit = tag, yld = e.key}) or ({fit = tag, why = "stack"})
end
--- R5: their laners are known: every enemy hero seen near the lane lately is dead or seen far from the clash.
local function enemiesAway(m, now, cx, cy)
    local visible = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue35
            repeat
                if e == nil or e == nil or e:IsIllusion() or not e:CanBeSeen() then
                    __continue35 = true
                    break
                end
                visible[e:GetPlayerID()] = e
                if dist(
                    e:GetLocation(),
                    cx,
                    cy
                ) <= ____exports.SETTINGS.EnemyLaneR then
                    m.enemies[e:GetPlayerID()] = now
                end
                __continue35 = true
            until true
            if not __continue35 then
                break
            end
        end
    end
    local any = false
    for k in pairs(m.enemies) do
        do
            local __continue39
            repeat
                local pid = tonumber(k)
                if now - m.enemies[pid] > ____exports.SETTINGS.EnemyMemory then
                    __TS__Delete(m.enemies, pid)
                    __continue39 = true
                    break
                end
                any = true
                if not IsHeroAlive(pid) then
                    __continue39 = true
                    break
                end
                local e = visible[pid]
                if e == nil or dist(
                    e:GetLocation(),
                    cx,
                    cy
                ) <= ____exports.SETTINGS.EnemyAway then
                    return false
                end
                __continue39 = true
            until true
            if not __continue39 then
                break
            end
        end
    end
    return any
end
local function coreThreat(core, supportIn)
    local u = core.unit
    if u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    ) < ____exports.SETTINGS.CoreLowHp then
        return true
    end
    if supportIn then
        return false
    end
    local near = u:GetNearbyHeroes(____exports.SETTINGS.CoreThreatR, true, 0) or ({})
    return #near >= ____exports.SETTINGS.CoreThreat
end
local function ownAt(samples, path, team, t)
    if samples == nil or path == nil then
        return nil
    end
    local c = LanePush.ClashAt(samples, t)
    if c == nil then
        return nil
    end
    local t1, dir = LanePush.OwnT1(path, team)
    return dir * (c - t1)
end
local function round(x)
    local ____temp_4
    if x == nil then
        ____temp_4 = nil
    else
        ____temp_4 = math.floor(x + 0.5)
    end
    return ____temp_4
end
local function decide(team, lane, now, m)
    local clock = RealTime ~= nil and RealTime or nil
    local started = clock and clock()
    local s = ____exports.SETTINGS
    local path = LanePush.PathOf(lane)
    local r = LanePush.Read(team, lane)
    if path == nil or r == nil then
        Telemetry.Event("lane_ctl", {{"team", team}, {"lane", lane}, {"kind", "wave"}, {"why", r == nil and "no_read" or "no_path"}})
        return
    end
    local cx, cy = unpack(LanePush.PointAt(path, r.clash))
    local laners = lanersOf(lane, cx, cy)
    local cores = __TS__ArrayFilter(
        laners,
        function(____, l) return l.pos >= 1 and l.pos <= 3 end
    )
    local sups = __TS__ArrayFilter(
        laners,
        function(____, l) return l.pos >= 4 end
    )
    local coreIn = __TS__ArrayFind(
        cores,
        function(____, l) return l.present end
    )
    local supIn = __TS__ArrayFind(
        sups,
        function(____, l) return l.present end
    )
    local supBot = __TS__ArrayFind(
        sups,
        function(____, l) return l.present and l.bot end
    )
    local cal = supIn ~= nil and supIn.bot and Calendar.Of(supIn.unit, now) or nil
    local ____temp_7
    if cal ~= nil then
        ____temp_7 = Calendar.NextLeave(cal, now)
    else
        ____temp_7 = nil
    end
    local dep = ____temp_7
    local rule = "R1"
    local mode = "safe"
    local away = enemiesAway(m, now, cx, cy)
    if coreIn ~= nil and coreThreat(coreIn, supIn ~= nil) then
        rule = "R6"
    elseif away and (coreIn ~= nil or supIn ~= nil) then
        rule = "R5"
        mode = "shove"
    elseif supIn ~= nil and dep ~= nil and dep >= s.DepartAfter and dep <= s.DepartWithin then
        rule = "R2"
    elseif coreIn ~= nil and supIn == nil then
        rule = "R3"
    end
    local ourT1, dir = LanePush.OwnT1(path, team)
    local theirT1 = __TS__ArrayFind(
        path.towers,
        function(____, tw) return tw.team ~= team end
    ).s
    local span = dir * (theirT1 - ourT1)
    local reach = WorldFacts.Reach(s.TowerRange)
    local tgt = mode == "shove" and span - reach or LanePush.TargetOf(lane)
    local at = math.floor(now) + s.Horizon
    local samples = LanePush.Forecast(team, lane, s.Horizon + 3)
    local plain = ownAt(samples, path, team, at)
    local cycle = LaneConfig.Settings().Timing.WaveCycle
    local ts = math.floor(now / cycle) * cycle
    local gone = LanePush.WaveGoneNow(team, lane, ts, at)
    local need = r.own + r.move - tgt
    local base = plain or r.own + r.move
    local n45 = base - tgt
    local intent = ____exports.IntentOf(n45, s.Band, rule == "R2")
    local pe = (gone and gone.own) ~= nil and plain ~= nil and s.PullScale * s.DivertShare * (gone.own - plain) or nil
    local pc
    if supBot ~= nil then
        local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
        local w = PullJob.Window(supBot.unit, now)
        if w ~= nil then
            local fit, e = Calendar.FitOf(
                Calendar.Of(supBot.unit, now),
                w.start,
                w["end"]
            )
            pc = ____exports.PullCalendar(fit, e, n45, now)
        end
    end
    local levers = {}
    local anyIn = coreIn ~= nil or supIn ~= nil
    levers[#levers + 1] = {
        name = "predeny",
        effect = -s.PreDenySize,
        danger = 1,
        who = coreIn ~= nil and supIn ~= nil and "both" or (coreIn ~= nil and "core" or "sup"),
        why = not anyIn and "nobody" or (not Ours.On("PreDeny") and "off" or nil)
    }
    levers[#levers + 1] = {
        name = "feed",
        effect = -s.FeedSize,
        danger = 2,
        who = coreIn ~= nil and "core" or "sup",
        why = not anyIn and "nobody" or nil
    }
    levers[#levers + 1] = {
        name = "pull",
        effect = pe or 0,
        danger = 3,
        who = supBot ~= nil and tostring(supBot.pid) or "",
        why = supBot == nil and "no_sup" or (rule == "R6" and "r6" or (pe == nil and "no_clash" or (gone ~= nil and gone.pw == 0 and "no_wave" or pc and pc.why)))
    }
    levers[#levers + 1] = {
        name = "setup",
        effect = s.SetupSize,
        danger = 1,
        who = coreIn ~= nil and supIn ~= nil and "both" or (coreIn ~= nil and "core" or "sup"),
        why = mode == "shove" and "mode" or (not anyIn and "nobody" or (not Ours.On("PreDeny") and "off" or nil))
    }
    levers[#levers + 1] = {
        name = "shove",
        effect = s.PreDenySize,
        danger = 2,
        who = coreIn ~= nil and "core" or "sup",
        why = mode ~= "shove" and "mode" or (not anyIn and "nobody" or nil)
    }
    local c
    if intent == "reset" and math.abs(n45) <= s.Band then
        local pd = levers[1]
        c = pd.why == nil and ({levers = {pd}, left = n45 + pd.effect, short = false}) or ({levers = {}, left = n45, short = true})
    elseif intent == "back" or intent == "reset" or intent == "forward" then
        c = ____exports.Choose(n45, s.Band, levers)
    else
        c = {levers = {}, left = n45, short = false}
    end
    local left = c.left
    local chosen = __TS__ArrayMap(
        c.levers,
        function(____, l) return l.name end
    )
    local who = __TS__ArrayMap(
        c.levers,
        function(____, l) return l.who end
    )
    local after = tgt + left
    if __TS__ArrayIncludes(chosen, "pull") and after < reach and coreIn ~= nil then
        chosen[#chosen + 1] = "hold"
        who[#who + 1] = tostring(coreIn.pid)
        after = math.max(after, reach)
    end
    local rej = {}
    for ____, l in ipairs(levers) do
        if l.why ~= nil then
            rej[#rej + 1] = (l.name .. ":") .. l.why
        end
    end
    local ms = started ~= nil and math.floor((clock() - started) * 10000 + 0.5) / 10 or nil
    local ____m_chks_12 = m.chks
    ____m_chks_12[#____m_chks_12 + 1] = ts
    local ____chosen_includes_result_15
    if __TS__ArrayIncludes(chosen, "pull") then
        ____chosen_includes_result_15 = pc and pc.yld
    else
        ____chosen_includes_result_15 = nil
    end
    local yields = ____chosen_includes_result_15
    local d = {
        wave = ts,
        at = now,
        rule = rule,
        mode = mode,
        intent = intent,
        levers = chosen,
        who = who,
        cx = cx,
        cy = cy,
        core = coreIn and coreIn.unit,
        yields = yields
    }
    ____exports.Remember(team, lane, d)
    local ____Telemetry_Event_25 = Telemetry.Event
    local ____array_24 = __TS__SparseArrayNew(
        {"team", team},
        {"lane", lane},
        {"kind", "wave"},
        {"wave", ts},
        {"mode", mode},
        {"rule", rule},
        {
            "tgt",
            round(tgt)
        },
        {
            "own",
            round(r.own)
        },
        {
            "mv",
            round(r.move)
        },
        {"st", r.state},
        {
            "need",
            round(need)
        },
        {
            "m45",
            round(plain)
        },
        {
            "p45",
            round(gone and gone.own)
        },
        {
            "pe",
            round(pe)
        },
        {
            "n45",
            round(n45)
        },
        {"intent", intent},
        {
            "lever",
            #chosen > 0 and table.concat(chosen, "+") or "none"
        },
        {
            "who",
            table.concat(who, "+")
        },
        {
            "left",
            round(after - tgt)
        }
    )
    local ____c_short_20
    if c.short then
        ____c_short_20 = true
    else
        ____c_short_20 = nil
    end
    __TS__SparseArrayPush(
        ____array_24,
        {"short", ____c_short_20},
        {
            "rej",
            table.concat(rej, ";")
        },
        {"core", coreIn ~= nil and coreIn.pid or nil},
        {"sup", supIn ~= nil and supIn.pid or nil},
        {
            "dep",
            round(dep)
        },
        {"fit", pc and pc.fit},
        {"yld", yields}
    )
    local ____away_23
    if away then
        ____away_23 = true
    else
        ____away_23 = nil
    end
    __TS__SparseArrayPush(____array_24, {"away", ____away_23}, {"ms", ms})
    ____Telemetry_Event_25(
        "lane_ctl",
        {__TS__SparseArraySpread(____array_24)}
    )
end
local function check(team, lane, wave)
    local r = LanePush.Read(team, lane)
    Telemetry.Event(
        "lane_ctl",
        {
            {"team", team},
            {"lane", lane},
            {"kind", "chk"},
            {"wave", wave},
            {
                "own",
                round(r and r.own)
            },
            {
                "mv",
                round(r and r.move)
            },
            {"st", r and r.state}
        }
    )
end
--- Slice 3: the live decision's pull takes this support's stack minute `minute`.
function ____exports.YieldsStack(team, lane, pid, minute)
    local d = ____exports.Current(team, lane)
    if d == nil or d.yields ~= minute then
        return false
    end
    do
        local i = 0
        while i < #d.levers do
            if d.levers[i + 1] == "pull" and d.who[i + 1] == tostring(pid) then
                return true
            end
            i = i + 1
        end
    end
    return false
end
--- The decision made for the wave that spawned at `wave` (a pull's pulled wave), while the controller drives.
function ____exports.DecisionFor(team, lane, wave)
    if not ____exports.Drives() then
        return nil
    end
    local ____opt_32 = memory[(tostring(team) .. ":") .. tostring(lane)]
    return ____opt_32 and ____opt_32.decisions[wave]
end
--- The lane's mode for the idle swing: the live decision's, `safe` with none.
function ____exports.ModeFor(team, lane)
    local ____opt_36 = ____exports.Current(team, lane)
    return ____opt_36 and ____opt_36.mode or "safe"
end
--- Whether `lever` is in the lane's live decision; undefined with none (the owner's own trigger then decides).
function ____exports.Chosen(team, lane, lever)
    local d = ____exports.Current(team, lane)
    local ____temp_38
    if d == nil then
        ____temp_38 = nil
    else
        ____temp_38 = __TS__ArrayIncludes(d.levers, lever)
    end
    return ____temp_38
end
--- An enemy hero seen (visible, alive, not an illusion) within EnemyAway of the clash: the shove's break. Vision loss is no
-- break (review 2026-11-06-lane-control-2b H1: every R5 shove in lctl2 broke 0-13 s in when `enemiesAway` read a hero out of
-- vision as near).
function ____exports.EnemySeenNear(heroes, cx, cy, r)
    for ____, h in ipairs(heroes) do
        if (h.x - cx) ^ 2 + (h.y - cy) ^ 2 <= r * r then
            return true
        end
    end
    return false
end
local function seenEnemies()
    local out = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue95
            repeat
                if e == nil or e == nil or e:IsNull() or not e:IsAlive() or e:IsIllusion() or not e:CanBeSeen() then
                    __continue95 = true
                    break
                end
                local at = e:GetLocation()
                out[#out + 1] = {x = at.x, y = at.y}
                __continue95 = true
            until true
            if not __continue95 then
                break
            end
        end
    end
    return out
end
--- Commitment's breaking events for a `shove` mode (s5.1b): an enemy hero seen near the clash, or the core low or dead.
local function breakCheck(team, lane, m, now)
    local d = m.last
    if d == nil or d.mode ~= "shove" or now - d.at > ____exports.SETTINGS.Live then
        return
    end
    if m.breakAt ~= nil and now - m.breakAt < ____exports.SETTINGS.BreakEvery then
        return
    end
    m.breakAt = now
    local why
    if ____exports.EnemySeenNear(
        seenEnemies(),
        d.cx,
        d.cy,
        ____exports.SETTINGS.EnemyAway
    ) then
        why = "enemy"
    elseif d.core ~= nil and not d.core:IsNull() and (not d.core:IsAlive() or d.core:GetHealth() / math.max(
        1,
        d.core:GetMaxHealth()
    ) < ____exports.SETTINGS.CoreLowHp) then
        why = "core_low"
    end
    if why == nil then
        return
    end
    d.mode = "safe"
    d.broke = why
    d.levers = __TS__ArrayFilter(
        d.levers,
        function(____, l) return l ~= "shove" end
    )
    Telemetry.Event("lane_ctl", {
        {"team", team},
        {"lane", lane},
        {"kind", "break"},
        {"wave", d.wave},
        {"why", why}
    })
end
--- Called every frame by every hero of the team: the first call in a lane's read second decides that lane's wave (each lane the
-- team has a hero assigned to), and the first call Horizon s after a decision logs its check.
function ____exports.Tick(bot)
    if not Ours.On("LaneControl") then
        return
    end
    local now = DotaTime()
    local s = ____exports.SETTINGS
    if now < s.From or now > s.Until + s.Horizon then
        return
    end
    local team = bot:GetTeam()
    if team ~= Team.Radiant and team ~= Team.Dire then
        return
    end
    local lane = bot:GetAssignedLane()
    if lane ~= Lane.Top and lane ~= Lane.Mid and lane ~= Lane.Bot then
        return
    end
    local m = memoryOf(team, lane)
    local cycle = LaneConfig.Settings().Timing.WaveCycle
    local wave = math.floor(now / cycle) * cycle
    while #m.chks > 0 and now >= m.chks[1] + s.ReadAt + s.Horizon do
        check(
            team,
            lane,
            table.remove(m.chks, 1)
        )
    end
    if ____exports.Drives() then
        breakCheck(team, lane, m, now)
    end
    if now > s.Until or now - wave < s.ReadAt or m.wave == wave then
        return
    end
    m.wave = wave
    decide(team, lane, now, m)
end
return ____exports
