dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice rune-rotation: RuneJob (Ours.RuneRotation) under the job chooser. Pos4 goes to the 6:00 power rune and its own
-- 7:00 shrine; pos5 to the 6:00 rune when no stack holds it; the chooser ranks the trip against the stack.

local dota = require("bots/ts_libs/dota/index")
local FARM, LANING = dota.BotMode.Farm, dota.BotMode.Laning
local RAD = 2

-- lane_world has no rune pick-up order; the Valve API's Action_PickUpRune(rune).
getmetatable(MakeUnit({ pid = 98, team = 3 })).__index.Action_PickUpRune = function(self, r) table.insert(ACTIONS, { pid = self.pid, kind = "PickUpRune", args = { r } }) end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function world(o)
	o = o or {}
	-- A fresh engine bundle: its task runner would carry the last world's trip over.
	package.loaded["bots/FunLib/engine/tasks"] = nil
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	local C = package.loaded["bots/FunLib/custom_loader"]
	C.Ours = { StackExecute = o.stack == true, DoubleStack = o.stack == true, RuneRotation = o.rune ~= false }
	T = o.t or 290
	CURRENT_TEAM = RAD
	H.StackJob.ResetCache()
	H.RuneJob.ResetCache()
	return H
end

local function hero(pid, pos, at)
	local u = MakeUnit({ pid = pid, team = RAD, loc = at or Vector(-6000, 6000) })
	u.pos = pos
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

local function lines(all, ev)
	local r = {}
	for _, l in ipairs(all) do if l:find("ev=" .. ev .. " ", 1, true) then table.insert(r, l) end end
	return r
end

local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local function farmDesire(H, bot)
	return H.Chooser.Gate(bot, "farm", function() return H.Chooser.FarmDesire(bot) end)()
end

-- One frame per bot: farm's GetDesire, then its Think when farm wins. Moves arrive at once.
local function frame(H, bots, dt)
	for _, bot in ipairs(bots) do
		local n0 = #ACTIONS
		if farmDesire(H, bot) > 0 then
			bot.mode = FARM
			H.Chooser.HostThink(bot, "farm", function() return H.Chooser.FarmThink(bot) end, function() return false end)()
		else
			bot.mode = LANING
		end
		for i = #ACTIONS, n0 + 1, -1 do
			local a = ACTIONS[i]
			if a.pid == bot.pid and a.kind == "MoveToLocation" then bot.loc = Vector(a.args[1].x, a.args[1].y) break end
		end
	end
	T = T + (dt or 0.1)
end

local function run(H, bots, untilT)
	return capture(function() while T < untilT do frame(H, bots) end end)
end

-- Pos4: leaves for the 6:00 rune, arrives before it, then the 7:00 shrine is its own, taken by its channel.
do
	local H = world()
	local bot = hero(4, 4)
	local out = run(H, { bot }, 359)
	local starts = lines(out, "job")
	check("pos4: one rune job started before 6:00", #starts == 1 and field(starts[1], "job") == "rune" and field(starts[1], "phase") == "start", #starts)
	check("pos4: on its trip at 5:59, the farm host holds it", H.RuneJob.Running(bot) and bot.mode == FARM)
	out = run(H, { bot }, 440)
	local trips = lines(out, "rune_job")
	local power, wisdom
	for _, l in ipairs(trips) do
		if field(l, "kind") == "power" then power = l elseif field(l, "kind") == "wisdom" then wisdom = l end
	end
	check("pos4 power: arrived before the spawn, no death", power ~= nil and tonumber(field(power, "arr")) <= 360 and field(power, "died") == "0", power)
	check("pos4 power: the empty spot ends no_target (the rune spawned at the other spot)", power ~= nil and field(power, "why"):find("no_target", 1, true) ~= nil, power)
	check("pos4 wisdom: channel done, ok, arrived before 7:00", wisdom ~= nil and field(wisdom, "res") == "ok" and tonumber(field(wisdom, "arr")) <= 420, wisdom)
	check("pos4 wisdom: at its own shrine", dist(bot.loc, Vector(-7948, 768)) <= 300, bot.loc.x .. "," .. bot.loc.y)
end

-- The shrine trip marks the shrine as taken for OHA's own wisdom logic while it runs.
do
	local H = world({ t = 395 })
	local bot = hero(4, 4)
	local taken = false
	capture(function()
		while T < 425 do
			frame(H, { bot })
			if H.RuneJob.Running(bot) and H.RuneJob.ShrineTaken(RAD) then taken = true end
		end
	end)
	check("shrine taken while the pos4's trip runs", taken)
	check("shrine free once it ended", not H.RuneJob.Running(bot) and not H.RuneJob.ShrineTaken(RAD))
end

-- Ranking: pos4's pending rune claim holds its stack back; pos5's stack holds its rune back.
do
	local H = world({ stack = true, t = 316 })
	local p4 = hero(4, 4)
	local seen
	H.StackJob.Applies = function() return true end
	H.StackJob.Pending = function() return true end
	H.StackJob.Wants = function(bot, blocked) seen = blocked(bot) return false end
	capture(function() frame(H, { p4 }) end)
	check("pos4 at 5:16, before its leave time: the stack sees the rune's claim", seen == "rune", seen)

	H = world({ stack = true, t = 300 })
	local p5 = hero(5, 5)
	H.StackJob.Applies = function() return true end
	H.StackJob.Pending = function() return T < 366 end
	H.StackJob.Wants = function() return false end
	local out = run(H, { p5 }, 370)
	local skip = lines(out, "rune_job")[1]
	check("pos5: no rune trip while its stack claims the minute", not H.RuneJob.Running(p5) and #lines(out, "job") == 0)
	check("pos5: one skip line naming the stack", skip ~= nil and field(skip, "res") == "skip" and field(skip, "why") == "stack", skip)
end

-- Pos5 with no stack takes the power spot the pos4's trip does not have.
do
	local H = world()
	local p4 = hero(4, 4, Vector(-9000, 6000))
	local p5 = hero(5, 5, Vector(-9000, 6000))
	local out = run(H, { p4, p5 }, 362)
	local side = {}
	for _, l in ipairs(lines(out, "rune_job")) do side[field(l, "pid")] = l end
	check("pos4 and pos5 both went", (H.RuneJob.Running(p4) or side["4"] ~= nil) and (H.RuneJob.Running(p5) or side["5"] ~= nil))
	local a, b = p4.loc, p5.loc
	check("pos4 and pos5 wait at different spots", dist(a, b) > 500, string.format("%d,%d vs %d,%d", a.x, a.y, b.x, b.y))
	check("pos4 at the spot nearer it", math.abs(a.x - -9000) < 200, a.x)
end

-- The chooser's start checks: an enemy hero in reach past the leave time skips the trip with its reason.
do
	local H = world()
	local bot = hero(4, 4)
	MakeUnit({ pid = 7, team = 3, loc = Vector(-6100, 6000) })
	local out = run(H, { bot }, 370)
	local l = lines(out, "rune_job")[1]
	check("enemy near: no trip, skip why=enemy-near", #lines(out, "job") == 0 and l ~= nil and field(l, "res") == "skip" and field(l, "why") == "enemy-near", l)
end

-- Switch off: no rune job, no line, and the stack ranks alone.
do
	local H = world({ rune = false })
	local bot = hero(4, 4)
	local out = run(H, { bot }, 425)
	check("switch off: no rune line, no rune job", #lines(out, "rune_job") == 0 and #lines(out, "job") == 0 and H.RuneJob.Priority(bot) == nil)
end

-- Positions 1-3 never get a trip.
do
	local H = world()
	local bot = hero(2, 2)
	local out = run(H, { bot }, 425)
	check("pos2: no rune line", #lines(out, "rune_job") == 0)
end

finish()
