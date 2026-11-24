-- Rig setters (rework step 8): server Lua, not bot script. `script_reload_code bots/rigs/setters` (sv_cheats) runs it once in a
-- dotactl game, through the same vscripts/bots link the bot VM loads from; it registers console commands that a rig's
-- `--at`/`--every` steps call for the rest of the game. Each prints one `[RIG]` line saying what it did.
--   rig_hp <pid> <hp>               set a hero's health (clamped to 1..max)
--   rig_hp_share <pid> <share>      set a hero's health to a share of its maximum (0..1)
--   rig_hp_all <share>              set every live hero's health to a share of its maximum
--   rig_pos <pid> <x> <y>           place a hero (nearest clear ground) and stop its current order
--   rig_creep <team 2|3> <melee|ranged> <x> <y> [n]   create n lane creeps of that team
--   rig_kill_creeps <team 2|3> <x> <y> <radius>       kill that team's lane creeps in the circle
--   rig_tower_hp <team 2|3> <x> <y> <radius>          heal that team's live towers in the circle to full
--   rig_hp_holding <item> <share> [team 2|3]   set the health share of every live hero holding that item (slots 0-8)
--   rig_mp_holding <item> <share> [team]       set the mana share of every live hero holding that item
--   rig_charges <item> <n> [team]              set the charges of that item on every live hero holding it (a bottle's, a tango's)
-- With a team, only that team's heroes (a benched enemy buys the same items).
-- The *_holding setters let a rig name a hero by a marker item it bought in setup (the sustain rig): the server cannot read
-- the bot's state, and a pid differs by lineup.
-- Bot pids are PlayerResource ids; heroes are found through HeroList (GetSelectedHeroEntity can be nil for bots).
local function hero(pid)
	pid = tonumber(pid)
	for _, h in ipairs(HeroList:GetAllHeroes()) do
		if h:GetPlayerOwnerID() == pid and not h:IsIllusion() then return h end
	end
end

local function say(s) print("[RIG] " .. s) end

Convars:RegisterCommand("rig_hp", function(_, pid, hp)
	local h = hero(pid)
	if h == nil then return say("hp no hero " .. tostring(pid)) end
	h:SetHealth(math.max(1, math.min(h:GetMaxHealth(), tonumber(hp) or 1)))
	say(string.format("hp pid=%s hp=%d max=%d", pid, h:GetHealth(), h:GetMaxHealth()))
end, "rig: set a hero's health", FCVAR_CHEAT)

Convars:RegisterCommand("rig_hp_share", function(_, pid, share)
	local h = hero(pid)
	if h == nil then return say("hp_share no hero " .. tostring(pid)) end
	h:SetHealth(math.max(1, math.floor(h:GetMaxHealth() * math.max(0, math.min(1, tonumber(share) or 1)))))
	say(string.format("hp_share pid=%s hp=%d max=%d", pid, h:GetHealth(), h:GetMaxHealth()))
end, "rig: set a hero's health to a share of its maximum", FCVAR_CHEAT)

-- One command for every hero: at 8x each console step costs about a game second (lane-trade probe1: ten rig_hp_share lines
-- meant for 0:59 ran from 1:01 to 1:35).
Convars:RegisterCommand("rig_hp_all", function(_, share)
	local n = 0
	for _, h in ipairs(HeroList:GetAllHeroes()) do
		if not h:IsIllusion() and h:IsAlive() then
			h:SetHealth(math.max(1, math.floor(h:GetMaxHealth() * math.max(0, math.min(1, tonumber(share) or 1)))))
			n = n + 1
		end
	end
	say(string.format("hp_all share=%s n=%d", tostring(share), n))
end, "rig: set every live hero's health to a share of its maximum", FCVAR_CHEAT)

Convars:RegisterCommand("rig_pos", function(_, pid, x, y)
	local h = hero(pid)
	if h == nil then return say("pos no hero " .. tostring(pid)) end
	FindClearSpaceForUnit(h, Vector(tonumber(x), tonumber(y), 0), true)
	h:Stop()
	local o = h:GetAbsOrigin()
	say(string.format("pos pid=%s x=%d y=%d", pid, o.x, o.y))
end, "rig: place a hero", FCVAR_CHEAT)

Convars:RegisterCommand("rig_creep", function(_, team, kind, x, y, n)
	team = tonumber(team)
	local name = "npc_dota_creep_" .. (team == DOTA_TEAM_GOODGUYS and "goodguys" or "badguys") .. "_" .. (kind == "ranged" and "ranged" or "melee")
	local made = 0
	for _ = 1, tonumber(n) or 1 do
		if CreateUnitByName(name, Vector(tonumber(x), tonumber(y), 0), true, nil, nil, team) ~= nil then made = made + 1 end
	end
	say(string.format("creep %s n=%d", name, made))
end, "rig: create lane creeps", FCVAR_CHEAT)

Convars:RegisterCommand("rig_tower_hp", function(_, team, x, y, r)
	local n = 0
	for _, u in ipairs(FindUnitsInRadius(tonumber(team), Vector(tonumber(x), tonumber(y), 0), nil, tonumber(r), DOTA_UNIT_TARGET_TEAM_FRIENDLY,
		DOTA_UNIT_TARGET_BUILDING, 0, 0, false)) do
		if u:IsTower() and u:IsAlive() then
			u:SetHealth(u:GetMaxHealth())
			n = n + 1
		end
	end
	say(string.format("tower_hp team=%s n=%d", team, n))
end, "rig: heal that team's towers in a circle to full", FCVAR_CHEAT)

Convars:RegisterCommand("rig_kill_creeps", function(_, team, x, y, r)
	local n = 0
	for _, u in ipairs(FindUnitsInRadius(tonumber(team), Vector(tonumber(x), tonumber(y), 0), nil, tonumber(r), DOTA_UNIT_TARGET_TEAM_FRIENDLY,
		DOTA_UNIT_TARGET_BASIC, 0, 0, false)) do
		if u:GetClassname() == "npc_dota_creep_lane" then
			u:ForceKill(false)
			n = n + 1
		end
	end
	say(string.format("kill_creeps team=%s n=%d", team, n))
end, "rig: kill lane creeps in a circle", FCVAR_CHEAT)

-- Every live non-illusion hero with `item` in slots 0-8, and that item.
local function holders(item, team)
	local r = {}
	team = tonumber(team)
	for _, h in ipairs(HeroList:GetAllHeroes()) do
		if not h:IsIllusion() and h:IsAlive() and (team == nil or h:GetTeamNumber() == team) then
			for s = 0, 8 do
				local it = h:GetItemInSlot(s)
				if it ~= nil and it:GetAbilityName() == item then
					table.insert(r, { h = h, it = it })
					break
				end
			end
		end
	end
	return r
end

local function share(v) return math.max(0, math.min(1, tonumber(v) or 1)) end

Convars:RegisterCommand("rig_hp_holding", function(_, item, s, team)
	local hs = holders(item, team)
	for _, e in ipairs(hs) do e.h:SetHealth(math.max(1, math.floor(e.h:GetMaxHealth() * share(s)))) end
	say(string.format("hp_holding item=%s share=%s n=%d", tostring(item), tostring(s), #hs))
end, "rig: set the health share of every hero holding an item", FCVAR_CHEAT)

Convars:RegisterCommand("rig_mp_holding", function(_, item, s, team)
	local hs = holders(item, team)
	for _, e in ipairs(hs) do e.h:SetMana(e.h:GetMaxMana() * share(s)) end
	say(string.format("mp_holding item=%s share=%s n=%d", tostring(item), tostring(s), #hs))
end, "rig: set the mana share of every hero holding an item", FCVAR_CHEAT)

Convars:RegisterCommand("rig_charges", function(_, item, n, team)
	local hs = holders(item, team)
	for _, e in ipairs(hs) do e.it:SetCurrentCharges(math.max(0, math.floor(tonumber(n) or 0))) end
	say(string.format("charges item=%s n=%s heroes=%d", tostring(item), tostring(n), #hs))
end, "rig: set the charges of an item on every hero holding it", FCVAR_CHEAT)

local function campNeutrals(c, r)
	local out = {}
	for _, u in ipairs(FindUnitsInRadius(DOTA_TEAM_NEUTRALS, c, nil, r, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BASIC,
		DOTA_UNIT_TARGET_FLAG_INVULNERABLE, 0, false)) do
		if u:IsAlive() and u:GetTeamNumber() == DOTA_TEAM_NEUTRALS then table.insert(out, u) end
	end
	return out
end

-- A stack without a stacker, by the game's own minute spawn: from :59.0 of the coming minute to :00.6 the camp's neutrals
-- are held out of its box, then left to walk home (the camp held 6 or 7 after it, pullstk6). Moving them out and forcing a
-- spawn adds none: `dota_spawn_neutrals` only arms the next :00 spawn (pullstk1, pullstk3).
-- The units held are those in the circle at :59.0, so a set stacked earlier goes out with them.
-- The think runs on a hero: a plain `map dota` game has no game-mode entity to host it (GetGameModeEntity, pullstk2:
-- "error in error handling" on every call).
local function stackMinute(x, y, r, dx, dy)
	local c = Vector(tonumber(x), tonumber(y), 0)
	local off = Vector(tonumber(dx) or 0, tonumber(dy) or 800, 0)
	r = tonumber(r) or 500
	local now = GameRules:GetDOTATime(false, false)
	local from = math.floor(now / 60) * 60 + 59
	if now > from then from = from + 60 end
	local held
	local name = "rig_stack_" .. tostring(x) .. "_" .. tostring(y)
	HeroList:GetAllHeroes()[1]:SetContextThink(name, function()
		local t = GameRules:GetDOTATime(false, false)
		if t < from then return 0.1 end
		if held == nil then
			held = campNeutrals(c, r)
			local near, nd = 0, 1e9
			for _, u in ipairs(campNeutrals(c, 2000)) do
				near = near + 1
				nd = math.min(nd, (u:GetAbsOrigin() - c):Length2D())
			end
			say(string.format("stack_minute x=%s y=%s t=%.2f in=%d within2000=%d nearest=%.0f", tostring(x), tostring(y), t, #held, near, nd))
		end
		if t > from + 1.6 then
			say(string.format("stack_minute x=%s y=%s held=%d at=%.1f", tostring(x), tostring(y), #held, from))
			return nil
		end
		for _, u in ipairs(held) do
			if u:IsAlive() and (u:GetAbsOrigin() - c):Length2D() < 600 then FindClearSpaceForUnit(u, c + off, true) end
		end
		return 0.05
	end, 0)
	say(string.format("stack_minute armed x=%s y=%s from=%.0f", tostring(x), tostring(y), from))
end

Convars:RegisterCommand("rig_stack_minute", function(_, ...)
	local ok, err = pcall(stackMinute, ...)
	if not ok then say("stack_minute error " .. tostring(err)) end
end, "rig: hold a camp's neutrals out of its box over the coming minute's spawn", FCVAR_CHEAT)

Convars:RegisterCommand("rig_neutrals", function(_, x, y, r)
	local us = campNeutrals(Vector(tonumber(x), tonumber(y), 0), tonumber(r) or 500)
	local names = {}
	for _, u in ipairs(us) do table.insert(names, (u:GetUnitName():gsub("npc_dota_neutral_", ""))) end
	say(string.format("neutrals x=%s y=%s t=%.1f n=%d %s", tostring(x), tostring(y), GameRules:GetDOTATime(false, false), #us,
		table.concat(names, ",")))
end, "rig: count the live neutrals in a circle", FCVAR_CHEAT)

-- A camp's watch for the stacked pull's rig (families proposal s5 case 3, round 3), one think per camp for the rest of the
-- game: at :59.5 and :00.5 the neutrals in the box circle with their HP shares (`watch_min`: what a stack meets and makes);
-- each lane creep of `team` that came within `r` of the camp and leaves past r + 300 alive, with its HP share (`watch_off`:
-- the pulled wave's survivors walking back); and when the last of that team's creeps leaves or dies, the neutrals still
-- alive within r with their HP shares (`watch_end`).
local function hps(us)
	local t = {}
	for _, u in ipairs(us) do table.insert(t, string.format("%.2f", u:GetHealth() / math.max(1, u:GetMaxHealth()))) end
	return table.concat(t, ",")
end

local function laneCreeps(team, c, r)
	local out = {}
	for _, u in ipairs(FindUnitsInRadius(team, c, nil, r, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BASIC, 0, 0, false)) do
		if u:IsAlive() and u:GetClassname() == "npc_dota_creep_lane" then table.insert(out, u) end
	end
	return out
end

Convars:RegisterCommand("rig_camp_watch", function(_, x, y, team, r, box)
	local ok, err = pcall(function()
		local c = Vector(tonumber(x), tonumber(y), 0)
		team = tonumber(team)
		r = tonumber(r) or 900
		box = tonumber(box) or 500
		local tag = string.format("x=%s y=%s", tostring(x), tostring(y))
		local inside, fighting = {}, false
		local lastMark = -1
		HeroList:GetAllHeroes()[1]:SetContextThink("rig_watch_" .. tostring(x) .. "_" .. tostring(y), function()
			local t = GameRules:GetDOTATime(false, false)
			local sec = t % 60
			local mark = math.floor(t * 2 + 0.5)
			if (sec >= 59.5 or sec < 0.75) and mark ~= lastMark and (math.abs(sec - 59.5) < 0.2 or math.abs(sec - 0.5) < 0.2) then
				lastMark = mark
				local ns = campNeutrals(c, box)
				say(string.format("watch_min %s t=%.1f n=%d hp=%s", tag, t, #ns, hps(ns)))
			end
			local near = laneCreeps(team, c, r)
			for _, u in ipairs(near) do inside[u:entindex()] = u end
			for id, u in pairs(inside) do
				if u:IsNull() or not u:IsAlive() then
					inside[id] = nil
				elseif (u:GetAbsOrigin() - c):Length2D() > r + 300 then
					say(string.format("watch_off %s t=%.1f hp=%.2f", tag, t, u:GetHealth() / math.max(1, u:GetMaxHealth())))
					inside[id] = nil
				end
			end
			local any = next(inside) ~= nil
			if any then fighting = true end
			if fighting and not any then
				fighting = false
				local ns = campNeutrals(c, r)
				say(string.format("watch_end %s t=%.1f n=%d hp=%s", tag, t, #ns, hps(ns)))
			end
			return 0.1
		end, 0)
		say(string.format("watch armed %s team=%d r=%d", tag, team, r))
	end)
	if not ok then say("watch error " .. tostring(err)) end
end, "rig: watch a camp for the stacked pull's rig", FCVAR_CHEAT)

say("setters registered")
