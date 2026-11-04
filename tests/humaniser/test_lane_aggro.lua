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

-- The feed tilts the clash toward us: not when it already sits near our tower or is coming in.
check("clash holding mid-lane: feed", A.FeedWanted({ state = "HOLD", q = 0.5 }))
check("clash moving out: feed", A.FeedWanted({ state = "OUT", q = 0.35 }))
check("clash coming in: no feed", not A.FeedWanted({ state = "IN", q = 0.6 }))
check("clash already by our tower: no feed", not A.FeedWanted({ state = "HOLD", q = 0.2 }))
check("no reading: no feed", not A.FeedWanted(nil))

-- The drop (attack order on our ranged creep) comes once a drawn creep reaches it, not before the walk has pulled them.
check("a drawn creep beside our ranged creep after the walk: drop", A.DropNow(1.0, 2, 150))
check("beside it but too early (the creeps would turn back onto our melee): wait", not A.DropNow(0.5, 2, 150))
check("still far from it: keep walking", not A.DropNow(1.0, 2, 600))
check("the drop is never later than DropBy, near or not", A.DropNow(1.9, 1, 900))
finish()
