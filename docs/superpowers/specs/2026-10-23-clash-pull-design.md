# Clash pull — design

Date: 23/10/2026. Builds on the pull trace (`lane_pull_trace`) and the lane-at-meet gate (`Flags.PullLaneGate`), both in
`docs/HUMANISER_DEV.md`.

## Why

A timed pull hits the camp on a fixed second so the neutrals reach a fixed meet point just before our next wave walks past
it. On 7.41 the creep meeting point moved toward the off lane, and Radiant's off-lane pull (`radiant_off_large`, Dire's hard
camp beside their safe-lane T1) now meets the lane fight: in `console.9057326631` and `9057329817` our creeps were within 800
of the meet at the hit in 4 of 7 pulls, and none of those diverted a single creep. The wave was on time; the neutrals reached
the meet about 3.5 s after the hit and left about 2 s later. Creeps busy with the enemy wave do not turn to the neutrals.

The lane-at-meet gate now skips those pulls. A player in that spot uses a different pull: wait at the camp while the two waves
fight, and hit the camp so the neutrals reach **the fight** as the last enemy creep there dies. Our surviving creeps, with
nothing left to hit, take the neutrals instead, and the wave is pulled from where it stands.

## Goal

When a planned pull is skipped because our creeps are already at its meet point, a skilled support may instead run a clash
pull: hit the camp at a moment read from the fight, not the clock, and lead the neutrals to the fight's location.

Non-goals: replacing timed pulls where they work; pulling while the enemy wave is winning; hitting the enemy creeps down
itself to speed the clash up; stacking or double pulls in this style.

Anti-goals: a support standing at an enemy-side camp for many seconds with nothing to show; a support leading a camp into
enemy heroes at the front; a pull that drags the camp so far that it goes home before it arrives.

## Behaviour

### When it is chosen

A clash pull is not tied to a pull second. `camp_jobs.schedule` gets its own entry for it, before the timed pulls' start
window check (`windowFor`): any time in the cycle that the planner wants a `full_pull` or `half_pull`, the lane-at-meet
gate would refuse it, and the cycle has no technique yet, a clash pull starts when all hold:

0. The lane needs fixing: `LanePlanner.Plan` picks `full_pull` or `half_pull`. That is the planner's existing judgement
   (where the lane is against where this lane kind wants it, with the forecast weighted by skill), asked at any second of
   the cycle instead of only near a pull second. Whether to pull is the planner's; when to hit is the clash's.
1. `Flags.ClashPull` on and `SkillOf(bot) >= Gates.ClashPull` (0.7).
2. The checks a timed pull passes apart from its window: planner choice, `StartBlocked`, owner, travel to the stand
   ≤ `MaxTravel`, `CampsUp(now)`.
3. Our creeps are winning the clash: `s.allyPower > s.enemyPower` and at least `Thresholds.ClashAllyMin` (2) of our lane
   creeps in `s.ally.units`. "The clash" is always the snapshot's front creeps (`s.ally.units`, `s.enemy.units`): the start
   check, the aborts and the clear-time read use the same sets.
4. The fight is in reach of the camp: the camp's lead path with its meet replaced by the fight point
   (`PullTiming.LeadPath(pull, fight)`) is at most `Radii.ClashPullReach` (2000) long from the spawner origin. 2000 is a
   start: the longest meet in use is ~1450 from its camp, and the trace will show where the camp starts giving up.

Otherwise the gate's `lane_plan gate=lane-at-meet` stands. A clash pull is the cycle's technique, as a full pull is: one
per cycle, the cycle spent (`doneCycle`) once the job has acted, whatever it ends with.

A timed pull aborted `lane-at-meet` just before its hit (the gate in `orderAggro`) does not spend the cycle, so the clash
entry may start one in the same cycle. The timed job is not converted in place.

### The fight point

`s.frontLoc` (our lane front), moved `Radii.ClashStandOff` (400) toward the camp's spawner origin, the side the neutrals
come from, so they stop inside our creeps' acquisition range rather than in the middle of the enemy laners. Re-read every
frame until the hit; fixed from the hit. The reach check (4) uses this point.

### When to hit

The support walks to the camp's stand point (as a full pull) and waits there. Each frame it reads the clash at the fight
point: the total HP of `s.enemy.units`, and how fast it fell over the last `Timing.ClashRateWindow` (1.5 s), kept on the job
as (time, HP) samples. The predicted time to clear is HP / rate; until 1 s of history exists, or while the HP is not
falling, there is no prediction and no hit.

The camp needs `walk = WalkLength(origin, leadPath) / NeutralSpeed[type]` to reach the fight. The support hits when
`predicted clear <= walk + aggro lead`, so the neutrals arrive as the last enemy creep dies (arriving late chases a wave
that has started walking again). Aggro lead is the existing `aggroLead` (walk, wind-up, flight).

It does not hit, and the job ends, when:

- `lane-won`: our creeps are still at the front and no enemy lane creep is left there, before the hit (missed it);
- `clash-lost`: `s.allyPower <= s.enemyPower` or fewer than `ClashAllyMin` of our creeps left. Enemy creeps are seen
  through our creeps, so "none visible" only counts as `lane-won` while ours are there; with ours gone it is `clash-lost`;
- `outnumbered`: at the moment it would hit, `Thresholds.TakePullDangerEnemies` (2) or more visible enemy heroes within
  `Radii.TakePullDanger` (1200) of the fight point (the take's rule). One enemy laner at the front is normal laning and does
  not stop it; it does not hit and waits on, so this is not an end unless `wait-max` runs out;
- `next-wave`: the next enemy wave would reach the fight within `walk + Timing.ClashWaveMargin` (3 s) of the hit
  (`s.enemyArrivalSec`);
- `wait-max`: `Timing.ClashWaitMax` (15 s) at the stand without a hit;
- every abort a full pull already has (partner, HP, mode end, hands-off, preempted).

### After the hit

Same as a full pull: confirm the aggro, lead along the path to the fight point, watch, grade by divert (`FullPullMin`). The
watch ends `WatchSec` after the lead, with no `waveAt` (the wave is already there). `lane_pull_trace` measures at the fight
point.

## Telemetry

- `lane_job_start kind=clash` with `fight=x,y walk` (camp walk seconds).
- `lane_job kind=clash` graded as a full pull; `lane_job_abort kind=clash` with the reasons above.
- `lane_pull_trace` for clash pulls adds `pred` (predicted clear in seconds after the hit, from the last prediction before it)
  and `cleared` (seconds after the hit when no enemy lane creep was within `ClashFight` of the fight point, -1 if never).
  `pred` against `cleared` says whether the prediction works; `nIn`/`nLast` against `cleared` whether the camp arrived in time.
- hlog summary: a `clash pull:` line: started, graded ok/weak/no-divert, ends by reason, median `cleared - pred`.

## Config

- `Flags.ClashPull: true`; `Gates.ClashPull: 0.7`.
- `Thresholds.ClashAllyMin: 2`.
- `Radii.ClashPullReach: 2000`, `Radii.ClashStandOff: 400`, `Radii.ClashFight: 600`.
- `Timing.ClashRateWindow: 1.5`, `Timing.ClashWaitMax: 15`, `Timing.ClashWaveMargin: 3`.

## Calls made without asking

- Clash pulls run only where the lane-at-meet gate fires, so timed pulls are untouched.
- The clear-time prediction uses the observed HP drop, not creep attack stats, so it includes heroes and spells in the fight
  (the bot API declares no `GetSecondsPerAttack`).
- Stand-off 400, reach 2000, fight radius 600, skill gate 0.7 and the timing values are judgements to tune from the trace.
- A half pull refused by the gate becomes a full clash pull: there is no half version.
- `clash_pull` is a pull kind (`PULL_KINDS`): it is graded, traced and telegraphed as one and goes through `StartBlocked`;
  the lane-at-meet gate never applies to it.
- The wait at the stand relies on the existing aborts (partner, HP, mode end, hands-off) for safety; no new exposure check.
- The stand-off moves the fight point toward the camp, not along the lane.
- Two or more enemy heroes at the fight hold the hit; one does not.

## Tests (offline)

- The gate fires with our creeps winning at the front: a clash job starts instead of `gate=lane-at-meet`; with the enemy
  winning, skill 0.6, the flag off, or the fight beyond `ClashPullReach`, no clash job and the gate's line.
- No hit before 1 s of HP history; a hit once `predicted clear <= walk + lead`, not before.
- Ends `lane-won`, `clash-lost`, `next-wave` and `wait-max` in their cases, with no attack on the camp; holds the hit with two
  enemy heroes at the fight, not with one.
- Starts at a cycle second far from the camp's pull seconds (not window-bound); a timed pull aborted `lane-at-meet` before
  its hit leaves the cycle free for a clash pull; one clash pull per cycle.
- After the hit it leads to the fight point (stand-off applied) and grades as a full pull; `lane_pull_trace` carries `pred`
  and `cleared`.

## In game

Bots-only with `OwnLaningThink = 'all'`. Check the `clash pull:` summary and the trace: `cleared - pred` near 0, `nIn` near
`cleared`, and diverts on the clash pulls that hit.
