dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

-- The engine as console.9055745679 showed it: GetLaneFrontAmount answers in the calling script's frame (0 = own base)
-- whichever team is asked. GetAmountAlongLane is run both caller-relative (what the tower amounts showed) and
-- absolute (lane_world's assumption); eqPos must come out the same either way. T1s sit at absolute 0.3 / 0.7
-- (lane_world's absolute GetLocationAlongLane places them; lane_state never calls it).
local MIN_X, SPAN = -7000, 14000
local FRONT = {}

local function engine(amountCallerRelative)
	local function toCaller(abs) return CURRENT_TEAM == 2 and abs or 1 - abs end
	function GetAmountAlongLane(l, v)
		local abs = math.max(0, math.min(1, (v.x - MIN_X) / SPAN))
		return { amount = amountCallerRelative and toCaller(abs) or abs, distance = math.abs(v.y - LANE_Y[l]) }
	end
	function GetLaneFrontAmount(team, lane) return toCaller(FRONT[team]) end
	function GetLaneFrontLocation(team, lane, d) return Vector(MIN_X + SPAN * FRONT[team], LANE_Y[lane]) end
end

local function snapshot(team, ourAbs, theirAbs)
	local H = LaneFresh({ Enable = true })
	T = 100
	CURRENT_TEAM = team
	FRONT[team], FRONT[team == 2 and 3 or 2] = ourAbs, theirAbs
	return H.Lane.LaneState.Get(team, Lane.Bot)
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
end

finish()
