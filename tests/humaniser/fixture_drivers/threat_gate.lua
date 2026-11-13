-- Driver: Threat.Gate (the start gate of a trip: the threat read over the walk from `from` to `place`) on a world cut from a
-- game (ev=cut kind=gate, tools/hlog/cut.js), real map. The world and its API answers: cut_world.lua.
-- world: as cut_world.lua (no creeps, no tower targets, no vis), plus who, from {x, y}, place {x, y},
--        vw {n, hex} (visibility at the walk's n + 1 evenly spaced points, from `from` to `place`; absent: all visible).
-- Observation: go, or hold(threat) / hold(missing); fact.reach (heroes in reach), fact.missing (the belief's weight sum),
-- fact.mcut (unseen heroes the vision cut dropped), fact.burst, fact.allies, fact.tower (1 when the place is in a tower's reach).
local cutWorld = dofile(HARNESS_DIR .. "/fixture_drivers/cut_world.lua")

return function(fx)
	local w = fx.world
	local cw = cutWorld(w)
	local dist = cw.dist
	local from, place = Vector(w.from.x, w.from.y), Vector(w.place.x, w.place.y)
	local vw = w.vw
	-- The walk point nearest the asked one, by its share of the walk: the replay's rounded coordinates may cut the walk in another
	-- number of steps than the game's did.
	function IsLocationVisible(v)
		if vw == nil then return true end
		local d = dist(from, place)
		local i = d > 0 and math.floor(dist(from, v) / d * vw.n + 0.5) or 0
		i = math.max(0, math.min(vw.n, i))
		local nib = tonumber(vw.hex:sub(math.floor(i / 4) + 1, math.floor(i / 4) + 1), 16) or 0
		return math.floor(nib / 2 ^ (3 - i % 4)) % 2 == 1
	end

	local res = cw.Threat.Gate(cw.bot, from, place, w.who or "gate")
	local r = res.r
	return {
		actions = { res.why and { verb = "hold", target = res.why } or { verb = "go" } },
		fact = { reach = #r.reach, missing = r.missing, mcut = r.mcut, burst = r.burst, allies = r.allies, tower = r.tower and 1 or 0 },
	}
end
