--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ObjectEntries(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = {key, obj[key]}
    end
    return result
end

local function __TS__ArrayReverse(self)
    local i = 1
    local j = #self
    while i < j do
        local temp = self[j]
        self[j] = self[i]
        self[i] = temp
        i = i + 1
        j = j - 1
    end
    return self
end
-- End of Lua Library inline imports
local ____exports = {}
local camps, dist2D, walkable, LANE_AMOUNT_TEAM_RELATIVE
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local ____camps_data = require(GetScriptDirectory().."/FunLib/humaniser/camps_data")
local CAMP_DATA = ____camps_data.CAMP_DATA
local DEFAULT_STACK_SEC = ____camps_data.DEFAULT_STACK_SEC
function camps()
    return LaneConfig.Settings().Camps
end
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function ____exports.ToTeamAmount(team, absAmount)
    local frameTeam = LANE_AMOUNT_TEAM_RELATIVE and GetTeam() or Team.Radiant
    return team == frameTeam and absAmount or 1 - absAmount
end
function ____exports.ToAbsAmount(team, teamAmount)
    return ____exports.ToTeamAmount(team, teamAmount)
end
function ____exports.NearestLaneAmount(lane, loc)
    local step = camps().LaneSampleStep
    local n = math.floor(1 / step + 0.5)
    local best = 0
    local bestDist = math.huge
    do
        local i = 0
        while i <= n do
            local a = math.min(1, i * step)
            local d = dist2D(
                GetLocationAlongLane(lane, a),
                loc
            )
            if d < bestDist then
                bestDist = d
                best = a
            end
            i = i + 1
        end
    end
    return best
end
--- The lane point `offset` along the lane from `meet` the way `team`'s wave walks (negative: back towards its base).
function ____exports.ShiftAlongLane(team, lane, meet, offset)
    local step = camps().LaneSampleStep
    local dir = ____exports.ToAbsAmount(team, 1) > ____exports.ToAbsAmount(team, 0) and 1 or -1
    if offset < 0 then
        dir = -dir
        offset = -offset
    end
    local a = ____exports.NearestLaneAmount(lane, meet)
    local prev = GetLocationAlongLane(lane, a)
    local prevDist = dist2D(prev, meet)
    while a > 0 and a < 1 do
        a = math.max(
            0,
            math.min(1, a + dir * step)
        )
        local cur = GetLocationAlongLane(lane, a)
        local curDist = dist2D(cur, meet)
        if curDist >= offset then
            local span = curDist - prevDist
            local t = span > 0 and math.max(
                0,
                math.min(1, (offset - prevDist) / span)
            ) or 1
            return Vector(prev.x + (cur.x - prev.x) * t, prev.y + (cur.y - prev.y) * t, prev.z + (cur.z - prev.z) * t)
        end
        prev = cur
        prevDist = curDist
    end
    return prev
end
function walkable(from, to)
    local step = LaneConfig.Settings().Radii.ExitCheckStep
    local n = math.max(
        1,
        math.ceil(dist2D(from, to) / step)
    )
    do
        local i = 1
        while i <= n do
            local t = i / n
            if not IsLocationPassable(Vector(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t, from.z)) then
                return false
            end
            i = i + 1
        end
    end
    return true
end
LANE_AMOUNT_TEAM_RELATIVE = true
local LANES = {Lane.Top, Lane.Mid, Lane.Bot}
local TYPE_RANK = {small = 0, medium = 1, large = 2, ancient = 3}
local TYPE_BY_INT = {"small", "medium", "large", "ancient"}
local function normaliseType(raw)
    if type(raw) == "number" then
        return TYPE_BY_INT[raw + 1] or "medium"
    end
    local s = string.lower(tostring(raw))
    if s == "small" or s == "medium" or s == "large" or s == "ancient" then
        return s
    end
    return "medium"
end
local spawnerCache
local resolveCache
--- Job of the spawner's own team, per camp.
local byIdx = {}
--- Seed and replay jobs per team, per camp: one camp can be one team's safe-lane camp and the other's off-lane camp.
local byTeam = {}
function ____exports.ResetCache()
    spawnerCache = nil
    resolveCache = nil
    byIdx = {}
    byTeam = {}
end
function ____exports.Spawners()
    if spawnerCache ~= nil then
        return spawnerCache
    end
    local list = {}
    local raw = GetNeutralSpawners()
    if raw ~= nil and raw ~= nil then
        for key, entry in pairs(raw) do
            local e = entry
            local idx = type(key) == "number" and key or e.idx
            list[#list + 1] = {
                idx = idx,
                team = e.team,
                type = normaliseType(e.type),
                location = e.location,
                min = e.min,
                max = e.max,
                speed = e.speed
            }
        end
    end
    __TS__ArraySort(
        list,
        function(____, a, b) return a.idx - b.idx end
    )
    if #list > 0 then
        spawnerCache = list
    end
    return list
end
function ____exports.BoxCenter(s)
    return Vector((s.min.x + s.max.x) / 2, (s.min.y + s.max.y) / 2, (s.min.z + s.max.z) / 2)
end
function ____exports.NearestSpawner(loc)
    local best
    local bestDist = math.huge
    for ____, s in ipairs(____exports.Spawners()) do
        local d = dist2D(
            ____exports.BoxCenter(s),
            loc
        )
        if d < bestDist then
            bestDist = d
            best = s
        end
    end
    return best, bestDist
end
--- A neutral belongs to the camp whose spawner is nearest, if within this (the box is about 300 across).
local FeedSpawnerRange = 600
--- Behaviour-side feeder for WorldFacts.NeutralSpeedFor: groups the neutrals `bot` sees by the camp type of their nearest
-- spawner and remembers each type's speed. One scan per second serves every bot of the team (not telemetry's tick, so it
-- runs with telemetry off).
function ____exports.FeedNeutralSpeeds(_bot)
    if not WorldFacts.FeedDue() then
        return
    end
    local bySpawner = {}
    for ____, n in ipairs(GetUnitList(UnitType.NeutralCreeps) or ({})) do
        do
            local __continue21
            repeat
                if n == nil or n:IsNull() then
                    __continue21 = true
                    break
                end
                local loc = n:GetLocation()
                if loc == nil or loc == nil then
                    __continue21 = true
                    break
                end
                local sp, d = ____exports.NearestSpawner(loc)
                if sp == nil or d > FeedSpawnerRange then
                    __continue21 = true
                    break
                end
                local ____temp_0 = bySpawner[sp.idx] or ({type = sp.type, units = {}})
                bySpawner[sp.idx] = ____temp_0
                local e = ____temp_0
                local ____e_units_1 = e.units
                ____e_units_1[#____e_units_1 + 1] = n
                __continue21 = true
            until true
            if not __continue21 then
                break
            end
        end
    end
    for ____, ____value in ipairs(__TS__ObjectEntries(bySpawner)) do
        local idx = ____value[1]
        local e = ____value[2]
        WorldFacts.FeedNeutral(
            e.type,
            e.units,
            tonumber(idx)
        )
    end
end
function ____exports.InBox(idx, loc, margin)
    if margin == nil then
        margin = 0
    end
    for ____, s in ipairs(____exports.Spawners()) do
        do
            local __continue29
            repeat
                if s.idx ~= idx then
                    __continue29 = true
                    break
                end
                return loc.x >= s.min.x - margin and loc.x <= s.max.x + margin and loc.y >= s.min.y - margin and loc.y <= s.max.y + margin
            until true
            if not __continue29 then
                break
            end
        end
    end
    return false
end
function ____exports.LaneOfKind(team, kind)
    if kind == "mid" then
        return Lane.Mid
    end
    local radiant = team == Team.Radiant
    local safe = radiant and Lane.Bot or Lane.Top
    local off = radiant and Lane.Top or Lane.Bot
    return kind == "safe" and safe or off
end
function ____exports.DeriveMeetPoint(_team, lane, campLoc)
    return GetLocationAlongLane(
        lane,
        ____exports.NearestLaneAmount(lane, campLoc)
    )
end
function ____exports.DeriveHalfMeetPoint(team, lane, meet)
    return ____exports.ShiftAlongLane(
        team,
        lane,
        meet,
        camps().HalfMeetOffset
    )
end
--- Point `offset` outside the spawn box, on the ray from its centre toward `target`; undefined when they coincide.
function ____exports.BoxEdgePoint(s, target, offset)
    local c = ____exports.BoxCenter(s)
    local dx = target.x - c.x
    local dy = target.y - c.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        return nil
    end
    local ux = dx / len
    local uy = dy / len
    local halfW = (s.max.x - s.min.x) / 2
    local halfH = (s.max.y - s.min.y) / 2
    local tx = math.abs(ux) > 0.000001 and halfW / math.abs(ux) or math.huge
    local ty = math.abs(uy) > 0.000001 and halfH / math.abs(uy) or math.huge
    local t = math.min(tx, ty) + offset
    return Vector(c.x + ux * t, c.y + uy * t, c.z)
end
--- Where a bot stands to aggro the camp: on the ray from the spawner origin (where the neutrals idle, not the box
-- centre) toward `toward`, `offset` past the box edge but at most Radii.StandReach from the origin. 7.41 boxes are
-- 600-1150 wide with the origin off-centre (good_8/evil_8: ~1000 from the west edge), so an edge stand could leave the
-- camp outside NeutralSearch or behind the trees along the box edge (console.9055828679 `mistake:no-camp`).
function ____exports.StandPoint(s, toward, offset)
    local o = s.location
    local dx = toward.x - o.x
    local dy = toward.y - o.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        return o
    end
    local ux = dx / len
    local uy = dy / len
    local tx = ux > 0.000001 and (s.max.x - o.x) / ux or (ux < -0.000001 and (s.min.x - o.x) / ux or math.huge)
    local ty = uy > 0.000001 and (s.max.y - o.y) / uy or (uy < -0.000001 and (s.min.y - o.y) / uy or math.huge)
    local d = math.min(
        math.max(
            0,
            math.min(tx, ty)
        ) + offset,
        LaneConfig.Settings().Radii.StandReach
    )
    return Vector(o.x + ux * d, o.y + uy * d, o.z)
end
function ____exports.DerivePullPath(s, meet)
    local edge = ____exports.BoxEdgePoint(
        s,
        meet,
        LaneConfig.Settings().Radii.PullPathEdge
    )
    return edge == nil and ({meet}) or ({edge, meet})
end
function ____exports.SpawnerByIdx(idx)
    for ____, s in ipairs(____exports.Spawners()) do
        if s.idx == idx then
            return s
        end
    end
    return nil
end
--- `towardLane`: the walk-off heads for the nearest lane instead of away from it (slice 4 StackJob, user 30/10/2026).
function ____exports.DeriveStackExit(s, _team, towardLane)
    if towardLane == nil then
        towardLane = false
    end
    local c = ____exports.BoxCenter(s)
    local nearest
    local nearestDist = math.huge
    for ____, lane in ipairs(LANES) do
        local p = GetLocationAlongLane(
            lane,
            ____exports.NearestLaneAmount(lane, c)
        )
        local d = dist2D(p, c)
        if d < nearestDist then
            nearestDist = d
            nearest = p
        end
    end
    local away = LaneConfig.Settings().Radii.StackExit
    local ux = 0
    local uy = -1
    if nearest ~= nil and nearestDist >= 1 then
        local sign = towardLane and -1 or 1
        ux = sign * (c.x - nearest.x) / nearestDist
        uy = sign * (c.y - nearest.y) / nearestDist
    end
    local fallback
    for ____, turn in ipairs({0, 45, 90, 135}) do
        local candidates = {}
        for ____, sign in ipairs(turn == 0 and ({1}) or ({1, -1})) do
            local a = sign * turn * math.pi / 180
            local dx = ux * math.cos(a) - uy * math.sin(a)
            local dy = ux * math.sin(a) + uy * math.cos(a)
            local target = Vector(c.x + dx * away, c.y + dy * away, c.z)
            candidates[#candidates + 1] = ____exports.BoxEdgePoint(s, target, away) or target
        end
        if nearest ~= nil and #candidates == 2 and dist2D(candidates[2], nearest) > dist2D(candidates[1], nearest) ~= towardLane then
            __TS__ArrayReverse(candidates)
        end
        fallback = fallback or candidates[1]
        for ____, exit in ipairs(candidates) do
            if walkable(
                ____exports.BoxEdgePoint(s, exit, 0) or c,
                exit
            ) then
                return {exit}
            end
        end
    end
    return {fallback or c}
end
local T1 = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
local T2 = {[Lane.Top] = Tower.Top2, [Lane.Mid] = Tower.Mid2, [Lane.Bot] = Tower.Bot2}
local function laneTower(team, lane)
    for ____, id in ipairs({T1[lane], T2[lane]}) do
        local tower = GetTower(team, id)
        if tower ~= nil and tower ~= nil and tower:IsAlive() then
            return tower:GetLocation()
        end
    end
    return nil
end
local function campTeamOf(entry)
    if entry.enemySide ~= true then
        return entry.team
    end
    return entry.team == Team.Radiant and Team.Dire or Team.Radiant
end
local function matchReplay(s)
    local radius = camps().ReplayMatchRadius
    for ____, entry in ipairs(CAMP_DATA) do
        do
            local __continue77
            repeat
                if entry.near == nil or campTeamOf(entry) ~= s.team or entry.type ~= s.type then
                    __continue77 = true
                    break
                end
                if dist2D(entry.near, s.location) <= radius then
                    return entry
                end
                __continue77 = true
            until true
            if not __continue77 then
                break
            end
        end
    end
    return nil
end
local function stackFor(s, entry)
    return {
        aggroSec = entry and entry.stackAggroSec or DEFAULT_STACK_SEC[s.type],
        exitPath = entry and entry.stackExitPath or ____exports.DeriveStackExit(s, s.team)
    }
end
function ____exports.Resolve()
    if resolveCache ~= nil then
        return resolveCache
    end
    local spawners = ____exports.Spawners()
    local jobs = {[Team.Radiant] = {}, [Team.Dire] = {}}
    for ____, s in ipairs(spawners) do
        do
            local __continue84
            repeat
                local entry = matchReplay(s)
                if entry == nil then
                    __continue84 = true
                    break
                end
                local lane = entry.laneKind ~= nil and ____exports.LaneOfKind(entry.team, entry.laneKind) or nil
                local job = {
                    campIdx = s.idx,
                    team = entry.team,
                    lane = lane,
                    stack = stackFor(s, entry),
                    source = entry.source,
                    type = s.type,
                    key = entry.key,
                    derived = false,
                    unverified = entry.unverified
                }
                if lane ~= nil and entry.pullAggroSec ~= nil and entry.pullPath ~= nil and entry.meetPoint ~= nil then
                    job.pull = {
                        aggroSec = entry.pullAggroSec,
                        halfAggroSec = entry.halfAggroSec,
                        path = entry.pullPath,
                        meetPoint = entry.meetPoint,
                        halfMeetPoint = entry.halfMeetPoint
                    }
                end
                jobs[entry.team][s.idx] = job
                __continue84 = true
            until true
            if not __continue84 then
                break
            end
        end
    end
    for ____, entry in ipairs(CAMP_DATA) do
        do
            local __continue88
            repeat
                if entry.near ~= nil or entry.laneKind == nil or entry.pullAggroSec == nil then
                    __continue88 = true
                    break
                end
                local lane = ____exports.LaneOfKind(entry.team, entry.laneKind)
                local tower = laneTower(entry.team, lane)
                if tower == nil then
                    __continue88 = true
                    break
                end
                local maxTowerDist = entry.maxTowerDist or camps().PullCampMaxTowerDist
                local own = jobs[entry.team]
                local campTeam = campTeamOf(entry)
                local best
                local bestDist = math.huge
                for ____, s in ipairs(spawners) do
                    do
                        local __continue91
                        repeat
                            if own[s.idx] ~= nil or s.team ~= campTeam or s.type ~= entry.type then
                                __continue91 = true
                                break
                            end
                            local d = dist2D(s.location, tower)
                            if d >= bestDist or d > maxTowerDist then
                                __continue91 = true
                                break
                            end
                            if dist2D(
                                s.location,
                                ____exports.DeriveMeetPoint(entry.team, lane, s.location)
                            ) > camps().PullCampMaxLaneDist then
                                __continue91 = true
                                break
                            end
                            bestDist = d
                            best = s
                            __continue91 = true
                        until true
                        if not __continue91 then
                            break
                        end
                    end
                end
                if best == nil then
                    __continue88 = true
                    break
                end
                local nearest = ____exports.DeriveMeetPoint(entry.team, lane, best.location)
                local meet = entry.meetBack ~= nil and ____exports.ShiftAlongLane(entry.team, lane, nearest, -entry.meetBack) or nearest
                own[best.idx] = {
                    campIdx = best.idx,
                    team = entry.team,
                    lane = lane,
                    stack = stackFor(best, entry),
                    pull = {
                        aggroSec = entry.pullAggroSec,
                        halfAggroSec = entry.halfAggroSec,
                        path = ____exports.DerivePullPath(best, meet),
                        meetPoint = meet,
                        halfMeetPoint = ____exports.DeriveHalfMeetPoint(entry.team, lane, meet)
                    },
                    source = entry.source,
                    type = best.type,
                    key = entry.key,
                    derived = true,
                    unverified = entry.unverified
                }
                __continue88 = true
            until true
            if not __continue88 then
                break
            end
        end
    end
    local result = {}
    for ____, s in ipairs(spawners) do
        local ____opt_6 = jobs[s.team]
        local job = ____opt_6 and ____opt_6[s.idx] or ({
            campIdx = s.idx,
            team = s.team,
            stack = stackFor(s, nil),
            source = "seed",
            type = s.type,
            derived = true
        })
        result[#result + 1] = job
        byIdx[s.idx] = job
        local enemyJob = jobs[s.team == Team.Radiant and Team.Dire or Team.Radiant][s.idx]
        if enemyJob ~= nil then
            result[#result + 1] = enemyJob
        end
    end
    byTeam = jobs
    if #spawners > 0 then
        resolveCache = result
    end
    return result
end
--- `team`'s job on the camp, else the job of the spawner's own team (every spawner has one).
function ____exports.ByIdx(idx, team)
    ____exports.Resolve()
    local ____temp_10
    if team ~= nil then
        local ____opt_8 = byTeam[team]
        ____temp_10 = ____opt_8 and ____opt_8[idx]
    else
        ____temp_10 = nil
    end
    return ____temp_10 or byIdx[idx]
end
function ____exports.PullCampsFor(team, lane)
    local found = {}
    for ____, job in ipairs(____exports.Resolve()) do
        if job.team == team and job.lane == lane and job.pull ~= nil then
            found[#found + 1] = job
        end
    end
    __TS__ArraySort(
        found,
        function(____, a, b) return TYPE_RANK[a.type] ~= TYPE_RANK[b.type] and TYPE_RANK[a.type] - TYPE_RANK[b.type] or a.campIdx - b.campIdx end
    )
    return found
end
return ____exports
