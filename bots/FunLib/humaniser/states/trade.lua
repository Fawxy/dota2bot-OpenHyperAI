--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end

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
local arrive, noneReason, distXY, frac, valid, awaySpeed, rawDps, hunterOf, huntersOf, safeTime, predictedPlace, towerCovers, runOf, shareOn, playFor, roleOf, chaseLost, chaseEnd, unanswered, noteSight, stepOutPoint, BARS, CAND_RADIUS, AGGRO_CLEAR, AT_PLACE, heads, lastSeen, lastHandles, runs, TOWER_IDS, sayRatio, NO_EVERY, episodes, lastNo, kindOf, chases
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local SupportDeny = require(GetScriptDirectory().."/FunLib/humaniser/states/support_deny")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Deaggro = require(GetScriptDirectory().."/FunLib/humaniser/deaggro")
local CreepAggro = require(GetScriptDirectory().."/FunLib/humaniser/creep_aggro")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local PairJoin = require(GetScriptDirectory().."/FunLib/humaniser/pair_join")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
function arrive(d, r, close)
    if d <= r then
        return 0
    end
    return close > 0 and (d - r) / close or math.huge
end
--- Each hunter's attacks from the moment it is in attack range to the end of `w`, and each ready spell it reaches in time, against the target's HP.
function ____exports.CatchRead(hunters, thpAbs, w)
    if w == nil then
        w = BARS.catchWindow
    end
    local dmg = 0
    local first = math.huge
    for ____, h in ipairs(hunters) do
        local ta = arrive(h.d, h.reach, h.close)
        if ta < w then
            dmg = dmg + h.dps * (w - ta)
            first = math.min(first, ta)
        end
        for ____, s in ipairs(h.spells) do
            do
                local __continue8
                repeat
                    local ts = arrive(h.d, s.range, h.close) + s.cp
                    if ts > w then
                        __continue8 = true
                        break
                    end
                    dmg = dmg + s.dmg
                    first = math.min(first, ts)
                    __continue8 = true
                until true
                if not __continue8 then
                    break
                end
            end
        end
    end
    return {ok = dmg >= thpAbs, dmg = dmg, first = first, safe = w}
end
function noneReason(rest, ended)
    if ended ~= nil then
        return ended
    end
    local near
    for ____, r in ipairs(rest) do
        if near == nil or r.c.d < near.c.d then
            near = r
        end
    end
    return near == nil and "no_target" or near.p.reason
end
function distXY(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function frac(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
end
function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen() and not u:IsIllusion()
end
function awaySpeed(u, place, vx, vy, pid, seen, unseenKnown)
    local me = u:GetLocation()
    local dx = place.x - me.x
    local dy = place.y - me.y
    local n = math.sqrt(dx * dx + dy * dy)
    if n < 1 then
        return 0
    end
    if not seen and not unseenKnown then
        return Threat.SeenSpeed(pid) or Threat.SETTINGS.MissingSpeed
    end
    return (vx * dx + vy * dy) / n
end
function rawDps(u)
    local ____this_19
    ____this_19 = u
    local ____opt_18 = ____this_19.GetSecondsPerAttack
    local spa = ____opt_18 and ____opt_18(____this_19)
    return spa ~= nil and spa > 0 and u:GetAttackDamage() / spa or 0
end
function hunterOf(u, place, ls, pid, seen, known)
    local spells = {}
    for ____, sp in ipairs(SpellReady.ReadySpells(u)) do
        local f = sp.dtype == DamageType.Pure and 1 or (sp.dtype == DamageType.Physical and ls.physF or ls.magF)
        spells[#spells + 1] = {range = sp.range, cp = sp.cp, dmg = sp.dmg * f}
    end
    return {
        d = distXY(
            u:GetLocation(),
            place
        ),
        reach = u:GetAttackRange() + u:GetBoundingRadius() + ls.hull,
        close = u:GetCurrentMovementSpeed() - awaySpeed(
            u,
            place,
            ls.vx,
            ls.vy,
            pid,
            seen,
            known
        ),
        dps = rawDps(u) * ls.physF,
        spells = spells
    }
end
function huntersOf(bot, place, ls, pid, seen, known)
    local out = {hunterOf(
        bot,
        place,
        ls,
        pid,
        seen,
        known
    )}
    local me = bot:GetPlayerID()
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue155
            repeat
                if a == nil or a == nil or a:IsNull() or not a:IsAlive() or a:IsIllusion() or a:GetPlayerID() == me then
                    __continue155 = true
                    break
                end
                local ____opt_24 = runs[a:GetPlayerID()]
                if (____opt_24 and ____opt_24.target) ~= pid then
                    __continue155 = true
                    break
                end
                out[#out + 1] = hunterOf(
                    a,
                    place,
                    ls,
                    pid,
                    seen,
                    known
                )
                __continue155 = true
            until true
            if not __continue155 then
                break
            end
        end
    end
    return out
end
function safeTime(bot, place, ls, pid, seen, known)
    local theirs = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
    local best
    local bestD = math.huge
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue160
            repeat
                local t = GetTower(theirs, id)
                if t == nil or t == nil or not t:IsAlive() then
                    __continue160 = true
                    break
                end
                local d = distXY(
                    t:GetLocation(),
                    place
                )
                if d < bestD then
                    bestD = d
                    best = t:GetLocation()
                end
                __continue160 = true
            until true
            if not __continue160 then
                break
            end
        end
    end
    if best == nil then
        return BARS.catchWindow
    end
    local left = bestD - LaneConfig.TowerReach()
    if left <= 0 then
        return 0
    end
    local v
    if not seen and not known then
        v = Threat.SeenSpeed(pid) or Threat.SETTINGS.MissingSpeed
    else
        v = (ls.vx * (best.x - place.x) + ls.vy * (best.y - place.y)) / math.max(1, bestD)
    end
    return v > 0 and math.min(BARS.catchWindow, left / v) or BARS.catchWindow
end
function predictedPlace(pid, ls)
    local info = GetHeroLastSeenInfo(pid)[1]
    if info == nil then
        return nil
    end
    local l = info.location
    local vx = ls and ls.vx or 0
    local vy = ls and ls.vy or 0
    local v = math.sqrt(vx * vx + vy * vy)
    local cap = Threat.SeenSpeed(pid) or Threat.SETTINGS.MissingSpeed
    local f = v > cap and v > 0 and cap / v or 1
    return Vector(l.x + vx * f * info.time_since_seen, l.y + vy * f * info.time_since_seen, l.z)
end
function towerCovers(bot, a, b)
    local reach = LaneConfig.TowerReach()
    for ____, t in ipairs(bot:GetNearbyTowers(1600, true)) do
        do
            local __continue171
            repeat
                if not t:IsAlive() then
                    __continue171 = true
                    break
                end
                local tl = t:GetLocation()
                if distXY(tl, a) <= reach or distXY(tl, b) <= reach then
                    return true
                end
                __continue171 = true
            until true
            if not __continue171 then
                break
            end
        end
    end
    return false
end
function runOf(bot, rs, seen, here)
    local run = __TS__ObjectAssign(
        {},
        rs,
        {alive = IsHeroAlive(rs.target)}
    )
    if seen or not run.alive or rs.level ~= "kill" then
        return run
    end
    local ls = lastSeen[rs.target]
    local place = predictedPlace(rs.target, ls)
    if place == nil then
        run.unseen = {at = true, tower = false, threat = false}
        return run
    end
    run.chaseAt = {x = place.x, y = place.y}
    local hull = ls and ls.hull or 0
    local known = ls ~= nil
    local lsr = ls or ({
        vx = 0,
        vy = 0,
        physF = 1,
        magF = 1,
        hull = 0,
        thpAbs = 0
    })
    local creepOn = Ours.On("TradeSwing") and Ours.On("CreepRead") and Ours.On("TowerRead")
    local walk = SafeGather.At(bot, place, {
        horizon = SafeGather.WalkHorizon,
        away = true,
        held = false,
        hold = true,
        draws = creepOn,
        exclude = rs.target
    })
    run.unseen = {
        at = distXY(here, place) <= bot:GetBoundingRadius() + hull + AT_PLACE,
        tower = not creepOn and towerCovers(bot, here, place),
        threat = walk.level == "deadly"
    }
    run.catch = ____exports.CatchRead(
        huntersOf(
            bot,
            place,
            lsr,
            rs.target,
            false,
            known
        ),
        lsr.thpAbs,
        safeTime(
            bot,
            place,
            lsr,
            rs.target,
            false,
            known
        )
    )
    return run
end
function shareOn(from, on)
    return SpellReady.DamageOn(from, on, PairJoin.SETTINGS.Window) / math.max(
        1,
        on:GetHealth()
    )
end
function playFor(bot, here)
    local mine = Plays.Of(bot)
    local function pick(p)
        local t = p.target
        if not valid(t) then
            return nil
        end
        local at = t:GetLocation()
        local walk = SafeGather.At(bot, at, {
            horizon = SafeGather.WalkHorizon,
            away = true,
            held = false,
            hold = true,
            who = "play"
        })
        local inputs = Plays.InputsOf({kind = p.kind, by = bot, target = t, at = at})
        inputs.walk = {level = walk.level, reason = walk.reason}
        return {
            id = p.id,
            kind = p.kind,
            tgt = p.tgt,
            zero = Plays.Weigh(inputs).zero
        }
    end
    if mine ~= nil then
        local ____temp_45
        if mine.by == bot and mine.kind ~= ____exports.LANE_FIGHT then
            ____temp_45 = nil
        else
            ____temp_45 = pick(mine)
        end
        return ____temp_45
    end
    for ____, p in ipairs(Plays.Near(here, CAND_RADIUS)) do
        do
            local __continue237
            repeat
                if p.by == bot then
                    __continue237 = true
                    break
                end
                local r = pick(p)
                if r ~= nil then
                    return r
                end
                __continue237 = true
            until true
            if not __continue237 then
                break
            end
        end
    end
    return nil
end
--- Why a lane fight on this candidate is off the table, whoever starts it: their tower, the walk's answer (`kill`, `unknown`), a big wave.
function ____exports.FightZero(i, c)
    local cr = i.creepRead == true
    if not cr and (i.towerOnMe or c.tw) then
        return "tower"
    end
    local say = c.walk or i.safe.hold
    if say.level == "deadly" then
        return say.reason
    end
    if not cr and i.wave > BARS.waveKill then
        return "wave"
    end
    return nil
end
function roleOf(bot)
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 4 and "support" or "core"
end
function chaseLost(bot, ep, now)
    local pid = bot:GetPlayerID()
    if chases[pid] ~= nil then
        chaseEnd(
            bot,
            chases[pid],
            now,
            "next",
            nil
        )
    end
    chases[pid] = {level = ep.level, tpid = ep.tpid, at = now}
    local info = GetHeroLastSeenInfo(ep.tpid)[1]
    local me = bot:GetLocation()
    local d = info ~= nil and distXY(me, info.location) or nil
    local reach = bot:GetAttackRange() + bot:GetBoundingRadius() + ep.thull
    local ____opt_74 = heads[ep.tpid]
    local a = ____opt_74 and ____opt_74.s0
    local ____opt_76 = heads[ep.tpid]
    local b = ____opt_76 and ____opt_76.s1
    local span = a ~= nil and b ~= nil and b.at - a.at or 0
    local hv = span > 0 and distXY(
        Vector(a.x, a.y, 0),
        Vector(b.x, b.y, 0)
    ) / span or nil
    local hd = span > 0 and math.floor(math.deg(math.atan2(b.y - a.y, b.x - a.x)) + 0.5) or nil
    Telemetry.Event(
        "chase",
        {
            {"pid", pid},
            {"ph", "lost"},
            {
                "role",
                roleOf(bot)
            },
            {
                "ek",
                kindOf(ep.level)
            },
            {"tgt", ep.tpid},
            {
                "dur",
                ep.startedAt ~= nil and math.floor((now - ep.startedAt) * 10) / 10 or nil
            },
            {
                "hp",
                math.floor(frac(bot) * 100) / 100
            },
            {
                "thp",
                math.floor(ep.thpSeen / math.max(1, ep.tmax) * 100) / 100
            },
            {"kh", BARS.commitHp},
            {
                "x",
                math.floor(me.x)
            },
            {
                "y",
                math.floor(me.y)
            },
            {
                "lx",
                info ~= nil and math.floor(info.location.x) or nil
            },
            {
                "ly",
                info ~= nil and math.floor(info.location.y) or nil
            },
            {
                "tss",
                info ~= nil and math.floor(info.time_since_seen * 10 + 0.5) / 10 or nil
            },
            {
                "d",
                d ~= nil and math.floor(d) or nil
            },
            {
                "gap",
                d ~= nil and math.floor(d - reach) or nil
            },
            {
                "ms",
                math.floor(bot:GetCurrentMovementSpeed())
            },
            {
                "tms",
                math.floor(Threat.SeenSpeed(ep.tpid) or -1)
            },
            {
                "hv",
                hv ~= nil and math.floor(hv) or nil
            },
            {"hd", hd},
            {
                "sp",
                SpellReady.ReadyDamage(bot)
            }
        }
    )
end
function chaseEnd(bot, c, now, ph, seen)
    local pid = bot:GetPlayerID()
    chases[pid] = nil
    local ep = episodes[pid]
    Telemetry.Event(
        "chase",
        {
            {"pid", pid},
            {"ph", ph},
            {
                "ek",
                kindOf(c.level)
            },
            {"tgt", c.tpid},
            {
                "dt",
                math.floor((now - c.at) * 10) / 10
            },
            {
                "alive",
                bot:IsAlive() and 1 or 0
            },
            {
                "d",
                seen ~= nil and bot:IsAlive() and math.floor(GetUnitToUnitDistance(bot, seen)) or nil
            },
            {
                "thp",
                seen ~= nil and math.floor(frac(seen) * 100) / 100 or nil
            },
            {
                "hp",
                bot:IsAlive() and math.floor(frac(bot) * 100) / 100 or nil
            },
            {
                "mode",
                bot:GetActiveMode()
            },
            {
                "onk",
                ep ~= nil and ep.tpid == c.tpid and kindOf(ep.level) or nil
            }
        }
    )
end
function unanswered(bot, now, why, i)
    local pid = bot:GetPlayerID()
    local last = lastNo[pid]
    if not Telemetry.IsEnabled() or last ~= nil and now - last < NO_EVERY then
        return
    end
    local hitter
    for ____, c in ipairs(i.cands) do
        if c.hitting and (hitter == nil or c.d < hitter.d) then
            hitter = c
        end
    end
    if hitter == nil then
        return
    end
    lastNo[pid] = now
    local h = lastHandles[hitter.pid]
    Telemetry.Event(
        "trade_no",
        {
            {"pid", pid},
            {
                "role",
                roleOf(bot)
            },
            {"why", why},
            {"tgt", hitter.pid},
            {
                "d",
                math.floor(hitter.d)
            },
            {
                "reach",
                math.floor(hitter.d - hitter.gap)
            },
            {
                "har",
                h ~= nil and math.floor(h:GetAttackRange()) or nil
            },
            {"agg", hitter.paid and 1 or 0},
            {
                "hp",
                math.floor(i.hp * 100) / 100
            },
            {
                "thp",
                math.floor(hitter.thp * 100) / 100
            },
            {"en", i.n},
            {"cr", i.wave},
            {"hc", i.creepsOnMe},
            {
                "mode",
                bot:GetActiveMode()
            },
            {
                "md",
                math.floor(bot:GetActiveModeDesire() * 100) / 100
            }
        }
    )
end
function noteSight(bot, ep, now)
    local t = lastHandles[ep.tpid]
    if t ~= nil then
        ep.target = t
        ep.thpSeen = t:GetHealth()
        ep.unseenSince = nil
    elseif ep.level == "kill" and ep.startedAt ~= nil and ep.unseenSince == nil and IsHeroAlive(ep.tpid) then
        ep.unseenSince = now
        if Telemetry.IsEnabled() then
            chaseLost(bot, ep, now)
        end
    end
end
function stepOutPoint(bot, creeps)
    local me = bot:GetLocation()
    local x = 0
    local y = 0
    local seen = 0
    for ____, c in ipairs(creeps) do
        do
            local __continue371
            repeat
                local l = c:GetLocation()
                if l == nil then
                    __continue371 = true
                    break
                end
                x = x + l.x
                y = y + l.y
                seen = seen + 1
                __continue371 = true
            until true
            if not __continue371 then
                break
            end
        end
    end
    x = seen > 0 and x / seen or me.x
    y = seen > 0 and y / seen or me.y
    local dx = me.x - x
    local dy = me.y - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        local back = GetLocationAlongLane(
            bot:GetAssignedLane(),
            math.max(
                0,
                GetAmountAlongLane(
                    bot:GetAssignedLane(),
                    me
                ).amount - 0.05
            )
        )
        dx = back.x - me.x
        dy = back.y - me.y
    end
    local n = math.max(
        1,
        math.sqrt(dx * dx + dy * dy)
    )
    return Vector(x + dx / n * (AGGRO_CLEAR + 100), y + dy / n * (AGGRO_CLEAR + 100), me.z)
end
BARS = {
    commitHp = 0.4,
    waveHit = 3,
    waveKill = 5,
    creeps = 2,
    slackWave = 1,
    losing = 0.05,
    unlandedCap = 0.15,
    catchFails = 2,
    catchGap = 0.5,
    catchWindow = 30,
    walkHit = 0.5,
    slackWalk = 0.5,
    pairReach = 1200,
    playWalk = 600,
    outrange = 100,
    notTaken = 1,
    noClear = 2,
    chase = 30,
    holdCap = 3
}
local function sayOf(a)
    return {level = a.level, ratio = a.ratio, reason = a.reason}
end
--- Whether a hero at `gap` (distance past attack range plus both hulls, 0 or less in range) is in range within `horizon` s when the target moves `away` (signed; towards us is negative) and we run at `ms`.
function ____exports.Arrives(gap, ms, away, horizon)
    if gap <= 0 then
        return true
    end
    local closing = ms - away
    return closing > 0 and gap <= closing * horizon
end
--- Seconds until a hero at `gap` past attack range stands in it, the target's retreat counted and its approach not (as `Arrives`).
function ____exports.SwingIn(gap, ms, away)
    if gap <= 0 then
        return 0
    end
    return gap / math.max(
        1,
        ms - math.max(0, away)
    )
end
--- A hit with no answer coming back: the target swings at a lane creep, or our range is `outrange` or more over its.
function ____exports.Free(targetLastHitting, range, targetRange)
    return targetLastHitting or range >= targetRange + BARS.outrange
end
--- HP lost beyond what the target lost since the baseline, over our max HP (positive: losing). Absolute HP, so a big hero is not judged against a small one's fractions.
function ____exports.Deficit(hp0, hp, thp0, thp, maxHp)
    return (hp0 - hp - (thp0 - thp)) / math.max(1, maxHp)
end
local RANK = {
    none = 0,
    hit = 1,
    hitback = 2,
    kill = 3,
    join = 4
}
local function pairOn(i, c)
    return i.pair ~= nil and i.pair.tgt == c.pid and i.pair.ko > i.pair.kt
end
--- `c` is hitting us as a hit back reads it: a hit in the last second, or, for the running hit back's own target, one within its attack interval.
local function hitsUs(c, run)
    return c.hitting or c.swung and run ~= nil and run.level == "hitback" and run.target == c.pid
end
local function playOn(i, c)
    return i.play ~= nil and i.play.tgt == c.pid and i.play.zero == nil
end
--- A running kill's catch state this frame: failures so far, when the last was, and whether it has ended on them.
local function catchState(i, run, ok)
    if ok then
        return {fails = 0, ended = false}
    end
    if run.catchFails == 0 or run.catchFailAt == nil then
        return {fails = 1, at = i.now, ended = BARS.catchFails <= 1}
    end
    if i.now - run.catchFailAt >= BARS.catchGap then
        return {fails = run.catchFails + 1, at = i.now, ended = run.catchFails + 1 >= BARS.catchFails}
    end
    return {fails = run.catchFails, at = run.catchFailAt, ended = false}
end
--- The gates of one level on one candidate in the bars table's order: the first that fails, or undefined. `run` is set for the running exchange's own target (the slack).
local function gate(i, c, level, src, run)
    local cr = i.creepRead == true
    if not cr and (i.towerOnMe or c.tw) then
        return "tower"
    end
    local walks = level == "kill" or level == "join"
    local slack = run ~= nil
    local here = cr and not walks and c.say ~= nil and c.say or i.safe
    local say = walks and c.walk ~= nil and c.walk or (level == "hit" and here.hit or here.hold)
    if say.level == "deadly" then
        return say.reason
    end
    if not walks and c.lost == true then
        return "lost"
    end
    local wave = slack and BARS.slackWave or 0
    if level == "kill" then
        local cs = c.catch
        if cs == nil then
            return "catch"
        end
        if not cs.ok and not (run ~= nil and run.level == "kill" and not catchState(i, run, false).ended) then
            return "catch"
        end
        if not cr and i.wave > BARS.waveKill + wave then
            return "wave"
        end
        return nil
    end
    if level == "join" then
        local ____temp_0
        if src == "pair" then
            ____temp_0 = c.d > BARS.pairReach
        else
            ____temp_0 = c.gap > BARS.playWalk
        end
        if ____temp_0 then
            return "no_reach"
        end
        return nil
    end
    local sw = i.swing
    local reaches = ____exports.Arrives(
        c.gap,
        i.ms,
        math.max(0, c.away),
        BARS.walkHit + (slack and BARS.slackWalk or 0)
    )
    local held = i.hold == true and run ~= nil and not run.landed and (run.level == level or run.level == "hitback" and level == "hit")
    if sw == nil then
        if not held and not (c.free or c.ko > c.kt or level == "hitback" and c.paid) then
            return "unfavoured"
        end
    elseif not reaches then
        return "no_reach"
    elseif not held then
        local unfired = run ~= nil and not run.landed
        local ____slack_1
        if slack then
            ____slack_1 = sw.cover > 0
        else
            ____slack_1 = sw.cover > ____exports.SwingIn(c.gap, i.ms, c.away) + sw.atk
        end
        local covered = ____slack_1
        local draws = not unfired and not covered and (c.near or 0) > 0
        local theirs = c.kt + (draws and (c.kc or 0) or 0)
        local ours = c.ko + (cr and (c.oc or 0) or 0)
        if not (c.free and not draws or ours > theirs or level == "hitback" and c.paid) then
            return (c.free or ours > c.kt) and "aggro" or "unfavoured"
        end
    end
    if sw == nil and (run and run.stepFor) == nil and not reaches then
        return "no_reach"
    end
    if i.denyDue then
        return "deny"
    end
    if sw ~= nil and run == nil and sw.due ~= nil and sw.due < ____exports.SwingIn(c.gap, i.ms, c.away) + sw.atk then
        return "due"
    end
    if cr then
        return nil
    end
    if i.creepsOnMe >= BARS.creeps then
        return "creeps"
    end
    if i.wave > BARS.waveHit + wave then
        return "wave"
    end
    return nil
end
--- The level one candidate gets, trying the rules in order; or `none` with the first gate that failed.
local function pickFor(i, c, run)
    local first
    local function fail(why)
        if why == nil then
            return false
        end
        first = first or why
        return true
    end
    local killable = c.thp <= BARS.commitHp or run ~= nil and run.level == "kill"
    if playOn(i, c) and not fail(gate(
        i,
        c,
        "join",
        "play",
        run
    )) then
        return {level = "join", source = "play", reason = "play", rank = 5}
    end
    local pair = pairOn(i, c)
    if pair then
        if killable and not fail(gate(
            i,
            c,
            "kill",
            "pair",
            run
        )) then
            return {level = "kill", source = "pair", reason = "pair", rank = 4}
        end
        if not fail(gate(
            i,
            c,
            "join",
            "pair",
            run
        )) then
            return {level = "join", source = "pair", reason = "pair", rank = 4}
        end
    elseif killable and not fail(gate(
        i,
        c,
        "kill",
        nil,
        run
    )) then
        return {level = "kill", reason = "kill", rank = 3}
    end
    if hitsUs(c, run) and not fail(gate(
        i,
        c,
        "hitback",
        nil,
        run
    )) then
        return {level = "hitback", reason = "hitback", rank = 2}
    end
    if not fail(gate(
        i,
        c,
        "hit",
        nil,
        run
    )) then
        return {level = "hit", reason = "hit", rank = 1}
    end
    return {level = "none", reason = first or "none", rank = 0}
end
--- `a` is the better target of two candidates at the same rank: kill on the lowest HP, hit back on the nearest, hit on a free one then the smallest gap, a join on the nearest.
local function before(a, b)
    if a.p.rank ~= b.p.rank then
        return a.p.rank > b.p.rank
    end
    if a.p.level == "kill" then
        return a.c.thp < b.c.thp
    end
    if a.p.level == "hit" then
        if a.c.free ~= b.c.free then
            return a.c.free
        end
        return a.c.gap < b.c.gap
    end
    return a.c.d < b.c.d
end
local function howOf(level, run, seen)
    if level == "none" then
        return nil
    end
    if level == "hit" or level == "hitback" then
        return {verb = "attack", aggro = "free"}
    end
    if not seen and run ~= nil and run.chaseAt ~= nil then
        return {verb = "move", aggro = "commit", at = run.chaseAt}
    end
    return {verb = "attack", aggro = "commit"}
end
--- Ends that exclude the target from this frame's fresh choice: the exchange did not fail a gate, it stopped.
local STOPS = {
    target_dead = true,
    target_lost = true,
    not_taken = true,
    no_clear = true,
    backstop = true,
    losing = true,
    cannot_catch = true,
    spot_clear = true,
    utower = true,
    threat = true
}
--- What ends the running exchange besides a gate of its own level, or undefined.
local function endOf(i, run, t)
    if not run.alive then
        return "target_dead"
    end
    if run.started == nil and run.offered > BARS.notTaken then
        return "not_taken"
    end
    if run.stepFor ~= nil and run.stepFor > BARS.noClear then
        return "no_clear"
    end
    if run.level == "kill" and run.started ~= nil and run.started > BARS.chase then
        return "backstop"
    end
    local hits = run.level == "hit" or run.level == "hitback"
    if i.hold == true and hits and not run.landed and run.started ~= nil and run.started > BARS.holdCap then
        return "backstop"
    end
    if t == nil then
        if run.level ~= "kill" then
            return "target_lost"
        end
        local u = run.unseen
        if u ~= nil then
            if u.at then
                return "spot_clear"
            end
            if u.tower then
                return "utower"
            end
            if u.threat then
                return "threat"
            end
        end
        if run.catch ~= nil and catchState(i, run, run.catch.ok).ended then
            return "cannot_catch"
        end
        return nil
    end
    if hits then
        if run.soFar > (run.landed and BARS.losing or BARS.unlandedCap) then
            return "losing"
        end
    end
    if run.level == "join" then
        if run.source == "pair" and not pairOn(i, t) then
            return "pair_end"
        end
        if run.source == "play" and not playOn(i, t) then
            return "play_end"
        end
    end
    if run.level == "kill" and t.catch ~= nil and catchState(i, run, t.catch.ok).ended then
        return "cannot_catch"
    end
    return nil
end
local function answerOf(i, pid, c, p, run, ended, reason)
    local a = {
        level = p.level,
        target = pid,
        source = p.source,
        how = howOf(p.level, run, c ~= nil),
        reason = reason or p.reason,
        ended = ended
    }
    if p.level == "kill" and run ~= nil and run.level == "kill" and run.target == pid then
        local ____catchState_14 = catchState
        local ____i_12 = i
        local ____run_13 = run
        local ____opt_4 = c and c.catch
        local ____temp_10 = ____opt_4 and ____opt_4.ok
        if ____temp_10 == nil then
            local ____opt_8 = run.catch
            ____temp_10 = ____opt_8 and ____opt_8.ok
        end
        local ____temp_10_11 = ____temp_10
        if ____temp_10_11 == nil then
            ____temp_10_11 = true
        end
        local cs = ____catchState_14(____i_12, ____run_13, ____temp_10_11)
        a.catchFails = cs.fails
        a.catchFailAt = cs.at
    end
    return a
end
--- The frame's answer: the level and target, how, and why, over `i`.
function ____exports.Decide(i)
    local run = i.run
    local ended
    local exclude
    local kept
    if run ~= nil then
        local t = __TS__ArrayFind(
            i.cands,
            function(____, c) return c.pid == run.target end
        )
        ended = endOf(i, run, t)
        if ended == nil and t == nil then
            local p = {level = "kill", reason = "chase", rank = 3}
            kept = {c = nil, p = p}
        elseif ended == nil then
            local own = gate(
                i,
                t,
                run.level,
                run.source,
                run
            )
            local p = pickFor(i, t, run)
            if own ~= nil then
                ended = own
            elseif p.level == "none" then
                ended = p.reason
            else
                kept = {c = t, p = p}
            end
        end
        if ended ~= nil and STOPS[ended] == true then
            exclude = run.target
        end
    end
    local rest = {}
    for ____, c in ipairs(i.cands) do
        do
            local __continue95
            repeat
                if kept ~= nil and kept.c == c then
                    __continue95 = true
                    break
                end
                if c.pid == exclude then
                    __continue95 = true
                    break
                end
                rest[#rest + 1] = {
                    c = c,
                    p = pickFor(i, c, nil)
                }
                __continue95 = true
            until true
            if not __continue95 then
                break
            end
        end
    end
    local best
    for ____, r in ipairs(rest) do
        if r.p.level ~= "none" and (best == nil or before(r, best)) then
            best = r
        end
    end
    if kept ~= nil then
        if best == nil or best.p.rank <= kept.p.rank then
            local upReason = kept.c ~= nil and RANK[kept.p.level] > RANK[run.level] and (kept.p.level == "kill" and "kill_up" or "level_up") or nil
            return answerOf(
                i,
                run.target,
                kept.c,
                kept.p,
                run,
                nil,
                upReason
            )
        end
        return answerOf(
            i,
            best.c.pid,
            best.c,
            best.p,
            nil,
            "higher"
        )
    end
    if best ~= nil then
        return answerOf(
            i,
            best.c.pid,
            best.c,
            best.p,
            nil,
            ended
        )
    end
    return {
        level = "none",
        reason = noneReason(rest, ended),
        ended = ended
    }
end
--- Slice trade-count (design step4-exchanges 4.1): where each end reason can come from. `gate`: a gate of some level gives it, so it can
-- already hold when the exchange opens; `think`: the executor's own read (`no_clear`: a creep within the aggro radius of the hero at
-- the first act); `later`: a change in the game after the open, which no start gate asks. A reason not listed (`mode_*`) is `later`.
____exports.ENDS = {
    tower = "gate",
    kill = "gate",
    unknown = "gate",
    lost = "gate",
    catch = "gate",
    wave = "gate",
    no_reach = "gate",
    unfavoured = "gate",
    deny = "gate",
    creeps = "gate",
    aggro = "gate",
    due = "gate",
    no_clear = "think",
    target_dead = "later",
    target_lost = "later",
    not_taken = "later",
    backstop = "later",
    losing = "later",
    cannot_catch = "later",
    spot_clear = "later",
    utower = "later",
    threat = "later",
    pair_end = "later",
    play_end = "later",
    higher = "later",
    switch = "later",
    lane_end = "later",
    dead = "later",
    play = "later"
}
--- The reasons a fresh read gives each level on `c` (no running exchange): what could end the exchange the moment after it opens.
function ____exports.OpenFails(i, c)
    local out = {}
    local function add(why)
        if why ~= nil and __TS__ArrayIndexOf(out, why) < 0 then
            out[#out + 1] = why
        end
    end
    local killable = c.thp <= BARS.commitHp
    if playOn(i, c) then
        add(gate(
            i,
            c,
            "join",
            "play",
            nil
        ))
    end
    if pairOn(i, c) then
        if killable then
            add(gate(
                i,
                c,
                "kill",
                "pair",
                nil
            ))
        end
        add(gate(
            i,
            c,
            "join",
            "pair",
            nil
        ))
    elseif killable then
        add(gate(
            i,
            c,
            "kill",
            nil,
            nil
        ))
    end
    if hitsUs(c, nil) then
        add(gate(
            i,
            c,
            "hitback",
            nil,
            nil
        ))
    end
    add(gate(
        i,
        c,
        "hit",
        nil,
        nil
    ))
    return out
end
--- 1 when the end `why` already held at the open (`opens`: `OpenFails` there; `first`: the episode's first act), 0 when it came later, undefined when it can only come later.
function ____exports.TrueAtOpen(why, opens, first)
    local kind = ____exports.ENDS[why]
    if kind == "gate" then
        return __TS__ArrayIndexOf(opens, why) >= 0 and 1 or 0
    end
    if kind == "think" then
        return first == "step" and 1 or 0
    end
    return nil
end
--- What holds retreat (design section 1, "Hold"), over the inputs (`Holds` reads them for a hero): `hitback` while some hitter passes tower and the held here answer (hold) is not `deadly` and is either paid or
-- free or favoured, whatever the swing is doing (a due deny, creeps and the wave change the swing, not the hold); `join`
-- while some candidate is a pair join. Undefined: retreat decides alone.
function ____exports.HoldsOf(i)
    local run = i.run
    for ____, c in ipairs(i.cands) do
        do
            local __continue122
            repeat
                if not hitsUs(c, run) or c.lost == true or i.creepRead ~= true and (i.towerOnMe or c.tw) then
                    __continue122 = true
                    break
                end
                if i.safe.hold.level == "deadly" then
                    __continue122 = true
                    break
                end
                if c.paid or c.free or c.ko > c.kt then
                    return "hitback"
                end
                __continue122 = true
            until true
            if not __continue122 then
                break
            end
        end
    end
    for ____, c in ipairs(i.cands) do
        local slack = run ~= nil and run.target == c.pid and run or nil
        if pairOn(i, c) and gate(
            i,
            c,
            "join",
            "pair",
            slack
        ) == nil then
            return "join"
        end
    end
    return nil
end
CAND_RADIUS = 1600
--- Enemy lane creeps within this of us count as the wave and turn on a hero attacker (EC-053: lane creeps acquire a hero attacker within about 500).
local CREEP_RADIUS = 500
AGGRO_CLEAR = 550
local AGGRO_COOLDOWN = 3
local COOLDOWN_LEFT = 0.3
--- When this bot last gave an attack order on an enemy hero (its aggro cooldown runs from there).
local primedAt = {}
--- A lane creep's seconds per attack when its handle does not say (base attack time 1.0, Liquipedia Lane_Creeps).
local CREEP_SPA = 1
--- With `Ours.TradeSwing` the one creep scan reaches the aggro radius round any swing place a hit can open on: a walk of `walkHit + slackWalk` at a fast hero's speed (`judgement`: 450).
local SWING_SCAN = 1000
--- A hero hit us "recently" within this (s): Threat.SETTINGS.EngagedRecent's value.
local HIT_RECENT = 1
--- Past the hitter's seconds per attack before `swung` lapses: a projectile's flight and the frame step vary the gap between two landings (`judgement`).
local SWING_SLACK = 0.25
--- The window `swung` is read over for a hitter: its seconds per attack plus the slack (`swung` includes `hitting`, so a fast hitter needs no floor).
local function SwingWindow(spa)
    if spa == nil or spa <= 0 then
        return HIT_RECENT
    end
    return spa + SWING_SLACK
end
--- Seconds between the two places a target's velocity is read from, and the age past which a sample is no velocity (a target seen again after a gap). `judgement`.
local HEADING_SPAN = 0.5
local HEADING_STALE = 1.5
AT_PLACE = 100
heads = {}
local function noteSeen(pid, l, now)
    local ____temp_15 = heads[pid] or ({})
    heads[pid] = ____temp_15
    local h = ____temp_15
    if h.s1 ~= nil and now - h.s1.at < HEADING_SPAN then
        return
    end
    h.s0 = h.s1
    h.s1 = {x = l.x, y = l.y, at = now}
end
--- The hero's velocity (units/s) from its movement since the sample before last; 0 when unknown.
local function velocityOf(pid, l, now)
    local ____opt_16 = heads[pid]
    local s0 = ____opt_16 and ____opt_16.s0
    if s0 == nil or now - s0.at > HEADING_STALE then
        return 0, 0
    end
    local dt = math.max(0.01, now - s0.at)
    return (l.x - s0.x) / dt, (l.y - s0.y) / dt
end
lastSeen = {}
lastHandles = {}
--- The last pair answer that was a join (per bot) and when, for the Keep window.
local lastPair = {}
--- Heroes we lost an exchange with, per bot: set when one ends `losing`, cleared once neither has damaged the other for StayEngaged.
local lostWith = {}
--- Whether `h` is one we lost an exchange with and not yet quiet (clears the memory when it is).
local function lostFor(bot, h)
    local mine = lostWith[bot:GetPlayerID()]
    local pid = h:GetPlayerID()
    if mine == nil or mine[pid] ~= true then
        return false
    end
    local quiet = Threat.SETTINGS.StayEngaged
    if not bot:WasRecentlyDamagedByHero(h, quiet) and not h:WasRecentlyDamagedByHero(bot, quiet) then
        mine[pid] = nil
        return false
    end
    return true
end
runs = {}
local function NoteRun(pid, level, target)
    runs[pid] = target ~= nil and (level == "kill" or level == "join") and ({level = level, target = target}) or nil
end
--- The enemy hero is swinging at a lane creep: a last-hit or deny attempt.
local function lastHitting(h)
    local t = h:GetAttackTarget()
    return t ~= nil and t ~= nil and not t:IsNull() and t:IsCreep() and not t:IsHero()
end
--- Where the bot attacks `target` from: here inside attack range plus both hulls, else the point on the line to it at that distance (where an attack order stops walking).
local function attackPoint(bot, target)
    local me = bot:GetLocation()
    local at = target:GetLocation()
    local range = bot:GetAttackRange() + bot:GetBoundingRadius() + target:GetBoundingRadius()
    local d = distXY(me, at)
    if d <= range then
        return me
    end
    local f = range / d
    return Vector(at.x + (me.x - at.x) * f, at.y + (me.y - at.y) * f, me.z)
end
--- Seconds from an attack's start to its hit (or its projectile's launch): the attack point over the attack speed, as the engine's last-hit timing reads it.
local function attackPointOf(u)
    local x = u
    local ____opt_20 = x.GetAttackSpeed
    local speed = ____opt_20 and ____opt_20(x) or 1
    local ____opt_22 = x.GetAttackPoint
    return (____opt_22 and ____opt_22(x) or 0) / (speed > 0 and speed or 1)
end
TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
    Tower.Base1,
    Tower.Base2
}
--- The inputs of one frame, read from the game once. `rs` is the executor's running exchange, if any. Reads only (it writes the heading samples and the last-seen record).
function ____exports.Gather(bot, rs)
    local now = DotaTime()
    local here = bot:GetLocation()
    local safeHit = SafeGather.At(bot, here, {held = true, hold = false, who = "trade"})
    local safeHold = SafeGather.At(bot, here, {held = true, hold = true})
    local wave = 0
    local creepsOnMe = 0
    local swingOn = Ours.On("TradeSwing")
    local creepOn = swingOn and Ours.On("CreepRead") and Ours.On("TowerRead")
    local creepReads = {}
    local heroes = bot:GetNearbyHeroes(CAND_RADIUS, true, BotMode.None)
    if not swingOn or #heroes == 0 then
        for ____, c in ipairs(bot:GetNearbyLaneCreeps(CREEP_RADIUS, true)) do
            do
                local __continue177
                repeat
                    if not c:IsAlive() then
                        __continue177 = true
                        break
                    end
                    wave = wave + 1
                    if c:GetAttackTarget() == bot then
                        creepsOnMe = creepsOnMe + 1
                    end
                    __continue177 = true
                until true
                if not __continue177 then
                    break
                end
            end
        end
    else
        local physF = bot:GetActualIncomingDamage(100, DamageType.Physical) / 100
        local hull = bot:GetBoundingRadius()
        for ____, c in ipairs(bot:GetNearbyLaneCreeps(SWING_SCAN, true)) do
            do
                local __continue182
                repeat
                    if c:IsNull() or not c:IsAlive() then
                        __continue182 = true
                        break
                    end
                    local l = c:GetLocation()
                    if l == nil then
                        __continue182 = true
                        break
                    end
                    local dHere = distXY(l, here)
                    if dHere <= CREEP_RADIUS then
                        wave = wave + 1
                        if c:GetAttackTarget() == bot then
                            creepsOnMe = creepsOnMe + 1
                        end
                    end
                    local ____this_31
                    ____this_31 = c
                    local ____opt_30 = ____this_31.GetSecondsPerAttack
                    local spa = ____opt_30 and ____opt_30(____this_31)
                    creepReads[#creepReads + 1] = {
                        at = l,
                        dHere = dHere,
                        dps = c:GetAttackDamage() / (spa ~= nil and spa > 0 and spa or CREEP_SPA) * physF,
                        reach = c:GetAttackRange() + c:GetBoundingRadius() + hull,
                        ms = c:GetCurrentMovementSpeed()
                    }
                    __continue182 = true
                until true
                if not __continue182 then
                    break
                end
            end
        end
    end
    local towerOnMe = false
    local reach = LaneConfig.TowerReach()
    local towers = {}
    for ____, t in ipairs(bot:GetNearbyTowers(reach + 1000, true)) do
        do
            local __continue188
            repeat
                if not t:IsAlive() then
                    __continue188 = true
                    break
                end
                towers[#towers + 1] = t:GetLocation()
                if t:GetAttackTarget() == bot then
                    creepsOnMe = creepsOnMe + 2
                    towerOnMe = true
                end
                __continue188 = true
            until true
            if not __continue188 then
                break
            end
        end
    end
    local bpid = bot:GetPlayerID()
    local primed = primedAt[bpid]
    local cover = primed ~= nil and math.max(0, AGGRO_COOLDOWN - COOLDOWN_LEFT - (now - primed)) or 0
    local pairRead = PairJoin.For(bot)
    local pair = pairRead.ans ~= nil and pairRead.rec ~= nil and pairRead.ans.tgt ~= -1 and ({tgt = pairRead.ans.tgt, ko = pairRead.ans.ko, kt = pairRead.ans.kt, dec = pairRead.ans.dec}) or nil
    local kept = lastPair[bpid]
    if pair ~= nil and pair.ko > pair.kt then
        lastPair[bpid] = {p = pair, at = now}
    elseif pair == nil and kept ~= nil and now - kept.at <= PairJoin.SETTINGS.Keep then
        pair = kept.p
    end
    for k in pairs(lastHandles) do
        lastHandles[k] = nil
    end
    local play = playFor(bot, here)
    local myRange = bot:GetAttackRange()
    local myHull = bot:GetBoundingRadius()
    local ms = bot:GetCurrentMovementSpeed()
    local cands = {}
    local runSeen = false
    local walkLogged = false
    local swingLogged = false
    local ownCreeps
    local atk = attackPointOf(bot)
    for ____, h in ipairs(heroes) do
        do
            local __continue196
            repeat
                if not valid(h) then
                    __continue196 = true
                    break
                end
                local pid = h:GetPlayerID()
                local at = h:GetLocation()
                local d = GetUnitToUnitDistance(bot, h)
                local gap = d - (myRange + myHull + h:GetBoundingRadius())
                noteSeen(pid, at, now)
                local vx, vy = velocityOf(pid, at, now)
                local away = 0
                if gap > 0 and d > 1 then
                    away = (vx * (at.x - here.x) + vy * (at.y - here.y)) / d
                end
                local free = ____exports.Free(
                    lastHitting(h),
                    myRange,
                    h:GetAttackRange()
                )
                local hitting = bot:WasRecentlyDamagedByHero(h, HIT_RECENT)
                local ____hitting_37 = hitting
                if not ____hitting_37 then
                    local ____bot_35 = bot
                    local ____bot_WasRecentlyDamagedByHero_36 = bot.WasRecentlyDamagedByHero
                    local ____SwingWindow_34 = SwingWindow
                    local ____this_33
                    ____this_33 = h
                    local ____opt_32 = ____this_33.GetSecondsPerAttack
                    ____hitting_37 = ____bot_WasRecentlyDamagedByHero_36(
                        ____bot_35,
                        h,
                        ____SwingWindow_34(____opt_32 and ____opt_32(____this_33))
                    )
                end
                local swung = ____hitting_37
                local stand = attackPoint(bot, h)
                local tw = false
                for ____, tl in ipairs(towers) do
                    if distXY(stand, tl) <= reach then
                        tw = true
                    end
                end
                local thp = frac(h)
                local isRun = rs ~= nil and rs.target == pid
                if isRun then
                    runSeen = true
                end
                local near
                local kc
                local say
                local oc
                local paid = swung and CreepAggro.Paid(bot, h)
                if creepOn then
                    local ca = SafeGather.CreepsAt(bot, stand)
                    near = ca.near
                    kc = ca.dmg / math.max(
                        1,
                        bot:GetHealth()
                    )
                    if isRun or ____exports.Arrives(
                        gap,
                        ms,
                        math.max(0, away),
                        BARS.walkHit + BARS.slackWalk
                    ) then
                        local ____isRun_38
                        if isRun then
                            ____isRun_38 = cover > 0
                        else
                            ____isRun_38 = cover > ____exports.SwingIn(gap, ms, away) + atk
                        end
                        local covered = ____isRun_38
                        local named = isRun or rs == nil and not swingLogged
                        swingLogged = swingLogged or named
                        local both = SafeGather.AtBoth(bot, stand, {held = true, draws = not covered, who = named and "trade_swing" or nil})
                        say = {
                            hit = sayOf(both.plain),
                            hold = sayOf(both.hold)
                        }
                    end
                    if paid then
                        if ownCreeps == nil then
                            ownCreeps = {}
                            for ____, o in ipairs(bot:GetNearbyLaneCreeps(1600, false) or ({})) do
                                do
                                    local __continue207
                                    repeat
                                        if o:IsNull() or not o:IsAlive() then
                                            __continue207 = true
                                            break
                                        end
                                        local ol = o:GetLocation()
                                        if ol == nil then
                                            __continue207 = true
                                            break
                                        end
                                        local ____this_40
                                        ____this_40 = o
                                        local ____opt_39 = ____this_40.GetSecondsPerAttack
                                        local spa = ____opt_39 and ____opt_39(____this_40)
                                        ownCreeps[#ownCreeps + 1] = {
                                            at = ol,
                                            dps = o:GetAttackDamage() / (spa ~= nil and spa > 0 and spa or CREEP_SPA)
                                        }
                                        __continue207 = true
                                    until true
                                    if not __continue207 then
                                        break
                                    end
                                end
                            end
                        end
                        local dps = 0
                        for ____, o in ipairs(ownCreeps) do
                            if distXY(o.at, at) <= CREEP_RADIUS then
                                dps = dps + o.dps
                            end
                        end
                        oc = dps * (h:GetActualIncomingDamage(100, DamageType.Physical) / 100) * PairJoin.SETTINGS.Window / math.max(
                            1,
                            h:GetHealth()
                        )
                    end
                elseif swingOn then
                    near = 0
                    local dmg = 0
                    for ____, cr in ipairs(creepReads) do
                        do
                            local __continue215
                            repeat
                                local dStand = distXY(cr.at, stand)
                                if dStand > AGGRO_CLEAR and cr.dHere > AGGRO_CLEAR then
                                    __continue215 = true
                                    break
                                end
                                near = near + 1
                                local ta = arrive(dStand, cr.reach, cr.ms)
                                if ta < PairJoin.SETTINGS.Window then
                                    dmg = dmg + cr.dps * (PairJoin.SETTINGS.Window - ta)
                                end
                                __continue215 = true
                            until true
                            if not __continue215 then
                                break
                            end
                        end
                    end
                    kc = dmg / math.max(
                        1,
                        bot:GetHealth()
                    )
                end
                local shares = not free or near ~= nil and near > 0
                local c = {
                    pid = pid,
                    thp = thp,
                    thpAbs = h:GetHealth(),
                    d = d,
                    gap = gap,
                    away = away,
                    hitting = hitting,
                    swung = swung,
                    free = free,
                    ko = shares and shareOn(bot, h) or 0,
                    kt = shares and shareOn(h, bot) or 0,
                    paid = paid,
                    tw = tw,
                    lost = lostFor(bot, h),
                    near = near,
                    kc = kc,
                    say = say,
                    oc = oc
                }
                lastHandles[pid] = h
                local asked = thp <= BARS.commitHp or pair ~= nil and pair.tgt == pid or play ~= nil and play.tgt == pid or isRun
                if asked then
                    local named = isRun or rs == nil and not walkLogged
                    walkLogged = walkLogged or named
                    c.walk = sayOf(SafeGather.At(bot, at, {
                        horizon = SafeGather.WalkHorizon,
                        away = true,
                        held = false,
                        hold = true,
                        draws = creepOn,
                        who = named and "trade_walk" or nil
                    }))
                end
                if thp <= BARS.commitHp or isRun and rs.level == "kill" then
                    local ls = {
                        vx = vx,
                        vy = vy,
                        physF = h:GetActualIncomingDamage(100, DamageType.Physical) / 100,
                        magF = h:GetActualIncomingDamage(100, DamageType.Magical) / 100,
                        hull = h:GetBoundingRadius(),
                        thpAbs = c.thpAbs
                    }
                    lastSeen[pid] = ls
                    local hunters = huntersOf(
                        bot,
                        at,
                        ls,
                        pid,
                        true,
                        true
                    )
                    c.hunters = hunters
                    c.catch = ____exports.CatchRead(
                        hunters,
                        c.thpAbs,
                        safeTime(
                            bot,
                            at,
                            ls,
                            pid,
                            true,
                            true
                        )
                    )
                end
                cands[#cands + 1] = c
                __continue196 = true
            until true
            if not __continue196 then
                break
            end
        end
    end
    local i = {
        now = now,
        hp = frac(bot),
        safe = {
            hit = sayOf(safeHit),
            hold = sayOf(safeHold)
        },
        n = #cands,
        ms = ms,
        towerOnMe = towerOnMe,
        creepsOnMe = creepsOnMe,
        wave = wave,
        denyDue = Laning.DenyDue(bot),
        pair = pair,
        play = play,
        cands = cands
    }
    if swingOn then
        local ____cover_42 = cover
        local ____temp_41
        if #cands > 0 then
            ____temp_41 = Laning.NextDue(bot)
        else
            ____temp_41 = nil
        end
        i.swing = {cover = ____cover_42, due = ____temp_41, atk = atk}
    end
    if creepOn then
        i.creepRead = true
    end
    if Ours.On("TradeHold") then
        i.hold = true
    end
    if i.play ~= nil and i.play.zero == nil then
        local pc = __TS__ArrayFind(
            cands,
            function(____, c) return c.pid == i.play.tgt end
        )
        if pc ~= nil then
            i.play.zero = ____exports.FightZero(i, pc)
        end
    end
    if rs ~= nil then
        i.run = runOf(bot, rs, runSeen, here)
    end
    return i
end
--- The cut's cadence: an answer change at once, a running exchange every 0.5 s, else every 2 s, to the laning stage's end (PairJoin's 12:00).
local CUT_RUNNING = 0.5
local CUT_IDLE = 2
local CUT_UNTIL = 720
local cutState = {}
--- Six places: a replay on a border decides as the game did.
local function round6(v)
    return math.floor(v * 1000000 + 0.5) / 1000000
end
local function r1(v)
    return math.floor(v * 10 + 0.5) / 10
end
local function bit(b)
    local ____temp_46
    if b == nil then
        ____temp_46 = nil
    else
        ____temp_46 = b and 1 or 0
    end
    return ____temp_46
end
local function ____or(v)
    return v == nil and "-" or v
end
--- `arr` (the seventh field) is the opening read for a reader of the line: we reach attack range within `walkHit`. Decide recomputes it from gap, away and `ms`.
local function candText(c, ms)
    local w = c.walk
    local k = c.catch
    local ____array_61 = __TS__SparseArrayNew(
        c.pid,
        round6(c.thp),
        math.floor(c.thpAbs + 0.5),
        math.floor(c.d),
        math.floor(c.gap),
        math.floor(c.away),
        ____exports.Arrives(
            c.gap,
            ms,
            math.max(0, c.away),
            BARS.walkHit
        ) and 1 or 0,
        c.hitting and 1 or 0,
        c.free and 1 or 0,
        round6(c.ko),
        round6(c.kt),
        c.paid and 1 or 0,
        c.tw and 1 or 0,
        ____or(w and w.level),
        ____or(w ~= nil and sayRatio(w) or nil),
        ____or(w and w.reason),
        ____or(bit(k and k.ok)),
        ____or(k ~= nil and math.floor(k.dmg + 0.5) or nil),
        ____or(k ~= nil and round6(k.safe) or nil),
        c.lost == true and 1 or 0,
        c.swung and 1 or 0,
        ____or(c.near),
        ____or(c.kc ~= nil and round6(c.kc) or nil)
    )
    local ____opt_53 = c.say
    __TS__SparseArrayPush(
        ____array_61,
        ____or(____opt_53 and ____opt_53.hit.level),
        ____or(c.say ~= nil and sayRatio(c.say.hit) or nil)
    )
    local ____opt_55 = c.say
    __TS__SparseArrayPush(
        ____array_61,
        ____or(____opt_55 and ____opt_55.hit.reason)
    )
    local ____opt_57 = c.say
    __TS__SparseArrayPush(
        ____array_61,
        ____or(____opt_57 and ____opt_57.hold.level),
        ____or(c.say ~= nil and sayRatio(c.say.hold) or nil)
    )
    local ____opt_59 = c.say
    __TS__SparseArrayPush(
        ____array_61,
        ____or(____opt_59 and ____opt_59.hold.reason),
        ____or(c.oc ~= nil and round6(c.oc) or nil)
    )
    return table.concat(
        {__TS__SparseArraySpread(____array_61)},
        ","
    )
end
--- The ratio of a `Say` to six places; `-` when nothing can reach (`math.huge`).
sayRatio = function(s) return s.ratio == math.huge and "-" or round6(s.ratio) end
local function sayText(s)
    return table.concat(
        {
            s.level,
            sayRatio(s),
            s.reason
        },
        ","
    )
end
local function huntersText(hs)
    local out = {}
    for ____, h in ipairs(hs) do
        local sp = {}
        for ____, s in ipairs(h.spells) do
            sp[#sp + 1] = (((tostring(r1(s.range)) .. ":") .. tostring(math.floor(s.cp * 100 + 0.5) / 100)) .. ":") .. tostring(r1(s.dmg))
        end
        out[#out + 1] = table.concat(
            {
                r1(h.d),
                r1(h.reach),
                r1(h.close),
                r1(h.dps),
                table.concat(sp, "/")
            },
            ","
        )
    end
    return table.concat(out, ";")
end
local function runText(r, now)
    local ____array_64 = __TS__SparseArrayNew(
        r.level,
        r.target,
        ____or(r.source),
        r.alive and 1 or 0,
        round6(r.offered),
        ____or(r.started ~= nil and round6(r.started) or nil),
        r.landed and 1 or 0,
        round6(r.soFar),
        r.catchFails,
        ____or(r.catchFailAt ~= nil and round6(now - r.catchFailAt) or nil),
        ____or(r.stepFor ~= nil and round6(r.stepFor) or nil),
        ____or(r.chaseAt ~= nil and math.floor(r.chaseAt.x) or nil),
        ____or(r.chaseAt ~= nil and math.floor(r.chaseAt.y) or nil)
    )
    local ____opt_62 = r.catch
    __TS__SparseArrayPush(
        ____array_64,
        ____or(bit(____opt_62 and ____opt_62.ok))
    )
    return table.concat(
        {__TS__SparseArraySpread(____array_64)},
        ":"
    )
end
local function howText(h)
    if h == nil then
        return nil
    end
    return h.at ~= nil and (((((h.verb .. ":") .. h.aggro) .. "@") .. tostring(math.floor(h.at.x))) .. ",") .. tostring(math.floor(h.at.y)) or (h.verb .. ":") .. h.aggro
end
--- The `ev=cut kind=trade` line for this frame's inputs and answer, when one is due (see the cut's cadence). Reads only.
function ____exports.Cut(bot, i, a)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or i.now > CUT_UNTIL then
        return
    end
    if #i.cands == 0 and i.run == nil then
        return
    end
    local pid = bot:GetPlayerID()
    local ____temp_65 = cutState[pid] or ({})
    cutState[pid] = ____temp_65
    local st = ____temp_65
    local key = (((((a.level .. ":") .. tostring(a.target)) .. ":") .. a.reason) .. ":") .. tostring(a.ended)
    local every = i.run ~= nil and CUT_RUNNING or CUT_IDLE
    if key == st.key and st.at ~= nil and i.now >= st.at and i.now - st.at < every then
        return
    end
    st.key = key
    st.at = i.now
    local lowest
    for ____, c in ipairs(i.cands) do
        if c.hunters ~= nil and (lowest == nil or c.thp < lowest.thp) then
            lowest = c
        end
    end
    local pos = LaneConfig.PositionOf(bot)
    local cds = {}
    for ____, c in ipairs(i.cands) do
        cds[#cds + 1] = candText(c, i.ms)
    end
    local ____opt_66 = i.run
    local u = ____opt_66 and ____opt_66.unseen
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "trade"},
            {"role", pos ~= nil and pos >= 4 and "support" or "core"},
            {
                "hp",
                round6(i.hp)
            },
            {
                "svh",
                sayText(i.safe.hit)
            },
            {
                "svb",
                sayText(i.safe.hold)
            },
            {"n", i.n},
            {
                "ms",
                math.floor(i.ms)
            },
            {"tm", i.towerOnMe and 1 or 0},
            {"hc", i.creepsOnMe},
            {"cr", i.wave},
            {"dn", i.denyDue and 1 or 0},
            {
                "swg",
                i.swing ~= nil and (((tostring(round6(i.swing.cover)) .. ":") .. tostring(____or(i.swing.due ~= nil and round6(i.swing.due) or nil))) .. ":") .. tostring(round6(i.swing.atk)) or nil
            },
            {"thd", i.hold == true and 1 or nil},
            {"crd", i.creepRead == true and 1 or nil},
            {
                "pjr",
                i.pair ~= nil and (((((i.pair.dec .. ":") .. tostring(i.pair.tgt)) .. ":") .. tostring(round6(i.pair.ko))) .. ":") .. tostring(round6(i.pair.kt)) or nil
            },
            {
                "pl",
                i.play ~= nil and (((((tostring(i.play.id) .. ":") .. i.play.kind) .. ":") .. tostring(i.play.tgt)) .. ":") .. (i.play.zero or "-") or nil
            },
            {
                "cd",
                table.concat(cds, ";")
            },
            {
                "chu",
                lowest ~= nil and huntersText(lowest.hunters) or nil
            },
            {
                "run",
                i.run ~= nil and runText(i.run, i.now) or nil
            },
            {
                "uat",
                bit(u and u.at)
            },
            {
                "utw",
                bit(u and u.tower)
            },
            {
                "uth",
                bit(u and u.threat)
            },
            {"lv", a.level},
            {"tgt", a.target},
            {"src", a.source},
            {
                "how",
                howText(a.how)
            },
            {"why", a.reason},
            {"ed", a.ended}
        }
    )
end
--- Desire of a hit or hit back, and of a kill or join: under laning's 0.9 last-hit desire and any retreat (design section 9).
____exports.DESIRE_HIT = 0.6
____exports.DESIRE_COMMIT = 0.75
--- The speculative lane fight (slice lane-fight, user 04/11/2026: the fights no clear window decides come from the play roll):
-- the base weight is the older core trade's (before value on cil5, lposchk3, sspotchk1: cores 0.4 kills and 0.5 deaths per 100 encounters at
-- even numbers with the enemy over 40%, about 110 such encounters a game; lfpchk1 at 0.05 fired 1.6 a game, so 0.1 for about 4;
-- `judgement`), a chance per target at most every FIGHT_ROLL_EVERY s so standing beside a hero is not a roll a frame. A fired play
-- is fought as a join by its roller and by whoever joins it; the play ends with the roller's exchange or at its timeout.
____exports.LANE_FIGHT = "lane_fight"
local FIGHT_BASE = 0.1
local FIGHT_ROLL_EVERY = 15
local FIGHT_TIMEOUT = 10
Plays.Define(____exports.LANE_FIGHT, {base = FIGHT_BASE, timeout = FIGHT_TIMEOUT, chases = true})
--- Within this of its assigned lane's path the hero is in lane.
local LANE_WIDTH = 1200
NO_EVERY = 5
--- After a loss of sight (`target_lost`), what follows within this many seconds is logged on `ev=chase`.
local CHASE_WATCH = 12
episodes = {}
--- Which arm this frame's GetDesire took: Think follows it.
local ownsFrame = {}
--- When this bot last had a lane-fight chance, per target pid.
local rolledAt = {}
lastNo = {}
--- Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it): the laning body holds the hero.
function ____exports.Owns(bot)
    return Ours.On("Trade") and (CoreLastHit.Applies(bot) or SupportDeny.Applies(bot))
end
--- The hero lanes: held by its laning body (transitions/phase) and standing by its own lane; elsewhere OHA's port fights.
local function inLane(bot)
    return Phase.LaningHeld(bot) and GetAmountAlongLane(
        bot:GetAssignedLane(),
        bot:GetLocation()
    ).distance <= LANE_WIDTH
end
--- Every fight of this in-lane hero beyond a hit is this module's: team roam keeps only its non-fight branches for it.
function ____exports.OwnsFights(bot)
    return ____exports.Owns(bot) and bot:IsAlive() and inLane(bot)
end
--- OHA's farm mode runs a laning hero off on its own triggers (`X.ShouldRun`); in lane this context decides when its hero backs off, so farm skips them.
function ____exports.OwnsLaneRun(bot)
    return ____exports.Owns(bot) and inLane(bot)
end
kindOf = function(level) return (level == "hit" or level == "hitback") and "trade" or level end
local function desireOf(level)
    return (level == "hit" or level == "hitback") and ____exports.DESIRE_HIT or ____exports.DESIRE_COMMIT
end
--- Where the running exchange stands: `Deficit` from the landing baseline once our first hit has landed, before it from the start (a ranged hit counts from its firing).
local function soFarOf(bot, ep, now)
    local hp = bot:GetHealth()
    local thp = valid(ep.target) and ep.target:GetHealth() or ep.thpSeen
    local max = bot:GetMaxHealth()
    local fired = bot:GetLastAttackTime()
    local rose = ep.atkSeen ~= nil and fired > ep.atkSeen
    if rose then
        ep.atkSeen = fired
    end
    local at = bot:GetAttackTarget()
    if ep.landedAt == nil and rose and at ~= nil and at ~= nil and at:IsHero() and at:GetPlayerID() == ep.tpid then
        ep.landedAt = now
        ep.hpL = ep.hpPrev or ep.hp0
        ep.thpL = ep.thpPrev or ep.thp0
    end
    if ep.landedAt == nil then
        ep.hpPrev = hp
        ep.thpPrev = thp
        return {
            landed = false,
            soFar = ____exports.Deficit(
                ep.hp0,
                hp,
                ep.thp0,
                thp,
                max
            )
        }
    end
    return {
        landed = true,
        soFar = ____exports.Deficit(
            ep.hpL,
            hp,
            ep.thpL,
            thp,
            max
        )
    }
end
--- The executor's numbers for Decide: what `Gather` takes as the running exchange.
local function RunStateOf(bot, ep, now)
    local sf = soFarOf(bot, ep, now)
    return {
        level = ep.level,
        target = ep.tpid,
        source = ep.source,
        offered = now - ep.offeredAt,
        started = ep.startedAt ~= nil and now - ep.startedAt or nil,
        landed = sf.landed,
        soFar = sf.soFar,
        catchFails = ep.catchFails,
        catchFailAt = ep.catchFailAt,
        stepFor = ep.stepSince ~= nil and now - ep.stepSince or nil
    }
end
--- What holds retreat for this hero now (`HoldsOf` on this frame's inputs): `hitback`, `join` or nothing.
function ____exports.Holds(bot)
    if not ____exports.Owns(bot) or not bot:IsAlive() or not inLane(bot) then
        return nil
    end
    local ep = episodes[bot:GetPlayerID()]
    local i = ____exports.Gather(
        bot,
        ep ~= nil and ep.ended ~= true and RunStateOf(
            bot,
            ep,
            DotaTime()
        ) or nil
    )
    return ____exports.HoldsOf(i)
end
--- The enemy hero `pid` if our team sees it now: a hero's handle reads null once it leaves sight and a new one comes back with it.
local function seenHero(pid)
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if h ~= nil and h ~= nil and not h:IsNull() and not h:IsIllusion() and h:GetPlayerID() == pid and h:IsAlive() and h:CanBeSeen() then
            return h
        end
    end
    return nil
end
chases = {}
local function chaseTick(bot, now)
    local c = chases[bot:GetPlayerID()]
    if c == nil then
        return
    end
    local dead = not IsHeroAlive(c.tpid)
    local ____dead_78
    if dead then
        ____dead_78 = nil
    else
        ____dead_78 = seenHero(c.tpid)
    end
    local seen = ____dead_78
    local out = now - c.at > CHASE_WATCH
    if not dead and seen == nil and not out then
        return
    end
    chaseEnd(
        bot,
        c,
        now,
        dead and "dead" or (seen ~= nil and "seen" or "gone"),
        seen
    )
end
--- The target Think named with SetTarget is cleared, if it is still the one set (another module's stays).
local function clearTarget(bot, ep)
    local t = bot:GetTarget()
    if t == nil or t == nil then
        return
    end
    if t == ep.target or valid(t) and t:IsHero() and t:GetPlayerID() == ep.tpid or not valid(t) then
        bot:SetTarget(nil)
    end
end
local function close(bot, ep, why, now)
    local pid = bot:GetPlayerID()
    episodes[pid] = nil
    NoteRun(pid, "none", nil)
    if ep.level ~= "hit" and ep.level ~= "hitback" then
        clearTarget(bot, ep)
    end
    if why == "losing" then
        local ____temp_79 = lostWith[pid] or ({})
        lostWith[pid] = ____temp_79
        local mine = ____temp_79
        mine[ep.tpid] = true
    end
    local started = ep.startedAt ~= nil
    if ep.play ~= nil and ep.play.by == bot then
        Plays.End(ep.play, why)
    end
    local killed = started and not IsHeroAlive(ep.tpid)
    local thp = killed and 0 or (valid(ep.target) and ep.target:GetHealth() or ep.thpSeen)
    if why == "target_lost" and Telemetry.IsEnabled() then
        chaseLost(bot, ep, now)
    end
    local ____Telemetry_Event_83 = Telemetry.Event
    local ____array_82 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "role",
            roleOf(bot)
        },
        {"kind", ep.level},
        {"tgt", ep.tpid}
    )
    local ____opt_80 = ep.play
    __TS__SparseArrayPush(
        ____array_82,
        {"play", ____opt_80 and ____opt_80.id},
        {"join", ep.play ~= nil and (ep.joined == true and 1 or 0) or nil},
        {"hb", ep.level == "hitback" and 1 or nil},
        {"result", started and (killed and "kill" or "done") or "lost"},
        {"why", why},
        {
            "dur",
            started and math.floor((now - ep.startedAt) * 10) / 10 or 0
        },
        {
            "hpd",
            started and ep.hp0 - bot:GetHealth() or 0
        },
        {"thpd", started and ep.thp0 - thp or 0},
        {
            "ld",
            started and ep.landedAt ~= nil and math.floor((ep.landedAt - ep.startedAt) * 10) / 10 or nil
        },
        {
            "hp",
            math.floor(ep.hp * 100) / 100
        },
        {
            "thp",
            math.floor(ep.thp * 100) / 100
        },
        {"en", ep.n},
        {"cr", ep.wave},
        {"pr", ep.primes},
        {"so", ep.stepOuts},
        {"fa", ep.first},
        {
            "ato",
            ____exports.TrueAtOpen(why, ep.opens, ep.first)
        },
        {"ag", ep.aggro},
        {
            "mode",
            bot:GetActiveMode()
        },
        {
            "md",
            math.floor(bot:GetActiveModeDesire() * 100) / 100
        }
    )
    ____Telemetry_Event_83(
        "trade",
        {__TS__SparseArraySpread(____array_82)}
    )
    if started then
        PairJoin.After(
            bot,
            kindOf(ep.level),
            why,
            ep.tpid
        )
    end
end
local function open(bot, i, a, now)
    local level = a.level
    local tpid = a.target
    local t = lastHandles[tpid]
    if t == nil then
        return 0
    end
    local c = __TS__ArrayFind(
        i.cands,
        function(____, x) return x.pid == tpid end
    )
    local play
    local joined
    if a.source == "play" and i.play ~= nil then
        play = __TS__ArrayFind(
            Plays.Active(),
            function(____, p) return p.id == i.play.id end
        )
        if play ~= nil then
            if Plays.Of(bot) == nil then
                Plays.Join(play, bot)
            end
            joined = play.by ~= bot
        end
    end
    local pid = bot:GetPlayerID()
    episodes[pid] = {
        level = level,
        source = a.source,
        tpid = tpid,
        target = t,
        how = a.how,
        offeredAt = now,
        hp0 = bot:GetHealth(),
        thp0 = t:GetHealth(),
        catchFails = 0,
        primes = 0,
        stepOuts = 0,
        aggro = 0,
        tmax = t:GetMaxHealth(),
        thull = t:GetBoundingRadius(),
        thpSeen = t:GetHealth(),
        play = play,
        joined = joined,
        hp = i.hp,
        thp = c.thp,
        n = i.n,
        wave = i.wave,
        opens = ____exports.OpenFails(i, c)
    }
    NoteRun(pid, level, tpid)
    return desireOf(level)
end
--- What this frame's answer does to the episode: keep it (a level change on the same target is made in place), end it, open one. Returns the desire.
local function apply(bot, ep, i, a, now)
    local pid = bot:GetPlayerID()
    if ep ~= nil then
        if a.level ~= "none" and a.target == ep.tpid and a.ended == nil then
            if a.level ~= ep.level then
                ep.level = a.level
                NoteRun(pid, ep.level, ep.tpid)
            end
            ep.source = a.source
            ep.how = a.how
            if a.catchFails ~= nil then
                ep.catchFails = a.catchFails
                ep.catchFailAt = a.catchFailAt
            end
            return desireOf(ep.level)
        end
        close(bot, ep, a.ended or (a.level ~= "none" and a.target ~= ep.tpid and "switch" or a.reason), now)
    end
    if a.level == "none" then
        unanswered(bot, now, a.reason, i)
        return 0
    end
    return open(bot, i, a, now)
end
--- Whether a lane-fight chance on `tpid` is due (at most every FIGHT_ROLL_EVERY seconds); asking claims it.
local function rollDue(bot, tpid, now)
    local pid = bot:GetPlayerID()
    local ____temp_84 = rolledAt[pid] or ({})
    rolledAt[pid] = ____temp_84
    local seen = ____temp_84
    local last = seen[tpid]
    if last ~= nil and now - last < FIGHT_ROLL_EVERY then
        return false
    end
    seen[tpid] = now
    return true
end
--- The lane-fight chance (design section 4): offered once per target per FIGHT_ROLL_EVERY s when the frame's answer is a hit or
-- nothing and tower, burst (the walk read) and wave pass. The target is the hit's, else the nearest hero.
local function chanceTarget(bot, i, a, now)
    if a.level ~= "hit" and a.level ~= "none" then
        return nil
    end
    local c
    if a.level == "hit" then
        c = __TS__ArrayFind(
            i.cands,
            function(____, x) return x.pid == a.target end
        )
    else
        for ____, x in ipairs(i.cands) do
            if c == nil or x.d < c.d then
                c = x
            end
        end
    end
    local ____temp_85
    if c ~= nil then
        ____temp_85 = lastHandles[c.pid]
    else
        ____temp_85 = nil
    end
    local t = ____temp_85
    if c == nil or t == nil or not rollDue(bot, c.pid, now) then
        return nil
    end
    if c.walk == nil then
        c.walk = sayOf(SafeGather.At(
            bot,
            t:GetLocation(),
            {horizon = SafeGather.WalkHorizon, away = true, held = false, hold = true}
        ))
    end
    return ____exports.FightZero(i, c) == nil and t or nil
end
--- The in-lane attack desire, or undefined outside lane (the caller then asks OHA's port). One Gather and one Decide a frame; the
-- answer opens, keeps (a level change on the same target in place), ends or replaces the hero's exchange. An exchange attack mode
-- never took is ended `not_taken` by Decide itself.
function ____exports.Desire(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local ep = episodes[pid]
    if Telemetry.IsEnabled() then
        chaseTick(bot, now)
    end
    if not bot:IsAlive() or not inLane(bot) then
        if ep ~= nil then
            close(
                bot,
                ep,
                bot:IsAlive() and "lane_end" or "dead",
                now
            )
        end
        ownsFrame[pid] = false
        local ____bot_IsAlive_result_86
        if bot:IsAlive() then
            ____bot_IsAlive_result_86 = nil
        else
            ____bot_IsAlive_result_86 = 0
        end
        return ____bot_IsAlive_result_86
    end
    ownsFrame[pid] = true
    Plays.Tick(now)
    if ep ~= nil and ep.ended == true then
        close(
            bot,
            ep,
            "mode_" .. tostring(bot:GetActiveMode()),
            now
        )
        ep = nil
    end
    local mine = Plays.Of(bot)
    if mine ~= nil and mine.by == bot and mine.kind ~= ____exports.LANE_FIGHT then
        if ep ~= nil then
            close(bot, ep, "play", now)
        end
        return 0
    end
    local i = ____exports.Gather(
        bot,
        ep ~= nil and RunStateOf(bot, ep, now) or nil
    )
    if ep ~= nil then
        noteSight(bot, ep, now)
    end
    local a = ____exports.Decide(i)
    if ep == nil and ____exports.OwnsFights(bot) then
        local t = chanceTarget(bot, i, a, now)
        local ____temp_87
        if t ~= nil then
            ____temp_87 = Plays.Roll(
                {
                    kind = ____exports.LANE_FIGHT,
                    by = bot,
                    target = t,
                    at = t:GetLocation()
                },
                now
            )
        else
            ____temp_87 = nil
        end
        local play = ____temp_87
        if play ~= nil then
            i = ____exports.Gather(bot)
            a = ____exports.Decide(i)
            if a.level ~= "join" or a.source ~= "play" or a.target ~= play.tgt then
                Plays.End(play, "refused")
            end
        end
    end
    ____exports.Cut(bot, i, a)
    return apply(
        bot,
        ep,
        i,
        a,
        now
    )
end
--- The aggro-free attack: what a trading hero does this frame so its hits draw no creep aggro: `attack` while its own attack
-- order's cooldown covers it; `prime` (a fresh attack order) when no enemy lane creep is within AGGRO_CLEAR; otherwise `step_out`
-- of the creeps first.
function ____exports.AggroPlan(now, primed, creepsWithinClear)
    if primed ~= nil and now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT then
        return "attack"
    end
    return creepsWithinClear == 0 and "prime" or "step_out"
end
--- Whether this frame's GetDesire took our arm; mode_attack_generic's Think runs ours when true, OHA's port otherwise.
function ____exports.OwnsFrame(bot)
    return ownsFrame[bot:GetPlayerID()] == true
end
--- Carries out `Answer.how` on the episode: a move to the predicted place for an unseen chase, a committed attack order, or the aggro-free plan (the step out of the creeps is the only mechanics decided here).
function ____exports.Think(bot)
    local pid = bot:GetPlayerID()
    local ep = episodes[pid]
    if ep == nil or ep.how == nil then
        return
    end
    local how = ep.how
    local commits = how.aggro == "commit"
    if not valid(ep.target) then
        if commits then
            clearTarget(bot, ep)
        end
        if how.verb == "move" and how.at ~= nil then
            bot:Action_MoveToLocation(Vector(
                how.at.x,
                how.at.y,
                bot:GetLocation().z
            ))
        end
        return
    end
    local now = DotaTime()
    if commits then
        bot:SetTarget(ep.target)
    end
    if ep.startedAt == nil then
        ep.startedAt = now
        ep.atkSeen = bot:GetLastAttackTime()
        ep.shedSeen = ep.atkSeen
        PairJoin.Reopened(bot)
    end
    local creeps = {}
    local onMe = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(AGGRO_CLEAR, true)) do
        do
            local __continue358
            repeat
                if c:IsNull() or not c:IsAlive() then
                    __continue358 = true
                    break
                end
                creeps[#creeps + 1] = c
                if c:GetAttackTarget() == bot then
                    onMe = onMe + 1
                end
                __continue358 = true
            until true
            if not __continue358 then
                break
            end
        end
    end
    ep.aggro = math.max(ep.aggro, onMe)
    if not commits and Ours.On("CreepRead") and Ours.On("TradeSwing") and Ours.On("TowerRead") then
        Deaggro.Watch(bot)
        local last = bot:GetLastAttackTime()
        if onMe > 0 and last > (ep.shedSeen or last) then
            ep.shedSeen = last
            if Deaggro.Shed(bot).ordered then
                return
            end
        end
    end
    local plan = commits and "attack" or ____exports.AggroPlan(
        now,
        primedAt[pid],
        Ours.On("TradeSwing") and 0 or #creeps
    )
    if plan == "step_out" then
        if ep.stepSince == nil then
            ep.stepSince = now
            ep.stepOuts = ep.stepOuts + 1
        end
        ep.first = ep.first or "step"
        bot:Action_MoveToLocation(stepOutPoint(bot, creeps))
        return
    end
    ep.stepSince = nil
    ep.first = ep.first or "order"
    if plan == "prime" then
        primedAt[pid] = now
        ep.primes = ep.primes + 1
        bot:Action_AttackUnit(ep.target, false)
        return
    end
    if bot:GetAttackTarget() ~= ep.target then
        if commits then
            primedAt[pid] = now
        end
        bot:Action_AttackUnit(ep.target, false)
    end
end
--- Attack mode lost the hero to another mode: a started exchange ends there (closed by the next Desire, which can name that mode).
function ____exports.OnEnd(bot)
    local ep = episodes[bot:GetPlayerID()]
    if ep ~= nil and ep.startedAt ~= nil then
        ep.ended = true
    end
end
--- Laning's 0.9 last-hit desire must not cut a retreat this hero is already in (core-time-diagnosis s2: a death within 15 s of
-- such a cut was 4 times as likely), nor a kill or join (lfpchk1: 2 of 8 fights ended in a last hit at 4.9 s; a pair join, D10
-- group 2, is above the last hit, D11 group 3, by the doctrine). A hit or hit back still gives way to it. A predicate on the
-- laning GetDesire (OWNERSHIP H2), for every hero this context owns.
function ____exports.LastHitYields(bot)
    if not ____exports.Owns(bot) then
        return false
    end
    if bot:GetActiveMode() == BotMode.Retreat then
        return true
    end
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and (ep.level == "kill" or ep.level == "join") and ep.startedAt ~= nil and ep.ended ~= true
end
--- An exchange is open for this hero (Desire returns its desire in attack mode); reads only.
function ____exports.Running(bot)
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and ep.ended ~= true
end
--- A pair join (D10, group 2) is open for this hero, or a kill carrying one: the arbiter's pair group. Reads only.
function ____exports.Joining(bot)
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and ep.ended ~= true and ep.source == "pair"
end
--- The hero's running exchange, its level and target (ev=cast, and PairJoin's partner read). Reads only.
function ____exports.EpisodeOf(pid)
    local ep = episodes[pid]
    local ____temp_88
    if ep == nil or ep.ended == true then
        ____temp_88 = nil
    else
        ____temp_88 = {kind = ep.level, tpid = ep.tpid, target = ep.target, at = ep.offeredAt}
    end
    return ____temp_88
end
--- When this bot last gave an attack order on an enemy hero from an exchange (lane_aggro shares the 3 s draw clock).
function ____exports.PrimedAt(pid)
    return primedAt[pid]
end
--- Another lane module gave an attack order on an enemy hero: the aggro-free plan counts it as its prime.
function ____exports.NotePrimed(pid, t)
    primedAt[pid] = t
end
function ____exports.Reset()
    for k in pairs(heads) do
        heads[k] = nil
    end
    for k in pairs(lastSeen) do
        lastSeen[k] = nil
    end
    for k in pairs(runs) do
        runs[k] = nil
    end
    for k in pairs(cutState) do
        cutState[k] = nil
    end
    for k in pairs(episodes) do
        episodes[k] = nil
    end
    for k in pairs(ownsFrame) do
        ownsFrame[k] = nil
    end
    for k in pairs(primedAt) do
        primedAt[k] = nil
    end
    for k in pairs(rolledAt) do
        rolledAt[k] = nil
    end
    for k in pairs(lastNo) do
        lastNo[k] = nil
    end
    for k in pairs(chases) do
        chases[k] = nil
    end
    for k in pairs(lostWith) do
        lostWith[k] = nil
    end
    for k in pairs(lastPair) do
        lastPair[k] = nil
    end
    for k in pairs(lastHandles) do
        lastHandles[k] = nil
    end
end
return ____exports
