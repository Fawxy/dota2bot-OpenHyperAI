dofile(HARNESS_DIR .. "/lane_world.lua")
-- `rotate` state, wisdom case (humaniser/states/rotate.ts, team slice 9): the pos 4 leaves lane in time to stand in
-- its own Shrine of Wisdom as it fills at 7:00, through the SDK's runeRun (shrine mode), hosted by the rune mode.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode
local BUNDLE = "bots/FunLib/engine/tasks"

local SHRINE = Vector(-7948.152344, 768.207825, 256)
local TOP, MID, BOT = Vector(-6000, 5000), Vector(0, 0), Vector(0, -5000)

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc, hp = o.hp })
	u.lane, u.pos, u.mode = o.lane, o.pos, BotMode.Laning
	return u
end

local function world(opts)
	opts = opts or {}
	package.loaded[BUNDLE] = nil
	local states = opts.states or { Enable = true, Shadow = true, Teams = "all", Own = { rotate = { 4 } } }
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true }, transitions = { Enable = true }, states = states })
	T = opts.T or 380
	CURRENT_TEAM = 2
	local w = { H = H }
	w.carry = hero({ pid = 1, bot = false, pos = 1, lane = Lane.Bot, loc = BOT })
	w.mid = hero({ pid = 2, pos = 2, lane = Lane.Mid, loc = MID })
	w.off = hero({ pid = 3, pos = 3, lane = Lane.Top, loc = TOP })
	w.p4 = hero({ pid = 4, pos = opts.pos or 4, lane = Lane.Top, loc = TOP })
	w.p5 = hero({ pid = 5, pos = 5, lane = Lane.Bot, loc = BOT })
	for _, u in ipairs({ w.carry, w.mid, w.off, w.p4, w.p5 }) do H.Lane.Config.SkillOf(u) end
	return w
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- One frame: the layer's ticks, then the rune mode's Think while the state's task runs (its claim wins the mode).
-- Moves go `speed * dt` towards their target.
local function frame(w, bot, dt)
	dt = dt or 0.1
	local H = w.H
	local n0 = #ACTIONS
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	local t = H.Tasks.Current(bot)
	if t ~= nil and t.name == "state:rotate" and not bot.forceMode then bot.mode = BotMode.Rune
	elseif not bot.forceMode then bot.mode = BotMode.Laning end
	if bot.mode == BotMode.Rune then H.States.Step(bot, BotMode.Rune) end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "MoveToLocation" then
			local to, d = a.args[1], dist(bot.loc, a.args[1])
			local step = 300 * dt
			if d <= step then bot.loc = Vector(to.x, to.y) else bot.loc = Vector(bot.loc.x + (to.x - bot.loc.x) * step / d, bot.loc.y + (to.y - bot.loc.y) * step / d) end
			break
		end
	end
	T = T + dt
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function events(lines, name)
	local out = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) then table.insert(out, l) end end
	return out
end

local function num(line, key) return line and tonumber(line:match(" " .. key .. "=([%-%d%.]+)")) end

-- Owned pos 4, 5,200 from the shrine at 300 speed: leaves about 4 + 20.8 s before 7:00, arrives early, takes the shrine
-- 3 s after it fills (the bar: within 15 s), then is free again.
do
	local w = world()
	local leave = w.H.States.Describe(w.p4)
	local lines = capture(function() while T < 440 do frame(w, w.p4) end end)
	local starts = events(lines, "state_start")
	local first = starts[1]
	local expectLeave = 420 - 4 - dist(TOP, SHRINE) * 1.2 / 300
	check("wisdom: trip started once", #starts == 1, #starts)
	check("wisdom: left lane within one selection (0.3 s) of the planned second", first ~= nil and num(first, "t") >= expectLeave - 1e-6 and num(first, "t") - expectLeave <= 0.35, first)
	local ev = events(lines, "wisdom")[1]
	check("wisdom: trip ended ok", ev ~= nil and ev:find("result=ok", 1, true) ~= nil, ev)
	check("wisdom: arrived before the fill", num(ev, "arrived") ~= nil and num(ev, "arrived") < 420, ev)
	local taken = num(ev, "taken")
	check("wisdom: shrine taken within 15 s of 7:00 (3 s channel)", taken ~= nil and taken >= 3 and taken <= 4, taken)
	check("wisdom: stood within 300 of the shrine", dist(w.p4.loc, SHRINE) <= 300)
	check("wisdom: state left after the trip", (w.H.States.Describe(w.p4) or ""):sub(1, 6) ~= "rotate", w.H.States.Describe(w.p4))
	check("wisdom: no second trip for the same fill", #events(lines, "state_start") == 1)
end

-- Before its leave time the pos 4 stays in lane: no state, no task.
do
	local w = world({ T = 380 })
	local lines = capture(function() while T < 390 do frame(w, w.p4) end end)
	check("early: no trip 30 s before leaving", #events(lines, "state_start") == 0 and #ACTIONS == 0)
end

-- Not the pos 4 (pos 5 in that slot): OHA's own wisdom logic is left alone.
do
	local w = world({ pos = 5 })
	w.p5.pos = 4
	local lines = capture(function() while T < 430 do frame(w, w.p4) end end)
	check("pos 5: no shrine trip", #events(lines, "wisdom") == 0 and #events(lines, "state_start") == 0)
end

-- Listed nowhere in Own: the trip is only shadowed.
do
	local w = world({ states = { Enable = true, Shadow = true, Teams = "all", Own = { stack = { 4 } } } })
	local lines = capture(function() while T < 430 do frame(w, w.p4) end end)
	check("unowned: shadow rotate chosen", #events(lines, "state") > 0 and lines[1] ~= nil)
	check("unowned: no task, no moves", #events(lines, "state_start") == 0 and #ActionsOf(4, "MoveToLocation") == 0)
end

-- Enemies outnumber the pos 4 on the way: the guard ends the trip and it is not retried for this fill.
do
	local w = world()
	local lines = capture(function()
		while T < 405 do frame(w, w.p4) end
		-- GetNearbyHeroes counts the bot itself among its allies, as the rune mode's own outnumbered gate does.
		hero({ pid = 10, team = 3, pos = 3, lane = Lane.Top, loc = Vector(w.p4.loc.x + 300, w.p4.loc.y) })
		hero({ pid = 11, team = 3, pos = 4, lane = Lane.Top, loc = Vector(w.p4.loc.x + 350, w.p4.loc.y) })
		while T < 440 do frame(w, w.p4) end
	end)
	local ev = events(lines, "wisdom")[1]
	check("danger: trip abandoned as outnumbered", ev ~= nil and ev:find("reason=outnumbered", 1, true) ~= nil, ev)
	check("danger: not retried", #events(lines, "state_start") == 1)
end

-- While the pos 4 is on its trip the shrine is taken for the team (OHA's wisdom logic skips it for everyone).
do
	local w = world()
	local during, before
	capture(function()
		before = w.H.States.WisdomOwned(w.off)
		while T < 410 do frame(w, w.p4) end
		during = w.H.States.WisdomOwned(w.off)
	end)
	check("claim: free before the trip", before == false)
	check("claim: taken during it, for teammates too", during == true and w.H.States.WisdomOwned(w.p4) == true)
end

-- Kept out of the rune mode (a long retreat) past the fill's window: the trip is closed unfinished and the state leaves.
do
	local w = world()
	local lines = capture(function()
		while T < 400 do frame(w, w.p4) end
		w.p4.forceMode = true
		w.p4.mode = BotMode.Retreat
		while T < 445 do frame(w, w.p4) end
	end)
	local ev = events(lines, "wisdom")[1]
	check("preempt: closed unfinished, once", ev ~= nil and ev:find("result=fail", 1, true) ~= nil and #events(lines, "wisdom") == 1, ev)
	check("preempt: no channel happened", #events(lines, "wisdom") == 1 and ev:find("taken=", 1, true) == nil, ev)
	check("preempt: state left", (w.H.States.Describe(w.p4) or ""):sub(1, 6) ~= "rotate", w.H.States.Describe(w.p4))
end

-- Dying on the way closes the trip at once: the shrine is free for the team's own wisdom logic again.
do
	local w = world()
	local lines = capture(function()
		while T < 405 do frame(w, w.p4) end
		w.p4.alive = false
		for _ = 1, 5 do frame(w, w.p4) end
	end)
	local ev = events(lines, "wisdom")[1]
	check("death: trip closed", ev ~= nil and ev:find("result=fail", 1, true) ~= nil, ev)
	check("death: shrine free for the team", w.H.States.WisdomOwned(w.off) == false)
end

-- Power rune (States.Rotate.Power): OHA's rotation decides at ~5:35 and the body walks the pos 4 to the spot, waits for
-- the 6:00 spawn and, with our mid not coming, takes the rune once OHA's hold rule lets it (RuneHoldGrace, 3 s).
do
	local dota2 = require("bots/ts_libs/dota/index")
	local Rune = dota2.Rune
	local TOP_SPOT = Vector(-1500, 1500)
	local function spotOf(r) if r == Rune.Power1 then return TOP_SPOT end return Vector(1500, -1500) end
	local function powerWorld()
		local w = world({ T = 330, states = { Enable = true, Shadow = true, Teams = "all", Own = { rotate = { 4 } }, Rotate = { Power = true } } })
		w.p4.loc = Vector(-2000, 5000)
		w.mid.loc = Vector(3000, -3000)
		return w
	end
	local oldSpawn, oldStatus = GetRuneSpawnLocation, GetRuneStatus
	GetRuneSpawnLocation = spotOf
	local picked
	GetRuneStatus = function(r) if r == Rune.Power1 and T >= 360 and not picked then return RUNE_STATUS_AVAILABLE end return RUNE_STATUS_MISSING end
	local w = powerWorld()
	w.p4.Action_PickUpRune = function(_, r) picked = T end
	SetRandomSequence({ 0, 0.5, 0.25, 0.9 })
	local lines = capture(function()
		while T < 375 do
			w.H.Transitions.Tick(w.p4)
			frame(w, w.p4)
		end
	end)
	GetRuneSpawnLocation, GetRuneStatus = oldSpawn, oldStatus
	local ev = events(lines, "rune_trip")[1]
	check("power: rotation decided by OHA", events(lines, "tr_rotate")[1] ~= nil and events(lines, "tr_rotate")[1]:find("go=1", 1, true) ~= nil, events(lines, "tr_rotate")[1])
	check("power: body walked to the top spot", #events(lines, "state_start") >= 1 and dist(w.p4.loc, TOP_SPOT) <= 160, w.p4.loc.x .. "," .. w.p4.loc.y)
	check("power: rune left for the mid for the hold grace, then taken", picked ~= nil and picked >= 363 - 0.2 and picked <= 365, picked)
	check("power: trip logged ok", ev ~= nil and ev:find("result=ok", 1, true) ~= nil, ev)
end

-- Power off (the default): the same rotation runs on OHA's rune mode, no state body.
do
	local w = world({ T = 330 })
	w.p4.loc = Vector(-2000, 5000)
	SetRandomSequence({ 0, 0.5, 0.25, 0.9 })
	local lines = capture(function()
		while T < 345 do
			w.H.Transitions.Tick(w.p4)
			frame(w, w.p4)
		end
	end)
	check("power off: no rotate body for the power rune", #events(lines, "state_start") == 0 and #events(lines, "rune_trip") == 0)
end

finish()
