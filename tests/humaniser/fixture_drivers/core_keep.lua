-- Driver: CoreTrade.KeepAnswer (slice chase-log; D19's kill and D10's join kept or ended each frame), on a world cut from a
-- game (ev=cut kind=keep, tools/hlog/cut.js) or written by hand. KeepAnswer is pure over its inputs: the world is its record.
-- world: ek (kill|join), alv, sn (1|0: the target alive, seen), oa, sa (seconds since the offer, the start; sa absent: not
--        started), jn (join: none|same|other), kh (kill HP share), hb (1: a hit back);
--        hp, thp, en, ally, cr, hc, tw, bu, tm: Gather's on the target as on the trade cut (present where the answer reads them);
--        slice kill-chase: chu, cth (the catch read's hunters and the target's HP), uat, utw, uou, uth (unseen reads), kup.
-- Observation: keep, or end(<target_dead|target_lost|pair_end|retarget|not_taken|time|tower|outnumbered|low_hp|...|hb_hp|hb_burst>);
-- fact.sa, fact.thp.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function bit(v)
	return v == 1 or v == true
end

return function(fx)
	local w = fx.world
	FreshHumaniser({ Enable = true })
	local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")
	local k = {
		kind = w.ek,
		alive = bit(w.alv),
		seen = bit(w.sn),
		offered = w.oa,
		started = w.sa,
		join = w.jn,
		killHp = w.kh,
		hb = bit(w.hb),
	}
	if w.hp ~= nil then
		k.g = {
			hp = w.hp,
			targetHp = w.thp,
			enemiesNear = w.en,
			alliesNear = w.ally,
			enemyCreepsNear = w.cr,
			hitByCreeps = w.hc,
			tower = bit(w.tw),
			burst = w.bu,
			towerOnMe = w.bu ~= nil and bit(w.tm) or nil,
		}
	end
	-- Slice kill-chase: the catch read's hunters (`chu`: d,reach,close,dps,spells with spells range:cp:dmg joined by /), the
	-- target's HP (`cth`), the unseen reads (uat, utw, uou, uth) and a join's hand-over (kup).
	if w.chu ~= nil and w.cth ~= nil then
		k.hunters = {}
		for rec in string.gmatch(w.chu, "[^;]+") do
			local f = {}
			for v in string.gmatch(rec .. ",", "([^,]*),") do table.insert(f, v) end
			local spells = {}
			for s in string.gmatch(f[5] or "", "[^/]+") do
				local r, cp, dm = s:match("^([^:]+):([^:]+):([^:]+)$")
				if r then table.insert(spells, { range = tonumber(r), cp = tonumber(cp), dmg = tonumber(dm) }) end
			end
			table.insert(k.hunters, { d = tonumber(f[1]), reach = tonumber(f[2]), close = tonumber(f[3]), dps = tonumber(f[4]), spells = spells })
		end
		k.thpAbs = w.cth
	end
	for key, field in pairs({ at = "uat", utower = "utw", uout = "uou", threat = "uth", killUp = "kup" }) do
		if w[field] ~= nil then k[key] = bit(w[field]) end
	end
	local why = CoreTrade.KeepAnswer(k)
	local action = why == nil and { verb = "keep" } or { verb = "end", target = why }
	return {
		actions = { action },
		fact = { sa = w.sa or -1, thp = w.thp or -1 },
	}
end
