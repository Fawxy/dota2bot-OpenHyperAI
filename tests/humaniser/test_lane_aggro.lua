-- Slice lane-aggro: the rules that decide when a laner may draw creeps (lane_aggro). The in-game halves (who the creeps target,
-- the deny) are read from ev=aggro in the check run.
dofile(HARNESS_DIR .. "/lane_world.lua")
LaneFresh({ Enable = true })
local A = require("bots/FunLib/humaniser/lane_aggro")

-- The 3 s draw clock is shared with the trade's own attack orders: a prime 1 s ago blocks a draw, as does our own draw.
check("a trade's prime 1 s ago blocks the draw (one aggro clock per hero)", not A.CooldownClear(10, nil, 9))
check("our own draw 2 s ago blocks the next", not A.CooldownClear(10, 8, nil))
check("both older than the cooldown: the draw may go", A.CooldownClear(10, 6.5, 6.8))
check("never ordered: the draw may go", A.CooldownClear(10, nil, nil))

-- One draw per lane at a time: the partner's draw holds the lane for the cooldown, ours does not hold us.
check("the partner drew 1 s ago: the lane is held", A.LaneHeld(10, 2, { pid = 1, at = 9 }))
check("our own draw does not hold us (the cooldown does)", not A.LaneHeld(10, 1, { pid = 1, at = 9 }))
check("the partner's draw has run out: the lane is free", not A.LaneHeld(10, 2, { pid = 1, at = 6 }))

-- Slice lh-draw step 2: the feed runs on every wave; the controller refuses it only on a shove wave, a drill only by forcing
-- another lever.
check("a back wave: no veto", A.CtlVeto({ mode = "safe", levers = { "feed" } }, nil) == nil)
check("a hold wave choosing no lever: no veto (the feed is no longer the controller's to give)", A.CtlVeto({ mode = "safe", levers = {} }, nil) == nil)
check("a shove wave: refused", A.CtlVeto({ mode = "shove", levers = { "shove" } }, nil) == "ctl_shove")
check("shove mode on a hold wave: refused (the feed would pull back what the shove pushed)", A.CtlVeto({ mode = "shove", levers = {} }, nil) == "ctl_shove")
check("a drill forcing none: refused", A.CtlVeto({ mode = "safe", levers = {} }, "none") == "ctl_forced")
check("a drill forcing the feed: fires even under shove", A.CtlVeto({ mode = "shove", levers = {} }, "feed") == nil)

-- The tower move orders just past their creeps, never from inside the tower's reach.
local x, y = A.TowerPoint(0, 0, 500, 0)
check("their creeps 500 from the tower: order 924 out on their line (reach 844 + hero 24 + margin 56)", x == 924 and y == 0)
x, y = A.TowerPoint(0, 0, 0, -800)
check("their creeps 800 out: order 250 beyond them", x == 0 and y == -1050)

-- The drop (attack order on our ranged creep) comes once a drawn creep reaches it, not before the walk has pulled them.
check("a drawn creep beside our ranged creep after the walk: drop", A.DropNow(1.0, 2, 150))
check("beside it but too early (the creeps would turn back onto our melee): wait", not A.DropNow(0.5, 2, 150))
check("still far from it: keep walking", not A.DropNow(1.0, 2, 600))
check("the drop is never later than DropBy, near or not", A.DropNow(1.9, 1, 900))
-- Review 2026-11-05-lane-aggro-41120ba F1: a move whose caller lost the frame (OHA's retreat 396-416 s in lagchk4 A) resumed past
-- its gates. An acting move ends after half a second unstepped; the watch rides out a body swing but not a retreat.
check("stale: acting, 0.3 s gap kept", not A.Stale("approach", 0.3))
check("stale: acting, 1 s gap ends it", A.Stale("walk", 1))
check("stale: watch, 1 s gap (a swing) kept", not A.Stale("watch", 1))
check("stale: watch, 20 s gap (a retreat) ends it", A.Stale("watch", 20))

-- A creep seen at the order that has since left our vision keeps a valid handle with no location (chold3_A_on_1 t=217.6:
-- `lua_error` in States.SupportStep, lane_aggro's moved count indexed it). It is not counted, and nothing raises.
do
	local function u(loc, alive) return { IsNull = function() return false end, IsAlive = function() return alive ~= false end, GetLocation = function() return loc end } end
	local start = { { unit = u(nil), x = 0, y = 0 }, { unit = u(Vector(200, 0)), x = 0, y = 0 }, { unit = u(Vector(50, 0)), x = 0, y = 0 }, { unit = u(Vector(500, 0), false), x = 0, y = 0 } }
	local ok, n = pcall(A.MovedOf, start)
	check("moved: a creep with no location is skipped, no error", ok, n)
	check("moved: only the seen creep 200 from its spot counts", ok and n == 1, n)
end

-- Slice lane-aggro, user 06/11/2026 (obs0611 mark 1): lane_spot keeps an offlaner 560-940 from the feed's approach point, so
-- the feed walks up to ApproachMax and gets the time to arrive; under a fixed 1.2 s a 900 walk ordered about 350 in, short of
-- the creeps.
check("approach: a 900 walk at 300 speed gets the time to arrive", A.ApproachTime(900, 300) * 300 >= 900, A.ApproachTime(900, 300))
check("approach: a short walk orders soon after arriving", A.ApproachTime(120, 300) < 1, A.ApproachTime(120, 300))
check("approach: a slowed or rooted hero orders from where it stands by the cap", A.ApproachTime(900, 0) <= 3.5 and A.ApproachTime(900, 150) <= 3.5)

-- The feed never draws their creeps inside the wave hold point (900 from our T1 on a side lane, 1300 mid): wave_hold meets
-- them there. Points are taken along the real lane paths from each team's own T1.
do
	local LP = require("bots/FunLib/humaniser/lane_push")
	local dota = require("bots/ts_libs/dota/index")
	local function at(lane, team, own)
		local path = LP.PathOf(lane)
		local t1, dir = LP.OwnT1(path, team)
		local p = LP.PointAt(path, t1 + dir * own)
		return path, p[1], p[2]
	end
	local function inside(lane, team, own)
		local path, x, y = at(lane, team, own)
		return A.InsideHold(path, team, lane, x, y)
	end
	check("hold: Radiant top, the walk back ends 700 from our T1: inside", inside(dota.Lane.Top, dota.Team.Radiant, 700))
	check("hold: Radiant top, 1100 from our T1: outside", not inside(dota.Lane.Top, dota.Team.Radiant, 1100))
	check("hold: Dire bot (the path runs the other way), 700 from their own T1: inside", inside(dota.Lane.Bot, dota.Team.Dire, 700))
	check("hold: Dire bot, 1100 from their own T1: outside", not inside(dota.Lane.Bot, dota.Team.Dire, 1100))
	check("hold: mid's hold point is further out: 1100 is inside", inside(dota.Lane.Mid, dota.Team.Radiant, 1100))
end

-- An order's hero that leaves vision before the order is re-picked (any visible enemy hero draws the creeps, EC-053) instead
-- of ending the move `cancelled` (obs0611 t=33.1: Lich went into the trees, DK was still seen; 11% of feeds ended so).
do
	local dota = require("bots/ts_libs/dota/index")
	local function world()
		LaneFresh({ Enable = true }, { laneAggro = true })
		local Ag = require("bots/FunLib/humaniser/lane_aggro")
		local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, 5000), hp = 600 })
		bot.maxhp, bot.lane = 600, dota.Lane.Top
		MakeCreep({ team = 3, x = 150, y = 5000 })
		local nearH = MakeUnit({ pid = 5, team = 3, loc = Vector(400, 5000) })
		local farH = MakeUnit({ pid = 6, team = 3, loc = Vector(900, 5000) })
		return Ag, bot, nearH, farH
	end
	local Ag, bot, nearH, farH = world()
	check("re-pick: the draw starts on the nearest enemy hero", Ag.StartBack(bot, Vector(-3000, 5000)))
	nearH.CanBeSeen = function() return false end
	Ag.Step(bot)
	local orders = ActionsOf(1, "AttackUnit")
	check("re-pick: the order goes to the hero still seen", #orders == 1 and orders[1].args[1] == farH, #orders)
	check("re-pick: the move is still open", Ag.Pending(bot))
end

-- A feed scene on the real top lane path from Radiant's T1 (the world's T1 moved onto it): our ranged creep `S` from the T1,
-- two of their melee creeps on it 200 further out, the core 700 back from the creep (a walk of about 500 to the approach
-- point), two enemy heroes 1600 out. The lane push reading says the clash is beyond the target point.
local function feedScene(S, pos)
	local dota = require("bots/ts_libs/dota/index")
	local H = LaneFresh({ Enable = true }, { laneAggro = true, telemetry = { Enable = true }, states = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local LP = require("bots/FunLib/humaniser/lane_push")
	LP.Read = function() return { own = 2000, move = 0, q = 0.5, state = "hold", clash = 0, tower = false } end
	local Ag = require("bots/FunLib/humaniser/lane_aggro")
	local path = LP.PathOf(dota.Lane.Top)
	local t1, dir = LP.OwnT1(path, 2)
	local function pt(own) local p = LP.PointAt(path, t1 + dir * own) return p[1], p[2] end
	local tx, ty = pt(0)
	TOWERS_W[2][dota.Tower.Top1].loc = Vector(tx, ty)
	local x, y = pt(S)
	MakeCreep({ team = 2, x = x, y = y, name = "npc_dota_creep_goodguys_ranged" })
	for i = 1, 2 do local cx, cy = pt(S + 200) MakeCreep({ team = 3, x = cx + 20 * i, y = cy }) end
	local bx, by = pt(S - 700)
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(bx, by), hp = 600, mode = dota.BotMode.Laning })
	bot.maxhp, bot.lane, bot.pos = 600, dota.Lane.Top, pos or 3
	local hx, hy = pt(S + 1600)
	local h1 = MakeUnit({ pid = 5, team = 3, loc = Vector(hx, hy) })
	local h2 = MakeUnit({ pid = 6, team = 3, loc = Vector(hx + 300, hy) })
	T = 30
	local function has(pat) for _, l in ipairs(lines) do if l:find(pat) then return true end end return false end
	return Ag, bot, h1, h2, has, H
end

-- The feed's walk back would end 750 from our T1, inside the side lane's 900 hold point: no draw (wave_hold meets them there).
do
	local Ag, bot, _, _, has = feedScene(1000)
	Ag.Step(bot)
	check("inside hold: the feed does not start", not Ag.Pending(bot) and #ActionsOf(1) == 0)
	check("inside hold: the skip says why", has("why=feed:inside_hold"))
	Ag, bot = feedScene(1400)
	Ag.Step(bot)
	check("outside hold (the walk back ends 1150 out): the feed starts its approach", Ag.Pending(bot) and #ActionsOf(1, "MoveToLocation") == 1)
end

-- The feed's own approach: the named hero leaves vision mid-walk; the order goes to the hero still seen when the bot arrives.
do
	local Ag, bot, h1, h2, has = feedScene(1400)
	Ag.Step(bot)
	h1.CanBeSeen = function() return false end
	local orders
	for _ = 1, 16 do
		T = T + 0.25
		Ag.Step(bot)
		orders = ActionsOf(1, "AttackUnit")
		if #orders > 0 then break end
		local mv = ActionsOf(1, "MoveToLocation")
		bot.loc = mv[#mv].args[1]
	end
	check("feed re-pick: the move is not cancelled", not has("result=cancelled"))
	check("feed re-pick: the draw is ordered on the hero still seen", #orders == 1 and orders[1].args[1] == h2, #orders)
end

-- awchk1 (t=32.7, Pudge, ad=772): the approach returns from mode_laning's Think before the laning body is stepped, so the
-- engine ends the body's task (stalled, then never_started) and the body stops running for a while. The draw step must keep
-- stepping the open attempt then, or the attempt ends `stale` mid-walk (23 of 25 stale feeds in awchk1).
do
	local Ag, bot, _, _, has, H = feedScene(1400)
	Ag.Step(bot)
	check("body off: the laning body is not running", H.States.IsEnabled() and not H.States.BodyLastHits(bot))
	local n0 = #ActionsOf(1, "MoveToLocation")
	for _ = 1, 4 do
		T = T + 0.25
		H.States.CoreAggroStep(bot)
	end
	check("body off: the approach keeps stepping", #ActionsOf(1, "MoveToLocation") == n0 + 4 and Ag.Pending(bot), #ActionsOf(1, "MoveToLocation") - n0)
	check("body off: no stale end", not has("result=stale"))
end

-- Review 2026-11-06-aggro-walkin-321f215 M1: with the body off only the open attempt is stepped, and only a core's. An attempt
-- that ends there (a retreat held the bot) opens no new draw; a support's open draw stays support_lane's (body-running gate).
do
	local dota = require("bots/ts_libs/dota/index")
	local Ag, bot, _, _, has, H = feedScene(1400)
	Ag.Step(bot)
	T = T + 0.25
	bot.mode = dota.BotMode.Retreat
	Ag.Tick(bot)
	T = T + 0.5
	bot.mode = dota.BotMode.Laning
	local n0 = #ActionsOf(1, "MoveToLocation")
	check("body off: the laning body is not running", not H.States.BodyLastHits(bot))
	H.States.CoreAggroStep(bot)
	check("body off: the stale attempt ends and no new draw starts", has("result=stale") and not Ag.Pending(bot) and #ActionsOf(1, "MoveToLocation") == n0)

	Ag, bot, _, _, _, H = feedScene(1400, 5)
	Ag.Step(bot)
	check("support scene: the support's feed starts (its core away)", Ag.Pending(bot))
	n0 = #ActionsOf(1, "MoveToLocation")
	T = T + 0.25
	H.States.CoreAggroStep(bot)
	check("body off, a support: the core step does not step its draw", #ActionsOf(1, "MoveToLocation") == n0)
end

-- awchk2 (t=44.3 Pudge, 104.7): the walk went unstepped for 0.7-1.7 s with the bot in laning mode throughout, and a body
-- deny swing holds a feed's watch for seconds (161.9, 335.4). With no other mode seen holding the bot, the move resumes; after
-- OHA's retreat held it, it ends `stale` naming that mode.
do
	local dota = require("bots/ts_libs/dota/index")
	local Ag, bot, _, _, has, H = feedScene(1400)
	Ag.Step(bot)
	local n0 = #ActionsOf(1, "MoveToLocation")
	for _ = 1, 6 do T = T + 0.25 H.States.Tick(bot) end
	Ag.Step(bot)
	check("gap in laning: the walk resumes", Ag.Pending(bot) and #ActionsOf(1, "MoveToLocation") == n0 + 1 and not has("result=stale"))

	Ag, bot, _, _, has, H = feedScene(1400)
	Ag.Step(bot)
	T = T + 0.25
	bot.mode = dota.BotMode.Retreat
	H.States.Tick(bot)
	T = T + 0.5
	bot.mode = dota.BotMode.Laning
	H.States.Tick(bot)
	Ag.Step(bot)
	check("retreat held the bot: the move ends stale, naming the retreat", has("result=stale.* md=" .. dota.BotMode.Retreat .. " "))
end

-- Slice lh-draw step 3: the feed's watch is read whichever mode holds the bot (banked logs: 697 of 999 stale feeds ended in
-- the watch, the move done); a feed whose approach ends with no enemy creep in draw range gives no order.
local function toWatch(Ag, bot)
	Ag.Step(bot)
	bot.loc = ActionsOf(1, "MoveToLocation")[1].args[1]
	T = T + 0.25
	Ag.Step(bot)
	CREEPS[3][1].target = bot
	T = T + 0.5
	Ag.Step(bot)
	T = T + 1.5
	Ag.Step(bot)
end
do
	local dota = require("bots/ts_libs/dota/index")
	local Ag, bot, _, _, has, H = feedScene(1400)
	bot.GetDenies = function(self) return self.dn or 0 end
	toWatch(Ag, bot)
	check("watch scene: the drop was ordered on our ranged creep", #ActionsOf(1, "AttackUnit") == 2 and Ag.Pending(bot) and not Ag.Acting(bot))
	local ranged = ActionsOf(1, "AttackUnit")[2].args[1]
	bot.mode = dota.BotMode.Retreat
	for _ = 1, 20 do T = T + 0.25 H.States.Tick(bot) end
	bot.mode = dota.BotMode.Laning
	Ag.Step(bot)
	check("a retreat held the bot 5 s through the watch: back in lane it still watches, not stale", Ag.Pending(bot) and not has("result=stale"))
	bot.mode = dota.BotMode.Retreat
	T = T + 0.25
	ranged.hp = 0
	bot.dn = 1
	H.States.Tick(bot)
	check("the fed creep dies to our deny during the retreat: denied", has("kind=feed result=denied") and not Ag.Pending(bot))
end
do
	local Ag, bot, _, _, has = feedScene(1400)
	Ag.Step(bot)
	bot.loc = ActionsOf(1, "MoveToLocation")[1].args[1]
	for _, c in ipairs(CREEPS[3]) do c.loc = Vector(c.loc.x + 3000, c.loc.y) end
	T = T + 0.25
	Ag.Step(bot)
	check("approach ends with no enemy creep in draw range: `short`, no draw order", has("kind=feed result=short") and #ActionsOf(1, "AttackUnit") == 0)
	T = T + 0.25
	Ag.Step(bot)
	check("short: that ranged creep is not fed again", not Ag.Pending(bot) and has("why=feed:no_ranged_fed"))
end

-- A walk started safe is not dropped when an enemy hero edges a few units closer: the end needs its attack to reach the point.
do
	local Ag, bot, h1 = feedScene(1400)
	Ag.Step(bot)
	local at = ActionsOf(1, "MoveToLocation")[1].args[1]
	h1.loc = Vector(at.x + 750, at.y)
	T = T + 0.25
	Ag.Step(bot)
	check("hysteresis: a hero 750 from the approach point (inside the start margin, outside its attack) keeps the walk", Ag.Pending(bot))
end

-- Review 2026-11-06-aggro-walkin M1: the walk may last 3.5 s; an enemy hero that comes into reach of the approach point during it
-- ends the move before the order.
do
	local Ag, bot, h1, _, has = feedScene(1400)
	Ag.Step(bot)
	local at = ActionsOf(1, "MoveToLocation")[1].args[1]
	h1.loc = Vector(at.x + 300, at.y)
	T = T + 0.25
	Ag.Step(bot)
	check("unsafe mid-walk: the move ends `unsafe` with no draw order", has("result=unsafe") and not Ag.Pending(bot) and #ActionsOf(1, "AttackUnit") == 0)
end

finish()
