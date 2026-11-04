dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice support-lane: PullJob (Ours.SupportPull) under the job chooser. The lane push reading is stubbed per world, so these
-- tests cover the job's decision and hand-off, not the fight model (test_lane_push.lua).

local dota = require("bots/ts_libs/dota/index")
local Lane, FARM, LANING = dota.Lane, dota.BotMode.Farm, dota.BotMode.Laning

-- As test_lane_pull_timing: Radiant bot lane along y = -5000, the small camp south of it, wave-timed pulls at 300 speed.
local SMALL = Vector(-1600, -6200)
local PATH = { { -9400, -5000 }, { 7000, -5000 } }

-- The camp's box out of our team's sight (an empty box then says nothing about the camp), as in lane before a ward or a
-- puller is near; `visible` worlds see it.
local function campFog(v) return math.abs(v.x - SMALL.x) < 600 and math.abs(v.y - SMALL.y) < 600 end

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
	local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, LiveEvery = o.liveEvery, HalfLag = o.halfLag } },
		{ skill = 1, telemetry = { Enable = true }, supportPull = o.on ~= false })
	T = o.t or 61
	for k in pairs(NEUTRALS) do NEUTRALS[k] = nil end
	FOGGED = not o.visible and campFog or nil
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { { team = 2, type = "small", location = SMALL, min = Vector(SMALL.x - 150, SMALL.y - 150, 0),
		max = Vector(SMALL.x + 150, SMALL.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	H.PullJob.ResetCache()
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportHalfPull = o.half
	local data = H.Lane.Camps.ByIdx(1)
	local stand = H.Lane.Camps.BoxEdgePoint(H.Lane.Camps.SpawnerByIdx(1), data.pull.path[1], 150)
	local sup = MakeUnit({ pid = 5, team = 2, bot = true, loc = o.supAt or Vector(stand.x + 600, stand.y), hp = o.supHp or 600, maxhp = 600 })
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

-- The neutrals walk back and the wave follows them into the camp, out of the meet point's watch radius: it still counts
-- (pw1: Radiant safe small, camp about 1100 from its meet point, logged undiverted while the camp's neutrals hit our wave;
-- ~/.dotactl/logs/2026-11-03T00-27-18-pw1_B_on_2.log t=549.2, slot 530.4).
do
	local w = world({ reading = OUT })
	for k in pairs(NEUTRALS) do NEUTRALS[k] = nil end
	local kobold = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	kobold.target = w.sup
	local meet = w.H.Lane.Camps.ByIdx(1).pull.meetPoint
	local far = math.sqrt((meet.x - SMALL.x) ^ 2 + (meet.y - SMALL.y) ^ 2) > w.H.Lane.Config.Settings().Radii.MeetWatch
	local wave, ended = {}, nil
	capture(function()
		while T < 140 and ended == nil do
			frame(w)
			if #wave == 0 and w.H.PullJob.Running(w.sup) then
				for i = 1, 4 do wave[i] = MakeCreep({ team = 2, x = SMALL.x + 50 * i, y = SMALL.y, target = kobold }) end
			end
			if #wave > 0 and not w.H.PullJob.Running(w.sup) then ended = T end
		end
	end)
	local out = run(w, (ended or 0) + 30)
	local pulls = lines(out, "pull_job")
	check("camp fight: the camp lies outside the meet point's watch, and the wave fighting there is diverted", far and #pulls == 1
		and tonumber(field(pulls[1], "div")) == 1 and tonumber(field(pulls[1], "n")) == 4, pulls[1])
end

-- Slice pull-diag: the camp's neutral follows the puller reading no attack target (a chase out of attack range does, review
-- 2026-11-04-pull-diag H1), then walks home 3 s after the hit, while a box member stays home (M1) and another camp's neutral
-- stands by the meet point (lhrchk1 pid 3 slot 80.353: the watch named a neutral 3350 from the camp once the camp's own had
-- gone home). The line says when the hit landed, when the camp gave up and how far it came; the watch counts the camp only.
do
	local w = world({ reading = OUT })
	for k in pairs(NEUTRALS) do NEUTRALS[k] = nil end
	local kobold = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	kobold.target = w.sup
	local stays = MakeNeutral({ x = SMALL.x + 50, y = SMALL.y })
	local meet = w.H.Lane.Camps.ByIdx(1).pull.meetPoint
	MakeNeutral({ x = meet.x + 200, y = meet.y + 200 })
	local hitAt, ended = nil, nil
	local out = capture(function()
		while T < 140 and ended == nil do
			frame(w)
			local p = w.H.PullJob.Running(w.sup)
			if p and hitAt == nil and w.H.PullJob.Running(w.sup) and w.sup.loc.y > SMALL.y + 300 then hitAt = T end
			-- A tagged neutral dies and is freed while the watch runs (pdg1/pdg2: Invalid object in taggedState).
			if hitAt ~= nil and T >= hitAt + 1 and not stays.removed then
				stays.removed = true
				for i = #NEUTRALS, 1, -1 do if NEUTRALS[i] == stays then table.remove(NEUTRALS, i) end end
			end
			if hitAt ~= nil then
				kobold.target = nil
				if T < hitAt + 3 then
					kobold.loc = Vector(w.sup.loc.x, w.sup.loc.y - 150)
				else
					local dx, dy = SMALL.x - kobold.loc.x, SMALL.y - kobold.loc.y
					local d = math.sqrt(dx * dx + dy * dy)
					if d > 40 then kobold.loc = Vector(kobold.loc.x + dx / d * 30, kobold.loc.y + dy / d * 30) end
				end
			end
			if hitAt ~= nil and not p then ended = T end
		end
	end)
	local diagErr
	for _, l in ipairs(out) do if l:find("pull diag error", 1, true) then diagErr = l end end
	check("diag: a tagged neutral freed mid-watch raises no diagnostics error", diagErr == nil, diagErr)
	local tagged
	for _, l in ipairs(lines(out, "pull_watch")) do
		if field(l, "tn") ~= nil and (tagged == nil or tonumber(field(l, "tn")) > tonumber(field(tagged, "tn"))) then tagged = l end
	end
	check("diag: watch samples count the camp's two neutrals (tn=2 at most), not the other camp's by the meet point", tagged ~= nil
		and field(tagged, "tn") == "2", tagged)
	out = run(w, (ended or 0) + 30)
	local pull = lines(out, "pull_job")[1]
	local ht, gu, gh, g4 = tonumber(field(pull, "ht")), tonumber(field(pull, "gu")), tonumber(field(pull, "gh")), tonumber(field(pull, "g4"))
	-- The world's neutral walks home 3 s after the puller leaves the camp, which a pace hold (`pz`) after the hit delays.
	local pz = tonumber(field(pull, "pz")) or 0
	check("diag: a chase with no attack target is not giving up; gu comes once it walks home (3-4.5 s after ht and any pace), the box member staying home neither holds nor sets it",
		ht ~= nil and gu ~= nil and gu - ht - pz >= 3 and gu - ht - pz <= 4.5, pull)
	check("diag: g4 when it passed 400 from its camp, gh how far it followed, no shift", g4 ~= nil and g4 >= ht and g4 < gu
		and gh ~= nil and gh > 400 and field(pull, "sh") == "0" and field(pull, "lv") == "0", pull)
end

-- An early wave moves the hit earlier (LiveRead): the support leaves that much earlier, so a pull it starts can still be
-- made (pw2: 12 starts planned against the unshifted slot failed `late` while still walking; first in
-- ~/.dotactl/logs/2026-11-03T00-51-30-pw2_A_on_1.log t=108.8).
do
	local function startAt(shift)
		local w = world({ reading = OUT })
		local PT = package.loaded["bots/FunLib/humaniser/pull_timing"]
		local live = PT.LiveRead
		PT.LiveRead = function() return shift ~= 0 and { shift = shift, front = shift } or nil end
		local at
		capture(function() while T < 90 and at == nil do frame(w) if w.H.PullJob.Running(w.sup) then at = T end end end)
		PT.LiveRead = live
		return at
	end
	local on, early = startAt(0), startAt(-4)
	check("early wave: the pull starts 4 s earlier than on time", on ~= nil and early ~= nil and math.abs((on - early) - 4) < 0.15, tostring(on) .. " " .. tostring(early))
	-- Held back (partner low) until 6 s after that early leave time: past the moved hit's late limit (leave + Early 2 +
	-- JobStartLate 2), short of the unshifted slot's (4 s later): the pull is skipped as late, not started.
	local w = world({ reading = OUT, coreHp = 30 })
	local enemy = MakeUnit({ pid = 10, team = 3, loc = Vector(300, -5000) })
	enemy.lane, enemy.pos = Lane.Bot, 3
	local PT = package.loaded["bots/FunLib/humaniser/pull_timing"]
	local live = PT.LiveRead
	PT.LiveRead = function() return { shift = -4, front = -4 } end
	local out = capture(function()
		while T < 90 do
			if early ~= nil and T >= early + 6 then enemy.loc = Vector(9000, 9000) end
			frame(w)
		end
	end)
	PT.LiveRead = live
	local choice = lines(out, "choice")
	check("early wave, held back past the moved hit's late limit: no start, the hold named", #lines(out, "job") == 0 and #choice == 1
		and field(choice[1], "go") == "0" and field(choice[1], "why") == "partner-low", choice[1])
end

-- Slice pull-live: the wave read again up to the order and after it. `shiftAt(t, started)` stubs LiveRead from the job's
-- start; `neutralAt` places the camp's one neutral (on the puller) each frame. Returns the pull_job line.
local function livePull(shiftAt, neutralAt, o)
	o = o or {}
	local w = world({ reading = o.reading or OUT, liveEvery = 0, halfLag = o.halfLag })
	ACTIONS = {}
	local PT = package.loaded["bots/FunLib/humaniser/pull_timing"]
	local live = PT.LiveRead
	local started
	PT.LiveRead = function()
		local sh = shiftAt(T, started)
		return sh ~= nil and { shift = sh, front = sh } or nil
	end
	for k in pairs(NEUTRALS) do NEUTRALS[k] = nil end
	local kobold = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	kobold.target = w.sup
	local out = capture(function()
		while T < 120 do
			frame(w)
			if started == nil and w.H.PullJob.Running(w.sup) then started = T end
			if neutralAt ~= nil then kobold.loc = neutralAt(w) end
		end
	end)
	PT.LiveRead = live
	return lines(out, "pull_job")[1]
end

do
	-- On time at the start, 1.5 s late from 1 s after it: the hit lands 1.5 s later than on a wave that stays on time.
	local steady = livePull(function() return 0 end)
	local slowed = livePull(function(t, started) if started ~= nil and t >= started + 1 then return 1.5 end return 0 end)
	local d = tonumber(field(slowed, "ht")) - tonumber(field(steady, "ht"))
	check("live: a wave slowed after the start moves the hit with it (1.5 s)", math.abs(d - 1.5) <= 0.15, d)
	check("live: sh is the shift at the order, s0 the start's", tonumber(field(slowed, "sh")) == 1.5 and tonumber(field(slowed, "s0")) == 0, slowed)
end

do
	-- The wave falls 4 s behind once the attack order is out: the puller holds the whole PaceFor
	-- (3 s) while the neutral stays in its camp (the wave read every frame, LiveEvery 0, so the first read after the order sees it), and walks the lead at once when the neutral is already past the guard.
	-- On time it still holds about a second: the plan puts the neutrals at the meet point Lead (1.5 s) before the wave, the
	-- pace PaceLead (0.5 s), plus the hit landing about 0.5 s before the slot in this world.
	local function ordered()
		for _, a in ipairs(ACTIONS) do if a.pid == 5 and a.kind == "AttackUnit" then return true end end
		return false
	end
	local function late(t, started) if started ~= nil and ordered() then return 4 end return 0 end
	local held = livePull(late)
	local onTime = tonumber(field(livePull(function() return 0 end), "pz") or "0")
	check("pace: a late wave holds the puller after the hit for PaceFor", math.abs(tonumber(field(held, "pz") or "0") - 3) <= 0.15, held)
	check("pace: an on-time pull holds about a second, so the neutrals come PaceLead before the wave: " .. onTime, onTime >= 1 and onTime <= 2)
	local out = livePull(late, function(w) return Vector(SMALL.x, SMALL.y + 500) end)
	check("pace: a neutral past the guard (500 from its camp) is not held for", field(out, "pz") == nil, out)
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

-- Slice pull-half. The safe-lane pos5 half-pulls a lane that holds on their half: the same wave, decided once at the full
-- pull's leave time, hit HalfPullLater (2 s) later; with the switch off it full-pulls. A pushing lane is still a full pull.
local HOLD = { state = "HOLD", clash = 9500, move = 50, q = 0.62, tower = false }
do
	local function pull(o)
		local w = world(o)
		local out = run(w, 80)
		return lines(out, "choice")[1], lines(out, "job")[1], w
	end
	local full = pull({ reading = OUT })
	local half, job, w = pull({ reading = HOLD })
	local off = pull({ reading = HOLD, half = false })
	local d = tonumber(field(half, "slot")) - tonumber(field(full, "slot"))
	check("half: HOLD on their half gets pk=half, its slot 2 s after the full pull's", field(half, "pk") == "half" and field(half, "go") == "1"
		and math.abs(d - 2) < 0.01 and job ~= nil, half)
	check("half: the lane read once for the wave", w.reads == 1, w.reads)
	check("half: OUT gets a full pull", field(full, "pk") == "full", full)
	check("half: switch off, HOLD gets a full pull on the full slot", field(off, "pk") == "full" and field(off, "slot") == field(full, "slot"), off)
end

-- Only the safe-lane pos5: an off-lane support (Radiant top) or a pos4 full-pulls the same reading.
do
	local w = world({ reading = HOLD })
	check("half: safe-lane pos5 half-pulls", w.H.PullJob.KindFor(w.sup, HOLD) == "half")
	w.sup.lane = Lane.Top
	check("half: off-lane pos5 full-pulls", w.H.PullJob.KindFor(w.sup, HOLD) == "full")
	w.sup.lane, w.sup.pos = Lane.Bot, 4
	check("half: pos4 full-pulls", w.H.PullJob.KindFor(w.sup, HOLD) == "full")
end

-- The half pull's pace aims the neutrals HalfLag after the wave's body (a full pull's PaceLead before it): one more second
-- of HalfLag holds the puller about a second longer after the same hit.
do
	local function hold(lag)
		local line = livePull(function() return 0 end, nil, { reading = HOLD, halfLag = lag })
		return tonumber(field(line, "pz") or "0"), line
	end
	local one, l1 = hold(1)
	local two, l2 = hold(2)
	check("half pace: pk=half on the pull_job line", field(l1, "pk") == "half", l1)
	check("half pace: HalfLag 2 holds about 1 s more than HalfLag 1: " .. one .. " / " .. two, math.abs(two - one - 1) <= 0.2, l2)
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

-- An enemy hero beside the camp (the user's ptm1_A 4:21: a pull walked into the enemy offlaner): skipped, with its distance;
-- the same hero 1,500 away lets the pull start.
for _, case in ipairs({ { "enemy at the camp", Vector(-1600, -6600), "0" }, { "enemy 1,500 from the site", Vector(-1600, -8100), "1" } }) do
	local w = world({ reading = OUT })
	local enemy = MakeUnit({ pid = 10, team = 3, loc = case[2] })
	enemy.lane, enemy.pos = Lane.Bot, 3
	local out = run(w, 80)
	local choice = lines(out, "choice")
	local se = tonumber(field(choice[1], "se") or "")
	if case[3] == "0" then
		check(case[1] .. ": go=0 why=enemy-site, se within 1,200, no job", #choice == 1 and field(choice[1], "go") == "0"
			and field(choice[1], "why") == "enemy-site" and se ~= nil and se <= 1200 and #lines(out, "job") == 0, choice[1])
	else
		check(case[1] .. ": pull started, se logged over 1,200", #lines(out, "job") >= 1 and field(choice[1], "go") == "1"
			and se ~= nil and se > 1200, choice[1])
	end
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

-- An empty camp the team sees whole is not pulled, unless a spawn minute comes before the hit (pw3: `no-camp` 19 of 89
-- starts); out of sight, an empty box says nothing and the pull goes (the first test above).
do
	local w = world({ reading = OUT, visible = true })
	local out = run(w, 90)
	local choice = lines(out, "choice")
	check("empty, seen: no start, why=empty, the probe says nothing there in a visible box", #lines(out, "job") == 0 and #choice == 1
		and field(choice[1], "why") == "empty" and field(choice[1], "cn") == "0" and field(choice[1], "cv") == "1", choice[1])
	local s = { n = 0, seen = 0, hp = 0, vis = true, units = {} }
	check("empty, seen, a spawn minute before the hit: no gate", w.H.PullJob.CampGate(s, 58, 63) == nil and w.H.PullJob.CampGate(s, 61, 78) == "empty")
	-- One neutral left in a camp the team sees: not pulled (user 04/11/2026); two are; out of sight or a spawn before the
	-- hit says nothing.
	local one = { n = 1, seen = 1, hp = 300, vis = true, units = {} }
	local two = { n = 2, seen = 2, hp = 600, vis = true, units = {} }
	local fogged = { n = 1, seen = 1, hp = 300, vis = false, units = {} }
	check("one neutral, seen: why=one; two: no gate; out of sight or a spawn first: no gate", w.H.PullJob.CampGate(one, 61, 78) == "one"
		and w.H.PullJob.CampGate(two, 61, 78) == nil and w.H.PullJob.CampGate(fogged, 61, 78) == nil and w.H.PullJob.CampGate(one, 58, 63) == nil)
end

-- A camp the puller cannot take is not pulled: its estimated damage over the pull would leave less than StartReserve of
-- max HP. Eight neutrals (a stacked camp) against a single spawn's three, same puller (pw3_C_on_3 t=262.5, the one death:
-- 8 neutrals led alone; ~/.dotactl/logs/2026-11-03T01-32-12-pw3_C_on_3.log).
do
	local function camp(k)
		local w = world({ reading = OUT, visible = true })
		for i = 1, k do MakeNeutral({ x = SMALL.x + 20 * i, y = SMALL.y }).dps = 40 end
		local out = run(w, 80)
		return lines(out, "choice")[1], #lines(out, "job")
	end
	local stacked, jobsS = camp(8)
	local single, jobs1 = camp(3)
	check("stacked camp in sight: no start, why=camp-dmg, the probe counts its 8 neutrals", jobsS == 0 and field(stacked, "why") == "camp-dmg"
		and field(stacked, "cn") == "8" and field(stacked, "cv") == "1", stacked)
	check("single spawn: the same puller starts", jobs1 >= 1 and field(single, "go") == "1" and field(single, "cn") == "3", single)
end

-- A camp out of sight at the start (the API returns nothing, so the estimate is one spawn at DefaultDps) that the walk
-- finds stacked: the job ends `cancelled:camp-dmg` before the hit, and its line carries the camp it saw on the walk.
-- This is the in-game path for a fogged stacked camp like the pw3 death (review 2026-11-03-pull-camp-5f7d8a4 M1).
do
	local w = world({ reading = OUT })
	local seen
	local out = capture(function()
		while T < 120 and not (seen and not w.H.PullJob.Running(w.sup)) do
			if not seen and w.H.PullJob.Running(w.sup) then
				seen = T
				for i = 1, 8 do MakeNeutral({ x = SMALL.x + 20 * i, y = SMALL.y }).dps = 40 end
			end
			frame(w)
		end
	end)
	local pull = lines(out, "pull_job")[1]
	check("walk finds a stacked camp: cancelled:camp-dmg before the hit, with the walk's camp", seen ~= nil
		and field(pull, "why") == "cancelled:camp-dmg" and field(pull, "cn") == "8" and (field(pull, "label") or "travel") ~= "aggro", pull)
end

-- After the hit (slot 78.5) a neutral hits the puller from T=79 at `dps` while it has `hp` of 600. Returns whether it walked
-- towards our tower and the job's pull_job line.
local function hitAfterPull(hp, dps)
	local w = world({ reading = OUT })
	TOWERS_W[2][dota.Tower.Bot1] = MakeUnit({ pid = 90, team = 2, loc = Vector(3000, -5500) })
	local kobold = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	kobold.target = w.sup
	local bailed
	local out = capture(function()
		while T < 140 and not ((bailed or T > 79) and not w.H.PullJob.Running(w.sup)) do
			if T >= 79 and not bailed then kobold.dps, w.sup.hp, kobold.loc = dps, hp, Vector(w.sup.loc.x + 100, w.sup.loc.y) end
			local n0 = #ACTIONS
			frame(w)
			for i = n0 + 1, #ACTIONS do
				local a = ACTIONS[i]
				if a.pid == 5 and a.kind == "MoveToLocation" and a.args[1].x == 3000 then bailed = true end
			end
			if bailed then kobold.target = nil end
		end
	end)
	TOWERS_W[2][dota.Tower.Bot1] = nil
	return bailed, lines(out, "pull_job")[1]
end

-- About to die (60 HP, 40 dps): it steps back while hit, then the job ends `interrupted:bail` with the puller alive.
do
	local bailed, pull = hitAfterPull(60, 40)
	check("bail: the puller walked towards our tower while hit", bailed == true)
	check("bail: the job ended interrupted:bail, alive", field(pull, "why") == "interrupted:bail" and field(pull, "died") == "0", pull)
end

-- A puller with HP to spare keeps leading although the camp's dps over the whole lead would take it under the reserve:
-- pc1 bailed 12 times about 1 s after the hit at 58-100% HP (~/.dotactl/logs/2026-11-03T02-37-32-pc1_B_on_2.log t=590.3).
do
	local bailed, pull = hitAfterPull(330, 80)
	check("no bail with HP to spare: the lead goes on", not bailed and field(pull, "why") ~= "interrupted:bail", pull)
end

finish()
