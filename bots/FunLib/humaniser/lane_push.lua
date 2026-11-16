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

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

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
-- End of Lua Library inline imports
local ____exports = {}
local dirOf, readUntil, readingOf, segs, projectAll, nearerLane, R, D, CHUNK, SLACK, segsOf, memoAt, memoS, memoD
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local ____lane_push_data = require(GetScriptDirectory().."/FunLib/humaniser/lane_push_data")
local LANE_PATHS = ____lane_push_data.LANE_PATHS
function dirOf(team)
    return team == R and 1 or -1
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
function readUntil(t0)
    return t0 + ____exports.SETTINGS.Horizon + 2
end
function readingOf(lane, team, t0, smp)
    local h = ____exports.SETTINGS.Horizon
    local dir = dirOf(team)
    local c0 = ____exports.ClashAt(smp, t0)
    local cH = ____exports.ClashAt(smp, t0 + h)
    local move = c0 ~= nil and cH ~= nil and dir * (cH - c0) or nil
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
    return reading
end
function segs(lane)
    local g = segsOf[lane]
    if g ~= nil then
        return g
    end
    g = {
        ax = {},
        ay = {},
        vx = {},
        vy = {},
        len2 = {},
        len = {},
        s0 = {},
        lo = {},
        hi = {},
        x0 = {},
        x1 = {},
        y0 = {},
        y1 = {}
    }
    local n = #lane.pts - 1
    do
        local i = 1
        while i <= n do
            local ax = lane.pts[i][1]
            local ay = lane.pts[i][2]
            local vx = lane.pts[i + 1][1] - ax
            local vy = lane.pts[i + 1][2] - ay
            local len2 = vx * vx + vy * vy
            local ____g_ax_22 = g.ax
            ____g_ax_22[#____g_ax_22 + 1] = ax
            local ____g_ay_23 = g.ay
            ____g_ay_23[#____g_ay_23 + 1] = ay
            local ____g_vx_24 = g.vx
            ____g_vx_24[#____g_vx_24 + 1] = vx
            local ____g_vy_25 = g.vy
            ____g_vy_25[#____g_vy_25 + 1] = vy
            local ____g_len2_26 = g.len2
            ____g_len2_26[#____g_len2_26 + 1] = len2
            local ____g_len_27 = g.len
            ____g_len_27[#____g_len_27 + 1] = math.sqrt(len2)
            local ____g_s0_28 = g.s0
            ____g_s0_28[#____g_s0_28 + 1] = lane.s[i]
            i = i + 1
        end
    end
    do
        local lo = 0
        while lo < n do
            local hi = math.min(n, lo + CHUNK) - 1
            local x0 = math.huge
            local x1 = -math.huge
            local y0 = math.huge
            local y1 = -math.huge
            do
                local p = lo
                while p <= hi + 1 do
                    x0 = math.min(x0, lane.pts[p + 1][1])
                    x1 = math.max(x1, lane.pts[p + 1][1])
                    y0 = math.min(y0, lane.pts[p + 1][2])
                    y1 = math.max(y1, lane.pts[p + 1][2])
                    p = p + 1
                end
            end
            local ____g_lo_29 = g.lo
            ____g_lo_29[#____g_lo_29 + 1] = lo
            local ____g_hi_30 = g.hi
            ____g_hi_30[#____g_hi_30 + 1] = hi
            local ____g_x0_31 = g.x0
            ____g_x0_31[#____g_x0_31 + 1] = x0
            local ____g_x1_32 = g.x1
            ____g_x1_32[#____g_x1_32 + 1] = x1
            local ____g_y0_33 = g.y0
            ____g_y0_33[#____g_y0_33 + 1] = y0
            local ____g_y1_34 = g.y1
            ____g_y1_34[#____g_y1_34 + 1] = y1
            lo = lo + CHUNK
        end
    end
    segsOf[lane] = g
    return g
end
function projectAll(lane, x, y)
    local g = segs(lane)
    local box = {}
    local nearest = 0
    do
        local c = 0
        while c < #g.lo do
            local ex = x < g.x0[c + 1] and g.x0[c + 1] - x or (x > g.x1[c + 1] and x - g.x1[c + 1] or 0)
            local ey = y < g.y0[c + 1] and g.y0[c + 1] - y or (y > g.y1[c + 1] and y - g.y1[c + 1] or 0)
            box[#box + 1] = math.sqrt(ex * ex + ey * ey)
            if box[c + 1] < box[nearest + 1] then
                nearest = c
            end
            c = c + 1
        end
    end
    local function at(i)
        local ax = g.ax[i + 1]
        local ay = g.ay[i + 1]
        local vx = g.vx[i + 1]
        local vy = g.vy[i + 1]
        local len2 = g.len2[i + 1]
        local u = math.max(
            0,
            math.min(1, len2 > 0 and ((x - ax) * vx + (y - ay) * vy) / len2 or 0)
        )
        return math.sqrt((x - (ax + u * vx)) ^ 2 + (y - (ay + u * vy)) ^ 2), u
    end
    local bound = math.huge
    do
        local i = g.lo[nearest + 1]
        while i <= g.hi[nearest + 1] do
            bound = math.min(bound, (at(i)))
            i = i + 1
        end
    end
    local bestD = math.huge
    local bestS = 0
    do
        local c = 0
        while c < #g.lo do
            do
                local __continue137
                repeat
                    if box[c + 1] > bound + SLACK then
                        __continue137 = true
                        break
                    end
                    do
                        local i = g.lo[c + 1]
                        while i <= g.hi[c + 1] do
                            local d, u = at(i)
                            if d < bestD then
                                bestD = d
                                bestS = g.s0[i + 1] + u * g.len[i + 1]
                            end
                            i = i + 1
                        end
                    end
                    __continue137 = true
                until true
                if not __continue137 then
                    break
                end
            end
            c = c + 1
        end
    end
    return bestS, bestD
end
--- Distance along the lane path of the point nearest `(x, y)`, and how far the point is from the path.
function ____exports.Project(lane, x, y)
    if x ~= x or y ~= y then
        return projectAll(lane, x, y)
    end
    local clock = DotaTime ~= nil and math.floor(DotaTime()) or nil
    if clock ~= memoAt then
        memoAt = clock
        memoS = {}
        memoD = {}
    end
    local bx = memoS[lane]
    local dx = memoD[lane]
    if bx == nil or dx == nil then
        bx = {}
        dx = {}
        memoS[lane] = bx
        memoD[lane] = dx
    end
    local by = bx[x]
    local dy = dx[x]
    if by == nil or dy == nil then
        by = {}
        dy = {}
        bx[x] = by
        dx[x] = dy
    end
    local s = by[y]
    local d = dy[y]
    if s ~= nil and d ~= nil then
        return s, d
    end
    local ps, pd = projectAll(lane, x, y)
    by[y] = ps
    dy[y] = pd
    return ps, pd
end
function nearerLane(lane, loc, d)
    for ____, k in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        do
            local __continue167
            repeat
                local other = LANE_PATHS[k]
                if other == lane then
                    __continue167 = true
                    break
                end
                if select(
                    2,
                    ____exports.Project(other, loc.x, loc.y)
                ) < d then
                    return true
                end
                __continue167 = true
            until true
            if not __continue167 then
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
R = Team.Radiant
D = Team.Dire
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
        alive = true,
        ty = k.building == true and 0 or (kind == "siege" and 2 or 1)
    })
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
-- Returns a sample of both leads every second from `from`. `steps`, when given, receives each sample's step time: a run to
-- an earlier `until` from the same start is exactly the samples whose step is at or before it (Upto).
function ____exports.Run(lane, from, ____until, init, towerHp, skip, steps)
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
    local nLive = 0
    --- Live units by team (index 0 Radiant, 1 Dire), each in `units` order.
    local byTeam = {{}, {}}
    local nBy = {0, 0}
    local flags = {}
    local nFlags = 0
    local function best(u, r)
        local pick
        local key = math.huge
        local us = u.s
        local lim = r + REACH
        local siege = u.kind == "siege"
        local e = u.team == R and 1 or 0
        local list = byTeam[e + 1]
        local n = nBy[e + 1]
        do
            local i = 0
            while i < n do
                local v = list[i + 1]
                local d = v.s - us
                if d < 0 then
                    d = -d
                end
                if d <= lim then
                    local ____type = v.ty
                    local k = (siege and ____type or (____type == 1 and 0 or (____type == 2 and 1 or 2))) * 1000000 + d
                    if k < key then
                        key = k
                        pick = v
                    end
                end
                i = i + 1
            end
        end
        return pick
    end
    local nextSample = from
    local walk
    do
        local t = from
        while t <= ____until + 1e-9 do
            if math.abs(t % GameRules.WAVE_EVERY) < dt / 2 and not (init ~= nil and t < from + dt / 2) then
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
            nLive = 0
            nFlags = 0
            nBy[1] = 0
            nBy[2] = 0
            do
                local i = 0
                while i < #units do
                    local u = units[i + 1]
                    if u.alive then
                        local ____nLive_6 = nLive
                        nLive = ____nLive_6 + 1
                        live[____nLive_6 + 1] = u
                        local k = u.team == R and 0 or 1
                        local ____byTeam_index_10 = byTeam[k + 1]
                        local ____nBy_7, ____temp_8 = nBy, k + 1
                        local ____nBy_index_9 = ____nBy_7[____temp_8]
                        ____nBy_7[____temp_8] = ____nBy_index_9 + 1
                        ____byTeam_index_10[____nBy_index_9 + 1] = u
                        if u.aura == true then
                            local ____nFlags_11 = nFlags
                            nFlags = ____nFlags_11 + 1
                            flags[____nFlags_11 + 1] = u
                        end
                    end
                    i = i + 1
                end
            end
            do
                local i = 0
                while i < nLive do
                    local u = live[i + 1]
                    local r = u.regen
                    if u.building ~= true then
                        do
                            local j = 0
                            while j < nFlags do
                                local f = flags[j + 1]
                                if f.team == u.team and math.abs(f.s - u.s) <= FLAG_RADIUS then
                                    r = r + FLAG_REGEN
                                    break
                                end
                                j = j + 1
                            end
                        end
                    end
                    local hp = u.hp + r * dt
                    u.hp = hp < u.maxhp and hp or u.maxhp
                    i = i + 1
                end
            end
            do
                local i = 0
                while i < nLive do
                    local u = live[i + 1]
                    if u.target ~= nil and not u.target.alive then
                        u.target = nil
                        u.swingAt = nil
                    end
                    if u.swingAt == nil then
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
                    end
                    i = i + 1
                end
            end
            do
                local i = 0
                while i < nLive do
                    local u = live[i + 1]
                    local v = u.target
                    local gap = v ~= nil and v.s - u.s or 0
                    if gap < 0 then
                        gap = -gap
                    end
                    if v ~= nil and gap <= u.range + REACH then
                        if u.swingAt == nil and t >= u.readyAt then
                            u.swingAt = t + u.point
                            u.readyAt = t + u.bat
                        end
                        if u.swingAt ~= nil and t >= u.swingAt then
                            u.swingAt = nil
                            local dmg = damage(u, v)
                            if u.proj > 0 then
                                projectiles[#projectiles + 1] = {at = t + gap / u.proj, dst = v, dmg = dmg}
                            else
                                hit(v, dmg)
                            end
                        end
                    elseif u.building ~= true then
                        u.swingAt = nil
                        local goal = v ~= nil and (v.s > u.s and 1 or (v.s < u.s and -1 or 0)) or dirOf(u.team)
                        if walk == nil then
                            walk = speed()
                        end
                        u.s = u.s + goal * walk * dt
                    end
                    i = i + 1
                end
            end
            local np = #projectiles
            local landed = false
            do
                local i = np - 1
                while i >= 0 do
                    local p = projectiles[i + 1]
                    if t >= p.at then
                        landed = true
                        if p.dst.alive then
                            hit(p.dst, p.dmg)
                        end
                    end
                    i = i - 1
                end
            end
            if landed then
                local w = 0
                do
                    local i = 0
                    while i < np do
                        local p = projectiles[i + 1]
                        if not (t >= p.at) then
                            local ____w_12 = w
                            w = ____w_12 + 1
                            projectiles[____w_12 + 1] = p
                        end
                        i = i + 1
                    end
                end
                do
                    local i = np - 1
                    while i >= w do
                        table.remove(projectiles)
                        i = i - 1
                    end
                end
            end
            if t >= nextSample then
                local front = {}
                for ____, u in ipairs(units) do
                    do
                        local __continue74
                        repeat
                            if not u.alive or u.building == true then
                                __continue74 = true
                                break
                            end
                            local f = front[u.team]
                            front[u.team] = f == nil and u.s or (u.team == R and math.max(f, u.s) or math.min(f, u.s))
                            __continue74 = true
                        until true
                        if not __continue74 then
                            break
                        end
                    end
                end
                samples[#samples + 1] = {t = nextSample, front = front, dead = {[R] = dead[R], [D] = dead[D]}}
                if steps ~= nil then
                    steps[#steps + 1] = t
                end
                nextSample = nextSample + 1
            end
            t = round3(t + dt)
        end
    end
    return samples
end
--- The samples a run from the same start to `until` returns, out of a longer run's samples and their `steps`.
function ____exports.Upto(samples, steps, ____until)
    local out = {}
    do
        local i = 0
        while i < #samples do
            if steps[i + 1] > ____until + 1e-9 then
                break
            end
            out[#out + 1] = samples[i + 1]
            i = i + 1
        end
    end
    return out
end
local function maxHp(kind, t0)
    return ____exports.KINDS[kind].hp + (kind == "siege" and 0 or 12 * math.floor(t0 / UPGRADE_EVERY))
end
--- `team`'s lead lane creep: the path distance of its creep furthest towards the enemy; undefined with none.
function ____exports.LeadOf(own, team)
    local lead
    for ____, c in ipairs(own) do
        if lead == nil or dirOf(team) * (c.s - lead) > 0 then
            lead = c.s
        end
    end
    return lead
end
--- Where `team`'s waves spawn on the path, and the sign of their travel along it.
function ____exports.SpawnOf(lane, team)
    return team == R and lane.spawnR or lane.spawnD, dirOf(team)
end
--- The start state from team `v`'s view at second `t0`: own and visible enemy creeps (HP clipped to the kind's maximum), plus
-- each enemy wave spawned in the last 90 s that nothing would see, placed by the schedule at full HP (push.js `initView`).
function ____exports.ViewStart(lane, v, t0, own, enemy)
    local e = v == R and D or R
    local de = dirOf(e)
    local init = {}
    local lead = ____exports.LeadOf(own, v)
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
    local spawnE = ____exports.SpawnOf(lane, e)
    do
        local ts = math.floor(t0 / GameRules.WAVE_EVERY) * GameRules.WAVE_EVERY
        while ts >= t0 - 3 * GameRules.WAVE_EVERY and ts >= 0 do
            do
                local __continue103
                repeat
                    local pos = spawnE + de * speed() * (t0 - ts)
                    local seen = false
                    for ____, c in ipairs(enemy) do
                        if math.abs(c.s - pos) <= ____exports.SETTINGS.SeenR then
                            seen = true
                        end
                    end
                    if seen then
                        __continue103 = true
                        break
                    end
                    if lead ~= nil and de * (pos - lead) >= -____exports.SETTINGS.OurVision then
                        __continue103 = true
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
                    __continue103 = true
                until true
                if not __continue103 then
                    break
                end
            end
            ts = ts - GameRules.WAVE_EVERY
        end
    end
    return init
end
--- The reading for a start state. Undefined when the run leaves no clash (a lane with no creeps of one team).
function ____exports.ReadFrom(lane, team, t0, init, towerHp)
    local clock = RealTime ~= nil and RealTime or nil
    local started = clock and clock()
    local reading = readingOf(
        lane,
        team,
        t0,
        ____exports.Run(
            lane,
            t0,
            readUntil(t0),
            init,
            towerHp
        )
    )
    if reading ~= nil and started ~= nil then
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
            local __continue121
            repeat
                if c.team == team and inWave(c) then
                    found = true
                    __continue121 = true
                    break
                end
                left[#left + 1] = c
                if c.team == team then
                    ap = ap + c.hp
                elseif not inWave(c) then
                    ep = ep + c.hp
                end
                __continue121 = true
            until true
            if not __continue121 then
                break
            end
        end
    end
    local ____exports_Run_21 = ____exports.Run
    local ____array_20 = __TS__SparseArrayNew(
        lane,
        t0,
        at + 2,
        left,
        towerHp
    )
    local ____spawned_19
    if spawned then
        ____spawned_19 = nil
    else
        ____spawned_19 = {team = team, t = ts}
    end
    __TS__SparseArrayPush(____array_20, ____spawned_19)
    local smp = ____exports_Run_21(__TS__SparseArraySpread(____array_20))
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
CHUNK = 8
SLACK = 0.000001
segsOf = {}
memoS = {}
memoD = {}
--- The full scan `Project` replaced, kept for the test that holds the two equal.
function ____exports.ProjectScan(lane, x, y)
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
        math.ceil((now - travel) / GameRules.WAVE_EVERY)
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
            local __continue161
            repeat
                if not u:IsAlive() or visibleOnly and not u:CanBeSeen() then
                    __continue161 = true
                    break
                end
                local kind = kindOf(u:GetUnitName())
                if kind == nil then
                    __continue161 = true
                    break
                end
                local loc = u:GetLocation()
                local s, d = ____exports.Project(lane, loc.x, loc.y)
                if d > ____exports.SETTINGS.Assign or nearerLane(lane, loc, d) then
                    __continue161 = true
                    break
                end
                out[#out + 1] = {
                    team = team,
                    kind = kind,
                    s = s,
                    hp = u:GetHealth()
                }
                __continue161 = true
            until true
            if not __continue161 then
                break
            end
        end
    end
    return out
end
local T1 = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
local function t1Hp(team, lane)
    local t = GetTower(team, T1[lane])
    local ____temp_35
    if t == nil or t == nil or not t:IsAlive() then
        ____temp_35 = false
    else
        ____temp_35 = t:GetHealth()
    end
    return ____temp_35
end
--- The lane creeps `team`'s view of `lane` starts from at the whole second now: the path, the second, its own creeps and
-- the visible enemy creeps on the path (the enemy wave tracker reads the same).
function ____exports.CreepsNow(team, lane)
    local path = LANE_PATHS[lane]
    local t0 = math.floor(DotaTime())
    if path == nil then
        return nil, t0, {}, {}
    end
    local enemy = team == R and D or R
    return path, t0, creepsOn(
        path,
        GetUnitList(UnitType.AlliedCreeps),
        team,
        false
    ), creepsOn(
        path,
        GetUnitList(UnitType.EnemyCreeps),
        enemy,
        true
    )
end
--- By team * 10 + lane. Callers on one frame (lane_control's decide reads, forecasts and pulls the same view) share it:
-- nothing a view reads changes inside a frame, and a plain run is a function of the view and the creep speed.
local frameViews = {}
--- `team`'s view of `lane` at the whole second now: the start creeps and T1 HP a run begins from (once a frame).
local function viewNow(team, lane)
    local frame = DotaTime()
    local key = team * 10 + lane
    local had = frameViews[key]
    local walk = WorldFacts.Live().lane_creep_speed
    if had ~= nil and had.frame == frame and had.walk == walk then
        return had
    end
    local path, t0, own, enemyCreeps = ____exports.CreepsNow(team, lane)
    local v
    if path == nil then
        v = {
            frame = frame,
            walk = walk,
            t0 = t0,
            init = {},
            towerHp = {}
        }
    else
        local enemy = team == R and D or R
        v = {
            frame = frame,
            walk = walk,
            path = path,
            t0 = t0,
            init = ____exports.ViewStart(
                path,
                team,
                t0,
                own,
                enemyCreeps
            ),
            towerHp = {
                [team] = t1Hp(team, lane),
                [enemy] = t1Hp(enemy, lane)
            }
        }
    end
    frameViews[key] = v
    return v
end
--- Forgets the frame views (a new game or test world in the same VM, at a DotaTime already seen).
function ____exports.ResetFrames()
    frameViews = {}
end
--- The plain run of a view to `until`: the frame's longest run cut at `until` when it reaches that far, else a new run
-- that becomes the frame's (viewNow has already matched the creep speed).
local function runOf(v, path, ____until)
    if v.smp == nil or v["until"] < ____until then
        local steps = {}
        v.smp = ____exports.Run(
            path,
            v.t0,
            ____until,
            v.init,
            v.towerHp,
            nil,
            steps
        )
        v.steps = steps
        v["until"] = ____until
    end
    return ____exports.Upto(v.smp, v.steps, ____until)
end
--- The reading for `team`'s side of `lane` now (the calling script must be `team`'s).
function ____exports.Read(team, lane)
    local v = viewNow(team, lane)
    if v.path == nil then
        return nil
    end
    local clock = RealTime ~= nil and RealTime or nil
    local started = clock and clock()
    local reading = readingOf(
        v.path,
        team,
        v.t0,
        runOf(
            v,
            v.path,
            readUntil(v.t0)
        )
    )
    if reading ~= nil and started ~= nil then
        reading.ms = math.floor((clock() - started) * 10000 + 0.5) / 10
    end
    return reading
end
--- The lane's target meeting point, as a distance along the lane from our T1.
function ____exports.TargetOf(lane)
    return lane == Lane.Mid and ____exports.SETTINGS.TargetMid or ____exports.SETTINGS.TargetSide
end
--- `team`'s view of `lane` now with its wave spawned at `ts` pulled away (WaveGoneFrom).
function ____exports.WaveGoneNow(team, lane, ts, at)
    local v = viewNow(team, lane)
    if v.path == nil then
        return nil
    end
    return ____exports.WaveGoneFrom(
        v.path,
        team,
        v.t0,
        v.init,
        v.towerHp,
        ts,
        at
    )
end
--- One run of `lane` from `team`'s view now, `horizon` seconds ahead: its samples and the path, or undefined.
function ____exports.Forecast(team, lane, horizon)
    local v = viewNow(team, lane)
    if v.path == nil then
        return nil, nil
    end
    return runOf(v, v.path, v.t0 + horizon), v.path
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
