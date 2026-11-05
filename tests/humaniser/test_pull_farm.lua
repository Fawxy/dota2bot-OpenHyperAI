dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice support-pull-farm: PullFarm (Ours.SupportPullFarm), the support clearing the camp it pulled into, and its hand-off to a core's
-- camp trip. Built on test_pull_job's world: the pull runs for real (a wave of four on one neutral), then the farm follows.

local dota = require("bots/ts_libs/dota/index")
local Lane, FARM, LANING = dota.Lane, dota.BotMode.Farm, dota.BotMode.Laning

-- As test_lane_pull_timing: Radiant bot lane along y = -5000, the small camp south of it, wave-timed pulls at 300 speed.
local SMALL = Vector(-1600, -6200)
local PATH = { { -9400, -5000 }, { 7000, -5000 } }

-- The camp's box out of our team's sight (an empty box then says nothing about the camp), as in lane before a ward or a
-- puller is near; `visible` worlds see it.
local function campFog(v) return math.abs(v.x - SMALL.x) < 600 and math.abs(v.y - SMALL.y) < 600 end

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
	for _, l in ipairs(all) do if l:find("ev=" .. ev .. " ", 1, true) then table.insert(r, l) end end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

-- `reading`: what LanePush.Read returns (nil: no clash); `reads` counts the calls.
local function world(o)
	o = o or {}
	package.loaded["bots/FunLib/engine/tasks"] = nil
	local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, LiveEvery = o.liveEvery } },
		{ skill = 1, telemetry = { Enable = true }, supportPull = o.on ~= false })
	T = o.t or 61
	for k in pairs(NEUTRALS) do NEUTRALS[k] = nil end
	FOGGED = not o.visible and campFog or nil
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { { team = 2, type = "small", location = SMALL, min = Vector(SMALL.x - 150, SMALL.y - 150, 0),
		max = Vector(SMALL.x + 150, SMALL.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	H.PullJob.ResetCache()
	H.PullFarm.ResetCache()
	H.CampClaims.ResetCache()
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportPullFarm = o.farm ~= false
	local data = H.Lane.Camps.ByIdx(1)
	local stand = H.Lane.Camps.BoxEdgePoint(H.Lane.Camps.SpawnerByIdx(1), data.pull.path[1], 150)
	local sup = MakeUnit({ pid = 5, team = 2, bot = true, loc = o.supAt or Vector(stand.x + 600, stand.y), hp = o.supHp or 600, maxhp = 600 })
	sup.lane, sup.pos = Lane.Bot, 5
	getmetatable(sup).__index.GetNetWorth = function(self) return self.gold or 0 end
	local core = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000), hp = o.coreHp })
	core.lane, core.pos = Lane.Bot, 1
	local P = package.loaded["bots/FunLib/humaniser/lane_push"]
	local w = { H = H, sup = sup, core = core, reads = 0, stand = stand }
	P.Read = function()
		w.reads = w.reads + 1
		return o.reading
	end
	return w
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- A frame: moves teleport; an attack order on a neutral takes 1,000 HP a second off it (a kill in under a second).
local function frame(w, dt)
	dt = dt or 0.1
	local H, bot = w.H, w.sup
	local n0 = #ACTIONS
	if H.Chooser.Gate(bot, "farm", function() return 0 end)() > 0 then
		bot.mode = FARM
		H.Chooser.HostThink(bot, "farm", function() return false end, function() return false end)()
	else
		bot.mode = LANING
	end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "MoveToLocation" then bot.loc = Vector(a.args[1].x, a.args[1].y) break end
		if a.pid == bot.pid and a.kind == "AttackUnit" and H.PullFarm.Running(bot) then bot.loc = Vector(a.args[1].loc.x + 100, a.args[1].loc.y) bot.hitting = a.args[1] break end
	end
	if bot.hitting ~= nil then
		bot.hitting.hp = math.max(0, bot.hitting.hp - 1000 * dt)
		if bot.hitting.hp == 0 then bot.hitting = nil end
	end
	T = T + dt
end

local function run(w, untilT) return capture(function() while T < untilT do frame(w) end end) end

local OUT = { state = "OUT", clash = 9000, move = 640, q = 0.7, tower = false, cf = -420, ms = 3.1 }

-- A pull that ends ok with `left` neutrals still on the camp. Returns the world, the output so far and the neutrals.
local function afterPull(o)
	o = o or {}
	local w = world({ reading = OUT, farm = o.farm, visible = true })
	local neutrals = {}
	for i = 1, o.left or 2 do neutrals[i] = MakeNeutral({ x = SMALL.x + 20 * i, y = SMALL.y, hp = 300, maxhp = 300 }) end
	neutrals[1].target = w.sup
	local wave, ended = {}, nil
	local all = {}
	local function take(out) for _, l in ipairs(out) do table.insert(all, l) end end
	take(capture(function()
		while T < 140 and ended == nil do
			frame(w)
			if #wave == 0 and w.H.PullJob.Running(w.sup) then
				for i = 1, 4 do wave[i] = MakeCreep({ team = 2, x = 0, y = 0 }) end
				wave[1].target = neutrals[1]
			end
			for _, c in ipairs(wave) do c.loc = Vector(w.sup.loc.x, w.sup.loc.y) end
			if #wave > 0 and not w.H.PullJob.Running(w.sup) then ended = T end
		end
	end))
	return w, all, neutrals, ended, take
end

-- The pull ended ok with neutrals left and nothing near: the support starts on the camp, kills them and walks back to lane.
do
	local w, all, neutrals, ended, take = afterPull()
	check("farm: the pull ended ok", ended ~= nil and #lines(all, "job") >= 2)
	take(run(w, ended + 40))
	local start, fin = lines(all, "pull_clear")[1], nil
	for _, l in ipairs(lines(all, "pull_clear")) do if field(l, "phase") == "end" then fin = l end end
	check("farm: started within seconds of the pull's end on its camp, two neutrals left", start ~= nil and field(start, "phase") == "start"
		and field(start, "camp") == "1" and field(start, "n0") == "2" and tonumber(field(start, "ago")) <= 1, start)
	check("farm: both neutrals killed", neutrals[1].hp == 0 and neutrals[2].hp == 0)
	check("farm: ended back at the lane front with nothing left", fin ~= nil and field(fin, "why") == "back" and field(fin, "nl") == "0" and field(fin, "died") == "0", fin)
	check("farm: the claim is released at the end", w.H.CampClaims.On("pullfarm", 1) == nil)
end

-- Off: the support goes back to lane after the pull, no farm line.
do
	local w, all, _, ended, take = afterPull({ farm = false })
	take(run(w, ended + 20))
	check("off: no pull_clear line and no farm job", #lines(all, "pull_clear") == 0 and not w.H.PullFarm.Running(w.sup))
end

-- A core's camp trip is already on the camp: the support gives it up (a skip line naming it), the core's claim is not disturbed.
do
	local w = world({ reading = OUT, visible = true })
	w.H.CampClaims.Set("core", 1, 1)
	local neutrals = { MakeNeutral({ x = SMALL.x, y = SMALL.y, hp = 300, maxhp = 300 }), MakeNeutral({ x = SMALL.x + 20, y = SMALL.y, hp = 300, maxhp = 300 }) }
	neutrals[1].target = w.sup
	local wave, ended = {}, nil
	local all = {}
	for _, l in ipairs(capture(function()
		while T < 140 and ended == nil do
			frame(w)
			if #wave == 0 and w.H.PullJob.Running(w.sup) then
				for i = 1, 4 do wave[i] = MakeCreep({ team = 2, x = 0, y = 0 }) end
				wave[1].target = neutrals[1]
			end
			for _, c in ipairs(wave) do c.loc = Vector(w.sup.loc.x, w.sup.loc.y) end
			if #wave > 0 and not w.H.PullJob.Running(w.sup) then ended = T end
		end
		while T < ended + 20 do frame(w) end
	end)) do table.insert(all, l) end
	local skip = lines(all, "pull_clear")[1]
	check("core coming: one skip line why=core-coming, no start", skip ~= nil and field(skip, "phase") == "skip" and field(skip, "why") == "core-coming" and #lines(all, "pull_clear") == 1, skip)
	check("core coming: the neutrals are left to the core", neutrals[1].hp == 300 and neutrals[2].hp == 300)
end

-- A core's trip begins mid-farm: the support ends the farm `interrupted:yield` and the camp is the core's.
do
	local w, all, neutrals, ended, take = afterPull({ left = 3 })
	for _, n in ipairs(neutrals) do n.hp = 100000 end
	take(run(w, ended + 4))
	check("yield: the farm is running before the core comes", w.H.PullFarm.Running(w.sup))
	w.H.CampClaims.Set("core", 1, 1)
	take(run(w, T + 1))
	local fin
	for _, l in ipairs(lines(all, "pull_clear")) do if field(l, "phase") == "end" then fin = l end end
	check("yield: the farm ended interrupted:yield with neutrals left", fin ~= nil and field(fin, "why") == "interrupted:yield" and tonumber(field(fin, "nl")) >= 1, fin)
	check("yield: the claim is released", w.H.CampClaims.On("pullfarm", 1) == nil)
end

-- An enemy hero by the camp: no start, one skip line naming the threat.
do
	local w = world({ reading = OUT, visible = true })
	local neutrals = { MakeNeutral({ x = SMALL.x, y = SMALL.y, hp = 300, maxhp = 300 }), MakeNeutral({ x = SMALL.x + 20, y = SMALL.y, hp = 300, maxhp = 300 }) }
	neutrals[1].target = w.sup
	local enemy = MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) })
	enemy.pos = 3
	local wave, ended = {}, nil
	local all = {}
	for _, l in ipairs(capture(function()
		while T < 140 and ended == nil do
			frame(w)
			if #wave == 0 and w.H.PullJob.Running(w.sup) then
				for i = 1, 4 do wave[i] = MakeCreep({ team = 2, x = 0, y = 0 }) end
				wave[1].target = neutrals[1]
			end
			for _, c in ipairs(wave) do c.loc = Vector(w.sup.loc.x, w.sup.loc.y) end
			if #wave > 0 and not w.H.PullJob.Running(w.sup) then ended = T end
		end
		enemy.loc = Vector(SMALL.x + 900, SMALL.y + 300)
		while T < ended + 20 do frame(w) end
	end)) do table.insert(all, l) end
	local pc = lines(all, "pull_clear")
	check("enemy by the camp: no farm, one skip naming why", #pc == 1 and field(pc[1], "phase") == "skip" and (field(pc[1], "why") == "threat" or field(pc[1], "why") == "enemy-near"), pc[1])
end

finish()
