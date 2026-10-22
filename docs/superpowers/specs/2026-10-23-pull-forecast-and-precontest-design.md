# Pull forecast and pre-emptive contest: design

Date: 23/10/2026. Builds on task 07 (lane management): `lane_planner.ts`, `lane_state.ts`, `counterplay.ts`, `camp_jobs.ts`, `pull_timing.ts`.

## Why

Bot pulls are reactive. `LanePlanner.Choose` pulls when `laneScore = desiredEq − eqPos` reaches `Planner.FullPullBelow` (−0.5), with `eqPos` the point where the waves meet *now*. For a safe lane (`desiredEq` −0.7) that means the meet point has already drifted to about −0.2, near mid-lane. A good human support pulls earlier: they look at the clash in lane, see that our side will come out ahead, and know the lane is about to push. They also skip a pull when the lane looks pushed but is about to come back.

Contesting enemy pulls has the same problem. `respondToPull` acts only after `EnemyPullSuspected` sees the enemy support at their camp (or missing near a pull second). By the time our support walks over, the wave is usually already diverted.

Difficulty already scales how often bots attempt techniques (gates, `AttemptRate`, `StackAttempt`, `JitterSigma`), but not how well they read the lane. A skill-0.3 bot and a skill-1.0 bot pull on the same signal. This design adds that missing axis: better bots read where the lane is going, weaker bots react to where it is.

## Goals

1. **Forecast.** Predict where the lane meets after the current clash, from the visible lane creeps near the front (count, HP and type on each side).
2. **Skill-scaled reading.** Blend the reactive and forecast signals by a skill curve: skill 0 behaves exactly as today, skill 1 decides on the forecast.
3. **Pre-emptive contest.** Use the same forecast, seen from the enemy's side, to predict an enemy pull. A skilled bot gets to the enemy camp before the aggro second and contests at once instead of after detection.
4. **Measurable.** Telemetry good enough to fit the forecast constant from real games.

## Non-goals

- Enemy hero pressure (laners hitting creeps) in the forecast. Creeps only for now; add later if telemetry shows it matters.
- Changing stacking, the stack-pull and double-pull logic, or the pull timing itself.
- Verifying or enabling `CampBlock`.
- New attempt rolls for full or half pulls. Their frequency stays with `AttemptRate`.

## Anti-goals (failure even if it works)

- **Omniscience.** The forecast reads fogged creeps, or the bots pull on information a player couldn't have.
- **Abandoning the carry.** A support leaves a 1v2 lane to watch an enemy camp the enemy support never goes to.
- **Flip-flopping.** Pulls toggle on and off within a cycle as the clash counts jitter, so bots walk towards a camp and back.
- **Sharper low-difficulty bots.** Low-skill bots must not get noticeably better at pulling.

## Constraints

- TypeScript sources under `typescript/bots/FunLib/humaniser/`, compiled to Lua with the project's TSTL build. Hand-written Lua is untouched.
- Every tunable lives in `lane_config.ts` `DEFAULTS` and is overridable through `Customize.Humaniser.Lane`.
- Fairness, as stated at the top of `counterplay.ts`: inputs are visible units, `LaneState.Enemies` and public map data only. `GetUnitList(UnitType.EnemyCreeps)` returns visible creeps, which is fine. `GetLaneFrontAmount` for the enemy is not vision-filtered (known leak in `HUMANISER_DEV.md`), so the forecast must not add to that leak.
- Offline tests follow `tests/humaniser/` (Lua harness with `lane_world.lua` and `dota_stubs.lua`). `Choose` is pure and has an existing test file to extend.
- Kill switches restore today's behaviour exactly.

## Design

### 1. The forecast (`lane_state.ts`)

A new pure function in `lane_state.ts`, plus a snapshot field computed in the snapshot refresh:

```
LanePower(units: Unit[]): number        // sum over alive lane creeps of HP × TypeWeight[type]
Imbalance(ally, enemy): number          // (A − E) / (A + E + Forecast.PowerFloor), in [−1, 1]
ForecastEq(eqPos, imbalance): number    // clamp(eqPos + Forecast.K × imbalance, −1, 1)
```

- **Inputs:** `s.ally.units` and `s.enemy.units`, the lane creeps within `Radii.LaneCreep` of the front that the snapshot already collects. Enemy creeps are visible creeps only.
- **Type weights** go in config as `Forecast.TypeWeight` `{ melee, ranged, siege }`, matched by unit name the way `summarise` already does (`ranged`, `siege`, otherwise melee). Starting values: melee 1.0, ranged 1.6, siege 1.0. Ranged creeps have about half a melee creep's HP for similar damage, so HP alone undervalues them. The builder should check the 7.41 numbers in `npc_units.txt` and adjust; these are my starting call, not a requirement.
- **Normalising** by the sum of both sides makes the imbalance independent of creep upgrades over time. `PowerFloor` (starting value: one melee creep's HP) keeps a 1-creep-vs-0 mop-up from reading as a full ±1.
- **`K`** starting value 0.4, to be fitted from telemetry (section 4).
- **No clash, no forecast:** with no creeps on either side near the front, the imbalance is 0 and the forecast equals `eqPos`.
- **Sign convention:** positive imbalance means we're winning the clash, the lane will push towards the enemy, and `eqPos` rises.

Store `imbalance` and `forecastEq` on `LaneSnapshot`. They're team-relative like `eqPos`, so the enemy's view is the negation (section 3).

### 2. Skill-scaled pull decisions (`lane_planner.ts`)

- **New curve** `Curves.Foresight` with default `[0, 1]`: `w = Curve("Foresight", skill)`.
- **Reading:** `readEq = eqPos + w × (forecastEq − eqPos)`, then `forecastScore = LaneScore(desiredEq, readEq, exposure)`, computed in `LaneState.ScoreFor` alongside `laneScore` and added to `ObserverView`.
- **New `PlannerInput` field** `forecastScore`, set in `buildInput`.
- **Where it applies in `Choose`:** the default (non-freeze) pull branch, meaning the `FullPullBelow` full and stack pull check, the `SmallDriftBelow` half pull and the `AggroCorrectBelow` aggro correction, uses `forecastScore` in place of `laneScore`.
- **Where it doesn't:** the freeze branch, the mid tower check and the cover-core branch keep raw `laneScore` and `eqPos`. They're about the current position, and the freeze branch already looks at creep counts.
- **Kill switch:** new `Lane.Forecast` flag (default true). Off, or skill 0, means `forecastScore === laneScore` and `Choose` behaves exactly as today.

Consequences, both intended:

- A high-skill support pulls a cycle earlier when our side is winning the clash, even though the meet point hasn't moved yet.
- A high-skill support skips a pull when the lane looks pushed out but our side is losing the clash and the lane is coming back.

**Flip-flopping.** Since `Choose` re-decides on every call, the forecast can wobble during a clash. Once a job starts, the existing per-cycle `Commit` stops re-deciding. Before that, the window opens only once per cycle (`windowFor`), and the decision that matters is the one when it opens. If telemetry shows choices toggling inside that window, the builder may smooth `imbalance` over the last ~1 s of snapshots. Not required up front.

**Timing assumption, to check in telemetry.** A :15 or :45 pull is decided when its start window opens, up to `MaxTravel` (12 s) before the aggro second. At that moment the previous waves should still be fighting, so the forecast reads the clash that decides the next meet point. If `lane_plan` shows zero creeps on both sides most of the time at the planner gate, the forecast is reading too late and needs another look.

### 3. Pre-emptive contest (`counterplay.ts`, `camp_jobs.ts`)

**Predicting the enemy pull.** This is a pure function next to `EnemyPullSuspected`:

```
EnemyPullExpected(s, enemyLanePullCamp, now): { campIdx, aggroAt } | undefined
```

- **The enemy's view:** `enemyEq = −s.forecastEq`. Their `desiredEq` is `DesiredEq` for the lane kind on their side: our off lane is their safe lane, and the reverse. `enemyScore = LaneScore(desired_e, enemyEq, 0)`.
- **Expected if:**
  - `enemyScore ≤ Planner.SmallDriftBelow` (they'd half or full pull),
  - the enemy has a camp for this lane (`Camps.PullCampsFor(enemyTeam, s.lane)`, the list `campBlock` already uses),
  - the enemy has a support-position laner in this lane (`LaneState.Enemies` with position 4 or 5, seen within `ExposureSeen`),
  - and the camp is up (`CampsUp`).
- **Aggro second:** the next one from `PullTiming.ForCamp(enemyCamp, false)`, the same source `EnemyPullSuspected` uses.

The bot reads the enemy's lane at full forecast weight, with no `Foresight` blend. Skill instead decides whether the bot does this at all (below).

**Who and when.**

- **Who:** the lane's camp-job owner (`LaneRoles.CampJobOwner(s)`), from the same laning-Think path as `respondToPull`. It therefore follows `OwnLaningThink` the way contests do today: with the default `'allies'`, enemy bots don't pre-contest.
- **Gates:**
  - new flag `Lane.PreContest` (default true; my call, because like the other contest code it only reacts to visible state),
  - new gate `Gates.PreContest` (0.7),
  - one `CounterNotice` roll per predicted instance, remembered like other signals,
  - nothing committed this cycle (`LanePlanner.Committed`) and no live camp job,
  - `pathSafe` to the watch point,
  - `PartnerSafe`.
- **Start time:** early enough to reach the watch point `Timing.PreContestLead` (2 s) before the predicted aggro second, at most `MaxTravel` away.

**The job.** It's the existing `contest` job, started early with a new `lookout` phase ahead of its attack phase. It commits `"contest"` for the cycle, so our own pull and the pre-contest can't both run.

- **Watch point:** on the enemy camp's lead path (`PullTiming.LeadPath`), `Radii.PreContestStand` (starting value 400) from the spawner origin, towards the lane.
- **While watching:** hold still (`Intent.Hold`, source `lane:precontest`) until either:
  - **Enemy support seen near the camp** (the existing `contestTarget`, which only targets heroes): switch to the attack phase at once (`stepContest`, target the enemy support's pid). The `ContestMax` cap applies from that moment.
  - **Enemy support seen near our front** (`Radii.Exposure`) after `aggroAt − PreContestLead`: they aren't pulling, so end the job with reason `enemy-in-lane` and walk back.
  - **Nothing by `aggroAt + Timing.PreContestWait`** (starting value 4 s): end with reason `no-pull`.
  - **Usual safety aborts** (partner low HP or dived, own HP, enemy hero near), with the existing reasons.
- **Same instance seen by `respondToPull` later:** if the pull happens anyway, the instance is marked responded, so it doesn't start a second contest.

**Why there's rarely a conflict with our own pull:** the enemy wants to pull when the lane drifts towards *their* tower, which is when ours looks fine to us. The per-cycle commit settles the rare overlap: whichever starts first owns the cycle.

### 4. Telemetry

- **`lane_plan`:** add `imb`, `feq` (forecast eq), `w` (foresight weight), `fscore` and `apow`/`epow` to the `planner` gate fields, in `camp_jobs.ts` `notePlan`.
- **New `lane_eq` event:** one per team and lane per wave cycle, at a fixed cycle second (`Timing.EqSampleAt`, starting value 10), with `team lane eq imb feq a e`. Emitted from the snapshot refresh when it first passes that second in a cycle. Fitting `K` needs the forecast at time t against the measured `eq` at t + 30 s, which is the next row for the same team and lane.
- **`lane_job_start`:** a pre-contest gets `pre=1`. **`lane_job_end`:** every contest end is logged with `kind=contest camp reason pre`; `reason` is `no-target`, `timeout`, `enemy-in-lane` or `no-pull`. A contest end is not an abort, so `lane_job_abort` is unchanged.
- **`tools/hlog` analyser:** add a fit of `Δeq` (next cycle − this cycle) against `imb` per lane kind, printing a suggested `K` and the fit quality. Also add a pre-contest summary: started, converted to an attack, `no-pull`, `enemy-in-lane`.
- Document the new and changed events in the `HUMANISER_DEV.md` telemetry table.

### 5. Config summary (`lane_config.ts`)

| Key | Default | Meaning |
|---|---|---|
| `Forecast` (flag) | true | Skill-blended forecast in the pull branch |
| `PreContest` (flag) | true | Pre-emptive contest |
| `Forecast.K` | 0.4 | Eq shift per unit of imbalance, to be fitted |
| `Forecast.TypeWeight` | `{ melee: 1.0, ranged: 1.6, siege: 1.0 }` | Power per HP by creep type |
| `Forecast.PowerFloor` | one melee creep's HP | Damps tiny mop-ups |
| `Curves.Foresight` | `[0, 1]` | Forecast weight by skill |
| `Gates.PreContest` | 0.7 | Minimum skill for pre-contest |
| `Timing.PreContestLead` | 2 | Seconds early at the watch point |
| `Timing.PreContestWait` | 4 | Seconds past the aggro second before giving up |
| `Timing.EqSampleAt` | 10 | Cycle second of the `lane_eq` sample |
| `Radii.PreContestStand` | 400 | Watch point distance from the spawner |

### 6. Tests

Offline, in `tests/humaniser/`:

- **`test_lane_state.lua`, forecast:**
  - a side with two ranged creeps outweighs a side with three melee creeps of the same total HP;
  - a 1-creep mop-up gives a small imbalance, not ±1;
  - empty fronts give `forecastEq == eqPos`;
  - fresh creeps and upgraded creeps in the same proportions give the same imbalance.
- **`test_lane_planner.lua`, decisions:**
  - at skill 0.9, a lane at `eqPos −0.3` (half pull today) with imbalance 0.6 full pulls;
  - the same lane at skill 0.3 does not;
  - at skill 0.9, a lane at `eqPos −0.1` (full pull today) with imbalance −0.6 doesn't full pull;
  - at skill 0, the choice matches today's for the same inputs;
  - with `Forecast = false`, the choice matches today's at any skill;
  - the freeze branch ignores the forecast.
- **`test_lane_counter.lua`, prediction:**
  - `EnemyPullExpected` fires when the lane drifts towards the enemy tower with an enemy support present;
  - it doesn't fire with no enemy support seen, or with the camp down;
  - mirrored lane kinds pick the right `desiredEq`.
- **`test_lane_camp_jobs.lua`, the lookout phase** (`lane_world.lua`):
  - converts to an attack when the enemy support appears at the camp;
  - ends `enemy-in-lane` when they're seen at our front after the lead time;
  - ends `no-pull` after the wait;
  - commits `contest`, so the same bot can't start a pull that cycle.

In-game, as new items in `HUMANISER_TEST_PLAN.md`:

- a 0.9 support pulls a cycle earlier than a 0.3 one when the clash favours us;
- with a losing clash and a pushed-out meet point, the 0.9 support holds;
- against a human support who pulls every time the lane drifts back, a 0.9 bot is often at the camp before the aggro, and a 0.4 bot never is;
- the carry is never left alone with both enemy laners while the support watches (expect `enemy-in-lane` aborts).

### 7. Docs

- **`HUMANISER_DEV.md`:** a "Pull forecast" subsection under the camp jobs and pulls section, the pre-contest under counter-play, the new flags in the flags table, and the new telemetry.
- **`docs/ARCHITECTURE.md`:** only if it lists lane module responsibilities in enough detail to go stale.

## Left to the builder

- Exact type weights from `npc_units.txt`, and whether siege creeps need special treatment.
- Whether smoothing the imbalance is needed (decide from telemetry).
- How the lookout phase sits in `camp_jobs.ts`: a phase of `contest` as described, or a separate step function sharing `stepContest`. The behaviour above is what matters.
- Where in the snapshot refresh the `lane_eq` sample is taken, as long as it's once per team, lane and cycle.

## Calls I made (not discussed with you)

- Creeps only in the forecast; hero pressure is out of scope.
- The forecast is a single constant `K` times a normalised imbalance, not a simulation of the clash.
- The forecast changes only the default pull branch; freeze, mid and cover-core keep reading the current position.
- `Foresight` is linear from 0 to 1, so skill 0 is identical to today.
- The pre-contest reads the enemy's lane at full forecast weight; skill instead decides whether the bot tries at all (gate 0.7 plus the `CounterNotice` roll).
- `PreContest` defaults on.
- The pre-contest reuses the `contest` job with a new `lookout` phase instead of a new job kind (`watch` is already the pull's wave-watch phase).
- Starting values for `K`, type weights, lead, wait and stand distance.
