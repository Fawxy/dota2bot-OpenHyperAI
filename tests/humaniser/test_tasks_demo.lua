dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Spike demo (humaniser/tasks_demo_gather.ts): GATHER/SMOKE/BACK run as one task, driven the way
-- mode_assemble_generic drives it: Desire every frame, Think only while assemble is the active mode.
local BUNDLE = "bots/FunLib/sdk/tasks/tasks"
local ASSEMBLE, RETREAT = BOT_MODE_ASSEMBLE, BOT_MODE_RETREAT
local DT, SPEED = 0.1, 100
local GOAL = Vector(2000, 0)
local ARRIVE = 500
local DEMO = { Enable = true, Tasks = { Enable = true, Demo = true } }

local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
local function moveCount(bot) return bot.moves and #bot.moves or 0 end

local function Fresh(cfg)
	ResetWorld()
	T = 10
	package.loaded[BUNDLE] = nil
	local H = FreshHumaniser(cfg or DEMO)
	local bot = MakeUnit({ pid = 1, mode = ASSEMBLE, loc = Vector(0, 0) })
	-- The first Tick loads the tasks bundle; IsActive() needs it.
	H.Tick(bot)
	return H, bot
end

-- Dota keeps executing the last move order, so the bot keeps walking toward it until it is there.
local function walk(bot)
	local target = bot.moves and bot.moves[#bot.moves]
	if target == nil then return end
	local d = dist(bot.loc, target)
	if d <= SPEED then bot.loc = Vector(target.x, target.y) return end
	bot.loc = Vector(bot.loc.x + (target.x - bot.loc.x) / d * SPEED, bot.loc.y + (target.y - bot.loc.y) / d * SPEED)
end

-- One frame, gated the way mode_assemble_generic gates the demo.
local function frame(H, bot)
	T = T + DT
	walk(bot)
	local desire
	if H.TasksDemo.IsActive() then
		desire = H.TasksDemo.Desire(bot)
		if bot.mode == ASSEMBLE then H.TasksDemo.Think(bot) end
	end
	H.Tick(bot)
	return desire
end

local function post(H, key, opts)
	local o = opts or {}
	return H.Orders.Post(2, { type = o.type or "GATHER", sourceKey = key, issuerPID = 0, location = o.location or GOAL, duration = o.duration or 8, maxResponders = 1 })
end

-- Frames until the bot has read and accepted the order (Profile reading delay).
local function accept(H, bot)
	for _ = 1, 50 do
		if H.Orders.GetFor(bot) ~= nil then return true end
		frame(H, bot)
	end
	return false
end

local function taskClaim(H, bot)
	local d = H.Intent.Resolve(bot, ASSEMBLE, 0)
	return d, H.Intent.Explain(bot, ASSEMBLE)
end

-- GATHER: walks to the point under the order floor, holds under the task's own claim until expiry, ends ok.
do
	local H, bot = Fresh()
	check("demo active with Tasks.Demo", H.TasksDemo.IsActive() == true)
	local order = post(H, "g1")
	check("order accepted", accept(H, bot))
	local name = "gather:" .. order.id
	local floor = H.Config.Get().Orders.DesireFloor

	local walkDesires, walkFrames = true, 0
	while dist(bot.loc, GOAL) > ARRIVE and walkFrames < 100 do
		local d = frame(H, bot)
		walkFrames = walkFrames + 1
		if d ~= floor and dist(bot.loc, GOAL) > ARRIVE then walkDesires = false end
	end
	check("Desire is the order floor while walking", walkDesires and walkFrames > 0, walkFrames)
	check("walk issues moves to the order point", moveCount(bot) >= walkFrames - 1 and bot.moves[1].x == GOAL.x and bot.moves[1].y == GOAL.y, moveCount(bot))
	check("bot reaches the point", dist(bot.loc, GOAL) <= ARRIVE, dist(bot.loc, GOAL))

	frame(H, bot)
	check("arrived: Desire drops like the executor's", H.TasksDemo.Desire(bot) == nil)
	check("task still running after arrival", H.Tasks.Describe(bot):find("^" .. name .. " step=") ~= nil, H.Tasks.Describe(bot))
	local d, why = taskClaim(H, bot)
	check("hold: task claim lifts assemble", d >= 0.6, d)
	check("hold: Explain names the task", why:find("by task:" .. name, 1, true) ~= nil, why)

	local movesAtHold = moveCount(bot)
	while T + DT < order.expiresAt - DT do frame(H, bot) end
	check("holds until the order expires", H.Tasks.Describe(bot):find("^" .. name .. " step=") ~= nil, H.Tasks.Describe(bot))
	check("no moves while holding", moveCount(bot) == movesAtHold, moveCount(bot) - movesAtHold)
	for _ = 1, 3 do frame(H, bot) end
	check("finishes ok at expiry", H.Tasks.Describe(bot) == "- last=" .. name .. " ok", H.Tasks.Describe(bot))
	local after, afterWhy = taskClaim(H, bot)
	check("claim lapses after the task", after < 0.6 and afterWhy:find("task:", 1, true) == nil, afterWhy)
	check("no new task once the order is gone", not H.TasksDemo.Think(bot))
end

-- Mode switch mid-walk: preempted, no moves after, and the demo restarts when assemble is active again.
do
	local H, bot = Fresh()
	local order = post(H, "g2")
	accept(H, bot)
	local name = "gather:" .. order.id
	for _ = 1, 3 do frame(H, bot) end
	check("walking before the switch", moveCount(bot) > 0 and H.Tasks.Describe(bot):find("^" .. name) ~= nil, H.Tasks.Describe(bot))
	bot.mode = RETREAT
	frame(H, bot)
	check("mode switch preempts", H.Tasks.Describe(bot) == "- last=" .. name .. " preempted", H.Tasks.Describe(bot))
	local n = moveCount(bot)
	for _ = 1, 5 do frame(H, bot) end
	check("no moves after cancellation", moveCount(bot) == n, moveCount(bot) - n)
	check("Desire still asks for assemble while the order is unfinished", H.TasksDemo.Desire(bot) ~= nil)
	bot.mode = ASSEMBLE
	frame(H, bot)
	check("demo restarts for the still-active order", H.Tasks.Describe(bot) == name .. " step=1" and moveCount(bot) == n + 1, H.Tasks.Describe(bot))
end

-- The order goes away mid-walk, by cancel or by expiry: interrupted.
do
	local H, bot = Fresh()
	local order = post(H, "g3")
	accept(H, bot)
	for _ = 1, 3 do frame(H, bot) end
	H.Orders.Cancel(2, order.id)
	frame(H, bot)
	check("cancelled mid-walk -> interrupted", H.Tasks.Describe(bot) == "- last=gather:" .. order.id .. " interrupted", H.Tasks.Describe(bot))
	local n = moveCount(bot)
	frame(H, bot)
	check("no restart for a cancelled order", moveCount(bot) == n and H.Tasks.Describe(bot):find("^%- last=") ~= nil, H.Tasks.Describe(bot))
end
do
	local H, bot = Fresh()
	local order = post(H, "g4", { location = Vector(9000, 0), duration = 3 })
	accept(H, bot)
	while T < order.expiresAt + 2 * DT do frame(H, bot) end
	check("expired mid-walk -> interrupted", dist(bot.loc, Vector(9000, 0)) > ARRIVE and H.Tasks.Describe(bot) == "- last=gather:" .. order.id .. " interrupted", H.Tasks.Describe(bot))
end

-- ATTACK stays on the legacy path even with the demo on.
do
	local H, bot = Fresh()
	post(H, "a1", { type = "ATTACK" })
	accept(H, bot)
	check("ATTACK: no demo desire", H.TasksDemo.Desire(bot) == nil)
	check("ATTACK: Think defers to legacy", H.TasksDemo.Think(bot) == false and moveCount(bot) == 0 and H.Tasks.Describe(bot) == "-")
end

-- Tasks.Demo=false: the gate is off, so the mode file never calls Desire/Think; nothing starts or claims.
do
	local H, bot = Fresh({ Enable = true, Tasks = { Enable = true, Demo = false } })
	check("Demo=false: tasks bundle loaded", H.Tasks.IsActive() == true)
	check("Demo=false: IsActive false", H.TasksDemo.IsActive() == false)
	post(H, "g5")
	accept(H, bot)
	for _ = 1, 5 do frame(H, bot) end
	check("Demo=false: no task started", H.Tasks.Describe(bot) == "-" and moveCount(bot) == 0, H.Tasks.Describe(bot))
	local d, why = taskClaim(H, bot)
	check("Demo=false: no task claim", d < 0.6 and why:find("task:", 1, true) == nil, why)
end

finish()
