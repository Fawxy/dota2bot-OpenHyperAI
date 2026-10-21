local bot = GetBot()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not string.find(bot:GetUnitName(), "hero") or bot:IsIllusion() then return end

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )

local PING_RECENCY = 8        -- respond to pings within this many seconds
local ASSEMBLE_DURATION = 5    -- stay in assemble mode for this long after ping
local ASSEMBLE_DESIRE = 0.85   -- desire value when assembling
local ARRIVE_RADIUS = 500      -- close enough to ping location
local MAX_RESPOND_DIST = 3200  -- only respond if within this distance

local assembleLoc = nil
local assembleExpireTime = 0

-- Humaniser Orders executor (GATHER / ATTACK / SMOKE / BACK). Takes precedence over the legacy ping path below.
local ATTACK_HANDOFF_RANGE = 900   -- once this close to an ATTACK target, let OHA's fight logic take over
local activeOrder = nil
local orderArrived = {}            -- order id -> true once this bot reached a GATHER/SMOKE point

local function GetOrderDesire()
	activeOrder = nil
	if not J.Humaniser.IsEnabled() then return nil end
	local order = J.Humaniser.Orders.GetFor(bot)
	if order == nil then return nil end
	if order.type ~= 'GATHER' and order.type ~= 'ATTACK' and order.type ~= 'SMOKE' and order.type ~= 'BACK' then return nil end

	local loc = J.Humaniser.Orders.OrderLocation(order)
	if loc == nil then return nil end
	local dist = GetUnitToLocationDistance(bot, loc)

	if order.type == 'ATTACK' then
		if order.target ~= nil and J.IsValidHero(order.target) and order.target:CanBeSeen() and dist <= ATTACK_HANDOFF_RANGE then
			return nil
		end
	elseif orderArrived[order.id] or dist <= ARRIVE_RADIUS then
		-- GATHER/SMOKE/BACK: hold near the point until the order expires, but don't fight the other modes for it.
		orderArrived[order.id] = true
		if dist <= ARRIVE_RADIUS * 2 then return nil end
	end

	activeOrder = order
	return J.Humaniser.Orders.DesireFloor(bot, BOT_MODE_ASSEMBLE)
end

function GetDesire()
	if not bot:IsAlive() then return BOT_MODE_DESIRE_NONE end

	local orderDesire = GetOrderDesire()
	if orderDesire ~= nil and orderDesire > 0 then return orderDesire end

	-- Check for recent human normal pings (not danger pings); the humaniser ping interpreter replaces this.
	local human, ping = nil, nil
	if not J.Humaniser.Pings.IsActive() then human, ping = J.GetHumanPing() end
	if human ~= nil and ping ~= nil
	and ping.normal_ping
	and ping.time ~= 0
	and GameTime() - ping.time < PING_RECENCY
	then
		local dist = GetUnitToLocationDistance(bot, ping.location)
		-- Only respond if we're not already very close and not too far away
		if dist > ARRIVE_RADIUS and dist < MAX_RESPOND_DIST then
			assembleLoc = ping.location
			assembleExpireTime = GameTime() + ASSEMBLE_DURATION
			J.ModeAnnounce(bot, 'say_assemble', ASSEMBLE_DURATION)
			return ASSEMBLE_DESIRE
		end
	end

	-- Continue moving to assembly point if still active
	if assembleLoc ~= nil and GameTime() < assembleExpireTime then
		local dist = GetUnitToLocationDistance(bot, assembleLoc)
		if dist <= ARRIVE_RADIUS then
			assembleLoc = nil
			return BOT_MODE_DESIRE_NONE
		end
		return ASSEMBLE_DESIRE
	end

	assembleLoc = nil
	return BOT_MODE_DESIRE_NONE
end

function OnEnd()
	assembleLoc = nil
	assembleExpireTime = 0
	activeOrder = nil
end

function Think()
	if J.CanNotUseAction(bot) then return end

	if activeOrder ~= nil then
		local loc = J.Humaniser.Orders.OrderLocation(activeOrder)
		if loc == nil then return end
		if activeOrder.type == 'ATTACK' then
			bot:Action_AttackMove(loc)
		else
			bot:Action_MoveToLocation(loc)
		end
		return
	end

	if assembleLoc == nil then return end

	local dist = GetUnitToLocationDistance(bot, assembleLoc)
	if dist <= ARRIVE_RADIUS then
		assembleLoc = nil
		return
	end

	bot:Action_MoveToLocation(assembleLoc)
end
