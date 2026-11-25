dofile(HARNESS_DIR .. "/lane_world.lua")
-- The offer's three answers (offer.ts): pure functions, so plain tables in and answers out.
LaneFresh({ Enable = true }, { skill = 1 })
local O = require("bots/FunLib/humaniser/offer")

do -- Arrive: the boundary is strict, and a late creep reads its negative slack
	local on = O.Arrive(1.0, 0.45, 1.5)
	check("arrive: one tick of slack is on time", on.ok == true and near(on.slack, 0.05), on.slack)
	local edge = O.Arrive(1.0, 0.45, 1.45)
	check("arrive: no slack at all is not on time", edge.ok == false and near(edge.slack, 0), edge.slack)
	local late = O.Arrive(2.0, 0.45, 1.0)
	check("arrive: late reads the shortfall", late.ok == false and near(late.slack, -1.45), late.slack)
end

do -- GivenUp counts only the targets that come due inside the away time
	local others = { { due = 0.2, ranged = true }, { due = 1.5, ranged = false }, { due = 2.0, ranged = true }, { due = 3.5, ranged = true } }
	local g = O.GivenUp(others, 2.0)
	check("given up: those due before the hero is back, and the ranged among them", g.due == 2 and g.ranged == 1, g.due .. " " .. g.ranged)
	check("given up: one due exactly as the hero returns is not given up", O.GivenUp({ { due = 2.0, ranged = false } }, 2.0).due == 0)
end

do -- the stand spot: attack range from the creep on the hero's line, or the hero's own place
	local s = O.StandSpot({ x = 1000, y = 0 }, { x = 0, y = 0 }, 600)
	check("stand spot: at reach from the creep on the line to the hero", near(s.x, 600) and near(s.y, 0), s.x)
	local own = O.StandSpot({ x = 400, y = 300 }, { x = 0, y = 0 }, 600)
	check("stand spot: a hero already in range stands where it is", near(own.x, 400) and near(own.y, 300))
end

local function enemy(pid, x, y)
	return { pid = pid, x = x, y = y, range = 500, hull = 24, dmg = 60, spa = 1.5 }
end
local function path(from, spot, enemies, extra)
	local p = { from = from, spot = spot, speed = 300, hull = 24, creeps = {}, towers = {}, enemies = enemies }
	for k, v in pairs(extra or {}) do p[k] = v end
	return O.PathCost(p)
end

do -- exposure: the seconds of the straight walk inside the enemy's range plus both hulls (r = 548), the enemy standing still
	local e = { enemy(7, 0, 0) }
	local outside = path({ x = -2000, y = 0 }, { x = -1500, y = 0 }, e)
	check("path: a walk wholly outside the range has no exposure", outside.covering == 0 and outside.exposure == 0 and near(outside.enemies[1].exp, 0))
	local across = path({ x = -1000, y = 0 }, { x = 1000, y = 0 }, e)
	check("path: a walk across the range is exposed for the chord, but the spot is not covered", across.covering == 0
		and near(across.enemies[1].exp, 1096 / 300) and near(across.enemies[1].dist, 1000), across.enemies[1].exp)
	local into = path({ x = -1000, y = 0 }, { x = 0, y = 0 }, e)
	check("path: a walk ending inside is exposed from the edge on", into.covering == 1 and near(into.exposure, 548 / 300), into.exposure)
	local there = path({ x = 100, y = 0 }, { x = 100, y = 0 }, e)
	check("path: a hero already standing inside is covered with no walk to be exposed on", there.covering == 1 and there.exposure == 0)
	local two = path({ x = -1000, y = 0 }, { x = 0, y = 0 }, { enemy(7, 0, 0), enemy(8, -400, 0) })
	check("path: two cover the spot and the longest exposure is the answer", two.covering == 2 and near(two.exposure, 948 / 300), two.exposure)
end

do -- their creeps and the tower count only at the stand spot
	local spot = { x = 0, y = 0 }
	local a = path({ x = -500, y = 0 }, spot, {}, {
		creeps = { { x = 300, y = 0, reach = 574, dps = 20 }, { x = 800, y = 0, reach = 574, dps = 30 } },
		towers = { { x = 800, y = 0, reach = 868 } },
	})
	check("path: only the creeps whose acquisition reach holds the spot, with their damage", a.creeps == 1 and near(a.cdps, 20), a.creeps)
	check("path: the tower reaches the spot", a.tower == true)
	local b = path({ x = -500, y = 0 }, spot, {}, { towers = { { x = 1000, y = 0, reach = 868 } } })
	check("path: a tower out of reach of the spot is not counted", b.tower == false)
end

finish()
