-- Driver: the retreat desire hook (H3) after the Transitions caution tick, in a lane_world world (lane_world_fixture.lua).
-- world: as lane_world_fixture.lua, plus subject (pid judged) and retreatBase (OHA's retreat desire before claims,
--        e.g. 0.75-0.9 for laning-phase creep aggro).
-- Caution ticks at t and t + 0.6 (past its notice delay). Observation: desire.retreat = Intent.Resolve(subject, Retreat,
-- retreatBase); fact.base = retreatBase; fact.caution = the caution level.
dofile(HARNESS_DIR .. "/fixture_drivers/lane_world_fixture.lua")
local BotMode = require("bots/ts_libs/dota/index").BotMode

return function(fx, skill)
	local w = fx.world
	local H, units = LaneFixtureWorld(w, skill)
	local bot = units[w.subject]
	local t0 = T
	H.Transitions.Caution.Tick(bot)
	T = t0 + 0.6
	H.Transitions.Caution.Tick(bot)
	return {
		desire = { retreat = H.Intent.Resolve(bot, BotMode.Retreat, w.retreatBase) },
		fact = { base = w.retreatBase, caution = H.Transitions.Caution.Level(bot) },
	}
end
