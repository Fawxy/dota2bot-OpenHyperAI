-- Driver: the lane-fight kill check (LaneFight.KillCheck.Check: can the subject and its partners kill the target in the
-- burst window, and survive it?), in a lane_world world (lane_world_fixture.lua). The subject's team sees every unit.
-- world: as lane_world_fixture.lua, plus subject, target (pid) and partners (pids of allied heroes offered as helpers).
-- Observation: kill when the check passes, noKill(<reason>) when it fails; fact.margin.
dofile(HARNESS_DIR .. "/fixture_drivers/lane_world_fixture.lua")

return function(fx, skill)
	local w = fx.world
	local H, units = LaneFixtureWorld(w, skill)
	local bot = units[w.subject]
	OBSERVER = bot
	local partners = {}
	for _, pid in ipairs(w.partners or {}) do table.insert(partners, units[pid]) end
	local r = H.LaneFight.KillCheck.Check(bot, partners, units[w.target], T)
	if r == nil then return { actions = { { verb = "noKill", target = "nocheck" } } } end
	return {
		actions = { r.pass and { verb = "kill" } or { verb = "noKill", target = r.reason } },
		fact = { margin = r.margin },
	}
end
