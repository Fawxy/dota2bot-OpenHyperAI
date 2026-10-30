dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Behaviour-state layer (humaniser/states) on the engine's States: ownership by position and team,
-- the laning body replacing PositionThink through Step, and the kill switch.
local BUNDLE = "bots/FunLib/engine/tasks"
local LANING = 1
BOT_MODE_LANING = LANING

local function Fresh(states, o)
	ResetWorld()
	T = 10
	package.loaded[BUNDLE] = nil
	local H = FreshHumaniser({ Enable = true, Lane = { Enable = false }, Transitions = { Enable = false }, States = states })
	-- These cases test the States settings on OHA's path: slice 5's Ours.CoreLastHit (pos1-3 own laning) is off here.
	package.loaded["bots/FunLib/custom_loader"].Ours = { CoreLastHit = false }
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	Phase.IsLaningFor = function() return true end
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	local positions = {}
	LaneConfig.SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	o = o or {}
	local human = MakeUnit({ pid = 0, bot = false })
	local bot = MakeUnit({ pid = 1, mode = LANING, loc = Vector(0, 0) })
	positions[1] = o.pos or 2
	return H, bot, positions, human
end

-- One frame as OHA plays it: Humaniser.Tick's States then Tasks ticks, then the laning Think's last step.
local function frame(H, bot, spot)
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	local stepped = false
	if bot.mode == LANING then stepped = H.States.Step(bot, LANING) end
	T = T + 0.05
	return stepped
end

local function silenced(fn)
	local p = print
	print = function() end
	local ok, err = pcall(fn)
	print = p
	if not ok then error(err, 0) end
end

-- Owned (pos 2, ally of a human): the body walks the bot to the spot it is handed, re-read each frame.
do
	local H, bot
	local stepped = 0
	local spot = Vector(1000, 0)
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } } })
		check("pos 2 may own", H.States.MayOwn(bot) == true)
		H.States.SetLaneSpot(bot, function() return spot end)
		for _ = 1, 10 do if frame(H, bot) then stepped = stepped + 1 end end
	end)
	check("owned: laning body stepped every frame", stepped == 10, stepped)
	local last = bot.moves and bot.moves[#bot.moves]
	check("owned: move ordered towards the spot", last ~= nil and GetUnitToLocationDistance({ loc = last }, spot) <= 50, last and (last.x .. "," .. last.y))
	spot = Vector(-500, 300)
	silenced(function() for _ = 1, 3 do frame(H, bot) end end)
	last = bot.moves[#bot.moves]
	check("owned: follows a moved spot", GetUnitToLocationDistance({ loc = last }, spot) <= 50, last.x .. "," .. last.y)
	check("Describe: owned and running", (H.States.Describe(bot) or ""):find("laning* run", 1, true) ~= nil, H.States.Describe(bot))
end

-- Not listed in Own (pos 3): shadow only; Step returns false so OHA's PositionThink runs.
do
	local H, bot
	local stepped = false
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } } }, { pos = 3 })
		H.States.SetLaneSpot(bot, function() return Vector(1000, 0) end)
		for _ = 1, 10 do stepped = frame(H, bot) or stepped end
	end)
	check("pos 3: never stepped", stepped == false)
	check("pos 3: no moves issued", bot.moves == nil)
	check("pos 3: shadow state chosen", (H.States.Describe(bot) or ""):sub(1, 6) == "laning", H.States.Describe(bot))
end

-- A Customize Own list replaces the default, so an empty list owns nothing.
do
	local H, bot
	silenced(function() H, bot = Fresh({ Enable = true, Own = { laning = {} } }) end)
	check("empty Own: pos 2 may not own", H.States.MayOwn(bot) == false)
end

-- Kill switch: Enable = false (the default) does nothing at all and never loads the bundle for states.
do
	local H, bot
	local stepped = false
	silenced(function()
		H, bot = Fresh(nil)
		H.States.SetLaneSpot(bot, function() return Vector(1000, 0) end)
		for _ = 1, 10 do stepped = frame(H, bot) or stepped end
	end)
	check("off: MayOwn false", H.States.MayOwn(bot) == false)
	check("off: never stepped", stepped == false)
	check("off: no moves", bot.moves == nil)
	check("off: Describe nil", H.States.Describe(bot) == nil)
end

-- Teams = 'allies': a bot on a team without a human is left alone.
do
	local H, bot
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } } })
		UNITS[2] = { bot } -- the human leaves the team
	end)
	check("allies: bot without a human ally may not own", H.States.MayOwn(bot) == false)
end

finish()
