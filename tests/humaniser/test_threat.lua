dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice threat: Threat.Read (the missing belief's minute weights, a hero's own speed for its run, reach over the horizon,
-- the enemy tower, lethal), the gates that read it under Ours.Threat and their OFF arm, and ev=threat's rate limit.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local HERE = Vector(-2000, -5000)
local CAMP = Vector(-1000, -6200)

local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours.Threat = o.off ~= true
	T = o.t or 300
	CURRENT_TEAM, OBSERVER = 2, 1
	local Threat = require("bots/FunLib/humaniser/threat")
	Threat.ResetCache()
	local bot = MakeUnit({ pid = 1, team = 2, loc = HERE, level = 3 })
	bot.lane, bot.pos, bot.maxhp, bot.hp = Lane.Bot, 3, 600, 600
	local e = MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) })
	e.maxhp, e.hp = 600, 600
	return H, Threat, bot, e
end

local function hide(e, at, tss)
	e.hiddenFrom = { [OBSERVER] = true }
	LAST_SEEN[e.pid] = { location = at, time_since_seen = tss }
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function threatLines(all)
	local r = {}
	for _, l in ipairs(all) do if l:find("ev=threat ", 1, true) then r[#r + 1] = l end end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

-- The belief: a hero unseen by the walk weighs 0.2 before 4:00 and 0.5 after (graded rows: precision 0.22 against 0.55), so
-- the gates' 0.5 holds on one hero late and needs three early.
do
	local H, Threat, bot, e = world({ t = 200 })
	hide(e, Vector(-500, -7000), 10)
	local early = Threat.Read(bot, HERE, CAMP, 4)
	check("belief: early weight 0.2 for one hero by the walk", near(early.missing, 0.2), early.missing)
	check("belief: the counted pid and its time unseen", early.mpids[1] == 10 and early.mtss == 10)
	local e2 = MakeUnit({ pid = 11, team = 3 })
	local e3 = MakeUnit({ pid = 12, team = 3 })
	hide(e2, Vector(-800, -6800), 20)
	hide(e3, Vector(0, -6500), 30)
	local three = Threat.Read(bot, HERE, CAMP, 4)
	check("belief: three early heroes sum to 0.6, past the gate", near(three.missing, 0.6) and three.missing >= H.CoreCamp.SETTINGS.MissingRefuse, three.missing)
	T = 300
	local late = Threat.Read(bot, HERE, CAMP, 4)
	check("belief: after 4:00 each weighs 0.5", near(late.missing, 1.5), late.missing)
end

-- The run grows at the hero's own last seen speed (not 330): a slow hero last seen 2,700 from the walk 6 s ago is out
-- (6 x 300 + 600 = 2,400), a fast one is in (6 x 400 + 600 = 3,000).
for _, case in ipairs({ { speed = 300, n = 0 }, { speed = 400, n = 1 } }) do
	local _, Threat, bot, e = world()
	e.loc, e.speed = Vector(0, -9200), case.speed
	Threat.Read(bot, HERE, CAMP, 4) -- seen once: the speed is remembered
	hide(e, Vector(-1000, -8900), 6)
	local r = Threat.Read(bot, HERE, CAMP, 4)
	check("belief: speed " .. case.speed .. " -> counted " .. case.n, #r.mpids == case.n, #r.mpids)
end

-- Reach is the run over the horizon plus attack range and both hulls: a melee 300-speed hero 1,300 from the walk is in at
-- 4 s (1,200 + 150 + 48 = 1,398), out at 3 s; its estimated damage is the burst, a share of our HP.
do
	local _, Threat, bot, e = world()
	e.loc, e.range, e.estDamage = Vector(-1000, -7500), 150, 300
	local r4 = Threat.Read(bot, HERE, CAMP, 4)
	check("reach: in at 4 s", #r4.reach == 1 and near(r4.burst, 0.5), r4.burst)
	check("reach: out at 3 s", #Threat.Read(bot, HERE, CAMP, 3).reach == 0)
	check("band: one hero in reach, half our HP in burst: watch or more", r4.band ~= "none" and r4.band ~= "lethal", r4.band)
	bot.hp = 250
	local low = Threat.Read(bot, HERE, CAMP, 4)
	check("lethal: their burst passes our HP and they outnumber us", low.band == "lethal", low.band)
	local ally = MakeUnit({ pid = 2, team = 2, loc = Vector(-1100, -6000) })
	ally.maxhp, ally.hp = 600, 600
	check("lethal: not with an ally who reaches the place", Threat.Read(bot, HERE, CAMP, 4).band ~= "lethal")
end

-- Tower: the place inside the Dire T1's reach (844 from x = 2,800) is flagged, outside is not.
do
	local _, Threat, bot = world()
	check("tower: inside the reach", Threat.Read(bot, HERE, Vector(2200, -5000), 2).tower == true)
	check("tower: outside", Threat.Read(bot, HERE, Vector(1700, -5000), 2).tower == false)
end

-- The core camp gate with the switch on: an early lone missing hero no longer holds the trip; the OFF arm (MissingOf) still
-- counts it. After 4:00 both hold.
for _, case in ipairs({ { t = 200, off = false, held = 0 }, { t = 200, off = true, held = 1 }, { t = 300, off = false, held = 1 } }) do
	local H, _, bot, e = world({ t = case.t, off = case.off })
	hide(e, Vector(-500, -7000), 10)
	local n
	capture(function() n = H.CoreCamp.MissingGate(bot, CAMP, "core_pull") end)
	check(string.format("gate t=%d off=%s: held %d", case.t, tostring(case.off), case.held), n == case.held, n)
end

-- ev=threat: one line per consumer while the decision holds, again after LogEvery or at once when it changes.
do
	local H, _, bot, e = world()
	hide(e, Vector(-500, -7000), 10)
	local out = capture(function()
		H.CoreCamp.MissingGate(bot, CAMP, "core_pull")
		T = T + 1
		H.CoreCamp.MissingGate(bot, CAMP, "core_pull")
		e.alive = false
		H.CoreCamp.MissingGate(bot, CAMP, "core_pull")
		T = T + 1
		H.CoreCamp.MissingGate(bot, CAMP, "core_pull")
		T = T + 6
		H.CoreCamp.MissingGate(bot, CAMP, "core_pull")
	end)
	local l = threatLines(out)
	check("log: held, then go on the change, then go again after LogEvery", #l == 3 and field(l[1], "dec") == "missing" and field(l[2], "dec") == "go" and field(l[3], "dec") == "go", #l)
	check("log: the held line carries the weight and pid", tonumber(field(l[1], "miss")) == 0.5 and field(l[1], "mpid") == "10", l[1])
end
finish()
