dofile(HARNESS_DIR .. "/lane_world.lua")
-- Drills (humaniser/drill.ts; master docs/proposals/2026-11-08-drills.md): Overrides.Drill picks a table entry; its cast
-- plays, the rest are benched, statues or lane-only; reps log ev=drill ph=rep once per team; roles log ph=role.
local RAD, DIRE = 2, 3

local function world(drill)
	local H = LaneFresh({ Enable = true }, { enable = true, skill = 1, telemetry = { Enable = true } })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = drill and { Drill = drill } or nil
	H.Drill.ResetCache()
	return H, Customize
end

local function hero(pid, team, pos, lane)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(0, 0, 0) })
	u.pos, u.lane = pos, lane
	return u
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	local r = {}
	for _, l in ipairs(printed) do if l:find("ev=drill ", 1, true) then table.insert(r, l) end end
	return r
end

local function field(line, k) return line and line:match("%f[%w]" .. k .. "=(%S+)") end

-- No drill: everyone plays, nobody is held, the stack keeps its trigger minutes, nothing is logged.
do
	local H = world(nil)
	local b = hero(0, RAD, 1, 3)
	check("no drill: plays", H.Drill.RoleOf(b) == "play" and not H.Drill.Held(b) and not H.Drill.LaneOnly(b) and not H.Overrides.LaneOnly(b))
	check("no drill: no forced reps", H.Drill.RepTimes("stack") == nil)
	check("no drill: no lines", #capture(function() H.Drill.Tick(b) end) == 0)
	local _, C = world("")
	check("empty name: no drill, no line", H.Drill.Name() == nil and #capture(function() H.Drill.Tick(b) end) == 0)
end

-- A knob drills replaced is logged once when set, and does nothing.
do
	local H, C = world(nil)
	C.Overrides = { Solo = 5, LaneOnly = false }
	local b = hero(0, RAD, 1, 3)
	local lines = capture(function() H.Drill.Tick(b) H.Drill.Tick(b) end)
	check("removed knob: one line", #lines == 1 and field(lines[1], "ph") == "removed" and field(lines[1], "name") == "Solo", lines[1])
	check("removed knob: no effect", H.Drill.RoleOf(b) == "play" and not H.Chooser.Benched(hero(5, DIRE, 1, 1)))
end

-- An unknown name logs once and runs no drill.
do
	local H = world("nope")
	local b = hero(0, RAD, 1, 3)
	local lines = capture(function() H.Drill.Tick(b) H.Drill.Tick(b) end)
	check("unknown drill: one line", #lines == 1 and field(lines[1], "ph") == "unknown" and field(lines[1], "name") == "nope", lines[1])
	check("unknown drill: plays", H.Drill.RoleOf(b) == "play")
end

-- hold: the Radiant pos5 is the cast (the pull), the Radiant pos1 lane-only with the wave hold, everyone else benched.
do
	local H = world("hold")
	local core = hero(0, RAD, 1, 3)
	local sup = hero(4, RAD, 5, 3)
	local mid = hero(2, RAD, 2, 2)
	local off = hero(7, DIRE, 3, 3)
	check("hold: pos5 cast, forced pull", H.Drill.RoleOf(sup) == "cast" and H.Drill.ForcedJob(sup) == "pull" and not H.Drill.LaneOnly(sup) and not H.Drill.LaneHold(sup))
	check("hold: pos1 lane-only with the hold", H.Drill.RoleOf(core) == "laneonly" and H.Drill.LaneOnly(core) and H.Drill.LaneHold(core) and not H.Drill.Held(core))
	check("hold: no forced job for the lane-only core", H.Drill.ForcedJob(core) == nil)
	check("hold: others benched, no hold", H.Drill.RoleOf(mid) == "bench" and H.Drill.RoleOf(off) == "bench" and not H.Drill.LaneHold(off))
end
do
	local H = world("lane-spot-statue")
	check("lane-spot-statue: no hold for the lane-only cast", not H.Drill.LaneHold(hero(0, RAD, 1, 3)))
end

-- Lever drills: the feed pair runs lane aggro for the lane-only cast (else lane-only skips the feed), the setup pair does
-- not; each pair differs only in the forced lever.
do
	local core = hero(0, RAD, 1, 3)
	local F, O, S = world("lever-feed"), world("lever-feed-off"), world("lever-setup")
	check("lever-feed: the lane-only cast runs lane aggro", F.Drill.LaneOnly(core) and F.Drill.LaneAggro(core))
	check("lever-feed: the Dire pos3 a statue in both arms (the feed orders an attack on a visible enemy hero)",
		F.Drill.RoleOf(hero(7, DIRE, 3, 3)) == "statue" and O.Drill.RoleOf(hero(7, DIRE, 3, 3)) == "statue" and not F.Drill.LaneAggro(hero(7, DIRE, 3, 3)))
	check("lever-setup: no lane aggro", S.Drill.LaneOnly(core) and not S.Drill.LaneAggro(core))
	check("lever-feed pair: the feed forced, its control none", F.Drill.Implied("ForceLever") == "r:bot=feed" and O.Drill.Implied("ForceLever") == "r:bot=none" and O.Drill.LaneAggro(core))
end

-- core-camp: the shipped CampForce default ("") lets the drill force trips; an explicit false (a --set) still wins. The
-- default was false, which hid the drill's CampForce.
do
	local H, Customize = world("core-camp")
	local Ov = require("bots/FunLib/humaniser/overrides")
	Customize.Overrides.CampForce = ""
	check("core-camp: the shipped default lets the drill force the trip", Ov.CampForce() == true)
	check("core-camp: pos1 and pos3 play, the rest benched", H.Drill.RoleOf(hero(0, RAD, 1, 3)) == "cast" and H.Drill.RoleOf(hero(2, RAD, 3, 1)) == "cast" and H.Drill.RoleOf(hero(3, RAD, 4, 1)) == "bench")
	Customize.Overrides.CampForce = false
	check("core-camp: an explicit false wins over the drill", Ov.CampForce() == false)
end

-- lane-spot-sentry: the Dire pos3 is held like a statue (never casts) but attacks an enemy hero that walks into its zone
-- (attack range 150 + both radii 24 + 0.5 s at 300 = 348 centre to centre), and only while it stands within that 0.5 s step
-- of its spot.
do
	local H = world("lane-spot-sentry")
	local core = hero(0, RAD, 1, 3)
	local off = hero(7, DIRE, 3, 3)
	check("sentry: held, never casts", H.Drill.RoleOf(off) == "sentry" and H.Drill.Held(off) and H.Chooser.HoldsCasts(off))
	check("sentry: the cast plays lane-only", H.Drill.RoleOf(core) == "cast" and H.Drill.LaneOnly(core))
	off.range = 150
	local spot = GetLaneFrontLocation(DIRE, 3, -300)
	off.loc = Vector(spot.x, spot.y)
	core.loc = Vector(spot.x + 360, spot.y)
	H.Drill.Hold(off)
	check("sentry: an enemy outside its zone is left alone, it sways as a statue", #ActionsOf(7, "AttackUnit") == 0 and #ActionsOf(7, "MoveToLocation") > 0)
	core.loc = Vector(spot.x + 340, spot.y)
	H.Drill.Hold(off)
	local at = ActionsOf(7, "AttackUnit")
	check("sentry: an enemy inside its zone is attacked", #at == 1 and at[1].args[1] == core)
	off.loc = Vector(spot.x + 200, spot.y)
	core.loc = Vector(spot.x + 300, spot.y)
	H.Drill.Hold(off)
	local back = ActionsOf(7, "MoveToLocation")
	check("sentry: past its step from the spot it walks back instead", #ActionsOf(7, "AttackUnit") == 1 and math.abs(back[#back].args[1].x - spot.x) <= 20)
end

-- lane-spot-statue: the Radiant pos1 is the cast (lane-only), the Dire pos3 a statue, everyone else benched.
do
	local H = world("lane-spot-statue")
	local core = hero(0, RAD, 1, 3)
	local sup = hero(4, RAD, 5, 3)
	local off = hero(7, DIRE, 3, 3)
	local mid = hero(6, DIRE, 2, 2)
	check("cast", H.Drill.RoleOf(core) == "cast" and not H.Drill.Held(core))
	check("cast lane-only", H.Drill.LaneOnly(core) and H.Overrides.LaneOnly(core))
	check("ally benched", H.Drill.RoleOf(sup) == "bench" and H.Drill.Held(sup) and not H.Drill.LaneOnly(sup))
	check("enemy pos3 statue", H.Drill.RoleOf(off) == "statue" and H.Drill.Held(off))
	check("enemy mid benched", H.Drill.RoleOf(mid) == "bench")
	check("statue and bench never cast", H.Chooser.HoldsCasts(off) and H.Chooser.HoldsCasts(sup))
	check("OHA's idle relocation skips statue and bench, not the cast", H.Chooser.HoldsIdle(off) and H.Chooser.HoldsIdle(sup) and not H.Chooser.HoldsIdle(core))
	-- A hero whose position is not known yet plays.
	local unknown = hero(9, DIRE, nil, 1)
	check("no position yet: plays", H.Drill.RoleOf(unknown) == "play")

	-- The statue walks 300 behind its own lane front and keeps a move order on, swaying between two points.
	off.loc = Vector(0, 0, 0)
	check("statue step taken", H.Drill.Hold(off))
	local mv = ActionsOf(7, "MoveToLocation")
	local spot = GetLaneFrontLocation(DIRE, 3, -300)
	local first = mv[#mv] and mv[#mv].args[1]
	check("statue walks to its lane spot", first ~= nil and math.abs(first.y - spot.y) < 1 and math.abs(first.x - spot.x) <= 20, first and (first.x .. "," .. first.y))
	off.loc = first
	H.Drill.Hold(off)
	mv = ActionsOf(7, "MoveToLocation")
	local second = mv[#mv].args[1]
	check("statue at its point sways to the other", math.abs(second.x - first.x) > 30, second.x .. " vs " .. first.x)
	check("statue never attacks", #ActionsOf(7, "AttackUnit") == 0)
	check("cast is not held", not H.Drill.Hold(core))

	-- Nothing is logged before the pregame (strategy time's clock reaches 0 before the pregame resets it to -90).
	GAME_STATE = 5
	T = 0
	check("no lines before the pregame", #capture(function() H.Drill.Tick(core) H.Drill.Tick(off) end) == 0)
	GAME_STATE = 8
	-- Role lines once per hero; rep lines once per rep from the team with a cast (Radiant), none from Dire.
	T = 1
	local lines = capture(function()
		for _ = 1, 3 do H.Drill.Tick(core) H.Drill.Tick(off) H.Drill.Tick(sup) end
		T = 31
		H.Drill.Tick(core) H.Drill.Tick(core)
	end)
	local roles, reps = {}, {}
	for _, l in ipairs(lines) do
		if field(l, "ph") == "role" then table.insert(roles, l) elseif field(l, "ph") == "rep" then table.insert(reps, l) end
	end
	check("one role line per hero", #roles == 3, #roles)
	check("role line fields", field(roles[2], "role") == "statue" and field(roles[2], "pid") == "7" and field(roles[2], "pos") == "3", roles[2])
	check("two reps logged", #reps == 2 and field(reps[1], "rep") == "1" and field(reps[2], "rep") == "2" and field(reps[2], "start") == "30", table.concat(reps, " / "))
	check("natural reps: input on, no forced context", field(reps[1], "input") == "on" and field(reps[1], "forces") == nil, reps[1])
end

-- stack: forced reps every third minute from 2:00; a control setting withholds every nth rep.
do
	local H = world("stack")
	local t = H.Drill.RepTimes("stack")
	check("stack reps from 120 every 180", t[1] == 120 and t[2] == 300 and t[3] == 480)
	check("another context is not forced", H.Drill.RepTimes("pull") == nil)
	H.Drill.TABLE.stack.rep.control = 3
	t = H.Drill.RepTimes("stack")
	check("control 3: the third rep withheld", t[1] == 120 and t[2] == 300 and t[3] == 660, t[3])
	local b = hero(4, RAD, 5, 3)
	T = 485
	local lines = capture(function() H.Drill.Tick(b) end)
	local rep
	for _, l in ipairs(lines) do if field(l, "ph") == "rep" then rep = l end end
	check("control rep logs input=off", field(rep, "rep") == "3" and field(rep, "input") == "off" and field(rep, "forces") == "stack", rep)
	H.Drill.TABLE.stack.rep.control = nil
end

-- lane-only (the old Overrides.LaneOnly): every hero is the cast and lane-only.
do
	local H = world("lane-only")
	for pos = 1, 5 do
		check("lane-only pos " .. pos, H.Drill.LaneOnly(hero(pos, RAD, pos, 1)) and H.Drill.LaneOnly(hero(pos + 5, DIRE, pos, 1)))
	end
end

-- Every table entry is complete.
do
	local H = world(nil)
	for name, e in pairs(H.Drill.TABLE) do
		check("entry " .. name, type(e.note) == "string" and e.cast ~= nil and e.others ~= nil and e.rep ~= nil and e.rep.every > 0, name)
	end
end

-- pull: the Radiant pos5 is the cast, a statue while no pull runs; only the pull job is asked; the minute's wave carries the
-- input, the :30 wave is the control.
do
	local H = world("pull")
	local sup = hero(4, RAD, 5, 3)
	local core = hero(0, RAD, 1, 3)
	check("pull: pos5 cast, not held", H.Drill.RoleOf(sup) == "cast" and not H.Drill.Held(sup) and not H.Chooser.Benched(sup))
	check("pull: idle statue, only the pull job", H.Drill.IdleStatue(sup) and H.Drill.ForcedJob(sup) == "pull" and not H.Drill.IdleStatue(core) and H.Drill.ForcedJob(core) == nil)
	check("pull: the minute's wave on, the :30 off, before the first none", H.Drill.ForcedAt("pull", 60) == "on" and H.Drill.ForcedAt("pull", 90) == "off"
		and H.Drill.ForcedAt("pull", 120) == "on" and H.Drill.ForcedAt("pull", 30) == "none" and H.Drill.ForcedAt("stack", 60) == nil)
	check("pull: the idle cast never casts and skips OHA's idle relocation", H.Chooser.HoldsCasts(sup) and H.Chooser.HoldsIdle(sup))
	sup.loc = Vector(0, 0, 0)
	check("pull: the idle cast takes the statue's step", H.Drill.Hold(sup) and #ActionsOf(4, "MoveToLocation") > 0)
	check("pull: with no job, the idle cast holds the bench's desire", H.Chooser.Decide(sup, "farm") == H.Chooser.SETTINGS.BenchDesire, tostring(H.Chooser.Decide(sup, "farm")))
	check("pull: a cast with no castIdle keeps OHA's desire", world("lane-spot").Chooser.Decide(core, "farm") == nil)
	-- drill pull ldr1 (~/.dotactl/logs/2026-11-07T18-07-29-drill_pull_ldr1.log, t=360): both benched mids walked to the 6:00 rune.
	check("pull: a benched mid is never the rune plan's mid", not H.RuneJob.MidWants(hero(2, RAD, 2, 2)))
	check("pull: no drill, nothing forced", world(nil).Drill.ForcedAt("pull", 60) == nil)
end

-- lane-still: no cast, every hero benched, no rep line.
do
	local H = world("lane-still")
	local b = hero(0, RAD, 1, 3)
	check("lane-still: benched", H.Drill.RoleOf(b) == "bench" and H.Drill.RoleOf(hero(9, DIRE, 5, 1)) == "bench")
	GAME_STATE = 8
	T = 40
	local reps = 0
	for _, l in ipairs(capture(function() H.Drill.Tick(b) end)) do if field(l, "ph") == "rep" then reps = reps + 1 end end
	check("lane-still: no rep line", reps == 0)
end

-- shove: the drill implies ForceShove r:bot, an explicit --set wins.
do
	local H, C = world("shove")
	check("shove: implies ForceShove", H.Overrides.Get("ForceShove") == "r:bot" and H.Drill.LaneOnly(hero(0, RAD, 1, 3)))
	-- drill shove ldr4 (~/.dotactl/logs/2026-11-07T18-21-47-drill_shove_ldr4.log): general.lua's default ForceShove = "" hid
	-- the drill's value; no shove swing ran.
	C.Overrides.ForceShove = ""
	check("shove: general.lua's empty default does not shadow the drill", H.Overrides.Get("ForceShove") == "r:bot")
	C.Overrides.Drill = nil
	check("shove: no drill, the empty default stays", H.Overrides.Get("ForceShove") == "")
	C.Overrides.Drill = "shove"
	C.Overrides.ForceShove = "all"
	check("shove: --set wins", H.Overrides.Get("ForceShove") == "all")
end

-- Slice threat: a statue with a spot list stands at the rep's spot, cycling (threat-missing: the Dire pos5 by the pos3's pull
-- camp, benched, by Dire's offlane camp, its lane); before rep 1 and with no list, its lane. One ph=spot line per rep.
do
	local H = world("threat-missing")
	local sup = hero(8, DIRE, 5, 1)
	local core = hero(2, RAD, 3, 1)
	check("threat-missing: pos3 lane-only cast, Dire pos5 statue", H.Drill.LaneOnly(core) and H.Drill.RoleOf(sup) == "statue")
	local seen = {}
	for _, t in ipairs({ 10, 40, 130, 220, 310, 400 }) do
		T = t
		seen[#seen + 1] = H.Drill.SpotOf(sup)
	end
	check("spots: lane before rep 1, then the list cycling", table.concat(seen, " ") == "lane pull:r:off bench pull:d:off lane pull:r:off", table.concat(seen, " "))
	GAME_STATE = 8
	T = 130
	sup.loc = Vector(0, 0, 0)
	local lines = capture(function() H.Drill.Hold(sup) H.Drill.Hold(sup) end)
	local mv = ActionsOf(8, "MoveToLocation")
	local to = mv[#mv] and mv[#mv].args[1]
	check("bench spot: walks to its fountain", to ~= nil and to.x > 6000 and to.y > 6000, to and (to.x .. "," .. to.y))
	check("bench spot: one spot line for the rep", #lines == 1 and field(lines[1], "spot") == "bench" and field(lines[1], "rep") == "2", lines[1])
	T = 40
	local n0 = #ActionsOf(8, "MoveToLocation")
	local l2 = capture(function() H.Drill.Hold(sup) end)
	check("pull spot with no camp known: the statue stands, the line has no point", #ActionsOf(8, "MoveToLocation") == n0 and #l2 == 1 and field(l2[1], "x") == nil, l2[1])
	check("no spot list: a statue logs no spot line", #capture(function() world("lane-spot-statue") H.Drill.Hold(hero(7, DIRE, 3, 3)) end) == 0)
end

finish()
