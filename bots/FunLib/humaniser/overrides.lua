--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
function ____exports.Get(key)
    local ____opt_0 = Customize.Overrides
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0[key]
    end
    return ____opt_0
end
--- Overrides.LaneOnly (slice lane-last-hits, scenario games only): every bot stays in laning mode through the laning phase
-- and does nothing in it but hold its spot, last-hit and deny: no techniques, harass, trades, spells or items. A check
-- harness for the last-hit model (many attempts per game, no trade or retreat deaths), not a behaviour.
function ____exports.LaneOnly()
    return ____exports.Get("LaneOnly") == true
end
--- Overrides.CampForce (slice core-next-gold, harness games only): an owned core's camp trip starts whenever an open camp is
-- in reach, without the decision's gates (creeps at the core, the gap to the clash, the return deadline, the least net). The
-- safety gates stay. A harness for the trip's execution (walk, clear, chain, walk back, its ends and deaths), not a behaviour.
function ____exports.CampForce()
    return ____exports.Get("CampForce") == true
end
return ____exports
