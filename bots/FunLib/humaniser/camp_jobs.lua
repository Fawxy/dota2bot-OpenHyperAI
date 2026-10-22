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

local function __TS__ArrayPush(self, ...)
    local items = {...}
    local len = #self
    for i = 1, #items do
        len = len + 1
        self[len] = items[i]
    end
    return len
end

local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local settings, inFight, enemyHeroNear, desireOf, campNeutral, neutralsInBox, boxInSight, settleStack, aggroLead, awaitSupply, noteSupply, round3, modeEndFields, LOG_KIND, pendingStacks, pendingModeEnd
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
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
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local LastHitSkill = require(GetScriptDirectory().."/FunLib/humaniser/last_hit_skill")
function settings()
    return LaneConfig.Settings()
end
function inFight(bot)
    local cfg = settings()
    local enemies = bot:GetNearbyHeroes(cfg.Radii.JobStartEnemy, true, BotMode.None) or ({})
    if #enemies == 0 then
        return false
    end
    if bot:WasRecentlyDamagedByAnyHero(cfg.Timing.JobStartHeroHit) then
        return true
    end
    local target = bot:GetAttackTarget()
    return target ~= nil and target ~= nil and target:IsHero() and target:GetTeam() ~= bot:GetTeam()
end
function enemyHeroNear(bot)
    return #(bot:GetNearbyHeroes(
        settings().Radii.JobEnemyHero,
        true,
        BotMode.None
    ) or ({})) > 0
end
function desireOf(kind)
    local t = settings().Timing
    return kind == "contest" and t.ContestDesire or t.JobDesire
end
function campNeutral(bot, job)
    local best
    local bestDist = math.huge
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(
        settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        do
            local __continue267
            repeat
                if n == nil or n == nil or not n:IsAlive() or not n:CanBeSeen() then
                    __continue267 = true
                    break
                end
                if not Camps.InBox(
                    job.activeCamp,
                    n:GetLocation()
                ) then
                    __continue267 = true
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
                __continue267 = true
            until true
            if not __continue267 then
                break
            end
        end
    end
    return best
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
    if spawner == nil or not bot:IsAlive() then
        return false
    end
    return GetUnitToLocationDistance(bot, spawner.location) <= settings().Radii.StackSight and IsLocationVisible(spawner.location)
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
    local from, to = Stacking.Window(p.campIdx)
    local assumed = after == nil and p.aggro >= (from or t.StackAssumedFrom) and p.aggro <= (to or t.StackAssumedTo)
    local stacked = Stacking.NoteStackOutcome(p.campIdx, p.minute, after, assumed)
    local grade = after == nil and "unknown" or ____exports.StackGrade(p.aggro)
    Telemetry.Event(
        "lane_stack",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"camp", p.campIdx},
            {"type", p.type},
            {"aggro", p.aggro},
            {"planned", p.planned},
            {"before", p.before},
            {"after", after or "?"},
            {"grade", grade},
            {"stacked", stacked},
            {"assumed", assumed}
        }
    )
    HDebug.Log(
        "lane",
        string.format(
            "stack pid=%d camp=%d type=%s aggro=%.1f planned=%.1f before=%d after=%s grade=%s stacked=%d",
            bot:GetPlayerID(),
            p.campIdx,
            p.type,
            p.aggro,
            p.planned,
            p.before,
            after == nil and "?" or tostring(after),
            grade,
            stacked and 1 or 0
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
    if grade == "ok" and stacked and after ~= nil then
        Stacking.Telegraph(bot, p.type)
    end
end
function aggroLead(bot, creep)
    local t = settings().Timing
    local estimate = LaneConfig.Helpers().GetAttackProDelayTime
    local lead = estimate ~= nil and estimate(bot, creep) or t.AggroLeadDefault
    return math.max(
        0,
        math.min(t.AggroLeadMax, lead)
    )
end
function awaitSupply(bot, job, now, item, modifier)
    job.supplyUntil = now + settings().Timing.SupplyWait
    job.supplyModifier = modifier
    job.supplyItem = item
    noteSupply(bot, job, item, "use")
end
function noteSupply(bot, job, item, state, reason)
    if item == nil or not Telemetry.IsEnabled() then
        return
    end
    local key = (item .. ":") .. state
    if job.supplyNoted == nil then
        job.supplyNoted = {}
    end
    if job.supplyNoted[key] == true then
        return
    end
    job.supplyNoted[key] = true
    local maxHP = bot:GetMaxHealth()
    local maxMP = bot:GetMaxMana()
    local ____Telemetry_Event_47 = Telemetry.Event
    local ____array_46 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"item", item},
        {"state", state},
        unpack(reason ~= nil and ({{"reason", reason}}) or ({}))
    )
    __TS__SparseArrayPush(
        ____array_46,
        {"kind", LOG_KIND[job.kind]},
        {"phase", job.phase},
        {
            "hp",
            maxHP > 0 and round3(bot:GetHealth() / maxHP) or -1
        },
        {
            "mp",
            maxMP > 0 and round3(bot:GetMana() / maxMP) or -1
        }
    )
    ____Telemetry_Event_47(
        "lane_job_supply",
        {__TS__SparseArraySpread(____array_46)}
    )
end
--- Logs a pending mode-end abort once farm has given way, or at once when forced; it waits at most a second.
function ____exports.FlushModeEnd(bot, force)
    if force == nil then
        force = false
    end
    local pid = bot:GetPlayerID()
    local pending = pendingModeEnd[pid]
    if pending == nil then
        return
    end
    local to = bot:GetActiveMode()
    if not force and to == BotMode.Farm and GameTime() - pending.at < 1 then
        return
    end
    __TS__Delete(pendingModeEnd, pid)
    local ____Telemetry_Event_49 = Telemetry.Event
    local ____array_48 = __TS__SparseArrayNew(unpack(pending.fields))
    __TS__SparseArrayPush(
        ____array_48,
        {
            "to",
            HDebug.ModeName(to)
        },
        {
            "toBy",
            Intent.Explain(bot, to)
        },
        {
            "toAge",
            round3(Intent.SampleAge(bot, to))
        },
        {
            "logLag",
            round3(GameTime() - pending.at)
        }
    )
    ____Telemetry_Event_49(
        "lane_job_abort",
        {__TS__SparseArraySpread(____array_48)}
    )
end
function round3(v)
    return v == nil and -1 or math.floor(v * 1000 + 0.5) / 1000
end
function modeEndFields(bot, job)
    if not Telemetry.IsEnabled() then
        return {}
    end
    return {
        {
            "competing",
            Intent.Competing(bot)
        },
        {"hold", job.retreatHold or "-"},
        {
            "holdAge",
            round3(Intent.ClaimAge(bot, "lane:job_hold", BotMode.Retreat))
        },
        {
            "focusAge",
            round3(Intent.ClaimAge(bot, "lane:job_focus", BotMode.Ward))
        },
        {
            "farmAge",
            round3(Intent.SampleAge(bot, BotMode.Farm))
        }
    }
end
local PULL_KINDS = {full_pull = true, half_pull = true, stack_pull = true, double_pull = true}
local PULL_TECHS = {full_pull = "full_pull", half_pull = "half_pull", stack_pull = "stack_pull"}
LOG_KIND = {
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
local RANGED_ATTACK_RANGE = 326
local jobs = {}
local doneCycle = {}
pendingStacks = {}
--- The aggro time of a job aborted before it acted, so the same attempt is not registered again.
local skipped = {}
--- Gates of the bot's lane_plan events in its latest wave cycle.
local planNoted = {}
--- The core's view of its support leaving for a camp: when it started, and how it was known.
local covering = {}
--- Until when a bot starts no pre-contest in that lane: the last one found the enemy not pulling.
local preContestRest = {}
pendingModeEnd = {}
function ____exports.ResetCache()
    jobs = {}
    doneCycle = {}
    pendingStacks = {}
    skipped = {}
    planNoted = {}
    covering = {}
    preContestRest = {}
    pendingModeEnd = {}
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
        return data.stack ~= nil and ({Stacking.AggroSec(data)}) or ({})
    end
    return data.pull ~= nil and PullTiming.SeedSeconds(data.pull, kind == "half_pull") or ({})
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
--- The point `dist` along the polyline from `origin` through `path`; the last point when the polyline is shorter.
function ____exports.LookoutPoint(origin, path, dist)
    local from = origin
    local left = dist
    for ____, to in ipairs(path) do
        local seg = dist2D(from, to)
        if seg >= left and seg > 0 then
            local f = left / seg
            return Vector(from.x + (to.x - from.x) * f, from.y + (to.y - from.y) * f, from.z)
        end
        left = left - seg
        from = to
    end
    return from
end
function ____exports.WindowOpen(now, aggroAt, travel)
    local t = settings().Timing
    return now >= aggroAt - travel - t.JobStartSlack and now <= aggroAt + t.JobStartLate
end
--- Camps hold neutrals for the whole minute containing `time` only from their first spawn on.
function ____exports.CampsUp(time)
    local t = settings().Timing
    return math.floor(time / t.PullPeriod) * t.PullPeriod >= t.NeutralFirstSpawn
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
    return Camps.StandPoint(
        spawner,
        firstWaypoint,
        settings().Radii.StandOffset
    )
end
local leadPath = PullTiming.LeadPath
--- Where a puller of this camp stands to hit it, whichever team's camp data it is.
function ____exports.PullerStand(data)
    local spawner = Camps.SpawnerByIdx(data.campIdx)
    if spawner == nil or data.pull == nil then
        return nil
    end
    return standFor(
        spawner,
        leadPath(data.pull, data.pull.meetPoint)[1]
    )
end
local function timingFor(kind, data, meet)
    return PullTiming.ForCamp(data, kind == "half_pull", meet)
end
--- The classic double pull: hit the hard camp from its side facing the small camp, walk to the small camp's stand, hit
-- it on its own second and lead both; the hard camp follows and must reach the meet point by DoublePullJoin after the
-- wave. The reverse (the hard camp led in once the small one engaged) cannot fit on 7.41: evil_1 / good_2 are 6-9 s of
-- neutral walk from the small camp's meet plus the bot's walk there, so they would arrive 10-16 s after the wave.
-- `why`: no-camp, no-wave (the small camp is not wave-timed, so the hard camp cannot be placed), far, join.
function ____exports.DoubleGeometry(small, hard, speed)
    local smallSp = Camps.SpawnerByIdx(small.campIdx)
    local hardSp = Camps.SpawnerByIdx(hard.campIdx)
    if small.pull == nil or smallSp == nil or hardSp == nil then
        return {why = "no-camp", before = 0, late = 0, gap = 0}
    end
    local timing = timingFor("full_pull", small)
    if timing.waveAfter == nil then
        return {why = "no-wave", before = 0, late = 0, gap = 0}
    end
    local cfg = settings()
    local exact = leadPath(small.pull, small.pull.meetPoint)
    local smallStand = standFor(smallSp, exact[1])
    local hardStand = Camps.StandPoint(hardSp, smallStand, cfg.Radii.StandOffset)
    local gap = ____exports.TravelTime(
        dist2D(hardStand, smallStand),
        speed
    )
    local before = gap + cfg.Timing.DoublePullHitGap
    local hardSpeed = cfg.PullTiming.NeutralSpeed[hard.type] or 300
    local late = PullTiming.WalkLength(
        hardSp.location,
        {
            smallStand,
            unpack(exact)
        }
    ) / hardSpeed - before - timing.waveAfter
    local why
    if gap > cfg.Timing.DoublePullMaxGap then
        why = "far"
    elseif late > cfg.Timing.DoublePullJoin then
        why = "join"
    end
    return {
        why = why,
        before = before,
        late = late,
        gap = gap,
        hardStand = hardStand
    }
end
local function hpOk(bot)
    local maxHP = bot:GetMaxHealth()
    return maxHP > 0 and bot:GetHealth() / maxHP >= settings().Thresholds.JobMinHP
end
--- Why a pull or stack should not start now, else undefined. Forced (debug) jobs skip it.
local function startBlocked(bot)
    local maxHP = bot:GetMaxHealth()
    if maxHP <= 0 or bot:GetHealth() / maxHP < settings().Thresholds.JobStartHP then
        return "low-hp"
    end
    local retreat = Intent.Resolved(bot, BotMode.Retreat)
    if retreat ~= nil and retreat >= settings().Timing.JobDesire then
        return "retreat"
    end
    if inFight(bot) then
        return "fight"
    end
    return nil
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
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", LOG_KIND[job.kind]},
        {"camp", job.campIdx},
        {"key", data.key},
        {
            "data",
            dataLabel(data)
        },
        {"aggroAt", job.aggroAt},
        {"forced", job.forced == true},
        {"core", job.core == true},
        {"timing", job.timing or "seed"}
    }
    if job.preAggroAt ~= nil then
        fields[#fields + 1] = {"pre", 1}
    end
    if job.take == true then
        fields[#fields + 1] = {"take", 1}
    end
    Telemetry.Event("lane_job_start", fields)
    HDebug.Log(
        "lane",
        string.format(
            "job-start pid=%d kind=%s camp=%d key=%s data=%s aggroAt=%.1f forced=%s timing=%s",
            bot:GetPlayerID(),
            LOG_KIND[job.kind],
            job.campIdx,
            data.key or "-",
            dataLabel(data),
            job.aggroAt,
            tostring(job.forced == true),
            job.timing or "seed"
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
    local aggroSec = Stacking.AggroSec(data)
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
    local exitUntil = minuteStart + period + cfg.Timing.StackExitUntil
    Stacking.Reserve(
        req.campIdx,
        bot:GetPlayerID(),
        exitUntil
    )
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
                telegraphed = false,
                baseAggro = base,
                exitUntil = exitUntil
            }
        ),
        data
    )
    return true
end
--- Started only by counterplay: walk to the enemy pull camp and hit the puller while it stays visible. A pre-contest
-- (preAggroAt) first waits at a lookout on their pull path for the expected puller.
local function startContest(bot, req)
    local data = Camps.ByIdx(req.campIdx)
    local spawner = Camps.SpawnerByIdx(req.campIdx)
    if data == nil or spawner == nil then
        return false
    end
    local now = DotaTime()
    local stand = Camps.BoxCenter(spawner)
    if req.preAggroAt ~= nil then
        if data.pull == nil then
            return false
        end
        stand = ____exports.LookoutPoint(
            spawner.location,
            PullTiming.LeadPath(data.pull, data.pull.meetPoint),
            settings().Radii.PreContestStand
        )
    end
    register(
        bot,
        __TS__ObjectAssign({}, req, {
            phase = req.preAggroAt ~= nil and "lookout" or "travel",
            aggroAt = req.preAggroAt or now,
            plannedSec = 0,
            path = {stand},
            startedAt = now,
            peakDivert = 0,
            waveSize = 0,
            activeCamp = req.campIdx,
            stand = stand,
            waypoint = 0,
            stage = 1,
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
    if not hpOk(bot) then
        return false
    end
    if req.kind == "contest" then
        return startContest(bot, req)
    end
    if PULL_KINDS[req.kind] ~= true then
        return false
    end
    local data = Camps.ByIdx(
        req.campIdx,
        bot:GetTeam()
    )
    local spawner = Camps.SpawnerByIdx(req.campIdx)
    if data == nil or data.pull == nil or spawner == nil then
        return false
    end
    local timing = timingFor(req.kind, data)
    local seconds = timing.seconds
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
    local first
    if req.kind == "double_pull" then
        local ____temp_0
        if req.secondCampIdx ~= nil then
            ____temp_0 = Camps.ByIdx(
                req.secondCampIdx,
                bot:GetTeam()
            )
        else
            ____temp_0 = nil
        end
        local hard = ____temp_0
        local g = hard ~= nil and ____exports.DoubleGeometry(
            data,
            hard,
            bot:GetCurrentMovementSpeed()
        ) or nil
        if hard == nil or g == nil or g.why ~= nil or g.hardStand == nil then
            return false
        end
        first = {
            camp = hard.campIdx,
            stand = noisy(g.hardStand, noise),
            before = g.before
        }
    end
    local base = ____exports.NextAggroTime(now - cfg.Timing.JobStartLate, seconds, period)
    if req.forced == true and base < now + travelTo(bot, stand) then
        base = ____exports.NextAggroTime(
            now + travelTo(bot, stand),
            seconds,
            period
        )
    end
    local slot = base
    local shift = PullTiming.LiveShift(timing, base, now)
    if shift ~= nil then
        base = base + shift
    end
    local job = __TS__ObjectAssign({}, req, {
        phase = "travel",
        aggroAt = base + jitter - (first and first.before or 0),
        chain = first ~= nil and ({stand = stand, aggroAt = base + jitter}) or nil,
        plannedSec = base % period,
        path = path,
        meet = meet,
        slot = slot,
        waveAt = timing.waveAfter ~= nil and base + timing.waveAfter or nil,
        timing = shift ~= nil and "live" or timing.source,
        startedAt = now,
        peakDivert = 0,
        waveSize = 0,
        activeCamp = first and first.camp or req.campIdx,
        stand = first and first.stand or stand,
        waypoint = 0,
        stage = 1,
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
function ____exports.PreContestResting(bot, lane)
    local r = preContestRest[bot:GetPlayerID()]
    return r ~= nil and r.lane == lane and DotaTime() < r["until"]
end
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
--- How a core knows its lane support is away on a camp job, or undefined: `job` when this module instance holds the
-- support's job (modules shared between bots), else `camp` when the support is seen away from the front within
-- Radii.CoverCamp of one of the lane's pull camps (also a human support's pull). Laning phase only.
function ____exports.CoverFor(bot)
    if not LaneConfig.IsActive() or not LaneConfig.InLaningPhase() then
        return nil, nil, nil
    end
    local s = LaneState.ForBot(bot)
    if s == nil or LaneRoles.RoleIn(bot, s) ~= "core" then
        return nil, nil, nil
    end
    local partner = LaneRoles.Partner(bot, s)
    if partner == nil or not partner.alive then
        return nil, nil, nil
    end
    local job = jobs[partner.pid]
    if isLive(job) and job.kind ~= "contest" then
        return "job", partner.pid, LOG_KIND[job.kind]
    end
    if partner.distToFront <= settings().Thresholds.SupportNearFront then
        return nil, nil, nil
    end
    local loc = partner.unit:GetLocation()
    for ____, c in ipairs(Camps.PullCampsFor(s.team, s.lane)) do
        local spawner = Camps.SpawnerByIdx(c.campIdx)
        if spawner ~= nil and dist2D(
            loc,
            Camps.BoxCenter(spawner)
        ) <= settings().Radii.CoverCamp then
            return "camp", partner.pid, "camp"
        end
    end
    return nil, nil, nil
end
--- Lane.Tick: while its support is on a camp, the core plays safer: retreat is scaled up by Thresholds.CoverRetreatScale
-- (it backs off sooner from a threat it would have stood against with the support beside it) and 07's harass and
-- forward stand point are off (Covering). `lane_cover` marks when that starts and ends.
function ____exports.CoverTick(bot)
    local pid = bot:GetPlayerID()
    local via, partner, kind = ____exports.CoverFor(bot)
    local now = DotaTime()
    local cur = covering[pid]
    if via == nil then
        if cur ~= nil then
            __TS__Delete(covering, pid)
            Intent.Release(bot, "lane:cover", BotMode.Retreat)
            Telemetry.Event("lane_cover", {
                {"pid", pid},
                {"state", "end"},
                {"partner", cur.partner},
                {"via", cur.via},
                {"dur", now - cur.since}
            })
        end
        return
    end
    if cur == nil then
        covering[pid] = {since = now, via = via, partner = partner, kind = kind}
        Telemetry.Event("lane_cover", {
            {"pid", pid},
            {"state", "start"},
            {"partner", partner},
            {"via", via},
            {"kind", kind}
        })
    end
    Intent.Claim(
        bot,
        {
            source = "lane:cover",
            tier = "LANE_PLAN",
            mode = BotMode.Retreat,
            scale = settings().Thresholds.CoverRetreatScale
        }
    )
end
function ____exports.Covering(bot)
    return covering[bot:GetPlayerID()] ~= nil
end
local function logJob(bot, job, grade)
    local data = Camps.ByIdx(
        job.campIdx,
        bot:GetTeam()
    )
    local aggro = job.plannedSec + ((job.actualAggro or job.aggroAt) - job.baseAggro)
    Telemetry.Event(
        "lane_job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", LOG_KIND[job.kind]},
            {"camp", job.campIdx},
            {"key", data and data.key},
            {"aggro", aggro},
            {"planned", job.plannedSec},
            {"divert", job.peakDivert},
            {"grade", grade}
        }
    )
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
local JOB_CLAIM_SOURCES = {"lane:camp_job", "lane:job_focus", "lane:job_hold"}
local function releaseClaims(bot)
    for ____, source in ipairs(JOB_CLAIM_SOURCES) do
        Intent.ReleaseSource(bot, source)
    end
end
--- Completed pull: the graded `job` line that parse_condebug.js counts as an attempt.
local function close(bot, job, phase, grade)
    job.phase = phase
    releaseClaims(bot)
    doneCycle[bot:GetPlayerID()] = cycleOf(DotaTime())
    if job.kind == "stack_pull" then
        Stacking.ClearStack(job.campIdx)
    end
    logJob(bot, job, grade)
end
--- Aborts go on the `job-abort` line, which the console parser does not read, so safety aborts never count
-- against a camp's timing.
local function abort(bot, job, reason, keepStack, extra, deferLog)
    if keepStack == nil then
        keepStack = false
    end
    if extra == nil then
        extra = {}
    end
    if deferLog == nil then
        deferLog = false
    end
    ____exports.FlushModeEnd(bot, true)
    local phase = job.phase
    job.phase = "return"
    releaseClaims(bot)
    local pid = bot:GetPlayerID()
    if job.acted ~= true then
        LanePlanner.Release(
            bot,
            commitTech(job.kind)
        )
        skipped[pid] = job.slot or job.baseAggro
    elseif job.kind ~= "stack" then
        doneCycle[pid] = cycleOf(DotaTime())
    end
    if job.take == true then
        LanePlanner.Release(bot, "contest")
    end
    if not keepStack and job.kind == "stack_pull" and job.actualAggro ~= nil then
        Stacking.ClearStack(job.campIdx)
    end
    if job.kind == "stack" then
        Stacking.Release(job.campIdx, pid)
    end
    local token = string.gsub(reason, "%s+", "-")
    local ____array_13 = __TS__SparseArrayNew({"pid", pid}, {"kind", LOG_KIND[job.kind]}, {"camp", job.campIdx})
    local ____opt_11 = Camps.ByIdx(
        job.campIdx,
        bot:GetTeam()
    )
    __TS__SparseArrayPush(
        ____array_13,
        {"key", ____opt_11 and ____opt_11.key},
        {"reason", token},
        {"phase", phase},
        {"acted", job.acted == true},
        {"divert", job.peakDivert},
        unpack(job.preAggroAt ~= nil and ({{"pre", 1}}) or ({}))
    )
    __TS__SparseArrayPush(
        ____array_13,
        unpack(job.take == true and ({{"take", 1}}) or ({}))
    )
    __TS__SparseArrayPush(
        ____array_13,
        unpack(extra)
    )
    local fields = {__TS__SparseArraySpread(____array_13)}
    if deferLog and Telemetry.IsEnabled() then
        pendingModeEnd[pid] = {
            fields = fields,
            at = GameTime()
        }
    else
        Telemetry.Event("lane_job_abort", fields)
    end
    local ____HDebug_Log_18 = HDebug.Log
    local ____string_format_17 = string.format
    local ____array_16 = __TS__SparseArrayNew(
        "job-abort pid=%d kind=%s camp=%d key=%s reason=%s divert=%.2f",
        bot:GetPlayerID(),
        LOG_KIND[job.kind],
        job.campIdx
    )
    local ____opt_14 = Camps.ByIdx(
        job.campIdx,
        bot:GetTeam()
    )
    __TS__SparseArrayPush(____array_16, ____opt_14 and ____opt_14.key or "-", token, job.peakDivert)
    ____HDebug_Log_18(
        "lane",
        ____string_format_17(__TS__SparseArraySpread(____array_16))
    )
end
--- A stack's walk-off ended (its outcome follows on `lane_stack`). Logged so the end is never only implied: without it a
-- stack ending at :01 and a pull starting 10 s later read as two jobs at once (ogre, console.9055921786, 8:01 / 8:11).
local function endStack(bot, job)
    job.phase = "done"
    releaseClaims(bot)
    Telemetry.Event(
        "lane_job_end",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", LOG_KIND[job.kind]},
            {"camp", job.campIdx}
        }
    )
end
--- A contest is no pull attempt, so it ends on its own line, which the console parser does not read.
local function endContest(bot, job, reason)
    job.phase = "return"
    releaseClaims(bot)
    if job.take == true then
        LanePlanner.Release(bot, "contest")
    end
    doneCycle[bot:GetPlayerID()] = cycleOf(DotaTime())
    local pre = job.preAggroAt ~= nil and 1 or 0
    if pre == 1 and (reason == "enemy-in-lane" or reason == "no-pull") then
        preContestRest[bot:GetPlayerID()] = {
            lane = bot:GetAssignedLane(),
            ["until"] = DotaTime() + settings().Timing.PreContestCooldown
        }
    end
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", LOG_KIND[job.kind]},
        {"camp", job.campIdx},
        {"reason", reason},
        {"pre", pre}
    }
    if job.take == true then
        __TS__ArrayPush(fields, {"take", 1}, {"swings", job.swings or 0})
    end
    Telemetry.Event("lane_job_end", fields)
    HDebug.Log(
        "lane",
        string.format(
            "contest-end pid=%d camp=%d reason=%s pre=%d",
            bot:GetPlayerID(),
            job.campIdx,
            reason,
            pre
        )
    )
end
--- Continue checks for a running pull: the partner check is the committed one (LaneRoles.PartnerHolding).
local function jobAllowed(bot, s, forced)
    if not hpOk(bot) then
        return false, "low-hp"
    end
    local enemies = LaneState.Enemies(bot, s.lane)
    local ok, why = LaneRoles.MayRunCampJob(bot, s, enemies, true)
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
        return true, "ok"
    end
    return LaneRoles.PartnerHolding(bot, s, enemies)
end
--- Stacks need no camp-job ownership (any eligible support may stack, after laning too); forced ones only safety.
local function stackAllowed(bot, job)
    local s = LaneState.ForBot(bot)
    if job.core == true then
        return Stacking.SafeAway(
            bot,
            LaneState.Enemies(
                bot,
                s and s.lane or bot:GetAssignedLane()
            )
        )
    end
    local laning = LaneConfig.InLaningPhase()
    if laning and s == nil then
        return false, "no-lane"
    end
    local enemies = LaneState.Enemies(
        bot,
        s and s.lane or bot:GetAssignedLane()
    )
    local ok, why = unpack(job.forced == true and ({Stacking.Safe(bot, s, enemies, true)}) or ({Stacking.Eligible(bot, s, enemies, true)}))
    if not ok then
        return false, why
    end
    if laning and s ~= nil and LanePlan.View(bot, s).handsOff then
        return false, "handsoff"
    end
    return true, "ok"
end
local function partnerFields(bot, s)
    local ____temp_23
    if s ~= nil then
        ____temp_23 = LaneRoles.ReadPartner(
            bot,
            s,
            LaneState.Enemies(bot, s.lane)
        )
    else
        ____temp_23 = nil
    end
    local r = ____temp_23
    if r == nil then
        return {}
    end
    return {
        {"partner", r.pid},
        {"php", r.hp},
        {"pnear", r.near},
        {"pclose", r.close},
        {"ploss", r.loss}
    }
end
--- Safety aborts carry the partner reading, so the log shows what the support reacted to.
local function abortUnsafe(bot, job, why, s)
    local partnerAbort = string.find(why, "^partner")
    abort(
        bot,
        job,
        why,
        false,
        partnerAbort ~= nil and partnerFields(bot, s) or ({})
    )
end
--- Once per job: the start gate would have stopped it here, and only the commitment keeps it going.
local function noteHeld(bot, job, s)
    if job.heldNoted == true or s == nil or not Telemetry.IsEnabled() then
        return
    end
    if LaneRoles.PartnerSafe(
        bot,
        s,
        LaneState.Enemies(bot, s.lane)
    ) then
        return
    end
    job.heldNoted = true
    Telemetry.Event(
        "lane_job_hold",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"hold", "partner"},
            {"kind", LOG_KIND[job.kind]},
            {"camp", job.campIdx},
            {"phase", job.phase},
            unpack(partnerFields(bot, s))
        }
    )
end
--- The camp has been hit and is chasing the bot: from the hit in the aggro phase through lead and watch, and for a
-- double pull also the walk to the small camp and its hit once the hard camp is on the bot (its chain is taken up).
local function drawingCamp(job)
    if job.kind == "stack" or job.kind == "contest" then
        return false
    end
    if job.kind == "double_pull" and job.chain == nil then
        return true
    end
    return job.phase == "lead" or job.phase == "watch" or job.phase == "aggro" and job.aggroOrderedAt ~= nil
end
--- A core's stack once its hit is ordered: the walk-off drags the camp after the bot like a pull's lead. Without the hold,
-- retreat's creep-damage branch (0.81 at 73% HP) cut both core stacks' walk-offs in console.9057148714/9057153685.
local function coreStackDrawn(job)
    return job.kind == "stack" and job.core == true and (job.phase == "exit" or job.phase == "aggro" and job.aggroOrderedAt ~= nil)
end
--- What should still send a pulling bot home; the neutrals' own hits (the point of a pull) are not on the list.
local function retreatThreat(bot)
    local cfg = settings()
    local maxHP = bot:GetMaxHealth()
    if maxHP <= 0 or bot:GetHealth() / maxHP < cfg.Thresholds.JobHoldMinHP then
        return "hp"
    end
    local hit = cfg.Timing.JobHoldHeroHit
    if bot:WasRecentlyDamagedByAnyHero(hit) then
        return "hero-hit"
    end
    if bot:WasRecentlyDamagedByTower(hit) then
        return "tower"
    end
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        if e.visible and e.unit ~= nil and e.unit:GetAttackTarget() == bot then
            return "hero-attack"
        end
    end
    for ____, tower in ipairs(bot:GetNearbyTowers(1000, true)) do
        if tower:GetAttackTarget() == bot then
            return "tower"
        end
    end
    return nil
end
local function logRetreatHold(bot, job, state, reason)
    if not Telemetry.IsEnabled() then
        return
    end
    local maxHP = bot:GetMaxHealth()
    Telemetry.Event(
        "lane_job_hold",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"hold", "retreat"},
            {"state", state},
            {"reason", reason or "neutrals"},
            {"kind", LOG_KIND[job.kind]},
            {"camp", job.campIdx},
            {"phase", job.phase},
            {
                "hp",
                maxHP > 0 and bot:GetHealth() / maxHP or 0
            }
        }
    )
end
--- True while a pull's retreat may be held below the job: the camp is drawn and nothing but neutrals threatens.
-- The first real threat releases the hold for the rest of the job. lane_job_hold logs the hold and its release once each.
function ____exports.HoldsRetreat(bot)
    local job = jobs[bot:GetPlayerID()]
    if not isLive(job) or job.retreatHold == "off" or not (drawingCamp(job) or coreStackDrawn(job)) then
        return false
    end
    local why = retreatThreat(bot)
    if why == nil then
        if job.retreatHold ~= "on" then
            job.retreatHold = "on"
            logRetreatHold(bot, job, "on")
        end
        return true
    end
    job.retreatHold = "off"
    Intent.ReleaseSource(bot, "lane:job_hold")
    logRetreatHold(bot, job, "off", why)
    return false
end
--- Spells and items wait while a job works a camp: upstream's farm branches (J.IsFarming is true in farm mode or on a
-- neutral target) cast stuns and nukes on the camp it is drawing. From the camp coming into sight, or being drawn,
-- until the job ends; an enemy hero in range lifts it so the bot can still fight or save itself.
function ____exports.HoldsCasts(bot)
    local job = jobs[bot:GetPlayerID()]
    if not isLive(job) or job.kind == "contest" then
        return false
    end
    if job.phase == "travel" and not drawingCamp(job) and campNeutral(bot, job) == nil then
        return false
    end
    return not enemyHeroNear(bot)
end
--- The job's farm desire goes above Valve's attack mode (JobCommitDesire) unless the bot has a reason to leave: an
-- enemy hero near, a human's order or survival claim, or retreat already scoring at the job's own desire. Retreat is
-- scored before farm in each round, so its sample is this round's; with no fresh sample (intent off) nothing commits.
function ____exports.Commits(bot)
    local job = jobs[bot:GetPlayerID()]
    if not isLive(job) or job.kind == "contest" or Orders.GetFor(bot) ~= nil or Intent.PriorityLive(bot) or enemyHeroNear(bot) then
        return false
    end
    local retreat = Intent.Resolved(bot, BotMode.Retreat)
    return retreat ~= nil and retreat < desireOf(job.kind)
end
--- A take's continue check. Its bot is not the lane's camp-job owner, so MayRunCampJob does not apply: it leaves on
-- low HP, on TakePullMax, or once outnumbered by visible enemy heroes at the camp.
local function keepTaking(bot, job, now)
    local cfg = settings()
    if not LaneConfig.IsOn("TakePull") then
        abort(bot, job, "flag-off")
        return false
    end
    local s = LaneState.ForBot(bot)
    if s ~= nil and LanePlan.View(bot, s).handsOff then
        abort(bot, job, "handsoff")
        return false
    end
    local reason
    if not hpOk(bot) then
        reason = "low-hp"
    elseif now - job.startedAt >= cfg.Timing.TakePullMax then
        reason = "timeout"
    elseif job.creepSeenAt == nil and s ~= nil and s.enemy.count > cfg.Thresholds.TakePullLaneCreeps then
        reason = "lane-wave"
    else
        local near = 0
        local here = bot:GetLocation()
        for ____, e in ipairs(LaneState.Enemies(
            bot,
            bot:GetAssignedLane()
        )) do
            if e.visible and dist2D(e.location, here) <= cfg.Radii.TakePullDanger then
                near = near + 1
            end
        end
        if near >= cfg.Thresholds.TakePullDangerEnemies then
            reason = "outnumbered"
        end
    end
    if reason == nil then
        return true
    end
    endContest(bot, job, reason)
    return false
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
    if job.take == true then
        return keepTaking(bot, job, now)
    end
    if job.kind == "contest" then
        local ____temp_24
        if job.preAggroAt ~= nil then
            ____temp_24 = job.attackFrom
        else
            ____temp_24 = job.startedAt
        end
        local from = ____temp_24
        if from ~= nil and now - from >= settings().Timing.ContestMax then
            endContest(bot, job, "timeout")
            return false
        end
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
        local ____LaneConfig_InLaningPhase_result_25
        if LaneConfig.InLaningPhase() then
            ____LaneConfig_InLaningPhase_result_25 = LaneState.ForBot(bot)
        else
            ____LaneConfig_InLaningPhase_result_25 = nil
        end
        local ls = ____LaneConfig_InLaningPhase_result_25
        if not ok then
            abortUnsafe(bot, job, why, ls)
        else
            noteHeld(bot, job, ls)
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
        abortUnsafe(bot, job, why, s)
        return false
    end
    if LanePlan.View(bot, s).handsOff then
        abort(bot, job, "handsoff")
        return false
    end
    noteHeld(bot, job, s)
    return true
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
--- Travel to the camp's stand point when the start window of its next full or half pull would be open now for a bot
-- within MaxTravel, else undefined. A result above MaxTravel means only the distance keeps the window shut.
local function windowTravel(bot, data, kind, now)
    local spawner = Camps.SpawnerByIdx(data.campIdx)
    if spawner == nil or data.pull == nil then
        return nil
    end
    local t = settings().Timing
    local base = ____exports.NextAggroTime(
        now - t.JobStartLate,
        timingFor(kind, data).seconds,
        t.PullPeriod
    )
    if not ____exports.CampsUp(base) then
        return nil
    end
    local travel = travelTo(
        bot,
        standFor(
            spawner,
            leadPath(data.pull, data.pull.meetPoint)[1]
        )
    )
    return ____exports.WindowOpen(
        now,
        base,
        math.min(travel, t.MaxTravel)
    ) and travel or nil
end
--- In reach, and still able to stand at the camp by the late tolerance: a later start would only end as `late`.
local function windowFor(bot, data, kind, now)
    local t = settings().Timing
    local travel = windowTravel(bot, data, kind, now)
    if travel == nil or travel > t.MaxTravel then
        return false
    end
    return now + travel <= ____exports.NextAggroTime(
        now - t.JobStartLate,
        timingFor(kind, data).seconds,
        t.PullPeriod
    ) + t.JobStartLate
end
--- One lane_plan event per wave cycle and gate: why this bot did or did not start a pull in it. The gates are
-- re-checked every frame, so a bot that reads `far` early in the cycle may still reach the planner later in it.
local function notePlan(bot, s, now, fields)
    if not Telemetry.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    local cycle = cycleOf(now)
    local gate = fields[1][2]
    local noted = planNoted[pid]
    if noted == nil or noted.cycle ~= cycle then
        noted = {cycle = cycle, gates = {}}
        planNoted[pid] = noted
    end
    if noted.gates[gate] == true then
        return
    end
    noted.gates[gate] = true
    local mayRun, why = LaneRoles.MayRunCampJob(
        bot,
        s,
        LaneState.Enemies(bot, s.lane)
    )
    local ____Telemetry_Event_27 = Telemetry.Event
    local ____array_26 = __TS__SparseArrayNew(
        {"pid", pid},
        unpack(fields)
    )
    __TS__SparseArrayPush(
        ____array_26,
        {"owner", mayRun and "ok" or why},
        {"eq", s.eqPos},
        {"meet", s.meetAmount},
        {"want", s.desiredEq},
        {"front", s.ourFront},
        {"efront", s.enemyFront},
        {"tower", s.ourTowerAmount},
        {"etower", s.theirTowerAmount}
    )
    ____Telemetry_Event_27(
        "lane_plan",
        {__TS__SparseArraySpread(____array_26)}
    )
end
--- Whether this bot may double pull its lane's first two camps (skill, a second camp), and if so whether its start
-- window, the hard camp's hit `before` ahead of the small camp's second, is open now; `why` says what rules it out.
local function doubleFor(bot, camps, now)
    if #camps < 2 or not LaneConfig.Knows(
        "stack_pull",
        LaneConfig.SkillOf(bot)
    ) then
        return nil
    end
    local g = ____exports.DoubleGeometry(
        camps[1],
        camps[2],
        bot:GetCurrentMovementSpeed()
    )
    if g.why ~= nil or g.hardStand == nil then
        return {open = false, why = g.why, g = g}
    end
    local t = settings().Timing
    local base = ____exports.NextAggroTime(
        now - t.JobStartLate,
        timingFor("full_pull", camps[1]).seconds,
        t.PullPeriod
    )
    local hardAt = base - g.before
    local travel = travelTo(bot, g.hardStand)
    if not ____exports.CampsUp(base) or travel > t.MaxTravel or now + travel > hardAt then
        return {open = false, why = "reach", g = g}
    end
    return {
        open = ____exports.WindowOpen(now, hardAt, travel),
        g = g
    }
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
        notePlan(bot, s, now, {{"gate", "no-camp"}})
        return false
    end
    local double = doubleFor(bot, camps, now)
    local doubleOpen = double ~= nil and double.open
    if not doubleOpen and not windowFor(bot, camps[1], "full_pull", now) and not windowFor(bot, camps[1], "half_pull", now) then
        local any = false
        for ____, c in ipairs(camps) do
            if LaneHooks.IsStacked(c.campIdx) and windowFor(bot, c, "stack_pull", now) then
                any = true
            end
        end
        if not any then
            local travel = windowTravel(bot, camps[1], "full_pull", now)
            if travel ~= nil then
                notePlan(
                    bot,
                    s,
                    now,
                    {
                        {
                            "gate",
                            travel > settings().Timing.MaxTravel and "far" or "late"
                        },
                        {"camp", camps[1].campIdx},
                        {"travel", travel},
                        {
                            "timing",
                            timingFor("full_pull", camps[1]).source
                        }
                    }
                )
            end
            return false
        end
    end
    local choice = LanePlanner.Plan(bot, s)
    local input = LanePlanner.LastInput(bot)
    local view = LaneState.ScoreFor(bot, s)
    notePlan(
        bot,
        s,
        now,
        {
            {"gate", "planner"},
            {"camp", camps[1].campIdx},
            {
                "timing",
                timingFor("full_pull", camps[1]).source
            },
            {"tech", choice.tech},
            {"reason", choice.reason},
            {"score", input and input.laneScore},
            {"fscore", input and input.forecastScore},
            {"w", view.foresight},
            {"imb", s.imbalance},
            {"feq", s.forecastEq},
            {"apow", s.allyPower},
            {"epow", s.enemyPower},
            {"plan", input and input.plan.plan},
            {"pullOk", input and input.plan.pullAllowed},
            {"partner", input and input.partnerSafe},
            {"laners", input and input.enemyLaners}
        }
    )
    local kind = PULL_TECHS[choice.tech]
    if kind == nil then
        return false
    end
    local blocked = startBlocked(bot)
    if blocked ~= nil then
        notePlan(bot, s, now, {{"gate", blocked}, {"camp", camps[1].campIdx}})
        return false
    end
    local camp = pullCampFor(kind, camps)
    local asDouble = kind == "full_pull" and doubleOpen
    if kind == "full_pull" and double ~= nil and not double.open and double.why == nil then
        return false
    end
    if not asDouble and not windowFor(bot, camp, kind, now) then
        return false
    end
    local base = ____exports.NextAggroTime(
        now - settings().Timing.JobStartLate,
        timingFor(kind, camp).seconds,
        settings().Timing.PullPeriod
    )
    if skipped[pid] == base then
        return false
    end
    local req = {kind = kind, campIdx = camp.campIdx}
    if asDouble then
        req.kind = "double_pull"
        req.secondCampIdx = camps[2].campIdx
    elseif kind == "full_pull" and double ~= nil then
        notePlan(bot, s, now, {
            {"gate", "double-unfit"},
            {"camp", camp.campIdx},
            {"second", camps[2].campIdx},
            {"why", double.why},
            {"late", double.g.late},
            {"gap", double.g.gap}
        })
    end
    return ____exports.Start(bot, req)
end
--- Earliest second of the minute at which any camp's stack window can open, so most frames skip the stack roll.
local function earliestStackStart()
    local t = settings().Timing
    local earliest = t.StackMoveFrom
    for ____, data in ipairs(Camps.Resolve()) do
        if data.stack ~= nil then
            earliest = math.min(
                earliest,
                Stacking.AggroSec(data) - t.MaxTravel - t.JobStartLate
            )
        end
    end
    return earliest
end
local function scheduleStack(bot, now)
    local t = settings().Timing
    local minute = math.floor(now / t.PullPeriod)
    local sec = now - minute * t.PullPeriod
    if sec < earliestStackStart() or not ____exports.CampsUp(now) then
        return false
    end
    if LanePlanner.Committed(bot) ~= nil then
        return false
    end
    local data = Stacking.WantsStack(bot, minute)
    local ____temp_40
    if data ~= nil then
        ____temp_40 = Camps.SpawnerByIdx(data.campIdx)
    else
        ____temp_40 = nil
    end
    local spawner = ____temp_40
    if data == nil or data.stack == nil or spawner == nil then
        return false
    end
    local travel = travelTo(
        bot,
        Stacking.StandPoint(spawner, data)
    )
    local aggroSec = Stacking.AggroSec(data)
    local from = math.min(t.StackMoveFrom, aggroSec - travel - t.JobStartLate)
    if sec < from or sec > aggroSec then
        return false
    end
    if skipped[bot:GetPlayerID()] == ____exports.NextAggroTime(now, {aggroSec}, t.PullPeriod) then
        return false
    end
    if startBlocked(bot) ~= nil then
        return false
    end
    return ____exports.Start(bot, {kind = "stack", campIdx = data.campIdx, minute = minute})
end
--- Farm's GetDesire registers a job whether or not farm wins the frame. A job farm's Think has not run for
-- JobPreemptAfter while another mode is active was out-bid; a stun inside farm mode is not a pre-emption.
local function preempted(bot, job, now)
    if job.unthought ~= true then
        return false
    end
    if now - (job.lastThinkAt or job.startedAt) <= settings().Timing.JobPreemptAfter then
        return false
    end
    return bot:GetActiveMode() ~= BotMode.Farm
end
--- Ends a live job from outside the executor (farm mode starting a run).
function ____exports.Abort(bot, reason)
    if not LaneConfig.IsActive() then
        return
    end
    local job = jobs[bot:GetPlayerID()]
    if isLive(job) then
        abort(bot, job, reason)
    end
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
            endStack(bot, job)
            return 0
        end
        if preempted(bot, job, now) then
            if job.phase == "watch" then
                close(
                    bot,
                    job,
                    "return",
                    ____exports.Grade(job.kind, job.peakDivert)
                )
            else
                abort(bot, job, "preempted", true)
            end
            return 0
        end
        job.unthought = true
        if not keepGoing(bot, job) then
            return 0
        end
        if job.kind ~= "stack" and job.take ~= true and LanePlanner.Committed(bot) == nil then
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
--- A human core cannot read this module, so the support pings the camp it leaves for, the usual "pulling, play safe"
-- heads-up. A bot core reads the same thing from CoverFor.
local function pingPartner(bot, job)
    if job.pinged == true or job.kind == "contest" or job.core == true then
        return
    end
    job.pinged = true
    if not LaneConfig.IsOn("Telegraph") or not LaneConfig.InLaningPhase() then
        return
    end
    local s = LaneState.ForBot(bot)
    local ____temp_41
    if s ~= nil then
        ____temp_41 = LaneRoles.Partner(bot, s)
    else
        ____temp_41 = nil
    end
    local partner = ____temp_41
    if partner == nil or partner.isBot or not Orders.Ping(bot, job.stand) then
        return
    end
    Telemetry.Event(
        "lane_job_ping",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", LOG_KIND[job.kind]},
            {"camp", job.campIdx},
            {"partner", partner.pid}
        }
    )
end
local function telegraph(bot, job, now)
    pingPartner(bot, job)
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
local function aggroConfirmed(bot, job)
    if job.aggroOrderedAt ~= nil and bot:GetLastAttackTime() >= job.aggroOrderedAt then
        return true
    end
    if job.kind == "double_pull" and job.activeCamp == job.campIdx then
        return false
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
        aggro = job.plannedSec + ((job.actualAggro or now) - job.baseAggro),
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
            local __continue295
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue295 = true
                    break
                end
                if dist2D(
                    c:GetLocation(),
                    center
                ) <= radius then
                    result[#result + 1] = c
                end
                __continue295 = true
            until true
            if not __continue295 then
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
            local __continue304
            repeat
                if not e.visible or e.unit == nil then
                    __continue304 = true
                    break
                end
                local d = dist2D(e.location, center)
                if e.pid == job.targetPid and d <= radii.ContestReach then
                    return e.unit
                end
                if best == nil and d <= radii.EnemyNearCamp then
                    best = e.unit
                end
                __continue304 = true
            until true
            if not __continue304 then
                break
            end
        end
    end
    return best
end
local function enemyInLane(bot, job)
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false
    end
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        if e.pid == job.targetPid and e.visible and dist2D(e.location, s.frontLoc) <= settings().Radii.Exposure then
            return true
        end
    end
    return false
end
--- Waiting at the lookout for the expected puller; true while the job keeps the frame.
local function stepLookout(bot, job, now)
    local t = settings().Timing
    if now >= job.aggroAt - t.PreContestLead and enemyInLane(bot, job) then
        endContest(bot, job, "enemy-in-lane")
        return false
    end
    if now > job.aggroAt + t.PreContestWait then
        endContest(bot, job, "no-pull")
        return false
    end
    if not arrived(bot, job.stand) then
        return moveTo(bot, job.stand)
    end
    Intent.Hold(bot, "lane:precontest")
    return true
end
local function pulledCreeps(bot, job)
    local radii = settings().Radii
    local out = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(radii.LaneCreepScan, true) or ({})) do
        do
            local __continue319
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() then
                    __continue319 = true
                    break
                end
                local loc = c:GetLocation()
                if loc ~= nil and dist2D(loc, job.stand) <= radii.TakePullCreeps then
                    out[#out + 1] = c
                end
                __continue319 = true
            until true
            if not __continue319 then
                break
            end
        end
    end
    return out
end
--- Last hits on their pulled wave; true while the job keeps the frame.
local function stepTake(bot, job, now)
    local t = settings().Timing
    if job.swing ~= nil then
        local target = job.swing.target
        if not target:IsNull() and target:IsAlive() and now - job.swing.at < t.TakePullSwing then
            return true
        end
        job.swing = nil
    end
    if job.arrivedAt == nil and arrived(bot, job.stand) then
        job.arrivedAt = now
    end
    local creeps = pulledCreeps(bot, job)
    if #creeps > 0 then
        job.creepSeenAt = now
        local damage = bot:GetAttackDamage()
        local killable = __TS__ArrayFilter(
            creeps,
            function(____, c) return LastHitSkill.WillKill(
                bot,
                c,
                damage,
                aggroLead(bot, c),
                false
            ) end
        )
        local ____temp_44
        if #killable > 0 then
            ____temp_44 = LastHitSkill.Choose(bot, killable)
        else
            ____temp_44 = nil
        end
        local pick = ____temp_44
        if pick ~= nil then
            bot:Action_AttackUnit(pick, true)
            LastHitSkill.NoteAttempt(bot, pick)
            job.swing = {target = pick, at = now}
            job.swings = (job.swings or 0) + 1
            return true
        end
        local low = creeps[1]
        for ____, c in ipairs(creeps) do
            if c:GetHealth() < low:GetHealth() then
                low = c
            end
        end
        if GetUnitToUnitDistance(bot, low) > bot:GetAttackRange() then
            return moveTo(
                bot,
                low:GetLocation()
            )
        end
        Intent.Hold(bot, "lane:take_pull")
        return true
    end
    local since = job.creepSeenAt or job.arrivedAt
    if since == nil then
        return moveTo(bot, job.stand)
    end
    if now - since >= t.TakePullWait then
        endContest(bot, job, "no-creeps")
        return false
    end
    Intent.Hold(bot, "lane:take_pull")
    return true
end
local function stepContest(bot, job, now)
    if job.take == true then
        return stepTake(bot, job, now)
    end
    local target = contestTarget(bot, job)
    if job.phase == "lookout" then
        if target == nil then
            return stepLookout(bot, job, now)
        end
        job.attackFrom = now
        job.phase = "travel"
    end
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
local function orderAggro(bot, job, creep)
    if job.kind == "stack" then
        job.stackBefore = neutralsInBox(bot, job.activeCamp)
    end
    bot:Action_AttackUnit(creep, true)
    job.aggroTarget = creep
    job.aggroOrderedAt = GameTime()
    job.phase = "aggro"
    return true
end
--- Seen nothing from the stand point (trees, night vision): move the stand in to StandApproach from the spawner origin,
-- once per camp. False when already done or the stand is that close anyway.
local function approachCamp(job)
    local spawner = Camps.SpawnerByIdx(job.activeCamp)
    if spawner == nil or job.approachedCamp == job.activeCamp then
        return false
    end
    job.approachedCamp = job.activeCamp
    local o = spawner.location
    local d = dist2D(job.stand, o)
    local near = settings().Radii.StandApproach
    if d <= near + settings().Radii.JobArrive then
        return false
    end
    job.stand = Vector(o.x + (job.stand.x - o.x) * near / d, o.y + (job.stand.y - o.y) * near / d, o.z)
    return true
end
--- When the aggro hit landed, in DotaTime. GetLastAttackTime() (GameTime clock) is taken as the projectile's release,
-- so a ranged hit adds its flight; a confirmation from a neutral targeting the bot comes after the hit, so `now`.
-- **TODO (in-game):** if GetLastAttackTime() is the swing start, this reads early by the wind-up.
local function aggroLanded(bot, job, now)
    local last = bot:GetLastAttackTime()
    if job.aggroOrderedAt == nil or last < job.aggroOrderedAt then
        return now
    end
    local flight = 0
    local speed = bot:GetAttackProjectileSpeed()
    if job.aggroTarget ~= nil and bot:GetAttackRange() > RANGED_ATTACK_RANGE and speed > 0 then
        flight = math.min(
            GetUnitToUnitDistance(bot, job.aggroTarget),
            bot:GetAttackRange()
        ) / speed
    end
    return math.min(
        now,
        now - (GameTime() - last)
    ) + flight
end
local function usableItem(bot, name)
    local slot = bot:FindItemSlot(name)
    if slot == nil or slot < 0 or slot > 5 then
        return nil
    end
    local item = bot:GetItemInSlot(slot)
    return item ~= nil and item ~= nil and item:IsFullyCastable() and item or nil
end
local function tangoTree(bot)
    for ____, tree in ipairs(bot:GetNearbyTrees(settings().Radii.TangoTree) or ({})) do
        local loc = GetTreeLocation(tree)
        if IsLocationVisible(loc) and IsLocationPassable(loc) then
            return tree
        end
    end
    return nil
end
--- A support about to take a camp's hits eats a tango and drinks a clarity on the way, with time to spare: upstream
-- waits for 200 HP or 60% mana lost, and from the camp coming into sight the cast hold keeps its item code off.
-- True while the job leaves the frame to the use.
local function supply(bot, job, now)
    local slack = job.aggroAt - now - travelTo(bot, job.stand)
    if job.supplyUntil ~= nil then
        local taken = bot:HasModifier(job.supplyModifier or "")
        if now < job.supplyUntil and slack > 0 and not taken then
            return true
        end
        noteSupply(bot, job, job.supplyItem, taken and "taken" or "missed")
        job.supplyUntil = nil
    end
    local cfg = settings()
    if job.tangoUsed == true and job.clarityUsed == true then
        return false
    end
    local needClarity = job.clarityUsed ~= true and bot:GetMaxMana() - bot:GetMana() >= cfg.Thresholds.ClarityMinLost and not bot:HasModifier("modifier_clarity_potion")
    local needTango = job.tangoUsed ~= true and bot:GetMaxHealth() - bot:GetHealth() >= cfg.Thresholds.TangoMinLost and not bot:HasModifier("modifier_tango_heal") and not bot:HasModifier("modifier_flask_healing")
    if not needClarity and not needTango then
        return false
    end
    local blocked = slack < cfg.Timing.SupplySlack and "slack" or (enemyHeroNear(bot) and "enemy" or nil)
    if needClarity then
        local clarity = usableItem(bot, "item_clarity")
        if blocked ~= nil or clarity == nil then
            noteSupply(
                bot,
                job,
                "clarity",
                "skip",
                blocked or "no-item"
            )
        else
            job.clarityUsed = true
            awaitSupply(
                bot,
                job,
                now,
                "clarity",
                "modifier_clarity_potion"
            )
            bot:Action_UseAbilityOnEntity(clarity, bot)
            return true
        end
    end
    if needTango then
        local tango = usableItem(bot, "item_tango_single") or usableItem(bot, "item_tango")
        local ____temp_45
        if tango ~= nil and blocked == nil then
            ____temp_45 = tangoTree(bot)
        else
            ____temp_45 = nil
        end
        local tree = ____temp_45
        if tango == nil or tree == nil then
            noteSupply(
                bot,
                job,
                "tango",
                "skip",
                blocked or (tango == nil and "no-item" or "no-tree")
            )
        else
            job.tangoUsed = true
            awaitSupply(
                bot,
                job,
                now,
                "tango",
                "modifier_tango_heal"
            )
            bot:Action_UseAbilityOnTree(tango, tree)
            return true
        end
    end
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
        if job.kind ~= "stack" and supply(bot, job, now) then
            return true
        end
        local creep = campNeutral(bot, job)
        if creep ~= nil and now >= job.aggroAt - aggroLead(bot, creep) then
            return orderAggro(bot, job, creep)
        end
        if creep == nil and now >= job.aggroAt - cfg.Timing.StandApproachLead and arrived(bot, job.stand) and approachCamp(job) then
            return moveTo(bot, job.stand)
        end
        local there = arrived(bot, job.stand)
        if now < job.aggroAt then
            if not there then
                return moveTo(bot, job.stand)
            end
            job.phase = "wait"
            Intent.Hold(bot, "lane:job_wait")
            return true
        end
        if not there then
            if now >= job.aggroAt + cfg.Timing.JobStartLate then
                abort(bot, job, "late", true)
                return false
            end
            return moveTo(bot, job.stand)
        end
        job.phase = "aggro"
    end
    if job.phase == "aggro" then
        if job.aggroTarget == nil then
            local creep = campNeutral(bot, job)
            if creep ~= nil then
                return orderAggro(bot, job, creep)
            end
            if arrived(bot, job.stand) and approachCamp(job) then
                return moveTo(bot, job.stand)
            end
            if now >= job.aggroAt + cfg.Timing.NoCampAfter then
                if arrived(bot, job.stand) then
                    Stacking.ClearStack(job.activeCamp)
                    abort(bot, job, "mistake:no-camp")
                    return false
                end
                if now >= job.aggroAt + cfg.Timing.JobStartLate then
                    abort(bot, job, "late", true)
                    return false
                end
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
            Intent.Hold(bot, "lane:job_aggro")
            return true
        end
        if job.stage == 1 and job.chain == nil then
            job.actualAggro = aggroLanded(bot, job, now)
        end
        job.aggroTarget = nil
        if job.chain ~= nil then
            job.activeCamp = job.campIdx
            job.stand = job.chain.stand
            job.aggroAt = job.chain.aggroAt
            job.chain = nil
            job.aggroOrderedAt = nil
            job.phase = "travel"
            HDebug.Log(
                "lane",
                (((("job-second pid=" .. tostring(bot:GetPlayerID())) .. " camp=") .. tostring(job.campIdx)) .. " aggroAt=") .. string.format("%.1f", job.aggroAt)
            )
            return step(bot, job)
        end
        if job.kind == "stack" then
            noteStackAggro(bot, job, now)
            job.phase = "exit"
        else
            job.phase = "lead"
        end
    end
    if job.phase == "exit" then
        if now >= (job.exitUntil or now) then
            endStack(bot, job)
            return false
        end
        while job.waypoint < #job.path and arrived(bot, job.path[job.waypoint + 1]) do
            job.waypoint = job.waypoint + 1
        end
        if job.waypoint < #job.path then
            return moveTo(bot, job.path[job.waypoint + 1])
        end
        Intent.Hold(bot, "lane:stack_exit")
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
        if now - (job.watchFrom or now) >= cfg.Timing.WatchSec and (job.waveAt == nil or now >= job.waveAt + cfg.PullTiming.WatchAfterWave) then
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
        Intent.Hold(bot, "lane:job_watch")
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
    job.acted = true
    job.lastThinkAt = DotaTime()
    job.unthought = false
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
        abort(
            bot,
            job,
            "mode-end",
            false,
            modeEndFields(bot, job),
            true
        )
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
