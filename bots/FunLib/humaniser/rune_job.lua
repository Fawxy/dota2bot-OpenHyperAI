--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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
local key, planFor, closestOn, dropFromPlan, canStillArrive, nearestEnemy, offerGank, running, handled, body, playFight
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Rune = ____dota.Rune
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local RunePlan = require(GetScriptDirectory().."/FunLib/humaniser/rune_plan")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local Rotate = require(GetScriptDirectory().."/FunLib/humaniser/states/rotate")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- A support with a stack open that minute is not free for the 6:00 plan (pos5's trip yields to its stack).
function ____exports.Busy(u)
    return LaneConfig.PositionOf(u) == 5 and StackJob.Pending(u)
end
function key(kind, spawn)
    return (kind .. ":") .. tostring(spawn)
end
function planFor(t)
    if t.kind == "wisdom" or t.kind == "contest" then
        return {
            at = t.at,
            via = t.via,
            spawnAt = t.spawn,
            channel = ____exports.SETTINGS.ShrineChannel,
            radius = ____exports.SETTINGS.ShrineRadius,
            tolerance = ____exports.SETTINGS.ShrineRadius - 100,
            lateBy = ____exports.SETTINGS.LateBy.wisdom,
            pickupFor = 20
        }
    end
    return {at = t.at, spawnAt = t.spawn, rune = t.rune, lateBy = ____exports.SETTINGS.LateBy.power}
end
--- Valve's waypoints (the first is the start) with a point kept only where skipping it would make a leg longer than RouteStep.
function ____exports.Thin(wp, to)
    local out = {}
    local last = wp[1]
    do
        local i = 1
        while i < #wp do
            if FR.Dist(last, wp[i + 1 + 1] or to) > ____exports.SETTINGS.RouteStep then
                out[#out + 1] = wp[i + 1]
                last = wp[i + 1]
            end
            i = i + 1
        end
    end
    return out
end
function closestOn(a, b, p)
    local dx = b.x - a.x
    local dy = b.y - a.y
    local l2 = dx * dx + dy * dy
    local k = l2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2)
    ) or 0
    return Vector(a.x + k * dx, a.y + k * dy, a.z)
end
body = __TS__Generator(function(bot, t, ctx)
    local hooks = {
        label = function(l)
            ctx.label(l)
            if (l == "wait" or l == "channel" or l == "decide") and t.arr == nil then
                t.arr = DotaTime()
            end
        end,
        urgent = ctx.urgent
    }
    if t.stand ~= nil and t.rune ~= nil then
        local r = __TS__DelegatedYield(Tasks.Jobs().runeSpawnRun(
            bot,
            ____exports.spawnPlanFor(bot, t),
            hooks
        ))
        if t.fight ~= nil then
            __TS__DelegatedYield(playFight(bot, t.fight, hooks))
        elseif LaneConfig.PositionOf(bot) ~= 2 and bot:IsAlive() then
            t.gank = offerGank(bot)
            if t.gank ~= nil then
                __TS__DelegatedYield(playFight(bot, t.gank, hooks))
            end
        end
        return r
    end
    return __TS__DelegatedYield(Tasks.Jobs().runeRun(
        bot,
        planFor(t),
        hooks
    ))
end)
function dropFromPlan(bot, why)
    local next = RunePlan.Drop(bot, why, ____exports.Busy)
    if next == nil then
        return
    end
    local pid = next:GetPlayerID()
    handled[pid] = handled[pid] or ({})
    handled[pid][key("power", RunePlan.SETTINGS.Spawn)] = false
end
function canStillArrive(bot, t)
    return t.stand ~= nil and RunePlan.Replaces(bot) and DotaTime() + RunePlan.WalkSecs(bot, t.at) * ____exports.SETTINGS.PathFactor <= t.spawn
end
function nearestEnemy(at, within)
    local best
    local bestD = within
    for ____, e in ipairs(FR.EnemiesNear(at, within)) do
        local d = FR.Dist(
            e:GetLocation(),
            at
        )
        if d <= bestD then
            best, bestD = e, d
        end
    end
    return best
end
function offerGank(bot)
    local e = nearestEnemy(
        bot:GetLocation(),
        ____exports.SETTINGS.GankReach
    )
    if e == nil then
        return nil
    end
    return Plays.Roll({
        kind = "gank",
        by = bot,
        target = e,
        at = e:GetLocation()
    })
end
--- A fired gank or rune fight: the gank verb on the play's target, straight in, ended by the verb or the play's stops.
playFight = __TS__Generator(function(bot, play, hooks)
    local target = play.target
    local r = __TS__DelegatedYield(Tasks.Jobs().gank(
        bot,
        {
            target = function() return FR.Alive(target) and target or nil end,
            path = {},
            deadline = DotaTime() + ____exports.SETTINGS.GankEngageBy,
            engageFor = ____exports.SETTINGS.GankFightFor,
            commit = function() return FR.HpFraction(bot) < ____exports.SETTINGS.StopHp and "hp" or (FR.Alive(target) and FR.TowerDistance(
                target:GetTeam(),
                target:GetLocation()
            ) < ____exports.SETTINGS.StopTower and "tower" or nil) end
        },
        hooks
    ))
    Plays.End(play, r.success and (r.message or "ok") or r.reason .. (r.message ~= nil and ":" .. r.message or ""))
    return r
end)
--- The 6:00 spawn run's plan: the spot and stand from rune_plan, its race as the decision.
function ____exports.spawnPlanFor(bot, t)
    local other = RunePlan.Other(t.rune)
    local hideFrom
    return {
        rune = t.rune,
        at = t.at,
        otherRune = other,
        otherAt = RunePlan.SpotAt(other),
        stand = t.stand.at,
        spawnAt = t.spawn,
        early = RunePlan.SETTINGS.Early,
        decide = function()
            local act, race = unpack(RunePlan.Race(bot, t.rune))
            t.race = race
            if t.fight == nil and act ~= "none" and t.race ~= nil then
                local e = nearestEnemy(t.at, ____exports.SETTINGS.FightNear)
                if e ~= nil then
                    t.fight = Plays.Roll({kind = "rune_fight", by = bot, target = e, at = t.at})
                    if t.fight ~= nil then
                        return "off"
                    end
                end
            end
            return act
        end,
        denyResult = function() return RunePlan.DenyResult(t.rune) end,
        phase = function(name, act)
            if name == "hide" then
                hideFrom = DotaTime()
            end
            if name == "walk" and hideFrom ~= nil then
                t.hidden = math.floor((DotaTime() - hideFrom) * 10) / 10
            end
            if name == "decide" then
                t.act = act
            end
        end
    }
end
function ____exports.Step(bot, host)
    return running[bot:GetPlayerID()] ~= nil and Tasks.Step(bot, host)
end
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
____exports.SETTINGS = {
    Trips = {
        [4] = {{"power", 360}, {"wisdom", 420}},
        [5] = __TS__ArrayMap(
            {
                120,
                180,
                240,
                300,
                360,
                420,
                480
            },
            function(____, n) return {"contest", n} end
        )
    },
    Priority = {[4] = 0.95, [5] = 0.85},
    ClaimFrom = 60,
    StartSlack = 3,
    PathFactor = 1.2,
    LateBy = {power = 5, wisdom = 15, contest = 15},
    OwnFor = {power = 120, wisdom = 420, contest = 0},
    ShrineChannel = 3,
    ShrineRadius = 300,
    GankReach = 4000,
    GankEngageBy = 20,
    GankFightFor = 8,
    TowerAvoid = 1000,
    DetourMargin = 200,
    DetourMax = 3,
    RouteStep = 600,
    RouteMoved = 400,
    RouteFresh = 10,
    RouteEnds = 300,
    FightNear = 700,
    StopTower = 700,
    StopHp = 0.3,
    MidMinHp = 0.5
}
Plays.Define("gank", {base = 0.35, timeout = 30, chases = true})
Plays.Define(
    "rune_fight",
    {
        base = 0.5,
        timeout = 15,
        chases = false,
        sure = Plays.SureKill(____exports.SETTINGS.FightNear)
    }
)
Plays.Define("shrine", {base = 0.4, timeout = 60, chases = false})
--- The 6:00 power trip runs as rune_spawn's plan (spot plan, stand, timed walk) rather than the plain trip.
local function planned(kind, spawn)
    return kind == "power" and spawn == RunePlan.SETTINGS.Spawn and RunePlan.On()
end
running = {}
handled = {}
local gateWhy = {}
function ____exports.ResetCache()
    for k in pairs(running) do
        running[k] = nil
    end
    for k in pairs(handled) do
        handled[k] = {}
    end
    for k in pairs(gateWhy) do
        gateWhy[k] = nil
    end
end
function ____exports.Applies(bot)
    return Ours.On("RuneRotation") and Ours.On("JobChooser") and bot:IsBot() and ____exports.SETTINGS.Trips[LaneConfig.PositionOf(bot) or 0] ~= nil
end
--- This hero's rank for the chooser, or undefined when the job never applies to it.
function ____exports.Priority(bot)
    return ____exports.Applies(bot) and ____exports.SETTINGS.Priority[LaneConfig.PositionOf(bot) or 0] or nil
end
--- The trips still open for this bot now: from ClaimFrom before the spawn until its late limit, not yet handled.
local function open(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local out = {}
    for ____, ____value in ipairs(____exports.SETTINGS.Trips[LaneConfig.PositionOf(bot) or 0] or ({})) do
        local kind = ____value[1]
        local spawn = ____value[2]
        do
            local __continue13
            repeat
                if kind == "contest" and not RunePlan.On() then
                    __continue13 = true
                    break
                end
                local ____opt_0 = handled[pid]
                if (____opt_0 and ____opt_0[key(kind, spawn)]) ~= true and now >= spawn - ____exports.SETTINGS.ClaimFrom and now < spawn + ____exports.SETTINGS.LateBy[kind] then
                    out[#out + 1] = {kind, spawn}
                end
                __continue13 = true
            until true
            if not __continue13 then
                break
            end
        end
    end
    return out
end
--- True while a trip runs or is pending for this bot: lower-ranked jobs wait.
function ____exports.Claims(bot)
    return ____exports.Applies(bot) and (____exports.Running(bot) or #open(bot) > 0)
end
local function powerRunes()
    return __TS__ArrayMap(
        {Rune.Power1, Rune.Power2},
        function(____, r) return {
            r,
            GetRuneSpawnLocation(r)
        } end
    )
end
--- The power spot a teammate's trip already has, by rune id.
local function takenSpots(bot)
    local out = {}
    do
        local i = 1
        while i <= 5 do
            do
                local __continue21
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot then
                        __continue21 = true
                        break
                    end
                    local t = running[m:GetPlayerID()]
                    if t ~= nil and t.rune ~= nil then
                        out[t.rune] = true
                    end
                    __continue21 = true
                until true
                if not __continue21 then
                    break
                end
            end
            i = i + 1
        end
    end
    return out
end
--- Pos4: the power spot nearest it. Others: the nearest spot no teammate's trip has, else the nearest.
local function powerSpot(bot)
    local taken = LaneConfig.PositionOf(bot) == 4 and ({}) or takenSpots(bot)
    local best
    local bestCost = math.huge
    for ____, spot in ipairs(powerRunes()) do
        local cost = GetUnitToLocationDistance(bot, spot[2]) + (taken[spot[1]] and 1000000 or 0)
        if cost < bestCost then
            best, bestCost = spot, cost
        end
    end
    return best
end
--- When to leave for the trip: the verb's skill-scaled arrival less the walk (path factor on the straight line).
local function leaveAt(bot, t)
    if t.stand ~= nil then
        return RunePlan.LeaveAt(bot, t.stand.at, t.at)
    end
    local u = bot
    local arrive = Tasks.Jobs().runeArriveBy(
        u,
        planFor(t)
    )
    local walk = 0
    local from = bot:GetLocation()
    local ____array_2 = __TS__SparseArrayNew(unpack(t.via or ({})))
    __TS__SparseArrayPush(____array_2, t.at)
    for ____, to in ipairs({__TS__SparseArraySpread(____array_2)}) do
        walk, from = walk + FR.Dist(from, to), to
    end
    return arrive - walk * ____exports.SETTINGS.PathFactor / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
--- CANDIDATE(route): waypoints from `from` to `to` that keep each leg TowerAvoid from every tower in `towers`: a leg passing
-- closer gets a point beside the nearest such tower, on the side the leg passes (the other side when that is not
-- passable), at most DetourMax points. rspchk1: both fired shrine contests walked past the enemy's tower and OHA's retreat
-- took the hero (405 s, retreat 1.10 and 1.26). Exported for tests.
function ____exports.Detour(from, to, towers)
    local s = ____exports.SETTINGS
    local via = {}
    local a = from
    do
        local n = 0
        while n < s.DetourMax do
            local worst
            local worstD = s.TowerAvoid
            local near = a
            for ____, tw in ipairs(towers) do
                local c = closestOn(a, to, tw)
                local d = FR.Dist(c, tw)
                if d < worstD then
                    worst, worstD, near = tw, d, c
                end
            end
            if worst == nil then
                break
            end
            local dx = near.x - worst.x
            local dy = near.y - worst.y
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 1 then
                dx, dy, len = -(to.y - a.y), to.x - a.x, math.max(
                    1,
                    FR.Dist(a, to)
                )
            end
            local r = s.TowerAvoid + s.DetourMargin
            local p = Vector(worst.x + dx / len * r, worst.y + dy / len * r, worst.z)
            if not IsLocationPassable(p) then
                p = Vector(worst.x - dx / len * r, worst.y - dy / len * r, worst.z)
            end
            via[#via + 1] = p
            a = p
            n = n + 1
        end
    end
    return via
end
local paths = {}
--- Answers PathVia threw away since the hero's last rune_job line, as `vbad`.
local rejected = {}
--- CANDIDATE(route): Valve's walking path from the hero to `to`, as waypoints before `to`, legs merged up to RouteStep; undefined
-- until an answer asked within RouteMoved of where the hero is now and at most RouteFresh s ago arrives (an older answer
-- starts from somewhere else: its first leg is a straight line that can cross the lane by a tower). A request that has not
-- answered in a second is sent again. The callback's arguments are (distance, request id, waypoints), not the (distance,
-- waypoints) of Valve's docs, and it runs on a later frame (probe genpath5, 04/11/2026: 10 of 24 requests in one frame
-- called back). Avoidance zones changed no path (genpath5 to genpath7); from the contest's starts in rspchk4 at 6:30,
-- Valve's path kept 1,108-1,912 from every enemy tower (genpath7), outside OHA retreat's 898 (`X.ShouldRun`). An answer
-- that does not run from where it was asked to `to` is dropped: rspchk5's five contests walked fresh answers (0.9-9.9 s,
-- asked 82-331 away) that kept only 540-596 from a tower, with 7-10 waypoints where the probe's path from such starts has
-- 11-14 and keeps 1,677-1,912, so the answers were likely another request's.
function ____exports.PathVia(bot, to)
    if type(GeneratePath) == "nil" then
        return nil
    end
    local pid = bot:GetPlayerID()
    local here = bot:GetLocation()
    local c = paths[pid]
    local fits = c ~= nil and FR.Dist(c.to, to) <= 1 and FR.Dist(c.from, here) <= ____exports.SETTINGS.RouteMoved and DotaTime() - c.asked <= ____exports.SETTINGS.RouteFresh
    if not fits or c.via == nil and DotaTime() - c.asked > 1 then
        local entry = {
            from = here,
            asked = DotaTime(),
            to = to
        }
        paths[pid] = entry
        GeneratePath(
            here,
            to,
            {},
            function(...)
                local args = {...}
                for ____, a in ipairs(args) do
                    do
                        local __continue46
                        repeat
                            if type(a) ~= "table" then
                                __continue46 = true
                                break
                            end
                            local wp = a
                            if #wp > 0 and FR.Dist(wp[1], entry.from) <= ____exports.SETTINGS.RouteEnds and FR.Dist(wp[#wp], to) <= ____exports.SETTINGS.RouteEnds then
                                entry.via = ____exports.Thin(wp, to)
                            else
                                rejected[pid] = (rejected[pid] or 0) + 1
                            end
                            __continue46 = true
                        until true
                        if not __continue46 then
                            break
                        end
                    end
                end
            end
        )
        return nil
    end
    return c.via
end
--- The hero's path request is out and has not answered yet, within a second of asking.
function ____exports.PathPending(bot)
    local c = paths[bot:GetPlayerID()]
    return c ~= nil and c.via == nil and DotaTime() - c.asked <= 1
end
--- The answer behind PathVia's last route: its age and how far from the hero it was asked.
local function pathAge(bot)
    local c = paths[bot:GetPlayerID()]
    return (c and c.via) ~= nil and ({
        DotaTime() - c.asked,
        FR.Dist(
            c.from,
            bot:GetLocation()
        )
    }) or nil
end
local function takeRejected(bot)
    local n = rejected[bot:GetPlayerID()] or 0
    rejected[bot:GetPlayerID()] = 0
    return n
end
--- The least distance from any tower to the walk from `from` through `legs`.
function ____exports.Clearance(from, legs, towers)
    local min = math.huge
    local a = from
    for ____, b in ipairs(legs) do
        for ____, tw in ipairs(towers) do
            min = math.min(
                min,
                FR.Dist(
                    closestOn(a, b, tw),
                    tw
                )
            )
        end
        a = b
    end
    return min
end
local function tripFor(bot, kind, spawn, host, mine)
    if kind == "wisdom" then
        return {
            kind = kind,
            spawn = spawn,
            at = Rotate.ShrineFor(bot:GetTeam()),
            left = DotaTime(),
            host = host
        }
    end
    if kind == "contest" then
        local enemy = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
        local at = Rotate.ShrineFor(enemy)
        local towers = FR.TowerSpots(enemy)
        local path = ____exports.PathVia(bot, at)
        local via = path or ____exports.Detour(
            bot:GetLocation(),
            at,
            towers
        )
        local ____temp_5
        if path ~= nil then
            ____temp_5 = pathAge(bot)
        else
            ____temp_5 = nil
        end
        local age = ____temp_5
        local ____kind_9 = kind
        local ____spawn_10 = spawn
        local ____at_11 = at
        local ____via_12 = via
        local ____temp_13 = path ~= nil and "path" or "detour"
        local ____exports_Clearance_8 = ____exports.Clearance
        local ____temp_7 = bot:GetLocation()
        local ____array_6 = __TS__SparseArrayNew(unpack(via))
        __TS__SparseArrayPush(____array_6, at)
        return {
            kind = ____kind_9,
            spawn = ____spawn_10,
            at = ____at_11,
            via = ____via_12,
            route = ____temp_13,
            clear = ____exports_Clearance_8(
                ____temp_7,
                {__TS__SparseArraySpread(____array_6)},
                towers
            ),
            pathAge = age,
            left = DotaTime(),
            host = host
        }
    end
    if mine ~= nil then
        local at = RunePlan.SpotAt(mine)
        return {
            kind = kind,
            spawn = spawn,
            at = at,
            rune = mine,
            side = at.y > 0 and "top" or "bot",
            left = DotaTime(),
            host = host,
            stand = RunePlan.StandFor(bot, at)
        }
    end
    local rune, at = unpack(powerSpot(bot))
    return {
        kind = kind,
        spawn = spawn,
        at = at,
        rune = rune,
        side = at.y > 0 and "top" or "bot",
        left = DotaTime(),
        host = host
    }
end
local function log(bot, kind, spawn, fields)
    Telemetry.Event(
        "rune_job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "pos",
                LaneConfig.PositionOf(bot)
            },
            {"kind", kind},
            {"spawn", spawn},
            unpack(fields)
        }
    )
end
local function jobLine(bot, t, phase, why)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "rune"},
            {"phase", phase},
            {"why", why},
            {"host", t.host},
            unpack(phase == "end" and ({{"hit", t.hit == true and 1 or 0}}) or ({}))
        }
    )
end
local function finish(bot, t, r, label)
    running[bot:GetPlayerID()] = nil
    local why = r.success and "ok" or r.reason .. (r.message ~= nil and ":" .. r.message or "")
    for ____, p in ipairs({t.play, t.fight, t.gank}) do
        if p ~= nil then
            Plays.End(p, "trip:" .. why, p == t.play and r.success and "contested" or nil)
        end
    end
    jobLine(bot, t, "end", why)
    local function r1(x)
        return x ~= nil and math.floor(x * 10) / 10 or nil
    end
    local ____log_27 = log
    local ____array_26 = __TS__SparseArrayNew(bot, t.kind, t.spawn)
    local ____array_25 = __TS__SparseArrayNew(
        {"res", r.success and "ok" or "fail"},
        {"why", why},
        {"label", label},
        {"side", t.side},
        {
            "left",
            r1(t.left)
        },
        {
            "arr",
            r1(t.arr)
        },
        {
            "away",
            r1(DotaTime() - t.left)
        },
        {
            "died",
            bot:IsAlive() and 0 or 1
        },
        {"hit", t.hit == true and 1 or 0},
        {"idle", t.idle},
        {"phase", t.act}
    )
    local ____temp_14
    if t.race ~= nil then
        ____temp_14 = r1(t.race.ours)
    else
        ____temp_14 = nil
    end
    __TS__SparseArrayPush(____array_25, {"ta", ____temp_14})
    local ____temp_15
    if t.race ~= nil and t.race.theirs < math.huge then
        ____temp_15 = r1(t.race.theirs)
    else
        ____temp_15 = nil
    end
    __TS__SparseArrayPush(____array_25, {"te", ____temp_15}, {"hid", t.hidden})
    local ____opt_16 = t.stand
    __TS__SparseArrayPush(____array_25, {"sh", ____opt_16 and ____opt_16.height})
    local ____opt_18 = t.stand
    __TS__SparseArrayPush(
        ____array_25,
        {"sph", ____opt_18 and ____opt_18.spotHeight},
        {"via", t.via ~= nil and #t.via or nil},
        {"route", t.route},
        {
            "vclr",
            t.clear ~= nil and math.floor(t.clear) or nil
        }
    )
    local ____temp_20
    if t.pathAge ~= nil then
        ____temp_20 = r1(t.pathAge[1])
    else
        ____temp_20 = nil
    end
    __TS__SparseArrayPush(
        ____array_25,
        {"vage", ____temp_20},
        {
            "voff",
            t.pathAge ~= nil and math.floor(t.pathAge[2]) or nil
        },
        {
            "vbad",
            t.kind == "contest" and takeRejected(bot) or nil
        }
    )
    local ____opt_21 = t.play or t.fight
    __TS__SparseArrayPush(____array_25, {"play", ____opt_21 and ____opt_21.id})
    local ____opt_23 = t.gank
    __TS__SparseArrayPush(____array_25, {"gank", ____opt_23 and ____opt_23.id})
    __TS__SparseArrayPush(
        ____array_26,
        {__TS__SparseArraySpread(____array_25)}
    )
    ____log_27(__TS__SparseArraySpread(____array_26))
end
--- OHA's own action holds the hero (a queued TP, a cast or channel): the host's Think does not step a job then
-- (J.CanNotUseAction), so a trip started now ends `never_started` (probe rr2: a pos4 in its fountain with a queued TP).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
--- Every frame while the chooser asks: true while a trip runs or as one starts. `blocked` says why a start must wait (the
-- chooser's checks, or a higher job's claim); `host` is the mode that will step the trip.
function ____exports.Wants(bot, blocked, host)
    if not ____exports.Applies(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    Plays.Tick()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    if Tasks.Jobs() == nil then
        return false
    end
    handled[pid] = handled[pid] or ({})
    for ____, ____value in ipairs(open(bot)) do
        local kind = ____value[1]
        local spawn = ____value[2]
        do
            local __continue79
            repeat
                local mine
                local function skip(why)
                    handled[pid][key(kind, spawn)] = true
                    gateWhy[pid] = nil
                    log(bot, kind, spawn, {{"res", "skip"}, {"why", why}})
                    if mine ~= nil and DotaTime() < spawn then
                        dropFromPlan(bot, why)
                    end
                    return false
                end
                if not bot:IsAlive() then
                    if DotaTime() >= spawn then
                        return skip("dead")
                    end
                    gateWhy[pid] = "dead"
                    __continue79 = true
                    break
                end
                if planned(kind, spawn) then
                    if DotaTime() < RunePlan.SETTINGS.PlanAt then
                        __continue79 = true
                        break
                    end
                    mine = RunePlan.SpotOf(bot, ____exports.Busy)
                    if mine == nil then
                        return skip("plan-other")
                    end
                end
                local t = tripFor(
                    bot,
                    kind,
                    spawn,
                    host,
                    mine
                )
                local leave = leaveAt(bot, t)
                if DotaTime() < leave then
                    return false
                end
                local why = blocked(bot) or (acting(bot) and "acting" or nil)
                if DotaTime() > leave + ____exports.SETTINGS.StartSlack and not canStillArrive(bot, t) then
                    return skip(gateWhy[pid] or why or "late")
                end
                if why ~= nil then
                    gateWhy[pid] = why
                    return false
                end
                if kind == "contest" then
                    if ____exports.Busy(bot) then
                        return skip("busy")
                    end
                    if t.route == "detour" and ____exports.PathPending(bot) then
                        return false
                    end
                end
                local ok = Tasks.Start(
                    bot,
                    {
                        name = "rune",
                        host = host,
                        preemptAfter = 1,
                        stallAfter = 4,
                        onEnd = function(r, info) return finish(bot, t, r, info.label) end
                    },
                    function(ctx) return body(bot, t, ctx) end
                )
                if not ok then
                    return skip("refused")
                end
                handled[pid][key(kind, spawn)] = true
                gateWhy[pid] = nil
                running[pid] = t
                jobLine(bot, t, "start", "trigger")
                return true
            until true
            if not __continue79 then
                break
            end
        end
    end
    return false
end
--- The rune mode's desire while the mid's trip runs: above laning's (up to about 0.95). Only OHA retreat's 1.0 and 1.1 returns
-- beat it; its HIGH and VERYHIGH returns (0.8, 0.9) lose once the trip runs (it starts only at MidMinHp or more).
____exports.MID_DESIRE = 0.97
local MID_HOST = BotMode.Rune
--- Ours.RuneSpawn, the mid's side of the 6:00 plan, every frame from the rune mode's GetDesire: true while its trip runs or
-- as it starts (the mode then returns MidDesire and steps it in Think). Not a chooser job: the mid has no other jobs, and
-- the rune mode is the mode Valve would give a rune walk.
function ____exports.MidWants(bot)
    if not RunePlan.On() or not bot:IsBot() or LaneConfig.PositionOf(bot) ~= 2 then
        return false
    end
    local pid = bot:GetPlayerID()
    Plays.Tick()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    if Tasks.Jobs() == nil then
        return false
    end
    local spawn = RunePlan.SETTINGS.Spawn
    local now = DotaTime()
    handled[pid] = handled[pid] or ({})
    local k = key("power", spawn)
    if handled[pid][k] == true or now < RunePlan.SETTINGS.PlanAt or now >= spawn + ____exports.SETTINGS.LateBy.power then
        return false
    end
    local mine = RunePlan.SpotOf(bot, ____exports.Busy)
    if mine == nil then
        return false
    end
    local function skip(why)
        handled[pid][k] = true
        log(bot, "power", spawn, {{"res", "skip"}, {"why", why}})
        return false
    end
    if not bot:IsAlive() then
        local ____temp_28
        if now >= spawn then
            ____temp_28 = skip("dead")
        else
            ____temp_28 = false
        end
        return ____temp_28
    end
    local t = tripFor(
        bot,
        "power",
        spawn,
        MID_HOST,
        mine
    )
    local leave = leaveAt(bot, t)
    if now < leave then
        return false
    end
    local why = bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MidMinHp and "low-hp" or (acting(bot) and "acting" or nil)
    if why ~= nil then
        local ____temp_29
        if now > leave + ____exports.SETTINGS.StartSlack then
            ____temp_29 = skip(why)
        else
            ____temp_29 = false
        end
        return ____temp_29
    end
    local ok = Tasks.Start(
        bot,
        {
            name = "rune",
            host = MID_HOST,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(r, info) return finish(bot, t, r, info.label) end
        },
        function(ctx) return body(bot, t, ctx) end
    )
    if not ok then
        return skip("refused")
    end
    handled[pid][k] = true
    running[pid] = t
    jobLine(bot, t, "start", "plan")
    return true
end
function ____exports.MidStep(bot)
    return LaneConfig.PositionOf(bot) == 2 and ____exports.Step(bot, MID_HOST)
end
--- The mode that steps this hero's running trip (the chooser's host, or the rune mode for the mid's 6:00 trip), if any.
function ____exports.HostOf(bot)
    local ____opt_30 = running[bot:GetPlayerID()]
    return ____opt_30 and ____opt_30.host
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
function ____exports.NoteIdleHeld(bot)
    local t = running[bot:GetPlayerID()]
    if t ~= nil then
        t.idle = (t.idle or 0) + 1
    end
end
--- This hero's spawn of `kind` is the job's to decide now, taken or skipped: OHA's rune mode stands aside (review 03/11/2026:
-- after a skip, OHA's wisdom branch walked the same pos4 to the shrine in 12 of 16 cases).
function ____exports.Owns(bot, kind)
    if not ____exports.Applies(bot) then
        return false
    end
    local now = DotaTime()
    for ____, ____value in ipairs(____exports.SETTINGS.Trips[LaneConfig.PositionOf(bot) or 0] or ({})) do
        local k = ____value[1]
        local spawn = ____value[2]
        if k == kind and now >= spawn - ____exports.SETTINGS.ClaimFrom and now < spawn + ____exports.SETTINGS.OwnFor[k] then
            return true
        end
    end
    return false
end
--- OHA's own wisdom logic leaves the shrine to `bot`: its own spawn is the job's (taken or skipped), or a teammate's trip is on
-- the shrine. Only the job's hero is held past a skip; the rest of the team stays OHA's (follow-up review 03/11/2026: a
-- team-wide hold left the shrine untaken after a skip, 9 of 30 within 15 s against OFF's 14).
function ____exports.ShrineHeld(bot)
    if ____exports.Owns(bot, "wisdom") then
        return true
    end
    do
        local i = 1
        while i <= 5 do
            do
                local __continue156
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m:GetTeam() ~= bot:GetTeam() then
                        __continue156 = true
                        break
                    end
                    local ____opt_32 = running[m:GetPlayerID()]
                    if (____opt_32 and ____opt_32.kind) == "wisdom" then
                        return true
                    end
                    __continue156 = true
                until true
                if not __continue156 then
                    break
                end
            end
            i = i + 1
        end
    end
    return false
end
return ____exports
