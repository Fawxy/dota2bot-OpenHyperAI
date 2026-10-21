-- Plays a short scripted session through the real humaniser modules with telemetry on and returns the
-- [HEV] lines in HLOG_LINES. Driven from tools/hlog/test/hlog.test.js to check the Lua -> analyser contract.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode, Lane, UnitType = dota.BotMode, dota.Lane, dota.UnitType

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetMostRecentPing() return { time = 0, location = Vector(0, 0), normal_ping = true } end
function UnitMeta:ActionImmediate_Ping() end
function UnitMeta:FindItemSlot() return -1 end
function UnitMeta:GetAttackTarget() return self.target end
function UnitMeta:GetLastHits() return self.lh or 0 end
function UnitMeta:GetDenies() return self.dn or 0 end
function UnitMeta:GetMana() return 50 end
function UnitMeta:GetMaxMana() return 100 end
function UnitMeta:GetGold() return 600 end
function UnitMeta:ActionImmediate_Chat() end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
function GetUnitList(t) return {} end
local FRONTS = { [Lane.Top] = Vector(-6000, 2000), [Lane.Mid] = Vector(0, 0), [Lane.Bot] = Vector(4000, -6000) }
function GetLaneFrontLocation(team, lane) return FRONTS[lane] end
function GetAncient() return { loc = Vector(-6000, -6000), GetLocation = function(self) return self.loc end, IsAlive = function() return true end, GetHealth = function() return 4500 end } end
function GetTower() return nil end

ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
HLOG_LINES = {}
H.Telemetry.SetSink(function(line) table.insert(HLOG_LINES, line) end)

MakeUnit({ pid = 0, bot = false, loc = Vector(0, 0) })
local bots = { MakeUnit({ pid = 1, loc = Vector(500, 0), mode = BotMode.Laning }), MakeUnit({ pid = 2, loc = Vector(900, 0), mode = BotMode.Farm }) }
H.Chat.EnsureInstalled(bots[1])

local function tick(t)
	T = t
	for _, b in ipairs(bots) do
		H.Commands.Tick(b)
		H.Orders.GetFor(b)
		H.Telemetry.Tick(b)
		-- Bots that accepted the defend order switch to it, as the mode files would.
		if H.Orders.GetFor(b) ~= nil then b.mode = BotMode.DefendTowerMid end
	end
end
local function say(text)
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = 0, string = text, team_only = true }) end
end

for i = 0, 50 do tick(i * 0.1) end
say("!def mid")
for i = 51, 120 do tick(i * 0.1) end
say("!mark bots went mid")
for i = 121, 160 do tick(i * 0.1) end
