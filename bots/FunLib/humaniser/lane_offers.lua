--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
-- A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
-- were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
____exports.ARRIVE_SLACK = 0.45
--- The longest walk into range counted as on offer. Check run llhchk2 (03/11/2026, 5 normal games, skill 1): attempts
-- picked in range landed 0.61 of the time, under a second's walk 0.53, one to two seconds 0.34, beyond 0.19. `judgement`.
____exports.MAX_WALK = 1
--- The reach rule: a creep in range always; one to walk to only when the walk is short and it outlives the walk and a swing.
function ____exports.Reachable(t)
    if t.walk <= 0 then
        return true
    end
    if t.walk + ____exports.ARRIVE_SLACK >= t.dies then
        return false
    end
    return t.walk <= ____exports.MAX_WALK
end
--- The engine's `laneTargets`, handed over by humaniser/tasks once the bundle is loaded; telemetry never loads the bundle itself.
local offers
function ____exports.SetOffers(fn)
    offers = fn
end
--- Reachable last hits and reachable denies on offer now. Undefined while the bundle is not loaded.
function ____exports.Options(bot)
    if offers == nil then
        return nil, nil
    end
    local lastHits = 0
    local denies = 0
    for ____, t in ipairs(offers(bot)) do
        do
            local __continue8
            repeat
                if not ____exports.Reachable(t) then
                    __continue8 = true
                    break
                end
                if t.kind == "lasthit" then
                    lastHits = lastHits + 1
                else
                    denies = denies + 1
                end
                __continue8 = true
            until true
            if not __continue8 then
                break
            end
        end
    end
    return lastHits, denies
end
return ____exports
