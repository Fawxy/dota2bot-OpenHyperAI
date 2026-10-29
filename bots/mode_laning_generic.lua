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

-- An allied core (not this bot) that can take this creep itself: judged from the creep, so a core 800 away but in
-- range of it keeps it, and one beside the bot but far from the creep does not.
local function CoreCanTake(creep)
	for _, ally in pairs(J.GetNearbyHeroes(bot, 1600, false, BOT_MODE_NONE) or {}) do
		if ally ~= bot and J.IsCore(ally) and AllyLastHit.CoreCanReach(ally, creep) then return true end
	end
	return false
end

local function CanTakeLastHit(creep)
	local bMay, sReason = AllyLastHit.MayLastHit(bot, creep)
	if not bMay then return false end
	if string.sub(sReason, 1, 5) == 'take:' then return true end
	return J.GetPosition(bot) <= 2 or not CoreCanTake(creep)
end
local fLastHitFilter = bHumaniserLaning and CanTakeLastHit or nil
-- Ours.LeaveCoreCreep (slice 3): a support leaves a creep an allied core can take. Valve's C++ laning cannot be filtered, so
-- the bot runs this file's Think() and our predicate replaces every other last-hit gate (AllyLastHit's included).
local Etiquette = J.Humaniser.Etiquette
local bEtiquette = Etiquette.Applies(bot)
if bEtiquette then fLastHitFilter = function(creep) return Etiquette.MayLastHit(bot, creep) end end
-- The humaniser's own changes to this Think() (the hold, reach judged from the creep) apply only where it owns the
-- laning; upstream's own cases keep upstream's behaviour with the humaniser off.
-- Humaniser lane management (task 07): in-lane techniques run inside this Think(); also decided once at load.
local Lane = J.Humaniser.Lane
local bLaneLaning = Lane.OwnsLaning(bot)
-- Task 14 self-test: this bot times its last hits from the trainer's own start window.
local Trainer = J.Humaniser.Trainer
local bTrainerSelfTest = Trainer.IsSelfTestBot(bot)
-- Humaniser last-hit accuracy (task 10) only acts where OHA owns this Think(); Valve's C++ laning cannot be changed.
local LastHitSkill = J.Humaniser.LastHitSkill
local bHumaniserOwned = bHumaniserLaning or bLaneLaning
-- A creep no allied core will take: judged from the creep where the humaniser owns laning, else upstream's 700 radius.
local function CoreLeaves(creep)
	if bHumaniserOwned then return not CoreCanTake(creep) end
	return not J.IsThereNonSelfCoreNearby(700)
end
-- Behaviour states (team slice 1): the `laning` state's SDK body can replace PositionThink() below.
local States = J.Humaniser.States
local bOwnsThink = local_mode_laning_generic ~= nil or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) or bHumaniserLaning or bLaneLaning or bTrainerSelfTest or States.MayOwn(bot) or bEtiquette
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

	-- Wherever this file's Think() runs the laning (upstream's cases and the humaniser's), a dying creep is laning's to take.
	if bOwnsThink then
		-- last hit
		if J.IsInLaningPhase() then
			local hitCreep, _ = GetBestLastHitCreep(nEnemyCreeps, fLastHitFilter)
			if J.IsValid(hitCreep) then
				if (fLastHitFilter or J.GetPosition(bot) <= 2 or CoreLeaves(hitCreep)) -- this is for e.g lone druid bear as pos1-2 with core LD nearby to do last hit.
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

local bHoldingForLastHit = false
local HOLD_MAX = 1.5
local holdCreep, holdSince = nil, 0
local function HoldingFor(creep)
	if holdCreep ~= creep then holdCreep, holdSince = creep, DotaTime() end
	return DotaTime() - holdSince < HOLD_MAX
end

-- The last-hit state the in-lane techniques wait for, gated as LastHitThink gates the hit: 'kill' for a killable
-- creep in attack range, 'soon' for one about to be killable or still out of range, nil when none is ours.
local function LastHitState()
	local hc, bMoveTo = GetBestLastHitCreep(nEnemyCreeps, fLastHitFilter)
	if not J.IsValid(hc) or not (fLastHitFilter or J.GetPosition(bot) <= 2 or CoreLeaves(hc)) then return nil end
	if bMoveTo or GetUnitToUnitDistance(bot, hc) > botAttackRange then return 'soon' end
	return 'kill'
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
	if not (fLastHitFilter or J.GetPosition(bot) <= 2 or CoreLeaves(hitCreep)) then return false end
	if GetUnitToUnitDistance(bot, hitCreep) > botAttackRange
	or (moveToCreep and GetUnitToUnitDistance(bot, hitCreep) > botAttackRange * 0.8) then
		bot:Action_MoveToUnit(hitCreep)
	elseif moveToCreep and bHumaniserOwned and HoldingFor(hitCreep) then
		-- In range of a creep that is not killable yet: swinging now lands early and leaves it for the enemy's deny.
		-- Wait for it (at most HOLD_MAX, for a creep nothing is hitting), letting a deny go first.
		bHoldingForLastHit = true
		return false
	else
		bot:SetTarget(hitCreep)
		bot:Action_AttackUnit(hitCreep, true)
		LastHitSkill.NoteAttempt(bot, hitCreep)
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
	LastHitSkill.NoteAttempt(bot, denyCreep)
	return true
end

local function PositionTarget()
	if botAssignedLane == nil then return nil end
	local fLaneFrontAmount = GetLaneFrontAmount(GetTeam(), botAssignedLane, false)
	local fLaneFrontAmount_enemy = GetLaneFrontAmount(GetOpposingTeam(), botAssignedLane, false)

	local nLongestAttackRange = math.max(botAttackRange, 250, nFurthestEnemyAttackRange)

	local target_loc = GetLaneFrontLocation(GetTeam(), botAssignedLane, -nLongestAttackRange)
	if fLaneFrontAmount_enemy < fLaneFrontAmount then
		target_loc = GetLaneFrontLocation(GetOpposingTeam(), botAssignedLane, -nLongestAttackRange)
	end

	if bLaneLaning then target_loc = Lane.AdjustPosition(bot, target_loc) end
	return target_loc
end

local function PositionThink()
	local target_loc = PositionTarget()
	if target_loc ~= nil then bot:Action_MoveToLocation(target_loc + RandomVector(50)) end
end

if bOwnsThink then
	States.SetLaneSpot(bot, PositionTarget)
	function Think()
		-- The SDK body's last-hit or deny swing in progress must not be overridden by the steps below (slice 4).
		if States.BodyBusy(bot) and States.Step(bot, BOT_MODE_LANING) then return end
		-- Ours.LeaveCoreCreep: a swing or auto-attack on a creep a core can take is cancelled by the move.
		if bEtiquette and Etiquette.LeavesTarget(bot) then PositionThink() return end
		-- A technique before the last hit could take a frame inside the self-test's start window and score a miss.
		bHoldingForLastHit = false
		if bLaneLaning and not bTrainerSelfTest then
			-- Aggro draws wait for a creep that is dying or about to be.
			local sLastHit = LastHitState()
			if Lane.PreThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy, sLastHit) then return end
		end
		-- With etiquette on, a last hit near a protected human is only allowed when the human will miss it,
		-- so taking it before a deny is intended. Where the laning state's SDK body owns last hits (team
		-- slice 4), it takes them and the denies itself in its Step below.
		if not States.BodyLastHits(bot) then
			if LastHitThink() then return end
			if DenyThink() then return end
			if bHoldingForLastHit then
				bot:Action_MoveToLocation(bot:GetLocation())
				return
			end
		end
		if bLaneLaning and Lane.Think(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end

		if (bHumaniserLaning or bLaneLaning) and Lane.SupersedesHarass(bot) then
			if Lane.HarassThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy, bHumaniserLaning) then return end
		elseif bHumaniserLaning and HarassThink() then return end

		if local_mode_laning_generic then
			local_mode_laning_generic.Think()
		end

		if not States.Step(bot, BOT_MODE_LANING) then PositionThink() end
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
-- H.1 probe (slice 1): errors escaping these entry points print ev=lua_error where=oha.<file>.<fn>, then re-raise.
do local E = require(GetScriptDirectory()..'/FunLib/humaniser/telemetry').Entry; GetDesire = E('mode_laning.GetDesire', GetDesire) end
