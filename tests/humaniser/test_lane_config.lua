dofile(HARNESS_DIR .. "/lane_world.lua")

do
	local C = LaneFresh({ Enable = true }).LaneConfig
	check("sigma at 0", near(C.Curve("JitterSigma", 0), 1.5))
	check("sigma at 1 is none", near(C.Curve("JitterSigma", 1), 0))
	check("sigma at 0.5", near(C.Curve("JitterSigma", 0.5), 0.75))
	check("attempt midpoint", near(C.Curve("AttemptRate", 0.5), 0.575))
	check("path noise at 0", near(C.Curve("PathNoise", 0), 150))
	check("clamped above 1", near(C.Curve("AttemptRate", 1.7), 1))
	check("clamped below 0", near(C.Curve("AttemptRate", -1), 0.15))
end


do
	local C = LaneFresh({ Enable = true }).LaneConfig
	SetRandomSequence({ 0.5, 0.25 })
	check("zero z gives zero jitter", math.abs(C.Jitter(0)) < 1e-3)
	SetRandomSequence({ math.exp(-2), 1.0 })
	check("no jitter at skill 1", math.abs(C.Jitter(1)) < 1e-9)
	SetRandomSequence({ math.exp(-2), 1.0 })
	local j0 = C.Jitter(0)
	check("jitter scales with sigma", math.abs(j0 - 3.0) < 1e-3, j0)
	SetRandomSequence({ 0.2 })
	check("roll below chance", C.Roll(0.3))
	SetRandomSequence({ 0.4 })
	check("roll above chance", not C.Roll(0.3))
end

-- WO-022: Roll and Gauss draw from the injected Skill source; RandomFloat only without one (tasks off).
do
	local C = LaneFresh({ Enable = true }).LaneConfig
	local skill = { random = function() return 0.9 end, gauss = function() return 1.25 end }
	C.SetRng(function() return skill end)
	SetRandomSequence({ 0.1 })
	check("roll uses the Skill source", not C.Roll(0.5))
	check("gauss uses the Skill source", C.Gauss() == 1.25)
	C.SetRng(function() return nil end)
	SetRandomSequence({ 0.1 })
	check("roll falls back while tasks are off", C.Roll(0.5))
	C.SetRng(nil)
	SetRandomSequence({ 0.1 })
	check("roll falls back with no source", C.Roll(0.5))
end

do
	local H = LaneFresh({ Enable = true })
	local C = H.LaneConfig
	local u = MakeUnit({ pid = 1, team = 2 })
	u.pos = 4
	check("position via helper", C.PositionOf(u) == 4)
	C.SetHelpers({})
	check("position missing helper", C.PositionOf(u) == nil)
	T = 500
	check("laning fallback early", C.InLaningPhase())
	T = 700
	check("laning fallback late", not C.InLaningPhase())
end

do
	LaneFresh({ Enable = true })
	local dota = require("bots/ts_libs/dota/index")
	local r, d = GetTower(2, dota.Tower.Mid1), GetTower(3, dota.Tower.Mid1)
	check("radiant mid T1 at 0.3", r ~= nil and near(GetAmountAlongLane(dota.Lane.Mid, r.loc).amount, 0.3))
	check("dire top T1 at 0.7", GetTower(3, dota.Tower.Top1) ~= nil
		and near(GetAmountAlongLane(dota.Lane.Top, GetTower(3, dota.Tower.Top1):GetLocation()).amount, 0.7))
	check("bot T1 exists per team", GetTower(2, dota.Tower.Bot1) ~= nil and d ~= nil)
	check("no T2 stub", GetTower(2, dota.Tower.Mid2) == nil)
end

finish()
