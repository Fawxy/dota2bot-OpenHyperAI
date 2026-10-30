-- Driver: mode_team_roam_generic Think alone (no GetDesire: OHA's roam desire needs far more world than these fixtures
-- build), in the laning_mode stub world (laning_mode_world.lua). Same world fields and observations as laning_mode,
-- without desire.laning. Pins Ours.LeaveCoreCreep's team_roam cancel (slice 3), which had only a source pin.
local drive = dofile(HARNESS_DIR .. "/fixture_drivers/laning_mode.lua")

return function(fx)
	return drive(fx, { file = "bots/mode_team_roam_generic.lua", think = true })
end
