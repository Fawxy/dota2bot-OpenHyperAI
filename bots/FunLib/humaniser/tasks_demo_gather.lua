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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local ARRIVE_RADIUS = 500
local arrived = {}
function ____exports.IsActive()
    return Tasks.IsActive() and Config.Get().Tasks.Demo == true
end
local function demoOrder(bot)
    local order = Orders.GetFor(bot)
    if order == nil or order.type ~= "GATHER" and order.type ~= "SMOKE" and order.type ~= "BACK" then
        return nil
    end
    return order
end
local gather = __TS__Generator(function(bot, order, verbs)
    local unit = bot
    local function gone()
        local ____opt_0 = Orders.GetFor(bot)
        return (____opt_0 and ____opt_0.id) ~= order.id
    end
    local walked = __TS__DelegatedYield(verbs.walkTo(
        unit,
        Orders.OrderLocation(order),
        {
            tolerance = ARRIVE_RADIUS,
            timeout = order.expiresAt - GameTime() + 1,
            interruptIf = gone
        }
    ))
    if not walked.success then
        return walked
    end
    return __TS__DelegatedYield(verbs.wait(
        unit,
        order.expiresAt - GameTime(),
        {interruptIf = function() return gone() and GameTime() < order.expiresAt end}
    ))
end)
--- The executor's GATHER/SMOKE/BACK desire: the order floor until arrival, nothing while within 2x the radius.
function ____exports.Desire(bot)
    local order = demoOrder(bot)
    local ____temp_2
    if order ~= nil then
        ____temp_2 = Orders.OrderLocation(order)
    else
        ____temp_2 = nil
    end
    local loc = ____temp_2
    if order == nil or loc == nil then
        return nil
    end
    local dist = GetUnitToLocationDistance(bot, loc)
    if arrived[bot:GetPlayerID()] == order.id or dist <= ARRIVE_RADIUS then
        arrived[bot:GetPlayerID()] = order.id
        if dist <= ARRIVE_RADIUS * 2 then
            return nil
        end
    end
    return Orders.DesireFloor(bot, BotMode.Assemble)
end
--- Steps the running task, or starts one for the bot's order. Returns false when the legacy Think should act.
function ____exports.Think(bot)
    if Tasks.Step(bot, BotMode.Assemble) then
        return true
    end
    local order = demoOrder(bot)
    local verbs = Tasks.Verbs()
    if order == nil or verbs == nil or Orders.OrderLocation(order) == nil then
        return false
    end
    if not Tasks.Start(
        bot,
        {
            name = "gather:" .. tostring(order.id),
            host = BotMode.Assemble
        },
        function() return gather(bot, order, verbs) end
    ) then
        return false
    end
    return Tasks.Step(bot, BotMode.Assemble)
end
return ____exports
