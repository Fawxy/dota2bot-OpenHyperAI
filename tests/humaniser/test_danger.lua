dofile(HARNESS_DIR .. "/lane_world.lua")
-- Danger at a place (danger.ts, offers-and-the-decider s5): the parts for a walk from the hero to an offer's place over its
-- seconds, from Threat.Reader's frame and Offer.PathCost; and the begin line's fields.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local HERE = Vector(-2000, -5000)
local CAMP = Vector(-1000, -6200)

local function world()
	LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true } })
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	require("bots/FunLib/humaniser/threat").ResetCache()
	FOGGED = function() return true end
	local bot = MakeUnit({ pid = 1, team = 2, loc = HERE, level = 3 })
	bot.lane, bot.pos, bot.maxhp, bot.hp, bot.speed = Lane.Bot, 3, 600, 600, 300
	return require("bots/FunLib/humaniser/danger"), bot
end

local function near(a, b, eps) return a ~= nil and math.abs(a - b) <= (eps or 0.01) end

-- A melee hero beside the camp reaches the walk within 4 s; the walk's last stretch is inside its range: exposure > 0, its
-- distance to the place, its damage as the threat read counts it, and the burst as a share of our HP.
do
	local Danger, bot = world()
	local e = MakeUnit({ pid = 10, team = 3, loc = Vector(-1000, -6300) })
	e.maxhp, e.hp, e.range, e.estDamage = 600, 600, 150, 300
	local p = Danger.At(bot, CAMP, 4)
	local r = p.reach[1]
	check("reach: the hero by the camp is counted", #p.reach == 1 and r.pid == 10, #p.reach)
	check("reach: its distance to the place", r and near(r.dist, 100, 1), r and r.dist)
	check("reach: seconds of the walk inside its range", r and r.exp > 0 and r.exp < 2, r and r.exp)
	check("reach: its damage and the burst share", r and near(r.dmg, 300) and near(p.burst, 0.5), p.burst)
	check("window: the offer's seconds", p.secs == 4, p.secs)
end

-- No seconds on the offer: the gate horizon. A hero far off is not in reach; out of sight heroes are listed nearest first
-- with their seconds unseen (no cut-off applied), and one never sighted is counted apart.
do
	local Danger, bot = world()
	local far = MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) })
	far.maxhp, far.hp = 600, 600
	local a = MakeUnit({ pid = 11, team = 3 })
	local b = MakeUnit({ pid = 12, team = 3 })
	local c = MakeUnit({ pid = 13, team = 3 })
	for _, u in ipairs({ a, b, c }) do u.hiddenFrom = { [OBSERVER] = true } end
	LAST_SEEN[11] = { location = Vector(3000, -6200), time_since_seen = 1 }
	LAST_SEEN[12] = { location = Vector(-1000, -5200), time_since_seen = 40 }
	LAST_SEEN[13] = nil
	local p = Danger.At(bot, CAMP)
	check("window: the gate horizon without seconds", p.secs == require("bots/FunLib/humaniser/threat").SETTINGS.GateHorizon, p.secs)
	check("reach: a hero far off is not counted", #p.reach == 0, #p.reach)
	check("away: both sighted heroes, nearest first, however briefly unseen", #p.away == 2 and p.away[1].pid == 12 and p.away[2].pid == 11
		and near(p.away[1].dist, 1000, 1) and p.away[2].tss == 1, #p.away)
	check("away: the hero never sighted counted apart", p.nos == 1, p.nos)
	local f = {}
	for _, kv in ipairs(Danger.Fields(p)) do f[kv[1]] = kv[2] end
	check("fields: no reachers, the unseen as pid:tss:dist", f.dn == 0 and f.dre == nil and f.dun == "12:40:1000,11:1:4000" and f.dnos == 1, tostring(f.dun))
end
finish()
