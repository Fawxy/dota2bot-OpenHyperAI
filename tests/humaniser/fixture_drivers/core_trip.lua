-- Driver: a laning core's jungle trip between waves (FarmPattern), in the farm_world.lua world: Radiant bot lane,
-- core pid 1 at the front, support pid 5, the next enemy wave `travel` s from the front.
-- world: t, pos (the core's), travel, skill, camps [{type = small|large, at = small|small2|large}], transitions (config
--        block; caution's missing-enemy probe needs it on), enemies [{pid, unseen (s), at = [x, y]}] (bot-lane enemies).
-- Observation: noTrip(<reason>) when FarmPattern.StartGate blocks, else trip(camp#idx) when FarmPattern.Desire starts
-- one (or noTrip(none) when it does not).
dofile(HARNESS_DIR .. "/farm_world.lua")
local Lane = require("bots/ts_libs/dota/index").Lane

local AT = { small = FARM_SMALL, small2 = FARM_SMALL2, large = FARM_LARGE }

return function(fx, skill)
	local w = fx.world
	local camps = {}
	for _, c in ipairs(w.camps or {}) do table.insert(camps, { c.type, AT[c.at or c.type] }) end
	local H, core = FarmWorld({ t = w.t, pos = w.pos, travel = w.travel or 10, skill = skill or 0.9, camps = camps,
		transitions = w.transitions })
	for _, e in ipairs(w.enemies or {}) do
		local loc = e.at and Vector(e.at[1], e.at[2]) or FARM_FRONT
		local u = MakeUnit({ pid = e.pid, team = 3, loc = loc })
		u.lane = Lane.Bot
		if e.unseen then
			u.hiddenFrom = setmetatable({}, { __index = function() return true end })
			LAST_SEEN[e.pid] = { location = loc, time_since_seen = e.unseen }
		end
	end
	if w.transitions then
		H.Profile.SampleDelay = function() return 0 end
		H.Transitions.Caution.Tick(core)
	end
	local gate = H.FarmPattern.StartGate(core, T)
	if gate then return { actions = { { verb = "noTrip", target = gate } } } end
	H.FarmPattern.Desire(core)
	local trip = H.FarmPattern.Current(core)
	return { actions = { trip and { verb = "trip", target = "camp#" .. trip.campIdx } or { verb = "noTrip", target = "none" } } }
end
