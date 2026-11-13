-- Driver: LaneSpot.Compute (and the Threat.Read it makes) on a world cut from a game (ev=cut kind=spot, tools/hlog/cut.js),
-- real map coordinates and lane paths. The world and its API answers: cut_world.lua.
-- world: as cut_world.lua, plus role, lane, front {x, y, bx, by}, fed (creep id in ca), hold {x, y}.
-- Observation: stand(<why>) the limit that placed the spot (pref, hero, creep, hp, tower, xp), anchor(<anchor>),
-- read(<verdict>) the read at the preferred point (none, burst, missing, threat); fact.x, fact.y, fact.pushed,
-- fact.burst, fact.threat, fact.missing (the read at the chosen spot), fact.reads.
local cutWorld = dofile(HARNESS_DIR .. "/fixture_drivers/cut_world.lua")

return function(fx)
	local w = fx.world
	local cw = cutWorld(w)
	local LaneSpot = require("bots/FunLib/humaniser/states/lane_spot")
	function GetLaneFrontLocation(_, _, d) return d == 0 and Vector(w.front.x, w.front.y) or Vector(w.front.bx, w.front.by) end

	local fed = w.fed ~= nil and cw.byCreep[w.fed] or nil
	local hold = w.hold ~= nil and Vector(w.hold.x, w.hold.y) or nil
	local info = LaneSpot.Compute(cw.bot, w.role, fed, hold)
	if info == nil then return { actions = { { verb = "stand", target = "none" } } } end
	return {
		actions = { { verb = "stand", target = info.why }, { verb = "anchor", target = info.anchor }, { verb = "read", target = info.rp or "off" } },
		fact = { x = info.spot.x, y = info.spot.y, pushed = info.pushed, burst = info.rb, threat = info.rt, missing = info.rm, reads = info.rn },
	}
end
