-- Driver: Safe.Decide (the safe-here read, hum/safe.ts) on a world cut from a game (ev=cut kind=safe, tools/hlog/cut.js) or written
-- by hand. Decide is pure over Inputs: the world is its record, in the cut's fields.
-- world: hpa, hpm (HP and max HP, absolute), rr ("pid,hitting,dmg,unseen" records, ";"-joined; absent: none in reach), mi (the unseen
--        weight), stw ("tower,towerOnMe", 1/0), ld ("hero,creeps,tower" HP a second), awy, hld, hd (1/0: away, held, hold),
--        prs (1/0: a hero damaged us lately; absent on an older cut, where a hitting reacher stands in).
-- Observation: lv(why), e.g. deadly(kill); fact.kill, fact.ratio (absent when nothing reaches), fact.price.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function split(s, sep)
	local out = {}
	for part in string.gmatch(s, "[^" .. sep .. "]+") do table.insert(out, part) end
	return out
end

return function(fx)
	local w = fx.world
	FreshHumaniser({ Enable = true })
	local Safe = require("bots/FunLib/humaniser/safe")
	local reach = {}
	for _, rec in ipairs(split(w.rr or "", ";")) do
		local f = split(rec, ",")
		table.insert(reach, { pid = tonumber(f[1]), hitting = f[2] == "1", dmg = tonumber(f[3]), unseen = f[4] == "1" or nil })
	end
	local tw = split(w.stw or "0,0", ",")
	local ld = split(w.ld or "0,0,0", ",")
	local a = Safe.Decide({
		hp = w.hpa, hpMax = w.hpm, reach = reach, missing = w.mi or 0,
		tower = tw[1] == "1", towerOnMe = tw[2] == "1",
		landing = { hero = tonumber(ld[1]), creeps = tonumber(ld[2]), tower = tonumber(ld[3]) },
		away = w.awy == 1, held = w.hld == 1, hold = w.hd == 1, pressed = w.prs == 1,
	})
	return {
		actions = { { verb = a.level, target = a.reason } },
		fact = { kill = a.kill, ratio = a.kill > 0 and a.ratio or nil, price = a.price },
	}
end
