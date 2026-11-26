dofile(HARNESS_DIR .. "/lane_world.lua")
-- The stay at the lane's camp (camp_stay.ts, Ours.CampStay): the fight read, the go, the hold, the ends and the lines, on the real
-- decider (Host/HostThink as farm's file wires them) and the engine's real runner and lastHit.
-- World: Radiant's bot-lane small camp at (-1600, -6200) (as test_pull_job); our two melee creeps at y -5900 each on a neutral
-- at y -6100/-6150; the pos5 at (-1600, -5600), range 550, so it stands 300 behind our creeps, about 90 from where it starts.

local dota = require("bots/ts_libs/dota/index")
local Lane, FARM, LANING, ATTACK = dota.Lane, dota.BotMode.Farm, dota.BotMode.Laning, dota.BotMode.Attack
local SMALL = Vector(-1600, -6200)

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function lines(all, pat) local r = {} for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(r, l) end end return r end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local function world(o)
	o = o or {}
	package.loaded["bots/FunLib/engine/tasks"] = nil
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours = { CampStay = o.on ~= false, SupportPull = false, RuneDetour = false, LaneCreeps = false, CreepDeny = false, StackExecute = false }
	CURRENT_TEAM = 2
	T = 200
	SPAWNERS = { { team = 2, type = "small", location = SMALL, min = Vector(SMALL.x - 150, SMALL.y - 150, 0),
		max = Vector(SMALL.x + 150, SMALL.y + 150, 0), speed = 0 } }
	require("bots/FunLib/humaniser/camps").ResetCache()
	H.CampRead.ResetCache()
	H.CampStay.ResetCache()
	H.Decider.Reset()
	local bot = MakeUnit({ pid = 5, team = 2, bot = true, loc = Vector(-1600, -5600), hp = 600, maxhp = 600 })
	bot.lane, bot.pos, bot.range = Lane.Bot, 5, 550
	bot.GetAttackPoint = function() return 0.3 end
	bot.mode = LANING
	local w = { H = H, bot = bot, S = H.CampStay }
	if o.creeps ~= false then
		w.c1 = MakeCreep({ team = 2, x = -1600, y = -5900 })
		w.c2 = MakeCreep({ team = 2, x = -1550, y = -5900 })
	end
	if o.neutrals ~= false then
		w.n1 = MakeNeutral({ x = -1600, y = -6100 })
		w.n2 = MakeNeutral({ x = -1650, y = -6150 })
		w.n1.dps, w.n2.dps = 20, 20
	end
	if w.c1 and w.n1 then
		w.c1.target, w.c2.target = w.n1, w.n2
		w.n1.target, w.n2.target = w.c1, w.c2
	end
	return w
end

-- One decider round and one Think, as mode_farm_generic wires them; a move order puts the hero where it was sent.
local function frame(w, dt)
	local H, bot = w.H, w.bot
	local n0 = #ACTIONS
	w.desire = H.Decider.Host(bot, function() return 0 end)()
	if w.desire > 0 then
		bot.mode = FARM
		H.Decider.HostThink(bot, function() end, function() return false end)()
	elseif bot.mode == FARM then
		bot.mode = LANING
	end
	H.Tasks.ForOurs.Tick(bot)
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "MoveToLocation" then bot.loc = Vector(a.args[1].x, a.args[1].y) break end
	end
	T = T + (dt or 0.1)
end
local function run(w, n) return capture(function() for _ = 1, n do frame(w) end end) end
local function jobs(out, phase)
	local r = {}
	for _, l in ipairs(lines(out, "job=stay ")) do if l:find("phase=" .. phase, 1, true) then table.insert(r, l) end end
	return r
end
local function ends(out) return jobs(out, "end") end

do -- off: no hold, and the fight is the shadow's one line, written as it ends
	local w = world({ on = false })
	local held
	local out = capture(function()
		held = w.H.Decider.Ask(w.bot, w.S.ROW)
		w.S.Shadow(w.bot)
		T = T + 0.1
		w.S.Shadow(w.bot)
		RemoveCreep(w.c1)
		RemoveCreep(w.c2)
		T = T + 0.1
		w.S.Shadow(w.bot)
	end)
	local ch = lines(out, "kind=stay")
	check("off: the row does not want the hero", held == false)
	check("off: one shadow line, go=0 why=off src=shadow want=1, the camp's counts", #ch == 1 and field(ch[1], "go") == "0" and field(ch[1], "why") == "off"
		and field(ch[1], "src") == "shadow" and field(ch[1], "want") == "1" and field(ch[1], "nc") == "2" and field(ch[1], "nn") == "2", table.concat(out, " | "))
end

do -- on: neutrals alone, or our creeps alone, are no stay; both are
	local a = world({ creeps = false })
	local b = world({ neutrals = false })
	check("neutrals and none of ours: not wanted", a.H.Decider.Ask(a.bot, a.S.ROW) == false)
	check("ours and no neutral: not wanted", b.H.Decider.Ask(b.bot, b.S.ROW) == false)
	local w = world()
	local out = run(w, 1)
	local ch, st = lines(out, "kind=stay"), jobs(out, "start")
	check("both: the stay begins, one go=1 line with the job's aid", #ch == 1 and field(ch[1], "go") == "1" and #st == 1 and field(ch[1], "aid") == field(st[1], "aid")
		and field(st[1], "tgt") == "camp:1", table.concat(out, " | "))
	-- A fight where nobody hits anybody is not a stay (rule 5's worth).
	local i = world()
	i.c1.target, i.c2.target, i.n1.target, i.n2.target = nil, nil, nil, nil
	check("both at the camp, neither on the other: not wanted", i.H.Decider.Ask(i.bot, i.S.ROW) == false)
end

do -- the hold: soft while standing, hard from a last-hit attempt's go to its end, soft again after
	local w = world()
	run(w, 3)
	local standing = w.desire
	w.n1.hp = 40 -- within one of the hero's hits (50): due
	local o1 = run(w, 2)
	local inAttempt = w.desire
	w.bot.lh = 1
	w.n1.hp = 0
	local o2 = run(w, 3)
	local after = w.desire
	local tries = lines(o2, "ev=stay_try")
	check("standing: the hold is soft", standing > 0 and standing < w.H.Decider.HARD, tostring(standing))
	check("in the attempt: the hold is hard", inAttempt == w.H.Decider.HARD, tostring(inAttempt) .. " " .. table.concat(o1, " | "))
	check("after it: soft again", after > 0 and after < w.H.Decider.HARD, tostring(after))
	check("the attempt's line: the neutral, landed", #tries == 1 and field(tries[1], "ok") == "1" and field(tries[1], "cid") ~= nil and field(tries[1], "k") == "lasthit", table.concat(o2, " | "))
	local soft = lines(o1, "kind=decider")
	check("the decider's line shows hs=hard in the attempt", #lines(soft, "hs=hard") >= 1, table.concat(o1, " | "))
end

do -- standing gives no hit: only moves to the spot behind our creeps
	local w = world()
	run(w, 10)
	check("no attack order while nothing is due", #ActionsOf(5, "AttackUnit") == 0, #ActionsOf(5, "AttackUnit"))
	local d = math.sqrt((w.bot.loc.x + 1600) ^ 2 + (w.bot.loc.y + 6125) ^ 2)
	check("it stands farther from the neutrals than our creeps do", d > 225 + 200, d)
end

local function endsWith(name, setup, steps)
	local w = world()
	run(w, 2)
	setup(w)
	local out = run(w, steps or 3)
	local e = ends(out)
	check("end " .. name .. ": one end line why=" .. name, #e == 1 and field(e[1], "why") == name, table.concat(out, " | "))
	return w, e[1], out
end

endsWith("creeps", function(w) RemoveCreep(w.c1) RemoveCreep(w.c2) end)
endsWith("cleared", function(w) w.n1.hp, w.n2.hp = 0, 0 end)
endsWith("danger", function() package.loaded["bots/FunLib/humaniser/safe_gather"].At = function() return { level = "deadly" } end end, 8)

do -- a neutral on the hero: it walks out towards the lane, ends `hit`, and does not take the same fight again
	local w = world()
	run(w, 2)
	w.n1.target = w.bot
	local o1 = run(w, 1)
	local walked = ActionsOf(5, "MoveToLocation")
	local to = walked[#walked].args[1]
	check("hit: it walks towards its lane", to.y == LANE_Y[Lane.Bot] and #ends(o1) == 0, table.concat(o1, " | "))
	w.n1.target = w.c1
	w.bot.loc = Vector(-1600, -5000)
	local o2 = run(w, 2)
	local e = ends(o2)
	check("hit: the stay ends why=hit once out of reach", #e == 1 and field(e[1], "why") == "hit", table.concat(o2, " | "))
	w.bot.loc = Vector(-1600, -5600)
	local o3 = run(w, 5)
	check("hit: the same fight is not taken again", #jobs(o3, "start") == 0 and w.desire == 0, table.concat(o3, " | "))
end

do -- HP under the pull's bail bar: ends `hp`, and the same fight is not taken again when HP comes back
	local w, e = endsWith("hp", function(w) w.bot.hp = 100 end)
	check("hp: the end line carries HP at start and end", field(e, "hp0") == "600" and field(e, "hp1") == "100", e)
	w.bot.hp = 600
	local o = run(w, 5)
	check("hp: not begun again for that fight", #jobs(o, "start") == 0, table.concat(o, " | "))
end

do -- the backstop: 35 s from the fight's first stay, logged as `timeout`
	local w = world()
	run(w, 2)
	local out = capture(function() while T < 200 + 36 do frame(w, 0.5) end end)
	local e = ends(out)
	check("timeout: ends why=timeout at the backstop", #e == 1 and field(e[1], "why") == "timeout" and tonumber(field(e[1], "ss")) >= 34, table.concat(e, " | "))
end

do -- a higher row begun over the stay takes the hero (over=stay); once its attempt ends the stay is begun again
	local w = world()
	local H = w.H
	local stub = { applies = false }
	stub.row = {
		name = "deny_stub",
		wants = function()
			local r = H.Tasks.ForOurs.Running(w.bot)
			if stub.applies or (r ~= nil and r.name == "deny_stub") then return { tgt = "creep:1" } end
		end,
		begin = function()
			stub.applies = false
			return H.Tasks.ForOurs.Start(w.bot, { name = "deny_stub", host = FARM }, function() return H.Tasks.ForOurs.Verbs().wait(w.bot, 0.3) end)
		end,
		step = function()
			H.Tasks.ForOurs.Step(w.bot, FARM)
			local r = H.Tasks.ForOurs.Running(w.bot)
			return r == nil or r.name ~= "deny_stub"
		end,
	}
	local rows = H.Decider.ROWS
	table.insert(rows, #rows, stub.row)
	run(w, 2)
	local out = capture(function()
		stub.applies = true
		H.Decider.Offer(w.bot, stub.row)
		for _ = 1, 8 do frame(w) end
	end)
	local over = lines(out, "beg=deny_stub")
	local e, st = ends(out), jobs(out, "start")
	check("over: the decider's line names the stay as replaced", #over == 1 and field(over[1], "over") == "stay", table.concat(out, " | "))
	check("over: the stay ended why=replaced, then was begun again with a new aid", #e == 1 and field(e[1], "why") == "replaced" and #st == 1
		and field(st[1], "aid") ~= field(e[1], "aid"), table.concat(out, " | "))
	check("over: one choice line for the fight (the second stay writes none)", #lines(out, "kind=stay") == 0, table.concat(out, " | "))
end

do -- a neutral still on the hero at the go (the puller as its pull ends): held back, then begun once it turns to our creeps
	local w = world()
	w.n1.target = w.bot
	local first = w.H.Decider.Ask(w.bot, w.S.ROW)
	w.n1.target = w.c1
	check("aggro: not begun while a neutral is on the hero; begun once it is on our creeps", first == false and w.H.Decider.Ask(w.bot, w.S.ROW) == true)
end

do -- attack has the hero: held back `busy` (a soft hold would be outbid and the stay never step)
	local w = world()
	w.bot.mode = ATTACK
	local busy = w.H.Decider.Ask(w.bot, w.S.ROW)
	w.bot.mode = LANING
	check("attack has the hero: not begun; once it lets go, begun", busy == false and w.H.Decider.Ask(w.bot, w.S.ROW) == true)
end

finish()
