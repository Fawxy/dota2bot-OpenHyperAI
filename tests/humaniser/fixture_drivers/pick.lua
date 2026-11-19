-- Driver: LanePick.Choose (the laning body's creep pick, states/lane_pick.ts) on a world cut from a game (ev=cut kind=pick, tools/hlog/cut.js)
-- or written by hand. Choose is pure over its arguments: the world is the line, in the cut's fields. What the game's callbacks answered is
-- taken as logged, not recomputed: `mine` per target, the walk-in limit `far`, and the idle swing found.
-- world: ord (the order of kinds, ","-joined), tg (offered targets, ";"-joined records "n,kind,eta,due,walk,dies,ranged,mine"; -1 is an infinite
--        time), cur (the offer the attempt waits on; -1: its creep is not among them; absent: none), pre ("n,eta,walk,dies", n the offer on the
--        same creep, -1 none; absent: none), far ("n,ok" per creep asked, ";"-joined, "-" none; absent: no limit given), idle ("0" none found,
--        else "n,kind,eta,due,walk,dies,ranged"; absent: not asked).
-- Observation: one action, verb the answer (its place in the offer, "pre", "idle" or "none"), target its kind (`lasthit`, `deny`, `prehit`, "none").
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function split(s, sep)
	local out = {}
	for part in string.gmatch(s, "[^" .. sep .. "]+") do table.insert(out, part) end
	return out
end

local function secs(v)
	v = tonumber(v)
	return v == -1 and math.huge or v
end

return function(fx)
	local w = fx.world
	FreshHumaniser({ Enable = false })
	local Pick = require("bots/FunLib/humaniser/states/lane_pick")
	local creeps, targets, mine = {}, {}, {}
	for _, rec in ipairs(split(w.tg or "", ";")) do
		local f = split(rec, ",")
		local n = tonumber(f[1])
		creeps[n] = {}
		local t = { creep = creeps[n], kind = f[2], eta = secs(f[3]), due = secs(f[4]), walk = secs(f[5]), dies = secs(f[6]), ranged = f[7] == "1" }
		targets[n] = t
		mine[t] = f[8] == "1"
	end
	local function creepOf(n)
		n = tonumber(n)
		return creeps[n] or {}
	end
	local current, pre, far, idleFn, idle
	if w.cur ~= nil then
		current = targets[tonumber(w.cur)] or { creep = {}, kind = "lasthit", eta = 0, due = 0, walk = 0, dies = math.huge, ranged = false }
	end
	if w.pre ~= nil then
		local f = split(w.pre, ",")
		local eta = secs(f[2])
		pre = { creep = creepOf(f[1]), kind = "prehit", eta = eta, due = eta, walk = secs(f[3]), dies = secs(f[4]), ranged = false }
	end
	if w.far ~= nil then
		local ok = {}
		for _, rec in ipairs(split(w.far, ";")) do
			local f = split(rec, ",")
			if f[2] ~= nil then ok[creepOf(f[1])] = f[2] == "1" end
		end
		far = function(t) return ok[t.creep] == true end
	end
	if w.idle ~= nil then
		if w.idle ~= "0" then
			local f = split(w.idle, ",")
			idle = { creep = creepOf(f[1]), kind = f[2], eta = secs(f[3]), due = secs(f[4]), walk = secs(f[5]), dies = secs(f[6]), ranged = f[7] == "1" }
		end
		idleFn = function() return idle end
	end
	local kinds = split(w.ord or "lasthit,pre_hit,deny,idle_swing", ",")
	local chosen = Pick.Choose(targets, current, function(t) return mine[t] ~= false end, pre, idleFn, far, kinds)
	local ans = "none"
	if chosen ~= nil then
		if chosen == pre then ans = "pre"
		elseif chosen == idle then ans = "idle"
		else
			for n, t in pairs(targets) do if t == chosen then ans = tostring(n) end end
		end
	end
	return { actions = { { verb = ans, target = chosen ~= nil and chosen.kind or "none" } } }
end
