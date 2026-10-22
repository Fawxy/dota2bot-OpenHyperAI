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
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill, telemetry = opts.telemetry })
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
	-- The enemy's pull seconds come from their wave (pull_timing) when their camp is wave-timed, as ours do: with a Dire
	-- creep path along the stub top lane their small camp pulls at :18.3 (half :21.4), so a support unseen by it at :25
	-- reads as pulling; on the :15/:17 seeds it did not (8 s off, CounterPullWindow 6).
	local WAVE = { Enable = true, PullTiming = { LanePaths = { dire_top = { { 9400, 5000 }, { -7000, 5000 } } } } }
	local function at25(cfg)
		local H, support, _, _, esup = world(1, { cfg = cfg })
		-- Seen in lane first, so its position is known.
		tick(H, support, 80)
		hide(esup, 4)
		LAST_SEEN[15] = { location = Vector(THEIR_SMALL.x, THEIR_SMALL.y - 500), time_since_seen = 5 }
		tick(H, support, 85)
		LAST_SEEN[15] = nil
		return #signalsOf(H, support, "pull")
	end
	check("seed seconds: unseen support at :25 not suspected", at25(nil) == 0)
	check("wave-timed seconds: unseen support at :25 suspected", at25(WAVE) == 1)
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

	H, support = pulled()
	H.Lane.Counter.Think(support, {})
	local job = H.Lane.CampJobs.Current(support)
	check("not stronger, enemy core in our lane: contest job at their camp", job ~= nil and job.kind == "contest" and job.campIdx == 1 and job.targetPid == 15)
	check("contest is the cycle's technique", H.Lane.LanePlanner.Committed(support) == "contest")
	check("contest desire", near(H.Lane.CampJobDesire(support), 0.65))

	H, support = pulled()
	local mid = unit({ pid = 12, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-6000, 0) })
	hide(mid, 4)
	-- 632 from the camp end of the route, 2,500 from our front: a third enemy, not one of this lane's laners.
	LAST_SEEN[12] = { location = Vector(1800, 6800), time_since_seen = 2 }
	T = 76
	H.Lane.Counter.Think(support, {})
	check("unsafe path: no contest", H.Lane.CampJobs.Current(support) == nil)
	check("unsafe path: no attack", #ActionsOf(4, "AttackUnit") == 0)

	H, support = pulled()
	mid = unit({ pid = 12, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-6000, 0) })
	hide(mid, 4)
	LAST_SEEN[12] = { location = Vector(1800, 6800), time_since_seen = 8 }
	T = 76
	H.Lane.Counter.Think(support, {})
	check("third enemy seen 8 s ago: contest goes ahead", H.Lane.CampJobs.Current(support) ~= nil)
end

do
	-- The contest executor: walk to the camp, hit the visible puller every 2.5 s, give up after 10 s.
	local H, support, _, _, esup = world(1)
	esup.loc = THEIR_SMALL
	tick(H, support, 75)
	H.Lane.Counter.Think(support, {})
	-- Visible but 2,000 from the camp: the contest does not chase it.
	esup.loc = Vector(THEIR_SMALL.x + 2000, THEIR_SMALL.y)
	T = 75.6
	H.Lane.CampJobThink(support)
	local moves = ActionsOf(4, "MoveToLocation")
	check("contest walks to their camp", #moves == 1 and moves[1].args[1].x == THEIR_SMALL.x and moves[1].args[1].y == THEIR_SMALL.y)
	check("puller far from the camp is not chased", attacksOn(4, esup) == 0)
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
	-- Support at (0, 5300): 1,836 from the camp at 300 speed is a 6.1 s walk.
	local function blockWorld(cfg, skill, at, setup)
		local H, support = world(skill, { cfg = cfg })
		local ward = { GetName = function() return "item_ward_sentry" end }
		support.GetItemInSlot = function(_, i) if i == 0 then return ward end end
		if setup then setup() end
		T = at or 110
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
	T = 111
	check("walking to plant keeps the frame", H.Lane.Counter.Think(support, {}) == true)
	T = 170
	H.Lane.Counter.Think(support, {})
	check("60 s later: still on the 180 s cooldown", #ActionsOf(4, "UseAbilityOnLocation") == 1)

	blockWorld({ Enable = true, CampBlock = true }, 0.6)
	check("skill 0.6 is not above the gate", #ActionsOf(4, "UseAbilityOnLocation") == 0)

	blockWorld({ Enable = true, CampBlock = true }, 0.7, 114)
	check(":54 with a 6.1 s walk: cannot plant before :58", #ActionsOf(4, "UseAbilityOnLocation") == 0)

	blockWorld({ Enable = true, CampBlock = true }, 0.7, 110, function()
		local mid = unit({ pid = 12, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-6000, 0) })
		hide(mid, 4)
		LAST_SEEN[12] = { location = Vector(1800, 6800), time_since_seen = 2 }
	end)
	check("enemy near the route: no camp block", #ActionsOf(4, "UseAbilityOnLocation") == 0)
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
	STRONGER = true
	check("freeze noticed", #signalsOf(H, support, "freeze") == 1)
	check("stronger support's override: shove", H.Lane.Hooks.TechniqueOverride(support) == "shove")
	SetRandomSequence({ 0.99, 0.0 })
	local c = H.Lane.LanePlanner.Plan(support, H.Lane.LaneState.ForBot(support))
	check("planner under HOLD shoves for the counter", c.tech == "shove" and c.reason == "counter: shove", c.tech .. " " .. c.reason)
	check("plan is HOLD", H.Lane.LanePlan.View(support, H.Lane.LaneState.ForBot(support)).plan == "HOLD")
	-- The wave moves back to mid-lane, out of their tower's reach: the shove executor hits a creep.
	LANE_FRONT[2][Lane.Top], LANE_FRONT[3][Lane.Top] = 0.5, 0.5
	local n1 = MakeCreep({ team = 3, x = 100, y = 5000, hp = 300 })
	local n2 = MakeCreep({ team = 3, x = 150, y = 5000 })
	T = 122
	check("shove issued under the override", H.Lane.Think(support, {}, { n1, n2 }, {}) == true and attacksOn(4, n1) == 1)
	support.hp = 40
	check("below ShoveMinHP: no shove override", H.Lane.Hooks.TechniqueOverride(support) == nil)
	support.hp = 100
	T = 179
	check("override lasts through the next cycle", H.Lane.Hooks.TechniqueOverride(support) == "shove")
	T = 181
	check("next-next cycle: override cleared", H.Lane.Hooks.TechniqueOverride(support) == nil)

	H, support = frozen(0.5)
	STRONGER = false
	MakeCreep({ team = 2, x = 2500, y = 5000 })
	T = 122
	local loc = Vector(2000, 5000)
	check("not stronger: no shove override", H.Lane.Hooks.TechniqueOverride(support) == nil)
	check("not stronger: zones instead", H.Lane.AdjustPosition(support, loc) ~= loc)
	SetRandomSequence({ 0.99, 0.0, 0.0 })
	c = H.Lane.LanePlanner.Plan(support, H.Lane.LaneState.ForBot(support))
	check("not stronger: planner not stuck on shove", c.tech ~= "shove", c.tech .. " " .. c.reason)

	H, support = frozen(0.3)
	STRONGER = true
	MakeCreep({ team = 2, x = 2500, y = 5000 })
	T = 122
	local loc = Vector(2000, 5000)
	loc = Vector(2000, 5000)
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
		unit({ pid = 7, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-2600, 0) })
		MakeCreep({ team = 2, x = -2700, y = 0 })
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
	check("not stronger: no shove override", H.Lane.Hooks.TechniqueOverride(mid) == nil)
	local here = Vector(-3000, 0)
	check("not stronger: zones until the rune", H.Lane.AdjustPosition(mid, here) ~= here)
	T = 121
	check("after the rune: no zoning", H.Lane.AdjustPosition(mid, here) == here)
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
	local H, support, _, ecore, esup = stackWorld(true)
	H.Lane.Counter.Think(support, {})
	T = 114.6
	local held = H.Lane.Counter.Think(support, {})
	check("stronger: one attack on the stacker", attacksOn(4, esup) == 1, attacksOn(4, esup))
	check("frame held until the hit lands", held == true and #ActionsOf(4) == 1)
	support.lastAttack = GameTime()
	T = 115.2
	H.Lane.Counter.Think(support, {})
	check("hit landed: frame released (the pull punish follows)", attacksOn(4, esup) == 1 and attacksOn(4, ecore) == 1)
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
	check("rune mode takes the lane's rune contest desire", read("bots/mode_rune_generic.lua"):find("math.max(X.PowerRuneDesire(rune, nProximityRadius), J.Humaniser.Lane.RuneContestDesire(bot))", 1, true) ~= nil)
	local loc = read("bots/FunLib/localization.lua")
	for _, key in ipairs({ "say_lane_they_pull_top", "say_lane_they_pull_mid", "say_lane_they_pull_bot", "say_lane_their_sup_missing", "say_lane_they_freeze", "say_lane_ss_mid" }) do
		local _, n = loc:gsub(key .. " = ", "")
		check(key .. " in all four languages", n == 4, n)
	end
end

do
	-- Both laners notice the same pull instance; the team posts one line.
	local H, support, core, _, esup = world(1)
	unit({ pid = 1, pos = 2, bot = false, lane = Lane.Mid, loc = Vector(0, 0) })
	local said = {}
	H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
	esup.loc = THEIR_SMALL
	RANDOM_FRACTION = 0
	tick(H, support, 75)
	tick(H, core, 75)
	RANDOM_FRACTION = nil
	check("precondition: both laners noticed the pull", #signalsOf(H, support, "pull") == 1 and #signalsOf(H, core, "pull") == 1)
	check("one telegraph for one instance", #said == 1 and said[1] == "say_lane_they_pull_top", #said)
	tick(H, core, 105)
	check("the next instance is telegraphed again", #said == 2, #said)
end

do
	local C = LaneFresh({ Enable = true }).Lane.Counter
	-- Our top is the enemy's safe lane (desired -0.7); our forecast eq -0.6 is their 0.6.
	local base = { now = 60, forecastEq = -0.6, enemyDesiredEq = -0.7, pullSec = { 15, 45 }, supportInLane = true }
	local function with(o) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(o) do t[k] = v end return t end
	check("lane drifting to their tower: pull expected at :15", C.EnemyPullExpected(base) == 75)
	check("lane at their wanted spot: no pull expected", C.EnemyPullExpected(with({ forecastEq = 0.7 })) == nil)
	check("support not in lane: none", C.EnemyPullExpected(with({ supportInLane = false })) == nil)
	check("no pull seconds: none", C.EnemyPullExpected(with({ pullSec = {} })) == nil)
	check("camps not up before 1:00: none", C.EnemyPullExpected(with({ now = 0, pullSec = { 15 } })) == nil)
	-- Their score is forecastEq - 0.7: the band ends at Planner.FullPullBelow (-0.5), forecastEq 0.2.
	check("lane only slightly toward our side (0.3): none", C.EnemyPullExpected(with({ forecastEq = 0.3 })) == nil)
	check("lane past 0.2 toward our tower (0.1): expected", C.EnemyPullExpected(with({ forecastEq = 0.1 })) == 75)
end

do
	-- Mirroring: our top is the enemy's safe lane, so their wanted eq is Eq.Safe, whatever ours (Eq.Off) is.
	local function expectedWith(eq)
		local H, support = world(1, { cfg = { Enable = true, Eq = eq } })
		LANE_FRONT[2][Lane.Top], LANE_FRONT[3][Lane.Top] = 0.5, 0.5
		RANDOM_FRACTION = 0
		tick(H, support, 61)
		RANDOM_FRACTION = nil
		return H.Lane.LaneState.ForBot(support).forecastEq, #signalsOf(H, support, "pull_expected")
	end
	local feq, n = expectedWith({ Safe = -0.7, Off = -0.4 })
	check("fixture: a level lane, forecast 0", near(feq, 0), feq)
	check("their safe lane wants -0.7: a level lane drifts from it, pull expected", n == 1, n)
	_, n = expectedWith({ Safe = -0.4, Off = -0.7 })
	check("their safe lane wants -0.4: a level lane does not, none", n == 0, n)
end

do
	-- Our lane drifts toward our tower (forecast about -0.6): the enemy support in lane will want to pull.
	local said
	local function expected(skill, cfg, seen)
		local H, support, _, _, esup = world(skill, { cfg = cfg })
		said = {}
		H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
		LANE_FRONT[2][Lane.Top], LANE_FRONT[3][Lane.Top] = 0.38, 0.62 -- both fronts meet at 0.38 of our lane: eqPos -0.6
		if seen == false then hide(esup, 4) end
		RANDOM_FRACTION = 0
		tick(H, support, 61)
		RANDOM_FRACTION = nil
		return H, support, signalsOf(H, support, "pull_expected")
	end
	local H, support, sigs = expected(1)
	local feq = H.Lane.LaneState.ForBot(support).forecastEq
	check("fixture: our forecast reads about -0.6", feq < -0.5 and feq > -0.7, feq)
	check("one pull_expected, aggro at :15", #sigs == 1 and sigs[1].aggroAt == 75 and sigs[1].campIdx == 1 and sigs[1].enemyPid == 15, #sigs)
	check("no pull_expected chat line", #said == 0, #said)
	check("below the PreContest gate: none", #select(3, expected(0.6)) == 0)
	check("PreContest off: none", #select(3, expected(1, { Enable = true, PreContest = false })) == 0)
	check("enemy support never seen: none", #select(3, expected(1, nil, false)) == 0)
end

do
	local p = LaneFresh({ Enable = true }).Lane.CampJobs.LookoutPoint(Vector(0, 0), { Vector(0, 300), Vector(1000, 300) }, 400)
	check("lookout point is 400 along the polyline", near(p.x, 100) and near(p.y, 300), p.x .. "," .. p.y)
	p = LaneFresh({ Enable = true }).Lane.CampJobs.LookoutPoint(Vector(0, 0), { Vector(200, 0) }, 400)
	check("short path: lookout at its end", near(p.x, 200) and near(p.y, 0))
end

do
	-- Pre-contest: our lane drifts toward our tower, so the enemy support is expected to pull their small camp at
	-- 1:15. It then walks off into the fog, leaving our core 1v1.
	local function expecting(opts)
		opts = opts or {}
		-- Their core at the fronts' meeting point (x -1680), a laner, so not a threat on the route.
		local H, support, core, _, esup = world(1, { at = opts.at, enemyCoreAt = Vector(-1500, 5000), telemetry = { Enable = true } })
		local lines = {}
		H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
		LANE_FRONT[2][Lane.Top], LANE_FRONT[3][Lane.Top] = 0.38, 0.62
		RANDOM_FRACTION = 0
		tick(H, support, opts.signalAt or 61)
		RANDOM_FRACTION = nil
		local data = H.Lane.Camps.ByIdx(1)
		local origin = H.Lane.Camps.SpawnerByIdx(1).location
		local look = H.Lane.CampJobs.LookoutPoint(origin, H.Lane.PullTiming.LeadPath(data.pull, data.pull.meetPoint), 400)
		local travel = H.Lane.CampJobs.TravelTime(GetUnitToLocationDistance(support, look), 300)
		return H, support, esup, lines, look, travel, core
	end
	local function endsWith(lines, reason)
		for _, l in ipairs(lines) do
			if l:find(" ev=lane_job_end ", 1, true) and l:find("kind=contest camp=1 reason=" .. reason .. " pre=1", 1, true) then return true end
		end
		return false
	end
	local function starts(lines)
		local n = 0
		for _, l in ipairs(lines) do if l:find(" ev=lane_job_start ", 1, true) then n = n + 1 end end
		return n
	end
	-- Counter Tick and Think every 0.5 s from `from` to `to`; the time of the first lane_job_start, if any.
	local function run(H, support, lines, from, to, each)
		local before, started = starts(lines), nil
		RANDOM_FRACTION = 0
		for t = from, to, 0.5 do
			if each ~= nil then each(t) end
			tick(H, support, t)
			H.Lane.Counter.Think(support, {})
			if started == nil and starts(lines) > before then started = t end
		end
		RANDOM_FRACTION = nil
		return started
	end
	local function startedPre(lines)
		for _, l in ipairs(lines) do if l:find(" ev=lane_job_start ", 1, true) and l:find("pre=1", 1, true) then return true end end
		return false
	end
	-- One executor frame as farm mode runs it: the desire query, then Think.
	local function frame(H, support, t)
		T = t
		H.Lane.CampJobDesire(support)
		H.Lane.CampJobThink(support)
		local job = H.Lane.CampJobs.Current(support)
		return job ~= nil and job.phase or "none"
	end
	-- Leaves just inside its last second: aggro 75, 2 s early, minus the walk.
	-- The departure re-check still sees their support in lane; it walks off into the fog once ours has set out.
	local function begin(H, support, esup, look, travel)
		T = 73 - travel - 0.05
		H.Lane.Counter.Think(support, {})
		hide(esup, 4)
		H.Lane.CampJobThink(support)
		support.loc = look
	end

	local H, support, esup, lines, look, travel = expecting()
	check("fixture: lookout walk under MaxTravel", travel > 4 and travel < 7, travel)
	T = 73 - travel - 1.2
	H.Lane.Counter.Think(support, {})
	check("more than a second early: no job yet", H.Lane.CampJobs.Current(support) == nil)
	T = 73 - travel - 0.05
	H.Lane.Counter.Think(support, {})
	hide(esup, 4)
	local job = H.Lane.CampJobs.Current(support)
	check("pull expected: a contest job in its lookout", job ~= nil and job.kind == "contest" and job.phase == "lookout", job and job.phase)
	check("the contest is this cycle's commit", H.Lane.LanePlanner.Committed(support) == "contest")
	check("lane_job_start marks the pre-contest", startedPre(lines))
	H.Lane.CampJobThink(support)
	local moves = ActionsOf(4, "MoveToLocation")
	check("walks to the lookout point", #moves == 1 and near(moves[1].args[1].x, look.x) and near(moves[1].args[1].y, look.y),
		#moves > 0 and (moves[1].args[1].x .. "," .. moves[1].args[1].y) or "no move")
	support.loc = look
	T = 72
	check("at the lookout: keeps the frame", H.Lane.CampJobThink(support) == true)
	frame(H, support, 74)
	check("waits there without a new order", #ActionsOf(4, "MoveToLocation") == 1 and #ActionsOf(4, "AttackUnit") == 0)
	check("the wait is a hold", H.Intent.HeldBy(support) == "lane:precontest", H.Intent.HeldBy(support))
	show(esup)
	esup.loc = THEIR_SMALL
	T = 75
	H.Lane.CampJobThink(support)
	check("the support shows up at their camp: hit it", attacksOn(4, esup) == 1)
	check("out of the lookout once it is fighting", H.Lane.CampJobs.Current(support).phase ~= "lookout")

	H, support, esup, lines, look, travel = expecting()
	begin(H, support, esup, look, travel)
	local front = H.Lane.LaneState.ForBot(support).frontLoc
	show(esup)
	esup.loc = front
	check("their support still in lane before aggro - 2: keeps waiting", frame(H, support, 72.5) == "lookout")
	frame(H, support, 73.5)
	check("their support stays in lane: walk back", H.Lane.CampJobDesire(support) == 0 and endsWith(lines, "enemy-in-lane"))
	check("an enemy-in-lane end rests the bot's pre-contests in that lane", H.Lane.CampJobs.PreContestResting(support, Lane.Top))

	H, support, esup, lines, look, travel = expecting()
	begin(H, support, esup, look, travel)
	frame(H, support, 74)
	frame(H, support, 76)
	-- Started about 7.5 s before the aggro: 10 s from the start would already be over.
	check("no pull yet at 1:18: still waiting", frame(H, support, 78) == "lookout")
	frame(H, support, 79.1)
	check("nothing by aggro + 4: walk back, no-pull", H.Lane.CampJobDesire(support) == 0 and endsWith(lines, "no-pull"))

	H, support, esup, lines, look, travel = expecting()
	begin(H, support, esup, look, travel)
	show(esup)
	esup.loc = THEIR_SMALL
	local phase
	for _, t in ipairs({ 76, 78.5, 81, 83.5, 85 }) do phase = frame(H, support, t) end
	check("ContestMax counts from the first hit: live at 85", phase == "travel" and attacksOn(4, esup) == 4, phase .. " " .. attacksOn(4, esup))
	T = 86.1
	check("over 10 s after the first hit", H.Lane.CampJobDesire(support) == 0 and endsWith(lines, "timeout"))

	H, support, esup, lines, look, travel = expecting()
	H.Lane.LanePlanner.Commit(support, "full_pull")
	T = 73 - travel - 0.05
	H.Lane.Counter.Think(support, {})
	check("another technique committed this cycle: no pre-contest", H.Lane.CampJobs.Current(support) == nil)

	H, support, esup, lines, look, travel = expecting()
	T = 74
	H.Lane.Counter.Think(support, {})
	check("too late to reach the lookout by aggro - 2: no pre-contest", H.Lane.CampJobs.Current(support) == nil)

	-- 5,000 from the lookout is a 16.7 s walk; the 1:45 pull (seen at 1:16) leaves time to set out, MaxTravel forbids it.
	H, support, esup, lines, look, travel = expecting({ at = Vector(-3400, 5800), signalAt = 76 })
	check("fixture: far support's walk over MaxTravel", travel > 12, travel)
	T = 103 - travel - 0.05
	H.Lane.Counter.Think(support, {})
	check("lookout over 12 s away: no pre-contest", H.Lane.CampJobs.Current(support) == nil)

	-- 1:15's instance is first seen at 0:46, the tick after the 0:45 aggro: it stays live until its own aggro.
	H, support, esup, lines, look, travel = expecting({ signalAt = 46 })
	local started = run(H, support, lines, 46.5, 80)
	check("seen 29 s before the aggro: sets out in its departure window", started ~= nil and started >= 72 - travel and started <= 73 - travel,
		tostring(started) .. " window " .. (72 - travel) .. ".." .. (73 - travel))
	check("and it is the pre-contest", startedPre(lines))

	H, support, esup, lines, look, travel = expecting({ signalAt = 46 })
	started = run(H, support, lines, 46.5, 80, function(t)
		if t == 60 then LANE_FRONT[2][Lane.Top], LANE_FRONT[3][Lane.Top] = 0.62, 0.38 end
	end)
	local feq = H.Lane.LaneState.ForBot(support).forecastEq
	check("fixture: by departure the lane sits toward their tower", feq > 0.2, feq)
	check("lane no longer drifting at departure: no job", started == nil, started)

	H, support, esup, lines, look, travel = expecting({ signalAt = 46 })
	started = run(H, support, lines, 46.5, 80, function(t) if t == 60 then hide(esup, 4) end end)
	check("their support gone from lane at departure: no job", started == nil, started)

	-- The pull the pre-contest waited for comes anyway: neither its cycle's nor the next cycle's pull signal is contested again.
	H, support, esup, lines, look, travel = expecting()
	begin(H, support, esup, look, travel)
	show(esup)
	esup.loc = THEIR_SMALL
	RANDOM_FRACTION = 0
	tick(H, support, 75)
	RANDOM_FRACTION = nil
	check("precondition: the pull itself is noticed", #signalsOf(H, support, "pull") == 1)
	frame(H, support, 75)
	check("precondition: the pre-contest hits the puller", attacksOn(4, esup) == 1)
	hide(esup, 4)
	frame(H, support, 76)
	check("precondition: puller lost, ends no-target", endsWith(lines, "no-target"))
	check("a contest that attacked does not rest the bot", not H.Lane.CampJobs.PreContestResting(support, Lane.Top))
	started = run(H, support, lines, 76.5, 91)
	check("the next wave cycle starts no second contest for that pull", started == nil and starts(lines) == 1, started)
	show(esup)
	started = run(H, support, lines, 91.5, 94)
	check("precondition: the next cycle's pull at their camp is noticed", #signalsOf(H, support, "pull") == 2, #signalsOf(H, support, "pull"))
	check("nor for the next cycle's pull signal of that camp", started == nil and starts(lines) == 1, started)

	-- After a no-pull, no pre-contest in that lane for Timing.PreContestCooldown (60 s).
	H, support, esup, lines, look, travel = expecting()
	begin(H, support, esup, look, travel)
	frame(H, support, 74)
	frame(H, support, 76)
	frame(H, support, 79.1)
	check("precondition: ends no-pull at 1:19.1", endsWith(lines, "no-pull"))
	show(esup)
	started = run(H, support, lines, 79.5, 139)
	check("1:45 and 2:15 expected pulls within 60 s: no pre-contest", started == nil, started)
	started = run(H, support, lines, 139.5, 165)
	check("2:45's expected pull after the 60 s: pre-contest", started ~= nil and started > 139.1 and starts(lines) == 2, started)

	-- The partner-safety guards.
	H, support, esup, lines, look, travel, core = expecting()
	core.hp = 30
	T = 73 - travel - 0.05
	H.Lane.Counter.Think(support, {})
	check("partner at 30% HP: no pre-contest", H.Lane.CampJobs.Current(support) == nil)
	H, support, esup, lines, look, travel, core = expecting()
	core.hp = 100
	T = 73 - travel - 0.05
	H.Lane.Counter.Think(support, {})
	check("partner at 100% HP: it starts", H.Lane.CampJobs.Current(support) ~= nil)

	H, support, esup, lines, look, travel, core = expecting()
	begin(H, support, esup, look, travel)
	check("precondition: at the lookout", frame(H, support, 72) == "lookout")
	core.hp = 20
	local phase = frame(H, support, 72.5)
	check("partner drops to 20% in the lookout: walk back", phase == "return" and H.Lane.CampJobDesire(support) == 0, phase)
	local aborted
	for _, l in ipairs(lines) do
		if l:find(" ev=lane_job_abort ", 1, true) and l:find("reason=partner-low-hp", 1, true) then aborted = l end
	end
	check("a partner-low-hp abort", aborted ~= nil)
	check("the abort of a pre-contest carries pre=1", aborted ~= nil and aborted:find("pre=1", 1, true) ~= nil, aborted)
end

do
	-- Take the pull: their support pulls their small camp at 1:15 and our core (pid 3, not the lane's camp-job owner)
	-- has no enemy creeps left at its front. Their Dire top T1 stands 1,697 from the camp, outside its 850 range.
	local function taking(opts)
		opts = opts or {}
		local H, support, core, ecore, esup = world(opts.skill or 1, { cfg = opts.cfg, telemetry = { Enable = true } })
		OBSERVER = 3
		H.LastHitSkill.SetHelpers({ WillKillTarget = function(c, dmg) return dmg >= c:GetHealth() end })
		local lines = {}
		H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
		esup.loc = THEIR_SMALL
		for i = 1, (opts.laneCreeps or 0) do MakeCreep({ team = 3, x = 100 + i * 20, y = 5000 }) end
		if opts.setup ~= nil then opts.setup(H, core) end
		RANDOM_FRACTION = 0
		tick(H, core, 75)
		RANDOM_FRACTION = nil
		check("precondition: the core noticed the pull", #signalsOf(H, core, "pull") == 1)
		T = 75.5
		H.Lane.Counter.Think(core, {})
		return H, core, H.Lane.CampJobs.Current(core), lines, ecore, esup, support
	end
	local function frame(H, bot, t)
		T = t
		local d = H.Lane.CampJobDesire(bot)
		H.Lane.CampJobThink(bot)
		return d
	end
	local function ended(lines)
		for _, l in ipairs(lines) do if l:find(" ev=lane_job_end ", 1, true) then return l end end
		return nil
	end

	local H, core, job, lines, _, _, support = taking()
	check("not the owner, empty lane: the core takes their pull", job ~= nil and job.kind == "contest" and job.take == true and job.campIdx == 1)
	check("the take is the cycle's commit", H.Lane.LanePlanner.Committed(core) == "contest")
	local start
	for _, l in ipairs(lines) do if l:find(" ev=lane_job_start ", 1, true) then start = l end end
	check("lane_job_start marks the take", start ~= nil and start:find("pid=3", 1, true) ~= nil and start:find("take=1", 1, true) ~= nil, start)
	OBSERVER = 4
	tick(H, support, 75)
	T = 75.5
	H.Lane.Counter.Think(support, {})
	local own = H.Lane.CampJobs.Current(support)
	check("the owner's answer stays a contest of the puller", own ~= nil and own.kind == "contest" and own.take ~= true)

	local asOwner = select(3, taking({ setup = function(_, c) c.pos = 5 end }))
	check("the owner contests rather than takes", asOwner ~= nil and asOwner.kind == "contest" and asOwner.take ~= true)
	check("two enemy creeps still at our front: no take", select(3, taking({ laneCreeps = 2 })) == nil)
	check("one enemy creep at our front: take", select(3, taking({ laneCreeps = 1 })) ~= nil)
	check("skill 0.4: no take", select(3, taking({ skill = 0.4 })) == nil)
	check("TakePull off: no take", select(3, taking({ cfg = { Enable = true, TakePull = false } })) == nil)
	check("their tower beside the camp: no take", select(3, taking({ setup = function()
		TOWERS_W[3][dota.Tower.Top1].loc = Vector(THEIR_SMALL.x + 300, THEIR_SMALL.y)
	end })) == nil)
	check("a third enemy seen near the route: no take", select(3, taking({ setup = function()
		local mid = unit({ pid = 12, team = 3, pos = 2, lane = Lane.Mid, loc = Vector(-6000, 0) })
		hide(mid, 3)
		LAST_SEEN[12] = { location = Vector(1800, 6800), time_since_seen = 2 }
	end })) == nil)

	-- The executor.
	H, core, job, lines = taking()
	local d = frame(H, core, 76)
	local moves = ActionsOf(3, "MoveToLocation")
	check("take walks to their camp", #moves == 1 and moves[1].args[1].x == THEIR_SMALL.x and moves[1].args[1].y == THEIR_SMALL.y)
	check("take desire is the contest's", near(d, 0.65), d)
	core.loc = Vector(THEIR_SMALL.x, THEIR_SMALL.y)
	local creep = MakeCreep({ team = 3, x = THEIR_SMALL.x + 200, y = THEIR_SMALL.y, hp = 300 })
	d = frame(H, core, 77)
	check("a non-owner's take is not aborted as not-owner", near(d, 0.65), d)
	check("a creep it cannot kill is not hit", attacksOn(3, creep) == 0)
	check("waits by the pulled creeps", H.Intent.HeldBy(core) == "lane:take_pull", H.Intent.HeldBy(core))
	creep.hp = 30
	RANDOM_FRACTION = 0
	frame(H, core, 77.5)
	RANDOM_FRACTION = nil
	check("last-hits the killable pulled creep", attacksOn(3, creep) == 1, attacksOn(3, creep))
	frame(H, core, 77.8)
	check("one swing per creep", attacksOn(3, creep) == 1, attacksOn(3, creep))
	creep.hp = 0
	frame(H, core, 79)
	check("no creeps for under 3 s: still there", H.Lane.CampJobs.Active(core))
	frame(H, core, 81.1)
	check("no creeps for 3 s: the take ends", not H.Lane.CampJobs.Active(core))
	local e = ended(lines)
	check("lane_job_end: no-creeps, take=1, one swing", e ~= nil and e:find("reason=no-creeps", 1, true) ~= nil
		and e:find("take=1", 1, true) ~= nil and e:find("swings=1", 1, true) ~= nil, e)

	H, core, job, lines = taking()
	core.loc = Vector(THEIR_SMALL.x, THEIR_SMALL.y)
	MakeCreep({ team = 3, x = THEIR_SMALL.x + 200, y = THEIR_SMALL.y, hp = 300 })
	frame(H, core, 76)
	check("precondition: taking with one enemy hero by it", H.Lane.CampJobs.Active(core))
	local ecore
	H, core, job, lines, ecore = taking()
	core.loc = Vector(THEIR_SMALL.x, THEIR_SMALL.y)
	ecore.loc = Vector(THEIR_SMALL.x + 400, THEIR_SMALL.y)
	frame(H, core, 76)
	e = ended(lines)
	check("two enemy heroes by it: the take ends outnumbered", not H.Lane.CampJobs.Active(core) and e ~= nil and e:find("reason=outnumbered", 1, true) ~= nil, e)

	H, core, job, lines = taking()
	core.loc = Vector(THEIR_SMALL.x, THEIR_SMALL.y)
	MakeCreep({ team = 3, x = THEIR_SMALL.x + 200, y = THEIR_SMALL.y, hp = 300 })
	frame(H, core, 89)
	check("14.5 s in: still taking", H.Lane.CampJobs.Active(core))
	frame(H, core, 90.6)
	e = ended(lines)
	check("15 s after its start: the take ends on timeout", not H.Lane.CampJobs.Active(core) and e ~= nil and e:find("reason=timeout", 1, true) ~= nil, e)

	H, core, job, lines = taking()
	frame(H, core, 76)
	H.Lane.CampJobs.OnEnd(core)
	local aborted
	for _, l in ipairs(lines) do if l:find(" ev=lane_job_abort ", 1, true) then aborted = l end end
	check("a take's abort carries take=1", aborted ~= nil and aborted:find("take=1", 1, true) ~= nil, aborted)
end

finish()
