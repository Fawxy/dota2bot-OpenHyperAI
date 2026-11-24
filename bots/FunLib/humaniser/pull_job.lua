--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
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

local function __TS__StringStartsWith(self, searchString, position)
    if position == nil or position < 0 then
        position = 0
    end
    return string.sub(self, position + 1, #searchString + position) == searchString
end

local function __TS__StringSubstring(self, start, ____end)
    if ____end ~= ____end then
        ____end = 0
    end
    if ____end ~= nil and start > ____end then
        start, ____end = ____end, start
    end
    if start >= 0 then
        start = start + 1
    else
        start = 1
    end
    if ____end ~= nil and ____end < 0 then
        ____end = 0
    end
    return string.sub(self, start, ____end)
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
local campFor, alive, recordCount, advance, recordOf, readsHit, campDmgGate, ourTower, share, laneCreepsNear, onNeutral, sample, sampleWave, diag, stale, taggedState, trackTagged, countDiverted, targetKind, watchLine, taggedFields, behindOurs, watch, logSeeds, Step, End, running, records, watchedAt, RECORD_LEASH, HOST, seedsLogged
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local JobVerbs = require(GetScriptDirectory().."/FunLib/humaniser/job_verbs")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
function campFor(bot)
    local lane = bot:GetAssignedLane()
    if lane ~= Lane.Top and lane ~= Lane.Bot then
        return nil
    end
    local camps = Camps.PullCampsFor(
        bot:GetTeam(),
        lane
    )
    local kind = Overrides.Get("PullCamp")
    if type(kind) == "string" and kind ~= "" then
        return __TS__ArrayFind(
            camps,
            function(____, c) return c.type == kind end
        )
    end
    return camps[1]
end
function ____exports.CampStateOf(spawner)
    local m = LaneConfig.Settings().Radii.BoxMargin
    local lo = spawner.min
    local hi = spawner.max
    local z = spawner.location.z
    local x0, y0, x1, y1 = lo.x - m, lo.y - m, hi.x + m, hi.y + m
    local full = IsLocationVisible(Vector(x0, y0, z)) and IsLocationVisible(Vector(x1, y0, z)) and IsLocationVisible(Vector(x0, y1, z)) and IsLocationVisible(Vector(x1, y1, z))
    local s = {
        n = 0,
        seen = 0,
        hp = 0,
        vis = IsLocationVisible(spawner.location),
        full = full,
        units = {}
    }
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue30
            repeat
                if not u:IsAlive() then
                    __continue30 = true
                    break
                end
                local p = u:GetLocation()
                if p == nil or p == nil then
                    __continue30 = true
                    break
                end
                if p.x < lo.x - m or p.x > hi.x + m or p.y < lo.y - m or p.y > hi.y + m then
                    __continue30 = true
                    break
                end
                s.n = s.n + 1
                if u:CanBeSeen() then
                    s.seen = s.seen + 1
                end
                s.hp = s.hp + u:GetHealth()
                local ____s_units_1 = s.units
                ____s_units_1[#____s_units_1 + 1] = u
                __continue30 = true
            until true
            if not __continue30 then
                break
            end
        end
    end
    return s
end
function alive(u)
    return not u:IsNull() and u:IsAlive()
end
function recordCount(r)
    local n = r.added
    for ____, u in ipairs(r.units) do
        if alive(u) then
            n = n + 1
        end
    end
    return n
end
function advance(r, ____type, now)
    local m = math.floor(now / GameRules.NEUTRAL_EVERY)
    while r.minute < m do
        r.minute = r.minute + 1
        if r.minute * GameRules.NEUTRAL_EVERY >= GameRules.NEUTRAL_FIRST and recordCount(r) == 0 then
            r.added = r.added + ____exports.SETTINGS.SetSize[____type]
            r.src = "rules"
        end
    end
end
function recordOf(spawner, now)
    local r = records[spawner.idx]
    if r == nil then
        r = {
            units = {},
            added = 0,
            seenAt = now,
            src = "rules",
            minute = math.floor(now / GameRules.NEUTRAL_EVERY)
        }
        if now >= GameRules.NEUTRAL_FIRST then
            r.added = ____exports.SETTINGS.SetSize[spawner.type]
        end
        records[spawner.idx] = r
    end
    advance(r, spawner.type, now)
    return r
end
--- A look at the camp (`s`, CampStateOf now). A full view (the box's corners in sight, or `close`: one of ours stands at the
-- camp, since the corners never all read visible in the drills, ldr11) replaces the record; a partial one only raises it,
-- since a neutral out of view would drop a strong camp under the bar. An unseen origin says nothing (the API returns no
-- fogged neutrals).
function ____exports.NoteSighting(spawner, s, close)
    if not s.vis then
        return
    end
    local now = DotaTime()
    local r = recordOf(spawner, now)
    if r.heldUntil ~= nil and now < r.heldUntil then
        return
    end
    if not (s.full == true or close) and s.n <= recordCount(r) then
        return
    end
    local units = {unpack(s.units)}
    for ____, u in ipairs(r.units) do
        do
            local __continue51
            repeat
                if not alive(u) or not u:CanBeSeen() or __TS__ArrayIncludes(units, u) or GetUnitToLocationDistance(u, spawner.location) > RECORD_LEASH then
                    __continue51 = true
                    break
                end
                units[#units + 1] = u
                __continue51 = true
            until true
            if not __continue51 then
                break
            end
        end
    end
    r.units = units
    r.added = 0
    r.seenAt = now
    r.src = "seen"
end
--- The camp's strength as this hero knows it now (CampRecord).
function ____exports.Known(spawner)
    local now = DotaTime()
    local r = recordOf(spawner, now)
    local n = recordCount(r)
    return {
        n = n,
        src = r.src,
        age = math.floor((now - r.seenAt) * 10) / 10,
        held = n - r.added
    }
end
--- `empty` when the camp holds nothing to pull at `hitAt`: nothing returned while the team sees the camp's origin, and no
-- spawn minute before the hit (a camp respawns only on the minute, so it stays empty). An empty box out of sight says
-- nothing: the API returns no fogged neutrals (pc1: every one returned was `CanBeSeen`). `one` the same with a single
-- neutral left: too little to hold a wave (banked `ok` pulls with one neutral seen at the start diverted 26 of 56, two or
-- more 243 of 385; user 04/11/2026: skip it). Stacking it instead is the stack job's call, not this one's.
function ____exports.CampGate(s, now, hitAt)
    if not readsHit(s, now, hitAt) then
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
function readsHit(s, now, hitAt)
    local period = LaneConfig.Settings().Timing.PullPeriod
    return s.vis and math.floor(hitAt / period) <= math.floor(now / period)
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
function campDmgGate(bot, dmg)
    return bot:GetHealth() - dmg < bot:GetMaxHealth() * ____exports.SETTINGS.StartReserve and "camp-dmg" or nil
end
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
--- The wave a slot pulls: ours spawned on the last 30 s at or before the slot (aggro comes after the spawn).
function ____exports.PulledSpawn(slot)
    return math.floor((slot - 1) / GameRules.WAVE_EVERY) * GameRules.WAVE_EVERY
end
function share(p)
    return p.wave > 0 and math.floor(p.peak / p.wave * 100 + 0.5) / 100 or 0
end
function laneCreepsNear(p, radius)
    local out = {}
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue123
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue123 = true
                    break
                end
                if GetUnitToLocationDistance(c, p.meet) <= radius or GetUnitToLocationDistance(c, p.spawner.location) <= radius then
                    out[#out + 1] = c
                end
                __continue123 = true
            until true
            if not __continue123 then
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
function sample(bot, p)
    if p.label ~= "lead" and p.label ~= "watch" then
        return
    end
    watchLine(bot, p, p.label)
    local now = DotaTime()
    if p.sampledAt ~= nil and now - p.sampledAt < ____exports.SETTINGS.WatchEvery then
        return
    end
    p.sampledAt = now
    local radii = LaneConfig.Settings().Radii
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue131
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue131 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, p.plan.meet)
                if p.near == nil or d < p.near then
                    p.near = d
                end
                __continue131 = true
            until true
            if not __continue131 then
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
function sampleWave(bot, p)
    local now = DotaTime()
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
            local __continue155
            repeat
                if stale(u) then
                    __continue155 = true
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
                __continue155 = true
            until true
            if not __continue155 then
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
                local __continue166
                repeat
                    if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) or __TS__ArrayIndexOf(p.early, c) >= 0 then
                        __continue166 = true
                        break
                    end
                    if GetUnitToLocationDistance(c, p.plan.meet) <= ____exports.SETTINGS.ArriveR then
                        p.wa = now
                        break
                    end
                    __continue166 = true
                until true
                if not __continue166 then
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
            local __continue173
            repeat
                if stale(u) then
                    __continue173 = true
                    break
                end
                local ____opt_40 = p.starts
                local s0 = ____opt_40 and ____opt_40:get(u)
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
                    __continue173 = true
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
                __continue173 = true
            until true
            if not __continue173 then
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
            local __continue194
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue194 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, meet)
                if wd == nil or d < wd then
                    wd = d
                end
                __continue194 = true
            until true
            if not __continue194 then
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
            local __continue204
            repeat
                if not u:IsAlive() then
                    __continue204 = true
                    break
                end
                local d = GetUnitToLocationDistance(u, meet)
                if d > ____exports.SETTINGS.WatchNeutralSearch then
                    __continue204 = true
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
                __continue204 = true
            until true
            if not __continue204 then
                break
            end
        end
    end
    local function r0(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    local ____Telemetry_Event_46 = Telemetry.Event
    local ____array_45 = __TS__SparseArrayNew(
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
    local ____temp_42
    if best ~= nil then
        ____temp_42 = r0(nd)
    else
        ____temp_42 = nil
    end
    __TS__SparseArrayPush(____array_45, {"nd", ____temp_42})
    local ____temp_43
    if best ~= nil then
        ____temp_43 = r0(GetUnitToLocationDistance(best, p.plan.spawner.location))
    else
        ____temp_43 = nil
    end
    __TS__SparseArrayPush(
        ____array_45,
        {"nh", ____temp_43},
        {
            "nt",
            best ~= nil and targetKind(
                bot,
                best:GetAttackTarget()
            ) or nil
        }
    )
    local ____bot_IsAlive_result_44
    if bot:IsAlive() then
        ____bot_IsAlive_result_44 = r0(GetUnitToLocationDistance(bot, meet))
    else
        ____bot_IsAlive_result_44 = nil
    end
    __TS__SparseArrayPush(
        ____array_45,
        {"pd", ____bot_IsAlive_result_44},
        {"shd", p.shs ~= nil and 1 or nil},
        unpack(taggedFields(bot, p, ours))
    )
    ____Telemetry_Event_46(
        "pull_watch",
        {__TS__SparseArraySpread(____array_45)}
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
function behindOurs(bot, pull)
    local ours = laneCreepsNear(
        pull.plan,
        LaneConfig.Settings().Radii.MeetWatch
    )
    if not __TS__ArraySome(
        ours,
        function(____, c) return onNeutral(c) end
    ) then
        return nil
    end
    local neutrals = {}
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        if u:IsAlive() and GetUnitToLocationDistance(u, pull.plan.spawner.location) <= LaneConfig.Settings().Radii.MeetWatch then
            neutrals[#neutrals + 1] = u
        end
    end
    return JobVerbs.behindPoint(bot, ours, neutrals, pull.plan.spawner.location)
end
function watch(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    if running[pid] ~= nil or now - (watchedAt[pid] or -math.huge) < ____exports.SETTINGS.RecordEvery then
        return
    end
    watchedAt[pid] = now
    local sp = ____exports.SpawnerFor(bot)
    if sp == nil then
        return
    end
    ____exports.NoteSighting(
        sp,
        ____exports.CampStateOf(sp),
        bot:IsAlive() and GetUnitToLocationDistance(bot, sp.location) <= ____exports.SETTINGS.CampReadNear
    )
end
--- The spawner of the lane's pull camp (the pull's and the stack row's camp).
function ____exports.SpawnerFor(bot)
    local camp = campFor(bot)
    local ____temp_50
    if camp ~= nil then
        ____temp_50 = Camps.SpawnerByIdx(camp.campIdx)
    else
        ____temp_50 = nil
    end
    return ____temp_50
end
function logSeeds()
    if seedsLogged or not Telemetry.IsEnabled() then
        return
    end
    local reads = Camps.SeedReads()
    if #reads == 0 then
        return
    end
    seedsLogged = true
    for ____, r in ipairs(reads) do
        Telemetry.Event("pull_camp_seed", {
            {"key", r.key},
            {"idx", r.idx},
            {"td", r.td},
            {"ld", r.ld},
            {"ok", r.ok and 1 or 0}
        })
    end
end
function Step(bot)
    local p = running[bot:GetPlayerID()]
    if p == nil then
        return false
    end
    if p.label == nil or p.label == "travel" or p.label == "wait" then
        local s = ____exports.CampStateOf(p.plan.spawner)
        s.dmg = ____exports.CampDamage(bot, s, p.plan.spawner.type)
        s.php = bot:GetHealth()
        local now = DotaTime()
        local close = GetUnitToLocationDistance(bot, p.plan.stand) <= ____exports.SETTINGS.CampReadNear
        ____exports.NoteSighting(p.plan.spawner, s, close)
        local gate = ____exports.CampGate(s, now, p.hitAt) or (readsHit(s, now, p.hitAt) and ____exports.Known(p.plan.spawner).n < ____exports.SETTINGS.StrongAt and "weak" or nil)
        if gate == nil or not close then
            p.low = nil
        elseif p.low == nil or p.low.why ~= gate then
            p.low = {why = gate, at = now}
        end
        local hold = math.min(____exports.SETTINGS.CampLowHold, p.hitAt - now)
        local why = p.low ~= nil and now - p.low.at >= hold and p.low.why or nil or campDmgGate(bot, s.dmg)
        if why ~= nil then
            p.start = s
            End(bot, why)
            return false
        end
    end
    sample(bot, p)
    return Tasks.Step(bot, HOST)
end
function End(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
--- Telemetry only (`hit` on the pull's lines): a hero damaged the puller within this many seconds.
local HERO_HIT_WITHIN = 3
____exports.SETTINGS = {
    CampLowHold = 1.5,
    CampReadNear = 500,
    Early = 2,
    PathFactor = 1.2,
    WantPast = 150,
    ArriveAfter = 12,
    PowerRatio = 1.2,
    WatchEvery = 0.25,
    TrailSec = 10,
    StayMax = 35,
    WatchLogEvery = 1,
    WatchNeutralSearch = 3000,
    TagRadius = 1200,
    Acquire = 500,
    ArriveR = 300,
    Left = 400,
    HomeMargin = 150,
    Moved = 50,
    HitSeconds = 1.5,
    StartReserve = 0.25,
    DefaultDps = {small = 40, medium = 60, large = 80, ancient = 150},
    BailReserve = 0.25,
    BailGrace = 2,
    BailFor = 6,
    BailScan = 1200,
    BailStep = 700,
    ShedMargin = 300,
    ShedFor = 5,
    StrongAt = 6,
    SetSize = {small = 3, medium = 3, large = 3, ancient = 3},
    RecordEvery = 0.5
}
running = {}
local trailing = {}
local handled = {}
local decided = {}
local timers = {}
local gateWhy = {}
records = {}
watchedAt = {}
function ____exports.ResetCache()
    for ____, t in ipairs({
        running,
        trailing,
        handled,
        decided,
        gateWhy,
        timers,
        records,
        watchedAt
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
--- The hero that would pull for its lane, whatever the switches say.
function ____exports.IsPuller(bot)
    return bot:IsBot() and TripTable.Does(
        "pull",
        LaneConfig.PositionOf(bot)
    ) and isSupport(bot) and pullerOfLane(bot) and campFor(bot) ~= nil
end
--- The row is switched on for this lane's puller (Ours.Team scopes it, so the other team's puller is shadowed). A hero a drill
-- benches or stands as a statue is the drill's: the chooser never asked its jobs, and the row is not asked either.
local function rowOn(bot)
    return Ours.On("SupportPull") and ____exports.IsPuller(bot) and not Drill.Held(bot)
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
--- The next wave's pull: its hit second from the wave plan (pull_timing), stand, lead and meet point.
local function planFor(bot, now)
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
    local timing = PullTiming.ForCamp(camp)
    if #timing.seconds == 0 then
        return nil
    end
    local slot = ____exports.NextSlot(now - t.JobStartLate, timing.seconds, t.PullPeriod)
    if math.floor(slot / t.PullPeriod) * t.PullPeriod < t.NeutralFirstSpawn then
        return nil
    end
    local meet = camp.pull.meetPoint
    local lead = PullTiming.LeadPath(camp.pull, meet)
    local stand = Camps.StandPoint(
        spawner,
        lead[1],
        LaneConfig.Settings().Radii.StandOffset
    )
    return {
        camp = camp,
        spawner = spawner,
        stand = stand,
        lead = lead,
        meet = meet,
        timing = timing,
        slot = slot
    }
end
local function travel(bot, p)
    return GetUnitToLocationDistance(bot, p.stand) * ____exports.SETTINGS.PathFactor / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
RECORD_LEASH = 1200
--- The stack row's read of its camp after the mark: the set it pulled out (`pulled`, the handles at its hit) and the spawn it
-- saw come in (`fresh`), or a set by the rules when the box was out of sight (`fresh` undefined). It replaces the record:
-- the row held it through the stack (Hold), since no look at the box counts a pulled-out set.
function ____exports.NoteStack(spawner, pulled, fresh)
    local now = DotaTime()
    local r = recordOf(spawner, now)
    r.units = __TS__ArrayFilter(
        pulled,
        function(____, u) return alive(u) end
    )
    r.added = fresh or ____exports.SETTINGS.SetSize[spawner.type]
    r.src = fresh ~= nil and "seen" or "rules"
    if fresh ~= nil then
        r.seenAt = now
    end
    r.heldUntil = nil
end
--- No look updates the record until `until` (or NoteStack): a stack is pulling the camp out of its box.
function ____exports.Hold(spawner, ____until)
    recordOf(
        spawner,
        DotaTime()
    ).heldUntil = ____until
end
--- The camp holds at least the bar's neutrals (SETTINGS.StrongAt) on this hero's record.
function ____exports.Strong(spawner)
    return ____exports.Known(spawner).n >= ____exports.SETTINGS.StrongAt
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
            local __continue72
            repeat
                if not u:IsAlive() or u:GetAttackTarget() ~= bot or GetUnitToUnitDistance(u, bot) > ____exports.SETTINGS.BailScan then
                    __continue72 = true
                    break
                end
                local l = u:GetLocation()
                if l == nil or l == nil then
                    __continue72 = true
                    break
                end
                dps = dps + u:GetEstimatedDamageToTarget(true, bot, 1, DamageType.All)
                cx = cx + l.x
                cy = cy + l.y
                k = k + 1
                __continue72 = true
            until true
            if not __continue72 then
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
            local __continue82
            repeat
                if not u:IsAlive() or u:GetAttackTarget() ~= bot or GetUnitToUnitDistance(u, bot) > ____exports.SETTINGS.BailScan then
                    __continue82 = true
                    break
                end
                local l = u:GetLocation()
                if l == nil or l == nil then
                    __continue82 = true
                    break
                end
                cx = cx + l.x
                cy = cy + l.y
                k = k + 1
                range = math.max(
                    range,
                    u:GetAttackRange()
                )
                __continue82 = true
            until true
            if not __continue82 then
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
function ____exports.Wanted(g, target)
    if g == nil or g.own == nil then
        return false
    end
    return g.own > target + ____exports.SETTINGS.WantPast and g.ep <= ____exports.SETTINGS.PowerRatio * g.ap
end
--- Two slots pull the same wave. A slot is a float from the camp's timing, which is re-read at every timing read since the
-- neutral speed is (neutral-speed-at-order), so the same slot drifts by a fraction of a second between frames; comparing the
-- floats restarted a cancelled pull on its own slot (lctl9: 11 duplicate pull_job lines in 5 games, none in lctl4). Keyed by
-- the pulled wave instead.
function ____exports.SameWave(a, b)
    return a ~= nil and ____exports.PulledSpawn(a) == ____exports.PulledSpawn(b)
end
--- The nearest enemy hero to the pull site (stand or meet point), logged as `se`: no gate reads it.
local function siteEnemy(p)
    local near
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue102
            repeat
                if not e:IsAlive() or e:IsIllusion() then
                    __continue102 = true
                    break
                end
                local d = math.min(
                    GetUnitToLocationDistance(e, p.stand),
                    GetUnitToLocationDistance(e, p.meet)
                )
                if near == nil or d < near then
                    near = d
                end
                __continue102 = true
            until true
            if not __continue102 then
                break
            end
        end
    end
    return near
end
--- OHA's own action holds the hero (rune_job's check: a queued TP, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
local function campFields(s)
    local function r0(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    local ____array_11 = __TS__SparseArrayNew(
        {"cn", s.n},
        {"cs", s.seen},
        {
            "chp",
            r0(s.hp)
        },
        {"cv", s.vis and 1 or 0}
    )
    local ____temp_2
    if s.full == nil then
        ____temp_2 = nil
    else
        ____temp_2 = s.full and 1 or 0
    end
    __TS__SparseArrayPush(
        ____array_11,
        {"cfv", ____temp_2},
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
    )
    local ____opt_3 = s.known
    __TS__SparseArrayPush(____array_11, {"rn", ____opt_3 and ____opt_3.n})
    local ____opt_5 = s.known
    __TS__SparseArrayPush(____array_11, {"rsrc", ____opt_5 and ____opt_5.src})
    local ____opt_7 = s.known
    __TS__SparseArrayPush(____array_11, {"rage", ____opt_7 and ____opt_7.age})
    local ____opt_9 = s.known
    __TS__SparseArrayPush(____array_11, {"rh", ____opt_9 and ____opt_9.held})
    return {__TS__SparseArraySpread(____array_11)}
end
--- `slot` the plan's hit second, so the line joins its `pull_job` line.
local function choiceLine(bot, d, slot, go, why, camp, src)
    if src == nil then
        src = "own"
    end
    local r = d.reading
    local function r1(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    local ____Telemetry_Event_29 = Telemetry.Event
    local ____array_28 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "pull"},
        {"go", go and 1 or 0},
        {"want", d.want and 1 or 0},
        {"why", why},
        {"src", src},
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
        {"tw", r ~= nil and (r.tower and 1 or 0) or nil}
    )
    local ____opt_18 = d.gone
    __TS__SparseArrayPush(
        ____array_28,
        {
            "pa",
            r1(____opt_18 and ____opt_18.own)
        }
    )
    local ____opt_20 = d.gone
    __TS__SparseArrayPush(
        ____array_28,
        {
            "ap",
            r1(____opt_20 and ____opt_20.ap)
        }
    )
    local ____opt_22 = d.gone
    __TS__SparseArrayPush(
        ____array_28,
        {
            "ep",
            r1(____opt_22 and ____opt_22.ep)
        }
    )
    local ____opt_24 = d.gone
    __TS__SparseArrayPush(
        ____array_28,
        {"pw", ____opt_24 and ____opt_24.pw},
        {"rule", d.rule},
        {"ms", r and r.ms},
        unpack(campFields(camp))
    )
    ____Telemetry_Event_29(
        "choice",
        {__TS__SparseArraySpread(____array_28)}
    )
end
local function jobLine(bot, p, phase, why, cut)
    local ____Telemetry_Event_31 = Telemetry.Event
    local ____array_30 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"job", "pull"},
        {"phase", phase},
        {"why", why},
        {"host", p.host},
        unpack(phase == "end" and ({{"hit", p.hit == true and 1 or 0}}) or ({}))
    )
    __TS__SparseArrayPush(
        ____array_30,
        {"cut", cut},
        {
            "hp",
            cut == "retreat" and math.floor(bot:GetHealth() / math.max(
                1,
                bot:GetMaxHealth()
            ) * 100 + 0.5) / 100 or nil
        }
    )
    ____Telemetry_Event_31(
        "job",
        {__TS__SparseArraySpread(____array_30)}
    )
end
--- Plan s4 step 8: the decider does not tell a row it was cut off, so a pull the engine ends because the host mode lost the
-- hero names what took it: `retreat` when the decider let go for stock's retreat or the retreat mode holds the hero (OHA's
-- latch outbids the hold), else the mode that does.
local function cutBy(bot, r)
    if r.success or r.reason ~= "preempted" then
        return nil
    end
    if Decider.LetGo(bot) or bot:GetActiveMode() == BotMode.Retreat then
        return "retreat"
    end
    return HDebug.ModeName(bot:GetActiveMode())
end
local function finish(bot, p, ____end, label)
    running[bot:GetPlayerID()] = nil
    local endWhy = ____end.success and (____end.message or "ok") or ____end.reason .. (____end.message ~= nil and ":" .. ____end.message or "")
    local r = p.stayAt ~= nil and ({success = true, reason = "ok"}) or ____end
    local why = r.success and "ok" or endWhy
    local cut = cutBy(bot, ____end)
    local ____jobLine_35 = jobLine
    local ____bot_33 = bot
    local ____p_34 = p
    local ____temp_32
    if p.stayAt ~= nil then
        ____temp_32 = nil
    else
        ____temp_32 = cut
    end
    ____jobLine_35(
        ____bot_33,
        ____p_34,
        "end",
        why,
        ____temp_32
    )
    local function r1(x)
        return math.floor(x * 10) / 10
    end
    local ____array_36 = __TS__SparseArrayNew(
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
        ____array_36,
        {
            "sh",
            math.floor((p.hitAt - p.plan.slot) * 10 + 0.5) / 10
        },
        {
            "s0",
            p.timer.first ~= nil and math.floor(p.timer.first * 10 + 0.5) / 10 or nil
        },
        {"lv", p.timer.reads},
        {
            "nsp",
            p.timer.timing.neutralSpeed ~= nil and math.floor(p.timer.timing.neutralSpeed + 0.5) or nil
        },
        {"hr", p.timer.hit ~= nil and "geo" or "plan"},
        {"hc", p.timer.n},
        {"hn", p.timer.next},
        {"hb", p.timer.back},
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
        },
        {"st", p.stayAt ~= nil and (cut ~= nil and (endWhy .. ":") .. cut or endWhy) or nil},
        {
            "ss",
            p.stayAt ~= nil and r1(DotaTime() - p.stayAt) or nil
        },
        {"sdt", p.sdt},
        {"sdk", p.sdk},
        {"slt", p.slt},
        {"slk", p.slk},
        {"sht", p.sht},
        {
            "shl",
            p.stayHp ~= nil and math.floor((p.stayHp - (bot:IsAlive() and bot:GetHealth() or 0)) / bot:GetMaxHealth() * 100 + 0.5) / 100 or nil
        }
    )
    local fields = {__TS__SparseArraySpread(____array_36)}
    if not r.success then
        Telemetry.Event("pull_job", fields)
        return
    end
    local now = DotaTime()
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
    local ____Telemetry_Event_38 = Telemetry.Event
    local ____array_37 = __TS__SparseArrayNew(unpack(tr.fields))
    __TS__SparseArrayPush(
        ____array_37,
        {
            "dt",
            share(tr.pull)
        }
    )
    ____Telemetry_Event_38(
        "pull_job",
        {__TS__SparseArraySpread(____array_37)}
    )
end
--- At the hit: the camp's neutrals (in its box, or on the puller within TagRadius), so the watch follows that camp only.
local function tagCamp(bot, p)
    p.hat = DotaTime()
    local tagged = ____exports.CampStateOf(p.plan.spawner).units
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue143
            repeat
                if not u:IsAlive() or __TS__ArrayIndexOf(tagged, u) >= 0 or GetUnitToUnitDistance(u, bot) > ____exports.SETTINGS.TagRadius then
                    __continue143 = true
                    break
                end
                if u:GetAttackTarget() == bot then
                    tagged[#tagged + 1] = u
                end
                __continue143 = true
            until true
            if not __continue143 then
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
            local ____p_early_39 = p.early
            ____p_early_39[#____p_early_39 + 1] = c
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
    camp.earlier = function()
        pull.hitAt = PullTiming.Read(
            pull.timer,
            DotaTime()
        )
        return aggroAt - pull.hitAt
    end
    return {
        bail = function() return bailPoint(bot) end,
        bailFor = ____exports.SETTINGS.BailFor,
        camp = camp,
        aggroAt = aggroAt,
        lead = p.lead,
        watchAt = function()
            local ____Ours_On_result_47
            if Ours.On("SupportPullStay") then
                ____Ours_On_result_47 = behindOurs(bot, pull)
            else
                ____Ours_On_result_47 = nil
            end
            return ____Ours_On_result_47 or shedPoint(bot, pull)
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
local function tenth(x)
    return math.floor(x * 10 + 0.5) / 10
end
--- A unit name less `npc_dota_neutral_` or `npc_dota_creep_` (stay_try).
local function shortName(name)
    for ____, pre in ipairs({"npc_dota_neutral_", "npc_dota_creep_"}) do
        if __TS__StringStartsWith(name, pre) then
            return __TS__StringSubstring(name, #pre)
        end
    end
    return name
end
--- One `ev=stay_try` line: a deny or neutral last-hit try of the stay and why it ended (logging only).
local function tryLine(bot, p, kind, r, target, hp, hits)
    local ____this_49
    ____this_49 = target
    local ____opt_48 = ____this_49.GetUnitName
    local name = ____opt_48 and ____opt_48(____this_49) or "?"
    Telemetry.Event(
        "stay_try",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"slot", p.plan.slot},
            {"k", kind},
            {"ok", r.success and 1 or 0},
            {"why", r.reason},
            {"m", r.message},
            {
                "u",
                shortName(name)
            },
            {
                "hp",
                math.floor(hp + 0.5)
            },
            {
                "hh",
                tenth(hits)
            },
            {
                "dt",
                p.tryAt ~= nil and tenth(DotaTime() - p.tryAt) or nil
            }
        }
    )
    p.tryAt = nil
end
--- One `ev=stay_look` sample per WatchLogEvery while the stay runs (logging only).
local function lookLine(bot, p, l)
    local now = DotaTime()
    if l.step == "lasthit" or l.step == "deny" then
        p.tryAt = now
    end
    if p.lookedAt ~= nil and now - p.lookedAt < ____exports.SETTINGS.WatchLogEvery then
        return
    end
    p.lookedAt = now
    Telemetry.Event(
        "stay_look",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"slot", p.plan.slot},
            {"step", l.step},
            {"nc", l.ours},
            {"nn", l.neutrals},
            {"nw", l.worked},
            {"due", l.due},
            {"sk", l.skipped},
            {
                "mh",
                l.minHits ~= nil and tenth(l.minHits) or nil
            },
            {
                "bh",
                math.floor(bot:GetHealth() / bot:GetMaxHealth() * 100 + 0.5) / 100
            }
        }
    )
end
local stay = __TS__Generator(function(bot, p, hooks)
    p.stayAt = DotaTime()
    p.stayHp = bot:GetHealth()
    return __TS__DelegatedYield(Tasks.Jobs().stayCamp(
        bot,
        {
            at = p.plan.spawner.location,
            deadline = p.stayAt + ____exports.SETTINGS.StayMax,
            onHit = function()
                p.sht = (p.sht or 0) + 1
            end,
            onAttempt = function(kind, r, target, hp, hits)
                if kind == "deny" then
                    p.sdt = (p.sdt or 0) + 1
                    if r.success then
                        p.sdk = (p.sdk or 0) + 1
                    end
                else
                    p.slt = (p.slt or 0) + 1
                    if r.success then
                        p.slk = (p.slk or 0) + 1
                    end
                end
                tryLine(
                    bot,
                    p,
                    kind,
                    r,
                    target,
                    hp,
                    hits
                )
            end,
            onLook = function(l) return lookLine(bot, p, l) end
        },
        hooks
    ))
end)
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
    local r = __TS__DelegatedYield(Tasks.Jobs().pull(
        bot,
        verbPlan(bot, p, aggroAt),
        hooks
    ))
    if not r.success or not Ours.On("SupportPullStay") then
        return r
    end
    return __TS__DelegatedYield(stay(bot, p, hooks))
end)
--- The slot this puller would have to leave for now, with the lane's read of it: undefined before the leave time and once
-- the slot's wave is handled. The lane is read once per wave, on the first frame at or after the leave time.
local function dueSlot(bot, now)
    local pid = bot:GetPlayerID()
    local p = planFor(bot, now)
    if p == nil or ____exports.SameWave(handled[pid], p.slot) then
        return nil
    end
    local walk = travel(bot, p)
    local timer = timers[pid]
    if timer == nil or not ____exports.SameWave(timer.slot, p.slot) then
        timer = PullTiming.Timer(
            p.timing,
            p.slot,
            LaneConfig.Settings().PullTiming.FullPast
        )
        timers[pid] = timer
    end
    local hitAt = PullTiming.Read(timer, now)
    if now < hitAt - walk - ____exports.SETTINGS.Early then
        return nil
    end
    local d = decided[pid]
    if d == nil or not ____exports.SameWave(d.slot, p.slot) then
        local reading = LanePush.Read(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )
        local gone = LanePush.WaveGoneNow(
            bot:GetTeam(),
            bot:GetAssignedLane(),
            ____exports.PulledSpawn(p.slot),
            p.slot + ____exports.SETTINGS.ArriveAfter
        )
        local tgt = LanePush.TargetOf(bot:GetAssignedLane())
        local forced = Drill.ForcedAt(
            "pull",
            ____exports.PulledSpawn(p.slot)
        )
        if forced ~= nil then
            d = {
                slot = p.slot,
                want = forced == "on",
                reading = reading,
                gone = gone,
                rule = forced == "on" and "drill" or nil,
                drill = true
            }
        else
            local byNew = ____exports.Wanted(gone, tgt)
            d = {
                slot = p.slot,
                want = byNew,
                reading = reading,
                gone = gone,
                rule = byNew and "new" or nil
            }
        end
        decided[pid] = d
        gateWhy[pid] = nil
    end
    return {
        p = p,
        timer = timer,
        hitAt = hitAt,
        walk = walk,
        d = d
    }
end
--- Plan s5's denominator in the arm that does not pull: for a lane's puller whose pull is switched off, the same read of each
-- slot at the same leave time, written as the line the row writes (`go=0 why=off src=shadow`). It reads and logs; nothing is
-- ordered or started. A shadowed slot is where a puller standing where stock left it would have had to leave; the on arm's
-- puller may stand elsewhere, so the two arms' slots match by wave, not by second.
function ____exports.Shadow(bot)
    logSeeds()
    if not Telemetry.IsEnabled() or not ____exports.IsPuller(bot) or rowOn(bot) or Drill.Held(bot) then
        return
    end
    if not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return
    end
    watch(bot)
    local due = dueSlot(
        bot,
        DotaTime()
    )
    if due == nil then
        return
    end
    handled[bot:GetPlayerID()] = due.p.slot
    local camp = ____exports.CampStateOf(due.p.spawner)
    camp.known = ____exports.Known(due.p.spawner)
    choiceLine(
        bot,
        due.d,
        due.p.slot,
        false,
        "off",
        camp,
        "shadow"
    )
end
HOST = BotMode.Farm
--- Why a wanted pull may not start now. Danger is the shared read's answer where the hero stands; a hero Valve's attack or a
-- retreat holds is left to it. The camp's damage is the pull's own check, since the shared read prices no neutral damage.
-- The old job's HP floor, hero-hit check, enemy-site rule and partner check are gone: once started, stopping is the
-- decider's (it lets go when stock would retreat) and the verb's bail.
local function startBlock(bot, camp, now, hitAt)
    local gate = ____exports.CampGate(camp, now, hitAt)
    if gate ~= nil then
        return gate
    end
    if SafeGather.At(
        bot,
        bot:GetLocation(),
        {who = "pull_start"}
    ).level == "deadly" then
        return "enemy-near"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    return campDmgGate(bot, camp.dmg) or (acting(bot) and "acting" or nil)
end
seedsLogged = false
local function rowApplies(bot)
    logSeeds()
    if not rowOn(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    local cur = running[pid]
    if cur ~= nil then
        if bot:WasRecentlyDamagedByAnyHero(HERO_HIT_WITHIN) then
            cur.hit = true
        end
        return true
    end
    trail(bot, false)
    if Tasks.Jobs() == nil or not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return false
    end
    watch(bot)
    local now = DotaTime()
    local due = dueSlot(bot, now)
    if due == nil then
        return false
    end
    local p = due.p
    local timer = due.timer
    local hitAt = due.hitAt
    local walk = due.walk
    local d = due.d
    local camp = ____exports.CampStateOf(p.spawner)
    camp.known = ____exports.Known(p.spawner)
    local function done(go, why)
        handled[pid] = p.slot
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
        done(false, d.drill == true and "drill" or (d.reading == nil and "no-read" or "lane"))
        return false
    end
    if camp.known.n < ____exports.SETTINGS.StrongAt and ____exports.CampGate(camp, now, hitAt) == nil then
        done(false, "weak")
        return false
    end
    camp.dmg = ____exports.CampDamage(bot, camp, p.spawner.type)
    camp.php = bot:GetHealth()
    camp.se = siteEnemy(p)
    local why = startBlock(bot, camp, now, hitAt)
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
        host = HOST,
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
            host = HOST,
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
--- The row's verb: one frame of the pull; true once it has ended.
local function rowStep(bot)
    Step(bot)
    return running[bot:GetPlayerID()] == nil
end
--- Soft in the stay (Ours.SupportPullStay): Valve's modes and retreat take the puller when they want it; hard before it.
local function rowSoft(bot)
    local ____opt_51 = running[bot:GetPlayerID()]
    return (____opt_51 and ____opt_51.label) == "stay"
end
--- The decider's row (registered in index.ts, so the decider imports no row).
____exports.ROW = {name = "pull", applies = rowApplies, step = rowStep, soft = rowSoft}
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
function ____exports.NoteIdleHeld(bot)
    local p = running[bot:GetPlayerID()]
    if p ~= nil then
        p.idle = (p.idle or 0) + 1
    end
end
return ____exports
