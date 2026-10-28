# SimpleHost example (plain bot script)

Runs a lua-tasks task in a bot script that is not OHA: 30 s into the game each bot walks to the river centre,
waits 3 s and walks back, hosted on the farm mode.

## Install
1. In `packages/lua-tasks`: `npm run build`.
2. Copy `dist/tasks.lua` and `examples/generic/mode_farm_generic.lua` into
   `<Steam>/steamapps/common/dota 2 beta/game/dota/scripts/vscripts/bots/`.
3. Start a lobby with bots using the local dev script, with `-console` in the launch options.

This file replaces Valve's farm mode for these bots: farm only wins while a task claims it.

## Expected console output
```
[scout] npc_dota_hero_<name> started
[scout] npc_dota_hero_<name> ended ok
```
`ended preempted` means a higher-desire mode (retreat, attack, ...) took over; the task is not restarted.
Runner refusals and errors print as `[tasks] ...` (`debug = true`).

## Using it in your own mode files
At the bottom of any `mode_<name>_generic.lua` that should host tasks:
```lua
local M = tasks.SimpleHost.wrapMode(BOT_MODE_<NAME>, { GetDesire = GetDesire, Think = Think, OnStart = OnStart, OnEnd = OnEnd })
GetDesire, Think, OnStart, OnEnd = M.GetDesire, M.Think, M.OnStart, M.OnEnd
```
The wrapped `GetDesire` also ticks the runner (grace, stall and preemption checks), so the host mode's file must
be loaded for every bot that runs tasks. A mode file without its own `Think` should return a number, not nil,
from `GetDesire`: the wrapped `Think` replaces Valve's built-in one.

Task bodies in Lua use `SimpleHost.body(function(run) ... end)`: `run(verb)` runs a verb to completion one
frame at a time, `coroutine.yield()` ends a frame.

## Unverified in-game
- That `require`d modules are shared between one bot's script files (only needed if you start a task in one
  file and host it in another; this example keeps everything in one file).
- That a floor of 0.75 beats laning at 0:30.
