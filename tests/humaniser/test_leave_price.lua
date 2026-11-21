-- The priced leave's pure decider (decision centre pilot steps 2 and 3; master docs/proposals/decision-centre/step2-3-decider.md s5
-- and s7 cases 1 to 4, plus the marginal two-hero case of "Not verified"). Gold from tools/dc/prices.json via dc_prices.ts.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local LP = require("bots/FunLib/humaniser/leave_price")
local P = require("bots/FunLib/humaniser/dc_prices")

local CONV1 = P.CONVERSION[1]
-- Inputs with farm in reach F (converted gold) at position 1; w 1,200 at 300 is no walk cost.
local function inputs(t)
	local i = { hp = 70, hs = 1, thp = 50, n = 1, w = 1200, ms = 300, pos = 1, cg = 0 }
	for k, v in pairs(t) do i[k] = v end
	if t.F then i.cg, i.F = t.F / CONV1, nil end
	return i
end
local function near(a, b, tol) return a ~= nil and math.abs(a - b) <= (tol or 1) end
local function show(r) return string.format("pick=%s stay=%s leave=%s d=%s M=%s", r.pick, tostring(r.stay), tostring(r.leave), tostring(r.d), tostring(r.M)) end

-- 1. Hard leaves: no price.
do
	local r = LP.Decide(inputs({ F = 20, burst = true }), "stay")
	check("1. burst now: leave, hard=burst, no prices", r.pick == "leave" and r.hard == "burst" and r.stay == nil and r.d == nil, show(r))
	r = LP.Decide(inputs({ hp = 90, hs = 0, F = 200, tower = true, heal = true }), "stay")
	check("a tower on us leaves first, whatever the price", r.pick == "leave" and r.hard == "tower", show(r))
	r = LP.Decide(inputs({ hp = 90, hs = 0, F = 200, heal = true }), "stay")
	check("the heal rule leaves with no price", r.pick == "leave" and r.hard == "heal" and r.stay == nil, show(r))
end

-- 2. A lone poke stays: HP 70%, hs 1, T 50%, n 1, w 1,200, F 20, incumbent leave. Stay 38, leave -10, d 48 > 30.
do
	local r = LP.Decide(inputs({ F = 20 }), "leave")
	check("2. lone poke: stay 38, leave -10, d 48 over M 30: stay", r.pick == "stay" and near(r.stay, 38) and near(r.leave, -10) and near(r.d, 48) and r.M == 30, show(r))
	check("the leave side has no kill term with n 1 (P_k(T, 0) = 0) and no walk cost at w 1,200", r.pkl == 0 and r.W == 0, show(r))
end

-- 3. Two heroes committed leave: HP 50%, hs 2, T 50%, n 1, w 1,200, F 20. Stay -57, leave -20.
do
	local r = LP.Decide(inputs({ hp = 50, hs = 2, F = 20 }), "leave")
	check("3. two committed: stay -57, leave -20: leave", r.pick == "leave" and near(r.stay, -57) and near(r.leave, -20), show(r))
	r = LP.Decide(inputs({ hp = 50, hs = 2, F = 20 }), "stay")
	check("an incumbent stay leaves too (d -37 under -30)", r.pick == "leave", show(r))
end

-- 4. The incumbent margin. HP 70%, hs 2, T 90%: d = F - 51 alone; with n 2 the kill terms add 16.6.
do
	local base = inputs({ hs = 2, thp = 90 })
	local d0 = LP.Decide(base, "leave").d
	local at = function(d, t) local i = inputs({ hs = 2, thp = 90 }) for k, v in pairs(t or {}) do i[k] = v end i.cg = (d - d0) / CONV1 return i end
	local r1, r2 = LP.Decide(at(-20), "stay"), LP.Decide(at(-20), "leave")
	check("4. d = -20: an incumbent stay keeps staying, an incumbent leave keeps leaving", near(r1.d, -20, 0.01) and r1.pick == "stay" and r2.pick == "leave", show(r1) .. " | " .. show(r2))
	local r3 = LP.Decide(at(20), "leave")
	check("d = +20, incumbent leave, no release: leave (within M 30)", r3.pick == "leave" and r3.M == 30, show(r3))
	-- The release: n goes from 1 to 2, which moves the kill terms; pick F so that d is +20 at n 2.
	local d2 = LP.Decide(inputs({ hs = 2, thp = 90, n = 2 }), "leave").d
	local i4 = inputs({ hs = 2, thp = 90, n = 2, rel = true })
	i4.cg = (20 - d2) / CONV1
	local r4 = LP.Decide(i4, "leave")
	check("d = +20, incumbent leave, a release (n 1 to 2): M 0, stay", near(r4.d, 20, 0.01) and r4.M == 0 and r4.rel == 1 and r4.pick == "stay", show(r4))
end

-- 5. The marginal two-hero stay: HP 30%, poked, two on a 30% target: d = F - 25, so it needs farm to stay.
do
	local r = LP.Decide(inputs({ hp = 30, hs = 1, thp = 30, n = 2, F = 20 }), "leave")
	check("two on a 30% target, HP 30% poked: d = F - 25 (P_k(n - 1) on the leave side); F 20 leaves", near(r.d, 20 - 25) and r.pick == "leave" and r.pkl > 0, show(r))
	r = LP.Decide(inputs({ hp = 30, hs = 1, thp = 30, n = 2, F = 60 }), "leave")
	check("the same with F 60: d 35 over M 30, stay", near(r.d, 35) and r.pick == "stay", show(r))
end

-- The walk back: w 2,500 at 300, position 1: 27 gold, and a leave's death price reads the walk bin.
do
	check("W at w 2,500, ms 300, 4 creeps a 30 s: 27 gold", near(LP.Walk(1, 2500, 300, 4 / 30), 27, 0.5), LP.Walk(1, 2500, 300, 4 / 30))
	check("P_dl reads the walk bin and the committed column", LP.PDeathLeave(70, 1, 1000) < LP.PDeathLeave(70, 1, 2000) and LP.PDeathLeave(50, 2, 1000) > LP.PDeathLeave(50, 1, 1000))
	check("HP 100% is the top bin and HP 0 the bottom", LP.PDeathStay(100, 0) == P.DEATH_STAY.p[13] and LP.PDeathStay(0, 2) == P.DEATH_STAY.p[3])
end
finish()
