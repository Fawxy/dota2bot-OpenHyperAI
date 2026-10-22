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
-- End of Lua Library inline imports
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local PLAN_RANK = {"SHOVE", "FREEZE", "HOLD", "NEUTRAL"}
local NEUTRAL_SCORE = 0.25
function ____exports.PickCorePlan(i)
    local cfg = LaneConfig.Settings()
    local cautious = i.cautious == true
    if i.rotating and not cautious then
        return "SHOVE"
    end
    if i.skill >= cfg.Gates.Freeze and i.stronger and i.enemyLaners > 0 and i.eqPos <= cfg.Thresholds.FreezeCoreEqMax then
        return "FREEZE"
    end
    if not cautious and i.enemyLaners == 0 and i.laneScore < 0 then
        return "SHOVE"
    end
    return "HOLD"
end
function ____exports.NewTally()
    return {
        shoveHits = 0,
        lastHitTries = 0,
        denies = 0,
        aggroDraws = 0,
        stepBacks = 0,
        eqSum = 0,
        samples = 0
    }
end
local function sumTally(a, b)
    return {
        shoveHits = a.shoveHits + b.shoveHits,
        lastHitTries = a.lastHitTries + b.lastHitTries,
        denies = a.denies + b.denies,
        aggroDraws = a.aggroDraws + b.aggroDraws,
        stepBacks = a.stepBacks + b.stepBacks,
        eqSum = a.eqSum + b.eqSum,
        samples = a.samples + b.samples
    }
end
function ____exports.ClassifyTally(t)
    local infer = LaneConfig.Settings().Infer
    if t.shoveHits >= infer.ShoveHits then
        return "SHOVE"
    end
    if t.shoveHits == 0 and t.denies >= infer.FreezeDenies and t.samples > 0 and t.eqSum / t.samples <= infer.FreezeEqMax then
        return "FREEZE"
    end
    if t.aggroDraws + t.stepBacks >= infer.HoldSignals then
        return "HOLD"
    end
    return "NEUTRAL"
end
local function scoreTally(t)
    local infer = LaneConfig.Settings().Infer
    local meanEq = t.samples > 0 and t.eqSum / t.samples or 0
    local freeze = t.shoveHits == 0 and t.denies / infer.FreezeDenies * (meanEq <= infer.FreezeEqMax and 1 or 0.5) or 0
    return {SHOVE = t.shoveHits / infer.ShoveHits, FREEZE = freeze, HOLD = (t.aggroDraws + t.stepBacks) / infer.HoldSignals, NEUTRAL = NEUTRAL_SCORE}
end
--- The best-scoring plan of the tally other than `exclude` (ties go to the order of PLAN_RANK).
local function alternativePlan(t, exclude)
    local scores = scoreTally(t)
    local best
    for ____, plan in ipairs(PLAN_RANK) do
        do
            local __continue14
            repeat
                if plan == exclude then
                    __continue14 = true
                    break
                end
                if best == nil or scores[plan] > scores[best] then
                    best = plan
                end
                __continue14 = true
            until true
            if not __continue14 then
                break
            end
        end
    end
    return best
end
function ____exports.NewInference()
    return {current = "NEUTRAL", candidate = "NEUTRAL", candidateSince = 0, changedAt = -math.huge}
end
function ____exports.Step(inf, candidate, now)
    local timing = LaneConfig.Settings().Timing
    local candidateSince = candidate ~= inf.candidate and now or inf.candidateSince
    local current = inf.current
    local changedAt = inf.changedAt
    if candidate ~= current and now - candidateSince >= timing.PlanSustain and now - changedAt >= timing.PlanMinDwell then
        current = candidate
        changedAt = now
    end
    return {current = current, candidate = candidate, candidateSince = candidateSince, changedAt = changedAt}
end
local laneTracks = {}
local pickCache = {}
local misreads = {}
function ____exports.ResetCache()
    laneTracks = {}
    pickCache = {}
    misreads = {}
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function cycleIndex(time)
    return math.floor(time / LaneConfig.Settings().Timing.WaveCycle)
end
local function trackFor(s)
    local key = (tostring(s.team) .. ":") .. tostring(s.lane)
    local t = laneTracks[key]
    if t == nil then
        t = {
            cycle = cycleIndex(s.time),
            cur = ____exports.NewTally(),
            prev = ____exports.NewTally(),
            inf = ____exports.NewInference()
        }
        laneTracks[key] = t
    end
    return t
end
--- Ally hero assigned to the lane with the lowest core position (1-3), alive or not.
local function coreOf(s)
    local best
    for ____, h in ipairs(s.allies) do
        do
            local __continue27
            repeat
                if not h.assigned or h.position == nil or h.position < 1 or h.position > 3 then
                    __continue27 = true
                    break
                end
                if best == nil or h.position < best.position or h.position == best.position and h.pid < best.pid then
                    best = h
                end
                __continue27 = true
            until true
            if not __continue27 then
                break
            end
        end
    end
    return best
end
local function isLaneCreep(unit)
    return unit ~= nil and unit ~= nil and LaneState.IsLaneCreepName(unit:GetUnitName())
end
local function sampleHuman(t, s, h)
    local cfg = LaneConfig.Settings()
    local human = h.unit
    local target = human:GetAttackTarget()
    local targetIsCreep = isLaneCreep(target)
    if targetIsCreep then
        if target:GetTeam() ~= s.team then
            if target:GetHealth() <= human:GetAttackDamage() * cfg.Infer.ShoveHitDamageMult then
                t.lastHitTries = t.lastHitTries + 1
            else
                t.shoveHits = t.shoveHits + 1
            end
        else
            t.denies = t.denies + 1
        end
    end
    if s.lastAllyAggroAt[h.pid] == s.time and not targetIsCreep then
        t.aggroDraws = t.aggroDraws + 1
    end
    local here = GetAmountAlongLane(
        s.lane,
        human:GetLocation()
    ).amount
    local ahead = GetAmountAlongLane(
        s.lane,
        human:GetExtrapolatedLocation(cfg.Radii.ApproachExtrapolate)
    ).amount
    if Camps.ToTeamAmount(s.team, ahead) < Camps.ToTeamAmount(s.team, here) then
        local moved = dist2D(
            GetLocationAlongLane(s.lane, here),
            GetLocationAlongLane(s.lane, ahead)
        )
        if moved > cfg.Radii.StepBackEps then
            local near = 0
            local loc = human:GetLocation()
            for ____, c in ipairs(s.enemy.units) do
                if dist2D(
                    c:GetLocation(),
                    loc
                ) <= cfg.Radii.StepBackCreeps then
                    near = near + 1
                end
            end
            if near >= 1 then
                t.stepBacks = t.stepBacks + 1
            end
        end
    end
    t.eqSum = t.eqSum + s.eqPos
    t.samples = t.samples + 1
end
local function inWindow(cycleSec, sec)
    local cycle = LaneConfig.Settings().Timing.WaveCycle
    local d = math.abs(cycleSec - sec % cycle)
    return math.min(d, cycle - d) <= LaneConfig.Settings().Timing.HumanPullWindow
end
local function humanPulling(s, human)
    local radius = LaneConfig.Settings().Radii.HumanPullRadius
    local loc = human:GetLocation()
    for ____, job in ipairs(Camps.PullCampsFor(s.team, s.lane)) do
        do
            local __continue47
            repeat
                if job.pull == nil then
                    __continue47 = true
                    break
                end
                local spawner
                for ____, sp in ipairs(Camps.Spawners()) do
                    if sp.idx == job.campIdx then
                        spawner = sp
                    end
                end
                if spawner == nil or dist2D(
                    Camps.BoxCenter(spawner),
                    loc
                ) > radius then
                    __continue47 = true
                    break
                end
                local ____array_0 = __TS__SparseArrayNew(unpack(PullTiming.ForCamp(job, false).seconds))
                __TS__SparseArrayPush(
                    ____array_0,
                    unpack(PullTiming.ForCamp(job, true).seconds)
                )
                local seconds = {__TS__SparseArraySpread(____array_0)}
                for ____, sec in ipairs(seconds) do
                    if inWindow(s.cycleSec, sec) then
                        return true
                    end
                end
                __continue47 = true
            until true
            if not __continue47 then
                break
            end
        end
    end
    return false
end
function ____exports.ObserveSnapshot(s)
    if not LaneConfig.IsOn("Plan") then
        return
    end
    local track = trackFor(s)
    local idx = cycleIndex(s.time)
    if track.cycle ~= idx then
        track.prev = idx == track.cycle + 1 and track.cur or ____exports.NewTally()
        track.cur = ____exports.NewTally()
        track.cycle = idx
    end
    local core = coreOf(s)
    for ____, h in ipairs(s.allies) do
        do
            local __continue60
            repeat
                if h.isBot or not h.alive then
                    __continue60 = true
                    break
                end
                if humanPulling(s, h.unit) then
                    track.pullBlockedCycle = idx
                end
                if core ~= nil and h.pid == core.pid then
                    sampleHuman(track.cur, s, h)
                end
                __continue60 = true
            until true
            if not __continue60 then
                break
            end
        end
    end
    if core ~= nil and not core.isBot and core.alive then
        track.inf = ____exports.Step(
            track.inf,
            ____exports.ClassifyTally(sumTally(track.cur, track.prev)),
            s.time
        )
    end
end
--- Enemy heroes seen near the lane front within the exposure window.
function ____exports.EnemyLaners(bot, s)
    local cfg = LaneConfig.Settings()
    local n = 0
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        do
            local __continue67
            repeat
                if not e.visible and e.timeSinceSeen > cfg.Timing.ExposureSeen then
                    __continue67 = true
                    break
                end
                if dist2D(e.location, s.frontLoc) <= cfg.Radii.Exposure then
                    n = n + 1
                end
                __continue67 = true
            until true
            if not __continue67 then
                break
            end
        end
    end
    return n
end
local function pickFor(picker, s)
    local key = (tostring(picker:GetPlayerID()) .. ":") .. tostring(s.lane)
    local inputs = pickCache[key]
    if inputs == nil or inputs.time ~= s.time then
        local stronger = LaneConfig.Helpers().WeAreStronger
        inputs = {
            time = s.time,
            skill = LaneConfig.SkillOf(picker),
            laneScore = LaneState.ScoreFor(picker, s).laneScore,
            eqPos = s.eqPos,
            stronger = stronger ~= nil and stronger(
                picker,
                LaneConfig.Settings().Radii.Stronger
            ),
            enemyLaners = ____exports.EnemyLaners(picker, s)
        }
        pickCache[key] = inputs
    end
    return ____exports.PickCorePlan(__TS__ObjectAssign(
        {},
        inputs,
        {
            rotating = LaneHooks.IsRotationPlanned(picker),
            cautious = LaneHooks.IsCautious(picker)
        }
    ))
end
function ____exports.View(bot, s)
    local core = coreOf(s)
    local coreIsHuman = core ~= nil and not core.isBot
    if not LaneConfig.IsOn("Plan") then
        return {
            plan = "NEUTRAL",
            source = "default",
            handsOff = false,
            pullAllowed = true,
            pullForced = false,
            stackRequested = false,
            coreIsHuman = coreIsHuman,
            corePid = core and core.pid
        }
    end
    local track = trackFor(s)
    local plan
    local source
    if Orders.GetAcceptedForLane(bot, "LANE_FREEZE", s.lane) ~= nil then
        plan = "FREEZE"
        source = "order"
    elseif Orders.GetAcceptedForLane(bot, "LANE_SHOVE", s.lane) ~= nil then
        plan = "SHOVE"
        source = "order"
    elseif core ~= nil and coreIsHuman and core.alive then
        plan = track.inf.current
        source = "inferred"
    else
        plan = pickFor(core ~= nil and core.alive and core.unit or bot, s)
        source = "picked"
    end
    return {
        plan = plan,
        source = source,
        handsOff = Orders.GetAcceptedForLane(bot, "LANE_HANDSOFF", s.lane) ~= nil,
        pullAllowed = Orders.GetAcceptedForLane(bot, "LANE_NOPULL", s.lane) == nil and track.pullBlockedCycle ~= cycleIndex(s.time),
        pullForced = Orders.GetAcceptedForLane(bot, "LANE_PULL", s.lane) ~= nil,
        stackRequested = Orders.GetAcceptedForLane(bot, "LANE_STACK", s.lane) ~= nil,
        coreIsHuman = coreIsHuman,
        corePid = core and core.pid
    }
end
--- View with the support's once-per-wave-cycle chance of reading the plan wrong. Orders are never misread.
function ____exports.ForSupport(bot, s)
    local view = ____exports.View(bot, s)
    if view.source == "order" or view.source == "default" then
        return view
    end
    local pid = bot:GetPlayerID()
    local idx = cycleIndex(s.time)
    local m = misreads[pid]
    if m == nil or m.cycle ~= idx then
        m = {cycle = idx}
        misreads[pid] = m
        if LaneConfig.Roll(LaneConfig.Curve(
            "PlanMisread",
            LaneConfig.SkillOf(bot)
        )) then
            local track = trackFor(s)
            m.alt = view.coreIsHuman and alternativePlan(
                sumTally(track.cur, track.prev),
                view.plan
            ) or "NEUTRAL"
            HDebug.Log(
                "lane",
                (((("pid=" .. tostring(pid)) .. " misread plan ") .. view.plan) .. " as ") .. m.alt
            )
        end
    end
    if m.alt == nil or m.alt == view.plan then
        return view
    end
    return __TS__ObjectAssign({}, view, {plan = m.alt})
end
function ____exports.Describe(v)
    local text = ((("plan=" .. v.plan) .. "(") .. v.source) .. ")"
    if v.handsOff then
        text = text .. " handsoff"
    end
    if not v.pullAllowed then
        text = text .. " nopull"
    end
    if v.pullForced then
        text = text .. " pull!"
    end
    if v.stackRequested then
        text = text .. " stack!"
    end
    return text
end
LaneState.OnRefresh(____exports.ObserveSnapshot)
return ____exports
