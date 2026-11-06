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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- All `judgement` unless marked.
____exports.SETTINGS = {
    ReadAt = 2,
    From = 60,
    Until = 720,
    Horizon = 45,
    Band = 150,
    PullScale = 0.6,
    PreDenySize = 300,
    FeedSize = 300,
    InLane = 2000,
    DepartWithin = 60,
    DepartLead = 25,
    CoreLowHp = 0.4,
    CoreThreat = 2,
    CoreThreatR = 1200,
    EnemyLaneR = 2500,
    EnemyMemory = 90,
    EnemyAway = 3000,
    TowerRange = 700
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
local memory = {}
function ____exports.ResetCache()
    for k in pairs(memory) do
        __TS__Delete(memory, k)
    end
end
local function memoryOf(team, lane)
    local key = (tostring(team) .. ":") .. tostring(lane)
    local m = memory[key]
    if m == nil then
        m = {enemies = {}, chks = {}}
        memory[key] = m
    end
    return m
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
--- Seconds until the support's next departure (rune trip or stack slot) leaves, or undefined with none in reach.
function ____exports.NextDeparture(pos, now)
    local best
    local function consider(eventAt)
        local leave = eventAt - ____exports.SETTINGS.DepartLead
        if leave >= now and (best == nil or leave - now < best) then
            best = leave - now
        end
    end
    for ____, ____value in ipairs(RuneJob.SETTINGS.Trips[pos] or ({})) do
        local at = ____value[2]
        consider(at)
    end
    if pos == 4 or pos == 5 then
        for ____, m in ipairs(StackJob.Minutes()) do
            consider(m * 60 + 52)
        end
    end
    return best
end
--- R5: their laners are known: every enemy hero seen near the lane lately is dead or seen far from the clash.
local function enemiesAway(m, now, cx, cy)
    local visible = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue39
            repeat
                if e == nil or e == nil or e:IsIllusion() or not e:CanBeSeen() then
                    __continue39 = true
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
                __continue39 = true
            until true
            if not __continue39 then
                break
            end
        end
    end
    local any = false
    for k in pairs(m.enemies) do
        do
            local __continue43
            repeat
                local pid = tonumber(k)
                if now - m.enemies[pid] > ____exports.SETTINGS.EnemyMemory then
                    __TS__Delete(m.enemies, pid)
                    __continue43 = true
                    break
                end
                any = true
                if not IsHeroAlive(pid) then
                    __continue43 = true
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
                __continue43 = true
            until true
            if not __continue43 then
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
    local ____temp_7
    if supIn ~= nil then
        ____temp_7 = ____exports.NextDeparture(supIn.pos, now)
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
    elseif supIn ~= nil and dep ~= nil and dep <= s.DepartWithin then
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
    local tgt = mode == "shove" and span - s.TowerRange or LanePush.TargetOf(lane)
    local at = math.floor(now) + s.Horizon
    local samples = LanePush.Forecast(team, lane, s.Horizon + 3)
    local plain = ownAt(samples, path, team, at)
    local ts = math.floor(now / 30) * 30
    local gone = LanePush.WaveGoneNow(team, lane, ts, at)
    local need = r.own + r.move - tgt
    local base = plain or r.own + r.move
    local n45 = base - tgt
    local intent = ____exports.IntentOf(n45, s.Band, rule == "R2")
    local pe = (gone and gone.own) ~= nil and plain ~= nil and s.PullScale * (gone.own - plain) or nil
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
        why = supBot == nil and "no_sup" or (rule == "R6" and "r6" or (pe == nil and "no_clash" or (gone ~= nil and gone.pw == 0 and "no_wave" or nil)))
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
    elseif intent == "back" or intent == "reset" or intent == "forward" and mode == "shove" then
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
    if __TS__ArrayIncludes(chosen, "pull") and after < s.TowerRange and coreIn ~= nil then
        chosen[#chosen + 1] = "hold"
        who[#who + 1] = tostring(coreIn.pid)
        after = math.max(after, s.TowerRange)
    end
    local rej = {}
    for ____, l in ipairs(levers) do
        if l.why ~= nil then
            rej[#rej + 1] = (l.name .. ":") .. l.why
        end
    end
    local ms = started ~= nil and math.floor((clock() - started) * 10000 + 0.5) / 10 or nil
    local ____m_chks_10 = m.chks
    ____m_chks_10[#____m_chks_10 + 1] = ts
    local ____Telemetry_Event_16 = Telemetry.Event
    local ____array_15 = __TS__SparseArrayNew(
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
    local ____c_short_13
    if c.short then
        ____c_short_13 = true
    else
        ____c_short_13 = nil
    end
    __TS__SparseArrayPush(
        ____array_15,
        {"short", ____c_short_13},
        {
            "rej",
            table.concat(rej, ";")
        },
        {"core", coreIn ~= nil and coreIn.pid or nil},
        {"sup", supIn ~= nil and supIn.pid or nil},
        {
            "dep",
            round(dep)
        }
    )
    local ____away_14
    if away then
        ____away_14 = true
    else
        ____away_14 = nil
    end
    __TS__SparseArrayPush(____array_15, {"away", ____away_14}, {"ms", ms})
    ____Telemetry_Event_16(
        "lane_ctl",
        {__TS__SparseArraySpread(____array_15)}
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
    local wave = math.floor(now / 30) * 30
    while #m.chks > 0 and now >= m.chks[1] + s.ReadAt + s.Horizon do
        check(
            team,
            lane,
            table.remove(m.chks, 1)
        )
    end
    if now > s.Until or now - wave < s.ReadAt or m.wave == wave then
        return
    end
    m.wave = wave
    decide(team, lane, now, m)
end
return ____exports
