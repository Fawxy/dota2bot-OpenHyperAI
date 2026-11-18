-- The lane table (states/lane_table): the one ordered list of what a hero does on a laning frame, with a rank per position, and the
-- one walker. Ported from the support lane steps' tests (slice l1-support-deny, support-lane-hits, support-spot, lane-aggro).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true, Cut = true } })
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)

local world = { denyOnly = true, offered = false, spot = false }
package.loaded["bots/FunLib/humaniser/states/laning"] = {
	OwnsSupportHits = function() return world.denyOnly end,
	HitOffered = function() return world.offered end,
	OwnsSpot = function() return world.spot end,
}
package.loaded["bots/FunLib/humaniser/lane_aggro"] = {
	Owns = function() return world.aggro == true end,
	Pending = function() return world.aggroPending == true end,
	Step = function() world.aggroSteps = (world.aggroSteps or 0) + 1 return world.aggroActs ~= false end,
	StepOpen = function() return world.openActs == true end,
}
package.loaded["bots/FunLib/humaniser/states/wave_hold"] = { Step = function() end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return false end }
package.loaded["bots/FunLib/humaniser/drill"] = {
	LaneHold = function() return world.laneHold == true end,
	LaneAggro = function() return world.laneAggro == true end,
}
package.loaded["bots/FunLib/humaniser/overrides"] = { LaneOnly = function() return world.laneOnly == true end }
package.loaded["bots/FunLib/humaniser/lane_config"] = { PositionOf = function(u) return u.pos end }
package.loaded["bots/FunLib/humaniser/states/lane_table"] = nil
local LaneTable = require("bots/FunLib/humaniser/states/lane_table")

local function names(rows)
	local out = {}
	for _, r in ipairs(rows) do table.insert(out, r.name) end
	return table.concat(out, ",")
end

-- A bot of the given position and a ctx whose every predicate of ours is false and whose host steps do nothing but position.
-- o.log, when given, collects the name of every host step and the body step in the order they ran.
local function ctx(o)
	o.steps = 0
	local function host(name, acts)
		return function() if o.log then table.insert(o.log, name) end return acts end
	end
	return {
		enabled = function() return o.enabled ~= false end,
		bodyRunning = function() return o.running == true end,
		bodyLabel = function() return o.label end,
		stepBody = function()
			o.steps = o.steps + 1
			if o.log then table.insert(o.log, "body") end
			return o.acts ~= false
		end,
		bodyBusy = function() return o.busy == true end,
		bodyLastHits = function() return o.bodyLastHits == true end,
		bodySupportHits = function() return o.bodySupportHits == true end,
		bodySupportLastHits = function() return o.bodySupportLastHits == true end,
		etiquette = host("etiquette", o.etiquette == true),
		ohaLastHit = host("oha_lh", o.ohaLastHit == true),
		ohaDeny = host("oha_deny", o.ohaDeny == true),
		ohaHold = host("oha_hold", o.ohaHold == true),
		ohaLocal = host("oha_local", o.ohaLocal == true),
		ohaPosition = host("oha_pos", true),
	}, o
end

local support = { pos = 5, GetPlayerID = function() return 1 end }
local core = { pos = 2, GetPlayerID = function() return 2 end }
local function walk(bot, c) return LaneTable.Walk(bot, c) end
local function isSupportRow(name) return name:find("^support_") ~= nil end

-- The contract: each position's order, written out. A later re-ranking shows up as a diff of these lists.
do
	local coreOrder = "body_hit,aggro,etiquette,oha_lh,oha_deny,oha_hold,oha_local,body,oha_pos"
	local coreDrill = "body_hit,drill_hold,drill_aggro,oha_lh,oha_deny,oha_hold,body,oha_pos"
	local supportOrder = "body_hit,support_hit,support_aggro,support_hold,etiquette,oha_lh,oha_deny,oha_hold,oha_local,body,oha_pos"
	local supportDrill = "body_hit,support_hit,support_aggro,support_hold,oha_lh,oha_deny,oha_hold,body,oha_pos"
	for pos = 1, 3 do
		check("order, position " .. pos, names(LaneTable.Order(pos, false)) == coreOrder, names(LaneTable.Order(pos, false)))
		check("order, position " .. pos .. ", lane-only", names(LaneTable.Order(pos, true)) == coreDrill, names(LaneTable.Order(pos, true)))
	end
	for pos = 4, 5 do
		check("order, position " .. pos, names(LaneTable.Order(pos, false)) == supportOrder, names(LaneTable.Order(pos, false)))
		check("order, position " .. pos .. ", lane-only", names(LaneTable.Order(pos, true)) == supportDrill, names(LaneTable.Order(pos, true)))
	end
	check("an unknown position takes position 1's order", LaneTable.Order(nil, false) == LaneTable.Order(1, false))
end

-- A row with no rank for a position is never asked whether it wants the frame.
do
	local asked = {}
	local saved = {}
	for _, r in ipairs(LaneTable.ROWS) do
		saved[r] = r.wants
		r.wants = function(...) asked[r.name] = (asked[r.name] or 0) + 1 return saved[r](...) end
	end
	world.laneOnly = false
	local c = ctx({})
	walk(core, c)
	check("a core is never asked about a support row nor a drill-only row",
		asked.support_hit == nil and asked.support_aggro == nil and asked.support_hold == nil and asked.drill_hold == nil and asked.drill_aggro == nil
			and asked.body_hit == 1 and asked.aggro == 1)
	asked = {}
	c = ctx({})
	walk(support, c)
	check("a support is never asked about a core draw", asked.aggro == nil and asked.support_hit == 1)
	asked = {}
	world.laneOnly = true
	c = ctx({})
	walk(core, c)
	check("lane-only: the rows a drill does not run are not asked", asked.aggro == nil and asked.etiquette == nil and asked.oha_local == nil and asked.oha_lh == 1)
	world.laneOnly = false
	for _, r in ipairs(LaneTable.ROWS) do r.wants = saved[r] end
end

-- A support's lane hits first, then its draw, then its hold; a row whose run gives no order falls through.
do
	world.offered = true
	local c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("hit offered: the hit row steps the body first", walk(support, c) == "support_hit" and o.steps == 1)
	world.offered = false
	c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("nothing offered: the frame goes back to OHA's steps", isSupportRow(walk(support, c)) == false and o.steps == 0)
	c, o = ctx({ running = true, label = "deny", bodySupportHits = true })
	check("a deny attempt in progress keeps the frame though nothing new is offered", walk(support, c) == "support_hit" and o.steps == 1)
	c, o = ctx({ running = true, label = "lasthit", bodySupportHits = true })
	check("a last-hit attempt in progress keeps the frame though nothing new is offered", walk(support, c) == "support_hit" and o.steps == 1)
end

do
	world.offered = true
	local c, o = ctx({ running = false, bodySupportHits = true })
	check("body not running (another state): OHA's steps keep the frame", isSupportRow(walk(support, c)) == false and o.steps == 0)
	c, o = ctx({ running = true, label = "hold", acts = false, bodySupportHits = true })
	check("body stepped but issued nothing: OHA's steps still run this frame", walk(support, c) == "oha_pos" and o.steps == 1)
	world.denyOnly = false
	c, o = ctx({ running = true, label = "deny" })
	check("not a support the body takes lane hits for (a core, or the switch off): no support row", isSupportRow(walk(support, c)) == false)
end

-- Slice support-spot: on our spot, a frame with no lane hit goes to the body's hold, not to OHA's harass and PositionThink.
do
	world.denyOnly, world.offered, world.spot = true, false, true
	local c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("our spot, nothing offered: the hold row keeps the frame", walk(support, c) == "support_hold" and o.steps == 1)
	world.offered = true
	c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("our spot, a hit offered: the hit row goes first and the body is stepped once", walk(support, c) == "support_hit" and o.steps == 1)
	world.offered = false
	c, o = ctx({ running = false, bodySupportHits = true })
	check("our spot but the body not running (another state): no row", walk(support, c) == "oha_pos" and o.steps == 0)
	world.denyOnly = false
	c, o = ctx({ running = true, label = "hold" })
	check("our spot for a bot whose lane hits are not the support body's: no hold row", isSupportRow(walk(support, c)) == false)
end

-- Slice lane-aggro: a support whose lane core is away draws creeps after its lane hits and before the hold.
do
	world.denyOnly, world.spot, world.aggro, world.aggroSteps = true, true, true, 0
	world.offered = true
	local c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("core away, a hit offered: the hit goes first, no draw", walk(support, c) == "support_hit" and world.aggroSteps == 0)
	world.offered = false
	c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("core away, no hit: the aggro row takes the frame before the hold", walk(support, c) == "support_aggro" and o.steps == 0)
	world.aggroActs = false
	c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("aggro row gives no order: the hold still runs", walk(support, c) == "support_hold" and o.steps == 1)
	world.aggroActs, world.aggroSteps = nil, 0
	c, o = ctx({ running = false, bodySupportHits = true })
	walk(support, c)
	check("body not running (another state): no draw", world.aggroSteps == 0)
	-- Review lane-aggro F1: the core came back mid-move; the support's open attempt is still stepped so it ends cleanly.
	world.aggro, world.aggroPending, world.aggroActs, world.aggroSteps = false, true, false, 0
	c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("core back, attempt open: the aggro row still runs it", walk(support, c) == "support_hold" and world.aggroSteps == 1)
	world.aggroPending, world.aggroSteps = false, 0
	c, o = ctx({ running = true, label = "hold", bodySupportHits = true })
	check("core back, nothing open: no aggro row", walk(support, c) == "support_hold" and world.aggroSteps == 0)
	world.aggro, world.aggroActs, world.denyOnly, world.spot = false, nil, false, false
end

-- Our code off: whatever the world says, only the host's rows run, in order, and OHA's local override never ends the frame.
do
	world.denyOnly, world.offered, world.spot, world.aggro, world.laneHold = true, true, true, true, true
	for _, bot in ipairs({ support, core }) do
		local log = {}
		local c = ctx({ enabled = false, running = true, label = "deny", acts = false, log = log })
		c.bodyRunning = function() return false end
		local row = walk(bot, c)
		check("our code off, position " .. bot.pos .. ": the host rows run in order and the last acts",
			row == "oha_pos" and table.concat(log, ",") == "etiquette,oha_lh,oha_deny,oha_hold,oha_local,body,oha_pos", table.concat(log, ","))
	end
	local log = {}
	local c = ctx({ enabled = false, ohaDeny = true, log = log })
	check("our code off: the first host step that acts ends the frame", walk(core, c) == "oha_deny" and table.concat(log, ",") == "etiquette,oha_lh,oha_deny")
	log = {}
	c = ctx({ enabled = false, ohaLocal = true, acts = false, log = log })
	check("the local override's Think running does not end the frame", walk(core, c) == "oha_pos" and table.concat(log, ","):find("oha_local,body,oha_pos", 1, true) ~= nil)
	world.denyOnly, world.offered, world.spot, world.aggro, world.laneHold = false, false, false, false, false
end

-- The host's last hit, deny and hold are skipped where the body owns them, so a frame is not both.
do
	world.aggroActs = false
	local log = {}
	local c = ctx({ bodyLastHits = true, acts = false, log = log })
	walk(core, c)
	check("the body owns a core's last hits: OHA's last hit, deny and hold do not run", table.concat(log, ",") == "etiquette,oha_local,body,oha_pos", table.concat(log, ","))
	log = {}
	c = ctx({ bodySupportLastHits = true, bodySupportHits = true, acts = false, log = log })
	walk(support, c)
	check("the body owns a support's hits: OHA's last hit and deny do not run, its hold may", table.concat(log, ",") == "etiquette,oha_hold,oha_local,oha_pos", table.concat(log, ","))
	log = {}
	c = ctx({ bodyLastHits = true, busy = true, log = log })
	check("the body's swing in progress ends the frame before every other row", walk(core, c) == "body_hit" and table.concat(log, ",") == "body")
	world.aggroActs = nil
end

-- The drill rows: only under lane-only, with their drill entry on.
do
	world.laneOnly, world.laneHold, world.laneAggro, world.openActs = true, true, false, false
	local c = ctx({ bodyLastHits = true, acts = false })
	check("lane-only with the wave hold but no open draw: the hold row gives no order and the frame falls through", walk(core, c) == "oha_pos")
	world.openActs = true
	check("lane-only with the wave hold and an open draw: the hold row acts", walk(core, ctx({ bodyLastHits = true })) == "drill_hold")
	world.laneHold, world.laneAggro, world.aggroSteps = false, true, 0
	check("lane-only with lane aggro: its draw acts", walk(core, ctx({ bodyLastHits = true })) == "drill_aggro" and world.aggroSteps == 1)
	world.laneOnly = false
	check("not lane-only: the drill rows do not run, the core's draw does", walk(core, ctx({ bodyLastHits = true })) == "aggro")
	world.laneHold, world.laneAggro, world.openActs = false, false, false
end

-- The cut line: a change of row at once, the same row quiet for 5 s, then again.
do
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local bot = { pos = 2, GetPlayerID = function() return 7 end }
	T = 100
	walk(bot, ctx({ acts = false }))
	check("cut: the first frame logs the row", #lines == 1 and lines[1]:find("ev=cut", 1, true) ~= nil and lines[1]:find("kind=lane", 1, true) ~= nil
		and lines[1]:find("row=oha_pos", 1, true) ~= nil and lines[1]:find("pos=2", 1, true) ~= nil and lines[1]:find("lo=0", 1, true) ~= nil, lines[1])
	T = 102
	walk(bot, ctx({ acts = false }))
	check("cut: the same row within 5 s is not logged again", #lines == 1, #lines)
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: a change of row is logged at once", #lines == 2 and lines[2]:find("row=oha_lh", 1, true) ~= nil, lines[2])
	T = 108
	walk(bot, ctx({ ohaLastHit = true }))
	check("cut: the same row after 5 s is logged again", #lines == 3, #lines)
	T = 109
	walk(bot, ctx({ busy = true, acts = false }))
	check("cut: the rows that wanted the frame and gave no order are named", #lines == 4 and lines[4]:find("skip=body_hit,", 1, true) ~= nil
		and lines[4]:find("row=oha_pos", 1, true) ~= nil, lines[4])
	T = 110
	walk(bot, ctx({ busy = true, acts = false }))
	check("cut: an unchanged skipped list is not logged again", #lines == 4, #lines)
	T = 111
	walk(bot, ctx({ acts = false }))
	check("cut: the same row with a different skipped list is logged", #lines == 5 and lines[5]:find("body_hit", 1, true) == nil, lines[5])
end

finish()
