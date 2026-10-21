# Humaniser in-game test plan

Tasks 01–06 were built and checked offline only (`tests/humaniser`: a LuaJIT syntax check plus 204 behaviour tests). This plan covers what only the real game can verify. Run it in order: session 1 checks the assumptions the rest of the design rests on, so a wrong answer there may change later code.

Setup is in [HUMANISER_DEV.md](HUMANISER_DEV.md): symlink, lobby, `sv_cheats 1`. Set `Customize.Humaniser.Debug = true` for every session.

Launch Dota with `-condebug` and keep `Telemetry.Enable = true` (see "Telemetry and log analysis"). When something looks wrong, type `!mark <note>` and keep playing. After the session, run `node tools/hlog/analyse.js`: its checks cover most of the "No Lua errors", perception, order and etiquette items below, and `--mark N` shows what each bot was doing at a mark.

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
- [ ] Pings (05): hero, Roshan, tower and danger pings; two humans pinging at once; a dead bot declining. Danger-ping a jungle camp a bot is farming: it switches camp, then returns once a bot sees the camp is clear (about 6 s), or after 10 s if nobody can see it.
- [ ] Commands (06): `!def mid`, `!rosh`, `!smoke`, `!lion push bot`, `!back`, `!farm`, `!bhelp`, `-都来守家`; confirm FretBots `!diff` and `!info` still work.
- [ ] Last-hit trainer (14): see "Last-hit trainer (14)" below.

## Session 4: regression
- [ ] `Customize.Humaniser.Enable = false`: a 20-minute game behaves like upstream (Valve laning for supports, legacy ping response, no `[Humaniser]` lines).
- [ ] With each sub-feature disabled on its own (`Perception`, `AllyLastHit`, `Pings`, `Commands`), only that feature disappears.

## Last-hit trainer (14)
Setup: Local Host lobby, cheats on, `Debug = true`, then `!trainer on`. Details are in the "Last-hit trainer (task 14)" section of HUMANISER_DEV.md.
- [ ] **Spike results recorded** in `HUMANISER_DEV.md` (`!trainer spike`), and the `BarStyle`, `OutcomeOnly` and `ScreenText` defaults decided. Also check:
  - draws are visible with and without Debug
  - the bars are smooth, and the think rate is noted
  - which human-hero reads work
  - `GetAttackProDelayTime` gives sane values on the human
  - a Unicode text line renders or doesn't
  - optional: latency from bot chat to a FretBots `player_chat` listener
- [ ] **Free lane against Valve Passive bots:** the bar appears over the right creep and the green zone slides smoothly. Starting on the tick gets mostly `PERFECT`.
- [ ] **Deliberately early and late swings** are graded `EARLY` and `LATE`, with sensible HP and source reasons.
- [ ] **Cancelled swings and denies** are classified correctly.
- [ ] **Ignored creeps:** deliberately ignoring wide-window creeps shows `MISSED_EASY`, and the 5:00 checkpoint names the leak.
- [ ] **Self-test:** the bot scores at least 85% `PERFECT` + `OK` and under 5% `MISSED_EASY` (`!trainer stats selftest`).
- [ ] **`!trainer stats` and the auto summaries print.** `!trainer off` removes all drawing and text.
- [ ] **Draws with Debug off:** with `Debug = false`, trainer draws appear and HDebug's columns don't.
- [ ] **Draws with Debug on:** with `Debug = true`, the trainer text doesn't overlap HDebug's columns.
- [ ] **Frame cost:** with 2 bars and 2 watched creeps (spike item 7), no visible FPS drop at `host_timescale 1`. If it's noticeable, lower `MaxWatched` or raise `WatchInterval` (keep `BAR_STICKINESS` at or above `WatchInterval`), and record the values here: _?_
- [ ] **Counter timing:** last hits read `PERFECT`/`OK`, not all `LATE`. If everything is `LATE`, `GetLastHits`/`GetDenies` update after the death frame and `creepObservations` needs a death hold (R12).
- [ ] **Attack reads:** `GetLastAttackTime` is the attack start (not projectile release); `ACTIVITY_ATTACK2` counts as an attack; `GetAnimCycle`/`GetAttackPoint`/`GetAttackSpeed` units give a sensible swing start; cached creep handles stay valid and `IsAlive()` doesn't error.
- [ ] **Regression:** with `Trainer.LastHit.Enable = false`, no `[H:trainer]` lines, no trainer chat and no draws.

## Known risks to watch
- **Laning:** every allied bot on a team with a human uses OHA's laning `Think()` for the whole game, never Valve's (task 04). If laning gets worse, fall back to option B in the 04 handoff.
- **Channel delay:** delaying enemy `IsChanneling` affects every OHA use of it, not just interrupts. `Perception.Channel = false` disables only that part.
- **Commitment:** orders cap retreat while HP is above 50%, so bots may die more on orders. Ordered pushes also skip OHA's "never push alone" checks.
- **Avoidance zones:** they may only affect pathing via `GeneratePath`, not `Action_MoveToLocation`.
- **FretBots bridge option A** (`FretBridge.BridgeModifier`) is untested and off by default. Try it only after the chat mirror proves unreliable.
- **Leftover probe:** remove `SharedStateProbe` once the session 1 result is recorded.
