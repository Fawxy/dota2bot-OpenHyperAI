# Write your first task

Goal: shortly before 3:00 a bot walks to a bounty rune spot, waits for the spawn and picks the rune up. If its health drops
below 40% on the way, it gives up. This guide uses a plain Lua bot script and `SimpleHost`. Allow about 15 minutes.

## 1. Build and copy
In `engine/`, run `npm install && npm run build`. Then copy `../bots/FunLib/engine/tasks.lua` into
`<Steam>/steamapps/common/dota 2 beta/game/dota/scripts/vscripts/bots/`.

## 2. Pick a host mode
A task runs under one bot mode. While the task is live, SimpleHost raises that mode's desire to the task's `floor`.
When a stronger mode wins (retreat, a fight), the task ends `preempted`. Use the rune mode:
`bots/mode_rune_generic.lua`. That file replaces Valve's rune mode for every bot, which is fine for a first task.

## 3. Write the body
The body is the behaviour, read top to bottom. `run(verb)` runs one verb to completion, one frame at a time.
`ctx.must(verb)` ends the whole task when that verb fails.
```lua
local tasks = require(GetScriptDirectory() .. "/tasks")
local Host, Tasks = tasks.SimpleHost, tasks.Tasks

Host.install({ debug = true })

local bot = GetBot()
local started = false

local function runeTrip(rune, spawnAt)
    return Host.body(function(run, ctx)
        ctx.label("walk")
        run(ctx.must(ctx.walkTo(GetRuneSpawnLocation(rune), { timeout = 60, deadline = spawnAt + 5 })))
        ctx.label("wait")
        -- The rune's status may only turn available a moment after the spawn second.
        run(ctx.must(ctx.waitUntil(spawnAt + 0.5)))
        ctx.label("pickup")
        return run(ctx.pickUpRune(rune))
    end)
end
```
- `label` names the phase. It shows in `Tasks.Describe(bot)` and in `onEnd`.
- `deadline` is absolute game time. Past it, the walk fails `timeout`, and `must` ends the task with that result.
- The last verb's result is returned as the task's result.

## 4. Start it
Start the task from `GetDesire`, which Dota calls every frame for every mode file. `guard` is checked every frame,
and a string ends the task `interrupted` with that message.
```lua
function GetDesire()
    if not started and DotaTime() > 150 then
        local rune = GetTeam() == TEAM_RADIANT and RUNE_BOUNTY_1 or RUNE_BOUNTY_2
        started = Tasks.task(bot, {
            name = "rune",
            host = BOT_MODE_RUNE,
            floor = 0.8,
            guard = function()
                if bot:GetHealth() < 0.4 * bot:GetMaxHealth() then return "low hp" end
            end,
            onEnd = function(r, info)
                print("[rune] " .. bot:GetUnitName() .. " " .. r.reason .. " " .. tostring(r.message) .. " at " .. tostring(info.label))
            end,
        }, runeTrip(rune, 180))
    end
    return 0
end

function Think() end

local M = Host.wrapMode(BOT_MODE_RUNE, { GetDesire = GetDesire, Think = Think })
GetDesire, Think, OnStart, OnEnd = M.GetDesire, M.Think, M.OnStart, M.OnEnd
```
- The last two lines add task hosting to the file. The wrapped `GetDesire` ticks the runner and lifts the desire
  to `floor` while the task runs; the wrapped `Think` steps it.
- `GetDesire` returns 0, not nil. This file defines `Think`, so the rune mode must only win while a task claims it.
- Rune constants, locations and spawn times change between patches; check them for yours.

## 5. Run it
Start a lobby with bots on the local dev script, with `-console` in the launch options. Expect a console line like
`[rune] npc_dota_hero_<name> ok nil at pickup`. Other outcomes:
- `preempted` means a stronger mode took over; the task is not restarted.
- `interrupted low hp at <label>` is the guard firing.
- `[tasks] ...` lines are runner refusals and body errors.

## 6. Test it offline
Bot scripts are hard to debug in-game, so test the body first in plain Lua (LuaJIT or any Lua 5.1+). Load the bundle
with `dofile`, install SimpleHost with your own clock, give it a fake bot, and drive the frames. The README's
[Testing](../README.md#testing) section has a complete harness. For this task, also fake the rune globals the verbs
read and the health the guard reads:
```lua
RUNE_BOUNTY_1, RUNE_STATUS_AVAILABLE, RUNE_STATUS_MISSING = 1, 1, 2
local status = 0                                   -- unknown until it spawns
function GetRuneStatus() return status end
function GetRuneSpawnLocation() return { x = 300, y = 0 } end
function bot:Action_PickUpRune() status = RUNE_STATUS_MISSING end
function bot:GetHealth() return 1000 end                -- read by the guard
function bot:GetMaxHealth() return 1000 end
```
Set `status = RUNE_STATUS_AVAILABLE` once your fake clock passes 180, and the task should end `ok`.

## 7. The same body in TypeScript
In the bot's TypeScript, import the engine's types and write the body as a
generator. `yield*` replaces `run`:
```ts
import { Ctx, TaskBody, Vec } from "bots/FunLib/engine/tasks";

function* runeTrip(ctx: Ctx, rune: number, at: Vec, spawnAt: number): TaskBody {
    ctx.label("walk");
    yield* ctx.must(ctx.walkTo(at, { timeout: 60, deadline: spawnAt + 5 }));
    ctx.label("wait");
    yield* ctx.must(ctx.waitUntil(spawnAt + 0.5));
    ctx.label("pickup");
    return yield* ctx.pickUpRune(rune);
}
```
Start it with `Tasks.task(bot, opts, (ctx) => runeTrip(ctx, rune, at, 180))`.

## Next
- Combine verbs with `Flow.race`, `Flow.watch`, `Flow.retry` and `Flow.withTimeout` (see the [README](../README.md#combinators-flow)).
- Keep loops yielding: loop on verb results, or `coroutine.yield()` before retrying by hand.
