-- Driver: Trade.Decide (D18 hit, D24 hit back, D19 kill, D10 join: the one hero-on-hero exchange decision), on a world cut from a game
-- (ev=cut kind=trade2, tools/hlog/cut.js) or written by hand. Decide is pure over Inputs: the world is its record, in the cut's fields.
-- world: hp, bu, n, mi (the threat read here: our HP share, their burst over it, heroes that reach us, unseen weight), tm (1: a tower
--        attacks us), hc (creeps attacking us), cr (creeps within 500), dn (1: a deny is due), t (the clock), role (logged only);
--        pjr "dec:tgt:ko:kt" (the pair answer), pl "id:kind:tgt:zero" (a running play; `-` no zero);
--        cd: candidates, ";"-joined records "pid,thp,thpAbs,d,gap,away,arr,hit,free,ko,kt,paid,tw,wb,wn,wm,cok,cdm,csf,lo" (`-` absent; lo: lost, absent on older lines);
--        run: "level:tgt:src:alive:offered:started:landed:soFar:catchFails:failAge:stepFor:chaseX:chaseY:unseenCatchOk" with uat, utw, uth.
-- Observation: none(<first failed gate or end>), hit(hero#P), hitback(hero#P), kill(hero#P) or join(hero#P); end(<why>) when a running
-- exchange ended this frame (`higher`: another candidate won); hold(<hitback|join>) when Holds says retreat waits; fact.hp, fact.burst, fact.n.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function split(s, sep)
	local out, from = {}, 1
	while true do
		local at = string.find(s, sep, from, true)
		if at == nil then
			table.insert(out, string.sub(s, from))
			return out
		end
		table.insert(out, string.sub(s, from, at - 1))
		from = at + #sep
	end
end

local function num(v)
	if v == nil or v == "-" or v == "" then return nil end
	return tonumber(v)
end

local function bit(v)
	return v == 1 or v == true or v == "1"
end

return function(fx)
	local w = fx.world
	FreshHumaniser({ Enable = true })
	local Trade = require("bots/FunLib/humaniser/states/trade")
	local now = w.t or 100
	local i = {
		now = now,
		hp = w.hp,
		burst = w.bu,
		n = w.n,
		missing = w.mi or 0,
		towerOnMe = bit(w.tm),
		creepsOnMe = w.hc,
		wave = w.cr,
		denyDue = bit(w.dn),
		cands = {},
	}
	if w.pjr ~= nil and w.pjr ~= "" then
		local f = split(w.pjr, ":")
		i.pair = { dec = f[1], tgt = num(f[2]), ko = num(f[3]), kt = num(f[4]) }
	end
	if w.pl ~= nil and w.pl ~= "" then
		local f = split(w.pl, ":")
		i.play = { id = num(f[1]), kind = f[2], tgt = num(f[3]), zero = f[4] ~= "-" and f[4] or nil }
	end
	for _, rec in ipairs(split(w.cd or "", ";")) do
		if rec ~= "" then
			local f = split(rec, ",")
			local c = { pid = num(f[1]), thp = num(f[2]), thpAbs = num(f[3]), d = num(f[4]), gap = num(f[5]), away = num(f[6]),
				arrives = bit(num(f[7])), hitting = bit(num(f[8])), free = bit(num(f[9])), ko = num(f[10]), kt = num(f[11]),
				paid = bit(num(f[12])), tw = bit(num(f[13])), lost = bit(num(f[20])) }
			if num(f[14]) ~= nil then c.walk = { burst = num(f[14]), n = num(f[15]), missing = num(f[16]) } end
			if num(f[17]) ~= nil then c.catch = { ok = bit(num(f[17])), dmg = num(f[18]) or 0, first = 0, safe = num(f[19]) or 0 } end
			table.insert(i.cands, c)
		end
	end
	if w.run ~= nil and w.run ~= "" then
		local f = split(w.run, ":")
		local r = { level = f[1], target = num(f[2]), source = f[3] ~= "-" and f[3] or nil, alive = bit(num(f[4])), offered = num(f[5]),
			started = num(f[6]), landed = bit(num(f[7])), soFar = num(f[8]), catchFails = num(f[9]) or 0,
			catchFailAt = num(f[10]) ~= nil and now - num(f[10]) or nil, stepFor = num(f[11]) }
		if num(f[12]) ~= nil then r.chaseAt = { x = num(f[12]), y = num(f[13]) } end
		if num(f[14]) ~= nil then r.catch = { ok = bit(num(f[14])), dmg = 0, first = 0, safe = 0 } end
		if w.uat ~= nil or w.utw ~= nil or w.uth ~= nil then r.unseen = { at = bit(w.uat), tower = bit(w.utw), threat = bit(w.uth) } end
		i.run = r
	end
	local a = Trade.Decide(i)
	local actions = {}
	if a.level == "none" then
		table.insert(actions, { verb = "none", target = a.reason })
	else
		table.insert(actions, { verb = a.level, target = "hero#" .. tostring(a.target) })
	end
	if a.ended ~= nil then table.insert(actions, { verb = "end", target = a.ended }) end
	local held = Trade.HoldsOf(i)
	if held ~= nil then table.insert(actions, { verb = "hold", target = held }) end
	return { actions = actions, fact = { hp = w.hp, burst = w.bu, n = w.n } }
end
