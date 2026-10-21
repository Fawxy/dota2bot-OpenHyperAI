dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, Barracks = dota.Lane, dota.Barracks

-- The engine as console.9055745679 showed it: GetLaneFrontAmount answers in the calling script's frame (0 = own base)
-- whichever team is asked. GetAmountAlongLane is run both caller-relative (what the tower amounts showed) and
-- absolute (lane_world's assumption); eqPos must come out the same either way. T1s sit at absolute 0.3 / 0.7
-- (lane_world's absolute GetLocationAlongLane places them; lane_state never calls it).
local MIN_X, SPAN, BOT_Y = -7000, 14000, -5000
local FRONT = {}
local BARRACKS = {}

local function engine(amountCallerRelative)
	local function toCaller(abs) return CURRENT_TEAM == 2 and abs or 1 - abs end
	function GetAmountAlongLane(l, v)
		local abs = math.max(0, math.min(1, (v.x - MIN_X) / SPAN))
		return { amount = amountCallerRelative and toCaller(abs) or abs, distance = math.abs(v.y - LANE_Y[l]) }
	end
	function GetLaneFrontAmount(team, lane) return toCaller(FRONT[team]) end
	function GetLaneFrontLocation(team, lane, d) return Vector(MIN_X + SPAN * FRONT[team], LANE_Y[lane]) end
	function GetBarracks(team, id)
		if id ~= Barracks.BotMelee or BARRACKS[team] == nil then return nil end
		return { GetLocation = function() return Vector(MIN_X + SPAN * BARRACKS[team], BOT_Y) end }
	end
end

local function snapshot(team, ourAbs, theirAbs, t)
	local H = LaneFresh({ Enable = true })
	T = t or 100
	CURRENT_TEAM = team
	FRONT[team], FRONT[team == 2 and 3 or 2] = ourAbs, theirAbs
	return H.Lane.LaneState.Get(team, Lane.Bot), H.Lane.LaneState
end

for _, callerRelative in ipairs({ true, false }) do
	engine(callerRelative)
	local tag = callerRelative and " (caller-relative amounts)" or " (absolute amounts)"

	check("radiant: wave meeting at our T1 is eq -1" .. tag, near(snapshot(2, 0.3, 0.3).eqPos, -1), snapshot(2, 0.3, 0.3).eqPos)
	check("radiant: wave meeting at their T1 is eq 1" .. tag, near(snapshot(2, 0.7, 0.7).eqPos, 1), snapshot(2, 0.7, 0.7).eqPos)
	check("radiant: meet a quarter in from our T1 is eq -0.5" .. tag, near(snapshot(2, 0.4, 0.4).eqPos, -0.5), snapshot(2, 0.4, 0.4).eqPos)
	check("dire: wave meeting at our T1 is eq -1" .. tag, near(snapshot(3, 0.7, 0.7).eqPos, -1), snapshot(3, 0.7, 0.7).eqPos)
	check("dire: wave meeting at their T1 is eq 1" .. tag, near(snapshot(3, 0.3, 0.3).eqPos, 1), snapshot(3, 0.3, 0.3).eqPos)
	check("dire: meet a quarter in from our T1 is eq -0.5" .. tag, near(snapshot(3, 0.6, 0.6).eqPos, -0.5), snapshot(3, 0.6, 0.6).eqPos)

	-- No enemy wave in lane: their front reads their base, so our front alone is the meet.
	check("radiant: enemy wave absent, eq follows our wave" .. tag, near(snapshot(2, 0.6, 1).eqPos, 0.5), snapshot(2, 0.6, 1).eqPos)
	check("dire: our wave absent, eq follows theirs" .. tag, near(snapshot(3, 1, 0.65).eqPos, -0.75), snapshot(3, 1, 0.65).eqPos)

	BARRACKS[2], BARRACKS[3] = 0.1, 0.8
	local rad, S = snapshot(2, 0.5, 0.5, 40)
	check("radiant: expected meet between barracks, nearer their T1" .. tag,
		rad.expectedMeetAmount ~= nil and near(S.EqPos(rad.expectedMeetAmount, rad.ourTowerAmount, rad.theirTowerAmount), -0.25), rad.expectedMeetAmount)
	local dire = snapshot(3, 0.5, 0.5, 40)
	check("dire: same expected meet seen from dire" .. tag,
		dire.expectedMeetAmount ~= nil and near(S.EqPos(dire.expectedMeetAmount, dire.ourTowerAmount, dire.theirTowerAmount), 0.25), dire.expectedMeetAmount)
	check("expected meet only for the first waves" .. tag, snapshot(2, 0.5, 0.5, 95).expectedMeetAmount == nil and snapshot(2, 0.5, 0.5, -10).expectedMeetAmount == nil)
	BARRACKS[2], BARRACKS[3] = nil, nil
	check("no barracks, no expected meet" .. tag, snapshot(2, 0.5, 0.5, 40).expectedMeetAmount == nil)
end

finish()
