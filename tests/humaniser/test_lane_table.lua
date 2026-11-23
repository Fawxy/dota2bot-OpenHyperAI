-- The lane table (states/lane_table): the one ordered list of what a hero does on a laning frame, with a rank per position, and the
-- one walker. Since the lane-body cut (23/11/2026) its rows are sustain's walk and the host's own steps.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true, Cut = true } })
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)

local world = {}
package.loaded["bots/FunLib/humaniser/overrides"] = { LaneOnly = function() return world.laneOnly == true end }
package.loaded["bots/FunLib/humaniser/lane_config"] = { PositionOf = function(u) return u.pos end }
package.loaded["bots/FunLib/humaniser/sustain_act"] = {
	Walking = function() return world.sustainWalk == true end,
	Step = function() world.sustainSteps = (world.sustainSteps or 0) + 1 return world.sustainActs ~= false end,
}
package.loaded["bots/FunLib/humaniser/states/lane_table"] = nil
local LaneTable = require("bots/FunLib/humaniser/states/lane_table")

local function names(rows)
	local out = {}
	for _, r in ipairs(rows) do table.insert(out, r.name) end
	return table.concat(out, ",")
end

-- A ctx whose host steps act as `o` says (position always acts). o.log collects the name of every host step in the order it ran.
local function ctx(o)
	local function host(name, acts)
		return function() if o.log then table.insert(o.log, name) end return acts end
	end
	return {
		enabled = function() return o.enabled ~= false end,
		ohaLastHit = host("oha_lh", o.ohaLastHit == true),
		ohaDeny = host("oha_deny", o.ohaDeny == true),
		ohaHold = host("oha_hold", o.ohaHold == true),
		ohaLocal = host("oha_local", o.ohaLocal == true),
		ohaPosition = host("oha_pos", true),
	}
end

local support = { pos = 5, GetPlayerID = function() return 1 end }
local core = { pos = 2, GetPlayerID = function() return 2 end }
local function walk(bot, c) return LaneTable.Walk(bot, c) end

-- The contract: each position's order, written out. A later row shows up as a diff of these lists.
do
	for pos = 1, 5 do
		check("order, position " .. pos, names(LaneTable.Order(pos, false)) == "sustain,oha_lh,oha_deny,oha_hold,oha_local,oha_pos", names(LaneTable.Order(pos, false)))
		check("order, position " .. pos .. ", lane-only", names(LaneTable.Order(pos, true)) == "sustain,oha_lh,oha_deny,oha_hold,oha_pos", names(LaneTable.Order(pos, true)))
	end
	check("an unknown position takes position 1's order", LaneTable.Order(nil, false) == LaneTable.Order(1, false))
end

-- Sustain's walk (a tango's tree, a step out) takes the frame before the host's steps, for both roles and lane-only; off with
-- the state layer off; a step that gives no order falls through to the host.
do
	world.sustainWalk, world.sustainSteps = true, 0
	local s, c = walk(support, ctx({ ohaLastHit = true })), walk(core, ctx({ ohaLastHit = true }))
	world.laneOnly = true
	local d = walk(core, ctx({ ohaLastHit = true }))
	world.laneOnly = false
	local off = walk(core, ctx({ enabled = false, ohaLastHit = true }))
	check("a sustain walk takes the frame over the host's last hit for a support, a core and a drill; off: the host's",
		s == "sustain" and c == "sustain" and d == "sustain" and off == "oha_lh" and world.sustainSteps == 3)
	world.sustainActs = false
	check("a sustain step that gives no order: the host's last hit still runs", walk(core, ctx({ ohaLastHit = true })) == "oha_lh")
	world.sustainWalk, world.sustainActs = false, nil
	check("no walk: the host's last hit", walk(core, ctx({ ohaLastHit = true })) == "oha_lh")
end

-- The host's steps run in order; the first that acts ends the frame; OHA's local override never ends it; lane-only skips it.
do
	for _, bot in ipairs({ support, core }) do
		local log = {}
		local row = walk(bot, ctx({ log = log }))
		check("position " .. bot.pos .. ": nothing acts, the host rows run in order and the position acts",
			row == "oha_pos" and table.concat(log, ",") == "oha_lh,oha_deny,oha_hold,oha_local,oha_pos", table.concat(log, ","))
	end
	local log = {}
	check("the first host step that acts ends the frame", walk(core, ctx({ ohaDeny = true, log = log })) == "oha_deny" and table.concat(log, ",") == "oha_lh,oha_deny")
	log = {}
	check("the local override's Think running does not end the frame", walk(core, ctx({ ohaLocal = true, log = log })) == "oha_pos"
		and table.concat(log, ","):find("oha_local,oha_pos", 1, true) ~= nil)
	log = {}
	world.laneOnly = true
	walk(core, ctx({ ohaLocal = true, log = log }))
	world.laneOnly = false
	check("lane-only: the local override does not run", table.concat(log, ",") == "oha_lh,oha_deny,oha_hold,oha_pos", table.concat(log, ","))
end

-- The cut line: a change of row at once, the same row quiet for 5 s, then again; a row of ours that wanted the frame and gave no
-- order is named in skip, the host's scans are not.
do
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local bot = { pos = 2, GetPlayerID = function() return 7 end }
	T = 100
	walk(bot, ctx({}))
	check("cut: the first frame logs the row", #lines == 1 and lines[1]:find("ev=cut", 1, true) ~= nil and lines[1]:find("kind=lane", 1, true) ~= nil
		and lines[1]:find("row=oha_pos", 1, true) ~= nil and lines[1]:find("pos=2", 1, true) ~= nil and lines[1]:find("lo=0", 1, true) ~= nil
		and lines[1]:find("skip=", 1, true) == nil, lines[1])
	T = 102
	walk(bot, ctx({}))
	check("cut: the same row within 5 s is not logged again", #lines == 1, #lines)
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: a change of row is logged at once", #lines == 2 and lines[2]:find("row=oha_lh", 1, true) ~= nil, lines[2])
	T = 108
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: the same row after 5 s is logged again", #lines == 3, #lines)
	world.sustainWalk, world.sustainActs = true, false
	T = 109
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: a row of ours that wanted the frame and gave no order is named", #lines == 4 and lines[4]:find("skip=sustain ", 1, true) ~= nil
		and lines[4]:find("row=oha_lh", 1, true) ~= nil, lines[4])
	T = 110
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: an unchanged skipped list is not logged again", #lines == 4, #lines)
	world.sustainWalk, world.sustainActs = false, nil
	T = 111
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: the same row with a different skipped list is logged", #lines == 5 and lines[5]:find("sustain", 1, true) == nil, lines[5])
end

-- An error in a row of ours: the row stands aside and the host's rows still run; an error in a host step is raised.
do
	H.Telemetry.SetSink(function() end)
	world.sustainWalk = true
	package.loaded["bots/FunLib/humaniser/sustain_act"].Step = function() error("boom") end
	check("an error in our row falls through to the host's last hit", walk(core, ctx({ ohaLastHit = true })) == "oha_lh")
	world.sustainWalk = false
	local c = ctx({})
	c.ohaLastHit = function() error("host boom") end
	local ok, err = pcall(walk, core, c)
	check("an error in a host step is raised, not swallowed as ours", not ok and tostring(err):find("host boom", 1, true) ~= nil, err)
end

finish()
