--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local noteHeroTarget, heroHitAt
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHits = require(GetScriptDirectory().."/FunLib/humaniser/lane_hits")
local LaneOffers = require(GetScriptDirectory().."/FunLib/humaniser/lane_offers")
local LaneRead = require(GetScriptDirectory().."/FunLib/humaniser/lane_read")
local Offer = require(GetScriptDirectory().."/FunLib/humaniser/offer")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function noteHeroTarget(bot, now)
    local tg = bot:GetAttackTarget()
    if tg ~= nil and tg ~= nil and tg:IsHero() and tg:GetTeam() ~= bot:GetTeam() then
        heroHitAt[bot:GetPlayerID()] = now
    end
end
____exports.SETTINGS = {
    Every = 0.2,
    Reach = 300,
    Drawn = 350,
    Back = 250,
    Clash = 1200,
    Draw = 2.5,
    MaxWalk = 1,
    TowerMargin = 100,
    Cooldown = 3,
    Step = 64,
    TowerRadius = 2500
}
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- The draw spot: the hero's place when within `reach` of the creep, else the point at `reach` from it on the line to the hero.
function ____exports.DrawSpot(hero, creep, reach)
    return Offer.StandSpot(hero, creep, reach)
end
--- The hand-over spot: `back` behind our ranged creep on the line from the clash's centre through it.
function ____exports.HandSpot(ranged, clash, back)
    local d = dist(ranged, clash)
    if d == 0 then
        return {x = ranged.x, y = ranged.y}
    end
    return {x = ranged.x + (ranged.x - clash.x) / d * back, y = ranged.y + (ranged.y - clash.y) / d * back}
end
--- What the draw gives up over `window` seconds.
function ____exports.GivenUp(ts, window)
    local g = {all = 0, miss = 0, dr = 0, dm = 0}
    for ____, t in ipairs(ts) do
        do
            local __continue7
            repeat
                if t.feed or t.due >= window then
                    __continue7 = true
                    break
                end
                g.all = g.all + 1
                if t.kind == "lasthit" then
                    if t.drawn then
                        if t.ranged then
                            g.dr = g.dr + 1
                        else
                            g.dm = g.dm + 1
                            g.miss = g.miss + 1
                        end
                    else
                        g.miss = g.miss + 1
                    end
                elseif t.undrawn then
                    g.miss = g.miss + 1
                end
                __continue7 = true
            until true
            if not __continue7 then
                break
            end
        end
    end
    return g
end
--- The go rule's failed checks, in the order s6b gives them.
function ____exports.Checks(f)
    local out = {}
    if f.k == "dn" and f.onR > 0 then
        out[#out + 1] = "onr"
    end
    if f.miss > 0 then
        out[#out + 1] = "due"
    end
    if f.walk > ____exports.SETTINGS.MaxWalk then
        out[#out + 1] = "far"
    end
    if f.seen == 0 then
        out[#out + 1] = "unseen"
    end
    if f.tw ~= nil and f.tw < ____exports.SETTINGS.TowerMargin then
        out[#out + 1] = "etower"
    end
    if f.covering > 0 then
        out[#out + 1] = "covered"
    end
    if f.deadly then
        out[#out + 1] = "danger"
    end
    if f.rh > f.fh + ____exports.SETTINGS.Step then
        out[#out + 1] = "up"
    end
    if f.sinceHero ~= nil and f.sinceHero < ____exports.SETTINGS.Cooldown then
        out[#out + 1] = "cd"
    end
    return out
end
local opps = {}
local readAt = {}
heroHitAt = {}
function ____exports.ResetCache()
    for k in pairs(opps) do
        opps[k] = nil
    end
    for k in pairs(readAt) do
        readAt[k] = nil
    end
    for k in pairs(heroHitAt) do
        heroHitAt[k] = nil
    end
end
local function due(pid, now)
    local n = math.floor((now + pid % 2 * (____exports.SETTINGS.Every / 2)) / ____exports.SETTINGS.Every + 0.000001)
    if readAt[pid] == n then
        return false
    end
    readAt[pid] = n
    return true
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
local function r1(x)
    return math.floor(x * 10 + 0.5) / 10
end
--- A hero the read covers: a bot whose position the trip table lets act on an `aggro` row.
function ____exports.MayOffer(bot)
    return bot:IsBot() and TripTable.Does(
        "aggro",
        LaneConfig.PositionOf(bot)
    )
end
--- The draw's row is on for this hero's team (Ours.Team scopes it).
function ____exports.RowOn()
    return Ours.On("LaneAggro")
end
local function line(bot, o)
    local s = o.snap
    local own = ____exports.RowOn()
    local go = own and o.aid ~= nil
    local ____Telemetry_Event_4 = Telemetry.Event
    local ____array_3 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "aggro"}
    )
    local ____go_0
    if go then
        ____go_0 = o.aid
    else
        ____go_0 = nil
    end
    __TS__SparseArrayPush(____array_3, {"aid", ____go_0}, {"go", go and 1 or 0}, {"want", o.okFrom ~= nil and 1 or 0})
    local ____temp_2
    if not own then
        ____temp_2 = "off"
    else
        local ____go_1
        if go then
            ____go_1 = nil
        else
            ____go_1 = #s.fails > 0 and s.fails[1] or "nogo"
        end
        ____temp_2 = ____go_1
    end
    __TS__SparseArrayPush(
        ____array_3,
        {"why", ____temp_2},
        {"src", own and "own" or "shadow"},
        {"lane", o.lane},
        {"slot", o.first},
        {"cid", o.cid},
        {
            "wo",
            o.okFrom ~= nil and r1(o.okFrom - o.first) or nil
        },
        {"ak", s.f.k},
        {
            "arf",
            #s.fails > 0 and table.concat(s.fails, ",") or "-"
        },
        {"ard", o.reads},
        {"awr", o.wanted},
        {
            "walk",
            r2(s.f.walk)
        },
        {"an", s.drawn},
        {"am", s.melee},
        {"ao", s.f.onR},
        {
            "af",
            math.floor(s.f.fh + 0.5)
        },
        {
            "ar",
            math.floor(s.f.rh + 0.5)
        },
        {
            "arp",
            r2(s.rhp)
        },
        {
            "apw",
            r2(s.pw)
        },
        {"aes", s.f.seen},
        {
            "atw",
            s.f.tw ~= nil and math.floor(s.f.tw) or nil
        },
        {"eh", s.f.covering},
        {"adl", s.danger},
        {"ag0", s.g.all},
        {"ag1", s.g.miss},
        {"agr", s.g.dr},
        {"agm", s.g.dm}
    )
    ____Telemetry_Event_4(
        "choice",
        {__TS__SparseArraySpread(____array_3)}
    )
end
local function close(bot, pid)
    local o = opps[pid]
    if o == nil then
        return
    end
    line(bot, o)
    opps[pid] = nil
end
local function sameTeam(u, team)
    return u ~= nil and u ~= nil and u:GetTeam() == team
end
--- One read of the hero's chance: undefined when there is no clash near our ranged creep.
local function read(bot, ranged, theirs, mine, now)
    local team = bot:GetTeam()
    local rAt = ranged:GetLocation()
    local fight = {}
    local onR = 0
    local cz = 0
    local cx = 0
    local cy = 0
    for ____, c in ipairs(theirs) do
        do
            local __continue41
            repeat
                local at = c:GetLocation()
                if at == nil or at == nil or not c:IsAlive() then
                    __continue41 = true
                    break
                end
                local tg = c:GetAttackTarget()
                if not sameTeam(tg, team) then
                    __continue41 = true
                    break
                end
                if tg == ranged then
                    onR = onR + 1
                end
                if LaneRead.CreepKind(c:GetUnitName()) == "f" or dist(at, rAt) > ____exports.SETTINGS.Clash then
                    __continue41 = true
                    break
                end
                fight[#fight + 1] = c
                cz = cz + at.z
                cx = cx + at.x
                cy = cy + at.y
                __continue41 = true
            until true
            if not __continue41 then
                break
            end
        end
    end
    if #fight == 0 then
        return nil
    end
    local loc = bot:GetLocation()
    local hero = {x = loc.x, y = loc.y}
    local near
    local nd = math.huge
    for ____, c in ipairs(fight) do
        local d = dist(
            hero,
            c:GetLocation()
        )
        if d < nd then
            nd = d
            near = c:GetLocation()
        end
    end
    local spot = ____exports.DrawSpot(hero, near, ____exports.SETTINGS.Reach)
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local walk = math.max(0, nd - ____exports.SETTINGS.Reach) / speed
    local drawnSet = {}
    local drawnUnits = {}
    local drawn = 0
    local melee = 0
    for ____, c in ipairs(fight) do
        do
            local __continue51
            repeat
                if dist(
                    spot,
                    c:GetLocation()
                ) > ____exports.SETTINGS.Drawn then
                    __continue51 = true
                    break
                end
                drawnSet[c] = true
                drawnUnits[#drawnUnits + 1] = c
                drawn = drawn + 1
                if LaneRead.CreepKind(c:GetUnitName()) == "m" then
                    melee = melee + 1
                end
                __continue51 = true
            until true
            if not __continue51 then
                break
            end
        end
    end
    local fh = cz / #fight
    local rh = rAt.z
    local k = fh > rh + ____exports.SETTINGS.Step and "hg" or "dn"
    local ours = 0
    local theirsHp = 0
    for ____, c in ipairs(fight) do
        theirsHp = theirsHp + c:GetHealth()
    end
    for ____, c in ipairs(mine) do
        local at = c:GetLocation()
        if at ~= nil and at ~= nil and c:IsAlive() and dist(at, rAt) <= ____exports.SETTINGS.Clash then
            ours = ours + c:GetHealth()
        end
    end
    local enemies = {}
    local hitters = {}
    local target
    local td = math.huge
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue60
            repeat
                if not e:IsAlive() or e:IsIllusion() or not e:CanBeSeen() then
                    __continue60 = true
                    break
                end
                local at = e:GetLocation()
                if at == nil or at == nil then
                    __continue60 = true
                    break
                end
                local d = dist(hero, at)
                if d < td then
                    td = d
                    target = e
                end
                enemies[#enemies + 1] = {
                    x = at.x,
                    y = at.y,
                    pid = e:GetPlayerID(),
                    range = e:GetAttackRange(),
                    hull = e:GetBoundingRadius(),
                    dmg = e:GetAttackDamage(),
                    spa = 1
                }
                hitters[#hitters + 1] = e
                __continue60 = true
            until true
            if not __continue60 then
                break
            end
        end
    end
    local tw
    local hull = bot:GetBoundingRadius()
    for ____, t in ipairs(bot:GetNearbyTowers(____exports.SETTINGS.TowerRadius, true) or ({})) do
        do
            local __continue65
            repeat
                local at = t:GetLocation()
                if at == nil or at == nil then
                    __continue65 = true
                    break
                end
                local gap = dist(spot, at) - (t:GetAttackRange() + t:GetBoundingRadius() + hull)
                if tw == nil or gap < tw then
                    tw = gap
                end
                hitters[#hitters + 1] = t
                __continue65 = true
            until true
            if not __continue65 then
                break
            end
        end
    end
    local path = Offer.PathCost({
        from = hero,
        spot = spot,
        speed = speed,
        hull = hull,
        creeps = {},
        towers = {},
        enemies = enemies
    })
    local window = 2 * walk + ____exports.SETTINGS.Draw
    local ts = {}
    local offers = Tasks.Verbs().laneTargets(bot, {radius = LaneHits.READER_RADIUS, within = window})
    for ____, t in ipairs(offers) do
        do
            local __continue69
            repeat
                if t.kind == "prehit" or not LaneOffers.Reachable(t) then
                    __continue69 = true
                    break
                end
                local c = t.creep
                local undrawn = false
                if t.kind == "deny" then
                    for ____, x in ipairs(theirs) do
                        if x:GetAttackTarget() == c and drawnSet[x] ~= true then
                            undrawn = true
                        end
                    end
                    for ____, x in ipairs(hitters) do
                        if x:GetAttackTarget() == c then
                            undrawn = true
                        end
                    end
                end
                ts[#ts + 1] = {
                    kind = t.kind,
                    due = t.due,
                    ranged = t.ranged,
                    drawn = drawnSet[c] == true,
                    undrawn = undrawn,
                    feed = c == ranged
                }
                __continue69 = true
            until true
            if not __continue69 then
                break
            end
        end
    end
    local g = ____exports.GivenUp(ts, window)
    local danger = SafeGather.At(
        bot,
        Vector(spot.x, spot.y, 0),
        {remember = false}
    ).level
    local pid = bot:GetPlayerID()
    local hit = heroHitAt[pid]
    local f = {
        k = k,
        walk = walk,
        onR = onR,
        fh = fh,
        rh = rh,
        seen = #enemies,
        tw = tw,
        covering = path.covering,
        deadly = danger == "deadly",
        miss = g.miss,
        sinceHero = hit ~= nil and now - hit or nil
    }
    local hand = ____exports.HandSpot(rAt, {x = cx / #fight, y = cy / #fight}, ____exports.SETTINGS.Back)
    return {
        f = f,
        fails = ____exports.Checks(f),
        drawn = drawn,
        melee = melee,
        rhp = ranged:GetHealth() / math.max(
            ranged:GetMaxHealth(),
            1
        ),
        pw = ours / math.max(theirsHp, 1),
        g = g,
        danger = danger,
        spot = spot,
        hand = hand,
        target = target,
        drawnUnits = drawnUnits,
        ranged = ranged
    }
end
local function readFn(bot, ranged, theirs, mine, now)
    return read(
        bot,
        ranged,
        theirs,
        mine,
        now
    )
end
local timedRead
--- The open opportunity's ranged creep while it is still listed; else our ranged creep nearest the hero. One line per creep: with
-- two of ours in reach the nearest may swap, and the open one is kept until it dies or leaves the lists.
local function pickRanged(bot, mine, open)
    if open ~= nil then
        for ____, c in ipairs(mine) do
            if c == open and c:IsAlive() then
                return c
            end
        end
    end
    local ranged
    local rd = math.huge
    local loc = bot:GetLocation()
    for ____, c in ipairs(mine) do
        do
            local __continue85
            repeat
                if not c:IsAlive() or LaneRead.CreepKind(c:GetUnitName()) ~= "r" then
                    __continue85 = true
                    break
                end
                local at = c:GetLocation()
                if at == nil or at == nil then
                    __continue85 = true
                    break
                end
                local d = dist(loc, at)
                if d < rd then
                    rd = d
                    ranged = c
                end
                __continue85 = true
            until true
            if not __continue85 then
                break
            end
        end
    end
    return ranged
end
--- A fresh read for the draw's row at its go and after its walk-in (rule 5): the same read as the line's, on the open opportunity's
-- ranged creep or the nearest; counts nothing and writes no line. Undefined with no ranged creep of ours or no clash near it.
function ____exports.ReadNow(bot)
    local now = DotaTime()
    noteHeroTarget(bot, now)
    local mine = bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false)
    local ____pickRanged_8 = pickRanged
    local ____bot_7 = bot
    local ____opt_5 = opps[bot:GetPlayerID()]
    local ranged = ____pickRanged_8(____bot_7, mine, ____opt_5 and ____opt_5.ranged)
    if ranged == nil then
        return nil
    end
    return read(
        bot,
        ranged,
        bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, true),
        mine,
        now
    )
end
--- The draw's row went on our ranged creep `ranged`: the open opportunity on it carries the attempt's aid to its line.
function ____exports.NoteGo(bot, ranged, aid)
    local o = opps[bot:GetPlayerID()]
    if o ~= nil and o.ranged == ranged and o.aid == nil then
        o.aid = aid
    end
end
--- The hero ordered an attack on an enemy hero now (the draw's order): the cooldown runs from it.
function ____exports.NoteHeroHit(bot)
    heroHitAt[bot:GetPlayerID()] = DotaTime()
end
--- The reference arm's denominator: the draw's chance read and logged (`src=shadow go=0 why=off`) for every core the trip table
-- covers. Reads and logs; nothing is ordered.
function ____exports.Shadow(bot)
    if not Telemetry.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    if not due(pid, now) or not ____exports.MayOffer(bot) then
        return
    end
    if not bot:IsAlive() or Drill.Held(bot) or not LaneConfig.InLaningPhase() or Tasks.Verbs() == nil then
        close(bot, pid)
        return
    end
    noteHeroTarget(bot, now)
    local mine = bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false)
    local ____pickRanged_12 = pickRanged
    local ____bot_11 = bot
    local ____opt_9 = opps[pid]
    local ranged = ____pickRanged_12(____bot_11, mine, ____opt_9 and ____opt_9.ranged)
    local o = opps[pid]
    if o ~= nil and o.ranged ~= ranged then
        close(bot, pid)
        o = nil
    end
    if ranged == nil then
        return
    end
    if timedRead == nil then
        timedRead = Telemetry.PerfStep("AO:read", readFn)
    end
    local s = timedRead(
        bot,
        ranged,
        bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, true),
        mine,
        now
    )
    if s == nil then
        return
    end
    if o == nil then
        o = {
            ranged = ranged,
            cid = Telemetry.CreepId(ranged),
            lane = bot:GetAssignedLane(),
            first = math.floor(now * 10) / 10,
            snap = s,
            reads = 0,
            wanted = 0
        }
        opps[pid] = o
    elseif #s.fails < #o.snap.fails then
        o.snap = s
    end
    o.reads = o.reads + 1
    if #s.fails == 0 then
        o.wanted = o.wanted + 1
        if o.okFrom == nil then
            o.okFrom = now
        end
    end
end
return ____exports
