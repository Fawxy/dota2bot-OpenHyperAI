-- World and hero events (BACKLOG 0.6, slice 23): runes, wards, buildings, Roshan, smoke, teleports, aegis.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local Rune, UnitType = dota.Rune, dota.UnitType

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetLastHits() return 0 end
function UnitMeta:GetDenies() return 0 end
function UnitMeta:GetAttackTarget() return nil end
function UnitMeta:GetGold() return 600 end
function UnitMeta:FindItemSlot(name) return (self.items or {})[name] and 0 or -1 end

RUNE_STATUS_UNKNOWN, RUNE_STATUS_AVAILABLE, RUNE_STATUS_MISSING = 0, 1, 2
RUNES, RUNE_SPOTS = {}, {}
function GetRuneStatus(r) return RUNES[r] or RUNE_STATUS_MISSING end
function GetRuneSpawnLocation(r) return RUNE_SPOTS[r] or Vector(9000, 9000) end
ROSHAN_AT = 0
function GetRoshanKillTime() return ROSHAN_AT end
WARDS, ENEMIES, TOWERS = {}, {}, {}
function GetUnitList(kind)
	if kind == UnitType.AlliedWards then return WARDS end
	if kind == UnitType.EnemyHeroes then return ENEMIES end
	return {}
end
local function building() return { IsAlive = function(self) return not self.dead end } end
function GetTower(team, id) return TOWERS[team .. ":" .. id] end
function GetBarracks() return nil end

local lines
local function fresh()
	ResetWorld()
	RUNES, RUNE_SPOTS, WARDS, ENEMIES, TOWERS, ROSHAN_AT = {}, {}, {}, {}, {}, 0
	CURRENT_TEAM = 2
	local H = FreshHumaniser({ Enable = false, Telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	return H
end
local function events(name)
	local r = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) or l:sub(-#name - 4) == " ev=" .. name then table.insert(r, l) end end
	return r
end
local function field(line, key) return line:match(" " .. key .. '="([^"]*)"') or line:match(" " .. key .. "=(%S+)") end
local function tick(H, units, t)
	T = t
	for _, u in ipairs(units) do H.Telemetry.Tick(u) end
end

-- A rune that vanishes next to an own hero is that hero's pickup; power spots before 6:00 hold water runes.
do
	local H = fresh()
	local logger = MakeUnit({ pid = 1, loc = Vector(-5000, -5000) })
	local mid = MakeUnit({ pid = 2, loc = Vector(-1650, 1150) })
	RUNE_SPOTS[Rune.Power1] = Vector(-1700, 1100)
	RUNES[Rune.Power1] = RUNE_STATUS_AVAILABLE
	tick(H, { logger, mid }, 120)
	RUNES[Rune.Power1] = RUNE_STATUS_MISSING
	tick(H, { logger, mid }, 121)
	local e = events("rune_pickup")
	check("one water pickup", #e == 1, #e)
	check("taker is the nearest own hero", e[1] and field(e[1], "pid") == "2", e[1])
	check("water before 6:00", e[1] and field(e[1], "kind") == "water", e[1])
	tick(H, { logger, mid }, 122)
	check("reported once", #events("rune_pickup") == 1, #events("rune_pickup"))
	RUNES[Rune.Power1] = RUNE_STATUS_AVAILABLE
	tick(H, { logger, mid }, 360)
	RUNES[Rune.Power1] = RUNE_STATUS_MISSING
	tick(H, { logger, mid }, 361)
	local p = events("rune_pickup")[2]
	check("power from 6:00", p and field(p, "kind") == "power", p)
end

-- Rune status is stale across 0:00: nothing is tracked before 1 s.
do
	local H = fresh()
	local a = MakeUnit({ pid = 1, loc = Vector(-1650, 1150) })
	RUNE_SPOTS[Rune.Power1] = Vector(-1700, 1100)
	RUNES[Rune.Power1] = RUNE_STATUS_AVAILABLE
	tick(H, { a }, -5)
	RUNES[Rune.Power1] = RUNE_STATUS_MISSING
	tick(H, { a }, 0.2)
	tick(H, { a }, 1.5)
	check("no pickup across 0:00", #events("rune_pickup") == 0, #events("rune_pickup"))
end

-- No own hero near (fog or an enemy far away took it), or an enemy hero nearer: not this team's pickup.
do
	local H = fresh()
	local a = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	RUNE_SPOTS[Rune.Bounty1] = Vector(3000, 0)
	RUNES[Rune.Bounty1] = RUNE_STATUS_AVAILABLE
	tick(H, { a }, 10)
	RUNES[Rune.Bounty1] = RUNE_STATUS_UNKNOWN
	tick(H, { a }, 11)
	check("no own hero within range: no pickup", #events("rune_pickup") == 0, #events("rune_pickup"))
	a.loc = Vector(2800, 0)
	RUNES[Rune.Bounty1] = RUNE_STATUS_AVAILABLE
	tick(H, { a }, 12)
	ENEMIES = { { loc = Vector(2950, 0) } }
	RUNES[Rune.Bounty1] = RUNE_STATUS_MISSING
	tick(H, { a }, 13)
	check("enemy nearer: left to the enemy logger", #events("rune_pickup") == 0, #events("rune_pickup"))
end

-- The first bot of the team to tick in a frame logs world events, once; a dead lowest-PID bot (no Tick) delays nothing.
do
	local H = fresh()
	local lo = MakeUnit({ pid = 1, loc = Vector(0, 0), alive = false })
	local hi = MakeUnit({ pid = 3, loc = Vector(-1650, 1150) })
	local other = MakeUnit({ pid = 4, loc = Vector(5000, 5000) })
	RUNE_SPOTS[Rune.Power1] = Vector(-1700, 1100)
	RUNES[Rune.Power1] = RUNE_STATUS_AVAILABLE
	tick(H, { hi, other }, 400)
	RUNES[Rune.Power1] = RUNE_STATUS_MISSING
	tick(H, { hi, other }, 401)
	local e = events("rune_pickup")
	check("logged on time while the lowest-PID bot is dead", #e == 1 and field(e[1], "t") == "401", e[1])
	local function ward() return { GetUnitName = function() return "npc_dota_observer_wards" end, GetLocation = function() return Vector(-1600, 1100) end } end
	WARDS = { ward() }
	tick(H, { hi, other }, 402)
	check("two bots in one frame: one ward event", #events("ward_place") == 1, #events("ward_place"))
end

-- A rune that goes out of sight and comes back is re-armed and reported when taken.
do
	local H = fresh()
	local a = MakeUnit({ pid = 1, loc = Vector(-1650, 1150) })
	RUNE_SPOTS[Rune.Power2] = Vector(-1700, 1100)
	RUNES[Rune.Power2] = RUNE_STATUS_AVAILABLE
	a.loc = Vector(0, 0)
	tick(H, { a }, 500)
	RUNES[Rune.Power2] = RUNE_STATUS_UNKNOWN
	tick(H, { a }, 501)
	a.loc = Vector(-1650, 1150)
	RUNES[Rune.Power2] = RUNE_STATUS_AVAILABLE
	tick(H, { a }, 502)
	RUNES[Rune.Power2] = RUNE_STATUS_MISSING
	tick(H, { a }, 503)
	local e = events("rune_pickup")
	check("fog then pickup: one event at the pickup", #e == 1 and field(e[1], "t") == "503", e[1])
end

-- Wards: once each, owner by distance, hero summons skipped.
do
	local H = fresh()
	local sup = MakeUnit({ pid = 1, loc = Vector(100, 0) })
	local function ward(name, x) return { GetUnitName = function() return name end, GetLocation = function() return Vector(x, 0) end } end
	WARDS = { ward("npc_dota_sentry_wards", 400), ward("npc_dota_shadow_shaman_ward_1", 0) }
	tick(H, { sup }, 50)
	tick(H, { sup }, 52)
	local w = events("ward_place")
	check("one ward event (summon skipped, no repeat)", #w == 1, #w)
	check("sentry kind and owner", w[1] and field(w[1], "kind") == "sentry" and field(w[1], "pid") == "1", w[1])
	table.insert(WARDS, ward("npc_dota_observer_wards", 5000))
	tick(H, { sup }, 54)
	local o = events("ward_place")[2]
	check("far ward has no owner", o and field(o, "kind") == "obs" and field(o, "pid") == nil, o)
end

-- Buildings: a known-alive tower that dies or disappears falls once; Roshan kill-time increases are kills.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	local t1 = building()
	TOWERS["2:" .. dota.Tower.Mid1] = t1
	tick(H, { b }, 600)
	t1.dead = true
	tick(H, { b }, 602)
	TOWERS["2:" .. dota.Tower.Mid1] = nil
	tick(H, { b }, 604)
	local f = events("building_fall")
	check("tower falls once", #f == 1, #f)
	check("fall names tier and id", f[1] and field(f[1], "tier") == "1" and field(f[1], "id") == tostring(dota.Tower.Mid1) and field(f[1], "team") == "2", f[1])
	ROSHAN_AT = 1300
	tick(H, { b }, 1301)
	tick(H, { b }, 1303)
	local r = events("roshan_kill")
	check("roshan kill once", #r == 1, #r)
	check("roshan kill time", r[1] and field(r[1], "at") == "1300", r[1])
end

-- Barracks fall like towers, without a tier.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	local rax = building()
	GetBarracks = function(team, id) if team == 2 and id == dota.Barracks.MidMelee then return rax end return nil end
	tick(H, { b }, 900)
	rax.dead = true
	tick(H, { b }, 902)
	local f = events("building_fall")
	check("barracks fall", #f == 1 and field(f[1], "kind") == "rax" and field(f[1], "id") == tostring(dota.Barracks.MidMelee) and field(f[1], "tier") == nil, f[1])
	GetBarracks = function() return nil end
end

-- A Roshan killed before telemetry first looks is not reported.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	ROSHAN_AT = 900
	tick(H, { b }, 1000)
	check("old roshan kill not reported", #events("roshan_kill") == 0, #events("roshan_kill"))
end

-- Hero edges: smoke on, teleport start to landing, aegis picked up.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, loc = Vector(-6000, -6000) })
	tick(H, { b }, 700)
	b.modifiers["modifier_smoke_of_deceit"] = 1
	tick(H, { b }, 700.5)
	tick(H, { b }, 701)
	check("smoke once", #events("smoke_use") == 1, #events("smoke_use"))
	b.modifiers["modifier_teleporting"] = 1
	tick(H, { b }, 702)
	tick(H, { b }, 704)
	b.modifiers["modifier_teleporting"] = nil
	tick(H, { b }, 705)
	b.loc = Vector(-6000, -2000)
	tick(H, { b }, 705.2)
	local tp = events("tp")
	check("one tp", #tp == 1, #tp)
	check("tp from, to, duration", tp[1] and field(tp[1], "fx") == "-6000" and field(tp[1], "y") == "-2000" and field(tp[1], "dur") == "3" and field(tp[1], "dist") == "4000", tp[1])
	b.items = { item_aegis = true }
	tick(H, { b }, 707)
	tick(H, { b }, 709)
	check("aegis once", #events("aegis") == 1, #events("aegis"))
end

-- A cancelled teleport is logged with its short distance; a human's edges come through the team's snapshot loop.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	local human = MakeUnit({ pid = 2, bot = false, loc = Vector(100, 0) })
	tick(H, { b }, 800)
	b.modifiers["modifier_teleporting"] = 1
	human.modifiers["modifier_smoke_of_deceit"] = 1
	tick(H, { b }, 801)
	b.modifiers["modifier_teleporting"] = nil
	tick(H, { b }, 802)
	tick(H, { b }, 802.5)
	local tp = events("tp")
	check("cancelled tp logged short", #tp == 1 and field(tp[1], "dist") == "0", tp[1])
	local sm = events("smoke_use")
	check("human smoke via the team loop", #sm == 1 and field(sm[1], "pid") == "2", sm[1])
end

-- A tracker error is reported as Telemetry.* lua_error and does not stop snapshots.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	local saved = GetRuneStatus
	GetRuneStatus = function() error("boom") end
	tick(H, { b }, 10)
	GetRuneStatus = saved
	local e = events("lua_error")
	check("tracker error reported", e[1] and field(e[1], "where") == "Telemetry.World", e[1])
	check("snapshot still logged", #events("snap") == 1, #events("snap"))
	local saved2 = UnitMeta.HasModifier
	UnitMeta.HasModifier = function() error("bang") end
	tick(H, { b }, 11.5)
	UnitMeta.HasModifier = saved2
	local found = false
	for _, l in ipairs(events("lua_error")) do if field(l, "where") == "Telemetry.Hero" then found = true end end
	check("hero tracker error reported", found)
	check("snapshot logged despite hero error", #events("snap") == 2, #events("snap"))
end

finish()
