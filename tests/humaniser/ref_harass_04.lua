-- Verbatim copy of 04's HarassThink from bots/mode_laning_generic.lua: the reference that the shared harass
-- tool's idle poke must match (regression scenario 15). test_lane_harass pins the text against the mode file.
-- Free names (bot, J, AllyLastHit, nInRangeEnemy, botAttackRange and the three harass state locals) resolve
-- through env, so assignments to the state persist in env between calls.
return function(env)
	local _ENV = setmetatable({}, {
		__index = function(_, k) local v = env[k] if v ~= nil then return v end return _G[k] end,
		__newindex = env,
	})
local function HarassThink()
	local s = AllyLastHit.Settings()
	local now = GameTime()
	if J.IsValidHero(harassTarget) and now - harassStartTime < s.HarassWindow and bot:GetLastAttackTime() < harassStartTime then
		bot:Action_AttackUnit(harassTarget, true)
		return true
	end
	harassTarget = nil
	if now - lastHarassTime < s.HarassInterval or J.GetHP(bot) < s.HarassMinHP then return false end
	if AllyLastHit.GetProtectedHuman(bot, bot:GetLocation()) == nil or not J.WeAreStronger(bot, 1200) then return false end

	local nTowers = bot:GetNearbyTowers(1600, true)
	local target, nTargetDist = nil, botAttackRange + s.HarassExtraRange
	for _, enemy in pairs(nInRangeEnemy or {}) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and GetUnitToUnitDistance(bot, enemy) <= nTargetDist then
			local bUnderTower = false
			for _, tower in pairs(nTowers) do
				if J.IsValidBuilding(tower) and (GetUnitToUnitDistance(tower, bot) < s.TowerAvoidRange or GetUnitToUnitDistance(tower, enemy) < s.TowerAvoidRange) then
					bUnderTower = true
				end
			end
			if not bUnderTower then
				target, nTargetDist = enemy, GetUnitToUnitDistance(bot, enemy)
			end
		end
	end
	if target == nil then return false end

	harassTarget, harassStartTime, lastHarassTime = target, now, now
	bot:Action_AttackUnit(target, true)
	return true
end
	return HarassThink
end
