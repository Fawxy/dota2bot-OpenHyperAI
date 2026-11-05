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
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
--- Pure: our T1's fire reach to a creep's centre (`reach` in the docs), from the API's values or the fallbacks.
function ____exports.EffReach(range, towerHull, creepHull)
    local function ok(x, d)
        return x ~= nil and x > 0 and x or d
    end
    return ok(range, ____exports.SETTINGS.TowerR) + ok(towerHull, ____exports.SETTINGS.TowerHull) + ok(creepHull, ____exports.SETTINGS.CreepHull)
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
    SkipEvery = 5
}
--- Their wave in the stretch (our T1 distances, positive towards theirs): its count, front and rear.
function ____exports.Stretch(theirs, target)
    local n = 0
    local front = math.huge
    local rear = -math.huge
    for ____, o in ipairs(theirs) do
        do
            local __continue3
            repeat
                if o < -____exports.SETTINGS.OursBehind or o > target + ____exports.SETTINGS.StartAhead then
                    __continue3 = true
                    break
                end
                n = n + 1
                front = math.min(front, o)
                rear = math.max(rear, o)
                __continue3 = true
            until true
            if not __continue3 then
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
                local __continue8
                repeat
                    local o = ours[i + 1]
                    if o < ____exports.SETTINGS.TowerR and busy[i + 1] == true then
                        __continue8 = true
                        break
                    end
                    if o >= -____exports.SETTINGS.OursBehind and o <= w.rear + ____exports.SETTINGS.OursAhead then
                        return "ours"
                    end
                    __continue8 = true
                until true
                if not __continue8 then
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
function ____exports.Choose(threat, near, need, behind)
    if not threat or near <= ____exports.SETTINGS.NearSecs then
        return "hold"
    end
    return need + ____exports.SETTINGS.DragMargin <= behind and "drag" or "hold"
end
--- Pure: seconds until our next wave reaches the hold point, from the spawn schedule's `schedule` and the straight-line
-- distances to it of our lane creeps already on the map and walking.
function ____exports.Near(schedule, live)
    local d = math.huge
    for ____, x in ipairs(live) do
        d = math.min(d, x)
    end
    return math.min(schedule, d / ____exports.SETTINGS.CreepSpeed)
end
--- Pure: the seconds the drag needs from their front's distance from our T1.
function ____exports.DragSecs(front)
    return (front + ____exports.SETTINGS.Behind) / ____exports.SETTINGS.CreepSpeed + ____exports.SETTINGS.DrawSecs
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
                local __continue35
                repeat
                    if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                        __continue35 = true
                        break
                    end
                    local l = c:GetLocation()
                    if l == nil then
                        __continue35 = true
                        break
                    end
                    local s, d = LanePush.Project(path, l.x, l.y)
                    if d > ____exports.SETTINGS.PathR then
                        __continue35 = true
                        break
                    end
                    local own = dir * (s - t1)
                    out[#out + 1] = own
                    local ____opt_0 = keep
                    if ____opt_0 ~= nil then
                        keep[#keep + 1] = {u = c, own = own}
                    end
                    __continue35 = true
                until true
                if not __continue35 then
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
    local r = ____exports.SETTINGS.NearSecs * ____exports.SETTINGS.CreepSpeed
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue43
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue43 = true
                    break
                end
                local t = c:GetAttackTarget()
                if t ~= nil and t ~= nil and not t:IsNull() then
                    __continue43 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, hold)
                if d <= r then
                    out[#out + 1] = d
                end
                __continue43 = true
            until true
            if not __continue43 then
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
                local __continue49
                repeat
                    local h = GetTeamMember(i)
                    if h == nil or h == nil or h:IsNull() then
                        __continue49 = true
                        break
                    end
                    if h:GetAssignedLane() == lane and PullJob.Running(h) then
                        return "pull"
                    end
                    __continue49 = true
                until true
                if not __continue49 then
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
            local __continue54
            repeat
                if h == nil or h == nil or h:IsNull() or not h:IsAlive() or h:IsIllusion() then
                    __continue54 = true
                    break
                end
                local r = LaneSpot.HeroReach(bot, h) + ____exports.SETTINGS.ThreatMargin
                if GetUnitToUnitDistance(bot, h) <= r or GetUnitToLocationDistance(h, hold) <= r then
                    return h
                end
                __continue54 = true
            until true
            if not __continue54 then
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
        behind = pointAt(v, -____exports.SETTINGS.Behind, z),
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
            local __continue72
            repeat
                if o < -____exports.SETTINGS.OursBehind then
                    __continue72 = true
                    break
                end
                if o < ____exports.SETTINGS.TowerR then
                    oin = oin + 1
                else
                    on = on + 1
                end
                __continue72 = true
            until true
            if not __continue72 then
                break
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
            }
        }
    )
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
    local ____ok_2
    if ok then
        ____ok_2 = r
    else
        ____ok_2 = nil
    end
    local samples = ____ok_2
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
            local __continue103
            repeat
                if x.own < -____exports.SETTINGS.OursBehind - ____exports.SETTINGS.Behind or x.own > a.tgt + ____exports.SETTINGS.StartAhead then
                    __continue103 = true
                    break
                end
                if x.own < front then
                    front = x.own
                    nearest = x.u
                end
                __continue103 = true
            until true
            if not __continue103 then
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
            local __continue109
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue109 = true
                    break
                end
                if __TS__ArrayIncludes(a.old, c) then
                    __continue109 = true
                    break
                end
                if GetUnitToUnitDistance(c, nearest) <= ____exports.SETTINGS.MeetR then
                    a.mo = front
                    return finish(bot, a, "met", now)
                end
                __continue109 = true
            until true
            if not __continue109 then
                break
            end
        end
    end
    if a.br == "hold" and front < ____exports.SETTINGS.TowerR then
        return finish(bot, a, "tower", now)
    end
    local threat = threatOf(bot, a.hold)
    if threat ~= nil then
        a.thr = threat:GetPlayerID()
    end
    local live = walkingTo(a.hold)
    a.nl = #live > 0 and ____exports.Near(math.huge, live) or nil
    local sched = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 + v.dir * a.tgt,
        now
    ) - now
    local near = ____exports.Near(sched, live)
    a.ds = ____exports.DragSecs(math.max(0, front))
    a.nb = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 - v.dir * ____exports.SETTINGS.Behind,
        now
    ) - now
    local dragging = a.br == "drag" and (LaneAggro.Acting(bot) or GetUnitToLocationDistance(bot, a.behind) <= ____exports.SETTINGS.Arrived)
    local br = dragging and "drag" or ____exports.Choose(threat ~= nil, near, a.ds, a.nb)
    if br == "hold" and not dragging and ____exports.Choose(threat ~= nil, sched, a.ds, a.nb) == "drag" then
        a.lv = 1
    end
    if br == "drag" and not dragging and not LaneAggro.StartBack(bot, a.behind) then
        if a.br ~= "hold" then
            a.sw = a.sw + 1
        end
        a.br = "hold"
    elseif br ~= a.br then
        a.sw = a.sw + 1
        a.br = br
    end
    Laning.SetHold(bot, a.br == "hold" and a.hold or nil)
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
