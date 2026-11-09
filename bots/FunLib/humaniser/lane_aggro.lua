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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local valid, live, frac, d2, counter, roleOf, TowerOrderR, newAttempt, finish, seenAt, drawnOn, watch, attempts, towerEnd
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local CoreTrade = require(GetScriptDirectory().."/FunLib/humaniser/states/core_trade")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen()
end
function live(u)
    return not u:IsNull() and u:IsAlive()
end
function frac(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
end
function d2(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
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
function TowerOrderR()
    return LaneConfig.TowerReach() + ____exports.SETTINGS.TowerOrderMargin
end
function newAttempt(bot, kind, phase, hero, creep, back, approach, now)
    return {
        kind = kind,
        phase = phase,
        startedAt = now,
        steppedAt = now,
        hero = hero,
        tpid = hero:GetPlayerID(),
        creep = creep,
        mv = 0,
        sty = 0,
        approachTime = ____exports.SETTINGS.ApproachTimeMax,
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
function finish(bot, a, result, now, gap)
    attempts[bot:GetPlayerID()] = nil
    if a.kind == "feed" then
        Laning.SetFed(bot, nil)
    end
    if a.kind == "tower" then
        towerEnd[bot:GetPlayerID()] = now
    end
    local ____Telemetry_Event_6 = Telemetry.Event
    local ____array_5 = __TS__SparseArrayNew(
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
            a.kind == "feed" and live(a.creep) and math.floor(frac(a.creep) * 100) / 100 or nil
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
        {"own", a.own},
        {"fc", a.fc},
        {"td", a.td},
        {"out", a.out},
        {"sty", a.kind == "feed" and a.sty or nil},
        {"nd", a.nd},
        {"src", a.src},
        {"ad", a.ad},
        {
            "apt",
            a.ad ~= nil and math.floor(a.approachTime * 100) / 100 or nil
        },
        {
            "md",
            result == "stale" and (a.left or bot:GetActiveMode()) or nil
        }
    )
    local ____temp_4
    if result == "stale" then
        local ____opt_2 = Tasks.Current(bot)
        ____temp_4 = ____opt_2 and ____opt_2.label or "-"
    else
        ____temp_4 = nil
    end
    __TS__SparseArrayPush(
        ____array_5,
        {"lbl", ____temp_4},
        {
            "gap",
            gap ~= nil and math.floor(gap * 100) / 100 or nil
        },
        {
            "drop",
            a.droppedAt ~= nil and math.floor((a.droppedAt - (a.orderedAt or a.startedAt)) * 100) / 100 or nil
        },
        {
            "dur",
            math.floor((now - a.startedAt) * 100) / 100
        }
    )
    ____Telemetry_Event_6(
        "aggro",
        {__TS__SparseArraySpread(____array_5)}
    )
end
function seenAt(u)
    if u:IsNull() or not u:IsAlive() then
        return nil
    end
    return u:GetLocation() or nil
end
function drawnOn(bot, target)
    local out = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1200, true)) do
        do
            local __continue132
            repeat
                if not valid(c) then
                    __continue132 = true
                    break
                end
                local t = c:GetAttackTarget()
                if t ~= nil and t ~= nil and not t:IsNull() and t == target then
                    out[#out + 1] = c
                end
                __continue132 = true
            until true
            if not __continue132 then
                break
            end
        end
    end
    return out
end
function watch(bot, a, now)
    if not bot:IsAlive() then
        return finish(bot, a, "died", now)
    end
    local dead = not live(a.creep)
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
    elseif a.kind == "back" then
        local out = 0
        for ____, s0 in ipairs(a.start or ({})) do
            local u = s0.unit
            local l = seenAt(u)
            if l ~= nil and d2(l, a.back) <= ____exports.SETTINGS.BackOut then
                out = out + 1
            end
        end
        a.out = out
        return finish(bot, a, out > 0 and "ok" or "stayed", now)
    else
        if now - (a.walkedAt or a.startedAt) < ____exports.SETTINGS.TowerWatch then
            return
        end
        local out = 0
        local tl = a.tower:GetLocation()
        for ____, s0 in ipairs(a.start or ({})) do
            local u = s0.unit
            local l = seenAt(u)
            if l ~= nil and d2(l, tl) >= TowerOrderR() then
                out = out + 1
            end
        end
        a.out = out
        return finish(bot, a, out > 0 and "ok" or "stayed", now)
    end
end
____exports.SETTINGS = {
    Cooldown = 3.1,
    DrawR = 450,
    Every = 0.25,
    MinHp = 0.45,
    HeroMargin = 250,
    TowerR = 1000,
    TowerOrderMargin = 56,
    FeedCreepHp = 0.25,
    OwnTowerR = 800,
    TowerSeek = 1000,
    TowerPast = 250,
    TowerApproachMax = 900,
    TowerApproachTime = 2.5,
    TowerBack = 450,
    TowerWalk = 1.8,
    TowerWatch = 1.5,
    SkipEvery = 3,
    FightR = 700,
    FeedMinCreeps = 1,
    ApproachBack = 380,
    ApproachMax = 900,
    ApproachSlack = 0.4,
    ApproachTimeMax = 3.5,
    FeedBack = 250,
    DropNear = 220,
    DropAfter = 0.8,
    DropBy = 1.8,
    DrawCheck = 1,
    MovedR = 120,
    BusyWithin = 1.5,
    StaleActing = 0.5,
    StaleWatch = 3,
    StaleCap = 10,
    UnsafeMargin = 0,
    HurtShare = 0.12,
    FeedWatch = 30,
    FeedHeroClear = 300,
    BackArrive = 150,
    BackWalk = 10,
    BackOut = 900,
    CoreNear = 1600
}
attempts = {}
local orderedAt = {}
local decidedAt = {}
--- Our ranged creeps already fed (one feed per creep).
local fed = {}
--- Last draw per team and lane: one draw per lane at a time.
local laneDraw = {}
local pushCache = {}
local lastSkip = {}
towerEnd = {}
function ____exports.TowerMovedAt(pid)
    return towerEnd[pid]
end
local function laneKey(team, lane)
    return (tostring(team) .. ":") .. tostring(lane)
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
--- Whether an attempt last stepped `gap` seconds ago is stale: after another mode held the bot (`left`), the watch tolerates a
-- short loss of the frame and acting does not; with the bot in laning throughout, only a gap past StaleCap.
function ____exports.Stale(phase, gap, left)
    if left == nil then
        left = true
    end
    if not left then
        return gap > ____exports.SETTINGS.StaleCap
    end
    return gap > (phase == "watch" and ____exports.SETTINGS.StaleWatch or ____exports.SETTINGS.StaleActing)
end
--- Every frame (States.Tick, from ItemUsageThink, whichever mode runs): notes another mode holding the bot during an attempt.
function ____exports.Tick(bot)
    local a = attempts[bot:GetPlayerID()]
    if a == nil then
        return
    end
    if a.phase == "watch" then
        local now = DotaTime()
        a.steppedAt = now
        a.left = nil
        watch(bot, a, now)
        return
    end
    if a.left ~= nil then
        return
    end
    local mode = bot:GetActiveMode()
    if mode ~= BotMode.Laning then
        a.left = mode
    end
end
--- Pure: why the lane controller refuses the feed this wave, or undefined (slice lh-draw step 2, user 09/11/2026: the deny
-- feed runs on every wave, not only on the controller's `back` waves; its drill measured no lane move, -10 +- 396). A live
-- decision refuses it on a `shove` wave (the feed would pull back the wave the shove pushes); a drill's forced lever other
-- than `feed` refuses it (a lever drill's control arm). Our pull out on the lane is the shared gate's (`pull`).
function ____exports.CtlVeto(d, forced)
    if forced ~= nil then
        local ____temp_0
        if forced == "feed" then
            ____temp_0 = nil
        else
            ____temp_0 = "ctl_forced"
        end
        return ____temp_0
    end
    if d ~= nil and (d.mode == "shove" or __TS__ArrayIncludes(d.levers, "shove")) then
        return "ctl_shove"
    end
    return nil
end
--- Pure: the tower move's order point, on the line from their tower `(tx, ty)` through their creeps' centre `(cx, cy)`:
-- TowerPast beyond the creeps, never inside TowerOrderR() of the tower.
function ____exports.TowerPoint(tx, ty, cx, cy)
    local dx = cx - tx
    local dy = cy - ty
    local len = math.max(
        1,
        math.sqrt(dx * dx + dy * dy)
    )
    local r = math.max(
        len + ____exports.SETTINGS.TowerPast,
        TowerOrderR()
    )
    return tx + dx / len * r, ty + dy / len * r
end
--- Pure: seconds the bot gets to walk `dist` to the approach point at `speed` before it orders from where it stands.
function ____exports.ApproachTime(dist, speed)
    return math.min(
        ____exports.SETTINGS.ApproachTimeMax,
        dist / math.max(1, speed) + ____exports.SETTINGS.ApproachSlack
    )
end
--- Pure: whether the point `(x, y)` lies inside `team`'s wave hold point on `lane` (closer to our T1 along the path than lane_push
-- TargetOf). The feed walks their creeps to its back point, so a back point inside it draws them where wave_hold meets them.
function ____exports.InsideHold(path, team, lane, x, y)
    local s = LanePush.Project(path, x, y)
    local t1, dir = LanePush.OwnT1(path, team)
    return dir * (s - t1) < LanePush.TargetOf(lane)
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
    local ____ok_1
    if ok then
        ____ok_1 = r
    else
        ____ok_1 = nil
    end
    local v = ____ok_1
    pushCache[key] = {t = now, r = v}
    return v
end
local function coreAway(bot)
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue33
                repeat
                    local h = GetTeamMember(i)
                    if h == nil or h == nil or h == bot or h:IsNull() then
                        __continue33 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(h)
                    if pos == nil or pos > 3 or h:GetAssignedLane() ~= lane then
                        __continue33 = true
                        break
                    end
                    if h:IsAlive() and GetUnitToUnitDistance(h, bot) <= ____exports.SETTINGS.CoreNear then
                        return false
                    end
                    __continue33 = true
                until true
                if not __continue33 then
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
local function heroSafe(at, heroes, margin)
    if margin == nil then
        margin = ____exports.SETTINGS.HeroMargin
    end
    for ____, h in ipairs(heroes) do
        if GetUnitToLocationDistance(h, at) <= h:GetAttackRange() + h:GetBoundingRadius() * 2 + margin then
            return false
        end
    end
    return true
end
local TOWERS = {
    Tower.Top1,
    Tower.Mid1,
    Tower.Bot1,
    Tower.Top2,
    Tower.Mid2,
    Tower.Bot2
}
local function enemyOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
--- The nearest alive tier-1 or tier-2 tower of `team` within `r` of `at`.
local function towerNear(at, team, r)
    local best
    local bestD = r
    for ____, id in ipairs(TOWERS) do
        do
            local __continue54
            repeat
                local t = GetTower(team, id)
                if t == nil or t == nil or not t:IsAlive() then
                    __continue54 = true
                    break
                end
                local d = d2(
                    t:GetLocation(),
                    at
                )
                if d <= bestD then
                    best = t
                    bestD = d
                end
                __continue54 = true
            until true
            if not __continue54 then
                break
            end
        end
    end
    return best
end
local function nearTower(at, team, r)
    if r == nil then
        r = ____exports.SETTINGS.TowerR
    end
    return towerNear(
        at,
        enemyOf(team),
        r
    ) ~= nil
end
--- The enemy hero the order names: the nearest visible one anywhere (the draw comes from where the bot stands).
local function orderTarget(bot)
    local best
    local bestD = math.huge
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue61
            repeat
                if not valid(h) or h:IsIllusion() then
                    __continue61 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < bestD then
                    best = h
                    bestD = d
                end
                __continue61 = true
            until true
            if not __continue61 then
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
                local __continue66
                repeat
                    local h = GetTeamMember(i)
                    if h == nil or h == nil or h:IsNull() then
                        __continue66 = true
                        break
                    end
                    if h:GetAssignedLane() == lane and PullJob.Running(h) then
                        return true
                    end
                    __continue66 = true
                until true
                if not __continue66 then
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
        bot:GetTeam(),
        TowerOrderR()
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
local function tryTower(bot, heroes, now)
    local team = bot:GetTeam()
    local tw = towerNear(
        bot:GetLocation(),
        enemyOf(team),
        ____exports.SETTINGS.TowerSeek + ____exports.SETTINGS.TowerApproachMax
    )
    if tw == nil then
        return nil, "none"
    end
    local tl = tw:GetLocation()
    local ours = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1600, false)) do
        if valid(c) and isLaneCreep(c) and d2(
            c:GetLocation(),
            tl
        ) <= LaneConfig.TowerReach() then
            ours = ours + 1
        end
    end
    local theirs = enemyCreepsNear(bot, tl, ____exports.SETTINGS.TowerSeek)
    if ours == 0 or #theirs == 0 then
        return nil, "none"
    end
    local cx = 0
    local cy = 0
    for ____, c in ipairs(theirs) do
        cx = cx + c:GetLocation().x
        cy = cy + c:GetLocation().y
    end
    local px, py = ____exports.TowerPoint(tl.x, tl.y, cx / #theirs, cy / #theirs)
    local at = Vector(
        px,
        py,
        bot:GetLocation().z
    )
    local drawable = enemyCreepsNear(bot, at, ____exports.SETTINGS.DrawR)
    if #drawable == 0 then
        return nil, "draw_far"
    end
    if GetUnitToLocationDistance(bot, at) > ____exports.SETTINGS.TowerApproachMax then
        return nil, "approach_far"
    end
    if not heroSafe(at, heroes) then
        return nil, "unsafe"
    end
    if #laneTargets(bot, ____exports.SETTINGS.BusyWithin, true) > 0 then
        return nil, "busy"
    end
    local hero = orderTarget(bot)
    if hero == nil then
        return nil, "no_target"
    end
    local back = along(
        at,
        backDir(
            team,
            bot:GetAssignedLane(),
            at
        ),
        ____exports.SETTINGS.TowerBack
    )
    local a = newAttempt(
        bot,
        "tower",
        "approach",
        hero,
        drawable[1],
        back,
        at,
        now
    )
    a.tower = tw
    a.ad = math.floor(GetUnitToLocationDistance(bot, at))
    a.approachTime = ____exports.SETTINGS.TowerApproachTime
    return a, "go"
end
local function nearOwnTower(at, team)
    return towerNear(at, team, ____exports.SETTINGS.OwnTowerR) ~= nil
end
local function tryFeed(bot, heroes, now)
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    local ranged
    local none = "none"
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1200, false)) do
        do
            local __continue98
            repeat
                if not valid(c) or not isLaneCreep(c) or not isRanged(c) then
                    __continue98 = true
                    break
                end
                if fed[c] == true then
                    none = "fed"
                elseif frac(c) < ____exports.SETTINGS.FeedCreepHp then
                    none = none == "fed" and none or "low"
                else
                    ranged = c
                end
                __continue98 = true
            until true
            if not __continue98 then
                break
            end
        end
    end
    if ranged == nil then
        return nil, "no_ranged_" .. none
    end
    local LaneControl = require(GetScriptDirectory().."/FunLib/humaniser/lane_control")
    local veto = ____exports.CtlVeto(
        LaneControl.Current(team, lane),
        LaneControl.ForcedLever(
            Overrides.Get("ForceLever"),
            team,
            lane
        )
    )
    if veto ~= nil then
        return nil, veto
    end
    if nearOwnTower(
        ranged:GetLocation(),
        team
    ) then
        return nil, "own_tower"
    end
    local fighting = enemyCreepsNear(
        bot,
        ranged:GetLocation(),
        ____exports.SETTINGS.FightR
    )
    if #fighting < ____exports.SETTINGS.FeedMinCreeps then
        return nil, "few_creeps"
    end
    for ____, h in ipairs(heroes) do
        if GetUnitToUnitDistance(h, ranged) <= h:GetAttackRange() + h:GetBoundingRadius() + ____exports.SETTINGS.FeedHeroClear then
            return nil, "hero_on_ranged"
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
    local ad = GetUnitToLocationDistance(bot, approach)
    if ad > ____exports.SETTINGS.ApproachMax then
        return nil, "approach_far", ad
    end
    if #enemyCreepsNear(bot, approach, ____exports.SETTINGS.DrawR) < ____exports.SETTINGS.FeedMinCreeps then
        return nil, "approach_creeps"
    end
    local back = along(
        ranged:GetLocation(),
        dir,
        ____exports.SETTINGS.FeedBack
    )
    local path = LanePush.PathOf(lane)
    if path ~= nil and ____exports.InsideHold(
        path,
        team,
        lane,
        back.x,
        back.y
    ) then
        return nil, "inside_hold"
    end
    if not heroSafe(approach, heroes) or not heroSafe(back, heroes) then
        return nil, "unsafe"
    end
    if nearTower(approach, team) then
        return nil, "tower"
    end
    if #laneTargets(bot, ____exports.SETTINGS.BusyWithin, true) > 0 then
        return nil, "busy"
    end
    local hero = orderTarget(bot)
    if hero == nil then
        return nil, "no_target"
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
    a.ad = math.floor(ad)
    a.approachTime = ____exports.ApproachTime(
        ad,
        bot:GetCurrentMovementSpeed()
    )
    local r = pushRead(team, lane)
    if r ~= nil then
        a.q = math.floor(r.q * 100) / 100
        a.st = r.state
        a.own = math.floor(r.own)
        a.fc = math.floor(r.own + r.move)
    end
    return a, "go"
end
--- Enemy creeps near at the order that have since moved MovedR or more (drawn off their fight).
function ____exports.MovedOf(start)
    local n = 0
    for ____, s0 in ipairs(start or ({})) do
        local l = seenAt(s0.unit)
        if l ~= nil and d2(
            l,
            Vector(s0.x, s0.y, l.z)
        ) >= ____exports.SETTINGS.MovedR then
            n = n + 1
        end
    end
    return n
end
--- wave_hold's drag: draw their creeps near the bot and walk them to `to` (behind our T1). False when a move already runs or a
-- shared gate (the draw clock, another hero's draw on the lane, HP, a trade) says no; the pull gate does not apply.
function ____exports.StartBack(bot, to, src)
    if src == nil then
        src = "drag"
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    if attempts[pid] ~= nil or not Ours.On("LaneAggro") then
        return false
    end
    if not ____exports.CooldownClear(
        now,
        orderedAt[pid],
        CoreTrade.PrimedAt(pid)
    ) then
        return false
    end
    if ____exports.LaneHeld(
        now,
        pid,
        laneDraw[laneKey(
            bot:GetTeam(),
            bot:GetAssignedLane()
        )]
    ) then
        return false
    end
    if frac(bot) < ____exports.SETTINGS.MinHp then
        return false
    end
    local near = enemyCreepsNear(
        bot,
        bot:GetLocation(),
        ____exports.SETTINGS.DrawR
    )
    if #near == 0 then
        return false
    end
    local hero = orderTarget(bot)
    if hero == nil then
        return false
    end
    local a = newAttempt(
        bot,
        "back",
        "walk",
        hero,
        near[1],
        to,
        nil,
        now
    )
    a.src = src
    a.nd = 0
    start(bot, a)
    return true
end
--- Keeps the order's hero, or re-picks it (orderTarget's rule) once it has left vision: any visible enemy hero draws the creeps
-- (EC-053), so losing the first one need not end the move (obs0611: 11% of feeds ended `cancelled` that way). False when none is seen.
local function retarget(bot, a)
    if valid(a.hero) then
        return true
    end
    local h = orderTarget(bot)
    if h == nil then
        return false
    end
    a.hero = h
    a.tpid = h:GetPlayerID()
    return true
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
    if a.orderedAt == nil and not retarget(bot, a) then
        finish(bot, a, "cancelled", now)
        return false
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
        local heroes = enemyHeroes(bot, 1600)
        if not heroSafe(at, heroes, ____exports.SETTINGS.UnsafeMargin) or a.kind == "feed" and not heroSafe(a.back, heroes, ____exports.SETTINGS.UnsafeMargin) then
            finish(bot, a, "unsafe", now)
            return false
        end
        if GetUnitToLocationDistance(bot, at) > 60 and now - a.startedAt < a.approachTime then
            bot:Action_MoveToLocation(at)
            return true
        end
        if not live(a.creep) or not retarget(bot, a) then
            finish(bot, a, "cancelled", now)
            return false
        end
        a.phase = "walk"
    end
    if a.orderedAt == nil then
        if a.kind == "feed" and #enemyCreepsNear(
            bot,
            bot:GetLocation(),
            ____exports.SETTINGS.DrawR
        ) < ____exports.SETTINGS.FeedMinCreeps then
            fed[a.creep] = true
            finish(bot, a, "short", now)
            return false
        end
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
        a.td = math.floor(GetUnitToUnitDistance(bot, a.hero))
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
        if a.nd ~= nil then
            a.nd = a.nd + 1
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
        ____exports.MovedOf(a.start)
    )
    if t >= ____exports.SETTINGS.DrawCheck and a.drawn == 0 and a.mv == 0 then
        finish(bot, a, "no_draw", now)
        return false
    end
    if a.kind == "feed" then
        local nearest
        if live(a.creep) then
            for ____, c in ipairs(drawnOn(bot, bot)) do
                local d = GetUnitToUnitDistance(c, a.creep)
                if nearest == nil or d < nearest then
                    nearest = d
                end
            end
            for ____, s0 in ipairs(a.start or ({})) do
                do
                    local __continue180
                    repeat
                        local u = s0.unit
                        local l = seenAt(u)
                        if l == nil or d2(
                            l,
                            Vector(s0.x, s0.y, 0)
                        ) < ____exports.SETTINGS.MovedR then
                            __continue180 = true
                            break
                        end
                        local d = GetUnitToUnitDistance(u, a.creep)
                        if nearest == nil or d < nearest then
                            nearest = d
                        end
                        __continue180 = true
                    until true
                    if not __continue180 then
                        break
                    end
                end
            end
        end
        if not live(a.creep) then
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
    if a.kind == "back" then
        if GetUnitToLocationDistance(bot, a.back) > ____exports.SETTINGS.BackArrive and now - a.startedAt < ____exports.SETTINGS.BackWalk then
            if #drawnOn(bot, bot) == 0 and ____exports.CooldownClear(
                now,
                orderedAt[pid],
                CoreTrade.PrimedAt(pid)
            ) and retarget(bot, a) then
                bot:Action_AttackUnit(a.hero, true)
                a.orderedAt = now
                orderedAt[pid] = now
                CoreTrade.NotePrimed(pid, now)
                laneDraw[laneKey(
                    bot:GetTeam(),
                    bot:GetAssignedLane()
                )] = {pid = pid, at = now}
                a.nd = (a.nd or 0) + 1
                return true
            end
            bot:Action_MoveToLocation(a.back)
            return true
        end
        a.walkedAt = now
        a.phase = "watch"
        return false
    end
    if t < ____exports.SETTINGS.TowerWalk then
        bot:Action_MoveToLocation(a.back)
        return true
    end
    a.walkedAt = now
    a.phase = "watch"
    return false
end
local function skip(bot, why, now, ad)
    local pid = bot:GetPlayerID()
    local last = lastSkip[pid]
    if last ~= nil and (last.why == why or now - last.at < ____exports.SETTINGS.SkipEvery) then
        return
    end
    lastSkip[pid] = {why = why, at = now}
    Telemetry.Event(
        "aggro_skip",
        {
            {"pid", pid},
            {
                "role",
                roleOf(bot) or "?"
            },
            {"why", why},
            {
                "ad",
                ad ~= nil and math.floor(ad) or nil
            }
        }
    )
end
--- Steps the bot's open attempt: the acting frame's result, or undefined when nothing acted (watching, ended or none).
local function stepOpen(bot, now)
    local pid = bot:GetPlayerID()
    local a = attempts[pid]
    if a ~= nil and ____exports.Stale(a.phase, now - a.steppedAt, a.left ~= nil) then
        finish(
            bot,
            a,
            "stale",
            now,
            now - a.steppedAt
        )
    elseif a ~= nil then
        a.steppedAt = now
        a.left = nil
    end
    if a == nil or attempts[pid] ~= a then
        return nil
    end
    if a.phase ~= "watch" then
        return act(bot, a, now)
    end
    if a.kind == "feed" then
        Laning.SetFed(bot, a.creep)
        local ____opt_7 = Laning.SpotInfo(bot)
        if (____opt_7 and ____opt_7.anchor) == "fed" then
            a.sty = 1
        end
    end
    watch(bot, a, now)
    return nil
end
--- Steps only an open attempt, never deciding a new draw: a core's draw while its laning body is not running.
function ____exports.StepOpen(bot)
    local ____stepOpen_result_9 = stepOpen(
        bot,
        DotaTime()
    )
    if ____stepOpen_result_9 == nil then
        ____stepOpen_result_9 = false
    end
    return ____stepOpen_result_9
end
--- One frame of the module for this bot: reads a running move's result, steps a running move, or decides whether to start one.
-- True when it gave the bot's order this frame (the caller's other steps then stay off).
function ____exports.Step(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local acted = stepOpen(bot, now)
    if acted ~= nil then
        return acted
    end
    if attempts[pid] ~= nil or not ____exports.Owns(bot) then
        return false
    end
    local last = decidedAt[pid]
    if last ~= nil and now - last < ____exports.SETTINGS.Every then
        return false
    end
    decidedAt[pid] = now
    local g = gate(bot, now)
    if g ~= nil then
        skip(bot, g, now)
        return false
    end
    local heroes = enemyHeroes(bot, 1600)
    if not heroSafe(
        bot:GetLocation(),
        heroes
    ) then
        skip(bot, "reach", now)
        return false
    end
    local ad
    local tw, twWhy = tryTower(bot, heroes, now)
    local next = tw
    local why = "tower:" .. twWhy
    if next == nil and twWhy == "none" then
        local fd, fdWhy, fdAd = tryFeed(bot, heroes, now)
        next = fd
        ad = fdAd
        why = "feed:" .. fdWhy
    end
    if next == nil then
        skip(bot, why, now, ad)
        return false
    end
    lastSkip[pid] = nil
    start(bot, next)
    return act(bot, next, now)
end
--- An attempt is open (acting or watching): its caller keeps stepping it so it ends cleanly.
function ____exports.Pending(bot)
    return attempts[bot:GetPlayerID()] ~= nil
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
    Laning.ClearFed()
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
    for k in pairs(lastSkip) do
        lastSkip[k] = nil
    end
    for k in pairs(towerEnd) do
        towerEnd[k] = nil
    end
end
return ____exports
