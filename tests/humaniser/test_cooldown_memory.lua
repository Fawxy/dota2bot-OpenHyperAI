dofile(HARNESS_DIR .. "/lane_world.lua")

local function fresh(laneFight)
	ResetWorld()
	FreshHumaniser({ Enable = true, LaneFight = laneFight or {} })
	RANDOM_FRACTION = 0.5
	return require("bots/FunLib/humaniser/cooldown_memory")
end

do
	local M = fresh()
	check("ult remembered at skill 0 (0.5 < 0.6)", M.Record(1, 6, "ult", "ult", 100, 0, 10))
	check("key not remembered at skill 0 (0.5 >= 0.35)", not M.Record(1, 6, "key", "key", 10, 0, 10))
	check("key remembered at skill 1", M.Record(1, 6, "key", "key", 10, 1, 10))
	check("other not remembered at skill 0", not M.Record(1, 6, "other", "other", 10, 0, 10))
	local ready, conf = M.ProbablyReady(1, 6, "other", true, 11, 0)
	check("a rejected cast leaves no memory", ready and conf == 0)
	check("other remembered at skill 1 (0.5 < 0.6)", M.Record(1, 6, "other", "other", 10, 1, 10))
	check("only remembered casts count", M.Count(1, 10) == 3)
end

do
	local M = fresh()
	RANDOM_FRACTION = 0
	M.Record(1, 6, "a", "ult", 100, 0, 10)
	check("skill 0 low end is 0.65 cd", near(select(2, M.ProbablyReady(1, 6, "a", true, 74.9, 0)), 1)
		and not M.ProbablyReady(1, 6, "a", true, 74.9, 0))
	check("skill 0 ready at 0.65 cd", (M.ProbablyReady(1, 6, "a", true, 75.1, 0)))
	local draws = { 0, 1 }
	local real = RandomFloat
	RandomFloat = function(a, b) return a + (b - a) * table.remove(draws, 1) end
	M.Record(1, 6, "b", "ult", 100, 0, 10)
	RandomFloat = real
	check("skill 0 high end is 1.35 cd", not M.ProbablyReady(1, 6, "b", true, 144.9, 0)
		and M.ProbablyReady(1, 6, "b", true, 145.1, 0))
	RANDOM_FRACTION = 0
	M.Record(1, 6, "c", "ult", 100, 1, 10)
	check("skill 1 low end is 0.95 cd", not M.ProbablyReady(1, 6, "c", true, 104.9, 1)
		and M.ProbablyReady(1, 6, "c", true, 105.1, 1))
end

do
	local M = fresh()
	RANDOM_FRACTION = 0.5
	M.Record(1, 6, "a", "ult", 100, 0, 0)
	local est = 100
	check("not ready just before estimate", not M.ProbablyReady(1, 6, "a", true, est - 0.1, 0))
	local ready, conf = M.ProbablyReady(1, 6, "a", true, est - 0.1, 0)
	check("confidence is 1 before estimate", conf == 1)
	ready, conf = M.ProbablyReady(1, 6, "a", true, est + 10, 0)
	check("ready with half confidence 10s into a 20s window", ready and near(conf, 0.5))
	ready, conf = M.ProbablyReady(1, 6, "a", true, est + 30, 0)
	check("confidence floors at 0 once forgotten", ready and conf == 0)
	check("forgotten entries stop counting", M.Count(1, est + 19) == 1 and M.Count(1, est + 21) == 0)
end

do
	local M = fresh()
	local ready, conf = M.ProbablyReady(1, 6, "x", true, 5, 0.5)
	check("unseen ability is ready with confidence 0", ready and conf == 0)
	M.Record(1, 6, "x", "ult", 100, 1, 0)
	ready, conf = M.ProbablyReady(1, 6, "x", false, 5, 1)
	check("unlearned ability is not ready, confidence 1", not ready and conf == 1)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 20, 1, 0)
	check("one of two key abilities down", near(M.KeyThreatsDown(1, 6, { "stun", "hex" }, 5, 1), 0.5))
	check("no learned key abilities gives 0", M.KeyThreatsDown(1, 6, {}, 5, 1) == 0)
	check("fraction drops when cooldown is believed over", M.KeyThreatsDown(1, 6, { "stun", "hex" }, 60, 1) == 0)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 20, 1, 0)
	check("observer 2 does not see observer 1's memory", M.ProbablyReady(2, 6, "stun", true, 5, 1) and M.Count(2, 5) == 0)
	M.Share(1, { 2 }, 6, "stun", 1)
	check("Share passes the entry on", not M.ProbablyReady(2, 6, "stun", true, 5, 1) and M.Count(2, 5) == 1)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 20, 1, 0)
	RANDOM_FRACTION = 0.2
	M.Share(1, { 2 }, 6, "stun", 0)
	check("share dropped at skill 0 (0.2 < 0.3)", M.Count(2, 5) == 0)
	M.Share(1, { 2 }, 6, "stun", 1)
	check("share kept at skill 1 (0.2 >= 0.05)", M.Count(2, 5) == 1)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 20, 1, 0)
	M.Record(1, 6, "stun", "key", 20, 1, 100)
	check("re-recording overwrites rather than duplicates", M.Count(1, 100) == 1)
	check("re-recorded entry uses the new cast", not M.ProbablyReady(1, 6, "stun", true, 110, 1))
	M.Reset()
	check("Reset clears everything", M.Count(1, 100) == 0)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 100, 1, 0)
	check("remembered at skill 1", not M.ProbablyReady(1, 6, "stun", true, 10, 1))
	check("recast that fails its roll at skill 0 is forgotten", not M.Record(1, 6, "stun", "key", 100, 0, 20))
	local ready, conf = M.ProbablyReady(1, 6, "stun", true, 25, 1)
	check("forgotten cast is assumed ready", ready and conf == 0 and M.Count(1, 25) == 0)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 20, 1, 0)
	RANDOM_FRACTION = 0.5
	M.Share(1, { 2 }, 6, "stun", 0)
	-- skill 0 window is 20s; the sharer (skill 1) alone would still remember at est + 30
	local est = 20
	local ready, conf = M.ProbablyReady(2, 6, "stun", true, est + 10, 1)
	check("shared entry uses the recipient's forget window", ready and near(conf, 0.5))
	check("Count and ProbablyReady agree on forgotten", M.Count(2, est + 19) == 1 and M.Count(2, est + 21) == 0
		and select(2, M.ProbablyReady(2, 6, "stun", true, est + 21, 1)) == 0)
end

do
	local M = fresh()
	M.Record(1, 6, "stun", "key", 20, 1, 0)
	M.Share(1, { 1, 2 }, 6, "stun", 1)
	check("Share skips self", M.Count(1, 5) == 1 and M.Count(2, 5) == 1)
	M.Record(3, 6, "stun", "key", 20, 1, 50)
	M.Share(1, { 3 }, 6, "stun", 1)
	check("Share keeps a fresher entry on the recipient", not M.ProbablyReady(3, 6, "stun", true, 60, 1))
end

finish()
