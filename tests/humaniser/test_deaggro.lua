-- Slice deaggro: which of our lane creeps the shed orders onto (Plan), and the attempt's order, confirm and log line (Shed,
-- Watch). Whether the tower and creeps really switch on the order is the game's: read from ev=deaggro once a caller runs it.
dofile(HARNESS_DIR .. "/lane_world.lua")
LaneFresh({ Enable = true }, { telemetry = { Enable = true } })
local D = require("bots/FunLib/humaniser/deaggro")
local Telemetry = require("bots/FunLib/humaniser/telemetry")

local function tower(x, y) return { kind = "tower", x = x, y = y, reach = 800, locked = false } end
local function creep(x, y, locked) return { kind = "lane", x = x, y = y, reach = 500, locked = locked == true } end
local function own(x, y, d) return { x = x, y = y, d = d } end

-- Plan (target is the TS index into `ours`, 0-based)
local p = D.Plan({}, { own(0, 0, 10) })
check("plan: nobody on us: none", p.target == nil and p.why == "none")
p = D.Plan({ creep(0, 0, true), creep(10, 0, true) }, { own(0, 50, 10) })
check("plan: every attacker locked (we stand in their attack range): locked, no order", p.target == nil and p.why == "locked" and p.locked == 2)
p = D.Plan({ tower(0, 0) }, { own(2000, 0, 10) })
check("plan: our only creep outside the tower's reach: no_unit", p.target == nil and p.why == "no_unit")
p = D.Plan({ tower(0, 0) }, { own(700, 0, 300), own(500, 0, 100) })
check("plan: two creeps in the tower's reach: the nearer to us", p.target == 1 and p.covers == 1, p.target)
p = D.Plan({ tower(0, 0), creep(1200, 0) }, { own(400, 0, 50), own(750, 0, 400) })
check("plan: the creep both the tower and the chaser would take beats a nearer one only the tower would", p.target == 1 and p.covers == 2, p.target)
p = D.Plan({ creep(0, 0, true), creep(800, 0) }, { own(900, 0, 50) })
check("plan: a locked creep is not counted, the chaser is", p.target == 0 and p.covers == 1 and p.locked == 1)

-- Shed and Watch, against hand-made units.
local function unit(t)
	local u = { team = t.team or 2, hp = t.hp or 500, alive = true, target = nil }
	u.IsNull = function() return false end
	u.IsAlive = function() return u.alive end
	u.GetLocation = function() return Vector(t.x, t.y) end
	u.GetBoundingRadius = function() return t.radius or 24 end
	u.GetAttackRange = function() return t.range or 100 end
	u.GetAcquisitionRange = function() return t.acq or 500 end
	u.GetAttackTarget = function() return u.target end
	u.GetTeam = function() return u.team end
	u.GetUnitName = function() return t.name or "npc_dota_creep_goodguys_melee" end
	u.GetHealth = function() return u.hp end
	u.GetMaxHealth = function() return 1000 end
	u.GetPlayerID = function() return t.pid or -1 end
	return u
end

local lines = {}
Telemetry.SetSink(function(line) if line:find("ev=deaggro", 1, true) then table.insert(lines, line) end end)

local bot = unit({ x = 0, y = 0, pid = 3, range = 550 })
local enemyTower = unit({ x = 600, y = 0, team = 3, range = 700, radius = 100 })
local ours = unit({ x = 300, y = 100 })
local orders = {}
bot.Action_AttackUnit = function(_, target, once) table.insert(orders, { target = target, once = once }) end
bot.GetNearbyTowers = function(_, _, enemy) return enemy and { enemyTower } or {} end
bot.GetNearbyLaneCreeps = function(_, _, enemy) return enemy and {} or { ours } end

T = 100
local r = D.Shed(bot)
check("shed: nothing on us: no order", not r.ordered and r.why == "none" and #orders == 0)

enemyTower.target = bot
r = D.Shed(bot)
check("shed: the tower on us: one attack order on our creep", r.ordered and #orders == 1 and orders[1].target == ours, #orders)
check("shed: a second call while the attempt is open gives no second order", not D.Shed(bot).ordered and #orders == 1)
T = 100.2
check("watch: the tower still on us inside ConfirmFor: pending", D.Watch(bot) == "pending")
enemyTower.target = ours
T = 100.4
check("watch: the tower moved to our creep: ok", D.Watch(bot) == "ok")
check("watch: closed, nothing open", D.Watch(bot) == nil)
check("log: one ev=deaggro line, ok, tower", #lines == 1 and lines[1]:find("result=ok", 1, true) and lines[1]:find("kind=tower", 1, true), lines[1])

enemyTower.target = bot
T = 110
D.Shed(bot)
for _, t in ipairs({ 110.25, 110.5, 110.75 }) do
	T = t
	D.Watch(bot)
end
T = 111.1
check("watch: still on us after ConfirmFor: still_hit", D.Watch(bot) == "still_hit")

T = 120
D.Shed(bot)
T = 121
check("watch: the caller stopped watching: stale", D.Watch(bot) == "stale")

-- A creep with us inside its attack range will not switch: no order is given for it alone.
enemyTower.target = nil
local hugger = unit({ x = 80, y = 0, team = 3, range = 100 })
hugger.target = bot
bot.GetNearbyLaneCreeps = function(_, _, enemy) return enemy and { hugger } or { ours } end
T = 130
r = D.Shed(bot)
check("shed: only a locked creep on us: locked, no order", not r.ordered and r.why == "locked")

Telemetry.SetSink(nil)
finish()
