-- The trip table (states/trip_table): which trips each position does and in what order, and the helpers the
-- chooser and the jobs read.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Table = require("bots/FunLib/humaniser/states/trip_table")

-- The contract: each position's order written out. A re-ranking shows up as a diff of these lists.
do
	local want = { [1] = "creep,aggro", [2] = "creep,aggro", [3] = "creep,aggro", [4] = "rune,stack,pull,deny,creep", [5] = "stack,pull,rune,deny,creep" }
	for pos = 1, 5 do
		local order = table.concat(Table.Order(pos), ",")
		check("order, position " .. pos, order == want[pos], order)
	end
end

do
	check("an undefined position has no trips", #Table.Order(nil) == 0)
	check("a position outside 1-5 has no trips", #Table.Order(6) == 0 and #Table.Order(0) == 0)
	check("an undefined position does no trip", not Table.Does("pull", nil) and Table.RankOf("pull", nil) == nil)
end

-- Which positions ever do each trip.
do
	local function who(kind)
		local out = {}
		for pos = 1, 5 do if Table.Does(kind, pos) then table.insert(out, pos) end end
		return table.concat(out, ",")
	end
	check("pull: positions 4-5", who("pull") == "4,5", who("pull"))
	check("rune: positions 4-5", who("rune") == "4,5", who("rune"))
	check("stack: positions 4-5", who("stack") == "4,5", who("stack"))
	check("deny: positions 4-5", who("deny") == "4,5", who("deny"))
	check("creep: every position, the supports' cell above the cores'", who("creep") == "1,2,3,4,5" and Table.RankOf("creep", 4) > Table.RankOf("creep", 2), who("creep"))
	check("creep: a support is outranked, a core is not; the deny is nobody's to yield", Table.Outranked("creep", 5) and not Table.Outranked("creep", 1) and not Table.Outranked("deny", 4))
end
finish()
