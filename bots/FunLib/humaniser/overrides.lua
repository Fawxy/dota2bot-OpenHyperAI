--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
--- An explicit override, else the value the active drill implies (`Drill.TABLE` entry `overrides`), else the default. An
-- empty string is general.lua's unset default for a string knob (`ForceShove = ""`), so it never shadows a drill's value
-- (drill shove ldr4: no shove swing ran under the implied `r:bot`).
function ____exports.Get(key)
    local ____opt_0 = Customize.Overrides
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0[key]
    end
    local v = ____opt_0
    if v ~= nil and v ~= "" then
        return v
    end
    local implied = Drill.Implied(key)
    local ____temp_2
    if implied ~= nil then
        ____temp_2 = implied
    else
        ____temp_2 = v
    end
    return ____temp_2
end
--- Lane-only (a drill's `castLaneOnly` or `others: "laneonly"`; the old Overrides.LaneOnly is drill `lane-only`): the bot
-- stays in laning mode through the laning phase and does nothing in it but hold its spot, last-hit and deny: no
-- techniques, harass, trades, spells or items. A harness, not a behaviour. Per hero: a drill's bench and statues are not.
function ____exports.LaneOnly(bot)
    return Drill.LaneOnly(bot)
end
--- Overrides.CampForce (slice core-next-gold, harness games only): an owned core's camp trip starts whenever an open camp is
-- in reach, without the decision's gates (creeps at the core, the gap to the clash, the return deadline, the least net). The
-- safety gates stay. A harness for the trip's execution (walk, clear, chain, walk back, its ends and deaths), not a behaviour.
function ____exports.CampForce()
    return ____exports.Get("CampForce") == true
end
--- Overrides.AdmitLog (slice core-next-gold, drills only): the camp trip's price check at the camp (`admits`) judges both its
-- halves by the real rule, logs its verdict as `phase=admit` and refuses nobody, so what a refusal would have saved or cost
-- is observed (refusal precision). Baked into the arm's `Customize/general.lua` for a remote drill.
function ____exports.AdmitLog()
    return ____exports.Get("AdmitLog") == true
end
return ____exports
