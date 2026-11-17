-- Driver: CoreTrade.Answer (D18 harass, D19's commit: a laner's fresh decision on the enemy hero in its reach with no trade
-- running), on a world cut from a game (ev=cut kind=trade, tools/hlog/cut.js) or written by hand. Answer is pure over
-- Decide's inputs: the world is its record.
-- world: hp, thp (HP shares), en, ally (heroes within 1,200), cr, hc (enemy creeps within 500, those on the bot), tw (0|1),
--        kh (kill HP share), gap (HP-share gap a lost trade left; absent none).
-- world, slice trade-safe: bu (burst over HP), tm (0|1, tower on the bot); with bu the safe rule decides.
-- world, slice trade-free: tf (1: question 2 asked), tlh, ar, tar, ko, kt, dn; with tf the answer may be unfavoured or deny, never gap.
-- world, slice lone-mid-exchange: te (0 turns Ours.TradeEven off: a lone core at 70% HP or more is held `unfavoured` again; absent: on).
-- world, slice hitback-fold: hb (1: the target is hitting the bot; CoreTrade.Exchange then answers whether the exchange is taken
--        as a hit back: hb_hp under 70% HP, hb_burst at two heroes, else Answer's).
-- Observation: trade, kill or respect(<tower|outnumbered|low_hp|behind|burst|creeps|wave|gap|unfavoured|deny|hb_hp|hb_burst>); fact.hp, fact.thp, fact.cr.
-- world, slice fight-safe: lf (1: the core's lane fights are ours) adds the lane-fight gate's answer (CoreTrade.FightAnswer) as
-- a second action, fight(<roll|kill|tower|outnumbered|burst|hp|behind>); fpo, fpt, ftd the roll's inputs as logged (absent: ally,
-- en and no tower); fs as logged, 0 turning Ours.FightSafe off (the old `behind`; absent: on).
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
	-- Slice trade-free: with tf (a cut made with Ours.TradeFree on, or a hand world) question 2 replaces gap.
	if (w.tf == 1 or w.tf == true) and CoreTrade.Free ~= nil then
		inputs.free = CoreTrade.Free(w.tlh == 1, w.ar, w.tar)
		if not inputs.free then
			inputs.ko, inputs.kt = w.ko, w.kt
			inputs.outranged = CoreTrade.Outranged ~= nil and CoreTrade.Outranged(w.ar, w.tar) or nil
		end
		-- Round 2: dn (1: the laning body is offered a deny now) outbids a free or favoured trade.
		inputs.denyDue = w.dn == 1 or w.dn == true
	end
	-- Slice hitback-fold: hb (1: the target is hitting the bot) is an input of the one decision, Exchange.
	if w.hb == 1 or w.hb == true then inputs.hitting = true end
	-- Slice lone-mid-exchange: te 0 turns Ours.TradeEven off (question 2 holds a lone core's even exchange; absent: on).
	package.loaded["bots/FunLib/custom_loader"].Ours.TradeEven = w.te ~= 0 and w.te ~= false
	local a = CoreTrade.Exchange(inputs, w.kh, w.gap)
	local action = (a == "trade" or a == "kill") and { verb = a } or { verb = "respect", target = a }
	local actions = { action }
	if (w.lf == 1 or w.lf == true) and CoreTrade.FightAnswer ~= nil then
		package.loaded["bots/FunLib/custom_loader"].Ours.FightSafe = w.fs ~= 0 and w.fs ~= false
		local pi = {
			kind = CoreTrade.LANE_FIGHT,
			ourLevel = 1,
			theirLevel = 1,
			ours = w.fpo or w.ally,
			theirs = w.fpt or w.en,
			hp = w.hp,
			mana = 1,
			targetHp = w.thp,
			rune = false,
			tower = w.ftd or math.huge,
			skill = 1,
		}
		table.insert(actions, { verb = "fight", target = CoreTrade.FightAnswer(inputs, w.kh, pi) })
	end
	return {
		actions = actions,
		fact = { hp = w.hp, thp = w.thp, cr = w.cr },
	}
end
