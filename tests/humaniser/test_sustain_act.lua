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
		local ed = lines[i]:match("ev=sustain .*ed=([%a_]+)")
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
	check("a camp job runs but its supply step has not asked: no walk starts", (function() A.ItemThink(bot) return #bot.orders == 0 end)())
	T = 300.6
	A.Yield(bot)
	A.ItemThink(bot)
	check("a camp job runs: the walk starts, and the supply's yield carries it", bot.orders[1] == "tree:item_tango:7" and A.Yield(bot))
	T = 300.7
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
	local nl = #lines
	T = 500.3
	A.ItemThink(bot)
	check("rule 1 again a frame later, the wand's charge not yet gone: the running use is kept (not cut and restarted)", #lines == nl, table.concat(lines, " | "))
end

-- An instant use whose charge has not gone is ordered again each frame (a stun swallowed the first), until it starts.
do
	reset()
	bot.slots = { [3] = itemOf("item_magic_wand", 8) }
	bot.hitByHero = true
	answer = { kind = "use", slot = 3, name = "magic_wand", reason = "survive" }
	T = 550
	A.ItemThink(bot)
	T = 550.05
	A.ItemThink(bot)
	check("the wand's charge still there a frame later: ordered again", #bot.orders == 2 and bot.orders[2] == "none:item_magic_wand", table.concat(bot.orders, ","))
	bot.slots[3].charges = 0
	answer = { kind = "none", reason = "fine" }
	T = 550.1
	A.ItemThink(bot)
	check("its charge gone: started, no third order", ended() == "started" and #bot.orders == 2)
end

-- Step 4: home is retreat's walk (the flag it reads); while that walk runs Decide is asked with a running `home`.
local RS = require("bots/FunLib/humaniser/retreat_state")
do
	reset()
	bot.slots = { [1] = itemOf("item_tango", 3) }
	answer = { kind = "home", reason = "cannot_stay" }
	T = 600
	A.ItemThink(bot)
	check("home: no order, the flag set for retreat", #bot.orders == 0 and not A.Walking(bot) and RS.Home(bot) == true)
	answer = { kind = "none", reason = "fine" }
	T = 601
	A.ItemThink(bot)
	check("none: the flag cleared", RS.Home(bot) == false)
	RS.SetHealing(bot, true)
	world.running = { kind = "home", reason = "running" }
	T = 602
	A.ItemThink(bot)
	check("the walk home runs: Decide asked with a running home", INPUTS.run ~= nil and INPUTS.run.kind == "home" and RS.Home(bot) == true)
	RS.SetHealing(bot, false)
	world.running = nil
	world.held = false
	T = 603
	A.ItemThink(bot)
	check("no longer held: the flag gone (retreat's heal floor decides)", RS.Home(bot) == nil)
end

-- Step 5: a purchase, its courier delivery (OHA's courier stands aside) and the wait at the safe spot. What is on the way is
-- the game's read (SustainGather.OnTheWay: the stash and the courier), here `world.way`.
PURCHASE_ITEM_SUCCESS, PURCHASE_ITEM_INSUFFICIENT_GOLD = 0, 63
COURIER_ACTION_TAKE_AND_TRANSFER_ITEMS, COURIER_ACTION_BURST = 4, 10
COURIER_STATE_IDLE, COURIER_STATE_AT_BASE, COURIER_STATE_DELIVERING_ITEMS, COURIER_STATE_DEAD = 0, 1, 3, 5
local courier = { st = 1, GetAbilityByName = function() return { IsFullyCastable = function() return true end } end }
function GetCourierState(c) return c.st end
G.CourierOf = function() return courier end
G.OnTheWay = function() return world.way end
local buyRes = 0
function bot:ActionImmediate_PurchaseItem(name)
	table.insert(self.orders, "buy:" .. name)
	if buyRes == 0 then world.way = { hp = 400, mp = 0, eta = 20 } end
	return buyRes
end
function bot:ActionImmediate_Courier(_, act) table.insert(self.orders, "courier:" .. act) return true end
function bot:GetCurrentMovementSpeed() return 300 end
function bot:Action_MoveToLocation(p) table.insert(self.orders, "move:" .. p.x) end
INPUTS.shop = { { name = "flask", cost = 110, hp = 400, mp = 0 } }
INPUTS.courier = { eta = 20 }
local function count(prefix)
	local n = 0
	for _, o in ipairs(bot.orders) do if o:sub(1, #prefix) == prefix then n = n + 1 end end
	return n
end
do
	reset()
	world.way = nil
	bot.slots = {}
	answer = { kind = "buy", name = "flask", at = { x = -500, y = 0 }, reason = "cannot_stay" }
	T = 700
	A.ItemThink(bot)
	check("buy: purchased, the courier ordered to take and transfer, and burst", bot.orders[1] == "buy:item_flask" and bot.orders[2] == "courier:4" and bot.orders[3] == "courier:10",
		table.concat(bot.orders, ","))
	check("buy: OHA's courier stands aside; retreat is not sent home", A.OwnsCourier(bot) and RS.Home(bot) == false)
	answer = { kind = "wait", at = { x = -500, y = 0 }, reason = "delivery" }
	INPUTS.delivery = world.way
	T = 700.6
	A.ItemThink(bot)
	check("wait: the hero walks to the safe spot, the lane row holds the frame", A.Walking(bot) and bot.orders[#bot.orders] == "move:-500", table.concat(bot.orders, ","))
	world.way = nil
	T = 701
	A.ItemThink(bot)
	check("nothing left on the way: the delivery ends, the courier is OHA's again", not A.OwnsCourier(bot))
	local saw = false
	for _, l in ipairs(lines) do if l:find("ev=sustain ", 1, true) and l:find("k=buy", 1, true) and l:find("ed=delivered", 1, true) then saw = true end end
	check("ev=sustain k=buy ed=delivered logged", saw)
	answer = { kind = "none", reason = "fine" }
	INPUTS.delivery = nil
	T = 701.6
	A.ItemThink(bot)
	check("the answer moves on: the wait ends done", ended() == "done" and not A.Walking(bot))
end

do
	reset()
	bot.slots = {}
	world.way = { hp = 400, mp = 0, eta = 15 }
	answer = { kind = "buy", name = "flask", reason = "buy_hp" }
	T = 750
	A.ItemThink(bot)
	check("regen already on the way (OHA's, or a late one of ours): no second purchase", count("buy:") == 0, table.concat(bot.orders, ","))
	answer = { kind = "wait", at = { x = -500, y = 0 }, reason = "delivery" }
	INPUTS.delivery = world.way
	T = 751
	A.ItemThink(bot)
	check("a wait for it adopts it: our courier is ordered to bring it", A.OwnsCourier(bot) and count("courier:4") == 1, table.concat(bot.orders, ","))
	T = 751 + 15 + A.SETTINGS.LateSlack + 1
	A.ItemThink(bot)
	local late = false
	for _, l in ipairs(lines) do if l:find("k=buy", 1, true) and l:find("ed=late", 1, true) then late = true end end
	check("not landed by its eta: the delivery ends late; the wait's decision takes it over again (review: no stuck wait with the courier idle)",
		late and A.Walking(bot) and A.OwnsCourier(bot) and count("courier:4") == 2, table.concat(bot.orders, ","))
	INPUTS.delivery = nil
	world.way = nil
end

do
	reset()
	bot.slots = {}
	world.way = nil
	buyRes = 63
	answer = { kind = "buy", name = "flask", at = { x = -500, y = 0 }, reason = "cannot_stay" }
	T = 800
	A.ItemThink(bot)
	check("a refused purchase: no delivery, rule 2 sends the hero home", not A.OwnsCourier(bot) and RS.Home(bot) == true and ended() == "failed")
	answer = { kind = "buy", name = "flask", reason = "buy_hp" }
	T = 801
	A.ItemThink(bot)
	check("rule 5's buy sends nobody home", RS.Home(bot) == false)
	buyRes = 0
end

do
	reset()
	bot.slots = {}
	world.way = nil
	courier.st = 1
	answer = { kind = "buy", name = "flask", reason = "buy_hp" }
	T = 900
	A.ItemThink(bot)
	courier.st = 5
	T = 900.1
	A.ItemThink(bot)
	check("the courier dies on the way: the delivery ends", not A.OwnsCourier(bot) and ended() == "courier_dead")
	courier.st = 1
	T = 901
	A.ItemThink(bot)
	check("its salve still in the stash: no second purchase", count("buy:") == 1, table.concat(bot.orders, ","))
	world.way = nil
	T = 902
	A.ItemThink(bot)
	T = 902 + 20 + A.SETTINGS.LateSlack + 1
	A.ItemThink(bot)
	check("never landed: late", not A.OwnsCourier(bot) and ended() == "late")
	world.way = nil
end

-- A dead hero ends its attempt.
do
	reset()
	bot.slots = { [1] = itemOf("item_tango", 3) }
	answer = { kind = "use", slot = 1, name = "tango", reason = "top_up" }
	INPUTS.tree = { walk = 1, safe = true }
	T = 1000
	A.ItemThink(bot)
	bot.alive = false
	A.ItemThink(bot)
	check("dead mid-attempt: ends dead", ended() == "dead")
	bot.alive = true
end

-- OHA's retreat teleport (ability_item_usage_generic.lua item_tpscroll), its own source text run here: sustain holds the trips
-- home of a held laner (cases 1 and 3; rule 2 walks home) and leaves its escape (case 2) to OHA. h2h742: one gate on the whole
-- block left 7 of 280 losing escapes with a teleport, the mirror 81 of 318.
do
	local src = io.open(BOTS_ROOT .. "/bots/ability_item_usage_generic.lua", "r"):read("a")
	local from = src:find("\n\t%-%-撤退\n")
	local to = src:find("\n\t%-%-TP出去发育\n")
	check("the retreat teleport block is found in OHA's file", from ~= nil and to ~= nil and to > from)
	local tp = MakeUnit({ pid = 2, team = 2, hp = 60, maxhp = 600, level = 4 })
	function tp:GetAttackTarget() return nil end
	local juke = true
	local function ask(s)
		local env = setmetatable({
			bot = tp, botName = "npc_dota_hero_lion", nMode = BOT_MODE_RETREAT, nModeDesire = 0.95, botHP = s.hp, botMP = 0.5,
			nEnemyCount = s.enemies, nAllyCount = 1, itemFlask = nil, nMinTPDistance = 5500, sCastType = "ground",
			BOT_MODE_DESIRE_MODERATE = 0.5, BOT_ACTION_DESIRE_HIGH = 0.75,
			X = { CanJuke = function() return juke end },
			J = { Humaniser = { IsEnabled = function() return true end, SustainAct = A }, GetTeamFountain = function() return "fountain" end,
				GetNearbyHeroes = function() return {} end },
		}, { __index = _G })
		local chunk = assert(load(src:sub(from, to) .. "\nreturn nil", "tp_block", "t", env))
		local desire, loc, _, why = chunk()
		return desire, loc, why
	end
	local function tpLines()
		local n, why = 0, nil
		for _, l in ipairs(lines) do
			local w = l:match("ev=sustain_tp .*why=(%S+)")
			if w then n, why = n + 1, w end
		end
		return n, why
	end

	reset()
	T = 300
	tp.level, tp.hitByHero, tp.fountainDist = 4, true, 8000
	local d, loc, why = ask({ hp = 0.1, enemies = 1 })
	check("held, losing a fight it can break vision from: OHA's escape teleport casts", d == 0.75 and loc == "fountain" and why == "撤退:2", why)
	check("an escape logs no refusal", tpLines() == 0)

	reset()
	T = 300
	tp.hitByHero = false
	d = ask({ hp = 0.1, enemies = 0 })
	local n, w = tpLines()
	check("held, no enemy near, low: the trip home is sustain's, no teleport", d == nil)
	check("the refused trip home logs its case", n == 1 and w == "1", n)
	T = 300.5
	ask({ hp = 0.1, enemies = 0 })
	check("one line per run of refusals", tpLines() == 1)
	T = 303
	ask({ hp = 0.1, enemies = 0 })
	check("a refusal after the gap logs again", tpLines() == 2)

	reset()
	T = 300
	tp.level, tp.hitByHero = 10, false
	d = ask({ hp = 0.3, enemies = 1 })
	n, w = tpLines()
	check("held, level 10, one enemy not hitting: case 3's trip home is held too", d == nil and n == 1 and w == "3", w)

	reset()
	world.held = false
	tp.level, tp.hitByHero = 4, false
	d, loc, why = ask({ hp = 0.1, enemies = 0 })
	check("not held: OHA's trip home casts and nothing is logged", d == 0.75 and why == "撤退:1" and tpLines() == 0, why)
end

finish()
