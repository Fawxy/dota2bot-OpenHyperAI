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

-- The feed tilts the clash toward the lane's target point (900 from our T1 on a side lane): it fires when the clash sits or is
-- heading beyond it, including a clash coming back in from beyond it, and not once the clash is ours.
check("clash in the middle (2000 out), holding: feed", A.FeedWanted({ own = 2000, move = 0 }, 900))
check("clash at the target but our bigger wave will push it out: feed", A.FeedWanted({ own = 900, move = 400 }, 900))
check("clash coming back in from beyond the target: still feed", A.FeedWanted({ own = 1600, move = -300 }, 900))
check("clash at the target and holding: no feed", not A.FeedWanted({ own = 950, move = 50 }, 900))
check("clash inside the target, coming in: no feed", not A.FeedWanted({ own = 600, move = -200 }, 900))
check("no reading: no feed", not A.FeedWanted(nil, 900))
check("mid's target sits further out (our high-ground edge) than a side lane's", A.TargetOf(require(GetScriptDirectory() .. "/ts_libs/dota/index").Lane.Mid) > A.TargetOf(require(GetScriptDirectory() .. "/ts_libs/dota/index").Lane.Bot))

-- The tower move orders just past their creeps, never from inside the tower's reach.
local x, y = A.TowerPoint(0, 0, 500, 0)
check("their creeps 500 from the tower: order 900 out on their line", x == 900 and y == 0)
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
finish()
