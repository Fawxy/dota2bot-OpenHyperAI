--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
--- Whether to hit the hero, and if not the first reason, in the order the lane's own picks rank above it: the running episodes,
-- the creeps (pre-hit, walk-in, a due last hit or deny, the idle swing), then the costs of the hit itself (their tower, creep
-- aggro). `prime` and `attack` both draw no aggro (AggroPlan's own reading: a fresh order with no enemy creep within its clear
-- radius, or one inside the cooldown of an earlier order); `step_out` would, so the hero is not hit.
function ____exports.Answer(f)
    if f.trade then
        return "trade"
    end
    if f.leaving then
        return "retreat"
    end
    if f.pre then
        return "pre"
    end
    if f.walkIn then
        return "walk_in"
    end
    if f.due then
        return "due"
    end
    if f.idle then
        return "idle"
    end
    if f.tower then
        return "tower"
    end
    if f.aggro == "step_out" then
        return "aggro"
    end
    return "hit"
end
--- Seconds from an attack order on the hero now until our next swing can start: the cooldown left and the turn to it (the
-- last-hit engine's own `cooldownLeft`, `turnTime`) and one full attack cycle, since the hit restarts the attack clock.
function ____exports.Cycle(cooldownLeft, turn, secondsPerAttack)
    return cooldownLeft + turn + secondsPerAttack
end
--- Of laneTargets' facts (asked with `within` = the cycle), the earliest creep this laner may take (`mine`, the reach rule) whose
-- swing is due before the cycle ends and the walk to it is done: hitting the hero now would make that swing late. Undefined:
-- none, the hero hit costs no last hit or deny on offer.
function ____exports.Due(targets, mine, cycle)
    local first
    for ____, t in ipairs(targets) do
        do
            local __continue13
            repeat
                if mine ~= nil and not mine(t) then
                    __continue13 = true
                    break
                end
                if not LanePick.Reachable(t) then
                    __continue13 = true
                    break
                end
                if t.due >= cycle + t.walk then
                    __continue13 = true
                    break
                end
                if first == nil or t.due < first.due then
                    first = t
                end
                __continue13 = true
            until true
            if not __continue13 then
                break
            end
        end
    end
    return first
end
--- g's level. OHA's laning bid a mean 0.49 in the seconds Valve's attack mode won (step D2), and OHA's attack-mode entries came at
-- 0.54 or more in nine of ten (h2hohafight1, 1,213 entries to 10:00: 94% above 0.52, 86% above 0.55). 0.52 stays over the rig's
-- idle hold (drill RIG_IDLE_DESIRE 0.5) and the Valve built-in mode the arbiter's LaneDesire was set over (0.475), so a yield
-- leaves the hero to the attack mode and to nothing else. `judgement`.
____exports.YIELD_DESIRE = 0.52
--- Laning's last-hit bid (mode_laning_generic's 0.9, OWNERSHIP H2). Under the yield it follows our own read both ways: a creep the
-- pick would take bids it, so the hero comes back from whatever mode took it (lhrig1_g_s30: on OHA's read alone, creeps within 800,
-- Sniper never left the rig's idle hold after a yield and took no last hit in 17 reps).
____exports.LAST_HIT_DESIRE = 0.9
--- Whether laning yields (`yield`), or what the lane has due.
function ____exports.YieldAnswer(f)
    if f.hold then
        return "hold"
    end
    if f.walkIn then
        return "walk_in"
    end
    if f.offered then
        return "offered"
    end
    return "yield"
end
return ____exports
