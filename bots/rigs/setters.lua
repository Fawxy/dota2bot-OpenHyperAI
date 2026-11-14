-- Rig setters (rework step 8): server Lua, not bot script. `script_reload_code bots/rigs/setters` (sv_cheats) runs it once in a
-- dotactl game, through the same vscripts/bots link the bot VM loads from; it registers console commands that a rig's
-- `--at`/`--every` steps call for the rest of the game. Each prints one `[RIG]` line saying what it did.
--   rig_hp <pid> <hp>               set a hero's health (clamped to 1..max)
--   rig_hp_share <pid> <share>      set a hero's health to a share of its maximum (0..1)
--   rig_pos <pid> <x> <y>           place a hero (nearest clear ground) and stop its current order
--   rig_creep <team 2|3> <melee|ranged> <x> <y> [n]   create n lane creeps of that team
--   rig_kill_creeps <team 2|3> <x> <y> <radius>       kill that team's lane creeps in the circle
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

say("setters registered")
