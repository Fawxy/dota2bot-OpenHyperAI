# Contract: `laneFarm` (posture verb)

```
name / version / owner:  laneFarm / 1 (slice 5, 31/10/2026: first contract; adds `retarget`) / engine (main loop)
layer:          atomic composite (holdAt, lastHit, deny)
intent:         A laner holds a spot and breaks off for the lane creeps its caller picks, swinging with lastHit/deny.
applicability:  A bot handle; `spot()` read every frame (undefined: no spot to hold). Without `pick` it only holds (the
                engine makes no choice of its own); with `lastHits()` false it only holds.
inputs:         spot (function); opts.hold (holdAt options); opts.lastHits (default always); opts.within (laneTargets',
                default 1); opts.pick (caller's choice from laneTargets' offers); opts.leash (900), near (600), far (1200),
                scanEvery (0.1 s), contestRadius (1000), retarget (default false): all taste. opts.label, onAttempt,
                deadline, interruptIf.
effect check:   per attempt, lastHit/deny's own (the bot's last-hit or deny counter rises).
outcomes:       the verb: dead | interrupted (interruptIf) | timeout (deadline); never ok by itself. Per attempt, through
                onAttempt(target, result, contested): lastHit/deny's outcomes, plus interrupted with message suffix `sw=1`
                when `retarget` dropped the attempt for another creep.
timing:         one laneTargets scan per scanEvery while holding; with `retarget`, also while an attempt waits for its
                creep. An attempt waits up to its creep's eta + 1.5 s; a pass that took no frame yields once.
interruption:   interruptIf and deadline end the verb; an attempt is dropped beyond the leash. With `retarget`, an attempt
                is dropped before its swing once its creep is no longer among laneTargets' offers and pick chooses another
                (the creep's handle compared across scans: same handle per unit in game, s5c, see below).
skill:          none of its own (lastHit/deny draw the Skill error).
telemetry:      none (the caller logs ev=lh per attempt from onAttempt).
fixtures:       engine test_lane (skill 1 farm, lastHits off, no pick, skill scaling, leash, retarget on/off, dead,
                interrupted); bot test_states_laning_body.
evidence:       handle identity across laneTargets calls: in-game, ER-007 re-run s5c game 1 (31/10/2026), 15 of 233
                Radiant core attempts switched, mean wait 0.95 s before the switch (a failed identity would switch every
                attempt at its first 0.1 s scan).
consumers:      bot states/laning (the laning body; retarget on).
status:         offline-verified (in-game result for slice 5: ER-007)
```
