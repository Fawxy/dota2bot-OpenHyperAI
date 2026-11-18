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
	local a = P.Decide({ ally = 1, ours = { m(0, 600), m(1, 600) }, theirs = { m(5, 100), m(6, 600), m(7, 600) },
		dmg = { [0] = { [5] = 500 }, [1] = { [5] = 500 } } })
	check("outnumbered stays out whatever the shares", a.dec == "outnumbered")
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
	-- 2v2 with our hit ally retreating: it counts on neither side, so one of ours against two is outnumbered.
	local ret = m(1, 300)
	ret.ret = 1
	local a = P.Decide({ ally = 1, ours = { m(0, 600), ret }, theirs = { m(6, 600), m(7, 400) },
		dmg = { [0] = { [6] = 500, [7] = 500 }, [6] = { [0] = 10, [1] = 300 }, [7] = { [0] = 10, [1] = 300 } } })
	check("a retreating ally does not count on our side", a.dec == "outnumbered")
	-- 1v1 left (Decide alone; Gather hands it no such record): the retreating ally's low HP is not theirs to weigh.
	local b = P.Decide({ ally = 1, ours = { m(0, 600), ret }, theirs = { m(6, 600) },
		dmg = { [0] = { [6] = 300 }, [6] = { [0] = 100, [1] = 300 } } })
	check("theirs are weighed on ours still fighting", b.dec == "join" and math.abs(b.kt - 100 / 600) < 1e-9)
end

do
	-- Joins: the switch, the answer and its Keep, the target's range.
	local P = fresh()
	local Customize = require("bots.Customize.general")
	local bot = unit({ pid = 0, x = 0, y = 0, hp = 600, dmg = { [6] = 400 } })
	local ally = unit({ pid = 1, x = 500, y = 0, hp = 500, hit = true, dmg = { [6] = 100 } })
	local e = unit({ pid = 6, x = 900, y = 0, hp = 500, dmg = { [1] = 50 } })
	lists({ bot, ally }, { e })
	T = 100
	local t = P.Joins(bot)
	check("join answered: the bot joins on the pair's target", t ~= nil and t:GetPlayerID() == 6)
	lists({ bot, unit({ pid = 1, x = 500, y = 0, hp = 500 }) }, { e })
	T = 100.6
	check("the join holds for Keep with no situation", P.Joins(bot) ~= nil)
	T = 102.2
	check("past Keep it ends", P.Joins(bot) == nil)
	-- A losing answer ends it at once.
	lists({ bot, ally }, { e })
	T = 103
	check("join again", P.Joins(bot) ~= nil)
	local weak = unit({ pid = 1, x = 500, y = 0, hp = 40, hit = true, dmg = {} })
	local hard = unit({ pid = 6, x = 900, y = 0, hp = 500, dmg = { [1] = 300, [0] = 300 } })
	local soft = unit({ pid = 0, x = 0, y = 0, hp = 600, dmg = { [6] = 10 } })
	lists({ soft, weak }, { hard })
	T = 103.6
	check("a losing answer ends the join at once", P.Joins(soft) == nil)
	-- Off: logged only.
	lists({ bot, ally }, { e })
	T = 110
	Customize.Ours.PairJoin = false
	check("switch off: no join", P.Joins(bot) == nil)
	Customize.Ours.PairJoin = true
	-- A target past TargetRange of the bot is not walked to.
	local P2 = fresh()
	local farE = unit({ pid = 6, x = 1500, y = 0, hp = 500, dmg = { [1] = 50 } })
	lists({ bot, ally }, { farE })
	T = 120
	check("a target past TargetRange is not joined", P2.Joins(bot) == nil)
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

do
	-- Slice join-hits: no ally hit, an ally other than the bot with a fight of its own open on an enemy hero (CoreTrade's
	-- episode, read through SetReaders) makes an `ours` record on that hero.
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true, Cut = true } })
	local P = require("bots/FunLib/humaniser/pair_join")
	local Customize = require("bots.Customize.general")
	local lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local e6 = unit({ pid = 6, x = 700, y = 0, hp = 500, dmg = { [1] = 50, [0] = 50 } })
	local e7 = unit({ pid = 7, x = 900, y = 0, hp = 100, dmg = { [1] = 20, [0] = 20 } })
	local bot = unit({ pid = 0, x = 0, y = 0, hp = 600, dmg = { [6] = 300, [7] = 300 } })
	-- The opener's attack target is the softer hero 7: the record follows its episode, not its attack.
	local opener = unit({ pid = 1, x = 500, y = 0, hp = 500, att = e7, dmg = { [6] = 100, [7] = 100 } })
	local episodes = {}
	local function readers(refusal)
		P.SetReaders({ episodeOf = function(pid) return episodes[pid] end, refusal = function() return refusal end })
	end
	readers()
	lists({ bot, opener }, { e6, e7 })
	T = 600
	check("no episode open: an ally's attack alone makes no record", P.Gather(bot) == nil)
	episodes[1] = { kind = "trade", tpid = 6, target = e6, at = 597.5 }
	local rec = P.Gather(bot)
	check("an ally's open trade makes an ours record around it", rec ~= nil and rec.on == "ours" and rec.ally == 1 and rec.focus == 6)
	check("the record carries the episode's kind, its age and that the ally is not yet attacking the hero",
		rec ~= nil and rec.open.kind == "trade" and math.abs(rec.open.age - 2.5) < 1e-9 and rec.open.attacking == false)
	local a = rec and P.Decide(rec)
	check("our share and target are on the episode's hero, not the softer one", a ~= nil and a.tgt == 6 and math.abs(a.ko - 400 / 500) < 1e-9, a and a.tgt)
	for _, kind in ipairs({ "kill", "fight" }) do
		episodes[1] = { kind = kind, tpid = 6, target = e6, at = 599 }
		local r = P.Gather(bot)
		check("an ally's open " .. kind .. " is a trigger too", r ~= nil and r.focus == 6 and r.open.kind == kind)
	end
	-- Control: a partner's join would hold this bot's join up after the fight that drew both ended.
	episodes[1] = { kind = "join", tpid = 6, target = e6, at = 599 }
	check("a partner's join episode makes no record", P.Gather(bot) == nil)
	-- The bot's own episode makes no record for itself.
	episodes[1] = nil
	episodes[0] = { kind = "trade", tpid = 6, target = e6, at = 599 }
	check("the bot's own episode is not its trigger", P.Gather(bot) == nil)
	episodes[0] = nil
	-- An episode on a hero out of sight, or far from the opener (not in the weighing), makes none.
	local hidden = unit({ pid = 8, x = 700, y = 0, hp = 500 })
	function hidden:CanBeSeen() return false end
	episodes[1] = { kind = "trade", tpid = 8, target = hidden, at = 599 }
	lists({ bot, opener }, { e6, hidden })
	check("an episode on an unseen hero is no trigger", P.Gather(bot) == nil)
	local farFoe = unit({ pid = 9, x = 2500, y = 0, hp = 500 })
	episodes[1] = { kind = "trade", tpid = 9, target = farFoe, at = 599 }
	lists({ bot, opener }, { e6, farFoe })
	check("an episode on a hero outside the weighing is no trigger", P.Gather(bot) == nil)
	-- A hit ally still comes first: the old record, on=hit, no focus.
	episodes[1] = { kind = "trade", tpid = 6, target = e6, at = 597.5 }
	lists({ bot, opener, unit({ pid = 2, x = 300, y = 0, hp = 400, hit = true }) }, { e6, e7 })
	local h = P.Gather(bot)
	check("a hit ally is the record, on=hit", h ~= nil and h.on == "hit" and h.ally == 2 and h.focus == nil and h.open == nil)
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")
	RetreatState.SetRunning(opener, true)
	lists({ bot, opener }, { e6 })
	check("a retreating opener is no trigger", P.Gather(bot) == nil)
	RetreatState.SetRunning(opener, false)

	-- The cut: the episode's fields, and a fresh line the moment the ally starts attacking the hero.
	lists({ bot, opener }, { e6, e7 })
	local function cuts()
		local o = {}
		for _, l in ipairs(lines) do
			if l:find("ev=cut", 1, true) and l:find("kind=join", 1, true) then o[#o + 1] = l end
		end
		return o
	end
	Customize.Ours.JoinOnHit = false
	readers("burst")
	T = 620
	P.Tick(bot)
	local o = cuts()
	check("the ours cut names the episode, its age, the ally not attacking and the refusal",
		#o == 1 and o[1]:find("on=ours", 1, true) and o[1]:find("fo=6", 1, true) and o[1]:find("ek=trade", 1, true)
			and o[1]:find("oa=22.5", 1, true) and o[1]:find("aa=0", 1, true) and o[1]:find("free=burst", 1, true), o[1])
	function opener:GetAttackTarget() return e6 end
	T = 620.6
	P.Tick(bot)
	o = cuts()
	check("the ally's first attack on the hero is cut at once, inside CutEvery", #o == 2 and o[2]:find("aa=1", 1, true) ~= nil, o[2])
	function opener:GetAttackTarget() return e7 end

	-- Joins: off, the ours record is logged only; on, it joins on the episode's hero; a hero in a play is left to it.
	readers()
	Customize.Ours.JoinOnHit = false
	T = 630
	check("switch off: an ours record draws no join", P.Joins(bot) == nil)
	Customize.Ours.JoinOnHit = true
	local Plays = require("bots/FunLib/humaniser/plays/plays")
	local of = Plays.Of
	Plays.Of = function(u) return u == bot and {} or nil end
	T = 640
	check("switch on: a hero in a play is not drawn out of it", P.Joins(bot) == nil)
	Plays.Of = of
	-- FightRefusal holds a join we start, as it holds a fight we start: the same world joins below once it clears.
	readers("tower")
	T = 645
	check("switch on: a hero the lane fight's refusal holds does not join", P.Joins(bot) == nil)
	readers()
	T = 650
	local t = P.Joins(bot)
	check("switch on: the bot joins on the hero its ally's fight is on", t ~= nil and t:GetPlayerID() == 6)
	Customize.Ours.JoinOnHit = false
end

finish()
