# Decision fixtures (rung E1)

A fixture is a frozen situation plus what the bot must and must not do in it. `tests/humaniser/fixtures.js` runs every
fixture here offline, in seconds, against the real bot code in fengari. The format follows the master template
`docs/templates/fixture.md`; this file is the bot-side reference for the runner, its drivers and its terms.

```
cd tests/humaniser
npm run fixtures            # every active fixture; prints fixture_pass_rate (the former GOALS.md KR 0.3); exit 1 on any failure
npm run fixtures:controls   # negative controls (below)
node fixtures.js f4 --json  # fixtures whose path contains "f4", or by id; JSON output
node fixtures.js --root <dir>   # run against the bots/ under <dir> instead of this checkout
```

## Fields
| field | |
|---|---|
| `id` | `area.verb.slug.nnn`, unique |
| `source`, `ref` | `log` + `{log, t}`; also `replay`, `playtest`, `evidence-card` as in the template |
| `status` | `active` (counted), `quarantined` (run and shown, not counted), `retired` (skipped; needs `reason`) |
| `decision` | the driver, `tests/humaniser/fixture_drivers/<decision>.lua` |
| `control` | `{commit, outcome: fail|pass}`: the commit just before the fix the fixture encodes, and what the fixture does there |
| `conditions.skill` | `[lo, hi]` runs at lo, the midpoint and hi; a number runs once; none runs once at the driver default |
| `world` | the driver's input (each driver's header lists its fields). YAML map keys arrive as strings (`{1: {hp: 45}}` gives `["1"]`); drivers convert with `tonumber` |
| `expect` | `must` (all hold), `mustNot` (none holds); `acceptable` is documentation only |
| `tolerance.value` | for `==`/`<=`/`>=` on numbers (default 1e-6) |

## Expectation terms
- **Action** `verb` or `verb(target)`: some observed action has that verb (and target). Targets are `creep#<id>`,
  `hero#<pid>`, a technique (`aggro_pull`) or a reason (`survive`, `margin`, `rune`). A verb not in the driver's list
  (the table below, `VERBS` in fixtures.js) makes the fixture invalid, so a misspelled `mustNot` cannot pass by never
  matching. Targets are not checked; spell reasons as the code logs them.
- **Comparison** `a <op> b` with `<op>` one of `< <= > >= == !=`, where `a` and `b` are numbers, `desire.<mode>` or
  `fact.<name>`. A value the driver did not observe is an error (the term fails).

Write the outcome, not today's number: "retreat stays at OHA's desire" (`desire.retreat <= fact.base`), not
`desire.retreat == 0.85`. A `mustNot`-only fixture needs a positive control, a sibling fixture showing the same world
does produce the action when the condition is absent; otherwise it passes when the world never wanted the action.

## Drivers and their verbs
| decision | runs | verbs and values |
|---|---|---|
| `threat_gate` | `SafeGather.TripGate` (Safe.At over a trip's walk, 4 s, away) on a world cut from a game (`ev=cut kind=gate`, `cut.js --kind gate --who CONSUMER`; vision at the walk points as logged) | `go`, `hold(<kill\|tower\|unknown>)`; `fact.reach`, `fact.missing`, `fact.mcut`, `fact.burst`, `fact.allies`, `fact.tower` |
| `retreat_leave` | `retreat.LeaveWhy` (`SafeGather.At` at the hero's own place) on a world cut from a game (`ev=cut kind=leave`, `cut.js --kind leave`; the deleted trade's holds are ignored on a banked cut) | `leave(<lethal\|tower\|heal\|threat>)`, `stay(under)`; `fact.ratio`, `fact.kill`, `fact.reach`, `fact.hp` |

A cut fixture's world is the game's, not hand-built: `node tools/hlog/cut.js <log> --pid P --t m:ss [--kind gate|leave|safe]` prints one with an
empty `expect` for the author to fill; `--check [--kind K]` replays up to 20 cuts of each answer the game gave and compares them with what it logged (a quick
look); `--check --all` replays every cut and judges the bar, 95% of each answer; `--list` finds moments by answer, pid and HP. A printed fixture's header gives the
distances and HP its notes quote.

A new cut kind: its driver builds the world with `fixture_drivers/cut_world.lua`, and `cut.js` gets one `DECISIONS` entry.
`cut.ts` never imports the decision's module: the decision calls `Cut.<Kind>` with values or, where `cut.ts` imports the
decision (`threat.ts`), registers through a setter (`Threat.SetGateCut`); a build does not catch a Lua `require` cycle. The
generated Lua under `bots/` is tracked and the drivers run on it: build before committing.

The verbs are this runner's vocabulary until behaviour contracts exist (`docs/contracts/`); they move there then. The
worlds are the hand-built test worlds the unit tests already use, so a driver adds no new simulation.

## Negative controls
`npm run fixtures:controls` exports `bots/` at each fixture's `control.commit` (cached in the temp directory) and runs the
fixture there. A fixture that encodes a bug must fail before its fix (`outcome: fail`) on behaviour: a failure by error,
including a term on a value the old code never produced, is `BAD`, because it only shows the old code lacked something. A guard or positive control passes before and after
(`outcome: pass`). Any other result is reported as `BAD` and exits 1. Controls are run when a fixture is added or its
driver changes; they are not part of `npm run check` because they need git. Duplicate ids and invalid fixtures fail both
modes.
