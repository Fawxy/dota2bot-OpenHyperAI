-- Slice pre-hit: the two questions on a creep's forecast HP (states/pre_hit Decide) and the pre-hit's rank in lane_pick Choose.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local PreHit = require("bots/FunLib/humaniser/states/pre_hit")
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

-- A tower hitting for 100 every second, the first hit landing at 0.3 s; `drain` HP per second from creeps spread evenly.
local function towerHp(hp, drain)
	return function(t)
		local n = t >= 0.3 and math.floor((t - 0.3) / 1.0) + 1 or 0
		return hp - 100 * n - (drain or 0) * t
	end
end

-- Our core: 50 at the low roll, 56 at the high, first landing at 0.4 s, 1.4 s between attacks.
local LO, HI, T0, PERIOD = 50, 56, 0.4, 1.4
local function decide(hp, drain) return PreHit.Decide(towerHp(hp, drain), PreHit.HORIZON, T0, PERIOD, LO, HI) end

-- 290 HP: the tower steps it 190, 90, then dead; never in (0, 50]. One hit of ours at 0.4 s makes it 140, 40 from 1.3 s
-- until the tower's 2.3 s hit, and our next swing can land from 1.8 s: a 0.5 s window. Pre-hit.
check("decide: tower steps over our kill range, one hit makes a window: go", decide(290) == "go")

-- 230 HP: 130, then 30 from 1.3 s to 2.3 s, a window of its own: the last-hit verb takes it, no pre-hit.
check("decide: a window already there: no pre-hit", decide(230) == "window")

-- 180 HP: 80, then dead at 1.3 s. A hit of ours at 0.4 s leaves 30 at 1.3 s, but our next swing lands at 1.8 s at the earliest:
-- the tower's 1.3 s hit already killed it. No pre-hit (it would only feed the tower).
check("decide: the window a pre-hit makes closes before our next swing: no", decide(180) == "no-after")

-- 900 HP: still above 0 at the horizon, so the forecast cannot say yet.
check("decide: creep outlives the horizon: undecided", decide(900) == "open")

-- 153 HP: 53 when our hit lands at 0.4 s, until the tower kills it at 1.3 s: no window at the low roll, but the high roll kills
-- at t0, so the swing is a last hit (a gamble on the roll), not a pre-hit.
check("decide: a hit at t0 that may kill is not a pre-hit", decide(153) == "kills")

-- A weak hero (25 / 28): 290 HP steps 190, 90, dead; after our hit 165, 65, dead: still never in (0, 25]. No.
check("decide: one hit is not enough to make a window: no",
	PreHit.Decide(towerHp(290), PreHit.HORIZON, T0, PERIOD, 25, 28) == "no-after")

-- Both rolls must make a window.
do
	-- 296 HP: low roll -> 46 at 1.3 s (window), high roll -> 40 (window): go.
	check("decide: both rolls make a window: go", decide(296) == "go")
	-- A wide spread (40 / 56): 295 HP steps 195, 95, dead. The high roll leaves 39 at 1.3 s, inside the low roll's range, but
	-- the low roll leaves 55: above it. No.
	check("decide: the low roll leaves it above our range: no",
		PreHit.Decide(towerHp(295), PreHit.HORIZON, T0, PERIOD, 40, 56) == "no-after")
end

-- Even creep damage between the tower's hits makes windows of its own: 290 HP with 40 HP/s from creeps is 38 at 1.3 s and
-- lasts about 0.9 s more, so the last-hit verb has it and there is no pre-hit.
check("decide: creep damage spreads the steps into a window: no pre-hit", decide(290, 40) == "window")

-- WindowFrom: a window counts only from `from` on, and only when it lasts WINDOW_MIN.
do
	local hp = towerHp(230)
	check("window: from inside the window on, still a window", PreHit.WindowFrom(hp, 3.5, LO, 2.0) == "window")
	check("window: from after it closed, dead", PreHit.WindowFrom(hp, 3.5, LO, 2.35) == "dead")
	-- 0.1 s in range before the tower's hit: under WINDOW_MIN.
	check("window: shorter than WINDOW_MIN is none", PreHit.WindowFrom(hp, 3.5, LO, 2.2) == "dead")
end

-- Choose: the pre-hit ranks below a reachable last hit on another creep, whatever its eta (a pre-hit spends our attack cycle;
-- user 04/11/2026), above every deny, and replaces a wait on its own creep.
local function target(kind, eta, creep, walk, dies)
	return { creep = creep or {}, kind = kind, eta = eta, due = eta, walk = walk or 0, dies = dies or math.huge, ranged = false }
end
do
	local c = {}
	local pre = target("prehit", 0, c)
	local lh = target("lasthit", 0.9)
	check("choose: a reachable last hit on another creep beats the pre-hit", Pick.Choose({ lh }, nil, nil, pre) == lh)
	local far = target("lasthit", 0, nil, 2, 1)
	check("choose: an unreachable last hit does not block it", Pick.Choose({ far }, nil, nil, pre) == pre)
	local d = target("deny", 0)
	check("choose: the pre-hit beats a deny due now", Pick.Choose({ d }, nil, nil, pre) == pre)
	local same = target("lasthit", 0.8, c)
	check("choose: the pre-hit replaces a wait on its own creep", Pick.Choose({ same }, same, nil, pre) == pre)
	check("choose: with nothing offered, the pre-hit", Pick.Choose({}, nil, nil, pre) == pre)
	-- A last hit that is not this laner's (a support's claims) does not block it.
	local function denies(t) return t.kind == "deny" end
	check("choose: a last hit not mine does not block it", Pick.Choose({ lh }, nil, denies, pre) == pre)
end

finish()
