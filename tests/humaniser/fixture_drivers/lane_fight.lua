-- Driver: a lane fight played frame by frame (lane_fight_world.lua: a pos 5 bot against one enemy laner in the bottom
-- lane, mode scoring every 0.31 s, LaneFight.Tick and Intent.Tick every frame).
-- world: burst, botX, enemyX, botLevel, enemyLevel, botHP, enemyHP (lane_fight_world options), and steps, run in order:
--        {play = seconds} | {burst = n} (the bot's estimated damage from now) | {towerAggro = true} (the bot and the
--        enemy stand under the enemy T1, which targets the bot) | {retreat = d} (OHA's retreat desire before claims).
-- Observation: commitEnd(<reason>) for each commit that ended, committing while a commit claim is held at the end;
-- desire.retreat, desire.roam from a scoring round after the last step; fact.retreatBase = OHA's retreat desire then.
dofile(HARNESS_DIR .. "/lane_fight_world.lua")

return function(fx, skill)
	local w = fx.world
	local W = LaneFightWorld({ skill = skill or 1, burst = w.burst, botX = w.botX, enemyX = w.enemyX, botLevel = w.botLevel,
		enemyLevel = w.enemyLevel, botHP = w.botHP, enemyHP = w.enemyHP })
	local y = W.bot.loc.y
	for _, s in ipairs(w.steps or {}) do
		if s.burst then W.bot.estDamage = s.burst end
		if s.retreat then W.retreat = s.retreat end
		if s.towerAggro then
			local tower
			for _, t in pairs(TOWERS_W[W.bot.team == 2 and 3 or 2]) do if math.abs(t.loc.y - y) < 1000 then tower = t end end
			W.bot.loc = Vector(tower.loc.x - W.sign * 600, y)
			W.enemy.loc = Vector(tower.loc.x - W.sign * 400, y)
			tower.target = W.bot
		end
		if s.play then LaneFightPlay(W, s.play) end
	end
	LaneFightScore(W)
	local obs = { actions = {}, desire = { retreat = W.last.retreat, roam = W.last.roam }, fact = { retreatBase = W.retreat } }
	for _, l in ipairs(W.lines) do
		if l:find("ev=lanefight_end", 1, true) and l:find("phase=commit", 1, true) then
			table.insert(obs.actions, { verb = "commitEnd", target = l:match("reason=([%w%-]+)") })
		end
	end
	if W.age("commit") ~= nil then table.insert(obs.actions, { verb = "committing" }) end
	return obs
end
