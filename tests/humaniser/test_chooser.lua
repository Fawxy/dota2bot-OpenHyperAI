dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice job-chooser: while our job runs, OHA's modes outside the exceptions list cannot take the hero.

local GATED = { "defend_tower_bot", "defend_tower_mid", "defend_tower_top", "laning", "outpost", "push_tower_bot", "push_tower_mid",
	"push_tower_top", "roam", "roshan", "rune", "secret_shop", "side_shop", "team_roam", "ward" }
local EXCEPTED = { "retreat", "assemble", "assemble_with_humans", "attack" }

local function world(ours)
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	if ours ~= nil then package.loaded["bots/FunLib/custom_loader"].Ours = ours end
	T = 200
	H.StackJob.ResetCache()
	return H, MakeUnit({ pid = 5, team = 2, loc = Vector(0, 0, 0) })
end

-- OHA's desire stand-in: returns 0.5 and records the call.
local function inner()
	local o = { called = false }
	o.fn = function() o.called = true return 0.5 end
	return o
end

local function gated(H, bot, mode)
	local i = inner()
	local v = H.Chooser.Gate(bot, mode, i.fn)()
	return v, i.called
end

do
	local H, bot = world()
	H.StackJob.Running = function() return true end
	for _, m in ipairs(GATED) do
		local v, called = gated(H, bot, m)
		check("job running, " .. m .. " gated: exactly 0, OHA's code not run", v == 0 and not called, tostring(v))
	end
	for _, m in ipairs(EXCEPTED) do
		local v, called = gated(H, bot, m)
		check("job running, exception " .. m .. ": OHA's code runs", v == 0.5 and called, tostring(v))
		check("exception " .. m .. " names what removes it", type(H.Chooser.EXCEPTIONS[m]) == "string" and #H.Chooser.EXCEPTIONS[m] > 0)
	end
end

do
	local H, bot = world()
	for _, list in ipairs({ GATED, EXCEPTED }) do
		for _, m in ipairs(list) do
			local v, called = gated(H, bot, m)
			check("no job, " .. m .. ": OHA's code runs", v == 0.5 and called, tostring(v))
		end
	end
end

do
	local H, bot = world({ JobChooser = false })
	H.StackJob.Running = function() return true end
	for _, m in ipairs(GATED) do
		local v, called = gated(H, bot, m)
		check("switch off, job running, " .. m .. ": OHA's code runs", v == 0.5 and called, tostring(v))
	end
end

-- A chooser error hands the hero back to OHA, never every mode at 0.
do
	local H, bot = world()
	H.StackJob.Running = function() error("boom") end
	local v, called = gated(H, bot, "rune")
	check("chooser error: OHA's code runs", v == 0.5 and called, tostring(v))
end

-- A wrong name would silently leave a mode outside the gate: every file holds its own name, above its telemetry line.
do
	local function source(m) return io.open(BOTS_ROOT .. "/bots/mode_" .. m .. "_generic.lua", "r"):read("a") end
	local names = { "farm" }
	for _, list in ipairs({ GATED, EXCEPTED }) do for _, m in ipairs(list) do table.insert(names, m) end end
	check("all 20 mode files listed", #names == 20, #names)
	for _, m in ipairs(names) do
		local src = source(m)
		local at = src:find("C.Gate(GetBot(), '" .. m .. "', GetDesire)", 1, true)
		check(m .. ": wrapper holds its own name", at ~= nil)
		local _, n = src:gsub("C%.Gate%(", "")
		check(m .. ": one wrapper", n == 1, n)
		if m == "attack" then
			-- Two branches define GetDesire (Ours.CoreTrade, then the buggy-hero override); one guarded wrapper after both.
			local block = src:find("elseif local_mode_attack_generic ~= nil then", 1, true)
			local def = src:find("function GetDesire()", block or 1, true)
			local guard = src:find("if GetDesire ~= nil then", 1, true)
			check("attack: wrapper after both branches' GetDesire, only where one is defined", block ~= nil and def ~= nil and guard ~= nil and at ~= nil and block < def and def < guard and guard < at)
		else
			local e = src:find("telemetry').Entry", 1, true)
			check(m .. ": wrapper above its telemetry line", at ~= nil and e ~= nil and at < e)
		end
	end
end

-- Slice retreat: while our episode runs, no OHA mode but the human's orders can take the hero, with the job chooser off too
-- (rtwatch1 7:50-7:58: roam's tango branch at 1.00 outbid the episode's 0.95 five times in 8 s).
for _, ours in ipairs({ {}, { JobChooser = false } }) do
	local H, bot = world(ours)
	require("bots/FunLib/humaniser/retreat_state").SetRunning(bot, true)
	for _, m in ipairs({ "roam", "laning", "team_roam", "attack", "farm", "rune", "ward" }) do
		local v, called = gated(H, bot, m)
		check("episode running, " .. m .. ": exactly 0, OHA's code not run", v == 0 and not called, tostring(v))
	end
	for _, m in ipairs({ "retreat", "assemble", "assemble_with_humans" }) do
		local v, called = gated(H, bot, m)
		check("episode running, " .. m .. ": its own desire runs", v == 0.5 and called, tostring(v))
	end
	require("bots/FunLib/humaniser/retreat_state").SetRunning(bot, false)
	local v = gated(H, bot, "roam")
	check("episode over: roam's own desire runs again", v == 0.5, tostring(v))
end

-- Slice arbiter-fold: the two holds the gate enforces, through the arbiter. An episode outranks a running job, and a job
-- hosted in the rune mode leaves the chooser's own host at 0.
do
	local H, bot = world()
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")
	local asked = 0
	H.StackJob.Running = function() return true end
	H.StackJob.Wants = function() asked = asked + 1 return true end
	RetreatState.SetRunning(bot, true)
	local v, called = gated(H, bot, "farm")
	check("episode during a job: the job's host gets exactly 0 and the job is not asked", v == 0 and not called and asked == 0, tostring(v) .. " " .. asked)
	v, called = gated(H, bot, "retreat")
	check("episode during a job: the retreat mode's own desire runs", v == 0.5 and called, tostring(v))
	v, called = gated(H, bot, "attack")
	check("episode during a job: the job's exception does not pass", v == 0 and not called, tostring(v))
	RetreatState.SetRunning(bot, false)
	v = gated(H, bot, "farm")
	check("episode over: the job holds its host again", v == H.Chooser.SETTINGS.JobDesire and asked > 0, tostring(v))
end
do
	local H, bot = world()
	local BotMode = require("bots/ts_libs/dota/index").BotMode
	H.RuneJob.Running = function() return true end
	H.RuneJob.HostOf = function() return BotMode.Rune end
	local v, called = gated(H, bot, "rune")
	check("job hosted in rune: the rune mode's own desire runs", v == 0.5 and called, tostring(v))
	v, called = gated(H, bot, "farm")
	check("job hosted in rune: the chooser's host gets exactly 0", v == 0 and not called, tostring(v))
	v, called = gated(H, bot, "laning")
	check("job hosted in rune: laning gets exactly 0", v == 0 and not called, tostring(v))
	v, called = gated(H, bot, "attack")
	check("job hosted in rune: the exception attack runs", v == 0.5 and called, tostring(v))
end
finish()
