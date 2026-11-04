local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local Utils = require( GetScriptDirectory()..'/FunLib/utils')

local local_mode_attack_generic
if bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end

if Utils.BuggyHeroesDueToValveTooLazy[botName] then
	local_mode_attack_generic = dofile( GetScriptDirectory().."/FunLib/override_generic/mode_attack_generic" )
end

-- Core in lane (Ours.CoreTrade) and Support in lane (Ours.SupportHarass), OWNERSHIP H13: our attack desire and Think while the
-- laner lanes (core trades, support harass), OHA's Lua port outside lane. Decided once at load: defining GetDesire removes Valve's attack desire for the whole game, so the port covers the rest.
local CoreTrade = require( GetScriptDirectory()..'/FunLib/humaniser/index' ).CoreTrade
if CoreTrade.Owns(bot) then
	local Humaniser = require( GetScriptDirectory()..'/FunLib/humaniser/index' )
	local port = local_mode_attack_generic or dofile( GetScriptDirectory().."/FunLib/override_generic/mode_attack_generic" )
	local function Desire()
		local d = CoreTrade.Desire(bot)
		if d ~= nil then return d end
		return port.GetDesire()
	end
	function GetDesire() return Humaniser.Intent.Resolve(bot, BOT_MODE_ATTACK, Desire()) end
	function Think()
		if CoreTrade.OwnsFrame(bot) then return CoreTrade.Think(bot) end
		return port.Think()
	end
	function OnStart() return port.OnStart() end
	function OnEnd()
		CoreTrade.OnEnd(bot)
		return port.OnEnd()
	end
elseif local_mode_attack_generic ~= nil then
	-- Humaniser intent arbitration (task 09). Other heroes' attack desire is Valve's C++ and cannot be resolved.
	local Humaniser = require( GetScriptDirectory()..'/FunLib/humaniser/index' )
	function GetDesire() return Humaniser.Intent.Resolve(bot, BOT_MODE_ATTACK, local_mode_attack_generic.GetDesire()) end
	function Think() return local_mode_attack_generic.Think() end
	function OnStart() return local_mode_attack_generic.OnStart() end
	function OnEnd() return local_mode_attack_generic.OnEnd() end
end
-- Valve's C++ attack mode runs where neither branch above defined GetDesire.
if GetDesire ~= nil then
	do local C = require(GetScriptDirectory()..'/FunLib/humaniser/index').Chooser; GetDesire = C.Gate(GetBot(), 'attack', GetDesire) end
end