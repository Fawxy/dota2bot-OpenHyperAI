-- Driver: Lane.PreThink (the in-lane techniques step mode_laning_generic.Think runs first: block, pulls, aggro draws,
-- tower swap), in a lane_world world (lane_world_fixture.lua).
-- world: as lane_world_fixture.lua, plus subject (pid) and frames [{t, lastHit = kill|soon}] (the last-hit state the
--        laning Think hands PreThink; none = nothing to last-hit). PreThink gets every allied and enemy creep and every
--        enemy hero.
-- Observation (last frame): attack(<id>) / move actions issued that frame; fact.acted = 1 if PreThink took the frame;
-- commit(<tech>) when the lane planner is committed to a technique.
dofile(HARNESS_DIR .. "/fixture_drivers/lane_world_fixture.lua")

return function(fx, skill)
	local w = fx.world
	local H, units, creeps = LaneFixtureWorld(w, skill)
	local bot = units[w.subject]
	local allyCreeps, enemyCreeps, enemyHeroes = {}, {}, {}
	for _, c in pairs(creeps) do table.insert(c.team == bot.team and allyCreeps or enemyCreeps, c) end
	for _, u in pairs(units) do if u.team ~= bot.team then table.insert(enemyHeroes, u) end end
	local acted, from
	for _, f in ipairs(w.frames or { {} }) do
		if f.t then T = f.t end
		from = #ACTIONS
		acted = H.Lane.PreThink(bot, allyCreeps, enemyCreeps, enemyHeroes, f.lastHit)
	end
	local obs = { actions = LaneFixtureActions(bot.pid, from), fact = { acted = acted and 1 or 0 } }
	local tech = H.Lane.LanePlanner.Committed(bot)
	if tech then table.insert(obs.actions, { verb = "commit", target = tech }) end
	return obs
end
