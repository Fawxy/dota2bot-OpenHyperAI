--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ArrayIncludes(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    local k = fromIndex
    if fromIndex < 0 then
        k = len + fromIndex
    end
    if k < 0 then
        k = 0
    end
    for i = k + 1, len do
        if self[i] == searchElement then
            return true
        end
    end
    return false
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local LaneAggro = require(GetScriptDirectory().."/FunLib/humaniser/lane_aggro")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local LaneSpot = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_spot")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
--- Pure: our T1's fire reach to a creep's centre (`reach` in the docs), from the API's values or the fallbacks.
function ____exports.EffReach(range, towerHull, creepHull)
    local function ok(x, d)
        return x ~= nil and x > 0 and x or d
    end
    return ok(range, ____exports.SETTINGS.TowerR) + ok(towerHull, ____exports.SETTINGS.TowerHull) + ok(creepHull, ____exports.SETTINGS.CreepHull)
end
local function creepSpeed()
    return WorldFacts.Latest("lane_creep_speed", ____exports.SETTINGS.CreepSpeed)
end
____exports.SETTINGS = {
    Every = 0.25,
    PathR = 600,
    MinCreeps = 2,
    StartAhead = 1600,
    TowerR = 700,
    TowerHull = 144,
    CreepHull = 16,
    LateMargin = 50,
    OursBehind = 400,
    OursAhead = 600,
    MeetR = 700,
    Reach = 2000,
    StartHp = 0.5,
    ThreatMargin = 200,
    NearSecs = 10,
    Behind = 500,
    CreepSpeed = 325,
    DrawSecs = 1,
    DragMargin = 2,
    HurtShare = 0.25,
    HurtFloor = 0.35,
    LeftAfter = 3,
    RestAfter = 15,
    MaxSecs = 45,
    Arrived = 300,
    AggroRecent = 20,
    ForecastAhead = 200,
    ForecastEvery = 1,
    ForecastSecs = 8,
    SkipEvery = 5,
    HoldDrawLead = 1,
    HoldNear = 300,
    HoldDrawOut = 150,
    TankShare = 0.15,
    CreepSpa = 1
}
--- Their wave in the stretch (our T1 distances, positive towards theirs): its count, front and rear.
function ____exports.Stretch(theirs, target)
    local n = 0
    local front = math.huge
    local rear = -math.huge
    for ____, o in ipairs(theirs) do
        do
            local __continue4
            repeat
                if o < -____exports.SETTINGS.OursBehind or o > target + ____exports.SETTINGS.StartAhead then
                    __continue4 = true
                    break
                end
                n = n + 1
                front = math.min(front, o)
                rear = math.max(rear, o)
                __continue4 = true
            until true
            if not __continue4 then
                break
            end
        end
    end
    return {n = n, front = front, rear = rear}
end
--- Pure: the trigger's reading of a lane, from our T1 distances (positive towards theirs) of the lane creeps on it; `busy[i]`
-- when ours[i] has an attack target.
function ____exports.Read(theirs, ours, target, busy, reach)
    if busy == nil then
        busy = {}
    end
    if reach == nil then
        reach = ____exports.EffReach()
    end
    local w = ____exports.Stretch(theirs, target)
    if w.n < ____exports.SETTINGS.MinCreeps then
        return "none"
    end
    do
        local i = 0
        while i < #ours do
            do
                local __continue9
                repeat
                    local o = ours[i + 1]
                    if o < ____exports.SETTINGS.TowerR and busy[i + 1] == true then
                        __continue9 = true
                        break
                    end
                    if o >= -____exports.SETTINGS.OursBehind and o <= w.rear + ____exports.SETTINGS.OursAhead then
                        return "ours"
                    end
                    __continue9 = true
                until true
                if not __continue9 then
                    break
                end
            end
            i = i + 1
        end
    end
    if w.front < reach + ____exports.SETTINGS.LateMargin then
        return "late"
    end
    return {front = w.front, n = w.n}
end
--- Pure: the hold point's distance from our T1 for the lane target and their front at the start: never past their front, never
-- inside LateMargin past the tower's reach.
function ____exports.HoldAt(target, front, reach)
    if reach == nil then
        reach = ____exports.EffReach()
    end
    return math.max(
        reach + ____exports.SETTINGS.LateMargin,
        math.min(target, front)
    )
end
--- Pure: whether a creep of ours at `own` is in the clash at the start (fighting, within our-wave reach of their rear), so
-- its fight does not end the attempt as `met`. Our next wave walking up is not.
function ____exports.InClash(own, busy, rear)
    return busy and own >= -____exports.SETTINGS.OursBehind and own <= rear + ____exports.SETTINGS.OursAhead
end
--- Pure: seconds from `t0` until lane_push's run (`samples`) has `enemy`'s front inside our T1's range, within ForecastSecs;
-- undefined when it stays out. `t1` and `dir` are our T1 on the path and the sign towards theirs.
function ____exports.TowerIn(samples, t1, dir, enemy, t0, reach)
    if reach == nil then
        reach = ____exports.EffReach()
    end
    for ____, smp in ipairs(samples) do
        if smp.t - t0 > ____exports.SETTINGS.ForecastSecs then
            break
        end
        local f = smp.front[enemy]
        if f ~= nil and dir * (f - t1) < reach then
            return smp.t - t0
        end
    end
    return nil
end
--- Pure: the branch (user 05/11/2026). `threat` an enemy hero's move on the core; `near` seconds until our next wave reaches the
-- hold point; `need` seconds the drag needs; `behind` seconds until our next wave reaches the drag's point.
function ____exports.Choose(cost, budget, need, behind)
    if cost <= budget then
        return "hold"
    end
    return need + ____exports.SETTINGS.DragMargin <= behind and "drag" or "concede"
end
--- Pure: seconds the core stands as their wave's target at the hold point `hd` before our creeps get there: our creeps' time
-- to the hold point `near` less their front's walk to it.
function ____exports.TankSecs(near, front, hd)
    return math.max(
        0,
        near - math.max(0, front - hd) / creepSpeed()
    )
end
--- Pure: the physical damage a unit with armor `a` takes per point dealt (Dota's armor formula, 1 - 0.06a / (1 + 0.06|a|)).
function ____exports.ArmorMult(a)
    return 1 - 0.06 * a / (1 + 0.06 * math.abs(a))
end
--- Pure: the wave's damage per second on one target, from each creep's attack damage and seconds per attack.
function ____exports.WaveDps(creeps, armorMult)
    local s = 0
    for ____, c in ipairs(creeps) do
        if c.spa > 0 then
            s = s + c.dmg / c.spa
        end
    end
    return s * armorMult
end
--- Pure: seconds until our next wave reaches the hold point, from the spawn schedule's `schedule` and the straight-line
-- distances to it of our lane creeps already on the map and walking.
function ____exports.Near(schedule, live)
    local d = math.huge
    for ____, x in ipairs(live) do
        d = math.min(d, x)
    end
    return math.min(
        schedule,
        d / creepSpeed()
    )
end
--- Pure: whether the hold draws their wave now: their front (from our T1) within the lead of the hold point `hd`, the core
-- `at` from it, `on` their creeps already on the core.
function ____exports.DrawNow(front, hd, at, on)
    return on == 0 and at <= ____exports.SETTINGS.HoldNear and front <= hd + ____exports.SETTINGS.HoldDrawLead * creepSpeed()
end
--- Pure: lane_spot pushed the held spot back inside the hold point's floor for an enemy hero (`why` hero, spot `own` from our
-- T1) while their front is within HoldDrawLead seconds' walk of the floor: the hold cannot stand where it keeps their wave out
-- of our T1's fire, so it ends `unsafe`. Further out the hold runs on from the pushed spot (hschk4: 7 of 13 unsafe ends were
-- Zeus mid stepping out of Sniper's reach with their front 1,100-1,440 out; user 06/11/2026: stepping back from a hero's reach
-- is right, the hold point would give Sniper free harass).
function ____exports.Unsafe(anchor, why, own, reach, front)
    local floor = reach + ____exports.SETTINGS.LateMargin
    return anchor == "hold" and why == "hero" and own < floor and front <= floor + ____exports.SETTINGS.HoldDrawLead * creepSpeed()
end
--- Pure: the drag point's distance behind our T1: out of its fire for every creep (`reach` plus LateMargin).
function ____exports.BehindAt(reach)
    if reach == nil then
        reach = ____exports.EffReach()
    end
    return math.max(____exports.SETTINGS.Behind, reach + ____exports.SETTINGS.LateMargin)
end
--- Pure: the seconds the drag needs from their front's distance from our T1, to the drag point `bd` behind it.
function ____exports.DragSecs(front, bd)
    if bd == nil then
        bd = ____exports.SETTINGS.Behind
    end
    return (front + bd) / creepSpeed() + ____exports.SETTINGS.DrawSecs
end
--- Pure: seconds until a creep of ours on the lane (our T1 distances) reaches the drag point `bd` behind our T1; 0 when one
-- already stands between it and their front, where it would meet their dragged wave inside our T1's fire.
function ____exports.OursAtBehind(ours, bd, front)
    local s = math.huge
    for ____, o in ipairs(ours) do
        do
            local __continue38
            repeat
                if o > front then
                    __continue38 = true
                    break
                end
                s = math.min(
                    s,
                    o >= -bd and 0 or (-bd - o) / creepSpeed()
                )
                __continue38 = true
            until true
            if not __continue38 then
                break
            end
        end
    end
    return s
end
local attempts = {}
local decidedAt = {}
local endedAt = {}
local skippedAt = {}
local forecastAt = {}
local function counter(bot, name)
    local f = bot[name]
    return f ~= nil and f(bot) or 0
end
local function frac(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
end
--- Whether the hold may act for this bot: the switches, an in-lane core under CoreLastHit with our spot.
function ____exports.Owns(bot)
    return Ours.On("CoreHold") and Ours.On("LaneSpot") and CoreLastHit.Applies(bot) and bot:IsAlive() and Phase.IsLaningFor(bot)
end
local T1_OF = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
--- Our T1's reach on this lane from the API, with a creep of theirs (when one is in view) for the creep hull.
local function towerReach(team, lane, v)
    local t = GetTower(team, T1_OF[lane])
    local alive = t ~= nil and t ~= nil and not t:IsNull() and t:IsAlive()
    local c = #v.units > 0 and v.units[1].u or nil
    return ____exports.EffReach(
        alive and t:GetAttackRange() or nil,
        alive and t:GetBoundingRadius() or nil,
        c ~= nil and c:GetBoundingRadius() or nil
    )
end
local function fighting(c)
    local t = c:GetAttackTarget()
    return t ~= nil and t ~= nil and not t:IsNull()
end
local function viewOf(team, lane)
    local path = LanePush.PathOf(lane)
    if path == nil then
        return nil
    end
    local t1, dir = LanePush.OwnT1(path, team)
    local function project(list, keep)
        local out = {}
        for ____, c in ipairs(list) do
            do
                local __continue49
                repeat
                    if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                        __continue49 = true
                        break
                    end
                    local l = c:GetLocation()
                    if l == nil then
                        __continue49 = true
                        break
                    end
                    local s, d = LanePush.Project(path, l.x, l.y)
                    if d > ____exports.SETTINGS.PathR then
                        __continue49 = true
                        break
                    end
                    local own = dir * (s - t1)
                    out[#out + 1] = own
                    local ____opt_0 = keep
                    if ____opt_0 ~= nil then
                        keep[#keep + 1] = {u = c, own = own}
                    end
                    __continue49 = true
                until true
                if not __continue49 then
                    break
                end
            end
        end
        return out
    end
    local units = {}
    local theirs = project(
        GetUnitList(UnitType.EnemyCreeps),
        units
    )
    local mine = {}
    local ours = project(
        GetUnitList(UnitType.AlliedCreeps),
        mine
    )
    local busy = __TS__ArrayMap(
        mine,
        function(____, m) return fighting(m.u) end
    )
    return {
        path = path,
        t1 = t1,
        dir = dir,
        theirs = theirs,
        ours = ours,
        busy = busy,
        units = units,
        mine = mine
    }
end
local function pointAt(v, own, z)
    local x, y = unpack(LanePush.PointAt(v.path, v.t1 + v.dir * own))
    return Vector(x, y, z)
end
--- Distances to the hold point of our lane creeps within NearSecs' walk of it that have no attack target.
local function walkingTo(hold)
    local out = {}
    local r = ____exports.SETTINGS.NearSecs * creepSpeed()
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue57
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue57 = true
                    break
                end
                local t = c:GetAttackTarget()
                if t ~= nil and t ~= nil and not t:IsNull() then
                    __continue57 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, hold)
                if d <= r then
                    out[#out + 1] = d
                end
                __continue57 = true
            until true
            if not __continue57 then
                break
            end
        end
    end
    return out
end
local function whyGone(bot, now)
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue63
                repeat
                    local h = GetTeamMember(i)
                    if h == nil or h == nil or h:IsNull() then
                        __continue63 = true
                        break
                    end
                    if h:GetAssignedLane() == lane and PullJob.Running(h) then
                        return "pull"
                    end
                    __continue63 = true
                until true
                if not __continue63 then
                    break
                end
            end
            i = i + 1
        end
    end
    local at = LaneAggro.TowerMovedAt(bot:GetPlayerID())
    if at ~= nil and now - at <= ____exports.SETTINGS.AggroRecent then
        return "aggro"
    end
    return "other"
end
--- The visible enemy hero whose reach covers the core or the hold point, if any.
local function threatOf(bot, hold)
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None)) do
        do
            local __continue68
            repeat
                if h == nil or h == nil or h:IsNull() or not h:IsAlive() or h:IsIllusion() then
                    __continue68 = true
                    break
                end
                local r = LaneSpot.HeroReach(bot, h) + ____exports.SETTINGS.ThreatMargin
                if GetUnitToUnitDistance(bot, h) <= r or GetUnitToLocationDistance(h, hold) <= r then
                    return h
                end
                __continue68 = true
            until true
            if not __continue68 then
                break
            end
        end
    end
    return nil
end
local function finish(bot, a, res, now)
    local pid = bot:GetPlayerID()
    attempts[pid] = nil
    if res ~= "left" then
        endedAt[pid] = now
    end
    Laning.SetHold(bot, nil)
    Telemetry.Event(
        "wave_hold",
        {
            {"pid", pid},
            {"lane", a.lane},
            {"br", a.br},
            {"res", res},
            {"why", a.why},
            {"trig", a.trig},
            {
                "fc",
                a.fc ~= nil and math.floor(a.fc * 10) / 10 or nil
            },
            {
                "hd",
                math.floor(a.hd)
            },
            {
                "rch",
                math.floor(a.rch)
            },
            {"hdr", a.hdr},
            {"n", a.n},
            {
                "lh",
                counter(bot, "GetLastHits") - a.lh0
            },
            {
                "dn",
                counter(bot, "GetDenies") - a.dn0
            },
            {
                "own0",
                math.floor(a.own0)
            },
            {
                "omin",
                math.floor(a.omin)
            },
            {
                "mo",
                a.mo ~= nil and math.floor(a.mo) or nil
            },
            {"tw", a.tw},
            {"tgt", a.tgt},
            {
                "nw",
                math.floor(a.nw * 10) / 10
            },
            {
                "ds",
                a.ds ~= nil and math.floor(a.ds * 10) / 10 or nil
            },
            {
                "nb",
                a.nb ~= nil and math.floor(a.nb * 10) / 10 or nil
            },
            {
                "nl",
                a.nl ~= nil and math.floor(a.nl * 10) / 10 or nil
            },
            {"lv", a.lv},
            {
                "tk",
                a.tk ~= nil and math.floor(a.tk * 10) / 10 or nil
            },
            {
                "cost",
                a.cost ~= nil and math.floor(a.cost) or nil
            },
            {
                "bud",
                a.bud ~= nil and math.floor(a.bud) or nil
            },
            {"thr", a.thr},
            {"sw", a.sw},
            {
                "hp",
                math.floor(a.hp0 / math.max(
                    1,
                    bot:GetMaxHealth()
                ) * 100) / 100
            },
            {"dhp", a.hp0 - a.hpMin},
            {
                "dur",
                math.floor((now - a.startedAt) * 100) / 100
            },
            {
                "md",
                (res == "left" or res == "died") and bot:GetActiveMode() or nil
            }
        }
    )
end
--- Every frame (States.Tick): an attempt whose caller lost the frame ends, `retreat` when OHA's retreat holds the core.
function ____exports.Tick(bot)
    local a = attempts[bot:GetPlayerID()]
    if a == nil then
        return
    end
    local now = DotaTime()
    if not bot:IsAlive() then
        return finish(bot, a, "died", now)
    end
    if now - a.steppedAt <= ____exports.SETTINGS.LeftAfter then
        return
    end
    if bot:GetActiveMode() == BotMode.Retreat then
        a.br = "retreat"
    end
    finish(bot, a, "left", now)
end
--- Why a start was refused (`reach`, `hp`), or the attempt.
local function begin(bot, v, front, n, rear, reach, now, trig, fc)
    local lane = bot:GetAssignedLane()
    local tgt = LanePush.TargetOf(lane)
    local z = bot:GetLocation().z
    local hd = ____exports.HoldAt(tgt, front, reach)
    local hold = pointAt(v, hd, z)
    if GetUnitToLocationDistance(bot, hold) > ____exports.SETTINGS.Reach then
        return "reach"
    end
    if frac(bot) < ____exports.SETTINGS.StartHp then
        return "hp"
    end
    local nw = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 + v.dir * hd,
        now
    ) - now
    local old = {}
    do
        local i = 0
        while i < #v.mine do
            if ____exports.InClash(v.mine[i + 1].own, v.busy[i + 1], rear) then
                old[#old + 1] = v.mine[i + 1].u
            end
            i = i + 1
        end
    end
    return {
        lane = lane,
        br = "hold",
        sw = 0,
        startedAt = now,
        steppedAt = now,
        hold = hold,
        behind = pointAt(
            v,
            -____exports.BehindAt(reach),
            z
        ),
        bd = ____exports.BehindAt(reach),
        hdr = 0,
        why = trig == "forecast" and "losing" or whyGone(bot, now),
        trig = trig,
        fc = fc,
        hd = hd,
        rch = reach,
        old = old,
        n = n,
        lh0 = counter(bot, "GetLastHits"),
        dn0 = counter(bot, "GetDenies"),
        own0 = front,
        omin = front,
        tw = 0,
        tgt = tgt,
        nw = nw,
        hp0 = bot:GetHealth(),
        hpMin = bot:GetHealth(),
        readAt = -math.huge
    }
end
--- One ev=wave_hold_skip per bot and reason per SkipEvery.
local function skip(bot, v, why, front, n, reach, now, fc)
    local key = (tostring(bot:GetPlayerID()) .. ":") .. why
    local at = skippedAt[key]
    if at ~= nil and now - at < ____exports.SETTINGS.SkipEvery then
        return
    end
    skippedAt[key] = now
    local on = 0
    local oin = 0
    for ____, o in ipairs(v.ours) do
        do
            local __continue86
            repeat
                if o < -____exports.SETTINGS.OursBehind then
                    __continue86 = true
                    break
                end
                if o < ____exports.SETTINGS.TowerR then
                    oin = oin + 1
                else
                    on = on + 1
                end
                __continue86 = true
            until true
            if not __continue86 then
                break
            end
        end
    end
    local ob
    local obt
    if why == "ours" or why == "ours_far" then
        local w = ____exports.Stretch(
            v.theirs,
            LanePush.TargetOf(bot:GetAssignedLane())
        )
        do
            local i = 0
            while i < #v.mine do
                do
                    local __continue92
                    repeat
                        local o = v.mine[i + 1].own
                        if o < ____exports.SETTINGS.TowerR and v.busy[i + 1] then
                            __continue92 = true
                            break
                        end
                        if o >= -____exports.SETTINGS.OursBehind and o <= w.rear + ____exports.SETTINGS.OursAhead then
                            ob = o
                            local t = v.mine[i + 1].u:GetAttackTarget()
                            local ____temp_5
                            if t == nil or t == nil or t:IsNull() then
                                ____temp_5 = "none"
                            else
                                local ____t_IsHero_result_4
                                if t:IsHero() then
                                    ____t_IsHero_result_4 = "hero"
                                else
                                    local ____this_3
                                    ____this_3 = t
                                    local ____opt_2 = ____this_3.IsTower
                                    ____t_IsHero_result_4 = (____opt_2 and ____opt_2(____this_3)) == true and "tower" or (LanePush.IsLaneCreep(t:GetUnitName()) and "lane" or "other")
                                end
                                ____temp_5 = ____t_IsHero_result_4
                            end
                            obt = ____temp_5
                            break
                        end
                        __continue92 = true
                    until true
                    if not __continue92 then
                        break
                    end
                end
                i = i + 1
            end
        end
    end
    Telemetry.Event(
        "wave_hold_skip",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "lane",
                bot:GetAssignedLane()
            },
            {"why", why},
            {
                "front",
                math.floor(front)
            },
            {"n", n},
            {"on", on},
            {"oin", oin},
            {
                "rch",
                math.floor(reach)
            },
            {
                "fc",
                fc ~= nil and math.floor(fc * 10) / 10 or nil
            },
            {
                "ob",
                ob ~= nil and math.floor(ob) or nil
            },
            {"obt", obt}
        }
    )
end
--- Whether no creep of ours on the lane is fighting a lane creep or a hero (their wave is walking in unopposed).
local function notOnWave(v)
    for ____, m in ipairs(v.mine) do
        local t = m.u:GetAttackTarget()
        if t ~= nil and t ~= nil and not t:IsNull() and (t:IsHero() or LanePush.IsLaneCreep(t:GetUnitName())) then
            return false
        end
    end
    return true
end
--- lane_push's run for the forecast start, at most every ForecastEvery per bot: seconds until their front is inside our T1's
-- range, or undefined (also when the run fails or was read too recently: `false`).
local function forecastIn(bot, v, reach, now)
    local pid = bot:GetPlayerID()
    local at = forecastAt[pid]
    if at ~= nil and now - at < ____exports.SETTINGS.ForecastEvery then
        return false
    end
    forecastAt[pid] = now
    local ok, r = pcall(function()
        local smp = LanePush.Forecast(
            bot:GetTeam(),
            bot:GetAssignedLane(),
            ____exports.SETTINGS.ForecastSecs + 1
        )
        return smp
    end)
    local ____ok_6
    if ok then
        ____ok_6 = r
    else
        ____ok_6 = nil
    end
    local samples = ____ok_6
    if samples == nil or #samples == 0 then
        return nil
    end
    local enemy = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
    return ____exports.TowerIn(
        samples,
        v.t1,
        v.dir,
        enemy,
        samples[1].t,
        reach
    )
end
--- The start read: an attempt, or undefined (a skip worth reading is logged).
local function tryStart(bot, now)
    local pid = bot:GetPlayerID()
    local lane = bot:GetAssignedLane()
    local v = viewOf(
        bot:GetTeam(),
        lane
    )
    if v == nil then
        return nil
    end
    local tgt = LanePush.TargetOf(lane)
    local reach = towerReach(
        bot:GetTeam(),
        lane,
        v
    )
    local r = ____exports.Read(
        v.theirs,
        v.ours,
        tgt,
        v.busy,
        reach
    )
    local w = ____exports.Stretch(v.theirs, tgt)
    local front
    local n
    local trig = "gone"
    local fc
    if type(r) == "string" then
        if r ~= "ours" and r ~= "late" then
            return nil
        end
        if w.front > math.max(tgt, reach + ____exports.SETTINGS.LateMargin) + ____exports.SETTINGS.ForecastAhead then
            if r == "ours" and notOnWave(v) then
                skip(
                    bot,
                    v,
                    "ours_far",
                    w.front,
                    w.n,
                    reach,
                    now
                )
            end
            return nil
        end
        if r == "late" then
            skip(
                bot,
                v,
                "late",
                w.front,
                w.n,
                reach,
                now
            )
            return nil
        end
        if w.front < reach + ____exports.SETTINGS.LateMargin then
            skip(
                bot,
                v,
                "ours",
                w.front,
                w.n,
                reach,
                now
            )
            return nil
        end
        local f = forecastIn(bot, v, reach, now)
        if f == false then
            return nil
        end
        if f == nil then
            skip(
                bot,
                v,
                "ours",
                w.front,
                w.n,
                reach,
                now
            )
            return nil
        end
        front = w.front
        n = w.n
        trig = "forecast"
        fc = f
    else
        front = r.front
        n = r.n
    end
    local ended = endedAt[pid]
    if ended ~= nil and now - ended < ____exports.SETTINGS.RestAfter then
        skip(
            bot,
            v,
            "rest",
            front,
            n,
            reach,
            now,
            fc
        )
        return nil
    end
    local a = begin(
        bot,
        v,
        front,
        n,
        w.rear,
        reach,
        now,
        trig,
        fc
    )
    if type(a) == "string" then
        skip(
            bot,
            v,
            a,
            front,
            n,
            reach,
            now,
            fc
        )
        return nil
    end
    return a
end
--- One frame for this core: starts, steps or ends the hold. It gives no order itself: the hold is the spot's input, the drag
-- lane_aggro's draw (stepped right after by the caller).
function ____exports.Step(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local a = attempts[pid]
    if a == nil then
        if not ____exports.Owns(bot) then
            return
        end
        local last = decidedAt[pid]
        if last ~= nil and now - last < ____exports.SETTINGS.Every then
            return
        end
        decidedAt[pid] = now
        local started = tryStart(bot, now)
        if started == nil then
            return
        end
        a = started
        attempts[pid] = a
    end
    a.steppedAt = now
    a.hpMin = math.min(
        a.hpMin,
        bot:GetHealth()
    )
    if not ____exports.Owns(bot) then
        return finish(bot, a, "left", now)
    end
    if (a.hp0 - bot:GetHealth()) / math.max(
        1,
        bot:GetMaxHealth()
    ) >= ____exports.SETTINGS.HurtShare or frac(bot) < ____exports.SETTINGS.HurtFloor then
        return finish(bot, a, "hurt", now)
    end
    if now - a.startedAt > ____exports.SETTINGS.MaxSecs then
        return finish(bot, a, "timeout", now)
    end
    if now - a.readAt < ____exports.SETTINGS.Every then
        return
    end
    a.readAt = now
    local v = viewOf(
        bot:GetTeam(),
        a.lane
    )
    if v == nil then
        return finish(bot, a, "left", now)
    end
    local front = math.huge
    local nearest
    for ____, x in ipairs(v.units) do
        do
            local __continue126
            repeat
                if x.own < -____exports.SETTINGS.OursBehind - a.bd or x.own > a.tgt + ____exports.SETTINGS.StartAhead then
                    __continue126 = true
                    break
                end
                if x.own < front then
                    front = x.own
                    nearest = x.u
                end
                __continue126 = true
            until true
            if not __continue126 then
                break
            end
        end
    end
    if nearest == nil then
        return finish(bot, a, "cleared", now)
    end
    a.omin = math.min(a.omin, front)
    if front < ____exports.SETTINGS.TowerR then
        a.tw = 1
    end
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue132
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue132 = true
                    break
                end
                if __TS__ArrayIncludes(a.old, c) then
                    __continue132 = true
                    break
                end
                if GetUnitToUnitDistance(c, nearest) <= ____exports.SETTINGS.MeetR then
                    a.mo = front
                    return finish(bot, a, "met", now)
                end
                __continue132 = true
            until true
            if not __continue132 then
                break
            end
        end
    end
    if a.br == "hold" and front < ____exports.SETTINGS.TowerR then
        return finish(bot, a, "tower", now)
    end
    if a.br == "hold" then
        local info = Laning.SpotInfo(bot)
        if info ~= nil then
            local s = LanePush.Project(v.path, info.spot.x, info.spot.y)
            if ____exports.Unsafe(
                info.anchor,
                info.why,
                v.dir * (s - v.t1),
                a.rch,
                front
            ) then
                return finish(bot, a, "unsafe", now)
            end
        end
    end
    local threat = threatOf(bot, a.hold)
    if threat ~= nil then
        a.thr = threat:GetPlayerID()
    end
    local wave = {}
    for ____, x in ipairs(v.units) do
        if x.own >= -____exports.SETTINGS.OursBehind - a.bd and x.own <= a.tgt + ____exports.SETTINGS.StartAhead then
            local ____temp_9 = x.u:GetAttackDamage()
            local ____this_8
            ____this_8 = x.u
            local ____opt_7 = ____this_8.GetSecondsPerAttack
            wave[#wave + 1] = {
                dmg = ____temp_9,
                spa = ____opt_7 and ____opt_7(____this_8) or ____exports.SETTINGS.CreepSpa
            }
        end
    end
    local ____exports_WaveDps_13 = ____exports.WaveDps
    local ____exports_ArmorMult_12 = ____exports.ArmorMult
    local ____this_11
    ____this_11 = bot
    local ____opt_10 = ____this_11.GetArmor
    local dps = ____exports_WaveDps_13(
        wave,
        ____exports_ArmorMult_12(____opt_10 and ____opt_10(____this_11) or 0)
    )
    a.bud = ____exports.SETTINGS.TankShare * bot:GetMaxHealth()
    local live = walkingTo(a.hold)
    a.nl = #live > 0 and ____exports.Near(math.huge, live) or nil
    local sched = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 + v.dir * a.tgt,
        now
    ) - now
    local near = ____exports.Near(sched, live)
    a.tk = ____exports.TankSecs(near, front, a.hd)
    a.cost = dps * a.tk
    a.ds = ____exports.DragSecs(
        math.max(0, front),
        a.bd
    )
    a.nb = math.min(
        LanePush.NextArrival(
            v.path,
            bot:GetTeam(),
            v.t1 - v.dir * a.bd,
            now
        ) - now,
        ____exports.OursAtBehind(v.ours, a.bd, front)
    )
    local dragging = a.br == "drag" and (LaneAggro.Acting(bot) or GetUnitToLocationDistance(bot, a.behind) <= ____exports.SETTINGS.Arrived)
    local br = dragging and "drag" or ____exports.Choose(a.cost, a.bud, a.ds, a.nb)
    if br == "hold" and not dragging and ____exports.Choose(
        dps * ____exports.TankSecs(sched, front, a.hd),
        a.bud,
        a.ds,
        a.nb
    ) ~= "hold" then
        a.lv = 1
    end
    if br == "concede" or br == "drag" and not dragging and not LaneAggro.StartBack(bot, a.behind) then
        return finish(bot, a, "concede", now)
    end
    if br ~= a.br then
        a.sw = a.sw + 1
        a.br = br
    end
    Laning.SetHold(bot, a.br == "hold" and a.hold or a.behind)
    if a.br == "hold" and not LaneAggro.Acting(bot) then
        local on = 0
        for ____, x in ipairs(v.units) do
            local t = x.u:GetAttackTarget()
            if t ~= nil and t ~= nil and t == bot then
                on = on + 1
            end
        end
        if ____exports.DrawNow(
            front,
            a.hd,
            GetUnitToLocationDistance(bot, a.hold),
            on
        ) and LaneAggro.StartBack(
            bot,
            pointAt(v, a.hd + ____exports.SETTINGS.HoldDrawOut, a.hold.z),
            "hold"
        ) then
            a.hdr = a.hdr + 1
        end
    end
end
function ____exports.Reset()
    for k in pairs(attempts) do
        attempts[k] = nil
    end
    for k in pairs(decidedAt) do
        decidedAt[k] = nil
    end
    for k in pairs(endedAt) do
        endedAt[k] = nil
    end
    for k in pairs(skippedAt) do
        skippedAt[k] = nil
    end
    for k in pairs(forecastAt) do
        forecastAt[k] = nil
    end
end
return ____exports
