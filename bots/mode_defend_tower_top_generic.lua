local Defend = require( GetScriptDirectory()..'/FunLib/aba_defend')

local bot = GetBot()
local botName = bot:GetUnitName()

if bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end

function GetDesire() return Defend.GetDefendDesire(bot, LANE_TOP) end
function Think() Defend.DefendThink(bot, LANE_TOP) end
-- H.1 probe (slice 1): errors escaping these entry points print ev=lua_error where=oha.<file>.<fn>, then re-raise.
do local E = require(GetScriptDirectory()..'/FunLib/humaniser/telemetry').Entry; GetDesire, Think = E('mode_defend_tower_top.GetDesire', GetDesire), E('mode_defend_tower_top.Think', Think) end
