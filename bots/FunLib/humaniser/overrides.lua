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
return ____exports
