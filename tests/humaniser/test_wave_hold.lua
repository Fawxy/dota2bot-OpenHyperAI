-- Slice core-in-lane, the wave hold (states/wave_hold): the trigger's reading of a lane, the branch rule (user 05/11/2026) and
-- the lane_push schedule it reads. The in-game halves (where their wave died, the drag's walk) are read from ev=wave_hold.
dofile(HARNESS_DIR .. "/lane_world.lua")
LaneFresh({ Enable = true })
local W = require("bots/FunLib/humaniser/states/wave_hold")
local P = require("bots/FunLib/humaniser/lane_push")
local paths = require("bots/FunLib/humaniser/lane_push_data").LANE_PATHS
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end

-- The trigger: their wave walking in (distances from our T1, positive towards theirs) on a side lane (target 900).
local r = W.Read({ 1500, 1600, 1650, 1700 }, {}, 900)
check("their four creeps walking in, ours gone: hold, front at the nearest", type(r) == "table" and r.front == 1500 and r.n == 4, r)
check("our wave fighting theirs (600 past their front): no hold", W.Read({ 1500, 1600 }, { 1800 }, 900) == "ours")
check("our wave ahead of theirs walking back in: no hold", W.Read({ 1500, 1600 }, { 1200 }, 900) == "ours")
local r2 = W.Read({ 1500, 1600 }, { -800 }, 900)
check("our next wave still behind our T1 (800): ours is gone, hold", type(r2) == "table" and r2.front == 1500, r2)
check("their front 20 inside the 750 floor (our T1's range + 50): late", W.Read({ 730, 800 }, {}, 900) == "late")
local r3 = W.Read({ 800, 850 }, {}, 900)
check("their front 800 out, inside the side target 900: a hold, not late", type(r3) == "table" and r3.front == 800, r3)
-- obs0611 mark 4 (Luna 1:48-1:53 bot): a pull returnee of ours at 666 fighting 3 of theirs just outside our T1's range; mark 5
-- (Sniper 2:35 mid): our lone ranged creep at 512 while 4 of theirs walk in from 900. A creep of ours inside the T1's range is
-- not our wave.
local m4 = W.Read({ 760, 770, 775, 2200, 2230 }, { 666 }, 900)
check("mark 4: our lone creep at 666 inside the T1's range does not keep the hold off", type(m4) == "table" and m4.front == 760 and m4.n == 5, m4)
local m5 = W.Read({ 900, 920, 954, 1338 }, { 512 }, 1300)
check("mark 5: our lone ranged creep at 512 does not keep the hold off", type(m5) == "table" and m5.front == 900, m5)
check("one of ours at the T1's range edge (700) fighting their wave still counts as our wave", W.Read({ 800, 850 }, { 700 }, 900) == "ours")

-- The hold point: the lane target, or their front when it is already nearer our T1, never inside 800 of it.
check("hold point: their front past the side target, the target", W.HoldAt(900, 1500) == 900)
check("hold point: their front 850 inside the target, at their front", W.HoldAt(900, 850) == 850)
check("hold point: their front 760, the 800 floor", W.HoldAt(900, 760) == 800)

-- The forecast start reads lane_push's run: their front inside our T1's range within 8 s while our wave still fights.
-- Radiant's bot T1 sits at 8,057 on the bot path (sign +1); 2:30 has no spawn in the next 8 s.
do
	local bot = paths[3]
	local T = 8057
	local function run(init) return P.Run(bot, 150, 159, init, {}) end
	-- mark 5's shape: our melee at 850 (200 HP) and ranged at 512 against 4 full melee of theirs at 900-960.
	local losing = run({
		{ team = 2, kind = "melee", s = T + 850, hp = 200 },
		{ team = 2, kind = "ranged", s = T + 512, hp = 150 },
		{ team = 3, kind = "melee", s = T + 900, hp = 562 },
		{ team = 3, kind = "melee", s = T + 920, hp = 562 },
		{ team = 3, kind = "melee", s = T + 940, hp = 562 },
		{ team = 3, kind = "melee", s = T + 960, hp = 562 },
	})
	local fc = W.TowerIn(losing, T, 1, 3, 150)
	check("forecast: 2 weak creeps of ours v 4 at 900: their front inside our T1's range within 8 s", fc ~= nil and fc > 0 and fc <= 8, fc)
	local winning = run({
		{ team = 2, kind = "melee", s = T + 860, hp = 562 },
		{ team = 2, kind = "melee", s = T + 870, hp = 562 },
		{ team = 2, kind = "melee", s = T + 880, hp = 562 },
		{ team = 2, kind = "ranged", s = T + 700, hp = 400 },
		{ team = 3, kind = "melee", s = T + 920, hp = 120 },
		{ team = 3, kind = "melee", s = T + 940, hp = 120 },
	})
	check("forecast: our full wave v 2 weak creeps of theirs at 920: no start", W.TowerIn(winning, T, 1, 3, 150) == nil, W.TowerIn(winning, T, 1, 3, 150))
	-- Their front reaching the tower 12 s out is past ForecastSecs: the core does not leave its spot that early.
	local late = { { t = 150, front = { [3] = T + 2000 } }, { t = 162, front = { [3] = T + 650 } } }
	check("forecast: their front at our T1 only 12 s out: no start yet", W.TowerIn(late, T, 1, 3, 150) == nil)
end
-- chold1 0:31 mid: their front creeps chased 900 past a clash our wave was still fighting further out.
check("our wave fighting their rear creeps 800 behind their front: no hold", W.Read({ 1100, 1900, 1950 }, { 2050 }, 1300) == "ours")
check("their wave still beyond the stretch (2,500 past our T1 on a side lane): none", W.Read({ 3000, 3100 }, {}, 900) == "none")
check("mid's target sits further out, so the same wave is in its stretch", type(W.Read({ 2700, 2800 }, {}, 1300)) == "table")
check("one creep is not a wave", W.Read({ 1500 }, {}, 900) == "none")

-- The branch: a threat drags only when our next wave is not near and the drag ends before it arrives behind our T1.
check("no threat: hold", W.Choose(false, 30, 5, 30) == "hold")
check("threat, our next wave 8 s from the hold point: hold, the waves meet there", W.Choose(true, 8, 5, 20) == "hold")
check("threat, our wave 20 s off, the drag needs 6 s of 12: drag", W.Choose(true, 20, 6, 12) == "drag")
check("threat, the drag needs 11 s of 12 (inside the 2 s margin): hold", W.Choose(true, 20, 11, 12) == "hold")
-- ptchk1 A 7:00 top: the schedule put our next wave 24 s off while the pulled creeps walked back 1,000 from the hold point.
check("threat, schedule 24 s, our pulled creeps walking back 1,000 out: hold", W.Choose(true, W.Near(24, { 1000, 1400 }), 6, 30) == "hold", W.Near(24, { 1000, 1400 }))
check("threat, schedule 24 s, no creep of ours walking: drag", W.Choose(true, W.Near(24, {}), 6, 30) == "drag")
check("a wave on schedule sooner than the creeps walking in: the schedule's time", near(W.Near(5, { 3000 }), 5))
check("their front 1,475 from our T1: (1,475 + 500) / 325 + 1 s for the draw", near(W.DragSecs(1475), 1975 / 325 + 1), W.DragSecs(1475))

-- lane_push's schedule: waves every 30 s from 0:00 at each team's spawn end, 325 a second along the path. Bot lane: Radiant
-- spawns at -325, its T1 at 8,057 (25.8 s away); Dire spawns at 18,662, its T1 at 12,574 (18.7 s).
local bot = paths[3]
local tR = (8057 + 325) / 325
check("Radiant at 0:10: the first wave reaches its T1 at 25.8 s", near(P.NextArrival(bot, 2, 8057, 10), tR), P.NextArrival(bot, 2, 8057, 10))
check("Radiant at 0:30: that wave has passed, the next arrives 30 s later", near(P.NextArrival(bot, 2, 8057, 30), 30 + tR), P.NextArrival(bot, 2, 8057, 30))
check("Dire at 0:20: its second wave reaches its T1 at 48.7 s", near(P.NextArrival(bot, 3, 12574, 20), 30 + (18662 - 12574) / 325), P.NextArrival(bot, 3, 12574, 20))
local pt = P.PointAt(bot, 8957)
local x, y = pt[1], pt[2]
local s, d = P.Project(bot, x, y)
check("PointAt lies on the path at its distance (900 past Radiant's bot T1)", math.abs(s - 8957) < 1 and d < 1, s .. " " .. d)
local t1, dir = P.OwnT1(bot, 3)
check("Dire's T1 on the bot path and its sign towards Radiant's", t1 == 12574 and dir == -1)
finish()
