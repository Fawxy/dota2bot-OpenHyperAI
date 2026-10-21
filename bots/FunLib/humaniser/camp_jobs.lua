--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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

local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ClassExtends(target, base)
    target.____super = base
    local staticMetatable = setmetatable({__index = base}, base)
    setmetatable(target, staticMetatable)
    local baseMetatable = getmetatable(base)
    if baseMetatable then
        if type(baseMetatable.__index) == "function" then
            staticMetatable.__index = baseMetatable.__index
        end
        if type(baseMetatable.__newindex) == "function" then
            staticMetatable.__newindex = baseMetatable.__newindex
        end
    end
    setmetatable(target.prototype, base.prototype)
    if type(base.prototype.__index) == "function" then
        target.prototype.__index = base.prototype.__index
    end
    if type(base.prototype.__newindex) == "function" then
        target.prototype.__newindex = base.prototype.__newindex
    end
    if type(base.prototype.__tostring) == "function" then
        target.prototype.__tostring = base.prototype.__tostring
    end
end

local Error, RangeError, ReferenceError, SyntaxError, TypeError, URIError
do
    local function getErrorStack(self, constructor)
        if debug == nil then
            return nil
        end
        local level = 1
        while true do
            local info = debug.getinfo(level, "f")
            level = level + 1
            if not info then
                level = 1
                break
            elseif info.func == constructor then
                break
            end
        end
        if __TS__StringIncludes(_VERSION, "Lua 5.0") then
            return debug.traceback(("[Level " .. tostring(level)) .. "]")
        else
            return debug.traceback(nil, level)
        end
    end
    local function wrapErrorToString(self, getDescription)
        return function(self)
            local description = getDescription(self)
            local caller = debug.getinfo(3, "f")
            local isClassicLua = __TS__StringIncludes(_VERSION, "Lua 5.0") or _VERSION == "Lua 5.1"
            if isClassicLua or caller and caller.func ~= error then
                return description
            else
                return (description .. "\n") .. tostring(self.stack)
            end
        end
    end
    local function initErrorClass(self, Type, name)
        Type.name = name
        return setmetatable(
            Type,
            {__call = function(____, _self, message) return __TS__New(Type, message) end}
        )
    end
    local ____initErrorClass_1 = initErrorClass
    local ____class_0 = __TS__Class()
    ____class_0.name = ""
    function ____class_0.prototype.____constructor(self, message)
        if message == nil then
            message = ""
        end
        self.message = message
        self.name = "Error"
        self.stack = getErrorStack(nil, self.constructor.new)
        local metatable = getmetatable(self)
        if metatable and not metatable.__errorToStringPatched then
            metatable.__errorToStringPatched = true
            metatable.__tostring = wrapErrorToString(nil, metatable.__tostring)
        end
    end
    function ____class_0.prototype.__tostring(self)
        return self.message ~= "" and (self.name .. ": ") .. self.message or self.name
    end
    Error = ____initErrorClass_1(nil, ____class_0, "Error")
    local function createErrorClass(self, name)
        local ____initErrorClass_3 = initErrorClass
        local ____class_2 = __TS__Class()
        ____class_2.name = ____class_2.name
        __TS__ClassExtends(____class_2, Error)
        function ____class_2.prototype.____constructor(self, ...)
            ____class_2.____super.prototype.____constructor(self, ...)
            self.name = name
        end
        return ____initErrorClass_3(nil, ____class_2, name)
    end
    RangeError = createErrorClass(nil, "RangeError")
    ReferenceError = createErrorClass(nil, "ReferenceError")
    SyntaxError = createErrorClass(nil, "SyntaxError")
    TypeError = createErrorClass(nil, "TypeError")
    URIError = createErrorClass(nil, "URIError")
end

local function __TS__ObjectGetOwnPropertyDescriptors(object)
    local metatable = getmetatable(object)
    if not metatable then
        return {}
    end
    return rawget(metatable, "_descriptors") or ({})
end

local function __TS__Delete(target, key)
    local descriptors = __TS__ObjectGetOwnPropertyDescriptors(target)
    local descriptor = descriptors[key]
    if descriptor then
        if not descriptor.configurable then
            error(
                __TS__New(
                    TypeError,
                    ((("Cannot delete property " .. tostring(key)) .. " of ") .. tostring(target)) .. "."
                ),
                0
            )
        end
        descriptors[key] = nil
        return true
    end
    target[key] = nil
    return true
end
-- End of Lua Library inline imports
local ____exports = {}
local settings, neutralsInBox, boxInSight, settleStack, pendingStacks
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LanePlanner = require(GetScriptDirectory().."/FunLib/humaniser/lane_planner")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
function settings()
    return LaneConfig.Settings()
end
function neutralsInBox(bot, campIdx)
    local margin = settings().Radii.BoxMargin
    local n = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        settings().Radii.StackCountScan,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() and Camps.InBox(
            campIdx,
            c:GetLocation(),
            margin
        ) then
            n = n + 1
        end
    end
    return n
end
function boxInSight(bot, campIdx)
    local spawner = Camps.SpawnerByIdx(campIdx)
    return spawner ~= nil and bot:IsAlive() and GetUnitToLocationDistance(
        bot,
        Camps.BoxCenter(spawner)
    ) <= settings().Radii.StackSight
end
function ____exports.StackGrade(aggroSec)
    local t = settings().Timing
    if aggroSec < t.StackEarlyBefore then
        return "mistake:early"
    end
    if aggroSec > t.StackLateAfter then
        return "mistake:late"
    end
    return "ok"
end
function settleStack(bot, now)
    local p = pendingStacks[bot:GetPlayerID()]
    if p == nil or now < p.at then
        return
    end
    if boxInSight(bot, p.campIdx) then
        p.peak = math.max(
            p.peak or 0,
            neutralsInBox(bot, p.campIdx)
        )
    end
    if now < p["until"] and (p.peak == nil or p.peak <= p.before) then
        return
    end
    __TS__Delete(
        pendingStacks,
        bot:GetPlayerID()
    )
    local t = settings().Timing
    local after = p.peak
    local assumed = after == nil and p.aggro >= t.StackAssumedFrom and p.aggro <= t.StackAssumedTo
    Stacking.NoteStackOutcome(p.campIdx, p.minute, after, assumed)
    local grade = after == nil and "unknown" or ____exports.StackGrade(p.aggro)
    HDebug.Log(
        "lane",
        string.format(
            "stack pid=%d camp=%d type=%s aggro=%.1f planned=%.1f before=%d after=%s grade=%s",
            bot:GetPlayerID(),
            p.campIdx,
            p.type,
            p.aggro,
            p.planned,
            p.before,
            after == nil and "?" or tostring(after),
            grade
        )
    )
    if assumed then
        HDebug.Log(
            "lane",
            string.format(
                "stack-assumed pid=%d camp=%d aggro=%.1f",
                bot:GetPlayerID(),
                p.campIdx,
                p.aggro
            )
        )
    end
    if grade == "ok" and after ~= nil and after > p.before then
        Stacking.Telegraph(bot, p.type)
    end
end
local PULL_KINDS = {full_pull = true, half_pull = true, stack_pull = true, double_pull = true}
local PULL_TECHS = {full_pull = "full_pull", half_pull = "half_pull", stack_pull = "stack_pull"}
local LOG_KIND = {
    full_pull = "full",
    half_pull = "half",
    stack_pull = "stackpull",
    double_pull = "double",
    stack = "stack",
    contest = "contest"
}
local FLAG_OF = {
    full_pull = "FullPull",
    half_pull = "HalfPull",
    stack_pull = "StackPull",
    double_pull = "FullPull",
    stack = "Stack",
    contest = "CounterPlay"
}
local JOB_FLAGS = {"FullPull", "HalfPull", "StackPull"}
local jobs = {}
local doneCycle = {}
pendingStacks = {}
function ____exports.ResetCache()
    jobs = {}
    doneCycle = {}
    pendingStacks = {}
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function cycleOf(time)
    return math.floor(time / settings().Timing.WaveCycle)
end
local function commitTech(kind)
    if kind == "double_pull" then
        return "full_pull"
    end
    if kind == "contest" then
        return "contest"
    end
    return kind
end
function ____exports.AggroSecondsFor(kind, data)
    if kind == "stack" or kind == "contest" then
        return data.stack ~= nil and ({data.stack.aggroSec}) or ({})
    end
    local pull = data.pull
    if pull == nil then
        return {}
    end
    if kind ~= "half_pull" then
        return pull.aggroSec
    end
    if pull.halfAggroSec ~= nil then
        return pull.halfAggroSec
    end
    local later = settings().Timing.HalfPullLater
    return __TS__ArrayMap(
        pull.aggroSec,
        function(____, s) return s + later end
    )
end
function ____exports.NextAggroTime(dotaTime, seconds, period)
    local base = math.floor(dotaTime / period) * period
    local best = math.huge
    for ____, s in ipairs(seconds) do
        for ____, t in ipairs({base + s, base + period + s}) do
            if t >= dotaTime and t < best then
                best = t
            end
        end
    end
    return best
end
function ____exports.TravelTime(dist, speed)
    return dist / math.max(speed, 1)
end
function ____exports.WindowOpen(now, aggroAt, travel)
    local t = settings().Timing
    return now >= aggroAt - travel - t.JobStartSlack and now <= aggroAt + t.JobStartLate
end
local function isNeutral(unit)
    return unit ~= nil and unit ~= nil and unit:GetTeam() == Team.Neutral
end
function ____exports.MeasureDivert(allyCreeps, waveSize)
    local n = 0
    for ____, c in ipairs(allyCreeps) do
        if isNeutral(c:GetAttackTarget()) then
            n = n + 1
        end
    end
    return math.min(
        1,
        n / math.max(waveSize, 1)
    )
end
function ____exports.Grade(kind, divert)
    local t = settings().Thresholds
    if kind == "half_pull" then
        if divert > t.HalfPullMax then
            return "mistake:half->full"
        end
        if divert < t.HalfPullMin then
            return "mistake:weak-pull"
        end
        return "ok"
    end
    if divert > t.FullPullMin then
        return "ok"
    end
    return divert > 0 and "mistake:weak-pull" or "mistake:no-divert"
end
local function noisy(v, noise)
    local r = RandomVector(noise)
    return Vector(v.x + r.x, v.y + r.y, v.z)
end
local function standFor(spawner, firstWaypoint)
    return Camps.BoxEdgePoint(
        spawner,
        firstWaypoint,
        settings().Radii.StandOffset
    ) or Camps.BoxCenter(spawner)
end
--- The camp's lead waypoints with its own meet point replaced by `meet`.
local function leadPath(pull, meet)
    local result = {}
    local n = #pull.path
    do
        local i = 0
        while i < n do
            do
                local __continue36
                repeat
                    local p = pull.path[i + 1]
                    if i == n - 1 and dist2D(p, pull.meetPoint) < 1 then
                        __continue36 = true
                        break
                    end
                    result[#result + 1] = p
                    __continue36 = true
                until true
                if not __continue36 then
                    break
                end
            end
            i = i + 1
        end
    end
    result[#result + 1] = meet
    return result
end
local function travelTo(bot, loc)
    return ____exports.TravelTime(
        GetUnitToLocationDistance(bot, loc),
        bot:GetCurrentMovementSpeed()
    )
end
local function dataLabel(data)
    return data.unverified == true and "unverified" or data.source
end
local function register(bot, job, data)
    jobs[bot:GetPlayerID()] = job
    LanePlanner.Commit(
        bot,
        commitTech(job.kind)
    )
    HDebug.Log(
        "lane",
        string.format(
            "job-start pid=%d kind=%s camp=%d key=%s data=%s aggroAt=%.1f forced=%s",
            bot:GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            data.key or "-",
            dataLabel(data),
            job.aggroAt,
            tostring(job.forced == true)
        )
    )
end
local function startStack(bot, req)
    local data = Camps.ByIdx(req.campIdx)
    local spawner = Camps.SpawnerByIdx(req.campIdx)
    if data == nil or data.stack == nil or spawner == nil then
        return false
    end
    local cfg = settings()
    local skill = LaneConfig.SkillOf(bot)
    local now = DotaTime()
    local period = cfg.Timing.PullPeriod
    local aggroSec = data.stack.aggroSec
    local jitter = LaneConfig.Jitter(skill)
    local noise = LaneConfig.Curve("PathNoise", skill)
    local stand = noisy(
        Stacking.StandPoint(spawner, data),
        noise
    )
    local path = __TS__ArrayMap(
        data.stack.exitPath,
        function(____, p) return noisy(p, noise) end
    )
    local base = ____exports.NextAggroTime(now, {aggroSec}, period)
    if req.forced == true and base < now + travelTo(bot, stand) then
        base = ____exports.NextAggroTime(
            now + travelTo(bot, stand),
            {aggroSec},
            period
        )
    end
    local minuteStart = base - aggroSec
    register(
        bot,
        __TS__ObjectAssign(
            {},
            req,
            {
                minute = math.floor(base / period),
                phase = "travel",
                aggroAt = base + jitter,
                plannedSec = aggroSec,
                path = path,
                startedAt = now,
                peakDivert = 0,
                waveSize = 0,
                activeCamp = req.campIdx,
                stand = stand,
                waypoint = 0,
                stage = 1,
                secondTried = false,
                telegraphed = false,
                baseAggro = base,
                exitUntil = minuteStart + period + cfg.Timing.StackExitUntil
            }
        ),
        data
    )
    return true
end
--- Started only by counterplay: walk to the enemy pull camp and hit the puller while it stays visible.
local function startContest(bot, req)
    local data = Camps.ByIdx(req.campIdx)
    local spawner = Camps.SpawnerByIdx(req.campIdx)
    if data == nil or spawner == nil then
        return false
    end
    local now = DotaTime()
    local center = Camps.BoxCenter(spawner)
    register(
        bot,
        __TS__ObjectAssign({}, req, {
            phase = "travel",
            aggroAt = now,
            plannedSec = 0,
            path = {center},
            startedAt = now,
            peakDivert = 0,
            waveSize = 0,
            activeCamp = req.campIdx,
            stand = center,
            waypoint = 0,
            stage = 1,
            secondTried = false,
            telegraphed = true,
            baseAggro = now
        }),
        data
    )
    return true
end
function ____exports.Start(bot, req)
    if req.kind == "stack" then
        return startStack(bot, req)
    end
    if req.kind == "contest" then
        return startContest(bot, req)
    end
    if PULL_KINDS[req.kind] ~= true then
        return false
    end
    local data = Camps.ByIdx(req.campIdx)
    local spawner = Camps.SpawnerByIdx(req.campIdx)
    if data == nil or data.pull == nil or spawner == nil then
        return false
    end
    local seconds = ____exports.AggroSecondsFor(req.kind, data)
    if #seconds == 0 then
        return false
    end
    local cfg = settings()
    local skill = LaneConfig.SkillOf(bot)
    local now = DotaTime()
    local period = cfg.Timing.PullPeriod
    local jitter = LaneConfig.Jitter(skill)
    local meet = req.kind == "half_pull" and (data.pull.halfMeetPoint or data.pull.meetPoint) or data.pull.meetPoint
    local noise = LaneConfig.Curve("PathNoise", skill)
    local exact = leadPath(data.pull, meet)
    local stand = noisy(
        standFor(spawner, exact[1]),
        noise
    )
    local path = __TS__ArrayMap(
        exact,
        function(____, p) return noisy(p, noise) end
    )
    local base = ____exports.NextAggroTime(now - cfg.Timing.JobStartLate, seconds, period)
    if req.forced == true and base < now + travelTo(bot, stand) then
        base = ____exports.NextAggroTime(
            now + travelTo(bot, stand),
            seconds,
            period
        )
    end
    local job = __TS__ObjectAssign({}, req, {
        phase = "travel",
        aggroAt = base + jitter,
        plannedSec = base % period,
        path = path,
        meet = meet,
        startedAt = now,
        peakDivert = 0,
        waveSize = 0,
        activeCamp = req.campIdx,
        stand = stand,
        waypoint = 0,
        stage = 1,
        secondTried = false,
        telegraphed = false,
        baseAggro = base
    })
    register(bot, job, data)
    return true
end
function ____exports.Current(bot)
    return jobs[bot:GetPlayerID()]
end
local function isLive(job)
    return job ~= nil and job.phase ~= "done" and job.phase ~= "return"
end
--- Cheap: a config read, then a table lookup; false before any engine call when the lane system is off.
function ____exports.Active(bot)
    if not LaneConfig.IsActive() then
        return false
    end
    return isLive(jobs[bot:GetPlayerID()])
end
function ____exports.UpcomingWithin(bot, seconds)
    local job = jobs[bot:GetPlayerID()]
    if job == nil or job.phase ~= "travel" and job.phase ~= "wait" then
        return false
    end
    return job.aggroAt - DotaTime() <= seconds
end
local function logJob(bot, job, grade)
    local data = Camps.ByIdx(job.campIdx)
    local aggro = job.plannedSec + ((job.actualAggro or job.aggroAt) - job.baseAggro)
    HDebug.Log(
        "lane",
        string.format(
            "job pid=%d kind=%s camp=%d key=%s aggro=%.1f planned=%.1f divert=%.2f grade=%s",
            bot:GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            data and data.key or "-",
            aggro,
            job.plannedSec,
            job.peakDivert,
            grade
        )
    )
end
--- Completed pull: the graded `job` line that parse_condebug.js counts as an attempt.
local function close(bot, job, phase, grade)
    job.phase = phase
    doneCycle[bot:GetPlayerID()] = cycleOf(DotaTime())
    if job.kind == "stack_pull" then
        Stacking.ClearStack(job.campIdx)
    end
    logJob(bot, job, grade)
end
--- Aborts go on the `job-abort` line, which the console parser does not read, so safety aborts never count
-- against a camp's timing. A double pull aborted in its second stage still grades the first pull.
local function abort(bot, job, reason)
    if job.stage == 2 then
        close(
            bot,
            job,
            "return",
            ____exports.Grade(job.kind, job.peakDivert)
        )
        return
    end
    job.phase = "return"
    if job.kind ~= "stack" then
        doneCycle[bot:GetPlayerID()] = cycleOf(DotaTime())
    end
    if job.kind == "stack_pull" and job.actualAggro ~= nil then
        Stacking.ClearStack(job.campIdx)
    end
    local token = string.gsub(reason, "%s+", "-")
    local ____HDebug_Log_6 = HDebug.Log
    local ____string_format_5 = string.format
    local ____array_4 = __TS__SparseArrayNew(
        "job-abort pid=%d kind=%s camp=%d key=%s reason=%s divert=%.2f",
        bot:GetPlayerID(),
        LOG_KIND[job.kind],
        job.campIdx
    )
    local ____opt_2 = Camps.ByIdx(job.campIdx)
    __TS__SparseArrayPush(____array_4, ____opt_2 and ____opt_2.key or "-", token, job.peakDivert)
    ____HDebug_Log_6(
        "lane",
        ____string_format_5(__TS__SparseArraySpread(____array_4))
    )
end
--- A contest is no pull attempt, so it ends on its own line, which the console parser does not read.
local function endContest(bot, job, reason)
    job.phase = "return"
    doneCycle[bot:GetPlayerID()] = cycleOf(DotaTime())
    HDebug.Log(
        "lane",
        string.format(
            "contest-end pid=%d camp=%d reason=%s",
            bot:GetPlayerID(),
            job.campIdx,
            reason
        )
    )
end
local function jobAllowed(bot, s, forced)
    local enemies = LaneState.Enemies(bot, s.lane)
    local ok, why = LaneRoles.MayRunCampJob(bot, s, enemies)
    if ok or not forced or why ~= "not-owner" then
        return ok, why
    end
    if not LaneConfig.InLaningPhase() then
        return false, "not-laning"
    end
    if LaneRoles.RoleIn(bot, s) == "solo" then
        if not LaneRoles.LaneStable(bot, enemies) then
            return false, "solo: unstable"
        end
    elseif not LaneRoles.PartnerSafe(bot, s, enemies) then
        return false, "partner unsafe"
    end
    return true, "ok"
end
--- Stacks need no camp-job ownership (any eligible support may stack, after laning too); forced ones only safety.
local function stackAllowed(bot, job)
    local s = LaneState.ForBot(bot)
    local laning = LaneConfig.InLaningPhase()
    if laning and s == nil then
        return false, "no-lane"
    end
    local enemies = LaneState.Enemies(
        bot,
        s and s.lane or bot:GetAssignedLane()
    )
    local ok, why = unpack(job.forced == true and ({Stacking.Safe(bot, s, enemies)}) or ({Stacking.Eligible(bot, s, enemies)}))
    if not ok then
        return false, why
    end
    if laning and s ~= nil and LanePlan.View(bot, s).handsOff then
        return false, "handsoff"
    end
    return true, "ok"
end
--- Abort checks for a running job; true when it may continue.
local function keepGoing(bot, job)
    if not LaneConfig.IsOn(FLAG_OF[job.kind]) then
        abort(bot, job, "flag-off")
        return false
    end
    if not bot:IsAlive() then
        abort(bot, job, "dead")
        return false
    end
    local now = DotaTime()
    if job.kind == "contest" and now - job.startedAt >= settings().Timing.ContestMax then
        endContest(bot, job, "timeout")
        return false
    end
    if now > job.aggroAt + settings().Timing.JobMaxAfterAggro then
        if job.phase == "watch" then
            close(
                bot,
                job,
                "return",
                ____exports.Grade(job.kind, job.peakDivert)
            )
        else
            abort(bot, job, "timeout")
        end
        return false
    end
    if job.kind == "stack" then
        local ok, why = stackAllowed(bot, job)
        if not ok then
            abort(bot, job, why)
        end
        return ok
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        abort(bot, job, "no-lane")
        return false
    end
    local ok, why = jobAllowed(bot, s, job.forced == true)
    if not ok then
        abort(bot, job, why)
        return false
    end
    if LanePlan.View(bot, s).handsOff then
        abort(bot, job, "handsoff")
        return false
    end
    return true
end
local function desireOf(kind)
    local t = settings().Timing
    return kind == "contest" and t.ContestDesire or t.JobDesire
end
local function anyJobFlag()
    for ____, flag in ipairs(JOB_FLAGS) do
        if LaneConfig.IsOn(flag) then
            return true
        end
    end
    return false
end
local function pullCampFor(tech, camps)
    if tech == "stack_pull" then
        for ____, c in ipairs(camps) do
            if LaneHooks.IsStacked(c.campIdx) then
                return c
            end
        end
    end
    return camps[1]
end
--- Earliest pull aggro in the start window for the camp's full or half seconds, before asking the planner.
local function windowFor(bot, data, kind, now)
    local spawner = Camps.SpawnerByIdx(data.campIdx)
    if spawner == nil or data.pull == nil then
        return false
    end
    local travel = travelTo(
        bot,
        standFor(
            spawner,
            leadPath(data.pull, data.pull.meetPoint)[1]
        )
    )
    if travel > settings().Timing.MaxTravel then
        return false
    end
    local base = ____exports.NextAggroTime(
        now - settings().Timing.JobStartLate,
        ____exports.AggroSecondsFor(kind, data),
        settings().Timing.PullPeriod
    )
    return ____exports.WindowOpen(now, base, travel)
end
local function schedule(bot)
    local now = DotaTime()
    local pid = bot:GetPlayerID()
    if doneCycle[pid] == cycleOf(now) or not LaneConfig.InLaningPhase() then
        return false
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false
    end
    local camps = Camps.PullCampsFor(s.team, s.lane)
    if #camps == 0 then
        return false
    end
    if not windowFor(bot, camps[1], "full_pull", now) and not windowFor(bot, camps[1], "half_pull", now) then
        local any = false
        for ____, c in ipairs(camps) do
            if LaneHooks.IsStacked(c.campIdx) and windowFor(bot, c, "stack_pull", now) then
                any = true
            end
        end
        if not any then
            return false
        end
    end
    local kind = PULL_TECHS[LanePlanner.Plan(bot, s).tech]
    if kind == nil then
        return false
    end
    local camp = pullCampFor(kind, camps)
    if not windowFor(bot, camp, kind, now) then
        return false
    end
    local req = {kind = kind, campIdx = camp.campIdx}
    if kind == "full_pull" and #camps > 1 and LaneConfig.Knows(
        "stack_pull",
        LaneConfig.SkillOf(bot)
    ) then
        req.kind = "double_pull"
        req.secondCampIdx = camps[2].campIdx
    end
    return ____exports.Start(bot, req)
end
--- Earliest second of the minute at which any camp's stack window can open, so most frames skip the stack roll.
local function earliestStackStart()
    local t = settings().Timing
    local earliest = t.StackMoveFrom
    for ____, data in ipairs(Camps.Resolve()) do
        if data.stack ~= nil then
            earliest = math.min(earliest, data.stack.aggroSec - t.MaxTravel - t.JobStartLate)
        end
    end
    return earliest
end
local function scheduleStack(bot, now)
    local t = settings().Timing
    local minute = math.floor(now / t.PullPeriod)
    local sec = now - minute * t.PullPeriod
    if sec < earliestStackStart() then
        return false
    end
    if LanePlanner.Committed(bot) ~= nil then
        return false
    end
    local data = Stacking.WantsStack(bot, minute)
    local ____temp_9
    if data ~= nil then
        ____temp_9 = Camps.SpawnerByIdx(data.campIdx)
    else
        ____temp_9 = nil
    end
    local spawner = ____temp_9
    if data == nil or data.stack == nil or spawner == nil then
        return false
    end
    local travel = travelTo(
        bot,
        Stacking.StandPoint(spawner, data)
    )
    local from = math.min(t.StackMoveFrom, data.stack.aggroSec - travel - t.JobStartLate)
    if sec < from or sec > data.stack.aggroSec then
        return false
    end
    return ____exports.Start(bot, {kind = "stack", campIdx = data.campIdx, minute = minute})
end
function ____exports.Desire(bot)
    if not LaneConfig.IsActive() then
        return 0
    end
    local now = DotaTime()
    settleStack(bot, now)
    local job = jobs[bot:GetPlayerID()]
    if isLive(job) then
        if job.kind == "stack" and job.phase == "exit" and now >= (job.exitUntil or now) then
            job.phase = "done"
            return 0
        end
        if not keepGoing(bot, job) then
            return 0
        end
        if job.kind ~= "stack" and LanePlanner.Committed(bot) == nil then
            LanePlanner.Commit(
                bot,
                commitTech(job.kind)
            )
        end
        return desireOf(job.kind)
    end
    if not bot:IsAlive() then
        return 0
    end
    local started = anyJobFlag() and schedule(bot)
    if not started and LaneConfig.IsOn("Stack") then
        started = scheduleStack(bot, now)
    end
    return started and desireOf(jobs[bot:GetPlayerID()].kind) or 0
end
local function overlay(bot, job)
    HDebug.Text(
        bot,
        "lane_job",
        string.format(
            "job=%s@%.1f %s out=%.2f",
            job.kind,
            job.plannedSec,
            job.phase,
            job.peakDivert
        )
    )
end
local function moveTo(bot, loc)
    bot:Action_MoveToLocation(loc)
    return true
end
local function arrived(bot, loc)
    return GetUnitToLocationDistance(bot, loc) <= settings().Radii.JobArrive
end
local function telegraph(bot, job, now)
    if job.kind == "stack" then
        return
    end
    if job.telegraphed or job.stage ~= 1 or now < job.aggroAt - settings().Timing.PullTelegraphLead then
        return
    end
    job.telegraphed = true
    if not LaneConfig.IsOn("Telegraph") or not Difficulty.IsAllyOfHuman(bot) then
        return
    end
    Orders.Say(
        bot,
        job.kind == "half_pull" and "say_lane_half_pull" or "say_lane_pulling_in_5",
        settings().Timing.PullTelegraphCooldown
    )
end
local function campNeutral(bot, job)
    local best
    local bestDist = math.huge
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(
        settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        do
            local __continue141
            repeat
                if n == nil or n == nil or not n:IsAlive() or not n:CanBeSeen() then
                    __continue141 = true
                    break
                end
                if not Camps.InBox(
                    job.activeCamp,
                    n:GetLocation()
                ) then
                    __continue141 = true
                    break
                end
                local d = GetUnitToLocationDistance(
                    bot,
                    n:GetLocation()
                )
                if d < bestDist then
                    best = n
                    bestDist = d
                end
                __continue141 = true
            until true
            if not __continue141 then
                break
            end
        end
    end
    return best
end
local function aggroConfirmed(bot, job)
    if job.aggroOrderedAt ~= nil and bot:GetLastAttackTime() >= job.aggroOrderedAt then
        return true
    end
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(
        settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        if n ~= nil and n ~= nil and n:IsAlive() and n:CanBeSeen() and n:GetAttackTarget() == bot then
            return true
        end
    end
    return false
end
--- The aggro landed: the attempt counts from here, whether or not the walk-off completes.
local function noteStackAggro(bot, job, now)
    local data = Camps.ByIdx(job.campIdx)
    local before = job.stackBefore or 0
    local minute = job.minute or math.floor(job.baseAggro / settings().Timing.PullPeriod)
    Stacking.NoteStackAttempt(job.campIdx, minute, before)
    local minuteEnd = (job.exitUntil or now) - settings().Timing.StackExitUntil
    pendingStacks[bot:GetPlayerID()] = {
        campIdx = job.campIdx,
        minute = minute,
        at = minuteEnd + settings().Timing.StackOutcomeAt,
        ["until"] = minuteEnd + settings().Timing.StackOutcomeUntil,
        before = before,
        aggro = job.plannedSec + (now - job.baseAggro),
        planned = job.plannedSec,
        type = data and data.type or "medium"
    }
end
local function laneCreepsNear(bot, center, radius)
    local result = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(
        settings().Radii.LaneCreepScan,
        false
    ) or ({})) do
        do
            local __continue167
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue167 = true
                    break
                end
                if dist2D(
                    c:GetLocation(),
                    center
                ) <= radius then
                    result[#result + 1] = c
                end
                __continue167 = true
            until true
            if not __continue167 then
                break
            end
        end
    end
    return result
end
local function sample(bot, job, now)
    local cfg = settings()
    if job.sampledAt ~= nil and now - job.sampledAt < cfg.Timing.WatchEvery then
        return
    end
    job.sampledAt = now
    local meet = job.meet or bot:GetLocation()
    local watched = laneCreepsNear(bot, meet, cfg.Radii.MeetWatch)
    if job.waveSize == 0 then
        if ____exports.MeasureDivert(watched, 1) == 0 then
            return
        end
        job.waveSize = math.max(
            1,
            #laneCreepsNear(bot, meet, cfg.Radii.WaveSize)
        )
    end
    job.peakDivert = math.max(
        job.peakDivert,
        ____exports.MeasureDivert(watched, job.waveSize)
    )
end
--- Double pull: once the first camp has engaged, lead the second camp into the same wave if it pulls soon enough.
local function trySecondCamp(bot, job, now)
    if job.kind ~= "double_pull" or job.stage ~= 1 or job.secondTried or job.peakDivert <= 0 or job.secondCampIdx == nil then
        return false
    end
    job.secondTried = true
    local data = Camps.ByIdx(job.secondCampIdx)
    local spawner = Camps.SpawnerByIdx(job.secondCampIdx)
    if data == nil or data.pull == nil or spawner == nil or job.meet == nil then
        return false
    end
    local cfg = settings()
    local base = ____exports.NextAggroTime(
        now,
        ____exports.AggroSecondsFor("full_pull", data),
        cfg.Timing.PullPeriod
    )
    if base - now > cfg.Timing.DoublePullReach then
        return false
    end
    local skill = LaneConfig.SkillOf(bot)
    local jitter = LaneConfig.Jitter(skill)
    local noise = LaneConfig.Curve("PathNoise", skill)
    local exact = leadPath(data.pull, job.meet)
    job.stand = noisy(
        standFor(spawner, exact[1]),
        noise
    )
    job.path = __TS__ArrayMap(
        exact,
        function(____, p) return noisy(p, noise) end
    )
    job.aggroAt = base + jitter
    job.activeCamp = job.secondCampIdx
    job.stage = 2
    job.waypoint = 0
    job.watchFrom = nil
    job.phase = "travel"
    HDebug.Log(
        "lane",
        (((("job-second pid=" .. tostring(bot:GetPlayerID())) .. " camp=") .. tostring(job.secondCampIdx)) .. " aggroAt=") .. string.format("%.1f", job.aggroAt)
    )
    return true
end
--- The puller while it stays near the camp, else any visible enemy at the camp; never a chase across the map.
local function contestTarget(bot, job)
    local center = job.stand
    local radii = settings().Radii
    local best
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        do
            local __continue181
            repeat
                if not e.visible or e.unit == nil then
                    __continue181 = true
                    break
                end
                local d = dist2D(e.location, center)
                if e.pid == job.targetPid and d <= radii.ContestReach then
                    return e.unit
                end
                if best == nil and d <= radii.EnemyNearCamp then
                    best = e.unit
                end
                __continue181 = true
            until true
            if not __continue181 then
                break
            end
        end
    end
    return best
end
local function stepContest(bot, job, now)
    local target = contestTarget(bot, job)
    if target ~= nil then
        if job.lastAttackAt == nil or now - job.lastAttackAt >= settings().Timing.ContestAttackGap then
            bot:Action_AttackUnit(target, true)
            job.lastAttackAt = now
        end
        return true
    end
    if not arrived(bot, job.stand) then
        return moveTo(bot, job.stand)
    end
    endContest(bot, job, "no-target")
    return false
end
local function step(bot, job)
    local now = DotaTime()
    local cfg = settings()
    if job.kind == "contest" then
        return stepContest(bot, job, now)
    end
    if job.phase == "travel" or job.phase == "wait" then
        telegraph(bot, job, now)
        if now < job.aggroAt then
            if not arrived(bot, job.stand) then
                return moveTo(bot, job.stand)
            end
            job.phase = "wait"
            return true
        end
        job.phase = "aggro"
    end
    if job.phase == "aggro" then
        if job.aggroTarget == nil then
            local creep = campNeutral(bot, job)
            if creep ~= nil then
                if job.kind == "stack" then
                    job.stackBefore = neutralsInBox(bot, job.activeCamp)
                end
                bot:Action_AttackUnit(creep, true)
                job.aggroTarget = creep
                job.aggroOrderedAt = GameTime()
                return true
            end
            if now >= job.aggroAt + cfg.Timing.NoCampAfter then
                Stacking.ClearStack(job.activeCamp)
                abort(bot, job, "mistake:no-camp")
                return false
            end
            return moveTo(bot, job.stand)
        end
        if not aggroConfirmed(bot, job) then
            if GameTime() - (job.aggroOrderedAt or GameTime()) >= cfg.Timing.AggroConfirm then
                abort(bot, job, "mistake:no-aggro")
                return false
            end
            if not job.aggroTarget:IsAlive() or not job.aggroTarget:CanBeSeen() then
                job.aggroTarget = nil
            end
            return true
        end
        if job.stage == 1 then
            job.actualAggro = now
        end
        job.aggroTarget = nil
        if job.kind == "stack" then
            noteStackAggro(bot, job, now)
            job.phase = "exit"
        else
            job.phase = "lead"
        end
    end
    if job.phase == "exit" then
        if now >= (job.exitUntil or now) then
            job.phase = "done"
            return false
        end
        while job.waypoint < #job.path and arrived(bot, job.path[job.waypoint + 1]) do
            job.waypoint = job.waypoint + 1
        end
        if job.waypoint < #job.path then
            return moveTo(bot, job.path[job.waypoint + 1])
        end
        return true
    end
    if job.phase == "lead" then
        while job.waypoint < #job.path and arrived(bot, job.path[job.waypoint + 1]) do
            job.waypoint = job.waypoint + 1
        end
        if job.waypoint < #job.path then
            return moveTo(bot, job.path[job.waypoint + 1])
        end
        job.phase = "watch"
        job.watchFrom = now
    end
    if job.phase == "watch" then
        sample(bot, job, now)
        if trySecondCamp(bot, job, now) then
            return step(bot, job)
        end
        if now - (job.watchFrom or now) >= cfg.Timing.WatchSec then
            close(
                bot,
                job,
                "done",
                ____exports.Grade(job.kind, job.peakDivert)
            )
            return false
        end
        local last = job.path[#job.path]
        if last ~= nil and not arrived(bot, last) then
            return moveTo(bot, last)
        end
        return true
    end
    return false
end
function ____exports.Think(bot)
    if not LaneConfig.IsActive() then
        return false
    end
    local job = jobs[bot:GetPlayerID()]
    if not isLive(job) then
        return false
    end
    local acted = step(bot, job)
    overlay(bot, job)
    return acted
end
function ____exports.OnEnd(bot)
    if not LaneConfig.IsActive() then
        return
    end
    local job = jobs[bot:GetPlayerID()]
    if isLive(job) then
        abort(bot, job, "mode-end")
    end
end
function ____exports.RegisterProbes()
    LaneHooks.SetRotationProbe(function(bot) return ____exports.UpcomingWithin(
        bot,
        settings().Timing.JobUpcoming
    ) end)
end
____exports.RegisterProbes()
return ____exports
