dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- OHA integration of the engine bundle (bots/FunLib/engine/tasks.lua; humaniser/tasks.ts). Bodies are the bundle's own verbs,
-- since the TS test bodies live in the engine's test bundle.
local BUNDLE = "bots/FunLib/engine/tasks"
local ASSEMBLE, RETREAT = BOT_MODE_ASSEMBLE, BOT_MODE_RETREAT

local function capture(fn)
	local lines, realPrint = {}, print
	print = function(s) table.insert(lines, tostring(s)) end
	local ok, err = pcall(fn)
	print = realPrint
	return lines, ok, err
end

local function taskLines(lines)
	local r = {}
	for _, l in ipairs(lines) do if l:find("[H:tasks]", 1, true) then table.insert(r, l) end end
	return r
end

-- The bundle is cached in package.loaded outside FreshHumaniser's reach; dropping it gives a fresh runner.
local function Fresh(cfg, botOpts)
	ResetWorld()
	T = 10
	package.loaded[BUNDLE] = nil
	cfg = cfg or { Enable = true }
	local H = FreshHumaniser(cfg)
	local o = botOpts or {}
	o.pid, o.mode = o.pid or 1, o.mode or ASSEMBLE
	return H, MakeUnit(o)
end

local function waitBody(H, bot, secs) return function() return H.Tasks.Verbs().wait(bot, secs) end end

-- Defaults: one support line, and the task steps under its host mode to its end.
do
	local H, bot
	local started, stepped
	local lines = capture(function()
		H, bot = Fresh()
		started = H.Tasks.Start(bot, { name = "hold", host = ASSEMBLE }, waitBody(H, bot, 1))
		H.Tasks.Tick(bot)
		stepped = H.Tasks.Step(bot, ASSEMBLE)
	end)
	local support = taskLines(lines)
	check("support line printed once", #support == 1, #support)
	check("support line reports coroutine and bundle", support[1] == "[H:tasks] support coroutine=table bundle=ok", support[1])
	check("Start returns true", started == true)
	check("Step runs the host's task", stepped == true)
	check("Step under another mode does nothing", H.Tasks.Step(bot, RETREAT) == false)

	check("Describe shows the running task", H.Tasks.Describe(bot) == "hold step=1", H.Tasks.Describe(bot))

	H.Tasks.Step(bot, ASSEMBLE)
	T = T + 1
	H.Tasks.Step(bot, ASSEMBLE)
	check("finished task reported ok", H.Tasks.Describe(bot) == "- last=hold ok", H.Tasks.Describe(bot))
	T = T + 0.3
	check("Step after the task ends does nothing", H.Tasks.Step(bot, ASSEMBLE) == false)
end

-- walkTo through the wrapper issues moves each step and ends when the bot arrives.
do
	local H, bot = Fresh()
	local goal = Vector(1000, 0)
	H.Tasks.Start(bot, { name = "walk", host = ASSEMBLE }, function() return H.Tasks.Verbs().walkTo(bot, goal) end)
	for i = 1, 3 do
		H.Tasks.Step(bot, ASSEMBLE)
		T = T + 0.1
		bot.loc = Vector(bot.loc.x + 300, 0)
	end
	check("walkTo issues a move per step", bot.moves ~= nil and #bot.moves == 3 and bot.moves[1] == goal, bot.moves and #bot.moves)
	bot.loc = Vector(950, 0)
	H.Tasks.Step(bot, ASSEMBLE)
	check("walkTo ends on arrival", H.Tasks.Describe(bot) == "- last=walk ok", H.Tasks.Describe(bot))
end

-- A mode switch preempts the task on the humaniser's Tick.
do
	local H, bot = Fresh()
	H.Tasks.Start(bot, { name = "hold", host = ASSEMBLE }, waitBody(H, bot, 5))
	H.Tasks.Step(bot, ASSEMBLE)
	bot.mode = RETREAT
	H.Tick(bot)
	check("task gone after a mode switch", H.Tasks.Step(bot, ASSEMBLE) == false)
	check("Describe shows preempted", H.Tasks.Describe(bot) == "- last=hold preempted", H.Tasks.Describe(bot))
end

-- The adapter's lastHitFilter: a support's lastHit task ends with "etiquette" while an allied core can take the creep
-- itself (within its attack range + 150), and proceeds when none can.
do
	ACTIVITY_IDLE = 1500
	LANE_BOT = 3
	local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
	function GetUnitToUnitDistance(a, b) return dist(a.loc, b.loc) end
	local Unit = getmetatable(MakeUnit({ pid = 99 })).__index
	function Unit:GetAttackTarget() return self.target end
	function Unit:GetLastAttackTime() return self.lastAttack or -100 end
	function Unit:GetAnimActivity() return self.anim or ACTIVITY_IDLE end
	function Unit:GetExtrapolatedLocation() return self.heading or self.loc end
	function Unit:GetAssignedLane() return self.lane or LANE_BOT end
	function Unit:GetNearbyHeroes() return ALLIES or {} end
	function Unit:GetNearbyLaneCreeps() return ENEMY_CREEPS end
	function Unit:GetAttackDamage() return 50 end
	function Unit:GetAttackPoint() return 0.3 end
	function Unit:Action_AttackUnit(u) self.attacked = u end
	local Creep = {}
	Creep.__index = Creep
	function Creep:GetTeam() return self.team end
	function Creep:GetLocation() return self.loc end
	function Creep:GetHealth() return self.hp end
	function Creep:GetMaxHealth() return 100 end
	function Creep:IsAlive() return true end
	function Creep:IsNull() return false end

	local function setup()
		local H, bot = Fresh({ Enable = true }, { pid = 1, loc = Vector(-200, 0) })
		T = 100
		bot.pos = 5
		H.LaneConfig.SetHelpers({ GetPosition = function(u) return u.pos end, IsInLaningPhase = function() return true end })
		local core = MakeUnit({ pid = 2, loc = Vector(0, 0), mode = ASSEMBLE })
		core.pos, core.range = 1, 150
		ALLIES = { bot, core }
		-- Above one hit's damage, so an allowed task keeps waiting for the creep's HP to drop.
		ENEMY_CREEPS = { setmetatable({ team = 3, loc = Vector(100, 0), hp = 80 }, Creep) }
		H.Tasks.Start(bot, { name = "lh", host = ASSEMBLE }, function() return H.Tasks.Verbs().lastHit(bot) end)
		return H, bot, core
	end

	local H, bot = setup()
	H.Tasks.Step(bot, ASSEMBLE)
	check("lastHit left to a core in reach", H.Tasks.Describe(bot) == "- last=lh etiquette", H.Tasks.Describe(bot))

	local H2, bot2, core2 = setup()
	core2.loc = Vector(2000, 0)
	H2.Tasks.Step(bot2, ASSEMBLE)
	check("lastHit proceeds with no core in reach", H2.Tasks.Describe(bot2) == "lh step=1", H2.Tasks.Describe(bot2))
	-- Ours.SupportCreeps replaces the core-in-reach rule with creep_row's FreeFor for a support; a pos 3 core keeps the rule.
	local H3, bot3 = setup()
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportCreeps = true
	T = T + 1
	H3.Tasks.Step(bot3, ASSEMBLE)
	check("lastHit with the switch on: a core in reach no longer takes a support's creep from the filter", H3.Tasks.Describe(bot3) == "lh step=1", H3.Tasks.Describe(bot3))
	local H4, bot4 = setup()
	bot4.pos = 3
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportCreeps = true
	T = T + 1
	H4.Tasks.Step(bot4, ASSEMBLE)
	check("lastHit with the switch on: a pos 3 still leaves the creep to a pos 1 in reach", H4.Tasks.Describe(bot4) == "- last=lh etiquette", H4.Tasks.Describe(bot4))
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportCreeps = false
	ALLIES = nil
end

-- Kill switches: nothing starts, nothing is claimed, the bundle is never required and nothing is printed.
for _, case in ipairs({
	{ name = "Humaniser.Enable=false", cfg = { Enable = false } },
	{ name = "Tasks.Enable=false", cfg = { Enable = true, Tasks = { Enable = false } } },
}) do
	local H, bot, started, stepped
	local lines = capture(function()
		H, bot = Fresh(case.cfg)
		started = H.Tasks.Start(bot, { name = "hold", host = ASSEMBLE }, waitBody(H, bot, 1))
		stepped = H.Tasks.Step(bot, ASSEMBLE)
		H.Tick(bot)
		H.Tasks.Tick(bot)
	end)
	check(case.name .. ": Start false", started == false, started)
	check(case.name .. ": Step false", stepped == false, stepped)
	check(case.name .. ": bundle never required", package.loaded[BUNDLE] == nil)
	check(case.name .. ": nothing printed", #taskLines(lines) == 0, lines[1])
	check(case.name .. ": no Verbs or Describe", H.Tasks.Verbs() == nil and H.Tasks.Describe(bot) == nil)
end

-- A bundle that fails to load: one fail line with the error, Start false, and nothing raised.
do
	local realRequire = require
	local H, bot, started
	local lines, ok, err = capture(function()
		H, bot = Fresh()
		require = function(name, ...)
			if name == BUNDLE then error("no bundle here") end
			return realRequire(name, ...)
		end
		H.Tick(bot)
		started = H.Tasks.Start(bot, { name = "hold", host = ASSEMBLE }, function() end)
		H.Tasks.Step(bot, ASSEMBLE)
		H.Tasks.Tick(bot)
	end)
	require = realRequire
	local support = taskLines(lines)
	check("broken bundle raises nothing", ok, err)
	check("broken bundle: one fail line", #support == 1 and support[1]:find("^%[H:tasks%] support coroutine=table bundle=fail .*no bundle here") ~= nil, support[1])
	check("broken bundle: Start false", started == false, started)
end

-- WO-022: tasks.ts registers the bundle's Skill as the LaneConfig draw source; with tasks off nothing loads.
do
	local H = Fresh({ Enable = true })
	local C = H.LaneConfig
	local lines = capture(function()
		check("Skill wiring: Roll loads the bundle", C.Roll(1.1) == true)
	end)
	check("Skill wiring: bundle loaded on the first draw", package.loaded[BUNDLE] ~= nil and #taskLines(lines) == 1, table.concat(lines, " | "))
	local skill = H.Tasks.Loaded().Skill
	local realRandom, realGauss = skill.random, skill.gauss
	skill.random, skill.gauss = function() return 0.9 end, function() return -0.75 end
	check("Skill wiring: Roll draws from Skill.random", C.Roll(0.5) == false)
	check("Skill wiring: Gauss returns Skill.gauss", C.Gauss() == -0.75)
	skill.random, skill.gauss = realRandom, realGauss
end

do
	local H = Fresh({ Enable = true, Tasks = { Enable = false } })
	local C = H.LaneConfig
	local seq, i = { 0.1, math.exp(-2), 1.0 }, 0
	local realRandomFloat = RandomFloat
	RandomFloat = function() i = i + 1; return seq[i] end
	local roll, g
	local lines = capture(function()
		roll = C.Roll(0.5)
		g = C.Gauss()
	end)
	RandomFloat = realRandomFloat
	check("tasks off: Roll falls back to RandomFloat", roll == true)
	check("tasks off: Gauss falls back to RandomFloat Box-Muller", math.abs(g - 2) < 1e-6, g)
	check("tasks off: bundle not loaded", package.loaded[BUNDLE] == nil)
	check("tasks off: no support line", #taskLines(lines) == 0, table.concat(lines, " | "))
end

finish()
