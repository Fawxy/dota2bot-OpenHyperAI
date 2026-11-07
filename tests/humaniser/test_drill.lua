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

-- An unknown name logs once and runs no drill.
do
	local H = world("nope")
	local b = hero(0, RAD, 1, 3)
	local lines = capture(function() H.Drill.Tick(b) H.Drill.Tick(b) end)
	check("unknown drill: one line", #lines == 1 and field(lines[1], "ph") == "unknown" and field(lines[1], "name") == "nope", lines[1])
	check("unknown drill: plays", H.Drill.RoleOf(b) == "play")
end

-- lane-spot-statue: the Radiant pos1 is the cast (lane-only), the Dire pos3 a statue, everyone else benched.
do
	local H = world("lane-spot-statue")
	local core = hero(0, RAD, 1, 3)
	local sup = hero(4, RAD, 5, 3)
	local off = hero(7, DIRE, 3, 3)
	local mid = hero(6, DIRE, 2, 2)
	check("cast", H.Drill.RoleOf(core) == "cast" and not H.Drill.Held(core))
	check("cast lane-only", H.Drill.LaneOnly(core) and H.Overrides.LaneOnly(core) and H.Overrides.LaneOnly())
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

-- stack: forced reps every minute from 2:00; a control setting withholds every nth rep.
do
	local H = world("stack")
	local t = H.Drill.RepTimes("stack")
	check("stack reps from 120 every 60", t[1] == 120 and t[2] == 180 and t[3] == 240)
	check("another context is not forced", H.Drill.RepTimes("pull") == nil)
	H.Drill.TABLE.stack.rep.control = 3
	t = H.Drill.RepTimes("stack")
	check("control 3: the third rep withheld", t[1] == 120 and t[2] == 180 and t[3] == 300, t[3])
	local b = hero(4, RAD, 5, 3)
	T = 245
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

finish()
