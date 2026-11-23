dofile(HARNESS_DIR .. "/lane_world.lua")
-- Shadow choice line (Ours.ChoiceShadow, choice_shadow.ts): the gate returns the same desires with the line on or off and
-- calls OHA's code exactly as often; the line names OHA's top beside Valve's pick and what made the difference.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local MODES = { "laning", "attack", "retreat", "farm", "team_roam", "roam", "rune", "ward", "assemble", "assemble_with_humans",
	"defend_tower_top", "defend_tower_mid", "defend_tower_bot", "push_tower_top", "push_tower_mid", "push_tower_bot", "roshan",
	"secret_shop", "side_shop", "outpost" }
-- OHA's desire stand-ins: roam is the highest, so OHA alone would roam.
local VALUE = { laning = 0.3, roam = 0.8, team_roam = 0.7, ward = 0.1, rune = 0.05 }

local function world(sw)
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true }, retreat = true })
	local C = package.loaded["bots/FunLib/custom_loader"]
	for k, v in pairs(sw) do C.Ours[k] = v end
	package.loaded["bots/FunLib/humaniser/choice_shadow"].Reset()
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000), level = 3 })
	bot.lane, bot.pos, bot.mode = Lane.Bot, 1, BotMode.Laning
	return H, bot
end

-- Three frames through all 20 gates: every returned desire and the count of OHA calls per mode.
local function play(sw, setup)
	local H, bot = world(sw)
	if setup then setup(H, bot) end
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local outs, calls = {}, {}
	local ok, err = pcall(function()
		for f = 1, 3 do
			for _, m in ipairs(MODES) do
				local out = H.Chooser.Gate(bot, m, function()
					calls[m] = (calls[m] or 0) + 1
					return VALUE[m] or 0
				end)()
				outs[#outs + 1] = m .. "=" .. tostring(out)
			end
			T = T + 0.1
		end
	end)
	print = old
	if not ok then error(err, 0) end
	local lines = {}
	for _, l in ipairs(printed) do if l:find("kind=shadow", 1, true) then lines[#lines + 1] = l end end
	return table.concat(outs, " "), calls, lines
end

local function same(a, b)
	for k, v in pairs(a) do if b[k] ~= v then return false end end
	for k, v in pairs(b) do if a[k] ~= v then return false end end
	return true
end

local offOut, offCalls, offLines = play({ ChoiceShadow = false })
local onOut, onCalls, onLines = play({ ChoiceShadow = true })
check("shadow off: no line", #offLines == 0)
check("shadow on: the gate returns the same desires as off", onOut == offOut, onOut .. "\n" .. offOut)
check("shadow on: OHA's code asked exactly as often as off", same(onCalls, offCalls))
check("shadow on: a line from the second frame on", #onLines >= 1, table.concat(onLines, "\n"))
local l = onLines[1] or ""
check("line: the active mode is the winner", l:find("win=laning", 1, true) ~= nil, l)
check("line: OHA's top over computed modes is roam, with its value", l:find("top=roam", 1, true) ~= nil and l:find("d_roam=0.800", 1, true) ~= nil, l)
check("line: nothing of ours moved a value, so Valve's arbitration is named", l:find("how=valve by=Valve:arbitration", 1, true) ~= nil
	and l:find("gate=", 1, true) == nil, l)

-- A running job holds OHA's gated modes at 0 before their code and the chooser's host takes the hero.
do
	local _, calls, lines = play({ ChoiceShadow = true }, function(H, bot)
		H.StackJob.Running = function() return true end
		H.StackJob.Wants = function() return true end
		bot.mode = BotMode.Farm
	end)
	local j = lines[1] or ""
	check("job: roam's code not run while the job holds it", calls.roam == nil)
	check("job: the line names the hold and the host's desire, no top among OHA's held modes", j:find("win=farm", 1, true) ~= nil
		and j:find("d_roam=-hold", 1, true) ~= nil and j:find("hdes=", 1, true) ~= nil and j:find(" top=", 1, true) == nil, j)
end

-- Runs `frames` frames of the laning and team_roam gates (stubs `lane(f)` and `roam(f)`); every shadow line printed.
local function frames(H, bot, n, lane, roam, step)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(function()
		for f = 1, n do
			H.Chooser.Gate(bot, "laning", function() return lane(f) end)()
			H.Chooser.Gate(bot, "team_roam", function() return roam(f) end)()
			T = T + (step or 0.1)
		end
	end)
	print = old
	if not ok then error(err, 0) end
	local lines = {}
	for _, s in ipairs(printed) do if s:find("kind=shadow", 1, true) then lines[#lines + 1] = s end end
	return lines
end

-- Laning's own branch of ours fired (MarkMix) and wins at its own desire: nothing to name.
do
	local H, bot = world({ ChoiceShadow = true })
	local lines = frames(H, bot, 2, function() H.ChoiceShadow.MarkMix(bot) return 0.9 end, function() return 0.7 end)
	local line = lines[#lines] or ""
	check("mix: laning wins at its own desire, no difference to name", line:find("top=laning", 1, true) ~= nil
		and line:find("how=", 1, true) == nil, line)
	check("mix: laning's branch marked as fired", line:find("mix=laning", 1, true) ~= nil, line)
end

-- Mix attribution: laning's branch fired but laning's desire (with it) is under team roam's, and Valve held laning anyway:
-- the branch cannot have made the difference, so the line names Valve's arbitration. A frame where it did not fire has no mix.
do
	local H, bot = world({ ChoiceShadow = true })
	local lines = frames(H, bot, 3, function(f)
		if f == 1 then H.ChoiceShadow.MarkMix(bot) end
		return 0.3
	end, function() return 0.7 end, 1.0)
	local a, b = lines[1] or "", lines[2] or ""
	check("mix: laning's fired branch logged", a:find("mix=laning", 1, true) ~= nil, a)
	check("mix: under top, the branch is not the cause", a:find("top=team_roam", 1, true) ~= nil
		and a:find("how=valve by=Valve:arbitration", 1, true) ~= nil, a)
	check("mix: a frame without the branch has no laning mix", b ~= "" and b:find("mix=laning", 1, true) == nil, b)
end
finish()
