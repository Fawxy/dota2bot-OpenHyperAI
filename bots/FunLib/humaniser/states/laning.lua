--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local LaneSpot = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_spot")
____exports.NAME = "laning"
--- Beyond this the body reports `walk`, within `NEAR` it reports `hold` (with hysteresis between them).
local NEAR = 600
local FAR = 1200
--- A last-hit attempt is dropped when it would take the bot this far from its spot.
local LEASH = 900
local DEFAULTS = {Spot = "oha", LastHit = {}, LastHitWithin = 1}
function ____exports.Settings()
    local ____opt_0 = Config.Get().States
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0.Laning
    end
    local s = ____opt_0
    return {Spot = s and s.Spot or DEFAULTS.Spot, LastHit = s and s.LastHit or DEFAULTS.LastHit, LastHitWithin = s and s.LastHitWithin or DEFAULTS.LastHitWithin}
end
local spots = {}
function ____exports.SetSpot(bot, fn)
    spots[bot:GetPlayerID()] = fn
end
local function ohaSpot(bot)
    local fn = spots[bot:GetPlayerID()]
    if fn == nil then
        return nil
    end
    local ok, v = pcall(fn)
    local ____ok_8
    if ok then
        ____ok_8 = v
    else
        ____ok_8 = nil
    end
    return ____ok_8
end
function ____exports.RoleOf(bot)
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 4 and "support" or "core"
end
local spotCache = {}
--- The spot the body holds this frame (cached per frame: holdAt and its exits read it several times).
function ____exports.Spot(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local c = spotCache[pid]
    if c ~= nil and c.t == now then
        return c.v
    end
    local v = ohaSpot(bot)
    local info
    if ____exports.Settings().Spot == "sdk" then
        local ok, res = pcall(
            LaneSpot.Compute,
            bot,
            ____exports.RoleOf(bot)
        )
        if ok and res ~= nil then
            info = res
            v = res.spot
        end
    end
    spotCache[pid] = {t = now, v = v, info = info}
    return v
end
--- The last computed SDK spot details for telemetry, if any.
function ____exports.SpotInfo(bot)
    local ____opt_9 = spotCache[bot:GetPlayerID()]
    return ____opt_9 and ____opt_9.info
end
--- Whether the body takes this bot's last hits and denies (read every frame by mode_laning_generic.lua).
function ____exports.OwnsLastHit(bot)
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil then
        return false
    end
    for ____, p in ipairs(____exports.Settings().LastHit) do
        if p == pos then
            return true
        end
    end
    return false
end
local function distTo(bot, p)
    return p ~= nil and GetUnitToLocationDistance(bot, p) or nil
end
local function enemyHeroNear(bot, r)
    for ____, h in ipairs(bot:GetNearbyHeroes(r, true, BotMode.None)) do
        if h:IsAlive() then
            return true
        end
    end
    return false
end
local body = __TS__Generator(function(bot, ctx)
    local function spot()
        return ____exports.Spot(bot)
    end
    local sdk = ____exports.Settings().Spot == "sdk"
    local hold = sdk and ({
        tolerance = 40,
        repath = 1.05,
        jitter = 0.85,
        scatter = 130,
        step = {50, 150},
        follow = 150,
        hold = "state:laning"
    }) or ({
        tolerance = 100,
        repath = 1,
        jitter = 0.3,
        scatter = 50,
        hold = "state:laning"
    })
    local verbs = Tasks.Verbs()
    local target
    local function pick()
        if verbs == nil or not ____exports.OwnsLastHit(bot) or (distTo(
            bot,
            ____exports.Spot(bot)
        ) or 0) > FAR then
            return false
        end
        target = verbs.nextLastHit(
            bot,
            {within = ____exports.Settings().LastHitWithin}
        )
        return target ~= nil
    end
    local near = false
    while true do
        do
            local __continue26
            repeat
                ctx.label(near and "hold" or "walk")
                local r = __TS__DelegatedYield(ctx.holdAt(
                    spot,
                    __TS__ObjectAssign(
                        {},
                        hold,
                        {interruptIf = function()
                            local d = distTo(
                                bot,
                                ____exports.Spot(bot)
                            )
                            local ____near_11
                            if near then
                                ____near_11 = (d or 0) > FAR
                            else
                                ____near_11 = (d or math.huge) <= NEAR
                            end
                            if ____near_11 then
                                return true
                            end
                            return pick()
                        end}
                    )
                ))
                if r.reason ~= "interrupted" then
                    return r
                end
                if target == nil then
                    local d = distTo(
                        bot,
                        ____exports.Spot(bot)
                    )
                    near = d ~= nil and d <= (near and FAR or NEAR)
                    __continue26 = true
                    break
                end
                local t = target
                target = nil
                local contested = enemyHeroNear(bot, 1000)
                ctx.label(t.kind)
                local opts = {
                    target = t.creep,
                    maxWait = ____exports.Settings().LastHitWithin + 1,
                    hold = "state:laning",
                    interruptIf = function() return (distTo(
                        bot,
                        ____exports.Spot(bot)
                    ) or 0) > LEASH end
                }
                local res = t.kind == "lasthit" and __TS__DelegatedYield(ctx.lastHit(opts)) or __TS__DelegatedYield(ctx.deny(opts))
                Telemetry.Event(
                    "lh",
                    {
                        {
                            "pid",
                            bot:GetPlayerID()
                        },
                        {"kind", t.kind},
                        {"result", res.success and "ok" or "fail"},
                        {"reason", res.reason},
                        {"ranged", t.ranged},
                        {
                            "eta",
                            math.floor(t.eta * 100) / 100
                        },
                        {"contested", contested}
                    }
                )
                if res.reason == "dead" then
                    return res
                end
                __continue26 = true
            until true
            if not __continue26 then
                break
            end
        end
    end
end)
function ____exports.Spec(bot)
    return {
        name = ____exports.NAME,
        kind = "posture",
        host = BotMode.Laning,
        floor = 0,
        preemptAfter = 3,
        score = function() return Phase.IsLaningFor(bot) and 0.5 or nil end,
        body = function(ctx) return body(bot, ctx) end
    }
end
return ____exports
