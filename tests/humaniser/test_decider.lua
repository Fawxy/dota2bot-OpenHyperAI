dofile(HARNESS_DIR .. "/lane_world.lua")
-- The decider in the farm host (decider.ts, plan s3 step 7): with nothing held, farm's own desire and Think pass through; a row that
-- wants the hero holds it at the hard strength and its verb replaces farm's Think until it finishes; one ev=choice kind=decider line
-- per change of what is held or of the mode Valve gave the hero; no verb step while the bot cannot act.
local dota = require("bots/ts_libs/dota/index")
local BotMode = dota.BotMode

local CAN_ACT = function() return false end -- the cannotAct check: the bot can always act

-- The runner's current task as the decider reads it (the stub rows below start none of the engine's).
local RUN = {}

local function world()
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	H.Decider.Reset()
	for k in pairs(H.Decider.ROWS) do H.Decider.ROWS[k] = nil end
	RUN.task = nil
	package.loaded["bots/FunLib/humaniser/tasks"].ForOurs.Running = function() return RUN.task end
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

-- A row that wants the hero while `on.applies`, whose begin starts its task (`on.begun` counts them) and whose verb finishes
-- on the step `on.finishAt`.
local function row(on)
	return {
		name = "test_row",
		wants = function() if on.applies then return {} end end,
		begin = function()
			on.begun = (on.begun or 0) + 1
			RUN.task = { name = "test_row" }
			return true
		end,
		step = function()
			on.steps = on.steps + 1
			if on.steps < on.finishAt then return false end
			RUN.task = nil
			return true
		end,
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
	H.Decider.Add(row(on))
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
	H.Decider.Add(row(on))
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
	H.Decider.Add(row(on))
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
	H.Decider.Add(row({ applies = true, steps = 0, finishAt = 99 }))
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
	H.Decider.Add(r)
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
	H.Decider.Add(row({ applies = true, steps = 0, finishAt = 99 }))
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
	H.Decider.Add(r)
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

do -- a row's soft may be a function, asked each round: soft then hard while it holds; the line goes out at the change; the cap follows
	local H, bot = world()
	local on = { applies = true, steps = 0, finishAt = 99, soft = true }
	local r = row(on)
	r.soft = function() return on.soft end
	H.Decider.Add(r)
	local f = farm()
	local desire = H.Decider.Host(bot, f.GetDesire)
	local soft, capSoft, hard, capHard, gone
	local lines = capture(function()
		soft = desire()
		capSoft = gate(H, bot, "team_roam", 0.7)
		on.soft = false
		hard = desire()
		capHard = gate(H, bot, "team_roam", 0.7)
		desire()
		on.applies = false
		gone = desire()
	end)
	check("a soft function answering true: the soft value, and an OHA Lua mode is capped", soft == H.Decider.SOFT and capSoft == H.Decider.CAP,
		tostring(soft) .. " " .. tostring(capSoft))
	check("the same row once the function answers false: HARD, nothing capped", hard == H.Decider.HARD and capHard == 0.7, tostring(hard) .. " " .. tostring(capHard))
	check("one line at each change of hs (soft, then hard) while the same row holds, none for an unchanged round",
		#lines == 3 and lines[1]:find("held=test_row", 1, true) and lines[1]:find("hs=soft", 1, true) and lines[2]:find("hs=hard", 1, true)
		and lines[3]:find("held=-", 1, true), table.concat(lines, " | "))
	check("control: the row no longer applying yields farm's own desire", gone == 0.4, tostring(gone))
end

-- Only the decider starts a row's task (master docs/proposals/2026-11-26-decider-owns-starts.md s3), on the engine's own runner:
-- a start replaces the hero's running task, so who starts and in what order is the decider's.
local function runnerWorld()
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true }, supportPull = true })
	H.Decider.Reset()
	for k in pairs(H.Decider.ROWS) do H.Decider.ROWS[k] = nil end
	T = 300
	local bot = MakeUnit({ pid = 4, team = 2, loc = Vector(0, 0, 0) })
	bot.mode = BotMode.Farm
	return H, bot, package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
end

local FOREVER = function() return { next = function() return { done = false } end } end

-- A row on the runner: wants the hero while `on.want` or while its task runs; its begin starts the task `name`.
local function taskRow(F, name, on)
	local r = { name = name, begun = 0, ends = {} }
	r.wants = function()
		if r.running or on.want then return { tgt = "camp:" .. name, by = 312.34 } end
	end
	r.begin = function(bot)
		r.begun = r.begun + 1
		local ok = F.Start(bot, { name = name, host = BotMode.Farm, onEnd = function(res)
			r.running = false
			r.ends[#r.ends + 1] = res
		end }, FOREVER)
		r.running = ok
		return ok
	end
	r.step = function() return not r.running end
	return r
end

do -- a higher row that wants the hero while a lower row's task runs takes it; the decider's line names the lower row
	local H, bot, F = runnerWorld()
	local hiOn, loOn = { want = false }, { want = true }
	local hi, lo = taskRow(F, "hi", hiOn), taskRow(F, "lo", loOn)
	H.Decider.Add(hi)
	H.Decider.Add(lo)
	local desire = H.Decider.Host(bot, function() return 0.4 end)
	local lines = capture(function()
		desire()
		T = T + 0.2
		hiOn.want = true
		desire()
	end)
	local cur = F.Running(bot)
	check("takeover: the higher row is begun and its task runs", hi.begun == 1 and cur ~= nil and cur.name == "hi", tostring(cur and cur.name))
	check("takeover: the lower row's task ended, replaced", #lo.ends == 1 and lo.ends[1].message == "replaced", tostring(lo.ends[1] and lo.ends[1].message))
	check("takeover: the line names the row begun, its offer and the lower row it took the hero from",
		#lines == 2 and lines[2]:find("held=hi", 1, true) and lines[2]:find("beg=hi", 1, true) and lines[2]:find("over=lo", 1, true)
		and lines[2]:find("btgt=camp:hi", 1, true) and lines[2]:find("bby=312.3", 1, true), table.concat(lines, " | "))
	check("control: the lower row's begin line names nothing taken over", lines[1] ~= nil and lines[1]:find("beg=lo", 1, true) and not lines[1]:find("over=", 1, true),
		tostring(lines[1]))
end

do -- each begin names the mode Valve had the hero in at that moment, read before the row's begin moves it (the round's and a read's offer)
	local H, bot, F = runnerWorld()
	local hiOn, loOn = { want = false }, { want = true }
	local hi, lo = taskRow(F, "hi", hiOn), taskRow(F, "lo", loOn)
	for _, r in ipairs({ hi, lo }) do
		local inner = r.begin
		r.begin = function(b)
			b.mode = BotMode.Farm -- the started task's host mode, as Valve would show it once it runs
			return inner(b)
		end
	end
	H.Decider.Add(hi)
	H.Decider.Add(lo)
	local desire = H.Decider.Host(bot, function() return 0.4 end)
	local offered
	local lines = capture(function()
		bot.mode = BotMode.Laning
		desire()
		T = T + 0.2
		hiOn.want = true
		bot.mode = BotMode.Attack
		offered = H.Decider.Offer(bot, hi)
	end)
	check("bfrom: the round's begin names the mode before it", lines[1] ~= nil and lines[1]:find("beg=lo", 1, true) and lines[1]:find("bfrom=laning", 1, true),
		table.concat(lines, " | "))
	check("bfrom: a read's offer names the mode at its own moment", offered and lines[2] ~= nil and lines[2]:find("beg=hi", 1, true)
		and lines[2]:find("bfrom=attack", 1, true), table.concat(lines, " | "))
	local quiet = capture(function()
		T = T + 0.2
		bot.mode = BotMode.Laning -- a change of `win` writes a line with no begin
		desire()
	end)
	check("bfrom: a line with no begin carries none", #quiet == 1 and not quiet[1]:find("beg=", 1, true) and not quiet[1]:find("bfrom=", 1, true),
		table.concat(quiet, " | "))
end

do -- a begun offer that names a place carries its place and the danger there (Danger.At) on the begin line; one with none carries neither
	local H, bot, F = runnerWorld()
	local placed = taskRow(F, "placed", { want = true })
	local inner = placed.wants
	placed.wants = function(b)
		local o = inner(b)
		if o then o.at, o.secs = Vector(300, -200, 0), 6.04 end
		return o
	end
	local bare = taskRow(F, "bare", { want = true })
	local e = MakeUnit({ pid = 10, team = 3, loc = Vector(500, -200, 0) })
	e.maxhp, e.hp, e.range, e.estDamage = 600, 600, 150, 120
	bot.maxhp, bot.hp = 600, 600
	H.Decider.Add(placed)
	local lines = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	local l = lines[1] or ""
	check("danger: the begin line names the place and the window", l:find("beg=placed", 1, true) and l:find("bpx=300", 1, true) and l:find("bpy=-200", 1, true)
		and l:find("bsec=6", 1, true), l)
	check("danger: the enemy by the place is a reacher, with its burst share", l:find("dn=1", 1, true) and l:find("dre=10:200:", 1, true) and l:find("dbu=0.2", 1, true), l)
	H.Decider.Reset()
	for k in pairs(H.Decider.ROWS) do H.Decider.ROWS[k] = nil end
	H.Decider.Add(bare)
	T = T + 1
	local quiet = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	check("danger: an offer with no place logs no danger", quiet[1] ~= nil and quiet[1]:find("beg=bare", 1, true) and not quiet[1]:find("bsec=", 1, true)
		and not quiet[1]:find("dn=", 1, true), tostring(quiet[1]))
end

local function placedRow(F, name)
	local row = taskRow(F, name, { want = true })
	local inner = row.wants
	row.wants = function(b)
		local o = inner(b)
		if o then o.at, o.secs = Vector(300, -200, 0), 6 end
		return o
	end
	return row
end

do -- a Danger.At that raises never blocks the begin: the task runs, and the line says the parts failed (dfail=1, no bsec)
	local H, bot, F = runnerWorld()
	local Danger = require("bots/FunLib/humaniser/danger")
	local at = Danger.At
	Danger.At = function() error("boom") end
	H.Decider.Add(placedRow(F, "placed"))
	local lines = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	Danger.At = at
	local l = lines[1] or ""
	check("danger: a failed read leaves the begin standing", F.Running(bot) ~= nil and F.Running(bot).name == "placed", l)
	check("danger: a failed read is marked, with no parts", l:find("beg=placed", 1, true) and l:find("dfail=1", 1, true) and not l:find("bsec=", 1, true), l)
end

do -- telemetry off: the danger read is not asked at all (it only feeds the line)
	local H, bot, F = runnerWorld()
	local Danger, Telemetry = require("bots/FunLib/humaniser/danger"), require("bots/FunLib/humaniser/telemetry")
	local at, on = Danger.At, Telemetry.IsEnabled
	local asked = 0
	Danger.At = function(...) asked = asked + 1; return at(...) end
	Telemetry.IsEnabled = function() return false end
	H.Decider.Add(placedRow(F, "placed"))
	H.Decider.Host(bot, function() return 0.4 end)()
	Danger.At, Telemetry.IsEnabled = at, on
	check("danger: telemetry off asks no danger read", asked == 0 and F.Running(bot) ~= nil, asked)
end

-- Ours.FightFirst (slice oha-no-start-over-fight): no row begins while Valve has the hero in attack, roam or team roam.
local function fightWorld(flag)
	local H, bot, F = runnerWorld()
	package.loaded["bots/FunLib/custom_loader"].Ours.FightFirst = flag
	local hiOn, loOn = { want = true }, { want = true }
	local hi, lo = taskRow(F, "hi", hiOn), taskRow(F, "lo", loOn)
	local asked = 0
	local loWants = lo.wants
	lo.wants = function(...) asked = asked + 1 return loWants(...) end
	H.Decider.Add(hi)
	H.Decider.Add(lo)
	return H, bot, F, hi, lo, function() return asked end
end

for _, m in ipairs({ { BotMode.Attack, "attack" }, { BotMode.Roam, "roam" }, { BotMode.TeamRoam, "team_roam" } }) do
	local mode, name = m[1], m[2]
	do -- the round: neither row begins, the next row is asked, each refusal is kept for its row and forgotten on reading
		local H, bot, F, hi, lo, asked = fightWorld(true)
		bot.mode = mode
		local desire = H.Decider.Host(bot, function() return 0.4 end)
		local v
		local lines = capture(function() v = desire() end)
		check("fight " .. name .. ": the round begins no row and yields", hi.begun == 0 and lo.begun == 0 and F.Running(bot) == nil and v == 0.4,
			hi.begun .. " " .. lo.begun .. " " .. tostring(v))
		check("fight " .. name .. ": the refused row passes the turn to the next", asked() == 1, tostring(asked()))
		check("fight " .. name .. ": each row's refusal is kept, once", H.Decider.Refusal(bot, "hi") == "fight" and H.Decider.Refusal(bot, "lo") == "fight"
			and H.Decider.Refusal(bot, "hi") == nil, "")
		local refs = 0
		for _, l in ipairs(lines) do
			if l:find("ref=", 1, true) then
				refs = refs + 1
				check("fight " .. name .. ": the refusal line names the row, target, mode and why",
					l:find("why=fight", 1, true) and l:find("bfrom=" .. name, 1, true) and l:find("btgt=camp:", 1, true) and not l:find("beg=", 1, true), l)
			end
		end
		check("fight " .. name .. ": one refusal line per row", refs == 2, table.concat(lines, " | "))
		local again = capture(function()
			T = T + 0.3
			desire()
		end)
		local more = 0
		for _, l in ipairs(again) do if l:find("ref=", 1, true) then more = more + 1 end end
		check("fight " .. name .. ": a repeated refusal writes no second line", more == 0, table.concat(again, " | "))
	end
	do -- a read's offer is refused the same way
		local H, bot, F, hi = fightWorld(true)
		bot.mode = mode
		local offered
		capture(function() offered = H.Decider.Offer(bot, hi) end)
		check("fight " .. name .. ": an offer is not begun", offered == false and hi.begun == 0 and F.Running(bot) == nil, tostring(offered))
		check("fight " .. name .. ": the offer's refusal is kept for its row", H.Decider.Refusal(bot, "hi") == "fight", "")
	end
	do -- the flag off: every begin goes
		local H, bot, F, hi = fightWorld(false)
		bot.mode = mode
		local desire = H.Decider.Host(bot, function() return 0.4 end)
		capture(function() desire() end)
		check("fight " .. name .. ", flag off: the round begins the row", hi.begun == 1 and H.Decider.Refusal(bot, "hi") == nil, tostring(hi.begun))
		local H2, bot2, _, hi2 = fightWorld(false)
		bot2.mode = mode
		local offered
		capture(function() offered = H2.Decider.Offer(bot2, hi2) end)
		check("fight " .. name .. ", flag off: an offer is begun", offered == true and hi2.begun == 1, tostring(offered))
	end
end

for _, m in ipairs({ { BotMode.Laning, "laning" }, { BotMode.Farm, "farm" } }) do
	do -- out of a fight the flag changes nothing, and a refused row begins once the fight ends
		local H, bot, F, hi = fightWorld(true)
		bot.mode = m[1]
		local desire = H.Decider.Host(bot, function() return 0.4 end)
		local v
		capture(function() v = desire() end)
		check("no fight " .. m[2] .. ": the round begins the row", hi.begun == 1 and v == H.Decider.HARD, tostring(hi.begun))
		local H2, bot2, _, hi2 = fightWorld(true)
		bot2.mode = BotMode.Attack
		local offered
		capture(function()
			H2.Decider.Offer(bot2, hi2)
			bot2.mode = m[1]
			T = T + 0.2
			offered = H2.Decider.Offer(bot2, hi2)
		end)
		check("no fight " .. m[2] .. ": an offer refused in the fight is begun after it", offered == true and hi2.begun == 1
			and H2.Decider.Refusal(bot2, "hi2") == nil and H2.Decider.Refusal(bot2, "hi") == nil, tostring(offered))
	end
end
package.loaded["bots/FunLib/custom_loader"].Ours.FightFirst = nil

do -- a lower row that wants the hero while a higher row holds it is not begun, in the round or at a read's offer
	local H, bot, F = runnerWorld()
	local hiOn, loOn = { want = true }, { want = false }
	local hi, lo = taskRow(F, "hi", hiOn), taskRow(F, "lo", loOn)
	H.Decider.Add(hi)
	H.Decider.Add(lo)
	local desire = H.Decider.Host(bot, function() return 0.4 end)
	local v, offered, afterRound, afterOffer
	capture(function()
		desire()
		hiOn.want = false
		loOn.want = true
		T = T + 0.2
		v = desire()
		afterRound = F.Running(bot)
		offered = H.Decider.Offer(bot, lo)
		afterOffer = F.Running(bot)
	end)
	check("held: the higher row was begun once by the decider and still holds", hi.begun == 1 and v == H.Decider.HARD and #hi.ends == 0,
		hi.begun .. " " .. tostring(v))
	check("held: the higher row's task is the runner's current one after the round and after the lower row's offer",
		afterRound ~= nil and afterRound.name == "hi" and afterOffer ~= nil and afterOffer.name == "hi",
		tostring(afterRound and afterRound.name) .. " " .. tostring(afterOffer and afterOffer.name))
	check("held: the lower row's begin was never called, in the round or at its offer", lo.begun == 0 and offered == false, lo.begun .. " " .. tostring(offered))
end

do -- a read's offer (the creep row's hook): begun in the same call when no row above holds the hero
	local H, bot, F = runnerWorld()
	local hi, lo = taskRow(F, "hi", { want = false }), taskRow(F, "lo", { want = true })
	H.Decider.Add(hi)
	H.Decider.Add(lo)
	local offered
	local lines = capture(function() offered = H.Decider.Offer(bot, lo) end)
	local cur = F.Running(bot)
	check("offer: nothing above holds, so the row is begun in the call", offered == true and lo.begun == 1 and cur ~= nil and cur.name == "lo",
		tostring(offered) .. " " .. tostring(cur and cur.name))
	check("offer: the decider's line goes out at the begin, naming the row", #lines == 1 and lines[1]:find("held=lo", 1, true) and lines[1]:find("beg=lo", 1, true),
		table.concat(lines, " | "))
	local unregistered = taskRow(F, "other", { want = true })
	check("offer: a row the decider does not hold in its rows is not begun", H.Decider.Offer(bot, unregistered) == false and unregistered.begun == 0)
end

do -- a row's task started anywhere but the decider's begin is refused and logged; the running task survives
	local H, bot, F = runnerWorld()
	local pull = taskRow(F, "pull", { want = true })
	H.Decider.Add(pull)
	H.Decider.Add(taskRow(F, "creep", { want = false }))
	local started, exempt
	local out = {}
	local old = print
	print = function(l) out[#out + 1] = tostring(l) end
	local ok, err = pcall(function()
		H.Decider.Host(bot, function() return 0.4 end)()
		started = F.Start(bot, { name = "creep", host = BotMode.Farm }, FOREVER)
	end)
	print = old
	if not ok then error(err, 0) end
	local cur = F.Running(bot)
	local errs = {}
	for _, l in ipairs(out) do if l:find("ev=lua_error", 1, true) then errs[#errs + 1] = l end end
	check("outside begin: a row's start is refused", started == false)
	check("outside begin: the pull begun by the decider still runs", cur ~= nil and cur.name == "pull" and #pull.ends == 0, tostring(cur and cur.name))
	check("outside begin: one line naming the task", #errs == 1 and errs[1]:find("where=Tasks.Start", 1, true) and errs[1]:find("row task creep", 1, true),
		table.concat(errs, " | "))
	capture(function() exempt = F.Start(bot, { name = "stack", host = BotMode.Farm }, FOREVER, "StackJob.Wants") end)
	check("control: the chooser's stack (StackJob.Wants) is exempt and starts", exempt == true and F.Running(bot).name == "stack")
end

-- Claims by target and acceptance (slice oha-offer-accept, offers-and-the-decider s4 and s6): the decider takes the offer's target
-- as the hero's claim after a begin and releases it when the row's task ends; the claim and go-by checks are logged, never refuse.
do -- a begin takes the claim with the offer's data; the task's end releases it, after the row's own end could still read it
	local H, bot, F = runnerWorld()
	local C = package.loaded["bots/FunLib/humaniser/claims"]
	local on = { want = true }
	local r = taskRow(F, "lo", on)
	local base = r.wants
	r.wants = function(...)
		local o = base(...)
		if o then o.claim = { rank = 60, k = "lh", due = 301 } end
		return o
	end
	H.Decider.Add(r)
	capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	local c = C.ClaimsOn("camp:lo")[1]
	check("claim: the begin takes the target with the offer's claim", c ~= nil and c.pid == 4 and c.rank == 60 and c.k == "lh" and c.due == 301 and C.HeldBy(4) == "camp:lo",
		tostring(c and c.pid))
	local endsBefore = #r.ends
	F.Cancel(bot, "cancelled", "test")
	check("claim: the task's end releases it", #r.ends == endsBefore + 1 and C.HeldBy(4) == nil and #C.ClaimsOn("camp:lo") == 0, tostring(C.HeldBy(4)))
end

do -- the row's own end still sees the claim; the decider releases after it
	local H, bot, F = runnerWorld()
	local C = package.loaded["bots/FunLib/humaniser/claims"]
	local seen
	local r = { name = "lo", begun = 0 }
	r.wants = function() if r.running ~= false then return { tgt = "creep:9" } end end
	r.begin = function(b)
		r.running = F.Start(b, { name = "lo", host = BotMode.Farm, onEnd = function()
			r.running = false
			seen = C.HeldBy(4)
		end }, FOREVER)
		return r.running
	end
	r.step = function() return not r.running end
	H.Decider.Add(r)
	capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	F.Cancel(bot, "cancelled", "test")
	check("claim order: the row's end reads the claim, then it is gone", seen == "creep:9" and C.HeldBy(4) == nil, tostring(seen))
end

do -- a higher row begun over a lower row: the lower row's claim goes with its task, the higher row's is taken
	local H, bot, F = runnerWorld()
	local C = package.loaded["bots/FunLib/humaniser/claims"]
	local hiOn, loOn = { want = false }, { want = true }
	local hi, lo = taskRow(F, "hi", hiOn), taskRow(F, "lo", loOn)
	H.Decider.Add(hi)
	H.Decider.Add(lo)
	local desire = H.Decider.Host(bot, function() return 0.4 end)
	capture(function() desire() end)
	local first = C.HeldBy(4)
	capture(function()
		T = T + 0.2
		hiOn.want = true
		desire()
	end)
	check("claim over: the lower row's claim was taken, then the higher row's replaces it", first == "camp:lo" and C.HeldBy(4) == "camp:hi"
		and #C.ClaimsOn("camp:lo") == 0, tostring(first) .. " " .. tostring(C.HeldBy(4)))
end

do -- the claim and go-by checks are logged on the begin line and refuse nothing
	local H, bot, F = runnerWorld()
	local C = package.loaded["bots/FunLib/humaniser/claims"]
	C.Take("camp:lo", { pid = 2 })
	local r = taskRow(F, "lo", { want = true })
	H.Decider.Add(r)
	local lines = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	check("accept claim: another hero's claim is logged as would-refuse and the begin goes", r.begun == 1 and lines[1] ~= nil
		and lines[1]:find("beg=lo", 1, true) and lines[1]:find("bacc=claim", 1, true) and lines[1]:find("bcl=1", 1, true), table.concat(lines, " | "))
	check("accept claim: both heroes now hold the target", #C.ClaimsOn("camp:lo") == 2)

	H, bot, F = runnerWorld()
	C = package.loaded["bots/FunLib/humaniser/claims"]
	C.Take("creep:3", { pid = 2, rank = 70, k = "lh" })
	local lt = taskRow(F, "lo", { want = true })
	lt.wants = function() if lt.running ~= false then return { tgt = "creep:3", claim = { rank = 60, k = "lh" } } end end
	H.Decider.Add(lt)
	lines = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	check("accept claim: a claim at a higher cell than this offer's does not hold it, and is counted", lines[1] ~= nil and lines[1]:find("bcl=1", 1, true)
		and not lines[1]:find("bacc=", 1, true), table.concat(lines, " | "))

	H, bot, F = runnerWorld()
	local late = taskRow(F, "lo", { want = true })
	late.wants = function() if late.running ~= false then return { tgt = "camp:lo", by = T - 1 } end end
	H.Decider.Add(late)
	lines = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	check("accept late: a go-by already past is logged as would-refuse and the begin goes", late.begun == 1 and lines[1] ~= nil
		and lines[1]:find("bacc=late", 1, true) and not lines[1]:find("bcl=", 1, true), table.concat(lines, " | "))

	H, bot, F = runnerWorld()
	local ok = taskRow(F, "lo", { want = true })
	H.Decider.Add(ok)
	lines = capture(function() H.Decider.Host(bot, function() return 0.4 end)() end)
	check("control: an offer on time and unclaimed carries no acceptance fields", lines[1] ~= nil and lines[1]:find("beg=lo", 1, true)
		and not lines[1]:find("bacc=", 1, true) and not lines[1]:find("bcl=", 1, true), table.concat(lines, " | "))
end

do -- a begin that throws ends the decider's allowance: the row's task started afterwards outside begin is refused and logged
	local H, bot, F = runnerWorld()
	local bad = taskRow(F, "bad", { want = true })
	bad.begin = function() error("boom") end
	H.Decider.Add(bad)
	local raised, started
	local out = {}
	local old = print
	print = function(l) out[#out + 1] = tostring(l) end
	local ok, err = pcall(function()
		raised = not pcall(H.Decider.Host(bot, function() return 0.4 end))
		started = F.Start(bot, { name = "bad", host = BotMode.Farm }, FOREVER)
	end)
	print = old
	if not ok then error(err, 0) end
	local errs = {}
	for _, l in ipairs(out) do if l:find("where=Tasks.Start", 1, true) then errs[#errs + 1] = l end end
	check("throwing begin: the error reaches the caller", raised == true)
	check("throwing begin: the row's task started afterwards is refused and logged", started == false and F.Running(bot) == nil and #errs == 1
		and errs[1]:find("row task bad", 1, true), table.concat(errs, " | "))
end

finish()
