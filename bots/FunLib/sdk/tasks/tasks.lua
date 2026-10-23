-- Vendored from dota-bot-sdk packages/lua-tasks @ ef0b2d1a8f4beeb2ab821d2ddce40f3737a86d56. Do not edit; run npm run vendor.
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]

local ____modules = {}
local ____moduleCache = {}
local ____originalRequire = require
local function require(file, ...)
    if ____moduleCache[file] then
        return ____moduleCache[file].value
    end
    if ____modules[file] then
        local module = ____modules[file]
        local value = nil
        if (select("#", ...) > 0) then value = module(...) else value = module(file) end
        ____moduleCache[file] = { value = value }
        return value
    else
        if ____originalRequire then
            return ____originalRequire(file)
        else
            error("module '" .. file .. "' not found")
        end
    end
end
____modules = {
["types"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
return ____exports
 end,
["abort"] = function(...) 
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
local TAG = {}
--- Ends the running task with `result` from any generator depth; the runner finishes it as if returned.
function ____exports.abortWith(result)
    local thrown = {tag = TAG, result = result}
    error(thrown, 0)
end
function ____exports.abort(reason, message)
    return ____exports.abortWith({success = false, reason = reason, message = message})
end
--- The carried result if `err` was raised by `abort`/`must`, else undefined.
function ____exports.aborted(err)
    if type(err) ~= "table" then
        return nil
    end
    local t = err
    return rawequal(t.tag, TAG) and t.result or nil
end
--- Runs `g` and returns its result if it succeeded; a failure ends the whole task with that result, its message
-- replaced by `message` when given.
____exports.must = __TS__Generator(function(g, message)
    local r = __TS__DelegatedYield(g)
    if r == nil then
        return {success = true, reason = "ok"}
    end
    if not r.success then
        ____exports.abortWith(message == nil and r or ({success = false, reason = r.reason, message = message}))
    end
    return r
end)
return ____exports
 end,
["adapter"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local current
--- Host integration: OHA (or any host) injects claims, etiquette, time, logging and the kill switch here.
function ____exports.init(a)
    current = a
end
function ____exports.get()
    return current
end
return ____exports
 end,
["skill"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____adapter = require("adapter")
local get = ____adapter.get
--- Last-hit error half-width (fraction of own damage) at skill 0 and 1: OHA LastHitSkill ErrorLow/ErrorHigh.
____exports.LAST_HIT_ERROR_LOW = 0.15
____exports.LAST_HIT_ERROR_HIGH = 0.02
--- Seconds of swing-timing error per unit of last-hit error: 0.02 -> 0.04 s, 0.15 -> 0.3 s.
____exports.TIMING_PER_ERROR = 2
--- Chance per creep of a lapse (a clearly late swing) at skill 0 and 1, when the profile has no `lapse`.
____exports.LAPSE_LOW = 0.15
____exports.LAPSE_HIGH = 0.01
function ____exports.lerp(low, high, t)
    return low + (high - low) * t
end
--- Uniform [0, 1) from the adapter's `random` (tests seed it), else `math.random`.
function ____exports.random()
    local a = get()
    if a ~= nil and a.random ~= nil then
        return a.random()
    end
    return math.random()
end
--- The bot's skill in [0, 1], read through the adapter every call; 1 when the host gives none.
function ____exports.of(bot)
    local a = get()
    local s = a ~= nil and a.skill ~= nil and a.skill(bot) or nil
    if s == nil then
        return 1
    end
    return math.max(
        0,
        math.min(1, s)
    )
end
function ____exports.profile(bot)
    local a = get()
    local p = a ~= nil and a.profile ~= nil and a.profile(bot) or nil
    return p or ({react = 0, jitter = 0})
end
--- `secs` scaled by a uniform factor in 1 +- jitter/2 of the bot's profile.
function ____exports.jitter(bot, secs)
    local j = ____exports.profile(bot).jitter
    return secs * (1 - j / 2 + ____exports.random() * j)
end
--- One sampled reaction delay: the profile's `react` +- jitter/2. 0 when the host gives no profile.
function ____exports.react(bot)
    return ____exports.jitter(
        bot,
        ____exports.profile(bot).react
    )
end
--- Half-width of the per-creep damage-estimate error: the host's `lastHitError`, else lerped from skill.
function ____exports.lastHitError(bot)
    local a = get()
    if a ~= nil and a.lastHitError ~= nil then
        return math.max(
            0,
            a.lastHitError(bot)
        )
    end
    return ____exports.lerp(
        ____exports.LAST_HIT_ERROR_LOW,
        ____exports.LAST_HIT_ERROR_HIGH,
        ____exports.of(bot)
    )
end
function ____exports.lapseChance(bot)
    return ____exports.profile(bot).lapse or ____exports.lerp(
        ____exports.LAPSE_LOW,
        ____exports.LAPSE_HIGH,
        ____exports.of(bot)
    )
end
--- Gaussian sigma (s) of a timed action's error at skill 0 and 1: OHA lane_config Curves.JitterSigma.
____exports.TIMING_SIGMA_LOW = 1.5
____exports.TIMING_SIGMA_HIGH = 0.2
--- Draws past this many sigmas are clamped, so one roll can never wreck a job outright.
____exports.TIMING_CLAMP = 2.5
--- Standard normal (Box-Muller) from `random()`.
function ____exports.gauss()
    local u1 = math.max(
        0.000001,
        ____exports.random()
    )
    local u2 = ____exports.random()
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end
function ____exports.timingSigma(bot)
    return ____exports.lerp(
        ____exports.TIMING_SIGMA_LOW,
        ____exports.TIMING_SIGMA_HIGH,
        ____exports.of(bot)
    )
end
--- One sampled timing error in seconds for a timed action (pull/stack aggro, rune arrival); positive is late.
function ____exports.timingError(bot)
    local s = ____exports.timingSigma(bot)
    return math.max(
        -____exports.TIMING_CLAMP * s,
        math.min(
            ____exports.TIMING_CLAMP * s,
            ____exports.gauss() * s
        )
    )
end
return ____exports
 end,
["verbs"] = function(...) 
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
local ok, fail, now, expired, dist
local ____adapter = require("adapter")
local get = ____adapter.get
local ____skill = require("skill")
local random = ____skill.random
function ok()
    return {success = true, reason = "ok"}
end
function fail(reason)
    return {success = false, reason = reason}
end
function now()
    return get().now()
end
function expired(deadline)
    return deadline ~= nil and now() >= deadline
end
function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- Walks through `points` in order. Each frame, every leading waypoint already within tolerance is skipped,
-- so a bot that starts at (or overshoots onto) later waypoints never walks back. `timeout` runs from the
-- start of the walk; stuck detection restarts at each new waypoint and is disabled by `stuckSecs = math.huge`.
____exports.walkPath = __TS__Generator(function(bot, points, opts)
    if opts == nil then
        opts = {}
    end
    local tolerance = opts.tolerance or 150
    local timeout = opts.timeout or 10
    local stuckSecs = opts.stuckSecs or 1.5
    local start = now()
    local i = 0
    local tracking = -1
    local prev = start
    local best = 0
    local stuckClock = 0
    while true do
        local t = now()
        if not bot:IsAlive() then
            return fail("dead")
        end
        while i < #points and dist(
            bot:GetLocation(),
            points[i + 1]
        ) <= tolerance do
            i = i + 1
        end
        if i >= #points then
            return ok()
        end
        if opts.interruptIf ~= nil and opts.interruptIf() then
            return fail("interrupted")
        end
        if t - start > timeout or expired(opts.deadline) then
            return fail("timeout")
        end
        local d = dist(
            bot:GetLocation(),
            points[i + 1]
        )
        if tracking ~= i then
            tracking = i
            best = d
            stuckClock = 0
        elseif d <= best - 25 then
            best = d
            stuckClock = 0
        else
            local ____this_1
            ____this_1 = bot
            local ____opt_0 = ____this_1.IsStunned
            local ____temp_2 = ____opt_0 and ____opt_0(____this_1)
            if ____temp_2 == nil then
                ____temp_2 = false
            end
            if not ____temp_2 then
                stuckClock = stuckClock + (t - prev)
            end
        end
        prev = t
        if stuckClock >= stuckSecs then
            return fail("stuck")
        end
        bot:Action_MoveToLocation(points[i + 1])
        coroutine.yield()
    end
end)
____exports.walkTo = __TS__Generator(function(bot, loc, opts)
    if opts == nil then
        opts = {}
    end
    return __TS__DelegatedYield(____exports.walkPath(bot, {loc}, opts))
end)
____exports.wait = __TS__Generator(function(bot, secs, opts)
    if opts == nil then
        opts = {}
    end
    local start = now()
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if opts.interruptIf ~= nil and opts.interruptIf() then
            return fail("interrupted")
        end
        if now() - start >= secs then
            return ok()
        end
        if expired(opts.deadline) then
            return fail("timeout")
        end
        coroutine.yield()
    end
end)
local function hold(bot, tag)
    if tag == nil then
        return
    end
    local a = get()
    if a.hold ~= nil then
        a.hold(bot, tag)
    end
end
--- Finishes as soon as game time reaches `t`, on the first resume without yielding if it already has.
____exports.waitUntil = __TS__Generator(function(bot, t, opts)
    if opts == nil then
        opts = {}
    end
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if now() >= t then
            return ok()
        end
        if opts.interruptIf ~= nil and opts.interruptIf() then
            return fail("interrupted")
        end
        if expired(opts.deadline) then
            return fail("timeout")
        end
        hold(bot, opts.hold)
        coroutine.yield()
    end
end)
____exports.retreatTo = __TS__Generator(function(bot, opts)
    return __TS__DelegatedYield(____exports.walkTo(bot, opts.safe, {tolerance = opts.tolerance or 300, timeout = opts.timeout or 20, stuckSecs = 3}))
end)
local function targetLost(t)
    local ____this_4
    ____this_4 = t
    local ____opt_3 = ____this_4.IsNull
    local ____temp_5 = ____opt_3 and ____opt_3(____this_4)
    if ____temp_5 == nil then
        ____temp_5 = false
    end
    local ____temp_9 = ____temp_5 or not t:IsAlive()
    if not ____temp_9 then
        local ____this_7
        ____this_7 = t
        local ____opt_6 = ____this_7.CanBeSeen
        local ____temp_8 = ____opt_6 and ____opt_6(____this_7)
        if ____temp_8 == nil then
            ____temp_8 = true
        end
        ____temp_9 = not ____temp_8
    end
    return ____temp_9
end
--- Orders a queued attack on `pick()` and finishes `ok` once it is confirmed to have landed: the bot's last
-- attack time rose past its reading at the order (never compared with another clock), the target is
-- attacking the bot, or `opts.confirmed()`. A target that dies or vanishes before confirmation is dropped and
-- a new one picked and ordered the next frame, which restarts the `confirmFor` clock.
____exports.attackAndConfirm = __TS__Generator(function(bot, pick, opts)
    if bot.GetLastAttackTime == nil then
        return fail("unsupported")
    end
    local start = now()
    local target
    local baseline = 0
    local orderedAt = 0
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if expired(opts.deadline) then
            return fail("timeout")
        end
        if target == nil then
            target = pick()
            if target ~= nil then
                bot:Action_AttackUnit(target, true)
                baseline = bot:GetLastAttackTime()
                orderedAt = now()
            elseif now() - start >= opts.findFor then
                return fail("no_target")
            elseif opts.searchAt ~= nil then
                bot:Action_MoveToLocation(opts.searchAt)
            end
        else
            local ____temp_12 = bot:GetLastAttackTime() > baseline
            if not ____temp_12 then
                local ____this_11
                ____this_11 = target
                local ____opt_10 = ____this_11.GetAttackTarget
                ____temp_12 = (____opt_10 and ____opt_10(____this_11)) == bot
            end
            local ____temp_12_16 = ____temp_12
            if not ____temp_12_16 then
                local ____opt_13 = opts.confirmed
                local ____temp_15 = ____opt_13 and ____opt_13()
                if ____temp_15 == nil then
                    ____temp_15 = false
                end
                ____temp_12_16 = ____temp_15
            end
            if ____temp_12_16 then
                return ok()
            elseif now() - orderedAt >= opts.confirmFor then
                return fail("missed")
            elseif targetLost(target) then
                target = nil
            else
                hold(bot, opts.hold)
            end
        end
        coroutine.yield()
    end
end)
local function vec(x, y, z)
    local make = get().vector
    return make ~= nil and make(x, y, z or 0) or ({x = x, y = y, z = z})
end
local function scattered(p, r)
    if r <= 0 then
        return p
    end
    local a = random() * 2 * math.pi
    local d = random() * r
    return vec(
        p.x + math.cos(a) * d,
        p.y + math.sin(a) * d,
        p.z
    )
end
local function stepped(from, p, r, min, max)
    local len = min + random() * (max - min)
    local a = random() * 2 * math.pi
    local x = from.x + math.cos(a) * len
    local y = from.y + math.sin(a) * len
    if dist({x = x, y = y}, p) > r then
        local d = dist(from, p)
        if d > 0.000001 then
            x = from.x + (p.x - from.x) / d * len
            y = from.y + (p.y - from.y) / d * len
        end
        local e = dist({x = x, y = y}, p)
        if e > r then
            x = p.x + (x - p.x) / e * r
            y = p.y + (y - p.y) / e * r
        end
    end
    return vec(x, y, p.z)
end
--- Posture verb: keeps the bot within `tolerance` of `point()` (re-read every frame) and never ends `ok` by itself.
-- A new spot is picked when the point moves more than half the tolerance or every `repath` s (+jitter). An order
-- is issued on every resume (walk to the spot, or stand on the bot's own location), so an order the host gave
-- between resumes never sticks. `point()` returning undefined stands the bot still.
____exports.holdAt = __TS__Generator(function(bot, point, opts)
    if opts == nil then
        opts = {}
    end
    local tolerance = opts.tolerance or 100
    local repath = opts.repath or 1
    local jitter = opts.jitter or 0.3
    local scatter = opts.scatter or 50
    local follow = opts.follow or tolerance / 2
    local anchor
    local spot
    local nextPick = 0
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if opts.interruptIf ~= nil and opts.interruptIf() then
            return fail("interrupted")
        end
        if expired(opts.deadline) then
            return fail("timeout")
        end
        local t = now()
        local p = point()
        if p == nil then
            anchor = nil
            bot:Action_MoveToLocation(bot:GetLocation())
            hold(bot, opts.hold)
        else
            if anchor == nil or t >= nextPick or dist(p, anchor) > follow then
                local step = opts.step
                local here = bot:GetLocation()
                spot = step ~= nil and dist(here, p) <= scatter + tolerance and stepped(
                    here,
                    p,
                    scatter,
                    step[1],
                    step[2]
                ) or scattered(p, scatter)
                anchor = p
                nextPick = t + repath * (1 + jitter * (random() - 0.5))
            end
            if dist(
                bot:GetLocation(),
                spot
            ) > tolerance then
                bot:Action_MoveToLocation(spot)
            else
                bot:Action_MoveToLocation(bot:GetLocation())
                hold(bot, opts.hold)
            end
        end
        coroutine.yield()
    end
end)
return ____exports
 end,
["verbs_cast"] = function(...) 
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
local ____adapter = require("adapter")
local get = ____adapter.get
local ____verbs = require("verbs")
local walkTo = ____verbs.walkTo
local function ok()
    return {success = true, reason = "ok"}
end
local function fail(reason, message)
    return {success = false, reason = reason, message = message}
end
local function now()
    return get().now()
end
local function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function stopped(opts)
    if opts.interruptIf ~= nil and opts.interruptIf() then
        return fail("interrupted")
    end
    if opts.deadline ~= nil and now() >= opts.deadline then
        return fail("timeout")
    end
    return nil
end
local function targetLost(t)
    local ____this_1
    ____this_1 = t
    local ____opt_0 = ____this_1.IsNull
    local ____temp_2 = ____opt_0 and ____opt_0(____this_1)
    if ____temp_2 == nil then
        ____temp_2 = false
    end
    local ____temp_6 = ____temp_2 or not t:IsAlive()
    if not ____temp_6 then
        local ____this_4
        ____this_4 = t
        local ____opt_3 = ____this_4.CanBeSeen
        local ____temp_5 = ____opt_3 and ____opt_3(____this_4)
        if ____temp_5 == nil then
            ____temp_5 = true
        end
        ____temp_6 = not ____temp_5
    end
    return ____temp_6
end
local REORDER_SECS = 0.5
local CHANNEL_SLACK = 0.25
local function inPhase(bot, ability)
    local ____this_8
    ____this_8 = ability
    local ____opt_7 = ____this_8.IsInAbilityPhase
    local ____temp_11 = ____opt_7 and ____opt_7(____this_8)
    if ____temp_11 == nil then
        local ____this_10
        ____this_10 = bot
        local ____opt_9 = ____this_10.IsCastingAbility
        ____temp_11 = ____opt_9 and ____opt_9(____this_10)
    end
    local ____temp_11_12 = ____temp_11
    if ____temp_11_12 == nil then
        ____temp_11_12 = false
    end
    return ____temp_11_12
end
local function channeling(bot, ability)
    local ____this_14
    ____this_14 = ability
    local ____opt_13 = ____this_14.IsChanneling
    local ____temp_17 = ____opt_13 and ____opt_13(____this_14)
    if ____temp_17 == nil then
        local ____this_16
        ____this_16 = bot
        local ____opt_15 = ____this_16.IsChanneling
        ____temp_17 = ____opt_15 and ____opt_15(____this_16)
    end
    return ____temp_17
end
local function orderFor(bot, ability, opts)
    local target = opts.target
    if target ~= nil then
        if bot.Action_UseAbilityOnEntity == nil then
            return nil
        end
        return function() return bot:Action_UseAbilityOnEntity(ability, target) end
    end
    local at = opts.at
    if at ~= nil then
        if bot.Action_UseAbilityOnLocation == nil then
            return nil
        end
        return function() return bot:Action_UseAbilityOnLocation(ability, at) end
    end
    if bot.Action_UseAbility == nil then
        return nil
    end
    return function() return bot:Action_UseAbility(ability) end
end
--- Casts `ability` and finishes `ok` only once its effect is seen: the cooldown rose above its reading at the
-- order, or mana fell by at least half the mana cost. A cast phase that is seen and then ends without that
-- effect (two frames in a row, allowing the effect to show a frame late) fails `interrupted`; a unit target
-- that dies or vanishes first fails `no_target`.
-- 
-- Re-ordering: while neither the cast phase nor the effect has been seen, the order is re-issued every
-- 0.5 s (another order in the same frame may have replaced it). Never once the phase is seen, since
-- re-issuing during the cast point risks restarting it, and only when a phase signal exists at all.
-- Failing (including `interruptIf`/`deadline`) does not cancel a cast in progress in-game.
-- 
-- The default `timeout` assumes the caster is already in range and facing; pass a longer one when the order
-- has to walk the bot into cast range first.
-- 
-- Channels (`channel: true`): after the effect, waits for the channel; ends `ok` if it ran within 0.25 s of
-- `GetChannelTime()`, else `interrupted`. Early ends shorter than that slack are indistinguishable from
-- natural ones. A target dying mid-channel counts as an early end.
-- 
-- UNVERIFIED in-game: that `GetCooldownTimeRemaining` / mana drop are visible within a frame of the cast
-- point ending; that `IsInAbilityPhase` is true for the whole cast point; that a stun-cancelled cast starts
-- no cooldown and costs no mana; that re-issuing the same cast order before its phase starts is harmless;
-- that channelled abilities start their cooldown when the channel starts; `IsChanneling` on the handle
-- (falls back to the unit's). Abilities with neither cooldown nor mana cost (and not channelled) can never
-- be confirmed and time out; charge-based abilities may not raise the cooldown and rely on mana.
____exports.cast = __TS__Generator(function(bot, ability, opts)
    if opts == nil then
        opts = {}
    end
    local ____temp_21 = ability == nil
    if not ____temp_21 then
        local ____this_19
        ____this_19 = ability
        local ____opt_18 = ____this_19.IsNull
        local ____temp_20 = ____opt_18 and ____opt_18(____this_19)
        if ____temp_20 == nil then
            ____temp_20 = false
        end
        ____temp_21 = ____temp_20
    end
    if ____temp_21 then
        return fail("not_castable", "no ability")
    end
    local order = orderFor(bot, ability, opts)
    if order == nil then
        return fail("unsupported")
    end
    local ____this_23
    ____this_23 = ability
    local ____opt_22 = ____this_23.GetManaCost
    local cost = ____opt_22 and ____opt_22(____this_23) or 0
    local canSeeChannel = channeling(bot, ability) ~= nil and ability.GetChannelTime ~= nil
    if opts.channel == true and not canSeeChannel then
        return fail("unsupported")
    end
    local canSeeEffect = ability.GetCooldownTimeRemaining ~= nil or bot.GetMana ~= nil and cost > 0
    if not canSeeEffect then
        return fail("unsupported")
    end
    local canSeePhase = ability.IsInAbilityPhase ~= nil or bot.IsCastingAbility ~= nil
    if not bot:IsAlive() then
        return fail("dead")
    end
    local early = stopped(opts)
    if early ~= nil then
        return early
    end
    if not ability:IsFullyCastable() then
        return fail("not_castable")
    end
    if opts.target ~= nil and targetLost(opts.target) then
        return fail("no_target")
    end
    local start = now()
    local ____opts_timeout_26 = opts.timeout
    if ____opts_timeout_26 == nil then
        local ____this_25
        ____this_25 = ability
        local ____opt_24 = ____this_25.GetCastPoint
        ____opts_timeout_26 = (____opt_24 and ____opt_24(____this_25) or 0) + 1
    end
    local timeout = ____opts_timeout_26
    local ____this_28
    ____this_28 = ability
    local ____opt_27 = ____this_28.GetCooldownTimeRemaining
    local cd0 = ____opt_27 and ____opt_27(____this_28)
    local ____this_30
    ____this_30 = bot
    local ____opt_29 = ____this_30.GetMana
    local mana0 = ____opt_29 and ____opt_29(____this_30)
    local function effectSeen()
        local ____this_32
        ____this_32 = ability
        local ____opt_31 = ____this_32.GetCooldownTimeRemaining
        local cd = ____opt_31 and ____opt_31(____this_32)
        if cd ~= nil and cd0 ~= nil and cd > cd0 + 0.05 then
            return true
        end
        local ____this_34
        ____this_34 = bot
        local ____opt_33 = ____this_34.GetMana
        local mana = ____opt_33 and ____opt_33(____this_34)
        return cost > 0 and mana ~= nil and mana0 ~= nil and mana0 - mana >= cost * 0.5
    end
    order()
    local orderedAt = start
    local phaseSeen = false
    local phaseGone = 0
    while true do
        coroutine.yield()
        if not bot:IsAlive() then
            return fail("dead")
        end
        if effectSeen() or opts.channel == true and channeling(bot, ability) == true then
            break
        end
        if opts.target ~= nil and targetLost(opts.target) then
            return fail("no_target", "target lost before cast")
        end
        if inPhase(bot, ability) then
            phaseSeen = true
            phaseGone = 0
        elseif phaseSeen then
            phaseGone = phaseGone + 1
            if phaseGone >= 2 then
                return fail("interrupted", "cast phase cancelled")
            end
        end
        local stop = stopped(opts)
        if stop ~= nil then
            return stop
        end
        if now() - start >= timeout then
            return fail("timeout")
        end
        if canSeePhase and not phaseSeen and now() - orderedAt >= REORDER_SECS and ability:IsFullyCastable() then
            order()
            orderedAt = now()
        end
    end
    if opts.channel ~= true then
        return ok()
    end
    local channelTime = ability:GetChannelTime()
    local castAt = now()
    local channelStart
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        local ch = channeling(bot, ability) == true
        if channelStart == nil then
            if ch then
                channelStart = now()
            elseif now() - castAt > CHANNEL_SLACK then
                return fail("interrupted", "channel never started")
            end
        elseif not ch then
            if now() - channelStart >= channelTime - CHANNEL_SLACK then
                return ok()
            end
            return fail("interrupted", "channel ended early")
        elseif now() - channelStart > channelTime + 1 then
            return fail("timeout", "still channelling past channel time")
        end
        local stop = stopped(opts)
        if stop ~= nil then
            return stop
        end
        coroutine.yield()
    end
end)
local MAIN_SLOTS = 6
local function findMainItem(bot, name)
    if bot.FindItemSlot ~= nil then
        local slot = bot:FindItemSlot(name)
        local ____temp_35
        if slot >= 0 and slot < MAIN_SLOTS then
            ____temp_35 = bot:GetItemInSlot(slot)
        else
            ____temp_35 = nil
        end
        return ____temp_35
    end
    do
        local slot = 0
        while slot < MAIN_SLOTS do
            local item = bot:GetItemInSlot(slot)
            local ____temp_38 = item ~= nil
            if ____temp_38 then
                local ____opt_36 = item.GetName
                ____temp_38 = (____opt_36 and ____opt_36(item)) == name
            end
            if ____temp_38 then
                return item
            end
            slot = slot + 1
        end
    end
    return nil
end
--- Finds `itemName` in the six main inventory slots (backpack, stash, TP and neutral slots are not searched)
-- and casts it with `cast`, so the same options and confirmation apply.
-- UNVERIFIED in-game: that `FindItemSlot` returns the main-slot copy when the bot holds several.
____exports.useItem = __TS__Generator(function(bot, itemName, opts)
    if opts == nil then
        opts = {}
    end
    if bot.GetItemInSlot == nil then
        return fail("unsupported")
    end
    local item = findMainItem(bot, itemName)
    if item == nil then
        return fail("no_item", itemName)
    end
    return __TS__DelegatedYield(____exports.cast(bot, item, opts))
end)
local function dotaGlobal(name)
    return rawget(_G, name)
end
--- Walks to the rune at location constant `rune`, orders `Action_PickUpRune` and finishes `ok` when the
-- rune's status leaves `RUNE_STATUS_AVAILABLE` while we are within `tolerance` having ordered the pick-up
-- (or, with `confirmed`, when that says so). A rune that disappears before then fails `taken_by_other`;
-- one already reported missing fails `no_target` without moving. Re-orders the pick-up every 0.5 s.
-- 
-- Reads the Dota globals `GetRuneStatus`, `GetRuneSpawnLocation` and `RUNE_STATUS_AVAILABLE`/`_MISSING`
-- through `_G`, failing `unsupported` when absent.
-- 
-- UNVERIFIED in-game: that `GetRuneStatus` leaves `AVAILABLE` within a frame of the pick-up; that a rune
-- vanishing while we stand on it with a pick-up ordered was ours (another hero grabbing it at the same
-- moment reads as ok unless `confirmed` is given); that `Action_PickUpRune` is a no-op once it is gone.
____exports.pickUpRune = __TS__Generator(function(bot, rune, opts)
    if opts == nil then
        opts = {}
    end
    local status = dotaGlobal("GetRuneStatus")
    local available = dotaGlobal("RUNE_STATUS_AVAILABLE")
    local missing = dotaGlobal("RUNE_STATUS_MISSING")
    local spawnAt = dotaGlobal("GetRuneSpawnLocation")
    local loc = opts.at or (spawnAt ~= nil and spawnAt(rune) or nil)
    if status == nil or available == nil or missing == nil then
        return fail("unsupported")
    end
    if loc == nil or bot.Action_PickUpRune == nil then
        return fail("unsupported")
    end
    if not bot:IsAlive() then
        return fail("dead")
    end
    if status(rune) == missing then
        return fail("no_target", "rune missing")
    end
    local tolerance = opts.tolerance or 150
    local confirmFor = opts.confirmFor or 2
    local start = now()
    local deadline = start + (opts.timeout or 15)
    local seen = false
    local function gone()
        local s = status(rune)
        if s == available then
            seen = true
        end
        return s == missing or seen and s ~= available
    end
    local function lost()
        return seen and fail("taken_by_other") or fail("no_target", "rune missing")
    end
    local walked = __TS__DelegatedYield(walkTo(
        bot,
        loc,
        {
            tolerance = tolerance,
            timeout = deadline - start,
            stuckSecs = 3,
            interruptIf = function() return gone() or stopped(opts) ~= nil end
        }
    ))
    if not walked.success then
        if walked.reason ~= "interrupted" then
            return walked
        end
        if gone() then
            return lost()
        end
        return stopped(opts) or walked
    end
    if gone() then
        return lost()
    end
    if not seen then
        return fail("no_target", "rune not seen at location")
    end
    local orderedAt = now()
    local firstOrder = orderedAt
    bot:Action_PickUpRune(rune)
    while true do
        coroutine.yield()
        if not bot:IsAlive() then
            return fail("dead")
        end
        if gone() then
            if opts.confirmed ~= nil then
                return opts.confirmed() and ok() or fail("taken_by_other")
            end
            return dist(
                bot:GetLocation(),
                loc
            ) <= tolerance and ok() or fail("taken_by_other")
        end
        local stop = stopped(opts)
        if stop ~= nil then
            return stop
        end
        if now() >= deadline then
            return fail("timeout")
        end
        if now() - firstOrder >= confirmFor then
            return fail("missed")
        end
        if now() - orderedAt >= REORDER_SECS then
            bot:Action_PickUpRune(rune)
            orderedAt = now()
        end
    end
end)
return ____exports
 end,
["lasthit"] = function(...) 
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
local now, dist, gone, nearby, others, isRanged, windupDamage, attackersByTarget, scanAttackers, ACTIVITY_ATTACK, ACTIVITY_ATTACK2, RANGED_ABOVE, CREEP_LAUNCH_OFFSET, QUERY_RADIUS, nearbyCache
local ____adapter = require("adapter")
local get = ____adapter.get
local Skill = require("skill")
function now()
    return get().now()
end
function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function gone(u)
    local ____this_1
    ____this_1 = u
    local ____opt_0 = ____this_1.IsNull
    local ____temp_2 = ____opt_0 and ____opt_0(____this_1)
    if ____temp_2 == nil then
        ____temp_2 = false
    end
    return ____temp_2 or not u:IsAlive() or u:GetLocation() == nil
end
function nearby(bot)
    local id = bot:GetPlayerID()
    local t = now()
    local hit = nearbyCache[id]
    if hit ~= nil and hit.t == t then
        return hit
    end
    local ____t_7 = t
    local ____this_4
    ____this_4 = bot
    local ____opt_3 = ____this_4.GetNearbyLaneCreeps
    local ____temp_8 = ____opt_3 and ____opt_3(____this_4, QUERY_RADIUS, true) or ({})
    local ____this_6
    ____this_6 = bot
    local ____opt_5 = ____this_6.GetNearbyLaneCreeps
    local n = {
        t = ____t_7,
        enemyCreeps = ____temp_8,
        allyCreeps = ____opt_5 and ____opt_5(____this_6, QUERY_RADIUS, false) or ({})
    }
    nearbyCache[id] = n
    return n
end
function others(bot, n)
    if n.others ~= nil then
        return n.others
    end
    local out = {}
    for ____, enemies in ipairs({true, false}) do
        local ____this_10
        ____this_10 = bot
        local ____opt_9 = ____this_10.GetNearbyHeroes
        for ____, h in ipairs(____opt_9 and ____opt_9(____this_10, QUERY_RADIUS, enemies, 0) or ({})) do
            if h.GetLocation ~= nil and h.IsAlive ~= nil then
                out[#out + 1] = h
            end
        end
        local ____this_12
        ____this_12 = bot
        local ____opt_11 = ____this_12.GetNearbyTowers
        for ____, t in ipairs(____opt_11 and ____opt_11(____this_12, QUERY_RADIUS, enemies) or ({})) do
            out[#out + 1] = t
        end
    end
    n.others = out
    return out
end
function isRanged(u)
    local ____this_14
    ____this_14 = u
    local ____opt_13 = ____this_14.GetAttackRange
    local ____temp_17 = (____opt_13 and ____opt_13(____this_14) or 0) > RANGED_ABOVE
    if ____temp_17 then
        local ____this_16
        ____this_16 = u
        local ____opt_15 = ____this_16.GetAttackProjectileSpeed
        ____temp_17 = (____opt_15 and ____opt_15(____this_16) or 0) > 0
    end
    return ____temp_17
end
function windupDamage(a, creep, horizon)
    if a.GetAnimActivity == nil then
        return 0
    end
    local act = a:GetAnimActivity()
    if act ~= ACTIVITY_ATTACK and act ~= ACTIVITY_ATTACK2 then
        return 0
    end
    if a.GetAnimCycle == nil or a.GetAttackPoint == nil then
        return 0
    end
    local cycle = a:GetAnimCycle()
    local point = a:GetAttackPoint()
    if cycle >= point then
        return 0
    end
    local ____temp_20 = point - cycle
    local ____this_19
    ____this_19 = a
    local ____opt_18 = ____this_19.GetSecondsPerAttack
    local t = ____temp_20 * (____opt_18 and ____opt_18(____this_19) or 1)
    if isRanged(a) then
        t = t + math.max(
            0,
            dist(
                a:GetLocation(),
                creep:GetLocation()
            ) - CREEP_LAUNCH_OFFSET
        ) / a:GetAttackProjectileSpeed()
    end
    local ____temp_23
    if t <= horizon then
        local ____this_22
        ____this_22 = a
        local ____opt_21 = ____this_22.GetAttackDamage
        ____temp_23 = ____opt_21 and ____opt_21(____this_22) or 0
    else
        ____temp_23 = 0
    end
    return ____temp_23
end
function attackersByTarget(bot, n)
    if n.byTarget ~= nil then
        return n.byTarget
    end
    local by = {}
    local ____this_25
    ____this_25 = bot
    local ____opt_24 = ____this_25.GetTeam
    local myTeam = ____opt_24 and ____opt_24(____this_25)
    local function add(a)
        if a == bot or gone(a) then
            return
        end
        local ____temp_28 = myTeam ~= nil
        if ____temp_28 then
            local ____this_27
            ____this_27 = a
            local ____opt_26 = ____this_27.GetTeam
            ____temp_28 = (____opt_26 and ____opt_26(____this_27)) ~= myTeam
        end
        local ____temp_28_32 = ____temp_28
        if ____temp_28_32 then
            local ____this_30
            ____this_30 = a
            local ____opt_29 = ____this_30.CanBeSeen
            local ____temp_31 = ____opt_29 and ____opt_29(____this_30)
            if ____temp_31 == nil then
                ____temp_31 = true
            end
            ____temp_28_32 = not ____temp_31
        end
        if ____temp_28_32 then
            return
        end
        local ____temp_36 = myTeam == nil
        if ____temp_36 then
            local ____this_34
            ____this_34 = a
            local ____opt_33 = ____this_34.CanBeSeen
            local ____temp_35 = ____opt_33 and ____opt_33(____this_34)
            if ____temp_35 == nil then
                ____temp_35 = true
            end
            ____temp_36 = not ____temp_35
        end
        if ____temp_36 then
            return
        end
        local ____this_38
        ____this_38 = a
        local ____opt_37 = ____this_38.GetAttackTarget
        local target = ____opt_37 and ____opt_37(____this_38)
        if target == nil or target == nil then
            return
        end
        local list = by[target]
        if list == nil then
            list = {}
            by[target] = list
        end
        list[#list + 1] = a
    end
    for ____, c in ipairs(n.enemyCreeps) do
        add(c)
    end
    for ____, c in ipairs(n.allyCreeps) do
        add(c)
    end
    for ____, o in ipairs(others(bot, n)) do
        add(o)
    end
    n.byTarget = by
    return by
end
function scanAttackers(bot, creep, horizon)
    local raw = 0
    local dps = 0
    local ____this_48
    ____this_48 = creep
    local ____opt_47 = ____this_48.GetIncomingTrackingProjectiles
    for ____, p in ipairs(____opt_47 and ____opt_47(____this_48) or ({})) do
        local c = p.caster
        local ____temp_42 = p.is_attack == true and c ~= nil and c ~= nil and c ~= bot
        if ____temp_42 then
            local ____opt_39 = c.IsNull
            local ____temp_41 = ____opt_39 and ____opt_39(c)
            if ____temp_41 == nil then
                ____temp_41 = false
            end
            ____temp_42 = not ____temp_41
        end
        if ____temp_42 then
            local ____opt_43 = c.GetAttackProjectileSpeed
            local speed = ____opt_43 and ____opt_43(c) or 0
            if speed > 0 and dist(
                p.location,
                creep:GetLocation()
            ) / speed <= horizon then
                local ____opt_45 = c.GetAttackDamage
                raw = raw + (____opt_45 and ____opt_45(c) or 0)
            end
        end
    end
    for ____, a in ipairs(attackersByTarget(
        bot,
        nearby(bot)
    )[creep] or ({})) do
        do
            local __continue49
            repeat
                if a == creep then
                    __continue49 = true
                    break
                end
                raw = raw + windupDamage(a, creep, horizon)
                local ____opt_49 = a.GetAttackDamage
                local ____temp_53 = ____opt_49 and ____opt_49(a) or 0
                local ____opt_51 = a.GetSecondsPerAttack
                dps = dps + ____temp_53 / (____opt_51 and ____opt_51(a) or 1)
                __continue49 = true
            until true
            if not __continue49 then
                break
            end
        end
    end
    return {raw = raw, dps = dps}
end
ACTIVITY_ATTACK = 1503
ACTIVITY_ATTACK2 = 1504
RANGED_ABOVE = 320
--- Projectiles start this far in front of a ranged hero / creep (OHA's offsets).
local HERO_LAUNCH_OFFSET = 39
CREEP_LAUNCH_OFFSET = 22
QUERY_RADIUS = 1600
--- Skill above which, of several creeps killable now, the ranged/siege one is taken (OHA RangedPrioritySkill).
local RANGED_PRIORITY_SKILL = 0.6
--- Extra seconds a lapse delays the swing, on top of the normal timing error.
local LAPSE_MIN = 0.15
local LAPSE_MAX = 0.4
--- Seconds a hit must land before ours to be relied on (one frame at 30 fps); grows with the observed frame
-- time, since bots think less often per game second at high timescales.
local MIN_MARGIN = 0.034
local MAX_MARGIN = 0.3
--- Seconds after the predicted hit time before an unresolved swing counts as `missed`.
local CONFIRM_SLACK = 0.5
local function ok()
    return {success = true, reason = "ok"}
end
local function fail(reason)
    return {success = false, reason = reason}
end
local function expired(deadline)
    return deadline ~= nil and now() >= deadline
end
nearbyCache = {}
local function physical(creep, raw)
    if creep.GetActualIncomingDamage == nil then
        return raw
    end
    return creep:GetActualIncomingDamage(raw, DAMAGE_TYPE_PHYSICAL or 1)
end
--- Damage (after armour) the creep takes from others within `horizon` seconds: attack projectiles in flight
-- plus every attacker of either team winding up an attack on it. Attacks not yet started are not counted;
-- the prediction runs every frame, so they enter it once their wind-up begins.
function ____exports.incomingDamage(bot, creep, horizon)
    return physical(
        creep,
        scanAttackers(bot, creep, horizon).raw
    )
end
--- Damage per second (after armour) of every visible attacker of either team currently targeting the creep.
function ____exports.incomingDps(bot, creep)
    return physical(
        creep,
        scanAttackers(bot, creep, 0).dps
    )
end
--- Seconds until the bot can start its next swing (0 without the adapter's `attackClock`).
function ____exports.cooldownLeft(bot)
    local a = get()
    if a.attackClock == nil or bot.GetSecondsPerAttack == nil or bot.GetLastAttackTime == nil then
        return 0
    end
    local ____temp_56 = bot:GetAttackPoint()
    local ____this_55
    ____this_55 = bot
    local ____opt_54 = ____this_55.GetAttackSpeed
    local windup = ____temp_56 / (____opt_54 and ____opt_54(____this_55) or 1)
    local idle = bot:GetSecondsPerAttack() - windup
    local since = a.attackClock() - bot:GetLastAttackTime() + 0.01
    if since < -0.1 then
        return 0
    end
    return math.max(0, since) < idle and idle - math.max(0, since) or 0
end
local ____math_atan2_57 = math.atan2
if ____math_atan2_57 == nil then
    ____math_atan2_57 = math.atan
end
local atan2 = ____math_atan2_57
--- Hero turn rate (radians per 0.03 s; heroes 0.5-0.9) and the angle an attack can start within.
local TURN_RATE = 0.6
local TURN_SLACK = 0.2
--- Seconds to turn to face the creep (0 without GetFacing).
function ____exports.turnTime(bot, creep)
    local ____this_59
    ____this_59 = bot
    local ____opt_58 = ____this_59.GetFacing
    local facing = ____opt_58 and ____opt_58(____this_59)
    if facing == nil or facing == nil then
        return 0
    end
    local a = bot:GetLocation()
    local b = creep:GetLocation()
    local want = atan2(b.y - a.y, b.x - a.x)
    local d = math.abs(want - facing * math.pi / 180) % (2 * math.pi)
    if d > math.pi then
        d = 2 * math.pi - d
    end
    return 0.03 * math.max(0, d - TURN_SLACK) / TURN_RATE
end
function ____exports.ownHitTime(bot, creep)
    local ____temp_62 = bot:GetAttackPoint()
    local ____this_61
    ____this_61 = bot
    local ____opt_60 = ____this_61.GetAttackSpeed
    local t = ____temp_62 / (____opt_60 and ____opt_60(____this_61) or 1) + ____exports.cooldownLeft(bot) + ____exports.turnTime(bot, creep)
    local ____this_64
    ____this_64 = bot
    local ____opt_63 = ____this_64.GetAttackProjectileSpeed
    local speed = ____opt_63 and ____opt_63(____this_64) or 0
    local range = bot:GetAttackRange()
    if range > RANGED_ABOVE and speed > 0 then
        local d = dist(
            bot:GetLocation(),
            creep:GetLocation()
        ) - HERO_LAUNCH_OFFSET
        t = t + math.min(
            math.max(0, d),
            range
        ) / speed
    end
    return t
end
local rolls = {}
local function rollFor(bot, creep)
    local id = bot:GetPlayerID()
    local byCreep = rolls[id]
    if byCreep == nil then
        byCreep = setmetatable({}, {__mode = "k"})
        rolls[id] = byCreep
    end
    local r = byCreep[creep]
    if r == nil then
        local width = Skill.lastHitError(bot)
        local shift = (2 * Skill.random() - 1) * width * Skill.TIMING_PER_ERROR
        if Skill.random() < Skill.lapseChance(bot) then
            shift = shift - Skill.lerp(
                LAPSE_MIN,
                LAPSE_MAX,
                Skill.random()
            )
        end
        r = {
            eps = 2 * Skill.random() - 1,
            shift = shift
        }
        byCreep[creep] = r
    end
    return r
end
--- What the bot believes about a swing ordered now. A negative timing shift shortens the horizon (late swing);
-- a positive one extends it with the attackers' DPS, i.e. counts hits that have not started yet (early swing):
-- the visible prediction alone cannot over-anticipate, so without that extrapolation early errors vanish.
local function believe(bot, creep, withError, margin)
    if margin == nil then
        margin = MIN_MARGIN
    end
    local tHit = ____exports.ownHitTime(bot, creep)
    local ____this_66
    ____this_66 = creep
    local ____opt_65 = ____this_66.GetHealthRegen
    local regen = ____opt_65 and ____opt_65(____this_66) or 0
    local hp = creep:GetHealth()
    local visible = hp + regen * tHit - ____exports.incomingDamage(
        bot,
        creep,
        math.max(0, tHit - margin)
    )
    local believed = visible
    local width = 0
    local eps = 0
    if withError then
        local r = rollFor(bot, creep)
        width = Skill.lastHitError(bot)
        eps = r.eps
        if r.shift < 0 then
            local h = math.max(0, tHit - margin + r.shift)
            believed = hp + regen * h - ____exports.incomingDamage(bot, creep, h)
        elseif r.shift > 0 then
            believed = visible + regen * r.shift - ____exports.incomingDps(bot, creep) * r.shift
        end
    end
    local ____tHit_72 = tHit
    local ____temp_73 = visible > 0
    local ____believed_74 = believed
    local ____physical_71 = physical
    local ____creep_70 = creep
    local ____temp_69 = bot:GetAttackDamage()
    local ____this_68
    ____this_68 = bot
    local ____opt_67 = ____this_68.GetBaseDamageVariance
    return {
        tHit = ____tHit_72,
        survives = ____temp_73,
        hpAtHit = ____believed_74,
        mine = ____physical_71(
            ____creep_70,
            (____temp_69 - (____opt_67 and ____opt_67(____this_68) or 0)) * (1 + eps * width)
        )
    }
end
--- Swing now: the creep survives everyone else until our hit lands, and (as believed) our hit then kills it.
local function due(b)
    return b.survives and b.hpAtHit <= b.mine
end
local function isRangedCreep(c)
    local ____this_76
    ____this_76 = c
    local ____opt_75 = ____this_76.GetUnitName
    local name = ____opt_75 and ____opt_75(____this_76)
    if name == nil then
        return false
    end
    return (string.find(name, "ranged", 1, true)) ~= nil or (string.find(name, "siege", 1, true)) ~= nil
end
local function deniable(c)
    local ____this_78
    ____this_78 = c
    local ____opt_77 = ____this_78.GetMaxHealth
    local max = ____opt_77 and ____opt_77(____this_78)
    return max == nil or c:GetHealth() < max / 2
end
--- Of `creeps`, the one closest to dying to our hit (exact prediction, no error), preferring a ranged or siege
-- creep already killable when the bot's skill is above RANGED_PRIORITY_SKILL.
local function choose(bot, creeps)
    local best
    local bestMargin = math.huge
    local ranged
    local preferRanged = Skill.of(bot) > RANGED_PRIORITY_SKILL
    for ____, c in ipairs(creeps) do
        local b = believe(bot, c, false)
        local margin = b.hpAtHit - b.mine
        if margin < bestMargin then
            bestMargin = margin
            best = c
        end
        if preferRanged and ranged == nil and b.survives and margin <= 0 and isRangedCreep(c) then
            ranged = c
        end
    end
    return ranged or best
end
--- Deny heuristic, UNVERIFIED in-game: assumes an enemy hero attacking the creep on its last live frame
-- landed the killing blow, and that Dota hands back the same handle for the same unit so `==` matches.
local function enemyTargeting(bot, creep)
    local ____this_80
    ____this_80 = bot
    local ____opt_79 = ____this_80.GetNearbyHeroes
    local heroes = ____opt_79 and ____opt_79(____this_80, 1200, true, 0)
    if heroes == nil then
        return false
    end
    for ____, h in ipairs(heroes) do
        local ____opt_81 = h.GetAttackTarget
        if (____opt_81 and ____opt_81(h)) == creep then
            return true
        end
    end
    return false
end
--- Seconds until the creep is killable by a swing ordered then, and the walk into attack range.
local function etaOf(bot, c, walkSpeed)
    local b = believe(bot, c, false)
    if not b.survives then
        return nil
    end
    local walk = math.max(
        0,
        dist(
            bot:GetLocation(),
            c:GetLocation()
        ) - bot:GetAttackRange()
    ) / walkSpeed
    local margin = b.hpAtHit - b.mine
    if margin <= 0 then
        return {0, walk}
    end
    local ____exports_incomingDps_result_86 = ____exports.incomingDps(bot, c)
    local ____math_max_85 = math.max
    local ____this_84
    ____this_84 = c
    local ____opt_83 = ____this_84.GetHealthRegen
    local dps = ____exports_incomingDps_result_86 + ____math_max_85(
        0,
        -(____opt_83 and ____opt_83(____this_84) or 0)
    )
    if dps <= 0 then
        return nil
    end
    return {margin / dps, walk}
end
--- The lane creep the bot should go for next, if any becomes killable within `within` seconds of the bot reaching
-- attack range: an enemy creep to last-hit (the adapter's `lastHitFilter` applies) or an allied creep to deny.
-- Exact prediction, no skill error (the verbs apply that when they swing): eta is when the creep becomes
-- killable by a swing ordered then (from incoming DPS), or the walk into range if longer. Priority (knowledge.md 1.2): ranged last hit, ranged deny,
-- melee last hit, melee deny, as eta biases so a melee creep due now still beats a ranged one due much later.
function ____exports.nextLastHit(bot, opts)
    if opts == nil then
        opts = {}
    end
    if bot.GetAttackDamage == nil or bot.GetAttackPoint == nil or bot.GetNearbyLaneCreeps == nil then
        return nil
    end
    local adapter = get()
    local radius = opts.radius or math.max(
        800,
        bot:GetAttackRange() + 400
    )
    local within = opts.within or 1
    local rangedBias = opts.rangedBias or 0.4
    local lhBias = opts.lastHitBias or 0.3
    local ____math_max_89 = math.max
    local ____this_88
    ____this_88 = bot
    local ____opt_87 = ____this_88.GetCurrentMovementSpeed
    local speed = ____math_max_89(
        100,
        ____opt_87 and ____opt_87(____this_88) or 300
    )
    local here = bot:GetLocation()
    local n = nearby(bot)
    local best
    local bestKey = math.huge
    local function consider(c, kind)
        if gone(c) or dist(
            here,
            c:GetLocation()
        ) > radius then
            return
        end
        if kind == "lasthit" and adapter.lastHitFilter ~= nil and not adapter.lastHitFilter(bot, c) then
            return
        end
        local e = etaOf(bot, c, speed)
        if e == nil or e[1] - e[2] > within then
            return
        end
        local eta = math.max(e[1], e[2])
        local ranged = isRangedCreep(c)
        local key = eta - (ranged and rangedBias or 0) - (kind == "lasthit" and lhBias or 0)
        if key < bestKey then
            bestKey = key
            best = {creep = c, kind = kind, eta = eta, ranged = ranged}
        end
    end
    if opts.lastHit ~= false then
        for ____, c in ipairs(n.enemyCreeps) do
            consider(c, "lasthit")
        end
    end
    if opts.deny ~= false and bot.GetDenies ~= nil then
        for ____, c in ipairs(n.allyCreeps) do
            consider(c, "deny")
        end
    end
    return best
end
local strike = __TS__Generator(function(bot, mode, opts)
    local adapter = get()
    if bot.GetAttackDamage == nil or bot.GetAttackPoint == nil then
        return fail("unsupported")
    end
    if mode == "deny" and bot.GetDenies == nil then
        return fail("unsupported")
    end
    local start = now()
    local maxWait = opts.maxWait or 1.5
    local creep = opts.target
    if creep == nil then
        if bot.GetNearbyLaneCreeps == nil then
            return fail("unsupported")
        end
        local radius = opts.searchRadius or bot:GetAttackRange() + 300
        local here = bot:GetLocation()
        local n = nearby(bot)
        local candidates = 0
        local allowed = {}
        for ____, c in ipairs(mode == "deny" and n.allyCreeps or n.enemyCreeps) do
            if not gone(c) and dist(
                here,
                c:GetLocation()
            ) <= radius then
                candidates = candidates + 1
                if mode == "deny" or adapter.lastHitFilter == nil or adapter.lastHitFilter(bot, c) then
                    allowed[#allowed + 1] = c
                end
            end
        end
        creep = choose(bot, allowed)
        if creep == nil then
            return fail(candidates > 0 and "etiquette" or "no_target")
        end
    elseif mode == "lasthit" and adapter.lastHitFilter ~= nil and not adapter.lastHitFilter(bot, creep) then
        return fail("etiquette")
    end
    local function counter()
        return mode == "deny" and bot:GetDenies() or bot:GetLastHits()
    end
    local function lostReason(enemyOnIt)
        return mode == "lasthit" and enemyOnIt and "denied" or "taken_by_other"
    end
    local baseline = counter()
    local enemyOnIt = false
    local tHit = 0
    local diag = ""
    local lastFrame
    local margin = MIN_MARGIN
    while true do
        local t = now()
        if lastFrame ~= nil and t > lastFrame then
            margin = math.min(
                MAX_MARGIN,
                math.max(MIN_MARGIN, 1.2 * (t - lastFrame))
            )
        end
        lastFrame = t
        if not bot:IsAlive() then
            return fail("dead")
        end
        if gone(creep) then
            return fail(lostReason(enemyOnIt))
        end
        if opts.interruptIf ~= nil and opts.interruptIf() then
            return fail("interrupted")
        end
        if now() - start > maxWait or expired(opts.deadline) then
            return fail("timeout")
        end
        if mode == "lasthit" then
            enemyOnIt = enemyTargeting(bot, creep)
        end
        if dist(
            bot:GetLocation(),
            creep:GetLocation()
        ) > bot:GetAttackRange() then
            bot:Action_MoveToLocation(creep:GetLocation())
        else
            if (mode == "lasthit" or deniable(creep)) and ____exports.cooldownLeft(bot) <= margin then
                local b = believe(bot, creep, true, margin)
                if due(b) then
                    tHit = b.tHit
                    diag = string.format(
                        "hp=%d pred=%d mine=%d t=%.2f m=%.2f",
                        math.floor(creep:GetHealth()),
                        math.floor(b.hpAtHit),
                        math.floor(b.mine),
                        b.tHit,
                        margin
                    )
                    bot:Action_AttackUnit(creep, true)
                    break
                end
            end
            if opts.hold ~= nil and adapter.hold ~= nil then
                adapter.hold(bot, opts.hold)
            end
        end
        coroutine.yield()
    end
    local swingAt = now()
    local function landBy()
        return now() - swingAt >= tHit
    end
    local function out(r)
        local hp = gone(creep) and 0 or math.floor(creep:GetHealth())
        r.message = string.format(
            "%s end=%d dt=%.2f",
            diag,
            hp,
            now() - swingAt
        )
        return r
    end
    while true do
        coroutine.yield()
        if counter() > baseline then
            return out(ok())
        end
        if gone(creep) then
            return out(fail(landBy() and "missed" or lostReason(enemyOnIt)))
        end
        if not bot:IsAlive() then
            return fail("dead")
        end
        if now() - swingAt > tHit + CONFIRM_SLACK then
            return out(fail("missed"))
        end
        if mode == "lasthit" then
            enemyOnIt = enemyTargeting(bot, creep)
        end
    end
end)
--- Last-hits an enemy lane creep (`opts.target`, or the best one within `searchRadius` that the adapter's
-- `lastHitFilter` allows). Waits in attack range until the bot believes its hit, ordered now, lands after
-- everyone else's incoming damage and kills: `creepHP + regen * t - incoming(t) <= ownDamage`, where t is the
-- own hit time (wind-up, cooldown, projectile travel) and incoming counts attack projectiles in flight and
-- wind-ups of creeps, heroes and towers targeting the creep. The belief carries a per-creep error from the
-- bot's skill (see SDK_API.md): misses are early swings (`missed`) or late ones (`taken_by_other`/`denied`).
-- Ok once the bot's last-hit count rises.
____exports.lastHit = __TS__Generator(function(bot, opts)
    if opts == nil then
        opts = {}
    end
    return __TS__DelegatedYield(strike(bot, "lasthit", opts))
end)
--- Denies an allied lane creep: as `lastHit`, but only swings while the creep is below 50% HP (Dota refuses
-- the order above it), and confirms on the bot's deny count. `lastHitFilter` does not apply; whether a core
-- should deny rather than last-hit is the body's decision. Lost to an enemy last hit: `taken_by_other`.
____exports.deny = __TS__Generator(function(bot, opts)
    if opts == nil then
        opts = {}
    end
    return __TS__DelegatedYield(strike(bot, "deny", opts))
end)
return ____exports
 end,
["jobs"] = function(...) 
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

local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
end
-- End of Lua Library inline imports
local ____exports = {}
local ____adapter = require("adapter")
local get = ____adapter.get
local Skill = require("skill")
local ____lasthit = require("lasthit")
local ownHitTime = ____lasthit.ownHitTime
local ____verbs = require("verbs")
local attackAndConfirm = ____verbs.attackAndConfirm
local walkPath = ____verbs.walkPath
local walkTo = ____verbs.walkTo
local waitUntil = ____verbs.waitUntil
local ____verbs_cast = require("verbs_cast")
local pickUpRune = ____verbs_cast.pickUpRune
local ARRIVE = 100
local BOX_MARGIN = 300
local NEUTRAL_SEARCH = 700
local START_LATE = 2
local NO_CAMP_AFTER = 1
local AGGRO_CONFIRM = 2
local AGGRO_LEAD_DEFAULT = 0.4
local AGGRO_LEAD_MAX = 1.5
local LEAD_MAX_AFTER_AGGRO = 15
local WATCH_SEC = 8
--- handoff 12 / knowledge.md §2.3: arrive at a rune 3-5 s early.
local RUNE_EARLY = 4
--- Fraction of `early` kept at skill 0 (1 at skill 1): low-skill bots cut rune timings finer.
local RUNE_EARLY_LOW = 0.25
local RUNE_LATE_BY = 5
--- After the spawn, seconds to keep retrying a rune not yet reported available.
local RUNE_GRACE = 2
local RUNE_PICKUP_FOR = 10
local SHRINE_RADIUS = 300
local function ok()
    return {success = true, reason = "ok"}
end
local function fail(reason, message)
    return {success = false, reason = reason, message = message}
end
local function now()
    return get().now()
end
local function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function hold(bot, tag)
    local a = get()
    if a.hold ~= nil then
        a.hold(bot, tag)
    end
end
local function inBox(b, p, m)
    return p.x >= b.min.x - m and p.x <= b.max.x + m and p.y >= b.min.y - m and p.y <= b.max.y + m
end
--- The camp's neutral nearest the bot: alive, visible, inside the box grown by `margin` (or, without a box,
-- within `margin` of the origin, else anything in `search`).
function ____exports.campNeutral(bot, camp)
    if camp.pick ~= nil then
        return camp.pick()
    end
    if bot.GetNearbyNeutralCreeps == nil then
        return nil
    end
    local m = camp.margin or BOX_MARGIN
    local here = bot:GetLocation()
    local best
    local bestD = math.huge
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(camp.search or NEUTRAL_SEARCH) or ({})) do
        do
            local __continue12
            repeat
                local ____opt_0 = n.IsNull
                local ____temp_2 = ____opt_0 and ____opt_0(n)
                if ____temp_2 == nil then
                    ____temp_2 = false
                end
                local ____temp_6 = ____temp_2 or not n:IsAlive()
                if not ____temp_6 then
                    local ____opt_3 = n.CanBeSeen
                    local ____temp_5 = ____opt_3 and ____opt_3(n)
                    if ____temp_5 == nil then
                        ____temp_5 = true
                    end
                    ____temp_6 = not ____temp_5
                end
                if ____temp_6 then
                    __continue12 = true
                    break
                end
                local p = n:GetLocation()
                local ____temp_7
                if camp.box ~= nil then
                    ____temp_7 = not inBox(camp.box, p, m)
                else
                    ____temp_7 = camp.origin ~= nil and dist(p, camp.origin) > m
                end
                if ____temp_7 then
                    __continue12 = true
                    break
                end
                local d = dist(here, p)
                if d < bestD then
                    best = n
                    bestD = d
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    return best
end
--- Seconds from an attack order on `target` to the hit landing: walk into range, wind-up, projectile flight.
function ____exports.aggroLead(bot, target)
    if bot.GetAttackPoint == nil then
        return AGGRO_LEAD_DEFAULT
    end
    local d = dist(
        bot:GetLocation(),
        target:GetLocation()
    )
    local ____math_max_result_11 = math.max(
        0,
        d - bot:GetAttackRange()
    )
    local ____math_max_10 = math.max
    local ____this_9
    ____this_9 = bot
    local ____opt_8 = ____this_9.GetCurrentMovementSpeed
    local walk = ____math_max_result_11 / ____math_max_10(
        1,
        ____opt_8 and ____opt_8(____this_9) or 300
    )
    local hit = ownHitTime(bot, target)
    return math.max(
        0,
        math.min(AGGRO_LEAD_MAX, walk + hit)
    )
end
--- Travels to the camp's stand point and hits the camp so the hit lands at `at` (already including the error):
-- the order goes `aggroLead` early, from wherever the bot is once a neutral is in sight. Ends `ok` when the hit is
-- confirmed. Failures carry OHA's camp-job messages: `late`, `mistake:no-camp`, `mistake:no-aggro`.
local aggroCamp = __TS__Generator(function(bot, camp, planned, err, o, h)
    local at = planned + err
    local arrive = o.arrive or ARRIVE
    local late = at + (o.startLate or START_LATE)
    local function there()
        return dist(
            bot:GetLocation(),
            camp.stand
        ) <= arrive
    end
    local reached = false
    local waiting = false
    local ____opt_12 = h.label
    if ____opt_12 ~= nil then
        ____opt_12("travel")
    end
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        local t = now()
        local n = ____exports.campNeutral(bot, camp)
        if there() then
            reached = true
        end
        if n ~= nil and t >= at - (o.aggroLead or ____exports.aggroLead(bot, n)) then
            break
        end
        if t >= at and there() then
            break
        end
        if not there() then
            if t >= late then
                return fail("timeout", "late")
            end
            bot:Action_MoveToLocation(camp.stand)
        else
            if not waiting then
                local ____opt_14 = h.label
                if ____opt_14 ~= nil then
                    ____opt_14("wait")
                end
            end
            waiting = true
            hold(bot, "job_wait")
        end
        coroutine.yield()
    end
    local ____opt_16 = h.label
    if ____opt_16 ~= nil then
        ____opt_16("aggro")
    end
    local orderedAt
    local target
    local function pick()
        local n = ____exports.campNeutral(bot, camp)
        if n ~= nil and orderedAt == nil then
            orderedAt = now()
        end
        if n ~= nil then
            target = n
        end
        return n
    end
    local hit = __TS__DelegatedYield(attackAndConfirm(
        bot,
        pick,
        {
            findFor = math.max(
                0,
                at + (o.noCampAfter or NO_CAMP_AFTER) - now()
            ),
            confirmFor = o.confirmFor or AGGRO_CONFIRM,
            searchAt = camp.origin or camp.stand,
            hold = "job_aggro",
            confirmed = camp.confirmed
        }
    ))
    if hit.reason == "no_target" then
        return (reached or there()) and fail("no_target", "mistake:no-camp") or fail("timeout", "late")
    end
    if not hit.success then
        return fail(hit.reason, "mistake:no-aggro")
    end
    local ____opt_18 = o.onAggro
    if ____opt_18 ~= nil then
        ____opt_18({
            camp = camp,
            planned = planned,
            error = err,
            orderedAt = orderedAt or now(),
            confirmedAt = now(),
            target = target
        })
    end
    return ok()
end)
--- Camp stack (v0.2 port of OHA's O2 `stack_task.ts`): travel, wait at the stand point, a confirmed hit landing on
-- the aggro second (+ skill error), walk off along `exitPath`, stay out until `exitUntil`. Labels `travel`, `wait`,
-- `aggro`, `exit`; urgent until the hit lands.
____exports.stack = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local err = p.timingError or Skill.timingError(bot)
    local ____opt_20 = h.urgent
    if ____opt_20 ~= nil then
        ____opt_20(true)
    end
    local r = __TS__DelegatedYield(aggroCamp(
        bot,
        p.camp,
        p.aggroAt,
        err,
        p,
        h
    ))
    if not r.success then
        return r
    end
    local ____opt_22 = h.urgent
    if ____opt_22 ~= nil then
        ____opt_22(false)
    end
    local ____opt_24 = h.label
    if ____opt_24 ~= nil then
        ____opt_24("exit")
    end
    local arrive = p.arrive or ARRIVE
    __TS__DelegatedYield(walkPath(bot, p.exitPath, {tolerance = arrive, timeout = math.huge, stuckSecs = math.huge, deadline = p.exitUntil}))
    local held = __TS__DelegatedYield(waitUntil(bot, p.exitUntil, {hold = "stack_exit"}))
    return held.success and ok() or held
end)
--- Pull (full, half, double: the kind is in the data). Aggro the camp so the hit lands on its second (+ one skill
-- error for the whole job), lead it along `lead` to the meet point, then watch there. Labels `travel`, `wait`,
-- `aggro` (twice for a double), `lead`, `watch`; urgent until the lead is done. Grading the divert is the host's.
____exports.pull = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local err = p.timingError or Skill.timingError(bot)
    local ____opt_26 = h.urgent
    if ____opt_26 ~= nil then
        ____opt_26(true)
    end
    if p.first ~= nil then
        local r = __TS__DelegatedYield(aggroCamp(
            bot,
            p.first.camp,
            p.first.aggroAt,
            err,
            p,
            h
        ))
        if not r.success then
            return r
        end
    end
    local r = __TS__DelegatedYield(aggroCamp(
        bot,
        p.camp,
        p.aggroAt,
        err,
        p,
        h
    ))
    if not r.success then
        return r
    end
    local ____opt_28 = h.label
    if ____opt_28 ~= nil then
        ____opt_28("lead")
    end
    local arrive = p.arrive or ARRIVE
    if #p.lead > 0 then
        local led = __TS__DelegatedYield(walkPath(bot, p.lead, {tolerance = arrive, timeout = math.huge, stuckSecs = 3, deadline = p.leadDeadline or p.aggroAt + err + LEAD_MAX_AFTER_AGGRO}))
        if not led.success then
            return fail(led.reason, "lead")
        end
    end
    local ____opt_30 = h.urgent
    if ____opt_30 ~= nil then
        ____opt_30(false)
    end
    local ____opt_32 = h.label
    if ____opt_32 ~= nil then
        ____opt_32("watch")
    end
    local spot = #p.lead > 0 and p.lead[#p.lead] or bot:GetLocation()
    local ____until = math.max(
        now() + (p.watchSec or WATCH_SEC),
        p.watchUntil or 0
    )
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if now() >= ____until then
            return ok()
        end
        if dist(
            bot:GetLocation(),
            spot
        ) > arrive then
            bot:Action_MoveToLocation(spot)
        else
            hold(bot, "job_watch")
        end
        coroutine.yield()
    end
end)
local arrivalErrors = {}
--- When the bot means to be at `at`: `early * lerp(0.25, 1, skill)` s before the spawn, plus its timing error.
function ____exports.runeArriveBy(bot, p)
    local err = p.timingError
    if err == nil then
        local key = (tostring(bot:GetPlayerID()) .. ":") .. tostring(p.spawnAt)
        err = arrivalErrors[key] or Skill.timingError(bot)
        arrivalErrors[key] = err
    end
    return p.spawnAt - (p.early or RUNE_EARLY) * Skill.lerp(
        RUNE_EARLY_LOW,
        1,
        Skill.of(bot)
    ) + err
end
--- When to start `runeRun` to arrive by `runeArriveBy`, from the straight-line walk at the current speed.
function ____exports.runeLeaveAt(bot, p)
    local ____math_max_36 = math.max
    local ____this_35
    ____this_35 = bot
    local ____opt_34 = ____this_35.GetCurrentMovementSpeed
    local speed = ____math_max_36(
        1,
        ____opt_34 and ____opt_34(____this_35) or 300
    )
    return ____exports.runeArriveBy(bot, p) - dist(
        bot:GetLocation(),
        p.at
    ) / speed
end
--- Rune or shrine run: walk to `at`, wait for the spawn, then one reaction delay later pick the rune up (retrying
-- while it is not yet reported, for 2 s) or, for a shrine, stand within `radius` for `channel` s (pushed out, the
-- count restarts). Start it at `runeLeaveAt` to arrive skill-scaled early. Labels `travel`, `wait`, then `pickup`
-- or `channel`.
____exports.runeRun = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local tolerance = p.tolerance or 150
    local ____opt_37 = h.label
    if ____opt_37 ~= nil then
        ____opt_37("travel")
    end
    local walked = __TS__DelegatedYield(walkTo(bot, p.at, {tolerance = tolerance, timeout = math.huge, stuckSecs = math.huge, deadline = p.spawnAt + (p.lateBy or RUNE_LATE_BY)}))
    if not walked.success then
        return walked.reason == "timeout" and fail("timeout", "late") or walked
    end
    local ____opt_39 = h.label
    if ____opt_39 ~= nil then
        ____opt_39("wait")
    end
    local go = math.max(
        p.spawnAt,
        now()
    ) + Skill.react(bot)
    while now() < go do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if dist(
            bot:GetLocation(),
            p.at
        ) > tolerance then
            bot:Action_MoveToLocation(p.at)
        else
            hold(bot, "rune_wait")
        end
        coroutine.yield()
    end
    local giveUp = p.spawnAt + (p.pickupFor or RUNE_PICKUP_FOR)
    if p.channel ~= nil then
        local ____opt_41 = h.label
        if ____opt_41 ~= nil then
            ____opt_41("channel")
        end
        local radius = p.radius or SHRINE_RADIUS
        local from
        while true do
            if not bot:IsAlive() then
                return fail("dead")
            end
            local t = now()
            local ____opt_43 = p.confirmed
            if (____opt_43 and ____opt_43()) == true then
                return ok()
            end
            if dist(
                bot:GetLocation(),
                p.at
            ) <= radius then
                if from == nil then
                    from = t
                end
                if t - from >= p.channel then
                    return p.confirmed == nil and ok() or fail("missed")
                end
                hold(bot, "rune_channel")
            else
                from = nil
                bot:Action_MoveToLocation(p.at)
            end
            if t >= giveUp then
                return fail("timeout")
            end
            coroutine.yield()
        end
    end
    if p.rune == nil then
        return fail("no_target", "no rune")
    end
    local ____opt_45 = h.label
    if ____opt_45 ~= nil then
        ____opt_45("pickup")
    end
    local graceUntil = go + RUNE_GRACE
    while true do
        local r = __TS__DelegatedYield(pickUpRune(
            bot,
            p.rune,
            {
                at = p.runeAt,
                deadline = giveUp,
                timeout = math.max(
                    0,
                    giveUp - now()
                ),
                confirmed = p.confirmed
            }
        ))
        if r.reason ~= "no_target" or now() >= graceUntil then
            return r
        end
        coroutine.yield()
    end
end)
local CLEAR_RADIUS = 700
local CLEAR_ARRIVE = 300
local CLEAR_SEARCH = 1600
local CLEAR_EMPTY_AFTER = 0.5
local CLEAR_REORDER = 1
local ENGAGE_SLACK = 100
--- Seconds a fought neutral may be out of sight before it no longer holds the camp open.
local CLEAR_LOST = 2
local function campOf(bot, p)
    local out = {}
    if bot.GetNearbyNeutralCreeps == nil then
        return out
    end
    local r = p.radius or CLEAR_RADIUS
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(p.search or CLEAR_SEARCH) or ({})) do
        do
            local __continue70
            repeat
                local ____opt_47 = n.IsNull
                local ____temp_49 = ____opt_47 and ____opt_47(n)
                if ____temp_49 == nil then
                    ____temp_49 = false
                end
                local ____temp_53 = ____temp_49 or not n:IsAlive()
                if not ____temp_53 then
                    local ____opt_50 = n.CanBeSeen
                    local ____temp_52 = ____opt_50 and ____opt_50(n)
                    if ____temp_52 == nil then
                        ____temp_52 = true
                    end
                    ____temp_53 = not ____temp_52
                end
                if ____temp_53 then
                    __continue70 = true
                    break
                end
                if dist(
                    n:GetLocation(),
                    p.at
                ) <= r then
                    out[#out + 1] = n
                end
                __continue70 = true
            until true
            if not __continue70 then
                break
            end
        end
    end
    return out
end
local function hpOf(n)
    local c = n
    return c.GetHealth ~= nil and c:GetHealth() or 0
end
local function lowestHp(list)
    local best
    for ____, n in ipairs(list) do
        if best == nil or hpOf(n) < hpOf(best) then
            best = n
        end
    end
    return best
end
--- Clears a neutral camp: walks to `at`, attacks its neutrals (the current target is kept while it lives, else the
-- lowest HP one), one order per target (re-given every `reorder` s), and after each kill waits one reaction delay
-- (`Skill.react`, skill-scaled) before the next order. Ends ok with message "cleared" once a camp it fought is
-- empty, or "empty" when nothing was there; `timeout` "late" past `deadline`. Labels `go`, then `farm` from the first frame a neutral is in attack range (+100).
____exports.clearCamp = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local arrive = p.arrive or CLEAR_ARRIVE
    local fought = false
    local engaged = false
    local target
    local orderedAt = -math.huge
    local nextOrderAt = -math.huge
    local emptySince
    local seen = {}
    local ____opt_54 = h.label
    if ____opt_54 ~= nil then
        ____opt_54("go")
    end
    while true do
        do
            local __continue80
            repeat
                if not bot:IsAlive() then
                    return fail("dead")
                end
                local t = now()
                if p.deadline ~= nil and t >= p.deadline then
                    return fail("timeout", "late")
                end
                local camp = campOf(bot, p)
                local kept = {}
                for ____, e in ipairs(seen) do
                    do
                        local __continue83
                        repeat
                            local ____this_57
                            ____this_57 = e.n
                            local ____opt_56 = ____this_57.IsNull
                            local ____temp_58 = ____opt_56 and ____opt_56(____this_57)
                            if ____temp_58 == nil then
                                ____temp_58 = false
                            end
                            local alive = not ____temp_58 and e.n:IsAlive()
                            if not alive then
                                __continue83 = true
                                break
                            end
                            local inCamp = __TS__ArrayIndexOf(camp, e.n) >= 0
                            local ____inCamp_62 = inCamp
                            if not ____inCamp_62 then
                                local ____this_60
                                ____this_60 = e.n
                                local ____opt_59 = ____this_60.CanBeSeen
                                local ____temp_61 = ____opt_59 and ____opt_59(____this_60)
                                if ____temp_61 == nil then
                                    ____temp_61 = true
                                end
                                ____inCamp_62 = ____temp_61
                            end
                            local visibleNow = ____inCamp_62
                            local at = visibleNow and t or e.at
                            if t - at > CLEAR_LOST then
                                __continue83 = true
                                break
                            end
                            if not inCamp and visibleNow then
                                camp[#camp + 1] = e.n
                            end
                            kept[#kept + 1] = {n = e.n, at = at}
                            __continue83 = true
                        until true
                        if not __continue83 then
                            break
                        end
                    end
                end
                for ____, n in ipairs(camp) do
                    if not __TS__ArraySome(
                        kept,
                        function(____, e) return e.n == n end
                    ) then
                        kept[#kept + 1] = {n = n, at = t}
                    end
                end
                seen = kept
                if target ~= nil and __TS__ArrayIndexOf(camp, target) < 0 then
                    target = nil
                    nextOrderAt = t + Skill.react(bot)
                end
                if #camp == 0 then
                    if dist(
                        bot:GetLocation(),
                        p.at
                    ) > arrive then
                        emptySince = nil
                        bot:Action_MoveToLocation(p.at)
                    else
                        if emptySince == nil then
                            emptySince = t
                        end
                        if fought or t - emptySince >= (p.emptyAfter or CLEAR_EMPTY_AFTER) then
                            return {success = true, reason = "ok", message = fought and "cleared" or "empty"}
                        end
                        hold(bot, "camp_look")
                    end
                    coroutine.yield()
                    __continue80 = true
                    break
                end
                emptySince = nil
                fought = true
                if t < nextOrderAt then
                    hold(bot, "camp_react")
                    coroutine.yield()
                    __continue80 = true
                    break
                end
                local ____target_64 = target
                if ____target_64 == nil then
                    local ____temp_63
                    if p.pick ~= nil then
                        ____temp_63 = p.pick(camp)
                    else
                        ____temp_63 = nil
                    end
                    ____target_64 = ____temp_63
                end
                local next = ____target_64 or lowestHp(camp)
                if next ~= target or t - orderedAt >= (p.reorder or CLEAR_REORDER) then
                    bot:Action_AttackUnit(next, false)
                    orderedAt = t
                end
                target = next
                if not engaged and dist(
                    bot:GetLocation(),
                    next:GetLocation()
                ) <= bot:GetAttackRange() + ENGAGE_SLACK then
                    engaged = true
                    local ____opt_65 = h.label
                    if ____opt_65 ~= nil then
                        ____opt_65("farm")
                    end
                    local ____opt_67 = p.onEngage
                    if ____opt_67 ~= nil then
                        ____opt_67(t)
                    end
                end
                coroutine.yield()
                __continue80 = true
            until true
            if not __continue80 then
                break
            end
        end
    end
end)
local GANK_ENGAGE = 700
local GANK_LOST_GRACE = 2
local GANK_ENGAGE_FOR = 8
local GANK_REORDER = 1
local function visible(t)
    local ____temp_72 = t ~= nil
    if ____temp_72 then
        local ____this_70
        ____this_70 = t
        local ____opt_69 = ____this_70.IsNull
        local ____temp_71 = ____opt_69 and ____opt_69(____this_70)
        if ____temp_71 == nil then
            ____temp_71 = false
        end
        ____temp_72 = not ____temp_71
    end
    local ____temp_76 = ____temp_72 and t:IsAlive()
    if ____temp_76 then
        local ____this_74
        ____this_74 = t
        local ____opt_73 = ____this_74.CanBeSeen
        local ____temp_75 = ____opt_73 and ____opt_73(____this_74)
        if ____temp_75 == nil then
            ____temp_75 = true
        end
        ____temp_76 = ____temp_75
    end
    return ____temp_76
end
local function pathLeft(from, path, i, ____end)
    local d = 0
    local at = from
    do
        local k = i
        while k < #path do
            d = d + dist(at, path[k + 1])
            at = path[k + 1]
            k = k + 1
        end
    end
    return d + dist(at, ____end)
end
--- A gank: walk the host's approach path, then chase the target into `engageRange` and attack it (one reaction delay
-- after reaching range, `Skill.react`), re-ordering every `reorder` s. Ends ok "kill" when the target dies; fails
-- `interrupted` "escaped" when it stays out of sight `lostGrace` s, `timeout` "no-kill" after `engageFor` s of
-- fighting, `timeout` "late" if not engaged by `deadline`, or with the host's `commit` message. Labels `travel`,
-- `engage`; urgent while engaged.
____exports.gank = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local range = p.engageRange or GANK_ENGAGE
    local function speed()
        local ____math_max_79 = math.max
        local ____this_78
        ____this_78 = bot
        local ____opt_77 = ____this_78.GetCurrentMovementSpeed
        return ____math_max_79(
            1,
            ____opt_77 and ____opt_77(____this_78) or 300
        )
    end
    local wp = 0
    local lastSeen
    local lostAt
    local telegraphed = p.telegraph == nil
    local engagedAt
    local attackAt
    local orderedAt = -math.huge
    local ____opt_80 = h.label
    if ____opt_80 ~= nil then
        ____opt_80("travel")
    end
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        local t = now()
        local ____opt_82 = p.commit
        local why = ____opt_82 and ____opt_82()
        if why ~= nil then
            return fail("interrupted", why)
        end
        local target = p.target()
        local ____temp_87 = target ~= nil
        if ____temp_87 then
            local ____opt_84 = target.IsNull
            local ____temp_86 = ____opt_84 and ____opt_84(target)
            if ____temp_86 == nil then
                ____temp_86 = false
            end
            ____temp_87 = not ____temp_86
        end
        if ____temp_87 and not target:IsAlive() then
            return {success = true, reason = "ok", message = "kill"}
        end
        if visible(target) then
            lastSeen = target:GetLocation()
            lostAt = nil
        else
            if lostAt == nil then
                lostAt = t
            end
            if t - lostAt >= (p.lostGrace or GANK_LOST_GRACE) then
                return fail("interrupted", "escaped")
            end
        end
        if engagedAt == nil and p.deadline ~= nil and t >= p.deadline then
            return fail("timeout", "late")
        end
        if engagedAt ~= nil and t - engagedAt >= (p.engageFor or GANK_ENGAGE_FOR) then
            return fail("timeout", "no-kill")
        end
        local here = bot:GetLocation()
        while wp < #p.path and dist(here, p.path[wp + 1]) <= ARRIVE do
            wp = wp + 1
        end
        local goal = lastSeen or here
        if not telegraphed and lastSeen ~= nil then
            local eta = pathLeft(here, p.path, wp, goal) / speed()
            if eta <= p.telegraph.lead then
                telegraphed = true
                p.telegraph.fn(eta)
            end
        end
        if wp < #p.path then
            bot:Action_MoveToLocation(p.path[wp + 1])
        elseif engagedAt == nil and (not visible(target) or dist(here, goal) > range) then
            bot:Action_MoveToLocation(goal)
        elseif visible(target) then
            if engagedAt == nil then
                engagedAt = t
                attackAt = t + Skill.react(bot)
                local ____opt_88 = h.label
                if ____opt_88 ~= nil then
                    ____opt_88("engage")
                end
                local ____opt_90 = h.urgent
                if ____opt_90 ~= nil then
                    ____opt_90(true)
                end
                local ____opt_92 = p.onEngage
                if ____opt_92 ~= nil then
                    ____opt_92(t)
                end
            end
            if t >= attackAt and t - orderedAt >= (p.reorder or GANK_REORDER) then
                bot:Action_AttackUnit(target, false)
                orderedAt = t
            end
        else
            bot:Action_MoveToLocation(goal)
        end
        coroutine.yield()
    end
end)
return ____exports
 end,
["lane"] = function(...) 
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
local ____adapter = require("adapter")
local get = ____adapter.get
local ____verbs = require("verbs")
local holdAt = ____verbs.holdAt
local ____lasthit = require("lasthit")
local deny = ____lasthit.deny
local lastHit = ____lasthit.lastHit
local nextLastHit = ____lasthit.nextLastHit
local function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function enemyHeroNear(bot, r)
    local ____this_4
    ____this_4 = bot
    local ____opt_3 = ____this_4.GetNearbyHeroes
    for ____, h in ipairs(____opt_3 and ____opt_3(____this_4, r, true, 0) or ({})) do
        local ____opt_0 = h.IsAlive
        local ____temp_2 = ____opt_0 and ____opt_0(h)
        if ____temp_2 == nil then
            ____temp_2 = true
        end
        if ____temp_2 then
            return true
        end
    end
    return false
end
--- Posture verb for a laner: holds `spot()` (re-read every frame) and, while `lastHits()` allows, breaks off for
-- the creep nextLastHit offers (walking in so it arrives as the creep becomes killable), swings with the
-- skill-scaled lastHit/deny verbs, then walks back. Never ends ok by itself; ends on death, `deadline`,
-- `interruptIf`. Labels phases `walk` / `hold` / `lasthit` / `deny`.
____exports.laneFarm = __TS__Generator(function(bot, spot, opts)
    if opts == nil then
        opts = {}
    end
    local near = opts.near or 600
    local far = opts.far or 1200
    local leash = opts.leash or 900
    local label = opts.label or (function() return nil end)
    local function away()
        local p = spot()
        return p ~= nil and dist(
            bot:GetLocation(),
            p
        ) or 0
    end
    local target
    local scanEvery = opts.scanEvery or 0.1
    local scannedAt = -math.huge
    local function pick()
        local t = get().now()
        if t - scannedAt < scanEvery then
            return false
        end
        scannedAt = t
        if opts.lastHits ~= nil and not opts.lastHits() then
            return false
        end
        if away() > leash then
            return false
        end
        target = nextLastHit(bot, {within = opts.within})
        return target ~= nil
    end
    local function stop()
        return opts.interruptIf ~= nil and opts.interruptIf() or opts.deadline ~= nil and get().now() >= opts.deadline
    end
    local atSpot = false
    local passAt
    while true do
        do
            local __continue15
            repeat
                local t0 = get().now()
                if passAt == t0 then
                    coroutine.yield()
                end
                passAt = get().now()
                label(atSpot and "hold" or "walk")
                local r = __TS__DelegatedYield(holdAt(
                    bot,
                    spot,
                    __TS__ObjectAssign(
                        {},
                        opts.hold or ({}),
                        {
                            deadline = opts.deadline,
                            interruptIf = function()
                                if stop() then
                                    return true
                                end
                                local d = spot() ~= nil and away() or nil
                                local ____atSpot_5
                                if atSpot then
                                    ____atSpot_5 = (d or 0) > far
                                else
                                    ____atSpot_5 = (d or math.huge) <= near
                                end
                                if ____atSpot_5 then
                                    return true
                                end
                                return pick()
                            end
                        }
                    )
                ))
                if r.reason ~= "interrupted" then
                    return r
                end
                if stop() then
                    return {success = false, reason = "interrupted"}
                end
                if target == nil then
                    local d = spot() ~= nil and away() or nil
                    atSpot = d ~= nil and d <= (atSpot and far or near)
                    __continue15 = true
                    break
                end
                local t = target
                target = nil
                local contested = enemyHeroNear(bot, opts.contestRadius or 1000)
                label(t.kind)
                local ____t_creep_8 = t.creep
                local ____temp_9 = t.eta + 1.5
                local ____opts_deadline_10 = opts.deadline
                local ____opt_6 = opts.hold
                local o = {
                    target = ____t_creep_8,
                    maxWait = ____temp_9,
                    deadline = ____opts_deadline_10,
                    hold = ____opt_6 and ____opt_6.hold,
                    interruptIf = function() return stop() or away() > leash end
                }
                local res = t.kind == "lasthit" and __TS__DelegatedYield(lastHit(bot, o)) or __TS__DelegatedYield(deny(bot, o))
                if opts.onAttempt ~= nil then
                    opts.onAttempt(t, res, contested)
                end
                if res.reason == "dead" then
                    return res
                end
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
end)
return ____exports
 end,
["verbs_all"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
do
    local ____export = require("verbs")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
do
    local ____export = require("verbs_cast")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
do
    local ____export = require("lasthit")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
do
    local ____export = require("jobs")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
do
    local ____export = require("lane")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
return ____exports
 end,
["ctx"] = function(...) 
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
-- End of Lua Library inline imports
local ____exports = {}
local ____adapter = require("adapter")
local get = ____adapter.get
local ____abort = require("abort")
local abort = ____abort.abort
local must = ____abort.must
local Skill = require("skill")
local Verbs = require("verbs_all")
function ____exports.makeCtx(bot, c)
    local function now()
        return get().now()
    end
    local hooks = {label = c.label, urgent = c.urgent}
    return {
        bot = bot,
        now = now,
        elapsed = function() return now() - c.startedAt end,
        label = c.label,
        urgent = c.urgent,
        ok = function() return {success = true, reason = "ok"} end,
        fail = function(reason, message) return {success = false, reason = reason, message = message} end,
        abort = abort,
        must = must,
        skill = function() return Skill.of(bot) end,
        react = function() return Skill.react(bot) end,
        jitter = function(secs) return Skill.jitter(bot, secs) end,
        walkTo = function(loc, opts) return Verbs.walkTo(bot, loc, opts) end,
        walkPath = function(points, opts) return Verbs.walkPath(bot, points, opts) end,
        holdAt = function(point, opts) return Verbs.holdAt(bot, point, opts) end,
        wait = function(secs, opts) return Verbs.wait(bot, secs, opts) end,
        waitUntil = function(t, opts) return Verbs.waitUntil(bot, t, opts) end,
        retreatTo = function(opts) return Verbs.retreatTo(bot, opts) end,
        lastHit = function(opts) return Verbs.lastHit(bot, opts) end,
        laneFarm = function(spot, opts) return Verbs.laneFarm(
            bot,
            spot,
            __TS__ObjectAssign({label = c.label}, opts)
        ) end,
        deny = function(opts) return Verbs.deny(bot, opts) end,
        attackAndConfirm = function(pick, opts) return Verbs.attackAndConfirm(bot, pick, opts) end,
        cast = function(ability, opts) return Verbs.cast(bot, ability, opts) end,
        useItem = function(name, opts) return Verbs.useItem(bot, name, opts) end,
        pickUpRune = function(rune, opts) return Verbs.pickUpRune(bot, rune, opts) end,
        stack = function(plan) return Verbs.stack(bot, plan, hooks) end,
        pull = function(plan) return Verbs.pull(bot, plan, hooks) end,
        runeRun = function(plan) return Verbs.runeRun(bot, plan, hooks) end,
        clearCamp = function(plan) return Verbs.clearCamp(bot, plan, hooks) end,
        gank = function(plan) return Verbs.gank(bot, plan, hooks) end
    }
end
return ____exports
 end,
["support"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- True iff the VM exposes a usable `coroutine` library (generators compile to coroutines).
function ____exports.Supported()
    local co = rawget(_G, "coroutine")
    if type(co) ~= "table" then
        return false
    end
    local t = co
    return type(t.create) == "function" and type(t.resume) == "function" and type(t.status) == "function" and type(t.yield) == "function"
end
return ____exports
 end,
["runner"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local finish, running, last
local ____abort = require("abort")
local aborted = ____abort.aborted
local ____adapter = require("adapter")
local getAdapter = ____adapter.get
local ____ctx = require("ctx")
local makeCtx = ____ctx.makeCtx
local ____support = require("support")
local Supported = ____support.Supported
function finish(bot, t, result)
    local id = bot:GetPlayerID()
    running[id] = nil
    last[id] = {name = t.name, result = result}
    local a = getAdapter()
    if a ~= nil then
        a.release(bot, t.source, t.host)
    end
    local onEnd = t.onEnd
    if onEnd == nil then
        return
    end
    local ok, err = pcall(function() return onEnd(result, {label = t.label, steps = t.steps}) end)
    if not ok and a ~= nil then
        a.log(
            "tasks",
            (("task " .. t.name) .. " onEnd error: ") .. tostring(err)
        )
    end
end
function ____exports.Cancel(bot, reason, message)
    local t = running[bot:GetPlayerID()]
    if t == nil then
        return
    end
    finish(bot, t, {success = false, reason = reason, message = message})
end
--- Seconds a task may wait for its first `Step`, whatever the active mode, before it is cancelled.
____exports.START_GRACE = 1
local DEFAULT_TIER = "LANE_PLAN"
local DEFAULT_FLOOR = 0.6
local DEFAULT_STALL_AFTER = 2
running = {}
last = {}
local loggedRefusals = {}
local function refuse(why)
    local a = getAdapter()
    if a ~= nil and loggedRefusals[why] == nil then
        loggedRefusals[why] = true
        a.log("tasks", "task refused: " .. why)
    end
    return false
end
local function claim(a, bot, t)
    local now = a.now()
    if t.claimedAt == now and t.claimedUrgent == t.urgent then
        return
    end
    t.claimedAt = now
    t.claimedUrgent = t.urgent
    a.claim(bot, {
        source = t.source,
        mode = t.host,
        tier = t.tier,
        floor = t.floor,
        urgent = t.urgent
    })
end
local function guarded(bot, t)
    if t.guard == nil then
        return false
    end
    local message = t.guard()
    if message == nil then
        return false
    end
    finish(bot, t, {success = false, reason = "interrupted", message = message})
    return true
end
function ____exports.task(bot, opts, body)
    local a = getAdapter()
    if a == nil then
        return refuse("no_adapter")
    end
    if not a.enabled() then
        return refuse("disabled")
    end
    if not Supported() then
        return refuse("unsupported")
    end
    if running[bot:GetPlayerID()] ~= nil then
        ____exports.Cancel(bot, "cancelled", "replaced")
    end
    local now = a.now()
    local t = {
        name = opts.name,
        host = opts.host,
        tier = opts.tier or DEFAULT_TIER,
        floor = opts.floor or DEFAULT_FLOOR,
        source = "task:" .. opts.name,
        startedAt = now,
        steps = 0,
        body = body,
        onEnd = opts.onEnd,
        guard = opts.guard,
        stallAfter = opts.stallAfter or DEFAULT_STALL_AFTER,
        preemptAfter = opts.preemptAfter or 0,
        lastStepAt = now,
        urgent = false
    }
    t.ctx = makeCtx(
        bot,
        {
            startedAt = now,
            label = function(label)
                t.label = label
            end,
            urgent = function(on)
                t.urgent = on
            end
        }
    )
    running[bot:GetPlayerID()] = t
    return true
end
function ____exports.Step(bot, host)
    local a = getAdapter()
    local t = running[bot:GetPlayerID()]
    if a == nil or t == nil or t.host ~= host or not a.enabled() then
        return false
    end
    if guarded(bot, t) then
        return false
    end
    claim(a, bot, t)
    local ok, res = pcall(function()
        if t.gen == nil then
            t.gen = t.body(t.ctx)
        end
        return t.gen:next()
    end)
    t.steps = t.steps + 1
    t.lastStepAt = a.now()
    if not ok then
        local thrown = aborted(res)
        if thrown ~= nil then
            finish(bot, t, thrown)
            return true
        end
        local message = tostring(res)
        a.log("tasks", (("task " .. t.name) .. " error: ") .. message)
        finish(bot, t, {success = false, reason = "error", message = message})
    elseif res.done then
        finish(bot, t, res.value or ({success = true, reason = "ok"}))
    end
    return true
end
--- Every frame from the host's global tick. Re-posts the claim while the task is live, so the host can win
-- the mode before the first `Step`; the grace and stall limits keep an unstepped task from pinning it.
function ____exports.Tick(bot)
    local a = getAdapter()
    local t = running[bot:GetPlayerID()]
    if t == nil then
        return
    end
    if a == nil or not a.enabled() then
        ____exports.Cancel(bot, "cancelled", "disabled")
        return
    end
    if not bot:IsAlive() then
        ____exports.Cancel(bot, "dead")
        return
    end
    if guarded(bot, t) then
        return
    end
    local now = a.now()
    if t.steps == 0 then
        if now - t.startedAt > ____exports.START_GRACE then
            ____exports.Cancel(bot, "preempted", "never_started")
            return
        end
    else
        local mode = bot:GetActiveMode()
        if mode == t.host then
            t.awaySince = nil
        else
            if t.awaySince == nil then
                t.awaySince = now
            end
            if now - t.awaySince >= t.preemptAfter then
                ____exports.Cancel(
                    bot,
                    "preempted",
                    "mode=" .. tostring(mode)
                )
                return
            end
        end
        if now - t.lastStepAt > t.stallAfter then
            ____exports.Cancel(bot, "preempted", "stalled")
            return
        end
    end
    claim(a, bot, t)
end
--- Sets or clears urgency on the current task's claims from the next one posted; callable from a body.
function ____exports.Urgent(bot, on)
    local t = running[bot:GetPlayerID()]
    if t ~= nil then
        t.urgent = on
    end
end
--- Sets a free-form label on the current task, shown by `Current`/`Describe` and passed to `onEnd`.
function ____exports.Label(bot, label)
    local t = running[bot:GetPlayerID()]
    if t ~= nil then
        t.label = label
    end
end
function ____exports.Current(bot)
    local t = running[bot:GetPlayerID()]
    if t == nil then
        return nil
    end
    local name = t.name
    local host = t.host
    local startedAt = t.startedAt
    local steps = t.steps
    local label = t.label
    local preemptAfter = t.preemptAfter
    return {
        name = name,
        host = host,
        startedAt = startedAt,
        steps = steps,
        label = label,
        preemptAfter = preemptAfter
    }
end
function ____exports.Last(bot)
    return last[bot:GetPlayerID()]
end
function ____exports.Describe(bot)
    local t = running[bot:GetPlayerID()]
    if t ~= nil then
        return ((t.name .. (t.label ~= nil and ":" .. t.label or "")) .. " step=") .. tostring(t.steps)
    end
    local l = last[bot:GetPlayerID()]
    if l ~= nil then
        return (("- last=" .. l.name) .. " ") .. (l.result.success and "ok" or l.result.reason)
    end
    return "-"
end
return ____exports
 end,
["states"] = function(...) 
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
-- End of Lua Library inline imports
local ____exports = {}
local taskName, ours, cancelOurs
local ____adapter = require("adapter")
local getAdapter = ____adapter.get
local Tasks = require("runner")
function taskName(spec)
    return "state:" .. spec.name
end
function ours(bot, s)
    local t = Tasks.Current(bot)
    return t ~= nil and s.current ~= nil and t.name == taskName(s.current)
end
function cancelOurs(bot, s, message)
    if not ours(bot, s) then
        return
    end
    s.cancelling = true
    Tasks.Cancel(bot, "cancelled", message)
    s.cancelling = false
end
local config = {
    interval = 0.25,
    sticky = 0.1,
    minDwell = 3,
    jobBreak = 0.9,
    cooldown = 5,
    restart = 1
}
function ____exports.configure(c)
    for k, v in pairs(c) do
        config[k] = v
    end
end
local bots = {}
local function ownedFn()
    return false
end
--- Which states the SDK runs for which bot; read at every selection, so it may change during the game.
function ____exports.SetOwned(fn)
    ownedFn = fn
end
local function emit(name, fields)
    local a = getAdapter()
    if a == nil then
        return
    end
    if a.event ~= nil then
        a.event(name, fields)
        return
    end
    local parts = {"ev=" .. name}
    for ____, ____value in ipairs(fields) do
        local k = ____value[1]
        local v = ____value[2]
        if v ~= nil then
            parts[#parts + 1] = (k .. "=") .. tostring(v)
        end
    end
    a.log(
        "states",
        table.concat(parts, " ")
    )
end
--- Registers (or replaces) a bot's states. The current state is kept if a spec of that name remains.
function ____exports.define(bot, specs)
    local id = bot:GetPlayerID()
    local s = bots[id]
    if s == nil then
        bots[id] = {
            specs = specs,
            since = 0,
            owned = false,
            forceSelect = true,
            cooldownUntil = {},
            jobEnded = false,
            cancelling = false,
            starts = 0
        }
        return
    end
    s.specs = specs
    if s.current ~= nil then
        local name = s.current.name
        s.current = __TS__ArrayFind(
            specs,
            function(____, sp) return sp.name == name end
        )
    end
end
function ____exports.Forget(bot)
    local s = bots[bot:GetPlayerID()]
    if s == nil then
        return
    end
    cancelOurs(bot, s, "forgotten")
    bots[bot:GetPlayerID()] = nil
end
local priorFn
--- A prior on every raw score (e.g. `Phase.Prior()`), applied before stickiness and the job-break check; undefined
-- from it makes the state not applicable. A failing prior is logged and the raw score used. Nil removes it.
function ____exports.SetPrior(fn)
    priorFn = fn
end
local function scoreOf(bot, spec)
    local ok, v = pcall(function() return spec.score(bot) end)
    if not ok then
        local ____opt_0 = getAdapter()
        if ____opt_0 ~= nil then
            ____opt_0.log(
                "states",
                (("score " .. spec.name) .. " error: ") .. tostring(v)
            )
        end
        return nil
    end
    local prior = priorFn
    if v == nil or prior == nil then
        return v
    end
    local pok, pv = pcall(function() return prior(bot, spec.name, v) end)
    if pok then
        return pv
    end
    local ____opt_2 = getAdapter()
    if ____opt_2 ~= nil then
        ____opt_2.log(
            "states",
            (("prior " .. spec.name) .. " error: ") .. tostring(pv)
        )
    end
    return v
end
local function jobActive(s)
    return s.current ~= nil and s.current.kind == "job" and s.owned and not s.jobEnded
end
local function change(bot, s, next, score, why, now)
    local prev = s.current
    cancelOurs(bot, s, "state:" .. (next and next.name or "none"))
    s.current = next
    s.since = now
    s.score = score
    s.owned = next ~= nil and ownedFn(bot, next.name)
    s.jobEnded = false
    s.lastEnd = nil
    emit(
        "state",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"from", prev and prev.name or "none"},
            {"to", next and next.name or "none"},
            {"score", score},
            {"owned", s.owned},
            {"why", why}
        }
    )
end
local function select(bot, s, now)
    s.lastSelect = now
    s.forceSelect = false
    local cur = s.current
    local best
    local bestRaw
    local bestEff = -math.huge
    local curRaw
    for ____, spec in ipairs(s.specs) do
        do
            local __continue32
            repeat
                if (s.cooldownUntil[spec.name] or -math.huge) > now then
                    __continue32 = true
                    break
                end
                if spec == cur and s.jobEnded then
                    __continue32 = true
                    break
                end
                local raw = scoreOf(bot, spec)
                if raw == nil then
                    __continue32 = true
                    break
                end
                if spec == cur then
                    curRaw = raw
                end
                local eff = spec == cur and raw + config.sticky or raw
                if eff > bestEff then
                    bestEff = eff
                    best = spec
                    bestRaw = raw
                end
                __continue32 = true
            until true
            if not __continue32 then
                break
            end
        end
    end
    if cur ~= nil and best ~= cur then
        if jobActive(s) then
            if curRaw == nil and not ours(bot, s) then
                change(
                    bot,
                    s,
                    best,
                    bestRaw,
                    "n/a",
                    now
                )
                return
            end
            if best == nil or bestRaw < config.jobBreak then
                return
            end
            change(
                bot,
                s,
                best,
                bestRaw,
                "break",
                now
            )
            return
        end
        local dwelling = cur.kind == "posture" and curRaw ~= nil and now - s.since < config.minDwell
        if dwelling and best ~= nil and best.kind == "posture" then
            return
        end
        local why = s.jobEnded and "ended" or (curRaw == nil and "n/a" or "best")
        change(
            bot,
            s,
            best,
            bestRaw,
            why,
            now
        )
        return
    end
    if cur == nil then
        if best ~= nil then
            change(
                bot,
                s,
                best,
                bestRaw,
                "start",
                now
            )
        end
        return
    end
    s.score = curRaw
    local owned = ownedFn(bot, cur.name)
    if owned ~= s.owned then
        if not owned then
            cancelOurs(bot, s, "disowned")
        end
        s.owned = owned
        emit(
            "state",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"from", cur.name},
                {"to", cur.name},
                {"score", curRaw},
                {"owned", owned},
                {"why", owned and "own" or "disown"}
            }
        )
    end
end
local function ended(bot, s, spec, r, info)
    emit(
        "state_task",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"state", spec.name},
            {"result", r.success and "ok" or "fail"},
            {"reason", r.reason},
            {"msg", r.message},
            {"label", info.label},
            {"steps", info.steps}
        }
    )
    if s.cancelling or s.current ~= spec then
        return
    end
    local now = getAdapter().now()
    s.lastEnd = {at = now, reason = r.reason}
    if spec.kind == "job" and r.reason ~= "preempted" and r.reason ~= "dead" then
        s.jobEnded = true
        s.forceSelect = true
        if not r.success then
            s.cooldownUntil[spec.name] = now + config.cooldown
        end
    end
end
local function maybeStart(bot, s, now)
    local spec = s.current
    if spec == nil or not s.owned or s.jobEnded or not bot:IsAlive() then
        return
    end
    if Tasks.Current(bot) ~= nil then
        return
    end
    local last = s.lastEnd
    if last ~= nil then
        local waited = now - last.at >= config.restart
        local inHost = bot:GetActiveMode() == spec.host
        local quickOk = last.reason == "preempted" or last.reason == "dead"
        local canPull = (spec.floor or 0) > 0
        if not (inHost and (quickOk or waited) or waited and canPull) then
            return
        end
    end
    local started = Tasks.task(
        bot,
        {
            name = taskName(spec),
            host = spec.host,
            tier = spec.tier,
            floor = spec.floor or 0,
            preemptAfter = spec.preemptAfter or (spec.kind == "posture" and 3 or 0),
            stallAfter = spec.stallAfter or math.huge,
            guard = spec.guard,
            onEnd = function(r, info)
                ended(
                    bot,
                    s,
                    spec,
                    r,
                    info
                )
                local ____opt_10 = spec.onEnd
                if ____opt_10 ~= nil then
                    ____opt_10(r, info)
                end
            end
        },
        spec.body
    )
    if not started then
        return
    end
    s.starts = s.starts + 1
    emit(
        "state_start",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"state", spec.name},
            {"n", s.starts},
            {"gap", last ~= nil and now - last.at or nil},
            {"after", last and last.reason}
        }
    )
end
--- Every frame from the host's global tick, before the runner's Tick. Selects at `interval`, starts and restarts.
function ____exports.Tick(bot)
    local a = getAdapter()
    local s = bots[bot:GetPlayerID()]
    if a == nil or s == nil or not a.enabled() then
        return
    end
    local now = a.now()
    if s.forceSelect or s.lastSelect == nil or now - s.lastSelect >= config.interval then
        select(bot, s, now)
    end
    maybeStart(bot, s, now)
end
--- From the host mode's Think(): steps the current owned state's task when it runs on `host`; false otherwise.
function ____exports.Step(bot, host)
    local s = bots[bot:GetPlayerID()]
    if s == nil or s.current == nil or not s.owned or s.current.host ~= host or not ours(bot, s) then
        return false
    end
    return Tasks.Step(bot, host)
end
function ____exports.Current(bot)
    local s = bots[bot:GetPlayerID()]
    if s == nil or s.current == nil then
        return nil
    end
    local c = s.current
    return {
        name = c.name,
        kind = c.kind,
        host = c.host,
        since = s.since,
        score = s.score,
        owned = s.owned,
        running = ours(bot, s),
        starts = s.starts
    }
end
return ____exports
 end,
["phase"] = function(...) 
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

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
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
-- End of Lua Library inline imports
local ____exports = {}
local ____adapter = require("adapter")
local getAdapter = ____adapter.get
local config = {
    interval = 0.5,
    margin = 0.1,
    confirm = 2,
    urgentConfirm = 1,
    minDwell = 20,
    blend = 4
}
function ____exports.configure(c)
    for k, v in pairs(c) do
        config[k] = v
    end
end
local DOTA_DEFAULTS = {laningEnd = 600, transitionEnd = 900, lateFrom = 2100}
local function t1Down(s)
    local t = s.towers
    return t == nil and 0 or 6 - t.ours.t1 - t.theirs.t1
end
local function anyBelow(s, tier)
    local t = s.towers
    return t ~= nil and (t.ours[tier] < 3 or t.theirs[tier] < 3)
end
--- The default Dota set. Scores are fixed levels except push (advantage) and defend (threat). Bias keys are the
-- team plan's state names (laning, pull, stack, rotate, farm, gank).
function ____exports.DotaPhases(opts)
    local o = __TS__ObjectAssign({}, DOTA_DEFAULTS, opts or ({}))
    local function laning(s)
        return s.time < o.laningEnd and t1Down(s) == 0
    end
    return {
        {
            name = "laning",
            score = function(s) return laning(s) and 0.6 or nil end
        },
        {
            name = "transition",
            score = function(s) return not laning(s) and s.time < o.transitionEnd and t1Down(s) < 4 and not anyBelow(s, "t2") and 0.5 or nil end,
            bias = {
                laning = 0.6,
                pull = 0.7,
                rotate = 1.1,
                farm = 1.3,
                gank = 1.2
            }
        },
        {
            name = "midgame",
            score = function(s)
                local ____laning_result_0
                if laning(s) then
                    ____laning_result_0 = nil
                else
                    ____laning_result_0 = 0.4
                end
                return ____laning_result_0
            end,
            bias = {
                laning = 0.3,
                pull = 0.5,
                stack = 1.2,
                farm = 1.4,
                gank = 1.1
            },
            desire = {farm = 1.2}
        },
        {
            name = "push",
            score = function(s)
                if laning(s) then
                    return nil
                end
                if s.alive ~= nil and s.alive.ours < 3 then
                    return nil
                end
                local adv = 0
                if s.alive ~= nil then
                    adv = adv + 0.15 * math.max(0, s.alive.ours - s.alive.theirs)
                end
                local nw = s.netWorth
                if nw ~= nil and nw.theirs > 0 then
                    adv = adv + math.min(
                        0.3,
                        math.max(0, (nw.ours - nw.theirs) / nw.theirs) * 1.5
                    )
                end
                local w = s.waves
                if w ~= nil and #w > 0 then
                    local sum = 0
                    for ____, f in ipairs(w) do
                        sum = sum + f
                    end
                    adv = adv + 0.2 * math.max(0, sum / #w)
                end
                return adv >= 0.2 and math.min(1, 0.3 + adv) or nil
            end,
            bias = {
                laning = 0.3,
                pull = 0.3,
                stack = 0.5,
                farm = 0.6,
                gank = 0.8
            },
            desire = {push = 1.5, farm = 0.6}
        },
        {
            name = "defend",
            urgent = true,
            score = function(s)
                local th = s.threat
                if th == nil or th.heroes < 2 then
                    return nil
                end
                if laning(s) and th.tier <= 1 and th.heroes < 3 then
                    return nil
                end
                return math.min(1, 0.75 + 0.05 * (th.heroes - 2) + (th.tier >= 3 and 0.05 or 0))
            end,
            bias = {
                laning = 0.5,
                pull = 0.3,
                stack = 0.3,
                farm = 0.4,
                gank = 0.5,
                rotate = 0.6
            },
            desire = {defend = 1.6, farm = 0.5, push = 0.6}
        },
        {
            name = "late",
            score = function(s) return not laning(s) and (s.time >= o.lateFrom or anyBelow(s, "t3")) and 0.55 or nil end,
            bias = {laning = 0.2, pull = 0.2, stack = 0.6, farm = 1.1},
            desire = {push = 1.2, farm = 0.8}
        }
    }
end
local teams = {}
function ____exports.Reset()
    teams = {}
end
local function teamOf(team)
    local t = teams[team]
    if t == nil then
        t = {
            specs = ____exports.DotaPhases(),
            since = 0,
            pendingSince = 0,
            released = false
        }
        teams[team] = t
    end
    return t
end
--- Sets a team's phases (default: `DotaPhases()`). The current phase is kept if a spec of that name remains.
function ____exports.define(team, specs)
    local t = teamOf(team)
    t.specs = specs
    local ____opt_1 = t.current
    local name = ____opt_1 and ____opt_1.name
    local ____temp_3
    if name ~= nil then
        ____temp_3 = __TS__ArrayFind(
            specs,
            function(____, s) return s.name == name end
        )
    else
        ____temp_3 = nil
    end
    t.current = ____temp_3
    t.previous = nil
    t.pending = nil
end
local function log(msg)
    local ____opt_4 = getAdapter()
    if ____opt_4 ~= nil then
        ____opt_4.log("phase", msg)
    end
end
local function emit(fields)
    local a = getAdapter()
    if a == nil then
        return
    end
    if a.event ~= nil then
        a.event("phase", fields)
        return
    end
    local parts = {"ev=phase"}
    for ____, ____value in ipairs(fields) do
        local k = ____value[1]
        local v = ____value[2]
        if v ~= nil then
            parts[#parts + 1] = (k .. "=") .. tostring(v)
        end
    end
    a.log(
        "phase",
        table.concat(parts, " ")
    )
end
local function change(team, t, next, score, why, now)
    local prev = t.current
    t.previous = prev
    t.current = next
    t.since = now
    t.score = score
    t.pending = nil
    t.released = false
    local ____emit_11 = emit
    local ____array_10 = __TS__SparseArrayNew(
        {"team", team},
        {"from", prev and prev.name or "none"},
        {"to", next.name},
        {"score", score},
        {"why", why}
    )
    local ____opt_8 = t.order
    __TS__SparseArrayPush(____array_10, {"order", ____opt_8 and ____opt_8.source})
    ____emit_11({__TS__SparseArraySpread(____array_10)})
end
local function evaluate(team, t, snap, now)
    local cur = t.current
    local best
    local bestRaw
    local bestEff = -math.huge
    local curRaw
    for ____, spec in ipairs(t.specs) do
        do
            local __continue37
            repeat
                local ok, v = pcall(function() return spec.score(snap) end)
                if not ok then
                    log((("score " .. spec.name) .. " error: ") .. tostring(v))
                end
                local ____ok_12
                if ok then
                    ____ok_12 = v
                else
                    ____ok_12 = nil
                end
                local raw = ____ok_12
                if raw == nil then
                    __continue37 = true
                    break
                end
                if spec == cur then
                    curRaw = raw
                end
                local eff = spec == cur and raw + config.margin or raw
                if eff > bestEff then
                    bestEff = eff
                    best = spec
                    bestRaw = raw
                end
                __continue37 = true
            until true
            if not __continue37 then
                break
            end
        end
    end
    if best == nil then
        return
    end
    if cur == nil then
        change(
            team,
            t,
            best,
            bestRaw,
            "start",
            now
        )
        return
    end
    if best == cur then
        t.score = curRaw
        t.pending = nil
        return
    end
    local applies = curRaw ~= nil
    local urgent = best.urgent == true
    if applies and not urgent and not t.released and now - t.since < config.minDwell then
        t.pending = nil
        return
    end
    if t.pending ~= best then
        t.pending = best
        t.pendingSince = now
    end
    if now - t.pendingSince < (urgent and config.urgentConfirm or config.confirm) then
        return
    end
    change(
        team,
        t,
        best,
        bestRaw,
        t.released and "released" or (applies and "best" or "n/a"),
        now
    )
end
--- From the host's tick, per team (any frame rate). Re-evaluates at most every `interval`, calling `build` only
-- then. Returns the current phase name (undefined until a phase applies).
function ____exports.Tick(team, build)
    local a = getAdapter()
    if a == nil then
        return nil
    end
    local t = teamOf(team)
    local now = a.now()
    if t.order ~= nil and now >= t.order["until"] then
        t.order = nil
        t.released = true
        t.lastEval = nil
    end
    if t.order == nil and (t.lastEval == nil or now - t.lastEval >= config.interval) then
        t.lastEval = now
        local ok, snap = pcall(build)
        if ok then
            evaluate(team, t, snap, now)
        else
            log("snapshot error: " .. tostring(snap))
        end
    end
    local ____opt_13 = t.current
    return ____opt_13 and ____opt_13.name
end
--- Forces `phase` for `secs` (team orders bus, a human's call). False for an unknown phase name.
function ____exports.Order(team, phase, secs, source)
    local t = teamOf(team)
    local spec = __TS__ArrayFind(
        t.specs,
        function(____, s) return s.name == phase end
    )
    local a = getAdapter()
    if spec == nil or a == nil then
        return false
    end
    local now = a.now()
    t.order = {phase = spec, ["until"] = now + secs, source = source}
    if t.current ~= spec then
        change(
            team,
            t,
            spec,
            nil,
            "order",
            now
        )
    end
    return true
end
function ____exports.ClearOrder(team)
    local t = teams[team]
    if t == nil or t.order == nil then
        return
    end
    t.order = nil
    t.released = true
    t.lastEval = nil
end
function ____exports.Current(team)
    local t = teams[team]
    if t == nil or t.current == nil then
        return nil
    end
    local ____t_current_name_19 = t.current.name
    local ____t_since_20 = t.since
    local ____t_score_21 = t.score
    local ____opt_15 = t.order
    local ____temp_22 = ____opt_15 and ____opt_15.source
    local ____opt_17 = t.order
    return {
        name = ____t_current_name_19,
        since = ____t_since_20,
        score = ____t_score_21,
        ordered = ____temp_22,
        ["until"] = ____opt_17 and ____opt_17["until"]
    }
end
local function blended(t, pick, key)
    if t == nil or t.current == nil then
        return 1
    end
    local function of(p)
        if p == nil then
            return 1
        end
        local m = pick(p)
        if m == nil then
            return 1
        end
        return m[key] or m["*"] or 1
    end
    local to = of(t.current)
    if t.previous == nil or config.blend <= 0 then
        return to
    end
    local ____opt_23 = getAdapter()
    local now = ____opt_23 and ____opt_23.now() or t.since
    local f = math.min(
        1,
        math.max(0, (now - t.since) / config.blend)
    )
    local from = of(t.previous)
    return from + (to - from) * f
end
--- The current multiplier for a state's score (1 with no phase).
function ____exports.Bias(team, state)
    return blended(
        teams[team],
        function(p) return p.bias end,
        state
    )
end
--- The current multiplier for a host mode desire key (1 with no phase).
function ____exports.Desire(team, key)
    return blended(
        teams[team],
        function(p) return p.desire end,
        key
    )
end
--- A state score with the team's phase prior applied, clamped to [0, 1]; undefined stays undefined.
function ____exports.Apply(team, state, raw)
    if raw == nil then
        return nil
    end
    return math.min(
        1,
        math.max(
            0,
            raw * ____exports.Bias(team, state)
        )
    )
end
--- A `States.SetPrior` function: the bot's team phase prior on every state score. Bots without GetTeam: raw.
function ____exports.Prior()
    return function(bot, state, raw)
        local team = bot.GetTeam ~= nil and bot:GetTeam() or nil
        return team == nil and raw or ____exports.Apply(team, state, raw)
    end
end
return ____exports
 end,
["combinators"] = function(...) 
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
local ____adapter = require("adapter")
local get = ____adapter.get
local function settle(value)
    return value or ({success = true, reason = "ok"})
end
--- Steps `g` once per frame. Before each step `check()` may return a message, which ends the combinator with
-- `interrupted` carrying it; `g` is then abandoned (its `finally` blocks do not run).
____exports.watch = __TS__Generator(function(g, check)
    while true do
        local message = check()
        if message ~= nil then
            return {success = false, reason = "interrupted", message = message}
        end
        local s = g:next()
        if s.done then
            return settle(s.value)
        end
        coroutine.yield()
    end
end)
--- Ends with `timeout` once `secs` have passed since its first step, unless `g` finished first.
____exports.withTimeout = __TS__Generator(function(g, secs)
    local now = get().now
    local start = now()
    while true do
        if now() - start >= secs then
            return {success = false, reason = "timeout"}
        end
        local s = g:next()
        if s.done then
            return settle(s.value)
        end
        coroutine.yield()
    end
end)
--- Runs `factory()` up to `times` times, starting a fresh attempt the frame after a failed one, while
-- `shouldRetry(result)` allows (default: any failure). Returns the last attempt's result.
____exports.retry = __TS__Generator(function(times, factory, shouldRetry)
    local r = {success = false, reason = "error", message = "retry: times < 1"}
    do
        local attempt = 1
        while attempt <= times do
            r = settle(__TS__DelegatedYield(factory(attempt)))
            if r.success then
                return r
            end
            if shouldRetry ~= nil and not shouldRetry(r) then
                return r
            end
            if attempt < times then
                coroutine.yield()
            end
            attempt = attempt + 1
        end
    end
    return r
end)
--- Steps every branch once per frame, in order, and returns the first to finish; the rest are abandoned.
-- Branches stepped after an acting one in the same frame override its orders, so let one branch act and make
-- the others watchers (`waitUntil`, conditions).
____exports.race = __TS__Generator(function(...)
    local branches = {...}
    if #branches == 0 then
        return {success = false, reason = "error", message = "race: no branches", winner = 0}
    end
    while true do
        do
            local i = 0
            while i < #branches do
                local s = branches[i + 1]:next()
                if s.done then
                    local r = settle(s.value)
                    return {success = r.success, reason = r.reason, message = r.message, winner = i + 1}
                end
                i = i + 1
            end
        end
        coroutine.yield()
    end
end)
--- Never acts; finishes `ok` on the first frame `cond()` holds (without yielding if it already does).
____exports["until"] = __TS__Generator(function(cond)
    while not cond() do
        coroutine.yield()
    end
    return {success = true, reason = "ok"}
end)
return ____exports
 end,
["simple_host"] = function(...) 
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
-- End of Lua Library inline imports
local ____exports = {}
local run
local ____adapter = require("adapter")
local init = ____adapter.init
local Runner = require("runner")
function run(gen)
    while true do
        local r = gen:next()
        if r.done == true then
            return r.value
        end
        coroutine.yield()
    end
end
local claims = {}
local tickedAt = {}
local opts = {}
local switchedOn = true
local function global(name)
    return rawget(_G, name)
end
local function now()
    return opts.now ~= nil and opts.now() or global("DotaTime")()
end
local function enabled()
    return switchedOn and (opts.enabled == nil or opts.enabled())
end
____exports.adapter = {
    claim = function(bot, c)
        local id = bot:GetPlayerID()
        local ____claims_id_1 = claims[id]
        if ____claims_id_1 == nil then
            local ____temp_0 = {}
            claims[id] = ____temp_0
            ____claims_id_1 = ____temp_0
        end
        local byMode = ____claims_id_1
        local ____byMode_c_mode_3 = byMode[c.mode]
        if ____byMode_c_mode_3 == nil then
            local ____temp_2 = {}
            byMode[c.mode] = ____temp_2
            ____byMode_c_mode_3 = ____temp_2
        end
        local bySource = ____byMode_c_mode_3
        bySource[c.source] = {
            floor = c.floor,
            urgent = c.urgent == true,
            at = now()
        }
    end,
    release = function(bot, source, mode)
        local ____opt_4 = claims[bot:GetPlayerID()]
        local bySource = ____opt_4 and ____opt_4[mode]
        if bySource ~= nil then
            bySource[source] = nil
        end
    end,
    now = function() return now() end,
    log = function(tag, msg)
        if opts.debug == true then
            print((("[" .. tag) .. "] ") .. msg)
        end
    end,
    enabled = function() return enabled() end
}
--- Installs the host as the runner's adapter. Returns false (and installs nothing) without a clock.
function ____exports.install(o)
    if o == nil then
        o = {}
    end
    if o.now == nil and type(global("DotaTime")) ~= "function" then
        print("[tasks] SimpleHost.install: no DotaTime; pass opts.now")
        return false
    end
    opts = o
    init(____exports.adapter)
    return true
end
--- Kill switch. Off: the next `desire` call cancels the running task (`cancelled`/`disabled`).
function ____exports.SetEnabled(on)
    switchedOn = on
end
--- The strongest live claim on `mode` for this bot: highest floor, urgent if any live claim is.
function ____exports.ClaimOf(bot, mode)
    local ____opt_6 = claims[bot:GetPlayerID()]
    local bySource = ____opt_6 and ____opt_6[mode]
    if bySource == nil or not enabled() then
        return nil
    end
    local t = now()
    local ttl = opts.claimTTL or 1
    local best
    for ____, c in pairs(bySource) do
        do
            local __continue17
            repeat
                if c == nil or t - c.at > ttl then
                    __continue17 = true
                    break
                end
                if best == nil then
                    best = {floor = c.floor, urgent = c.urgent}
                else
                    best.floor = math.max(best.floor, c.floor)
                    best.urgent = best.urgent or c.urgent
                end
                __continue17 = true
            until true
            if not __continue17 then
                break
            end
        end
    end
    return best
end
--- Call from mode `mode`'s `GetDesire` with the desire it would return without tasks (nil falls through to
-- Valve's). Ticks the runner once per bot per frame, then returns `max(base, floor)` while a task holds a
-- live claim on `mode`, else `base`. Urgency is not used: this host has no hysteresis to suppress.
function ____exports.desire(bot, mode, base)
    local id = bot:GetPlayerID()
    local t = now()
    if tickedAt[id] ~= t then
        tickedAt[id] = t
        Runner.Tick(bot)
    end
    local c = ____exports.ClaimOf(bot, mode)
    if c == nil then
        return base
    end
    return base == nil and c.floor or math.max(base, c.floor)
end
--- Call from mode `mode`'s `Think`; steps this bot's task if it is hosted on `mode`. True if one ran.
function ____exports.think(bot, mode)
    return Runner.Step(bot, mode)
end
--- Call from mode `mode`'s `OnEnd`. A started task hosted on `mode` ends `preempted`, as the runner's `Tick`
-- would on the next frame; one with `preemptAfter` set is left to `Tick`, and an unstarted one to the grace.
function ____exports.onEnd(bot, mode)
    local t = Runner.Current(bot)
    if t == nil or t.host ~= mode or t.steps == 0 or t.preemptAfter > 0 then
        return
    end
    Runner.Cancel(bot, "preempted", "mode_end")
end
--- Layers task hosting on a mode file's functions:
--   local M = tasks.SimpleHost.wrapMode(BOT_MODE_FARM, { GetDesire = GetDesire, Think = Think, OnEnd = OnEnd })
--   GetDesire, Think, OnStart, OnEnd = M.GetDesire, M.Think, M.OnStart, M.OnEnd
-- `Think` runs the task, else the original. Defining `Think` replaces Valve's built-in one for the mode, so a
-- file with no `Think` of its own should not let `GetDesire` fall through (nil) to Valve's desire.
function ____exports.wrapMode(mode, original, getBot)
    if original == nil then
        original = {}
    end
    local function bot()
        return (getBot or global("GetBot"))()
    end
    return {
        GetDesire = function()
            local ____exports_desire_11 = ____exports.desire
            local ____bot_result_9 = bot()
            local ____mode_10 = mode
            local ____temp_8
            if original.GetDesire ~= nil then
                ____temp_8 = original.GetDesire()
            else
                ____temp_8 = nil
            end
            return ____exports_desire_11(____bot_result_9, ____mode_10, ____temp_8)
        end,
        Think = function()
            if not ____exports.think(
                bot(),
                mode
            ) and original.Think ~= nil then
                original.Think()
            end
        end,
        OnStart = function()
            if original.OnStart ~= nil then
                original.OnStart()
            end
        end,
        OnEnd = function()
            ____exports.onEnd(
                bot(),
                mode
            )
            if original.OnEnd ~= nil then
                original.OnEnd()
            end
        end
    }
end
--- A task body written as a plain function, for Lua callers (who cannot write generators). Inside `fn`,
-- `coroutine.yield()` ends this frame's slice and `run(verb)` runs a verb to completion, one slice per frame,
-- returning its `Result`; `run(ctx.must(verb))` ends the task on failure. Returning nothing counts as ok.
function ____exports.body(fn)
    return __TS__Generator(function(ctx)
        return fn(run, ctx)
    end)
end
return ____exports
 end,
["index"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Tasks = require("runner")
local States = require("states")
local Phase = require("phase")
do
    local ____support = require("support")
    local Supported = ____support.Supported
    ____exports.Supported = Supported
end
do
    local ____adapter = require("adapter")
    local init = ____adapter.init
    ____exports.init = init
end
____exports.Tasks = Tasks
____exports.States = States
____exports.Phase = Phase
do
    local ____export = require("types")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
____exports.Verbs = require("verbs_all")
____exports.Flow = require("combinators")
____exports.Skill = require("skill")
do
    local ____abort = require("abort")
    local abort = ____abort.abort
    local must = ____abort.must
    ____exports.abort = abort
    ____exports.must = must
end
____exports.SimpleHost = require("simple_host")
return ____exports
 end,
}
return require("index", ...)
