--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    TriggerMinutes = {3, 5, 7},
    LookFrom = 15,
    Lead = 5,
    MinHpFraction = 0.5,
    EnemyRadius = 600,
    HitWithin = 3,
    Desire = 0.92,
    PreemptAfter = 1,
    WatchUntil = 5
}
local handled = {}
local gateWhy = {}
local running = {}
function ____exports.ResetCache()
    for k in pairs(handled) do
        __TS__Delete(handled, k)
    end
    for k in pairs(gateWhy) do
        __TS__Delete(gateWhy, k)
    end
    for k in pairs(running) do
        __TS__Delete(running, k)
    end
end
--- The switch is on and `bot` is OHA position 5.
function ____exports.Applies(bot)
    return Ours.On("StackExecute") and LaneConfig.PositionOf(bot) == 5
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
--- Own-side, not ancient, with a Valve stack window: the camps this job may stack.
function ____exports.Candidates(team)
    local out = {}
    for ____, s in ipairs(Camps.Spawners()) do
        do
            local __continue12
            repeat
                if s.team ~= team or s.type == "ancient" or (Stacking.Window(s.idx)) == nil then
                    __continue12 = true
                    break
                end
                local data = Camps.ByIdx(s.idx, team)
                if data ~= nil and data.stack ~= nil then
                    out[#out + 1] = data
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    return out
end
--- The candidate whose stand point is nearest `loc`, with that stand point.
function ____exports.Nearest(team, loc)
    local best
    local stand
    for ____, data in ipairs(____exports.Candidates(team)) do
        local sp = Camps.SpawnerByIdx(data.campIdx)
        local p = Stacking.StandPoint(sp, data)
        if stand == nil or dist(loc, p) < dist(loc, stand) then
            best = data
            stand = p
        end
    end
    return best, stand
end
--- Why the pos5 may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
-- hero just now, or fighting or retreating.
function ____exports.Gate(bot)
    if bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MinHpFraction then
        return "low-hp"
    end
    if #(bot:GetNearbyHeroes(____exports.SETTINGS.EnemyRadius, true, BotMode.None) or ({})) > 0 then
        return "enemy-near"
    end
    if bot:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.HitWithin) then
        return "hit"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    return nil
end
--- The stack verb's plan for `data` in `minute`: the hit lands on the camp's stack second of that minute.
function ____exports.Plan(bot, data, stand, minute, a)
    local sp = Camps.SpawnerByIdx(data.campIdx)
    local r = LaneConfig.Settings().Radii
    local t = LaneConfig.Settings().Timing
    local start = minute * 60
    local o = sp.location
    local d = math.max(1, ((stand.x - o.x) ^ 2 + (stand.y - o.y) ^ 2) ^ 0.5)
    local near = math.min(d, r.StandApproach)
    local approach = Vector(o.x + (stand.x - o.x) * near / d, o.y + (stand.y - o.y) * near / d, o.z)
    return {
        camp = {
            stand = stand,
            box = {min = sp.min, max = sp.max},
            origin = sp.location,
            margin = r.BoxMargin,
            search = r.NeutralSearch,
            confirmed = function() return CampJobs.Exec.NeutralTargets(bot) end,
            approach = approach
        },
        approachLead = t.StandApproachLead,
        aggroAt = start + Stacking.AggroSec(data),
        exitPath = data.stack.exitPath,
        exitUntil = start + 60 + t.StackExitUntil,
        arrive = r.JobArrive,
        onAggro = function(info)
            a.before = CampJobs.Exec.NeutralsInBox(bot, data.campIdx)
            a.aggro = info.confirmedAt - start
        end
    }
end
--- Seconds to walk from the bot to `p`.
local function travel(bot, p)
    return GetUnitToLocationDistance(bot, p) / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
local body = __TS__Generator(function(bot, plan, a, ctx)
    local r = __TS__DelegatedYield(Tasks.Jobs().stack(bot, plan, {label = ctx.label, urgent = ctx.urgent}))
    if not r.success then
        return r
    end
    ctx.label("watch")
    local sp = Camps.SpawnerByIdx(a.campIdx)
    local spawnCheck = a.minute * 60 + 60
    local outcomeAt = spawnCheck + LaneConfig.Settings().Timing.StackOutcomeAt
    local stopped = false
    while DotaTime() < spawnCheck + ____exports.SETTINGS.WatchUntil do
        if not bot:IsAlive() then
            return {success = false, reason = "dead"}
        end
        if CampJobs.Exec.BoxInSight(bot, a.campIdx) then
            if not stopped then
                bot:Action_MoveToLocation(bot:GetLocation())
            end
            stopped = true
            if DotaTime() >= outcomeAt then
                a.after = math.max(
                    a.after or 0,
                    CampJobs.Exec.NeutralsInBox(bot, a.campIdx)
                )
                if a.after > (a.before or 0) then
                    break
                end
            end
        else
            bot:Action_MoveToLocation(sp.location)
        end
        coroutine.yield()
    end
    return {success = true, reason = "ok"}
end)
local function log(bot, minute, fields)
    Telemetry.Event(
        "stack",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"min", minute},
            unpack(fields)
        }
    )
end
--- What the bot sees of the camp as the attempt ends, so a `no_target` reads as an empty camp or a wrong box from the log.
local function look(bot, a)
    local sp = Camps.SpawnerByIdx(a.campIdx)
    if sp == nil or not bot:IsAlive() then
        return
    end
    local near = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        LaneConfig.Settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() then
            near = near + 1
        end
    end
    a.near = near
    a.inbox = CampJobs.Exec.NeutralsInBox(bot, a.campIdx)
    a.dist = math.floor(GetUnitToLocationDistance(bot, sp.location))
    a.vis = IsLocationVisible(sp.location) and 1 or 0
end
local function finish(bot, a, result)
    running[bot:GetPlayerID()] = nil
    look(bot, a)
    local sp = Camps.SpawnerByIdx(a.campIdx)
    local landed = a.aggro ~= nil
    local res = not landed and "failed" or (a.after ~= nil and a.after > (a.before or 0) and "stacked" or "not_stacked")
    log(
        bot,
        a.minute,
        {
            {"res", res},
            {"why", result.success and "ok" or result.reason .. (result.message ~= nil and ":" .. result.message or "")},
            {"camp", a.campIdx},
            {"type", a.type},
            {
                "start",
                math.floor(a.startedAt * 10) / 10
            },
            {
                "aggro",
                a.aggro ~= nil and math.floor(a.aggro * 10) / 10 or "?"
            },
            {"before", a.before or "?"},
            {"after", a.after or "?"},
            {
                "away",
                math.floor((DotaTime() - a.startedAt) * 10) / 10
            },
            {
                "death",
                (result.reason == "dead" or not bot:IsAlive()) and 1 or 0
            },
            {
                "cx",
                sp ~= nil and math.floor(sp.location.x) or "?"
            },
            {
                "cy",
                sp ~= nil and math.floor(sp.location.y) or "?"
            },
            {"dist", a.dist or "?"},
            {"near", a.near or "?"},
            {"inbox", a.inbox or "?"},
            {"vis", a.vis or "?"}
        }
    )
end
--- mode_farm_generic GetDesire: the job's desire while it runs or as it starts, else 0 (OHA decides).
function ____exports.Desire(bot)
    if not ____exports.Applies(bot) then
        return 0
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return ____exports.SETTINGS.Desire
    end
    local now = DotaTime()
    handled[pid] = handled[pid] or ({})
    for ____, minute in ipairs(____exports.SETTINGS.TriggerMinutes) do
        do
            local __continue48
            repeat
                if handled[pid][minute] or now < minute * 60 + ____exports.SETTINGS.LookFrom or now >= minute * 60 + 60 then
                    __continue48 = true
                    break
                end
                local data, stand = ____exports.Nearest(
                    bot:GetTeam(),
                    bot:GetLocation()
                )
                local function skip(why)
                    handled[pid][minute] = true
                    gateWhy[pid] = nil
                    log(bot, minute, {{"res", "skip"}, {"why", why}})
                    return 0
                end
                if data == nil or stand == nil or Tasks.Jobs() == nil then
                    return skip("no-camp")
                end
                local aggroAt = minute * 60 + Stacking.AggroSec(data)
                local walk = travel(bot, stand)
                if now < aggroAt - walk - ____exports.SETTINGS.Lead then
                    return 0
                end
                if now > aggroAt - walk then
                    return skip(gateWhy[pid] or "late")
                end
                local why = ____exports.Gate(bot)
                if why ~= nil then
                    gateWhy[pid] = why
                    return 0
                end
                local a = {minute = minute, campIdx = data.campIdx, type = data.type, startedAt = now}
                local plan = ____exports.Plan(
                    bot,
                    data,
                    stand,
                    minute,
                    a
                )
                local ok = Tasks.Start(
                    bot,
                    {
                        name = "stack",
                        host = BotMode.Farm,
                        preemptAfter = ____exports.SETTINGS.PreemptAfter,
                        onEnd = function(result) return finish(bot, a, result) end
                    },
                    function(ctx) return body(bot, plan, a, ctx) end
                )
                if not ok then
                    return skip("refused")
                end
                handled[pid][minute] = true
                gateWhy[pid] = nil
                running[pid] = a
                return ____exports.SETTINGS.Desire
            until true
            if not __continue48 then
                break
            end
        end
    end
    return 0
end
--- mode_farm_generic Think: steps the job; false when none runs.
function ____exports.Think(bot)
    if running[bot:GetPlayerID()] == nil then
        return false
    end
    return Tasks.Step(bot, BotMode.Farm)
end
--- OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`.
function ____exports.Abort(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
return ____exports
