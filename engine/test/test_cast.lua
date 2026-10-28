-- cast / useItem / pickUpRune stepped directly against the frame simulator.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

local DT = 0.1

local function run(sim, g, maxFrames)
    for _ = 1, maxFrames or 1000 do
        local r = g:next()
        if r.done then return r.value, sim.t end
        sim:step(DT)
    end
    error("generator did not finish", 0)
end

local function world()
    local sim = Sim.new()
    sim:adapter(tasks)
    return sim
end

-- cast -----------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 10, manaCost = 100, castPoint = 0.5 })
    local r, t = run(sim, V.cast(bot, ab))
    T.eq("cast no-target ok", r.reason, "ok")
    T.eq("cast ok: ability fired once", ab.fired, 1)
    T.check("cast ok only after the cast point", t >= 0.5 - 1e-9)
    T.eq("cast ok: no re-order once the phase was seen", bot:actionsOf("cast"), 1)
    T.near("cast ok: mana spent", bot.mana, 400)
end

-- Cooldown and mana show up a frame after the phase ends: must not be read as a cancelled phase.
do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 10, castPoint = 0.3, effectLag = 0.1 })
    local r = run(sim, V.cast(bot, ab))
    T.eq("cast with effect a frame late -> ok", r.reason, "ok")
end

do
    local sim = world()
    local bot = sim:addBot{}
    bot.ignoreOrders = true
    local ab = sim:addAbility(bot, { cooldown = 10, castPoint = 0.3 })
    local r, t = run(sim, V.cast(bot, ab))
    T.eq("cast order never takes -> timeout", r.reason, "timeout")
    T.near("cast never takes: times out at cast point + 1", t, 1.3, 0.05)
    T.check("cast never takes: re-ordered while nothing seen", bot:actionsOf("cast") >= 2)
end

do
    local sim = world()
    local bot = sim:addBot{}
    bot.ignoreOrders = true
    sim:at(0.4, function() bot.ignoreOrders = false end)
    local ab = sim:addAbility(bot, { cooldown = 10, castPoint = 0.3 })
    local r = run(sim, V.cast(bot, ab))
    T.eq("cast first order lost -> re-order lands -> ok", r.reason, "ok")
    T.eq("cast re-order: fired once", ab.fired, 1)
end

-- Mana is the only effect signal for a zero-cooldown ability.
do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 0, manaCost = 80, castPoint = 0.2 })
    local r = run(sim, V.cast(bot, ab))
    T.eq("cast confirmed by mana alone -> ok", r.reason, "ok")
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 10 })
    ab.cdEnd = 5
    local r = run(sim, V.cast(bot, ab))
    T.eq("cast on cooldown -> not_castable", r.reason, "not_castable")
    T.eq("cast on cooldown: no order", bot:actionsOf("cast"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { manaCost = 100 })
    bot.mana = 50
    local r = run(sim, V.cast(bot, ab))
    T.eq("cast without mana -> not_castable", r.reason, "not_castable")
end

do
    local sim = world()
    local bot = sim:addBot{}
    local r = run(sim, V.cast(bot, nil))
    T.eq("cast nil ability -> not_castable", r.reason, "not_castable")
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 10, castPoint = 0.6 })
    sim:at(0.3, function() bot.stunned = true end)
    local r, t = run(sim, V.cast(bot, ab))
    T.eq("cast phase cancelled by stun -> interrupted", r.reason, "interrupted")
    T.check("cast stun: well before the timeout", t < 1)
    T.eq("cast stun: ability never fired", ab.fired, 0)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local enemy = sim:addHero{ x = 300, team = 3 }
    local ab = sim:addAbility(bot, { cooldown = 10, castPoint = 0.6 })
    sim:at(0.3, function() sim:kill(enemy) end)
    local r = run(sim, V.cast(bot, ab, { target = enemy }))
    T.eq("cast target dies mid cast point -> no_target", r.reason, "no_target")
    T.eq("cast target dies: ability never fired", ab.fired, 0)
    T.check("cast unit target: order carried the target", bot.actions[1].kind == "cast_target" and bot.actions[1].target == enemy)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local enemy = sim:addHero{ x = 300, team = 3, hidden = true }
    local ab = sim:addAbility(bot, {})
    local r = run(sim, V.cast(bot, ab, { target = enemy }))
    T.eq("cast invisible target -> no_target", r.reason, "no_target")
    T.eq("cast invisible target: no order", bot:actionsOf("cast_target"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { castPoint = 0.2 })
    local r = run(sim, V.cast(bot, ab, { at = { x = 500, y = 200 } }))
    T.eq("cast at location ok", r.reason, "ok")
    T.near("cast at location: order carried the point", bot.actions[1].loc.x, 500)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { castPoint = 1.0 })
    local r, t = run(sim, V.cast(bot, ab, { deadline = 0.5 }))
    T.eq("cast deadline before the cast point ends -> timeout", r.reason, "timeout")
    T.near("cast deadline at 0.5", t, 0.5, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { castPoint = 1.0 })
    local r = run(sim, V.cast(bot, ab, { interruptIf = function() return sim.t >= 0.4 end }))
    T.eq("cast interruptIf -> interrupted", r.reason, "interrupted")
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 20, castPoint = 0.3, channelTime = 2 })
    local r, t = run(sim, V.cast(bot, ab, { channel = true }))
    T.eq("cast channel runs full time -> ok", r.reason, "ok")
    T.check("cast channel: finished after cast point + channel time", t >= 2.3 - 1e-9 and t < 2.6)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 20, castPoint = 0.3, channelTime = 2 })
    sim:at(1.2, function() bot.stunned = true end)
    local r, t = run(sim, V.cast(bot, ab, { channel = true }))
    T.eq("cast channel stunned early -> interrupted", r.reason, "interrupted")
    T.eq("cast channel stunned early: message", r.message, "channel ended early")
    T.near("cast channel stunned: noticed promptly", t, 1.2, 0.15)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, { cooldown = 20, castPoint = 0.3, channelTime = 2 })
    local r, t = run(sim, V.cast(bot, ab))
    T.eq("cast channelled without channel opt -> ok at cast", r.reason, "ok")
    T.check("cast without channel opt returns at the cast, not channel end", t < 1)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local ab = sim:addAbility(bot, {})
    local bare = {
        IsAlive = function() return true end,
        Action_UseAbility = function() end,
    }
    local r = run(sim, V.cast(bare, ab, { target = bot }))
    T.eq("cast without Action_UseAbilityOnEntity -> unsupported", r.reason, "unsupported")
end

-- useItem --------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{}
    local item = sim:giveItem(bot, 2, { name = "item_blink", cooldown = 15, castPoint = 0 })
    local r = run(sim, V.useItem(bot, "item_blink", { at = { x = 900, y = 0 } }))
    T.eq("useItem ok", r.reason, "ok")
    T.eq("useItem: the item fired", item.fired, 1)
    T.check("useItem: item now on cooldown", item:GetCooldownTimeRemaining() > 0)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local r = run(sim, V.useItem(bot, "item_blink"))
    T.eq("useItem missing -> no_item", r.reason, "no_item")
end

do
    local sim = world()
    local bot = sim:addBot{}
    local item = sim:giveItem(bot, 7, { name = "item_blink" })
    local r = run(sim, V.useItem(bot, "item_blink"))
    T.eq("useItem in backpack -> no_item", r.reason, "no_item")
    T.eq("useItem in backpack: not used", item.fired, 0)
end

-- pickUpRune -----------------------------------------------------------------

local RUNE = 1

do
    local sim = world()
    sim:installRuneGlobals()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    local rune = sim:addRune(RUNE, { x = 900, y = 0 })
    local r, t = run(sim, V.pickUpRune(bot, RUNE))
    T.eq("pickUpRune ok", r.reason, "ok")
    T.check("pickUpRune: we took it", rune.takenBy == bot)
    T.check("pickUpRune: walked there first", t >= 2.5)
    sim:removeRuneGlobals()
end

do
    local sim = world()
    sim:installRuneGlobals()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    local rune = sim:addRune(RUNE, { x = 900, y = 0 })
    sim:at(1.0, function() rune.status = Sim.RUNE_STATUS_MISSING end)
    local r, t = run(sim, V.pickUpRune(bot, RUNE))
    T.eq("pickUpRune taken by another mid-walk -> taken_by_other", r.reason, "taken_by_other")
    T.near("pickUpRune taken: noticed promptly", t, 1.0, 0.15)
    sim:removeRuneGlobals()
end

-- Someone grabs it while we stand on it: only a `confirmed` hook can tell.
do
    local sim = world()
    sim:installRuneGlobals()
    local bot = sim:addBot{ x = 1000, y = 0 }
    local rune = sim:addRune(RUNE, { x = 900, y = 0 })
    bot.blocked = true
    sim:at(0.2, function() rune.status = Sim.RUNE_STATUS_MISSING end)
    local r = run(sim, V.pickUpRune(bot, RUNE, { confirmed = function() return rune.takenBy == bot end }))
    T.eq("pickUpRune taken in range, confirmed() false -> taken_by_other", r.reason, "taken_by_other")
    sim:removeRuneGlobals()
end

do
    local sim = world()
    sim:installRuneGlobals()
    local bot = sim:addBot{ x = 0, y = 0 }
    sim:addRune(RUNE, { x = 900, y = 0, status = Sim.RUNE_STATUS_MISSING })
    local r = run(sim, V.pickUpRune(bot, RUNE))
    T.eq("pickUpRune already missing -> no_target", r.reason, "no_target")
    T.eq("pickUpRune already missing: no move", bot:actionsOf("move"), 0)
    sim:removeRuneGlobals()
end

do
    local sim = world()
    sim:installRuneGlobals()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    sim:addRune(RUNE, { x = 900, y = 0 })
    local r, t = run(sim, V.pickUpRune(bot, RUNE, { deadline = 1.0 }))
    T.eq("pickUpRune deadline mid-walk -> timeout", r.reason, "timeout")
    T.near("pickUpRune deadline at 1.0", t, 1.0, 0.15)
    sim:removeRuneGlobals()
end

do
    local sim = world()
    local bot = sim:addBot{}
    sim:addRune(RUNE, { x = 900, y = 0 })
    local r = run(sim, V.pickUpRune(bot, RUNE))
    T.eq("pickUpRune without Dota rune globals -> unsupported", r.reason, "unsupported")
end

print("test_cast (" .. T.runtime() .. ")")
T.finish()
