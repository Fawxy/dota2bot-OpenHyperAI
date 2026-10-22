# Take the pull — design

Date: 23/10/2026. Builds on the pull-forecast and pre-contest work (`2026-10-23-pull-forecast-and-precontest-design.md`).

## Why

In `console.9057013636.log` (t≈160–180 s, Radiant safe lane), CM pulled our small camp and, half a second later, Lion pulled
`dire_off_large`. Both waves left the lane. Slark (pos 1) stood in lane for 20 s, flipping laning/team_roam/retreat, while the
Dire creeps died to neutrals in their camp. A decent carry walks over and takes those last hits: the lane is empty, so it costs
nothing, and it denies the puller the XP and gold the pull was for.

Today nothing can do this:

- `Counter.respondToPull` lets only the lane's camp-job owner (the support) contest, and only when it has no job running. CM was
  pulling, Slark is not the owner.
- The `contest` job hits the enemy *hero* (`contestTarget`) and ends `no-target` without one; it never touches the pulled creeps.
- A running contest is continued through `jobAllowed` → `LaneRoles.MayRunCampJob`, which aborts a non-owner as `not-owner`.

The pre-contest has the same owner and busy checks, so it would not have helped either.

## Goal

A laner who is not the camp-job owner answers a noticed enemy pull, when its own lane has nothing to stay for, by walking to the
enemy pull camp and last-hitting the pulled enemy lane creeps there. Skill-gated and humanised through the existing last-hit model.

Non-goals: chasing or fighting the puller (the existing contest and punish do that); denying our own pulled creeps; taking pulls
outside the laning phase; predicting the pull (the pre-contest's job).

Anti-goals: a carry walking under an enemy tower, through unseen enemies, or into a 2v1 for a few creeps; a carry leaving a wave it
should be farming.

## Behaviour

### Start (counterplay, `respondToPull`)

For each live, noticed, not yet answered `pull` or `half_pull` signal, after the existing pre-contested and punish branches, a bot
that is **not** `LaneRoles.CampJobOwner(s)` starts a take when all hold:

1. Flag `TakePull` on and `SkillOf(bot) > Gates.TakePull` (0.5). The notice roll already scales how often a pull is seen; the gate
   keeps low difficulties from doing this at all.
2. Nothing committed this cycle (`LanePlanner.Committed`) and no camp job running (`CampJobs.Active`).
3. The lane has nothing to stay for: `s.enemy.count <= Thresholds.TakePullLaneCreeps` (1).
4. The signal names a camp whose box centre is reachable within `Timing.MaxTravel` (12 s) and `pathSafe` (as the contest).
5. No enemy tower within `Thresholds.EnemyTowerRange` of the camp's box centre.
6. HP at or above `Thresholds.JobMinHP` (`CampJobs.Start`'s existing gate).

It then calls `CampJobs.Start(bot, { kind: "contest", campIdx, targetPid, take: true })` and marks the signal answered. A failed
check leaves the signal for later frames while it stays live, as the owner's contest does.

The owner's contest and the take are independent: if the support is free it contests the puller, and the core may take the creeps
at the same time.

### Executor (`camp_jobs`, contest with `take`)

Stand point: the camp's box centre; phase `travel`, telegraphed (no ping). Each frame:

1. Pulled creeps: visible enemy lane creeps (`GetNearbyLaneCreeps(..., true)`) within `Radii.TakePullCreeps` (800) of the stand.
2. If one is killable now (`LastHitSkill.WillKill` with the bot's attack damage and attack delay), take the one
   `LastHitSkill.Choose` picks: attack it, `NoteAttempt`, and keep the frame on that swing for up to `Timing.TakePullSwing` (1 s).
3. Else, with creeps present: walk to the lowest-HP creep while it is out of attack range, otherwise hold (`lane:take_pull`).
4. No creeps: walk to the stand; once there, end `no-creeps` after `Timing.TakePullWait` (3 s) with none seen.

Ends: `no-creeps`; `timeout` after `Timing.TakePullMax` (15 s) from the start (instead of `ContestMax`); `outnumbered` when
`Thresholds.TakePullDangerEnemies` (2) or more visible enemy heroes are within `Radii.TakePullDanger` (1200) of the bot; `low-hp`
below `JobMinHP`. The take does not use `MayRunCampJob`. Retreat and other higher modes still preempt it through the contest's
desire (`ContestDesire` 0.65).

### Telemetry

- `lane_job_start` carries `take=1`.
- `lane_job_end` (contest) carries `take=1` and `swings=<n>`, the last-hit swings it made.
- `tools/hlog` prints `take-pull: started=<n> swings=<n> no-creeps=<n> timeout=<n> outnumbered=<n> aborted=<n>`.

## Config

- Flag `TakePull: true`.
- `Gates.TakePull: 0.5`.
- `Thresholds.TakePullLaneCreeps: 1`, `Thresholds.TakePullDangerEnemies: 2`.
- `Timing.TakePullMax: 15`, `Timing.TakePullWait: 3`, `Timing.TakePullSwing: 1`.
- `Radii.TakePullCreeps: 800`, `Radii.TakePullDanger: 1200`.

## Calls made without asking

- Any non-owner laner can take, not only pos 1/2: in a two-lane that is the core, which is the case seen.
- The wave-anomaly `pull` signal names the first pull camp; with two enemy pull camps it can name the wrong one, and the take then
  ends `no-creeps`. Accepted rather than adding camp disambiguation.
- Last hits only. No hitting the creeps down and no attacking the puller.

## Tests (offline)

- A noticed pull, bot is the core (not owner), empty lane: a contest job with `take`, at the camp.
- Each start check blocks it: owner, lane still has 2 enemy creeps, skill 0.4, enemy tower by the camp, unsafe path, flag off.
- Executor: walks to the camp; last-hits only a killable creep (an unkillable one is not attacked); ends `no-creeps` 3 s after
  arriving with none; ends `outnumbered` with two enemy heroes beside it; does not abort as `not-owner`.
- Telemetry: `lane_job_end` with `take=1 swings=1`; hlog counts it.

## In game

Run `oha/bots` (re-point the `scripts/vscripts/bots` symlink) and check `take-pull:` in the hlog summary: takes should mostly end
`no-creeps`/`timeout` with swings > 0, rarely `outnumbered`.
