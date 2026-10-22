--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
end
-- End of Lua Library inline imports
local ____exports = {}
local settings, dist2D, visibleEnemy, isLaner, runStackAttack
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LanePlanner = require(GetScriptDirectory().."/FunLib/humaniser/lane_planner")
local LaneTech = require(GetScriptDirectory().."/FunLib/humaniser/lane_tech")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local Harass = require(GetScriptDirectory().."/FunLib/humaniser/harass")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
function settings()
    return LaneConfig.Settings()
end
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function visibleEnemy(enemies, pid)
    if pid == nil then
        return nil
    end
    for ____, e in ipairs(enemies) do
        if e.pid == pid and e.visible and e.unit ~= nil then
            return e
        end
    end
    return nil
end
function isLaner(e, s)
    local cfg = settings()
    if not e.visible and e.timeSinceSeen > cfg.Timing.ExposureSeen then
        return false
    end
    return dist2D(e.location, s.frontLoc) <= cfg.Radii.Exposure
end
function runStackAttack(bot, st, enemies, now)
    local sa = st.stackAttack
    if sa == nil then
        return false
    end
    local stacker = visibleEnemy(enemies, sa.pid)
    if now > sa["until"] or stacker == nil or stacker.unit == nil then
        st.stackAttack = nil
        return false
    end
    if sa.orderedAt == nil then
        bot:Action_AttackUnit(stacker.unit, true)
        sa.orderedAt = GameTime()
        return true
    end
    if bot:GetLastAttackTime() >= sa.orderedAt then
        st.stackAttack = nil
        return false
    end
    return true
end
local LANE_NAME = {[Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot"}
local WARDS = {item_ward_sentry = true, item_ward_observer = true, item_ward_dispenser = true}
local INVENTORY_SLOTS = 6
local observers = {}
local positions = {}
local marked = {}
local dropDenyUntil = {}
local teamSaid = {}
function ____exports.ResetCache()
    observers = {}
    positions = {}
    marked = {}
    dropDenyUntil = {}
    teamSaid = {}
end
local function on()
    return LaneConfig.IsOn("CounterPlay")
end
local function distToSegment(p, a, b)
    local dx = b.x - a.x
    local dy = b.y - a.y
    local len2 = dx * dx + dy * dy
    if len2 == 0 then
        return dist2D(p, a)
    end
    local t = math.max(
        0,
        math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2)
    )
    return dist2D(
        p,
        Vector(a.x + t * dx, a.y + t * dy, 0)
    )
end
local function circularGap(a, b, period)
    local d = math.abs(a - b) % period
    return math.min(d, period - d)
end
local function enemyTeamOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
local function cycleOf(time)
    return math.floor(time / settings().Timing.WaveCycle)
end
local function isSupport(bot)
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 4
end
local function stronger(bot)
    local fn = LaneConfig.Helpers().WeAreStronger
    return fn ~= nil and fn(
        bot,
        settings().Radii.Stronger
    )
end
local function stateOf(pid)
    local st = observers[pid]
    if st == nil then
        st = {instances = {}, responded = {}, waveMax = 0, said = {}}
        observers[pid] = st
    end
    return st
end
function ____exports.EnemyPullSuspected(i)
    local cfg = settings()
    local e = i.enemySupport
    if e.visible then
        return dist2D(e.location, i.campLoc) <= cfg.Radii.EnemyNearCamp
    end
    if e.timeSinceSeen <= cfg.Timing.CounterUnseen or dist2D(e.location, i.campLoc) > cfg.Radii.PullCampLastSeen then
        return false
    end
    local period = cfg.Timing.WaveCycle
    local sec = i.now % period
    local ____array_0 = __TS__SparseArrayNew(unpack(i.campPullSec))
    __TS__SparseArrayPush(
        ____array_0,
        unpack(i.campHalfSec or ({}))
    )
    for ____, s in ipairs({__TS__SparseArraySpread(____array_0)}) do
        if circularGap(sec, s % period, period) <= cfg.Timing.CounterPullWindow then
            return true
        end
    end
    return false
end
--- `visibleEnemyCreeps` is the most enemy creeps seen at the front so far this cycle: a wave already fighting
-- loses creeps, so the current count would read a normal wave as thin. Thin is judged once the wave has had
-- CounterWaveLate seconds to arrive in full.
function ____exports.WaveAnomaly(cycleSec, expectedArrival, visibleEnemyCreeps, typicalSize)
    if expectedArrival == nil then
        return nil
    end
    local cfg = settings()
    local settled = expectedArrival + cfg.Timing.CounterWaveLate
    if visibleEnemyCreeps == 0 then
        return cycleSec > settled and "late" or nil
    end
    if cycleSec >= settled and visibleEnemyCreeps <= typicalSize - cfg.Thresholds.ThinWaveMargin then
        return "thin"
    end
    return nil
end
function ____exports.FreezeSuspected(eqHistory, enemyDeniesPerCycle)
    local cfg = settings()
    local n = #eqHistory
    local m = #enemyDeniesPerCycle
    if n < 2 or m < 2 then
        return false
    end
    do
        local k = 1
        while k <= 2 do
            if eqHistory[n - k + 1] < cfg.Thresholds.FreezeSuspectEq or enemyDeniesPerCycle[m - k + 1] < cfg.Infer.FreezeDenies then
                return false
            end
            k = k + 1
        end
    end
    return true
end
--- The next aggro time at which the enemy support will want to pull, or undefined when it will not.
function ____exports.EnemyPullExpected(i)
    if not i.supportInLane or #i.pullSec == 0 then
        return nil
    end
    local cfg = settings()
    if LaneState.LaneScore(i.enemyDesiredEq, -i.forecastEq, 0) > cfg.Planner.SmallDriftBelow then
        return nil
    end
    local aggroAt = CampJobs.NextAggroTime(i.now, i.pullSec, cfg.Timing.PullPeriod)
    return CampJobs.CampsUp(aggroAt) and aggroAt or nil
end
function ____exports.StackSuspected(secOfMinute, enemyNearCampVisible, neutralOutsideBoxVisible)
    local t = settings().Timing
    if enemyNearCampVisible and secOfMinute >= t.StackWatchFrom and secOfMinute <= t.StackWatchTo then
        return true
    end
    return neutralOutsideBoxVisible and secOfMinute >= 0 and secOfMinute <= t.StackOutsideUntil
end
local function say(bot, st, key, instance)
    if not LaneConfig.IsOn("Telegraph") or not Difficulty.IsAllyOfHuman(bot) then
        return
    end
    if teamSaid[instance] == true then
        return
    end
    local cooldown = settings().Timing.CounterTelegraphCooldown
    local last = st.said[key]
    if last ~= nil and GameTime() - last < cooldown then
        return
    end
    if Orders.Say(bot, key, cooldown) then
        st.said[key] = GameTime()
        teamSaid[instance] = true
    end
end
local function mark(team, campIdx, now)
    local m = marked[team]
    if m == nil then
        m = {}
        marked[team] = m
    end
    m[campIdx] = now + settings().Timing.MarkedStackFor
end
--- Answers that need no unit action happen at notice time, so they also work for bots outside laning Think.
local function onNotice(bot, st, key, sig, s, enemies, inferred)
    local cfg = settings()
    local now = DotaTime()
    local instance = (((tostring(s.team) .. ":") .. tostring(s.lane)) .. ":") .. key
    HDebug.Log(
        "lane",
        (((((((("counter pid=" .. tostring(bot:GetPlayerID())) .. " noticed=") .. sig.kind) .. " lane=") .. tostring(sig.lane)) .. " camp=") .. tostring(sig.campIdx or "-")) .. " enemy=") .. tostring(sig.enemyPid or "-")
    )
    if sig.kind == "pull_expected" then
        return
    end
    if sig.kind == "pull" or sig.kind == "half_pull" then
        say(bot, st, inferred and "say_lane_their_sup_missing" or "say_lane_they_pull_" .. LANE_NAME[sig.lane], instance)
    elseif sig.kind == "freeze" then
        say(bot, st, "say_lane_they_freeze", instance)
        if not isSupport(bot) then
            return
        end
        st.counterUntil = (cycleOf(now) + 2) * cfg.Timing.WaveCycle
    elseif sig.kind == "stack" then
        local stacker = visibleEnemy(enemies, sig.enemyPid)
        local canHit = LaneConfig.InLaningPhase() and stacker ~= nil and GetUnitToLocationDistance(bot, stacker.location) <= cfg.Radii.Stronger
        if canHit and stacker ~= nil and stronger(bot) then
            st.stackAttack = {pid = stacker.pid, ["until"] = now + cfg.Timing.PunishFor}
        elseif sig.campIdx ~= nil then
            mark(s.team, sig.campIdx, now)
        end
    elseif sig.kind == "mid_missing" then
        say(bot, st, "say_lane_ss_mid", instance)
        dropDenyUntil[s.team] = now + cfg.Timing.DropRangedDenyFor
    elseif sig.kind == "rune_shove" then
        local next = LaneConfig.Helpers().NextPowerRuneTime
        local rune = next ~= nil and next() or now
        if stronger(bot) then
            st.runeContestUntil = rune + cfg.Timing.RuneContestAfter
        else
            st.counterUntil = rune
        end
    end
end
--- The notice roll is the only draw for a new instance (PF10 draw order).
local function observe(bot, st, key, sig, s, enemies, inferred)
    if inferred == nil then
        inferred = false
    end
    if st.instances[key] ~= nil then
        return
    end
    local signal = __TS__ObjectAssign(
        {},
        sig,
        {noticed = LaneConfig.Roll(LaneConfig.Curve(
            "CounterNotice",
            LaneConfig.SkillOf(bot)
        ))}
    )
    st.instances[key] = signal
    if signal.noticed then
        onNotice(
            bot,
            st,
            key,
            signal,
            s,
            enemies,
            inferred
        )
    end
end
local function prune(st, now)
    local forget = settings().Timing.CounterForgetAfter
    for key, sig in pairs(st.instances) do
        if now - sig.at > forget and key ~= st.freezeKey then
            __TS__Delete(st.instances, key)
            __TS__Delete(st.responded, key)
        end
    end
end
local function notePositions(enemies)
    for ____, e in ipairs(enemies) do
        do
            local __continue65
            repeat
                if not e.visible or e.unit == nil or positions[e.pid] ~= nil then
                    __continue65 = true
                    break
                end
                local pos = e.position or LaneConfig.PositionOf(e.unit)
                if pos ~= nil then
                    positions[e.pid] = pos
                end
                __continue65 = true
            until true
            if not __continue65 then
                break
            end
        end
    end
end
--- Known enemy of that position whose (last-seen) location is nearest the lane; never-seen enemies are unknown.
local function enemyAt(enemies, lane, wanted)
    local best
    local bestDist = math.huge
    for ____, e in ipairs(enemies) do
        do
            local __continue70
            repeat
                local pos = positions[e.pid]
                if pos == nil or not wanted(pos) then
                    __continue70 = true
                    break
                end
                local d = GetAmountAlongLane(lane, e.location).distance
                if d < bestDist then
                    best = e
                    bestDist = d
                end
                __continue70 = true
            until true
            if not __continue70 then
                break
            end
        end
    end
    return best
end
local function suspectedCamp(camps, support, now)
    for ____, camp in ipairs(camps) do
        do
            local __continue75
            repeat
                local spawner = Camps.SpawnerByIdx(camp.campIdx)
                if spawner == nil or camp.pull == nil then
                    __continue75 = true
                    break
                end
                local input = {
                    now = now,
                    enemySupport = support,
                    campLoc = Camps.BoxCenter(spawner),
                    campPullSec = PullTiming.ForCamp(camp, false).seconds,
                    campHalfSec = PullTiming.ForCamp(camp, true).seconds
                }
                if ____exports.EnemyPullSuspected(input) then
                    return camp.campIdx
                end
                __continue75 = true
            until true
            if not __continue75 then
                break
            end
        end
    end
    return nil
end
--- Gate and skill are checked before observe so no notice roll is spent below the gate.
local function pullExpectedSignal(bot, st, s, enemies, camp, support, now)
    if not LaneConfig.IsOn("PreContest") or LaneConfig.SkillOf(bot) < settings().Gates.PreContest or camp.pull == nil then
        return
    end
    local aggroAt = ____exports.EnemyPullExpected({
        now = now,
        forecastEq = s.forecastEq,
        enemyDesiredEq = LaneState.DesiredEq(
            LaneState.LaneKindOf(
                enemyTeamOf(s.team),
                s.lane
            ),
            false
        ),
        pullSec = PullTiming.ForCamp(camp, false).seconds,
        supportInLane = support ~= nil and isLaner(support, s)
    })
    if aggroAt == nil then
        return
    end
    local key = (("pexp:" .. tostring(camp.campIdx)) .. ":") .. tostring(math.floor(aggroAt / settings().Timing.WaveCycle))
    observe(
        bot,
        st,
        key,
        {
            kind = "pull_expected",
            lane = s.lane,
            at = now,
            campIdx = camp.campIdx,
            enemyPid = support and support.pid,
            aggroAt = aggroAt
        },
        s,
        enemies
    )
end
local function pullSignals(bot, st, s, enemies, now)
    local camps = Camps.PullCampsFor(
        enemyTeamOf(s.team),
        s.lane
    )
    if #camps == 0 then
        return
    end
    local cycle = cycleOf(now)
    local support = enemyAt(
        enemies,
        s.lane,
        function(pos) return pos >= 4 end
    )
    local ____temp_3
    if support ~= nil then
        ____temp_3 = suspectedCamp(camps, support, now)
    else
        ____temp_3 = nil
    end
    local suspected = ____temp_3
    if support ~= nil and suspected ~= nil then
        local sig = {
            kind = "pull",
            lane = s.lane,
            at = now,
            campIdx = suspected,
            enemyPid = support.pid
        }
        observe(
            bot,
            st,
            (("pull:" .. tostring(suspected)) .. ":") .. tostring(cycle),
            sig,
            s,
            enemies,
            not support.visible
        )
    end
    pullExpectedSignal(
        bot,
        st,
        s,
        enemies,
        camps[1],
        support,
        now
    )
    if st.waveCycle ~= cycle then
        st.waveCycle = cycle
        st.waveMax = 0
    end
    st.waveMax = math.max(st.waveMax, s.enemy.count)
    if #s.enemyWaveSizes == 0 then
        return
    end
    local typical = 0
    for ____, n in ipairs(s.enemyWaveSizes) do
        typical = math.max(typical, n)
    end
    local anomaly = ____exports.WaveAnomaly(s.cycleSec, s.enemyArrivalSec, st.waveMax, typical)
    if anomaly == nil then
        return
    end
    local kind = anomaly == "late" and "pull" or "half_pull"
    local sig = {
        kind = kind,
        lane = s.lane,
        at = now,
        campIdx = camps[1].campIdx,
        enemyPid = support and support.pid
    }
    observe(
        bot,
        st,
        (((kind .. ":") .. tostring(camps[1].campIdx)) .. ":") .. tostring(cycle),
        sig,
        s,
        enemies
    )
end
local function freezeSignal(bot, st, s, enemies, now)
    if not ____exports.FreezeSuspected(s.eqHistory, s.enemyDeniesPerCycle) then
        st.freezeKey = nil
        return
    end
    if st.freezeKey == nil then
        st.freezeKey = "freeze:" .. tostring(cycleOf(now))
    end
    observe(
        bot,
        st,
        st.freezeKey,
        {kind = "freeze", lane = s.lane, at = now},
        s,
        enemies
    )
end
local function midSignals(bot, st, s, enemies, now)
    if s.lane ~= Lane.Mid then
        return
    end
    local cfg = settings()
    local shoveEq = cfg.Thresholds.MidMissingEq
    local enemyMid = enemyAt(
        enemies,
        s.lane,
        function(pos) return pos == 2 end
    )
    local last = s.eqHistory[#s.eqHistory]
    if enemyMid ~= nil and not enemyMid.visible and enemyMid.timeSinceSeen > cfg.Timing.CounterUnseen and last ~= nil and last <= shoveEq then
        observe(
            bot,
            st,
            "mid_missing:" .. tostring(cycleOf(now)),
            {kind = "mid_missing", lane = s.lane, at = now, enemyPid = enemyMid.pid},
            s,
            enemies
        )
    end
    local next = LaneConfig.Helpers().NextPowerRuneTime
    if next == nil or s.eqPos > shoveEq then
        return
    end
    local rune = next()
    local left = rune - now
    if left <= 0 or left > cfg.Timing.MidRuneShoveLookahead then
        return
    end
    observe(
        bot,
        st,
        "rune_shove:" .. tostring(math.floor(rune)),
        {kind = "rune_shove", lane = s.lane, at = now, enemyPid = enemyMid and enemyMid.pid},
        s,
        enemies
    )
end
local function stackSignals(bot, st, s, enemies, now)
    local cfg = settings()
    local minute = math.floor(now / 60)
    local sec = now - minute * 60
    local watching = sec >= cfg.Timing.StackWatchFrom and sec <= cfg.Timing.StackWatchTo
    local after = sec <= cfg.Timing.StackOutsideUntil
    if not watching and not after then
        return
    end
    local stackMinute = watching and minute or minute - 1
    local outside = {}
    if after then
        for ____, n in ipairs(bot:GetNearbyNeutralCreeps(cfg.Radii.CounterNeutralScan, false) or ({})) do
            do
                local __continue103
                repeat
                    if n == nil or n == nil or not n:IsAlive() or not n:CanBeSeen() then
                        __continue103 = true
                        break
                    end
                    local spawner = Camps.NearestSpawner(n:GetLocation())
                    if spawner == nil or spawner.team == s.team then
                        __continue103 = true
                        break
                    end
                    if not Camps.InBox(
                        spawner.idx,
                        n:GetLocation(),
                        cfg.Radii.NeutralOutsideMargin
                    ) then
                        outside[spawner.idx] = true
                    end
                    __continue103 = true
                until true
                if not __continue103 then
                    break
                end
            end
        end
    end
    for ____, spawner in ipairs(Camps.Spawners()) do
        do
            local __continue108
            repeat
                local center = Camps.BoxCenter(spawner)
                local near
                if watching then
                    for ____, e in ipairs(enemies) do
                        if e.visible and dist2D(e.location, center) <= cfg.Radii.EnemyNearCamp then
                            near = e
                            break
                        end
                    end
                end
                if not ____exports.StackSuspected(sec, near ~= nil, outside[spawner.idx] == true) then
                    __continue108 = true
                    break
                end
                local sig = {
                    kind = "stack",
                    lane = s.lane,
                    at = now,
                    campIdx = spawner.idx,
                    enemyPid = near and near.pid
                }
                observe(
                    bot,
                    st,
                    (("stack:" .. tostring(spawner.idx)) .. ":") .. tostring(stackMinute),
                    sig,
                    s,
                    enemies
                )
                __continue108 = true
            until true
            if not __continue108 then
                break
            end
        end
    end
end
--- Evaluates once per lane snapshot refresh; off, it returns before any engine call.
function ____exports.Tick(bot)
    if not on() then
        return
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        return
    end
    local st = stateOf(bot:GetPlayerID())
    if st.lastEval == s.time then
        return
    end
    st.lastEval = s.time
    local now = DotaTime()
    prune(st, now)
    local enemies = LaneState.Enemies(bot, s.lane)
    notePositions(enemies)
    if LaneConfig.InLaningPhase() then
        pullSignals(
            bot,
            st,
            s,
            enemies,
            now
        )
        freezeSignal(
            bot,
            st,
            s,
            enemies,
            now
        )
        midSignals(
            bot,
            st,
            s,
            enemies,
            now
        )
    end
    stackSignals(
        bot,
        st,
        s,
        enemies,
        now
    )
end
local function live(st, now)
    local ttl = settings().Timing.CounterSignalTTL
    local result = {}
    for key, sig in pairs(st.instances) do
        if sig.noticed and now - sig.at <= ttl then
            result[#result + 1] = {key, sig}
        end
    end
    return result
end
function ____exports.Signals(bot)
    if not on() then
        return {}
    end
    local st = observers[bot:GetPlayerID()]
    if st == nil then
        return {}
    end
    return __TS__ArrayMap(
        live(
            st,
            DotaTime()
        ),
        function(____, ____bindingPattern0)
            local sig
            sig = ____bindingPattern0[2]
            return sig
        end
    )
end
local function towerProtects(bot, target)
    local range = settings().Thresholds.EnemyTowerRange
    for ____, t in ipairs(bot:GetNearbyTowers(1600, true) or ({})) do
        if t ~= nil and t ~= nil and dist2D(
            t:GetLocation(),
            target.location
        ) <= range then
            return true
        end
    end
    return false
end
local function hpOf(u)
    local max = u:GetMaxHealth()
    return max > 0 and u:GetHealth() / max or 0
end
--- The remaining visible enemy laner (not the puller) nearest our front.
local function remainingLaner(s, enemies, pullerPid)
    local best
    local bestDist = settings().Radii.LaneCreep
    for ____, e in ipairs(enemies) do
        do
            local __continue133
            repeat
                if not e.visible or e.unit == nil or e.pid == pullerPid then
                    __continue133 = true
                    break
                end
                local d = dist2D(e.location, s.frontLoc)
                if d <= bestDist then
                    best = e
                    bestDist = d
                end
                __continue133 = true
            until true
            if not __continue133 then
                break
            end
        end
    end
    return best
end
--- No enemy other than this lane's laners (the puller included) seen near the route recently. The laners are
-- already weighed by the partner-safety check the camp-job executor repeats every frame.
local function pathSafe(bot, s, to, enemies, pullerPid)
    local cfg = settings()
    local from = bot:GetLocation()
    for ____, e in ipairs(enemies) do
        do
            local __continue140
            repeat
                if e.pid == pullerPid or isLaner(e, s) or not e.visible and e.timeSinceSeen > cfg.Timing.PathSafeSeen then
                    __continue140 = true
                    break
                end
                if distToSegment(e.location, from, to) <= cfg.Radii.PathSafe then
                    return false
                end
                __continue140 = true
            until true
            if not __continue140 then
                break
            end
        end
    end
    return true
end
--- Punish the 2v1 while the enemy support is away; a reaction, so exempt from the one-technique lock.
local function runPunish(bot, st, enemies, now)
    local p = st.punish
    if p == nil then
        return false
    end
    local t = settings().Timing
    local target = visibleEnemy(enemies, p.pid)
    if now - p.startAt > t.PunishFor or target == nil or target.unit == nil then
        st.punish = nil
        return false
    end
    if Harass.TowerForbids(
        bot:GetLevel(),
        towerProtects(bot, target),
        hpOf(target.unit)
    ) then
        return false
    end
    if p.lastAt == nil or now - p.lastAt >= t.PunishGap then
        bot:Action_AttackUnit(target.unit, true)
        p.lastAt = now
    end
    return true
end
local function respondToPull(bot, st, s, enemies, now)
    for ____, ____value in ipairs(live(st, now)) do
        local key = ____value[1]
        local sig = ____value[2]
        do
            local __continue150
            repeat
                if sig.kind ~= "pull" and sig.kind ~= "half_pull" or st.responded[key] == true then
                    __continue150 = true
                    break
                end
                if stronger(bot) then
                    local laner = remainingLaner(s, enemies, sig.enemyPid)
                    if laner == nil then
                        __continue150 = true
                        break
                    end
                    st.responded[key] = true
                    st.punish = {pid = laner.pid, startAt = now}
                    return
                end
                if sig.campIdx == nil or LaneRoles.CampJobOwner(s) ~= bot:GetPlayerID() or LanePlanner.Committed(bot) ~= nil then
                    __continue150 = true
                    break
                end
                if CampJobs.Active(bot) then
                    __continue150 = true
                    break
                end
                local spawner = Camps.SpawnerByIdx(sig.campIdx)
                if spawner == nil or not pathSafe(
                    bot,
                    s,
                    Camps.BoxCenter(spawner),
                    enemies,
                    sig.enemyPid
                ) then
                    __continue150 = true
                    break
                end
                if CampJobs.Start(bot, {kind = "contest", campIdx = sig.campIdx, targetPid = sig.enemyPid}) then
                    st.responded[key] = true
                end
                return
            until true
            if not __continue150 then
                break
            end
        end
    end
end
local function findWard(bot)
    do
        local slot = 0
        while slot < INVENTORY_SLOTS do
            local item = bot:GetItemInSlot(slot)
            if item ~= nil and item ~= nil and WARDS[item:GetName()] == true then
                return item
            end
            slot = slot + 1
        end
    end
    return nil
end
--- Blocks the enemy pull camp's next spawn with a ward in its box at :50-:58.
-- TODO (in-game): confirm a sentry/observer ward in the box still blocks the neutral spawn on the current patch.
local function campBlock(bot, st, s, enemies, now)
    local cfg = settings()
    if not LaneConfig.IsOn("CampBlock") or not LaneConfig.InLaningPhase() or not isSupport(bot) then
        return false
    end
    if LaneConfig.SkillOf(bot) <= cfg.Gates.CampBlock then
        return false
    end
    local sec = now % 60
    if sec < cfg.Timing.CampBlockFrom or sec > cfg.Timing.CampBlockTo then
        return false
    end
    local ward = findWard(bot)
    if st.campBlockAt ~= nil and now - st.campBlockAt < cfg.Timing.CampBlockCooldown then
        return ward ~= nil and math.floor(st.campBlockAt / 60) == math.floor(now / 60)
    end
    if ward == nil then
        return false
    end
    local spawner
    for ____, camp in ipairs(Camps.PullCampsFor(
        enemyTeamOf(s.team),
        s.lane
    )) do
        local sp = Camps.SpawnerByIdx(camp.campIdx)
        if sp ~= nil and sp.team ~= s.team then
            spawner = sp
            break
        end
    end
    if spawner == nil then
        return false
    end
    local center = Camps.BoxCenter(spawner)
    local eta = GetUnitToLocationDistance(bot, center) / math.max(
        bot:GetCurrentMovementSpeed(),
        1
    )
    if eta > cfg.Timing.CampBlockTo - sec or not pathSafe(
        bot,
        s,
        center,
        enemies,
        nil
    ) then
        return false
    end
    bot:Action_UseAbilityOnLocation(ward, center)
    st.campBlockAt = now
    HDebug.Log(
        "lane",
        (("counter pid=" .. tostring(bot:GetPlayerID())) .. " camp-block camp=") .. tostring(spawner.idx)
    )
    return true
end
--- Laning Think, after the techniques; true when this frame's action is issued.
function ____exports.Think(bot, _enemies)
    local counter = on()
    if not counter and not LaneConfig.IsOn("CampBlock") then
        return false
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false
    end
    local st = stateOf(bot:GetPlayerID())
    local now = DotaTime()
    local enemies = LaneState.Enemies(bot, s.lane)
    if counter then
        if runStackAttack(bot, st, enemies, now) then
            return true
        end
        if runPunish(bot, st, enemies, now) then
            return true
        end
        respondToPull(
            bot,
            st,
            s,
            enemies,
            now
        )
        if runPunish(bot, st, enemies, now) then
            return true
        end
    end
    return campBlock(
        bot,
        st,
        s,
        enemies,
        now
    )
end
--- The live break-freeze / rune-shove answer: "shove", "zone", or undefined when none applies.
local function counterAnswer(bot)
    if not on() then
        return nil
    end
    local st = observers[bot:GetPlayerID()]
    if st == nil or st.counterUntil == nil then
        return nil
    end
    if DotaTime() >= st.counterUntil then
        st.counterUntil = nil
        return nil
    end
    local s = LaneState.ForBot(bot)
    if s == nil or LanePlan.View(bot, s).plan == "FREEZE" then
        return nil
    end
    local canShove = LaneConfig.Knows(
        "shove",
        LaneConfig.SkillOf(bot)
    ) and stronger(bot) and hpOf(bot) >= settings().Thresholds.ShoveMinHP
    return {answer = canShove and "shove" or "zone", s = s}
end
--- Zoning point while the counter answer is to zone; `loc` itself otherwise.
function ____exports.AdjustPosition(bot, loc)
    local c = counterAnswer(bot)
    if c == nil or c.answer ~= "zone" then
        return loc
    end
    return LaneTech.ZonePoint(bot, c.s) or loc
end
local function techniqueOverride(bot)
    local c = counterAnswer(bot)
    return c ~= nil and c.answer == "shove" and "shove" or nil
end
function ____exports.RuneContestDesire(bot)
    if not on() then
        return 0
    end
    local st = observers[bot:GetPlayerID()]
    if st == nil or st.runeContestUntil == nil then
        return 0
    end
    if DotaTime() >= st.runeContestUntil then
        st.runeContestUntil = nil
        return 0
    end
    return settings().Timing.RuneContestDesire
end
function ____exports.MarkedStacked(team)
    local result = {}
    if not on() then
        return result
    end
    local now = DotaTime()
    for idx, ____until in pairs(marked[team] or ({})) do
        if ____until > now then
            result[#result + 1] = idx
        end
    end
    __TS__ArraySort(
        result,
        function(____, a, b) return a - b end
    )
    return result
end
local function campSafe(center, enemies)
    local cfg = settings()
    for ____, e in ipairs(enemies) do
        do
            local __continue203
            repeat
                if not e.visible and e.timeSinceSeen > cfg.Timing.StackedCampSeen then
                    __continue203 = true
                    break
                end
                if dist2D(e.location, center) <= cfg.Radii.StackedCampSafe then
                    return false
                end
                __continue203 = true
            until true
            if not __continue203 then
                break
            end
        end
    end
    return true
end
--- mode_farm_generic: a core after laning heads for a camp an enemy was seen stacking; undefined keeps its own pick.
function ____exports.PreferStackedCamp(bot, camps)
    if not on() or LaneConfig.InLaningPhase() then
        return nil
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos < 1 or pos > 3 then
        return nil
    end
    local team = bot:GetTeam()
    local marks = marked[team]
    if marks == nil then
        return nil
    end
    local now = DotaTime()
    local enemies = LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )
    local matchRadius = settings().Camps.ReplayMatchRadius
    local best
    local bestDist = math.huge
    for ____, camp in ipairs(camps or ({})) do
        do
            local __continue211
            repeat
                local ____opt_result_14
                if camp ~= nil then
                    ____opt_result_14 = camp.cattr
                end
                local ____opt_result_15
                if ____opt_result_14 ~= nil then
                    ____opt_result_15 = ____opt_result_14.location
                end
                local loc = ____opt_result_15
                if loc == nil then
                    __continue211 = true
                    break
                end
                local spawner, d = Camps.NearestSpawner(loc)
                if spawner == nil or d > matchRadius or (marks[spawner.idx] or 0) <= now then
                    __continue211 = true
                    break
                end
                if spawner.team ~= team and not campSafe(
                    Camps.BoxCenter(spawner),
                    enemies
                ) then
                    __continue211 = true
                    break
                end
                local dist = GetUnitToLocationDistance(bot, loc)
                if dist < bestDist then
                    best = camp
                    bestDist = dist
                end
                __continue211 = true
            until true
            if not __continue211 then
                break
            end
        end
    end
    return best
end
function ____exports.DropRangedDeny(team)
    return on() and (dropDenyUntil[team] or 0) > DotaTime()
end
function ____exports.RegisterProbes()
    LaneHooks.SetTechniqueOverride(techniqueOverride)
end
____exports.RegisterProbes()
return ____exports
