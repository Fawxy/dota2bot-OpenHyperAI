--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local FarmPattern = require(GetScriptDirectory().."/FunLib/humaniser/farm_pattern")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
____exports.NAME = "farm"
--- Shadow (slice 2) scores, kept so ownership changes nothing but who executes the trip.
local TRIP = 0.7
local RETURN_REORDER = 0.5
local RETURN_MOVED = 200
--- Runs `g` until it ends or `stop()` says the trip it serves is over (OHA's Desire ended or redirected it).
local ____until = __TS__Generator(function(g, stop)
    while true do
        if stop() then
            return {success = false, reason = "interrupted", message = "trip-changed"}
        end
        local s = g:next()
        if s.done then
            return s.value or ({success = true, reason = "ok"})
        end
        coroutine.yield()
    end
end)
local body = __TS__Generator(function(bot, ctx)
    local V = Tasks.Verbs()
    local u = bot
    local s = FarmPattern.Settings()
    local lastFront
    local orderedAt = -math.huge
    while true do
        do
            local __continue7
            repeat
                local trip = FarmPattern.Live(bot)
                if trip == nil or trip.sdk ~= true then
                    ctx.label("idle")
                    coroutine.yield()
                    __continue7 = true
                    break
                end
                if trip.phase == "stack" then
                    ctx.label("stack")
                    if CampJobs.Active(bot) then
                        CampJobs.Think(bot)
                    else
                        FarmPattern.Exec.Stacked(bot, trip)
                    end
                    coroutine.yield()
                    __continue7 = true
                    break
                end
                if trip.phase == "return" then
                    ctx.label("return")
                    local front = GetLaneFrontLocation(trip.team, trip.lane, 0)
                    local now = DotaTime()
                    if lastFront == nil or now - orderedAt >= RETURN_REORDER or math.abs(front.x - lastFront.x) + math.abs(front.y - lastFront.y) > RETURN_MOVED then
                        bot:Action_MoveToLocation(front)
                        lastFront = front
                        orderedAt = now
                    end
                    coroutine.yield()
                    __continue7 = true
                    break
                end
                local spawner = Camps.SpawnerByIdx(trip.campIdx)
                if spawner == nil then
                    FarmPattern.Exec.ToReturn(bot, trip, "no-camp")
                    __continue7 = true
                    break
                end
                local camp = trip.campIdx
                local hooks = {
                    label = function(l)
                        ctx.label(l)
                        if l == "farm" then
                            trip.phase = "farm"
                        end
                    end,
                    urgent = ctx.urgent
                }
                local r = __TS__DelegatedYield(____until(
                    V.clearCamp(
                        u,
                        {
                            at = Camps.BoxCenter(spawner),
                            radius = s.CampRadius,
                            arrive = s.Arrive,
                            search = s.NeutralScan,
                            deadline = trip.leaveBy,
                            onEngage = function(t)
                                if trip.farmFrom == nil then
                                    trip.farmFrom = t
                                end
                            end
                        },
                        hooks
                    ),
                    function() return FarmPattern.Live(bot) ~= trip or trip.campIdx ~= camp or trip.phase == "return" end
                ))
                if FarmPattern.Live(bot) ~= trip or trip.campIdx ~= camp then
                    __continue7 = true
                    break
                end
                if r.success then
                    FarmPattern.Exec.CampDone(bot, trip, r.message == "cleared")
                elseif r.reason == "timeout" then
                    FarmPattern.Exec.ToReturn(bot, trip, "late")
                elseif r.reason ~= "interrupted" then
                    return r
                end
                __continue7 = true
            until true
            if not __continue7 then
                break
            end
        end
    end
end)
--- A posture, as slice 2's shadow `farm`: `shadow` (FarmScore) scores it, so the state is chosen exactly as before.
-- Only FarmPattern's Think steps the body, and only for a trip it started as `sdk`; outside trips the body idles.
function ____exports.Spec(bot, shadow)
    return {
        name = ____exports.NAME,
        kind = "posture",
        host = BotMode.Farm,
        tier = "CAMP_JOB",
        floor = 0,
        preemptAfter = FarmPattern.Settings().PreemptAfter,
        score = function()
            local trip = FarmPattern.Live(bot)
            if trip ~= nil and trip.sdk == true then
                return TRIP
            end
            return shadow(bot)
        end,
        body = function(ctx) return body(bot, ctx) end
    }
end
return ____exports
