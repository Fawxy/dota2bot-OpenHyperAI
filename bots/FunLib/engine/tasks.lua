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
--- Host integration: the host injects claims, etiquette, time, logging and the kill switch here.
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
--- Last-hit error half-width (fraction of own damage) at skill 0 and 1.
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
--- Gaussian sigma (s) of a timed action's error at skill 0 and 1.
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
["verbs_util"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____adapter = require("adapter")
local get = ____adapter.get
function ____exports.ok()
    return {success = true, reason = "ok"}
end
function ____exports.fail(reason, message)
    return {success = false, reason = reason, message = message}
end
function ____exports.now()
    return get().now()
end
--- True once game time has reached `deadline`; verbs then fail `timeout`.
function ____exports.expired(deadline)
    return deadline ~= nil and ____exports.now() >= deadline
end
function ____exports.dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- Reports a deliberate stand-still to the adapter's `hold`; no tag, no report.
function ____exports.hold(bot, tag)
    if tag == nil then
        return
    end
    local a = get()
    if a.hold ~= nil then
        a.hold(bot, tag)
    end
end
--- Released, dead or out of sight.
function ____exports.targetLost(t)
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
--- `interrupted` or `timeout` when `opts` says to stop now, else undefined.
function ____exports.stopped(opts)
    if opts.interruptIf ~= nil and opts.interruptIf() then
        return ____exports.fail("interrupted")
    end
    if ____exports.expired(opts.deadline) then
        return ____exports.fail("timeout")
    end
    return nil
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
local ____skill = require("skill")
local random = ____skill.random
local ____verbs_util = require("verbs_util")
local dist = ____verbs_util.dist
local expired = ____verbs_util.expired
local fail = ____verbs_util.fail
local hold = ____verbs_util.hold
local now = ____verbs_util.now
local ok = ____verbs_util.ok
local stopped = ____verbs_util.stopped
local targetLost = ____verbs_util.targetLost
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
--- `walkTo(opts.safe)` with retreat defaults: tolerance 300, timeout 20, stuckSecs 3.
____exports.retreatTo = __TS__Generator(function(bot, opts)
    return __TS__DelegatedYield(____exports.walkTo(
        bot,
        opts.safe,
        __TS__ObjectAssign({}, opts, {tolerance = opts.tolerance or 300, timeout = opts.timeout or 20, stuckSecs = opts.stuckSecs or 3})
    ))
end)
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
        local stop = stopped(opts)
        if stop ~= nil then
            return stop
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
            local ____temp_5 = bot:GetLastAttackTime() > baseline
            if not ____temp_5 then
                local ____this_4
                ____this_4 = target
                local ____opt_3 = ____this_4.GetAttackTarget
                ____temp_5 = (____opt_3 and ____opt_3(____this_4)) == bot
            end
            local ____temp_5_9 = ____temp_5
            if not ____temp_5_9 then
                local ____opt_6 = opts.confirmed
                local ____temp_8 = ____opt_6 and ____opt_6()
                if ____temp_8 == nil then
                    ____temp_8 = false
                end
                ____temp_5_9 = ____temp_8
            end
            if ____temp_5_9 then
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
local ____verbs = require("verbs")
local walkTo = ____verbs.walkTo
local ____verbs_util = require("verbs_util")
local dist = ____verbs_util.dist
local fail = ____verbs_util.fail
local now = ____verbs_util.now
local ok = ____verbs_util.ok
local stopped = ____verbs_util.stopped
local targetLost = ____verbs_util.targetLost
local REORDER_SECS = 0.5
local CHANNEL_SLACK = 0.25
local function inPhase(bot, ability)
    local ____this_1
    ____this_1 = ability
    local ____opt_0 = ____this_1.IsInAbilityPhase
    local ____temp_4 = ____opt_0 and ____opt_0(____this_1)
    if ____temp_4 == nil then
        local ____this_3
        ____this_3 = bot
        local ____opt_2 = ____this_3.IsCastingAbility
        ____temp_4 = ____opt_2 and ____opt_2(____this_3)
    end
    local ____temp_4_5 = ____temp_4
    if ____temp_4_5 == nil then
        ____temp_4_5 = false
    end
    return ____temp_4_5
end
local function channeling(bot, ability)
    local ____this_7
    ____this_7 = ability
    local ____opt_6 = ____this_7.IsChanneling
    local ____temp_10 = ____opt_6 and ____opt_6(____this_7)
    if ____temp_10 == nil then
        local ____this_9
        ____this_9 = bot
        local ____opt_8 = ____this_9.IsChanneling
        ____temp_10 = ____opt_8 and ____opt_8(____this_9)
    end
    return ____temp_10
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
    local ____temp_14 = ability == nil
    if not ____temp_14 then
        local ____this_12
        ____this_12 = ability
        local ____opt_11 = ____this_12.IsNull
        local ____temp_13 = ____opt_11 and ____opt_11(____this_12)
        if ____temp_13 == nil then
            ____temp_13 = false
        end
        ____temp_14 = ____temp_13
    end
    if ____temp_14 then
        return fail("not_castable", "no ability")
    end
    local order = orderFor(bot, ability, opts)
    if order == nil then
        return fail("unsupported")
    end
    local ____this_16
    ____this_16 = ability
    local ____opt_15 = ____this_16.GetManaCost
    local cost = ____opt_15 and ____opt_15(____this_16) or 0
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
    local ____opts_timeout_19 = opts.timeout
    if ____opts_timeout_19 == nil then
        local ____this_18
        ____this_18 = ability
        local ____opt_17 = ____this_18.GetCastPoint
        ____opts_timeout_19 = (____opt_17 and ____opt_17(____this_18) or 0) + 1
    end
    local timeout = ____opts_timeout_19
    local ____this_21
    ____this_21 = ability
    local ____opt_20 = ____this_21.GetCooldownTimeRemaining
    local cd0 = ____opt_20 and ____opt_20(____this_21)
    local ____this_23
    ____this_23 = bot
    local ____opt_22 = ____this_23.GetMana
    local mana0 = ____opt_22 and ____opt_22(____this_23)
    local function effectSeen()
        local ____this_25
        ____this_25 = ability
        local ____opt_24 = ____this_25.GetCooldownTimeRemaining
        local cd = ____opt_24 and ____opt_24(____this_25)
        if cd ~= nil and cd0 ~= nil and cd > cd0 + 0.05 then
            return true
        end
        local ____this_27
        ____this_27 = bot
        local ____opt_26 = ____this_27.GetMana
        local mana = ____opt_26 and ____opt_26(____this_27)
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
        local ____temp_28
        if slot >= 0 and slot < MAIN_SLOTS then
            ____temp_28 = bot:GetItemInSlot(slot)
        else
            ____temp_28 = nil
        end
        return ____temp_28
    end
    do
        local slot = 0
        while slot < MAIN_SLOTS do
            local item = bot:GetItemInSlot(slot)
            local ____temp_31 = item ~= nil
            if ____temp_31 then
                local ____opt_29 = item.GetName
                ____temp_31 = (____opt_29 and ____opt_29(item)) == name
            end
            if ____temp_31 then
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
--- Projectiles start this far in front of a ranged hero / creep.
local HERO_LAUNCH_OFFSET = 39
CREEP_LAUNCH_OFFSET = 22
QUERY_RADIUS = 1600
--- Skill above which, of several creeps killable now, the ranged/siege one is taken.
local RANGED_PRIORITY_SKILL = 0.6
--- Extra seconds a lapse delays the swing, on top of the normal timing error.
local LAPSE_MIN = 0.15
local LAPSE_MAX = 0.4
--- Seconds a hit must land before ours to be relied on (one frame at 30 fps); grows with the observed frame
-- time, since bots think less often per game second at high timescales.
local MIN_MARGIN = 0.034
local MAX_MARGIN = 0.3
--- Seconds ahead over which attacks are visible as wind-ups (a creep's attack point is 0.467 s).
local SEEN_AHEAD = 0.45
--- An attack order may be given this long before the cooldown ends: Dota queues it and the swing starts on time.
local COOLDOWN_QUEUE = 0.25
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
    local relied = math.max(0, tHit - margin)
    local dps = ____exports.incomingDps(bot, creep)
    local certain = hp + regen * tHit - ____exports.incomingDamage(bot, creep, relied)
    local visible = certain - math.max(0, relied - SEEN_AHEAD) * dps
    local believed = visible
    local width = 0
    local eps = 0
    if withError then
        local r = rollFor(bot, creep)
        width = Skill.lastHitError(bot)
        eps = r.eps
        if r.shift < 0 then
            local h = math.max(0, tHit - margin + r.shift)
            believed = hp + regen * h - ____exports.incomingDamage(bot, creep, h) - math.max(0, h - SEEN_AHEAD) * dps
        elseif r.shift > 0 then
            believed = visible + regen * r.shift - dps * r.shift
        end
    end
    local ____tHit_72 = tHit
    local ____temp_73 = certain > 0
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
-- killable by a swing ordered then (from incoming DPS), or the walk into range if longer. Priority: ranged last hit, ranged deny,
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
            if (mode == "lasthit" or deniable(creep)) and ____exports.cooldownLeft(bot) <= math.max(margin, COOLDOWN_QUEUE) then
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
        pickUpRune = function(rune, opts) return Verbs.pickUpRune(bot, rune, opts) end
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
    if t.ended then
        return
    end
    t.ended = true
    local id = bot:GetPlayerID()
    if running[id] == t then
        running[id] = nil
    end
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
local MAX_REPLACE = 8
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
    do
        local i = 0
        while i < MAX_REPLACE and running[bot:GetPlayerID()] ~= nil do
            ____exports.Cancel(bot, "cancelled", "replaced")
            i = i + 1
        end
    end
    if running[bot:GetPlayerID()] ~= nil then
        return refuse("onEnd restarts endlessly")
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
        urgent = false,
        ended = false
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
--- A prior on every raw score (e.g. a team-phase bias), applied before stickiness and the job-break check; undefined
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
--- Installs the host as the runner's adapter. Returns false (and installs nothing) without a clock. Points verbs
-- build themselves are made with `opts.vector`, else the script's `Vector`, as Dota's move orders require.
function ____exports.install(o)
    if o == nil then
        o = {}
    end
    if o.now == nil and type(global("DotaTime")) ~= "function" then
        print("[tasks] SimpleHost.install: no DotaTime; pass opts.now")
        return false
    end
    opts = o
    local V = global("Vector")
    ____exports.adapter.vector = o.vector or (V ~= nil and (function(x, y, z) return V(x, y, z) end) or nil)
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
            local __continue18
            repeat
                if c == nil or t - c.at > ttl then
                    __continue18 = true
                    break
                end
                if best == nil then
                    best = {floor = c.floor, urgent = c.urgent}
                else
                    best.floor = math.max(best.floor, c.floor)
                    best.urgent = best.urgent or c.urgent
                end
                __continue18 = true
            until true
            if not __continue18 then
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
