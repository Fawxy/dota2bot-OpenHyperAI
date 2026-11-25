--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local UnitType = ____dota.UnitType
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHits = require(GetScriptDirectory().."/FunLib/humaniser/lane_hits")
local LaneOffers = require(GetScriptDirectory().."/FunLib/humaniser/lane_offers")
local LaneRead = require(GetScriptDirectory().."/FunLib/humaniser/lane_read")
local Offer = require(GetScriptDirectory().."/FunLib/humaniser/offer")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {SlackStep = 0.1, SlackCap = 99, TowerRadius = 2500}
local parts
--- pid -> creep id -> its opportunity.
local opps = {}
function ____exports.ResetCache()
    for k in pairs(opps) do
        opps[k] = nil
    end
end
local function r1(x)
    return math.floor(x * 10 + 0.5) / 10
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- A bot whose position the trip table lets act on a creep offer.
function ____exports.MayOffer(bot)
    return bot:IsBot() and TripTable.Does(
        "creep",
        LaneConfig.PositionOf(bot)
    )
end
local function enemyFormat(es)
    local out = {}
    for ____, e in ipairs(es) do
        out[#out + 1] = (((((((((tostring(e.pid) .. ":") .. tostring(math.floor(e.dist))) .. ":") .. tostring(math.floor(e.range))) .. ":") .. tostring(math.floor(e.dmg))) .. ":") .. tostring(r2(e.spa))) .. ":") .. tostring(r2(e.exp))
    end
    return table.concat(out, ";")
end
local function line(bot, o)
    local s = o.snap
    local want = o.okFrom ~= nil
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "creep"},
            {"go", 0},
            {"want", want and 1 or 0},
            {"why", "off"},
            {"src", "shadow"},
            {"lane", o.lane},
            {"slot", o.first},
            {
                "cid",
                Telemetry.CreepId(o.creep)
            },
            {"ck", o.ck},
            {"who", o.who},
            {
                "wo",
                o.okFrom ~= nil and r1(o.okFrom - o.first) or nil
            },
            {
                "wl",
                o.okFrom ~= nil and o.okTo ~= nil and r1(o.okTo - o.okFrom) or nil
            },
            {
                "walk",
                r2(s.walk)
            },
            {
                "due",
                r2(s.due)
            },
            {
                "dies",
                s.dies == math.huge and -1 or r2(s.dies)
            },
            {
                "slk",
                r2(math.min(s.slk, ____exports.SETTINGS.SlackCap))
            },
            {
                "hpp",
                r2(s.hpp)
            },
            {"mode", s.mode},
            {
                "crhp",
                math.floor(s.crhp)
            },
            {"g2", s.given.due},
            {"g2r", s.given.ranged},
            {"pc", s.path.creeps},
            {
                "pd",
                math.floor(s.path.cdps + 0.5)
            },
            {"ptw", s.path.tower and 1 or 0},
            {"eh", s.path.covering},
            {
                "exs",
                r2(s.path.exposure)
            },
            {
                "en",
                enemyFormat(s.path.enemies)
            },
            {"kb", s.kb},
            {
                "kt",
                s.kt ~= nil and r2(s.kt) or nil
            },
            {
                "md",
                math.floor(s.md)
            },
            {
                "ed",
                math.floor(s.ed)
            },
            {"ein", s.ein},
            {"atk", o.atk and 1 or 0}
        }
    )
end
local function closeAll(bot, pid)
    local m = opps[pid]
    if m == nil then
        return
    end
    for cid, o in pairs(m) do
        line(bot, o)
        m[cid] = nil
    end
end
local LANES = {Lane.Top, Lane.Mid, Lane.Bot}
--- The creep's lane row in the lane read, the hero's own lane tried first.
local function rowOf(bot, creep)
    local team = bot:GetTeam()
    local own = bot:GetAssignedLane()
    local first = LaneHits.Of(team, own, creep)
    if first ~= nil then
        return first
    end
    for ____, lane in ipairs(LANES) do
        do
            local __continue17
            repeat
                if lane == own then
                    __continue17 = true
                    break
                end
                local r = LaneHits.Of(team, lane, creep)
                if r ~= nil then
                    return r
                end
                __continue17 = true
            until true
            if not __continue17 then
                break
            end
        end
    end
    return nil
end
local function towersOf(bot, f)
    if f.towers ~= nil then
        return f.towers
    end
    local out = {}
    for ____, t in ipairs(bot:GetNearbyTowers(____exports.SETTINGS.TowerRadius, true)) do
        local at = t:GetLocation()
        out[#out + 1] = {
            x = at.x,
            y = at.y,
            reach = t:GetAttackRange() + t:GetBoundingRadius() + f.hull
        }
    end
    f.towers = out
    return out
end
local function creepsOf(f)
    if f.creeps ~= nil then
        return f.creeps
    end
    local out = {}
    for ____, c in ipairs(f.enemyCreeps) do
        local at = c:GetLocation()
        local ____this_1
        ____this_1 = c
        local ____opt_0 = ____this_1.GetSecondsPerAttack
        local spa = ____opt_0 and ____opt_0(____this_1) or 1
        out[#out + 1] = {
            x = at.x,
            y = at.y,
            reach = c:GetAcquisitionRange() + c:GetBoundingRadius() + f.hull,
            dps = c:GetAttackDamage() / math.max(spa, 0.1)
        }
    end
    f.creeps = out
    return out
end
local function enemiesOf(f)
    if f.enemies ~= nil then
        return f.enemies
    end
    local out = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue31
            repeat
                if not e:IsAlive() or not e:CanBeSeen() then
                    __continue31 = true
                    break
                end
                local at = e:GetLocation()
                if at == nil or at == nil then
                    __continue31 = true
                    break
                end
                local ____at_x_4 = at.x
                local ____at_y_5 = at.y
                local ____temp_6 = e:GetPlayerID()
                local ____temp_7 = e:GetAttackRange()
                local ____temp_8 = e:GetBoundingRadius()
                local ____temp_9 = e:GetAttackDamage()
                local ____this_3
                ____this_3 = e
                local ____opt_2 = ____this_3.GetSecondsPerAttack
                out[#out + 1] = {
                    x = ____at_x_4,
                    y = ____at_y_5,
                    pid = ____temp_6,
                    range = ____temp_7,
                    hull = ____temp_8,
                    dmg = ____temp_9,
                    spa = ____opt_2 and ____opt_2(____this_3) or 1
                }
                __continue31 = true
            until true
            if not __continue31 then
                break
            end
        end
    end
    f.enemies = out
    return out
end
--- Whose hit the forecast says kills the creep, and when.
local function race(bot, creep)
    local row = rowOf(bot, creep)
    if row == nil then
        return {"none", nil}
    end
    local k = LaneHits.KillingHit(row)
    if k == nil then
        return {"none", nil}
    end
    if k.by == "tower" then
        return {"tower", k.t}
    end
    if k.by == "creep" then
        return {"creep", k.t}
    end
    local a = k.attacker
    if a == bot then
        return {"me", k.t}
    end
    return {
        a:GetTeam() == bot:GetTeam() and "mate" or "foe",
        k.t
    }
end
local function snapshot(bot, f, t, slack, others)
    local creep = t.creep
    local at = creep:GetLocation()
    local spot = Offer.StandSpot(
        f.hero,
        at,
        f.reach + creep:GetBoundingRadius()
    )
    local path = Offer.PathCost({
        from = f.hero,
        spot = spot,
        speed = f.speed,
        hull = f.hull,
        creeps = creepsOf(f),
        towers = towersOf(bot, f),
        enemies = enemiesOf(f)
    })
    local ed = 0
    local ein = 0
    local hull = creep:GetBoundingRadius()
    for ____, e in ipairs(enemiesOf(f)) do
        do
            local __continue42
            repeat
                if dist(e, at) > e.range + e.hull + hull then
                    __continue42 = true
                    break
                end
                ein = ein + 1
                if e.dmg > ed then
                    ed = e.dmg
                end
                __continue42 = true
            until true
            if not __continue42 then
                break
            end
        end
    end
    local kb, kt = unpack(parts.race(bot, creep))
    return {
        walk = t.walk,
        due = t.due,
        dies = t.dies,
        slk = slack,
        hpp = bot:GetHealth() / math.max(
            bot:GetMaxHealth(),
            1
        ),
        mode = HDebug.ModeName(bot:GetActiveMode()),
        crhp = creep:GetHealth(),
        given = Offer.GivenUp(others, 2 * t.walk + LaneOffers.ARRIVE_SLACK),
        path = path,
        kb = kb,
        kt = kt,
        md = bot:GetAttackDamage(),
        ed = ed,
        ein = ein
    }
end
local function partsOf()
    if parts ~= nil then
        return parts
    end
    parts = {
        targets = Telemetry.PerfStep(
            "CO:targets",
            function(bot) return Tasks.Verbs().laneTargets(bot, {radius = LaneHits.READER_RADIUS, within = 1}) end
        ),
        lists = Telemetry.PerfStep(
            "CO:lists",
            function(bot)
                local listed = {}
                local mine = bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false)
                local theirs = bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, true)
                for ____, c in ipairs(mine) do
                    listed[c] = true
                end
                for ____, c in ipairs(theirs) do
                    listed[c] = true
                end
                return {listed = listed, theirs = theirs}
            end
        ),
        snapshot = Telemetry.PerfStep("CO:snapshot", snapshot),
        race = Telemetry.PerfStep("CO:race", race)
    }
    return parts
end
--- One call per hero (the tick's ten a second): opens, updates and closes the hero's opportunities. Reads and logs; nothing is
-- ordered.
function ____exports.Shadow(bot)
    if not Telemetry.IsEnabled() or not ____exports.MayOffer(bot) then
        return
    end
    local pid = bot:GetPlayerID()
    if not bot:IsAlive() or Drill.Held(bot) or not LaneConfig.InLaningPhase() then
        closeAll(bot, pid)
        return
    end
    if Tasks.Verbs() == nil then
        return
    end
    local P = partsOf()
    local now = DotaTime()
    local targets = P.targets(bot)
    local ____P_lists_result_10 = P.lists(bot)
    local listed = ____P_lists_result_10.listed
    local theirs = ____P_lists_result_10.theirs
    local m = opps[pid]
    if m ~= nil then
        for cid, o in pairs(m) do
            do
                local __continue59
                repeat
                    if listed[o.creep] == true then
                        __continue59 = true
                        break
                    end
                    line(bot, o)
                    m[cid] = nil
                    __continue59 = true
                until true
                if not __continue59 then
                    break
                end
            end
        end
    end
    if #targets == 0 then
        return
    end
    if m == nil then
        m = {}
        opps[pid] = m
    end
    local loc = bot:GetLocation()
    local f = {
        hero = {x = loc.x, y = loc.y},
        speed = math.max(
            100,
            bot:GetCurrentMovementSpeed()
        ),
        hull = bot:GetBoundingRadius(),
        reach = bot:GetAttackRange() + bot:GetBoundingRadius(),
        enemyCreeps = theirs
    }
    local atkTarget = bot:GetAttackTarget()
    local slot = math.floor(now * 10) / 10
    for ____, t in ipairs(targets) do
        local creep = t.creep
        local cid = Telemetry.CreepId(creep)
        local a = Offer.Arrive(t.walk, LaneOffers.ARRIVE_SLACK, t.dies)
        local o = m[cid]
        local others = {}
        if o == nil or o.okFrom == nil and (a.ok or a.slack > o.snap.slk + ____exports.SETTINGS.SlackStep) then
            for ____, x in ipairs(targets) do
                if x ~= t and x.walk <= 0 then
                    others[#others + 1] = {due = x.due, ranged = x.ranged}
                end
            end
        end
        if o == nil then
            o = {
                creep = creep,
                lane = bot:GetAssignedLane(),
                first = slot,
                ck = LaneRead.CreepKind(creep:GetUnitName()),
                who = t.kind == "deny" and "o" or "t",
                snap = P.snapshot(
                    bot,
                    f,
                    t,
                    a.slack,
                    others
                ),
                atk = false
            }
            m[cid] = o
        elseif o.okFrom == nil and (a.ok or a.slack > o.snap.slk + ____exports.SETTINGS.SlackStep) then
            o.snap = P.snapshot(
                bot,
                f,
                t,
                a.slack,
                others
            )
        end
        if a.ok then
            if o.okFrom == nil then
                o.okFrom = now
            end
            o.okTo = now
        end
        if atkTarget ~= nil and atkTarget ~= nil and atkTarget == creep then
            o.atk = true
        end
    end
end
return ____exports
