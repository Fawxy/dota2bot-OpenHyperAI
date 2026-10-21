dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode, Lane = dota.BotMode, dota.Lane
local MARKER = "modifier_special_bonus_cooldown_reduction"

local function say(pid, text, teamOnly)
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = teamOnly ~= false }) end
end

-- Difficulty: FretBots off uses Valve difficulty only
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	local easy = MakeUnit({ pid = 1, difficulty = DIFFICULTY_EASY })
	local unfair = MakeUnit({ pid = 2, difficulty = DIFFICULTY_UNFAIR })
	check("fret inactive without marker", H.Difficulty.GetFret(easy).active == false)
	check("valve easy -> 0.25", near(H.Difficulty.GetSkill(easy), 0.25), H.Difficulty.GetSkill(easy))
	check("valve unfair -> 1.0", near(H.Difficulty.GetSkill(unfair), 1.0), H.Difficulty.GetSkill(unfair))
end

-- Difficulty: FretBots on, vote mirrored from pre-game chat, enemy team (no humans)
for _, case in ipairs({ { vote = "1", expect = 0.30 }, { vote = "9", expect = 0.70 } }) do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	local human = MakeUnit({ pid = 0, team = 2, bot = false })
	local enemy = MakeUnit({ pid = 5, team = 3, difficulty = DIFFICULTY_MEDIUM, modifiers = { [MARKER] = 0 } })
	GAME_STATE = GAME_STATE_PRE_GAME
	H.Tick(enemy)
	say(0, case.vote, false)
	local fret = H.Difficulty.GetFret(enemy)
	check("vote " .. case.vote .. " mirrored", fret.active and fret.source == "chat" and near(fret.level, tonumber(case.vote)), fret.source)
	check("vote " .. case.vote .. " enemy skill", near(H.Difficulty.GetSkill(enemy), case.expect), H.Difficulty.GetSkill(enemy))
end

-- Difficulty: allies of humans are scaled by FretBots allyScale (default 0.5); a second vote by the same player is ignored
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	MakeUnit({ pid = 0, team = 2, bot = false })
	local ally = MakeUnit({ pid = 1, team = 2, difficulty = DIFFICULTY_MEDIUM, modifiers = { [MARKER] = 0 } })
	GAME_STATE = GAME_STATE_PRE_GAME
	H.Tick(ally)
	say(0, "9")
	say(0, "0")
	check("ally skill scaled by allyScale", near(H.Difficulty.GetSkill(ally), 0.25 + 0.5 * 0.9 * 0.5), H.Difficulty.GetSkill(ally))
end

-- Difficulty: marker from a level-10+ talent must not switch FretBots on
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	local u = MakeUnit({ pid = 1, level = 12, modifiers = { [MARKER] = 0 } })
	check("late talent marker ignored", H.Difficulty.GetFret(u).active == false)
end

-- Difficulty: bridge modifier decoding (difficulty 7.5, allyScale 0.3 -> 75 + 30*1000)
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, FretBridge = { BridgeModifier = "modifier_x" } })
	local u = MakeUnit({ pid = 1, modifiers = { modifier_x = 30075 } })
	local fret = H.Difficulty.GetFret(u)
	check("bridge decodes level", near(fret.level, 7.5), fret.level)
	check("bridge decodes ally scale", near(fret.allyScale, 0.3), fret.allyScale)
end

-- SkillOverride beats everything
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, SkillOverride = 0.9 })
	local u = MakeUnit({ pid = 1, difficulty = DIFFICULTY_PASSIVE })
	check("override wins", near(H.Difficulty.GetSkill(u), 0.9))
end

-- Profile: higher skill reacts faster, react delay never below MinReact even with jitter at minimum
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	local slow = MakeUnit({ pid = 1, difficulty = DIFFICULTY_PASSIVE })
	local fast = MakeUnit({ pid = 2, difficulty = DIFFICULTY_UNFAIR })
	check("skill speeds reaction", H.Profile.Get(fast).reactBase < H.Profile.Get(slow).reactBase)
	RANDOM_FRACTION = 0
	local d = H.Profile.SampleDelay(fast, "react")
	RANDOM_FRACTION = nil
	check("react floor", d >= 0.17 - 1e-9, d)
	check("deference: easy ally defers fully", near(H.Profile.Get(slow).deference, 1))
end

-- Orders: nearest-N ranking with deterministic tie-break, alsoWithin, dedupe and replacement
local function gatherSpec(key, extra)
	local spec = { type = "GATHER", sourceKey = key, issuerPID = 0, location = Vector(0, 0), duration = 8, maxResponders = 2 }
	for k, v in pairs(extra or {}) do spec[k] = v end
	return spec
end
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	MakeUnit({ pid = 0, bot = false, loc = Vector(0, 0) })
	MakeUnit({ pid = 4, loc = Vector(300, 0) })
	MakeUnit({ pid = 3, loc = Vector(0, 300) })
	MakeUnit({ pid = 1, loc = Vector(100, 0) })
	MakeUnit({ pid = 2, loc = Vector(1500, 0) })
	local o = H.Orders.Post(2, gatherSpec("g1"))
	check("humans never respond", o.responders[1] ~= 0)
	check("nearest first", o.responders[1] == 1, o.responders[1])
	check("tie broken by pid", o.responders[2] == 3 and #o.responders == 2, table.concat(o.responders, ","))
	check("same source ignored", H.Orders.Post(2, gatherSpec("g1")) == nil and #H.Orders.GetActive(2) == 1)
	local o2 = H.Orders.Post(2, gatherSpec("g2", { alsoWithin = 1600 }))
	check("same type replaces", #H.Orders.GetActive(2) == 1 and H.Orders.GetActive(2)[1].id == o2.id)
	check("alsoWithin adds extra", #o2.responders == 4, #o2.responders)
	check("expiry", (function() T = 9 return #H.Orders.GetActive(2) == 0 end)())
end

-- Orders: two independent module instances (non-shared modules) agree on responders for the same input
do
	ResetWorld()
	MakeUnit({ pid = 0, bot = false })
	for pid = 1, 4 do MakeUnit({ pid = pid, loc = Vector(pid * 250, 0) }) end
	local A = FreshHumaniser({ Enable = true })
	local oa = A.Orders.Post(2, gatherSpec("ping:0:12.0"))
	local B = FreshHumaniser({ Enable = true })
	local ob = B.Orders.Post(2, gatherSpec("ping:0:12.0"))
	check("instances agree", table.concat(oa.responders, ",") == table.concat(ob.responders, ","))
end

-- Orders: read delay, decline, single acknowledgement
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, bot:GetPlayerID() .. ":" .. key) end)
	MakeUnit({ pid = 0, bot = false })
	local dead = MakeUnit({ pid = 1, loc = Vector(100, 0), alive = false })
	local b2 = MakeUnit({ pid = 2, loc = Vector(200, 0) })
	local b3 = MakeUnit({ pid = 3, loc = Vector(300, 0) })
	local o = H.Orders.Post(2, gatherSpec("g", { maxResponders = 3 }))
	check("not accepted before reading", H.Orders.TryAccept(b2, o) == false)
	T = 5
	check("dead declines", H.Orders.TryAccept(dead, o) == false)
	check("accepted after reading", H.Orders.TryAccept(b2, o) == true and H.Orders.TryAccept(b3, o) == true)
	H.Orders.TryAccept(b2, o) H.Orders.TryAccept(b3, o) H.Orders.TryAccept(dead, o)
	check("one decline line, one ack from next in line", table.concat(said, " ") == "1:say_order_decline_dead 2:say_order_ack_gather", table.concat(said, " "))
end

-- Orders: DesireFloor maps order types to the right modes and lanes
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true })
	MakeUnit({ pid = 0, bot = false })
	local b = MakeUnit({ pid = 1, loc = Vector(100, 0) })
	H.Orders.Post(2, { type = "DEFEND", sourceKey = "d", issuerPID = 0, location = Vector(0, 0), lane = Lane.Mid, duration = 20, maxResponders = 1 })
	T = 5
	check("defend floor on matching lane", near(H.Orders.DesireFloor(b, BotMode.DefendTowerMid, Lane.Mid), 0.85))
	check("no floor on other lane", H.Orders.DesireFloor(b, BotMode.DefendTowerTop, Lane.Top) == 0)
	check("no floor for unrelated mode", H.Orders.DesireFloor(b, BotMode.Assemble) == 0)
	H.Orders.Post(2, { type = "RELEASE", sourceKey = "r", issuerPID = 0, duration = 0, maxResponders = 0 })
	check("release cancels", #H.Orders.GetActive(2) == 0)
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

-- Kill switch: disabled humaniser installs nothing and never raises desire
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = false })
	local b = MakeUnit({ pid = 1 })
	H.Tick(b)
	check("disabled: no chat callback", #CHAT_CALLBACKS == 0)
	H.Orders.Post(2, gatherSpec("x"))
	T = 5
	check("disabled: no desire floor", H.Orders.DesireFloor(b, BotMode.Assemble) == 0)
end

finish()
