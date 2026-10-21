dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")

local function bot()
	return MakeUnit({ pid = 2, team = 2, bot = true, loc = Vector(0, 0) })
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = true } })
	check("positive control: active by default", H.Transitions.IsActive())
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = false } })
	local b = bot()
	T = 100
	H.Transitions.Tick(b)
	check("disabled: no unit scans", next(GETUNITLIST_CALLS) == nil)
	local why = H.Intent.Explain(b, dota.BotMode.Laning)
	check("disabled: no claims posted", why:find("valve", 1, true) ~= nil, why)
	check("disabled: sub-flags report off", not H.Transitions.Settings.IsOn("Rotation"))
	H = LaneFresh({ Enable = true }, { enable = false })
	check("humaniser off also deactivates", not H.Transitions.IsActive())
end

do
	local H = LaneFresh({ Enable = true }, { transitions = { Rotation = false } })
	local S = H.Transitions.Settings
	check("flag off", not S.IsOn("Rotation"))
	check("other flags keep defaults", S.IsOn("MidRunes") and S.IsOn("LostLane"))
	check("untouched values keep defaults", near(S.Get().Refresh, 0.5) and near(S.Get().RotateChance.Low, 0.3))
	H = LaneFresh({ Enable = true }, { transitions = { RotateChance = { High = 1.0 } } })
	S = H.Transitions.Settings
	check("partial lerp pair merges", near(S.Get().RotateChance.High, 1.0) and near(S.Get().RotateChance.Low, 0.3))
end

do
	local S = LaneFresh({ Enable = true }).Transitions.Settings
	local pair = { Low = 0.3, High = 0.9 }
	check("lerp interpolates", near(S.Lerp(pair, 0.5), 0.6))
	check("lerp clamps skill", near(S.Lerp(pair, 2), 0.9) and near(S.Lerp(pair, -1), 0.3))
	check("falling pair interpolates", near(S.Lerp(S.Get().ArriveSigma, 1), 1))
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.5 })
	local b = bot()
	T = 100
	LANING = true
	local line = H.Transitions.Overlay(b)
	check("overlay format", line:match("^phase: laning busy=%a+ spare=%a+ alone=%a+ rot=%-$") ~= nil, line)
	LANING = false
	check("overlay phase after laning", H.Transitions.Overlay(b):find("^phase: post ") ~= nil)
	H.Transitions.SetOverlayProviders({ Busy = function() return true end, Rotation = function() return "top" end })
	line = H.Transitions.Overlay(b)
	check("overlay reads providers", line:find("busy=true", 1, true) ~= nil and line:find("rot=top", 1, true) ~= nil, line)
end

finish()
