--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local logged, r2
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
--- ev=threat for one consumer's decision on a read: on a changed decision, else at most once per LogEvery per hero and
-- consumer (gates run every think; the design's "once per decision" would flood).
function ____exports.Log(bot, consumer, r, decision)
    local pid = bot:GetPlayerID()
    local key = (tostring(pid) .. ":") .. consumer
    local last = logged[key]
    if last ~= nil and last.decision == decision and r.t - last.t < ____exports.SETTINGS.LogEvery then
        return
    end
    logged[key] = {t = r.t, decision = decision}
    Telemetry.Event(
        "threat",
        {
            {"pid", pid},
            {"who", consumer},
            {"dec", decision},
            {
                "x",
                math.floor(r.place.x)
            },
            {
                "y",
                math.floor(r.place.y)
            },
            {
                "hz",
                r2(r.horizon)
            },
            {
                "dep",
                r2(r.depth)
            },
            {
                "threat",
                r2(r.threat)
            },
            {"band", r.band},
            {"reach", #r.reach},
            {
                "rpid",
                #r.reach > 0 and table.concat(r.reach, ",") or nil
            },
            {
                "burst",
                r2(r.burst)
            },
            {"ally", r.allies},
            {"tower", r.tower},
            {
                "miss",
                r2(r.missing)
            },
            {
                "mpid",
                #r.mpids > 0 and table.concat(r.mpids, ",") or nil
            },
            {
                "mtss",
                r.mtss ~= nil and math.floor(r.mtss + 0.5) or nil
            },
            {"mcut", r.mcut > 0 and r.mcut or nil},
            {
                "hp",
                r2(bot:GetHealth() / math.max(
                    1,
                    bot:GetMaxHealth()
                ))
            }
        }
    )
end
____exports.SETTINGS = {
    MissingAfter = 3,
    MissingSpeed = 330,
    MissingReachMax = 4000,
    MissingMargin = 600,
    EarlyWeight = 0.2,
    LateWeight = 0.5,
    EarlyUntil = 240,
    DepthFactor = {{0.5, 1}, {0.65, 0.25}, {1.01, 0.1}},
    DistFactor = {{2000, 1}, {3000, 0.5}, {math.huge, 0.25}},
    GateHorizon = 4,
    MissingRefuse = 0.5,
    VisionCut = true,
    WalkStep = 300,
    BurstWindow = 3,
    TowerReach = 868,
    WReach = 0.25,
    WMissing = 0.3,
    WTower = 0.4,
    WBurst = 0.5,
    WAlly = 0.15,
    Watch = 0.25,
    Pressured = 0.5,
    LogEvery = 5
}
local TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
    Tower.Base1,
    Tower.Base2
}
local MAX_PLAYER_ID = 23
local speeds = {}
logged = {}
function ____exports.ResetCache()
    speeds = {}
    logged = {}
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
local function distToSegment(p, a, b)
    local vx = b.x - a.x
    local vy = b.y - a.y
    local len2 = vx * vx + vy * vy
    local u = len2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)
    ) or 0
    return math.sqrt((p.x - (a.x + u * vx)) ^ 2 + (p.y - (a.y + u * vy)) ^ 2)
end
local function valid(u)
    return u ~= nil and u ~= nil and u:IsAlive() and not u:IsIllusion()
end
--- Can `u` be in attack range of a point on the walk within `horizon`: its run plus its attack range and both hulls.
local function canReach(u, bot, from, place, horizon)
    local at = u:GetLocation()
    if at == nil or at == nil then
        return false
    end
    local run = u:GetCurrentMovementSpeed() * horizon + u:GetAttackRange() + u:GetBoundingRadius() + bot:GetBoundingRadius()
    return distToSegment(at, from, place) <= run
end
local function nearestTower(team, place)
    local best
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue9
            repeat
                local tw = GetTower(team, id)
                if not valid(tw) then
                    __continue9 = true
                    break
                end
                local d = dist(
                    tw:GetLocation(),
                    place
                )
                if best == nil or d < best then
                    best = d
                end
                __continue9 = true
            until true
            if not __continue9 then
                break
            end
        end
    end
    return best
end
--- The place's depth: its distance to the nearest live enemy tower over the sum with the distance to our nearest; 0.5 with no read.
local function placeDepth(team, enemyTeam, place)
    local own = nearestTower(team, place)
    local en = nearestTower(enemyTeam, place)
    if own == nil or en == nil or own + en <= 0 then
        return 0.5
    end
    return en / (own + en)
end
local function stepFactor(steps, v)
    for ____, ____value in ipairs(steps) do
        local edge = ____value[1]
        local f = ____value[2]
        if v < edge then
            return f
        end
    end
    return steps[#steps][2]
end
local function inTowerReach(enemyTeam, place)
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue20
            repeat
                local tw = GetTower(enemyTeam, id)
                if not valid(tw) then
                    __continue20 = true
                    break
                end
                if dist(
                    tw:GetLocation(),
                    place
                ) <= WorldFacts.TowerReach(tw, ____exports.SETTINGS.TowerReach) then
                    return true
                end
                __continue20 = true
            until true
            if not __continue20 then
                break
            end
        end
    end
    return false
end
--- The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
-- read speed, capped) plus MissingMargin; one whose run touches the walk adds EarlyWeight or LateWeight by game minute.
-- Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for a bot-only team). A hero the API has no sighting of is
-- not placed and not counted.
local function walkPoints(from, place)
    local d = dist(from, place)
    local n = math.max(
        1,
        math.ceil(d / ____exports.SETTINGS.WalkStep)
    )
    local out = {}
    do
        local i = 0
        while i <= n do
            out[#out + 1] = Vector(from.x + (place.x - from.x) * i / n, from.y + (place.y - from.y) * i / n, place.z)
            i = i + 1
        end
    end
    return out
end
--- Some walk point within `r` of `at` is out of our sight.
local function unseenWithin(points, at, r)
    for ____, p in ipairs(points) do
        if dist(p, at) <= r and not IsLocationVisible(p) then
            return true
        end
    end
    return false
end
--- The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
-- read speed, capped) plus MissingMargin; one whose run touches the walk, with some of that reach out of our sight
-- (VisionCut), adds EarlyWeight or LateWeight by game minute, scaled by the place prior (DepthFactor for the place's depth,
-- DistFactor for its last-seen distance to the place). Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for
-- a bot-only team). A hero the API has no sighting of is not placed and not counted.
local function missingOf(bot, from, place, depth, now, visible)
    local s = ____exports.SETTINGS
    local team = bot:GetTeam()
    local base = (now < s.EarlyUntil and s.EarlyWeight or s.LateWeight) * stepFactor(s.DepthFactor, depth)
    local sum = 0
    local cut = 0
    local mtss
    local pids = {}
    local points
    do
        local pid = 0
        while pid <= MAX_PLAYER_ID do
            do
                local __continue31
                repeat
                    local t = GetTeamForPlayer(pid)
                    if t == team or t ~= Team.Radiant and t ~= Team.Dire or visible[pid] == true or not IsHeroAlive(pid) then
                        __continue31 = true
                        break
                    end
                    local info = GetHeroLastSeenInfo(pid)[1]
                    if info == nil or info.time_since_seen <= s.MissingAfter then
                        __continue31 = true
                        break
                    end
                    local r = math.min((speeds[pid] or s.MissingSpeed) * info.time_since_seen, s.MissingReachMax) + s.MissingMargin
                    if distToSegment(info.location, from, place) > r then
                        __continue31 = true
                        break
                    end
                    if s.VisionCut then
                        points = points or walkPoints(from, place)
                        if not unseenWithin(points, info.location, r) then
                            cut = cut + 1
                            __continue31 = true
                            break
                        end
                    end
                    sum = sum + base * stepFactor(
                        s.DistFactor,
                        dist(info.location, place)
                    )
                    pids[#pids + 1] = pid
                    mtss = math.max(mtss or 0, info.time_since_seen)
                    __continue31 = true
                until true
                if not __continue31 then
                    break
                end
            end
            pid = pid + 1
        end
    end
    return sum, pids, mtss, cut
end
function ____exports.BandOf(threat, lethal)
    if lethal then
        return "lethal"
    end
    return threat >= ____exports.SETTINGS.Pressured and "pressured" or (threat >= ____exports.SETTINGS.Watch and "watch" or "none")
end
--- The read for `bot` walking from `from` to `place` with `horizon` seconds ahead. `lethal` fires when the heroes in reach
-- can deal the bot's HP within the burst window and they outnumber our heroes in reach (the `escape` input is not built yet:
-- slice file Open items).
function ____exports.Read(bot, from, place, horizon)
    local s = ____exports.SETTINGS
    local now = DotaTime()
    local visible = {}
    local reach = {}
    local dmg = 0
    local window = math.min(horizon, s.BurstWindow)
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue40
            repeat
                if not valid(e) or not e:CanBeSeen() then
                    __continue40 = true
                    break
                end
                local pid = e:GetPlayerID()
                visible[pid] = true
                local sp = e:GetCurrentMovementSpeed()
                if sp ~= nil and sp > 0 then
                    speeds[pid] = sp
                end
                if canReach(
                    e,
                    bot,
                    from,
                    place,
                    horizon
                ) then
                    reach[#reach + 1] = pid
                    dmg = dmg + e:GetEstimatedDamageToTarget(true, bot, window, DamageType.All)
                end
                __continue40 = true
            until true
            if not __continue40 then
                break
            end
        end
    end
    local allies = 0
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue45
            repeat
                if not valid(a) or a == bot then
                    __continue45 = true
                    break
                end
                if canReach(
                    a,
                    bot,
                    place,
                    place,
                    horizon
                ) then
                    allies = allies + 1
                end
                __continue45 = true
            until true
            if not __continue45 then
                break
            end
        end
    end
    local enemyTeam = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
    local depth = placeDepth(
        bot:GetTeam(),
        enemyTeam,
        place
    )
    local missing, mpids, mtss, mcut = missingOf(
        bot,
        from,
        place,
        depth,
        now,
        visible
    )
    local tower = inTowerReach(enemyTeam, place)
    local hp = math.max(
        1,
        bot:GetHealth()
    )
    local burst = dmg / hp
    local raw = s.WReach * #reach + s.WMissing * missing + (tower and s.WTower or 0) + s.WBurst * math.min(1, burst) - s.WAlly * allies
    local threat = math.max(
        0,
        math.min(1, raw)
    )
    local lethal = burst >= 1 and #reach > allies
    return {
        t = now,
        from = from,
        place = place,
        horizon = horizon,
        depth = depth,
        reach = reach,
        burst = burst,
        allies = allies,
        tower = tower,
        missing = missing,
        mpids = mpids,
        mtss = mtss,
        mcut = mcut,
        threat = threat,
        band = ____exports.BandOf(threat, lethal)
    }
end
--- The gate rule the starts share (the core camp trip, the support's pull, stack and take, the farm trip, the pull farm): held
-- by a visible hero who can reach the walk within GateHorizon ("threat"), else by the belief's weight sum at MissingRefuse
-- ("missing"); the read and its decision are logged as ev=threat for `consumer`.
function ____exports.Gate(bot, from, place, consumer)
    local r = ____exports.Read(bot, from, place, ____exports.SETTINGS.GateHorizon)
    local why = #r.reach > 0 and "threat" or (r.missing >= ____exports.SETTINGS.MissingRefuse and "missing" or nil)
    ____exports.Log(bot, consumer, r, why or "go")
    return {why = why, r = r}
end
r2 = function(x) return math.floor(x * 100 + 0.5) / 100 end
return ____exports
