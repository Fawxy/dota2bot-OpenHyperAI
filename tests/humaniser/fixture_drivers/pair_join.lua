-- Driver: PairJoin.Decide (D10, the pair join: join a fight on an ally hit by a hero when our side's best kill share beats
-- theirs), on a world cut from a game (ev=cut kind=join, tools/hlog/cut.js) or written by hand. Decide is pure: the world is
-- its record.
-- world: ally (pid of the hit ally), ours [{pid, x, y, hp, mhp, ret}], theirs [{pid, x, y, hp, mhp}],
--        dmg [{from, to, d}] (GetEstimatedDamageToTarget over PairJoin Window, both ways).
--        Slice join-hits, an ours record: focus (the hero the ally's episode is on), ek (that episode's kind), aa (1 when the
--        ally's attack target names the hero, 0 when it has not attacked yet; unset counts as 1), free (the cut's `free`:
--        yes, ret, play, tower, outnumbered, burst; a `yes` with aa 0 is held as `noatk`).
-- Observation: join(hero#<tgt>) or out(<outnumbered|losing>); for an ours record that joins, act(hero#<tgt>) or
-- hold(<free>) (the switch on); none(<ek>) alone when the partner's episode is no trigger; fact.ko, fact.kt (the two kill shares), fact.ours, fact.theirs.
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
	-- focus (slice join-hits, on=ours): the enemy hero the ally's open episode is on; our share and target are on it.
	local a = PairJoin.Decide({ ally = w.ally, focus = w.focus, ours = w.ours or {}, theirs = w.theirs or {}, dmg = dmg })
	local actions = { a.dec == "join" and { verb = "join", target = "hero#" .. a.tgt } or { verb = "out", target = a.dec } }
	-- An ours record (ek, free as cut): what the second hero does with it, `Ours.JoinOnHit` on. A partner's episode that
	-- is no trigger makes no record at all, so there is no weighing either.
	if w.focus ~= nil and w.ek ~= nil then
		if not PairJoin.Opens(w.ek) then
			actions = { { verb = "none", target = w.ek } }
		elseif a.dec == "join" then
			local acts = PairJoin.Acts("ours", true, PairJoin.WithAttack(w.free or "yes", w.aa ~= 0))
			actions[2] = acts and { verb = "act", target = "hero#" .. a.tgt } or { verb = "hold", target = PairJoin.WithAttack(w.free or "yes", w.aa ~= 0) }
		end
	end
	return {
		actions = actions,
		fact = { ko = a.ko, kt = a.kt, ours = #(w.ours or {}), theirs = #(w.theirs or {}) },
	}
end
