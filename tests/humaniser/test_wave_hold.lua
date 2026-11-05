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
-- The user's rule (06/11/2026): the hold keeps their creeps just outside tower fire. Our T1 fires to its range plus both hull
-- radii (fallback 700 + 144 + 16 = 860 to a creep's centre); a start needs their front 50 past that.
check("tower reach from the fallbacks: 700 + 144 + 16", W.EffReach() == 860)
check("tower reach from the API's values", W.EffReach(700, 120, 20) == 840)
-- hschk2 8:18-8:25 top: Pudge held at 756 with their creeps at 727-795 from our T1; the tower shot the one at 795 dead.
check("hschk2: their front 792 is inside tower fire: late, no start", W.Read({ 792, 830, 1188 }, {}, 900) == "late")
check("their front 905, inside the 910 floor: late", W.Read({ 905, 950 }, {}, 900) == "late")
local r3 = W.Read({ 920, 950 }, {}, 900)
check("their front 920, outside the 910 floor: a hold", type(r3) == "table" and r3.front == 920, r3)
check("a smaller reach from the API moves the floor: front 880 starts under 820", type(W.Read({ 880, 950 }, {}, 900, {}, 820)) == "table")
-- obs0611 marks 4 and 5 (Luna 1:48 bot, Sniper 2:35 mid): a lone creep of ours fighting inside our T1's range (666, 512) is not
-- our wave. Their wave stood 740-900 out there, inside tower fire by the rule above, so the shapes here sit further out.
local m4 = W.Read({ 960, 970, 975, 2200, 2230 }, { 666 }, 900, { true })
check("mark 4 shape: our lone creep fighting at 666 inside the T1's range does not keep the hold off", type(m4) == "table" and m4.front == 960 and m4.n == 5, m4)
local m5 = W.Read({ 930, 950, 970, 1338 }, { 512 }, 1300, { true })
check("mark 5 shape: our lone ranged creep fighting at 512 does not keep the hold off", type(m5) == "table" and m5.front == 930, m5)
check("one of ours at the T1's range edge (700) fighting their wave still counts as our wave", W.Read({ 950, 990 }, { 700 }, 900, { true }) == "ours")
-- hdchk1 0:27 top: our fresh wave walking out under our T1 while theirs walks in 2,190 out is our wave, not gone.
check("our fresh wave walking out under our T1 (not fighting): our wave", W.Read({ 2190, 2290 }, { -205, -8, 115, 215 }, 900, { false, false, false, false }) == "ours")

-- The hold point: the lane target, or their front when nearer, never inside tower fire + 50 (910 on the fallbacks).
check("hold point, side lane: the target 900 is inside the 910 floor, so 910", W.HoldAt(900, 1500) == 910)
check("hold point, mid: their front past the target 1,300, the target", W.HoldAt(1300, 1500) == 1300)
check("hold point, mid: their front 1,000 inside the target, at their front", W.HoldAt(1300, 1000) == 1000)
check("hold point under the API's reach 840: floor 890", W.HoldAt(900, 960, 840) == 900 and W.HoldAt(1300, 895, 840) == 895 and W.HoldAt(1300, 880, 840) == 890)
-- The hold takes their aggro: a draw once their front is within 1 s' walk (325) of the hold point, the core on it, none on it yet.
check("hold draw: their front 1,200 walking to the hold point 910, core on it: draw", W.DrawNow(1200, 910, 100, 0))
check("hold draw: their front 1,400 (over 1 s out): not yet", not W.DrawNow(1400, 910, 100, 0))
check("hold draw: a creep of theirs already on the core: no draw", not W.DrawNow(1100, 910, 100, 1))
check("hold draw: the core 500 off the hold point: no draw", not W.DrawNow(1100, 910, 500, 0))
-- An enemy hero pushing the held spot inside the floor (reach 860 + 50) ends the hold `unsafe` (hschk3 Sniper 7:06 at 575)...
-- Only once their front is within 1 s' walk of the floor (910 + 325): further out the hold runs on from the pushed spot.
check("unsafe: the hold spot pushed by a hero to 575, their front 1,100 (within 1,235)", W.Unsafe("hold", "hero", 575, 860, 1100))
check("hschk4 Zeus 5:05 mid: pushed by Sniper to 750 with their front 1,440 out: the hold runs on", not W.Unsafe("hold", "hero", 750, 860, 1440))
check("not unsafe: pushed by a hero but still at 950", not W.Unsafe("hold", "hero", 950, 860, 1000))
check("not unsafe: inside the floor for a creep ring, not a hero", not W.Unsafe("hold", "creep", 575, 860, 1000))
-- The creeps of ours that do not end an attempt as met: those fighting in the clash at the start, not our next wave.
check("in the clash: one of ours fighting 300 behind their rear", W.InClash(1500, true, 1800))
check("not in the clash: our next wave walking up 3,000 behind our T1", not W.InClash(-3000, false, 1800))
check("not in the clash: one of ours fighting 2,000 past their rear (another fight)", not W.InClash(3900, true, 1800))

-- The forecast start reads lane_push's run: their front inside our T1's fire (860) within 8 s while our wave still fights.
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
	check("forecast: 2 weak creeps of ours v 4 at 900: their front inside our T1's fire (860) within 8 s", fc ~= nil and fc > 0 and fc <= 8, fc)
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
	-- Dire's view: its bot T1 at 12,574, distances towards Radiant's are negative path steps (sign -1).
	local D1 = 12574
	local dire = { { t = 150, front = { [2] = D1 - 1200 } }, { t = 155, front = { [2] = D1 - 650 } } }
	check("forecast, Dire: Radiant's front 650 from Dire's T1 (inside its fire) at 5 s", W.TowerIn(dire, D1, -1, 2, 150) == 5, W.TowerIn(dire, D1, -1, 2, 150))
	local direOut = { { t = 150, front = { [2] = D1 - 1200 } }, { t = 155, front = { [2] = D1 - 870 } } }
	check("forecast, Dire: Radiant's front 870 out, outside tower fire (860): no start", W.TowerIn(direOut, D1, -1, 2, 150) == nil)
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
-- The user's rule (06/11/2026, hschk3 1:45): the drag takes their wave through our T1's fire only to meet our creeps behind it
-- and out of its reach (860 + 50 on the fallbacks).
check("the drag point sits out of our T1's fire: 910 behind it", W.BehindAt() == 910 and W.BehindAt(400) == 500)
check("their front 1,500 to the drag point 910 behind: (1,500 + 910) / 325 + 1", near(W.DragSecs(1500, 910), 2410 / 325 + 1))
-- Luna's shape: our creeps back from the pull walk in at 300 from our T1 while their wave stands 1,500 out; our next wave far off.
local luna = W.OursAtBehind({ 300, 340, -5000 }, 910, 1500)
check("hschk3 1:45: our pulled creeps between the drag point and their front: they meet in tower fire now (0 s)", luna == 0, luna)
check("hschk3 1:45: so the threatened core holds at the hold point, no drag", W.Choose(true, 20, W.DragSecs(1500, 910), luna) == "hold")
local far = W.OursAtBehind({ -5000, -5100, 2600 }, 910, 1500)
check("only our next wave 5,000 behind our T1 (and a fight past their front): (5,000 - 910) / 325 s", near(far, 4090 / 325), far)
check("then the drag goes, their wave meeting ours out of our T1's reach", W.Choose(true, 20, W.DragSecs(1500, 910), far) == "drag")

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
