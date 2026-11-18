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
local arrive, noneReason, distXY, valid, awaySpeed, rawDps, hunterOf, huntersOf, safeTime, predictedPlace, towerCovers, runOf, shareOn, playFor, CAND_RADIUS, AT_PLACE, lastSeen, runs, TOWER_IDS
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local CreepAggro = require(GetScriptDirectory().."/FunLib/humaniser/creep_aggro")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local PairJoin = require(GetScriptDirectory().."/FunLib/humaniser/pair_join")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
function arrive(d, r, close)
    if d <= r then
        return 0
    end
    return close > 0 and (d - r) / close or math.huge
end
--- Each hunter's attacks from the moment it is in attack range to the end of `w`, and each ready spell it reaches in time, against the target's HP.
function ____exports.CatchRead(hunters, thpAbs, w)
    if w == nil then
        w = ____exports.BARS.catchWindow
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
                local __continue7
                repeat
                    local ts = arrive(h.d, s.range, h.close) + s.cp
                    if ts > w then
                        __continue7 = true
                        break
                    end
                    dmg = dmg + s.dmg
                    first = math.min(first, ts)
                    __continue7 = true
                until true
                if not __continue7 then
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
    local ____this_13
    ____this_13 = u
    local ____opt_12 = ____this_13.GetSecondsPerAttack
    local spa = ____opt_12 and ____opt_12(____this_13)
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
                local ____opt_14 = runs[a:GetPlayerID()]
                if (____opt_14 and ____opt_14.target) ~= pid then
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
        return ____exports.BARS.catchWindow
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
    return v > 0 and math.min(____exports.BARS.catchWindow, left / v) or ____exports.BARS.catchWindow
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
    local r = Threat.Read(
        bot,
        here,
        place,
        Threat.SETTINGS.GateHorizon,
        {exclude = rs.target}
    )
    run.unseen = {
        at = distXY(here, place) <= bot:GetBoundingRadius() + hull + AT_PLACE,
        tower = towerCovers(bot, here, place),
        threat = #r.mpids > 0 and r.missing >= Threat.SETTINGS.MissingRefuse
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
    if Plays.Of(bot) ~= nil then
        return nil
    end
    for ____, p in ipairs(Plays.Near(here, CAND_RADIUS)) do
        do
            local __continue177
            repeat
                local t = p.target
                if p.by == bot or not valid(t) then
                    __continue177 = true
                    break
                end
                local zero = Plays.Weigh(Plays.InputsOf({
                    kind = p.kind,
                    by = bot,
                    target = t,
                    at = t:GetLocation()
                })).zero
                return {id = p.id, kind = p.kind, tgt = p.tgt, zero = zero}
            until true
            if not __continue177 then
                break
            end
        end
    end
    return nil
end
--- Every number the decision owns, with its source. The burst and HP bars live in `Threat.SETTINGS` (StandBurst 1 / PackBurst
-- 0.5 and StandHp 0.5 / PackHp 0.7, banked h2hstand1) and the unseen bar is its `MissingRefuse` (0.5, the 425 graded rows):
-- read at call time, not copied.
____exports.BARS = {
    commitHp = 0.4,
    waveHit = 3,
    waveKill = 5,
    creeps = 2,
    slackHp = 0.05,
    slackBurst = 0.05,
    slackWave = 1,
    losing = 0.05,
    unlandedCap = 0.15,
    catchFails = 2,
    catchGap = 0.5,
    catchWindow = 30,
    walkIn = 1.5,
    pairReach = 1200,
    playWalk = 600,
    outrange = 100,
    notTaken = 1,
    noClear = 2,
    chase = 30
}
--- Whether a hero at `gap` (distance past attack range plus both hulls, 0 or less in range) is in range within `horizon` s when the target moves `away` (signed; towards us is negative) and we run at `ms`.
function ____exports.Arrives(gap, ms, away, horizon)
    if horizon == nil then
        horizon = ____exports.BARS.walkIn
    end
    if gap <= 0 then
        return true
    end
    local closing = ms - away
    return closing > 0 and gap <= closing * horizon
end
--- A hit with no answer coming back: the target swings at a lane creep, or our range is `outrange` or more over its.
function ____exports.Free(targetLastHitting, range, targetRange)
    return targetLastHitting or range >= targetRange + ____exports.BARS.outrange
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
local function burstBar(n)
    return n >= 2 and Threat.SETTINGS.PackBurst or Threat.SETTINGS.StandBurst
end
local function hpBar(n)
    return n >= 2 and Threat.SETTINGS.PackHp or Threat.SETTINGS.StandHp
end
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
        return {fails = 1, at = i.now, ended = ____exports.BARS.catchFails <= 1}
    end
    if i.now - run.catchFailAt >= ____exports.BARS.catchGap then
        return {fails = run.catchFails + 1, at = i.now, ended = run.catchFails + 1 >= ____exports.BARS.catchFails}
    end
    return {fails = run.catchFails, at = run.catchFailAt, ended = false}
end
--- The gates of one level on one candidate in the bars table's order: the first that fails, or undefined. `run` is set for the running exchange's own target (the slack).
local function gate(i, c, level, src, run)
    if i.towerOnMe or c.tw then
        return "tower"
    end
    local walks = level == "kill" or level == "join"
    local r = walks and c.walk ~= nil and c.walk or ({burst = i.burst, n = i.n, missing = i.missing})
    local slack = run ~= nil
    if r.burst >= burstBar(r.n) + (slack and ____exports.BARS.slackBurst or 0) then
        return "burst"
    end
    if not walks and i.hp < hpBar(i.n) - (slack and ____exports.BARS.slackHp or 0) then
        return "hp"
    end
    if walks and r.missing >= Threat.SETTINGS.MissingRefuse then
        return "missing"
    end
    local wave = slack and ____exports.BARS.slackWave or 0
    if level == "kill" then
        local cs = c.catch
        if cs == nil then
            return "catch"
        end
        if not cs.ok and not (run ~= nil and run.level == "kill" and not catchState(i, run, false).ended) then
            return "catch"
        end
        if i.wave > ____exports.BARS.waveKill + wave then
            return "wave"
        end
        return nil
    end
    if level == "join" then
        local ____temp_0
        if src == "pair" then
            ____temp_0 = c.d > ____exports.BARS.pairReach
        else
            ____temp_0 = c.gap > ____exports.BARS.playWalk
        end
        if ____temp_0 then
            return "no_reach"
        end
        return nil
    end
    if not (c.free or c.ko > c.kt or level == "hitback" and c.paid) then
        return "unfavoured"
    end
    if not c.arrives then
        return "no_reach"
    end
    if i.denyDue then
        return "deny"
    end
    if i.creepsOnMe >= ____exports.BARS.creeps then
        return "creeps"
    end
    if i.wave > ____exports.BARS.waveHit + wave then
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
    local killable = c.thp <= ____exports.BARS.commitHp or run ~= nil and run.level == "kill"
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
    if run.started == nil and run.offered > ____exports.BARS.notTaken then
        return "not_taken"
    end
    if run.stepFor ~= nil and run.stepFor > ____exports.BARS.noClear then
        return "no_clear"
    end
    if run.level == "kill" and run.started ~= nil and run.started > ____exports.BARS.chase then
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
        if run.soFar > (run.landed and ____exports.BARS.losing or ____exports.BARS.unlandedCap) then
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
        local ____catchState_8 = catchState
        local ____i_6 = i
        local ____run_7 = run
        local ____opt_1 = c and c.catch
        local ____temp_5 = ____opt_1 and ____opt_1.ok
        if ____temp_5 == nil then
            ____temp_5 = true
        end
        local cs = ____catchState_8(____i_6, ____run_7, ____temp_5)
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
            local __continue87
            repeat
                if kept ~= nil and kept.c == c then
                    __continue87 = true
                    break
                end
                if c.pid == exclude then
                    __continue87 = true
                    break
                end
                rest[#rest + 1] = {
                    c = c,
                    p = pickFor(i, c, nil)
                }
                __continue87 = true
            until true
            if not __continue87 then
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
--- What holds retreat (design section 1, "Hold"): `hitback` while some hitter passes tower, burst and HP and is either paid or
-- free or favoured, whatever the swing is doing (a due deny, creeps and the wave change the swing, not the hold); `join`
-- while some candidate is a pair join. Undefined: retreat decides alone.
function ____exports.Holds(i)
    local run = i.run
    for ____, c in ipairs(i.cands) do
        do
            local __continue103
            repeat
                local slack = run ~= nil and run.target == c.pid and run or nil
                if not c.hitting or i.towerOnMe or c.tw then
                    __continue103 = true
                    break
                end
                if i.burst >= burstBar(i.n) + (slack ~= nil and ____exports.BARS.slackBurst or 0) then
                    __continue103 = true
                    break
                end
                if i.hp < hpBar(i.n) - (slack ~= nil and ____exports.BARS.slackHp or 0) then
                    __continue103 = true
                    break
                end
                if c.paid or c.free or c.ko > c.kt then
                    return "hitback"
                end
                __continue103 = true
            until true
            if not __continue103 then
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
--- Per enemy hero: samples of its place a HEADING_SPAN or more apart, newest `s1` and the one before it.
local heads = {}
local function noteSeen(pid, l, now)
    local ____temp_9 = heads[pid] or ({})
    heads[pid] = ____temp_9
    local h = ____temp_9
    if h.s1 ~= nil and now - h.s1.at < HEADING_SPAN then
        return
    end
    h.s0 = h.s1
    h.s1 = {x = l.x, y = l.y, at = now}
end
--- The hero's velocity (units/s) from its movement since the sample before last; 0 when unknown.
local function velocityOf(pid, l, now)
    local ____opt_10 = heads[pid]
    local s0 = ____opt_10 and ____opt_10.s0
    if s0 == nil or now - s0.at > HEADING_STALE then
        return 0, 0
    end
    local dt = math.max(0.01, now - s0.at)
    return (l.x - s0.x) / dt, (l.y - s0.y) / dt
end
lastSeen = {}
runs = {}
function ____exports.NoteRun(pid, level, target)
    runs[pid] = target ~= nil and (level == "kill" or level == "join") and ({level = level, target = target}) or nil
end
local function frac(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
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
    local stay = Threat.Read(
        bot,
        here,
        here,
        Threat.SETTINGS.StayHorizon,
        {engagedWindow = Threat.SETTINGS.StayEngaged}
    )
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
    local walkOf = Threat.Reader(bot, Threat.SETTINGS.GateHorizon)
    local pairRead = PairJoin.For(bot)
    local pair = pairRead.ans ~= nil and pairRead.rec ~= nil and pairRead.rec.on ~= "ours" and pairRead.ans.tgt ~= -1 and ({tgt = pairRead.ans.tgt, ko = pairRead.ans.ko, kt = pairRead.ans.kt, dec = pairRead.ans.dec}) or nil
    local play = playFor(bot, here)
    local myRange = bot:GetAttackRange()
    local myHull = bot:GetBoundingRadius()
    local ms = bot:GetCurrentMovementSpeed()
    local cands = {}
    local runSeen = false
    for ____, h in ipairs(bot:GetNearbyHeroes(CAND_RADIUS, true, BotMode.None)) do
        do
            local __continue160
            repeat
                if not valid(h) then
                    __continue160 = true
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
                    arrives = ____exports.Arrives(gap, ms, away, ____exports.BARS.walkIn),
                    hitting = hitting,
                    free = free,
                    ko = free and 0 or shareOn(bot, h),
                    kt = free and 0 or shareOn(h, bot),
                    paid = hitting and CreepAggro.Paid(bot, h),
                    tw = tw
                }
                local asked = thp <= ____exports.BARS.commitHp or pair ~= nil and pair.tgt == pid or play ~= nil and play.tgt == pid or isRun
                if asked then
                    local r = walkOf(here, at)
                    c.walk = {burst = r.burst, n = #r.reach, missing = r.missing}
                end
                if thp <= ____exports.BARS.commitHp or isRun and rs.level == "kill" then
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
                __continue160 = true
            until true
            if not __continue160 then
                break
            end
        end
    end
    local i = {
        now = now,
        hp = frac(bot),
        burst = stay.burst,
        n = #stay.reach,
        missing = stay.missing,
        towerOnMe = towerOnMe,
        creepsOnMe = creepsOnMe,
        wave = wave,
        denyDue = Laning.DenyDue(bot),
        pair = pair,
        play = play,
        cands = cands
    }
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
    local ____temp_22
    if b == nil then
        ____temp_22 = nil
    else
        ____temp_22 = b and 1 or 0
    end
    return ____temp_22
end
local function ____or(v)
    return v == nil and "-" or v
end
local function candText(c)
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
            c.arrives and 1 or 0,
            c.hitting and 1 or 0,
            c.free and 1 or 0,
            round6(c.ko),
            round6(c.kt),
            c.paid and 1 or 0,
            c.tw and 1 or 0,
            ____or(w ~= nil and round6(w.burst) or nil),
            ____or(w and w.n),
            ____or(w ~= nil and round6(w.missing) or nil),
            ____or(bit(k and k.ok)),
            ____or(k ~= nil and math.floor(k.dmg + 0.5) or nil),
            ____or(k ~= nil and round6(k.safe) or nil)
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
    local ____array_29 = __TS__SparseArrayNew(
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
    local ____opt_27 = r.catch
    __TS__SparseArrayPush(
        ____array_29,
        ____or(bit(____opt_27 and ____opt_27.ok))
    )
    return table.concat(
        {__TS__SparseArraySpread(____array_29)},
        ":"
    )
end
local function howText(h)
    if h == nil then
        return nil
    end
    return h.at ~= nil and (((((h.verb .. ":") .. h.aggro) .. "@") .. tostring(math.floor(h.at.x))) .. ",") .. tostring(math.floor(h.at.y)) or (h.verb .. ":") .. h.aggro
end
--- The `ev=cut kind=trade2` line for this frame's inputs and answer, when one is due (see the cut's cadence). Not called from any
-- game path yet: the executor (step 4) calls it after Decide. Reads only.
function ____exports.Cut(bot, i, a)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or i.now > CUT_UNTIL then
        return
    end
    if #i.cands == 0 and i.run == nil then
        return
    end
    local pid = bot:GetPlayerID()
    local ____temp_30 = cutState[pid] or ({})
    cutState[pid] = ____temp_30
    local st = ____temp_30
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
        cds[#cds + 1] = candText(c)
    end
    local ____opt_31 = i.run
    local u = ____opt_31 and ____opt_31.unseen
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "trade2"},
            {"role", pos ~= nil and pos >= 4 and "support" or "core"},
            {
                "hp",
                round6(i.hp)
            },
            {
                "bu",
                round6(i.burst)
            },
            {"n", i.n},
            {
                "mi",
                round6(i.missing)
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
end
return ____exports
