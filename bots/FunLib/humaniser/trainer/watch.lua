--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local SELECT_RADIUS = 800
local DEATH_RADIUS = 1200
local DEATH_HP_FRACTION = 0.3
--- Bars go to the subject's attack target, then the creeps whose windows close soonest; the next ones are only watched.
function ____exports.SelectCreeps(subject, candidates, maxBars, maxWatched)
    local usable = {}
    for ____, c in ipairs(candidates) do
        do
            local __continue3
            repeat
                if c.prediction == nil or not c.creep:IsAlive() then
                    __continue3 = true
                    break
                end
                if GetUnitToLocationDistance(
                    subject,
                    c.creep:GetLocation()
                ) > SELECT_RADIUS then
                    __continue3 = true
                    break
                end
                usable[#usable + 1] = {creep = c.creep, close = c.prediction.startClose, order = #usable}
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    table.sort(
        usable,
        function(a, b)
            local ____temp_0
            if a.close ~= b.close then
                ____temp_0 = a.close < b.close
            else
                ____temp_0 = a.order < b.order
            end
            return ____temp_0
        end
    )
    local target = subject:GetAttackTarget()
    local ranked = {}
    for ____, u in ipairs(usable) do
        if u.creep == target then
            ranked[#ranked + 1] = u.creep
        end
    end
    for ____, u in ipairs(usable) do
        if u.creep ~= target then
            ranked[#ranked + 1] = u.creep
        end
    end
    local bars = {}
    local watched = {}
    do
        local i = 0
        while i < #ranked do
            if i < maxBars then
                bars[#bars + 1] = ranked[i + 1]
            elseif i < maxBars + maxWatched then
                watched[#watched + 1] = ranked[i + 1]
            end
            i = i + 1
        end
    end
    return {bars = bars, watched = watched}
end
local function Rose(counts, pid, before, after)
    return (after[counts][pid] or 0) > (before[counts][pid] or 0)
end
function ____exports.Attribute(creep, subjectPid, before, after, heroes, towerTargeting)
    local counter = creep.isDeny and "denies" or "lastHits"
    if Rose(counter, subjectPid, before, after) then
        return {kind = "subject"}
    end
    for ____, h in ipairs(heroes) do
        if h.ally and h.pid ~= subjectPid and Rose(counter, h.pid, before, after) then
            return {kind = "ally", name = h.name}
        end
    end
    for ____, h in ipairs(heroes) do
        if not h.ally and Rose(counter, h.pid, before, after) then
            return {kind = "enemyHero", name = h.name}
        end
    end
    return towerTargeting and ({kind = "tower"}) or ({kind = "creep"})
end
--- A creep whose handle went invalid counts as dead only if it was in reach and low enough for one hit; otherwise it left vision.
function ____exports.IsDeathLikely(lastHp, maxHp, effDmg, dist)
    return dist <= DEATH_RADIUS and lastHp <= math.max(effDmg, DEATH_HP_FRACTION * maxHp)
end
return ____exports
