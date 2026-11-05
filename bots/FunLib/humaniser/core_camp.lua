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

local function __TS__CountVarargs(...)
    return select("#", ...)
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
-- End of Lua Library inline imports
local ____exports = {}
local dist, hpOf, currentMinute, campNeutralCount, measured, r1, r2
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampClaims = require(GetScriptDirectory().."/FunLib/humaniser/camp_claims")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local LaneSpot = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_spot")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function hpOf(bot)
    local m = bot:GetMaxHealth()
    return m > 0 and bot:GetHealth() / m or 0
end
function currentMinute(t)
    return math.floor(t / 60)
end
function campNeutralCount(center)
    local n = 0
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps) or ({})) do
        do
            local __continue67
            repeat
                if u == nil or u == nil or not u:IsAlive() then
                    __continue67 = true
                    break
                end
                local at = u:GetLocation()
                if at ~= nil and at ~= nil and dist(at, center) <= ____exports.SETTINGS.CampRadius then
                    n = n + 1
                end
                __continue67 = true
            until true
            if not __continue67 then
                break
            end
        end
    end
    return n
end
function measured(bot, t, now, center)
    t.nl = campNeutralCount(center)
    local ____t_17 = t
    local ____temp_16
    if t.engagedAt ~= nil then
        ____temp_16 = r1(now - t.engagedAt)
    else
        ____temp_16 = nil
    end
    ____t_17.clrm = ____temp_16
    t.hpm = t.hpAtEngage ~= nil and r2(t.hpAtEngage - hpOf(bot)) or nil
end
____exports.SETTINGS = {
    Priority = 0.8,
    PlanEvery = 1,
    From = 120,
    StartHP = 0.65,
    AbortHP = 0.3,
    FrontRadius = 1800,
    WaveClearRadius = 1000,
    TowerReach = 900,
    TowerShare = 0.2,
    Horizon = 60,
    ClashGap = 300,
    MinGap = 12,
    MaxLate = 15,
    CreepGold = 40,
    LaneShare = 0.5,
    CampGold = {small = 80, medium = 120, large = 160, ancient = 250},
    MinNet = 30,
    CampMinLevel = {small = 3, medium = 4, large = 6, ancient = 12},
    MaxCampDist = 3800,
    PathFactor = 1.2,
    ThreatMargin = 600,
    MidRuneGuard = 40,
    CampRadius = 700,
    ReturnArrive = 900,
    ReturnMax = 25,
    ReturnReorder = 0.5,
    ClearSec = {small = 7, medium = 14, large = 19, ancient = 26},
    RefLevel = 8,
    LevelScale = {0.6, 1.6},
    StackedClearMul = 0.8,
    Learn = 0.3,
    LearnClamp = {0.4, 2.5},
    LateGrowth = 1.15,
    ClearHP = {small = 0.12, medium = 0.2, large = 0.35, ancient = 0.6},
    NeutralsPerStack = 3,
    HPRefLevel = 6,
    HPLevelStep = 0.88,
    ArriveHP = 0.4,
    SwitchSec = 0.6,
    DefaultSPA = 1.7
}
local running = {}
local nextPlanAt = {}
local pace = {}
local hpRate = {}
--- Each camp's neutrals as last seen untouched, by team then camp, with the minute (a respawn is assumed the same).
local lastSeen = {}
--- Camps cleared or seen empty, by team then camp, as the minute (they respawn on the next).
local cleared = {}
--- Skip lines written, by pid: one per wave window and reason.
local skipped = {}
local gates = {}
function ____exports.ResetCache()
    for ____, t in ipairs({
        running,
        nextPlanAt,
        pace,
        hpRate,
        cleared,
        lastSeen,
        skipped,
        gates
    }) do
        for k in pairs(t) do
            __TS__Delete(t, k)
        end
    end
    CampClaims.ResetCache()
end
local function clamp(v, r)
    return math.max(
        r[1],
        math.min(r[2], v)
    )
end
--- A unit's location, or undefined for a handle the API gives none (fogged, or removed this frame).
local function locOf(u)
    local at = u:GetLocation()
    local ____temp_0
    if at == nil then
        ____temp_0 = nil
    else
        ____temp_0 = at
    end
    return ____temp_0
end
local function distToSegment(p, a, b)
    local vx = b.x - a.x
    local vy = b.y - a.y
    local len2 = vx * vx + vy * vy
    local u = len2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)
    ) or 0
    return math.sqrt((p.x - (a.x + u * vx)) ^ 2 + (p.y - (a.y + u * vy)) ^ 2)
end
local function speedOf(bot)
    return math.max(
        bot:GetCurrentMovementSpeed(),
        100
    )
end
--- Meepo's clones and Arc's tempest double share the hero's player ID.
local function sharesPlayerID(bot)
    return bot:GetUnitName() == "npc_dota_hero_meepo" or bot:HasModifier("modifier_arc_warden_tempest_double")
end
function ____exports.Applies(bot)
    if not Ours.On("CoreCampTrip") or not Ours.On("CoreLastHit") or not Ours.On("JobChooser") or not bot:IsBot() or sharesPlayerID(bot) then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 1 and pos <= 3
end
--- The core's lane-stage camp trips are this job's: FarmPattern starts none for it.
function ____exports.Owns(bot)
    return ____exports.Applies(bot) and LaneConfig.InLaningPhase()
end
function ____exports.Priority(bot)
    return ____exports.Owns(bot) and ____exports.SETTINGS.Priority or nil
end
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
function ____exports.Claims(bot)
    return ____exports.Running(bot)
end
function ____exports.PriorClearTime(____type, level, stacks)
    local s = ____exports.SETTINGS
    return (s.ClearSec[____type] or s.ClearSec.medium) * clamp(
        s.RefLevel / math.max(level, 1),
        s.LevelScale
    ) * (1 + s.StackedClearMul * stacks)
end
function ____exports.Pace(bot)
    return pace[bot:GetPlayerID()] or 1
end
local function learn(bot, measured, prior)
    if prior <= 0 then
        return
    end
    local pid = bot:GetPlayerID()
    local old = pace[pid] or 1
    pace[pid] = clamp(old + ____exports.SETTINGS.Learn * (measured / prior - old), ____exports.SETTINGS.LearnClamp)
end
local function growLate(bot)
    local pid = bot:GetPlayerID()
    pace[pid] = clamp((pace[pid] or 1) * ____exports.SETTINGS.LateGrowth, ____exports.SETTINGS.LearnClamp)
end
function ____exports.PriorClearHP(____type, level, stacks)
    local s = ____exports.SETTINGS
    local scale = clamp(s.HPLevelStep ^ (level - s.HPRefLevel), s.LevelScale)
    return (s.ClearHP[____type] or s.ClearHP.medium) * scale * (1 + s.StackedClearMul * stacks)
end
function ____exports.HPRate(bot)
    return hpRate[bot:GetPlayerID()] or 1
end
local function learnHP(bot, measured, prior)
    if prior <= 0 then
        return
    end
    local pid = bot:GetPlayerID()
    local old = hpRate[pid] or 1
    hpRate[pid] = clamp(
        old + ____exports.SETTINGS.Learn * (math.max(measured, 0) / prior - old),
        ____exports.SETTINGS.LearnClamp
    )
end
local function growHP(bot)
    local pid = bot:GetPlayerID()
    hpRate[pid] = clamp((hpRate[pid] or 1) * ____exports.SETTINGS.LateGrowth, ____exports.SETTINGS.LearnClamp)
end
local function spaOf(u)
    local ____this_2
    ____this_2 = u
    local ____opt_1 = ____this_2.GetSecondsPerAttack
    local spa = ____opt_1 and ____opt_1(____this_2)
    return spa ~= nil and spa > 0 and spa or ____exports.SETTINGS.DefaultSPA
end
local function readNeutral(u, hp)
    return {
        hp = hp,
        take = u:GetActualIncomingDamage(100, DamageType.Physical) / 100,
        dmg = u:GetAttackDamage(),
        spa = spaOf(u),
        name = u:GetUnitName()
    }
end
--- Seconds for `bot` to clear `camp` by right-clicks and the fraction of its max HP lost doing it. The neutrals die one at a
-- time in the order that loses the least HP (most damage a second per second of kill time first); each hits until it dies;
-- SwitchSec between kills; the core's regen offsets the loss. Spells and cleave are not in it: the learned pace and HP rate
-- carry them.
function ____exports.ClearOf(bot, camp)
    local hit = bot:GetAttackDamage() / spaOf(bot)
    local foes = {}
    for ____, n in ipairs(camp) do
        foes[#foes + 1] = {
            kill = n.hp / math.max(hit * n.take, 1) + ____exports.SETTINGS.SwitchSec,
            dps = bot:GetActualIncomingDamage(n.dmg, DamageType.Physical) / math.max(n.spa, 0.1)
        }
    end
    __TS__ArraySort(
        foes,
        function(____, a, b) return b.dps / b.kill - a.dps / a.kill end
    )
    local t = 0
    local taken = 0
    for ____, f in ipairs(foes) do
        t = t + f.kill
        taken = taken + f.dps * t
    end
    local hp = math.max(
        0,
        taken - bot:GetHealthRegen() * t
    ) / math.max(
        bot:GetMaxHealth(),
        1
    )
    return t, hp
end
--- The camp's live neutrals (the API returns none in fog). Kept as its make-up only when untouched (every one at full HP),
-- and never replaced by fewer within the same minute: a read of a half-cleared or half-seen camp priced its respawn at one
-- neutral (cngchk8 game 1049 camp 1, t=543: 4.4 s planned, 2 of 3 left).
local function liveNeutrals(team, idx, center, now)
    local live = {}
    local untouched = true
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps) or ({})) do
        do
            local __continue38
            repeat
                if u == nil or u == nil or not u:IsAlive() then
                    __continue38 = true
                    break
                end
                local at = u:GetLocation()
                if at == nil or at == nil or dist(at, center) > ____exports.SETTINGS.CampRadius then
                    __continue38 = true
                    break
                end
                live[#live + 1] = readNeutral(
                    u,
                    u:GetHealth()
                )
                if u:GetHealth() < u:GetMaxHealth() then
                    untouched = false
                end
                __continue38 = true
            until true
            if not __continue38 then
                break
            end
        end
    end
    local min = currentMinute(now)
    local ____opt_3 = lastSeen[team]
    local old = ____opt_3 and ____opt_3[idx]
    if #live > 0 and untouched and (old == nil or old.min ~= min or #live >= #old.ns) then
        lastSeen[team] = lastSeen[team] or ({})
        lastSeen[team][idx] = {min = min, ns = live}
    end
    return live
end
--- Clear seconds and HP fraction before the learned factors, and their source; `stacks` scales only the unseen ones.
local function estimate(bot, spawner, center, stacks, now)
    local live = liveNeutrals(
        bot:GetTeam(),
        spawner.idx,
        center,
        now
    )
    if #live > 0 then
        local secs, hp = ____exports.ClearOf(bot, live)
        return secs, hp, "live", live
    end
    local ____opt_7 = lastSeen[bot:GetTeam()]
    local ____opt_5 = ____opt_7 and ____opt_7[spawner.idx]
    local seen = ____opt_5 and ____opt_5.ns
    if seen ~= nil then
        local secs, hp = ____exports.ClearOf(bot, seen)
        local k = 1 + ____exports.SETTINGS.StackedClearMul * stacks
        return secs * k, hp * k, "seen", seen
    end
    local level = bot:GetLevel()
    return ____exports.PriorClearTime(spawner.type, level, stacks), ____exports.PriorClearHP(spawner.type, level, stacks), "table", nil
end
--- The neutrals the model priced, for the check: short name, HP, damage, seconds per attack, share taken.
local function neutralsField(ns)
    if ns == nil then
        return nil
    end
    local parts = {}
    for ____, n in ipairs(ns) do
        local short = string.gsub(n.name or "?", "npc_dota_neutral_", "")
        parts[#parts + 1] = (((((((short .. "/") .. tostring(math.floor(n.hp))) .. "/") .. tostring(math.floor(n.dmg))) .. "/") .. tostring(r2(n.spa))) .. "/") .. tostring(r2(n.take))
    end
    return table.concat(parts, ",")
end
--- Whether lane position `s` lies within the enemy T1's reach (Radiant runs along increasing `s`).
function ____exports.UnderEnemyTower(path, team, s)
    for ____, tw in ipairs(path.towers) do
        do
            local __continue52
            repeat
                if tw.team == team then
                    __continue52 = true
                    break
                end
                local ____temp_9
                if team == Team.Radiant then
                    ____temp_9 = s >= tw.s - ____exports.SETTINGS.TowerReach
                else
                    ____temp_9 = s <= tw.s + ____exports.SETTINGS.TowerReach
                end
                return ____temp_9
            until true
            if not __continue52 then
                break
            end
        end
    end
    return false
end
--- Where the fronts meet in a sample (their midpoint on the lane), or undefined when they are not within ClashGap.
local function meetingAt(smp)
    local r = smp.front[Team.Radiant]
    local d = smp.front[Team.Dire]
    return r ~= nil and d ~= nil and d - r <= ____exports.SETTINGS.ClashGap and (r + d) / 2 or nil
end
--- The next lane gold: the first second the fronts meet outside the enemy T1's reach. A wave crashing into their tower is
-- not it, so a pushed lane's gap runs to the next wave's meeting.
function ____exports.ClashOf(samples, path, team)
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    for ____, smp in ipairs(samples) do
        local m = meetingAt(smp)
        if m ~= nil and not ____exports.UnderEnemyTower(path, team, m) then
            local x, y = unpack(LanePush.PointAt(path, m))
            return {
                t = smp.t,
                at = Vector(x, y, 0),
                t0 = samples[1].t,
                samples = samples,
                enemy = enemy,
                path = path,
                team = team
            }
        end
    end
    return nil
end
--- The lane gold the core would have taken from the enemy creeps the run kills between `from` and `to` (to the last sample
-- when `to` lies beyond it): LaneShare of each, TowerShare of those killed while the fronts meet in the enemy T1's reach.
function ____exports.LossBetween(c, from, to)
    local gold = 0
    local prev
    for ____, smp in ipairs(c.samples) do
        if smp.t > to then
            break
        end
        local dead = smp.dead[c.enemy] or 0
        if prev ~= nil and smp.t > from and dead > prev then
            local m = meetingAt(smp)
            local share = m ~= nil and ____exports.UnderEnemyTower(c.path, c.team, m) and ____exports.SETTINGS.TowerShare or ____exports.SETTINGS.LaneShare
            gold = gold + (dead - prev) * ____exports.SETTINGS.CreepGold * share
        end
        prev = dead
    end
    return gold
end
local function seenStacks(center)
    return math.max(
        0,
        math.floor(campNeutralCount(center) / ____exports.SETTINGS.NeutralsPerStack) - 1
    )
end
local function markCleared(team, idx, now)
    cleared[team] = cleared[team] or ({})
    cleared[team][idx] = currentMinute(now)
end
--- Lane mates whose pull is planned: our lane's pull camps are theirs.
local function matePulling(bot)
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false
    end
    local pid = bot:GetPlayerID()
    for ____, h in ipairs(s.allies) do
        if h.assigned and h.pid ~= pid and h.alive and PullJob.Claims(h.unit) then
            return true
        end
    end
    return false
end
local function otherTripOn(bot, idx)
    local pid = bot:GetPlayerID()
    for other, t in pairs(running) do
        if other ~= pid and t ~= nil and t.plan.camp == idx then
            return true
        end
    end
    return false
end
local function allyInBox(bot, idx)
    local pid = bot:GetPlayerID()
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue82
            repeat
                if a == nil or a == nil or not a:IsAlive() or a:GetPlayerID() == pid then
                    __continue82 = true
                    break
                end
                local at = locOf(a)
                if at ~= nil and Camps.InBox(idx, at, 300) then
                    return true
                end
                __continue82 = true
            until true
            if not __continue82 then
                break
            end
        end
    end
    return false
end
--- A lane creep in the camp: a pulled wave is fighting it, and its neutrals die to the wave, not to the core (cngchk5-9: 6
-- trips to camp 26 at about 3:36 found its neutrals damaged, saw them die to no hero and came back with 0 kills).
local function pulledInto(center)
    for ____, kind in ipairs({UnitType.AlliedCreeps, UnitType.EnemyCreeps}) do
        for ____, u in ipairs(GetUnitList(kind) or ({})) do
            do
                local __continue88
                repeat
                    if u == nil or u == nil or not u:IsAlive() or not LanePush.IsLaneCreep(u:GetUnitName()) then
                        __continue88 = true
                        break
                    end
                    local at = locOf(u)
                    if at ~= nil and dist(at, center) <= ____exports.SETTINGS.CampRadius then
                        return true
                    end
                    __continue88 = true
                until true
                if not __continue88 then
                    break
                end
            end
        end
    end
    return false
end
local function campOpen(bot, spawner, center, now, pullCamps)
    local team = bot:GetTeam()
    local ____opt_10 = cleared[team]
    if (____opt_10 and ____opt_10[spawner.idx]) == currentMinute(now) then
        return false
    end
    if IsLocationVisible(center) and campNeutralCount(center) == 0 then
        return false
    end
    if pullCamps[spawner.idx] == true or pulledInto(center) and CampClaims.On("pullfarm", spawner.idx) == nil then
        return false
    end
    return not allyInBox(bot, spawner.idx) and not otherTripOn(bot, spawner.idx) and not Stacking.ReservedByAlly(
        spawner.idx,
        bot:GetPlayerID()
    )
end
--- The best camp of the core's own jungle from `from` against the forecast `c`, or undefined: open, of a type its level
-- allows, within MaxCampDist of the clash point, back by the clash + MaxLate, with the highest net of at least MinNet.
function ____exports.Plan(bot, from, now, c)
    local s = ____exports.SETTINGS
    local speed = speedOf(bot) / s.PathFactor
    local level = bot:GetLevel()
    local pullCamps = {}
    if matePulling(bot) then
        for ____, p in ipairs(Camps.PullCampsFor(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )) do
            pullCamps[p.campIdx] = true
        end
    end
    local best
    for ____, spawner in ipairs(Camps.Spawners()) do
        do
            local __continue101
            repeat
                if spawner.team ~= bot:GetTeam() or level < (s.CampMinLevel[spawner.type] or 1) then
                    __continue101 = true
                    break
                end
                local center = Camps.BoxCenter(spawner)
                if dist(center, c.at) > s.MaxCampDist or not campOpen(
                    bot,
                    spawner,
                    center,
                    now,
                    pullCamps
                ) then
                    __continue101 = true
                    break
                end
                local stacks = math.max(
                    Stacking.StackCount(spawner.idx),
                    seenStacks(center)
                )
                local prior, hpPrior, src, priced = estimate(
                    bot,
                    spawner,
                    center,
                    stacks,
                    now
                )
                local clrt = ____exports.PriorClearTime(spawner.type, level, stacks)
                local hpt = ____exports.PriorClearHP(spawner.type, level, stacks)
                local clr = prior * ____exports.Pace(bot)
                local hpc = hpPrior * ____exports.HPRate(bot)
                if hpOf(bot) - hpc < s.ArriveHP then
                    __continue101 = true
                    break
                end
                local back = dist(center, c.at) / speed
                local ret = now + dist(from, center) / speed + clr + back
                local force = Overrides.CampForce()
                if ret > (force and now + s.Horizon or c.t + s.MaxLate) then
                    __continue101 = true
                    break
                end
                local gold = (s.CampGold[spawner.type] or s.CampGold.medium) * (1 + stacks)
                local loss = ____exports.LossBetween(c, now, ret)
                local net = gold - loss
                if (force or net >= s.MinNet) and (best == nil or net > best.net) then
                    best = {
                        camp = spawner.idx,
                        type = spawner.type,
                        ret = ret,
                        leaveBy = ret - back,
                        clr = clr,
                        prior = prior,
                        src = src,
                        nu = neutralsField(priced),
                        n0 = priced and #priced,
                        clrt = clrt,
                        hpt = hpt,
                        hpc = hpc,
                        hpPrior = hpPrior,
                        gold = gold,
                        loss = loss,
                        net = net
                    }
                end
                __continue101 = true
            until true
            if not __continue101 then
                break
            end
        end
    end
    return best
end
--- Any open camp of a type the core's level allows within MaxCampDist of `front`: the forecast (about 11 ms for 60 s) runs only then.
local function anyCamp(bot, front, now)
    local level = bot:GetLevel()
    for ____, spawner in ipairs(Camps.Spawners()) do
        do
            local __continue109
            repeat
                if spawner.team ~= bot:GetTeam() or level < (____exports.SETTINGS.CampMinLevel[spawner.type] or 1) then
                    __continue109 = true
                    break
                end
                local center = Camps.BoxCenter(spawner)
                if dist(center, front) <= ____exports.SETTINGS.MaxCampDist and campOpen(
                    bot,
                    spawner,
                    center,
                    now,
                    {}
                ) then
                    return true
                end
                __continue109 = true
            until true
            if not __continue109 then
                break
            end
        end
    end
    return false
end
--- A visible enemy hero whose reach (plus ThreatMargin) touches the walk from the core to `at` or the camp itself.
function ____exports.ThreatOnWay(bot, at)
    local here = bot:GetLocation()
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue114
            repeat
                if e == nil or e == nil or not e:IsAlive() or e:IsIllusion() then
                    __continue114 = true
                    break
                end
                local loc = locOf(e)
                if loc ~= nil and distToSegment(loc, here, at) <= LaneSpot.HeroReach(bot, e) + ____exports.SETTINGS.ThreatMargin then
                    return true
                end
                __continue114 = true
            until true
            if not __continue114 then
                break
            end
        end
    end
    return false
end
local function mateOnJob(bot)
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false
    end
    local pid = bot:GetPlayerID()
    for ____, h in ipairs(s.allies) do
        do
            local __continue120
            repeat
                if not h.assigned or h.pid == pid or not h.alive then
                    __continue120 = true
                    break
                end
                if StackJob.Running(h.unit) or PullJob.Running(h.unit) or RuneJob.Running(h.unit) or CampJobs.Active(h.unit) then
                    return true
                end
                __continue120 = true
            until true
            if not __continue120 then
                break
            end
        end
    end
    return false
end
local function enemyLaneCreepNear(at, radius)
    for ____, c in ipairs(GetUnitList(UnitType.EnemyCreeps) or ({})) do
        do
            local __continue125
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue125 = true
                    break
                end
                local loc = locOf(c)
                if loc ~= nil and dist(loc, at) <= radius then
                    return true
                end
                __continue125 = true
            until true
            if not __continue125 then
                break
            end
        end
    end
    return false
end
--- Why the core is not looking for a camp now (cheap reads, before the forecast), or undefined.
local function inLaneGate(bot, now)
    local s = ____exports.SETTINGS
    if not bot:IsAlive() then
        return "dead"
    end
    if now < s.From then
        return "time"
    end
    local mode = bot:GetActiveMode()
    if mode ~= BotMode.Laning and mode ~= BotMode.None then
        return "mode"
    end
    if hpOf(bot) < s.StartHP then
        return "low-hp"
    end
    local front = GetLaneFrontLocation(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        0
    )
    if dist(
        bot:GetLocation(),
        front
    ) > s.FrontRadius then
        return "far"
    end
    if not Overrides.CampForce() and enemyLaneCreepNear(
        bot:GetLocation(),
        s.WaveClearRadius
    ) then
        return "wave"
    end
    return nil
end
--- Why a fitting trip may not start now, or undefined.
local function startGate(bot, plan, now)
    if mateOnJob(bot) then
        return "mate-job"
    end
    if LaneHooks.EnemiesMissing(
        bot,
        LaneConfig.Settings().Thresholds.JobMissingFresh
    ) > 0 then
        return "enemy-missing"
    end
    if LaneConfig.PositionOf(bot) == 2 and Runes.NextSpawn("power", now) - now < ____exports.SETTINGS.MidRuneGuard then
        return "rune"
    end
    local spawner = Camps.SpawnerByIdx(plan.camp)
    if spawner ~= nil and ____exports.ThreatOnWay(
        bot,
        Camps.BoxCenter(spawner)
    ) then
        return "threat"
    end
    return nil
end
r1 = function(x) return x ~= nil and math.floor(x * 10 + 0.5) / 10 or nil end
r2 = function(x) return math.floor(x * 100 + 0.5) / 100 end
local function planFields(p)
    return {
        {"camp", p.camp},
        {"type", p.type},
        {
            "ret",
            r1(p.ret)
        },
        {
            "clr",
            r1(p.clr)
        },
        {"src", p.src},
        {
            "clrt",
            r1(p.clrt)
        },
        {
            "hpt",
            r2(p.hpt)
        },
        {"n0", p.n0},
        {"nu", p.nu},
        {
            "hpc",
            r2(p.hpc)
        },
        {
            "gold",
            math.floor(p.gold)
        },
        {
            "loss",
            math.floor(p.loss)
        },
        {
            "net",
            math.floor(p.net)
        }
    }
end
local function log(bot, phase, c, fields)
    Telemetry.Event(
        "core_camp",
        {
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
            {"phase", phase},
            {"clash", c.t},
            {
                "win",
                math.floor(c.t / 30)
            },
            unpack(fields)
        }
    )
end
--- One skip line per wave window and reason: the coverage count's windows where a camp fitted and no trip started.
local function noteSkip(bot, why, c, plan)
    local pid = bot:GetPlayerID()
    local key = (tostring(math.floor(c.t / 30)) .. ":") .. why
    skipped[pid] = skipped[pid] or ({})
    if skipped[pid][key] == true then
        return
    end
    skipped[pid][key] = true
    log(
        bot,
        "skip",
        c,
        {
            {"why", why},
            unpack(planFields(plan))
        }
    )
end
local GATE_FIELD = {
    dead = "h_dead",
    mode = "h_mode",
    ["low-hp"] = "h_hp",
    far = "h_far",
    wave = "h_wave",
    ["no-camp"] = "h_camp",
    ["no-forecast"] = "h_fc",
    ["no-clash"] = "h_clash",
    gap = "h_gap",
    ["no-plan"] = "h_plan",
    skip = "h_skip",
    trip = "h_trip"
}
--- The coverage's denominator: each planning second of the laning phase counted by what held it, one `phase=gates` line per
-- core per game minute. The skip lines only see seconds where a camp already fitted.
local function tally(bot, now, why)
    local pid = bot:GetPlayerID()
    local min = math.floor(now / 60)
    local g = gates[pid]
    if g ~= nil and g.min ~= min then
        local fields = {{"min", g.min}}
        for k, n in pairs(g.n) do
            fields[#fields + 1] = {GATE_FIELD[k], n}
        end
        Telemetry.Event(
            "core_camp",
            {
                {"pid", pid},
                {
                    "pos",
                    LaneConfig.PositionOf(bot)
                },
                {
                    "lane",
                    bot:GetAssignedLane()
                },
                {"phase", "gates"},
                unpack(fields)
            }
        )
        g = nil
    end
    if g == nil then
        g = {min = min, n = {}}
        gates[pid] = g
    end
    g.n[why] = (g.n[why] or 0) + 1
end
local function jobLine(bot, t, phase, why)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "camp"},
            {"phase", phase},
            {"why", why},
            {"host", t.host},
            unpack(phase == "end" and ({{"hit", t.hit == true and 1 or 0}}) or ({}))
        }
    )
end
--- Why the trip must stop now (the task's guard, every frame), or undefined. The walk back ignores heroes: laning decides.
local function guard(bot, t)
    if hpOf(bot) < ____exports.SETTINGS.AbortHP then
        return "hp"
    end
    if t.returning == true then
        return nil
    end
    local near = false
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue155
            repeat
                if e == nil or e == nil or not e:IsAlive() or e:IsIllusion() then
                    __continue155 = true
                    break
                end
                local loc = locOf(e)
                if loc ~= nil and dist(
                    loc,
                    bot:GetLocation()
                ) <= LaneSpot.HeroReach(bot, e) then
                    near = true
                end
                __continue155 = true
            until true
            if not __continue155 then
                break
            end
        end
    end
    if not near then
        t.threatSince = nil
        return nil
    end
    local now = DotaTime()
    t.threatSince = t.threatSince or now
    return now - t.threatSince >= Profile.Get(bot).reactBase and "threat" or nil
end
local walkBack = __TS__Generator(function(bot, t, ctx)
    ctx.label("return")
    t.returning = true
    local from = DotaTime()
    local orderedAt = -math.huge
    while true do
        if not bot:IsAlive() then
            return {success = false, reason = "dead"}
        end
        local now = DotaTime()
        local front = GetLaneFrontLocation(
            bot:GetTeam(),
            t.lane,
            0
        )
        if dist(
            bot:GetLocation(),
            front
        ) <= ____exports.SETTINGS.ReturnArrive or enemyLaneCreepNear(
            bot:GetLocation(),
            ____exports.SETTINGS.WaveClearRadius
        ) then
            t.back = now
            return {
                success = true,
                reason = "ok",
                message = dist(
                    bot:GetLocation(),
                    front
                ) <= ____exports.SETTINGS.ReturnArrive and "back" or "wave"
            }
        end
        if now - from > ____exports.SETTINGS.ReturnMax then
            return {success = false, reason = "timeout", message = "late"}
        end
        if now - orderedAt >= ____exports.SETTINGS.ReturnReorder then
            bot:Action_MoveToLocation(front)
            orderedAt = now
        end
        coroutine.yield()
    end
end)
local body = __TS__Generator(function(bot, t, ctx)
    local V = Tasks.Jobs()
    local hooks = {
        label = function(l) return ctx.label(l) end,
        urgent = ctx.urgent
    }
    while true do
        local spawner = Camps.SpawnerByIdx(t.plan.camp)
        if spawner == nil then
            break
        end
        t.engagedAt = nil
        t.hpAtEngage = nil
        local ____t_15 = t
        local ____t_14 = t
        t.nl = nil
        ____t_14.hpm = nil
        ____t_15.clrm = nil
        t.center = Camps.BoxCenter(spawner)
        local r = __TS__DelegatedYield(V.clearCamp(
            bot,
            {
                at = Camps.BoxCenter(spawner),
                radius = ____exports.SETTINGS.CampRadius,
                deadline = t.plan.leaveBy,
                onEngage = function(at)
                    t.engagedAt = at
                    t.hpAtEngage = hpOf(bot)
                end
            },
            hooks
        ))
        local now = DotaTime()
        if not r.success then
            if r.reason ~= "timeout" then
                return r
            end
            if t.engagedAt ~= nil then
                measured(
                    bot,
                    t,
                    now,
                    Camps.BoxCenter(spawner)
                )
                growLate(bot)
            end
            break
        end
        if t.engagedAt ~= nil then
            measured(
                bot,
                t,
                now,
                Camps.BoxCenter(spawner)
            )
        end
        if r.message == "cleared" and t.engagedAt ~= nil then
            learn(bot, now - t.engagedAt, t.plan.prior)
            if t.hpAtEngage ~= nil then
                learnHP(
                    bot,
                    t.hpAtEngage - hpOf(bot),
                    t.plan.hpPrior
                )
            end
        end
        markCleared(
            bot:GetTeam(),
            t.plan.camp,
            now
        )
        local next = ____exports.Plan(
            bot,
            bot:GetLocation(),
            now,
            t.clash
        )
        if next == nil then
            break
        end
        t.plan = next
        CampClaims.Set(
            "core",
            bot:GetPlayerID(),
            next.camp
        )
        t.camps = t.camps + 1
        log(
            bot,
            "next",
            t.clash,
            {
                {"after", r.message or "ok"},
                {"clrm", t.clrm},
                {"hpm", t.hpm},
                {"nl", t.nl},
                unpack(planFields(next))
            }
        )
    end
    return __TS__DelegatedYield(walkBack(bot, t, ctx))
end)
local function finish(bot, t, r, label)
    running[bot:GetPlayerID()] = nil
    CampClaims.Set(
        "core",
        bot:GetPlayerID(),
        nil
    )
    local why = r.success and (r.message or "ok") or r.reason .. (r.message ~= nil and ":" .. r.message or "")
    if why == "interrupted:hp" and t.returning ~= true then
        growHP(bot)
    end
    if t.returning ~= true and t.engagedAt ~= nil and t.clrm == nil and t.center ~= nil then
        measured(
            bot,
            t,
            DotaTime(),
            t.center
        )
    end
    jobLine(bot, t, "end", why)
    log(
        bot,
        "end",
        t.clash,
        {
            {"res", r.success and "ok" or "fail"},
            {"why", why},
            {"label", label},
            {"camp", t.plan.camp},
            {"camps", t.camps},
            {
                "ret",
                r1(t.plan.ret)
            },
            {
                "back",
                r1(t.back)
            },
            {"g0", t.g0},
            {
                "g1",
                bot:GetNetWorth()
            },
            {
                "secs",
                r1(DotaTime() - t.left)
            },
            {
                "pace",
                r1(____exports.Pace(bot))
            },
            {
                "hp",
                r2(hpOf(bot))
            },
            {
                "hpr",
                r2(____exports.HPRate(bot))
            },
            {"clrm", t.clrm},
            {"hpm", t.hpm},
            {"nl", t.nl}
        }
    )
end
--- Every frame while the chooser asks: true while a trip runs or as one starts. Planned at most every PlanEvery: the cheap
-- in-lane reads, then the forecast and the camps, then the start gates (`blocked`: the chooser's own and higher jobs').
function ____exports.Wants(bot, blocked, host)
    if not ____exports.Owns(bot) then
        return false
    end
    Tasks.Tick(bot)
    local pid = bot:GetPlayerID()
    if running[pid] ~= nil then
        return true
    end
    if Tasks.Jobs() == nil then
        return false
    end
    local now = DotaTime()
    if now < (nextPlanAt[pid] or -math.huge) then
        return false
    end
    nextPlanAt[pid] = now + ____exports.SETTINGS.PlanEvery
    local function held(why)
        tally(bot, now, why)
        return false
    end
    local gate = inLaneGate(bot, now)
    if gate == "time" then
        return false
    end
    if gate ~= nil then
        return held(gate)
    end
    local lane = bot:GetAssignedLane()
    if not anyCamp(
        bot,
        GetLaneFrontLocation(
            bot:GetTeam(),
            lane,
            0
        ),
        now
    ) then
        return held("no-camp")
    end
    local samples, path = LanePush.Forecast(
        bot:GetTeam(),
        lane,
        ____exports.SETTINGS.Horizon
    )
    if samples == nil or path == nil or #samples == 0 then
        return held("no-forecast")
    end
    local force = Overrides.CampForce()
    local clash = ____exports.ClashOf(
        samples,
        path,
        bot:GetTeam()
    )
    if clash == nil and force then
        local at = GetLaneFrontLocation(
            bot:GetTeam(),
            lane,
            0
        )
        clash = {
            t = now + ____exports.SETTINGS.Horizon,
            at = at,
            t0 = samples[1].t,
            samples = samples,
            enemy = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant,
            path = path,
            team = bot:GetTeam()
        }
    end
    if clash == nil then
        return held("no-clash")
    end
    if not force and clash.t - now < ____exports.SETTINGS.MinGap then
        return held("gap")
    end
    local plan = ____exports.Plan(
        bot,
        bot:GetLocation(),
        now,
        clash
    )
    if plan == nil then
        return held("no-plan")
    end
    local why = blocked(bot) or startGate(bot, plan, now)
    if why ~= nil then
        noteSkip(bot, why, clash, plan)
        return held("skip")
    end
    tally(bot, now, "trip")
    local t = {
        lane = lane,
        clash = clash,
        plan = plan,
        camps = 1,
        left = now,
        g0 = bot:GetNetWorth(),
        host = host
    }
    local ok = Tasks.Start(
        bot,
        {
            name = "camp",
            host = host,
            preemptAfter = 1,
            stallAfter = 4,
            guard = function() return guard(bot, t) end,
            onEnd = function(r, info) return finish(bot, t, r, info.label) end
        },
        function(ctx) return body(bot, t, ctx) end
    )
    if not ok then
        return false
    end
    running[pid] = t
    CampClaims.Set("core", pid, plan.camp)
    jobLine(bot, t, "start", "trigger")
    log(
        bot,
        "start",
        clash,
        planFields(plan)
    )
    return true
end
function ____exports.Step(bot, host)
    return running[bot:GetPlayerID()] ~= nil and Tasks.Step(bot, host)
end
function ____exports.End(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
function ____exports.NoteHit(bot)
    local t = running[bot:GetPlayerID()]
    if t ~= nil then
        t.hit = true
    end
end
function ____exports.NoteIdleHeld(_bot)
end
return ____exports
