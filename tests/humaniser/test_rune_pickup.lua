dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice rune-spawn: RunePickup gives up a rune that pickup orders do not take (the 0:00 river bounty held a hero at its
-- spot until 2:00 in 4 of 385 banked games, e.g. game_id 20 pid 5 in the hlog store: rune mode from -1:30 to 2:00 at the top
-- spot, then item mode) and frees the hero and the team from it until the next river spawn.

local RAD = 2
local SPOT = Vector(-1640, 1112)
local status = {}
function GetRuneSpawnLocation(r) return SPOT end
function GetRuneStatus(r) return status[r] or RUNE_STATUS_MISSING end

local function world(on)
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours = { RuneSpawn = on ~= false }
	CURRENT_TEAM = RAD
	H.RunePickup.ResetCache()
	status = { [0] = RUNE_STATUS_AVAILABLE }
	return H.RunePickup
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function count(all, res)
	local n = 0
	for _, l in ipairs(all) do if l:find("ev=rune_try ", 1, true) and l:find(" res=" .. res, 1, true) then n = n + 1 end end
	return n
end

do
	local P = world()
	local a = MakeUnit({ pid = 1, team = RAD, loc = SPOT })
	local b = MakeUnit({ pid = 2, team = RAD, loc = Vector(-1500, 1100) })
	local held, after, other, next
	local out = capture(function()
		held = P.Try(a, 0, 0.5) and P.Try(a, 0, 2.0) and P.Try(a, 0, 3.4)
		after = P.Try(a, 0, 3.6)
		other = P.Try(b, 0, 10)
		next = P.Try(b, 0, 120.1)
	end)
	check("orders within reach keep trying for GiveUpAfter seconds", held == true)
	check("the rune still there 3 s after the first order is given up", after == false)
	check("the give-up holds for a teammate too", other == false)
	check("the next river spawn may be tried again", next == true)
	check("one try line and one gave_up line for the held hero", count(out, "try") == 2 and count(out, "gave_up") == 1, table.concat(out, "\n"))
end

do
	local P = world()
	local a = MakeUnit({ pid = 1, team = RAD, loc = SPOT })
	local out = capture(function()
		P.Try(a, 0, 0.5)
		status[0] = RUNE_STATUS_MISSING
		P.Tick(a, 1.2)
	end)
	status[0] = RUNE_STATUS_AVAILABLE
	check("a rune that went ends the try gone, not given up", count(out, "gone") == 1 and not P.Unpickable(0, 5))
end

do
	-- Orders from beyond Near are the walk in: the timer starts at arrival, so a long walk is not a held rune.
	local P = world()
	local a = MakeUnit({ pid = 1, team = RAD, loc = Vector(-1640, 1700) })
	capture(function()
		P.Try(a, 0, 0.5)
		P.Try(a, 0, 4.0)
		a.loc = SPOT
		P.Try(a, 0, 4.5)
	end)
	local ok
	capture(function() ok = P.Try(a, 0, 6.0) end)
	check("the give-up timer starts when the hero reaches the rune", ok == true and not P.Unpickable(0, 6.0))
end

finish()
