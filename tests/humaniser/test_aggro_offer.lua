dofile(HARNESS_DIR .. "/lane_world.lua")
-- The draw's offer (aggro_offer.ts): the spots, what the draw gives up and the go rule's checks, as pure functions.
LaneFresh({ Enable = true }, { skill = 1 })
local A = require("bots/FunLib/humaniser/aggro_offer")

do -- the spots
	local s = A.DrawSpot({ x = 1000, y = 0 }, { x = 0, y = 0 }, 450)
	check("draw spot: at reach from the creep on the line to the hero", near(s.x, 450) and near(s.y, 0), s.x)
	local own = A.DrawSpot({ x = 300, y = 0 }, { x = 0, y = 0 }, 450)
	check("draw spot: a hero within reach stays put", near(own.x, 300))
	local h = A.HandSpot({ x = -500, y = 0 }, { x = 0, y = 0 }, 250)
	check("hand-over spot: behind our ranged creep, away from the clash", near(h.x, -750) and near(h.y, 0), h.x)
end

local function t(kind, due, o)
	local r = { kind = kind, due = due, ranged = false, drawn = false, undrawn = false, feed = false }
	for k, v in pairs(o or {}) do r[k] = v end
	return r
end

do -- given up: what the draw would cost, against the rule as first written
	local ts = {
		t("lasthit", 1.0), -- their creep left at the clash: missed
		t("lasthit", 1.0, { drawn = true, ranged = true }), -- drawn ranged: the creep row's hand-over
		t("lasthit", 1.0, { drawn = true }), -- drawn melee: no row above takes it yet
		t("deny", 1.0), -- every attacker drawn: delayed, not lost
		t("deny", 1.0, { undrawn = true }), -- an enemy hero or undrawn creep keeps it on time
		t("deny", 1.0, { feed = true, undrawn = true }), -- our ranged creep, the feed
		t("lasthit", 4.0), -- after the window
	}
	local g = A.GivenUp(ts, 3.0)
	check("given up: all but the feed inside the window", g.all == 5, g.all)
	check("given up: missed are the undrawn last hit, the drawn melee and the deny kept on time", g.miss == 3, g.miss)
	check("given up: drawn ranged and melee counted apart", g.dr == 1 and g.dm == 1, g.dr .. " " .. g.dm)
end

do -- the checks, in order
	local ok = { k = "dn", walk = 0.5, onR = 0, fh = 128, rh = 128, seen = 1, tw = 500, covering = 0, deadly = false, miss = 0 }
	check("checks: a clean read fails none", #A.Checks(ok) == 0)
	local bad = { k = "dn", walk = 1.5, onR = 2, fh = 0, rh = 128, seen = 0, tw = 50, covering = 1, deadly = true, miss = 1, sinceHero = 1 }
	local got = table.concat(A.Checks(bad), ",")
	check("checks: every one fails in s6b's order", got == "onr,due,far,unseen,etower,covered,danger,up,cd", got)
	local hg = { k = "hg", walk = 0.5, onR = 2, fh = 256, rh = 128, seen = 1, covering = 0, deadly = false, miss = 0 }
	check("checks: their creeps on our ranged creep do not hold the high-ground case back; no tower near is no tower check", #A.Checks(hg) == 0, table.concat(A.Checks(hg), ","))
end

finish()
