# Pull Forecast and Pre-emptive Contest Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bots forecast where the lane meets after the current creep clash and, scaled by skill, pull on that forecast. Skilled supports also use the mirrored forecast to reach the enemy pull camp before the enemy support does.

**Architecture:**
- Pure forecast functions and new snapshot fields in `lane_state.ts`.
- A skill-blended score fed to the planner's default pull branch.
- A new counter-play signal (`pull_expected`) that starts the existing `contest` camp job early, in a new `lookout` phase.
- Telemetry (`lane_eq`, extra `lane_plan` fields, contest end lines) plus an analyser fit in `tools/hlog`.

**Tech Stack:** TypeScript compiled to Lua 5.1 by TypeScriptToLua. Offline tests are Lua files run in fengari (`tests/humaniser/run.js`). The analyser tests use `node --test`.

**Spec:** `docs/superpowers/specs/2026-10-23-pull-forecast-and-precontest-design.md`

## Global Constraints

- Edit TypeScript under `typescript/bots/FunLib/humaniser/`, then regenerate the Lua with `npm run build:lua` from `oha/`. Commit both the TS and the generated `bots/FunLib/humaniser/*.lua`. Never hand-edit generated Lua.
- Every tunable goes in `lane_config.ts` `DEFAULTS`.
- Fairness: the forecast reads only visible creeps (`LaneState` `partition` already drops enemy creeps that fail `CanBeSeen()`). The prediction reads only `LaneState.Enemies`, the snapshot and public camp data.
- With `Lane.Forecast = false`, or at skill 0, planner choices must equal today's. With `Lane.PreContest = false`, no `pull_expected` signal and no pre-contest job.
- Tests are Lua files in `tests/humaniser/`, using `check(name, cond, detail)` and the `lane_world.lua` fixtures (`LaneFresh`, `MakeCreep`, `MakeUnit`, `T`, `LAST_SEEN`, `ActionsOf`).
- Run a test file: `cd tests/humaniser && node run.js test_<name>.lua`. Run everything: `cd tests/humaniser && npm run check`.
- Default values, verbatim from the spec:

  | Key | Value |
  |---|---|
  | `Forecast.K` | 0.4 |
  | `Forecast.TypeWeight` | `{ melee: 1.0, ranged: 1.6, siege: 1.0 }` |
  | `Forecast.PowerFloor` | 550 |
  | `Curves.Foresight` | `[0, 1]` |
  | `Gates.PreContest` | 0.7 |
  | `Timing.PreContestLead` | 2 |
  | `Timing.PreContestWait` | 4 |
  | `Timing.EqSampleAt` | 10 |
  | `Radii.PreContestStand` | 400 |

## Review Focus

1. **Fogged enemy creeps.** A clash where some enemy creeps are out of vision must not count them. Test in Task 1.
2. **Enemy support never seen.** No position is known, so there's no prediction and no pre-contest. Test in Task 3.
3. **Our own technique already committed this cycle.** No pre-contest may start. Test in Task 4.
4. **`PreContest` off while `CounterPlay` is on.** Normal contests still work and nothing pre-emptive happens. Test in Task 3.
5. **Support too far to arrive in time** (travel over `MaxTravel`, or arrival after `aggroAt − PreContestLead`). No job starts rather than one that arrives late. Test in Task 4.

---

### Task 1: Forecast functions and snapshot fields

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/lane_config.ts`
  - `LaneFlag`: add `"Forecast" | "PreContest"`.
  - `CurveName`: add `"Foresight"`.
  - `DEFAULTS`: add the keys in Global Constraints, and `Forecast: true`, `PreContest: true` beside the other flags.
  - `CONSUMER_FLAGS`: leave unchanged. Neither new flag keeps the lane system active on its own.
- Modify: `typescript/bots/FunLib/humaniser/lane_state.ts`
  - new exported functions;
  - `LaneSnapshot` fields;
  - fill them in `refresh` from `scan.ally[lane]` / `scan.enemy[lane]`, filtered the same way `summarise` filters (use `ally.units` / `enemy.units`).
- Test: `tests/humaniser/test_lane_state.lua`

**Interfaces:**
- Produces:
  - `LaneState.CreepWeight(name: string): number`. `ranged` in the name gives `TypeWeight.ranged`, `siege` gives `TypeWeight.siege`, anything else gives `TypeWeight.melee`.
  - `LaneState.LanePower(units: Unit[]): number`, the sum over alive units of `GetHealth() × CreepWeight(GetUnitName())`.
  - `LaneState.Imbalance(allyPower: number, enemyPower: number): number`, equal to `(A − E) / (A + E + Forecast.PowerFloor)`.
  - `LaneState.ForecastEq(eqPos: number, imbalance: number): number`, equal to `clamp(eqPos + Forecast.K × imbalance, −1, 1)`.
  - New `LaneSnapshot` fields: `allyPower: number`, `enemyPower: number`, `imbalance: number`, `forecastEq: number`.

- [ ] **Step 1: Write the failing tests** (append to `test_lane_state.lua`; get the module the way the file already does)

```lua
-- Same total HP (600): two ranged creeps beat three melee.
local ranged = { MakeCreep({ team = 2, x = 0, y = 0, hp = 300, name = "npc_dota_creep_goodguys_ranged" }),
	MakeCreep({ team = 2, x = 0, y = 0, hp = 300, name = "npc_dota_creep_goodguys_ranged" }) }
local melee = { MakeCreep({ team = 3, x = 0, y = 0, hp = 200 }), MakeCreep({ team = 3, x = 0, y = 0, hp = 200 }),
	MakeCreep({ team = 3, x = 0, y = 0, hp = 200 }) }
check("ranged outweigh melee of equal HP", S.Imbalance(S.LanePower(ranged), S.LanePower(melee)) > 0)
check("a 100-HP straggler is a small imbalance", S.Imbalance(100, 0) < 0.2, S.Imbalance(100, 0))
check("upgraded waves in proportion read alike", math.abs(S.Imbalance(2000, 1000) - S.Imbalance(4000, 2000)) < 0.05)
check("forecast clamps at the enemy tower", S.ForecastEq(0.9, 1) == 1)
check("forecast moves toward the winner", near(S.ForecastEq(-0.3, 0.5), -0.1))
```

Also add a snapshot test using the file's existing lane setup: with no creeps near the front, `s.imbalance == 0` and `s.forecastEq == s.eqPos`.

Then a fog test (Review Focus 1): the same world with one enemy creep whose `CanBeSeen` returns false, `local c = MakeCreep({...}); c.CanBeSeen = function() return false end`. It must not contribute to `s.enemyPower`. Assert `s.enemyPower` equals the visible creeps' power only.

- [ ] **Step 2: Build and run to verify they fail**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_state.lua`
Expected: errors on `S.Imbalance` / `S.LanePower` being nil.

- [ ] **Step 3: Implement the config keys and the four functions plus snapshot fields.** Signatures and values are as in Interfaces.

- [ ] **Step 4: Build and run**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_state.lua test_lane_config.lua test_lane_state_frames.lua`
Expected: no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add typescript/bots/FunLib/humaniser/lane_config.ts typescript/bots/FunLib/humaniser/lane_state.ts bots/FunLib/humaniser tests/humaniser/test_lane_state.lua
git commit -m "Lane forecast: creep power, clash imbalance and forecast eq on the lane snapshot"
```

---

### Task 2: Skill-blended score in the planner

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/lane_state.ts`
  - `ObserverView` gains `foresight: number` and `forecastScore: number`;
  - `ScoreFor` computes them;
  - add the pure functions below.
- Modify: `typescript/bots/FunLib/humaniser/lane_planner.ts`
  - `PlannerInput` gains `forecastScore?: number` (optional, so the existing test inputs still work);
  - `buildInput` sets it from `ScoreFor`;
  - in `Choose`, the default branch reads `const score = i.forecastScore ?? i.laneScore`. That branch is the `(!i.isMid || i.pullCamp)` block and the final `AggroCorrectBelow` check.
  - The freeze branch, cover-core branch and mid tower check keep `i.laneScore`.
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts`. In the `notePlan` call with `["gate", "planner"]` (around line 972), after `["score", ...]`, add `["fscore", input?.forecastScore]`, `["w", view.foresight]`, `["imb", s.imbalance]`, `["feq", s.forecastEq]`, `["apow", s.allyPower]` and `["epow", s.enemyPower]`, where `view = LaneState.ScoreFor(bot, s)`.
- Modify: `docs/HUMANISER_DEV.md`
  - in the `lane_plan` row of the telemetry table, list the new planner fields;
  - add a "Pull forecast" subsection under "Lane management: camp jobs and pulls" covering the imbalance, the forecast, the `Foresight` blend, where it applies and the kill switch;
  - add the `Forecast` flag to the flags table.
- Test: `tests/humaniser/test_lane_planner.lua`, `tests/humaniser/test_lane_state.lua`

**Interfaces:**
- Consumes: from Task 1, `LaneSnapshot.forecastEq` and `LaneState.LaneScore`.
- Produces:
  - `LaneState.ForesightOf(skill: number): number`. Returns 0 when `LaneConfig.IsOn("Forecast")` is false, else `LaneConfig.Curve("Foresight", skill)`.
  - `LaneState.ForecastScore(desired: number, eqPos: number, forecastEq: number, foresight: number, exposure: number): number`, equal to `LaneScore(desired, eqPos + foresight × (forecastEq − eqPos), exposure)`.

- [ ] **Step 1: Write the failing tests**

In `test_lane_state.lua`: K is 0.4, and safe lane `desiredEq` is −0.7.

```lua
local function fscore(eq, imb, skill) return S.ForecastScore(-0.7, eq, S.ForecastEq(eq, imb), S.ForesightOf(skill), 0) end
check("skill 0 reads the lane as today", near(fscore(-0.3, 0.6, 0), S.LaneScore(-0.7, -0.3, 0)))
check("skill 0.9, winning clash: full-pull score", fscore(-0.3, 0.6, 0.9) <= -0.5, fscore(-0.3, 0.6, 0.9))
check("skill 0.3, same lane: still half-pull score", fscore(-0.3, 0.6, 0.3) > -0.5, fscore(-0.3, 0.6, 0.3))
check("skill 0.9, losing clash: no longer a full-pull score", fscore(-0.1, -0.6, 0.9) > -0.5, fscore(-0.1, -0.6, 0.9))
```

Then a `Forecast = false` world (`LaneFresh({ Enable = true, Forecast = false }, ...)`): `S.ForesightOf(1) == 0`.

In `test_lane_planner.lua`, using its existing `choose`:

```lua
check("forecast score drives the full pull", choose({ laneScore = -0.4, forecastScore = -0.62 }).tech == "full_pull")
check("forecast score can hold back a full pull", choose({ laneScore = -0.6, forecastScore = -0.38 }).tech == "half_pull")
c = choose({ plan = view({ plan = "FREEZE" }), laneScore = -1.0, forecastScore = -0.1 })
check("freeze branch ignores the forecast", c.tech == "freeze", desc(c))
```

- [ ] **Step 2: Build and run to verify they fail**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_state.lua test_lane_planner.lua`
Expected: `S.ForecastScore` is nil, and the "forecast score drives the full pull" check FAILs.

- [ ] **Step 3: Implement the two functions, the `ObserverView` fields, the planner input and the `Choose` change, then the telemetry fields and docs.**

- [ ] **Step 4: Build and run**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_state.lua test_lane_planner.lua test_lane_camp_jobs.lua test_telemetry.lua`
Expected: no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add typescript/bots/FunLib/humaniser bots/FunLib/humaniser tests/humaniser/test_lane_state.lua tests/humaniser/test_lane_planner.lua docs/HUMANISER_DEV.md
git commit -m "Lane forecast: skill-blended score in the planner's pull branch, planner telemetry"
```

---

### Task 3: Predicting the enemy pull

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/counterplay.ts`
  - `SignalKind` gains `"pull_expected"`; `Signal` gains `aggroAt?: number`;
  - add the pure function below;
  - in `pullSignals`, after the existing `pull` detection, observe a `pull_expected` signal (rules below);
  - `onNotice` does nothing for `pull_expected` (no chat line), only the existing `HDebug.Log` line.
- Modify: `docs/HUMANISER_DEV.md`: describe the prediction in the counter-play section, and add the `PreContest` flag to the flags table.
- Test: `tests/humaniser/test_lane_counter.lua`

**Interfaces:**
- Consumes: from Task 1, `LaneSnapshot.forecastEq`; also `LaneState.DesiredEq`, `LaneState.LaneKindOf`, `LaneState.LaneScore`, `CampJobs.NextAggroTime`, `CampJobs.CampsUp` and `PullTiming.ForCamp`.
- Produces:
  - `Counter.EnemyPullExpected(i: { now: number; forecastEq: number; enemyDesiredEq: number; pullSec: number[]; supportInLane: boolean }): number | undefined`. It returns the next aggro time when all of these hold, else `undefined`:
    - `i.supportInLane` is true;
    - `i.pullSec` is non-empty;
    - `LaneScore(i.enemyDesiredEq, −i.forecastEq, 0) ≤ Planner.SmallDriftBelow`;
    - `CampsUp(aggroAt)`, where `aggroAt = NextAggroTime(i.now, i.pullSec, Timing.PullPeriod)`.
  - Signal: `{ kind: "pull_expected", lane, at: now, campIdx, enemyPid, aggroAt }`. Its key is `` `pexp:${campIdx}:${math.floor(aggroAt / Timing.WaveCycle)}` ``.

**Rules in `pullSignals`:**
- Only when `LaneConfig.IsOn("PreContest")` and `LaneConfig.SkillOf(bot) >= Gates.PreContest`, checked before `observe`, so no notice roll is spent below the gate.
- Camp: the first enemy camp (`camps[0]`) with `pull` data.
- `supportInLane`: `support !== undefined && isLaner(support, s)`.
- `enemyDesiredEq`: `LaneState.DesiredEq(LaneState.LaneKindOf(enemyTeamOf(s.team), s.lane), false)`.
- `pullSec`: `PullTiming.ForCamp(camp, false).seconds`.
- The notice roll comes from `observe` (`CounterNotice`).

- [ ] **Step 1: Write the failing tests** (the pure function directly, then through `Tick` with the file's `world`)

```lua
local C = LaneFresh({ Enable = true }).Lane.Counter
-- Our top is the enemy's safe lane (desired -0.7); our forecast eq -0.6 is their 0.6.
local base = { now = 60, forecastEq = -0.6, enemyDesiredEq = -0.7, pullSec = { 15, 45 }, supportInLane = true }
local function with(o) local t = {} for k, v in pairs(base) do t[k] = v end for k, v in pairs(o) do t[k] = v end return t end
check("lane drifting to their tower: pull expected at :15", C.EnemyPullExpected(base) == 75)
check("lane at their wanted spot: no pull expected", C.EnemyPullExpected(with({ forecastEq = 0.7 })) == nil)
check("support not in lane: none", C.EnemyPullExpected(with({ supportInLane = false })) == nil)
check("camps not up before 1:00: none", C.EnemyPullExpected(with({ now = 0, pullSec = { 15 } })) == nil)
```

Through `Tick`:
- Skill 1 `world`, with `LANE_FRONT` set so `eqPos` reads about −0.6 and with the enemy support seen at the front: one `pull_expected` signal from `signalsOf(H, support, "pull_expected")`.
- Skill 0.6 (below the gate): none.
- `cfg = { Enable = true, PreContest = false }`: none, and the existing "noticed pull" contest test still passes. This is Review Focus 4.
- Enemy support never visible and no `LAST_SEEN` entry: none. This is Review Focus 2.

- [ ] **Step 2: Build and run to verify they fail**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_counter.lua`
Expected: `C.EnemyPullExpected` is nil.

- [ ] **Step 3: Implement the function, the signal and the docs.**

- [ ] **Step 4: Build and run**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_counter.lua`
Expected: no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add typescript/bots/FunLib/humaniser bots/FunLib/humaniser tests/humaniser/test_lane_counter.lua docs/HUMANISER_DEV.md
git commit -m "Counter-play: expect the enemy pull from the mirrored lane forecast (pull_expected)"
```

---

### Task 4: Pre-contest job with a lookout phase

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts`
  - `JobRequest` gains `preAggroAt?: number`;
  - `Job.phase` gains `"lookout"`. It's a new name because `"watch"` already means the pull's wave watch, which `keepGoing` grades on timeout;
  - `Job` gains `attackFrom?: number`;
  - `startContest`, `stepContest`, the contest timeout in `keepGoing`, and `endContest` (rules below);
  - `register`'s `lane_job_start` gets `["pre", 1]` when `preAggroAt` is set.
- Modify: `typescript/bots/FunLib/humaniser/counterplay.ts`: `respondToPull` handles `pull_expected` (rules below).
- Modify: `docs/HUMANISER_DEV.md`
  - in the telemetry table: `lane_job_start` `pre`, and the new `lane_job_end` contest line;
  - in the counter-play section: the lookout behaviour and its end reasons;
  - in `HUMANISER_TEST_PLAN.md`: the four in-game items from spec section 6.
- Test: `tests/humaniser/test_lane_counter.lua`

**Interfaces:**
- Consumes: from Task 3, the `pull_expected` signal (`campIdx`, `enemyPid`, `aggroAt`).
- Produces:
  - `CampJobs.LookoutPoint(origin: Vector, path: Vector[], dist: number): Vector`, the point `dist` along the polyline that starts at `origin` and runs through `path`. Returns the last point if the polyline is shorter.
  - Telemetry `lane_job_end` from `endContest`: `pid kind=contest camp reason pre` (`pre` 1 or 0). `reason` is one of `no-target`, `timeout`, `enemy-in-lane` or `no-pull`.

**Rules:**
- **`respondToPull`, for a noticed `pull_expected` not yet responded:**
  - Require `LaneRoles.CampJobOwner(s) === pid`, `LanePlanner.Committed(bot) === undefined`, `!CampJobs.Active(bot)` and `LaneRoles.PartnerSafe(bot, s, enemies)`.
  - Lookout point: `LookoutPoint(spawner.location, PullTiming.LeadPath(data.pull, data.pull.meetPoint), Radii.PreContestStand)`, with `data = Camps.ByIdx(campIdx)`.
  - `travel = distance / max(movement speed, 1)`. Start only when `travel ≤ Timing.MaxTravel`, `now + travel ≤ aggroAt − PreContestLead`, and `now ≥ aggroAt − PreContestLead − travel − 1`. The last condition means the bot leaves at most a second before it needs to.
  - `pathSafe(bot, s, lookout, enemies, enemyPid)`.
  - Then `CampJobs.Start(bot, { kind: "contest", campIdx, targetPid: enemyPid, preAggroAt: aggroAt })`, and mark the signal responded on success.
- **`startContest` with `preAggroAt`:** `phase: "lookout"`, `stand` and `path` set to the lookout point, `aggroAt: preAggroAt`. `register` commits `"contest"` as today.
- **`stepContest` in `lookout`, checked in this order:**
  1. `contestTarget(bot, job) !== undefined`: set `attackFrom = now` and `phase = "travel"`, then fall into the existing contest logic.
  2. `now ≥ aggroAt − PreContestLead`, and the `targetPid` enemy is visible within `Radii.Exposure` of `LaneState.ForBot(bot).frontLoc`: `endContest(bot, job, "enemy-in-lane")`.
  3. `now > aggroAt + PreContestWait`: `endContest(bot, job, "no-pull")`.
  4. Not arrived: `moveTo(bot, job.stand)`.
  5. Otherwise hold the same way the `lane:job_wait` hold does (`camp_jobs.ts` around line 1427), with source `"lane:precontest"`, and return true.
- **`keepGoing`'s contest timeout** measures from `job.attackFrom ?? job.startedAt`, so `ContestMax` (10 s) counts from the first sight of the puller.

- [ ] **Step 1: Write the failing tests** (in `test_lane_counter.lua`, a skill 1 `world` with a noticed `pull_expected` for aggro at 75, the support at `Vector(0, 5300)`)

```lua
local p = H.Lane.CampJobs.LookoutPoint(Vector(0, 0), { Vector(0, 300), Vector(1000, 300) }, 400)
check("lookout point is 400 along the polyline", near(p.x, 100) and near(p.y, 300), p.x .. "," .. p.y)
p = H.Lane.CampJobs.LookoutPoint(Vector(0, 0), { Vector(200, 0) }, 400)
check("short path: lookout at its end", near(p.x, 200) and near(p.y, 0))
```

Use `CampJobs.TravelTime(dist, speed)` for `travel`.

Behaviour checks, each from a fresh `world`. "Ticking" means `H.Lane.Counter.Think(support, {})`, then `H.Lane.CampJobThink(support)` at the stated `T` values.
- At `T` = aggroAt − 2 − travel: `CampJobs.Current(support).phase == "lookout"`, `kind == "contest"`, `Committed(support) == "contest"`.
- It walks to the lookout point (`MoveToLocation` args equal the lookout point), then issues no further move or attack while waiting.
- When the enemy support appears at `THEIR_SMALL` at `T` = 75: it attacks it (`attacksOn(4, esup) == 1`) and the phase is no longer `lookout`.
- When the enemy support is visible at our front at `T` = 73.5: the job ends (`CampJobDesire(support) == 0`) and the `contest-end` log has `reason=enemy-in-lane`.
- When nothing happens: at `T` = 79.1 the job has ended (`CampJobDesire(support) == 0`).
- `ContestMax` counts from the attack: the enemy appears at 76, the job is still live at 85 and over at 86.1.
- When `Commit(support, "full_pull")` was called this cycle: no job starts. This is Review Focus 3.
- With the support placed 5000 from the camp (travel over 12 s): no job starts. Likewise at `T` = 74, when it can no longer arrive by aggroAt − 2. This is Review Focus 5.

- [ ] **Step 2: Build and run to verify they fail**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_counter.lua`
Expected: `LookoutPoint` is nil, and the phase check FAILs.

- [ ] **Step 3: Implement the rules above, then the docs and test-plan items.**

- [ ] **Step 4: Build and run**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_lane_counter.lua test_lane_camp_jobs.lua test_lane_regression.lua`
Expected: no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add typescript/bots/FunLib/humaniser bots/FunLib/humaniser tests/humaniser/test_lane_counter.lua docs/HUMANISER_DEV.md docs/HUMANISER_TEST_PLAN.md
git commit -m "Counter-play: pre-contest the expected enemy pull from a lookout on their pull path"
```

---

### Task 5: `lane_eq` telemetry and the analyser fit

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/lane_state.ts`
  - `Track` gains `eqSampledCycle?: number`;
  - in `refresh`, when `cycleSec >= Timing.EqSampleAt` and `t.eqSampledCycle !== t.cycle`, set it and emit `Telemetry.Event("lane_eq", [["team", team], ["lane", lane], ["kind", kind], ["eq", eqPos], ["imb", imbalance], ["feq", forecastEq], ["a", ally.count], ["e", enemy.count]])`.
  - If importing `telemetry` from `lane_state` creates a require cycle, route it through the existing `OnRefresh` callback from `lane.ts` instead.
- Modify: `tools/hlog/report.js`
  - add `forecastSection(game)` to `summary`;
  - export `fitForecast(events)` for tests.
- Modify: `docs/HUMANISER_DEV.md`: the `lane_eq` row in the telemetry table, and how to read the fit.
- Test: `tools/hlog/test/hlog.test.js`, `tests/humaniser/test_telemetry.lua`

**Interfaces:**
- Consumes: from Task 1, `imbalance` and `forecastEq`.
- Produces:
  - `fitForecast(events: object[]): { kind: string, n: number, k: number, r2: number }[]`. Pairs `lane_eq` events of the same `team` and `lane` whose times are 25 to 35 s apart; `Δeq = next.eq − this.eq` against `this.imb`.
  - The fit is least squares through the origin: `k = Σ(imb·Δ) / Σ(imb²)`, with `r2 = 1 − Σ(Δ − k·imb)² / Σ(Δ − mean Δ)²`.
  - One row per `kind`, and none when `n < 2`.
  - `forecastSection` prints `forecast fit:` then one line per row, `  <kind> n=<n> K=<k.toFixed(2)> r2=<r2.toFixed(2)>`.
- Also add a pre-contest line to `forecastSection`: `pre-contest: started <n> attacked <n> no-pull <n> enemy-in-lane <n>`. Started comes from `lane_job_start` events with `kind=contest pre=1`; the other counts come from `lane_job_end` `kind=contest pre=1` reasons. "attacked" is the ends with reason `no-target` or `timeout`.

- [ ] **Step 1: Write the failing tests**

In `hlog.test.js`:

```js
test('forecast fit recovers K from lane_eq pairs', () => {
    const ev = (t, eq, imb) => ({ ev: 'lane_eq', t, team: 2, lane: 1, kind: 'safe', eq, imb });
    const rows = report.fitForecast([ev(70, -0.5, 0.5), ev(100, -0.35, -0.25), ev(130, -0.425, 0.0), ev(160, -0.425, 0.4)]);
    assert.strictEqual(rows.length, 1);
    assert.strictEqual(rows[0].n, 3);
    assert.ok(Math.abs(rows[0].k - 0.3) < 1e-9);
});
test('forecast fit skips pairs more than one cycle apart', () => {
    const ev = (t, eq, imb) => ({ ev: 'lane_eq', t, team: 2, lane: 1, kind: 'safe', eq, imb });
    assert.strictEqual(report.fitForecast([ev(70, -0.5, 0.5), ev(160, 0, 0)]).length, 0);
});
```

In `test_telemetry.lua`, following the file's sink pattern, check that exactly one `lane_eq` line per team and lane per cycle appears, at or after cycle second 10. Do this by refreshing the snapshot at `T` = 65, 71, 72.

- [ ] **Step 2: Build and run to verify they fail**

Run: `npm run build:lua && cd tests/humaniser && node run.js test_telemetry.lua && npm run hlog`
Expected: no `lane_eq` line, and `report.fitForecast` is not a function.

- [ ] **Step 3: Implement the event, the fit and the section, then the docs.**

- [ ] **Step 4: Run the full offline check**

Run: `cd tests/humaniser && npm run check`
Expected: exit code 0, no `FAIL` lines.

- [ ] **Step 5: Commit**

```bash
git add typescript/bots/FunLib/humaniser bots/FunLib/humaniser tools/hlog tests/humaniser/test_telemetry.lua docs/HUMANISER_DEV.md
git commit -m "Telemetry: lane_eq per wave cycle; hlog fits the forecast K and summarises pre-contests"
```
