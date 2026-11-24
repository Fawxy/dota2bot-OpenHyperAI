dofile(HARNESS_DIR .. "/lane_world.lua")
-- Lane hits (lane_hits.ts) and its check probe (lane_hits_probe.ts). The engine's hpForecast is stubbed (its own tests
-- cover it), so these cover who reads each creep, the per-frame cache, the hero hits and the probe's line.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

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

-- w.hits[creep]: the forecast's hits for that creep; w.calls: hpForecast calls; w.readers: the bot each was read from.
local function world(o)
	o = o or {}
	LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Overrides = { LaneReadProbe = o.probe == true }
	CURRENT_TEAM = 2
	T = 100
	local w = { hits = {}, hp = {}, calls = 0, readers = {} }
	local F = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
	F.Verbs = function()
		return {
			hpForecast = function(bot, creep, horizon)
				w.calls = w.calls + 1
				table.insert(w.readers, bot)
				local hs = w.hits[creep] or {}
				if type(hs) == "function" then hs = hs(bot) end
				local copy = {}
				for i, x in ipairs(hs) do copy[i] = x end
				return { hp = creep.hp, regen = 0, horizon = horizon, hits = copy, unphased = 0, unphasedTower = false, unphasedHits = {} }
			end,
			forecastHp = function(f, t)
				local hp = f.hp
				for _, h in ipairs(f.hits) do if h.t <= t then hp = hp - h.damage end end
				return hp
			end,
		}
	end
	local LH = require("bots/FunLib/humaniser/lane_hits")
	LH.Reset()
	w.LH = LH
	return w
end

local function hero(pid, team, x, y)
	local h = MakeUnit({ pid = pid, team = team, bot = true, loc = Vector(x, y), hp = 600, maxhp = 600 })
	h.lh, h.dn = 0, 0
	h.GetLastHits = function(self) return self.lh end
	h.GetDenies = function(self) return self.dn end
	h.GetAttackTarget = function(self) return self.atk end
	return h
end

do -- rows: own and enemy lane creeps with a reader in range; the nearest hero reads; one build per frame
	local w = world()
	local sup = hero(5, 2, 0, -5000)
	local core = hero(6, 2, 500, -5000)
	local own = MakeCreep({ team = 2, x = 450, y = -5000, hp = 40 })
	local foe = MakeCreep({ team = 3, x = 100, y = -5000, hp = 90 })
	MakeCreep({ team = 2, x = 6000, y = -5000, hp = 300 }) -- no hero within 1600
	local enemy = hero(7, 3, 200, -4900)
	w.hits[own] = {
		{ t = 0.3, damage = 45, by = "hero", attacker = core, commit = 0.3 },
		{ t = 0.5, damage = 20, by = "creep", attacker = foe, commit = 0.5 },
		{ t = 0.6, damage = 50, by = "hero", attacker = enemy, commit = 0.2 },
	}
	local rows = w.LH.Read(2, Lane.Bot)
	check("rows: the two creeps with a hero in range, own first", #rows == 2 and rows[1].creep == own and rows[1].own == true
		and rows[2].creep == foe and rows[2].own == false, #rows)
	check("rows: the nearest hero reads each creep", rows[1].reader == 6 and rows[2].reader == 5, tostring(rows[1].reader) .. " " .. tostring(rows[2].reader))
	local hs = rows[1].heroes
	check("hero hits: our core's and the enemy's, creeps left out, by pid and side", #hs == 2 and hs[1].pid == 6 and hs[1].ours == true
		and hs[1].commit == 0.3 and hs[2].pid == 7 and hs[2].ours == false, #hs)
	local calls = w.calls
	w.LH.Read(2, Lane.Bot)
	check("cache: a second read in the frame forecasts nothing more", w.calls == calls, w.calls)
	T = 100.1
	w.LH.Read(2, Lane.Bot)
	check("cache: the next frame reads again", w.calls == calls + 2, w.calls)
	local k = w.LH.KillingHit(rows[1])
	check("killing hit: the first that takes the HP to 0 (the core's 45 on 40)", k ~= nil and k.attacker == core, k and k.t)
	check("killing hit: none when nothing kills", w.LH.KillingHit(rows[2]) == nil)
	check("of: finds a creep's row", w.LH.Of(2, Lane.Bot, foe) ~= nil and w.LH.Of(2, Lane.Mid, foe) == nil)
end

do -- reader: a hero attacking the creep does not read it (its own wind-up is not in its read); all attacking: the next fills it in
	local w = world()
	local core = hero(6, 2, 400, -5000)
	local sup = hero(5, 2, 0, -5000)
	local own = MakeCreep({ team = 2, x = 450, y = -5000, hp = 40 })
	local swing = { t = 0.2, damage = 45, by = "hero", attacker = core, commit = 0.2 }
	local enemy = hero(7, 3, 200, -4900)
	local theirs = { t = 0.5, damage = 50, by = "hero", attacker = enemy, commit = 0.1 }
	-- The engine leaves the reader's own wind-up out of its read.
	w.hits[own] = function(bot) if bot == core then return { theirs } end return { swing, theirs } end
	core.atk = own
	local r = w.LH.Read(2, Lane.Bot)[1]
	check("reader: the core attacking the creep does not read it; the support does, and sees the core's swing",
		r.reader == 5 and #r.heroes == 2 and r.heroes[1].pid == 6, tostring(r.reader) .. " " .. #r.heroes)
	sup.atk = own
	T = 100.1
	local selfFlight = { t = 0.3, damage = 30, by = "self", attacker = core, commit = 0 }
	w.hits[own] = function(bot)
		if bot == core then return { selfFlight, theirs } end
		return { swing, { t = 0.3, damage = 30, by = "hero", attacker = core, commit = 0 }, theirs }
	end
	r = w.LH.Read(2, Lane.Bot)[1]
	check("all attacking: the nearest reads, its own hits from the next one's read, once each, by time",
		r.reader == 6 and #r.heroes == 3 and r.heroes[1].t == 0.2 and r.heroes[2].t == 0.3 and r.heroes[3].pid == 7,
		tostring(r.reader) .. " " .. #r.heroes)
end

do -- the probe: a creep that dies leaves one line, its last prediction beside the denier whose count rose that frame
	local w = world({ probe = true })
	local sup = hero(5, 2, 0, -5000)
	local core = hero(6, 2, 500, -5000)
	local own = MakeCreep({ team = 2, x = 450, y = -5000, hp = 40 })
	w.hits[own] = { { t = 0.2, damage = 45, by = "hero", attacker = core, commit = 0.1 } }
	local P = require("bots/FunLib/humaniser/lane_hits_probe")
	P.ResetCache()
	local out = capture(function()
		T = 200 P.Tick(sup)
		T = 200.1 P.Tick(sup)
		own.hp = 0
		CREEPS[2] = {}
		core.dn = 1
		T = 200.2 P.Tick(sup)
	end)
	local l = lines(out, "ev=lane_hits_check")
	check("probe: one line for the dead creep", #l == 1, table.concat(out, " | "))
	check("probe: predicted the core (hero, pid 6), the core's deny rose, own, dead", field(l[1], "pby") == "hero" and field(l[1], "ppid") == "6"
		and field(l[1], "rose") == "6" and field(l[1], "own") == "1" and field(l[1], "end") == "dead", l[1])
	package.loaded["bots/FunLib/custom_loader"].Overrides = {}
	local out2 = capture(function() T = 300 P.Tick(sup) T = 300.1 P.Tick(sup) end)
	check("probe off: nothing logged", #lines(out2, "ev=lane_hits_check") == 0)
end

finish()
