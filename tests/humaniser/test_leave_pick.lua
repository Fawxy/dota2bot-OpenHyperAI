dofile(HARNESS_DIR .. "/lane_world.lua")
-- The priced leave wired into the retreat (decision centre pilot step 2 part B; master docs/proposals/decision-centre/step2-3-decider.md
-- s6, s7 cases 5 and 6, and the direction log: lethal stays a hard leave). Worlds as test_retreat: the Radiant bot lane, HP 600 unless set.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local HERE = Vector(0, -5000)

local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true }, retreat = true })
	T = o.t or 300
	CURRENT_TEAM, OBSERVER = 2, 1
	FOGGED = function() return false end
	H.Retreat.ResetCache()
	require("bots/FunLib/humaniser/threat").ResetCache()
	local bot = MakeUnit({ pid = 1, team = 2, loc = o.loc or HERE, level = 3 })
	bot.lane, bot.pos, bot.maxhp, bot.hp = Lane.Bot, 1, 600, o.hp or 600
	local ours = package.loaded["bots/FunLib/custom_loader"].Ours
	ours.PricedLeave = o.priced ~= false
	ours.PricedLeaveAct = o.act == true
	require("bots/FunLib/humaniser/states/trade").Holds = function() return nil end
	-- The stub's estimated damage ignores the window, so step 1's burst-now read (test_commit) is set here: none unless `o.burst`.
	require("bots/FunLib/humaniser/commit").BurstNow = function() return { by = { [10] = { spell = o.burst or 0, attack = 0 } }, sum = o.burst or 0 } end
	return H, bot
end

local function enemy(pid, loc, est)
	local e = MakeUnit({ pid = pid, team = 3, loc = loc })
	e.maxhp, e.hp, e.range, e.estDamage = 600, 600, 150, est or 0
	return e
end

-- Our exchange on `t` (the scope's first case).
local function exchange(t)
	local Tr = require("bots/FunLib/humaniser/states/trade")
	Tr.Running = function(u) return t ~= nil and u.pid == 1 end
	Tr.EpisodeOf = function(pid) if t ~= nil and pid == 1 then return { kind = "hit", tpid = t.pid, target = t, at = 0 } end end
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function only(all, ev, ph)
	local r = {}
	for _, l in ipairs(all) do
		if l:find("ev=" .. ev .. " ", 1, true) and (ph == nil or l:find(" ph=" .. ph .. " ", 1, true)) then r[#r + 1] = l end
	end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end
local function running(bot) return require("bots/FunLib/humaniser/retreat_state").Running(bot) end
local function leaveNow(bot) return require("bots/FunLib/humaniser/retreat_state").LeaveNow(bot) end
-- The retreat's own lines (not ph=read), for the switch-off comparison.
local function retreatLines(all)
	local r = {}
	for _, l in ipairs(all) do
		if l:find("ev=retreat ", 1, true) then r[#r + 1] = (l:gsub("^.-ev=", "ev=")) end
	end
	return table.concat(r, "\n")
end

-- A lone poke (s7 case 2's shape): one hero hitting us, kill line 583 over 600 HP (ratio 1.03, `threat`), target full, our tower 2,800
-- back. Stay about 0, leave about -40 (the walk), d about 40 over M 30 with the leave rule's leave as incumbent: stay.
local function lone(o)
	local H, bot = world(o)
	local e = enemy(10, Vector(300, -5000), 583)
	e.target = bot
	bot.hitBy = { [e] = math.huge }
	if o.scope ~= false then exchange(e) else exchange(nil) end
	return H, bot, e
end

-- Two committed (s7 case 3's shape): two heroes hitting us at 30% HP, kill line 150 over 180 (ratio 1.2, `threat`): leave.
local function pair(o)
	o.hp = 180
	local H, bot = world(o)
	local e1, e2 = enemy(10, Vector(300, -5000), 75), enemy(11, Vector(300, -4900), 75)
	e1.target, e2.target = bot, bot
	bot.hitBy = { [e1] = math.huge, [e2] = math.huge }
	exchange(e1)
	return H, bot
end

local function run(build, o)
	local H, bot = build(o)
	local d, now
	local out = capture(function()
		now = leaveNow(bot)
		d = H.Retreat.Desire(bot)
	end)
	return { d = d, running = running(bot), now = now, out = out, retreat = retreatLines(out), choice = only(out, "choice") }
end

-- 5. Act off is today: Desire, the episode, the arbiter's LeaveNow and every retreat line equal PricedLeave off's; the shadow logs act=0.
for _, case in ipairs({ { "lone", lone }, { "pair", pair } }) do
	local name, build = case[1], case[2]
	local today = run(build, { priced = false })
	local shadow = run(build, { act = false })
	check("5. " .. name .. ": Act off gives today's desire and episode", shadow.d == today.d and shadow.running == today.running and today.running, tostring(shadow.d) .. " " .. tostring(today.d))
	check("5. " .. name .. ": Act off, LeaveNow is false (the lag as today)", shadow.now == false and today.now == false)
	check("5. " .. name .. ": Act off, the retreat lines are today's", shadow.retreat == today.retreat, shadow.retreat .. "\n--\n" .. today.retreat)
	check("5. " .. name .. ": the shadow logs one ev=choice kind=leave act=0, today none", #shadow.choice == 1 and field(shadow.choice[1], "act") == "0" and field(shadow.choice[1], "kind") == "leave" and #today.choice == 0, shadow.choice[1])
end

-- 2 in game: the lone poke stays under Act, with no episode and a ph=stay why=priced line.
do
	local r = run(lone, { act = true })
	local c = r.choice[1]
	check("act: a lone poke in an exchange stays (no episode, desire 0)", r.d == 0 and not r.running, r.d)
	check("act: its line is pick=stay act=1 inc=leave lw=threat sc=trade", #r.choice == 1 and field(c, "pick") == "stay" and field(c, "act") == "1" and field(c, "inc") == "leave" and field(c, "lw") == "threat" and field(c, "sc") == "trade", c)
	check("act: d over the margin 30", tonumber(field(c, "d")) > 30 and tonumber(field(c, "mg")) == 30, c)
	local st = only(r.out, "retreat", "stay")
	check("act: ph=stay why=priced", #st == 1 and field(st[1], "why") == "priced", st[1])
	check("act: LeaveNow false on a stay", r.now == false)
end

-- 3 in game: two committed leave under Act, the arbiter's LeaveNow true before Desire runs (no lag), the episode starts the same frame
-- `threat`, one line for the frame.
do
	local r = run(pair, { act = true })
	local s = only(r.out, "retreat", "start")[1]
	check("act: two committed leave the same frame, LeaveNow first", r.now == true and r.running and r.d == 0.95, tostring(r.now))
	check("act: the episode is the leave rule's why (threat)", field(s, "why") == "threat", s)
	check("act: one decision for the frame (LeaveNow and Desire share it)", #r.choice == 1 and field(r.choice[1], "pick") == "leave", #r.choice)
end

-- Lethal is a hard leave: a lone hero not hitting us, kill line 640 over 600 (ratio 0.94), in an exchange, under Act: the episode starts
-- `lethal` and the line is hard=lethal with no prices.
do
	local function lethal(o)
		local H, bot = world(o)
		local e = enemy(10, Vector(300, -5000), 640)
		exchange(e)
		return H, bot
	end
	local r = run(lethal, { act = true })
	local c = r.choice[1]
	check("lethal: hard leave, the episode starts why=lethal", r.running and field(only(r.out, "retreat", "start")[1], "why") == "lethal")
	check("lethal: the line says hard=lethal pick=leave and carries no price", field(c, "hard") == "lethal" and field(c, "pick") == "leave" and field(c, "d") == nil, c)
	local LP = require("bots/FunLib/humaniser/leave_price")
	local d = LP.Decide({ hp = 90, hs = 0, thp = 10, n = 2, w = 500, ms = 300, pos = 1, cg = 500, lethal = true }, "stay")
	check("lethal: Decide leaves whatever the price", d.pick == "leave" and d.hard == "lethal" and d.stay == nil)
end

-- 1 in game: burst now (ready spells and an attack over our HP) is a hard leave even where the price stays.
do
	local r = run(lone, { act = true, burst = 700 })
	check("burst: hard leave, the episode starts why=threat", r.running and field(r.choice[1], "hard") == "burst" and field(only(r.out, "retreat", "start")[1], "why") == "threat", r.choice[1])
end

-- 6. Out of scope: no exchange, play or ally exchange: the leave rule unchanged (threat leave) and no line, Act on.
do
	local today = run(lone, { priced = false, scope = false })
	local r = run(lone, { act = true, scope = false })
	check("6. out of scope: the leave rule leaves as today", r.running and r.retreat == today.retreat and r.now == false)
	check("6. out of scope: no ev=choice line", #r.choice == 0, r.choice[1])
end

-- During an episode: a threat episode started out of scope ends `priced` once the exchange makes the lone poke a stay.
do
	local H, bot, e = lone({ act = true, scope = false })
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + 0.2
		exchange(e)
		H.Retreat.Desire(bot)
	end)
	local ends = only(out, "retreat", "end")
	check("episode: a stay pick ends a running threat episode res=priced", not running(bot) and #ends == 1 and field(ends[1], "res") == "priced", ends[1])
	-- And in shadow it does not.
	local H2, bot2, e2 = lone({ act = false, scope = false })
	capture(function()
		H2.Retreat.Desire(bot2)
		T = T + 0.2
		exchange(e2)
		H2.Retreat.Desire(bot2)
	end)
	check("episode: Act off, the episode runs on", running(bot2))
end

finish()
