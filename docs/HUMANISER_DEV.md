# Humaniser development guide

Working notes for the humaniser fork of OHA. Items marked **TODO (in-game)** still need confirming in a live lobby.

## Build
- Use yarn, which matches the checked-in `yarn.lock`. `npm install` fails on a peer conflict: `typescript-to-lua@1.26.2` pins `typescript@5.5.2`, but the project has `5.5.4`.
  ```bash
  PUPPETEER_SKIP_DOWNLOAD=1 npx --yes yarn@1 install --frozen-lockfile
  ```
  ```bash
  npm run build
  ```
- `bots/Customize/general.lua` is hand-written Lua. `typescript/bots/Customize/general.ts` only re-exports it, so humaniser config lives in the Lua file under `Customize.Humaniser`.

## Debug overlay
`typescript/bots/FunLib/humaniser/overlay.ts` draws while `Customize.Overrides.Label` is set, which dotactl does every
game with the run's label (`--no-overlay` leaves it out). Draws need `sv_cheats 1` (dotactl sets it); whether a
replay keeps them is untested.

- `DebugDrawText` is **screen-space only** with one large font, so text can't float above a hero. The block is at the top
  left: the label and build, then each team's line (its `Ours` switches on, or `stock`) and one line per position from the
  horn: our task (`name:label`, soft or hard) in yellow, Valve's mode in grey, `(row outbid)` when the decider holds the
  hero but another mode has it, `dead`. A ring on the map marks a hero while one of our jobs has it.
- `Customize.Humaniser.Debug = true` adds each hero's **reported** desires to its line (`DesireLog.Competing`). The bot API
  exposes only the active mode and its desire; the rest come from `Chooser.Gate`, which wraps each mode file's `GetDesire`.
  Modes whose `GetDesire()` returns nil fall back to Valve's C++ desire, which can't be read.
- `HDebug.Log(tag, ...)` (`debug.ts`, gated on Debug) prints `[H:tag] ...`. It bypasses OHA's `print` override (which stays silent unless `Utils.DebugMode`) through `Utils.RawPrint`, set in `aba_global_overrides.lua`.
- Drawing runs from `ItemUsageThink`, before its throttle, so it happens every frame; a dead hero's script does not run.

## Shared-state finding
**TODO (in-game).** This blocks the design of tasks 02, 05 and 06.

How to run the check: enable Debug and start a game with bots on both teams. Every 5 s, each bot logs:
```
[H:probe] pid=<id> team=<2|3> total=<n> mine=<n> playersInThisModule=<k> bothTeamsInThisModule=<bool>
```
- If `playersInThisModule` reaches 5 (and `total` is about 5 × `mine`), `require`d modules are **shared per team**.
- If it stays at 1, each bot has its own module instance.
- If `bothTeamsInThisModule=true`, Radiant and Dire share a VM.

Result: _not yet recorded._ Afterwards, delete `SharedStateProbe` from `debug.ts` and its call in `ability_item_usage_generic.lua`.

## Offline checks (no game needed)
```bash
cd tests/humaniser && npm install && npm run check
```
- `syntax` parses every `.lua` under `bots/` as LuaJIT, Dota's dialect. The checker also accepts `break;`, which upstream uses and LuaJIT allows.
- `test` runs `tests/humaniser/test_*.lua` in fengari (Lua 5.3 in JS) against the stubs in `dota_stubs.lua`. `FreshHumaniser(cfg)` loads a new module instance with the given `Customize.Humaniser`. Two instances in one test stand in for "modules are not shared between bots".
  - Each file runs in its own child process, 4 at a time (`node run.js --jobs N [files...]`; name files to run only the
    ones a change touches). The harness caches each module's compiled chunk per Lua state, so `FreshHumaniser` re-runs
    the chunk instead of parsing it again; a re-run still builds new module tables (Lua 5.3 may reuse a closure that
    captures nothing changed, so compare instances by their tables, not their functions). A test that needs a
    module's source changed on disk mid-file would see the old chunk (none does; `package.preload` still wins).
- `npm run check:calls` (repo root; `npm run build` runs it first and stops on a finding; its tests run in `npm run check` here as `anycall`; `npm run dev`, the watch build, skips it) fails on a member call with no declared signature (the callee is `any` or `Function`, a cast on the callee included) under `typescript/bots/FunLib/humaniser/`. The Lua build has `noImplicitSelf`, so such a call compiles to `x.Foo()` with no self argument: a unit method called without its unit, which only fails in a game. Declare the method on a typed interface (`h as Unit & { GetAttackPoint?(): number }`); a call that is meant to be a plain function call takes `// any-call-ok: <reason>` on its line or as a comment line above, one call per comment. OHA's own TypeScript and `engine/` are out of scope.
- These check logic and wiring only. Valve API semantics (ping types, chat callback delivery, modifier stacks) still need the in-game checks marked TODO in this file.
- `hlog` runs the telemetry analyser's tests (`tools/hlog/test`), including `hlog_session.lua`: a scripted mode switch and `!mark` through the real modules whose `[HEV]` output the analyser must read.

## Telemetry and log analysis
`Customize.Humaniser.Telemetry.Enable = true` (on in `general.lua`, off in the `config.ts` defaults) makes every bot print machine-readable `[HEV]` lines. They're independent of `Debug` and never change behaviour. The only visible effect is the `mark N saved` reply to `!mark`. The module is `typescript/bots/FunLib/humaniser/telemetry.ts`.

**Setup, once:** add `-condebug` to Dota's Steam launch options (next to `-console`). Dota then writes its console to `…/dota 2 beta/game/dota/console.log`. **TODO (in-game):** confirm that bot-VM prints reach that file, and whether it's overwritten or appended per launch. The analyser splits games on clock resets either way.

**While playing:** type `!mark <what looks wrong>` in chat (team or all). The team's lowest-PID bot replies `mark N saved`. Every bot logs its state at that moment (`mark_state`), including Dire's bots when you use all chat.

**Afterwards:**
```bash
node tools/hlog/analyse.js                 # latest game: per-player summary and checks
node tools/hlog/analyse.js --mark 2        # every bot's state at mark 2, plus the 20 s before it
node tools/hlog/analyse.js --from 4:30 --to 5:10 --pid 3 --ev mode,lasthit
node tools/hlog/analyse.js --check         # checks only; exit 1 on any FAIL
node tools/hlog/analyse.js --list          # games in the log; --game N picks one
```

**Humaniser off (A/B games):** telemetry has its own switch. With `Customize.Humaniser.Enable = false` and `Telemetry.Enable = true`, `Humaniser.Tick` runs only `Telemetry.Tick`: snapshots, `mode`, `lasthit`/`deny`, `game_end`, `lua_error`, and a `bot` line with `humaniser=0` and the read-only `skill`/`ally` (the profile is not built, because building it draws `RandomFloat`). Every humaniser hook still early-returns as before, so behaviour is upstream OHA. Not available off: every humaniser-only event, `by`/`order` on snapshots, and `!mark` (the humaniser chat hub isn't installed; upstream installs its own callback). `Customize.Enable = false` still turns telemetry off with everything else.

**Lua error guard (`Telemetry.LuaErrors`, default on with telemetry):** read once at load. `Humaniser.Tick` and the hooks other files call every frame (the `Chooser`, `Retreat`, `SustainAct`, `StackJob`, `Drill` and `States` hooks) run under `xpcall`. A throw is printed as `lua_error`, once per `where`+`msg` and again at most every `LuaErrorRepeat` s with the count, and is swallowed: the hook returns its feature-off value (raw desire, unfiltered list, `false`, `0`), so a humaniser bug degrades to upstream behaviour instead of losing the whole `GetDesire`/`Think` call. Reporting runs after `xpcall` returns, so a stack overflow, which Valve's handler prints only as `error in error handling`, is still attributed to its entry point. If the console shows `error in error handling` and there's no `lua_error`, the error came from outside the guarded entry points (upstream OHA or Valve code). Cost: roughly 0.03 µs per guarded call under the LuaJIT interpreter on an M4, so expect about 0.1 µs in Dota's Lua. Set `LuaErrors = false` to remove the wrappers.

**Line format:** `[HEV] t=<DotaTime> ev=<name> k=v ...`. A value with spaces, `"` or `=` is double-quoted with inner quotes turned into single quotes. Marks are emitted by every module instance. The analyser de-duplicates them, so the log looks the same whether or not modules are shared.

The full list of events and fields is `tools/hlog/EVENTS.md` (generated from `events.ts`). The ones the bot still writes and the analyser reads:

| `ev` | When | Key fields |
|---|---|---|
| `bot` | First tick, and when the position settles | `ally build pos ours` (logs before 23/11/2026 also carry the skill profile) |
| `player` / `snap` | Human allies are reported by the team's lowest-PID bot | Every `SnapshotInterval` (1 s): `x y alive hp mp lvl lh dn tgt`, plus for bots `mode d act gold by order` |
| `mode` | Active mode changed | `from to d dwell by` |
| `lasthit` / `deny` | Last-hit or deny counter rose | `human creep` |
| `ping` / `cmd` | Human ping or chat command | `context danger order` / `name args only text` |
| `mark` / `mark_state` | `!mark` | `n by text` / one bot's full state at the mark |
| `game_end` | An ancient fell or post-game started | |
| `lua_error` | A guarded humaniser entry point threw (`Telemetry.LuaErrors`) | `pid where n msg tb` (`where` e.g. `Chooser.FarmDesire`, `Retreat.Tick`, `Tick`; `n` running count; `tb` up to six `file.lua:line(fn)` frames, absent for a stack overflow) |

Legacy, declared for banked logs: `ping`, `cmd`, `notice`, `react`, `trainer`, `order_post`, `order_decline`, `order_accept`, `thrash`, `stuck`, `intent_cadence`, `lane_plan`, `lane_job_*`, `lane_signal`, `lane_take_skip`, `lane_enemy_role`, `lane_cover`, `lane_stack`, `lane_eq`, `rune_skip`, `tr_*`. No code writes them now.

**Checks** (`tools/hlog/checks.js`):

| Check | Fails or warns when |
|---|---|
| `script_errors` | **FAIL:** any Lua error line in the console (runtime errors and `[Humaniser] chat subscriber failed`). |
| `snapshot_gaps` | **FAIL:** a bot stops reporting for more than 10 s (its script stalled or errored). |
| `frozen_bots` | **WARN:** a live bot outside fountain range doesn't move for 10 s. |

`notice_delay`, `react_delay`, `order_read_delay`, `order_followed`, `intent_health` and `trainer_selftest` are still in `checks.js` but read events nothing writes, so they report no data on a new log.

**Tripwires** (`TRIPWIRES` in the same file): the outcomes every full game owes. `batch.js` runs them on every batch and prints only failures; `node tools/hlog/checks.js <manifest|run>` runs them on banked games and `--help` lists them.

**Mode churn** (summary section): OHA's `mode_team_roam_generic.lua` wants 1.5 whenever `X.GetLastHitCreep()` finds a killable creep, and `CapForLanePush` holds that to 0.72 in the laning phase. Every last-hit attempt is therefore a short team_roam visit out of laning. The analyser calls a team_roam visit entered from laning at exactly 0.72 and left within 2 s (to any mode) a *blip*. The section lists, per bot, total switches, blips, blips/min, other switches/min and the top three non-blip mode pairs. Blips are upstream behaviour, not a humaniser fault.

### Build stamp
- `npm run build` writes `bots/FunLib/humaniser/build_info.lua` (git-ignored) with the commit's short sha, plus `+dirty` if there are uncommitted changes. Every `bot` line carries `build=` and `pos=`, and every snapshot carries the scoreboard `kills=`/`deaths=` (snapshots stop while a bot is dead). **Commit first, then build.** The `bots` symlink is shared between worktrees and other sessions re-point it, so trust a game only when `build=` names the commit you meant.

## What our code is now
`typescript/bots/FunLib/humaniser/` holds the decider (`decider.ts`), the decisions behind `Customize.Ours` (the job
chooser and its stack, pull, pull-farm and rune jobs; retreat and the danger read; sustain), telemetry, and the drill
harness. With every `Ours` switch off a game plays as stock OHA: each of OHA's files differs from the stock branch
(`oha-stock-fix`) only by logging wrappers, the decider's host in `mode_farm_generic`, the `Ours` and drill hooks
(each returns its off value) and a few fixes.

The earlier features (ally last-hit etiquette, perception and difficulty, pings, orders and chat commands, the lane
planner and its camp jobs, intent arbitration, last-hit accuracy, the last-hit trainer, the core farm pattern,
Transitions, the state layer's owned and shadowed states) were deleted on 23/11/2026; tag `pre-humaniser-cut` holds
them, `pre-lane-body-cut` the lane body before it. `!mark <note>` is the one chat command left (telemetry).

### Rows and the decider
A behaviour is a row (`Decider.Row` in `decider.ts`), and only the decider starts a row's task: a start replaces whatever
task the hero has (the runner's `replaced`), so the order among rows is the decider's. A row is wired as:

- `name`: logged as `held`, and the name of the row's task (the decider reads the runner's current task by it).
- `wants(bot)`: asked every desire round in doctrine order until a row answers. Returns an `Offer` (`tgt`, the target;
  `by`, the game time it must go by; both optional) while its task runs or when it would start one now, else undefined.
  It checks its own `Ours.<Name>` switch, may keep its memo and write its own decision line (`ev=choice`), and keeps what
  it decided for `begin`; it starts, cancels and orders nothing.
- `begin(bot)`: starts the task as `wants` decided it (the aid, the go line, the job line); false when the runner
  refused (it writes the `refused` line). Called only by the decider, which then passes the turn to the next row.
- `step(bot)`: one frame of the verb from farm's Think while the row holds; true when finished. `soft` as before.
- Registration: `index.ts` pushes the row into `Decider.ROWS` in doctrine order and wraps `wants`, `begin` and `step` in
  guards (an error: no offer, not begun, finished).

The decider begins the first row that wants the hero when its task is not running. A higher row begun while a lower row's
task runs takes the hero from it; the decider's `ev=choice kind=decider` line then carries `beg`, the offer (`btgt`,
`bby`) and `over` (the task replaced). A row that decides at a read of its own between rounds (the creep row, at the
creep offer read) keeps its choice and calls `Decider.Offer(bot, row)`: the decider begins it in that call unless a row
above holds the hero. `tasks.ts` refuses and logs (`ev=lua_error where=Tasks.Start`) a start of a row's task (`pull`,
`stack`, `rune_detour`, `creep`) that does not come through the decider's begin; the job chooser's stack
(`StackJob.Wants`) names itself and is exempt. Offline: `tests/humaniser/test_decider.lua`.

## Task runner
Coroutine task runner: a task is a generator body (`walkTo`, `wait`, `lastHit`, ...) resumed once per frame from its host mode's `Think()`. OHA side: `FunLib/humaniser/tasks.lua` (TS: `tasks.ts`), exposed as `J.Humaniser.Tasks`.

- **Engine code:** `bots/FunLib/engine/tasks.lua` (TSTL bundle) and `typescript/bots/FunLib/engine/decl/` (declarations) are built from `engine/src` (lua-tasks). Do not edit them; change `engine/src` (master skill `engine-change`), run `npm run build:engine` (`npm run build` builds the engine first) and commit the outputs. Engine tests: `npm test` in `engine/`.
- **Loading:** the bundle is required lazily under `pcall`, only when the humaniser and `Tasks.Enable` are on, so a bundle that fails to load cannot break the rest of the humaniser. The first load attempt in each script context always prints one `[H:tasks] support ...` line (not gated on Debug).
- **Adapter:** no task posts a claim (the jobs hold their host mode through the chooser); skill is 1, with no reaction delay, jitter or last-hit error; `lastHit` is filtered by `mayTake` (`tasks.ts`): a bot outside positions 1 and 2 leaves a creep to an allied core (position 1-3, within 1,600) that can reach it. That is a direct position check, which master `docs/team/ARCHITECTURE.md` rule 2 (positions differ through one table) does not allow; it describes the code as it is, not a pattern to copy.
- **API:** `Tasks.Start(bot, { name, host, tier?, floor? }, body)`, `Tasks.Step(bot, mode)` from the host mode's `Think()`, `Tasks.Tick(bot)` (run from `Humaniser.Tick`: cancels the task when the bot dies or leaves the host mode), `Tasks.Describe(bot)`, `Tasks.Verbs()`. All return false/nil when disabled or the bundle failed to load.
- **Kill switch:** `Customize.Humaniser.Tasks.Enable = false` (or `Humaniser.Enable = false`): the bundle is never required and nothing is printed.
- **Overlay** (Debug): `task: <name> step=<n>`, or `- last=<name> <ok|reason>` once it ends.
- **Offline:** `tests/humaniser/test_tasks_integration.lua`.

### Job verbs (`job_verbs.ts`)
Generic, skill-scaled bodies for the support clock. Each takes its geometry and times
as a plan; the host (`camps`/`stacking`, `GetNeutralSpawners()`, rotation) supplies the data and
decides *when* to start; the verb executes. `JobVerbs.*(bot, plan, hooks?)` report phases through `{ label?, urgent? }`
(pass the task's `ctx.label`/`ctx.urgent`); `Tasks.Jobs()` returns the module once the engine bundle has loaded (it is
bound to the bundle and its adapter by `JobVerbs.Bind`). Tests: `tests/humaniser/test_job_verbs.lua`. Callers: `stack_job.ts` (`stack`), `pull_job.ts` (`pull`, which passes no `first`), `rune_job.ts` (`runeRun`, `runeSpawnRun`); nothing outside the tests calls `clearCamp` or `gank`. Defaults are OHA's `lane_config` values, so OHA data passes through unchanged.

**Camp** `{ stand, box?, origin?, margin? = 300, search? = 700, pick?, confirmed? }`. `campNeutral(bot, camp)`:
the nearest alive, visible neutral (`GetNearbyNeutralCreeps`) inside the box grown by `margin` (OHA
`Radii.BoxMargin`). This is the fix for the `CampNeutral` known issue (`engine/docs/API.md`, "In-game checks outstanding"): pass the spawner's `min`/`max` as
`box` rather than OHA's strict-box `pick`. While nothing is seen at the aggro second the bot walks to `origin`.

**Aggro (shared by stack and pull).** `aggroAt` is when the hit should **land** (OHA's `baseAggro`, the camp's
second, with no host jitter). The verb draws one `Skill.timingError(bot)` per job (Gaussian, sigma
`lerp(1.5, 0.2, skill)` s = OHA `Curves.JitterSigma`, clamped at 2.5 sigma; override with `timingError`, 0 =
exact) and orders the attack `aggroLead(bot, target)` early (walk into range + wind-up + projectile flight,
`ownHitTime`; 0.4 s without `GetAttackPoint`, at most 1.5 s; override with `aggroLead`). A neutral already in
sight is hit from wherever the bot is (OHA's travel rule); otherwise the bot waits at `stand` (hold `job_wait`)
and walks back if pushed off. The hit is confirmed by `attackAndConfirm` (hold `job_aggro`). Failures use OHA's
messages: `timeout`/`late` (not at the stand by aggroAt + err + `startLate` 2 s), `no_target`/`mistake:no-camp`
(nothing in the box by + `noCampAfter` 1 s), `missed`/`mistake:no-aggro` (hit not seen within `confirmFor` 2 s).
`onAggro({ camp, planned, error, orderedAt, confirmedAt })` fires on each confirmed hit (OHA `NoteStackAggro`).

**`stack(bot, { camp, aggroAt, exitPath, exitUntil, ...aggro })`**: urgent travel/wait/aggro, then `exit` along `exitPath` and hold (`stack_exit`)
until `exitUntil`. Labels `travel, wait, aggro, exit`.

**`pull(bot, { camp, aggroAt, lead, first?, watchSec? = 8, watchUntil?, leadDeadline?, ...aggro })`**: full
and double pulls are one body; the timing lives in the data (:15/:45 small, :18/:48 hard). `first = { camp, aggroAt }` makes a double: the hard camp is hit at its own second, then the
graded camp at `aggroAt` (one error for both, as OHA). Then `lead` (walk `lead` to the meet point, stuck after
3 s, deadline aggroAt + 15; failure message `lead`), then `watch` at the meet point for `watchSec` and until
`watchUntil` (hold `job_watch`). Urgent until the lead is done. Labels `travel, wait, aggro[, travel, wait,
aggro], lead, watch`. The divert grade stays OHA's (`MeasureDivert`/`Grade`).

**`runeRun(bot, { at, spawnAt, rune? | channel?, runeAt?, early? = 4, tolerance? = 150, lateBy? = 5,
pickupFor? = 10, radius? = 300, confirmed?, timingError? })`**: walk to `at` (fails `timeout`/`late` after
spawnAt + lateBy), wait (hold `rune_wait`) until the spawn plus one `Skill.react` delay, then either
`pickUpRune(rune)` (retried for 2 s while the rune is not yet reported) or, for a shrine (`channel`, wisdom: 3 s
within 300), stand in range for `channel` s, restarting the count when pushed out (`confirmed` false at the end:
`missed`). Labels `travel, wait, pickup|channel`. **Skill-scaled arrival:** `runeArriveBy(bot, plan)` =
spawnAt - `early * lerp(0.25, 1, skill)` + one timing error (drawn once per bot and spawn, so repeated calls
agree); `runeLeaveAt(bot, plan)` subtracts the straight walk at the current speed. The host starts the task at
`runeLeaveAt` (skill 1 arrives ~4 s early, skill 0.2 ~1.6 s and sometimes late).

**`clearCamp(bot, { at, radius? = 700, arrive? = 300, search? = 1600, deadline?, emptyAfter? = 0.5,
reorder? = 1, pick?, onEngage? })`**: walk to the camp centre, attack its neutrals (the current target
kept while alive, else the lowest HP one, or the host's `pick`), one order per target (re-given every `reorder` s),
one `Skill.react` delay before each new target after a kill. ok `cleared` (it fought) or `empty` (nothing seen for
`emptyAfter` s at the camp); `timeout` "late" past `deadline`. Labels `go`, then `farm` from the first frame a
neutral is in attack range + 100 (`onEngage` fires once, there).

**`gank(bot, { target, path, engageRange? = 700, telegraph?: { lead, fn }, commit?, lostGrace? = 2,
engageFor? = 8, deadline?, reorder? = 1, onEngage? })`**: walk the host's approach waypoints, then chase
the target (re-read every frame through `target()`) into `engageRange` and attack it, the first order one
`Skill.react` after reaching range. `telegraph.fn(eta)` fires once when the remaining path ETA falls to `lead` s.
ok `kill` when the target dies; `interrupted` "escaped" (out of sight `lostGrace` s), `timeout` "no-kill" (fighting
`engageFor` s), `timeout` "late" (not engaged by `deadline`), or `interrupted` with the host's `commit()` message.
Labels `travel`, `engage`; urgent while engaged.

UNVERIFIED in-game: `GetNearbyNeutralCreeps(radius)` (one argument) sees idle neutrals at 700 from the stand;
the lead estimate against a real attack order that walks into range; rune status before the spawn (treated as
not there until seen available, then retried for 2 s).

### In-game: check first
1. **`coroutine` is present in Dota's bot VM.** Expected console line: `[H:tasks] support coroutine=table bundle=ok`. `coroutine=nil` means the bundle loaded but every task reports `unsupported`.
2. **The luaBundle `require` shim works in Dota.** The same line shows `bundle=ok`. If it shows `bundle=fail <err>`, record the error here: no task code can run.
