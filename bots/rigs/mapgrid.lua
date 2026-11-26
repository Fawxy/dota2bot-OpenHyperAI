-- Map probe: server Lua, loaded like the rig setters (`script_reload_code bots/rigs/mapgrid`).
--   rig_map_grid <x0> <y0> <x1> <y1> <step>   sample the square on a grid and print it as `[RIG]` lines, north row first:
--       map_head  the bounds, the step, the lowest ground height (z0) and the height unit (32)
--       map_p     one row: `#` terrain not walkable, `T` a tree within half a step, `B` blocked by something else (a building),
--                 else the ground height above z0 in units of 32 as one base-36 digit
--       map_h     the same row's ground height for every cell, walkable or not (a cliff face against a tree line)
--       map_tower each live tower: team, name, place, attack range and hull radius (its reach to a point is the two added)
local function say(s) print("[RIG] " .. s) end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local UNIT = 32

local function digit(z, z0)
	local i = math.max(0, math.min(35, math.floor((z - z0) / UNIT + 0.5)))
	return string.sub(DIGITS, i + 1, i + 1)
end

Convars:RegisterCommand("rig_map_grid", function(_, x0, y0, x1, y1, step)
	local ok, err = pcall(function()
		x0, y0, x1, y1, step = tonumber(x0), tonumber(y0), tonumber(x1), tonumber(y1), tonumber(step)
		local rows, z0 = {}, math.huge
		for y = y1, y0, -step do
			local row = {}
			for x = x0, x1, step do
				local v = Vector(x, y, 0)
				local z = GetGroundHeight(v, nil)
				if z < z0 and z > -10000 then z0 = z end -- off the map the ground reads -16384
				table.insert(row, { z = z, pass = GridNav:IsTraversable(v), blocked = GridNav:IsBlocked(v), tree = GridNav:IsNearbyTree(v, step / 2, true) })
			end
			table.insert(rows, { y = y, cells = row })
		end
		say(string.format("map_head x0=%d y0=%d x1=%d y1=%d step=%d z0=%d unit=%d rows=%d", x0, y0, x1, y1, step, z0, UNIT, #rows))
		for _, r in ipairs(rows) do
			local p, h = {}, {}
			for _, c in ipairs(r.cells) do
				table.insert(p, c.tree and "T" or (not c.pass and "#") or (c.blocked and "B") or digit(c.z, z0))
				table.insert(h, digit(c.z, z0))
			end
			say(string.format("map_p y=%d p=%s", r.y, table.concat(p)))
			say(string.format("map_h y=%d h=%s", r.y, table.concat(h)))
		end
		for _, t in ipairs(Entities:FindAllByClassname("npc_dota_tower")) do
			if t:IsAlive() then
				local o = t:GetAbsOrigin()
				say(string.format("map_tower team=%d name=%s x=%d y=%d z=%d range=%d hull=%d", t:GetTeamNumber(), t:GetUnitName(), o.x, o.y, o.z,
					t:Script_GetAttackRange(), t:GetHullRadius()))
			end
		end
	end)
	if not ok then say("map error " .. tostring(err)) end
end, "rig: print a walkability and height grid of a square", FCVAR_CHEAT)

say("mapgrid registered")
