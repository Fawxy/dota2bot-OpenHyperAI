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
function UnitMeta:GetNetWorth() return 1200 end
function UnitMeta:GetXPNeededToLevel() return 200 end

CREEPS, ENEMIES, OWN, NEUTRALS = {}, {}, {}, {}
function GetUnitList(kind)
	if kind == UnitType.EnemyCreeps then return CREEPS end
	if kind == UnitType.NeutralCreeps then return NEUTRALS end
	if kind == UnitType.AlliedCreeps then return OWN end
	if kind == UnitType.EnemyHeroes then return ENEMIES end
	return {}
end
function GetTower() return nil end
function GetBarracks() return nil end

local lines
local function fresh()
	ResetWorld()
	CREEPS, ENEMIES, OWN, NEUTRALS = {}, {}, {}, {}
	CURRENT_TEAM = 2
	local H = FreshHumaniser({ Enable = false, Telemetry = { Enable = true } })
	H.LaneConfig.SetHelpers({ GetPosition = function(u) return u.pos end })
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
local function creep(name, loc, hp, list)
	local c = { name = name, loc = loc, hp = hp }
	local function live(f) return function(self, ...) if self.removed then error("Invalid object passed to " .. f) end return self["_" .. f](self, ...) end end
	c._GetUnitName = function(self) return self.name end
	c._GetLocation = function(self) return self.loc end
	c._GetHealth = function(self) return self.hp end
	c._GetMaxHealth = function() return 100 end
	c._IsAlive = function(self) return self.dead ~= true end
	c._IsNull = function() return false end
	c._IsAncientCreep = function(self) return self.ancient == true end
	for _, f in ipairs({ "GetUnitName", "GetLocation", "GetHealth", "GetMaxHealth", "IsAlive", "IsAncientCreep", "IsNull" }) do c[f] = live(f) end
	table.insert(list or CREEPS, c)
	return c
end
local function kill(c)
	for _, l in ipairs({ CREEPS, OWN, NEUTRALS }) do
		for i, u in ipairs(l) do if u == c then table.remove(l, i) end end
	end
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

-- tw: one of our towers was attacking the creep on the frame before it died (row "Last-hit refinement"). The tower's target
-- is read for the next frame's deaths, so a creep it takes only on the death frame is tw=0; an enemy team's tower is not ours.
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 1
	local tower = { target = nil, IsAlive = function() return true end }
	function tower:GetAttackTarget() return self.target end
	local theirs = { IsAlive = function() return true end }
	local a = creep("npc_dota_creep_badguys_melee", Vector(120, 0), 20)
	local b = creep("npc_dota_creep_badguys_melee", Vector(150, 0), 20)
	theirs.GetAttackTarget = function() return b end
	local real = GetTower
	GetTower = function(team, id) if id == 0 then return team == 2 and tower or theirs end end
	tower.target = a
	tick(H, { core }, 60)
	kill(a)
	tower.target = b
	tick(H, { core }, 60.1)
	local e = events("creep_death")
	check("tw: the tower's creep is tw=1, no one's", #e == 1 and field(e[1], "tw") == "1" and field(e[1], "by") == "none", e[1])
	tick(H, { core }, 60.2)
	kill(b)
	core.lh = 1
	tick(H, { core }, 60.3)
	e = events("creep_death")
	check("tw: our last hit under the tower keeps tw=1", #e == 2 and field(e[2], "tw") == "1" and field(e[2], "by") == "1", e[2])
	local c = creep("npc_dota_creep_badguys_melee", Vector(130, 0), 20)
	tick(H, { core }, 60.4)
	tower.target = c
	kill(c)
	tick(H, { core }, 60.5)
	e = events("creep_death")
	check("tw: targeted only on the death frame is tw=0", #e == 3 and field(e[3], "tw") == "0", e[3])
	GetTower = real
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

-- Own lane creeps: ev=unit_gone names our own deny; an own creep that dies with no deny rise (an enemy last hit, tower or creep
-- kill) is by none. It is gone wherever it was and at any health (a team sees its own creeps everywhere), and enemy creeps and
-- neutrals are not own units. The old own/wave/neutral death events are no longer written.
do
	local keep = GetAmountAlongLane
	GetAmountAlongLane = function(lane, loc)
		local y = lane == dota.Lane.Bot and -6000 or lane == dota.Lane.Top and 6000 or 0
		return { amount = 0.5, distance = math.abs(loc.y - y) }
	end
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 1
	local sup = MakeUnit({ pid = 2, loc = Vector(100, 0) })
	sup.pos = 5
	local denied = creep("npc_dota_creep_goodguys_melee", Vector(150, 0), 30, OWN)
	local taken = creep("npc_dota_creep_goodguys_ranged", Vector(-200, 0), 20, OWN)
	local healthy = creep("npc_dota_creep_goodguys_melee", Vector(120, 0), 90, OWN)
	local far = creep("npc_dota_creep_goodguys_melee", Vector(5000, 0), 10, OWN)
	local theirs = creep("npc_dota_creep_badguys_melee", Vector(100, 0), 10)
	tick(H, { core, sup }, 100)
	kill(denied)
	kill(taken)
	kill(healthy)
	kill(far)
	kill(theirs)
	core.dn = 1
	local ok, err = pcall(tick, H, { core, sup }, 100.1)
	check("removed own creep handles are never read", ok, err)
	local e = events("unit_gone")
	check("every own creep that left is gone, far and healthy ones too", #e == 4, #e)
	local byX = {}
	for _, l in ipairs(e) do byX[field(l, "x")] = field(l, "by") end
	check("the nearest low creep was denied by the core", byX["150"] == "1", byX["150"])
	check("the ranged one died to someone else: by none", byX["-200"] == "none", byX["-200"])
	check("a healthy creep that left is never claimed", byX["120"] == "none", byX["120"])
	check("the enemy creep is a creep_death, not an own unit", #events("creep_death") == 1, #events("creep_death"))
	check("the three old death events are not written", #events("own_creep_death") == 0 and #events("wave_creep_death") == 0 and #events("neutral_death") == 0, #events("own_creep_death"))
	local late = creep("npc_dota_creep_goodguys_melee", Vector(100, 0), 5, OWN)
	tick(H, { core, sup }, 721)
	kill(late)
	tick(H, { core, sup }, 721.1)
	check("nothing after CreepDeathUntil", #events("unit_gone") == 4, #events("unit_gone"))
	GetAmountAlongLane = keep
end

-- Far deaths and the wave reader's facts: an own creep that leaves the list far from every hero is gone with its lane (on its
-- unit_seen); one denied beside its hero carries the denier; a frame with no allied list is skipped, not read as deaths.
do
	local keep = GetAmountAlongLane
	-- The bot lane runs along y = -6000, the top along y = 6000.
	GetAmountAlongLane = function(lane, loc)
		local y = lane == dota.Lane.Bot and -6000 or lane == dota.Lane.Top and 6000 or 0
		return { amount = 0.5, distance = math.abs(loc.y - y) }
	end
	local H = fresh()
	local sup = MakeUnit({ pid = 2, loc = Vector(0, -6000) })
	sup.pos = 5
	local early = creep("npc_dota_creep_goodguys_melee", Vector(-6000, -5900), 100, OWN)
	tick(H, { sup }, 30.1)
	local late = creep("npc_dota_creep_goodguys_ranged", Vector(-6000, -5900), 100, OWN)
	local top = creep("npc_dota_creep_goodguys_melee", Vector(-6000, 5900), 100, OWN)
	tick(H, { sup }, 60.1)
	local seen = events("unit_seen")
	local lanes = {}
	for _, l in ipairs(seen) do lanes[field(l, "kind") == "lane" and field(l, "type") .. field(l, "y")] = field(l, "lane") end
	check("each unit_seen names the lane it was first seen in", #seen == 3 and lanes["creep_goodguys_melee-5900"] == "bot" and lanes["creep_goodguys_melee5900"] == "top", #seen)
	-- Both bot creeps walk to the camp, 5,000 from the support, and die there; the top one is denied beside its hero.
	early.loc, early.hp = Vector(5000, -6000), 40
	late.loc, late.hp = Vector(5000, -6000), 80
	tick(H, { sup }, 90)
	kill(early)
	kill(late)
	tick(H, { sup }, 90.1)
	local e = events("unit_gone")
	check("both far deaths logged, the healthy one too", #e == 2, #e)
	sup.loc = Vector(-6000, 5800)
	top.hp = 20
	tick(H, { sup }, 95)
	kill(top)
	sup.dn = 1
	tick(H, { sup }, 95.1)
	e = events("unit_gone")
	check("a denied creep carries its denier", #e == 3 and field(e[3], "by") == "2", e[3])
	-- A frame whose allied list is missing is skipped: the creeps tracked are not read as gone at full health.
	local held = creep("npc_dota_creep_goodguys_melee", Vector(0, -5900), 100, OWN)
	tick(H, { sup }, 100)
	local list = GetUnitList
	GetUnitList = function(kind) if kind == UnitType.AlliedCreeps then return nil end return list(kind) end
	tick(H, { sup }, 100.1)
	GetUnitList = list
	tick(H, { sup }, 100.2)
	check("no death from a missing list", #events("unit_gone") == 3, #events("unit_gone"))
	kill(held)
	tick(H, { sup }, 100.3)
	check("and the creep is still tracked", #events("unit_gone") == 4, #events("unit_gone"))
	GetAmountAlongLane = keep
end


-- A neutral listed with no location (the engine gives a fogged or dying handle none): the creep read skips it, no error
-- (cnghar2_B_harness_5 t=624.0: `lua_error` in Telemetry.Creeps).
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(900, 0) })
	core.pos = 1
	local blind = creep("npc_dota_neutral_kobold", nil, 10, NEUTRALS)
	local ok, err = pcall(tick, H, { core }, 60)
	check("neutral: one with no location is skipped without an error", ok, err)
	kill(blind)
end

-- Neutral deaths: a neutral kill raises GetLastHits, so it shares the claim pool with lane creep deaths. The core's rise goes
-- to the neutral it killed, not to a lane creep that died the same frame within KILLER_NEAR (the neutral's unit_gone carries
-- the taker). A neutral with no own hero within 1,500, or one that vanished above half HP, takes no rise. One that left vision at
-- half HP or less and is listed again is a creep_revive.
do
	local realSpawners = GetNeutralSpawners
	GetNeutralSpawners = function()
		return { [13] = { team = 2, type = "small", location = Vector(1000, 0), min = Vector(900, -100), max = Vector(1100, 100) } }
	end
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(900, 0) })
	core.pos = 1
	local lane = creep("npc_dota_creep_badguys_melee", Vector(300, 0), 20)
	local n = creep("npc_dota_neutral_kobold", Vector(1000, 0), 10, NEUTRALS)
	local far = creep("npc_dota_neutral_kobold", Vector(5000, 0), 10, NEUTRALS)
	local fled = creep("npc_dota_neutral_kobold", Vector(1050, 0), 80, NEUTRALS)
	local anc = creep("npc_dota_neutral_black_drake", Vector(3000, 0), 10, NEUTRALS)
	anc.ancient = true
	tick(H, { core }, 60)
	kill(lane)
	kill(n)
	kill(far)
	kill(fled)
	core.lh = 1
	tick(H, { core }, 60.1)
	local byX = {}
	for _, l in ipairs(events("unit_gone")) do byX[field(l, "x")] = field(l, "by") end
	local cd = events("creep_death")
	check("neutral: the core's rise is the near neutral's", byX["1000"] == "1", byX["1000"])
	check("neutral: far and above-half-HP ones take no rise", byX["5000"] == "none" and byX["1050"] == "none", byX["5000"])
	check("neutral: the lane creep that died beside it is no one's", #cd == 1 and field(cd[1], "by") == "none", cd[1])
	-- A neutral that left vision at half HP or less was claimed as dead; seen alive again it is named by ev=creep_revive.
	core.loc = Vector(2500, 0)
	local hidden = creep("npc_dota_neutral_kobold", Vector(2600, 0), 30, NEUTRALS)
	tick(H, { core }, 60.4)
	table.remove(NEUTRALS, #NEUTRALS)
	tick(H, { core }, 60.5)
	table.insert(NEUTRALS, hidden)
	tick(H, { core }, 60.6)
	local rv = events("creep_revive")
	check("neutral: seen again, creep_revive kind neutral", #rv == 1 and field(rv[1], "kind") == "neutral", rv[1])
	GetNeutralSpawners = realSpawners
end

-- ev=unit_seen / ev=unit_gone: one row per own lane creep, and per neutral. A neutral that leaves the list alive (out of
-- vision) is held: not a death, and not seen again when it returns; found dead only by its own handle.
do
	local realSpawners = GetNeutralSpawners
	GetNeutralSpawners = function()
		return { [13] = { team = 2, type = "small", location = Vector(1000, 0), min = Vector(900, -100), max = Vector(1100, 100) } }
	end
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(900, 0) })
	core.pos = 1
	local function unlist(c)
		for i, u in ipairs(NEUTRALS) do if u == c then table.remove(NEUTRALS, i) break end end
	end
	local n = creep("npc_dota_neutral_kobold", Vector(1000, 0), 90, NEUTRALS)
	creep("npc_dota_xp_fountain", Vector(1000, 0), 100, NEUTRALS)
	tick(H, { core }, 60)
	local seen = events("unit_seen")
	check("unit: a neutral is seen once, with its name and camp; a map fixture in the list is no unit", #seen == 1 and field(seen[1], "kind") == "neutral" and field(seen[1], "type") == "neutral_kobold" and field(seen[1], "camp") == "13", seen[1])
	-- out of vision, alive: its handle is still valid
	unlist(n)
	tick(H, { core }, 60.1)
	tick(H, { core }, 61)
	check("unit: out of sight alive is not gone", #events("unit_gone") == 0, events("unit_gone")[1])
	table.insert(NEUTRALS, n)
	tick(H, { core }, 62)
	check("unit: back in sight is the same unit", #events("unit_seen") == 1 and #events("unit_gone") == 0, #events("unit_seen"))
	-- out of sight again, then found dead later: hid=1, the last spot and health it was listed with
	unlist(n)
	tick(H, { core }, 62.1)
	n.dead = true
	tick(H, { core }, 62.2)
	check("unit: dead out of sight is not found before the recheck", #events("unit_gone") == 0, #events("unit_gone"))
	tick(H, { core }, 63)
	local gone = events("unit_gone")
	check("unit: found dead later is hid=1 with its last spot", #gone == 1 and field(gone[1], "hid") == "1" and field(gone[1], "x") == "1000" and field(gone[1], "by") == "none", gone[1])
	tick(H, { core }, 64)
	check("unit: written once", #events("unit_gone") == 1, #events("unit_gone"))
	-- killed in sight by the core: its handle is removed on the frame it leaves the list, and the core's rise is the taker
	local k = creep("npc_dota_neutral_kobold", Vector(1000, 50), 10, NEUTRALS)
	tick(H, { core }, 70)
	kill(k)
	core.lh = 1
	tick(H, { core }, 70.1)
	gone = events("unit_gone")
	check("unit: killed in sight is gone at once, hid=0, by the core", #gone == 2 and field(gone[2], "hid") == "0" and field(gone[2], "by") == "1", gone[2])
	GetNeutralSpawners = realSpawners
end

-- An own lane creep: seen once with the unit's own name (a flag bearer shows) and the lane; gone on the frame it leaves the list
-- wherever it was, with our deny as the taker (an enemy hero's last hits read -1 from our side).
do
	local H = fresh()
	local keep = GetAmountAlongLane
	GetAmountAlongLane = function(lane, loc)
		local y = lane == dota.Lane.Bot and -6000 or lane == dota.Lane.Top and 6000 or 0
		return { amount = 0.5, distance = math.abs(loc.y - y) }
	end
	local sup = MakeUnit({ pid = 2, loc = Vector(0, -6000) })
	sup.pos = 5
	local flag = creep("npc_dota_creep_goodguys_melee_flagbearer", Vector(-6000, -5900), 100, OWN)
	local far = creep("npc_dota_creep_goodguys_ranged", Vector(5000, -6000), 40, OWN)
	local denied = creep("npc_dota_creep_goodguys_melee", Vector(0, -5900), 30, OWN)
	tick(H, { sup }, 100)
	local seen = events("unit_seen")
	local byType = {}
	for _, l in ipairs(seen) do byType[field(l, "type")] = l end
	check("own: three seen, flag bearer named by the unit", #seen == 3 and byType["creep_goodguys_melee_flagbearer"] ~= nil and field(byType["creep_goodguys_ranged"], "lane") == "bot", #seen)
	tick(H, { sup }, 100.1)
	check("own: each is seen once", #events("unit_seen") == 3, #events("unit_seen"))
	kill(far)
	kill(denied)
	sup.dn = 1
	tick(H, { sup }, 100.2)
	local gone = events("unit_gone")
	local farLine, denLine
	for _, l in ipairs(gone) do if field(l, "x") == "5000" then farLine = l else denLine = l end end
	check("own: two gone, one of them 5,000 from every own hero", #gone == 2 and farLine ~= nil and denLine ~= nil, #gone)
	check("own: the far one has no taker we can read", farLine and field(farLine, "by") == "none", farLine)
	check("own: our deny keeps its pid", denLine and field(denLine, "by") == "2", denLine)
	GetAmountAlongLane = keep
end

-- A fixture in the neutral list is classified once, not every frame; a neutral found dead whose handle read errored and is listed
-- again keeps one unit_seen and one unit_gone; and a neutral found dead after it left the list (a stale spot) neither takes a
-- hero's last-hit rise from a lane creep that died nearby nor names a taker itself.
do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(900, 0) })
	core.pos = 1
	local fix = creep("npc_dota_xp_fountain", Vector(1000, 0), 100, NEUTRALS)
	local reads = 0
	local nameOf = fix._GetUnitName
	fix._GetUnitName = function(self) reads = reads + 1 return nameOf(self) end
	local flaky = creep("npc_dota_neutral_kobold", Vector(1000, 0), 90, NEUTRALS)
	tick(H, { core }, 60)
	tick(H, { core }, 60.1)
	tick(H, { core }, 60.2)
	check("unit: a fixture's name is read once", reads == 1, reads)
	-- its handle check errors while it is out of the list: logged gone; listed again, it is the same unit, not a new one
	flaky._IsNull = function() error("invalid handle") end
	for i, u in ipairs(NEUTRALS) do if u == flaky then table.remove(NEUTRALS, i) break end end
	tick(H, { core }, 60.3)
	check("unit: an errored handle check is a gone", #events("unit_gone") == 1, #events("unit_gone"))
	table.insert(NEUTRALS, flaky)
	tick(H, { core }, 60.4)
	for i, u in ipairs(NEUTRALS) do if u == flaky then table.remove(NEUTRALS, i) break end end
	tick(H, { core }, 60.5)
	tick(H, { core }, 61.5)
	check("unit: listed again it keeps one seen and one gone", #events("unit_seen") == 1 and #events("unit_gone") == 1, #events("unit_seen") .. "/" .. #events("unit_gone"))
end

do
	local H = fresh()
	local core = MakeUnit({ pid = 1, loc = Vector(0, 0) })
	core.pos = 1
	local n = creep("npc_dota_neutral_kobold", Vector(100, 0), 30, NEUTRALS)
	tick(H, { core }, 60)
	for i, u in ipairs(NEUTRALS) do if u == n then table.remove(NEUTRALS, i) break end end
	tick(H, { core }, 60.1)
	local lane = creep("npc_dota_creep_badguys_melee", Vector(300, 0), 20)
	tick(H, { core }, 60.2)
	-- the hidden neutral dies out of sight and is noticed on the frame the core last-hits the lane creep
	n.dead = true
	kill(lane)
	core.lh = 1
	tick(H, { core }, 61)
	local cd = events("creep_death")
	check("unit: a neutral found dead after being held does not take the core's rise", #cd == 1 and field(cd[1], "by") == "1", cd[1])
	local gone = events("unit_gone")
	check("unit: and it is logged hid=1 with no taker", #gone == 1 and field(gone[1], "hid") == "1" and field(gone[1], "by") == "none", gone[1])
end

-- An own creep that left the list and is listed again (a change of owner) keeps one unit_seen and one unit_gone.
do
	local H = fresh()
	local keep = GetAmountAlongLane
	GetAmountAlongLane = function(lane, loc)
		local y = lane == dota.Lane.Bot and -6000 or lane == dota.Lane.Top and 6000 or 0
		return { amount = 0.5, distance = math.abs(loc.y - y) }
	end
	local sup = MakeUnit({ pid = 2, loc = Vector(0, -6000) })
	sup.pos = 5
	local c = creep("npc_dota_creep_goodguys_melee", Vector(-6000, -5900), 100, OWN)
	tick(H, { sup }, 100)
	table.remove(OWN, 1)
	tick(H, { sup }, 100.1)
	table.insert(OWN, c)
	tick(H, { sup }, 100.2)
	table.remove(OWN, 1)
	tick(H, { sup }, 100.3)
	check("own: listed again, one seen and one gone", #events("unit_seen") == 1 and #events("unit_gone") == 1, #events("unit_seen") .. "/" .. #events("unit_gone"))
	GetAmountAlongLane = keep
end

finish()
