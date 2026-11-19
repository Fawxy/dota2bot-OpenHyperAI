-- The trip table (states/trip_table): which trips each position does and in what order, the pull's lifted place, and the
-- helpers the chooser and the jobs read.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Table = require("bots/FunLib/humaniser/states/trip_table")

local function never() return false end
local function pullLifted(kind) return kind == "pull" end

-- The contract: each position's order written out. A re-ranking shows up as a diff of these lists.
do
	local want = {
		[1] = { plain = "camp", lifted = "camp" },
		[2] = { plain = "camp", lifted = "camp" },
		[3] = { plain = "pull,pullfarm,camp", lifted = "pull,pullfarm,camp" },
		[4] = { plain = "rune,stack,pull,pullfarm", lifted = "pull,rune,stack,pullfarm" },
		[5] = { plain = "stack,pull,pullfarm,rune", lifted = "pull,stack,pullfarm,rune" },
	}
	for pos = 1, 5 do
		local plain = table.concat(Table.Order(pos, never), ",")
		local lifted = table.concat(Table.Order(pos, pullLifted), ",")
		check("order, position " .. pos, plain == want[pos].plain, plain)
		check("order lifted, position " .. pos, lifted == want[pos].lifted, lifted)
	end
end

do
	check("an undefined position has no trips", #Table.Order(nil, never) == 0 and #Table.Order(nil, pullLifted) == 0)
	check("a position outside 1-5 has no trips", #Table.Order(6, never) == 0 and #Table.Order(0, never) == 0)
	check("an undefined position does no trip", not Table.Does("camp", nil) and Table.RankOf("pull", nil, true) == nil)
end

-- The lifted column applies only to a row that has one, and only when asked for.
do
	check("pull: lifted ranks above its usual place", Table.RankOf("pull", 5, true) < Table.RankOf("pull", 5, false))
	check("a row without a lifted column ignores the flag", Table.RankOf("stack", 5, true) == Table.RankOf("stack", 5, false))
	check("the lifted pull is above every other trip of a position", Table.RankOf("pull", 4, true) < Table.RankOf("rune", 4))
	check("a position that never does a trip has no lifted place either", Table.RankOf("pull", 2, true) == nil)
end

-- Which positions ever do each trip.
do
	local function who(kind)
		local out = {}
		for pos = 1, 5 do if Table.Does(kind, pos) then table.insert(out, pos) end end
		return table.concat(out, ",")
	end
	check("pull: positions 3-5", who("pull") == "3,4,5", who("pull"))
	check("pullfarm: positions 3-5", who("pullfarm") == "3,4,5", who("pullfarm"))
	check("rune: positions 4-5", who("rune") == "4,5", who("rune"))
	check("stack: positions 4-5", who("stack") == "4,5", who("stack"))
	check("camp: positions 1-3", who("camp") == "1,2,3", who("camp"))
end
finish()
