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

-- Bottom lane: our bot (pid 1) at x = -800 facing an enemy (pid 6) at x = 300, from either team's side; `sign`
-- mirrors x so our side is always negative x. The enemy T1 stands at x = 2800 (mirrored for Dire).
local function world(o)
	o = o or {}
	local team = o.team or 2
	local other = team == 2 and 3 or 2
	local sign = team == 2 and 1 or -1
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = o.laneFight, telemetry = o.telemetry })
	T = 100
	CURRENT_TEAM = team
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.5, 0.5
	local bot = MakeUnit({ pid = 1, team = team, loc = Vector(sign * -800, BOT_Y), hp = o.botHP or 100 })
	bot.pos, bot.lane = 5, Lane.Bot
	bot.estDamage = o.burst or 500
	OBSERVER = bot
	local enemy = MakeUnit({ pid = 6, team = other, loc = Vector(sign * (o.enemyX or 300), BOT_Y), hp = o.hp or 450 })
	enemy.lane = Lane.Bot
	if o.regen then enemy.GetHealthRegen = function() return o.regen end end
	if o.escape then enemy.abilities = { [0] = ability("antimage_blink", { cd = 12 }) } end
	local W = { H = H, bot = bot, enemy = enemy, sign = sign, other = other, KC = H.LaneFight.KillCheck, M = H.LaneFight.CooldownMemory }
	function W.check(partners) return W.KC.Check(bot, partners or {}, enemy, T) end
	return W
end

local base = { burst = 500, hp = 450, regen = 5, escapeReady = false, towerInRange = false, enemiesNear = 1, alliesNear = 1,
	skill = 1, errRoll = 0.5 }
local function with(over) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(over) do t[k] = v end return t end

do
	local H = LaneFresh({ Enable = true }, {})
	local KC = H.LaneFight.KillCheck
	local pass, margin = KC.Passes(base)
	check("exact maths with fixed inputs", pass == true and near(margin, 500 / 460), tostring(margin))
	pass, margin = KC.Passes(with({ skill = 0, errRoll = 0 }))
	check("low-skill error can flip the result", pass == false and near(margin, 500 * 0.7 / 460), tostring(margin))
	pass, margin = KC.Passes(with({ skill = 0, errRoll = 1, burst = 400 }))
	check("low-skill error can also overrate the burst", pass == true and near(margin, 400 * 1.3 / 460), tostring(margin))

	local p1 = KC.Passes(with({ burst = 1200, hp = 1000, regen = 0, towerInRange = false }))
	local p2 = KC.Passes(with({ burst = 1200, hp = 1000, regen = 0, towerInRange = true }))
	local p3 = KC.Passes(with({ burst = 1350, hp = 1000, regen = 0, towerInRange = true }))
	check("tower needs 1.3x: 1.2 passes away from the tower", p1 == true)
	check("tower needs 1.3x: 1.2 under the tower fails", p2 == false)
	check("tower needs 1.3x: 1.35 under the tower passes", p3 == true)

	local big = { burst = 2000, hp = 1000, regen = 0 }
	check("a big margin passes on its own", KC.Passes(with(big)) == true)
	check("escape believed ready blocks the kill", KC.Passes(with({ burst = 2000, hp = 1000, regen = 0, escapeReady = true })) == false)
	local e = KC.Evaluate(with({ burst = 2000, hp = 1000, regen = 0, escapeReady = true }))
	check("escape fail reason", e.reason == "escape", tostring(e.reason))
	check("outnumbered blocks the kill", KC.Passes(with({ burst = 2000, hp = 1000, regen = 0, enemiesNear = 2, alliesNear = 1 })) == false)
	check("level numbers do not block the kill", KC.Passes(with({ burst = 2000, hp = 1000, regen = 0, enemiesNear = 2, alliesNear = 2 })) == true)
	e = KC.Evaluate(with({ burst = 2000, hp = 1000, regen = 0, enemiesNear = 3, alliesNear = 2 }))
	check("outnumbered fail reason", e.reason == "outnumbered", tostring(e.reason))
	e = KC.Evaluate(with({ burst = 1200, hp = 1000, regen = 0, towerInRange = true }))
	check("tower fail reason", e.reason == "tower" and e.pass == false, tostring(e.reason))
	e = KC.Evaluate(with({ burst = 900, hp = 1000, regen = 0 }))
	check("burst fail reason", e.reason == "burst" and e.pass == false, tostring(e.reason))
	e = KC.Evaluate(with({ burst = 1400, hp = 1000, regen = 0 }))
	check("1.4x is not overwhelming", e.pass == true and e.overwhelming == false and e.reason == nil)
	e = KC.Evaluate(with({ burst = 1500, hp = 1000, regen = 0 }))
	check("1.5x is overwhelming", e.pass == true and e.overwhelming == true)
	e = KC.Evaluate(with({ burst = 2000, hp = 1000, regen = 0, enemiesNear = 2, alliesNear = 2, botHP = 0.4 }))
	check("two enemies near and bot under half HP fails on counter-burst", e.pass == false and e.reason == "counter", tostring(e.reason))
	e = KC.Evaluate(with({ burst = 2000, hp = 1000, regen = 0, enemiesNear = 2, alliesNear = 2, botHP = 0.6 }))
	check("two enemies near and bot over half HP passes", e.pass == true, tostring(e.reason))
	e = KC.Evaluate(with({ burst = 2000, hp = 1000, regen = 0, enemiesNear = 1, alliesNear = 1, botHP = 0.4 }))
	check("one enemy near does not trip counter-burst", e.pass == true, tostring(e.reason))
end

for _, team in ipairs({ 2, 3 }) do
	local tag = team == 2 and " (radiant)" or " (dire)"
	local W = world({ team = team })
	local r = W.check()
	check("Check reads burst, HP and regen from the units" .. tag, r ~= nil and r.pass == true and near(r.margin, 500 / 450), r and r.margin)

	W = world({ team = team, regen = 30 })
	r = W.check()
	check("Check counts the target's regen" .. tag, r ~= nil and r.pass == false and r.reason == "burst" and near(r.margin, 500 / 510),
		r and r.margin)

	-- Target 600 from the enemy T1 at x = 2800; the bot stands close enough to count its burst.
	W = world({ team = team, enemyX = 2200, burst = 540, hp = 450 })
	W.bot.loc = Vector(W.sign * 1500, BOT_Y)
	r = W.check()
	check("1.2x under their tower fails" .. tag, r ~= nil and r.pass == false and r.reason == "tower", r and r.reason)
	W = world({ team = team, enemyX = 2200, burst = 610, hp = 450 })
	W.bot.loc = Vector(W.sign * 1500, BOT_Y)
	r = W.check()
	check("1.35x under their tower passes" .. tag, r ~= nil and r.pass == true, r and r.reason)
	-- Our own T1 at x = -2800: a target beside it is not under an enemy tower.
	W = world({ team = team, enemyX = -2300, burst = 540, hp = 450 })
	W.bot.loc = Vector(W.sign * -2000, BOT_Y)
	r = W.check()
	check("1.2x beside our own tower passes" .. tag, r ~= nil and r.pass == true, r and r.reason)
end

do
	local W = world({ escape = true, burst = 900 })
	local r = W.check()
	check("an unseen escape counts as ready", r ~= nil and r.pass == false and r.reason == "escape", r and r.reason)
	SetRandomSequence({ 0.1, 0.5 })
	W.M.Record(1, 6, "antimage_blink", "key", 12, 1, T)
	SetRandomSequence({})
	T = T + 1
	r = W.check()
	check("a remembered escape on cooldown no longer blocks the kill", r ~= nil and r.pass == true, r and r.reason)
	T = T + 13
	r = W.check()
	check("the escape blocks again once remembered back up", r ~= nil and r.pass == false and r.reason == "escape", r and r.reason)
end

do
	local W = world({ burst = 300, hp = 500 })
	local partner = MakeUnit({ pid = 2, team = 2, loc = Vector(-700, BOT_Y) })
	partner.lane = Lane.Bot
	partner.estDamage = 300
	local r = W.check({ partner })
	check("a partner near the target adds its burst", r ~= nil and r.pass == true and near(r.margin, 600 / 500), r and r.margin)
	partner.loc = Vector(-6500, BOT_Y)
	T = T + 1
	r = W.check({ partner })
	check("a partner beyond 1,200 adds nothing", r ~= nil and r.pass == false and near(r.margin, 300 / 500), r and r.margin)
	partner.loc = Vector(-700, BOT_Y)
	partner.alive = false
	T = T + 1
	r = W.check({ partner })
	check("a dead partner adds nothing", r ~= nil and near(r.margin, 300 / 500), r and r.margin)
	partner.alive = true
	partner.removed = true
	T = T + 1
	local ok, res = pcall(W.check, { partner, nil })
	check("a removed partner handle adds nothing and does not error", ok and res ~= nil and near(res.margin, 300 / 500), res)
	partner.removed = false
	partner.IsIllusion = function() return true end
	T = T + 1
	r = W.check({ partner })
	check("an illusion partner adds nothing", r ~= nil and near(r.margin, 300 / 500), r and r.margin)
end

do
	local W = world({ burst = 300, hp = 500 })
	W.bot.loc = Vector(-2000, BOT_Y)
	local r = W.check()
	check("the bot's own burst counts only within 1,200", r ~= nil and r.margin == 0, r and r.margin)
end

do
	local W = world()
	W.enemy.illusion = true
	local r = W.check()
	check("illusion targets are skipped", r ~= nil and r.pass == false and r.reason == "illusion", r and r.reason)
	W = world()
	W.enemy.IsIllusion = function() return true end
	r = W.check()
	check("engine illusions are skipped", r ~= nil and r.pass == false and r.reason == "illusion", r and r.reason)
	W = world()
	W.enemy.unkillable = true
	r = W.check()
	check("CannotBeKilled targets are skipped", r ~= nil and r.pass == false and r.reason == "unkillable", r and r.reason)
	W = world()
	W.enemy.IsMagicImmune = function() return true end
	r = W.check()
	check("magic immune targets are skipped", r ~= nil and r.pass == false and r.reason == "magic_immune", r and r.reason)
end

do
	-- Two enemies in lane against our bot and its partner: not outnumbered, but the bot is low.
	local W = world({ burst = 1000, botHP = 40 })
	local partner = MakeUnit({ pid = 2, team = 2, loc = Vector(-700, BOT_Y) })
	partner.lane = Lane.Bot
	local second = MakeUnit({ pid = 7, team = 3, loc = Vector(600, BOT_Y) })
	second.lane = Lane.Bot
	local r = W.check({ partner })
	check("low bot facing two enemies fails on counter-burst", r ~= nil and r.pass == false and r.reason == "counter", r and r.reason)
	W.bot.hp = 70
	T = T + 1
	r = W.check({ partner })
	check("healthy bot facing two enemies with a partner passes", r ~= nil and r.pass == true, r and r.reason)
	partner.alive = false
	T = T + 1
	r = W.check({ partner })
	check("two enemies against the bot alone is outnumbered", r ~= nil and r.pass == false and r.reason == "outnumbered", r and r.reason)
end

do
	-- An enemy last seen 5 s ago in lane counts towards the outnumber rule, one seen 15 s ago does not.
	local W = world({ burst = 1000 })
	MakeUnit({ pid = 7, team = 3, loc = Vector(600, BOT_Y) }).CanBeSeen = function() return false end
	LAST_SEEN[7] = { location = Vector(600, BOT_Y), time_since_seen = 5 }
	local r = W.check()
	check("a recently seen enemy in lane counts", r ~= nil and r.reason == "outnumbered", r and r.reason)
	LAST_SEEN[7] = { location = Vector(600, BOT_Y), time_since_seen = 15 }
	T = T + 1
	W.H.Lane.LaneState.ResetCache()
	r = W.check()
	check("an enemy last seen long ago does not count", r ~= nil and r.pass == true, r and r.reason)
end

do
	local W = world({ skill = 0, burst = 500, hp = 450 })
	-- Profile and lane snapshot draw their own rolls on first use.
	W.H.Profile.Get(W.bot)
	W.H.Lane.LaneState.ForBot(W.bot)
	SetRandomSequence({ 1, 0 })
	local r1 = W.check()
	check("the error roll is drawn for a fresh check", r1 ~= nil and near(r1.margin, 500 * 1.3 / 450), r1 and r1.margin)
	check("one roll per fresh check", RandomUnread() == 1, RandomUnread())
	T = T + 0.3
	W.bot.estDamage = 100
	local r2 = W.check()
	check("the result is cached for KillCheckEvery", r2 ~= nil and near(r2.margin, r1.margin), r2 and r2.margin)
	check("a cached check draws no roll", RandomUnread() == 1, RandomUnread())
	T = T + 0.3
	local r3 = W.check()
	check("a fresh check after KillCheckEvery rereads the units", r3 ~= nil and near(r3.margin, 100 * 0.7 / 450), r3 and r3.margin)
	SetRandomSequence({})
	local other = MakeUnit({ pid = 8, team = 3, loc = Vector(300, BOT_Y), hp = 50 })
	local r4 = W.KC.Check(W.bot, {}, other, T)
	check("the cache is per target", r4 ~= nil and r4.pass == true, r4 and r4.margin)
end

do
	local W = world()
	W.enemy.CanBeSeen = function() return false end
	local ok, r = pcall(W.check)
	check("an unseen target gives no check", ok and r == nil, r)
	W = world()
	W.enemy.loc = nil
	ok, r = pcall(W.check)
	check("a target without a location gives no check", ok and r == nil, r)
	W = world()
	W.enemy.removed = true
	ok, r = pcall(W.check)
	check("a removed target gives no check", ok and r == nil, r)
	W = world()
	W.enemy.alive = false
	ok, r = pcall(W.check)
	check("a dead target gives no check", ok and r == nil, r)
end

do
	local W = world({ laneFight = { Kill = false } })
	check("Kill off gives no check", W.check() == nil)
end

do
	local W = world({ telemetry = { Enable = true, LuaErrors = true } })
	local r = W.H.LaneFight.CheckKill(W.bot, {}, W.enemy, T)
	check("the guarded facade answers", r ~= nil and r.pass == true)
	W.enemy.GetHealth = function() error("boom") end
	T = T + 1
	r = W.H.LaneFight.CheckKill(W.bot, {}, W.enemy, T)
	check("an error in the guarded facade reads as no check", r == nil)
end

finish()
