dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice oha-spell-aim: spell_aim.ts, where to cast a point or no-target spell so it hits the creep it must and the most enemy
-- heroes; and spell_secure's Aimed, the aim timed on where the units will be when the cast lands.

LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
local A = require("bots/FunLib/humaniser/spell_aim")
local S = require("bots/FunLib/humaniser/spell_secure")

local hero = { x = 0, y = 0 }
local function geom(o)
	return { k = o.k, range = o.range or 0, radius = o.radius or 0, half = o.half or 0, length = o.length or 0, offset = o.offset or 0 }
end
local function body(x, y) return { x = x, y = y, hull = 24 } end

do -- a line turns off the creep to catch a hero beside it, keeping the creep inside
	local line = geom({ k = "l", half = 100, length = 1100 })
	local creep, foe = { x = 500, y = 0 }, body(500, 150)
	local straight = A.AimAt(line, hero, creep, {}, { foe })
	check("straight at the creep the line misses the hero 150 to the side", straight.others == 0 and straight.off == 0)
	local aim = A.AimAt(line, hero, creep, { foe }, {})
	check("aimed, it hits the hero too and the creep stays within the half width", aim.also == 1 and aim.off <= 100 and aim.gap == 0, aim.off)
	local far = A.AimAt(line, hero, creep, { body(500, 400) }, {})
	check("a hero no facing reaches leaves the line straight at the creep", far.also == 0 and far.off < 1e-6, far.off)
	local wide = A.AimAt(line, hero, { x = 1400, y = 0 }, {}, {})
	check("past the line's length the hero walks the difference first", near(wide.gap, 300) and near(wide.from.x, 300), wide.gap)
end

do -- an area's centre moves towards a hero, pulled back within cast range
	local area = geom({ k = "a", range = 700, radius = 250 })
	local creep, foe = { x = 600, y = 0 }, body(900, 0)
	local aim = A.AimAt(area, hero, creep, { foe }, {})
	check("the centre sits between creep and hero, no farther than cast range, and hits both",
		aim.also == 1 and aim.at.x > 600 and aim.at.x <= 700 + 1e-6 and aim.off <= 250, aim.at.x)
	check("straight at the creep the same area misses that hero", A.AimAt(area, hero, creep, {}, { foe }).others == 0)
	local out = A.AimAt(area, hero, { x = 1100, y = 0 }, {}, {})
	check("an area reaches cast range plus its radius: a creep 1,100 away needs 150 of walk", near(out.gap, 150), out.gap)
	local wave = { body(620, 60), body(640, -80), body(1200, 0) }
	check("their other creeps are counted, not aimed for", A.AimAt(area, hero, creep, {}, wave).others == 2)
end

do -- a raze's circle sits in front of the hero: it turns to the creep, or walks so the creep is at the circle's distance
	local raze = geom({ k = "r", radius = 250, offset = 450 })
	local creep, foe = { x = 450, y = 0 }, body(450, 300)
	check("straight at the creep it misses a hero 300 to the side", A.AimAt(raze, hero, creep, {}, { foe }).others == 0)
	local aim = A.AimAt(raze, hero, creep, { foe }, {})
	check("turned towards the hero the circle takes both", aim.also == 1 and aim.off <= 250 and aim.gap == 0, aim.off)
	local farther = A.AimAt(raze, hero, { x = 1000, y = 0 }, {}, {})
	check("a creep beyond the circle's far edge: walk towards it until it is inside", near(farther.gap, 300) and near(farther.from.x, 300), farther.from.x)
	local inside = A.AimAt(geom({ k = "r", radius = 250, offset = 700 }), hero, { x = 100, y = 0 }, {}, {})
	check("a creep inside the near edge of the far raze: walk away from it", near(inside.gap, 350) and near(inside.from.x, -350), inside.from.x)
end

do -- a circle around the hero has no aim, only the walk to bring the creep inside
	local s = A.AimAt(geom({ k = "s", radius = 400 }), hero, { x = 550, y = 0 }, { body(-200, 0), body(-300, 0) }, {})
	check("the hero walks 150, and from there the foe 350 behind is inside and the one 450 behind is not", near(s.gap, 150) and s.also == 1, s.also)
end

do -- Aimed: the cast is timed on its delay, and aimed where a walking creep will be when it lands
	local torrent = { name = "torrent", shape = "p", geom = "a", range = 1300, cp = 0.4, dmg = 120, dtype = 2, mana = 90, cd = 10, key = true,
		radius = 250, half = 0, speed = 0, length = 0, delay = 1.6, offset = 0 }
	local creep = { x = 500, y = 0, hull = 16, vx = 300, vy = 0 }
	local r = S.Aimed(torrent, hero, 300, 0.1, creep, {}, {})
	check("it lands after the turn, the cast point and the delay", near(r.timing.land, 0.1 + 0.4 + 1.6), r.timing.land)
	check("its centre is where the creep will be then, 630 on", near(r.aim.at.x, 500 + 300 * 2.1) and r.aim.off < 1e-6, r.aim.at.x)
	local still = S.Aimed(torrent, hero, 300, 0.1, { x = 800, y = 0, hull = 16, vx = 0, vy = 0 }, { { x = 800, y = 400, hull = 24, vx = 0, vy = 0 } }, {})
	check("a hero the centre would miss is caught by the aim, and `centre` says it would not have been", still.aim.also == 1 and still.centre == 0)
end

finish()
