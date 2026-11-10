dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice arbiter-shadow: the pick rule (doctrine group order, interrupts only from a strictly higher group), and the shadow's
-- log line beside Valve's active mode.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local function c(name, group, applies, running)
	return { name = name, group = group, host = name, applies = applies, running = running or false }
end
local function pick(Arb, list, prev)
	local p = Arb.Pick(list, prev)
	return p and p.name
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true } })
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local job, lane, oha = c("job", 6, true, true), c("lane", 3, false), c("oha", Arb.BASE_GROUP + 1, true)

	check("a running job is interrupted by a higher group that starts applying",
		pick(Arb, { c("retreat", 1, true), job, oha }, "job") == "retreat")
	check("a running pick is kept against a lower group that starts applying",
		pick(Arb, { job, c("probe", 7, true), oha }, "job") == "job")
	check("an equal group that starts applying does not interrupt the running pick",
		pick(Arb, { c("first", 6, true), job }, "job") == "job")
	check("a tie in one group with no previous pick takes list order",
		pick(Arb, { c("first", 6, true), job }, nil) == "first")
	check("when the running pick stops applying the highest remaining wins",
		pick(Arb, { c("lever", 4, true), c("trade", 5, true), c("job", 6, false, true), oha }, "job") == "lever")
	check("oha wins when nothing else applies", pick(Arb, { c("retreat", 1, false), lane, c("job", 6, false), oha }, "retreat") == "oha")
	local base = c("lane", Arb.BASE_GROUP, true)
	check("base lane loses to an applying group-5 candidate", pick(Arb, { base, c("lane_fight", 5, true), oha }, "lane") == "lane_fight")
	check("base lane loses to an applying group-6 candidate", pick(Arb, { base, job, oha }, "lane") == "job")
	check("base lane does not interrupt a running group-6 job", pick(Arb, { base, job, oha }, "job") == "job")
	check("base lane wins when no interrupt applies", pick(Arb, { c("retreat", 1, false), base, c("job", 6, false), oha }, "job") == "lane")
	check("a last hit under way lifts the lane to group 3 and it interrupts a running job",
		pick(Arb, { c("lane", 3, true), job, oha }, "job") == "lane")
	check("a higher group wins over a running lower one even when the lower is listed first",
		pick(Arb, { c("trade", 5, true, true), c("lane", 3, true) }, "trade") == "lane")
end

-- The shadow: a laning hero whose retreat episode runs while Valve holds it in laning disagrees; the line is logged on a
-- change of pick or mode only, and an error inside never reaches the caller.
do
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true }, retreat = true })
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000), level = 3 })
	bot.lane, bot.pos, bot.mode = Lane.Bot, 1, BotMode.Laning
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local function frame(dt)
		T = T + dt
		Arb.Shadow(bot, function() return nil end)
	end
	local ok, err = pcall(function()
		frame(0)
		frame(0.1)
		RetreatState.SetRunning(bot, true)
		frame(0.1)
		frame(0.1)
		bot.mode = BotMode.Retreat
		frame(0.1)
	end)
	print = old
	if not ok then error(err, 0) end
	local arb = {}
	for _, l in ipairs(printed) do if l:find("ev=arb ", 1, true) then arb[#arb + 1] = l end end
	check("one line per change of pick or mode, none between", #arb == 3, #arb .. "\n" .. table.concat(arb, "\n"))
	check("the lane as base logs grp=base and agrees with laning", arb[1] and arb[1]:find("grp=base", 1, true) and arb[1]:find("agree=1", 1, true), arb[1])
	check("running retreat against laning: pick retreat, disagree", arb[2] and arb[2]:find("pick=retreat", 1, true) and arb[2]:find("act=laning", 1, true) and arb[2]:find("agree=0", 1, true) and arb[2]:find("prev=lane", 1, true), arb[2])
	check("the mode following the pick: agree", arb[3] and arb[3]:find("act=retreat", 1, true) and arb[3]:find("agree=1", 1, true), arb[3])

	local Fight = require("bots/FunLib/humaniser/lane_fight")
	Fight.CurrentPhase = function() error("boom") end
	check("an error inside the shadow does not reach the caller", pcall(Arb.Shadow, bot, function() return nil end))
end
finish()
