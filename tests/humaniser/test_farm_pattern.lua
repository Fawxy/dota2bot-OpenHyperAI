dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

-- Radiant bot lane: the stub front sits at (0, -5000). Overriding Dire's bot path with a straight line along the lane
-- puts the enemy wave's walk to the front at `travel` seconds (path length / 325), so arrivals are travel + 30k.
local FRONT = Vector(0, -5000)
local SMALL = Vector(0, -6200) -- 1,200 from the front: 4 s each way at 300
local SMALL2 = Vector(900, -6600) -- 985 from SMALL, 1,836 from the front
local LARGE = Vector(1500, -6500) -- 2,121 from the front

local function spawner(type_, at)
	return { team = 2, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

local function world(o)
	local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { dire_bot = { { 325 * o.travel, -5000 }, { -7000, -5000 } } } } },
		{ skill = o.skill or 0.9, farm = o.farm })
	T = o.t
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = {}
	local camp = {}
	for i, c in ipairs(o.camps) do
		table.insert(SPAWNERS, spawner(c[1], c[2]))
		camp[i] = MakeNeutral({ x = c[2].x, y = c[2].y })
	end
	H.Lane.Camps.ResetCache()
	H.FarmPattern.ResetCache()
	local core = MakeUnit({ pid = 1, team = 2, loc = o.at or FRONT, level = o.level or 6, mode = BotMode.Laning })
	core.lane, core.pos = Lane.Bot, o.pos or 1
	local support = MakeUnit({ pid = 5, team = 2, loc = Vector(-3000, -5600), level = 4, mode = BotMode.Laning })
	support.lane, support.pos = Lane.Bot, 5
	MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) }).pos = 3
	H.Lane.Config.SkillOf(core)
	H.Lane.Config.SkillOf(support)
	return H, core, support, camp
end

local function lastAction(pid)
	local a = ACTIONS[#ACTIONS]
	if a == nil or a.pid ~= pid then return nil end
	return a
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Wave dead at 7:25 (arrivals :10 and :40): 20 s to the next wave plus 5 s late. The small camp fits (4 + 9.3 + 4 at
-- level 6), the large one does not (7.1 + 17.3 + 7.1), so the core walks to the small camp.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL }, { "large", LARGE } } })
	check("wave arrival: next enemy wave at the front", near(H.FarmPattern.NextWaveAt(2, Lane.Bot, FRONT, 445), 460))
	local d = H.FarmPattern.Desire(core)
	local trip = H.FarmPattern.Current(core)
	check("trip: starts between waves", d > 0.6 and trip ~= nil, d)
	check("trip: takes the camp that fits before the wave", trip and trip.campIdx == 1, trip and trip.campIdx)
	check("trip: leaves the camp in time to walk back", trip and near(trip.leaveBy, 465 - 4), trip and trip.leaveBy)
	H.FarmPattern.Think(core)
	local a = lastAction(1)
	check("trip: heads into the camp it can see", a and a.kind == "AttackUnit" and dist(a.args[1]:GetLocation(), SMALL) < 1, a and a.kind)
end

-- Camp types open by level. At 7:12 (33 s to the wave) a large camp 1,200 away fits even at level 3's clear time
-- (4 + 20.8 + 4), so only CampMinLevel keeps a level-3 core out of it; at level 6 it is taken.
do
	local H, core = world({ travel = 10, t = 432, level = 3, camps = { { "large", SMALL } } })
	check("level: large camp shut at level 3", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
	local H2, core2 = world({ travel = 10, t = 432, level = 6, camps = { { "large", SMALL } } })
	check("level: large camp open at level 6", H2.FarmPattern.Desire(core2) > 0)
end
do
	local H, core = world({ travel = 10, t = 440, level = 3, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	check("level: small camp open at level 3", H.FarmPattern.Current(core) ~= nil)
end

-- No trip while the wave in front is still alive, nor when the next wave is too close for any camp.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	MakeCreep({ team = 3, x = 300, y = -5000 })
	check("gate: enemy wave still alive", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end
do
	local H, core = world({ travel = 10, t = 445, at = Vector(-1200, -5000), camps = { { "small", SMALL } } })
	MakeCreep({ team = 3, x = 0, y = -5000 })
	check("gate: wave alive at the front, bot standing back from it", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end
do
	local H, core = world({ travel = 10, t = 455, camps = { { "small", SMALL } } })
	check("gate: next wave too close for a camp", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end
do
	local H, _, support = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	support.loc, support.level = FRONT, 10
	check("gate: supports do not take trips", H.FarmPattern.Desire(support) == 0)
end
do
	local H, core = world({ travel = 10, t = 280, camps = { { "small", SMALL } } })
	check("gate: not before the position's start time", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end

-- Past leaveBy the core leaves an unfinished camp and walks back; at the front the trip ends.
do
	local H, core, _, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode = BotMode.Farm
	core.loc = SMALL
	local n = camp[1]
	T = 450
	H.FarmPattern.Think(core)
	local a = lastAction(1)
	check("farm: attacks the camp", a and a.kind == "AttackUnit" and a.args[1] == n, a and a.kind)
	T = 461.5
	H.FarmPattern.Desire(core)
	H.FarmPattern.Think(core)
	a = lastAction(1)
	check("leave: walks back to the front at leaveBy", H.FarmPattern.Current(core).phase == "return" and a.kind == "MoveToLocation"
		and dist(a.args[1], FRONT) < 1)
	core.loc = Vector(0, -5300)
	T = 463
	check("leave: trip ends back at the front", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end

-- On the walk back the retreat hold is off; once retreat out-bids the trip (the camp left with aggro chases the core),
-- the trip ends instead of trading the bot with retreat every scoring round.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode, core.loc = BotMode.Farm, SMALL
	T = 461.5
	H.FarmPattern.Think(core)
	H.FarmPattern.Desire(core)
	check("retreat: hold released on the walk back", near(H.Intent.Resolve(core, BotMode.Retreat, 0.9), 0.9))
	H.FarmPattern.Think(core)
	check("retreat: trip ends once retreat out-bids it", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end

-- At level 12 a cleared small camp leaves time for the second one (3.3 + 4.7 + 6.1 before 465), so the trip chains.
do
	local H, core, _, camp = world({ travel = 10, t = 445, level = 12, camps = { { "small", SMALL }, { "small", SMALL2 } } })
	H.FarmPattern.Desire(core)
	check("chain: first pick is the nearer camp", H.FarmPattern.Current(core).campIdx == 1)
	core.mode = BotMode.Farm
	core.loc = SMALL
	camp[1].hp = 0
	local second = camp[2]
	T = 450
	H.FarmPattern.Think(core)
	local trip = H.FarmPattern.Current(core)
	check("chain: moves on to the second camp", trip.campIdx == 2 and trip.camps == 2, trip.campIdx)
	local a = lastAction(1)
	check("chain: attacks the second camp", a and a.kind == "AttackUnit" and a.args[1] == second, a and a.kind)
end

-- A camp an ally's stack job has claimed is left to it.
do
	local H, core = world({ travel = 10, t = 445, level = 12, camps = { { "small", SMALL }, { "small", SMALL2 } } })
	H.Lane.Stacking.Reserve(1, 5, 480)
	H.FarmPattern.Desire(core)
	local trip = H.FarmPattern.Current(core)
	check("reserved: skips the camp an ally is stacking", trip and trip.campIdx == 2, trip and trip.campIdx)
end

-- 7:46, waves at :00/:30, level 5: the small camp takes 4 + 11.2 + 4 s and misses 8:00 + 5 s, but a stack (hit at
-- :54.5, walk-off to 8:01, 4 s back) fits StackLateExtra, so the core runs camp_jobs' stack job for its own camp.
do
	local H, core = world({ travel = 30, t = 466, level = 5, camps = { { "small", SMALL } } })
	local stand = H.Lane.Stacking.StandPoint(H.Lane.Camps.SpawnerByIdx(1), H.Lane.Camps.ByIdx(1, 2))
	local wait = 474.5 - (466 + dist(FRONT, stand) / 300)
	check("stack precondition: arrives within the stack wait", wait >= 0.5 and wait <= 10, wait)
	H.FarmPattern.Desire(core)
	local trip = H.FarmPattern.Current(core)
	local job = H.Lane.CampJobs.Current(core)
	check("stack: trip waits on a stack", trip and trip.phase == "stack", trip and trip.phase)
	check("stack: camp_jobs runs it for the core", job and job.kind == "stack" and job.core == true and job.campIdx == 1)
	core.mode = BotMode.Farm
	check("stack: the core's job passes its own safety checks", H.Lane.CampJobDesire(core) > 0)
	local before = #ACTIONS
	check("stack: the trip runs the job's frame, never upstream farm", H.FarmPattern.Think(core) == true and #ACTIONS > before)
end

-- The core's stack walk-off drags the camp after it; retreat's creep-damage branch is held below the job, as for a
-- pull's lead, until a real threat shows up.
do
	local H, core = world({ travel = 30, t = 466, level = 5, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode = BotMode.Farm
	local job = H.Lane.CampJobs.Current(core)
	-- farm's own GetDesire returns the job's desire first, so the trip's farm:hold lapses; only the job's hold is left.
	T = T + 0.6
	job.phase, job.exitUntil = "exit", T + 10
	core.hp = 70
	local farm = H.Intent.Resolve(core, BotMode.Farm, H.Lane.CampJobRawDesire(core, H.Lane.CampJobDesire(core)))
	local retreat = H.Intent.Resolve(core, BotMode.Retreat, 0.81)
	check("stack walk-off: retreat held below the job", retreat < farm, retreat .. " " .. farm)
	core.heroHitAt = T
	T = T + 0.05
	H.Lane.CampJobRawDesire(core, H.Lane.CampJobDesire(core))
	check("stack walk-off: a hero's hit releases it", near(H.Intent.Resolve(core, BotMode.Retreat, 0.81), 0.81))
end

-- Another mode taking over ends the trip once farm has not thought for PreemptAfter.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode = BotMode.Farm
	H.FarmPattern.Think(core)
	core.mode = BotMode.Rune
	H.FarmPattern.OnEnd(core)
	T = 446.5
	check("preempt: a short blip under another mode keeps the trip", H.FarmPattern.Desire(core) > 0 and H.FarmPattern.Current(core) ~= nil)
	T = 447.5
	check("preempt: trip ends once another mode holds past PreemptAfter", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
end

-- From the trip's start (the claim reaches retreat a scoring round later, so it cannot wait for the first neutral hit)
-- retreat and errands sit below the trip; a hero hitting or targeting the core lifts the retreat hold.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	check("hold: retreat capped from the walk in", near(H.Intent.Resolve(core, BotMode.Retreat, 0.8), 0.57))
	check("focus: a ward errand waits for the trip", near(H.Intent.Resolve(core, BotMode.Ward, 0.8), 0.57))
	check("focus: a rune is still the core's call", near(H.Intent.Resolve(core, BotMode.Rune, 0.8), 0.8))
	core.heroHitAt = T
	H.FarmPattern.Desire(core)
	check("hold: released once a hero hits", near(H.Intent.Resolve(core, BotMode.Retreat, 0.8), 0.8))
end
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	UNITS[3][1].loc, UNITS[3][1].target = Vector(-2000, -5000), core
	T = 445.3
	H.FarmPattern.Desire(core)
	check("hold: released while a hero targets the core", near(H.Intent.Resolve(core, BotMode.Retreat, 0.8), 0.8))
end

-- No trip while retreat already bids the trip's desire: farm would only win in retreat's dip.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.Intent.Resolve(core, BotMode.Retreat, 0.7)
	check("gate: retreat already wants out", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.StartGate(core, T) == "retreat")
end

-- Units sharing the hero's player ID (Meepo clones, tempest double) never take trips.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	core.modifiers["modifier_arc_warden_tempest_double"] = 1
	check("gate: tempest double", H.FarmPattern.Desire(core) == 0)
end

-- An enemy hero showing up ends the trip only after the core's reaction time.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode = BotMode.Farm
	H.FarmPattern.Think(core)
	UNITS[3][1].loc = Vector(-1000, -5000)
	T = 445.05
	H.FarmPattern.Desire(core)
	check("enemy: not on the first sighting", H.FarmPattern.Current(core) ~= nil)
	T = 445.06 + H.Profile.Get(core).reactBase
	H.FarmPattern.Think(core)
	H.FarmPattern.Desire(core)
	check("enemy: ends after the reaction time", H.FarmPattern.Current(core) == nil)
	-- The enemy steps back out of range: no new trip until the cooldown has passed.
	UNITS[3][1].loc = Vector(6000, 6000)
	core.mode = BotMode.Laning
	T = T + 2
	check("enemy: no restart right after", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
	-- Past the cooldown, at a point in the wave cycle where the camp fits again.
	T = 465
	check("enemy: restarts after the cooldown", H.FarmPattern.Desire(core) > 0 and H.FarmPattern.Current(core) ~= nil)
end

-- A trip does not start with an enemy hero just outside the radius that would end it.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	UNITS[3][1].loc = Vector(-1700, -5000)
	check("gate: enemy near the abort radius", H.FarmPattern.Desire(core) == 0 and H.FarmPattern.Current(core) == nil)
	UNITS[3][1].loc = Vector(-2500, -5000)
	T = T + 1
	check("gate: enemy well clear", H.FarmPattern.Desire(core) > 0)
end

-- The core keeps hitting its target as other neutrals' HP drops, so re-targeting does not cancel its attacks.
do
	local H, core, _, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	local other = MakeNeutral({ x = SMALL.x + 50, y = SMALL.y, hp = 400 })
	H.FarmPattern.Desire(core)
	core.mode, core.loc = BotMode.Farm, SMALL
	H.FarmPattern.Think(core)
	check("target: first pick is the lowest HP", lastAction(1).args[1] == camp[1])
	other.hp = 50
	T = 446
	H.FarmPattern.Think(core)
	check("target: kept while it lives", lastAction(1).args[1] == camp[1])
	camp[1].hp = 0
	T = 447
	H.FarmPattern.Think(core)
	check("target: next one once it dies", lastAction(1).args[1] == other)
end

-- Clear time is measured from the first frame in attack range, not from first seeing the camp on the walk in.
do
	local H, core = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode = BotMode.Farm
	H.FarmPattern.Think(core)
	check("pace clock: not started while walking in", H.FarmPattern.Current(core).farmFrom == nil)
	core.loc = SMALL
	T = 449
	H.FarmPattern.Think(core)
	check("pace clock: starts in attack range", H.FarmPattern.Current(core).farmFrom == 449)
end

-- A bot that clears slower than the prior learns it: after a 25 s small camp (prior 9.3 s at level 6) the same gap
-- between waves no longer fits that camp.
do
	local H, core, _, camp = world({ travel = 10, t = 445, camps = { { "small", SMALL } } })
	H.FarmPattern.Desire(core)
	core.mode, core.loc = BotMode.Farm, SMALL
	H.FarmPattern.Think(core)
	camp[1].hp = 0
	T = 445 + 25
	-- leaveBy has passed: the learning path under test is the clear, so move leaveBy out of the way.
	H.FarmPattern.Current(core).leaveBy = 1e9
	H.FarmPattern.Think(core)
	local pace = 1 + 0.3 * (25 / (7 * 8 / 6) - 1)
	check("pace: factor moves toward measured over prior", near(H.FarmPattern.PaceFactor(core), pace), H.FarmPattern.PaceFactor(core))
	-- Next minute, camp respawned, a 20 s gap: the prior (4 + 9.3 + 4) fits, the learned pace (4 + 14 + 4) does not.
	camp[1].hp = 300
	core.loc = FRONT
	T = 505
	check("pace: the learned pace rules the camp out", H.FarmPattern.PlanCamp(core, FRONT, FRONT, 505, 525) == nil)
end

-- Two cores in one module instance (shared per team) do not both head for the same camp.
do
	local H, core = world({ travel = 10, t = 445, level = 12, camps = { { "small", SMALL }, { "small", SMALL2 } } })
	local mid = MakeUnit({ pid = 2, team = 2, loc = FRONT, level = 12, mode = BotMode.Laning })
	mid.lane, mid.pos = Lane.Bot, 1
	H.Lane.Config.SkillOf(mid)
	H.FarmPattern.Desire(core)
	H.FarmPattern.Desire(mid)
	local a, b = H.FarmPattern.Current(core), H.FarmPattern.Current(mid)
	check("claims: second core takes another camp", a and b and a.campIdx ~= b.campIdx, b and b.campIdx)
end

finish()
