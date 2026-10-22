dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local BOT_Y = LANE_Y[Lane.Bot]

local function ability(name, o)
	o = o or {}
	return {
		GetName = function() return name end,
		GetLevel = function() return o.level or 1 end,
		IsUltimate = function() return o.ult == true end,
		IsHidden = function() return false end,
		IsNull = function() return false end,
		GetCooldown = function() return o.cd or 12 end,
	}
end

local function lion(u)
	u.abilities = { [0] = ability("lion_impale", { cd = 12 }), [5] = ability("lion_finger_of_death", { ult = true, cd = 100 }) }
	return u
end

-- T2s at absolute 0.15 / 0.85 (x = -4900 / 4900); lane_world places only T1s.
local function addT2s()
	local t1 = TOWERS_W[2][dota.Tower.Bot1]
	for team, x in pairs({ [2] = -4900, [3] = 4900 }) do
		local t = setmetatable({ pid = -1, team = team, bot = true, alive = true, hp = 1300, modifiers = {}, loc = Vector(x, BOT_Y) },
			getmetatable(t1))
		t.GetUnitName = function() return "tower_t2" end
		TOWERS_W[team][dota.Tower.Bot2] = t
	end
end

-- One bottom-lane laner per side. Both creep fronts meet at the lane midpoint (x = 0), with one enemy creep there unless
-- noWave; the Radiant T1 is at x = -2800 and the Dire T1 at x = 2800. `sign` mirrors x so the same layout holds for
-- either team: our side is negative x.
local function world(o)
	o = o or {}
	local team = o.team or 2
	local other = team == 2 and 3 or 2
	local sign = team == 2 and 1 or -1
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = o.laneFight, telemetry = o.telemetry })
	T = 100
	CURRENT_TEAM = team
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.5, 0.5
	addT2s()
	local bot = MakeUnit({ pid = 1, team = team, loc = Vector(sign * -800, BOT_Y), level = o.botLevel or 1 })
	bot.pos, bot.lane = 5, Lane.Bot
	OBSERVER = bot
	local enemy = lion(MakeUnit({ pid = 6, team = other, loc = Vector(sign * (o.enemyX or 300), BOT_Y), level = o.enemyLevel or 1 }))
	local creep = not o.noWave and MakeCreep({ team = other, x = sign * 100, y = BOT_Y }) or nil
	local W = {
		H = H, bot = bot, enemy = enemy, sign = sign, other = other, creep = creep,
		FR = H.LaneFight.FightRead,
		M = H.LaneFight.CooldownMemory,
	}
	function W.read() return W.FR.ReadFor(bot, T) end
	function W.at(x) enemy.loc = Vector(sign * x, BOT_Y) end
	return W
end

local function rememberStun(W, roll)
	SetRandomSequence({ roll or 0.1, 0.5 })
	W.M.Record(1, 6, "lion_impale", "key", 12, 1, T)
	SetRandomSequence({})
end

local function countRandom()
	local n = 0
	local real = RandomFloat
	RandomFloat = function(a, b) n = n + 1 return real(a, b) end
	return function() RandomFloat = real return n end
end

do
	local W = world()
	rememberStun(W)
	T = T + 1
	local r = W.read()
	check("spell window after the remembered stun", r.window == "spell" and r.target == W.enemy, tostring(r.window))
	T = T + 12
	r = W.read()
	check("the spell window ends once the stun is remembered as back", r.window == nil, tostring(r.window))
end

do
	local W = world()
	rememberStun(W, 0.95)
	T = T + 1
	local r = W.read()
	check("no spell window when the stun was forgotten", r.window == nil and r.target == W.enemy, tostring(r.window))
end

do
	local W = world({ botLevel = 2 })
	local r = W.read()
	check("level 2 first gives a 'level' window", r.window == "level" and r.respect == nil, tostring(r.window))
	-- SpikeWindow is drawn uniformly in [LevelSpikeMin, LevelSpikeMax] = [10, 15]; the default fraction 0.5 gives 12.5 s.
	T = 112.4
	r = W.read()
	check("the level window lasts SpikeWindow seconds", r.window == "level", tostring(r.window))
	T = 112.7
	r = W.read()
	check("the level window is gone after SpikeWindow seconds", r.window == nil, tostring(r.window))
	check("LevelSpike reads ours while it lasts and nothing after", W.FR.LevelSpike(2, Lane.Bot, 105) == "ours"
		and W.FR.LevelSpike(2, Lane.Bot, 113) == nil)
end

do
	local W = world({ botLevel = 2 })
	W.read()
	T = T + 3
	W.enemy.level = 2
	local r = W.read()
	check("the level window ends when they reach the level too", r.window == nil, tostring(r.window))
end

do
	local W = world()
	W.read()
	T = T + 1
	W.enemy.level = 2
	local r = W.read()
	check("their spike first gives respect", r.respect == "their_spike" and r.window == nil, tostring(r.respect))
	check("LevelSpike reads theirs", W.FR.LevelSpike(2, Lane.Bot, T) == "theirs")
end

do
	local W = world()
	T = -10
	W.bot.level = 2
	W.read()
	T = 5
	local r = W.read()
	-- A spike timed from before the horn would have ended by 2.5 s; it starts at the first read after it instead.
	check("levels seen before the horn start no spike until after it", r.window == "level" and W.FR.LevelSpike(2, Lane.Bot, 17) == "ours",
		tostring(r.window))
end

for _, team in ipairs({ 2, 3 }) do
	local tag = team == 2 and " (radiant)" or " (dire)"
	local W = world({ team = team, enemyX = -450 })
	local r = W.read()
	check("400+ ahead of their creeps is out of position" .. tag, r.window == "position", tostring(r.window))
	W = world({ team = team, enemyX = -300 })
	r = W.read()
	check("less than 400 ahead of their creeps is not out of position" .. tag, r.window == nil and r.target ~= nil, tostring(r.window))
	W = world({ team = team, enemyX = 600 })
	W.bot.loc = Vector(W.sign * -200, BOT_Y)
	r = W.read()
	check("behind their creeps is not out of position" .. tag, r.window == nil and r.target ~= nil, tostring(r.window))
end

for _, team in ipairs({ 2, 3 }) do
	local tag = team == 2 and " (radiant)" or " (dire)"
	-- Fronts pushed to our tower: the enemy is behind their own creeps but within 700 of our T1.
	local W = world({ team = team })
	LANE_FRONT[team][Lane.Bot], LANE_FRONT[team == 2 and 3 or 2][Lane.Bot] = 0.25, 0.75
	W.bot.loc = Vector(W.sign * -3200, BOT_Y)
	W.at(-2300)
	local r = W.read()
	check("within our tower's range is out of position" .. tag, r.window == "position", tostring(r.window))
end

do
	local W = world({ noWave = true, enemyX = -450 })
	T = 10
	local r = W.read()
	check("ahead of their front is not out of position with no enemy wave in lane (0:10)", r.window == nil and r.target ~= nil,
		tostring(r.window))
end

do
	local W = world({ enemyX = -450 })
	check("with their wave in lane the same spot is out of position", W.read().window == "position")
	W.creep.hp = 0
	T = T + 0.6
	local r = W.read()
	check("right after their wave died it is not", r.window == nil and r.target ~= nil, tostring(r.window))
end

do
	-- Our wave and theirs 2100 apart along the lane: their creeps have not met ours.
	local W = world({ noWave = true })
	LANE_FRONT[2][Lane.Bot] = 0.35
	MakeCreep({ team = 3, x = -2000, y = BOT_Y })
	W.bot.loc = Vector(-1400, BOT_Y)
	W.at(-500)
	local r = W.read()
	check("ahead of their front is not out of position before the waves meet", r.window == nil and r.target ~= nil, tostring(r.window))
end

do
	-- Waves pushed to their T1 (x = 2800): 420 ahead of their front but 700 from their own tower.
	local W = world({ noWave = true })
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.68, 0.32
	MakeCreep({ team = 3, x = 2600, y = BOT_Y })
	W.bot.loc = Vector(1200, BOT_Y)
	W.at(2100)
	local r = W.read()
	check("a target within 750 of its own tower is not out of position", r.window == nil and r.target ~= nil, tostring(r.window))
	TOWERS_W[3][dota.Tower.Bot1].alive = false
	T = T + 0.6
	r = W.read()
	check("the same spot with their tower down is out of position", r.window == "position", tostring(r.window))
end

do
	local W = world()
	W.enemy.loc = Vector(-300, BOT_Y + 500)
	local r = W.read()
	check("300 ahead and 500 to the side is not out of position", r.window == nil and r.target ~= nil, tostring(r.window))
end

do
	-- Our wave pushed to their T1; the enemy dives at our T1, 5500 from our creep front.
	local W = world({ noWave = true })
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.7, 0.3
	W.bot.loc = Vector(-2400, BOT_Y)
	W.at(-2700)
	local r = W.read()
	check("an enemy diving at our T1 is a target", r.target == W.enemy and r.window == "position", tostring(r.target) .. tostring(r.respect))
	lion(MakeUnit({ pid = 7, team = 3, loc = Vector(2600, BOT_Y) }))
	T = T + 0.6
	r = W.read()
	check("the diver and their laner at the far end both count", r.respect == "outnumbered", tostring(r.respect))
	local mid = MakeUnit({ pid = 8, team = 3, loc = Vector(-2400, 0) })
	W.H.Lane.LaneState.ResetCache()
	mid.level = 1
	T = T + 0.6
	r = W.read()
	check("an enemy in another lane is not counted", r.respect == "outnumbered" and r.target == W.enemy)
end

do
	-- Partner (assigned bottom) is away at a camp: a 1v2 in lane.
	local W = world()
	local partner = MakeUnit({ pid = 2, loc = Vector(-3000, -1000) })
	partner.pos, partner.lane = 4, Lane.Bot
	lion(MakeUnit({ pid = 7, team = 3, loc = Vector(600, BOT_Y) }))
	local r = W.read()
	check("assigned partner away on a camp: 1v2 reads outnumbered", r.respect == "outnumbered", tostring(r.respect))
	partner.loc = Vector(-900, BOT_Y)
	W.H.Lane.LaneState.ResetCache()
	T = T + 0.6
	r = W.read()
	check("with the partner back in lane 2v2 is no respect", r.respect == nil, tostring(r.respect))
end

do
	local W = world()
	local missing = MakeUnit({ pid = 7, team = 3, loc = Vector(600, BOT_Y), level = 2 })
	missing.hiddenFrom = { [W.bot] = true }
	LAST_SEEN[7] = { location = Vector(600, BOT_Y), time_since_seen = 15 }
	MakeUnit({ pid = 8, team = 3, loc = Vector(-800, 0), level = 2 })
	local r = W.read()
	check("a level 2 enemy in mid or missing for 15 s sets no spike", r.respect == nil and W.FR.LevelSpike(2, Lane.Bot, T) == nil,
		tostring(r.respect))
	LAST_SEEN[7] = { location = Vector(600, BOT_Y), time_since_seen = 5 }
	W.H.Lane.LaneState.ResetCache()
	T = T + 0.6
	r = W.read()
	check("the same enemy seen 5 s ago in lane sets their spike", r.respect == "their_spike", tostring(r.respect))
end

do
	local W = world()
	local dying = MakeCreep({ team = 2, x = -200, y = BOT_Y, hp = 40 })
	W.enemy.target = dying
	local r = W.read()
	check("an enemy going for a dying allied creep gives a lasthit window", r.window == "lasthit", tostring(r.window))
end

do
	local W = world()
	W.at(1500)
	local r = W.read()
	check("an enemy beyond 1200 of the bot is no target", r.target == nil and r.window == nil)
end

do
	local W = world({ enemyLevel = 6 })
	W.bot.level = 6
	local r = W.read()
	check("their learned ult not seen used gives respect at 6", r.respect == "their_ult", tostring(r.respect))
	W = world({ enemyLevel = 6 })
	W.bot.level = 6
	SetRandomSequence({ 0.1, 0.5 })
	W.M.Record(1, 6, "lion_finger_of_death", "ult", 100, 1, T)
	SetRandomSequence({})
	r = W.read()
	check("their ult remembered on cooldown is no respect", r.respect == nil, tostring(r.respect))
end

do
	local W = world()
	rememberStun(W)
	local second = lion(MakeUnit({ pid = 7, team = 3, loc = Vector(1500, BOT_Y) }))
	T = T + 1
	local r = W.read()
	check("respect beats a window", r.respect == "outnumbered" and r.window == nil, tostring(r.respect) .. "/" .. tostring(r.window))
	second.hiddenFrom = { [W.bot] = true }
	LAST_SEEN[7] = { location = Vector(1500, BOT_Y), time_since_seen = 5 }
	T = T + 1
	r = W.read()
	check("an enemy missing for 5 s near the lane still counts", r.respect == "outnumbered", tostring(r.respect))
	LAST_SEEN[7] = { location = Vector(1500, BOT_Y), time_since_seen = 15 }
	T = T + 1
	r = W.read()
	check("an enemy missing for 15 s does not count", r.respect == nil and r.window == "spell", tostring(r.respect))
	LAST_SEEN[7] = { location = Vector(1500, 2000), time_since_seen = 5 }
	T = T + 1
	r = W.read()
	check("a recently seen enemy far from the lane does not count", r.respect == nil, tostring(r.respect))
end

do
	local W = world({ telemetry = { Enable = true } })
	local lines = {}
	W.H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	rememberStun(W)
	W.H.Profile.Get(W.bot)
	local stop = countRandom()
	for _ = 1, 10 do
		T = T + 0.3
		W.read()
	end
	check("notice roll is drawn once per window instance", stop() == 1)
	local logged = 0
	for _, l in ipairs(lines) do
		if l:find("ev=lanefight_window", 1, true) and l:find("pid=1 window=spell target=6", 1, true) then logged = logged + 1 end
	end
	check("the window is logged once per instance", logged == 1, logged)
	-- 1.5 s with the enemy out of reach ends the instance; coming back is a new one with its own roll.
	W.at(1500)
	T = T + 0.3
	W.read()
	T = T + 1.5
	W.read()
	W.at(300)
	stop = countRandom()
	T = T + 0.3
	local r = W.read()
	check("a window back after a 1 s lapse is a new instance", stop() == 1 and r.window == "spell")
end

do
	local W = world({ skill = 0 })
	rememberStun(W)
	SetRandomSequence({ 0.5 })
	T = T + 1
	-- Notice at skill 0 is 0.3: a 0.5 roll misses.
	check("a missed notice roll reads noticed = false", W.read().noticed == false)
	W = world({ skill = 1 })
	rememberStun(W)
	SetRandomSequence({ 0.5 })
	T = T + 1
	check("a notice roll under Curve('Notice') reads noticed = true", W.read().noticed == true)
end

do
	local W = world()
	rememberStun(W)
	T = T + 1
	local first = W.read()
	W.enemy.loc = Vector(1500, BOT_Y)
	local again = W.read()
	check("reads are cached per pid for WindowReadEvery", again == first)
end

do
	local W = world()
	W.enemy.removed = true
	local ok, r = pcall(W.read)
	check("a removed enemy handle is skipped", ok and r.target == nil, r)
	W = world()
	W.enemy.loc = nil
	ok, r = pcall(W.read)
	check("an enemy listed without a location is skipped", ok and r.target == nil, r)
end

do
	-- In game a cached target went invalid inside WindowReadEvery and the caller's GetPlayerID threw.
	local W = world()
	rememberStun(W)
	T = T + 1
	local first = W.read()
	W.enemy.removed = true
	local again = W.read()
	check("a cached read whose target handle went null is read again", first.target == W.enemy and again.target == nil, again)
end

do
	local W = world({ laneFight = { Enable = false } })
	rememberStun(W)
	T = T + 1
	local r = W.read()
	check("LaneFight off reads nothing", r.window == nil and r.respect == nil and r.target == nil)
end

do
	local W = world()
	local FR = W.FR
	local base = { target = true, keyThreatsDown = 1, lastHit = true, spike = "ours", aheadOfFront = 500, wavesMet = true,
		nearOurTower = false, nearTheirTower = false,
		theirUltReady = false, enemiesNear = 1, ourLaners = 1 }
	local function with(over) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(over) do t[k] = v end return t end
	check("spell is checked first", FR.Decide(base).window == "spell")
	check("then lasthit", FR.Decide(with({ keyThreatsDown = 0.5 })).window == "lasthit")
	check("then level", FR.Decide(with({ keyThreatsDown = 0, lastHit = false })).window == "level")
	check("then position", FR.Decide(with({ keyThreatsDown = 0, lastHit = false, spike = false })).window == "position")
	check("their spike is respect, not a window", FR.Decide(with({ spike = "theirs" })).respect == "their_spike"
		and FR.Decide(with({ spike = "theirs" })).window == nil)
end

finish()
