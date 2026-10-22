--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local CooldownMemory = require(GetScriptDirectory().."/FunLib/humaniser/cooldown_memory")
local CastWatch = require(GetScriptDirectory().."/FunLib/humaniser/cast_watch")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local Harass = require(GetScriptDirectory().."/FunLib/humaniser/harass")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local TARGET_RANGE = 1200
local TOWER_RANGE = 700
local LANE_RADIUS = 2500
local MISSING_COUNTS = 10
local ULT_LEVEL = 6
local INSTANCE_GAP = 1
local SPIKE_LEVELS = {6, 2}
local TOWER_IDS = {[Lane.Top] = {Tower.Top1, Tower.Top2, Tower.Top3}, [Lane.Mid] = {Tower.Mid1, Tower.Mid2, Tower.Mid3}, [Lane.Bot] = {Tower.Bot1, Tower.Bot2, Tower.Bot3}}
local spikeTracks = {}
local readCache = {}
local instances = {}
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function enemyTeamOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
function ____exports.RespectFrom(i)
    if i.spike == "theirs" then
        return "their_spike"
    end
    if i.theirUltReady then
        return "their_ult"
    end
    if i.enemiesNear > i.ourLaners then
        return "outnumbered"
    end
    return nil
end
--- Every window that applies, in the order they are checked; the first wins.
function ____exports.WindowsFrom(i)
    local list = {}
    if not i.target then
        return list
    end
    local s = LaneFightConfig.Settings()
    if i.keyThreatsDown > s.KeyThreatsWindow then
        list[#list + 1] = "spell"
    end
    if i.lastHit then
        list[#list + 1] = "lasthit"
    end
    if i.spike == "ours" then
        list[#list + 1] = "level"
    end
    if i.aheadOfFront > s.OutOfPosition or i.nearOurTower then
        list[#list + 1] = "position"
    end
    return list
end
function ____exports.Decide(i)
    local respect = ____exports.RespectFrom(i)
    if respect ~= nil then
        return {respect = respect}
    end
    return {window = ____exports.WindowsFrom(i)[1]}
end
local function spikeTrack(team, lane)
    local key = (tostring(team) .. ":") .. tostring(lane)
    local t = spikeTracks[key]
    if t == nil then
        t = {ours = {}, theirs = {}, spikes = {}}
        spikeTracks[key] = t
    end
    return t
end
--- Records the first time each side's highest laner level reached 2 and 6; the side that got there first spikes.
function ____exports.ObserveLevels(team, lane, ourMax, theirMax, now)
    if now < 0 then
        return
    end
    local t = spikeTrack(team, lane)
    for ____, level in ipairs(SPIKE_LEVELS) do
        do
            local __continue20
            repeat
                if t.ours[level] == nil and ourMax >= level then
                    t.ours[level] = now
                end
                if t.theirs[level] == nil and theirMax >= level then
                    t.theirs[level] = now
                end
                if t.spikes[level] ~= nil then
                    __continue20 = true
                    break
                end
                local ours = t.ours[level]
                local theirs = t.theirs[level]
                if ours == nil and theirs == nil then
                    __continue20 = true
                    break
                end
                if ours ~= nil and theirs ~= nil and ours == theirs then
                    t.spikes[level] = {at = now, ["until"] = now}
                    __continue20 = true
                    break
                end
                local s = LaneFightConfig.Settings()
                local side = (theirs == nil or ours ~= nil and ours < theirs) and "ours" or "theirs"
                local at = side == "ours" and ours or theirs
                t.spikes[level] = {
                    side = side,
                    at = at,
                    ["until"] = at + RandomFloat(s.LevelSpikeMin, s.LevelSpikeMax)
                }
                __continue20 = true
            until true
            if not __continue20 then
                break
            end
        end
    end
end
--- The side with a live level spike on (team, lane), from team's point of view; it ends early once the other side catches up.
function ____exports.LevelSpike(team, lane, now)
    if now < 0 then
        return nil
    end
    local t = spikeTracks[(tostring(team) .. ":") .. tostring(lane)]
    if t == nil then
        return nil
    end
    for ____, level in ipairs(SPIKE_LEVELS) do
        do
            local __continue30
            repeat
                local spike = t.spikes[level]
                if spike == nil or spike.side == nil or now < spike.at or now >= spike["until"] then
                    __continue30 = true
                    break
                end
                local caughtUp = t.ours[level]
                if spike.side == "ours" then
                    caughtUp = t.theirs[level]
                end
                if caughtUp ~= nil and caughtUp <= now then
                    __continue30 = true
                    break
                end
                return spike.side
            until true
            if not __continue30 then
                break
            end
        end
    end
    return nil
end
local function usable(u)
    if u == nil or u == nil or u:IsNull() then
        return false
    end
    if not u:IsAlive() or not u:CanBeSeen() or u:IsIllusion() or u:GetLocation() == nil then
        return false
    end
    local suspicious = LaneConfig.Helpers().IsSuspiciousIllusion
    return suspicious == nil or not suspicious(u)
end
local function nearestTower(team, lane)
    for ____, id in ipairs(TOWER_IDS[lane] or ({})) do
        local tower = GetTower(team, id)
        if tower ~= nil and tower ~= nil and tower:IsAlive() then
            return tower
        end
    end
    return nil
end
local function aheadOfFront(team, lane, loc)
    local front = GetLaneFrontLocation(
        enemyTeamOf(team),
        lane,
        0
    )
    local d = dist2D(loc, front)
    return LaneState.TeamAmountAt(team, lane, loc) < LaneState.TeamAmountAt(team, lane, front) and d or -d
end
local function keyAbilities(enemy)
    local names = {}
    for ____, a in ipairs(CastWatch.AbilitiesOf(enemy)) do
        if a.learned and AbilityClasses.Classify(a.name, a.ult) == "key" then
            names[#names + 1] = a.name
        end
    end
    return names
end
local function ultReady(pid, enemy, enemyPid, now, skill)
    if GetHeroLevel(enemyPid) < ULT_LEVEL then
        return false
    end
    for ____, a in ipairs(CastWatch.AbilitiesOf(enemy)) do
        do
            local __continue49
            repeat
                if not a.ult or a.item or not a.learned then
                    __continue49 = true
                    break
                end
                local ready = CooldownMemory.ProbablyReady(
                    pid,
                    enemyPid,
                    a.name,
                    true,
                    now,
                    skill
                )
                if ready then
                    return true
                end
                __continue49 = true
            until true
            if not __continue49 then
                break
            end
        end
    end
    return false
end
local function instanceFor(pid, key, now)
    local byKey = instances[pid]
    if byKey == nil then
        byKey = {}
        instances[pid] = byKey
    end
    local inst = byKey[key]
    if inst == nil or now - inst.lastApplied > INSTANCE_GAP then
        inst = {lastApplied = now}
        byKey[key] = inst
    end
    inst.lastApplied = now
    return inst
end
local function gather(bot, snap, now)
    local pid = bot:GetPlayerID()
    local team = bot:GetTeam()
    local lane = snap.lane
    local skill = Profile.Get(bot).skill
    local botLoc = bot:GetLocation()
    local ourLaners = 0
    local ourMax = 0
    for ____, h in ipairs(snap.allies) do
        do
            local __continue57
            repeat
                if not h.assigned then
                    __continue57 = true
                    break
                end
                if h.alive then
                    ourLaners = ourLaners + 1
                end
                ourMax = math.max(
                    ourMax,
                    GetHeroLevel(h.pid)
                )
                __continue57 = true
            until true
            if not __continue57 then
                break
            end
        end
    end
    local target
    local targetDist = math.huge
    local enemiesNear = 0
    local theirMax = 0
    local theirUltReady = false
    for ____, e in ipairs(LaneState.Enemies(bot, lane)) do
        do
            local __continue61
            repeat
                if e == nil or e.location == nil then
                    __continue61 = true
                    break
                end
                local unit = e.visible and usable(e.unit) and e.unit or nil
                local loc = unit ~= nil and unit:GetLocation() or e.location
                if dist2D(loc, snap.frontLoc) > LANE_RADIUS then
                    __continue61 = true
                    break
                end
                theirMax = math.max(
                    theirMax,
                    GetHeroLevel(e.pid)
                )
                if unit == nil then
                    if not e.visible and e.timeSinceSeen <= MISSING_COUNTS then
                        enemiesNear = enemiesNear + 1
                    end
                    __continue61 = true
                    break
                end
                enemiesNear = enemiesNear + 1
                if not theirUltReady and ultReady(
                    pid,
                    unit,
                    e.pid,
                    now,
                    skill
                ) then
                    theirUltReady = true
                end
                local d = dist2D(botLoc, loc)
                if d <= TARGET_RANGE and d < targetDist then
                    target = unit
                    targetDist = d
                end
                __continue61 = true
            until true
            if not __continue61 then
                break
            end
        end
    end
    ____exports.ObserveLevels(
        team,
        lane,
        ourMax,
        theirMax,
        now
    )
    local inputs = {
        target = target ~= nil,
        keyThreatsDown = 0,
        lastHit = false,
        spike = ____exports.LevelSpike(team, lane, now),
        aheadOfFront = -math.huge,
        nearOurTower = false,
        theirUltReady = theirUltReady,
        enemiesNear = enemiesNear,
        ourLaners = ourLaners
    }
    if target ~= nil then
        local loc = target:GetLocation()
        inputs.keyThreatsDown = CooldownMemory.KeyThreatsDown(
            pid,
            target:GetPlayerID(),
            keyAbilities(target),
            now,
            skill
        )
        inputs.lastHit = Harass.IsLastHitAttempt(target, snap.ally.units) ~= nil
        inputs.aheadOfFront = aheadOfFront(team, lane, loc)
        local tower = nearestTower(team, lane)
        inputs.nearOurTower = tower ~= nil and dist2D(
            loc,
            tower:GetLocation()
        ) <= TOWER_RANGE
    end
    return {inputs = inputs, target = target}
end
local function compute(bot, now)
    if now < 0 or not LaneFightConfig.IsActive() then
        return {noticed = false}
    end
    local snap = LaneState.ForBot(bot)
    if snap == nil then
        return {noticed = false}
    end
    local ____gather_result_0 = gather(bot, snap, now)
    local inputs = ____gather_result_0.inputs
    local target = ____gather_result_0.target
    local respect = ____exports.RespectFrom(inputs)
    if respect ~= nil or target == nil then
        return {target = target, respect = respect, noticed = false}
    end
    local windows = ____exports.WindowsFrom(inputs)
    if #windows == 0 then
        return {target = target, noticed = false}
    end
    local pid = bot:GetPlayerID()
    local targetPid = target:GetPlayerID()
    local winner
    for ____, w in ipairs(windows) do
        local inst = instanceFor(
            pid,
            (w .. ":") .. tostring(targetPid),
            now
        )
        if winner == nil then
            winner = inst
        end
    end
    local window = windows[1]
    if winner.noticed == nil then
        winner.noticed = RandomFloat(0, 1) < LaneFightConfig.Curve(
            "Notice",
            Profile.Get(bot).skill
        )
        Telemetry.Event("lanefight_window", {{"pid", pid}, {"window", window}, {"target", targetPid}, {"noticed", winner.noticed and 1 or 0}})
    end
    return {target = target, window = window, noticed = winner.noticed}
end
--- Cached per pid for WindowReadEvery.
function ____exports.ReadFor(bot, now)
    local pid = bot:GetPlayerID()
    local cached = readCache[pid]
    if cached ~= nil and now >= cached.at and now - cached.at < LaneFightConfig.Settings().WindowReadEvery then
        return cached.read
    end
    local read = compute(bot, now)
    readCache[pid] = {at = now, read = read}
    return read
end
return ____exports
