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

if local_mode_attack_generic ~= nil then
	function GetDesire() return local_mode_attack_generic.GetDesire() end
	function Think() return local_mode_attack_generic.Think() end
	function OnStart() return local_mode_attack_generic.OnStart() end
	function OnEnd() return local_mode_attack_generic.OnEnd() end
end
-- Valve's C++ attack mode runs where the branch above did not define GetDesire.
if GetDesire ~= nil then
	do local C = require(GetScriptDirectory()..'/FunLib/humaniser/index').Chooser; GetDesire = C.Gate(GetBot(), 'attack', GetDesire) end
	do local E = require(GetScriptDirectory()..'/FunLib/humaniser/telemetry').Entry; GetDesire, Think = E('mode_attack.GetDesire', GetDesire), E('mode_attack.Think', Think) end
end