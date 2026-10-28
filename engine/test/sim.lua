-- Tiny frame simulator for verb/runner tests. Pure Lua (fengari 5.3 and LuaJIT).
-- Load with: local Sim = dofile("test/sim.lua")
--
--   local sim = Sim.new()
--   local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
--   local creep = sim:addCreep{ x = 100, y = 0, hp = 200, drain = 50 }
--   sim:adapter(tasks)            -- builds a fake Adapter and calls tasks.init with it
--   sim:at(1.0, function() ... end)
--   sim:step(0.1)
--
-- Units are plain tables; fields can be poked directly by tests (blocked, stunned, alive, hp, attackTarget,
-- hidden). A bot attack that lands sets the bot's lastAttackTime and makes the victim attack back
-- (attackTarget = bot) unless the victim has `passive`; a bot with `whiff` never lands an attack.
--
-- Attack model (for last-hit prediction): every swing has a wind-up of `attackPoint` seconds, during which
-- GetAnimActivity() is 1503 and GetAnimCycle() = elapsed / secondsPerAttack (so (attackPoint - cycle) *
-- secondsPerAttack is the wind-up left, as the verbs read it). A unit with `projectileSpeed` launches a tracking
-- projectile at the end of the wind-up (seen in the target's GetIncomingTrackingProjectiles) that deals its
-- damage on arrival. A unit with `autoAttack` swings at its attackTarget every `secondsPerAttack`, from
-- `firstSwingAt` (default 0), ignoring range. Kills by a bot count as a deny when the victim is on its team.
-- addTower is a unit seen by GetNearbyTowers. `drain` is reported as negative GetHealthRegen.
local Sim = {}
Sim.__index = Sim

local Unit = {}
Unit.__index = Unit

-- Module-wide so player IDs stay unique across Sim instances: verbs cache per (playerID, now()), and every
-- sim starts at t = 0.
local nextPlayerID = 1

local function dist(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
Sim.dist = dist

function Sim.new()
    return setmetatable({
        t = 0,
        units = {},
        events = {},
        logs = {},
        holds = {}, -- adapter hold calls: {id=, t=, tag=}
        calls = {}, -- calls[method][unit.id] = count
        nextId = 1,
    }, Sim)
end

function Sim:count(method, unit)
    local m = self.calls[method]
    return (m and m[unit.id]) or 0
end

function Sim:_count(method, unit)
    self.calls[method] = self.calls[method] or {}
    self.calls[method][unit.id] = (self.calls[method][unit.id] or 0) + 1
end

function Sim:_add(kind, o)
    local u = setmetatable({
        sim = self,
        id = self.nextId,
        kind = kind,
        team = o.team or (kind == "creep" and 3 or 2),
        playerID = o.playerID or nextPlayerID,
        loc = { x = o.x or 0, y = o.y or 0, z = 0 },
        speed = o.speed or 300,
        hp = o.hp or 1000,
        drain = o.drain or 0, -- hp lost per second
        alive = true,
        blocked = o.blocked or false,
        stunned = o.stunned or false,
        range = o.range or 150,
        damage = o.damage or 50,
        attackPoint = o.attackPoint or 0.3,
        lastHits = 0,
        denies = 0,
        maxHp = o.maxHp or o.hp or 1000,
        name = o.name,
        secondsPerAttack = o.secondsPerAttack or 1,
        projectileSpeed = o.projectileSpeed,
        autoAttack = o.autoAttack or false,
        nextSwingAt = o.firstSwingAt or 0,
        attackTarget = o.attackTarget,
        lastAttackTime = -1,
        hidden = o.hidden or false,
        passive = o.passive or false,
        cooldown = o.cooldown or false,
        fireTime = o.fireTime or false,
        fogged = o.fogged or false,
        facing = o.facing,
        variance = o.variance,
        whiff = o.whiff or false,
        mode = 0,
        actions = {}, -- log of issued actions: {kind=, t=, loc=/target=, targetHp=}
    }, Unit)
    self.nextId = self.nextId + 1
    nextPlayerID = nextPlayerID + 1
    self.units[#self.units + 1] = u
    return u
end

function Sim:addBot(o) return self:_add("bot", o or {}) end
function Sim:addCreep(o) return self:_add("creep", o or {}) end
function Sim:addHero(o) return self:_add("hero", o or {}) end
function Sim:addTower(o) return self:_add("tower", o or {}) end
--- A neutral creep (team 4), seen by GetNearbyNeutralCreeps only.
function Sim:addNeutral(o) o = o or {}; o.team = o.team or 4; return self:_add("neutral", o) end

--- Runs fn(sim) on the first step at or after time t.
function Sim:at(t, fn)
    self.events[#self.events + 1] = { t = t, fn = fn }
end

--- Kills `victim` now; credits a last hit when the killer is a bot.
function Sim:kill(victim, killer)
    if not victim.alive then return end
    victim.alive = false
    victim.hp = 0
    if killer and killer.kind == "bot" then
        if killer.team == victim.team then killer.denies = killer.denies + 1
        else killer.lastHits = killer.lastHits + 1 end
    end
end

function Sim:_hit(u, c, at)
    if not c.alive then return end
    u.lastAttackTime = at
    if not c.passive then c.attackTarget = u end
    c.hp = c.hp - u.damage
    if c.hp <= 0 then self:kill(c, u) end
end

function Sim:killAt(t, victim, killer)
    self:at(t, function(s) s:kill(victim, killer) end)
end

function Sim:step(dt)
    self.t = self.t + dt
    local pending = {}
    for _, e in ipairs(self.events) do
        if self.t >= e.t - 1e-9 then e.fn(self) else pending[#pending + 1] = e end
    end
    self.events = pending

    for _, u in ipairs(self.units) do
        if u.alive and u.drain ~= 0 then
            u.hp = u.hp - u.drain * dt
            if u.hp <= 0 then self:kill(u, nil) end
        end
    end

    for _, u in ipairs(self.units) do
        local sw = u.swing
        if sw and self.t >= sw.landAt - 1e-9 then
            u.swing = nil
            local c = sw.target
            if u.alive and c.alive and not u.whiff and (u.autoAttack or dist(u.loc, c.loc) <= u.range + 1e-6) then
                if u.projectileSpeed then
                    -- As Dota (GetLastAttackTime is the fire time): `fireTime` units stamp the launch.
                    if u.fireTime then u.lastAttackTime = sw.landAt end
                    self.projectiles = self.projectiles or {}
                    self.projectiles[#self.projectiles + 1] = {
                        caster = u, target = c, at = sw.landAt,
                        loc = { x = u.loc.x, y = u.loc.y, z = 0 },
                    }
                else
                    self:_hit(u, c, sw.landAt)
                end
            end
        end
    end

    local flying = {}
    for _, p in ipairs(self.projectiles or {}) do
        local c = p.target
        if c.alive then
            local step = p.caster.projectileSpeed * (self.t - p.at)
            p.at = self.t
            local d = dist(p.loc, c.loc)
            if d <= step + 1e-6 then
                self:_hit(p.caster, c, self.t)
            else
                p.loc.x = p.loc.x + (c.loc.x - p.loc.x) / d * step
                p.loc.y = p.loc.y + (c.loc.y - p.loc.y) / d * step
                flying[#flying + 1] = p
            end
        end
    end
    self.projectiles = flying

    for _, u in ipairs(self.units) do
        local tg = u.attackTarget
        if u.autoAttack and u.alive and not u.swing and tg and tg.alive and self.t >= u.nextSwingAt - 1e-9 then
            u.swing = { target = tg, start = u.nextSwingAt, landAt = u.nextSwingAt + u.attackPoint }
            u.nextSwingAt = u.nextSwingAt + u.secondsPerAttack
        end
    end

    for _, u in ipairs(self.units) do
        if u.alive and u.moveTarget and not u.blocked and not u.stunned and not u.swing then
            local d = dist(u.loc, u.moveTarget)
            local stepLen = u.speed * dt
            if d <= stepLen then
                u.loc.x, u.loc.y = u.moveTarget.x, u.moveTarget.y
                u.moveTarget = nil
            else
                u.loc.x = u.loc.x + (u.moveTarget.x - u.loc.x) / d * stepLen
                u.loc.y = u.loc.y + (u.moveTarget.y - u.loc.y) / d * stepLen
            end
        end
    end

    self:_stepCasts()
end

--- Fake Adapter (now = sim.t). Calls tasks.init(adapter) when `tasks` is given.
function Sim:adapter(tasks, opts)
    opts = opts or {}
    local sim = self
    local a = {
        now = function() return sim.t end,
        log = function(tag, msg) sim.logs[#sim.logs + 1] = tostring(tag) .. " " .. tostring(msg) end,
        enabled = function() return true end,
        claim = function() end,
        release = function() end,
        lastHitFilter = opts.lastHitFilter,
        skill = opts.skill,
        profile = opts.profile,
        lastHitError = opts.lastHitError,
        random = opts.random,
        attackClock = opts.attackClock,
        hold = function(bot, tag) sim.holds[#sim.holds + 1] = { id = bot.id, t = sim.t, tag = tag } end,
    }
    if tasks then tasks.init(a) end
    return a
end

-- Unit API (subset of Dota's bot unit API used by the verbs).
function Unit:GetPlayerID() return self.playerID end
function Unit:GetTeam() return self.team end
-- Only for units given `facing` / `variance`, so other tests keep the old (absent) behaviour.
function Unit:GetFacing() return self.facing end
function Unit:GetBaseDamageVariance() return self.variance end
-- A `fogged` unit is alive and its handle valid, but (as Dota for units out of sight) has no location.
function Unit:GetLocation() if self.fogged then return nil end return { x = self.loc.x, y = self.loc.y, z = 0 } end
function Unit:IsAlive() return self.alive end
function Unit:GetActiveMode() return self.mode end
function Unit:GetLastHits() return self.lastHits end
function Unit:IsStunned() return self.stunned end
function Unit:GetHealth() return self.hp end
function Unit:GetAttackRange() return self.range end
function Unit:GetAttackDamage() return self.damage end
function Unit:GetAttackPoint() return self.attackPoint end
function Unit:GetAttackTarget() return self.attackTarget end
function Unit:GetLastAttackTime() return self.lastAttackTime end
function Unit:CanBeSeen() return not self.hidden end
function Unit:GetDenies() return self.denies end
function Unit:GetMaxHealth() return self.maxHp end
function Unit:GetHealthRegen() return -self.drain end
function Unit:GetUnitName() return self.name or ("npc_" .. self.kind) end
function Unit:GetSecondsPerAttack() return self.secondsPerAttack end
function Unit:GetAttackProjectileSpeed() return self.projectileSpeed or 0 end
function Unit:GetCurrentMovementSpeed() return self.speed end
function Unit:GetAnimActivity() return self.swing and 1503 or 0 end
function Unit:GetAnimCycle()
    if not self.swing then return 0 end
    return (self.sim.t - self.swing.start) / self.secondsPerAttack
end
function Unit:GetIncomingTrackingProjectiles()
    local out = {}
    for _, p in ipairs(self.sim.projectiles or {}) do
        if p.target == self then
            out[#out + 1] = { location = { x = p.loc.x, y = p.loc.y, z = 0 }, caster = p.caster, is_attack = true }
        end
    end
    return out
end
function Unit:GetNearbyTowers(radius, enemies)
    local out = {}
    for _, u in ipairs(self.sim.units) do
        if u.alive and u.kind == "tower" and dist(self.loc, u.loc) <= radius
            and ((u.team ~= self.team) == (enemies and true or false)) then
            out[#out + 1] = u
        end
    end
    return out
end

--- Deterministic uniform [0, 1) generator, identical under fengari and LuaJIT.
function Sim.lcg(seed)
    local state = seed % 2147483647
    if state <= 0 then state = state + 2147483646 end
    local function nextState() state = (state * 16807) % 2147483647 end
    -- The first outputs of nearby small seeds are tiny and correlated; spin them off.
    for _ = 1, 8 do nextState() end
    return function()
        nextState()
        return (state - 1) / 2147483646
    end
end

function Unit:Action_MoveToLocation(loc)
    self.sim:_count("Action_MoveToLocation", self)
    self.actions[#self.actions + 1] = { kind = "move", t = self.sim.t, loc = { x = loc.x, y = loc.y }, native = loc.native }
    if self.swing then return end
    self.moveTarget = { x = loc.x, y = loc.y }
end

function Unit:Action_AttackUnit(target, once)
    self.sim:_count("Action_AttackUnit", self)
    self.actions[#self.actions + 1] = { kind = "attack", t = self.sim.t, target = target, targetHp = target.hp, once = once }
    self.moveTarget = nil
    self.attackTarget = target
    -- `cooldown` units cannot start a swing before secondsPerAttack after their last one started.
    local start = self.sim.t
    if self.cooldown and self.lastSwingStart then start = math.max(start, self.lastSwingStart + self.secondsPerAttack) end
    if self.swing and self.cooldown then return end
    self.lastSwingStart = start
    self.swing = { target = target, start = start, landAt = start + self.attackPoint }
end

function Unit:actionsOf(kind)
    local n = 0
    for _, a in ipairs(self.actions) do if a.kind == kind then n = n + 1 end end
    return n
end

local function nearby(self, radius, enemies, kind)
    local out = {}
    for _, u in ipairs(self.sim.units) do
        if u ~= self and u.alive and u.kind == kind and dist(self.loc, u.loc) <= radius
            and ((u.team ~= self.team) == (enemies and true or false)) then
            out[#out + 1] = u
        end
    end
    return out
end

function Unit:GetNearbyLaneCreeps(radius, enemies)
    self.sim:_count("GetNearbyLaneCreeps", self)
    return nearby(self, radius, enemies, "creep")
end

function Unit:GetNearbyNeutralCreeps(radius)
    self.sim:_count("GetNearbyNeutralCreeps", self)
    local out = {}
    for _, u in ipairs(self.sim.units) do
        if u.alive and u.kind == "neutral" and dist(self.loc, u.loc) <= radius then out[#out + 1] = u end
    end
    return out
end

function Unit:GetNearbyHeroes(radius, enemies, _mode)
    self.sim:_count("GetNearbyHeroes", self)
    return nearby(self, radius, enemies, "hero")
end

-- Abilities, items and runes ------------------------------------------------------------------------------
-- sim:addAbility(unit, { name=, cooldown=, manaCost=, castPoint=, channelTime=, effectLag= }) returns an
-- ability handle. A cast order starts the cast phase (ignored while `unit.ignoreOrders` or stunned, or when
-- not fully castable); the phase is cancelled by a stun, death, or the unit target dying/hiding. When it
-- completes the ability fires: cooldown and mana cost apply (`effectLag` seconds later, default 0), `fired`
-- increments and a channel starts if `channelTime` > 0; a stun or death ends the channel early.
-- sim:giveItem(unit, slot, opts) puts an ability-like item in an inventory slot.
-- sim:addRune(loc, { x=, y=, status= }) and sim:installRuneGlobals() / sim:removeRuneGlobals() fake the
-- Dota rune globals; a bot with a pick-up order within 50 units of the rune takes it (status MISSING).
local Ability = {}
Ability.__index = Ability
Sim.RUNE_STATUS_UNKNOWN, Sim.RUNE_STATUS_AVAILABLE, Sim.RUNE_STATUS_MISSING = 0, 1, 2

function Sim:addAbility(unit, o)
    o = o or {}
    local a = setmetatable({
        sim = self,
        owner = unit,
        name = o.name or "ability",
        cooldown = o.cooldown or 10,
        manaCost = o.manaCost or 0,
        castPoint = o.castPoint or 0.3,
        channelTime = o.channelTime or 0,
        effectLag = o.effectLag or 0,
        cdEnd = 0,
        fired = 0,
    }, Ability)
    unit.mana = unit.mana or 500
    unit.abilities = unit.abilities or {}
    unit.abilities[#unit.abilities + 1] = a
    return a
end

function Sim:giveItem(unit, slot, o)
    o = o or {}
    local item = self:addAbility(unit, o)
    unit.items = unit.items or {}
    unit.items[slot] = item
    return item
end

function Ability:GetName() return self.name end
function Ability:IsNull() return false end
function Ability:GetCooldownTimeRemaining() return math.max(0, self.cdEnd - self.sim.t) end
function Ability:GetCastPoint() return self.castPoint end
function Ability:GetChannelTime() return self.channelTime end
function Ability:GetManaCost() return self.manaCost end
function Ability:IsInAbilityPhase() return self.phase ~= nil end
function Ability:IsChanneling() return self.channel ~= nil end
function Ability:IsFullyCastable()
    return self:GetCooldownTimeRemaining() <= 0 and self.owner.mana >= self.manaCost
end

function Unit:GetMana() return self.mana end
function Unit:IsCastingAbility()
    for _, a in ipairs(self.abilities or {}) do if a.phase then return true end end
    return false
end
function Unit:IsChanneling()
    for _, a in ipairs(self.abilities or {}) do if a.channel then return true end end
    return false
end
function Unit:GetItemInSlot(slot) return (self.items or {})[slot] end
function Unit:FindItemSlot(name)
    for slot = 0, 16 do
        local it = (self.items or {})[slot]
        if it and it.name == name then return slot end
    end
    return -1
end

local function order(unit, kind, ability, target, loc)
    unit.sim:_count("cast", unit)
    unit.actions[#unit.actions + 1] = { kind = kind, t = unit.sim.t, ability = ability, target = target, loc = loc }
    if unit.ignoreOrders or unit.stunned or not unit.alive or ability.phase or ability.channel then return end
    if not ability:IsFullyCastable() then return end
    unit.moveTarget = nil
    ability.phase = { fireAt = unit.sim.t + ability.castPoint, target = target }
end

function Unit:Action_UseAbility(a) order(self, "cast", a) end
function Unit:Action_UseAbilityOnEntity(a, target) order(self, "cast_target", a, target) end
function Unit:Action_UseAbilityOnLocation(a, loc) order(self, "cast_loc", a, nil, { x = loc.x, y = loc.y }) end

function Ability:_step()
    local sim, u = self.sim, self.owner
    if self.pendingEffect and sim.t >= self.pendingEffect.at - 1e-9 then
        self.cdEnd = self.pendingEffect.at + self.cooldown
        u.mana = u.mana - self.manaCost
        self.pendingEffect = nil
    end
    local ph = self.phase
    if ph then
        local tg = ph.target
        if u.stunned or not u.alive or (tg and (not tg.alive or tg.hidden)) then
            self.phase = nil
        elseif sim.t >= ph.fireAt - 1e-9 then
            self.phase = nil
            self.fired = self.fired + 1
            self.pendingEffect = { at = ph.fireAt + self.effectLag }
            if self.effectLag <= 0 then self:_step() end
            if self.channelTime > 0 then self.channel = { endAt = ph.fireAt + self.channelTime } end
        end
    end
    local ch = self.channel
    if ch and (u.stunned or not u.alive or sim.t >= ch.endAt - 1e-9) then self.channel = nil end
end

function Sim:addRune(loc, o)
    o = o or {}
    self.runes = self.runes or {}
    self.runes[loc] = { loc = { x = o.x or 0, y = o.y or 0 }, status = o.status or Sim.RUNE_STATUS_AVAILABLE }
    return self.runes[loc]
end

function Sim:installRuneGlobals()
    local sim = self
    GetRuneStatus = function(loc) return sim.runes[loc].status end
    GetRuneSpawnLocation = function(loc) local r = sim.runes[loc].loc; return { x = r.x, y = r.y, z = 0 } end
    RUNE_STATUS_UNKNOWN, RUNE_STATUS_AVAILABLE, RUNE_STATUS_MISSING =
        Sim.RUNE_STATUS_UNKNOWN, Sim.RUNE_STATUS_AVAILABLE, Sim.RUNE_STATUS_MISSING
end

function Sim:removeRuneGlobals()
    GetRuneStatus, GetRuneSpawnLocation = nil, nil
    RUNE_STATUS_UNKNOWN, RUNE_STATUS_AVAILABLE, RUNE_STATUS_MISSING = nil, nil, nil
end

function Unit:Action_PickUpRune(loc)
    self.sim:_count("Action_PickUpRune", self)
    self.actions[#self.actions + 1] = { kind = "rune", t = self.sim.t, rune = loc }
    local r = self.sim.runes and self.sim.runes[loc]
    if r then
        self.pickup = loc
        self.moveTarget = { x = r.loc.x, y = r.loc.y }
    end
end

function Sim:_stepCasts()
    for _, u in ipairs(self.units) do
        for _, a in ipairs(u.abilities or {}) do a:_step() end
        local r = u.pickup and self.runes[u.pickup]
        if r and u.alive and r.status == Sim.RUNE_STATUS_AVAILABLE and dist(u.loc, r.loc) <= 50 then
            r.status = Sim.RUNE_STATUS_MISSING
            r.takenBy = u
            u.pickup = nil
        end
    end
end

return Sim
