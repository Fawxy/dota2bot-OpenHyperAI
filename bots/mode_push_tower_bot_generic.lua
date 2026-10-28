local Push = require( GetScriptDirectory()..'/FunLib/aba_push')
local bot = GetBot()
local botName = bot:GetUnitName()
if bot == nil or bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
if bot.PushLaneDesire == nil then bot.PushLaneDesire = {0, 0, 0} end

function GetDesire()
    bot.PushLaneDesire[LANE_BOT] = Push.GetPushDesire(bot, LANE_BOT)
    return bot.PushLaneDesire[LANE_BOT]
end
function Think() Push.PushThink(bot, LANE_BOT) end
-- H.1 probe (slice 1): errors escaping these entry points print ev=lua_error where=oha.<file>.<fn>, then re-raise.
do local E = require(GetScriptDirectory()..'/FunLib/humaniser/telemetry').Entry; GetDesire, Think = E('mode_push_tower_bot.GetDesire', GetDesire), E('mode_push_tower_bot.Think', Think) end
