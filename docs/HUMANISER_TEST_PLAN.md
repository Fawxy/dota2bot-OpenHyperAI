# Humaniser in-game test plan

Tasks 01–07 were built and checked offline only (`tests/humaniser`: a LuaJIT syntax check, 1,086 behaviour tests in 19 files and 9 replay-mining tests). This plan covers what only the real game can verify. Run it in order: session 1 checks the assumptions the rest of the design rests on, so a wrong answer there may change later code.

Setup is in [HUMANISER_DEV.md](HUMANISER_DEV.md): symlink, lobby, `sv_cheats 1`. Set `Customize.Humaniser.Debug = true` for every session.

## Session 1: foundations (about 15 min, FretBots off, then on)
These answers decide whether code needs to change. Record each result in `HUMANISER_DEV.md`.
- [ ] **No Lua errors** in the console for 15 minutes, with FretBots off and with it on.
- [ ] **Shared-state probe:** read the `[H:probe]` lines (see "Shared-state finding"). Is `playersInThisModule` 1 or 5? Is `bothTeamsInThisModule` true? The orders bus works either way. Perception's teammate callout only works if modules are shared.
- [ ] **Skill resolution:** each bot prints `[Humaniser] pid=... skill=...` at the horn. Check:
  - FretBots off: Valve Easy gives 0.25, Unfair gives 1.0.
  - FretBots on: votes of 1 and 9 show `fret=true/1` and `fret=true/9` with source `chat`.
  - If the source shows `default`, the chat mirror missed the vote; note when you typed it.
- [ ] **Chat hub:** bot reply chatter still answers normal team chat, `!sp ru` still switches language, and `!htest gather` makes the 2 nearest bots acknowledge and walk to you.
- [ ] **Overlay:** each bot's block shows its mode, `skill`, `delay`, `order`, `percept`, `react`, `lasthit` and `ping`/`cmd` lines. Adjust `DIRE_X` in `debug.ts` if the Dire column is off-screen.

## Session 2: ping semantics (step 0 in the "Ping response (05)" section)
- [ ] Fill in the `normal_ping` table for each ping action. If danger pings come through as `normal_ping == true`, flip `Pings.IsDangerPing`.
- [ ] Ping the ground: the 2 nearest bots acknowledge with one chat line and one return ping.

## Session 3: feature checklists
Each section of HUMANISER_DEV.md has its own checklist, taken from the handoffs:
- [ ] Perception (03): fog exit, Lotus/BKB timing at `SkillOverride = 0.1` vs `0.9`, juke, smoke gank, FPS at `host_timescale 2`.
- [ ] Ally last-hit (04): human pos 1 with bot pos 5 and pos 4, at low, mid and high difficulty; log last hits at 5 and 10 minutes.
- [ ] Pings (05): hero, Roshan, tower and danger pings; two humans pinging at once; a dead bot declining.
- [ ] Commands (06): `!def mid`, `!rosh`, `!smoke`, `!lion push bot`, `!back`, `!farm`, `!bhelp`, `-都来守家`; confirm FretBots `!diff` and `!info` still work.

## Session 4: regression
- [ ] `Customize.Humaniser.Enable = false`: a 20-minute game behaves like upstream (Valve laning for supports, legacy ping response, no `[Humaniser]` lines).
- [ ] With each sub-feature disabled on its own (`Perception`, `AllyLastHit`, `Pings`, `Commands`), only that feature disappears.

## Session 5: lane management (07)
Setup and background are in the "Lane management (07)" section of HUMANISER_DEV.md. Launch with `-condebug` and `Debug = true`; work from a lobby with at least one human.

**Data calibration run** (first, so later sessions run on measured data)
- [ ] For every camp index, run `!hstacktest <idx>` and `!hpulltest <idx>` (and `!hpulltest <idx> half` for the pull camps) with a bot nearby; use `!hcamp` to find the index. Note which fail to start.
- [ ] Copy `console.log` out of the game folder and run `node tools/replay-mining/parse_condebug.js console.log`. Promote entries with a `suggest:` line to `source: "measured"` with `verifiedAt` (dd/mm/yyyy), as described in HUMANISER_DEV.md.
- [ ] Run through the in-game TODO list in HUMANISER_DEV.md ("Lane management (07)" and its phase sections) and record each answer.

**Scenarios 2-14** (spec numbering; run each at `SkillOverride = 0.9`, then at `0.2` or `0.4` where the spec gives a gate, and compare). The checklist with the exact expectations is in HUMANISER_DEV.md.
- [ ] 2 Full pull, 3 half pull (never at 0.4), 4 stack pull
- [ ] 5 Creep block at 0:00, 6 aggro pull and tower-aggro drop
- [ ] 7 No pull while the partner is in danger
- [ ] 8 Harass timing (human goes for 20 last hits: 0.9 punishes most, 0.2 some, at random times)
- [ ] 9 Enemy pull detection (human support pulls: 0.9 reacts most times, 0.2 rarely)
- [ ] 10 Fairness: all enemies fogged, no last-seen hints, no `counter pid=...` lines
- [ ] 11 Bot duo: never two aggro draws in one 3 s window; absent core covered
- [ ] 12 Human core (`!freeze`, `!shove`, inferred plan, lane-front ping hands-off for 30 s)
- [ ] 13 Human support (bot core reads your pulls and aggro draws, does not contest your camps)
- [ ] 14 Mid: block at 0:00, shove 15-20 s before runes, hands-off beside a human mid
- [ ] Overlay shows `lane`, `lane_tech`, `lane_exec` and `lane_job` lines updating, and no more than 1 chat line per bot per 10 s from the lane telegraphs.

**Regression (scenario 15)**
- [ ] `Lane.Enable = false`: a 20-minute game behaves like the pre-07 branch (laning, farm, rune and ping behaviour; no `[H:lane]` lines).
- [ ] Every `Lane.*` flag false (with `Enable = true`): same result.
- [ ] Each flag off on its own: only that behaviour disappears (`Harass = false` restores 04's original poke).

## Known risks to watch
- **Laning:** every allied bot on a team with a human uses OHA's laning `Think()` for the whole game, never Valve's (task 04). If laning gets worse, fall back to option B in the 04 handoff.
- **Channel delay:** delaying enemy `IsChanneling` affects every OHA use of it, not just interrupts. `Perception.Channel = false` disables only that part.
- **Commitment:** orders cap retreat while HP is above 50%, so bots may die more on orders. Ordered pushes also skip OHA's "never push alone" checks.
- **Avoidance zones:** they may only affect pathing via `GeneratePath`, not `Action_MoveToLocation`.
- **FretBots bridge option A** (`FretBridge.BridgeModifier`) is untested and off by default. Try it only after the chat mirror proves unreliable.
- **Leftover probe:** remove `SharedStateProbe` once the session 1 result is recorded.
- **Lane `OwnLaningThink = 'all'`:** it gives every bot, the enemy team included, OHA's laning `Think()` for the whole game in place of Valve's C++ laning. Only use it deliberately; compare lane results against `'allies'`.
- **Camp jobs:** pulls and stacks run at desire 0.7, so supports leave their lane for them (a pull is gated on partner safety, but a stack after laning has no partner). If supports die or vanish more than before, raise `Thresholds.StableEnemyRadius` or turn off `Stack` / the pull flags.
- **Untrusted seed paths:** pull and stack seconds, paths and the off-lane hard camp come from public guides and derived geometry and have not been measured on this patch (`data=seed` or `unverified` in `job-start`). Bad data means failed pulls and wasted trips, not errors; fix by promoting measured entries.
- **Replay data:** the Go replay parser is uncompiled and stack-only; half-pull data must be measured in-game.
