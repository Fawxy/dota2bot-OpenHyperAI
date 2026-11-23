dofile(HARNESS_DIR .. "/lane_world.lua")
-- The decider in the farm host (decider.ts, plan s3 step 7): with nothing held, farm's own desire and Think pass through; a row that
-- applies holds the hero at the hard strength and its verb replaces farm's Think until it finishes; one ev=choice kind=decider line
-- per change of what is held or of the mode Valve gave the hero; no verb step while the bot cannot act.
local dota = require("bots/ts_libs/dota/index")
local BotMode = dota.BotMode

local CAN_ACT = function() return false end -- the cannotAct check: the bot can always act

local function world()
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	H.Decider.Reset()
	for k in pairs(H.Decider.ROWS) do H.Decider.ROWS[k] = nil end
	T = 300
	local bot = MakeUnit({ pid = 4, team = 2, loc = Vector(0, 0, 0) })
	bot.mode = BotMode.Laning
	return H, bot
end

-- Farm's GetDesire and Think stand-ins, counting their calls.
local function farm()
	local o = { desire = 0, think = 0 }
	o.GetDesire = function() o.desire = o.desire + 1 return 0.4 end
	o.Think = function() o.think = o.think + 1 end
	return o
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	local lines = {}
	for _, l in ipairs(printed) do if l:find("kind=decider", 1, true) then lines[#lines + 1] = l end end
	return lines
end

-- A row that applies while `on.applies` and finishes on the step `on.finishAt`.
local function row(on)
	return {
		name = "test_row",
		applies = function() return on.applies end,
		step = function() on.steps = on.steps + 1 return on.steps >= on.finishAt end,
	}
end

do
	local H, bot = world()
	local f = farm()
	local desire, think = H.Decider.Host(bot, f.GetDesire), H.Decider.HostThink(bot, f.Think, CAN_ACT)
	local v
	local lines = capture(function()
		v = desire()
		think()
		desire()
		bot.mode = BotMode.Farm
		desire()
	end)
	check("no row: farm's own desire is returned", v == 0.4, tostring(v))
	check("no row: farm's GetDesire and Think each run on every call", f.desire == 3 and f.think == 1, f.desire .. " " .. f.think)
	check("no row: a line on the first call and on the mode change only", #lines == 2, #lines .. " lines")
	check("no row: the lines say nothing held and the mode Valve gave", lines[1] and lines[1]:find("held=-", 1, true)
		and lines[1]:find("win=laning", 1, true) and lines[2] and lines[2]:find("win=farm", 1, true), table.concat(lines, " | "))
end

do
	local H, bot = world()
	local on = { applies = true, steps = 0, finishAt = 2 }
	H.Decider.ROWS[1] = row(on)
	local f = farm()
	local desire, think = H.Decider.Host(bot, f.GetDesire), H.Decider.HostThink(bot, f.Think, CAN_ACT)
	local v1, v2, v3
	local lines = capture(function()
		v1 = desire()
		think()
		think()
		think()
		on.applies = false
		v2 = desire()
		on.applies = true
		v3 = desire()
	end)
	check("a row that applies holds at the hard strength; farm's GetDesire runs only on the yield", v1 == H.Decider.HARD and f.desire == 1,
		tostring(v1) .. " farm calls " .. f.desire)
	check("the held row's verb replaces farm's Think until it finishes, then farm's Think runs", on.steps == 2 and f.think == 1,
		"steps " .. on.steps .. " farm thinks " .. f.think)
	check("a row that no longer applies yields farm's desire", v2 == 0.4, tostring(v2))
	check("held then yielded then held: three lines", #lines == 3 and lines[1]:find("held=test_row", 1, true)
		and lines[2]:find("held=-", 1, true), table.concat(lines, " | "))
	check("held again after a yield", v3 == H.Decider.HARD, tostring(v3))
end

do
	local H, bot = world()
	local on = { applies = true, steps = 0, finishAt = 5 }
	H.Decider.ROWS[1] = row(on)
	local f = farm()
	local stunned = true
	local think = H.Decider.HostThink(bot, f.Think, function() return stunned end)
	capture(function()
		H.Decider.Host(bot, f.GetDesire)()
		think()
		stunned = false
		think()
	end)
	check("a held row's verb is not stepped while the bot cannot act, nor is farm's Think", on.steps == 1 and f.think == 0,
		"steps " .. on.steps .. " farm thinks " .. f.think)
end

-- Plan s3 (user 23/11/2026): a row lets go when stock would retreat, read from the values the mode files returned through
-- Chooser's gate. `gated` sets each mode's value as its file returns it this round.
local function gated(H, bot, values)
	for mode, v in pairs(values) do H.Chooser.Gate(bot, mode, function() return v end)() end
end

do
	local H, bot = world()
	local on = { applies = true, steps = 0, finishAt = 99 }
	H.Decider.ROWS[1] = row(on)
	local f = farm()
	local desire, think = H.Decider.Host(bot, f.GetDesire), H.Decider.HostThink(bot, f.Think, CAN_ACT)
	local held, let, back
	local lines = capture(function()
		gated(H, bot, { retreat = 0.3, laning = 0.45 })
		held = desire()
		T = T + 0.1
		gated(H, bot, { retreat = 0.6, laning = 0.45 })
		let = desire()
		think()
		T = T + 0.1
		gated(H, bot, { retreat = 0.4, laning = 0.45 })
		back = desire()
	end)
	check("retreat under laning: the row holds", held == H.Decider.HARD, tostring(held))
	check("retreat leads every other mode: the decider yields farm's own desire and Think, the verb is not stepped",
		let == 0.4 and f.think == 1 and on.steps == 0, tostring(let) .. " farm thinks " .. f.think .. " steps " .. on.steps)
	check("retreat falls back under laning: the row holds again", back == H.Decider.HARD, tostring(back))
	check("the let-go line says let=retreat and the retreat value that led", #lines == 3 and lines[2]:find("held=-", 1, true)
		and lines[2]:find("let=retreat", 1, true) and lines[2]:find("d_retreat=0.6", 1, true)
		and not lines[3]:find("let=", 1, true), table.concat(lines, " | "))
end

do
	local H, bot = world()
	H.Decider.ROWS[1] = row({ applies = true, steps = 0, finishAt = 99 })
	local f = farm()
	local desire = H.Decider.Host(bot, f.GetDesire)
	local tie, farmHigh, stale, staleRival
	capture(function()
		gated(H, bot, { retreat = 0.5, team_roam = 0.5 })
		tie = desire()
		T = T + 0.1
		gated(H, bot, { retreat = 0.5, team_roam = 0.2, farm = 0.9 })
		farmHigh = desire()
		T = T + 2
		gated(H, bot, { laning = 0.1 })
		stale = desire()
		gated(H, bot, { roam = 0.8 })
		T = T + 2
		gated(H, bot, { retreat = 0.5, laning = 0.1 })
		staleRival = desire()
	end)
	check("retreat level with another mode: the row holds", tie == H.Decider.HARD, tostring(tie))
	check("farm's own value is not a rival (hidden while the row holds): retreat leading the rest lets go", farmHigh == 0.4,
		tostring(farmHigh))
	check("a retreat value (0.5) not returned this round or the last is not read, though over every fresh one: the row holds", stale == H.Decider.HARD,
		tostring(stale))
	check("a rival not asked this round or the last (roam 0.8) is not read: a fresh retreat over the fresh rest lets go",
		staleRival == 0.4, tostring(staleRival))
end

finish()
