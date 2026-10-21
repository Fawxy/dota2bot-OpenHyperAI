# Last-Hit and Deny Accuracy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Low-skill bots miss and deny less the way low-MMR players do. Skill 1.0 bots behave exactly like upstream.

**Architecture:** A new TS module, `humaniser/last_hit_skill.ts`, wraps the "will this attack kill it" decision. It holds one damage-estimate error ε and one attempt roll per (bot, creep), both kept until that creep is gone. The owned laning `Think()` (`GetBestLastHitCreep`, `GetBestDenyCreep`, `LaneMid.PickDeny`) and team roam's `X.GetLastHitCreep` call it in place of the bare checks. A per-bot `Tick` counts attempts and misses for the overlay.

**Tech Stack:** TypeScript → Lua via TSTL (`npm run build`), hand-written Lua mode files, offline tests in fengari (`tests/humaniser/run.js`).

**Spec:** `../handoffs/10-last-hit-accuracy.md` (repo-relative from the workspace root: `handoffs/10-last-hit-accuracy.md`). Conventions: `handoffs/00-README.md`.

**Worktree:** `oha-h10` on branch `h-10-lasthit`, cut from `humaniser` @ `c73d4c3`. The uncommitted lane/camp edits in `oha` are **not** here; none of them touch the files this plan changes.

## Global Constraints

- New module code goes in `typescript/bots/FunLib/humaniser/last_hit_skill.ts`. Never hand-edit `bots/FunLib/humaniser/*.lua`; run `npm run build`.
- Config key: `Customize.Humaniser.LastHitSkill`, with defaults in `config.ts` `DEFAULTS.LastHitSkill`. Kill switch `LastHitSkill.Enable`.
- With `LastHitSkill.Enable = false`, or with `Humaniser.Enable = false`, every changed call site must evaluate exactly the upstream expression.
- Skill 1.0 must equal upstream (ε = 0, attempt = 1, no ranged preference).
- Error half-width `e = lerp(0.15, 0.02, skill)`. Attempt rate `lerp(0.75, 0.98, skill)`, denies `lerp(0.35, 0.9, skill)`.
- Pressure multiplier ×1.5 on `e` when the bot was damaged by a hero in the last 2 s, or while it is harassing.
- Ranged priority only for `0.6 < skill < 1.0`.
- `LastHitSkill.RequireOwnedLaning` defaults to `true`. Warn once per bot when the feature is on but the bot is on Valve laning.
- Per-bot state is keyed by `GetPlayerID()`. Per-creep state goes in weak-keyed tables keyed by the creep handle (README convention 5), never as fields on the handle.
- No `GetUnitList` scans. Cache per `DotaTime()` where a value is reused within a frame.
- The overlay line is exactly `cs: e=<e> attempts=<n> misses=<n>` (key `"cs"`).

## Decisions made in planning (check these)

1. **Skill 1.0 is a hard bypass.** The spec's lerps give `e = 0.02` and attempt `0.98` at skill 1.0, but it also says skill 1.0 equals upstream. The plan takes `skill >= 1` → upstream path, untouched. The curves apply below 1.0.
2. **Farm mode is not wired.** `mode_farm_generic.lua` never times a last hit; it right-clicks `J.Site.GetFarmLaneTarget` (the nearest or max-HP creep). There is no kill check to wrap. 04's `FilterCreeps` there stays as is.
3. **Ranged preference only for `0.6 < skill < 1.0`.** This preserves "skill 1.0 unchanged". It means a 0.9 bot picks ranged creeps where upstream doesn't; the spec asks for that.
4. **`RequireOwnedLaning = true` gates every path, team roam included.** A bot on Valve laning gets no skill effect anywhere, so its roam grabs aren't sloppier than its (perfect) laning. With `false`, team roam applies the skill even to Valve-laning bots.
5. **"Harassing"** means the bot's current attack target is an enemy hero. That covers both 04's `HarassThink` and 07's `Harass.Think`, with no coupling to either.
6. **Intent arbitration (task 09): no new claims.** Accuracy changes which creep is killable, not mode desires. The one arbitrator risk is team roam's `X.GetLastHitCreep`, which returns a raw **1.5** desire through `Intent.Resolve`. Laning's `GetDesire` returns 0.9 off `GetBestLastHitCreep`. If either decision re-rolled every frame, the desire would flicker and trip 09's thrash limiter. Per-creep cached rolls make `GetDesire` and `Think` agree. Task 1 pins that stability, and Task 4 checks the thrash counter in-game.
7. **Miss** means: the bot attempted a creep (`WillKill` first returned true for it), the creep is now gone, and the bot's `GetLastHits()` (or `GetDenies()` for a deny) didn't rise while that creep was tracked.
8. **Denies keep upstream's predicate shape.** The base is `creep:GetHealth() <= damage * (1 + ε)` with no delay term, matching `GetBestDenyCreep` and `LaneMid.PickDeny`.

## Review Focus

1. **A creep handle that dies and a new creep in its place.** It must get a fresh ε and roll, not inherit stale ones. Covered in Task 1 (`fresh roll for a new handle`).
2. **Two bots on the same creep.** Each bot rolls its own ε and attempt. Covered in Task 1 (`per-bot rolls are independent`).
3. **Called many times per frame.** `GetDesire`, `Think` and the move-to lookahead all ask about the same creep and must agree, or the mode flickers under 09. Covered in Task 1 (`decision stable across calls and frames`).
4. **Feature off means byte-identical behaviour.** Not "close". Covered in Task 1 (`disabled passes the upstream predicate through`) and Task 2/3 source pins.
5. **Pressure ending.** `e` must drop back after the 2 s window or once the hero target is gone. The stored ε for a creep is scaled at use, not baked in at roll time, so this works. Covered in Task 1 (`pressure scales e at use time`).

---

### Task 1: `last_hit_skill.ts` core and config

**Files:**
- Create: `typescript/bots/FunLib/humaniser/last_hit_skill.ts`
- Modify: `typescript/bots/FunLib/humaniser/config.ts` (add `LastHitSkill: { Enable: true } as Record<string, any>` to `DEFAULTS`, and `"LastHitSkill"` to the `IsFeatureEnabled` union)
- Modify: `typescript/bots/FunLib/humaniser/index.ts` (import and export `LastHitSkill`)
- Modify: `bots/FunLib/jmz_func.lua:40-60` (add `J.Humaniser.LastHitSkill.SetHelpers({ WillKillTarget = ..., IsKeyWordUnit = ... })`, next to the existing `SetHelpers` calls)
- Test: `tests/humaniser/test_last_hit_skill.lua`

**Interfaces:**
- Produces:
  - `DEFAULTS = { RequireOwnedLaning: true, ErrorLow: 0.15, ErrorHigh: 0.02, AttemptLow: 0.75, AttemptHigh: 0.98, DenyAttemptLow: 0.35, DenyAttemptHigh: 0.9, PressureMult: 1.5, PressureSeconds: 2, RangedPrioritySkill: 0.6 }`
  - `Settings(): LastHitSkillSettings`, merged shallow over `Config.Get().LastHitSkill`, the same way as `AllyLastHit.Settings`
  - `SetHelpers(h: { WillKillTarget?: (target, dmg, dmgType, delay) => boolean; IsKeyWordUnit?: (word: string, unit) => boolean }): void`
  - `IsActiveFor(bot: Unit): boolean`: the feature is enabled, skill < 1, and (`!RequireOwnedLaning` or the bot is marked owned via `NoteLaningOwner`)
  - `NoteLaningOwner(bot: Unit, owned: boolean): void`: called once at laning-file load. If the feature is enabled, `RequireOwnedLaning` is set, `owned` is false and this bot hasn't been warned, print one `[Humaniser] LastHitSkill: pid=<pid> <hero> is on Valve laning; no effect (set Lane.OwnLaningThink='all')`
  - `ErrorWidth(bot: Unit): number`: the current `e`, pressure included
  - `WillKill(bot: Unit, creep: Unit, attackDamage: number, delay: number, isDeny: boolean): boolean`
  - `Upstream(creep, attackDamage, delay, isDeny): boolean`: the base predicate. Last hit: `WillKillTarget(creep, attackDamage, DAMAGE_TYPE_PHYSICAL, delay)`. Deny: `creep.GetHealth() <= attackDamage`.
- `WillKill` when `!IsActiveFor(bot)` returns `Upstream(...)` with no state touched.
- When active, it looks up or creates this bot's entry for the creep, `{ eps: RandomFloat(-1, 1), attempt: RandomFloat(0,1) < rate, attempted: false, isDeny }`. `eps` is stored unit-scaled and multiplied by `ErrorWidth(bot)` at use. It returns `entry.attempt && Upstream(creep, attackDamage * (1 + eps * ErrorWidth(bot)), delay, isDeny)`. On the first true it sets `entry.attempted = true` and records the bot's `GetLastHits()` / `GetDenies()` for Task 4.

- [ ] **Step 1: Install deps in the worktree**

Run: `npm ci && (cd tests/humaniser && npm ci)`
Expected: both finish without errors.

- [ ] **Step 2: Write the failing tests** in `tests/humaniser/test_last_hit_skill.lua`

Use `FreshHumaniser({ Enable = true, SkillOverride = s, LastHitSkill = { Enable = true, RequireOwnedLaning = false } })`. Stub `WillKillTarget(c, dmg) return dmg >= c.hp` via `SetHelpers`. Drive `RANDOM_FRACTION` to pin rolls.
- `error width per skill`: `ErrorWidth` is 0.15 at skill 0, 0.085 at skill 0.5, and 0.02 + (0.13 × 0.01) at 0.99 (within 1e-6).
- `skill 1.0 is upstream`: with skill 1 and `RANDOM_FRACTION = 0` (the worst roll), `WillKill` equals `Upstream` for hp ∈ {9, 10, 11} at damage 10, last hit and deny.
- `disabled passes the upstream predicate through`: same assertions with `LastHitSkill.Enable = false` at skill 0.
- `eps fixed for the creep's lifetime`: at skill 0 with `RANDOM_FRACTION = 1` (ε = +1, e = 0.15), damage 10, a creep at hp 11 is killable. Change `RANDOM_FRACTION` to 0 and the same creep still answers true across `T` = 100, 100.5, 101.
- `decision stable across calls and frames`: 20 calls on one creep at unchanged hp all return the same value.
- `fresh roll for a new handle`: a new creep table at the same hp after `RANDOM_FRACTION` changes gets the new roll.
- `per-bot rolls are independent`: bot A rolled at fraction 1 and bot B at fraction 0 disagree on hp 11.
- `attempt-rate distribution`: at skill 0, with `RandomFloat` replaced by `math.random` (seeded), over 2000 fresh creeps that are killable upstream, the last-hit try rate is within 0.75 ± 0.04 and the deny rate within 0.35 ± 0.04.
- `pressure scales e at use time`: at skill 0 with `WasRecentlyDamagedByAnyHero(2)` stubbed true, `ErrorWidth` is 0.225. With it false and no hero attack target, `ErrorWidth` is 0.15 again on the next frame.
- `RequireOwnedLaning gates`: with it true and no `NoteLaningOwner(bot, true)`, `WillKill` equals `Upstream` at skill 0. After `NoteLaningOwner(bot, true)` it doesn't. `NoteLaningOwner(bot, false)` prints exactly once across two calls (capture `print`).

- [ ] **Step 3: Run to verify they fail**

Run: `node tests/humaniser/run.js tests/humaniser/test_last_hit_skill.lua`
Expected: FAIL. The module isn't found.

- [ ] **Step 4: Implement `last_hit_skill.ts`, the config entry, the index export and the `jmz_func` helper wiring** per the Interfaces above. Use `lerp(low, high, skill)` with `skill = Profile.Get(bot).skill`. Pressure is `bot.WasRecentlyDamagedByAnyHero(PressureSeconds)` or `bot.GetAttackTarget()` being a hero on another team. Per-bot creep tables are `setmetatable({}, { __mode: "k" })`, keyed by pid.

- [ ] **Step 5: Build and run**

Run: `npm run build && node tests/humaniser/run.js tests/humaniser/test_last_hit_skill.lua && (cd tests/humaniser && npm run check)`
Expected: all PASS. The syntax check passes over `bots/`.

- [ ] **Step 6: Commit**

```bash
git add typescript/bots/FunLib/humaniser/last_hit_skill.ts typescript/bots/FunLib/humaniser/config.ts typescript/bots/FunLib/humaniser/index.ts bots/FunLib/humaniser bots/FunLib/jmz_func.lua tests/humaniser/test_last_hit_skill.lua
git commit -m "Humaniser 10: LastHitSkill core (per-creep error and attempt rolls)"
```

---

### Task 2: Wire owned laning (last hits, denies, ranged priority)

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/last_hit_skill.ts` (add `Choose`)
- Modify: `bots/mode_laning_generic.lua:165-200` (`GetBestLastHitCreep`, `GetBestDenyCreep`), and the load block near line 50 (`NoteLaningOwner`)
- Modify: `typescript/bots/FunLib/humaniser/lane_mid.ts:44` (`PickDeny`)
- Test: `tests/humaniser/test_last_hit_skill.lua` (extend)

**Interfaces:**
- Consumes: `WillKill`, `IsActiveFor`, `NoteLaningOwner`, `Settings` from Task 1.
- Produces: `Choose(bot: Unit, killable: Unit[]): Unit | undefined`. It returns `killable[0]` unless `IsActiveFor(bot)` and `RangedPrioritySkill < skill < 1`, in which case it returns the first ranged or siege creep (`IsKeyWordUnit("ranged")` or `("siege")`), falling back to `killable[0]`.

- [ ] **Step 1: Write the failing tests**
- `Choose keeps upstream order below 0.6 and at 1.0`: given `[melee, ranged]`, it returns melee at skill 0.5 and 1.0.
- `Choose prefers ranged above 0.6`: returns ranged at skill 0.7.
- `laning source pin`: read `bots/mode_laning_generic.lua` via `io.open` (the pattern `test_lane_regression.lua` uses). Assert it contains `LastHitSkill.WillKill(bot, creep, attackDamage, nDelay, false)`, `LastHitSkill.WillKill(bot, creep, attackDamage + dmgDelta, nDelay, false)`, `LastHitSkill.WillKill(bot, creep, attackDamage, 0, true)` and `LastHitSkill.NoteLaningOwner(bot,`.

- [ ] **Step 2: Run to verify they fail**

Run: `node tests/humaniser/run.js tests/humaniser/test_last_hit_skill.lua`
Expected: FAIL on the new checks.

- [ ] **Step 3: Implement**
- In `GetBestLastHitCreep`, replace both `J.WillKillTarget(...)` calls with `LastHitSkill.WillKill(...)`. The move-to lookahead shares the creep's ε and roll. When `LastHitSkill.IsActiveFor(bot)`, collect every killable creep and `return LastHitSkill.Choose(bot, list), false`. Otherwise keep the early return.
- In `GetBestDenyCreep`, swap `creep:GetHealth() <= attackDamage` for `LastHitSkill.WillKill(bot, creep, attackDamage, 0, true)`.
- In `LaneMid.PickDeny`, swap `hp <= damage` for `LastHitSkill.WillKill(bot, creep, damage, 0, true)`.
- After `bTrainerSelfTest` is set, call `LastHitSkill.NoteLaningOwner(bot, <the same condition as the Think() guard at line 285>)`. Hoist that condition into a local `bOwnsThink` and use it in both places.
- The trainer self-test bot stays exact: `IsActiveFor` returns false when `Trainer.IsSelfTestBot(bot)`. Add that check and a test for it.

- [ ] **Step 4: Build and run**

Run: `npm run build && (cd tests/humaniser && npm run check)`
Expected: all PASS, including the existing `test_lane_regression.lua` and `test_ally_last_hit.lua`.

- [ ] **Step 5: Commit**

```bash
git add -A bots typescript tests/humaniser/test_last_hit_skill.lua
git commit -m "Humaniser 10: owned laning last hits and denies go through LastHitSkill"
```

---

### Task 3: Wire team roam's last-hit grab

**Files:**
- Modify: `bots/mode_team_roam_generic.lua:227-228` (`X.GetLastHitCreep`)
- Test: `tests/humaniser/test_last_hit_skill.lua` (extend)

**Interfaces:**
- Consumes: `WillKill` from Task 1.

- [ ] **Step 1: Write the failing test** `team roam source pin`. `mode_team_roam_generic.lua` contains `LastHitSkill.WillKill(bot, creep, bot:GetAttackDamage()-1, nDelay, false)` and no longer contains `J.WillKillTarget(creep, bot:GetAttackDamage()-1`.

- [ ] **Step 2: Run to verify it fails**

Run: `node tests/humaniser/run.js tests/humaniser/test_last_hit_skill.lua`
Expected: FAIL on the pin.

- [ ] **Step 3: Replace the call.** Leave the other `WillKillTarget` sites in this file (`X.GetExceptRangeLastHitCreep`, the illusion helpers) alone; they're out of scope.

- [ ] **Step 4: Run**

Run: `(cd tests/humaniser && npm run check)`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add bots/mode_team_roam_generic.lua tests/humaniser/test_last_hit_skill.lua
git commit -m "Humaniser 10: team roam last-hit grab goes through LastHitSkill"
```

---

### Task 4: Attempt and miss counting, overlay, docs, in-game check

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/last_hit_skill.ts` (add `Tick`, `Counts`)
- Modify: `typescript/bots/FunLib/humaniser/index.ts` (call `LastHitSkill.Tick(bot)` in `tick`, and draw the overlay line in `drawOverlay`)
- Modify: `bots/Customize/general.lua` (a commented `LastHitSkill = { Enable = true, RequireOwnedLaning = true }` block beside the other sub-features)
- Modify: `docs/HUMANISER_DEV.md` (a short LastHitSkill section: config keys, the Valve-laning caveat, how to run the 1v0 test)
- Test: `tests/humaniser/test_last_hit_skill.lua` (extend)

**Interfaces:**
- Consumes: the per-creep entries from Task 1 (`attempted`, `isDeny`, and the recorded counter value).
- Produces:
  - `Tick(bot: Unit): void`. At most every 0.25 s per bot, for each attempted entry whose creep is invalid (`IsNull()` or `!IsAlive()`): count it, and count a miss if the bot's matching counter equals the recorded value; then drop the entry. It also drops un-attempted entries for dead creeps.
  - `Counts(bot: Unit): { attempts: number; misses: number }`
  - Overlay: `HDebug.Text(bot, "cs", string.format("e=%.3f attempts=%d misses=%d", ErrorWidth(bot), attempts, misses))`, only when `IsActiveFor(bot)`. The existing `Text` prefixes the key as `cs: `; confirm that in `debug.ts:69`, and if it doesn't, put `cs: ` in the string.

- [ ] **Step 1: Write the failing tests**
- `attempt counted once per creep`: 10 `WillKill` true calls on one creep, then the creep dies and `GetLastHits` rose → attempts 1, misses 0.
- `miss when another unit took it`: the creep dies with `GetLastHits` unchanged → misses 1.
- `deny miss uses GetDenies`.
- `unattempted dead creeps are not counted`.

- [ ] **Step 2: Run to verify they fail.** Run: `node tests/humaniser/run.js tests/humaniser/test_last_hit_skill.lua`. Expected: FAIL.

- [ ] **Step 3: Implement** `Tick` and `Counts`, the index wiring, the Customize block and the dev doc.

- [ ] **Step 4: Build and run.** Run: `npm run build && (cd tests/humaniser && npm run check)`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A bots typescript docs tests/humaniser/test_last_hit_skill.lua
git commit -m "Humaniser 10: last-hit attempt/miss counts and cs overlay"
```

- [ ] **Step 6: In-game check** (manual, per the handoff). A 1v0 lane, bot alone, 10 minutes, `Lane.OwnLaningThink = 'all'`, `Debug = true`, one run each at `SkillOverride` 0.2, 0.5 and 0.9, plus one at 0.5 with `LastHitSkill.Enable = false`. Record the last hits and denies at 10:00 and the final `cs:` line. Targets: about 35–45 / 50–60 / 70+. The disabled run should land within normal variance of the current branch. During the runs, watch 09's overlay: the thrash counter must not climb from laning ↔ team roam flips. Save the table and the clips for the MR.
