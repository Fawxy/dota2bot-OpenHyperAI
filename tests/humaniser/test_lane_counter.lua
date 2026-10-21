dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, UnitType = dota.Lane, dota.UnitType

local FRONT = Vector(0, 5000)
-- The Dire safe-lane small camp, near the Dire top T1 (2800, 5000): the enemy pull camp opposing our top lane.
local THEIR_SMALL = Vector(1600, 6200)

local function spawner(team, type_, at)
	return { team = team, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or FRONT })
	u.lane, u.pos, u.dmg = o.lane or Lane.Top, o.pos, o.dmg
	return u
end

local function hide(u, ...) u.hiddenFrom = {} for _, pid in ipairs({ ... }) do u.hiddenFrom[pid] = true end end
local function show(u) u.hiddenFrom = nil end

-- Radiant top (our offlane): core pid 3 (pos 3) and support pid 4 (pos 4); Dire laners: core pid 11 (pos 1) and
-- support pid 15 (pos 5). The support observes. Only the Dire small camp exists.
local function world(skill, opts)
	opts = opts or {}
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill })
	T = opts.t or 60
	CURRENT_TEAM = 2
	OBSERVER = 4
	SPAWNERS = { spawner(3, "small", THEIR_SMALL) }
	H.Lane.Camps.ResetCache()
	local core = unit({ pid = 3, pos = 3, loc = opts.coreAt })
	local support = unit({ pid = 4, pos = 4, loc = opts.at or Vector(0, 5300) })
	local ecore = unit({ pid = 11, team = 3, pos = 1, loc = opts.enemyCoreAt or Vector(300, 5000) })
	local esup = unit({ pid = 15, team = 3, pos = 5, loc = opts.enemySupAt or Vector(-300, 5000) })
	H.Lane.Config.SkillOf(support)
	H.Lane.Config.SkillOf(core)
	return H, support, core, ecore, esup
end

local function tick(H, bot, t)
	T = t
	H.Lane.Counter.Tick(bot)
end

local function signalsOf(H, bot, kind)
	local r = {}
	for _, s in ipairs(H.Lane.Counter.Signals(bot)) do if kind == nil or s.kind == kind then table.insert(r, s) end end
	return r
end

local function attacksOn(pid, target)
	local n = 0
	for _, a in ipairs(ActionsOf(pid, "AttackUnit")) do if a.args[1] == target then n = n + 1 end end
	return n
end

do
	-- Scenario 10: every enemy fogged with no last-seen hint, the wave on time, no neutrals in sight.
	local function fogged(H, support, ecore, esup)
		hide(ecore, 4)
		hide(esup, 4)
		for i = 1, 4 do MakeCreep({ team = 3, x = 100 + i * 20, y = 5000 }) end
		RANDOM_FRACTION = 0
		for t = 60, 180, 0.5 do tick(H, support, t) end
	end
	local H, support, _, ecore, esup = world(1)
	fogged(H, support, ecore, esup)
	check("fairness: all fogged, no hints -> no signals", #signalsOf(H, support) == 0, #signalsOf(H, support))

	H, support, _, ecore, esup = world(1)
	fogged(H, support, ecore, esup)
	show(esup)
	esup.loc = Vector(THEIR_SMALL.x, THEIR_SMALL.y - 300)
	T = 195
	H.Lane.Tick(support)
	local pulls = signalsOf(H, support, "pull")
	check("positive control: support visible at their camp at :15 -> pull", #pulls == 1 and pulls[1].campIdx == 1 and pulls[1].enemyPid == 15)
	RANDOM_FRACTION = nil
end

do
	local H = world(0.5)
	local C = H.Lane.Counter
	local function input(now, unseen, loc, visible)
		return { now = now, campLoc = THEIR_SMALL, campPullSec = { 15, 45 }, campHalfSec = { 17, 47 },
			enemySupport = { pid = 15, visible = visible == true, location = loc, timeSinceSeen = unseen } }
	end
	local away = Vector(THEIR_SMALL.x, THEIR_SMALL.y - 1000)
	check("unseen 5 s, last seen 1,000 from camp, :14 -> suspected", C.EnemyPullSuspected(input(74, 5, away)))
	check("unseen only 3 s -> not suspected", not C.EnemyPullSuspected(input(74, 3, away)))
	check(":25 is outside the pull window -> not suspected", not C.EnemyPullSuspected(input(85, 5, away)))
	check("last seen 2,000 from camp -> not suspected", not C.EnemyPullSuspected(input(74, 5, Vector(THEIR_SMALL.x, THEIR_SMALL.y - 2000))))
	check("visible at the camp -> suspected", C.EnemyPullSuspected(input(85, 0, THEIR_SMALL, true)))
	check("visible far from the camp -> not suspected", not C.EnemyPullSuspected(input(74, 0, away, true)))
end

do
	local H = world(0.5)
	local C = H.Lane.Counter
	check("wave 6 s past its usual arrival with none in sight -> late", C.WaveAnomaly(18, 12, 0, 5) == "late")
	check("wave only 2 s past arrival -> no anomaly yet", C.WaveAnomaly(14, 12, 0, 5) == nil)
	check("arrived with 2 of a usual 5 -> thin", C.WaveAnomaly(17, 12, 2, 5) == "thin")
	check("arrived with 4 of 5 -> normal", C.WaveAnomaly(17, 12, 4, 5) == nil)
	check("no arrival history -> nothing", C.WaveAnomaly(18, nil, 0, 5) == nil)
end

do
	local H = world(0.5)
	local C = H.Lane.Counter
	check("two cycles near their tower with denies -> freeze", C.FreezeSuspected({ 0.7, 0.65 }, { 3, 2 }))
	check("second cycle off the tower -> no freeze", not C.FreezeSuspected({ 0.7, 0.4 }, { 3, 2 }))
	check("one cycle with a single deny -> no freeze", not C.FreezeSuspected({ 0.7, 0.65 }, { 1, 3 }))
	check("one cycle of history -> no freeze", not C.FreezeSuspected({ 0.7 }, { 3 }))
end

do
	local H = world(0.5)
	local C = H.Lane.Counter
	check("enemy near a camp at :54 -> stack", C.StackSuspected(54, true, false))
	check("enemy near a camp at :49 -> no stack", not C.StackSuspected(49, true, false))
	check("neutrals outside their box at :01 -> stack", C.StackSuspected(1, false, true))
	check("neutrals outside their box at :05 -> no stack", not C.StackSuspected(5, false, true))
end

do
	-- Scenario 9: 20 pull instances, one per wave cycle; the notice roll is the only draw of each.
	local function noticed(skill)
		local H, support, _, _, esup = world(skill)
		esup.loc = THEIR_SMALL
		local n = 0
		for k = 0, 19 do
			SetRandomSequence({ 0.025 + 0.05 * k })
			tick(H, support, 60 + 30 * k + 15)
			for _, s in ipairs(signalsOf(H, support, "pull")) do if s.at == T then n = n + 1 end end
		end
		return n
	end
	local hi, lo = noticed(0.9), noticed(0.2)
	check("skill 0.9 notices 15 of 20 (0.74)", hi == 15, hi)
	check("skill 0.2 notices 6 of 20 (0.32)", lo == 6, lo)
end

do
	-- A noticed pull: the enemy support stands at its camp at :15.
	local function pulled(opts)
		local H, support, core, ecore, esup = world(1, opts)
		esup.loc = THEIR_SMALL
		tick(H, support, 75)
		check("precondition: pull noticed", #signalsOf(H, support, "pull") == 1)
		return H, support, core, ecore, esup
	end

	local H, support, _, ecore = pulled()
	STRONGER = true
	H.Lane.Counter.Think(support, {})
	check("stronger: punishes the remaining laner", attacksOn(4, ecore) == 1, attacksOn(4, ecore))
	T = 76
	check("punish holds the attack between hits", H.Lane.Counter.Think(support, {}) == true)
	check("no second hit inside the 2 s gap", attacksOn(4, ecore) == 1)
	T = 77.5
	H.Lane.Counter.Think(support, {})
	check("second hit after the gap", attacksOn(4, ecore) == 2)
	T = 82
	H.Lane.Counter.Think(support, {})
	check("punish ends after 6 s", attacksOn(4, ecore) == 2)
	check("no contest while punishing", H.Lane.CampJobs.Current(support) == nil)

	H, support = pulled({ enemyCoreAt = Vector(-4000, 5000) })
	H.Lane.Counter.Think(support, {})
	local job = H.Lane.CampJobs.Current(support)
	check("not stronger, safe path: contest job at their camp", job ~= nil and job.kind == "contest" and job.campIdx == 1 and job.targetPid == 15)
	check("contest is the cycle's technique", H.Lane.LanePlanner.Committed(support) == "contest")
	check("contest desire", near(H.Lane.CampJobDesire(support), 0.65))

	H, support = pulled({ enemyCoreAt = Vector(-4000, 5000) })
	local mid = unit({ pid = 12, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-6000, 0) })
	hide(mid, 4)
	LAST_SEEN[12] = { location = Vector(800, 4700), time_since_seen = 2 }
	T = 76
	H.Lane.Counter.Think(support, {})
	check("unsafe path: no contest", H.Lane.CampJobs.Current(support) == nil)
	check("unsafe path: no attack", #ActionsOf(4, "AttackUnit") == 0)
end

do
	-- The contest executor: walk to the camp, hit the visible puller every 2.5 s, give up after 10 s.
	local H, support, _, _, esup = world(1, { enemyCoreAt = Vector(-4000, 5000) })
	esup.loc = THEIR_SMALL
	tick(H, support, 75)
	H.Lane.Counter.Think(support, {})
	esup.loc = Vector(-6000, 5000)
	hide(esup, 4)
	T = 75.6
	H.Lane.CampJobThink(support)
	local moves = ActionsOf(4, "MoveToLocation")
	check("contest walks to their camp", #moves == 1 and moves[1].args[1].x == THEIR_SMALL.x and moves[1].args[1].y == THEIR_SMALL.y)
	show(esup)
	esup.loc = THEIR_SMALL
	T = 76.2
	H.Lane.CampJobThink(support)
	T = 77
	H.Lane.CampJobThink(support)
	check("hits the puller once inside the gap", attacksOn(4, esup) == 1)
	T = 78.8
	H.Lane.CampJobThink(support)
	check("hits again after 2.5 s", attacksOn(4, esup) == 2)
	T = 85.1
	check("contest gives up after 10 s", H.Lane.CampJobDesire(support) == 0)
end

do
	local function blockWorld(cfg, skill)
		local H, support = world(skill, { cfg = cfg })
		local ward = { GetName = function() return "item_ward_sentry" end }
		support.GetItemInSlot = function(_, i) if i == 0 then return ward end end
		T = 114
		H.Lane.Counter.Think(support, {})
		return H, support, ward
	end
	local _, support = blockWorld({ Enable = true }, 1)
	check("camp block off by default", #ActionsOf(4, "UseAbilityOnLocation") == 0)

	local H, ward
	H, support, ward = blockWorld({ Enable = true, CampBlock = true }, 0.7)
	local uses = ActionsOf(4, "UseAbilityOnLocation")
	check("CampBlock on: one ward at their pull camp", #uses == 1 and uses[1].args[1] == ward
		and uses[1].args[2].x == THEIR_SMALL.x and uses[1].args[2].y == THEIR_SMALL.y)
	T = 115
	check("walking to plant keeps the frame", H.Lane.Counter.Think(support, {}) == true)
	T = 174
	H.Lane.Counter.Think(support, {})
	check("60 s later: still on the 180 s cooldown", #ActionsOf(4, "UseAbilityOnLocation") == 1)

	blockWorld({ Enable = true, CampBlock = true }, 0.6)
	check("skill 0.6 is not above the gate", #ActionsOf(4, "UseAbilityOnLocation") == 0)
end

do
	-- Their wave frozen at their tower (eqPos 0.8) for two cycles while their core denies twice a cycle.
	local function frozen(skill)
		local H, support, core, ecore, esup = world(skill, { coreAt = Vector(2500, 5000), at = Vector(2400, 5200),
			enemyCoreAt = Vector(2600, 5000), enemySupAt = Vector(-6000, 5000) })
		hide(esup, 4)
		LANE_FRONT[2][Lane.Top], LANE_FRONT[3][Lane.Top] = 0.7, 0.38
		local c1 = MakeCreep({ team = 3, x = 2700, y = 5000 })
		local c2 = MakeCreep({ team = 3, x = 2750, y = 5000 })
		for _, base in ipairs({ 60, 90 }) do
			ecore.target = c1
			tick(H, support, base + 1)
			ecore.target = c2
			tick(H, support, base + 2)
		end
		ecore.target = nil
		SetRandomSequence({ 0.0 })
		tick(H, support, 121)
		return H, support, core
	end
	local H, support = frozen(0.5)
	check("freeze noticed", #signalsOf(H, support, "freeze") == 1)
	check("support's override: shove", H.Lane.Hooks.TechniqueOverride(support) == "shove")
	SetRandomSequence({ 0.99, 0.0 })
	local c = H.Lane.LanePlanner.Plan(support, H.Lane.LaneState.ForBot(support))
	check("planner under HOLD shoves for the counter", c.tech == "shove" and c.reason == "counter: shove", c.tech .. " " .. c.reason)
	check("plan is HOLD", H.Lane.LanePlan.View(support, H.Lane.LaneState.ForBot(support)).plan == "HOLD")
	T = 179
	check("override lasts through the next cycle", H.Lane.Hooks.TechniqueOverride(support) == "shove")
	T = 181
	check("next-next cycle: override cleared", H.Lane.Hooks.TechniqueOverride(support) == nil)

	H, support = frozen(0.3)
	MakeCreep({ team = 2, x = 2500, y = 5000 })
	T = 122
	local loc = Vector(2000, 5000)
	check("support that cannot shove: no override", H.Lane.Hooks.TechniqueOverride(support) == nil)
	check("support that cannot shove zones instead", H.Lane.AdjustPosition(support, loc) ~= loc)
end

do
	local function midWorld(stronger)
		local H = LaneFresh({ Enable = true }, { skill = 1 })
		T, CURRENT_TEAM, OBSERVER = 100, 2, 2
		SPAWNERS = {}
		H.Lane.Camps.ResetCache()
		local mid = unit({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(-2800, 0) })
		unit({ pid = 7, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
		H.Lane.Config.SkillOf(mid)
		LANE_FRONT[2][Lane.Mid], LANE_FRONT[3][Lane.Mid] = 0.3, 0.65
		STRONGER = stronger
		NEXT_RUNE = 120
		tick(H, mid, 100)
		return H, mid
	end
	local H, mid = midWorld(true)
	check("rune shove noticed", #signalsOf(H, mid, "rune_shove") == 1)
	check("stronger: contest the rune", near(H.Lane.RuneContestDesire(mid), 0.6))
	T = 129.5
	check("still contesting 9.5 s after the rune", near(H.Lane.RuneContestDesire(mid), 0.6))
	T = 130.5
	check("contest ends 10 s after the rune", H.Lane.RuneContestDesire(mid) == 0)
	check("stronger: no shove override", H.Lane.Hooks.TechniqueOverride(mid) == nil)

	H, mid = midWorld(false)
	check("not stronger: no rune contest", H.Lane.RuneContestDesire(mid) == 0)
	check("not stronger: shove override", H.Lane.Hooks.TechniqueOverride(mid) == "shove")
end

do
	local function stackWorld(stronger)
		local H, support, core, ecore, esup = world(1, { at = Vector(1200, 5800) })
		esup.loc = Vector(THEIR_SMALL.x + 50, THEIR_SMALL.y + 50)
		STRONGER = stronger
		tick(H, support, 114)
		check("precondition: stack noticed", #signalsOf(H, support, "stack") == 1)
		return H, support, core, ecore, esup
	end
	local H, support, _, _, esup = stackWorld(true)
	H.Lane.Counter.Think(support, {})
	T = 114.6
	H.Lane.Counter.Think(support, {})
	check("stronger: one attack on the stacker", attacksOn(4, esup) == 1, attacksOn(4, esup))
	check("stronger: camp not marked", #H.Lane.Counter.MarkedStacked(2) == 0)

	local core
	H, support, core, _, esup = stackWorld(false)
	H.Lane.Counter.Think(support, {})
	check("not stronger: no attack on the stacker", attacksOn(4, esup) == 0)
	local marks = H.Lane.Counter.MarkedStacked(2)
	check("not stronger: their camp marked", #marks == 1 and marks[1] == 1)
	local camps = { { idx = 1, cattr = SPAWNERS[1] } }
	check("still laning: no stacked-camp preference", H.Lane.PreferStackedCamp(core, camps) == nil)
	LANING = false
	hide(esup, 3, 4)
	T = 120
	check("after laning, nobody near it: the core prefers it", H.Lane.PreferStackedCamp(core, camps) == camps[1])
	LAST_SEEN[15] = { location = Vector(1500, 6000), time_since_seen = 3 }
	T = 121
	check("enemy last seen 3 s ago beside it: no preference", H.Lane.PreferStackedCamp(core, camps) == nil)
	LAST_SEEN[15] = { location = Vector(1500, 6000), time_since_seen = 8 }
	T = 122
	check("seen 8 s ago: preferred again", H.Lane.PreferStackedCamp(core, camps) == camps[1])
	check("support is not a core: no preference", H.Lane.PreferStackedCamp(support, camps) == nil)
	T = 240
	check("mark expires after 2 minutes", H.Lane.PreferStackedCamp(core, camps) == nil)
end

do
	local function ssWorld(enemyVisible)
		local H = LaneFresh({ Enable = true }, { skill = 1 })
		T, CURRENT_TEAM, OBSERVER = 61, 2, 2
		SPAWNERS = {}
		H.Lane.Camps.ResetCache()
		unit({ pid = 1, pos = 1, bot = false, lane = Lane.Bot, loc = Vector(0, -5000) })
		local mid = unit({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(-2800, 0), dmg = 50 })
		local emid = unit({ pid = 7, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-2500, 0) })
		H.Lane.Config.SkillOf(mid)
		local said = {}
		H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
		LANE_FRONT[2][Lane.Mid], LANE_FRONT[3][Lane.Mid] = 0.3, 0.65
		tick(H, mid, 61)
		if not enemyVisible then
			hide(emid, 2)
			LAST_SEEN[7] = { location = Vector(-2500, 0), time_since_seen = 5 }
		end
		tick(H, mid, 91)
		tick(H, mid, 92)
		return H, mid, said
	end
	local H, mid, said = ssWorld(false)
	local ranged = MakeCreep({ team = 2, x = -2700, y = 0, hp = 40, maxhp = 300, name = "npc_dota_creep_goodguys_ranged" })
	check("ss mid said once", #said == 1 and said[1] == "say_lane_ss_mid", #said)
	check("ranged deny dropped", H.Lane.Counter.DropRangedDeny(2) == true)
	check("mid bot no longer prioritises the ranged deny", H.Lane.PickDeny(mid, { ranged }) == nil)
	T = 112
	check("ranged deny back after 20 s", H.Lane.Counter.DropRangedDeny(2) == false and H.Lane.PickDeny(mid, { ranged }) == ranged)

	H, mid, said = ssWorld(true)
	check("enemy mid visible: no ss mid", #said == 0)
	check("enemy mid visible: ranged deny kept", H.Lane.Counter.DropRangedDeny(2) == false)
end

do
	-- The same world with the defaults (positive control) and with CounterPlay off.
	local function scenario(cfg)
		local H, support, core, _, esup = world(1, { cfg = cfg })
		esup.loc = THEIR_SMALL
		tick(H, support, 75)
		local pulls = #signalsOf(H, support, "pull")
		tick(H, support, 114)
		LANING = false
		hide(esup, 3, 4)
		T = 120
		local prefer = H.Lane.PreferStackedCamp(core, { { idx = 1, cattr = SPAWNERS[1] } })
		T = 130
		local before = GETUNITLIST_CALLS[UnitType.EnemyHeroes] or 0
		H.Lane.Counter.Tick(support)
		local scanned = (GETUNITLIST_CALLS[UnitType.EnemyHeroes] or 0) > before
		return pulls, prefer, scanned
	end
	local pulls, prefer, scanned = scenario({ Enable = true })
	check("defaults: pull noticed", pulls == 1)
	check("defaults: stacked camp preferred", prefer ~= nil)
	check("defaults: Tick scans", scanned)
	pulls, prefer, scanned = scenario({ Enable = true, CounterPlay = false })
	check("CounterPlay off: no signals", pulls == 0)
	check("CounterPlay off: no stacked-camp preference", prefer == nil)
	check("CounterPlay off: Tick makes no scan", not scanned)

	local function rune(cfg)
		local H = LaneFresh(cfg, { skill = 1 })
		T, CURRENT_TEAM, OBSERVER = 100, 2, 2
		local mid = unit({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(-2800, 0) })
		unit({ pid = 7, team = 3, pos = 2, lane = Lane.Mid })
		H.Lane.Config.SkillOf(mid)
		LANE_FRONT[2][Lane.Mid], LANE_FRONT[3][Lane.Mid] = 0.3, 0.65
		STRONGER, NEXT_RUNE = true, 120
		tick(H, mid, 100)
		return H.Lane.RuneContestDesire(mid), #H.Lane.Counter.Signals(mid)
	end
	local d, n = rune({ Enable = true })
	check("defaults: rune contest desire", near(d, 0.6) and n == 1)
	d, n = rune({ Enable = true, CounterPlay = false })
	check("CounterPlay off: rune contest desire 0", d == 0 and n == 0)
end

do
	local function read(path) return io.open(HARNESS_DIR .. "/../../" .. path, "r"):read("a") end
	check("farm mode prefers a marked stacked camp", read("bots/mode_farm_generic.lua"):find("preferedCamp = J.Humaniser.Lane.PreferStackedCamp(bot, availableCamp) or preferedCamp", 1, true) ~= nil)
	check("rune mode takes the lane's rune contest desire", read("bots/mode_rune_generic.lua"):find("local nLaneContest = J.Humaniser.Lane.RuneContestDesire(bot)", 1, true) ~= nil)
	local loc = read("bots/FunLib/localization.lua")
	for _, key in ipairs({ "say_lane_they_pull_top", "say_lane_they_pull_mid", "say_lane_they_pull_bot", "say_lane_their_sup_missing", "say_lane_they_freeze", "say_lane_ss_mid" }) do
		local _, n = loc:gsub(key .. " = ", "")
		check(key .. " in all four languages", n == 4, n)
	end
end

finish()
