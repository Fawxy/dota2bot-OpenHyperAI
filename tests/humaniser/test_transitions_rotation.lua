-- Support power-rune rotations (task 12, Task 4): pos 4 / pos 5 leave lane for the power rune near our mid.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode, Rune = dota.Lane, dota.BotMode, dota.Rune

-- The top power spot is nearest the top lane, the bottom one nearest the bottom lane; both 2,121 from our mid.
local TOP_SPOT, BOT_SPOT = Vector(-1500, 1500), Vector(1500, -1500)
local SPOT = { [Rune.Power1] = TOP_SPOT, [Rune.Power2] = BOT_SPOT }
function GetRuneSpawnLocation(r) return SPOT[r] or Vector(-9000, 9000) end

local TOP, MID, BOT = Vector(0, 5000), Vector(0, 0), Vector(0, -5000)
-- From either lane front to its spot: 3,808 * 1.2 / 300 = 15.23 s, so a jitter-free leave is at 340.77.
local LEAVE = 360 - 4 - math.sqrt(1500 ^ 2 + 3500 ^ 2) * 1.2 / 300

-- One decision draws: the rotate roll, two Gauss draws (0.5, 0.25 give a jitter of ~0), the mistake roll.
local PASS = { 0, 0.5, 0.25, 0.9 }
local FAIL = { 0.95, 0.5, 0.25, 0.9 }
local function rolls(...)
	local r = {}
	for _, list in ipairs({ ... }) do for _, v in ipairs(list) do table.insert(r, v) end end
	SetRandomSequence(r)
end

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc, hp = o.hp })
	u.lane, u.pos, u.mode = o.lane, o.pos, 0
	return u
end

-- A Radiant team: a human carry and a pos 5 bottom, our mid, the offlaner and a pos 4 top.
local function world(opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = opts.skill or 0.9, transitions = opts.transitions or { Enable = true } })
	T = opts.T or 335
	CURRENT_TEAM = 2
	local w = { H = H, R = H.Transitions.Rotation, said = {} }
	w.carry = hero({ pid = 1, bot = false, pos = 1, lane = Lane.Bot, loc = BOT })
	w.mid = hero({ pid = 2, pos = 2, lane = Lane.Mid, loc = MID })
	w.off = hero({ pid = 3, pos = 3, lane = Lane.Top, loc = TOP })
	w.p4 = hero({ pid = 4, pos = 4, lane = Lane.Top, loc = TOP })
	w.p5 = hero({ pid = 5, pos = 5, lane = Lane.Bot, loc = BOT })
	H.Orders.SetAnnouncer(function(_, key) table.insert(w.said, key) end)
	-- Profiles draw randoms when first built; build them now so the queued rolls reach the decision.
	for _, u in ipairs({ w.carry, w.mid, w.off, w.p4, w.p5 }) do H.Lane.Config.SkillOf(u) end
	return w
end

local function count(list, key)
	local n = 0
	for _, v in ipairs(list) do if v == key then n = n + 1 end end
	return n
end

do
	local w = world()
	rolls(PASS)
	local d = w.R.Decide(w.p4, 335)
	check("pos 4 rotates when idle and lane stable", d.go == true, d.reason)
	check("pos 4 leaves in time for the spawn", d.leaveAt ~= nil and d.leaveAt >= 335 and d.leaveAt <= 356, d.leaveAt)
	check("pos 4 leaves 4 s plus the travel before the spawn", d.leaveAt ~= nil and math.abs(d.leaveAt - LEAVE) < 1e-3, d.leaveAt)
	check("pos 4 heads for the spot nearest its lane", d.side == "top", d.side)
	check("pos 4 announces once it decides", w.H.Transitions.Tick(w.p4) == nil and count(w.said, "say_rune_coming_mid") == 1, #w.said)
	T = 336
	w.H.Transitions.Tick(w.p4)
	check("the announce is once per spawn", count(w.said, "say_rune_coming_mid") == 1)
end

do
	local w = world()
	w.p4.hp = 40
	rolls(PASS)
	local d = w.R.Decide(w.p4, 335)
	check("pos 4 skips when busy", d.go == false and d.reason == "hp", d.reason)
end

do
	local w = world()
	rolls(FAIL)
	local all = true
	for i = 0, 9 do
		if i == 1 then rolls(PASS) end
		if w.R.Decide(w.p4, 335 + i * 0.5).go then all = false end
	end
	check("rotation chance is rolled once per spawn", all)
end

do
	local w = world()
	rolls(PASS, PASS)
	check("pos 4 going (precondition)", w.R.Decide(w.p4, 335).go == true)
	local d = w.R.Decide(w.p5, 335)
	check("pos 5 stays when pos 4 is going", d.go == false and d.reason == "pos4 going", d.reason)

	w = world()
	MakeUnit({ pid = 10, team = 3, loc = Vector(1400, -1400) })
	MakeUnit({ pid = 11, team = 3, loc = Vector(1600, -1600) })
	rolls(PASS, PASS)
	w.R.Decide(w.p4, 335)
	d = w.R.Decide(w.p5, 335)
	check("pos 5 joins when 2 enemies are seen near its spot", d.go == true and d.side == "bot", d.reason)
end

do
	local w = world()
	w.H.Lane.CampJobs.Active = function(u) return u:GetPlayerID() == 4 end
	rolls(PASS, PASS)
	local d = w.R.Decide(w.p5, 335)
	check("pos 4 in a camp job does not go", w.R.Decide(w.p4, 335).reason == "job", w.R.Decide(w.p4, 335).reason)
	check("pos 5 rotates when pos 4 is busy", d.go == true, d.reason)

	w = world()
	w.H.Lane.CampJobs.Active = function(u) return u:GetPlayerID() == 4 end
	MakeUnit({ pid = 10, team = 3, loc = Vector(1000, -5000) })
	rolls(PASS, PASS)
	d = w.R.Decide(w.p5, 335)
	check("pos 5 stays with an enemy 1,000 from the carry", d.go == false and d.reason == "enemy near", d.reason)
end

do
	local w = world({ T = 215 })
	rolls(PASS)
	local d = w.R.Decide(w.p4, 215)
	check("no rotation before 6:00", d.go == false, d.reason)
	check("no rotation before 6:00: nothing is rolled", RandomUnread() == 4, RandomUnread())
end

do
	local w = world()
	rolls(PASS)
	w.H.Transitions.Tick(w.p4)
	for i = 0, 2 do MakeUnit({ pid = 10 + i, team = 3, loc = Vector(-1500 + 100 * i, 1500) }) end
	T = 350
	w.H.Transitions.Tick(w.p4)
	check("contest aborts when outnumbered", w.R.Active(w.p4) == nil)
	check("contest abort announces the rune lost once", count(w.said, "say_rune_lost") == 1, #w.said)
	T = 351
	w.H.Transitions.Tick(w.p4)
	check("rune lost is said once", count(w.said, "say_rune_lost") == 1)
end

do
	-- Two seen enemies against the support and our mid: not outnumbered.
	local w = world()
	rolls(PASS)
	w.H.Transitions.Tick(w.p4)
	for i = 0, 1 do MakeUnit({ pid = 10 + i, team = 3, loc = Vector(-1500 + 100 * i, 1500) }) end
	T = 350
	w.H.Transitions.Tick(w.p4)
	check("even contest keeps the rotation", w.R.Active(w.p4) ~= nil)
end

do
	local w = world()
	rolls(PASS)
	w.R.Decide(w.p4, 335)
	T = 355
	w.p4.loc = Vector(-1000, 0)
	check("mid gets the contest floor with support near", near(w.R.MidRuneDesire(w.mid), 0.55), w.R.MidRuneDesire(w.mid))
	check("the support itself gets no mid floor", w.R.MidRuneDesire(w.p4) == 0)
	w.p4.loc = Vector(2000, 0)
	check("support 2,000 away: no mid floor", w.R.MidRuneDesire(w.mid) == 0, w.R.MidRuneDesire(w.mid))
	w.p4.loc = Vector(-1000, 0)
	T = 345
	check("15 s before the spawn: no mid floor yet", w.R.MidRuneDesire(w.mid) == 0, w.R.MidRuneDesire(w.mid))
end

do
	local leave = {}
	for _, skill in ipairs({ 0, 1 }) do
		local w = world({ skill = skill })
		w.H.Lane.Config.Gauss = function() return 2 end
		leave[skill] = w.R.Decide(w.p4, 335).leaveAt
	end
	check("low skill sometimes leaves late", leave[0] ~= nil and leave[1] ~= nil and leave[0] - leave[1] > 8, tostring(leave[0]) .. " vs " .. tostring(leave[1]))
end

do
	-- Low skill with a hurt lane partner: the mistake roll skips LaneCanSpare, never IsBusy.
	local w = world({ skill = 0 })
	w.off.hp = 40
	rolls({ 0, 0.5, 0.25, 0.9 })
	local d = w.R.Decide(w.p4, 335)
	check("no mistake: a hurt partner keeps the support", d.go == false and d.reason == "partner hp", d.reason)
	w = world({ skill = 0 })
	w.off.hp = 40
	rolls({ 0, 0.5, 0.25, 0.1 })
	d = w.R.Decide(w.p4, 335)
	check("mistake: leaves a hurt partner", d.go == true and d.reason == "mistake", d.reason)
	w = world({ skill = 0 })
	w.p4.hp = 40
	rolls({ 0, 0.5, 0.25, 0.1 })
	d = w.R.Decide(w.p4, 335)
	check("mistake never skips IsBusy", d.go == false and d.reason == "hp", d.reason)
end

-- Kill switch contrast: the same world posts the claim only with Transitions enabled.
for _, enabled in ipairs({ true, false }) do
	local w = world({ transitions = { Enable = enabled } })
	rolls(PASS)
	w.H.Transitions.Tick(w.p4)
	T = 355
	w.H.Transitions.Tick(w.p4)
	w.H.Intent.Resolve(w.p4, BotMode.Rune, 0.1)
	local why = w.H.Intent.Explain(w.p4, BotMode.Rune)
	if enabled then
		check("enabled: pos 4 at 5:55 posts the rotate claim", why:find("transitions:rotate", 1, true) ~= nil, why)
		check("enabled: the overlay names the target", w.H.Transitions.Overlay(w.p4):find("rot=top", 1, true) ~= nil, w.H.Transitions.Overlay(w.p4))
		check("enabled: the lane plan sees the rotation", w.H.Lane.Hooks.IsRotationPlanned(w.p4))
		check("enabled: the rune mode is pointed at the top spot", w.H.Transitions.RuneTarget(w.p4) == Rune.Power1, w.H.Transitions.RuneTarget(w.p4))
	else
		check("disabled: no rotate claim", why:find("transitions:rotate", 1, true) == nil, why)
		check("disabled: no rune target", w.H.Transitions.RuneTarget(w.p4) == nil)
		check("disabled: no mid desire", w.H.Transitions.MidRuneDesire(w.mid) == 0)
		check("disabled: no announce", #w.said == 0, #w.said)
	end
end

do
	local w = world({ transitions = { Enable = true, Rotation = false } })
	rolls(PASS)
	check("Rotation flag off: no decision", w.R.Decide(w.p4, 335).go == false)
end

do
	-- At the spot before the spawn the bot holds still on purpose.
	local w = world()
	rolls(PASS)
	w.H.Transitions.Tick(w.p4)
	T = 355
	w.p4.loc = Vector(-1450, 1450)
	w.H.Transitions.Tick(w.p4)
	check("at the spot before the spawn: held", w.H.Intent.HeldBy(w.p4) == "transitions:rotate", w.H.Intent.HeldBy(w.p4))
	T = 366
	w.H.Transitions.Tick(w.p4)
	check("5 s after the spawn the rotation is over", w.R.Active(w.p4) == nil)
end

do
	local loc = io.open(HARNESS_DIR .. "/../../bots/FunLib/localization.lua", "r"):read("a")
	for _, key in ipairs({ "say_rune_coming_mid", "say_rune_lost" }) do
		local _, n = loc:gsub(key .. " = ", "")
		check(key .. " in all four languages", n == 4, n)
	end
end

finish()
