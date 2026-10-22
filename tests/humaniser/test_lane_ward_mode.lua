-- mode_ward_generic GetDesireHelper against a stubbed bot world (task 12, Task 7): the lane-ward pick and its fallback.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

BOT_MODE_NONE, BOT_MODE_RUNE, BOT_MODE_DEFEND_ALLY, BOT_MODE_WARD = 0, 7, 15, 18
BOT_MODE_DESIRE_NONE, BOT_MODE_DESIRE_VERYHIGH, BOT_MODE_DESIRE_ABSOLUTE = 0, 0.9, 1
function GetOpposingTeam() return 3 end
function GetAncient() return { GetLocation = function() return Vector(-7000, -7000) end } end
function IsHeroAlive() return false end
function GetHeroLastSeenInfo() return {} end
function RemapValClamped(v, a, b, c, d) return c + (d - c) * math.max(0, math.min(1, (v - a) / (b - a))) end

local BOT_AT = Vector(0, 0)
local CLOSE = { location = Vector(500, 0) }
local LANE_FAR = { location = Vector(4000, 0) }
local LANE_NEAR = { location = Vector(2000, 0) }

-- pick: what PickLaneWard returns. Returns the desire and the spots ConfirmLaneWard was called with.
local function run(pick)
	T = 200
	local confirmed = {}
	local bot = {
		loc = BOT_AT,
		IsInvulnerable = function() return false end,
		IsHero = function() return true end,
		IsIllusion = function() return false end,
		GetUnitName = function() return "npc_dota_hero_x" end,
		GetLocation = function(self) return self.loc end,
		GetItemInSlot = function(_, i) if i == 0 then return { GetName = function() return "item_ward_observer" end } end end,
		GetNearbyHeroes = function() return {} end,
		GetActiveMode = function() return BOT_MODE_NONE end,
		GetActiveModeDesire = function() return 0 end,
		WasRecentlyDamagedByAnyHero = function() return false end,
	}
	function GetBot() return bot end
	local J = setmetatable({
		GetPosition = function() return 5 end,
		GetHP = function() return 1 end,
		CanCastAbility = function(item) return item ~= nil end,
		Utils = { IsTeamPushingSecondTierOrHighGround = function() return false end, CountEnemyHeroesNear = function() return 0 end },
		Humaniser = {
			Intent = { Resolve = function(_, _, d) return d end },
			Transitions = {
				PickLaneWard = function() return pick end,
				ConfirmLaneWard = function(_, spot) table.insert(confirmed, spot) end,
			},
		},
	}, { __index = function() return function() return false end end })
	package.loaded["bots/FunLib/jmz_func"] = J
	package.loaded["bots/FunLib/aba_ward_utility"] = {
		GetAvailabeObserverWardSpots = function() return { CLOSE, LANE_NEAR, LANE_FAR } end,
		GetClosestObserverWardSpot = function() return CLOSE end,
	}
	package.loaded["bots/Customize/general"] = { Enable = false }
	dofile(HARNESS_DIR .. "/../../bots/mode_ward_generic.lua")
	return GetDesireHelper(), confirmed
end

do
	local d, confirmed = run(nil)
	check("no lane pick: the upstream closest spot is warded (control)", d == BOT_MODE_DESIRE_VERYHIGH, d)
	d, confirmed = run(LANE_NEAR)
	check("lane pick within 3200: warded and confirmed", d == BOT_MODE_DESIRE_VERYHIGH and confirmed[1] == LANE_NEAR, d)
	d, confirmed = run(LANE_FAR)
	check("lane pick rejected (4000 away): the upstream closest spot is still warded", d == BOT_MODE_DESIRE_VERYHIGH, d)
	local farConfirmed = false
	for _, spot in ipairs(confirmed) do if spot == LANE_FAR then farConfirmed = true end end
	check("... and the rejected lane pick is not confirmed", not farConfirmed)
end

finish()
