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
		-- The bot API's GetCooldown takes no level; an argument here reads a different (wrong) number.
		GetCooldown = function(_, level) if level ~= nil then return 999 end return o.cd or 12 end,
	}
end

-- Radiant support (pid 1) in the bottom lane with an enemy laner (pid 6) 500 away holding Lion's stun and ult.
local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = o.laneFight, telemetry = o.telemetry })
	T = 100
	CURRENT_TEAM = 2
	local bot = MakeUnit({ pid = 1, loc = Vector(-3000, BOT_Y) })
	bot.pos, bot.lane = 5, Lane.Bot
	OBSERVER = bot
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(-2500, BOT_Y), level = o.enemyLevel or 3 })
	enemy.impale = ability("lion_impale", { cd = o.cd })
	enemy.abilities = { [0] = enemy.impale, [5] = ability("lion_finger_of_death", { ult = true, cd = 100 }) }
	local M = require("bots/FunLib/humaniser/cooldown_memory")
	local records = {}
	local real = M.Record
	M.Record = function(obs, epid, name, ...)
		table.insert(records, { obs = obs, enemy = epid, ability = name })
		return real(obs, epid, name, ...)
	end
	return H, bot, enemy, records, M
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
	local H, bot, enemy, records, M = world()
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("a visible cast is recorded once", recordsOf(records, "lion_impale") == 1, #records)
	check("the record is the observer's, about the caster", records[1] and records[1].obs == 1 and records[1].enemy == 6)
	check("the cast is remembered as on cooldown", not M.ProbablyReady(1, 6, "lion_impale", true, T, 1))
	check("the cooldown is GetCooldown() with no level (12 s, not the level form's 999)",
		M.ProbablyReady(1, 6, "lion_impale", true, 100 + 12.1, 1) and not M.ProbablyReady(1, 6, "lion_impale", true, 100 + 11.9, 1))
	local last = H.LaneFight.CastWatch.LastRecorded(1)
	check("LastRecorded names the cast", last ~= nil and last.enemyPid == 6 and last.ability == "lion_impale" and near(last.at, 100))
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
	check("a cast by an enemy absent from the list is not recorded", #records == 0, #records)
	LAST_SEEN[6] = { location = enemy.loc, time_since_seen = 1 }
	T = T + 1
	poll(H, bot, 3)
	check("a cast by an enemy listed as not visible is not recorded", #records == 0, #records)
end

do
	-- The lane enemy list is cached; a hero that walked into fog since still has its handle there.
	local H, bot, enemy, records = world()
	poll(H, bot, 1)
	enemy.CanBeSeen = function() return false end
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	check("a cast by a cached enemy that can no longer be seen is not recorded", #records == 0, #records)
end

do
	local H, bot, enemy, records = world()
	enemy.illusion = true
	enemy.casting = enemy.impale
	poll(H, bot, 3)
	check("illusion casts are not recorded", #records == 0, #records)
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
	check("nothing is recorded before the horn", #records == 0, #records)
end

do
	local blink = ability("item_blink", { cd = 15 })
	local H, bot, enemy, records = world()
	enemy.GetItemInSlot = function(_, slot) if slot == 0 then return blink end return nil end
	poll(H, bot, 1)
	enemy.loc = Vector(-1800, BOT_Y)
	poll(H, bot, 1)
	check("a jump over BlinkJump records the blink ability", recordsOf(records, "item_blink") == 1, #records)
end

do
	local H, bot, enemy, records = world()
	poll(H, bot, 1)
	enemy.loc = Vector(-1800, BOT_Y)
	poll(H, bot, 1)
	check("a jump without a blink-class ability records nothing", #records == 0, #records)
end

do
	local blink = ability("item_blink", { cd = 15 })
	local H, bot, enemy, records = world()
	enemy.GetItemInSlot = function(_, slot) if slot == 0 then return blink end return nil end
	poll(H, bot, 1)
	enemy.loc = Vector(-2000, BOT_Y)
	poll(H, bot, 1)
	check("a move under BlinkJump records nothing", #records == 0, #records)
end

do
	local blink = ability("item_blink", { cd = 15 })
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
	check("nothing is recorded after the laning phase", #records == 0, #records)
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
	check("AbilitiesOf reads the no-argument cooldown", basic ~= nil and basic.cooldown == 12, basic and basic.cooldown)
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
	local lines = {}
	local H, bot, enemy, records = world({ cd = 0, telemetry = { Enable = true } })
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	enemy.casting = nil
	poll(H, bot, 7)
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	local noCd = 0
	for _, l in ipairs(lines) do
		if l:find("lanefight_mem", 1, true) and l:find("reason=no_cd", 1, true) and l:find("ability=lion_impale", 1, true)
			and l:find("remembered=0", 1, true) then noCd = noCd + 1 end
	end
	check("a cast with no readable cooldown is not recorded", #records == 0, #records)
	check("no_cd is logged once per observer, enemy and ability", noCd == 1, noCd)
end

-- Lane partner: a bot core (pid 2) beside the support.
local function withPartner(o)
	local H, bot, enemy, records, M = world(o)
	local core = MakeUnit({ pid = 2, loc = Vector(-3100, BOT_Y) })
	core.pos, core.lane = 1, Lane.Bot
	return H, bot, enemy, records, M
end

do
	local H, bot, enemy, records, M = withPartner()
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	check("without ShareMemory the partner learns nothing", M.Count(2, T) == 0 and M.Count(1, T) == 1)
	H, bot, enemy, records, M = withPartner({ laneFight = { ShareMemory = true } })
	enemy.casting = enemy.impale
	poll(H, bot, 2)
	check("with ShareMemory a remembered cast is shared to the lane partner", M.Count(2, T) == 1)
end

do
	local H, bot, enemy = world()
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
	check("a callback cast by a visible enemy is recorded", recordsOf(records, "lion_impale") == 1, #records)
	T = T + 1
	-- A summon of the same player: its own handle, not the hero's (kept out of the world so the hero stays the caster).
	local summon = setmetatable({ pid = 6, team = 3, alive = true, loc = Vector(-2400, BOT_Y), modifiers = {} }, getmetatable(enemy))
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = ability("lion_mana_drain"), unit = summon })
	check("a callback cast by another unit of the enemy player is not the hero's", recordsOf(records, "lion_mana_drain") == 0, #records)
	-- Still in the cached lane list, but in fog by the time the event fires.
	enemy.CanBeSeen = function() return false end
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = ability("lion_mana_drain"), unit = enemy })
	check("a callback cast by a fogged enemy is ignored", recordsOf(records, "lion_mana_drain") == 0, #records)
	enemy.CanBeSeen = nil
	T = T + 1
	CAST_CALLBACKS[6][1]({ player_id = 6, ability = "lion_impale", unit = enemy })
	check("a callback naming the ability by string is read from the ability list", recordsOf(records, "lion_impale") == 2, #records)
end

do
	-- Skill 0: an "other" ability is remembered at 0.1, so the 0.5 roll fails.
	local H, bot, enemy, records = world({ skill = 0 })
	enemy.casting = ability("lion_mana_drain", { cd = 16 })
	poll(H, bot, 2)
	local seen = H.LaneFight.CastWatch.LastSeenCast(1)
	check("a failed remember roll records nothing", #records == 1 and H.LaneFight.CastWatch.LastRecorded(1) == nil, #records)
	check("a failed remember roll still updates LastSeenCast", seen ~= nil and seen.enemyPid == 6 and seen.ability == "lion_mana_drain"
		and near(seen.at, 100))
end

do
	local lines = {}
	local blink = ability("item_blink", { cd = 15 })
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
	check("the summary counts polls, visible enemies, casts, records and jumps",
		first:find("pid=1", 1, true) and first:find("polls=302", 1, true) and first:find("visible=302", 1, true)
		and first:find("casts=2", 1, true) and first:find("recorded=2", 1, true) and first:find("jumps=1", 1, true), first)
end

finish()
