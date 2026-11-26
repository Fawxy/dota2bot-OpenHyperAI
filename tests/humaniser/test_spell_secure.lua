dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice oha-creep-spell-shadow: spell_secure.ts, whether a castable spell could take a lane creep and at what price.

LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
local S = require("bots/FunLib/humaniser/spell_secure")

local function spell(o)
	return {
		name = o.name or "nuke", shape = o.shape or "u", range = o.range or 800, cp = o.cp or 0.4, dmg = o.dmg or 75, dtype = 2,
		mana = o.mana or 90, cd = o.cd or 6, key = o.key == true, radius = o.radius or 0, half = o.half or 0, speed = o.speed or 0,
	}
end

do -- timing: the walk, turn, cast point and flight, by shape
	local t = S.TimingOf(spell({ range = 800, cp = 0.3, speed = 1000 }), 600, 300, 0.1)
	check("in range: no walk; land is turn + cast point + flight over the distance", t.gap == -200 and t.walk == 0 and near(t.land, 0.1 + 0.3 + 0.6), t.land)
	t = S.TimingOf(spell({ range = 600, cp = 0.3, speed = 1000 }), 900, 300, 0.1)
	check("out of range: the walk to range comes first and the flight is from cast range", t.gap == 300 and near(t.walk, 1) and near(t.land, 1 + 0.1 + 0.3 + 0.6), t.land)
	t = S.TimingOf(spell({ shape = "n", range = 400, cp = 0.2, speed = 900 }), 300, 300, 0.5)
	check("no target: neither turn nor flight", t.gap == -100 and near(t.land, 0.2), t.land)
end

do -- a kill needs the creep alive when the damage lands
	check("alive and within the damage: a kill", S.Kills(60, 75) == true)
	check("dead before it lands: no kill, however low", S.Kills(-5, 75) == false and S.Kills(0, 75) == false)
	check("more HP than the damage: no kill", S.Kills(80, 75) == false)
end

do -- the reserve: the dearest other key spell, castable or not
	local impale = spell({ name = "impale", mana = 100, key = true })
	check("the spell itself is not its own reserve; the dearer other key spell is", S.OverReserve(250, impale, { impale = 100, hex = 125 }) == 25)
	check("short of the reserve reads below 0", S.OverReserve(200, impale, { impale = 100, hex = 125 }) == -25)
	check("no other key spell: mana after the cast", S.OverReserve(200, spell({ mana = 90 }), {}) == 110)
end

do -- enemy heroes the cast aimed at the creep also hits
	local hero, creep = { x = 0, y = 0 }, { x = 500, y = 0 }
	local line = spell({ shape = "p", range = 1000, half = 60 })
	local behind = { x = 900, y = 40, hull = 24 }
	local beside = { x = 500, y = 200, hull = 24 }
	local back = { x = -200, y = 0, hull = 24 }
	check("a line catches a foe behind the creep within its width, not one beside it or behind the hero",
		S.AlsoHit(line, hero, creep, { behind, beside, back }) == 1)
	check("a line reaches only to its cast range", S.AlsoHit(spell({ shape = "p", range = 600, half = 60 }), hero, creep, { behind }) == 0)
	local area = spell({ radius = 250 })
	check("an area counts foes around the creep", S.AlsoHit(area, hero, creep, { beside, behind, back }) == 1)
	check("a no-target area counts foes around the hero", S.AlsoHit(spell({ shape = "n", range = 300, radius = 300 }), hero, creep, { back, beside }) == 1)
	check("a single-target spell hits nobody else", S.AlsoHit(spell({}), hero, creep, { { x = 510, y = 0, hull = 24 } }) == 0)
end

do -- the best answer of a read
	local function ans(o)
		return { spell = spell({ name = o.name, mana = o.mana }), timing = { gap = 0, walk = 0, land = 0.5 }, taken = o.taken or 75, hp = o.hp,
			kill = S.Kills(o.hp, o.taken or 75), over = o.over or 10, also = 0 }
	end
	check("a kill beats a closer miss", S.Best({ ans({ name = "a", hp = 76 }), ans({ name = "b", hp = 70 }) }).spell.name == "b")
	check("of two kills, the one that meets the reserve beats a cheaper one that does not",
		S.Best({ ans({ name = "cheap", hp = 50, mana = 60, over = -5 }), ans({ name = "dear", hp = 50, mana = 120, over = 5 }) }).spell.name == "dear")
	check("of two kills that meet it, the cheaper", S.Best({ ans({ name = "dear", hp = 50, mana = 120 }), ans({ name = "cheap", hp = 50, mana = 60 }) }).spell.name == "cheap")
	check("with no kill, a creep alive at landing beats one dead by then", S.Best({ ans({ name = "dead", hp = -10 }), ans({ name = "alive", hp = 200 }) }).spell.name == "alive")
	check("with no kill, the least HP still to lose", S.Best({ ans({ name = "far", hp = 200 }), ans({ name = "close", hp = 90 }) }).spell.name == "close")
	check("nothing to weigh: none", S.Best({}) == nil)
end

finish()
