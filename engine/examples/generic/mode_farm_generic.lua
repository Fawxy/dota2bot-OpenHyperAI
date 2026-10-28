-- lua-tasks SimpleHost example: hosts tasks on the farm mode. Copy next to tasks.lua in vscripts/bots/.
local tasks = require(GetScriptDirectory() .. "/tasks")
local Host, Tasks = tasks.SimpleHost, tasks.Tasks

Host.install({ debug = true })

local bot = GetBot()
local started = false

-- Walk to the river centre, wait 3 s, walk back to where the task started. A failed step ends the task.
local function scout()
    local home = bot:GetLocation()
    return Host.body(function(run, ctx)
        ctx.label("out")
        run(ctx.must(ctx.walkTo(Vector(0, 0, 0), { timeout = 60 })))
        ctx.label("look")
        run(ctx.must(ctx.wait(3)))
        ctx.label("back")
        return run(ctx.walkTo(home, { timeout = 60 }))
    end)
end

-- GetDesire runs every frame whatever the active mode, so it is a safe place to start a task.
function GetDesire()
    if not started and DotaTime() > 30 and bot:IsAlive() then
        started = Tasks.task(bot, {
            name = "scout",
            host = BOT_MODE_FARM,
            floor = 0.75,
            onEnd = function(r) print("[scout] " .. bot:GetUnitName() .. " ended " .. r.reason) end,
        }, scout())
        if started then print("[scout] " .. bot:GetUnitName() .. " started") end
    end
    -- Not nil: this file replaces Valve's farm Think, so farm must only win while a task claims it.
    return 0
end

function Think() end

-- The one line (two here) that adds task hosting to an existing mode file.
local M = Host.wrapMode(BOT_MODE_FARM, { GetDesire = GetDesire, Think = Think })
GetDesire, Think, OnStart, OnEnd = M.GetDesire, M.Think, M.OnStart, M.OnEnd
