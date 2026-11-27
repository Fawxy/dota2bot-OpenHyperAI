dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice oha-creep-spell-shadow: spell_secure.ts, whether a castable spell could take a lane creep and at what price.

LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
local S = require("bots/FunLib/humaniser/spell_secure")

local function spell(o)
	return {
		name = o.name or "nuke", shape = o.shape or "u", range = o.range or 800, cp = o.cp or 0.4, dmg = o.dmg or 75, dtype = 2,
		mana = o.mana or 90, cd = o.cd or 6, key = o.key == true, radius = o.radius or 0, half = o.half or 0, speed = o.speed or 0,
		length = 0, delay = 0, offset = 0,
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

do -- the cast the creep row may order (slice oha-creep-spells)
	local function ans(o)
		return { spell = spell({ name = o.name, mana = o.mana, key = o.key, shape = o.shape }), timing = { gap = o.gap or -100, walk = 0, land = 0.5 }, taken = 75,
			hp = o.hp or 50, kill = S.Kills(o.hp or 50, 75), over = o.over or 10, also = o.also or 0 }
	end
	local function pick(as) local r = S.CastPick(as) return r.pick and r.pick.spell.name, r.why end
	check("a damage spell that kills in range with the reserve kept is cast", pick({ ans({ name = "beam" }) }) == "beam")
	check("a damage spell before a key spell, whatever the price", pick({ ans({ name = "stun", key = true, also = 1, mana = 50 }), ans({ name = "beam", mana = 120 }) }) == "beam")
	check("of two damage spells, the cheaper", pick({ ans({ name = "dear", mana = 120 }), ans({ name = "cheap", mana = 60 }) }) == "cheap")
	check("a key spell that also hits an enemy hero is cast", pick({ ans({ name = "spike", key = true, also = 1 }) }) == "spike")
	local _, why = pick({ ans({ name = "spike", key = true, also = 0 }) })
	check("a key spell hitting no enemy hero is not: key", why == "key")
	_, why = pick({ ans({ name = "torrent", shape = "p" }) })
	check("a spell cast on a place is not this group's: shape", why == "shape")
	_, why = pick({ ans({ hp = 90 }) })
	check("no kill: nokill", why == "nokill")
	_, why = pick({ ans({ gap = 20 }) })
	check("out of cast range by 20: walk", why == "walk")
	_, why = pick({ ans({ over = -1 }) })
	check("the reserve not kept: reserve", why == "reserve")
	_, why = pick({ ans({ name = "a", hp = 90 }), ans({ name = "b", over = -1 }), ans({ name = "c", shape = "p" }) })
	check("the reason is the furthest any answer got", why == "reserve")
	check("nothing to weigh: no pick and no reason", S.CastPick({}).pick == nil and S.CastPick({}).why == nil)
end

do -- slice oha-aimed-cast: a point or no-target answer through the same gates, aimed
	local function ans(o)
		local s = spell({ name = o.name, mana = o.mana, key = o.key, shape = o.shape or "n" })
		s.geom = o.geom
		local aim
		if not o.noaim then aim = { gap = 0, from = { x = 0, y = 0 }, at = { x = 450, y = 0 }, off = 0, also = o.also or 0, others = 0, slack = o.slack, th = 0 } end
		return { spell = s, timing = { gap = o.gap or 0, walk = 0, land = 0.6 }, taken = 75, hp = o.hp or 50, kill = S.Kills(o.hp or 50, 75), over = o.over or 10,
			also = o.also or 0, aim = aim }
	end
	local on = { aimed = true, slack = 0.1 }
	local function pick(as, o) local r = S.CastPick(as, o) return r.pick and r.pick.spell.name, r.why end
	check("a raze that kills from the spot with slack to turn to is cast", pick({ ans({ name = "raze", geom = "r", slack = 0.3 }) }, on) == "raze")
	local _, why = pick({ ans({ name = "raze", geom = "r", slack = 0.3 }) }, { aimed = false, slack = 0.1 })
	check("the same raze with the switch off: aimoff, the furthest reason", why == "aimoff")
	_, why = pick({ ans({ name = "raze", geom = "r", slack = 0.05 }), ans({ name = "nuke", shape = "u", hp = 90 }) }, on)
	check("a raze whose aim has less slack than the bar: aim", why == "aim")
	check("a spell around the hero needs no slack", pick({ ans({ name = "pulse", geom = "s" }) }, on) == "pulse")
	check("a point spell needs no slack (the game turns the hero to its point)", pick({ ans({ name = "lsa", shape = "p", geom = "a" }) }, on) == "lsa")
	_, why = pick({ ans({ name = "lsa", shape = "p", geom = "a", noaim = true }) }, on)
	check("a point answer with no aim is still shape", why == "shape")
	_, why = pick({ ans({ name = "fissure", shape = "p", geom = "l", key = true, also = 0 }) }, on)
	check("an aimed disable hitting no enemy hero: key, as the unit-target one", why == "key")
	check("a unit-target damage spell before an aimed one, even when dearer", pick({ ans({ name = "pulse", geom = "s", mana = 50 }), ans({ name = "nuke", shape = "u", mana = 120 }) }, on) == "nuke")
	check("an aimed damage spell before a unit-target disable", pick({ ans({ name = "pulse", geom = "s", mana = 120 }), ans({ name = "stun", shape = "u", key = true, also = 1, mana = 50 }) }, on) == "pulse")
	check("Turns: a no-target ring or line, not a point spell or a circle around the hero", S.Turns(ans({ geom = "r" }).spell) and S.Turns(ans({ geom = "l" }).spell)
		and not S.Turns(ans({ geom = "s" }).spell) and not S.Turns(ans({ shape = "p", geom = "l" }).spell))
	check("FacingOf: the aim's facing, none without an aim", near(S.FacingOf(ans({ geom = "r" })), 0) and S.FacingOf(ans({ noaim = true })) == nil)
end

finish()
