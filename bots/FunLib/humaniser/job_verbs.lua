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
local LEAD_MAX_AFTER_AGGRO = 15
local WATCH_SEC = 8
--- Seconds early to arrive at a rune (players aim for 3-5 s).
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
            local __continue14
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
                    __continue14 = true
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
                    __continue14 = true
                    break
                end
                local d = dist(here, p)
                if d < bestD then
                    best = n
                    bestD = d
                end
                __continue14 = true
            until true
            if not __continue14 then
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
    local function there()
        return dist(
            bot:GetLocation(),
            stand
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
        if n == nil and not approached and there() and t >= at - (o.approachLead or APPROACH_LEAD) then
            approached = true
            stand = camp.approach
            waiting = false
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
--- Camp stack: travel, wait at the stand point, a confirmed hit landing on
-- the aggro second (+ skill error), walk off along `exitPath`, stay out until `exitUntil`. Labels `travel`, `wait`,
-- `aggro`, `exit`; urgent until the hit lands.
____exports.stack = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local err = p.timingError or E().Skill.timingError(bot)
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
    __TS__DelegatedYield(E().Verbs.walkPath(bot, p.exitPath, {tolerance = arrive, timeout = math.huge, stuckSecs = math.huge, deadline = p.exitUntil}))
    local held = __TS__DelegatedYield(E().Verbs.waitUntil(bot, p.exitUntil, {hold = "stack_exit"}))
    return held.success and ok() or held
end)
--- Pull (full, half, double: the kind is in the data). Aggro the camp so the hit lands on its second (+ one skill
-- error for the whole job), lead it along `lead` to the meet point, then watch there. Labels `travel`, `wait`,
-- `aggro` (twice for a double), `lead`, `watch`; urgent until the lead is done. Grading the divert is the host's.
____exports.pull = __TS__Generator(function(bot, p, h)
    if h == nil then
        h = {}
    end
    local err = p.timingError or E().Skill.timingError(bot)
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
        local led = __TS__DelegatedYield(E().Verbs.walkPath(bot, p.lead, {tolerance = arrive, timeout = math.huge, stuckSecs = 3, deadline = p.leadDeadline or p.aggroAt + err + LEAD_MAX_AFTER_AGGRO}))
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
    local walked = __TS__DelegatedYield(E().Verbs.walkTo(bot, p.at, {tolerance = tolerance, timeout = math.huge, stuckSecs = math.huge, deadline = p.spawnAt + (p.lateBy or RUNE_LATE_BY)}))
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
            local __continue73
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
                    __continue73 = true
                    break
                end
                if dist(
                    n:GetLocation(),
                    p.at
                ) <= r then
                    out[#out + 1] = n
                end
                __continue73 = true
            until true
            if not __continue73 then
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
            local __continue83
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
                        local __continue86
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
                                __continue86 = true
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
                                __continue86 = true
                                break
                            end
                            if not inCamp and visibleNow then
                                camp[#camp + 1] = e.n
                            end
                            kept[#kept + 1] = {n = e.n, at = at}
                            __continue86 = true
                        until true
                        if not __continue86 then
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
                    __continue83 = true
                    break
                end
                emptySince = nil
                fought = true
                if t < nextOrderAt then
                    hold(bot, "camp_react")
                    coroutine.yield()
                    __continue83 = true
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
                __continue83 = true
            until true
            if not __continue83 then
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
                attackAt = t + E().Skill.react(bot)
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
