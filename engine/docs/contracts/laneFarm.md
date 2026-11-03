# Contract: `laneFarm` (posture verb)

```
name / version / owner:  laneFarm / 3 (slice 5, 30/10/2026: first contract; adds `retarget`. Slice l1-support-deny, 02/11/2026: adds `dropLost`. Slice lane-last-hits, 03/11/2026: `pick(targets, current)` asked while an attempt waits) / engine (main loop)
layer:          atomic action (a composite of holdAt, lastHit and deny)
intent:         A laner holds a spot and breaks off for the lane creeps its caller picks, swinging with lastHit/deny.
applicability:  A bot handle; `spot()` read every frame (undefined: no spot to hold). Without `pick` it only holds (the
                engine makes no choice of its own); with `lastHits()` false it only holds.
inputs:         spot (function); opts.hold (holdAt options); opts.lastHits (default always); opts.within (laneTargets',
                default 1); opts.pick(targets, current?) (caller's choice from laneTargets' offers; with `retarget`, while
                an attempt waits for its creep and the creep is still offered, `current` is that creep's fresh offer and
                the answer decides the wait: `current`'s creep or undefined keeps it, another creep ends it for that
                one); opts.leash (900), near (600), far (1200),
                scanEvery (0.1 s), contestRadius (1000), retarget (default false), dropLost (default false; acts only with retarget): all taste. opts.label, onAttempt,
                deadline, interruptIf.
effect check:   per attempt, lastHit/deny's own (the bot's last-hit or deny counter rises).
outcomes:       the verb: dead | interrupted (interruptIf) | timeout (deadline); never ok by itself. Per attempt, through
                onAttempt(target, result, contested): lastHit/deny's outcomes, plus interrupted with message suffix `sw=1`
                when `retarget` dropped the attempt for another creep, or `sw=0` when `dropLost` dropped it and pick chose
                nothing.
timing:         one laneTargets scan per scanEvery while holding; with `retarget`, also while an attempt waits for its
                creep. An attempt waits up to its creep's eta + 1.5 s; a pass that took no frame yields once.
interruption:   interruptIf and deadline end the verb; an attempt is dropped beyond the leash. With `retarget`, an attempt
                is dropped before its swing when pick(offers, current) answers another creep while its creep is still
                offered, or once its creep is no longer among laneTargets' offers and pick(offers) chooses another (the
                creep's handle compared across scans: same handle per unit in game, s5c, see below); whether a switch is
                worth the attack cooldown is pick's rule, not the verb's. With `dropLost`, also when pick chooses nothing
                for a creep no longer offered, and the verb goes back to holding.
skill:          none of its own (lastHit/deny draw the Skill error).
telemetry:      none (the caller logs ev=lh per attempt from onAttempt).
fixtures:       engine test_lane (skill 1 farm, lastHits off, no pick, skill scaling, leash, retarget on/off, dropLost on/off, dead,
                interrupted, switch/keep two-waves: a switching pick takes both creeps, a keeping pick loses one); bot
                test_states_laning_body, test_lane_pick (the switch rule).
evidence:       handle identity across laneTargets calls: in-game, ER-008 re-run s5c game 1 (30/10/2026), 15 of 233
                Radiant core attempts switched, mean wait 0.95 s before the switch (a failed identity would switch every
                attempt at its first 0.1 s scan).
consumers:      bot states/laning (the laning body; retarget on; dropLost on for a deny-only Radiant support,
                slice l1-support-deny). Its pick is lane_pick.Choose: a waited-on creep is left only for one killable
                now (eta <= 0.2 s) while the current is at least 0.5 s from due, a last hit always replaces a deny wait,
                a deny never replaces a last-hit wait (slice lane-last-hits; ChooseDeny for a deny-only support ignores
                `current`).
status:         offline-verified (in-game result for slice 5: ER-008; dropLost: ER-012)
```
