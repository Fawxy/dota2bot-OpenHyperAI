-- The contest walk-in's HP price (states/contest PriceOf), pure.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local C = require("bots/FunLib/humaniser/states/contest")

-- A level-1 melee core (640 HP, 300 movement) walking 2 s in for a creep beside one enemy.
local function price(threats, opts)
	opts = opts or {}
	return C.PriceOf(threats, opts.walk or 2, opts.wait or 0.3, 0.4, 300, opts.hp or 640, 640, opts.tower == true)
end
local ranged = function(d, nuke) return { d = d, zone = 600 + 48 + 48 + 150, dps = 50 / 1.7, nuke = nuke or 0 } end

-- The creep 300 inside a ranged enemy's zone: in 300 and out 300 (2 s), the wait and the swing, about 2.7 s at ~29 a second.
do
	local p = price({ ranged(546) })
	check("price: one ranged enemy, one zone (" .. p.heroes .. ")", p.heroes == 1)
	check("price: exposure walks the zone's depth both ways plus wait and swing (" .. p.exposure .. ")", math.abs(p.exposure - 2.7) < 0.01)
	check("price: about 12% of 640 HP refused on cost (" .. p.why .. " " .. p.cost .. ")", p.why == "cost")
end

-- Shallower: 100 inside the zone costs about 1.37 s, ~6% of max HP, and passes at full HP.
do
	local p = price({ ranged(746) })
	check("price: a shallow walk-in passes (" .. p.why .. " " .. p.cost .. ")", p.ok and p.cost < 0.07)
	local low = price({ ranged(746) }, { hp = 340 })
	check("price: the same walk-in at 53% HP falls under the floor (" .. low.why .. ")", low.why == "hp")
end

-- A ready nuke in range is added once; an enemy whose zone does not reach the creep costs nothing.
do
	local p = price({ ranged(746, 60) })
	check("price: a ready nuke tips a shallow walk-in over the cap (" .. p.why .. ")", p.why == "cost")
	local away = price({ ranged(900, 60) })
	check("price: an enemy out of reach is not priced (" .. away.heroes .. " " .. away.cost .. ")", away.ok and away.heroes == 0 and away.cost == 0)
end

-- Two enemies covering the creep, or an enemy tower over it, refuse it whatever the HP.
do
	check("price: two heroes refuse", price({ ranged(800), ranged(820) }).why == "two")
	check("price: the enemy tower refuses", price({}, { tower = true }).why == "tower")
end

-- The zone's depth is capped by the walk itself: a short walk into a deep zone is priced on the walk.
do
	local p = price({ ranged(300) }, { walk = 0.5 })
	check("price: depth capped at the walk's length (" .. p.exposure .. ")", math.abs(p.exposure - (1.0 + 0.3 + 0.4)) < 0.01)
end

-- A running walk-in is priced against COST_CAP x WALK_SLACK: the 12% walk-in refused at a pick is kept once under way, the
-- HP floor still applies.
do
	local t = { ranged(546) }
	local cap = C.COST_CAP * C.WALK_SLACK
	check("price: refused at the pick", not C.PriceOf(t, 2, 0.3, 0.4, 300, 640, 640, false).ok)
	check("price: kept while running", C.PriceOf(t, 2, 0.3, 0.4, 300, 640, 640, false, cap).ok)
	check("price: the floor still releases a running walk-in", C.PriceOf(t, 2, 0.3, 0.4, 300, 380, 640, false, cap).why == "hp")
end

-- Threats are read where the core swings from, its reach short of the creep on its own side: a melee enemy (zone 150 + 48
-- + 150 = 348) 300 behind the creep covers the creep but not a core swinging from 198 on the near side (498 away).
do
	local function d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
	local creep, enemy = Vector(0, 0), Vector(300, 0)
	local stand = C.StandPoint(Vector(-600, 0), creep, 198)
	check("stand: its reach short of the creep, toward the core (" .. stand.x .. ")", math.abs(stand.x + 198) < 0.01 and stand.y == 0)
	local melee = function(dist) return { d = dist, zone = 348, dps = 50 / 1.7, nuke = 0 } end
	check("stand: the enemy covers the creep", price({ melee(d(enemy, creep)) }).heroes == 1)
	check("stand: but not where the core swings, so it costs nothing", price({ melee(d(enemy, stand)) }).heroes == 0)
	check("stand: a core already in reach swings from where it is", C.StandPoint(Vector(-100, 0), creep, 198).x == -100)
end

-- Two walk-ins held at once (a retarget from one to another picks the next before the first reports): each is found and
-- finished on its own creep.
do
	local a, b = {}, {}
	local p = C.PriceOf({}, 1.5, 0, 0.4, 300, 640, 640, false)
	C.Start(7, a, p, 600, 10)
	C.Start(7, b, p, 590, 11)
	check("walks: the first walk-in is still running after a second starts", C.Running(7, a) ~= nil)
	check("walks: finishing the first returns its own HP at the pick", C.Finish(7, a).hp == 600)
	check("walks: the second is untouched", C.Running(7, b) ~= nil and C.Running(7, a) == nil)
end

finish()
