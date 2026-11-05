--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
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

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
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

local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end

local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
end

local function __TS__DelegatedYield(iterable)
    if type(iterable) == "string" then
        for index = 0, #iterable - 1 do
            coroutine.yield(__TS__StringAccess(iterable, index))
        end
    elseif iterable.____coroutine ~= nil then
        local co = iterable.____coroutine
        while true do
            local status, value = coroutine.resume(co)
            if not status then
                error(value, 0)
            end
            if coroutine.status(co) == "dead" then
                return value
            else
                coroutine.yield(value)
            end
        end
    elseif iterable[Symbol.iterator] then
        local iterator = iterable[Symbol.iterator](iterable)
        while true do
            local result = iterator:next()
            if result.done then
                return result.value
            else
                coroutine.yield(result.value)
            end
        end
    else
        for ____, value in ipairs(iterable) do
            coroutine.yield(value)
        end
    end
end

local __TS__Unpack = table.unpack or unpack

local __TS__Generator
do
    local function generatorIterator(self)
        return self
    end
    local function generatorNext(self, ...)
        local co = self.____coroutine
        if coroutine.status(co) == "dead" then
            return {done = true}
        end
        local status, value = coroutine.resume(co, ...)
        if not status then
            error(value, 0)
        end
        return {
            value = value,
            done = coroutine.status(co) == "dead"
        }
    end
    function __TS__Generator(fn)
        return function(...)
            local args = {...}
            local argsLength = __TS__CountVarargs(...)
            return {
                ____coroutine = coroutine.create(function() return fn(__TS__Unpack(args, 1, argsLength)) end),
                [Symbol.iterator] = generatorIterator,
                next = generatorNext
            }
        end
    end
end
-- End of Lua Library inline imports
local ____exports = {}
local ourTower, share, creepLines, trackCreeps, laneCreepsNear, onNeutral, sampleWave, diag, stale, taggedState, trackTagged, countDiverted, targetKind, watchLine, taggedFields, running
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function ourTower(bot)
    local ids = bot:GetAssignedLane() == Lane.Top and ({Tower.Top1, Tower.Top2, Tower.Top3}) or ({Tower.Bot1, Tower.Bot2, Tower.Bot3})
    for ____, id in ipairs(ids) do
        local t = GetTower(
            bot:GetTeam(),
            id
        )
        if t ~= nil and t ~= nil and t:IsAlive() then
            return t:GetLocation()
        end
    end
    return nil
end
function share(p)
    return p.wave > 0 and math.floor(p.peak / p.wave * 100 + 0.5) / 100 or 0
end
function creepLines(bot, p)
    if p.creeps == nil then
        return
    end
    local function r1(x)
        return x ~= nil and math.floor(x * 10 + 0.5) / 10 or nil
    end
    local function r0(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    for ____, ____value in __TS__Iterator(p.creeps) do
        local c = ____value[2]
        Telemetry.Event(
            "pull_creep",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"slot", p.plan.slot},
                {"camp", p.plan.camp.campIdx},
                {"ci", c.ci},
                {"rg", c.rg},
                {"tr", c.tr},
                {
                    "tt",
                    r1(c.tt)
                },
                {
                    "dp",
                    r0(c.dp)
                },
                {
                    "dn",
                    r0(c.dn)
                },
                {"ph", c.ph},
                {
                    "pv",
                    r0(c.pv)
                },
                {
                    "po",
                    r0(c.po)
                },
                {
                    "ca",
                    r0(c.ca)
                },
                {
                    "lt",
                    r1(c.lt)
                },
                {
                    "ld",
                    r0(c.ld)
                },
                {
                    "ln",
                    r0(c.ln)
                }
            }
        )
    end
    p.creeps = nil
end
function trackCreeps(bot, p)
    if p.hat == nil then
        return
    end
    local now = DotaTime()
    local at = bot:GetLocation()
    local pv = 0
    if p.pAt ~= nil and p.pT ~= nil and now > p.pT then
        pv = GetUnitToLocationDistance(bot, p.pAt) / (now - p.pT)
    end
    p.pAt = at
    p.pT = now
    if p.creeps == nil then
        p.creeps = __TS__New(Map)
    end
    local path = p.plan.timing.lanePath
    local meetAlong = p.plan.timing.meetAlong
    local ph = 0
    local alive = {}
    for ____, u in ipairs(p.tagged or ({})) do
        do
            local __continue115
            repeat
                if stale(u) then
                    __continue115 = true
                    break
                end
                alive[#alive + 1] = u
                if u:GetAttackTarget() == bot then
                    ph = 1
                end
                __continue115 = true
            until true
            if not __continue115 then
                break
            end
        end
    end
    local po = path ~= nil and select(
        2,
        PullTiming.Along(path, at)
    ) or nil
    for ____, c in ipairs(laneCreepsNear(
        p.plan,
        LaneConfig.Settings().Radii.MeetWatch
    )) do
        do
            local __continue119
            repeat
                local t = p.creeps:get(c)
                if t == nil then
                    t = {ci = p.creepN or 0, rg = (string.find(
                        c:GetUnitName(),
                        "ranged"
                    )) ~= nil and 1 or 0, tr = 0}
                    p.creepN = (p.creepN or 0) + 1
                    p.creeps:set(c, t)
                end
                if t.tr == 1 then
                    __continue119 = true
                    break
                end
                local dp = GetUnitToUnitDistance(c, bot)
                local function nearest()
                    local dn
                    for ____, u in ipairs(alive) do
                        local d = GetUnitToUnitDistance(c, u)
                        if dn == nil or d < dn then
                            dn = d
                        end
                    end
                    return dn
                end
                if path ~= nil and t.lt == nil then
                    local off = select(
                        2,
                        PullTiming.Along(
                            path,
                            c:GetLocation()
                        )
                    )
                    if t.off0 == nil or off < t.off0 then
                        t.off0 = off
                    elseif off > t.off0 + ____exports.SETTINGS.Leave then
                        t.lt = now - p.hat
                        t.ld = dp
                        t.ln = nearest()
                    end
                end
                local turned = onNeutral(c)
                if not turned and t.dp ~= nil and dp >= t.dp then
                    __continue119 = true
                    break
                end
                local dn = nearest()
                t.tr = turned and 1 or 0
                t.tt = now - p.hat
                t.dp = dp
                t.dn = dn
                t.ph = ph
                t.pv = pv
                t.po = po
                if path ~= nil and meetAlong ~= nil then
                    t.ca = (PullTiming.Along(
                        path,
                        c:GetLocation()
                    )) - meetAlong
                end
                __continue119 = true
            until true
            if not __continue119 then
                break
            end
        end
    end
end
function laneCreepsNear(p, radius)
    local out = {}
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue134
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue134 = true
                    break
                end
                if GetUnitToLocationDistance(c, p.meet) <= radius or GetUnitToLocationDistance(c, p.spawner.location) <= radius then
                    out[#out + 1] = c
                end
                __continue134 = true
            until true
            if not __continue134 then
                break
            end
        end
    end
    return out
end
function onNeutral(c)
    local t = c:GetAttackTarget()
    return t ~= nil and t ~= nil and t:GetTeam() == Team.Neutral
end
function sampleWave(bot, p)
    local now = DotaTime()
    diag(bot, p, trackCreeps)
    if p.sampledAt ~= nil and now - p.sampledAt < ____exports.SETTINGS.WatchEvery then
        return
    end
    p.sampledAt = now
    countDiverted(p)
    diag(bot, p, trackTagged)
end
function diag(bot, p, fn)
    local ok, err = pcall(fn, bot, p)
    if ok or p.diagErr == true then
        return
    end
    p.diagErr = true
    print((("[Humaniser] pull diag error slot=" .. tostring(p.plan.slot)) .. ": ") .. tostring(err))
end
function stale(u)
    return u.IsNull ~= nil and u:IsNull() or not u:IsAlive()
end
function taggedState(bot, p, ours)
    local s = {alive = 0, onPuller = 0, onCreep = 0}
    for ____, u in ipairs(p.tagged or ({})) do
        do
            local __continue166
            repeat
                if stale(u) then
                    __continue166 = true
                    break
                end
                s.alive = s.alive + 1
                local k = targetKind(
                    bot,
                    u:GetAttackTarget()
                )
                if k == "p" then
                    s.onPuller = s.onPuller + 1
                elseif k == "c" then
                    s.onCreep = s.onCreep + 1
                end
                local d = #ours > 0 and math.huge or GetUnitToLocationDistance(u, p.plan.meet)
                for ____, c in ipairs(ours) do
                    d = math.min(
                        d,
                        GetUnitToUnitDistance(u, c)
                    )
                end
                if s.nearest == nil or d < s.nearest then
                    s.nearest = d
                end
                local h = GetUnitToLocationDistance(u, p.plan.spawner.location)
                if s.farthest == nil or h > s.farthest then
                    s.farthest = h
                end
                __continue166 = true
            until true
            if not __continue166 then
                break
            end
        end
    end
    return s
end
function trackTagged(bot, p)
    local now = DotaTime()
    if p.wa == nil and p.early ~= nil then
        for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
            do
                local __continue177
                repeat
                    if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) or __TS__ArrayIndexOf(p.early, c) >= 0 then
                        __continue177 = true
                        break
                    end
                    if GetUnitToLocationDistance(c, p.plan.meet) <= ____exports.SETTINGS.ArriveR then
                        p.wa = now
                        break
                    end
                    __continue177 = true
                until true
                if not __continue177 then
                    break
                end
            end
        end
    end
    if p.tagged == nil or p.peaks == nil then
        return
    end
    local s = taggedState(
        bot,
        p,
        laneCreepsNear(
            p.plan,
            LaneConfig.Settings().Radii.MeetWatch
        )
    )
    if s.farthest ~= nil and (p.gh == nil or s.farthest > p.gh) then
        p.gh = s.farthest
    end
    if p.na == nil and s.nearest ~= nil and s.nearest <= ____exports.SETTINGS.Acquire and s.alive > 0 then
        p.na = now
    end
    local left = 0
    local home = 0
    for ____, u in ipairs(p.tagged) do
        do
            local __continue184
            repeat
                if stale(u) then
                    __continue184 = true
                    break
                end
                local ____opt_14 = p.starts
                local s0 = ____opt_14 and ____opt_14:get(u)
                if p.nm == nil and s0 ~= nil and GetUnitToLocationDistance(u, s0) >= ____exports.SETTINGS.Moved then
                    p.nm = now
                end
                local h = GetUnitToLocationDistance(u, p.plan.spawner.location)
                local peak = math.max(
                    p.peaks:get(u) or 0,
                    h
                )
                p.peaks:set(u, peak)
                if peak <= ____exports.SETTINGS.Left then
                    __continue184 = true
                    break
                end
                if p.g4 == nil then
                    p.g4 = now
                end
                left = left + 1
                local t = u:GetAttackTarget()
                if h < peak - ____exports.SETTINGS.HomeMargin and (t == nil or t == nil) then
                    home = home + 1
                end
                __continue184 = true
            until true
            if not __continue184 then
                break
            end
        end
    end
    if p.gu == nil and left > 0 and home == left then
        p.gu = now
        p.gd = s.nearest
    end
end
function countDiverted(p)
    local radii = LaneConfig.Settings().Radii
    local n = 0
    for ____, c in ipairs(laneCreepsNear(p.plan, radii.MeetWatch)) do
        if onNeutral(c) then
            n = n + 1
        end
    end
    if n == 0 then
        return
    end
    if p.wave == 0 then
        p.wave = math.max(
            1,
            #laneCreepsNear(p.plan, radii.WaveSize)
        )
    end
    p.peak = math.max(
        p.peak,
        math.min(n, p.wave)
    )
end
function targetKind(bot, t)
    if t == nil or t == nil then
        return "x"
    end
    if t == bot then
        return "p"
    end
    if t:IsHero() then
        return "h"
    end
    if t:IsCreep() then
        return "c"
    end
    return "o"
end
function watchLine(bot, p, ph)
    local now = DotaTime()
    if p.watchedAt ~= nil and now - p.watchedAt < ____exports.SETTINGS.WatchLogEvery then
        return
    end
    p.watchedAt = now
    local radii = LaneConfig.Settings().Radii
    local meet = p.plan.meet
    local ours = laneCreepsNear(p.plan, radii.MeetWatch)
    local won = 0
    local whe = 0
    local wcr = 0
    local wid = 0
    local wd
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue205
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue205 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, meet)
                if wd == nil or d < wd then
                    wd = d
                end
                __continue205 = true
            until true
            if not __continue205 then
                break
            end
        end
    end
    for ____, c in ipairs(ours) do
        local t = c:GetAttackTarget()
        if t == nil or t == nil then
            wid = wid + 1
        elseif t:GetTeam() == Team.Neutral then
            won = won + 1
        elseif t:IsHero() then
            whe = whe + 1
        else
            wcr = wcr + 1
        end
    end
    local nn = 0
    local ntp = 0
    local ntc = 0
    local ntx = 0
    local best
    local nd = math.huge
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue215
            repeat
                if not u:IsAlive() then
                    __continue215 = true
                    break
                end
                local d = GetUnitToLocationDistance(u, meet)
                if d > ____exports.SETTINGS.WatchNeutralSearch then
                    __continue215 = true
                    break
                end
                if d <= radii.WaveSize then
                    nn = nn + 1
                    local k = targetKind(
                        bot,
                        u:GetAttackTarget()
                    )
                    if k == "p" then
                        ntp = ntp + 1
                    elseif k == "c" then
                        ntc = ntc + 1
                    elseif k == "x" then
                        ntx = ntx + 1
                    end
                end
                for ____, c in ipairs(ours) do
                    d = math.min(
                        d,
                        GetUnitToUnitDistance(u, c)
                    )
                end
                if d < nd then
                    nd = d
                    best = u
                end
                __continue215 = true
            until true
            if not __continue215 then
                break
            end
        end
    end
    local function r0(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    local ____Telemetry_Event_20 = Telemetry.Event
    local ____array_19 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"slot", p.plan.slot},
        {"ph", ph},
        {"wc", #ours},
        {"won", won},
        {"whe", whe},
        {"wcr", wcr},
        {"wid", wid},
        {
            "wd",
            r0(wd)
        },
        {"nn", nn},
        {"ntp", ntp},
        {"ntc", ntc},
        {"ntx", ntx}
    )
    local ____temp_16
    if best ~= nil then
        ____temp_16 = r0(nd)
    else
        ____temp_16 = nil
    end
    __TS__SparseArrayPush(____array_19, {"nd", ____temp_16})
    local ____temp_17
    if best ~= nil then
        ____temp_17 = r0(GetUnitToLocationDistance(best, p.plan.spawner.location))
    else
        ____temp_17 = nil
    end
    __TS__SparseArrayPush(
        ____array_19,
        {"nh", ____temp_17},
        {
            "nt",
            best ~= nil and targetKind(
                bot,
                best:GetAttackTarget()
            ) or nil
        }
    )
    local ____bot_IsAlive_result_18
    if bot:IsAlive() then
        ____bot_IsAlive_result_18 = r0(GetUnitToLocationDistance(bot, meet))
    else
        ____bot_IsAlive_result_18 = nil
    end
    __TS__SparseArrayPush(
        ____array_19,
        {"pd", ____bot_IsAlive_result_18},
        {"shd", p.shs ~= nil and 1 or nil},
        unpack(taggedFields(bot, p, ours))
    )
    ____Telemetry_Event_20(
        "pull_watch",
        {__TS__SparseArraySpread(____array_19)}
    )
end
function taggedFields(bot, p, ours)
    if p.tagged == nil then
        return {}
    end
    local s = taggedState(bot, p, ours)
    local function r0(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    return {
        {"tn", s.alive},
        {"tp", s.onPuller},
        {"tc", s.onCreep},
        {
            "td",
            r0(s.nearest)
        },
        {
            "th",
            r0(s.farthest)
        }
    }
end
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
function ____exports.End(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
____exports.SETTINGS = {
    Priority = 0.9,
    Early = 2,
    PathFactor = 1.2,
    WantPast = 150,
    PartnerHp = 0.5,
    PartnerRadius = 900,
    PartnerGank = 3,
    SiteEnemy = 1200,
    WatchEvery = 0.25,
    TrailSec = 10,
    WatchLogEvery = 1,
    WatchNeutralSearch = 3000,
    TagRadius = 1200,
    Acquire = 500,
    ArriveR = 300,
    Left = 400,
    HomeMargin = 150,
    Moved = 50,
    Leave = 100,
    HitSeconds = 1.5,
    StartReserve = 0.25,
    DefaultDps = {small = 40, medium = 60, large = 80, ancient = 150},
    BailReserve = 0.25,
    BailGrace = 2,
    BailFor = 6,
    BailScan = 1200,
    BailStep = 700,
    ShedMargin = 300,
    ShedFor = 5
}
running = {}
local trailing = {}
local handled = {}
local decided = {}
local timers = {}
local gateWhy = {}
local ended = {}
function ____exports.ResetCache()
    for ____, t in ipairs({
        running,
        trailing,
        handled,
        decided,
        gateWhy,
        timers,
        ended
    }) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
local function isSupport(u)
    local pos = LaneConfig.PositionOf(u)
    return pos == 4 or pos == 5
end
--- The support that pulls for `bot`'s lane: pos5 when both supports share it.
local function pullerOfLane(bot)
    if LaneConfig.PositionOf(bot) == 5 then
        return true
    end
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue9
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot then
                        __continue9 = true
                        break
                    end
                    if LaneConfig.PositionOf(m) == 5 and m:GetAssignedLane() == lane then
                        return false
                    end
                    __continue9 = true
                until true
                if not __continue9 then
                    break
                end
            end
            i = i + 1
        end
    end
    return true
end
local function campFor(bot)
    local lane = bot:GetAssignedLane()
    if lane ~= Lane.Top and lane ~= Lane.Bot then
        return nil
    end
    return Camps.PullCampsFor(
        bot:GetTeam(),
        lane
    )[1]
end
function ____exports.Applies(bot)
    return Ours.On("SupportPull") and Ours.On("JobChooser") and bot:IsBot() and isSupport(bot) and pullerOfLane(bot) and campFor(bot) ~= nil
end
function ____exports.Priority(bot)
    return ____exports.Applies(bot) and ____exports.SETTINGS.Priority or nil
end
function ____exports.Claims(bot)
    return ____exports.Running(bot)
end
--- The next hit second at or after `from` among `seconds` of each minute (camp_jobs' NextAggroTime).
function ____exports.NextSlot(from, seconds, period)
    local base = math.floor(from / period) * period
    local best = math.huge
    for ____, s in ipairs(seconds) do
        for ____, t in ipairs({base + s, base + period + s}) do
            if t >= from and t < best then
                best = t
            end
        end
    end
    return best
end
--- The next wave's pull of `kind`. A half pull is the same wave and the same meet point hit HalfPullLater after the full
-- pull's second (pull_timing's half timing), so its slot is the first half second at or after the full one; `key` stays
-- the full slot, so one wave is read and decided once whatever the kind.
local function planFor(bot, now, kind)
    local camp = campFor(bot)
    local ____temp_0
    if camp ~= nil then
        ____temp_0 = Camps.SpawnerByIdx(camp.campIdx)
    else
        ____temp_0 = nil
    end
    local spawner = ____temp_0
    if camp == nil or camp.pull == nil or spawner == nil then
        return nil
    end
    local t = LaneConfig.Settings().Timing
    local full = PullTiming.ForCamp(camp, false)
    if #full.seconds == 0 then
        return nil
    end
    local key = ____exports.NextSlot(now - t.JobStartLate, full.seconds, t.PullPeriod)
    if math.floor(key / t.PullPeriod) * t.PullPeriod < t.NeutralFirstSpawn then
        return nil
    end
    local meet = camp.pull.meetPoint
    local timing = kind == "half" and PullTiming.ForCamp(camp, true, meet) or full
    if #timing.seconds == 0 then
        return nil
    end
    local slot = kind == "half" and ____exports.NextSlot(key, timing.seconds, t.PullPeriod) or key
    local lead = PullTiming.LeadPath(camp.pull, meet)
    local stand = Camps.StandPoint(
        spawner,
        lead[1],
        LaneConfig.Settings().Radii.StandOffset
    )
    return {
        kind = kind,
        key = key,
        camp = camp,
        spawner = spawner,
        stand = stand,
        lead = lead,
        meet = meet,
        timing = timing,
        slot = slot
    }
end
--- The safe lane of `bot`'s team (pull_timing's LaneAhead rule).
local function safeLane(bot)
    local lane = bot:GetAssignedLane()
    return lane ~= Lane.Mid and bot:GetTeam() == Team.Radiant == (lane == Lane.Bot)
end
--- Which pull a wanted slot gets: the safe-lane pos5 half-pulls when a wanted lane holds (it is out a little: slow
-- and thin the wave rather than reset it; banked full pulls from there took the clash to -0.66 in 30 s and back to +0.07
-- in 60, partial ones to -0.13 and -0.15, slice file Decisions), and full-pulls when it pushes out. Everyone else full.
function ____exports.KindFor(bot, r)
    if not Ours.On("SupportHalfPull") or LaneConfig.PositionOf(bot) ~= 5 or not safeLane(bot) then
        return "full"
    end
    if LaneConfig.Settings().PullTiming.HalfAll == true then
        return "half"
    end
    return r ~= nil and r.state == "HOLD" and "half" or "full"
end
local function travel(bot, p)
    return GetUnitToLocationDistance(bot, p.stand) * ____exports.SETTINGS.PathFactor / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
function ____exports.CampStateOf(spawner)
    local m = LaneConfig.Settings().Radii.BoxMargin
    local lo = spawner.min
    local hi = spawner.max
    local s = {
        n = 0,
        seen = 0,
        hp = 0,
        vis = IsLocationVisible(spawner.location),
        units = {}
    }
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue34
            repeat
                if not u:IsAlive() then
                    __continue34 = true
                    break
                end
                local p = u:GetLocation()
                if p == nil or p == nil then
                    __continue34 = true
                    break
                end
                if p.x < lo.x - m or p.x > hi.x + m or p.y < lo.y - m or p.y > hi.y + m then
                    __continue34 = true
                    break
                end
                s.n = s.n + 1
                if u:CanBeSeen() then
                    s.seen = s.seen + 1
                end
                s.hp = s.hp + u:GetHealth()
                local ____s_units_1 = s.units
                ____s_units_1[#____s_units_1 + 1] = u
                __continue34 = true
            until true
            if not __continue34 then
                break
            end
        end
    end
    return s
end
--- `empty` when the camp holds nothing to pull at `hitAt`: nothing returned while the team sees the camp's origin, and no
-- spawn minute before the hit (a camp respawns only on the minute, so it stays empty). An empty box out of sight says
-- nothing: the API returns no fogged neutrals (pc1: every one returned was `CanBeSeen`). `one` the same with a single
-- neutral left: too little to hold a wave (banked `ok` pulls with one neutral seen at the start diverted 26 of 56, two or
-- more 243 of 385; user 04/11/2026: skip it). Stacking it instead is the stack job's call, not this one's.
function ____exports.CampGate(s, now, hitAt)
    local period = LaneConfig.Settings().Timing.PullPeriod
    if not s.vis or math.floor(hitAt / period) > math.floor(now / period) then
        return nil
    end
    if s.n == 0 then
        return "empty"
    end
    if s.n == 1 then
        return "one"
    end
    return nil
end
--- The camp's expected damage on `bot` over `seconds` of its hits (the pull's HitSeconds by default; DefaultDps unseen).
function ____exports.CampDamage(bot, s, ____type, seconds)
    local exposure = seconds or ____exports.SETTINGS.HitSeconds
    if #s.units == 0 then
        return ____exports.SETTINGS.DefaultDps[____type] * exposure
    end
    local dmg = 0
    for ____, u in ipairs(s.units) do
        dmg = dmg + u:GetEstimatedDamageToTarget(true, bot, exposure, DamageType.All)
    end
    return dmg
end
--- The puller cannot take the camp: its expected damage would leave less than StartReserve of max HP.
local function campDmgGate(bot, dmg)
    return bot:GetHealth() - dmg < bot:GetMaxHealth() * ____exports.SETTINGS.StartReserve and "camp-dmg" or nil
end
--- Where the puller steps back to while neutrals are about to kill it (SETTINGS BailReserve), else undefined.
local function bailPoint(bot)
    if not bot:IsAlive() then
        return nil
    end
    local at = bot:GetLocation()
    local dps = 0
    local cx = 0
    local cy = 0
    local k = 0
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue51
            repeat
                if not u:IsAlive() or u:GetAttackTarget() ~= bot or GetUnitToUnitDistance(u, bot) > ____exports.SETTINGS.BailScan then
                    __continue51 = true
                    break
                end
                local l = u:GetLocation()
                if l == nil or l == nil then
                    __continue51 = true
                    break
                end
                dps = dps + u:GetEstimatedDamageToTarget(true, bot, 1, DamageType.All)
                cx = cx + l.x
                cy = cy + l.y
                k = k + 1
                __continue51 = true
            until true
            if not __continue51 then
                break
            end
        end
    end
    if k == 0 then
        return nil
    end
    if bot:GetHealth() - dps * ____exports.SETTINGS.BailGrace >= bot:GetMaxHealth() * ____exports.SETTINGS.BailReserve then
        return nil
    end
    local tower = ourTower(bot)
    if tower ~= nil then
        return tower
    end
    local dx = at.x - cx / k
    local dy = at.y - cy / k
    local d = math.max(
        1,
        math.sqrt(dx * dx + dy * dy)
    )
    return Vector(at.x + dx * ____exports.SETTINGS.BailStep / d, at.y + dy * ____exports.SETTINGS.BailStep / d, at.z)
end
--- In the watch: where the puller walks to hand the neutrals to our creeps (SETTINGS ShedMargin), else undefined. Starts once
-- a lane creep of ours near the watch attacks a neutral while a neutral attacks the puller; once started it follows the
-- neutrals that still attack the puller for ShedFor seconds, and otherwise returns where it last walked to, so the watch
-- stays out of the fight.
local function shedPoint(bot, pull)
    if not bot:IsAlive() then
        return nil
    end
    local now = DotaTime()
    if pull.shs ~= nil and now - pull.shs > ____exports.SETTINGS.ShedFor then
        return pull.shedTo
    end
    local at = bot:GetLocation()
    local cx = 0
    local cy = 0
    local k = 0
    local range = 0
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue61
            repeat
                if not u:IsAlive() or u:GetAttackTarget() ~= bot or GetUnitToUnitDistance(u, bot) > ____exports.SETTINGS.BailScan then
                    __continue61 = true
                    break
                end
                local l = u:GetLocation()
                if l == nil or l == nil then
                    __continue61 = true
                    break
                end
                cx = cx + l.x
                cy = cy + l.y
                k = k + 1
                range = math.max(
                    range,
                    u:GetAttackRange()
                )
                __continue61 = true
            until true
            if not __continue61 then
                break
            end
        end
    end
    if k == 0 then
        return pull.shedTo
    end
    if pull.shs == nil and not __TS__ArraySome(
        laneCreepsNear(
            pull.plan,
            LaneConfig.Settings().Radii.MeetWatch
        ),
        function(____, c) return onNeutral(c) end
    ) then
        return nil
    end
    cx = cx / k
    cy = cy / k
    local function unit(x, y)
        local l = math.sqrt(x * x + y * y)
        return l < 1 and ({0, 0, 0}) or ({x / l, y / l, l})
    end
    local ax, ay, al = unpack(unit(at.x - cx, at.y - cy))
    local tower = ourTower(bot)
    local tx, ty, tl = unpack(tower ~= nil and unit(tower.x - at.x, tower.y - at.y) or ({0, 0, 0}))
    local dx, dy, dl = unpack(unit(ax + tx, ay + ty))
    if dl < 0.5 then
        dx, dy, dl = unpack(al > 0 and ({ax, ay, 1}) or ({tx, ty, tl}))
    end
    if dl == 0 then
        return pull.shedTo
    end
    if pull.shs == nil then
        pull.shs = now
        pull.shh = bot:GetHealth() / math.max(
            1,
            bot:GetMaxHealth()
        )
    end
    local r = range + ____exports.SETTINGS.ShedMargin
    pull.shedTo = Vector(cx + dx * r, cy + dy * r, at.z)
    return pull.shedTo
end
--- The reading wants a pull: the clash is forecast beyond the lane's target point (`target`, from our T1) and is not coming
-- in. Lane aggro feeds on the same target and the wave hold meets their wave at it, so all three aim at one meeting point.
function ____exports.Wanted(r, target)
    if r == nil or r.state == "IN" then
        return false
    end
    return r.own + r.move > target + ____exports.SETTINGS.WantPast
end
--- Why the lane partner (a teammate core assigned to the lane) should not be left now, else undefined.
function ____exports.PartnerThreat(bot)
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue79
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot or not m:IsAlive() or isSupport(m) or m:GetAssignedLane() ~= lane then
                        __continue79 = true
                        break
                    end
                    local pids = {}
                    local n = 0
                    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
                        do
                            local __continue81
                            repeat
                                if not e:IsAlive() or e:IsIllusion() or GetUnitToUnitDistance(e, m) > ____exports.SETTINGS.PartnerRadius then
                                    __continue81 = true
                                    break
                                end
                                if pids[e:GetPlayerID()] ~= true then
                                    n = n + 1
                                end
                                pids[e:GetPlayerID()] = true
                                __continue81 = true
                            until true
                            if not __continue81 then
                                break
                            end
                        end
                    end
                    if n >= ____exports.SETTINGS.PartnerGank then
                        return "partner-gank"
                    end
                    if n > 0 and m:GetHealth() < m:GetMaxHealth() * ____exports.SETTINGS.PartnerHp then
                        return "partner-low"
                    end
                    __continue79 = true
                until true
                if not __continue79 then
                    break
                end
            end
            i = i + 1
        end
    end
    return nil
end
--- The nearest enemy hero to the pull site (stand or meet point) into `camp.se`; `enemy-site` within SiteEnemy.
local function siteThreat(p, camp)
    local near
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue88
            repeat
                if not e:IsAlive() or e:IsIllusion() then
                    __continue88 = true
                    break
                end
                local d = math.min(
                    GetUnitToLocationDistance(e, p.stand),
                    GetUnitToLocationDistance(e, p.meet)
                )
                if near == nil or d < near then
                    near = d
                end
                __continue88 = true
            until true
            if not __continue88 then
                break
            end
        end
    end
    camp.se = near
    return near ~= nil and near <= ____exports.SETTINGS.SiteEnemy and "enemy-site" or nil
end
--- OHA's own action holds the hero (rune_job's check: a queued TP, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
local function campFields(s)
    local function r0(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    return {
        {"cn", s.n},
        {"cs", s.seen},
        {
            "chp",
            r0(s.hp)
        },
        {"cv", s.vis and 1 or 0},
        {
            "cdmg",
            r0(s.dmg)
        },
        {
            "php",
            r0(s.php)
        },
        {
            "se",
            r0(s.se)
        }
    }
end
--- `slot` the plan's hit second (a half pull's, not the wave's `key`), so the line joins its `pull_job` line.
local function choiceLine(bot, d, slot, go, why, camp)
    local r = d.reading
    local function r1(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "pull"},
            {"go", go and 1 or 0},
            {"want", d.want and 1 or 0},
            {"why", why},
            {"src", "own"},
            {
                "lane",
                bot:GetAssignedLane()
            },
            {"slot", slot},
            {"st", r and r.state},
            {
                "q",
                r ~= nil and math.floor(r.q * 100 + 0.5) / 100 or nil
            },
            {
                "mv",
                r1(r and r.move)
            },
            {
                "own",
                r1(r and r.own)
            },
            {
                "tgt",
                LanePush.TargetOf(bot:GetAssignedLane())
            },
            {"tw", r ~= nil and (r.tower and 1 or 0) or nil},
            {"ms", r and r.ms},
            {"pk", d.want and d.kind or nil},
            {"hm", d.hm},
            unpack(campFields(camp))
        }
    )
end
local function jobLine(bot, p, phase, why)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "pull"},
            {"phase", phase},
            {"why", why},
            {"host", p.host},
            unpack(phase == "end" and ({{"hit", p.hit == true and 1 or 0}}) or ({}))
        }
    )
end
local function finish(bot, p, r, label)
    running[bot:GetPlayerID()] = nil
    local why = r.success and "ok" or r.reason .. (r.message ~= nil and ":" .. r.message or "")
    jobLine(bot, p, "end", why)
    local function r1(x)
        return math.floor(x * 10) / 10
    end
    local ____array_10 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {
            "pos",
            LaneConfig.PositionOf(bot)
        },
        {
            "lane",
            bot:GetAssignedLane()
        },
        {"camp", p.plan.camp.campIdx},
        {"slot", p.plan.slot},
        {"pk", p.plan.kind},
        {"res", r.success and "ok" or "fail"},
        {"why", why},
        {"label", label or p.label},
        {
            "div",
            share(p)
        },
        {"n", p.wave},
        {
            "left",
            r1(p.left)
        },
        {
            "away",
            r1(DotaTime() - p.left)
        },
        {
            "died",
            bot:IsAlive() and 0 or 1
        },
        {"hit", p.hit == true and 1 or 0},
        {"idle", p.idle},
        {
            "wd",
            p.near ~= nil and math.floor(p.near + 0.5) or nil
        },
        {"nn", p.neutrals},
        unpack(campFields(p.start))
    )
    __TS__SparseArrayPush(
        ____array_10,
        {
            "sh",
            math.floor((p.hitAt - p.plan.slot) * 10 + 0.5) / 10
        },
        {
            "s0",
            p.timer.first ~= nil and math.floor(p.timer.first * 10 + 0.5) / 10 or nil
        },
        {"lv", p.timer.reads},
        {"hr", p.timer.hit ~= nil and "geo" or "plan"},
        {"hc", p.timer.n},
        {"hn", p.timer.next},
        {"hb", p.timer.back},
        {"hf", p.timer.clear},
        {"hu", p.timer.turn},
        {"hm", p.timer.margin},
        {"hs", p.timer.standBack},
        {"hi", p.stepIn},
        {"ht", p.hat},
        {"g4", p.g4},
        {
            "gh",
            p.gh ~= nil and math.floor(p.gh + 0.5) or nil
        },
        {"na", p.na},
        {"gu", p.gu},
        {
            "gd",
            p.gd ~= nil and math.floor(p.gd + 0.5) or nil
        },
        {"wa", p.wa},
        {"nm", p.nm},
        {
            "shs",
            p.shs ~= nil and math.floor(p.shs * 10 + 0.5) / 10 or nil
        },
        {
            "shh",
            p.shh ~= nil and math.floor(p.shh * 100 + 0.5) / 100 or nil
        }
    )
    local fields = {__TS__SparseArraySpread(____array_10)}
    if not r.success then
        creepLines(bot, p)
        Telemetry.Event("pull_job", fields)
        return
    end
    local now = DotaTime()
    ended[bot:GetPlayerID()] = {camp = p.plan.camp.campIdx, at = now, pull = p}
    trailing[bot:GetPlayerID()] = {
        pull = p,
        fields = fields,
        ["until"] = math.max(
            now,
            PullTiming.WaveAt(p.timer) or now
        ) + ____exports.SETTINGS.TrailSec
    }
end
--- Samples a finished pull's wave until its trail ends, then writes its line with `dt`. A new pull's start writes it first.
local function trail(bot, flush)
    local pid = bot:GetPlayerID()
    local tr = trailing[pid]
    if tr == nil then
        return
    end
    if not flush and DotaTime() < tr["until"] then
        sampleWave(bot, tr.pull)
        watchLine(bot, tr.pull, "trail")
        return
    end
    trailing[pid] = nil
    creepLines(bot, tr.pull)
    local ____Telemetry_Event_12 = Telemetry.Event
    local ____array_11 = __TS__SparseArrayNew(unpack(tr.fields))
    __TS__SparseArrayPush(
        ____array_11,
        {
            "dt",
            share(tr.pull)
        }
    )
    ____Telemetry_Event_12(
        "pull_job",
        {__TS__SparseArraySpread(____array_11)}
    )
end
--- How far `at` is from `stand` towards the meet point (negative: back towards the camp).
local function stepped(p, stand, at)
    local dx = p.meet.x - stand.x
    local dy = p.meet.y - stand.y
    local l = math.max(
        1,
        math.sqrt(dx * dx + dy * dy)
    )
    return math.floor(((at.x - stand.x) * dx + (at.y - stand.y) * dy) / l + 0.5)
end
--- During lead and watch: our wave's largest diverted share (camp_jobs' sample: the wave is counted once the first of it
-- is seen on a neutral).
local function sample(bot, p)
    if p.label ~= "lead" and p.label ~= "watch" then
        return
    end
    watchLine(bot, p, p.label)
    diag(bot, p, trackCreeps)
    local now = DotaTime()
    if p.sampledAt ~= nil and now - p.sampledAt < ____exports.SETTINGS.WatchEvery then
        return
    end
    p.sampledAt = now
    local radii = LaneConfig.Settings().Radii
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue142
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue142 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, p.plan.meet)
                if p.near == nil or d < p.near then
                    p.near = d
                end
                __continue142 = true
            until true
            if not __continue142 then
                break
            end
        end
    end
    local nn = 0
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        if u:IsAlive() and GetUnitToLocationDistance(u, p.plan.meet) <= radii.MeetWatch then
            nn = nn + 1
        end
    end
    p.neutrals = math.max(p.neutrals, nn)
    countDiverted(p)
    diag(bot, p, trackTagged)
end
--- At the hit: the camp's neutrals (in its box, or on the puller within TagRadius), so the watch follows that camp only.
local function tagCamp(bot, p)
    p.hat = DotaTime()
    local tagged = ____exports.CampStateOf(p.plan.spawner).units
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue154
            repeat
                if not u:IsAlive() or __TS__ArrayIndexOf(tagged, u) >= 0 or GetUnitToUnitDistance(u, bot) > ____exports.SETTINGS.TagRadius then
                    __continue154 = true
                    break
                end
                if u:GetAttackTarget() == bot then
                    tagged[#tagged + 1] = u
                end
                __continue154 = true
            until true
            if not __continue154 then
                break
            end
        end
    end
    p.tagged = tagged
    p.peaks = __TS__New(Map)
    p.starts = __TS__New(Map)
    for ____, u in ipairs(tagged) do
        local l = u:GetLocation()
        if l ~= nil and l ~= nil then
            p.starts:set(u, l)
        end
    end
    p.early = {}
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        if c:IsAlive() and LanePush.IsLaneCreep(c:GetUnitName()) and GetUnitToLocationDistance(c, p.plan.meet) <= ____exports.SETTINGS.ArriveR then
            local ____p_early_13 = p.early
            ____p_early_13[#____p_early_13 + 1] = c
        end
    end
end
local function verbCamp(p)
    local radii = LaneConfig.Settings().Radii
    local o = p.spawner.location
    local d = math.sqrt((p.stand.x - o.x) ^ 2 + (p.stand.y - o.y) ^ 2)
    local approach = d > radii.StandApproach + radii.JobArrive and Vector(o.x + (p.stand.x - o.x) * radii.StandApproach / d, o.y + (p.stand.y - o.y) * radii.StandApproach / d, o.z) or nil
    return {
        stand = p.stand,
        approach = approach,
        box = {min = p.spawner.min, max = p.spawner.max},
        origin = o,
        margin = radii.BoxMargin,
        search = radii.NeutralSearch
    }
end
local function verbPlan(bot, pull, aggroAt)
    local p = pull.plan
    local s = LaneConfig.Settings()
    local camp = verbCamp(p)
    local lead = {unpack(p.lead)}
    local stepIn = pull.timer.keep > 0 and s.PullTiming.HalfStepIn == true
    if stepIn and #lead > 0 then
        lead[#lead] = PullTiming.StepBackPoint(p.spawner.location, pull.timer.stand or p.meet, p.timing.lanePath)
    end
    camp.earlier = function()
        pull.hitAt = PullTiming.Read(
            pull.timer,
            DotaTime()
        )
        if pull.timer.stand ~= nil and #lead > 0 then
            lead[#lead] = stepIn and PullTiming.StepBackPoint(p.spawner.location, pull.timer.stand, p.timing.lanePath) or pull.timer.stand
        end
        return aggroAt - pull.hitAt
    end
    local stepAt = stepIn and (function()
        local ____end = pull.timer.stand or p.meet
        local engaged = __TS__ArraySome(
            laneCreepsNear(p, s.Radii.MeetWatch),
            function(____, c) return onNeutral(c) end
        )
        local here = bot:GetLocation()
        local offs = {}
        local ranged = false
        for ____, u in ipairs(pull.tagged or ({})) do
            do
                local __continue237
                repeat
                    if stale(u) then
                        __continue237 = true
                        break
                    end
                    local l = u:GetLocation()
                    if l == nil or l == nil then
                        __continue237 = true
                        break
                    end
                    offs[#offs + 1] = Vector(l.x - here.x, l.y - here.y, 0)
                    if u:GetAttackRange() >= s.PullTiming.HalfRangedFrom then
                        ranged = true
                    end
                    __continue237 = true
                until true
                if not __continue237 then
                    break
                end
            end
        end
        local byNeutrals = s.PullTiming.HalfStepNeutrals == true
        local at = PullTiming.StepIn(
            pull.timer,
            p.spawner.location,
            ____end,
            p.meet,
            DotaTime(),
            engaged,
            here,
            byNeutrals and offs or nil,
            byNeutrals and ranged
        )
        if engaged and pull.stepIn == nil then
            local path = p.timing.lanePath
            pull.stepIn = path ~= nil and math.floor(select(
                2,
                PullTiming.Along(path, here)
            ) + 0.5) or stepped(p, ____end, here)
        end
        return at
    end) or nil
    return {
        bail = function() return bailPoint(bot) end,
        bailFor = ____exports.SETTINGS.BailFor,
        camp = camp,
        aggroAt = aggroAt,
        lead = lead,
        watchAt = function()
            local step = stepAt and stepAt()
            local shed = shedPoint(bot, pull)
            return shed or step
        end,
        watchSec = s.Timing.WatchSec,
        watchUntil = function()
            local w = PullTiming.WaveAt(pull.timer)
            return w ~= nil and w + s.PullTiming.WatchAfterWave or nil
        end,
        leadDeadline = aggroAt + s.Timing.JobMaxAfterAggro,
        arrive = s.Radii.JobArrive,
        startLate = s.Timing.JobStartLate,
        approachLead = s.Timing.StandApproachLead,
        noCampAfter = s.Timing.NoCampAfter,
        confirmFor = s.Timing.AggroConfirm
    }
end
local body = __TS__Generator(function(bot, p, aggroAt, ctx)
    local hooks = {
        label = function(l)
            ctx.label(l)
            p.label = l
            if l == "lead" and p.hat == nil then
                diag(bot, p, tagCamp)
            end
        end,
        urgent = ctx.urgent
    }
    return __TS__DelegatedYield(Tasks.Jobs().pull(
        bot,
        verbPlan(bot, p, aggroAt),
        hooks
    ))
end)
--- Every frame while the chooser asks: true while a pull runs or as one starts. The lane is read once per slot at the leave
-- time; a wanted pull then waits for `blocked` (the chooser's checks, a higher job's claim), the partner check and OHA's own
-- action until it could no longer reach the camp by the hit's late limit.
function ____exports.Wants(bot, blocked, host)
    if not ____exports.Applies(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    trail(bot, false)
    if Tasks.Jobs() == nil or not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return false
    end
    local now = DotaTime()
    local full = planFor(bot, now, "full")
    if full == nil or handled[pid] == full.key then
        return false
    end
    local ____opt_23 = decided[pid]
    local kind = (____opt_23 and ____opt_23.slot) == full.key and decided[pid].kind or "full"
    local ____temp_25
    if kind == "half" then
        ____temp_25 = planFor(bot, now, "half")
    else
        ____temp_25 = nil
    end
    local half = ____temp_25
    if kind == "half" and half == nil and decided[pid] ~= nil then
        decided[pid].kind = "full"
    end
    local p = half or full
    local walk = travel(bot, p)
    local timer = timers[pid]
    if timer == nil or timer.slot ~= p.slot then
        local cfg = LaneConfig.Settings().PullTiming
        timer = p.kind == "half" and PullTiming.Timer(
            p.timing,
            p.slot,
            1,
            cfg.HalfClear,
            2,
            bot:GetCurrentMovementSpeed()
        ) or PullTiming.Timer(p.timing, p.slot, 0, cfg.FullPast)
        timers[pid] = timer
    end
    local hitAt = PullTiming.Read(timer, now)
    if now < hitAt - walk - ____exports.SETTINGS.Early then
        return false
    end
    local d = decided[pid]
    if d == nil or d.slot ~= p.key then
        local reading = LanePush.Read(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )
        local harness = LaneConfig.Settings().PullTiming.HalfAll == true and ____exports.KindFor(bot, reading) == "half"
        local want = ____exports.Wanted(
            reading,
            LanePush.TargetOf(bot:GetAssignedLane())
        ) or harness
        d = {
            slot = p.key,
            want = want,
            kind = want and ____exports.KindFor(bot, reading) or "full",
            reading = reading
        }
        decided[pid] = d
        gateWhy[pid] = nil
        if d.kind == "half" then
            return false
        end
    end
    local camp = ____exports.CampStateOf(p.spawner)
    local function done(go, why)
        handled[pid] = p.key
        gateWhy[pid] = nil
        choiceLine(
            bot,
            d,
            p.slot,
            go,
            why,
            camp
        )
    end
    if not d.want then
        done(false, d.reading == nil and "no-read" or "lane")
        return false
    end
    if d.kind == "half" and timer.margin ~= nil and timer.margin <= 0 then
        d.hm = timer.margin
        done(false, "half-geo")
        return false
    end
    camp.dmg = ____exports.CampDamage(bot, camp, p.spawner.type)
    camp.php = bot:GetHealth()
    local site = siteThreat(p, camp)
    local why = ____exports.CampGate(camp, now, hitAt) or blocked(bot) or campDmgGate(bot, camp.dmg) or site or ____exports.PartnerThreat(bot) or (acting(bot) and "acting" or nil)
    if now + walk > hitAt + LaneConfig.Settings().Timing.JobStartLate then
        done(false, gateWhy[pid] or why or "late")
        return false
    end
    if why ~= nil then
        gateWhy[pid] = why
        return false
    end
    local aggroAt = hitAt
    trail(bot, true)
    local pull = {
        plan = p,
        left = now,
        host = host,
        wave = 0,
        peak = 0,
        neutrals = 0,
        hitAt = hitAt,
        timer = timer,
        start = camp
    }
    local ok = Tasks.Start(
        bot,
        {
            name = "pull",
            host = host,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(r, info) return finish(bot, pull, r, info.label) end
        },
        function(ctx) return body(bot, pull, aggroAt, ctx) end
    )
    if not ok then
        done(false, "refused")
        return false
    end
    done(true, nil)
    running[pid] = pull
    jobLine(bot, pull, "start", "trigger")
    return true
end
function ____exports.Step(bot, host)
    local p = running[bot:GetPlayerID()]
    if p == nil then
        return false
    end
    if p.label == nil or p.label == "travel" or p.label == "wait" then
        local s = ____exports.CampStateOf(p.plan.spawner)
        s.dmg = ____exports.CampDamage(bot, s, p.plan.spawner.type)
        s.php = bot:GetHealth()
        local why = ____exports.CampGate(
            s,
            DotaTime(),
            p.hitAt
        ) or campDmgGate(bot, s.dmg)
        if why ~= nil then
            p.start = s
            ____exports.End(bot, why)
            return false
        end
    end
    sample(bot, p)
    return Tasks.Step(bot, host)
end
--- The bot's last ok pull: its camp index, end time and the wave's diverted share (still growing for TrailSec after the end).
function ____exports.Finished(bot)
    local e = ended[bot:GetPlayerID()]
    return e ~= nil and ({
        camp = e.camp,
        at = e.at,
        div = share(e.pull)
    }) or nil
end
function ____exports.NoteHit(bot)
    local p = running[bot:GetPlayerID()]
    if p ~= nil then
        p.hit = true
    end
end
function ____exports.NoteIdleHeld(bot)
    local p = running[bot:GetPlayerID()]
    if p ~= nil then
        p.idle = (p.idle or 0) + 1
    end
end
return ____exports
