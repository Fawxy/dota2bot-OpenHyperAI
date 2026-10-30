-- Slice 5a: the laner's choice among the engine's laneTargets facts (moved from the engine's nextLastHit).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

local function target(kind, eta, ranged) return { creep = {}, kind = kind, eta = eta, walk = 0, ranged = ranged == true } end

-- The ranged creep wins over a melee creep due a little sooner (gold and XP).
do
	local m, r = target("lasthit", 0.2), target("lasthit", 0.4, true)
	check("pick: ranged preferred over a melee due 0.2 s sooner", Pick.Choose({ m, r }) == r)
end

-- ...but not over a melee creep due now when the ranged one is a second away: the bias is bounded.
do
	local m, r = target("lasthit", 0), target("lasthit", 1.0, true)
	check("pick: melee due now beats a ranged creep due in 1 s", Pick.Choose({ r, m }) == m)
end

-- A core never gives up its own last hit to deny: an allied creep due now loses to an enemy creep due in 0.2 s,
-- but a deny due now beats a last hit a second away.
do
	local d, e = target("deny", 0), target("lasthit", 0.2)
	check("pick: last hit beats a deny due slightly sooner", Pick.Choose({ d, e }) == e)
	local late = target("lasthit", 1.0)
	check("pick: deny due now beats a last hit 1 s away", Pick.Choose({ late, d }) == d)
end


finish()
