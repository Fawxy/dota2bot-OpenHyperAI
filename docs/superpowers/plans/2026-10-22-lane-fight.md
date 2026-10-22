# Lane Fight (task 11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In lane, bots trade hits and go for kills the way people do, with imperfect memory of the spells they've seen cast, and the quality scales with skill.

**Architecture:** There are three layers. The first is a per-observer cooldown memory, fed by watching visible enemy casts. The second is a per-bot "fight read" that finds trade windows, respect windows and kill chances. The third is an executor that runs trades and kills through OHA's Lua `team_roam` mode, using `FIGHT`-tier intent claims. `team_roam` is used because it is the only Lua mode that every bot runs (enemy team included) and that makes OHA's per-hero spell logic fire: `J.IsGoingOnSomeone` counts it, but not laning. Lane partners coordinate by watching each other's visible behaviour, the same path used for a human partner. They don't use the orders bus, so this works whether or not modules are shared.

**Tech Stack:** TypeScript → Lua via TSTL (`npm run build`), hand-written Lua for the mode files, and offline tests in fengari (`tests/humaniser`).

**Spec:** `../handoffs/11-lane-trading-and-kill-setups.md` (outside the repo, next to the `oha*` checkouts). "Design decisions" below lists where this plan departs from it and why.

**Worktree:** `/Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h11`, branch `h-11-lanefight`, cut from `humaniser` @ `c73d4c3` (07 and 09 are both merged there). `node_modules` is a symlink to `../oha/node_modules` (no yarn on this machine; `npm install` fails on a peer conflict, see `docs/HUMANISER_DEV.md` "Build").

## Design decisions

These are my calls, made from reading the code.

1. **Execution goes through `team_roam`, not the orders bus.** The bus's `ATTACK` order doesn't work for this, for four reasons:
   - The assemble executor hands off within 900 units of the target (`bots/mode_assemble_generic.lua:31-34`), so in lane it does nothing.
   - Every order becomes a `HUMAN_ORDER` claim, not `FIGHT`.
   - Every order caps retreat and sends a chat acknowledgement.
   - Posting one replaces any active `ATTACK` order, including one from a human ping (`orders.ts` `Post`, same type and lane).

   `team_roam` already runs `Intent.Resolve` (`bots/mode_team_roam_generic.lua:80`), attacks `targetUnit` in `Think()`, and switches on the `IsGoingOnSomeone` branches of the per-hero `ConsiderX` functions. Without that switch, Lion, Crystal Maiden, Sven and most other heroes never use their stun on a chosen hero from laning (subagent survey: 48 of 128 hero files have no `IsLaning` branch).
2. **Partners coordinate by what they can see.** A bot's kill decision involves random rolls, so its partner can't post the same order deterministically. The partner also can't read the decision if modules aren't shared, and that check (`HUMANISER_DEV.md` "Shared-state finding") is still not recorded. So a bot treats its lane partner's visible commit as the commit signal, whether the partner is a human or a bot: the partner attacking an enemy hero while closing on it, or casting a key ability on it. The spec already asks for this for human partners; this plan uses it for bot partners too. 09's arbitration is used through `FIGHT` claims.
3. **Who runs it:** `LaneFight.Teams` decides which bots run it: `'all'` (the default), `'allies'` (allies of a human) or `'enemies'`. The default is `'all'` because the spec's in-game tests 1, 3 and 4 are about enemy bots punishing a human. It doesn't depend on 07's `OwnLaningThink`, because `team_roam` runs for every bot.
4. **Trades are short commits.** A trade is a `FIGHT` floor on `team_roam` for `TradeDuration` (2.5 s) or until `TradeHits` (3) attacks land. A kill commit lasts until the target dies, the abort rules fire, or `CommitMax` (8 s) runs out. 07's harass punish (one right-click on a last-hit attempt) stays as it is and runs first, so the spec's "mid-last-hit" window here only triggers on a last-hit attempt the harass tool didn't punish.
5. **Ability classes are a curated table.** The repo has no table of disables and escapes. `spell_list.lua`'s weights are Rubick replace weights and don't fit. `ability_classes.ts` holds a hand-curated set of "key" ability names (stuns, roots, hexes, silences, blinks and other escapes, and key items such as `item_blink`). The ultimate is detected from the ability handle (`IsUltimate()`), or from it being in slot 5.
6. **Cooldown source.** Task 1 probes the game first. The default source is `ability:GetCooldown(level)` on the enemy handle. If the probe shows it returns 0 or nil for enemies, Task 4b generates `cooldowns_data.ts` from d2vpkr's `npc_abilities.txt` instead. Ability level comes from `ability:GetLevel()` if it's readable; otherwise from `levelEstimate(heroLevel, isUlt)` (ultimate: 1 at level 6, 2 at 12, 3 at 18; basic ability: `min(4, ceil(heroLevel / 2))`).
7. **Instant casts.** Polling `IsCastingAbility()` / `GetCurrentActiveAbility()` misses casts with no cast point, including blink. Task 4 adds two fallbacks:
   - `InstallCastCallback` per enemy player ID, gated on the caster being visible to the observer when the callback fires, if Task 1 shows it fires for enemies;
   - a blink heuristic: a visible enemy that moves more than `BlinkJump` (600) between two polls 0.1 s apart is recorded as having used its blink-class key ability.

## Global Constraints

- Every number in the spec appears here unchanged as a config default in `lane_fight_config.ts` `DEFAULTS`, under `Customize.Humaniser.LaneFight`.
  - Remember chance: ultimate `[0.6, 0.98]`, key `[0.35, 0.9]`, other `[0.1, 0.6]`.
  - Timing error `x = [0.35, 0.05]`.
  - Forget window `[20, 90]` s.
  - Sharing loss `[0.3, 0.05]`.
  - Window notice `[0.3, 0.9]`.
  - Level spike window 10–15 s.
  - Out of position: more than 400 units ahead of their creeps.
  - Kill check every 0.5 s.
  - Burst error `y = [0.3, 0.05]`.
  - Tower override 1.3× HP.
  - Sync delay `react + [0.6, 0.1]` s.
  - Solo commit when overwhelming above skill 0.7.
- Curves are `[low, high]` pairs read as `low + (high - low) * skill`, the same as `LaneConfig.Curve`.
- **Kill switches:** `Humaniser.Enable = false` or `LaneFight.Enable = false` must give behaviour identical to the current branch: no claims, no `GetUnitList` scans, no cast callbacks installed, and `team_roam` returning its raw desire.
- **Performance:**
  - no per-call `GetUnitList` scan;
  - reuse `LaneState.Enemies(bot, lane)` (already perception-filtered and cached per `SnapshotRefresh`);
  - cast polling at most every `PollInterval` (0.1 s) per observer;
  - kill check every 0.5 s and window read every 0.25 s per bot.
- **State keys:** per observer by `GetPlayerID()`; per enemy by enemy player ID (handles can be shared across observers).
- **Fairness:** only casts by enemies visible to the observer (perception-noticed) are remembered. Anything a callback reports for a fogged caster is ignored.
- **Requires and build:**
  - Edit `.ts` and run `npm run build`.
  - Use absolute `bots/...` import paths.
  - Hand-written Lua (`mode_team_roam_generic.lua`, `jmz_func.lua`, `localization.lua`, `Customize/general.lua`) is edited directly.
- **Comments:** only where they say something the code doesn't (user rule).

## Review Focus

1. **A target that turns invulnerable or untargetable mid-commit** (Shallow Grave, Aeon Disk, BKB, Eul's on self): the commit must abort within one tick, not keep right-clicking. Test in Task 7: `abort when the target becomes CannotBeKilled or magic immune`.
2. **The bot drops low during a trade:** an HP threshold or a survival claim must end the trade. A `FIGHT` floor must never keep a bot under 25% HP in `team_roam`. Test in Task 7: `trade ends and releases its claim below StopHP`.
3. **The human partner pings or orders something else mid-commit** (`!back`, a danger ping): `HUMAN_ORDER` claims must win over the `FIGHT` floor. Test in Task 7: `a HUMAN_ORDER retreat floor beats the fight floor`.
4. **An enemy hero dies, or leaves vision for good, during a commit:** the commit releases its claim, and team_roam's sticky `targetUnit` doesn't keep chasing a fogged hero. Test in Task 7: `fogged target ends the commit after FogGrace`.
5. **An illusion as the target or the cast source** (Phantom Lancer, Naga, Manta): no kill check against an illusion, and no memory from an illusion's casts. Tests in Task 4 (`illusion casts are not recorded`) and Task 6 (`illusion targets are skipped`).

---

### Task 1: In-game probe command `!hfight` (spike, run once by the user)

Answers decisions 6 and 7 before the data layer is built.

**Files:**
- Create: `typescript/bots/FunLib/humaniser/lane_fight_probe.ts`
- Modify: `typescript/bots/FunLib/humaniser/lane_debug.ts` (register `!hfight` next to `!hcamp`)
- Test: `tests/humaniser/test_lane_fight_probe.lua`

**Interfaces:**
- Produces: `Probe.Run(bot: Unit): string[]` (the log lines) and `Probe.InstallCastLogger(team: number): void`.

- [ ] **Step 1: Write the failing test.** `probe lists each ability of the nearest visible enemy`: a stub enemy with abilities `{name, level, cooldown, ultimate}` in slots 0–5 produces one line per ability: `hfight <hero> slot=<i> <name> lvl=<n> cd=<n> ult=<bool> behavior=<n>`. A further line reads `hfight est=<GetEstimatedDamageToTarget(true, bot, 5, DAMAGE_TYPE_ALL)>`. Add `GetAbilityInSlot` and `GetEstimatedDamageToTarget` to the stubs (`dota_stubs.lua`) as plain fields on the unit.
- [ ] **Step 2: Run it and confirm it fails.** Run `cd tests/humaniser && node run.js test_lane_fight_probe.lua`. Expected: an error because `lane_fight_probe` isn't found.
- [ ] **Step 3: Implement `Probe.Run` and `Probe.InstallCastLogger`.** `InstallCastLogger` calls `InstallCastCallback(pid, fn)` once per enemy player ID. Each event is logged as `hfight cast pid=<caster> visible=<CanBeSeen> <dump of event keys>`, because the API doc doesn't list the callback's fields. Debug builds only: run only when `HDebug.IsEnabled()`.
- [ ] **Step 4: Run it and confirm it passes**, with the same command. Expected: `N passed, 0 failed`.
- [ ] **Step 5: Build and commit.** Run `npm run build && cd tests/humaniser && npm run check`, then `git commit -m "Lane fight: !hfight probe for enemy ability handles and cast callbacks"`.
- [ ] **Step 6 (user, in-game):** run with Debug on, stand next to an enemy bot, type `!hfight`, and watch it cast once in view and once from fog. Record the results in `HUMANISER_DEV.md` under "Lane fight (11)": does `cd` read non-zero, does `lvl` read correctly, does the callback fire for enemies, and does it fire for fogged casters. **Tasks 4 and 4b depend on these answers.** If `cd` works, skip 4b.

### Task 2: Config, kill switch, ability classes

**Files:**
- Create: `typescript/bots/FunLib/humaniser/lane_fight_config.ts` and `typescript/bots/FunLib/humaniser/ability_classes.ts`
- Modify:
  - `typescript/bots/FunLib/humaniser/config.ts`: add `LaneFight: { Enable: true }` to `DEFAULTS` and `"LaneFight"` to the `IsFeatureEnabled` union;
  - `typescript/bots/Customize/general.ts` and `bots/Customize/general.lua`: add a `LaneFight = { Enable = true }` block with the flags commented.
- Test: `tests/humaniser/test_lane_fight_config.lua`

**Interfaces:**
- Produces:
  - `LaneFightConfig.Settings(): LaneFightSettings`, a deep merge like `LaneConfig.Settings`;
  - `IsActive(): boolean`: Humaniser, LaneFight and at least one of `Memory`, `Trade` or `Kill` on;
  - `IsOn(flag: "Memory" | "Trade" | "Kill" | "CallKills"): boolean`;
  - `Curve(name, skill): number`;
  - `AppliesTo(bot: Unit): boolean`, which reads `Teams` and `IsHumanAllyTeam`;
  - `AbilityClasses.Classify(name: string, isUltimate: boolean): "ult" | "key" | "other"` and `AbilityClasses.IsEscape(name: string): boolean`.
- Every default listed under Global Constraints, plus:
  - `PollInterval 0.1`, `BlinkJump 600`;
  - `TradeDuration 2.5`, `TradeHits 3`, `CommitMax 8`;
  - `StopHP 0.3`, `FogGrace 1.0`;
  - `TradeFloor 0.75`, `CommitFloor 0.82`, `ShareMemory false`;
  - `KeyThreatsWindow 0.5`;
  - `CallCooldown 30`.

- [ ] **Step 1: Write the failing tests.**
  - `merge keeps defaults for missing keys`: an override of `{ Curves = { Notice = {0,1} } }` keeps `ForgetWindow` at `{20,90}`.
  - `inactive when humaniser off`, and `inactive when all of Memory, Trade and Kill are false`.
  - `Teams 'enemies' excludes allies of a human`.
  - Classes:
    - `lion_impale` and `item_blink` are key;
    - `lion_finger_of_death` with `isUltimate = true` is ult;
    - `lion_mana_drain` is other;
    - an unknown name is other;
    - `IsEscape("antimage_blink")` is true and `IsEscape("lion_impale")` is false.
- [ ] **Step 2: Run them and confirm they fail.** Run `node run.js test_lane_fight_config.lua`.
- [ ] **Step 3: Implement.** In `ability_classes.ts`, `KEY` and `ESCAPE` are `Record<string, true>` tables, with roughly 150 entries curated from the 7.41 hero list. The disables: stuns, roots, hexes, silences, sleeps, fears, taunts. The escapes: blinks, leaps, invisibility, untargetability. The items: `item_blink` and variants, `item_force_staff`, `item_hurricane_pike`, `item_cyclone`, `item_sheepstick`, `item_abyssal_blade`, `item_glimmer_cape`, `item_black_king_bar`. Cover every hero that has a `BotLib` file, with one line per hero, so a reviewer can scan it.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the full check: `npm run build && cd tests/humaniser && npm run check`.
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: config, kill switch, ability classes"`.

### Task 3: Cooldown memory (pure model)

**Files:**
- Create: `typescript/bots/FunLib/humaniser/cooldown_memory.ts`
- Test: `tests/humaniser/test_cooldown_memory.lua`

**Interfaces:**
- Consumes: `LaneFightConfig.Curve` and `Settings`, and `AbilityClasses.Classify`.
- Produces:
  ```ts
  export interface Entry { seenAt: number; estReadyAt: number; cls: "ult" | "key" | "other"; shared: boolean }
  export function Record(observerPid: number, enemyPid: number, ability: string, cls: Entry["cls"], cooldown: number, skill: number, now: number): boolean // false = not remembered
  export function Share(fromPid: number, toPids: number[], enemyPid: number, ability: string, skill: number): void // only when modules are shared
  export function ProbablyReady(observerPid: number, enemyPid: number, ability: string, learned: boolean, now: number, skill: number): LuaMultiReturn<[boolean, number]> // (ready, confidence)
  export function KeyThreatsDown(observerPid: number, enemyPid: number, keyAbilities: string[], now: number, skill: number): number
  export function Count(observerPid: number, now: number): number // remembered, not yet forgotten
  export function Reset(): void
  ```
- The rules come from spec Part 1:
  - remember roll by class;
  - `estReadyAt = seenAt + cd * (1 + U(-x, x))`;
  - confidence 1 until `estReadyAt`, then a linear fall to 0 over `ForgetWindow(skill)`;
  - ready when `now >= estReadyAt` or the entry is forgotten;
  - an unlearned ability returns `(false, 1)`;
  - unseen returns `(true, 0)`.
- `KeyThreatsDown` is the fraction of the enemy's learned key abilities believed not ready, so it's 0 when the enemy has none.

- [ ] **Step 1: Write the failing tests.** Use the stub's `RANDOM_FRACTION` to make each roll deterministic.
  - `remember roll per class at skill 0 and 1`: at `RANDOM_FRACTION = 0.5`, an ult is remembered at skill 0 (0.5 < 0.6). Key is not remembered at skill 0 (0.5 ≥ 0.35) but is at skill 1. Other is not remembered at skill 0 but is at skill 1 (0.5 < 0.6).
  - `timing error spans ±x`: at `RANDOM_FRACTION = 0` and skill 0, `estReadyAt = seenAt + cd * 0.65`; at 1 it's `cd * 1.35`; at skill 1 the range is ±0.05.
  - `confidence decays to 0 over the forget window, then ready`: skill 0, so 20 s. Confidence is 0.5 at `estReadyAt + 10`, and `ProbablyReady` is true once `now >= estReadyAt`. Check it's false at `estReadyAt - 0.1`.
  - `unseen ability is ready with confidence 0`, and `unlearned ability is not ready`.
  - `KeyThreatsDown counts only learned key abilities`: two key abilities, one on cooldown, gives 0.5; with none learned it's 0.
  - `memory is per observer`: what observer 1 records is invisible to observer 2 unless `Share` is used.
  - `Share loses entries at the sharing-loss rate`: at skill 0 and `RANDOM_FRACTION = 0.2`, the entry is dropped (0.2 < 0.3). At skill 1 it's kept (0.2 ≥ 0.05).
- [ ] **Step 2: Run them and confirm they fail.** Run `node run.js test_cooldown_memory.lua`.
- [ ] **Step 3: Implement.** Use per-observer tables, `Record<number, Record<number, Record<string, Entry>>>`. Re-recording the same ability overwrites its entry. Count each new cast as a new remember roll.
- [ ] **Step 4: Run the tests and confirm they pass.**
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: imperfect cooldown memory"`.

### Task 4: Cast watching (feeds the memory)

**Files:**
- Create: `typescript/bots/FunLib/humaniser/cast_watch.ts`
- Modify: `typescript/bots/FunLib/humaniser/lane_fight.ts` (created here as a facade with `Tick(bot)`), and `typescript/bots/FunLib/humaniser/index.ts` (call `LaneFight.Tick(bot)` after `Lane.Tick`, and guard it in `GuardModule`)
- Test: `tests/humaniser/test_cast_watch.lua`

**Interfaces:**
- Consumes:
  - `CooldownMemory.Record` and `Share`;
  - `AbilityClasses.Classify`;
  - `LaneState.Enemies(bot, lane)`, which gives visible enemies already filtered by perception;
  - `Profile.Get(bot).skill`.
- Produces:
  - `CastWatch.Tick(bot: Unit): void`;
  - `CastWatch.AbilitiesOf(enemy: Unit): { name: string; slot: number; learned: boolean; ult: boolean; cooldown: number }[]`, cached per enemy player ID for 5 s;
  - `CastWatch.LastRecorded(observerPid: number): { enemyPid: number; ability: string; at: number } | undefined`, used by the overlay and by Task 8's abort.
- Detection:
  1. Poll every `PollInterval`. For each visible, non-illusion enemy, a cast counts as new when `IsCastingAbility()` or `IsUsingAbility()` is true, `GetCurrentActiveAbility()` gives a name, and the same name hasn't been seen within the perception `EventGap` (0.5 s).
  2. Blink jump.
  3. `InstallCastCallback`, only if Task 1 confirmed it works for enemies (flag `UseCastCallback`, default from the probe result). Ignore the event unless the caster is in the observer's visible list.
- After a successful `Record`, call `CooldownMemory.Share` to the bot's lane partner only when `Settings().ShareMemory` is true. It defaults to false until the shared-state finding is recorded; with unshared modules, sharing would do nothing anyway.
- Cooldown is `ability:GetCooldown(level)` if it's greater than 0, else `CooldownsData[name]?.[level]` (Task 4b), else skip. Level is `ability:GetLevel()` if it's greater than 0, else the estimate from decision 6.

- [ ] **Step 1: Write the failing tests.**
  - `a visible cast is recorded once`: an enemy casting `lion_impale` for three polls produces one record.
  - `a fogged cast is not recorded`: the enemy is absent from `LaneState.Enemies`, or listed with `visible = false`.
  - `illusion casts are not recorded`.
  - `a jump over BlinkJump records the blink ability`, and `a jump without a blink-class ability records nothing`.
  - `with LaneFight off, Tick makes no engine calls`: count `GetUnitList` calls and `GetCurrentActiveAbility` calls, and both must be zero.
  - `level estimate before handle level`: with `GetLevel()` returning 0 at hero level 5, an ult reads as not learned and a basic ability as level 3.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement `cast_watch.ts` and the facade's `Tick`.** Run it from `Humaniser.Tick` only while `LaneFight.IsActive()` and `LaneConfig.InLaningPhase()`.
- [ ] **Step 4: Run the tests and confirm they pass.** Then run `npm run build && npm run check`.
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: watch visible enemy casts into cooldown memory"`.

### Task 4b (conditional, only if the Task 1 probe shows `GetCooldown` is unusable on enemies): generated cooldown table

**Files:**
- Create:
  - `typescript/post-process/gen-cooldowns.ts`: reads a local `npc_abilities.txt` (d2vpkr, `scripts/npc/npc_abilities.txt` plus `heroes/*.txt`) given as an argument;
  - output `typescript/bots/FunLib/humaniser/cooldowns_data.ts`: `export const CooldownsData: Record<string, number[]>`;
  - `package.json` script `gen-cooldowns`.
- Test: `tests/humaniser/test_cast_watch.lua`, adding `falls back to CooldownsData when GetCooldown is 0`.

- [ ] **Step 1:** Write the failing fallback test.
- [ ] **Step 2:** Implement the KV parser for `AbilityCooldown` (space-separated per-level values, or a `special_value` block in the newer format).
- [ ] **Step 3:** Run the generator once against a download the user provides. Record the d2vpkr commit and date in the file header.
- [ ] **Step 4:** Run the tests and confirm they pass.
- [ ] **Step 5:** Commit: `git commit -m "Lane fight: generated ability cooldown table"`.

### Task 5: Fight read (trade and respect windows)

**Files:**
- Create: `typescript/bots/FunLib/humaniser/fight_read.ts`
- Test: `tests/humaniser/test_fight_read.lua`

**Interfaces:**
- Consumes:
  - `CooldownMemory.KeyThreatsDown` and `ProbablyReady`;
  - `CastWatch.AbilitiesOf`;
  - `LaneState.Enemies` and `LaneState.ForBot` (for creep fronts);
  - `Harass.IsLastHitAttempt`;
  - `GetHeroLevel(pid)`.
- Produces:
  ```ts
  export type Window = "spell" | "lasthit" | "level" | "position";
  export type Respect = "their_spike" | "their_ult" | "outnumbered";
  export interface Read { target?: Unit; window?: Window; respect?: Respect; noticed: boolean }
  export function ReadFor(bot: Unit, now: number): Read // cached 0.25 s per pid
  export function LevelSpike(team: number, lane: Lane, now: number): "ours" | "theirs" | undefined
  ```
- Rules (spec Part 2):
  - **spell:** `KeyThreatsDown > KeyThreatsWindow`;
  - **lasthit:** `IsLastHitAttempt` is true for the target;
  - **level:** our side reached 2 or 6 first, and it's within `SpikeWindow` of that moment;
  - **position:** the target is more than 400 units ahead of its own creep front, or within our tower range.
  - **Respect:** the enemy reached the spike first, or the enemy's learned ult is `ProbablyReady` at level 6+, or visible plus recently-missing enemies (last seen within 10 s, within 2,500 units of the lane) outnumber our laners.
  - The lane spike is tracked by watching hero levels on both sides each read, storing the first time either side reached 2 and 6.
  - Respect suppresses every window.
  - `noticed` is one roll per (pid, window instance) against `Curve("Notice", skill)`.

- [ ] **Step 1: Write the failing tests**, one per window and one per respect reason:
  - `spell window after the remembered stun`;
  - `no spell window when the stun was forgotten`;
  - `level 2 first gives a 'level' window for SpikeWindow seconds then none`;
  - `their spike first gives respect`;
  - `400+ ahead of their creeps is out of position`;
  - `respect beats a window`;
  - `notice roll is drawn once per window instance`: the same window across 10 reads makes one draw (count `RandomFloat` calls).
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: trade and respect windows"`.

### Task 6: Kill check

**Files:**
- Create: `typescript/bots/FunLib/humaniser/kill_check.ts`
- Test: `tests/humaniser/test_kill_check.lua`

**Interfaces:**
- Consumes:
  - `CooldownMemory.ProbablyReady` for the target's escapes (`AbilityClasses.IsEscape`);
  - `LaneState.Enemies`;
  - helpers injected through `LaneConfig.Helpers()`: add `CannotBeKilled`, `GetTotalEstimatedDamageToTarget` and `IsSuspiciousIllusion` to `LaneHelpers` and `Lane.SetHelpers` in `jmz_func.lua`.
- Produces:
  ```ts
  export interface KillInputs { burst: number; hp: number; regen: number; escapeReady: boolean; towerInRange: boolean; enemiesNear: number; alliesNear: number; skill: number; errRoll: number }
  export function Passes(i: KillInputs): LuaMultiReturn<[boolean, number]> // (pass, margin = burst*(1+err)/(hp+regen*2))
  export function Check(bot: Unit, partners: Unit[], target: Unit, now: number): { pass: boolean; margin: number; overwhelming: boolean } | undefined // cached 0.5 s per pid
  ```
- Rules:
  - margin ≥ 1;
  - escape not believed ready;
  - tower not in range, unless the margin is at least `TowerOverride` (1.3);
  - `enemiesNear ≤ alliesNear`;
  - overwhelming means margin ≥ `Overwhelming` (1.5);
  - the error is `y * (2 * errRoll - 1)` with `y = Curve("BurstError", skill)`.

- [ ] **Step 1: Write the failing tests:**
  - `exact maths with fixed inputs`: burst 500, HP 450, regen 5, skill 1, `errRoll = 0.5` gives margin `500 / 460`, a pass;
  - `low-skill error can flip the result`: skill 0, `errRoll = 0` gives `500 * 0.7 / 460`, a fail;
  - `tower needs 1.3x`: margin 1.2 under the tower fails, 1.35 passes;
  - `escape believed ready blocks the kill`;
  - `outnumbered blocks the kill`;
  - `illusion targets are skipped` and `CannotBeKilled targets are skipped` (`Check` returns `pass = false`).
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: kill check"`.

### Task 7: Executor through `team_roam` with `FIGHT` claims

**Files:**
- Modify:
  - `typescript/bots/FunLib/humaniser/lane_fight.ts`: state machine and public hooks;
  - `bots/mode_team_roam_generic.lua`:
    - in `GetDesire`, after `CapForLanePush`, call `J.Humaniser.LaneFight.RoamDesire(bot, res)` before `Intent.Resolve`;
    - in `Think`, after `ItemOpsThink()`, `if J.Humaniser.LaneFight.Think(bot) then return end`;
  - `bots/FunLib/jmz_func.lua`: expose `J.Humaniser.LaneFight`, following how `J.Humaniser.Lane` is exposed.
- Test: `tests/humaniser/test_lane_fight.lua`

**Interfaces:**
- Consumes: `FightRead.ReadFor`, `KillCheck.Check`, `Intent.Claim` / `Release` / `Hold`, and `Profile.SampleDelay`.
- Produces:
  ```ts
  export type Phase = "idle" | "trade" | "commit" | "wait_partner";
  export function RoamDesire(bot: Unit, raw: number): number // posts the FIGHT floor while trading/committing; returns raw unchanged (claim does the lifting); without intent returns max(raw, floor)
  export function Think(bot: Unit): boolean // true = issued an action (SetTarget + Action_AttackUnit on the target)
  export function Target(bot: Unit): Unit | undefined
  export function Describe(bot: Unit): string // "fight: window=<type|none> kill=<margin|-> mem=<n> phase=<p>"
  ```
- Claim: `{ source: "lanefight:<phase>", tier: "FIGHT", mode: BotMode.TeamRoam, floor: TradeFloor | CommitFloor }`, re-posted every `RoamDesire` call with the default TTL.
- Ending a phase releases the claim and calls `bot.SetTarget(undefined)`.
- End conditions:
  - HP below `StopHP`;
  - the target is dead, an illusion, `CannotBeKilled` or magic immune;
  - the target has been out of the visible list for more than `FogGrace`;
  - trade duration or hits used up;
  - `CommitMax` reached;
  - a `HUMAN_ORDER` or `SURVIVAL` claim, which wins through intent without any extra code.

- [ ] **Step 1: Write the failing tests:**
  - `a noticed trade window posts a FIGHT floor on team_roam`: `Intent.Explain(bot, TEAM_ROAM)` names `lanefight:trade`;
  - `trade ends and releases its claim below StopHP`;
  - `trade ends after TradeHits landed attacks`;
  - `abort when the target becomes CannotBeKilled or magic immune`;
  - `fogged target ends the commit after FogGrace`;
  - `a HUMAN_ORDER retreat floor beats the fight floor`: resolve both and assert retreat is higher;
  - `with LaneFight off RoamDesire returns raw and posts no claim`;
  - `team_roam hooks are source-pinned`: read `bots/mode_team_roam_generic.lua` and check both call sites are present. This follows `test_lane_regression.lua`'s pinning style, because that mode file can't be loaded offline.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement the state machine, then the two Lua hooks.**
- [ ] **Step 4: Run the tests and confirm they pass.** Then run `npm run build && npm run check`.
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: trades and commits through team_roam FIGHT claims"`.

### Task 8: Partner coordination, kill calls, aborts

**Files:**
- Modify: `typescript/bots/FunLib/humaniser/lane_fight.ts`, `typescript/bots/FunLib/humaniser/lane_roles.ts` (reuse `Partner(bot)`), and `bots/FunLib/localization.lua` (key `say_lanefight_go`, `"go on %s"`; check how existing keys take an argument and follow that)
- Test: `tests/humaniser/test_lane_fight_partner.lua`

**Interfaces:**
- Consumes: `LaneRoles.Partner(bot)`, `Orders.Say`, `Orders.Ping`, and `CastWatch.LastRecorded`.
- Produces: `IsCommitting(ally: Unit, target: Unit, prev: { dist: number; at: number }): boolean`. It's true when `ally.GetAttackTarget() === target` and the distance between them is closing, or the ally is casting a key-class ability whose target is `target`.
- Rules (spec Part 3):
  - The support (position 4 or 5) with a ready key ability is the initiator when its own check passes.
  - A core whose check passes, with a bot support partner that holds a key ability, enters `wait_partner` and commits after the partner's visible commit plus `SampleDelay(react) + Curve("SyncDelay", skill)`.
  - A core with no such partner commits itself.
  - A follower commits on the partner's visible commit if its own margin is at least `FollowMargin` (0.8). That covers bot and human partners alike.
  - **Human partner:** the bot's check passes, so it says `go on <hero>` (at most one per `CallCooldown`, through `Orders.Say`) and pings the target. It waits for the human's commit, or commits alone only if overwhelming and skill > 0.7.
  - **Abort:** the target uses a remembered escape (`CastWatch.LastRecorded` is the target with an escape class), or the visible enemy count rises. Each triggers a re-check after `Curve("AbortNotice", skill)` (`[0.8, 0.15]` s), which is how low-skill bots abort late. Any commit or trade started on a memory entry that later proves wrong (the "down" ability is cast within 2 s of the commit) emits telemetry `lanefight_mistake kind=bad_memory` for 08.

- [ ] **Step 1: Write the failing tests:**
  - `support with a stun initiates, core waits`;
  - `core follows the partner's visible commit after the sync delay`: assert the commit time equals partner commit + react + `Curve("SyncDelay", skill)`, at skills 0 and 1;
  - `follows a human partner's attack on an enemy hero`;
  - `kill with a human partner calls and pings once, does not dive at skill 0.5`;
  - `overwhelming kill at skill 0.8 commits alone`;
  - `escape cast triggers a re-check after AbortNotice`;
  - `bad memory emits the mistake event`.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them and confirm they pass.**
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: partner sync, kill calls, aborts"`.

### Task 9: Overlay, telemetry, docs, regression

**Files:**
- Modify:
  - `typescript/bots/FunLib/humaniser/index.ts`: overlay key `fight` from `LaneFight.Describe`;
  - `typescript/bots/FunLib/humaniser/lane_fight.ts`: telemetry events;
  - `tools/hlog/analyse.js`: a summary line of windows, commits and aborts per bot, if the analyser lists per-event-type counts (follow its existing pattern);
  - `docs/HUMANISER_DEV.md`: a new section, "Lane fight (11)";
  - `../handoffs/00-README.md`: status line.
- Test: `tests/humaniser/test_lane_fight.lua`, adding the regression and telemetry assertions.

**Interfaces:**
- Telemetry events:
  - `lanefight_window pid= window= target= noticed=`;
  - `lanefight_commit pid= target= margin= role=<initiator|follower|solo>`;
  - `lanefight_abort pid= reason=`;
  - `lanefight_mistake pid= kind=`;
  - `lanefight_mem pid= enemy= ability= remembered=`.

- [ ] **Step 1: Write the failing tests:**
  - `overlay shows window, kill margin and remembered count`: the string equals `fight: window=spell kill=1.12 mem=2 phase=trade`;
  - `telemetry lines parse through hlog`: use `Telemetry.FormatLine` round trip;
  - `regression: LaneFight.Enable=false leaves team_roam desire, actions and RandomFloat draws unchanged`: compare against a run with the humaniser off, as `test_lane_regression.lua` does.
- [ ] **Step 2: Run them and confirm they fail.**
- [ ] **Step 3: Implement.** Write the docs section: module map, flags, design decisions 1–7, overlay and log formats, the spec's six in-game scenarios as a checklist, and the TODO (in-game) items (Task 1's answers, the `team_roam` 0.72 cap interacting with the floor, and `J.IsGoingOnSomeone` firing spells at the chosen target).
- [ ] **Step 4: Run the full check:** `npm run build && cd tests/humaniser && npm run check`, then confirm `git status` shows no Lua changes that don't match a TS edit.
- [ ] **Step 5: Commit:** `git commit -m "Lane fight: overlay, telemetry, docs"`.
