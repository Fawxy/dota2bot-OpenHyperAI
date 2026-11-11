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

-- An engaged hero (it hit us within a second) is counted over EngagedWindow (6 s), so one melee hero that keeps hitting at about
-- 2.6% of our max HP a second reads 0.25 + 0.5 x 0.156 / HP: over the free budget from about 31% HP, 0.33 at full HP.
-- rtlng2: the lane spot alone could not out-walk him; leaving a hero that is hitting us is the retreat's job.
do
	local function engagedWorld(hp, engaged)
		local H, bot = world({ hp = hp })
		local e = enemy(10, Vector(300, -5000), 0)
		e.GetEstimatedDamageToTarget = function(_, _, _, dur) return 15.6 * dur end
		local function hit() if engaged then bot.hitBy = { [e] = T - 0.2 } end end
		hit()
		return H, bot, e, hit
	end
	local function leaves(hp, engaged)
		local H, bot, e, hit = engagedWorld(hp, engaged)
		local out = capture(function()
			H.Retreat.Desire(bot)
			T = T + react(bot) + 1
			hit()
			H.Retreat.Desire(bot)
		end)
		return H.Retreat.Running(bot), lines(out, "retreat")[1]
	end
	local on, s = leaves(150, true)
	check("engaged: a melee hero hitting us at 25% HP starts a retreat why=threat, logged with eng", on and field(s, "why") == "threat" and field(s, "eng") == "1", s)
	check("engaged: the same hero not hitting us at 25% HP starts none (2 s window)", not leaves(150, false))
	check("engaged: at full HP the hitting hero starts none (a lone harasser is not run from)", not leaves(600, true))
	local H, bot, e, hit = engagedWorld(150, true)
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + react(bot) + 1
		hit()
		H.Retreat.Desire(bot)
		for _ = 1, 5 do T = T + 1 hit() H.Retreat.Desire(bot) end
	end)
	check("engaged: the episode does not end safe while he still hits us", H.Retreat.Running(bot) and #lines(out, "retreat") == 1, #lines(out, "retreat"))
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

-- The regen credit is for our tower's stand point, not the enemy tower's edge: a tango held leaves a tower_edge cost as it was.
do
	local function edgeCost(items)
		local H, bot = world({ loc = Vector(2300, -5000) })
		bot.items = items
		TOWERS_W[3][dota.Tower.Bot1].target = bot
		local out = capture(function() H.Retreat.Desire(bot) end)
		return tonumber(field(lines(out, "retreat")[1], "cost")), field(lines(out, "retreat")[1], "anchor")
	end
	local plain, a1 = edgeCost(nil)
	local held, a2 = edgeCost({ [3] = { name = "item_tango" } })
	check("regen credit: a held tango does not cheapen the enemy tower's edge", a1 == "tower_edge" and a2 == "tower_edge" and plain == held, tostring(plain) .. " " .. tostring(held))
end

-- The tower's damage flag lasts 0.5 s past the hit: a hero already out of the reach (an episode just ended at its edge) does
-- not start another on the flag alone; inside the reach it does (drills rtwalk2, rtchase2: episodes chained every 0.3 s).
do
	local H, bot = world({ loc = Vector(2800 - 844 - 150, -5000) })
	bot.towerHitAt = T
	capture(function() check("tower flag: out of the reach, no new episode", H.Retreat.Desire(bot) == 0) end)
	TOWERS_W[3][dota.Tower.Bot1].target = bot
	capture(function() check("tower target: still targeted out of the reach, no new episode", H.Retreat.Desire(bot) == 0) end)
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

-- HealStop (D3): HP back over half on the walk, nobody in reach, the lane front nearer than the fountain: the walk stops
-- there. Short of half, or with the fountain nearer, or with the switch off, it walks on.
do
	local function healWalk(o)
		local H, bot = world({ hp = 150 })
		package.loaded["bots/FunLib/custom_loader"].Ours.HealStop = o.on
		local out = capture(function()
			check("heal stop: leaves under the floor", H.Retreat.Desire(bot) == 0.95)
			bot.loc = o.loc
			bot.hp = 290
			T = T + 5
			check("heal stop: under half the walk goes on", H.Retreat.Desire(bot) == 0.95)
			bot.hp = 330
			T = T + 1
			o.after = H.Retreat.Desire(bot)
		end)
		package.loaded["bots/FunLib/custom_loader"].Ours.HealStop = nil
		return o.after, lines(out, "retreat")
	end
	local d, l = healWalk({ on = true, loc = Vector(-1500, -5000) })
	check("heal stop: back over half nearer the lane, the episode ends healed", d == 0 and field(l[2], "res") == "healed", l[2])
	d = healWalk({ on = true, loc = Vector(-6000, -6000) })
	check("heal stop: nearer the fountain it walks on", d == 0.95)
	d = healWalk({ on = false, loc = Vector(-1500, -5000) })
	check("heal stop: off, it walks on to the fountain", d == 0.95)
	local H, bot = world({ hp = 150 })
	capture(function()
		H.Retreat.Desire(bot)
		bot.loc, bot.hp = Vector(-1500, -5000), 330
		enemy(10, Vector(-1300, -5000), 50)
		T = T + 1
		check("heal stop: an enemy in reach keeps the walk going", H.Retreat.Desire(bot) == 0.95)
	end)
end

-- retreat-heal's harness: in a chase rep the cast's retreat starts nothing above the drill's 25% HP (a lethal read
-- included), and once it has been there it leaves as usual for the rest of the rep; a control rep is not held.
do
	local H, bot = world({ hp = 300, t = 70 })
	package.loaded["bots/FunLib/custom_loader"].Overrides = { Drill = "retreat-heal" }
	H.Drill.ResetCache()
	enemy(10, Vector(300, -5000), 400)
	enemy(11, Vector(300, -4900), 400)
	capture(function()
		check("heal drill: the cast is the cast", H.Drill.RoleOf(bot) == "cast", H.Drill.RoleOf(bot))
		check("heal drill: held above the break", H.Retreat.Desire(bot) == 0)
		bot.hp = 140
		T = T + 0.2
		check("heal drill: at the break it leaves", H.Retreat.Desire(bot) == 0.95)
	end)
	local H2, bot2 = world({ hp = 300, t = 60 + 3 * 90 + 10 })
	H2.Drill.ResetCache()
	enemy(10, Vector(300, -5000), 400)
	enemy(11, Vector(300, -4900), 400)
	capture(function() check("heal drill: a control rep is not held", H2.Retreat.Desire(bot2) == 0.95) end)
	package.loaded["bots/FunLib/custom_loader"].Overrides = nil
	H2.Drill.ResetCache()
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

-- Route price (user 10/11/2026): the walk costs its seconds (SecsPerCost), and a healing item held takes RegenCredit off a tower
-- anchor, so the same walk that ends at an ally anchor with empty pockets ends at our tower with a tango held; the choice
-- logs the exposed points, the least on any anchor and whether regen was held.
do
	local function pick(items)
		local H, bot = world({ loc = Vector(-1500, -5000), hp = 150 })
		bot.items = items
		local ally = MakeUnit({ pid = 2, team = 2, loc = Vector(-2000, -5000) })
		ally.maxhp, ally.hp = 600, 600
		enemy(10, Vector(-900, -5000), 400)
		local out = capture(function()
			H.Retreat.Desire(bot)
			T = T + 1
			H.Retreat.Desire(bot)
		end)
		return lines(out, "retreat")[1]
	end
	local none = pick(nil)
	check("regen: empty pockets, the nearer ally anchor wins", field(none, "anchor") == "ally" and field(none, "regen") == "0", none)
	local held = pick({ [3] = { name = "item_tango" } })
	check("regen: a tango held, the tower anchor wins and the log says so", field(held, "anchor") == "tower" and field(held, "regen") == "1", held)
	check("regen: the exposure and the least exposure are logged", field(held, "exp") ~= nil and field(held, "minexp") ~= nil, held)
	local backpack = pick({ [7] = { name = "item_tango" } })
	check("regen: a tango in the backpack counts for nothing", field(backpack, "anchor") == "ally" and field(backpack, "regen") == "0", backpack)
end

-- The exit band: with a hero still in reach, the episode ends `safe` only once threat stays under budget - 0.15 for 1.5 s; a
-- spike in the dwell restarts it. One harmless hero in reach reads 0.25, under the free band 0.35.
do
	local H, bot = world()
	local e1 = enemy(10, Vector(300, -5000), 100)
	local e2 = enemy(11, Vector(300, -4900), 100)
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + 2
		H.Retreat.Desire(bot)
		e1.estDamage, e2.alive = 0, false
		T = T + 1
		check("exit: under the band with one in reach, still in the dwell", H.Retreat.Desire(bot) == 0.95)
		e1.estDamage, e2.alive = 100, true
		T = T + 0.2
		H.Retreat.Desire(bot)
		e1.estDamage, e2.alive = 0, false
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

-- D2: once no enemy hero can reach us the episode ends on that read (res=gone), with no dwell and short of its anchor.
do
	local H, bot = world()
	local e1 = enemy(10, Vector(300, -5000), 100)
	local e2 = enemy(11, Vector(300, -4900), 100)
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + 2
		check("gone: in the episode while both are in reach", H.Retreat.Desire(bot) == 0.95)
		e1.loc, e2.loc = Vector(3000, -5000), Vector(3000, -4900)
		T = T + 0.2
		check("gone: ends on the first read with nobody in reach", H.Retreat.Desire(bot) == 0)
	end)
	local l = lines(out, "retreat")
	check("gone: res=gone, not at its anchor", field(l[#l], "res") == "gone" and field(l[#l], "anchor") ~= "fountain", l[#l])
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

-- Slice even-fight (D24, D1): two heroes in reach with the lane partner beside us read 0.67 - 0.15 = 0.52, over the free
-- budget, yet they do not outnumber us; RetreatOdds keeps the hero in lane and logs the hold once. Off, the same read leaves.
do
	local function evenFight(est, odds)
		local H, bot = world()
		package.loaded["bots/FunLib/custom_loader"].Ours.RetreatOdds = odds
		local ally = MakeUnit({ pid = 2, team = 2, loc = Vector(-100, -5000) })
		ally.maxhp, ally.hp = 600, 600
		enemy(10, Vector(300, -5000), est)
		enemy(11, Vector(300, -4900), est)
		local out = capture(function()
			for _ = 1, 4 do
				H.Retreat.Desire(bot)
				T = T + react(bot)
			end
		end)
		local stays = {}
		for _, l in ipairs(out) do if l:find("ev=retreat ph=stay ", 1, true) then stays[#stays + 1] = l end end
		return H.Retreat.Running(bot), lines(out, "retreat"), stays
	end
	local on, _, stays = evenFight(100, true)
	check("odds: an even 2v2 over budget starts no episode", not on)
	check("odds: the hold is logged once per over-budget spell, with the allies counted", #stays == 1 and field(stays[1], "al") == "1" and field(stays[1], "reach") == "2", #stays)
	local offOn, offLines = evenFight(100, false)
	check("odds off: the same read leaves why=threat (the path replaced)", offOn and field(offLines[1], "why") == "threat", offLines[1])
	local lethalOn, lethalLines = evenFight(300, true)
	check("odds: an even 2v2 whose burst kills us still leaves why=lethal", lethalOn and field(lethalLines[1], "why") == "lethal", lethalLines[1])
end

-- Even-fight round 2 (D24): the hold stands only while the heroes hitting us pay for it in creep aggro (our lane creeps within
-- 500 of them). Hitting us from outside it, the same even 2v2 is left on `threat`, as with the switch off.
do
	local function hitFrom(creepX)
		local H, bot = world()
		package.loaded["bots/FunLib/custom_loader"].Ours.RetreatOdds = true
		local ally = MakeUnit({ pid = 2, team = 2, loc = Vector(-100, -5000) })
		ally.maxhp, ally.hp = 600, 600
		local e1, e2 = enemy(10, Vector(300, -5000), 100), enemy(11, Vector(300, -4900), 100)
		MakeCreep({ team = 2, x = creepX, y = -5000 })
		local out = capture(function()
			for _ = 1, 4 do
				bot.hitBy = { [e1] = T - 0.2, [e2] = T - 0.2 }
				H.Retreat.Desire(bot)
				T = T + react(bot)
			end
		end)
		return H.Retreat.Running(bot), lines(out, "retreat")
	end
	local paidOn = hitFrom(150)
	check("aggro: two heroes hitting us beside our creeps are held (they pay in creep damage)", not paidOn)
	local freeOn, freeLines = hitFrom(-1200)
	check("aggro: the same two hitting us with no creep of ours within 500 leave why=threat, logged unp=2",
		freeOn and field(freeLines[1], "why") == "threat" and field(freeLines[1], "unp") == "2", freeLines[1])
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

-- MaxSecs is the backstop: an episode whose danger never clears is cut after 40 s, so the gate cannot hold other modes forever.
do
	local H, bot = world({ hp = 200 })
	enemy(10, Vector(300, -5000), 250)
	local out = capture(function()
		H.Retreat.Desire(bot)
		T = T + 30
		H.Retreat.Desire(bot)
		T = T + 11
		H.Retreat.Desire(bot)
	end)
	local l = lines(out, "retreat")
	local ends = {}
	for _, x in ipairs(l) do if field(x, "ph") == "end" then ends[#ends + 1] = x end end
	check("max secs: still running at 30 s, cut after 40", #ends >= 1 and field(ends[1], "res") == "cut" and tonumber(field(ends[1], "secs")) > 40, ends[1])
end

-- The OFF arm leaves OHA's desire (the nudges' own arms: test_transitions_caution "retreat on").
do
	local H2, bot2 = world({ off = true })
	check("off: Desire leaves OHA's (nil)", H2.Retreat.Desire(bot2) == nil and not H2.Retreat.Owns(bot2))
end

-- The plain walk for a hero we do not own goes to the fountain at any HP, as Valve's walk does: OHA's retreat for mana near
-- base holds until mana refills, which a tower stand point never gives (review of 1eacd10e).
do
	local H, bot = world({ off = true })
	package.loaded["bots/FunLib/custom_loader"].Ours.Retreat = true
	LANING = false
	H.Retreat.ResetCache()
	capture(function() H.Retreat.Think(bot) end)
	local m = ACTIONS[#ACTIONS] and ACTIONS[#ACTIONS].args[1]
	check("plain: an unowned hero at full HP walks to the fountain, not our T1", m ~= nil and m.x < -6000, m and m.x)
end

finish()
