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
	u.lane, u.pos, u.dmg, u.name = o.lane or Lane.Top, o.pos, o.dmg, o.name
	return u
end

local function hide(u, ...) u.hiddenFrom = {} for _, pid in ipairs({ ... }) do u.hiddenFrom[pid] = true end end
local function show(u) u.hiddenFrom = nil end

-- Radiant top (our offlane): core pid 3 (pos 3) and support pid 4 (pos 4); Dire laners: Anti-Mage pid 11 and
-- Crystal Maiden pid 15, the support. The support observes. Only the Dire small camp exists. Both Dire heroes have
-- laned at our front for the 11 s before `t` (opts.unlaned skips that), so counter-play knows CM as their support.
local function world(skill, opts)
	opts = opts or {}
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill, telemetry = opts.telemetry })
	local start = opts.t or 60
	CURRENT_TEAM = 2
	OBSERVER = 4
	SPAWNERS = { spawner(3, "small", THEIR_SMALL) }
	H.Lane.Camps.ResetCache()
	local core = unit({ pid = 3, pos = 3, loc = opts.coreAt })
	local support = unit({ pid = 4, pos = 4, loc = opts.at or Vector(0, 5300) })
	local ecore = unit({ pid = 11, team = 3, pos = 1, loc = Vector(300, 5000), name = "npc_dota_hero_antimage" })
	local esup = unit({ pid = 15, team = 3, pos = 5, loc = Vector(-300, 5000), name = "npc_dota_hero_crystal_maiden" })
	H.Lane.Config.SkillOf(support)
	H.Lane.Config.SkillOf(core)
	if not opts.unlaned then
		for t = start - 12, start - 1, 1 do
			T = t
			H.Lane.Counter.Tick(support)
		end
	end
	T = start
	ecore.loc = opts.enemyCoreAt or ecore.loc
	esup.loc = opts.enemySupAt or esup.loc
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
	-- The puller's stand is 400 below the box centre. console.9057255027 / 9057261947 and four earlier games
	-- (scratch replay of 29 real pulls): within 300 of where a puller stands, within 3 s of the aggro second, caught 20
	-- with 14 false; the old rule (800 of the box, any time if visible, 6 s if not) caught 29 with 81 false.
	local STAND = Vector(THEIR_SMALL.x, THEIR_SMALL.y - 400)
	local function input(now, unseen, loc, visible)
		return { now = now, campLoc = THEIR_SMALL, standLoc = STAND, campPullSec = { 15, 45 },
			enemySupport = { pid = 15, visible = visible == true, location = loc, timeSinceSeen = unseen } }
	end
	local lastSeen = Vector(STAND.x, STAND.y - 700)
	check("unseen 5 s, last seen 700 from the stand, :14 -> suspected", C.EnemyPullSuspected(input(74, 5, lastSeen)))
	check("unseen only 3 s -> not suspected", not C.EnemyPullSuspected(input(74, 3, lastSeen)))
	check(":21 is outside the 3 s window -> not suspected", not C.EnemyPullSuspected(input(81, 5, lastSeen)))
	check("last seen 1,000 from the stand -> not suspected", not C.EnemyPullSuspected(input(74, 5, Vector(STAND.x, STAND.y - 1000))))
	check("visible at its stand at :16 -> suspected", C.EnemyPullSuspected(input(76, 0, Vector(STAND.x + 200, STAND.y), true)))
	check("visible in the box (a human's spot) at :16 -> suspected", C.EnemyPullSuspected(input(76, 0, THEIR_SMALL, true)))
	check("visible at its stand at :25, outside the window -> not suspected", not C.EnemyPullSuspected(input(85, 0, STAND, true)))
	check("visible 500 from both stand and box at :15 -> not suspected", not C.EnemyPullSuspected(input(75, 0, Vector(STAND.x, STAND.y - 500), true)))
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
	-- The wave anomaly against real waves: `sizes` enemy creeps reach our front at :05 of successive cycles from 1:00.
	-- console.9057072982: one stacked cycle (8) made the next normal waves (4) read as thin, 73 thin-wave signals and no pull.
	local function anomalies(sizes, supportInLane)
		local H, support, _, _, esup = world(1, { telemetry = { Enable = true } })
		local lines = {}
		H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
		if not supportInLane then
			hide(esup, 4)
			esup.loc = Vector(-6000, -6000)
		end
		RANDOM_FRACTION = 0
		for k, n in ipairs(sizes) do
			local c0 = 60 + 30 * (k - 1)
			for i = #CREEPS[3], 1, -1 do table.remove(CREEPS[3], i) end
			for t = c0, c0 + 29.5, 0.5 do
				if t == c0 + 5 then for i = 1, n do MakeCreep({ team = 3, x = 100 + i * 20, y = 5000 }) end end
				tick(H, support, t)
			end
		end
		RANDOM_FRACTION = nil
		local n = 0
		for _, l in ipairs(lines) do
			if l:find(" ev=lane_signal ", 1, true) and l:find("kind=pull ", 1, true) then n = n + 1 end
		end
		return n
	end
	check("a stacked cycle does not make the next normal waves thin", anomalies({ 8, 4, 4, 4 }) == 0, anomalies({ 8, 4, 4, 4 }))
	check("positive control: 2 of a 4-creep wave with their support unseen -> thin", anomalies({ 4, 4, 2 }) == 1, anomalies({ 4, 4, 2 }))
	check("their support seen in our lane: a thin wave is no pull", anomalies({ 4, 4, 2 }, true) == 0, anomalies({ 4, 4, 2 }, true))
end

do
	-- Their support is read from who lanes at our front and what hero each is, not from J.GetPosition (console.9057240733:
	-- 19 of 20 first reads were pos 3, so no enemy was ever their support).
	local function roles(lines)
		local r = {}
		for _, l in ipairs(lines) do if l:find(" ev=lane_enemy_role ", 1, true) then table.insert(r, l) end end
		return r
	end
	local function laned(opts)
		local H, support, core, ecore, esup = world(1, { telemetry = { Enable = true }, unlaned = true })
		local lines = {}
		H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
		if opts.swap then ecore.name, esup.name = esup.name, ecore.name end
		if opts.solo then hide(ecore, 4) ecore.loc = Vector(-6000, -6000) end
		-- Seen at our front from 0:45; their support then pulls at 1:15, in sight at the camp.
		for t = 45, 45 + (opts.secs or 15), 0.5 do tick(H, support, t) end
		local pullAt = opts.supportAt or THEIR_SMALL
		esup.loc = pullAt
		if opts.swap then ecore.loc = pullAt end
		tick(H, support, 75)
		return H, support, lines, signalsOf(H, support, "pull")
	end
	local _, _, lines, pulls = laned({})
	check("their support at its camp, after 15 s laning: pull names it", #pulls == 1 and pulls[1].enemyPid == 15, pulls[1] and pulls[1].enemyPid)
	local r = roles(lines)
	check("lane_enemy_role reports CM as their support", #r == 1 and r[1]:find("role=support enemy=15 hero=npc_dota_hero_crystal_maiden", 1, true) ~= nil, r[1])
	_, _, _, pulls = laned({ swap = true })
	check("the hero decides, not the player id: with the names swapped, pid 11 is CM and their support", #pulls == 1 and pulls[1].enemyPid == 11, pulls[1] and pulls[1].enemyPid)
	_, _, _, pulls = laned({ secs = 8 })
	check("laned only 8 s: no support known yet, no sighting", #pulls == 0)
	_, _, _, pulls = laned({ solo = true })
	check("a solo laner is nobody's support", #pulls == 0)
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
	check("skill 0.9 notices 18 of 20 (0.92)", hi == 18, hi)
	check("skill 0.2 notices 7 of 20 (0.36)", lo == 7, lo)
end

do
	-- The enemy's pull seconds come from their wave (pull_timing) when their camp is wave-timed, as ours do: with a Dire
	-- creep path along the stub top lane their small camp pulls at :18.3, so a support unseen by it at :21 reads as
	-- pulling; on the :15 seed it does not (6 s off, CounterPullWindow 3).
	local WAVE = { Enable = true, PullTiming = { LanePaths = { dire_top = { { 9400, 5000 }, { -7000, 5000 } } }, WaveAhead = { safe = 0, off = 0 } } }
	local function at21(cfg)
		local H, support, _, _, esup = world(1, { cfg = cfg })
		tick(H, support, 80)
		hide(esup, 4)
		LAST_SEEN[15] = { location = Vector(THEIR_SMALL.x, THEIR_SMALL.y - 500), time_since_seen = 5 }
		tick(H, support, 81)
		LAST_SEEN[15] = nil
		return #signalsOf(H, support, "pull")
	end
	check("seed seconds: unseen support at :21 not suspected", at21(nil) == 0)
	check("wave-timed seconds: unseen support at :21 suspected", at21(WAVE) == 1)
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
	local H, support = stackWorld(true)
	check("stronger: camp not marked", #H.Lane.Counter.MarkedStacked(2) == 0)

	local core, esup
	H, support, core, _, esup = stackWorld(false)
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
	local H, _, core, _, esup = world(0.5, { telemetry = { Enable = true } })
	OBSERVER = 3
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	esup.loc = THEIR_SMALL
	RANDOM_FRACTION = 0.999
	tick(H, core, 75)
	RANDOM_FRACTION = nil
	local sig = {}
	for _, l in ipairs(lines) do if l:find(" ev=lane_signal ", 1, true) then table.insert(sig, l) end end
	check("lane_signal: a missed notice roll logs noticed=0", #sig == 1 and sig[1]:find("noticed=0", 1, true) ~= nil, sig[1])
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
		-- Their mid has laned against ours since 0:46, so it is known as their mid.
		for t = 46, 61, 0.5 do tick(H, mid, t) end
		if not enemyVisible then
			hide(emid, 2)
			LAST_SEEN[7] = { location = Vector(-2500, 0), time_since_seen = 5 }
		end
		tick(H, mid, 91)
		tick(H, mid, 92)
		return H, mid, said
	end
	local H, mid, said = ssWorld(false)
	check("ss mid said once", #said == 1 and said[1] == "say_lane_ss_mid", #said)

	H, mid, said = ssWorld(true)
	check("enemy mid visible: no ss mid", #said == 0)
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
	check("rune mode takes the lane's rune contest desire", read("bots/mode_rune_generic.lua"):find("math.max(nOwn, J.Humaniser.Lane.RuneContestDesire(bot),", 1, true) ~= nil)
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

finish()
