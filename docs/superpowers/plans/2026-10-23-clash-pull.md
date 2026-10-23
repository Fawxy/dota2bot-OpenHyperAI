# Clash Pull Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the lane-at-meet gate refuses a planned pull, a skilled support pulls the camp to the lane fight, hitting it as the enemy creeps there are about to die.

**Architecture:** A new camp-job kind `clash_pull` in `camp_jobs.ts`. It gets its own entry in `schedule` (not bound to a pull second), its own start (`startClash`), and its own wait phase whose hit is triggered by a clear-time prediction from the snapshot's front creeps. After the hit it reuses the full pull's aggro, lead, watch and grading, with the fight point as its meet.

**Tech Stack:** TypeScript compiled to Lua with TSTL (`npm run build:lua` in the repo root); offline tests in Lua under fengari (`tests/humaniser`, `node run.js <file>`, `npm run check`); the hlog analyser in Node (`npm run hlog`).

**Spec:** `docs/superpowers/specs/2026-10-23-clash-pull-design.md`

## Global Constraints

- Edit TypeScript under `typescript/bots/FunLib/humaniser/`, then run `npm run build:lua` (repo root) and commit the regenerated `bots/FunLib/humaniser/*.lua`. Never hand-edit generated Lua.
- Never commit `bots/Customize/general.lua`: it holds a local `OwnLaningThink = 'all'`. Stage files by path, never `git commit -a`.
- Config values, verbatim from the spec: `Flags.ClashPull: true`; `Gates.ClashPull: 0.7`; `Thresholds.ClashAllyMin: 2`; `Radii.ClashPullReach: 2000`, `Radii.ClashStandOff: 400`, `Radii.ClashFight: 600`; `Timing.ClashRateWindow: 1.5`, `Timing.ClashWaitMax: 15`, `Timing.ClashWaveMargin: 3`.
- "The clash" is always the snapshot's front creeps: `s.ally.units` and `s.enemy.units` (`LaneState.ForBot(bot)`), for the start, the aborts and the prediction.
- Log kind for `clash_pull` is `clash` (`LOG_KIND`). Abort and end reasons, verbatim: `lane-won`, `clash-lost`, `next-wave`, `wait-max`; the hold is `outnumbered`.
- Comments only where they add something not obvious; match the surrounding style (see `camp_jobs.ts`).
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

## Review Focus

1. The fight point moves while the support waits (the front advances): the reach check and the camp walk must use the current point each frame, and the point is frozen at the hit. Test in Task 3.
2. Our creeps die mid-wait so the snapshot's enemy set reads empty: that must be `clash-lost`, not `lane-won`. Test in Task 3.
3. Enemy HP rises between samples (a new enemy creep joins the front): no prediction from a rising or flat HP. Test in Task 1.
4. No enemy-wave arrival history yet (`s.enemyArrivalSec` undefined): the `next-wave` check is skipped, not treated as "now". Test in Task 3.
5. The camp has been farmed or pulled away when the trigger fires: the existing `mistake:no-camp` path ends the job; the clash must not attack anything else. Test in Task 3.

---

### Task 1: Config, the kind, and the two pure helpers

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/lane_config.ts` (the `LaneFlag` union, `Flags`, `Gates`, `Thresholds`, `Radii`, `Timing`)
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts` (`JobKind`, `PULL_KINDS`, `LOG_KIND`, `FLAG_OF`, `commitTech`, new exports)
- Test: `tests/humaniser/test_lane_camp_jobs.lua`

**Interfaces:**
- Produces: `JobKind` includes `"clash_pull"`; `PULL_KINDS.clash_pull = true`; `LOG_KIND.clash_pull = "clash"`; `FLAG_OF.clash_pull = "ClashPull"`; `commitTech("clash_pull") === "full_pull"`.
- Produces: `export function ClashPoint(front: Vector, origin: Vector, standOff: number): Vector`, which is `front` moved `standOff` toward `origin` (or `origin` itself if it is closer than `standOff`).
- Produces: `export interface HpSample { t: number; hp: number }` and `export function ClearPrediction(samples: HpSample[], now: number, window: number): number | undefined`. Seconds until the latest HP reaches 0 at the drop rate between the oldest sample within `window` of `now` and the latest. `undefined` when the samples in the window span under 1 s, or the HP did not fall.

- [ ] **Step 1: Write the failing tests**

```lua
do
	local J = LaneFresh({ Enable = true }).Lane.CampJobs
	local p = J.ClashPoint(Vector(0, 0), Vector(1000, 0), 400)
	check("clash point stands off toward the camp", near(p.x, 400) and near(p.y, 0))
	local q = J.ClashPoint(Vector(0, 0), Vector(300, 0), 400)
	check("a camp nearer than the stand-off is the point", near(q.x, 300))
	check("no prediction under 1 s of history", J.ClearPrediction({ { t = 10, hp = 900 }, { t = 10.8, hp = 700 } }, 10.8, 1.5) == nil)
	check("clear time from the drop rate", near(J.ClearPrediction({ { t = 10, hp = 900 }, { t = 11, hp = 600 } }, 11, 1.5), 2))
	check("only samples in the window count", near(J.ClearPrediction({ { t = 5, hp = 5000 }, { t = 10, hp = 900 }, { t = 11, hp = 600 } }, 11, 1.5), 2))
	check("no prediction while the HP rises", J.ClearPrediction({ { t = 10, hp = 600 }, { t = 11, hp = 900 } }, 11, 1.5) == nil)
	check("no prediction while the HP is flat", J.ClearPrediction({ { t = 10, hp = 600 }, { t = 11, hp = 600 } }, 11, 1.5) == nil)
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `npm run build:lua` (repo root), then `node run.js test_lane_camp_jobs.lua` in `tests/humaniser`. Expected: an error calling a nil `ClashPoint`.

- [ ] **Step 3: Add the config values (Global Constraints) with `"ClashPull"` in `LaneFlag` (not in `CONSUMER_FLAGS`), the kind entries above, and the two helpers**

- [ ] **Step 4: Build and run the file again.** Expected: `0 failed`.

- [ ] **Step 5: Commit**

```bash
git add typescript/bots/FunLib/humaniser/lane_config.ts typescript/bots/FunLib/humaniser/camp_jobs.ts bots/FunLib/humaniser/lane_config.lua bots/FunLib/humaniser/camp_jobs.lua tests/humaniser/test_lane_camp_jobs.lua
git commit -m "Clash pull: config, kind, clash point and clear-time helpers"
```

### Task 2: Starting a clash pull

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts` (`schedule`, `Start`, new `startClash`, `abort`, `orderAggro`)
- Test: `tests/humaniser/test_lane_camp_jobs.lua`

**Interfaces:**
- Consumes: `ClashPoint`, `PULL_KINDS`, `commitTech` (Task 1); `PullTiming.LeadPath`, `PullTiming.WalkLength`; `laneAtMeet(meet)` (existing).
- Produces: a `Job` with `kind: "clash_pull"`, `phase: "travel"`, `meet` set to the current fight point, `path` set to `leadPath(...)` towards it, `aggroAt` = start time (unused until the hit), and the new fields `clash: { samples: HpSample[]; walk: number; waitFrom?: number; pred?: number }`. `startClash(bot: Unit, req: JobRequest): boolean`, reached through `Start` when `req.kind === "clash_pull"`.
- Produces: `abort(..., keepCycle = false)` as a new last parameter. When true, abort releases the commit and leaves `doneCycle` unset, like the not-acted branch.

The `schedule` entry: after the `no-camp` check and before the `windowFor` check, if the clash conditions hold (spec "When it is chosen", 0–4), call `Start(bot, { kind: "clash_pull", campIdx: camps[0].campIdx })` and return its result. "Gate would refuse" means `laneAtMeet` on the chosen pull's meet point. The lane-at-meet gate for timed pulls stays where it is. `orderAggro`'s pre-hit gate calls `abort(bot, job, "lane-at-meet", false, [], false, true)`, and the gate never runs for `clash_pull`. Reach is `WalkLength(spawner.location, LeadPath(pull, fight)) <= Radii.ClashPullReach`. `walk` is that length over `PullTiming` `NeutralSpeed[data.type]`.

Test world: the existing `jobWorld`. Put our and enemy creeps at the front with `MakeCreep({ team = 2|3, x, y })` at `GetLaneFrontLocation(2, Lane.Bot, 0)`. Put one of ours at the camp's meet point so the gate fires. Set HP via the creep's `hp`. Call `H.Lane.LaneState.ResetCache()` after moving creeps if the snapshot is cached.

- [ ] **Step 1: Write the failing tests**, each asserting `H.Lane.CampJobs.Current(support)` (`.kind == "clash_pull"`, or nil), plus the `lane_plan gate=lane-at-meet` line where nil:
  - our 3 creeps beat 2 enemy creeps at the front, ours also at the meet, skill 0.9, at cycle second 5 (a time no timed pull window is open) → a clash job;
  - the same with enemy power ≥ ours → none, gate line;
  - skill 0.6 → none; `ClashPull = false` → none;
  - front moved so the lead path is over 2000 → none;
  - a timed pull aborted `lane-at-meet` before its hit, then the clash conditions true later in the same cycle → a clash job;
  - after a clash job ends in a cycle, no second clash job in that cycle.
- [ ] **Step 2: Build, run, verify they fail** (no `clash_pull` job).
- [ ] **Step 3: Implement `startClash`, the `schedule` entry, `keepCycle`, and the gate exemption**
- [ ] **Step 4: Build, run.** Expected: `0 failed`, and the earlier lane-at-meet tests still pass.
- [ ] **Step 5: Commit** (TS, regenerated `camp_jobs.lua`, the test file): `git commit -m "Clash pull: start from the lane plan when the meet point is in the fight"`

### Task 3: Waiting for the clash, the hit, and the ends

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts` (`step`, new `stepClashWait(bot: Unit, job: Job, now: number): boolean`)
- Test: `tests/humaniser/test_lane_camp_jobs.lua`

**Interfaces:**
- Consumes: the `clash` job state (Task 2), `ClearPrediction` (Task 1), `campNeutral`, `orderAggro`, `aggroLead`, `abort`.
- Produces: once hit, `job.meet` and `job.path` are frozen at the fight point of the hit frame, `job.clash.pred` is the last prediction before the hit, and `job.waveAt` is undefined. From there the full pull's `aggro`/`lead`/`watch` run unchanged and grade with `Grade("full_pull", ...)`.

In `step`, a `clash_pull` in `travel`/`wait` goes to `stepClashWait`. That function walks to the stand, as the full pull does. Every frame it re-reads the fight point and walk (Review Focus 1), and pushes `{ t: now, hp }` with hp = total HP of `s.enemy.units`, keeping only `ClashRateWindow`. At the stand it holds (`Intent.Hold(bot, "lane:job_wait")`). It ends, in this order:
1. `clash-lost`: ally power ≤ enemy power, or fewer than `ClashAllyMin` of ours.
2. `lane-won`: ours present and `s.enemy.units` empty.
3. `next-wave`: the next `s.enemyArrivalSec` within `walk + ClashWaveMargin` of now; skipped when undefined.
4. `wait-max`: `ClashWaitMax` after reaching the stand.

It hits (`orderAggro` on `campNeutral`) when `pred <= walk + aggroLead(bot, creep)`, unless 2+ visible enemy heroes are within `TakePullDanger` of the fight point. If there is no camp neutral by then, it takes the full pull's `NoCampAfter` path with `aggroAt` set to the trigger time.

- [ ] **Step 1: Write the failing tests**
  - Hit timing: with enemy HP falling 300/s from 1500 and `walk` ≈ 4 s, there's no `AttackUnit` on the neutral before the prediction reaches `walk + lead`; there is one on the first frame after.
  - No hit in the first second of samples.
  - Each end, with no attack on the camp and the matching `lane_job_abort reason=`: `clash-lost` when ours drop below the enemy; `clash-lost` (not `lane-won`) when ours are all gone; `lane-won` when the enemy creeps die first; `next-wave` with arrivals recorded at a second 2 s ahead; `wait-max` after 15 s at the stand.
  - No `next-wave` end with no arrival history.
  - Two enemy heroes at the fight: no hit while the prediction says hit. One enemy hero: hit.
  - After the hit, the front moves 500 along the lane: the lead still ends at the hit's fight point (`job.meet` unchanged).
  - A whole clash pull diverting 4 of 4 grades `lane_job kind=clash ... grade=ok`.
- [ ] **Step 2: Build, run, verify they fail.**
- [ ] **Step 3: Implement `stepClashWait` and the `step` routing.**
- [ ] **Step 4: Build, run.** Expected: `0 failed`.
- [ ] **Step 5: Commit:** `git commit -m "Clash pull: hit on the predicted clear, lead to the fight, ends"`

### Task 4: Telemetry, hlog summary and docs

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts` (`register` fields, `tracePull`, `logTrace`)
- Modify: `tools/hlog/report.js` (`forecastSection`, next to `pull trace`)
- Modify: `docs/HUMANISER_DEV.md` (telemetry rows for `lane_job_start`, `lane_job_abort`, `lane_pull_trace`; a "Clash pull" paragraph after "Lane at the meet point"; `lane_plan` gate note)
- Test: `tests/humaniser/test_lane_camp_jobs.lua`, `tools/hlog/test/hlog.test.js`

**Interfaces:**
- Produces: `lane_job_start kind=clash ... fight=<x>,<y> walk=<s>` (rounded with `round3`, x/y to integers); `lane_pull_trace` for `clash` adds `pred` and `cleared` (seconds after the hit; `cleared` is the first trace sample with no `s.enemy.units` within `Radii.ClashFight` of `job.meet`, -1 if never).
- Produces: the hlog line `clash pull: started <n> ok <n> weak <n> no-divert <n> lane-won <n> clash-lost <n> next-wave <n> wait-max <n> other <n> cleared-pred <+x.xs|->`, the last being the median of `cleared - pred` over traces with both ≥ 0.

- [ ] **Step 1: Write the failing tests.** In Lua: the start line carries `fight=` and `walk=`; the clash trace carries `pred` and `cleared`, with `cleared` matching the frame the last enemy creep was removed (`RemoveCreep`). In `hlog.test.js`: a log with 2 clash starts, one graded ok with trace `pred=3 cleared=3.5` and one `lane_job_abort kind=clash reason=wait-max`, matches `/clash pull: started 2 ok 1 weak 0 no-divert 0 lane-won 0 clash-lost 0 next-wave 0 wait-max 1 other 0 cleared-pred \+0\.5s/`.
- [ ] **Step 2: Run, verify they fail.**
- [ ] **Step 3: Implement the fields, the summary line, and the docs.**
- [ ] **Step 4: Run `npm run check` in `tests/humaniser`.** Expected: exit 0, every suite `0 failed`, hlog `# fail 0`.
- [ ] **Step 5: Commit:** `git commit -m "Clash pull: telemetry, hlog summary, docs"`
