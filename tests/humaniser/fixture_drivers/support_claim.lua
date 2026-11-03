-- Driver: a support's claim on one lane creep (states/lane_claims SupportClaim: is the creep the support's to last-hit, or
-- will an allied core take it?), in a lane_world world (lane_world_fixture.lua).
-- world: as lane_world_fixture.lua (heroes take `spa`, seconds per attack), plus
--   subject: the support's pid;
--   target: {creep, kind (lasthit|deny), eta, due, walk, dies, ranged}: the creep as the support's laneTargets offers it;
--   offers: {[pid] = [{creep, kind, eta, due, walk, dies, ranged}]}: each core's laneTargets (the engine's facts, given);
--   attempts: {[pid] = {creep, ph (lasthit|deny)}}: the creep a core's laning body is in an attempt on.
-- Observation: claim(<deny|free|busy>), or noClaim when an allied core will take the creep.
dofile(HARNESS_DIR .. "/fixture_drivers/lane_world_fixture.lua")

local function offer(o, creeps)
	return { creep = creeps[o.creep], kind = o.kind or "lasthit", eta = o.eta, due = o.due or o.eta, walk = o.walk or 0,
		dies = o.dies, ranged = o.ranged == true }
end

return function(fx, skill)
	local w = fx.world
	local H, units, creeps = LaneFixtureWorld(w, skill)
	for _, h in ipairs(w.heroes or {}) do
		if h.spa then units[h.pid].GetSecondsPerAttack = function() return h.spa end end
	end
	local offers = {}
	for pid, list in pairs(w.offers or {}) do
		local out = {}
		for _, o in ipairs(list) do table.insert(out, offer(o, creeps)) end
		offers[tonumber(pid)] = out
	end
	require("bots/FunLib/humaniser/tasks").Verbs = function()
		return { laneTargets = function(u) return offers[u:GetPlayerID()] or {} end }
	end
	local Pick = require("bots/FunLib/humaniser/states/lane_pick")
	for pid, a in pairs(w.attempts or {}) do
		pid = tonumber(pid)
		local cur
		for _, o in ipairs(offers[pid] or {}) do if o.creep == creeps[a.creep] then cur = o end end
		cur = cur or offer({ creep = a.creep, kind = a.ph, eta = 1, dies = 2 }, creeps)
		Pick.NotePick(pid, T, offers[pid] or { cur }, cur)
		Pick.NotePhase(pid, a.ph or "lasthit")
	end
	local Claims = require("bots/FunLib/humaniser/states/lane_claims")
	local claim = Claims.SupportClaim(units[w.subject], offer(w.target, creeps), w.within or 1200)
	return { actions = { claim == nil and { verb = "noClaim" } or { verb = "claim", target = claim } } }
end
