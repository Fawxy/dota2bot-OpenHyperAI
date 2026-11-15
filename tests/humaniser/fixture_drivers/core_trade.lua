-- Driver: CoreTrade.Answer (D18 harass, D19's commit: a laner's fresh decision on the enemy hero in its reach with no trade
-- running), on a world cut from a game (ev=cut kind=trade, tools/hlog/cut.js) or written by hand. Answer is pure over
-- Decide's inputs: the world is its record.
-- world: hp, thp (HP shares), en, ally (heroes within 1,200), cr, hc (enemy creeps within 500, those on the bot), tw (0|1),
--        kh (kill HP share), gap (HP-share gap a lost trade left; absent none).
-- world, slice trade-safe: bu (burst over HP), tm (0|1, tower on the bot); with bu the safe rule decides.
-- Observation: trade, kill or respect(<tower|outnumbered|low_hp|behind|burst|creeps|wave|gap>); fact.hp, fact.thp, fact.cr.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

return function(fx)
	local w = fx.world
	FreshHumaniser({ Enable = true })
	local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")
	local inputs = {
		hp = w.hp,
		targetHp = w.thp,
		enemiesNear = w.en,
		alliesNear = w.ally,
		enemyCreepsNear = w.cr,
		hitByCreeps = w.hc,
		tower = w.tw == 1 or w.tw == true,
		-- Slice trade-safe: present only on a cut made with Ours.TradeSafe on (or a hand world); Decide then asks "is it safe?".
		burst = w.bu,
		towerOnMe = w.bu ~= nil and (w.tm == 1 or w.tm == true) or nil,
	}
	local a = CoreTrade.Answer(inputs, w.kh, w.gap)
	local action = (a == "trade" or a == "kill") and { verb = a } or { verb = "respect", target = a }
	return {
		actions = { action },
		fact = { hp = w.hp, thp = w.thp, cr = w.cr },
	}
end
