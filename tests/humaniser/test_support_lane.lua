-- Slice l1-support-deny: a support's ordered lane steps (states/support_lane). The deny step takes the frame while the body
-- is in a deny or would start one, and only while the body runs; otherwise the frame goes back to OHA's own laning steps.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local world = { denyOnly = true, offered = false }
package.loaded["bots/FunLib/humaniser/states/laning"] = {
	OwnsDenyOnly = function() return world.denyOnly end,
	DenyOffered = function() return world.offered end,
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
	check("deny offered: the deny step steps the body first", SupportLane.Step({}, c) == "deny" and o.steps == 1)
	world.offered = false
	c, o = ctx({ running = true, label = "hold" })
	check("nothing offered: the frame goes back to OHA's steps", SupportLane.Step({}, c) == nil and o.steps == 0)
	c, o = ctx({ running = true, label = "deny" })
	check("an attempt in progress keeps the frame though no new deny is offered", SupportLane.Step({}, c) == "deny" and o.steps == 1)
end

do
	world.offered = true
	local c, o = ctx({ running = false, label = nil })
	check("body not running (another state): OHA's steps keep the frame", SupportLane.Step({}, c) == nil and o.steps == 0)
	c, o = ctx({ running = true, label = "hold", acts = false })
	check("body stepped but issued nothing: OHA's steps still run this frame", SupportLane.Step({}, c) == nil and o.steps == 1)
	world.denyOnly = false
	c, o = ctx({ running = true, label = "deny" })
	check("not a deny-only bot (a core, or the switch off): no step", SupportLane.Step({}, c) == nil and o.steps == 0)
end

finish()
