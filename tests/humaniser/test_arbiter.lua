dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice arbiter-shadow: the pick rule (the lowest doctrine group that applies; a tie keeps the previous pick), and the shadow's
-- log line beside Valve's active mode.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local function c(name, group, applies)
	return { name = name, group = group, host = name, applies = applies }
end
local function pick(Arb, list, prev)
	local p = Arb.Pick(list, prev)
	return p and p.name
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true } })
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local job, lane, oha = c("job", 6, true), c("lane", 3, false), c("oha", Arb.BASE_GROUP + 1, true)

	check("a running job is interrupted by a higher group that starts applying",
		pick(Arb, { c("retreat", 1, true), job, oha }, "job") == "retreat")
	check("an equal group that starts applying does not interrupt the running pick",
		pick(Arb, { c("first", 6, true), job }, "job") == "job")
	check("a tie in one group with no previous pick takes list order",
		pick(Arb, { c("first", 6, true), job }, nil) == "first")
	check("when the running pick stops applying the highest remaining wins",
		pick(Arb, { c("lever", 4, true), c("trade", 5, true), c("job", 6, false), oha }, "job") == "lever")
	check("oha wins when nothing else applies", pick(Arb, { c("retreat", 1, false), lane, c("job", 6, false), oha }, "retreat") == "oha")
	local base = c("lane", Arb.BASE_GROUP, true)
	check("base lane loses to an applying group-5 candidate", pick(Arb, { base, c("lane_fight", 5, true), oha }, "lane") == "lane_fight")
	check("base lane loses to an applying group-6 candidate", pick(Arb, { base, job, oha }, "lane") == "job")
	check("base lane wins when no interrupt applies", pick(Arb, { c("retreat", 1, false), base, c("job", 6, false), oha }, "job") == "lane")
	check("a last hit under way lifts the lane to group 3 and it interrupts a running job",
		pick(Arb, { c("lane", 3, true), job, oha }, "job") == "lane")
	check("a higher group wins over a running lower one even when the lower is listed first",
		pick(Arb, { c("trade", 5, true), c("lane", 3, true) }, "trade") == "lane")
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
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	check("a hero whose laning read nobody has made is OHA's", Arb.Candidates(bot, nil)[1].name == "oha")
	-- The retreat desire reads the laning phase every frame in a game; the shadow only looks at what was stored.
	local function frame(dt)
		T = T + dt
		Phase.LaningTransitions(bot)
		Arb.Shadow(bot, function() return nil end)
	end
	local ok, err = pcall(function()
		frame(0)
		frame(0.3)
		RetreatState.SetRunning(bot, true)
		frame(0.3)
		frame(0.3)
		bot.mode = BotMode.Retreat
		frame(0.3)
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
	Fight.CurrentPhase = function() return "trade" end
	local function winner(job, lever) return Arb.Pick(Arb.Candidates(bot, job, lever), nil).name end
	RetreatState.SetRunning(bot, false)
	check("a lane fight outranks a job out of lane", winner("stack", nil) == "lane_fight")
	check("the controller's pull lever lifts the running pull over a lane fight", winner("pull", "pull") == "job")
	check("a pull the controller did not ask for stays a group-6 job", winner("pull", nil) == "lane_fight")
	check("a pull lever with another job running lifts nothing", winner("stack", "pull") == "lane_fight")

	-- Activities that run outside the chooser: a core's trade (attack mode), a camp job of the older path, the mid's rune claim.
	Fight.CurrentPhase = function() return "idle" end
	local Trade = require("bots/FunLib/humaniser/states/core_trade")
	local CampJobs = require("bots/FunLib/humaniser/camp_jobs")
	local MidRunes = require("bots/FunLib/humaniser/transitions/mid_runes")
	local trading, camp, claiming = true, nil, false
	Trade.Running = function() return trading end
	CampJobs.LiveKind = function() return camp end
	MidRunes.Claiming = function() return claiming end
	local function host(job, lever) return Arb.Pick(Arb.Candidates(bot, job, lever), nil).host end
	check("an open trade is the pick and is hosted in attack", winner(nil, nil) == "trade" and host(nil, nil) == "attack")
	check("an open trade outranks a job out of lane", winner("stack", nil) == "trade")
	camp = "stack_pull"
	check("the pull lever lifts a camp-job pull over a trade", winner(nil, "pull") == "job" and host(nil, "pull") == "farm")
	camp = "stack"
	check("the pull lever does not lift a camp job that is no pull", winner(nil, "pull") == "trade")
	trading = false
	check("a camp job with no chooser job is the pick over the base lane", winner(nil, nil) == "job")
	camp, claiming = nil, true
	check("the mid's rune claim is the pick over the base lane, hosted in rune", winner(nil, nil) == "mid_rune" and host(nil, nil) == "rune")

	local threw = 0
	Fight.CurrentPhase = function() threw = threw + 1; error("boom") end
	T = T + 1
	check("an error inside the shadow does not reach the caller", pcall(Arb.Shadow, bot, function() return nil end) and threw == 1, threw)
	Arb.Shadow(bot, function() return nil end)
	check("after an error the shadow waits out its period before trying again", threw == 1, threw)
end
finish()
