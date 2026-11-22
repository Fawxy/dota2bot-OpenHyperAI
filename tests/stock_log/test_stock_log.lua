-- stock_log's ledger events: named cases, parity with team-bots' telemetry, and unchanged bot/snap lines.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local M = { NONE = 0, LANING = 1, ATTACK = 2, ROAM = 3, RETREAT = 4, SECRET_SHOP = 5, SIDE_SHOP = 6, RUNE = 7, PUSH_TOWER_TOP = 8,
	PUSH_TOWER_MID = 9, PUSH_TOWER_BOT = 10, DEFEND_TOWER_TOP = 11, DEFEND_TOWER_MID = 12, DEFEND_TOWER_BOT = 13, ASSEMBLE = 14,
	TEAM_ROAM = 16, FARM = 17, DEFEND_ALLY = 18, EVASIVE_MANEUVERS = 19, ROSHAN = 20, ITEM = 21, WARD = 22 }
for name, v in pairs(M) do _G["BOT_MODE_" .. name] = v end
UNIT_LIST_ALLIED_CREEPS, UNIT_LIST_ALLIED_WARDS, UNIT_LIST_ENEMY_HEROES, UNIT_LIST_ENEMY_CREEPS, UNIT_LIST_NEUTRAL_CREEPS = 3, 4, 8, 9, 13
RUNE_POWERUP_1, RUNE_POWERUP_2, RUNE_BOUNTY_1, RUNE_BOUNTY_2, RUNE_BOUNTY_3, RUNE_BOUNTY_4 = 0, 1, 2, 3, 4, 5
RUNE_STATUS_UNKNOWN, RUNE_STATUS_AVAILABLE, RUNE_STATUS_MISSING = 0, 1, 2

local U = getmetatable(MakeUnit({ pid = 99 })).__index
function U:GetLastHits() return self.lh or 0 end
function U:GetDenies() return self.dn or 0 end
function U:GetAttackTarget() return nil end
function U:GetLastAttackTime() return -1 end
function U:GetGold() if self.badGold then error("bad gold") end return 600 end
function U:GetNetWorth() return self.nw or 1200 end
function U:GetXPNeededToLevel() return 200 end
function U:GetItemInSlot(i) if self.badItem then error("bad slot") end return self.slots and self.slots[i] or nil end
function GetHeroKills() return 0 end
function GetHeroDeaths() return 0 end
function GetTower() return nil end
function GetBarracks() return nil end
function GetNeutralSpawners() return {} end
function GetRoshanKillTime() return 0 end
function GameTime() return T + 150 end

local lists, status, spots, badList
function GetUnitList(k)
	if badList ~= nil and k == badList then error("bad list " .. k) end
	return lists[k] or {}
end
function GetRuneStatus(r) return status[r] or 2 end
function GetRuneSpawnLocation(r) return spots[r] or Vector(9000, 9000) end

local function reset(team)
	ResetWorld()
	lists, status, spots, badList = { [3] = {}, [8] = {}, [9] = {}, [13] = {} }, {}, {}, nil
	CURRENT_TEAM = team or 2
end

local Utils = require("bots/FunLib/utils")
package.loaded["bots/FunLib/jmz_func"] = { GetPosition = function() return 1 end }

local function stock(file)
	local L = assert(loadfile(file or STOCK_FILE))()
	local mine = {}
	local tick = function(b)
		Utils.RawPrint = function(s) table.insert(mine, s) end
		L.Tick(b)
	end
	return tick, mine
end
local function of(lines, ev)
	local r = {}
	for _, l in ipairs(lines) do if l:match(" ev=(%S+)") == ev then table.insert(r, l) end end
	return r
end
local function field(l, k)
	if not l then return nil end
	return l:match(" " .. k .. '="([^"]*)"') or l:match(" " .. k .. "=(%S+)")
end
local function creep(list, x, y, hp, name)
	local c = { loc = Vector(x, y), hp = hp, name = name or "npc_dota_creep_badguys_melee" }
	local function live(v) if c.removed then error("removed handle") end return v end
	c.GetUnitName = function() return live(c.name) end
	c.GetLocation = function() return live(c.loc) end
	c.GetHealth = function() return live(c.hp) end
	c.GetMaxHealth = function() return live(100) end
	c.IsAlive = function() return live(true) end
	c.IsAncientCreep = function() return live(c.ancient == true) end
	table.insert(lists[list], c)
	return c
end
local function kill(list, c)
	for i, u in ipairs(lists[list]) do if u == c then table.remove(lists[list], i) break end end
	c.removed = true
end
local function frame(tick, at)
	T = at
	for _, u in ipairs(UNITS[CURRENT_TEAM]) do if u.alive then tick(u) end end
end
local function item(name, n)
	return { GetName = function() return "item_" .. name end, GetCurrentCharges = function() return n or 0 end }
end

do -- lane last hit
	reset()
	local tick, log = stock()
	local h = MakeUnit({ pid = 1 })
	MakeUnit({ pid = 2, loc = Vector(900, 0) })
	local c = creep(9, 120, 5, 20)
	frame(tick, 60); kill(9, c); h.lh = 1; frame(tick, 60.1)
	local e = of(log, "creep_death")
	check("lane death: logged once for two bots", #e == 1, #e)
	check("lane death: team, kind, place, taker", field(e[1], "team") == "2" and field(e[1], "kind") == "melee"
		and field(e[1], "x") == "120" and field(e[1], "y") == "5" and field(e[1], "by") == "1", e[1])
end

do -- ranged, siege, unclaimed
	reset()
	local tick, log = stock()
	MakeUnit({ pid = 1 })
	local r = creep(9, 100, 0, 20, "npc_dota_creep_badguys_ranged")
	local s = creep(9, 200, 0, 20, "npc_dota_badguys_siege")
	frame(tick, 60); kill(9, r); frame(tick, 60.1); kill(9, s); frame(tick, 60.2)
	local e = of(log, "creep_death")
	check("ranged, nobody's", field(e[1], "kind") == "ranged" and field(e[1], "by") == "none", e[1])
	check("siege", field(e[2], "kind") == "siege", e[2])
end

do -- what is no death
	reset()
	local tick, log = stock()
	MakeUnit({ pid = 1 })
	local full, far = creep(9, 100, 0, 90), creep(9, 5000, 0, 20)
	frame(tick, 60); kill(9, full); kill(9, far); frame(tick, 60.1)
	check("out of vision or far from us: no death", #of(log, "creep_death") == 0)
	local late = creep(9, 100, 0, 20)
	frame(tick, 720.1); kill(9, late); frame(tick, 720.2)
	check("nothing after 720 s", #of(log, "creep_death") == 0)
end

do -- deny
	reset()
	local tick, log = stock()
	MakeUnit({ pid = 1 })
	local e = MakeUnit({ pid = 6, team = 3 })
	lists[8] = { e }
	local c = creep(9, 80, 0, 20)
	frame(tick, 60); kill(9, c); e.dn = 1; frame(tick, 60.1)
	check("enemy deny", field(of(log, "creep_death")[1], "by") == "deny")
end

do -- one claim pool
	reset()
	local tick, log = stock()
	local h = MakeUnit({ pid = 1 })
	local lane, wild = creep(9, 300, 0, 20), creep(13, 50, 0, 20, "npc_dota_neutral_kobold")
	frame(tick, 60); kill(9, lane); kill(13, wild); h.lh = 1; frame(tick, 60.1)
	local n = of(log, "neutral_death")[1]
	check("neutral takes the one last hit", field(n, "by") == "1" and field(n, "kind") == "neutral", n)
	check("lane creep beside it is nobody's", field(of(log, "creep_death")[1], "by") == "none")
end

do -- bot-only team
	reset()
	local real = GetTeamPlayers
	GetTeamPlayers = function() return {} end
	local tick, log = stock()
	local h = MakeUnit({ pid = 1 })
	local c = creep(9, 80, 0, 20)
	frame(tick, 60); kill(9, c); h.lh = 1; frame(tick, 60.1)
	GetTeamPlayers = real
	check("bot-only team", #of(log, "creep_death") == 1)
end

do -- inventory
	reset()
	local tick, log = stock()
	local h = MakeUnit({ pid = 1 })
	h.slots = { [0] = item("flask", 1), [1] = item("tango", 3), [9] = item("blink"), [16] = item("trident") }
	frame(tick, 0); frame(tick, 1.1)
	local e = of(log, "inv")
	check("inv: first layout, quoted, only once", #e == 1 and field(e[1], "pid") == "1"
		and e[1]:find('items="s0=flask:1 s1=tango:3 s9=blink s16=trident"', 1, true) ~= nil, e[1])
	h.slots[1] = item("tango", 2); frame(tick, 2.2)
	check("inv: a charge logs", #of(log, "inv") == 2)
	h.slots = {}; frame(tick, 3.3)
	check("inv: empty logs", #of(log, "inv") == 3 and (of(log, "inv")[3] or ""):find('items=""', 1, true) ~= nil)
end

local function runeCase(power, from, to, enemy)
	reset()
	local tick, log = stock()
	MakeUnit({ pid = 2, loc = Vector(100, 0) })
	local r = power and 0 or 2
	spots[r], status[r] = Vector(0, 0), 1
	if enemy then lists[8] = { MakeUnit({ pid = 7, team = 3, loc = Vector(10, 0) }) } end
	for i = 0, 2 do frame(tick, from + i / 30) end
	status[r] = 2
	for i = 0, 2 do frame(tick, to + i / 30) end
	return of(log, "rune_pickup")
end
do
	local e = runeCase(false, 245, 246)
	check("bounty pickup", #e == 1 and field(e[1], "kind") == "bounty" and field(e[1], "pid") == "2"
		and field(e[1], "team") == "2" and field(e[1], "rune") == "2", e[1])
	check("water before 6:00", field(runeCase(true, 125, 126)[1], "kind") == "water")
	check("power from 6:00", field(runeCase(true, 365, 366)[1], "kind") == "power")
	check("enemy nearer", #runeCase(false, 245, 246, true) == 0)
	check("despawn on the spawn tick", #runeCase(true, 300, 360.01) == 0)
	check("stale across 0:00", #runeCase(false, -5, 0.2) == 0)
end

do -- mode changes
	reset()
	local tick, log = stock()
	local h = MakeUnit({ pid = 1, mode = 1 })
	for i = 0, 3 do frame(tick, 60 + i / 30) end
	check("mode: the first mode is no change", #of(log, "mode") == 0)
	h.mode, h.desire = 2, 0.9
	for i = 0, 3 do frame(tick, 61 + i / 30) end
	local e = of(log, "mode")
	check("mode: from, to, desire, once", #e == 1 and field(e[1], "pid") == "1" and field(e[1], "from") == "laning"
		and field(e[1], "to") == "attack" and field(e[1], "d") == "0.900" and field(e[1], "dwell") ~= nil, e[1])
end

do -- guards
	reset()
	local tick, log = stock()
	local h = MakeUnit({ pid = 1 })
	h.badItem, badList = true, 13
	local c = creep(9, 80, 0, 20)
	frame(tick, 60); kill(9, c); h.lh = 1; frame(tick, 61.1); frame(tick, 62.2)
	check("guards: snaps outlive a bad item read", #of(log, "snap") == 3, #of(log, "snap"))
	check("guards: lane deaths outlive a bad neutral read", #of(log, "creep_death") == 1)
	local where = {}
	for _, l in ipairs(of(log, "stock_log_error")) do
		local w = field(l, "where") or "?"
		where[w] = (where[w] or 0) + 1
	end
	check("guards: each site named once", where.inv == 1 and where.neutrals == 1)
	h.badItem = false; frame(tick, 63.3)
	check("guards: inv recovers", #of(log, "inv") == 1)
	h.badGold = true
	local d = creep(9, 90, 0, 20)
	frame(tick, 64.4); kill(9, d); frame(tick, 65.5)
	check("guards: deaths outlive a bad snapshot", #of(log, "creep_death") == 2)
end

-- Random worlds: the four events match team-bots' telemetry, and everything the old logger printed is unchanged.
local KEYS = {
	creep_death = { "t", "team", "kind", "x", "y", "hp", "by" },
	neutral_death = { "t", "team", "kind", "x", "y", "hp", "by" },
	rune_pickup = { "t", "pid", "team", "rune", "kind", "x", "y" },
	inv = { "pid", "items" },
	mode = { "t", "pid", "from", "to", "d", "dwell" },
}
local function projected(lines, ev)
	local r = {}
	for _, l in ipairs(of(lines, ev)) do
		local p = {}
		for _, k in ipairs(KEYS[ev]) do p[#p + 1] = k .. "=" .. tostring(field(l, k)) end
		r[#r + 1] = table.concat(p, " ")
	end
	table.sort(r)
	return r
end
local function lastInv(lines)
	local m = {}
	for _, l in ipairs(of(lines, "inv")) do m[field(l, "pid")] = field(l, "items") end
	return m
end

local LANE = { "npc_dota_creep_badguys_melee", "npc_dota_creep_goodguys_ranged", "npc_dota_badguys_siege" }
local totals = { creep_death = 0, neutral_death = 0, rune_pickup = 0, inv = 0, mode = 0 }
for seed, start in ipairs({ 0.5, 116, 236, 355, 478, 700 }) do
	math.randomseed(seed)
	local team = seed % 2 == 0 and 3 or 2
	reset(team)
	local H = FreshHumaniser({ Enable = false, TickEvery = 3, Telemetry = { Enable = true } })
	H.Lane.SetHelpers({ GetPosition = function() return 1 end })
	local ref = {}
	H.Telemetry.SetSink(function(s) table.insert(ref, s) end)
	local new, newLog = stock()
	local old, oldLog = stock(OLD_FILE)
	local hs = {}
	for i = 1, 5 do
		hs[i] = MakeUnit({ pid = i + (team == 3 and 4 or -1), team = team, loc = Vector(math.random(-800, 800), math.random(-800, 800)) })
	end
	local e = MakeUnit({ pid = 20, team = 5 - team, loc = Vector(500, 500) })
	lists[8] = { e }
	for r = 0, 5 do spots[r] = Vector(math.random(-500, 500), math.random(-500, 500)) end

	for f = 1, 900 do
		T = start + f / 30
		for _, h in ipairs(hs) do
			h.loc = Vector(h.loc.x + math.random(-15, 15) + math.random(), h.loc.y + math.random(-15, 15) + math.random())
			if math.random() < 0.002 then h.alive = not h.alive end
			if math.random() < 0.01 then h.mode, h.desire = ({ 1, 2, 4, 7, 16, 17, 22 })[math.random(7)], math.random() end
			if math.random() < 0.004 then
				h.slots = h.slots or {}
				local slot = math.random(0, 16)
				if math.random() < 0.3 then h.slots[slot] = nil else h.slots[slot] = item("tango", math.random(0, 3)) end
			end
		end
		for _, k in ipairs({ 9, 13 }) do
			if math.random() < 0.12 then
				local c = creep(k, math.random(-1900, 1900) + math.random(), math.random(-1900, 1900) + math.random(),
					math.random(20, 100), k == 13 and "npc_dota_neutral_kobold" or LANE[math.random(3)])
				c.ancient = math.random() < 0.2
			end
			for i = #lists[k], 1, -1 do
				local c = lists[k][i]
				if math.random() < 0.04 then c.hp = math.max(1, c.hp - 20) end
				if math.random() < 0.012 then
					kill(k, c)
					local h = hs[math.random(5)]
					if h.alive and math.random() < 0.7 then h.lh = (h.lh or 0) + 1
					elseif math.random() < 0.3 then e.dn = (e.dn or 0) + 1 end
				end
			end
		end
		for r = 0, 5 do
			if math.random() < 0.015 then status[r] = status[r] == 1 and 2 or 1 end
		end
		for _, h in ipairs(hs) do
			if h.alive then H.Tick(h); new(h); old(h) end
		end
	end

	for _, ev in ipairs({ "creep_death", "neutral_death", "rune_pickup", "inv", "mode" }) do
		local a, b = projected(ref, ev), projected(newLog, ev)
		if ev == "inv" then
			-- team-bots samples inv on a third frame and stock on its own snapshot, so a change undone between samples differs.
			local la, lb = lastInv(ref), lastInv(newLog)
			local both = true
			for _, h in ipairs(hs) do
				if la[tostring(h.pid)] == nil or lb[tostring(h.pid)] == nil then both = false end
			end
			check("parity " .. seed .. " inv: every hero", both)
			check("parity " .. seed .. " inv: count within 10%", math.abs(#a - #b) <= math.max(3, #a / 10), #a .. " vs " .. #b)
		else
			check("parity " .. seed .. " " .. ev, table.concat(a, "\n") == table.concat(b, "\n"),
				#a .. " team-bots vs " .. #b .. " stock; first " .. tostring(a[1]) .. " | " .. tostring(b[1]))
		end
		totals[ev] = totals[ev] + #b
	end
	local kept = {}
	for _, l in ipairs(newLog) do
		if not KEYS[l:match(" ev=(%S+)")] then kept[#kept + 1] = l end
	end
	check("bot and snap lines unchanged " .. seed, #kept > 0 and table.concat(kept, "\n") == table.concat(oldLog, "\n"), #kept .. " vs " .. #oldLog)
end
for ev, n in pairs(totals) do
	print("fuzz " .. ev .. " " .. n)
	check("fuzz exercised " .. ev, n >= 10, n)
end
finish()
