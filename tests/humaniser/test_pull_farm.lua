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

local OUT = { state = "OUT", clash = 9000, move = 640, q = 0.7, own = 3160, tower = false, ms = 3.1 }

-- A pull that ends ok with `left` neutrals still on the camp. Returns the world, the output so far and the neutrals.
local function afterPull(o)
	o = o or {}
	local w = world({ reading = OUT, farm = o.farm, visible = true })
	if o.pos ~= nil then w.sup.pos = o.pos end
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

-- Madstone (user 06/11/2026: "they should pick up the madstone after if they do the support-pull-farm routine"): a drop by
-- the cleared camp is picked up before the walk back; an item of another name or one far from the camp is left.
do
	local w, all, neutrals, ended, take = afterPull()
	local stone = { item = { GetName = function() return "item_madstone_bundle" end }, location = Vector(SMALL.x + 100, SMALL.y) }
	local other = { item = { GetName = function() return "item_branches" end }, location = Vector(SMALL.x - 100, SMALL.y) }
	local far = { item = { GetName = function() return "item_madstone_bundle" end }, location = Vector(SMALL.x + 3000, SMALL.y) }
	DROPPED = { stone, other, far }
	local picked = {}
	take(capture(function()
		while T < ended + 40 do
			local n0 = #ACTIONS
			frame(w)
			for i = n0 + 1, #ACTIONS do
				local a = ACTIONS[i]
				if a.pid == w.sup.pid and a.kind == "PickUpItem" then
					table.insert(picked, a.args[1])
					for j = #DROPPED, 1, -1 do if DROPPED[j].item == a.args[1] then table.remove(DROPPED, j) end end
				end
			end
		end
	end))
	DROPPED = {}
	local fin
	for _, l in ipairs(lines(all, "pull_clear")) do if field(l, "phase") == "end" then fin = l end end
	check("madstone: the drop by the camp picked up, nothing else", #picked >= 1 and picked[1] == stone.item and #lines({}, "x") == 0
		and (function() for _, it in ipairs(picked) do if it ~= stone.item then return false end end return true end)(), #picked)
	check("madstone: the end line counts one seen, one picked, and the walk back still ends it", fin ~= nil and field(fin, "ms") == "1"
		and field(fin, "mp") == "1" and field(fin, "why") == "back", fin)
end

-- The kills (user 06/11/2026: the hero that finishes a camp gets its madstone when close enough, else it drops and is often
-- contested; the support takes the last hits, at least the camp's last neutral). The pulled wave drains each neutral at
-- 100 HP/s; the support's hit (200) would leave it to the wave if it attacked at once, so the clear waits in range for the
-- hit that kills (the engine's lastHit) and the kill is credited to it. The pull tweaks come from the bug-hunt log
-- C:\Users\Chris\.dotactl\logs\2026-11-05T18-13-16-bug-hunt_observe_team-bots_e3fcbd4.log (marks 13 and 16).
local function lastHits(o)
	o = o or {}
	local w, all, neutrals, ended, take = afterPull({ pos = o.pos })
	w.sup.dmg = 200
	w.sup.GetAttackPoint = function() return 0.3 end
	if o.lastHit == false then w.H.PullFarm.SETTINGS.LastHit = false end
	local wave = {}
	for i = 1, 3 do wave[i] = MakeCreep({ team = 2, x = SMALL.x, y = SMALL.y }) end
	local function alive(n) return n.hp > 0 end
	local pending = {}
	take(capture(function()
		while T < ended + 40 do
			-- The wave turns onto the first neutral alive.
			local on
			for _, n in ipairs(neutrals) do if alive(n) then on = n break end end
			for _, c in ipairs(wave) do c.target = on end
			if on ~= nil and alive(on) then on.hp = math.max(0, on.hp - 100 * 0.1) end
			-- The support's attacks as hits: each attack order on a neutral lands its 200 0.3 s later (frame's own drain on
			-- the neutral is undone); a hit that takes it to 0 is the support's last hit.
			local before = {}
			for i, n in ipairs(neutrals) do before[i] = n.hp end
			local n0 = #ACTIONS
			frame(w)
			w.sup.hitting = nil
			for i, n in ipairs(neutrals) do n.hp = before[i] end
			for i = n0 + 1, #ACTIONS do
				local a = ACTIONS[i]
				if a.pid == w.sup.pid and a.kind == "AttackUnit" then table.insert(pending, { n = a.args[1], at = T + 0.3 }) end
			end
			for i = #pending, 1, -1 do
				local h = pending[i]
				if T >= h.at then
					table.remove(pending, i)
					if h.n.hp > 0 then
						h.n.hp = math.max(0, h.n.hp - w.sup.dmg)
						if h.n.hp == 0 then w.sup.lh = (w.sup.lh or 0) + 1 end
					end
				end
			end
		end
	end))
	w.H.PullFarm.SETTINGS.LastHit = true
	local fin
	for _, l in ipairs(lines(all, "pull_clear")) do if field(l, "phase") == "end" then fin = l end end
	return fin, neutrals
end
do
	local fin, neutrals = lastHits()
	check("last hit: both neutrals dead and the clear ended back in lane", neutrals[1].hp == 0 and neutrals[2].hp == 0 and fin ~= nil
		and field(fin, "why") == "back", fin)
	check("last hit: the clear waited for the killing hit and took both kills, the final neutral's included", fin ~= nil
		and tonumber(field(fin, "lt") or "0") >= 2 and field(fin, "lk") == "2" and field(fin, "lh") == "2" and field(fin, "fl") == "1"
		and tonumber(field(fin, "fd")) <= 650, fin)
	check("last hit: the end line counts madstone charges gained (none here)", fin ~= nil and field(fin, "mi") == "0", fin)
	local off = lastHits({ lastHit = false })
	check("last hit off: no wait for the killing hit (lt absent)", off ~= nil and field(off, "lt") == nil, off)
end

-- A lone pos4 is its lane's puller (PullJob pullerOfLane; the off-lane's large camp is its pull camp, camps_data
-- *_off_large): the clear and its kills apply to it as to a pos5.
do
	local fin = lastHits({ pos = 4 })
	check("pos4 puller: the clear ran and took the final kill", fin ~= nil and field(fin, "pos") == "4" and field(fin, "fl") == "1", fin)
end

finish()
