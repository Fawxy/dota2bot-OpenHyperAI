dofile(HARNESS_DIR .. "/dota_stubs.lua")
-- A rig owns its heroes (humaniser/drill.ts Owns): the per-hero entry points in bots/ that this scan can see must reach a
-- Drill gate, directly or through a listed route. A new `function ...Think` or `function GetDesire` with no gate fails here,
-- naming the file and function. It cannot see a Valve built-in mode with no file (held by the rig's `idle` release), nor an
-- entry point written `Name = function` or under another name.
local ROOT = BOTS_ROOT .. "/bots"

-- Direct gates: the function's first lines contain this call. Item and ability use go through Chooser.HoldsCasts, the one
-- combiner for the cast hold (OWNERSHIP.md), which asks Drill for rig heroes.
local DIRECT = {
	["ability_item_usage_generic.lua"] = { ItemUsageThink = "Chooser.HoldsCasts(bot, true)", AbilityUsageThink = "Chooser.HoldsCasts(bot)", BuybackUsageThink = 'Drill.Owns(bot, "buyback")', CourierUsageThink = 'Drill.Owns(bot, "courier")', AbilityLevelUpThink = 'Drill.Owns(bot, "levelup")' },
	["item_purchase_generic.lua"] = { ItemPurchaseThink = 'Drill.Owns(bot, "purchase")' },
}

-- Not an entry point for a rig hero: the reason is the entry.
local ALLOW = {
	["bot_generic.lua:MinionThink"] = "runs for a hero's minions and illusions, never for the hero",
	["hero_selection.lua:Think"] = "the draft, before any hero exists",
	["mode_team_roam_generic.lua:ItemOpsThink"] = "a helper of team_roam's Think, which is behind that mode's Chooser.Gate",
	["mode_retreat_generic_wip.lua:*"] = "not a Valve mode name: Dota never loads it",
	["--mode_item_generic.lua:*"] = "disabled file (leading dashes): Dota never loads it",
}

-- A mode file's GetDesire and Think: Chooser.Gate wraps GetDesire (Chooser.Decide asks Drill.RigDesire first, so a rig cast
-- gets 0 for every mode its release does not list), and Think only runs while that mode wins.
local function modeFile(name) return name:match("^mode_.*_generic%.lua$") ~= nil and name ~= "mode_retreat_generic_wip.lua" end

local function stripComments(text)
	return (text:gsub("%-%-%[%[.-%]%]", ""):gsub("%-%-[^\n]*", ""))
end

local function entryPoints(text)
	local found, order = {}, {}
	local n = 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		local fn = line:match("^%s*function%s+([%w_]+)%s*%(")
		if fn ~= nil and (fn == "GetDesire" or fn:match("Think$")) and found[fn] == nil then
			found[fn] = n
			table.insert(order, fn)
		end
	end
	return found, order
end

local function bodyOf(text, from)
	local lines, n = {}, 0
	for line in (text .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		if n >= from then
			table.insert(lines, line)
			if n > from and line:match("^end") then break end
		end
	end
	return lines
end

local function gateProblem(file, fn, text, line)
	local key = file .. ":" .. fn
	if ALLOW[key] ~= nil or ALLOW[file .. ":*"] ~= nil then return nil end
	local kind = DIRECT[file] and DIRECT[file][fn]
	if kind ~= nil then
		local body = bodyOf(text, line)
		for i = 2, math.min(#body, 10) do
			if body[i]:find(kind, 1, true) then return nil end
		end
		return key .. ": no " .. kind .. " in its first lines"
	end
	if modeFile(file) then
		if text:find("C.Gate(GetBot(), '", 1, true) then return nil end
		return key .. ": a mode file with no Chooser.Gate on its GetDesire"
	end
	return key .. ": an engine entry point with no Drill gate and no ALLOW reason"
end

-- Every file's problems, plus each ALLOW entry that matched nothing (a stale reason hides a future gap).
local function scan(root, direct, allow)
	local problems, seen, matchedAllow, count = {}, {}, {}, 0
	for _, file in ipairs(LIST_FILES(root)) do
		if file:match("%.lua$") then
			local text = stripComments(io.open(root .. "/" .. file, "r"):read("a"))
			local found, order = entryPoints(text)
			for _, fn in ipairs(order) do
				count = count + 1
				seen[file .. ":" .. fn] = true
				if allow[file .. ":" .. fn] or allow[file .. ":*"] then matchedAllow[allow[file .. ":" .. fn] and (file .. ":" .. fn) or (file .. ":*")] = true end
				local p = gateProblem(file, fn, text, found[fn])
				if p ~= nil then table.insert(problems, p) end
			end
		end
	end
	return problems, seen, matchedAllow, count
end

local problems, seen, matchedAllow, count = scan(ROOT, DIRECT, ALLOW)
for _, p in ipairs(problems) do check("entry point is gated: " .. p, false) end
check("no entry point lacks a Drill gate or an explained route (" .. count .. " scanned)", #problems == 0)
check("the scan sees the engine's per-hero thinks, so an empty scan cannot pass", seen["ability_item_usage_generic.lua:ItemUsageThink"] and seen["item_purchase_generic.lua:ItemPurchaseThink"] and seen["mode_farm_generic.lua:GetDesire"] and count > 20)
for key in pairs(ALLOW) do check("ALLOW entry still matches a function: " .. key, matchedAllow[key] == true) end
for file, fns in pairs(DIRECT) do for fn in pairs(fns) do check("DIRECT entry still exists: " .. file .. ":" .. fn, seen[file .. ":" .. fn] == true) end end

finish()
