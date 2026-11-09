dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice retreat (master docs/team/slices/retreat.md): our retreat for a laning hero. The leave rule (over budget for the
-- hero's reaction time; lethal, a tower on us and the heal floor at once), the anchor by route cost, the exit band and its
-- dwell, an ally in retreat counting no help, the areas' retreat nudges off for an owned hero, and the OFF arm.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

-- The Radiant bot lane: our T1 at x = -2,800, theirs at x = 2,800 (reach 844).
local HERE = Vector(0, -5000)

local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true }, retreat = o.off ~= true })
	T = o.t or 300
	CURRENT_TEAM, OBSERVER = 2, 1
	FOGGED = function() return false end
	H.Retreat.ResetCache()
	require("bots/FunLib/humaniser/threat").ResetCache()
	local bot = MakeUnit({ pid = 1, team = 2, loc = o.loc or HERE, level = 3 })
	bot.lane, bot.pos, bot.maxhp, bot.hp = Lane.Bot, 1, 600, o.hp or 600
	return H, bot
end

local function enemy(pid, loc, est)
	local e = MakeUnit({ pid = pid, team = 3, loc = loc })
	e.maxhp, e.hp, e.range, e.estDamage = 600, 600, 150, est or 0
	return e
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function lines(all, ev)
	local r = {}
	-- ph=read lines (band changes) are counted apart: the checks below read starts and ends.
	for _, l in ipairs(all) do if l:find("ev=" .. ev .. " ", 1, true) and not l:find(" ph=read ", 1, true) then r[#r + 1] = l end end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local function react(bot)
	return require("bots/FunLib/humaniser/profile").Get(bot).reactBase
end

-- Over budget: the hero leaves only once the threat has lasted its reaction time, not on a flicker. Two heroes in reach with
-- a third of our HP in burst read 0.25 x 2 + 0.5 x 0.33 = 0.67 against the free budget 0.5.
do
	local H, bot = world()
	enemy(10, Vector(300, -5000), 100)
	enemy(11, Vector(300, -4900), 100)
	local out = capture(function()
		check("leave: no episode on the first over-budget read", H.Retreat.Desire(bot) == 0)
		T = T + react(bot) * 0.5
		check("leave: still none before the reaction time", H.Retreat.Desire(bot) == 0)
		T = T + react(bot) * 0.6
		check("leave: the episode's desire once it has lasted", H.Retreat.Desire(bot) == 0.95, H.Retreat.Desire(bot))
	end)
	local reads = {}
	for _, l in ipairs(out) do if l:find("ev=retreat ph=read ", 1, true) then reads[#reads + 1] = l end end
	local s = lines(out, "retreat")[1]
	check("leave: one ph=read line per band change, not per think", #reads == 1 and field(reads[1], "band") == "pressured", #reads)
	check("leave: ev=retreat start why=threat with the budget and purpose", field(s, "why") == "threat" and tonumber(field(s, "budget")) == 0.5 and field(s, "purp") == "free", s)
	check("leave: the hero counts as retreating for its allies' read", H.Retreat.Running(bot))
end

-- A flicker: the threat drops under budget before the reaction time, so the clock restarts.
do
	local H, bot = world()
	local e1 = enemy(10, Vector(300, -5000), 100)
	enemy(11, Vector(300, -4900), 100)
	capture(function()
		H.Retreat.Desire(bot)
		T = T + react(bot) * 0.6
		e1.alive = false
		H.Retreat.Desire(bot)
		e1.alive = true
		T = T + react(bot) * 0.6
		check("leave: a dip under budget restarts the clock", H.Retreat.Desire(bot) == 0)
	end)
end

-- One lane opponent in reach at full HP is under budget: the laner stays (OHA counted heads; the rule prices them).
do
	local H, bot = world()
	enemy(10, Vector(300, -5000), 60)
	capture(function()
		H.Retreat.Desire(bot)
		T = T + 3
		check("stay: one opponent in reach at full HP", H.Retreat.Desire(bot) == 0)
	end)
end

-- Lethal leaves at once; an escape item ready (or a faster bot out of their range) is not lethal.
do
	local H, bot = world({ hp = 200 })
	enemy(10, Vector(300, -5000), 250)
	local out = capture(function() check("lethal: leaves on the first read", H.Retreat.Desire(bot) == 0.95) end)
	check("lethal: why=lethal", field(lines(out, "retreat")[1], "why") == "lethal")
	local H2, bot2 = world({ hp = 200 })
	enemy(10, Vector(300, -5000), 250)
	bot2.items = { [0] = { name = "item_force_staff", ready = true } }
	local r = require("bots/FunLib/humaniser/threat").Read(bot2, HERE, HERE, 2)
	check("escape: a force staff ready drops lethal", r.escape == true and r.band ~= "lethal", r.band)
	bot2.items = { [0] = { name = "item_force_staff", ready = false } }
	check("escape: on cooldown it does not", require("bots/FunLib/humaniser/threat").Read(bot2, HERE, HERE, 2).band == "lethal")
	bot2.items = nil
	bot2.speed = 350
	local near_ = enemy(12, Vector(100, -5000), 0)
	near_.speed = 290
	local _ = H2
	check("escape: slower chasers but one already in range: no escape", require("bots/FunLib/humaniser/threat").Read(bot2, HERE, HERE, 2).escape == false)
end

-- A tower on us leaves at once, and the anchor is the point just out of its reach, not the walk to our tower through it.
do
	local H, bot = world({ loc = Vector(2300, -5000) })
	TOWERS_W[3][dota.Tower.Bot1].target = bot
	local out = capture(function() check("tower: leaves at once", H.Retreat.Desire(bot) == 0.95) end)
	local s = lines(out, "retreat")[1]
	check("tower: why=tower, anchor the reach's edge", field(s, "why") == "tower" and field(s, "anchor") == "tower_edge", s)
end

-- The tower's damage flag lasts 0.5 s past the hit: a hero already out of the reach (an episode just ended at its edge) does
-- not start another on the flag alone; inside the reach it does (drills rtwalk2, rtchase2: episodes chained every 0.3 s).
do
	local H, bot = world({ loc = Vector(2800 - 844 - 150, -5000) })
	bot.towerHitAt = T
	capture(function() check("tower flag: out of the reach, no new episode", H.Retreat.Desire(bot) == 0) end)
	local H2, bot2 = world({ loc = Vector(2800 - 600, -5000) })
	bot2.towerHitAt = T
	capture(function() check("tower flag: inside the reach, leaves at once", H2.Retreat.Desire(bot2) == 0.95) end)
end

-- A drill's held hero (here the chase drill's Dire pos3 chaser) is the drill's, not ours: lethal reads start no episode.
do
	local H, bot = world({ hp = 200 })
	bot.team, bot.pos = 3, 3
	package.loaded["bots/FunLib/custom_loader"].Overrides = { Drill = "retreat-chase" }
	H.Drill.ResetCache()
	MakeUnit({ pid = 0, team = 2, loc = Vector(300, -5000) }).estDamage = 250
	local held = H.Drill.Held(bot)
	check("held: the chaser is held", held, H.Drill.RoleOf(bot))
	check("held: our retreat does not own it", held and H.Retreat.Desire(bot) == nil and not H.Retreat.Owns(bot))
	package.loaded["bots/FunLib/custom_loader"].Overrides = nil
	H.Drill.ResetCache()
end

-- The heal floor: under 0.3 HP with nobody in reach the hero goes home, and stays in the episode until 0.8 at the fountain.
do
	local H, bot = world({ hp = 150 })
	local out = capture(function()
		check("heal: leaves under the floor with no enemy in reach", H.Retreat.Desire(bot) == 0.95)
		bot.loc = H.Retreat.Fountain(2)
		T = T + 5
		check("heal: at the fountain below 0.8 the episode holds", H.Retreat.Desire(bot) == 0.95)
		bot.hp = 500
		T = T + 1
		check("heal: ends at 0.8", H.Retreat.Desire(bot) == 0)
	end)
	local l = lines(out, "retreat")
	check("heal: anchor fountain, end res=anchor", field(l[1], "anchor") == "fountain" and field(l[2], "res") == "anchor", l[2])
end

-- Route cost: our T1 lies past an enemy wave (its acquisition covers the walk), so with an ally standing clear behind us
-- the ally anchor wins over the shorter walk through the wave.
do
	local H, bot = world({ loc = Vector(-1500, -5000), hp = 150 })
	MakeCreep({ team = 3, x = -2200, y = -5000 })
	local ally = MakeUnit({ pid = 2, team = 2, loc = Vector(-1500, -6200) })
	ally.maxhp, ally.hp = 600, 600
	enemy(10, Vector(-900, -5000), 400)
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + 1
		H.Retreat.Desire(bot)
	end)
	local s = lines(out, "retreat")[1]
	check("route: the walk clear of the wave wins", field(s, "anchor") == "ally" and tonumber(field(s, "alt")) > tonumber(field(s, "cost")), s)
end

-- The exit band: the episode ends `safe` only once threat stays under budget - 0.15 for 1.5 s; a spike in the dwell restarts it.
do
	local H, bot = world()
	local e1 = enemy(10, Vector(300, -5000), 100)
	local e2 = enemy(11, Vector(300, -4900), 100)
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + 2
		H.Retreat.Desire(bot)
		e1.alive, e2.alive = false, false
		T = T + 1
		check("exit: under the band, still in the dwell", H.Retreat.Desire(bot) == 0.95)
		e1.alive, e2.alive = true, true
		T = T + 0.2
		H.Retreat.Desire(bot)
		e1.alive, e2.alive = false, false
		T = T + 0.2
		H.Retreat.Desire(bot)
		T = T + 1.2
		check("exit: the spike restarted the dwell", H.Retreat.Desire(bot) == 0.95)
		T = T + 0.5
		check("exit: ends after 1.5 s under the band", H.Retreat.Desire(bot) == 0)
	end)
	local l = lines(out, "retreat")
	check("exit: res=safe", field(l[#l], "res") == "safe", l[#l])
end

-- An ally in our retreat counts no help: the lane partner's leave drops it from the other's ally count.
do
	local H, bot = world()
	local ally = MakeUnit({ pid = 2, team = 2, loc = Vector(-100, -5000) })
	ally.maxhp, ally.hp = 600, 600
	enemy(10, Vector(300, -5000), 100)
	local Threat = require("bots/FunLib/humaniser/threat")
	check("ally: counted while it stays", Threat.Read(bot, HERE, HERE, 2).allies == 1)
	require("bots/FunLib/humaniser/retreat_state").SetRunning(ally, true)
	check("ally: no help while it retreats", Threat.Read(bot, HERE, HERE, 2).allies == 0)
end

-- A death ends the episode with res=died.
do
	local H, bot = world({ hp = 200 })
	enemy(10, Vector(300, -5000), 250)
	local out = capture(function()
		H.Retreat.Desire(bot)
		bot.alive = false
		H.Retreat.Tick(bot)
	end)
	local l = lines(out, "retreat")
	check("death: res=died", field(l[2], "res") == "died" and not H.Retreat.Running(bot), l[2])
end

-- The OFF arm leaves OHA's desire (the nudges' own arms: test_transitions_caution "retreat on").
do
	local H2, bot2 = world({ off = true })
	check("off: Desire leaves OHA's (nil)", H2.Retreat.Desire(bot2) == nil and not H2.Retreat.Owns(bot2))
end

-- The plain walk for a hero we do not own: our tower behind it above half HP, the fountain below.
do
	local H, bot = world({ off = true })
	package.loaded["bots/FunLib/custom_loader"].Ours.Retreat = true
	LANING = false
	H.Retreat.ResetCache()
	capture(function() H.Retreat.Think(bot) end)
	local m = ACTIONS[#ACTIONS] and ACTIONS[#ACTIONS].args[1]
	check("plain: walks to our T1's stand point", m ~= nil and m.x < -2800 and m.x > -3300, m and m.x)
	bot.hp = 200
	H.Retreat.ResetCache()
	capture(function() H.Retreat.Think(bot) end)
	m = ACTIONS[#ACTIONS] and ACTIONS[#ACTIONS].args[1]
	check("plain: the fountain below half HP", m ~= nil and m.x < -6000, m and m.x)
end

finish()
