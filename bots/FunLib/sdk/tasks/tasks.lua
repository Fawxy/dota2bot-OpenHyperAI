-- Vendored from dota-bot-sdk packages/lua-tasks @ 4b4a4afe9d79aa924cfcd9558aecdc134046dc56. Do not edit; run npm run vendor.
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
local ____adapter = require("adapter")
local getAdapter = ____adapter.get
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
    running[bot:GetPlayerID()] = {
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
            t.gen = t.body()
        end
        return t.gen:next()
    end)
    t.steps = t.steps + 1
    t.lastStepAt = a.now()
    if not ok then
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
    return {
        name = t.name,
        host = t.host,
        startedAt = t.startedAt,
        steps = t.steps,
        label = t.label
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
local ok, fail, now, dist
local ____adapter = require("adapter")
local get = ____adapter.get
function ok()
    return {success = true, reason = "ok"}
end
function fail(reason)
    return {success = false, reason = reason}
end
function now()
    return get().now()
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
        if t - start > timeout then
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
        hold(bot, opts.hold)
        coroutine.yield()
    end
end)
____exports.retreatTo = __TS__Generator(function(bot, opts)
    return __TS__DelegatedYield(____exports.walkTo(bot, opts.safe, {tolerance = opts.tolerance or 300, timeout = opts.timeout or 20, stuckSecs = 3}))
end)
local CREEP_QUERY_RADIUS = 1600
local creepCache = {}
local function enemyLaneCreeps(bot)
    local id = bot:GetPlayerID()
    local t = now()
    local cached = creepCache[id]
    if cached ~= nil and cached.t == t then
        return cached.creeps
    end
    local creeps = bot:GetNearbyLaneCreeps(CREEP_QUERY_RADIUS, true) or ({})
    creepCache[id] = {t = t, creeps = creeps}
    return creeps
end
local function creepGone(c)
    local ____this_4
    ____this_4 = c
    local ____opt_3 = ____this_4.IsNull
    local ____temp_5 = ____opt_3 and ____opt_3(____this_4)
    if ____temp_5 == nil then
        ____temp_5 = false
    end
    return ____temp_5 or not c:IsAlive()
end
--- Deny heuristic, UNVERIFIED in-game: assumes an enemy hero attacking the creep on its last live frame
-- landed the killing blow, and that Dota hands back the same handle for the same unit so `==` matches.
local function enemyTargeting(bot, creep)
    local ____this_7
    ____this_7 = bot
    local ____opt_6 = ____this_7.GetNearbyHeroes
    local heroes = ____opt_6 and ____opt_6(____this_7, 1200, true, 0)
    if heroes == nil then
        return false
    end
    for ____, h in ipairs(heroes) do
        local ____opt_8 = h.GetAttackTarget
        if (____opt_8 and ____opt_8(h)) == creep then
            return true
        end
    end
    return false
end
____exports.lastHit = __TS__Generator(function(bot, opts)
    if opts == nil then
        opts = {}
    end
    if bot.GetAttackDamage == nil or bot.GetAttackPoint == nil then
        return fail("unsupported")
    end
    local adapter = get()
    local start = adapter.now()
    local maxWait = opts.maxWait or 1.5
    local creep = opts.target
    if creep == nil then
        if bot.GetNearbyLaneCreeps == nil then
            return fail("unsupported")
        end
        local radius = opts.searchRadius or bot:GetAttackRange() + 300
        local here = bot:GetLocation()
        local candidates = 0
        local bestHp = math.huge
        for ____, c in ipairs(enemyLaneCreeps(bot)) do
            if not creepGone(c) and dist(
                here,
                c:GetLocation()
            ) <= radius then
                candidates = candidates + 1
                if adapter.lastHitFilter == nil or adapter.lastHitFilter(bot, c) then
                    local hp = c:GetHealth()
                    if hp < bestHp then
                        bestHp = hp
                        creep = c
                    end
                end
            end
        end
        if creep == nil then
            return fail(candidates > 0 and "etiquette" or "no_target")
        end
    elseif adapter.lastHitFilter ~= nil and not adapter.lastHitFilter(bot, creep) then
        return fail("etiquette")
    end
    local baseline = bot:GetLastHits()
    local enemyOnIt = false
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        if creepGone(creep) then
            return fail(enemyOnIt and "denied" or "taken_by_other")
        end
        if adapter.now() - start > maxWait then
            return fail("timeout")
        end
        enemyOnIt = enemyTargeting(bot, creep)
        if creep:GetHealth() <= bot:GetAttackDamage() then
            bot:Action_AttackUnit(creep, true)
            break
        end
        if dist(
            bot:GetLocation(),
            creep:GetLocation()
        ) > bot:GetAttackRange() then
            bot:Action_MoveToLocation(creep:GetLocation())
        end
        coroutine.yield()
    end
    local swingAt = adapter.now()
    local window = bot:GetAttackPoint() + 0.5
    while true do
        coroutine.yield()
        if creepGone(creep) then
            if bot:GetLastHits() > baseline then
                return ok()
            end
            return fail(enemyOnIt and "denied" or "taken_by_other")
        end
        if not bot:IsAlive() then
            return fail("dead")
        end
        if adapter.now() - swingAt > window then
            return fail("missed")
        end
        enemyOnIt = enemyTargeting(bot, creep)
    end
end)
local function targetLost(t)
    local ____this_11
    ____this_11 = t
    local ____opt_10 = ____this_11.IsNull
    local ____temp_12 = ____opt_10 and ____opt_10(____this_11)
    if ____temp_12 == nil then
        ____temp_12 = false
    end
    local ____temp_16 = ____temp_12 or not t:IsAlive()
    if not ____temp_16 then
        local ____this_14
        ____this_14 = t
        local ____opt_13 = ____this_14.CanBeSeen
        local ____temp_15 = ____opt_13 and ____opt_13(____this_14)
        if ____temp_15 == nil then
            ____temp_15 = true
        end
        ____temp_16 = not ____temp_15
    end
    return ____temp_16
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
            local ____temp_19 = bot:GetLastAttackTime() > baseline
            if not ____temp_19 then
                local ____this_18
                ____this_18 = target
                local ____opt_17 = ____this_18.GetAttackTarget
                ____temp_19 = (____opt_17 and ____opt_17(____this_18)) == bot
            end
            local ____temp_19_23 = ____temp_19
            if not ____temp_19_23 then
                local ____opt_20 = opts.confirmed
                local ____temp_22 = ____opt_20 and ____opt_20()
                if ____temp_22 == nil then
                    ____temp_22 = false
                end
                ____temp_19_23 = ____temp_22
            end
            if ____temp_19_23 then
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
return ____exports
 end,
["index"] = function(...) 
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Tasks = require("runner")
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
do
    local ____export = require("types")
    for ____exportKey, ____exportValue in pairs(____export) do
        if ____exportKey ~= "default" then
            ____exports[____exportKey] = ____exportValue
        end
    end
end
____exports.Verbs = require("verbs")
return ____exports
 end,
}
return require("index", ...)
