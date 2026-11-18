dofile(HARNESS_DIR .. "/lane_world.lua")

-- vision_map (slice vision-map): Overrides.VisionMap dumps the height grid and the trees once, from the Radiant VM only.
local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, s) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return printed
end

local function field(line, k)
	return line ~= nil and (line:match(" " .. k .. "=\"([^\"]*)\"") or line:match(" " .. k .. "=(%S+)")) or nil
end

local function kinds(ls, k)
	local r = {}
	for _, l in ipairs(ls) do
		if l:find("ev=vmap", 1, true) and field(l, "kind") == k then table.insert(r, l) end
	end
	return r
end

do
	LaneFresh({ Enable = true }, { enable = true, skill = 1, telemetry = { Enable = true } })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = { VisionMap = true }
	package.loaded["bots/FunLib/humaniser/vision_map"] = nil
	local VM = require("bots/FunLib/humaniser/vision_map")
	GetWorldBounds = function() return { -128, -128, 128, 128 } end
	HEIGHT = function(v) return v.x < 0 and 2 or 4 end
	IMPASSABLE = function(v) return v.x == 128 end
	TREES = { [0] = Vector(10.6, 20, 0), [2] = Vector(30, 40, 0) }
	local rad = MakeUnit({ pid = 1, team = 2, loc = Vector(0, 0) })
	local dire = MakeUnit({ pid = 6, team = 3, loc = Vector(0, 0) })
	local ls = capture(function()
		for i = 1, 40 do
			T = -90 + i * 0.1
			CURRENT_TEAM = 3
			VM.Tick(dire)
			CURRENT_TEAM = 2
			VM.Tick(rad)
			VM.Tick(rad)
		end
	end)
	local st, h, t, e = kinds(ls, "start"), kinds(ls, "h"), kinds(ls, "t"), kinds(ls, "end")
	check("vision_map: one start line, the box from GetWorldBounds", #st == 1 and field(st[1], "src") == "api" and field(st[1], "bx0") == "-128" and field(st[1], "step") == "64", st[1])
	check("vision_map: five rows, one a frame (a second tick in the frame writes nothing)", #h == 5 and field(h[1], "y") == "-128" and field(h[5], "y") == "128", #h)
	check("vision_map: a row is the height level plus 8 when passable, from x0 east", field(h[1], "x0") == "-128" and field(h[1], "n") == "5" and field(h[1], "hex") == "aacc4", h[1])
	check("vision_map: trees by index, floored, the missing index skipped", #t == 1 and field(t[1], "xy") == "0:10:20;2:30:40", t[1])
	check("vision_map: the end line counts rows and trees, once", #e == 1 and field(e[1], "rows") == "5" and field(e[1], "trees") == "2", e[1])
	local again = capture(function() T = 0 VM.Tick(rad) end)
	check("vision_map: nothing after the end", #again == 0, again[1])
	GetWorldBounds, HEIGHT, IMPASSABLE, TREES = nil, nil, nil, nil
	Customize.Overrides = nil
end
finish()
