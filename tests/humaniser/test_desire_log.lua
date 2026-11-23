dofile(HARNESS_DIR .. "/lane_world.lua")
-- The desire log (desire_log.ts): Chooser.Gate notes what each mode's own GetDesire returned, and the snapshot's `by` and
-- `competing` read it back; a mode whose code was not asked just now reads as Valve's.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local function world()
	local H = LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000), level = 3 })
	bot.lane, bot.pos, bot.mode = Lane.Bot, 1, BotMode.Laning
	return H, bot, require("bots/FunLib/humaniser/desire_log")
end

do
	local H, bot, D = world()
	local laning = H.Chooser.Gate(bot, "laning", function() return 0.446 end)
	local farm = H.Chooser.Gate(bot, "farm", function() return 0.62 end)
	local attack = H.Chooser.Gate(bot, "attack", function() return nil end)
	check("the gate returns the mode's own desire", laning() == 0.446 and farm() == 0.62 and attack() == nil)
	check("the active mode's desire, by raw", D.Explain(bot, BotMode.Laning) == "laning 0.45 by raw", D.Explain(bot, BotMode.Laning))
	check("a mode that returned nil is Valve's", D.Explain(bot, BotMode.Attack) == "attack (valve)", D.Explain(bot, BotMode.Attack))
	check("competing lists the fresh desires, highest first", D.Competing(bot) == "farm=0.62 laning=0.45", D.Competing(bot))
	T = T + 1
	check("a desire not asked for half a second is Valve's again", D.Explain(bot, BotMode.Laning) == "laning (valve)", D.Explain(bot, BotMode.Laning))
	check("and no longer competes", D.Competing(bot) == "", D.Competing(bot))
end

finish()
