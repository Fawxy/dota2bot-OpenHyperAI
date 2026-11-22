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
local Lane = J.Humaniser.Lane
-- Task 14 self-test: this bot times its last hits from the trainer's own start window.
local Trainer = J.Humaniser.Trainer
local bTrainerSelfTest = Trainer.IsSelfTestBot(bot)
-- Humaniser last-hit accuracy (task 10) only acts where OHA owns this Think(); Valve's C++ laning cannot be changed.
local LastHitSkill = J.Humaniser.LastHitSkill
local bHumaniserOwned = bHumaniserLaning
-- A creep no allied core will take: judged from the creep where the humaniser owns laning, else upstream's 700 radius.
local function CoreLeaves(creep)
	if bHumaniserOwned then return not CoreCanTake(creep) end
	return not J.IsThereNonSelfCoreNearby(700)
end
-- Behaviour states (team slice 1): the `laning` state's SDK body can replace PositionThink() below.
local States = J.Humaniser.States
local bOwnsThink = local_mode_laning_generic ~= nil or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) or bHumaniserLaning or bTrainerSelfTest or States.MayOwn(bot) or bEtiquette
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

	-- A lane-only drill hero (humaniser/drill.ts): the bot stays in lane through the laning phase and does nothing but hold,
	-- last-hit and deny (Think below). Above every other mode, as a drill's bench in mode_farm_generic.
	-- Our retreat (slice retreat) takes a lane-only hero while its episode runs: the chase drill's cast retreats live.
	if bOwnsThink and J.Humaniser.Overrides.LaneOnly(bot) and J.IsInLaningPhase() and not J.Humaniser.Retreat.Running(bot) then return BOT_MODE_DESIRE_ABSOLUTE * 1.2 end

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
				and not J.Humaniser.Trade.LastHitYields(bot) -- nor a retreat, kill or join our laner is already in (Ours.Trade)
				and not require(GetScriptDirectory()..'/FunLib/humaniser/ours').On('NoLastHitLift') -- diagnostic hook: the lift off
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

local bHoldingForLastHit = false
local HOLD_MAX = 1.5
local holdCreep, holdSince = nil, 0
local function HoldingFor(creep)
	if holdCreep ~= creep then holdCreep, holdSince = creep, DotaTime() end
	return DotaTime() - holdSince < HOLD_MAX
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
	local denyCreep = GetBestDenyCreep(nAllyCreeps)
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

	return target_loc
end

local function PositionThink()
	local target_loc = PositionTarget()
	if target_loc ~= nil then bot:Action_MoveToLocation(target_loc + RandomVector(50)) end
end

-- Telemetry only (ev=snap step=): the lane table returns the name of the row that acted, which no decision reads.
local Telemetry = J.Humaniser.Telemetry
Telemetry.NoteLaneThink(bot, bOwnsThink)

if bOwnsThink then
	States.SetLaneSpot(bot, PositionTarget)
	-- The steps of the lane table (states/lane_table) that are OHA's own; the table decides their order against ours.
	local laneCtx = {
		etiquette = function()
			-- Ours.LeaveCoreCreep: a swing or auto-attack on a creep a core can take is cancelled by the move.
			if bEtiquette and Etiquette.LeavesTarget(bot) and not States.SupportOwnsAttack(bot) then PositionThink() return true end
			return false
		end,
		ohaLastHit = LastHitThink,
		ohaDeny = DenyThink,
		ohaHold = function()
			if not bHoldingForLastHit then return false end
			bot:Action_MoveToLocation(bot:GetLocation())
			return true
		end,
		ohaLocal = function()
			if local_mode_laning_generic then local_mode_laning_generic.Think() end
			return false
		end,
		ohaPosition = function() PositionThink() return true end,
	}
	function Think()
		-- Set by LastHitThink on the frame it runs, so a frame that skips it cannot hold on an earlier frame's wait.
		bHoldingForLastHit = false
		Telemetry.NoteLaneStep(bot, States.LaneStep(bot, laneCtx))
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
do local C = require(GetScriptDirectory()..'/FunLib/humaniser/index').Chooser; GetDesire = C.Gate(GetBot(), 'laning', GetDesire) end
do local E = require(GetScriptDirectory()..'/FunLib/humaniser/telemetry').Entry; GetDesire = E('mode_laning.GetDesire', GetDesire); if Think then Think = E('mode_laning.Think', Think) end end
