-- aba_role.GetPosition's unmatched-bot fallback, under Dota's bot VM, which has no debug library.
dofile(HARNESS_DIR .. "/lane_world.lua")
debug = nil
function GetGameMode() return 22 end
function GetSelectedHeroName() return "" end

local R = require("bots/FunLib/aba_role")
CURRENT_TEAM = 2
-- A same-team bot whose player ID is missing from GetTeamPlayers can't be matched to a slot.
local bot = MakeUnit({ pid = 7, team = 2, bot = true })
UNITS[2] = {}

local ok, role = pcall(R.GetPosition, bot)
check("unmatched bot gets a role without the debug library", ok and type(role) == "number", tostring(role))
check("the fallback role is cached on the bot", bot.assignedRole == role, tostring(bot.assignedRole))
finish()
