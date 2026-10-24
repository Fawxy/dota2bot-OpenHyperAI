dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Team slice 14: the state layer (SDK Modes) as the authority over mode desires, wired through Intent.Resolve:
-- the laning host flattens OHA's last-hit spike where the body takes the last hits, owned farm is suppressed,
-- team_roam's last-hit score is refused, delegated modes pass, claims (survival, job floors) still bind, and the
-- kill switch restores OHA's own arbitration.
local BUNDLE = "bots/FunLib/sdk/tasks/tasks"
local LANING, RETREAT, TEAM_ROAM, FARM = 1, 4, 16, 17
BOT_MODE_LANING = LANING

local function Fresh(states, o)
	ResetWorld()
	T = 10
	package.loaded[BUNDLE] = nil
	local H = FreshHumaniser({ Enable = true, Lane = { Enable = false }, Transitions = { Enable = false }, States = states })
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	Phase.IsLaningFor = function() return true end
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	local positions = {}
	LaneConfig.SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	o = o or {}
	MakeUnit({ pid = 0, bot = false, team = o.humanTeam or 2 })
	local bot = MakeUnit({ pid = 1, mode = LANING, loc = Vector(0, 0), team = 2 })
	positions[1] = o.pos or 2
	return H, bot, positions
end

local function frame(H, bot)
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	if bot.mode == LANING then H.States.Step(bot, LANING) end
	T = T + 0.05
end

local function silenced(fn)
	local p = print
	print = function() end
	local ok, err = pcall(fn)
	print = p
	if not ok then error(err, 0) end
end

local ON = { Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } }, Modes = { Enable = true } }

local function ready(states, o)
	local H, bot, positions
	silenced(function()
		H, bot, positions = Fresh(states, o)
		H.States.SetLaneSpot(bot, function() return Vector(0, 0) end)
		for _ = 1, 6 do frame(H, bot) end
	end)
	return H, bot, positions
end

-- Body takes the last hits: OHA's 0.9 spike is flattened to the base score, so laning stays laning.
do
	local H, bot = ready(ON)
	check("on: asserting for pos 2", H.States.ModesAsserting(bot) == true)
	local base = H.Intent.Resolve(bot, LANING, 0.446)
	local spike = H.Intent.Resolve(bot, LANING, 0.9, "lasthit")
	check("on: base laning gets the hold band", near(base, 0.446 + 0.08), base)
	check("on: last-hit spike flattened to the base", near(spike, 0.446 + 0.08), spike)
	check("on: farm suppressed while laning", H.Intent.Resolve(bot, FARM, 0.62) == 0)
	check("on: team_roam's last hit refused", H.Intent.Resolve(bot, TEAM_ROAM, 1.5, "lasthit") == 0)
	check("on: team_roam's fight passes", near(H.Intent.Resolve(bot, TEAM_ROAM, 0.98), 0.98))
	check("on: retreat passes", near(H.Intent.Resolve(bot, RETREAT, 0.7), 0.7))
end

-- OHA keeps the bot's last hits (LastHit lists no position): its spike passes as the host desire and team_roam's
-- last-hit score is not refused, since those are how OHA's own last hits get the frame.
do
	local H, bot = ready({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = {} }, Modes = { Enable = true } })
	local spike = H.Intent.Resolve(bot, LANING, 0.9, "lasthit")
	check("oha last hits: spike kept (+hold)", near(spike, 0.9 + 0.08), spike)
	check("oha last hits: team_roam's last hit passes", near(H.Intent.Resolve(bot, TEAM_ROAM, 1.5, "lasthit"), 1.5))
	check("oha last hits: farm still suppressed", H.Intent.Resolve(bot, FARM, 0.62) == 0)
end

-- Claims still bind after the layer: a camp job's start floor lifts the suppressed farm (so job timing stays
-- exact), and the survival cap keeps laning below a retreat that wants out at low HP.
do
	local H, bot = ready(ON)
	H.Intent.Claim(bot, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.7 })
	check("claims: job floor lifts suppressed farm", near(H.Intent.Resolve(bot, FARM, 0.62), 0.7))
	bot.hp = 10
	local retreat = H.Intent.Resolve(bot, RETREAT, 0.8)
	local lane = H.Intent.Resolve(bot, LANING, 0.446)
	check("claims: survival keeps laning below retreat", lane < retreat, lane .. " vs " .. retreat)
end

-- Kill switch: Modes.Enable = false leaves Intent exactly as before (raw desires, OHA's own stickiness).
do
	local H, bot = ready({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } }, Modes = { Enable = false } })
	check("off: not asserting", H.States.ModesAsserting(bot) == false)
	check("off: farm passes", near(H.Intent.Resolve(bot, FARM, 0.62), 0.62))
	check("off: team_roam last hit passes", near(H.Intent.Resolve(bot, TEAM_ROAM, 1.5, "lasthit"), 1.5))
end

-- Positions and team: a position not listed, or a bot that is not an ally of the human, is left to OHA.
do
	local H, bot = ready({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } }, Modes = { Enable = true, Positions = { 1 } } })
	check("positions: pos 2 not listed passes", near(H.Intent.Resolve(bot, FARM, 0.62), 0.62))
	local H2, bot2 = ready(ON, { humanTeam = 3 })
	check("team: no human ally passes", near(H2.Intent.Resolve(bot2, FARM, 0.62), 0.62))
end

-- The overlay of Intent names the layer as the setter, so a game log's ev=mode `by` shows who decided.
do
	local H, bot = ready(ON)
	H.Intent.Resolve(bot, LANING, 0.446)
	local why = H.Intent.Explain(bot, LANING)
	check("explain: by states", why:find("by states", 1, true) ~= nil, why)
end

finish()
