dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice retreat (master docs/team/slices/retreat.md): our retreat for a laning hero. The leave rule (Safe.At at the hero's own place:
-- deadly leaves at once, a hit back or join holds it down to Safe.BARS.hold; a tower on us and the heal floor at once), the anchor by
-- route cost, the stop on a fresh place (Safe.BARS.stay x 1.15) or nobody in reach, an ally in retreat counting no help, the areas'
-- retreat nudges off for an owned hero, and the OFF arm. HP 600 unless set: a kill line of 600 is ratio 1.0, 460 is 1.3, 400 is 1.5.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

-- The Radiant bot lane: our T1 at x = -2,800, theirs at x = 2,800 (reach 844).
local HERE = Vector(0, -5000)

local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = o.telemetry or { Enable = true }, retreat = o.off ~= true })
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
	for _, l in ipairs(all) do
		local ph = l:match(" ph=(%S+)")
		if l:find("ev=" .. ev .. " ", 1, true) and ph ~= "read" then r[#r + 1] = l end
	end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local function react(bot)
	return require("bots/FunLib/humaniser/profile").ThreatHold(bot)
end

local function noHold() require("bots/FunLib/humaniser/states/trade").Holds = function() return nil end end
local function running(bot) return require("bots/FunLib/humaniser/retreat_state").Running(bot) end

-- A deadly place is left at once, with no reaction time: two heroes in reach with 300 damage each against 600 HP are ratio 1.0, under
-- the held bar 1.25. Controls: the same two with 100 each (ratio 3, what the head count used to leave) stay; ratio 1.3 stays at a place
-- the hero holds; ratio 1.2 leaves.
do
	local function two(est)
		local H, bot = world()
		noHold()
		enemy(10, Vector(300, -5000), est)
		enemy(11, Vector(300, -4900), est)
		local out = capture(function() H.Retreat.Desire(bot) end)
		return bot, out
	end
	local bot, out = two(300)
	local reads, s = {}, lines(out, "retreat")[1]
	for _, l in ipairs(out) do if l:find("ev=retreat ph=read ", 1, true) then reads[#reads + 1] = l end end
	check("leave: the episode on the first deadly read, no wait", running(bot) and field(s, "why") == "threat", s)
	check("leave: ev=retreat start carries the answer (deadly, ratio 1, kill 600) and the purpose", field(s, "lv") == "deadly" and tonumber(field(s, "ra")) == 1 and tonumber(field(s, "kill")) == 600 and field(s, "purp") == "free", s)
	check("leave: one ph=read line per band change, not per think", #reads == 1, #reads)
	check("stay: two heroes in reach with 100 damage each are no reason to leave (ratio 3)", not running((two(100))))
	check("stay: ratio 1.3 is kept at a place the hero holds (bar 1.25)", not running((two(230))))
	check("leave: ratio 1.2 is not", running((two(250))))
end

-- The Oracle stand case (h2hsnapcreeps1_B_dire_2 t=396: one hero, kill line just over HP, ratio about 1.03): left at once, where the
-- old stand (burst under HP) stayed. Control: half the damage stays.
do
	local function lone(est)
		local H, bot = world()
		noHold()
		enemy(10, Vector(300, -5000), est)
		local out = capture(function() H.Retreat.Desire(bot) end)
		return bot, lines(out, "retreat")[1]
	end
	local bot, s = lone(583)
	check("oracle: a lone hero with a kill line of 583 over 600 HP (ratio 1.03) is left, why=threat", running(bot) and field(s, "why") == "threat", s)
	check("oracle control: half the damage stays", not running((lone(290))))
end

-- An engaged hero (it hit us within a second) is counted over EngagedWindow (6 s): 30 a second is 180 against 60 when it is not
-- hitting. At 200 HP that is ratio 1.1 against 3.3, and at 600 HP 3.3 either way.
do
	local function engagedWorld(hp, engaged)
		local H, bot = world({ hp = hp })
		noHold()
		local e = enemy(10, Vector(300, -5000), 0)
		e.GetEstimatedDamageToTarget = function(_, _, _, dur) return 30 * dur end
		local function hit() if engaged then bot.hitBy = { [e] = T - 0.2 } end end
		hit()
		return H, bot, hit
	end
	local function leaves(hp, engaged)
		local H, bot = engagedWorld(hp, engaged)
		local out = capture(function() H.Retreat.Desire(bot) end)
		return running(bot), lines(out, "retreat")[1]
	end
	local on, s = leaves(200, true)
	check("engaged: a melee hero hitting us at 33% HP starts a retreat why=threat", on and field(s, "why") == "threat", s)
	check("engaged: the same hero not hitting us starts none (2 s window)", not leaves(200, false))
	check("engaged: at full HP the hitting hero starts none (a lone harasser is not run from)", not leaves(600, true))
	local H, bot, hit = engagedWorld(200, true)
	local out = capture(function()
		H.Retreat.Desire(bot)
		for _ = 1, 5 do T = T + 1 hit() H.Retreat.Desire(bot) end
	end)
	check("engaged: the episode does not end safe while he still hits us", running(bot) and #lines(out, "retreat") == 1, #lines(out, "retreat"))
end

-- The hit back (D24) and the join (D10) hold a deadly place down to Safe.BARS.hold (ratio 1.0): Trade.Holds is asked only when the
-- answer is deadly by the kill line and not under that; under it the hero leaves `lethal` whatever Holds says.
do
	local asked = 0
	local function run(holds, est)
		local H, bot = world({ hp = 540 })
		enemy(10, Vector(300, -5000), est)
		enemy(11, Vector(300, -4900), est)
		asked = 0
		require("bots/FunLib/humaniser/states/trade").Holds = function() asked = asked + 1 return holds end
		local out = capture(function() H.Retreat.Desire(bot) T = T + 0.2 H.Retreat.Desire(bot) end)
		return running(bot), out
	end
	local on, out = run("hitback", 250)
	local stay
	for _, l in ipairs(out) do if l:find("ph=stay", 1, true) then stay = l end end
	check("hit back: ratio 1.08 with the hit back holding, no leave", not on and asked > 0, tostring(on) .. " asked=" .. asked)
	check("hit back: one ph=stay why=hitback line, with the answer", stay ~= nil and field(stay, "why") == "hitback" and field(stay, "lv") == "deadly", stay)
	check("hit back: the same read with no hit back holding leaves", (run(nil, 250)))
	run("hitback", 100)
	check("hit back: not asked while the place is not deadly (ratio 2.7)", asked == 0)
	local lethalOn, lethalOut = run("hitback", 2000)
	check("hit back: ratio under 1.0 leaves lethal and never asks", lethalOn and asked == 0 and field(lines(lethalOut, "retreat")[1], "why") == "lethal", asked)
	local joinOn, joinOut = run("join", 250)
	local joinStay
	for _, l in ipairs(joinOut) do if l:find("ph=stay", 1, true) then joinStay = l end end
	check("join hold: no leave, one ph=stay why=join line", not joinOn and joinStay ~= nil and field(joinStay, "why") == "join", joinStay)
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

-- A hero that cannot reach the fountain point (patch 7.42, Dire) has arrived once the fountain's buff is on it.
do
	local H, bot = world({ hp = 150 })
	local out = capture(function()
		H.Retreat.Desire(bot)
		local f = H.Retreat.Fountain(2)
		bot.loc = Vector(f.x + 300, f.y, f.z)
		bot.hp = 500
		T = T + 5
		check("heal: healed 300 short of the fountain point without its buff, the episode holds", H.Retreat.Desire(bot) == 0.95)
		bot.modifiers["modifier_fountain_aura_buff"] = true
		T = T + 1
		check("heal: with the fountain's buff it ends", H.Retreat.Desire(bot) == 0)
	end)
	local l = lines(out, "retreat")
	check("heal: the buff end is res=anchor", field(l[2], "res") == "anchor", l[2])
end

-- Sustain's rule 2 (design 2026-11-19-sustain-design.md step 4): for a hero sustain carries, its home answer is the heal leave,
-- where the place is not deadly; its "stay" keeps a hero under the heal floor in lane (its items reach the line). A stale answer,
-- or none, falls back to the heal floor. The walk home marks the hero healing (sustain spends nothing meanwhile).
do
	local RS
	local r = {}
	local H, bot = world({ hp = 400 })
	RS = require("bots/FunLib/humaniser/retreat_state")
	capture(function()
		RS.SetHome(bot, true)
		r.d1, r.h1 = H.Retreat.Desire(bot), RS.Healing(bot)
		bot.loc, bot.hp = H.Retreat.Fountain(2), 500
		T = T + 5
		r.d2, r.h2 = H.Retreat.Desire(bot), RS.Healing(bot)
	end)
	check("sustain home: leaves at 400 HP with nobody in reach, healing", r.d1 == 0.95 and r.h1, tostring(r.d1))
	check("sustain home: ends at the fountain at 0.8, healing cleared", r.d2 == 0 and not r.h2, tostring(r.d2))
	H, bot = world({ hp = 150 })
	RS = require("bots/FunLib/humaniser/retreat_state")
	capture(function()
		RS.SetHome(bot, false)
		r.d3 = H.Retreat.Desire(bot)
		T = T + RS.HOME_FRESH + 1
		r.d4 = H.Retreat.Desire(bot)
	end)
	check("sustain stay: under the floor, items reach the line: no leave", r.d3 == 0, tostring(r.d3))
	check("sustain stale: the heal floor decides again", r.d4 == 0.95, tostring(r.d4))
	H, bot = world({ hp = 150 })
	RS = require("bots/FunLib/humaniser/retreat_state")
	capture(function()
		RS.SetHome(bot, nil)
		r.d5 = H.Retreat.Desire(bot)
	end)
	check("sustain not carrying: the heal floor", r.d5 == 0.95, tostring(r.d5))
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

-- The stop is the fresh bar (Safe.BARS.stay x 1.15 = 1.4375): with a hero still in reach the episode ends `safe` only at a place
-- the hero would not leave again. Ratio 1.3 is a place to stay in but not to stop at; 1.5 stops it. The same ratio 1.3 starts no
-- episode in the first place (the leave test above), so the two bars differ.
do
	local H, bot = world()
	noHold()
	local e1 = enemy(10, Vector(300, -5000), 300)
	local e2 = enemy(11, Vector(300, -4900), 300)
	local out = capture(function()
		check("exit: the deadly read starts the episode", H.Retreat.Desire(bot) == 0.95)
		e1.estDamage, e2.estDamage = 230, 230
		T = T + 0.2
		check("exit: ratio 1.3 does not end it (fresh bar 1.44)", H.Retreat.Desire(bot) == 0.95)
		T = T + 3
		check("exit: still going after seconds at ratio 1.3, no dwell timer decides", H.Retreat.Desire(bot) == 0.95)
		e1.estDamage, e2.estDamage = 200, 200
		T = T + 0.2
		check("exit: ratio 1.5 ends it", H.Retreat.Desire(bot) == 0)
	end)
	local l = lines(out, "retreat")
	check("exit: res=safe", field(l[#l], "res") == "safe", l[#l])
end

-- D2: once no enemy hero can reach us the episode ends on that read (res=gone), short of its anchor. Control: both in reach keep it.
do
	local H, bot = world()
	noHold()
	local e1 = enemy(10, Vector(300, -5000), 300)
	local e2 = enemy(11, Vector(300, -4900), 300)
	local out = capture(function()
		check("gone: the episode starts", H.Retreat.Desire(bot) == 0.95)
		T = T + 0.2
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

-- ev=cut kind=leave (fixture cuts): a line when the answer changes and, while a hero is in reach, every CutEvery; the decisions are
-- the same with the cut off (it only reads).
do
	local function run(cut, est)
		local H, bot = world({ telemetry = { Enable = true, Cut = cut } })
		noHold()
		enemy(10, Vector(300, -5000), est)
		enemy(11, Vector(300, -4900), est)
		local desires = {}
		local out = capture(function()
			for _ = 1, 12 do
				desires[#desires + 1] = H.Retreat.Desire(bot)
				T = T + 0.2
			end
		end)
		local cuts = {}
		for _, l in ipairs(out) do if l:find("ev=cut ", 1, true) and l:find("kind=leave", 1, true) then cuts[#cuts + 1] = l end end
		return desires, cuts
	end
	local on, cuts = run(true, 300)
	local off, none = run(false, 300)
	check("cut: the desires are the same with the cut off", table.concat(on, ",") == table.concat(off, ","), table.concat(on, ",") .. " / " .. table.concat(off, ","))
	check("cut: no line with the cut off", #none == 0, #none)
	check("cut: the leave is logged once (the episode ends the reads)", #cuts == 1 and field(cuts[1], "dec") == "threat", #cuts)
	check("cut: the line carries the answer the rule read", field(cuts[1], "lv") == "deadly" and field(cuts[1], "why") == "kill" and tonumber(field(cuts[1], "kill")) == 600 and tonumber(field(cuts[1], "ra")) == 1 and field(cuts[1], "purp") == "free", cuts[1])
	local _, calm = run(true, 100)
	check("cut: a place that is not deadly is logged as under", #calm >= 1 and field(calm[1], "dec") == "under" and field(calm[1], "lv") == "safe", calm[1])
end

-- While no episode runs and a hero stays in reach under budget, the samples are CutEvery apart, not per read.
do
	local H, bot = world()
	enemy(10, Vector(300, -5000), 60)
	local out = capture(function()
		for _ = 1, 50 do
			H.Retreat.Desire(bot)
			T = T + 0.2
		end
	end)
	local n, first = 0, nil
	for _, l in ipairs(out) do if l:find("ev=cut ", 1, true) and l:find("kind=leave", 1, true) then n = n + 1; first = first or l end end
	-- 10 s of reads: the first (answer new), then one per 2 s.
	check("cut: a hero in reach under budget is sampled every CutEvery, not per read", n == 5 or n == 6, n)
	check("cut: the stay's reason is logged", field(first, "dec") == "under", first)
end

finish()
