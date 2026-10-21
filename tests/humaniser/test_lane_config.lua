dofile(HARNESS_DIR .. "/lane_world.lua")

local function bounds(tech, below, at)
	local H = LaneFresh({ Enable = true })
	local C = H.Lane.Config
	check(tech .. " unknown below gate", not C.Knows(tech, below))
	check(tech .. " known at gate", C.Knows(tech, at))
end
bounds("block", 0.29, 0.3)
bounds("full_pull", 0.29, 0.3)
bounds("half_pull", 0.59, 0.6)
bounds("stack_pull", 0.74, 0.75)
bounds("aggro_pull", 0.49, 0.5)
bounds("freeze", 0.69, 0.7)
bounds("shove", 0.39, 0.4)
do
	local C = LaneFresh({ Enable = true }).Lane.Config
	check("stack has no gate", C.Knows("stack", 0))
end

do
	local C = LaneFresh({ HalfPull = false }).Lane.Config
	check("flag off hides half_pull", not C.Knows("half_pull", 1.0))
	check("other techniques unaffected", C.Knows("full_pull", 1.0))
end

do
	local C = LaneFresh({ Enable = true }).Lane.Config
	check("positive control: block known by default", C.Knows("block", 1.0))
	C = LaneFresh({ Enable = false }).Lane.Config
	for _, t in ipairs({ "block", "full_pull", "half_pull", "stack_pull", "aggro_pull", "freeze", "shove", "stack" }) do
		check("lane disabled hides " .. t, not C.Knows(t, 1.0))
	end
	check("lane disabled hides flags", not C.IsOn("Stack"))
	C = LaneFresh({ Enable = true }, { enable = false }).Lane.Config
	check("humaniser disabled hides block", not C.Knows("block", 1.0))
	check("humaniser disabled hides flags", not C.IsOn("Stack"))
end

do
	local off = { Enable = true }
	for _, f in ipairs({ "Plan", "Block", "FullPull", "HalfPull", "StackPull", "AggroPull", "Freeze", "Shove", "Stack",
		"Harass", "Mid", "CounterPlay", "CampBlock" }) do off[f] = false end
	off.Telegraph = true
	check("telegraph alone is not active", not LaneFresh(off).Lane.Config.IsActive())
	off.Stack = true
	check("a consumer flag activates", LaneFresh(off).Lane.Config.IsActive())
end

do
	local H = LaneFresh({ Enable = true })
	local Hooks, bot = H.Lane.Hooks, MakeUnit({ pid = 1, team = 2 })
	check("no rotation probe", not Hooks.IsRotationPlanned(bot))
	Hooks.SetRotationProbe(function() return false end)
	check("false probe stays false", not Hooks.IsRotationPlanned(bot))
	Hooks.SetRotationProbe(function() return true end)
	check("any true probe wins", Hooks.IsRotationPlanned(bot))
	check("no stacked probe", not Hooks.IsStacked(3))
	Hooks.SetStackedProbe(function(i) return i == 3 end)
	check("stacked probe true for 3", Hooks.IsStacked(3))
	check("stacked probe false for 4", not Hooks.IsStacked(4))
	check("no override by default", Hooks.TechniqueOverride(bot) == nil)
	Hooks.SetTechniqueOverride(function() return "shove" end)
	check("override returned", Hooks.TechniqueOverride(bot) == "shove")
	Hooks.ResetHooks()
	check("reset clears probes", not Hooks.IsRotationPlanned(bot) and not Hooks.IsStacked(3))
end

do
	local C = LaneFresh({ Enable = true }).Lane.Config
	check("sigma at 0", near(C.Curve("JitterSigma", 0), 1.5))
	check("sigma at 1", near(C.Curve("JitterSigma", 1), 0.2))
	check("sigma at 0.5", near(C.Curve("JitterSigma", 0.5), 0.85))
	check("attempt midpoint", near(C.Curve("AttemptRate", 0.5), 0.5))
	check("path noise at 0", near(C.Curve("PathNoise", 0), 150))
	check("clamped above 1", near(C.Curve("AttemptRate", 1.7), 0.85))
	check("clamped below 0", near(C.Curve("AttemptRate", -1), 0.15))
end

do
	local C = LaneFresh({ Gates = { Freeze = 0.9 }, Curves = { AttemptRate = { 0.5, 0.6 } } }).Lane.Config
	check("override gate", near(C.GateFor("freeze"), 0.9))
	check("sibling gate kept", near(C.GateFor("block"), 0.3))
	check("freeze unknown at 0.8 after override", not C.Knows("freeze", 0.8))
	check("curve array replaced whole", near(C.Curve("AttemptRate", 1), 0.6))
	check("other curve kept", near(C.Curve("JitterSigma", 0), 1.5))
end

do
	for _, m in ipairs({ "all", "allies", "off" }) do
		check("mode " .. m, LaneFresh({ OwnLaningThink = m }).Lane.Config.OwnLaningMode() == m)
	end
	check("bogus mode is off", LaneFresh({ OwnLaningThink = "bogus" }).Lane.Config.OwnLaningMode() == "off")
end

do
	local C = LaneFresh({ Enable = true }).Lane.Config
	SetRandomSequence({ 0.5, 0.25 })
	check("zero z gives zero jitter", math.abs(C.Jitter(0)) < 1e-3)
	SetRandomSequence({ math.exp(-2), 1.0 })
	check("jitter at high skill", math.abs(C.Jitter(1) - 0.4) < 1e-3)
	SetRandomSequence({ math.exp(-2), 1.0 })
	local j0 = C.Jitter(0)
	check("jitter scales with sigma", math.abs(j0 - 3.0) < 1e-3, j0)
	SetRandomSequence({ 0.2 })
	check("roll below chance", C.Roll(0.3))
	SetRandomSequence({ 0.4 })
	check("roll above chance", not C.Roll(0.3))
end

do
	local H = LaneFresh({ Enable = true })
	local C = H.Lane.Config
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
