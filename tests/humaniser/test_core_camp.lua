dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice core-next-gold: CoreCamp (Ours.CoreCampTrip), an in-lane core's camp trip under the job chooser, priced against the
-- lane forecast's creep deaths. The forecast is stubbed: these checks are about the price and the trip, not the creep model.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode
local FARM, LANING = BotMode.Farm, BotMode.Laning
local PUSH = "bots/FunLib/humaniser/lane_push"

local FRONT = Vector(0, -5000)
local SMALL = Vector(0, -6200) -- 1,200 from the front
local LARGE = Vector(1500, -6500) -- 2,121 from the front

local function spawner(type_, at)
	return { team = 2, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- Forecast samples from t0: the fronts 2,000 apart until `clash`, then 200; `deaths` enemy (Dire) creep deaths from
-- `dieFrom`, one every `every` s.
local function samples(t0, clash, dieFrom, every)
	local out = {}
	for t = t0, t0 + 60 do
		local dead = 0
		if dieFrom ~= nil and t >= dieFrom then dead = 1 + math.floor((t - dieFrom) / every) end
		-- On PATH, s = 7,000 is x = 0: the clash point (fronts r and r + 200) sits on FRONT.
		local r = 6900
		out[#out + 1] = { t = t, front = { [2] = r, [3] = t < clash and r + 2000 or r + 200 }, dead = { [2] = 0, [3] = dead } }
	end
	return out
end

-- A straight lane along y = -5000 from x = -7,000.
local PATH = { pts = { { -7000, -5000 }, { 7000, -5000 } }, s = { 0, 14000 }, spawnR = 0, spawnD = 14000, towers = {} }

local function world(o)
	package.loaded["bots/FunLib/engine/tasks"] = nil
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true } })
	local C = package.loaded["bots/FunLib/custom_loader"]
	C.Ours = { CoreCampTrip = o.off ~= true }
	C.Overrides = { CampForce = o.force == true }
	T = o.t or 300
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = {}
	local camp = {}
	for i, c in ipairs(o.camps) do
		table.insert(SPAWNERS, spawner(c[1], c[2]))
		camp[i] = MakeNeutral({ x = c[2].x, y = c[2].y, hp = c[3] or 300 })
	end
	H.Lane.Camps.ResetCache()
	H.FarmPattern.ResetCache()
	H.CoreCamp.ResetCache()
	local core = MakeUnit({ pid = 1, team = 2, loc = o.at or FRONT, level = o.level or 6, mode = LANING })
	core.lane, core.pos, core.maxhp, core.hp, core.gold = Lane.Bot, 1, 600, 600, 500
	getmetatable(core).__index.GetGold = function(self) return self.gold or 0 end
	local enemy = MakeUnit({ pid = 10, team = 3, loc = o.enemyAt or Vector(6000, 6000) })
	enemy.pos = 3
	H.Lane.Config.SkillOf(core)
	local push = package.loaded[PUSH]
	local clash, dieFrom, every = o.clash or 40, o.dieFrom, o.every or 3
	push.Forecast = function() return samples(math.floor(T), math.floor(T) + clash, dieFrom and math.floor(T) + dieFrom, every), PATH end
	return H, core, camp, enemy
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function lines(all, ev, phase)
	local r = {}
	for _, l in ipairs(all) do
		if l:find("ev=" .. ev .. " ", 1, true) and (phase == nil or l:find(" phase=" .. phase .. " ", 1, true) or l:find(" phase=" .. phase .. "$")) then table.insert(r, l) end
	end
	return r
end

local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local function moveTowards(bot, to, step)
	local d = dist(bot.loc, to)
	if d <= step then bot.loc = Vector(to.x, to.y) else bot.loc = Vector(bot.loc.x + (to.x - bot.loc.x) * step / d, bot.loc.y + (to.y - bot.loc.y) * step / d) end
end

-- One frame: the farm host's GetDesire through the chooser, its Think when it bids, else laning. Moves go 300/s; an attack
-- order walks into range (550), then hits for 100 a second.
local function frame(H, bot, dt)
	dt = dt or 0.1
	local n0 = #ACTIONS
	local d = H.Chooser.Gate(bot, "farm", function() return H.Chooser.FarmDesire(bot) end)()
	if d > 0 then
		bot.mode = FARM
		H.Chooser.HostThink(bot, "farm", function() return H.Chooser.FarmThink(bot) end, function() return false end)()
	else
		bot.mode = LANING
		bot.order = nil
	end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and (a.kind == "MoveToLocation" or a.kind == "AttackUnit") then bot.order = a break end
	end
	local a = bot.order
	if a ~= nil and a.kind == "MoveToLocation" then moveTowards(bot, a.args[1], 300 * dt) end
	if a ~= nil and a.kind == "AttackUnit" and a.args[1].hp > 0 then
		local n = a.args[1]
		if dist(bot.loc, n.loc) > 550 then moveTowards(bot, n.loc, 300 * dt)
		elseif T >= (bot.nextHit or 0) then
			n.hp = math.max(0, n.hp - 100)
			bot.nextHit = T + 1
		end
	end
	T = T + dt
end

local function run(H, bot, untilT, each)
	return capture(function() while T < untilT do frame(H, bot) if each then each() end end end)
end

-- Price: the hard camp when its clear fits the gap, the small one when it does not; never past the clash + MaxLate.
do
	local H, core = world({ camps = { { "small", SMALL }, { "large", LARGE } } })
	local CC = H.CoreCamp
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	check("clash: first second the fronts meet, at their midpoint on the lane", c ~= nil and c.t == 340 and dist(c.at, FRONT) < 1, c and c.t)
	local p = CC.Plan(core, FRONT, 300, c)
	check("plan: a level-6 core with 40 s takes the large camp (more gold, fits)", p ~= nil and p.camp == 2 and p.type == "large", p and p.camp)
	check("plan: the return is walk in + clear + walk back", p ~= nil and math.abs(p.ret - (300 + 2 * 2121 * 1.2 / 300 + p.clr)) < 0.01, p and p.ret)
	local tight = CC.ClashOf(samples(300, 318), PATH, 2)
	local q = CC.Plan(core, FRONT, 300, tight)
	check("plan: with 18 s only the small camp is back by the clash + 15", q ~= nil and q.type == "small", q and q.type)
	core.level = 5
	local r = CC.Plan(core, FRONT, 300, c)
	check("plan: below level 6 the large camp is not offered", r ~= nil and r.type == "small", r and r.type)
end

-- Price: the lane creeps the forecast kills before the return are the trip's cost; a camp that does not pay for them is no trip.
do
	local H, core = world({ camps = { { "small", SMALL } } })
	local CC = H.CoreCamp
	local calm = CC.ClashOf(samples(300, 318), PATH, 2)
	local p = CC.Plan(core, FRONT, 300, calm)
	check("loss: no deaths before the return, the small camp's whole gold is net", p ~= nil and p.loss == 0 and p.net == p.gold, p and p.net)
	-- Two creeps a second die from 2 s on: by the return (~ 25 s) the lane has lost far more than the small camp pays.
	local bloody = CC.ClashOf(samples(300, 318, 302, 0.5), PATH, 2)
	local q = CC.Plan(core, FRONT, 300, bloody)
	check("loss: the same camp is refused when the lane loses more than it pays", q == nil, q and q.net)
	check("loss: priced at creep gold times the core's share", math.abs(CC.LossBetween(bloody, 300, 310) - 17 * 40 * 0.5) < 1e-6, CC.LossBetween(bloody, 300, 310))
end

-- The enemy tower: a wave crashing into their T1 is not the next lane gold, and its deaths are priced at the tower share.
do
	local H = world({ camps = { { "small", SMALL } } })
	local CC = H.CoreCamp
	-- Dire T1 at s = 9,500: fronts meeting at 9,000 are in its reach, at 7,000 they are not.
	local path = { pts = PATH.pts, s = PATH.s, spawnR = 0, spawnD = 14000, towers = { { team = 2, s = 4500 }, { team = 3, s = 9500 } } }
	local smp = {}
	for t = 300, 360 do
		local meet = (t <= 320 and 9000) or (t >= 335 and 7000) or nil
		local front = meet and { [2] = meet - 100, [3] = meet + 100 } or { [2] = 6000, [3] = 8000 }
		smp[#smp + 1] = { t = t, front = front, dead = { [2] = 0, [3] = math.min(t, 320) - 300 } }
	end
	local c = CC.ClashOf(smp, path, 2)
	check("tower: the clash is the next meeting outside their T1, not the crash under it", c ~= nil and c.t == 335, c and c.t)
	check("tower: deaths under their T1 cost the tower share", c ~= nil and math.abs(CC.LossBetween(c, 300, 320) - 20 * 40 * 0.2) < 1e-6, c and CC.LossBetween(c, 300, 320))
	path.towers = { { team = 2, s = 4500 }, { team = 3, s = 12000 } }
	local open = CC.ClashOf(smp, path, 2)
	check("tower: the same fight outside their reach is the clash now, at the full share", open ~= nil and open.t == 300 and math.abs(CC.LossBetween(open, 300, 320) - 20 * 40 * 0.5) < 1e-6, open and open.t)
end

-- The wave is better: its fight at the front is now (outside their tower), so the core stays, held by the gap.
do
	local H, core = world({ t = 294.5, camps = { { "small", SMALL } }, clash = 0, at = Vector(-1500, -5000) })
	local out = run(H, core, 301)
	local g = lines(out, "core_camp", "gates")[1]
	check("wave now: no trip", #lines(out, "core_camp", "start") == 0)
	check("wave now: every second held by the gap", g ~= nil and tonumber(field(g, "h_gap")) >= 5 and field(g, "h_trip") == nil, g)
end

-- The harness (Overrides.CampForce): the same 8 s gap that holds the core sends it, and the trip runs to its end.
do
	local H, core, camp = world({ t = 295, camps = { { "small", SMALL } }, clash = 8, force = true })
	local out = run(H, core, 330)
	local start, ended = lines(out, "core_camp", "start")[1], lines(out, "core_camp", "end")[1]
	check("harness: a trip starts despite the gap", start ~= nil, #lines(out, "core_camp"))
	check("harness: the camp is cleared and the core walks back", camp[1].hp == 0 and ended ~= nil and field(ended, "why") == "back", ended)
end

-- A trip end to end: started by the chooser, the camp cleared on the verb, the walk back, `back` logged; FarmPattern idle.
do
	local H, core, camp = world({ camps = { { "small", SMALL } } })
	local fp = 0
	local out = run(H, core, 330, function() if H.FarmPattern.Desire(core) > 0 then fp = fp + 1 end end)
	local start, ended = lines(out, "core_camp", "start")[1], lines(out, "core_camp", "end")[1]
	check("trip: started on the small camp with its price", start ~= nil and field(start, "camp") == "1" and field(start, "loss") == "0" and field(start, "net") == "80", start)
	check("trip: the neutral killed", camp[1].hp == 0)
	check("trip: ended back at the front, in time", ended ~= nil and field(ended, "why") == "back" and tonumber(field(ended, "back")) <= tonumber(field(ended, "ret")) + 5, ended)
	check("trip: FarmPattern never bid for the owned core", fp == 0, fp)
	check("trip: pace learned from the measured clear", math.abs(H.CoreCamp.Pace(core) - 1) > 1e-3, H.CoreCamp.Pace(core))
end

-- Switch off: no trip of ours; the core is FarmPattern's again.
do
	local H, core = world({ off = true, camps = { { "small", SMALL } } })
	local out = run(H, core, 302)
	check("off: no core_camp line", #lines(out, "core_camp") == 0)
	check("off: CoreCamp does not own the core", not H.CoreCamp.Owns(core))
end

-- An enemy hero by the camp: the walk would meet it, so no trip; one skip line for the window, naming the threat.
do
	local H, core = world({ camps = { { "small", SMALL } }, enemyAt = Vector(300, -6600) })
	local out = run(H, core, 305)
	local skips = lines(out, "core_camp", "skip")
	check("threat at the camp: no trip", #lines(out, "core_camp", "start") == 0)
	check("threat at the camp: one skip line for the window, why=threat", #skips == 1 and field(skips[1], "why") == "threat", #skips)
end

-- The gate tally: each planning second of a minute counted by what held it, flushed when the minute turns.
do
	local H, core = world({ t = 294.5, camps = { { "small", SMALL } }, enemyAt = Vector(300, -6600), clash = 8 })
	local out = run(H, core, 301)
	local g = lines(out, "core_camp", "gates")
	check("gates: one line for minute 4 once minute 5 starts", #g == 1 and field(g[1], "min") == "4", #g)
	check("gates: a clash 8 s away counts every second as gap, nothing as a fitted camp", g[1] ~= nil and tonumber(field(g[1], "h_gap")) >= 5 and field(g[1], "h_skip") == nil, g[1])
end

-- An enemy hero walks up during the clear: the trip ends `threat` after the core's reaction time, not at once.
do
	local H, core, camp, enemy = world({ camps = { { "small", SMALL, 5000 } } })
	local cameAt
	local out = run(H, core, 325, function()
		if cameAt == nil and H.CoreCamp.Running(core) and dist(core.loc, SMALL) < 700 then
			enemy.loc = Vector(core.loc.x + 300, core.loc.y)
			cameAt = T
		elseif cameAt ~= nil and enemy.loc.x ~= 6000 then
			enemy.loc = Vector(core.loc.x + 300, core.loc.y)
		end
	end)
	local ended = lines(out, "core_camp", "end")[1]
	local endT = ended and tonumber(ended:match("t=(%S+)"))
	check("threat on the trip: ended threat", ended ~= nil and field(ended, "why") == "interrupted:threat", ended)
	check("threat on the trip: after a reaction time, within 2 s", cameAt ~= nil and endT ~= nil and endT - cameAt > 0.05 and endT - cameAt < 2, endT and cameAt and endT - cameAt)
end

-- A camp that will not die in time: left at its leave time, walked back, the pace grows.
do
	local H, core, camp = world({ camps = { { "small", SMALL, 5000 } }, clash = 30 })
	local out = run(H, core, 340)
	local ended = lines(out, "core_camp", "end")[1]
	check("late: the camp left unfinished and the core walked back", ended ~= nil and field(ended, "why") == "back" and camp[1].hp > 0, ended)
	check("late: the pace grew", H.CoreCamp.Pace(core) > 1 + 1e-3, H.CoreCamp.Pace(core))
end

finish()
