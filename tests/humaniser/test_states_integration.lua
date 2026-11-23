dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Behaviour-state layer (humaniser/states) on the engine's States: who may own (an Own list, the team rule) and the kill
-- switch. The laning state is gone (23/11/2026), so laning's Think has nothing of the layer to step.
local BUNDLE = "bots/FunLib/engine/tasks"
local LANING = 1
BOT_MODE_LANING = LANING

local function Fresh(states)
	ResetWorld()
	T = 10
	package.loaded[BUNDLE] = nil
	local H = FreshHumaniser({ Enable = true, Lane = { Enable = false }, Transitions = { Enable = false }, States = states })
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	Phase.LaningHeld = function() return true end
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	LaneConfig.SetHelpers({ GetPosition = function() return 4 end })
	MakeUnit({ pid = 0, bot = false })
	local bot = MakeUnit({ pid = 1, mode = LANING, loc = Vector(0, 0) })
	return H, bot
end

local function frame(H, bot)
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	local stepped = H.States.Step(bot, LANING)
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

-- An ally of a human with a state listed in Own may own; laning's Think finds nothing of the layer to step.
do
	local H, bot
	local stepped = false
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { stack = { 4 } } })
		for _ = 1, 10 do stepped = frame(H, bot) or stepped end
	end)
	check("listed in Own: may own", H.States.MayOwn(bot) == true)
	check("laning: never stepped, no moves", stepped == false and bot.moves == nil)
end

-- A Customize Own list replaces the default, so empty lists own nothing.
do
	local H, bot
	silenced(function() H, bot = Fresh({ Enable = true, Own = { stack = {}, rotate = {} } }) end)
	check("empty Own: may not own", H.States.MayOwn(bot) == false)
end

-- Kill switch: Enable = false (the default) does nothing at all.
do
	local H, bot
	local stepped = false
	silenced(function()
		H, bot = Fresh(nil)
		for _ = 1, 10 do stepped = frame(H, bot) or stepped end
	end)
	check("off: MayOwn false", H.States.MayOwn(bot) == false)
	check("off: never stepped, no moves", stepped == false and bot.moves == nil)
	check("off: Describe nil", H.States.Describe(bot) == nil)
end

-- Teams = 'allies': a bot on a team without a human is left alone.
do
	local H, bot
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { stack = { 4 } } })
		UNITS[2] = { bot } -- the human leaves the team
	end)
	check("allies: bot without a human ally may not own", H.States.MayOwn(bot) == false)
end

finish()
