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
		camp[i] = MakeNeutral({ x = c[2].x, y = c[2].y, hp = c[3] or 300, maxhp = c[3] or 300 })
		camp[i].dmg, camp[i].armor = c[4], c[5]
	end
	H.Lane.Camps.ResetCache()
	H.FarmPattern.ResetCache()
	H.CoreCamp.ResetCache()
	-- The gate's count is under test here; the threat read's vision cut has its own checks (test_threat).
	require("bots/FunLib/humaniser/threat").SETTINGS.VisionCut = false
	local core = MakeUnit({ pid = 1, team = 2, loc = o.at or FRONT, level = o.level or 6, mode = LANING })
	core.lane, core.pos, core.maxhp, core.hp, core.gold = Lane.Bot, 1, 600, 600, 500
	-- The clear model sees the hit this world deals: 100 a second.
	core.dmg, core.spa = 100, 1
	getmetatable(core).__index.GetNetWorth = function(self) return self.gold or 0 end
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

-- The clear model: kills in the order that loses the least HP, each neutral hitting until it dies, regen against the loss.
do
	local H, core = world({ camps = { { "small", SMALL } } })
	core.dmg, core.spa, core.regen = 60, 1.5, 5
	-- 40 a second: the 200-HP hard hitter dies first (5.6 s with the switch), the 400-HP one by 16.2 s.
	local secs, hp = H.CoreCamp.ClearOf(core, { { hp = 400, take = 1, dmg = 20, spa = 1 }, { hp = 200, take = 1, dmg = 40, spa = 1 } })
	check("model: the clear is each kill plus a switch", math.abs(secs - 16.2) < 1e-6, secs)
	check("model: the hard hitter dies first; the loss net of regen (40 x 5.6 + 20 x 16.2 - 5 x 16.2) / 600", math.abs(hp - 467 / 600) < 1e-6, hp)
	local slow = H.CoreCamp.ClearOf(core, { { hp = 400, take = 0.5, dmg = 20, spa = 1 } })
	check("model: armour (half the hit taken) doubles the kill", math.abs(slow - 20.6) < 1e-6, slow)
end

-- Price from the model: the hard camp when its clear fits the gap and leaves the core HP; the hero's damage decides, not
-- its level (no level gate, user 06/11/2026).
do
	local H, core, camp = world({ camps = { { "small", SMALL }, { "large", LARGE, 2400, 8 } } })
	local CC = H.CoreCamp
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	check("clash: first second the fronts meet, at their midpoint on the lane", c ~= nil and c.t == 340 and dist(c.at, FRONT) < 1, c and c.t)
	local p = CC.Plan(core, FRONT, 300, c)
	check("plan: with 40 s the large camp (24.6 s clear by the model) is taken", p ~= nil and p.camp == 2 and p.src == "live" and math.abs(p.clr - 24.6) < 1e-6, p and p.clr)
	check("plan: the return is walk in + clear + walk back", p ~= nil and math.abs(p.ret - (300 + 2 * 2121 * 1.2 / 300 + p.clr)) < 0.01, p and p.ret)
	local tight = CC.ClashOf(samples(300, 318), PATH, 2)
	local q = CC.Plan(core, FRONT, 300, tight)
	check("plan: with 18 s only the small camp is back by the clash + 15", q ~= nil and q.type == "small", q and q.type)
	core.level = 2
	local r = CC.Plan(core, FRONT, 300, c)
	check("plan: at level 2 the live large camp is still taken when its clear fits (no level gate)", r ~= nil and r.type == "large" and r.lvl == 2, r and r.type)
	core.level, core.hp = 6, 480
	local h = CC.Plan(core, FRONT, 300, c)
	check("plan: at 80% HP the core takes it (8 a second for 24.6 s is 0.33 of its HP)", h ~= nil and h.type == "large" and math.abs(h.hpc - 8 * 24.6 / 600) < 1e-6, h and h.hpc)
	core.hp, camp[2].dmg = 600, 20
	check("plan: a camp hitting for 20 a second would leave it under 40% even from full HP", (CC.Plan(core, FRONT, 300, c) or {}).type == "small")
	core.dmg = 200
	local strong = CC.Plan(core, FRONT, 300, c)
	check("plan: a core hitting twice as hard clears it in half the time and takes it", strong ~= nil and strong.type == "large", strong and strong.type)
	for _ = 1, 5 do MakeNeutral({ x = LARGE.x + 50, y = LARGE.y, hp = 300 }) end
	local st = CC.Plan(core, FRONT, 300, c)
	check("plan: six neutrals are a stack the stack job never made: double gold, and the extra neutrals in the clear", st ~= nil and st.gold == 320 and st.clr > strong.clr + 10, st and st.clr)
end

-- Fog: a camp seen once is priced as last seen; one never seen falls back to the type tables.
do
	local H, core, camp = world({ camps = { { "large", LARGE, 2400, 8 } } })
	local CC = H.CoreCamp
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	check("fog: seen, priced live", (CC.Plan(core, FRONT, 300, c) or {}).src == "live")
	camp[1].unseen = true
	FOGGED = function(v) return dist(v, LARGE) < 800 end
	local seen = CC.Plan(core, FRONT, 300, c)
	check("fog: fogged, priced as last seen", seen ~= nil and seen.src == "seen" and math.abs(seen.clr - 24.6) < 1e-6, seen and seen.src)
	CC.ResetCache()
	check("fog: never seen, the type tables", (CC.Plan(core, FRONT, 300, c) or {}).src == "table")
	FOGGED = nil
end

-- A pulled wave in the camp: its neutrals are the wave's, so the camp is not offered (cngchk9 camp 26 at 3:36).
do
	local H, core = world({ camps = { { "small", SMALL }, { "large", LARGE, 2400, 8 } } })
	local CC = H.CoreCamp
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	check("pulled: without a wave in it the large camp is the pick", (CC.Plan(core, FRONT, 300, c) or {}).camp == 2)
	MakeCreep({ team = 2, x = LARGE.x + 100, y = LARGE.y, name = "npc_dota_lycan_wolf1" })
	check("pulled: a summon in the camp is no pulled wave", (CC.Plan(core, FRONT, 300, c) or {}).camp == 2)
	MakeCreep({ team = 3, x = LARGE.x + 100, y = LARGE.y })
	local p = CC.Plan(core, FRONT, 300, c)
	check("pulled: their lane creep in the large camp leaves the small one", p ~= nil and p.camp == 1, p and p.camp)
	-- Slice support-pull-farm: while the support is clearing that camp (and will give it up) the core may price it.
	H.CampClaims.Set("pullfarm", 5, 2)
	-- The support stands in the camp's box, as it does while farming: its own claim must not close the camp to the core.
	local sup = MakeUnit({ pid = 5, team = 2, loc = Vector(LARGE.x + 50, LARGE.y), level = 6 })
	sup.lane, sup.pos = Lane.Bot, 5
	local q = CC.Plan(core, FRONT, 300, c)
	check("pulled: the support clearing the camp leaves it open to the core", q ~= nil and q.camp == 2, q and q.camp)
	H.CampClaims.Set("pullfarm", 5, nil)
	check("pulled: the claim released, the camp is closed again", (CC.Plan(core, FRONT, 300, c) or {}).camp == 1)
	H.CampClaims.Set("pullfarm", 7, 2)
	check("pulled: an ally in the box that is not the claim holder still closes it", (CC.Plan(core, FRONT, 300, c) or {}).camp == 1)
end

-- A half-cleared camp is not its make-up: the respawn is priced as the camp was seen untouched (cngchk8 game 1049 camp 1).
do
	local H, core, camp = world({ camps = { { "large", LARGE, 2400, 8 } } })
	local CC = H.CoreCamp
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	local extra = MakeNeutral({ x = LARGE.x + 50, y = LARGE.y, hp = 600, maxhp = 600 })
	local whole = CC.Plan(core, FRONT, 300, c)
	camp[1].hp = 1200
	extra.hp = 0
	CC.Plan(core, FRONT, 300, c)
	camp[1].unseen = true
	FOGGED = function(v) return dist(v, LARGE) < 800 end
	local seen = CC.Plan(core, FRONT, 300, c)
	check("seen: the fogged camp keeps its untouched two-neutral make-up", whole ~= nil and seen ~= nil and seen.src == "seen" and seen.n0 == 2 and math.abs(seen.clr - whole.clr) < 1e-6, seen and seen.n0)
	FOGGED = nil
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
	local H, core, camp = world({ camps = { { "small", SMALL, 300, 20 } } })
	local fp = 0
	local out = run(H, core, 330, function() if H.FarmPattern.Desire(core) > 0 then fp = fp + 1 end end)
	local start, ended = lines(out, "core_camp", "start")[1], lines(out, "core_camp", "end")[1]
	check("trip: started on the small camp with its price", start ~= nil and field(start, "camp") == "1" and field(start, "loss") == "0" and field(start, "net") == "80", start)
	check("trip: the neutral killed", camp[1].hp == 0)
	check("trip: ended back at the front, in time", ended ~= nil and field(ended, "why") == "back" and tonumber(field(ended, "back")) <= tonumber(field(ended, "ret")) + 5, ended)
	check("trip: pace learned from the measured clear", math.abs(H.CoreCamp.Pace(core) - 1) > 1e-3, H.CoreCamp.Pace(core))
	check("trip: a clear priced 0.12 that cost no HP lowers the HP rate", H.CoreCamp.HPRate(core) < 1 - 1e-3, H.CoreCamp.HPRate(core))
	check("trip: the end line logs the HP, the rate and the measured clear", ended ~= nil and field(ended, "hp") == "1" and field(ended, "hpr") ~= nil and tonumber(field(ended, "clrm")) > 0, ended)
end

-- An enemy hero handle with no location (fogged): the gates and the trip's guard skip it, and the trip runs.
do
	local H, core, camp, enemy = world({ camps = { { "small", SMALL } } })
	local ok, out = pcall(run, H, core, 330, function() if H.CoreCamp.Running(core) then enemy.loc = nil end end)
	local ended = ok and lines(out, "core_camp", "end")[1]
	check("no location: no error mid-trip, and the trip runs to its end", ok and ended and field(ended, "why") == "back", ok and ended or out)
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

-- An enemy hero walks up during the clear (the camp made tough once the fight began, so the clear outlasts it): the trip
-- ends `threat` after the core's reaction time, not at once.
do
	local H, core, camp, enemy = world({ camps = { { "small", SMALL } } })
	local cameAt
	local out = run(H, core, 325, function()
		if camp[1].hp < camp[1].maxhp and camp[1].maxhp ~= 5000 then camp[1].hp, camp[1].maxhp = 5000, 5000 end
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
	check("threat on the trip: the aborted clear is measured on the end line", ended ~= nil and tonumber(field(ended, "clrm")) ~= nil and field(ended, "nl") == "1", ended)
end

-- A camp that will not die in time (tougher than the model read, once the fight has begun): left at its leave time, walked
-- back, the pace grows.
do
	local H, core, camp = world({ camps = { { "small", SMALL } }, clash = 30 })
	local out = run(H, core, 340, function()
		if camp[1].hp < camp[1].maxhp and camp[1].maxhp ~= 5000 then camp[1].hp, camp[1].maxhp = 5000, 5000 end
	end)
	local ended = lines(out, "core_camp", "end")[1]
	check("late: the camp left unfinished and the core walked back", ended ~= nil and field(ended, "why") == "back" and camp[1].hp > 0, ended)
	check("late: the pace grew", H.CoreCamp.Pace(core) > 1 + 1e-3, H.CoreCamp.Pace(core))
end

-- The offlaner also takes the enemy's small and large camps by its lane (the hard camp its pos4 pulls): with its own team's
-- camps only, pos3 never fitted one (cngchk6, cngchk9; ~/.dotactl/logs/2026-11-05T18-13-16-bug-hunt_observe_team-bots_e3fcbd4.log
-- t=661-781: pid 1 and 9 gate no-camp, no plan; user 06/11/2026). A pos1 does not take the enemy's camp.
do
	local H, core = world({ camps = { { "large", LARGE, 2400, 8 }, { "medium", Vector(-1500, -6500), 2400, 8 } } })
	local CC = H.CoreCamp
	SPAWNERS[1].team, SPAWNERS[2].team = 3, 3
	H.Lane.Camps.ResetCache()
	local saved = TOWERS_W[2][dota.Tower.Bot1]
	TOWERS_W[2][dota.Tower.Bot1] = MakeUnit({ pid = 91, team = 2, loc = Vector(0, -5000) })
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	check("offlane: a pos1 takes no enemy camp", CC.Plan(core, FRONT, 300, c) == nil)
	core.pos = 3
	local p = CC.Plan(core, FRONT, 300, c)
	check("offlane: the pos3 takes the enemy's large camp by its lane tower, not their medium one", p ~= nil and p.camp == 1 and p.type == "large", p and p.camp)
	TOWERS_W[2][dota.Tower.Bot1] = MakeUnit({ pid = 91, team = 2, loc = Vector(6000, -5000) })
	check("offlane: an enemy camp past OffCampDist of the tower is not offered", CC.Plan(core, FRONT, 300, c) == nil)
	TOWERS_W[2][dota.Tower.Bot1] = saved
end

-- User 06/11/2026: the pos3 does not take the enemy small camp by its lane (the enemy pos5's pull camp, in their support's
-- path, next to their carry); only the large one its pos4 pulls.
do
	local H, core = world({ camps = { { "small", Vector(-1000, -6000) }, { "large", LARGE, 2400, 8 } } })
	local CC = H.CoreCamp
	SPAWNERS[1].team, SPAWNERS[2].team = 3, 3
	H.Lane.Camps.ResetCache()
	local saved = TOWERS_W[2][dota.Tower.Bot1]
	TOWERS_W[2][dota.Tower.Bot1] = MakeUnit({ pid = 91, team = 2, loc = Vector(0, -5000) })
	core.pos = 3
	local c = CC.ClashOf(samples(300, 340), PATH, 2)
	local p = CC.Plan(core, FRONT, 300, c)
	check("offlane: the pos3 takes the enemy large camp, not the nearer enemy small one", p ~= nil and p.camp == 2 and p.type == "large", p and p.camp)
	table.remove(SPAWNERS, 2)
	H.Lane.Camps.ResetCache()
	local only = CC.Plan(core, FRONT, 300, c)
	check("offlane: the enemy small camp alone is not offered to the pos3", only == nil, only and only.camp)
	TOWERS_W[2][dota.Tower.Bot1] = saved
end

-- The missing-hero gate (user 06/11/2026, pos1 and pos3 alike): an enemy alive and unseen for more than MissingAfter whose
-- last-seen spot is within its possible run of the walk or the camp holds the start, why=missing with the count; a visible
-- far enemy, one last seen far off, a dead one or a fresh sighting does not.
for _, pos in ipairs({ 1, 3 }) do
	local H, core, _, enemy = world({ camps = { { "small", SMALL } } })
	core.pos = pos
	enemy.hiddenFrom = { [OBSERVER] = true }
	LAST_SEEN[enemy.pid] = { location = Vector(2500, -7000), time_since_seen = 10 }
	local out = run(H, core, 302)
	local skips = lines(out, "core_camp", "skip")
	check("missing pos" .. pos .. ": an unseen enemy near the camp holds the trip", #lines(out, "core_camp", "start") == 0)
	check("missing pos" .. pos .. ": one skip line, why=missing nmiss=1", #skips == 1 and field(skips[1], "why") == "missing" and field(skips[1], "nmiss") == "1", skips[1])
end

do
	local H, core, _, enemy = world({ camps = { { "small", SMALL } } })
	local CC = H.CoreCamp
	check("missing: a visible enemy far off is not missing", CC.MissingNear(core, SMALL) == 0)
	enemy.hiddenFrom = { [OBSERVER] = true }
	LAST_SEEN[enemy.pid] = { location = Vector(2500, -7000), time_since_seen = 2 }
	check("missing: seen 2 s ago is not missing yet", CC.MissingNear(core, SMALL) == 0)
	LAST_SEEN[enemy.pid] = { location = Vector(6000, 6000), time_since_seen = 5 }
	check("missing: last seen far off a short while ago is not near", CC.MissingNear(core, SMALL) == 0)
	LAST_SEEN[enemy.pid] = { location = Vector(6000, 6000), time_since_seen = 120 }
	check("missing: long unseen far off is past MissingReachMax", CC.MissingNear(core, SMALL) == 0)
	LAST_SEEN[enemy.pid] = { location = Vector(2500, -7000), time_since_seen = 100 }
	check("missing: long unseen by the camp counts", CC.MissingNear(core, SMALL) == 1)
	enemy.alive = false
	check("missing: a dead enemy does not count", CC.MissingNear(core, SMALL) == 0)
	local out = run(H, core, 302)
	check("missing: with the enemy dead the trip starts", #lines(out, "core_camp", "start") == 1)
end

-- Review M1 (2fec253): the skip line carries the longest time_since_seen of the counted heroes (mtss, rounded) and their
-- pids (mpid), so holds on stale sightings can be split by age from the logs.
do
	local H, core, _, enemy = world({ camps = { { "small", SMALL } } })
	enemy.hiddenFrom = { [OBSERVER] = true }
	local e2 = MakeUnit({ pid = 11, team = 3, loc = Vector(6000, 6000) })
	e2.hiddenFrom = { [OBSERVER] = true }
	LAST_SEEN[enemy.pid] = { location = Vector(2500, -7000), time_since_seen = 10 }
	LAST_SEEN[e2.pid] = { location = Vector(-1500, -6800), time_since_seen = 31.6 }
	local skip = lines(run(H, core, 302), "core_camp", "skip")[1]
	check("missing M1: nmiss=2, mtss the longest unseen rounded, mpid both pids", skip ~= nil and field(skip, "nmiss") == "2" and field(skip, "mtss") == "32" and field(skip, "mpid") == "10,11", skip)
end

-- With no level gate, the HP price keeps a low-level core off a large camp it has never seen: the table's 0.35 at level 6
-- grows 1/0.8 a level below it, so at level 3 (0.68; drill cngdr1 lost 0.62 there with a neutral left) a full-HP core would
-- not keep 40%, at level 4 (0.55) it would.
do
	local H, core, camp = world({ camps = { { "large", LARGE, 2400, 8 } } })
	camp[1].loc = Vector(99999, 99999)
	core.level = 3
	check("table: a level 3 core cannot clear an unseen large camp", H.CoreCamp.CanClear(core, 1, 0) == false)
	core.level = 4
	check("table: a level 4 core can, from full HP", H.CoreCamp.CanClear(core, 1, 0) == true)
	check("table: not with one stack on it", H.CoreCamp.CanClear(core, 1, 1) == false)
end

-- A clear priced under LearnMinHP teaches the HP rate nothing (drill cngdr2: 0 lost on 0.04 three times took it to 0.5).
do
	local H, core = world({ camps = { { "small", SMALL, 300, 5 } } })
	local ended = lines(run(H, core, 330), "core_camp", "end")[1]
	check("learn: a clear priced 0.03 leaves the HP rate", ended ~= nil and tonumber(field(ended, "hpe")) < 0.1 and H.CoreCamp.HPRate(core) == 1, ended)
end

-- The price checked on the camp found (drill cngdr2: the table priced a small camp 0.23 that held a taskmaster and two
-- troll berserkers, 0.89 live; a level 4 large 0.44 against 0.96). Unseen at the plan, so priced from the tables; the
-- camp seen on the walk would cost 1.6 of the core's HP: refused before any attack, the core walks back, and the next plan
-- prices the camp as seen.
do
	local H, core, camp = world({ camps = { { "large", LARGE, 2400, 40 } } })
	local home = camp[1].loc
	camp[1].loc = Vector(99999, 99999)
	FOGGED = function(v) return dist(v, LARGE) < 800 end
	local attacks = 0
	local out = run(H, core, 330, function()
		if T > 300.5 and FOGGED ~= nil then camp[1].loc, FOGGED = home, nil end
		for _, a in ipairs(ACTIONS) do if a.pid == core.pid and a.kind == "AttackUnit" then attacks = attacks + 1 end end
	end)
	local start, ref, ended = lines(out, "core_camp", "start")[1], lines(out, "core_camp", "refuse")[1], lines(out, "core_camp", "end")[1]
	check("refuse: the trip started on the table price", start ~= nil and field(start, "src") == "table" and field(start, "camp") == "1", start)
	check("refuse: the live camp priced past the HP budget, refused", ref ~= nil and tonumber(field(ref, "hpe")) > 1, ref)
	check("refuse: no attack order on the camp", attacks == 0, attacks)
	check("refuse: the core walked back", ended ~= nil and field(ended, "why") == "back", ended)
	local c = H.CoreCamp.ClashOf(samples(330, 380), PATH, 2)
	check("refuse: the next plan prices the camp as seen and leaves it", H.CoreCamp.Plan(core, FRONT, 330, c) == nil)
end

-- The clear is learned against the neutrals met at engage, not the plan's price (drill cngdr1 t=244: a camp priced full
-- held one neutral, and its quick clear taught pace 0.9 and HP rate 0.75 though every trip cost more than priced). Two
-- neutrals at the plan, one dead before the core arrives: the pace moves on the measured clear over the one met.
do
	local H, core, camp = world({ camps = { { "small", SMALL, 300, 5 } } })
	local extra = MakeNeutral({ x = SMALL.x, y = SMALL.y, hp = 300, maxhp = 300 })
	extra.dmg = 5
	local out = run(H, core, 330, function() if T > 301 then extra.hp = 0 end end)
	local start, ended = lines(out, "core_camp", "start")[1], lines(out, "core_camp", "end")[1]
	local clr, clrm, clre = tonumber(field(start, "clr")), tonumber(field(ended, "clrm")), tonumber(field(ended, "clre"))
	check("learn: the plan priced two neutrals, the engage one", clr ~= nil and clre ~= nil and clre < clr * 0.7, start, ended)
	local want = 1 + 0.3 * (clrm / clre - 1)
	check("learn: the pace moves on the measured clear over the engage price", clrm ~= nil and math.abs(H.CoreCamp.Pace(core) - want) < 0.02, H.CoreCamp.Pace(core), want)
end

-- The no-camp gate names why (smoke ~/.dotactl/logs/2026-11-05T19-50-59-core-missing_fn1.log, t=180-600: the pos3s pid 1
-- and 8 read h_camp on the gates line and never planned a camp; their nearest trip camp was the enemy off-lane large camp,
-- 1,400-2,300 from the front, held by the level gate at levels 2-5, removed 06/11/2026). One phase=nocamp line per minute
-- and reason.
local function offlaneWorld(pos)
	local H, core = world({ camps = { { "large", LARGE, 2400, 8 } }, level = 5 })
	SPAWNERS[1].team = 3
	H.Lane.Camps.ResetCache()
	TOWERS_W[2][dota.Tower.Bot1] = MakeUnit({ pid = 91, team = 2, loc = Vector(0, -5000) })
	core.pos = pos
	return H, core
end
do
	local saved = TOWERS_W[2][dota.Tower.Bot1]
	local H, core = offlaneWorld(3)
	local out = run(H, core, 303)
	local st = lines(out, "core_camp", "start")[1]
	check("offlane: a level 5 pos3 starts on the enemy large camp by its lane", st ~= nil and field(st, "camp") == "1" and field(st, "lvl") == "5", st)
	check("offlane: no nocamp line", #lines(out, "core_camp", "nocamp") == 0)
	H, core = offlaneWorld(1)
	local nc = lines(run(H, core, 303), "core_camp", "nocamp")
	check("nocamp: for a pos1 the enemy camp is not in the list (nwhy=list), none of its own", #nc == 1 and field(nc[1], "why") == "none" and field(nc[1], "ncand") == "0" and field(nc[1], "near") == "1" and field(nc[1], "nwhy") == "list" and field(nc[1], "lvl") == "5", nc[1])
	TOWERS_W[2][dota.Tower.Bot1] = saved
end

do
	local H, core = world({ camps = { { "small", Vector(0, -9500) } } })
	local nc = lines(run(H, core, 302), "core_camp", "nocamp")
	check("nocamp: an own camp past MaxCampDist of the front reads why=far", #nc == 1 and field(nc[1], "why") == "far" and field(nc[1], "cd") == "4500" and field(nc[1], "near") == nil, nc[1])
end

-- Review L3 (2fec253): a chained camp after a clear passes the start gates; held (an enemy unseen by the next camp, or one
-- visible on the walk to it), the core logs phase=nexthold with the gate and walks back. With no hold it chains (control).
local CAMP2 = Vector(-1200, -6200)
for _, case in ipairs({ "none", "missing", "threat" }) do
	local H, core, camp, enemy = world({ camps = { { "small", SMALL, 300, 5 }, { "small", CAMP2, 300, 5 } } })
	local out = run(H, core, 340, function()
		if not H.CoreCamp.Running(core) or camp[1].hp > 0 then return end
		if case == "missing" and LAST_SEEN[enemy.pid] == nil then
			enemy.hiddenFrom = { [OBSERVER] = true }
			LAST_SEEN[enemy.pid] = { location = Vector(-4000, -6200), time_since_seen = 10 }
		elseif case == "threat" then
			enemy.loc = Vector(-1500, -6500)
		end
	end)
	local nexts, holds, ended = lines(out, "core_camp", "next"), lines(out, "core_camp", "nexthold"), lines(out, "core_camp", "end")[1]
	if case == "none" then
		check("chain: with no hold the next camp is taken", #nexts == 1 and field(nexts[1], "camp") == "2" and #holds == 0, nexts[1] or ended)
	else
		check("chain " .. case .. ": the next camp is held, why=" .. case, #nexts == 0 and #holds == 1 and field(holds[1], "why") == case and field(holds[1], "camp") == "2" and field(holds[1], "after") == "cleared", holds[1] or nexts[1])
		check("chain " .. case .. ": the core walks back after the first camp", ended ~= nil and field(ended, "camps") == "1" and field(ended, "camp") == "1" and camp[2].hp > 0, ended)
		if case == "missing" then check("chain missing: nmiss, mtss and mpid on the hold", holds[1] ~= nil and field(holds[1], "nmiss") == "1" and field(holds[1], "mtss") == "10" and field(holds[1], "mpid") == "10", holds[1]) end
	end
end

finish()
