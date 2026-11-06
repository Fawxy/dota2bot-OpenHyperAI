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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__ArraySplice(self, ...)
    local args = {...}
    local len = #self
    local actualArgumentCount = __TS__CountVarargs(...)
    local start = args[1]
    local deleteCount = args[2]
    if start < 0 then
        start = len + start
        if start < 0 then
            start = 0
        end
    elseif start > len then
        start = len
    end
    local itemCount = actualArgumentCount - 2
    if itemCount < 0 then
        itemCount = 0
    end
    local actualDeleteCount
    if actualArgumentCount == 0 then
        actualDeleteCount = 0
    elseif actualArgumentCount == 1 then
        actualDeleteCount = len - start
    else
        actualDeleteCount = deleteCount or 0
        if actualDeleteCount < 0 then
            actualDeleteCount = 0
        end
        if actualDeleteCount > len - start then
            actualDeleteCount = len - start
        end
    end
    local out = {}
    for k = 1, actualDeleteCount do
        local from = start + k
        if self[from] ~= nil then
            out[k] = self[from]
        end
    end
    if itemCount < actualDeleteCount then
        for k = start + 1, len - actualDeleteCount do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
        for k = len - actualDeleteCount + itemCount + 1, len do
            self[k] = nil
        end
    elseif itemCount > actualDeleteCount then
        for k = len - actualDeleteCount, start + 1, -1 do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
    end
    local j = start + 1
    for i = 3, actualArgumentCount do
        self[j] = args[i]
        j = j + 1
    end
    for k = #self, len - actualDeleteCount + itemCount + 1, -1 do
        self[k] = nil
    end
    return out
end

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
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
-- End of Lua Library inline imports
local ____exports = {}
local nearerLane
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local ____lane_push_data = require(GetScriptDirectory().."/FunLib/humaniser/lane_push_data")
local LANE_PATHS = ____lane_push_data.LANE_PATHS
--- Distance along the lane path of the point nearest `(x, y)`, and how far the point is from the path.
function ____exports.Project(lane, x, y)
    local bestD = math.huge
    local bestS = 0
    do
        local i = 1
        while i < #lane.pts do
            local ax, ay = lane.pts[i][1], lane.pts[i][2]
            local vx = lane.pts[i + 1][1] - ax
            local vy = lane.pts[i + 1][2] - ay
            local len2 = vx * vx + vy * vy
            local u = math.max(
                0,
                math.min(1, len2 > 0 and ((x - ax) * vx + (y - ay) * vy) / len2 or 0)
            )
            local d = math.sqrt((x - (ax + u * vx)) ^ 2 + (y - (ay + u * vy)) ^ 2)
            if d < bestD then
                bestD = d
                bestS = lane.s[i] + u * math.sqrt(len2)
            end
            i = i + 1
        end
    end
    return bestS, bestD
end
function nearerLane(lane, loc, d)
    for ____, k in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        do
            local __continue136
            repeat
                local other = LANE_PATHS[k]
                if other == lane then
                    __continue136 = true
                    break
                end
                if select(
                    2,
                    ____exports.Project(other, loc.x, loc.y)
                ) < d then
                    return true
                end
                __continue136 = true
            until true
            if not __continue136 then
                break
            end
        end
    end
    return false
end
____exports.SETTINGS = {
    Horizon = 30,
    Band = 300,
    Near = 900,
    Dt = 0.05,
    SeenR = 500,
    OurVision = 300,
    Assign = 1100,
    TargetSide = 900,
    TargetMid = 1300,
    WaveWindow = 500
}
local R = Team.Radiant
local D = Team.Dire
--- Fallback only: the lane creeps' speed is read live (WorldFacts.Latest).
local SPEED_FALLBACK = 325
local function speed()
    return WorldFacts.Latest("lane_creep_speed", SPEED_FALLBACK)
end
local REACH = 50
local FLAG_REGEN = 3
local FLAG_RADIUS = 700
local UPGRADE_EVERY = 450
--- Game files (npc_units.txt, npc_abilities.txt), as lane_sim.js; its header has the sources.
____exports.KINDS = {
    melee = {
        hp = 550,
        regen = 0.5,
        armor = 2,
        dmg = 21,
        bat = 1,
        point = 0.467,
        range = 100,
        acq = 500,
        proj = 0,
        heavy = false
    },
    flag = {
        hp = 550,
        regen = 0.5,
        armor = 2,
        dmg = 21,
        bat = 1,
        point = 0.467,
        range = 100,
        acq = 500,
        proj = 0,
        heavy = false,
        aura = true
    },
    ranged = {
        hp = 300,
        regen = 2,
        armor = 0,
        dmg = 23.5,
        bat = 1,
        point = 0.5,
        range = 500,
        acq = 600,
        proj = 900,
        heavy = false
    },
    siege = {
        hp = 935,
        regen = 0,
        armor = 0,
        dmg = 40.5,
        bat = 3,
        point = 0.7,
        range = 690,
        acq = 800,
        proj = 1100,
        heavy = true
    },
    tower1 = {
        hp = 1800,
        regen = 0,
        armor = 12,
        dmg = 90,
        bat = 0.9,
        point = 0.6,
        range = 700,
        acq = 700,
        proj = 750,
        heavy = true,
        building = true
    }
}
local function armorMult(a)
    return 1 - 0.06 * a / (1 + 0.06 * math.abs(a))
end
local function damage(a, b)
    local d = a.dmg
    if a.kind == "ranged" then
        d = d * (b.heavy and 0.35 or 1.5)
    elseif a.heavy and b.heavy then
        d = d * 2.5
    elseif not a.heavy and b.heavy then
        d = d * 0.7
    end
    return d * armorMult(b.armor)
end
local function rank(a, b)
    local ____type = b.building == true and 0 or (b.kind == "siege" and 2 or 1)
    if a.kind == "siege" then
        return ____type
    end
    return ____type == 1 and 0 or (____type == 2 and 1 or 2)
end
local function makeUnit(team, kind, s, t)
    local k = ____exports.KINDS[kind]
    return __TS__ObjectAssign({}, k, {
        team = team,
        kind = kind,
        s = s,
        maxhp = k.hp,
        readyAt = t,
        alive = true
    })
end
local function dirOf(team)
    return team == R and 1 or -1
end
--- The wave `team` spawns at second `t` (a multiple of 30), at `spawnS`: 3 melee (one a flagbearer on the minute from
-- 2:00), 1 ranged 150 behind, a siege every 5:00; +12 HP and +1 (ranged +2) damage every 7:30.
function ____exports.WaveAt(team, t, spawnS)
    local up = math.floor(t / UPGRADE_EVERY)
    local kinds = {"melee", "melee", "melee", "ranged"}
    if t >= 120 and t % 60 == 0 then
        kinds[3] = "flag"
    end
    if t >= 300 and t % 300 == 0 then
        kinds[#kinds + 1] = "siege"
    end
    return __TS__ArrayMap(
        kinds,
        function(____, kind)
            local behind = kind == "ranged" and -150 * dirOf(team) or 0
            local u = makeUnit(team, kind, spawnS + behind, t)
            if kind ~= "siege" then
                u.hp = u.hp + 12 * up
                u.maxhp = u.maxhp + 12 * up
                u.dmg = u.dmg + (kind == "ranged" and 2 or 1) * up
            end
            return u
        end
    )
end
local function round3(x)
    return math.floor(x * 1000 + 0.5) / 1000
end
--- One lane from `from` to `until` (s), mean damage. `init` creeps start at `from` (given, even empty, no wave spawns at
-- `from` itself);
-- `towerHp[team]` starts that team's T1 at a value, undefined leaves it at full, false leaves it out (down).
-- `skip` leaves out one team's wave spawning at second `skip.t` (a wave pulled before it reaches the lane).
-- Returns a sample of both leads every second from `from`.
function ____exports.Run(lane, from, ____until, init, towerHp, skip)
    local dt = ____exports.SETTINGS.Dt
    local units = {}
    for ____, tw in ipairs(lane.towers) do
        do
            local __continue19
            repeat
                local hp = towerHp[tw.team]
                if hp == false then
                    __continue19 = true
                    break
                end
                local u = makeUnit(tw.team, "tower1", tw.s, from)
                if hp ~= nil then
                    u.hp = hp
                end
                units[#units + 1] = u
                __continue19 = true
            until true
            if not __continue19 then
                break
            end
        end
    end
    for ____, c in ipairs(init or ({})) do
        local u = makeUnit(c.team, c.kind, c.s, from)
        if c.maxhp ~= nil then
            u.maxhp = c.maxhp
        end
        u.hp = c.hp
        units[#units + 1] = u
    end
    local projectiles = {}
    local samples = {}
    local dead = {[R] = 0, [D] = 0}
    local function hit(v, dmg)
        v.hp = v.hp - dmg
        if v.hp <= 0 and v.alive then
            v.alive = false
            if v.building ~= true then
                local ____dead_0, ____v_team_1 = dead, v.team
                ____dead_0[____v_team_1] = ____dead_0[____v_team_1] + 1
            end
        end
    end
    local function inReach(u, v, r)
        return math.abs(v.s - u.s) <= r + REACH
    end
    local live = {}
    local function best(u, r)
        local pick
        local key = math.huge
        for ____, v in ipairs(live) do
            do
                local __continue31
                repeat
                    if v.team == u.team or not v.alive or not inReach(u, v, r) then
                        __continue31 = true
                        break
                    end
                    local k = rank(u, v) * 1000000 + math.abs(v.s - u.s)
                    if k < key then
                        key = k
                        pick = v
                    end
                    __continue31 = true
                until true
                if not __continue31 then
                    break
                end
            end
        end
        return pick
    end
    local nextSample = from
    do
        local t = from
        while t <= ____until + 1e-9 do
            if math.abs(t % 30) < dt / 2 and not (init ~= nil and t < from + dt / 2) then
                local ts = math.floor(t + 0.5)
                if (skip and skip.team) ~= R or skip.t ~= ts then
                    for ____, u in ipairs(____exports.WaveAt(R, ts, lane.spawnR)) do
                        units[#units + 1] = u
                    end
                end
                if (skip and skip.team) ~= D or skip.t ~= ts then
                    for ____, u in ipairs(____exports.WaveAt(D, ts, lane.spawnD)) do
                        units[#units + 1] = u
                    end
                end
            end
            live = {}
            for ____, u in ipairs(units) do
                if u.alive then
                    live[#live + 1] = u
                end
            end
            for ____, u in ipairs(live) do
                local r = u.regen
                if u.building ~= true then
                    for ____, f in ipairs(live) do
                        if f.aura == true and f.team == u.team and math.abs(f.s - u.s) <= FLAG_RADIUS then
                            r = r + FLAG_REGEN
                            break
                        end
                    end
                end
                u.hp = math.min(u.maxhp, u.hp + r * dt)
            end
            for ____, u in ipairs(live) do
                do
                    local __continue52
                    repeat
                        if u.target ~= nil and not u.target.alive then
                            u.target = nil
                            u.swingAt = nil
                        end
                        if u.swingAt ~= nil then
                            __continue52 = true
                            break
                        end
                        if u.target ~= nil then
                            local b = best(u, u.range)
                            if b ~= nil and (rank(u, b) < rank(u, u.target) or not inReach(u, u.target, u.range)) then
                                u.target = b
                            elseif not inReach(u, u.target, u.acq) and b == nil then
                                u.target = nil
                            end
                        end
                        if u.target == nil then
                            u.target = best(u, u.acq)
                        end
                        __continue52 = true
                    until true
                    if not __continue52 then
                        break
                    end
                end
            end
            for ____, u in ipairs(live) do
                local v = u.target
                if v ~= nil and math.abs(v.s - u.s) <= u.range + REACH then
                    if u.swingAt == nil and t >= u.readyAt then
                        u.swingAt = t + u.point
                        u.readyAt = t + u.bat
                    end
                    if u.swingAt ~= nil and t >= u.swingAt then
                        u.swingAt = nil
                        local dmg = damage(u, v)
                        if u.proj > 0 then
                            projectiles[#projectiles + 1] = {
                                at = t + math.abs(v.s - u.s) / u.proj,
                                dst = v,
                                dmg = dmg
                            }
                        else
                            hit(v, dmg)
                        end
                    end
                elseif u.building ~= true then
                    u.swingAt = nil
                    local goal = v ~= nil and (v.s > u.s and 1 or (v.s < u.s and -1 or 0)) or dirOf(u.team)
                    u.s = u.s + goal * speed() * dt
                end
            end
            do
                local i = #projectiles - 1
                while i >= 0 do
                    local p = projectiles[i + 1]
                    if t >= p.at then
                        if p.dst.alive then
                            hit(p.dst, p.dmg)
                        end
                        __TS__ArraySplice(projectiles, i, 1)
                    end
                    i = i - 1
                end
            end
            if t >= nextSample then
                local front = {}
                for ____, u in ipairs(units) do
                    do
                        local __continue72
                        repeat
                            if not u.alive or u.building == true then
                                __continue72 = true
                                break
                            end
                            local f = front[u.team]
                            front[u.team] = f == nil and u.s or (u.team == R and math.max(f, u.s) or math.min(f, u.s))
                            __continue72 = true
                        until true
                        if not __continue72 then
                            break
                        end
                    end
                end
                samples[#samples + 1] = {t = nextSample, front = front, dead = {[R] = dead[R], [D] = dead[D]}}
                nextSample = nextSample + 1
            end
            t = round3(t + dt)
        end
    end
    return samples
end
--- Mean of the two leads' midpoint over t-2..t+2 (each second's first sample at or after it); undefined under 3 seconds.
function ____exports.ClashAt(samples, t)
    local sum = 0
    local n = 0
    do
        local u = t - 2
        while u <= t + 2 do
            local smp
            for ____, x in ipairs(samples) do
                if x.t >= u then
                    smp = x
                    break
                end
            end
            local a = smp and smp.front[R]
            local b = smp and smp.front[D]
            if a ~= nil and b ~= nil then
                sum = sum + (a + b) / 2
                n = n + 1
            end
            u = u + 1
        end
    end
    return n >= 3 and sum / n or nil
end
function ____exports.StateOf(move)
    return move > ____exports.SETTINGS.Band and "OUT" or (move < -____exports.SETTINGS.Band and "IN" or "HOLD")
end
--- EC-079: a clash within Near of a T1 bounces away from it; undefined elsewhere.
function ____exports.TowerRule(lane, clash, team)
    for ____, tw in ipairs(lane.towers) do
        if math.abs(clash - tw.s) <= ____exports.SETTINGS.Near then
            return tw.team == team and "OUT" or "IN"
        end
    end
    return nil
end
local function maxHp(kind, t0)
    return ____exports.KINDS[kind].hp + (kind == "siege" and 0 or 12 * math.floor(t0 / UPGRADE_EVERY))
end
--- The start state from team `v`'s view at second `t0`: own and visible enemy creeps (HP clipped to the kind's maximum), plus
-- each enemy wave spawned in the last 90 s that nothing would see, placed by the schedule at full HP (push.js `initView`).
function ____exports.ViewStart(lane, v, t0, own, enemy)
    local e = v == R and D or R
    local de = dirOf(e)
    local init = {}
    local lead
    for ____, c in ipairs(own) do
        init[#init + 1] = {
            team = v,
            kind = c.kind,
            s = c.s,
            hp = math.min(
                c.hp,
                maxHp(c.kind, t0)
            ),
            maxhp = maxHp(c.kind, t0)
        }
        if lead == nil or dirOf(v) * (c.s - lead) > 0 then
            lead = c.s
        end
    end
    for ____, c in ipairs(enemy) do
        init[#init + 1] = {
            team = e,
            kind = c.kind,
            s = c.s,
            hp = math.min(
                c.hp,
                maxHp(c.kind, t0)
            ),
            maxhp = maxHp(c.kind, t0)
        }
    end
    local spawnE = e == R and lane.spawnR or lane.spawnD
    do
        local ts = math.floor(t0 / 30) * 30
        while ts >= t0 - 90 and ts >= 0 do
            do
                local __continue93
                repeat
                    local pos = spawnE + de * speed() * (t0 - ts)
                    local seen = false
                    for ____, c in ipairs(enemy) do
                        if math.abs(c.s - pos) <= ____exports.SETTINGS.SeenR then
                            seen = true
                        end
                    end
                    if seen then
                        __continue93 = true
                        break
                    end
                    if lead ~= nil and de * (pos - lead) >= -____exports.SETTINGS.OurVision then
                        __continue93 = true
                        break
                    end
                    for ____, u in ipairs(____exports.WaveAt(e, ts, spawnE)) do
                        init[#init + 1] = {
                            team = e,
                            kind = u.kind,
                            s = u.s - spawnE + pos,
                            hp = u.hp,
                            maxhp = u.maxhp
                        }
                    end
                    __continue93 = true
                until true
                if not __continue93 then
                    break
                end
            end
            ts = ts - 30
        end
    end
    return init
end
--- The reading for a start state. Undefined when the run leaves no clash (a lane with no creeps of one team).
function ____exports.ReadFrom(lane, team, t0, init, towerHp)
    local clock = RealTime ~= nil and RealTime or nil
    local started = clock and clock()
    local h = ____exports.SETTINGS.Horizon
    local dir = dirOf(team)
    local function moveOf(list)
        local smp = ____exports.Run(
            lane,
            t0,
            t0 + h + 2,
            list,
            towerHp
        )
        local c0 = ____exports.ClashAt(smp, t0)
        local cH = ____exports.ClashAt(smp, t0 + h)
        return {c0, c0 ~= nil and cH ~= nil and dir * (cH - c0) or nil}
    end
    local c0, move = unpack(moveOf(init))
    if c0 == nil or move == nil then
        return nil
    end
    local ours = __TS__ArrayFind(
        lane.towers,
        function(____, tw) return tw.team == team end
    )
    local theirs = __TS__ArrayFind(
        lane.towers,
        function(____, tw) return tw.team ~= team end
    )
    local tower = ____exports.TowerRule(lane, c0, team)
    local reading = {
        state = tower or ____exports.StateOf(move),
        clash = c0,
        move = move,
        q = (c0 - ours.s) / (theirs.s - ours.s),
        own = dir * (c0 - ours.s),
        tower = tower ~= nil
    }
    if started ~= nil then
        reading.ms = math.floor((clock() - started) * 10000 + 0.5) / 10
    end
    return reading
end
--- Where the schedule puts `team`'s wave spawned at `ts` at second `t0`.
local function waveSpot(lane, team, ts, t0)
    return (team == R and lane.spawnR or lane.spawnD) + dirOf(team) * speed() * (t0 - ts)
end
--- `team`'s view `init` at `t0` with its wave spawned at `ts` removed (its creeps near the schedule's spot, or the spawn left
-- out when it is still to come), run to `at`. A wave off its schedule (a creep block, already fighting) is not found and
-- stays in the run (`pw` 0). CANDIDATE(wave_gone): the pull trigger is its one reader.
function ____exports.WaveGoneFrom(lane, team, t0, init, towerHp, ts, at)
    local spawned = t0 >= ts
    local function inWave(c)
        return spawned and math.abs(c.s - waveSpot(lane, c.team, ts, t0)) <= ____exports.SETTINGS.WaveWindow
    end
    local left = {}
    local ap = 0
    local ep = 0
    local found = not spawned
    for ____, c in ipairs(init) do
        do
            local __continue110
            repeat
                if c.team == team and inWave(c) then
                    found = true
                    __continue110 = true
                    break
                end
                left[#left + 1] = c
                if c.team == team then
                    ap = ap + c.hp
                elseif not inWave(c) then
                    ep = ep + c.hp
                end
                __continue110 = true
            until true
            if not __continue110 then
                break
            end
        end
    end
    local ____exports_Run_14 = ____exports.Run
    local ____array_13 = __TS__SparseArrayNew(
        lane,
        t0,
        at + 2,
        left,
        towerHp
    )
    local ____spawned_12
    if spawned then
        ____spawned_12 = nil
    else
        ____spawned_12 = {team = team, t = ts}
    end
    __TS__SparseArrayPush(____array_13, ____spawned_12)
    local smp = ____exports_Run_14(__TS__SparseArraySpread(____array_13))
    local clash = ____exports.ClashAt(smp, at)
    local ours = __TS__ArrayFind(
        lane.towers,
        function(____, tw) return tw.team == team end
    )
    return {
        own = clash ~= nil and dirOf(team) * (clash - ours.s) or nil,
        ap = ap,
        ep = ep,
        pw = found and 1 or 0
    }
end
function ____exports.PathOf(lane)
    return LANE_PATHS[lane]
end
--- `team`'s T1 on the path, and the sign that turns a path distance into "towards their T1".
function ____exports.OwnT1(lane, team)
    return __TS__ArrayFind(
        lane.towers,
        function(____, tw) return tw.team == team end
    ).s, dirOf(team)
end
--- When `team`'s next wave reaches path distance `s`, at or after `now`: waves spawn every 30 s from 0:00 (WaveAt) at the
-- team's spawn end and walk the path at the lane creeps' 325.
function ____exports.NextArrival(lane, team, s, now)
    local spawn = team == R and lane.spawnR or lane.spawnD
    local travel = math.abs(s - spawn) / speed()
    local k = math.max(
        0,
        math.ceil((now - travel) / 30)
    )
    return k * 30 + travel
end
local function kindOf(name)
    if (string.find(name, "siege", 1, true)) ~= nil then
        return "siege"
    end
    if (string.find(name, "creep_goodguys", 1, true)) == nil and (string.find(name, "creep_badguys", 1, true)) == nil then
        return nil
    end
    if (string.find(name, "ranged", 1, true)) ~= nil then
        return "ranged"
    end
    if (string.find(name, "flag", 1, true)) ~= nil then
        return "flag"
    end
    return "melee"
end
function ____exports.IsLaneCreep(name)
    return kindOf(name) ~= nil
end
--- Lane creeps of a unit list on this lane's path (alive; visible only for `visibleOnly`), as start creeps of `team`.
local function creepsOn(lane, units, team, visibleOnly)
    local out = {}
    for ____, u in ipairs(units) do
        do
            local __continue130
            repeat
                if not u:IsAlive() or visibleOnly and not u:CanBeSeen() then
                    __continue130 = true
                    break
                end
                local kind = kindOf(u:GetUnitName())
                if kind == nil then
                    __continue130 = true
                    break
                end
                local loc = u:GetLocation()
                local s, d = ____exports.Project(lane, loc.x, loc.y)
                if d > ____exports.SETTINGS.Assign or nearerLane(lane, loc, d) then
                    __continue130 = true
                    break
                end
                out[#out + 1] = {
                    team = team,
                    kind = kind,
                    s = s,
                    hp = u:GetHealth()
                }
                __continue130 = true
            until true
            if not __continue130 then
                break
            end
        end
    end
    return out
end
local T1 = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
local function t1Hp(team, lane)
    local t = GetTower(team, T1[lane])
    local ____temp_15
    if t == nil or t == nil or not t:IsAlive() then
        ____temp_15 = false
    else
        ____temp_15 = t:GetHealth()
    end
    return ____temp_15
end
--- `team`'s view of `lane` at the whole second now: the start creeps and T1 HP a run begins from.
local function viewNow(team, lane)
    local path = LANE_PATHS[lane]
    local t0 = math.floor(DotaTime())
    if path == nil then
        return nil, t0, {}, {}
    end
    local enemy = team == R and D or R
    local init = ____exports.ViewStart(
        path,
        team,
        t0,
        creepsOn(
            path,
            GetUnitList(UnitType.AlliedCreeps),
            team,
            false
        ),
        creepsOn(
            path,
            GetUnitList(UnitType.EnemyCreeps),
            enemy,
            true
        )
    )
    return path, t0, init, {
        [team] = t1Hp(team, lane),
        [enemy] = t1Hp(enemy, lane)
    }
end
--- The reading for `team`'s side of `lane` now (the calling script must be `team`'s).
function ____exports.Read(team, lane)
    local path, t0, init, towerHp = viewNow(team, lane)
    if path == nil then
        return nil
    end
    return ____exports.ReadFrom(
        path,
        team,
        t0,
        init,
        towerHp
    )
end
--- The lane's target meeting point, as a distance along the lane from our T1.
function ____exports.TargetOf(lane)
    return lane == Lane.Mid and ____exports.SETTINGS.TargetMid or ____exports.SETTINGS.TargetSide
end
--- `team`'s view of `lane` now with its wave spawned at `ts` pulled away (WaveGoneFrom).
function ____exports.WaveGoneNow(team, lane, ts, at)
    local path, t0, init, towerHp = viewNow(team, lane)
    if path == nil then
        return nil
    end
    return ____exports.WaveGoneFrom(
        path,
        team,
        t0,
        init,
        towerHp,
        ts,
        at
    )
end
--- One run of `lane` from `team`'s view now, `horizon` seconds ahead: its samples and the path, or undefined.
function ____exports.Forecast(team, lane, horizon)
    local path, t0, init, towerHp = viewNow(team, lane)
    if path == nil then
        return nil, nil
    end
    return ____exports.Run(
        path,
        t0,
        t0 + horizon,
        init,
        towerHp
    ), path
end
--- The map point at distance `s` along the lane path.
function ____exports.PointAt(lane, s)
    local n = #lane.pts
    if s <= lane.s[1] then
        return {lane.pts[1][1], lane.pts[1][2]}
    end
    do
        local i = 1
        while i < n do
            if s <= lane.s[i + 1] then
                local u = (s - lane.s[i]) / math.max(1e-9, lane.s[i + 1] - lane.s[i])
                return {lane.pts[i][1] + u * (lane.pts[i + 1][1] - lane.pts[i][1]), lane.pts[i][2] + u * (lane.pts[i + 1][2] - lane.pts[i][2])}
            end
            i = i + 1
        end
    end
    return {lane.pts[n][1], lane.pts[n][2]}
end
return ____exports
