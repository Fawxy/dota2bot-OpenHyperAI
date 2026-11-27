dofile(HARNESS_DIR .. "/lane_world.lua")
-- The draw's row (aggro_row.ts, Ours.LaneAggro, no-creep-unpaid s6b): the go on a fresh read, the soft walk-in and hard order,
-- the draw's end, the hand-over to the creep row and the resume, and the lines. The task runner is stubbed (ForOurs); the verb's
-- body is driven frame by frame with a stub ctx. Its execution in game is the rig's.

local dota = require("bots/ts_libs/dota/index")
BOT_ACTION_TYPE_ATTACK = BOT_ACTION_TYPE_ATTACK or 4
local Lane, BotMode = dota.Lane, dota.BotMode

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function lines(all, pat) local r = {} for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(r, l) end end return r end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

-- The world: our core at (0, -5000) beside our ranged creep at (-300, -5000); our melee at (100, -5000) fought by their two melee
-- at (300, -5000); their hero seen at (1500, -5000). No towers, nothing due.
local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours.LaneAggro = o.on ~= false
	CURRENT_TEAM = 2
	T = 100
	TOWERS_W = { [2] = {}, [3] = {} }
	local w = { starts = 0, targets = {} }
	local F = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
	F.Verbs = function() return { laneTargets = function() return w.targets end } end
	F.Jobs = function() return {} end
	F.Running = function() return w.running end
	F.Tick = function() end
	-- The real Start wraps a row's onEnd with the decider's end hook (Tasks.WithRowEnd), which releases the claim; so does the stub.
	F.Start = function(bot, opts, body)
		opts = package.loaded["bots/FunLib/humaniser/tasks"].WithRowEnd(bot, opts)
		w.starts = w.starts + 1
		w.opts = opts
		local task = { name = opts.name }
		w.running = task
		w.task = task
		w.onEnd = function(r)
			if w.running == task then w.running = nil end
			opts.onEnd(r)
		end
		w.ctx = {
			now = function() return T end,
			ok = function() return { success = true, reason = "ok" } end,
			fail = function(reason, message) return { success = false, reason = reason, message = message } end,
			walkTo = function(loc)
				w.walkedTo = loc
				return { ____coroutine = coroutine.create(function() return { success = true, reason = "ok" } end) }
			end,
		}
		w.gen = body(w.ctx)
		return true
	end
	F.Step = function() return true end
	w.AO, w.AR, w.D = require("bots/FunLib/humaniser/aggro_offer"), H.AggroRow, H.Decider
	w.AO.ResetCache()
	w.AR.ResetCache()
	w.core = MakeUnit({ pid = 1, team = 2, bot = true, loc = Vector(0, -5000), hp = 600, maxhp = 600 })
	w.core.pos, w.core.lane, w.core.mode = o.pos or 2, Lane.Bot, BotMode.Laning
	w.core.action = BOT_ACTION_TYPE_ATTACK
	w.ours = MakeCreep({ team = 2, x = -300, y = -5000, name = "npc_dota_creep_goodguys_ranged" })
	w.melee = MakeCreep({ team = 2, x = 100, y = -5000 })
	w.m1 = MakeCreep({ team = 3, x = 300, y = -5000, target = w.melee })
	w.m2 = MakeCreep({ team = 3, x = 320, y = -4980, target = w.melee })
	w.foe = MakeUnit({ pid = 6, team = 3, bot = true, loc = Vector(1500, -5000), hp = 600, maxhp = 600 })
	return w
end

-- One frame of the verb: true once its body has returned, with the result kept in w.res.
local function frame(w)
	local r = w.gen:next()
	if r.done then
		w.res = r.value
		w.onEnd(r.value)
		return true
	end
	return false
end

local function ask(w) return w.D.Ask(w.core, w.AR.ROW) end

do -- the offer's place and seconds (the danger asked at each begin): the draw spot, the walk and the draw
	local w = world()
	local o
	capture(function() o = w.AR.ROW.wants(w.core) end)
	check("offer: at the draw spot, 200 from their nearest fighting creep; secs the draw's 2.5 with no walk past it", o ~= nil and o.at ~= nil and math.abs(o.at.x - 100) < 5 and math.abs(o.secs - (100 / w.core:GetCurrentMovementSpeed() + 2.5)) < 0.01,
		o and (tostring(o.at and o.at.x) .. " " .. tostring(o.secs)))
end

do -- off: the row never wants the hero; the read stays the shadow's
	local w = world({ on = false })
	check("off: no offer", w.AR.ROW.wants(w.core) == nil and w.starts == 0)
end

do -- a clean chance: go, the order on their hero, the walk back, the end when the draw lets go
	local w = world()
	local held, soft0, soft1, done
	local out = capture(function()
		held = ask(w)
		soft0 = w.AR.ROW.soft(w.core)
		frame(w) -- no walk: the read again and the order
		soft1 = w.AR.ROW.soft(w.core)
		w.m1.target, w.m2.target = w.core, w.core
		-- Melee drawn: the draw lets go at about 2.3 s after the order.
		for _ = 1, 23 do T = T + 0.1 frame(w) end
		w.m1.target, w.m2.target = w.ours, w.ours
		for _ = 1, 10 do
			T = T + 0.1
			done = frame(w)
			if done then break end
		end
	end)
	local atk = ActionsOf(1, "AttackUnit")
	local mv = ActionsOf(1, "MoveToLocation")
	check("go: the row holds and starts one task", held == true and w.starts == 1)
	check("go: soft while walking in, hard from the order", soft0 == true and soft1 == false, tostring(soft0) .. " " .. tostring(soft1))
	check("order: one attack order, on their hero, once", #atk == 1 and atk[1].args[1] == w.foe and atk[1].args[2] == true, #atk)
	check("back: walks to 250 behind our ranged creep, away from the clash", #mv > 0 and math.abs(mv[#mv].args[1].x - (-300 - 250)) < 5, mv[#mv] and mv[#mv].args[1].x)
	check("end: ok once no drawn creep is on the hero", done == true and w.res.success == true, w.res and w.res.reason)
	local jobs = lines(out, "job=aggro")
	local e = jobs[#jobs]
	check("lines: start, order, end", #jobs == 3 and field(jobs[1], "phase") == "start" and field(jobs[2], "phase") == "order" and field(e, "phase") == "end", table.concat(jobs, " | "))
	check("end line: two drawn, two on the hero at most, two on our ranged creep", field(e, "an") == "2" and field(e, "ah") == "2" and field(e, "ar") == "2", e)
	check("the aid is shared", field(jobs[1], "aid") ~= nil and field(jobs[1], "aid") == field(e, "aid"))
end

do -- nothing drawn: missed nodraw after the switch time
	local w = world()
	capture(function()
		ask(w)
		frame(w)
		for _ = 1, 12 do T = T + 0.1 if frame(w) then break end end
	end)
	check("nodraw: missed once the switch time passed with none on the hero", w.res ~= nil and w.res.reason == "missed" and w.res.message == "nodraw", w.res and w.res.reason)
end

do -- chasers that close on the hero without naming it (rig r2): drawn, so the walk back lasts to the let-go time, not nodraw at 1 s
	local w = world()
	local endT
	capture(function()
		ask(w)
		frame(w)
		for i = 1, 30 do
			T = T + 0.1
			w.m1.loc = Vector(300 - 20 * i, -5000)
			if frame(w) then endT = T break end
		end
	end)
	check("chasers: ok, not nodraw", w.res ~= nil and w.res.success == true, w.res and (w.res.reason .. " " .. tostring(w.res.message)))
	check("chasers: ended at the melee let-go time, not at 1 s", endT ~= nil and endT - 100 >= 2.3 - 1e-6, endT)
end

do -- the control: a last hit the draw would cost holds it back (their creep left at the clash, not drawn)
	local w = world()
	local far = MakeCreep({ team = 3, x = 1400, y = -5000, hp = 40, target = w.melee })
	w.targets = { { creep = far, kind = "lasthit", due = 1.0, eta = 1.0, walk = 0, ranged = false, dies = 1 } }
	check("control: a last hit given up is no go", ask(w) == false and w.starts == 0)
end

do -- no enemy hero seen: no go
	local w = world()
	w.foe.alive = false
	check("unseen: no go", ask(w) == false and w.starts == 0)
end

do -- the hand-over: the creep row replaces the draw mid-walk; the walk back resumes with the same aid
	local w = world()
	local out = capture(function()
		ask(w)
		frame(w)
		w.m1.target, w.m2.target = w.core, w.core
		T = T + 0.5
		frame(w)
		-- The creep row begins over the draw: the runner ends ours cancelled, replaced.
		w.running = { name = "creep" }
		w.onEnd({ success = false, reason = "cancelled", message = "replaced" })
		-- The creep row's attempt ends (the decider asks the creep row first while it runs, so the draw is not asked meanwhile).
		w.running = nil
		T = T + 0.5
		ask(w)
	end)
	local jobs = lines(out, "job=aggro")
	local res = lines(out, "phase=resume")
	check("hand-over: the end reads cut=replaced", #lines(out, "cut=replaced") == 1, table.concat(jobs, " | "))
	check("resume: the walk back is taken up again with the same aid", #res == 1 and field(res[1], "aid") == field(jobs[1], "aid") and w.starts == 2, table.concat(jobs, " | "))
end

do -- no resume once the drawn creeps left the hero
	local w = world()
	capture(function()
		ask(w)
		frame(w)
		T = T + 0.5
		frame(w)
		w.onEnd({ success = false, reason = "cancelled", message = "replaced" })
		T = T + 0.5
	end)
	check("no resume: nothing on the hero, nothing to walk back for (and the cooldown holds a new draw)", ask(w) == false and w.starts == 1, w.starts)
end

do -- the claim: a key of the draw's own, never our ranged creep's (a creep key is a last hit's or a deny's), released at the end
	local w = world()
	local held, on, after
	capture(function()
		ask(w)
		local C = package.loaded["bots/FunLib/humaniser/claims"]
		local cid = package.loaded["bots/FunLib/humaniser/telemetry"].CreepId(w.ours)
		held, on = C.HeldBy(1) == "draw:" .. cid, #C.ClaimsOn("creep:" .. cid)
		frame(w)
		for _ = 1, 12 do T = T + 0.1 if frame(w) then break end end
		after = C.HeldBy(1)
	end)
	check("claim: draw:<cid> while it runs, none on our ranged creep", held == true and on == 0, tostring(held) .. " " .. tostring(on))
	check("claim: released at the end", w.res ~= nil and after == nil, tostring(after))
end

do -- a fight (Ours.FightFirst): the decider refuses the resume as it would any start
	local w = world()
	package.loaded["bots/FunLib/custom_loader"].Ours.FightFirst = true
	local held
	local out = capture(function()
		ask(w)
		frame(w)
		w.m1.target, w.m2.target = w.core, w.core
		T = T + 0.5
		frame(w)
		w.onEnd({ success = false, reason = "preempted" })
		w.core.mode = BotMode.Attack
		T = T + 0.5
		held = ask(w)
	end)
	check("fight: no resume while Valve has the hero in attack, and the refusal is logged", held == false and w.starts == 1 and #lines(out, "ref=aggro") == 1, table.concat(out, " | "))
end

do -- the decider lets the creep row begin over the draw: a lower row's task
	local w = world()
	local CR = package.loaded["bots/FunLib/humaniser/creep_row"]
	check("below: the draw's task is below the creep row", w.D.Below(CR.ROW, "aggro") == true and w.D.Below(w.AR.ROW, "creep") == false)
end

finish()
