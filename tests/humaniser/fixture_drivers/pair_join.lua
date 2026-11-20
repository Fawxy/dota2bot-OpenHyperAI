-- Driver: PairJoin.Decide (D10, the pair join: join a fight on an ally hit by a hero when our side's best kill share beats
-- theirs), on a world cut from a game (ev=cut kind=join, tools/hlog/cut.js) or written by hand. Decide is pure: the world is
-- its record.
-- world: ally (pid of the hit ally), ours [{pid, x, y, hp, mhp, ret}], theirs [{pid, x, y, hp, mhp}],
--        dmg [{from, to, d}] (GetEstimatedDamageToTarget over PairJoin Window, both ways).
--        ar "pid,reach,speed,hull;..." (the cut's `jar`; absent on older lines: counted whole), arv (the cut's `jav`; 1: Ours.JoinArrive on).
-- Observation: join(hero#<tgt>) or out(losing); fact.ko, fact.kt (the two kill shares), fact.ours, fact.theirs.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

return function(fx)
	local w = fx.world
	FreshHumaniser({ Enable = true })
	local PairJoin = require("bots/FunLib/humaniser/pair_join")
	local dmg = {}
	for _, e in ipairs(w.dmg or {}) do
		local from, to = tonumber(e.from), tonumber(e.to)
		dmg[from] = dmg[from] or {}
		dmg[from][to] = e.d
	end
	local ours, theirs = w.ours or {}, w.theirs or {}
	if w.ar ~= nil and w.ar ~= "" then
		local reach = {}
		for r in tostring(w.ar):gmatch("[^;]+") do
			local pid, rc, ms, hull = r:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
			reach[tonumber(pid)] = { rc = tonumber(rc), ms = tonumber(ms), hull = tonumber(hull) }
		end
		for _, side in ipairs({ ours, theirs }) do
			for _, m in ipairs(side) do
				local x = reach[tonumber(m.pid)]
				if x then m.rc, m.ms, m.hull = x.rc, x.ms, x.hull end
			end
		end
	end
	local a = PairJoin.Decide({ ally = w.ally, ours = ours, theirs = theirs, dmg = dmg, arrive = tonumber(w.arv) == 1 or nil })
	return {
		actions = { a.dec == "join" and { verb = "join", target = "hero#" .. a.tgt } or { verb = "out", target = a.dec } },
		fact = { ko = a.ko, kt = a.kt, ours = #(w.ours or {}), theirs = #(w.theirs or {}) },
	}
end
