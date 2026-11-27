dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice cast-read: SpellReady.ReadyList (ev=snap rdy) and ClassByName (ev=cast cl): which spells a hero can cast now, and
-- each one's class (u ultimate, k hard disable from ability_classes, d damage, o other).

local function spell(name, o)
	o = o or {}
	return {
		IsNull = function() return false end,
		GetName = function() return name end,
		GetLevel = function() return o.level or 1 end,
		IsHidden = function() return o.hidden == true end,
		IsPassive = function() return o.passive == true end,
		IsUltimate = function() return o.ult == true end,
		IsFullyCastable = function() return o.castable ~= false end,
		GetAbilityDamage = function() return o.dmg or 0 end,
		GetSpecialValueFloat = function() return 0 end,
	}
end

LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
local SpellReady = require("bots/FunLib/humaniser/spell_ready")
local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, 0) })
bot.abilities = {
	[0] = spell("bane_enfeeble"),
	[1] = spell("bane_brain_sap", { dmg = 75 }),
	[2] = spell("bane_nightmare"),
	[3] = spell("bane_fiends_grip", { ult = true }),
	[4] = spell("some_passive", { passive = true }),
	[5] = spell("some_cooling", { castable = false }),
}
check("ready: castable spells with classes, passive and cooling left out",
	SpellReady.ReadyList(bot) == "bane_enfeeble:o;bane_brain_sap:d;bane_nightmare:k;bane_fiends_grip:u", SpellReady.ReadyList(bot))
bot.abilities[1] = spell("bane_brain_sap", { level = 0, dmg = 75 })
bot.abilities[2] = spell("bane_nightmare", { hidden = true })
check("ready: unlearned and hidden left out", SpellReady.ReadyList(bot) == "bane_enfeeble:o;bane_fiends_grip:u", SpellReady.ReadyList(bot))
bot.abilities = {}
check("ready: nothing castable reads absent", SpellReady.ReadyList(bot) == nil)
bot.abilities = { [0] = spell("bane_nightmare"), [1] = spell("zuus_lightning_bolt") }
check("class: a hard disable by name", SpellReady.ClassByName(bot, "bane_nightmare") == "k")
check("class: a SPELL_DAMAGE row is damage", SpellReady.ClassByName(bot, "zuus_lightning_bolt") == "d")
check("class: an item or an unknown name has none", SpellReady.ClassByName(bot, "item_tango") == nil and SpellReady.ClassByName(bot, "nope") == nil)

-- Slice oha-burst-left-out: DamageOn adds the castable spells Valve's estimate leaves out (SPELL_ADDED). Names come from the
-- generated tables, the first of each kind by name, so a patch's regeneration does not break the cases.
do
	local Data = require("bots/FunLib/humaniser/spell_damage_data")
	local Telemetry = require("bots/FunLib/humaniser/telemetry")
	local ours = package.loaded["bots/FunLib/custom_loader"].Ours
	local function firstAdded(want)
		local names = {}
		for n, r in pairs(Data.SPELL_ADDED) do if want(r) then names[#names + 1] = n end end
		table.sort(names)
		return names[1], Data.SPELL_ADDED[names[1]]
	end
	local leftOut, leftRow = firstAdded(function(r) return r[4] == "left_out" and not r[2] end)
	local unknown, unknownRow = firstAdded(function(r) return r[4] == "unknown" end)
	local perSec, perSecRow = firstAdded(function(r) return r[2] end)
	local counted
	do
		local names = {}
		for n, r in pairs(Data.SPELL_DAMAGE) do if not r[2] then names[#names + 1] = n end end
		table.sort(names)
		counted = names[1]
	end
	check("added: the cases found a row of each kind", leftOut and unknown and perSec and counted and Data.SPELL_ADDED[counted] == nil)

	local function added(name, o)
		o = o or {}
		local a = spell(name, o)
		a.GetSpecialValueFloat = function() return o.value or 100 end
		return a
	end
	local lines = {}
	Telemetry.SetSink(function(line) table.insert(lines, line) end)
	ours.BurstReady = true
	local target = MakeUnit({ pid = 20, team = 3, loc = Vector(0, 0) })
	target.GetActualIncomingDamage = function(_, d) return d * 0.75 end
	local function read(caster, abilities, est)
		T = T + 0.1
		caster.abilities, caster.estDamage = abilities, est
		return SpellReady.DamageOn(caster, target, 3)
	end
	local enemy = MakeUnit({ pid = 21, team = 3, loc = Vector(0, 0) })
	check("added: a castable left-out spell adds its value through the target's resistance",
		near(read(enemy, { [0] = added(leftOut) }, 300), 300 + 100 * 0.75))
	check("added: the same spell on cooldown adds nothing", near(read(enemy, { [0] = added(leftOut, { castable = false }) }, 300), 300))
	check("added: an unlearned spell adds nothing", near(read(enemy, { [0] = added(leftOut, { level = 0 }) }, 300), 300))
	check("added: a value of 0 adds nothing", near(read(enemy, { [0] = added(leftOut, { value = 0 }) }, 300), 300))
	check("added: a counted spell is not added", near(read(enemy, { [0] = added(counted) }, 300), 300))
	check("added: a per-second row is multiplied by the window", near(read(enemy, { [0] = added(perSec, { value = 20 }) }, 300), 300 + 20 * 3 * 0.75))
	check("added: two spells sum", near(read(enemy, { [0] = added(leftOut), [1] = added(unknown, { value = 40 }) }, 300), 300 + 75 + 30))
	check("added: with an estimate of 0 the added term is the read", near(read(enemy, { [0] = added(leftOut) }, 0), 75))
	check("added: with an estimate of 0 and nothing castable the read stays 0", read(enemy, { [0] = added(leftOut, { castable = false }) }, 0) == 0)
	local both2 = MakeUnit({ pid = 26, team = 3, loc = Vector(0, 0) })
	local est, spentValue = 300, 150
	local attackPart = target:GetActualIncomingDamage(both2:GetAttackDamage() * 3 / both2:GetSecondsPerAttack())
	local want = math.max(math.min(est, attackPart), est - spentValue * 0.75) + 100 * 0.75
	local got = read(both2, { [0] = added(counted, { castable = false, value = spentValue }), [1] = added(leftOut) }, est)
	check("added: with a cooling counted spell the term still comes on top of the spent subtraction", near(got, want), tostring(want) .. " got " .. tostring(got))
	local ally = MakeUnit({ pid = 22, team = 2, loc = Vector(0, 0) })
	check("added: a hero of our own team gets the term", near(read(ally, { [0] = added(leftOut) }, 300), 375))
	local illusion = MakeUnit({ pid = 23, team = 3, loc = Vector(0, 0) })
	illusion.IsIllusion = function() return true end
	check("added: an illusion gets none", near(read(illusion, { [0] = added(leftOut) }, 300), 300))
	ours.BurstReady = false
	check("added: BurstReady off, Valve's figure", read(enemy, { [0] = added(leftOut) }, 300) == 300 and read(enemy, { [0] = added(leftOut) }, 0) == 0)
	ours.BurstReady = true

	lines = {}
	local mine = MakeUnit({ pid = 24, team = 3, loc = Vector(0, 0) })
	local both = { [0] = added(unknown, { value = 55, level = 3 }), [1] = added(leftOut) }
	read(mine, both, 300)
	read(mine, both, 300)
	read(mine, both, 300)
	local first = lines[1] or ""
	check("log: one ev=burst_add per hero, spell and level", #lines == 2, #lines)
	check("log: the line names the hero, spell, status, key, value, level and side",
		first:find("ev=burst_add", 1, true) and first:find("pid=24", 1, true) and first:find("ab=" .. unknown, 1, true)
			and first:find("st=unknown", 1, true) and first:find("key=" .. unknownRow[1], 1, true) and first:find("val=55", 1, true)
			and first:find("lvl=3", 1, true) and first:find("own=0", 1, true), first)
	local otherHero = MakeUnit({ pid = 25, team = 3, loc = Vector(0, 0) })
	read(otherHero, both, 300)
	check("log: another hero with the same spell logs again", #lines == 4, #lines)
	read(mine, { [0] = added(unknown, { value = 70, level = 4 }) }, 300)
	check("log: a new level of the same spell logs again, with its value", #lines == 5 and lines[5]:find("lvl=4", 1, true) and lines[5]:find("val=70", 1, true), lines[5])
	Telemetry.SetSink(nil)
end

-- Slice oha-creep-spell-shadow: CreepSpellsOf, the spells that could take a lane creep in one cast, with the facts of each.
do
	local function cast(name, o)
		local a = spell(name, o)
		local sv = o.special or {}
		a.GetBehavior = function() return o.bits or 8 end
		a.GetCastRange = function() return o.range or 700 end
		a.GetCastPoint = function() return o.cp or 0.3 end
		a.GetManaCost = function() return o.mana or 100 end
		a.GetCooldown = function() return o.cd or 8 end
		a.GetTargetType = o.ttype and function() return o.ttype end or nil
		a.GetTargetTeam = o.tteam and function() return o.tteam end or nil
		a.GetSpecialValueFloat = function(_, k) return sv[k] or 0 end
		return a
	end
	T = (T or 0) + 1
	local caster = MakeUnit({ pid = 3, team = 2, loc = Vector(0, 0) })
	caster.abilities = {
		[0] = cast("bolt", { dmg = 90, bits = 24, special = { speed = 1600, width = 120 } }), -- unit and point bits: cast on the unit
		[1] = cast("lion_voodoo", { castable = false, mana = 125 }), -- a key spell on cooldown: no cast, but the reserve
		[2] = cast("wave", { dmg = 80, bits = 16, special = { start_radius = 150, end_radius = 250, speed = 1050 } }),
		[3] = cast("big", { dmg = 300, ult = true }),
		[4] = cast("drain", { dmg = 50, bits = 8 + 128 }),
		[5] = cast("heroes_only", { dmg = 100, ttype = 1 }),
	}
	local got = SpellReady.CreepSpellsOf(caster)
	local by = {}
	for _, s in ipairs(got.spells) do by[s.name] = s end
	check("creep spells: the ultimate, the channelled one and a hero-only unit target are left out",
		#got.spells == 2 and by.bolt and by.wave and not by.big and not by.drain and not by.heroes_only, #got.spells)
	check("unit-target and point bits read as cast on the unit; a point-only spell as `p`", by.bolt.shape == "u" and by.wave.shape == "p")
	check("a line's half width and speed from its keys", by.bolt.half == 60 and by.bolt.speed == 1600 and by.bolt.radius == 0)
	check("a cone reads as a line as wide as its far end", by.wave.half == 250 and by.wave.speed == 1050)
	check("a key spell on cooldown still sets the reserve", got.keys.lion_voodoo == 125 and by.bolt.key == false)

	T = T + 1
	caster.abilities = {
		[0] = cast("ally_shield", { dmg = 50, ttype = 3, tteam = 1 }), -- an ally's buff that damages around its target (Frost Shield)
		[1] = cast("both_teams", { dmg = 60, ttype = 3, tteam = 3 }),
		[2] = cast("enemy_nuke", { dmg = 70, ttype = 3, tteam = 2 }),
	}
	local teams = SpellReady.CreepSpellsOf(caster)
	local tn = {}
	for _, s in ipairs(teams.spells) do tn[s.name] = true end
	check("a unit target only an ally may take is left out; one for either team or the enemy is kept",
		#teams.spells == 2 and tn.both_teams and tn.enemy_nuke and not tn.ally_shield, #teams.spells)

	T = T + 1
	caster.abilities = {
		-- A no-target spell has cast range 0 (ReadySpells then reads its radius as its reach).
		[0] = cast("pulse", { dmg = 100, bits = 4, range = 0, special = { radius = 475 } }),
		[1] = cast("stomp_no_radius", { dmg = 100, bits = 4, range = 0 }),
	}
	local n = SpellReady.CreepSpellsOf(caster)
	check("a no-target spell hits within its radius; one with no radius is left out",
		#n.spells == 1 and n.spells[1].name == "pulse" and n.spells[1].shape == "n" and n.spells[1].range == 475, #n.spells)
	-- A per-second row (SPELL_DAMAGE) is damage over time: no one-cast kill.
	local Data = require("bots/FunLib/humaniser/spell_damage_data")
	local perSec
	for name, r in pairs(Data.SPELL_DAMAGE) do if r[2] then perSec = name break end end
	T = T + 1
	caster.abilities = { [0] = cast(perSec, { bits = 8, special = { [Data.SPELL_DAMAGE[perSec][1]] = 40 } }) }
	check("a per-second spell is left out", #SpellReady.CreepSpellsOf(caster).spells == 0, perSec)

	-- A spell Valve's estimate leaves out reads 0 from GetAbilityDamage: its damage is the SPELL_ADDED key's (the smoke game saw no Meat Hook).
	local leftName
	for name, r in pairs(Data.SPELL_ADDED) do
		if r[4] == "left_out" and not r[2] and Data.SPELL_DAMAGE[name] == nil then leftName = name break end
	end
	T = T + 1
	caster.abilities = { [0] = cast(leftName, { dmg = 0, bits = 16, special = { [Data.SPELL_ADDED[leftName][1]] = 80 } }) }
	local left = SpellReady.CreepSpellsOf(caster)
	check("a left-out spell takes its SPELL_ADDED damage in the creep read", #left.spells == 1 and left.spells[1].dmg == 80, leftName)
	check("the chase's list stays as built: no damage, no entry", #SpellReady.ReadySpells(caster) == 0)
end

finish()
