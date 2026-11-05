dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- The rearmost clash (states/lane_spot RearClash, slice core-in-lane). awchk2 game 1
-- (logs/2026-11-05T21-36-13-awchk2_A_on_1.log, t=231.567, pid 1, Radiant Pudge pos3 top): the wave hold ended `met` and the
-- spot went `walk spot=wave why=pref` to our far front (-5300, 5480), 3,301 away, leaving 3 Dire creeps under our T1. Unit
-- positions are the replay's at 231.6 (pulltruth); our front is ev=front team=2 at 231.
FreshHumaniser({})
local LaneSpot = require("bots/FunLib/humaniser/states/lane_spot")
local LanePush = require("bots/FunLib/humaniser/lane_push")

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local U = {}
U.__index = U
function U:IsNull() return false end
function U:IsAlive() return true end
function U:GetLocation() return self.loc end
function U:GetUnitName() return self.name end
function U:GetTeam() return self.team end
function U:GetHealth() return self.hp end
function U:GetMaxHealth() return self.maxhp or self.hp end
function U:GetAttackTarget() return self.target end
function U:GetAttackRange() return self.range or 100 end
function U:GetBoundingRadius() return 24 end
function U:GetCurrentMovementSpeed() return 300 end
function U:GetAssignedLane() return 1 end
function U:GetPlayerID() return 1 end

local T1 = Vector(-6336, 1856)
local FAR = Vector(-5200, 5483)
local world

local function unit(o) return setmetatable(o, U) end
local function near(self, list, r)
	local out = {}
	for _, u in ipairs(list) do if dist(u.loc, self.loc) <= r then out[#out + 1] = u end end
	return out
end
function U:GetNearbyLaneCreeps(r, enemies) return near(self, enemies and world.theirs or world.ours, r) end
function U:GetNearbyTowers(r, enemies) return enemies and {} or near(self, world.towers, r) end
function U:GetNearbyHeroes() return {} end

function GetUnitList(kind)
	if kind == UNIT_LIST_ENEMY_CREEPS or kind == 9 then return world.theirs end
	if kind == UNIT_LIST_ALLIED_CREEPS or kind == 3 then return world.ours end
	return {}
end
local path = LanePush.PathOf(1)
local frontS = LanePush.Project(path, FAR.x, FAR.y)
function GetLaneFrontLocation(team, lane, delta)
	-- Radiant's front moves up the path, so behind it is a smaller path distance.
	local p = LanePush.PointAt(path, frontS + delta)
	return Vector(p[1], p[2])
end

local function awchk2(withTheirs)
	world = { ours = {}, theirs = {}, towers = {} }
	local function ours(x, y) local c = unit({ loc = Vector(x, y), team = 2, hp = 550, name = "npc_dota_creep_goodguys_melee" }) world.ours[#world.ours + 1] = c return c end
	-- Our new wave at our T1, and the old one that walked past theirs to (-5300, 4900)-(-5000, 5000).
	local mine = { ours(-6419, 2294), ours(-6465, 2439), ours(-6513, 2307), ours(-6487, 2006) }
	for _, p in ipairs({ { -5260, 4923 }, { -5170, 4916 }, { -6068, 5035 }, { -6003, 5088 }, { -5119, 4969 }, { -5025, 4993 } }) do ours(p[1], p[2]) end
	if withTheirs then
		for i, p in ipairs({ { -6485, 2515 }, { -6450, 2668 }, { -6423, 2579 } }) do
			world.theirs[#world.theirs + 1] = unit({ loc = Vector(p[1], p[2]), team = 3, hp = 550, name = "npc_dota_creep_badguys_melee", target = mine[i] })
		end
	end
	world.towers[1] = unit({ loc = T1, team = 2, hp = 1800, range = 700 })
	return unit({ loc = Vector(-6473, 2395), team = 2, hp = 92, maxhp = 100, range = 150 })
end

do
	local bot = awchk2(true)
	local info = LaneSpot.Compute(bot, "core")
	check("awchk2 3:51: the spot stays at the clash under our T1, not our far front", info ~= nil and dist(info.spot, T1) < 1000 and dist(info.spot, FAR) > 2500,
		info and string.format("%.0f,%.0f", info.spot.x, info.spot.y))
	check("awchk2 3:51: the clash is logged with our far front", info ~= nil and info.clash ~= nil and info.clash < 800 and info.far ~= nil and info.far > 3000,
		info and tostring(info.clash) .. " " .. tostring(info.far))
	local sup = LaneSpot.Compute(bot, "support")
	check("awchk2 3:51: a support keeps the front anchor (cores only)", sup ~= nil and sup.clash == nil and dist(sup.spot, FAR) < 600, sup and string.format("%.0f,%.0f", sup.spot.x, sup.spot.y))

	bot = awchk2(false)
	info = LaneSpot.Compute(bot, "core")
	check("their creeps gone: the far front again", info ~= nil and info.clash == nil and dist(info.spot, FAR) < 300, info and string.format("%.0f,%.0f", info.spot.x, info.spot.y))
end

-- RearClash on lane distances from our T1.
do
	check("rear clash: their creeps within 1,000 of our front are the spot's usual read", LaneSpot.RearClash({ 1500, 1600 }, { 1450 }, 1500) == nil)
	check("rear clash: our creep fighting their rearmost, on our side", LaneSpot.RearClash({ 820, 660, 740 }, { 600, 450, 3600 }, 3600) == 600)
	check("rear clash: none of ours near, their rearmost creep", LaneSpot.RearClash({ 820, 660 }, { 3600, -100 }, 3600) == 660)
	check("rear clash: creeps past our T1's range behind it do not count", LaneSpot.RearClash({ -900 }, {}, 3600) == nil)
end

finish()
