dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode, Lane, UnitType = dota.BotMode, dota.Lane, dota.UnitType

-- Extra stubs for the ping interpreter (kept here so dota_stubs.lua stays core-only).
local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetMostRecentPing() return self.ping or { time = 0, location = Vector(0, 0), normal_ping = true } end
function UnitMeta:ActionImmediate_Ping(x, y, normal) table.insert(PINGS_SENT, { pid = self.pid, x = x, y = y }) end
function UnitMeta:FindItemSlot(name) return self.items and self.items[name] or -1 end
function UnitMeta:GetItemInSlot(slot) if slot == 15 and self.tp then return { IsFullyCastable = function() return true end } end return nil end

BUILDINGS = {}
ZONES_ADDED, ZONES_REMOVED, PINGS_SENT = {}, {}, {}
function GetUnitList(t)
	local mine, theirs = UNITS[CURRENT_TEAM], UNITS[CURRENT_TEAM == 2 and 3 or 2]
	if t == UnitType.EnemyHeroes then return theirs end
	if t == UnitType.AlliedHeroes then return mine end
	if t == UnitType.EnemyBuildings then return BUILDINGS[CURRENT_TEAM == 2 and 3 or 2] or {} end
	if t == UnitType.AlliedBuildings then return BUILDINGS[CURRENT_TEAM] or {} end
	return {}
end
function AddAvoidanceZone(v, d) table.insert(ZONES_ADDED, v) return #ZONES_ADDED end
function RemoveAvoidanceZone(h) table.insert(ZONES_REMOVED, h) end
VISIBLE = true
function IsLocationVisible() return VISIBLE end

local function building(team, name, loc)
	local b = setmetatable({ pid = -1, team = team, bot = true, alive = true, loc = loc, modifiers = {} }, { __index = UnitMeta })
	b.GetUnitName = function() return name end
	BUILDINGS[team] = BUILDINGS[team] or {}
	table.insert(BUILDINGS[team], b)
	return b
end

local ROSH = Vector(-3000, 2300)
local RUNE = Vector(-1600, 1200)
local function reset()
	ResetWorld()
	BUILDINGS, ZONES_ADDED, ZONES_REMOVED, PINGS_SENT = {}, {}, {}, {}
	VISIBLE = true
end
local function fresh(cfg)
	local H = FreshHumaniser(cfg or { Enable = true })
	H.Pings.SetHelpers({ roshanLocation = function() return ROSH end, reservedSpots = function() return { RUNE } end })
	return H
end
local function ping(unit, x, y, time, normal)
	unit.ping = { time = time, location = Vector(x, y), normal_ping = normal ~= false }
end
local function onlyOrder(H)
	local list = H.Orders.GetActive(2)
	return #list == 1 and list[1] or nil, #list
end

-- Classification precedence: each context, checked in the spec's order
local cases = {
	{ name = "roshan beats a hero standing at the pit", at = { -3000, 2350 }, expect = "ROSHAN",
	  setup = function() MakeUnit({ pid = 7, team = 3, loc = Vector(-3000, 2400) }) end },
	{ name = "visible enemy hero beats the tower behind it", at = { 3000, 0 }, expect = "ATTACK",
	  setup = function() MakeUnit({ pid = 7, team = 3, loc = Vector(3100, 0) }) building(3, "npc_dota_badguys_tower1_mid", Vector(3200, 0)) end },
	{ name = "enemy tower -> push its lane", at = { 3000, 0 }, expect = "PUSH", lane = Lane.Top,
	  setup = function() building(3, "npc_dota_badguys_tower2_top", Vector(3300, 0)) end },
	{ name = "own tower -> defend its lane", at = { 3000, 0 }, expect = "DEFEND", lane = Lane.Bot,
	  setup = function() building(2, "npc_dota_goodguys_tower1_bot", Vector(3300, 0)) end },
	{ name = "outpost is not a lane building", at = { 3000, 0 }, expect = "GATHER",
	  setup = function() building(3, "npc_dota_watch_tower_top", Vector(3100, 0)) end },
	{ name = "rune spot keeps the rune-claim behaviour (no order)", at = { -1600, 1250 }, expect = nil, danger = true },
	{ name = "danger ping on ground -> avoid", at = { 0, -2000 }, expect = "AVOID", danger = true },
	{ name = "normal ping on ground -> gather", at = { 0, -2000 }, expect = "GATHER" },
}
for _, c in ipairs(cases) do
	reset()
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false })
	local bot = MakeUnit({ pid = 1, loc = Vector(500, 0) })
	if c.setup then c.setup() end
	T = 10
	ping(human, c.at[1], c.at[2], 10, not c.danger)
	H.Tick(bot)
	local order, n = onlyOrder(H)
	if c.expect == nil then
		check(c.name, n == 0, n)
	else
		check(c.name, order ~= nil and order.type == c.expect and (c.lane == nil or order.lane == c.lane), order and order.type or n)
	end
end

-- ATTACK carries the hero as target and ranks nearest 2 within 4000 plus anyone within 1600
do
	reset()
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false })
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(0, 0) })
	MakeUnit({ pid = 1, loc = Vector(1000, 0) })
	MakeUnit({ pid = 2, loc = Vector(1200, 0) })
	MakeUnit({ pid = 3, loc = Vector(1500, 0) })
	MakeUnit({ pid = 4, loc = Vector(4500, 0) })
	T = 10
	ping(human, 50, 0, 10)
	H.Pings.Scan(2)
	local o = onlyOrder(H)
	check("attack targets the pinged hero", o and o.target == enemy)
	check("attack responders: nearest 2 + within 1600, none beyond 4000", o and table.concat(o.responders, ",") == "1,2,3", o and table.concat(o.responders, ","))
end

-- DEFEND: nearest 2, plus far bots that have a TP ready
do
	reset()
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false })
	building(2, "npc_dota_goodguys_tower2_mid", Vector(0, 0))
	MakeUnit({ pid = 1, loc = Vector(500, 0) })
	MakeUnit({ pid = 2, loc = Vector(800, 0) })
	MakeUnit({ pid = 3, loc = Vector(9000, 0) })
	local tpBot = MakeUnit({ pid = 4, loc = Vector(9500, 0) })
	tpBot.tp = true
	T = 10
	ping(human, 100, 0, 10)
	H.Pings.Scan(2)
	local o = onlyOrder(H)
	check("defend adds far TP bot only", o and table.concat(o.responders, ",") == "1,2,4", o and table.concat(o.responders, ","))
end

-- Dedupe: the same ping read every frame posts once; a stale ping is ignored; a new ping replaces GATHER
do
	reset()
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false })
	local bot = MakeUnit({ pid = 1 })
	T = 20
	ping(human, 0, -2000, 10)
	H.Tick(bot)
	check("ping older than MaxPingAge ignored", #H.Orders.GetActive(2) == 0)
	ping(human, 0, -2000, 20)
	for i = 1, 5 do T = 20 + i * 0.03 H.Tick(bot) end
	local first = onlyOrder(H)
	check("same ping posts once", first ~= nil and first.sourceKey == "ping:0:20.00", first and first.sourceKey)
	T = 21
	ping(human, 0, -2500, 21)
	H.Tick(bot)
	local second = onlyOrder(H)
	check("new ping replaces the earlier gather", second ~= nil and second.id ~= first.id)
end

-- Two module instances (non-shared modules) derive the same order and responders from one ping
do
	reset()
	local human = MakeUnit({ pid = 0, bot = false })
	local bots = {}
	for pid = 1, 4 do bots[pid] = MakeUnit({ pid = pid, loc = Vector(pid * 300, 0) }) end
	building(3, "npc_dota_badguys_tower1_bot", Vector(0, 0))
	T = 30
	ping(human, 100, 0, 30)
	local A = fresh()
	A.Tick(bots[1])
	local B = fresh()
	B.Tick(bots[4])
	local oa, ob = onlyOrder(A), onlyOrder(B)
	check("instances agree on order", oa and ob and oa.type == ob.type and oa.lane == ob.lane and oa.sourceKey == ob.sourceKey)
	check("instances agree on responders", oa and ob and table.concat(oa.responders, ",") == table.concat(ob.responders, ",") and #oa.responders == 3)
end

-- Two humans pinging different things get separate orders with separate responders
do
	reset()
	local H = fresh()
	local h0 = MakeUnit({ pid = 0, bot = false, loc = Vector(-5000, 0) })
	local h1 = MakeUnit({ pid = 5, bot = false, loc = Vector(5000, 0) })
	MakeUnit({ pid = 1, loc = Vector(-4000, 0) })
	MakeUnit({ pid = 2, loc = Vector(-4100, 0) })
	MakeUnit({ pid = 3, loc = Vector(4000, 0) })
	MakeUnit({ pid = 4, loc = Vector(4100, 0) })
	building(2, "npc_dota_goodguys_tower1_top", Vector(-4500, 0))
	T = 40
	ping(h0, -4500, 0, 40)
	ping(h1, 4500, 0, 40)
	H.Pings.Scan(2)
	local defend, gather
	for _, o in ipairs(H.Orders.GetActive(2)) do
		if o.type == "DEFEND" then defend = o elseif o.type == "GATHER" then gather = o end
	end
	check("both humans' pings handled", defend ~= nil and gather ~= nil)
	check("separate responders", defend and gather and table.concat(defend.responders, ",") == "2,1" and table.concat(gather.responders, ",") == "4,3", defend and gather and (table.concat(defend.responders, ",") .. " / " .. table.concat(gather.responders, ",")))
end

-- Moving out of a smoke: a smoked issuer's ping brings everyone and ends the SMOKE gather
do
	reset()
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false, modifiers = { modifier_smoke_of_deceit = 0 } })
	for pid = 1, 4 do MakeUnit({ pid = pid, loc = Vector(pid * 100, 0) }) end
	H.Orders.Post(2, { type = "SMOKE", sourceKey = "s", issuerPID = 0, location = Vector(0, 0), duration = 30, maxResponders = 5 })
	T = 5
	ping(human, 0, -3000, 5)
	H.Pings.Scan(2)
	local o = onlyOrder(H)
	check("smoked ping: whole team, smoke order replaced", o and o.type == "GATHER" and #o.responders == 4, o and o.type)
end

-- AVOID adds one avoidance zone on accept and removes it when the order expires; it does not mask other orders
do
	reset()
	local H = fresh()
	MakeUnit({ pid = 0, bot = false })
	local b1 = MakeUnit({ pid = 1, loc = Vector(100, 0) })
	local b2 = MakeUnit({ pid = 2, loc = Vector(200, 0) })
	H.Orders.Post(2, { type = "DEFEND", sourceKey = "d", issuerPID = 0, location = Vector(0, 0), lane = Lane.Mid, duration = 20, maxResponders = 2 })
	H.Orders.Post(2, { type = "AVOID", sourceKey = "a", issuerPID = 0, location = Vector(500, 600), radius = 1200, duration = 10, maxResponders = 5 })
	T = 5
	H.Orders.GetFor(b1) H.Orders.GetFor(b2)
	check("one zone per order", #ZONES_ADDED == 1 and ZONES_ADDED[1].z == 1200, #ZONES_ADDED)
	check("AVOID does not hide DEFEND floor", H.Orders.DesireFloor(b1, BotMode.DefendTowerMid, Lane.Mid) > 0)
	T = 11
	H.Orders.GetActive(2)
	check("zone removed on expiry", #ZONES_REMOVED == 1 and ZONES_REMOVED[1] == 1)
end

-- Acknowledgement: spokesperson pings back once; a second order within 10 s gets no extra ping or line
do
	reset()
	local H = fresh()
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, bot:GetPlayerID() .. ":" .. key) end)
	local human = MakeUnit({ pid = 0, bot = false })
	local b1 = MakeUnit({ pid = 1, loc = Vector(100, 0) })
	local b2 = MakeUnit({ pid = 2, loc = Vector(200, 0) })
	T = 1
	ping(human, 0, -2000, 1)
	H.Tick(b1) H.Tick(b2)
	T = 5
	H.Tick(b1) H.Tick(b2)
	check("one ack line, one ack ping, from the spokesperson", #said == 1 and said[1] == "1:say_order_ack_gather" and #PINGS_SENT == 1 and PINGS_SENT[1].pid == 1, table.concat(said, " "))
	T = 6
	ping(human, 0, -2600, 6)
	H.Tick(b1)
	T = 10
	H.Tick(b1)
	check("no second line or ping within 10 s", #said == 1 and #PINGS_SENT == 1, #said .. "/" .. #PINGS_SENT)
	T = 17
	ping(human, 0, -3000, 17)
	H.Tick(b1)
	T = 21
	H.Tick(b1)
	check("line and ping allowed again after 10 s", #said == 2 and #PINGS_SENT == 2, #said .. "/" .. #PINGS_SENT)
end

-- Commitment: retreat is capped only while an order is accepted and HP is above 50%
do
	reset()
	local H = fresh()
	MakeUnit({ pid = 0, bot = false })
	local b = MakeUnit({ pid = 1, hp = 80 })
	check("no order: retreat untouched", H.Orders.CapRetreatDesire(b, 1.1) == 1.1)
	H.Orders.Post(2, { type = "DEFEND", sourceKey = "d", issuerPID = 0, location = Vector(0, 0), lane = Lane.Mid, duration = 20, maxResponders = 1 })
	T = 5
	check("healthy + order: capped below the order floor", near(H.Orders.CapRetreatDesire(b, 1.1), 0.75), H.Orders.CapRetreatDesire(b, 1.1))
	b.hp = 40
	check("below half HP: retreat untouched", H.Orders.CapRetreatDesire(b, 1.1) == 1.1)
end

-- A bot avoids an AVOID zone only after reading the ping; units inside it are filtered out
do
	reset()
	local H = fresh()
	MakeUnit({ pid = 0, bot = false })
	local b = MakeUnit({ pid = 1, loc = Vector(3000, 0) })
	local inside, outside = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) }), MakeUnit({ pid = 8, team = 3, loc = Vector(2000, 0) })
	local list = { inside, outside }
	check("no AVOID: list passes through", H.Orders.FilterAvoided(b, list) == list)
	H.Orders.Post(2, { type = "AVOID", sourceKey = "a", issuerPID = 0, location = Vector(0, 0), radius = 1200, duration = 10, maxResponders = 5 })
	T = 0.1
	check("not avoided before the bot reads the ping", H.Orders.AvoidsLocation(b, Vector(0, 0)) == false)
	T = 3
	check("avoided inside the radius", H.Orders.AvoidsLocation(b, Vector(1000, 0)) == true)
	check("not avoided outside the radius", H.Orders.AvoidsLocation(b, Vector(1300, 0)) == false)
	local kept = H.Orders.FilterAvoided(b, list)
	check("filter drops units inside the zone", #kept == 1 and kept[1] == outside, #kept)
end

-- AVOID is never declined: a dead bot says nothing and still avoids the zone after respawning
do
	reset()
	local H = fresh()
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, key) end)
	MakeUnit({ pid = 0, bot = false })
	local b = MakeUnit({ pid = 1, alive = false })
	H.Orders.Post(2, { type = "AVOID", sourceKey = "a", issuerPID = 0, location = Vector(0, 0), radius = 1200, duration = 10, maxResponders = 5 })
	T = 3
	H.Orders.GetFor(b)
	b.alive = true
	T = 4
	local declined = false
	for _, key in ipairs(said) do if key:find("decline") then declined = true end end
	check("dead bot did not decline AVOID", not declined and H.Orders.AvoidsLocation(b, Vector(0, 0)) == true, table.concat(said, " "))
end

-- Danger pings are forgotten early once the team can see the area is clear, never before MinSeconds
do
	local function setup()
		reset()
		local H = fresh()
		MakeUnit({ pid = 0, bot = false })
		local b = MakeUnit({ pid = 1, loc = Vector(3000, 0) })
		H.Orders.Post(2, { type = "AVOID", sourceKey = "a", issuerPID = 0, location = Vector(0, 0), radius = 1200, duration = 10, maxResponders = 5 })
		T = 1.5
		H.Orders.GetFor(b)
		return H, b
	end
	local function run(H, from, to)
		for t = from, to, 0.5 do T = t H.Pings.ForgetClearedDangers(2) end
		return #H.Orders.GetActive(2)
	end

	local H = setup()
	check("clear area kept before MinSeconds", run(H, 2, 3.5) == 1)
	check("clear area forgotten after MinSeconds + ClearSeconds", run(H, 4, 6) == 0)
	check("forgetting removes the avoidance zone", #ZONES_REMOVED == 1)

	H = setup()
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(500, 0) })
	check("enemy seen in the area keeps it", run(H, 4, 9.5) == 1)
	enemy.loc = Vector(5000, 0)
	check("enemy leaving restarts the clear timer", run(H, 9.5, 9.5) == 1)

	H = setup()
	VISIBLE = false
	check("unseen area kept until expiry", run(H, 4, 9.5) == 1 and run(H, 10, 10) == 0)
end

-- Kill switch: Pings disabled means no orders and legacy readers stay in charge
do
	reset()
	local H = fresh({ Enable = true, Pings = { Enable = false } })
	local human = MakeUnit({ pid = 0, bot = false })
	local bot = MakeUnit({ pid = 1 })
	T = 3
	ping(human, 0, -2000, 3)
	H.Tick(bot)
	check("pings disabled: nothing posted", #H.Orders.GetActive(2) == 0)
	check("pings disabled: legacy path active", H.Pings.IsActive() == false)
	local H2 = fresh({ Enable = false })
	check("humaniser disabled: pings inactive", H2.Pings.IsActive() == false)
end

-- The danger mapping is one function so it can be flipped after the in-game check
do
	reset()
	local H = fresh()
	check("normal_ping=false is danger", H.Pings.IsDangerPing({ normal_ping = false }) == true and H.Pings.IsDangerPing({ normal_ping = true }) == false)
end

finish()
