-- Lane creep deaths (BACKLOG 1.12, WO-025): who got each enemy lane creep, and what each own core was doing.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local UnitType = dota.UnitType

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetLastHits() return self.lh or 0 end
function UnitMeta:GetDenies() return self.dn or 0 end
function UnitMeta:GetAttackTarget() return self.target end
function UnitMeta:GetLastAttackTime() return self.attackAt or -1 end
function UnitMeta:GetGold() return 600 end

CREEPS, ENEMIES = {}, {}
function GetUnitList(kind)
	if kind == UnitType.EnemyCreeps then return CREEPS end
	if kind == UnitType.EnemyHeroes then return ENEMIES end
	return {}
end
function GetTower() return nil end
function GetBarracks() return nil end

local lines
local function fresh()
	ResetWorld()
	CREEPS, ENEMIES = {}, {}
	CURRENT_TEAM = 2
	local H = FreshHumaniser({ Enable = false, Telemetry = { Enable = true } })
	H.Lane.SetHelpers({ GetPosition = function(u) return u.pos end })
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
-- GetLastAttackTime runs on GameTime, which leads DotaTime by the pre-game and hero selection.
local LEAD = 150
function GameTime() return T + LEAD end
local function tick(H, units, t)
	T = t
	for _, u in ipairs(units) do H.Telemetry.Tick(u) end
end
-- A creep handle that raises once removed, as the engine's does (BACKLOG 0.14).
local function creep(name, loc, hp)
	local c = { name = name, loc = loc, hp = hp }
	local function live(f) return function(self, ...) if self.removed then error("Invalid object passed to " .. f) end return self["_" .. f](self, ...) end end
	c._GetUnitName = function(self) return self.name end
	c._GetLocation = function(self) return self.loc end
	c._GetHealth = function(self) return self.hp end
	c._GetMaxHealth = function() return 100 end
	c._IsAlive = function() return true end
	for _, f in ipairs({ "GetUnitName", "GetLocation", "GetHealth", "GetMaxHealth", "IsAlive" }) do c[f] = live(f) end
	table.insert(CREEPS, c)
	return c
end
local function kill(c)
	for i, u in ipairs(CREEPS) do if u == c then table.remove(CREEPS, i) end end
	c.removed = true
end

-- The core's last hit is its own; a creep the core was swinging at but an ally took is the ally's, with the core's state.
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 1
	local sup = MakeUnit({ pid = 2, loc = Vector(100, 0) })
	sup.pos = 5
	local a = creep("npc_dota_creep_badguys_melee", Vector(120, 0), 20)
	local b = creep("npc_dota_creep_badguys_ranged", Vector(150, 50), 30)
	tick(H, { core, sup }, 60)
	core.target, core.attackAt = b, 60.1 + LEAD
	tick(H, { core, sup }, 60.2)
	-- Frame 1: the core kills a.
	kill(a)
	core.lh = 1
	tick(H, { core, sup }, 60.3)
	local e = events("creep_death")
	check("one death", #e == 1, #e)
	check("by the core", e[1] and field(e[1], "by") == "1", e[1])
	check("kind melee", e[1] and field(e[1], "kind") == "melee", e[1])
	check("core distance logged", e[1] and tonumber(field(e[1], "p1d")) == 120, e[1])
	check("core was not targeting a", e[1] and field(e[1], "p1t") == "0", e[1])
	check("support is not a core", e[1] and field(e[1], "p5d") == nil, e[1])
	-- Frame 2: the support takes b while the core's swing on it is under way.
	-- The engine stops returning a removed unit as an attack target.
	kill(b)
	core.target = nil
	sup.lh = 1
	tick(H, { core, sup }, 60.4)
	e = events("creep_death")
	check("second death by the support", #e == 2 and field(e[2], "by") == "2", e[2])
	check("kind ranged", e[2] and field(e[2], "kind") == "ranged", e[2])
	check("core was targeting b", e[2] and field(e[2], "p1t") == "1", e[2])
	check("core's attack on b started 0.3 s before the frame that saw the death", e[2] and math.abs(tonumber(field(e[2], "p1a")) - 0.3) < 1e-6, e[2])
end

-- Practice mode: GetTeamPlayers is empty for the bot-only team; its heroes are still found (GetTeamMember 1..5) and its
-- creep deaths logged (debt getteamplayers-bound: the old loop logged none).
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 1
	local real = GetTeamPlayers
	GetTeamPlayers = function() return {} end
	local a = creep("npc_dota_creep_badguys_melee", Vector(120, 0), 20)
	tick(H, { core }, 60)
	kill(a)
	core.lh = 1
	tick(H, { core }, 60.1)
	GetTeamPlayers = real
	local e = events("creep_death")
	check("bot-only team: death logged", #e == 1, #e)
	check("bot-only team: credited to the core", e[1] and field(e[1], "by") == "1", e[1])
end

-- Creeps that leave vision, enemy denies, creeps far from every hero, other teams' units and the time limit.
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 2
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(300, 0) })
	ENEMIES = { enemy }
	local healthy = creep("npc_dota_creep_badguys_melee", Vector(200, 0), 90)
	local denied = creep("npc_dota_creep_badguys_melee", Vector(250, 0), 10)
	local far = creep("npc_dota_creep_badguys_melee", Vector(5000, 0), 10)
	local neutral = creep("npc_dota_neutral_kobold", Vector(100, 0), 10)
	tick(H, { core }, 100)
	kill(healthy)
	kill(denied)
	kill(far)
	kill(neutral)
	enemy.dn = 1
	local ok, err = pcall(tick, H, { core }, 100.1)
	check("removed creep handles are never read", ok, err)
	local e = events("creep_death")
	check("only the denied creep counts", #e == 1, #e)
	check("its killer is a deny", e[1] and field(e[1], "by") == "deny", e[1])
	check("mid core described as p2", e[1] and field(e[1], "p2d") ~= nil and field(e[1], "p2r") == "150", e[1])
	local s = creep("npc_dota_badguys_siege", Vector(100, 0), 5)
	tick(H, { core }, 100.2)
	kill(s)
	tick(H, { core }, 100.3)
	e = events("creep_death")
	check("a siege death with no counter rise is by none", #e == 2 and field(e[2], "kind") == "siege" and field(e[2], "by") == "none", e[2])
	local late = creep("npc_dota_creep_badguys_melee", Vector(100, 0), 5)
	tick(H, { core }, 721)
	kill(late)
	tick(H, { core }, 721.1)
	check("nothing after CreepDeathUntil", #events("creep_death") == 2, #events("creep_death"))
end

-- A creep logged dead and seen again had left vision: ev=creep_revive. Illusions' deny counters are ignored.
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 1
	local ill = MakeUnit({ pid = 6, team = 3, loc = Vector(100, 0) })
	function ill:IsIllusion() return true end
	ENEMIES = { ill }
	local c = creep("npc_dota_creep_badguys_melee", Vector(100, 0), 10)
	tick(H, { core }, 200)
	for i, u in ipairs(CREEPS) do if u == c then table.remove(CREEPS, i) end end
	ill.dn = 1
	tick(H, { core }, 200.1)
	local e = events("creep_death")
	check("a vanished low creep is logged dead", #e == 1, #e)
	check("an illusion's deny rise is not a deny", e[1] and field(e[1], "by") == "none", e[1])
	table.insert(CREEPS, c)
	tick(H, { core }, 200.2)
	local r = events("creep_revive")
	check("seen again: one creep_revive", #r == 1 and field(r[1], "kind") == "melee", r[1])
	tick(H, { core }, 200.3)
	check("revive logged once", #events("creep_revive") == 1, #events("creep_revive"))
end

finish()
