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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
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
local function settings()
    return LaneConfig.Settings().PullTiming
end
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
function ____exports.For(team, lane, origin, ____type, leadPath, half, seed)
    local cfg = settings()
    local fallback = {seconds = seed, source = "seed"}
    local meet = leadPath[#leadPath]
    local neutralSpeed = cfg.NeutralSpeed[____type]
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
    local waveTravel = meetAlong / cfg.CreepSpeed
    local waveAfter = ____exports.WalkLength(origin, leadPath) / neutralSpeed + cfg.Lead - (half and t.HalfPullLater or 0)
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
        lanePath = path
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
                local __continue20
                repeat
                    local p = pull.path[i + 1]
                    if i == n - 1 and hypot(p.x, p.y, pull.meetPoint.x, pull.meetPoint.y) < 1 then
                        __continue20 = true
                        break
                    end
                    result[#result + 1] = p
                    __continue20 = true
                until true
                if not __continue20 then
                    break
                end
            end
            i = i + 1
        end
    end
    result[#result + 1] = meet
    return result
end
--- The data table's pull seconds; a half pull without its own is HalfPullLater after the full pull.
function ____exports.SeedSeconds(pull, half)
    if not half then
        return pull.aggroSec
    end
    if pull.halfAggroSec ~= nil then
        return pull.halfAggroSec
    end
    local later = LaneConfig.Settings().Timing.HalfPullLater
    return __TS__ArrayMap(
        pull.aggroSec,
        function(____, s) return s + later end
    )
end
--- `data`'s pull seconds: from its team's wave reaching `meet` (default the pull's own meet point, or the half one) for
-- seed camps, else the data table's, since replay and measured seconds are measurements.
function ____exports.ForCamp(data, half, meet)
    if data.pull == nil then
        return {seconds = {}, source = "seed"}
    end
    local seed = ____exports.SeedSeconds(data.pull, half)
    local spawner = Camps.SpawnerByIdx(data.campIdx)
    if data.source ~= "seed" or spawner == nil then
        return {seconds = seed, source = "seed"}
    end
    local target = meet or (half and (data.pull.halfMeetPoint or data.pull.meetPoint) or data.pull.meetPoint)
    return ____exports.For(
        data.team,
        data.lane,
        spawner.location,
        data.type,
        ____exports.LeadPath(data.pull, target),
        half,
        seed
    )
end
--- Live correction for a wave-timed pull at `aggroAt` (no jitter): once its wave has left the barracks, the lead creep
-- of our lane creeps within LiveWindow of where the wave should be says how early or late it really is. 7.41 speeds
-- safe-lane waves up and slows off-lane ones for a few seconds after spawn (patch notes, no figure given), and a wave
-- can be blocked or held up on the way. Returns the shift in seconds, or undefined when nothing reliable is seen.
function ____exports.LiveShift(timing, aggroAt, now)
    if timing.source ~= "wave" or timing.waveAfter == nil or timing.waveTravel == nil or timing.meetAlong == nil or timing.lanePath == nil then
        return nil
    end
    local cfg = settings()
    local spawnAt = aggroAt + timing.waveAfter - timing.waveTravel
    if now < spawnAt + cfg.LiveFrom then
        return nil
    end
    local expected = (now - spawnAt) * cfg.CreepSpeed
    if expected >= timing.meetAlong then
        return nil
    end
    local window = cfg.LiveWindow * cfg.CreepSpeed
    local lead
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps) or ({})) do
        do
            local __continue33
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue33 = true
                    break
                end
                local along, off = ____exports.Along(
                    timing.lanePath,
                    c:GetLocation()
                )
                if off > cfg.LiveMaxOffset or math.abs(along - expected) > window then
                    __continue33 = true
                    break
                end
                if lead == nil or along > lead then
                    lead = along
                end
                __continue33 = true
            until true
            if not __continue33 then
                break
            end
        end
    end
    if lead == nil then
        return nil
    end
    local shift = (expected - lead) / cfg.CreepSpeed
    return math.max(
        -cfg.LiveMaxShift,
        math.min(cfg.LiveMaxShift, shift)
    )
end
return ____exports
