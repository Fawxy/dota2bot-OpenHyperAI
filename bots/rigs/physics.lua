-- Physics probe (branch oha-physics-probe, research only, never merged): server Lua, loaded like the setters
-- (`script_reload_code bots/rigs/physics`). `rig_phys <scenario>` runs one mechanic's trials with units this script makes
-- itself (no bot hero takes part), timed on the game clock, one `[RIG] phys ...` line per event.
--   stats   every lane creep type, a hero and the towers: the server's readable stats; turn rate and walk speed measured
--   acq     a hero stepped toward a standing creep: distance when the creep takes it (melee, ranged, siege, 3 each)
--   switch  a creep chasing a walking hero passes an idle allied creep of the hero's at a lateral offset: who it takes, where
--   order   a creep hitting a standing hero; the hero's attack order on its own creep (full HP and 40%), standing and walking
--   giveup  a creep chasing a hero that outruns it (450) or not (310): the gap, stand times, when it stops
--   block   a hero walking through a line of three allied creeps against an open line
--   tower   Radiant top T2: when it takes a hero, creep-first and hero-first, the hero hitting a hero, the hero's order
--           on its own creep, the hero stepping out
--   height  a Dire ranged creep on the 128 shelf at a target on the 256 plateau against the same on the flat: hits in 40 s,
--           first without Dire vision of the target, then with a viewer
-- Line of the main site: y=-2050 from x=-6000 to -4400 (flat 128, 1,280 or more from every tower).
local function say(s) print("[RIG] phys " .. s) end
local function now() return GameRules:GetDOTATime(false, false) end
local R, D = DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS
local Y = -2050
local X0 = -5900

local label, made = {}, {}
local function L(u)
	if u == nil then return "nil" end
	if u:IsNull() then return "null" end
	return label[u:entindex()] or u:GetUnitName()
end
local function d2(a, b) return (a:GetAbsOrigin() - b:GetAbsOrigin()):Length2D() end
local function edge(a, b) return d2(a, b) - a:GetHullRadius() - b:GetHullRadius() end
local function V(x, y) return Vector(x, y, 0) end
local function f0(v) return string.format("%.0f", v) end

local CREEP = {
	melee = "npc_dota_creep_%s_melee",
	ranged = "npc_dota_creep_%s_ranged",
	siege = "npc_dota_%s_siege",
	flag = "npc_dota_creep_%s_flagbearer",
}
local function side(team) return team == R and "goodguys" or "badguys" end

local function make(name, pos, team, lab)
	local u = CreateUnitByName(name, pos, true, nil, nil, team)
	if u == nil then
		say("make_fail " .. lab .. " " .. name)
		return nil
	end
	label[u:entindex()] = lab
	table.insert(made, u)
	return u
end
local function creep(kind, team, pos, lab) return make(string.format(CREEP[kind], side(team)), pos, team, lab) end

local function tank(u, hp)
	hp = hp or 20000
	pcall(function()
		u:SetBaseMaxHealth(hp)
		u:SetMaxHealth(hp)
		u:SetHealth(hp)
		u:SetBaseHealthRegen(200)
	end)
end
local function passive(u)
	pcall(function() u:SetIdleAcquire(false) end)
	pcall(function() u:SetAcquisitionRange(0) end)
	pcall(function() u:SetAttackCapability(DOTA_UNIT_CAP_NO_ATTACK) end)
end
local function hero(name, team, pos, lab, keepAttack)
	local u = make(name, pos, team, lab)
	if u == nil then return nil end
	tank(u)
	if keepAttack then
		pcall(function() u:SetIdleAcquire(false) end)
		pcall(function() u:SetAcquisitionRange(0) end)
	else
		passive(u)
	end
	return u
end
local function order(u, t, target, pos)
	ExecuteOrderFromTable({ UnitIndex = u:entindex(), OrderType = t, TargetIndex = target and target:entindex() or nil,
		Position = pos, Queue = false })
end
local function attackOrder(u, target) order(u, DOTA_UNIT_ORDER_ATTACK_TARGET, target) end
local function moveOrder(u, pos) order(u, DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, pos) end
local function clear()
	for _, u in ipairs(made) do
		if not u:IsNull() then
			pcall(function() u:ForceKill(false) end)
			pcall(function() UTIL_Remove(u) end)
		end
	end
	made = {}
end
-- Real heroes within 1500 of a point: a trial with one near is contaminated.
local function intruders(pos)
	local n = 0
	for _, h in ipairs(HeroList:GetAllHeroes()) do
		if h:IsAlive() and not h:IsIllusion() and (h:GetAbsOrigin() - pos):Length2D() < 1500 then n = n + 1 end
	end
	return n
end

-- The runner: a scenario is a list of trials; a trial is setup(ctx) then tick(ctx, dt) until it returns true or its
-- timeout. One think on a hero (a plain dota game has no game-mode entity to host it).
local function run(name, trials, onDone)
	local i, ctx, started = 0, nil, 0
	local last = now()
	local function nextTrial()
		clear()
		i = i + 1
		if i > #trials then
			say(name .. " done")
			if onDone then onDone() end
			return false
		end
		ctx = { t0 = now(), n = i, tag = trials[i].tag or tostring(i) }
		started = now()
		local ok, err = pcall(trials[i].setup, ctx)
		if not ok then
			say(name .. " setup_error " .. ctx.tag .. " " .. tostring(err))
			return nextTrial()
		end
		return true
	end
	if not nextTrial() then return end
	HeroList:GetAllHeroes()[1]:SetContextThink("rig_phys_" .. name, function()
		local t = now()
		local dt = t - last
		last = t
		if dt <= 0 then return 0.03 end
		local tr = trials[i]
		local ok, fin = pcall(tr.tick, ctx, t - ctx.t0, dt)
		if not ok then
			say(name .. " tick_error " .. ctx.tag .. " " .. tostring(fin))
			fin = true
		end
		if fin or t - started > (tr.timeout or 10) then
			if not fin then say(name .. " timeout " .. ctx.tag) end
			say(string.format("%s end %s t=%.2f intruders=%d", name, ctx.tag, t, intruders(V(ctx.cx or X0, ctx.cy or Y))))
			if not nextTrial() then return nil end
		end
		return 0.03
	end, 0)
	say(name .. " armed trials=" .. #trials)
end

-- A watcher: each tick, a change of a unit's attack target, and its walk/stand segments.
local function watch(ctx, u, others)
	ctx.w = ctx.w or {}
	table.insert(ctx.w, { u = u, tgt = false, pos = u:GetAbsOrigin(), moving = nil, since = now(), others = others })
end
local function watchTick(ctx, t)
	for _, w in ipairs(ctx.w or {}) do
		local u = w.u
		if not u:IsNull() and u:IsAlive() then
		local tg = u:GetAttackTarget()
		local aggro = nil
		pcall(function() aggro = u:GetAggroTarget() end)
		local key = L(tg) .. "/" .. L(aggro)
		if key ~= w.tgt then
			local ds = {}
			for _, o in ipairs(w.others or {}) do
				if not o:IsNull() and o:IsAlive() then
					table.insert(ds, string.format("%s=%s/%s", L(o), f0(d2(u, o)), f0(edge(u, o))))
				end
			end
			say(string.format("%s target t=%.2f rel=%.2f %s attack=%s aggro=%s moving=%s %s", ctx.tag, now(), t, L(u), L(tg), L(aggro),
				tostring(w.moving), table.concat(ds, " ")))
			w.tgt = key
		end
		local p = u:GetAbsOrigin()
		local mv = (p - w.pos):Length2D() > 0.5
		if mv ~= w.moving then
			if w.moving ~= nil and w.seg then
				say(string.format("%s seg %s %s for=%.2f rel=%.2f", ctx.tag, L(u), w.moving and "walk" or "stand", now() - w.since, t))
			end
			w.moving = mv
			w.since = now()
			w.seg = true
		end
		w.pos = p
		end
	end
end

local GETTERS = { "GetHullRadius", "GetPaddedCollisionRadius", "GetCollisionPadding", "Script_GetAttackRange", "GetAttackRangeBuffer",
	"GetAcquisitionRange", "GetAttackAnimationPoint", "GetBaseAttackTime", "GetAttackSpeed", "GetSecondsPerAttack",
	"GetProjectileSpeed", "GetBaseMoveSpeed", "GetIdealSpeed", "GetDayTimeVisionRange", "GetNightTimeVisionRange", "GetMaxHealth",
	"GetPhysicalArmorValue", "GetBaseDamageMin", "GetBaseDamageMax", "GetModelRadius" }
local function stats(u)
	local out = {}
	for _, g in ipairs(GETTERS) do
		local ok, v = pcall(function() return u[g](u, false) end)
		if ok and type(v) == "number" then table.insert(out, g:gsub("^Get", ""):gsub("^Script_Get", "") .. "=" .. string.format("%.3f", v)) end
	end
	local ok, mx = pcall(function() return u:GetBoundingMaxs() end)
	if ok and mx then table.insert(out, string.format("BoundMaxs=%.1f,%.1f", mx.x, mx.y)) end
	say(string.format("stat %s %s %s", L(u), u:GetUnitName(), table.concat(out, " ")))
end
local function yaw(u)
	local f = u:GetForwardVector()
	return math.deg(math.atan2(f.y, f.x))
end
local function angDiff(a, b)
	local d = (a - b) % 360
	if d > 180 then d = d - 360 end
	return d
end

local S = {}

-- stats ---------------------------------------------------------------------------------------------------------------
S.stats = {
	{
		tag = "stats",
		timeout = 12,
		setup = function(c)
			c.units = {}
			local x = X0
			for _, k in ipairs({ "melee", "ranged", "siege", "flag" }) do
				local u = creep(k, D, V(x, Y), k)
				if u then
					u:SetForwardVector(Vector(-1, 0, 0))
					table.insert(c.units, u)
					stats(u)
				end
				x = x + 300
			end
			for _, hn in ipairs({ "npc_dota_hero_axe", "npc_dota_hero_sniper" }) do
				local h = make(hn, V(X0 + 1400, Y), R, hn:gsub("npc_dota_hero_", ""))
				if h then
					stats(h)
					UTIL_Remove(h)
				end
			end
			for _, t in ipairs(Entities:FindAllByClassname("npc_dota_tower")) do
				local n = t:GetUnitName()
				if n == "npc_dota_goodguys_tower1_top" or n == "npc_dota_goodguys_tower2_top" or n == "npc_dota_goodguys_tower3_top"
					or n == "npc_dota_goodguys_tower4" then
					label[t:entindex()] = n
					stats(t)
				end
			end
			c.phase = "wait"
		end,
		tick = function(c, t)
			-- 1 s for the creeps to settle, then each turns 180 degrees and walks 2 s: turn time and speed.
			if c.phase == "wait" and t > 1 then
				c.phase = "turn"
				c.turn = {}
				for _, u in ipairs(c.units) do
					local p = u:GetAbsOrigin()
					local y0 = yaw(u)
					moveOrder(u, V(p.x + 1000, p.y))
					c.turn[u] = { y0 = y0, goal = y0 + 180, t0 = t, done = nil, p0 = nil }
				end
			elseif c.phase == "turn" then
				local all = true
				for u, s in pairs(c.turn) do
					if not u:IsNull() then
						if s.done == nil then
							if math.abs(angDiff(yaw(u), s.goal)) < 3 then
								s.done = t - s.t0
								s.p0 = u:GetAbsOrigin()
								s.tw = t
							end
							all = false
						elseif t - s.tw < 2 then
							all = false
						elseif not s.reported then
							s.reported = true
							say(string.format("turn %s deg=180 sec=%.3f deg_per_s=%.0f walk=%.0f in=%.2f speed=%.1f", L(u), s.done, 180 / math.max(0.001, s.done),
								(u:GetAbsOrigin() - s.p0):Length2D(), t - s.tw, (u:GetAbsOrigin() - s.p0):Length2D() / (t - s.tw)))
						end
					end
				end
				if all then return true end
			end
		end,
	},
}

-- acq -----------------------------------------------------------------------------------------------------------------
local function acqTrial(kind, dir, n)
	return {
		tag = "acq_" .. kind .. "_" .. n,
		timeout = 14,
		setup = function(c)
			c.cx, c.cy = X0 + 600, Y
			c.cr = creep(kind, D, V(c.cx, c.cy), kind)
			local a = math.rad(dir)
			c.dir = Vector(math.cos(a), math.sin(a), 0)
			c.h = hero("npc_dota_hero_axe", R, V(c.cx, c.cy) + c.dir * 1100, "axe")
			c.wait = 1
		end,
		tick = function(c, t, dt)
			if t < c.wait then return end
			local ag = nil
			pcall(function() ag = c.cr:GetAggroTarget() end)
			if c.cr:GetAttackTarget() == c.h or ag == c.h then
				say(string.format("acq %s kind=%s dir=%d centre=%s edge=%s hull_c=%.0f hull_h=%.0f acqrange=%.0f", c.n and c.tag or "",
					kind, dir, f0(d2(c.cr, c.h)), f0(edge(c.cr, c.h)), c.cr:GetHullRadius(), c.h:GetHullRadius(), c.cr:GetAcquisitionRange()))
				return true
			end
			-- 120 units a second toward the creep, placed (not walked) so the hero never has a move order.
			local p = c.h:GetAbsOrigin() - c.dir * (120 * dt)
			c.h:SetAbsOrigin(GetGroundPosition(p, c.h))
			if d2(c.cr, c.h) < 60 then
				say("acq " .. c.tag .. " none")
				return true
			end
		end,
	}
end
S.acq = {}
for _, k in ipairs({ "melee", "ranged", "siege" }) do
	for n, dir in ipairs({ 0, -90, 200 }) do table.insert(S.acq, acqTrial(k, dir, n)) end
end
-- A walking hero, not placed: the same read with a move order (melee only).
for n = 1, 2 do
	table.insert(S.acq, {
		tag = "acq_walk_melee_" .. n,
		timeout = 14,
		setup = function(c)
			c.cx, c.cy = X0 + 600, Y
			c.cr = creep("melee", D, V(c.cx, c.cy), "melee")
			c.h = hero("npc_dota_hero_axe", R, V(c.cx + 1100, c.cy), "axe")
			c.go = false
		end,
		tick = function(c, t)
			if t > 1 and not c.go then
				c.go = true
				moveOrder(c.h, V(c.cx - 1500, c.cy))
			end
			if c.go and c.cr:GetAttackTarget() == c.h then
				say(string.format("acq %s kind=melee walking centre=%s edge=%s", c.tag, f0(d2(c.cr, c.h)), f0(edge(c.cr, c.h))))
				return true
			end
		end,
	})
end

-- switch --------------------------------------------------------------------------------------------------------------
local function switchTrial(kind, off, rep)
	return {
		tag = string.format("switch_%s_off%d_%d", kind, off, rep),
		timeout = 12,
		setup = function(c)
			c.cx, c.cy = X0, Y
			c.cr = creep(kind, D, V(X0, Y), kind)
			tank(c.cr)
			local start = kind == "ranged" and 400 or 90
			c.h = hero("npc_dota_hero_axe", R, V(X0 + start, Y), "axe")
			c.r = creep("melee", R, V(X0 + start + 600, Y + off), "own")
			tank(c.r)
			passive(c.r)
			watch(c, c.cr, { c.h, c.r })
			c.go = false
		end,
		tick = function(c, t)
			watchTick(c, t)
			if t > 1.5 and not c.go then
				c.go = true
				say(string.format("%s go t=%.2f", c.tag, now()))
				moveOrder(c.h, V(X0 + 1700, Y))
			end
			if c.go and d2(c.h, c.cr) > 1300 then return true end
		end,
	}
end
S.switch = {}
for rep = 1, 2 do
	for _, off in ipairs({ 0, 150, 300, 450, 600 }) do table.insert(S.switch, switchTrial("melee", off, rep)) end
end
for _, off in ipairs({ 0, 300, 550 }) do table.insert(S.switch, switchTrial("ranged", off, 1)) end

-- order ---------------------------------------------------------------------------------------------------------------
local function orderTrial(kind, hp, walking, rep)
	return {
		tag = string.format("order_%s_hp%d_%s_%d", kind, hp, walking and "walk" or "stand", rep),
		timeout = 9,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			c.cr = creep(kind, D, V(c.cx, c.cy), kind)
			tank(c.cr)
			local start = kind == "ranged" and 400 or 90
			c.h = hero("npc_dota_hero_axe", R, V(c.cx + start, c.cy), "axe", true)
			-- Our creep stands 250 beside the attacker, at full or 40% of its health.
			c.r = creep("melee", R, V(c.cx + 60, c.cy + 250), "own")
			passive(c.r)
			c.r:SetHealth(math.floor(c.r:GetMaxHealth() * hp / 100))
			watch(c, c.cr, { c.h, c.r })
			c.step = 0
		end,
		tick = function(c, t)
			watchTick(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				if walking then moveOrder(c.h, V(c.cx + 1500, c.cy)) end
			elseif c.step == 1 and t > (walking and 2.3 or 2.0) then
				c.step = 2
				say(string.format("%s order t=%.2f rel=%.2f attacker_on=%s hero_d=%s own_d=%s own_hp=%d", c.tag, now(), t, L(c.cr:GetAttackTarget()),
					f0(d2(c.cr, c.h)), f0(d2(c.cr, c.r)), c.r:GetHealth()))
				attackOrder(c.h, c.r)
			elseif c.step == 2 and t > 2.6 then
				c.step = 3
				-- The hero's own order: what it is doing 0.3 s after (an attack refused on a full-HP ally reads nil).
				say(string.format("%s hero_after attack=%s", c.tag, L(c.h:GetAttackTarget())))
				if walking then moveOrder(c.h, V(c.cx + 1500, c.cy)) end
			end
		end,
	}
end
S.order = {}
for rep = 1, 2 do
	for _, hp in ipairs({ 100, 40 }) do
		table.insert(S.order, orderTrial("melee", hp, false, rep))
		table.insert(S.order, orderTrial("melee", hp, true, rep))
	end
end
for _, hp in ipairs({ 100, 40 }) do table.insert(S.order, orderTrial("ranged", hp, false, 1)) end
-- Control: no order, a standing hero beside our creep for the same time.
for rep = 1, 2 do
	table.insert(S.order, {
		tag = "order_control_" .. rep,
		timeout = 7,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			c.cr = creep("melee", D, V(c.cx, c.cy), "melee")
			tank(c.cr)
			c.h = hero("npc_dota_hero_axe", R, V(c.cx + 90, c.cy), "axe", true)
			c.r = creep("melee", R, V(c.cx + 60, c.cy + 250), "own")
			passive(c.r)
			watch(c, c.cr, { c.h, c.r })
		end,
		tick = function(c, t) watchTick(c, t) end,
	})
end

-- giveup --------------------------------------------------------------------------------------------------------------
local function giveupTrial(kind, speed, rep)
	return {
		tag = string.format("giveup_%s_ms%d_%d", kind, speed, rep),
		timeout = 22,
		setup = function(c)
			c.cx, c.cy = X0 - 100, Y
			c.cr = creep(kind, D, V(c.cx, c.cy), kind)
			tank(c.cr)
			local start = kind == "ranged" and 400 or 90
			c.h = hero("npc_dota_hero_axe", R, V(c.cx + start, c.cy), "axe")
			pcall(function() c.h:SetBaseMoveSpeed(speed) end)
			watch(c, c.cr, { c.h })
			c.go, c.lastLog = false, 0
			c.home = c.cr:GetAbsOrigin()
		end,
		tick = function(c, t)
			watchTick(c, t)
			if t > 1.5 and not c.go then
				c.go = true
				moveOrder(c.h, V(-4300, Y))
				say(string.format("%s go t=%.2f hero_speed=%.0f", c.tag, now(), c.h:GetIdealSpeed()))
			end
			if c.go and t - c.lastLog >= 0.5 then
				c.lastLog = t
				say(string.format("%s gap rel=%.2f gap=%s edge=%s creep_from_home=%s hero_x=%s attack=%s", c.tag, t, f0(d2(c.cr, c.h)), f0(edge(c.cr, c.h)),
					f0((c.cr:GetAbsOrigin() - c.home):Length2D()), f0(c.h:GetAbsOrigin().x), L(c.cr:GetAttackTarget())))
			end
			if c.go and c.h:GetAbsOrigin().x > -4400 then
				-- The hero stands at the end: does the creep still come?
				if c.endAt == nil then c.endAt = t end
				if t - c.endAt > 6 then return true end
			end
		end,
	}
end
S.giveup = {}
for rep = 1, 2 do
	table.insert(S.giveup, giveupTrial("melee", 450, rep))
	table.insert(S.giveup, giveupTrial("melee", 310, rep))
end
table.insert(S.giveup, giveupTrial("ranged", 450, 1))
table.insert(S.giveup, giveupTrial("ranged", 310, 1))

-- block ---------------------------------------------------------------------------------------------------------------
local function blockTrial(withCreeps, team, rep)
	return {
		tag = string.format("block_%s_%d", withCreeps and (team == R and "own" or "enemy") or "open", rep),
		timeout = 12,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			c.h = hero("npc_dota_hero_axe", R, V(X0, Y), "axe")
			if withCreeps then
				for k = -1, 1 do
					local u = creep("melee", team, V(X0 + 400, Y + k * 40), "wall")
					tank(u)
					passive(u)
					pcall(function() u:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
				end
			end
			c.go, c.path, c.prev = false, 0, nil
		end,
		tick = function(c, t)
			if t > 1 and not c.go then
				c.go = true
				c.tgo = t
				c.prev = c.h:GetAbsOrigin()
				moveOrder(c.h, V(X0 + 800, Y))
			end
			if c.go then
				local p = c.h:GetAbsOrigin()
				c.path = c.path + (p - c.prev):Length2D()
				c.maxdev = math.max(c.maxdev or 0, math.abs(p.y - Y))
				c.prev = p
				if (p - V(X0 + 800, Y)):Length2D() < 10 then
					say(string.format("%s arrived sec=%.2f path=%.0f straight=800 max_dev=%.0f", c.tag, t - c.tgo, c.path, c.maxdev))
					return true
				end
			end
		end,
	}
end
S.block = {}
for rep = 1, 2 do
	table.insert(S.block, blockTrial(false, R, rep))
	table.insert(S.block, blockTrial(true, R, rep))
	table.insert(S.block, blockTrial(true, D, rep))
end

-- tower ---------------------------------------------------------------------------------------------------------------
local function tower2()
	for _, t in ipairs(Entities:FindAllByClassname("npc_dota_tower")) do
		if t:GetUnitName() == "npc_dota_goodguys_tower2_top" then return t end
	end
end
local function towerWatch(c, tw, others)
	label[tw:entindex()] = "T2"
	watch(c, tw, others)
end
S.tower = {}
for n, dir in ipairs({ -30, -60, -90 }) do
	table.insert(S.tower, {
		tag = "tower_approach_" .. n,
		timeout = 14,
		setup = function(c)
			c.tw = tower2()
			local o = c.tw:GetAbsOrigin()
			c.cx, c.cy = o.x, o.y
			local a = math.rad(dir)
			c.dir = Vector(math.cos(a), math.sin(a), 0)
			c.h = hero("npc_dota_hero_sniper", D, o + c.dir * 1150, "dhero")
			c.dir = c.dir
		end,
		tick = function(c, t, dt)
			if t < 1 then return end
			if c.tw:GetAttackTarget() == c.h then
				say(string.format("tower_take %s dir=%d centre=%s edge=%s hull_t=%.0f hull_h=%.0f range=%d", c.tag, dir, f0(d2(c.tw, c.h)), f0(edge(c.tw, c.h)),
					c.tw:GetHullRadius(), c.h:GetHullRadius(), c.tw:Script_GetAttackRange()))
				return true
			end
			local p = c.h:GetAbsOrigin() - c.dir * (100 * dt)
			c.h:SetAbsOrigin(GetGroundPosition(p, c.h))
		end,
	})
end
-- Placement inside the reach, toward the Radiant side (south-east of the T2), 450 from its centre.
local function inReach(c, k, spread)
	local o = c.tw:GetAbsOrigin()
	local a = math.rad(-60 + spread)
	return V(o.x + 450 * math.cos(a), o.y + 450 * math.sin(a))
end
for rep = 1, 2 do
	table.insert(S.tower, {
		tag = "tower_creep_first_" .. rep,
		timeout = 8,
		setup = function(c)
			c.tw = tower2()
			c.cx, c.cy = c.tw:GetAbsOrigin().x, c.tw:GetAbsOrigin().y
			c.cr = creep("melee", D, inReach(c, 1, 0), "dcreep")
			tank(c.cr)
			passive(c.cr)
			c.step = 0
			towerWatch(c, c.tw, { c.cr })
		end,
		tick = function(c, t)
			watchTick(c, t)
			if c.step == 0 and t > 2 then
				c.step = 1
				c.h = hero("npc_dota_hero_sniper", D, inReach(c, 2, -25), "dhero")
				c.w[1].others = { c.cr, c.h }
				say(c.tag .. " hero_in t=" .. string.format("%.2f", now()))
			end
		end,
	})
	table.insert(S.tower, {
		tag = "tower_hero_first_" .. rep,
		timeout = 8,
		setup = function(c)
			c.tw = tower2()
			c.cx, c.cy = c.tw:GetAbsOrigin().x, c.tw:GetAbsOrigin().y
			c.h = hero("npc_dota_hero_sniper", D, inReach(c, 2, -25), "dhero")
			c.step = 0
			towerWatch(c, c.tw, { c.h })
		end,
		tick = function(c, t)
			watchTick(c, t)
			if c.step == 0 and t > 2 then
				c.step = 1
				c.cr = creep("melee", D, inReach(c, 1, 0), "dcreep")
				tank(c.cr)
				passive(c.cr)
				c.w[1].others = { c.cr, c.h }
				say(c.tag .. " creep_in t=" .. string.format("%.2f", now()))
			end
		end,
	})
	-- Tower on a creep; the hero attacks a Radiant hero in reach (the call for help); then the hero's attack order on its
	-- own creep; then the hero walks out of reach.
	table.insert(S.tower, {
		tag = "tower_help_" .. rep,
		timeout = 14,
		setup = function(c)
			c.tw = tower2()
			c.cx, c.cy = c.tw:GetAbsOrigin().x, c.tw:GetAbsOrigin().y
			c.cr = creep("melee", D, inReach(c, 1, 0), "dcreep")
			tank(c.cr)
			passive(c.cr)
			c.h = hero("npc_dota_hero_sniper", D, inReach(c, 2, -40), "dhero", true)
			c.a = hero("npc_dota_hero_axe", R, inReach(c, 3, -55), "rhero")
			c.step = 0
			towerWatch(c, c.tw, { c.cr, c.h, c.a })
		end,
		tick = function(c, t)
			watchTick(c, t)
			if c.step == 0 and t > 2 then
				c.step = 1
				say(string.format("%s hit_hero t=%.2f", c.tag, now()))
				attackOrder(c.h, c.a)
			elseif c.step == 1 and t > 5 then
				c.step = 2
				say(string.format("%s own_order t=%.2f tower_on=%s", c.tag, now(), L(c.tw:GetAttackTarget())))
				order(c.h, DOTA_UNIT_ORDER_STOP)
				attackOrder(c.h, c.cr)
			elseif c.step == 2 and t > 8 then
				c.step = 3
				-- Back on the hero first (a fresh call for help), then walk out of reach.
				attackOrder(c.h, c.a)
			elseif c.step == 3 and t > 10 then
				c.step = 4
				local o = c.tw:GetAbsOrigin()
				say(string.format("%s walk_out t=%.2f tower_on=%s", c.tag, now(), L(c.tw:GetAttackTarget())))
				moveOrder(c.h, V(o.x + 1400, o.y - 600))
			end
		end,
	})
end

-- height --------------------------------------------------------------------------------------------------------------
local function heightTrial(tag, sx, sy, tx, ty, viewer, secs)
	return {
		tag = tag,
		timeout = secs + 3,
		setup = function(c)
			c.cx, c.cy = sx, sy
			c.s = creep("ranged", D, V(sx, sy), "shooter")
			tank(c.s)
			pcall(function() c.s:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			c.u = creep("melee", R, V(tx, ty), "target")
			tank(c.u, 100000)
			passive(c.u)
			pcall(function() c.u:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			pcall(function() c.u:SetBaseHealthRegen(0) end)
			if viewer then AddFOWViewer(D, V(tx, ty), 300, secs + 2, false) end
			c.hits, c.first = 0, nil
			c.hp = c.u:GetHealth()
			c.lastAttack = nil
			say(string.format("%s setup z_shooter=%.0f z_target=%.0f dist=%s edge=%s vis_dire=%s", tag, c.s:GetAbsOrigin().z, c.u:GetAbsOrigin().z,
				f0(d2(c.s, c.u)), f0(edge(c.s, c.u)), tostring(c.u:CanBeSeenByAnyOpposingTeam())))
		end,
		tick = function(c, t)
			local hp = c.u:GetHealth()
			if hp < c.hp then
				c.hits = c.hits + 1
				c.first = c.first or t
			end
			c.hp = hp
			if c.s:GetAttackTarget() == c.u and c.attackSeen == nil then c.attackSeen = t end
			if t >= secs then
				local from = c.first or secs
				say(string.format("%s result hits=%d first_hit=%.2f attack_target_at=%s span=%.2f hits_per_s=%.3f spa=%.3f", tag, c.hits, from,
					tostring(c.attackSeen and string.format("%.2f", c.attackSeen) or "never"), secs - from, c.hits / math.max(0.01, secs - from), c.s:GetSecondsPerAttack(false)))
				return true
			end
		end,
	}
end
S.height = {
	heightTrial("height_up_novision", -2750, -250, -3170, -250, false, 10),
	heightTrial("height_up_viewer", -2750, -250, -3170, -250, true, 45),
	heightTrial("height_flat", -3600, -250, -4020, -250, false, 45),
	heightTrial("height_down", -3170, -250, -2750, -250, false, 45),
}

-- rig_phys <scenario> [<scenario> ...]: the scenarios one after another (they share the unit list, so never two at once).
Convars:RegisterCommand("rig_phys", function(_, ...)
	local names = { ... }
	local k = 0
	local function nextOne()
		k = k + 1
		local name = names[k]
		if name == nil then return say("all done t=" .. string.format("%.2f", now())) end
		local s = S[name]
		if s == nil then
			say("unknown " .. tostring(name))
			return nextOne()
		end
		say(string.format("start %s t=%.2f", name, now()))
		run(name, s, nextOne)
	end
	local ok, err = pcall(nextOne)
	if not ok then say("error " .. tostring(err)) end
end, "rig: run one physics probe scenario", FCVAR_CHEAT)

say("registered")
