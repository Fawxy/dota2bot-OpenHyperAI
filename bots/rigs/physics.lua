-- Physics probe: server Lua, loaded like the setters
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
--   order2  as order, our creep put nearer the attacker than the hero; with and without the order
--   tower2  the T2 on a creep while our hero hits theirs (the call for help); the order on our creep, nearer the tower
--   lanegoal a creep given the nearest Dire path corner as its goal, chasing a hero that walks off at 450
--   trees   clear the site's trees again (they regrow about 5 min after the load clears them)
--   height  a Dire ranged creep on the 128 shelf at a target on the 256 plateau against the same on the flat: hits in 40 s,
--           first without Dire vision of the target, then with a viewer
--   repick  a creep on a hero who walks off, two idle creeps of ours still beside it: nearest by centre or by edge
--   threat  as repick, an idle creep of ours nearer and a fighting one farther (on a dummy, or on the attacker);
--           threat2 the same with the idle creep able to attack
--   lateral switch at offsets 50 and 100
--   order3  the order on our creep when it is clearly nearer the attacker than the hero (ranged and melee attacker)
--   fog     a creep on a standing hero; the hero moved 600, 900 or 1300 away, with and without a Dire viewer there
--   ramp    a creep chasing a hero who walks up the ramp north-east of the site (128 to 256), at 310 and 450
--   height2 uphill with an observer ward, a hero shooter uphill and flat, a ranged creep from the river onto a shelf
--   towerpref a creep and a hero put in the T2's reach on the same tick at different distances
--   turn    yaw every tick from facing east to walking west (two heroes, two creeps)
--   swing   a hero walks off at a creep's landed hit, or 0.5 s after: when the creep first moves
--   fogwalk as fog at 900, the hero then walks 500 north in the fog; ramp2, towerpref2: more reps, the centre/edge ties
--   real    a creep of the real Dire waves moved to the site: chase, and re-pick with our creep beside it
-- Round 3, protective aggro (the hero's attack order on an enemy hero; Dire creeps fighting a passive Radiant bait first):
--   draw    one creep (melee, ranged) at centre 460 to 600 from the hero: drawn or not, and how soon
--   chase   a drawn wave (two melee, one ranged) on a hero that stands, or walks off at 300 or 350: how long each stays
--   reshow  the draw at the ramp's foot, the hero walks up at 400: no second order, one at first unseen, one past 3.1 s
--   release the hero walks back past our ranged creep: no order, the attack order on our creep, or round it then the order;
--           made and real wave creeps
--   restrict a real (and a made) creep drawn far from every tower, near the Radiant top T1, near the Dire top T1
-- Round 3b (round 3 drew only with the target hero near and in sight):
--   why     the target hero 300 to 1,200 beyond ours on the flat; then a hold, a move away or nothing; the hero's state
--   radius  the target 300 beyond, a hold; the creep (melee, ranged) at centre 350 to 500
--   chase2, reshow2, release2  as chase, reshow, release (made creeps) with the target 300 away in sight, the walk at 0.8 s
-- Round 3c:
--   reshow3 the climb starts inside the draw's window (speed 300): no second order, one inside the cooldown, one past
--           3.1 s, and Dire vision kept on the hero as the control
--   release3 the order on our creep at 2.6 s, after the window, with the hero level with our creep or in front of it
--   lanes   real waves where they meet: a Dire creep fighting ours, drawn from 300; its distance to every tier one
--           (leaves real lane creeps alive)
-- Round 3d:
--   reshow4 up the ramp at 300, 200 or 150; or a landed hit on a chaser halfway up, or on the nearest creep once unseen
--   down    the draw from the high ground down to ours: the chase, and the hand-over to our ranged creep below
-- Round 3e:
--   clash   before 5:00, a real Dire wave stopped by a bait at a spot within 1,500 of their T1, ours, both or neither,
--           and drawn there (kills the real Radiant lane creeps within 2,500 of the spot while it waits)
-- Round 3f:
--   swingdraw the hand-over walk with one attack on the nearest chaser at 1.3 s (a landed hit, or a last hit at 40 HP),
--           against no attack: whether the draw lasts longer and who the chasers take at its end
-- Line of the main site: y=-2050 from x=-5700 to -4300 (flat 128, 1,280 or more from every tower, trees cleared).
-- Round 3 also kills real lane creeps within 1800 of the top T1 sites (-6336,600) and (-6300,5300), and moves real Dire
-- wave creeps to the main site (release, restrict).
-- What it changes in a game: loading clears the trees within 1300 of (-5100,-2050) and precaches axe and sniper; a running
-- scenario kills the real lane creeps (melee, ranged, siege) within 1800 of its trial site, including near the Radiant top
-- T2 (tower, tower2, towerpref), around the ramp's foot (-5848,-2136) and at the height sites (one in the river by mid);
-- height2 makes a Dire observer ward and Dire snipers at its sites for about 48 s; fog, fogwalk and height give Dire vision
-- (AddFOWViewer); `real` moves a real Dire wave creep to the site and kills it after.
-- Results and the API calls that read each value: master docs/reference/specifics/engine-physics.md.
local function say(s) print("[RIG] phys " .. s) end
local function now() return GameRules:GetDOTATime(false, false) end
local R, D = DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS
local Y = -2050
local X0 = -5700

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
			label[u:entindex()] = nil
			pcall(function() u:ForceKill(false) end)
			pcall(function() UTIL_Remove(u) end)
		end
	end
	made = {}
	-- Every label goes, also of a unit already removed: a reused entity index must not hide a real creep (strays, grabReal).
	label = {}
end
-- Real heroes within 1500 of a point: a trial with one near is contaminated.
local function intruders(pos)
	local n = 0
	for _, h in ipairs(HeroList:GetAllHeroes()) do
		if label[h:entindex()] == nil and h:IsAlive() and not h:IsIllusion() and (h:GetAbsOrigin() - pos):Length2D() < 1500 then n = n + 1 end
	end
	return n
end

-- Lane creeps of the real waves within 1800 of a point (probe 2: one walked onto the site and took the chasers): killed.
local function strays(pos)
	local n = 0
	for _, team in ipairs({ R, D }) do
		for _, u in ipairs(FindUnitsInRadius(team, pos, nil, 1800, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BASIC, 0, 0, false)) do
			if label[u:entindex()] == nil and (u:GetClassname() == "npc_dota_creep_lane" or u:GetClassname() == "npc_dota_creep_siege") and u:IsAlive() then
				u:ForceKill(false)
				n = n + 1
			end
		end
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
		local k = ctx.keep and 0 or strays(V(ctx.cx or X0, ctx.cy or Y))
		if k > 0 then say(string.format("%s strays_killed %s n=%d", name, ctx.tag, k)) end
		if not ok then
			say(name .. " setup_error " .. ctx.tag .. " " .. tostring(err))
			return nextTrial()
		end
		return true
	end
	if not nextTrial() then return end
	local host = HeroList:GetAllHeroes()[1]
	if host == nil then return say(name .. " no_host_hero") end
	local body
	host:SetContextThink("rig_phys_" .. name, function()
		local ok, v = pcall(body)
		if ok then return v end
		say(name .. " runner_error " .. tostring(v))
		return nil
	end, 0)
	body = function()
		local t = now()
		local dt = t - last
		last = t
		if dt <= 0 then return 0.03 end
		local tr = trials[i]
		if not ctx.keep and math.floor(t * 2) ~= math.floor((t - dt) * 2) then
			local k = strays(V(ctx.cx or X0, ctx.cy or Y))
			if k > 0 then say(string.format("%s strays_killed_mid %s n=%d", name, ctx.tag, k)) end
		end
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
	end
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
		local ok, v = pcall(function() return u[g](u) end)
		if not ok or type(v) ~= "number" then ok, v = pcall(function() return u[g](u, false) end) end
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
					c.turn[u] = { y0 = y0, goal = y0 + 180, t0 = t, done = nil, p0 = nil, pl = p }
				end
			elseif c.phase == "turn" then
				local all = true
				for u, s in pairs(c.turn) do
					if not u:IsNull() then
						if s.done == nil then
							local pp = u:GetAbsOrigin()
							if s.mv == nil and (pp - s.pl):Length2D() > 1 then
								s.mv = t - s.t0
								s.mvyaw = angDiff(yaw(u), s.goal)
							end
							s.pl = pp
							if s.t10 == nil and math.abs(angDiff(yaw(u), s.goal)) < 10 then s.t10 = t - s.t0 end
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
							say(string.format("turn %s first_move=%s yaw_off_then=%s within10=%s", L(u), tostring(s.mv), tostring(s.mvyaw), tostring(s.t10)))
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
			c.cx, c.cy = X0 + 700, Y
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
	for n, dir in ipairs({ 0, 180, 0, 180 }) do table.insert(S.acq, acqTrial(k, dir, n)) end
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


-- order2: the order on our creep when it is nearer the attacker than the hero (probe 2's re-picks took the nearer unit) ----
local function order2Trial(withOrder, rep)
	return {
		tag = string.format("order2_%s_%d", withOrder and "order" or "control", rep),
		timeout = 6,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			c.cr = creep("melee", D, V(c.cx, c.cy), "melee")
			tank(c.cr)
			c.h = hero("npc_dota_hero_axe", R, V(c.cx + 90, c.cy), "axe", true)
			c.step = 0
			watch(c, c.cr, { c.h })
		end,
		tick = function(c, t)
			watchTick(c, t)
			if c.step == 0 and t > 1.0 then
				-- Our creep put beside the attacker, nearer than the hero, once the attacker is on the hero.
				c.step = 1
				c.r = creep("melee", R, V(c.cx - 20, c.cy - 55), "own")
				passive(c.r)
				c.w[1].others = { c.h, c.r }
				say(string.format("%s own_in rel=%.2f on=%s hero_d=%s own_d=%s", c.tag, t, L(c.cr:GetAttackTarget()), f0(d2(c.cr, c.h)), f0(d2(c.cr, c.r))))
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				say(string.format("%s %s rel=%.2f on=%s hero_d=%s own_d=%s", c.tag, withOrder and "order" or "no_order", t, L(c.cr:GetAttackTarget()),
					f0(d2(c.cr, c.h)), f0(d2(c.cr, c.r))))
				if withOrder then attackOrder(c.h, c.r) end
			end
		end,
	}
end
S.order2 = {}
for rep = 1, 3 do
	table.insert(S.order2, order2Trial(true, rep))
	table.insert(S.order2, order2Trial(false, rep))
end

-- tower2: the call for help from a tower on a creep; the order on our creep with the creep nearer the tower ------------
S.tower2 = {}
for rep = 1, 3 do
	table.insert(S.tower2, {
		tag = "tower2_help_" .. rep,
		timeout = 10,
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
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_sniper", D, inReach(c, 2, -40), "dhero", true)
				c.a = hero("npc_dota_hero_axe", R, inReach(c, 3, -55), "rhero")
				c.w[1].others = { c.cr, c.h, c.a }
				say(string.format("%s heroes_in rel=%.2f on=%s", c.tag, t, L(c.tw:GetAttackTarget())))
			elseif c.step == 1 and t > 3.5 then
				c.step = 2
				say(string.format("%s hit_hero rel=%.2f on=%s", c.tag, t, L(c.tw:GetAttackTarget())))
				attackOrder(c.h, c.a)
			end
		end,
	})
	for _, withOrder in ipairs({ true, false }) do
		table.insert(S.tower2, {
			tag = string.format("tower2_own_%s_%d", withOrder and "order" or "control", rep),
			timeout = 8,
			setup = function(c)
				c.tw = tower2()
				local o = c.tw:GetAbsOrigin()
				c.cx, c.cy = o.x, o.y
				-- The hero at 600 from the tower's centre, our creep at 350: nearer the tower.
				local a = math.rad(-60)
				c.h = hero("npc_dota_hero_sniper", D, V(o.x + 600 * math.cos(a), o.y + 600 * math.sin(a)), "dhero", true)
				c.step = 0
				towerWatch(c, c.tw, { c.h })
			end,
			tick = function(c, t)
				watchTick(c, t)
				if c.step == 0 and t > 1.5 then
					c.step = 1
					local o = c.tw:GetAbsOrigin()
					local a = math.rad(-75)
					c.cr = creep("melee", D, V(o.x + 350 * math.cos(a), o.y + 350 * math.sin(a)), "dcreep")
					tank(c.cr)
					passive(c.cr)
					c.w[1].others = { c.h, c.cr }
				elseif c.step == 1 and t > 3 then
					c.step = 2
					say(string.format("%s %s rel=%.2f on=%s hero_d=%s creep_d=%s", c.tag, withOrder and "order" or "no_order", t, L(c.tw:GetAttackTarget()),
						f0(d2(c.tw, c.h)), f0(d2(c.tw, c.cr))))
					if withOrder then attackOrder(c.h, c.cr) end
				end
			end,
		})
	end
end

-- lanegoal: a Dire melee creep given the nearest Dire path corner as its goal, aggroed by a hero that walks off east ----
S.lanegoal = {}
for rep = 1, 2 do
	table.insert(S.lanegoal, {
		tag = "lanegoal_" .. rep,
		timeout = 16,
		setup = function(c)
			c.cx, c.cy = X0, Y
			local best, bd
			for _, e in ipairs(Entities:FindAllByClassname("path_corner")) do
				local n = e:GetName()
				local d = (e:GetAbsOrigin() - V(X0, Y)):Length2D()
				if string.find(n, "bad") and (bd == nil or d < bd) then best, bd = e, d end
			end
			if best == nil then error("no Dire path_corner") end
			say(string.format("%s goal %s at %s,%s d=%s", c.tag, best:GetName(), f0(best:GetAbsOrigin().x), f0(best:GetAbsOrigin().y), f0(bd)))
			c.cr = creep("melee", D, V(X0, Y), "melee")
			tank(c.cr)
			c.cr:SetInitialGoalEntity(best)
			c.h = hero("npc_dota_hero_axe", R, V(X0 + 300, Y), "axe")
			pcall(function() c.h:SetBaseMoveSpeed(450) end)
			c.home = c.cr:GetAbsOrigin()
			c.go, c.lastLog = false, 0
			watch(c, c.cr, { c.h })
		end,
		tick = function(c, t)
			watchTick(c, t)
			if not c.go and c.cr:GetAttackTarget() == c.h then
				c.go = true
				c.tgo = t
				moveOrder(c.h, V(-4300, Y))
				say(string.format("%s go rel=%.2f", c.tag, t))
			end
			if t - c.lastLog >= 0.5 then
				c.lastLog = t
				local p = c.cr:GetAbsOrigin()
				say(string.format("%s pos rel=%.2f creep=%s,%s gap=%s from_home=%s attack=%s", c.tag, t, f0(p.x), f0(p.y), f0(d2(c.cr, c.h)),
					f0((p - c.home):Length2D()), L(c.cr:GetAttackTarget())))
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

-- Round 2 (the open questions) ----------------------------------------------------------------------------------------
local function at(o, d, deg)
	local a = math.rad(deg)
	return V(o.x + d * math.cos(a), o.y + d * math.sin(a))
end
local function still(u)
	tank(u)
	passive(u)
	pcall(function() u:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
end
local function visible(u) return u:CanBeSeenByAnyOpposingTeam() and "seen" or "fog" end

-- repick: a Dire ranged creep hitting a standing hero; the hero walks off east at 450; two idle candidates of ours stand
-- still, north and south of the attacker: which it takes. The split pairs separate nearest by centre from nearest by edge.
local function repickTrial(tag, cands)
	return {
		tag = tag,
		timeout = 7,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			local o = V(c.cx, c.cy)
			c.cr = creep("ranged", D, o, "attacker")
			tank(c.cr)
			pcall(function() c.cr:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			c.h = hero("npc_dota_hero_sniper", R, V(c.cx + 450, c.cy), "hero")
			pcall(function() c.h:SetBaseMoveSpeed(450) end)
			watch(c, c.cr, { c.h })
			c.go = false
		end,
		tick = function(c, t)
			watchTick(c, t)
			if t > 1 and not c.placed then
				-- After the attacker is on the hero (a candidate there at spawn is taken at once, round 2a).
				c.placed = true
				local o = c.cr:GetAbsOrigin()
				for _, k in ipairs(cands) do
					local u = creep(k[1], R, at(o, k[2], k[3]), k[4])
					still(u)
					u:SetAbsOrigin(GetGroundPosition(at(o, k[2], k[3]), u))
					table.insert(c.w[1].others, u)
				end
			end
			if t > 2 and not c.go then
				c.go = true
				say(string.format("%s go rel=%.2f on=%s", c.tag, t, L(c.cr:GetAttackTarget())))
				moveOrder(c.h, V(c.cx + 2000, c.cy))
			end
		end,
	}
end
S.repick = {}
for rep = 1, 2 do
	local n, s = rep == 1 and 90 or -90, rep == 1 and -90 or 90
	-- centre picks the ranged (300 against 306); edge picks the melee (284 against 282). Spawn order swapped.
	table.insert(S.repick, repickTrial("repick_split_r" .. rep, { { "ranged", 300, n, "own_r" }, { "melee", 306, s, "own_m" } }))
	table.insert(S.repick, repickTrial("repick_split_m" .. rep, { { "melee", 306, s, "own_m" }, { "ranged", 300, n, "own_r" } }))
	-- controls: both rules agree.
	table.insert(S.repick, repickTrial("repick_melee_near_" .. rep, { { "melee", 280, n, "own_m" }, { "ranged", 330, s, "own_r" } }))
	table.insert(S.repick, repickTrial("repick_ranged_near_" .. rep, { { "ranged", 280, n, "own_r" }, { "melee", 340, s, "own_m" } }))
end

-- threat: as repick, an idle creep of ours at 250 and a fighting one at 350 (attacking a Dire dummy, or the attacker).
local function threatTrial(tag, onAttacker, idleArmed)
	return {
		tag = tag,
		timeout = 8,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			local o = V(c.cx, c.cy)
			c.cr = creep("ranged", D, o, "attacker")
			tank(c.cr)
			pcall(function() c.cr:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			c.h = hero("npc_dota_hero_sniper", R, V(c.cx + 450, c.cy), "hero")
			pcall(function() c.h:SetBaseMoveSpeed(450) end)
			if onAttacker then
				c.victim = c.cr
			else
				c.victim = creep("melee", D, at(o, 700, -90), "dummy")
				still(c.victim)
			end
			watch(c, c.cr, { c.h })
			c.go, c.lastOrder = false, -1
		end,
		tick = function(c, t)
			watchTick(c, t)
			if t > 0.8 and not c.placed then
				c.placed = true
				local o = c.cr:GetAbsOrigin()
				c.idle = creep("melee", R, at(o, 250, 90), "idle")
				if idleArmed then
					tank(c.idle)
					pcall(function() c.idle:SetIdleAcquire(false) end)
					pcall(function() c.idle:SetAcquisitionRange(0) end)
					pcall(function() c.idle:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
				else
					still(c.idle)
				end
				c.idle:SetAbsOrigin(GetGroundPosition(at(o, 250, 90), c.idle))
				c.f = creep("ranged", R, at(o, 350, -90), "fighter")
				tank(c.f)
				pcall(function() c.f:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
				c.w[1].others = { c.h, c.idle, c.f }
			end
			if c.f and c.victim and t - c.lastOrder > 0.5 then
				c.lastOrder = t
				if c.f:GetAttackTarget() ~= c.victim then attackOrder(c.f, c.victim) end
			end
			if t > 2.5 and not c.go then
				c.go = true
				say(string.format("%s go rel=%.2f on=%s fighter_on=%s", c.tag, t, L(c.cr:GetAttackTarget()), L(c.f:GetAttackTarget())))
				moveOrder(c.h, V(c.cx + 2000, c.cy))
			end
		end,
	}
end
S.threat2 = {}
for rep = 1, 3 do
	table.insert(S.threat2, threatTrial("threat2_dummy_" .. rep, false, true))
	table.insert(S.threat2, threatTrial("threat2_attacker_" .. rep, true, true))
end
S.threat = {}
for rep = 1, 2 do
	table.insert(S.threat, threatTrial("threat_dummy_" .. rep, false))
	table.insert(S.threat, threatTrial("threat_attacker_" .. rep, true))
end

-- lateral: the chase past our idle creep at the small offsets switch left between 0 and 150.
S.lateral = {}
for rep = 1, 2 do
	for _, off in ipairs({ 50, 100 }) do table.insert(S.lateral, switchTrial("melee", off, rep)) end
end

-- order3: the hero's attack order on its own creep when that creep is clearly nearer the attacker than the hero.
-- ranged: attacker on a sniper at 450, our creep 150 beside it. melee: attacker on an axe at 135, our creep set at 50.
local function order3Trial(kind, withOrder, rep)
	return {
		tag = string.format("order3_%s_%s_%d", kind, withOrder and "order" or "control", rep),
		timeout = 6,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			local o = V(c.cx, c.cy)
			c.cr = creep(kind, D, o, "attacker")
			tank(c.cr)
			pcall(function() c.cr:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			if kind == "ranged" then
				c.h = hero("npc_dota_hero_sniper", R, V(c.cx + 450, c.cy), "hero", true)
				c.r = creep("melee", R, at(o, 1500, 90), "own")
			else
				c.h = hero("npc_dota_hero_axe", R, V(c.cx + 135, c.cy), "hero", true)
				c.r = creep("melee", R, V(c.cx - 200, c.cy), "own")
			end
			still(c.r)
			c.step = 0
			watch(c, c.cr, { c.h, c.r })
		end,
		tick = function(c, t)
			watchTick(c, t)
			if c.step == 0 and t > 0.3 and kind == "melee" then
				c.step = 0.5
				c.r:SetAbsOrigin(GetGroundPosition(V(c.cx - 50, c.cy), c.r))
			end
			if c.step == 0 and t > 1 and kind == "ranged" then
				-- Brought in after the attacker is on the hero (at spawn it takes our creep, round 2a).
				c.step = 0.5
				c.r:SetAbsOrigin(GetGroundPosition(at(c.cr:GetAbsOrigin(), 150, 90), c.r))
			end
			if c.step < 1 and t > 2.5 then
				c.step = 1
				say(string.format("%s %s rel=%.2f on=%s hero_d=%s/%s own_d=%s/%s", c.tag, withOrder and "order" or "no_order", t, L(c.cr:GetAttackTarget()),
					f0(d2(c.cr, c.h)), f0(edge(c.cr, c.h)), f0(d2(c.cr, c.r)), f0(edge(c.cr, c.r))))
				if withOrder then attackOrder(c.h, c.r) end
			end
		end,
	}
end
S.order3 = {}
for rep = 1, 3 do
	table.insert(S.order3, order3Trial("ranged", true, rep))
	table.insert(S.order3, order3Trial("ranged", false, rep))
end
for rep = 1, 2 do
	table.insert(S.order3, order3Trial("melee", true, rep))
	table.insert(S.order3, order3Trial("melee", false, rep))
end

-- fog: a melee creep hitting a standing hero; the hero is moved away along the line (a blink) and stands: does the creep
-- come, with and without Dire vision of the new spot.
local function fogTrial(dist, viewer, rep)
	return {
		tag = string.format("fog_%d_%s_%d", dist, viewer and "viewer" or "none", rep),
		timeout = 10,
		setup = function(c)
			c.cx, c.cy = X0, Y
			c.cr = creep("melee", D, V(X0, Y), "melee")
			tank(c.cr)
			c.h = hero("npc_dota_hero_axe", R, V(X0 + 90, Y), "hero")
			c.home = c.cr:GetAbsOrigin()
			watch(c, c.cr, { c.h })
			c.go, c.lastLog = false, 0
		end,
		tick = function(c, t)
			watchTick(c, t)
			if not c.go and t > 1.5 then
				c.go = true
				local p = V(X0 + dist, Y)
				if viewer then AddFOWViewer(D, p, 300, 9, false) end
				c.h:SetAbsOrigin(GetGroundPosition(p, c.h))
				say(string.format("%s blink rel=%.2f on=%s", c.tag, t, L(c.cr:GetAttackTarget())))
			end
			if c.go and t - c.lastLog >= 0.5 then
				c.lastLog = t
				say(string.format("%s gap rel=%.2f gap=%s from_home=%s vis=%s attack=%s", c.tag, t, f0(d2(c.cr, c.h)),
					f0((c.cr:GetAbsOrigin() - c.home):Length2D()), visible(c.h), L(c.cr:GetAttackTarget())))
			end
		end,
	}
end
S.fog = {}
for rep = 1, 2 do
	table.insert(S.fog, fogTrial(900, false, rep))
	table.insert(S.fog, fogTrial(900, true, rep))
end
table.insert(S.fog, fogTrial(600, false, 1))
table.insert(S.fog, fogTrial(1300, false, 1))

-- ramp: a creep chasing a hero who walks up the ramp north-east of the main site (128 to 256) and stands at the top.
local RAMP0, RAMP1 = V(-5848, -2136), V(-4858, -1146)
local function rampTrial(speed, rep)
	return {
		tag = string.format("ramp_ms%d_%d", speed, rep),
		timeout = 18,
		setup = function(c)
			c.cx, c.cy = RAMP0.x, RAMP0.y
			c.cr = creep("melee", D, RAMP0 - Vector(64, 64, 0), "melee")
			tank(c.cr)
			c.h = hero("npc_dota_hero_axe", R, RAMP0 + Vector(30, 30, 0), "hero")
			pcall(function() c.h:SetBaseMoveSpeed(speed) end)
			watch(c, c.cr, { c.h })
			c.go, c.lastLog = false, 0
		end,
		tick = function(c, t)
			watchTick(c, t)
			if not c.go and t > 1.5 then
				c.go = true
				moveOrder(c.h, RAMP1)
				say(string.format("%s go rel=%.2f on=%s", c.tag, t, L(c.cr:GetAttackTarget())))
			end
			if c.go and t - c.lastLog >= 0.5 then
				c.lastLog = t
				local p, q = c.cr:GetAbsOrigin(), c.h:GetAbsOrigin()
				say(string.format("%s gap rel=%.2f gap=%s z_creep=%.0f z_hero=%.0f vis=%s attack=%s", c.tag, t, f0(d2(c.cr, c.h)), p.z, q.z,
					visible(c.h), L(c.cr:GetAttackTarget())))
			end
		end,
	}
end
S.ramp = {}
for rep = 1, 2 do
	table.insert(S.ramp, rampTrial(310, rep))
	table.insert(S.ramp, rampTrial(450, rep))
end

-- height2: hits over a fixed time. vision "none" | "viewer" | "ward" (a Dire observer ward unit beside the target); the
-- shooter a ranged creep or a Dire sniper (given the attack order).
local function height2Trial(tag, sx, sy, tx, ty, vision, shooterHero, secs)
	return {
		tag = tag,
		timeout = secs + 3,
		setup = function(c)
			c.cx, c.cy = sx, sy
			if shooterHero then
				c.s = hero("npc_dota_hero_sniper", D, V(sx, sy), "shooter", true)
			else
				c.s = creep("ranged", D, V(sx, sy), "shooter")
				tank(c.s)
			end
			pcall(function() c.s:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			c.u = creep("melee", R, V(tx, ty), "target")
			tank(c.u, 100000)
			passive(c.u)
			pcall(function() c.u:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			pcall(function() c.u:SetBaseHealthRegen(0) end)
			if vision == "viewer" then AddFOWViewer(D, V(tx, ty), 300, secs + 2, false) end
			if vision == "ward" then c.ward = make("npc_dota_observer_wards", V(tx + 120, ty), D, "ward") end
			c.hits, c.first, c.lastOrder = 0, nil, -1
			c.hp = c.u:GetHealth()
		end,
		tick = function(c, t)
			if t > 0.5 and not c.logged then
				c.logged = true
				say(string.format("%s setup z_shooter=%.0f z_target=%.0f dist=%s vis_dire=%s ward=%s", tag, c.s:GetAbsOrigin().z, c.u:GetAbsOrigin().z,
					f0(d2(c.s, c.u)), tostring(c.u:CanBeSeenByAnyOpposingTeam()), tostring(c.ward ~= nil)))
			end
			if shooterHero and t - c.lastOrder > 1 then
				c.lastOrder = t
				if c.s:GetAttackTarget() ~= c.u then attackOrder(c.s, c.u) end
			end
			local hp = c.u:GetHealth()
			if hp < c.hp then
				c.hits = c.hits + 1
				c.first = c.first or t
			end
			c.hp = hp
			if t >= secs then
				local from = c.first or secs
				local spa = c.s:GetSecondsPerAttack(false)
				say(string.format("%s result hits=%d first_hit=%.2f span=%.2f spa=%.3f expected=%.1f", tag, c.hits, from, secs - from, spa,
					(secs - from) / spa + 1))
				return true
			end
		end,
	}
end
S.height2 = {
	height2Trial("h2_up_ward", -2750, -250, -3170, -250, "ward", false, 45),
	height2Trial("h2_up_hero", -2750, -250, -3170, -250, "viewer", true, 45),
	height2Trial("h2_flat_hero", -3600, -250, -4020, -250, "none", true, 45),
	height2Trial("h2_river_up", -1300, 1150, -900, 1250, "viewer", false, 45),
}

-- towerpref: a Dire creep and a Dire hero put in the T2's reach on the same tick, at set distances from its centre.
local function towerPrefTrial(hd, cd, rep)
	return {
		tag = string.format("towerpref_h%d_c%d_%d", hd, cd, rep),
		timeout = 4,
		setup = function(c)
			c.tw = tower2()
			local o = c.tw:GetAbsOrigin()
			c.cx, c.cy = o.x, o.y
			local ha, ca = rep == 1 and -40 or -80, rep == 1 and -80 or -40
			c.h = hero("npc_dota_hero_sniper", D, at(o, hd, ha), "dhero")
			c.cr = creep("melee", D, at(o, cd, ca), "dcreep")
			still(c.cr)
			pcall(function() c.h:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
			towerWatch(c, c.tw, { c.h, c.cr })
		end,
		tick = function(c, t) watchTick(c, t) end,
	}
end
S.towerpref = {}
for rep = 1, 2 do
	table.insert(S.towerpref, towerPrefTrial(450, 600, rep))
	table.insert(S.towerpref, towerPrefTrial(600, 450, rep))
	table.insert(S.towerpref, towerPrefTrial(520, 520, rep))
end

-- turn: a unit faced east is ordered to walk west: its yaw every tick until it faces the goal, and when it first moves.
local function turnTrial(kind, rep)
	return {
		tag = string.format("turn_%s_%d", kind, rep),
		timeout = 5,
		setup = function(c)
			c.cx, c.cy = X0 + 700, Y
			if kind == "axe" or kind == "sniper" then
				c.u = hero("npc_dota_hero_" .. kind, R, V(c.cx, c.cy), kind)
			else
				c.u = creep(kind, R, V(c.cx, c.cy), kind)
				tank(c.u)
				passive(c.u)
			end
			c.u:SetForwardVector(Vector(1, 0, 0))
			c.trace, c.step = {}, 0
			local tr = {}
			for _, g in ipairs({ "GetTurnRate", "GetBaseTurnRate" }) do
				local ok, v = pcall(function() return c.u[g](c.u) end)
				table.insert(tr, g .. "=" .. tostring(ok and v or "x"))
			end
			say(c.tag .. " " .. table.concat(tr, " "))
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1 then
				c.step = 1
				c.tt0, c.p0 = t, c.u:GetAbsOrigin()
				moveOrder(c.u, V(c.cx - 1000, c.cy))
			elseif c.step == 1 then
				local y = yaw(c.u)
				table.insert(c.trace, string.format("%.2f:%.0f", t - c.tt0, y))
				if c.mv == nil and (c.u:GetAbsOrigin() - c.p0):Length2D() > 1 then c.mv = t - c.tt0 end
				if math.abs(angDiff(y, 180)) < 3 or t - c.tt0 > 3 then
					say(string.format("%s faced=%.2f first_move=%s trace=%s", c.tag, t - c.tt0, tostring(c.mv and string.format("%.2f", c.mv)),
						table.concat(c.trace, ",")))
					return true
				end
			end
		end,
	}
end
S.turn = {}
for rep = 1, 2 do
	for _, k in ipairs({ "axe", "sniper", "melee", "ranged" }) do table.insert(S.turn, turnTrial(k, rep)) end
end

-- swing: a creep hitting a standing hero; the hero walks off at its second landed hit ("hit") or 0.5 s after it ("mid"):
-- when the creep first moves, after that hit.
local function swingTrial(kind, when, rep)
	return {
		tag = string.format("swing_%s_%s_%d", kind, when, rep),
		timeout = 8,
		setup = function(c)
			c.cx, c.cy = X0 + 400, Y
			c.cr = creep(kind, D, V(c.cx, c.cy), kind)
			tank(c.cr)
			local start = kind == "ranged" and 450 or 90
			c.h = hero("npc_dota_hero_axe", R, V(c.cx + start, c.cy), "hero")
			pcall(function() c.h:SetBaseHealthRegen(0) end)
			pcall(function() c.h:SetBaseMoveSpeed(450) end)
			c.hp, c.hits, c.step = c.h:GetHealth(), 0, 0
			watch(c, c.cr, { c.h })
		end,
		tick = function(c, t)
			watchTick(c, t)
			local hp = c.h:GetHealth()
			if hp < c.hp then
				c.hits = c.hits + 1
				say(string.format("%s hit rel=%.2f n=%d", c.tag, t, c.hits))
				if c.hits == 2 and c.step == 0 then
					c.step = 1
					c.thit = t
					c.leaveAt = when == "hit" and t or t + 0.5
				end
			end
			c.hp = hp
			if c.step == 1 and t >= c.leaveAt then
				c.step = 2
				c.p0 = c.cr:GetAbsOrigin()
				moveOrder(c.h, V(c.cx + 2000, c.cy))
				say(string.format("%s leave rel=%.2f after_hit=%.2f", c.tag, t, t - c.thit))
			elseif c.step == 2 and (c.cr:GetAbsOrigin() - c.p0):Length2D() > 1 then
				c.step = 3
				say(string.format("%s creep_moves rel=%.2f after_hit=%.2f after_leave=%.2f", c.tag, t, t - c.thit, t - c.leaveAt))
				return true
			end
		end,
	}
end
S.swing = {}
for rep = 1, 2 do
	for _, k in ipairs({ "melee", "ranged" }) do
		table.insert(S.swing, swingTrial(k, "hit", rep))
		table.insert(S.swing, swingTrial(k, "mid", rep))
	end
end

-- real: a creep of the real Dire waves moved to the main site: the chase and the re-pick on it.
local function grabReal()
	for _, u in ipairs(Entities:FindAllByClassname("npc_dota_creep_lane")) do
		if u:IsAlive() and u:GetTeamNumber() == D and label[u:entindex()] == nil and string.find(u:GetUnitName(), "melee") then
			return u
		end
	end
end
local function realTrial(kind, rep)
	return {
		tag = string.format("real_%s_%d", kind, rep),
		timeout = 16,
		setup = function(c)
			c.cx, c.cy = X0, Y
			c.cr = grabReal()
			if c.cr == nil then error("no real Dire melee creep") end
			label[c.cr:entindex()] = "real"
			table.insert(made, c.cr)
			say(string.format("%s grabbed %s from %s,%s acq=%.0f", c.tag, c.cr:GetUnitName(), f0(c.cr:GetAbsOrigin().x),
				f0(c.cr:GetAbsOrigin().y), c.cr:GetAcquisitionRange()))
			order(c.cr, DOTA_UNIT_ORDER_STOP)
			c.cr:SetAbsOrigin(GetGroundPosition(V(X0, Y), c.cr))
			tank(c.cr)
			c.h = hero("npc_dota_hero_axe", R, V(X0 + 90, Y), "hero")
			local others = { c.h }
			if kind == "repick" then
				c.r = creep("melee", R, V(X0 + 60, Y + 170), "own")
				still(c.r)
				table.insert(others, c.r)
			end
			c.home = V(X0, Y)
			watch(c, c.cr, others)
			c.go, c.lastLog = false, 0
		end,
		tick = function(c, t)
			watchTick(c, t)
			if not c.go and t > 2 then
				c.go = true
				moveOrder(c.h, V(-4300, Y))
				say(string.format("%s go rel=%.2f on=%s", c.tag, t, L(c.cr:GetAttackTarget())))
			end
			if t > 0.5 and not c.where then
				c.where = true
				local p = c.cr:GetAbsOrigin()
				say(string.format("%s at %s,%s on=%s", c.tag, f0(p.x), f0(p.y), L(c.cr:GetAttackTarget())))
			end
			if c.go and kind == "chase" and t - c.lastLog >= 0.5 then
				c.lastLog = t
				say(string.format("%s gap rel=%.2f gap=%s from_home=%s attack=%s", c.tag, t, f0(d2(c.cr, c.h)),
					f0((c.cr:GetAbsOrigin() - c.home):Length2D()), L(c.cr:GetAttackTarget())))
			end
			if kind == "repick" and c.go and t > 6 then return true end
		end,
	}
end
S.real = {}
for rep = 1, 2 do
	table.insert(S.real, realTrial("chase", rep))
	table.insert(S.real, realTrial("repick", rep))
end

-- fogwalk: as fog at 900, then the hero walks 500 north in the fog: does the creep go to where it is or where it was seen.
local function fogWalkTrial(viewer, rep)
	return {
		tag = string.format("fogwalk_%s_%d", viewer and "viewer" or "none", rep),
		timeout = 12,
		setup = function(c)
			c.cx, c.cy = X0, Y
			c.cr = creep("melee", D, V(X0, Y), "melee")
			tank(c.cr)
			c.h = hero("npc_dota_hero_axe", R, V(X0 + 90, Y), "hero")
			watch(c, c.cr, { c.h })
			c.go, c.lastLog = false, 0
		end,
		tick = function(c, t)
			watchTick(c, t)
			if not c.go and t > 1.5 then
				c.go = true
				local p = V(X0 + 900, Y)
				c.h:SetAbsOrigin(GetGroundPosition(p, c.h))
				c.tblink = t
				say(string.format("%s blink rel=%.2f on=%s", c.tag, t, L(c.cr:GetAttackTarget())))
			end
			if c.go and not c.walked and t - c.tblink > 0.1 then
				c.walked = true
				moveOrder(c.h, V(X0 + 900, Y + 500))
			end
			if viewer and c.go and t - (c.lastView or -9) > 0.25 then
				c.lastView = t
				AddFOWViewer(D, c.h:GetAbsOrigin(), 200, 0.4, false)
			end
			if c.go and t - c.lastLog >= 0.5 then
				c.lastLog = t
				local p, q = c.cr:GetAbsOrigin(), c.h:GetAbsOrigin()
				say(string.format("%s gap rel=%.2f gap=%s creep=%s,%s hero=%s,%s vis=%s attack=%s", c.tag, t, f0(d2(c.cr, c.h)), f0(p.x - X0), f0(p.y - Y),
					f0(q.x - X0), f0(q.y - Y), visible(c.h), L(c.cr:GetAttackTarget())))
			end
		end,
	}
end
S.fogwalk = {}
for rep = 1, 3 do
	table.insert(S.fogwalk, fogWalkTrial(false, rep))
	if rep < 3 then table.insert(S.fogwalk, fogWalkTrial(true, rep)) end
end

-- ramp2: more ramp reps (round 2a gave up in 2 of 4).
S.ramp2 = {}
for rep = 3, 5 do
	table.insert(S.ramp2, rampTrial(310, rep))
	table.insert(S.ramp2, rampTrial(450, rep))
end

-- towerpref2: the ties that separate nearest by centre from nearest by edge (hero hull 24, creep 16).
S.towerpref2 = {}
for rep = 1, 2 do
	table.insert(S.towerpref2, towerPrefTrial(526, 520, rep)) -- hero farther by centre, nearer by edge (358 against 360)
	table.insert(S.towerpref2, towerPrefTrial(540, 520, rep)) -- creep nearer both ways
end

-- Protective aggro (round 3): the hero's attack order on an enemy hero draws enemy creeps near the hero. The aggressor is
-- a Radiant axe that can attack (idle acquire off), its target a passive Dire sniper away from the creeps; the Dire creeps
-- fight a passive Radiant bait creep first, so "drawn" is a fighting creep switching to the hero.
local function holdOrder(u) order(u, DOTA_UNIT_ORDER_HOLD_POSITION) end
local function grabKind(kind)
	for _, u in ipairs(Entities:FindAllByClassname("npc_dota_creep_lane")) do
		if u:IsAlive() and u:GetTeamNumber() == D and label[u:entindex()] == nil and string.find(u:GetUnitName(), kind) then
			return u
		end
	end
end
-- A Dire creep at pos: made, or a real wave creep moved there (`real`).
local function direCreep(kind, real, pos, lab)
	if not real then
		local u = creep(kind, D, pos, lab)
		if u then tank(u) end
		return u
	end
	local u = grabKind(kind)
	if u == nil then error("no real Dire " .. kind .. " creep") end
	label[u:entindex()] = lab
	table.insert(made, u)
	say(string.format("grabbed %s %s from %s,%s", lab, u:GetUnitName(), f0(u:GetAbsOrigin().x), f0(u:GetAbsOrigin().y)))
	order(u, DOTA_UNIT_ORDER_STOP)
	u:SetAbsOrigin(GetGroundPosition(pos, u))
	tank(u)
	return u
end
local function bait(pos, lab)
	local b = creep("melee", R, pos, lab)
	tank(b, 100000)
	passive(b)
	pcall(function() b:SetMoveCapability(DOTA_UNIT_CAP_MOVE_NONE) end)
	return b
end
local function on(u, h)
	local a = nil
	pcall(function() a = u:GetAggroTarget() end)
	return u:GetAttackTarget() == h or a == h
end
-- The draw: logs each creep's distance at the order and whether (and how soon) it took the hero.
local function drawCheck(c, t)
	for _, cr in ipairs(c.crs) do
		local k = cr:entindex()
		if c.drawn[k] == nil and on(cr, c.h) then
			c.drawn[k] = t - c.tord
			say(string.format("%s drawn %s after=%.2f", c.tag, L(cr), t - c.tord))
		end
	end
end
local function drawOrder(c, t)
	c.tord = t
	c.drawn = {}
	for _, cr in ipairs(c.crs) do
		say(string.format("%s order %s centre=%s edge=%s on=%s acq=%.0f", c.tag, L(cr), f0(d2(cr, c.h)), f0(edge(cr, c.h)), L(cr:GetAttackTarget()),
			cr:GetAcquisitionRange()))
	end
	say(string.format("%s order_tgt d=%s seen_by_radiant=%s", c.tag, f0(d2(c.h, c.tg)), tostring(c.tg:CanBeSeenByAnyOpposingTeam())))
	attackOrder(c.h, c.tg)
end
-- The hero's own state after the order (round 3b): where it is, what it attacks, whether it is attacking.
local function heroState(c, t)
	c.hs = c.hs or {}
	for _, at in ipairs({ 0.05, 0.3, 0.7, 1.2 }) do
		if c.hs[at] == nil and t - c.tord >= at then
			c.hs[at] = true
			local att = false
			pcall(function() att = c.h:IsAttacking() end)
			say(string.format("%s hero rel=%.2f moved=%s attack=%s attacking=%s tgt_d=%s", c.tag, t - c.tord, f0((c.h:GetAbsOrigin() - c.hpos):Length2D()),
				L(c.h:GetAttackTarget()), tostring(att), f0(d2(c.h, c.tg))))
		end
	end
end

-- draw: one Dire creep fighting the bait, the hero at a set centre distance west of it: drawn or not.
local function drawTrial(kind, d, rep)
	return {
		tag = string.format("draw_%s_%d_%d", kind, d, rep),
		timeout = 6,
		setup = function(c)
			c.cx, c.cy = -4400, Y
			local P = V(-4400, Y)
			c.b = bait(P + Vector(kind == "ranged" and 300 or 60, 0, 0), "bait")
			c.cr = direCreep(kind, false, P, kind)
			c.crs = { c.cr }
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, V(-4400 - d, Y), "hero", true)
				c.tg = hero("npc_dota_hero_sniper", D, V(-5700, Y), "dtgt")
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				if t - c.tord > 0.1 and not c.held then
					c.held = true
					holdOrder(c.h)
				end
				drawCheck(c, t)
				if t - c.tord > 1.5 then
					say(string.format("%s result %s drawn=%d on=%s", c.tag, kind, c.drawn[c.cr:entindex()] and 1 or 0, L(c.cr:GetAttackTarget())))
					return true
				end
			end
		end,
	}
end
-- why (round 3b): one melee creep fighting the bait, the hero `cd` (centre) west of it, the target hero `tgd` farther
-- west on the flat; 0.1 s after the order a hold, a move away, or nothing.
local function whyTrial(kind, cd, tgd, after, rep)
	return {
		tag = string.format("why_%s_c%d_t%d_%s_%d", kind, cd, tgd, after, rep),
		timeout = 6,
		setup = function(c)
			c.cx, c.cy = -4400, Y
			local P = V(-4400, Y)
			c.b = bait(P + Vector(kind == "ranged" and 300 or 60, 0, 0), "bait")
			c.cr = direCreep(kind, false, P, kind)
			c.crs = { c.cr }
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.hpos = V(-4400 - cd, Y)
				c.h = hero("npc_dota_hero_axe", R, c.hpos, "hero", true)
				c.hpos = c.h:GetAbsOrigin()
				c.tg = hero("npc_dota_hero_sniper", D, V(-4400 - cd - tgd, Y), "dtgt")
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				if t - c.tord > 0.1 and not c.held then
					c.held = true
					if after == "hold" then holdOrder(c.h) elseif after == "move" then moveOrder(c.h, V(-4400 - cd, Y - 400)) end
				end
				heroState(c, t)
				drawCheck(c, t)
				if t - c.tord > 1.5 then
					say(string.format("%s result drawn=%d on=%s", c.tag, c.drawn[c.cr:entindex()] and 1 or 0, L(c.cr:GetAttackTarget())))
					return true
				end
			end
		end,
	}
end
S.why = {}
for rep = 1, 2 do
	for _, tgd in ipairs({ 300, 600, 900, 1200 }) do
		for _, after in ipairs({ "hold", "move", "none" }) do table.insert(S.why, whyTrial("melee", 300, tgd, after, rep)) end
	end
end
-- radius (round 3b): the restrict condition (target 300 beyond the hero, hold), creep distance varied.
S.radius = {}
for rep = 1, 2 do
	for _, kind in ipairs({ "melee", "ranged" }) do
		for _, cd in ipairs({ 350, 400, 450, 500 }) do table.insert(S.radius, whyTrial(kind, cd, 300, "hold", rep)) end
	end
end
S.draw = {}
for rep = 1, 2 do
	for _, kind in ipairs({ "melee", "ranged" }) do
		for _, d in ipairs({ 460, 490, 510, 530, 560, 600 }) do table.insert(S.draw, drawTrial(kind, d, rep)) end
	end
end

-- A wave fighting two baits at P: two melee creeps and a ranged one. Returns the creeps.
local function wave(c, P, real)
	c.b1 = bait(P + Vector(60, 40, 0), "bait1")
	c.b2 = bait(P + Vector(60, -40, 0), "bait2")
	local m1 = direCreep("melee", real, P + Vector(0, 40, 0), "m1")
	local m2 = direCreep("melee", real, P + Vector(0, -40, 0), "m2")
	local r = direCreep("ranged", real, P + Vector(120, 0, 0), "r")
	return { m1, m2, r }
end
local function gaps(c, t)
	if t - (c.lastLog or -9) < 0.5 then return end
	c.lastLog = t
	local parts = {}
	for _, cr in ipairs(c.crs) do
		if not cr:IsNull() and cr:IsAlive() then
			table.insert(parts, string.format("%s=%s:%s", L(cr), f0(d2(cr, c.h)), L(cr:GetAttackTarget())))
		end
	end
	say(string.format("%s gap rel=%.2f %s vis=%s z=%.0f hp=%d", c.tag, t, table.concat(parts, " "), visible(c.h), c.h:GetAbsOrigin().z, c.h:GetHealth()))
end
local function watchAll(c, extra)
	for _, cr in ipairs(c.crs) do
		local others = { c.h }
		for _, e in ipairs(extra or {}) do table.insert(others, e) end
		watch(c, cr, others)
	end
end

-- chase: after the draw the hero stands (hold) or walks west at 300 or 350: how long each creep stays on the hero.
local function chaseTrial(mode, rep, o)
	o = o or {}
	return {
		tag = string.format("chase%s_%s_%d", o.sfx or "", mode, rep),
		timeout = 14,
		setup = function(c)
			c.cx, c.cy = -4400, Y
			c.crs = wave(c, V(-4400, Y), false)
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, V(-4700, Y), "hero", true)
				if mode ~= "stand" then pcall(function() c.h:SetBaseMoveSpeed(mode == "walk300" and 300 or 350) end) end
				c.tg = hero("npc_dota_hero_sniper", D, o.tg or V(-4400, Y + 700), "dtgt")
				watchAll(c, { c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > (o.at or 0.1) and not c.moved then
					c.moved = true
					if mode == "stand" then holdOrder(c.h) else moveOrder(c.h, V(-6300, Y)) end
				end
				if t - c.tord > 10 then return true end
			end
		end,
	}
end
S.chase = {}
for rep = 1, 2 do
	for _, mode in ipairs({ "stand", "walk300", "walk350" }) do table.insert(S.chase, chaseTrial(mode, rep)) end
end

-- reshow: the draw at the ramp's foot, the hero walks up to the high ground at 400; again the attack order on the hero
-- (none; `first`: at the first tick the hero is unseen; `late`: at the first unseen tick from 3.1 s after the order).
local function reshowTrial(mode, rep, o)
	o = o or {}
	return {
		tag = string.format("reshow%s_%s_%d", o.sfx or "", mode, rep),
		timeout = 16,
		setup = function(c)
			c.cx, c.cy = RAMP0.x, RAMP0.y
			c.crs = wave(c, V(-5550, Y), false)
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, RAMP0, "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(400) end)
				c.tg = hero("npc_dota_hero_sniper", D, o.tg or V(-4400, Y), "dtgt")
				watchAll(c, { c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > (o.at or 0.1) and not c.moved then
					c.moved = true
					moveOrder(c.h, RAMP1)
				end
				local unseen = not c.h:CanBeSeenByAnyOpposingTeam()
				if unseen and c.fog == nil then
					c.fog = t
					say(string.format("%s unseen rel=%.2f after_order=%.2f z=%.0f", c.tag, t, t - c.tord, c.h:GetAbsOrigin().z))
				end
				if not unseen and c.fog ~= nil and c.seenAgain == nil then
					c.seenAgain = t
					say(string.format("%s seen_again rel=%.2f", c.tag, t))
				end
				local due = mode == "first" and unseen or (mode == "late" and unseen and t - c.tord >= 3.1)
				if due and not c.reordered then
					c.reordered = true
					say(string.format("%s reorder rel=%.2f after_order=%.2f", c.tag, t, t - c.tord))
					attackOrder(c.h, c.tg)
					c.remove = t
				end
				if c.remove and t - c.remove > 0.1 then
					c.remove = nil
					moveOrder(c.h, RAMP1)
				end
				if t - c.tord > 12 then return true end
			end
		end,
	}
end
S.reshow = {}
for rep = 1, 2 do
	for _, mode in ipairs({ "none", "first", "late" }) do table.insert(S.reshow, reshowTrial(mode, rep)) end
end

-- release: our ranged creep (able to attack, so it fights) 500 behind the wave; the hero draws from 300 and walks to 250
-- behind our creep: straight through it with no order (`walk`), the same then the attack order on our creep once every
-- drawn creep is nearer it by edge than the hero (`through`), or round it 220 to the side and the same order (`side`).
-- Made or real wave creeps.
local function releaseTrial(real, mode, rep, o)
	o = o or {}
	return {
		tag = string.format("release%s_%s_%s_%d", o.sfx or "", real and "real" or "made", mode, rep),
		timeout = 16,
		setup = function(c)
			c.cx, c.cy = -4400, Y
			c.crs = wave(c, V(-4400, Y), real)
			c.own = creep("ranged", R, V(-4900, Y), "own")
			tank(c.own)
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, V(-4700, Y), "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(310) end)
				c.tg = hero("npc_dota_hero_sniper", D, o.tg or V(-4400, Y + 700), "dtgt")
				watchAll(c, { c.own, c.b1 })
				c.hp0 = c.h:GetHealth()
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > (o.at or 0.1) and not c.moved then
					c.moved = true
					if mode == "side" then
						order(c.h, DOTA_UNIT_ORDER_MOVE_TO_POSITION, nil, V(-4900, Y + 220))
						ExecuteOrderFromTable({ UnitIndex = c.h:entindex(), OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION, Position = V(-5150, Y + 220), Queue = true })
					else
						moveOrder(c.h, V(-5150, Y))
					end
				end
				if mode ~= "walk" and c.moved and not c.released then
					local n, ready = 0, true
					for _, cr in ipairs(c.crs) do
						if on(cr, c.h) then
							n = n + 1
							if edge(cr, c.own) >= edge(cr, c.h) - 30 then ready = false end
						end
					end
					if n > 0 and ready then
						c.released = t
						say(string.format("%s release rel=%.2f after_order=%.2f n=%d", c.tag, t, t - c.tord, n))
						attackOrder(c.h, c.own)
					end
				end
				if c.released and not c.stopped and t - c.released > 0.1 then
					c.stopped = true
					holdOrder(c.h)
				end
				if t - c.tord > 10 then
					local parts = {}
					for _, cr in ipairs(c.crs) do table.insert(parts, L(cr) .. "=" .. L(cr:GetAttackTarget())) end
					say(string.format("%s final %s hp_lost=%d", c.tag, table.concat(parts, " "), c.hp0 - c.h:GetHealth()))
					return true
				end
			end
		end,
	}
end
S.release = {}
for rep = 1, 2 do
	for _, real in ipairs({ false, true }) do
		for _, mode in ipairs({ "walk", "through", "side" }) do table.insert(S.release, releaseTrial(real, mode, rep)) end
	end
end

-- Round 3b: chase, reshow and release again with the target hero 300 from ours on the flat and in sight, and the walk
-- ordered 0.8 s after the attack order (round 3 put the target out of sight or 1,450 away and walked at 0.1 s: none drawn).
S.chase2, S.reshow2, S.release2 = {}, {}, {}
for rep = 1, 2 do
	for _, mode in ipairs({ "stand", "walk300", "walk350" }) do table.insert(S.chase2, chaseTrial(mode, rep, { sfx = "2", tg = V(-4700, Y - 300), at = 0.8 })) end
	for _, mode in ipairs({ "none", "first", "late" }) do table.insert(S.reshow2, reshowTrial(mode, rep, { sfx = "2", tg = V(-6148, -2136), at = 0.8 })) end
	for _, mode in ipairs({ "walk", "through", "side" }) do table.insert(S.release2, releaseTrial(false, mode, rep, { sfx = "2", tg = V(-4700, Y - 300), at = 0.8 })) end
end

-- Round 3c.
-- reshow3: a wave fighting at the foot of the ramp line (0.2 of RAMP0 to RAMP1), the hero 280 up it at 0.4 (the slope
-- starts at 0.45, 256 from 0.6); the walk up at 300 from 0.8 s, so it leaves sight inside the draw's 2.3 s. Then no second
-- order, one at the first unseen tick (inside the 3 s cooldown), one at the first unseen tick from 3.1 s, or Dire vision
-- kept on the hero (`viewer`, the control: sight alone differs).
local function rampAt(f) return RAMP0 + (RAMP1 - RAMP0) * f end
local function reshow3Trial(mode, rep)
	return {
		tag = string.format("reshow3_%s_%d", mode, rep),
		timeout = 16,
		setup = function(c)
			c.cx, c.cy = RAMP0.x, RAMP0.y
			c.crs = wave(c, rampAt(0.2), false)
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, rampAt(0.4), "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(300) end)
				c.tg = hero("npc_dota_hero_sniper", D, RAMP0, "dtgt")
				watchAll(c, { c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > 0.8 and not c.moved then
					c.moved = true
					moveOrder(c.h, RAMP1)
				end
				if mode == "viewer" and c.moved and t - (c.lastView or -9) > 0.25 then
					c.lastView = t
					AddFOWViewer(D, c.h:GetAbsOrigin(), 200, 0.4, false)
				end
				local unseen = not c.h:CanBeSeenByAnyOpposingTeam()
				if unseen and c.fog == nil then
					c.fog = t
					say(string.format("%s unseen rel=%.2f after_order=%.2f z=%.0f", c.tag, t, t - c.tord, c.h:GetAbsOrigin().z))
				end
				if not unseen and c.fog ~= nil and c.seenAgain == nil then
					c.seenAgain = t
					say(string.format("%s seen_again rel=%.2f", c.tag, t))
				end
				local due = (mode == "first" and unseen) or (mode == "late" and unseen and t - c.tord >= 3.1)
				if due and not c.reordered then
					c.reordered = true
					local near = {}
					for _, cr in ipairs(c.crs) do table.insert(near, L(cr) .. "=" .. f0(d2(cr, c.h))) end
					say(string.format("%s reorder rel=%.2f after_order=%.2f %s", c.tag, t, t - c.tord, table.concat(near, " ")))
					attackOrder(c.h, c.tg)
					c.remove = t
				end
				if c.remove and t - c.remove > 0.1 then
					c.remove = nil
					moveOrder(c.h, RAMP1)
				end
				if t - c.tord > 10 then return true end
			end
		end,
	}
end
S.reshow3 = {}
for rep = 1, 2 do
	for _, mode in ipairs({ "none", "first", "late", "viewer" }) do table.insert(S.reshow3, reshow3Trial(mode, rep)) end
end

-- release3: the order on our creep after the draw's window (2.6 s), where the walk back did not put our creep nearer:
-- the hero stops level with our creep 150 to its side (`level`) or 100 in front of it (`front`); with the order or none.
local function release3Trial(stop, withOrder, rep)
	return {
		tag = string.format("release3_%s_%s_%d", stop, withOrder and "order" or "none", rep),
		timeout = 15,
		setup = function(c)
			c.cx, c.cy = -4400, Y
			c.crs = wave(c, V(-4400, Y), false)
			c.own = creep("ranged", R, V(-4900, Y), "own")
			tank(c.own)
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, V(-4700, Y), "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(310) end)
				c.tg = hero("npc_dota_hero_sniper", D, V(-4700, Y - 300), "dtgt")
				watchAll(c, { c.own, c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > 0.8 and not c.moved then
					c.moved = true
					moveOrder(c.h, stop == "level" and V(-4900, Y + 150) or V(-4800, Y + 60))
				end
				if withOrder and not c.released and t - c.tord >= 2.6 then
					c.released = t
					local parts = {}
					for _, cr in ipairs(c.crs) do
						table.insert(parts, string.format("%s=%s:%s/%s", L(cr), L(cr:GetAttackTarget()), f0(edge(cr, c.h)), f0(edge(cr, c.own))))
					end
					say(string.format("%s release rel=%.2f after_order=%.2f %s", c.tag, t, t - c.tord, table.concat(parts, " ")))
					attackOrder(c.h, c.own)
				end
				if c.released and not c.stopped and t - c.released > 0.1 then
					c.stopped = true
					holdOrder(c.h)
				end
				if t - c.tord > 8 then
					local parts = {}
					for _, cr in ipairs(c.crs) do table.insert(parts, L(cr) .. "=" .. L(cr:GetAttackTarget())) end
					say(string.format("%s final %s", c.tag, table.concat(parts, " ")))
					return true
				end
			end
		end,
	}
end
S.release3 = {}
for rep = 1, 2 do
	for _, stop in ipairs({ "level", "front" }) do
		for _, w in ipairs({ true, false }) do table.insert(S.release3, release3Trial(stop, w, rep)) end
	end
end

-- Round 3d (the user's ways up a ramp, 27/11/2026). reshow4: as reshow3, the hero walks up at 300 (`none`, the control),
-- at 200 or 150 (`slow200`, `slow150`), or at 300 stopping at 0.5 of the ramp line (just before it leaves sight) to land
-- one hit on the nearest creep on it, then on up (`hitmid`), or at the first unseen tick turning to land one hit on the
-- nearest Dire creep, then on up (`hitlost`). The wave's regen is 0 so a landed hit shows in its HP.
local RAMPLEN = (RAMP1 - RAMP0):Length2D()
local function rampFrac(u)
	local d = u:GetAbsOrigin() - RAMP0
	return (d.x * (RAMP1.x - RAMP0.x) + d.y * (RAMP1.y - RAMP0.y)) / (RAMPLEN * RAMPLEN)
end
local function nearestOf(c, onHero)
	local best, bd
	for _, cr in ipairs(c.crs) do
		if cr:IsAlive() and (not onHero or on(cr, c.h)) then
			local d = d2(cr, c.h)
			if bd == nil or d < bd then best, bd = cr, d end
		end
	end
	return best
end
local function reshow4Trial(mode, rep)
	local speed = mode == "slow200" and 200 or mode == "slow150" and 150 or 300
	return {
		tag = string.format("reshow4_%s_%d", mode, rep),
		timeout = 20,
		setup = function(c)
			c.cx, c.cy = RAMP0.x, RAMP0.y
			c.crs = wave(c, rampAt(0.2), false)
			for _, cr in ipairs(c.crs) do pcall(function() cr:SetBaseHealthRegen(0) end) end
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, rampAt(0.4), "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(speed) end)
				c.tg = hero("npc_dota_hero_sniper", D, RAMP0, "dtgt")
				watchAll(c, { c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > 0.8 and not c.moved then
					c.moved = true
					moveOrder(c.h, RAMP1)
				end
				local unseen = not c.h:CanBeSeenByAnyOpposingTeam()
				if unseen ~= c.lastUnseen then
					say(string.format("%s %s rel=%.2f after_order=%.2f z=%.0f frac=%.2f", c.tag, unseen and "unseen" or "seen", t, t - c.tord,
						c.h:GetAbsOrigin().z, rampFrac(c.h)))
					c.lastUnseen = unseen
				end
				local want = c.moved and not c.swing and ((mode == "hitmid" and rampFrac(c.h) >= 0.5) or (mode == "hitlost" and unseen))
				if want then
					local cr = nearestOf(c, mode == "hitmid")
					if cr then
						c.swing = { cr = cr, hp = cr:GetHealth(), t = t }
						say(string.format("%s swing rel=%.2f after_order=%.2f at=%s d=%s frac=%.2f", c.tag, t, t - c.tord, L(cr), f0(d2(cr, c.h)), rampFrac(c.h)))
						attackOrder(c.h, cr)
					end
				end
				local s = c.swing
				if s and not s.done and (s.cr:GetHealth() < s.hp or t - s.t > 2.5) then
					s.done = true
					say(string.format("%s %s rel=%.2f after_order=%.2f frac=%.2f", c.tag, s.cr:GetHealth() < s.hp and "landed" or "no_hit", t, t - c.tord, rampFrac(c.h)))
					moveOrder(c.h, RAMP1)
				end
				if t - c.tord > 14 then return true end
			end
		end,
	}
end
S.reshow4 = {}
for rep = 1, 2 do
	for _, mode in ipairs({ "none", "slow200", "slow150", "hitmid", "hitlost" }) do table.insert(S.reshow4, reshow4Trial(mode, rep)) end
end

-- down: the draw from their high ground down to ours. The wave fights at 0.75 of the ramp line (256), the hero 280 below
-- it at 0.55 walks down from 0.8 s: to 0.1 (`chase`), or to 0.12 with our ranged creep at 0.3 (`release`, 250 past it).
local function downTrial(mode, rep)
	return {
		tag = string.format("down_%s_%d", mode, rep),
		timeout = 15,
		setup = function(c)
			c.cx, c.cy = RAMP0.x, RAMP0.y
			c.crs = wave(c, rampAt(0.75), false)
			if mode == "release" then
				c.own = creep("ranged", R, rampAt(0.3), "own")
				tank(c.own)
			end
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, rampAt(0.55), "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(300) end)
				c.tg = hero("npc_dota_hero_sniper", D, RAMP0, "dtgt")
				watchAll(c, { c.own or c.b1, c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > 0.8 and not c.moved then
					c.moved = true
					moveOrder(c.h, rampAt(mode == "release" and 0.12 or 0.1))
				end
				local unseen = not c.h:CanBeSeenByAnyOpposingTeam()
				if unseen ~= c.lastUnseen then
					say(string.format("%s %s rel=%.2f after_order=%.2f z=%.0f", c.tag, unseen and "unseen" or "seen", t, t - c.tord, c.h:GetAbsOrigin().z))
					c.lastUnseen = unseen
				end
				if t - c.tord > 9 then
					local parts = {}
					for _, cr in ipairs(c.crs) do table.insert(parts, L(cr) .. "=" .. L(cr:GetAttackTarget())) end
					say(string.format("%s final %s", c.tag, table.concat(parts, " ")))
					return true
				end
			end
		end,
	}
end
S.down = {}
for rep = 1, 2 do
	for _, mode in ipairs({ "chase", "release" }) do table.insert(S.down, downTrial(mode, rep)) end
end

-- lanes: real waves where they meet. A Dire lane creep attacking a Radiant lane creep (at most one per 1,500, so one per
-- clash), our hero made 300 from it toward the Radiant fountain and a Dire target hero 300 beyond ours: drawn or not, with
-- the creep's distance to every tier-one tower. Real lane creeps are left alive (`keep`). Run before and after 5:00.
local T1S = { "npc_dota_goodguys_tower1_top", "npc_dota_goodguys_tower1_mid", "npc_dota_goodguys_tower1_bot",
	"npc_dota_badguys_tower1_top", "npc_dota_badguys_tower1_mid", "npc_dota_badguys_tower1_bot" }
local picked = {}
local function fighting(k)
	for _, u in ipairs(Entities:FindAllByClassname("npc_dota_creep_lane")) do
		local tg = u:IsAlive() and u:GetTeamNumber() == D and label[u:entindex()] == nil and u:GetAttackTarget() or nil
		if tg and not tg:IsNull() and tg:GetTeamNumber() == R and tg:GetClassname() == "npc_dota_creep_lane" then
			local far = true
			for j = 1, k - 1 do
				if picked[j] and (picked[j] - u:GetAbsOrigin()):Length2D() < 1500 then far = false end
			end
			if far then return u end
		end
	end
end
local function lanesTrial(k)
	return {
		tag = "lanes_" .. k,
		timeout = 5,
		setup = function(c)
			c.keep = true
			if k == 1 then picked = {} end
			c.cr = fighting(k)
			if c.cr == nil then error("no fighting Dire lane creep " .. k) end
			local p = c.cr:GetAbsOrigin()
			picked[k] = p
			c.cx, c.cy = p.x, p.y
			c.crs = { c.cr }
			local ds = {}
			for _, n in ipairs(T1S) do
				for _, tw in ipairs(Entities:FindAllByClassname("npc_dota_tower")) do
					if tw:GetUnitName() == n and tw:IsAlive() then table.insert(ds, n:gsub("npc_dota_", ""):gsub("guys_tower1", "") .. "=" .. f0((tw:GetAbsOrigin() - p):Length2D())) end
				end
			end
			say(string.format("%s creep %s at %s,%s on=%s %s", c.tag, c.cr:GetUnitName(), f0(p.x), f0(p.y), c.cr:GetAttackTarget():GetUnitName(), table.concat(ds, " ")))
			local dir = (V(-7000, -6500) - p):Normalized()
			c.hpos = p + dir * 300
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, c.hpos, "hero", true)
				local dir = (V(-7000, -6500) - c.cr:GetAbsOrigin()):Normalized()
				c.tg = hero("npc_dota_hero_sniper", D, c.hpos + dir * 300, "dtgt")
			elseif c.step == 1 and t > 0.3 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				if t - c.tord > 0.1 and not c.held then
					c.held = true
					holdOrder(c.h)
				end
				drawCheck(c, t)
				if not c.cr:IsAlive() then
					say(string.format("%s result died drawn=%d clock=%.0f", c.tag, c.drawn[c.cr:entindex()] and 1 or 0, now()))
					return true
				end
				if t - c.tord > 1.5 then
					say(string.format("%s result drawn=%d on=%s clock=%.0f", c.tag, c.drawn[c.cr:entindex()] and 1 or 0, L(c.cr:GetAttackTarget()), now()))
					return true
				end
			end
		end,
	}
end
S.lanes = { lanesTrial(1), lanesTrial(2), lanesTrial(3) }

-- clash (round 3e): before 5:00, a real Dire wave made to stop where we choose. A passive Radiant bait creep at the spot,
-- the real Radiant lane creeps within 2,500 of it killed so the Dire wave walks on to it; once a real Dire creep attacks the
-- bait, our hero is made 300 from it toward our fountain and draws (target 300 beyond, a hold). Spots by their distance to
-- the two tier ones: within 1,500 of theirs only, of ours only, of both, of neither (top lane).
local CLASH = {
	dT1 = V(0, 0), -- 1187 from the Dire mid T1, 1742 from ours
	rT1 = V(-300, -300), -- 1318 from our mid T1, 1611 from theirs
	both = V(-200, -200), -- 1459 and 1469
	none = V(-6300, 4600), -- 1765 from the Dire top T1, 2744 from ours
}
local function t1dists(p)
	local ds = {}
	for _, n in ipairs(T1S) do
		for _, tw in ipairs(Entities:FindAllByClassname("npc_dota_tower")) do
			if tw:GetUnitName() == n and tw:IsAlive() then table.insert(ds, n:gsub("npc_dota_", ""):gsub("guys_tower1", "") .. "=" .. f0((tw:GetAbsOrigin() - p):Length2D())) end
		end
	end
	return table.concat(ds, " ")
end
local function clashTrial(name, rep)
	local at = CLASH[name]
	return {
		tag = string.format("clash_%s_%d", name, rep),
		timeout = 50,
		setup = function(c)
			c.keep = true
			c.cx, c.cy = at.x, at.y
			c.b = bait(at, "bait")
			c.step = 0
			c.lastKill = -9
		end,
		tick = function(c, t)
			if t - c.lastKill > 0.5 then
				c.lastKill = t
				for _, u in ipairs(FindUnitsInRadius(R, at, nil, 2500, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BASIC, 0, 0, false)) do
					if label[u:entindex()] == nil and u:GetClassname() == "npc_dota_creep_lane" and u:IsAlive() then u:ForceKill(false) end
				end
			end
			if c.step == 0 then
				for _, u in ipairs(FindUnitsInRadius(D, at, nil, 800, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BASIC, 0, 0, false)) do
					if u:IsAlive() and u:GetClassname() == "npc_dota_creep_lane" and u:GetAttackTarget() == c.b then
						c.step = 1
						c.cr = u
						c.k = u:entindex()
						label[c.k] = "real"
						c.crs = { u }
						local p = u:GetAbsOrigin()
						say(string.format("%s fighting %s at %s,%s rel=%.2f clock=%.0f %s", c.tag, u:GetUnitName(), f0(p.x), f0(p.y), t, now(), t1dists(p)))
						local dir = (V(-7000, -6500) - p):Normalized()
						c.h = hero("npc_dota_hero_axe", R, p + dir * 300, "hero", true)
						c.tg = hero("npc_dota_hero_sniper", D, p + dir * 600, "dtgt")
						c.t1 = t
						break
					end
				end
			elseif c.step == 1 and t - c.t1 > 0.3 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				if t - c.tord > 0.1 and not c.held then
					c.held = true
					holdOrder(c.h)
				end
				local gone = c.cr:IsNull() or not c.cr:IsAlive()
				if not gone then drawCheck(c, t) end
				if gone or t - c.tord > 1.5 then
					say(string.format("%s result drawn=%d alive=%s on=%s clock=%.0f", c.tag, c.drawn[c.k] and 1 or 0, tostring(not gone),
						gone and "-" or L(c.cr:GetAttackTarget()), now()))
					if not gone then label[c.k] = nil end
					return true
				end
			end
		end,
	}
end
S.clash = {}
for rep = 1, 2 do
	for _, name in ipairs({ "dT1", "rT1", "both", "none" }) do table.insert(S.clash, clashTrial(name, rep)) end
end

-- restrict: before 5:00 a new wave is said to be undrawable unless within 1500 of a tier-one tower (whose is open). A real
-- (or made) Dire melee creep fighting the bait, drawn from 300: far from every tower, 1256 from the Radiant top T1, 1183
-- from the Dire top T1. Run once before 5:00 and once after.
local SITES = {
	{ name = "far", creep = V(-4400, Y), bait = V(-4340, Y), hero = V(-4700, Y), tgt = V(-5300, Y) },
	{ name = "rT1", creep = V(-6336, 600), bait = V(-6336, 660), hero = V(-6336, 300), tgt = V(-6036, 600) },
	{ name = "dT1", creep = V(-6300, 5300), bait = V(-6300, 5360), hero = V(-6300, 5000), tgt = V(-6200, 5600) },
}
local function restrictTrial(site, real)
	return {
		tag = string.format("restrict_%s_%s", site.name, real and "real" or "made"),
		timeout = 6,
		setup = function(c)
			c.cx, c.cy = site.creep.x, site.creep.y
			c.b = bait(site.bait, "bait")
			c.cr = direCreep("melee", real, site.creep, "melee")
			c.crs = { c.cr }
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, site.hero, "hero", true)
				c.tg = hero("npc_dota_hero_sniper", D, site.tgt, "dtgt")
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				if t - c.tord > 0.1 and not c.held then
					c.held = true
					holdOrder(c.h)
				end
				drawCheck(c, t)
				if t - c.tord > 1.5 then
					say(string.format("%s result drawn=%d on=%s clock=%.0f", c.tag, c.drawn[c.cr:entindex()] and 1 or 0, L(c.cr:GetAttackTarget()), now()))
					return true
				end
			end
		end,
	}
end
S.restrict = {}
for _, site in ipairs(SITES) do
	table.insert(S.restrict, restrictTrial(site, true))
	table.insert(S.restrict, restrictTrial(site, false))
end

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

-- The hero models a plain game has not loaded (an unloaded model asserts and writes a minidump, probe 1).
for _, n in ipairs({ "npc_dota_hero_axe", "npc_dota_hero_sniper" }) do
	pcall(function() PrecacheUnitByNameAsync(n, function() say("precached " .. n) end) end)
end
-- The site's trees (east of the creep, probe 1: they hid the hero until 250): cleared now, regrow in about 5 min.
-- Round 3f (the hand-over to the creep row, no-creep-unpaid s6b): as release3 `level` with no release order, the hero walks
-- back from 0.8 s to 250 behind our ranged creep; at 1.3 s after the order it attacks the nearest creep on it once, then walks
-- on (`hit`: a landed hit; `kill`: the creep set to 40 HP so the hit is a last hit), or does not (`none`, the control). Read:
-- whether the other chasers stay on the hero longer than the control, and who they take at the draw's end.
local function swingDrawTrial(mode, rep)
	return {
		tag = string.format("swingdraw_%s_%d", mode, rep),
		timeout = 15,
		setup = function(c)
			c.cx, c.cy = -4400, Y
			c.crs = wave(c, V(-4400, Y), false)
			c.own = creep("ranged", R, V(-4900, Y), "own")
			tank(c.own)
			c.step = 0
		end,
		tick = function(c, t)
			if c.step == 0 and t > 1.5 then
				c.step = 1
				c.h = hero("npc_dota_hero_axe", R, V(-4700, Y), "hero", true)
				pcall(function() c.h:SetBaseMoveSpeed(310) end)
				c.tg = hero("npc_dota_hero_sniper", D, V(-4700, Y - 300), "dtgt")
				watchAll(c, { c.own, c.b1 })
			elseif c.step == 1 and t > 2.5 then
				c.step = 2
				drawOrder(c, t)
			elseif c.step == 2 then
				watchTick(c, t)
				drawCheck(c, t)
				gaps(c, t)
				if t - c.tord > 0.8 and not c.moved then
					c.moved = true
					moveOrder(c.h, V(-5150, Y))
				end
				if mode ~= "none" and not c.swing and t - c.tord >= 1.3 then
					local cr = nearestOf(c, true)
					if cr then
						if mode == "kill" then
							pcall(function()
								cr:SetBaseHealthRegen(0)
								cr:SetHealth(40)
							end)
						end
						c.swing = { cr = cr, hp = cr:GetHealth(), t = t }
						local parts = {}
						for _, x in ipairs(c.crs) do
							if not x:IsNull() and x:IsAlive() then table.insert(parts, L(x) .. "=" .. L(x:GetAttackTarget())) end
						end
						say(string.format("%s swing rel=%.2f after_order=%.2f at=%s d=%s %s", c.tag, t, t - c.tord, L(cr), f0(d2(cr, c.h)), table.concat(parts, " ")))
						attackOrder(c.h, cr)
					end
				end
				local s = c.swing
				if s and not s.done then
					local dead = s.cr:IsNull() or not s.cr:IsAlive()
					if dead or s.cr:GetHealth() < s.hp or t - s.t > 2 then
						s.done = true
						local parts = {}
						for _, x in ipairs(c.crs) do
							if not x:IsNull() and x:IsAlive() then table.insert(parts, L(x) .. "=" .. L(x:GetAttackTarget())) end
						end
						say(string.format("%s %s rel=%.2f after_order=%.2f %s", c.tag, dead and "killed" or (t - s.t > 2 and "no_hit" or "landed"), t, t - c.tord,
							table.concat(parts, " ")))
						moveOrder(c.h, V(-5150, Y))
					end
				end
				if t - c.tord > 8 then
					local parts = {}
					for _, cr in ipairs(c.crs) do
						if not cr:IsNull() and cr:IsAlive() then table.insert(parts, L(cr) .. "=" .. L(cr:GetAttackTarget())) end
					end
					say(string.format("%s final %s", c.tag, table.concat(parts, " ")))
					return true
				end
			end
		end,
	}
end
S.swingdraw = {}
for rep = 1, 3 do
	for _, mode in ipairs({ "none", "hit", "kill" }) do table.insert(S.swingdraw, swingDrawTrial(mode, rep)) end
end

local function clearTrees()
	pcall(function() GridNav:DestroyTreesAroundPoint(V(-5100, Y), 1300, true) end)
	say("trees cleared")
end
clearTrees()
S.trees = { { tag = "trees", timeout = 1, setup = function() clearTrees() end, tick = function() return true end } }
say("registered")
