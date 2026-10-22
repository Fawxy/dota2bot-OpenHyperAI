dofile(HARNESS_DIR .. "/lane_world.lua")

local function ability(name, level, cd, ult, behavior)
	return {
		GetName = function() return name end, GetLevel = function() return level end,
		GetCooldownTimeRemaining = function() return cd end, IsUltimate = function() return ult end,
		GetBehavior = function() return behavior end,
	}
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, s) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return printed
end

local function world(debug)
	local H = LaneFresh({ Enable = true }, { debug = debug })
	CURRENT_TEAM = 2
	OBSERVER = nil
	local human = MakeUnit({ pid = 0, team = 2, bot = false, loc = Vector(0, 0) })
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, 0) })
	local near = MakeUnit({ pid = 6, team = 3, loc = Vector(300, 0) })
	local far = MakeUnit({ pid = 7, team = 3, loc = Vector(900, 0) })
	local fogged = MakeUnit({ pid = 8, team = 3, loc = Vector(100, 0) })
	return H, bot, near, far, fogged, human
end

do
	local H, bot, near, far, fogged = world(true)
	OBSERVER = bot
	fogged.hiddenFrom = { [bot] = true }
	near.abilities = {
		[0] = ability("sven_storm_bolt", 3, 4.5, false, 4),
		[1] = ability("sven_great_cleave", 2, 0, false, 16),
		[3] = ability("sven_gods_strength", 1, 60, true, 2),
	}
	near.estDamage = 275
	far.abilities = { [0] = ability("far_ability", 1, 0, false, 0) }
	local Probe = require("bots/FunLib/humaniser/lane_fight_probe")
	local lines = Probe.Run(bot)
	check("one line per existing ability plus the estimate", #lines == 4, #lines)
	check("slot 0 line", lines[1] == "hfight npc_dota_hero_6 slot=0 sven_storm_bolt lvl=3 cd=4.5 ult=false behavior=4", lines[1])
	check("slot 3 line keeps its slot index", lines[3] == "hfight npc_dota_hero_6 slot=3 sven_gods_strength lvl=1 cd=60 ult=true behavior=2", lines[3])
	check("estimate line", lines[4] == "hfight est=275", lines[4])
	check("nearest visible enemy chosen over a nearer hidden one and a farther one", not table.concat(lines, "\n"):find("far_ability", 1, true))
end

do
	local H, bot, near = world(true)
	OBSERVER = bot
	for _, e in ipairs(UNITS[3]) do e.hiddenFrom = { [bot] = true } end
	local Probe = require("bots/FunLib/humaniser/lane_fight_probe")
	local lines = Probe.Run(bot)
	check("no visible enemy gives a single explanatory line", #lines == 1 and lines[1]:find("no visible enemy", 1, true) ~= nil, lines[1])
end

do
	local H, bot, near, far, fogged = world(true)
	OBSERVER = bot
	fogged.hiddenFrom = { [bot] = true }
	local Probe = require("bots/FunLib/humaniser/lane_fight_probe")
	Probe.InstallCastLogger(2)
	Probe.InstallCastLogger(2)
	local count = 0
	for pid, list in pairs(CAST_CALLBACKS) do count = count + #list end
	check("one callback per enemy player id, installed once", count == 3 and #CAST_CALLBACKS[6] == 1 and #CAST_CALLBACKS[7] == 1 and #CAST_CALLBACKS[8] == 1, count)
	check("no callbacks for allies", CAST_CALLBACKS[0] == nil and CAST_CALLBACKS[1] == nil)
	local out = capture(function()
		CAST_CALLBACKS[6][1]({ ability = "storm_bolt", level = 3 })
		CAST_CALLBACKS[8][1]({ ability = "blink" })
	end)
	check("visible caster logged with sorted event keys", out[1] == "[H:fight] hfight cast pid=6 visible=true ability=storm_bolt level=3", out[1])
	check("fogged caster reports visible=false", out[2] == "[H:fight] hfight cast pid=8 visible=false ability=blink", out[2])
end

do
	local H, bot = world(false)
	local Probe = require("bots/FunLib/humaniser/lane_fight_probe")
	Probe.InstallCastLogger(2)
	check("debug off installs nothing", next(CAST_CALLBACKS) == nil)
end

do
	local function chat(debug)
		local H, bot, near, far, fogged = world(debug)
		OBSERVER = bot
		fogged.hiddenFrom = { [bot] = true }
		near.abilities = { [0] = ability("sven_storm_bolt", 3, 4.5, false, 4) }
		local out = capture(function()
			H.Tick(bot)
			for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = 0, string = "!hfight", team_only = false }) end
		end)
		local fight = {}
		for _, l in ipairs(out) do if l:find("[H:fight]", 1, true) then table.insert(fight, l) end end
		return fight
	end
	local on = chat(true)
	local joined = table.concat(on, "\n")
	check("!hfight from a human logs the probe lines", joined:find("hfight npc_dota_hero_6 slot=0 sven_storm_bolt", 1, true) ~= nil, joined)
	check("!hfight installs the cast logger for the enemy team", CAST_CALLBACKS[6] ~= nil)
	check("debug off: !hfight is silent", #chat(false) == 0)
end

finish()
