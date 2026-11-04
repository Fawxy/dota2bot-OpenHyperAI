# Contract: `lastHit` and `deny` (atomic actions)

```
name / version / owner:  lastHit, deny / 3 (slice pre-hit, 05/11/2026: an attacker with a wind-up seen or a projectile in flight is phased: its repeats
                within the horizon are counted and its rate is not spread; v2 slice lasthit-windup-logs, 04/11/2026: the enemy-hero watch fields `hf hwf ha hc
                hpt` on every message and an enemy-hero query each frame; v1 slice lane-last-hits, 03/11/2026: first
                contract, written as the kill belief, the outcome rule and the message fields changed) / engine (main loop)
layer:          atomic action (one swing on one lane creep, confirmed on the bot's last-hit or deny count)
intent:         Swing once at a lane creep so the hit lands as the killing blow (lastHit: an enemy creep; deny: an allied
                creep below half HP), waiting in attack range until the bot believes a swing ordered now does that.
applicability:  A bot handle with GetAttackDamage and GetAttackPoint (deny: also GetDenies); otherwise `unsupported`.
                With `target` given the caller has chosen the creep (laneFarm does, from laneTargets through its
                `pick`); without it the verb picks the creep closest to dying within `searchRadius` (needs
                GetNearbyLaneCreeps, else `unsupported`; no in-game caller omits `target`). The adapter's `lastHitFilter`
                (host etiquette) vetoes enemy creeps for lastHit only: `etiquette` when it vetoes the target or every
                candidate, `no_target` when there is none.
inputs:         target (creep handle); opts.maxWait (s, default 1.5, taste: laneFarm passes eta + 1.5); opts.deadline;
                opts.searchRadius (default attack range + 300, taste); opts.hold (tag for the adapter's hold while
                waiting); opts.interruptIf.
                Kill belief (game facts, each frame): own hit time = attack point / attack speed + cooldown left (with the
                adapter's attackClock) + projectile flight for a ranged bot (dist - 39, over projectile speed); incoming
                damage = attack projectiles in flight at the creep plus every visible attacker of either team winding up
                on it whose hit lands at least one server tick (0.034 s) before ours, after armour
                (GetActualIncomingDamage); a tower's or creep's hit in flight or winding up repeats one attack cycle
                later within the horizon (its phase is known; the repeat assumes it stays on the creep, UNVERIFIED in-game
                as for hpForecast; slice pre-hit, 05/11/2026); past 0.45 s of horizon the
                DPS of the attackers with no such hit (between swings, phase unknown) is extrapolated over the rest;
                the creep's own HP loss over the last 1.5 s of waiting (less its largest
                single-frame drop) is a lower bound on the rate, and the part of it the indexed attackers and regen do
                not explain is extrapolated over the horizon. Own damage = (attack damage - damage variance) after
                armour. Due when the creep survives the seen hits and the believed HP at our landing <= own damage.
                The wind-up formula (attack point as a fraction of the attack cycle) is UNVERIFIED in game.
effect check:   ok once the bot's GetLastHits (GetDenies) count rises, checked each frame until 0.5 s past the predicted
                landing.
outcomes:       ok | missed | taken_by_other | denied | timeout | no_target | etiquette | dead | interrupted |
                unsupported. missed: the creep was alive at the predicted landing, or our attack fired and the creep
                was gone after the landing without the kill, or nothing resolved 0.5 s past the landing (early or wrong
                belief). taken_by_other: the creep was gone at or before the predicted landing without our attack
                having fired, including during our wind-up (a late belief); alive at the landing takes precedence
                (missed). denied (lastHit only): taken_by_other with an enemy hero attacking it as it died.
                timeout: not due within maxWait or past the deadline (no swing). dead: the bot died. interrupted:
                interruptIf fired. The per-frame `Skill` error rolls the belief early or late; there is no random
                "don't try".
timing:         one belief per frame while waiting (creep queries cached per bot per frame; enemy heroes queried once
                per frame, cached the same way, for the enemy-hero watch; allied heroes and towers only once a swing
                decision is due); at most maxWait of waiting plus own hit time + 0.5 s to resolve.
interruption:   interruptIf and deadline while waiting; once the swing is ordered the verb only watches (the attack
                is not cancelled).
skill:          Skill.lastHitError (width) and the per-creep roll: a negative shift shortens the relied horizon (swings
                late), a positive one extends it with the attackers' DPS (swings early); eps scales own damage. At
                skill 1 the belief is exact.
telemetry:      none of its own; the Result message carries the calibration fields for the caller's ev=lh: `w hp pred
                mine t m obs idps end dt fa lhp fg` (wait, HP and believed HP at the order, own damage, hit time,
                frame margin, observed and indexed damage rate, HP at the end, order-to-end time, order-to-fire time or
                -1, HP on the first frame at or past the landing or -1, mean frame gap), and before `end`, only when the swing
                counted enemy hero wind-ups, `ew er ec oc` (how many, due only because of them, their latest commit
                point and ours, seconds). Every message, swung or not, ends with the enemy-hero watch over the frames the verb
                watched the creep: `hf hwf` (frames an enemy hero's attack target was the creep, and of those the frames
                the wind-up reader read it winding up) and, when hf > 0, `ha hc hpt` (that hero's GetAnimActivity,
                GetAnimCycle, GetAttackPoint, from the last wind-up frame once one was seen): the in-game check of the
                UNVERIFIED wind-up reading on heroes. Read by hlog `@lh_swings`.
fixtures:       engine test_lasthit (predict melee, hidden allies, fogged target, variance, turn, long horizon, think
                gap, observed rate, killed in our wind-up, wind-up once, projectile in flight, calibration fields,
                enemy hero wind-ups relied on, not relied on, and under a lapse, hero watch (relied on, idle hero aimed at
                the creep, two heroes with one wind-up frame),
                deny 50% rule, etiquette); bot test_states_laning_body.
evidence:       calibration in lane-only games llhscn1 and llhscn2 (03/11/2026, slice lane-last-hits: relied horizon,
                wind-up double count); the 0.45 s look-ahead sits just under a lane creep's 0.467 s attack point (game
                file); the kill belief is otherwise game-fact maths with no tuned numbers. maxWait, searchRadius, the
                0.5 s resolve slack, the 0.25 s cooldown queue and the frame margin bounds are taste.
consumers:      engine laneFarm (every attempt); bot states/laning through it (cores: last hits and denies; deny-only
                supports: denies).
status:         offline-verified (in-game: the slice's check run, docs/team/slices/lane-last-hits.md)
```
