dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice support-lane: PullJob (Ours.SupportPull) under the job chooser. The lane push reading is stubbed per world, so these
-- tests cover the job's decision and hand-off, not the fight model (test_lane_push.lua).

local dota = require("bots/ts_libs/dota/index")
local Lane, FARM, LANING = dota.Lane, dota.BotMode.Farm, dota.BotMode.Laning

-- As test_lane_pull_timing: Radiant bot lane along y = -5000, the small camp south of it, wave-timed pulls at 300 speed.
local SMALL = Vector(-1600, -6200)
local PATH = { { -9400, -5000 }, { 7000, -5000 } }

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

-- `reading`: what LanePush.Read returns (nil: no clash); `reads` counts the calls.
local function world(o)
	o = o or {}
	package.loaded["bots/FunLib/engine/tasks"] = nil
	local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 } } },
		{ skill = 1, telemetry = { Enable = true }, supportPull = o.on ~= false })
	T = o.t or 61
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { { team = 2, type = "small", location = SMALL, min = Vector(SMALL.x - 150, SMALL.y - 150, 0),
		max = Vector(SMALL.x + 150, SMALL.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	H.PullJob.ResetCache()
	local data = H.Lane.Camps.ByIdx(1)
	local stand = H.Lane.Camps.BoxEdgePoint(H.Lane.Camps.SpawnerByIdx(1), data.pull.path[1], 150)
	local sup = MakeUnit({ pid = 5, team = 2, bot = true, loc = o.supAt or Vector(stand.x + 600, stand.y) })
	sup.lane, sup.pos = Lane.Bot, 5
	local core = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000), hp = o.coreHp })
	core.lane, core.pos = Lane.Bot, 1
	local P = package.loaded["bots/FunLib/humaniser/lane_push"]
	local w = { H = H, sup = sup, core = core, reads = 0, stand = stand }
	P.Read = function()
		w.reads = w.reads + 1
		return o.reading
	end
	return w
end

local function frame(w, dt)
	local H, bot = w.H, w.sup
	local n0 = #ACTIONS
	if H.Chooser.Gate(bot, "farm", function() return 0 end)() > 0 then
		bot.mode = FARM
		H.Chooser.HostThink(bot, "farm", function() return false end, function() return false end)()
	else
		bot.mode = LANING
	end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "MoveToLocation" then bot.loc = Vector(a.args[1].x, a.args[1].y) break end
	end
	T = T + (dt or 0.1)
end

local function run(w, untilT) return capture(function() while T < untilT do frame(w) end end) end

local OUT = { state = "OUT", clash = 9000, move = 640, q = 0.7, tower = false, cf = -420, ms = 3.1 }

-- The lane pushes out: at the leave time the support reads the lane once, starts, walks to the camp under the farm host.
do
	local w = world({ reading = OUT })
	local out = run(w, 75)
	local choice = lines(out, "choice")
	check("OUT: one choice line, go=1 want=1, the reading's fields", #choice == 1 and field(choice[1], "go") == "1" and field(choice[1], "want") == "1"
		and field(choice[1], "st") == "OUT" and field(choice[1], "cf") == "-420" and field(choice[1], "kind") == "pull", choice[1])
	local starts = lines(out, "job")
	check("OUT: the chooser started a pull job", #starts == 1 and field(starts[1], "job") == "pull" and field(starts[1], "phase") == "start", starts[1])
	check("OUT: running under the farm host", w.H.PullJob.Running(w.sup) and w.sup.mode == FARM)
	check("OUT: the lane read once for the slot", w.reads == 1, w.reads)
	-- No neutrals in this world: the verb ends at the camp with no camp to hit, and the attempt is logged (before the next
	-- slot's pull, about 30 s later, could end too).
	out = run(w, 100)
	local pulls = lines(out, "pull_job")
	check("end: one pull_job line, failed for no camp, slot as chosen, alive", #pulls == 1 and field(pulls[1], "res") == "fail"
		and field(pulls[1], "why"):find("no-camp", 1, true) ~= nil and field(pulls[1], "slot") == field(choice[1], "slot") and field(pulls[1], "died") == "0", pulls[1])
	check("end: the hero is handed back to lane", not w.H.PullJob.Running(w.sup) and w.sup.mode == LANING)
end

-- A pull that ends ok: the wave's later creeps reach the neutrals after the job has handed the hero back, so the line waits
-- for the trail and carries both shares (sp2: pulls logged at div 0.25 moved the lane back the most).
do
	local w = world({ reading = OUT })
	for k in pairs(NEUTRALS) do NEUTRALS[k] = nil end
	local kobold = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	kobold.target = w.sup
	local wave, ended = {}, nil
	local out = capture(function()
		while T < 140 and ended == nil do
			frame(w)
			-- The wave walks with the hero, so it is at the meet point while the hero watches there.
			if #wave == 0 and w.H.PullJob.Running(w.sup) then
				for i = 1, 4 do wave[i] = MakeCreep({ team = 2, x = 0, y = 0 }) end
				wave[1].target = kobold
			end
			for _, c in ipairs(wave) do c.loc = Vector(w.sup.loc.x, w.sup.loc.y) end
			if #wave > 0 and not w.H.PullJob.Running(w.sup) then ended = T end
		end
	end)
	local watch
	for _, l in ipairs(lines(out, "pull_watch")) do if field(l, "ph") == "watch" and field(l, "won") == "1" then watch = l end end
	check("ok pull: a watch sample names one creep of four on the neutral, and the neutral left at its camp (out of nn) on the puller", watch ~= nil
		and field(watch, "wc") == "4" and field(watch, "nn") == "0" and field(watch, "nt") == "p" and tonumber(field(watch, "nh")) == 0
		and tonumber(field(watch, "nd")) > 0, watch)
	local atEnd = ended ~= nil and #lines(out, "pull_job") or -1
	check("ok pull: the job ended with the wave there", ended ~= nil and #wave == 4, ended)
	for i = 2, 4 do wave[i].target = kobold end
	out = run(w, (ended or 0) + 1)
	check("ok pull: no line while the trail runs", atEnd == 0 and #lines(out, "pull_job") == 0, out[1])
	local trailed = lines(out, "pull_watch")
	check("ok pull: the trail goes on sampling, now with all four creeps on the neutral", #trailed >= 1
		and field(trailed[#trailed], "ph") == "trail" and field(trailed[#trailed], "won") == "4", trailed[#trailed])
	out = run(w, (ended or 0) + 30)
	local pulls = lines(out, "pull_job")
	check("ok pull: one line after the trail, div from the job, dt with the creeps that came later", #pulls == 1
		and field(pulls[1], "res") == "ok" and tonumber(field(pulls[1], "div")) == 0.25 and tonumber(field(pulls[1], "dt")) == 1, pulls[1])
end

-- The lane comes in (or holds on our half): no pull; the slot is decided once, not re-read every frame.
for _, case in ipairs({
	{ "IN", { state = "IN", clash = 7000, move = -500, q = 0.3, tower = false } },
	{ "HOLD on our half", { state = "HOLD", clash = 8000, move = 100, q = 0.4, tower = false } },
}) do
	local w = world({ reading = case[2] })
	local out = run(w, 75)
	local choice = lines(out, "choice")
	check(case[1] .. ": go=0 want=0 why=lane", #choice == 1 and field(choice[1], "go") == "0" and field(choice[1], "want") == "0" and field(choice[1], "why") == "lane", choice[1])
	check(case[1] .. ": no job, read once", #lines(out, "job") == 0 and w.reads == 1, w.reads)
end

-- HOLD past the middle on their side counts as pushing out.
do
	local w = world({ reading = { state = "HOLD", clash = 9500, move = 50, q = 0.62, tower = false } })
	local out = run(w, 75)
	check("HOLD on their half: pull started", #lines(out, "job") == 1 and field(lines(out, "choice")[1], "go") == "1")
end

-- Wanted, but the core is low with an enemy beside it until the pull would be late: skipped, naming the partner.
do
	local w = world({ reading = OUT, coreHp = 30 })
	local enemy = MakeUnit({ pid = 10, team = 3, loc = Vector(300, -5000) })
	enemy.lane, enemy.pos = Lane.Bot, 3
	local out = run(w, 80)
	local choice = lines(out, "choice")
	check("partner low: go=0 want=1 why=partner-low, no job", #choice == 1 and field(choice[1], "go") == "0" and field(choice[1], "want") == "1"
		and field(choice[1], "why") == "partner-low" and #lines(out, "job") == 0, choice[1])
end

-- Both supports in the bot lane: the pos5 pulls, the pos4 does not apply.
do
	local w = world({ reading = OUT })
	local four = MakeUnit({ pid = 4, team = 2, bot = true, loc = Vector(0, -5000) })
	four.lane, four.pos = Lane.Bot, 4
	check("shared lane: pos5 applies, pos4 does not", w.H.PullJob.Applies(w.sup) and not w.H.PullJob.Applies(four))
	four.lane = Lane.Top
	check("pos4 in its own lane with no pull camp there: does not apply", not w.H.PullJob.Applies(four))
end

-- The old camp-job pulls: refused for a bot the job applies to (a human's order still runs), and back with the switch off.
do
	local w = world({ reading = OUT })
	check("switch on: old full pull refused", not w.H.Lane.CampJobs.Start(w.sup, { kind = "full_pull", campIdx = 1 }))
	check("switch on: a human-ordered pull still starts", w.H.Lane.CampJobs.Start(w.sup, { kind = "full_pull", campIdx = 1, forced = true }))
	w = world({ reading = OUT, on = false })
	check("switch off: no pull job, the old full pull starts", not w.H.PullJob.Applies(w.sup) and w.H.Lane.CampJobs.Start(w.sup, { kind = "full_pull", campIdx = 1 }))
end

finish()
