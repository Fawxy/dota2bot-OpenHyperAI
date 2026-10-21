dofile(HARNESS_DIR .. "/dota_stubs.lua")

local Judge = require("bots/FunLib/humaniser/trainer/judge")
local Watch = require("bots/FunLib/humaniser/trainer/watch")

local function NewJudge()
	local j = setmetatable({}, Judge.Judge.prototype)
	Judge.Judge.prototype.____constructor(j, 0.3)
	return j
end

local t0 = 100
local DT = 1 / 30

local function pred(open, close, o)
	o = o or {}
	return { startOpen = open, startClose = close, ideal = (open + close) / 2, delay = 0.4,
		effDmg = 58, hp = 71, curve = {}, at = t0, isDeny = false, uncertain = false }
end

local function swingAnim(swingStart, now)
	if now < swingStart + 0.2 then return "swing" end
	if now < swingStart + 0.35 then return "followthrough" end
	return "none"
end

-- Plays a creep whose prediction is windowFor(now) until it dies at deathAt; the subject swings at swingAt if given.
local function run(o)
	local judge, verdicts = NewJudge(), {}
	local now = t0
	while now <= t0 + 2.0 do
		local dead = now >= o.deathAt - 1e-9
		local c = { id = "A", kind = o.kind or "melee", isDeny = o.isDeny or false, alive = not dead, hp = dead and 0 or 71, dist = o.dist or 100 }
		if not dead then c.prediction = o.windowFor(now) else c.killer = o.killer or { kind = "creep" } end
		local s = { now = now, alive = o.subjectAlive ~= false, eligible = o.eligible ~= false, harassed = false,
			anim = "none", lastHits = 0, denies = 0, target = "A" }
		if o.swingAt and not dead and now >= o.swingAt then
			s.anim, s.swingStart = swingAnim(o.swingAt, now), o.swingAt
		end
		for _, e in ipairs(judge:Step(s, { c })) do
			if e.type == "verdict" then table.insert(verdicts, e.v) end
		end
		now = now + DT
	end
	return verdicts
end

local function wide(now) return pred(t0 + 0.1, t0 + 0.52) end

-- The widest window is 0.42 s and was seen on the first frame; the creep dies at t0 + 0.7.
do
	local v = run({ windowFor = wide, deathAt = t0 + 0.7, kind = "ranged" })
	check("wide window, no swing: one MISSED_EASY", #v == 1 and v[1].kind == "MISSED_EASY", #v)
	local e = v[1] or {}
	check("no-swing reason", e.reason == "missed easy one - 0.42s window, ranged creep, no swing", e.reason)
	check("no-swing verdict is marked unswung with its window", e.swung == false and near(e.window or 0, 0.42), e.window)

	v = run({ windowFor = wide, deathAt = t0 + 0.7, isDeny = true, kind = "melee" })
	check("deny wording", v[1] ~= nil and v[1].reason == "missed easy deny - 0.42s window, melee creep, no swing", v[1] and v[1].reason)

	v = run({ windowFor = wide, deathAt = t0 + 0.7, killer = { kind = "ally", name = "Lion" } })
	check("ally took it after you passed", v[1] ~= nil and v[1].reason == "missed easy one - 0.42s window, melee creep, no swing - Lion took it after you passed", v[1] and v[1].reason)
end

do
	local v = run({ windowFor = function() return pred(t0 + 0.1, t0 + 0.3) end, deathAt = t0 + 0.7 })
	check("narrow window, no swing: nothing", #v == 0, #v)

	v = run({ windowFor = function(now) return pred(now - 0.5, now) end, deathAt = t0 + 0.7 })
	check("unreachable wide window: nothing", #v == 0, #v)

	v = run({ windowFor = wide, deathAt = t0 + 0.7, eligible = false })
	check("hero fight excludes the creep", #v == 0, #v)

	v = run({ windowFor = wide, deathAt = t0 + 0.7, subjectAlive = false })
	check("dead subject is not charged easy misses", #v == 0, #v)

	v = run({ windowFor = wide, deathAt = t0 + 0.7, dist = 900 })
	check("creep beyond 800 is not an easy miss", #v == 0, #v)

	v = run({ windowFor = wide, deathAt = t0 + 0.7, killer = { kind = "subject" } })
	check("subject kill is not a miss", #v == 0, #v)
end

-- Swung at 0.33 s in, just after the ideal moment (0.31); the projectile would have landed at t0 + 0.73.
do
	local v = run({ windowFor = wide, deathAt = t0 + 0.5, swingAt = t0 + 0.33 })
	check("late on a wide window: exactly one verdict", #v == 1, #v)
	local e = v[1] or {}
	check("late on a wide window is MISSED_EASY with the swing kept", e.kind == "MISSED_EASY" and e.swung == true and (e.offset or 0) > 0, e.kind)
	check("late reason", e.reason == "missed easy one - 0.42s window, you were 0.23s late", e.reason)

	v = run({ windowFor = function() return pred(t0 + 0.1, t0 + 0.3) end, deathAt = t0 + 0.5, swingAt = t0 + 0.2 })
	check("late on a narrow window stays LATE", #v == 1 and v[1].kind == "LATE", v[1] and v[1].kind)

	v = run({ windowFor = wide, deathAt = t0 + 1.2, swingAt = t0 + 0.2 })
	check("a miss after the landing time is not an easy miss", #v == 1 and v[1].kind == "MISS", v[1] and v[1].kind)
end

-- A creep that leaves vision is never graded: the lifecycle drops it, so the judge only stops seeing it.
do
	check("invalid handle at 80% HP is not a death", Watch.IsDeathLikely(80, 100, 58, 300) == false)
	check("low, close creep is a death", Watch.IsDeathLikely(40, 100, 58, 300) == true)
	check("one-hit-low creep is a death even when above 30%", Watch.IsDeathLikely(50, 100, 58, 300) == true)
	check("out of range, even if low, is not a death", Watch.IsDeathLikely(10, 100, 58, 1300) == false)

	local judge, count = NewJudge(), 0
	local now = t0
	while now <= t0 + 6 do
		local creeps = {}
		if now < t0 + 0.5 then
			creeps[1] = { id = "A", kind = "melee", isDeny = false, alive = true, hp = 71, dist = 100, prediction = pred(t0 + 0.1, t0 + 0.52) }
		end
		count = count + #judge:Step({ now = now, alive = true, eligible = true, harassed = false, anim = "none", lastHits = 0, denies = 0 }, creeps)
		now = now + DT
	end
	check("a creep that vanishes produces no events, ever", count == 0, count)
end

-- Attribution.
do
	local function counters(lh, dn) return { lastHits = lh or {}, denies = dn or {} } end
	local heroes = { { pid = 1, ally = true, name = "Me" }, { pid = 2, ally = true, name = "Lion" }, { pid = 7, ally = false, name = "Axe" } }
	local theirs = { id = "A", kind = "melee", isDeny = false, alive = false, hp = 0, dist = 0 }
	local ours = { id = "A", kind = "melee", isDeny = true, alive = false, hp = 0, dist = 0 }
	local before = counters({ [1] = 5, [2] = 5, [7] = 5 }, { [1] = 1, [2] = 1, [7] = 1 })
	local function kind(creep, lh, dn, tower)
		local after = counters(lh, dn)
		local k = Watch.Attribute(creep, 1, before, after, heroes, tower)
		return k.kind, k.name
	end

	check("subject last hit wins over everything", kind(theirs, { [1] = 6, [2] = 6, [7] = 6 }, {}, true) == "subject")
	check("subject deny on our creep", kind(ours, {}, { [1] = 2 }, false) == "subject")
	check("subject last hit does not count for our creep", kind(ours, { [1] = 6 }, {}, false) == "creep")
	local k, name = kind(theirs, { [2] = 6, [7] = 6 }, {}, true)
	check("ally beats enemy and tower", k == "ally" and name == "Lion", k)
	k, name = kind(theirs, { [7] = 6 }, {}, true)
	check("enemy last hit on their creep", k == "enemyHero" and name == "Axe", k)
	k, name = kind(ours, {}, { [7] = 2 }, false)
	check("enemy deny on our creep", k == "enemyHero" and name == "Axe", k)
	check("enemy deny does not count for their creep", kind(theirs, {}, { [7] = 2 }, false) == "creep")
	check("tower when nobody scored", kind(theirs, {}, {}, true) == "tower")
	check("creep otherwise", kind(theirs, {}, {}, false) == "creep")
end

-- Selection.
do
	local subject = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	local n = 0
	local function cand(x, close, o)
		n = n + 1
		local u = MakeUnit({ pid = 500 + n, team = 3, loc = Vector(x, 0) })
		for k, v in pairs(o or {}) do u[k] = v end
		return { creep = u, isDeny = false, prediction = close and pred(close - 0.3, close) or nil }
	end
	local a, b, c, d = cand(100, 105), cand(100, 101), cand(100, 103), cand(100, 104)
	local far = cand(900, 100)
	local dead = cand(100, 99, { alive = false })
	local none = cand(100, nil)
	subject.GetAttackTarget = function() return a.creep end

	local sel = Watch.SelectCreeps(subject, { a, b, c, d, far, dead, none }, 2, 1)
	check("attack target is the first bar", sel.bars[1] == a.creep)
	check("second bar is the earliest startClose", sel.bars[2] == b.creep)
	check("bars are capped", #sel.bars == 2)
	check("watched is the next by startClose, capped", #sel.watched == 1 and sel.watched[1] == c.creep, #sel.watched)

	subject.GetAttackTarget = function() return nil end
	sel = Watch.SelectCreeps(subject, { a, b, c, d, far, dead, none }, 2, 2)
	check("no target: earliest two get bars", sel.bars[1] == b.creep and sel.bars[2] == c.creep)
	check("no target: remaining by startClose are watched", #sel.watched == 2 and sel.watched[1] == d.creep and sel.watched[2] == a.creep)
	local all = {}
	for _, u in ipairs(sel.bars) do all[u] = true end
	for _, u in ipairs(sel.watched) do all[u] = true end
	check("far, dead and predictionless creeps are never selected", not all[far.creep] and not all[dead.creep] and not all[none.creep])
end

finish()
