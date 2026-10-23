dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function freshCustomize(overrides)
	for k in pairs(package.loaded) do
		if k:find("Customize") or k:find("humaniser") or k:find("custom_loader") then package.loaded[k] = nil end
	end
	package.preload["bots.Customize.override"] = overrides and function() return overrides end or nil
	local Customize = require("bots.Customize.general")
	package.loaded["bots/FunLib/custom_loader"] = Customize
	return Customize
end

-- No override file (the normal case): the bundled defaults stand.
local base = freshCustomize(nil)
check("no override file keeps States.Enable", base.Humaniser.States.Enable == true)

-- dotactl's dotted keys land on nested tables, creating missing ones, and leave siblings alone.
local c = freshCustomize({ ["Humaniser.States.Enable"] = false, ["Overrides.ClockOffset"] = 600, ["Scenario.LoneEnemy"] = "bot" })
check("dotted key overrides a nested default", c.Humaniser.States.Enable == false)
check("sibling keys survive", c.Humaniser.States.Shadow == true and c.Humaniser.Telemetry.Enable == true)
check("missing parent table is created", c.Scenario ~= nil and c.Scenario.LoneEnemy == "bot")

-- The phase clock follows the offset, while raw DotaTime() and the world-timed code don't.
T = 30
local Config = require("bots/FunLib/humaniser/config")
local LaneConfig = require("bots/FunLib/humaniser/lane_config")
check("Config.Now adds ClockOffset", near(Config.Now(), 630))
check("offset ends the laning phase", LaneConfig.InLaningPhase() == false)
freshCustomize(nil)
Config = require("bots/FunLib/humaniser/config")
LaneConfig = require("bots/FunLib/humaniser/lane_config")
check("no offset: still laning at 0:30", Config.Now() == 30 and LaneConfig.InLaningPhase() == true)
package.preload["bots.Customize.override"] = nil
finish()
