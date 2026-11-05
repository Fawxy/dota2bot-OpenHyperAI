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
check("their front already in our T1's range: late", W.Read({ 600, 700 }, {}, 900) == "late")
check("their wave still beyond the stretch (2,500 past our T1 on a side lane): none", W.Read({ 3000, 3100 }, {}, 900) == "none")
check("mid's target sits further out, so the same wave is in its stretch", type(W.Read({ 2700, 2800 }, {}, 1300)) == "table")
check("one creep is not a wave", W.Read({ 1500 }, {}, 900) == "none")

-- The branch: a threat drags only when our next wave is not near and the drag ends before it arrives behind our T1.
check("no threat: hold", W.Choose(false, 30, 5, 30) == "hold")
check("threat, our next wave 8 s from the hold point: hold, the waves meet there", W.Choose(true, 8, 5, 20) == "hold")
check("threat, our wave 20 s off, the drag needs 6 s of 12: drag", W.Choose(true, 20, 6, 12) == "drag")
check("threat, the drag needs 11 s of 12 (inside the 2 s margin): hold", W.Choose(true, 20, 11, 12) == "hold")
check("their front 1,475 from our T1: (1,475 + 500) / 325 + 1 s for the draw", near(W.DragSecs(1475), 1975 / 325 + 1), W.DragSecs(1475))

-- lane_push's schedule: waves every 30 s from 0:00 at each team's spawn end, 325 a second along the path. Bot lane: Radiant
-- spawns at -325, its T1 at 8,057 (25.8 s away); Dire spawns at 18,662, its T1 at 12,574 (18.7 s).
local bot = paths[3]
local tR = (8057 + 325) / 325
check("Radiant at 0:10: the first wave reaches its T1 at 25.8 s", near(P.NextArrival(bot, 2, 8057, 10), tR), P.NextArrival(bot, 2, 8057, 10))
check("Radiant at 0:30: that wave has passed, the next arrives 30 s later", near(P.NextArrival(bot, 2, 8057, 30), 30 + tR), P.NextArrival(bot, 2, 8057, 30))
check("Dire at 0:20: its second wave reaches its T1 at 48.7 s", near(P.NextArrival(bot, 3, 12574, 20), 30 + (18662 - 12574) / 325), P.NextArrival(bot, 3, 12574, 20))
local x, y = P.PointAt(bot, 8957)
local s, d = P.Project(bot, x, y)
check("PointAt lies on the path at its distance (900 past Radiant's bot T1)", math.abs(s - 8957) < 1 and d < 1, s .. " " .. d)
local t1, dir = P.OwnT1(bot, 3)
check("Dire's T1 on the bot path and its sign towards Radiant's", t1 == 12574 and dir == -1)
finish()
