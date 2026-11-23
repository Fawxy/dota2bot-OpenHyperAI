dofile(HARNESS_DIR .. "/lane_world.lua")
-- The own bounty on a cheap detour (rune_detour.ts, doctrine D23): the pass read, the row's start and the shadow's line.
-- Stub map: lanes are lines at y 5000 / 0 / -5000; Radiant's own bounty at (0, -2500), Dire's at (0, 2500); the bot lane's
-- Radiant front at (0, -5000).

local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode
local RAD = 2
local OWN, OTHER = Vector(0, -2500), Vector(0, 2500)
local SPOTS = { [2] = OTHER, [3] = OWN }
local status = {}
function GetRuneSpawnLocation(r) return SPOTS[r] or Vector(9000, 9000) end
function GetRuneStatus(r) return status[r] or RUNE_STATUS_MISSING end
local ANC = { [2] = Vector(-6000, -6000), [3] = Vector(6000, 6000) }
function GetAncient(team)
	return { IsAlive = function() return true end, GetHealth = function() return 4500 end, GetLocation = function() return ANC[team] end }
end

local function world(on)
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours = { RuneDetour = on == true }
	CURRENT_TEAM = RAD
	H.RuneDetour.ResetCache()
	status = { [3] = RUNE_STATUS_AVAILABLE }
	T = 250
	return H
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function lines(all, pat)
	local out = {}
	for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(out, l) end end
	return out
end

local function hero(o)
	o.team = o.team or RAD
	local u = MakeUnit(o)
	u.lane = o.lane or Lane.Bot
	return u
end

do
	local H = world(false)
	local R = H.RuneDetour
	check("the own rune is the bounty nearer the ancient", R.OwnRune(RAD) == 3 and R.OwnRune(3) == 2)
	local a = hero({ pid = 1, loc = Vector(0, -3000) })
	local r = R.ReadPass(a, 250)
	check("out of lane by a live own bounty is a pass", r ~= nil and r.rune == 3)
	check("its detour is the walk by the rune less the walk to the front", r ~= nil and math.abs(r.ex - 1000 / 300) < 0.01, r and r.ex)
	local inLane = hero({ pid = 2, loc = Vector(0, -4200) })
	check("a hero in its own lane makes no pass (control)", R.ReadPass(inLane, 250) == nil)
	check("before the 4:00 spawn the 0:00 bounty is stock's", R.ReadPass(a, 100) == nil)
	check("after 10:00 there is no pass", R.ReadPass(a, 610) == nil)
	status[3] = RUNE_STATUS_MISSING
	check("a rune that is not available makes no pass", R.ReadPass(a, 250) == nil)
	status[3] = RUNE_STATUS_AVAILABLE
	local far = hero({ pid = 3, loc = Vector(0, 0), lane = Lane.Bot })
	check("beyond the radius there is no pass", R.ReadPass(far, 250) == nil)
end

do
	-- Off: the pass is the shadow's line, one per pass, written as the pass ends.
	local H = world(false)
	local R = H.RuneDetour
	local a = hero({ pid = 1, loc = Vector(0, -3000) })
	local out = capture(function()
		T = 250
		R.Shadow(a)
		T = 251
		R.Shadow(a)
		a.loc = Vector(0, -4500)
		T = 252
		R.Shadow(a)
	end)
	local ch = lines(out, "kind=rune_detour")
	check("one shadow line for the pass", #ch == 1, table.concat(out, "\n"))
	check("the shadow line reads go=0 why=off src=shadow want=1 slot=240", ch[1] ~= nil and ch[1]:find("go=0", 1, true) and ch[1]:find("why=off", 1, true)
		and ch[1]:find("src=shadow", 1, true) and ch[1]:find("want=1", 1, true) and ch[1]:find("slot=240", 1, true), ch[1])
end

do
	-- On, the detour over budget: refused `detour`, nothing ordered (the opposite rule's control).
	local H = world(true)
	local R = H.RuneDetour
	local a = hero({ pid = 1, loc = Vector(1600, -3300) })
	a.speed = 150
	local applied
	local out = capture(function()
		applied = R.ROW.applies(a)
		a.loc = Vector(0, -4500)
		T = 251
		R.ROW.applies(a)
	end)
	local ch = lines(out, "kind=rune_detour")
	check("a detour over the budget does not hold the hero", applied == false)
	check("its line is go=0 want=0 why=detour", #ch == 1 and ch[1]:find("go=0", 1, true) and ch[1]:find("want=0", 1, true) and ch[1]:find("why=detour", 1, true), table.concat(out, "\n"))
end

do
	-- On, a cheap detour: the row holds the hero and starts the walk; one go=1 line and a job start.
	local H = world(true)
	local R = H.RuneDetour
	local a = hero({ pid = 1, loc = Vector(0, -3000) })
	a.mode = BotMode.Farm
	local applied
	local out = capture(function() applied = R.ROW.applies(a) end)
	local ch = lines(out, "kind=rune_detour")
	check("a cheap detour holds the hero", applied == true, table.concat(out, "\n"))
	check("its line is go=1 want=1", #ch == 1 and ch[1]:find("go=1", 1, true) and ch[1]:find("want=1", 1, true), table.concat(out, "\n"))
	check("the walk starts as job rune_detour", #lines(out, "job=rune_detour") == 1)
	local again
	capture(function()
		R.ROW.step(a)
		status[3] = RUNE_STATUS_MISSING
		T = 252
		R.ROW.step(a)
		T = 253
		R.ROW.step(a)
		T = 254
		again = R.ROW.applies(a)
	end)
	status[3] = RUNE_STATUS_AVAILABLE
	local more
	local out2 = capture(function()
		T = 260
		more = R.ROW.applies(a)
	end)
	check("one walk a spawn: the same hero does not start again", more == false and #lines(out2, "kind=rune_detour") == 0, table.concat(out2, "\n"))
end

finish()
