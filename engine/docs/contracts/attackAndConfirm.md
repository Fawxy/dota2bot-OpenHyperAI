# Contract: `attackAndConfirm` (atomic action)

```
name / version / owner:  attackAndConfirm / 1 (slice pre-hit, 04/11/2026: first contract; adds `aggroConfirms`) / engine (main loop)
layer:          atomic action
intent:         Order one queued attack on the unit `pick()` answers and finish once it is confirmed to have landed or fired.
applicability:  A bot handle with GetLastAttackTime (else `unsupported`).
inputs:         pick (function, re-asked when the target is lost); opts.findFor (s to keep asking pick before no_target),
                opts.confirmFor (s from the latest order to see it confirmed before missed), opts.searchAt (walked to while
                pick finds nothing), opts.hold (adapter hold tag while waiting), opts.confirmed (extra host check),
                opts.aggroConfirms (default true), deadline, interruptIf.
effect check:   the bot's last attack time rises past its reading at the order (never compared with another clock); or,
                unless aggroConfirms is false, the target is attacking the bot (an aggro pull); or opts.confirmed().
                aggroConfirms false where the target may already be on the bot before the attack fires (laneFarm's
                prehit: a lane creep under fire next to the bot).
outcomes:       ok | missed (no confirmation within confirmFor) | no_target (pick found nothing within findFor) | dead |
                interrupted | timeout | unsupported.
timing:         one Action_AttackUnit per target; a target that dies or vanishes before confirmation is dropped and a new
                one picked and ordered the next frame, which restarts the confirmFor clock.
skill:          none.
consumers:      laneFarm's `prehit` (aggroConfirms false); bot job verbs (aggro draws, pull, stack: default); engine testing
                helper.
status:         offline-verified (aggroConfirms false: engine test_prehit). Notes: aggro confirmation was seen in game on
                23/10/2026 (dotactl log 2026-10-23T07-11-27-sdk_stack_aggro_diag_3.log, API.md "In-game checks
                outstanding"), a diagnostic, not a check run; aggroConfirms false in game: slice pre-hit check runs
                (prhchk2 on). In-game-verified once a run named in the pre-hit slice file shows it.
```
