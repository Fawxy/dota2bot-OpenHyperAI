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
local arrive, noneReason, distXY, frac, valid, awaySpeed, rawDps, hunterOf, huntersOf, safeTime, predictedPlace, towerCovers, runOf, shareOn, playFor, roleOf, chaseLost, chaseEnd, unanswered, noteSight, stepOutPoint, BARS, CAND_RADIUS, AT_PLACE, heads, lastSeen, lastHandles, runs, TOWER_IDS, sayRatio, AGGRO_CLEAR, NO_EVERY, episodes, lastNo, kindOf, chases
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
    local ____this_18
    ____this_18 = u
    local ____opt_17 = ____this_18.GetSecondsPerAttack
    local spa = ____opt_17 and ____opt_17(____this_18)
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
            local __continue131
            repeat
                if a == nil or a == nil or a:IsNull() or not a:IsAlive() or a:IsIllusion() or a:GetPlayerID() == me then
                    __continue131 = true
                    break
                end
                local ____opt_19 = runs[a:GetPlayerID()]
                if (____opt_19 and ____opt_19.target) ~= pid then
                    __continue131 = true
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
                __continue131 = true
            until true
            if not __continue131 then
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
            local __continue136
            repeat
                local t = GetTower(theirs, id)
                if t == nil or t == nil or not t:IsAlive() then
                    __continue136 = true
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
                __continue136 = true
            until true
            if not __continue136 then
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
            local __continue147
            repeat
                if not t:IsAlive() then
                    __continue147 = true
                    break
                end
                local tl = t:GetLocation()
                if distXY(tl, a) <= reach or distXY(tl, b) <= reach then
                    return true
                end
                __continue147 = true
            until true
            if not __continue147 then
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
    local walk = SafeGather.At(bot, place, {
        horizon = SafeGather.WalkHorizon,
        away = true,
        held = false,
        hold = true,
        exclude = rs.target
    })
    run.unseen = {
        at = distXY(here, place) <= bot:GetBoundingRadius() + hull + AT_PLACE,
        tower = towerCovers(bot, here, place),
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
        local ____temp_27
        if mine.by == bot and mine.kind ~= ____exports.LANE_FIGHT then
            ____temp_27 = nil
        else
            ____temp_27 = pick(mine)
        end
        return ____temp_27
    end
    for ____, p in ipairs(Plays.Near(here, CAND_RADIUS)) do
        do
            local __continue186
            repeat
                if p.by == bot then
                    __continue186 = true
                    break
                end
                local r = pick(p)
                if r ~= nil then
                    return r
                end
                __continue186 = true
            until true
            if not __continue186 then
                break
            end
        end
    end
    return nil
end
--- Why a lane fight on this candidate is off the table, whoever starts it: their tower, the walk's answer (`kill`, `unknown`), a big wave.
function ____exports.FightZero(i, c)
    if i.towerOnMe or c.tw then
        return "tower"
    end
    local say = c.walk or i.safe.hold
    if say.level == "deadly" then
        return say.reason
    end
    if i.wave > BARS.waveKill then
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
    local ____opt_47 = heads[ep.tpid]
    local a = ____opt_47 and ____opt_47.s0
    local ____opt_49 = heads[ep.tpid]
    local b = ____opt_49 and ____opt_49.s1
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
            local __continue317
            repeat
                local l = c:GetLocation()
                if l == nil then
                    __continue317 = true
                    break
                end
                x = x + l.x
                y = y + l.y
                seen = seen + 1
                __continue317 = true
            until true
            if not __continue317 then
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
    chase = 30
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
    if i.towerOnMe or c.tw then
        return "tower"
    end
    local walks = level == "kill" or level == "join"
    local slack = run ~= nil
    local say = walks and c.walk ~= nil and c.walk or (level == "hit" and i.safe.hit or i.safe.hold)
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
        if i.wave > BARS.waveKill + wave then
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
    if not (c.free or c.ko > c.kt or level == "hitback" and c.paid) then
        return "unfavoured"
    end
    if (run and run.stepFor) == nil and not ____exports.Arrives(
        c.gap,
        i.ms,
        math.max(0, c.away),
        BARS.walkHit + (slack and BARS.slackWalk or 0)
    ) then
        return "no_reach"
    end
    if i.denyDue then
        return "deny"
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
    if c.hitting and not fail(gate(
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
    if run.level == "hit" or run.level == "hitback" then
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
        local ____catchState_13 = catchState
        local ____i_11 = i
        local ____run_12 = run
        local ____opt_3 = c and c.catch
        local ____temp_9 = ____opt_3 and ____opt_3.ok
        if ____temp_9 == nil then
            local ____opt_7 = run.catch
            ____temp_9 = ____opt_7 and ____opt_7.ok
        end
        local ____temp_9_10 = ____temp_9
        if ____temp_9_10 == nil then
            ____temp_9_10 = true
        end
        local cs = ____catchState_13(____i_11, ____run_12, ____temp_9_10)
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
            local __continue85
            repeat
                if kept ~= nil and kept.c == c then
                    __continue85 = true
                    break
                end
                if c.pid == exclude then
                    __continue85 = true
                    break
                end
                rest[#rest + 1] = {
                    c = c,
                    p = pickFor(i, c, nil)
                }
                __continue85 = true
            until true
            if not __continue85 then
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
--- What holds retreat (design section 1, "Hold"), over the inputs (`Holds` reads them for a hero): `hitback` while some hitter passes tower and the held here answer (hold) is not `deadly` and is either paid or
-- free or favoured, whatever the swing is doing (a due deny, creeps and the wave change the swing, not the hold); `join`
-- while some candidate is a pair join. Undefined: retreat decides alone.
function ____exports.HoldsOf(i)
    local run = i.run
    for ____, c in ipairs(i.cands) do
        do
            local __continue101
            repeat
                if not c.hitting or c.lost == true or i.towerOnMe or c.tw then
                    __continue101 = true
                    break
                end
                if i.safe.hold.level == "deadly" then
                    __continue101 = true
                    break
                end
                if c.paid or c.free or c.ko > c.kt then
                    return "hitback"
                end
                __continue101 = true
            until true
            if not __continue101 then
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
--- A hero hit us "recently" within this (s): Threat.SETTINGS.EngagedRecent's value.
local HIT_RECENT = 1
--- Seconds between the two places a target's velocity is read from, and the age past which a sample is no velocity (a target seen again after a gap). `judgement`.
local HEADING_SPAN = 0.5
local HEADING_STALE = 1.5
AT_PLACE = 100
heads = {}
local function noteSeen(pid, l, now)
    local ____temp_14 = heads[pid] or ({})
    heads[pid] = ____temp_14
    local h = ____temp_14
    if h.s1 ~= nil and now - h.s1.at < HEADING_SPAN then
        return
    end
    h.s0 = h.s1
    h.s1 = {x = l.x, y = l.y, at = now}
end
--- The hero's velocity (units/s) from its movement since the sample before last; 0 when unknown.
local function velocityOf(pid, l, now)
    local ____opt_15 = heads[pid]
    local s0 = ____opt_15 and ____opt_15.s0
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
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(CREEP_RADIUS, true)) do
        do
            local __continue152
            repeat
                if not c:IsAlive() then
                    __continue152 = true
                    break
                end
                wave = wave + 1
                if c:GetAttackTarget() == bot then
                    creepsOnMe = creepsOnMe + 1
                end
                __continue152 = true
            until true
            if not __continue152 then
                break
            end
        end
    end
    local towerOnMe = false
    local reach = LaneConfig.TowerReach()
    local towers = {}
    for ____, t in ipairs(bot:GetNearbyTowers(reach + 1000, true)) do
        do
            local __continue156
            repeat
                if not t:IsAlive() then
                    __continue156 = true
                    break
                end
                towers[#towers + 1] = t:GetLocation()
                if t:GetAttackTarget() == bot then
                    creepsOnMe = creepsOnMe + 2
                    towerOnMe = true
                end
                __continue156 = true
            until true
            if not __continue156 then
                break
            end
        end
    end
    local bpid = bot:GetPlayerID()
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
    for ____, h in ipairs(bot:GetNearbyHeroes(CAND_RADIUS, true, BotMode.None)) do
        do
            local __continue164
            repeat
                if not valid(h) then
                    __continue164 = true
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
                local c = {
                    pid = pid,
                    thp = thp,
                    thpAbs = h:GetHealth(),
                    d = d,
                    gap = gap,
                    away = away,
                    hitting = hitting,
                    free = free,
                    ko = free and 0 or shareOn(bot, h),
                    kt = free and 0 or shareOn(h, bot),
                    paid = hitting and CreepAggro.Paid(bot, h),
                    tw = tw,
                    lost = lostFor(bot, h)
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
                __continue164 = true
            until true
            if not __continue164 then
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
    local ____temp_28
    if b == nil then
        ____temp_28 = nil
    else
        ____temp_28 = b and 1 or 0
    end
    return ____temp_28
end
local function ____or(v)
    return v == nil and "-" or v
end
--- `arr` (the seventh field) is the opening read for a reader of the line: we reach attack range within `walkHit`. Decide recomputes it from gap, away and `ms`.
local function candText(c, ms)
    local w = c.walk
    local k = c.catch
    return table.concat(
        {
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
            c.lost == true and 1 or 0
        },
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
    local ____array_37 = __TS__SparseArrayNew(
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
    local ____opt_35 = r.catch
    __TS__SparseArrayPush(
        ____array_37,
        ____or(bit(____opt_35 and ____opt_35.ok))
    )
    return table.concat(
        {__TS__SparseArraySpread(____array_37)},
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
    local ____temp_38 = cutState[pid] or ({})
    cutState[pid] = ____temp_38
    local st = ____temp_38
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
    local ____opt_39 = i.run
    local u = ____opt_39 and ____opt_39.unseen
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
AGGRO_CLEAR = 550
local AGGRO_COOLDOWN = 3
local COOLDOWN_LEFT = 0.3
NO_EVERY = 5
--- After a loss of sight (`target_lost`), what follows within this many seconds is logged on `ev=chase`.
local CHASE_WATCH = 12
episodes = {}
--- Which arm this frame's GetDesire took: Think follows it.
local ownsFrame = {}
--- When this bot last gave an attack order on an enemy hero (its aggro cooldown runs from there).
local primedAt = {}
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
    local ____dead_51
    if dead then
        ____dead_51 = nil
    else
        ____dead_51 = seenHero(c.tpid)
    end
    local seen = ____dead_51
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
        local ____temp_52 = lostWith[pid] or ({})
        lostWith[pid] = ____temp_52
        local mine = ____temp_52
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
    local ____Telemetry_Event_56 = Telemetry.Event
    local ____array_55 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "role",
            roleOf(bot)
        },
        {"kind", ep.level},
        {"tgt", ep.tpid}
    )
    local ____opt_53 = ep.play
    __TS__SparseArrayPush(
        ____array_55,
        {"play", ____opt_53 and ____opt_53.id},
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
    ____Telemetry_Event_56(
        "trade",
        {__TS__SparseArraySpread(____array_55)}
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
        wave = i.wave
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
    local ____temp_57 = rolledAt[pid] or ({})
    rolledAt[pid] = ____temp_57
    local seen = ____temp_57
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
    local ____temp_58
    if c ~= nil then
        ____temp_58 = lastHandles[c.pid]
    else
        ____temp_58 = nil
    end
    local t = ____temp_58
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
        local ____bot_IsAlive_result_59
        if bot:IsAlive() then
            ____bot_IsAlive_result_59 = nil
        else
            ____bot_IsAlive_result_59 = 0
        end
        return ____bot_IsAlive_result_59
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
        local ____temp_60
        if t ~= nil then
            ____temp_60 = Plays.Roll(
                {
                    kind = ____exports.LANE_FIGHT,
                    by = bot,
                    target = t,
                    at = t:GetLocation()
                },
                now
            )
        else
            ____temp_60 = nil
        end
        local play = ____temp_60
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
        PairJoin.Reopened(bot)
    end
    local creeps = {}
    local onMe = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(AGGRO_CLEAR, true)) do
        do
            local __continue307
            repeat
                if c:IsNull() or not c:IsAlive() then
                    __continue307 = true
                    break
                end
                creeps[#creeps + 1] = c
                if c:GetAttackTarget() == bot then
                    onMe = onMe + 1
                end
                __continue307 = true
            until true
            if not __continue307 then
                break
            end
        end
    end
    ep.aggro = math.max(ep.aggro, onMe)
    local plan = commits and "attack" or ____exports.AggroPlan(now, primedAt[pid], #creeps)
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
    local ____temp_61
    if ep == nil or ep.ended == true then
        ____temp_61 = nil
    else
        ____temp_61 = {kind = ep.level, tpid = ep.tpid, target = ep.target, at = ep.offeredAt}
    end
    return ____temp_61
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
