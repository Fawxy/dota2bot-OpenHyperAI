# Contract: `laneTargets` (with `laneFarm`'s `pick`)

```
name / version / owner:  laneTargets / 1 (slice 5a, 30/10/2026) / engine (main loop)
layer:          game fact
intent:         The lane creeps a laner could go for next, with when each becomes killable by its own swing; no choice.
applicability:  A bot handle with GetAttackDamage, GetAttackPoint and GetNearbyLaneCreeps; without them the result is an
                empty list (never an error). Creeps without a location (fog) or already dead are left out.
inputs:         opts.radius (default max(800, attack range + 400), taste); opts.within (s, default 1, taste);
                opts.lastHit / opts.deny (default true: enemy creeps to last-hit, allied creeps to deny). The adapter's
                lastHitFilter (host etiquette) drops enemy creeps the host forbids.
effect check:   none (a query; no order is issued).
outcomes:       a list of { creep, kind: "lasthit" | "deny", eta (s), ranged (bool) }, enemy creeps first, then allied
                ones, each side in the host's creep order; empty when nothing is due. eta = max(walk into attack range at
                the current speed, (believed HP at our hit - own damage) / incoming DPS), exact (no skill error).
timing:         one scan of the creeps within radius; per-frame creep queries are cached per bot.
interruption:   n/a (a query).
skill:          none (exact prediction; lastHit/deny draw Skill error when they swing).
telemetry:      none (laneFarm's caller logs ev=lh per attempt).
fixtures:       engine test_lasthit "targets:" cases; test_lane "no pick"; bot test_lane_pick, test_states_laning_body.
evidence:       none (radius and within are taste; the eta maths is the lastHit fact's).
consumers:      engine laneFarm (pick receives this list; without pick, laneFarm only holds its spot); bot states/laning
                via states/lane_pick Choose; slice 5's core last-hit choice (docs/team/ROADMAP.md row 5).
status:         offline-verified (no in-game caller with last hits on by default; slice 5's ER will say)
```
