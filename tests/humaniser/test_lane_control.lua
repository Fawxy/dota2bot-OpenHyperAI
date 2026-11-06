-- Slice lane-control 2a (lane controller design s5.1-s5.3): the lever choice (fewest, then least dangerous levers that bring
-- the clash into the band without overshoot; a pull and a shove never together), the wave intent, the support's next
-- departure (the calendar stub) and the switch.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
TEAM_RADIANT, TEAM_DIRE = 2, 3
LANE_TOP, LANE_MID, LANE_BOT = 1, 2, 3
FreshHumaniser({ Enable = false })
local Customize = package.loaded["bots/FunLib/custom_loader"]
local Ctl = require("bots/FunLib/humaniser/lane_control")

local function names(c)
	local out = {}
	for _, l in ipairs(c.levers) do out[#out + 1] = l.name end
	return table.concat(out, "+")
end
local function lv(name, effect, danger, why) return { name = name, effect = effect, danger = danger, who = "x", why = why } end

-- Choose: need is the clash past the target (positive: bring it back), band 150.
do
	local levers = { lv("predeny", -300, 1), lv("feed", -300, 2), lv("pull", -900, 3), lv("shove", 300, 2, "mode") }
	check("inside the band: no lever", names(Ctl.Choose(100, 150, levers)) == "")
	check("small need: the least dangerous lever", names(Ctl.Choose(350, 150, levers)) == "predeny")
	-- 700: predeny+feed leaves 100 (two levers); the pull alone leaves -200, past -150: overshoot, so the two small ones.
	check("no overshoot: two small levers beat a pull that passes the target", names(Ctl.Choose(700, 150, levers)) == "predeny+feed")
	-- 1000: the pull alone leaves 100, one lever.
	check("big need: the pull alone", names(Ctl.Choose(1000, 150, levers)) == "pull")
	local c = Ctl.Choose(3000, 150, levers)
	check("too big: the nearest set without overshoot, marked short", c.short and names(c) == "predeny+feed+pull")
	check("too big: what is left", c.left == 3000 - 1500)
	check("an unusable lever is never chosen", names(Ctl.Choose(1000, 150, { lv("pull", -900, 3, "no_sup"), lv("predeny", -300, 1) })) == "predeny")
	-- forward: shove only, and never with a pull.
	local fwd = { lv("shove", 300, 2), lv("pull", 900, 3) }
	check("forward: the shove", names(Ctl.Choose(-400, 150, fwd)) == "shove")
	check("pull and shove never together", names(Ctl.Choose(-1300, 150, { lv("shove", 300, 2), lv("pull", 900, 3), lv("x", 100, 1) })) ~= "shove+pull")
	check("no lever: short, need left", Ctl.Choose(500, 150, {}).short and Ctl.Choose(500, 150, {}).left == 500)
end

-- IntentOf.
do
	check("intent back", Ctl.IntentOf(200, 150, false) == "back")
	check("intent forward", Ctl.IntentOf(-200, 150, false) == "forward")
	check("intent hold", Ctl.IntentOf(100, 150, false) == "hold")
	check("reset before a departure", Ctl.IntentOf(0, 150, true) == "reset")
	check("reset: a lane well short of the target is let go", Ctl.IntentOf(-400, 150, true) == "forward")
end

-- NextDeparture: pos 4 leaves for the 6:00 power rune at 335 (DepartLead 25) and for the 5:52 stack at 327.
do
	check("pos 4 at 5:00: the stack slot first", Ctl.NextDeparture(4, 300) == 27)
	check("pos 5 at 5:30: the power rune", Ctl.NextDeparture(5, 330) == 5)
	check("pos 4 after 7:52 trips: none", Ctl.NextDeparture(4, 7 * 60 + 52) == nil)
	check("a core has no departures", Ctl.NextDeparture(1, 300) == nil)
end

-- The switch: off, Tick reads nothing (no LanePush call on a stub bot with no lane path).
do
	Customize.Ours = Customize.Ours or {}
	Customize.Ours.LaneControl = false
	local called = false
	local bot = { GetTeam = function() called = true return TEAM_RADIANT end }
	Ctl.Tick(bot)
	check("switch off: the bot is not read", not called)
	Customize.Ours.LaneControl = nil
end

finish()
