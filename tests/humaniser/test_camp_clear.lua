dofile(HARNESS_DIR .. "/lane_world.lua")
-- CampClear.CanClear (camp_clear.ts): whether a core keeps 40% of its HP clearing a camp from full, the stack job's pos5
-- double gate. Moved from the deleted core camp trip with its answers unchanged.
local LARGE = Vector(1500, -6500)

local function world()
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = false } })
	T = 300
	CURRENT_TEAM = 2
	SPAWNERS = { { team = 2, type = "large", location = Vector(LARGE.x, LARGE.y, 0), min = Vector(LARGE.x - 150, LARGE.y - 150, 0),
		max = Vector(LARGE.x + 150, LARGE.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	local CC = require("bots/FunLib/humaniser/camp_clear")
	CC.ResetCache()
	-- 40 damage a second, 600 HP, no regen.
	local core = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000) })
	core.dmg, core.spa, core.maxhp, core.hp, core.regen = 60, 1.5, 600, 600, 0
	return CC, core
end

local function neutral(dx)
	local n = MakeNeutral({ x = LARGE.x + dx, y = LARGE.y, hp = 1200, maxhp = 1200 })
	n.dmg = 5
	return n
end

-- A camp never seen is priced by its type's table: a large camp's 0.35 at level 6 grows 1/0.8 a level below it, so a level 3
-- core (0.68) would not keep 40%, a level 4 one (0.55) would, and not with one stack more (x 1.8).
do
	local CC, core = world()
	core.level = 3
	check("table: a level 3 core cannot clear an unseen large camp", CC.CanClear(core, 1, 0) == false)
	core.level = 4
	check("table: a level 4 core can, from full HP", CC.CanClear(core, 1, 0) == true)
	check("table: not with one stack on it", CC.CanClear(core, 1, 1) == false)
end

-- A live camp is priced by the model: each 1,200-HP neutral takes 30.6 s (30 of hits and a 0.6 s switch) at 5 damage a
-- second, one at a time. One costs 153 of 600 HP; two cost 153 + 306.
do
	local CC, core = world()
	core.level = 3
	neutral(0)
	check("live: one neutral the level 3 core clears though its table refuses the camp", CC.CanClear(core, 1, 0) == true)
	neutral(50)
	check("live: two cost 0.77 of its HP: refused", CC.CanClear(core, 1, 0) == false)
end

-- Fewer neutrals than the camp's untouched make-up, all at full HP, is a half-seen camp: priced as last seen, not as the one
-- in sight. Seen whole in fog, it is the last sighting scaled by the stacks.
do
	local CC, core = world()
	neutral(0)
	local far = neutral(50)
	CC.CanClear(core, 1, 0)
	far.loc = Vector(99999, 99999)
	check("half seen: one of the two in sight is priced as both", CC.CanClear(core, 1, 0) == false)
	CC.ResetCache()
	check("control: with no sighting of the second, the one in sight is the camp", CC.CanClear(core, 1, 0) == true)
end

-- A camp seen once and now in fog is its last sighting times 1 + 0.8 a stack: one neutral (0.255 of HP) clears with no
-- stack (where the level 3 table refuses) and not with two (0.66).
do
	local CC, core = world()
	core.level = 3
	local n = neutral(0)
	CC.CanClear(core, 1, 0)
	n.loc = Vector(99999, 99999)
	check("seen in fog: priced as last seen, not by the table", CC.CanClear(core, 1, 0) == true)
	check("seen in fog: two stacks on it refuse", CC.CanClear(core, 1, 2) == false)
end

finish()
