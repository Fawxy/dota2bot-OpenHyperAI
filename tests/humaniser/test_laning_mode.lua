-- mode_laning_generic GetDesire and Think run against a stubbed bot world and a stubbed humaniser.
dofile(HARNESS_DIR .. "/laning_mode_world.lua")
local creep, hero, load = LaningCreep, LaningHero, LaningLoad

local function last(bot) return bot.actions[#bot.actions] end

do
	local c = creep({ hp = 40, loc = Vector(100, 0) })
	load({ pos = 3, owned = true, enemyCreeps = { c } })
	check("owned laning: a pos 3 bids 0.9 with a killable creep", near(GetDesire(), 0.9), GetDesire())
	load({ pos = 3, owned = false, enemyCreeps = { c } })
	check("unowned laning: a pos 3 keeps upstream's desire", not near(GetDesire(), 0.9), GetDesire())
	load({ pos = 3, owned = true, enemyCreeps = { creep({ hp = 400 }) } })
	check("owned laning: nothing killable, no 0.9", not near(GetDesire(), 0.9), GetDesire())
end

do
	-- 60 HP against 50 damage: within 1.7x, so a move-to creep; it is in range (100 < 150 * 0.8).
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local allyCreep = creep({ hp = 40, loc = Vector(-100, 0) })
	allyCreep.GetHealth = function() return 40 end
	local bot, attempts = load({ pos = 1, owned = true, enemyCreeps = { enemyCreep }, allyCreeps = { allyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("nearly killable in range: the deny goes through instead of an early swing", a ~= nil and a.name == "AttackUnit" and a.args[1] == allyCreep, a and a.name)
	local attempted = false
	for _, c in ipairs(attempts) do if c == enemyCreep then attempted = true end end
	check("no attempt is counted on the nearly-killable creep", not attempted, #attempts)
	enemyCreep.hp = 45
	GetDesire()
	Think()
	a = last(bot)
	check("killable on the next frame: it is attacked", a ~= nil and a.name == "AttackUnit" and a.args[1] == enemyCreep, a and a.name)
end

do
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("nearly killable in range, nothing to deny: the bot holds, no attack", a ~= nil and a.name == "MoveToLocation" and #bot.actions == 1, a and a.name)
end

do
	-- A bot support (pos 5) at x=0; a bot core 800 away at x=800 but within its range + 150 of a creep at x=700.
	local c = creep({ hp = 40, loc = Vector(100, 0) })
	local core = hero({ pos = 1, pid = 2, loc = Vector(800, 0), range = 600 })
	local bot = load({ pos = 5, owned = true, enemyCreeps = { c }, allies = { core } })
	GetDesire()
	Think()
	local hit = false
	for _, a in ipairs(bot.actions) do if a.name == "AttackUnit" and a.args[1] == c then hit = true end end
	check("support leaves a creep its core 800 away can reach", not hit)
	core.loc = Vector(1500, 0)
	bot.actions = {}
	GetDesire()
	Think()
	hit = false
	for _, a in ipairs(bot.actions) do if a.name == "AttackUnit" and a.args[1] == c then hit = true end end
	check("support takes a creep its core cannot reach", hit)
end

do
	-- Final review fix: the hold is capped. A creep nobody is hitting never turns killable; after HoldMax the bot swings.
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	check("hold: the first frame holds", last(bot).name == "MoveToLocation")
	DotaTime = function() return 121.6 end
	GameTime = DotaTime
	GetDesire()
	Think()
	local a = last(bot)
	check("hold: past HoldMax the bot swings at the creep", a.name == "AttackUnit" and a.args[1] == enemyCreep, a.name)
end

do
	-- Final review fix: with the humaniser off, upstream's own owned case (pos 1 with a human pos 5) keeps upstream's
	-- early swing and its 700-radius core check.
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = false, humanPos5 = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("humaniser off: upstream's early swing is kept", a ~= nil and a.name == "AttackUnit" and a.args[1] == enemyCreep, a and a.name)
end

do
	-- Final review fix: the last-hit state handed to PreThink is gated like LastHitThink and reads 'kill' only in range.
	local c = creep({ hp = 40, loc = Vector(100, 0) })
	local core = hero({ pos = 1, pid = 2, loc = Vector(200, 0), range = 600 })
	local bot = load({ pos = 5, owned = true, enemyCreeps = { c }, allies = { core } })
	GetDesire()
	Think()
	check("a support's core's creep is no last hit for PreThink", bot.preThinkLastHit == nil, tostring(bot.preThinkLastHit))
	local far = creep({ hp = 40, loc = Vector(700, 0) })
	bot = load({ pos = 1, owned = true, enemyCreeps = { far } })
	GetDesire()
	Think()
	check("a killable creep out of attack range reads as soon, not kill", bot.preThinkLastHit == "soon", tostring(bot.preThinkLastHit))
end

-- Ours.LeaveCoreCreep (slice 3): the switch alone makes a support own this Think(); off, it is Valve's (OHA) as before.
do
	LaningLoad({ pos = 5, ours = false })
	check("switch off: a pos5 bot does not own the laning Think", Think == nil)
	LaningLoad({ pos = 5, ours = true })
	check("switch on: a pos5 bot owns the laning Think", Think ~= nil)
	LaningLoad({ pos = 1, ours = true })
	check("switch on: a pos1 bot is not taken over", Think == nil)
end

finish()
