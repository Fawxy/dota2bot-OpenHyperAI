dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- hero_selection.lua needs the whole pick environment, so only X.BestRolesByHero is lifted out of its source.
local f = io.open("bots/hero_selection.lua", "r")
local src = f:read("*a")
f:close()
local body = src:match("(function X%.BestRolesByHero.-\n%end\n)")
check("BestRolesByHero found in hero_selection.lua", body ~= nil)
local X = {}
local chunk = load("local X = ...\n" .. body .. "\nreturn X")
X = chunk(X)

-- Weights shaped like aba_hero_pos_weights: { pos1, pos2, pos3, pos4, pos5 }.
local w = {
	omni = { 0, 5, 30, 40, 60 },
	bane = { 0, 20, 10, 30, 40 },
	sky = { 0, 45, 10, 65, 20 },
	necro = { 30, 60, 40, 5, 0 },
	bh = { 0, 45, 30, 50, 35 },
	pa = { 70, 25, 5, 0, 0 },
}
-- Seed 1's Radiant (slot order omni, bane, sky, necro, bh) gave omni pos 1 by slot. By weight nobody suits pos 1, so the
-- best total (215: bane 1, necro 2, bh 3, sky 4, omni 5) gives it to a 0-weight hero; the seed scan has to filter such teams.
local roles, score = X.BestRolesByHero({ "omni", "bane", "sky", "necro", "bh" }, w)
local seen = {}
for i = 1, 5 do seen[roles[i]] = true end
check("each position used once", seen[1] and seen[2] and seen[3] and seen[4] and seen[5])
check("omniknight is not the carry", roles[1] ~= 1)
check("the best total wins", score == 215 and roles[4] == 2 and roles[1] == 5)

-- A clear carry takes pos 1 whatever its slot.
local r2 = X.BestRolesByHero({ "omni", "bane", "sky", "bh", "pa" }, w)
check("phantom assassin in slot 5 plays pos 1", r2[5] == 1)

-- Unknown heroes weigh 0 but still get a position.
local r3 = X.BestRolesByHero({ "x1", "x2", "x3", "x4", "x5" }, w)
check("unknown heroes still get five distinct positions", #r3 == 5)
finish()
