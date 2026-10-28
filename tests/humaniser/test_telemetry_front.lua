-- Lane-front fields (slice 2b): ev=front per team and ln/s/ld in ev=snap, in absolute amounts (0 = Radiant's ancient)
-- whichever team's script writes the line; lane_world answers lane amounts in the caller's frame, as the game does.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetLastHits() return 0 end
function UnitMeta:GetDenies() return 0 end
function UnitMeta:GetAttackTarget() return nil end
function UnitMeta:GetGold() return 600 end
function UnitMeta:FindItemSlot() return -1 end
function GetRuneStatus() return 2 end
function GetRuneSpawnLocation() return Vector(9000, 9000) end
function GetRoshanKillTime() return 0 end
function GetBarracks() return nil end
RUNE_STATUS_AVAILABLE = 1

local lines
local function fresh()
	ResetWorld()
	LANE_FRONT = { [2] = {}, [3] = {} }
	local H = FreshHumaniser({ Enable = false, Telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	return H
end
local function events(name, key, value)
	local r = {}
	for _, l in ipairs(lines) do
		if l:find(" ev=" .. name .. " ", 1, true) and (key == nil or l:match(" " .. key .. "=(%S+)") == value) then table.insert(r, l) end
	end
	return r
end
local function field(line, key) return line and line:match(" " .. key .. "=(%S+)") end

-- Each team logs its own fronts once per interval; the same game state reads the same from either team's script.
for _, caller in ipairs({ 2, 3 }) do
	local H = fresh()
	LANE_FRONT[2][Lane.Mid] = 0.4 -- Radiant's mid wave 40% of the way to Dire's ancient
	LANE_FRONT[3][Lane.Mid] = 0.3 -- Dire's mid wave 30% of the way to Radiant's: absolute 0.7
	LANE_FRONT[2][Lane.Top] = 0.25
	CURRENT_TEAM = caller
	local hero = MakeUnit({ pid = caller * 10, team = caller, loc = Vector(0, 4900) })
	T = 60
	H.Telemetry.Tick(hero)
	local tag = "caller " .. caller .. ": "
	local f = events("front", "team", tostring(caller))
	check(tag .. "one ev=front for the caller's team", #f == 1 and #events("front") == 1, #f)
	local want = caller == 2 and { mid = "0.400", midx = "-1400", top = "0.250", topy = "5000" } or { mid = "0.700", midx = "2800", top = "0.500", topy = "5000" }
	for k, v in pairs(want) do check(tag .. "front " .. k, field(f[1], k) == v, f[1]) end
	local s = events("snap", "pid", tostring(caller * 10))[1]
	check(tag .. "snap ln is the nearest lane", field(s, "ln") == "top", s)
	check(tag .. "snap s is absolute", field(s, "s") == "0.500", s)
	check(tag .. "snap ld", field(s, "ld") == "100", s)
	-- The Radiant-side hero reads the same from either script.
	local west = MakeUnit({ pid = caller * 10 + 1, team = caller, loc = Vector(-5600, -4800) })
	T = 62
	H.Telemetry.Tick(west)
	local w = events("snap", "pid", tostring(caller * 10 + 1))[1]
	check(tag .. "west hero s=0.100 on bot", field(w, "s") == "0.100" and field(w, "ln") == "bot", w)
	check(tag .. "front again after the interval", #events("front", "team", tostring(caller)) == 2, #events("front"))
end

-- A failing lane read drops only the lane fields and the front event, reported under their own guards (review L1, L2).
do
	local H = fresh()
	CURRENT_TEAM = 2
	local hero = MakeUnit({ pid = 5, team = 2, loc = Vector(0, 0) })
	local keep = GetAmountAlongLane
	GetAmountAlongLane = function() error("boom") end
	T = 100
	H.Telemetry.Tick(hero)
	GetAmountAlongLane = keep
	local s = events("snap", "pid", "5")[1]
	check("snap still logged without lane fields", s ~= nil and field(s, "ln") == nil and field(s, "hp") ~= nil, s)
	local where = {}
	for _, l in ipairs(events("lua_error")) do where[field(l, "where")] = true end
	check("errors under Telemetry.Lane and Telemetry.Front", where["Telemetry.Lane"] and where["Telemetry.Front"], table.concat(lines, "\n"))
	check("no ev=front", #events("front") == 0, #events("front"))
end

finish()
