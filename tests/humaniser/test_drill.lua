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

-- retreat-even (even-fight round 2): its chasers keep OHA's spells and items on a chase rep, as the lethal drops in games need;
-- on its control rep and in an entry without `chaserCasts` a chaser is cast-held like any held hero.
do
	local H = world("retreat-even")
	local chaser = hero(9, DIRE, 3, 3)
	T = 65
	check("chaserCasts: a chaser on a chase rep may cast", not H.Chooser.HoldsCasts(chaser))
	T = 245
	check("chaserCasts: on the control rep (4) it is held", H.Chooser.HoldsCasts(chaser))
	local H2 = world("retreat-chase2")
	local other = hero(9, DIRE, 3, 3)
	T = 65
	check("chaserCasts: retreat-chase2's chaser on a chase rep never casts", H2.Chooser.HoldsCasts(other))
end

-- retreat-linger (slice retreat, plan 2026-11-10-retreat-read-bars): on a chase rep the chaser hits as retreat-chase until the cast
-- is at or under 45% HP (ph=linger_go), backs off to 1,100 from her (outside our T1's reach + 100), and the window's clock starts
-- when it first stands at 1,000 or more (ph=linger). The window ends on contact (her within its attack range + 100), after 20 s,
-- or `no_standoff` when it never got out; it runs on past the rep's end. Once per rep.
do
	local dota = require("bots/ts_libs/dota/index")
	local function setup(towerAt, chaserAt)
		local H = world("retreat-linger")
		local core = hero(0, RAD, 1, 3)
		core.loc = Vector(-1700, -5000, 0)
		core.hp = 40
		local chaser = hero(9, DIRE, 3, 3)
		chaser.loc = chaserAt or Vector(-1300, -5000, 0) -- 400 from her, still on her
		chaser.range = 150
		if towerAt then TOWERS_W[RAD][dota.Tower.Bot1].loc = towerAt end
		T = 65 -- rep 1 (a chase rep)
		return H, core, chaser
	end
	local function lastMove(pid) local mv = ActionsOf(pid, "MoveToLocation") return mv[#mv] and mv[#mv].args[1] end

	local H, core, chaser = setup()
	T = 105 -- late in rep 1, as the logged games trigger
	local lines = capture(function() H.Drill.Hold(chaser) end)
	local to = lastMove(9)
	check("linger: at 40% the chaser backs off to the point 1,100 from the cast instead of attacking",
		#ActionsOf(9, "AttackUnit") == 0 and to ~= nil and math.abs(to.x - (-600)) < 2 and math.abs(to.y + 5000) < 2, to and (to.x .. "," .. to.y))
	check("linger: the trigger logs linger_go (HP share, distance, the rep's end) and no window start yet", #lines == 1 and field(lines[1], "ph") == "linger_go" and tonumber(field(lines[1], "thp")) == 0.4 and field(lines[1], "d") == "400" and field(lines[1], "rend") == "120", lines[1])

	-- Contact counts only once it has stood off: at 700 from her the clock has not started, so stepping in is no contact.
	chaser.loc = Vector(-1000, -5000, 0)
	T = 107
	local l1 = capture(function() H.Drill.Hold(chaser) end)
	check("linger: the clock does not start before the stand-off", #l1 == 0)
	chaser.loc = Vector(-600, -5000, 0)
	T = 108
	local l2 = capture(function() H.Drill.Hold(chaser) end)
	check("linger: the window starts when it first stands 1,000 or more off", #l2 == 1 and field(l2[1], "ph") == "linger" and field(l2[1], "d") == "1100", l2[1])
	-- The rep ends at 120: the window runs on into the control rep (no wait behind the T1).
	T = 121
	local n = #ActionsOf(9, "MoveToLocation")
	core.loc = Vector(-1700, -5000, 0)
	chaser.loc = Vector(-300, -5000, 0)
	capture(function() H.Drill.Hold(chaser) end)
	check("linger: past the rep's end the window still holds the chaser out", #ActionsOf(9, "MoveToLocation") == n + 1 and #ActionsOf(9, "AttackUnit") == 0)
	T = 125
	core.loc = Vector(-800, -5000, 0)
	chaser.loc = Vector(-600, -5000, 0)
	local l3 = capture(function() H.Drill.Hold(chaser) end)
	check("linger: contact after the stand-off ends the window `contact`; in a control rep the chaser then waits, it does not attack", #ActionsOf(9, "AttackUnit") == 0 and #l3 == 1 and field(l3[1], "ph") == "linger_end" and field(l3[1], "res") == "contact" and tonumber(field(l3[1], "secs")) == 17 and field(l3[1], "dmax") == "1400" and field(l3[1], "dend") == "200", l3[1])

	-- In a chase rep contact makes the chaser attack, and it does not stand off again that rep.
	local hc, cc, kc = setup(nil, Vector(-600, -5000, 0))
	capture(function() hc.Drill.Hold(kc) end)
	T = 66
	cc.loc = Vector(-800, -5000, 0)
	local l5 = capture(function() hc.Drill.Hold(kc) end)
	check("linger: contact in a chase rep: the window ends and the chaser attacks", #ActionsOf(9, "AttackUnit") == 1 and #l5 == 1 and field(l5[1], "res") == "contact", l5[1])
	cc.loc = Vector(-1700, -5000, 0)
	kc.loc = Vector(-600, -5000, 0)
	T = 68
	hc.Drill.Hold(kc)
	check("linger: once per rep: the chaser keeps attacking after contact", #ActionsOf(9, "AttackUnit") == 2)

	-- Never gets out: no_standoff after 20 s.
	local h2, c2, k2 = setup()
	capture(function() h2.Drill.Hold(k2) end)
	T = 86
	local l4 = capture(function() h2.Drill.Hold(k2) end)
	check("linger: a chaser that never stands off ends no_standoff after 20 s", #l4 == 1 and field(l4[1], "res") == "no_standoff", l4[1])

	check("linger: a window that never stood off logs no dmin (it is measured from the stand-off)", field(l4[1], "dmin") == nil, l4[1])

	-- Out of sight (night, fog): the window keeps running and holds the last stand-off point; it does not end `lost` and no
	-- location is read off the unseen hero (rtlng1b: lua_error in Drill.Hold on the nil location, three times).
	local hu, cu, ku = setup(nil, Vector(-600, -5000, 0))
	T = 105
	capture(function() hu.Drill.Hold(ku) end)
	cu.GetLocation = function() return nil end
	ku.loc = Vector(-300, -5000, 0)
	T = 110
	local lu = capture(function() hu.Drill.Hold(ku) end)
	local mu = lastMove(9)
	check("linger: unseen, the window goes on and the chaser holds the last stand-off point", #lu == 0 and #ActionsOf(9, "AttackUnit") == 0 and mu ~= nil and math.abs(mu.x - (-600)) < 2, mu and mu.x)
	T = 129
	local lt = capture(function() hu.Drill.Hold(ku) end)
	check("linger: unseen to the end: `timeout` with the unseen seconds", #lt == 1 and field(lt[1], "res") == "timeout" and tonumber(field(lt[1], "uns")) == 24, lt[1])
	local hv, cv, kv = setup()
	cv.GetLocation = function() return nil end
	cv.hp = 666
	check("linger: a cast out of sight starts no window (thp 666 was a bad read)", #capture(function() hv.Drill.Hold(kv) end) == 0)

	local h3, c3, k3 = setup(nil, Vector(-700, -5000, 0))
	c3.hp = 80
	h3.Drill.Hold(k3)
	check("linger: above 45% HP it attacks as retreat-chase does", #ActionsOf(9, "AttackUnit") == 1 and lastMove(9) == nil)

	local hb, cb, kb = setup(Vector(-500, -5300, 0))
	hb.Drill.Hold(kb)
	local tb = lastMove(9)
	local tw = TOWERS_W[RAD][dota.Tower.Bot1].loc
	local dTw = tb and math.sqrt((tb.x - tw.x) ^ 2 + (tb.y - tw.y) ^ 2)
	check("linger: a point inside our T1's reach is pulled out to its reach + 100 (844 + 100)", tb ~= nil and math.abs(dTw - 944) < 2, dTw)
end

-- Rigs (slice drill-rig): every rig entry's setup lists end in a step that stands (a hero is placed only there), name only
-- spots the rig defines, and attack heroes the rep lists; rep kinds and release are non-empty.
do
	local H = world(nil)
	for name, e in pairs(H.Drill.TABLE) do
		local r = e.rig
		if r ~= nil then
			check(name .. ": rig has reps and a release", #r.reps > 0 and #r.release.modes > 0 and r.timeout > 0 and type(r.switch) == "string")
			-- A rep that cannot finish its setup inside its own length overlaps the next; one that ends after the window is not a
			-- rep of the rule at all, so rep 1 must end inside it.
			check(name .. ": rep 1 ends inside the rig's window, and the ready timeout fits the rep", type(r.window) == "number" and e.rep.from + e.rep.every <= r.window and r.timeout < e.rep.every, r.window)
			for _, rr in ipairs(r.reps) do
				for k, steps in pairs(rr.setup) do
					local last = steps[#steps]:match("^(%a+)")
					check(name .. "/" .. rr.name .. "/" .. k .. ": the last step stands", last == "stand" or last == "leave" or last == "front" or last == "lasthit" or last == "hitback", steps[#steps])
					for _, s in ipairs(steps) do
						local verb, a = s:match("^(%a+)%s*(%S*)")
						if verb == "stand" or verb == "walk" or (verb == "leave" and a ~= "") then
							check(name .. "/" .. rr.name .. ": spot " .. a .. " defined", r.spots[a] ~= nil)
						elseif verb == "attack" then
							check(name .. "/" .. rr.name .. ": attack target listed", rr.setup[a] ~= nil and tonumber(s:match("until hp ([%d%.]+)$")) ~= nil, s)
						elseif verb == "burst" then
							check(name .. "/" .. rr.name .. ": burst target listed, seconds and spells given", rr.setup[a] ~= nil and s:match("^burst %S+ for [%d%.]+ using %S") ~= nil, s)
						elseif verb == "wait" then
							check(name .. "/" .. rr.name .. ": the hero waited for is listed", rr.setup[a] ~= nil, s)
						else
							check(name .. "/" .. rr.name .. ": known step " .. s, verb == "heal" or verb == "buy" or verb == "sell" or verb == "leave" or verb == "front" or verb == "lasthit" or verb == "hitback")
						end
					end
				end
			end
		end
	end
end

local KINDS = { "purchase", "courier", "buyback", "levelup", "items", "abilities" }
local function ownsAny(H, u) for _, k in ipairs(KINDS) do if H.Drill.Owns(u, k) then return k end end return nil end
-- Every kind but level-ups, which retreat-heal-items keeps for its heroes (tested on its own).
local function ownsAll(H, u) for _, k in ipairs(KINDS) do if k ~= "levelup" and not H.Drill.Owns(u, k) then return false end end return true end

-- A drill without a rig leaves OHA's purchases, courier, level-ups and casts alone, for its cast too.
do
	local Hs = world("retreat-heal")
	local cast = hero(0, RAD, 1, 3)
	check("no rig: the cast is a cast and OHA keeps every entry point for it", Hs.Drill.RoleOf(cast) == "cast" and ownsAny(Hs, cast) == nil)
	local Hr = world("retreat-heal-items")
	check("the same kind of hero is owned once the rig drill is the active one", ownsAll(Hr, hero(4, RAD, 5, 3)))
	local Hn = world(nil)
	check("no drill: OHA keeps every entry point", ownsAny(Hn, hero(4, RAD, 5, 3)) == nil)
	package.loaded["bots/FunLib/custom_loader"].Overrides = { Drill = "retreat-heal-items" }
	Hn.Drill.ResetCache()
	check("no drill: the same hero is owned as soon as a rig drill is on", ownsAll(Hn, hero(4, RAD, 5, 3)))
end

-- A rig rep end to end (retreat-heal-items, rep 1 `salve`): the cast heals and buys at its fountain, walks to its spot; the
-- attacker waits until the cast stands there, hits it to 25%, leaves; ready then holds and the cast is released into our
-- retreat only, with OHA's item and ability use still off. A rep whose checks never hold times out invalid and stays held.
do
	local dota = require("bots/ts_libs/dota/index")
	local function rigWorld(over)
		local H, C = world("retreat-heal-items")
		for k, v in pairs(over or {}) do C.Overrides[k] = v end
		local cast = hero(4, RAD, 5, 3)
		local atk = hero(7, DIRE, 3, 3)
		local mid = hero(2, RAD, 2, 2)
		cast.maxhp, cast.hp, cast.items = 100, 100, {}
		atk.maxhp, atk.hp = 100, 100
		cast.loc = Vector(-6619, -6336, 0)
		atk.loc = Vector(6928, 6372, 0)
		cast.ActionImmediate_PurchaseItem = function(self, name) self.items[0] = { name = name } return 0 end
		cast.GetGold = function() return 600 end
		cast.ActionImmediate_SellItem = function(self, it) for s, v in pairs(self.items) do if v.name == it:GetName() then self.items[s] = nil end end end
		ACTIONS = {}
		return H, cast, atk, mid
	end
	-- Each hero ticks as its own team (each team's bots run in their own VM; GetUnitList answers from CURRENT_TEAM).
	local function tick(H, ...) for _, u in ipairs({ ... }) do CURRENT_TEAM = u.team H.Drill.Tick(u) if H.Drill.Held(u) then H.Drill.Hold(u) end end CURRENT_TEAM = 2 end
	local function lastMoveTo(pid)
		local mv = ActionsOf(pid, "MoveToLocation")
		return mv[#mv] and mv[#mv].args[1]
	end
	local function readyLines(lines) local r = {} for _, l in ipairs(lines) do if field(l, "ph") == "ready" then table.insert(r, l) end end return r end

	local H, cast, atk, mid = rigWorld()
	check("rig: roles (cast, actor, bench)", H.Drill.RoleOf(cast) == "cast" and H.Drill.RoleOf(atk) == "actor" and H.Drill.RoleOf(mid) == "bench")
	check("rig: nothing of OHA's runs for the cast or the actor, in any kind, before the first rep and in setup; a benched hero keeps all", ownsAll(H, cast) and ownsAll(H, atk) and ownsAny(H, mid) == nil)
	local Hk = H.Drill.TABLE["retreat-heal-items"].rig
	check("rig: retreat-heal-items keeps level-ups for the cast and the attacker, and owns the rest", Hk.keeps ~= nil and not H.Drill.Owns(cast, "levelup") and not H.Drill.Owns(atk, "levelup") and H.Drill.Owns(cast, "purchase") and H.Drill.Owns(atk, "purchase"))
	Hk.keeps = nil
	check("rig: an entry without keeps owns level-ups for the cast and the actor", H.Drill.Owns(cast, "levelup") and H.Drill.Owns(atk, "levelup"))
	Hk.keeps = { "levelup" }
	check("rig: Chooser.HoldsCasts alone holds the cast in setup and the actor, for items and abilities",
		H.Chooser.HoldsCasts(cast, true) and H.Chooser.HoldsCasts(cast) and H.Chooser.HoldsCasts(atk, true) and H.Chooser.HoldsCasts(atk))
	T = 30
	check("rig: the cast is held before the first rep", H.Drill.Held(cast) and H.Chooser.HoldsCasts(cast, true))
	T = 61
	-- Frame 1 tries the buy, frame 2 sees the salve held and moves on.
	local lines = capture(function() tick(H, cast, atk) tick(H, cast, atk) end)
	check("rig: full HP at the fountain, so heal ends at once, the buy lands and the cast walks to its spot", cast.items[0] and cast.items[0].name == "item_flask" and lastMoveTo(4) ~= nil)
	local spot = lastMoveTo(4)
	check("rig: the cast spot is logged once with its tower distances", (function()
		for _, l in ipairs(lines) do if field(l, "ph") == "spot" and field(l, "spot") == "cast" then return tonumber(field(l, "rt")) ~= nil end end
	end)())
	-- The attacker reaches `near` but the cast is not standing yet: it waits, no attack.
	local near = lastMoveTo(7)
	atk.loc = Vector(near.x, near.y, 0)
	tick(H, atk)
	tick(H, atk)
	check("rig: the attacker does not attack before the cast stands at its spot", #ActionsOf(7, "AttackUnit") == 0)
	local toward = lastMoveTo(7)
	check("rig: meanwhile it walks to the cast's spot (a respawned attacker must find the cast again)", toward ~= nil and math.abs(toward.x - spot.x) < 1 and math.abs(toward.y - spot.y) < 1)
	cast.loc = Vector(spot.x, spot.y, 0)
	tick(H, cast, atk)
	check("rig: the cast stands, the attacker attacks it", #ActionsOf(7, "AttackUnit") > 0 and ActionsOf(7, "AttackUnit")[1].args[1] == cast)
	check("rig: still in setup, nothing ready", #readyLines(capture(function() tick(H, cast) end)) == 0 and H.Drill.Held(cast))
	cast.hp = 24
	local hits = #ActionsOf(7, "AttackUnit")
	tick(H, cast, atk)
	check("rig: at 24%, under the ready bar but over the attack's 20%, the attack goes on (fix5: regen over the bar)", #ActionsOf(7, "AttackUnit") == hits + 1)
	cast.hp = 19
	tick(H, cast, atk)
	local wait = lastMoveTo(7)
	check("rig: at 19% the attacker leaves for its fountain", wait ~= nil and math.sqrt((wait.x - spot.x) ^ 2 + (wait.y - spot.y) ^ 2) > 1600)
	check("rig: the attacker still near: not ready (clear)", #readyLines(capture(function() tick(H, cast) end)) == 0)
	cast.hp = 30
	check("rig: HP latched: regen back over the bar while the attacker walks off still counts (fix5)", #readyLines(capture(function() tick(H, cast) end)) == 0)
	-- r1: the attacker leaving stepped into fog 490 off; out of sight is not gone until its last sighting is 6 s old.
	atk.GetLocation = function() return nil end
	LAST_SEEN[7] = { location = Vector(spot.x + 490, spot.y, 0), time_since_seen = 0.3 }
	check("rig: the attacker in fog 490 off, seen 0.3 s ago: not ready (clear)", #readyLines(capture(function() tick(H, cast) end)) == 0)
	atk.GetLocation = nil
	LAST_SEEN[7].time_since_seen = 6
	atk.loc = Vector(wait.x, wait.y, 0)
	T = 80
	local r = readyLines(capture(function() tick(H, atk, cast) end))
	check("rig: ready once, ok=1, var=salve", #r == 1 and field(r[1], "ok") == "1" and field(r[1], "var") == "salve" and field(r[1], "secs") == "20", r[1])
	check("rig: the ready line carries the rep's end, the window and the released modes without idle", field(r[1], "rend") == "195" and field(r[1], "win") == "600" and field(r[1], "rel") == "retreat", r[1])
	check("rig: released: not held, retreat runs, laning gets 0, farm holds idle at 0.5", not H.Drill.Held(cast) and H.Chooser.Decide(cast, "laning") == 0 and H.Chooser.Decide(cast, "farm") == 0.5 and H.Drill.RigDesire(cast, "retreat") == nil)
	-- The path every mode file takes (test_rig_entry_points.lua): Chooser.Gate answers for a released cast before OHA's desire.
	check("rig: released: a mode file's Gate keeps OHA's desire for a listed mode and gives 0 for an unlisted one", H.Chooser.Gate(cast, "retreat", function() return 0.7 end)() == 0.7 and H.Chooser.Gate(cast, "laning", function() return 0.7 end)() == 0)
	-- fix6: Valve kept farm active at desire 0 and OHA's farm Think ran; a released cast's farm Think is ours: it stands
	-- where its idle spell began, and a later spell (after a retreat walked it home) stands there, not back at the release.
	local relAt = Vector(cast.loc.x, cast.loc.y, 0)
	ACTIONS = {}
	check("rig: released: farm Think is ours, it stands still", H.Chooser.Bench(cast) == true and lastMoveTo(4) ~= nil and math.abs(lastMoveTo(4).x - relAt.x) < 30)
	T = T + 5
	cast.loc = Vector(-6619, -6336, 0)
	ACTIONS = {}
	H.Chooser.Bench(cast)
	check("rig: released: a later idle spell stands where the cast is now (the fountain)", lastMoveTo(4) ~= nil and math.abs(lastMoveTo(4).x - -6619) < 30)
	cast.loc = relAt
	T = T - 5
	check("rig: released: OHA's items and spells stay off (not listed)", H.Chooser.HoldsCasts(cast, true) and H.Chooser.HoldsCasts(cast, false))
	-- A release lists what runs: items and the courier here (keeps is lifted so level-ups follow the release too). Everything unlisted stays owned, and in setup nothing is released.
	local release = H.Drill.TABLE["retreat-heal-items"].rig.release
	local unlisted = { "purchase", "buyback", "abilities", "levelup" }
	check("rig: released, nothing listed: every kind stays owned but the kept level-ups", ownsAll(H, cast) and ownsAll(H, atk) and not H.Drill.Owns(cast, "levelup"))
	release.items, release.also = true, { "courier" }
	H.Drill.TABLE["retreat-heal-items"].rig.keeps = nil
	local listedOk = not H.Drill.Owns(cast, "items") and not H.Drill.Owns(cast, "courier")
	for _, k in ipairs(unlisted) do listedOk = listedOk and H.Drill.Owns(cast, k) end
	check("rig: released: a listed kind runs for the cast, each unlisted one stays owned", listedOk)
	check("rig: the release never frees the actor", ownsAll(H, atk))
	check("rig: released, Chooser.HoldsCasts holds the unlisted kind only, for the cast (by itself, with no second gate)", H.Chooser.HoldsCasts(cast, false) and not H.Chooser.HoldsCasts(cast, true))
	check("rig: the listed items run in OHA's item use and the unlisted abilities stay off", not H.Chooser.HoldsCasts(cast, true) and H.Chooser.HoldsCasts(cast, false))
	check("rig: ready logs once per rep", #readyLines(capture(function() tick(H, cast) end)) == 0)
	T = 211
	capture(function() tick(H, cast, atk) end)
	check("rig: the next rep holds the cast again, and owns every kind again although the release lists some", H.Drill.Held(cast) and ownsAll(H, cast))
	release.items, release.also = nil, nil
	H.Drill.TABLE["retreat-heal-items"].rig.keeps = { "levelup" }

	-- The attacker's VM never sees the cast's own setup state (rig1, 12/11/2026: the Dire actor waited all game): it attacks
	-- once it sees the cast standing at the cast's spot, though the cast has not ticked in this world.
	local spotOf = spot
	local Hv, cv, av = rigWorld()
	T = 61
	av.loc = Vector(spotOf.x + 500, spotOf.y, 0)
	cv.loc = Vector(spotOf.x + 400, spotOf.y, 0)
	capture(function() tick(Hv, av) tick(Hv, av) end)
	check("rig VMs: the cast 400 off its spot: no attack", #ActionsOf(7, "AttackUnit") == 0)
	cv.loc = Vector(spotOf.x + 20, spotOf.y, 0)
	capture(function() tick(Hv, av) end)
	check("rig VMs: the cast seen at its spot: the attacker attacks with no state from the cast's VM", #ActionsOf(7, "AttackUnit") == 1)

	-- rig2 (12/11/2026): OHA gives an enemy hero its estimated position (3 by default), so the attacker finds the cast by
	-- where it stands, not by position: a cast whose position reads 3 to the attacker is still attacked; a benched hero
	-- elsewhere is not.
	local Hp, cp, ap, mp = rigWorld()
	T = 61
	cp.pos = 3
	mp.loc = Vector(spotOf.x + 2000, spotOf.y, 0)
	ap.loc = Vector(spotOf.x + 500, spotOf.y, 0)
	cp.loc = Vector(spotOf.x + 20, spotOf.y, 0)
	capture(function() tick(Hp, ap) tick(Hp, ap) end)
	local at = ActionsOf(7, "AttackUnit")
	check("rig: the attacker finds the cast by its spot, whatever position it reads", #at >= 1 and at[1].args[1] == cp)

	-- Host on: the same release frees every mode and OHA's items and spells.
	local Hh, ch, ah = rigWorld({ DrillHost = true })
	T = 61
	tick(Hh, ch, ah)
	tick(Hh, ch, ah)
	check("rig host: in setup the cast still owns every kind", Hh.Drill.Held(ch) and ownsAll(Hh, ch))
	local sp = lastMoveTo(4)
	ch.loc = Vector(sp.x, sp.y, 0)
	ch.hp = 20
	local w = Hh.Drill.TABLE["retreat-heal-items"]
	ah.loc = Vector(sp.x + 5000, sp.y, 0)
	-- The attacker's step list is skipped straight to its last (it is placed where it stands at its wait point).
	capture(function() for _ = 1, 4 do tick(Hh, ch, ah) local m = lastMoveTo(7) if m then ah.loc = Vector(m.x, m.y, 0) end end end)
	check("rig host: released with no mode gate and casts free", w ~= nil and not Hh.Drill.Held(ch) and Hh.Drill.RigDesire(ch, "farm") == nil and Hh.Drill.RigHoldsCasts(ch, true) == nil)
	check("rig host: released, OHA's items and abilities are free, but purchases, courier and buyback stay owned (the rig's gold)",
		not Hh.Drill.Owns(ch, "items") and not Hh.Drill.Owns(ch, "abilities") and Hh.Drill.Owns(ch, "purchase") and Hh.Drill.Owns(ch, "courier") and Hh.Drill.Owns(ch, "buyback"))
	check("rig host: the actor still owns every kind", ownsAll(Hh, ah))

	-- Rep 2 (`tango`) never gets its tango (the buy fails): at the timeout the rep is invalid, logged with the failing check.
	local Ht, ct, at = rigWorld()
	ct.ActionImmediate_PurchaseItem = function() return 1 end
	T = 211
	local buys = {}
	local function grab(ls, ph) for _, l in ipairs(ls) do if field(l, "ph") == ph then table.insert(buys, l) end end end
	grab(capture(function() tick(Ht, ct, at) end), "buy")
	T = 211.5
	grab(capture(function() tick(Ht, ct, at) end), "buy")
	T = 212.2
	grab(capture(function() tick(Ht, ct, at) end), "buy")
	check("rig buy: retried once a second while not held, the result logged", #buys == 2 and field(buys[1], "step") == "item_tango" and field(buys[1], "res") == "1", #buys)
	check("rig buy: the cast waits at its fountain meanwhile", lastMoveTo(4) == nil)
	T = 221.5
	tick(Ht, ct, at)
	local s2 = lastMoveTo(4)
	check("rig buy: after 10 s it gives up and the cast takes its spot", s2 ~= nil)
	ct.loc = Vector(s2.x, s2.y, 0)
	ct.hp = 20
	at.loc = Vector(s2.x + 5000, s2.y, 0)
	local waits = {}
	for _, l in ipairs(capture(function() for _ = 1, 4 do tick(Ht, ct, at) local m = lastMoveTo(7) if m then at.loc = Vector(m.x, m.y, 0) end end end)) do
		if field(l, "ph") == "wait" then table.insert(waits, field(l, "fail")) end
	end
	check("rig wait: each change of the failing check logged once, ending on holds", #waits >= 1 and waits[#waits] == "holds", table.concat(waits, ","))
	T = 211 + 111
	local rt = readyLines(capture(function() tick(Ht, ct) end))
	check("rig timeout: an invalid rep never releases a kind", ownsAll(Ht, ct))
	check("rig timeout: ok=0 fail=holds, the cast stays held", #rt == 1 and field(rt[1], "ok") == "0" and field(rt[1], "fail") == "holds" and Ht.Drill.Held(ct), rt[1])
end


-- retreat-chase: a chaser waits behind its own T1 on control reps (user 10/11/2026), not in its fountain, and chases on odd reps.
do
	local H = world("retreat-chase")
	local dota = require("bots/ts_libs/dota/index")
	local core = hero(0, RAD, 1, 3)
	local chaser = hero(9, DIRE, 3, 3)
	chaser.loc = Vector(0, 0, 0)
	local t1 = TOWERS_W[DIRE][dota.Tower.Bot1]
	T = 120.5 -- rep 2 (control)
	check("chase wait: the chaser is held", H.Drill.RoleOf(chaser) == "chaser" and H.Drill.Held(chaser))
	H.Drill.Hold(chaser)
	local mv = ActionsOf(9, "MoveToLocation")
	local to = mv[#mv] and mv[#mv].args[1]
	local fx, fy = 6928, 6372
	local d1 = to and math.sqrt((to.x - t1.loc.x) ^ 2 + (to.y - t1.loc.y) ^ 2)
	local dF = to and math.sqrt((to.x - fx) ^ 2 + (to.y - fy) ^ 2)
	check("chase wait: on a control rep it walks to 350 behind its own T1, not to the fountain", to ~= nil and math.abs(d1 - 350) < 5 and dF > 1000, to and (to.x .. "," .. to.y))
end

-- Slice hit-back's rig (retreat-hitback), rebuilt off the lane: the cast stands at the side spot; `far` is ready only on a
-- hit from 100-300 past its trade reach at 90%+ HP, `behind` only 16+ points under its hitter; the rep supplies the creep-aggro
-- fact (`RigCreepAggro`); the far hitter attacks from 500 without stepping in.
do
	local dota = require("bots/ts_libs/dota/index")
	local H = world("retreat-hitback")
	local cast, d3, r5, d4 = hero(1, RAD, 1, dota.Lane.Bot), hero(7, DIRE, 3, dota.Lane.Top), hero(5, RAD, 5, dota.Lane.Bot), hero(8, DIRE, 4, dota.Lane.Bot)
	for _, u in ipairs({ cast, d3, r5, d4 }) do u.maxhp, u.hp, u.hitBy = 100, 100, {} end
	-- Seed 8's cast is a melee Sven: reach 150 + 2 x 24 + 100 = 298.
	cast.range = 150
	cast.loc, r5.loc = Vector(-6619, -6336, 0), Vector(-6619, -6336, 0)
	d3.loc, d4.loc = Vector(6928, 6372, 0), Vector(6928, 6372, 0)
	CREEPS[2], CREEPS[3] = {}, {}
	ACTIONS = {}
	local function tick(...) for _, u in ipairs({ ... }) do CURRENT_TEAM = u.team H.Drill.Tick(u) if H.Drill.Held(u) then H.Drill.Hold(u) end end CURRENT_TEAM = 2 end
	local function lastMoveTo(pid) local mv = ActionsOf(pid, "MoveToLocation") return mv[#mv] and mv[#mv].args[1] end
	local function ready(lines) for _, l in ipairs(lines) do if field(l, "ph") == "ready" then return l end end end
	local function waitFail(lines) local f for _, l in ipairs(lines) do if field(l, "ph") == "wait" then f = field(l, "fail") end end return f end
	local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

	-- Rep 1 `far`.
	T = 5
	check("hitback rig: the rep's creep-aggro fact is supplied (far: true)", H.Drill.RigCreepAggro() == true)
	capture(function() tick(cast) end)
	local side = lastMoveTo(1)
	check("hitback rig: the cast walks to the side spot, off the lane", side ~= nil and math.abs(side.y - -5000) > 300, side and (side.x .. "," .. side.y))
	cast.loc = Vector(side.x, side.y, 0)
	capture(function() tick(cast) end)
	-- The far hitter comes in from the east, 1,500 off; it walks to 500 from the cast on that line rather than into its range.
	d4.loc = Vector(side.x + 1500, side.y, 0)
	ACTIONS = {}
	capture(function() tick(d4) tick(d4) end)
	local goal = lastMoveTo(8)
	-- on2: a hitter already beside the cast (it arrived first, or stood there the rep before) backs off to 500 before its first hit.
	d4.loc = Vector(side.x + 230, side.y, 0)
	ACTIONS = {}
	capture(function() tick(d4) tick(d4) end)
	local back = lastMoveTo(8)
	check("hitback rig: a far hitter 230 from the cast backs off to 500 rather than hitting from in reach",
		back ~= nil and math.abs(dist(back, cast.loc) - 500) < 60 and #ActionsOf(8, "AttackUnit") == 0, back and dist(back, cast.loc))
	d4.loc = Vector(side.x + 1500, side.y, 0)
	ACTIONS = {}
	capture(function() tick(d4) tick(d4) end)
	check("hitback rig: the far hitter walks to 500 from the cast on its own line, not into its attack range",
		goal ~= nil and math.abs(dist(goal, cast.loc) - 500) < 60 and goal.x > side.x and #ActionsOf(8, "AttackUnit") == 0, goal and dist(goal, cast.loc))
	d4.loc = Vector(side.x + 500, side.y, 0)
	ACTIONS = {}
	capture(function() tick(d4) end)
	check("hitback rig: at 500 it attacks", #ActionsOf(8, "AttackUnit") == 1 and ActionsOf(8, "AttackUnit")[1].args[1] == cast)
	-- Released, the cast walks in on it; the hitter keeps attacking from where it stands, not walking off to 500 again.
	cast.loc = Vector(side.x + 300, side.y, 0)
	ACTIONS = {}
	capture(function() tick(d4) end)
	check("hitback rig: once in place the hitter keeps attacking as the cast walks in", #ActionsOf(8, "AttackUnit") == 1 and #ActionsOf(8, "MoveToLocation") == 0)
	cast.loc = Vector(side.x, side.y, 0)

	check("hitback rig far: standing, not hit: not ready (hit)", waitFail(capture(function() tick(cast) end)) == "hit")
	d4.loc = Vector(side.x + 350, side.y, 0)
	cast.hitBy[d4] = T
	check("hitback rig far: hit from 52 past its reach (in reach of the plain trade's walk): not ready (past)", waitFail(capture(function() tick(cast) end)) == "past")
	d4.loc = Vector(side.x + 500, side.y, 0)
	cast.hp = 85
	check("hitback rig far: from 202 past, but at 85% HP: not ready (hplow)", waitFail(capture(function() tick(cast) end)) == "hplow")
	cast.hp = 93
	local r = ready(capture(function() tick(cast) end))
	check("hitback rig far: hit from 202 past its reach at 93%: ready, the distance on the line", r ~= nil and field(r, "ok") == "1" and field(r, "var") == "far" and field(r, "d") == "202", r)
	cast.hitBy[d4] = nil

	-- Rep 2 `behind`: the cast is hit to 72% at the side spot; ready only once 16 points under its hitter.
	T = 125
	cast.hp = 100
	check("hitback rig behind: at full HP the cast is not placed yet (stands until 72%)", waitFail(capture(function() tick(cast) tick(cast) end)) == "setup")
	cast.hp = 72
	capture(function() tick(cast) tick(cast) end)
	d3.loc = Vector(side.x + 150, side.y, 0)
	d3.hp = 85
	cast.hitBy[d3] = T
	check("hitback rig behind: 13 points under its hitter: not ready (behind)", waitFail(capture(function() tick(cast) end)) == "behind")
	d3.hp = 95
	r = ready(capture(function() tick(cast) end))
	check("hitback rig behind: 23 points under its hitter in reach: ready", r ~= nil and field(r, "ok") == "1" and field(r, "var") == "behind", r)
	cast.hitBy[d3] = nil

	T = 245
	check("hitback rig: the free control supplies the fact false", H.Drill.RigCreepAggro() == false)

	CREEPS[2], CREEPS[3] = {}, {}
	local Hn = world(nil)
	check("no drill: no creep-aggro fact, the game decides", Hn.Drill.RigCreepAggro() == nil)
end

-- tower-prehit's ready check: an own tower near the cast attacking an enemy lane creep within the distance.
do
	local H = world("tower-prehit")
	local bot = hero(0, RAD, 1, 3)
	local function unit(team, x, o)
		local u = { team = team, loc = Vector(x, 0, 0), alive = true }
		function u:GetTeam() return self.team end
		function u:GetLocation() return self.loc end
		function u:IsAlive() return self.alive end
		function u:IsNull() return false end
		function u:IsCreep() return o.creep end
		function u:IsHero() return o.hero end
		return u
	end
	local creep = unit(DIRE, 600, { creep = true, hero = false })
	local tower = { target = creep }
	function tower:GetAttackTarget() return self.target end
	bot.GetNearbyTowers = function() return { tower } end
	check("towerCreep: our tower on an enemy creep 600 off: holds at 700", H.Drill.TowerOnCreep(bot, 700))
	check("towerCreep: not at 500", not H.Drill.TowerOnCreep(bot, 500))
	tower.target = unit(DIRE, 300, { creep = false, hero = true })
	check("towerCreep: a hero is not a creep", not H.Drill.TowerOnCreep(bot, 700))
	tower.target = unit(RAD, 300, { creep = true, hero = false })
	check("towerCreep: our own creep does not count", not H.Drill.TowerOnCreep(bot, 700))
	tower.target = nil
	check("towerCreep: a tower attacking nothing", not H.Drill.TowerOnCreep(bot, 700))
	-- One cast per lane: a cast standing at its spot is ready though the other two casts are still walking.
	local H3 = world("tower-prehit")
	local c1, c2, c3 = hero(0, RAD, 1, 3), hero(1, RAD, 2, 2), hero(2, RAD, 3, 1)
	for _, c in ipairs({ c1, c2, c3 }) do
		c.maxhp, c.hp = 100, 100
		c.GetNearbyTowers = function() return { tower } end
	end
	tower.target = unit(DIRE, 300, { creep = true, hero = false })
	ACTIONS = {}
	T = 31
	local function tick3(...) for _, u in ipairs({ ... }) do CURRENT_TEAM = u.team H3.Drill.Tick(u) if H3.Drill.Held(u) then H3.Drill.Hold(u) end end CURRENT_TEAM = 2 end
	tick3(c1, c2, c3)
	local mv = ActionsOf(0, "MoveToLocation")
	local spot = mv[#mv] and mv[#mv].args[1]
	check("tower-prehit: each cast walks to its own spot", spot ~= nil and ActionsOf(1, "MoveToLocation")[1] ~= nil)
	c1.loc = Vector(spot.x, spot.y, 0)
	tower.target.loc = Vector(spot.x + 300, spot.y, 0)
	local lines = capture(function() tick3(c1, c2, c3) tick3(c1, c2, c3) end)
	local ready = {}
	for _, l in ipairs(lines) do if field(l, "ph") == "ready" then ready[tonumber(field(l, "pid"))] = field(l, "ok") end end
	check("tower-prehit: the placed cast is ready while the other casts walk; they are not", ready[0] == "1" and ready[1] == nil and ready[2] == nil, ready)
	check("tower-prehit: released, laning is free and idle holds at the rig's 0.3, under laning's 0.369 at level 8 to 11",
		H3.Drill.RigDesire(c1, "laning") == nil and H3.Drill.RigDesire(c1, "farm") == 0.3)
	-- Next rep with the lane's tower dead: the cast waits on `notower`, not `towercreep`.
	c1.GetNearbyTowers = function() return {} end
	T = 61
	local fails = {}
	for _, l in ipairs(capture(function() tick3(c1, c2, c3) T = 61.5 tick3(c1, c2, c3) end)) do
		if field(l, "pid") == "0" and field(l, "fail") ~= nil then fails[#fails + 1] = field(l, "fail") end
	end
	check("tower-prehit: a dead tower fails notower", fails[#fails] == "notower", fails)

	local t = H.Drill.TABLE["tower-prehit"].rig
	check("tower-prehit: execution rig on PreHit with the towerCreep check, one cast per lane", t.half == "execution" and t.switch == "PreHit" and t.reps[1].ready.towerCreep == 700 and #H.Drill.TABLE["tower-prehit"].cast.r == 3)
end

-- kill-reach's ready checks (slice trade-reach): a low enemy hero past the cast's trade reach (298 for a 150-range hero with
-- 24 hulls), and the enemy heroes within 1,200.
do
	local H = world("kill-reach")
	local bot = hero(0, RAD, 1, 3)
	bot.range = 150
	local low = hero(8, DIRE, 4, 3)
	local other = hero(7, DIRE, 3, 3)
	low.hp, low.maxhp, low.loc = 25, 100, Vector(650, 0, 0)
	other.hp, other.maxhp, other.loc = 100, 100, Vector(5000, 0, 0)
	local old = GetUnitList
	local mate = hero(4, RAD, 5, 3)
	mate.loc = Vector(1400, 0, 0)
	-- UnitType EnemyHeroes is 8, AlliedHeroes 2 (their enum fallbacks); the cast is in its own list.
	GetUnitList = function(k) if k == 2 then return { bot, mate } end return { low, other } end
	local ok, n = H.Drill.LowFacts(bot, { 0.35, 100, 550 })
	check("kill-reach: a 25% hero 352 past reach is low; one foe within 1,200", ok == true and n == 1, tostring(ok) .. " " .. tostring(n))
	low.hp = 50
	ok = H.Drill.LowFacts(bot, { 0.35, 100, 550 })
	check("kill-reach: at 50% it is not", ok == false)
	low.hp, low.loc = 25, Vector(1100, 0, 0)
	ok = H.Drill.LowFacts(bot, { 0.35, 100, 550 })
	check("kill-reach: 802 past reach it is not", ok == false)
	low.loc, other.loc = Vector(650, 0, 0), Vector(1000, 0, 0)
	local a
	ok, n, a = H.Drill.LowFacts(bot, nil)
	check("kill-reach: two foes within 1,200; the pos5 1,400 off and the cast itself are no ally near", n == 2 and a == 0, tostring(n) .. " " .. tostring(a))
	mate.loc = Vector(1100, 0, 0)
	ok, n, a = H.Drill.LowFacts(bot, nil)
	check("kill-reach: the pos5 1,100 off is an ally near", a == 1, a)
	GetUnitList = old
	local t = H.Drill.TABLE["kill-reach"].rig
	check("kill-reach: execution rig on KillReach, two reach reps to one outnumbered control", t.half == "execution" and t.switch == "KillReach" and #t.reps == 3 and t.reps[3].ready.foes == 2)
	-- The spots' offsets on one anchor (they resolve within 100 of these, ph=spot, except where marked in the rig's comment):
	-- the control's pos3 over 200 from the Lich's spot (the pos5's attack takes the enemy nearest it) with a margin, and
	-- within 1,200 of the cast with a margin.
	local sp = t.spots
	local function dx(a, b) return math.abs(sp[a][2] - sp[b][2]) end
	check("kill-reach: the pos3 300+ from the Lich's spot, under 1,100 from the cast", dx("foe", "low") >= 300 and dx("foe", "side") <= 1100, tostring(dx("foe", "low")) .. " " .. tostring(dx("foe", "side")))
end

-- burst-read (slice burst-truth): the actor refills mana before it walks in, casts its listed spells as they come up (in
-- list order, never one it cannot cast), lets a channel run 0.3 s, attacks between casts, and stops after 6 s; the cast,
-- released to idle, traces the read and its HP for 12 s from ready. The truth the rig gives is only as good as this order.
do
	local H = world("burst-read")
	local cast = hero(2, RAD, 2, 2)
	local actor = hero(7, DIRE, 2, 2)
	cast.maxhp, cast.hp = 600, 600
	actor.maxhp, actor.hp, actor.maxmana, actor.maxMana, actor.mana = 500, 500, 400, 400, 120
	actor.estDamage = 548
	cast.loc = Vector(-6619, -6336, 0)
	actor.loc = Vector(6928, 6372, 0)
	local function spell(name) return { name = name, down = false, IsNull = function() return false end, GetName = function(self) return self.name end, GetLevel = function() return 2 end, IsFullyCastable = function(self) return not self.down end } end
	local flames, fe, other = spell("oracle_purifying_flames"), spell("oracle_fortunes_end"), spell("oracle_fates_edict")
	actor.abilities = { [0] = fe, [1] = flames, [2] = other }
	ACTIONS = {}
	local function tick(...) for _, u in ipairs({ ... }) do CURRENT_TEAM = u.team H.Drill.Tick(u) if H.Drill.Held(u) then H.Drill.Hold(u) end end CURRENT_TEAM = 2 end
	local function lastMove(pid) local mv = ActionsOf(pid, "MoveToLocation") return mv[#mv] and mv[#mv].args[1] end
	local function lines(ph, ls) local r = {} for _, l in ipairs(ls) do if field(l, "ph") == ph then table.insert(r, l) end end return r end
	T = 31
	tick(cast, actor)
	tick(cast, actor)
	local m = lastMove(7)
	check("burst-read: an unhurt actor at 30% mana stays at its fountain (heal waits for mana)", m == nil or (math.abs(m.x - 6928) < 1 and math.abs(m.y - 6372) < 1))
	actor.mana = 400
	tick(actor)
	tick(actor)
	local foe = lastMove(7)
	check("burst-read: at full mana it walks off toward the cast's side", foe ~= nil and foe.x < 0)
	local side = lastMove(2)
	cast.loc = Vector(side.x, side.y, 0)
	actor.loc = Vector(foe.x, foe.y, 0)
	T = 40
	local ls = capture(function() tick(cast, actor) tick(cast, actor) end)
	local e = ActionsOf(7, "UseAbilityOnEntity")
	check("burst-read: in place, it casts the first listed spell it holds on the cast, Fortune's End not first", #e == 1 and e[1].args[1] == flames and e[1].args[2] == cast, #e)
	check("burst-read: the cast is released, and the cast line names the spell", #lines("ready", ls) == 1 and field(lines("ready", ls)[1], "ok") == "1" and field(lines("cast", ls)[1], "spell") == "oracle_purifying_flames")
	actor.casting = true
	T = 40.6
	tick(actor)
	check("burst-read: no new order while its cast point runs", #ActionsOf(7, "UseAbilityOnEntity") == 1 and #ActionsOf(7, "AttackUnit") == 0)
	actor.casting, flames.down = nil, true
	tick(actor)
	e = ActionsOf(7, "UseAbilityOnEntity")
	check("burst-read: Flames cooling, the next listed spell (Fortune's End), never the unlisted Fate's Edict", #e == 2 and e[2].args[1] == fe)
	fe.down, actor.channeling = true, true
	T = 40.8
	tick(actor)
	T = 41.0
	tick(actor)
	check("burst-read: a channel runs 0.3 s with no new order", #ActionsOf(7, "AttackUnit") == 0)
	T = 41.2
	tick(actor)
	check("burst-read: after 0.3 s the next order lands; nothing castable, so an attack", #ActionsOf(7, "AttackUnit") == 1 and ActionsOf(7, "AttackUnit")[1].args[1] == cast)
	actor.channeling = nil
	flames.down = false
	T = 42
	tick(actor)
	check("burst-read: Flames up again is cast again", #ActionsOf(7, "UseAbilityOnEntity") == 3)
	T = 46.1
	ACTIONS = {}
	tick(actor)
	tick(actor)
	local home = lastMove(7)
	check("burst-read: 6 s after its first order it stops and leaves", #ActionsOf(7, "UseAbilityOnEntity") == 0 and #ActionsOf(7, "AttackUnit") == 0 and home ~= nil and home.x > 6000)
	-- The trace: from ready (T 40) every 0.25 s for 12 s.
	cast.hp = 410
	local tr = {}
	for t = 47, 51.9, 0.05 do T = t for _, l in ipairs(lines("trace", capture(function() tick(cast) end))) do table.insert(tr, l) end end
	check("burst-read: trace carries the read and HP", #tr > 0 and field(tr[1], "est") == "548" and field(tr[1], "hp") == "410" and field(tr[1], "foe") ~= nil)
	check("burst-read: trace every 0.25 s (a 0.05 s frame: every 0.3 s)", #tr >= 16 and #tr <= 20, #tr)
	T = 52.5
	check("burst-read: none 12 s after ready", #lines("trace", capture(function() tick(cast) end)) == 0)
end

-- sight-probe (slice rig-sight): `sees` and `unseen` read the cast team's sight of an enemy key at its stand point, `after`
-- holds ready until the actor has had time to walk there, and ph=wait / ph=ready carry `sight` and `hl`; ph=grid at ready.
do
	local H = world("sight-probe")
	local cast = hero(0, RAD, 1, 3)
	local actor = hero(8, DIRE, 4, 1)
	cast.loc = Vector(-6619, -6336, 0)
	actor.loc = Vector(6928, 6372, 0)
	ACTIONS = {}
	local function tick(...) for _, u in ipairs({ ... }) do CURRENT_TEAM = u.team H.Drill.Tick(u) if H.Drill.Held(u) then H.Drill.Hold(u) end end CURRENT_TEAM = 2 end
	local function lastMove(pid) local mv = ActionsOf(pid, "MoveToLocation") return mv[#mv] and mv[#mv].args[1] end
	local function lines(ph, ls) local r = {} for _, l in ipairs(ls) do if field(l, "ph") == ph then table.insert(r, l) end end return r end
	local function place(u) local m = lastMove(u.pid) u.loc = Vector(m.x, m.y, 0) end
	local t = H.Drill.TABLE["sight-probe"].rig
	check("sight-probe: four reps, open sees d4, trees, far and high want it unseen, each after 20 s", #t.reps == 4 and t.reps[1].ready.sees[1] == "d4"
		and t.reps[2].ready.unseen[1] == "d4" and t.reps[3].ready.unseen[1] == "d4" and t.reps[4].ready.unseen[1] == "d4" and t.reps[1].ready.after == 20)
	HEIGHT = function() return 3 end
	T = 1
	local ls = capture(function() tick(cast, actor) tick(cast, actor) place(cast) place(actor) tick(cast, actor) tick(cast, actor) end)
	local w = lines("wait", ls)
	check("sight-probe: before 20 s the cast waits `early`, the actor seen at its spot", field(w[#w], "fail") == "early" and field(w[#w], "sight") == "d4:1", w[#w])
	T = 21
	ls = capture(function() tick(cast, actor) end)
	local rd, gr = lines("ready", ls)[1], lines("grid", ls)[1]
	check("sight-probe: open, seen: ready, sight d4:1, the cast's height level", field(rd, "ok") == "1" and field(rd, "sight") == "d4:1" and field(rd, "hl") == "3", rd)
	check("sight-probe: the grid line at ready, 33 or 34 cells a side, 100 apart", gr ~= nil and field(gr, "vg"):match("^%-?%d+,%-?%d+,3[34],3[34],100,") ~= nil and field(gr, "vr") == "1800" and field(gr, "vu") ~= nil, gr)
	-- Rep 2 (trees): the actor out of sight there.
	T = 61
	tick(cast, actor)
	tick(cast, actor)
	place(actor)
	local trees = Vector(actor.loc.x, actor.loc.y, 0)
	actor.hiddenFrom = setmetatable({}, { __index = function() return true end })
	FOGGED = function(v) return math.abs(v.x - trees.x) < 300 and math.abs(v.y - trees.y) < 300 end
	T = 82
	ls = capture(function() tick(cast, actor) end)
	rd = lines("ready", ls)[1]
	check("sight-probe: trees, fogged: ready, sight d4:0", field(rd, "ok") == "1" and field(rd, "sight") == "d4:0", rd)
	-- Rep 3 (far): the actor stands in sight, so `unseen` fails until the timeout.
	T = 121
	tick(cast, actor)
	tick(cast, actor)
	place(actor)
	actor.hiddenFrom = nil
	T = 142
	ls = capture(function() tick(cast, actor) end)
	check("sight-probe: far but seen: waits `unseen`", field(lines("wait", ls)[1], "fail") == "unseen" and field(lines("wait", ls)[1], "sight") == "d4:1", ls[1])
	actor.loc = Vector(6928, 6372, 0)
	FOGGED = nil
	T = 150
	tick(cast, actor)
	T = 171.5
	ls = capture(function() tick(cast) end)
	rd = lines("ready", ls)[1]
	check("sight-probe: its spot in sight and nobody there (sight 2): invalid at the timeout", field(rd, "ok") == "0" and field(rd, "fail") == "unseen" and field(rd, "sight") == "d4:2", rd)
	HEIGHT, FOGGED = nil, nil
end

-- support-kill-reach (slice support-lane-fight): the spots against a 600-range support's reaches. `low`'s bands are past the
-- core's reach (600 + 48 + 100 = 748): the bar rep's Lich stands inside the support's harass reach (948, so under 200 past),
-- the reach rep's past it and inside its commit's walk (1,548, so 200 to 800 past).
do
	local H = world("support-kill-reach")
	local t = H.Drill.TABLE["support-kill-reach"].rig
	check("support-kill-reach: execution rig on SupportLaneFight, cast the Radiant pos5", t.half == "execution" and t.switch == "SupportLaneFight"
		and H.Drill.TABLE["support-kill-reach"].cast.r[1] == 5 and #t.reps == 3 and t.reps[3].ready.foes == 2)
	local sp = t.spots
	local function dx(a, b) return math.abs(sp[a][2] - sp[b][2]) end
	local past = function(d) return d - 748 end
	check("support-kill-reach: the bar rep's Lich inside the harass reach, inside its band", past(dx("low", "side")) <= 200 and past(dx("low", "side")) >= t.reps[1].ready.low[2])
	check("support-kill-reach: the reach rep's Lich past the harass reach, inside the walk and its band",
		past(dx("far", "side")) > 200 and dx("far", "side") <= 1548 and past(dx("far", "side")) <= t.reps[2].ready.low[3])
	check("support-kill-reach: the actor's away spot over 1,200 from the cast", dx("away", "side") > 1200)
	check("support-kill-reach: the pos3 300+ from the Lich's spot, under 1,200 from the cast", dx("foe", "low") >= 300 and dx("foe", "side") < 1200)
	check("support-kill-reach: the actor stops over the trade's 25% cut", t.reps[1].setup.r1[2] == "attack d4 until hp 0.33")
	check("support-kill-reach: in the control the actor waits for the pos3 before it hits", t.reps[3].setup.r1[2] == "wait d3" and t.reps[3].setup.r1[3] == "attack d4 until hp 0.33")
	check("support-kill-reach: the pos3 beyond the actor's 200 target pick from the Lich", dx("foe", "low") > 250)
end

-- lane-trade (plan trade-from-the-stand step 2): the enemy actor's three kinds. Rep 1 `stand` holds its last-hit place and
-- never attacks, a dying creep or a hitter beside it; rep 2 `lasthit` walks up to one of our creeps its next two hits kill
-- (not one they do not, not one far off its place) and walks back once it dies; rep 3 `hitback` also attacks the cast while
-- the cast hits it, stops 2 s after the last hit, and does not chase past its leash. The released cast's watch logs each
-- of its attacks on an enemy hero once and each creep attack on it once.
do
	local H = world("lane-trade")
	local Lane = require("bots/ts_libs/dota/index").Lane
	local cast = hero(1, RAD, 2, Lane.Mid)
	local actor = hero(7, DIRE, 2, Lane.Mid)
	cast.maxhp, cast.hp, cast.range = 600, 600, 550
	actor.maxhp, actor.hp, actor.range, actor.dmg = 600, 600, 380, 50
	CURRENT_TEAM = DIRE
	local place = GetLaneFrontLocation(DIRE, Lane.Mid, -(380 - 50))
	CURRENT_TEAM = RAD
	actor.loc = Vector(place.x, place.y, 0)
	cast.loc = Vector(place.x - 900, place.y, 0)
	CREEPS[2], CREEPS[3] = {}, {}
	local function tick(...) for _, u in ipairs({ ... }) do CURRENT_TEAM = u.team H.Drill.Tick(u) if H.Drill.Held(u) then H.Drill.Hold(u) end end CURRENT_TEAM = 2 end
	local function attacks(pid) return ActionsOf(pid, "AttackUnit") end
	local function lines(ph, ls) local r = {} for _, l in ipairs(ls) do if field(l, "ph") == ph then table.insert(r, l) end end return r end
	ACTIONS = {}
	-- Rep 1 (stand), from 1:00.
	T = 61
	local dying = MakeCreep({ team = 2, x = place.x - 200, y = place.y, hp = 60 })
	cast.hitBy = nil
	actor.hitBy = { [cast] = T }
	tick(actor)
	check("lane-trade stand: the actor holds its last-hit place, attacking nothing", #attacks(7) == 0 and #ActionsOf(7, "MoveToLocation") > 0)
	-- Rep 2 (lasthit).
	T = 91
	actor.hitBy = nil
	dying.hp = 101
	local ls = capture(function() tick(actor) end)
	check("lane-trade lasthit: a creep over two of its hits is left", #attacks(7) == 0 and #lines("swing", ls) == 0)
	local far = MakeCreep({ team = 2, x = place.x - 1000, y = place.y, hp = 30 })
	tick(actor)
	check("lane-trade lasthit: a dying creep 1,000 off its place is left", #attacks(7) == 0)
	dying.hp = 100
	ls = capture(function() tick(actor) end)
	local a = attacks(7)
	check("lane-trade lasthit: two hits kill it, so it walks up and attacks it, logging the swing", #a == 1 and a[1].args[1] == dying and #lines("swing", ls) == 1, #a)
	T = 91.5
	tick(actor)
	check("lane-trade lasthit: it keeps on the creep while it lives", attacks(7)[#attacks(7)].args[1] == dying)
	dying.hp = 0
	far.hp = 500
	local n = #attacks(7)
	T = 92
	tick(actor)
	local mv = ActionsOf(7, "MoveToLocation")
	check("lane-trade lasthit: once it dies it walks back to its place", #attacks(7) == n and mv[#mv] ~= nil and math.abs(mv[#mv].args[1].x - place.x) <= 20)
	actor.hitBy = { [cast] = T }
	tick(actor)
	check("lane-trade lasthit: a hitter is not answered", #attacks(7) == n)
	-- Rep 3 (hitback): hit by the cast 900 off, inside its range + leash (380 + 400 from the place).
	T = 121
	cast.loc = Vector(place.x - 700, place.y, 0)
	actor.hitBy = { [cast] = T }
	ls = capture(function() tick(actor) end)
	a = attacks(7)
	check("lane-trade hitback: the cast that hit it is attacked, the answer logged", a[#a].args[1] == cast and #lines("answer", ls) == 1 and field(lines("answer", ls)[1], "tpid") == "1")
	n = #a
	T = 122.5
	tick(actor)
	check("lane-trade hitback: it keeps answering 1.5 s after the hit", #attacks(7) == n + 1 and attacks(7)[n + 1].args[1] == cast)
	T = 123.6
	tick(actor)
	check("lane-trade hitback: 2.6 s after the last hit it stops", #attacks(7) == n + 1)
	T = 124
	cast.loc = Vector(place.x - 900, place.y, 0)
	actor.hitBy = { [cast] = T }
	ls = capture(function() tick(actor) tick(actor) end)
	check("lane-trade hitback: a hitter 900 off its place (past 780) is not chased, nor its answer logged", #attacks(7) == n + 1 and #lines("answer", ls) == 0)

	-- The cast's watch, once released: ready needs the cast at its own place and the actor in sight within 1,500.
	actor.hitBy = nil
	cast.hitBy = nil
	local cplace = GetLaneFrontLocation(RAD, Lane.Mid, -(550 - 50))
	cast.loc = Vector(cplace.x, cplace.y, 0)
	actor.loc = Vector(cplace.x + 1000, cplace.y, 0)
	T = 151
	tick(cast)
	ls = capture(function() tick(cast) end)
	check("lane-trade: the cast at its place with the actor 1,000 off is released", #lines("ready", ls) == 1 and field(lines("ready", ls)[1], "ok") == "1", ls[1])
	CREEPS[3] = {}
	local creep = MakeCreep({ team = 3, x = cplace.x + 300, y = cplace.y, target = cast })
	creep.lastAttack = -1000
	cast.lastAttack = -1000
	T = 151.1
	tick(cast)
	cast.lastAttack, cast.target = 151.15, actor
	creep.lastAttack = 151.15
	T = 151.2
	ls = capture(function() tick(cast) end)
	check("lane-trade watch: one atk on the enemy hero and one chit", #lines("atk", ls) == 1 and field(lines("atk", ls)[1], "tpid") == "7" and #lines("chit", ls) == 1, table.concat(ls, " / "))
	T = 151.3
	ls = capture(function() tick(cast) end)
	check("lane-trade watch: the same attacks are not counted again", #lines("atk", ls) == 0 and #lines("chit", ls) == 0)
	cast.lastAttack, cast.target = 151.35, creep
	T = 151.4
	ls = capture(function() tick(cast) end)
	check("lane-trade watch: an attack fired at a creep is no atk", #lines("atk", ls) == 0)
	CURRENT_TEAM = 2
end

-- The lane ladder's in-lane hold: the cast plays everything (not held, not lane-only), but no mode that leaves its lane,
-- no teleport and no global spell. `sided` entries swap r and d when Ours.Team scopes Dire.
do
	local H, C = world("ladder-solo")
	local mid = hero(1, RAD, 2, 2)
	local sup = hero(4, RAD, 5, 3)
	local dmid = hero(6, DIRE, 2, 2)
	check("ladder-solo: our mid in-lane, not held", H.Drill.RoleOf(mid) == "cast" and H.Drill.InLane(mid) and not H.Drill.Held(mid) and not H.Drill.LaneOnly(mid))
	check("ladder-solo: our support and their mid benched", H.Drill.RoleOf(sup) == "bench" and H.Drill.RoleOf(dmid) == "bench")
	for _, m in ipairs({ "rune", "roam", "team_roam", "ward", "secret_shop", "roshan", "push_tower_top", "defend_tower_bot" }) do
		check("in-lane: " .. m .. " held at 0", H.Drill.InLaneDenies(mid, m) and H.Chooser.Decide(mid, m) == 0)
	end
	for _, m in ipairs({ "laning", "attack", "retreat", "farm", "push_tower_mid", "defend_tower_mid" }) do
		check("in-lane: " .. m .. " runs", not H.Drill.InLaneDenies(mid, m))
	end
	check("in-lane: a benched hero is not in-lane", not H.Drill.InLaneDenies(sup, "rune"))
	check("in-lane: no teleport, other items run", H.Drill.ForbidsItem(mid, "item_tpscroll") and H.Drill.ForbidsItem(mid, "item_travel_boots") and not H.Drill.ForbidsItem(mid, "item_flask") and not H.Drill.ForbidsItem(sup, "item_tpscroll"))
	GAME_STATE = 8
	local cleared = 0
	mid.Action_ClearActions = function() cleared = cleared + 1 end
	mid.casting = { GetName = function() return "zuus_thundergods_wrath" end }
	local ls = capture(function() H.Drill.Tick(mid) H.Drill.Tick(mid) end)
	local forbid = {}
	for _, l in ipairs(ls) do if field(l, "ph") == "forbid" then table.insert(forbid, l) end end
	check("in-lane: a global spell's cast is cleared each tick, logged once", cleared == 2 and #forbid == 1 and field(forbid[1], "ability") == "zuus_thundergods_wrath", table.concat(ls, " / "))
	mid.casting = { GetName = function() return "zuus_arc_lightning" end }
	capture(function() H.Drill.Tick(mid) end)
	check("in-lane: another spell runs", cleared == 2)
	C.Ours = { Team = "dire" }
	check("sided under Ours.Team dire: their mid is the cast, ours benched", H.Drill.RoleOf(dmid) == "cast" and H.Drill.RoleOf(mid) == "bench")
	C.Ours = nil
end
do
	local H, C = world("ladder-duel")
	C.Ours = { Team = "dire" }
	check("ladder-duel: both mids cast whatever the scope", H.Drill.RoleOf(hero(1, RAD, 2, 2)) == "cast" and H.Drill.RoleOf(hero(6, DIRE, 2, 2)) == "cast")
	C.Ours = nil
	local H2 = world(nil)
	check("no drill: nothing held", not H2.Drill.InLaneDenies(hero(1, RAD, 2, 2), "rune") and not H2.Drill.ForbidsItem(hero(1, RAD, 2, 2), "item_tpscroll"))
end

finish()
