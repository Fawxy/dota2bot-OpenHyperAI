dofile(HARNESS_DIR .. "/lane_world.lua")
-- The deny (deny_row.ts, Ours.Deny, doctrine D12), a decider row. The engine's laneTargets and task
-- runner are stubbed (ForOurs), so these cover the row's decision, its latch and its lines; the deny verb is the engine's
-- (its own tests) and its execution is the rig's.
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function lines(all, pat)
	local r = {}
	for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(r, l) end end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

-- o.on: the switch; o.pos, o.lane: the hero; w.offers: what laneTargets returns; w.starts: Start calls; w.onEnd: the last task's.
local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours.Deny = o.on ~= false
	T = 120
	local SD = require("bots/FunLib/humaniser/deny_row")
	SD.ResetCache()
	local sup = MakeUnit({ pid = 5, team = 2, bot = true, loc = Vector(0, -5000), hp = 600, maxhp = 600 })
	sup.lane, sup.pos = o.lane or Lane.Bot, o.pos or 5
	local w = { SD = SD, sup = sup, offers = {}, starts = 0, steps = 0 }
	local F = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
	F.Verbs = function() return { laneTargets = function() return w.offers end } end
	F.Tick = function() end
	F.Start = function(_, opts, body)
		w.starts = w.starts + 1
		w.onEnd, w.opts, w.body = opts.onEnd, opts, body
		return o.refuse ~= true
	end
	F.Step = function() w.steps = w.steps + 1 return true end
	-- w.kills[creep]: the lane read's killing hit for that creep ({ by, attacker, commit }); none: the creep is not in the read.
	w.kills = {}
	local LH = package.loaded["bots/FunLib/humaniser/lane_hits"]
	LH.Of = function(_, _, creep) if w.kills[creep] ~= nil then return { creep = creep } end return nil end
	LH.KillingHit = function(r) return w.kills[r.creep] end
	return w
end

-- The deny options the started task passed to the engine verb.
local function denyOpts(w)
	local got
	w.body({ deny = function(opts) got = opts end })
	return got
end
local mate = MakeUnit({ pid = 1, team = 2, bot = true, loc = Vector(50, -5000) })
local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(300, -5000) })

local creepA = MakeCreep({ team = 2, loc = Vector(100, -5000), hp = 40, maxhp = 550 })
local creepB = MakeCreep({ team = 2, loc = Vector(150, -5000), hp = 300, maxhp = 550 })
local function deny(c, walk, due, dies) return { creep = c, kind = "deny", walk = walk, due = due, eta = math.max(walk, due), dies = dies, ranged = false } end

do -- off: no hold, the offer logged once per creep as a shadow
	local w = world({ on = false })
	w.offers = { deny(creepA, 0, 0.2, 2) }
	local a1, a2
	local out = capture(function() a1 = w.SD.ROW.applies(w.sup) a2 = w.SD.ROW.applies(w.sup) end)
	local ch = lines(out, "kind=deny")
	check("off: the row never applies", a1 == false and a2 == false and w.starts == 0, tostring(a1) .. " " .. w.starts)
	check("off: one shadow line for the creep, go=0 why=off src=shadow", #ch == 1 and field(ch[1], "go") == "0"
		and field(ch[1], "why") == "off" and field(ch[1], "src") == "shadow", table.concat(ch, " | "))
end

do -- on: a reachable deny starts an attempt; the latch holds after the offer is gone; the end lets go
	local w = world()
	w.offers = { deny(creepB, 0.5, 0.9, 3), deny(creepA, 0, 0.2, 2) }
	local a1, a2, a3, s1, s2
	local out = capture(function()
		a1 = w.SD.ROW.applies(w.sup)
		w.offers = {}
		a2 = w.SD.ROW.applies(w.sup)
		s1 = w.SD.ROW.step(w.sup)
		w.onEnd({ success = true })
		s2 = w.SD.ROW.step(w.sup)
		a3 = w.SD.ROW.applies(w.sup)
	end)
	local ch, jobs = lines(out, "kind=deny"), lines(out, "job=deny")
	check("on: a reachable deny holds the hero and starts one task", a1 == true and w.starts == 1, tostring(a1) .. " " .. w.starts)
	check("on: the task waits laneFarm's slack past the eta of the creep closest to due", w.opts ~= nil and w.opts.host == dota.BotMode.Farm, "")
	check("on: the latch holds while the attempt runs, with no offer", a2 == true, tostring(a2))
	check("on: the step runs the task and is not finished until it ends", s1 == false and w.steps == 1 and s2 == true, tostring(s1) .. " " .. tostring(s2))
	check("on: after the end the row lets go", a3 == false, tostring(a3))
	check("on: one choice line, go=1 src=own, with the creep's facts", #ch == 1 and field(ch[1], "go") == "1" and field(ch[1], "src") == "own"
		and field(ch[1], "walk") == "0" and field(ch[1], "dies") == "2", table.concat(ch, " | "))
	check("on: a job start and an end why=ok", #jobs == 2 and field(jobs[1], "phase") == "start" and field(jobs[2], "why") == "ok", table.concat(jobs, " | "))
end

do -- control: nothing the reach rule passes holds nothing
	local w = world()
	w.offers = { deny(creepA, 1.5, 0, 5), deny(creepB, 0.8, 0.8, 1.0), { creep = creepA, kind = "lasthit", walk = 0, due = 0, eta = 0, dies = 2 } }
	local a
	local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
	check("control: a walk over a second, a creep dying before walk + swing, or a last hit: no hold, no line",
		a == false and w.starts == 0 and #lines(out, "kind=deny") == 0, tostring(a) .. " " .. w.starts)
end

do -- control: a position the trip table holds back (the cores)
	for _, case in ipairs({ { pos = 1, lane = Lane.Bot, name = "a pos 1" }, { pos = 3, lane = Lane.Top, name = "a pos 3" } }) do
		local w = world({ pos = case.pos, lane = case.lane })
		w.offers = { deny(creepA, 0, 0.2, 2) }
		local a
		local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
		check("control: " .. case.name .. " never applies or logs", a == false and w.starts == 0 and #lines(out, "kind=deny") == 0, tostring(a))
	end
end

do -- the off lane's pos 4 acts as the safe lane's pos 5 does
	local w = world({ pos = 4, lane = Lane.Top })
	w.offers = { deny(creepA, 0, 0.2, 2) }
	local a
	capture(function() a = w.SD.ROW.applies(w.sup) end)
	check("pos 4: a reachable deny holds the hero", a == true and w.starts == 1, tostring(a) .. " " .. w.starts)
end

do -- acting, then free: a held-back line, then the go line for the same creep
	local w = world()
	w.offers = { deny(creepA, 0, 0.2, 2) }
	w.sup.IsChanneling = function() return true end
	local a1, a2
	local out = capture(function()
		a1 = w.SD.ROW.applies(w.sup)
		a1 = w.SD.ROW.applies(w.sup) or a1
		w.sup.IsChanneling = function() return false end
		a2 = w.SD.ROW.applies(w.sup)
	end)
	local ch = lines(out, "kind=deny")
	check("acting: no hold while OHA channels, then the attempt starts", a1 == false and a2 == true and w.starts == 1, tostring(a1) .. " " .. tostring(a2))
	check("acting: one why=acting line, then one go=1 line with the same slot", #ch == 2 and field(ch[1], "why") == "acting"
		and field(ch[2], "go") == "1" and field(ch[1], "slot") == field(ch[2], "slot"), table.concat(ch, " | "))
end

do -- refused by the runner: a refused line, no hold
	local w = world({ refuse = true })
	w.offers = { deny(creepA, 0, 0.2, 2) }
	local a
	local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
	local ch = lines(out, "kind=deny")
	check("refused: no hold, why=refused", a == false and #ch == 1 and field(ch[1], "why") == "refused", table.concat(ch, " | "))
end

do -- skip: the nearest-due creep a teammate's hit kills is passed over for the next one in reach
	local w = world()
	w.offers = { deny(creepA, 0, 0.2, 2), deny(creepB, 0.5, 0.9, 3) }
	w.kills[creepA] = { by = "hero", attacker = mate, commit = 0.15 }
	local a
	local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
	local ch = lines(out, "kind=deny")
	check("skip: the attempt goes to the creep no teammate takes", a == true and w.starts == 1 and denyOpts(w).target == creepB, tostring(a))
	check("skip: one go=1 line, for the other creep, with no mate", #ch == 1 and field(ch[1], "go") == "1" and field(ch[1], "mate") == nil
		and tonumber(field(ch[1], "walk")) == 0.5, table.concat(ch, " | "))
end

do -- skip: every reachable deny taken by a teammate holds nothing and logs why=mate with the teammate and its commit
	local w = world()
	w.offers = { deny(creepA, 0, 0.2, 2) }
	w.kills[creepA] = { by = "hero", attacker = mate, commit = 0.15 }
	local a
	local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
	local ch = lines(out, "kind=deny")
	check("skip: no hold when a teammate takes the only deny", a == false and w.starts == 0, tostring(a))
	check("skip: why=mate mate=1 mc=0.15", #ch == 1 and field(ch[1], "why") == "mate" and field(ch[1], "mate") == "1"
		and tonumber(field(ch[1], "mc")) == 0.15, table.concat(ch, " | "))
end

do -- skip, not latched: a teammate's wind-up that cancels gives the creep back on the next round
	local w = world()
	w.offers = { deny(creepA, 0, 0.2, 2) }
	w.kills[creepA] = { by = "hero", attacker = mate, commit = 0.2 }
	local a1, a2
	local out = capture(function()
		a1 = w.SD.ROW.applies(w.sup)
		w.kills[creepA] = nil
		a2 = w.SD.ROW.applies(w.sup)
	end)
	local ch = lines(out, "kind=deny")
	check("cancel: skipped, then attempted once the teammate's hit is gone", a1 == false and a2 == true and w.starts == 1, tostring(a1) .. " " .. tostring(a2))
	check("cancel: a why=mate line, then a go=1 line for the same creep", #ch == 2 and field(ch[1], "why") == "mate" and field(ch[2], "go") == "1",
		table.concat(ch, " | "))
end

do -- controls: a killing hit that is not a teammate's leaves the attempt as the solo deny made it
	for _, case in ipairs({
		{ name = "an enemy hero's", k = { by = "hero", attacker = foe, commit = 0 } },
		{ name = "the bot's own", k = "self" },
		{ name = "a creep's", k = { by = "creep", attacker = MakeCreep({ team = 3, loc = Vector(200, -5000) }), commit = 0 } },
	}) do
		local w = world()
		w.offers = { deny(creepA, 0, 0.2, 2) }
		w.kills[creepA] = case.k == "self" and { by = "self", attacker = w.sup, commit = 0 } or case.k
		local a
		local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
		local ch = lines(out, "kind=deny")
		check("control: " .. case.name .. " killing hit: the attempt starts", a == true and w.starts == 1 and #ch == 1
			and field(ch[1], "go") == "1" and field(ch[1], "mate") == nil, table.concat(ch, " | "))
	end
end

do -- live drop: a started attempt's verb is told to stop before its swing once a teammate's hit takes the creep
	local w = world()
	w.offers = { deny(creepA, 0, 0.2, 2) }
	local a, before, after
	local out = capture(function()
		a = w.SD.ROW.applies(w.sup)
		local opts = denyOpts(w)
		before = opts.interruptIf()
		w.kills[creepA] = { by = "hero", attacker = mate, commit = 0 }
		after = opts.interruptIf()
		w.onEnd({ success = false, reason = "interrupted" })
	end)
	local jobs = lines(out, "job=deny")
	check("live drop: the verb's interrupt is false, then true once the teammate's hit kills it", a == true and before == false and after == true,
		tostring(before) .. " " .. tostring(after))
	check("live drop: the job ends why=mate", #jobs == 2 and field(jobs[2], "why") == "mate", table.concat(jobs, " | "))
end

do -- shadow: the reference arm logs the same read, why=off with the teammate on it
	local w = world({ on = false })
	w.offers = { deny(creepA, 0, 0.2, 2) }
	w.kills[creepA] = { by = "hero", attacker = mate, commit = 0 }
	local out = capture(function() w.SD.ROW.applies(w.sup) end)
	local ch = lines(out, "kind=deny")
	check("shadow: why=off src=shadow with mate=1", #ch == 1 and field(ch[1], "why") == "off" and field(ch[1], "src") == "shadow"
		and field(ch[1], "mate") == "1", table.concat(ch, " | "))
end

do -- the hold strength: soft (plan s3), so Valve's attack outbids an attempt when it wants the hero
	local w = world()
	check("the deny row holds soft", w.SD.ROW.soft == true, tostring(w.SD.ROW.soft))
end

finish()
