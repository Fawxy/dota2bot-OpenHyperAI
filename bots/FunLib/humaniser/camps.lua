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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local ____camps_data = require(GetScriptDirectory().."/FunLib/humaniser/camps_data")
local CAMP_DATA = ____camps_data.CAMP_DATA
local DEFAULT_STACK_SEC = ____camps_data.DEFAULT_STACK_SEC
--- **TODO (in-game):** GetAmountAlongLane/GetLocationAlongLane are assumed absolute (0 = Radiant ancient) while
-- GetLaneFrontAmount is team-relative. OHA's J.GetClosestTeamLane feeds a team-relative amount straight into
-- GetLocationAlongLane, so one assumption may be wrong for Dire. Flip this if so.
local LANE_AMOUNT_TEAM_RELATIVE = false
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
local function camps()
    return LaneConfig.Settings().Camps
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local spawnerCache
local resolveCache
local byIdx = {}
function ____exports.ResetCache()
    spawnerCache = nil
    resolveCache = nil
    byIdx = {}
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
function ____exports.InBox(idx, loc, margin)
    if margin == nil then
        margin = 0
    end
    for ____, s in ipairs(____exports.Spawners()) do
        do
            local __continue20
            repeat
                if s.idx ~= idx then
                    __continue20 = true
                    break
                end
                return loc.x >= s.min.x - margin and loc.x <= s.max.x + margin and loc.y >= s.min.y - margin and loc.y <= s.max.y + margin
            until true
            if not __continue20 then
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
function ____exports.ToTeamAmount(team, absAmount)
    if LANE_AMOUNT_TEAM_RELATIVE or team == Team.Radiant then
        return absAmount
    end
    return 1 - absAmount
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
function ____exports.DeriveMeetPoint(_team, lane, campLoc)
    return GetLocationAlongLane(
        lane,
        ____exports.NearestLaneAmount(lane, campLoc)
    )
end
function ____exports.DeriveHalfMeetPoint(team, lane, meet)
    local step = camps().LaneSampleStep
    local offset = camps().HalfMeetOffset
    local dir = ____exports.ToAbsAmount(team, 1) > ____exports.ToAbsAmount(team, 0) and 1 or -1
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
function ____exports.DeriveStackExit(s, _team)
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
    if nearest == nil or nearestDist < 1 then
        return {Vector(c.x, c.y - away, c.z)}
    end
    local ux = (c.x - nearest.x) / nearestDist
    local uy = (c.y - nearest.y) / nearestDist
    return {Vector(c.x + ux * away, c.y + uy * away, c.z)}
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
local function matchReplay(s)
    local radius = camps().ReplayMatchRadius
    for ____, entry in ipairs(CAMP_DATA) do
        do
            local __continue52
            repeat
                if entry.near == nil or entry.team ~= s.team or entry.type ~= s.type then
                    __continue52 = true
                    break
                end
                if dist2D(entry.near, s.location) <= radius then
                    return entry
                end
                __continue52 = true
            until true
            if not __continue52 then
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
    local jobs = {}
    local claimed = {}
    for ____, s in ipairs(spawners) do
        do
            local __continue59
            repeat
                local entry = matchReplay(s)
                if entry == nil then
                    __continue59 = true
                    break
                end
                claimed[s.idx] = true
                local lane = entry.laneKind ~= nil and ____exports.LaneOfKind(entry.team, entry.laneKind) or nil
                local job = {
                    campIdx = s.idx,
                    team = s.team,
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
                jobs[s.idx] = job
                __continue59 = true
            until true
            if not __continue59 then
                break
            end
        end
    end
    for ____, entry in ipairs(CAMP_DATA) do
        do
            local __continue63
            repeat
                if entry.near ~= nil or entry.laneKind == nil or entry.pullAggroSec == nil then
                    __continue63 = true
                    break
                end
                local lane = ____exports.LaneOfKind(entry.team, entry.laneKind)
                local tower = laneTower(entry.team, lane)
                if tower == nil then
                    __continue63 = true
                    break
                end
                local best
                local bestDist = math.huge
                for ____, s in ipairs(spawners) do
                    do
                        local __continue66
                        repeat
                            if claimed[s.idx] == true or s.team ~= entry.team or s.type ~= entry.type then
                                __continue66 = true
                                break
                            end
                            local d = dist2D(s.location, tower)
                            if d < bestDist then
                                bestDist = d
                                best = s
                            end
                            __continue66 = true
                        until true
                        if not __continue66 then
                            break
                        end
                    end
                end
                if best == nil or bestDist > camps().PullCampMaxTowerDist then
                    __continue63 = true
                    break
                end
                claimed[best.idx] = true
                local meet = ____exports.DeriveMeetPoint(entry.team, lane, best.location)
                jobs[best.idx] = {
                    campIdx = best.idx,
                    team = best.team,
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
                __continue63 = true
            until true
            if not __continue63 then
                break
            end
        end
    end
    local result = {}
    for ____, s in ipairs(spawners) do
        local job = jobs[s.idx] or ({
            campIdx = s.idx,
            team = s.team,
            stack = stackFor(s, nil),
            source = "seed",
            type = s.type,
            derived = true
        })
        result[#result + 1] = job
        byIdx[s.idx] = job
    end
    if #spawners > 0 then
        resolveCache = result
    end
    return result
end
function ____exports.ByIdx(idx)
    ____exports.Resolve()
    return byIdx[idx]
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
