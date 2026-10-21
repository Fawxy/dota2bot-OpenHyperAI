dofile(HARNESS_DIR .. "/dota_stubs.lua")

local Judge = require("bots/FunLib/humaniser/trainer/judge")
local Format = require("bots/FunLib/humaniser/trainer/format")

local function NewJudge()
	local j = setmetatable({}, Judge.Judge.prototype)
	Judge.Judge.prototype.____constructor(j, 0.3)
	return j
end

local t0 = 100
local DT = 1 / 30

-- Window and times are absolute; ideal defaults to the window midpoint.
local function pred(open, close, o)
	o = o or {}
	return { startOpen = open, startClose = close, ideal = o.ideal or (open + close) / 2, delay = o.delay or 0.4,
		effDmg = o.eff or 58, hp = o.hp or 71, curve = {}, at = t0, isDeny = false, uncertain = false }
end

local function creep(id, o)
	local c = { id = id, kind = "melee", isDeny = false, alive = true, hp = 71, dist = 100 }
	for k, v in pairs(o or {}) do c[k] = v end
	return c
end

local function newRun()
	local r = { judge = NewJudge(), verdicts = {}, outcomes = {} }
	-- script(now) returns the subject fields and the creep list for that frame.
	function r.play(from, to, script)
		local now = from
		while now <= to + 1e-9 do
			local s, creeps = script(now)
			local obs = { now = now, alive = true, eligible = true, harassed = false, anim = "none", lastHits = 0, denies = 0 }
			for k, v in pairs(s) do obs[k] = v end
			for _, e in ipairs(r.judge:Step(obs, creeps)) do
				if e.type == "verdict" then
					e.v.seenAt = now
					table.insert(r.verdicts, e.v)
				else
					table.insert(r.outcomes, e)
				end
			end
			now = now + DT
		end
	end
	return r
end

-- Swing begins at swingStart, reaches followthrough after 0.2 s, and idles after 0.35 s.
local function swingAnim(swingStart, now)
	if now < swingStart + 0.2 then return "swing" end
	if now < swingStart + 0.35 then return "followthrough" end
	return "none"
end

-- A swing at swingStart on creep A that ends with the creep dying at deathAt.
local function killScript(swingStart, deathAt, window, killer, creepOpts)
	return function(now)
		local dead = now >= deathAt - 1e-9
		local c = creep("A", creepOpts)
		c.prediction = window
		if dead then c.alive = false c.hp = 0 c.killer = killer end
		local s = { anim = dead and "none" or swingAnim(swingStart, now), target = "A", swingStart = swingStart }
		if now < swingStart then s.anim = "none" end
		return s, { c }
	end
end

local function only(name, r, kind)
	check(name .. ": exactly one verdict", #r.verdicts == 1, #r.verdicts)
	check(name .. ": kind is " .. kind, r.verdicts[1] ~= nil and r.verdicts[1].kind == kind, r.verdicts[1] and r.verdicts[1].kind)
	return r.verdicts[1] or {}
end

-- Formatting.
check("Sec trims trailing zeros", Format.Sec(0.1) == "0.1" and Format.Sec(0.12) == "0.12" and Format.Sec(1) == "1" and Format.Sec(0.126) == "0.13")
check("Signed always shows a sign", Format.Signed(0.03) == "+0.03" and Format.Signed(-0.11) == "-0.11" and Format.Signed(-0.001) == "+0")

-- PERFECT: swing starts inside the window.
do
	local r = newRun()
	local w = pred(t0 - 0.2, t0 + 0.4, { ideal = t0 })
	r.play(t0 + 0.03, t0 + 1.0, function(now)
		local s, cs = killScript(t0 + 0.03, t0 + 0.43, w, { kind = "subject" })(now)
		s.harassed = true
		return s, cs
	end)
	local v = only("perfect inside window", r, "PERFECT")
	check("perfect reason carries the signed offset", v.reason == "perfect (+0.03s)", v.reason)
	check("perfect offset is swing start minus ideal", near(v.offset or 99, 0.03))
	check("verdict carries creep identity and harassed flag", v.creepId == "A" and v.creepKind == "melee" and v.isDeny == false and v.harassed == true)
	check("perfect: one outcome, subject got it", #r.outcomes == 1 and r.outcomes[1].creepId == "A" and r.outcomes[1].subjectGotIt == true, #r.outcomes)
end

-- OK: killed by the subject but the swing started outside the window.
do
	local r = newRun()
	local w = pred(t0 - 0.2, t0 + 0.4, { ideal = t0 })
	r.play(t0 + 0.6, t0 + 2.0, killScript(t0 + 0.6, t0 + 1.0, w, { kind = "subject" }))
	local v = only("ok after window", r, "OK")
	check("ok reason says how late", v.reason == "got it (window said 0.2s late)", v.reason)

	r = newRun()
	r.play(t0 - 0.3, t0 + 1.0, killScript(t0 - 0.3, t0 + 0.1, w, { kind = "subject" }))
	v = only("ok before window", r, "OK")
	check("ok reason says how early", v.reason == "got it (window said 0.1s early)", v.reason)
end

-- EARLY: the hit lands without killing.
do
	local r = newRun()
	local w = pred(t0 + 0.25, t0 + 0.6, { ideal = t0 + 0.4 })
	r.play(t0, t0 + 3.0, function(now)
		local c = creep("A", { prediction = w })
		if now >= t0 + 0.4 - 1e-9 then c.hp = 13 end
		return { anim = swingAnim(t0, now), target = "A", swingStart = t0 }, { c }
	end)
	local v = only("early", r, "EARLY")
	check("early reason", v.reason == "early by 0.25s - creep had 71 HP, you deal 58", v.reason)
	check("early offset is swing start minus ideal", near(v.offset or 99, -0.4), v.offset)
end

-- LATE: somebody else kills the creep before our hit lands.
do
	local cases = {
		{ "creep", { kind = "creep" }, "late by 0.1s - lane creep took it" },
		{ "tower", { kind = "tower" }, "late by 0.1s - tower took it" },
		{ "ally", { kind = "ally", name = "Lina" }, "late by 0.1s - Lina took it" },
		{ "enemy deny", { kind = "enemyHero", name = "Axe" }, "late by 0.1s - denied by Axe" },
	}
	for _, case in ipairs(cases) do
		local r = newRun()
		local w = pred(t0 - 0.1, t0 + 0.1, { ideal = t0 })
		r.play(t0, t0 + 1.0, killScript(t0, t0 + 0.3, w, case[2]))
		local v = only("late to " .. case[1], r, "LATE")
		check("late reason for " .. case[1], v.reason == case[3], v.reason)
		check("late to " .. case[1] .. ": subject did not get it", #r.outcomes == 1 and r.outcomes[1].subjectGotIt == false)
	end
end

-- CANCELLED.
do
	local r = newRun()
	local w = pred(t0 - 0.1, t0 + 0.4, { ideal = t0 })
	r.play(t0, t0 + 3.0, function(now)
		local c = creep("A", { prediction = w })
		local anim = now < t0 + 0.1 and "swing" or "none"
		return { anim = anim, target = "A", swingStart = t0 }, { c }
	end)
	local v = only("cancelled swing", r, "CANCELLED")
	check("cancelled reason", v.reason == "cancelled swing", v.reason)
	check("cancelled swing is not later reported as a miss", #r.verdicts == 1)
end

-- Retarget mid-swing.
do
	local r = newRun()
	local wA = pred(t0 - 0.1, t0 + 0.4, { ideal = t0 })
	local wB = pred(t0 + 0.3, t0 + 0.9, { ideal = t0 + 0.6 })
	local retarget = t0 + 0.1
	local swingB = retarget
	r.play(t0, t0 + 2.0, function(now)
		local cA = creep("A", { prediction = wA })
		local cB = creep("B", { prediction = wB })
		local s
		if now < retarget - 1e-9 then
			s = { anim = "swing", target = "A", swingStart = t0 }
		else
			s = { anim = swingAnim(swingB, now), target = "B", swingStart = swingB }
			if now >= swingB + 0.5 - 1e-9 then
				cB.alive = false cB.hp = 0 cB.killer = { kind = "subject" }
				s.anim = "none"
			end
		end
		return s, { cA, cB }
	end)
	check("retarget: two verdicts", #r.verdicts == 2, #r.verdicts)
	local a, b = r.verdicts[1] or {}, r.verdicts[2] or {}
	check("retarget: A is cancelled", a.kind == "CANCELLED" and a.creepId == "A", a.kind)
	check("retarget: B starts a fresh attempt and resolves on its own", b.creepId == "B" and (b.kind == "OK" or b.kind == "PERFECT"), b.kind)
	check("retarget: B's offset is measured from its own swing start", near(b.offset or 99, swingB - (t0 + 0.6)), b.offset)
	check("retarget: only B has an outcome", #r.outcomes == 1 and r.outcomes[1].creepId == "B" and r.outcomes[1].subjectGotIt == true)
end

-- MISS: our hit should have landed, nothing happened.
do
	local r = newRun()
	local w = pred(t0 - 0.1, t0 + 0.4, { ideal = t0 })
	r.play(t0, t0 + 3.0, function(now)
		return { anim = swingAnim(t0, now), target = "A", swingStart = t0 }, { creep("A", { prediction = w }) }
	end)
	local v = only("miss after landing passes", r, "MISS")
	check("miss reason", v.reason == "missed - evasion/uphill?", v.reason)
	check("miss is declared 0.3 s after the predicted landing, not before", v.seenAt > t0 + 0.7 and v.seenAt < t0 + 0.8, v.seenAt)
end

-- Double tap: first hit does not kill, the second does.
do
	local r = newRun()
	local w1 = pred(t0 + 0.25, t0 + 0.6, { ideal = t0 + 0.4 })
	local w2 = pred(t0 + 0.5, t0 + 1.2, { ideal = t0 + 0.8, hp = 13 })
	local second = t0 + 0.6
	r.play(t0, t0 + 3.0, function(now)
		local c = creep("A")
		local s
		if now < second - 1e-9 then
			c.prediction = w1
			if now >= t0 + 0.4 - 1e-9 then c.hp = 13 end
			s = { anim = swingAnim(t0, now), target = "A", swingStart = t0 }
		else
			c.prediction = w2
			c.hp = 13
			s = { anim = swingAnim(second, now), target = "A", swingStart = second }
			if now >= second + 0.4 - 1e-9 then
				c.alive = false c.hp = 0 c.killer = { kind = "subject" }
				s.anim = "none"
			end
		end
		return s, { c }
	end)
	check("double tap: EARLY then a new attempt", #r.verdicts == 2 and r.verdicts[1].kind == "EARLY" and (r.verdicts[2].kind == "PERFECT" or r.verdicts[2].kind == "OK"),
		#r.verdicts .. " " .. tostring(r.verdicts[1] and r.verdicts[1].kind) .. " " .. tostring(r.verdicts[2] and r.verdicts[2].kind))
	check("double tap: exactly one outcome, subject got it", #r.outcomes == 1 and r.outcomes[1].subjectGotIt == true, #r.outcomes)
end

-- Forced resolution.
do
	local r = newRun()
	local w = pred(t0 - 0.1, t0 + 0.4, { ideal = t0 })
	r.play(t0, t0 + 4.0, function(now)
		local cs = now < t0 + 0.2 and { creep("A", { prediction = w }) } or {}
		return { anim = swingAnim(t0, now), target = "A", swingStart = t0 }, cs
	end)
	local v = only("forced resolution", r, "MISS")
	check("forced resolution lands at 2.5 s", v.seenAt >= t0 + 2.5 - 1e-9 and v.seenAt < t0 + 2.6, v.seenAt)
end

-- A creep nobody swung at produces no outcome.
do
	local r = newRun()
	r.play(t0, t0 + 0.5, function(now)
		local c = creep("A")
		if now >= t0 + 0.2 then c.alive = false c.killer = { kind = "creep" } end
		return { anim = "none" }, { c }
	end)
	check("no attempt, no verdict and no outcome", #r.verdicts == 0 and #r.outcomes == 0)
end

finish()
