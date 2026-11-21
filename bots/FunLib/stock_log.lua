-- Log-only snapshots for the stock mirror arm: the subset of our fork's `[HEV] ev=bot` and `ev=snap` lines that the
-- batch readers use, once a second per hero. Reads facts only and issues no order.
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

local snapAt, announced = {}, {}

local function fmt(v)
	if type(v) == 'number' then
		if v == math.floor(v) and math.abs(v) < 1e9 then return string.format('%d', v) end
		return string.format('%.3f', v)
	end
	if type(v) == 'boolean' then return v and '1' or '0' end
	return tostring(v)
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

local function pct(a, b)
	if b == nil or b <= 0 then return 0 end
	return math.floor(100 * a / b + 0.5)
end

local function tick(bot)
	local state = GetGameState()
	if state ~= GAME_STATE_GAME_IN_PROGRESS and state ~= GAME_STATE_PRE_GAME then return end
	local pid, now = bot:GetPlayerID(), DotaTime()
	local hero = string.gsub(bot:GetUnitName(), 'npc_dota_hero_', '')
	if not announced[pid] or (announced[pid] == 0 and now > 0) then
		-- Positions settle after hero selection, so the line is repeated once the clock passes zero.
		announced[pid] = now > 0 and 1 or 0
		local J = require(GetScriptDirectory() .. '/FunLib/jmz_func')
		emit('bot', { { 'pid', pid }, { 'hero', hero }, { 'team', bot:GetTeam() }, { 'schema', 2 },
			{ 'humaniser', false }, { 'build', BUILD }, { 'pos', J.GetPosition(bot) }, { 'ours', 'stock' } })
	end
	if snapAt[pid] ~= nil and now - snapAt[pid] < INTERVAL then return end
	snapAt[pid] = now
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

local failed = false
function L.Tick(bot)
	if failed then return end
	local ok, err = pcall(tick, bot)
	if not ok then
		failed = true
		pcall(emit, 'stock_log_error', { { 'text', '"' .. string.gsub(tostring(err), '["\r\n]', ' ') .. '"' } })
	end
end

return L
