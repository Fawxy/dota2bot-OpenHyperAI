--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
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
-- End of Lua Library inline imports
local ____exports = {}
local close, doneFor
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Busy = require(GetScriptDirectory().."/FunLib/humaniser/transitions/busy")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
function close(bot, trip, r, label)
    local pid = bot:GetPlayerID()
    trip.ended = r.success and "ok" or (r.message or r.reason)
    doneFor[pid] = trip.spawn
    local now = DotaTime()
    local ____Telemetry_Event_4 = Telemetry.Event
    local ____array_3 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "pos",
            LaneConfig.PositionOf(bot)
        },
        {"spawn", trip.spawn},
        {"result", r.success and "ok" or "fail"}
    )
    local ____r_success_2
    if r.success then
        ____r_success_2 = nil
    else
        ____r_success_2 = trip.ended
    end
    __TS__SparseArrayPush(
        ____array_3,
        {"reason", ____r_success_2},
        {"label", label},
        {"left", trip.startedAt},
        {"arrived", trip.arrivedAt},
        {"taken", r.success and now - trip.spawn or nil},
        {"away", now - trip.startedAt}
    )
    ____Telemetry_Event_4(
        "wisdom",
        {__TS__SparseArraySpread(____array_3)}
    )
end
____exports.NAME = "rotate"
--- mode_rune_generic's shrine spots (7.38+: Shrines of Wisdom, one in each team's offlane jungle).
local SHRINE = {[Team.Radiant] = {-7948.152344, 768.207825, 256}, [Team.Dire] = {8029.234375, -1125.811768, 256}}
--- Above laning (0.5 + stickiness), below the job break, like the camp jobs.
local SCORE = 0.75
--- Liquipedia/7.41: stand within 300 of the shrine for 3 s.
local CHANNEL = 3
local RADIUS = 300
--- Not at the shrine this long after it fills: the trip is not worth it any more (lane, enemy support).
local LATE_BY = 15
local PICKUP_FOR = 20
--- Walking paths are longer than the straight line (transitions settings PathFactor).
local PATH_FACTOR = 1.2
local DANGER_RADIUS = 1200
local DANGER_HP = 0.5
local WISDOM_POSITIONS = {[4] = true}
local trips = {}
doneFor = {}
function ____exports.ResetCache()
    for k in pairs(trips) do
        trips[k] = nil
    end
    for k in pairs(doneFor) do
        doneFor[k] = nil
    end
end
function ____exports.ShrineFor(team)
    local s = SHRINE[team] or SHRINE[Team.Radiant]
    return Vector(s[1], s[2], s[3])
end
local function planFor(bot, spawn)
    return {
        at = ____exports.ShrineFor(bot:GetTeam()),
        spawnAt = spawn,
        channel = CHANNEL,
        radius = RADIUS,
        tolerance = RADIUS - 100,
        lateBy = LATE_BY,
        pickupFor = PICKUP_FOR
    }
end
--- The wisdom spawn a trip now would be for: the next fill, or one that filled under LATE_BY s ago.
local function spawnNow(now)
    return Runes.NextSpawn("wisdom", now - LATE_BY)
end
--- When to leave lane for `spawn`: the SDK's skill-scaled arrival, less the walk (path factor on the straight line).
function ____exports.LeaveAt(bot, spawn)
    local V = Tasks.Verbs()
    if V == nil then
        return nil
    end
    local u = bot
    local plan = planFor(bot, spawn)
    local d = GetUnitToLocationDistance(
        bot,
        ____exports.ShrineFor(bot:GetTeam())
    )
    return V.runeArriveBy(u, plan) - d * PATH_FACTOR / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
local function danger(bot)
    local enemies = bot:GetNearbyHeroes(DANGER_RADIUS, true, BotMode.None) or ({})
    local allies = bot:GetNearbyHeroes(DANGER_RADIUS, false, BotMode.None) or ({})
    if #enemies > #allies then
        return "outnumbered"
    end
    if bot:WasRecentlyDamagedByAnyHero(2) and bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ) < DANGER_HP then
        return "damaged"
    end
    return nil
end
local function score(bot)
    local pid = bot:GetPlayerID()
    local trip = trips[pid]
    if trip ~= nil and trip.ended == nil then
        if DotaTime() <= trip.spawn + PICKUP_FOR then
            return SCORE
        end
        close(bot, trip, {success = false, reason = "timeout", message = "expired"}, nil)
        return nil
    end
    if not bot:IsAlive() or WISDOM_POSITIONS[LaneConfig.PositionOf(bot) or 0] ~= true then
        return nil
    end
    local now = DotaTime()
    local spawn = spawnNow(now)
    if spawn == math.huge or doneFor[pid] == spawn then
        return nil
    end
    local leave = ____exports.LeaveAt(bot, spawn)
    if leave == nil or now < leave then
        return nil
    end
    if (Busy.IsBusy(bot, spawn)) or not (Busy.LaneCanSpare(bot, false)) or danger(bot) ~= nil then
        return nil
    end
    return SCORE
end
local body = __TS__Generator(function(bot, ctx)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local ____opt_0 = trips[pid]
    local spawn = ____opt_0 and ____opt_0.spawn or spawnNow(now)
    if doneFor[pid] == spawn and (trips[pid] == nil or trips[pid].ended ~= nil) then
        return ctx.fail("no_target", "done")
    end
    if trips[pid] == nil or trips[pid].ended ~= nil then
        trips[pid] = {
            team = bot:GetTeam(),
            spawn = spawn,
            startedAt = now
        }
    end
    local trip = trips[pid]
    local hooks = {
        label = function(l)
            ctx.label(l)
            if l == "wait" or l == "channel" and trip.arrivedAt == nil then
                trip.arrivedAt = DotaTime()
            end
            if l == "channel" then
                trip.channelAt = DotaTime()
            end
        end,
        urgent = ctx.urgent
    }
    return __TS__DelegatedYield(Tasks.Verbs().runeRun(
        bot,
        planFor(bot, spawn),
        hooks
    ))
end)
local function ended(bot, r, info)
    local trip = trips[bot:GetPlayerID()]
    if trip == nil or trip.ended ~= nil then
        return
    end
    if r.reason == "preempted" and DotaTime() <= trip.spawn + LATE_BY then
        return
    end
    close(bot, trip, r, info.label)
end
--- Bots not owning `rotate` keep the shadow score (slice 2: OHA's power-rune rotation or the mid's rune claim).
function ____exports.Spec(bot, owned, shadow)
    return {
        name = ____exports.NAME,
        kind = "job",
        host = BotMode.Rune,
        tier = "TRANSITION",
        floor = SCORE,
        preemptAfter = 1,
        score = function()
            if owned == nil or owned(bot, ____exports.NAME) then
                return score(bot)
            end
            local ____temp_5
            if shadow ~= nil then
                ____temp_5 = shadow(bot)
            else
                ____temp_5 = nil
            end
            return ____temp_5
        end,
        guard = function() return danger(bot) end,
        onEnd = function(r, info) return ended(bot, r, info) end,
        body = function(ctx) return body(bot, ctx) end
    }
end
--- The bot is on (or committed to) a shrine trip for the current fill: OHA's own wisdom logic leaves the shrine to it.
function ____exports.OnTrip(bot)
    local trip = trips[bot:GetPlayerID()]
    return trip ~= nil and trip.ended == nil
end
--- Some ally of `team` is on a shrine trip: the shrine is taken for this fill.
function ____exports.ShrineTaken(team)
    for ____, trip in pairs(trips) do
        if trip ~= nil and trip.ended == nil and trip.team == team then
            return true
        end
    end
    return false
end
return ____exports
