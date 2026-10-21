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
local T, there, fail, guard, ended, runs, body
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
function T()
    return LaneConfig.Settings().Timing
end
function there(bot, loc)
    return GetUnitToLocationDistance(bot, loc) <= LaneConfig.Settings().Radii.JobArrive
end
function fail(reason, message)
    return {success = false, reason = reason, message = message}
end
function guard(bot, p)
    if not LaneConfig.IsOn("Stack") then
        return "flag-off"
    end
    if not bot:IsAlive() then
        return "dead"
    end
    if DotaTime() > p.aggroAt + T().JobMaxAfterAggro then
        return "timeout"
    end
    local ok, why = CampJobs.StackAllowed(bot, p.forced)
    local ____ok_0
    if ok then
        ____ok_0 = nil
    else
        ____ok_0 = why
    end
    return ____ok_0
end
body = __TS__Generator(function(bot, p)
    local V = Tasks.Verbs()
    local u = bot
    local function walk(points, ____until)
        return V.walkPath(
            u,
            points,
            {
                tolerance = LaneConfig.Settings().Radii.JobArrive,
                timeout = math.huge,
                stuckSecs = math.huge,
                interruptIf = function() return DotaTime() >= ____until end
            }
        )
    end
    Tasks.Urgent(bot, true)
    Tasks.Label(bot, "travel")
    repeat
        do
            if not __TS__DelegatedYield(walk(
                {p.stand},
                p.aggroAt + T().JobStartLate
            )).success then
                return fail("timeout", "late")
            end
            Tasks.Label(bot, "wait")
            __TS__DelegatedYield(V.waitUntil(
                u,
                p.aggroAt,
                {
                    hold = "lane:job_wait",
                    interruptIf = function() return not there(bot, p.stand) end
                }
            ))
        end
    until there(bot, p.stand)
    Tasks.Label(bot, "aggro")
    local before = 0
    local function pick()
        local n = CampJobs.CampNeutral(bot, p.campIdx)
        if n ~= nil then
            before = CampJobs.NeutralsInBox(bot, p.campIdx)
        end
        return n
    end
    local hit = __TS__DelegatedYield(V.attackAndConfirm(
        u,
        pick,
        {
            findFor = math.max(
                0,
                p.aggroAt + T().NoCampAfter - DotaTime()
            ),
            confirmFor = T().AggroConfirm,
            searchAt = p.stand,
            hold = "lane:job_aggro",
            confirmed = function() return CampJobs.NeutralTargets(bot) end
        }
    ))
    if hit.reason == "no_target" then
        if not there(bot, p.stand) then
            return fail("timeout", "late")
        end
        Stacking.ClearStack(p.campIdx)
        return fail("no_target", "mistake:no-camp")
    end
    if not hit.success then
        return fail(hit.reason, "mistake:no-aggro")
    end
    CampJobs.NoteStackAggro(
        bot,
        p,
        before,
        DotaTime()
    )
    Tasks.Urgent(bot, false)
    Tasks.Label(bot, "exit")
    __TS__DelegatedYield(walk(p.path, p.exitUntil))
    __TS__DelegatedYield(V.waitUntil(u, p.exitUntil, {hold = "lane:stack_exit"}))
    return {success = true, reason = "ok"}
end)
function ended(bot, p, r, info)
    runs[bot:GetPlayerID()].ended = r.success and "done" or "aborted"
    if r.success then
        return
    end
    local reason = (r.reason == "preempted" or r.reason == "dead" or r.reason == "error") and r.reason or (r.message or r.reason)
    local phase = info.label or "travel"
    CampJobs.NoteJobAbort(bot, {
        kind = "stack",
        campIdx = p.campIdx,
        baseAggro = p.baseAggro,
        phase = phase,
        acted = info.steps > 0,
        divert = 0,
        aggroLanded = false
    }, reason)
end
runs = {}
--- False when the flag is off or the runner refused; camp_jobs then runs the legacy job on the same plan.
function ____exports.Start(bot, p)
    if Config.Get().Tasks.Stack ~= true then
        return false
    end
    local started = Tasks.Start(
        bot,
        {
            name = "stack",
            host = BotMode.Farm,
            tier = "CAMP_JOB",
            floor = CampJobs.DesireOf("stack"),
            preemptAfter = T().JobPreemptAfter,
            stallAfter = math.huge,
            guard = function() return guard(bot, p) end,
            onEnd = function(r, info) return ended(bot, p, r, info) end
        },
        function() return body(bot, p) end
    )
    if not started then
        return false
    end
    runs[bot:GetPlayerID()] = {plan = p}
    Stacking.Reserve(
        p.campIdx,
        bot:GetPlayerID(),
        p.exitUntil
    )
    CampJobs.NoteJobStart(bot, {kind = "stack", campIdx = p.campIdx, aggroAt = p.aggroAt, forced = p.forced}, p.data)
    return true
end
--- The bot's latest stack task: its plan, its label while it runs, and how it ended.
function ____exports.Job(bot)
    local run = runs[bot:GetPlayerID()]
    if run == nil then
        return nil
    end
    local current = Tasks.Current(bot)
    local ____run_plan_4 = run.plan
    local ____temp_3
    if (current and current.name) == "stack" then
        ____temp_3 = current.label
    else
        ____temp_3 = nil
    end
    return {plan = ____run_plan_4, label = ____temp_3, ended = run.ended}
end
--- The rotation probe: the aggro is within `seconds` while the bot travels to the camp or waits there.
function ____exports.UpcomingWithin(bot, seconds)
    local job = ____exports.Job(bot)
    if job == nil or job.ended ~= nil or job.label == "aggro" or job.label == "exit" then
        return false
    end
    return job.plan.aggroAt - DotaTime() <= seconds
end
CampJobs.SetStackTask({Start = ____exports.Start, UpcomingWithin = ____exports.UpcomingWithin})
return ____exports
