dofile(HARNESS_DIR .. "/lane_world.lua")
-- `farm` state (humaniser/states/farm.ts, team slice 10): FarmPattern plans a core's between-waves camp trip, the SDK's
-- clearCamp executes it in place of FarmPattern's step(), OHA chains the next camp or walks the core back.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode
local BUNDLE = "bots/FunLib/sdk/tasks/tasks"

local FRONT = Vector(0, -5000)
local SMALL = Vector(0, -6200)
local SMALL2 = Vector(900, -6600)

local function spawner(type_, at)
	return { team = 2, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

-- The farm tests' world (Dire's wave reaches the front `travel` s after each spawn), plus the state layer.
local function world(o)
	package.loaded[BUNDLE] = nil
	local states = o.states or { Enable = true, Shadow = true, Teams = "all", Own = { farm = { 1 } } }
	local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { dire_bot = { { 325 * o.travel, -5000 }, { -7000, -5000 } } } } },
		{ skill = 0.9, telemetry = { Enable = true }, states = states })
	T = o.t
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = {}
	local camp = {}
	for i, c in ipairs(o.camps) do
		table.insert(SPAWNERS, spawner(c[1], c[2]))
		camp[i] = MakeNeutral({ x = c[2].x, y = c[2].y, hp = c[3] or 300 })
	end
	H.Lane.Camps.ResetCache()
	H.FarmPattern.ResetCache()
	local core = MakeUnit({ pid = 1, team = 2, loc = o.at or FRONT, level = 6, mode = BotMode.Laning })
	core.lane, core.pos = Lane.Bot, o.pos or 1
	local support = MakeUnit({ pid = 5, team = 2, loc = Vector(-3000, -5600), level = 4, mode = BotMode.Laning })
	support.lane, support.pos = Lane.Bot, 5
	MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) }).pos = 3
	H.Lane.Config.SkillOf(core)
	H.Lane.Config.SkillOf(support)
	-- In game a core has been in its laning state for minutes when a trip starts: settle it past the 3 s dwell.
	local start = T
	T = start - 4
	capture(function() while T < start do H.States.Tick(core) H.Tasks.Tick(core) T = T + 0.1 end end)
	T = start
	return H, core, camp
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function moveTowards(bot, to, step)
	local d = dist(bot.loc, to)
	if d <= step then bot.loc = Vector(to.x, to.y) else bot.loc = Vector(bot.loc.x + (to.x - bot.loc.x) * step / d, bot.loc.y + (to.y - bot.loc.y) * step / d) end
end

-- One frame: the layer's ticks, farm's GetDesire and (when it bids) its Think. Moves go 300/s; an attack order walks
-- the core into range (550) and then hits its target for 100 every second.
local function frame(H, bot, dt)
	dt = dt or 0.1
	local n0 = #ACTIONS
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	if H.FarmPattern.Desire(bot) > 0 then
		bot.mode = BotMode.Farm
		H.FarmPattern.Think(bot)
	else
		bot.mode = BotMode.Laning
	end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and (a.kind == "MoveToLocation" or a.kind == "AttackUnit") then
			bot.order = a
			break
		end
	end
	local a = bot.order
	if a ~= nil and a.kind == "MoveToLocation" then moveTowards(bot, a.args[1], 300 * dt) end
	if a ~= nil and a.kind == "AttackUnit" and a.args[1].hp > 0 then
		local n = a.args[1]
		if dist(bot.loc, n.loc) > 550 then moveTowards(bot, n.loc, 300 * dt)
		elseif T >= (bot.nextHit or 0) then
			n.hp = math.max(0, n.hp - 100)
			bot.nextHit = T + 1
		end
	end
	T = T + dt
end


local function find(lines, needle)
	for _, l in ipairs(lines) do if l:find(needle, 1, true) then return l end end
end

-- Owned pos 1, wave dead at 7:25: the small camp is planned, cleared on the SDK body, and the core walks back.
do
	local H, core, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	local lines = capture(function() while T < 470 do frame(H, core) end end)
	local start, ended = find(lines, "ev=farm_trip_start"), find(lines, "ev=farm_trip_end")
	check("farm: trip started", start ~= nil and start:find("camp=1", 1, true) ~= nil, start)
	check("farm: camp neutral killed", camp[1].hp == 0)
	check("farm: cleared, then back to the lane", find(lines, "ev=farm_trip_return") ~= nil and find(lines, "ev=farm_trip_return"):find("why=cleared", 1, true) ~= nil,
		find(lines, "ev=farm_trip_return"))
	check("farm: trip ended at the front", ended ~= nil and ended:find("why=back", 1, true) ~= nil, ended)
	local sdk, legacy = ended and tonumber(ended:match(" sdk=(%d+)")), ended and tonumber(ended:match(" legacy=(%d+)"))
	check("farm: executed by the SDK body (>= 90% of frames, step() only before the first selection)", sdk ~= nil and legacy ~= nil and sdk >= 0.9 * (sdk + legacy) and legacy <= 3, ended)
	check("farm: pace learned from the clear", math.abs(H.FarmPattern.PaceFactor(core) - 1) > 1e-3, H.FarmPattern.PaceFactor(core))
	check("farm: state task running as farm", find(lines, "state=farm") ~= nil)
end

-- Same trip, pos 1 not owned: FarmPattern's step() runs it as before.
do
	local H, core, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL } }, states = { Enable = true, Shadow = true, Teams = "all", Own = { farm = { 2 } } } })
	local lines = capture(function() while T < 470 do frame(H, core) end end)
	local ended = find(lines, "ev=farm_trip_end")
	check("unowned: trip still cleared and ended", camp[1].hp == 0 and ended ~= nil)
	check("unowned: no SDK frame fields (not an SDK trip)", ended ~= nil and ended:find(" sdk=", 1, true) == nil, ended)
end

-- A camp too big for the window: at leaveBy the core leaves it unfinished (late) and its pace estimate grows.
do
	local H, core, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL, 5000 } } })
	local lines = capture(function() while T < 470 do frame(H, core) end end)
	local ret = find(lines, "ev=farm_trip_return")
	check("late: walked back unfinished", ret ~= nil and ret:find("why=late", 1, true) ~= nil and camp[1].hp > 0, ret)
	check("late: pace factor grew", H.FarmPattern.PaceFactor(core) > 1 + 1e-3, H.FarmPattern.PaceFactor(core))
end

-- Two camps in reach: after the first OHA chains the second (farm_trip_next), the body clears it too.
do
	local H, core, camp = world({ travel = 10, t = 433, camps = { { "small", SMALL, 200 }, { "small", SMALL2, 200 } } })
	local lines = capture(function() while T < 470 do frame(H, core) end end)
	check("chain: next camp adopted", find(lines, "ev=farm_trip_next") ~= nil, find(lines, "ev=farm_trip_next"))
	check("chain: both camps cleared", camp[1].hp == 0 and camp[2].hp == 0, camp[1].hp .. "/" .. camp[2].hp)
end

-- An enemy hero shows up at the camp: OHA's stop rule ends the trip and the body stops attacking.
do
	local H, core, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL, 5000 } } })
	local attacksAfter
	local lines = capture(function()
		while T < 452 do frame(H, core) end
		MakeUnit({ pid = 11, team = 3, loc = Vector(SMALL.x + 300, SMALL.y) }).pos = 1
		while T < 455 do frame(H, core) end
		local n = #ActionsOf(1, "AttackUnit")
		while T < 460 do frame(H, core) end
		attacksAfter = #ActionsOf(1, "AttackUnit") - n
	end)
	local ended = find(lines, "ev=farm_trip_end")
	check("enemy: trip ended by OHA", ended ~= nil and ended:find("why=enemy", 1, true) ~= nil, ended)
	check("enemy: no attack orders after the end", attacksAfter == 0, attacksAfter)
end

-- After laning, with no trip, the shadow score still picks `farm` for an owned core, but no task is started for it
-- (pre-flight H1: owned only while an SDK trip runs; before, a task started and was cancelled every second).
do
	local H, core = world({ travel = 10, t = 900, camps = {} })
	LANING = false
	core.mode = BotMode.Farm
	local lines = capture(function()
		for _ = 1, 100 do
			H.States.Tick(core)
			H.Tasks.Tick(core)
			T = T + 0.1
		end
	end)
	check("after laning: farm chosen (shadow score)", find(lines, "to=farm") ~= nil or (H.States.Describe(core) or ""):sub(1, 4) == "farm", H.States.Describe(core))
	check("after laning: no farm task started without a trip", find(lines, "ev=state_start") == nil, find(lines, "ev=state_start"))
end

finish()
