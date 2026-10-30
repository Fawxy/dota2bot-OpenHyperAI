-- Slice 5a: the laner's choice among the engine's laneTargets facts (moved from the engine's nextLastHit).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

local function target(kind, eta, ranged, walk, dies)
	return { creep = {}, kind = kind, eta = eta, due = eta, walk = walk or 0, dies = dies or math.huge, ranged = ranged == true }
end

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


-- The ranged bias outweighs the last-hit bias: a ranged deny beats a melee last hit due 0.05 s sooner (with the
-- two biases swapped the last hit would win).
do
	local rd, ml = target("deny", 0.25, true), target("lasthit", 0.2)
	check("pick: ranged deny beats a melee last hit due 0.05 s sooner", Pick.Choose({ ml, rd }) == rd)
end

-- Slice 5 (probe s5p3): a creep due now but 1.2 s of walking away, which the others kill in 0.9 s, is skipped even
-- though the pick would otherwise take it; one the bot can reach and swing at before it dies is kept.
do
	local far = target("lasthit", 0, true, 1.2, 0.9)
	local near = target("lasthit", 0.6, false, 0, 2)
	check("pick: a creep dead before the bot can reach it is skipped", Pick.Choose({ far, near }) == near)
	check("pick: nothing reachable, nothing picked", Pick.Choose({ far }) == nil)
	local reach = target("lasthit", 0.5, true, 0.5, 1.5)
	check("pick: a creep reachable with time to swing is kept", Pick.Choose({ reach, near }) == reach)
	-- In range already (walk 0): never skipped on this rule, even when it dies soon (lastHit judges the swing).
	local here = target("lasthit", 0, false, 0, 0.2)
	check("pick: a creep in range is kept however soon it dies", Pick.Choose({ here }) == here)
end

-- Missed-bar telemetry (s5b): the snapshot's lf field counts the offers the reach rule skipped, from the same rule Choose uses.
do
	local far = target("lasthit", 0, true, 1.2, 0.9)
	local near = target("lasthit", 0.6, false, 0, 2)
	check("lf: nothing before any scan", Pick.Describe(7, 10) == nil)
	Pick.NoteScan(7, 9.5, 340.6)
	Pick.NotePick(7, 8, { far, near }, Pick.Choose({ far, near }))
	Pick.NotePhase(7, "hold")
	check("lf: phase, ages, distance and offers", Pick.Describe(7, 10) == "ph=hold sc=0.5 aw=340 pk=2.0 n=2 sk=1 ch=1")
	Pick.NotePick(7, 10, { far }, Pick.Choose({ far }))
	check("lf: all offers skipped, none chosen", Pick.Describe(7, 10) == "ph=hold sc=0.5 aw=340 pk=0.0 n=1 sk=1 ch=0")
end

finish()
