--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
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
____exports.SETTINGS = {
    Every = 0.25,
    PathR = 600,
    MinCreeps = 2,
    StartAhead = 1600,
    TowerR = 700,
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
    LeftAfter = 1,
    MaxSecs = 45,
    Arrived = 300,
    AggroRecent = 20
}
--- Pure: the trigger's reading of a lane, from our T1 distances (positive towards theirs) of the lane creeps on it.
function ____exports.Read(theirs, ours, target)
    local n = 0
    local front = math.huge
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
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    if n < ____exports.SETTINGS.MinCreeps then
        return "none"
    end
    for ____, o in ipairs(ours) do
        if o >= -____exports.SETTINGS.OursBehind and o <= front + ____exports.SETTINGS.OursAhead then
            return "ours"
        end
    end
    if front < ____exports.SETTINGS.TowerR then
        return "late"
    end
    return {front = front, n = n}
end
--- Pure: the branch (user 05/11/2026). `threat` an enemy hero's move on the core; `near` seconds until our next wave reaches the
-- hold point; `need` seconds the drag needs; `behind` seconds until our next wave reaches the drag's point.
function ____exports.Choose(threat, near, need, behind)
    if not threat or near <= ____exports.SETTINGS.NearSecs then
        return "hold"
    end
    return need + ____exports.SETTINGS.DragMargin <= behind and "drag" or "hold"
end
--- Pure: the seconds the drag needs from their front's distance from our T1.
function ____exports.DragSecs(front)
    return (front + ____exports.SETTINGS.Behind) / ____exports.SETTINGS.CreepSpeed + ____exports.SETTINGS.DrawSecs
end
local attempts = {}
local decidedAt = {}
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
                local __continue20
                repeat
                    if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                        __continue20 = true
                        break
                    end
                    local l = c:GetLocation()
                    if l == nil then
                        __continue20 = true
                        break
                    end
                    local s, d = LanePush.Project(path, l.x, l.y)
                    if d > ____exports.SETTINGS.PathR then
                        __continue20 = true
                        break
                    end
                    local own = dir * (s - t1)
                    out[#out + 1] = own
                    local ____opt_0 = keep
                    if ____opt_0 ~= nil then
                        keep[#keep + 1] = {u = c, own = own}
                    end
                    __continue20 = true
                until true
                if not __continue20 then
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
    local ours = project(GetUnitList(UnitType.AlliedCreeps))
    return {
        path = path,
        t1 = t1,
        dir = dir,
        theirs = theirs,
        ours = ours,
        units = units
    }
end
local function pointAt(v, own, z)
    local x, y = LanePush.PointAt(v.path, v.t1 + v.dir * own)
    return Vector(x, y, z)
end
local function whyGone(bot, now)
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue27
                repeat
                    local h = GetTeamMember(i)
                    if h == nil or h == nil or h:IsNull() then
                        __continue27 = true
                        break
                    end
                    if h:GetAssignedLane() == lane and PullJob.Running(h) then
                        return "pull"
                    end
                    __continue27 = true
                until true
                if not __continue27 then
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
            local __continue32
            repeat
                if h == nil or h == nil or h:IsNull() or not h:IsAlive() or h:IsIllusion() then
                    __continue32 = true
                    break
                end
                local r = LaneSpot.HeroReach(bot, h) + ____exports.SETTINGS.ThreatMargin
                if GetUnitToUnitDistance(bot, h) <= r or GetUnitToLocationDistance(h, hold) <= r then
                    return h
                end
                __continue32 = true
            until true
            if not __continue32 then
                break
            end
        end
    end
    return nil
end
local function finish(bot, a, res, now)
    local pid = bot:GetPlayerID()
    attempts[pid] = nil
    Laning.SetHold(bot, nil)
    Telemetry.Event(
        "wave_hold",
        {
            {"pid", pid},
            {"lane", a.lane},
            {"br", a.br},
            {"res", res},
            {"why", a.why},
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
local function begin(bot, v, front, n, now)
    local lane = bot:GetAssignedLane()
    local tgt = LaneAggro.TargetOf(lane)
    local z = bot:GetLocation().z
    local hold = pointAt(v, tgt, z)
    if GetUnitToLocationDistance(bot, hold) > ____exports.SETTINGS.Reach or frac(bot) < ____exports.SETTINGS.StartHp then
        return nil
    end
    local nw = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 + v.dir * tgt,
        now
    ) - now
    return {
        lane = lane,
        br = "hold",
        sw = 0,
        startedAt = now,
        steppedAt = now,
        hold = hold,
        behind = pointAt(v, -____exports.SETTINGS.Behind, z),
        why = whyGone(bot, now),
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
        local v = viewOf(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )
        if v == nil then
            return
        end
        local r = ____exports.Read(
            v.theirs,
            v.ours,
            LaneAggro.TargetOf(bot:GetAssignedLane())
        )
        if type(r) == "string" then
            return
        end
        a = begin(
            bot,
            v,
            r.front,
            r.n,
            now
        )
        if a == nil then
            return
        end
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
            local __continue56
            repeat
                if x.own < -____exports.SETTINGS.OursBehind - ____exports.SETTINGS.Behind or x.own > a.tgt + ____exports.SETTINGS.StartAhead then
                    __continue56 = true
                    break
                end
                if x.own < front then
                    front = x.own
                    nearest = x.u
                end
                __continue56 = true
            until true
            if not __continue56 then
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
            local __continue62
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue62 = true
                    break
                end
                if GetUnitToUnitDistance(c, nearest) <= ____exports.SETTINGS.MeetR then
                    a.mo = front
                    return finish(bot, a, "met", now)
                end
                __continue62 = true
            until true
            if not __continue62 then
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
    local near = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 + v.dir * a.tgt,
        now
    ) - now
    a.ds = ____exports.DragSecs(math.max(0, front))
    a.nb = LanePush.NextArrival(
        v.path,
        bot:GetTeam(),
        v.t1 - v.dir * ____exports.SETTINGS.Behind,
        now
    ) - now
    local dragging = a.br == "drag" and (LaneAggro.Acting(bot) or GetUnitToLocationDistance(bot, a.behind) <= ____exports.SETTINGS.Arrived)
    local br = dragging and "drag" or ____exports.Choose(threat ~= nil, near, a.ds, a.nb)
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
end
return ____exports
