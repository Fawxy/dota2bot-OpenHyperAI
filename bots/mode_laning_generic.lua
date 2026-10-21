local Utils = require( GetScriptDirectory()..'/FunLib/utils')
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')

local Version      = require(GetScriptDirectory()..'/FunLib/version')
local Localization = require(GetScriptDirectory()..'/FunLib/localization')


local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local local_mode_laning_generic = nil
local nAllyCreeps = nil
local nEnemyCreeps = nil
local nFurthestEnemyAttackRange = 0
local nInRangeEnemy = nil
local botAssignedLane = nil
local botAttackRange = bot:GetAttackRange()
local attackDamage = bot:GetAttackDamage()
local nH, enemyBots = J.Utils.NumHumanBotPlayersInTeam(GetOpposingTeam())
local teamHumans, teamBots = J.Utils.NumHumanBotPlayersInTeam(GetTeam())

-- Announcer state
local hasPickedOneAnnouncer      = false
local lastAnnouncePrintedTime    = 0
local numberAnnouncePrinted      = 1
local announcementGapSeconds     = 6
local isChangePosMessageDone     = false

if Utils.BuggyHeroesDueToValveTooLazy[botName] then local_mode_laning_generic = dofile( GetScriptDirectory().."/FunLib/override_generic/mode_laning_generic" ) end

-- Humaniser ally last-hit etiquette. Valve's C++ laning cannot be filtered, so allies of humans get OHA's
-- Think() below for the whole game. Decided once at load: Think() cannot hand control back to Valve later.
local AllyLastHit = J.Humaniser.AllyLastHit
local bHumaniserLaning = AllyLastHit.OwnsLaning(bot)
local harassTarget = nil
local harassStartTime = -90
local lastHarassTime = -90

local function CanTakeLastHit(creep)
	local bMay, sReason = AllyLastHit.MayLastHit(bot, creep)
	if not bMay then return false end
	if string.sub(sReason, 1, 5) == 'take:' then return true end
	return J.GetPosition(bot) <= 2 or not J.IsThereNonSelfCoreNearby(700)
end
local fLastHitFilter = bHumaniserLaning and CanTakeLastHit or nil
-- Humaniser lane management (task 07): in-lane techniques run inside this Think(); also decided once at load.
local Lane = J.Humaniser.Lane
local bLaneLaning = Lane.OwnsLaning(bot)
-- Task 14 self-test: this bot times its last hits from the trainer's own start window.
local Trainer = J.Humaniser.Trainer
local bTrainerSelfTest = Trainer.IsSelfTestBot(bot)
-- Humaniser last-hit accuracy (task 10) only acts where OHA owns this Think(); Valve's C++ laning cannot be changed.
local LastHitSkill = J.Humaniser.LastHitSkill
local bOwnsThink = local_mode_laning_generic ~= nil or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) or bHumaniserLaning or bLaneLaning or bTrainerSelfTest
LastHitSkill.NoteLaningOwner(bot, bOwnsThink)

function GetDesire()
	PickOneAnnouncer()
	AnnounceMessages()

	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return BOT_MODE_DESIRE_NONE end
	local botLV = bot:GetLevel()
	local currentTime = DotaTime()

	botAttackRange = bot:GetAttackRange()
	nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	nEnemyCreeps = bot:GetNearbyLaneCreeps(800, true)
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(nInRangeEnemy)
	if local_mode_laning_generic then
		botAssignedLane = local_mode_laning_generic.GetBotTargetLane()
	else
		botAssignedLane = bot:GetAssignedLane()
	end
	attackDamage = bot:GetAttackDamage()
	if bot:GetItemSlotType(bot:FindItemSlot("item_quelling_blade")) == ITEM_SLOT_TYPE_MAIN then
		if bot:GetAttackRange() > 310 or bot:GetUnitName() == "npc_dota_hero_templar_assassin" then
			attackDamage = attackDamage + 4
		else
			attackDamage = attackDamage + 8
		end
	end

	if GetGameMode() == 23 then currentTime = currentTime * 1.65 end
	if currentTime < 0 then return BOT_ACTION_DESIRE_NONE end

	-- if DotaTime() > 20 and DotaTime() - skipLaningState.lastCheckTime < skipLaningState.checkGap then
	-- 	if skipLaningState.count > 6 then
	-- 		print('[WARN] Bot ' ..botName.. ' switching modes too often, now stop it for laning to avoid conflicts.')
	-- 		return 0
	-- 	end
	-- else
	-- 	skipLaningState.lastCheckTime = DotaTime()
	-- 	skipLaningState.count = 0
	-- end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		return BOT_MODE_DESIRE_NONE
	end

	-- if J.GetDistanceFromAncient( bot, true ) < 6900 then
	-- 	return BOT_MODE_DESIRE_NONE
	-- end

	if bot:WasRecentlyDamagedByAnyHero(5)
	and #J.Utils.GetLastSeenEnemyIdsNearLocation(bot:GetLocation(), 800) > 0 then
		local nLaneFrontLocation = GetLaneFrontLocation(GetTeam(), bot:GetAssignedLane(), 0)
		local nDistFromLane = GetUnitToLocationDistance(bot, nLaneFrontLocation)
		if not J.WeAreStronger(bot, 1200) or (nDistFromLane > 700 and J.GetHP(bot) < 0.7) then
			return BOT_MODE_DESIRE_NONE
		end
	end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	-- if J.ShouldGoFarmDuringLaning(bot) then
	-- 	return 0.2
	-- end

	if local_mode_laning_generic or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) then
		-- last hit
		if J.IsInLaningPhase() then
			local hitCreep, _ = GetBestLastHitCreep(nEnemyCreeps, fLastHitFilter)
			if J.IsValid(hitCreep) then
				if (fLastHitFilter or J.GetPosition(bot) <= 2 or not J.IsThereNonSelfCoreNearby(700)) -- this is for e.g lone druid bear as pos1-2 with core LD nearby to do last hit.
				and not Lane.CampJobActive(bot) -- a running pull (farm mode, 0.7) must not be cut by a last hit at the meet point
				then
					return 0.9
				end
			end
		end
	end
	if local_mode_laning_generic and local_mode_laning_generic.GetDesire ~= nil then return local_mode_laning_generic.GetDesire() end

	if GetGameMode() == GAMEMODE_1V1MID or GetGameMode() == GAMEMODE_MO then
		return 1
	end

	if currentTime <= 10 then return 0.268 end
	if currentTime <= 9 * 60 and botLV <= 7 then return 0.446 end
	if currentTime <= 12 * 60 and botLV <= 11 then return 0.369 end
	if botLV <= 14 and J.GetCoresAverageNetworth() < 7000 then return 0.2 end

	J.Utils.GameStates.passiveLaningTime = true
	return 0.01
end

-- Humaniser intent arbitration (task 09): claims and stickiness applied on top of the desire above.
local GetDesireRaw = GetDesire
function GetDesire() return J.Humaniser.Intent.Resolve(bot, BOT_MODE_LANING, GetDesireRaw()) end

function GetFurthestEnemyAttackRange(enemyList)
	local attackRange = 0
	for _, enemy in pairs(enemyList) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then
			local enemyAttackRange = enemy:GetAttackRange()
			if enemyAttackRange > attackRange then
				attackRange = enemyAttackRange
			end
		end
	end

	return attackRange
end

function GetBestLastHitCreep(hCreepList, fFilter)
	local dmgDelta = attackDamage * 0.7

	local moveToCreep = nil
	local bChoose = LastHitSkill.IsActiveFor(bot)
	local killable = {}
	for _, creep in pairs(hCreepList) do
		if J.IsValid(creep) and J.CanBeAttacked(creep) and (fFilter == nil or fFilter(creep)) then
			local nDelay = J.GetAttackProDelayTime(bot, creep)
			if LastHitSkill.WillKill(bot, creep, attackDamage, nDelay, false) then
				if not bChoose then return creep, false end
				table.insert(killable, creep)
			elseif LastHitSkill.WillKill(bot, creep, attackDamage + dmgDelta, nDelay, false) then
				moveToCreep = creep
			end
		end
	end
	if #killable > 0 then
		return LastHitSkill.Choose(bot, killable), false
	end
	if moveToCreep then
		return moveToCreep, true
	end

	return nil
end

function GetBestDenyCreep(hCreepList)
	for _, creep in pairs(hCreepList)
	do
		if J.IsValid(creep)
		and J.GetHP(creep) < 0.49
		and J.CanBeAttacked(creep)
		and LastHitSkill.WillKill(bot, creep, attackDamage, 0, true)
		then
			return creep
		end
	end

	return nil
end

-- Supports holding back for a human: one right-click on the nearest enemy laner every HarassInterval.
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

-- Laning Think() steps, each returning true when it issued an action. Kept separate so later humaniser work
-- (lane management) can add steps without rewriting Think().
local function LastHitThink()
	if bTrainerSelfTest then
		if Trainer.SelfTestHolding(bot) then return true end
		local creep = Trainer.SelfTestTarget(bot)
		if not J.IsValid(creep) then return false end
		bot:SetTarget(creep)
		bot:Action_AttackUnit(creep, true)
		return true
	end
	local hitCreep, moveToCreep = GetBestLastHitCreep(nEnemyCreeps, fLastHitFilter)
	if not J.IsValid(hitCreep) then return false end
	if not (fLastHitFilter or J.GetPosition(bot) <= 2 or not J.IsThereNonSelfCoreNearby(700)) then return false end
	if GetUnitToUnitDistance(bot, hitCreep) > botAttackRange
	or (moveToCreep and GetUnitToUnitDistance(bot, hitCreep) > botAttackRange * 0.8) then
		bot:Action_MoveToUnit(hitCreep)
	else
		bot:SetTarget(hitCreep)
		bot:Action_AttackUnit(hitCreep, true)
	end
	return true
end

local function DenyThink()
	if bTrainerSelfTest then return false end
	if bLaneLaning and not Lane.MayDeny(bot, nAllyCreeps) then return false end
	local denyCreep = (bLaneLaning and Lane.PickDeny(bot, nAllyCreeps)) or GetBestDenyCreep(nAllyCreeps)
	if not J.IsValid(denyCreep) then return false end
	bot:SetTarget(denyCreep)
	bot:Action_AttackUnit(denyCreep, true)
	return true
end

local function PositionThink()
	local fLaneFrontAmount = GetLaneFrontAmount(GetTeam(), botAssignedLane, false)
	local fLaneFrontAmount_enemy = GetLaneFrontAmount(GetOpposingTeam(), botAssignedLane, false)

	local nLongestAttackRange = math.max(botAttackRange, 250, nFurthestEnemyAttackRange)

	local target_loc = GetLaneFrontLocation(GetTeam(), botAssignedLane, -nLongestAttackRange)
	if fLaneFrontAmount_enemy < fLaneFrontAmount then
		target_loc = GetLaneFrontLocation(GetOpposingTeam(), botAssignedLane, -nLongestAttackRange)
	end

	if bLaneLaning then target_loc = Lane.AdjustPosition(bot, target_loc) end
	bot:Action_MoveToLocation(target_loc + RandomVector(50))
end

if bOwnsThink then
	function Think()
		-- A technique before the last hit could take a frame inside the self-test's start window and score a miss.
		if bLaneLaning and not bTrainerSelfTest and Lane.PreThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end
		-- With etiquette on, a last hit near a protected human is only allowed when the human will miss it,
		-- so taking it before a deny is intended.
		if LastHitThink() then return end
		if DenyThink() then return end
		if bLaneLaning and Lane.Think(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end

		if (bHumaniserLaning or bLaneLaning) and Lane.SupersedesHarass(bot) then
			if Lane.HarassThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy, bHumaniserLaning) then return end
		elseif bHumaniserLaning and HarassThink() then return end

		if local_mode_laning_generic then
			local_mode_laning_generic.Think()
		end

		PositionThink()
	end
end


function PickOneAnnouncer()
	if not hasPickedOneAnnouncer then
		for i, _ in pairs(GetTeamPlayers(GetTeam())) do
			local member = GetTeamMember(i)
			if member ~= nil and member.isAnnouncer then return end
		end
		bot.isAnnouncer = true
		hasPickedOneAnnouncer = true
	end
end

function AnnounceMessages()
	-- Only pre-game chatter
	if DotaTime() > 60 then return end

	local welcomeMessages = Localization.Get('welcome_msgs')
	local inTurbo         = J.IsModeTurbo()

	-- Staggered lines during negative DotaTime pre-game
	if ((inTurbo and DotaTime() > -50 + GetTeam() * 2) or (not inTurbo and DotaTime() > -75 + GetTeam() * 2))
	   and numberAnnouncePrinted < #welcomeMessages + 1
	   and bot.isAnnouncer
	   and DotaTime() < 0
	then
		if GameTime() - lastAnnouncePrintedTime >= announcementGapSeconds then
			local message      = welcomeMessages[numberAnnouncePrinted]
			local isFirstLine  = (numberAnnouncePrinted == 1)
			if message then
				-- Match original behavior: first line (or if no enemy bots) can be global
				bot:ActionImmediate_Chat(isFirstLine and (message .. Version.number) or message, enemyBots == 0 or isFirstLine)
			end
			numberAnnouncePrinted   = numberAnnouncePrinted + 1
			lastAnnouncePrintedTime = GameTime()
		end
	end

	-- Announce role during pre-game
	if GetGameMode() ~= GAMEMODE_1V1MID
	   and GetGameState() == GAME_STATE_PRE_GAME
	   and (bot.announcedRole == nil or bot.announcedRole ~= J.GetPosition(bot))
	then
		bot.announcedRole = J.GetPosition(bot)
		bot:ActionImmediate_Chat(Localization.Get('say_play_pos') .. J.GetPosition(bot), false)
	end

	-- Close position selection after horn if humans and bots mixed
	if GetGameMode() ~= GAMEMODE_1V1MID and not isChangePosMessageDone then
		if DotaTime() >= 0 and teamHumans > 0 and teamBots > 0 then
			bot:ActionImmediate_Chat(Localization.Get('pos_select_closed'), true)
			isChangePosMessageDone = true
		end
	end
end
