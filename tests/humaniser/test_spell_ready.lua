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

finish()
