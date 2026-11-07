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
local engine
local host
--- The loaded bundle and the adapter it was initialised with: the clock and hold these bodies use.
function ____exports.Bind(lib, adapter)
    engine = lib
    host = adapter
end
local function E()
    return engine
end
local ARRIVE = 100
local BOX_MARGIN = 300
local NEUTRAL_SEARCH = 700
local START_LATE = 2
local NO_CAMP_AFTER = 1
local AGGRO_CONFIRM = 2
local APPROACH_LEAD = 3
local AGGRO_LEAD_DEFAULT = 0.4
local AGGRO_LEAD_MAX = 1.5
--- A stand point the bot gets near but cannot reach (trees) counts as reached once it is this close and has not got
-- STAND_STUCK_GAIN closer for STAND_STUCK_S: omniknight stopped ~300 short of evil_1's lane-side stand point and jiggled
-- until `late` (s4solo5, 15 of 20 Dire attempts).
local STAND_STUCK_R = 400
local STAND_STUCK_S = 1.5
local STAND_STUCK_GAIN = 25
local LEAD_MAX_AFTER_AGGRO = 15
local WATCH_SEC = 8
local BAIL_FOR = 6
--- Seconds early to arrive at a rune (players aim for 3-5 s).
local RUNE_EARLY = 4
--- Fraction of `early` kept at skill 0 (1 at skill 1): low-skill bots cut rune timings finer.
local RUNE_EARLY_LOW = 0.25
local RUNE_LATE_BY = 5
--- After the spawn, seconds to keep retrying a rune not yet reported available.
local RUNE_GRACE = 2
local RUNE_PICKUP_FOR = 10
local SHRINE_RADIUS = 300
--- Default for PullPlan aggroFor (the pull job passes its own, Lane.PullTiming.LockFor).
local AGGRO_FOR = 1
local function ok()
    return {success = true, reason = "ok"}
end
local function fail(reason, message)
    return {success = false, reason = reason, message = message}
end
local function now()
    return host.now()
end
local function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function hold(bot, tag)
    if host.hold ~= nil then
        host.hold(bot, tag)
    end
end
local function inBox(b, p, m)
    return p.x >= b.min.x - m and p.x <= b.max.x + m and p.y >= b.min.y - m and p.y <= b.max.y + m
end
--- The point `clear` from neutral `n` on the line from it through the bot, or undefined when the bot is already that far
-- (within 25). CANDIDATE(waitClear): one consumer, the double stack.
local function clearPoint(bot, n, clear)
    local p = n:GetLocation()
    local b = bot:GetLocation()
    local d = dist(p, b)
    if d >= clear - 25 then
        return nil
    end
    local k = clear / math.max(1, d)
    return Vector(p.x + (b.x - p.x) * k, p.y + (b.y - p.y) * k, b.z or 0)
end
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
            local __continue16
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
                    __continue16 = true
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
                    __continue16 = true
                    break
                end
                local d = dist(here, p)
                if d < bestD then
                    best = n
                    bestD = d
                end
                __continue16 = true
            until true
            if not __continue16 then
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
    local hit = E().Verbs.ownHitTime(bot, target)
    return math.max(
        0,
        math.min(AGGRO_LEAD_MAX, walk + hit)
    )
end
--- Travels to the camp's stand point and hits the camp so the hit lands at `at` (already including the error):
-- the order goes `aggroLead` early, from wherever the bot is once a neutral is in sight. Ends `ok` when the hit is
-- confirmed. Failure messages: `late`, `mistake:no-camp`, `mistake:no-aggro`.
local aggroCamp = __TS__Generator(function(bot, camp, planned, err, o, h)
    local at = planned + err
    local arrive = o.arrive or ARRIVE
    local late = at + (o.startLate or START_LATE)
    local stand = camp.stand
    local approached = camp.approach == nil
    local best = math.huge
    local bestAt = now()
    local arrived = false
    local function there()
        local d = dist(
            bot:GetLocation(),
            stand
        )
        if d <= arrive then
            arrived = true
            return true
        end
        if arrived then
            return false
        end
        if d < best - STAND_STUCK_GAIN then
            best = d
            bestAt = now()
        end
        return d <= STAND_STUCK_R and now() - bestAt >= STAND_STUCK_S
    end
    local reached = false
    local waiting = false
    local clearLead
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
        if camp.earlier ~= nil then
            at = planned + err - camp.earlier()
        end
        if there() then
            reached = true
        end
        if n ~= nil and t >= at - (o.aggroLead or ____exports.aggroLead(bot, n)) then
            break
        end
        if n == nil and clearLead ~= nil and there() and t >= at - clearLead then
            break
        end
        if n == nil and not approached and there() and t >= at - (o.approachLead or APPROACH_LEAD) then
            approached = true
            stand = camp.approach
            waiting = false
            best = math.huge
            bestAt = t
            arrived = false
        end
        if t >= at and there() then
            break
        end
        if not there() then
            if t >= late then
                return fail("timeout", "late")
            end
            bot:Action_MoveToLocation(stand)
        else
            if not waiting then
                local ____opt_14 = h.label
                if ____opt_14 ~= nil then
                    ____opt_14("wait")
                end
            end
            waiting = true
            local ____temp_16
            if o.waitClear ~= nil and n ~= nil then
                ____temp_16 = clearPoint(bot, n, o.waitClear)
            else
                ____temp_16 = nil
            end
            local back = ____temp_16
            if back ~= nil then
                stand = back
                approached = true
                arrived = false
                best = math.huge
                bestAt = t
                local ____math_max_19 = math.max
                local ____this_18
                ____this_18 = bot
                local ____opt_17 = ____this_18.GetCurrentMovementSpeed
                local speed = ____math_max_19(
                    1,
                    ____opt_17 and ____opt_17(____this_18) or 300
                )
                local hit = bot.GetAttackPoint == nil and AGGRO_LEAD_DEFAULT or E().Verbs.ownHitTime(bot, n)
                clearLead = math.min(
                    AGGRO_LEAD_MAX,
                    math.max(
                        0,
                        o.waitClear - bot:GetAttackRange()
                    ) / speed + hit
                )
                bot:Action_MoveToLocation(stand)
            else
                hold(bot, "job_wait")
            end
        end
        coroutine.yield()
    end
    local ____opt_20 = h.label
    if ____opt_20 ~= nil then
        ____opt_20("aggro")
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
            local ____opt_22 = o.onTarget
            if ____opt_22 ~= nil then
                ____opt_22(n)
            end
        end
        return n
    end
    local hit = __TS__DelegatedYield(E().Verbs.attackAndConfirm(
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
    local ____opt_24 = o.onAggro
    if ____opt_24 ~= nil then
        ____opt_24({
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
--- Camp stack: travel, wait at the stand point, a confirmed hit landing on
-- the aggro second (+ skill error), walk off along `exitPath`, stay out until `exitUntil`. Labels `travel`, `wait`,
-- `aggro` (twice for a double), `exit`; urgent until the last hit lands.
____exports.stack = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local err = p.timingError or E().Skill.timingError(bot)
    local ____opt_26 = h.urgent
    if ____opt_26 ~= nil then
        ____opt_26(true)
    end
    if p.first ~= nil then
        local f = __TS__DelegatedYield(aggroCamp(
            bot,
            p.first.camp,
            p.first.aggroAt,
            err,
            p,
            h
        ))
        if not f.success then
            return f
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
    local ____opt_28 = h.urgent
    if ____opt_28 ~= nil then
        ____opt_28(false)
    end
    local ____opt_30 = h.label
    if ____opt_30 ~= nil then
        ____opt_30("exit")
    end
    local arrive = p.arrive or ARRIVE
    __TS__DelegatedYield(E().Verbs.walkPath(bot, p.exitPath, {tolerance = arrive, timeout = math.huge, stuckSecs = math.huge, deadline = p.exitUntil}))
    local held = __TS__DelegatedYield(E().Verbs.waitUntil(bot, p.exitUntil, {hold = "stack_exit"}))
    return held.success and ok() or held
end)
local stepBack = __TS__Generator(function(bot, p, h)
    local ____opt_32 = h.label
    if ____opt_32 ~= nil then
        ____opt_32("bail")
    end
    local ____until = now() + (p.bailFor or BAIL_FOR)
    while now() < ____until do
        if not bot:IsAlive() then
            return fail("dead")
        end
        local to = p.bail()
        if to == nil then
            break
        end
        bot:Action_MoveToLocation(to)
        coroutine.yield()
    end
    return fail("interrupted", "bail")
end)
--- Pull (full, half, double: the kind is in the data). Aggro the camp so the hit lands on its second (+ one skill
-- error for the whole job), with `holdUntil` hold there taking the camp's hits until the leave time, lead it along `lead` to the
-- meet point, then watch there. Labels `travel`, `wait`, `aggro` (twice for a double), `hold`, `lead`, `watch`; urgent until the lead is done.
-- Grading the divert is the host's.
____exports.pull = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local err = p.timingError or E().Skill.timingError(bot)
    local ____opt_34 = h.urgent
    if ____opt_34 ~= nil then
        ____opt_34(true)
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
    local seen = false
    local function held()
        if p.holdUntil == nil then
            return nil
        end
        if not seen and p.aggroed ~= nil and p.aggroed() then
            seen = true
        end
        if not seen and p.aggroed ~= nil and now() >= p.holdUntil() + (p.aggroFor or AGGRO_FOR) then
            return fail("timeout", "no-aggro")
        end
        local ____opt_36 = p.deadline
        local cause = ____opt_36 and ____opt_36()
        return cause ~= nil and fail("timeout", "deadline:" .. cause) or nil
    end
    if p.holdUntil ~= nil then
        local ____opt_38 = h.label
        if ____opt_38 ~= nil then
            ____opt_38("hold")
        end
        while now() < p.holdUntil() do
            if not bot:IsAlive() then
                return fail("dead")
            end
            local ____end = held()
            if ____end ~= nil then
                return ____end
            end
            if p.bail ~= nil and p.bail() ~= nil then
                return __TS__DelegatedYield(stepBack(bot, p, h))
            end
            hold(bot, "job_hold")
            coroutine.yield()
        end
    end
    local ____opt_40 = h.label
    if ____opt_40 ~= nil then
        ____opt_40("lead")
    end
    local arrive = p.arrive or ARRIVE
    if #p.lead > 0 then
        local ended
        local led = __TS__DelegatedYield(E().Verbs.walkPath(
            bot,
            p.lead,
            {
                tolerance = arrive,
                timeout = math.huge,
                stuckSecs = 3,
                deadline = p.leadDeadline or p.aggroAt + err + LEAD_MAX_AFTER_AGGRO,
                interruptIf = (p.bail ~= nil or p.holdUntil ~= nil) and (function()
                    ended = held()
                    return ended ~= nil or p.bail ~= nil and p.bail() ~= nil
                end) or nil
            }
        ))
        if not led.success and led.reason == "interrupted" and ended ~= nil then
            return ended
        end
        if not led.success and led.reason == "interrupted" and p.bail ~= nil then
            return __TS__DelegatedYield(stepBack(bot, p, h))
        end
        if not led.success then
            return fail(led.reason, "lead")
        end
    end
    local ____opt_42 = h.urgent
    if ____opt_42 ~= nil then
        ____opt_42(false)
    end
    local ____opt_44 = h.label
    if ____opt_44 ~= nil then
        ____opt_44("watch")
    end
    local spot = #p.lead > 0 and p.lead[#p.lead] or bot:GetLocation()
    local least = now() + (p.watchSec or WATCH_SEC)
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        local ____temp_46
        if type(p.watchUntil) == "function" then
            ____temp_46 = p.watchUntil()
        else
            ____temp_46 = p.watchUntil
        end
        local w = ____temp_46
        if now() >= math.max(least, w or 0) then
            return ok()
        end
        if p.bail ~= nil and p.bail() ~= nil then
            return __TS__DelegatedYield(stepBack(bot, p, h))
        end
        local ____opt_47 = p.watchAt
        local at = ____opt_47 and ____opt_47()
        local to = at or spot
        if dist(
            bot:GetLocation(),
            to
        ) > (at ~= nil and 30 or arrive) then
            bot:Action_MoveToLocation(to)
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
        err = arrivalErrors[key] or E().Skill.timingError(bot)
        arrivalErrors[key] = err
    end
    return p.spawnAt - (p.early or RUNE_EARLY) * E().Skill.lerp(
        RUNE_EARLY_LOW,
        1,
        E().Skill.of(bot)
    ) + err
end
--- When to start `runeRun` to arrive by `runeArriveBy`, from the straight-line walk at the current speed.
function ____exports.runeLeaveAt(bot, p)
    local ____math_max_51 = math.max
    local ____this_50
    ____this_50 = bot
    local ____opt_49 = ____this_50.GetCurrentMovementSpeed
    local speed = ____math_max_51(
        1,
        ____opt_49 and ____opt_49(____this_50) or 300
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
    local ____opt_52 = h.label
    if ____opt_52 ~= nil then
        ____opt_52("travel")
    end
    local ____array_54 = __TS__SparseArrayNew(unpack(p.via or ({})))
    __TS__SparseArrayPush(____array_54, p.at)
    local legs = {__TS__SparseArraySpread(____array_54)}
    do
        local i = 0
        while i < #legs do
            local walked = __TS__DelegatedYield(E().Verbs.walkTo(bot, legs[i + 1], {tolerance = i < #legs - 1 and ARRIVE or tolerance, timeout = math.huge, stuckSecs = math.huge, deadline = p.spawnAt + (p.lateBy or RUNE_LATE_BY)}))
            if not walked.success then
                return walked.reason == "timeout" and fail("timeout", "late") or walked
            end
            i = i + 1
        end
    end
    local ____opt_55 = h.label
    if ____opt_55 ~= nil then
        ____opt_55("wait")
    end
    local go = math.max(
        p.spawnAt,
        now()
    ) + E().Skill.react(bot)
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
        local ____opt_57 = h.label
        if ____opt_57 ~= nil then
            ____opt_57("channel")
        end
        local radius = p.radius or SHRINE_RADIUS
        local from
        while true do
            if not bot:IsAlive() then
                return fail("dead")
            end
            local t = now()
            local ____opt_59 = p.confirmed
            if (____opt_59 and ____opt_59()) == true then
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
    local ____opt_61 = h.label
    if ____opt_61 ~= nil then
        ____opt_61("pickup")
    end
    local graceUntil = go + RUNE_GRACE
    while true do
        local r = __TS__DelegatedYield(E().Verbs.pickUpRune(
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
--- The 6:00 spawn run (slice rune-spawn): walk to the stand point, hold there out of sight until the walk in arrives
-- `early` before the spawn, walk to the spot, then one reaction delay after the spawn act on the host's decision: pick the
-- rune up (take, or cross to the other spot), attack-move onto the spot to deny it, or end (`cancelled` "off", or
-- `no_target` "rune missing"). Late to the stand, it walks straight in. Labels `stand`, `hide`, `walk`, `decide`, then
-- `pickup` or `deny`.
____exports.runeSpawnRun = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local function speed()
        local ____math_max_65 = math.max
        local ____this_64
        ____this_64 = bot
        local ____opt_63 = ____this_64.GetCurrentMovementSpeed
        return ____math_max_65(
            1,
            ____opt_63 and ____opt_63(____this_64) or 300
        )
    end
    local function walkInAt()
        return p.spawnAt - p.early - dist(p.stand, p.at) / speed()
    end
    local ____opt_66 = h.label
    if ____opt_66 ~= nil then
        ____opt_66("stand")
    end
    local ____opt_68 = p.phase
    if ____opt_68 ~= nil then
        ____opt_68("stand")
    end
    local stood = __TS__DelegatedYield(E().Verbs.walkTo(
        bot,
        p.stand,
        {
            tolerance = 120,
            timeout = math.huge,
            stuckSecs = 2,
            deadline = walkInAt()
        }
    ))
    if not stood.success and stood.reason == "dead" then
        return stood
    end
    if stood.success then
        local ____opt_70 = h.label
        if ____opt_70 ~= nil then
            ____opt_70("hide")
        end
        local ____opt_72 = p.phase
        if ____opt_72 ~= nil then
            ____opt_72("hide")
        end
        while now() < walkInAt() do
            if not bot:IsAlive() then
                return fail("dead")
            end
            if dist(
                bot:GetLocation(),
                p.stand
            ) > 120 then
                bot:Action_MoveToLocation(p.stand)
            else
                hold(bot, "rune_hide")
            end
            coroutine.yield()
        end
    end
    local ____opt_74 = h.label
    if ____opt_74 ~= nil then
        ____opt_74("walk")
    end
    local ____opt_76 = p.phase
    if ____opt_76 ~= nil then
        ____opt_76("walk")
    end
    local walked = __TS__DelegatedYield(E().Verbs.walkTo(bot, p.at, {tolerance = 150, timeout = math.huge, stuckSecs = math.huge, deadline = p.spawnAt + RUNE_LATE_BY}))
    if not walked.success then
        return walked.reason == "timeout" and fail("timeout", "late") or walked
    end
    local go = math.max(
        p.spawnAt,
        now()
    ) + E().Skill.react(bot)
    while now() < go do
        if not bot:IsAlive() then
            return fail("dead")
        end
        hold(bot, "rune_wait")
        coroutine.yield()
    end
    local ____opt_78 = h.label
    if ____opt_78 ~= nil then
        ____opt_78("decide")
    end
    local act = "none"
    local ____until = now() + (p.decideFor or RUNE_GRACE)
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        act = p.decide()
        if act ~= "none" or now() >= ____until then
            break
        end
        hold(bot, "rune_wait")
        coroutine.yield()
    end
    local ____opt_80 = p.phase
    if ____opt_80 ~= nil then
        ____opt_80("decide", act)
    end
    if act == "take" or act == "cross" then
        local ____opt_82 = h.label
        if ____opt_82 ~= nil then
            ____opt_82("pickup")
        end
        local rune = act == "take" and p.rune or p.otherRune
        return __TS__DelegatedYield(E().Verbs.pickUpRune(bot, rune, {at = act == "take" and p.at or p.otherAt, timeout = RUNE_PICKUP_FOR}))
    end
    if act == "deny" then
        local ____opt_84 = h.label
        if ____opt_84 ~= nil then
            ____opt_84("deny")
        end
        local ____end = now() + (p.denyFor or 3)
        while now() < ____end do
            if not bot:IsAlive() then
                return fail("dead")
            end
            local ____opt_86 = p.denyResult
            local r = ____opt_86 and ____opt_86()
            if r == "gone" then
                return ok()
            end
            if r == "taken" then
                return fail("taken_by_other", "deny")
            end
            bot:Action_AttackMove(p.at)
            coroutine.yield()
        end
        return fail("missed", "deny")
    end
    if act == "off" then
        return fail("cancelled", "off")
    end
    return fail("no_target", "rune missing")
end)
local CLEAR_RADIUS = 700
local CLEAR_ARRIVE = 300
local CLEAR_SEARCH = 1600
local CLEAR_EMPTY_AFTER = 0.5
local CLEAR_REORDER = 1
--- `lastHit`'s wait for the kill to be due (its own default, 1.5 s): past it the verb asks the host again.
local CLEAR_LH_WAIT = 1.5
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
            local __continue124
            repeat
                local ____opt_88 = n.IsNull
                local ____temp_90 = ____opt_88 and ____opt_88(n)
                if ____temp_90 == nil then
                    ____temp_90 = false
                end
                local ____temp_94 = ____temp_90 or not n:IsAlive()
                if not ____temp_94 then
                    local ____opt_91 = n.CanBeSeen
                    local ____temp_93 = ____opt_91 and ____opt_91(n)
                    if ____temp_93 == nil then
                        ____temp_93 = true
                    end
                    ____temp_94 = not ____temp_93
                end
                if ____temp_94 then
                    __continue124 = true
                    break
                end
                if dist(
                    n:GetLocation(),
                    p.at
                ) <= r then
                    out[#out + 1] = n
                end
                __continue124 = true
            until true
            if not __continue124 then
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
-- With `p.lastHit` the host may have a neutral's kill taken with the engine's `lastHit` instead of a plain attack.
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
    local targetAt
    local plain = {}
    local ____opt_95 = h.label
    if ____opt_95 ~= nil then
        ____opt_95("go")
    end
    while true do
        do
            local __continue134
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
                        local __continue137
                        repeat
                            local ____this_98
                            ____this_98 = e.n
                            local ____opt_97 = ____this_98.IsNull
                            local ____temp_99 = ____opt_97 and ____opt_97(____this_98)
                            if ____temp_99 == nil then
                                ____temp_99 = false
                            end
                            local alive = not ____temp_99 and e.n:IsAlive()
                            if not alive then
                                __continue137 = true
                                break
                            end
                            local inCamp = __TS__ArrayIndexOf(camp, e.n) >= 0
                            local ____inCamp_103 = inCamp
                            if not ____inCamp_103 then
                                local ____this_101
                                ____this_101 = e.n
                                local ____opt_100 = ____this_101.CanBeSeen
                                local ____temp_102 = ____opt_100 and ____opt_100(____this_101)
                                if ____temp_102 == nil then
                                    ____temp_102 = true
                                end
                                ____inCamp_103 = ____temp_102
                            end
                            local visibleNow = ____inCamp_103
                            local at = visibleNow and t or e.at
                            if t - at > CLEAR_LOST then
                                __continue137 = true
                                break
                            end
                            if not inCamp and visibleNow then
                                camp[#camp + 1] = e.n
                            end
                            kept[#kept + 1] = {n = e.n, at = at}
                            __continue137 = true
                        until true
                        if not __continue137 then
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
                    if targetAt ~= nil then
                        local ____opt_104 = p.onGone
                        if ____opt_104 ~= nil then
                            ____opt_104(target, targetAt, #camp)
                        end
                    end
                    target = nil
                    targetAt = nil
                    nextOrderAt = t + E().Skill.react(bot)
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
                    __continue134 = true
                    break
                end
                emptySince = nil
                fought = true
                if t < nextOrderAt then
                    hold(bot, "camp_react")
                    coroutine.yield()
                    __continue134 = true
                    break
                end
                local ____target_107 = target
                if ____target_107 == nil then
                    local ____temp_106
                    if p.pick ~= nil then
                        ____temp_106 = p.pick(camp)
                    else
                        ____temp_106 = nil
                    end
                    ____target_107 = ____temp_106
                end
                local next = ____target_107 or lowestHp(camp)
                local fresh = next ~= target
                target = next
                targetAt = next:GetLocation()
                if not engaged and dist(
                    bot:GetLocation(),
                    next:GetLocation()
                ) <= bot:GetAttackRange() + ENGAGE_SLACK then
                    engaged = true
                    local ____opt_108 = h.label
                    if ____opt_108 ~= nil then
                        ____opt_108("farm")
                    end
                    local ____opt_110 = p.onEngage
                    if ____opt_110 ~= nil then
                        ____opt_110(t)
                    end
                end
                if p.lastHit ~= nil and __TS__ArrayIndexOf(plain, next) < 0 and p.lastHit(next, camp) then
                    local campN = #camp
                    local r = __TS__DelegatedYield(E().Verbs.lastHit(bot, {target = next, maxWait = CLEAR_LH_WAIT, deadline = p.deadline, hold = "camp_lasthit"}))
                    local ____opt_112 = p.onLastHit
                    if ____opt_112 ~= nil then
                        ____opt_112(next, r, campN)
                    end
                    if not r.success and (r.reason == "etiquette" or r.reason == "unsupported") then
                        plain[#plain + 1] = next
                    end
                    orderedAt = -math.huge
                    if r.reason == "unsupported" or r.reason == "etiquette" then
                        coroutine.yield()
                    end
                    __continue134 = true
                    break
                end
                if fresh or t - orderedAt >= (p.reorder or CLEAR_REORDER) then
                    bot:Action_AttackUnit(next, false)
                    orderedAt = t
                end
                coroutine.yield()
                __continue134 = true
            until true
            if not __continue134 then
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
    local ____temp_117 = t ~= nil
    if ____temp_117 then
        local ____this_115
        ____this_115 = t
        local ____opt_114 = ____this_115.IsNull
        local ____temp_116 = ____opt_114 and ____opt_114(____this_115)
        if ____temp_116 == nil then
            ____temp_116 = false
        end
        ____temp_117 = not ____temp_116
    end
    local ____temp_121 = ____temp_117 and t:IsAlive()
    if ____temp_121 then
        local ____this_119
        ____this_119 = t
        local ____opt_118 = ____this_119.CanBeSeen
        local ____temp_120 = ____opt_118 and ____opt_118(____this_119)
        if ____temp_120 == nil then
            ____temp_120 = true
        end
        ____temp_121 = ____temp_120
    end
    return ____temp_121
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
        local ____math_max_124 = math.max
        local ____this_123
        ____this_123 = bot
        local ____opt_122 = ____this_123.GetCurrentMovementSpeed
        return ____math_max_124(
            1,
            ____opt_122 and ____opt_122(____this_123) or 300
        )
    end
    local wp = 0
    local lastSeen
    local lostAt
    local telegraphed = p.telegraph == nil
    local engagedAt
    local attackAt
    local orderedAt = -math.huge
    local ____opt_125 = h.label
    if ____opt_125 ~= nil then
        ____opt_125("travel")
    end
    while true do
        if not bot:IsAlive() then
            return fail("dead")
        end
        local t = now()
        local ____opt_127 = p.commit
        local why = ____opt_127 and ____opt_127()
        if why ~= nil then
            return fail("interrupted", why)
        end
        local target = p.target()
        local ____temp_132 = target ~= nil
        if ____temp_132 then
            local ____opt_129 = target.IsNull
            local ____temp_131 = ____opt_129 and ____opt_129(target)
            if ____temp_131 == nil then
                ____temp_131 = false
            end
            ____temp_132 = not ____temp_131
        end
        if ____temp_132 and not target:IsAlive() then
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
                attackAt = t + E().Skill.react(bot)
                local ____opt_133 = h.label
                if ____opt_133 ~= nil then
                    ____opt_133("engage")
                end
                local ____opt_135 = h.urgent
                if ____opt_135 ~= nil then
                    ____opt_135(true)
                end
                local ____opt_137 = p.onEngage
                if ____opt_137 ~= nil then
                    ____opt_137(t)
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
