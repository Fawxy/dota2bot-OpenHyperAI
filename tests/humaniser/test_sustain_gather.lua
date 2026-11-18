-- Sustain step 2 (design 2026-11-19-sustain-design.md): Gather reads the decision's Inputs from the game. The reads it
-- borrows (Threat.Read, Retreat.SafeSpot, SpellReady.DamageOn, CampJobs.Active) are replaced on their module tables, so
-- these checks are Gather's own: the items read from their special values, a running buff's rest, the lane burst's
-- 10 s memory, the shop from what was read, the courier, the tree, and the cut line's text.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })
local G = require("bots/FunLib/humaniser/sustain_gather")
local UnitType = require("bots/ts_libs/dota/index").UnitType
local Threat = require("bots/FunLib/humaniser/threat")
local Retreat = require("bots/FunLib/humaniser/retreat")
local SpellReady = require("bots/FunLib/humaniser/spell_ready")
local CampJobs = require("bots/FunLib/humaniser/camp_jobs")

local STAY = { burst = 0.5, reach = { 1 } }
Threat.Read = function() return STAY end
Retreat.SafeSpot = function() return { at = Vector(-500, -500), secs = 2.5 } end
Retreat.Fountain = function() return Vector(-6000, 0) end
SpellReady.DamageOn = function(e) return e.burst or 0 end
CampJobs.Active = function() return false end

COURIER_STATE_IDLE, COURIER_STATE_AT_BASE, COURIER_STATE_MOVING, COURIER_STATE_DEAD = 0, 1, 2, 5
local COURIER = { pid = 0, st = 1, loc = Vector(-6000, 0) }
function COURIER:GetPlayerID() return self.pid end
function COURIER:GetLocation() return self.loc end
function COURIER:GetCurrentMovementSpeed() return 300 end
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
check("absolute HP and the stay read's burst share made absolute", i.hp == 300 and i.hpMax == 600 and near(i.burst, 150) and i.reach == 1)
check("the nearest tree, and the enemy's distance to it", i.tree and near(i.tree.d, 300) and near(i.tree.enemyD, 200))
check("lane burst: the hero within 2,000 counts, the one 4,000 off does not", near(i.laneBurst, 250))
check("the shop: a tango pack of three uses from the read, in stock; the salve out of stock is left out",
	#i.shop == 2 and (function()
		for _, o in ipairs(i.shop) do if o.name == "tango" then return o.cost == 90 and near(o.hp, 336) end end
		return false
	end)())
check("courier at base: eta from the fountain to the bot at 300", i.courier and near(i.courier.eta, 20))
check("home there and back, the safe spot and the ally with its two salves",
	near(i.home, 40) and i.safeSpot.walk == 2.5 and #i.allies == 1 and i.allies[1].missing == 300 and i.allies[1].heals == 2)

T = 109
enemy.loc = Vector(5000, 0)
bot.modifiers = { modifier_tango_heal = 1 }
bot.left = 8
COURIER.st = COURIER_STATE_MOVING
local j = G.Gather(bot)
check("a hero seen 9 s ago still counts; gone at 11 s",
	near(j.laneBurst, 250) and (function() T = 111 return near(G.Gather(bot).laneBurst, 0) end)())
check("a running tango's 8 s left restore 56; a busy courier is no courier", near(j.regenLeft, 56) and j.courier == nil)

local S = require("bots/FunLib/humaniser/sustain")
local fields = G.CutFields(0, i, S.Decide(i))
local f = {}
for _, p in ipairs(fields) do f[p[1]] = p[2] end
local dump = {} for k, v in pairs(f) do table.insert(dump, k .. "=" .. tostring(v)) end
check("the cut line: kind sustain, items as records, the answer",
	f.kind == "sustain" and f.hpa == 300 and f.hpm == 600 and string.find(f.it, "0,tango,3,112,0,16,0,1,0,1", 1, true) ~= nil
		and f.tr == "300,200" and f.ak ~= nil and f.why ~= nil and f.co == 20, table.concat(dump, " "))

finish()
