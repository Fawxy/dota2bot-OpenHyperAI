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

-- Own lane creeps (slice creep-economy): ev=own_creep_death names our own deny; an own creep that dies with no deny rise
-- (an enemy last hit, tower or creep kill) is by none; one above half health that vanishes left vision; far ones, enemy
-- creeps and neutrals are not own deaths.
do
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
	local e = events("own_creep_death")
	check("two own deaths near a hero", #e == 2, #e)
	local byKind = {}
	for _, l in ipairs(e) do byKind[field(l, "kind")] = field(l, "by") end
	check("the melee one was denied by the core", byKind.melee == "1", byKind.melee)
	check("the ranged one died to someone else: by none", byKind.ranged == "none", byKind.ranged)
	check("the enemy creep is a creep_death, not an own death", #events("creep_death") == 1, #events("creep_death"))
	local late = creep("npc_dota_creep_goodguys_melee", Vector(100, 0), 5, OWN)
	tick(H, { core, sup }, 721)
	kill(late)
	tick(H, { core, sup }, 721.1)
	check("nothing after CreepDeathUntil", #events("own_creep_death") == 2, #events("own_creep_death"))
end

-- ev=wave_creep_death (the pull's wave reader): every own lane creep that leaves the list, far from every hero and at any
-- health, with the lane and second it was first seen in; own_creep_death keeps its gates.
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
	-- Both bot creeps walk to the camp, 5,000 from the support, and die there; the top one is denied beside its hero.
	early.loc, early.hp = Vector(5000, -6000), 40
	late.loc, late.hp = Vector(5000, -6000), 80
	tick(H, { sup }, 90)
	kill(early)
	kill(late)
	tick(H, { sup }, 90.1)
	local e = events("wave_creep_death")
	check("both far deaths logged, the healthy one too", #e == 2, #e)
	local byCid = {}
	for _, l in ipairs(e) do byCid[field(l, "kind")] = l end
	check("lane from where it was first seen", field(byCid.melee, "lane") == "bot" and field(byCid.ranged, "lane") == "bot", e[1])
	check("born names each creep's wave", tonumber(field(byCid.melee, "born")) == 30.1 and tonumber(field(byCid.ranged, "born")) == 60.1, e[1])
	check("distance to the nearest hero", tonumber(field(byCid.melee, "nd")) == 5000, field(byCid.melee, "nd"))
	check("far deaths are not own_creep_death", #events("own_creep_death") == 0, #events("own_creep_death"))
	sup.loc = Vector(-6000, 5800)
	top.hp = 20
	tick(H, { sup }, 95)
	kill(top)
	sup.dn = 1
	tick(H, { sup }, 95.1)
	e = events("wave_creep_death")
	check("a denied creep carries its denier", #e == 3 and field(e[3], "by") == "2" and field(e[3], "lane") == "top", e[3])
	check("and is still an own_creep_death", #events("own_creep_death") == 1, #events("own_creep_death"))
	-- A frame whose allied list is missing is skipped: the creeps tracked are not read as gone at full health.
	local held = creep("npc_dota_creep_goodguys_melee", Vector(0, -5900), 100, OWN)
	tick(H, { sup }, 100)
	local list = GetUnitList
	GetUnitList = function(kind) if kind == UnitType.AlliedCreeps then return nil end return list(kind) end
	tick(H, { sup }, 100.1)
	GetUnitList = list
	tick(H, { sup }, 100.2)
	check("no death from a missing list", #events("wave_creep_death") == 3, #events("wave_creep_death"))
	kill(held)
	tick(H, { sup }, 100.3)
	e = events("wave_creep_death")
	check("and the creep is still tracked with its birth", #e == 4 and tonumber(field(e[4], "born")) == 100, e[4])
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

-- Neutral deaths (slice lane-farm-logs): a neutral kill raises GetLastHits, so it shares the claim pool with lane creep deaths.
-- The core's rise goes to the neutral it killed, not to a lane creep that died the same frame within KILLER_NEAR; the neutral
-- names its camp (the nearest spawner box within 1,200) and the nearest own hero. A neutral with no own hero within 1,500, or
-- one that vanished above half HP (left vision), is not logged.
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
	local nd = events("neutral_death")
	local cd = events("creep_death")
	check("neutral: one logged (far and above-half-HP ones are not)", #nd == 1, #nd)
	check("neutral: the core's rise is the neutral's", nd[1] and field(nd[1], "by") == "1", nd[1])
	check("neutral: the lane creep that died beside it is no one's", #cd == 1 and field(cd[1], "by") == "none", cd[1])
	check("neutral: camp 13, nearest hero pid 1 at 100", nd[1] and field(nd[1], "camp") == "13" and field(nd[1], "np") == "1" and field(nd[1], "nd") == "100", nd[1])
	check("neutral: kind neutral", nd[1] and field(nd[1], "kind") == "neutral", nd[1])
	core.loc = Vector(2500, 0)
	tick(H, { core }, 60.2)
	kill(anc)
	tick(H, { core }, 60.3)
	nd = events("neutral_death")
	check("neutral: an ancient beyond 1,200 of every camp has no camp, kind ancient, no one's", #nd == 2 and field(nd[2], "camp") == nil and field(nd[2], "kind") == "ancient" and field(nd[2], "by") == "none", nd[2])
	-- A neutral that left vision at half HP or less was logged dead; seen alive again it is named by ev=creep_revive.
	local hidden = creep("npc_dota_neutral_kobold", Vector(2600, 0), 30, NEUTRALS)
	tick(H, { core }, 60.4)
	table.remove(NEUTRALS, #NEUTRALS)
	tick(H, { core }, 60.5)
	check("neutral: one that vanished at 30% is logged", #events("neutral_death") == 3, #events("neutral_death"))
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
	check("unit: and its neutral_death names the same taker", field(events("neutral_death")[1], "by") == "1", events("neutral_death")[1])
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
	check("own: the old own-creep events agree on the denier", #events("own_creep_death") == 1 and field(events("own_creep_death")[1], "by") == "2", events("own_creep_death")[1])
	GetAmountAlongLane = keep
end

finish()
