dofile(HARNESS_DIR .. "/lane_world.lua")

local function fresh(laneFight, humaniser)
	ResetWorld()
	local h = humaniser or { Enable = true }
	h.LaneFight = laneFight
	FreshHumaniser(h)
	return require("bots/FunLib/humaniser/lane_fight_config")
end

do
	local C = fresh({ Curves = { Notice = { 0, 1 } } })
	local s = C.Settings()
	check("override applies", s.Curves.Notice[1] == 0 and s.Curves.Notice[2] == 1)
	check("missing curves keep defaults", s.Curves.ForgetWindow[1] == 20 and s.Curves.ForgetWindow[2] == 90)
	check("missing scalars keep defaults", s.PollInterval == 0.1 and s.StartHP == 0.5)
	check("curve interpolates low to high", near(C.Curve("ForgetWindow", 0.5), 55) and near(C.Curve("ForgetWindow", 0), 20))
	check("curve clamps skill", near(C.Curve("ForgetWindow", 2), 90))
	check("an array override replaces rather than merges", #C.Settings().Curves.Notice == 2)
end

do
	check("active by default", fresh({}).IsActive())
	check("inactive when humaniser off", not fresh({}, { Enable = false }).IsActive())
	check("inactive when LaneFight off", not fresh({ Enable = false }).IsActive())
	check("inactive when Memory, Trade and Kill all off",
		not fresh({ Memory = false, Trade = false, Kill = false }).IsActive())
	check("one of the three keeps it active", fresh({ Memory = false, Trade = false, Kill = true }).IsActive())
	local C = fresh({ Trade = false })
	check("IsOn reads the flag", not C.IsOn("Trade") and C.IsOn("Kill"))
	check("CallKills on by default", fresh({}).IsOn("CallKills"))
	check("CallKills respects its flag", not fresh({ CallKills = false }).IsOn("CallKills"))
	check("IsOn is false with the humaniser off", not fresh({}, { Enable = false }).IsOn("Kill"))
end

do
	local function world(teams)
		local C = fresh({ Teams = teams })
		local human = MakeUnit({ pid = 0, team = 2, bot = false })
		local ally = MakeUnit({ pid = 1, team = 2 })
		local enemy = MakeUnit({ pid = 6, team = 3 })
		return C, ally, enemy
	end
	local C, ally, enemy = world("enemies")
	check("enemies excludes allies of a human", not C.AppliesTo(ally))
	check("enemies includes the other team", C.AppliesTo(enemy))
	C, ally, enemy = world("allies")
	check("allies includes allies of a human", C.AppliesTo(ally))
	check("allies excludes the other team", not C.AppliesTo(enemy))
	C, ally, enemy = world("all")
	check("all applies to both", C.AppliesTo(ally) and C.AppliesTo(enemy))
end

do
	fresh({})
	local A = require("bots/FunLib/humaniser/ability_classes")
	check("stun is key", A.Classify("lion_impale", false) == "key")
	check("blink item is key", A.Classify("item_blink", false) == "key")
	check("ultimate flag wins", A.Classify("lion_finger_of_death", true) == "ult")
	check("ultimate flag beats the key table", A.Classify("lion_impale", true) == "ult")
	check("mana drain is other", A.Classify("lion_mana_drain", false) == "other")
	check("unknown is other", A.Classify("not_an_ability", false) == "other")
	check("blink is an escape", A.IsEscape("antimage_blink"))
	check("a stun is not an escape", not A.IsEscape("lion_impale"))
	check("escape items", A.IsEscape("item_blink") and A.IsEscape("item_black_king_bar"))
	for _, n in ipairs({ "dazzle_shallow_grave", "winter_wyvern_cold_embrace", "shadow_demon_disruption",
		"juggernaut_blade_fury", "life_stealer_rage" }) do
		check("not an escape: " .. n, not A.IsEscape(n))
	end
	check("disruption stays key", A.Classify("shadow_demon_disruption", false) == "key")
	check("spell immunity stays key", A.Classify("juggernaut_blade_fury", false) == "key")
	check("shallow grave is not key", A.Classify("dazzle_shallow_grave", false) == "other")
	check("slows and non-hard disables are other", A.Classify("treant_natures_grasp", false) == "other"
		and A.Classify("tinker_warp_grenade", false) == "other" and A.Classify("tidehunter_gush", false) == "other")
	check("escapes classify as key", A.Classify("antimage_blink", false) == "key")
end

finish()
