-- Slice l1-support-deny, support-lane-hits: a support's ordered lane steps (states/support_lane). The hit step takes the frame
-- while the body is in a deny or last-hit attempt or would start one, and only while the body runs; otherwise the frame goes
-- back to OHA's own laning steps.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local world = { denyOnly = true, offered = false, spot = false }
package.loaded["bots/FunLib/humaniser/states/laning"] = {
	OwnsSupportHits = function() return world.denyOnly end,
	HitOffered = function() return world.offered end,
	OwnsSpot = function() return world.spot end,
}
package.loaded["bots/FunLib/humaniser/states/support_lane"] = nil
local SupportLane = require("bots/FunLib/humaniser/states/support_lane")

local function ctx(o)
	o.steps = 0
	return {
		bodyRunning = function() return o.running end,
		bodyLabel = function() return o.label end,
		stepBody = function() o.steps = o.steps + 1 return o.acts ~= false end,
	}, o
end

do
	world.offered = true
	local c, o = ctx({ running = true, label = "hold" })
	check("hit offered: the hit step steps the body first", SupportLane.Step({}, c) == "hit" and o.steps == 1)
	world.offered = false
	c, o = ctx({ running = true, label = "hold" })
	check("nothing offered: the frame goes back to OHA's steps", SupportLane.Step({}, c) == nil and o.steps == 0)
	c, o = ctx({ running = true, label = "deny" })
	check("a deny attempt in progress keeps the frame though nothing new is offered", SupportLane.Step({}, c) == "hit" and o.steps == 1)
	c, o = ctx({ running = true, label = "lasthit" })
	check("a last-hit attempt in progress keeps the frame though nothing new is offered", SupportLane.Step({}, c) == "hit" and o.steps == 1)
end

do
	world.offered = true
	local c, o = ctx({ running = false, label = nil })
	check("body not running (another state): OHA's steps keep the frame", SupportLane.Step({}, c) == nil and o.steps == 0)
	c, o = ctx({ running = true, label = "hold", acts = false })
	check("body stepped but issued nothing: OHA's steps still run this frame", SupportLane.Step({}, c) == nil and o.steps == 1)
	world.denyOnly = false
	c, o = ctx({ running = true, label = "deny" })
	check("not a support the body takes lane hits for (a core, or the switch off): no step", SupportLane.Step({}, c) == nil and o.steps == 0)
end

-- Slice support-spot: on our spot, a frame with no lane hit goes to the body's hold, not to OHA's harass and PositionThink.
do
	world.denyOnly, world.offered, world.spot = true, false, true
	local c, o = ctx({ running = true, label = "hold" })
	check("our spot, nothing offered: the hold step keeps the frame", SupportLane.Step({}, c) == "hold" and o.steps == 1)
	world.offered = true
	c, o = ctx({ running = true, label = "hold" })
	check("our spot, a hit offered: the hit step goes first and the body is stepped once", SupportLane.Step({}, c) == "hit" and o.steps == 1)
	world.offered = false
	c, o = ctx({ running = false })
	check("our spot but the body not running (another state): no step", SupportLane.Step({}, c) == nil and o.steps == 0)
	world.denyOnly = false
	c, o = ctx({ running = true, label = "hold" })
	check("our spot for a bot whose lane hits are not the support body's: no hold step", SupportLane.Step({}, c) == nil and o.steps == 0)
end

finish()
