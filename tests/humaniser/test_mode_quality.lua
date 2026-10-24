dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Team slice 14: telemetry that tells harmful mode switches from correct ones: each ev=mode carries the threat that
-- could justify it (th) and whether it cut an attack wind-up (cut); ev=dither marks visible back-and-forth walking.
local dota = require("bots/ts_libs/dota/index")
local BotMode = dota.BotMode
local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetMana() return 50 end
function UnitMeta:GetGold() return 600 end
function UnitMeta:GetDenies() return 0 end
function UnitMeta:GetAttackTarget() return nil end

local lines
local function fresh()
	ResetWorld()
	T = 10
	local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	return H
end
local function events(name)
	local r = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) then r[#r + 1] = l end end
	return r
end
local function field(line, key) return line:match(" " .. key .. '="([^"]*)"') or line:match(" " .. key .. "=(%S+)") end

-- A switch with a visible enemy hero near is tagged; one with nothing around reads "-".
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning, loc = Vector(0, 0) })
	H.Telemetry.Tick(b)
	b.mode = BotMode.Retreat
	T = T + 0.1
	H.Telemetry.Tick(b)
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(500, 0) })
	b.GetNearbyHeroes = function() return { enemy } end
	b.mode = BotMode.Laning
	T = T + 0.1
	H.Telemetry.Tick(b)
	local ev = events("mode")
	check("threat: none around", ev[1] ~= nil and field(ev[1], "th") == "-", ev[1])
	check("threat: enemy hero", ev[2] ~= nil and field(ev[2], "th") == "hero", ev[2])
end

-- A switch inside an attack wind-up is a cut; one after the hit point is not.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	b.attackPoint = 0.3
	H.Telemetry.Tick(b)
	b.anim = 1503
	T = T + 0.1
	H.Telemetry.Tick(b)
	b.mode = BotMode.TeamRoam
	T = T + 0.1
	H.Telemetry.Tick(b)
	T = T + 0.4
	H.Telemetry.Tick(b)
	b.mode = BotMode.Laning
	T = T + 0.1
	H.Telemetry.Tick(b)
	local ev = events("mode")
	check("cut: switch 0.1 s into a 0.3 s wind-up", ev[1] ~= nil and field(ev[1], "cut") == "1", ev[1])
	check("cut: switch after the hit point is not", ev[2] ~= nil and field(ev[2], "cut") == "0", ev[2])
end

-- Walking back and forth (300 units each way every second) with nothing around is dithering; the same walk with an
-- enemy hero near, or a steady walk, is not.
local function walk(H, b, legs)
	local x, dir = 0, 1
	for i = 1, legs * 2 do
		x = x + dir * 150
		b.loc = Vector(x, 0)
		T = T + 0.5
		H.Telemetry.Tick(b)
		if i % 2 == 0 then dir = -dir end
	end
end
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning, loc = Vector(0, 0) })
	walk(H, b, 4)
	check("dither: back and forth reported", #events("dither") >= 1, #events("dither"))
	local H2 = fresh()
	local b2 = MakeUnit({ pid = 1, mode = BotMode.Laning, loc = Vector(0, 0) })
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) })
	b2.GetNearbyHeroes = function() return { enemy } end
	walk(H2, b2, 4)
	check("dither: not with an enemy hero near", #events("dither") == 0)
	local H3 = fresh()
	local b3 = MakeUnit({ pid = 1, mode = BotMode.Laning, loc = Vector(0, 0) })
	for i = 1, 8 do b3.loc = Vector(i * 150, 0) T = T + 0.5 H3.Telemetry.Tick(b3) end
	check("dither: a steady walk is not", #events("dither") == 0)
end

finish()
