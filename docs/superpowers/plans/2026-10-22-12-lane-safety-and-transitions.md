# 12: Lane safety and laning-phase transitions implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** bots move through the laning phase like a real team. Supports rotate to power runes when their lane can spare them, a core left alone plays safer, bots react to missing enemies and enemy TPs, lost lanes are abandoned instead of fed, and laning ends on game state.

**Architecture:** a new `humaniser/transitions/` package of TypeScript modules.
- Each module has a pure decision core that takes plain input structs, so the offline tests can script it, plus a thin adapter that reads the world.
- It changes behaviour through only three routes:
  - `TRANSITION`-tier intent claims (09)
  - lane-hook probes that 07's modules read
  - a handful of named hooks in the Lua mode files (rune, ward, farm), plus 07's `AdjustPosition` and `HarassThink` chain
- `Transitions.Tick(bot)` runs from `Humaniser.Tick` and refreshes its state every 0.5 s.

**Tech stack:** TypeScript compiled to Lua 5.1 by TSTL (`npm run build`). Hand-written Lua for `general.lua`, `jmz_func.lua`, `localization.lua` and the mode files. Offline tests in fengari (`tests/humaniser/run.js`) on the `lane_world.lua` stubs.

**Spec:** `../handoffs/12-lane-safety-and-phase-transitions.md`. Read it alongside this plan. This plan makes these calls where the spec is open or the codebase differs. Each is marked **Plan call** where it applies.
1. **Rotation route:** a `Rune`-mode floor claim plus a rune-target override in `mode_rune_generic.lua`, not an internal GATHER order. A GATHER would park the support without the rune mode's pickup logic. Rune mode's own power-rune gate (`J.IsCore(bot) or not J.IsThereCoreNearby(1200)`) already gives our mid priority.
2. **No TP for rotations.** Reachability uses walking time only.
3. **Lane swap is out of scope.** OHA has no assigned-lane setter. A lost-lane core goes to the jungle and says `swapping` only if a later task adds lane reassignment. For now it says `going jungle`.
4. **Dependencies not yet merged** (08, 10, 11) are reached through probes or local placeholders:
   - 11's fights and commits: `SetBusyProbe`
   - 11's trade windows: the shared harass tool is suppressed instead
   - 10's expected last-hit rate: a local lerp in settings
   - 08: rotation mistakes are a local skill roll
   Each is marked so the later task can replace it.
5. **Ward anchors are new data.** OHA's ward tables have no per-lane gank path, so settings carry six hand-placed anchor points (team × lane). The lane ward picks the available early-game observer spot nearest the anchor. The anchors are calibrated in game.
6. **The alone-core lane-position offset only applies where OHA owns laning** (`Lane.OwnsLaning`). Valve's C++ laning can't be moved. The claim-based parts apply to every bot.

## Global constraints
- **Worktree:** create `/Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h12` on a new branch `h-12-transitions`, cut from `humaniser`. Commit there only. Never touch `oha`, `oha-h07` or `oha-h09`.
- **TS first.** New code goes in `typescript/bots/FunLib/humaniser/transitions/*.ts` with absolute `bots/...` imports. Commit the regenerated `bots/FunLib/humaniser/**/*.lua` alongside the TS. Hand-edit only these Lua files:
  - `bots/Customize/general.lua`
  - `bots/FunLib/jmz_func.lua`
  - `bots/FunLib/localization.lua`
  - `bots/mode_rune_generic.lua`
  - `bots/mode_ward_generic.lua`
  - `bots/mode_farm_generic.lua`
- **Build:** run `PUPPETEER_SKIP_DOWNLOAD=1 npx --yes yarn@1 install --frozen-lockfile` once, then `npm run build`.
- **Offline checks:** `cd tests/humaniser && npm install && npm run check`. Run one file with `node tests/humaniser/run.js tests/humaniser/<file>.lua`.
- **Kill switch:** `Customize.Humaniser.Transitions.Enable`. Each sub-feature also has its own flag: `MidRunes`, `Rotation`, `Caution`, `Teleports`, `LaneWard`, `Phase`, `LostLane`. With `Enable = false`:
  - every hook returns its upstream value (rune target `nil`, ward pick `nil`, farm gate unchanged, `AdjustPosition` returns `loc`, harass not suppressed)
  - no claims are posted
  - no `GetUnitList`/`GetIncomingTeleports` calls are made
- **Performance:**
  - `Tick` does its scans at most every `Refresh = 0.5` s per bot
  - enemy TPs are read once per team per 0.25 s
  - reuse `LaneState.Enemies` and `LaneState.ForBot`; no new `GetUnitList` scans
- **Perception:** enemy positions come only from `LaneState.Enemies` (visible or `GetHeroLastSeenInfo`). Never read an unseen hero's handle.
- **Chat:** every line goes through `Orders.Say(bot, key, cooldown)`, and only for allies of humans (`Difficulty.IsAllyOfHuman(bot)`). Each new key is added to all four language blocks in `localization.lua` (en, zh, ru, ja), matching the `say_lane_*` entries.
- **Claims:** all claims use `tier: "TRANSITION"` and source `transitions:<feature>`. They're re-posted each `Tick` while they apply, with the default TTL or an explicit `until`.
- **Spec values** (in `transitions/settings.ts` `DEFAULTS`, never as literals):
  - `Refresh 0.5`
  - Busy: `BusyHP 0.5`, `BusyMana 0.3`, `HumanPingWindow 30`
  - Spare:
    - `SpareEq -0.2`
    - `SparePartnerHP 0.6`
    - `SpareCreepAggro 3`
    - `SpareSeenWithin 5`
    - `Pos5PartnerHP 0.75`
    - `Pos5EnemyRadius 1200`
  - Rotation:
    - `DecideFrom 25`, `DecideTo 20` (s before spawn)
    - `ArriveLead 4` (s before spawn)
    - `RotateChance lerp(0.3, 0.9)`
    - `ArriveSigma lerp(6, 1)`
    - `MistakeChance lerp(0.15, 0)`: skips `LaneCanSpare`, but never `IsBusy`
    - `MidSupportRadius 1500`
    - `MidContestDesire 0.55`
    - `ContestRadius 1800`
    - `ContestSeenWithin 5`
    - `Pos5ContestEnemies 2`
    - `ChatCooldown 60`
  - Caution:
    - `AloneMissing 4`, `LaneMissing 6`
    - `OffsetMin 150`, `OffsetMax 300`
    - `RetreatScaleMax 1.3`, `AttackScaleMin 0.7`
    - `SkillAmount lerp(0.5, 1.0)`
    - `MissingCooldown 30`
  - Teleports:
    - `TpRadius 1600`
    - `TpLinger 2`
    - `TpSetupSkill 0.7`
    - `TpSetupDistance 600`
  - Ward: `WardFrom 150`, `WardTo 270`, `WardChance lerp(0.4, 0.95)`
  - Phase:
    - `SupportLevel 6`
    - `SupportFrom 360`, `SupportTo 480`
    - `LostWindow 240`
    - `LostDeaths 2`
    - `LostLHRatio 0.4`
    - `LostLevelGap 2`
    - `ExpectedLHPerMin lerp(3, 7)` (placeholder until 10)
    - `SuggestCooldown 60`

## Review focus
These are inputs the spec implies but doesn't spell out, most likely first. Each one has a pinned test in the task named.
1. **The pos 4 and pos 5 both qualify for the same rune.** Only one goes unless the enemy is likely to contest with 2 or more. Ties go to the pos 4. Task 4, `pos 5 stays when pos 4 is going`.
2. **The rotation decision is re-evaluated every Tick.** That would re-roll the skill chance 10 times per window and almost always rotate. The roll happens once per rune spawn. Task 4, `rotation chance is rolled once per spawn`.
3. **An enemy laner dies.** A dead hero has no last-seen time and must not count as "missing". Task 5, `dead enemy is not missing`.
4. **The bot that is alone is itself a support** (its core died, for example). It still gets caution, but no "alone core" rotation logic runs. Task 5, `alone support gets caution`.
5. **A human partner never pings after a `lane lost, i'll roam?` suggestion.** The bot keeps laning, asks again only after `SuggestCooldown`, and leaves once the human leaves the lane. Task 8, `human partner silence keeps the bot in lane`.

---

### Task 1: Plumbing, settings, kill switch and overlay

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/settings.ts`
- Create: `typescript/bots/FunLib/humaniser/transitions/transitions.ts` (facade)
- Modify:
  - `typescript/bots/FunLib/humaniser/config.ts`: add `Transitions: { Enable: true } as Record<string, any>` to `DEFAULTS`, and `"Transitions"` to the `IsFeatureEnabled` union
  - `typescript/bots/FunLib/humaniser/index.ts`: import, export, call `Transitions.Tick(bot)` after `Lane.Tick`, add `GuardModule("Transitions", …)` fallbacks
  - `bots/Customize/general.lua`: a `Transitions = {...}` block next to `Lane`, listing `Enable` and the seven sub-flags with one-line comments
  - `bots/FunLib/jmz_func.lua`: `J.Humaniser.Transitions.SetHelpers({...})` after the `Lane.SetHelpers` call
- Test: `tests/humaniser/test_transitions_core.lua`

**Interfaces:**
- Produces, in `settings.ts`:
  - `DEFAULTS`, holding the `Enable` flag, the seven sub-flags and every Global Constraints value. Store each lerp pair as `{ Low, High }`.
  - `function Get(): TransitionSettings`, which merges over `Config.Get().Transitions`. Copy `intent.ts`'s `merge`.
  - `function IsActive(): boolean`, true when `Config.IsFeatureEnabled("Transitions")`.
  - `function IsOn(flag: "MidRunes" | "Rotation" | "Caution" | "Teleports" | "LaneWard" | "Phase" | "LostLane"): boolean`
  - `function Lerp(pair: { Low: number; High: number }, skill: number): number`
  - `function ResetSettings(): void`, for tests.
- Produces, in `transitions.ts`:
  - `function SetHelpers(h: { IsInLaningPhase?: () => boolean; WeAreStronger?: (bot: Unit, r: number) => boolean; IsAllyOfHuman?: (bot: Unit) => boolean }): void`
  - `function Tick(bot: Unit): void`. It returns at once unless `IsActive()`.
  - `function Overlay(bot: Unit): string`, which returns `phase: laning|post busy=<bool> spare=<bool> alone=<bool> rot=<target>`. `<target>` is `top`, `bot` or `-`.
  - Later tasks add their module's `Tick` calls and hook exports to this facade.

- [ ] **Step 1: Write the failing tests.**
  - `disabled: Tick touches nothing`: with `Transitions.Enable = false`, `Tick` leaves `GETUNITLIST_CALLS` at 0 and posts no intent claims (`Intent.Explain` shows `raw`).
  - `settings merge keeps defaults`: a partial Customize (`{ Rotation = false }`) gives `IsOn("Rotation") == false` and `Get().Refresh == 0.5`.
  - `overlay format`: on a fresh world before 10:00, `Overlay` matches `^phase: laning busy=%a+ spare=%a+ alone=%a+ rot=%-$`.
- [ ] **Step 2:** Run `node tests/humaniser/run.js tests/humaniser/test_transitions_core.lua`. Expected: FAIL (module not found).
- [ ] **Step 3: Implement the settings, the facade and the wiring.**
  - The overlay line goes through `HDebug.Text(bot, "phase", …)` at the 0.25 s overlay cadence.
  - The guard fallbacks in `index.ts` are each hook's disabled return:
    - `RuneTarget: none`, `PickLaneWard: none`
    - `MidRuneDesire: zero`
    - `FarmAllowedInLaning: no`
    - `SuppressTrades: no`
    - `AdjustPosition: arg2`
    - `Tick: none`
- [ ] **Step 4:** Run `npm run build`, then the test file. Expected: PASS. Then run `npm run check` to confirm the whole suite still passes.
- [ ] **Step 5:** Commit: `Transitions (12): settings, kill switch, overlay, wiring`.

### Task 2: Rune rules table

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/runes.ts`
- Test: `tests/humaniser/test_transitions_runes.lua`

**Interfaces:**
- Produces:
  - `type RuneKind = "power" | "water" | "bounty" | "wisdom"`
  - `const RUNE_RULES: Record<RuneKind, { first: number; every: number; last?: number }>`
  - `function NextSpawn(kind: RuneKind, now: number): number`, the first spawn time ≥ `now`
  - `function PowerSpots(): Vector[]`, giving `GetRuneSpawnLocation(RUNE_POWERUP_1)` and `GetRuneSpawnLocation(RUNE_POWERUP_2)` in that order
  - `function NearestPowerSpot(loc: Vector): LuaMultiReturn<[Vector, "top" | "bot"]>`

- [ ] **Step 1: Check the rules against the live patch.**
  - Fetch `https://www.dota2.com/datafeed/patchnoteslist?language=english`, then every patch since 7.41 for rune changes.
  - Expected current rules, which you must confirm:
    - power every 120 s from 360
    - water at 120 and 240 only (`last: 240`)
    - bounty every 180 s from 0
    - wisdom every 420 s from 420
  - Record the patch version checked in a comment above `RUNE_RULES`.
  - `J.GetNextPowerRuneSpawnTime` returns every 120 s from 120, so it treats water runes as "power". Rotations use `RUNE_RULES.power`, not that helper.
- [ ] **Step 2: Write the failing tests.**
  - `NextSpawn("power", 300) == 360`
  - `NextSpawn("power", 360) == 360`
  - `NextSpawn("power", 361) == 480`
  - `NextSpawn("water", 250)` is `math.huge` (no more water runes)
  - `NextSpawn("bounty", 181) == 360`
  - `NearestPowerSpot` returns `"top"` for a point by the top spot
- [ ] **Step 3:** Run the tests. Expected: FAIL.
- [ ] **Step 4:** Implement `runes.ts`.
- [ ] **Step 5:** Run the tests. Expected: PASS.
- [ ] **Step 6:** Commit: `Transitions (12): rune rules table, checked against patch <ver>`.

### Task 3: `IsBusy` and `LaneCanSpare`

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/busy.ts`
- Modify: `typescript/bots/FunLib/humaniser/pings.ts`. In `Scan`, record each human ping as `{ pid, time, location }` in a per-team list pruned to `Pings.Get().MaxPingAge`, keeping at least 30 s. Export `function HumanPingNear(team: number, loc: Vector, radius: number, within: number): boolean`.
- Modify: `typescript/bots/FunLib/humaniser/lane_hooks.ts`. Add `SetBusyProbe(fn)` and `IsBusyByProbe(bot): boolean` on the rotation-probe pattern. 11 registers kill-setup commits here later. **Plan call 4.**
- Test: `tests/humaniser/test_transitions_busy.lua`

**Interfaces:**
- Produces:
  - `interface BusyInput { order: boolean; campJob: boolean; fighting: boolean; retreating: boolean; hp: number; mana: number; dead: boolean; respawnAfter?: number; windowEnd: number; carrying: boolean; humanPingOnLane: boolean }`
  - `function IsBusyPure(i: BusyInput): LuaMultiReturn<[boolean, string]>`. The reason string is one of `order`, `job`, `fight`, `retreat`, `hp`, `mana`, `dead`, `item` or `ping`. "Due to respawn later than the window" counts as `dead`.
  - `interface SpareInput { eqPos: number; plan: LanePlan.LanePlan; coreHealthy: boolean; partnerHP: number; partnerCreepAggro: number; enemies: { visible: boolean; sinceSeen: number; inKillPosition: boolean }[]; enemyTpIncoming: boolean; humanAskedStay: boolean; strict: boolean; enemyNearPartner: boolean }`
  - `function LaneCanSparePure(i: SpareInput): LuaMultiReturn<[boolean, string]>`. With `strict` set, it uses `Pos5PartnerHP` and requires `!enemyNearPartner`.
  - `function IsBusy(bot: Unit, windowEnd: number): LuaMultiReturn<[boolean, string]>`. This adapter fills the input:
    - `order`: `Orders.GetFor(bot) !== undefined`
    - `campJob`: `CampJobs.Active` or `UpcomingWithin(bot, 30)`
    - `fighting`: active mode is Attack, Roam, TeamRoam or Defend, or `LaneHooks.IsBusyByProbe`
    - `retreating`: active mode is Retreat
    - `carrying`: false (placeholder until 13)
    - `humanPingOnLane`: `HumanPingNear(team, laneFront, 2000, HumanPingWindow)`
  - `function LaneCanSpare(bot: Unit, strict: boolean): LuaMultiReturn<[boolean, string]>`. This adapter reads:
    - the partner from `LaneRoles.Partner` and `ReadPartner`
    - enemies from `LaneState.Enemies`
    - an enemy is in kill position when it's within its attack range + 300 of the partner while the partner is below 50% HP
    - `humanAskedStay`: a `LANE_NOPULL` or `LANE_HANDSOFF` order accepted for the lane, or a human ping on the lane within `HumanPingWindow`
    - `enemyTpIncoming`: from `function SetTpProbe(fn: (this: void, bot: Unit) => boolean): void` in `busy.ts`. Task 6 registers it; until then it's false.
  - A solo lane (no partner) is never "spare".

- [ ] **Step 1: Write the failing truth-table tests.** Each row flips one input from an all-clear base, so a test can't pass by default:
  - `IsBusyPure` returns false/"" on the all-clear base, then true with the matching reason for each of the 9 conditions.
  - `LaneCanSparePure`:
    - true on the clear base
    - false for `eqPos -0.3` with plan `HOLD`
    - true for `eqPos -0.3` with plan `FREEZE` and a healthy core
    - false for partner HP 0.55
    - false for 3 creeps aggroed on the partner
    - false when an enemy was last seen 6 s ago
    - false when an enemy is in kill position
    - false with a TP incoming
    - false when a human asked the support to stay
  - `strict`: false for partner HP 0.7, and false with an enemy near the partner.
  - Adapter test `solo lane is never spare`, in `lane_world` with no partner.
  - Adapter test `human ping on the lane makes the bot busy`, a ping 10 s ago at the lane front.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `busy.ts`, the `pings.ts` record and the `lane_hooks.ts` probe.
- [ ] **Step 4:** Run the tests. Expected: PASS. Also run `test_pings.lua` to confirm it still passes.
- [ ] **Step 5:** Commit: `Transitions (12): IsBusy and LaneCanSpare`.

### Task 3b: Our mid actually takes power runes

**Why:** in playtests, mid bots often leave power runes alone. Rotations (Task 4) assume our mid takes the rune, so this has to work first. Use superpowers:systematic-debugging: **state the root cause and show it in a failing test before changing behaviour.**

Two hypotheses, read from `bots/mode_rune_generic.lua`. Both are unconfirmed.
1. **A bounty rune shadows the power rune.** `X.GetBestRune` (:492) returns the nearest rune of all four that passes its gates, bounties included. Bounties also spawn at 6:00, 9:00 and so on. If the nearest is a bounty, the bounty branch (:170-193) returns NONE during laning unless the bot is within 500, so the power rune is never scored.
2. **The desire is too weak without a bottle.** A mid without a bottle in the early game gets `MODERATE` (0.5 in the stubs) scaled down to as low as half by distance (`X.GetScaledDesire`, :649). Before the spawn it only gets that inside 1,600 units, and only in the last 7 s (`PowerRuneDesire`, :233). That loses to laning's desire, plus the active mode's stickiness bonus.

**Files:**
- Modify: `bots/mode_rune_generic.lua`, the smallest change that fixes the confirmed cause, behind `J.Humaniser.Transitions.MidRunesOn(bot)`. That hook is true when `IsActive() && IsOn("MidRunes")` and the bot is pos 2.
  - If hypothesis 1 is confirmed: for a pos 2 bot, `X.GetBestRune` considers only power-rune spots while a power rune is due within 20 s or is up.
  - If hypothesis 2 is confirmed: from 15 s before a power spawn until the rune is taken, a pos 2 bot within 3,500 posts a `TRANSITION` claim on `BotMode.Rune` with `floor: MidRuneFloor`. Add `MidRuneFloor 0.6` to settings.
  - If something else is the cause: fix that instead, and record it in the task report.
- Modify: `typescript/bots/FunLib/humaniser/transitions/transitions.ts`. Export `MidRunesOn`, with a guard fallback of `no`.
- Modify: `bots/mode_rune_generic.lua`. When telemetry is enabled and a pos 2 bot's rune desire is below 0.3 within 10 s of a power spawn, emit `Telemetry.Event("rune_skip", …)` with these fields:
  - `pid`
  - `target`, which `GetBestRune` returned
  - `status`
  - `raw`, the rune desire
  - `laning`, the laning desire sample (`Intent.Competing`)
  - `gate`, the first early return hit
  At most one event per spawn per bot.
- Test: `tests/humaniser/test_lane_rune_mode.lua`. Extend its stub world.

- [ ] **Step 1: Reproduce.** Add tests to `test_lane_rune_mode.lua`. Both should FAIL on current code if their hypothesis holds:
  - `mid picks the power rune over a nearer bounty at 6:00`: a pos 2 bot sits 900 from a bounty spot and 1,400 from a power spot, `T = 357`, the bounty is UNKNOWN and the power rune is MISSING. `GetBestRune` must return the power rune, and the desire must be above 0.
  - `bottle-less mid wants the rune over laning`: a pos 2 bot with no bottle, 1,800 from the spot, at `T = 357`. The rune desire must reach at least 0.6.
- [ ] **Step 2:** Run `node tests/humaniser/run.js tests/humaniser/test_lane_rune_mode.lua`. Record which tests fail. That's the confirmed cause. If neither fails, write a test for the cause you find instead, and don't change behaviour without one.
- [ ] **Step 3:** Implement the fix for the confirmed cause only, plus the `rune_skip` telemetry.
- [ ] **Step 4:** Run the tests. Expected: PASS. Add `MidRunes flag off keeps upstream`: with `MidRunes = false`, `GetBestRune` and the desire match current behaviour for the same worlds.
- [ ] **Step 5:** Add in-game check 10 to the Task 9 list: watch the 6:00 and 8:00 runes with a bot mid, with and without a bottle, and read any `rune_skip` lines.
- [ ] **Step 6:** Commit: `Transitions (12): our mid takes power runes (<cause>)`.

### Task 4: Support rune rotations

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/rotation.ts`
- No edit to `lane_mid.ts`. `rotation.ts` registers the support's rotation with the existing `LaneHooks.SetRotationProbe`, so 07's lane plan sees `rotating`.
- Modify: `bots/mode_rune_generic.lua`
  - In `X.GetBestRune`, before the nearest-rune loop, add `local hForced = J.Humaniser.Transitions.RuneTarget(bot); if hForced then return hForced, <its location> end`. Use the rune id/table shape that `GetBestRune` already returns.
  - At :197, extend the power-rune `math.max(...)` with `J.Humaniser.Transitions.MidRuneDesire(bot)`.
- Modify: `bots/FunLib/localization.lua`. Add `say_rune_coming_mid` (`coming mid for rune`) and `say_rune_lost` (`rune lost`) to every language block.
- Test: `tests/humaniser/test_transitions_rotation.lua`

**Interfaces:**
- Consumes: `Busy.IsBusy`, `Busy.LaneCanSpare` (Task 3), and `Runes.NextSpawn` / `NearestPowerSpot` (Task 2).
- Produces:
  - `interface RotationDecision { spawn: number; go: boolean; spot?: Vector; side?: "top" | "bot"; leaveAt?: number; reason: string }`
  - `function Decide(bot: Unit, now: number): RotationDecision`. It's computed once per `(pid, spawn)` inside `[spawn - DecideFrom, spawn - DecideTo]`, then cached. The skill roll and the jitter sample are drawn once.
  - `function Active(bot: Unit): RotationDecision | undefined`. Returns the cached decision when `go` is true and `now` is in `[leaveAt, spawn + 5]`, else undefined.
  - `function RuneTarget(bot: Unit): any | undefined`, the hook. It returns the rune handle or id for `Active(bot).side`.
  - `function MidRuneDesire(bot: Unit): number`, the hook. It returns `MidContestDesire` when the bot is our pos 2, a support with `Active` is within `MidSupportRadius` of it or of the spot, and `now` is in `[spawn - 10, spawn + 5]`. Otherwise 0.
  - `function Target(bot: Unit): "top" | "bot" | undefined`, for the overlay.
- Rules for `Decide`:
  - Only for `LaneConfig.PositionOf(bot)` 4 or 5, `spawn >= RUNE_RULES.power.first`, and `IsOn("Rotation")`.
  - `travel = dist(bot, spot) * 1.2 / bot.GetCurrentMovementSpeed()`.
  - `leaveAt = spawn - ArriveLead - travel + Gauss() * Lerp(ArriveSigma, skill)`. It doesn't go if `leaveAt < now - 2`, because it can no longer make it.
  - Pos 4 goes when `!IsBusy && LaneCanSpare(strict=false)` and the skill roll passes.
  - Pos 5 goes when `!IsBusy && LaneCanSpare(strict=true)` and the skill roll passes, and:
    - either the pos 4 isn't going, or the enemies seen near the spot within `ContestSeenWithin` number at least `Pos5ContestEnemies`
    - and the pos 5 is at least as close to the spot as the pos 4, or the pos 4 is busy
  - Read the pos 4's decision from the shared cache, keyed by its pid. Decide the pos 4 first by calling `Decide` for it.
  - Mistake: with chance `Lerp(MistakeChance, skill)`, `LaneCanSpare` is treated as true. The reason becomes `mistake`. **Plan call 4.**
- While `Active`:
  - post a claim `{ source: "transitions:rotate", tier: "TRANSITION", mode: BotMode.Rune, floor: 0.7 }`
  - and `Intent.Hold` while the bot stands at the spot before the spawn
- Contest check, from 6 s before arrival:
  - count enemies seen within `ContestSeenWithin` inside `ContestRadius` of the spot
  - compare with our heroes there or arriving: the support, plus our mid if within 2,500
  - if they outnumber us: cancel the decision, release the claim, and `Say("say_rune_lost", ChatCooldown)`
- On going: `Say("say_rune_coming_mid", ChatCooldown)` once per spawn.

- [ ] **Step 1: Write the failing tests** in `lane_world`, a Radiant team with pos 2, 4 and 5 bots, at `T = 335` for the 6:00 rune:
  - `pos 4 rotates when idle and lane stable`: skill 0.9, roll 0.0, so `go == true` and `leaveAt` is between 335 and 356.
  - `pos 4 skips when busy`: at 40% HP, `go == false` with reason `hp`.
  - `rotation chance is rolled once per spawn`: with the random sequence `{0.95}` then `{0.0}`, ten `Decide` calls across the window all return `go == false`.
  - `pos 5 stays when pos 4 is going`: both eligible, so the pos 5 gets `go == false`. With 2 enemies seen near the spot, the pos 5 goes too.
  - `pos 5 rotates when pos 4 is busy`: the pos 4 is in a camp job, the carry is healthy with no enemy within 1,200, so the pos 5 goes. With an enemy 1,000 from the carry, it stays.
  - `no rotation before 6:00`: `T = 215` (water rune at 4:00) gives `go == false`.
  - `contest aborts when outnumbered`: 3 enemies seen near the spot gives `Active == undefined` after Tick, plus one `say_rune_lost` announce.
  - `mid gets the contest floor with support near`: with the support `Active` 1,000 from the mid at `T = 355`, `MidRuneDesire(mid) == 0.55`; with the support 2,000 away it's 0.
  - `low skill sometimes leaves late`: skill 0 with `Gauss()` stubbed to +2σ puts `leaveAt` more than 8 s after the skill-1 value.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `rotation.ts`, the Lua hooks and the localization keys. Register `LaneHooks.SetRotationProbe(bot => Active(bot) !== undefined)` at load.
- [ ] **Step 4:** Run the tests. Expected: PASS. Run `test_lane_rune_mode.lua` and `test_lane_mid.lua` to confirm they still pass.
- [ ] **Step 5:** Commit: `Transitions (12): support power-rune rotations`.

### Task 5: Caution (alone core and missing enemies)

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/caution.ts`
- Modify: `typescript/bots/FunLib/humaniser/lane_hooks.ts`. Add `SetCautionProbe(fn)` and `IsCautious(bot): boolean`.
- Modify: `typescript/bots/FunLib/humaniser/lane_plan.ts`
  - add `cautious: boolean` to `CorePlanInput`
  - in `PickCorePlan`, when `cautious`, never return `SHOVE`: the rotating and empty-lane branches fall through to `FREEZE`/`HOLD`
  - fill the input from `LaneHooks.IsCautious(picker)` in `pickFor`, beside `rotating`
- Modify: `typescript/bots/FunLib/humaniser/lane.ts`
  - in `AdjustPosition`, call `LaneHooks.PositionOverride(bot, loc)` first and return its result if it differs from `loc`
  - in `HarassThink`, return false when `LaneHooks.TradesSuppressed(bot)`
  - add these to `lane_hooks.ts`, to avoid a require cycle: `SetPositionProbe(fn)` / `PositionOverride(bot, loc): Vector`, which returns `loc` when there's no probe, and `SetTradeProbe(fn)` / `TradesSuppressed(bot): boolean`. `caution.ts` registers `AdjustPosition` and `SuppressTrades` at load.
- Modify: `bots/FunLib/localization.lua`. Add `say_ss_top`, `say_ss_mid` and `say_ss_bot` (`ss top`, …).
- Test: `tests/humaniser/test_transitions_caution.lua`

**Interfaces:**
- Produces:
  - `interface CautionInput { alone: boolean; laneEnemies: number; missing: number; skill: number }`
  - `function CautionLevel(i: CautionInput): number`. This is the algorithm:
    ```
    base = missing > 0 ? 1 : (alone ? min(1, 0.5 + 0.25 * max(0, laneEnemies - 1)) : 0)
    return base * Lerp(SkillAmount, skill)
    ```
  - `function IsAlone(bot: Unit, s: LaneSnapshot): boolean`. True when the bot is in a two-hero lane and the partner is dead, has `distToFront > CoreAbsentDist`, is `Rotation.Active`, or is in `CampJobs.Active`. Also true when the bot is solo against 2 or more enemy laners (`LanePlan.EnemyLaners >= 2`).
  - `function Missing(bot: Unit, s: LaneSnapshot, alone: boolean): number`. The count of enemy lane opponents that are alive (`IsHeroAlive`) and unseen for more than `alone ? AloneMissing : LaneMissing`.
  - `function Level(bot: Unit): number`. The level currently applied. It moves to a new target only after `Profile.SampleDelay(bot, "notice")` has elapsed since the target changed.
  - `function AdjustPosition(bot: Unit, loc: Vector): Vector`. When `Level > 0` and `Lane.OwnsLaning(bot)`, it moves `loc` toward our lane tower by `OffsetMin + (OffsetMax - OffsetMin) * level`. Otherwise it returns `loc` itself. **Plan call 6.**
  - `function SuppressTrades(bot: Unit): boolean`. True when `Level >= 0.5` and not `WeAreStronger(bot, 1200)`.
- Claims while `Level > 0`:
  - `{ source: "transitions:caution", tier: "TRANSITION", mode: BotMode.Retreat, scale: 1 + (RetreatScaleMax - 1) * level }`
  - the same source on `BotMode.Attack`, with `scale: 1 - (1 - AttackScaleMin) * level`
- Missing callout:
  - allies of humans only
  - one per team per lane per missing episode, with `MissingCooldown`
  - skipped for mid when `Counter.Signals(bot)` already has a `mid_missing` from the last 30 s

- [ ] **Step 1: Write the failing tests:**
  - `CautionLevel`:
    - alone vs 1 enemy at skill 1 gives 0.5
    - alone vs 3 gives 1.0
    - missing at skill 0 gives 0.5
    - not alone and nobody missing gives 0
  - `support leaving makes the core alone`: the partner pos 5 is `Rotation.Active`, so `IsAlone(core)` is true.
  - `dead enemy is not missing`: an enemy laner dead for 10 s gives `Missing == 0`.
  - `missing waits for the threshold`: unseen 5 s with the core not alone gives 0; unseen 7 s gives 1.
  - `alone support gets caution`: the core is dead and the support remains, so `Level(support) > 0` after the notice delay.
  - `notice delay holds the old level`: `SampleDelay` stubbed to 1.0, so Level is 0 at +0.5 s and >0 at +1.1 s.
  - `cautious core never shoves`: `PickCorePlan({ rotating = true, cautious = true, ... })` doesn't return `SHOVE`. With `cautious = false` it does.
  - `position offset only where OHA owns laning`: `AdjustPosition` returns `loc` unchanged for a bot that `OwnsLaning` is false for.
  - `trades suppressed unless stronger`: Level 0.6 with `WeAreStronger` false gives true; with it true, false.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `caution.ts` and the 07 hook edits.
- [ ] **Step 4:** Run the tests. Expected: PASS. Run `test_lane_plan.lua`, `test_lane_harass.lua` and `test_lane_regression.lua` to confirm they still pass.
- [ ] **Step 5:** Commit: `Transitions (12): caution for alone cores and missing enemies`.

### Task 6: Incoming enemy TPs

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/teleports.ts`
- Test: `tests/humaniser/test_transitions_teleports.lua`

**Interfaces:**
- Produces:
  - `interface EnemyTp { pid: number; location: Vector; remaining: number; seenAt: number }`
  - `function EnemyTps(team: number): EnemyTp[]`. Cached per team for 0.25 s, from `GetIncomingTeleports()` entries whose `playerid` is on the enemy team.
  - `function IncomingToLane(bot: Unit, s: LaneSnapshot): EnemyTp | undefined`. A TP whose destination is within `TpRadius` of our lane T1 tower or of `s.frontLoc`.
  - `function Response(bot: Unit, tp: EnemyTp): "back" | "setup"`. Returns `setup` when skill > `TpSetupSkill` and `WeAreStronger(bot, 1600)`, else `back`.
- Behaviour:
  - Registered into `Busy`'s `enemyTpIncoming` probe from Task 3.
  - After `SampleDelay(bot, "notice")`:
    - `back` sets the caution level to 1 until `seenAt + remaining + TpLinger`, through `caution.ts`. Add `function ForceLevel(bot, level, until)` there.
    - `setup` makes `AdjustPosition` return a point `TpSetupDistance` from the TP spot, toward our tower, for the same window, and posts no retreat scale.
- Log each TP seen with `HDebug.Log("transitions", "tp pid=… to=… remaining=…")`. In-game check 4 confirms whether fogged destinations appear.

- [ ] **Step 1: Write the failing tests.** Stub `GetIncomingTeleports` in the test file:
  - `ally TPs are ignored`
  - `TP to our T1 is incoming to lane`, and a TP 3,000 away isn't
  - `low skill backs off`: skill 0.5 gives `back`, and the caution level is 1 after the notice delay
  - `high skill and stronger sets up`: skill 0.9 with `WeAreStronger` true gives `setup`, and `AdjustPosition` is within 50 of the expected point
  - `reaction ends after the TP lands`: the level is back to 0 after `remaining + TpLinger + 0.5`
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `teleports.ts` and `Caution.ForceLevel`.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `Transitions (12): react to enemy TPs into the lane`.

### Task 7: Early lane ward

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/lane_ward.ts`
- Modify: `bots/mode_ward_generic.lua` `GetDesireHelper`. After the available observer spots are gathered, add `local vLane = J.Humaniser.Transitions.PickLaneWard(bot, <spots list>)`. If it returns a spot, use it as the target instead of the closest one.
- Test: `tests/humaniser/test_transitions_ward.lua`

**Interfaces:**
- Produces:
  - `const GANK_ANCHORS: Record<number, Record<Lane, Vector>>`, per team and lane. These are first-pass coordinates: the river or jungle entrance an enemy walks through to gank that lane. A comment marks them for in-game calibration. **Plan call 5.**
  - `function PickLaneWard(bot: Unit, spots: { location: Vector }[]): { location: Vector } | undefined`. It returns the spot nearest `GANK_ANCHORS[team][lane]` when all of these hold:
    - `IsOn("LaneWard")`
    - `DotaTime()` is in `[WardFrom, WardTo]`
    - the bot is its lane's support: pos 4 in the offlane, pos 5 in the safelane, or the lowest position present if the other is absent
    - no allied observer is within 1,600 of the anchor (`GetUnitList(UnitType.AlliedWards)`, scanned once per 5 s per team)
    - the skill roll `Lerp(WardChance, skill)` passes, drawn once per lane per game
  - Otherwise it returns undefined.
- While a pick is live, post `{ source: "transitions:ward", tier: "TRANSITION", mode: BotMode.Ward, floor: 0.6 }`.

- [ ] **Step 1: Write the failing tests:**
  - `picks the spot nearest the anchor`: 3 spots in, and the nearest one to the bot lane's anchor comes out.
  - `outside the window: no pick`: at 2:00 and at 4:40.
  - `existing observer covers the lane`: an allied observer 1,000 from the anchor gives no pick.
  - `only the lane support`: the pos 4 asked about the bot lane gives no pick.
  - `roll is once per lane`: a failed roll stays failed for the rest of the window.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `lane_ward.ts` and the ward-mode hook.
- [ ] **Step 4:** Run the tests. Expected: PASS.
- [ ] **Step 5:** Commit: `Transitions (12): early lane ward on the gank path`.

### Task 8: Laning end per bot, lost-lane detection and response

**Files:**
- Create: `typescript/bots/FunLib/humaniser/transitions/phase.ts`
- Modify: `bots/mode_farm_generic.lua:135`. Change the laning early exit to `if J.IsInLaningPhase() and not J.Humaniser.Transitions.FarmAllowedInLaning(bot) then`.
- Modify: `bots/FunLib/localization.lua`. Add `say_lane_lost_roam` (`lane lost, i'll roam?`) and `say_going_jungle` (`going jungle`). **Plan call 3.**
- Test: `tests/humaniser/test_transitions_phase.lua`

**Interfaces:**
- Produces:
  - `interface LaneRecord { deaths: number[]; lastHits: { at: number; total: number }[]; }`. Kept per pid. `Tick` samples deaths (an alive→dead edge while `IsLaningFor`) and `GetLastHits()`.
  - `function IsLaningFor(bot: Unit): boolean`. False when any of these hold:
    - our or their T1 in the bot's lane is dead (`GetTower(team, TOWER_*_1)`)
    - the bot is a support with level > `SupportLevel` and `now` in `[SupportFrom, SupportTo]`, holding a smoke (`Commands.HasSmoke`) or having an accepted ATTACK/SMOKE order
    - the bot is a core with a farm item and a safe jungle. "Farm item" means any item listed in `FARM_ITEMS` in this file: `item_maelstrom`, `item_battle_fury`, `item_radiance`, `item_hand_of_midas`, `item_mjollnir`. "Safe jungle" means no enemy hero seen within 3 s inside 2,500 of our nearest jungle camp.
    - the `IsInLaningPhase` helper is false
  - `interface LostInput { deathsInWindow: number; lhPerMin: number; expectedLhPerMin: number; levelGap: number }`
  - `function LaneLostPure(i: LostInput): LuaMultiReturn<[boolean, string]>`. The reason string is `deaths`, `lasthits` or `levels`.
  - `function LaneLost(bot: Unit): LuaMultiReturn<[boolean, string]>`. This adapter takes `levelGap` as the highest seen lane opponent's level minus ours, using visible or last-known level only.
  - `function FarmAllowedInLaning(bot: Unit): boolean`, the farm hook. True for a core when `IsOn("Phase") && !IsLaningFor(bot)`, or when `IsOn("LostLane") && LaneLost(bot)` and the partner isn't a human waiting.
- Response:
  - **Core:** returns `FarmAllowedInLaning` true and caps `BotMode.Laning` at 0.3 (`TRANSITION`), plus `Say("say_going_jungle")`.
  - **Support:** caps Laning at 0.3 and lets OHA's roam, ward and farm modes win. It doesn't start camp jobs itself.
  - **Human partner:** `Say("say_lane_lost_roam", SuggestCooldown)` and no cap. The cap starts only when one of these happens after the suggestion:
    - the human pings within 1,500 of the bot (`Pings.HumanPingNear`)
    - the bot accepts any order
    - the human has `distToFront > CoreAbsentDist` for 10 s
- The facade's `Overlay` uses `IsLaningFor` for `laning|post`.

- [ ] **Step 1: Write the failing tests:**
  - `IsLaningFor`:
    - our T1 dead gives false
    - a pos 5 at level 7 at 7:00 with smoke gives false; at level 5 it's true
    - a pos 1 with Maelstrom and a clear jungle gives false; with an enemy seen near the camp 2 s ago it's true
    - after the helper turns false it's false
  - `LaneLostPure`:
    - 2 deaths gives `deaths`
    - 1 death gives false
    - LH ratio 0.35 gives `lasthits`, 0.45 gives false
    - level gap 2 gives `levels`
  - `deaths older than the window are dropped`: deaths at 0:30 and 1:00 give false at 5:10.
  - `lost core may farm in laning`: `FarmAllowedInLaning` is true and the Laning cap is posted.
  - `human partner silence keeps the bot in lane`: a support with a human core gets one `say_lane_lost_roam`, no cap after 30 s, a second suggestion only after 60 s, and the cap once the human's `distToFront` stays above the threshold for 10 s.
- [ ] **Step 2:** Run the tests. Expected: FAIL.
- [ ] **Step 3:** Implement `phase.ts` and the farm hook.
- [ ] **Step 4:** Run the tests. Expected: PASS. Run `npm run check` to confirm the whole suite still passes.
- [ ] **Step 5:** Commit: `Transitions (12): per-bot laning end and lost-lane response`.

### Task 9: Docs, in-game checklist and regression pin

**Files:**
- Modify: `docs/HUMANISER_DEV.md`. Add a "Transitions (12)" section covering:
  - the module map
  - each hook and its file:line
  - the plan calls
  - the placeholders for 08, 10, 11 and 13
- Modify: `docs/HUMANISER_TEST_PLAN.md`. Add the spec's 7 in-game scenarios as a checklist, plus:
  - 8: `GetIncomingTeleports` shows an enemy TP to a fogged tower
  - 9: walk to each `GANK_ANCHORS` point and adjust it
- Modify: `bots/Customize/general.lua` comments, if any flag's wording changed.
- Test: `tests/humaniser/test_transitions_core.lua`. Add `disabled: every hook returns upstream`. With `Enable = false`:
  - `RuneTarget` is nil
  - `MidRuneDesire` is 0
  - `PickLaneWard` is nil
  - `FarmAllowedInLaning` is false
  - `AdjustPosition` returns the same table
  - `SuppressTrades` is false
  - `GETUNITLIST_CALLS` is 0

- [ ] **Step 1:** Write the regression test. Run it. It should pass already, since the earlier tasks guard every hook. If it fails, fix the hook that leaks.
- [ ] **Step 2:** Write the docs.
- [ ] **Step 3:** Run `npm run build && cd tests/humaniser && npm run check`. Expected: all suites PASS.
- [ ] **Step 4:** Commit: `Transitions (12): docs, in-game checklist, disabled-path regression test`.
