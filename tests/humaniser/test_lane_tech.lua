dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local BOT_Y = LANE_Y[Lane.Bot]
local DIRE_T1 = Vector(2800, BOT_Y)

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = Vector(o.x or 0, o.y or BOT_Y), hp = o.hp })
	u.lane, u.pos = o.lane or Lane.Bot, o.pos
	return u
end

local function world(skill, laneCfg, t)
	local H = LaneFresh(laneCfg or { Enable = true }, { skill = skill })
	T = t or 95
	CURRENT_TEAM = 2
	return H
end

local function attacks(pid) return ActionsOf(pid, "AttackUnit") end
local function moves(pid) return ActionsOf(pid, "MoveToLocation") end
local function lastMove(pid) local m = moves(pid) return m[#m] and m[#m].args[1] end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function setFronts(ours, theirs) LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = ours, theirs end
local function hitsOnEnemyCreeps(pid)
	local n = 0
	for _, a in ipairs(attacks(pid)) do if a.args[1].team == 3 and not a.args[1]:IsHero() then n = n + 1 end end
	return n
end

do
	local function owns(mode, extra)
		local cfg = { Enable = true, OwnLaningThink = mode }
		for k, v in pairs(extra or {}) do cfg[k] = v end
		local H = world(0.8, cfg)
		unit({ pid = 0, bot = false, lane = Lane.Top })
		local ally = unit({ pid = 1, pos = 1 })
		local enemy = unit({ pid = 6, team = 3, pos = 1 })
		return H, ally, enemy
	end
	local H, ally, enemy = owns("all")
	check("'all' owns an enemy-team bot with no humans", H.Lane.OwnsLaning(enemy) == true)
	check("04 ownership unchanged under 'all'", H.AllyLastHit.OwnsLaning(enemy) == false)
	H, ally, enemy = owns("allies")
	check("'allies' skips the enemy-team bot", H.Lane.OwnsLaning(enemy) == false)
	check("'allies' owns an ally of a human", H.Lane.OwnsLaning(ally) == true)
	H, ally = owns("off")
	check("'off' owns nobody", H.Lane.OwnsLaning(ally) == false)
	H, ally, enemy = owns("all", { Block = false, AggroPull = false, Freeze = false, Shove = false, Harass = false, Mid = false })
	check("all in-lane flags off owns nobody", H.Lane.OwnsLaning(enemy) == false)
end

-- 0:05 block: Radiant lead creep at x = -3000, the lane front on it, enemy wave far away.
local function blockWorld(team)
	local H = world(0.8, nil, 5)
	CURRENT_TEAM = team
	local sign = team == 2 and 1 or -1
	LANE_FRONT[team][Lane.Bot] = 4000 / 14000
	local bot = unit({ pid = 1, team = team, pos = 1, x = -2800 * sign })
	MakeCreep({ team = team, x = -3000 * sign, y = BOT_Y })
	MakeCreep({ team = team, x = -3100 * sign, y = BOT_Y })
	MakeCreep({ team = 5 - team, x = 3000 * sign, y = BOT_Y })
	return H, bot, sign
end

do
	local H, bot = blockWorld(2)
	local acted = H.Lane.PreThink(bot, {}, {}, {})
	local m = lastMove(1)
	check("block issues a move", acted == true and #moves(1) == 1)
	check("Radiant block stands ahead of the lead creep", m ~= nil and m.x > -3000 and math.abs(m.y - BOT_Y) <= 50, m and m.x)
	check("block commits", H.Lane.LanePlanner.Committed(bot) == "block")

	H, bot = blockWorld(3)
	H.Lane.PreThink(bot, {}, {}, {})
	m = lastMove(1)
	check("Dire block stands ahead of the lead creep", m ~= nil and m.x < 3000 and math.abs(m.y - BOT_Y) <= 50, m and m.x)
end

do
	local H, bot = blockWorld(2)
	check("precondition: blocking", H.Lane.PreThink(bot, {}, {}, {}) == true)
	T = 5.6
	local contact = MakeCreep({ team = 3, x = -2500, y = BOT_Y })
	local before = #moves(1)
	check("block ends on contact", H.Lane.PreThink(bot, {}, { contact }, {}) == false)
	check("no move after contact", #moves(1) == before)
end

-- Solo Radiant safe-lane bot at 1:35, wave at the default front (eq 0): the planner wants an aggro pull.
-- `front` moves our lane front (and the enemy laner's exposure) toward the Dire T1.
local function aggroWorld(skill, opts)
	opts = opts or {}
	local H = world(skill)
	if opts.front then setFronts(opts.front, 0.5) end
	local bot = unit({ pid = opts.pid or 1, pos = opts.pos or 1, x = opts.x or -200, hp = opts.hp })
	local creep = MakeCreep({ team = 2, x = (opts.x or -200) + 100, y = BOT_Y })
	local hero = unit({ pid = 6, team = 3, pos = 3, x = opts.heroX or 300 })
	return H, bot, creep, hero
end

do
	local H, bot, creep, hero = aggroWorld(0.8)
	local acted = H.Lane.PreThink(bot, { creep }, {}, { hero })
	local a = attacks(1)[1]
	check("aggro draw attacks the enemy hero once", acted and a ~= nil and a.args[1] == hero and a.args[2] == true)
	check("aggro draw commits", H.Lane.LanePlanner.Committed(bot) == "aggro_pull")
	local walkedBack = true
	for _, t in ipairs({ 95.5, 96.0, 96.4 }) do
		T = t
		local ok = H.Lane.PreThink(bot, { creep }, {}, { hero })
		local m = lastMove(1)
		if not ok or m == nil or m.x >= bot.loc.x then walkedBack = false end
	end
	check("walks toward our base while the creeps follow", walkedBack and #moves(1) == 3)
	check("walk-back stays within the max distance", dist(lastMove(1), bot.loc) <= 400 + 1e-6)
	T = 96.6
	H.Lane.PreThink(bot, { creep }, {}, { hero })
	local drop = attacks(1)[2]
	check("drops aggro on an allied creep", drop ~= nil and drop.args[1] == creep and drop.args[2] == true and #attacks(1) == 2)
	T = 96.7
	check("done after the drop", H.Lane.PreThink(bot, { creep }, {}, { hero }) == false and #attacks(1) == 2)
end

do
	local H = world(1)
	local core = unit({ pid = 1, pos = 1, x = -100 })
	local support = unit({ pid = 5, pos = 5, x = -200 })
	local hero = unit({ pid = 6, team = 3, pos = 3, x = 300 })
	local enemyCreep = MakeCreep({ team = 3, x = 100, y = BOT_Y, target = core })
	T = 94
	H.Lane.LaneState.ForBot(support)
	enemyCreep.target = nil
	T = 95
	check("ally aggro a second ago: support waits", H.Lane.PreThink(support, {}, {}, { hero }) == false and #attacks(5) == 0)
	T = 97.5
	H.Lane.PreThink(support, {}, {}, { hero })
	check("after the aggro window the support draws", #attacks(5) == 1 and attacks(5)[1].args[1] == hero)
end

-- Draw order for these frames: profiles are created first (one draw each, outside the queue), Plan's per-cycle rolls are primed, then the draw jitter (two Gauss draws,
-- 0.5/0.5 gives a negative sample, so no delay), then MayDrawAggro's double-draw roll.
do
	local H = world(0.5)
	local core = unit({ pid = 1, pos = 1, x = -100 })
	local support = unit({ pid = 5, pos = 5, x = -200 })
	local hero = unit({ pid = 6, team = 3, pos = 3, x = 300 })
	local enemyCreep = MakeCreep({ team = 3, x = 100, y = BOT_Y, target = core })
	T = 94
	H.Lane.LaneState.ForBot(support)
	enemyCreep.target = nil
	T = 95
	H.Profile.Get(core)
	H.Profile.Get(support)
	SetRandomSequence({ 0.9, 0.0 })
	local c = H.Lane.LanePlanner.Plan(support, H.Lane.LaneState.ForBot(support))
	check("precondition: support chooses aggro pull", c.tech == "aggro_pull" and RandomUnread() == 0, c.reason)
	SetRandomSequence({ 0.5, 0.5, 0.99, 0.0, 0.0, 0.0, 0.0, 0.0 })
	for i = 0, 5 do
		T = 95 + i * 0.1
		H.Lane.PreThink(support, {}, {}, { hero })
	end
	check("double-draw is rolled once per ally draw, not per frame", #attacks(5) == 0)
end

do
	local function drawTimes(skill)
		local H, bot, creep, hero = aggroWorld(skill)
		H.Profile.Get(bot)
		SetRandomSequence({ 0.0 })
		H.Lane.LanePlanner.Plan(bot, H.Lane.LaneState.ForBot(bot))
		SetRandomSequence({ math.exp(-0.5), 1.0 })
		local drewAt
		for i = 0, 15 do
			T = 95 + i * 0.1
			H.Lane.PreThink(bot, { creep }, {}, { hero })
			if drewAt == nil and #attacks(1) > 0 then drewAt = T end
		end
		return drewAt
	end
	local slow, fast = drawTimes(0.5), drawTimes(1)
	check("aggro draw waits for its jitter", fast ~= nil and fast > 95)
	check("lower skill draws later", slow ~= nil and fast ~= nil and slow > fast + 0.4, tostring(slow) .. " vs " .. tostring(fast))
end

do
	local H, bot, creep = aggroWorld(0.5, { x = 2200 })
	local ally = unit({ pid = 2, pos = 2, x = 2210 })
	TOWERS_W[3][dota.Tower.Bot1].target = bot
	H.Lane.PreThink(bot, { creep }, {}, {})
	check("tower drop prefers an allied creep over a nearer hero", attacks(1)[1] ~= nil and attacks(1)[1].args[1] == creep)
	H, bot = aggroWorld(0.5, { x = 2200 })
	ally = unit({ pid = 2, pos = 2, x = 2210 })
	TOWERS_W[3][dota.Tower.Bot1].target = bot
	H.Lane.PreThink(bot, {}, {}, {})
	check("tower drop falls back to an allied hero", attacks(1)[1] ~= nil and attacks(1)[1].args[1] == ally)
end

do
	local H, bot, creep, hero = aggroWorld(0.8)
	local function frame()
		H.Lane.PreThink(bot, { creep }, {}, { hero })
		H.Lane.Think(bot, { creep }, {}, { hero })
		H.Lane.AdjustPosition(bot, Vector(0, BOT_Y))
		local n = 0
		for _, v in pairs(GETUNITLIST_CALLS) do n = n + v end
		return n
	end
	local first = frame()
	T = 95.1
	local second = frame()
	T = 95.2
	check("per-frame hooks add no unit scans inside the snapshot window", first > 0 and frame() == first and second == first)
end

do
	local H, bot, creep, hero = aggroWorld(0.8, { x = 2000, heroX = 2300, front = 0.6 })
	check("no aggro on a hero under the enemy tower", H.Lane.PreThink(bot, { creep }, {}, { hero }) == false and #attacks(1) == 0)
	hero.loc = Vector(1700, BOT_Y)
	H.Lane.PreThink(bot, { creep }, {}, { hero })
	check("same hero out of tower range is drawn", #attacks(1) == 1 and attacks(1)[1].args[1] == hero)
end

do
	local H, bot, creep = aggroWorld(0.5, { x = 2200 })
	TOWERS_W[3][dota.Tower.Bot1].target = bot
	SetRandomSequence({ 0.99 })
	local c = H.Lane.LanePlanner.Plan(bot, H.Lane.LaneState.ForBot(bot))
	check("precondition: planner choice none", c.tech == "none", c.reason)
	check("tower aggro: drops on an allied creep", H.Lane.PreThink(bot, { creep }, {}, {}) == true
		and #attacks(1) == 1 and attacks(1)[1].args[1] == creep and attacks(1)[1].args[2] == true)
	T = 95.1
	H.Lane.PreThink(bot, { creep }, {}, {})
	local m = lastMove(1)
	check("then moves out of tower range", m ~= nil and dist(m, DIRE_T1) >= 1000 - 1e-6 and #attacks(1) == 1, m and dist(m, DIRE_T1))
	bot.loc = Vector(1700, BOT_Y)
	TOWERS_W[3][dota.Tower.Bot1].target = nil
	T = 95.2
	check("out of range: hands back", H.Lane.PreThink(bot, { creep }, {}, {}) == false)
end

do
	local H = world(0.8)
	setFronts(0.6, 0.5)
	local core = unit({ pid = 1, pos = 1, x = 2200, hp = 50 })
	local support = unit({ pid = 5, pos = 5, x = 1950 })
	local hero = unit({ pid = 6, team = 3, pos = 3, x = 2500 })
	TOWERS_W[3][dota.Tower.Bot1].target = core
	H.Lane.PreThink(support, {}, {}, { hero })
	check("swap: draws tower aggro off the low-HP core", #attacks(5) == 1 and attacks(5)[1].args[1] == hero)
	check("swap commits the aggro pull", H.Lane.LanePlanner.Committed(support) == "aggro_pull")
end

-- Shove worlds: Radiant safe lane, no enemy laner, wave at the default front; c2 is under the Dire T1.
local function shoveWorld(skill, laneCfg)
	local H = world(skill, laneCfg)
	STRONGER = true
	local said = {}
	H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
	unit({ pid = 0, bot = false, lane = Lane.Top, y = 5000 })
	local bot = unit({ pid = 1, pos = 1, x = -200 })
	local creeps = {
		MakeCreep({ team = 3, x = 100, y = BOT_Y, hp = 300 }),
		MakeCreep({ team = 3, x = 2300, y = BOT_Y, hp = 100 }),
		MakeCreep({ team = 3, x = 200, y = BOT_Y, hp = 400 }),
	}
	return H, bot, creeps, said
end

do
	local H, bot, creeps, said = shoveWorld(0.8)
	H.Lane.Hooks.SetRotationProbe(function() return true end)
	check("shove before rotating attacks", H.Lane.Think(bot, {}, creeps, {}) == true)
	T = 95.1
	H.Lane.Think(bot, {}, creeps, {})
	check("telegraphs the rotation once", #said == 1 and said[1] == "say_lane_shove_rotate", table.concat(said, ","))

	H, bot, creeps, said = shoveWorld(0.8)
	check("plan shove attacks", H.Lane.Think(bot, {}, creeps, {}) == true)
	check("plan shove says nothing", #said == 0)
	check("shove hits the lowest-HP creep not under the tower", attacks(1)[1].args[1] == creeps[1] and attacks(1)[1].args[2] == true)
	check("shove commits", H.Lane.LanePlanner.Committed(bot) == "shove")
end

-- Wave frozen at our side (eq -0.7) with an enemy laner at the front.
local function frozenWorld(skill, support)
	local H = world(skill)
	STRONGER = true
	setFronts(0.36, 0.64)
	local bot
	if support then
		unit({ pid = 1, pos = 1, x = -2000 })
		bot = unit({ pid = 5, pos = 5, x = -2100 })
	else
		bot = unit({ pid = 1, pos = 1, x = -2000 })
	end
	local hero = unit({ pid = 6, team = 3, pos = 3, x = -1700 })
	local creeps = { MakeCreep({ team = 3, x = -1800, y = BOT_Y }), MakeCreep({ team = 3, x = -1850, y = BOT_Y }) }
	local allies = { MakeCreep({ team = 2, x = -2050, y = BOT_Y }) }
	return H, bot, creeps, allies, hero
end

do
	local H, bot, creeps, allies, hero = frozenWorld(0.6, true)
	local s = H.Lane.LaneState.ForBot(bot)
	check("precondition: plan HOLD", H.Lane.LanePlan.ForSupport(bot, s).plan == "HOLD")
	check("precondition: choice none", H.Lane.LanePlanner.Plan(bot, s).tech == "none")
	check("HOLD support does not swing at the wave", H.Lane.Think(bot, allies, creeps, { hero }) == false and hitsOnEnemyCreeps(5) == 0)
end

do
	local H, bot, creeps, allies, hero = frozenWorld(0.8, false)
	local s = H.Lane.LaneState.ForBot(bot)
	check("precondition: plan FREEZE", H.Lane.LanePlan.View(bot, s).plan == "FREEZE")
	check("precondition: choice freeze", H.Lane.LanePlanner.Plan(bot, s).tech == "freeze")
	H.Lane.PreThink(bot, allies, creeps, { hero })
	H.Lane.Think(bot, allies, creeps, { hero })
	check("freeze never hits the wave", hitsOnEnemyCreeps(1) == 0)
	local input = Vector(-1960, BOT_Y)
	local out = H.Lane.AdjustPosition(bot, input)
	local ourT1 = Vector(-2800, BOT_Y)
	check("freeze holds nearer our tower", dist(out, ourT1) < dist(input, ourT1), out.x)
end

do
	local H, bot = frozenWorld(0.8, false)
	H.Lane.LanePlanner.Commit(bot, "aggro_pull")
	local c = H.Lane.LanePlanner.Plan(bot, H.Lane.LaneState.ForBot(bot))
	check("precondition: drag-back lock hides freeze", c.tech == "none", c.reason)
	local input = Vector(-1960, BOT_Y)
	local out = H.Lane.AdjustPosition(bot, input)
	check("freeze posture held under the one-per-cycle lock", dist(out, Vector(-2800, BOT_Y)) < dist(input, Vector(-2800, BOT_Y)), out.x)
end

do
	local H, bot, creeps = shoveWorld(0.8, { Enable = false })
	local input = Vector(0, BOT_Y)
	check("disabled: PreThink inert", H.Lane.PreThink(bot, {}, creeps, {}) == false)
	check("disabled: Think inert", H.Lane.Think(bot, {}, creeps, {}) == false)
	check("disabled: AdjustPosition returns the same vector", rawequal(H.Lane.AdjustPosition(bot, input), input))
	check("disabled: no actions, no unit scans", #ACTIONS == 0 and next(GETUNITLIST_CALLS) == nil)

	H, bot, creeps = shoveWorld(0.8)
	check("enabled control: Think shoves", H.Lane.Think(bot, {}, creeps, {}) == true and #attacks(1) == 1)
end

finish()
