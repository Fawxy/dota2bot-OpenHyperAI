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
	local zero, tie, farmHigh, stale, staleRival
	capture(function()
		gated(H, bot, { retreat = 0, laning = 0, team_roam = 0 })
		zero = desire()
		T = T + 0.1
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
	check("every mode at 0, retreat too: retreat does not lead, the row holds", zero == H.Decider.HARD, tostring(zero))
	check("retreat level with another mode: Valve's tie-break is not known, so the row lets go to stock", tie == 0.4, tostring(tie))
	check("farm's own value is not a rival (hidden while the row holds): retreat leading the rest lets go", farmHigh == 0.4,
		tostring(farmHigh))
	check("a retreat value (0.5) not returned this round or the last is not read, though over every fresh one: the row holds", stale == H.Decider.HARD,
		tostring(stale))
	check("a rival not asked this round or the last (roam 0.8) is not read: a fresh retreat over the fresh rest lets go",
		staleRival == 0.4, tostring(staleRival))
end

do
	local H, bot = world()
	local f = farm()
	local v
	local lines = capture(function()
		gated(H, bot, { retreat = 0.9, laning = 0.1 })
		v = H.Decider.Host(bot, f.GetDesire)()
	end)
	check("no row: a leading retreat is not a let-go; farm's own desire and a line without let", v == 0.4 and #lines == 1
		and lines[1]:find("held=-", 1, true) and not lines[1]:find("let=", 1, true), tostring(v) .. " " .. table.concat(lines, " | "))
end

do -- a soft row's first round with farm already active (OHA's farm, say): SOFT / BONUS, since Valve boosts what we return
	local H, bot = world()
	local r = row({ applies = true, steps = 0, finishAt = 99 })
	r.soft = true
	H.Decider.ROWS[1] = r
	bot.mode = BotMode.Farm
	local f = farm()
	local v
	capture(function() v = H.Decider.Host(bot, f.GetDesire)() end)
	check("a soft row's first round with farm already active returns SOFT / BONUS", v == H.Decider.SOFT / H.Decider.BONUS, tostring(v))
end

-- Plan s3, the soft hold: a row with soft=true holds at SOFT, and while it holds the gate returns OHA's Lua modes capped at
-- CAP, retreat and attack's file excepted; the retreat read still sees each value as its file returned it.
local function gate(H, bot, mode, v)
	return H.Chooser.Gate(bot, mode, function() return v end)()
end

do
	local H, bot = world()
	H.Decider.ROWS[1] = row({ applies = true, steps = 0, finishAt = 99 })
	local f = farm()
	local v, roam
	local lines = capture(function()
		v = H.Decider.Host(bot, f.GetDesire)()
		roam = gate(H, bot, "team_roam", 0.7)
	end)
	check("a hard row: nothing is capped", v == H.Decider.HARD and roam == 0.7, tostring(v) .. " " .. tostring(roam))
	bot.mode = BotMode.Farm
	local active
	capture(function() active = H.Decider.Host(bot, f.GetDesire)() end)
	check("a hard row held with farm active: still HARD, no bonus allowance", active == H.Decider.HARD, tostring(active))
	check("a hard row's line says hs=hard", #lines == 1 and lines[1]:find("hs=hard", 1, true), table.concat(lines, " | "))
end

do
	local H, bot = world()
	local on = { applies = true, steps = 0, finishAt = 99 }
	local r = row(on)
	r.soft = true
	H.Decider.ROWS[1] = r
	local f = farm()
	local desire = H.Decider.Host(bot, f.GetDesire)
	local v, got, held, let, after, gone, goneRoam
	local lines = capture(function()
		gate(H, bot, "laning", 0.45)
		v = desire()
		got = {
			team_roam = gate(H, bot, "team_roam", 0.7),
			laning = gate(H, bot, "laning", 0.43),
			laningOver = gate(H, bot, "laning", 0.446),
			retreat = gate(H, bot, "retreat", 0.3),
			attack = gate(H, bot, "attack", 0.7),
			roam = gate(H, bot, "roam", nil),
		}
		T = T + 0.1
		gate(H, bot, "team_roam", 0.8)
		gate(H, bot, "retreat", 0.6)
		bot.mode = BotMode.Farm
		held = desire()
		T = T + 0.1
		gate(H, bot, "team_roam", 0.8)
		gate(H, bot, "retreat", 0.9)
		let = desire()
		after = gate(H, bot, "team_roam", 0.8)
		T = T + 0.1
		gate(H, bot, "retreat", 0.1)
		on.applies = false
		gone = desire()
		goneRoam = gate(H, bot, "team_roam", 0.8)
	end)
	check("a soft row enters at SOFT, under 0.5 and over an active laning with Valve's bonus (0.446 x BONUS)",
		v == H.Decider.SOFT and v < 0.5 and v > 0.446 * H.Decider.BONUS, tostring(v))
	check("a capped mode with Valve's bonus stays under SOFT", H.Decider.CAP * H.Decider.BONUS < H.Decider.SOFT,
		tostring(H.Decider.CAP * H.Decider.BONUS))
	check("under a soft hold an OHA Lua mode over CAP is returned as CAP (laning's 0.446 too); one under it passes",
		got.team_roam == H.Decider.CAP and got.laningOver == H.Decider.CAP and got.laning == 0.43,
		tostring(got.team_roam) .. " " .. tostring(got.laningOver) .. " " .. tostring(got.laning))
	check("under a soft hold retreat and attack's file are not capped, and nil still falls through to Valve", got.retreat == 0.3
		and got.attack == 0.7 and got.roam == nil, tostring(got.retreat) .. " " .. tostring(got.attack) .. " " .. tostring(got.roam))
	check("the retreat read sees team roam's 0.8 as returned, not capped: retreat 0.6 under it, the soft row holds",
		held == H.Decider.SOFT / H.Decider.BONUS, tostring(held))
	check("held with farm active: SOFT / BONUS, over CAP and under 0.5 / BONUS (Valve's attack still outbids it with the bonus)",
		held > H.Decider.CAP and held * H.Decider.BONUS < 0.5, tostring(held))
	check("retreat leading the values as returned lets go, and nothing is capped once let go", let == 0.4 and after == 0.8,
		tostring(let) .. " " .. tostring(after))
	check("a soft row that no longer applies yields, uncapped", gone == 0.4 and goneRoam == 0.8, tostring(gone) .. " " .. tostring(goneRoam))
	check("the soft row's line says hs=soft", lines[1] and lines[1]:find("held=test_row", 1, true) and lines[1]:find("hs=soft", 1, true),
		table.concat(lines, " | "))
end

do -- a row whose soft is a function (the pull: hard, then soft in its stay): read each round; the line notes the change
	local H, bot = world()
	local r = row({ applies = true, steps = 0, finishAt = 99 })
	local stay = false
	r.soft = function() return stay end
	H.Decider.ROWS[1] = r
	local f = farm()
	local hard, soft, capped
	local lines = capture(function()
		hard = H.Decider.Host(bot, f.GetDesire)()
		stay = true
		soft = H.Decider.Host(bot, f.GetDesire)()
		capped = H.Decider.Cap(bot, "laning", 0.9)
	end)
	check("a soft function false holds HARD, then true holds SOFT", hard == H.Decider.HARD and soft == H.Decider.SOFT, tostring(hard) .. " " .. tostring(soft))
	check("a soft function true caps OHA's Lua modes", capped == H.Decider.CAP, tostring(capped))
	check("the line goes out again on the change, hs=hard then hs=soft", #lines == 2 and lines[1]:find("hs=hard", 1, true)
		and lines[2]:find("hs=soft", 1, true), table.concat(lines, " | "))
end

finish()
