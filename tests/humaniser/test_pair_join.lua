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
end

do
	local P = fresh()
	-- 2v2 with our hit ally retreating: it counts on neither side, so one of ours against two is outnumbered.
	local ret = m(1, 300)
	ret.ret = 1
	local a = P.Decide({ ally = 1, ours = { m(0, 600), ret }, theirs = { m(6, 600), m(7, 400) },
		dmg = { [0] = { [6] = 500, [7] = 500 }, [6] = { [0] = 10, [1] = 300 }, [7] = { [0] = 10, [1] = 300 } } })
	check("a retreating ally does not count on our side", a.dec == "outnumbered")
	-- 1v1 left: the retreating ally's low HP is not theirs to weigh.
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

finish()
