dofile(HARNESS_DIR .. "/dota_stubs.lua")

local StatsMod = require("bots/FunLib/humaniser/trainer/stats")

local function NewStats()
	local s = setmetatable({}, StatsMod.Stats.prototype)
	StatsMod.Stats.prototype.____constructor(s)
	return s
end

local serial = 0
local function verdict(kind, o)
	serial = serial + 1
	local v = { kind = kind, at = 0, creepId = "c" .. serial, creepKind = "melee", isDeny = false, harassed = false,
		swung = true, reason = "" }
	for k, x in pairs(o or {}) do v[k] = x end
	return { type = "verdict", v = v }
end

local function feed(stats, events)
	for _, e in ipairs(events) do stats:Add(e) end
end

local function repeated(n, kind, o)
	local out = {}
	for _ = 1, n do table.insert(out, verdict(kind, o)) end
	return out
end

local function concat(...)
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, e in ipairs(list) do table.insert(out, e) end
	end
	return out
end

local ON = { outcomeOnly = false, denies = true }

do
	local s = NewStats()
	feed(s, concat(repeated(2, "PERFECT"), repeated(1, "MISS"), repeated(1, "OK", { isDeny = true }),
		repeated(1, "MISS", { isDeny = true }), repeated(3, "CANCELLED")))
	check("score line counts takeable only", s:Lines(ON)[1] == "LH 2/3 (67%) - denies 1/2 - easy misses 0", s:Lines(ON)[1])
	check("denies segment dropped when denies are off",
		s:Lines({ outcomeOnly = false, denies = false })[1] == "LH 2/3 (67%) - easy misses 0")
	check("selftest line", (function()
		local t = NewStats()
		feed(t, concat(repeated(3, "PERFECT"), repeated(1, "MISSED_EASY", { swung = false })))
		return t:SelfTestLine() == "selftest: 3/4 PERFECT+OK (75%) - easy misses 1 of 4 reachable"
	end)())
end

do
	local s = NewStats()
	feed(s, concat(repeated(3, "PERFECT", { creepKind = "ranged", offset = -0.2 }),
		repeated(3, "PERFECT", { creepKind = "melee", offset = 0 })))
	local line = s:Lines(ON)[2]
	check("timing line early with ranged split",
		line == "you start 0.1s early on average (median -0.1s); early on ranged (-0.2s), fine on melee (+0s)", line)

	local t = NewStats()
	feed(t, concat(repeated(3, "PERFECT", { creepKind = "ranged", offset = 0.01 }),
		repeated(3, "PERFECT", { creepKind = "melee", offset = 0.03 })))
	check("on-time line, no split under 0.05 difference",
		t:Lines(ON)[2] == "you start on time on average (median +0.02s)", t:Lines(ON)[2])
end

do
	local s = NewStats()
	feed(s, concat(repeated(2, "EARLY", { offset = -0.2 }), repeated(1, "LATE", { offset = 0.2 }),
		repeated(1, "MISSED_EASY", { offset = 0.3 }), repeated(1, "MISSED_EASY", { swung = false })))
	local line = s:Lines({ outcomeOnly = true, denies = true })[2]
	check("outcome-only timing line", line == "early 2 - late 2 (no timing detail)", line)
end

do
	local s = NewStats()
	feed(s, concat(repeated(3, "MISSED_EASY", { swung = false, creepKind = "ranged" }),
		repeated(1, "MISSED_EASY", { swung = false, creepKind = "melee" }), repeated(6, "PERFECT")))
	check("leak: no-swing misses mostly ranged",
		s:Leak(true) == "4 easy creeps lost with no swing, mostly ranged. Watch the backline.", s:Leak(true))

	local t = NewStats()
	feed(t, concat(repeated(1, "MISSED_EASY", { swung = false, creepKind = "ranged" }),
		repeated(1, "MISSED_EASY", { swung = false, creepKind = "melee" }),
		repeated(1, "MISSED_EASY", { swung = false, creepKind = "siege" }), repeated(7, "PERFECT")))
	check("leak: no-swing misses with no dominant kind",
		t:Leak(true) == "3 easy creeps lost with no swing. Watch every creep near you, not just your target.", t:Leak(true))
end

do
	local s = NewStats()
	feed(s, concat(repeated(6, "LATE", { offset = 0.2 }), repeated(5, "MISS", { isDeny = true })))
	check("leak: late bias wins on cost over denies",
		s:Leak(true) == "you're late: start your swing about 0.2s sooner", s:Leak(true))

	local t = NewStats()
	feed(t, concat(repeated(3, "LATE", { offset = 0.2 }), repeated(8, "MISS", { isDeny = true })))
	check("leak: denies win when they cost more",
		t:Leak(true) == "denies 0/8: check allied creeps under half HP", t:Leak(true))
	check("leak: denies rule off when denies are off",
		t:Leak(false) == "you're late: start your swing about 0.2s sooner", t:Leak(false))
end

do
	local s = NewStats()
	feed(s, concat(repeated(3, "MISSED_EASY", { swung = false }), repeated(3, "LATE", { offset = 0.2 }),
		repeated(4, "PERFECT", { offset = 0.2 })))
	check("leak tie goes to earlier rule", s:Leak(true):find("easy creeps lost with no swing", 1, true) ~= nil, s:Leak(true))
end

do
	local function build(gotItFlags)
		local s = NewStats()
		local early = repeated(4, "EARLY", { offset = -0.2 })
		feed(s, concat(early, repeated(3, "MISSED_EASY", { swung = false }), repeated(3, "PERFECT", { offset = -0.2 })))
		for i, e in ipairs(early) do
			s:Add({ type = "outcome", creepId = e.v.creepId, subjectGotIt = gotItFlags[i] })
		end
		return s
	end

	local mixed = build({ true, true, false, false })
	check("early-bias cost counts only creeps then lost",
		mixed:Leak(true):find("easy creeps lost with no swing", 1, true) ~= nil, mixed:Leak(true))

	local allLost = build({ false, false, false, false })
	check("early bias wins once its cost is highest",
		allLost:Leak(true) == "you're early: wait about 0.2s longer before swinging", allLost:Leak(true))
end

do
	local s = NewStats()
	feed(s, repeated(9, "PERFECT"))
	check("under 10 takeable: not enough data yet", s:Leak(true) == "not enough data yet")
	feed(s, repeated(3, "CANCELLED"))
	check("cancelled verdicts do not count toward the 10", s:Leak(true) == "not enough data yet")
	feed(s, repeated(1, "PERFECT"))
	check("10 takeable with nothing wrong: no clear leak", s:Leak(true) == "no clear leak - keep going", s:Leak(true))
end

do
	local s = NewStats()
	feed(s, concat(repeated(2, "OK", { harassed = true }), repeated(3, "MISS", { harassed = true }),
		repeated(4, "PERFECT"), repeated(1, "MISS")))
	local lines = s:Lines(ON)
	check("harass line past 15 points", lines[4] == "under harass 40% vs 80% free", lines[4])
	check("harass slump is the leak", lines[3] == "you lose timing when hit: back off or swing earlier under pressure", lines[3])

	local t = NewStats()
	feed(t, concat(repeated(7, "PERFECT", { harassed = true }), repeated(3, "MISS", { harassed = true }),
		repeated(8, "PERFECT"), repeated(2, "MISS")))
	check("harass line absent under 15 points", #t:Lines(ON) == 3, #t:Lines(ON))
	check("no leak for a 10 point harass gap", t:Leak(true) == "no clear leak - keep going", t:Leak(true))
end

do
	local s = NewStats()
	local events = concat(repeated(10, "PERFECT"), repeated(2, "MISSED_EASY", { swung = false }))
	feed(s, events)
	s:Add({ type = "outcome", creepId = events[1].v.creepId, subjectGotIt = true })
	s:Reset()
	local lines = s:Lines(ON)
	check("reset clears the score", lines[1]:find("LH 0/0 (0%)", 1, true) == 1, lines[1])
	check("reset clears the leak", lines[3] == "not enough data yet", lines[3])
end

finish()
