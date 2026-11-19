-- Sustain step 3 (design 2026-11-19-sustain-design.md): sustain_act.ts carries Decide's answer out for a held laner. Gather and
-- Decide are replaced on their module tables, so these checks are the executor's own: who it carries, which order each answer
-- gives and from where, when a walk may start, how an attempt ends (ev=sustain), and OHA's item gate.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
local lines = {}
H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
local A = require("bots/FunLib/humaniser/sustain_act")
local G = require("bots/FunLib/humaniser/sustain_gather")
local S = require("bots/FunLib/humaniser/sustain")
local Phase = require("bots/FunLib/humaniser/transitions/phase")
local Drill = require("bots/FunLib/humaniser/drill")
local Overrides = require("bots/FunLib/humaniser/overrides")
local CampJobs = require("bots/FunLib/humaniser/camp_jobs")
local BotMode = require("bots/ts_libs/dota/index").BotMode

local world = { held = true, job = false }
Phase.LaningHeld = function() return world.held end
Drill.Held = function() return false end
Drill.RigHoldsCasts = function() return nil end
Overrides.LaneOnly = function() return false end
CampJobs.Active = function() return world.job end
BOT_ACTION_TYPE_USE_ABILITY = 6

local INPUTS = { hp = 300, mp = 100, items = {}, tree = { walk = 0, safe = true }, safeSpot = { x = -500, y = 0, walk = 2 } }
local answer = { kind = "none", reason = "fine" }
G.Gather = function(_, run) INPUTS.run = run return INPUTS end
G.Cut = function() end
G.NoteCourier = function() end
G.TreeOf = function() return { id = 7, loc = Vector(150, 0) } end
S.Decide = function(i)
	if i.run ~= nil and world.running ~= nil then return world.running end
	return answer
end

local function itemOf(name, charges)
	return { name = name, charges = charges, GetName = function(self) return self.name end, GetCurrentCharges = function(self) return self.charges end,
		IsFullyCastable = function() return true end, GetCastRange = function() return 165 end }
end
local bot = MakeUnit({ pid = 0, team = 2, hp = 300, maxhp = 600, loc = Vector(0, 0) })
bot.mode = BotMode.Laning
bot.slots = {}
bot.orders = {}
function bot:GetItemInSlot(s) return self.slots[s] end
function bot:Action_UseAbilityOnTree(item, tree) table.insert(self.orders, "tree:" .. item:GetName() .. ":" .. tree) end
function bot:Action_UseAbilityOnEntity(item, u) table.insert(self.orders, "unit:" .. item:GetName() .. ":" .. u:GetPlayerID()) end
function bot:Action_UseAbility(item) table.insert(self.orders, "none:" .. item:GetName()) end
local ally = MakeUnit({ pid = 1, team = 2, hp = 200, maxhp = 500, loc = Vector(600, 0) })
function GetUnitList() return { bot, ally } end
function GetUnitToUnitDistance(a, b) local dx, dy = a.loc.x - b.loc.x, a.loc.y - b.loc.y return math.sqrt(dx * dx + dy * dy) end
function GetUnitToLocationDistance(a, l) local dx, dy = a.loc.x - l.x, a.loc.y - l.y return math.sqrt(dx * dx + dy * dy) end

local function reset()
	A.ResetCache()
	bot.orders, bot.moves, lines = {}, {}, {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	bot.mode, bot.hitByHero, bot.action, bot.loc = BotMode.Laning, false, nil, Vector(0, 0)
	world.held, world.job, world.running = true, false, nil
end
local function ended()
	for i = #lines, 1, -1 do
		local ed = lines[i]:match("ev=sustain .*ed=(%a+)")
		if ed then return ed end
	end
	return nil
end

-- Who is carried, and OHA's gate.
do
	reset()
	check("a held laner: carried; every heal and mana item is gated from OHA, other items are not",
		A.Holds(bot) and A.HoldsItem(bot, "item_tango") and A.HoldsItem(bot, "item_magic_wand") and A.HoldsItem(bot, "item_clarity")
			and not A.HoldsItem(bot, "item_blink"))
	world.held = false
	check("not held: not carried, OHA keeps its items", not A.Holds(bot) and not A.HoldsItem(bot, "item_tango"))
	local C = require("bots/FunLib/custom_loader")
	C.Ours = C.Ours or {}
	C.Ours.Sustain = false
	world.held = true
	check("the switch off: nothing carried", not A.Holds(bot) and not A.HoldsItem(bot, "item_flask"))
	C.Ours.Sustain = nil
end

-- A tango with its tree in range: ordered from ItemThink in any mode; it ends `started` when a charge goes.
do
	reset()
	bot.slots = { [1] = itemOf("item_tango", 3) }
	answer = { kind = "use", slot = 1, name = "tango", reason = "top_up" }
	bot.mode = BotMode.Farm
	T = 100
	A.ItemThink(bot)
	check("tango, tree in range, farm mode: eaten on the tree at once; the lane row holds the frame until it starts", bot.orders[1] == "tree:item_tango:7" and A.Walking(bot))
	bot.slots[1].charges = 2
	T = 100.1
	A.ItemThink(bot)
	check("a charge gone: the attempt ends started", ended() == "started")
end

-- A tango walk: only where the laning mode (its row) or a camp job's supply will carry it; it ends `cut` when that stops.
do
	reset()
	bot.slots = { [1] = itemOf("item_tango", 3) }
	INPUTS.tree = { walk = 1.5, safe = true }
	answer = { kind = "use", slot = 1, name = "tango", reason = "top_up" }
	bot.mode = BotMode.Farm
	T = 200
	A.ItemThink(bot)
	check("a walk outside the laning mode and no job: not started", #bot.orders == 0 and not A.Walking(bot))
	bot.mode = BotMode.Laning
	T = 201
	A.ItemThink(bot)
	check("in the laning mode: ordered, and the row wants the frame", bot.orders[1] == "tree:item_tango:7" and A.Walking(bot))
	bot.action = BOT_ACTION_TYPE_USE_ABILITY
	T = 201.1
	A.Step(bot)
	check("the row's step gives no second order while the cast is under way", #bot.orders == 1)
	bot.mode = BotMode.Attack
	T = 201.2
	A.ItemThink(bot)
	check("the hero leaves the laning mode mid-walk: cut", ended() == "cut" and not A.Walking(bot))

	reset()
	bot.slots = { [1] = itemOf("item_tango", 3) }
	bot.mode = BotMode.Farm
	world.job = true
	T = 300
	A.ItemThink(bot)
	check("a camp job runs: the walk starts, and the supply's yield carries it", bot.orders[1] == "tree:item_tango:7" and A.Yield(bot))
	T = 300.1
	A.ItemThink(bot)
	check("yielded within 0.3 s: still running", ended() == nil and A.Walking(bot))
	T = 304
	A.ItemThink(bot)
	check("nothing by the deadline (walk + 1.5 s): missed or cut", ended() == "cut" or ended() == "missed")
	INPUTS.tree = { walk = 0, safe = true }
end

-- A salve with a step out: the row walks to the spot and drinks there; the running answer ends it.
do
	reset()
	bot.slots = { [2] = itemOf("item_flask", 1) }
	answer = { kind = "step_out_use", slot = 2, name = "flask", at = { x = -500, y = 0 }, reason = "top_up" }
	T = 400
	A.ItemThink(bot)
	check("a step out: no drink yet, the row wants the frame", #bot.orders == 0 and A.Walking(bot))
	A.Step(bot)
	check("the row's step moves to the spot", bot.moves ~= nil and #bot.moves >= 1 and bot.moves[#bot.moves].x == -500)
	bot.loc = Vector(-450, 0)
	A.Step(bot)
	check("within 100 of it: drinks the salve on itself, and the walk is over", bot.orders[1] == "unit:item_flask:0" and not A.Walking(bot))
	world.running = { kind = "step_out_use", reason = "running" }
	T = 400.6
	A.ItemThink(bot)
	check("the running answer holds it", ended() == nil)
	world.running = { kind = "none", reason = "fine", ended = "interrupted" }
	T = 401.2
	A.ItemThink(bot)
	check("the running answer ends it: logged with its end", ended() == "interrupted")
end

-- Give: a tango on the ally; rule 1 under hits replaces a running attempt.
do
	reset()
	bot.slots = { [1] = itemOf("item_tango", 2), [3] = itemOf("item_magic_wand", 8) }
	answer = { kind = "give", slot = 1, name = "tango", to = 1, reason = "give" }
	T = 500
	A.ItemThink(bot)
	check("give: the tango cast on the ally, walking into range from 600 away", bot.orders[1] == "unit:item_tango:1" and A.Walking(bot))
	bot.hitByHero = true
	answer = { kind = "use", slot = 3, name = "magic_wand", reason = "survive" }
	T = 500.2
	A.ItemThink(bot)
	check("hit, rule 1 answers: the give is cut and the wand used at once", bot.orders[#bot.orders] == "none:item_magic_wand")
	local cut = false
	for _, l in ipairs(lines) do if l:find("ev=sustain", 1, true) and l:find("k=give", 1, true) and l:find("ed=cut", 1, true) then cut = true end end
	check("the give's line ends cut", cut, table.concat(lines, " | "))
	local n, nl = #bot.orders, #lines
	T = 500.3
	A.ItemThink(bot)
	check("rule 1 again a frame later, the wand's charge not yet gone: the running use is kept, no second order", #bot.orders == n and #lines == nl, table.concat(lines, " | "))
end

-- home and buy are logged only in this step; a dead hero ends its attempt.
do
	reset()
	bot.slots = { [1] = itemOf("item_tango", 3) }
	answer = { kind = "home", reason = "cannot_stay" }
	T = 600
	A.ItemThink(bot)
	check("home: no order (retreat's heal still walks it home)", #bot.orders == 0 and not A.Walking(bot))
	answer = { kind = "use", slot = 1, name = "tango", reason = "top_up" }
	INPUTS.tree = { walk = 1, safe = true }
	T = 601
	A.ItemThink(bot)
	bot.alive = false
	A.ItemThink(bot)
	check("dead mid-attempt: ends dead", ended() == "dead")
	bot.alive = true
end

finish()
