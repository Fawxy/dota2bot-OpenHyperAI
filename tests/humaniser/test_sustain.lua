-- Sustain (design 2026-11-19-sustain-design.md): Decide over plain inputs, one check per row of the design's section 6
-- table plus the rules it adds, case and control in one check, so a Decide that always answers none, or always the
-- first rule, fails every one. A hero of 600 HP and 300 mana; the kill line is the heal floor, 180, unless set.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })
local S = require("bots/FunLib/humaniser/sustain")
local decide = function(i) return S.Decide(i) end

local function merge(base, o)
	for k, v in pairs(o or {}) do base[k] = v end
	return base
end
local function item(o)
	return merge({ slot = 0, name = "x", charges = 1, hp = 0, mp = 0, dur = 0, breaks = false, tree = false, refill = false, share = false }, o)
end
local function tango(o) return item(merge({ slot = 1, name = "item_tango", charges = 3, hp = 112, dur = 16, tree = true, share = true }, o)) end
local function salve(o) return item(merge({ slot = 2, name = "item_flask", hp = 300, dur = 10, breaks = true }, o)) end
local function wand(o) return item(merge({ slot = 3, name = "item_magic_stick", hp = 120, mp = 120 }, o)) end
local function bottle(o) return item(merge({ slot = 4, name = "item_bottle", charges = 3, hp = 110, mp = 60, dur = 2.7, refill = true }, o)) end
local function clarity(o) return item(merge({ slot = 5, name = "item_clarity", mp = 150, dur = 25, breaks = true }, o)) end
local TREE = { d = 300, enemyD = 900 }
local SAFE = { x = 1, y = 2, walk = 3 }
local SHOP = { { name = "item_flask", cost = 110, hp = 400, mp = 0 }, { name = "item_tango", cost = 90, hp = 336, mp = 0 },
	{ name = "item_clarity", cost = 50, hp = 0, mp = 150 } }
local function inputs(o)
	return merge({ now = 100, hp = 600, hpMax = 600, mp = 300, mpMax = 300, items = {}, hitRecently = false, burst = 0, reach = 0,
		laneBurst = 100, regenLeft = 0, manaLeft = 0, gold = 0, shop = SHOP, home = 60, idle = false, atFountain = false, allies = {} }, o)
end
local function is(a, kind, name, reason)
	return a.kind == kind and (name == nil or a.name == name) and (reason == nil or a.reason == reason)
end

check("tango at 60% with a tree in reach: use; no tree: none",
	is(decide(inputs({ hp = 360, items = { tango() }, tree = TREE })), "use", "item_tango", "top_up")
		and is(decide(inputs({ hp = 360, items = { tango() } })), "none"))

check("a tree nearer the enemy than us is out of reach: none",
	is(decide(inputs({ hp = 360, items = { tango() }, tree = { d = 300, enemyD = 200 } })), "none"))

check("salve at 250 HP with a safe spot 3 s away: step out and use; hit recently: none; a tango ticks through the hit",
	is(decide(inputs({ hp = 250, items = { salve() }, safeSpot = SAFE })), "step_out_use", "item_flask", "top_up")
		and is(decide(inputs({ hp = 250, items = { salve() }, safeSpot = SAFE, hitRecently = true })), "none")
		and is(decide(inputs({ hp = 250, items = { tango() }, tree = TREE, hitRecently = true })), "use", "item_tango"))

check("salve at a safe spot already reached: use in place",
	is(decide(inputs({ hp = 250, items = { salve() }, safeSpot = { x = 1, y = 2, walk = 0 } })), "use", "item_flask"))

check("wand at lethal under attack: use; not under attack: kept",
	is(decide(inputs({ hp = 150, burst = 200, reach = 1, hitRecently = true, items = { wand() } })), "use", "item_magic_stick", "survive")
		and decide(inputs({ hp = 250, burst = 200, reach = 1, items = { wand() } })).name ~= "item_magic_stick")

check("rule 1 takes the instant item that restores most, and only if it lifts us over the burst (else D1 is retreat's)",
	is(decide(inputs({ hp = 150, burst = 260, reach = 1, hitRecently = true, items = { wand({ hp = 60 }), item({ slot = 6, name = "item_faerie_fire", hp = 85 }) } })),
		"none")
		and is(decide(inputs({ hp = 150, burst = 220, reach = 1, hitRecently = true, items = { wand({ hp = 60 }), item({ slot = 6, name = "item_faerie_fire", hp = 85 }) } })),
			"use", "item_faerie_fire", "survive"))

check("at 150 HP the tangos reach the kill line: stay and use; no tree: home, nothing spent",
	is(decide(inputs({ hp = 150, items = { tango() }, tree = TREE })), "use", "item_tango")
		and is(decide(inputs({ hp = 150, items = { tango() } })), "home", nil, "cannot_stay"))

check("the kill line rises with the lane's burst: 350 HP and a salve stays at burst 100, goes home at burst 800",
	is(decide(inputs({ hp = 350, items = { salve({ hp = 200 }) }, safeSpot = SAFE })), "step_out_use")
		and is(decide(inputs({ hp = 350, laneBurst = 800, items = { salve({ hp = 200 }) }, safeSpot = SAFE })), "home"))

check("cannot stay, gold covers a tango and the courier beats the trip: buy and wait at the safe spot; no courier: home",
	(function()
		local a = decide(inputs({ hp = 150, gold = 200, courier = { eta = 20 }, safeSpot = SAFE }))
		return is(a, "buy", "item_tango", "cannot_stay") and a.at.x == 1
	end)()
		and is(decide(inputs({ hp = 150, gold = 200, safeSpot = SAFE })), "home"))

check("cannot stay with mana low too: home at once, no buy",
	is(decide(inputs({ hp = 150, mp = 50, gold = 200, courier = { eta = 20 }, safeSpot = SAFE })), "home", nil, "low_both")
		and is(decide(inputs({ hp = 150, mp = 200, gold = 200, courier = { eta = 20 }, safeSpot = SAFE })), "buy"))

check("a courier slower than the trip home: home",
	is(decide(inputs({ hp = 150, gold = 200, courier = { eta = 70 }, safeSpot = SAFE })), "home"))

check("no heal item under the line: buy a salve when the missing HP covers it, a tango when not; over the line: none",
	is(decide(inputs({ hp = 500, hpMax = 1000, gold = 200, courier = { eta = 20 } })), "buy", "item_flask", "buy_hp")
		and is(decide(inputs({ hp = 640, hpMax = 1000, gold = 200, courier = { eta = 20 } })), "buy", "item_tango", "buy_hp")
		and is(decide(inputs({ hp = 700, hpMax = 1000, gold = 200, courier = { eta = 20 } })), "none"))

check("mana at 100 with a clarity: use; hit recently: none; at 200: none",
	is(decide(inputs({ mp = 100, items = { clarity() } })), "use", "item_clarity", "mana")
		and is(decide(inputs({ mp = 100, items = { clarity() }, hitRecently = true })), "none")
		and is(decide(inputs({ mp = 200, items = { clarity() } })), "none"))

check("mana low and no mana item: buy a clarity; the wand's mana is kept",
	is(decide(inputs({ mp = 100, gold = 100, courier = { eta = 20 } })), "buy", "item_clarity", "buy_mana")
		and is(decide(inputs({ mp = 100, items = { wand() } })), "none"))

check("a support with two tango charges and a bare core missing 200: give; one charge: none; the core holds a salve: none",
	is(decide(inputs({ items = { tango({ charges = 2 }) }, allies = { { pid = 3, missing = 200, heals = 0 } } })), "give", "item_tango")
		and decide(inputs({ items = { tango({ charges = 2 }) }, allies = { { pid = 3, missing = 200, heals = 0 } } })).to == 3
		and is(decide(inputs({ items = { tango({ charges = 1 }) }, allies = { { pid = 3, missing = 200, heals = 0 } } })), "none")
		and is(decide(inputs({ items = { tango({ charges = 2 }) }, allies = { { pid = 3, missing = 200, heals = 1 } } })), "none"))

check("idle window at 80%: top up; not idle: none; missing less than one use: none",
	is(decide(inputs({ hp = 480, idle = true, items = { tango() }, tree = TREE })), "use", "item_tango")
		and is(decide(inputs({ hp = 480, items = { tango() }, tree = TREE })), "none")
		and is(decide(inputs({ hp = 540, idle = true, items = { tango() }, tree = TREE })), "none"))

check("bottle before tango before salve; a regen running: none",
	is(decide(inputs({ hp = 300, items = { salve(), tango(), bottle() }, tree = TREE, safeSpot = SAFE })), "use", "item_bottle")
		and is(decide(inputs({ hp = 300, items = { salve(), tango() }, tree = TREE, safeSpot = SAFE })), "use", "item_tango")
		and is(decide(inputs({ hp = 300, regenLeft = 100, items = { salve(), tango() }, tree = TREE, safeSpot = SAFE })), "none"))

check("the wand is never spent topping up, and counts in what we reach",
	is(decide(inputs({ hp = 300, items = { wand() } })), "none")
		and is(decide(inputs({ hp = 100, items = { wand() } })), "none")
		and is(decide(inputs({ hp = 50, items = { wand() } })), "home"))

do
	local run = { kind = "step_out_use", slot = 2, name = "item_flask", started = 95, hp0 = 250, dur = 10, at = { x = 1, y = 2 } }
	local on = decide(inputs({ hp = 300, run = run, items = {}, safeSpot = SAFE, regenLeft = 200 }))
	local reached = decide(inputs({ hp = 300, run = run, reach = 1, items = {}, safeSpot = SAFE }))
	local topped = decide(inputs({ hp = 420, run = run, items = {}, safeSpot = SAFE }))
	local over = decide(inputs({ now = 106, hp = 300, run = run, items = {}, safeSpot = SAFE, regenLeft = 0 }))
	check("a step-out use runs on; ends interrupted when a hero reaches us, topped over the line, done when its time is up",
		is(on, "step_out_use", "item_flask", "running") and on.at.x == 1
			and reached.ended == "interrupted" and topped.ended == "topped" and over.ended == "done")
end

do
	local run = { kind = "home", started = 90, hp0 = 150 }
	check("a trip home runs until 80% at the fountain, then the next rule",
		is(decide(inputs({ hp = 500, run = run })), "home", nil, "running")
			and is(decide(inputs({ hp = 400, run = run, atFountain = true })), "home", nil, "running")
			and decide(inputs({ hp = 500, run = run, atFountain = true })).ended == "healed")
end

check("rule 1 fires inside a running trip home",
	is(decide(inputs({ hp = 150, burst = 200, reach = 1, hitRecently = true, items = { wand() }, run = { kind = "home", started = 90, hp0 = 150 } })),
		"use", "item_magic_stick", "survive"))
finish()
