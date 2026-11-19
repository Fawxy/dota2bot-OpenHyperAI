-- Safe here (design 2026-11-19-safe-here-design.md section 6.1): Decide over plain inputs, one check per row, case and
-- control in one check, so a Decide that always answers one level fails every one. A hero of 630 of 1000 HP unless set.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })
local S = require("bots/FunLib/humaniser/safe")

local function inputs(o)
	local i = { hp = 630, hpMax = 1000, reach = {}, missing = 0, tower = false, towerOnMe = false,
		landing = { hero = 0, creeps = 0, tower = 0 }, away = false, held = false, hold = false }
	for k, v in pairs(o or {}) do i[k] = v end
	return i
end
local function one(dmg, extra)
	local r = { pid = 3, hitting = false, dmg = dmg }
	for k, v in pairs(extra or {}) do r[k] = v end
	return r
end
local function hit(dmg, extra)
	local r = one(dmg, extra)
	r.hitting = true
	return r
end
local function is(a, level, reason)
	return a.level == level and (reason == nil or a.reason == reason)
end

-- h2hsnapcreeps1_B_dire_2 t=396: HP 63%, one hero, burst 0.97 (ratio 1.03)
check("Oracle case (ratio 1.03) with the hero hitting us: deadly held and fresh at stay 1.25, safe at half the damage; at stay 1.0 it reads safe held, so the bar needs a margin",
	is(S.Decide(inputs({ reach = { hit(611) }, held = true }), 1.25), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { hit(611) }, held = false }), 1.25), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { hit(305.5) }, held = true }), 1.25), "safe")
		and is(S.Decide(inputs({ reach = { hit(611) }, held = true }), 1.0), "safe"))

check("two heroes in reach with little damage are safe; the same two with real damage are deadly",
	is(S.Decide(inputs({ reach = { one(40), one(40, { pid = 4 }) } })), "safe")
		and is(S.Decide(inputs({ reach = { one(300), one(300, { pid = 4 }) } })), "deadly", "kill"))

check("an enemy tower in reach or on us is deadly with nobody in reach; neither flag: safe",
	is(S.Decide(inputs({ tower = true })), "deadly", "tower")
		and is(S.Decide(inputs({ towerOnMe = true })), "deadly", "tower")
		and is(S.Decide(inputs()), "safe", "safe"))

check("a held place in tower reach is not deadly unless the tower targets us; the same place fresh is deadly",
	is(S.Decide(inputs({ tower = true, held = true })), "safe")
		and is(S.Decide(inputs({ tower = true, held = false })), "deadly", "tower")
		and is(S.Decide(inputs({ tower = true, towerOnMe = true, held = true })), "deadly", "tower"))

check("away with 0.6 unseen weight is deadly unknown; 0.3 is not; 0.6 without away is not",
	is(S.Decide(inputs({ away = true, missing = 0.6 })), "deadly", "unknown")
		and is(S.Decide(inputs({ away = true, missing = 0.3 })), "safe")
		and is(S.Decide(inputs({ away = false, missing = 0.6 })), "safe"))

check("a hero hitting us: held keeps a place a fresh read refuses: ratio 1.3 with stay 1.25 is safe held and deadly fresh (bar 1.44); ratio 1.2 is deadly held too",
	is(S.Decide(inputs({ reach = { hit(630 / 1.3) }, held = true })), "safe")
		and is(S.Decide(inputs({ reach = { hit(630 / 1.3) }, held = false })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { hit(630 / 1.2) }, held = true })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { hit(630 / 1.5) }, held = false })), "safe"))

check("a hero hitting us: a hold stays at ratio 1.2 and is deadly at 0.9; without a hold 1.2 is deadly",
	is(S.Decide(inputs({ reach = { hit(630 / 1.2) }, hold = true })), "safe")
		and is(S.Decide(inputs({ reach = { hit(630 / 0.9) }, hold = true })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { hit(630 / 1.2) } })), "deadly", "kill"))

check("a hold never makes the bar stricter than stay (stay 0.8, ratio 0.9 is safe with or without a hold) and is never raised by the fresh share (ratio 1.2 holds, fresh or not)",
	is(S.Decide(inputs({ reach = { one(630 / 0.9) }, hold = true }), 0.8), "safe")
		and is(S.Decide(inputs({ reach = { one(630 / 0.9) }, held = true }), 0.8), "safe")
		and is(S.Decide(inputs({ reach = { one(630 / 1.2) }, hold = true, held = false })), "safe"))

check("an unseen lane opponent counts in kill like a visible one",
	is(S.Decide(inputs({ reach = { one(611, { unseen = true }) } })), "deadly", "kill")
		and S.Decide(inputs({ reach = { one(300), one(311, { unseen = true, pid = 4 }) } })).kill == 611)

-- h2h742 (30 games): 56 kill leaves a game began with nobody hitting and HP between 1.0 and 1.25 of the kill line; none of the 160 called deaths needed them.
check("nobody hitting: a held place at ratio 1.1 is safe and at 0.95 deadly; the same 1.1 with the hero hitting is deadly",
	is(S.Decide(inputs({ reach = { one(630 / 1.1) }, held = true })), "safe")
		and is(S.Decide(inputs({ reach = { one(630 / 0.95) }, held = true })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { one(630 / 1.1, { hitting = true }) }, held = true })), "deadly", "kill"))

check("nobody hitting, a fresh place: the bar is 1.15 (ratio 1.2 safe, 1.1 deadly); one of two reachers hitting puts the whole line at 1.25",
	is(S.Decide(inputs({ reach = { one(630 / 1.2) } })), "safe")
		and is(S.Decide(inputs({ reach = { one(630 / 1.1) } })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { one(630 / 2.4, { hitting = true }), one(630 / 2.4, { pid = 4 }) }, held = true })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { one(630 / 2.4), one(630 / 2.4, { pid = 4 }) }, held = true })), "safe"))

-- The reviewer's case: a laner's swings are over a second apart, so between them no reacher is `hitting`. `pressed` (a hero damaged us
-- in the last 3 s) holds the bar at 1.25 across the gap; a bar on `hitting` alone read safe there and sent the hero back in.
check("between swings (pressed, nobody hitting) ratio 1.1 held is still deadly and a fresh place at 1.3 too; with neither both are safe",
	is(S.Decide(inputs({ reach = { one(630 / 1.1) }, held = true, pressed = true })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { one(630 / 1.3) }, pressed = true })), "deadly", "kill")
		and is(S.Decide(inputs({ reach = { one(630 / 1.1) }, held = true, pressed = false })), "safe")
		and is(S.Decide(inputs({ reach = { one(630 / 1.3) }, pressed = false })), "safe"))

check("Line: the stay bar under a hero's hits, the lower of it and idle without; a stay under idle is never raised",
	S.Line(true) == 1.25 and S.Line(false) == 1.0 and S.Line(false, 2.0) == 1.0 and S.Line(true, 2.0) == 2.0 and S.Line(false, 0.8) == 0.8)

do
	local none = S.Decide(inputs())
	check("nothing in reach: kill 0, ratio math.huge, safe even at zero HP-share concerns",
		none.kill == 0 and none.ratio == math.huge and none.level == "safe"
			and S.Decide(inputs({ hp = 5 })).level == "safe")
end

check("price picks the reason by the largest landing part, ties hero then creeps then tower; zero is safe",
	is(S.Decide(inputs({ landing = { hero = 10, creeps = 30, tower = 20 } })), "costly", "creeps")
		and is(S.Decide(inputs({ landing = { hero = 10, creeps = 5, tower = 20 } })), "costly", "tower")
		and is(S.Decide(inputs({ landing = { hero = 30, creeps = 5, tower = 20 } })), "costly", "hero")
		and is(S.Decide(inputs({ landing = { hero = 10, creeps = 10, tower = 10 } })), "costly", "hero")
		and is(S.Decide(inputs({ landing = { hero = 0, creeps = 10, tower = 10 } })), "costly", "creeps")
		and S.Decide(inputs({ landing = { hero = 10, creeps = 30, tower = 20 } })).price == 60)

check("costly never outranks deadly, and the price is still reported on a deadly answer",
	is(S.Decide(inputs({ reach = { one(611) }, landing = { hero = 50, creeps = 0, tower = 0 } })), "deadly", "kill")
		and S.Decide(inputs({ reach = { one(611) }, landing = { hero = 50, creeps = 0, tower = 0 } })).price == 50
		and is(S.Decide(inputs({ tower = true, landing = { hero = 50, creeps = 0, tower = 0 } })), "deadly", "tower")
		and is(S.Decide(inputs({ away = true, missing = 0.6, landing = { hero = 50, creeps = 0, tower = 0 } })), "deadly", "unknown"))

do
	local base = inputs({ reach = { one(611) } })
	local with = inputs({ reach = { one(611) }, exit = 0.4 })
	local safeBase = inputs({ reach = { one(200) } })
	local safeWith = inputs({ reach = { one(200) }, exit = 9 })
	check("exit is logged only: it changes neither a deadly nor a safe answer",
		is(S.Decide(base), "deadly", "kill") and is(S.Decide(with), "deadly", "kill")
			and is(S.Decide(safeBase), "safe") and is(S.Decide(safeWith), "safe"))
end
finish()
