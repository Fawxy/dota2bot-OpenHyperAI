--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- Seconds of eta a ranged or siege creep is preferred by (more gold and XP).
____exports.RANGED_BIAS = 0.4
--- Seconds of eta a last hit is preferred over a deny by (a core never gives up its last hit to deny).
____exports.LAST_HIT_BIAS = 0.3
--- Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
-- A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
-- were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
____exports.ARRIVE_SLACK = 0.45
function ____exports.Choose(targets)
    local best
    local bestKey = math.huge
    for ____, t in ipairs(targets) do
        do
            local __continue3
            repeat
                if t.walk > 0 and t.walk + ____exports.ARRIVE_SLACK >= t.dies then
                    __continue3 = true
                    break
                end
                local key = t.eta - (t.ranged and ____exports.RANGED_BIAS or 0) - (t.kind == "lasthit" and ____exports.LAST_HIT_BIAS or 0)
                if key < bestKey then
                    bestKey = key
                    best = t
                end
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    return best
end
return ____exports
