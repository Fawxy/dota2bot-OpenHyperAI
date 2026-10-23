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
	local H = LaneFresh({ Enable = true }, { skill = opts.skill or 0.9, transitions = opts.transitions or { Enable = true }, telemetry = opts.telemetry })
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

do
	-- A human pos 4 neither decides nor rotates: the bot pos 5 decides as if there were no pos 4.
	local w = world()
	w.p4.bot = false
	rolls(PASS, PASS)
	local d = w.R.Decide(w.p5, 335)
	check("human pos 4: bot pos 5 decides as if pos 4 is absent", d.go == true and d.reason == "ok", d.reason)
	check("human pos 4: only the bot drew rolls", RandomUnread() == 4, RandomUnread())
	check("human pos 4 gets no decision", w.R.Decide(w.p4, 335).go == false)
	T = 355
	w.p4.loc = Vector(-1000, 0)
	check("human pos 4 near the mid: no phantom mid floor", w.R.MidRuneDesire(w.mid) == 0, w.R.MidRuneDesire(w.mid))
	check("human pos 4: the lane plan sees no rotation", not w.H.Lane.Hooks.IsRotationPlanned(w.p4))
end

do
	-- A human ally standing at the spot counts for the contest by position.
	local w = world()
	w.off.bot = false
	rolls(PASS)
	w.H.Transitions.Tick(w.p4)
	for i = 0, 2 do MakeUnit({ pid = 10 + i, team = 3, loc = Vector(-1500 + 100 * i, 1500) }) end
	w.off.loc = Vector(-1400, 1400)
	T = 350
	w.H.Transitions.Tick(w.p4)
	check("a human ally at the spot evens the contest", w.R.Active(w.p4) ~= nil)
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

-- Rotations are a laning-phase transition: no decision and no line after laning (13:35, LANING = false) or with
-- the support's T1 down before 10:00. The same spawn in laning is the contrast.
do
	local function run(o)
		local w = world({ T = o.T })
		if o.notLaning then LANING = false end
		if o.t1Dead then TOWERS_W[2][dota.Tower.Top1].alive = false end
		rolls(PASS)
		local d = w.R.Decide(w.p4, T)
		w.H.Transitions.Tick(w.p4)
		return { go = d.go, reason = d.reason, said = count(w.said, "say_rune_coming_mid") }
	end
	local on = run({ T = 815 })
	check("in laning at 13:35 (contrast): pos 4 rotates and announces", on.go and on.said == 1, on.reason)
	local off = run({ T = 815, notLaning = true })
	check("after laning: no rotation", off.go == false and off.reason == "phase", off.reason)
	check("after laning: no coming-mid line", off.said == 0, off.said)
	local dead = run({ T = 335, t1Dead = true })
	check("our top T1 down before 10:00: the top pos 4 does not rotate", dead.go == false and dead.said == 0, dead.reason)
end

do
	-- Laning ends during a rotation: the floor claim goes at once and the rune mode loses its target.
	local w = world()
	rolls(PASS)
	check("precondition: pos 4 goes", w.R.Decide(w.p4, 335).go)
	T = 345
	w.H.Transitions.Tick(w.p4)
	check("precondition: rotation claim and target", w.H.Intent.ClaimAge(w.p4, "transitions:rotate", BotMode.Rune) ~= nil and w.R.RuneTarget(w.p4) ~= nil)
	LANING = false
	T = 346
	w.H.Transitions.Tick(w.p4)
	check("laning ends: rotation claim released", w.H.Intent.ClaimAge(w.p4, "transitions:rotate", BotMode.Rune) == nil)
	check("laning ends: no rune target", w.R.RuneTarget(w.p4) == nil)
end


-- tr_* telemetry: captured lines for one event name.
local function capture(w)
	local lines = {}
	w.H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	return function(ev)
		local out = {}
		for _, l in ipairs(lines) do if l:find("ev=" .. ev .. " ", 1, true) then table.insert(out, l) end end
		return out
	end
end
local function has(l, ...)
	for _, s in ipairs({ ... }) do if not (l or ""):find(s, 1, true) then return false end end
	return true
end

do
	-- A decision is reported once per spawn with its reason.
	local w = world({ telemetry = { Enable = true } })
	local ev = capture(w)
	rolls(PASS)
	w.R.Decide(w.p4, 335)
	w.R.Decide(w.p4, 336)
	local l = ev("tr_rotate")
	check("tr_rotate: once per spawn", #l == 1, #l)
	check("tr_rotate: names the outcome and the side", has(l[1], "pid=4", "spawn=360", "go=1", "side=top", "reason=ok"), l[1])
	w = world({ telemetry = { Enable = true } })
	ev = capture(w)
	w.p4.hp = 40
	rolls(PASS)
	w.R.Decide(w.p4, 335)
	check("tr_rotate: a skip says why", has(ev("tr_rotate")[1], "go=0", "reason=hp"), ev("tr_rotate")[1])
end


-- Holding a spawned rune for our mid. The pos 4 decided at 5:35 for the top spot and stands on it.
local RUNE_UP = {}
local baseStatus = GetRuneStatus
function GetRuneStatus(r) return RUNE_UP[r] and RUNE_STATUS_AVAILABLE or RUNE_STATUS_MISSING end
local function holding(opts)
	opts = opts or {}
	local w = world({ telemetry = opts.telemetry })
	if opts.telemetry then w.ev = capture(w) end
	rolls(PASS)
	w.R.Decide(w.p4, 335)
	w.p4.loc = TOP_SPOT
	w.mid.loc = opts.mid or MID
	RUNE_UP = { [Rune.Power1] = opts.taken ~= true }
	T = opts.T or 361
	return w
end

do
	local w = holding()
	check("rune up, our mid 2,121 away: the support leaves it for the mid", w.R.HoldsRune(w.p4, Rune.Power1) == true)
	check("... only the rune it rotated for", w.R.HoldsRune(w.p4, Rune.Power2) == false)
	w = holding({ mid = BOT, T = 362 })
	check("mid 5,600 away, 2 s after the spawn: still holding", w.R.HoldsRune(w.p4, Rune.Power1) == true)
	T = 363.5
	check("mid not coming 3 s after the spawn: the support takes it", w.R.HoldsRune(w.p4, Rune.Power1) == false)
	w = holding({ T = 363.5 })
	check("contrast: mid coming 3.5 s after the spawn: still holding", w.R.HoldsRune(w.p4, Rune.Power1) == true)
	T = 375
	check("mid coming but 15 s after the spawn: the support takes it", w.R.HoldsRune(w.p4, Rune.Power1) == false)
end

do
	local w = holding()
	MakeUnit({ pid = 10, team = 3, loc = Vector(-1500, 2600) })
	check("an enemy 1,100 from the rune: the support takes it", w.R.HoldsRune(w.p4, Rune.Power1) == false)
	w = holding()
	MakeUnit({ pid = 10, team = 3, loc = Vector(-1500, 2900) })
	check("an enemy 1,400 away: still holding", w.R.HoldsRune(w.p4, Rune.Power1) == true)
end

do
	-- The rotation (and its rune-mode floor) outlasts RotateLinger while the rune lies there.
	local w = holding({ T = 370 })
	check("10 s after the spawn with the rune up: still rotating", w.R.Active(w.p4) ~= nil)
	RUNE_UP = {}
	check("once the rune is taken: the rotation ends", w.R.Active(w.p4) == nil)
	w = holding({ T = 376 })
	check("past RuneHoldMax: the rotation ends even with the rune up", w.R.Active(w.p4) == nil)
end

do
	local w = holding({ mid = BOT, telemetry = { Enable = true } })
	local ev = w.ev
	w.R.HoldsRune(w.p4, Rune.Power1)
	T = 362
	w.R.HoldsRune(w.p4, Rune.Power1)
	T = 364
	w.R.HoldsRune(w.p4, Rune.Power1)
	local l = ev("tr_rune_hold")
	check("tr_rune_hold: hold, then one take line with the reason", #l == 2 and has(l[1], "pid=4", "state=hold") and has(l[2], "state=take", "reason=late"), #l)
end
GetRuneStatus = baseStatus

-- Priority fixes (Task 6): a decided rotation is re-checked until RecheckUntilWalk s after leaving, and tells the lane hooks.
do
	local w = world()
	rolls(PASS)
	check("precondition: pos 4 goes", w.R.Decide(w.p4, 335).go)
	check("a decided rotation is reported to the lane hooks", w.H.Lane.Hooks.RotationDecided(w.p4))
	check("no rotation, nothing reported", not w.H.Lane.Hooks.RotationDecided(w.p5))
	T = 336
	w.H.Transitions.Tick(w.p4)
	w.off.hp = 40
	T = 339.5
	w.H.Transitions.Tick(w.p4)
	local d = w.R.Decide(w.p4, 339.5)
	check("the lane turns unsafe before leaving: the rotation is called off", d.go == false and d.reason == "partner hp", d.reason)
	-- No "rune lost" line here: the "coming mid" line 3.5 s earlier holds the bot's chat for MIN_LINE_GAP (10 s).
	check("called off: no longer reported", not w.H.Lane.Hooks.RotationDecided(w.p4))
end
do
	local w = world()
	rolls(PASS)
	w.R.Decide(w.p4, 335)
	w.off.hp = 40
	T = LEAVE + 4.5
	w.H.Transitions.Tick(w.p4)
	check("past RecheckUntilWalk the walk goes on", w.R.Decide(w.p4, T).go == true, w.R.Decide(w.p4, T).reason)
end
do
	-- A low-skill mistake rotation left knowing the lane could not spare it: no re-check calls it off.
	local w = world({ skill = 0 })
	w.off.hp = 40
	rolls({ 0, 0.5, 0.25, 0.1 })
	check("precondition: a mistake rotation", w.R.Decide(w.p4, 335).reason == "mistake")
	T = 336
	w.H.Transitions.Tick(w.p4)
	check("a mistake rotation is not re-checked", w.R.Decide(w.p4, 336).go == true)
end

finish()
