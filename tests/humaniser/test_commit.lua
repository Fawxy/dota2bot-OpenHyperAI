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
	local r = C.Resolve(C.ParseArgs({ bot, e, 55 }), 1, 2, teamOf)
	check("(victim, attacker, damage) handles resolve to our hero hit by the enemy", r and r.victim == 1 and r.attacker == 10, r)
	local t = C.ParseArgs({ { damage = 70, player_id = 10, unit = bot } })
	r = C.Resolve(t, 1, 2, teamOf)
	check("a table {damage, player_id, unit} resolves by its keys", t.dmg == 70 and r and r.victim == 1 and r.attacker == 10)
	r = C.Resolve(C.ParseArgs({ { damage = 70, unit = bot } }), 10, 2, teamOf)
	check("a victim with no attacker on a callback installed for an enemy's id: that enemy dealt it", r and r.attacker == 10)
	check("no attacker on a callback installed for our own id cannot be attributed", C.Resolve(C.ParseArgs({ { damage = 70, unit = bot } }), 1, 2, teamOf) == nil)
	check("our hero hit by an ally, or an enemy hit by us, is not counted",
		C.Resolve(C.ParseArgs({ bot, ally, 10 }), 1, 2, teamOf) == nil and C.Resolve(C.ParseArgs({ e, bot, 10 }), 1, 2, teamOf) == nil)
end

-- The game step: the poll before the first callback hit, then the callback; transitions logged with the burst split.
do
	local C2, bot = world()
	local e = enemy(10, -1700, 100)
	e.dmg, e.spa = 60, 1.5
	C2.Tick(bot)
	check("the callback is installed on every hero's id once", cbs[1] ~= nil and cbs[10] ~= nil and #evs("dmgcb") == 1 and field(evs("dmgcb")[1], "kind") == "installed")
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
	cbs[10](bot, e, 55)
	C2.Tick(bot)
	c = evs("commit")
	-- The callback is now the source: its one hit at 301.5 alone is a poke (the poll's hit at 300.1 is not in its list), so no change.
	check("the first callback hit makes it the source and its lone hit is still poked: no line", #c == 2, c[#c])
	T = 302.8
	cbs[10](bot, e, 55)
	C2.Tick(bot)
	c = evs("commit")
	check("a second callback hit in another second: committed (why second, hits 2)",
		field(c[#c], "st") == "committed" and field(c[#c], "why") == "second" and field(c[#c], "hits") == "2" and field(c[#c], "src") == "cb", c[#c])
	local shape = evs("dmgcb")
	check("the first call's shape is logged with ok 1", #shape == 3 and field(shape[2], "kind") == "shape" and field(shape[2], "ok") == "1", shape[2])
	e.loc = Vector(-9000, -5000)
	T = 306.9
	C2.Tick(bot)
	c = evs("commit")
	check("out of reach with the hits lapsed: gone (why left)", field(c[#c], "st") == "gone" and field(c[#c], "why") == "left", c[#c])
end

-- The switch off: no install, no lines.
do
	local C3, bot = world(false)
	enemy(10, -1700, 100)
	C3.Tick(bot)
	check("Ours.PricedLeave off: no callback installed and no line", next(cbs) == nil and #evs("commit") == 0 and #evs("dmgcb") == 0)
end
finish()
