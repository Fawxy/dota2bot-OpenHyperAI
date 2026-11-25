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
local dist, rowOf, heightAt, towersOf, ownTowersOf, creepsOf, enemiesOf, race, snapshot, partsOf, candidate, parts, rowLead, LANES
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
--- Where the hero's attack on the creep starts without a move: the engine's `attackReach` (attack range and both hulls), the one
-- fact the engine's walk and last-hit verb, this read and the row all use (ARCHITECTURE.md rule 1).
function ____exports.Reach(bot, creep)
    return Tasks.Verbs().attackReach(bot, creep)
end
--- The unit's attack cycle (s, `GetSecondsPerAttack`); 1 where the handle has none.
function ____exports.AttackCycle(u)
    local ____this_1
    ____this_1 = u
    local ____opt_0 = ____this_1.GetSecondsPerAttack
    return ____opt_0 and ____opt_0(____this_1) or 1
end
--- laneTargets' `within` for the hero: the engine's default 1 s, or one own attack cycle when longer, so a creep is offered by
-- the time the creep row may go on it (it goes once due within the walk plus one cycle, creep_row.ts `Due`). For a hero the row acts
-- on, also the row's own lead when that is longer (`SetRow`'s `lead`, creep_row.ts `EarlyLead`); a hero it is off for asks as before.
function ____exports.Within(bot)
    return math.max(
        1,
        ____exports.AttackCycle(bot),
        rowLead == nil and 0 or rowLead(bot)
    )
end
function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
function rowOf(bot, creep)
    local team = bot:GetTeam()
    local own = bot:GetAssignedLane()
    local first = LaneHits.Of(team, own, creep)
    if first ~= nil then
        return first
    end
    for ____, lane in ipairs(LANES) do
        do
            local __continue27
            repeat
                if lane == own then
                    __continue27 = true
                    break
                end
                local r = LaneHits.Of(team, lane, creep)
                if r ~= nil then
                    return r
                end
                __continue27 = true
            until true
            if not __continue27 then
                break
            end
        end
    end
    return nil
end
function heightAt(x, y)
    local ok, h = pcall(
        GetHeightLevel,
        Vector(x, y, 0)
    )
    return ok and type(h) == "number" and h or nil
end
function towersOf(bot, f)
    if f.towers ~= nil then
        return f.towers
    end
    local out = {}
    for ____, t in ipairs(bot:GetNearbyTowers(____exports.SETTINGS.TowerRadius, true)) do
        do
            local __continue34
            repeat
                local at = t:GetLocation()
                if at == nil or at == nil then
                    __continue34 = true
                    break
                end
                out[#out + 1] = {
                    x = at.x,
                    y = at.y,
                    reach = t:GetAttackRange() + t:GetBoundingRadius() + f.hull
                }
                __continue34 = true
            until true
            if not __continue34 then
                break
            end
        end
    end
    f.towers = out
    return out
end
function ownTowersOf(bot, f)
    if f.ownTowers ~= nil then
        return f.ownTowers
    end
    local out = {}
    for ____, t in ipairs(bot:GetNearbyTowers(____exports.SETTINGS.TowerRadius, false)) do
        do
            local __continue39
            repeat
                local at = t:GetLocation()
                if at == nil or at == nil then
                    __continue39 = true
                    break
                end
                out[#out + 1] = {
                    x = at.x,
                    y = at.y,
                    reach = t:GetAttackRange() + t:GetBoundingRadius()
                }
                __continue39 = true
            until true
            if not __continue39 then
                break
            end
        end
    end
    f.ownTowers = out
    return out
end
function creepsOf(f)
    if f.creeps ~= nil then
        return f.creeps
    end
    local out = {}
    for ____, c in ipairs(f.enemyCreeps) do
        do
            local __continue44
            repeat
                local at = c:GetLocation()
                if at == nil or at == nil then
                    __continue44 = true
                    break
                end
                local ____this_8
                ____this_8 = c
                local ____opt_7 = ____this_8.GetSecondsPerAttack
                local spa = ____opt_7 and ____opt_7(____this_8) or 1
                out[#out + 1] = {
                    x = at.x,
                    y = at.y,
                    reach = c:GetAcquisitionRange() + c:GetBoundingRadius() + f.hull,
                    dps = c:GetAttackDamage() / math.max(spa, 0.1)
                }
                __continue44 = true
            until true
            if not __continue44 then
                break
            end
        end
    end
    f.creeps = out
    return out
end
function enemiesOf(f)
    if f.enemies ~= nil then
        return f.enemies
    end
    local out = {}
    local hs = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue49
            repeat
                if not e:IsAlive() or e:IsIllusion() or not e:CanBeSeen() then
                    __continue49 = true
                    break
                end
                local at = e:GetLocation()
                if at == nil or at == nil then
                    __continue49 = true
                    break
                end
                local ____at_x_11 = at.x
                local ____at_y_12 = at.y
                local ____temp_13 = e:GetPlayerID()
                local ____temp_14 = e:GetAttackRange()
                local ____temp_15 = e:GetBoundingRadius()
                local ____temp_16 = e:GetAttackDamage()
                local ____this_10
                ____this_10 = e
                local ____opt_9 = ____this_10.GetSecondsPerAttack
                out[#out + 1] = {
                    x = ____at_x_11,
                    y = ____at_y_12,
                    pid = ____temp_13,
                    range = ____temp_14,
                    hull = ____temp_15,
                    dmg = ____temp_16,
                    spa = ____opt_9 and ____opt_9(____this_10) or 1,
                    speed = e:GetCurrentMovementSpeed()
                }
                hs[#hs + 1] = (tostring(e:GetPlayerID()) .. ":") .. tostring(heightAt(at.x, at.y) or "-")
                __continue49 = true
            until true
            if not __continue49 then
                break
            end
        end
    end
    f.enemies = out
    f.enemyHeights = hs
    return out
end
function race(bot, creep)
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
function snapshot(bot, f, t, slack, others)
    local creep = t.creep
    local at = creep:GetLocation()
    local spot = Offer.StandSpot(
        f.hero,
        at,
        ____exports.Reach(bot, creep)
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
    local erc = 0
    local ert
    local md = bot:GetAttackDamage()
    local hull = creep:GetBoundingRadius()
    for ____, e in ipairs(enemiesOf(f)) do
        do
            local __continue60
            repeat
                local gap = dist(e, at) - (e.range + e.hull + hull)
                local reach = math.max(0, gap) / math.max(100, e.speed or 300)
                if e.dmg >= md and reach <= t.due then
                    erc = erc + 1
                    if ert == nil or reach < ert then
                        ert = reach
                    end
                end
                if gap > 0 then
                    __continue60 = true
                    break
                end
                ein = ein + 1
                if e.dmg > ed then
                    ed = e.dmg
                end
                __continue60 = true
            until true
            if not __continue60 then
                break
            end
        end
    end
    local kb, kt = unpack(parts.race(bot, creep))
    local otw = false
    for ____, tw in ipairs(ownTowersOf(bot, f)) do
        if dist(tw, at) <= tw.reach + hull then
            otw = true
            break
        end
    end
    local hs = f.enemyHeights or ({})
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
        md = md,
        ed = ed,
        ein = ein,
        erc = erc,
        ert = ert,
        otw = otw,
        hh = heightAt(f.hero.x, f.hero.y),
        sh = heightAt(spot.x, spot.y),
        ch = heightAt(at.x, at.y),
        ra = bot:GetAttackRange(),
        enh = #hs > 0 and table.concat(hs, ";") or nil
    }
end
function partsOf()
    if parts ~= nil then
        return parts
    end
    parts = {
        targets = Telemetry.PerfStep(
            "CO:targets",
            function(bot) return Tasks.Verbs().laneTargets(
                bot,
                {
                    radius = LaneHits.READER_RADIUS,
                    within = ____exports.Within(bot)
                }
            ) end
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
function candidate(bot, f, targets, t, creep, cid, o, a, now)
    local fresh
    return {
        t = t,
        creep = creep,
        cid = cid,
        ck = o.ck,
        arrive = a,
        facts = function()
            if fresh == nil then
                local others = {}
                for ____, x in ipairs(targets) do
                    if x ~= t and x.walk <= 0 then
                        others[#others + 1] = {due = x.due, ranged = x.ranged}
                    end
                end
                fresh = partsOf().snapshot(
                    bot,
                    f,
                    t,
                    a.slack,
                    others
                )
            end
            return fresh
        end,
        note = function(go, why, aid)
            if o.go == true then
                return
            end
            if go then
                o.go = true
                o.aid = aid
                o.gat = now - o.first
                o.gw = t.walk
                o.why = nil
            else
                if o.why == nil or o.why == "early" then
                    o.why = why
                end
                o.last = why
            end
        end
    }
end
____exports.SETTINGS = {Every = 0.2, SlackStep = 0.1, SlackCap = 99, TowerRadius = 2500}
local rowHook
--- Whether the row wants the read for this hero with telemetry off (the read itself writes lines only with telemetry on).
local rowWants
--- index.ts: the row's decision, asked at every read with the hero's candidates, and how far ahead it wants creeps offered.
function ____exports.SetRow(hook, wants, lead)
    rowHook = hook
    rowWants = wants
    rowLead = lead
end
--- pid -> the read interval the hero last read in.
local readAt = {}
--- pid -> creep id -> its opportunity.
local opps = {}
function ____exports.ResetCache()
    for k in pairs(opps) do
        opps[k] = nil
    end
    for k in pairs(readAt) do
        readAt[k] = nil
    end
    parts = nil
end
--- Whether this hero's read is due: once per interval, the heroes' intervals offset by player id.
local function due(pid, now)
    local n = math.floor((now + pid % 2 * (____exports.SETTINGS.Every / 2)) / ____exports.SETTINGS.Every + 0.000001)
    if readAt[pid] == n then
        return false
    end
    readAt[pid] = n
    return true
end
local function r1(x)
    return math.floor(x * 10 + 0.5) / 10
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
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
    local ____Telemetry_Event_6 = Telemetry.Event
    local ____array_5 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "creep"}
    )
    local ____temp_2
    if o.go == true then
        ____temp_2 = o.aid
    else
        ____temp_2 = nil
    end
    __TS__SparseArrayPush(____array_5, {"aid", ____temp_2}, {"go", o.go == true and 1 or 0}, {"want", want and 1 or 0})
    local ____temp_3
    if o.go == true then
        ____temp_3 = nil
    else
        ____temp_3 = o.why or "off"
    end
    __TS__SparseArrayPush(____array_5, {"why", ____temp_3})
    local ____temp_4
    if o.go == true then
        ____temp_4 = nil
    else
        ____temp_4 = o.last
    end
    __TS__SparseArrayPush(
        ____array_5,
        {"lw", ____temp_4},
        {"src", (o.go == true or o.why ~= nil) and "own" or "shadow"},
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
        {"atk", o.atk and 1 or 0},
        {"erc", s.erc},
        {
            "ert",
            s.ert ~= nil and r2(s.ert) or nil
        },
        {"otw", s.otw and 1 or 0},
        {
            "gat",
            o.gat ~= nil and r1(o.gat) or nil
        },
        {
            "gw",
            o.gw ~= nil and r2(o.gw) or nil
        },
        {"hh", s.hh},
        {"sh", s.sh},
        {"ch", s.ch},
        {
            "ra",
            math.floor(s.ra)
        },
        {"enh", s.enh}
    )
    ____Telemetry_Event_6(
        "choice",
        {__TS__SparseArraySpread(____array_5)}
    )
end
local function hasOpen(pid)
    local m = opps[pid]
    if m == nil then
        return false
    end
    for ____ in pairs(m) do
        return true
    end
    return false
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
LANES = {Lane.Top, Lane.Mid, Lane.Bot}
--- One call per hero (the tick's ten a second): opens, updates and closes the hero's opportunities. Reads and logs; nothing is
-- ordered.
function ____exports.Shadow(bot)
    if not Telemetry.IsEnabled() and (rowWants == nil or not rowWants(bot)) then
        return
    end
    local pid = bot:GetPlayerID()
    if not due(
        pid,
        DotaTime()
    ) or not ____exports.MayOffer(bot) then
        return
    end
    if not bot:IsAlive() or Drill.Held(bot) or not LaneConfig.InLaningPhase() then
        closeAll(bot, pid)
        if rowHook ~= nil then
            rowHook(bot, {})
        end
        return
    end
    if Tasks.Verbs() == nil then
        return
    end
    local P = partsOf()
    local now = DotaTime()
    local targets = P.targets(bot)
    if #targets == 0 and not hasOpen(pid) then
        return
    end
    local ____P_lists_result_17 = P.lists(bot)
    local listed = ____P_lists_result_17.listed
    local theirs = ____P_lists_result_17.theirs
    local m = opps[pid]
    if m ~= nil then
        for cid, o in pairs(m) do
            do
                local __continue85
                repeat
                    if listed[o.creep] == true then
                        __continue85 = true
                        break
                    end
                    line(bot, o)
                    m[cid] = nil
                    __continue85 = true
                until true
                if not __continue85 then
                    break
                end
            end
        end
    end
    if #targets == 0 then
        if rowHook ~= nil then
            rowHook(bot, {})
        end
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
        enemyCreeps = theirs
    }
    local atkTarget = bot:GetAttackTarget()
    local slot = math.floor(now * 10) / 10
    local cands = {}
    for ____, t in ipairs(targets) do
        do
            local __continue90
            repeat
                local creep = t.creep
                local here = creep:GetLocation()
                if here == nil or here == nil then
                    __continue90 = true
                    break
                end
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
                if rowHook ~= nil then
                    cands[#cands + 1] = candidate(
                        bot,
                        f,
                        targets,
                        t,
                        creep,
                        cid,
                        o,
                        a,
                        now
                    )
                end
                __continue90 = true
            until true
            if not __continue90 then
                break
            end
        end
    end
    if rowHook ~= nil then
        rowHook(bot, cands)
    end
end
return ____exports
