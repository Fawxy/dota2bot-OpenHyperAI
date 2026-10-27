# Decision fixtures (rung E1)

A fixture is a frozen situation plus what the bot must and must not do in it. `tests/humaniser/fixtures.js` runs every
fixture here offline, in seconds, against the real bot code in fengari. The format follows the master template
`docs/templates/fixture.md`; this file is the bot-side reference for the runner, its drivers and its terms.

```
cd tests/humaniser
npm run fixtures            # every active fixture; prints fixture_pass_rate (GOALS KR 0.3); exit 1 on any failure
npm run fixtures:controls   # negative controls (below)
node fixtures.js f4 --json  # fixtures whose path contains "f4", or by id; JSON output
node fixtures.js --root <dir>   # run against the bots/ under <dir> instead of this checkout
```

## Fields
| field | |
|---|---|
| `id` | `area.verb.slug.nnn`, unique |
| `source`, `ref` | `log` + `{log, t}`; for a review finding that names a game but no moment, `{log, finding}` (the 23/10/2026 priority-fix findings F1-F9, bot repo `docs/superpowers/plans/2026-10-23-humaniser-priority-fixes.md`). Also `replay`, `playtest`, `evidence-card` as in the template |
| `status` | `active` (counted), `quarantined` (run and shown, not counted), `retired` (skipped; needs `reason`) |
| `decision` | the driver, `tests/humaniser/fixture_drivers/<decision>.lua` |
| `control` | `{commit, outcome: fail|pass}`: the commit just before the fix the fixture encodes, and what the fixture does there |
| `conditions.skill` | `[lo, hi]` runs at lo, the midpoint and hi; a number runs once; none runs once at the driver default |
| `world` | the driver's input (each driver's header lists its fields) |
| `expect` | `must` (all hold), `mustNot` (none holds); `acceptable` is documentation only |
| `tolerance.value` | for `==`/`<=`/`>=` on numbers (default 1e-6) |

## Expectation terms
- **Action** `verb` or `verb(target)`: some observed action has that verb (and target). Targets are `creep#<id>`,
  `hero#<pid>`, a technique (`aggro_pull`) or a reason (`survive`, `margin`, `rune`).
- **Comparison** `a <op> b` with `<op>` one of `< <= > >= == !=`, where `a` and `b` are numbers, `desire.<mode>` or
  `fact.<name>`. A value the driver did not observe is an error (the term fails).

Write the outcome, not today's number: "retreat stays at OHA's desire" (`desire.retreat <= fact.base`), not
`desire.retreat == 0.85`. A `mustNot`-only fixture needs a positive control, a sibling fixture showing the same world
does produce the action when the condition is absent; otherwise it passes when the world never wanted the action.

## Drivers and their verbs
| decision | runs | verbs and values |
|---|---|---|
| `laning_mode` | `mode_laning_generic` GetDesire + Think, stub humaniser (`laning_mode_world.lua`) | `lastHit(creep#)`, `deny(creep#)`, `hold`, `move`, `attempt(creep#)`; `desire.laning` |
| `retreat_desire` | Transitions caution tick, then Intent.Resolve on retreat (hook H3), `lane_world.lua` | `desire.retreat`, `fact.base`, `fact.caution` |
| `lane_prethink` | `Lane.PreThink` (block, pulls, aggro draws, tower swap) over frames | `attack(<id>)`, `move`, `commit(<tech>)`; `fact.acted` |
| `kill_check` | `LaneFight.KillCheck.Check` | `kill`, `noKill(<reason>)`; `fact.margin` |
| `lane_fight` | a lane fight played at 30 fps with mode scoring (`lane_fight_world.lua`) | `commitEnd(<reason>)`, `committing`; `desire.retreat`, `desire.roam` |
| `core_trip` | `FarmPattern.StartGate` then `Desire` (`farm_world.lua`) | `noTrip(<reason>)`, `trip(camp#)` |

The verbs are this runner's vocabulary until behaviour contracts exist (`docs/contracts/`); they move there then. The
worlds are the hand-built test worlds the unit tests already use, so a driver adds no new simulation.

## Negative controls
`npm run fixtures:controls` exports `bots/` at each fixture's `control.commit` (cached in the temp directory) and runs the
fixture there. A fixture that encodes a bug must fail before its fix (`outcome: fail`), and it should fail on behaviour,
not with an error (the output says "fails (by error)" otherwise). A guard or positive control passes before and after
(`outcome: pass`). Any other result is reported as `BAD` and exits 1. Controls are run when a fixture is added or its
driver changes; they are not part of `npm run check` because they need git.
