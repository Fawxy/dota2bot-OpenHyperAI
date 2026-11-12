dofile(HARNESS_DIR .. "/lane_world.lua")
-- Rework step 7 (Ours.ArbiterDrive): the arbiter's pick holds every owned laner. Ownership from the first laning read to an
-- end event; the gate's tiers (ours, borrowed, admitted, denied) per mode; the complete-items TP denied.
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local DENIED = { "roam", "defend_tower_bot", "defend_tower_mid", "defend_tower_top", "push_tower_bot", "push_tower_mid",
	"push_tower_top", "roshan", "outpost", "secret_shop", "side_shop" }

local function world(drive)
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true }, retreat = true })
	package.loaded["bots/FunLib/custom_loader"].Ours.ArbiterDrive = drive
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000), level = 3 })
	bot.lane, bot.pos, bot.mode = Lane.Bot, 1, BotMode.Laning
	return H, bot
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	local arb = {}
	for _, l in ipairs(printed) do if l:find("ev=arb ", 1, true) then arb[#arb + 1] = l end end
	return arb
end

-- OHA's desire stand-in: returns `v` and records the call.
local function gated(H, bot, mode, v)
	local called = false
	local out = H.Chooser.Gate(bot, mode, function() called = true return v or 0.5 end)()
	return out, called
end

-- Ownership: from the first laning read, kept through a stale read, ended by the clock and never taken again.
do
	local H, bot = world(true)
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	local arb = capture(function()
		check("drive: the first laning read owns the hero", Arb.Owned(bot) == true)
		T = T + 5
		check("drive: no read for 5 s, still owned (no stale blank)", Arb.Owned(bot) == true and Phase.LaningTransitionsSeen(bot) ~= false)
		LANING = false
		T = T + 1
		check("drive: the clock exit ends ownership", Arb.Owned(bot) == false)
		LANING = nil
		T = T + 1
		check("drive: once ended the hero is not owned again", Arb.Owned(bot) == false)
	end)
	check("own and end logged on ev=arb", #arb == 2 and arb[1]:find("ph=own", 1, true) and arb[2]:find("ph=end", 1, true)
		and arb[2]:find("why=clock", 1, true), table.concat(arb, "\n"))
end

-- Switch off: ownership is the stored laning read, as the shadow had it.
do
	local H, bot = world(false)
	local Arb = require("bots/FunLib/humaniser/arbiter")
	check("drive off: a hero whose laning read nobody made is not owned", Arb.Owned(bot) == false)
	local v, called = gated(H, bot, "roam")
	check("drive off: roam runs OHA's code", v == 0.5 and called)
	check("drive off: the complete-items TP is OHA's", Arb.DeniesItemsTp(bot) == false)
end

-- The tiers with the lane as the pick.
do
	local H, bot = world(true)
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local Trade = require("bots/FunLib/humaniser/states/core_trade")
	local Fight = require("bots/FunLib/humaniser/lane_fight")
	local trading = false
	Trade.Running = function() return trading end
	Fight.CurrentPhase = function() return "idle" end
	capture(function()
		check("lane pick", Arb.Drive(bot, nil).name == "lane")
		for _, m in ipairs(DENIED) do
			local v, called = gated(H, bot, m)
			check("lane pick, " .. m .. " denied: 0, OHA's code not run", v == 0 and not called, tostring(v))
		end
		local v, called = gated(H, bot, "laning", 0.2)
		check("lane pick, laning is the host at the lane desire", v == Arb.SETTINGS.LaneDesire and called, tostring(v))
		v = gated(H, bot, "laning", 0.9)
		check("lane pick, laning's own last-hit desire stands above the lane desire", v == 0.9, tostring(v))
		for _, m in ipairs({ "ward", "rune", "retreat", "assemble", "assemble_with_humans" }) do
			v, called = gated(H, bot, m)
			check("lane pick, " .. m .. " runs its own desire", v == 0.5 and called, tostring(v))
		end
		v, called = gated(H, bot, "farm")
		check("lane pick, OHA's farm denied when no job starts", v == 0, tostring(v))
		v, called = gated(H, bot, "attack")
		check("lane pick, borrowed attack asked but held at 0 while no trade runs", v == 0 and called, tostring(v))
		trading = true
		v = gated(H, bot, "attack")
		check("lane pick, borrowed attack keeps its desire once its GetDesire opened a trade", v == 0.5, tostring(v))
		v, called = gated(H, bot, "team_roam")
		check("lane pick, team roam held at 0 with no fight", v == 0 and called, tostring(v))
		Fight.CurrentPhase = function() return "commit" end
		v = gated(H, bot, "team_roam")
		check("team roam keeps its desire while our fight commits", v == 0.5, tostring(v))
		check("the complete-items TP is denied for an owned hero", Arb.DeniesItemsTp(bot) == true)
	end)
end

-- Interrupt picks: the retreat keeps only itself and the human interface; a trade hosts attack; a last hit under way
-- holds the fight modes and the admitted modes off.
do
	local H, bot = world(true)
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")
	local Trade = require("bots/FunLib/humaniser/states/core_trade")
	local Fight = require("bots/FunLib/humaniser/lane_fight")
	Fight.CurrentPhase = function() return "idle" end
	Trade.Running = function() return false end
	capture(function()
		Arb.Owned(bot)
		RetreatState.SetRunning(bot, true)
		local v, called = gated(H, bot, "laning")
		check("retreat pick: laning 0", v == 0 and not called, tostring(v))
		v = gated(H, bot, "attack")
		check("retreat pick: attack 0", v == 0, tostring(v))
		v, called = gated(H, bot, "retreat")
		check("retreat pick: retreat runs", v == 0.5 and called, tostring(v))
		v = gated(H, bot, "assemble")
		check("retreat pick: assemble runs", v == 0.5, tostring(v))
		RetreatState.SetRunning(bot, false)
		T = T + 0.1
		Trade.Running = function() return true end
		check("trade pick hosted in attack", Arb.Drive(bot, nil).name == "trade")
		v = gated(H, bot, "attack")
		check("trade pick: attack is the host", v == 0.5, tostring(v))
		v, called = gated(H, bot, "laning", 0.9)
		check("trade pick: laning keeps its own last-hit desire (H2: a trade yields to a last hit)", v == 0.9 and called, tostring(v))
		v = gated(H, bot, "ward")
		check("trade pick: the admitted ward waits", v == 0, tostring(v))
	end)
	local p = { name = "lane", group = 3, host = "laning", applies = true }
	local farm = function() return nil end
	check("last hit under way: attack asked, so a running trade or kill is not ended by the lift", Arb.DriveDecide(bot, "attack", p, farm) == nil)
	check("last hit under way: team roam 0", Arb.DriveDecide(bot, "team_roam", p, farm) == 0)
	check("last hit under way: rune 0", Arb.DriveDecide(bot, "rune", p, farm) == 0)
	check("last hit under way: laning runs", Arb.DriveDecide(bot, "laning", p, farm) == nil)
	local job = { name = "job", group = 6, host = "farm", applies = true }
	check("job pick: farm is the chooser's host desire", Arb.DriveDecide(bot, "farm", job, function() return 0.92 end) == 0.92)
	check("job pick: ward waits", Arb.DriveDecide(bot, "ward", job, farm) == 0)
	check("job pick: borrowed attack may still open a trade", Arb.DriveDecide(bot, "attack", job, farm) == nil)
	local rune = { name = "job", group = 6, host = "rune", applies = true }
	check("job hosted in rune: rune runs, farm 0", Arb.DriveDecide(bot, "rune", rune, farm) == nil
		and Arb.DriveDecide(bot, "farm", rune, function() return 0.92 end) == 0)
end
-- A drill's lane-only hero is not driven: its laning holds it (only the thing under test acts).
do
	local H, bot = world(true)
	local Arb = require("bots/FunLib/humaniser/arbiter")
	local Overrides = require("bots/FunLib/humaniser/overrides")
	Overrides.LaneOnly = function() return true end
	check("drive: a lane-only drill hero is not owned", Arb.Owned(bot) == false and not Arb.Drives(bot))
end
finish()
