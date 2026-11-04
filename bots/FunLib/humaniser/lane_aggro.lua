--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local counter, roleOf, newAttempt
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local CoreTrade = require(GetScriptDirectory().."/FunLib/humaniser/states/core_trade")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
function counter(bot, name)
    local f = bot[name]
    return f ~= nil and f(bot) or 0
end
function roleOf(bot)
    if CoreLastHit.Applies(bot) then
        return "core"
    end
    if Laning.OwnsSupportHits(bot) then
        return "support"
    end
    return nil
end
function newAttempt(bot, kind, phase, hero, creep, back, approach, now)
    return {
        kind = kind,
        phase = phase,
        startedAt = now,
        hero = hero,
        tpid = hero:GetPlayerID(),
        creep = creep,
        mv = 0,
        approach = approach,
        back = back,
        hp0 = bot:GetHealth(),
        hpMin = bot:GetHealth(),
        near = 0,
        drawn = 0,
        onr = 0,
        lh0 = counter(bot, "GetLastHits"),
        dn0 = counter(bot, "GetDenies"),
        role = roleOf(bot) or "?"
    }
end
____exports.SETTINGS = {
    Cooldown = 3.1,
    DrawR = 450,
    Every = 0.25,
    MinHp = 0.45,
    HeroMargin = 250,
    TowerR = 1000,
    FeedCreepHp = 0.5,
    FightR = 700,
    FeedMinCreeps = 2,
    ApproachBack = 380,
    ApproachMax = 350,
    ApproachTime = 1.2,
    FeedBack = 250,
    DropNear = 220,
    DropAfter = 0.8,
    DropBy = 1.8,
    DrawCheck = 1,
    MovedR = 120,
    FeedMinQ = 0.3,
    DragDueMin = 0.8,
    DragDueMax = 3,
    DragContest = 150,
    DragBack = 300,
    DragWalk = 1.2,
    BusyWithin = 1.5,
    HurtShare = 0.12,
    FeedWatch = 30,
    FeedHeroClear = 300,
    DragWatch = 3.5,
    CoreNear = 1600
}
local attempts = {}
local orderedAt = {}
local decidedAt = {}
--- Our ranged creeps already fed (one feed per creep).
local fed = {}
--- Last draw per team and lane: one draw per lane at a time.
local laneDraw = {}
local pushCache = {}
local function laneKey(team, lane)
    return (tostring(team) .. ":") .. tostring(lane)
end
local function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen()
end
local function frac(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
end
local function d2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function along(from, dir, len)
    return Vector(from.x + dir.x * len, from.y + dir.y * len, from.z)
end
local T1 = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
--- Unit vector from `from` toward our side of the lane (our T1, else our ancient).
local function backDir(team, lane, from)
    local t = GetTower(team, T1[lane])
    local home = t ~= nil and t ~= nil and t:IsAlive() and t:GetLocation() or GetAncient(team):GetLocation()
    local len = math.max(
        1,
        d2(home, from)
    )
    return Vector((home.x - from.x) / len, (home.y - from.y) / len, 0)
end
local function isRanged(c)
    return __TS__StringIncludes(
        c:GetUnitName(),
        "ranged"
    )
end
local function isLaneCreep(c)
    return LanePush.IsLaneCreep(c:GetUnitName())
end
--- Pure: whether the draw clock lets this bot order now (its own last draw and its trades' primes share the 3 s cooldown).
function ____exports.CooldownClear(now, own, primed)
    local last = math.max(own or -math.huge, primed or -math.huge)
    return now - last >= ____exports.SETTINGS.Cooldown
end
--- Pure: whether another hero's draw holds this lane (one draw per lane at a time).
function ____exports.LaneHeld(now, pid, held)
    return held ~= nil and held.pid ~= pid and now - held.at < ____exports.SETTINGS.Cooldown
end
--- Pure: whether the lane push reading wants the wave tilted toward us (the clash not near our tower, not coming in).
function ____exports.FeedWanted(r)
    if r == nil then
        return false
    end
    return r.state ~= "IN" and r.q >= ____exports.SETTINGS.FeedMinQ
end
--- Pure: the feed's drop now? `t` seconds since the order, `nearest` the closest drawn creep to our ranged creep.
function ____exports.DropNow(t, drawn, nearest)
    if t >= ____exports.SETTINGS.DropBy then
        return true
    end
    return t >= ____exports.SETTINGS.DropAfter and drawn > 0 and nearest ~= nil and nearest <= ____exports.SETTINGS.DropNear
end
local function pushRead(team, lane)
    local key = laneKey(team, lane)
    local now = DotaTime()
    local c = pushCache[key]
    if c ~= nil and now - c.t < 1 then
        return c.r
    end
    local ok, r = pcall(LanePush.Read, team, lane)
    local ____ok_0
    if ok then
        ____ok_0 = r
    else
        ____ok_0 = nil
    end
    local v = ____ok_0
    pushCache[key] = {t = now, r = v}
    return v
end
local function coreAway(bot)
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue20
                repeat
                    local h = GetTeamMember(i)
                    if h == nil or h == nil or h == bot or h:IsNull() then
                        __continue20 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(h)
                    if pos == nil or pos > 3 or h:GetAssignedLane() ~= lane then
                        __continue20 = true
                        break
                    end
                    if h:IsAlive() and GetUnitToUnitDistance(h, bot) <= ____exports.SETTINGS.CoreNear then
                        return false
                    end
                    __continue20 = true
                until true
                if not __continue20 then
                    break
                end
            end
            i = i + 1
        end
    end
    return true
end
--- Whether this module may act for the bot now (the switch, laning phase, a core, or a support whose core is away).
function ____exports.Owns(bot)
    if not Ours.On("LaneAggro") or not bot:IsAlive() or not Phase.IsLaningFor(bot) then
        return false
    end
    local role = roleOf(bot)
    if role == "core" then
        return true
    end
    return role == "support" and coreAway(bot)
end
--- Whether the bot owns the move in principle (switch and role), so OHA's aggro pull stays off for it (lane_tech).
function ____exports.OwnsTechnique(bot)
    return Ours.On("LaneAggro") and roleOf(bot) ~= nil
end
local function enemyHeroes(bot, r)
    local out = {}
    for ____, h in ipairs(bot:GetNearbyHeroes(r, true, BotMode.None)) do
        if valid(h) and not h:IsIllusion() then
            out[#out + 1] = h
        end
    end
    return out
end
--- No enemy hero reaches `at` (attack range + radii + margin).
local function heroSafe(at, heroes)
    for ____, h in ipairs(heroes) do
        if GetUnitToLocationDistance(h, at) <= h:GetAttackRange() + h:GetBoundingRadius() * 2 + ____exports.SETTINGS.HeroMargin then
            return false
        end
    end
    return true
end
local function nearTower(at, team)
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    for ____, id in ipairs({
        Tower.Top1,
        Tower.Mid1,
        Tower.Bot1,
        Tower.Top2,
        Tower.Mid2,
        Tower.Bot2
    }) do
        local t = GetTower(enemy, id)
        if t ~= nil and t ~= nil and t:IsAlive() and d2(
            t:GetLocation(),
            at
        ) <= ____exports.SETTINGS.TowerR then
            return true
        end
    end
    return false
end
--- The enemy hero the order names: the nearest visible one, not by its own tower.
local function orderTarget(bot, heroes)
    local best
    local bestD = math.huge
    for ____, h in ipairs(heroes) do
        do
            local __continue44
            repeat
                if nearTower(
                    h:GetLocation(),
                    bot:GetTeam()
                ) then
                    __continue44 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < bestD then
                    best = h
                    bestD = d
                end
                __continue44 = true
            until true
            if not __continue44 then
                break
            end
        end
    end
    return best
end
local function allyPullOut(bot)
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
                        return true
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
    return false
end
local function enemyCreepsNear(bot, at, r)
    local out = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1600, true)) do
        if valid(c) and isLaneCreep(c) and d2(
            c:GetLocation(),
            at
        ) <= r then
            out[#out + 1] = c
        end
    end
    return out
end
local function laneTargets(bot, within, deny)
    local verbs = Tasks.Verbs()
    if verbs == nil then
        return {}
    end
    return verbs.laneTargets(bot, {within = within, deny = deny})
end
--- The shared gates of both moves, or why not.
local function gate(bot, now)
    local pid = bot:GetPlayerID()
    if not ____exports.CooldownClear(
        now,
        orderedAt[pid],
        CoreTrade.PrimedAt(pid)
    ) then
        return "cooldown"
    end
    if ____exports.LaneHeld(
        now,
        pid,
        laneDraw[laneKey(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )]
    ) then
        return "lane"
    end
    if frac(bot) < ____exports.SETTINGS.MinHp then
        return "hp"
    end
    local t = bot:GetAttackTarget()
    if t ~= nil and t ~= nil and not t:IsNull() and t:IsHero() then
        return "trading"
    end
    if nearTower(
        bot:GetLocation(),
        bot:GetTeam()
    ) then
        return "tower"
    end
    if allyPullOut(bot) then
        return "pull"
    end
    return nil
end
local function start(bot, a)
    attempts[bot:GetPlayerID()] = a
end
local function tryDrag(bot, heroes, now)
    local here = bot:GetLocation()
    for ____, t in ipairs(laneTargets(bot, ____exports.SETTINGS.DragDueMax, false)) do
        do
            local __continue67
            repeat
                if t.kind ~= "lasthit" or t.due < ____exports.SETTINGS.DragDueMin or t.due > ____exports.SETTINGS.DragDueMax then
                    __continue67 = true
                    break
                end
                local creep = t.creep
                if not valid(creep) or GetUnitToUnitDistance(bot, creep) > ____exports.SETTINGS.DrawR then
                    __continue67 = true
                    break
                end
                local contester
                for ____, h in ipairs(heroes) do
                    if GetUnitToUnitDistance(h, creep) <= h:GetAttackRange() + h:GetBoundingRadius() + ____exports.SETTINGS.DragContest then
                        contester = h
                    end
                end
                if contester == nil then
                    __continue67 = true
                    break
                end
                local hero = orderTarget(bot, heroes)
                if hero == nil then
                    return nil
                end
                local back = along(
                    here,
                    backDir(
                        bot:GetTeam(),
                        bot:GetAssignedLane(),
                        here
                    ),
                    ____exports.SETTINGS.DragBack
                )
                if not heroSafe(back, heroes) then
                    return nil
                end
                return newAttempt(
                    bot,
                    "drag",
                    "walk",
                    hero,
                    creep,
                    back,
                    nil,
                    now
                )
            until true
            if not __continue67 then
                break
            end
        end
    end
    return nil
end
local function tryFeed(bot, heroes, now)
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    local ranged
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1200, false)) do
        if valid(c) and isLaneCreep(c) and isRanged(c) and fed[c] ~= true and frac(c) >= ____exports.SETTINGS.FeedCreepHp then
            ranged = c
        end
    end
    if ranged == nil then
        return nil
    end
    local fighting = enemyCreepsNear(
        bot,
        ranged:GetLocation(),
        ____exports.SETTINGS.FightR
    )
    if #fighting < ____exports.SETTINGS.FeedMinCreeps then
        return nil
    end
    for ____, h in ipairs(heroes) do
        if GetUnitToUnitDistance(h, ranged) <= h:GetAttackRange() + h:GetBoundingRadius() + ____exports.SETTINGS.FeedHeroClear then
            return nil
        end
    end
    local cx = 0
    local cy = 0
    for ____, c in ipairs(fighting) do
        cx = cx + c:GetLocation().x
        cy = cy + c:GetLocation().y
    end
    local centre = Vector(
        cx / #fighting,
        cy / #fighting,
        ranged:GetLocation().z
    )
    local dir = backDir(team, lane, centre)
    local approach = along(centre, dir, ____exports.SETTINGS.ApproachBack)
    if GetUnitToLocationDistance(bot, approach) > ____exports.SETTINGS.ApproachMax then
        return nil
    end
    if #enemyCreepsNear(bot, approach, ____exports.SETTINGS.DrawR) < ____exports.SETTINGS.FeedMinCreeps then
        return nil
    end
    local back = along(
        ranged:GetLocation(),
        dir,
        ____exports.SETTINGS.FeedBack
    )
    if not heroSafe(approach, heroes) or not heroSafe(back, heroes) or nearTower(approach, team) then
        return nil
    end
    if #laneTargets(bot, ____exports.SETTINGS.BusyWithin, true) > 0 then
        return nil
    end
    local r = pushRead(team, lane)
    if not ____exports.FeedWanted(r) then
        return nil
    end
    local hero = orderTarget(bot, heroes)
    if hero == nil then
        return nil
    end
    local a = newAttempt(
        bot,
        "feed",
        "approach",
        hero,
        ranged,
        back,
        approach,
        now
    )
    a.q = r ~= nil and math.floor(r.q * 100) / 100 or nil
    a.st = r and r.state
    return a
end
local function finish(bot, a, result, now)
    attempts[bot:GetPlayerID()] = nil
    Telemetry.Event(
        "aggro",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"role", a.role},
            {"kind", a.kind},
            {"result", result},
            {"tgt", a.tpid},
            {"near", a.near},
            {"drawn", a.drawn},
            {"mv", a.mv},
            {
                "rhp",
                a.kind == "feed" and not a.creep:IsNull() and a.creep:IsAlive() and math.floor(frac(a.creep) * 100) / 100 or nil
            },
            {"onr", a.onr},
            {"dhp", a.hp0 - a.hpMin},
            {
                "hp",
                math.floor(a.hp0 / math.max(
                    1,
                    bot:GetMaxHealth()
                ) * 100) / 100
            },
            {"q", a.q},
            {"st", a.st},
            {"hd", a.hd},
            {
                "drop",
                a.droppedAt ~= nil and math.floor((a.droppedAt - (a.orderedAt or a.startedAt)) * 100) / 100 or nil
            },
            {
                "dur",
                math.floor((now - a.startedAt) * 100) / 100
            }
        }
    )
end
--- Enemy creeps near at the order that have since moved MovedR or more (drawn off their fight).
local function movedOf(a)
    local n = 0
    for ____, s0 in ipairs(a.start or ({})) do
        do
            local __continue97
            repeat
                local u = s0.unit
                if u:IsNull() or not u:IsAlive() then
                    __continue97 = true
                    break
                end
                local l = u:GetLocation()
                if d2(
                    l,
                    Vector(s0.x, s0.y, l.z)
                ) >= ____exports.SETTINGS.MovedR then
                    n = n + 1
                end
                __continue97 = true
            until true
            if not __continue97 then
                break
            end
        end
    end
    return n
end
local function drawnOn(bot, target)
    local out = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1200, true)) do
        do
            local __continue102
            repeat
                if not valid(c) then
                    __continue102 = true
                    break
                end
                local t = c:GetAttackTarget()
                if t ~= nil and t ~= nil and not t:IsNull() and t == target then
                    out[#out + 1] = c
                end
                __continue102 = true
            until true
            if not __continue102 then
                break
            end
        end
    end
    return out
end
--- The result once the move has handed the frame back: the creep's fate, read from our last-hit and deny counters.
local function watch(bot, a, now)
    if not bot:IsAlive() then
        return finish(bot, a, "died", now)
    end
    local dead = a.creep:IsNull() or not a.creep:IsAlive()
    if a.kind == "feed" then
        if not dead then
            a.onr = math.max(
                a.onr,
                #drawnOn(bot, a.creep)
            )
        end
        if dead then
            return finish(
                bot,
                a,
                counter(bot, "GetDenies") > a.dn0 and "denied" or "lost",
                now
            )
        end
        if now - (a.droppedAt or a.startedAt) > ____exports.SETTINGS.FeedWatch then
            return finish(bot, a, "alive", now)
        end
    else
        if dead then
            return finish(
                bot,
                a,
                counter(bot, "GetLastHits") > a.lh0 and "ok" or "lost",
                now
            )
        end
        if now - (a.walkedAt or a.startedAt) > ____exports.SETTINGS.DragWatch then
            return finish(bot, a, "alive", now)
        end
    end
end
--- The move's frame: true while it gives the bot's orders (approach, the draw, the walk back).
local function act(bot, a, now)
    local pid = bot:GetPlayerID()
    a.hpMin = math.min(
        a.hpMin,
        bot:GetHealth()
    )
    if not bot:IsAlive() then
        finish(bot, a, "died", now)
        return false
    end
    if not valid(a.hero) or a.kind == "drag" and (a.creep:IsNull() or not a.creep:IsAlive()) then
        if a.orderedAt == nil then
            finish(bot, a, "cancelled", now)
            return false
        end
    end
    if (a.hp0 - bot:GetHealth()) / math.max(
        1,
        bot:GetMaxHealth()
    ) > ____exports.SETTINGS.HurtShare then
        finish(bot, a, "hurt", now)
        return false
    end
    if a.phase == "approach" then
        local at = a.approach
        if GetUnitToLocationDistance(bot, at) > 60 and now - a.startedAt < ____exports.SETTINGS.ApproachTime then
            bot:Action_MoveToLocation(at)
            return true
        end
        if not a.creep:IsAlive() or not valid(a.hero) then
            finish(bot, a, "cancelled", now)
            return false
        end
        a.phase = "walk"
    end
    if a.orderedAt == nil then
        local near = enemyCreepsNear(
            bot,
            bot:GetLocation(),
            500
        )
        a.near = #near
        a.start = __TS__ArrayMap(
            near,
            function(____, c) return {
                unit = c,
                x = c:GetLocation().x,
                y = c:GetLocation().y
            } end
        )
        bot:Action_AttackUnit(a.hero, true)
        a.orderedAt = now
        orderedAt[pid] = now
        CoreTrade.NotePrimed(pid, now)
        laneDraw[laneKey(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )] = {pid = pid, at = now}
        if a.kind == "feed" then
            fed[a.creep] = true
        end
        return true
    end
    local t = now - a.orderedAt
    a.drawn = math.max(
        a.drawn,
        #drawnOn(bot, bot)
    )
    a.mv = math.max(
        a.mv,
        movedOf(a)
    )
    if t >= ____exports.SETTINGS.DrawCheck and a.drawn == 0 and a.mv == 0 then
        finish(bot, a, "no_draw", now)
        return false
    end
    if a.kind == "feed" then
        local nearest
        if a.creep:IsAlive() then
            for ____, c in ipairs(drawnOn(bot, bot)) do
                local d = GetUnitToUnitDistance(c, a.creep)
                if nearest == nil or d < nearest then
                    nearest = d
                end
            end
            for ____, s0 in ipairs(a.start or ({})) do
                do
                    local __continue132
                    repeat
                        local u = s0.unit
                        if u:IsNull() or not u:IsAlive() or d2(
                            u:GetLocation(),
                            Vector(s0.x, s0.y, 0)
                        ) < ____exports.SETTINGS.MovedR then
                            __continue132 = true
                            break
                        end
                        local d = GetUnitToUnitDistance(u, a.creep)
                        if nearest == nil or d < nearest then
                            nearest = d
                        end
                        __continue132 = true
                    until true
                    if not __continue132 then
                        break
                    end
                end
            end
        end
        if not a.creep:IsAlive() then
            a.phase = "watch"
            a.droppedAt = now
            return false
        end
        if ____exports.DropNow(t, a.drawn + a.mv, nearest) then
            bot:Action_AttackUnit(a.creep, true)
            a.droppedAt = now
            a.phase = "watch"
            return true
        end
        bot:Action_MoveToLocation(a.back)
        return true
    end
    if t < ____exports.SETTINGS.DragWalk and a.creep:IsAlive() then
        bot:Action_MoveToLocation(a.back)
        return true
    end
    a.walkedAt = now
    if a.creep:IsAlive() and valid(a.hero) then
        a.hd = math.floor(GetUnitToUnitDistance(a.hero, a.creep))
    end
    a.phase = "watch"
    return false
end
--- One frame of the module for this bot: reads a running move's result, steps a running move, or decides whether to start one.
-- True when it gave the bot's order this frame (the caller's other steps then stay off).
function ____exports.Step(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local a = attempts[pid]
    if a ~= nil then
        if a.phase == "watch" then
            watch(bot, a, now)
        else
            return act(bot, a, now)
        end
    end
    if attempts[pid] ~= nil or not ____exports.Owns(bot) then
        return false
    end
    local last = decidedAt[pid]
    if last ~= nil and now - last < ____exports.SETTINGS.Every then
        return false
    end
    decidedAt[pid] = now
    if gate(bot, now) ~= nil then
        return false
    end
    local heroes = enemyHeroes(bot, 1600)
    if #heroes == 0 or not heroSafe(
        bot:GetLocation(),
        heroes
    ) then
        return false
    end
    local next = tryDrag(bot, heroes, now) or tryFeed(bot, heroes, now)
    if next == nil then
        return false
    end
    start(bot, next)
    return act(bot, next, now)
end
--- A move is giving this bot's orders (not only watching its result).
function ____exports.Acting(bot)
    local a = attempts[bot:GetPlayerID()]
    return a ~= nil and a.phase ~= "watch"
end
function ____exports.Reset()
    for k in pairs(attempts) do
        attempts[k] = nil
    end
    for k in pairs(orderedAt) do
        orderedAt[k] = nil
    end
    for k in pairs(decidedAt) do
        decidedAt[k] = nil
    end
    for k in pairs(laneDraw) do
        laneDraw[k] = nil
    end
    for k in pairs(pushCache) do
        pushCache[k] = nil
    end
end
return ____exports
