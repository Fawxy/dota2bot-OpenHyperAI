dofile(HARNESS_DIR .. "/lane_world.lua")
-- The support's solo deny (support_deny.ts, Ours.SupportDeny, doctrine D12), a decider row. The engine's laneTargets and task
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
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportDeny = o.on ~= false
	T = 120
	local SD = require("bots/FunLib/humaniser/support_deny")
	SD.ResetCache()
	local sup = MakeUnit({ pid = 5, team = 2, bot = true, loc = Vector(0, -5000), hp = 600, maxhp = 600 })
	sup.lane, sup.pos = o.lane or Lane.Bot, o.pos or 5
	local w = { SD = SD, sup = sup, offers = {}, starts = 0, steps = 0 }
	local F = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
	F.Verbs = function() return { laneTargets = function() return w.offers end } end
	F.Tick = function() end
	F.Start = function(_, opts, body)
		w.starts = w.starts + 1
		w.onEnd, w.opts = opts.onEnd, opts
		return o.refuse ~= true
	end
	F.Step = function() w.steps = w.steps + 1 return true end
	return w
end

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

do -- control: not a side-lane support
	for _, case in ipairs({ { pos = 1, lane = Lane.Bot, name = "a pos 1" }, { pos = 4, lane = Lane.Mid, name = "a mid pos 4" } }) do
		local w = world({ pos = case.pos, lane = case.lane })
		w.offers = { deny(creepA, 0, 0.2, 2) }
		local a
		local out = capture(function() a = w.SD.ROW.applies(w.sup) end)
		check("control: " .. case.name .. " never applies or logs", a == false and w.starts == 0 and #lines(out, "kind=deny") == 0, tostring(a))
	end
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

finish()
