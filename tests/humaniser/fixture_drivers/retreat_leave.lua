-- Driver: retreat.LeaveWhy (the retreat's leave rule) and the Threat.Read it decides on, on a world cut from a game
-- (ev=cut kind=leave, tools/hlog/cut.js; real map coordinates). The world and its API answers: cut_world.lua; the hold timer
-- and Profile.ThreatHold are the logged ones.
-- world: as cut_world.lua (no lane or front), plus budget (the read's budget), over (seconds the read had been over it, -1 not
--        over), hold (Profile.ThreatHold), dt (1: an enemy tower damaged the bot within 0.5 s).
-- Observation: leave(<lethal|tower|heal|threat>) or stay(<under|even|hold|stand>); fact.threat, fact.burst, fact.reach, fact.eng,
-- fact.budget, fact.over, fact.hp (HP share).
local cutWorld = dofile(HARNESS_DIR .. "/fixture_drivers/cut_world.lua")

return function(fx)
	local w = fx.world
	local cw = cutWorld(w)
	local bot = cw.bot
	local Retreat = require("bots/FunLib/humaniser/retreat")
	local Profile = require("bots/FunLib/humaniser/profile")
	Profile.ThreatHold = function() return w.hold end

	local r = Retreat.ReadHere(bot)
	local st = {}
	if w.over >= 0 then st.overSince = w.t - w.over end
	local why, stay = Retreat.LeaveWhy(bot, st, r, w.budget, w.t)
	local verb, target = "stay", stay
	if why ~= nil then verb, target = "leave", why end
	return {
		actions = { { verb = verb, target = target } },
		fact = { threat = r.threat, burst = r.burst, reach = #r.reach, eng = #r.eng, budget = w.budget, over = w.over, hp = bot.hp / bot.mhp },
	}
end
