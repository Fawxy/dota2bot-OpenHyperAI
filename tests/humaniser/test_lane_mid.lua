dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local MID_FRONT = Vector(0, 0)

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or MID_FRONT })
	u.lane, u.pos, u.dmg = o.lane or Lane.Mid, o.pos, o.dmg
	return u
end

-- Radiant mid bot (pid 2, pos 2) alone in mid, wave in the middle of the lane (eqPos 0).
local function midWorld(skill, opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = skill })
	T = opts.t or 100
	CURRENT_TEAM = 2
	OBSERVER = 2
	NEXT_RUNE = opts.nextRune or 240
	SPAWNERS = {}
	H.Lane.Camps.ResetCache()
	local mid = unit({ pid = 2, pos = 2 })
	local enemy = unit({ pid = 7, team = 3, pos = 2 })
	return H, mid, enemy
end
local function setFronts(enemy, ours, theirs)
	LANE_FRONT[2][Lane.Mid], LANE_FRONT[3][Lane.Mid] = ours, theirs
	enemy.loc = GetLaneFrontLocation(2, Lane.Mid, 0)
end
local function plan(H, bot) return H.Lane.LanePlanner.Plan(bot, H.Lane.LaneState.ForBot(bot)) end
local function desc(c) return c.tech .. " (" .. c.reason .. ")" end

do
	local H = midWorld(0.9)
	local M = H.Lane.LaneMid
	check("window opens 20 s before the rune", M.IsPreRuneWindow(222, 240))
	check("not yet 21 s out", not M.IsPreRuneWindow(219, 240))
	check("window closes at 14 s out", not M.IsPreRuneWindow(226, 240))
	T = 222
	check("mid lane in the window", M.IsPreRune(2, Lane.Mid))
	check("other lanes never pre-rune", not M.IsPreRune(2, Lane.Top))
	local H2 = LaneFresh({ Enable = true, Mid = false }, { skill = 0.9 })
	NEXT_RUNE, T = 240, 222
	check("Mid flag off disables the window", not H2.Lane.LaneMid.IsPreRune(2, Lane.Mid))
end

do
	local H, mid = midWorld(0.5, { t = 222 })
	local s = H.Lane.LaneState.ForBot(mid)
	check("pre-rune desired eq", near(s.desiredEq, 0.15), s.desiredEq)
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	local c = plan(H, mid)
	check("shove inside the pre-rune window", c.tech == "shove" and c.reason == "shove before rotating", desc(c))

	H, mid = midWorld(0.5, { t = 210 })
	check("desired eq outside the window", near(H.Lane.LaneState.ForBot(mid).desiredEq, -0.1))
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	c = plan(H, mid)
	check("no shove outside the window", c.tech ~= "shove", desc(c))

	H, mid = midWorld(0.39, { t = 222 })
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	c = plan(H, mid)
	check("below the shove gate nothing shoves", c.tech ~= "shove", desc(c))
end

do
	local H, mid = midWorld(0.9, { t = 217 })
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	local c = plan(H, mid)
	check("window not open yet", c.tech ~= "shove", desc(c))
	T = 220.5
	c = plan(H, mid)
	check("entering the window mid-cycle shoves at once", c.tech == "shove" and c.reason == "shove before rotating", desc(c))
end

do
	local H, mid = midWorld(0.9)
	local M = H.Lane.LaneMid
	mid.dmg = 400
	local melee = MakeCreep({ team = 2, x = 50, y = 0, hp = 20 })
	local ranged = MakeCreep({ team = 2, x = 60, y = 0, hp = 25, name = "npc_dota_creep_goodguys_ranged" })
	check("deniable ranged creep before a deniable melee one", M.PickDeny(mid, { melee, ranged }) == ranged)
	ranged.hp = 330
	check("healthy ranged creep is left; melee is the Lua fallback's call", M.PickDeny(mid, { melee, ranged }) == nil)
	ranged.hp = 25
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot })
	support.dmg = 400
	check("non-mid bots never use mid deny control", M.PickDeny(support, { melee, ranged }) == nil)
end

do
	local H, mid = midWorld(0.9)
	local M = H.Lane.LaneMid
	local human = unit({ pid = 3, pos = 2, bot = false })
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(300, 0) })
	local creep = MakeCreep({ team = 3, x = 100, y = 0 })
	check("support hands off a human mid's wave", M.MayTouchWave(support, creep) == false)
	check("the mid bot itself may touch it", M.MayTouchWave(mid, creep) == true)
	local gone = MakeCreep({ team = 3, x = 100, y = 0 })
	RemoveCreep(gone)
	local ok, err = pcall(M.MayTouchWave, support, gone)
	check("a removed creep handle does not throw", ok, err)
	-- console.9057163106: 50 throws with IsNull guarded; the engine lists creeps out of sight with no location.
	local unseen = MakeCreep({ team = 3, x = 100, y = 0 })
	unseen.unseen = true
	ok, err = pcall(M.MayTouchWave, support, unseen)
	check("a creep with no location does not throw", ok, err)
	T = 700
	LANING = false
	check("after laning anyone may touch it", M.MayTouchWave(support, creep) == true)
	LANING = nil
	T = 100
	human.loc = Vector(0, 3000)
	H.Lane.LaneState.ResetCache()
	check("human away from the wave", M.MayTouchWave(support, creep) == true)
	human.loc = MID_FRONT
	H.Lane.LaneState.ResetCache()
	check("human back", M.MayTouchWave(support, creep) == false)
	local far = MakeCreep({ team = 3, x = 2000, y = 0 })
	check("a creep away from the mid front is fair game", M.MayTouchWave(support, far) == true)
	human.bot = true
	H.Lane.LaneState.ResetCache()
	check("a bot mid is not protected", M.MayTouchWave(support, creep) == true)
end

-- Hands-off: a bot-lane bot whose own lane is active, with a creep of a human mid's wave among the creeps it was handed.
local BOT_Y = LANE_Y[Lane.Bot]
local function botLaneWorld(humanMid, opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true, Mid = opts.mid }, { skill = 0.8 })
	T, CURRENT_TEAM = opts.t or 5, 2
	LANE_FRONT[2][Lane.Bot] = 4000 / 14000
	local bot = unit({ pid = 1, pos = 1, lane = Lane.Bot, loc = Vector(-2800, BOT_Y) })
	if humanMid then unit({ pid = 3, pos = 2, bot = false }) end
	local midCreep = MakeCreep({ team = 3, x = 100, y = 0 })
	return H, bot, midCreep
end
local function blockWorld(humanMid, opts)
	local H, bot, midCreep = botLaneWorld(humanMid, opts)
	MakeCreep({ team = 2, x = -3000, y = BOT_Y })
	MakeCreep({ team = 2, x = -3100, y = BOT_Y })
	MakeCreep({ team = 3, x = 3000, y = BOT_Y })
	return H, bot, midCreep
end
local function shoveWorld(humanMid, opts)
	opts = opts or {}
	opts.t = 95
	local H, bot, midCreep = botLaneWorld(humanMid, opts)
	STRONGER = true
	LANE_FRONT[2][Lane.Bot] = 0.5
	bot.loc = Vector(-200, BOT_Y)
	H.Lane.Hooks.SetRotationProbe(function() return true end)
	local creeps = { MakeCreep({ team = 3, x = 100, y = BOT_Y, hp = 300 }), MakeCreep({ team = 3, x = 200, y = BOT_Y, hp = 400 }), midCreep }
	return H, bot, creeps
end
local function actions(pid) return #ActionsOf(pid) end

do
	local H, bot, midCreep = blockWorld(false)
	check("control: a bot-lane bot blocks at 0:05", H.Lane.PreThink(bot, {}, { midCreep }, {}) == true and actions(1) > 0)
	H, bot, midCreep = blockWorld(true)
	check("PreThink stands down beside a human mid's wave", H.Lane.PreThink(bot, {}, { midCreep }, {}) == false and actions(1) == 0)
	H, bot, midCreep = blockWorld(true, { mid = false })
	check("Mid flag off leaves PreThink alone", H.Lane.PreThink(bot, {}, { midCreep }, {}) == true)
end

do
	local H, bot, creeps = shoveWorld(false)
	check("control: the shove runs", H.Lane.Think(bot, {}, creeps, {}) == true and #ActionsOf(1, "AttackUnit") > 0)
	H, bot, creeps = shoveWorld(true)
	check("Think stands down when any creep is a human mid's", H.Lane.Think(bot, {}, creeps, {}) == false and actions(1) == 0)
	H, bot, creeps = shoveWorld(true, { mid = false })
	check("Mid flag off leaves Think alone", H.Lane.Think(bot, {}, creeps, {}) == true)
end

do
	-- Shot by the Dire bot T1 with a human mid's creep among the enemy creeps it was handed: the drop still runs.
	local H, bot, midCreep = botLaneWorld(true, { t = 100 })
	LANE_FRONT[2][Lane.Bot] = 0.6
	bot.loc = Vector(2200, BOT_Y)
	local ownCreep = MakeCreep({ team = 2, x = 2150, y = BOT_Y })
	TOWERS_W[3][dota.Tower.Bot1].target = bot
	check("precondition: the human mid's wave is off limits", H.Lane.LaneMid.MayTouchWave(bot, midCreep) == false)
	check("tower-aggro drop runs beside a human mid's wave", H.Lane.PreThink(bot, { ownCreep }, { midCreep }, {}) == true
		and #ActionsOf(1, "AttackUnit") == 1 and ActionsOf(1, "AttackUnit")[1].args[1] == ownCreep)
	TOWERS_W[3][dota.Tower.Bot1].target = nil
	T = 100.1
	bot.loc = Vector(1500, BOT_Y)
	check("nothing else runs beside the human mid's wave", H.Lane.PreThink(bot, { ownCreep }, { midCreep }, {}) == false and #ActionsOf(1) == 1)
end

-- Same wave, same human mid: the bot assigned mid keeps acting while the passing support stands down.
do
	local H = LaneFresh({ Enable = true }, { skill = 0.8 })
	T, CURRENT_TEAM = 5, 2
	unit({ pid = 3, pos = 2, bot = false })
	local midBot = unit({ pid = 4, pos = 4, loc = Vector(-300, 0) })
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(-300, 0) })
	local blockers = { MakeCreep({ team = 2, x = -100, y = 0 }), MakeCreep({ team = 2, x = -200, y = 0 }) }
	local far = MakeCreep({ team = 3, x = 3000, y = 0 })
	local mid1 = MakeCreep({ team = 3, x = 900, y = 0 })
	check("precondition: the human mid protects this wave from the support", H.Lane.LaneMid.MayTouchWave(support, mid1) == false)
	check("mid bot still blocks at 0:05 beside the human", H.Lane.PreThink(midBot, blockers, { mid1, far }, {}) == true and #ActionsOf(4) > 0)
	check("support issues nothing for the same wave", H.Lane.PreThink(support, blockers, { mid1 }, {}) == false and #ActionsOf(5) == 0)
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.8 })
	T, CURRENT_TEAM, STRONGER = 95, 2, true
	H.Lane.Hooks.SetRotationProbe(function() return true end)
	unit({ pid = 3, pos = 2, bot = false })
	local midBot = unit({ pid = 2, pos = 2, loc = Vector(-200, 0) })
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(-200, 0) })
	local creeps = { MakeCreep({ team = 3, x = 100, y = 0, hp = 300 }), MakeCreep({ team = 3, x = 200, y = 0, hp = 400 }) }
	check("mid bot still shoves beside the human", H.Lane.Think(midBot, {}, creeps, {}) == true and #ActionsOf(2, "AttackUnit") > 0)
	check("support does not shove the human's wave", H.Lane.Think(support, {}, creeps, {}) == false and #ActionsOf(5) == 0)
end

do
	local H, mid = midWorld(0.8, { t = 5 })
	unit({ pid = 3, pos = 2, bot = false })
	local creep = MakeCreep({ team = 3, x = 100, y = 0 })
	local allyCreeps = { MakeCreep({ team = 2, x = 50, y = 0 }) }
	check("the mid bot itself may deny", H.Lane.MayDeny(mid, allyCreeps) == true)
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(300, 0) })
	check("a passing support may not deny a human mid's wave", H.Lane.MayDeny(support, allyCreeps) == false)
	check("no creeps, nothing to deny", H.Lane.MayDeny(support, {}) == true)
	local top = MakeCreep({ team = 2, x = 0, y = 5000 })
	check("a creep in another lane is fair game", H.Lane.MayDeny(support, { top }) == true)
end

do
	local src = io.open(HARNESS_DIR .. "/../../bots/mode_laning_generic.lua", "r"):read("a")
	check("laning mode asks Lane.MayDeny before denying", src:find("Lane.MayDeny(bot, nAllyCreeps)", 1, true) ~= nil)
end

local MID_CAMP = { team = 2, type = "small", location = Vector(-2800, 400, 0), min = Vector(-2950, 250, 0),
	max = Vector(-2650, 550, 0), speed = 0 }

do
	local H, mid, enemy = midWorld(0.9)
	SPAWNERS = { MID_CAMP }
	H.Lane.Camps.ResetCache()
	check("seed data has no mid pull camp", not H.Lane.LaneMid.MidPullAllowed(2))
	setFronts(enemy, 0.64, 0.36)
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	local c = plan(H, mid)
	check("planner never pulls mid from seed data", c.tech == "aggro_pull" and c.reason == "small correction", desc(c))
end

-- A mid pull camp injected into the data, wave 0.7 or 0.9 of the way to the enemy tower.
local function campPlan(ours, theirs)
	local H, mid, enemy = midWorld(0.9)
	local data = require("bots/FunLib/humaniser/camps_data")
	table.insert(data.CAMP_DATA, { key = "mid_test", team = 2, type = "small", laneKind = "mid", pullAggroSec = { 15, 45 }, source = "seed" })
	SPAWNERS = { MID_CAMP }
	H.Lane.Camps.ResetCache()
	check("precondition: injected mid pull camp", H.Lane.LaneMid.MidPullAllowed(2))
	setFronts(enemy, ours, theirs)
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	return plan(H, mid)
end

do
	local c = campPlan(0.68, 0.32)
	check("wave at the enemy tower aggro-pulls", c.tech == "aggro_pull" and c.reason == "mid: out of tower range", desc(c))
	c = campPlan(0.64, 0.36)
	check("short of the tower range the camp pull decides", c.tech == "full_pull", desc(c))
end

-- mode_rune_generic keeps its old rule: odd minute and second > 53 is the same as under 7 s to the next even minute.
do
	local src = io.open(HARNESS_DIR .. "/../../bots/FunLib/jmz_func.lua", "r"):read("a")
	local body = src:match("function J%.GetNextPowerRuneSpawnTime%(%)(.-)\nend\n")
	check("helper present in jmz_func", body ~= nil)
	local J = {}
	local fn = load("local J = ... ; return function()" .. body .. " end")
	local nextRune = fn(J)
	local runeSrc = io.open(HARNESS_DIR .. "/../../bots/mode_rune_generic.lua", "r"):read("a")
	check("rune mode uses the shared helper", runeSrc:find("J.GetNextPowerRuneSpawnTime() - DotaTime() < 7", 1, true) ~= nil)
	local mismatch
	for tenth = 601, 12000 do
		T = tenth / 10
		local minute, second = math.floor(T / 60), T % 60
		local old = (minute % 2 == 1 and second > 53)
		local new = (nextRune() - DotaTime() < 7)
		if old ~= new then mismatch = T break end
	end
	check("rune mode window identical to the old rule", mismatch == nil, mismatch)
	T = 30
	check("before 2:00 the next rune is 2:00", nextRune() == 120)
end

finish()
