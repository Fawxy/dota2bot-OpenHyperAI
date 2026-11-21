dofile(HARNESS_DIR .. "/lane_world.lua")
-- The commitment tracker (decision centre pilot step 1, Ours.PricedLeave; leave-on-commitment.md s2): each enemy's state towards one of
-- our heroes from its hit times, the burst-now split, the damage callback's arguments resolved to who hit whom, and the logged lines.
local HERE = Vector(-2000, -5000)

local lines, cbs
local function world(ours)
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true, Cut = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours.PricedLeave = ours ~= false
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	lines, cbs = {}, {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	InstallDamageCallback = function(pid, fn) cbs[pid] = fn end
	require("bots/FunLib/humaniser/spell_ready").DamageOn = function(e, _, w) return (e.perSec or 0) * w end
	local C = require("bots/FunLib/humaniser/commit")
	C.Reset()
	local bot = MakeUnit({ pid = 1, team = 2, loc = HERE, level = 3 })
	bot.maxhp, bot.hp = 1000, 1000
	return C, bot
end
local function enemy(pid, x, perSec)
	local e = MakeUnit({ pid = pid, team = 3, loc = Vector(x, -5000) })
	e.maxhp, e.hp, e.perSec = 600, 600, perSec
	return e
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end
local function evs(name)
	local r = {}
	for _, l in ipairs(lines) do if l:find("ev=" .. name .. " ", 1, true) then r[#r + 1] = l end end
	return r
end

local C = require("bots/FunLib/humaniser/commit")
-- Pure: HitState and States.
check("a lone poke is poked; a second hit 0.4 s later (spell then attack) is still poked",
	C.HitState({ 99 }, 100, 1).st == "poked" and C.HitState({ 99, 99.4 }, 100, 1).st == "poked")
check("a second hit in a separate second within 4 s is committed (why second)",
	C.HitState({ 97, 98.5 }, 100, 1).st == "committed" and C.HitState({ 97, 98.5 }, 100, 1).why == "second")
check("two heroes each hitting once in 3 s are both committed (why pair)", (function()
	local s = C.States({ [10] = { 99 }, [11] = { 98 } }, { [10] = true, [11] = true }, 100)
	return s[10].st == "committed" and s[11].st == "committed" and s[10].why == "pair"
end)())
check("a third reacher not hitting while two hit us is near", (function()
	local s = C.States({ [10] = { 99 }, [11] = { 98 } }, { [10] = true, [11] = true, [12] = true }, 100)
	return s[12].st == "near"
end)())
check("committed is held while the evidence holds and lapses: hits at 97 and 98.5 are committed at 100.9, poked at 101.5 (the first is over 4 s), nothing at 101.6+",
	C.HitState({ 97, 98.5 }, 100.9, 1).st == "committed" and C.HitState({ 97, 98.5 }, 101.5, 1).st == "poked"
		and C.HitState({ 97, 98.5 }, 101.6, 1).st == nil)
check("a hero that stopped hitting for over 3 s is near when in reach, absent when not", (function()
	local s = C.States({ [10] = { 96 } }, { [10] = true }, 100)
	local g = C.States({ [10] = { 96 } }, {}, 100)
	return s[10].st == "near" and s[10].why == "reach" and g[10] == nil
end)())
check("burst split: the ready-spell part is DamageOn less the attacks over the window, floored at 0; one attack apart",
	C.SplitBurst(300, 50, 60).spell == 250 and C.SplitBurst(300, 50, 60).attack == 60 and C.SplitBurst(40, 50, 60).spell == 0)

-- The callback's arguments.
do
	local _, bot = world()
	local e = enemy(10, -1700, 0)
	local ally = MakeUnit({ pid = 2, team = 2, loc = HERE })
	local teamOf = GetTeamForPlayer
	local r = C.Resolve(C.ParseArgs({ bot, e, 55 }), 2, teamOf)
	check("(victim, attacker, damage) handles resolve to our hero hit by the enemy", r and r.victim == 1 and r.attacker == 10, r)
	-- The shape smoke dc-step1 logged: player_id is the victim's.
	local t = C.ParseArgs({ { ability = {}, player_id = 1, attacking_unit = e, attacking_player_id = 10, damage = 72, unit = bot } })
	r = C.Resolve(t, 2, teamOf)
	check("the game's table resolves by attacking_unit, not player_id (the victim's)", t.dmg == 72 and r and r.victim == 1 and r.attacker == 10, r)
	t = C.ParseArgs({ { player_id = 1, attacking_player_id = 10, damage = 72, unit = bot } })
	r = C.Resolve(t, 2, teamOf)
	check("attacking_player_id alone names the attacker", r and r.attacker == 10)
	check("a table naming no attacker is not attributed", C.Resolve(C.ParseArgs({ { damage = 70, player_id = 1, unit = bot } }), 2, teamOf) == nil)
	check("our hero hit by an ally, or an enemy hit by us, is not counted",
		C.Resolve(C.ParseArgs({ bot, ally, 10 }), 2, teamOf) == nil and C.Resolve(C.ParseArgs({ e, bot, 10 }), 2, teamOf) == nil)
end

-- The game step: the poll before the first callback hit, then the callback; transitions logged with the burst split.
do
	local C2, bot = world()
	local e = enemy(10, -1700, 100)
	e.dmg, e.spa = 60, 1.5
	C2.Tick(bot)
	check("the callback is installed on our heroes' ids once, not the enemy's", cbs[1] ~= nil and cbs[10] == nil and #evs("dmgcb") == 1 and field(evs("dmgcb")[1], "kind") == "installed")
	local c = evs("commit")
	check("an enemy in reach is near (one line, src poll, burst over 1 s: spell 100 - 40, one attack 60)",
		#c == 1 and field(c[1], "st") == "near" and field(c[1], "was") == "gone" and field(c[1], "src") == "poll"
			and field(c[1], "bs") == "60" and field(c[1], "ba") == "60" and field(c[1], "bsum") == "120", c[1])
	T = 300.1
	bot.hitBy = { [e] = T }
	C2.Tick(bot)
	c = evs("commit")
	check("the flag poll records a hit: poked", #c == 2 and field(c[2], "st") == "poked" and field(c[2], "why") == "hit", c[2])
	T = 300.2
	C2.Tick(bot)
	check("no change, no line", #evs("commit") == 2)
	T = 301.5
	bot.hitBy = nil
	cbs[1]({ player_id = 1, unit = bot, attacking_unit = e, attacking_player_id = 10, damage = 55 })
	C2.Tick(bot)
	c = evs("commit")
	-- The callback is now the source: its one hit at 301.5 alone is a poke (the poll's hit at 300.1 is not in its list), so no change.
	check("the first callback hit makes it the source and its lone hit is still poked: no line", #c == 2, c[#c])
	T = 302.8
	cbs[1]({ player_id = 1, unit = bot, attacking_unit = e, attacking_player_id = 10, damage = 55 })
	C2.Tick(bot)
	c = evs("commit")
	check("a second callback hit in another second: committed (why second, hits 2)",
		field(c[#c], "st") == "committed" and field(c[#c], "why") == "second" and field(c[#c], "hits") == "2" and field(c[#c], "src") == "cb", c[#c])
	check("the committed line carries the hitter count nh 1", field(c[#c], "nh") == "1", c[#c])
	local shape, sw = {}, {}
	for _, l in ipairs(evs("dmgcb")) do
		if field(l, "kind") == "shape" then shape[#shape + 1] = l end
		if field(l, "kind") == "switch" then sw[#sw + 1] = l end
	end
	check("the first call's shape is logged with ok 1", #shape == 2 and field(shape[1], "ok") == "1", shape[1])
	check("the poll-to-callback switch is logged once as ev=dmgcb kind=switch, not as a commit line", #sw == 1 and field(sw[1], "ipid") == "1", sw[1])
	e.loc = Vector(-9000, -5000)
	T = 306.9
	C2.Tick(bot)
	c = evs("commit")
	check("out of reach with the hits lapsed: gone (why left)", field(c[#c], "st") == "gone" and field(c[#c], "why") == "left", c[#c])
end

-- Near hysteresis: a step out of reach keeps near for NearHold (1 s); fogged, the same, then gone why fog.
do
	local C2, bot = world()
	local e = enemy(10, -1700, 0)
	C2.Tick(bot)
	check("in reach: near", #evs("commit") == 1 and field(evs("commit")[1], "st") == "near")
	e.loc = Vector(-9000, -5000)
	T = 300.5
	C2.Tick(bot)
	e.loc = Vector(-1700, -5000)
	T = 300.6
	C2.Tick(bot)
	check("out of reach for 0.5 s and back: no near/gone pair", #evs("commit") == 1, evs("commit")[2])
	e.loc = Vector(-9000, -5000)
	T = 301.2
	C2.Tick(bot)
	check("out of reach under 1 s: still near", #evs("commit") == 1)
	T = 301.7
	C2.Tick(bot)
	local c = evs("commit")
	check("out of reach over 1 s: gone (why left)", #c == 2 and field(c[2], "st") == "gone" and field(c[2], "why") == "left", c[2])
	e.loc = Vector(-1700, -5000)
	T = 302
	C2.Tick(bot)
	e.hiddenFrom = { [OBSERVER] = true }
	T = 302.5
	C2.Tick(bot)
	check("unseen within 1 s of being in reach: still near", #evs("commit") == 3)
	T = 303.1
	C2.Tick(bot)
	c = evs("commit")
	check("unseen over 1 s: gone (why fog)", #c == 4 and field(c[4], "why") == "fog", c[4])
end

-- An enemy hitting from fog keeps its state and its count (fix: the state is keyed on hit times, not the visible list).
do
	local C2, bot = world()
	local e = enemy(10, -1700, 100)
	local f = enemy(11, -1600, 100)
	f.hiddenFrom = { [OBSERVER] = true }
	C2.Tick(bot)
	cbs[1]({ player_id = 1, unit = bot, attacking_unit = f, attacking_player_id = 11, damage = 40 })
	T = 300.1
	C2.Tick(bot) -- the switch tick
	T = 300.3
	cbs[1]({ player_id = 1, unit = bot, attacking_unit = f, attacking_player_id = 11, damage = 40 })
	C2.Tick(bot)
	check("a fogged enemy hitting us is poked, not dropped (no burst read)", C2.Code(1, 11) == "p" and C2.Nh(1) == 1)
	T = 300.6
	cbs[1]({ player_id = 1, unit = bot, attacking_unit = e, attacking_player_id = 10, damage = 40 })
	C2.Tick(bot)
	check("a visible and a fogged enemy hitting within 3 s: nh 2, both committed (pair)", C2.Nh(1) == 2 and C2.Code(1, 10) == "c" and C2.Code(1, 11) == "c")
	local c = evs("commit")
	local l10, l11
	for _, l in ipairs(c) do
		if field(l, "epid") == "11" then l11 = l end
		if field(l, "epid") == "10" then l10 = l end
	end
	check("the fogged one's line has nh 2 and no burst fields; the visible one's has them", l11 ~= nil and field(l11, "nh") == "2" and field(l11, "st") == "committed"
		and field(l11, "bs") == nil and l10 ~= nil and field(l10, "bs") ~= nil, l11)
	T = 301.5
	for _ = 1, 3 do C2.Tick(bot) end
	c = evs("commit")
	local gone = 0
	for _, l in ipairs(c) do if field(l, "why") == "lost" or field(l, "why") == "fog" then gone = gone + 1 end end
	check("the fogged hitter is not reported gone while its hits hold", gone == 0 and C2.Code(1, 11) == "c")
	check("Hitters(pid, w): fogged included, by window (hits at 300.3 by 11 and 300.6 by 10, now 301.5)", C2.Hitters(1, 3) == 2 and C2.Hitters(1, 1) == 1 and C2.Hitters(1, 0.5) == 0 and C2.Hitters(2, 3) == 0)
	local bn = C2.BurstNow(bot)
	check("BurstNow: the visible enemy only (spell 100 - 0, one attack), the fogged one left out", bn.by[10] ~= nil and bn.by[11] == nil and bn.sum == bn.by[10].spell + bn.by[10].attack)
	-- The rcs column carries nh first.
	local SG = require("bots/FunLib/humaniser/safe_gather")
	local i = { reach = { { pid = 10, hitting = true, dmg = 50 }, { pid = 11, hitting = true, dmg = 50 } }, hp = 900, hpMax = 1000, missing = 0,
		tower = false, towerOnMe = false, landing = { hero = 0, creeps = 0, tower = 0 }, away = false, held = false, hold = false }
	local rcs
	for _, kv in ipairs(SG.CutFields(1, "lane", HERE, i, { level = "stay", kill = 0, price = 0, reason = "x" })) do if kv[1] == "rcs" then rcs = kv[2] end end
	check("rcs is nh then each reacher's state: 2|10,c;11,c", rcs == "2|10,c;11,c", rcs)
	-- The enemy dies: gone (why edead), and nh drops it.
	f.alive = false
	T = 301.6
	C2.Tick(bot)
	c = evs("commit")
	check("an enemy that died goes gone (why edead) and leaves nh", field(c[#c], "epid") == "11" and field(c[#c], "why") == "edead" and C2.Nh(1) == 1, c[#c])
	-- Our hero dies: every tracked enemy gone (why dead), once.
	local before = #c
	bot.alive = false
	T = 301.7
	C2.Tick(bot)
	c = evs("commit")
	check("our hero died: one gone line (why dead) per tracked enemy (10, poked alone once 11 died)", #c == before + 1 and field(c[#c], "why") == "dead" and field(c[#c], "was") == "poked" and field(c[#c], "epid") == "10", c[#c])
	T = 301.8
	C2.Tick(bot)
	check("dead: no further lines", #evs("commit") == before + 1)
end

-- The switch off: no install, no lines.
do
	local C3, bot = world(false)
	enemy(10, -1700, 100)
	C3.Tick(bot)
	check("Ours.PricedLeave off: no callback installed and no line", next(cbs) == nil and #evs("commit") == 0 and #evs("dmgcb") == 0)
end
finish()
