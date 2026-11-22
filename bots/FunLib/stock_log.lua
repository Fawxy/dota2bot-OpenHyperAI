-- Log-only telemetry for the stock mirror arm: the subset of our fork's `[HEV]` lines that the batch readers use. Reads
-- facts only and issues no order. `ev=bot` and `ev=snap` once a second per hero; for the gold ledger (tools/hlog/gold.js)
-- `ev=creep_death`, `ev=neutral_death`, `ev=inv` and `ev=rune_pickup`; for hlog @mode_episodes `ev=mode`. Each event keeps
-- our fork's definition (typescript/bots/FunLib/humaniser/telemetry.ts at team-bots c02c5a61: trackCreepDeaths,
-- trackInventory, trackRunes, trackMode) and its timing: creep deaths every frame, modes and runes every third frame as
-- Humaniser.Tick runs them, the inventory with the snapshot. Fields no reader of the stock arm needs are left out.
local L = {}

local BUILD = 'stock-cb814c6c'
local INTERVAL = 1

local MODES = {
	[BOT_MODE_NONE] = 'none', [BOT_MODE_LANING] = 'laning', [BOT_MODE_ATTACK] = 'attack', [BOT_MODE_ROAM] = 'roam',
	[BOT_MODE_RETREAT] = 'retreat', [BOT_MODE_SECRET_SHOP] = 'secret_shop', [BOT_MODE_SIDE_SHOP] = 'side_shop',
	[BOT_MODE_RUNE] = 'rune', [BOT_MODE_PUSH_TOWER_TOP] = 'push_top', [BOT_MODE_PUSH_TOWER_MID] = 'push_mid',
	[BOT_MODE_PUSH_TOWER_BOT] = 'push_bot', [BOT_MODE_DEFEND_TOWER_TOP] = 'defend_top',
	[BOT_MODE_DEFEND_TOWER_MID] = 'defend_mid', [BOT_MODE_DEFEND_TOWER_BOT] = 'defend_bot',
	[BOT_MODE_ASSEMBLE] = 'assemble', [BOT_MODE_TEAM_ROAM] = 'team_roam', [BOT_MODE_FARM] = 'farm',
	[BOT_MODE_DEFEND_ALLY] = 'defend_ally', [BOT_MODE_EVASIVE_MANEUVERS] = 'evasive', [BOT_MODE_ROSHAN] = 'roshan',
	[BOT_MODE_ITEM] = 'item', [BOT_MODE_WARD] = 'ward',
}

-- The fork's numbering (ts_libs/dota enums) where the VM leaves a constant unset.
local ENEMY_CREEPS = UNIT_LIST_ENEMY_CREEPS or 9
local ALLIED_CREEPS = UNIT_LIST_ALLIED_CREEPS or 3
local NEUTRAL_CREEPS = UNIT_LIST_NEUTRAL_CREEPS or 13
local ENEMY_HEROES = UNIT_LIST_ENEMY_HEROES or 8
local POWER1, POWER2 = RUNE_POWERUP_1 or 0, RUNE_POWERUP_2 or 1
local RUNES = { POWER1, POWER2, RUNE_BOUNTY_1 or 2, RUNE_BOUNTY_2 or 3, RUNE_BOUNTY_3 or 4, RUNE_BOUNTY_4 or 5 }

-- The fork's constants, with its reasons (telemetry.ts).
local CREEP_DEATH_UNTIL = 720 -- creep deaths are logged up to here
local DEATH_MAX_HP = 0.5 -- a creep that vanishes above this health share left vision; it did not die
local DEATH_NEAR = 1500 -- deaths are logged only this close to an own hero
local KILLER_NEAR = 1200 -- a hero whose last hits (or an enemy whose denies) rose takes the nearest death within this
local ITEM_SLOTS = 17
local RUNES_FROM = 1 -- rune status is stale across 0:00
local RUNE_TAKER_R = 400 -- the own hero nearest a vanished rune took it if this close
local RUNE_EXPIRE_FOR = 0.15 -- a power rune gone this soon after a spawn tick despawned unpicked
local RUNE_RESPAWN = 120 -- power runes spawn every 2 minutes
local POWER_FROM = 360 -- power spots hold water runes before 6:00
local TICK_EVERY = 3 -- Humaniser.Tick's full steps run every third frame (Customize.Humaniser.TickEvery)

local snapAt, announced, heroState = {}, {}, {}
local teamJobAt, creepTracks, worlds = {}, {}, {}
local frameAt, frameNo, stepsDue = nil, 0, true

local function fmt(v)
	if type(v) == 'number' then
		if v == math.floor(v) and math.abs(v) < 1e9 then return string.format('%d', v) end
		return string.format('%.3f', v)
	end
	if type(v) == 'boolean' then return v and '1' or '0' end
	local s = tostring(v)
	if s ~= '' and not string.find(s, '[%s="]') then return s end
	return '"' .. string.gsub(string.gsub(s, '"', "'"), '[\r\n]', ' ') .. '"'
end

local function emit(ev, fields)
	local parts = { '[HEV]', 't=' .. fmt(DotaTime()), 'ev=' .. ev }
	for _, f in ipairs(fields) do
		if f[2] ~= nil then parts[#parts + 1] = f[1] .. '=' .. fmt(f[2]) end
	end
	local Utils = require(GetScriptDirectory() .. '/FunLib/utils')
	-- OHA's print override drops everything outside its debug mode.
	local out = Utils.RawPrint or print
	out(table.concat(parts, ' '))
end

-- Each part runs under its own pcall, so an error costs only that part; the first error of each part is logged.
local erred = {}
local function guarded(where, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not erred[where] then
		erred[where] = true
		pcall(emit, 'stock_log_error', { { 'where', where }, { 'text', tostring(err) } })
	end
end

local function pct(a, b)
	if b == nil or b <= 0 then return 0 end
	return math.floor(100 * a / b + 0.5)
end

local function stateOf(pid)
	local s = heroState[pid]
	if s == nil then
		s = {}
		heroState[pid] = s
	end
	return s
end

-- Team-wide work once per team and frame, by the first of its bots to tick.
local function firstThisFrame(job, team, now)
	local key = job .. team
	if teamJobAt[key] == now then return false end
	teamJobAt[key] = now
	return true
end

-- The calling bot's team, members 1..5: GetTeamPlayers is empty for a bot-only team.
local function teamHeroes()
	local heroes = {}
	for i = 1, 5 do
		local m = GetTeamMember(i)
		if m ~= nil and m:IsAlive() then heroes[#heroes + 1] = m end
	end
	return heroes
end

local function nearest(units, loc)
	local best, bestD = nil, math.huge
	for _, u in ipairs(units) do
		local d = GetUnitToLocationDistance(u, loc)
		if d < bestD then best, bestD = u, d end
	end
	return best, bestD
end

local function snapshot(bot, pid, now)
	local loc, target = bot:GetLocation(), bot:GetAttackTarget()
	local tgt, tid
	if target ~= nil then
		tgt = target:GetUnitName()
		if string.find(tgt, 'npc_dota_hero_', 1, true) and not target:IsIllusion() then tid = 'h' .. target:GetPlayerID() end
	end
	local alive = bot:IsAlive()
	emit('snap', {
		{ 'pid', pid }, { 'x', math.floor(loc.x) }, { 'y', math.floor(loc.y) }, { 'alive', alive },
		{ 'hp', pct(bot:GetHealth(), bot:GetMaxHealth()) }, { 'mp', pct(bot:GetMana(), bot:GetMaxMana()) },
		{ 'hpm', math.floor(bot:GetMaxHealth()) }, { 'lvl', bot:GetLevel() },
		{ 'lh', bot:GetLastHits() }, { 'dn', bot:GetDenies() },
		{ 'kills', GetHeroKills(pid) }, { 'deaths', GetHeroDeaths(pid) },
		{ 'tgt', tgt }, { 'tid', tid },
		{ 'mode', MODES[bot:GetActiveMode()] or ('mode_' .. tostring(bot:GetActiveMode())) },
		{ 'd', bot:GetActiveModeDesire() }, { 'gold', bot:GetGold() }, { 'nw', bot:GetNetWorth() },
		{ 'hit', alive and bot:WasRecentlyDamagedByAnyHero(1) or nil },
	})
end

-- ev=inv: `s<slot>=<name>[:<charges>]` per filled slot, at the first snapshot and whenever the layout differs.
local function inventory(bot, pid)
	local parts = {}
	for slot = 0, ITEM_SLOTS - 1 do
		local item = bot:GetItemInSlot(slot)
		if item ~= nil then
			local name = string.gsub(item:GetName(), '^item_', '')
			local charges = item:GetCurrentCharges()
			parts[#parts + 1] = charges > 0 and ('s' .. slot .. '=' .. name .. ':' .. charges) or ('s' .. slot .. '=' .. name)
		end
	end
	local sig = table.concat(parts, ' ')
	local s = stateOf(pid)
	if sig == s.invSig then return end
	s.invSig = sig
	emit('inv', { { 'pid', pid }, { 'items', sig } })
end

-- ev=mode: a change of the bot's active mode, with the new mode's desire and how long the old one lasted.
local function trackMode(bot, pid, now)
	local s = stateOf(pid)
	local mode = bot:GetActiveMode()
	if mode == s.mode then return end
	local from = s.mode
	s.mode = mode
	local dwell = now - (s.modeSince or now)
	s.modeSince = now
	if from == nil then return end
	emit('mode', { { 'pid', pid }, { 'from', MODES[from] or ('mode_' .. from) }, { 'to', MODES[mode] or ('mode_' .. mode) },
		{ 'd', bot:GetActiveModeDesire() }, { 'dwell', dwell } })
end

-- ev=rune_pickup: a rune that vanishes with an own hero nearer than any enemy, and within reach, was that hero's.
local function trackRunes(team, now)
	if now < RUNES_FROM then return end
	local w = worlds[team]
	if w == nil then
		w = {}
		worlds[team] = w
	end
	for _, r in ipairs(RUNES) do
		local seen = w[r]
		if GetRuneStatus(r) == RUNE_STATUS_AVAILABLE then
			if seen == nil or not seen.up then w[r] = { up = true, loc = GetRuneSpawnLocation(r) } end
		elseif seen ~= nil and seen.up then
			seen.up = false
			local power = r == POWER1 or r == POWER2
			if not (power and now >= RUNE_RESPAWN and now % RUNE_RESPAWN < RUNE_EXPIRE_FOR) then
				local taker, d = nearest(teamHeroes(), seen.loc)
				if taker ~= nil and d <= RUNE_TAKER_R then
					local _, enemyD = nearest(GetUnitList(ENEMY_HEROES) or {}, seen.loc)
					if enemyD >= d then
						emit('rune_pickup', { { 'pid', taker:GetPlayerID() }, { 'team', team }, { 'rune', r },
							{ 'kind', power and (now < POWER_FROM and 'water' or 'power') or 'bounty' },
							{ 'x', math.floor(seen.loc.x) }, { 'y', math.floor(seen.loc.y) } })
					end
				end
			end
		end
	end
end

-- Creep deaths, read from what was seen last frame, never through a dead creep's handle.
local function creepKind(name)
	local lane = string.find(name, 'creep_goodguys', 1, true) or string.find(name, 'creep_badguys', 1, true)
	if string.find(name, 'siege', 1, true) then return 'siege' end
	if not lane then return nil end
	return string.find(name, 'ranged', 1, true) and 'ranged' or 'melee'
end
local function laneKindOf(u) return creepKind(u:GetUnitName()) end
local function neutralKindOf(u) return u:IsAncientCreep() and 'ancient' or 'neutral' end

local function see(into, u, kindOf)
	local rec = into[u]
	local kind = rec ~= nil and rec.kind or kindOf(u)
	if kind == nil then return end
	local loc = u:GetLocation()
	local hp = u:GetHealth() / math.max(1, u:GetMaxHealth())
	if rec == nil then
		into[u] = { kind = kind, x = loc.x, y = loc.y, hp = hp }
		return
	end
	rec.x, rec.y, rec.hp = loc.x, loc.y, hp
end

local function deathDistance(u, d)
	local loc = u:GetLocation()
	return math.sqrt((loc.x - d.seen.x) ^ 2 + (loc.y - d.seen.y) ^ 2)
end

local function claimDeaths(deaths, unit, n, by)
	for _ = 1, n do
		local best, bestD = nil, KILLER_NEAR
		for _, d in ipairs(deaths) do
			local dist = deathDistance(unit, d)
			if d.by == nil and dist <= bestD then best, bestD = d, dist end
		end
		if best == nil then return end
		best.by = by
	end
end

local function rise(counts, pid, value)
	local prev = counts[pid]
	counts[pid] = value
	return (prev ~= nil and value > prev) and value - prev or 0
end

-- The deaths of a table's units that are no longer listed, at low health, near an own hero.
local function vanished(seenBy, live, heroes)
	local deaths = {}
	for creep, seen in pairs(seenBy) do
		if not live[creep] then
			seenBy[creep] = nil
			if seen.hp <= DEATH_MAX_HP then
				local d = { seen = seen }
				for _, h in ipairs(heroes) do
					if deathDistance(h, d) <= DEATH_NEAR then
						deaths[#deaths + 1] = d
						break
					end
				end
			end
		end
	end
	return deaths
end

local function listed(kind)
	local units, live = {}, {}
	for _, u in ipairs(GetUnitList(kind) or {}) do
		if u ~= nil and u:IsAlive() then
			units[#units + 1] = u
			live[u] = true
		end
	end
	return units, live
end

local function trackCreepDeaths(bot, now)
	if now < 0 or now > CREEP_DEATH_UNTIL then return end
	local team = bot:GetTeam()
	if not firstThisFrame('creeps', team, now) then return end
	local c = creepTracks[team]
	if c == nil then
		c = { creeps = {}, neutrals = {}, lastHits = {}, denies = {} }
		creepTracks[team] = c
	end
	local heroes = teamHeroes()
	local alive, live = listed(ENEMY_CREEPS)
	local deaths = vanished(c.creeps, live, heroes)
	-- A neutral kill raises the last hits too, so neutral deaths share the claim pool. Its own pcall: an error reading
	-- neutrals must not cost this frame's lane deaths.
	local neutralList, neutralDeaths = {}, {}
	local ok, err = pcall(function()
		local nlive
		neutralList, nlive = listed(NEUTRAL_CREEPS)
		neutralDeaths = vanished(c.neutrals, nlive, heroes)
	end)
	if not ok then
		neutralList, neutralDeaths = {}, {}
		if not erred.neutrals then
			erred.neutrals = true
			emit('stock_log_error', { { 'where', 'neutrals' }, { 'text', tostring(err) } })
		end
	end
	local pool = {}
	for _, d in ipairs(deaths) do pool[#pool + 1] = d end
	for _, d in ipairs(neutralDeaths) do pool[#pool + 1] = d end
	for _, h in ipairs(heroes) do
		local n = rise(c.lastHits, h:GetPlayerID(), h:GetLastHits())
		if n > 0 then claimDeaths(pool, h, n, tostring(h:GetPlayerID())) end
	end
	for _, e in ipairs(GetUnitList(ENEMY_HEROES) or {}) do
		if e ~= nil and e:IsAlive() and not e:IsIllusion() then
			local okDn, dn = pcall(function() return e:GetDenies() end)
			local n = (okDn and type(dn) == 'number') and rise(c.denies, e:GetPlayerID(), dn) or 0
			if n > 0 then claimDeaths(deaths, e, n, 'deny') end
		end
	end
	for _, d in ipairs(deaths) do
		emit('creep_death', { { 'team', team }, { 'kind', d.seen.kind }, { 'x', math.floor(d.seen.x) },
			{ 'y', math.floor(d.seen.y) }, { 'hp', d.seen.hp }, { 'by', d.by or 'none' } })
	end
	for _, d in ipairs(neutralDeaths) do
		emit('neutral_death', { { 'team', team }, { 'kind', d.seen.kind }, { 'x', math.floor(d.seen.x) },
			{ 'y', math.floor(d.seen.y) }, { 'hp', d.seen.hp }, { 'by', d.by or 'none' } })
	end
	for _, u in ipairs(neutralList) do
		-- A neutral removed this frame can still be listed with no location.
		if u:GetLocation() ~= nil then see(c.neutrals, u, neutralKindOf) end
	end
	for _, u in ipairs(alive) do see(c.creeps, u, laneKindOf) end
end

local function announce(bot, pid, now)
	if announced[pid] and not (announced[pid] == 0 and now > 0) then return end
	-- Positions settle after hero selection, so the line is repeated once the clock passes zero.
	announced[pid] = now > 0 and 1 or 0
	local J = require(GetScriptDirectory() .. '/FunLib/jmz_func')
	emit('bot', { { 'pid', pid }, { 'hero', string.gsub(bot:GetUnitName(), 'npc_dota_hero_', '') }, { 'team', bot:GetTeam() },
		{ 'schema', 2 }, { 'humaniser', false }, { 'build', BUILD }, { 'pos', J.GetPosition(bot) }, { 'ours', 'stock' } })
end

function L.Tick(bot)
	-- Humaniser.Tick counts frames for every bot before anything else.
	local frame = GameTime()
	if frame ~= frameAt then
		frameAt, frameNo = frame, frameNo + 1
		stepsDue = frameNo % TICK_EVERY == 0
	end
	local state = GetGameState()
	if state ~= GAME_STATE_GAME_IN_PROGRESS and state ~= GAME_STATE_PRE_GAME then return end
	local pid, now = bot:GetPlayerID(), DotaTime()
	guarded('bot', announce, bot, pid, now)
	if stepsDue then
		guarded('mode', trackMode, bot, pid, now)
		local team = bot:GetTeam()
		if firstThisFrame('world', team, now) then guarded('runes', trackRunes, team, now) end
	end
	guarded('creeps', trackCreepDeaths, bot, now)
	if snapAt[pid] ~= nil and now - snapAt[pid] < INTERVAL then return end
	snapAt[pid] = now
	guarded('snap', snapshot, bot, pid, now)
	guarded('inv', inventory, bot, pid)
end

return L
