-- The pick table (states/pick_table): the kinds of lane creep target each position goes for, in order, with the claim on each,
-- and the picker (states/lane_pick Choose) walking the order it is given.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Table = require("bots/FunLib/humaniser/states/pick_table")
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

local function target(kind, eta, walk, dies)
	return { creep = {}, kind = kind, eta = eta, due = eta, walk = walk or 0, dies = dies or math.huge, ranged = false }
end

-- The contract: each position's order and claims, written out. A re-ranking shows up as a diff of these lists.
do
	local core = { "lasthit", "pre_hit", "deny", "idle_swing" }
	local support = { "lasthit", "deny", "idle_swing" }
	local coreClaims = "lasthit=all,pre_hit=all,deny=unattempted,idle_swing=all"
	local supportClaims = "lasthit=unclaimed,pre_hit=none,deny=all,idle_swing=all"
	for pos = 1, 5 do
		local want = pos <= 3 and core or support
		check("order, position " .. pos, table.concat(Table.Order(pos), ",") == table.concat(want, ","), table.concat(Table.Order(pos), ","))
		local claims = {}
		for _, kind in ipairs({ "lasthit", "pre_hit", "deny", "idle_swing" }) do table.insert(claims, kind .. "=" .. Table.ClaimOf(kind, pos)) end
		check("claims, position " .. pos, table.concat(claims, ",") == (pos <= 3 and coreClaims or supportClaims), table.concat(claims, ","))
	end
	check("order: an unknown position takes position 1's", table.concat(Table.Order(nil), ",") == table.concat(core, ","))
	check("is core: positions 1-3 only, an unknown one is not", Table.IsCore(1) and Table.IsCore(3) and not Table.IsCore(4) and not Table.IsCore(5) and not Table.IsCore(nil))
end

-- The order comes from the table: with deny before lasthit the picker takes the deny, with today's order the last hit.
do
	local lh, dn = target("lasthit", 0.5), target("deny", 0.1)
	local today = Table.Order(1)
	local denyFirst = { "deny", "lasthit", "pre_hit", "idle_swing" }
	check("order: today's order takes the last hit over a deny due sooner", Pick.Choose({ dn, lh }, nil, nil, nil, nil, nil, today) == lh)
	check("order: deny first takes the deny over a last hit", Pick.Choose({ lh, dn }, nil, nil, nil, nil, nil, denyFirst) == dn)
	check("order: deny first, no deny on offer, the last hit", Pick.Choose({ lh }, nil, nil, nil, nil, nil, denyFirst) == lh)

	-- A wait is left or kept by rank.
	check("order: today's order, a deny wait is left for a last hit", Pick.Choose({ dn, lh }, dn, nil, nil, nil, nil, today) == lh)
	check("order: deny first, a deny wait is not left for a last hit", Pick.Choose({ dn, lh }, dn, nil, nil, nil, nil, denyFirst) == dn)
	check("order: today's order, a last-hit wait is kept over a deny", Pick.Choose({ dn, lh }, lh, nil, nil, nil, nil, today) == lh)
	check("order: deny first, a last-hit wait is left for a deny", Pick.Choose({ dn, lh }, lh, nil, nil, nil, nil, denyFirst) == dn)

	-- The pre-hit sits where the order puts it.
	local pre = target("pre_hit", 0)
	check("order: the pre-hit beats a deny and loses to a last hit", Pick.Choose({ dn }, nil, nil, pre, nil, nil, today) == pre
		and Pick.Choose({ dn, lh }, nil, nil, pre, nil, nil, today) == lh)
	check("order: deny first, the deny beats the pre-hit", Pick.Choose({ dn }, nil, nil, pre, nil, nil, { "deny", "pre_hit", "lasthit" }) == dn)
end

-- A kind a position has no rank for is never chosen for it, even alone.
do
	local lh, dn, pre = target("lasthit", 0.2), target("deny", 0.2), target("pre_hit", 0)
	local idleCalls = 0
	local idle = function() idleCalls = idleCalls + 1 return target("prehit", 0) end
	local noDeny, noLastHit = { "lasthit", "pre_hit" }, { "deny", "idle_swing" }
	check("unranked: a deny alone is not chosen without a deny rank", Pick.Choose({ dn }, nil, nil, nil, nil, nil, noDeny) == nil)
	check("unranked: a last hit alone is not chosen without a last-hit rank", Pick.Choose({ lh }, nil, nil, nil, nil, nil, noLastHit) == nil)
	check("unranked: a pre-hit is not chosen without a pre-hit rank", Pick.Choose({}, nil, nil, pre, nil, nil, noLastHit) == nil)
	check("unranked: the idle swing is not asked without an idle_swing rank", Pick.Choose({}, nil, nil, nil, idle, nil, noDeny) == nil and idleCalls == 0)
	check("unranked: a support's order has no pre-hit; its pick is a deny", Pick.Choose({ dn }, nil, nil, pre, nil, nil, Table.Order(5)) == dn)
	check("idle swing: asked only once nothing else is chosen and no wait is held", Pick.Choose({}, nil, nil, nil, idle, nil, Table.Order(5)) ~= nil
		and idleCalls == 1 and Pick.Choose({ lh }, nil, nil, nil, idle, nil, Table.Order(5)) == lh and idleCalls == 1)
end

finish()
