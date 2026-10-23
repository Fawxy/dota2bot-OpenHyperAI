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
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.STACK = "stack"
____exports.PULL = "pull"
local Exec = CampJobs.Exec
local STATE_OF = {
    stack = ____exports.STACK,
    full_pull = ____exports.PULL,
    half_pull = ____exports.PULL,
    stack_pull = ____exports.PULL,
    double_pull = ____exports.PULL
}
--- Above laning's 0.5 + stickiness; below the job break (0.9), so a running job is never switched for another.
local SCORE = 0.8
--- The state a job runs as, or undefined for jobs that stay on step() (contests, takes).
function ____exports.StateOf(job)
    if job.take == true then
        return nil
    end
    return STATE_OF[job.kind]
end
local function liveJob(bot, state)
    local job = CampJobs.Current(bot)
    return job ~= nil and Exec.IsLive(job) and ____exports.StateOf(job) == state and job or nil
end
local function T()
    return LaneConfig.Settings().Timing
end
local function R()
    return LaneConfig.Settings().Radii
end
local function campOf(bot, idx, stand, opts)
    local sp = Camps.SpawnerByIdx(idx)
    local approach
    if sp ~= nil then
        local o = sp.location
        local d = math.sqrt((stand.x - o.x) ^ 2 + (stand.y - o.y) ^ 2)
        local near = R().StandApproach
        if d > near + R().JobArrive then
            approach = {x = o.x + (stand.x - o.x) * near / d, y = o.y + (stand.y - o.y) * near / d, z = o.z}
        end
    end
    return {
        approach = approach ~= nil and Vector(approach.x, approach.y, approach.z or 0) or nil,
        stand = stand,
        box = sp ~= nil and ({min = sp.min, max = sp.max}) or nil,
        origin = sp ~= nil and sp.location or nil,
        margin = R().BoxMargin,
        search = R().NeutralSearch,
        confirmed = opts.confirmAny and (function() return Exec.NeutralTargets(bot) end) or nil
    }
end
--- GameTime of the aggro order (the clock GetLastAttackTime uses) from its DotaTime.
local function gameTimeOf(dotaTime)
    return GameTime() - (DotaTime() - dotaTime)
end
local function onLabel(bot, job, label)
    job.phase = label
    if label == "aggro" and job.kind == "stack" then
        job.stackBefore = Exec.NeutralsInBox(bot, job.activeCamp)
    end
end
local function landed(bot, job, info)
    job.aggroOrderedAt = gameTimeOf(info.orderedAt)
    job.aggroTarget = info.target
    local now = DotaTime()
    if job.chain ~= nil then
        job.activeCamp = job.campIdx
        job.stand = job.chain.stand
        job.aggroAt = job.chain.aggroAt
        job.chain = nil
        job.aggroOrderedAt = nil
        job.aggroTarget = nil
        return
    end
    if job.stage == 1 then
        job.actualAggro = Exec.AggroLanded(bot, job, now)
    end
    job.aggroTarget = nil
    if job.kind == "stack" then
        Exec.NoteStackAggro(bot, job, now)
    end
end
local function stackPlan(bot, job)
    return {
        camp = campOf(bot, job.campIdx, job.stand, {confirmAny = true}),
        aggroAt = job.aggroAt,
        timingError = 0,
        exitPath = job.path,
        exitUntil = job.exitUntil or job.aggroAt + T().JobMaxAfterAggro,
        arrive = R().JobArrive,
        startLate = T().JobStartLate,
        approachLead = T().StandApproachLead,
        noCampAfter = T().NoCampAfter,
        confirmFor = T().AggroConfirm,
        onAggro = function(info) return landed(bot, job, info) end
    }
end
local function pullPlan(bot, job)
    local chain = job.chain
    local small = chain ~= nil and chain.stand or job.stand
    return {
        camp = campOf(bot, job.campIdx, small, {confirmAny = chain == nil}),
        aggroAt = chain ~= nil and chain.aggroAt or job.aggroAt,
        first = chain ~= nil and ({
            camp = campOf(bot, job.activeCamp, job.stand, {confirmAny = true}),
            aggroAt = job.aggroAt
        }) or nil,
        timingError = 0,
        lead = job.path,
        watchSec = T().WatchSec,
        watchUntil = job.waveAt ~= nil and job.waveAt + LaneConfig.Settings().PullTiming.WatchAfterWave or nil,
        leadDeadline = (chain ~= nil and chain.aggroAt or job.aggroAt) + T().JobMaxAfterAggro,
        arrive = R().JobArrive,
        startLate = T().JobStartLate,
        approachLead = T().StandApproachLead,
        noCampAfter = T().NoCampAfter,
        confirmFor = T().AggroConfirm,
        onAggro = function(info) return landed(bot, job, info) end
    }
end
--- Steps `g` once per frame, except on frames where `host()` acted for the job (a tango or clarity).
local withHost = __TS__Generator(function(g, host)
    while true do
        if not host() then
            local s = g:next()
            if s.done then
                return s.value or ({success = true, reason = "ok"})
            end
        end
        coroutine.yield()
    end
end)
local function perFrame(bot, job)
    local now = DotaTime()
    if job.phase == "travel" or job.phase == "wait" then
        Exec.Telegraph(bot, job, now)
        if job.kind ~= "stack" and Exec.Supply(bot, job, now) then
            return true
        end
    end
    if job.phase == "watch" then
        Exec.Sample(bot, job, now)
    end
    return false
end
local started = {}
--- Gives the job back to step(): its path index set to the first waypoint ahead of the bot (the SDK walks paths itself
-- and never advances `job.waypoint`, so step() would otherwise walk back to the first one).
local function handBack(bot, job)
    job.sdk = false
    local path = job.path
    if #path == 0 or job.phase ~= "lead" and job.phase ~= "exit" and job.phase ~= "watch" then
        return
    end
    local nearest = 0
    local best = math.huge
    do
        local i = 0
        while i < #path do
            local d = GetUnitToLocationDistance(bot, path[i + 1])
            if d < best then
                best = d
                nearest = i
            end
            i = i + 1
        end
    end
    job.waypoint = best <= R().JobArrive and nearest + 1 or nearest
end
local body = __TS__Generator(function(bot, state, ctx)
    local job = liveJob(bot, state)
    if job == nil then
        return ctx.fail("no_target", "no-job")
    end
    local pid = bot:GetPlayerID()
    if started[pid] == job or job.phase ~= "travel" and job.phase ~= "wait" or job.aggroOrderedAt ~= nil or job.actualAggro ~= nil then
        handBack(bot, job)
        return ctx.fail("interrupted", "legacy-resume")
    end
    started[pid] = job
    local V = Tasks.Verbs()
    local u = bot
    local hooks = {
        label = function(l)
            ctx.label(l)
            onLabel(bot, job, l)
        end,
        urgent = ctx.urgent
    }
    local run = job.kind == "stack" and V.stack(
        u,
        stackPlan(bot, job),
        hooks
    ) or V.pull(
        u,
        pullPlan(bot, job),
        hooks
    )
    return __TS__DelegatedYield(withHost(
        run,
        function() return perFrame(bot, job) end
    ))
end)
--- The legacy abort reason (and keepStack) for a failed body, as step() would have aborted.
local function abortOf(r)
    if r.message == "late" then
        return "late", true
    end
    if r.message == "mistake:no-camp" or r.message == "mistake:no-aggro" then
        return r.message, false
    end
    if r.message == "lead" then
        return "lead-" .. r.reason, false
    end
    return r.reason, false
end
local function ended(bot, state, r, info)
    local job = CampJobs.Current(bot)
    if job == nil or ____exports.StateOf(job) ~= state then
        return
    end
    Telemetry.Event(
        "job_exec",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "kind",
                Exec.LogKind(job.kind)
            },
            {"camp", job.campIdx},
            {"result", r.success and "ok" or "fail"},
            {"reason", r.reason},
            {"msg", r.message},
            {"label", info.label},
            {"sdk", job.sdkFrames or 0},
            {"legacy", job.legacyFrames or 0}
        }
    )
    if not Exec.IsLive(job) then
        return
    end
    if r.success then
        if job.kind == "stack" then
            Exec.EndStack(bot, job)
        else
            Exec.Close(bot, job)
        end
        return
    end
    if r.reason == "preempted" or r.reason == "cancelled" or r.reason == "error" or r.reason == "interrupted" then
        handBack(bot, job)
        return
    end
    local reason, keepStack = abortOf(r)
    if reason == "mistake:no-camp" then
        Stacking.ClearStack(job.activeCamp)
    end
    Exec.Abort(bot, job, reason, keepStack)
end
--- `shadow` scores bots whose position is not owned (states/shadow.ts, slice 2: any live camp job of the kind,
-- contests included, with its linger), so shadow agreement stays measured the same way.
function ____exports.Spec(bot, state, owned, shadow)
    return {
        name = state,
        kind = "job",
        host = BotMode.Farm,
        tier = "CAMP_JOB",
        floor = T().JobDesire,
        preemptAfter = T().JobPreemptAfter,
        score = function()
            local job = liveJob(bot, state)
            if job ~= nil and job.sdk == true then
                return SCORE
            end
            if owned(bot, state) then
                return nil
            end
            if shadow ~= nil then
                return shadow(bot)
            end
            return job ~= nil and SCORE or nil
        end,
        guard = function()
            local job = liveJob(bot, state)
            if job == nil then
                return "job-ended"
            end
            local ____temp_0
            if job.sdk == true then
                ____temp_0 = nil
            else
                ____temp_0 = "legacy"
            end
            return ____temp_0
        end,
        onEnd = function(r, info) return ended(bot, state, r, info) end,
        body = function(ctx) return body(bot, state, ctx) end
    }
end
function ____exports.ResetCache()
    for k in pairs(started) do
        started[k] = nil
    end
end
return ____exports
