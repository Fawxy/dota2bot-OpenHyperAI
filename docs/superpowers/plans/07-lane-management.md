# Implementation plan: task 07, lane management

**Spec (binding authority):** `/Users/cbyatt/Documents/Projects/dota-bots-humaniser/handoffs/07-lane-management.md`
Also binding: `handoffs/00-README.md` (conventions), `handoffs/04-ally-last-hit-etiquette.md` ("Scope of the takeover"), `handoffs/02-humaniser-core.md`.
Worktree: `/Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h07`, branch `h-07-lane`. All paths below are relative to it.

Read before any task: `CLAUDE.md`, `docs/ARCHITECTURE.md` section 13 (TS to Lua), `docs/HUMANISER_DEV.md` ("Build", "Offline checks", the 04 and 03 sections), and the existing modules this plan extends: `typescript/bots/FunLib/humaniser/{config,profile,orders,commands,pings,ally_last_hit,perception,debug,index}.ts`, `bots/mode_laning_generic.lua`, `bots/mode_farm_generic.lua`, `tests/humaniser/{dota_stubs.lua,run.js,test_ally_last_hit.lua,test_pings.lua}`.

---

## Global Constraints

### Ground rules (apply to every task)
- **Nothing runs in-game.** Every task is done when (a) `npm run build` regenerates `bots/FunLib/humaniser/*.lua` from the TS, the generated Lua is committed with the TS, and a second `npm run build` leaves `git status` clean (no stray diff); and (b) `cd tests/humaniser && npm run check` passes. In-game-only facts become `**TODO (in-game):**` entries in `docs/HUMANISER_DEV.md` and checklist items in `docs/HUMANISER_TEST_PLAN.md` (task 14 consolidates; each task may add its own TODO lines as it goes).
- **TS first.** New code is TypeScript in `typescript/bots/FunLib/humaniser/*.ts` with absolute `bots/...` imports. Hand-written Lua is edited directly only in: `bots/Customize/general.lua`, `bots/FunLib/jmz_func.lua`, `bots/FunLib/localization.lua`, `bots/mode_laning_generic.lua`, `bots/mode_farm_generic.lua`, `bots/mode_rune_generic.lua`. `aba_site.ts` is **not** touched and its `CStackLoc` / `GetCampMoveToStack` / `GetCampStackTime` are never called (untrusted, pre-7.33).
- **jmz_func cannot be required** from humaniser modules (circular). Anything from `J.*` is injected with `Lane.SetHelpers(...)` from `jmz_func.lua`, exactly like `AllyLastHit.SetHelpers`.
- **Kill switches.** Every behaviour sits behind its own `Customize.Humaniser.Lane.<Flag>`. With `Humaniser.Enable = false`, `Lane.Enable = false`, or every Lane flag false, behaviour is identical to the pre-07 branch (spec regression scenario 15): `OwnsLaning` false, all Lua hooks no-ops that return before calling any engine function, no new chat commands parsed, ping classification unchanged.
- **Performance.** Lane snapshots are cached per `(team, lane)` for `SnapshotRefresh = 0.5` s. At most one `GetUnitList(AlliedCreeps)` and one `GetUnitList(EnemyCreeps)` per team per refresh (shared by the 3 lanes), and one `GetUnitList(EnemyHeroes)` per observer per refresh. No `GetUnitList` inside per-call predicates. Lua hooks pass the creep/hero lists `mode_laning_generic.lua` already computes.
- **State keys.** Per-bot state is keyed by `bot.GetPlayerID()`. Per-target state (enemy heroes, creeps, camps-as-units) lives in weak-keyed tables (`setmetatable(new LuaTable(), { __mode: "k" })`, as `weakKeys()` in `perception.ts`). Nothing is written onto unit handles.
- **Shared-state agnostic.** Whether modules are shared per team is unverified. Every cross-bot rule must give the same answer when each bot has its own module instance: use deterministic rankings (position, then player ID) and observed world state (creep attack targets, positions), with in-module claims only as a fast path.
- **Fairness.** Enemy heroes are read only through perception-filtered sources (`GetUnitList(UnitType.EnemyHeroes)` / `GetNearbyHeroes(r, true)`, already hooked by 03 for the observer `GetBot()`) plus `GetHeroLastSeenInfo(pid)[1]`. Never read fogged units (`CanBeSeen() === false` means ignore).
- **Tests** live in `tests/humaniser/test_lane_*.lua`, use `dofile(HARNESS_DIR .. "/dota_stubs.lua")` and the new shared stub `tests/humaniser/lane_world.lua` (task 1). Tests assert business decisions, not assignments, and each must fail if the code under test did nothing (check that the default/initial state does not already satisfy the assertion; where it might, assert a change between two states).
- **Module dependency direction (PF11).** Lua `require` cycles fail, so imports only point "down" this list: `lane_config` → `lane_hooks` → `camps_data`/`camps` → `lane_state` → `lane_roles` → `lane_plan` → `lane_planner` → `lane_tech`/`camp_jobs`/`stacking`/`harass`/`lane_mid`/`counterplay` → `lane_debug` → `lane` (facade). A lower module that needs something from a higher one reads it through a probe registered in `lane_hooks.ts` (task 1) by the higher module at load; `lane.ts` imports every module so all registrations run.
- **No hard-coded tunables (PF13).** Every number this plan names (radii, durations, thresholds, multipliers) is a key in `lane_config.ts` `DEFAULTS` (task 1 lists them all). Code reads `Settings().<Table>.<Key>`; if an implementer finds a literal this plan forgot, add it to `DEFAULTS` instead of hard-coding it.
- **One technique per wave cycle (PF14).** Once a technique has started executing in a wave cycle (`LanePlanner.Commit`), no other technique may start in that cycle, including after a camp job ends; `handsOff`, safety aborts and `none`/`hold` always apply immediately.
- **Randomness in tests (PF10).** `LaneConfig.Roll` draws exactly one `RandomFloat`; `Gauss` exactly two. `lane_world.lua`'s `SetRandomSequence` queue is reset by `LaneFresh` and at the start of every test block; tests that count rolls reset the queue before each simulated event with the decision roll first (documented draw order per function in its task).
- Follow existing naming: module `DEFAULTS` + merged `Get()/Settings()`, `HDebug.Text(bot, "lane", ...)`, `HDebug.Log("lane", ...)`, `Orders.Say(bot, key, cooldown)` for every team-chat line (respects the 1-line-per-10-s limit). Comments only where non-obvious.
- Lane enum values come from `bots/ts_libs/dota` (`Lane.Top/Mid/Bot`, `Team.Radiant/Dire`, `UnitType.*`).
- Dates in docs: dd/mm/yyyy. Units: game units (metric is not applicable to map units; seconds for time).

### Exact values from the spec
| Item | Value |
|---|---|
| Skill gates | Block 0.3, FullPull 0.3, HalfPull 0.6, StackPull (double/stack pull) 0.75, AggroPull 0.5, Freeze 0.7, Shove 0.4 |
| Other skill gates | Solo-lane camp jobs > 0.6; multi-stacking ancients > 0.7; camp block (ward in spawn box) > 0.6 |
| Timing jitter σ (every aggro, pulls and stacks) | `lerp(1.5, 0.2, skill)` s, Gaussian |
| Technique attempt rate | `lerp(0.15, 0.85, skill)` when the planner says the technique is right |
| Path noise per waypoint | `lerp(150, 20, skill)` units |
| Stack attempt rate | `lerp(0.2, 0.9, skill)` |
| Harass capitalise chance | `lerp(0.25, 0.85, skill)` |
| Counter-play notice chance | `lerp(0.2, 0.8, skill)` |
| Plan misread windows | `lerp(0.30, 0.05, skill)` |
| Cover absent core proactiveness | `lerp(0.3, 0.9, skill)` |
| Snapshot refresh | ~0.5 s |
| eqPos | −1 at our T1 ... +1 at their T1 |
| Desired eq | safelane and offlane: just outside own tower; mid: slightly toward enemy before runes (config table) |
| Wave rhythm | waves at :00 and :30 (30 s cycle); neutral respawn on the minute if box empty (TODO in-game confirm) |
| Single-actor aggro window | one hero draws aggro per ~2–3 s window; if anyone drew aggro in the last ~3 s the support waits (use 3.0 s) |
| Prefer support for aggro | when the core is mid-last-hit or core HP < 60% |
| Absent core | dead, or > 1,200 from the lane front, or away > one wave cycle (30 s) |
| Partner safety (never leave lane) | partner HP < 40% or ≥ 2 enemies visible near the partner |
| Lane-front ping | "leave the wave alone" for 30 s |
| Stack seed timing | ~:53–:55, ±1–1.5 s by camp |
| Pull seeds | safelane small camp :15/:45 (some :16/:46); hard camp :18/:48 |
| Pull/stack job desire | ~0.7 inside the job's time window only |
| Pull outcome | divert fraction = ally lane creeps whose `GetAttackTarget()` is a neutral / wave size; full > 0.8; half 0.3–0.6 |
| Stacking who | pos 4/5 in laning when lane stable: no enemy hero within 1,200 seen in last 3 s, and HP > 50%; after laning any support with nothing better |
| Stack execution | move to stand point from ~:45; at `aggroSec + jitter` attack one neutral once (`Action_AttackUnit(creep, true)`); walk `exitPath` until :00 + ~1 s; return to lane |
| Stack telegraph | `stacked big camp`, 2-minute cooldown |
| Pull telegraph | `pulling in 5`, with a cooldown |
| Harass | enemy laner within attack range + 100 making a last-hit attempt; respond after `Profile.SampleDelay(bot, 'react')`; ≥ 3 enemy lane creeps within 500 → one hit and step back; never under enemy tower before level 6 unless target < 30% HP |
| Mid | block at 0:00; shove ~15–20 s before power/water rune spawn or before leaving to gank; rune timings from OHA's rune logic, not hard-coded; pulls mid only if data shows a pullable camp |
| Counter-play signals | enemy support unseen > 4 s, last seen toward its pull camp, within ~6 s of that camp's pull/half-pull timing, or visible at the camp; expected enemy wave not at front within ~5 s of usual arrival (full pull) or noticeably fewer creeps (half pull); eqPos near enemy tower ≥ 2 wave cycles while enemy heroes deny heavily (freeze); enemy hero visible near a camp :50–:58, or neutrals visible outside their box at :00 (stack) |
| Camp block | skill > 0.6, at most once per few minutes (use 180 s), verify wards block spawns first |
| Replay event definitions | stack: hero attacks a neutral in camp X between :50 and :58 and the camp's creep count goes up next minute; pull: hero attacks a lane-side camp, then those neutrals take damage from our lane creeps within ~15 s; half pull: as pull but only part of the wave engages |

### Plan-chosen values (not in the spec; all live in config, tune in playtest)
These are this plan's resolutions of unspecified numbers. Keep them as named config keys so playtests can change them.
- `DesiredEq = { Safe = -0.7, Off = -0.7, Mid = -0.1, MidPreRune = 0.15 }`; `XpDenyWeight = 0.2`.
- Planner bands on `laneScore` (= desired − eqPos − XP adjustment; negative means the wave is too far toward the enemy): `FullPullBelow = -0.5`, `SmallDriftBelow = -0.2`, `AggroCorrectBelow = -0.15`. Large wave for half pull under FREEZE/HOLD: ally creeps near front ≥ enemy creeps + 2.
- Seed half-pull timings: full pull aggro + 2 s (small `[17, 47]`, hard `[20, 50]`). Seed stack seconds by type: small 54.5, medium 54.0, large 53.5, ancient 53.0. Offlane hard-camp pull seed `[18, 48]`, half `[20, 50]`, marked `unverified` (may not be pullable on the current map).
- `HalfMeetOffset = 500` units further along our wave's direction of travel; `PullCampMaxTowerDist = 2500` (seed pull camp matching); `ReplayMatchRadius = 600`.
- Inference: per 30 s cycle tallies; SHOVE if ≥ 4 non-last-hit hits on enemy creeps; FREEZE if 0 such hits and ≥ 2 denies and mean eqPos ≤ −0.5; HOLD if aggro draws + step-backs ≥ 2; else NEUTRAL. Hysteresis: candidate must persist `PlanSustain = 5` s and a new plan dwells ≥ `PlanMinDwell = 15` s.
- `DoubleDrawChance = lerp(0.2, 0.0, skill)` (low-skill double aggro draw, logged as a mistake).
- Order durations: `!freeze`/`!shove` 90 s, `!pull`/`!nopull` 120 s, `!stack` 60 s.
- Cooldowns: `pulling in 5` 60 s; counter-play telegraphs 60 s each; `stacked big camp` 120 s (spec).
- Aggro: `AggroCooldown = 2.3` s between draws by the same bot; walk-back 1.5 s / up to 400 units.
- Block window: 0:00 to 0:30, or until enemy lane creeps are within 700 of our lead creep.
- Harass positioning for high skill from `HarassPositionSkill = 0.6`; random-time harass interval 4–8 s for skill < 0.5. That random poke is the shared tool's idle poke on a different interval (task 11).
- Partner-danger radius 1,200; contest-camp path safety: no other enemy last seen within 1,500 of the route in the last 5 s.
- Mid pre-rune shove window: rune spawn − 20 s to rune spawn − 15 s (spec "15–20 s").
- Pull data second formats (PF8): pull and half-pull seconds are stored as `[s, s + 30]` with `s` in [0, 30) (both waves of the minute); stack seconds are stored mod 60.
- Human-pulling window: a human support counts as pulling when within `HumanPullRadius` (800) of one of our pull camps and the cycle second is within `HumanPullWindow` (6 s) of that camp's pull or half-pull second.
- Absent core: dead or more than 1,200 from the front (the spec's "away for more than one wave cycle" is subsumed: a core away for a cycle is necessarily > 1,200 from the front, so no separate 30 s timer).
- Telegraph `shoving then rotating` (`say_lane_shove_rotate`) on starting a shove-before-rotating, cooldown 60 s.

---

## Task list
1. Lane config, flags, hook registry, helpers and test world
2. Camp data (seeds) and live resolution, `!hpt` / `!hcamp`
3. Replay-mining and console-log tooling (offline, tested on fixtures)
4. Lane state snapshot (Phase B)
5. Shared lane plan: core pick, human inference, LANE_* orders, `!freeze`/`!shove`/`!pull`/`!nopull`/`!stack`, lane-front ping (B2)
6. Partnership rules: roles, single-actor aggro window, camp-job owner, partner safety, absent-core cover (B2)
7. Technique planner (Phase C decision only)
8. In-lane techniques: block, aggro pull and drop, tower aggro, freeze, shove; laning `Think()` hooks
9. Camp-job executor and pulls (full, half, double), farm-mode hooks, `!hpulltest`
10. Stacking (Phase D), stack pull, `!hstacktest`
11. One shared harass tool: timed last-hit punish plus 04's idle poke (Phase E)
12. Mid lane playbook (B3) and the rune-time helper
13. Counter-play (Phase F)
14. Docs, test plan, regression consolidation

---

## Task 1: Lane config, flags, helpers and test world

**Goal:** the configuration surface and shared helpers every later task uses, with no behaviour change.

### Files
- Create `typescript/bots/FunLib/humaniser/lane_config.ts` (→ `bots/FunLib/humaniser/lane_config.lua`).
- Create `typescript/bots/FunLib/humaniser/lane.ts` (Lua-facing facade; later tasks add functions here).
- Create `typescript/bots/FunLib/humaniser/lane_hooks.ts` (PF11: leaf probe registry that breaks import cycles; imports only `lane_config` and `bots/ts_libs/dota`).
- Modify `typescript/bots/FunLib/humaniser/config.ts`: add `Lane: { Enable: true } as Record<string, any>` to `DEFAULTS`; extend `IsFeatureEnabled`'s union with `"Lane"`.
- Modify `typescript/bots/FunLib/humaniser/index.ts`: `import * as Lane from "bots/FunLib/humaniser/lane"`, add to the `export { ... }` list, call `Lane.Tick(bot)` in `Tick` after `Commands.Tick(bot)`.
- Modify `typescript/bots/ts_libs/dota/globals.d.ts`: declare
  - `function GetLaneFrontAmount(team: Team, lane: Lane, ignoreTowers: boolean): number;`
  - `function GetAmountAlongLane(lane: Lane, loc: Vector): { amount: number; distance: number };` (OHA uses the table form: `ability_item_usage_generic.lua:4868`)
  - `function GetLocationAlongLane(lane: Lane, amount: number): Vector;`
  - add `GetExtrapolatedLocation(seconds: number): Vector` and `Action_MovePath(path: Vector[]): void` to the Unit interface in `interfaces.ts` (both are missing; `GetNearbyTowers` and `GetCurrentMovementSpeed` already exist).
- Modify `bots/Customize/general.lua`: add under `Customize.Humaniser` (after `Commands = { Enable = true },`):
  ```lua
  -- Lane management (task 07). Each flag switches one behaviour; Enable = false restores upstream laning.
  Lane = {
      Enable = true,
      -- Who gets OHA's laning Think() for in-lane techniques: 'allies' (allies of humans), 'all' (every bot), 'off'.
      OwnLaningThink = 'allies',
      Plan = true, Block = true, FullPull = true, HalfPull = true, StackPull = true,
      AggroPull = true, Freeze = true, Shove = true, Stack = true, Harass = true,
      Mid = true, CounterPlay = true, Telegraph = true,
      CampBlock = false, -- stretch: verify in-game that wards still block spawns first
  },
  ```
- Modify `bots/FunLib/jmz_func.lua` after the `J.Humaniser.Pings.SetHelpers(...)` block:
  ```lua
  J.Humaniser.Lane.SetHelpers({
      GetPosition = function(unit) return J.GetPosition(unit) end,
      IsInLaningPhase = function() return J.IsInLaningPhase() end,
      WillKillTarget = function(target, dmg, dmgType, delay) return J.WillKillTarget(target, dmg, dmgType, delay) end,
      GetAttackProDelayTime = function(attacker, target) return J.GetAttackProDelayTime(attacker, target) end,
      WeAreStronger = function(bot, radius) return J.WeAreStronger(bot, radius) end,
  })
  ```
  (task 12 adds `NextPowerRuneTime`; until then the helper is absent and `IsPreRune` returns false).
- Create `tests/humaniser/lane_world.lua` (shared stub, not a `test_` file so `run.js` skips it).
- Create `tests/humaniser/test_lane_config.lua`.

### `lane_config.ts` exports (exact signatures; later tasks consume them)
```ts
export type LaneFlag = "Plan" | "Block" | "FullPull" | "HalfPull" | "StackPull" | "AggroPull" | "Freeze"
    | "Shove" | "Stack" | "Harass" | "Mid" | "CounterPlay" | "Telegraph" | "CampBlock";
export type Technique = "block" | "full_pull" | "half_pull" | "stack_pull" | "aggro_pull" | "freeze" | "shove" | "stack";
export type CurveName = "JitterSigma" | "AttemptRate" | "PathNoise" | "StackAttempt" | "HarassCapitalise"
    | "CounterNotice" | "PlanMisread" | "CoverAbsentCore" | "DoubleDraw";
export const DEFAULTS: {...};          // see below
export type LaneSettings = typeof DEFAULTS;
export function Settings(): LaneSettings;            // deep merge of DEFAULTS with Config.Get().Lane, cached
export function ResetSettings(): void;               // tests only: drop the cache
export function IsEnabled(): boolean;                // Config.IsFeatureEnabled("Lane")
export function IsOn(flag: LaneFlag): boolean;       // IsEnabled() && Settings()[flag] === true
export function IsActive(): boolean;                 // PF4: IsEnabled() && any consumer flag on (every LaneFlag except Telegraph)
export function GateFor(tech: Technique): number;
export function Knows(tech: Technique, skill: number): boolean; // IsOn(flag for tech) && skill >= gate
export function Curve(name: CurveName, skill: number): number;  // lerp(low, high, clamp01(skill))
export function Gauss(): number;                     // Box-Muller from two RandomFloat(1e-6, 1) draws
export function Jitter(skill: number): number;       // Gauss() * Curve("JitterSigma", skill)
export function Roll(chance: number): boolean;       // exactly one RandomFloat(0, 1) draw; < chance
export function SkillOf(bot: Unit): number;          // Profile.Get(bot).skill
export function OwnLaningMode(): "allies" | "all" | "off"; // invalid strings -> "off"
export interface LaneHelpers {
    GetPosition?: (this: void, unit: Unit) => number;
    IsInLaningPhase?: (this: void) => boolean;
    WillKillTarget?: (this: void, target: Unit, dmg: number, dmgType: number, delay: number) => boolean;
    GetAttackProDelayTime?: (this: void, attacker: Unit, target: Unit) => number;
    WeAreStronger?: (this: void, bot: Unit, radius: number) => boolean;
    NextPowerRuneTime?: (this: void) => number;   // task 12
}
export function SetHelpers(h: LaneHelpers): void;
export function Helpers(): LaneHelpers;
export function PositionOf(unit: Unit): number | undefined;  // via helper, undefined if missing
export function InLaningPhase(): boolean;                     // helper, fallback DotaTime() < 600
```
Technique → flag map: block→Block, full_pull→FullPull, half_pull→HalfPull, stack_pull→StackPull, aggro_pull→AggroPull, freeze→Freeze, shove→Shove, stack→Stack (gate 0: `Knows("stack")` is just the flag; stacking has its own attempt curve). `stack` exists so the one-technique-per-cycle lock (PF14) covers stack jobs; the planner's `Choose` never returns it.

`DEFAULTS` (keys used by later tasks; values from Global Constraints):
```ts
{
  Enable: true, OwnLaningThink: "allies",
  Plan: true, Block: true, FullPull: true, HalfPull: true, StackPull: true, AggroPull: true, Freeze: true,
  Shove: true, Stack: true, Harass: true, Mid: true, CounterPlay: true, Telegraph: true, CampBlock: false,
  Gates: { Block: 0.3, FullPull: 0.3, HalfPull: 0.6, StackPull: 0.75, AggroPull: 0.5, Freeze: 0.7, Shove: 0.4,
           SoloCampJob: 0.6, MultiStackAncients: 0.7, CampBlock: 0.6, HarassPosition: 0.6 },
  Curves: { JitterSigma: [1.5, 0.2], AttemptRate: [0.15, 0.85], PathNoise: [150, 20], StackAttempt: [0.2, 0.9],
            HarassCapitalise: [0.25, 0.85], CounterNotice: [0.2, 0.8], PlanMisread: [0.30, 0.05],
            CoverAbsentCore: [0.3, 0.9], DoubleDraw: [0.2, 0.0] },
  Eq: { Safe: -0.7, Off: -0.7, Mid: -0.1, MidPreRune: 0.15, XpDenyWeight: 0.2 },
  Planner: { FullPullBelow: -0.5, SmallDriftBelow: -0.2, AggroCorrectBelow: -0.15, LargeWaveMargin: 2, AggroStepEq: 0.15 },
  Timing: { SnapshotRefresh: 0.5, WaveCycle: 30, AggroWindow: 3.0, AggroCooldown: 2.3, WalkBack: 1.5,
            BlockEnd: 30, BlockLostSec: 2, StackMoveFrom: 45, StackExitUntil: 1.0, StackOutcomeAt: 2, JobDesire: 0.7,
            ContestDesire: 0.65, ContestMax: 10, ContestAttackGap: 2.5, JobStartSlack: 3, JobStartLate: 2,
            JobMaxAfterAggro: 15, JobUpcoming: 10, MaxTravel: 12, WatchSec: 8, DoublePullReach: 8, ShoveMaxSec: 8,
            PingHandsOff: 30, PlanSustain: 5, PlanMinDwell: 15, CoreYieldStagger: 1.5, HumanPullWindow: 6,
            CounterUnseen: 4, CounterPullWindow: 6, CounterWaveLate: 5, CounterSignalTTL: 20, PunishGap: 2, PunishFor: 6,
            PathSafeSeen: 5, MidRuneShoveLookahead: 25, RuneContestAfter: 10, DropRangedDenyFor: 20,
            PreRuneMin: 15, PreRuneMax: 20, RandomHarassMin: 4, RandomHarassMax: 8, LowSkillHarassExtra: 1.5,
            AggroDanceBack: 1, BlockNoiseEvery: 1, CampBlockCooldown: 180, PullTelegraphLead: 5,
            PullTelegraphCooldown: 60, StackTelegraphCooldown: 120, CounterTelegraphCooldown: 60, ShoveTelegraphCooldown: 60 },
  Thresholds: { CoreAbsentDist: 1200, CoreBusyHP: 0.6, CoreBusyDamageMult: 1.3, PartnerMinHP: 0.4, PartnerDangerEnemies: 2,
                PartnerDangerRadius: 1200, SupportNearFront: 800, StableEnemyRadius: 1200, StableSeenWithin: 3, StableMinHP: 0.5,
                FullPullMin: 0.8, HalfPullMin: 0.3, HalfPullMax: 0.6, HarassExtraRange: 100, AggroDanceCreeps: 3,
                AggroDanceRadius: 500, HarassTowerLevel: 6, HarassTowerTargetHP: 0.3, EnemyTowerRange: 850,
                ShoveMinHP: 0.5, ShoveDoneCreeps: 1, TowerSwapAllyHP: 0.6, TowerSwapBotHP: 0.6, FreezeDriftMargin: 0.2,
                MidTowerEq: 0.8, FreezeCoreEqMax: -0.3, MidMissingEq: -0.6, StackMaxCampCount: 1, ApproachEpsilon: 25 },
  Radii: { LaneCreep: 1200, LaneAssign: 1200, AllyNearFront: 1600, Exposure: 1500, LaneFrontPing: 600, HumanPullRadius: 800,
           AggroDrawExtra: 200, AggroWalkBack: 300, AggroWalkMax: 400, BlockAhead: 120, BlockSide: 50, BlockStart: 1500,
           BlockLost: 400, BlockContact: 700, TowerAggro: 900, TowerExitMargin: 100, Zone: 900, ZoneOffset: 150,
           HarassStandBack: 50, LowHpCreep: 700, StepBackCreeps: 700, StepBackEps: 50, NeutralSearch: 700, StandOffset: 150,
           MeetWatch: 800, WaveSize: 1200, StackExit: 900, StackCoreCamp: 3000, EnemyNearCamp: 800, NeutralOutsideMargin: 200,
           PullCampLastSeen: 1500, PathSafe: 1500, MidFront: 1200, MidHuman: 1500, LaneActive: 2500, PullPathEdge: 150,
           BoxMargin: 300, AggroDanceStep: 250, Stronger: 1200, ApproachExtrapolate: 0.5 },
  Infer: { ShoveHits: 4, FreezeDenies: 2, FreezeEqMax: -0.5, HoldSignals: 2, ShoveHitDamageMult: 1.3 },
  Camps: { HalfMeetOffset: 500, PullCampMaxTowerDist: 2500, ReplayMatchRadius: 600, LaneSampleStep: 0.005 },
  Orders: { FreezeShove: 90, PullNoPull: 120, Stack: 60 },
}
```
Merge rule: tables deep-merge (like `commands.ts merge`); arrays in `Curves` replace whole. Later tasks reference these keys by name (e.g. `Radii.LaneFrontPing`); numbers quoted in later task text are these defaults.

### `lane_hooks.ts` exports (PF11)
```ts
export function SetRotationProbe(fn: (this: void, bot: Unit) => boolean): void;   // registered by camp_jobs (task 9) and lane_mid (task 12); several probes OR together
export function IsRotationPlanned(bot: Unit): boolean;                             // false when none registered
export function SetStackedProbe(fn: (this: void, campIdx: number) => boolean): void; // registered by stacking (task 10)
export function IsStacked(campIdx: number): boolean;                               // false when none registered
export function SetTechniqueOverride(fn: (this: void, bot: Unit) => LaneConfig.Technique | undefined): void; // counterplay (task 13)
export function TechniqueOverride(bot: Unit): LaneConfig.Technique | undefined;
export function ResetHooks(): void;                                                 // tests only
```

### `lane.ts` (facade) exports in this task
```ts
export * as Config from "bots/FunLib/humaniser/lane_config"; // if TSTL dislikes `export * as`, use import + export { }
export function IsEnabled(): boolean;
export function SetHelpers(h: LaneConfig.LaneHelpers): void;
export function Tick(bot: Unit): void;   // no-op when !LaneConfig.IsActive(); later tasks add work
```

### `lane_world.lua` (test stub world, extended by later tasks)
Provides deterministic geometry so pure functions can be tested:
- Lanes are straight lines from Radiant ancient (amount 0, x = −7000) to Dire ancient (amount 1, x = +7000) at `LANE_Y = { [top]=5000, [mid]=0, [bot]=-5000 }`. `GetLocationAlongLane(l, a)` = `Vector(-7000 + 14000*a, LANE_Y[l])`; `GetAmountAlongLane(l, v)` returns `{ amount = clamp01((v.x + 7000)/14000), distance = |v.y - LANE_Y[l]| }`.
- `LANE_FRONT[team][lane]` (team-relative amounts) backs `GetLaneFrontAmount`; `GetLaneFrontLocation(team, lane, d)` = location at the team's amount converted to absolute, shifted by `d/14000` toward the team's base.
- `TOWERS_W[team][id]` with `GetTower(team, id)`; T1s at absolute amounts 0.3 (Radiant) and 0.7 (Dire) for every lane.
- `MakeCreep{team, x, y, hp, maxhp, name, target}` with `GetAttackTarget`, `GetHealth`, `GetMaxHealth`, `GetUnitName`, `IsAlive`, `CanBeSeen`, `GetLocation`, `GetTeam`; `CREEPS[team]` backs `GetUnitList(AlliedCreeps|EnemyCreeps)` relative to `CURRENT_TEAM`.
- `SPAWNERS` table backs `GetNeutralSpawners()`; `NEUTRALS` list for `GetNearbyNeutralCreeps`.
- `LAST_SEEN[pid] = { location, time_since_seen }` backs `GetHeroLastSeenInfo(pid)` (returns `{}` when absent).
- An action recorder (PF12): `ACTIONS = {}`; Unit methods `Action_MoveToLocation`, `Action_AttackUnit`, `Action_MovePath`, `Action_ClearActions`, `Action_UseAbilityOnLocation` append `{ pid = self.pid, kind = "<method name without Action_>", args = { ... } }` holding every argument, so tests can assert e.g. `a.kind == "AttackUnit" and a.args[1] == hero and a.args[2] == true` (the `once` flag). Helper `ActionsOf(pid, kind)` filters.
- A call counter: `GETUNITLIST_CALLS` incremented by the stub `GetUnitList` (per `UnitType`), reset by `LaneFresh`.
- `SetRandomSequence({...})` replaces global `RandomFloat` with a queue of fractions (falls back to `RANDOM_FRACTION or 0.5` when exhausted), so tests can control rolls and Gaussian draws. `LaneFresh` resets the queue.
- `LaneFresh(laneCfg, extra)` = `FreshHumaniser({ Enable = true, SkillOverride = extra.skill, Lane = laneCfg, ... })` then `H.Lane.SetHelpers({...})` with stub helpers (`GetPosition = function(u) return u.pos end`, `IsInLaningPhase = function() return LANING ~= false end`, `WillKillTarget = function(t, dmg) return t.hp <= dmg end`, `GetAttackProDelayTime = function() return 0.3 end`, `WeAreStronger = function() return STRONGER == true end`, `NextPowerRuneTime = function() return NEXT_RUNE or 120 end`), and calls `ResetHooks`, `ResetSettings` and every module `ResetCache`.

### Behaviour
- Pure configuration and helpers. `Lane.Tick` returns immediately when `!IsActive()`.
- `Knows` must read both the flag and the gate: a flag switched off makes the technique unknown regardless of skill.

### Tests (`test_lane_config.lua`)
- `gates match spec`: at skill 0.29 `Knows("block")` false, at 0.3 true; `half_pull` false at 0.59/true at 0.6; `stack_pull` false at 0.74/true at 0.75; `aggro_pull` 0.5; `freeze` 0.7; `shove` 0.4 (boundary pairs for every technique).
- `flag off hides technique`: `{ HalfPull = false }`, skill 1.0 → `Knows("half_pull")` false while `Knows("full_pull")` stays true.
- `lane disabled hides all`: `Lane = { Enable = false }` → `Knows` false for all techniques at skill 1, `IsOn("Stack")` false; and `Humaniser.Enable = false` likewise. Positive control in the same test: defaults → `Knows("block")` true at skill 1.
- `active needs a consumer flag`: `Lane = { Enable = true }` with every flag false except `Telegraph` → `IsActive()` false; set `Stack = true` → true.
- `hooks default and register`: `IsRotationPlanned(bot)` false with no probe; after `SetRotationProbe(function() return true end)` true; two probes, one true → true; `IsStacked(3)` false until a probe returns true for 3.
- `curves endpoints and midpoint`: `Curve("JitterSigma", 0) == 1.5`, `(1) == 0.2`, `(0.5) == 0.85`; `AttemptRate(0.5) == 0.5`; `PathNoise(0) == 150`; clamp: `Curve("AttemptRate", 1.7) == 0.85`.
- `user override merges`: `Lane = { Gates = { Freeze = 0.9 } }` → freeze gate 0.9, block gate still 0.3.
- `own laning mode parse`: `'all'`, `'allies'`, `'off'` round-trip; `'bogus'` → `'off'`.
- `jitter uses gaussian`: Box-Muller `z = sqrt(-2 ln u1) * cos(2π u2)`. Re-seed the queue before every `Jitter` call (each call consumes two draws). `SetRandomSequence({0.5, 0.25})` → z = 0 so `Jitter(0)` ≈ 0 (within 1e-3); `SetRandomSequence({math.exp(-2), 1.0})` then `Jitter(1)` ≈ 0.4; re-seed the same pair, then `Jitter(0)` ≈ 3.0 (within 1e-3; proves σ scales with skill and the draw is not a constant).

### Verification
```bash
cd /Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h07 && npm run build && npm run build && git status --porcelain
cd tests/humaniser && npm run check
```
Second build must add no new changes beyond the TS + generated Lua + hand-written files of this task.

---

## Task 2: Camp data (seeds) and live resolution, `!hpt` / `!hcamp`

**Goal:** Phase A1/A2 data model, seed data, runtime resolution against `GetNeutralSpawners()`, and the first two debug commands.

### Files
- Create `typescript/bots/FunLib/humaniser/camps_data.ts` — data only. Header comment: "Seed data from public guides (Liquipedia Pulling, Dotafire, bo3.gg); regenerate replay entries with tools/replay-mining (task 3). Spawn boxes are never stored here."
- Create `typescript/bots/FunLib/humaniser/camps.ts` — types, resolution, derivation.
- Create `typescript/bots/FunLib/humaniser/lane_debug.ts` — debug chat commands.
- Modify `lane.ts`: export `Camps`, call `LaneDebug.Tick(bot)` from `Tick`.
- Create `tests/humaniser/test_lane_camps.lua`.

### Types and exports
`camps.ts`:
```ts
export type CampType = "small" | "medium" | "large" | "ancient";
export type LaneKind = "safe" | "off" | "mid";
export interface PullData { aggroSec: number[]; halfAggroSec?: number[]; path: Vector[]; meetPoint: Vector; halfMeetPoint?: Vector; }
export interface CampJobData {
    campIdx: number; team: number; lane?: Lane;
    stack?: { aggroSec: number; exitPath: Vector[] };
    pull?: PullData;
    source: "seed" | "replay" | "measured";
    type: CampType;            // from the live spawner
    key?: string;              // camps_data key that matched, if any
    derived: boolean;          // true when path/meet/exit were computed at runtime (unverified)
}
export interface Spawner { idx: number; team: number; type: CampType; location: Vector; min: Vector; max: Vector; speed: any; }
export function Spawners(): Spawner[];                      // cached once; idx = the Lua table key of GetNeutralSpawners() (fallback entry.idx)
export function Resolve(): CampJobData[];                   // cached once per game (spawners are static); ResetCache() for tests
export function ResetCache(): void;
export function ByIdx(idx: number): CampJobData | undefined;
export function PullCampsFor(team: number, lane: Lane): CampJobData[]; // camps with pull data whose lane === lane, small first then large
export function NearestSpawner(loc: Vector): LuaMultiReturn<[Spawner | undefined, number]>;
export function InBox(idx: number, loc: Vector, margin?: number): boolean;
export function BoxCenter(s: Spawner): Vector;
export function LaneOfKind(team: number, kind: LaneKind): Lane;  // Radiant: safe=Bot, off=Top; Dire: safe=Top, off=Bot; mid=Mid
export function ToTeamAmount(team: number, absAmount: number): number;   // Radiant: a; Dire: 1 - a
export function ToAbsAmount(team: number, teamAmount: number): number;   // inverse
export function NearestLaneAmount(lane: Lane, loc: Vector): number;      // absolute amount minimising GetLocationAlongLane distance; sample step Camps.LaneSampleStep (0.005)
export function DeriveMeetPoint(team: number, lane: Lane, campLoc: Vector): Vector;     // lane point nearest the camp
export function DeriveHalfMeetPoint(team: number, lane: Lane, meet: Vector): Vector;    // HalfMeetOffset units further along OUR wave's direction of travel (toward the enemy base)
export function DerivePullPath(s: Spawner, meet: Vector): Vector[];                     // [box edge point toward meet + Radii.PullPathEdge (150), meet]
export function DeriveStackExit(s: Spawner, team: number): Vector[];                    // one point Radii.StackExit (900) from the box centre, directly away from the nearest point of the team's nearest lane
```
`ToTeamAmount` is the single place that encodes "GetAmountAlongLane/GetLocationAlongLane are absolute (0 = Radiant ancient), GetLaneFrontAmount is team-relative". Put a `**TODO (in-game)**` comment and add a DEV.md TODO: OHA's `J.GetClosestTeamLane` feeds a team-relative amount straight into `GetLocationAlongLane`, so one of these assumptions may be wrong for Dire; flip `LANE_AMOUNT_TEAM_RELATIVE` constant in camps.ts if so.

`camps_data.ts`:
```ts
export interface CampDataEntry {
    key: string; team: number; type: CampType;
    laneKind?: LaneKind;                         // pull target lane relative to the camp's team; undefined = not pullable
    near?: Vector;                               // replay/measured only: camp location used to match a live spawner
    stackAggroSec?: number; stackExitPath?: Vector[];
    pullAggroSec?: number[]; halfAggroSec?: number[];
    pullPath?: Vector[]; meetPoint?: Vector; halfMeetPoint?: Vector;
    source: "seed" | "replay" | "measured";
    unverified?: boolean;                        // seed believed but not known to exist on the current map
    verifiedAt?: string;                         // dd/mm/yyyy, measured entries
}
export const DEFAULT_STACK_SEC: Record<CampType, number> = { small: 54.5, medium: 54.0, large: 53.5, ancient: 53.0 };
export const CAMP_DATA: CampDataEntry[];
```
Seed entries (both teams, so 6 entries): `radiant_safe_small` / `dire_safe_small` (`type small`, `laneKind safe`, pull `[15, 45]`, half `[17, 47]`), `radiant_safe_large` / `dire_safe_large` (`large`, `safe`, `[18, 48]`, half `[20, 50]`), `radiant_off_large` / `dire_off_large` (`large`, `off`, `[18, 48]`, half `[20, 50]`, `unverified: true`). All `source: 'seed'`, no vectors. Format (PF8, also produced by task 3's generator): pull and half arrays are `[s, s + 30]` with `s` in [0, 30); `stackAggroSec` is in [0, 60).

### Behaviour of `Resolve()`
For each spawner (in idx order):
1. If a `CAMP_DATA` entry has `near` within `ReplayMatchRadius` (600) of the spawner location, same team and type → use its explicit vectors (`derived = false`, `source` from entry).
2. Else, for seed entries with `laneKind`: the target lane is `LaneOfKind(team, laneKind)`; the spawner of that team and type nearest to that team's T1 tower of that lane (`GetTower(team, Tower.<Lane>1)`; if dead use T2) is matched, but only if that distance ≤ `PullCampMaxTowerDist` (2500). One spawner per seed entry. Pull data is derived (`derived = true`).
3. Every spawner gets stack data: `aggroSec = entry.stackAggroSec ?? DEFAULT_STACK_SEC[type]`, `exitPath = entry.stackExitPath ?? DeriveStackExit(...)`.
4. Mid pull: none unless a non-seed entry with `laneKind: 'mid'` matched (B3).
Neutral spawner `type` from the API may be a string (as in OHA) or an int (as the API doc says): normalise via a map that accepts both (`0..3` → small..ancient; TODO in-game which form).

### `lane_debug.ts`
```ts
export function Tick(bot: Unit): void;                         // subscribes "lanedebug:<team>" once per team, like index.ts htest
export function HandleMessage(team: number, msg: Chat.ChatMessage): void;   // exported for tests
export type DebugCommand = (this: void, team: number, issuer: Unit, args: string[]) => void;
export function Register(name: string, fn: DebugCommand): void;   // tasks 9/10 register hpulltest/hstacktest
```
Gated by `Config.Get().Debug` **and** `Lane.IsEnabled()`, human issuer only, any chat. Output via `HDebug.Log("lane", ...)` (console; `-condebug` captures it):
- `!hpt` → `[H:lane] hpt Vector(x, y, z)` with `%.0f` coordinates of the issuer's hero.
- `!hcamp` → nearest spawner: `[H:lane] hcamp idx=<n> team=<t> type=<type> min=Vector(...) max=Vector(...) job=<key or -> source=<src> derived=<bool>`.

### Tests (`test_lane_camps.lua`)
- `team frame conversion`: `ToTeamAmount(Dire, 0.3) == 0.7`, Radiant identity; round-trip `ToAbsAmount(ToTeamAmount(x))`.
- `lane of kind mirrors`: Radiant safe = Bot, Dire safe = Top, both off lanes opposite, mid = Mid.
- `seed pull camp matched to nearest T1`: world with two Radiant small spawners, one 1,200 from the bot-lane T1 and one 4,000 away → `PullCampsFor(Radiant, Bot)` returns exactly the near one with `aggroSec = {15, 45}`, `source = "seed"`, `derived = true`.
- `seed rejected when too far`: only spawner 3,000 from the T1 → `PullCampsFor` empty (no fabricated pull camp).
- `replay entry wins over seed`: add a `near` entry (injected by temporarily appending to `CAMP_DATA` in the test) within 500 of a spawner → resolved entry has `source = "replay"`, `derived = false`, and its explicit `meetPoint`.
- `meet point lies on lane, half meet further toward enemy`: for Radiant bot lane, `DeriveMeetPoint` y == LANE_Y[bot] and `DeriveHalfMeetPoint` x is 500 greater; for Dire top lane the half point x is 500 smaller (direction depends on team).
- `stack exit points away from lane`: exit point is farther from the lane line than the box centre.
- `every spawner gets stack data with type default`: ancient spawner `stack.aggroSec == 53.0`; small `54.5`.
- `no mid pull from seeds`: `PullCampsFor(team, Mid)` empty.
- `hpt and hcamp gated by Debug`: Debug off → no log; Debug on → `!hpt` logs a `Vector(` literal with the issuer's coordinates; `!hcamp` logs the nearest idx (capture via overriding `Utils.RawPrint`/`print` in test).

### Verification
As task 1 (build twice, `git status --porcelain` clean after second build; `npm run check`).

---

## Task 3: Replay-mining and console-log tooling

**Goal:** Phase A2 step 2 and A2 step 3's log collection, as committed, offline-tested scripts. Do not run anything against the network.

### Files (all new, plain Node ≥ 18 with no npm dependencies, plus one Go program)
- `tools/replay-mining/fetch_replays.js` — `node fetch_replays.js --count 50 --out ./replays` (CLI only, never run by tests). Uses `https` to call OpenDota `GET /api/proMatches`, then `GET /api/matches/{id}` for `replay_url`; downloads `.dem.bz2` and decompresses with the system `bunzip2` (spawned). Skips existing files. Rate-limit 1 request/s. Replays are git-ignored: add `tools/replay-mining/replays/` and `tools/replay-mining/out/` to the repo `.gitignore`.
- `tools/replay-mining/parser/main.go` + `go.mod` (module `replaymining`, requires `github.com/dotabuff/manta`). `go run ./parser <replay.dem> > out/<id>.ndjson`. Emits NDJSON events: `{"t":<game time s>,"k":"pos","hero":<slot>,"team":2|3,"x":..,"y":..}` every 0.5 s per hero; `{"k":"dmg","t":..,"src":"hero:<slot>"|"lanecreep:<team>"|"neutral","dst":"neutral:<entIdx>"|...,"campHint":[x,y]}` from the combat log; `{"k":"neutral","t":..,"ent":..,"x":..,"y":..,"alive":bool}` every 1 s; `{"k":"camp","x":..,"y":..,"type":..}` spawner boxes from the entity data at game start. Not compiled in tests; header comment documents the mapping assumptions.
- `tools/replay-mining/detect.js` — pure functions, `module.exports = { detectStacks, detectPulls, aggregate, downsamplePath, median }`:
  - `detectStacks(events, camps)`: a hero `dmg` on a neutral belonging to camp X (neutral within the camp box + 300 at the time) between second-of-minute 50 and 58, and the camp's alive-neutral count observed in the next minute (`t` in [next :00, next :05]) is greater than the count before the aggro → `{ camp, team, minute, aggroSec, path }` where `path` = that hero's positions from the aggro until its neutrals leave the box (or 6 s), downsampled to ≤ 6 points with `downsamplePath`.
  - `detectPulls(events, camps)`: a hero `dmg` on camp X's neutral, then any of those neutrals take `dmg` from `lanecreep:<hero's team>` within 15 s → pull event `{ camp, aggroSec (second of minute), meet (position of first lane-creep hit), path (hero positions aggro→meet), divert }`, `divert` = distinct lane creeps that hit those neutrals / lane creeps of that team within 1,200 of the meet point at that time. `half: divert < 0.6 && divert > 0`.
  - `aggregate(stacks, pulls)`: per camp (keyed by camp box centre rounded to 50 units and team), median `aggroSec` (every pull second normalised mod 30 into [0, 30) before the median; stack seconds kept mod 60), `halfAggroSec` median from half pulls, representative path = the event path whose aggro second is closest to the median.
  - `median(values)`; `downsamplePath(points, maxPoints, minSpacing=150)`.
- `tools/replay-mining/gen_camps.js` — reads `out/aggregate.json`, writes the `replay` entries into `typescript/bots/FunLib/humaniser/camps_data.ts` between markers `// BEGIN GENERATED REPLAY ENTRIES` / `// END GENERATED REPLAY ENTRIES` (add the empty markers to `camps_data.ts` in this task), preserving seed and measured entries. Each generated entry: `key`, `team`, `type`, `laneKind` (lane nearest the meet point relative to the team), `near`, `pullAggroSec` and `halfAggroSec` (written as `[s, s + 30]` from the mod-30 median `s`, PF8), `stackAggroSec` (mod 60), `pullPath`, `meetPoint`, `halfMeetPoint` (median meet of half pulls), `stackAggroSec`, `stackExitPath`, `source: 'replay'`. Prints a summary (camps covered, sample counts).
- `tools/replay-mining/parse_condebug.js` — `node parse_condebug.js <path to console.log>`: parses `[H:lane]` job-outcome lines (format defined in task 9: `[H:lane] job pid=<p> kind=<kind> camp=<idx> key=<key|-> aggro=<sec> planned=<sec> divert=<f> grade=<ok|mistake:...>`) and stack outcome lines in the exact format task 10 emits: `[H:lane] stack pid=<p> camp=<idx> type=<type> aggro=<sec %.1f> planned=<sec %.1f> before=<n> after=<n|?> grade=<ok|mistake:early|mistake:late|unknown>` (PF8; task 10 must emit exactly this), prints per camp/kind: attempts, success rate, median aggro error, and a suggested `measured` entry when ≥ 5 attempts and ≥ 80% `ok`. Pure core exported as `summarise(lines)`.
- `tools/replay-mining/test/fixtures/{stack_events.ndjson,pull_events.ndjson,console.log}` — small synthetic fixtures (hand-written, ~30 lines each).
- `tools/replay-mining/test/run.js` — assertion-based tests using `node:assert` (no framework).
- Modify `tests/humaniser/package.json`: add `"mining": "node ../../tools/replay-mining/test/run.js"` and change `"check"` to `"npm run syntax && npm test && npm run mining"`.

### Tests (`tools/replay-mining/test/run.js`)
- `stack detected only when count rises`: fixture with two hero hits at :54 on camp A (count 3 → 6 next minute) and camp B (count 3 → 3) → exactly one stack, camp A, aggroSec 54.
- `stack outside :50-:58 ignored`: hit at :47 with a count rise → no stack.
- `pull requires lane-creep damage within 15 s`: hit at :15 then lane-creep damage at :26 → pull; same with damage at :33 → no pull.
- `pull on wrong team creeps ignored`: neutrals damaged by the enemy team's lane creeps → no pull.
- `half pull classification`: 2 of 5 lane creeps engage → `half === true`, `divert == 0.4`; 5 of 5 → `half === false`.
- `aggregate medians`: pulls at 15, 16, 14, 45 (→15), 46 (→16) → median 15 and the generated `pullAggroSec` is `[15, 45]`; half pulls 17, 18 → `[17.5, 47.5]`; stacks at 53, 54, 55 → `stackAggroSec` 54.
- `downsample keeps endpoints and spacing`: 40 points → ≤ 6, first and last preserved, consecutive spacing ≥ 150.
- `gen_camps preserves seeds`: run generator on a temp copy of `camps_data.ts` with a 1-camp aggregate → seed entries unchanged byte-for-byte outside the markers; generated block contains `source: 'replay'`.
- `condebug summary`: fixture with 6 `ok` and 1 `mistake:half->full` half pulls for camp 12 → success 6/7, suggests a measured entry; camp with 3 attempts → no suggestion; 5 `stack` lines for camp 4 (all `ok`) → stack suggestion with median aggro.

### Verification
```bash
cd /Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h07 && npm run build && npm run build && git status --porcelain
cd tests/humaniser && npm run check     # now includes `npm run mining`
```
Do not run `fetch_replays.js` or the Go parser.

---

## Task 4: Lane state snapshot (Phase B)

**Goal:** one cached per-lane snapshot every technique decision reads.

### Files
- Create `typescript/bots/FunLib/humaniser/lane_state.ts`.
- Modify `lane.ts`: export `LaneState`; `Tick(bot)` calls `LaneState.ForBot(bot)` (keeps refresh cadence) and draws the overlay line.
- Create `tests/humaniser/test_lane_state.lua`.

### Exports
```ts
export interface CreepSummary { count: number; totalHP: number; rangedAlive: boolean; siegeAlive: boolean; units: Unit[]; lead?: Unit; }
export interface LaneHero { unit: Unit; pid: number; isBot: boolean; alive: boolean; assigned: boolean; position: number | undefined; hp: number; distToFront: number; } // dead: hp 0, distToFront math.huge
export interface LaneSnapshot {
    team: number; lane: Lane; kind: Camps.LaneKind; time: number;
    ourFront: number; enemyFront: number;          // GetLaneFrontAmount, each team-relative
    meetAmount: number;                            // our-team-relative: (ourFront + (1 - enemyFront)) / 2
    ourTowerAmount: number; theirTowerAmount: number; // our frame; nearest alive tower of each side on this lane (T1, else T2, else T3)
    eqPos: number; frontLoc: Vector;
    ally: CreepSummary; enemy: CreepSummary;       // lane creeps within 1,200 of frontLoc (enemy: visible only)
    cycleSec: number; nextWaveIn: number;          // DotaTime() % 30; 30 - cycleSec
    enemyArrivalSec?: number;                      // median cycle second at which visible enemy creeps near front first reached >= 3, last 3 cycles
    enemyWaveSizes: number[];                      // max visible enemy creeps near front per completed cycle, last 3
    allies: LaneHero[];                            // PF6: every ally assigned to this lane (alive or dead, `alive` flag) plus alive allies within 1,600 of frontLoc; consumers filter on `alive`
    desiredEq: number;                             // laneScore and XP exposure are per observer (PF7): see ScoreFor
    enemyDeniesPerCycle: number[];                 // PF8: per completed cycle (last 3), denies by visible enemy heroes (attack target = their own lane creep)
    lastAllyAggroAt: Record<number, number>;       // pid -> last time an enemy lane creep targeted that ally hero (observed)
    eqHistory: number[];                           // eqPos at each cycle end, last 4
}
export interface LaneEnemy { unit?: Unit; pid: number; visible: boolean; location: Vector; timeSinceSeen: number; position?: number; }
export function EqPos(meetAmount: number, ourTower: number, theirTower: number): number;   // clamp(2*(meet-our)/(their-our) - 1, -1, 1)
export function LaneKindOf(team: number, lane: Lane): Camps.LaneKind;
export function DesiredEq(kind: Camps.LaneKind, preRune: boolean): number;                 // Eq.Safe/Off/Mid/MidPreRune
export function LaneScore(desired: number, eqPos: number, enemyXpExposure: number): number; // desired - eqPos - XpDenyWeight*exposure
export interface ObserverView { exposure: number; laneScore: number; }
export function ScoreFor(bot: Unit, s: LaneSnapshot): ObserverView;   // PF7: exposure from this observer's Enemies(bot, s.lane); cached per pid per snapshot time
export function Get(team: number, lane: Lane): LaneSnapshot;   // cached SnapshotRefresh per (team,lane)
export function ForBot(bot: Unit): LaneSnapshot | undefined;   // bot's GetAssignedLane(); undefined if !LaneConfig.IsActive() (PF4) or invalid lane
// Get() and Enemies() also return an empty/undefined result without any engine call when !IsActive().
export function Enemies(bot: Unit, lane: Lane): LaneEnemy[];   // per observer pid, cached SnapshotRefresh
export function SetPreRune(fn: (this: void, team: number, lane: Lane) => boolean): void; // task 12 plugs mid pre-rune
export function OnRefresh(fn: (this: void, s: LaneSnapshot) => void): void;             // task 5 plan inference, task 13 counter-play
export function ResetCache(): void;
export function Describe(s: LaneSnapshot, v: ObserverView): string;   // "eq=-0.42 want=-0.70 score=0.28 a5/e4 next=12s" (score from the observer's ScoreFor)
```

### Behaviour
- **Gate (PF4)**: nothing in this module calls an engine function unless `LaneConfig.IsActive()` (Lane enabled and at least one consumer flag on).
- **Refresh** when `DotaTime() - s.time >= SnapshotRefresh`. One `GetUnitList(UnitType.AlliedCreeps)` and one `GetUnitList(UnitType.EnemyCreeps)` per team per refresh time (cache by `team` and `DotaTime()` stamp); partition lane creeps (unit name contains `creep_goodguys`, `creep_badguys`, `goodguys_siege` or `badguys_siege`; ranged = name contains `ranged`; siege = `siege`) into lanes by the smallest `GetAmountAlongLane(lane, loc).distance` (≤ `Radii.LaneAssign`, else ignored). Keep only those within `Radii.LaneCreep` of `frontLoc`. Enemy creeps with `CanBeSeen() === false` are ignored. `lead` = ally creep with the greatest team-relative amount.
- **frontLoc** = `GetLaneFrontLocation(team, lane, 0)`.
- **Tower amounts**: computed with `GetAmountAlongLane(lane, tower.GetLocation()).amount` converted with `Camps.ToTeamAmount`; cached until that tower dies.
- **eqPos** via `EqPos`, `meetAmount` as defined.
- **Wave timing**: `cycleSec = DotaTime() % 30` (TODO in-game: waves at :00/:30 on the current patch); per completed cycle record the arrival second and max size (feeds counter-play).
- **Allies** (PF6): from `GetTeamPlayers`/`GetTeamMember` (no GetUnitList), non-illusion: every member with `GetAssignedLane() === lane` (`assigned: true`, including dead ones with `alive: false`, `hp: 0`, `distToFront: math.huge`), plus alive members within `Radii.AllyNearFront` (1,600) of frontLoc; `position = LaneConfig.PositionOf(unit)`. Consumers that need living heroes filter on `alive`.
- **lastAllyAggroAt**: for each enemy lane creep in the snapshot, if `GetAttackTarget()` is an allied hero, set `lastAllyAggroAt[pid] = DotaTime()`.
- **Exposure and laneScore per observer (PF7)**: `ScoreFor(bot, s)` computes `exposure = min(1, (enemies from Enemies(bot, s.lane) that are visible or seen ≤ 3 s ago, within Radii.Exposure of frontLoc) / 2)` and `laneScore = LaneScore(s.desiredEq, s.eqPos, exposure)`. Nothing observer-dependent is stored in the shared snapshot except `enemyDeniesPerCycle` (below).
- **enemyDeniesPerCycle** (PF8): on each refresh, using the refreshing observer's visible `Enemies` entries, count enemy heroes whose `GetAttackTarget()` is one of their own lane creeps (each hero counted at most once per creep target); sum per cycle and keep the last 3 completed cycles. Perception notice delays (< 0.6 s) make this marginally observer-dependent; acceptable because only per-cycle totals are used.
- **desiredEq**: `DesiredEq(kind, preRuneFn(team, lane))` (preRune false until task 12).
- **Enemies(bot, lane)**: one `GetUnitList(UnitType.EnemyHeroes)` per observer per refresh (perception-filtered by the 03 hook since the caller is `GetBot()`); visible entries from it; for every enemy player in `GetTeamPlayers(enemyTeam)` not visible and `IsHeroAlive(pid)`, add a `visible: false` entry from `GetHeroLastSeenInfo(pid)[1]` if present. Never call methods on fogged handles.
- Overlay (`HDebug.Text(bot, "lane", ...)`, refreshed at the overlay cadence in `lane.ts`): `Describe(snapshot, ScoreFor(bot, snapshot))`; later tasks append plan and technique.

### Tests (`test_lane_state.lua`)
- `eqPos at towers and midpoint`: `EqPos(0.3, 0.3, 0.7) == -1`, `(0.7, ...) == 1`, `(0.5, ...) == 0`, beyond clamps.
- `eqPos uses next tower when T1 dead`: world with Radiant bot T1 dead and T2 at 0.2 → snapshot `ourTowerAmount == 0.2` and eqPos reflects it (fails if T1 hard-coded).
- `dire frame mirrors radiant`: identical but mirrored fronts give equal eqPos for both teams' snapshots.
- `laneScore sign`: wave pushed to enemy T1 (eqPos 1) with desired −0.7 → score < −1.5; with an enemy laner present, more negative by 0.1 (exposure 0.5 × 0.2).
- `exposure is per observer` (PF7): two observer bots; the enemy laner is in observer A's visible list but not B's (B's perception still pending, no last-seen) → `ScoreFor(A).laneScore` is 0.1 lower than `ScoreFor(B).laneScore` for the same snapshot, regardless of which observer refreshed it first.
- `dead assigned core kept` (PF6): pos 1 assigned to bot lane and dead → `allies` contains it with `alive == false`; alive pos 3 assigned elsewhere and 4,000 away → absent.
- `enemy denies tallied per cycle` (PF8): a visible enemy hero targeting its own creep on 3 refreshes in one cycle (different creeps) → after the cycle ends `enemyDeniesPerCycle[last] == 3`; no denies in the next cycle → `0` appended.
- `creeps partitioned by lane and visibility`: 3 ally creeps in bot lane, 2 in mid, 1 invisible enemy in bot → bot snapshot `ally.count == 3`, `enemy.count == 0`; `rangedAlive` true only when a ranged-named creep is present.
- `snapshot cached for 0.5 s`: count `GetUnitList` calls via a counting stub: two `Get` calls at T and T+0.2 → 1 allied + 1 enemy call; at T+0.6 → 2 each; three lanes at the same T share one call.
- `observed aggro recorded`: an enemy creep targeting ally pid 1 → `lastAllyAggroAt[1] == T`.
- `enemies use last-seen when fogged`: enemy pid 5 not in the visible list with `LAST_SEEN[5] = {..., time_since_seen = 2}` → entry `visible == false`, `timeSinceSeen == 2`; with no last-seen info → no entry.
- `disabled returns nothing`: `Lane.Enable = false`, and separately `Lane.Enable = true` with every consumer flag false (PF4) → `ForBot` nil and `GETUNITLIST_CALLS` zero; positive control: defaults in the same world → `ForBot` non-nil and `GETUNITLIST_CALLS > 0`.

### Verification
Build twice + clean status; `npm run check`.

---

## Task 5: Shared lane plan, LANE_* orders, commands and lane-front ping (B2)

**Goal:** one lane plan per lane that both laners follow, with human-plan inference, explicit overrides, and hands-off pings.

### Files
- Create `typescript/bots/FunLib/humaniser/lane_plan.ts`.
- Modify `orders.ts`:
  - Extend `OrderType` with `"LANE_FREEZE" | "LANE_SHOVE" | "LANE_PULL" | "LANE_NOPULL" | "LANE_STACK" | "LANE_HANDSOFF"`.
  - `PRIORITY` entries for all six = −1; in `acceptedFor`, skip `LANE_*` (like AVOID) when choosing `best`, so they never hide an executed order.
  - In `Post`, exclusive groups per lane: posting `LANE_FREEZE` cancels an active `LANE_SHOVE` on that lane and vice versa; `LANE_PULL` ↔ `LANE_NOPULL`.
  - `DeclineReason` returns `undefined` for `LANE_*` (a dead bot still adopts the plan after respawning).
  - New export `GetAcceptedForLane(bot: Unit, type: OrderType, lane: Lane): TeamOrder | undefined`.
  - `ackKey`: lane orders use `say_order_ack_lane_<suffix>` (no lane suffix).
- Modify `commands.ts`: add commands `freeze`, `shove`, `pull`, `nopull`, `stack`, each with optional lane word (`ParseLane`; default `laneNearest(team, issuer)`), recognised only when `LaneConfig.IsOn("Plan")` (otherwise `findCommand` ignores them, so pre-07 behaviour is unchanged). Responders: `onlyPIDs` = the selector's PIDs if given, else all bots whose `GetAssignedLane() === lane`; `maxResponders = onlyPIDs.length`; `delayKind: "chat"`; durations from `Lane.Orders` (`FreezeShove` 90, `PullNoPull` 120, `Stack` 60). `laneNearest` is module-private and takes a `Vector`: call it as `laneNearest(ctx.team, ctx.issuer.GetLocation())` inside `commands.ts`. Leave `say_cmd_help` unchanged (PF14); when `IsOn("Plan")`, the `bhelp` handler additionally queues a second line `say_cmd_help_lane` (`"Lane: !freeze/!shove/!pull/!nopull/!stack [lane]"`), so the help text is unchanged with Plan off.
- Modify `pings.ts` `Classify`: after the danger/AVOID branch and before the GATHER default, when `LaneConfig.IsOn("Plan")` and `LaneConfig.InLaningPhase()`: if the ping is within `Radii.LaneFrontPing` (600) of `GetLaneFrontLocation(team, lane, 0)` for some lane (nearest), return `LANE_HANDSOFF` for that lane, duration `Timing.PingHandsOff` (30), `onlyPIDs` = bots assigned to that lane (if none, fall through to GATHER), `ackPing: false`.
- Modify `bots/FunLib/localization.lua` (`en` table; add the same keys to `zh`, `ru`, `ja` reusing the English text if no translation is known, following how 06 did it — check): `say_order_ack_lane_freeze`, `_shove`, `_pull`, `_nopull`, `_stack`, `_handsoff` (e.g. `{"ok, freezing", "will hold it"}`, `{"ok, pushing it"}`, `{"will pull"}`, `{"no pulls"}`, `{"will stack"}`, `{"ok, leaving the wave"}`), and `say_cmd_help_lane`.
- Create `tests/humaniser/test_lane_plan.lua`.

### `lane_plan.ts` exports
```ts
export type LanePlan = "FREEZE" | "HOLD" | "SHOVE" | "NEUTRAL";
export interface CorePlanInput { skill: number; laneScore: number; eqPos: number; stronger: boolean; rotating: boolean; enemyLaners: number; }
export function PickCorePlan(i: CorePlanInput): LanePlan;
export interface CycleTally { shoveHits: number; lastHitTries: number; denies: number; aggroDraws: number; stepBacks: number; eqSum: number; samples: number; }
export function ClassifyTally(t: CycleTally): LanePlan;
export interface Inference { current: LanePlan; candidate: LanePlan; candidateSince: number; changedAt: number; }
export function Step(inf: Inference, candidate: LanePlan, now: number): Inference; // pure hysteresis
export interface PlanView {
    plan: LanePlan; source: "order" | "inferred" | "picked" | "default";
    handsOff: boolean; pullAllowed: boolean; pullForced: boolean; stackRequested: boolean;
    coreIsHuman: boolean; corePid?: number;
}
export function View(bot: Unit, s: LaneState.LaneSnapshot): PlanView;   // cached per pid per snapshot time
export function ForSupport(bot: Unit, s: LaneState.LaneSnapshot): PlanView; // View with per-cycle misread applied
export function ObserveSnapshot(s: LaneState.LaneSnapshot): void;  // registered via LaneState.OnRefresh
export function Describe(v: PlanView): string;  // "plan=HOLD(inferred)" + " handsoff" / " nopull" / " pull!" / " stack!"
```

### Behaviour
- **Core of a lane** = ally hero in `s.allies` with `assigned` true and the lowest position among positions 1–3, alive or dead (PF6); none → no core. A dead or absent core does not pick a plan: the support picks with `PickCorePlan` and its own skill (task 6/7 then apply absent-core cover).
- **PickCorePlan** (bot core): `rotating` → SHOVE; else `skill >= Gates.Freeze && stronger && enemyLaners > 0 && eqPos <= Thresholds.FreezeCoreEqMax (-0.3)` → FREEZE; else `enemyLaners === 0 && laneScore < 0` → SHOVE (free tower damage); else HOLD.
  - `rotating` = `LaneHooks.IsRotationPlanned(core)`, evaluated live on every call (PF3, PF11). Task 9 registers a probe for a camp job starting within `Timing.JobUpcoming` (10 s); task 12 registers the mid pre-rune window. `lane_plan.ts` never imports `camp_jobs`/`lane_mid`.
  - `laneScore` = `LaneState.ScoreFor(core, s).laneScore` (PF7); `stronger` = `Helpers().WeAreStronger(core, Radii.Stronger)`.
- **Human core inference**: on every snapshot refresh (`ObserveSnapshot`), for each lane whose core is a human, sample the human:
  - `target = human.GetAttackTarget()`; enemy lane creep and NOT (`target.GetHealth() <= human.GetAttackDamage() * Infer.ShoveHitDamageMult (1.3)`) → `shoveHits++`; enemy lane creep at or below that → `lastHitTries++`; allied lane creep → `denies++`.
  - an enemy lane creep targeting the human (from `s.lastAllyAggroAt[pid] === now`) while the human's target is not a creep → `aggroDraws++`.
  - human moving toward our base (team-relative amount of `GetExtrapolatedLocation(Radii.ApproachExtrapolate)` lower than the current amount by more than `Radii.StepBackEps` (50) units' worth) while ≥ 1 enemy creep within `Radii.StepBackCreeps` (700) → `stepBacks++`.
  - `eqSum += s.eqPos; samples++`. Keep the tallies of the current and previous cycle; `ClassifyTally` runs on the sum of both (rolling 1–2 cycles).
  - **ClassifyTally**: `shoveHits >= Infer.ShoveHits (4)` → SHOVE; else `shoveHits === 0 && denies >= Infer.FreezeDenies (2) && eqSum/samples <= Infer.FreezeEqMax (-0.5)` → FREEZE; else `aggroDraws + stepBacks >= Infer.HoldSignals (2)` → HOLD; else NEUTRAL.
  - **Step (hysteresis)**: if `candidate !== inf.candidate` → reset `candidateSince = now`; switch `current = candidate` only when `now - candidateSince >= PlanSustain` (5) and `now - changedAt >= PlanMinDwell` (15). Initial current = NEUTRAL.
  - Human support with bot core: the core is a bot so it picks its plan, but `ObserveSnapshot` also samples a human support in the lane: an observed aggro draw by the human counts in `lastAllyAggroAt` (single-actor rule, task 6); the human within `Radii.HumanPullRadius` (800) of one of our pull camps while the cycle second is within `Timing.HumanPullWindow` (6 s) of that camp's pull or half-pull second (the "pull window") means "human is pulling": `pullAllowed = false` for bots in that lane for the rest of that cycle (bots never contest).
- **View precedence**: (1) accepted `LANE_FREEZE`/`LANE_SHOVE` for this lane (`GetAcceptedForLane`) → that plan, source `order`; (2) inferred (human core) or picked (bot core / no core); `LaneConfig.IsOn("Plan") === false` → NEUTRAL `default`.
  - `handsOff` = accepted `LANE_HANDSOFF` for this lane.
  - `pullAllowed` = no `LANE_NOPULL` and not the human-pulling case; `pullForced` = accepted `LANE_PULL`; `stackRequested` = accepted `LANE_STACK`.
- **Misread** (`ForSupport`): once per wave cycle per pid, roll `Roll(Curve("PlanMisread", skill))`; on a hit the support uses the second-highest-scoring plan of that cycle's tally for the rest of the cycle (for bot cores: NEUTRAL). Orders are never misread. Log `[H:lane] pid=.. misread plan X as Y` (task 08 mistake).
- Overlay appends `Describe(view)` to the `lane:` line.

### Tests (`test_lane_plan.lua`)
- `core plan rules`: rotating → SHOVE even with FREEZE conditions; skill 0.8 + stronger + enemy laner + eqPos −0.5 → FREEZE; same at skill 0.6 → HOLD (freeze gate 0.7); no enemy laners and score < 0 → SHOVE.
- `tally classification`: 5 shove hits → SHOVE; 0 shove + 3 denies + mean eq −0.6 → FREEZE; same with mean −0.2 → not FREEZE; 1 aggro + 1 step-back → HOLD; only last hits → NEUTRAL.
- `hysteresis blocks flicker`: alternating SHOVE/NEUTRAL candidates every 1 s for 20 s → current stays NEUTRAL; sustained SHOVE from t=20 → current switches at t ≥ 25 and not before.
- `min dwell`: after switching to SHOVE at t=25, a sustained FREEZE candidate from t=26 does not switch before t=40.
- `human inference end to end`: human core attacking a full-HP enemy creep on 5 consecutive snapshots across 6 s (+ dwell satisfied) → `View(support).plan == "SHOVE"` with `source == "inferred"`.
- `order overrides inference`: inferred SHOVE plus accepted `LANE_FREEZE` for the lane (after the chat read delay) → FREEZE `order`; before the read delay → still SHOVE (fails if delay ignored).
- `exclusive lane orders`: posting `LANE_SHOVE` then `LANE_FREEZE` for bot lane → only the FREEZE order active; a mid-lane SHOVE is untouched.
- `lane orders never hide executed orders` (PF10): with only an accepted `LANE_FREEZE`, `Orders.GetFor(bot)` is `nil` (fails if LANE_* are not skipped, because priority −1 alone would still make it `best`); with an accepted PUSH as well → `GetFor(bot).type == "PUSH"`; `GetAcceptedForLane(bot, "LANE_FREEZE", Bot)` still returns the freeze order.
- `commands parse only with Plan on`: `!freeze bot` with `Lane = { Enable = true, Plan = false }` → no order, and `!bhelp` queues exactly one line; with Plan on → `LANE_FREEZE` lane Bot, responders = bots assigned to bot lane only, and `!bhelp` queues two lines.
- `lane-front ping hands off`: ping at the bot-lane front during laning → `LANE_HANDSOFF` lane Bot, 30 s; same ping with Plan off → GATHER (pre-07 behaviour); same ping after laning phase → GATHER.
- `misread uses second plan`: tally with SHOVE top and HOLD second, skill 0 and roll 0.1 (< 0.30) → `ForSupport` HOLD; roll 0.5 → SHOVE; skill 1 roll 0.1 (> 0.05) → SHOVE.
- `human pulling blocks bot pulls`: human support within 800 of the resolved seed pull camp (pull `[15, 45]`, half `[17, 47]`) at cycle second 14 → `View(core bot).pullAllowed == false` for the rest of that cycle; same position at second 25 of a new cycle (> 6 s from 15 and 17) → true; human 1,000 away at second 15 → true.
- `rotation probe read live` (PF3/PF11): `PickCorePlan` input built by `View` reports `rotating` false, then a registered probe returns true for the core → the next `View` call in the same snapshot window yields SHOVE (no stale cache).

### Verification
Build twice + clean status; `npm run check` (existing `test_commands.lua`/`test_pings.lua` must still pass unchanged).

---

## Task 6: Partnership rules (B2 "coordinate, don't collide")

**Goal:** roles, the single-actor aggro window, camp-job ownership, partner safety and absent-core cover as one shared rule module.

### Files
- Create `typescript/bots/FunLib/humaniser/lane_roles.ts`.
- Create `tests/humaniser/test_lane_roles.lua`.

### Exports
```ts
export type LaneRole = "core" | "support" | "solo";
export function RoleIn(bot: Unit, s: LaneState.LaneSnapshot): LaneRole; // solo when no other ally hero assigned to the lane; else core for pos 1-3, support for 4-5
export function Partner(bot: Unit, s: LaneState.LaneSnapshot): LaneState.LaneHero | undefined; // core for a support, highest-position support for a core
export function CoreBusy(core: LaneState.LaneHero, now: number): boolean;  // alive and (mid-last-hit: attack target is enemy lane creep with HP <= CoreBusyDamageMult (1.3) x core damage, or HP < CoreBusyHP (0.6))
export function NoteNeed(bot: Unit, now: number): void;   // PF9: records when this bot's need for an aggro draw began (called by LanePlanner.Plan when its choice becomes aggro_pull or a freeze/cover technique that may draw); cleared when the choice changes
export function MayDrawAggro(bot: Unit, s: LaneState.LaneSnapshot): LuaMultiReturn<[boolean, string]>;
export function NoteAggroDraw(bot: Unit, s: LaneState.LaneSnapshot): void;
export function CampJobOwner(s: LaneState.LaneSnapshot): number | undefined;  // pid
export function MayRunCampJob(bot: Unit, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[]): LuaMultiReturn<[boolean, string]>;
export function PartnerSafe(bot: Unit, s: LaneState.LaneSnapshot, enemies: LaneState.LaneEnemy[]): boolean;
export function LaneStable(bot: Unit, enemies: LaneState.LaneEnemy[]): boolean;
export function CoreAbsent(s: LaneState.LaneSnapshot): boolean;
export function CoverAbsentCore(bot: Unit, s: LaneState.LaneSnapshot, now: number): boolean;
```

### Behaviour
- **MayDrawAggro** (single-actor window, `AggroWindow` = 3.0 s):
  1. If any other ally pid has `s.lastAllyAggroAt[pid]` within the last 3.0 s, or an in-module claim by another pid is newer than 3.0 s → `false, "wait: ally-aggro"`, unless `Roll(Curve("DoubleDraw", skill))` (then `true, "mistake: double-draw"` and log it under `[H:lane]` as a mistake).
  2. Own cooldown: the bot's own last draw < `AggroCooldown` (2.3) ago → `false, "wait: cooldown"`.
  3. Bot is a core and a bot support partner exists, is alive, within `SupportNearFront` (800) of the front, and either the core is `CoreBusy` → `false, "yield: support"`, or the core's need began (from `NoteNeed`, stored per pid) less than `Timing.CoreYieldStagger` (1.5 s) ago → `false, "yield: stagger"`. This deterministic stagger gives the support the first draw without shared state. No `NoteNeed` recorded for the core → treat the need as starting now.
  4. Otherwise `true, "ok"`.
- `NoteAggroDraw` records the claim `{ pid, at }` per `(team, lane)` and per pid.
- Roles and partners consider only `alive` allies from `s.allies`, except `CoreAbsent`, which uses the assigned core even when dead (PF6).
- **CampJobOwner**: among alive bot allies assigned to the lane: the bot with the highest position (5, then 4; tie by lower pid). If a human ally with position 4 or 5 is in the lane → `undefined` (bots never take a human support's camp jobs). Solo lane: the lone bot.
- **MayRunCampJob**: `pid === CampJobOwner(s)` else `"not-owner"`; solo role requires `skill > Gates.SoloCampJob (0.6)` and `LaneStable`; partner must be `PartnerSafe`; `InLaningPhase()` required for lane camp jobs (post-laning stacking is task 10's rule).
- **PartnerSafe**: partner HP ≥ `PartnerMinHP` (0.4) and fewer than `PartnerDangerEnemies` (2) `visible` enemies within `PartnerDangerRadius` (1,200) of the partner. No partner → true.
- **LaneStable** (stacking): no enemy (visible, or not visible with `timeSinceSeen <= 3`) within 1,200 of the bot, and bot HP > 50%.
- **CoreAbsent** (PF6, PF14): the lane's assigned core (from `s.allies`, alive or dead) is dead or `distToFront > Thresholds.CoreAbsentDist` (1,200). The spec's "away for more than one wave cycle" is subsumed by the distance rule, so there is no separate timer. No core assigned → false.
- **CoverAbsentCore**: on each new absence (rising edge) roll once `Roll(Curve("CoverAbsentCore", skill))`, keep the result until the core returns; `true` means the support holds the wave near our tower (task 7 maps this to freeze if known, else aggro pull, else hold position).

### Tests (`test_lane_roles.lua`)
- `roles`: pos 1 + pos 5 in bot lane → core / support; lone mid → solo.
- `support waits after ally aggro`: enemy creep targeted the human core 2 s ago → support `MayDrawAggro` false `"wait: ally-aggro"`; 3.5 s ago → true.
- `low skill double-draws sometimes`: same as above, skill 0, roll 0.1 (< 0.2) → true with reason `mistake: double-draw`; skill 1 never (curve 0).
- `own cooldown`: support drew at T, asks at T+2 → false; T+2.4 → true.
- `busy core yields`: bot core mid-last-hit with healthy support partner → `yield: support`; core at 55% HP idle → `yield: support`; healthy idle core with `NoteNeed(core, T)` asked at T+1.0 → `yield: stagger`, at T+1.6 → true; same core with no support partner at T+0.1 → true (stagger only applies when a support can draw).
- `camp owner`: bot pos4 + bot pos5 + bot pos1 → owner pid of pos 5; pos 5 human → undefined; solo mid bot → itself.
- `solo camp job gate`: solo bot skill 0.6 → false (strictly above), 0.61 and stable → true; 0.9 with an enemy seen 2 s ago 1,000 away → false.
- `partner safety`: partner 39% HP → unsafe; 2 visible enemies within 1,200 → unsafe; 2 fogged enemies (last seen 1 s) → safe (only visible counts here, per spec).
- `core absent`: dead assigned core (still in `s.allies` with `alive = false`) → absent; 1,300 away → absent; 900 away → not; no core assigned → not absent.
- `cover roll once per absence`: skill 0 roll 0.5 (> 0.3) → no cover for the whole absence even if asked repeatedly with later rolls 0.1; after the core returns and leaves again, a new roll 0.1 → cover.

### Verification
Build twice + clean status; `npm run check`.

---

## Task 7: Technique planner (Phase C decision only)

**Goal:** pick at most one technique per wave cycle, owner-only, skill-gated, with attempt-rate rolls. No unit actions in this task. The decision is re-evaluated live on every call (PF3) so orders, pings, rotations and the pre-rune window take effect mid-cycle; only the attempt roll and the committed technique are remembered per cycle (PF14).

### Files
- Create `typescript/bots/FunLib/humaniser/lane_planner.ts`.
- Create `tests/humaniser/test_lane_planner.lua`.

### Exports
```ts
export interface PlannerInput {
    skill: number; role: LaneRoles.LaneRole; isMid: boolean; now: number; dotaTime: number;
    plan: LanePlan.PlanView; laneScore: number; eqPos: number;
    allyCreeps: number; enemyCreeps: number; enemyLaners: number;
    pullCamp: boolean; stackedPullCamp: boolean;      // a pull camp exists for this lane; we stacked it (task 10)
    mayRunCampJob: boolean; partnerSafe: boolean; coverAbsentCore: boolean;
    rotationPlanned: boolean; humanCoreInLane: boolean; desiredEq: number;
    override?: LaneConfig.Technique;                  // LaneHooks.TechniqueOverride (task 13 counter-play)
}
export type Choice = { tech: LaneConfig.Technique | "hold" | "none"; reason: string };
export function Choose(i: PlannerInput): Choice;               // pure; no rolls
export function Plan(bot: Unit, s: LaneState.LaneSnapshot): Choice; // builds input and runs Choose on every call; applies the per-cycle attempt roll and commit lock
export function Current(bot: Unit): Choice | undefined;        // last result of Plan for this pid
export function Commit(bot: Unit, tech: LaneConfig.Technique | "contest"): void; // executor calls this when the technique actually starts; locks the cycle (PF14)
export function Committed(bot: Unit): LaneConfig.Technique | "contest" | undefined; // committed technique of the current cycle, if any
```

### `Choose` rules, first match wins (reasons in quotes)
1. `plan.handsOff` → none `"handsoff"`.
2. `dotaTime >= 0 && dotaTime < Timing.BlockEnd (30)` and `Knows("block")` and (role is support or solo, or role is core and not `humanCoreInLane` per resolution of the C/B2 conflict) → block `"0:00 block"`.
3. `override` set and known → that technique `"counter: <tech>"` (task 13); then `rotationPlanned && plan.plan !== "FREEZE" && Knows("shove")` → shove `"shove before rotating"`.
4. `plan.plan === "SHOVE"`: core/solo → shove if known `"plan shove"`; support → shove if known (support adds damage only under SHOVE) else none.
5. `coverAbsentCore` (support): freeze if known `"cover core: freeze"`, else aggro_pull if known and `laneScore <= AggroCorrectBelow`, else hold `"cover core: hold"`.
6. `plan.plan === "FREEZE"`, in this order (PF14, no forward reference):
   a. half pull when `laneScore <= SmallDriftBelow`, `allyCreeps >= enemyCreeps + LargeWaveMargin (2)`, `pullCamp && plan.pullAllowed && mayRunCampJob && partnerSafe && Knows("half_pull")` → half_pull `"freeze: thin large wave"`;
   b. core/solo with `eqPos > desiredEq + Thresholds.FreezeDriftMargin (0.2)` and `Knows("aggro_pull")` → aggro_pull `"freeze: drag back"` (this replaces the earlier idea of task 8 starting an aggro pull on its own, so it goes through the attempt roll and commit lock);
   c. freeze if known (support: deny/zone, never hit the wave) `"plan freeze"`, else hold.
   FREEZE never reaches rules 7–9.
7. Full pull band `laneScore <= FullPullBelow (-0.5)` or `plan.pullForced`: requires `pullCamp && plan.pullAllowed && mayRunCampJob && partnerSafe` (PF1: HOLD does not block pulls; FREEZE already returned in rule 6):
   - `stackedPullCamp && Knows("stack_pull") && enemyLaners > 0` → stack_pull `"deny: stacked camp"`
   - `Knows("full_pull")` → full_pull
8. Small drift `laneScore <= SmallDriftBelow (-0.2)`: `pullCamp && plan.pullAllowed && mayRunCampJob && partnerSafe && Knows("half_pull")` → half_pull; else continue.
9. `laneScore <= AggroCorrectBelow (-0.15) && Knows("aggro_pull")` → aggro_pull `"small correction"`.
10. otherwise none `"lane fine"`.
- `isMid`: rules 7–8 only if `pullCamp` is true (mid pull camp only exists when non-seed data says so).

### `Plan` (per bot, per wave cycle)
- Builds `PlannerInput` from `LaneState.ForBot`, `LaneState.ScoreFor(bot, s)` (laneScore, PF7), `LanePlan.ForSupport` (supports) / `View` (others), `LaneRoles`, `Camps.PullCampsFor`, `LaneHooks.IsStacked(pullCampIdx)` (`stackedPullCamp`, PF11), `LaneHooks.IsRotationPlanned(bot)` (live, PF3) and `LaneHooks.TechniqueOverride(bot)`. No import of `camp_jobs`, `stacking`, `lane_mid` or `counterplay`.
- `Choose` runs on every call (PF3), so a new LANE order, a lane-front ping (`handsOff`), a rotation probe turning true or entering the mid pre-rune window changes the result immediately.
- **Attempt roll**: when `Choose` returns a technique (not `hold`/`none`), look up the roll cached under `(pid, cycle index floor(DotaTime()/30), tech)`; if absent, roll `Roll(Curve("AttemptRate", skill))` once and cache it. Failure → `{ tech: "none", reason: "skip: attempt-roll <tech>" }`. `pullForced` or `stackRequested` bypass the roll. Draw order: exactly one `RandomFloat` per new `(cycle, tech)`.
- **One technique per cycle (PF14)**: if `Committed(bot)` is set for the current cycle and `Choose` returns a different technique → `{ tech: "none", reason: "one per cycle (<committed>)" }`. The committed technique itself keeps being returned while `Choose` still selects it. `hold`/`none` and `handsOff` are always returned as is. The lock clears when the cycle index changes. Executors (tasks 8, 9) call `Commit` when the technique starts; a finished camp job therefore cannot start a second technique in the same cycle.
- When the result is `aggro_pull` (or freeze/cover choices that may draw aggro) and the previous result for this pid was different, call `LaneRoles.NoteNeed(bot, now)` (PF9).
- Overlay: `tech=<tech> (<reason>)`.

### Tests (`test_lane_planner.lua`) — mostly on `Choose`, plus `Plan` roll tests
- `half pull gated at 0.6` (scenario 3): small drift (score −0.3), pull camp, all safe; skill 0.9 → half_pull; skill 0.55 → aggro_pull (half pull unknown, aggro known); skill 0.4 → none (below both gates).
- `full pull when pushed to enemy T1` (scenario 2): score −1.6, skill 0.9 → full_pull.
- `no pull when partner in danger` (scenario 7): as above with `partnerSafe = false` → not a pull (aggro_pull or none).
- `no full pull while core freezes`: plan FREEZE, score −1.0, support skill 0.9 → freeze, never full_pull; with ally 7 vs enemy 4 creeps and score −0.3 → half_pull.
- `full pull allowed under HOLD` (PF1, scenario 2/11): plan HOLD picked by a bot core, score −1.6, support skill 0.9, camp, owner, safe → full_pull.
- `freeze drag back`: plan FREEZE, core skill 0.8, eqPos = desiredEq + 0.3 → aggro_pull reason `freeze: drag back`; eqPos = desiredEq + 0.1 → freeze.
- `counter override`: `override = "shove"` with plan HOLD for a support skill 0.5 → shove `counter: shove`; skill 0.3 → not shove.
- `support never shoves unless plan shove`: plan HOLD, score +0.5, support → not shove; plan SHOVE → shove.
- `stack pull needs stack and 0.75`: stacked + enemy laner + skill 0.8 → stack_pull; skill 0.7 → full_pull; not stacked → full_pull.
- `handsoff beats everything`: handsOff with block time and pull band → none.
- `block at game start`: dotaTime 5, support skill 0.3 → block; skill 0.29 → not block; core with human core in lane → not block; support with human core in lane → block (scenario 12).
- `cover absent core`: support skill 0.8 → freeze; skill 0.55 with score −0.3 → aggro_pull; skill 0.3 → hold.
- `pull forced bypasses band`: score +0.1 with `pullForced` and camp → full_pull.
- `non-owner never pulls`: `mayRunCampJob = false` with score −1.6 → aggro_pull (skill ≥ 0.5) not a pull.
- `attempt roll`: `Plan` with skill 0.9 (rate 0.78) roll 0.5 → technique kept; skill 0.4 shove case (rate 0.43) roll 0.5 → `skip: attempt-roll shove`; a second call in the same cycle with queue `{0.0}` returns the same skip (roll cached, no new draw consumed: the queue entry is still unread afterwards); next cycle with `{0.0}` → shove.
- `ping mid-cycle stops technique` (PF3, scenario 12): `Plan` returns full_pull at cycle second 5; a `LANE_HANDSOFF` for the lane is accepted at second 10 → the next `Plan` in the same cycle returns none `handsoff` (fails with a per-cycle decision cache).
- `pre-rune window mid-cycle` (PF3): a rotation probe that turns true at cycle second 12 → `Plan` at second 12 returns shove although it returned none at second 3 of the same cycle.
- `one technique per cycle` (PF14): `Plan` → full_pull, `Commit(bot, "full_pull")`, then the world changes so `Choose` would give aggro_pull in the same cycle → none `one per cycle (full_pull)`; next cycle → aggro_pull.

### Verification
Build twice + clean status; `npm run check`.

---

## Task 8: In-lane techniques and laning `Think()` hooks

**Goal:** execute block, aggro pull (and drop), tower-aggro drop, freeze positioning and shove inside the owned laning `Think()`; decide ownership via `Lane.OwnLaningThink`.

### Files
- Create `typescript/bots/FunLib/humaniser/lane_tech.ts`.
- Modify `lane.ts`: export `OwnsLaning`, `PreThink`, `Think`, `AdjustPosition`, `PickDeny` (returns undefined until task 12), `SupersedesHarass` (false until task 11).
- Modify `localization.lua`: `say_lane_shove_rotate = {"shoving then rotating"}` (en + other tables, PF14: used by the shove-before-rotating start below).
- Modify `bots/mode_laning_generic.lua` (minimal diff). Keep `bHumaniserLaning = AllyLastHit.OwnsLaning(bot)` and `fLastHitFilter` exactly as they are (04's last-hit filter stays tied to 04's ownership, so enemy bots under `'all'` do not get 04 etiquette; task 11 replaces the harass step with the shared tool). Add below them:
  ```lua
  local Lane = J.Humaniser.Lane
  local bLaneLaning = Lane.OwnsLaning(bot)
  ```
  and change the `Think()` definition condition to `if local_mode_laning_generic or (J.GetPosition(bot) == 1 and J.IsPosxHuman(5)) or bHumaniserLaning or bLaneLaning then`. For a bot owned only by 07, `fLastHitFilter` is nil, so the existing last-hit code applies upstream's own rule unchanged. Inside `Think()`:
  - first line: `if bLaneLaning and Lane.PreThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end`
  - deny: `local denyCreep = (bLaneLaning and Lane.PickDeny(bot, nAllyCreeps)) or GetBestDenyCreep(nAllyCreeps)`
  - after deny, before 04's harass: `if bLaneLaning and Lane.Think(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end`
  - 04's harass line `if bHumaniserLaning and HarassThink() then return end` is left unchanged in this task; task 11 replaces it with the shared-tool call
  - before the final move: `if bLaneLaning then target_loc = Lane.AdjustPosition(bot, target_loc) end`
- Create `tests/humaniser/test_lane_tech.lua`.

### Exports
```ts
export function OwnsLaning(bot: Unit): boolean;   // load-time decision
export function PreThink(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[]): boolean;
export function Think(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[]): boolean;
export function AdjustPosition(bot: Unit, loc: Vector): Vector;
export function BlockPoint(lead: Vector, dirAmountSign: number, lane: Lane, ahead: number, side: number): Vector; // pure, for tests
export function ShoveTarget(bot: Unit, enemyCreeps: Unit[]): Unit | undefined; // pure-ish: lowest-HP visible enemy lane creep not within EnemyTowerRange of an enemy tower
export function HoldPoint(team: number, lane: Lane, eq: number, ourTower: number, theirTower: number, back: number): Vector; // lane point at the eq value, shifted `back` toward our base
```

### Behaviour
- **OwnsLaning**: `LaneConfig.IsActive()` and at least one of `Block, AggroPull, Freeze, Shove, Harass, Mid` is on, and mode `'all'` → true; `'allies'` → `Difficulty.IsAllyOfHuman(bot)`; `'off'` → false. Decided once at file load (as 04).
- All entry points return false immediately when `!OwnsLaning`-relevant flags are off, `LaneState.ForBot(bot)` is undefined, or the bot is not within `Radii.LaneActive` (2,500) of its lane front.
- **Commit (PF14)**: each technique calls `LanePlanner.Commit(bot, tech)` on its first executed action; a technique only starts when `LanePlanner.Plan(bot, s).tech` names it (in-lane code never starts a technique the planner did not choose, so the attempt roll and one-per-cycle lock always apply).
- **PreThink** runs the active state machine for the current technique (per pid state `{ tech, phase, startedAt, ... }`):
  - **block** (from `Plan` choice `block` while `DotaTime() < BlockEnd` and enemy creeps are > `Radii.BlockContact` (700) from our lead creep): move to `BlockPoint(lead, +1/-1 for team, lane, ahead = Radii.BlockAhead (120) + pathNoise, side = ±Radii.BlockSide (50) alternating every Timing.BlockNoiseEvery (1) s)` each frame; `pathNoise = RandomFloat(-1, 1) * Curve("PathNoise", skill)` sampled once per `BlockNoiseEvery`. Ends when `DotaTime() >= BlockEnd`, enemy creeps within `BlockContact` of the lead, or the bot is > `Radii.BlockLost` (400) from the lead for `Timing.BlockLostSec` (2) s (then log `mistake: block-lost`). Bots not within `Radii.BlockStart` (1,500) of the wave at 0:00 move toward it first.
  - **aggro_pull** phases: `draw` → if `LaneRoles.MayDrawAggro` is false, wait (re-check each frame while the planner still chooses aggro_pull; reason on the overlay); find the nearest visible enemy hero within attack range + `Radii.AggroDrawExtra` (200) not within `EnemyTowerRange` (850) of an enemy tower; `Action_AttackUnit(hero, true)`; `Commit`; `NoteAggroDraw`; → `walk` for `WalkBack` (1.5) s toward `HoldPoint(..., eq = s.eqPos - Planner.AggroStepEq (0.15), back = Radii.AggroWalkBack (300))` (at most `Radii.AggroWalkMax` (400) units) → `drop`: `Action_AttackUnit(nearestAlliedLaneCreepInRange, true)` once (the deny command drops creep aggro; TODO in-game: does the drop work when the allied creep is above 50% HP and the attack order is refused?) → done; no further technique this cycle (commit lock).
  - **tower-aggro drop** (part of AggroPull flag, gate 0.5): whenever an enemy tower within `Radii.TowerAggro` (900) has `GetAttackTarget() === bot`, attack the nearest allied lane creep or allied hero in range once, then move out to `TowerAggro + Radii.TowerExitMargin` (1,000) from that tower. This is a safety reaction, not a planned technique: it is exempt from the planner, attempt roll and commit lock. Also **draw tower aggro off an ally** (a planned technique: only when the planner's choice is aggro_pull): allied core targeted by an enemy tower with HP < `Thresholds.TowerSwapAllyHP` (0.6), the bot HP > `TowerSwapBotHP` (0.6) and `MayDrawAggro` → attack an enemy hero within the tower's range once, then the drop sequence. TODO in-game for both.
- **Think** (stateless per frame, after last hit and deny):
  - **shove**: if the planner's choice is shove and `Helpers().WeAreStronger(bot, Radii.Stronger)` and HP ≥ `Thresholds.ShoveMinHP` (0.5): `Action_AttackUnit(ShoveTarget(...), true)`, `Commit`; never under an enemy tower; ends when ≤ `Thresholds.ShoveDoneCreeps` (1) visible enemy creep near the front, after `Timing.ShoveMaxSec` (8) s, or when the rotation starts. When the reason is `shove before rotating` and the bot is an ally of a human with `Telegraph` on, say `say_lane_shove_rotate` once at the start (`Orders.Say`, `Timing.ShoveTelegraphCooldown` 60 s; PF14).
  - **freeze** (core or solo): never attack enemy creeps except the existing last-hit path (already in Think). Dragging the wave back is the planner's `freeze: drag back` aggro_pull choice (task 7 rule 6b), executed by PreThink like any aggro pull; `lane_tech` does not start it on its own (PF14).
  - **freeze (support)** / **hold**: no swings at enemy creeps; zone: if an enemy laner is visible within `Radii.Zone` (900) of the front, stand between it and our lead creep (position override, see AdjustPosition).
  - Under plan FREEZE no technique may hit enemy creeps except last hits (assert in tests).
- **AdjustPosition**: freeze/hold/cover → `HoldPoint(team, lane, s.desiredEq, ..., back = max(attackRange, 250))`; zoning support → point `Radii.ZoneOffset` (150) from our lead creep toward the visible enemy laner; otherwise `loc` unchanged (the same table).
- **Logging**: each technique start `[H:lane] pid=.. tech=<tech> @<cycleSec %.1f> reason=<reason>`; mistakes `[H:lane] mistake pid=.. <kind>` (also used by task 08).
- Overlay: `tech=<tech>@<sec> <phase>`.

### Tests (`test_lane_tech.lua`) — use `lane_world.lua` action recorder
- `owns laning by mode`: `'all'` → true for an enemy-team bot with no humans; `'allies'` → false for it, true for an ally of a human; `'off'` → false; all in-lane flags off with `'all'` → false.
- `04 ownership unchanged under 'all'` (PF5): with `OwnLaningThink = 'all'`, an enemy-team bot has `Lane.OwnsLaning` true but `AllyLastHit.OwnsLaning` false (so the Lua keeps `fLastHitFilter` nil for it).
- `block stands ahead of lead creep`: Radiant bot lane, lead creep at x=−3000 → the issued move target has x > −3000 and |y − LANE_Y| ≤ 50 + noise; Dire mirrored (x < lead x). Fails if no move is issued.
- `block ends on contact`: enemy creep within 700 of the lead → PreThink returns false and issues no move.
- `aggro pull sequence`: skill 0.8, choice aggro_pull, enemy hero in range → frame 1 records `kind == "AttackUnit"`, `args[1] == hero`, `args[2] == true` (PF12) and `LanePlanner.Committed(bot) == "aggro_pull"`; frames during 1.5 s → moves toward our base (x decreasing for Radiant); then one `AttackUnit` with `args[1]` an allied creep and `args[2] == true`; then PreThink returns false.
- `aggro pull aborted by ally aggro`: enemy creep targeted the partner 1 s ago → no `AttackUnit(hero)` is issued (skill 1 so no double-draw).
- `no aggro under enemy tower`: the only enemy hero is within 850 of an enemy tower → no attack issued.
- `tower aggro drop`: enemy tower targeting the bot → one attack on an allied creep, then move out beyond 1,000 from the tower; this happens even when the planner's choice is none (safety reaction).
- `shove telegraph` (PF14): ally of a human, choice shove with reason `shove before rotating` → one `say_lane_shove_rotate` line; reason `plan shove` → no line.
- `shove respects plan`: support with plan HOLD and choice none → `Think` issues no attack on enemy creeps; plan SHOVE + stronger → attacks the lowest-HP enemy creep not under the tower.
- `freeze never hits wave`: plan FREEZE, full-HP enemy creeps in range → no `AttackUnit` on enemy creeps from `Think`; `AdjustPosition` returns a point nearer our tower than the input.
- `disabled hooks are inert` (PF10): `Lane.Enable = false` → `PreThink`/`Think` false, `AdjustPosition` returns the same vector object, zero actions recorded; positive control in the same world with defaults and plan SHOVE + stronger → `Think` true and one `AttackUnit` recorded.

### Verification
Build twice + clean status; `npm run check` (also confirms `mode_laning_generic.lua` parses).

---

## Task 9: Camp-job executor and pulls (full, half, double), farm hooks, `!hpulltest`

**Goal:** run pulls as camp jobs in `mode_farm_generic.lua`, timed and measured.

### Files
- Create `typescript/bots/FunLib/humaniser/camp_jobs.ts`.
- Modify `lane.ts`: export `CampJobDesire`, `CampJobThink`, `CampJobOnEnd`; register `hpulltest` with `LaneDebug.Register`.
- At module load, `camp_jobs.ts` registers `LaneHooks.SetRotationProbe(bot => UpcomingWithin(bot, Timing.JobUpcoming))` (PF11); `lane_planner.ts` and `lane_plan.ts` are not modified and never import `camp_jobs`.
- Modify `bots/mode_farm_generic.lua`:
  - In `GetDesireHelper`, immediately after the `runMode` block (before `if not bInitDone`):
    ```lua
    local nLaneJobDesire = J.Humaniser.Lane.CampJobDesire(bot)
    if nLaneJobDesire > 0 then return nLaneJobDesire end
    ```
  - In `Think`, after `if J.CanNotUseAction(bot) then return end`: `if J.Humaniser.Lane.CampJobThink(bot) then return end` (before the ThinkLess throttle, because aggro timing must not be delayed by it).
  - In `OnEnd`: `J.Humaniser.Lane.CampJobOnEnd(bot)` as the first line.
- Modify `bots/FunLib/localization.lua`: `say_lane_pulling_in_5 = {"pulling in 5"}`, `say_lane_half_pull = {"half pull"}` (en + other tables; `say_lane_shove_rotate` was added in task 8).
- Create `tests/humaniser/test_lane_camp_jobs.lua`.

### Exports
```ts
export type JobKind = "full_pull" | "half_pull" | "stack_pull" | "double_pull" | "stack" | "contest";
export interface JobRequest { kind: JobKind; campIdx: number; secondCampIdx?: number; forced?: boolean; minute?: number; }
export interface Job extends JobRequest {
    phase: "travel" | "wait" | "aggro" | "lead" | "watch" | "exit" | "return" | "done";
    aggroAt: number;  // DotaTime() of planned aggro (aggroSec + jitter)
    plannedSec: number; path: Vector[]; meet?: Vector; startedAt: number; peakDivert: number; waveSize: number;
}
export function AggroSecondsFor(kind: JobKind, data: Camps.CampJobData): number[]; // pull/stack_pull/double: pull.aggroSec; half: halfAggroSec ?? aggroSec+2
export function NextAggroTime(dotaTime: number, seconds: number[], period: number): number; // next absolute time whose (t % period) equals one of `seconds` (period 60 for pulls/stacks; pull seconds already cover both halves)
export function TravelTime(dist: number, speed: number): number;
export function WindowOpen(now: number, aggroAt: number, travel: number): boolean; // START gate only (PF2): now >= aggroAt - travel - JobStartSlack (3) && now <= aggroAt + JobStartLate (2)
export function MeasureDivert(allyCreeps: Unit[], waveSize: number): number;       // count with GetAttackTarget() being a neutral (team NEUTRAL) / waveSize
export function Grade(kind: JobKind, divert: number): string;  // "ok" | "mistake:half->full" | "mistake:weak-pull" | "mistake:no-divert"
export function Start(bot: Unit, req: JobRequest): boolean;     // validates camp + data; replaces any job
export function Current(bot: Unit): Job | undefined;
export function UpcomingWithin(bot: Unit, seconds: number): boolean; // an existing job in travel/wait with aggroAt - now <= seconds; never calls LanePlanner (avoids probe recursion)
export function Active(bot: Unit): boolean;  // a job exists and is not done/aborted
export function Desire(bot: Unit): number;   // Timing.JobDesire (0.7; contest: ContestDesire 0.65) while a job is active (PF2), else 0
export function Think(bot: Unit): boolean;   // true when it issued an action this frame
export function OnEnd(bot: Unit): void;
```

### Behaviour
- **Scheduling (laning phase)**: each frame from `Desire`: if no job and `LanePlanner.Plan(bot, s).tech` is `full_pull`/`half_pull`/`stack_pull`, and `WindowOpen(now, nextAggro, travel)` holds (travel ≤ `Timing.MaxTravel`), create the job for the first camp in `Camps.PullCampsFor(team, lane)` (`stack_pull`: the camp we stacked, task 10). `double_pull` = `full_pull` when a second pull camp exists for the lane and skill ≥ `Gates.StackPull` (0.75): after the first camp's neutrals engage (divert > 0) and if `NextAggroTime` for the second camp is within `Timing.DoublePullReach` (8 s), lead the second camp into the same wave (same job, same commit).
- `aggroAt = NextAggroTime(DotaTime(), seconds, 60) + LaneConfig.Jitter(skill)`, computed once at job start (low skill: late/early pulls emerge here).
- **Desire** (PF2): `WindowOpen` only gates *starting* a job. Once started, a job keeps `JobDesire` (0.7) through travel, wait, aggro, lead and watch until it reaches `done` or aborts. It is 0 when `!LaneConfig.IsActive()`, the relevant flag is off, the bot is dead, `LaneRoles.MayRunCampJob` turns false (abort; forced debug jobs skip only the owner check), `plan.handsOff` becomes true (abort), or `now > aggroAt + Timing.JobMaxAfterAggro` (15 s, hard stop).
- **Commit**: the job calls `LanePlanner.Commit(bot, tech)` when it is created (PF14; `double_pull` commits `"full_pull"`, `contest` commits `"contest"`, other kinds commit their own name); after it finishes, no other technique starts in that cycle.
- **Think** phases:
  - `travel`: `Action_MoveToLocation(stand)` where stand = the box edge point on the side of the first path waypoint (offset `Radii.StandOffset` (150) outside the box), with path noise.
  - `wait`: hold near stand until `aggroAt`; `Timing.PullTelegraphLead` (5) s before, if `Telegraph` on and the bot is an ally of a human: `Orders.Say(bot, "say_lane_pulling_in_5", PullTelegraphCooldown)` (half pull: `say_lane_half_pull`).
  - `aggro`: pick a visible neutral (`bot.GetNearbyNeutralCreeps(Radii.NeutralSearch)`) inside the camp box; `Action_AttackUnit(creep, true)`; record actual aggro second; if no neutral visible at `aggroAt + 1` → abort, log `grade=mistake:no-camp`.
  - `lead`: walk `path` waypoints (each offset by `RandomVector(PathNoise)`), ending at `meet` (`halfMeetPoint` for half pulls).
  - `watch`: up to `Timing.WatchSec` (8) s after reaching meet: every 0.25 s compute `MeasureDivert(allied lane creeps within Radii.MeetWatch (800) of meet, waveSize)` where `waveSize` = ally lane creeps within `Radii.WaveSize` (1,200) of meet when the first neutral engages (at least 1); keep the peak.
  - `return`: job done (the cycle stays committed); log `[H:lane] job pid=<p> kind=<kind> camp=<idx> key=<key|-> aggro=<actual %.1f> planned=<plannedSec %.1f> divert=<peak %.2f> grade=<Grade>` (task 3's parser reads this exact format).
- **Grade**: full/stack/double: `divert > 0.8` ok, `> 0` `mistake:weak-pull`, `0` `mistake:no-divert`; half: 0.3–0.6 ok, `> 0.6` `mistake:half->full`, `< 0.3` `mistake:weak-pull`.
- **`!hpulltest <idx> [half]`** (Debug): the nearest bot of the issuer's team starts `{ kind: full_pull|half_pull, campIdx, forced: true }` (bypasses planner and owner checks, not safety in combat); logs the job line.
- Overlay: `job=<kind>@<plannedSec> <phase> out=<divert>`.

### Tests (`test_lane_camp_jobs.lua`)
- `next aggro time`: at 12.0 with [15, 45] → 15; at 16.0 → 45; at 50.0 → 75.
- `window opens with travel`: aggro at 75, travel 9 → open at 63, closed at 62.9 and at 77.1 (start gate only).
- `jitter scales with skill`: with a fixed Gaussian draw of +1, skill 0 job `aggroAt` = base + 1.5, skill 1 = base + 0.2.
- `half uses half seconds`: half job on seed small camp → seconds {17, 47}; meet = halfMeetPoint.
- `divert measurement`: 4 of 5 ally creeps targeting neutrals → 0.8; grade full: 0.8 → `mistake:weak-pull` (strictly above 0.8), 0.85 → ok; half 0.45 → ok, 0.7 → `mistake:half->full`.
- `desire only inside window`: support owner with a planned full pull → desire 0.7 inside the start window, 0 at 10 s before it opens, 0 for a non-owner bot, 0 with `FullPull = false`.
- `desire held through execution` (PF2): job started at aggro 75 → at 80 (lead phase) and 84 (watch phase) `Desire` is still 0.7 although `WindowOpen` is false; after the job reaches `done` → 0; a job stuck in watch at 90.1 (> aggroAt + 15) → 0 and phase `return`.
- `handsoff aborts job`: a `LANE_HANDSOFF` accepted mid-travel → next `Desire` 0 and no further actions.
- `no second technique after job` (PF14): after a full pull finishes at cycle second 25, the planner's next choice in the same cycle is none `one per cycle (full_pull)`.
- `rotation probe registered` (PF11): with a job in wait phase 8 s before aggro, `LaneHooks.IsRotationPlanned(bot)` is true; 12 s before → false.
- `phases issue actions`: in-window travel issues a move; at `aggroAt` with a visible neutral in the box exactly one action with `kind == "AttackUnit"`, `args[1] == neutral`, `args[2] == true`; then moves along the path; final waypoint equals meet within noise.
- `abort when partner endangered`: partner drops to 30% HP mid-travel → next `Desire` 0 and job phase `return`.
- `job log format`: completed job prints a line matching `^%[H:lane%] job pid=%d+ kind=%w+ camp=%d+ key=[%w_%-]+ aggro=%-?%d+%.%d planned=%-?%d+%.%d divert=%d%.%d%d grade=%S+$`.
- `hpulltest debug only`: Debug off → no job; on → nearest bot has a forced job.
- `farm hook inert when off` (PF10): `Lane.Enable = false` → `CampJobDesire` 0 and `CampJobThink` false with no actions; positive control: same world with defaults inside the pull window → `CampJobDesire` 0.7 and `CampJobThink` true with one move recorded.

### Verification
Build twice + clean status; `npm run check`.

---

## Task 10: Stacking (Phase D), stack pull, `!hstacktest`

### Files
- Create `typescript/bots/FunLib/humaniser/stacking.ts`.
- Modify `camp_jobs.ts`: implement `stack` job phases; `stack_pull` uses `Stacking.IsStacked` (`camp_jobs` may import `stacking`; `stacking` must not import `camp_jobs`; job creation for stacks is driven from `camp_jobs.Desire` calling `Stacking.WantsStack`).
- At module load `stacking.ts` registers `LaneHooks.SetStackedProbe(IsStacked)` (PF11); `lane_planner.ts` already reads `LaneHooks.IsStacked` (task 7) and is not modified.
- Modify `lane.ts`: register `hstacktest`.
- Modify `localization.lua`: `say_lane_stacked_big = {"stacked big camp"}`.
- Create `tests/humaniser/test_lane_stacking.lua`.

### Exports
```ts
export function Eligible(bot: Unit, s: LaneState.LaneSnapshot | undefined, enemies: LaneState.LaneEnemy[]): LuaMultiReturn<[boolean, string]>;
export function ChooseCamp(bot: Unit, s: LaneState.LaneSnapshot | undefined, minute: number): Camps.CampJobData | undefined;
export function WantsStack(bot: Unit, minute: number): Camps.CampJobData | undefined;  // eligibility + per-minute attempt roll (cached per pid per minute)
export function NoteStackAttempt(campIdx: number, minute: number, countBefore: number): void;
export function NoteStackOutcome(campIdx: number, minute: number, countAfter: number): void;
export function IsStacked(campIdx: number): boolean;  // a successful (or assumed) stack this or last minute and the camp not yet pulled/farmed
export function StackCount(campIdx: number): number;
export function ClearStack(campIdx: number): void;    // after a stack pull / when neutrals seen dead
```

### Behaviour
- **Eligible**: `IsOn("Stack")`; laning phase: position 4 or 5 (`PositionOf`), `LaneRoles.LaneStable` (no enemy within 1,200 seen in last 3 s, HP > 50%), and `LaneRoles.PartnerSafe`; `stackRequested` plan bypasses the attempt roll but not safety. After laning: any position 4–5 bot whose active mode is `BOT_MODE_LANING`, `BOT_MODE_FARM` or `BOT_MODE_NONE`, no accepted order (`Orders.GetFor(bot) === undefined`), HP > `StableMinHP`, no visible enemy within `StableEnemyRadius`.
- A stack is a camp job and therefore the cycle's technique (PF14): a stack job starts only if `LanePlanner.Committed(bot)` is unset for the cycle in which it starts, and it calls `LanePlanner.Commit(bot, "stack")` (`"stack"` is part of `LaneConfig.Technique` from task 1).
- **ChooseCamp** priority: (1) our lane's pull camp (feeds a stack pull; any skill may stack it, only the later stack pull is gated at 0.75); (2) camps of our team nearest our cores (pos 1–3 allies' locations, within `Radii.StackCoreCamp` (3,000)); (3) our ancients — but if `StackCount(idx) >= Thresholds.StackMaxCampCount` (1) this minute-chain, only when skill > `Gates.MultiStackAncients` (0.7). Skip camps whose box contains a visible enemy hero or an allied human (do not contest). Travel time to the stand point must be ≤ `Timing.MaxTravel` (12 s) by :`aggroSec`.
- **WantsStack**: once per minute per pid, `Roll(Curve("StackAttempt", skill))` (0.2 → 0.9).
- **Stack job** (in `camp_jobs.ts`): the job may *start* from `min(StackMoveFrom (45), aggroSec - travel - JobStartLate (2))` until `aggroSec`; once started it keeps desire 0.7 until it is done at `:00 + StackExitUntil (1.0)` or aborts (PF2); phases travel → wait → at `stack.aggroSec + Jitter(skill)` attack one visible neutral in the box once (`Action_AttackUnit(creep, true)`) → walk `exitPath` until the next :00 + 1 s → return. Record visible neutral count in the box before aggro and at `:00 + Timing.StackOutcomeAt` (2 s) (only if the bot can see the box; else outcome "unknown", treated as stacked if aggro happened between :53 and :56 — log as assumed).
- Log, exactly the format task 3's `parse_condebug.js` reads (PF8): `[H:lane] stack pid=<p> camp=<idx> type=<type> aggro=<sec %.1f> planned=<sec %.1f> before=<n> after=<n|?> grade=<ok|mistake:early|mistake:late|unknown>` (`early` if aggro < :52, `late` if > :57; seconds mod 60).
- Telegraph: allies of humans, `Telegraph` on, camp type large or ancient and grade ok → `Orders.Say(bot, "say_lane_stacked_big", StackTelegraphCooldown (120))`.
- **Stack pull**: when `IsStacked(pullCamp)`, the planner can choose `stack_pull` (gate 0.75); the job uses full pull timing; on completion `ClearStack`. Scenario 4: the wave should be fully killed; grade full threshold applies.
- **`!hstacktest <idx>`** (Debug): nearest bot starts a forced stack job on that camp for the next minute.

### Tests (`test_lane_stacking.lua`)
- `eligibility`: pos 5 laning with no enemies → eligible; enemy seen 2 s ago at 1,000 → not (`unstable`); HP 45% → not; pos 2 → not.
- `attempt rate`: skill 0 roll 0.25 (> 0.2) → no stack this minute; skill 1 roll 0.85 (< 0.9) → stack; second call same minute with queue `{0.0}` → cached no (skill 0 case) and the queue entry is unread afterwards.
- `stack respects cycle lock` (PF14): a full pull committed in the cycle containing :45 → no stack job starts that minute.
- `stack log format`: a completed stack prints a line matching `^%[H:lane%] stack pid=%d+ camp=%d+ type=%a+ aggro=%d+%.%d planned=%d+%.%d before=%d+ after=[%d%?]+ grade=%S+$`.
- `camp priority`: pull camp present → chosen over a core's camp; without it → camp nearest our pos 1.
- `ancient multi-stack gate`: ancient with `StackCount == 1`: skill 0.7 → skipped; 0.71 → chosen.
- `do not contest human`: allied human hero inside the chosen box → camp skipped.
- `stack job timing`: aggro issued once at :53.5 + jitter (fixed draw 0 → exactly 53.5; one recorded `AttackUnit` with `args[2] == true`), no second attack; desire stays 0.7 at :58 (after the start window closed, PF2) while walking the exit path; at :01 desire 0.
- `outcome stacked`: before 3, after 6 → `IsStacked` true and planner input `stackedPullCamp` true; before 3, after 3 → `IsStacked` false even though the timing grade is `ok` (grade is about timing, `IsStacked` about the observed count).
- `stack pull consumes stack`: completed stack pull → `IsStacked` false.
- `telegraph once per 2 min`: two large-camp stacks 60 s apart → one `say_lane_stacked_big` line.
- `post-laning support with order does not stack`: accepted PUSH order → not eligible.

### Verification
Build twice + clean status; `npm run check`.

---

## Task 11: One shared harass tool (Phase E, merged with 04's idle poke)

**Goal:** `harass.ts` is the single harass implementation. It does Phase E's timed last-hit punish. When no punish fires, it does an idle poke equivalent to 04's `HarassThink`; Phase E's low-skill random poke is the same idle poke on a different interval, not a second mechanism. Both laning-Think owners call it: 04 (allies of humans) and 07 (`Lane.OwnLaningThink`). With `Lane.Harass` on, every bot whose laning Think is taken over, by 04 or by 07, uses the shared tool. This replaces PF5's "only bots 07 owns" rule. With `Lane.Harass` off, or every lane flag off, 04's `HarassThink` runs unchanged (regression scenario 15). 04's last-hit etiquette (`fLastHitFilter`, `MayLastHit`, `FilterCreeps`) is not touched.

### Files
- Create `typescript/bots/FunLib/humaniser/harass.ts`.
- Modify `lane.ts`: export `SupersedesHarass(bot)` = `LaneConfig.IsActive() && LaneConfig.IsOn("Harass")`. It no longer checks `LaneTech.OwnsLaning`, because the Lua only asks for bots whose Think is owned by 04 or 07. Also export `HarassThink(bot, allyCreeps, enemyCreeps, enemies, etiquette)` → `Harass.Think`. `Lane.Think` (task 8) does **not** call harass, so harass runs exactly once per frame, at 04's Harass step. `AdjustPosition` uses `Harass.StandPoint` when no technique overrides (07-owned bots only, since only they call `AdjustPosition`).
- Modify `lane_config.ts` `LaneHelpers`: add `IsValidHero?: (this: void, u: Unit) => boolean` and `IsSuspiciousIllusion?: (this: void, u: Unit) => boolean`. Modify `jmz_func.lua`'s `Lane.SetHelpers` table: `IsValidHero = function(u) return J.IsValidHero(u) end`, `IsSuspiciousIllusion = function(u) return J.IsSuspiciousIllusion(u) end`. `lane_world.lua`'s `LaneFresh` stubs both: valid if alive; illusion if `u.illusion`.
- Modify `bots/mode_laning_generic.lua`: only the harass line inside `Think()` changes. `local function HarassThink()` and its state locals (`harassTarget`, `harassStartTime`, `lastHarassTime`) stay byte-for-byte as they are now. The line `if bHumaniserLaning and HarassThink() then return end` (as task 8 left it) becomes:
  ```lua
  if (bHumaniserLaning or bLaneLaning) and Lane.SupersedesHarass(bot) then
      if Lane.HarassThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy, bHumaniserLaning) then return end
  elseif bHumaniserLaning and HarassThink() then return end
  ```
- Create `tests/humaniser/ref_harass_04.lua`. It holds a verbatim copy of 04's `HarassThink` body from `bots/mode_laning_generic.lua`, wrapped as `return function(env) ... end`: `bot`, `J`, `AllyLastHit`, `nInRangeEnemy`, `botAttackRange` and the three state locals come from `env`, and the body text is unchanged. It is the reference for the equivalence tests.
- Create `tests/humaniser/test_lane_harass.lua`.

### Exports
```ts
export interface HarassGates {          // the inputs that differ by owner
    etiquette: boolean;                 // true when 04 owns this bot (ally of a human)
    interval: number; window: number; idleExtraRange: number; minHP: number; towerAvoidRange: number;
    needProtectedHuman: boolean; needStronger: boolean;
}
export function GatesFor(bot: Unit, etiquette: boolean): HarassGates;
export function IsLastHitAttempt(enemy: Unit, ourCreeps: Unit[]): Unit | undefined; // the creep the enemy is about to last-hit, or undefined
export function TowerForbids(botLevel: number, nearEnemyTower: boolean, targetHP: number): boolean; // level < HarassTowerLevel (6) && near && targetHP >= HarassTowerTargetHP (0.3)
export function AggroDance(enemyCreepsWithin500: number): boolean;   // >= AggroDanceCreeps (3)
export function Capitalises(skill: number): boolean;                 // exactly one RandomFloat draw: Roll(Curve("HarassCapitalise", skill)); called first on a new attempt
export function StandPoint(bot: Unit, enemy: Unit, ourCreeps: Unit[]): Vector | undefined;  // skill >= 0.6 only
export function IdlePoke(bot: Unit, enemies: Unit[], g: HarassGates): boolean;  // 04-equivalent poke
export function Think(bot: Unit, allyCreeps: Unit[], enemyCreeps: Unit[], enemies: Unit[], etiquette: boolean): boolean; // timed punish first, then IdlePoke
export function RegisterSpellHarass(heroName: string, fn: (this: void, bot: Unit, enemy: Unit) => boolean): void;
```

### Behaviour
- **GatesFor**:
  - etiquette (04 owns the bot): read the values from `AllyLastHit.Settings()`, so 04's Customize overrides still apply. `interval = HarassInterval` (2.5), `window = HarassWindow` (1.2), `idleExtraRange = HarassExtraRange` (300), `minHP = HarassMinHP` (0.5), `towerAvoidRange = TowerAvoidRange` (850), `needProtectedHuman = true`, `needStronger = true`. These are 04's etiquette gates, now inputs to the shared tool.
  - not etiquette (07-only bot): mirror keys in Lane `DEFAULTS` (add `Harass: { IdleInterval: 2.5, IdleWindow: 1.2, IdleExtraRange: 300, IdleMinHP: 0.5, TowerAvoidRange: 850 }`), with `needProtectedHuman = false` and `needStronger = true`. A bot with skill < 0.5 uses `interval = RandomFloat(Timing.RandomHarassMin, Timing.RandomHarassMax)` (4–8 s), redrawn after each poke. This is Phase E's low-skill random poke, merged into the idle poke. A bot with skill ≥ 0.5 and no etiquette has no idle poke: it only punishes last-hit attempts.
  - Etiquette always wins: a bot that is both an ally of a human and low skill uses 04's 2.5 s interval.
- **IdlePoke** is a port of 04's `HarassThink` with the gates as parameters. It keeps the same statement order and the same engine calls in the same order, so the traces match the reference (see tests). Per-pid state `{ target, startAt, lastAt }`:
  1. If `target` is valid (`Helpers().IsValidHero`), `now - startAt < window` and `bot.GetLastAttackTime() < startAt` → `Action_AttackUnit(target, true)` and return true.
  2. Clear `target`. If `now - lastAt < interval` or HP < `minHP` → return false.
  3. If `needProtectedHuman` and `AllyLastHit.GetProtectedHuman(bot, bot.GetLocation())` is nil → false. If `needStronger` and not `Helpers().WeAreStronger(bot, 1200)` → false.
  4. `towers = bot.GetNearbyTowers(1600, true)`. Pick the nearest enemy from `enemies` that is valid, not `IsSuspiciousIllusion`, and within `bot.GetAttackRange() + idleExtraRange`, skipping any enemy where an enemy tower is within `towerAvoidRange` of the bot or of the enemy.
  5. No target → false. Otherwise set `target`, `startAt = lastAt = now`, call `Action_AttackUnit(target, true)` and return true.
  - 04 uses `J.IsSuspiciousIllusion`, so the shared tool does too, via the helper. This supersedes this plan's earlier note against filtering illusions; see the conflict note in the report.
- **Think**: if `plan.handsOff` for this bot's lane → false. Then:
  - **Timed punish.** Phase E as before. Candidates are visible enemies within attack range + `HarassExtraRange` (100). `IsLastHitAttempt` (a) or (b). On a new attempt, `Capitalises` is drawn first, then `Profile.SampleDelay(bot, 'react')`, plus `RandomFloat(0, LowSkillHarassExtra)` when skill < 0.5. At `fireAt`, run the manners checks and then `Action_AttackUnit(enemy, true)` once (or the registered spell harass), and count it as a poke (`lastAt = now`).
  - **Manners.** Aggro dance when ≥ 3 enemy creeps are within 500. `TowerForbids` applies to every bot. Etiquette bots must also pass their gates: HP ≥ `minHP`, `WeAreStronger`, and no enemy tower within `towerAvoidRange` of either unit, which is stricter than `TowerForbids`.
  - **Idle poke.** If nothing fired → `IdlePoke(bot, enemies, GatesFor(bot, etiquette))`.
- **StandPoint**: unchanged (skill ≥ `Gates.HarassPosition` 0.6, lowest-HP creep within `Radii.LowHpCreep`, attack range − `Radii.HarassStandBack`). Only 07-owned bots use it.
- Log: `[H:lane] harass pid=.. kind=<punish|poke> etiquette=<bool>`.

### Tests (`test_lane_harass.lua`)
- `attempt detection (a)`: enemy targeting our creep with HP 30 and damage 40 → that creep; HP 60 → undefined.
- `attempt detection (b)`: enemy moving toward a 35-HP creep (extrapolated closer) with damage 40 → creep; moving away → undefined.
- `capitalise rate` (scenario 8, PF10): 20 simulated attempts. Before attempt k (0..19), reset the queue to `{0.025 + 0.05k, 0.5, 0.5, 0.5}`. Skill 0.9 punishes exactly 16; skill 0.2 exactly 7; with `Harass = false`, `SupersedesHarass` is false and `Lane.HarassThink` is not called (control).
- `reaction delay respected`: no attack at the attempt frame; one attack at `now + react delay`.
- `aggro dance`, `tower rule` (level 5 near the tower: target 50% → none, 25% → attack, level 6 → attack), `out of range ignored`: as before.
- `etiquette gates block punish`: etiquette bot with HP 45%, or `WeAreStronger` false, or an enemy tower 800 from the target → no punish even on a detected attempt. The same setup without etiquette → punish (where `TowerForbids` allows).
- `low-skill random poke is the idle poke`: 07-only bot, skill 0.3, no attempts. With the interval draw at 4 s there is exactly one poke in the first 4.5 s, and its action log matches `IdlePoke`'s (no second mechanism). Skill 0.9 without etiquette → no idle poke at all. Etiquette + skill 0.3 → pokes every 2.5 s.
- `punish then idle share the timer`: a punish at T sets `lastAt`, so an etiquette bot's idle poke cannot fire again before T + 2.5.
- `shared tool for 04-owned bot with OwnLaningThink off` (replaces PF5): `Lane = { OwnLaningThink = 'off', Harass = true }`, ally of a human → `Lane.OwnsLaning` false, `AllyLastHit.OwnsLaning` true, `SupersedesHarass` true. Calling `Lane.HarassThink(..., etiquette = true)` with a detected last-hit attempt issues the punish, which 04's `HarassThink` never would.
- `supersedes gate`: true with `Harass` on; false with `Harass = false`; false with `Lane.Enable = false`; false with every lane flag off (PF4).
- `04 HarassThink text pinned` (scenario 15): read `bots/mode_laning_generic.lua` with `io.open`, extract the text from `local function HarassThink()` to its closing `end`, and assert it equals the body stored in `ref_harass_04.lua`, compared as strings. This fails if anyone edits 04's function.
- `idle poke equals 04` (equivalence): run `ref_harass_04.lua` and `Harass.IdlePoke(bot, enemies, GatesFor(bot, true))` on identical stub worlds through scripted 6 s scenarios (0.1 s steps), and assert identical `ACTIONS` logs and return values per frame. Scenarios:
  - window re-issue (attack not yet landed within 1.2 s)
  - interval (2.5 s)
  - HP 49%
  - no protected human
  - `WeAreStronger` false
  - tower within 850 of the bot, then of the enemy
  - two enemies (nearest chosen)
  - an illusion skipped
  - enemy at attack range + 301

### Verification
Build twice + clean status; `npm run check`.

---

## Task 12: Mid lane playbook (B3) and the rune-time helper

### Files
- Create `typescript/bots/FunLib/humaniser/lane_mid.ts`.
- Modify `bots/FunLib/jmz_func.lua`: add next to the other rune helpers
  ```lua
  -- Next power/water rune spawn (2-minute rhythm from 2:00), shared with mode_rune_generic.lua.
  function J.GetNextPowerRuneSpawnTime()
      local t = DotaTime()
      if t < 120 then return 120 end
      return (math.floor(t / 120) + 1) * 120
  end
  ```
  and add `NextPowerRuneTime = function() return J.GetNextPowerRuneSpawnTime() end` to the `Lane.SetHelpers` table.
- Modify `bots/mode_rune_generic.lua` line ~218: replace `(minute % 2 == 1 and second > 53)` with `(J.GetNextPowerRuneSpawnTime() - DotaTime() < 7)` — identical for `DotaTime() > 60` (odd minute and second > 53 ⇔ < 7 s to the next even minute), so the rune rule has one source. Do not change anything else there.
- At module load `lane_mid.ts` calls `LaneState.SetPreRune(IsPreRune)` and `LaneHooks.SetRotationProbe(bot => bot.GetAssignedLane() === Lane.Mid && IsPreRune(bot.GetTeam(), Lane.Mid))` (PF11; `lane_state`/`lane_planner` do not import `lane_mid`). Because the planner re-evaluates live (PF3), entering the window changes the choice immediately.
- Modify `lane.ts`: `PickDeny` → `LaneMid.PickDeny`; `Think` consults `LaneMid.MayTouchWave`.
- Modify `lane_planner.ts` `Choose`: add rule 6½ (after FREEZE, before rule 7): `isMid && eqPos >= Thresholds.MidTowerEq (0.8) && Knows("aggro_pull")` → aggro_pull `"mid: out of tower range"` (PF10: it must win over a mid pull or rule 9 so it is distinguishable).
- Create `tests/humaniser/test_lane_mid.lua`.

### Exports
```ts
export function IsPreRuneWindow(now: number, nextRune: number): boolean;   // nextRune - now in [Timing.PreRuneMin (15), Timing.PreRuneMax (20)]
export function IsPreRune(team: number, lane: Lane): boolean;              // lane Mid && IsOn("Mid") && window (helper missing -> false)
export function PickDeny(bot: Unit, allyCreeps: Unit[]): Unit | undefined; // mid only: deniable ranged creep first
export function MayTouchWave(bot: Unit, creep: Unit): boolean;             // false for non-mid bots near a human mid's wave
export function MidPullAllowed(team: number): boolean;                     // Camps.PullCampsFor(team, Mid).length > 0
```

### Behaviour
- Mid bot (`GetAssignedLane() === Lane.Mid`, role solo): block at 0:00 (task 8 block), aggro pull/deaggro toward `DesiredEq(mid)` (−0.1, slightly our side of the river) and to pull the wave out of the enemy tower's range: planner rule 6½ (`mid: out of tower range`, eqPos ≥ `Thresholds.MidTowerEq` 0.8).
- **Deny control**: `PickDeny` returns the first allied ranged lane creep (name contains `ranged`) with HP < 49% of max and HP ≤ the bot's attack damage; otherwise undefined (Lua falls back to `GetBestDenyCreep`). After task 13 sets `dropRangedDeny` (enemy mid missing), returns undefined.
- **Pre-rune shove**: `desiredEq` becomes `MidPreRune` (+0.15) inside the window; the rotation probe makes `rotationPlanned` true → shove if known (0.4) and plan not FREEZE. The pre-rune shove is the cycle's technique (commit lock applies). Gank pre-shove: see resolution (only rotations the lane module schedules).
- **Pulls mid**: only if `MidPullAllowed` (seed data never provides one).
- **Human mid**: `MayTouchWave(bot, creep)` is false when `InLaningPhase()`, the creep is within `Radii.MidFront` (1,200) of the mid front, an alive human ally with position 2 is assigned to mid within `Radii.MidHuman` (1,500) of the front, and the bot is not assigned mid. Lane techniques (shove, aggro, deny via `PickDeny`) check it. Last hits stay under 04's `MayLastHit` (human away → `take:`). Rune contest by rotating supports already backs off near humans in `mode_rune_generic.lua` (unchanged).

### Tests (`test_lane_mid.lua`)
- `pre-rune window`: next rune 240: now 222 → true; 219 → false; 226 → false.
- `pre-rune changes desired eq and triggers shove`: mid snapshot at 222 has `desiredEq == 0.15`; planner choice for skill 0.5 → shove; at 210 → not shove; skill 0.39 → not shove.
- `entering the window mid-cycle` (PF3): `Plan` at 217 (window not open) → not shove; `Plan` at 220.5 in the same wave cycle → shove.
- `ranged deny first`: allied melee (20 HP) and ranged (25 HP) both deniable → ranged chosen; ranged at 60% → undefined.
- `human mid hands off`: support bot passing mid with a human pos 2 in mid → `MayTouchWave` false; mid bot itself → true; after laning → true.
- `no mid pulls from seeds`: planner never returns a pull for a mid bot with seed data even at score −2.
- `wave at enemy tower triggers aggro pull` (PF10): mid eqPos 0.9, skill 0.6, and a mid pull camp injected into the data (so rule 7 would otherwise pick full_pull) → aggro_pull with reason `mid: out of tower range`; eqPos 0.7 with the same camp → full_pull (proves the new rule, not rule 9, decided).

### Verification
Build twice + clean status; `npm run check` (syntax check covers `mode_rune_generic.lua`/`jmz_func.lua` edits).

---

## Task 13: Counter-play (Phase F)

### Files
- Create `typescript/bots/FunLib/humaniser/counterplay.ts`.
- Modify `lane.ts`: `Tick` calls `Counter.Tick(bot)`; `Think` runs `Counter.Think` responses after techniques; export `RuneContestDesire`, `PreferStackedCamp`.
- Modify `camp_jobs.ts`: `contest` job kind: started only by `counterplay` (which may import `camp_jobs`); desire `Timing.ContestDesire` (0.65) for as long as the job is active (PF2), at most `Timing.ContestMax` (10 s); move to the camp and attack the visible puller once per `Timing.ContestAttackGap` (2.5 s); it is the cycle's committed technique (PF14). At load `counterplay.ts` registers `LaneHooks.SetTechniqueOverride` (break-freeze and rune-shove shove override) (PF11).
- Modify `lane_mid.ts`: honour `Counter.DropRangedDeny(team)`.
- Modify `bots/mode_rune_generic.lua` `GetDesire`: wrap the final result as `return math.max(res, J.Humaniser.Lane.RuneContestDesire(bot))` at the single return point if one exists; otherwise add `local nLaneContest = J.Humaniser.Lane.RuneContestDesire(bot); if nLaneContest > 0 then return nLaneContest end` right after the early exits. Returns 0 when disabled.
- Modify `bots/mode_farm_generic.lua`: where `preferedCamp` is chosen after laning (find the `UpdateAvailableCamp`/`GetClosestNeutralSpwan` call), add `preferedCamp = J.Humaniser.Lane.PreferStackedCamp(bot, availableCamp) or preferedCamp` (returns nil when disabled).
- Modify `localization.lua`: `say_lane_they_pull_<top|mid|bot>` (`{"they're pulling bot"}` etc.), `say_lane_their_sup_missing`, `say_lane_they_freeze`, `say_lane_ss_mid` (`{"ss mid"}`).
- Create `tests/humaniser/test_lane_counter.lua`.

### Exports
```ts
export interface PullSignalInput { now: number; enemySupport: LaneState.LaneEnemy; campLoc: Vector; campPullSec: number[]; campHalfSec?: number[]; }
export function EnemyPullSuspected(i: PullSignalInput): boolean;  // (unseen > CounterUnseen (4) && last seen within Radii.PullCampLastSeen (1500) of camp && |cycle sec - nearest pull/half sec mod 30| <= CounterPullWindow (6)) || (visible && within Radii.EnemyNearCamp (800) of camp)
export function WaveAnomaly(cycleSec: number, expectedArrival: number | undefined, visibleEnemyCreeps: number, typicalSize: number): "late" | "thin" | undefined; // late: cycleSec > expected + CounterWaveLate (5) and 0 creeps; thin: arrived with <= typical - 2
export function FreezeSuspected(eqHistory: number[], enemyDeniesPerCycle: number[]): boolean; // reads snapshot fields eqHistory and enemyDeniesPerCycle (task 4, PF8): last 2 cycles eqPos >= 0.6 and enemy denies >= 2 each
export function StackSuspected(secOfMinute: number, enemyNearCampVisible: boolean, neutralOutsideBoxVisible: boolean): boolean; // (50..58 && enemyNear) || (0..3 && outside)
export interface Signal { kind: "pull" | "half_pull" | "freeze" | "stack" | "mid_missing" | "rune_shove"; lane: Lane; at: number; campIdx?: number; enemyPid?: number; noticed: boolean; }
export function Tick(bot: Unit): void;          // evaluates on snapshot refresh, rolls notice once per signal instance
export function Signals(bot: Unit): Signal[];   // noticed, unexpired (Timing.CounterSignalTTL 20 s) signals for this observer
export function Think(bot: Unit, enemies: Unit[]): boolean;
export function RuneContestDesire(bot: Unit): number;
export function PreferStackedCamp(bot: Unit, camps: any[]): any | undefined;
export function DropRangedDeny(team: number): boolean;
export function MarkedStacked(team: number): number[];  // camp idx
```

### Behaviour
- **Fairness**: inputs only from `LaneState.Enemies(bot, lane)` (perception-filtered visible units plus `GetHeroLastSeenInfo`), visible enemy creeps from snapshots, visible neutrals (`CanBeSeen()`), and public map data (camp locations, enemy camp pull timings from `Camps` for the enemy team). An enemy with no last-seen info is never used. No reads of fogged handles.
- **Enemy support** = enemy with estimated position 4/5 whose last-seen location is nearest the lane. `Helpers().GetPosition` needs a unit handle, so call it only while the enemy is visible and cache the result per enemy pid (positions are fixed for the game); a never-seen enemy has no position and is not used.
- **Signals** (each new instance rolls `Roll(Curve("CounterNotice", skill))` once; unnoticed signals are remembered so they are not re-rolled):
  - pull / half pull: `EnemyPullSuspected` for the enemy team's pull camp of the lane opposing ours, or `WaveAnomaly` `late` → pull, `thin` → half_pull.
  - freeze: `FreezeSuspected(s.eqHistory, s.enemyDeniesPerCycle)` (snapshot fields from task 4).
  - stack: `StackSuspected` for any camp with a visible enemy within `Radii.EnemyNearCamp` (800) or visible neutrals outside box + `Radii.NeutralOutsideMargin` (200) at :00–:03.
  - mid: enemy mid (position 2) unseen > `CounterUnseen` (4 s) right after our mid wave was pushed to our tower (eqPos ≤ `Thresholds.MidMissingEq` (−0.6) in the previous cycle) → `mid_missing`; enemy mid shoving (eqPos ≤ −0.6) within `Timing.MidRuneShoveLookahead` (25 s) of the next power rune → `rune_shove`.
- **Responses** (laning bots of that lane, only if noticed):
  1. punish 2v1 (pull): `Helpers().WeAreStronger(bot, Radii.Stronger)` and the remaining enemy laner visible → `Action_AttackUnit(laner, true)` once per `Timing.PunishGap` (2 s) for up to `Timing.PunishFor` (6 s) (respect `Harass.TowerForbids`). A reaction, not a planned technique: exempt from the commit lock.
  2. contest camp: if not stronger, owner support, path safe (no other enemy last seen within `Radii.PathSafe` (1,500) of the route in the last `Timing.PathSafeSeen` (5 s)) and the cycle not committed → start `contest` camp job at the enemy pull camp.
  3. break freeze: our support → the technique override returns `shove` for the next wave cycle (the planner applies it if `Knows("shove")`, rule 3), else zone (AdjustPosition zoning point).
  4. camp block (`CampBlock` flag, default false; skill > `Gates.CampBlock` (0.6), cooldown `Timing.CampBlockCooldown` (180 s)): between :50 and :58, a support with a sentry or observer ward uses it at the enemy pull camp box centre (`Action_UseAbilityOnLocation(item, center)`). TODO (in-game): wards still block spawns.
  5. stacks: stronger → attack the visible stacker once; else mark the camp (`MarkedStacked`); `PreferStackedCamp` makes a core bot (pos 1–3, after laning) prefer a marked camp of our jungle, or of theirs when no enemy is visible or last seen ≤ 5 s within 1,500 of it.
  - mid_missing → our mid bot (ally of a human, `Telegraph` on) `Orders.Say(bot, "say_lane_ss_mid", CounterTelegraphCooldown)` and `DropRangedDeny(team)` true for `Timing.DropRangedDenyFor` (20 s); rune_shove → stronger: `RuneContestDesire` 0.6 for the mid bot until the rune spawns + `Timing.RuneContestAfter` (10 s); else the technique override returns `shove`.
- **Telegraphs** (allies of humans, `Telegraph` on, cooldown 60 s each): `say_lane_they_pull_<lane>`, `say_lane_their_sup_missing`, `say_lane_they_freeze` via `Orders.Say`.

### Tests (`test_lane_counter.lua`)
- `fairness: all fogged, no hints` (scenario 10, PF10): enemies absent from visible lists and no `LAST_SEEN` entries, the wave on time, no visible neutrals → `Signals` empty after 120 s of ticks with notice roll 0.0 and skill 1. Positive control in the same test: the same world, but the enemy support visible within 800 of their pull camp at cycle second 15 → a `pull` signal appears (so emptiness is not the default).
- `pull suspected from last seen`: support unseen 5 s, last seen 1,000 from their small camp, cycle sec 14 (pull 15) → true; unseen 3 s → false; cycle sec 25 → false; visible at the camp → true.
- `wave anomaly`: expected arrival 12, now cycle 18 with 0 visible enemy creeps → `late`; arrival with 2 vs typical 5 → `thin`; 4 vs 5 → undefined.
- `freeze suspected needs two cycles and denies`: eq history {0.7, 0.65} with denies {3, 2} → true; {0.7, 0.4} → false; denies {1, 3} → false.
- `stack suspected windows`: enemy near camp at :54 → true; at :49 → false; neutrals outside box at :01 → true.
- `notice rate` (scenario 9, PF10): 20 pull instances; before instance k reset the queue to `{0.025 + 0.05k}` (the notice roll is the first draw for a new instance): skill 0.9 notices exactly 15 (0.74), skill 0.2 exactly 6 (0.32).
- `punish when stronger, contest when not`: noticed pull + stronger → one attack on the remaining visible laner; not stronger + safe path → contest job started; unsafe path (another enemy last seen 1,000 from route 2 s ago) → nothing.
- `camp block off by default` (PF10): CampBlock default false → no `UseAbilityOnLocation` even at skill 1 with a sentry at :54; positive control: `CampBlock = true`, skill 0.7, sentry in inventory, :54 → exactly one `UseAbilityOnLocation` at the enemy pull camp box centre; a second attempt 60 s later → none (180 s cooldown); skill 0.6 → none (strictly above).
- `break freeze override`: noticed freeze for our support skill 0.5 → `LaneHooks.TechniqueOverride(bot) == "shove"` and the planner returns shove `counter: shove` under plan HOLD; next-next cycle → override cleared.
- `rune shove response`: noticed `rune_shove`, stronger → `RuneContestDesire(mid bot) == 0.6` until rune + 10 s then 0; not stronger → `RuneContestDesire` 0 and override `shove`.
- `stack response`: noticed enemy stack at their camp, stronger and the stacker visible in range → one attack on the stacker; not stronger → camp idx in `MarkedStacked(team)`, and after laning `PreferStackedCamp(core bot, camps)` returns that camp when no enemy is visible or last seen ≤ 5 s within 1,500 of it, nil otherwise.
- `ss mid`: our mid wave at our tower last cycle and enemy mid unseen 5 s → `say_lane_ss_mid` once and `DropRangedDeny` true; with the enemy mid visible → neither.
- `disabled` (PF10): `CounterPlay = false` → `Signals` empty, `RuneContestDesire` 0, `PreferStackedCamp` nil, in the same world where the defaults produce a noticed `pull` signal and a non-nil `PreferStackedCamp` (positive control).

### Verification
Build twice + clean status; `npm run check`.

---

## Task 14: Docs, test plan, regression consolidation

### Files
- Modify `docs/HUMANISER_DEV.md`: new section `## Lane management (07)` in the style of the 04/05/06 sections:
  - Module map (`lane_config`, `lane_hooks` (probe registry that keeps imports one-directional), `camps_data`, `camps`, `lane_state`, `lane_plan`, `lane_roles`, `lane_planner`, `lane_tech`, `camp_jobs`, `stacking`, `harass`, `lane_mid`, `counterplay`, `lane_debug`, facade `lane`), flags table (`Customize.Humaniser.Lane.*` with defaults and what each disables), `OwnLaningThink` semantics and blast radius (`'all'` gives every bot, enemies included, OHA's laning Think for the whole game. 04's last-hit filter stays limited to allies of humans. With `Lane.Harass` on, every bot whose Think 04 or 07 owns uses the single shared harass tool in `harass.ts`: timed punish plus an idle poke equivalent to 04's, with 04's gates as inputs for allies of humans. With it off, 04's `HarassThink` runs unchanged).
  - Design notes: lane snapshot shared per lane, exposure/laneScore per observer; planner re-decides live with one attempt roll and one committed technique per wave cycle; camp-job window gates only the start; `IsActive()` (Lane on and any consumer flag on) gates every engine call.
  - Data method: seeds (sources and access date 21/10/2026), replay mining usage (`tools/replay-mining`: fetch, `go run ./parser`, `detect.js`, `gen_camps.js`), measurement (`-condebug`, `!hpt`, `!hcamp`, `!hstacktest`, `!hpulltest`, `parse_condebug.js`), how to promote an entry to `source: 'measured'` with `verifiedAt` dd/mm/yyyy.
  - Overlay line format and log line formats (`[H:lane] job ...`, `stack ...`, `harass ...`, `mistake ...`).
  - **TODO (in-game)** list (collect from tasks): waves at :00/:30 and respawn-on-minute rule on the current patch; `GetLaneFrontAmount` team-relative vs `GetLocationAlongLane` absolute (`LANE_AMOUNT_TEAM_RELATIVE`); spawner `type` string vs int and `idx` meaning; `GetAmountAlongLane` returns a table; deaggro by attacking an allied creep above 50% HP; tower aggro drop; enemy `GetAttackTarget()` readable for last-hit detection; neutrals' `GetAttackTarget()` / allied creeps targeting neutrals readable for divert measurement; laning desire vs rune desire at 0:00 (bots going to bounty runes skip the block); `GetHeroLastSeenInfo` for enemy supports in fog; wards block neutral spawns; each seed timing per camp (stack :53–:55, pulls :15/:45, :18/:48, half pulls +2 s); the offlane hard camp is pullable on the current map; `J.GetPosition` on enemies gives the estimated role; job desire 0.7 beats laning (0.446) but not retreat.
  - Manual test checklist mirroring spec scenarios 1–15 (`- [ ]` items).
- Modify `docs/HUMANISER_TEST_PLAN.md`: update the intro count of offline tests; add `## Session 5: lane management (07)` with: data calibration run (every camp `!hstacktest`/`!hpulltest`, collect `console.log`, run `parse_condebug.js`), scenarios 2–14 at `SkillOverride = 0.9` vs `0.2/0.4`, and the regression item `Lane.Enable = false` and every flag false (scenario 15); add lane risks to "Known risks" (`OwnLaningThink = 'all'` replaces Valve laning for every bot; camp jobs pull supports out of lane; untrusted seed paths).
- Create `tests/humaniser/test_lane_regression.lua`.

### Tests (`test_lane_regression.lua`) — scenario 15, all must fail if any gate is missing
For each config in `{ Humaniser.Enable=false }`, `{ Lane = { Enable = false } }`, `{ Lane = { Enable = true, <every flag false> } }`:
- `IsActive()` false (PF4; for the third config this is the case `Enable = true` with only `Telegraph` left on as well).
- `OwnsLaning` false for an ally of a human and for an enemy bot under `OwnLaningThink = 'all'`.
- `PreThink`, `Think`, `CampJobThink` return false; `AdjustPosition(bot, v)` returns `v` (same table); `PickDeny` nil; `CampJobDesire` 0; `RuneContestDesire` 0; `PreferStackedCamp` nil; `SupersedesHarass` false (so the Lua runs 04's unchanged `HarassThink`; its text is pinned by task 11's `04 HarassThink text pinned` test).
- No action recorded, `GETUNITLIST_CALLS` zero after ticking `Lane.Tick` for 10 s of game time (valid for the all-flags-off config because of PF4), no `[H:lane]` output.
- `!freeze bot`, `!stack` post no orders; a lane-front ping during laning classifies as GATHER exactly as before.
- Positive control in the same file: with defaults on, the same world produces behaviour for each assertion group (`OwnsLaning` true, `CampJobDesire` 0.7 in a pull window for a pos 5 owner, `GETUNITLIST_CALLS > 0`, `!freeze bot` posts a `LANE_FREEZE`, the ping posts `LANE_HANDSOFF`), proving each check can fail.

### Verification
```bash
cd /Users/cbyatt/Documents/Projects/dota-bots-humaniser/oha-h07 && npm run build && npm run build && git status --porcelain
cd tests/humaniser && npm run check
```
Final review: `git diff humaniser --stat` should show changes only in the files listed across tasks 1–14.
