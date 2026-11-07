--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local settings, LaneAhead
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
function settings()
    return LaneConfig.Settings().PullTiming
end
function LaneAhead(team, lane)
    local ahead = settings().WaveAhead
    if lane == Lane.Mid then
        return 0
    end
    local safe = team == Team.Radiant == (lane == Lane.Bot)
    return safe and ahead.safe or ahead.off
end
--- 7.41 lane creep paths from maps/dota.vpk (entity lump, 22/10/2026): each team's npc_dota_spawner_<team>_<lane>
-- origin (the melee spawner), then the path_corner chain from its NPCFirstWaypoint. The first corner lies ~150-540
-- behind the spawner on every lane; creeps walk it, so it is kept.
local LANE_PATHS = {
    radiant_top = {
        {-6608, -4064},
        {-6584, -4224},
        {-6080, 384},
        {-6656, 1600},
        {-6208, 4224},
        {-6200, 5312},
        {-5792, 5464},
        {-5160, 5712},
        {-4488, 5824},
        {-3784, 5928},
        {-2792, 6048},
        {-1856, 6104},
        {3856, 5784},
        {5323, 4852}
    },
    radiant_mid = {
        {-5008, -4488},
        {-4856, -4376},
        {-3148, -2694},
        {-976, -824},
        {-360, -256},
        {176, 120},
        {912, 624},
        {2584, 1704},
        {4472, 3944},
        {5323, 4788}
    },
    radiant_bot = {
        {-3648, -6112},
        {-4024, -6112},
        {480, -6457},
        {2048, -6336},
        {3320, -6184},
        {4028, -6140},
        {4672, -6098},
        {5743, -5781},
        {6028, -5484},
        {6133, -4708},
        {6256, -3252},
        {6336, 3328},
        {5387, 4788}
    },
    dire_top = {
        {3168, 5792},
        {3704, 5768},
        {-1872, 6144},
        {-5248, 5696},
        {-6139, 5476},
        {-6236, 4872},
        {-6336, 3896},
        {-6576, -3720},
        {-5591, -5024}
    },
    dire_mid = {
        {4096, 3584},
        {4456, 3960},
        {2520, 1728},
        {864, 672},
        {144, 152},
        {-392, -224},
        {-1008, -760},
        {-4872, -4360},
        {-5527, -5024}
    },
    dire_bot = {
        {6272, 3648},
        {6320, 3840},
        {6080, 352},
        {6720, -2112},
        {6298, -3319},
        {6315, -4054},
        {6087, -5290},
        {5711, -5784},
        {5312, -6140},
        {1036, -6428},
        {-4224, -6096},
        {-5527, -5088}
    }
}
local LANE_NAME = {[Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot"}
local function hypot(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return math.sqrt(dx * dx + dy * dy)
end
function ____exports.LanePath(team, lane)
    local name = LANE_NAME[lane]
    if name == nil or team ~= Team.Radiant and team ~= Team.Dire then
        return nil
    end
    local key = ((team == Team.Radiant and "radiant" or "dire") .. "_") .. name
    return settings().LanePaths[key] or LANE_PATHS[key]
end
--- Distance along `path` (from its first point) to the nearest point on it, and how far `p` is from that point.
function ____exports.Along(path, p)
    local acc = 0
    local bestAlong = 0
    local bestOff = math.huge
    do
        local i = 0
        while i + 1 < #path do
            local ax, ay = unpack(path[i + 1])
            local bx, by = unpack(path[i + 1 + 1])
            local len = hypot(ax, ay, bx, by)
            local t = len > 0 and ((p.x - ax) * (bx - ax) + (p.y - ay) * (by - ay)) / (len * len) or 0
            t = math.max(
                0,
                math.min(1, t)
            )
            local off = hypot(p.x, p.y, ax + (bx - ax) * t, ay + (by - ay) * t)
            if off < bestOff then
                bestOff = off
                bestAlong = acc + t * len
            end
            acc = acc + len
            i = i + 1
        end
    end
    return bestAlong, bestOff
end
function ____exports.WalkLength(from, path)
    local d = 0
    local prev = from
    for ____, p in ipairs(path) do
        d = d + hypot(prev.x, prev.y, p.x, p.y)
        prev = p
    end
    return d
end
local function normalise(s, period)
    return s - math.floor(s / period) * period
end
--- Wave-derived aggro seconds for `team`'s wave on `lane` and a camp whose neutrals walk `leadPath` (ending at the
-- meet point) from `origin`; `seed` when an input is missing or the meet point is off the lane path.
function ____exports.For(team, lane, origin, ____type, leadPath, seed, campIdx)
    local cfg = settings()
    local fallback = {seconds = seed, source = "seed"}
    local meet = leadPath[#leadPath]
    local seedSpeed = cfg.NeutralSpeed[____type]
    local ____temp_0
    if seedSpeed == nil then
        ____temp_0 = nil
    else
        ____temp_0 = WorldFacts.NeutralSpeedFor(____type, seedSpeed, campIdx)
    end
    local neutralSpeed = ____temp_0
    if cfg.FromWave ~= true or lane == nil or origin == nil or meet == nil or neutralSpeed == nil then
        return fallback
    end
    local path = ____exports.LanePath(team, lane)
    if path == nil or #path < 2 then
        return fallback
    end
    local meetAlong, off = ____exports.Along(path, meet)
    if off > cfg.PathMaxOffset then
        return fallback
    end
    local t = LaneConfig.Settings().Timing
    local ahead = LaneAhead(team, lane)
    local waveTravel = meetAlong / WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed) - ahead
    local walkLen = ____exports.WalkLength(origin, leadPath)
    local walk = walkLen / neutralSpeed
    local waveAfter = walk + cfg.Lead
    local seconds = __TS__ArrayMap(
        cfg.WaveSlots,
        function(____, slot) return normalise(slot + waveTravel - waveAfter, t.PullPeriod) end
    )
    __TS__ArraySort(
        seconds,
        function(____, a, b) return a - b end
    )
    return {
        seconds = seconds,
        source = "wave",
        waveAfter = waveAfter,
        waveTravel = waveTravel,
        meetAlong = meetAlong,
        lanePath = path,
        ahead = ahead,
        team = team,
        walk = walk,
        neutralSpeed = neutralSpeed,
        walkLen = walkLen,
        type = ____type,
        seedSpeed = seedSpeed,
        campIdx = campIdx
    }
end
--- The camp's lead waypoints with its own meet point replaced by `meet`.
function ____exports.LeadPath(pull, meet)
    local result = {}
    local n = #pull.path
    do
        local i = 0
        while i < n do
            do
                local __continue22
                repeat
                    local p = pull.path[i + 1]
                    if i == n - 1 and hypot(p.x, p.y, pull.meetPoint.x, pull.meetPoint.y) < 1 then
                        __continue22 = true
                        break
                    end
                    result[#result + 1] = p
                    __continue22 = true
                until true
                if not __continue22 then
                    break
                end
            end
            i = i + 1
        end
    end
    result[#result + 1] = meet
    return result
end
--- `data`'s pull seconds: from its team's wave reaching the pull's meet point for seed camps, else the data table's, since
-- replay and measured seconds are measurements.
function ____exports.ForCamp(data)
    if data.pull == nil then
        return {seconds = {}, source = "seed"}
    end
    local seed = data.pull.aggroSec
    local spawner = Camps.SpawnerByIdx(data.campIdx)
    if data.source ~= "seed" or spawner == nil then
        return {seconds = seed, source = "seed"}
    end
    return ____exports.For(
        data.team,
        data.lane,
        spawner.location,
        data.type,
        ____exports.LeadPath(data.pull, data.pull.meetPoint),
        seed,
        data.campIdx
    )
end
--- The old camp-job pulls' live correction (camp_jobs; the pull job times its hit on the creeps, CreepTimer).
-- Live correction for a wave-timed pull at `aggroAt` (no jitter): once its wave has left the barracks, its lane creeps
-- within LiveWindow of where the wave should be say how early or late it really is. The plan already carries the lane's
-- WaveAhead; this is what is left. The shift applied is the wave's body (the mean of those creeps): the front creep runs
-- ahead of the creeps that take the neutrals (camp 1 hit 0.5-1 s early on the front creep, replay pdg3_C), so it is only
-- logged. A wave can also be blocked or held up on the way. Undefined when nothing reliable is seen.
function ____exports.LiveRead(timing, aggroAt, now)
    if timing.source ~= "wave" or timing.waveAfter == nil or timing.waveTravel == nil or timing.meetAlong == nil or timing.lanePath == nil then
        return nil
    end
    local cfg = settings()
    local spawnAt = aggroAt + timing.waveAfter - timing.waveTravel
    if now < spawnAt + cfg.LiveFrom then
        return nil
    end
    local expected = (now - spawnAt + (timing.ahead or 0)) * WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed)
    if expected >= timing.meetAlong then
        return nil
    end
    local window = cfg.LiveWindow * WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed)
    local front
    local sum = 0
    local n = 0
    local kind = (timing.team == nil or timing.team == GetTeam()) and UnitType.AlliedCreeps or UnitType.EnemyCreeps
    for ____, c in ipairs(GetUnitList(kind) or ({})) do
        do
            local __continue31
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue31 = true
                    break
                end
                local along, off = ____exports.Along(
                    timing.lanePath,
                    c:GetLocation()
                )
                if off > cfg.LiveMaxOffset or math.abs(along - expected) > window then
                    __continue31 = true
                    break
                end
                if front == nil or along > front then
                    front = along
                end
                sum = sum + along
                n = n + 1
                __continue31 = true
            until true
            if not __continue31 then
                break
            end
        end
    end
    if front == nil then
        return nil
    end
    local function clamp(d)
        return math.max(
            -cfg.LiveMaxShift,
            math.min(
                cfg.LiveMaxShift,
                (expected - d) / WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed)
            )
        )
    end
    return {
        shift = clamp(sum / n),
        front = clamp(front)
    }
end
--- Each creep of the timed wave by its distance along the lane path, front first: the timing team's lane creeps within
-- LiveWindow of where the wave should be at `now` for a hit at `aggroAt`, as LiveRead reads them, without its stop at the
-- meet point. Empty without a wave model.
function ____exports.WaveAlongs(timing, aggroAt, now)
    local out = {}
    if timing.source ~= "wave" or timing.waveAfter == nil or timing.waveTravel == nil or timing.lanePath == nil then
        return out
    end
    local cfg = settings()
    local v = WorldFacts.Latest("lane_creep_speed", cfg.CreepSpeed)
    local spawnAt = aggroAt + timing.waveAfter - timing.waveTravel
    local expected = (now - spawnAt + (timing.ahead or 0)) * v
    local window = cfg.LiveWindow * v
    local kind = (timing.team == nil or timing.team == GetTeam()) and UnitType.AlliedCreeps or UnitType.EnemyCreeps
    for ____, c in ipairs(GetUnitList(kind) or ({})) do
        do
            local __continue40
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue40 = true
                    break
                end
                local along, off = ____exports.Along(
                    timing.lanePath,
                    c:GetLocation()
                )
                if off <= cfg.LiveMaxOffset and math.abs(along - expected) <= window then
                    out[#out + 1] = along
                end
                __continue40 = true
            until true
            if not __continue40 then
                break
            end
        end
    end
    __TS__ArraySort(
        out,
        function(____, a, b) return b - a end
    )
    return out
end
function ____exports.LiveShift(timing, aggroAt, now)
    local ____opt_1 = ____exports.LiveRead(timing, aggroAt, now)
    return ____opt_1 and ____opt_1.shift
end
function ____exports.Timer(timing, slot, past)
    return {
        timing = timing,
        slot = slot,
        past = past,
        n = 0,
        reads = 0
    }
end
--- Reads the wave if LiveEvery has passed since the last read; returns the hit second (the slot until one is timed).
function ____exports.Read(c, now)
    local t = c.timing
    local meet = t.meetAlong
    if (c.readAt == nil or now - c.readAt >= settings().LiveEvery) and meet ~= nil and t.walk ~= nil then
        c.readAt = now
        if t.walkLen ~= nil and t.type ~= nil and t.seedSpeed ~= nil then
            local sp = WorldFacts.NeutralSpeedFor(t.type, t.seedSpeed, t.campIdx)
            t.neutralSpeed = sp
            t.walk = t.walkLen / sp
        end
        local walk = t.walk
        local alongs = ____exports.WaveAlongs(t, c.slot, now)
        c.n = #alongs
        if #alongs >= 2 then
            local v = WorldFacts.Latest(
                "lane_creep_speed",
                settings().CreepSpeed
            )
            local hit = now + (meet + c.past - alongs[1]) / v - walk
            local function pastAt(along)
                return math.floor(along + v * (hit + walk - now) - meet + 0.5)
            end
            c.hit = hit
            c.waveAt = now + (meet - alongs[#alongs]) / v
            c.next = pastAt(alongs[2])
            c.back = pastAt(alongs[#alongs])
            c.reads = c.reads + 1
            if c.first == nil then
                c.first = hit - c.slot
            end
        end
    end
    return c.hit or c.slot
end
--- When the wave's back creep reaches the meet point: from the last read (none after the order goes out, so the logged
-- read is the one the hit went on), else the plan's.
function ____exports.WaveAt(c)
    if c.waveAt ~= nil then
        return c.waveAt
    end
    return c.timing.waveAfter ~= nil and c.slot + c.timing.waveAfter or nil
end
return ____exports
