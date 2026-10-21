dofile(HARNESS_DIR .. "/dota_stubs.lua")

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:ActionImmediate_Chat(line) self.said = self.said or {} table.insert(self.said, line) end
function UnitMeta:GetMostRecentPing() return { time = 0, location = Vector(0, 0), normal_ping = true } end
function UnitMeta:FindItemSlot() return -1 end
function UnitMeta:GetAttackTarget() return nil end
function UnitMeta:GetLastHits() return 0 end
function UnitMeta:GetDenies() return 0 end
function UnitMeta:GetAnimActivity() return 1500 end
function UnitMeta:IsStunned() return false end
function UnitMeta:IsHexed() return false end
function UnitMeta:WasRecentlyDamagedByAnyHero() return false end
function GetUnitList() return {} end

local USAGE = "usage: !trainer on|off|stats|reset|bar on|off|chat off|misses|all|denies on|off"

local function setup(cfg, bots)
	ResetWorld()
	local H = FreshHumaniser(cfg)
	local calls = { delay = 0, laning = 0 }
	H.Trainer.SetHelpers({
		GetAttackProDelayTime = function() calls.delay = calls.delay + 1 return 0.4 end,
		IsInLaningPhase = function() calls.laning = calls.laning + 1 return true end,
	})
	local human = MakeUnit({ pid = 0, bot = false })
	local units = {}
	for _, pid in ipairs(bots or { 1, 3 }) do table.insert(units, MakeUnit({ pid = pid })) end
	return H, human, units, calls
end

local function say(H, text)
	T = T + 0.5
	H.Commands.HandleMessage(2, { pid = 0, text = text, teamOnly = true, time = T })
end

local function ticks(H, units, n)
	for _ = 1, n do
		T = T + 0.1
		for _, u in ipairs(units) do H.Tick(u) end
	end
end

local function capturePrint(fn)
	local lines, old = {}, print
	print = function(s) table.insert(lines, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return lines
end

local function trainerLines(lines)
	local r = {}
	for _, l in ipairs(lines) do if l:find("[H:trainer]", 1, true) then table.insert(r, l) end end
	return r
end

do
	local H = setup({ Enable = true })
	local p = H.Commands.Parse("!trainer bar on", 2)
	check("parse trainer with args", p and p.name == "trainer" and p.args[1] == "bar" and p.args[2] == "on" and p.onlyPIDs == nil)
end

do
	local H = setup({ Enable = true })
	local lion = MakeUnit({ pid = 5 })
	lion.GetUnitName = function() return "npc_dota_hero_lion" end
	check("trainer cannot take a hero selector", H.Commands.Parse("!lion trainer", 2) == nil)
	check("trainer cannot take a slot selector", H.Commands.Parse("!2 trainer on", 2) == nil)
end

do
	local cfg = { Enable = true, Debug = true, Trainer = { LastHit = { Enable = false } } }
	local H, _, bots, calls = setup(cfg)
	local printed = capturePrint(function()
		say(H, "!trainer on")
		ticks(H, bots, 20)
	end)
	check("kill switch: no helper calls", calls.delay == 0 and calls.laning == 0)
	check("kill switch: no [H:trainer] logs", #trainerLines(printed) == 0, #trainerLines(printed))
	check("kill switch: no chat", bots[1].said == nil and bots[2].said == nil)

	-- Same script with the trainer enabled does reply, so the silence above comes from the switch.
	cfg.Trainer.LastHit.Enable = true
	local H2, _, bots2 = setup(cfg)
	capturePrint(function()
		say(H2, "!trainer on")
		ticks(H2, bots2, 20)
	end)
	check("control: enabled trainer answers", bots2[1].said ~= nil and #bots2[1].said > 0)
end

do
	local H, _, bots = setup({ Enable = true })
	say(H, "!trainer")
	ticks(H, bots, 20)
	check("status line from the lowest-PID bot", bots[1].said and bots[1].said[1] == "trainer off - bar on - chat off - denies on", bots[1].said and bots[1].said[1])
	check("status reply sent once", bots[1].said and #bots[1].said == 1)
	check("other bot stays silent", bots[2].said == nil)
end

do
	local H, _, bots = setup({ Enable = true })
	say(H, "!trainer banana")
	ticks(H, bots, 5)
	check("unknown subcommand prints usage", bots[1].said and bots[1].said[1] == USAGE, bots[1].said and bots[1].said[1])
end

do
	local H, _, bots = setup({ Enable = true })
	say(H, "!trainer on")
	say(H, "!trainer bar off")
	say(H, "!trainer chat misses")
	say(H, "!trainer denies off")
	say(H, "!trainer")
	ticks(H, bots, 12)
	check("replies are rate limited to one per 0.5s", #bots[1].said == 3, #bots[1].said)
	ticks(H, bots, 30)
	local said = bots[1].said
	check("subcommands change the status line", #said == 5 and said[5] == "trainer on - bar off - chat misses - denies off", said[#said])
	say(H, "!trainer chat sometimes")
	ticks(H, bots, 10)
	said = bots[1].said
	check("bad argument prints usage", said[#said] == USAGE, said[#said])
end

do
	local H, _, bots = setup({ Enable = true, Trainer = { LastHit = { Chat = "all", Checkpoints = { 100 } } } })
	say(H, "!trainer")
	ticks(H, bots, 5)
	check("config seeds the runtime state", bots[1].said[1] == "trainer off - bar on - chat all - denies on", bots[1].said[1])
	check("array settings are replaced, not merged", #require("bots/FunLib/humaniser/trainer/settings").Get().Checkpoints == 1)
end

do
	local H, _, bots = setup({ Enable = true })
	say(H, "!trainer spike")
	ticks(H, bots, 5)
	check("spike needs Debug", bots[1].said and bots[1].said[1] == USAGE)
end

finish()
