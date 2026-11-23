-- Sustain (design 2026-11-19-sustain-design.md, steps 2 and 3): Gather reads the decision's Inputs from the game. The reads it
-- borrows (Threat.Read, SafeGather.FromRead, its own NextDue, Retreat.SafeSpot) are replaced on their module
-- tables, so these checks are Gather's own: the items read from their special values and whether they can be cast now, a
-- running buff's rest, the safe-here read here and over the tree walk, the shop from what was read, the courier, and the cut line.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })
local G = require("bots/FunLib/humaniser/sustain_gather")
local UnitType = require("bots/ts_libs/dota/index").UnitType
local Threat = require("bots/FunLib/humaniser/threat")
local Retreat = require("bots/FunLib/humaniser/retreat")
local SafeGather = require("bots/FunLib/humaniser/safe_gather")

-- A read is told by its place: here (the stay read) or the tree's (the walk). FromRead hands back the Safe inputs each carries.
local function safeInputs(reach)
	return { hp = 300, hpMax = 600, reach = reach, missing = 0, tower = false, towerOnMe = false, landing = { hero = 0, creeps = 0, tower = 0 },
		away = false, held = false, hold = false }
end
local STAY = { safe = safeInputs({ { pid = 5, hitting = true, dmg = 250 }, { pid = 6, hitting = false, dmg = 50, unseen = true } }) }
local WALK = { safe = safeInputs({ { pid = 5, hitting = false, dmg = 270 } }) }
local reads = {}
Threat.Read = function(_, _, place, horizon)
	table.insert(reads, horizon)
	if place.x == 0 and place.y == 0 then return STAY end
	return WALK
end
SafeGather.FromRead = function(_, r) return r.safe end
-- The safe spot's own read (rule 2's wait): deadly when the test sets it.
local spotDeadly = false
SafeGather.At = function() return { level = spotDeadly and "deadly" or "safe" } end
G.NextDue = function() return 2.5 end
Retreat.SafeSpot = function() return { at = Vector(-500, -500), secs = 2.5 } end
Retreat.Fountain = function() return Vector(-6000, 0) end

COURIER_STATE_IDLE, COURIER_STATE_AT_BASE, COURIER_STATE_MOVING, COURIER_STATE_DEAD = 0, 1, 2, 5
local COURIER = { pid = 0, st = 1, loc = Vector(-6000, 0) }
function COURIER:GetPlayerID() return self.pid end
function COURIER:GetLocation() return self.loc end
function COURIER:GetCurrentMovementSpeed() return 300 end
COURIER.slots = {}
function COURIER:GetItemInSlot(n) return self.slots[n] end
function GetCourier(n) if n == 0 then return COURIER end return nil end
function GetCourierState(c) return c.st end
local STOCK = { item_tango = 5, item_flask = 0, item_clarity = 3 }
function GetItemStockCount(name) return STOCK[name] or 0 end
function GetItemCost(name) return ({ item_tango = 90, item_flask = 110, item_clarity = 50 })[name] or 0 end
local TREES = { [7] = Vector(300, 0), [8] = Vector(900, 0) }
function GetTreeLocation(t) return TREES[t] end
function IsLocationVisible() return true end
function IsLocationPassable() return true end
function GetUnitToUnitDistance(a, b) local dx, dy = a.loc.x - b.loc.x, a.loc.y - b.loc.y return math.sqrt(dx * dx + dy * dy) end

local function itemOf(name, charges, values)
	return {
		GetName = function() return name end,
		GetCurrentCharges = function() return charges end,
		GetSpecialValueFloat = function(_, k) return values[k] or 0 end,
		IsFullyCastable = function() return values.cooling ~= true end,
		GetCastRange = function() return 165 end,
	}
end
local TANGO = { health_regen = 7, buff_duration = 16 }
local SALVE = { health_regen = 40, buff_duration = 10 }
local CLARITY = { mana_regen = 6, buff_duration = 25 }

local bot = MakeUnit({ pid = 0, team = 2, hp = 300, maxhp = 600, loc = Vector(0, 0) })
bot.slots = { [0] = itemOf("item_tango", 3, TANGO), [1] = itemOf("item_flask", 1, SALVE), [2] = itemOf("item_magic_wand", 5, { restore_per_charge = 15 }),
	[3] = itemOf("item_magic_stick", 0, { restore_per_charge = 15 }), [4] = itemOf("item_branches", 1, {}), [6] = itemOf("item_clarity", 1, CLARITY) }
function bot:GetItemInSlot(s) return self.slots[s] end
function bot:GetNearbyTrees() return { 8, 7 } end
function bot:GetGold() return 230 end
function bot:GetModifierRemainingDuration() return self.left or 0 end
function bot:GetMana() return 100 end
function bot:GetMaxMana() return 300 end
local enemy = MakeUnit({ pid = 5, team = 3, hp = 500, loc = Vector(500, 0) })
enemy.burst = 250
local far = MakeUnit({ pid = 6, team = 3, hp = 500, loc = Vector(4000, 0) })
far.burst = 999
local ally = MakeUnit({ pid = 1, team = 2, hp = 200, maxhp = 500, loc = Vector(400, 0) })
function ally:GetItemInSlot(s) if s == 0 then return itemOf("item_flask", 2, SALVE) end return nil end
local function noItems(self) return nil end
enemy.GetItemInSlot = noItems
far.GetItemInSlot = noItems
function GetUnitList(kind)
	if kind == UnitType.EnemyHeroes then return { enemy, far } end
	if kind == UnitType.AlliedHeroes then return { bot, ally } end
	return {}
end

T = 100
local i = G.Gather(bot)
local by = {}
for _, it in ipairs(i.items) do by[it.name] = it end

check("items: a tango's three uses of 7 x 16, a salve that breaks, a clarity in the backpack, branches left out",
	by.tango and by.tango.charges == 3 and near(by.tango.hp, 112) and by.tango.tree and by.tango.share
		and by.flask and by.flask.breaks and near(by.flask.hp, 400) and by.clarity and by.clarity.slot == 6 and near(by.clarity.mp, 150)
		and by.branches == nil)
check("a wand restores 15 a charge once; an empty stick has no use",
	by.magic_wand and by.magic_wand.charges == 1 and near(by.magic_wand.hp, 75) and near(by.magic_wand.mp, 75) and by.magic_stick.charges == 0)
check("absolute HP; the safe-here read here: its kill (an unseen lane opponent's row counts), a hero hitting, one visible in reach",
	i.hp == 300 and i.hpMax == 600 and near(i.safe.kill, 300) and i.safe.hitting == true and i.safe.reach == 1)
check("ready: a slot 0-5 item that can be cast; the backpack's clarity is not",
	by.tango.ready == true and by.flask.ready == true and by.clarity.ready == false)
check("the nearest tree as a walk into the tango's 165 range at 300 a second, its walk read over the gate horizon and deadly there (300 / 270 under the fresh idle bar 1.15)",
	i.tree and near(i.tree.walk, 0.45) and i.tree.safe == false and reads[#reads] == Threat.SETTINGS.GateHorizon)
check("the next hit due, read with a tree item held", i.nextDue == 2.5)
check("the shop: a tango pack of three uses from the read, in stock; the salve out of stock is left out",
	#i.shop == 2 and (function()
		for _, o in ipairs(i.shop) do if o.name == "tango" then return o.cost == 90 and near(o.hp, 336) end end
		return false
	end)())
check("courier at base: eta from the fountain to the bot at 300", i.courier and near(i.courier.eta, 20))
check("home there and back, the safe spot and the ally with its two salves",
	near(i.home, 40) and i.safeSpot.walk == 2.5 and #i.allies == 1 and i.allies[1].missing == 300 and i.allies[1].heals == 2)

T = 109
WALK.safe.reach[1].dmg = 100
STAY.safe.reach[1].dmg = 50
bot.modifiers = { modifier_tango_heal = 1 }
bot.left = 8
COURIER.st = COURIER_STATE_MOVING
local j = G.Gather(bot)
check("1 s later the tree is read again: safe at 300 / 100 over the walk, and here no longer deadly (300 / 100)", j.tree and j.tree.safe == true)
STAY.safe.reach[1].dmg = 250
WALK.safe.reach[1].dmg = 100
T = 111
check("the same safe walk from a place deadly here (300 / 300): still safe, but no walk starts", (function() local tr = G.Gather(bot).tree return tr.safe == true and tr.start == false end)())
check("a running tango's 8 s left restore 56; a busy courier is no courier", near(j.regenLeft, 56) and j.courier == nil)

-- The nearest tree's walk deadly, a tree on the way to the safe spot (-500, -500) safe: the tango walks back to that one.
do
	TREES[9] = Vector(-400, -300)
	local trees0 = bot.GetNearbyTrees
	function bot:GetNearbyTrees() return { 8, 7, 9 } end
	local read0 = Threat.Read
	local BACK = { safe = safeInputs({ { pid = 5, hitting = false, dmg = 50 } }) }
	Threat.Read = function(b, h, place, horizon)
		if place.x == -400 and place.y == -300 then return BACK end
		return read0(b, h, place, horizon)
	end
	STAY.safe.reach[1].dmg = 50
	WALK.safe.reach[1].dmg = 270
	T = 113
	local tr = G.Gather(bot).tree
	check("nearest walk deadly, the one toward the safe spot safe: that tree (500 away, 1.1 s)", tr.safe == true and near(tr.walk, (500 - 165) / 300) and G.TreeOf(bot).id == 9)
	WALK.safe.reach[1].dmg = 100
	T = 115
	tr = G.Gather(bot).tree
	check("the nearest walk safe: the nearest tree, the other not read", tr.safe == true and G.TreeOf(bot).id == 7)
	BACK.safe.reach[1].dmg = 270
	WALK.safe.reach[1].dmg = 270
	T = 117
	tr = G.Gather(bot).tree
	check("both deadly: the nearest, unsafe", tr.safe == false and G.TreeOf(bot).id == 7)
	Threat.Read = read0
	bot.GetNearbyTrees = trees0
	TREES[9] = nil
	STAY.safe.reach[1].dmg = 250
	WALK.safe.reach[1].dmg = 100
end

-- Two stacked packs read 6 at once; a later pack of 3 sets what one purchase holds.
local other = MakeUnit({ pid = 2, team = 2, hp = 600, maxhp = 600, loc = Vector(0, 0) })
other.n = 6
function other:GetItemInSlot(s) if s == 0 then return itemOf("item_tango", self.n, TANGO) end return nil end
G._test.learned.item_tango.pack = 0
G.Items(other)
local six = G._test.learned.item_tango.pack
other.n = 2
G.Items(other)
other.n = 5
G.Items(other)
check("a purchase's size is the smallest rise in charges: 3 after a stack of 6", six == 6 and G._test.learned.item_tango.pack == 3,
	"after the stack " .. tostring(six))

local S = require("bots/FunLib/humaniser/sustain")
local fields = G.CutFields(0, i, S.Decide(i))
local f = {}
for _, p in ipairs(fields) do f[p[1]] = p[2] end
local dump = {} for k, v in pairs(f) do table.insert(dump, k .. "=" .. tostring(v)) end
check("the cut line: kind sustain, items as records, the tree walk, the safe-here read, the next hit, the answer",
	f.kind == "sustain" and f.hpa == 300 and f.hpm == 600 and string.find(f.it, "0,tango,3,112,0,16,0,1,0,1,1", 1, true) ~= nil
		and f.tr == "0.5,0,0" and f.kill == 300 and f.sh == 1 and f.rc == 1 and f.nd == 2.5 and f.ak ~= nil and f.why ~= nil and f.co == 20, table.concat(dump, " "))

do
	local function srn(run)
		local with = {}
		for k, v in pairs(i) do with[k] = v end
		with.run = run
		for _, p in ipairs(G.CutFields(0, with, S.Decide(with))) do if p[1] == "srn" then return p[2] end end
	end
	check("the cut line carries the executor's running answer: a step-out use 1.5 s in, with its item time and place",
		srn({ kind = "step_out_use", slot = 2, name = "flask", started = i.now - 1.5, hp0 = 280, dur = 12.5, at = { x = -500, y = -480 } })
			== "step_out_use,2,flask,1.5,280,12.5,-500,-480", srn({ kind = "step_out_use", slot = 2, name = "flask", started = i.now - 1.5, hp0 = 280, dur = 12.5, at = { x = -500, y = -480 } }))
	check("a walk home has no item, time or place: the parts are empty", srn({ kind = "home", started = i.now, hp0 = 300 }) == "home,,,0,300,,,", srn({ kind = "home", started = i.now, hp0 = 300 }))
	check("control: with no running answer the field is absent", f.srn == nil)
end

-- Regen on the way is read from the game: heal and mana items in the stash (9-14) or on the courier, whoever bought them; the
-- eta is the courier's walk to us when it is out, else to the fountain and then to us.
do
	COURIER_STATE_DELIVERING_ITEMS = 3
	COURIER.st, COURIER.loc = COURIER_STATE_AT_BASE, Vector(-6000, 0)
	check("nothing in the stash or on the courier: nothing on the way", G.OnTheWay(bot) == nil)
	bot.slots[9] = itemOf("item_flask", 1, SALVE)
	COURIER.slots[0] = itemOf("item_clarity", 1, CLARITY)
	local d = G.OnTheWay(bot)
	check("a salve in the stash and a clarity on the courier at base: 400 HP, 150 mana, 20 s (6,000 at 300)",
		d ~= nil and near(d.hp, 400) and near(d.mp, 150) and near(d.eta, 20), d and (d.hp .. "," .. d.mp .. "," .. d.eta))
	COURIER.st, COURIER.loc = COURIER_STATE_DELIVERING_ITEMS, Vector(-1500, 0)
	d = G.OnTheWay(bot)
	check("the courier out delivering: its walk to us, 5 s", d ~= nil and near(d.eta, 5))
	check("Gather carries it as the delivery input", near(G.Gather(bot).delivery.hp, 400))
	bot.slots[9], COURIER.slots[0] = nil, nil
	COURIER.st, COURIER.loc = COURIER_STATE_AT_BASE, Vector(-6000, 0)
end
finish()
