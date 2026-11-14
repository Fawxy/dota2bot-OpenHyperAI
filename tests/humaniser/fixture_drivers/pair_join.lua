-- Driver: PairJoin.Decide (D10, the pair join: join a fight on an ally hit by a hero when our side's best kill share beats
-- theirs), on a world cut from a game (ev=cut kind=join, tools/hlog/cut.js) or written by hand. Decide is pure: the world is
-- its record.
-- world: ally (pid of the hit ally), ours [{pid, x, y, hp, mhp, ret}], theirs [{pid, x, y, hp, mhp}],
--        dmg [{from, to, d}] (GetEstimatedDamageToTarget over PairJoin Window, both ways).
-- Observation: join(hero#<tgt>) or out(<outnumbered|losing>); fact.ko, fact.kt (the two kill shares), fact.ours, fact.theirs.
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
	local a = PairJoin.Decide({ ally = w.ally, ours = w.ours or {}, theirs = w.theirs or {}, dmg = dmg })
	local action = a.dec == "join" and { verb = "join", target = "hero#" .. a.tgt } or { verb = "out", target = a.dec }
	return {
		actions = { action },
		fact = { ko = a.ko, kt = a.kt, ours = #(w.ours or {}), theirs = #(w.theirs or {}) },
	}
end
