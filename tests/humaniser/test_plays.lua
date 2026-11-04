dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice rune-spawn: the play roll (Plays). Weigh holds the hard zeros and factors; Roll draws only from the engine's Skill
-- rng; the library ends a play past its timeout so every fired play gets an end line.

local RAD, DIRE = 2, 3

local function world(draw, skill)
	local H = LaneFresh({ Enable = true }, { enable = false, skill = skill or 1, telemetry = { Enable = true } })
	H.Lane.Config.SetRng(draw ~= nil and function() return { random = function() return draw end, gauss = function() return 0 end } end or nil)
	H.Plays.ResetCache()
	H.Plays.Define("gank", { base = 0.35, timeout = 25, chases = true })
	H.Plays.Define("rune_fight", { base = 0.5, timeout = 15, chases = false })
	H.Plays.Define("finish", { base = 0.2, timeout = 15, chases = false, sure = H.Plays.SureKill(1000) })
	H.Plays.Define("solo", { base = 0.5, timeout = 15, chases = false, zero = function(i) return i.ours > 1 and "not-solo" or nil end })
	CURRENT_TEAM = RAD
	return H.Plays
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function line(all, ev)
	for _, l in ipairs(all) do if l:find("ev=" .. ev .. " ", 1, true) then return l end end
end
local function field(l, k) return l and l:match(" " .. k .. "=(%S+)") end

local even = { kind = "gank", ourLevel = 5, theirLevel = 5, ours = 1, theirs = 1, hp = 1, mana = 1, rune = false, tower = 5000 }
local function with(t) local r = {} for k, v in pairs(even) do r[k] = v end for k, v in pairs(t) do r[k] = v end return r end

do
	local P = world()
	local base = P.Weigh(even).w
	check("an even gank chance weighs the gank base", math.abs(base - 0.35) < 1e-9, base)
	check("below the HP floor: a hard zero", P.Weigh(with({ hp = 0.3 })).zero == "hp" and P.Weigh(with({ hp = 0.3 })).w == 0)
	check("two heroes down: a hard zero", P.Weigh(with({ theirs = 3 })).zero == "outnumbered")
	check("one hero down: weighed down, not zero", P.Weigh(with({ theirs = 2 })).w > 0 and P.Weigh(with({ theirs = 2 })).w < base)
	check("a gank target beside its tower: a hard zero", P.Weigh(with({ tower = 500 })).zero == "tower")
	check("a rune fight at a spot near their tower is not zeroed by it", P.Weigh(with({ kind = "rune_fight", tower = 500 })).zero == nil)
	check("levels ahead and a power rune raise the weight", P.Weigh(with({ ourLevel = 7, rune = true })).w > base)
	check("a low target weighs a play up, a healthy one down", P.Weigh(with({ targetHp = 0.3 })).w > base and P.Weigh(with({ targetHp = 0.9 })).w < base)
	check("a consumer's kind brings its own hard zero", P.Weigh(with({ kind = "solo", ours = 2 })).zero == "not-solo")
	check("an undefined kind never fires", P.Weigh(with({ kind = "nope" })).w == 0)
	local low = with({ kind = "finish", targetHp = 0.3, reach = 600, skill = 1 })
	check("a low target in reach with numbers even is sure", P.Weigh(low).sure == "low-target" and P.Weigh(low).commit == 1)
	check("sure needs the target low, in reach and numbers even", P.Weigh(with({ kind = "finish", targetHp = 0.5, reach = 600, skill = 1 })).sure == nil
		and P.Weigh(with({ kind = "finish", targetHp = 0.3, reach = 1200, skill = 1 })).sure == nil
		and P.Weigh(with({ kind = "finish", targetHp = 0.3, reach = 600, theirs = 2, skill = 1 })).sure == nil)
	check("a hard zero overrides sure", P.Weigh(with({ kind = "finish", targetHp = 0.3, reach = 600, hp = 0.3, skill = 1 })).sure == nil)
	check("below skill 1 a sure play commits less often", P.Weigh(with({ kind = "finish", targetHp = 0.3, reach = 600, skill = 0 })).commit < 1)
	check("the weight never passes MaxWeight", P.Weigh(with({ ourLevel = 30, rune = true, ours = 3, forecast = 9 })).w == P.SETTINGS.MaxWeight)
end

-- Units for Roll: our pos4 beside the river, their mid near the middle of the map, no towers.
local function units()
	ResetWorld()
	CURRENT_TEAM = RAD
	local by = MakeUnit({ pid = 3, team = RAD, loc = Vector(-1000, 0), level = 5 })
	local mid = MakeUnit({ pid = 7, team = DIRE, loc = Vector(-200, 0), level = 5 })
	by.mana, by.maxMana = 300, 300
	return by, mid
end

do
	local by, mid = units()
	local P = world(0.1)
	local play
	local out = capture(function() play = P.Roll({ kind = "gank", by = by, target = mid, at = mid:GetLocation() }, 360) end)
	local l = line(out, "play")
	check("a draw under the weight fires a play the team can see", play ~= nil and P.Active("gank")[1] == play and P.Of(by) == play)
	check("the chance's line has the draw and fire=1", field(l, "fire") == "1" and tonumber(field(l, "draw")) == 0.1, l)
	local ended = capture(function() P.Tick(360 + 25) P.Tick(360 + 25 + 5) end)
	check("past its timeout the library ends it with a line", #P.Active() == 0 and field(line(ended, "play_end"), "why") == "timeout")
end

do
	local by, mid = units()
	local P = world(0.95)
	local play
	capture(function() play = P.Roll({ kind = "gank", by = by, target = mid, at = mid:GetLocation() }, 360) end)
	check("a draw above the weight fires nothing", play == nil and #P.Active() == 0)
end

do
	-- No engine rng: no draw at all, even where a host draw of 0 would have fired.
	local by, mid = units()
	local P = world(nil)
	SetRandomSequence({ 0.0 })
	local play
	local out = capture(function() play = P.Roll({ kind = "gank", by = by, target = mid, at = mid:GetLocation() }, 360) end)
	check("without the engine rng nothing is drawn", play == nil and field(line(out, "play"), "zero") == "no-rng")
end

do
	local by, mid = units()
	local P = world(0.1)
	local play
	capture(function() play = P.Roll({ kind = "gank", by = by, target = mid, at = mid:GetLocation() }, 360) end)
	local helper = MakeUnit({ pid = 4, team = RAD, loc = Vector(-300, 0), level = 5 })
	check("a teammate finds the play near it and joins", P.Near(helper:GetLocation(), 1000, "gank")[1] == play and P.Join(play, helper) and P.Of(helper) == play)
	local early = capture(function() P.End(play, "arrived", nil, 370) end)
	check("an ended play with its target alive waits before its line", line(early, "play_end") == nil and #P.Active() == 0)
	mid.alive = false
	local out = capture(function() P.Tick(373) end)
	local l = line(out, "play_end")
	check("a kill within KillAfter of the end counts, with the joiner", field(l, "res") == "kill" and field(l, "join") == "1", l)
end

-- The sure tier: their mid at 30% HP 800 from our pos4, one each side.
local function sureRoll(draw, skill)
	local by, mid = units()
	mid.hp = 30
	local P = world(draw, skill)
	local play
	local out = capture(function() play = P.Roll({ kind = "finish", by = by, target = mid, at = mid:GetLocation() }, 360) end)
	return play, line(out, "play")
end

do
	local play, l = sureRoll(0.99, 1)
	check("at skill 1 a sure play fires with no draw, past what its weight allows", play ~= nil and field(l, "draw") == nil and field(l, "sure") == "low-target", l)
	play, l = sureRoll(nil, 1)
	check("a sure play needs no engine rng", play ~= nil and field(l, "zero") == nil, l)
	local miss = sureRoll(0.7, 0)
	local hit = sureRoll(0.3, 0)
	check("at skill 0 a sure play commits on a draw under its commit chance", miss == nil and hit ~= nil)
end

finish()
