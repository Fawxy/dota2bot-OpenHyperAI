# lua-tasks (the bot's engine)

The bot's internal engine (moved from dota-bot-sdk in slice 0b): task runner and verbs for Dota 2 bot scripts, written in TypeScript and compiled to one Lua file (TSTL, Lua 5.1 /
LuaJIT). You write a behaviour as one readable body. The runner resumes it once per frame, and verbs (walk,
attack, cast, ...) check that their orders actually took effect.

New to it? Start with [Write your first task](docs/first-task.md). A complete plain-bot-script example is in
[`examples/generic/`](examples/generic/README.md).

This README covers the stable core. `States` and the lane verbs (`lastHit`, `deny`, `laneFarm`, `nextLastHit`) are
exported but still changing, so they are not documented here. The job verbs (`stack`, `pull`, `runeRun`, `clearCamp`,
`gank`) are bot code since slice 0b (`humaniser/job_verbs`).

## Build
```sh
npm install
npm run build      # ../bots/FunLib/engine/tasks.lua (the bundle), ../typescript/bots/FunLib/engine/decl/*.d.ts, dist/tasks_test.lua
npm test           # syntax check, then every test/test_*.lua under fengari and LuaJIT (needs `luajit` on PATH)
```
The bot imports it as `bots/FunLib/engine/tasks` (types) and requires the bundle lazily (`humaniser/tasks`). The bot's
`npm run build` builds the engine first. Commit the outputs with the source change.

## SimpleHost: plain bot scripts
`SimpleHost` is a ready-made [Adapter](#the-adapter) for Valve's mode files. A task runs under one bot mode, its
**host mode**. While the task is live it lifts that mode's desire to the task's `floor`. The runner steps it from
the mode's `Think`, and it ends `preempted` when another mode wins.

```lua
local tasks = require(GetScriptDirectory() .. "/tasks")
local Host, Tasks = tasks.SimpleHost, tasks.Tasks

Host.install({ debug = true })   -- once per file; `debug` prints runner messages as [tasks] ...

local bot = GetBot()
local started = false

function GetDesire()
    if not started and DotaTime() > 30 then
        started = Tasks.task(bot, { name = "scout", host = BOT_MODE_FARM, floor = 0.75 }, Host.body(function(run, ctx)
            run(ctx.must(ctx.walkTo(Vector(0, 0, 0), { timeout = 60 })))
            return run(ctx.wait(3))
        end))
    end
    return 0
end

function Think() end

local M = Host.wrapMode(BOT_MODE_FARM, { GetDesire = GetDesire, Think = Think })
GetDesire, Think, OnStart, OnEnd = M.GetDesire, M.Think, M.OnStart, M.OnEnd
```
- `wrapMode(mode, fns)`: the wrapped `GetDesire` ticks the runner once per bot per frame and returns
  `max(your desire, floor)` while a task claims the mode. The wrapped `Think` steps the task, or else calls yours.
  The wrapped `OnEnd` preempts it.
- Every mode a task can be hosted on must be wrapped, or must call `Host.desire`/`Host.think`/`Host.onEnd` itself.
- A file that defines `Think` replaces Valve's built-in one, so its `GetDesire` should return a number, not nil.
- `Host.body(fn)` turns a plain function into a task body. Inside it:
  - `run(verb)` runs a verb to completion, one frame at a time, and returns its result;
  - `coroutine.yield()` ends a frame;
  - returning nothing counts as `ok`.
- `install` options: `now` (default `DotaTime`), `debug`, `enabled` (checked every frame), `claimTTL` (seconds a
  claim lives unposted; default 1), and `vector` (default: the global `Vector`). `SetEnabled(false)` is a kill switch: it cancels the task and
  refuses new ones.

## The Adapter
Any other host integrates through an `Adapter`, installed once with `init(adapter)`. Its fields are plain
functions (`adapter.fn(...)`, no `self`).

| Field | Required | Purpose |
|---|---|---|
| `claim(bot, { source, mode, tier, floor, urgent })` | yes | Re-posted every frame while a task is live. The host should make `mode` win with at least `floor` desire. `urgent` asks the host to skip its own hysteresis. |
| `release(bot, source, mode)` | yes | The task ended; drop its claim. |
| `now()` | yes | Game time in seconds. Every deadline and timeout uses this clock. |
| `log(tag, msg)` | yes | Runner refusals and body errors. |
| `enabled()` | yes | Kill switch: while false no task starts, and a running one is cancelled. |
| `vector(x, y, z)` | no | Builds the points verbs make themselves. Supply it when your move orders need a native `Vector` (SimpleHost does). |
| `hold(bot, tag)` | no | Called each frame a verb keeps the bot still on purpose (for hosts with a stuck detector). |
| `event(name, fields)` | no | Structured telemetry; without it, events go to `log`. |
| `skill(bot)`, `profile(bot)`, `random()` | no | Execution skill in [0, 1] (default 1), the reaction/jitter profile, and the random source (default `math.random`). |

`lastHitFilter`, `lastHitError` and `attackClock` are only read by the lane verbs (not covered here).

Then call the runner from two places:
- `Tasks.Tick(bot)` once per bot per frame, from code that runs whatever mode is active. It re-posts the claim and
  ends tasks that are dead, disabled, never started, stalled or preempted.
- `Tasks.Step(bot, mode)` from the host mode's `Think`. It resumes the body and returns true if it did.

## Tasks and the runner
```ts
Tasks.task(bot, { name: "scout", host: BOT_MODE_FARM }, (ctx) => body(ctx));  // false if refused
```
- One task per bot. Starting another replaces the first, which ends `cancelled` / `replaced`.
- The body is a factory `(ctx) => TaskBody`. A `TaskBody` is a generator that yields once per frame and returns a
  `Result`: `{ success, reason, message? }`. Returning nothing counts as `ok`.
- How a task ends:
  - The body returns.
  - The body throws, which ends it `error` (logged).
  - It is never stepped within `START_GRACE` (1 s): `preempted` / `never_started`.
  - It is not stepped for `stallAfter` s (default 2): `preempted` / `stalled`.
  - Its host mode loses for `preemptAfter` s (default 0): `preempted` / `mode=<id>`.
  - `guard()` returns a string: `interrupted`, with that string as the message.
  - The bot dies: `dead`.
  - The adapter is disabled.
  - `Tasks.Cancel(bot, reason, message?)`.
- `onEnd(result, { label, steps })` runs exactly once, after the claim is released. Do cleanup there: a
  generator's `finally` does not run when its task is cancelled.
- Other `TaskOptions`: `floor` (claim desire, default 0.6) and `tier` (passed through to the host's arbiter).
- To inspect: `Tasks.Current(bot)` (`name`, `host`, `steps`, `label`, ...), `Tasks.Last(bot)` (`name`, `result`) and
  `Tasks.Describe(bot)` (a one-line string for logs).

**Loops must yield.** A verb that finishes on its first resume returns without yielding (e.g. a walk whose
deadline has passed). Looping over such a verb without checking its result spins inside one frame, and nothing can
stop it. Loop on results: `must` the step that can fail, or `yield` before retrying by hand.

## Verbs
A verb is a generator `Verbs.<name>(bot, ..., opts?)`. It issues its orders every frame and ends with a `Result`.
Every verb takes `deadline` (absolute game time; fails `timeout`) and `interruptIf()` (fails `interrupted`). Every
verb fails `dead` if the bot dies. A handle method the verb needs but the bot lacks fails `unsupported` rather than
erroring.

| Verb | Ends ok when | Main options (defaults) |
|---|---|---|
| `walkTo(bot, loc, opts)` / `walkPath(bot, points, opts)` | Within `tolerance` of the (last) point. Fails `stuck` or `timeout`. | `tolerance` 150, `timeout` 10 s, `stuckSecs` 1.5 |
| `wait(bot, secs, opts)` | `secs` have passed | |
| `waitUntil(bot, t, opts)` | Game time reaches `t` (at once if it already has) | `hold`: tag for the adapter's `hold` |
| `holdAt(bot, point, opts)` | Never. A posture: it keeps the bot near `point()` (re-read every frame) until stopped. | `tolerance` 100, `repath` 1 s, `scatter` 50, `step` |
| `retreatTo(bot, { safe, ... })` | Reached `safe` | Walk options with `tolerance` 300, `timeout` 20 s, `stuckSecs` 3 |
| `attackAndConfirm(bot, pick, opts)` | A queued attack on `pick()` is seen to land. Fails `no_target` or `missed`. | `findFor`, `confirmFor` (required), `searchAt`, `confirmed()` |
| `cast(bot, ability, opts)` | The cooldown or mana shows the cast went off. Fails `not_castable`, `no_target`, `interrupted` or `timeout`. | `target` (unit) or `at` (ground), `channel`, `timeout` (cast point + 1 s) |
| `useItem(bot, itemName, opts)` | As `cast`, for an item in the six main slots. Fails `no_item`. | `cast` options |
| `pickUpRune(bot, rune, opts)` | The rune leaves `RUNE_STATUS_AVAILABLE` with the bot on it. Fails `no_target`, `taken_by_other`, `missed` or `timeout`. | `tolerance` 150, `timeout` 15 s, `confirmed()` |

Doc comments in `src/verbs.ts` and `src/verbs_cast.ts` give the exact rules, including what is still
`UNVERIFIED in-game`.

## The task context (`ctx`)
The body's argument. It holds the bot, task controls, and every verb bound to the bot (`ctx.walkTo(loc)` is
`Verbs.walkTo(bot, loc)`).

| Member | |
|---|---|
| `bot` | The bot handle. |
| `now()`, `elapsed()` | Game time; seconds since the task started. |
| `label(text)` | Names the current phase. Shown by `Tasks.Current`/`Describe` and passed to `onEnd`. |
| `urgent(on)` | Marks the task's claims urgent from the next one posted. |
| `ok()`, `fail(reason, message?)` | Build a `Result` to return. |
| `must(verb, message?)` | Runs the verb. On failure it ends the whole task with the verb's result (message replaced if given). |
| `abort(reason, message?)` | Ends the task with a failure from any depth. |
| `skill()`, `react()`, `jitter(secs)` | The adapter's skill (default 1), one sampled reaction delay, `secs * (1 +- jitter/2)` from the profile. |

```ts
function* scout(ctx: Ctx): TaskBody {
    ctx.label("out");
    yield* ctx.must(ctx.walkTo(river, { deadline: ctx.now() + 40 }));
    ctx.label("look");
    yield* ctx.must(ctx.wait(3));
    return yield* ctx.walkTo(home);
}
```
In Lua, `yield* g` is `run(g)` inside `Host.body`.

## Combinators (`Flow`)
| | |
|---|---|
| `watch(g, check)` | Steps `g`. Before each step, a string from `check()` ends it `interrupted` with that message. |
| `withTimeout(g, secs)` | `timeout` after `secs`, unless `g` finished first. |
| `retry(times, factory, shouldRetry?)` | Runs `factory(attempt)` again, the frame after each failure, while `shouldRetry(result)` allows (default: any failure). |
| `race(...gens)` | Steps all of them each frame and returns the first to finish, with `winner` (1-based). Let one branch act; make the others watchers. |
| `until(cond)` | Ends ok the frame `cond()` holds. In Lua: `Flow["until"]` (`until` is a keyword). |

```ts
// Hold the spot until the wave arrives, or for 20 s at most.
const r = yield* Flow.race(ctx.holdAt(() => spot), Flow.until(waveHere), ctx.wait(20));
```
A branch that is abandoned (the losers of `race`, or `g` when `watch`/`withTimeout` ends early) is not resumed again.

## Testing
Everything runs offline in plain Lua. Install SimpleHost with your own clock, give it a fake bot table, and drive
frames yourself:
```lua
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local Host, Tasks, FARM = tasks.SimpleHost, tasks.Tasks, 6
local t = 0
Host.install({ now = function() return t end })

local bot = { loc = { x = 0, y = 0 }, mode = FARM }
function bot:GetPlayerID() return 1 end
function bot:IsAlive() return true end
function bot:GetActiveMode() return self.mode end
function bot:GetLocation() return self.loc end
function bot:Action_MoveToLocation(p)   -- moves 30 units per order: 300 units/s at 10 frames/s
    local dx, dy = p.x - self.loc.x, p.y - self.loc.y
    local d = math.sqrt(dx * dx + dy * dy)
    local s = math.min(1, 30 / math.max(d, 1e-9))
    self.loc = { x = self.loc.x + dx * s, y = self.loc.y + dy * s }
end

Tasks.task(bot, { name = "walk", host = FARM }, Host.body(function(run, ctx)
    return run(ctx.walkTo({ x = 600, y = 0 }))
end))
for _ = 1, 50 do
    Host.desire(bot, FARM)   -- what the wrapped GetDesire does: ticks the runner
    Host.think(bot, FARM)    -- what the wrapped Think does: steps the task
    t = t + 0.1
end
assert(Tasks.Last(bot).result.reason == "ok")
```
- A single verb can be stepped without the runner: `local g = tasks.Verbs.wait(bot, 1)`, then call `g:next()` once
  per frame until `.done` (its `.value` is the `Result`). An adapter must still be installed for the clock.
- The SDK's own suite (`npm test`) uses a fuller frame simulator, `test/sim.lua`, with movement, creeps, attacks,
  projectiles and abilities. Copy it for heavier tests.
