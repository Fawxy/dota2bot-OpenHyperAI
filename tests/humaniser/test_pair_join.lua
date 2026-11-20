-- PairJoin (D10 in shadow): Decide's weighing and Gather's situation.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function fresh()
	ResetWorld()
	FreshHumaniser({ Enable = true })
	return require("bots/FunLib/humaniser/pair_join")
end

local function m(pid, hp) return { pid = pid, x = 0, y = 0, hp = hp, mhp = 600 } end

do
	local P = fresh()
	-- 2v2: ours deal 300 to hero 7 (HP 400, share 0.75); theirs deal 200 to our weakest (HP 300, 0.67): join on 7.
	local a = P.Decide({ ally = 1, ours = { m(0, 500), m(1, 300) }, theirs = { m(6, 600), m(7, 400) },
		dmg = { [0] = { [6] = 150, [7] = 150 }, [1] = { [6] = 150, [7] = 150 }, [6] = { [0] = 100, [1] = 100 }, [7] = { [0] = 100, [1] = 100 } } })
	check("join when our best share beats theirs", a.dec == "join" and a.tgt == 7)
	check("our share is damage over the target's HP", math.abs(a.ko - 0.75) < 1e-9)
	check("theirs is on our weakest", math.abs(a.kt - 200 / 300) < 1e-9)
end

do
	local P = fresh()
	-- Same damage, our hit ally at 150 HP: theirs 200 / 150 = 1.33 beats ours 0.75.
	local a = P.Decide({ ally = 1, ours = { m(0, 500), m(1, 150) }, theirs = { m(6, 600), m(7, 400) },
		dmg = { [0] = { [6] = 150, [7] = 150 }, [1] = { [6] = 150, [7] = 150 }, [6] = { [0] = 100, [1] = 100 }, [7] = { [0] = 100, [1] = 100 } } })
	check("losing when their share is the larger", a.dec == "losing" and a.tgt == 7)
end

do
	local P = fresh()
	-- Two of ours against three: the head count is no part of the rule, the kill shares are.
	local a = P.Decide({ ally = 1, ours = { m(0, 600), m(1, 600) }, theirs = { m(5, 100), m(6, 600), m(7, 600) },
		dmg = { [0] = { [5] = 500 }, [1] = { [5] = 500 } } })
	check("fewer of ours than theirs joins when our share on the weak hero is the larger", a.dec == "join" and a.tgt == 5)
end

do
	local P = fresh()
	local a = P.Decide({ ally = 1, ours = { m(0, 600), m(1, 600) }, theirs = { m(6, 600) }, dmg = {} })
	check("no damage either way is not a join", a.dec == "losing" and a.ko == 0 and a.kt == 0)
end

-- Gather: GetUnitList answers from two lists; a unit is { pid, x, y, hp, mhp, hit, dmg = {pid = d} }.
local function unit(o)
	local u = {}
	function u:IsNull() return false end
	function u:IsAlive() return true end
	function u:IsIllusion() return false end
	function u:CanBeSeen() return true end
	function u:GetLocation() return Vector(o.x, o.y) end
	function u:GetPlayerID() return o.pid end
	function u:GetHealth() return o.hp end
	function u:GetMaxHealth() return o.mhp or 600 end
	function u:WasRecentlyDamagedByAnyHero() return o.hit == true end
	function u:GetEstimatedDamageToTarget(_, t) return (o.dmg or {})[t:GetPlayerID()] or 0 end
	function u:IsHero() return true end
	function u:GetTeam() return o.pid < 5 and 2 or 3 end
	function u:GetAttackTarget() return o.att end
	function u:GetAttackRange() return o.range or 600 end
	function u:GetBoundingRadius() return 24 end
	function u:GetCurrentMovementSpeed() return o.ms or 300 end
	return u
end

local function lists(allies, enemies)
	GetUnitList = function(kind)
		if kind == require("bots/ts_libs/dota/index").UnitType.AlliedHeroes then return allies end
		if kind == require("bots/ts_libs/dota/index").UnitType.EnemyHeroes then return enemies end
		return {}
	end
end

do
	local P = fresh()
	local bot = unit({ pid = 0, x = 0, y = 0, hp = 600, dmg = { [6] = 90 } })
	local ally = unit({ pid = 1, x = 500, y = 0, hp = 300, hit = true, dmg = { [6] = 60 } })
	local far = unit({ pid = 2, x = 5000, y = 0, hp = 100, hit = true })
	local e = unit({ pid = 6, x = 900, y = 0, hp = 500, dmg = { [1] = 120 } })
	local away = unit({ pid = 7, x = 3000, y = 0, hp = 500 })
	lists({ bot, ally, far }, { e, away })
	local rec = P.Gather(bot)
	check("the hit ally in range is the situation's ally", rec ~= nil and rec.ally == 1)
	check("ours are the heroes near the ally", rec ~= nil and #rec.ours == 2)
	check("theirs are the heroes near the ally", rec ~= nil and #rec.theirs == 1 and rec.theirs[1].pid == 6)
	check("the damage reads both ways", rec ~= nil and rec.dmg[0][6] == 90 and rec.dmg[6][1] == 120)
	lists({ bot, unit({ pid = 1, x = 500, y = 0, hp = 300 }) }, { e })
	check("no hit ally, no situation", P.Gather(bot) == nil)
	lists({ bot, ally }, { away })
	check("no enemy near the ally, no situation", P.Gather(bot) == nil)
	-- The bot itself hit, its partner near: the bot is the hit ally (it holds and joins too).
	local hitBot = unit({ pid = 0, x = 0, y = 0, hp = 200, hit = true, dmg = { [6] = 90 } })
	lists({ hitBot, unit({ pid = 1, x = 500, y = 0, hp = 600 }) }, { e })
	local own = P.Gather(hitBot)
	check("the bot hit with a partner near is its own situation", own ~= nil and own.ally == 0 and #own.ours == 2)
	lists({ hitBot, far }, { e })
	check("a hit hero with nobody of ours near is no pair", P.Gather(hitBot) == nil)
	-- Its only partner retreating: a hero alone, no pair (review of pair-join-on).
	local leaving = unit({ pid = 1, x = 500, y = 0, hp = 600 })
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")
	RetreatState.SetRunning(leaving, true)
	lists({ hitBot, leaving }, { e })
	check("a hit hero whose only partner retreats is no pair", P.Gather(hitBot) == nil)
	RetreatState.SetRunning(leaving, false)
end

do
	local P = fresh()
	-- Our hit ally retreating counts on neither side: theirs are weighed on the hero still fighting, not on the weak ally.
	local ret = m(1, 300)
	ret.ret = 1
	local a = P.Decide({ ally = 1, ours = { m(0, 600), ret }, theirs = { m(6, 600), m(7, 400) },
		dmg = { [0] = { [6] = 500, [7] = 500 }, [6] = { [0] = 10, [1] = 300 }, [7] = { [0] = 10, [1] = 300 } } })
	check("a retreating ally does not count on our side", a.dec == "join" and a.tgt == 7 and math.abs(a.kt - 20 / 600) < 1e-9, a.kt)
	-- 1v1 left (Decide alone; Gather hands it no such record): the retreating ally's low HP is not theirs to weigh.
	local b = P.Decide({ ally = 1, ours = { m(0, 600), ret }, theirs = { m(6, 600) },
		dmg = { [0] = { [6] = 300 }, [6] = { [0] = 100, [1] = 300 } } })
	check("theirs are weighed on ours still fighting", b.dec == "join" and math.abs(b.kt - 100 / 600) < 1e-9)
end

do
	-- Slice join-after: after a fight ends, the weighing around the bot once a second for AfterWindow s, no hit needed.
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
	local P = require("bots/FunLib/humaniser/pair_join")
	local lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local function after() local o = {} for _, l in ipairs(lines) do if l:find("ev=join_after", 1, true) then table.insert(o, l) end end return o end
	local bot = unit({ pid = 0, x = 0, y = 0, hp = 600, dmg = { [6] = 300 } })
	local partner = unit({ pid = 1, x = 500, y = 0, hp = 600, dmg = { [6] = 100 } })
	local e = unit({ pid = 6, x = 400, y = 0, hp = 300, dmg = { [0] = 60 } })
	lists({ bot, partner }, { e })
	T = 200
	P.After(bot, "join", "pair_end", 6)
	for i = 0, 80 do T = 200 + i * 0.1 P.Tick(bot) end
	local o = after()
	check("one line at the window's end", #o == 1, #o)
	local l = o[1] or ""
	check("the line names the ended window", l:find("kind=join", 1, true) and l:find("why=pair_end", 1, true) and l:find("tgt=6", 1, true) and l:find("res=full", 1, true))
	local s = l:match(" s=(%S+)") or ""
	local n = select(2, s:gsub(";", ";")) + 1
	check("a sample a second over the window", n == 8 or n == 9, n)
	check("no hit needed: the pair's answer is join, with both shares", s:find("^0:j:1.333:0.1:0.5:400:1:2:1") ~= nil, s)
	-- A new window that opens ends the watch `reopen`; a fight kind with no watch logs nothing.
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	T = 300
	P.After(bot, "trade", "losing", 6)
	P.Tick(bot)
	P.Reopened(bot)
	o = after()
	check("an opened window ends the watch reopen", #o == 1 and o[1]:find("res=reopen", 1, true) ~= nil, o[1])
	P.After(bot, "kill", "time", 6)
	for i = 0, 90 do T = 310 + i * 0.1 P.Tick(bot) end
	check("a kill window is not watched", #after() == 1)
	-- Unseen enemies: answer `n`; the target unseen reads -1.
	lists({ bot, partner }, {})
	T = 400
	P.After(bot, "join", "target_lost", 6)
	P.Tick(bot)
	T = 409.5
	P.Tick(bot)
	o = after()
	local last = o[#o] or ""
	check("a watch the bot was not ticked through ends dead", last:find("res=dead", 1, true) ~= nil, last)
	check("no enemy seen: n, target -1", (last:match(" s=(%S+)") or ""):find("^0:n:0:0:%-1:%-1:1:2:0") ~= nil, last)
	-- A respawn inside the window (not ticked while dead, back after 5 s): the missed samples end it dead, not full.
	T = 500
	P.After(bot, "join", "pair_end", 6)
	P.Tick(bot)
	T = 505
	P.Tick(bot)
	o = after()
	check("a respawn inside the window ends dead", (o[#o] or ""):find("res=dead", 1, true) ~= nil, o[#o])
	-- Past the laning stage: the watch ends `stage`.
	T = 719.5
	P.After(bot, "trade", "deny", 6)
	P.Tick(bot)
	T = 720.5
	P.Tick(bot)
	o = after()
	check("past the laning stage it ends stage", (o[#o] or ""):find("res=stage", 1, true) ~= nil, o[#o])
end

-- Ours.JoinArrive: a hero's damage counts for the share of Window left after its walk into its own range of the target.
do
	local P = fresh()
	-- A hero at x with reach 648 (range 624 + hull 24), speed 300, hull 24.
	local function h(pid, hp, x, reach)
		local t = { pid = pid, x = x, y = 0, hp = hp, mhp = 600 }
		if reach ~= false then t.rc, t.ms, t.hull = 648, 300, 24 end
		return t
	end
	-- Hero 6 (HP 400) at x = 500 hits each of ours for 200 of 600 HP (0.33). Hero 0 does 100 to it alone (0.25), hero 1 adds 200.
	local dmg = { [0] = { [6] = 100 }, [1] = { [6] = 200 }, [6] = { [0] = 200, [1] = 200 } }
	local function rec(partnerX, arrive, reach)
		return { ally = 0, ours = { h(0, 600, 0, reach), h(1, 600, partnerX, reach) }, theirs = { h(6, 400, 500, reach) }, dmg = dmg, arrive = arrive }
	end
	local near = P.Decide(rec(0, true))
	check("a partner in range counts whole: join", near.dec == "join" and math.abs(near.ko - 0.75) < 1e-9, near.ko)
	-- 1572 from the target: 900 outside its reach, 3 s of walking: nothing left of the window.
	local far = P.Decide(rec(-1072, true))
	check("a partner 3 s of walking from its range adds nothing: losing", far.dec == "losing" and math.abs(far.ko - 0.25) < 1e-9, far.ko)
	local off = P.Decide(rec(-1072, false))
	check("the same far partner counts whole with the rule off: join", off.dec == "join" and math.abs(off.ko - 0.75) < 1e-9, off.ko)
	-- Control: 60 outside its reach is 0.2 s of walking, 0.933 of the window.
	local step = P.Decide(rec(-232, true))
	check("a partner one step out of range still counts nearly whole: join", step.dec == "join" and math.abs(step.ko - (100 + 200 * (1 - 0.2 / 3)) / 400) < 1e-9, step.ko)
	-- No reach carried (an old cut): the rule has nothing to scale by.
	local old = P.Decide(rec(-1072, true, false))
	check("members with no reach count whole on or off", old.dec == "join" and math.abs(old.ko - 0.75) < 1e-9 and old.ko == P.Decide(rec(-1072, false, false)).ko, old.ko)

	-- Their side: hero 0 at 300 HP is hit by 6 for 100 and by 7 for 200; ours do 150 each to hero 6 (0.5).
	local dmg2 = { [0] = { [6] = 150, [7] = 0 }, [1] = { [6] = 150, [7] = 0 }, [6] = { [0] = 100, [1] = 0 }, [7] = { [0] = 200, [1] = 0 } }
	local function rec2(x7, arrive)
		return { ally = 0, ours = { h(0, 300, 0), h(1, 600, 0) }, theirs = { h(6, 600, 500), h(7, 600, x7) }, dmg = dmg2, arrive = arrive }
	end
	local both = P.Decide(rec2(500, true))
	check("an enemy in range adds its damage: losing", both.dec == "losing" and math.abs(both.kt - 1) < 1e-9, both.kt)
	local away = P.Decide(rec2(2500, true))
	check("an enemy far outside its range adds less: join", away.dec == "join" and math.abs(away.kt - 1 / 3) < 1e-9, away.kt)
	check("the far enemy counts whole with the rule off: losing", P.Decide(rec2(2500, false)).dec == "losing")
end

do
	-- Gather records reach on both sides and the switch; the cut logs them and replays to the same answer.
	local H
	ResetWorld()
	H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true, Cut = true } })
	local P = require("bots/FunLib/humaniser/pair_join")
	local lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local bot = unit({ pid = 0, x = 0, y = 0, hp = 600, hit = true, dmg = { [6] = 90 } })
	local partner = unit({ pid = 1, x = 500, y = 0, hp = 600, range = 150, ms = 325, dmg = { [6] = 60 } })
	local e = unit({ pid = 6, x = 900, y = 0, hp = 500, range = 550, ms = 290, dmg = { [0] = 120 } })
	lists({ bot, partner }, { e })
	T = 100
	P.Tick(bot)
	local cut = lines[1] or ""
	check("the cut logs each member's reach, both sides", cut:find(" jar=0,624,300,24;1,174,325,24;6,574,290,24", 1, true) ~= nil, cut)
	check("the cut says the rule was on", cut:find(" jav=1", 1, true) ~= nil, cut)
	local rec = P.Gather(bot)
	check("the record carries the flag and the partner's reach", rec ~= nil and rec.arrive == true and rec.ours[2].rc == 174 and rec.ours[2].ms == 325)
	package.loaded["bots/FunLib/custom_loader"].Ours = { JoinArrive = false }
	local off = P.Gather(bot)
	check("with the switch off the record has no flag", off ~= nil and off.arrive == nil)
	lines = {}
	T = 110
	P.Tick(bot)
	check("with the switch off the cut has no jav", (lines[1] or ""):find(" jav=", 1, true) == nil and (lines[1] or ""):find(" jar=", 1, true) ~= nil, lines[1])
	package.loaded["bots/FunLib/custom_loader"].Ours = {}
end

finish()
