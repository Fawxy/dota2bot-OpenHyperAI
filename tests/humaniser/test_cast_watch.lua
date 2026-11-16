dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local BOT_Y = LANE_Y[Lane.Bot]

local function ability(name, o)
	o = o or {}
	return {
		GetName = function() return name end,
		GetLevel = function() return o.level or 1 end,
		IsUltimate = function() return o.ult == true end,
		IsHidden = function() return false end,
		IsNull = function() return false end,
	}
end

-- Radiant support (pid 1) in the bottom lane with an enemy laner (pid 6) 500 away holding Lion's stun and ult.
local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = o.laneFight, telemetry = o.telemetry, tickEvery = o.tickEvery })
	T = 100
	CURRENT_TEAM = 2
	local bot = MakeUnit({ pid = 1, loc = Vector(-3000, BOT_Y) })
	bot.pos, bot.lane = 5, Lane.Bot
	OBSERVER = bot
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(-2500, BOT_Y), level = o.enemyLevel or 3 })
	enemy.impale = ability("lion_impale")
	enemy.abilities = { [0] = enemy.impale, [5] = ability("lion_finger_of_death", { ult = true }) }
	-- `records`: each new cast the observer notes, read from LastSeenCast after every step that can note one.
	local records = {}
	local last
	local function observe()
		local seen = H.LaneFight.CastWatch.LastSeenCast(1)
		if seen ~= nil and seen ~= last then table.insert(records, { enemy = seen.enemyPid, ability = seen.ability, at = seen.at }) end
		last = seen
	end
	for _, step in ipairs({ { H.LaneFight, "Tick" }, { H.LaneFight, "Frame" }, { H, "Tick" } }) do
		local real = step[1][step[2]]
		step[1][step[2]] = function(...) real(...) observe() end
	end
	return H, bot, enemy, records
end

local function poll(H, bot, n)
	for _ = 1, n do
		H.LaneFight.Tick(bot)
		T = T + 0.1
	end
end

local function recordsOf(records, name)
	local n = 0
	for _, r in ipairs(records) do if r.ability == name then n = n + 1 end end
	return n
end

do
	local H, bot, enemy, records = world()
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("a visible cast is noted once", recordsOf(records, "lion_impale") == 1, #records)
	check("LastSeenCast names the caster, the spell and the time", records[1] and records[1].enemy == 6 and near(records[1].at, 100))
	enemy.casting = nil
	poll(H, bot, 7)
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	check("a recast after the event gap is a new cast", recordsOf(records, "lion_impale") == 2, #records)
end

do
	local H, bot, enemy, records = world()
	enemy.hiddenFrom = { [bot] = true }
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("a cast by an enemy absent from the list is not noted", #records == 0, #records)
	LAST_SEEN[6] = { location = enemy.loc, time_since_seen = 1 }
	T = T + 1
	poll(H, bot, 3)
	check("a cast by an enemy listed as not visible is not noted", #records == 0, #records)
end

do
	-- The lane enemy list is cached; a hero that walked into fog since still has its handle there.
	local H, bot, enemy, records = world()
	poll(H, bot, 1)
	enemy.CanBeSeen = function() return false end
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	check("a cast by a cached enemy that can no longer be seen is not noted", #records == 0, #records)
end

do
	local H, bot, enemy, records = world()
	enemy.illusion = true
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("illusion casts are not noted", #records == 0, #records)
end

do
	local H, bot, enemy, records = world()
	enemy.removed = true
	enemy.casting = enemy.impale
	local ok, err = pcall(poll, H, bot, 3)
	check("a removed handle in the list is skipped without error", ok and #records == 0, err)
end

do
	local H, bot, enemy, records = world()
	T = -20
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("nothing is noted before the horn", #records == 0, #records)
end

do
	local blink = ability("item_blink")
	local H, bot, enemy, records = world()
	enemy.GetItemInSlot = function(_, slot) if slot == 0 then return blink end return nil end
	poll(H, bot, 1)
	enemy.loc = Vector(-1800, BOT_Y)
	poll(H, bot, 1)
	check("a jump over BlinkJump notes the blink ability", recordsOf(records, "item_blink") == 1, #records)
end

do
	local H, bot, enemy, records = world()
	poll(H, bot, 1)
	enemy.loc = Vector(-1800, BOT_Y)
	poll(H, bot, 1)
	check("a jump without a blink-class ability notes nothing", #records == 0, #records)
end

do
	local blink = ability("item_blink")
	local H, bot, enemy, records = world()
	enemy.GetItemInSlot = function(_, slot) if slot == 0 then return blink end return nil end
	poll(H, bot, 1)
	enemy.loc = Vector(-2000, BOT_Y)
	poll(H, bot, 1)
	check("a move under BlinkJump notes nothing", #records == 0, #records)
end

do
	local blink = ability("item_blink")
	local H, bot, enemy, records = world()
	enemy.GetItemInSlot = function(_, slot) if slot == 0 then return blink end return nil end
	poll(H, bot, 1)
	enemy.CanBeSeen = function() return false end
	poll(H, bot, 1)
	enemy.CanBeSeen = nil
	enemy.loc = Vector(-1000, BOT_Y)
	poll(H, bot, 1)
	check("reappearing from fog far away is not a jump", #records == 0, #records)
end

do
	for _, case in ipairs({ { name = "LaneFight off", laneFight = { Enable = false } }, { name = "Memory off", laneFight = { Memory = false } },
		{ name = "Memory, Trade and Kill off", laneFight = { Memory = false, Trade = false, Kill = false } } }) do
		local H, bot, enemy, records = world({ laneFight = case.laneFight })
		enemy.casting = enemy.impale
		poll(H, bot, 5)
		local scans = 0
		for _, n in pairs(GETUNITLIST_CALLS) do scans = scans + n end
		-- With Memory off but Trade and Kill on, Tick still watches the lane partner through the cached lane snapshot
		-- (the one RoamDesire builds every round), so only the cast reads must stop.
		check("with " .. case.name .. ", Tick reads no casts", (scans == 0 or case.name == "Memory off") and ACTIVE_ABILITY_CALLS == 0
			and #records == 0, scans .. " " .. ACTIVE_ABILITY_CALLS)
	end
	local H, bot, enemy = world()
	enemy.casting = enemy.impale
	poll(H, bot, 1)
	check("with LaneFight on, the same Tick reads the casts", ACTIVE_ABILITY_CALLS > 0)
end

do
	local H, bot, enemy, records = world()
	LANING = false
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("nothing is noted after the laning phase", #records == 0, #records)
end

do
	local H, bot, enemy, records = world({ laneFight = { Teams = "allies" } })
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("a bot outside LaneFight.Teams watches nothing", #records == 0 and ACTIVE_ABILITY_CALLS == 0, #records)
end

do
	local H, bot, enemy = world({ enemyLevel = 5 })
	enemy.abilities[0] = ability("lion_impale", { level = 0 })
	enemy.abilities[5] = ability("lion_finger_of_death", { level = 0, ult = true })
	local list = H.LaneFight.CastWatch.AbilitiesOf(enemy)
	local byName = {}
	for _, a in ipairs(list) do byName[a.name] = a end
	local ult, basic = byName.lion_finger_of_death, byName.lion_impale
	check("level estimate: an unreadable ult at hero level 5 is not learned", ult ~= nil and ult.ult and not ult.learned)
	check("level estimate: an unreadable basic ability at hero level 5 is level 3", basic ~= nil and basic.learned and basic.level == 3,
		basic and basic.level)
	check("AbilitiesOf reports the slot", basic ~= nil and basic.slot == 0 and ult.slot == 5)
	enemy.level = 12
	enemy.abilities[5] = ability("lion_finger_of_death", { level = 0, ult = true })
	T = T + 1
	local cached = {}
	for _, a in ipairs(H.LaneFight.CastWatch.AbilitiesOf(enemy)) do cached[a.name] = a end
	check("AbilitiesOf is cached per enemy", not cached.lion_finger_of_death.learned)
	T = T + 5
	local again = {}
	for _, a in ipairs(H.LaneFight.CastWatch.AbilitiesOf(enemy)) do again[a.name] = a end
	check("the cache refreshes after 5 s (ult level 2 at hero level 12)", again.lion_finger_of_death.learned and again.lion_finger_of_death.level == 2)
end

do
	local H, bot, enemy = world({ laneFight = { UseCastCallback = false } })
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	check("UseCastCallback false installs no callback", next(CAST_CALLBACKS) == nil)
end

do
	local H, bot, enemy, records = world({ laneFight = { UseCastCallback = true } })
	poll(H, bot, 1)
	check("UseCastCallback installs one callback per enemy", CAST_CALLBACKS[6] ~= nil and #CAST_CALLBACKS[6] == 1)
	poll(H, bot, 3)
	check("the callback is installed once", #CAST_CALLBACKS[6] == 1)
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = enemy.impale, unit = enemy })
	check("a callback cast waits for the observer's tick (a callback has no bot context)", recordsOf(records, "lion_impale") == 0, #records)
	H.LaneFight.Tick(bot)
	check("a callback cast by a visible enemy is noted", recordsOf(records, "lion_impale") == 1, #records)
	T = T + 1
	-- A summon of the same player: its own handle, not the hero's (kept out of the world so the hero stays the caster).
	local summon = setmetatable({ pid = 6, team = 3, alive = true, loc = Vector(-2400, BOT_Y), modifiers = {} }, getmetatable(enemy))
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = ability("lion_mana_drain"), unit = summon })
	H.LaneFight.Tick(bot)
	check("a callback cast by another unit of the enemy player is not the hero's", recordsOf(records, "lion_mana_drain") == 0, #records)
	-- Still in the cached lane list, but in fog by the time the event fires.
	enemy.CanBeSeen = function() return false end
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = ability("lion_mana_drain"), unit = enemy })
	H.LaneFight.Tick(bot)
	check("a callback cast by a fogged enemy is ignored", recordsOf(records, "lion_mana_drain") == 0, #records)
	enemy.CanBeSeen = nil
	T = T + 1
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = "lion_impale", unit = enemy })
	H.LaneFight.Tick(bot)
	check("a callback naming the ability by string is read from the ability list", recordsOf(records, "lion_impale") == 2, #records)
	-- The observer had no tick for 5 s (dead): the queued cast is not handled as a fresh one on its next tick.
	T = T + 1
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = enemy.impale, unit = enemy })
	T = T + 5
	H.LaneFight.Tick(bot)
	check("a queued cast older than the event gap is dropped", recordsOf(records, "lion_impale") == 2, #records)
end

do
	local lines = {}
	local blink = ability("item_blink")
	local H, bot, enemy = world({ telemetry = { Enable = true } })
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	enemy.GetItemInSlot = function(_, slot) if slot == 0 then return blink end return nil end
	enemy.casting = enemy.impale
	poll(H, bot, 1)
	enemy.casting = nil
	enemy.loc = Vector(-1800, BOT_Y)
	poll(H, bot, 1)
	for _ = 1, 300 do poll(H, bot, 1) end
	local summaries = {}
	for _, l in ipairs(lines) do if l:find("lanefight_watch", 1, true) then table.insert(summaries, l) end end
	local first = summaries[1] or ""
	check("a watch summary is logged once per 30 s", #summaries == 1, #summaries)
	check("the summary counts polls, visible enemies, casts and jumps",
		first:find("pid=1", 1, true) and first:find("polls=302", 1, true) and first:find("visible=302", 1, true)
		and first:find("casts=2", 1, true) and first:find("jumps=1", 1, true), first)
end

-- Between full ticks the frame step reads the queue, so a caster who blinks into fog before the next Tick is not lost.
do
	local H, bot, enemy, records = world({ laneFight = { UseCastCallback = true } })
	poll(H, bot, 1)
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = enemy.impale, unit = enemy })
	H.LaneFight.Frame(bot)
	enemy.CanBeSeen = function() return false end
	H.LaneFight.Tick(bot)
	check("a cast read on the frame it was seen survives the caster going into fog", recordsOf(records, "lion_impale") == 1, #records)
end

-- Through Humaniser.Tick at the shipped rate: every third frame runs the steps; the two between read the cast queue
-- (the caster may be in fog by the next full tick) and nothing else of the cast watch.
do
	local H, bot, enemy, records = world({ laneFight = { UseCastCallback = true }, tickEvery = 3 })
	local function frame()
		H.Tick(bot)
		T = T + 0.034
	end
	frame() frame() frame()
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = enemy.impale, unit = enemy })
	frame()
	check("a between-frame reads a queued cast", recordsOf(records, "lion_impale") == 1, #records)
	enemy.casting = ability("lion_voodoo")
	frame()
	check("a between-frame does not poll", recordsOf(records, "lion_voodoo") == 0, #records)
	frame()
	check("the next full tick polls", recordsOf(records, "lion_voodoo") == 1, #records)
end

finish()
