-- Slice 3: Etiquette (Ours.LeaveCoreCreep), the support's "can an allied core take this creep" predicate.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
function GetUnitToUnitDistance(a, b) return dist(a.loc, b.loc) end

local Unit = getmetatable(MakeUnit({ pid = 99 })).__index
function Unit:GetAttackTarget() return self.target end
function Unit:GetExtrapolatedLocation() return self.heading or self.loc end
function Unit:IsIllusion() return self.illusion == true end

local function creepAt(x, y) return { loc = Vector(x, y or 0) } end

-- Radiant: support (pos botPos) at the origin; cores as given ({pos, x, range, ...}).
local function Setup(o)
	o = o or {}
	ResetWorld()
	local H = FreshHumaniser({ Enable = false })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	if o.ours ~= nil then Customize.Ours = o.ours end
	if o.enable ~= nil then Customize.Enable = o.enable end
	H.Lane.SetHelpers({ GetPosition = function(u) return u.pos end })
	local bot = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	bot.pos = o.botPos or 5
	local cores = {}
	for i, c in ipairs(o.cores or {}) do
		local u = MakeUnit({ pid = 1 + i, loc = Vector(c.x or 0, c.y or 0), bot = c.bot ~= false, alive = c.alive })
		u.pos, u.range, u.heading, u.illusion = c.pos or 1, c.range or 150, c.heading, c.illusion
		table.insert(cores, u)
	end
	return H.Etiquette, bot, cores
end

-- Applies: switch on (the Customize default) and a support.
do
	local E, bot = Setup({ botPos = 5 })
	check("applies to pos5 with the default switch", E.Applies(bot) == true)
	bot.pos = 4
	check("applies to pos4", E.Applies(bot) == true)
	for _, p in ipairs({ 1, 2, 3 }) do
		bot.pos = p
		check("does not apply to pos" .. p, E.Applies(bot) == false)
	end
	E, bot = Setup({ ours = { LeaveCoreCreep = false } })
	check("switch off: does not apply", E.Applies(bot) == false)
	E, bot = Setup({ ours = {} })
	check("Ours block without the key: the default (on)", E.Applies(bot) == true)
	E, bot = Setup({ enable = false })
	check("Customize.Enable = false turns the switch off", E.Applies(bot) == false)
end

-- CoreCanTake: in range + buffer, attacking, walking in; not beyond, not dead, not illusions, not other supports.
do
	local E, bot, cores = Setup({ cores = { { pos = 1, x = 400, range = 150 } } })
	local creep = creepAt(0)
	check("core within range + 300 can take", E.CoreCanTake(bot, creep) == true and E.MayLastHit(bot, creep) == false)
	cores[1].loc = Vector(460, 0)
	check("core just beyond range + 300, standing, cannot", E.CoreCanTake(bot, creep) == false and E.MayLastHit(bot, creep) == true)
	cores[1].target = creep
	check("core attacking the creep can take it from anywhere", E.CoreCanTake(bot, creep) == true)
	cores[1].target = nil
	cores[1].heading = Vector(400, 0)
	check("core walking towards the creep can take", E.CoreCanTake(bot, creep) == true)
	cores[1].loc, cores[1].heading = Vector(1100, 0), Vector(1000, 0)
	check("walking in from beyond ApproachRange does not count", E.CoreCanTake(bot, creep) == false)
	cores[1].loc, cores[1].heading = Vector(460, 0), Vector(470, 0)
	check("core walking away cannot", E.CoreCanTake(bot, creep) == false)
end

do
	local E, bot, cores = Setup({ cores = { { pos = 2, x = 600, range = 550 } } })
	check("a ranged mid in range can take", E.CoreCanTake(bot, creepAt(0)) == true)
	cores[1].alive = false
	check("a dead core cannot", E.CoreCanTake(bot, creepAt(0)) == false)
	cores[1].alive, cores[1].illusion = true, true
	check("an illusion is not a core", E.CoreCanTake(bot, creepAt(0)) == false)
	cores[1].illusion, cores[1].pos = false, 4
	check("another support is not a core", E.CoreCanTake(bot, creepAt(0)) == false)
	cores[1].pos = nil
	check("a hero with no position is not a core", E.CoreCanTake(bot, creepAt(0)) == false)
end

do
	local E, bot, cores = Setup({ cores = { { pos = 1, x = 300, bot = false } } })
	check("a human core counts", E.CoreCanTake(bot, creepAt(0)) == true)
	check("the bot itself is never its own core", E.CoreCanTake(cores[1], creepAt(300)) == false)
end

-- LeavesTarget: the bot's current attack is on an enemy creep a core can take (cancel); not on own creeps, heroes or
-- a creep no core can take, and never with the switch off.
do
	local E, bot, cores = Setup({ cores = { { pos = 1, x = 300, range = 150 } } })
	local enemy = creepAt(0)
	enemy.team, enemy.creep = 3, true
	function enemy:IsCreep() return self.creep end
	function enemy:GetTeam() return self.team end
	function GetOpposingTeam() return 3 end
	check("no attack target: nothing to cancel", E.LeavesTarget(bot) == false)
	bot.target = enemy
	check("attacking a creep the core can take: cancel", E.LeavesTarget(bot) == true)
	cores[1].loc = Vector(2000, 0)
	check("attacking a creep no core can take: keep", E.LeavesTarget(bot) == false)
	cores[1].loc = Vector(300, 0)
	enemy.team = 2
	check("attacking an own creep (deny): keep", E.LeavesTarget(bot) == false)
	enemy.team, enemy.creep = 3, false
	check("attacking a hero: keep", E.LeavesTarget(bot) == false)
	enemy.creep = true
	bot.pos = 1
	check("a core's own attack: keep", E.LeavesTarget(bot) == false)
	E, bot = Setup({ ours = { LeaveCoreCreep = false }, cores = { { pos = 1, x = 300 } } })
	bot.target = enemy
	check("switch off: keep", E.LeavesTarget(bot) == false)
end

-- Hooks (source pins; team_roam's cancel also has behavioural fixtures, tests/fixtures/laning/f9-roam-*.yaml). With the switch on, the support's team_roam last hit is
-- gated by the predicate alone; off, OHA's 800-radius exit and the humaniser's AllyLastHit check stay.
do
	local function source(rel) return io.open(BOTS_ROOT .. '/' .. rel, 'r'):read('a') end
	local function has(text, needle) return text:find(needle, 1, true) ~= nil end
	local roam = source('bots/mode_team_roam_generic.lua')
	check('team roam: near-core exit only with the switch off', has(roam, 'or (not bEtiquette and not J.IsCore(bot) and J.IsThereCoreNearby(800))'))
	check('team roam: predicate replaces AllyLastHit', has(roam, '(bEtiquette and Etiquette.MayLastHit(bot, creep) or not bEtiquette and J.Humaniser.AllyLastHit.MayLastHit(bot, creep))'))
	check('team roam: cancels a swing on a core creep before its own last hit', has(roam, 'if J.Humaniser.Etiquette.LeavesTarget(bot) then\n\t\tbot:Action_MoveToLocation(bot:GetLocation())'))
	local laning = source('bots/mode_laning_generic.lua')
	check('laning: cancels a swing on a core creep first in Think', has(laning, 'if bEtiquette and Etiquette.LeavesTarget(bot) then PositionThink() return end'))
	check('laning: predicate is the filter', has(laning, 'if bEtiquette then fLastHitFilter = function(creep) return Etiquette.MayLastHit(bot, creep) end end'))
	local general = source('bots/Customize/general.lua')
	check('Customize: LeaveCoreCreep on by default', has(general, 'Customize.Ours = { LeaveCoreCreep = true, StackExecute = true, DoubleStack = true, CoreLastHit = false }'))
end

finish()
