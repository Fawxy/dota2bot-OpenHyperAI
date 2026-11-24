dofile(HARNESS_DIR .. "/lane_world.lua")
-- The swing probe (swing_probe.ts, Overrides.SwingProbe): one record per own hero's wind-up on a lane creep, followed to the
-- fire and landing the game reports. Units here are plain tables with the reads the probe takes.

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function lines(all, pat)
	local r = {}
	for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(r, l) end end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end
local function num(line, k) return tonumber(field(line, k)) end

local function creep(o)
	local c = { hp = o.hp or 100, team = o.team or 2, alive = true, loc = o.loc or Vector(0, 0), proj = {} }
	function c:IsNull() return false end
	function c:IsAlive() return self.alive end
	function c:IsCreep() return true end
	function c:GetTeam() return self.team end
	function c:GetUnitName() return self.team == 2 and "npc_dota_creep_goodguys_melee" or "npc_dota_creep_badguys_melee" end
	function c:GetHealth() return self.hp end
	function c:GetLocation() return self.loc end
	function c:GetActualIncomingDamage(d) return d * 0.8 end
	function c:GetIncomingTrackingProjectiles() return self.proj end
	return c
end

local function hero(o)
	local h = { pid = o.pid, act = 0, cyc = 0, pt = o.pt or 0.4, spa = o.spa or 1.5, range = o.range or 150, pspeed = o.pspeed or 0,
		dmg = 50, lat = -100, lh = 0, dn = 0, loc = o.loc or Vector(0, 0), target = nil }
	function h:IsNull() return false end
	function h:IsAlive() return true end
	function h:IsIllusion() return false end
	function h:IsHero() return true end
	function h:GetTeam() return 2 end
	function h:GetPlayerID() return self.pid end
	function h:GetLocation() return self.loc end
	function h:GetAttackTarget() return self.target end
	function h:GetAnimActivity() return self.act end
	function h:GetAnimCycle() return self.cyc end
	function h:GetAttackPoint() return self.pt end
	function h:GetSecondsPerAttack() return self.spa end
	function h:GetAttackSpeed() return self.aspd or 1 end
	function h:GetAttackRange() return self.range end
	function h:GetAttackProjectileSpeed() return self.pspeed end
	function h:GetAttackDamage() return self.dmg end
	function h:GetLastAttackTime() return self.lat end
	function h:GetLastHits() return self.lh end
	function h:GetDenies() return self.dn end
	return h
end

local function world(heroes)
	LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Overrides = { SwingProbe = true }
	CURRENT_TEAM = 2
	UNITS[2] = heroes
	local P = require("bots/FunLib/humaniser/swing_probe")
	P.ResetCache()
	return P
end

local function frame(P, bot, t) T = t P.Tick(bot) end

do -- melee: seen at cycle 0.1 of a 0.4 point at 1.5 s an attack, so the fire is predicted 0.45 s on; it fires and kills
	local c = creep({ hp = 60 })
	local h = hero({ pid = 1 })
	local P = world({ h })
	local out = capture(function()
		frame(P, h, 100)
		h.target, h.act, h.cyc = c, 1503, 0.1
		frame(P, h, 100.1)
		h.cyc = 0.2
		frame(P, h, 100.3)
		h.lat, c.hp, c.alive, h.dn = 100.55, 0, false, 1
		frame(P, h, 100.6)
		frame(P, h, 100.7)
	end)
	local l = lines(out, "ev=swing_probe")
	check("melee: one line", #l == 1, table.concat(out, " | "))
	check("melee: predicted fire 0.45 s, seen fire 0.45 s, landed on the fire frame (0.5)", near(num(l[1], "pf"), 0.45)
		and near(num(l[1], "pl"), 0.45) and near(num(l[1], "fire"), 0.45) and near(num(l[1], "land"), 0.5), l[1])
	check("melee: own creep, same target, the drop the whole HP, kill 1, end land", field(l[1], "own") == "1" and field(l[1], "same") == "1"
		and num(l[1], "drop") == 60 and field(l[1], "kill") == "1" and field(l[1], "end") == "land" and num(l[1], "dmg") == 40, l[1])
	check("melee: the cycle on every live frame before the fire (wc)", field(l[1], "wc") == "0:0.100;0.200:0.200", l[1])
end

do -- ranged: the projectile is seen, then gone: the landing is the frame it went
	local c = creep({ hp = 300, team = 3, loc = Vector(522, 0) })
	local h = hero({ pid = 2, range = 600, pspeed = 1000 })
	local P = world({ h })
	local out = capture(function()
		h.target, h.act, h.cyc = c, 1504, 0.2
		frame(P, h, 200)
		h.lat = 200.3
		frame(P, h, 200.3)
		c.proj = { { caster = h, is_attack = true, location = Vector(222, 0) } }
		frame(P, h, 200.5)
		c.proj, c.hp = {}, 260
		frame(P, h, 200.8)
		frame(P, h, 200.9)
		frame(P, h, 201.0)
	end)
	local l = lines(out, "ev=swing_probe")
	check("ranged: one line, flight 0.5 s added to the 0.3 s fire", #l == 1 and near(num(l[1], "pf"), 0.3) and near(num(l[1], "pl"), 0.8), l[1])
	check("ranged: projectile seen, landing at 0.8, drop 40, enemy creep, no kill", field(l[1], "proj") == "1" and near(num(l[1], "land"), 0.8)
		and num(l[1], "drop") == 40 and field(l[1], "own") == "0" and field(l[1], "kill") == "0", l[1])
	check("ranged: pl3 from the projectile's position (0.5 + 300/1000), drop2 the two frames, age 0.9 (the second absent frame)", near(num(l[1], "pl3"), 0.8)
		and num(l[1], "drop2") == 40 and near(num(l[1], "age"), 0.9) and field(l[1], "pres") == "100" and num(l[1], "big") == 40, l[1])
end

do -- a wind-up that stops unfired ends cancel; a switch-off probe logs nothing
	local c = creep({})
	local h = hero({ pid = 3 })
	local P = world({ h })
	local out = capture(function()
		h.target, h.act, h.cyc = c, 1503, 0.1
		frame(P, h, 300)
		h.act = 0
		frame(P, h, 300.1)
		frame(P, h, 300.2)
	end)
	local l = lines(out, "ev=swing_probe")
	check("cancel: one line end=cancel, fire -1", #l == 1 and field(l[1], "end") == "cancel" and num(l[1], "fire") == -1, table.concat(l, " | "))
	package.loaded["bots/FunLib/custom_loader"].Overrides = {}
	h.act, h.cyc = 1503, 0.1
	local out2 = capture(function() frame(P, h, 400) frame(P, h, 400.1) h.act = 0 frame(P, h, 400.2) frame(P, h, 400.3) end)
	check("off: nothing logged", #lines(out2, "ev=swing_probe") == 0, table.concat(out2, " | "))
end

finish()
