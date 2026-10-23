dofile(HARNESS_DIR .. "/lane_world.lua")
-- Smoke: every state scorer (laning, pull, stack, rotate, farm, gank), the layer's selection and the rune/roam bodies
-- run for ten bots on both teams, every position owned, from the pre-horn to 15:00 (farm-hosted bodies need farm's
-- Think and are covered by their own tests). Catches nil errors in scorers for positions and phases the per-state
-- tests do not visit; a scorer error is logged by the SDK ("score <name> error: ...") and counted here.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode
local BUNDLE = "bots/FunLib/sdk/tasks/tasks"

package.loaded[BUNDLE] = nil
local all = { 1, 2, 3, 4, 5 }
local H = LaneFresh({ Enable = true }, { skill = 0.7, debug = true, telemetry = { Enable = true }, transitions = { Enable = true },
	states = { Enable = true, Shadow = true, Teams = "all", ShadowTeams = "all",
		Own = { laning = all, stack = all, pull = all, rotate = all, farm = all, gank = all }, Rotate = { Power = true } } })
T = -60
CURRENT_TEAM = 2
OBSERVER = 1
local lanes = { [1] = Lane.Bot, [2] = Lane.Mid, [3] = Lane.Top, [4] = Lane.Top, [5] = Lane.Bot }
local bots = {}
for team = 2, 3 do
	for pos = 1, 5 do
		local pid = (team - 2) * 5 + pos - 1
		local lane = lanes[pos]
		if team == 3 then lane = (lane == Lane.Bot and Lane.Top) or (lane == Lane.Top and Lane.Bot) or lane end
		local u = MakeUnit({ pid = pid, team = team, loc = Vector((team == 2 and -1 or 1) * 1500, LANE_Y[lane]), level = 1, mode = BotMode.Laning })
		u.lane, u.pos, u.mana, u.maxmana = lane, pos, 100, 100
		u.ActionImmediate_Ping = function() end
		table.insert(bots, u)
	end
end
for _, u in ipairs(bots) do H.Lane.Config.SkillOf(u) end

local errors, lines = {}, {}
local old = print
print = function(s)
	s = tostring(s)
	if s:find("ev=lua_error", 1, true) or s:find("error:", 1, true) then table.insert(errors, s) end
	if s:find(" ev=state ", 1, true) then table.insert(lines, s) end
end
local ok, err = pcall(function()
	while T < 900 do
		for _, u in ipairs(bots) do
			CURRENT_TEAM = u.team
			u.level = math.min(25, 1 + math.floor(math.max(T, 0) / 45))
			H.States.Tick(u)
			H.Tasks.Tick(u)
			local t = H.Tasks.Current(u)
			if t ~= nil then u.mode = t.name == "state:gank" and BotMode.Roam or t.name == "state:rotate" and BotMode.Rune or BotMode.Laning end
			if u.mode ~= BotMode.Laning then H.States.Step(u, u.mode) end
		end
		T = T + 1
	end
end)
print = old
check("smoke: no exception through 15:00", ok, err)
check("smoke: no scorer or hook errors", #errors == 0, errors[1])
check("smoke: states were selected", #lines > 0)
finish()
