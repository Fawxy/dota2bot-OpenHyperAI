# 14: Last-hit trainer: design

Written 21/10/2026. It refines `handoffs/14-last-hit-trainer.md`, which has the full technical detail. Where this document and the handoff disagree, this document wins. Branch `h-14-trainer`, worktree `oha-h14`, taken from `humaniser` @ `d8d61b6`.

## Intent
The player wants to get better at last hitting, and needs **something actionable**, not just a scoreboard. After a stretch of lane they should know:
1. whether they are **early or late on average**
2. which **easy creeps they lost**: creeps with a wide window that they swung at too late, or never swung at
3. the **one thing to change next**

They also want **instant feedback on each creep** as it resolves. The fuller picture waits for **checkpoints**, when they can stop and read it.

**Scope rule from the player:** build only what turns out to be reasonable to achieve. The Phase 0 spike decides each risky piece. A piece that fails the spike is dropped or downgraded to its fallback, not engineered around.

## Goals
- A short verdict line for each creep, shown right after it resolves (died or swing finished).
- A new verdict for creeps the player could easily have taken but didn't: `MISSED_EASY`.
- A checkpoint summary at 5:00, at 10:00 and when laning ends, plus `!trainer stats` on demand. Each summary has:
  - a headline early/late figure
  - the count of easy misses
  - one "biggest leak" line chosen by fixed rules (see Part 4)
- A live timing bar over the creep, only if the spike shows debug draws are visible and smooth.
- A self-test, where a calibration bot is graded by the trainer, to prove the predictor is accurate before the verdicts are trusted.
- One command switches everything off, and the config kill switch means none of the trainer's code runs.

## Non-goals
- Fight review, item hints, or any trainer except last hits and denies.
- Custom HUD or Panorama UI. Neither scripting context can edit Dota's own health bars.
- Audio cues and VScript particle effects in v1. These are a possible phase 2 (see the end of this document).
- Coaching beyond last hitting, such as positioning or harass avoidance, other than noting when harassment hurts timing.

## Anti-goals (failure even if it technically works)
- **Blaming the player for creeps they couldn't take.** An empty or very narrow window never counts against them, and that includes `MISSED_EASY`.
- **Confident numbers that are wrong.** If the predictor fails self-test calibration, the bar and the timing details must not ship as if they were reliable.
- **Noise.** No spam: at most 3 verdict lines on screen, chat off by default, and the summary is 3–4 lines.
- **A visible FPS drop** at `host_timescale 1`.
- **Changing bot behaviour** when the trainer is off. The trainer is an observer. Only the self-test bot's last-hit timing is ever altered, and only when `SelfTest = true`.

## Constraints
- Runs **bot-side**, in the lowest-PID allied bot on the human's team, with a per-team flag so it runs only once (as in the handoff). It needs at least one allied bot.
- Follows the README conventions:
  - TypeScript in `typescript/bots/FunLib/humaniser/trainer/*.ts`, compiled with `npm run build`
  - pure-Lua edits only where a file is pure Lua (`jmz_func.lua`)
  - the kill switch `Customize.Humaniser.Trainer.LastHit.Enable`
  - per-frame caching and throttling
- Drawing needs `sv_cheats 1`. That's the existing practice setup, and the player is fine relying on cheats and FretBots.
- **The trainer draws independently of `Customize.Humaniser.Debug`.** `HDebug.Text`, `Circle` and `Draw` are all no-ops unless `Debug = true` (`debug.ts`), so the trainer calls `DebugDrawLine`/`DebugDrawText` through its own small draw module. It may reuse `HDebug.Log` for `[H:trainer]` logs, which correctly stay gated on Debug.
- Its screen text must not overlap HDebug's Radiant (x = 10) or Dire (x = 1100) column blocks when Debug is on.

## Subjects and lifecycle (my calls)
- **One human subject in v1:** the first human on the trainer bot's team, by lowest PID. Debug draws are probably visible only to the host, and the screen corner and summary are built for one reader. If a second human is on the team, log a warning once and ignore them. Supporting several humans is future work.
- **Self-test adds a second subject:** the self-test bot. It's graded alongside the human, with separate counters keyed by PID. Its verdicts go only to `[H:trainer]` logs and a `!trainer stats selftest` line, never to the human's screen corner. Self-test works with no human on the team, because the trainer bot still starts when it has any subject.
- **Nothing runs until `!trainer on`.** With `Enable = true` and the trainer off, only the command handler is live: no predictor, no watching creeps, no counters. Stats cover the time since the trainer was last switched on, or since `!trainer reset`. With `SelfTest = true`, the trainer switches on automatically at game start.

## Phase 0: spike (timebox 1 day, do first)
Everything on the handoff's spike list (visibility, smoothness, reading the human's hero, prediction on a human's handle), plus:

5. **Draw without Debug:** confirm `DebugDrawLine` and `DebugDrawText` render with `Humaniser.Debug = false` once `sv_cheats 1` is on.
6. **Bar style:** draw both bars over one creep and let the player pick in game. Default to the time bar if there's no preference.
   - **Time bar** (as in the handoff): a green start window slides toward a "now" tick.
   - **HP-style bar:** drawn just above the creep's real health bar. It shows current HP, a fixed line at the player's effective damage, and a ghost marker at the predicted HP when a hit started now would land. Swing when the ghost crosses the line. It can't align exactly with the real health bar, because the camera angle shifts things, and that's accepted.
7. **Tracking cost:** run the predictor on 4 creeps (2 with bars, plus 2 being watched for easy misses) and measure the frame cost. If it's noticeable, watched creeps update every 0.1–0.2 s instead of every frame, or only 1 is watched.
8. **VScript bridge latency**, only to decide phase 2: can a value written bot-side be read in FretBots' VScript context within about 0.1 s? Record yes or no. v1 doesn't depend on the answer.

Record all results and the bar decision in `docs/HUMANISER_DEV.md`. The handoff's fallbacks still apply:
- **No usable draws:** verdicts and summaries go to team chat from the trainer bot.
- **The human's attack timing is unreadable:** grade from outcomes only, and leave the early/late seconds out of the headline.

## Part 1: Predictor (`lh_predict.ts`)
As in the handoff: HP over time from OHA's incoming-damage helpers, the landing window `[tLandMin, tOther)`, the start window shifted back by the attack delay, smoothing, and the uncertain flag.

**Change:** the predictor also tracks **watched creeps**, not only the creeps with bars. These are lane creeps within 800 units of the player that are killable soon (`tOther` within 2 s). For enemy creeps the window is a last-hit window; for allied creeps under 50% HP, when denies are on, it's a deny window. For each watched creep it records the **widest start window seen in the creep's last 2 s** and whether that window was **reachable**: the player could start the swing in time, counting any walk into range at their move speed.

**Prediction maths:** get OHA's functions through a `Trainer.SetHelpers({...})` block in `jmz_func.lua`. Copy the pattern of `Pings.SetHelpers` and 07's `Lane.SetHelpers`. Expose:
- `WillKillTarget`
- `GetAttackProDelayTime`
- `GetTotalAttackWillRealDamage`
- `GetCreepAttackActivityWillRealDamage`
- `GetCreepAttackProjectileWillRealDamage`
- `IsInLaningPhase`

Don't import 07's helper table. 14 must build and run without 07.

## Part 2: The bar (`lh_draw.ts`), only if the spike passes
- Uses the style picked in the spike.
- Draws at most 2 bars: the player's current target first, then the most urgent killable creep.
- Enemy creeps get green. Deny targets get cyan. The bar is amber while the prediction is uncertain.
- Hidden when the player is dead, more than 1,200 units away, or `Bar = false`.

## Part 3: Verdicts for each creep (`lh_judge.ts`)
Use the handoff's verdict table as it is: `PERFECT`, `OK`, `EARLY`, `LATE`, `CANCELLED`, `MISS`. Then add:

| Verdict | Detected by | Reason text, for example |
|---|---|---|
| `MISSED_EASY` | A watched creep died, and the player didn't get the last hit or deny. Its widest start window in its last 2 s was at least `EasyWindow` (default 0.3 s) and reachable. At the time, the player was alive, not disabled, and not channelling. The player either made no attempt on it, or their only attempt was `LATE`. | `missed easy one – 0.42s window, ranged creep, no swing` / `missed easy one – 0.35s window, you were 0.20s late` |

Rules:
- A `LATE` attempt on a wide-window creep is reported as `MISSED_EASY` instead of `LATE`, so the player never sees two lines for one creep. The early/late statistics still count it as late.
- A creep taken by an allied bot still counts as a miss for the player, because task 04 already makes allies defer to humans. The reason names who took it: `– Lion took it after you passed`.
- **Not counted:** creeps that died while the player was in a hero fight, meaning they dealt hero damage in the last 2 s. Being harassed doesn't stop a creep counting; it only adds the `harassed` tag.

**Instant display:** the last 3 verdict lines appear in a fixed screen corner, each fading out after about 6 s. Optional team chat (`Chat = 'off' | 'misses' | 'all'`), with `'misses'` covering `EARLY`, `LATE`, `MISS` and `MISSED_EASY`. At most 1 line every 2 s.

## Part 4: Checkpoints and summary
**When:** at 5:00, at 10:00, and when laning ends. Laning end is `J.IsInLaningPhase()` turning false. Task 12 will provide a better signal and can replace it later. `!trainer stats` shows the summary on demand.

**Where:** the summary goes to team chat from the trainer bot, and is also shown as screen text for about 15 s.

**Denominator** (my call). Every percentage and "success rate", including the harass-slump rule, is out of **takeable creeps**:
- the resolved attempts (excluding `CANCELLED`), plus
- the `MISSED_EASY` creeps where the player made no swing.

A creep that died near the player with a narrow or empty window, and that they never swung at, is not counted at all. That's how the anti-goal "never blame the player for creeps they couldn't take" carries through to the numbers. Denies use the same rule, with deny windows.

**Content, in 3–4 lines:**
1. **Score:** `LH 41/55 (75%) · denies 6/14 · easy misses 7`
2. **Timing:** `you start 0.08s early on average (median −0.06s)`. If ranged and melee averages differ by more than 0.05 s, add the split: `early on ranged (−0.14s), fine on melee (+0.01s)`. With outcome-only grading, this line is replaced by the counts of early and late attempts.
3. **Biggest leak:** one line, chosen below.
4. **Under harass**, only when it differs from free attempts by 15 points or more: `under harass 52% vs 81% free`.

**Biggest leak.** Each rule estimates how many creeps it cost, and the line with the highest cost is shown. Ties go to the rule higher in this list:

| Rule | Fires when | Cost | Line, for example |
|---|---|---|---|
| Easy misses, no swing | at least 3 `MISSED_EASY` with no attempt | that count | `7 easy creeps lost with no swing, mostly ranged. Watch the backline.` (the creep type is named if it's 60% or more of them) |
| Late bias | mean offset ≥ +0.06 s and `LATE` ≥ 20% of attempts | `LATE` + late `MISSED_EASY` | `you're late: start your swing about 0.1s sooner` |
| Early bias | mean offset ≤ −0.06 s and `EARLY` ≥ 20% of attempts | `EARLY` attempts that then lost the creep | `you're early: wait about 0.1s longer before swinging` |
| Harass slump | harassed success rate ≥ 20 points below free | (free rate − harassed rate) × harassed attempts | `you lose timing when hit: back off or swing earlier under pressure` |
| Denies | denies on, at least 5 deny windows, and under 30% taken | missed deny windows | `denies 2/11: check allied creeps under half HP` |

- Fewer than 10 resolved creeps gives `not enough data yet` instead of a leak line.
- The suggested adjustment ("about 0.1s") is the mean offset rounded to 0.05 s.

**Counters**, per player for the whole game: everything in the handoff's Part 4, plus `MISSED_EASY` counts split by whether a swing was made, and by creep type.

## Commands and config
Commands are as in the handoff, added to 06's `COMMANDS` table in `commands.ts`. That gives `!trainer on|off`, `bar on|off`, `chat off|misses|all`, `denies on|off`, `stats` and `reset`. A bot selector such as `!lion trainer` is not allowed, matching the existing rule for `bhelp` and `farm`.

`Customize.Humaniser.Trainer.LastHit`, with defaults:
- `Enable = true`. This makes the commands available. The trainer itself stays off until `!trainer on`.
- `Bar = true`
- `Denies = true`
- `Chat = 'off'`
- `EasyWindow = 0.3`
- `Checkpoints = { 300, 600 }`
- `SelfTest = false`

Add `"Trainer"` to `IsFeatureEnabled`'s union and `DEFAULTS` in `config.ts`.

## Self-test calibration
As in the handoff: when `SelfTest = true`, one allied bot times its last hits from the trainer's own start window, and the trainer grades that bot as its subject. The pass bar is `PERFECT` + `OK` on 85% or more of attempts in a 10-minute free lane, with predicted versus actual landing times logged.
- **How the timing is altered** (my call): through a hook in OHA's pure-Lua last-hit path. The builder finds where laning or attack code decides to swing at a creep for a last hit, and adds a `Trainer.SelfTestGate(bot, creep)` check there, registered like the `SetHelpers` blocks. For the self-test bot the gate holds the swing until the trainer's start window reaches now. For every other bot, and whenever `SelfTest = false`, it returns "no opinion". This is the one place the trainer changes bot behaviour, so the "trainer is an observer" anti-goal covers only the normal game. The self-test path doesn't issue orders from `Tick`.
- **Integration notes:**
  - The self-test bot should be in a lane without the human, because task 04's etiquette would otherwise make it skip creeps.
  - Set `Lane.Enable = false` (07) for the self-test lobby so pulls and blocks don't take it out of the lane.
  - If task 10 has landed, the self-test bot bypasses 10's skill error.
- The `MISSED_EASY` detector is also checked here: the self-test bot should score almost no easy misses.

## Integration with other work
- **Task 07 (`h-07-lane`, in progress).** It makes small additive edits to the same shared files:
  - `Customize/general.lua` (a `Lane = {...}` block)
  - `config.ts` (the `DEFAULTS` entry and `IsFeatureEnabled` union)
  - `index.ts` (export and `Tick`)
  - `commands.ts` (exports `memberByPID`)
  - `jmz_func.lua` (a `SetHelpers` block)
  - `HUMANISER_DEV.md`

  14 adds its own entries next to those, and touches nothing of 07's. Whichever merges into `humaniser` second rebases and resolves a few trivial conflicts. If 14 needs `memberByPID`, it copies the one-line export rather than depending on 07.
- **Task 04 (ally etiquette):** read-only. Allies deferring to humans is what makes "an ally took it" fair to count against the player.
- **Task 10 (bot last-hit accuracy):** not started. The self-test bypass is the only contact point.
- **Task 12 (laning end signal):** not started. Use `J.IsInLaningPhase()` until it lands.
- **Task 09 (intent arbitration):** none. The trainer issues no orders and posts no claims.

## Optional phase 2 (not in v1)
Only if spike item 8 shows the bridge is fast enough:
- an audio tick at the ideal start time for the current target, through FretBots' `EmitGlobalSound`
- optionally, a particle effect on the creep, as a more native-looking cue than debug lines

Neither is designed further here.

## Tests
Use the handoff's offline and in-game lists, plus:
- **Offline, `MISSED_EASY`:**
  - a wide window with no swing gives the verdict
  - a narrow window with no swing gives nothing
  - an unreachable wide window gives nothing
  - a wide window with a late swing gives one `MISSED_EASY` line, and the statistics still count it late
  - a creep that died during a hero fight is excluded
- **Offline, biggest leak:**
  - scripted counter sets pick the expected rule
  - ties go to the rule higher in the table
  - fewer than 10 creeps gives `not enough data yet`
- **In-game:**
  - deliberately ignore wide-window creeps: they're reported as `MISSED_EASY`, and the 5:00 checkpoint names the leak
  - with `Humaniser.Debug = false`, trainer draws still appear and HDebug's columns don't
  - with Debug on, the trainer's text doesn't overlap HDebug's columns

## Acceptance
The handoff's acceptance list, plus:
- `MISSED_EASY` verdicts and the biggest-leak line work, and appear in each checkpoint summary.
- The self-test bot has fewer than 5% `MISSED_EASY` among creeps it could reach.

## Left to the builder
- How the per-creep state machine is structured, and what the modules export inside `trainer/`.
- The exact corner position of the verdict text, and how it fades.
- Throttle rates, within the spike's measurements.
- Chat line wording, apart from the examples here.
