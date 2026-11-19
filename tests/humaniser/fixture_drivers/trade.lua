-- Driver: Trade.Decide (D18 hit, D24 hit back, D19 kill, D10 join: the one hero-on-hero exchange decision), on a world cut from a game
-- (ev=cut kind=trade, tools/hlog/cut.js) or written by hand. Decide is pure over Inputs: the world is its record, in the cut's fields.
-- world: hp (our HP share), svh, svb ("level,ratio,reason": Safe.At here held, without a hold (for a hit) and with one (hit back, kill, join);
--        ratio `-` when nothing reaches), n (enemy heroes within 1,600), ms (our speed;
--        absent on older lines: 300), tm (1: a tower
--        attacks us), hc (creeps attacking us), cr (creeps within 500), dn (1: a deny is due), t (the clock), role (logged only);
--        pjr "dec:tgt:ko:kt" (the pair answer), pl "id:kind:tgt:zero" (a running play; `-` no zero);
--        cd: candidates, ";"-joined records "pid,thp,thpAbs,d,gap,away,arr (read for the eye, unused),hit,free,ko,kt,paid,tw,wlv,wra,wwhy,cok,cdm,csf,lo,sw" (`-` absent; sw: hit us within its attack interval, absent on older lines; wlv, wra, wwhy: Safe.At along the walk, away and with a hold; lo: lost, absent on older lines);
--        run: "level:tgt:src:alive:offered:started:landed:soFar:catchFails:failAge:stepFor:chaseX:chaseY:unseenCatchOk" with uat, utw, uth.
-- Observation: none(<first failed gate or end>), hit(hero#P), hitback(hero#P), kill(hero#P) or join(hero#P); end(<why>) when a running
-- exchange ended this frame (`higher`: another candidate won); hold(<hitback|join>) when Holds says retreat waits; chance(<roll|tower|burst|wave>)
-- when the answer is a hit or none and a lane-fight chance would be offered (`roll`) or what zeroes it (Trade.FightZero), on the hit's target,
-- else the nearest candidate; fact.hp, fact.n.
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

local function say(v)
	if v == nil or v == "-" or v == "" then return nil end
	local f = split(v, ",")
	return { level = f[1], ratio = num(f[2]) or math.huge, reason = f[3] }
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
		safe = { hit = say(w.svh), hold = say(w.svb) },
		n = w.n or 1,
		ms = w.ms or 300,
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
				hitting = bit(num(f[8])), free = bit(num(f[9])), ko = num(f[10]), kt = num(f[11]),
				paid = bit(num(f[12])), tw = bit(num(f[13])), lost = bit(num(f[20])) }
			-- Lines from before `sw` read the 1 s flag as the stay bar too: swung is never narrower than hitting.
			if num(f[21]) ~= nil then c.swung = bit(num(f[21])) else c.swung = c.hitting end
			if f[14] ~= nil and f[14] ~= "-" then c.walk = say(f[14] .. "," .. f[15] .. "," .. f[16]) end
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
	-- opens(<reasons>): the gates of every level that fail on the answer's target read fresh (Trade.OpenFails, slice trade-count), `-` for none.
	if a.level ~= "none" then
		for _, x in ipairs(i.cands) do
			if x.pid == a.target then
				local s = table.concat(Trade.OpenFails(i, x), ",")
				table.insert(actions, { verb = "opens", target = s == "" and "-" or s })
			end
		end
	end
	-- endkinds(<reason=kind,...>): Trade.ENDS, which end reasons a start gate can already hold for (`gate`, `think`) and which only come later.
	do
		local ks = {}
		for r, k in pairs(Trade.ENDS) do table.insert(ks, r .. "=" .. k) end
		table.sort(ks)
		table.insert(actions, { verb = "endkinds", target = table.concat(ks, ",") })
	end
	if a.level == "hit" or a.level == "none" then
		local c
		for _, x in ipairs(i.cands) do
			if (a.level == "hit" and x.pid == a.target) or (a.level == "none" and (c == nil or x.d < c.d)) then c = x end
		end
		if c ~= nil then table.insert(actions, { verb = "chance", target = Trade.FightZero(i, c) or "roll" }) end
	end
	local held = Trade.HoldsOf(i)
	if held ~= nil then table.insert(actions, { verb = "hold", target = held }) end
	return { actions = actions, fact = { hp = w.hp, n = i.n } }
end
