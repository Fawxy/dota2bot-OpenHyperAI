-- Slice lane-control 2a (lane controller design s5.1-s5.3): the lever choice (fewest, then least dangerous levers that bring
-- the clash into the band without overshoot; a pull and a shove never together), the wave intent, the support's next
-- departure (the calendar stub) and the switch.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
TEAM_RADIANT, TEAM_DIRE = 2, 3
LANE_TOP, LANE_MID, LANE_BOT = 1, 2, 3
-- Telemetry on (for the break line fixture); every event in this file goes to a sink or is never fired.
FreshHumaniser({ Enable = false, Telemetry = { Enable = true } })
local Customize = package.loaded["bots/FunLib/custom_loader"]
local Ctl = require("bots/FunLib/humaniser/lane_control")

local function names(c)
	local out = {}
	for _, l in ipairs(c.levers) do out[#out + 1] = l.name end
	return table.concat(out, "+")
end
local function lv(name, effect, danger, why) return { name = name, effect = effect, danger = danger, who = "x", why = why } end

-- Choose: need is the clash past the target (positive: bring it back), band 150.
do
	local levers = { lv("predeny", -300, 1), lv("feed", -300, 2), lv("pull", -900, 3), lv("shove", 300, 2, "mode") }
	check("inside the band: no lever", names(Ctl.Choose(100, 150, levers)) == "")
	check("small need: the least dangerous lever", names(Ctl.Choose(350, 150, levers)) == "predeny")
	-- 700: predeny+feed leaves 100 (two levers); the pull alone leaves -200, past -150: overshoot, so the two small ones.
	check("no overshoot: two small levers beat a pull that passes the target", names(Ctl.Choose(700, 150, levers)) == "predeny+feed")
	-- 1000: the pull alone leaves 100, one lever.
	check("big need: the pull alone", names(Ctl.Choose(1000, 150, levers)) == "pull")
	local c = Ctl.Choose(3000, 150, levers)
	check("too big: the nearest set without overshoot, marked short", c.short and names(c) == "predeny+feed+pull")
	check("too big: what is left", c.left == 3000 - 1500)
	check("an unusable lever is never chosen", names(Ctl.Choose(1000, 150, { lv("pull", -900, 3, "no_sup"), lv("predeny", -300, 1) })) == "predeny")
	-- forward: shove only, and never with a pull.
	local fwd = { lv("shove", 300, 2), lv("pull", 900, 3) }
	check("forward: the shove", names(Ctl.Choose(-400, 150, fwd)) == "shove")
	check("pull and shove never together", names(Ctl.Choose(-1300, 150, { lv("shove", 300, 2), lv("pull", 900, 3), lv("x", 100, 1) })) ~= "shove+pull")
	check("no lever: short, need left", Ctl.Choose(500, 150, {}).short and Ctl.Choose(500, 150, {}).left == 500)
end

-- IntentOf.
do
	check("intent back", Ctl.IntentOf(200, 150, false) == "back")
	check("intent forward", Ctl.IntentOf(-200, 150, false) == "forward")
	check("intent hold", Ctl.IntentOf(100, 150, false) == "hold")
	check("reset before a departure", Ctl.IntentOf(0, 150, true) == "reset")
	check("reset: a lane well short of the target is let go", Ctl.IntentOf(-400, 150, true) == "forward")
end

-- Slice 3: the pull against the puller's calendar (YieldPast 1,600 at 3:00, +200 a minute).
do
	check("yield past: 1,600 at 3:00", Ctl.YieldPast(180) == 1600)
	check("yield past: 2,400 at 7:00", Ctl.YieldPast(420) == 2400)
	check("yield past: no less before 3:00", Ctl.YieldPast(60) == 1600)
	local stack = { kind = "stack", key = 3, claim = 195, leave = 215, back = 250, fixed = false }
	local rune = { kind = "rune", key = 360, claim = 300, leave = 345, back = 375, fixed = true }
	check("free: no refusal", Ctl.PullCalendar("free", nil, 2000, 212).why == nil and Ctl.PullCalendar("free", nil, 2000, 212).fit == "free")
	check("fits: no refusal", Ctl.PullCalendar("fits", rune, 2000, 302).why == nil)
	local r = Ctl.PullCalendar("clash", rune, 5000, 332)
	check("a rune trip is never traded", r.why == "away" and r.yld == nil and r.fit == "clash:rune")
	local y = Ctl.PullCalendar("clash", stack, 2000, 212)
	check("the lane needs it more: the pull takes the stack minute", y.why == nil and y.yld == 3)
	local k = Ctl.PullCalendar("clash", stack, 1100, 212)
	check("the stack keeps its minute", k.why == "stack" and k.yld == nil)
	stack.running = true
	check("a running stack is never taken", Ctl.PullCalendar("clash", stack, 5000, 212).why == "away")
end

-- The switch: off, Tick reads nothing (no LanePush call on a stub bot with no lane path).
do
	Customize.Ours = Customize.Ours or {}
	Customize.Ours.LaneControl = false
	local called = false
	local bot = { GetTeam = function() called = true return TEAM_RADIANT end }
	Ctl.Tick(bot)
	check("switch off: the bot is not read", not called)
	Customize.Ours.LaneControl = nil
end

-- Slice 2b: what the levers' owners read.
do
	Customize.Ours.LaneControl = true
	Customize.Ours.LaneControlDrive = true
	local now = 302
	DotaTime = function() return now end
	Ctl.Remember(TEAM_DIRE, LANE_TOP, { wave = 300, at = 302, rule = "R1", mode = "safe", intent = "back", levers = { "feed", "pull" }, who = { "core", "8" }, cx = 0, cy = 0 })
	check("current: the live decision", Ctl.Current(TEAM_DIRE, LANE_TOP) ~= nil and Ctl.Chosen(TEAM_DIRE, LANE_TOP, "feed") == true)
	check("chosen: a lever not in the set", Ctl.Chosen(TEAM_DIRE, LANE_TOP, "predeny") == false)
	check("chosen: another lane has no decision", Ctl.Chosen(TEAM_DIRE, LANE_MID, "feed") == nil)
	check("decision for the pulled wave", Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300) ~= nil and Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 270) == nil)
	local PullJob = require("bots/FunLib/humaniser/pull_job")
	check("pull: this support's pull", PullJob.CtlWants(Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300), 8))
	check("pull: another support's is not", not PullJob.CtlWants(Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300), 9))
	now = 334
	check("current: expired after the next read is due", Ctl.Current(TEAM_DIRE, LANE_TOP) == nil and Ctl.Chosen(TEAM_DIRE, LANE_TOP, "feed") == nil)
	check("decision for the wave outlives the live window", Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300) ~= nil)
	now = 310
	Customize.Ours.LaneControlDrive = false
	check("drive off: nothing read", Ctl.Current(TEAM_DIRE, LANE_TOP) == nil and Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300) == nil)
	Customize.Ours.LaneControlDrive = true
	Ctl.ResetCache()
	-- forward in safe mode takes the setup, never the shove.
	local levers = { lv("setup", 300, 1), lv("shove", 300, 2, "mode"), lv("predeny", -300, 1) }
	check("forward, safe: the setup", names(Ctl.Choose(-400, 150, levers)) == "setup")
	-- The shove's break: an enemy hero seen within 3,000 of the clash; none seen (out of vision) is no break (review H1).
	check("break: a seen enemy near", Ctl.EnemySeenNear({ { x = 2000, y = 0 } }, 0, 0, 3000))
	check("break: a seen enemy far", not Ctl.EnemySeenNear({ { x = 3500, y = 0 } }, 0, 0, 3000))
	check("break: none seen, no break", not Ctl.EnemySeenNear({}, 0, 0, 3000))
	-- Slice 3: the stack minute the live decision's pull takes.
	now = 212
	Ctl.Remember(TEAM_RADIANT, LANE_BOT, { wave = 210, at = 212, rule = "R1", mode = "safe", intent = "back", levers = { "pull" }, who = { "4" }, cx = 0, cy = 0, yields = 3 })
	check("yields: this support's minute", Ctl.YieldsStack(TEAM_RADIANT, LANE_BOT, 4, 3))
	check("yields: not another minute", not Ctl.YieldsStack(TEAM_RADIANT, LANE_BOT, 4, 5))
	check("yields: not another support", not Ctl.YieldsStack(TEAM_RADIANT, LANE_BOT, 3, 3))
	Ctl.Remember(TEAM_RADIANT, LANE_BOT, { wave = 240, at = 242, rule = "R1", mode = "safe", intent = "back", levers = { "pull" }, who = { "4" }, cx = 0, cy = 0 })
	now = 242
	check("yields: a later decision with no yield", not Ctl.YieldsStack(TEAM_RADIANT, LANE_BOT, 4, 3))
	Customize.Ours.LaneControlDrive = false
	check("yields: drive off, never", not Ctl.YieldsStack(TEAM_RADIANT, LANE_BOT, 4, 3))
	Customize.Ours.LaneControlDrive = true
	Ctl.ResetCache()
end

-- Their due wave absent (the tracker's resolution) refuses our pull this cycle (pull:ew), the other levers stay;
-- ewp reads whether Choose would have taken the pull without the skip.
do
	local function rej(levers)
		local out = {}
		for _, l in ipairs(levers) do if l.why then out[#out + 1] = l.name .. ":" .. l.why end end
		return table.concat(out, ";")
	end
	local function offer() return { lv("predeny", -300, 1), lv("feed", -300, 2), lv("pull", -900, 3), lv("setup", 300, 1), lv("shove", 300, 2, "mode") } end
	-- 1,000 back: the pull alone would be chosen; absent, the two small levers go instead and the line says pull:ew, ewp 1.
	local a = Ctl.MissingWave("a", "back", 1000, 150, offer())
	check("absent: no pull chosen, the other levers still work the need", names(a.choice) == "predeny+feed" and a.choice.short)
	check("absent: the pull refused ew", rej(a.levers) == "pull:ew;shove:mode")
	check("absent: the skip changed the set (ewp 1)", a.ewp == 1)
	-- 350 back: the pre-deny alone either way; the skip was redundant (ewp 0) but the refusal is still on the line.
	local b = Ctl.MissingWave("a", "back", 350, 150, offer())
	check("absent, small need: pre-deny, ewp 0", names(b.choice) == "predeny" and b.ewp == 0 and rej(b.levers) == "pull:ew;shove:mode")
	-- A pull already refused keeps its own reason (4a's @core_pull reads no_sup/away/stack) and ewp stays unset: the skip
	-- did nothing and the model was not asked.
	local unusable = offer()
	unusable[3].why = "no_sup"
	local u = Ctl.MissingWave("a", "back", 1000, 150, unusable)
	check("absent, no puller: the real refusal stays, no ewp", rej(u.levers) == "pull:no_sup;shove:mode" and u.ewp == nil and names(u.choice) == "predeny+feed")
	-- Present or unknown: the pull is chosen as before and ewp is unset.
	local p = Ctl.MissingWave("p", "back", 1000, 150, offer())
	check("present: the pull as before", names(p.choice) == "pull" and p.ewp == nil and rej(p.levers) == "shove:mode")
	check("unknown: the pull as before", names(Ctl.MissingWave("u", "back", 1000, 150, offer()).choice) == "pull")
	check("no schedule entry: the pull as before", names(Ctl.MissingWave(nil, "back", 1000, 150, offer()).choice) == "pull")
	-- The switch off: absent changes nothing.
	Ctl.SETTINGS.SkipPullOnMissingWave = false
	local off = Ctl.MissingWave("a", "back", 1000, 150, offer())
	check("skip off: the pull as before, ewp unset", names(off.choice) == "pull" and off.ewp == nil)
	Ctl.SETTINGS.SkipPullOnMissingWave = true
	-- A forward lane: the setup, with or without their wave (the pull is a back lever).
	check("absent, forward: the setup as before", names(Ctl.MissingWave("a", "forward", -400, 150, offer()).choice) == "setup")
	-- The tracker's rule (enemy_wave.ts Step): their wave's spot walks from their spawn (0, +1 along the path, 100 a second)
	-- towards our lead creep at 2,000: due at 17 (within 300), window 12..27, the base count read at 11, resolved at 27.
	-- `world(t)` gives our lead's path distance and the visible enemy lane creep count that second.
	local EW = require("bots/FunLib/humaniser/enemy_wave")
	local function track(to, world)
		local st = {}
		local res
		for t = 0, to do
			local lead, count = world(t)
			res = EW.Step(st, { now = t + 0.4, spawn = 0, dir = 1, speed = 100, lead = lead, count = count or 0 }, 30) or res
		end
		return st, EW.Take(st), res
	end
	local st, early = track(26, function() return 2000, 4 end)
	check("tracker: nothing resolved before the window ends", early == nil and st.track.ts == 0 and st.track.due == 17 and st.track.base == 4)
	-- Their previous wave (4 creeps) fights at our lead all along; the new one walks in at 20: the count rises by 4.
	local _, p, pr = track(27, function(t) return 2000, t >= 20 and 8 or 4 end)
	check("tracker: the count rises in the window: present, due 17", p ~= nil and p.ew == "p" and p.due == 17 and p.ts == 0)
	check("tracker: Step returns the resolution it makes", pr ~= nil and pr.ew == "p")
	-- The count never rises (their previous wave still there, 4 to 3 as it dies): absent.
	local st2, a = track(27, function(t) return 2000, t >= 20 and 3 or 4 end)
	check("tracker: no rise, our lead at the spot: absent", a ~= nil and a.ew == "a" and a.due == 17)
	check("tracker: the fact is taken once and the next wave is followed", EW.Take(st2) == nil and st2.track.ts == 30)
	-- A rise of one is not a wave (RiseMin 2).
	local _, one = track(27, function(t) return 2000, t >= 20 and 5 or 4 end)
	check("tracker: a rise of one is no wave", one ~= nil and one.ew == "a")
	-- The rise in the seconds before it came due (the history the window reaches back into), fallen back by D.
	local _, back = track(27, function(t) return 2000, (t >= 13 and t <= 15) and 6 or 4 end)
	check("tracker: a rise before due counts", back ~= nil and back.ew == "p")
	-- The base is the second before the window (11), not an earlier high count.
	local _, basehi = track(27, function(t) return 2000, t <= 10 and 9 or 4 end)
	check("tracker: an earlier high count is not the base", basehi ~= nil and basehi.ew == "a")
	-- Our creeps leave the spot once it is due (there 1 of 16 window seconds): unknown, nobody watching. In the absent case
	-- above they were there 11 of 16: the spot reaches within 300 of them at 17 and stops at them (the clamp) from 20.
	local _, gone = track(27, function(t) return t <= 17 and 2000 or 5000, 4 end)
	check("tracker: our creeps gone from the spot: unknown", gone ~= nil and gone.ew == "u" and gone.due == 17)
	-- No own creeps at all: never due, given up at 60 with no due second; the tracker catches up to the current wave (60),
	-- not the one already 30 s old.
	local st3, nobody = track(60, function() return nil, 0 end)
	check("tracker: never due, given up as unknown, caught up", nobody ~= nil and nobody.ew == "u" and nobody.due == nil and st3.track.ts == 60)
	-- Absent between reads breaks this wave's live decision's pull while its slot is unsettled (kind=break why=ew, beside
	-- the shove break: the mode, the intent and the ruleset's levers stay; the core's hold goes with the pull). A settled
	-- slot (the pull ran, was refused, cancelled or late, or is running) is left alone and nothing is logged.
	Ctl.ResetCache()
	Customize.Ours.LaneControl = true
	Customize.Ours.LaneControlDrive = true
	local Telemetry = require("bots/FunLib/humaniser/telemetry")
	local lines = {}
	Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local function decision() return { wave = 300, at = 302, rule = "R1", mode = "safe", intent = "back", levers = { "predeny", "pull", "hold" }, who = { "both", "8", "7" }, cx = 0, cy = 0, yields = 3 } end
	Ctl.Remember(TEAM_DIRE, LANE_TOP, decision())
	local PullJob = require("bots/FunLib/humaniser/pull_job")
	local settled = function() return true end
	local open = function() return false end
	check("pull break: a settled slot (finished, refused or running) is left alone, nothing logged", not Ctl.PullBreak(TEAM_DIRE, LANE_TOP, 320, 300, settled)
		and PullJob.CtlWants(Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300), 8) and #lines == 0)
	check("pull break: the previous wave's decision is not broken in a read second", not Ctl.PullBreak(TEAM_DIRE, LANE_TOP, 332, 330, open) and #lines == 0)
	local asked
	check("pull break: an unsettled pull is taken from this wave's decision", Ctl.PullBreak(TEAM_DIRE, LANE_TOP, 320, 300, function(pid, w) asked = { pid, w } return false end)
		and asked[1] == 8 and asked[2] == 300)
	local d = Ctl.DecisionFor(TEAM_DIRE, LANE_TOP, 300)
	check("pull break: the job no longer wanted; predeny stays, the hold goes with the pull, mode and intent unchanged, the stack minute given back",
		not PullJob.CtlWants(d, 8) and table.concat(d.levers, "+") == "predeny" and table.concat(d.who, "+") == "both" and d.mode == "safe" and d.intent == "back"
		and d.yields == nil and d.broke == "ew" and not Ctl.YieldsStack(TEAM_DIRE, LANE_TOP, 8, 3))
	check("pull break: one break line", #lines == 1 and lines[1]:find("ev=lane_ctl team=3 lane=1 kind=break wave=300 why=ew", 1, true) ~= nil, lines[1])
	check("pull break: nothing to break twice", not Ctl.PullBreak(TEAM_DIRE, LANE_TOP, 320, 300, open) and #lines == 1)
	check("pull break: no live decision", not Ctl.PullBreak(TEAM_DIRE, LANE_TOP, 340, 330, open))
	-- PullJob.Settled: the slot's wave, by its handled record or a running pull; a wave the job never reached is unsettled.
	PullJob.ResetCache()
	check("settled: a wave the job never reached is unsettled", not PullJob.Settled(8, 300))
	Telemetry.SetSink(nil)
	-- The fact the lane keeps: set by an absent read, aged out after SuspectFor; another lane knows nothing.
	Ctl.ResetCache()
	Ctl.NoteSuspect(TEAM_DIRE, LANE_TOP, { kind = "their_wave_missing", t = 302 })
	local sus = Ctl.Suspect(TEAM_DIRE, LANE_TOP, 330)
	check("suspect: their wave missing, within SuspectFor", sus ~= nil and sus.kind == "their_wave_missing" and sus.t == 302)
	check("suspect: another lane knows nothing", Ctl.Suspect(TEAM_DIRE, LANE_MID, 330) == nil)
	check("suspect: aged out", Ctl.Suspect(TEAM_DIRE, LANE_TOP, 302 + Ctl.SETTINGS.SuspectFor + 1) == nil)
	Ctl.ResetCache()
end

-- Slice 4a: who takes the pull lever (design s5.7's rule list). Before 6:00 an able support; from 6:00, or with the support
-- away or unable, the offlane pos3 when no enemy is missing near its walk and the lane gold it loses is at most 80.
do
	local function p(now, sup, core) return Ctl.PullerOf({ now = now, sup = sup, core = core }) end
	local S, C = { pid = 8 }, { pid = 7, missing = 0, loss = 30 }
	check("before 6:00: the able support", p(300, S, C).who == "8" and p(300, S, C).by == "sup")
	check("from 6:00: the pos3", p(360, S, C).who == "7" and p(360, S, C).by == "core")
	check("support away before 6:00: the pos3", p(300, { pid = 8, why = "away" }, C).by == "core")
	check("no support: the pos3", p(200, nil, C).by == "core")
	local m = p(400, S, { pid = 7, missing = 1, loss = 0 })
	check("an enemy missing near the walk: the support after all", m.by == "sup" and m.cwhy == "missing")
	local l = p(400, nil, { pid = 7, missing = 0, loss = 120 })
	check("too much lane gold lost, no support: no puller", l.by == nil and l.who == "" and l.why == "no_sup" and l.cwhy == "loss")
	local a = p(400, { pid = 8, why = "stack" }, { pid = 7, missing = 0 })
	check("no plan for the pos3, support refused: its refusal", a.by == nil and a.why == "stack" and a.cwhy == "no_plan")
	check("no core candidate, no support: no_sup", p(400, nil, nil).why == "no_sup")
	check("at the limit: the pos3", p(400, nil, { pid = 7, missing = 0, loss = 80 }).by == "core")
	-- User 07/11/2026: the lane's need lifts the limit (0.05 gold a unit past the band 150).
	check("limit: 80 inside the band", Ctl.CorePullLimit(100) == 80 and Ctl.CorePullLimit(nil) == 80)
	check("limit: 170 at a need of 1,950", Ctl.CorePullLimit(1950) == 170)
	check("a badly pushed lane: the pos3 pulls at a loss of 120", Ctl.PullerOf({ now = 400, n45 = 1950, core = { pid = 7, missing = 0, loss = 120 } }).by == "core")
end

finish()
