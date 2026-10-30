dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Slice 2: shadow states for every bot (ShadowTeams) while ownership stays gated by Teams, the shadow job and
-- farm scorers over OHA's own decisions, the owned laning task giving way to a job and coming back, linger
-- against flicker, spec replacement by name, and the kill switch.
local LANING, FARM, RUNE = 1, 17, 7
BOT_MODE_LANING = LANING

local W -- the OHA decisions the scorers read, set per test

local function Fresh(states, o)
	ResetWorld()
	T = 10
	package.loaded["bots/FunLib/engine/tasks"] = nil
	o = o or {}
	local H = FreshHumaniser({ Enable = true, Lane = { Enable = false }, Transitions = { Enable = false }, Telemetry = { Enable = true, LuaErrors = o.guards == true }, States = states })
	-- These cases test the States settings on OHA's path: slice 5's Ours.CoreLastHit (pos1-3 own laning) is off here.
	package.loaded["bots/FunLib/custom_loader"].Ours = { CoreLastHit = false }
	W = { laning = true }
	require("bots/FunLib/humaniser/transitions/phase").IsLaningFor = function() return W.laning end
	local CampJobs = require("bots/FunLib/humaniser/camp_jobs")
	CampJobs.Active = function() return W.job ~= nil end
	CampJobs.Current = function() return W.job end
	require("bots/FunLib/humaniser/transitions/rotation").Active = function() return W.rotation end
	require("bots/FunLib/humaniser/transitions/mid_runes").Claiming = function() return W.midRune == true end
	local Farm = require("bots/FunLib/humaniser/farm_pattern")
	Farm.IsActive = function() return true end
	Farm.Current = function() return W.trip end
	local positions = {}
	require("bots/FunLib/humaniser/lane_config").SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	MakeUnit({ pid = 0, bot = false, team = 2 })
	local bot = MakeUnit({ pid = 1, team = o.team or 2, mode = LANING, loc = Vector(0, 0), level = o.level or 6 })
	positions[1] = o.pos or 2
	local lines = {}
	require("bots/FunLib/humaniser/telemetry").SetSink(function(l) table.insert(lines, l) end)
	H.States.SetLaneSpot(bot, function() return Vector(1000, 0) end)
	return H, bot, lines
end

local function frame(H, bot)
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	local stepped = false
	if bot.mode == LANING then stepped = H.States.Step(bot, LANING) end
	T = T + 0.05
	return stepped
end

local function frames(H, bot, n)
	local stepped = 0
	for _ = 1, n do if frame(H, bot) then stepped = stepped + 1 end end
	return stepped
end

local function count(lines, pattern)
	local n = 0
	for _, l in ipairs(lines) do if l:find(pattern) then n = n + 1 end end
	return n
end

local function silenced(fn)
	local p = print
	print = function() end
	local ok, err = pcall(fn)
	print = p
	if not ok then error(err, 0) end
end

local function describe(H, bot) return H.States.Describe(bot) or "nil" end

-- A Dire bot (no human on its team) is shadowed with ShadowTeams = 'all' but never owns, even at a listed
-- position: MayOwn stays false (so mode_laning_generic leaves Valve's C++ laning alone) and no task starts.
do
	local H, bot, lines
	local stepped
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", ShadowTeams = "all" }, { team = 3, pos = 2 })
		stepped = frames(H, bot, 20)
	end)
	check("dire: MayOwn false", H.States.MayOwn(bot) == false)
	check("dire: shadow laning chosen, not owned", describe(H, bot) == "laning n=0", describe(H, bot))
	check("dire: state logged owned=0", count(lines, "ev=state pid=1 from=none to=laning.* owned=0") == 1, table.concat(lines, "\n"))
	check("dire: never stepped, no task, no moves", stepped == 0 and H.Tasks.Current(bot) == nil and bot.moves == nil)
	silenced(function()
		W.job = { kind = "stack" }
		bot.mode = FARM
		frames(H, bot, 5)
	end)
	check("dire: shadow job scored from OHA's camp job", describe(H, bot) == "stack n=0", describe(H, bot))
end

-- ShadowTeams = 'allies' keeps slice 1's reach: the same Dire bot is not even selected.
do
	local H, bot, lines
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", ShadowTeams = "allies" }, { team = 3, pos = 2 })
		frames(H, bot, 20)
	end)
	check("allies-only: dire bot not selected", describe(H, bot) == "-" and count(lines, "ev=state ") == 0, describe(H, bot))
end

-- Owned Radiant pos 2: a pull OHA starts takes the state (cancelling the laning task, OHA runs the job), and
-- laning comes back owned and running within LINGER plus a selection interval of the job ending.
do
	local H, bot, lines
	local before, during, back
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Own = { laning = { 2 } }, ShadowTeams = "all" })
		before = frames(H, bot, 10)
		W.job = { kind = "full_pull" }
		bot.mode = FARM
		frames(H, bot, 10)
		during = describe(H, bot)
		W.job = nil
		bot.mode = LANING
		back = 0
		for i = 1, 60 do
			if frame(H, bot) then back = i break end
		end
	end)
	check("owned: laning stepped before the job", before == 10, before)
	check("owned: pull state while OHA pulls", during:sub(1, 4) == "pull", during)
	check("owned: laning task cancelled for the pull", count(lines, "ev=state_task pid=1 state=laning result=fail reason=cancelled msg=\"?state:pull") == 1, table.concat(lines, "\n"))
	check("owned: laning stepped again within 1.5 s", back > 0 and back * 0.05 <= 1.5, back)
	check("owned: back to laning, owned and running", describe(H, bot):find("laning* run", 1, true) ~= nil, describe(H, bot))
	check("owned: exactly two switches", count(lines, "ev=state pid=1 from=laning to=pull") == 1 and count(lines, "ev=state pid=1 from=pull to=laning") == 1)
end

-- A source that drops for a frame or two (here 0.15 s off every 0.4 s, 4 s long) must not thrash the state.
do
	local H, bot, lines
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Own = { laning = {} }, ShadowTeams = "all" }, { pos = 5 })
		frames(H, bot, 10)
		for i = 1, 80 do
			W.rotation = (i % 8) < 5 and { spawn = 360, go = true } or nil
			frame(H, bot)
		end
		W.rotation = nil
		frames(H, bot, 40)
	end)
	check("flicker: one switch to rotate", count(lines, "ev=state pid=1 from=laning to=rotate") == 1, count(lines, "to=rotate"))
	check("flicker: one switch back", count(lines, "ev=state pid=1 from=rotate to=laning") == 1, count(lines, "from=rotate"))
end

-- The mid's rune claim is a rotate too; a farm trip beats laning even inside the laning phase; after laning a
-- core farms and a support has no state (OHA farm/roam for supports is not a shadow state yet).
do
	local H, bot
	local rune, trip, core
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = {} }, ShadowTeams = "all" })
		frames(H, bot, 10)
		W.midRune = true
		frames(H, bot, 6)
		rune = describe(H, bot)
		W.midRune = false
		-- Past laning's 3 s minimum dwell: a trip (a posture) cannot take over a fresh laning state.
		frames(H, bot, 100)
		W.trip = { phase = "go" }
		frames(H, bot, 6)
		trip = describe(H, bot)
		W.trip = nil
		W.laning = false
		frames(H, bot, 6)
		core = describe(H, bot)
	end)
	check("mid rune claim: rotate", rune:sub(1, 6) == "rotate", rune)
	check("trip in lane: farm", trip:sub(1, 4) == "farm", trip)
	check("after laning, core: farm", core:sub(1, 4) == "farm", core)
	local support
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = {} }, ShadowTeams = "all" }, { pos = 5 })
		frames(H, bot, 10)
		W.laning = false
		frames(H, bot, 6)
		support = describe(H, bot)
	end)
	check("after laning, support: no state", support == "-", support)
end

-- A later slice registers an owned spec under a shadow name: it replaces the shadow one in place (order kept)
-- and bots already defined pick it up on their next Tick.
do
	local H, bot
	local names, after
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = {} }, ShadowTeams = "all" })
		frames(H, bot, 10)
		H.States.Register("stack", function(b)
			return { name = "stack", kind = "job", host = FARM, score = function() return 0.95 end, body = function(ctx) return coroutine.wrap(function() return ctx.ok() end) end }
		end)
		names = table.concat(H.States.Registered(), ",")
		frames(H, bot, 6)
		after = describe(H, bot)
	end)
	check("register: replaced in place", names == "laning,pull,stack,rotate,farm,gank", names)
	check("register: live bot uses the new spec", after:sub(1, 5) == "stack", after)
end

-- A scorer that fails on some bot is reported as ev=lua_error (with guards on) and counts as not applicable,
-- so the bot stays in laning instead of the SDK swallowing it silently.
do
	local H, bot, lines
	local cur
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Own = { laning = {} }, ShadowTeams = "all" }, { team = 3, guards = true })
		require("bots/FunLib/humaniser/transitions/rotation").Active = function() error("boom") end
		frames(H, bot, 10)
		cur = describe(H, bot)
	end)
	check("scorer error: reported", count(lines, "ev=lua_error.*States.score.rotate") >= 1, table.concat(lines, "\n"))
	check("scorer error: state falls back to laning", cur == "laning n=0", cur)
end

-- Kill switch: Enable = false with ShadowTeams = 'all' selects, logs and owns nothing for anyone.
do
	local H, bot, lines
	local stepped
	silenced(function()
		H, bot, lines = Fresh({ Enable = false, Own = { laning = { 2 } }, ShadowTeams = "all" })
		W.job = { kind = "full_pull" }
		stepped = frames(H, bot, 20)
	end)
	check("off: nothing selected", H.States.Describe(bot) == nil)
	check("off: no state events", count(lines, "ev=state") == 0)
	check("off: never stepped, no task", stepped == 0 and H.Tasks.Current(bot) == nil and bot.moves == nil)
	check("off: MayOwn false", H.States.MayOwn(bot) == false)
end

finish()
