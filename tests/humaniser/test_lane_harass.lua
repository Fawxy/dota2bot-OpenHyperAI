dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local BOT_Y = LANE_Y[Lane.Bot]
local makeRef = dofile(HARNESS_DIR .. "/ref_harass_04.lua")

-- Same answers as LaneFresh's lane helpers, for 04's reference HarassThink.
local J = {
	IsValidHero = function(u) return u ~= nil and u.alive end,
	IsSuspiciousIllusion = function(u) return u.illusion == true end,
	IsValidBuilding = function(u) return u ~= nil and u.alive end,
	GetHP = function(u) return u:GetHealth() / u:GetMaxHealth() end,
	WeAreStronger = function() return STRONGER == true end,
}

local function world(skill, laneCfg)
	-- The default lane front (x = 0) puts the core 3,100 from it, which the transitions caution reads as an absent
	-- partner; these tests isolate the harass tool, so caution (covered by test_transitions_caution) stays off.
	local H = LaneFresh(laneCfg or { Enable = true }, { skill = skill, transitions = { Caution = false } })
	H.AllyLastHit.SetHelpers({ GetPosition = function(u) return u.pos end, IsInLaningPhase = function() return true end })
	T = 100
	CURRENT_TEAM = 2
	STRONGER = true
	return H
end

-- Radiant support (pid 1) with its human core (pid 0) beside it and an enemy laner (pid 6) 500 away.
local function lane(skill, o)
	o = o or {}
	local H = world(skill, o.cfg)
	local human = MakeUnit({ pid = 0, bot = false, loc = Vector(o.humanX or -3100, BOT_Y) })
	human.pos, human.lane = 1, Lane.Bot
	local bot = MakeUnit({ pid = 1, loc = Vector(o.botX or -3000, BOT_Y), hp = o.hp, level = o.level })
	bot.pos = 5
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(o.enemyX or -2500, BOT_Y), hp = o.enemyHp })
	enemy.dmg = 40
	H.Profile.Get(bot)
	return H, bot, enemy
end

-- An attack the engine reports as landed shortly after it is ordered, ending 04's re-issue window.
local function landing(u)
	u.Action_AttackUnit = function(self, target, once)
		table.insert(ACTIONS, { pid = self.pid, kind = "AttackUnit", args = { target, once } })
		self.lastAttack = T + 0.05
	end
end

local function attacksOn(pid, target)
	local n = 0
	for _, a in ipairs(ActionsOf(pid, "AttackUnit")) do if a.args[1] == target and a.args[2] == true then n = n + 1 end end
	return n
end

local function attempt(enemy, hp)
	local creep = MakeCreep({ team = 2, x = -2700, y = BOT_Y, hp = hp or 30 })
	enemy.target = creep
	return creep
end

local function think(H, bot, creeps, enemies, etiquette, enemyCreeps)
	return H.Lane.HarassThink(bot, creeps, enemyCreeps or {}, enemies, etiquette)
end

-- Runs frames from T until `untilT` and returns the time of the first attack on `target`, or nil.
local function firstAttack(H, bot, creeps, enemies, etiquette, target, untilT, step)
	local i0 = #ActionsOf(bot.pid, "AttackUnit")
	local t0 = T
	for i = 0, math.floor((untilT - t0) / (step or 0.1) + 0.5) do
		T = t0 + i * (step or 0.1)
		think(H, bot, creeps, enemies, etiquette)
		local list = ActionsOf(bot.pid, "AttackUnit")
		if #list > i0 and list[#list].args[1] == target then return T end
	end
	return nil
end

-- attempt detection
do
	local H, bot, enemy = lane(0.9)
	local Harass = H.Lane.Harass
	local creep = attempt(enemy, 30)
	check("(a) enemy targeting a creep it kills is an attempt", Harass.IsLastHitAttempt(enemy, { creep }) == creep)
	creep.hp = 60
	check("(a) a creep the hit cannot kill is no attempt", Harass.IsLastHitAttempt(enemy, { creep }) == nil)

	enemy.target = nil
	local low = MakeCreep({ team = 2, x = -2800, y = BOT_Y, hp = 35 })
	enemy.extrap = Vector(-2600, BOT_Y)
	check("(b) moving toward a killable creep is an attempt", Harass.IsLastHitAttempt(enemy, { low }) == low)
	enemy.extrap = Vector(-2400, BOT_Y)
	check("(b) moving away is no attempt", Harass.IsLastHitAttempt(enemy, { low }) == nil)
end

-- capitalise rate (scenario 8): the capitalise roll is the first draw of each new attempt.
do
	local function punishes(skill, cfg)
		local n = 0
		for k = 0, 19 do
			local H, bot, enemy = lane(skill, { cfg = cfg })
			local creep = attempt(enemy)
			SetRandomSequence({ 0.025 + 0.05 * k, 0.5, 0.5, 0.5 })
			for i = 0, 30 do
				T = 100 + i * 0.1
				if H.Lane.SupersedesHarass(bot) then think(H, bot, { creep }, { enemy }, false) end
			end
			n = n + attacksOn(1, enemy)
		end
		return n
	end
	check("skill 0.9 punishes 16 of 20 attempts", punishes(0.9) == 16, punishes(0.9))
	check("skill 0.2 punishes 7 of 20 attempts", punishes(0.2) == 7, punishes(0.2))
	check("Harass off: the shared tool never runs", punishes(0.9, { Enable = true, Harass = false }) == 0)
end

-- reaction delay respected
do
	local H, bot, enemy = lane(0.9)
	local creep = attempt(enemy)
	SetRandomSequence({ 0, 0.5, 0.5 })
	local expected = 100 + H.Profile.Get(bot).reactBase
	think(H, bot, { creep }, { enemy }, false)
	check("no attack on the attempt frame", attacksOn(1, enemy) == 0)
	T = 100
	local at = firstAttack(H, bot, { creep }, { enemy }, false, enemy, 102, 0.01)
	check("attack lands at attempt + react delay", at ~= nil and at >= expected - 1e-9 and at < expected + 0.011, at)
	check("exactly one punish", attacksOn(1, enemy) == 1)
end

-- aggro dance: one hit, then a step back toward our base
do
	local function dance(nCreeps)
		local H, bot, enemy = lane(0.9)
		bot.lane = Lane.Bot
		local creep = attempt(enemy)
		local foes = {}
		for i = 1, nCreeps do table.insert(foes, MakeCreep({ team = 3, x = -2700 + i * 10, y = BOT_Y })) end
		SetRandomSequence({ 0 })
		for i = 0, 10 do
			T = 100 + i * 0.1
			think(H, bot, { creep }, { enemy }, false, foes)
		end
		return attacksOn(1, enemy), ActionsOf(1, "MoveToLocation")
	end
	local hits, moves = dance(3)
	check("3 enemy creeps: one hit", hits == 1)
	check("3 enemy creeps: then a step back toward our base", #moves >= 1 and moves[1].args[1].x < -3000, moves[1] and moves[1].args[1].x)
	hits, moves = dance(2)
	check("2 enemy creeps: hit without stepping back", hits == 1 and #moves == 0)
end

-- tower rule: Dire T1 at x = 2800; the enemy stands 500 from it.
do
	local function punished(level, enemyHp)
		local H, bot, enemy = lane(0.9, { botX = 1800, enemyX = 2300, humanX = 1700, level = level, enemyHp = enemyHp })
		local creep = MakeCreep({ team = 2, x = 2100, y = BOT_Y, hp = 30 })
		enemy.target = creep
		SetRandomSequence({ 0 })
		for i = 0, 10 do
			T = 100 + i * 0.1
			think(H, bot, { creep }, { enemy }, false)
		end
		return attacksOn(1, enemy) == 1
	end
	check("level 5 near the tower, target 50%: no punish", not punished(5, 50))
	check("level 5 near the tower, target 25%: punish", punished(5, 25))
	check("level 6 near the tower: punish", punished(6, 50))
end

-- out of range ignored
do
	local H, bot, enemy = lane(0.9, { enemyX = -2300 })
	local creep = attempt(enemy)
	SetRandomSequence({ 0, 0.5, 0.5 })
	for i = 0, 20 do
		T = 100 + i * 0.1
		think(H, bot, { creep }, { enemy }, false)
	end
	check("enemy at attack range + 150: no roll", RandomUnread() == 3, RandomUnread())
	check("enemy at attack range + 150: no attack", attacksOn(1, enemy) == 0)
end

-- etiquette gates block the punish; without etiquette the same setup punishes.
do
	local function punished(etiquette, o, setup)
		local H, bot, enemy = lane(0.9, o)
		local creep = MakeCreep({ team = 2, x = (o.enemyX or -2500) - 200, y = BOT_Y, hp = 30 })
		enemy.target = creep
		if setup then setup() end
		SetRandomSequence({ 0 })
		for i = 0, 10 do
			T = 100 + i * 0.1
			think(H, bot, { creep }, { enemy }, etiquette)
		end
		return attacksOn(1, enemy) > 0
	end
	local weak = function() STRONGER = false end
	-- Dire T1 at 2800: the target is 800 from it, the bot 1300.
	local towerO = { botX = 1500, humanX = 1400, enemyX = 2000, level = 6 }
	check("etiquette, HP 45%: no punish", not punished(true, { hp = 45 }))
	check("no etiquette, HP 45%: punish", punished(false, { hp = 45 }))
	check("etiquette, not stronger: no punish", not punished(true, {}, weak))
	check("no etiquette, not stronger: punish", punished(false, {}, weak))
	check("etiquette, tower 800 from the target: no punish", not punished(true, towerO))
	check("no etiquette, tower 800 from the target at level 6: punish", punished(false, towerO))
end

-- low-skill random poke is the idle poke
do
	local function run(skill, etiquette, direct, untilT)
		local H, bot, enemy = lane(skill)
		landing(bot)
		SetRandomSequence({ 0 })
		local times = {}
		for i = 0, math.floor((untilT - 100) * 10 + 0.5) do
			T = 100 + i * 0.1
			local before = #ACTIONS
			if direct then
				H.Lane.Harass.IdlePoke(bot, { enemy }, H.Lane.Harass.GatesFor(bot, etiquette))
			else
				think(H, bot, {}, { enemy }, etiquette)
			end
			for j = before + 1, #ACTIONS do
				local a = ACTIONS[j]
				table.insert(times, string.format("%.1f:%s:%d:%s", T, a.kind, a.args[1].pid, tostring(a.args[2])))
			end
		end
		return times
	end
	local viaThink = run(0.3, false, false, 104.5)
	check("skill 0.3, interval 4 s: one poke in the first 4.5 s, at 4 s", #viaThink == 1 and viaThink[1] == "104.0:AttackUnit:6:true", viaThink[1])
	local direct = run(0.3, false, true, 104.5)
	check("the random poke's actions are IdlePoke's", table.concat(viaThink, ",") == table.concat(direct, ","))
	check("skill 0.9 without etiquette: no idle poke", #run(0.9, false, false, 106) == 0)
	local eti = run(0.3, true, false, 106)
	check("etiquette wins over low skill: pokes every 2.5 s", table.concat(eti, ",") == "100.0:AttackUnit:6:true,102.5:AttackUnit:6:true,105.0:AttackUnit:6:true", table.concat(eti, ","))
end

-- punish then idle share the timer
do
	local H, bot, enemy = lane(0.9)
	landing(bot)
	local creep = attempt(enemy)
	SetRandomSequence({ 0, 0.5, 0.5 })
	think(H, bot, { creep }, { enemy }, true)
	check("precondition: idle poke at 100", attacksOn(1, enemy) == 1)
	local punishAt = firstAttack(H, bot, { creep }, { enemy }, true, enemy, 101, 0.01)
	check("precondition: punish after the react delay", punishAt ~= nil and punishAt > 100)
	enemy.target = nil
	local nextAt = firstAttack(H, bot, { creep }, { enemy }, true, enemy, 106, 0.01)
	check("idle poke waits 2.5 s from the punish, not from the poke", nextAt ~= nil and nextAt >= punishAt + 2.5 - 1e-9 and nextAt < punishAt + 2.52, nextAt)
end

-- shared tool for a 04-owned bot with OwnLaningThink off; the human is too far for 04's poke.
do
	local cfg = { Enable = true, OwnLaningThink = "off", Harass = true }
	local H, bot, enemy = lane(0.9, { cfg = cfg, humanX = -5000 })
	check("07 does not own the bot", H.Lane.OwnsLaning(bot) == false)
	check("04 owns the bot", H.AllyLastHit.OwnsLaning(bot) == true)
	check("the shared tool supersedes 04's harass", H.Lane.SupersedesHarass(bot) == true)
	local creep = attempt(enemy)
	SetRandomSequence({ 0, 0.5, 0.5 })
	for i = 0, 10 do
		T = 100 + i * 0.1
		think(H, bot, { creep }, { enemy }, true)
	end
	check("the shared tool punishes the attempt", attacksOn(1, enemy) == 1)

	H, bot, enemy = lane(0.9, { cfg = cfg, humanX = -5000 })
	local env = { bot = bot, J = J, AllyLastHit = H.AllyLastHit, nInRangeEnemy = { enemy }, botAttackRange = bot:GetAttackRange(),
		harassStartTime = -90, lastHarassTime = -90 }
	local ref = makeRef(env)
	attempt(enemy)
	for i = 0, 10 do
		T = 100 + i * 0.1
		ref()
	end
	check("04's HarassThink never would", attacksOn(1, enemy) == 0)
end

-- a hands-off ping stops the shared tool
do
	local H, bot, enemy = lane(0.9)
	bot.lane = Lane.Bot
	check("precondition: etiquette bot pokes", think(H, bot, {}, { enemy }, true) == true)
	H.Orders.Post(2, { type = "LANE_HANDSOFF", sourceKey = "ping", issuerPID = 0, lane = Lane.Bot, duration = 30,
		maxResponders = 1, onlyPIDs = { 1 }, delayKind = "ping" })
	T = 110
	check("precondition: ping accepted", H.Orders.GetAcceptedForLane(bot, "LANE_HANDSOFF", Lane.Bot) ~= nil)
	local n = #ACTIONS
	check("hands off: no harass", think(H, bot, {}, { enemy }, true) == false and #ACTIONS == n)
end

-- supersedes gate
do
	local function sup(cfg)
		local H, bot = lane(0.9, { cfg = cfg })
		return H.Lane.SupersedesHarass(bot)
	end
	local allOff = { Enable = true }
	for _, f in ipairs({ "Plan", "Block", "FullPull", "HalfPull", "StackPull", "AggroPull", "Freeze", "Shove", "Stack",
		"Harass", "Mid", "CounterPlay", "Telegraph", "CampBlock" }) do allOff[f] = false end
	check("Harass on: supersedes", sup({ Enable = true, Harass = true }) == true)
	check("Harass off: 04 keeps its harass", sup({ Enable = true, Harass = false }) == false)
	check("Lane disabled: 04 keeps its harass", sup({ Enable = false }) == false)
	check("every lane flag off: 04 keeps its harass", sup(allOff) == false)
end

-- stand point: behind our lowest-HP creep near the enemy, at attack range minus the stand-back.
do
	local H, bot, enemy = lane(0.9)
	bot.lane = Lane.Bot
	local healthy = MakeCreep({ team = 2, x = -2600, y = BOT_Y, hp = 400 })
	local low = MakeCreep({ team = 2, x = -2700, y = BOT_Y, hp = 90 })
	local p = H.Lane.Harass.StandPoint(bot, enemy, { healthy, low })
	check("stand point is on our side of the low-HP creep at range - 50",
		p ~= nil and math.abs(p.x - (-2700 - 500)) < 1 and math.abs(p.y - BOT_Y) < 1, p and p.x)
	H, bot, enemy = lane(0.5)
	bot.lane = Lane.Bot
	check("below skill 0.6: no stand point", H.Lane.Harass.StandPoint(bot, enemy, { low }) == nil)
	H, bot, enemy = lane(0.9, { hp = 40 })
	bot.lane = Lane.Bot
	check("low HP: no stand point", H.Lane.Harass.StandPoint(bot, enemy, { low }) == nil)
	H, bot, enemy = lane(0.9)
	bot.lane = Lane.Bot
	STRONGER = false
	check("not stronger: no stand point", H.Lane.Harass.StandPoint(bot, enemy, { low }) == nil)
end

-- aggro dance after an idle poke: 07-only bots step back; the etiquette (04) poke keeps 04's behaviour.
do
	local function pokeIntoWave(skill, etiquette)
		local H, bot, enemy = lane(skill)
		bot.lane = Lane.Bot
		landing(bot)
		local foes = {}
		for i = 1, 3 do table.insert(foes, MakeCreep({ team = 3, x = -2700 + i * 10, y = BOT_Y })) end
		SetRandomSequence({ 0 })
		for i = 0, 50 do
			T = 100 + i * 0.1
			think(H, bot, {}, { enemy }, etiquette, foes)
		end
		return attacksOn(1, enemy), ActionsOf(1, "MoveToLocation")
	end
	local hits, moves = pokeIntoWave(0.3, false)
	check("07-only random poke into 3 creeps: one hit", hits == 1, hits)
	check("07-only random poke into 3 creeps: then a step back", #moves >= 1 and moves[1].args[1].x < -3000, #moves)
	hits, moves = pokeIntoWave(0.3, true)
	check("etiquette poke into 3 creeps: no step back", hits >= 1 and #moves == 0, #moves)
end

-- 04's HarassThink text pinned (scenario 15)
do
	local function fnText(path)
		local f = assert(io.open(path, "r"))
		local src = f:read("a")
		f:close()
		local s = src:find("local function HarassThink()", 1, true)
		local e = s and src:find("\nend\n", s, true)
		return s and e and src:sub(s, e + 3)
	end
	local live = fnText(HARNESS_DIR .. "/../../bots/mode_laning_generic.lua")
	local ref = fnText(HARNESS_DIR .. "/ref_harass_04.lua")
	check("04's HarassThink found", live ~= nil and #live > 200)
	check("04's HarassThink is unchanged", live == ref)
end

-- idle poke equals 04: same world, same frames, same actions and return values.
do
	local function scenario(build)
		local function run(useRef)
			local H, bot, enemy = lane(1.0)
			local enemies = { enemy }
			local step = build(H, bot, enemy, enemies)
			local fn
			if useRef then
				local env = { bot = bot, J = J, AllyLastHit = H.AllyLastHit, nInRangeEnemy = enemies, botAttackRange = bot:GetAttackRange(),
					harassStartTime = -90, lastHarassTime = -90 }
				fn = makeRef(env)
			else
				fn = function() return H.Lane.Harass.IdlePoke(bot, enemies, H.Lane.Harass.GatesFor(bot, true)) end
			end
			local trace = {}
			for i = 0, 60 do
				T = 100 + i * 0.1
				if step then step(i) end
				local before = #ACTIONS
				local ret = fn()
				local acts = {}
				for j = before + 1, #ACTIONS do
					local a = ACTIONS[j]
					table.insert(acts, a.kind .. ":" .. tostring(a.args[1].pid) .. ":" .. tostring(a.args[2]))
				end
				table.insert(trace, i .. "=" .. tostring(ret) .. "[" .. table.concat(acts, ",") .. "]")
			end
			return trace, #ActionsOf(1, "AttackUnit")
		end
		local refTrace, refAttacks = run(true)
		local ourTrace, ourAttacks = run(false)
		local diff
		for i = 1, #refTrace do
			if refTrace[i] ~= ourTrace[i] then diff = refTrace[i] .. " vs " .. ourTrace[i] break end
		end
		return diff, refAttacks, ourAttacks
	end
	local scenarios = {
		{ "window re-issue", function() end, true },
		{ "interval", function(_, bot) landing(bot) end, true },
		{ "HP 49%", function(_, bot) bot.hp = 49 end, false },
		{ "no protected human", function() UNITS[2][1].loc = Vector(-5000, BOT_Y) end, false },
		{ "not stronger", function() STRONGER = false end, false },
		{ "tower near the bot, then the enemy", function(_, bot)
			landing(bot)
			local tower = TOWERS_W[3][dota.Tower.Bot1]
			return function(i)
				if i < 30 then tower.loc = Vector(-3700, BOT_Y) else tower.loc = Vector(-1750, BOT_Y) end
				if i == 55 then tower.alive = false end
			end
		end, true },
		{ "two enemies: nearest chosen", function(_, bot, _, enemies)
			landing(bot)
			local near = MakeUnit({ pid = 7, team = 3, loc = Vector(-2800, BOT_Y) })
			table.insert(enemies, near)
		end, true },
		{ "illusion skipped", function(_, bot, _, enemies)
			landing(bot)
			local fake = MakeUnit({ pid = 7, team = 3, loc = Vector(-2800, BOT_Y) })
			fake.illusion = true
			table.insert(enemies, 1, fake)
		end, true },
		{ "enemy at attack range + 301, then + 299", function(_, bot, enemy)
			landing(bot)
			return function(i) enemy.loc = Vector(i < 30 and -2149 or -2151, BOT_Y) end
		end, true },
	}
	for _, sc in ipairs(scenarios) do
		local diff, refAttacks, ourAttacks = scenario(sc[2])
		check("idle poke equals 04: " .. sc[1], diff == nil, diff)
		check("idle poke equals 04: " .. sc[1] .. (sc[3] and " (attacks)" or " (no attacks)"),
			(refAttacks > 0) == sc[3] and refAttacks == ourAttacks, refAttacks .. "/" .. ourAttacks)
	end
end

finish()
