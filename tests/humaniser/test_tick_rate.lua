-- Humaniser.Tick runs every step on each TickEvery-th frame and only the frame steps on the frames between.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local UnitType = dota.UnitType

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetLastHits() return self.lh or 0 end
function UnitMeta:GetDenies() return self.dn or 0 end
function UnitMeta:GetAttackTarget() return self.target end
function UnitMeta:GetLastAttackTime() return -1 end
function UnitMeta:GetGold() return 600 end
function UnitMeta:GetNetWorth() return 1200 end
function UnitMeta:GetXPNeededToLevel() return 200 end

local CREEPS = {}
function GetUnitList(kind) return kind == UnitType.EnemyCreeps and CREEPS or {} end
function GetTower() return nil end
function GetBarracks() return nil end

local function count(lines, name)
	local n = 0
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) then n = n + 1 end end
	return n
end

ResetWorld()
CURRENT_TEAM = 2
local H = FreshHumaniser({ Enable = false, TickEvery = 3, Telemetry = { Enable = true } })
H.LaneConfig.SetHelpers({ GetPosition = function(u) return u.pos end })
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
core.pos = 1

local function frame(t)
	T = t
	H.Tick(core)
end

-- The third frame is the first to run every step. A creep that walks in on the second and is dead by the third is
-- never seen alive by a tracker that samples only with the other steps.
frame(60.000)
CREEPS = {
	{
		GetUnitName = function() return "npc_dota_creep_badguys_melee" end,
		GetLocation = function() return Vector(120, 0) end,
		GetHealth = function() return 20 end,
		GetMaxHealth = function() return 100 end,
		IsAlive = function() return true end,
		IsAncientCreep = function() return false end,
	},
}
frame(60.033)
check("no snapshot on the frames between", count(lines, "snap") == 0, count(lines, "snap"))
CREEPS = {}
core.lh = 1
frame(60.067)
check("a creep seen alive only between two full ticks is logged when it dies", count(lines, "creep_death") == 1, count(lines, "creep_death"))
check("the full tick takes the snapshot", count(lines, "snap") == 1, count(lines, "snap"))
finish()
