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
		for n in pairs(Data.SPELL_DAMAGE) do names[#names + 1] = n end
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
	check("log: one ev=burst_add per hero and spell", #lines == 2, #lines)
	check("log: the line names the hero, spell, status, key, value, level and side",
		first:find("ev=burst_add", 1, true) and first:find("pid=24", 1, true) and first:find("ab=" .. unknown, 1, true)
			and first:find("st=unknown", 1, true) and first:find("key=" .. unknownRow[1], 1, true) and first:find("val=55", 1, true)
			and first:find("lvl=3", 1, true) and first:find("own=0", 1, true), first)
	local otherHero = MakeUnit({ pid = 25, team = 3, loc = Vector(0, 0) })
	read(otherHero, both, 300)
	check("log: another hero with the same spell logs again", #lines == 4, #lines)
	Telemetry.SetSink(nil)
end

finish()
