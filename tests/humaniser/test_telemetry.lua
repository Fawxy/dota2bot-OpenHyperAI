dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode = dota.BotMode

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetLastHits() return self.lh or 0 end
function UnitMeta:GetDenies() return self.dn or 0 end
function UnitMeta:GetAttackTarget() return self.target end
function UnitMeta:GetMana() return 50 end
function UnitMeta:GetMaxMana() return 100 end
function UnitMeta:GetGold() return 600 end
function UnitMeta:GetNetWorth() return 1200 end
function UnitMeta:ActionImmediate_Chat(line) self.said = self.said or {} table.insert(self.said, line) end

local lines
local function fresh(telemetry)
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Telemetry = telemetry or { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	return H
end
local function events(name)
	local r = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) or l:sub(-#name - 4) == " ev=" .. name then table.insert(r, l) end end
	return r
end
local function field(line, key) return line:match(" " .. key .. '="([^"]*)"') or line:match(" " .. key .. "=(%S+)") end
local function say(pid, text)
	T = T + 0.5
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = true }) end
end
local function creep(name) return { GetUnitName = function() return name end } end

-- Kill switch: the Customize default is off, and then nothing is printed whatever happens.
do
	local H = fresh({})
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	H.Telemetry.Tick(b)
	b.mode = BotMode.Farm
	T = 2
	H.Telemetry.Tick(b)
	H.Telemetry.Event("notice", { { "pid", 1 } })
	check("disabled prints nothing", #lines == 0, #lines)
end

-- Values with spaces, quotes or '=' survive as one quoted field; tools/hlog parses the same rule.
do
	local H = fresh()
	local line = H.Telemetry.FormatLine("cmd", { { "text", 'say "hi" a=b' }, { "n", 3 }, { "d", 0.5 }, { "ok", true }, { "skip", nil } })
	check("quoted text", field(line, "text") == "say 'hi' a=b", line)
	check("integer bare", field(line, "n") == "3", line)
	check("float 3dp", field(line, "d") == "0.500", line)
	check("bool as 1", field(line, "ok") == "1", line)
	check("nil field omitted", not line:find("skip=", 1, true), line)
end

-- Snapshots are throttled to SnapshotInterval; mode switches report the previous mode's dwell.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	for i = 0, 20 do
		T = i * 0.1
		H.Telemetry.Tick(b)
	end
	check("snapshots throttled", #events("snap") == 3, #events("snap"))
	b.mode = BotMode.Farm
	T = 2.5
	H.Telemetry.Tick(b)
	local m = events("mode")
	check("one mode event", #m == 1, #m)
	check("mode from/to", m[1] and field(m[1], "from") == "laning" and field(m[1], "to") == "farm", m[1])
	check("mode dwell", m[1] and math.abs(tonumber(field(m[1], "dwell")) - 2.5) < 1e-6, m[1])
	check("profile reported once", #events("bot") == 1, #events("bot"))
end

-- A last hit is attributed to the etiquette decision on the creep the bot was attacking the frame before.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	local c = creep("npc_dota_creep_badguys_melee")
	H.Telemetry.Tick(b)
	b.target = c
	T = 0.1
	H.Telemetry.NoteLastHitDecision(b, c, false, "skip: core")
	H.Telemetry.Tick(b)
	b.lh, b.target = 1, nil
	T = 0.2
	H.Telemetry.Tick(b)
	local lh = events("lasthit")
	check("lasthit emitted", #lh == 1, #lh)
	check("lasthit carries decision", lh[1] and field(lh[1], "dec") == "skip: core", lh[1])
	check("lasthit creep", lh[1] and field(lh[1], "creep") == "npc_dota_creep_badguys_melee", lh[1])

	-- A decision older than DecisionMaxAge says nothing about this kill.
	local c2 = creep("npc_dota_creep_badguys_ranged")
	b.target = c2
	H.Telemetry.NoteLastHitDecision(b, c2, false, "skip: core")
	T = 0.3
	H.Telemetry.Tick(b)
	b.lh = 2
	T = 2
	H.Telemetry.Tick(b)
	lh = events("lasthit")
	check("stale decision not attributed", lh[2] and field(lh[2], "dec") == nil, lh[2])
end

-- ER-001 b04_C_off_1 t=340.4 (BACKLOG 0.14): the killed creep's handle was removed before the frame that saw the last hit, so
-- reading its name raised "Invalid object passed to GetUnitName" every frame and stopped that bot's counters and snapshots.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	local c = creep("npc_dota_creep_badguys_melee")
	c.IsNull = function() return c.removed == true end
	c.GetUnitName = function()
		if c.removed then error("Invalid object passed to GetUnitName.") end
		return "npc_dota_creep_badguys_melee"
	end
	H.Telemetry.Tick(b)
	b.target = c
	T = 0.1
	H.Telemetry.NoteLastHitDecision(b, c, false, "skip: core")
	H.Telemetry.Tick(b)
	c.removed, b.lh, b.target = true, 1, nil
	T = 0.2
	local ok, err = pcall(H.Telemetry.Tick, b)
	check("a removed last-hit creep does not raise", ok, err)
	local lh = events("lasthit")
	check("its last hit is still logged with the name read while it lived", #lh == 1 and field(lh[1], "creep") == "npc_dota_creep_badguys_melee", lh[1])
	check("and its decision", lh[1] and field(lh[1], "dec") == "skip: core", lh[1])
	b.lh = 2
	T = 0.3
	ok, err = pcall(H.Telemetry.Tick, b)
	check("the next last hit is counted once", ok and #events("lasthit") == 2 and field(events("lasthit")[2], "n") == "1", err)
end

-- Human allies' last hits are tracked by the team's lowest-PID bot only.
do
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false })
	local b1, b2 = MakeUnit({ pid = 1 }), MakeUnit({ pid = 2 })
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	human.lh = 1
	T = 0.1
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	local lh = events("lasthit")
	check("human last hit once", #lh == 1 and field(lh[1], "pid") == "0" and field(lh[1], "human") == "1", table.concat(lh, "\n"))
	check("human announced", #events("player") == 1, #events("player"))
end

-- !mark: one mark line and ack from the lowest-PID bot, one state line per bot, nothing repeated.
do
	local H = fresh()
	MakeUnit({ pid = 0, bot = false })
	local b1, b2 = MakeUnit({ pid = 1, mode = BotMode.Farm }), MakeUnit({ pid = 2, mode = BotMode.Laning })
	H.Chat.EnsureInstalled(b1)
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	say(0, "!mark pos4 walked into tower")
	say(0, "!marker not a mark")
	say(1, "!mark from a bot")
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	T = T + 0.1
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	local marks, states = events("mark"), events("mark_state")
	check("one mark", #marks == 1, table.concat(marks, "\n"))
	check("mark text", marks[1] and field(marks[1], "text") == "pos4 walked into tower", marks[1])
	check("mark state per bot", #states == 2, #states)
	check("mark state has mode", states[2] and field(states[2], "mode") == "laning", states[2])
	check("ack from lowest bot only", b1.said and #b1.said == 1 and b1.said[1] == "mark 1 saved" and b2.said == nil)

	H.Telemetry.Tick(b1)
	say(0, "!MARK")
	H.Telemetry.Tick(b1)
	check("empty mark numbered 2", #events("mark") == 2 and field(events("mark")[2], "n") == "2")
end

-- Guard: a thrown error is reported once as lua_error with where/msg/tb and swallowed; the caller gets the fallback.
do
	local H = fresh()
	local g = H.Telemetry.Guard("Test.Boom", function(a) error("boom " .. a) end, function(a) return "fallback " .. a end)
	local ok, r = pcall(g, 7)
	local e = events("lua_error")
	check("guard does not rethrow", ok, r)
	check("guard returns fallback", r == "fallback 7", r)
	check("one lua_error", #e == 1, #e)
	check("lua_error where", e[1] and field(e[1], "where") == "Test.Boom", e[1])
	check("lua_error msg", e[1] and (field(e[1], "msg") or ""):find("boom 7", 1, true) ~= nil, e[1])
	check("lua_error traceback names the file", e[1] and (field(e[1], "tb") or ""):find("test_telemetry.lua:", 1, true) ~= nil, e[1])

	-- No error: every return value passes through.
	local g2 = H.Telemetry.Guard("Test.Multi", function(a, b) return a + b, "second" end)
	local x, y = g2(2, 3)
	check("guard passes multiple returns", x == 5 and y == "second", tostring(x) .. " " .. tostring(y))

	-- An error object whose __tostring itself errors (one way to get "error in error handling") is still reported.
	local bad = setmetatable({}, { __tostring = function() error("tostring exploded") end })
	local g3 = H.Telemetry.Guard("Test.Weird", function() error(bad) end)
	check("weird error object swallowed", pcall(g3))
	local w = events("lua_error")
	check("weird error object reported by type", w[2] and field(w[2], "msg") == "<table>", w[2])
end

-- A stack overflow inside a guarded call is caught and reported where it entered, not left to Valve's handler.
do
	local H = fresh()
	local function deep(n) return 1 + deep(n + 1) end
	local g = H.Telemetry.Guard("Test.Deep", function() return deep(0) end, function() return -1 end)
	local ok, r = pcall(g)
	local e = events("lua_error")
	check("overflow swallowed with fallback", ok and r == -1, tostring(ok) .. " " .. tostring(r))
	check("overflow reported once", #e == 1 and field(e[1], "where") == "Test.Deep", e[1])
end

-- Entry (OHA entry points, H.1): returns pass through; an error is reported under oha.<where> and raised again unchanged.
do
	local H = fresh()
	local f = H.Telemetry.Entry("mode_test.GetDesire", function(a) return a * 2, "second" end)
	local x, y = f(4)
	check("entry passes returns", x == 8 and y == "second", tostring(x) .. " " .. tostring(y))
	check("entry quiet without error", #events("lua_error") == 0, #events("lua_error"))
	check("entry keeps nil", H.Telemetry.Entry("mode_test.Think", nil) == nil)

	local obj = { tag = "original" }
	local g = H.Telemetry.Entry("mode_test.Think", function() error(obj) end)
	local ok, err = pcall(g)
	local e = events("lua_error")
	check("entry rethrows", not ok)
	check("entry rethrows the same error object", err == obj, tostring(err))
	check("entry reports where=oha.<where>", e[1] and field(e[1], "where") == "oha.mode_test.Think", e[1])

	-- A stack overflow is reported with its own message, not as "error in error handling".
	local function deep(n) return 1 + deep(n + 1) end
	local d = H.Telemetry.Entry("mode_test.Deep", function() return deep(0) end)
	local okd, errd = pcall(d)
	e = events("lua_error")
	check("entry overflow rethrown", not okd)
	check("entry overflow message kept", e[2] and (field(e[2], "msg") or ""):find("overflow", 1, true) ~= nil, e[2])
	check("entry overflow message raised", type(errd) == "string" and errd:find("overflow", 1, true) ~= nil, tostring(errd))
end

-- Perf probe (Telemetry.Perf): an entry point's time is all script time; inside it only the outermost guarded call counts
-- as ours, and a guarded call made from it is reported under its caller, not a second time as ours.
do
	local realClock, C, spin = os.clock, 0, true
	os.clock = function() if spin then C = C + 0.01 end return C end
	local H = fresh({ Enable = true, Perf = true, PerfInterval = 10 })
	spin = false
	local inner = H.Telemetry.Guard("Test.Inner", function() C = C + 0.001 end)
	local outer = H.Telemetry.Guard("Test.Outer", function() C = C + 0.002 inner() return "kept" end)
	local kept
	local entry = H.Telemetry.Entry("mode_test.Think", function() C = C + 0.004 kept = outer() return 1, "two" end)
	entry()
	T = T + 10
	local a, b = entry()
	os.clock = realClock
	local near = function(line, key, want) return line ~= nil and math.abs(tonumber(field(line, key)) - want) < 0.01 end
	local row = function(kind, where)
		for _, l in ipairs(events("perf_top")) do if field(l, "kind") == kind and field(l, "where") == where then return l end end
	end
	check("timed entry and guard pass returns through", a == 1 and b == "two" and kept == "kept")
	local p = events("perf")[1]
	check("one window, the first call only opens it", #events("perf") == 1, #events("perf"))
	check("entry time is the whole call", near(p, "entry_ms", 7), p)
	check("ours is the outermost guard, nested not added again", near(p, "ours_ms", 3), p)
	check("nested guard reported under its caller", near(row("sub", "Test.Outer>Test.Inner"), "ms", 1), row("sub", "Test.Outer>Test.Inner"))
	check("nested guard has no row of its own", row("ours", "Test.Inner") == nil)
end

-- Entry is a no-op with telemetry off.
do
	local H = fresh({ Enable = false })
	local fn = function() end
	check("entry off returns fn", H.Telemetry.Entry("mode_test.Think", fn) == fn)
end

-- Rate limit per (where, msg): repeats are counted and reported again after LuaErrorRepeat with the running count.
do
	local H = fresh({ Enable = true, LuaErrorRepeat = 10 })
	local g = H.Telemetry.Guard("Test.Repeat", function(m) error(m, 0) end)
	for _ = 1, 5 do g("same") end
	check("repeats within the window are quiet", #events("lua_error") == 1, #events("lua_error"))
	g("other")
	H.Telemetry.Guard("Test.Elsewhere", function(m) error(m, 0) end)("same")
	check("new msg or where reported", #events("lua_error") == 3, #events("lua_error"))
	T = T + 10
	g("same")
	local e = events("lua_error")
	check("repeat after the window", #e == 4, #e)
	check("repeat carries running count", e[4] and field(e[4], "n") == "6" and field(e[4], "msg") == "same", e[4])
end

-- The guard is installed on the humaniser hooks: a hook that throws falls back to the feature-off value.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	b.GetPlayerID = function() error("handle went stale") end
	local ok, d = pcall(H.Intent.Resolve, b, BotMode.Laning, 0.42)
	check("Intent.Resolve error falls back to raw desire", ok and d == 0.42, tostring(ok) .. " " .. tostring(d))
	local e = events("lua_error")
	check("Intent.Resolve error reported", e[1] and field(e[1], "where") == "Intent.Resolve", e[1])
	local ok2 = pcall(H.Tick, b)
	check("Tick error swallowed", ok2)
	check("Tick error reported", events("lua_error")[2] and field(events("lua_error")[2], "where") == "Tick", events("lua_error")[2])

	local off = fresh({ Enable = true, LuaErrors = false })
	check("LuaErrors = false leaves hooks unwrapped", not pcall(off.Intent.Resolve, b, BotMode.Laning, 0.42))
end

-- Humaniser off (A/B game): telemetry still snapshots and logs mode switches; the humaniser itself stays inert.
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = false, Telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local draws = 0
	local realRandomFloat = RandomFloat
	RandomFloat = function(...) draws = draws + 1 return realRandomFloat(...) end
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	for i = 0, 20 do
		T = i * 0.1
		H.Tick(b)
	end
	b.mode = BotMode.Farm
	T = 2.5
	H.Tick(b)
	RandomFloat = realRandomFloat
	check("snapshots with humaniser off", #events("snap") == 3, #events("snap"))
	check("mode switch with humaniser off", #events("mode") == 1 and field(events("mode")[1], "to") == "farm", events("mode")[1])
	local bot = events("bot")[1]
	check("bot line says humaniser off, no profile", bot and field(bot, "humaniser") == "0" and field(bot, "skill") ~= nil and field(bot, "notice") == nil, bot)
	check("no profile RNG drawn", draws == 0, draws)
	check("no chat callback installed", #CHAT_CALLBACKS == 0, #CHAT_CALLBACKS)
	check("Intent.Resolve passes raw through", H.Intent.Resolve(b, BotMode.Farm, 0.31) == 0.31)
	check("no humaniser start line", #events("notice") == 0)
end

-- lane_eq: one sample per team and lane per wave cycle, once the cycle is EqSampleAt seconds old.
do
	local dota = require("bots/ts_libs/dota/index")
	local Lane = dota.Lane
	dofile(HARNESS_DIR .. "/lane_world.lua")
	local H = LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	CURRENT_TEAM = 2
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.55, 0.55
	local S = H.Lane.LaneState
	for _, t in ipairs({ 65, 71, 72 }) do
		T = t
		S.Get(2, Lane.Bot)
		S.Get(3, Lane.Bot)
	end
	local e = events("lane_eq")
	check("lane_eq once per team and lane in the cycle", #e == 2, #e)
	check("lane_eq at or after cycle second 10", e[1] and field(e[1], "t") == "71", e[1])
	check("lane_eq carries the forecast inputs", e[1] and field(e[1], "team") == "2" and field(e[1], "lane") == tostring(Lane.Bot)
		and field(e[1], "kind") and field(e[1], "eq") and field(e[1], "imb") and field(e[1], "feq") and field(e[1], "a") and field(e[1], "e"), e[1])
	T = 101
	S.Get(2, Lane.Bot)
	check("lane_eq again in the next cycle", #events("lane_eq") == 3, #events("lane_eq"))
end

-- Slice lane-activity: what the bot could do this second, up to 12:00, for a live bot that is no human's ally.
do
	local H = fresh()
	local enemy = MakeUnit({ pid = 7, team = 3 })
	-- A world loaded earlier in this file replaces the stubs' unit table, so the extras go on the current one.
	local U = getmetatable(enemy).__index
	for name, fn in pairs(UnitMeta) do if U[name] == nil then U[name] = fn end end
	function U:GetNearbyHeroes() return { enemy } end
	function U:WasRecentlyDamagedByAnyHero() return true end
	local dist = GetUnitToUnitDistance
	GetUnitToUnitDistance = function() return 432.7 end
	local b = MakeUnit({ pid = 1, team = 2, mode = BotMode.Laning })
	T = 100
	H.Telemetry.Tick(b)
	local snap = events("snap")[1]
	check("options: range and nearest enemy on the snap", snap ~= nil and field(snap, "ar") ~= nil and field(snap, "ed") == "432", snap)
	lines = {}
	T = 721
	H.Telemetry.Tick(b)
	snap = events("snap")[1]
	check("options: none past 12:00", snap ~= nil and field(snap, "ar") == nil and field(snap, "ed") == nil, snap)
	GetUnitToUnitDistance = dist
	U.GetNearbyHeroes, U.WasRecentlyDamagedByAnyHero = nil, nil
end

-- Tool slice hp-loss: who is hurting the bot, all game. Only units whose attack target is the bot count, by kind.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, team = 2, mode = BotMode.Laning })
	local function attacker(target) local u = MakeUnit({ team = 3 }) u.target = target return u end
	local other = MakeUnit({ pid = 2, team = 2 })
	local U = getmetatable(b).__index
	for name, fn in pairs(UnitMeta) do if U[name] == nil then U[name] = fn end end
	local names = { "GetNearbyHeroes", "GetNearbyLaneCreeps", "GetNearbyNeutralCreeps", "GetNearbyTowers", "WasRecentlyDamagedByAnyHero", "WasRecentlyDamagedByCreep", "WasRecentlyDamagedByTower", "GetHealth" }
	local saved = {}
	for _, n in ipairs(names) do saved[n] = rawget(U, n) end
	function U:GetNearbyHeroes() return { attacker(b), attacker(other) } end
	local dead = attacker(b)
	dead.alive = false
	function U:GetNearbyLaneCreeps() return { attacker(b), attacker(b), attacker(other), attacker(nil), dead } end
	function U:GetNearbyNeutralCreeps() return { attacker(other) } end
	function U:GetNearbyTowers() return { attacker(b) } end
	function U:WasRecentlyDamagedByAnyHero() return false end
	function U:WasRecentlyDamagedByCreep() return true end
	function U:WasRecentlyDamagedByTower() return true end
	function U:GetHealth() return 431.6 end
	T = 900
	H.Telemetry.Tick(b)
	local snap = events("snap")[1]
	check("damage: flags by source and raw HP, past 12:00 too", snap ~= nil and field(snap, "hit") == "0" and field(snap, "hc") == "1" and field(snap, "ht") == "1" and field(snap, "hv") == "431", snap)
	check("damage: only live units attacking this bot are counted, by kind", snap ~= nil and field(snap, "ah") == "1" and field(snap, "ac") == "2" and field(snap, "an") == "0" and field(snap, "at") == "1", snap)
	for _, n in ipairs(names) do U[n] = saved[n] end
end

finish()

-- Before/after runs: the bot line names the build and the position; snapshots carry kills and deaths.
do
	package.preload["bots/FunLib/humaniser/build_info"] = function() return { build = "abc1234+dirty" } end
	local H = fresh()
	package.preload["bots/FunLib/humaniser/build_info"] = nil
	H.Lane.SetHelpers({ GetPosition = function(u) return u.pos end })
	GetHeroKills = function(pid) return pid == 1 and 2 or 0 end
	GetHeroDeaths = function(pid) return pid == 1 and 3 or 0 end
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	b.pos = 4
	-- lane_world.lua (loaded above) replaces MakeUnit's metatable, so the counters the snapshot reads are set here.
	b.GetLastHits = function() return 0 end
	b.GetDenies = function() return 0 end
	b.GetMana = function() return 50 end
	b.GetMaxMana = function() return 100 end
	b.GetGold = function() return 600 end
	b.GetNetWorth = function() return 1200 end
	b.GetAttackTarget = function() return nil end
	T = 0
	H.Telemetry.Tick(b)
	local bot = events("bot")[1]
	check("bot line carries the build", bot and field(bot, "build") == "abc1234+dirty", bot)
	check("bot line carries the position", bot and field(bot, "pos") == "4", bot)
	check("bot line is schema 2", bot and field(bot, "schema") == "2", bot)
	local snap = events("snap")[1]
	check("snap carries kills and deaths", snap and field(snap, "kills") == "2" and field(snap, "deaths") == "3", snap)
	GetHeroKills, GetHeroDeaths = nil, nil
end
