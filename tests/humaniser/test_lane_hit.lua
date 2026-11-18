-- Plan trade-from-the-stand probe 3f (Ours.LaneHit): when a hero hit would cost a last hit or deny on offer (states/lane_hit Due),
-- and where it ranks among the lane's own picks (Answer).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Hit = require("bots/FunLib/humaniser/states/lane_hit")

local function target(kind, due, walk, dies)
	return { creep = {}, kind = kind, eta = math.max(due, walk or 0), due = due, walk = walk or 0, dies = dies or math.huge, ranged = false }
end

-- Our next swing is free 1.5 s after a hit now: a creep due inside that is lost to the hit, one due after it is not.
do
	local soon, later = target("lasthit", 1.2), target("deny", 1.6)
	check("due: a last hit due before the cycle ends blocks the hit", Hit.Due({ later, soon }, nil, 1.5) == soon)
	check("due: a deny due after the cycle ends does not", Hit.Due({ later }, nil, 1.5) == nil)
	-- The walk to the creep comes after the hit too: due 1.8 s with 0.5 s to walk is late from a hit with a 1.5 s cycle.
	local walked = target("lasthit", 1.8, 0.5, 5)
	check("due: a walk to the creep adds to the cycle", Hit.Due({ walked }, nil, 1.5) == walked)
end

-- Only creeps the body would take count: one the claims give another laner, or one dead before we could reach it, costs nothing.
do
	local theirs, doomed = target("deny", 0.3), target("lasthit", 0.2, 0.9, 1.0)
	local notTheirs = function(t) return t ~= theirs end
	check("due: a creep that is not mine does not block", Hit.Due({ theirs }, notTheirs, 1.5) == nil)
	check("due: a creep dead before the walk and swing does not block", Hit.Due({ doomed }, nil, 1.5) == nil)
end

-- The pick order: everything the lane holds comes first; the hit's own costs (their tower, creep aggro) are read last.
do
	local clear = { trade = false, leaving = false, pre = false, walkIn = false, due = false, idle = false, tower = false, aggro = "prime" }
	local function with(k, v)
		local f = {}
		for a, b in pairs(clear) do f[a] = b end
		f[k] = v
		return f
	end
	check("answer: nothing due and no aggro drawn, the hero is hit", Hit.Answer(clear) == "hit")
	check("answer: a due creep holds the hit even with no aggro to draw", Hit.Answer(with("due", true)) == "due")
	check("answer: the idle swing outranks the hero hit", Hit.Answer(with("idle", true)) == "idle")
	check("answer: a hit that would draw the creeps waits", Hit.Answer(with("aggro", "step_out")) == "aggro")
	check("answer: inside the aggro cooldown the hero is hit", Hit.Answer(with("aggro", "attack")) == "hit")
	local busy = with("trade", true)
	busy.due = true
	check("answer: an open trade episode keeps the hero, whatever is due", Hit.Answer(busy) == "trade")
end

finish()
