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

local function __TS__ArrayPush(self, ...)
    local items = {...}
    local len = #self
    for i = 1, #items do
        len = len + 1
        self[len] = items[i]
    end
    return len
end
-- End of Lua Library inline imports
local ____exports = {}
local merge, dist2D, speedOf, currentMinute, clamp, learnPace, aliveUnits, anyNear, campNeutrals, allyInBox, claimedByAlly, markCleared, knownEmpty, mateJobCamp, campOpen, stackRoll, stackPlan, fmt, log, adopt, releaseClaims, toReturn, nextOrReturn, pickTarget, step, cached, trips, cleared, stackRolls, paceFactor, gateLogged, MAX_STEPS
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
function merge(defaults, overrides)
    if overrides == nil or overrides == nil or type(overrides) ~= "table" then
        return defaults
    end
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = v
    end
    for k, v in pairs(overrides) do
        local d = defaults[k]
        local ____k_1 = k
        local ____temp_0
        if d ~= nil and type(d) == "table" and type(v) == "table" then
            ____temp_0 = merge(d, v)
        else
            ____temp_0 = v
        end
        result[____k_1] = ____temp_0
    end
    return result
end
function ____exports.Settings()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().FarmPattern
        )
    end
    return cached
end
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function speedOf(bot)
    return math.max(
        bot:GetCurrentMovementSpeed(),
        100
    )
end
function currentMinute(now)
    return math.floor(now / 60)
end
function clamp(v, range)
    return math.max(
        range[1],
        math.min(range[2], v)
    )
end
--- The prior clear time for a camp type at `level` with `stacks` extra sets of neutrals.
function ____exports.PriorClearTime(____type, level, stacks)
    local s = ____exports.Settings()
    local scale = clamp(
        s.RefLevel / math.max(level, 1),
        s.LevelScale
    )
    return (s.ClearSec[____type] or s.ClearSec.medium) * scale * (1 + s.StackedClearMul * stacks)
end
function ____exports.ClearTime(bot, ____type, stacks)
    return ____exports.PriorClearTime(
        ____type,
        bot:GetLevel(),
        stacks
    ) * (paceFactor[bot:GetPlayerID()] or 1)
end
function learnPace(bot, measured, prior)
    if prior <= 0 then
        return
    end
    local s = ____exports.Settings()
    local pid = bot:GetPlayerID()
    local old = paceFactor[pid] or 1
    paceFactor[pid] = clamp(old + s.Learn * (measured / prior - old), s.LearnClamp)
end
function aliveUnits(list)
    local out = {}
    for ____, u in ipairs(GetUnitList(list) or ({})) do
        if u ~= nil and u ~= nil and u:IsAlive() then
            out[#out + 1] = u
        end
    end
    return out
end
function anyNear(units, loc, radius)
    for ____, u in ipairs(units) do
        if dist2D(
            u:GetLocation(),
            loc
        ) <= radius then
            return true
        end
    end
    return false
end
function campNeutrals(bot, center)
    local s = ____exports.Settings()
    local out = {}
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(s.NeutralScan, false) or ({})) do
        if n ~= nil and n ~= nil and n:IsAlive() and n:CanBeSeen() and dist2D(
            n:GetLocation(),
            center
        ) <= s.CampRadius then
            out[#out + 1] = n
        end
    end
    return out
end
function allyInBox(bot, idx, allies)
    local pid = bot:GetPlayerID()
    for ____, a in ipairs(allies) do
        if a:GetPlayerID() ~= pid and Camps.InBox(
            idx,
            a:GetLocation(),
            300
        ) then
            return true
        end
    end
    return false
end
function claimedByAlly(bot, idx)
    local pid = bot:GetPlayerID()
    local team = bot:GetTeam()
    for other, trip in pairs(trips) do
        if other ~= pid and trip.team == team and trip.campIdx == idx and trip.phase ~= "return" then
            return true
        end
    end
    return false
end
function markCleared(team, idx, now)
    cleared[team] = cleared[team] or ({})
    cleared[team][idx] = currentMinute(now)
end
function knownEmpty(bot, team, idx, center, now)
    local ____opt_2 = cleared[team]
    if (____opt_2 and ____opt_2[idx]) == currentMinute(now) then
        return true
    end
    return dist2D(
        bot:GetLocation(),
        center
    ) <= ____exports.Settings().EmptySight and IsLocationVisible(center) and #campNeutrals(bot, center) == 0
end
function mateJobCamp(bot, idx)
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false
    end
    local pull = false
    for ____, c in ipairs(Camps.PullCampsFor(s.team, s.lane)) do
        if c.campIdx == idx then
            pull = true
        end
    end
    if not pull then
        return false
    end
    local pid = bot:GetPlayerID()
    for ____, h in ipairs(s.allies) do
        if h.assigned and h.pid ~= pid and h.alive and CampJobs.Active(h.unit) then
            return true
        end
    end
    return false
end
function campOpen(bot, team, idx, center, now, sight)
    if knownEmpty(
        bot,
        team,
        idx,
        center,
        now
    ) then
        return false
    end
    if mateJobCamp(bot, idx) then
        return false
    end
    if allyInBox(bot, idx, sight.allies) or claimedByAlly(bot, idx) or Stacking.ReservedByAlly(
        idx,
        bot:GetPlayerID()
    ) then
        return false
    end
    if Orders.AvoidsLocation(bot, center) then
        return false
    end
    return not anyNear(
        sight.enemies,
        center,
        ____exports.Settings().EnemyRadius
    )
end
function stackRoll(bot, minute)
    local pid = bot:GetPlayerID()
    local r = stackRolls[pid]
    if r ~= nil and r.minute == minute then
        return r.ok
    end
    local ok = LaneConfig.Roll(LaneConfig.Curve(
        "StackAttempt",
        LaneConfig.SkillOf(bot)
    ))
    stackRolls[pid] = {minute = minute, ok = ok}
    return ok
end
function stackPlan(bot, spawner, from, front, now, deadline, value)
    if not LaneConfig.IsActive() or not LaneConfig.IsOn("Stack") then
        return nil
    end
    local s = ____exports.Settings()
    local lane = LaneConfig.Settings()
    if Stacking.StackCount(spawner.idx) >= lane.Thresholds.StackMaxCampCount then
        return nil
    end
    local data = Camps.ByIdx(spawner.idx, spawner.team)
    if data == nil or data.stack == nil then
        return nil
    end
    local speed = speedOf(bot)
    local period = lane.Timing.PullPeriod
    local aggroAt = CampJobs.NextAggroTime(
        now,
        {Stacking.AggroSec(data)},
        period
    )
    local wait = aggroAt - (now + dist2D(
        from,
        Stacking.StandPoint(spawner, data)
    ) / speed)
    if wait < s.StackMinWait or wait > s.StackWaitMax then
        return nil
    end
    local minute = math.floor(aggroAt / period)
    local done = (minute + 1) * period + lane.Timing.StackExitUntil + dist2D(
        Camps.BoxCenter(spawner),
        front
    ) / speed
    if done > deadline + s.StackLateExtra then
        return nil
    end
    if not stackRoll(bot, minute) then
        return nil
    end
    return {
        campIdx = spawner.idx,
        type = spawner.type,
        stack = true,
        score = value * s.StackValue / (done - now),
        leaveBy = done,
        estimate = 0,
        minute = minute
    }
end
--- The best camp of the bot's own jungle within MaxCampDist of `front` that it can clear from `from` and still be back
-- at `front` by `deadline`, or stack on the way; by value per second of trip.
function ____exports.PlanCamp(bot, from, front, now, deadline, diag)
    local s = ____exports.Settings()
    local team = bot:GetTeam()
    local speed = speedOf(bot)
    local level = bot:GetLevel()
    local sight = {
        enemies = aliveUnits(UnitType.EnemyHeroes),
        allies = aliveUnits(UnitType.AlliedHeroes)
    }
    local best
    for ____, spawner in ipairs(Camps.Spawners()) do
        do
            local __continue96
            repeat
                if spawner.team ~= team then
                    __continue96 = true
                    break
                end
                if level < (s.CampMinLevel[spawner.type] or 1) then
                    __continue96 = true
                    break
                end
                local center = Camps.BoxCenter(spawner)
                if dist2D(center, front) > s.MaxCampDist or not campOpen(
                    bot,
                    team,
                    spawner.idx,
                    center,
                    now,
                    sight
                ) then
                    __continue96 = true
                    break
                end
                if diag ~= nil then
                    diag.open = diag.open + 1
                end
                local stacks = Stacking.StackCount(spawner.idx)
                local value = (s.Value[spawner.type] or 1) * (1 + stacks)
                local back = dist2D(center, front) / speed
                local clearTime = ____exports.ClearTime(bot, spawner.type, stacks)
                local total = dist2D(from, center) / speed + clearTime + back
                if diag ~= nil and (diag.bestTotal == nil or total < diag.bestTotal) then
                    diag.bestTotal = total
                end
                if now + total <= deadline then
                    local score = value / total
                    if best == nil or score > best.score then
                        best = {
                            campIdx = spawner.idx,
                            type = spawner.type,
                            stack = false,
                            score = score,
                            leaveBy = deadline - back,
                            estimate = clearTime
                        }
                    end
                end
                local stack = stackPlan(
                    bot,
                    spawner,
                    from,
                    front,
                    now,
                    deadline,
                    value
                )
                if stack ~= nil and (best == nil or stack.score > best.score) then
                    best = stack
                end
                __continue96 = true
            until true
            if not __continue96 then
                break
            end
        end
    end
    return best
end
function fmt(v)
    return v == nil and "-" or string.format("%.1f", v)
end
function log(bot, event, trip, extra)
    if extra == nil then
        extra = {}
    end
    if not Telemetry.IsEnabled() and not HDebug.IsEnabled() then
        return
    end
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"camp", trip.campIdx},
        {"type", trip.type},
        {"phase", trip.phase},
        {
            "waveAt",
            fmt(trip.waveAt)
        },
        {
            "leaveBy",
            fmt(trip.leaveBy)
        },
        unpack(extra)
    }
    Telemetry.Event(event, fields)
    local parts = {}
    for ____, ____value in ipairs(fields) do
        local k = ____value[1]
        local v = ____value[2]
        parts[#parts + 1] = (k .. "=") .. tostring(v)
    end
    HDebug.Log(
        "farm",
        (event .. " ") .. table.concat(parts, " ")
    )
end
function adopt(bot, trip, plan)
    if plan.stack and not CampJobs.Start(bot, {kind = "stack", campIdx = plan.campIdx, minute = plan.minute, core = true}) then
        return false
    end
    trip.campIdx = plan.campIdx
    trip.type = plan.type
    trip.leaveBy = plan.leaveBy
    trip.phase = plan.stack and "stack" or "go"
    local ____trip_5 = trip
    local ____plan_stack_4
    if plan.stack then
        ____plan_stack_4 = nil
    else
        ____plan_stack_4 = ____exports.PriorClearTime(
            plan.type,
            bot:GetLevel(),
            Stacking.StackCount(plan.campIdx)
        )
    end
    ____trip_5.estimate = ____plan_stack_4
    trip.farmFrom = nil
    trip.target = nil
    trip.camps = trip.camps + 1
    return true
end
function releaseClaims(bot)
    Intent.ReleaseSource(bot, "farm:hold")
    Intent.ReleaseSource(bot, "farm:focus")
end
function toReturn(bot, trip, now, why)
    if why == "late" and trip.phase == "farm" and trip.farmFrom ~= nil then
        local s = ____exports.Settings()
        local pid = bot:GetPlayerID()
        paceFactor[pid] = clamp((paceFactor[pid] or 1) * s.LateGrowth, s.LearnClamp)
    end
    trip.phase = "return"
    trip.returnFrom = now
    trip.target = nil
    releaseClaims(bot)
    log(bot, "farm_trip_return", trip, {{"why", why}})
end
function nextOrReturn(bot, trip, now, why, depth)
    local front = GetLaneFrontLocation(trip.team, trip.lane, 0)
    local plan = ____exports.PlanCamp(
        bot,
        bot:GetLocation(),
        front,
        now,
        trip.deadline
    )
    if plan ~= nil and adopt(bot, trip, plan) then
        log(bot, "farm_trip_next", trip, {{"after", why}})
        return step(bot, trip, now, depth + 1)
    end
    toReturn(bot, trip, now, why)
    return step(bot, trip, now, depth + 1)
end
function pickTarget(trip, neutrals)
    local current = trip.target
    if current ~= nil and not current:IsNull() then
        for ____, n in ipairs(neutrals) do
            if n == current then
                return current
            end
        end
    end
    local best = neutrals[1]
    for ____, u in ipairs(neutrals) do
        if u:GetHealth() < best:GetHealth() then
            best = u
        end
    end
    trip.target = best
    return best
end
function step(bot, trip, now, depth)
    if depth == nil then
        depth = 0
    end
    if depth > MAX_STEPS then
        return false
    end
    if trip.phase == "stack" then
        if CampJobs.Active(bot) then
            CampJobs.Think(bot)
            return true
        end
        return nextOrReturn(
            bot,
            trip,
            now,
            "stacked",
            depth
        )
    end
    if trip.phase == "return" then
        bot:Action_MoveToLocation(GetLaneFrontLocation(trip.team, trip.lane, 0))
        return true
    end
    local spawner = Camps.SpawnerByIdx(trip.campIdx)
    if spawner == nil then
        toReturn(bot, trip, now, "no-camp")
        return step(bot, trip, now, depth + 1)
    end
    if now >= trip.leaveBy then
        toReturn(bot, trip, now, "late")
        return step(bot, trip, now, depth + 1)
    end
    local center = Camps.BoxCenter(spawner)
    local neutrals = campNeutrals(bot, center)
    local there = GetUnitToLocationDistance(bot, center) <= ____exports.Settings().Arrive
    if trip.phase == "go" then
        if not there and #neutrals == 0 then
            bot:Action_MoveToLocation(center)
            return true
        end
        trip.phase = "farm"
    end
    if #neutrals == 0 then
        if not there then
            bot:Action_MoveToLocation(center)
            return true
        end
        if trip.farmFrom ~= nil and trip.estimate ~= nil then
            learnPace(bot, now - trip.farmFrom, trip.estimate)
        end
        markCleared(trip.team, trip.campIdx, now)
        Stacking.ClearStack(trip.campIdx)
        return nextOrReturn(
            bot,
            trip,
            now,
            trip.farmFrom ~= nil and "cleared" or "empty",
            depth
        )
    end
    local target = pickTarget(trip, neutrals)
    if trip.farmFrom == nil and GetUnitToUnitDistance(bot, target) <= bot:GetAttackRange() + 100 then
        trip.farmFrom = now
    end
    bot:Action_AttackUnit(target, true)
    return true
end
____exports.DEFAULTS = {
    Enable = true,
    StartTime = {[1] = 300, [2] = 360, [3] = 330},
    MinLevel = {[1] = 3, [2] = 3, [3] = 3},
    CampMinLevel = {small = 3, medium = 4, large = 6, ancient = 12},
    EndTime = 1200,
    Desire = 0.62,
    MidRuneGuard = 40,
    StartHP = 0.65,
    AbortHP = 0.3,
    HoldRetreatHP = 0.4,
    HoldHeroHit = 2,
    FrontRadius = 1800,
    WaveClearRadius = 1000,
    EnemyRadius = 1400,
    StartEnemyRadius = 2000,
    EnemyCooldown = 10,
    MaxCampDist = 3800,
    LateTolerance = 5,
    StackLateExtra = 8,
    WavePeriod = 30,
    ClearSec = {small = 7, medium = 10, large = 13, ancient = 18},
    RefLevel = 8,
    LevelScale = {0.6, 1.6},
    StackedClearMul = 0.8,
    Learn = 0.3,
    LearnClamp = {0.4, 2.5},
    LateGrowth = 1.15,
    Value = {small = 1, medium = 1.4, large = 1.9, ancient = 2.6},
    StackValue = 0.8,
    StackMinWait = 0.5,
    StackWaitMax = 10,
    Arrive = 300,
    ReturnArrive = 900,
    CampRadius = 700,
    EmptySight = 1200,
    NeutralScan = 1600,
    PlanEvery = 0.5,
    PreemptAfter = 2,
    GateLogEvery = 15,
    ReturnMax = 25,
    FocusMargin = 0.05
}
local executor
function ____exports.SetExecutor(e)
    executor = e
end
trips = {}
local nextPlanAt = {}
local enemyEndAt = {}
cleared = {}
stackRolls = {}
paceFactor = {}
function ____exports.ResetCache()
    cached = nil
    trips = {}
    nextPlanAt = {}
    enemyEndAt = {}
    cleared = {}
    stackRolls = {}
    paceFactor = {}
    gateLogged = {}
end
function ____exports.IsActive()
    return Config.IsFeatureEnabled("FarmPattern")
end
local function hpOf(bot)
    local max = bot:GetMaxHealth()
    return max > 0 and bot:GetHealth() / max or 0
end
--- When the next enemy wave reaches `front` on `lane`: waves leave the enemy spawner every WavePeriod from 0:00.
function ____exports.NextWaveAt(team, lane, front, now)
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    local path = PullTiming.LanePath(enemy, lane)
    if path == nil or #path < 2 then
        return nil
    end
    local along = PullTiming.Along(path, front)
    local travel = along / LaneConfig.Settings().PullTiming.CreepSpeed
    local period = ____exports.Settings().WavePeriod
    local k = math.max(
        0,
        math.ceil((now - travel) / period)
    )
    return k * period + travel
end
function ____exports.PaceFactor(bot)
    return paceFactor[bot:GetPlayerID()] or 1
end
local function eligiblePosition(bot)
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 1 and pos <= 3 and pos or nil
end
--- Meepo's clones and Arc's tempest double share the hero's player ID, and intent leaves them out: so do trips.
local function sharesPlayerID(bot)
    return bot:GetUnitName() == "npc_dota_hero_meepo" or bot:HasModifier("modifier_arc_warden_tempest_double")
end
local IDLE_MODES = {[BotMode.Laning] = true, [BotMode.Farm] = true, [BotMode.None] = true}
local FOCUS_MODES = {BotMode.Ward, BotMode.SideShop, BotMode.SecretShop}
--- StartGate's lasting part (the unit, a core position, its level): why this bot is not a farmer, or undefined.
function ____exports.Eligible(bot)
    if not bot:IsHero() or bot:IsIllusion() or sharesPlayerID(bot) or string.sub(
        bot:GetUnitName(),
        1,
        14
    ) ~= "npc_dota_hero_" then
        return "unit"
    end
    local pos = eligiblePosition(bot)
    if pos == nil then
        return "not-core"
    end
    if bot:GetLevel() < (____exports.Settings().MinLevel[pos] or ____exports.Settings().MinLevel[1]) then
        return "level"
    end
    return nil
end
--- Why the bot may not start a trip now, or undefined.
function ____exports.StartGate(bot, now)
    local s = ____exports.Settings()
    if not bot:IsHero() or bot:IsIllusion() or sharesPlayerID(bot) or string.sub(
        bot:GetUnitName(),
        1,
        14
    ) ~= "npc_dota_hero_" then
        return "unit"
    end
    local pos = eligiblePosition(bot)
    if pos == nil then
        return "not-core"
    end
    if now < (s.StartTime[pos] or s.StartTime[1]) or now >= s.EndTime then
        return "time"
    end
    if bot:GetLevel() < (s.MinLevel[pos] or s.MinLevel[1]) then
        return "level"
    end
    if hpOf(bot) < s.StartHP then
        return "low-hp"
    end
    if IDLE_MODES[bot:GetActiveMode()] ~= true then
        return "busy-mode"
    end
    if Orders.GetFor(bot) ~= nil then
        return "has-order"
    end
    if LaneConfig.IsActive() and CampJobs.Active(bot) then
        return "camp-job"
    end
    if LaneConfig.IsActive() and CampJobs.Covering(bot) then
        return "covering"
    end
    if LaneHooks.EnemiesMissing(
        bot,
        LaneConfig.Settings().Thresholds.JobMissingFresh
    ) > 0 then
        return "enemy-missing"
    end
    if pos == 2 and Runes.NextSpawn("power", now) - now < s.MidRuneGuard then
        return "rune"
    end
    local retreat = Intent.Resolved(bot, BotMode.Retreat)
    if retreat ~= nil and retreat >= s.Desire then
        return "retreat"
    end
    return nil
end
local function enemyCreepsNear(bot, radius)
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(radius, true) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() then
            return true
        end
    end
    return false
end
--- The wave at the front is still alive: a bot standing back from it (ranged, zoned) must not count it as dead.
local function waveAlive(front, radius)
    for ____, c in ipairs(GetUnitList(UnitType.EnemyCreeps) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and LaneState.IsLaneCreepName(c:GetUnitName()) and dist2D(
            c:GetLocation(),
            front
        ) <= radius then
            return true
        end
    end
    return false
end
--- The lane whose wave the trip is timed against: the assigned lane while laning, then the nearest lane front.
local function homeLane(bot)
    if LaneConfig.InLaningPhase() then
        return bot:GetAssignedLane()
    end
    local best = Lane.Mid
    local bestDist = math.huge
    for ____, lane in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        local d = GetUnitToLocationDistance(
            bot,
            GetLaneFrontLocation(
                bot:GetTeam(),
                lane,
                0
            )
        )
        if d < bestDist then
            best = lane
            bestDist = d
        end
    end
    return best
end
--- Starts a trip, or returns why not (with the numbers behind the reason) for farm_gate.
local function schedule(bot, now)
    local s = ____exports.Settings()
    local gate = ____exports.StartGate(bot, now)
    if gate ~= nil then
        return gate, {
            {
                "lvl",
                bot:GetLevel()
            },
            {
                "hp",
                fmt(hpOf(bot))
            },
            {
                "mode",
                HDebug.ModeName(bot:GetActiveMode())
            }
        }
    end
    local team = bot:GetTeam()
    local lane = homeLane(bot)
    local front = GetLaneFrontLocation(team, lane, 0)
    local fromFront = GetUnitToLocationDistance(bot, front)
    if fromFront > s.FrontRadius then
        return "far", {
            {"lane", lane},
            {
                "dist",
                math.floor(fromFront)
            }
        }
    end
    if enemyCreepsNear(bot, s.WaveClearRadius) or waveAlive(front, s.WaveClearRadius) then
        return "wave", {{"lane", lane}}
    end
    if anyNear(
        aliveUnits(UnitType.EnemyHeroes),
        bot:GetLocation(),
        s.StartEnemyRadius
    ) then
        return "enemy", {{"lane", lane}}
    end
    local since = now - (enemyEndAt[bot:GetPlayerID()] or -math.huge)
    if since < s.EnemyCooldown then
        return "enemy-cooldown", {
            {"lane", lane},
            {
                "left",
                fmt(s.EnemyCooldown - since)
            }
        }
    end
    local waveAt = ____exports.NextWaveAt(team, lane, front, now)
    if waveAt == nil then
        return "no-path", {{"lane", lane}}
    end
    local deadline = waveAt + s.LateTolerance
    local diag = {open = 0}
    local plan = ____exports.PlanCamp(
        bot,
        bot:GetLocation(),
        front,
        now,
        deadline,
        diag
    )
    if plan == nil then
        return diag.open == 0 and "no-camp" or "no-fit", {
            {"lane", lane},
            {
                "lvl",
                bot:GetLevel()
            },
            {
                "window",
                fmt(deadline - now)
            },
            {
                "best",
                fmt(diag.bestTotal)
            },
            {"open", diag.open},
            {
                "pace",
                string.format(
                    "%.2f",
                    ____exports.PaceFactor(bot)
                )
            }
        }
    end
    local trip = {
        team = team,
        lane = lane,
        campIdx = plan.campIdx,
        type = plan.type,
        phase = "go",
        waveAt = waveAt,
        deadline = deadline,
        leaveBy = plan.leaveBy,
        startedAt = now,
        camps = 0
    }
    if not adopt(bot, trip, plan) then
        return "stack-start", {{"camp", plan.campIdx}}
    end
    if executor ~= nil and executor.Owns(bot) then
        trip.sdk = true
    end
    trips[bot:GetPlayerID()] = trip
    log(
        bot,
        "farm_trip_start",
        trip,
        {
            {"lane", lane},
            {
                "pace",
                string.format(
                    "%.2f",
                    ____exports.PaceFactor(bot)
                )
            }
        }
    )
    return nil, {}
end
gateLogged = {}
--- One farm_gate line per reason change (and every GateLogEvery while it holds), so a game shows why cores stayed in lane.
local function noteGate(bot, why, fields, now)
    if not Telemetry.IsEnabled() and not HDebug.IsEnabled() then
        return
    end
    if why == "not-core" or why == "unit" then
        return
    end
    local pid = bot:GetPlayerID()
    local last = gateLogged[pid]
    if last ~= nil and last.why == why and now - last.at < ____exports.Settings().GateLogEvery then
        return
    end
    gateLogged[pid] = {why = why, at = now}
    Telemetry.Event(
        "farm_gate",
        {
            {"pid", pid},
            {"why", why},
            unpack(fields)
        }
    )
    HDebug.Log(
        "farm",
        (("gate pid=" .. tostring(pid)) .. " why=") .. why
    )
end
local function ____end(bot, trip, why)
    __TS__Delete(
        trips,
        bot:GetPlayerID()
    )
    if why == "enemy" then
        enemyEndAt[bot:GetPlayerID()] = DotaTime()
    end
    releaseClaims(bot)
    local extra = {
        {"why", why},
        {"camps", trip.camps},
        {
            "secs",
            fmt(DotaTime() - trip.startedAt)
        }
    }
    if trip.sdk ~= nil then
        __TS__ArrayPush(extra, {"sdk", trip.sdkFrames or 0}, {"legacy", trip.legacyFrames or 0})
    end
    if why == "preempted" then
        local to = bot:GetActiveMode()
        extra[#extra + 1] = {
            "to",
            HDebug.ModeName(to)
        }
        if Intent.IsActive() then
            extra[#extra + 1] = {
                "toBy",
                Intent.Explain(bot, to)
            }
        end
    end
    log(bot, "farm_trip_end", trip, extra)
end
--- Enemy heroes near the bot for longer than its reaction time (perception has already delayed when they show up).
local function threatened(bot, trip, now)
    if trip.phase == "return" or not anyNear(
        aliveUnits(UnitType.EnemyHeroes),
        bot:GetLocation(),
        ____exports.Settings().EnemyRadius
    ) then
        trip.enemySince = nil
        return false
    end
    trip.enemySince = trip.enemySince or now
    return now - trip.enemySince >= Profile.Get(bot).reactBase
end
--- Why a live trip must end now, or undefined.
local function stopReason(bot, trip, now)
    local s = ____exports.Settings()
    if not bot:IsAlive() then
        return "dead"
    end
    if hpOf(bot) < s.AbortHP then
        return "low-hp"
    end
    if Orders.GetFor(bot) ~= nil then
        return "order"
    end
    if threatened(bot, trip, now) then
        return "enemy"
    end
    local retreat = Intent.Resolved(bot, BotMode.Retreat)
    if retreat ~= nil and retreat > s.Desire then
        return "retreat"
    end
    if now - (trip.lastThinkAt or trip.startedAt) > s.PreemptAfter and bot:GetActiveMode() ~= BotMode.Farm then
        return "preempted"
    end
    if trip.phase == "return" then
        if GetUnitToLocationDistance(
            bot,
            GetLaneFrontLocation(trip.team, trip.lane, 0)
        ) <= s.ReturnArrive then
            return "back"
        end
        if enemyCreepsNear(bot, s.WaveClearRadius) then
            return "wave"
        end
        if now - (trip.returnFrom or now) > s.ReturnMax then
            return "return-timeout"
        end
    end
    return nil
end
--- Camp jobs' retreatThreat: a hero hitting or targeting the bot, or a tower, lifts the hold; neutrals do not.
local function retreatThreat(bot)
    local s = ____exports.Settings()
    if hpOf(bot) < s.HoldRetreatHP or bot:WasRecentlyDamagedByAnyHero(s.HoldHeroHit) or bot:WasRecentlyDamagedByTower(s.HoldHeroHit) then
        return true
    end
    for ____, e in ipairs(aliveUnits(UnitType.EnemyHeroes)) do
        if e:GetAttackTarget() == bot then
            return true
        end
    end
    return false
end
--- Claims for a trip on its way to or in a camp: retreat held below it (so chasing neutrals do not send the core home)
-- and the errands capped below it. Posted every round from farm's GetDesire; both drop on the walk back.
local function postClaims(bot, trip)
    if trip.phase == "return" then
        return
    end
    local s = ____exports.Settings()
    local cap = s.Desire - s.FocusMargin
    if not retreatThreat(bot) then
        Intent.Claim(bot, {source = "farm:hold", tier = "CAMP_JOB", mode = BotMode.Retreat, cap = cap})
    else
        Intent.Release(bot, "farm:hold", BotMode.Retreat)
    end
    for ____, mode in ipairs(FOCUS_MODES) do
        Intent.Claim(bot, {source = "farm:focus", tier = "CAMP_JOB", mode = mode, cap = cap})
    end
end
--- mode_farm_generic GetDesire: the trip's desire, 0 when the bot is not on (and does not start) a trip.
function ____exports.Desire(bot)
    if not ____exports.IsActive() then
        return 0
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local trip = trips[pid]
    if trip ~= nil then
        local why = stopReason(bot, trip, now)
        if why ~= nil then
            ____end(bot, trip, why)
            return 0
        end
        postClaims(bot, trip)
        return ____exports.Settings().Desire
    end
    if not bot:IsAlive() or now < (nextPlanAt[pid] or -math.huge) then
        return 0
    end
    nextPlanAt[pid] = now + ____exports.Settings().PlanEvery
    local why, fields = schedule(bot, now)
    if why ~= nil then
        noteGate(bot, why, fields, now)
        return 0
    end
    gateLogged[pid] = nil
    postClaims(bot, trips[pid])
    return ____exports.Settings().Desire
end
MAX_STEPS = 4
local function overlay(bot, trip, now)
    HDebug.Text(
        bot,
        "farm",
        string.format(
            "trip %s camp=%d %s wave=%+.1f leave=%+.1f pace=%.2f",
            trip.phase,
            trip.campIdx,
            trip.type,
            trip.waveAt - now,
            trip.leaveBy - now,
            ____exports.PaceFactor(bot)
        )
    )
end
--- mode_farm_generic Think: true when the trip owns this frame.
function ____exports.Think(bot)
    if not ____exports.IsActive() then
        return false
    end
    local trip = trips[bot:GetPlayerID()]
    if trip == nil then
        return false
    end
    local now = DotaTime()
    trip.lastThinkAt = now
    overlay(bot, trip, now)
    if trip.sdk == true and executor ~= nil and executor.Step(bot) then
        trip.sdkFrames = (trip.sdkFrames or 0) + 1
        return true
    end
    if trip.sdk == true then
        trip.legacyFrames = (trip.legacyFrames or 0) + 1
    end
    return step(bot, trip, now)
end
--- A trip's next camp after `why` (cleared, empty, stacked), else the walk back; true when it chained a camp.
local function planNext(bot, trip, now, why)
    local plan = ____exports.PlanCamp(
        bot,
        bot:GetLocation(),
        GetLaneFrontLocation(trip.team, trip.lane, 0),
        now,
        trip.deadline
    )
    if plan ~= nil and adopt(bot, trip, plan) then
        log(bot, "farm_trip_next", trip, {{"after", why}})
        return true
    end
    toReturn(bot, trip, now, why)
    return false
end
--- What an SDK trip body (states/farm.ts) needs of the trip's planning and bookkeeping: everything but step().
____exports.Exec = {
    CampDone = function(bot, trip, fought)
        local now = DotaTime()
        if fought and trip.farmFrom ~= nil and trip.estimate ~= nil then
            learnPace(bot, now - trip.farmFrom, trip.estimate)
        end
        markCleared(trip.team, trip.campIdx, now)
        Stacking.ClearStack(trip.campIdx)
        return planNext(bot, trip, now, fought and "cleared" or "empty")
    end,
    Stacked = function(bot, trip) return planNext(
        bot,
        trip,
        DotaTime(),
        "stacked"
    ) end,
    ToReturn = function(bot, trip, why) return toReturn(
        bot,
        trip,
        DotaTime(),
        why
    ) end
}
--- Farm lost the round. The trip is kept: a blip (team_roam's neutral last hit) hands farm back within PreemptAfter,
-- and a real take-over ends it as "preempted" from Desire, where GetActiveMode already names the winner.
function ____exports.OnEnd(_bot)
end
--- mode_farm_generic: a run started, so the trip ends now.
function ____exports.Abort(bot, why)
    if not ____exports.IsActive() then
        return
    end
    local trip = trips[bot:GetPlayerID()]
    if trip ~= nil then
        ____end(bot, trip, why)
    end
end
function ____exports.Current(bot)
    return trips[bot:GetPlayerID()]
end
--- The live trip itself, for its SDK executor (states/farm.ts).
function ____exports.Live(bot)
    return trips[bot:GetPlayerID()]
end
return ____exports
