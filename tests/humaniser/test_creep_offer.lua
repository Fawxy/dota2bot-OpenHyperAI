dofile(HARNESS_DIR .. "/lane_world.lua")
-- The creep offer's shadow (creep_offer.ts): an opportunity per hero and lane creep, its snapshot, and its one line. The
-- engine's laneTargets and hpForecast are stubs (w.targets, w.hits); the stub map's bot lane runs along y = -5000.

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
local function lines(all) local r = {} for _, l in ipairs(all) do if l:find("kind=creep", 1, true) then table.insert(r, l) end end return r end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end
local function num(line, k) return tonumber(field(line, k)) end

local function world(every)
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	-- The read alone: the creep row (test_creep_row.lua) is off, so every line is the shadow's.
	package.loaded["bots/FunLib/custom_loader"].Ours.LaneCreeps = false
	CURRENT_TEAM = 2
	T = 100
	local w = { targets = {}, hits = {}, calls = {} }
	local F = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
	F.Verbs = function()
		return {
			laneTargets = function(bot, opts) w.opts = opts w.calls[bot] = (w.calls[bot] or 0) + 1 return w.targets end,
			hpForecast = function(bot, creep, horizon)
				local copy = {}
				for i, x in ipairs(w.hits[creep] or {}) do copy[i] = x end
				return { hp = creep.hp, regen = 0, horizon = horizon, hits = copy, unphased = 0, unphasedTower = false, unphasedHits = {} }
			end,
			forecastHp = function(f, t)
				local hp = f.hp
				for _, h in ipairs(f.hits) do if h.t <= t then hp = hp - h.damage end end
				return hp
			end,
		}
	end
	package.loaded["bots/FunLib/humaniser/lane_hits"].Reset()
	w.CO = H.CreepOffer
	w.CO.ResetCache()
	w.CO.SETTINGS.Every = every or 0.1
	return w
end

local function hero(pid, pos, x)
	local h = MakeUnit({ pid = pid, team = 2, bot = true, loc = Vector(x or 0, -5000), hp = 600, maxhp = 600 })
	h.pos, h.lane = pos, Lane.Bot
	return h
end

local function target(creep, o)
	return { creep = creep, kind = o.kind or "lasthit", eta = o.eta or 0, due = o.due or 0, walk = o.walk or 0, dies = o.dies or 3, ranged = o.ranged == true }
end

-- A creep the engine has deleted: its handle is still the table key, and any call on it fails the test.
local function kill(c)
	RemoveCreep(c)
	for _, m in ipairs({ "GetHealth", "GetUnitName", "GetLocation", "GetBoundingRadius", "GetAcquisitionRange", "GetAttackDamage" }) do
		c[m] = function() error("a gone creep's handle was called: " .. m) end
	end
end

do -- a creep that is never arrivable: want 0, the snapshot at the largest slack, one line when it leaves the lists
	local w = world()
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, { walk = 1.0, dies = 0.2 }) }
		w.CO.Shadow(core) -- slack -1.25
		T = 100.1
		w.targets = { target(c, { walk = 0.6, dies = 0.2 }) }
		w.CO.Shadow(core) -- slack -0.85: the best
		T = 100.2
		w.targets = { target(c, { walk = 1.0, dies = 0.2 }) }
		w.CO.Shadow(core)
	end)
	check("nothing is written while the creep stays listed", #lines(out) == 0, table.concat(out, "\n"))
	out = capture(function()
		T = 100.3
		kill(c)
		w.targets = {}
		w.CO.Shadow(core)
		T = 100.4
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("one line, on the read the creep left", #l == 1, table.concat(out, "\n"))
	check("it reads go=0 why=off src=shadow want=0 with the slot", field(l[1], "go") == "0" and field(l[1], "why") == "off" and field(l[1], "src") == "shadow"
		and field(l[1], "want") == "0" and field(l[1], "slot") == "100" and field(l[1], "who") == "t", l[1])
	check("the snapshot is the largest slack's", near(num(l[1], "walk"), 0.6) and near(num(l[1], "slk"), -0.85), l[1])
	check("no window when arriving was never possible", field(l[1], "wo") == nil and field(l[1], "wl") == nil, l[1])
	check("the engine was asked over the reader radius, due within one attack cycle of the hero (the stub's 1.7 s)", w.opts.radius == 1600 and near(w.opts.within, 1.7))
end

do -- arrivable: the snapshot is the first ok read's, the window runs to the last ok read
	local w = world()
	local core = hero(1, 2)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, { walk = 1.0, dies = 3, due = 0.5 }) } -- slack 1.55 at 100.0
		w.CO.Shadow(core)
		T = 100.1
		w.targets = { target(c, { walk = 0.5, dies = 3 }) } -- ok again, a better read
		w.CO.Shadow(core)
		T = 100.2
		w.targets = { target(c, { walk = 0.5, dies = 0.1 }) } -- no longer ok
		w.CO.Shadow(core)
		T = 100.3
		kill(c)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("one line", #l == 1, table.concat(out, "\n"))
	check("want 1 and the first ok read's snapshot, not the later reads'", field(l[1], "want") == "1" and num(l[1], "walk") == 1 and num(l[1], "due") == 0.5
		and near(num(l[1], "slk"), 1.55), l[1])
	check("the window opened at once and lasted to the second ok read", num(l[1], "wo") == 0 and near(num(l[1], "wl"), 0.1), l[1])
end

do -- the first-ok snapshot replaces a worse earlier one
	local w = world()
	local core = hero(1, 3)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, { walk = 1.0, dies = 0.5 }) }
		w.CO.Shadow(core)
		T = 100.5
		w.targets = { target(c, { walk = 0.2, dies = 1.0 }) }
		w.CO.Shadow(core)
		T = 100.6
		kill(c)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("opened not ok, then ok: want 1, the window opens 0.5 s after the slot, the ok read is the snapshot", #l == 1 and field(l[1], "want") == "1"
		and near(num(l[1], "wo"), 0.5) and near(num(l[1], "walk"), 0.2) and num(l[1], "slot") == 100, l[1])
end

do -- a support writes nothing, with a core beside it writing its line from the same world (control)
	local w = world()
	local sup = hero(5, 5, 100)
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, {}) }
		w.CO.Shadow(sup)
		w.CO.Shadow(core)
		T = 100.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(sup)
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("only the core's line", #l == 1 and field(l[1], "pid") == "1", table.concat(out, "\n"))
end

do -- the hero dying closes its opportunities once, with the creep still listed
	local w = world()
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, {}) }
		w.CO.Shadow(core)
		T = 100.1
		core.alive = false
		w.CO.Shadow(core)
		T = 100.2
		w.CO.Shadow(core)
	end)
	check("one line at the death", #lines(out) == 1, table.concat(out, "\n"))
end

do -- whether stock was on the creep: any read with the attack target the creep
	local w = world()
	local core = hero(1, 1)
	local on = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local off = MakeCreep({ team = 3, x = 350, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(on, {}), target(off, {}) }
		core.target = on
		w.CO.Shadow(core)
		T = 100.1
		core.target = nil
		w.CO.Shadow(core)
		T = 100.2
		kill(on) kill(off)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	local by = {}
	for _, x in ipairs(l) do by[field(x, "cid")] = field(x, "atk") end
	local n1 = 0
	for _, v in pairs(by) do if v == "1" then n1 = n1 + 1 end end
	check("the creep it attacked once reads atk=1 and the other atk=0", #l == 2 and n1 == 1, table.concat(out, "\n"))
end

do -- the facts: the race, the enemies' reach and the path's cost
	local w = world()
	local core = hero(1, 1)
	local mate = hero(2, 5, 400)
	local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(550, -5000) })
	foe.dmg, foe.range, foe.spa = 90, 550, 1.7
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 40 })
	local ours = MakeCreep({ team = 2, x = 150, y = -5000, hp = 200 })
	local other = MakeCreep({ team = 3, x = 200, y = -4900, hp = 200, name = "npc_dota_creep_badguys_ranged" })
	other.dmg, other.spa, other.acq = 24, 1, 500
	w.hits[c] = { { t = 0.3, damage = 100, by = "hero", attacker = mate, commit = 0.2 } }
	local out = capture(function()
		w.targets = { target(c, { walk = 0, due = 0.4, dies = 2, ranged = false }), target(other, { due = 0.1, ranged = true }), target(ours, { kind = "deny", due = 5 }) }
		w.CO.Shadow(core)
		T = 100.1
		kill(c) kill(other) kill(ours)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = {}
	for _, x in ipairs(lines(out)) do if field(x, "ck") == "m" and field(x, "who") == "t" then table.insert(l, x) end end
	check("the melee creep's line", #l == 1, table.concat(out, "\n"))
	check("the race: a teammate's hit kills it at 0.3 s", field(l[1], "kb") == "mate" and near(num(l[1], "kt"), 0.3), l[1])
	check("the enemy hero reaches the creep: its hit and one such hero; mine beside it", num(l[1], "ed") == 90 and num(l[1], "ein") == 1 and num(l[1], "md") == 50, l[1])
	check("the enemy list holds pid, distance to the stand spot, range, hit, seconds an attack, exposure", (function() local a = {} for v in field(l[1], "en"):gmatch("[^:]+") do table.insert(a, tonumber(v)) end return #a == 6 and a[1] == 7 and a[2] == 550 and a[3] == 550 and a[4] == 90 and near(a[5], 1.7) and a[6] == 0 end)(), l[1])
	check("the enemy covers the spot (550 + hulls from 550 away) and the hero stands still", num(l[1], "eh") == 1 and num(l[1], "exs") == 0, l[1])
	check("their ranged creep with 500 acquisition range is at the spot and its damage counted", num(l[1], "pc") == 2 and num(l[1], "pd") == 24, l[1])
	check("the other target in reach due before the walk back counts (the ranged one), the deny due in 5 s does not", num(l[1], "g2") == 1 and num(l[1], "g2r") == 1, l[1])
end

do -- a lane creep or tower the API lists with no location (seen in games) is left out of the path's counts; the read does not throw
	local w = world()
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local near1 = MakeCreep({ team = 3, x = 200, y = -4900, hp = 200 })
	near1.dmg, near1.spa, near1.acq = 24, 1, 500
	local near2 = MakeCreep({ team = 3, x = 250, y = -5100, hp = 200 })
	near2.dmg, near2.spa, near2.acq = 24, 1, 500
	local ghost = MakeCreep({ team = 3, x = 280, y = -5000, hp = 200 })
	ghost.dmg, ghost.spa, ghost.acq = 24, 1, 500
	ghost.unseen, ghost.listedUnseen = true, true
	local good, bad = MakeLaneTowers()[3][dota.Tower.Bot1], MakeLaneTowers()[3][dota.Tower.Mid1]
	good.loc, bad.loc = Vector(300, -5000), Vector(100, -5000)
	bad.GetLocation = function() return nil end
	TOWERS_W[3] = { [dota.Tower.Bot1] = good, [dota.Tower.Mid1] = bad }
	local out = capture(function()
		w.targets = { target(c, {}) }
		w.CO.Shadow(core)
		T = 100.1
		kill(c) kill(near1) kill(near2) kill(ghost)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("the line is written with no lua_error", #l == 1 and not table.concat(out, "\n"):find("lua_error", 1, true), table.concat(out, "\n"))
	check("the offered creep and the two healthy ones are counted, 48 damage from the two that hit, the one with no location is left out", num(l[1], "pc") == 3 and num(l[1], "pd") == 48, l[1])
	check("the healthy tower still covers the path", num(l[1], "ptw") == 1, l[1])
end

do -- the offered creep itself reads no location: it is skipped for that read, with no line and no throw
	local w = world()
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	c.unseen = true
	local out = capture(function()
		w.targets = { target(c, {}) }
		w.CO.Shadow(core)
		T = 100.1
		w.targets = {}
		w.CO.Shadow(core)
	end)
	check("nothing is written and nothing throws", #out == 0, table.concat(out, "\n"))
end

do -- the rate: a read inside the interval does nothing; the close waits for the next due read and is written once
	local w = world(0.2)
	local core = hero(2, 2) -- an even pid reads at 100.0, 100.2, ...
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local blink = MakeCreep({ team = 3, x = 350, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, {}) }
		w.CO.Shadow(core) -- 100.0, due
		T = 100.1
		kill(c)
		w.targets = { target(blink, {}) }
		w.CO.Shadow(core) -- inside the interval: the gone creep is not closed yet, the new one is not seen
		check("a read inside the interval writes nothing", #lines({}) == 0)
	end)
	check("nothing is written inside the interval", #lines(out) == 0, table.concat(out, "\n"))
	out = capture(function()
		T = 100.15
		kill(blink)
		w.targets = {}
		w.CO.Shadow(core) -- still inside it
		T = 100.2
		w.CO.Shadow(core) -- due: the creep is closed
		T = 100.4
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("the first creep is closed once at the next due read; the one offered and gone inside the interval is missed", #l == 1 and field(l[1], "cid") == "1", table.concat(out, "\n"))
end

do -- an illusion of an enemy hero is no enemy: it leaves the counts and the list as without it
	local w = world()
	local core = hero(1, 1)
	local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(550, -5000) })
	foe.dmg, foe.range = 90, 550
	local fake = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(550, -5000) })
	fake.dmg, fake.range, fake.illusion = 90, 550, true
	function fake:IsIllusion() return true end
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, {}) }
		w.CO.Shadow(core)
		T = 100.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	local _, entries = (field(l[1], "en") or ""):gsub(";", ";")
	check("the illusion adds nothing to eh, ein or the list", #l == 1 and num(l[1], "eh") == 1 and num(l[1], "ein") == 1 and entries == 0, l[1])
end

do -- the stagger: an odd and an even pid read on different ticks
	local w = world(0.2)
	local odd, even = hero(1, 1), hero(2, 2)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	w.targets = { target(c, {}) }
	capture(function()
		w.CO.Shadow(odd) w.CO.Shadow(even) -- 100.0: the first read of each
		T = 100.1
		w.CO.Shadow(odd) w.CO.Shadow(even)
		check("at 100.1 the odd pid read and the even did not", w.calls[odd] == 2 and w.calls[even] == 1, tostring(w.calls[odd]) .. " " .. tostring(w.calls[even]))
		T = 100.2
		w.CO.Shadow(odd) w.CO.Shadow(even)
		check("at 100.2 the even pid read and the odd did not", w.calls[odd] == 2 and w.calls[even] == 2, tostring(w.calls[odd]) .. " " .. tostring(w.calls[even]))
	end)
end

do -- a creep nothing is hitting: dies is infinite, written -1, and the slack reads at its cap
	local w = world()
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
	local out = capture(function()
		w.targets = { target(c, { dies = math.huge, walk = 0.5 }) }
		w.CO.Shadow(core)
		T = 100.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	local l = lines(out)
	check("dies=-1, slk=99, and arriving is possible", #l == 1 and num(l[1], "dies") == -1 and num(l[1], "slk") == 99 and field(l[1], "want") == "1", l[1])
end

do -- the end of laning, or a drill holding the hero, closes its opportunities once with the creep still listed
	for _, how in ipairs({ "laning", "drill" }) do
		local w = world()
		local core = hero(1, 1)
		local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
		local Drill = package.loaded["bots/FunLib/humaniser/drill"]
		local held = Drill.Held
		local out = capture(function()
			w.targets = { target(c, {}) }
			w.CO.Shadow(core)
			T = 100.1
			if how == "laning" then LANING = false else Drill.Held = function() return true end end
			w.CO.Shadow(core)
			T = 100.2
			w.CO.Shadow(core)
		end)
		Drill.Held = held
		LANING = nil
		check("closed once when " .. how .. " turns the gate off", #lines(out) == 1, table.concat(out, "\n"))
	end
end

do -- ground height: the hero's, the stand spot's, the creep's and each listed enemy's, in en's order; an enemy with no location is in neither list
	local w = world()
	local core = hero(1, 1)
	local c = MakeCreep({ team = 3, x = 1300, y = -5000, hp = 80 })
	local high = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(1250, -5000) })
	local low = MakeUnit({ pid = 8, team = 3, bot = true, loc = Vector(0, -4800) })
	local ghost = MakeUnit({ pid = 9, team = 3, bot = true, loc = Vector(0, -4700) })
	ghost.GetLocation = function() return nil end
	HEIGHT = function(v) return v.x < 500 and 1 or (v.x < 1100 and 2 or 3) end
	local out = capture(function()
		w.targets = { target(c, { walk = 0.8 }) }
		w.CO.Shadow(core)
		T = 100.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(core)
	end)
	HEIGHT = nil
	local l = lines(out)
	check("the hero is low, the stand spot on the ramp, the creep high", #l == 1 and num(l[1], "hh") == 1 and num(l[1], "sh") == 2 and num(l[1], "ch") == 3, table.concat(out, "\n"))
	check("enemy heights follow en's pids, the one with no location left out of both", field(l[1], "enh") == "7:3;8:1" and (field(l[1], "en"):gsub("[^;]", "")) == ";", l[1])
	check("the hero's attack range is logged beside them", num(l[1], "ra") == 550, l[1])
end

do -- the height API absent, or answering nil: the line is written without the fields and nothing throws
	for _, how in ipairs({ "absent", "nil" }) do
		local w = world()
		local core = hero(1, 1)
		local c = MakeCreep({ team = 3, x = 300, y = -5000, hp = 80 })
		MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(550, -5000) })
		local keep = GetHeightLevel
		if how == "absent" then GetHeightLevel = nil else GetHeightLevel = function() return nil end end
		local out = capture(function()
			w.targets = { target(c, {}) }
			w.CO.Shadow(core)
			T = 100.1
			kill(c)
			w.targets = {}
			w.CO.Shadow(core)
		end)
		GetHeightLevel = keep
		local l = lines(out)
		check("no height read: a line, no lua_error, no height fields (" .. how .. ")", #l == 1 and not table.concat(out, "\n"):find("lua_error", 1, true)
			and field(l[1], "hh") == nil and field(l[1], "sh") == nil and field(l[1], "ch") == nil, table.concat(out, "\n"))
		check("the enemy's height is '-' where the API gave none (" .. how .. ")", field(l[1], "enh") == "7:-", l[1])
	end
end

finish()
