-- Driver: retreat.LeaveWhy (the retreat's leave rule: SafeGather.At at the hero's own place, held) on a world cut from a game
-- (ev=cut kind=leave, tools/hlog/cut.js; real map coordinates). The world and its API answers: cut_world.lua; what Trade.Holds said
-- is the logged one.
-- world: as cut_world.lua (no lane or front), plus dt (1: an enemy tower damaged the bot within 0.5 s), pj (1: Trade.Holds held a
--        join), hb (1: Trade.Holds held a hit back).
-- Observation: leave(<lethal|tower|heal|threat>) or stay(<under|join|hitback>); fact.ratio and fact.kill (the answer's HP over
-- kill line, absent with nobody in reach, and kill line), fact.reach (heroes in the read), fact.hp (HP share).
local cutWorld = dofile(HARNESS_DIR .. "/fixture_drivers/cut_world.lua")

return function(fx)
	local w = fx.world
	local cw = cutWorld(w)
	local bot = cw.bot
	local Retreat = require("bots/FunLib/humaniser/retreat")
	local holds = function()
		if w.pj == 1 then return "join" end
		if w.hb == 1 then return "hitback" end
		return nil
	end
	local l = Retreat.LeaveWhy(bot, holds)
	local verb, target = "stay", l.stay
	if l.why ~= nil then verb, target = "leave", l.why end
	local r = Retreat.ReadHere(bot)
	return {
		actions = { { verb = verb, target = target } },
		fact = { ratio = l.a.kill > 0 and l.a.ratio or nil, kill = l.a.kill, reach = #r.reach, hp = bot.hp / bot.mhp },
	}
end
