dofile(HARNESS_DIR .. "/dota_stubs.lua")

local WF = require("bots/FunLib/humaniser/world_facts")

local function unit(o) o.IsNull = nil return setmetatable(o, { __index = {
	IsNull = function(s) return s.removed == true end,
	GetAttackRange = function(s) return s.range end,
	GetBoundingRadius = function(s) return s.radius end,
	CanBeSeen = function(s) return s.seen ~= false end,
	GetBaseMovementSpeed = function(s) return s.speed end,
	GetAcquisitionRange = function(s) return s.acq end,
	GetUnitName = function(s) return s.name end,
	GetTeam = function(s) return s.team or 2 end,
	GetNearbyLaneCreeps = function(s, r, enemy) s.laneReads = (s.laneReads or 0) + 1 return enemy and s.enemyCreeps or s.myCreeps or {} end,
	GetNearbyNeutralCreeps = function(s) s.neutralReads = (s.neutralReads or 0) + 1 return s.neutrals or {} end,
} }) end

do
	WF.Reset()
	local tower = unit({ range = 700, radius = 144 })
	check("tower reach is range plus radius", WF.TowerReach(tower, 850) == 844)
	tower.range = 999
	check("tower reach is read once per tower", WF.TowerReach(tower, 850) == 844 and WF.ReadCount.tower_reach == 1)
	local bad = unit({ range = 0, radius = 100 })
	check("a failed read falls back", WF.TowerReach(bad, 850) == 850)
	check("the fallback is counted", WF.Fallbacks().tower_reach == 1)
end

do
	WF.Reset()
	T = 100
	local creep = unit({ speed = 330, team = 3 })
	local a = unit({ team = 2, enemyCreeps = { creep } })
	local b = unit({ team = 2, enemyCreeps = { creep } })
	check("lane creep speed live", WF.LaneCreepSpeed(a, 3, 325) == 330)
	check("second bot in the same second shares the read", WF.LaneCreepSpeed(b, 3, 325) == 330 and WF.ReadCount.lane_creep_speed == 1 and (b.laneReads or 0) == 0)
	T = 101
	WF.LaneCreepSpeed(b, 3, 325)
	check("a new second reads again", WF.ReadCount.lane_creep_speed == 2)
	T = 102
	local c = unit({ team = 2, enemyCreeps = {} })
	check("no creep in view keeps the last live value", WF.LaneCreepSpeed(c, 3, 325) == 330 and WF.Fallbacks().lane_creep_speed == nil)
end

do
	WF.Reset()
	T = 5
	local c = unit({ team = 2 })
	check("no creep ever seen falls back", WF.NeutralSpeed(c, 300) == 300 and WF.Fallbacks().neutral_speed == 1)
	T = 6
	c.neutrals = { unit({ speed = 295 }) }
	check("neutral speed live", WF.NeutralSpeed(c, 300) == 295)
	T = 7
	c.neutrals = { unit({ speed = 0 }), unit({ speed = 290 }) }
	check("an idle camp creep reading 0 is skipped, the next one is read", WF.NeutralSpeed(c, 300) == 290)
	T = 8
	c.neutrals = { unit({ speed = 0 }) }
	check("only zero readings: the last live value stands, not 0", WF.NeutralSpeed(c, 300) == 290)
	local u = unit({ name = "npc_dota_creep_goodguys_melee", acq = 600 })
	check("acquisition live", WF.AcquisitionRange(u, 500, "lane_creep") == 600 and WF.Latest("acquisition_lane_creep", 500) == 600)
	local ranged = unit({ name = "npc_dota_creep_badguys_ranged", acq = 800 })
	check("a ranged creep reads its own range and leaves the remembered melee value", WF.AcquisitionRange(ranged, 500, "lane_creep") == 800 and WF.Latest("acquisition_lane_creep", 500) == 600)
	WF.Reset()
	check("a type never sighted falls back, counted once", WF.NeutralSpeedFor("large", 300) == 300 and WF.NeutralSpeedFor("large", 300) == 300 and WF.Fallbacks().neutral_speed_large == 1)
	check("the feeder is due once a second", WF.FeedDue() == true and WF.FeedDue() == false)
	WF.FeedNeutral("large", { unit({ speed = 350 }), unit({ speed = 310 }), unit({ speed = 0 }) })
	check("a camp type's speed is the mean of its creeps, zeros skipped", WF.NeutralSpeedFor("large", 300) == 330)
	check("another type keeps its own fallback", WF.NeutralSpeedFor("small", 290) == 290)
	WF.FeedNeutral("large", { unit({ speed = 0 }) })
	check("only zero readings leave the last value", WF.NeutralSpeedFor("large", 300) == 330)
	do
		local camps = require("bots/FunLib/humaniser/camps")
		local savedSp, savedList = GetNeutralSpawners, GetUnitList
		GetNeutralSpawners = function()
			return {
				[1] = { team = 2, type = "large", location = Vector(0, 0, 0), min = Vector(-150, -150, 0), max = Vector(150, 150, 0) },
				[2] = { team = 3, type = "large", location = Vector(5000, 0, 0), min = Vector(4850, -150, 0), max = Vector(5150, 150, 0) },
			}
		end
		camps.ResetCache()
		local function at(x, speed) local u = unit({ speed = speed }); u.GetLocation = function() return Vector(x, 0, 0) end; return u end
		local ghost = unit({ speed = 300 }); ghost.GetLocation = function() return nil end
		GetUnitList = function() return { ghost, at(10, 270), at(-20, 270), at(5010, 295), at(2500, 999) } end
		WF.Reset(); T = 50
		local seer = unit({ team = 2 })
		check("a neutral with no location is skipped, not a crash", pcall(camps.FeedNeutralSpeeds, seer))
		check("each camp keeps its own speed", WF.NeutralSpeedFor("large", 300, 1) == 270 and WF.NeutralSpeedFor("large", 300, 2) == 295)
		check("a neutral between camps (beyond the range) is ignored", WF.NeutralSpeedFor("large", 300) ~= 999)
		check("a camp never seen uses its type's last sighting", WF.NeutralSpeedFor("large", 300, 7) == 295)
		GetNeutralSpawners, GetUnitList = savedSp, savedList
		camps.ResetCache()
	end
	local noacq = unit({ name = "npc_x" })
	check("acquisition missing falls back", WF.AcquisitionRange(noacq, 500, "neutral") == 500 and WF.Fallbacks().acquisition_neutral == 1)
end


do
	WF.Reset()
	local tw = unit({ range = 700, radius = 144 })
	local saved = GetTower
	GetTower = function() return tw end
	check("game reach is range plus radius", WF.Reach(850) == 844)
	check("game attack range is the range alone", WF.TowerAttackRange(700) == 700)
	tw.range = 999
	check("both are read once per game", WF.Reach(850) == 844 and WF.TowerAttackRange(700) == 700)
	WF.Reset()
	GetTower = function() return nil end
	check("no tower answers: the constants", WF.Reach(850) == 850 and WF.TowerAttackRange(700) == 700)
	GetTower = saved
end

do
	-- Latest: the last live value for code with no unit in hand; the constant (counted once) before any read.
	WF.Reset()
	check("Latest before any read is the constant", WF.Latest("lane_creep_speed", 325) == 325 and WF.Latest("lane_creep_speed", 325) == 325 and WF.Fallbacks().lane_creep_speed == 1)
	T = 100
	local a = unit({ team = 2, enemyCreeps = { unit({ speed = 330, team = 3 }) } })
	WF.LaneCreepSpeed(a, 3, 325)
	check("Latest after a read is the live value", WF.Latest("lane_creep_speed", 325) == 330)
end

do
	-- lctl6 smoke (log 2026-11-06T19-10-35-lctl6_A_on_1, team 3 world_fact tower_range live=200): the Dire VM read Radiant's
	-- fogged top T1. The own team's tower is read first, and a tower the team cannot see is skipped.
	WF.Reset()
	local rad = unit({ range = 200, radius = 0, seen = false })
	local dire = unit({ range = 700, radius = 144 })
	local saved, savedTeam = GetTower, GetTeam
	GetTower = function(team) return team == TEAM_RADIANT and rad or dire end
	GetTeam = function() return TEAM_DIRE end
	check("Dire reads its own tower's range", WF.TowerAttackRange(700) == 700)
	check("Dire reads its own tower's reach", WF.Reach(850) == 844)
	WF.Reset()
	GetTower = function(team) return team == TEAM_RADIANT and rad or nil end
	check("only a fogged tower: the constants", WF.TowerAttackRange(700) == 700 and WF.Reach(850) == 850)
	GetTower, GetTeam = saved, savedTeam
	WF.Reset()
end

do
	-- Review M1 (lctl6, lctl7: lane_creep_speed logged twice a team): only facts the probe has no row for are listed.
	WF.Reset()
	WF.Latest("lane_creep_speed", 325)
	WF.Fallback("attack_point", 0.4)
	WF.Fallback("attack_point", 0.4)
	local list = WF.UnprobedFallbacks()
	check("unprobed fallbacks: the caller's own fact only", #list == 1 and list[1].fact == "attack_point" and list[1].n == 2 and list[1].value == 0.4)
	WF.Reset()
end

do
	WF.Reset()
	local saved = GetTeamMember
	GetTeamMember = function(i) if i == 2 then return unit({ radius = 24 }) end return nil end
	check("hero radius is the first hero's bounding radius", WF.HeroRadius(30) == 24)
	GetTeamMember = function() return unit({ radius = 99 }) end
	check("hero radius is read once per game", WF.HeroRadius(30) == 24)
	WF.Reset()
	GetTeamMember = function() return nil end
	check("no hero answers: the constant, counted", WF.HeroRadius(30) == 30 and WF.Fallbacks().hero_radius == 1)
	GetTeamMember = saved
end

finish()
