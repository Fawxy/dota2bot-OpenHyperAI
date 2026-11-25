# Contract: `attackReach` (fact)

```
name / version / owner:  attackReach / 1 (slice oha-creep-reach, 26/11/2026) / engine (main loop)
layer:          game fact (no choice, no action)
intent:         The centre-to-centre distance within which an attacker begins an attack on a target without moving, so
                the verbs, the walk estimate and their callers test and plan against one quantity.
applicability:  An attacker handle with GetAttackRange and a target handle; GetBoundingRadius is optional on either (a
                handle without it counts 0, so engine fakes keep the bare attack range).
inputs:         attacker, target, range? (the attacker's attack range when the caller has already read it this frame).
sources:        Valve API reads only: GetAttackRange, GetBoundingRadius of both units.
outcomes:       a distance in game units: range + attacker hull + target hull. Inside it a swing starts with no move order;
                outside it the verb walks (lastHit/deny `why=range d=<distance left to the reach>`).
timing:         pure arithmetic on three reads; no per-frame state.
interruption:   n/a.
skill:          none.
telemetry:      none of its own; the bot logs it as `rch` on the creep row's start line.
fixtures:       engine test_lasthit "in reach beyond the range", "outside the reach", "laneTargets: the walk to reach".
evidence:       commit 628bfdd0's measurement from banked games: 21,212 hero attacks on lane creeps begun within 0.12 s of the
                creep's death (ev=creep_death pNd, pNr, pNt, pNa), 1,394 games. Attacks began up to range + 40 from a melee
                creep (hull 16) and range + 32 from a ranged creep (hull 8) for heroes of hull 24 (ev=cut hulls); 28 began
                farther; siege none beyond range + 40. UNVERIFIED: that the hero did not move in those attacks (the log gives
                its place at the creep's death), heroes of another hull, siege creeps' hull.
consumers:      engine strike (lastHit, deny) and etaOf (laneTargets' walk); bot creep_offer `Reach` (the stand spot, the row's
                reads) and creep_row `Need` and its `tin` test.
status:         offline-verified (engine tests above; in game: crr1a/crr1b rig games, one an arm, no fault seen)
```
