dofile(HARNESS_DIR .. "/lane_world.lua")
-- `gank` state (humaniser/states/gank.ts, team slice 11): a planned rotation onto an enemy core in another lane,
-- through the SDK's gank verb, hosted by roam. Stub lanes: top y = 5000, mid y = 0, bot y = -5000; lane amount from x.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode
local BUNDLE = "bots/FunLib/sdk/tasks/tasks"

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc, hp = o.hp or 100, level = o.level or 3 })
	u.lane, u.pos, u.mode = o.lane, o.pos, BotMode.Laning
	u.mana, u.maxmana = 100, 100
	return u
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

-- Radiant pos 4 (top, level 3, 2:30) with our mid (pid 2) near the enemy mid (pid 7), who sits on our half of mid.
local function world(o)
	o = o or {}
	package.loaded[BUNDLE] = nil
	local states = o.states or { Enable = true, Shadow = true, Teams = "all", Own = { gank = { 4 } } }
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, telemetry = { Enable = true }, transitions = { Enable = true }, states = states })
	T = o.t or 150
	CURRENT_TEAM = 2
	OBSERVER = 4
	local w = { H = H }
	w.carry = hero({ pid = 1, bot = false, pos = 1, lane = Lane.Bot, loc = Vector(0, -5000) })
	w.mid = hero({ pid = 2, pos = 2, lane = Lane.Mid, loc = o.midAt or Vector(-1800, 0) })
	w.off = hero({ pid = 3, pos = 3, lane = Lane.Top, loc = Vector(-4500, 5000) })
	w.p4 = hero({ pid = 4, pos = 4, lane = Lane.Top, loc = Vector(-4000, 5000), level = o.level or 3 })
	w.p5 = hero({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(0, -5000) })
	w.enemyMid = hero({ pid = 7, team = 3, pos = 2, lane = Lane.Mid, loc = o.targetAt or Vector(-1000, 0), hp = o.targetHp or 60 })
	for _, u in ipairs({ w.carry, w.mid, w.off, w.p4, w.p5 }) do H.Lane.Config.SkillOf(u) end
	w.pings = {}
	w.p4.ActionImmediate_Ping = function(_, x, y) table.insert(w.pings, { t = T, x = x, y = y }) end
	-- Settle the bot's laning state past its dwell, as in game (held at level 1 so no gank starts meanwhile).
	local start, level = T, w.p4.level
	w.p4.level = 1
	T = start - 4
	capture(function() while T < start do H.States.Tick(w.p4) H.Tasks.Tick(w.p4) T = T + 0.1 end end)
	w.p4.level = level
	T = start
	return w
end

local function moveTowards(u, to, step)
	local d = dist(u.loc, to)
	if d <= step then u.loc = Vector(to.x, to.y) else u.loc = Vector(u.loc.x + (to.x - u.loc.x) * step / d, u.loc.y + (to.y - u.loc.y) * step / d) end
end

-- One frame: the layer's ticks, then roam's Think while the gank task runs. Moves at 300/s; an attack order in 600
-- range hits for 20 a second; a hero at 0 HP dies.
local function frame(w, dt)
	dt = dt or 0.1
	local H, bot = w.H, w.p4
	local n0 = #ACTIONS
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	local t = H.Tasks.Current(bot)
	bot.mode = (t ~= nil and t.name == "state:gank") and BotMode.Roam or BotMode.Laning
	if bot.mode == BotMode.Roam then H.States.Step(bot, BotMode.Roam) end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and (a.kind == "MoveToLocation" or a.kind == "AttackUnit") then bot.order = a break end
	end
	local a = bot.order
	if a ~= nil and a.kind == "MoveToLocation" then moveTowards(bot, a.args[1], 300 * dt) end
	if a ~= nil and a.kind == "AttackUnit" and a.args[1].alive then
		local e = a.args[1]
		if dist(bot.loc, e.loc) > 600 then moveTowards(bot, e.loc, 300 * dt)
		elseif T >= (bot.nextHit or 0) then
			e.hp = e.hp - 20
			bot.nextHit = T + 1
			if e.hp <= 0 then e.alive = false end
		end
	end
	T = T + dt
end


local function events(lines, name)
	local out = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) then table.insert(out, l) end end
	return out
end

-- A low, overextended enemy mid with our mid beside it: the pos 4 goes through a flank point and gets the kill.
do
	local w = world()
	local lines = capture(function() while T < 200 and #events({}, "x") == 0 do frame(w) if not w.enemyMid.alive then break end end end)
	local starts = events(lines, "state_start")
	check("gank: started once", #starts == 1, #starts)
	check("gank: target killed", not w.enemyMid.alive)
	capture(function() for _ = 1, 5 do frame(w) end end)
	local ev = events(capture(function() frame(w) end), "gank")[1] or events(lines, "gank")[1]
	local flank = false
	for _, m in ipairs(ActionsOf(4, "MoveToLocation")) do
		if GetAmountAlongLane(Lane.Mid, m.args[1]).distance > 1000 and GetAmountAlongLane(Lane.Top, m.args[1]).distance > 1000 then flank = true end
	end
	check("gank: approached through a point off both lanes", flank)
	check("gank: pinged the target lane once, before engaging", #w.pings == 1, #w.pings)
end

-- The kill is logged on the gank line, with how long the pos 4 was away.
do
	local w = world()
	local lines = capture(function() while T < 220 do frame(w) end end)
	local ev = events(lines, "gank")[1]
	check("gank line: ok kill", ev ~= nil and ev:find("result=ok", 1, true) ~= nil and ev:find("msg=kill", 1, true) ~= nil, ev)
	local away = ev and tonumber(ev:match(" away=([%d%.]+)"))
	check("gank line: back within about a wave (away <= 40 s)", away ~= nil and away <= 40, away)
	check("gank: no second attempt inside the cooldown", #events(lines, "state_start") == 1)
end

-- Target at full HP under its tower, nobody of ours near: no gank.
do
	local w = world({ targetHp = 100, midAt = Vector(-5000, -2000) })
	TOWERS_W[3] = { [1] = { loc = Vector(-1000, 300), alive = true } }
	local lines = capture(function() while T < 170 do frame(w) end end)
	check("no target: no gank", #events(lines, "state_start") == 0)
end

-- Level 1 pos 4 at 2:30: the level window keeps it in lane.
do
	local w = world({ level = 1 })
	local lines = capture(function() while T < 170 do frame(w) end end)
	check("level 1: no gank", #events(lines, "state_start") == 0)
end

-- Commit quality scales with skill. A full-HP target on its own half with our mid beside it scores 1.0: a skill-0
-- pos 4 (threshold 1.0) takes it, walking straight in and pinging nothing; a high-skill one (1.8) waits.
local function always(w) require("bots/FunLib/humaniser/states/gank").SETTINGS.Commit = { 1, 1 } end
local function flanked()
	for _, m in ipairs(ActionsOf(4, "MoveToLocation")) do
		if GetAmountAlongLane(Lane.Mid, m.args[1]).distance > 1000 and GetAmountAlongLane(Lane.Top, m.args[1]).distance > 1000 then return true end
	end
	return false
end
do
	local w = world({ skill = 0, targetHp = 100, targetAt = Vector(100, 1000), midAt = Vector(-500, 0) })
	always(w)
	local lines = capture(function() while T < 200 do frame(w) end end)
	check("low skill: takes the 1.0 target", #events(lines, "state_start") >= 1)
	check("low skill: straight approach, no flank point", not flanked())
	check("low skill: no ping", #w.pings == 0)
end
do
	local w = world({ skill = 1, targetHp = 100, targetAt = Vector(100, 1000), midAt = Vector(-500, 0) })
	always(w)
	local lines = capture(function() while T < 200 do frame(w) end end)
	check("high skill: waits for a better target", #events(lines, "state_start") == 0)
end

-- Not owned (gank not in Own): the state never starts.
do
	local w = world({ states = { Enable = true, Shadow = true, Teams = "all", Own = { stack = { 4 } } } })
	local lines = capture(function() while T < 170 do frame(w) end end)
	check("unowned: no gank", #events(lines, "state_start") == 0)
end

-- The pos 4 drops below 40% HP on the way: the gank is abandoned (low-hp).
do
	local w = world({ targetAt = Vector(-500, 0) })
	local lines = capture(function()
		while T < 155 do frame(w) end
		w.p4.hp = 30
		while T < 165 do frame(w) end
	end)
	local ev = events(lines, "gank")[1]
	local started = #events(lines, "state_start") > 0
	check("low hp: started", started)
	check("low hp: abandoned", ev ~= nil and ev:find("msg=low-hp", 1, true) ~= nil, ev)
end

finish()
