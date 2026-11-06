dofile(HARNESS_DIR .. "/dota_stubs.lua")

local WF = require("bots/FunLib/humaniser/world_facts")

local function unit(o) o.IsNull = nil return setmetatable(o, { __index = {
	IsNull = function(s) return s.removed == true end,
	GetAttackRange = function(s) return s.range end,
	GetBoundingRadius = function(s) return s.radius end,
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
	local u = unit({ name = "npc_dota_creep_lane", acq = 600 })
	check("acquisition live", WF.AcquisitionRange(u, 500, "lane_creep") == 600)
	local noacq = unit({ name = "npc_x" })
	check("acquisition missing falls back", WF.AcquisitionRange(noacq, 500, "neutral") == 500 and WF.Fallbacks().acquisition_neutral == 1)
end

finish()

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
