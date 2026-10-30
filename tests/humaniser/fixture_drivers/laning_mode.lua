-- Driver: mode_laning_generic GetDesire then Think, in the stub world of laning_mode_world.lua (skill-independent).
-- world: t, owned, ours (Ours.LeaveCoreCreep), humanPos5, bot {pos, x, y, range, dmg, target = creep id it is attacking}, creeps [{id, team = enemy|ally, hp, x, y}],
--        allies [{id, pos, x, y, range, target = creep id, toward = {x, y}}] (allied bot heroes), frames [{t, creeps = {[id] = {hp}}, allies = {[id] = {x, y}}}]
-- Observation (last frame): lastHit/deny(creep#id) for AttackUnit on an enemy/allied creep, move(creep#id) for
-- MoveToUnit, hold for MoveToLocation at the bot's spot, move for any other MoveToLocation, attempt(creep#id) for a
-- counted last-hit attempt; desire.laning = GetDesire().
-- mode (the team_roam driver): { file = mode file, think = true } runs that file's Think alone, without GetDesire.
dofile(HARNESS_DIR .. "/laning_mode_world.lua")

return function(fx, mode)
	local w = fx.world
	local byId, enemies, allyCreeps = {}, {}, {}
	for _, c in ipairs(w.creeps or {}) do
		local u = LaningCreep({ hp = c.hp, loc = Vector(c.x or 0, c.y or 0), team = c.team == "ally" and 2 or 3 })
		u.fixtureId = "creep#" .. c.id
		byId[c.id] = u
		table.insert(c.team == "ally" and allyCreeps or enemies, u)
	end
	local allies, allyById = {}, {}
	for _, a in ipairs(w.allies or {}) do
		local h = LaningHero({ pos = a.pos, pid = a.id, loc = Vector(a.x or 0, a.y or 0), range = a.range })
		if a.toward then h.toward = Vector(a.toward.x, a.toward.y) end
		if a.target then h.target = byId[a.target] end
		allyById[a.id] = h
		table.insert(allies, h)
	end
	local b = w.bot or {}
	local frames = w.frames or { {} }
	local bot, attempts, desire
	for i, f in ipairs(frames) do
		for id, s in pairs(f.creeps or {}) do byId[tonumber(id)].hp = s.hp end
		for id, s in pairs(f.allies or {}) do allyById[tonumber(id)].loc = Vector(s.x, s.y) end
		local t = f.t or w.t or 120
		if i == 1 then
			bot, attempts = LaningLoad({ t = t, pos = b.pos, range = b.range, dmg = b.dmg, loc = Vector(b.x or 0, b.y or 0),
				owned = w.owned == true, ours = w.ours == true, humanPos5 = w.humanPos5 == true, enemyCreeps = enemies, allyCreeps = allyCreeps, allies = allies,
				modeFile = mode and mode.file })
			if b.target then bot.target = byId[b.target] end
		else
			DotaTime = function() return t end
			GameTime = DotaTime
		end
		bot.actions = {}
		for k in pairs(attempts) do attempts[k] = nil end
		if not (mode and mode.think) then desire = GetDesire() end
		Think()
	end
	local obs = { actions = {}, desire = { laning = desire } }
	if mode and mode.think then obs.desire = {} end
	local here = bot:GetLocation()
	for _, a in ipairs(bot.actions) do
		local target = a.args[1]
		if a.name == "AttackUnit" then
			local ally = false
			for _, c in ipairs(allyCreeps) do if c == target then ally = true end end
			table.insert(obs.actions, { verb = ally and "deny" or "lastHit", target = target and target.fixtureId })
		elseif a.name == "MoveToUnit" then
			table.insert(obs.actions, { verb = "move", target = target and target.fixtureId })
		elseif a.name == "MoveToLocation" then
			local still = target ~= nil and math.abs(target.x - here.x) < 1 and math.abs(target.y - here.y) < 1
			table.insert(obs.actions, { verb = still and "hold" or "move" })
		end
	end
	for _, c in ipairs(attempts) do table.insert(obs.actions, { verb = "attempt", target = c.fixtureId }) end
	return obs
end
