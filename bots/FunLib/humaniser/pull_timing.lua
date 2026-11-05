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

local function __TS__ArraySlice(self, first, last)
    local len = #self
    first = first or 0
    if first < 0 then
        first = len + first
        if first < 0 then
            first = 0
        end
    else
        if first > len then
            first = len
        end
    end
    last = last or len
    if last < 0 then
        last = len + last
        if last < 0 then
            last = 0
        end
    else
        if last > len then
            last = len
        end
    end
    local out = {}
    first = first + 1
    last = last + 1
    local n = 1
    while first < last do
        out[n] = self[first]
        first = first + 1
        n = n + 1
    end
    return out
end
-- End of Lua Library inline imports
local ____exports = {}
local settings, LaneAhead
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
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
    local ahead = LaneAhead(team, lane)
    local waveTravel = meetAlong / cfg.CreepSpeed - ahead
    local walk = ____exports.WalkLength(origin, leadPath) / neutralSpeed
    local waveAfter = walk + cfg.Lead - (half and t.HalfPullLater or 0)
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
        origin = origin,
        leadPath = leadPath,
        neutralSpeed = neutralSpeed
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
    local expected = (now - spawnAt + (timing.ahead or 0)) * cfg.CreepSpeed
    if expected >= timing.meetAlong then
        return nil
    end
    local window = cfg.LiveWindow * cfg.CreepSpeed
    local front
    local sum = 0
    local n = 0
    local kind = (timing.team == nil or timing.team == GetTeam()) and UnitType.AlliedCreeps or UnitType.EnemyCreeps
    for ____, c in ipairs(GetUnitList(kind) or ({})) do
        do
            local __continue35
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue35 = true
                    break
                end
                local along, off = ____exports.Along(
                    timing.lanePath,
                    c:GetLocation()
                )
                if off > cfg.LiveMaxOffset or math.abs(along - expected) > window then
                    __continue35 = true
                    break
                end
                if front == nil or along > front then
                    front = along
                end
                sum = sum + along
                n = n + 1
                __continue35 = true
            until true
            if not __continue35 then
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
            math.min(cfg.LiveMaxShift, (expected - d) / cfg.CreepSpeed)
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
    local spawnAt = aggroAt + timing.waveAfter - timing.waveTravel
    local expected = (now - spawnAt + (timing.ahead or 0)) * cfg.CreepSpeed
    local window = cfg.LiveWindow * cfg.CreepSpeed
    local kind = (timing.team == nil or timing.team == GetTeam()) and UnitType.AlliedCreeps or UnitType.EnemyCreeps
    for ____, c in ipairs(GetUnitList(kind) or ({})) do
        do
            local __continue44
            repeat
                if c == nil or c == nil or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue44 = true
                    break
                end
                local along, off = ____exports.Along(
                    timing.lanePath,
                    c:GetLocation()
                )
                if off <= cfg.LiveMaxOffset and math.abs(along - expected) <= window then
                    out[#out + 1] = along
                end
                __continue44 = true
            until true
            if not __continue44 then
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
    local ____opt_0 = ____exports.LiveRead(timing, aggroAt, now)
    return ____opt_0 and ____opt_0.shift
end
function ____exports.Timer(timing, slot, index, past, keep, heroSpeed)
    if keep == nil then
        keep = 0
    end
    return {
        timing = timing,
        slot = slot,
        index = index,
        past = past,
        keep = keep,
        heroSpeed = heroSpeed,
        n = 0,
        reads = 0
    }
end
--- The point `along` down `path` (clamped to its ends).
local function PathPoint(path, along)
    local acc = 0
    do
        local i = 0
        while i + 1 < #path do
            local ax, ay = unpack(path[i + 1])
            local bx, by = unpack(path[i + 1 + 1])
            local len = hypot(ax, ay, bx, by)
            if along <= acc + len or i + 2 == #path then
                local f = len > 0 and math.max(
                    0,
                    math.min(1, (along - acc) / len)
                ) or 0
                return {ax + (bx - ax) * f, ay + (by - ay) * f}
            end
            acc = acc + len
            i = i + 1
        end
    end
    return {path[1][1], path[1][2]}
end
--- Where a walker of the lead path is `s` seconds after the hit: down it from the origin, then at the meet point.
local function NeutralAt(origin, lead, speed, s)
    local left = math.max(0, s) * speed
    local px = origin.x
    local py = origin.y
    for ____, p in ipairs(lead) do
        local len = hypot(px, py, p.x, p.y)
        if left <= len then
            local f = len > 0 and left / len or 0
            return {px + (p.x - px) * f, py + (p.y - py) * f}
        end
        left = left - len
        px = p.x
        py = p.y
    end
    return {px, py}
end
--- `lead` with its last point moved `back` towards the point before it (the origin for a one-point lead).
local function Shorten(origin, lead, back)
    if back <= 0 or #lead == 0 then
        return lead
    end
    local ____end = lead[#lead]
    local prev = #lead > 1 and lead[#lead - 2 + 1] or origin
    local len = hypot(prev.x, prev.y, ____end.x, ____end.y)
    if len <= 0 then
        return lead
    end
    local f = math.max(0, len - back) / len
    local out = __TS__ArraySlice(lead, 0, #lead - 1)
    out[#out + 1] = Vector(prev.x + (____end.x - prev.x) * f, prev.y + (____end.y - prev.y) * f, ____end.z)
    return out
end
--- A half pull's hit and stand point from `centre`: candidate hits every HalfStep over HalfSearch around it (none before
-- `now`), each with the puller standing HalfStandBack short of the meet point on the lead's last leg. The puller starts
-- HalfHeroStart down the lead path at the hit (it hits from range) and walks it at `heroSpeed` to the stand point; the
-- neutrals leave the origin HalfNeutralDelay after the hit (the phchk2 replays: 0.4-2.3 s, camp 1 0.6-1.4) and follow it
-- there at NeutralSpeed, stopping where the first creep from `keep` back comes within HalfAcquire (the fight). A lane creep
-- turns within HalfAcquire of the neutrals or HalfHeroAggro of the puller they are hitting (EC-090: no written rule; in the
-- replays all four turned at 6:23 in A_on_4 with the neutrals 970-1025 off and the puller 280-390), the puller counted from
-- the hit on. Keeps the candidate with the largest margin (CreepTimer `margin`).
local function Clearance(t, alongs, keep, now, centre, heroSpeed)
    local cfg = settings()
    local path = t.lanePath
    local origin = t.origin
    local lead = t.leadPath
    local speed = t.neutralSpeed
    local walk = t.walk
    if path == nil or origin == nil or lead == nil or speed == nil or walk == nil then
        return nil
    end
    local step = cfg.HalfStep
    local r = cfg.HalfAcquire
    local rh = cfg.HalfHeroAggro
    local v = cfg.CreepSpeed
    local lo, hi = unpack(cfg.HalfSearch)
    local first = math.max(
        0,
        math.ceil((centre + lo - now) / step)
    )
    local last = math.floor((centre + hi - now) / step)
    if last < first then
        return nil
    end
    local delay = cfg.HalfNeutralDelay
    local span = math.ceil((walk + delay + cfg.HalfHold) / step)
    local creeps = {}
    do
        local k = 0
        while k < #alongs do
            local row = {}
            do
                local i = 0
                while i <= last + span do
                    row[#row + 1] = PathPoint(path, alongs[k + 1] + v * i * step)
                    i = i + 1
                end
            end
            creeps[#creeps + 1] = row
            k = k + 1
        end
    end
    local hs = heroSpeed ~= nil and heroSpeed > 0 and heroSpeed or nil
    local best
    for ____, back in ipairs(cfg.HalfStandBack) do
        local route = Shorten(origin, lead, back)
        local walked = {}
        local hero = {}
        do
            local j = 0
            while j <= span do
                walked[#walked + 1] = NeutralAt(origin, route, speed, j * step - delay)
                if hs ~= nil then
                    hero[#hero + 1] = NeutralAt(origin, route, hs, cfg.HalfHeroStart / hs + j * step)
                end
                j = j + 1
            end
        end
        do
            local h = first
            while h <= last do
                local clear = math.huge
                local turn = math.huge
                local stop
                do
                    local j = 0
                    while j <= span do
                        local nx, ny = unpack(stop or walked[j + 1])
                        local hit = hs ~= nil and hypot(nx, ny, hero[j + 1][1], hero[j + 1][2]) <= cfg.HalfHitReach
                        local fight = false
                        do
                            local k = 0
                            while k < #creeps do
                                local cx, cy = unpack(creeps[k + 1][h + j + 1])
                                local d = hypot(nx, ny, cx, cy)
                                local dh = hs ~= nil and hypot(hero[j + 1][1], hero[j + 1][2], cx, cy) - rh + r or math.huge
                                if k < keep then
                                    clear = math.min(
                                        clear,
                                        math.min(d, dh)
                                    )
                                else
                                    if k == keep then
                                        turn = math.min(
                                            turn,
                                            hit and math.min(d, dh) or d
                                        )
                                    end
                                    if d <= r then
                                        fight = true
                                    end
                                end
                                k = k + 1
                            end
                        end
                        if fight and stop == nil then
                            stop = {nx, ny}
                        end
                        j = j + 1
                    end
                end
                local margin = math.min(clear - r, r - turn)
                if best == nil or margin > best.margin then
                    best = {
                        hit = now + h * step,
                        clear = math.floor(clear + 0.5),
                        turn = math.floor(turn + 0.5),
                        margin = math.floor(margin + 0.5),
                        back = back,
                        stand = route[#route]
                    }
                end
                h = h + 1
            end
        end
    end
    return best
end
--- Where a stepping-in half pull's lead ends: back from `stand` towards `origin` (at least HalfStepBack) until HalfHoldOff
-- from the lane path, so the wave walks past out of reach of the puller and the neutrals hitting it (phhar4: 300 behind a
-- meet point on the lane, camp 1 took the whole wave 5 of 5 while the puller waited). At most the origin.
function ____exports.StepBackPoint(origin, stand, path)
    local cfg = settings()
    local ox = stand.x - origin.x
    local oy = stand.y - origin.y
    local ol = math.max(
        1,
        math.sqrt(ox * ox + oy * oy)
    )
    local b = math.min(cfg.HalfStepBack, ol)
    local function at(d)
        return Vector(stand.x - ox / ol * d, stand.y - oy / ol * d, stand.z)
    end
    if path ~= nil then
        while b < ol and select(
            2,
            ____exports.Along(
                path,
                at(b)
            )
        ) < cfg.HalfHoldOff do
            b = math.min(ol, b + 50)
        end
    end
    return at(b)
end
--- A half pull's live step-in (user 05/11/2026: walk-cancel towards the wave and time it): the lead ends HalfStepBack behind
-- `stand` (StepBackPoint), and during the watch the puller, its neutrals following, stands at the point on the line from
-- there through `stand` to the lane at the meet point that is nearest the lane while every front creep, now and
-- HalfStepAhead s on, stays more than HalfHeroAggro + HalfStepBuffer from it; none clear: the back end. Once `engaged` (a
-- creep of the wave on a neutral) it stays at `at`. The hit's timing error (the neutrals' start 0.4-2.1 s after the hit,
-- phchk3) is far above the search's margins (10-38); the lane end lets an off-lane meet point (camp 26: the puller 515-830
-- from the wave in phchk3, nothing taken) still reach the wave.
function ____exports.StepIn(c, origin, stand, meet, now, engaged, at)
    if engaged then
        return at
    end
    local cfg = settings()
    local t = c.timing
    local path = t.lanePath
    if path == nil then
        return stand
    end
    if t.meetAlong ~= nil then
        local lx, ly = unpack(PathPoint(path, t.meetAlong))
        meet = Vector(lx, ly, meet.z)
    end
    local alongs = ____exports.WaveAlongs(t, c.slot, now)
    if #alongs < c.keep + 1 then
        return stand
    end
    local fronts = {}
    do
        local k = 0
        while k < c.keep do
            fronts[#fronts + 1] = PathPoint(path, alongs[k + 1])
            fronts[#fronts + 1] = PathPoint(path, alongs[k + 1] + cfg.CreepSpeed * cfg.HalfStepAhead)
            k = k + 1
        end
    end
    local back = ____exports.StepBackPoint(origin, stand, path)
    local len = hypot(back.x, back.y, meet.x, meet.y)
    local n = math.max(
        1,
        math.ceil(len / 50)
    )
    local reach = cfg.HalfHeroAggro + cfg.HalfStepBuffer
    local pin = cfg.HalfStand
    do
        local i = n
        while i >= 0 do
            do
                local __continue89
                repeat
                    local x = back.x + (meet.x - back.x) * i / n
                    local y = back.y + (meet.y - back.y) * i / n
                    if pin > 0 then
                        if select(
                            2,
                            ____exports.Along(
                                path,
                                Vector(x, y, stand.z)
                            )
                        ) >= pin then
                            return Vector(x, y, stand.z)
                        end
                        __continue89 = true
                        break
                    end
                    local clear = true
                    for ____, ____value in ipairs(fronts) do
                        local fx = ____value[1]
                        local fy = ____value[2]
                        if hypot(x, y, fx, fy) <= reach then
                            clear = false
                        end
                    end
                    if clear then
                        return Vector(x, y, stand.z)
                    end
                    __continue89 = true
                until true
                if not __continue89 then
                    break
                end
            end
            i = i - 1
        end
    end
    return back
end
--- Reads the wave if LiveEvery has passed since the last read; returns the hit second (the slot until one is timed).
function ____exports.Read(c, now)
    local t = c.timing
    local meet = t.meetAlong
    local walk = t.walk
    if (c.readAt == nil or now - c.readAt >= settings().LiveEvery) and meet ~= nil and walk ~= nil then
        c.readAt = now
        local alongs = ____exports.WaveAlongs(t, c.slot, now)
        c.n = #alongs
        if #alongs >= math.max(c.index, c.keep) + 2 then
            local v = settings().CreepSpeed
            local hit = now + (meet + c.past - alongs[c.index + 1]) / v - walk
            if c.keep > 0 and settings().HalfStepIn == true then
                hit = hit - (settings().HalfNeutralDelay + settings().HalfStepEarly)
            elseif c.keep > 0 then
                local s = Clearance(
                    t,
                    alongs,
                    c.keep,
                    now,
                    hit,
                    c.heroSpeed
                )
                if s ~= nil then
                    hit = s.hit
                    c.clear = s.clear
                    c.turn = s.turn
                    c.margin = s.margin
                    c.standBack = s.back
                    c.stand = s.stand
                end
            end
            local function pastAt(along)
                return math.floor(along + v * (hit + walk - now) - meet + 0.5)
            end
            c.hit = hit
            c.waveAt = now + (meet - alongs[#alongs]) / v
            c.next = pastAt(alongs[c.index + 1 + 1])
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
