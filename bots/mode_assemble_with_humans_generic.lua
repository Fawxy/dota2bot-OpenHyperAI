local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

function GetDesire()
	return BOT_MODE_DESIRE_NONE
end
-- H.1 probe (slice 1): errors escaping these entry points print ev=lua_error where=oha.<file>.<fn>, then re-raise.
do local E = require(GetScriptDirectory()..'/FunLib/humaniser/telemetry').Entry; GetDesire = E('mode_assemble_with_humans.GetDesire', GetDesire) end
