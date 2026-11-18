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
-- End of Lua Library inline imports
local ____exports = {}
local noneReason
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
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
local function arrive(d, r, close)
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
return ____exports
