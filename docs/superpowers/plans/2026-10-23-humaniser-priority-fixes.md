# Humaniser Priority Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bots should prioritise like human laners. Last hits come before kill attempts that are marginal or wasted. Cores stay in lane instead of backing out whenever an enemy is out of sight. Supports don't leave the lane when it's risky or when another plan already needs them. Every change is shown to help with before/after telemetry from real games.

**Architecture:** No new subsystems. Each task changes gates or values in modules that already exist (`transitions/caution.ts`, `camp_jobs.ts`, `kill_check.ts`, `lane_fight.ts`, `lane_tech.ts`, `farm_pattern.ts`, `transitions/rotation.ts`, `bots/mode_laning_generic.lua`). Two new `LaneHooks` probes let modules read each other's state without circular requires. Task 0 adds a build stamp to the telemetry and a metrics/compare tool to `tools/hlog`. Baseline games are recorded before any behaviour change; every later task ends with a before/after comparison against that baseline.

**Tech Stack:** TypeScript → Lua via TSTL (`npm run build` in `oha/`), hand-written Lua mode files, offline tests in fengari (`tests/humaniser`, `npm run check`), Node analyser (`tools/hlog`, `node --test`).

**Spec:** the review findings of 23/10/2026, summarised in "Findings this plan fixes" below. The evidence game is `console.9057308756.log` (all bots, 10:51; Troll 12 last hits, cores cautious 40–70% of the laning phase, Magnus 12 kill commits with 3 kills).

**Worktree:** create `oha-priority` on a new branch `h-priority` from `humaniser` @ `568dbc9` (superpowers:using-git-worktrees). Symlink `node_modules` to `../oha/node_modules`, as the other worktrees do. **The Dota `bots` symlink is shared between worktrees, and other sessions re-point it.** Re-point it to this worktree before every game, and trust a log only when its `build=` field matches the commit you meant to run (Task 0 adds that field).

## Findings this plan fixes

| # | Finding | Task |
|---|---|---|
| F1 | Caution's retreat ×1.3 (any enemy laner unseen 4–6 s, held up to 60 s) and `lane:cover`'s ×1.25 stack on retreat. That lifts the laning-phase creep-aggro retreat (0.75–0.9) over laning's last-hit 0.9, so cores back out of lane and lose CS. | 1 |
| F2 | Caution's attack ×0.7 and the commit focus cap on attack do nothing for every hero except the buggy-hero overrides (Valve's C++ attack mode is never resolved). | 1, 5 |
| F3 | Laning bids 0.9 for a pending last hit only in upstream's two special cases, not for every bot whose `Think()` OHA owns. | 2 |
| F4 | `LastHitThink` swings early at a creep not yet killable (its HP is between 1× and 1.7× the bot's damage), counts that swing as an attempt, and blocks a deny that's available. | 2 |
| F5 | A support decides "a core is near" from its own position, not the creep's, so it takes hits from a bot core that is about 800 away. | 2 |
| F6 | Aggro pulls start, walk back for 1.5 s, and the tower-swap holds 1.5 s, all with a creep dying in range. | 3 |
| F7 | Kill check: full 5 s burst credited at any distance up to 1200; only 2 s of the target's regen counted; no creep, tower or enemy-hero damage on the bot; allies anywhere in the lane counted; one threshold for every position; missing enemies ignored. | 4 |
| F8 | A failing commit runs to `CommitMax` 8 s. Followers join a partner's trade at margin 0.8. Retreat stays capped while a tower targets the bot. | 5 |
| F9 | Pulls, stacks and core jungle trips ignore missing enemies. A pull or stack can be scheduled after a rune rotation is decided. A rotation is never re-checked after its decision. A core's trip can take the camp its support is about to pull, including while the core is covering for it. A mid's trip (0.62) can win over the power rune floor (0.60). | 6 |

**Deferred, and why:** perception leaking through `GetHeroLastSeenInfo` in `LaneState.Enemies` (needs an in-game probe first: does `time_since_seen` read ≈0 for a visible hero?); cooldown memory recording nothing (lane-fight Task 4b, a data job); handoffs 08 and 13; the enemy-bot `OwnLaningThink` default; block coordination; the harass punish's expiry; counter-play's contest gates; `MayTouchWave` on last hits. List them under "Follow-ups" in the 00-README when Task 7 updates it.

## Global Constraints

- Edit the `.ts` file, then run `npm run build`. Never hand-edit a generated `bots/FunLib/humaniser/*.lua`. Mode files (`bots/mode_*.lua`) are edited directly.
- Every new tunable is a `DEFAULTS` entry in that module's existing settings file (`transitions/settings.ts`, `lane_config.ts` `Thresholds`/`Timing`, `lane_fight_config.ts`, `farm_pattern.ts` `Settings`), so it can be overridden from `Customize.Humaniser`. No magic numbers inline.
- With `Customize.Humaniser.Enable = false` the behaviour is still upstream OHA. Each feature's own `Enable`/flag still turns off everything this plan adds to it.
- No new per-call `GetUnitList` scans. Reuse `LaneState.ForBot`, `LaneState.Enemies`, and the snapshot's `enemy.units`.
- Per-bot state is keyed by `GetPlayerID()`.
- `cd tests/humaniser && npm run check` passes after every task. It runs syntax, the fengari tests, mining, and the hlog tests.
- Tests follow `tests/humaniser/test_*.lua` style (`check(name, bool)`, `near(a, b)`, `LaneFresh(...)` worlds) and the user's test rules. Assert business outcomes, not assignments. Each test must fail if the change under test is reverted.
- Commit after each task with the repo's message style: an imperative summary naming the area, e.g. `Caution: …`. End each message with the attribution lines.

## Review Focus

1. **A core alone against a visible enemy that hits it:** the retreat must still win. F1's fix must not leave cores standing in a losing trade. Task 1 tests this, and the deaths@10 metric in Task 7 is the guard.
2. **A support pulling while the enemy support is merely in the fog near their own camp:** pulls must not stop entirely. Task 6's missing gate uses a freshness window, and Task 7 checks the pulls-per-game count stays within 30% of baseline.
3. **A commit on a target that walks into its own tower at 20% HP:** the bot keeps hitting only when the kill check, now including tower damage, still passes. Task 4 tests the tower damage.
4. **A ranged core whose `moveToCreep` creep is in range:** after F4 it must still last-hit when the creep becomes killable, not stand idle through the kill. Task 2 tests the hold, then the hit on the next frame.
5. **A mid at x:50 before an even minute:** no jungle trip starts. Task 6 tests this.

---

### Task 0: Before/after measurement and baseline games

**Files:**
- Create: `typescript/post-process/build-info.js` (writes `bots/FunLib/humaniser/build_info.lua`); add `bots/FunLib/humaniser/build_info.lua` to `.gitignore`
- Modify: `package.json` (`build:lua` runs `node ./typescript/post-process/build-info.js` after post-process)
- Modify: `typescript/bots/FunLib/humaniser/telemetry.ts` (`maybeProfile`, both `bot` events)
- Create: `tools/hlog/metrics.js`, `tools/hlog/compare.js`
- Test: `tools/hlog/test/hlog.test.js` (new `describe`-free tests, same style as the file)
- Modify: `docs/HUMANISER_DEV.md` (new "Before/after runs" subsection under "Telemetry and log analysis")

**Interfaces:**
- Produces: `bot` event gains `build=<git short sha, '+dirty' when the tree has changes>` and `pos=<1..5>` (`LaneConfig.PositionOf(bot)`; absent when undefined).
- Produces: `metrics.js` `laningMetrics(game, { until = 600 }) -> { complete: boolean, build: string, bots: BotMetrics[] }` where `BotMetrics = { pid, hero, team, pos, lh, dn, deaths, retreatSec, retreatHealthySec, retreatBy: {source: sec}, cautiousSec, commits, commitKills, commitSec, trades, pullsStarted, stacksStarted, rotations, aggroWithLastHit }`.
- Produces: `compare.js` CLI: `node tools/hlog/compare.js [--until 10:00] --base <log...> --cand <log...>`, or `--dir <dir> --builds <shaA>,<shaB>` (that form picks every game in the directory's `console.*.log` files whose `build` matches).

- [ ] **Step 1: Build stamp.** `build-info.js` runs `git rev-parse --short HEAD` and `git status --porcelain`, then writes `return { build = "<sha>[+dirty]" }`. Use `pcall` so it writes `"unknown"` when git fails. In `telemetry.ts`, load it once at module load with `pcall(require, "bots/FunLib/humaniser/build_info")` (falling back to `"unknown"`), and add `["build", ...]` and `["pos", LaneConfig.PositionOf(bot)]` to both `bot` events. Bump `SCHEMA` to 2.

- [ ] **Step 2: Write failing analyser tests** in `hlog.test.js`, using the file's `header()`/`snaps()` helpers to build synthetic logs:
  - `laningMetrics: lh and dn are read from the last snap at or before 10:00`. Snaps give lh 0..40 over 0..660 s, so the expected lh is the value at t=600.
  - `laningMetrics: retreatHealthySec counts retreat time only while hp >= 60`. Mode events laning→retreat at 100 and retreat→laning at 110, with snap hp 80 for 100–104 and 40 for 105–110, should give 5.
  - `laningMetrics: retreatBy splits retreat time by the claim source in the mode event's by= text`. `by="retreat 1.10 by transitions:caution"` for 10 s should give `retreatBy["transitions:caution"] === 10`, and `by="... by raw"` should go to `raw`.
  - `laningMetrics: a game that ends before until is complete=false and compare skips it`.
  - `laningMetrics: commitKills counts lanefight_end phase=commit reason=target-dead`.
  - `compare: --builds picks games by bot build and reports per-position means with delta and a noisy flag when |delta| < 2 × pooled SE`.

- [ ] **Step 3: Run them.** `cd tests/humaniser && npm run hlog`. Expected: FAIL (`metrics.js` not found).

- [ ] **Step 4: Implement `metrics.js` and `compare.js`.**
  - Deaths are `alive` going 1→0 in snaps.
  - `cautiousSec` integrates `tr_caution` level > 0.
  - `pullsStarted` counts `lane_job_start` with `kind` containing `pull`; `stacksStarted` counts `kind=stack`.
  - `rotations` counts `tr_rotate go=1`.
  - `aggroWithLastHit` counts `lane_tech` start events with `lh=1` (Task 3 adds the field; until then it is 0).
  - The `by=` source is the text after the last ` by `, with `+sticky` stripped.
  - `compare.js` aggregates over games, groups by `pos`, and prints one row per metric: `metric pos base_mean±sd (n) cand_mean±sd (n) delta [noisy]`. A team-wide block follows for counts.
  - Reuse `parse.js` `parseLog` and the `report.js` `table()` helper (export it).

- [ ] **Step 5: Run tests.** `npm run hlog`. Expected: PASS.

- [ ] **Step 6: Write the protocol in `HUMANISER_DEV.md` "Before/after runs".**
  - **Arms:**
    - **A (defaults):** `general.lua` as committed.
    - **B (owned laning):** A plus `Lane.OwnLaningThink = 'all'`. Without that, nothing in Tasks 2–3 runs in an all-bot game.
  - **Lineup:** fix the heroes for every run by setting `Customize.Radiant_Heros = { 'npc_dota_hero_dragon_knight', 'npc_dota_hero_medusa', 'npc_dota_hero_magnataur', 'npc_dota_hero_jakiro', 'npc_dota_hero_shadow_demon' }` and `Customize.Dire_Heros = { 'npc_dota_hero_troll_warlord', 'npc_dota_hero_queenofpain', 'npc_dota_hero_venomancer', 'npc_dota_hero_mirana', 'npc_dota_hero_ogre_magi' }` (pos 1–5 in order) for the run only. Revert it before committing.
  - **Per game:** all-bot lobby, `host_timescale 4`, let it run to at least 11:00 game time. Check `node tools/hlog/analyse.js --list` and the `build=` field.
  - **Count:** 4 games per arm per build. Laning variance between bot games is high. The compare tool's `noisy` flag means "not shown". Add games until a key metric is not noisy, or accept "no change".
  - Re-point the `bots` symlink before each batch.

- [ ] **Step 7: Baseline (in-game, needs the user).**
  - Build at the worktree's base commit plus Task 0 only, so there is no behaviour change.
  - Run 4 games of arm A and 4 of arm B.
  - Record in `HUMANISER_DEV.md`: the baseline build sha, the log file names, and the compare tool's table of the baseline against itself (split into halves) as a noise reference.

- [ ] **Step 8: Commit.** `Telemetry: build stamp and position on bot events; hlog laning metrics and before/after compare`.

---

### Task 1: Caution is positioning plus readiness to run, not a standing retreat boost (F1, F2)

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/transitions/caution.ts:265-279` (`Tick`)
- Modify: `typescript/bots/FunLib/humaniser/transitions/settings.ts` (new keys)
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts:597-627` (`CoverTick`)
- Modify: `typescript/bots/FunLib/humaniser/lane_hooks.ts` (missing-enemy probe; Task 4 and Task 6 use it)
- Test: `tests/humaniser/test_transitions_caution.lua`, `tests/humaniser/test_lane_camp_jobs.lua`

**Interfaces:**
- Produces: `Caution.Threatened(bot: Unit): boolean`. True when `bot.WasRecentlyDamagedByAnyHero(cfg.ThreatHitWindow)` (2 s), or HP fraction < `cfg.ThreatHP` (0.5), or an enemy tower has the bot as its attack target.
- Produces: `Caution.MissingNow(bot: Unit): number`, the `missing` count from the current `update()` state (0 when caution is off or the bot is not laning).
- Produces: `LaneHooks.SetMissingProbe(fn: (bot) => number)` and `LaneHooks.EnemiesMissing(bot: Unit): number`, registered by caution's `RegisterProbes`. `ResetHooks` clears it.

- [ ] **Step 1: Write failing tests** in `test_transitions_caution.lua`, each in its own `do … end` world:
  - "missing enemy, untouched core: no retreat scale". An enemy unseen 10 s at the front makes the level > 0, the core is at full HP and was not hit, and `Intent.Resolve(core, BotMode.Retreat, 0.8)` must be `near(0.8)`.
  - "missing enemy and the core was hit 1 s ago: retreat scaled". The stub's `WasRecentlyDamagedByAnyHero` returns true, so Resolve(0.8) should be `near(0.8 * (1 + 0.3 * level))`.
  - "caution never posts an attack claim". After Tick at level 1, `Intent.Resolve(core, BotMode.Attack, 0.5)` must be `near(0.5)`. This asserts that Attack is not scaled for a buggy-hero override either: the claim only ever reached those heroes, and suppressing trades is the real lever.
  - "MissingNow reports the missing count". One unseen enemy should give 1.
  - In `test_lane_camp_jobs.lua`: "cover posts no retreat scale while Transitions caution is on". The support is on a job, `Covering(core)` is true, Resolve(Retreat, 0.8) should be 0.8. With `Transitions.Enable = false` it should be `near(0.8 * 1.25)`.

- [ ] **Step 2: Run** `node tests/humaniser/run.js tests/humaniser/test_transitions_caution.lua tests/humaniser/test_lane_camp_jobs.lua`. Expected: the new checks FAIL.

- [ ] **Step 3: Implement.**
  - In `Tick`, post the Retreat scale only when `Threatened(bot)`. Otherwise call `Intent.Release(bot, SOURCE, BotMode.Retreat)`.
  - Delete the Attack claim and the `AttackScaleMin` key, and update the module header comment.
  - New settings: `ThreatHitWindow: 2`, `ThreatHP: 0.5`.
  - For the tower test, reuse the tower-attack-target read that `camp_jobs.ts` `retreatThreat` already does. Move it to a small exported helper in `lane_state.ts`, `EnemyTowerTargeting(bot): boolean`, and call it from both places.
  - `CoverTick` posts its scale only when `!TransitionsSettings.IsOn("Caution")`. Caution's `IsAlone` already treats a support on a camp job or at a camp as leaving the core alone, so the scale was counted twice.
  - Register the missing probe.

- [ ] **Step 4: Run** the two files plus `npm run check`. Expected: PASS.

- [ ] **Step 5: Before/after (in-game).**
  - Build and run 4 arm-A games, then `node tools/hlog/compare.js --dir "<console dir>" --builds <baseline>,<this>`.
  - **Accept when:**
    - `retreatBy[transitions:caution]` + `retreatBy[lane:cover]` falls ≥ 50%;
    - pos 1 `lh` at 10:00 rises (not noisy), or is unchanged with `retreatHealthySec` down ≥ 30%;
    - mean `deaths` at 10:00 per position rises by no more than 0.5.
  - Record the table in `HUMANISER_DEV.md` under Transitions (12) → "Results".

- [ ] **Step 6: Commit.** `Caution: scale retreat only when threatened, drop the attack scale and the doubled cover scale`.

---

### Task 2: Owned laning prioritises its last hits and stops swinging early (F3, F4, F5)

**Files:**
- Modify: `bots/mode_laning_generic.lua:123-131` (GetDesire last-hit branch), `:33-38` (`CanTakeLastHit`), `:250-266` (`LastHitThink`)
- Modify: `typescript/bots/FunLib/humaniser/ally_last_hit.ts` (export the reach test)
- Test: create `tests/humaniser/test_laning_mode.lua`. It loads `bots/mode_laning_generic.lua` against a stub `J`, using the same loader that `test_lane_rune_mode.lua` uses for the rune mode.

**Interfaces:**
- Produces: `AllyLastHit.CoreCanReach(core: Unit, creep: Unit): boolean`, the existing human-reach rule (attack range + buffer, or approaching) applied to any allied core.

- [ ] **Step 1: Write failing tests** in `test_laning_mode.lua`:
  - "owned laning (Lane.OwnLaningThink='all') bids 0.9 with a killable creep for a pos 3". The stub `GetPosition` returns 3, there is one enemy creep with HP below the bot's damage, and `GetDesire()` (after Resolve with intent off) is `near(0.9)`.
  - "unowned laning keeps upstream's desire for a pos 3". With `Lane.Enable=false`, `GetDesire()` must not be 0.9.
  - "in range of a nearly-killable creep: no attack is issued, and a deny goes through". `moveToCreep` is true and the creep is within attack range; an allied creep is deniable. After `Think()` the recorded action is `AttackUnit(allyCreep)`, and `LastHitSkill.NoteAttempt` was not called for the enemy creep.
  - "the nearly-killable creep becomes killable on the next frame: it is attacked". Same world, lower the creep's HP, call `Think()` again, and the action is `AttackUnit(enemyCreep)`.
  - "a bot support leaves the hit to a bot core 800 from the support but within its attack range + buffer of the creep". The filter returns false. The same support with the core 1,400 from the creep and not approaching takes it.

- [ ] **Step 2: Run** `node tests/humaniser/run.js tests/humaniser/test_laning_mode.lua`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - The GetDesire branch condition becomes `if bOwnsThink then`. `bOwnsThink` is defined above GetDesire, so move it there if needed. Upstream's pos 1 / human pos 5 and buggy-hero cases are already inside it.
  - In `LastHitThink`, when `moveToCreep` is set and the creep is within `botAttackRange * 0.8`, issue no attack and no `NoteAttempt`. Set a local `bHoldingForLastHit = true` and return false.
  - In `Think`, after `DenyThink` returns false, if `bHoldingForLastHit` is set, issue `bot:Action_MoveToLocation(bot:GetLocation())` (a hold) and return. Clear the flag at the start of each `Think`.
  - In `CanTakeLastHit` and in the non-filter path, replace `J.IsThereNonSelfCoreNearby(700)` with "some allied bot core (pos 1–3, not self) satisfies `AllyLastHit.CoreCanReach(core, creep)`". Keep a cheap first pass: return early when no allied core is within 1,600 of the bot.

- [ ] **Step 4: Run** the new file plus `npm run check` (`test_lane_regression.lua`'s source checks may need their expected strings updated; update them to the new lines). Expected: PASS.

- [ ] **Step 5: Before/after (in-game).**
  - Run 4 arm-B games against the arm-B baseline.
  - **Accept when:**
    - `lh` at 10:00 rises for pos 1–3 (not noisy);
    - pos 4/5 `lh` falls or stays the same;
    - the analyser's mode churn "blips" (team_roam last-hit visits) fall.
  - Record under "Ally last-hit etiquette (task 04)" → "Results".

- [ ] **Step 6: Commit.** `Laning: owned laning bids for its last hits, holds instead of swinging early, judges core reach from the creep`.

---

### Task 3: Aggro pulls yield to last hits (F6)

**Files:**
- Modify: `bots/mode_laning_generic.lua` `Think()` (pass the last-hit state into `Lane.PreThink`)
- Modify: `typescript/bots/FunLib/humaniser/lane.ts:64-72` (`PreThink` signature), `typescript/bots/FunLib/humaniser/lane_tech.ts:425-511` (`startAggro`, `runAggro`, `PreThink`, `noteStart`)
- Test: `tests/humaniser/test_lane_tech.lua`

**Interfaces:**
- Produces: `Lane.PreThink(bot, allyCreeps, enemyCreeps, enemies, lastHit?: "kill" | "soon")` and `LaneTech.PreThink(... same)`. `"kill"` means a creep is killable now, `"soon"` means `GetBestLastHitCreep` returned a move-to creep, and `undefined` means none.
- Produces: the `lane_tech` telemetry start event gains `lh=0|1` (1 when `lastHit !== undefined` at start). Task 0's `aggroWithLastHit` reads this field.

- [ ] **Step 1: Write failing tests** in `test_lane_tech.lua`, using the existing aggro-pull world:
  - "no aggro draw starts while a creep is killable or about to be". With `lastHit = "kill"` and with `"soon"`, `PreThink` returns false and no `AttackUnit(hero)` is issued.
  - "a walk-back in progress ends early for a killable creep". The sequence is in `walk` at 0.5 s, `PreThink(..., "kill")` returns false, and the sequence is finished.
  - "the tower swap does not hold the frame when a creep is killable". In the `swap` phase, `PreThink(..., "kill")` returns false.
  - "with nothing to last-hit the draw still starts". `lastHit = undefined` behaves as before.

- [ ] **Step 2: Run** `node tests/humaniser/run.js tests/humaniser/test_lane_tech.lua`. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - In `mode_laning_generic.lua` `Think`, compute the last-hit state once: `local hc, mv = GetBestLastHitCreep(nEnemyCreeps, fLastHitFilter)`, giving `lastHit = (J.IsValid(hc) and (mv and 'soon' or 'kill')) or nil`. Pass it to `Lane.PreThink`.
  - `startAggro` returns false when `lastHit !== undefined`, with the overlay `wait: last hit`.
  - `runAggro`'s walk and swap phases call `finish(bot)` and return false when `lastHit === "kill"`.
  - `towerDrop` stays first and is unconditional (safety).

- [ ] **Step 4: Run** the file plus `npm run check`. Expected: PASS.

- [ ] **Step 5: Before/after (in-game).** Run 4 arm-B games. **Accept when** `aggroWithLastHit` is 0 and pos 2 `lh` at 10:00 is not lower. Record under "Lane management: in-lane techniques" → "Results".

- [ ] **Step 6: Commit.** `Lane tech: aggro draws wait for the last hit`.

---

### Task 4: A kill check that sees distance, regen and the damage the bot will take (F7)

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/kill_check.ts` (`KillInputs`, `marginOf`, `Evaluate`, `burstOn`, `compute`)
- Modify: `typescript/bots/FunLib/humaniser/fight_read.ts:333-349` (`LaneCounts`)
- Modify: `typescript/bots/FunLib/humaniser/lane_fight_config.ts` (`DEFAULTS`)
- Test: `tests/humaniser/test_kill_check.lua`, `tests/humaniser/test_fight_read.lua`

**Interfaces:**
- Consumes: `LaneHooks.EnemiesMissing(bot): number` (Task 1).
- Produces: `KillInputs` gains `incoming: number` (damage the bot takes over `BURST_SECONDS`), `botHealth: number`, `botMaxHealth: number`, `minMargin: number`. `FailReason` gains `"survive"`.
- Produces: `FightRead.LaneCounts(bot, snap, radius, near?: Vector)`. With `near`, allies are counted only within `radius` of `near` (alive and in lane); enemies are counted as before.
- Produces: config keys `CreepAggroRadius: 500`, `CoreSoloMargin: 1.2`, `MissingMargin: 1.5`, `SurviveHP: 0.3` (defaults to `StopHP`'s value).

- [ ] **Step 1: Write failing tests** in `test_kill_check.lua`, built on `Evaluate` with plain inputs where possible:
  - "regen counts over the whole burst window". `hp` 300, `regen` 10, `burst` 340, error 0: the margin is `near(340 / 350)` and the check fails with `burst`.
  - "the bot would drop below SurviveHP: fail with survive". `botHealth` 400, `botMaxHealth` 600, `incoming` 300, margin 1.4: `reason === "survive"`.
  - "minMargin 1.2: margin 1.1 fails as burst, 1.25 passes".
  - Through `Check` with stub units:
    - "a contributor beyond attack range is credited for the time left after it arrives". A partner 1,000 from the target with range 150 and speed 300 (2.83 s to arrive) is credited `GetEstimatedDamageToTarget × (5 − 2.83) / 5`.
    - "four enemy lane creeps within 500 of the target add their damage to incoming, and a tower covering the target adds the tower's".
    - "a solo check for a pos 1 uses CoreSoloMargin; for a pos 5 it uses 1.0".
    - "with EnemiesMissing > 0 the minimum margin is MissingMargin".
  - In `test_fight_read.lua`: "LaneCounts with near counts an ally 1,500 from the target as absent and one 600 away as present".

- [ ] **Step 2: Run** both files. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - `marginOf` divides by `max(1, hp + regen * BURST_SECONDS)`.
  - `Evaluate` checks rules in this order: `margin < minMargin` → burst; then escape, tower, outnumbered and counter as now; then `botHealth - incoming < SurviveHP * botMaxHealth` → survive.
  - `burstOn(units, target)` multiplies each unit's estimate by `max(0, BURST_SECONDS - max(0, dist - attackRange) / max(1, moveSpeed)) / BURST_SECONDS`.
  - `compute` builds `incoming` as the sum of three terms:
    - each enemy lane creep in `snap.enemy.units` within `CreepAggroRadius` of the target: `bot.GetActualIncomingDamage(c.GetAttackDamage() * c.GetAttackSpeed() * BURST_SECONDS, DamageType.Physical)`, the formula retreat already uses;
    - the covering tower's damage computed the same way (`towerInRange` returns the tower);
    - `e.unit.GetEstimatedDamageToTarget(true, bot, BURST_SECONDS, DamageType.All)` for each visible enemy hero from `LaneState.Enemies` within `COUNTER_RANGE` of the bot, the target included.
  - `minMargin`:
    - 1 by default;
    - `CoreSoloMargin` when the only contributor is the bot and its `LaneConfig.PositionOf` is 1 or 2;
    - `max(that, MissingMargin)` when `LaneHooks.EnemiesMissing(bot) > 0`.
  - Pass `near = target location` to `LaneCounts`.

- [ ] **Step 4: Run** both files plus `npm run check`. Fix the existing lane-fight tests whose fixtures assumed 2 s regen or no incoming damage: adjust the fixtures, not the assertions' intent. Expected: PASS.

- [ ] **Step 5: Commit.** `Kill check: arrival-scaled burst, full-window regen, incoming damage, local ally count, position and missing-enemy margins`. The in-game comparison runs after Task 5, together with it.

---

### Task 5: Commits end when they stop working, and follow only real ones (F2, F8)

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/lane_fight.ts` (`endReason` ~797-860, `considerKill` ~1080, `FOCUS_MODES` :202, `claim` :499-507)
- Modify: `typescript/bots/FunLib/humaniser/lane_fight_config.ts` (`CommitMax: 5`, `FollowMargin: 1.0`, new `AbandonMargin: 0.8`, `AbandonAfter: 1.0`)
- Test: `tests/humaniser/test_lane_fight.lua`, `tests/humaniser/test_lane_fight_partner.lua`

**Interfaces:**
- Consumes: `LaneState.EnemyTowerTargeting(bot)` (Task 1).
- Produces: new end reasons `margin` and `tower-aggro`, reported on `lanefight_end`. Task 0's metrics count them from `reason`.

- [ ] **Step 1: Write failing tests.**
  - "a commit whose fresh margin stays below 0.8 for over 1 s ends with margin". Start a commit, make `KillCheck.Check` return margin 0.6 for 1.2 s of `RoamDesire` calls, and the phase is idle with end reason `margin`.
  - "a brief dip below 0.8 (0.5 s) does not end it".
  - "a commit ends at 5 s (commit-max)".
  - "while an enemy tower targets the bot, retreat is not capped by the commit". Retreat resolves to its raw value.
  - "the commit caps no attack mode". `Intent.Resolve(bot, BotMode.Attack, 0.9)` is `near(0.9)` during a commit.
  - In the partner file: "a partner's 2-hit trade with our margin 0.9 is not followed". The default `FollowMargin` is 1.0.

- [ ] **Step 2: Run** both files. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - `considerKill` already plans during a commit. Store `s.lastMargin` and track `s.lowMarginSince`: set it when the margin is below `AbandonMargin`, clear it otherwise.
  - In `endReason`, for a commit return `margin` once `now - lowMarginSince > AbandonAfter`.
  - Remove `BotMode.Attack` from `FOCUS_MODES`, with a comment that Valve's attack mode cannot be resolved.
  - In `claim`, release the Retreat focus cap whenever `LaneState.EnemyTowerTargeting(bot)`, and end the phase with `tower-aggro` after `END_GRACE`.
  - Change the config defaults as listed.

- [ ] **Step 4: Run** both files plus `npm run check`. Expected: PASS.

- [ ] **Step 5: Before/after (in-game), Tasks 4 and 5 together.**
  - Run 4 arm-A games.
  - **Accept when:**
    - commits per bot fall;
    - `commitKills / commits` rises;
    - `commitSec` falls ≥ 30%;
    - pos 1–3 `lh` at 10:00 is not lower;
    - kills per game, from `deaths` summed per team, falls by no more than 25%. Bots should still punish real mistakes.
  - Record under "Lane fight (11)" → "Results".

- [ ] **Step 6: Commit.** `Lane fight: abandon failing commits, 5 s cap, follow only passing kills, no attack cap, let tower aggro retreat`.

---

### Task 6: Leaving the lane respects missing enemies, rotations and lane-mates (F9)

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/camp_jobs.ts:328-341` (`StartBlocked`), `:1090` (`schedule`), `:1181` (`scheduleStack`)
- Modify: `typescript/bots/FunLib/humaniser/farm_pattern.ts:255-269` (`StartGate`), `:338-343` (`campOpen`)
- Modify: `typescript/bots/FunLib/humaniser/transitions/rotation.ts:268-305` (`Tick`), `RegisterProbes`
- Modify: `typescript/bots/FunLib/humaniser/lane_hooks.ts` (rotation-decided probe)
- Modify: `typescript/bots/FunLib/humaniser/lane_config.ts` `Thresholds` (`JobMissingFresh: 20`), `transitions/settings.ts` (`RecheckUntilWalk: 4`), `farm_pattern.ts` `Settings` (`MidRuneGuard: 20`)
- Test: `tests/humaniser/test_lane_camp_jobs.lua`, `tests/humaniser/test_farm_pattern.lua`, `tests/humaniser/test_transitions_rotation.lua`

**Interfaces:**
- Consumes: `LaneHooks.EnemiesMissing` (Task 1). Extend it with a freshness argument: `LaneHooks.EnemiesMissing(bot, maxAge?: number)` counts only enemies whose `timeSinceSeen <= maxAge`. Caution's `MissingNow(bot, maxAge?)` gets the same optional argument.
- Produces: `LaneHooks.SetRotationDecidedProbe(fn)` and `LaneHooks.RotationDecided(bot): boolean`, true from the decision until `spawn + RotateLinger` (rotation's `Target(bot) !== undefined`). Kept separate from `IsRotationPlanned`, because camp_jobs registers its own probe into that list.
- Produces: new `StartBlocked` reasons `enemy-missing` and `rotation`; new `StartGate` reasons `enemy-missing`, `covering`, `rune`. All are logged through the existing `lane_take_skip` / `lane_plan` gate fields and the farm "no trip because" counts.

- [ ] **Step 1: Write failing tests.**
  - camp_jobs:
    - "a pull does not start while a lane enemy has been missing 10 s (≤ JobMissingFresh)", giving `StartBlocked === "enemy-missing"`;
    - "one missing 40 s does not block it". The enemy support is at its own camp or back in base, so pulls go on.
    - "no pull or stack is scheduled once a rotation is decided for this bot", giving `rotation`.
  - farm_pattern:
    - "no trip while covering";
    - "no trip while an enemy is freshly missing";
    - "a mid at 5:45 with the power rune at 6:00 does not start a trip (rune)", while the same mid at 6:20 does;
    - "campOpen is false for the lane's pull camp while a lane-mate's camp job is live".
  - rotation: "a decided rotation is called off before its leave time when LaneCanSpare turns false (partner low HP)". The decision has `go=false`, `reason` is the spare reason, and `say_rune_lost` is said for an ally of a human. "After RecheckUntilWalk seconds of walking it is not re-checked."

- [ ] **Step 2: Run** the three files. Expected: FAIL.

- [ ] **Step 3: Implement.**
  - `StartBlocked` gains `EnemiesMissing(bot, Thresholds.JobMissingFresh) > 0` → `enemy-missing`, and `RotationDecided(bot)` → `rotation`. Put them before the `fight` check.
  - `StartGate` gains:
    - `CampJobs.Covering(bot)` → `covering`;
    - the same missing test → `enemy-missing`;
    - for pos 2, `Runes.NextSpawn("power") - now < MidRuneGuard` → `rune`, using the existing `transitions/runes.ts` helper. Add one if it's missing, mirroring `NearestPowerSpot`.
  - `campOpen` excludes `Camps.PullCampsFor(team, lane)` camps while `CampJobs.Active(mate)` is true for a lane-mate. Reuse `LaneRoles.Partner`.
  - In `rotation.Tick`, while `now < d.leaveAt + RecheckUntilWalk`, re-run `Busy.LaneCanSpare(bot, strict)` every `cfg.Refresh`. On false, call it off as the `contested` branch does, with `reason` set to the spare reason.
  - Register the new probe.

- [ ] **Step 4: Run** the three files plus `npm run check`. Expected: PASS.

- [ ] **Step 5: Before/after (in-game).**
  - Run 4 arm-A games.
  - **Accept when:**
    - `pullsStarted` stays within 30% of baseline (Review Focus 2);
    - `rotations` called off as `late` or by camp-job busy reasons fall;
    - no mid `farm_trips` start within 20 s before a power spawn;
    - pos 1 `deaths` at 10:00 is not higher.
  - Record under "Lane management: camp jobs and pulls" → "Results".

- [ ] **Step 6: Commit.** `Camp jobs, farm trips, rotations: respect fresh missing enemies, rotations, lane-mates and the mid's power rune`.

---

### Task 7: Final comparison and docs

**Files:**
- Modify: `docs/HUMANISER_DEV.md` ("Before/after runs" → "Results to date"), `../handoffs/00-README.md` (status line, follow-ups list from "Deferred" above)

- [ ] **Step 1: Run the final arms.** At the branch head, run 4 arm-A and 4 arm-B games. Then run `compare.js --builds <baseline>,<head>` for each arm.
- [ ] **Step 2: Check every task's acceptance line against the final numbers.** Where one regressed after a later task, file it in the results table as a known interaction. Don't tune blind.
- [ ] **Step 3: Write the table and a 3–5 line reading into `HUMANISER_DEV.md`. Update the 00-README status (dd/mm/yyyy) and follow-ups.**
- [ ] **Step 4: Commit.** `Docs: before/after results for the priority fixes`.
