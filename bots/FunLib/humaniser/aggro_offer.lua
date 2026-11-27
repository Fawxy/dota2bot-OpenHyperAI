--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHits = require(GetScriptDirectory().."/FunLib/humaniser/lane_hits")
local LaneOffers = require(GetScriptDirectory().."/FunLib/humaniser/lane_offers")
local LaneRead = require(GetScriptDirectory().."/FunLib/humaniser/lane_read")
local Offer = require(GetScriptDirectory().."/FunLib/humaniser/offer")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    Every = 0.2,
    Reach = 450,
    Drawn = 500,
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
local heroHitAt = {}
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
local function line(bot, o)
    local s = o.snap
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "aggro"},
            {"go", 0},
            {"want", o.okFrom ~= nil and 1 or 0},
            {"why", "off"},
            {"src", "shadow"},
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
        }
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
    for ____, c in ipairs(theirs) do
        do
            local __continue40
            repeat
                local at = c:GetLocation()
                if at == nil or at == nil or not c:IsAlive() then
                    __continue40 = true
                    break
                end
                local tg = c:GetAttackTarget()
                if not sameTeam(tg, team) then
                    __continue40 = true
                    break
                end
                if tg == ranged then
                    onR = onR + 1
                end
                if LaneRead.CreepKind(c:GetUnitName()) == "f" or dist(at, rAt) > ____exports.SETTINGS.Clash then
                    __continue40 = true
                    break
                end
                fight[#fight + 1] = c
                cz = cz + at.z
                __continue40 = true
            until true
            if not __continue40 then
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
    local drawn = 0
    local melee = 0
    for ____, c in ipairs(fight) do
        do
            local __continue50
            repeat
                if dist(
                    spot,
                    c:GetLocation()
                ) > ____exports.SETTINGS.Drawn then
                    __continue50 = true
                    break
                end
                drawnSet[c] = true
                drawn = drawn + 1
                if LaneRead.CreepKind(c:GetUnitName()) == "m" then
                    melee = melee + 1
                end
                __continue50 = true
            until true
            if not __continue50 then
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
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue59
            repeat
                if not e:IsAlive() or e:IsIllusion() or not e:CanBeSeen() then
                    __continue59 = true
                    break
                end
                local at = e:GetLocation()
                if at == nil or at == nil then
                    __continue59 = true
                    break
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
                __continue59 = true
            until true
            if not __continue59 then
                break
            end
        end
    end
    local tw
    local hull = bot:GetBoundingRadius()
    for ____, t in ipairs(bot:GetNearbyTowers(____exports.SETTINGS.TowerRadius, true)) do
        do
            local __continue63
            repeat
                local at = t:GetLocation()
                if at == nil or at == nil then
                    __continue63 = true
                    break
                end
                local gap = dist(spot, at) - (t:GetAttackRange() + t:GetBoundingRadius() + hull)
                if tw == nil or gap < tw then
                    tw = gap
                end
                hitters[#hitters + 1] = t
                __continue63 = true
            until true
            if not __continue63 then
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
            local __continue67
            repeat
                if t.kind == "prehit" or not LaneOffers.Reachable(t) then
                    __continue67 = true
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
                __continue67 = true
            until true
            if not __continue67 then
                break
            end
        end
    end
    local g = ____exports.GivenUp(ts, window)
    local danger = SafeGather.At(
        bot,
        Vector(spot.x, spot.y, 0)
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
        danger = danger
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
    local tg = bot:GetAttackTarget()
    if tg ~= nil and tg ~= nil and tg:IsHero() and tg:GetTeam() ~= bot:GetTeam() then
        heroHitAt[pid] = now
    end
    local ranged
    local rd = math.huge
    local loc = bot:GetLocation()
    local mine = bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false)
    for ____, c in ipairs(mine) do
        do
            local __continue83
            repeat
                if not c:IsAlive() or LaneRead.CreepKind(c:GetUnitName()) ~= "r" then
                    __continue83 = true
                    break
                end
                local at = c:GetLocation()
                if at == nil or at == nil then
                    __continue83 = true
                    break
                end
                local d = dist(loc, at)
                if d < rd then
                    rd = d
                    ranged = c
                end
                __continue83 = true
            until true
            if not __continue83 then
                break
            end
        end
    end
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
