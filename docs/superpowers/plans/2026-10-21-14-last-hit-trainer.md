# 14: Last-hit trainer implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a bot-side practice mode that grades every last-hit and deny attempt the human makes. It flags easy creeps they lost, and prints checkpoint summaries ending in one actionable "biggest leak" line. A live timing bar is drawn if the spike allows it.

**Architecture:** pure TypeScript modules under `humaniser/trainer/`:
- prediction maths
- an attempt judge, a state machine fed one observation per frame
- statistics and summary text
- drawing
- a lifecycle module that reads the game, feeds the judge and owns commands and checkpoints

Only the lowest-PID bot on each team runs it. The pure modules take plain observation structs, so the offline tests script them without the Dota API.

**Tech stack:** TypeScript compiled to Lua 5.1 by TSTL (`npm run build`), hand-written Lua for `general.lua`, `jmz_func.lua` and `mode_laning_generic.lua`, and offline tests in fengari (`tests/humaniser/run.js`).

**Spec:** `docs/superpowers/specs/2026-10-21-14-last-hit-trainer-design.md`. It refines `../handoffs/14-last-hit-trainer.md`, so read both. This plan overrides the spec in four places. Each is marked **Plan correction** where it applies:
1. **Incoming damage.** OHA's incoming-damage helpers are ported, not called. They scan creeps around `GetBot()` (the trainer bot, possibly in another lane), add bot-level fudge factors, and see only attacks already under way. See Task 2.
2. **`SetHelpers`** exposes only `GetAttackProDelayTime` and `IsInLaningPhase`.
3. **`IsFeatureEnabled` is not extended.** The trainer's config is nested (`Trainer.LastHit.Enable`), so it gets its own check instead.
4. **Screen text uses ASCII `-`** instead of `–`/`−`, because `DebugDrawText` may not render non-ASCII text. Spike item 9 checks this.

## Global constraints
- All work is in the worktree `/Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h14`, branch `h-14-trainer`. Commit there only. Never touch `oha` or `oha-h07`.
- **TS first.** New code goes in `typescript/bots/FunLib/humaniser/trainer/*.ts`, with absolute `bots/...` imports. Hand-edit only these Lua files: `bots/Customize/general.lua`, `bots/FunLib/jmz_func.lua` and `bots/mode_laning_generic.lua`. Commit the regenerated `bots/FunLib/humaniser/**/*.lua` alongside the TS.
- **Build:** `PUPPETEER_SKIP_DOWNLOAD=1 npx --yes yarn@1 install --frozen-lockfile` once, then `npm run build`. **Offline checks:** `cd tests/humaniser && npm install && npm run check`. Run one test file with `node tests/humaniser/run.js tests/humaniser/<file>.lua`.
- **Kill switch:** with `Customize.Humaniser.Trainer.LastHit.Enable = false`, no trainer code runs past its first `if`. This is checked by no helper calls and no `[H:trainer]` logs. Everything is off in game until `!trainer on`. With `SelfTest = true` the trainer switches itself on at game start.
- **The trainer observes.** It never issues actions or orders, and never posts to the Orders bus. The one exception is the self-test hook in `mode_laning_generic.lua` (Task 8).
- **Performance:**
  - at most 4 creeps predicted per frame: 2 with bars, plus `MaxWatched = 2` watched creeps
  - watched creeps are re-predicted every `WatchInterval = 0.1` s
  - `GetUnitList` is called at most once per list type per 0.25 s, cached in `incoming.ts`
- **Shared files touched**, all of which task 07 also edits: `general.lua`, `config.ts`, `index.ts`, `commands.ts`, `jmz_func.lua`, `mode_laning_generic.lua` and `HUMANISER_DEV.md`. Additions only, next to the existing blocks. Never edit 07's lines or import from 07's modules.
  - In `mode_laning_generic.lua`, 07 changes the `Think()` definition condition to add `or bLaneLaning`, and this plan adds `or bTrainerSelfTest`. When merging, keep both.
  - New Dota API typings go in `trainer/api.ts`, not in `ts_libs/dota/*`, which 07 also edits.
- **Spec values:**
  - `EasyWindow = 0.3` s
  - easy-miss radius 800
  - bar hide distance 1,200
  - prediction horizon 2.0 s in 0.05 s steps
  - smoothing over 3 frames
  - uncertain when the window moved more than 0.15 s in the last 0.3 s
  - attempts resolve within 2.5 s
  - a `PERFECT` last-hit counter change is matched within 0.15 s of the creep dying
  - 3 verdict lines on screen, each kept 6 s
  - the summary stays on screen 15 s
  - chat at most 1 verdict line per 2 s
  - checkpoints at `{300, 600}` and at laning end
  - "not enough data yet" below 10 takeable creeps
  - self-test passes at 85% `PERFECT` + `OK`, and fewer than 5% `MISSED_EASY`

## Review focus
Inputs the spec implies but doesn't spell out, most likely to bite first. Each one has a pinned test in the task named.
1. **The creep leaves vision or the handle goes invalid without dying,** e.g. fog, or the player walks away. It must not be graded as a death. Task 4, `creep lost from sight is dropped, not graded`.
2. **The subject switches target mid-swing,** onto a second creep. The first attempt must resolve as `CANCELLED` and the second must start fresh. Task 3, `retarget mid-swing cancels and restarts`.
3. **The trainer is switched on mid-game.** Checkpoints already past must not fire on the first frame. Task 6, `checkpoints already past are skipped`.
4. **The human dies with an attempt open.** The attempt resolves from what actually happened, and no `MISSED_EASY` is charged while they're dead. Task 4, `dead subject is not charged easy misses`.
5. **A second human joins, or the team has no bot.** The trainer must not crash or duplicate output. Task 6, `second human is ignored with one warning`, and `no bot on team: nothing runs`.

---

### Task 1: Plumbing, kill switch, the `!trainer` command and the spike probe

**Files:**
- Create: `typescript/bots/FunLib/humaniser/trainer/api.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/settings.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/trainer.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/spike.ts`
- Modify:
  - `typescript/bots/FunLib/humaniser/config.ts` (`DEFAULTS`)
  - `typescript/bots/FunLib/humaniser/index.ts` (import, export, `Tick`)
  - `typescript/bots/FunLib/humaniser/commands.ts` (`COMMANDS`, and the `Parse` selector exclusion)
  - `bots/Customize/general.lua` (the `Customize.Humaniser` block)
  - `bots/FunLib/jmz_func.lua` (after `J.Humaniser.Pings.SetHelpers`)
- Test: `tests/humaniser/test_trainer_core.lua`

**Interfaces:**
- Produces, in `api.ts`:
  - `interface TUnit extends Unit`. Add each of these: `GetLastHits(): number`, `GetDenies(): number`, `GetAnimCycle(): number`, `GetAttackPoint(): number`, `GetSecondsPerAttack(): number`, `GetAttackSpeed(): number`, `GetAttackProjectileSpeed(): number`, `GetIncomingTrackingProjectiles(): {location: Vector, caster?: Unit, is_attack: boolean}[]`, `IsStunned(): boolean`, `IsHexed(): boolean`, `IsTower(): boolean`.
  - `function T(u: Unit): TUnit`, a cast.
  - `declare function DebugDrawLine(a: Vector, b: Vector, r: number, g: number, b2: number): void`, as a global declaration.
  - `type CreepKind = "melee" | "ranged" | "siege"` and `function CreepKind(u: Unit): CreepKind`, which matches `siege` or `ranged` in the unit name, otherwise `melee`.
  - `function HeroLabel(u: Unit): string`: the unit name without `npc_dota_hero_`, underscores turned into spaces, first letter capitalised.
- Produces, in `settings.ts`:
  - the `DEFAULTS` record:
    `{ Enable: true, Bar: true, BarStyle: "time", OutcomeOnly: false, ScreenText: true, Denies: true, Chat: "off", EasyWindow: 0.3, Checkpoints: [300, 600], SelfTest: false, TextX: 560, TextY: 40, WatchInterval: 0.1, MaxWatched: 2 }`
  - `type TrainerSettings`
  - `function Get(): TrainerSettings`, which merges over `Config.Get().Trainer.LastHit`. Copy `commands.ts`'s `merge`.
  - `function IsEnabled(): boolean`, true when `Config.IsEnabled()` and `Get().Enable === true`.
- Produces, in `trainer.ts`:
  - `SetHelpers(h: { GetAttackProDelayTime(subject: Unit, creep: Unit): number; IsInLaningPhase(): boolean })`
  - `Tick(bot: Unit): void`, which returns immediately unless `IsEnabled()`
  - `OnCommand(team: number, pid: number, args: string[]): void`
  - `TrainerBotPID(team: number): number | undefined`, the lowest-PID bot. Reimplement it here; don't import it from `commands.ts`.
  - `GetHelpers()`, exported for the later modules.
- Produces, in `spike.ts`: `SpikeTick(bot: Unit, subject: Unit): void`.

- [ ] **Step 1: Worktree setup.** In `oha-h14`, run the yarn install, then `npm run build`, then `cd tests/humaniser && npm install && npm run check`. Expected: the build leaves no git diff, and every existing test passes.

- [ ] **Step 2: Write the failing tests** in `test_trainer_core.lua`, using `FreshHumaniser`. Stub `ActionImmediate_Chat` on units to record lines, and make `print` record `[H:trainer]` lines.
  - `parse trainer with args`: `H.Commands.Parse("!trainer bar on", 2)` gives `name == "trainer"` and `args == {"bar","on"}`.
  - `trainer cannot take a bot selector`: `Parse("!lion trainer", 2)` and `Parse("!2 trainer on", 2)` both give `nil`.
  - `kill switch: no helper calls, no logs`:
    - Config: `Trainer = { LastHit = { Enable = false } }` with `Debug = true`.
    - Run `!trainer on` through `H.Commands.HandleMessage`, then 20 `H.Tick(bot)` frames.
    - The helper spies (`GetAttackProDelayTime`, `IsInLaningPhase`) record 0 calls, no `[H:trainer]` lines are printed, and no chat is sent.
  - `status reply comes from the trainer bot only`:
    - Two bots, PIDs 1 and 3, and a human, PID 0. `!trainer` with no args is sent.
    - After `Tick` on both bots, only the PID 1 bot has said `trainer off - bar on - chat off - denies on`.
  - `unknown subcommand prints usage`: `!trainer banana` makes the trainer bot say the usage line from Step 3.

- [ ] **Step 3: Implement** `api.ts`, `settings.ts` and `trainer.ts`, enough to pass.
  - `config.ts`: add `Trainer: { LastHit: { Enable: true } } as Record<string, any>,` after `Commands`. Do not change `IsFeatureEnabled`.
  - `commands.ts`:
    - Add `{ name: "trainer", aliases: [], handler: (ctx) => Trainer.OnCommand(ctx.team, ctx.issuerPID, ctx.args) }` before `bhelp`.
    - In `Parse`, extend the selector exclusion to `def.name === "bhelp" || def.name === "farm" || def.name === "trainer"`.
    - Note: `trainer.ts` must not import `commands.ts`, or the imports become circular.
  - `index.ts`: import `* as Trainer from "bots/FunLib/humaniser/trainer/trainer"`, add `Trainer` to the export list, and call `Trainer.Tick(bot)` after `Commands.Tick(bot)`.
  - `general.lua`: add this after `Commands = { Enable = true },`:
    ```lua
    -- Last-hit trainer (task 14): practice feedback for the human. Nothing runs in game until "!trainer on".
    Trainer = {
        LastHit = {
            Enable = true,
            Bar = true, BarStyle = 'time', -- 'time' | 'hp'; picked in the Phase 0 spike
            OutcomeOnly = false, -- true if the human's swing timing can't be read (spike fallback)
            ScreenText = true, -- false sends verdicts and summaries to team chat instead (spike fallback)
            Denies = true, Chat = 'off', -- 'off' | 'misses' | 'all'
            EasyWindow = 0.3, Checkpoints = { 300, 600 },
            -- Calibration: the lowest-PID bot on each team times its last hits from the trainer's window.
            SelfTest = false,
        },
    },
    ```
  - `jmz_func.lua`:
    ```lua
    J.Humaniser.Trainer.SetHelpers({ GetAttackProDelayTime = function(subject, creep) return J.GetAttackProDelayTime(subject, creep) end, IsInLaningPhase = function() return J.IsInLaningPhase() end })
    ```
  - `OnCommand` stores runtime state per team in `teams[team] = { on, bar, chat, denies, replies: string[] }`, starting from the settings values. Subcommands:
    - `on` / `off`. `on` resets the stats; that wiring comes in Task 6.
    - `bar on|off`, `chat off|misses|all`, `denies on|off`
    - `stats [selftest]` and `reset`, which are stubs until Task 6
    - `spike`, only when `Config.Get().Debug`
    - no args: the status line
    - anything else: `usage: !trainer on|off|stats|reset|bar on|off|chat off|misses|all|denies on|off`

    Replies queue on the team. `Tick` sends one line every 0.5 s through `bot.ActionImmediate_Chat(line, false)`, and only when `bot.GetPlayerID() === TrainerBotPID(team)`.

- [ ] **Step 4: Implement `spike.ts`.** This is throwaway probe code. Keep it in the repo, since it's only reachable through `!trainer spike` with Debug on.
  - Every 0.5 s it logs `[H:trainer] spike` with the subject's readings:
    - `GetAttackTarget()` name
    - `GetLastAttackTime()`, `GetAnimActivity()`, `GetAnimCycle()`
    - `GetAttackPoint()`, `GetAttackSpeed()`, `GetSecondsPerAttack()`, `GetAttackDamage()`
    - `GetLastHits()` and `GetDenies()`
    - `GetAttackProDelayTime(subject, target)`, when there's a target
    - the frame gap since the last call (think rate)
  - Every frame, over the nearest enemy lane creep within 900, it draws two mock bars:
    - a time bar whose green segment loops right to left every 2 s
    - an HP-style bar drawn 40 units above it
    - drawn with the colours and geometry from Task 7 Step 3
  - It also draws `DebugDrawText` lines `ASCII - test` and `unicode – − test`.

- [ ] **Step 5: Build and run.** Run `npm run build`, then `node tests/humaniser/run.js tests/humaniser/test_trainer_core.lua`, then `cd tests/humaniser && npm run check`. Expected: all pass.

- [ ] **Step 6: Commit.**
  ```bash
  git add -A typescript/bots/FunLib/humaniser bots/FunLib/humaniser bots/Customize/general.lua bots/FunLib/jmz_func.lua tests/humaniser/test_trainer_core.lua
  git commit -m "Trainer: config, kill switch, !trainer command, spike probe (task 14)"
  ```

- [ ] **Step 7: Spike handoff (human, in game).** Ask the user to run the spike: Local Host lobby, cheats on, `Humaniser.Debug = true`, `!trainer spike`. Record the answers in `docs/HUMANISER_DEV.md` under a new "Last-hit trainer (task 14)" section:
  1. Are the draws visible? Are they visible with `Debug = false`? Change `HDebug.IsEnabled()` locally to try.
  2. Are the bars smooth or flickering? What's the think rate?
  3. Which human-hero reads work?
  4. Is the `GetAttackProDelayTime` value sane on the human?
  5. Which bar style does the user prefer?
  6. *(spike item 8)* Optionally: does a bot `ActionImmediate_Chat` line reach a FretBots `player_chat` listener, and how long does it take? Probe by hand. No code is committed for this.
  7. *(Plan correction 4)* Does the Unicode text line render?

  **Decision to record:** set `BarStyle`, `OutcomeOnly` and `ScreenText` defaults. Then update `settings.ts` and `general.lua` in one small commit. Tasks 2–6 don't depend on the answers. Task 7 does.

---

### Task 2: Incoming damage and the window predictor

**Files:**
- Create: `typescript/bots/FunLib/humaniser/trainer/incoming.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/predict.ts`
- Test: `tests/humaniser/test_trainer_predict.lua`

**Interfaces:**
- Produces, in `incoming.ts`:
  - `interface Hit { at: number; damage: number }`, where `at` is seconds from now and `damage` is after armour
  - `function Hits(creep: Unit, subject: Unit, horizon: number): Hit[]`
  - `function NearbyUnits(loc: Vector, radius: number): Unit[]`: allied and enemy creeps, heroes and towers, from a per-team cached `GetUnitList` refreshed every 0.25 s
- Produces, in `predict.ts`:
  - `STEP = 0.05`, `HORIZON = 2.0`
  - `function BuildCurve(hp: number, regen: number, hits: Hit[]): number[]`: 41 samples, where `curve[i]` = HP at `i*STEP`
  - `interface Window { open: number; close: number }`, relative start times
  - `function KillWindow(curve: number[], effDmg: number, delay: number, startFloor?: number): Window | undefined`
  - `interface Prediction { creep: Unit; isDeny: boolean; startOpen: number; startClose: number; ideal: number; uncertain: boolean; delay: number; effDmg: number; hp: number; curve: number[]; at: number }`, with absolute `DotaTime` values
  - `class Smoother { Push(now: number, open: number, close: number): { open: number; close: number; uncertain: boolean } }`
  - `function EffectiveDamage(subject: Unit, creep: Unit, isDeny: boolean): number`
  - `function Predict(subject: Unit, creep: Unit, isDeny: boolean, now: number, smoother: Smoother): Prediction | undefined`

**Plan correction 1, `Hits()` rules.** These port OHA's formulas from `jmz_func.lua:2131-2220`, without the `botLV` factors and without `GetBot()`:
- **In-flight projectiles** from `creep.GetIncomingTrackingProjectiles()` where `is_attack` and `caster !== subject`. Each is one hit, landing after `dist(p.location, creep) / (casterProjSpeed * (tower ? 0.93 : 1))`.
- **Every unit in `NearbyUnits(creep loc, 1600)`** other than the subject whose `GetAttackTarget() === creep`.
  - **Melee in swing** (activity 1503 and cycle < point): it lands after `(point - cycle) * SecondsPerAttack`.
  - **Ranged:** the same, plus `(dist - 22) / projSpeed` travel.
  - **Siege:** `(0.292 - cycle) * 0.699 / 0.292` plus travel, OHA's constants.
  - **Not in swing:** the next swing starts at `lastAttackTime + SecondsPerAttack`, clamped to now or later, and lands after `point * SecondsPerAttack` plus travel.
  - **Creeps and towers repeat** every `SecondsPerAttack` up to the horizon. **Heroes** count for their current or next hit only.
  - **Damage** is `creep.GetActualIncomingDamage(attacker.GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)`.

**`KillWindow` maths:**
- `tOther` is the first `i*STEP` with `curve[i] <= 0`, or `HORIZON + STEP` if there is none.
- `tLandMin` is the first `i*STEP` with `curve[i] <= effDmg`.
- If `tLandMin` doesn't exist, or `tLandMin >= tOther`, return `undefined`.
- Otherwise `open = max(tLandMin - delay, startFloor ?? -inf)` and `close = tOther - delay`. Return `undefined` if `open >= close`.
- For a deny, `startFloor` is the first `t` where the curve is below half of max HP.

**Other formulas:**
- `ideal` is `open + 0.05` when `close - open < 0.1`, otherwise the midpoint.
- `EffectiveDamage`: `creep.GetActualIncomingDamage(dmg, PHYSICAL)`, where `dmg = GetAttackDamage()` plus the Quelling Blade bonus for last hits only. Copy the rule from `mode_laning_generic.lua:69-75`: +8 melee, +4 when range > 310 or Templar Assassin, only if `item_quelling_blade` is in a main slot.
- `Smoother` averages the last 3 pushes of absolute open and close. It flags `uncertain` when the raw open differs by more than 0.15 from the raw open at least 0.3 s older; it keeps 0.5 s of history.

- [ ] **Step 1: Write the failing tests.** Use pure curves for `KillWindow`, and stub units with `GetAttackTarget`, `GetAnimActivity`, `GetAnimCycle`, `GetAttackPoint`, `GetSecondsPerAttack`, `GetLastAttackTime`, `GetAttackDamage`, `GetActualIncomingDamage` and `GetIncomingTrackingProjectiles` for `Hits`.
  - `steady curve: window from subject's damage to the other kill`:
    - `hp=100`, hits of 20 at 0.3, 0.8 and 1.3 s, and 50 at 1.3 s. Curve: 80 → 60 → −10.
    - With `effDmg=60` and `delay=0.3`: `tLandMin=0.8` and `tOther=1.3`, so `open≈0.5` and `close≈1.0`.
  - `two attackers on one tick merge into one drop`: the same curve value as summing them by hand at that sample.
  - `tower shot closes the window early`: a projectile with damage 110 at 0.6 s on `hp=100`. `tOther=0.6`. With `effDmg=40` and no other hits, the result is `undefined`.
  - `empty window`: `effDmg` smaller than every pre-kill HP step gives `undefined`.
  - `deny floor`: on an allied creep, the start can't open before HP drops below half.
  - `Hits excludes the subject's own projectile and swing`: a subject with a projectile in flight and a swing in progress produces no hits from the subject.
  - `idle creep's next swing is projected and repeats`: `lastAttackTime=now-0.2`, `SecondsPerAttack=1`, point 0.5 gives hits at 1.3 s and nothing else before 2.0. A tower with period 0.83 repeats.
  - `smoother averages and flags jumps`: pushing open 1.0, 1.0, 1.0 at 1/30 s apart gives `uncertain=false`. A jump of 0.3 at t+0.33 gives `uncertain=true`.

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_predict.lua`. Expected: FAIL, because the modules are missing.

- [ ] **Step 3: Implement `incoming.ts` and `predict.ts`** to the signatures and rules above.

- [ ] **Step 4: Run.** Same command. Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: incoming-damage port and start-window predictor"`, with the TS, the generated Lua and the test.

---

### Task 3: Attempt judge (`PERFECT`, `OK`, `EARLY`, `LATE`, `CANCELLED`, `MISS`)

**Files:**
- Create: `typescript/bots/FunLib/humaniser/trainer/judge.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/format.ts`
- Test: `tests/humaniser/test_trainer_judge.lua`

**Interfaces:**
- Consumes `Prediction` (Task 2) and `CreepKind` (Task 1).
- Produces, in `judge.ts`:
  - `interface SubjectObs { now: number; alive: boolean; eligible: boolean; harassed: boolean; target?: string; anim: "swing" | "followthrough" | "none"; swingStart?: number; lastHits: number; denies: number }`
    - `eligible`: alive, not stunned, hexed or channelling, and not in a hero fight
    - `target`: the creep id of the current attack target
    - `anim`: `swing` is attack activity with cycle < point; `followthrough` is attack activity with cycle ≥ point; `none` is anything else
  - `interface Killer { kind: "subject" | "ally" | "enemyHero" | "tower" | "creep"; name?: string }`
  - `interface CreepObs { id: string; kind: CreepKind; isDeny: boolean; alive: boolean; hp: number; dist: number; prediction?: Prediction; killer?: Killer }`. `killer` is set on the frame the creep is seen to have died.
  - `type VerdictKind = "PERFECT" | "OK" | "EARLY" | "LATE" | "CANCELLED" | "MISS" | "MISSED_EASY"`
  - `interface Verdict { kind: VerdictKind; at: number; creepId: string; creepKind: CreepKind; isDeny: boolean; harassed: boolean; swung: boolean; offset?: number; window?: number; predictedLand?: number; landedAt?: number; reason: string }`
    - `offset`: swing start minus ideal start; negative means early
    - `window`: the widest reachable window, for `MISSED_EASY`
  - `type JudgeEvent = { type: "verdict"; v: Verdict } | { type: "outcome"; creepId: string; subjectGotIt: boolean }`
  - `class Judge { constructor(easyWindow: number); Step(s: SubjectObs, creeps: CreepObs[]): JudgeEvent[] }`
- Produces, in `format.ts`: `Sec(x: number): string` (2 dp, trailing zeros trimmed, so `0.10` becomes `0.1`) and `Signed(x: number): string` (always shows the sign: `+0.03`, `-0.11`).

**Attempt rules** (the spec's Part 3, made exact):
- **Start:** `anim` becomes `swing` with `target` equal to a creep in `creeps`. `swingStart` is given in `SubjectObs`. Task 6 computes it as `now - cycle / attackSpeed`. Record the prediction from that frame (`predictedLand = swingStart + prediction.delay`), and the creep's HP.
- **Retarget or cancel:** `anim` goes from `swing` to `none` without passing through `followthrough`, or `target` changes while `anim` is `swing`. Either gives `CANCELLED` (`cancelled swing`). A new swing starts a new attempt.
- **Resolution** happens on the first matching frame. After 2.5 s it is forced to `MISS`.
  - **Creep died, `killer.kind === "subject"`:**
    - Start inside `[startOpen, startClose)`: `PERFECT`, reason `perfect (<Signed(offset)>s)`.
    - Otherwise `OK`, reason `got it (window said <Sec(|d|)>s early|late)`, where `d` is the distance to the nearer window edge.
  - **Creep died, other killer, death before `predictedLand`:** `LATE`, reason `late by <Sec(predictedLand - death)>s - <taker>`.
    - `<taker>` is `lane creep took it`, `tower took it`, `denied by <name>` (an enemy hero on our creep's opposite side) or `<name> took it` (an ally).
  - **Alive, and HP dropped by at least `0.6 * effDmg` within 0.2 s of `predictedLand`:** `EARLY`, reason `early by <Sec>s - creep had <hp> HP, you deal <effDmg>`. The early amount is `startOpen - swingStart`, floored at 0.01.
  - **Alive, `predictedLand + 0.3` passed, no drop:** `MISS`, reason `missed - evasion/uphill?`.
- **Outcome events:** when a creep that had any attempt dies, emit `{ type: "outcome", creepId, subjectGotIt }` once.
- **Offsets** are set for `PERFECT`, `OK`, `EARLY` and `LATE`.

- [ ] **Step 1: Write the failing tests.** Each test scripts frames (`SubjectObs`, `CreepObs`) at 1/30 s and collects verdicts:
  - `perfect inside window`: reason `perfect (+0.03s)`.
  - `ok outside window`
  - `early: hp drops, creep lives`: reason contains `creep had 71 HP, you deal 58`.
  - `late to creep / tower / ally / enemy deny`: one test each, checking all four taker strings.
  - `cancelled swing is not a miss`
  - `retarget mid-swing cancels and restarts`: a swing on A, then a target switch to B before the attack point, gives `CANCELLED` for A and a fresh attempt on B.
  - `miss after landing passes`
  - `double tap logs EARLY then a new attempt`: the second swing kills, so `EARLY` is followed by `PERFECT`/`OK`, and there's exactly one outcome event with `subjectGotIt=true`.
  - `forced resolution at 2.5s`

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_judge.lua`. Expected: FAIL.

- [ ] **Step 3: Implement `judge.ts` and `format.ts`.**

- [ ] **Step 4: Run.** Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: attempt judge and verdict reasons"`.

---

### Task 4: Easy misses, creep selection and attribution

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/trainer/judge.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/watch.ts`
- Test: `tests/humaniser/test_trainer_watch.lua`

**Interfaces:**
- Consumes `Judge`, `CreepObs`, `Killer` (Task 3) and `Prediction` (Task 2).
- Produces, in `watch.ts`:
  - `function SelectCreeps(subject: Unit, candidates: { creep: Unit; isDeny: boolean; prediction?: Prediction }[], maxBars: number, maxWatched: number): { bars: Unit[]; watched: Unit[] }`
    - Bars: the subject's attack target first, then the creep with the earliest `startClose`.
    - Watched: the next `maxWatched` by `startClose`.
    - Candidates are within 800 of the subject, alive, and have a prediction.
  - `interface Counters { lastHits: Record<number, number>; denies: Record<number, number> }`, keyed by PID
  - `function Attribute(creep: CreepObs, subjectPid: number, before: Counters, after: Counters, heroes: { pid: number; ally: boolean; name: string }[], towerTargeting: boolean): Killer`. Rules, in order:
    1. The subject's counter rose: `subject`.
    2. An allied hero's last hits rose: `ally` with its name.
    3. An enemy hero's denies rose (our creep) or last hits rose (their creep): `enemyHero` with its name.
    4. A tower had this creep as its attack target in the last 0.5 s: `tower`.
    5. Otherwise: `creep`.
  - `function IsDeathLikely(lastHp: number, effDmg: number, dist: number): boolean`. When a handle goes invalid, it counts as a death only if `dist <= 1200` and `lastHp <= max(effDmg, 0.3 * maxHp)`. Otherwise the record is dropped with no verdict.
- **Changes `Judge`:**
  - It keeps a per-creep record `widest`: the largest `min(startClose, now+2) - max(startOpen, now)` over predictions in the creep's last 2 s, counting only those with `startClose > now`. A creep with `swung = false` lives in this record and has no attempt.
  - On death with `killer.kind !== "subject"`, it emits `MISSED_EASY` when all of these hold:
    - `widest >= easyWindow`
    - the subject was `eligible` on the death frame
    - the creep was within 800 of the subject
    - the creep had no attempt, or its only resolved attempt was `LATE`
  - A `LATE` attempt is replaced by `MISSED_EASY` (`swung = true`, `offset` kept). Only one verdict line is shown for the creep.
  - **Reasons:**
    - no swing: `missed easy one - <Sec(window)>s window, <kind> creep, no swing`
    - late: `missed easy one - <Sec(window)>s window, you were <Sec(late)>s late`
    - deny: the same, with `easy deny` in place of `easy one`
    - ally taker: append ` - <name> took it after you passed`

- [ ] **Step 1: Write the failing tests.**
  - `wide window, no swing: MISSED_EASY`: a 0.42 s widest window and a creep killer. Reason: `missed easy one - 0.42s window, ranged creep, no swing`.
  - `narrow window, no swing: nothing`: a 0.2 s window gives no events.
  - `unreachable wide window: nothing`: `startClose` always at or before now, from walking distance.
  - `late on a wide window: one MISSED_EASY, offset kept`: exactly one verdict, `swung=true` and `offset > 0`.
  - `ally took it after you passed`: the reason ends with ` - Lion took it after you passed`.
  - `hero fight excludes the creep`: `eligible=false` on the death frame gives nothing.
  - `dead subject is not charged easy misses`
  - `creep lost from sight is dropped, not graded`: an invalid handle with `lastHp` at 80% gives no events, and later frames don't grade it either.
  - `attribution order`: one case per rule, checked against `Attribute` directly.
  - `selection puts the attack target first and caps counts`

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_watch.lua tests/humaniser/test_trainer_judge.lua`. Expected: the new tests fail and the Task 3 tests still pass.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run.** Expected: everything passes.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: easy-miss detection, creep selection, kill attribution"`.

---

### Task 5: Statistics, summary and biggest leak

**Files:**
- Create: `typescript/bots/FunLib/humaniser/trainer/stats.ts`
- Test: `tests/humaniser/test_trainer_stats.lua`

**Interfaces:**
- Consumes `JudgeEvent` and `Verdict` (Tasks 3–4), plus `Sec` and `Signed` from `format.ts`.
- Produces: `class Stats { Add(e: JudgeEvent): void; Reset(): void; Lines(o: { outcomeOnly: boolean; denies: boolean }): string[]; Leak(denies: boolean): string; SelfTestLine(): string }`

**Definitions**, from the spec's Part 4 and the denominator rule:
- **Takeable:** every verdict except `CANCELLED`. The no-swing case is only counted when it's a `MISSED_EASY`, because no other verdict exists for a creep that wasn't swung at.
- **Success:** `PERFECT` or `OK`.
- Last hits and denies are counted separately by `isDeny`.

**Lines**, 3 or 4 of them:
1. `LH <s>/<t> (<pct>%) - denies <s>/<t> - easy misses <n>`. The denies segment is left out when denies are off.
2. The timing line, using the mean and median of offsets:
   - `you start <Sec(|mean|)>s early|late on average (median <Signed(median)>s)`
   - when `|mean| < 0.03`: `you start on time on average (median <Signed(median)>s)`
   - when ranged and melee each have at least 3 offsets and their means differ by more than 0.05, append `; <early|late|fine> on ranged (<Signed>s), <...> on melee (<Signed>s)`. "Fine" means `|avg| < 0.03`.
   - with `outcomeOnly`: `early <n> - late <n> (no timing detail)`
3. `Leak()`.
4. `under harass <a>% vs <b>% free`, only when both groups have at least 5 takeable creeps and differ by at least 15 points.

**`Leak()`:**
- With fewer than 10 takeable creeps it returns `not enough data yet`.
- Otherwise it computes each rule's cost and returns the line with the highest cost. Ties go to the earlier row. With no rule firing it returns `no clear leak - keep going`.

| Rule | Fires | Cost | Line |
|---|---|---|---|
| no-swing misses | `MISSED_EASY` with `swung=false` ≥ 3 | that count | `<n> easy creeps lost with no swing` + kind suffix |
| late bias | mean ≥ +0.06 and `LATE`+late-`MISSED_EASY` ≥ 20% of attempts | `LATE` + late `MISSED_EASY` | `you're late: start your swing about <adj>s sooner` |
| early bias | mean ≤ −0.06 and `EARLY` ≥ 20% of attempts | `EARLY` verdicts whose creep's outcome was `subjectGotIt=false` | `you're early: wait about <adj>s longer before swinging` |
| harass slump | harassed success rate ≥ 20 points below free | `round((free% − harassed%)/100 × harassed takeable)` | `you lose timing when hit: back off or swing earlier under pressure` |
| denies | denies on, at least 5 deny takeable, under 30% success | deny takeable − deny successes | `denies <s>/<t>: check allied creeps under half HP` |

- **Kind suffix**, used when one kind is at least 60% of the no-swing misses:
  - ranged: `, mostly ranged. Watch the backline.`
  - melee: `, mostly melee. Watch the front line.`
  - siege: `, mostly siege. Watch the catapult.`
  - otherwise: `. Watch every creep near you, not just your target.`
- `adj` is `|mean|` rounded to the nearest 0.05, with a minimum of 0.05.
- `SelfTestLine()` returns `selftest: <s>/<t> PERFECT+OK (<pct>%) - easy misses <n> of <t> reachable`.

- [ ] **Step 1: Write the failing tests.** Build scripted event lists and assert the exact strings:
  - `score line counts takeable only`: three `CANCELLED` verdicts leave the denominator unchanged.
  - `timing line early with ranged split`
  - `outcome-only timing line`
  - `leak: no-swing misses mostly ranged`
  - `leak: late bias wins on cost over denies`
  - `leak tie goes to earlier rule`
  - `early-bias cost counts only creeps then lost`: an `EARLY` whose outcome was `subjectGotIt=true` doesn't count.
  - `under 10 takeable: not enough data yet`
  - `harass line only past 15 points`
  - `reset clears everything`: after `Reset`, `Lines` reports `LH 0/0 (0%)` and the leak line is `not enough data yet`.

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_stats.lua`. Expected: FAIL.

- [ ] **Step 3: Implement `stats.ts`.** Show the percentage as `0` when the denominator is 0.

- [ ] **Step 4: Run.** Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: stats, summary lines, biggest-leak rules"`.

---

### Task 6: Lifecycle — reading the game, verdict text, chat and checkpoints

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/trainer/trainer.ts`
- Create: `typescript/bots/FunLib/humaniser/trainer/draw.ts` (screen text only; Task 7 adds the bars)
- Test: `tests/humaniser/test_trainer_tick.lua`

**Interfaces:**
- Consumes everything from Tasks 1–5.
- Produces, in `draw.ts`:
  - `function VerdictLines(lines: { text: string; kind: VerdictKind; at: number }[], now: number): void`. It draws the last 3 lines younger than 6 s, at `(TextX, TextY + 14*i)`.
  - Colours by kind:
    - `PERFECT` (0,255,0)
    - `OK` (255,255,255)
    - `CANCELLED` (160,160,160)
    - every other kind (255,140,0)
  - `function SummaryText(lines: string[], shownAt: number, now: number): void`. It draws below the verdicts, at `TextY + 50`, for 15 s.
- Produces, in `trainer.ts`:
  - `GetSubjects(team): Unit[]`
  - `Predictions(team): Prediction[]`, the bar predictions for the current frame, used by Task 7
  - the internal state per team: `{ on, bar, chat, denies, subjects: Record<pid, { judge: Judge; stats: Stats; smoothers: Record<string, Smoother>; lastHeroAttackAt: number; verdictLines; summary?: { lines; at } }>, checkpointsDone: Record<number, boolean>, wasLaning: boolean }`

**Tick order**, on the trainer bot only:
1. Run when `IsEnabled()`, and either `team.on` or `SelfTest` is true. With `SelfTest`, the first Tick after `GameState.GameInProgress` sets `team.on = true`.
2. **Subjects:**
   - The first human on the team, by lowest PID.
   - If there's more than one human, log `[H:trainer] [WARN] trainer coaches one player; ignoring pid <n>` once per PID.
   - Add the trainer bot itself when `SelfTest` is on.
   - With no bot on the team, nothing runs, because there's no trainer bot.
3. **Candidates for each subject:**
   - Enemy lane creeps, plus allied lane creeps under 60% of max HP when denies are on.
   - Within 800, from `incoming.NearbyUnits`.
   - Predicted with `Predict`. Watched creeps are re-predicted every `WatchInterval`.
   - Selected with `SelectCreeps(…, 2, MaxWatched)`.
4. **Build `SubjectObs`:**
   - `swingStart = now - cycle / GetAttackSpeed()`
   - `harassed = WasRecentlyDamagedByAnyHero(2)`
   - in a hero fight: the attack target was a hero within the last 2 s
   - `eligible`: alive, not stunned, hexed or channelling, and not in a hero fight
5. **Build `CreepObs`** for every creep that's selected or already has a judge record. Snapshot the last-hit and deny counters of every hero on both teams each frame, and use `Attribute` and `IsDeathLikely` when a creep dies or goes invalid.
6. **Judge events → stats.**
   - Each verdict line goes to the subject's verdict list, but not for the self-test bot. That one gets an `HDebug.Log` instead: `selftest predicted=<p> actual=<a> verdict=<k>`.
   - Chat: with `'all'`, every verdict; with `'misses'`, only `EARLY`, `LATE`, `MISS` and `MISSED_EASY`. At most 1 line per 2 s, and extra lines are dropped, not queued.
   - When `ScreenText = false`, every verdict line goes to chat, with the same 2 s limit.
7. **Checkpoints:**
   - On `team.on`, mark every checkpoint `<= DotaTime()` as done, so ones already past are skipped.
   - When `DotaTime()` passes an unfired checkpoint, or `IsInLaningPhase()` goes from true to false, post the summary: `Stats.Lines` for the human, as screen text for 15 s and queued to chat.
8. **Draw** the verdict lines and the summary when `ScreenText` is true.

**Commands, wired up:**
- `on`: creates fresh stats and judges.
- `off`: clears the verdict list and the summary. Nothing draws after that, because the draws last only one frame.
- `stats`: queues the human's `Lines()`.
- `stats selftest`: queues `SelfTestLine()`.
- `reset`: clears the stats and the judges.

- [ ] **Step 1: Write the failing tests** with `FreshHumaniser`. They need a stub world with creeps that have the Task 2 stub methods, heroes with `GetLastHits`/`GetDenies`, and `GetUnitList` returning them.
  - `off: no predictions run`: with `Enable = true` and the trainer not switched on, 30 Ticks call `GetAttackProDelayTime` 0 times.
  - `on: verdict line drawn after a scripted last hit`:
    - The human swings at a creep whose window is open, then the creep dies and the human's `GetLastHits` goes up.
    - `DebugDrawText` gets a line starting `perfect`.
  - `chat misses mode sends late, not perfect`
  - `chat rate limit drops extras within 2s`
  - `checkpoints already past are skipped`: `!trainer on` at `DotaTime=400` posts no 300 s summary. The 600 s one does post.
  - `laning end posts a summary`: the `IsInLaningPhase` helper flips from true to false.
  - `second human is ignored with one warning`: exactly one `[WARN] trainer coaches one player` line over 30 Ticks, and the second human's creeps are never predicted.
  - `no bot on team: nothing runs`: a team of only humans ticks without error, and nothing is predicted.
  - `off clears screen text`
  - `stats command replies with summary lines`

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_tick.lua`. Expected: FAIL.

- [ ] **Step 3: Implement.**

- [ ] **Step 4: Run** the whole suite: `cd tests/humaniser && npm run check`. Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: lifecycle, verdict text, chat, checkpoints"`.

---

### Task 7: The bar (waits for the Task 1 spike decision)

Skip this task and record why in `HUMANISER_DEV.md` if the spike found draws unusable. In that case `ScreenText = false` already covers the fallback.

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/trainer/draw.ts`
- Modify: `typescript/bots/FunLib/humaniser/trainer/trainer.ts` (calls `Bars`)
- Test: `tests/humaniser/test_trainer_tick.lua` (adds cases)

**Interfaces:**
- Consumes `Predictions(team)` (Task 6) and `Prediction` (Task 2).
- Produces: `function Bars(subject: Unit, preds: Prediction[], style: "time" | "hp", now: number, swingStart?: number): void`

**Geometry and colour**, the decision the plan pins:
- The bar is centred over the creep at `z + 180`, and 160 units wide along world X. Ticks are 16 units tall along Z.
- **Time style:**
  - track `now..now+2` in grey (128,128,128)
  - start window green (0,255,0), or cyan (0,255,255) for a deny, or amber (255,191,0) when uncertain
  - a white "now" tick at the left end
  - once the subject is swinging at this creep, a blue (80,160,255) tick at `swingStart`
- **HP style:**
  - axis `0..maxHP`, with the current HP filled in grey
  - a white line at `effDmg`
  - a ghost marker in the window colour at `curve[round(delay/STEP)]`, the HP when a hit started now would land
- **Hidden when** the subject is dead, the creep is more than 1,200 units away, or `team.bar` is false.

- [ ] **Step 1: Write the failing tests.**
  - `bar draws lines for a visible creep`: `DebugDrawLine` is called at least 4 times.
  - `bar hidden when dead, far or bar off`: 0 calls in each case.
  - `deny bar uses cyan, uncertain uses amber`: check the recorded colour arguments.

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_tick.lua`. Expected: the new cases fail.

- [ ] **Step 3: Implement `Bars`,** and call it from the Tick after step 8.

- [ ] **Step 4: Run** the whole suite. Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: live timing bar"`.

---

### Task 8: Self-test calibration hook

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/trainer/trainer.ts`
- Modify: `bots/mode_laning_generic.lua`
- Test: `tests/humaniser/test_trainer_selftest.lua`

**Interfaces:**
- Consumes `Predict` and `Smoother` (Task 2), and `TrainerBotPID` (Task 1).
- Produces:
  - `IsSelfTestBot(bot: Unit): boolean`: `IsEnabled() && Get().SelfTest && bot.GetPlayerID() === TrainerBotPID(bot.GetTeam())`. It's decided at laning-file load, so it uses only `GetTeamPlayers` and `IsPlayerBot`.
  - `SelfTestTarget(bot: Unit): Unit | undefined`: the creep among the bot's own predictions (bars plus watched) whose smoothed `startOpen <= now < startClose`, preferring the earliest `startClose`. It returns `undefined` when there isn't one.

**The `mode_laning_generic.lua` edit**, a minimal diff:
- Below `local fLastHitFilter = …`, add:
  ```lua
  -- Task 14 self-test: this bot times its last hits from the trainer's own start window.
  local Trainer = J.Humaniser.Trainer
  local bTrainerSelfTest = Trainer.IsSelfTestBot(bot)
  ```
- At the top of `LastHitThink`:
  ```lua
  if bTrainerSelfTest then
      local creep = Trainer.SelfTestTarget(bot)
      if not J.IsValid(creep) then return false end
      bot:SetTarget(creep)
      bot:Action_AttackUnit(creep, true)
      return true
  end
  ```
- At the top of `DenyThink`: `if bTrainerSelfTest then return false end`. Denies already come through `SelfTestTarget`, because its candidates include deny creeps.
- Extend the `Think()` definition condition with `or bTrainerSelfTest`. When merging with 07, which adds `or bLaneLaning` to the same line, keep both.

- [ ] **Step 1: Write the failing tests.**
  - `only the trainer bot with SelfTest is the self-test bot`: PID 1 of bots {1, 3} returns true; PID 3 returns false; with `SelfTest=false`, both return false.
  - `target only when window reaches now`:
    - The creep's prediction has `startOpen = now+0.3`: `nil`.
    - Advance 0.3 s: the creep.
    - Past `startClose`: `nil`.
  - `self-test bot verdicts stay off the human's screen`: in a self-test run with a human present, the trainer-bot attempts produce `[H:trainer] selftest predicted=` logs, and no extra `DebugDrawText` lines.
  - `laning file parses with the hook`: `npm run check`'s syntax pass covers this, with no extra test code.

- [ ] **Step 2: Run.** `npm run build && node tests/humaniser/run.js tests/humaniser/test_trainer_selftest.lua`. Expected: FAIL.

- [ ] **Step 3: Implement both parts.**

- [ ] **Step 4: Run** `cd tests/humaniser && npm run check`. Expected: PASS.

- [ ] **Step 5: Commit.** `git commit -m "Trainer: self-test calibration hook in laning Think"`.

---

### Task 9: Docs and the in-game checklist

**Files:**
- Modify: `docs/HUMANISER_DEV.md` (the "Last-hit trainer (task 14)" section from Task 1 Step 7)
- Modify: `docs/HUMANISER_TEST_PLAN.md` (append a 14 block)

- [ ] **Step 1: Write the HUMANISER_DEV section.** It covers:
  - the commands and config keys
  - the spike results and decisions
  - plan corrections 1–4 and why
  - the 07 merge note about the `Think()` condition line
  - a self-test lobby recipe: the human in a different lane from the trainer bot, `Lane.Enable = false`, `SelfTest = true`, 10 minutes
  - the regression check: `Enable = false` means no `[H:trainer]` lines

- [ ] **Step 2: Write the test plan checklist.** Copy the handoff's in-game list 1–8, then add:
  - deliberately ignored wide-window creeps show `MISSED_EASY`, and the 5:00 checkpoint names the leak
  - with `Debug = false`, trainer draws appear and HDebug's columns don't
  - with `Debug = true`, the trainer text doesn't overlap HDebug's columns
  - self-test: at least 85% `PERFECT` + `OK`, and under 5% `MISSED_EASY` (`!trainer stats selftest`)
  - frame cost with 2 bars and 2 watched creeps, which is spike item 7. If it's noticeable, lower `MaxWatched` or raise `WatchInterval`, and record the values.

- [ ] **Step 3: Commit.** `git commit -m "Docs: last-hit trainer dev notes and in-game checklist (task 14)"`.
