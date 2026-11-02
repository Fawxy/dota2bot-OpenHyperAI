--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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
local planFor, running, body
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Rune = ____dota.Rune
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Rotate = require(GetScriptDirectory().."/FunLib/humaniser/states/rotate")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function planFor(t)
    if t.kind == "wisdom" then
        return {
            at = t.at,
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
body = __TS__Generator(function(bot, t, ctx)
    local hooks = {
        label = function(l)
            ctx.label(l)
            if (l == "wait" or l == "channel") and t.arr == nil then
                t.arr = DotaTime()
            end
        end,
        urgent = ctx.urgent
    }
    return __TS__DelegatedYield(Tasks.Jobs().runeRun(
        bot,
        planFor(t),
        hooks
    ))
end)
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
____exports.SETTINGS = {
    Trips = {[4] = {{"power", 360}, {"wisdom", 420}}, [5] = {{"power", 360}}},
    Priority = {[4] = 0.95, [5] = 0.85},
    ClaimFrom = 60,
    StartSlack = 3,
    PathFactor = 1.2,
    LateBy = {power = 5, wisdom = 15},
    OwnFor = {power = 120, wisdom = 420},
    ShrineChannel = 3,
    ShrineRadius = 300
}
running = {}
local handled = {}
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
local function key(kind, spawn)
    return (kind .. ":") .. tostring(spawn)
end
--- The trips still open for this bot now: from ClaimFrom before the spawn until its late limit, not yet handled.
local function open(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local out = {}
    for ____, ____value in ipairs(____exports.SETTINGS.Trips[LaneConfig.PositionOf(bot) or 0] or ({})) do
        local kind = ____value[1]
        local spawn = ____value[2]
        local ____opt_0 = handled[pid]
        if (____opt_0 and ____opt_0[key(kind, spawn)]) ~= true and now >= spawn - ____exports.SETTINGS.ClaimFrom and now < spawn + ____exports.SETTINGS.LateBy[kind] then
            out[#out + 1] = {kind, spawn}
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
                local __continue17
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot then
                        __continue17 = true
                        break
                    end
                    local t = running[m:GetPlayerID()]
                    if t ~= nil and t.rune ~= nil then
                        out[t.rune] = true
                    end
                    __continue17 = true
                until true
                if not __continue17 then
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
    local u = bot
    local arrive = Tasks.Jobs().runeArriveBy(
        u,
        planFor(t)
    )
    return arrive - GetUnitToLocationDistance(bot, t.at) * ____exports.SETTINGS.PathFactor / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
local function tripFor(bot, kind, spawn, host)
    if kind == "wisdom" then
        return {
            kind = kind,
            spawn = spawn,
            at = Rotate.ShrineFor(bot:GetTeam()),
            left = DotaTime(),
            host = host
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
    jobLine(bot, t, "end", why)
    local function r1(x)
        return x ~= nil and math.floor(x * 10) / 10 or nil
    end
    log(
        bot,
        t.kind,
        t.spawn,
        {
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
            {"idle", t.idle}
        }
    )
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
            local __continue38
            repeat
                local function skip(why)
                    handled[pid][key(kind, spawn)] = true
                    gateWhy[pid] = nil
                    log(bot, kind, spawn, {{"res", "skip"}, {"why", why}})
                    return false
                end
                if not bot:IsAlive() then
                    if DotaTime() >= spawn then
                        return skip("dead")
                    end
                    gateWhy[pid] = "dead"
                    __continue38 = true
                    break
                end
                local t = tripFor(bot, kind, spawn, host)
                local leave = leaveAt(bot, t)
                if DotaTime() < leave then
                    return false
                end
                local why = blocked(bot) or (acting(bot) and "acting" or nil)
                if DotaTime() > leave + ____exports.SETTINGS.StartSlack then
                    return skip(gateWhy[pid] or why or "late")
                end
                if why ~= nil then
                    gateWhy[pid] = why
                    return false
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
            if not __continue38 then
                break
            end
        end
    end
    return false
end
function ____exports.Step(bot, host)
    return running[bot:GetPlayerID()] ~= nil and Tasks.Step(bot, host)
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
--- A teammate of `team` owns the shrine spawn (on its trip, or the job skipped it): OHA's own wisdom logic leaves the shrine.
function ____exports.ShrineTaken(team)
    do
        local i = 1
        while i <= 5 do
            do
                local __continue66
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m:GetTeam() ~= team then
                        __continue66 = true
                        break
                    end
                    local ____opt_2 = running[m:GetPlayerID()]
                    if (____opt_2 and ____opt_2.kind) == "wisdom" or ____exports.Owns(m, "wisdom") then
                        return true
                    end
                    __continue66 = true
                until true
                if not __continue66 then
                    break
                end
            end
            i = i + 1
        end
    end
    return false
end
return ____exports
