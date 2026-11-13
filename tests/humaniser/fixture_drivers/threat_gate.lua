-- Driver: Threat.Gate (the start gate of a trip: the threat read over the walk from `from` to `place`) on a world cut from a
-- game (ev=cut kind=gate, tools/hlog/cut.js), real map. Every API call Gate and Read make is answered from the world.
-- world: t, team, pid, who, ours {Switch = bool}, bot {x, y, hp, mhp, range, hull, speed, esc}, from {x, y}, place {x, y},
--        he [{pid, x, y, hp, range, hull, speed, atk, eng, e3, e6, ill}], hu [{pid, x, y, tss, sp}],
--        ha [{pid, x, y, range, hull, speed, ret}], towers [{team, i, x, y, range, hull}],
--        vw {n, hex} (visibility at the walk's n + 1 evenly spaced points, from `from` to `place`; absent: all visible).
-- Observation: go, or hold(threat) / hold(missing); fact.reach (heroes in reach), fact.missing (the belief's weight sum),
-- fact.mcut (unseen heroes the vision cut dropped), fact.burst, fact.allies, fact.tower (1 when the place is in a tower's reach).
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local U = {}
U.__index = U
function U:IsNull() return false end
function U:IsAlive() return true end
function U:GetLocation() return self.loc end
function U:GetTeam() return self.team end
function U:GetHealth() return self.hp end
function U:GetMaxHealth() return self.mhp or self.hp end
function U:GetAttackTarget() return self.target end
function U:GetAttackRange() return self.range or 0 end
function U:GetBoundingRadius() return self.hull or 0 end
function U:GetCurrentMovementSpeed() return self.speed or 0 end
function U:GetPlayerID() return self.pid or -1 end
function U:CanBeSeen() return true end
function U:IsIllusion() return self.ill == true end
function U:GetEstimatedDamageToTarget(_, _, duration) return duration >= 6 and (self.e6 or 0) or (self.e3 or 0) end
function U:WasRecentlyDamagedByHero(e) return e.eng == true end
function U:FindItemSlot(name) return (self.esc and name == "item_tpscroll") and 0 or -1 end
function U:GetItemInSlot() return { IsFullyCastable = function() return true end } end

local function unit(o) return setmetatable(o, U) end

return function(fx)
	local w = fx.world
	local team = w.team
	local enemyTeam = team == 2 and 3 or 2
	local H = FreshHumaniser({ Enable = true })
	local ours = package.loaded["bots/FunLib/custom_loader"].Ours
	for k, v in pairs(w.ours or {}) do ours[k] = v == true or v == 1 end
	T, CURRENT_TEAM = w.t, team
	local Threat = require("bots/FunLib/humaniser/threat")
	Threat.ResetCache()
	local RetreatState = require("bots/FunLib/humaniser/retreat_state")

	local enemies, allies, byHero = {}, {}, {}
	local b = w.bot
	local bot = unit({ loc = Vector(b.x, b.y), team = team, hp = b.hp, mhp = b.mhp, range = b.range, hull = b.hull, speed = b.speed,
		esc = b.esc == 1 or b.esc == true, pid = w.pid, hero = true })
	byHero[w.pid] = bot
	for _, e in ipairs(w.he or {}) do
		local u = unit({ loc = Vector(e.x, e.y), team = enemyTeam, hp = e.hp, range = e.range, hull = e.hull, speed = e.speed, pid = e.pid,
			e3 = e.e3, e6 = e.e6, eng = e.eng == 1, ill = e.ill == 1, hero = true })
		if e.atk == 1 then u.target = bot end
		if not u.ill then byHero[e.pid] = u end
		table.insert(enemies, u)
	end
	for _, a in ipairs(w.ha or {}) do
		local u = unit({ loc = Vector(a.x, a.y), team = team, range = a.range, hull = a.hull, speed = a.speed, pid = a.pid, hero = true })
		byHero[a.pid] = u
		table.insert(allies, u)
		if a.ret == 1 then RetreatState.SetRunning(u, true) end
	end
	local towerAt = { [2] = {}, [3] = {} }
	for _, t in ipairs(w.towers or {}) do
		towerAt[t.team][t.i] = unit({ loc = Vector(t.x, t.y), team = t.team, range = t.range, hull = t.hull, hp = 1 })
	end

	function GetUnitList(kind)
		if kind == 8 then return enemies end
		if kind == 2 then local r = { bot } for _, a in ipairs(allies) do r[#r + 1] = a end return r end
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
		local real = enemies
		enemies = ghosts
		Threat.Read(bot, bot.loc, bot.loc, 0)
		enemies = real
	end
	local from, place = Vector(w.from.x, w.from.y), Vector(w.place.x, w.place.y)
	local vw = w.vw
	-- The walk point nearest the asked one, by its share of the walk: the replay's rounded coordinates may cut the walk in another
	-- number of steps than the game's did.
	function IsLocationVisible(v)
		if vw == nil then return true end
		local d = dist(from, place)
		local i = d > 0 and math.floor(dist(from, v) / d * vw.n + 0.5) or 0
		i = math.max(0, math.min(vw.n, i))
		local nib = tonumber(vw.hex:sub(math.floor(i / 4) + 1, math.floor(i / 4) + 1), 16) or 0
		return math.floor(nib / 2 ^ (3 - i % 4)) % 2 == 1
	end
	function GetUnitToUnitDistance(a, c) return dist(a.loc, c.loc) end

	local res = Threat.Gate(bot, from, place, w.who or "gate")
	local r = res.r
	return {
		actions = { res.why and { verb = "hold", target = res.why } or { verb = "go" } },
		fact = { reach = #r.reach, missing = r.missing, mcut = r.mcut, burst = r.burst, allies = r.allies, tower = r.tower and 1 or 0 },
	}
end
