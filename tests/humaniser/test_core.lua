dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode, Lane = dota.BotMode, dota.Lane
local MARKER = "modifier_special_bonus_cooldown_reduction"

local function say(pid, text, teamOnly)
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = teamOnly ~= false }) end
end

-- Chat hub: one callback, duplicate deliveries collapsed, failing subscriber isolated
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	local u = MakeUnit({ pid = 1 })
	H.Tick(u) H.Tick(u)
	check("single install", #CHAT_CALLBACKS == 1, #CHAT_CALLBACKS)
	local got = 0
	H.Chat.Subscribe("boom", function() error("x") end)
	H.Chat.Subscribe("count", function() got = got + 1 end)
	local cb = CHAT_CALLBACKS[1]
	cb({ player_id = 0, string = "hi", team_only = true })
	cb({ player_id = 0, string = "hi", team_only = true })
	check("dedupe + isolation", got == 1, got)
	T = 1
	cb({ player_id = 0, string = "hi", team_only = true })
	check("repeat after window delivered", got == 2, got)
end

-- Kill switch: disabled, nothing is installed
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = false })
	local b = MakeUnit({ pid = 1 })
	H.Tick(b)
	check("disabled: no chat callback", #CHAT_CALLBACKS == 0)
end

finish()
