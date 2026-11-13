-- Builds the world of a fixture cut from a game (tools/hlog/cut.js, ev=cut) for the cut drivers (lane_spot, threat_gate,
-- retreat_leave): every API call the decision and its Threat.Read make is answered from the world; nothing else runs.
-- world: t, team, pid, lane, ours {Switch = bool}, bot {x, y, hp, mhp, range, hull, speed, esc},
--        ce/ca [{id, x, y, hp, mhp, ranged, tgt, hull}], he [{pid, x, y, hp, range, hull, speed, atk, eng, e3, e6, ill}],
--        hu [{pid, x, y, tss, sp}], ha [{pid, x, y, range, hull, speed, ret}], towers [{team, i, x, y, range, hull, tgt}],
--        vis {x0, y0, nx, ny, step, hex} (cell i, j at x0 + i step, y0 + j step; absent: all visible).
--        A target is "b" (the bot), "h<pid>", "u<creep id>" or "-".
-- Returns { bot, byCreep (by creep id), Threat, dist }; a driver sets what only its decision reads (a lane front, a walk's vision) after this.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local U = {}
U.__index = U
function U:IsNull() return false end
function U:IsAlive() return true end
function U:GetLocation() return self.loc end
function U:GetUnitName() return self.name end
function U:GetTeam() return self.team end
function U:GetHealth() return self.hp end
function U:GetMaxHealth() return self.mhp or self.hp end
function U:GetAttackTarget() return self.target end
function U:GetAttackRange() return self.range or 0 end
function U:GetBoundingRadius() return self.hull or 0 end
function U:GetCurrentMovementSpeed() return self.speed or 0 end
function U:GetPlayerID() return self.pid or -1 end
function U:GetAssignedLane() return self.lane end
function U:CanBeSeen() return true end
function U:IsIllusion() return self.ill == true end
function U:IsHero() return self.hero == true end
function U:GetEstimatedDamageToTarget(_, _, duration) return duration >= 6 and (self.e6 or 0) or (self.e3 or 0) end
function U:WasRecentlyDamagedByHero(e) return e.eng == true end
function U:WasRecentlyDamagedByTower() return self.dtower == true end
function U:FindItemSlot(name) return (self.esc and name == "item_tpscroll") and 0 or -1 end
function U:GetItemInSlot() return { IsFullyCastable = function() return true end } end

local world

local function within(list, from, r)
	local out = {}
	for _, u in ipairs(list) do if dist(u.loc, from) <= r then out[#out + 1] = u end end
	return out
end
function U:GetNearbyLaneCreeps(r, enemies) return within(enemies and world.theirCreeps or world.ourCreeps, self.loc, math.min(r, 1600)) end
function U:GetNearbyTowers(r, enemies) return within(enemies and world.theirTowers or world.ourTowers, self.loc, math.min(r, 1600)) end
function U:GetNearbyHeroes(r, enemies) return enemies and within(world.enemies, self.loc, math.min(r, 1600)) or {} end

local function unit(o) return setmetatable(o, U) end

return function(w)
	local team = w.team
	local enemyTeam = team == 2 and 3 or 2
	FreshHumaniser({ Enable = true })
	local ours = package.loaded["bots/FunLib/custom_loader"].Ours
	for k, v in pairs(w.ours or {}) do ours[k] = v == true or v == 1 end
	T, CURRENT_TEAM = w.t, team
	local Threat = require("bots/FunLib/humaniser/threat")
	Threat.ResetCache()
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")

	world = { theirCreeps = {}, ourCreeps = {}, theirTowers = {}, ourTowers = {}, enemies = {}, allies = {} }
	local byCreep, byHero = {}, {}
	local elsewhere = unit({ loc = Vector(0, 0), hp = 1 })
	local b = w.bot
	local bot = unit({ loc = Vector(b.x, b.y), team = team, hp = b.hp, mhp = b.mhp, range = b.range, hull = b.hull, speed = b.speed,
		esc = b.esc == 1 or b.esc == true, pid = w.pid, lane = w.lane, hero = true, dtower = w.dt == 1 })
	byHero[w.pid] = bot
	local pending = {}
	local function creep(c, t, list)
		local side = t == 2 and "goodguys" or "badguys"
		local u = unit({ loc = Vector(c.x, c.y), team = t, hp = c.hp, mhp = c.mhp, hull = c.hull,
			name = "npc_dota_creep_" .. side .. ((c.ranged == 1 or c.ranged == true) and "_ranged" or "_melee") })
		byCreep[c.id] = u
		table.insert(list, u)
		pending[#pending + 1] = { u, c.tgt }
	end
	for _, c in ipairs(w.ce or {}) do creep(c, enemyTeam, world.theirCreeps) end
	for _, c in ipairs(w.ca or {}) do creep(c, team, world.ourCreeps) end
	for _, e in ipairs(w.he or {}) do
		local u = unit({ loc = Vector(e.x, e.y), team = enemyTeam, hp = e.hp, range = e.range, hull = e.hull, speed = e.speed, pid = e.pid,
			e3 = e.e3, e6 = e.e6, eng = e.eng == 1, ill = e.ill == 1, hero = true, name = "npc_dota_hero_enemy" })
		if e.atk == 1 then u.target = bot end
		if not u.ill then byHero[e.pid] = u end
		table.insert(world.enemies, u)
	end
	for _, a in ipairs(w.ha or {}) do
		local u = unit({ loc = Vector(a.x, a.y), team = team, range = a.range, hull = a.hull, speed = a.speed, pid = a.pid, hero = true })
		byHero[a.pid] = u
		table.insert(world.allies, u)
		if a.ret == 1 then RetreatState.SetRunning(u, true) end
	end
	local towerAt = { [2] = {}, [3] = {} }
	for _, t in ipairs(w.towers or {}) do
		local u = unit({ loc = Vector(t.x, t.y), team = t.team, range = t.range, hull = t.hull, hp = 1 })
		towerAt[t.team][t.i] = u
		table.insert(t.team == team and world.ourTowers or world.theirTowers, u)
		pending[#pending + 1] = { u, t.tgt }
	end
	for _, p in ipairs(pending) do
		local tgt = p[2]
		if tgt == "b" then p[1].target = bot
		elseif type(tgt) == "string" and tgt:sub(1, 1) == "h" then p[1].target = byHero[tonumber(tgt:sub(2))]
		elseif type(tgt) == "string" and tgt:sub(1, 1) == "u" then p[1].target = byCreep[tonumber(tgt:sub(2))] end
		-- A target outside the cut (a creep on a tower, a ward, a summon) is still a target: the decisions test only nil, the
		-- bot and the creeps they name.
		if p[1].target == nil and tgt ~= "-" and tgt ~= nil then p[1].target = elsewhere end
	end

	function GetUnitList(kind)
		if kind == 8 then return world.enemies end
		if kind == 2 then local r = { bot } for _, a in ipairs(world.allies) do r[#r + 1] = a end return r end
		if kind == 9 then return world.theirCreeps end
		if kind == 3 then return world.ourCreeps end
		return {}
	end
	function GetTower(t, id) return towerAt[t][id] end
	local seen = {}
	for _, h in ipairs(w.hu or {}) do seen[h.pid] = h end
	function GetTeamForPlayer(pid)
		if pid == w.pid or byHero[pid] ~= nil and byHero[pid].team == team then return team end
		if seen[pid] ~= nil or (byHero[pid] ~= nil and byHero[pid].team == enemyTeam) then return enemyTeam end
		return -1
	end
	function IsHeroAlive(pid) return byHero[pid] ~= nil or seen[pid] ~= nil end
	function GetHeroLastSeenInfo(pid)
		local h = seen[pid]
		if h == nil then return {} end
		return { { location = Vector(h.x, h.y), time_since_seen = h.tss } }
	end
	-- Threat's speed memory for unseen heroes (what the game's Read last saw): one throwaway Read with them in sight.
	local ghosts = {}
	for _, h in ipairs(w.hu or {}) do
		if h.sp ~= nil and h.sp > 0 then ghosts[#ghosts + 1] = unit({ loc = Vector(h.x, h.y), team = enemyTeam, pid = h.pid, speed = h.sp, hp = 1, hero = true }) end
	end
	if #ghosts > 0 then
		local real = world.enemies
		world.enemies = ghosts
		Threat.Read(bot, bot.loc, bot.loc, 0)
		world.enemies = real
	end
	local vis = w.vis
	function IsLocationVisible(v)
		if vis == nil then return true end
		local i = math.floor((v.x - vis.x0) / vis.step + 0.5)
		local j = math.floor((v.y - vis.y0) / vis.step + 0.5)
		if i < 0 or j < 0 or i >= vis.nx or j >= vis.ny then return false end
		local bit = j * vis.nx + i
		local nib = tonumber(vis.hex:sub(math.floor(bit / 4) + 1, math.floor(bit / 4) + 1), 16) or 0
		return math.floor(nib / 2 ^ (3 - bit % 4)) % 2 == 1
	end
	function GetUnitToUnitDistance(a, c) return dist(a.loc, c.loc) end
	function GetUnitToLocationDistance(u, v) return dist(u.loc, v) end
	return { bot = bot, byCreep = byCreep, Threat = Threat, dist = dist }
end
