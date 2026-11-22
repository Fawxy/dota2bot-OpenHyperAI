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
| `source`, `ref` | `log` + `{log, t}`; for a review finding that names a game but no moment, `{log, finding}` (the 23/10/2026 priority-fix findings F1-F9, bot repo `docs/superpowers/plans/2026-10-23-humaniser-priority-fixes.md`). Also `replay`, `playtest`, `evidence-card` as in the template |
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
| `laning_mode` | `mode_laning_generic` GetDesire + Think, stub humaniser (`laning_mode_world.lua`): tests the mode file's own logic; `CoreCanReach`, `WillKill` and `MayLastHit` are stubs | `lastHit(creep#)`, `deny(creep#)`, `hold`, `move`, `attempt(creep#)`; `desire.laning` |
| `team_roam` | `mode_team_roam_generic` Think alone (no GetDesire), in the `laning_mode` stub world | as `laning_mode`, no desire |
| `retreat_desire` | Transitions caution tick, then Intent.Resolve on retreat (hook H3), `lane_world.lua` | `desire.retreat`, `fact.base`, `fact.caution` |
| `core_trip` | `FarmPattern.StartGate` then `Desire` (`farm_world.lua`) | `noTrip(<reason>)`, `trip(camp#)` |
| `support_claim` | `states/lane_claims` `SupportClaim` for one creep, the cores' `laneTargets` and laning attempts given (`lane_world_fixture.lua`) | `claim(<deny\|free\|busy>)`, `noClaim` |
| `lane_spot` | `LaneSpot.Compute` and its `Threat.Read`, on a world cut from a game (`tools/hlog/cut.js` from `ev=cut kind=spot`; real map and lane paths) | `stand(<why>)` (pref, kill, unknown, creep, hp, tower, xp), `anchor(<anchor>)`, `read(<safe\|costly\|deadly>)` (`Safe.At` at the preferred point); `fact.x`, `fact.y`, `fact.pushed`, `fact.ratio`, `fact.pref` |
| `threat_gate` | `SafeGather.TripGate` (Safe.At over a trip's walk, 4 s, away) on a world cut from a game (`ev=cut kind=gate`, `cut.js --kind gate --who CONSUMER`; vision at the walk points as logged) | `go`, `hold(<kill\|tower\|unknown>)`; `fact.reach`, `fact.missing`, `fact.mcut`, `fact.burst`, `fact.allies`, `fact.tower` |
| `retreat_leave` | `retreat.LeaveWhy` (`SafeGather.At` at the hero's own place) on a world cut from a game (`ev=cut kind=leave`, `cut.js --kind leave`; what `Trade.Holds` said as logged) | `leave(<lethal\|tower\|heal\|threat>)`, `stay(<under\|join\|hitback>)`; `fact.ratio`, `fact.kill`, `fact.reach`, `fact.hp` |
| `pair_join` | `PairJoin.Decide` (D10) on a fight cut from a game (`ev=cut kind=join`, `cut.js --kind join`): both sides, their HP, the 3 s damage estimates both ways | `join(hero#<pid>)`, `out(losing)`; `fact.ko`, `fact.kt`, `fact.ours`, `fact.theirs` |
| `trade` | `Trade.Decide` (states/trade.ts: D18 hit, D24 hit back, D19 kill, D10 join, one decision for all five positions) on a frame cut from a game (`ev=cut kind=trade`, `cut.js --kind trade`; `trade2` on earlier logs): Safe.At here (`svh` without a hold, `svb` with one) and our speed `ms`, every candidate with its walk answer and catch read, the pair answer, a running play and the running exchange, as logged (the driver's header lists the fields) | `none(<first failed gate or end>)`, `hit(hero#P)`, `hitback(hero#P)`, `kill(hero#P)`, `join(hero#P)`; `end(<why>)` when a running exchange ended (`higher`: another candidate won the order); `hold(<hitback\|join>)` when `Holds` says retreat waits; `chance(<roll\|tower\|kill\|unknown\|wave>)` for a hit or none answer (the lane-fight chance, or what zeroes it); `endkinds(<reason=kind,...>)`: `Trade.ENDS`; `opens(<reasons>)`: the gates of every level that fail on the answer's target read fresh (slice trade-count), `-` for none; `fact.hp`, `fact.n` |
| `pick` | `LanePick.Choose` (states/lane_pick.ts: the laning body's creep pick) on a scan cut from a game (`ev=cut kind=pick`, `cut.js --kind pick`; the offered creeps, the wait, the pre-hit and the order of kinds as logged; `mine`, the walk-in limit and the idle swing found are the game's answers, not recomputed) | `<n>(<lasthit\|deny>)` (the offer's place), `pre(prehit)`, `idle(prehit)`, `none(none)` |

A cut fixture's world is the game's, not hand-built: `node tools/hlog/cut.js <log> --pid P --t m:ss [--kind spot|gate|leave]` prints one with an
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

## Coverage of the 23/10/2026 findings
Covered: F1 caution scale (2), F3 (1), F4 (4), F5 (2), F6 (4), F7 arrival credit, damage on the bot, core margin, local
allies (6), F8 abandon, tower aggro (4), F9 missing enemy, mid rune (3). Not covered yet: F2 (attack-mode claims that reach
no mode; nothing to observe offline), F1 `lane:cover` x1.25 stacking, F7 full-window regen and the missing-enemy margin,
F8 followers joining at margin 0.8, F9 pulls or stacks after a rune rotation, rotation re-checks, a core taking its
support's pull camp. "F1-F9 100%" (the former GOALS.md E.3) means 100% of these fixtures, not of every sub-finding.
