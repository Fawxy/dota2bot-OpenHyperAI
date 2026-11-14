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
end

finish()
