-- Slice fight-safe (D19, `Ours.FightSafe`): the lane-fight roll and join ask trade-safe's "is it safe?" (their burst in reach)
-- in place of `behind`. The gate as one answer (CoreTrade.FightAnswer: the core's refusal, then the roll's hard zeros).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })
local Ours = package.loaded["bots/FunLib/custom_loader"].Ours
local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")
local KILL_HP = 0.4

local function inputs(o)
	local i = { hp = 0.62, targetHp = 0.95, enemiesNear = 1, alliesNear = 1, enemyCreepsNear = 1, hitByCreeps = 0, tower = false,
		burst = 0.4, towerOnMe = false }
	for k, v in pairs(o or {}) do i[k] = v end
	return i
end

local function roll(i, o)
	local pi = { kind = CoreTrade.LANE_FIGHT, ourLevel = 1, theirLevel = 1, ours = 1, theirs = 1, hp = i.hp, mana = 1,
		targetHp = i.targetHp, rune = false, tower = math.huge, skill = 1 }
	for k, v in pairs(o or {}) do pi[k] = v end
	return pi
end

local function answer(o, po)
	local i = inputs(o)
	return CoreTrade.FightAnswer(i, KILL_HP, roll(i, po))
end

do
	Ours.FightSafe, Ours.TradeSafe = true, true
	check("33 points behind the target, their burst under our HP: a chance is offered (behind is gone)", answer() == "roll")
	check("the same HP gap with their burst at our HP: refused on burst (D1, the control)", answer({ burst = 1.0 }) == "burst")
	check("the target alone by its tower: refused, though the safe trade rule would harass it",
		answer({ tower = true }) == "tower" and CoreTrade.Decide(inputs({ tower = true })).kind == "trade")
	check("more of them within the play radius than us: the roll's own decline", answer({}, { theirs = 2 }) == "outnumbered")
	check("under the roll's HP floor: the library's zero", answer({ hp = 0.38, targetHp = 0.5 }) == "hp")

	Ours.FightSafe = false
	check("switch off: the old rule, behind", answer() == "behind")
	check("switch off: no burst question (ahead on HP at their burst 1.2 still rolls)",
		answer({ hp = 0.9, targetHp = 0.8, burst = 1.2 }) == "roll")

	Ours.FightSafe, Ours.TradeSafe = true, false
	local i = inputs()
	i.burst, i.towerOnMe = nil, nil
	check("TradeSafe off leaves no burst read: behind stays", CoreTrade.FightAnswer(i, KILL_HP, roll(i)) == "behind")
	Ours.TradeSafe = true
end
finish()
