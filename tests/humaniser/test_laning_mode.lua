-- mode_laning_generic GetDesire and Think run against a stubbed bot world and a stubbed humaniser.
dofile(HARNESS_DIR .. "/laning_mode_world.lua")
local creep, hero, load = LaningCreep, LaningHero, LaningLoad

local function last(bot) return bot.actions[#bot.actions] end

-- Slice job-chooser: 25 s of gated frames leave laning's desire as if it had never been skipped (the wrapper skips OHA's file).
do
	local function world(gate)
		T = 200
		return load({ pos = 3, owned = true, enemyCreeps = { creep({ hp = 40, loc = Vector(100, 0) }) }, chooser = gate })
	end
	world()
	T = 225
	local never = GetDesire()
	local gated = true
	local entered = false
	world({ Gate = function(_, _, inner) return function()
		if gated then return 0 end
		entered = true
		return inner()
	end end })
	local allZero = true
	while T < 225 do
		if GetDesire() ~= 0 then allZero = false end
		T = T + 0.1
	end
	T = 225
	gated = false
	check("laning, gated for 25 s: 0 and OHA's code not run", allZero and not entered)
	check("laning after a gated period: as if never gated", near(GetDesire(), never), never)
end

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
	-- 60 HP against 50 damage: within 1.7x, so a move-to creep; it is in range (100 < 150 * 0.8). OHA's own owned case
	-- (pos 1 with a human pos 5) swings early, as upstream does.
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = false, humanPos5 = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("OHA's owned case: upstream's early swing", a ~= nil and a.name == "AttackUnit" and a.args[1] == enemyCreep, a and a.name)
end

-- Slice step-telemetry: the step Think reports is the one whose order ended the frame (ev=snap step=).
do
	local function stepOf(opts)
		local bot = load(opts)
		GetDesire()
		Think()
		return bot.step, bot
	end
	local killable = creep({ hp = 40, loc = Vector(100, 0) })
	local own = creep({ hp = 40, loc = Vector(-100, 0) })
	check("step: OHA's last hit", stepOf({ pos = 1, owned = true, enemyCreeps = { killable } }) == "oha_lh")
	check("step: OHA's deny with no enemy creep to hit", stepOf({ pos = 1, owned = true, allyCreeps = { own } }) == "oha_deny")
	check("step: sustain's walk before OHA's steps", stepOf({ pos = 1, owned = true, sustainWalk = true, enemyCreeps = { killable } }) == "sustain")
	check("step: nothing to hit, OHA's position", stepOf({ pos = 1, owned = true }) == "oha_pos")
	check("step: lane-only, nothing to hit, OHA's position", stepOf({ pos = 3, owned = true, laneOnly = true, enemyCreeps = { creep({ hp = 400, loc = Vector(100, 0) }) } }) == "oha_pos")
end

-- Lane-only (slice lane-last-hits; drill `lane-only`): the lane-only harness holds every bot in laning above every other mode and runs
-- only the last-hit steps and the position.
do
	local c = creep({ hp = 400, loc = Vector(100, 0) })
	local bot = load({ pos = 3, owned = true, laneOnly = true, enemyCreeps = { c } })
	check("lane-only: laning bids above absolute with nothing killable", GetDesire() > 1, GetDesire())
	Think()
	check("lane-only: nothing killable, OHA's position moves the bot", last(bot) ~= nil and last(bot).name == "MoveToLocation")
	load({ pos = 3, owned = true, enemyCreeps = { c } })
	check("not lane-only: laning keeps upstream's desire with nothing killable", GetDesire() < 1, GetDesire())
	-- The chase drill's cast retreats live: our retreat's 0.95 must be able to beat laning while its episode runs.
	load({ pos = 3, owned = true, laneOnly = true, retreatRunning = true, enemyCreeps = { c } })
	check("lane-only: steps aside under our retreat's episode", GetDesire() < 0.95, GetDesire())
end

finish()
