--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- Seconds of eta a ranged or siege creep is preferred by (more gold and XP).
____exports.RANGED_BIAS = 0.4
--- Seconds of eta a last hit is preferred over a deny by (a core never gives up its last hit to deny).
____exports.LAST_HIT_BIAS = 0.3
function ____exports.Choose(targets)
    local best
    local bestKey = math.huge
    for ____, t in ipairs(targets) do
        local key = t.eta - (t.ranged and ____exports.RANGED_BIAS or 0) - (t.kind == "lasthit" and ____exports.LAST_HIT_BIAS or 0)
        if key < bestKey then
            bestKey = key
            best = t
        end
    end
    return best
end
return ____exports
