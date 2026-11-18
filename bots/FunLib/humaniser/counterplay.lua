--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local settings, dist2D, isLaner
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local ____aba_hero_roles_map = require(GetScriptDirectory().."/FunLib/aba_hero_roles_map")
local HeroRolesMap = ____aba_hero_roles_map.HeroRolesMap
function settings()
    return LaneConfig.Settings()
end
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function isLaner(e, s)
    local cfg = settings()
    if not e.visible and e.timeSinceSeen > cfg.Timing.ExposureSeen then
        return false
    end
    return dist2D(e.location, s.frontLoc) <= cfg.Radii.Exposure
end
local LANE_NAME = {[Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot"}
local observers = {}
--- Seconds each enemy hero was seen at our front, per "<team>:<lane>", and its hero name. J.GetPosition is no use for
-- enemies: enemy_role_estimation ranks only the enemies in sight, and reads 3 before it has run (console.9057240733:
-- 19 of 20 first reads were 3). Who lanes where, and what their hero is, is what a player reads instead.
local laneSeen = {}
local heroNames = {}
--- The lane support / mid last reported on lane_enemy_role, per "<team>:<lane>:<role>".
local rolesSaid = {}
local marked = {}
local teamSaid = {}
function ____exports.ResetCache()
    observers = {}
    laneSeen = {}
    heroNames = {}
    rolesSaid = {}
    marked = {}
    teamSaid = {}
end
local function on()
    return LaneConfig.IsOn("CounterPlay")
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
        st = {instances = {}, waveMax = 0, said = {}}
        observers[pid] = st
    end
    return st
end
function ____exports.EnemyPullSuspected(i)
    local cfg = settings()
    local e = i.enemySupport
    if e.visible then
        local near = cfg.Radii.PullerNear
        if dist2D(e.location, i.standLoc) > near and dist2D(e.location, i.campLoc) > near then
            return false
        end
    elseif e.timeSinceSeen <= cfg.Timing.CounterUnseen or dist2D(e.location, i.standLoc) > cfg.Radii.PullCampLastSeen then
        return false
    end
    local period = cfg.Timing.WaveCycle
    local sec = i.now % period
    for ____, s in ipairs(i.campPullSec) do
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
    if LaneState.LaneScore(i.enemyDesiredEq, -i.forecastEq, 0) > cfg.Planner.FullPullBelow then
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
local function visibleEnemy(enemies, pid)
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
    if sig.kind == "pull" then
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
        if not (canHit and stronger(bot)) and sig.campIdx ~= nil then
            mark(s.team, sig.campIdx, now)
        end
    elseif sig.kind == "mid_missing" then
        say(bot, st, "say_lane_ss_mid", instance)
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
    Telemetry.Event(
        "lane_signal",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", sig.kind},
            {"lane", sig.lane},
            {"camp", sig.campIdx or -1},
            {"enemy", sig.enemyPid or -1},
            {"noticed", signal.noticed},
            {"inferred", inferred}
        }
    )
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
        end
    end
end
--- Counts the seconds each visible enemy stands at our front; two observers in the same lane add the time once.
local function noteLaners(s, enemies, now)
    local key = (tostring(s.team) .. ":") .. tostring(s.lane)
    local seen = laneSeen[key]
    if seen == nil then
        seen = {}
        laneSeen[key] = seen
    end
    local gap = settings().Timing.LanerSeenGap
    for ____, e in ipairs(enemies) do
        do
            local __continue64
            repeat
                if not e.visible or e.unit == nil or dist2D(e.location, s.frontLoc) > settings().Radii.Exposure then
                    __continue64 = true
                    break
                end
                heroNames[e.pid] = e.unit:GetUnitName()
                local r = seen[e.pid]
                if r == nil then
                    seen[e.pid] = {secs = 0, lastAt = now}
                else
                    if now - r.lastAt <= gap then
                        r.secs = r.secs + (now - r.lastAt)
                    end
                    r.lastAt = now
                end
                __continue64 = true
            until true
            if not __continue64 then
                break
            end
        end
    end
end
--- This lane's enemy laners, most seen first: those seen at our front for Timing.LanerSeenMin or more.
local function laneMembers(s)
    local seen = laneSeen[(tostring(s.team) .. ":") .. tostring(s.lane)]
    if seen == nil then
        return {}
    end
    local min = settings().Timing.LanerSeenMin
    local members = {}
    for pid, r in pairs(seen) do
        if r.secs >= min then
            members[#members + 1] = pid
        end
    end
    __TS__ArraySort(
        members,
        function(____, a, b) return seen[a].secs ~= seen[b].secs and seen[b].secs - seen[a].secs or a - b end
    )
    return members
end
local function supportScore(pid)
    local roles = HeroRolesMap[heroNames[pid]]
    return roles ~= nil and roles.support - roles.carry or 0
end
--- The lane's enemy support: of two or more laners, the most support hero (HeroRolesMap support minus carry, ties to
-- the less seen); none in a solo lane. Mid: its most seen laner. Reported on lane_enemy_role when it changes.
local function laneRoleOf(s, enemies, role)
    local members = laneMembers(s)
    local pid
    if role == "mid" then
        pid = members[1]
    elseif #members >= 2 then
        for ____, m in ipairs(members) do
            if pid == nil or supportScore(m) >= supportScore(pid) then
                pid = m
            end
        end
    end
    if pid == nil then
        return nil
    end
    local key = (((tostring(s.team) .. ":") .. tostring(s.lane)) .. ":") .. role
    if rolesSaid[key] ~= pid then
        rolesSaid[key] = pid
        Telemetry.Event(
            "lane_enemy_role",
            {
                {"team", s.team},
                {"lane", s.lane},
                {"role", role},
                {"enemy", pid},
                {"hero", heroNames[pid]},
                {
                    "members",
                    table.concat(members, ",")
                }
            }
        )
    end
    for ____, e in ipairs(enemies) do
        if e.pid == pid then
            return e
        end
    end
    return nil
end
local function suspectedCamp(camps, support, now)
    for ____, camp in ipairs(camps) do
        do
            local __continue88
            repeat
                local spawner = Camps.SpawnerByIdx(camp.campIdx)
                if spawner == nil or camp.pull == nil then
                    __continue88 = true
                    break
                end
                local input = {
                    now = now,
                    enemySupport = support,
                    campLoc = Camps.BoxCenter(spawner),
                    standLoc = CampJobs.PullerStand(camp) or Camps.BoxCenter(spawner),
                    campPullSec = PullTiming.ForCamp(camp).seconds
                }
                if ____exports.EnemyPullSuspected(input) then
                    return camp.campIdx
                end
                __continue88 = true
            until true
            if not __continue88 then
                break
            end
        end
    end
    return nil
end
local function expectedAggro(s, camp, support, now)
    return ____exports.EnemyPullExpected({
        now = now,
        forecastEq = s.forecastEq,
        enemyDesiredEq = LaneState.DesiredEq(
            LaneState.LaneKindOf(
                enemyTeamOf(s.team),
                s.lane
            ),
            false
        ),
        pullSec = PullTiming.ForCamp(camp).seconds,
        supportInLane = support ~= nil and isLaner(support, s)
    })
end
--- Gate and skill are checked before observe so no notice roll is spent below the gate.
local function pullExpectedSignal(bot, st, s, enemies, camp, support, now)
    if not LaneConfig.IsOn("PreContest") or LaneConfig.SkillOf(bot) < settings().Gates.PreContest or camp.pull == nil then
        return
    end
    local aggroAt = expectedAggro(s, camp, support, now)
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
    local support = laneRoleOf(s, enemies, "support")
    local ____temp_2
    if support ~= nil then
        ____temp_2 = suspectedCamp(camps, support, now)
    else
        ____temp_2 = nil
    end
    local suspected = ____temp_2
    if support ~= nil and suspected ~= nil then
        local source = support.visible and "seen" or "lastseen"
        local sig = {
            kind = "pull",
            lane = s.lane,
            at = now,
            campIdx = suspected,
            enemyPid = support.pid,
            source = source
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
    local anomaly = ____exports.WaveAnomaly(
        s.cycleSec,
        s.enemyArrivalSec,
        st.waveMax,
        settings().Thresholds.WaveCreeps
    )
    if anomaly == nil then
        return
    end
    if support ~= nil and support.visible and isLaner(support, s) then
        return
    end
    local sig = {
        kind = "pull",
        lane = s.lane,
        at = now,
        campIdx = camps[1].campIdx,
        enemyPid = support and support.pid,
        source = "wave"
    }
    observe(
        bot,
        st,
        (("pull:" .. tostring(camps[1].campIdx)) .. ":") .. tostring(cycle),
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
    local enemyMid = laneRoleOf(s, enemies, "mid")
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
    local minute = math.floor(now / GameRules.NEUTRAL_EVERY)
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
                local __continue114
                repeat
                    if n == nil or n == nil or not n:IsAlive() or not n:CanBeSeen() then
                        __continue114 = true
                        break
                    end
                    local spawner = Camps.NearestSpawner(n:GetLocation())
                    if spawner == nil or spawner.team == s.team then
                        __continue114 = true
                        break
                    end
                    if not Camps.InBox(
                        spawner.idx,
                        n:GetLocation(),
                        cfg.Radii.NeutralOutsideMargin
                    ) then
                        outside[spawner.idx] = true
                    end
                    __continue114 = true
                until true
                if not __continue114 then
                    break
                end
            end
        end
    end
    for ____, spawner in ipairs(Camps.Spawners()) do
        do
            local __continue119
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
                    __continue119 = true
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
                __continue119 = true
            until true
            if not __continue119 then
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
    noteLaners(s, enemies, now)
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
--- A pull_expected is first seen about a cycle before its aggro, so it lives until that aggro rather than CounterSignalTTL.
local function live(st, now)
    local ttl = settings().Timing.CounterSignalTTL
    local result = {}
    for key, sig in pairs(st.instances) do
        do
            local __continue132
            repeat
                if not sig.noticed then
                    __continue132 = true
                    break
                end
                local ____temp_9
                if sig.kind == "pull_expected" and sig.aggroAt ~= nil then
                    ____temp_9 = now <= sig.aggroAt
                else
                    ____temp_9 = now - sig.at <= ttl
                end
                local alive = ____temp_9
                if alive then
                    result[#result + 1] = {key, sig}
                end
                __continue132 = true
            until true
            if not __continue132 then
                break
            end
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
local function hpOf(u)
    local max = u:GetMaxHealth()
    return max > 0 and u:GetHealth() / max or 0
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
            local __continue158
            repeat
                if not e.visible and e.timeSinceSeen > cfg.Timing.StackedCampSeen then
                    __continue158 = true
                    break
                end
                if dist2D(e.location, center) <= cfg.Radii.StackedCampSafe then
                    return false
                end
                __continue158 = true
            until true
            if not __continue158 then
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
            local __continue166
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
                    __continue166 = true
                    break
                end
                local spawner, d = Camps.NearestSpawner(loc)
                if spawner == nil or d > matchRadius or (marks[spawner.idx] or 0) <= now then
                    __continue166 = true
                    break
                end
                if spawner.team ~= team and not campSafe(
                    Camps.BoxCenter(spawner),
                    enemies
                ) then
                    __continue166 = true
                    break
                end
                local dist = GetUnitToLocationDistance(bot, loc)
                if dist < bestDist then
                    best = camp
                    bestDist = dist
                end
                __continue166 = true
            until true
            if not __continue166 then
                break
            end
        end
    end
    return best
end
function ____exports.RegisterProbes()
    LaneHooks.SetTechniqueOverride(techniqueOverride)
end
____exports.RegisterProbes()
return ____exports
